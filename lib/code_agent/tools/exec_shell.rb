# frozen_string_literal: true

require_relative "base"
require "open3"

module CodeAgent
  module Tools
    # Runs a shell command in the workspace and returns stdout/stderr/exit code.
    class ExecShell < Base
      description <<~DESC.strip
        Execute a shell command in the project workspace.
        Returns stdout, stderr, and exit code.
        Commands have a timeout (default 120s).
        Use this for running tests, builds, git commands, or inspecting the project.
        Avoid destructive commands (rm -rf, force push, etc.) unless the user
        explicitly asks for them.
      DESC

      def execute(command:, timeout_sec: nil)
        timeout = timeout_sec || tool_config["timeout_sec"] || 120
        allowed = tool_config["allow_commands"] || []

        # Optional command whitelist
        unless allowed.empty?
          cmd_name = command.split.first
          unless allowed.include?(cmd_name)
            return { error: "Command '#{cmd_name}' not in allowlist: #{allowed.join(', ')}" }
          end
        end

        cwd = CodeAgent.config.workspace

        stdout, stderr, status = nil

        begin
          Timeout.timeout(timeout.to_i) do
            stdout, stderr, status = Open3.capture3(command, chdir: cwd)
          end
        rescue Timeout::Error
          return { error: "Command timed out after #{timeout}s: #{command}" }
        end

        {
          stdout: stdout,
          stderr: stderr,
          exit_code: status.exitstatus,
          success: status.success?
        }
      end

      private

      def tool_config
        CodeAgent.config.tools["exec_shell"] || {}
      end
    end
  end
end
