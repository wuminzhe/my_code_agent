# frozen_string_literal: true

require "ruby_llm"
require "set"
require_relative "tools/read_file"
require_relative "tools/write_file"
require_relative "tools/edit_file"
require_relative "tools/exec_shell"
require_relative "tools/load_skill"
require_relative "extension"
require_relative "skill_loader"

module CodeAgent
  # Core agent loop — wraps RubyLLM::Chat with tool registration,
  # streaming output, and turn management.
  class AgentLoop
    attr_reader :chat, :turn_count, :extensions, :skills

    class << self
      # Current active agent loop (for tools to find skills)
      attr_accessor :current
    end

    def initialize(config = CodeAgent.config)
      self.class.current = self
      @config = config
      @chat = nil          # lazy init on first send_message
      @tools = {}
      @turn_count = 0
      @extensions = []      # loaded Extension instances
      @skills = {}          # name => { prompt:, description: }
    end

    # Load extensions from user and project directories (Ruby files only).
    def load_extensions!
      @extensions = Extension.load_all(@config.workspace)
      @extensions.each { |ext| ext.run_load_hooks(self) }
      self
    end

    # Load skills from multiple sources:
    # 1. Extension-defined skills (skill DSL in Ruby extensions)
    # 2. File-based skills (SKILL.md in .code_agent/skills/)
    def load_skills!
      # Extension skills
      @extensions.each do |ext|
        next unless ext.respond_to?(:get_skill)
        ext.instance_variable_get(:@skills).each do |name, skill_def|
          @skills[name] ||= {
            prompt: skill_def[:prompt],
            description: ext.description || "Skill from extension"
          }
        end
      end

      # File-based skills (SKILL.md)
      SkillLoader.load_all(@config.workspace).each do |skill|
        @skills[skill.name] ||= {
          prompt: skill.prompt,
          description: skill.description
        }
      end

      self
    end

    # Lazily build the chat (deferred so REPL can start without API key)
    def chat
      return @chat if @chat

      c = build_chat
      @chat = c                     # set BEFORE registering tools to avoid recursion
      register_default_tools
      register_extension_tools
      c
    end

    # Register a tool instance (RubyLLM::Tool subclass).
    # Always tracks the tool in @tools for prompt construction.
    # Only registers with the RubyLLM chat if chat is already initialized.
    def register_tool(tool)
      @tools[tool.name] = tool
      chat.with_tool(tool) if @chat
      self
    end

    # Send a user message and stream the response
    # Yields chunks of the form: { type: :text, content: "..." } or
    # { type: :tool_call, name: "...", args: {...} } or
    # { type: :tool_result, name: "...", result: {...} }
    def send_message(message, &block)
      @turn_count += 1

      if block
        stream_with_hooks(message, &block)
      else
        response = chat.ask(message)
        format_response(response)
      end
    end

    # Reset the conversation
    def reset!
      chat.reset_messages!
      @turn_count = 0
    end

    # Get conversation history
    def history
      chat.messages.map do |msg|
        {
          role: msg.role,
          content: msg.content.to_s[0..200],
          tool_call: msg.tool_call_id ? true : false
        }
      end
    end

    # Public for extension inspection
    def assemble_system_prompt
      parts = [build_context_header, @config.system_prompt]

      # Inject project context files (AGENTS.md / CLAUDE.md)
      context_files = load_context_files
      unless context_files.empty?
        ctx_section = context_files.map { |f| "## #{f[:path]}\n\n#{f[:content]}" }.join("\n\n")
        parts << ctx_section
      end

      # Inject skill catalog (available skills from extensions)
      skill_catalog = format_skill_catalog
      parts << skill_catalog unless skill_catalog.empty?

      @extensions.each do |ext|
        fragment = ext.build_system_prompt_fragment
        parts << fragment unless fragment.empty?
      end

      parts.compact.join("\n\n")
    end

    # Collect all loaded skills. Returns a hash keyed by skill name.
    def collect_skills
      @skills
    end

    # Find a skill by name
    def find_skill(name)
      @skills[name]
    end

    # Format skills as a catalog for the system prompt.
    def format_skill_catalog
      return "" if @skills.empty?

      lines = []
      lines << "Available skills (use the load_skill tool to activate):"
      @skills.each do |name, defn|
        desc = defn[:prompt] ? defn[:prompt].to_s.lines.first.to_s.strip[0..100] : "(no description)"
        lines << "  - #{name}: #{desc}"
      end
      lines.join("\n")
    end

    private

    # Build a dynamic context header injected at the top of the system prompt.
    # Includes date, working directory, git branch, platform, and active tools
    # with one-line descriptions.
    def build_context_header
      lines = []
      lines << "Current date: #{Time.now.strftime('%Y-%m-%d')}"
      lines << "Working directory: #{@config.workspace}"
      lines << "Platform: #{RUBY_PLATFORM}"

      # Git branch (best-effort)
      branch = git_branch
      lines << "Git branch: #{branch}" if branch

      # Active tools with one-line descriptions
      unless @tools.empty?
        lines << ""
        lines << "Available tools:"
        @tools.sort_by { |name, _| name }.each do |name, tool|
          snippet = tool_snippet(name, tool)
          lines << "  - #{name}: #{snippet}" if snippet
        end
      end

      lines.join("\n")
    end

    # One-line tool description for the context header
    def tool_snippet(name, tool)
      case name
      when "read_file"
        "Read file contents with optional line range"
      when "write_file"
        "Create or overwrite a file"
      when "edit_file"
        "Search-and-replace edit in a file (exact match required)"
      when "exec_shell"
        "Run a shell command in the workspace"
      when "load_skill"
        "Load instructions for a named skill"
      else
        tool.description.to_s.lines.first.to_s.strip[0..100]
      end
    end

    # Best-effort git branch detection
    def git_branch
      Dir.chdir(@config.workspace) do
        head = File.read(".git/HEAD").strip rescue nil
        return nil unless head
        head.sub(%r{^ref: refs/heads/}, "")
      end
    rescue StandardError
      nil
    end

    # Discover project context files (AGENTS.md / CLAUDE.md).
    # Walks from workspace root up to filesystem root, collecting context files
    # from each ancestor directory. Also checks user-level ~/.code_agent/.
    # Deduplicates by path, preferring project-level over user-level.
    CONTEXT_FILE_NAMES = %w[AGENTS.md CLAUDE.md].freeze

    def load_context_files
      return [] unless @config.context_files_enabled?

      seen = Set.new
      files = []

      # Walk up from workspace to root
      dir = File.expand_path(@config.workspace)
      root = File.expand_path("/")

      while dir != root
        CONTEXT_FILE_NAMES.each do |name|
          path = File.join(dir, name)
          next unless File.file?(path)
          next if seen.include?(File.expand_path(path))

          content = File.read(path) rescue nil
          next unless content && !content.strip.empty?

          seen << File.expand_path(path)
          files << { path: path, content: content.strip }
        end
        dir = File.expand_path("..", dir)
      end

      files.reverse # nearest ancestor first
    end

    private

    def build_chat
      configure_provider  # MUST be before RubyLLM.chat — provider init happens there
      RubyLLM.chat(model: @config.model).tap do |c|
        inject_system_prompt(c)
      end
    end

    def inject_system_prompt(chat_instance)
      prompt = assemble_system_prompt
      return if prompt.nil? || prompt.empty?

      has_system = chat_instance.messages.any? { |m| m.role == :system }
      return if has_system

      chat_instance.add_message(role: :system, content: prompt)
    end

    def register_extension_tools
      @extensions.each do |ext|
        ext.tool_instances.each { |tool| register_tool(tool) }
      end
    end

    def configure_provider
      key = @config.api_key
      return unless key

      case @config.provider
      when "deepseek"
        RubyLLM.configure { |c| c.deepseek_api_key = key }
      when "openai"
        RubyLLM.configure { |c| c.openai_api_key = key }
      when "anthropic"
        RubyLLM.configure { |c| c.anthropic_api_key = key }
      when "google"
        RubyLLM.configure { |c| c.gemini_api_key = key }
      end
    rescue StandardError => e
      # May already be configured from a previous call; ignore
    end

    def register_default_tools
      tool_config = @config.tools

      if tool_config.dig("read_file", "enabled")
        register_tool(Tools::ReadFile.new)
      end

      if tool_config.dig("write_file", "enabled")
        register_tool(Tools::WriteFile.new)
      end

      if tool_config.dig("edit_file", "enabled")
        register_tool(Tools::EditFile.new)
      end

      if tool_config.dig("exec_shell", "enabled")
        register_tool(Tools::ExecShell.new)
      end

      if tool_config.dig("load_skill", "enabled")
        register_tool(Tools::LoadSkill.new)
      end
    end

    def stream_with_hooks(message, &block)
      # Hook: before tool call — yield tool_call info
      chat.before_tool_call do |tool_call|
        yield type: :tool_call, name: tool_call.name, args: tool_call.arguments
      end

      # Hook: after tool result — yield tool_result
      chat.after_tool_result do |result|
        result_str = result.is_a?(Hash) ? result : result.to_s
        yield type: :tool_result, name: "tool", result: result_str[0..1000]
      end

      # Stream the actual response
      full_response = ""
      chat.ask(message) do |chunk|
        # RubyLLM 1.15 uses RubyLLM::Chunk for streaming
        if chunk.respond_to?(:content) && chunk.content
          text = chunk.content.to_s
          full_response += text
          yield type: :text, content: text
        end
      end

      { type: :complete, content: full_response }
    end

    def format_response(response)
      if response.tool_call?
        { type: :tool_calls, calls: response.tool_calls.map { |_, tc| { name: tc.name, args: tc.arguments } } }
      else
        { type: :text, content: response.content.to_s }
      end
    end
  end
end
