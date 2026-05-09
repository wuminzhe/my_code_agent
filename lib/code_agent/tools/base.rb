# frozen_string_literal: true

require "ruby_llm"

module CodeAgent
  module Tools
    # Base class for all coding agent tools.
    # Inherits RubyLLM::Tool for automatic schema inference from #execute signature.
    # Our tools use keyword arguments; RubyLLM infers the JSON Schema from them.
    #
    # Hook integration: we override RubyLLM::Tool#call (the entry point for
    # tool execution) so extension on_tool_call / on_tool_result hooks fire
    # around every tool call, while the original #execute signature is left
    # untouched for schema inference.
    class Base < RubyLLM::Tool
      # ── Tool lifecycle hooks ─────────────────────────────────────────

      # Override RubyLLM::Tool#call (signature: def call(args)).
      # Schema inference reads #execute so overriding #call does NOT affect
      # the JSON Schema sent to the LLM.
      def call(args)
        # Normalize string keys → symbols (same as RubyLLM does before execute)
        params = args.is_a?(Hash) ? args.transform_keys(&:to_sym) : {}

        # 1. Run on_tool_call hooks before execution.
        blocked = CodeAgent::Extension.run_tool_call_hooks(name, params)
        if blocked
          return { error: "Blocked by extension: #{blocked[:reason]}" }
        end

        # 2. Execute the tool (RubyLLM validates, then calls #execute).
        result = super(args)

        # 3. Run on_tool_result hooks — each can modify the result.
        CodeAgent::Extension.run_tool_result_hooks(name, params, result)
      end

      # Override to produce clean names like "read_file" instead of
      # "code_agent--tools--read_file"
      def name
        # Use the last segment of the class name, snake_cased.
        # Anonymous classes (Class.new) have nil name — fall back to object_id.
        raw = self.class.name || "anonymous_tool_#{object_id}"
        class_name = raw.split("::").last
        class_name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      # Shortcut to create a halt (stops the agent loop after execution)
      def halt(message)
        RubyLLM::Tool::Halt.new(message)
      end
    end
  end
end
