# frozen_string_literal: true

require_relative "base"

module CodeAgent
  module Tools
    # Edits a file using search-and-replace (like sed, but safer).
    # Takes old_string (exact match) and new_string, replaces the first occurrence.
    class EditFile < Base
      description <<~DESC.strip
        Edit a file by replacing one exact string with another.
        The old_string must match exactly (including whitespace) and uniquely
        within the file. If the match appears multiple times, the edit is
        rejected — the LLM should provide more surrounding context to make
        it unique. For creating new files or rewriting entire files, use the
        write_file tool instead.

        Always read the file first to get the exact content to replace.
      DESC

      def execute(path:, old_string:, new_string:)
        full_path = resolve_path(path)

        unless File.exist?(full_path)
          return { error: "File not found: #{path}" }
        end

        unless File.file?(full_path)
          return { error: "Not a file: #{path}" }
        end

        content = File.read(full_path)

        # Count occurrences — scan with String does literal matching (no regex escaping needed)
        count = content.scan(old_string).size
        if count.zero?
          return { error: "old_string not found in #{path}. Read the file first to get the exact content." }
        elsif count > 1
          return {
            error: "old_string matches #{count} locations in #{path}. " \
                   "Provide more surrounding context to make it unique."
          }
        end

        # Perform the replacement — sub with String does literal match
        new_content = content.sub(old_string, new_string)
        File.write(full_path, new_content)

        { success: true, path: path, replacements: 1 }
      rescue StandardError => e
        { error: "Failed to edit #{path}: #{e.message}" }
      end

      private

      def resolve_path(path)
        ws = CodeAgent.config.workspace
        File.expand_path(path, ws)
      end
    end
  end
end
