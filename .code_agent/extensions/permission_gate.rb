# frozen_string_literal: true

# Permission Gate — blocks dangerous shell commands.
#
# Intercepts exec_shell tool calls and denies known-dangerous patterns
# such as rm -rf, sudo, chmod 777, force push, dd, and mkfs.
#
# The LLM sees a clear "Blocked by extension" error and can explain
# to the user why the command was blocked. The user can then run
# the command manually if they truly intend it.

CodeAgent::Extension.define "permission_gate" do
  description "Blocks dangerous shell commands (rm -rf, sudo, chmod 777, etc.)"

  dangerous = [
    { pattern: /\brm\s+-rf?\b/,    reason: "rm -rf is destructive" },
    { pattern: /\bsudo\b/,          reason: "sudo requires explicit user permission" },
    { pattern: /\bchmod\s+777\b/,   reason: "chmod 777 is a security risk" },
    { pattern: /\bgit\s+push\s+.*--force/, reason: "force push rewrites remote history" },
    { pattern: /\bgit\s+push\s+.*--delete/, reason: "branch deletion requires confirmation" },
    { pattern: /\bdd\s+if=/,        reason: "dd can overwrite disks" },
    { pattern: /\bmkfs\./,          reason: "mkfs formats filesystems" },
    { pattern: /\b:>\s*\/dev\//,    reason: "writing directly to /dev/ is dangerous" },
    { pattern: /\biptables\s+-F\b/, reason: "flushing iptables can break networking" },
    { pattern: /\bshutdown\b/,      reason: "shutdown requires explicit user approval" },
  ].freeze

  before_tool_call do |tool_name, params|
    next unless tool_name == "exec_shell"

    command = params[:command].to_s
    matched = dangerous.find { |entry| command.match?(entry[:pattern]) }
    if matched
      { block: true, reason: "#{matched[:reason]}: #{command[0..80]}" }
    end
  end
end
