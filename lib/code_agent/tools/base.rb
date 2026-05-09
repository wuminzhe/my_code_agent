# frozen_string_literal: true

require "ruby_llm"

module CodeAgent
  module Tools
    # Base class for all coding agent tools.
    # Inherits RubyLLM::Tool for automatic schema inference from #execute signature.
    # Our tools use keyword arguments; RubyLLM infers the JSON Schema from them.
    class Base < RubyLLM::Tool
      # Override to produce clean names like "read_file" instead of
      # "code_agent--tools--read_file"
      def name
        # Use the last segment of the class name, snake_cased
        class_name = self.class.name.split("::").last
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
