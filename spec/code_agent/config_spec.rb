# frozen_string_literal: true

RSpec.describe CodeAgent::Config do
  describe "defaults" do
    subject(:config) { CodeAgent::Config.new }

    it "returns deepseek as default provider" do
      expect(config.provider).to eq("deepseek")
    end

    it "returns deepseek-v4-flash as default model" do
      expect(config.model).to eq("deepseek-v4-flash")
    end

    it "returns DEEPSEEK_API_KEY as env key" do
      expect(config.env_key).to eq("DEEPSEEK_API_KEY")
    end

    it "returns max_turns from config" do
      expect(config.max_turns).to be_a(Integer)
      expect(config.max_turns).to be > 0
    end

    it "returns a non-empty system prompt" do
      expect(config.system_prompt).to be_a(String)
      expect(config.system_prompt).not_to be_empty
    end

    it "returns tools config as a Hash" do
      expect(config.tools).to be_a(Hash)
      expect(config.tools).to have_key("read_file")
    end

    it "returns current dir as workspace by default" do
      expect(config.workspace).to eq(Dir.pwd)
    end
  end

  describe "#api_key" do
    around do |example|
      old = ENV.delete("DEEPSEEK_API_KEY")
      example.run
      ENV["DEEPSEEK_API_KEY"] = old if old
    end

    it "returns nil when env var is not set and config has no api_key" do
      config = CodeAgent::Config.new
      expect(config.api_key).to be_nil
    end

    it "returns env var when DEEPSEEK_API_KEY is set" do
      ENV["DEEPSEEK_API_KEY"] = "sk-env-test"
      config = CodeAgent::Config.new
      expect(config.api_key).to eq("sk-env-test")
    end

    it "returns nil when env var exists but is empty string" do
      ENV["DEEPSEEK_API_KEY"] = ""
      config = CodeAgent::Config.new
      expect(config.api_key).to be_nil  # empty string treated as missing
    end
  end

  describe "#env_key" do
    it "returns correct env key per provider" do
      expect(CodeAgent::Config.new.env_key).to eq("DEEPSEEK_API_KEY")
    end
  end

  describe "user config merge" do
    let(:user_config_path) { File.expand_path("~/.code_agent/config.yml") }

    around do |example|
      # Backup existing user config
      backup = nil
      if File.exist?(user_config_path)
        backup = File.read(user_config_path)
        File.delete(user_config_path)
      end
      example.run
      # Restore
      if backup
        File.write(user_config_path, backup)
      elsif File.exist?(user_config_path)
        File.delete(user_config_path)
      end
    end

    it "merges user config over defaults" do
      File.write(user_config_path, { "model" => { "name" => "custom-model" } }.to_yaml)
      config = CodeAgent::Config.new
      expect(config.model).to eq("custom-model")
    end
  end

  describe "custom config path" do
    it "loads and merges a custom config file" do
      Dir.mktmpdir do |dir|
        custom_path = File.join(dir, "custom.yml")
        File.write(custom_path, { "model" => { "name" => "override-model" } }.to_yaml)
        config = CodeAgent::Config.new(custom_path)
        expect(config.model).to eq("override-model")
      end
    end

    it "silently ignores missing custom config" do
      config = CodeAgent::Config.new("/nonexistent/path.yml")
      expect(config.model).to eq("deepseek-v4-flash")
    end
  end
end
