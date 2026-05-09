# frozen_string_literal: true

require_relative "base"

module CodeAgent
  module Tools
    # Reads a file from the workspace and returns its content.
    class ReadFile < Base
      description <<~DESC.strip
        Read the contents of a file in the project workspace.
        Use this before editing files to understand the current state.
        Returns the file content with line numbers.
      DESC

      def execute(path:,
                  start_line: nil,
                  end_line: nil)
        full_path = resolve_path(path)

        unless File.exist?(full_path)
          return { error: "File not found: #{path}" }
        end

        unless File.file?(full_path)
          return { error: "Not a file: #{path}" }
        end

        lines = File.readlines(full_path, chomp: true)
        total = lines.size

        # Apply line range
        start = [start_line.to_i, 1].max if start_line
        finish = [end_line.to_i, total].min if end_line

        if start && finish
          lines = lines[(start - 1)..(finish - 1)] || []
          lines.each_with_index.map { |l, i| "#{(start + i).to_s.rjust(4)}| #{l}" }.join("\n")
        elsif start
          lines = lines[(start - 1)..] || []
          lines.each_with_index.map { |l, i| "#{(start + i).to_s.rjust(4)}| #{l}" }.join("\n")
        else
          max_lines = CodeAgent.config.tools.dig("read_file", "max_lines") || 500
          if total > max_lines
            truncated = lines.first(max_lines)
            output = truncated.each_with_index.map { |l, i| "#{(i + 1).to_s.rjust(4)}| #{l}" }.join("\n")
            "#{output}\n\n[Truncated: #{total} lines total, showing first #{max_lines}]"
          else
            lines.each_with_index.map { |l, i| "#{(i + 1).to_s.rjust(4)}| #{l}" }.join("\n")
          end
        end
      end

      private

      def resolve_path(path)
        ws = CodeAgent.config.workspace
        File.expand_path(path, ws)
      end
    end
  end
end
