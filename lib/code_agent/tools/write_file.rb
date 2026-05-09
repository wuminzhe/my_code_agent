# frozen_string_literal: true

require_relative "base"

module CodeAgent
  module Tools
    # Writes content to a file (creates or overwrites).
    class WriteFile < Base
      description <<~DESC.strip
        Write content to a file in the project workspace.
        Creates the file if it doesn't exist; overwrites if it does.
        Use this for creating new files or full-file rewrites.
        For targeted edits, use the edit_file tool instead.
      DESC

      def execute(path:, content:)
        full_path = resolve_path(path)

        # Ensure parent directory exists
        dir = File.dirname(full_path)
        FileUtils.mkdir_p(dir)

        # Write the file
        File.write(full_path, content)

        size = File.size(full_path)
        lines = content.lines.count
        { success: true, path: path, bytes: size, lines: lines }
      rescue StandardError => e
        { error: "Failed to write #{path}: #{e.message}" }
      end

      private

      def resolve_path(path)
        ws = CodeAgent.config.workspace
        File.expand_path(path, ws)
      end
    end
  end
end
