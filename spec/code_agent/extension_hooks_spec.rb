# frozen_string_literal: true

RSpec.describe "Extension Hooks" do
  before do
    CodeAgent::Extension.instance_variable_set(:@registry, {})
    CodeAgent::Extension.clear_hooks!
  end

  # ── Hook Registry ───────────────────────────────────────────────────

  describe "Extension hook registry" do
    it "registers and runs before_tool_call hooks" do
      ext = CodeAgent::Extension.define("test_hooks") do
        before_tool_call do |tool_name, params|
          if tool_name == "exec_shell" && params[:command]&.include?("rm")
            { block: true, reason: "no rm allowed" }
          end
        end
      end

      CodeAgent::Extension.register_hooks(ext)

      result = CodeAgent::Extension.run_tool_call_hooks("exec_shell", { command: "rm -rf /" })
      expect(result).to eq({ block: true, reason: "no rm allowed" })

      result = CodeAgent::Extension.run_tool_call_hooks("exec_shell", { command: "ls" })
      expect(result).to be_nil

      result = CodeAgent::Extension.run_tool_call_hooks("read_file", { path: "foo" })
      expect(result).to be_nil
    end

    it "registers and runs after_tool_call hooks" do
      ext = CodeAgent::Extension.define("result_mod") do
        after_tool_call do |_tool_name, _params, result|
          result.merge(annotated: true)
        end
      end

      CodeAgent::Extension.register_hooks(ext)

      original = { stdout: "hello", exit_code: 0 }
      modified = CodeAgent::Extension.run_tool_result_hooks("exec_shell", { command: "ls" }, original)
      expect(modified).to eq({ stdout: "hello", exit_code: 0, annotated: true })
    end

    it "chains multiple hooks in order" do
      order = []

      ext1 = CodeAgent::Extension.define("first") do
        before_tool_call { |n, _| order << "call:#{n}" }
        after_tool_call { |n, _, r| order << "result:#{n}"; r }
      end

      ext2 = CodeAgent::Extension.define("second") do
        before_tool_call { |n, _| order << "call2:#{n}" }
        after_tool_call { |n, _, r| order << "result2:#{n}"; r }
      end

      CodeAgent::Extension.register_hooks(ext1)
      CodeAgent::Extension.register_hooks(ext2)

      CodeAgent::Extension.run_tool_call_hooks("write_file", { path: "x" })
      CodeAgent::Extension.run_tool_result_hooks("write_file", { path: "x" }, { ok: true })

      expect(order).to eq(["call:write_file", "call2:write_file", "result:write_file", "result2:write_file"])
    end

    it "first blocking hook wins" do
      CodeAgent::Extension.define("block_first") do
        before_tool_call { |_, _| { block: true, reason: "blocked by first" } }
      end

      CodeAgent::Extension.define("never_called") do
        before_tool_call { |_, _| { block: true, reason: "should not reach" } }
      end

      CodeAgent::Extension.registry.each_value { |e| CodeAgent::Extension.register_hooks(e) }

      result = CodeAgent::Extension.run_tool_call_hooks("exec_shell", { command: "ls" })
      expect(result).to eq({ block: true, reason: "blocked by first" })
    end

    it "clear_hooks! removes all hooks" do
      ext = CodeAgent::Extension.define("temp_hook") do
        before_tool_call { |_, _| { block: true, reason: "test" } }
      end

      CodeAgent::Extension.register_hooks(ext)
      expect(CodeAgent::Extension.hook_summary[:total]).to eq(1)

      CodeAgent::Extension.clear_hooks!
      expect(CodeAgent::Extension.hook_summary[:total]).to eq(0)
    end

    it "hook_summary reports counts correctly" do
      ext = CodeAgent::Extension.define("multi_hooks") do
        before_tool_call { |_, _| nil }
        before_tool_call { |_, _| nil }
        after_tool_call { |_, _, r| r }
      end

      CodeAgent::Extension.register_hooks(ext)

      summary = CodeAgent::Extension.hook_summary
      expect(summary[:tool_call]).to eq(2)
      expect(summary[:tool_result]).to eq(1)
      expect(summary[:total]).to eq(3)
    end
  end

  # ── Tool Execution via #call (RubyLLM entry point) ─────────────────

  describe "tool execution via #call" do
    let(:fake_tool_class) do
      Class.new(CodeAgent::Tools::Base) do
        description "A fake tool for testing hooks"

        def execute(action: "default")
          { action: action, executed: true }
        end
      end
    end

    it "blocks tool execution when before_tool_call returns block: true" do
      tool = fake_tool_class.new
      tname = tool.name
      ext = CodeAgent::Extension.define("blocker") do
        before_tool_call do |name, _params|
          if name == tname
            { block: true, reason: "testing block" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = tool.call(action: "test")
      expect(result).to eq({ error: "Blocked by extension: testing block" })
    end

    it "allows execution when hooks return nil" do
      ext = CodeAgent::Extension.define("passive") do
        before_tool_call { |_, _| nil }
      end
      CodeAgent::Extension.register_hooks(ext)

      tool = fake_tool_class.new
      result = tool.call(action: "hello")
      expect(result).to eq({ action: "hello", executed: true })
    end

    it "modifies result via after_tool_call hook" do
      tool = fake_tool_class.new
      tname = tool.name
      ext = CodeAgent::Extension.define("annotator") do
        after_tool_call do |name, _params, result|
          if name == tname
            result.merge(annotated_by: "annotator")
          else
            result
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = tool.call(action: "test")
      expect(result).to eq({ action: "test", executed: true, annotated_by: "annotator" })
    end

    it "chains result modifications from multiple hooks" do
      ext1 = CodeAgent::Extension.define("first_mod") do
        after_tool_call { |_, _, r| r.merge(step1: true) }
      end
      ext2 = CodeAgent::Extension.define("second_mod") do
        after_tool_call { |_, _, r| r.merge(step2: true) }
      end
      CodeAgent::Extension.register_hooks(ext1)
      CodeAgent::Extension.register_hooks(ext2)

      tool = fake_tool_class.new
      result = tool.call(action: "test")
      expect(result[:step1]).to be true
      expect(result[:step2]).to be true
    end

    it "does not affect tools without matching hooks" do
      ext = CodeAgent::Extension.define("shell_only") do
        before_tool_call do |tool_name, _params|
          if tool_name == "exec_shell"
            { block: true, reason: "no shell" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      tool = fake_tool_class.new
      result = tool.call(action: "safe")
      expect(result[:executed]).to be true
    end
  end

  # ── Extension DSL Inspection ────────────────────────────────────────

  describe "Extension#hook_counts" do
    it "returns zero for extension without hooks" do
      ext = CodeAgent::Extension.define("no_hooks") do
        description "Nothing"
      end
      counts = ext.hook_counts
      expect(counts[:tool_call]).to eq(0)
      expect(counts[:tool_result]).to eq(0)
    end

    it "counts hooks correctly" do
      ext = CodeAgent::Extension.define("with_hooks") do
        before_tool_call { |_, _| nil }
        before_tool_call { |_, _| nil }
        after_tool_call { |_, _, r| r }
      end
      counts = ext.hook_counts
      expect(counts[:tool_call]).to eq(2)
      expect(counts[:tool_result]).to eq(1)
    end
  end

  # ── Integration: permission_gate pattern ────────────────────────────

  describe "permission gate pattern" do
    it "blocks rm -rf" do
      patterns = [/\brm\s+-rf?\b/]
      ext = CodeAgent::Extension.define("gate") do
        before_tool_call do |tool_name, params|
          next nil unless tool_name == "exec_shell"

          command = params[:command].to_s
          if patterns.any? { |p| command.match?(p) }
            { block: true, reason: "Dangerous: #{command}" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = CodeAgent::Extension.run_tool_call_hooks("exec_shell", { command: "rm -rf /tmp/foo" })
      expect(result).to eq({ block: true, reason: "Dangerous: rm -rf /tmp/foo" })
    end

    it "allows safe commands" do
      patterns = [/\brm\s+-rf?\b/]
      ext = CodeAgent::Extension.define("safe_gate") do
        before_tool_call do |tool_name, params|
          next nil unless tool_name == "exec_shell"

          command = params[:command].to_s
          if patterns.any? { |p| command.match?(p) }
            { block: true, reason: "Dangerous" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = CodeAgent::Extension.run_tool_call_hooks("exec_shell", { command: "ls -la" })
      expect(result).to be_nil
    end
  end

  # ── Integration: path_protection pattern ────────────────────────────

  describe "path protection pattern" do
    it "blocks writes to .env" do
      ext = CodeAgent::Extension.define("protector") do
        before_tool_call do |tool_name, params|
          next nil unless %w[write_file edit_file].include?(tool_name)

          path = params[:path].to_s
          if File.fnmatch?("**/.env", path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
            { block: true, reason: "Protected: #{path}" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = CodeAgent::Extension.run_tool_call_hooks("write_file", { path: ".env", content: "x" })
      expect(result).to eq({ block: true, reason: "Protected: .env" })
    end

    it "allows writes to normal files" do
      ext = CodeAgent::Extension.define("allow_normal") do
        before_tool_call do |tool_name, params|
          next nil unless %w[write_file edit_file].include?(tool_name)

          path = params[:path].to_s
          if File.fnmatch?("**/.env", path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
            { block: true, reason: "Protected" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      result = CodeAgent::Extension.run_tool_call_hooks("write_file", { path: "lib/foo.rb", content: "x" })
      expect(result).to be_nil
    end
  end

  # ── Real built-in tool via #call ────────────────────────────────────

  describe "built-in tool via #call", :tmpdir do
    it "blocks exec_shell via hook" do
      ext = CodeAgent::Extension.define("no_exec") do
        before_tool_call do |tool_name, _params|
          if tool_name == "exec_shell"
            { block: true, reason: "shell disabled" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      tool = CodeAgent::Tools::ExecShell.new
      result = tool.call(command: "echo hello")
      expect(result).to eq({ error: "Blocked by extension: shell disabled" })
    end

    it "allows read_file despite hook for shell only" do
      ext = CodeAgent::Extension.define("shell_only_hook") do
        before_tool_call do |tool_name, _params|
          if tool_name == "exec_shell"
            { block: true, reason: "no shell" }
          end
        end
      end
      CodeAgent::Extension.register_hooks(ext)

      File.write(File.join(@tmpdir, "data.txt"), "content")

      tool = CodeAgent::Tools::ReadFile.new
      result = tool.call(path: "data.txt")
      expect(result).to include("   1| content")
    end
  end

  # ── Schema not affected by hooks ────────────────────────────────────

  describe "schema preservation" do
    it "execute signature is untouched (schema inference reads this)" do
      tool = CodeAgent::Tools::ReadFile.new
      params = tool.method(:execute).parameters
      # Should have :path, :start_line, :end_line — NOT just **params
      expect(params.map { |t, n| [t, n] }).to include([:keyreq, :path])
    end
  end
end
