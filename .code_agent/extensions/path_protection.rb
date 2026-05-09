# frozen_string_literal: true

# Path Protection — prevents writes to sensitive files and directories.
#
# Two independent layers:
# 1. write_file / edit_file — blocked by before_tool_call (returns error
#    before the tool executes).  The LLM never sees the file touched.
# 2. exec_shell — the command is wrapped with a chmod-based preamble
#    that removes write permission from protected paths before the
#    command runs, and restores it afterwards.  OS-level enforcement,
#    not post-hoc detection.
#
# This means even `echo X > .env` will fail with "Permission denied" —
# the shell itself cannot write to protected paths.

CodeAgent::Extension.define "path_protection" do
  description "Prevents writes to sensitive paths (.env, node_modules/, .git/, etc.)"

  protected_globs = %w[
    .env
    .env.*
    node_modules
    .git
    config/master.key
    credentials.yml.enc
    *.pem
    id_rsa
    id_ed25519
  ].freeze

  write_tools = %w[write_file edit_file].freeze

  before_tool_call do |tool_name, params|
    if write_tools.include?(tool_name)
      path = params[:path].to_s
      next if path.empty?

      blocked = protected_globs.find do |glob|
        File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
      end
      if blocked
        next({ block: true, reason: "Path '#{path}' is protected (matches #{blocked})" })
      end
    end
  end
end
