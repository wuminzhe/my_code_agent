# frozen_string_literal: true

require "tty-prompt"
require "tty-reader"
require "pastel"
require_relative "agent_loop"
require_relative "session_manager"

module CodeAgent
  # Interactive REPL for the coding agent.
  # Provides multi-line input, streaming AI responses, and slash commands.
  class REPL
    COMMANDS = {
      "/quit"       => "Exit the agent",
      "/clear"      => "Clear conversation history",
      "/save"       => "Save session (usage: /save <name>)",
      "/load"       => "Load session (usage: /load <name>)",
      "/sessions"   => "List saved sessions",
      "/delete"     => "Delete a session (usage: /delete <name>)",
      "/model"      => "Show current model info",
      "/tools"      => "List registered tools",
      "/extensions" => "List loaded extensions",
      "/hooks"      => "List active tool hooks (on_tool_call / on_tool_result)",
      "/skills"     => "List available skills",
      "/skill"      => "Load a skill (usage: /skill <name>)",
      "/compact"    => "Compact conversation context",
      "/help"       => "Show this help"
    }.freeze

    def initialize(config = CodeAgent.config)
      @config = config
      @pastel = Pastel.new
      @prompt = TTY::Prompt.new(interrupt: -> { handle_interrupt })
      @agent = AgentLoop.new(config)
      @agent.load_extensions!
      @agent.load_skills!
      @sessions = SessionManager.new
      @session_auto_save = config.data.dig("session", "auto_save") || false
      @ctrl_c_at = nil   # timestamp of last Ctrl+C for double-tap detection
    end

    def start
      print_banner
      repl_loop
    end

    private

    def print_banner
      puts @pastel.cyan("╭────────────────────────────────────────╮")
      puts @pastel.cyan("│") + @pastel.bright_white("  CodeAgent v#{CodeAgent::VERSION}") +
           @pastel.cyan("                     │")
      puts @pastel.cyan("│") + "  Provider: #{@config.provider.ljust(12)} Model: #{@config.model.ljust(16)}" +
           @pastel.cyan("│")
      puts @pastel.cyan("│") + "  Workspace: #{@config.workspace.to_s[0..30].ljust(31)}" +
           @pastel.cyan("│")
      puts @pastel.cyan("╰────────────────────────────────────────╯")

      # API key status
      if @config.api_key
        masked = @config.api_key[0..5] + "..." + @config.api_key[-4..]
        puts "  API key:   #{@pastel.green('set')} (#{masked})"
      else
        puts "  API key:   #{@pastel.red('NOT SET')}"
        puts "    → export #{@config.env_key}=\"sk-...\""
        puts "    → or add to ~/.code_agent/config.yml"
      end

      # Extensions
      ext_count = @agent.extensions.size
      if ext_count > 0
        names = @agent.extensions.map(&:name).join(", ")
        puts "  Extensions: #{@pastel.green(ext_count.to_s)} loaded (#{names})"
      end
      puts
      puts "  Type #{@pastel.bright_white('/help')} for commands, #{@pastel.bright_white('/quit')} to exit."
      puts "  Enter your request below. Use #{@pastel.bright_white('\\')} at end of line to continue."
      puts
    end

    def repl_loop
      loop do
        input = read_input
        break if input.nil?

        input = input.strip
        next if input.empty?

        if input.start_with?("/")
          handled = handle_command(input)
          break if handled == :quit
          next
        end

        process_message(input)
      end
    rescue Interrupt
      # Ctrl+C during message processing — treat same as input interrupt
      return handle_interrupt
    ensure
      puts
    end

    def read_input
      print @pastel.green("▸ ")
      input = +""

      while (line = $stdin.gets)
        if line.end_with?("\\\n")
          input << line.sub(/\\\n$/, "\n")
          @ctrl_c_at = nil  # reset double-tap on successful input
          print @pastel.green("▎ ")
        else
          input << line
          @ctrl_c_at = nil
          break
        end
      end

      input.empty? ? nil : input
    rescue Interrupt
      # Double-tap Ctrl+C to exit
      now = Time.now
      if @ctrl_c_at && (now - @ctrl_c_at) < 1.0
        puts @pastel.yellow("  Goodbye!")
        return nil
      end

      @ctrl_c_at = now
      puts
      puts @pastel.dim("  (Ctrl+C again to exit)")
      # Return empty string so repl_loop skips this round and re-prompts
      ""
    end

    def handle_command(cmd)
      parts = cmd.split(/\s+/, 2)
      command = parts[0]
      argument = parts[1]

      case command
      when "/quit", "/q", "/exit"
        puts @pastel.yellow("Goodbye!")
        return :quit
      when "/clear"
        @agent.reset!
        puts @pastel.green("✓ Conversation cleared.")
      when "/save"
        save_session(argument)
      when "/load"
        load_session(argument)
      when "/sessions"
        list_sessions
      when "/delete"
        delete_session(argument)
      when "/model"
        puts "  Provider: #{@config.provider}"
        puts "  Model:    #{@config.model}"
        puts "  API key:  #{@config.api_key ? 'set' : 'not set (check env)'}"
      when "/compact"
        compact_context
      when "/tools"
        @agent.chat rescue nil  # force lazy init so tools are registered
        tools = @agent.instance_variable_get(:@tools)
        if tools.empty?
          puts "  No tools registered."
        else
          tools.each do |name, tool|
            desc = tool.description.lines.first.to_s.strip
            puts "  #{@pastel.bright_white(name)} — #{desc}"
          end
        end
      when "/skills"
        skills = @agent.collect_skills
        if skills.empty?
          puts "  No skills available."
          puts "  Define skills in extensions or add SKILL.md files to .code_agent/skills/"
        else
          skills.each do |name, defn|
            desc = defn[:description] || defn[:prompt].to_s.lines.first.to_s.strip[0..80]
            puts "  #{@pastel.bright_white(name)} — #{desc}"
          end
        end
      when "/skill"
        unless argument
          puts @pastel.red("  Usage: /skill <name>")
          return nil
        end
        skill = @agent.find_skill(argument.strip)
        unless skill
          puts @pastel.red("  Skill not found: #{argument.strip}")
          puts @pastel.dim("  Use /skills to list available skills.")
          return nil
        end
        prompt = skill[:prompt].to_s
        puts
        puts @pastel.bright_white("  Skill: #{argument.strip}")
        puts @pastel.dim("  ─" * 30)
        prompt.each_line { |l| puts "  #{l.chomp}" }
        puts @pastel.dim("  ─" * 30)
        puts
        puts @pastel.dim("  Injecting skill as user message...")
        process_message(prompt)
      when "/extensions"
        if @agent.extensions.empty?
          puts "  No extensions loaded."
          puts "  Add .rb files to ~/.code_agent/extensions/ or .code_agent/extensions/"
        else
          @agent.extensions.each do |ext|
            tool_count = ext.instance_variable_get(:@tool_classes).size
            skill_count = ext.instance_variable_get(:@skills).size
            hook_counts = ext.hook_counts
            info = []
            info << "#{tool_count} tools" if tool_count > 0
            info << "#{skill_count} skills" if skill_count > 0
            info << "#{hook_counts[:tool_call]} on_tool_call, #{hook_counts[:tool_result]} on_tool_result" if hook_counts.values.sum > 0
            puts "  #{@pastel.bright_white(ext.name)} — #{ext.description}"
            puts "    #{info.join(', ')}" unless info.empty?
          end
        end
      when "/hooks"
        summary = CodeAgent::Extension.hook_summary
        if summary[:total] == 0
          puts "  No tool hooks active."
          puts "  Use on_tool_call / on_tool_result in extension files to add hooks."
        else
          puts "  Active tool hooks:"
          puts "    on_tool_call:  #{summary[:tool_call]}"
          puts "    on_tool_result: #{summary[:tool_result]}"
          puts
          puts "  Hooks by extension:"
          @agent.extensions.each do |ext|
            hc = ext.hook_counts
            next if hc.values.sum == 0
            parts = []
            parts << "#{hc[:tool_call]} on_tool_call" if hc[:tool_call] > 0
            parts << "#{hc[:tool_result]} on_tool_result" if hc[:tool_result] > 0
            puts "    #{@pastel.bright_white(ext.name)} — #{parts.join(', ')}"
          end
        end
      when "/help"
        puts
        COMMANDS.each do |cmd, desc|
          puts "  #{@pastel.bright_white(cmd.ljust(12))} #{desc}"
        end
        puts
        puts "  Multi-line: end a line with \\ to continue on the next line."
        puts "  Ctrl+C:     clear input (double-tap to exit)."
        puts
      else
        puts @pastel.red("Unknown command: #{cmd}. Type /help for options.")
      end

      nil
    end

    def process_message(message)
      puts

      @agent.send_message(message) do |chunk|
        case chunk[:type]
        when :tool_call
          puts @pastel.yellow("  🔧 #{chunk[:name]}(#{chunk[:args].to_s[0..80]})")
        when :tool_result
          # Tool results can be verbose; show first line only
          result_preview = chunk[:result].to_s.lines.first.to_s.strip[0..100]
          puts @pastel.dim("     ← #{result_preview}")
        when :text
          $stdout.print chunk[:content]
          $stdout.flush
        when :complete
          # done
        end
      end

      puts
      puts
    rescue RubyLLM::ConfigurationError => e
      puts @pastel.red("  ✗ Configuration error: #{e.message}")
      puts @pastel.red("    Set #{@config.env_key} environment variable or configure in ~/.code_agent/config.yml")
    rescue StandardError => e
      puts @pastel.red("  ✗ Error: #{e.message}")
    end

    def save_session(name)
      if name.nil? || name.strip.empty?
        puts @pastel.red("  Usage: /save <name>")
        return
      end

      begin
        # Force chat initialization so we have messages to save
        @agent.chat
        path = @sessions.save(name.strip, @agent)
        puts @pastel.green("  ✓ Session saved: #{name.strip}")
        puts @pastel.dim("    #{path}")
      rescue RubyLLM::ConfigurationError => e
        puts @pastel.red("  ✗ Cannot save: #{e.message}")
      rescue StandardError => e
        puts @pastel.red("  ✗ Save failed: #{e.message}")
      end
    end

    def load_session(name)
      if name.nil? || name.strip.empty?
        puts @pastel.red("  Usage: /load <name>")
        return
      end

      begin
        success = @sessions.replay_into(@agent, name.strip)
        if success
          puts @pastel.green("  ✓ Session loaded: #{name.strip}") +
               @pastel.dim(" (#{@agent.chat.messages.size} messages)")
          display_history
        else
          puts @pastel.red("  ✗ Session not found: #{name.strip}")
        end
      rescue RubyLLM::ConfigurationError => e
        puts @pastel.red("  ✗ Cannot load: #{e.message}")
      rescue StandardError => e
        puts @pastel.red("  ✗ Load failed: #{e.message}")
      end
    end

    def display_history
      messages = @agent.chat.messages
      return if messages.empty?

      puts
      messages.each do |msg|
        role = msg.role.to_s
        content = msg.content.to_s.strip

        case role
        when "system"
          # Skip system prompt — it's internal
          next
        when "user"
          puts @pastel.green("  ▸ #{content}")
        when "assistant"
          # Check if this was a tool-call message
          if msg.respond_to?(:tool_calls) && msg.tool_calls&.any?
            msg.tool_calls.each_value do |tc|
              args_preview = tc.arguments.to_s[0..60]
              puts @pastel.yellow("    🔧 #{tc.name}(#{args_preview})")
            end
          elsif !content.empty?
            # Wrap long responses
            content.each_line do |line|
              puts "    #{line.chomp}"
            end
          end
        when "tool"
          first_line = content.lines.first.to_s.strip[0..100]
          puts @pastel.dim("      ← #{first_line}")
        end
      end
      puts
    end

    def list_sessions
      sessions = @sessions.list
      if sessions.empty?
        puts "  No saved sessions."
        puts "  Sessions are stored in ~/.code_agent/sessions/"
      else
        puts "  Saved sessions:"
        sessions.each do |name|
          marker = name == @sessions.current_name ? " *" : "  "
          begin
            data = @sessions.load(name)
            meta = data[:metadata]
            turn_info = "#{meta[:turn_count]} turns" rescue "?"
            puts "  #{@pastel.bright_white(marker + name)} (#{turn_info}, #{meta[:model] || '?'})"
          rescue StandardError
            puts "  #{marker + name}"
          end
        end
        puts "  #{@pastel.dim('* = currently loaded')}" if @sessions.current_name
      end
    end

    def delete_session(name)
      if name.nil? || name.strip.empty?
        puts @pastel.red("  Usage: /delete <name>")
        return
      end

      unless @sessions.list.include?(name.strip)
        puts @pastel.red("  ✗ Session not found: #{name.strip}")
        return
      end

      @sessions.delete(name.strip)
      puts @pastel.green("  ✓ Session deleted: #{name.strip}")
    end

    def compact_context
      puts @pastel.yellow("  Compacting context...")

      begin
        messages = @agent.chat.messages
        if messages.size < 6
          puts "  Not enough messages to compact (need more than 6)."
          return
        end

        # Use the LLM to summarize the conversation so far
        summary_prompt = <<~PROMPT
          Summarize the conversation so far concisely, preserving:
          1. The user's original goal or request
          2. Key decisions made
          3. Files that were modified and what changed
          4. Current state / what remains to be done

          Keep the summary under 500 words.
        PROMPT

        # Create a temporary chat to generate the summary
        temp_chat = RubyLLM.chat(model: @agent.instance_variable_get(:@config).model)
        temp_chat.add_message(role: :user, content: summary_prompt)

        # Feed the conversation history
        messages[1..-2]&.each do |msg|
          role = msg.role.to_s
          next if role == "tool" || role == "system"
          temp_chat.add_message(role: role.to_sym, content: msg.content.to_s[0..2000])
        end

        response = temp_chat.ask("Please provide the summary.")
        summary = response.content.to_s

        # Replace all old messages with the summary
        @agent.reset!
        @agent.chat.add_message(role: :system, content: @agent.assemble_system_prompt)
        @agent.chat.add_message(role: :user, content: "[Conversation summary]\n\n#{summary}\n\nContinue from here.")

        puts @pastel.green("  ✓ Context compacted. Summary: #{summary.lines.count} lines.")
      rescue RubyLLM::ConfigurationError => e
        puts @pastel.red("  ✗ Compaction failed: #{e.message}")
      rescue StandardError => e
        puts @pastel.red("  ✗ Compaction error: #{e.message}")
      end
    end

    def handle_interrupt
      puts
      @ctrl_c_at = nil
      puts @pastel.dim("  Interrupted. Continue typing, or Ctrl+C twice to exit.")
    end
  end
end