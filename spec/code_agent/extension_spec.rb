# frozen_string_literal: true

RSpec.describe CodeAgent::Extension do
  before do
    CodeAgent::Extension.instance_variable_set(:@registry, {})
  end

  describe ".define" do
    it "creates an extension with a name" do
      ext = CodeAgent::Extension.define("test_ext") do
        description "A test extension"
      end
      expect(ext.name).to eq("test_ext")
      expect(ext.description).to eq("A test extension")
    end

    it "registers the extension in the class registry" do
      CodeAgent::Extension.define("my_ext") {}
      expect(CodeAgent::Extension.registry).to have_key("my_ext")
    end

    it "supports tool registration" do
      fake_tool_class = Class.new(CodeAgent::Tools::Base)
      ext = CodeAgent::Extension.define("tool_ext") do
        tool fake_tool_class
      end
      instances = ext.tool_instances
      expect(instances.size).to eq(1)
      expect(instances.first).to be_a(fake_tool_class)
    end

    it "supports system_prompt fragments" do
      ext = CodeAgent::Extension.define("prompt_ext") do
        system_prompt { "Custom prompt for testing." }
        system_prompt { "Another fragment." }
      end
      fragment = ext.build_system_prompt_fragment
      expect(fragment).to include("Custom prompt")
      expect(fragment).to include("Another fragment")
    end

    it "supports on_load hooks" do
      called = false
      ext = CodeAgent::Extension.define("hook_ext") do
        on_load { |_agent| called = true }
      end
      ext.run_load_hooks(double("agent"))
      expect(called).to be true
    end

    it "supports skill definitions" do
      ext = CodeAgent::Extension.define("skill_ext") do
        skill "rails", prompt: "You are a Rails expert", tools: []
      end
      skill = ext.get_skill("rails")
      expect(skill).not_to be_nil
      expect(skill[:prompt]).to eq("You are a Rails expert")
    end
  end

  describe ".load_all" do
    it "loads extensions from project .code_agent/extensions/" do
      Dir.mktmpdir do |dir|
        ext_dir = File.join(dir, ".code_agent", "extensions")
        FileUtils.mkdir_p(ext_dir)
        File.write(File.join(ext_dir, "proj_ext.rb"), <<~RUBY)
          CodeAgent::Extension.define("proj_ext") do
            description "Project-level extension"
          end
        RUBY

        extensions = CodeAgent::Extension.load_all(dir)
        expect(extensions.map(&:name)).to include("proj_ext")
      end
    end

    it "handles broken extension files gracefully" do
      Dir.mktmpdir do |dir|
        ext_dir = File.join(dir, ".code_agent", "extensions")
        FileUtils.mkdir_p(ext_dir)
        File.write(File.join(ext_dir, "bad.rb"), "raise 'boom'")

        expect {
          CodeAgent::Extension.load_all(dir)
        }.not_to raise_error
      end
    end

    it "returns empty array for non-existent directory" do
      extensions = CodeAgent::Extension.load_all("/nonexistent/path/xyz")
      expect(extensions).to eq([])
    end
  end

  describe "#build_system_prompt_fragment" do
    it "returns empty string when no fragments defined" do
      ext = CodeAgent::Extension.define("empty_prompt") {}
      expect(ext.build_system_prompt_fragment).to eq("")
    end

    it "joins multiple fragments with double newline" do
      ext = CodeAgent::Extension.define("multi") do
        system_prompt { "First." }
        system_prompt { "Second." }
      end
      expect(ext.build_system_prompt_fragment).to eq("First.\n\nSecond.")
    end
  end
end
