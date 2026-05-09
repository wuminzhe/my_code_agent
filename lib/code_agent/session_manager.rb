# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module CodeAgent
  # Session persistence — saves/loads conversation history to JSON files.
  #
  # Sessions are stored in ~/.code_agent/sessions/<name>.json
  # Each session contains:
  #   - metadata (created_at, updated_at, model, provider)
  #   - messages array (role, content, tool_call_id, tool_calls)
  #   - turn count
  class SessionManager
    SESSIONS_DIR = File.expand_path("~/.code_agent/sessions")

    attr_reader :current_name

    def initialize
      FileUtils.mkdir_p(SESSIONS_DIR)
      @current_name = nil
    end

    # List all saved sessions
    def list
      Dir.glob(File.join(SESSIONS_DIR, "*.json"))
         .map { |f| File.basename(f, ".json") }
         .sort
    end

    # Load a session by name, returns the session data hash
    def load(name)
      path = session_path(name)
      return nil unless File.exist?(path)

      data = JSON.parse(File.read(path), symbolize_names: true)
      @current_name = name
      data
    rescue JSON::ParserError => e
      warn "[CodeAgent] Corrupt session file: #{path} (#{e.message})"
      nil
    end

    # Save the current agent state to a session file
    def save(name, agent_loop, metadata = {})
      path = session_path(name)
      data = build_session_data(agent_loop, metadata)

      File.write(path, JSON.pretty_generate(data))
      @current_name = name
      path
    end

    # Delete a session
    def delete(name)
      path = session_path(name)
      File.delete(path) if File.exist?(path)
      @current_name = nil if @current_name == name
      true
    end

    # Get session path
    def session_path(name)
      File.join(SESSIONS_DIR, "#{sanitize_name(name)}.json")
    end

    # Load messages from a session into an AgentLoop (replay mode)
    def replay_into(agent_loop, name)
      data = load(name)
      return false unless data

      agent_loop.reset!

      # Restore turn count from metadata
      turn_count = data.dig(:metadata, :turn_count) || 0
      agent_loop.instance_variable_set(:@turn_count, turn_count)

      # Replay all non-system messages, preserving tool_call linkage
      messages = data[:messages] || []
      messages.each do |msg|
        next if msg[:role].to_s == "system"  # system prompt is injected fresh

        attrs = { role: msg[:role].to_sym, content: msg[:content] || "" }

        # Preserve tool_call_id for tool result messages
        attrs[:tool_call_id] = msg[:tool_call_id] if msg[:tool_call_id]

        # Reconstruct tool_calls on assistant messages so the LLM
        # sees the tool-use chain when the session is resumed
        if msg[:role].to_s == "assistant" && msg[:tool_calls]&.any?
          tool_calls_hash = {}
          msg[:tool_calls].each do |tc|
            tool_calls_hash[tc[:id]] = RubyLLM::ToolCall.new(
              id: tc[:id],
              name: tc[:name],
              arguments: tc[:arguments] || {}
            )
          end
          attrs[:tool_calls] = tool_calls_hash
        end

        agent_loop.chat.add_message(attrs)
      end

      @current_name = name
      true
    end

    private

    def build_session_data(agent_loop, metadata)
      messages = agent_loop.chat.messages.map do |msg|
        entry = {
          role: msg.role.to_s,
          content: msg.content.to_s
        }
        entry[:tool_call_id] = msg.tool_call_id if msg.respond_to?(:tool_call_id) && msg.tool_call_id
        if msg.respond_to?(:tool_calls) && msg.tool_calls&.any?
          entry[:tool_calls] = msg.tool_calls.values.map { |tc|
            { name: tc.name, id: tc.id, arguments: tc.arguments }
          }
        end
        entry
      end

      {
        metadata: {
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601,
          model: agent_loop.instance_variable_get(:@config).model,
          provider: agent_loop.instance_variable_get(:@config).provider,
          turn_count: agent_loop.turn_count,
          **metadata
        },
        messages: messages
      }
    end

    def sanitize_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")[0..100]
    end
  end
end