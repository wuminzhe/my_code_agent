# frozen_string_literal: true

require "tmpdir"

RSpec.describe CodeAgent::AgentLoop do
  let(:config) { CodeAgent::Config.new }
  let(:agent) { described_class.new(config) }

  before do
    # Explicitly configure with the real API key for integration tests
    if ENV["DEEPSEEK_API_KEY"] || config.api_key
      # configure_provider will be called in build_chat
    end
  end

  describe "#initialize" do
    it "creates with nil chat (lazy)" do
      expect(agent.instance_variable_get(:@chat)).to be_nil
    end

    it "has 0 turn count" do
      expect(agent.turn_count).to eq(0)
    end

    it "has empty extensions" do
      expect(agent.extensions).to eq([])
    end
  end

  describe "#load_extensions!" do
    it "loads project-level extensions" do
      agent.load_extensions!
      expect(agent.extensions).not_to be_empty
    end
  end

  describe "#assemble_system_prompt" do
    it "includes base system prompt" do
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("expert coding assistant")
    end

    it "injects current date" do
      prompt = agent.assemble_system_prompt
      today = Time.now.strftime("%Y-%m-%d")
      expect(prompt).to include("Current date: #{today}")
    end

    it "injects working directory" do
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("Working directory:")
    end

    it "injects platform" do
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("Platform: #{RUBY_PLATFORM}")
    end

    it "injects git branch when in a git repo" do
      has_git = File.directory?(".git") || File.file?(".git")
      skip "not a git repo" unless has_git
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("Git branch:")
    end

    it "injects active tools when tools are registered" do
      # Register tools directly to avoid triggering API key check via chat()
      agent.register_tool(CodeAgent::Tools::ReadFile.new)
      agent.register_tool(CodeAgent::Tools::ExecShell.new)
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("Available tools:")
      expect(prompt).to include("read_file")
      expect(prompt).to include("exec_shell")
    end

    it "does not include tools section when no tools registered" do
      prompt = agent.assemble_system_prompt
      expect(prompt).not_to include("Available tools:")
    end

    it "includes extension fragments after load" do
      agent.load_extensions!
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("my_code_agent") # from example_hello extension
    end

    it "includes context files when AGENTS.md exists in workspace" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "AGENTS.md"), "# Project Rules\n- Use TDD")
        config = CodeAgent::Config.new
        config.data["agent"] ||= {}
        config.data["agent"]["workspace"] = dir
        config.data["agent"]["context_files"] = true
        agent2 = described_class.new(config)
        prompt = agent2.assemble_system_prompt
        expect(prompt).to include("AGENTS.md")
        expect(prompt).to include("- Use TDD")
      end
    end

    it "skips context files when disabled" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "AGENTS.md"), "secret stuff")
        config = CodeAgent::Config.new
        config.data["agent"] ||= {}
        config.data["agent"]["workspace"] = dir
        config.data["agent"]["context_files"] = false
        agent2 = described_class.new(config)
        prompt = agent2.assemble_system_prompt
        expect(prompt).not_to include("secret stuff")
      end
    end

    it "discovers context files in ancestor directories" do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, "sub", "deep")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(dir, "CLAUDE.md"), "root rules")
        config = CodeAgent::Config.new
        config.data["agent"] ||= {}
        config.data["agent"]["workspace"] = subdir
        config.data["agent"]["context_files"] = true
        agent2 = described_class.new(config)
        prompt = agent2.assemble_system_prompt
        expect(prompt).to include("CLAUDE.md")
        expect(prompt).to include("root rules")
      end
    end

    it "includes skill catalog when extensions define skills" do
      ext = CodeAgent::Extension.define("test_skill_ext") do
        skill "ruby_style", prompt: "Use Ruby style guide conventions."
      end
      agent.instance_variable_get(:@extensions) << ext
      prompt = agent.assemble_system_prompt
      expect(prompt).to include("Available skills")
      expect(prompt).to include("ruby_style")
    end

    it "omits skill catalog when no skills defined" do
      prompt = agent.assemble_system_prompt
      expect(prompt).not_to include("Available skills")
    end
  end

  describe "#collect_skills" do
    it "returns empty hash when no extensions loaded" do
      expect(agent.collect_skills).to eq({})
    end

    it "returns skills from loaded extensions" do
      ext = CodeAgent::Extension.define("collect_test") do
        skill "test_a", prompt: "skill A"
        skill "test_b", prompt: "skill B"
      end
      agent.instance_variable_get(:@extensions) << ext
      skills = agent.collect_skills
      expect(skills.keys).to contain_exactly("test_a", "test_b")
    end
  end

  describe "#find_skill" do
    it "finds a skill by name" do
      ext = CodeAgent::Extension.define("find_test") do
        skill "my_skill", prompt: "instructions"
      end
      agent.instance_variable_get(:@extensions) << ext
      skill = agent.find_skill("my_skill")
      expect(skill).not_to be_nil
      expect(skill[:prompt]).to eq("instructions")
    end

    it "returns nil for unknown skill" do
      expect(agent.find_skill("nonexistent")).to be_nil
    end
  end

  describe "#chat (lazy init)", :integration do
    it "builds chat on first access and registers tools" do
      c = agent.chat
      expect(c).not_to be_nil
      tools = agent.instance_variable_get(:@tools)
      expect(tools).to have_key("read_file")
      expect(tools).to have_key("write_file")
      expect(tools).to have_key("edit_file")
      expect(tools).to have_key("exec_shell")
    end

    it "returns same chat on subsequent access" do
      c1 = agent.chat
      c2 = agent.chat
      expect(c1).to equal(c2)
    end
  end

  describe "#send_message", :integration do
    it "sends a message and gets a text response" do
      response = agent.send_message("Reply with exactly 'pong' and nothing else.")
      expect(response[:type]).to eq(:text)
      expect(response[:content].downcase).to include("pong")
    end

    it "increments turn count" do
      expect { agent.send_message("say hi") }.to change { agent.turn_count }.by(1)
    end
  end

  describe "#reset!", :integration do
    it "clears conversation history" do
      agent.send_message("say hi")
      agent.reset!
      expect(agent.turn_count).to eq(0)
    end
  end
end
