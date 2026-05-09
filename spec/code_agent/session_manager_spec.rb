# frozen_string_literal: true

RSpec.describe CodeAgent::SessionManager do
  let(:sessions) { described_class.new }
  let(:test_sessions_dir) { Dir.mktmpdir("ca_sessions_test") }

  before do
    stub_const("#{described_class}::SESSIONS_DIR", test_sessions_dir)
  end

  after do
    FileUtils.rm_rf(test_sessions_dir) if File.exist?(test_sessions_dir)
  end

  describe "#list" do
    it "returns empty array when no sessions exist" do
      expect(sessions.list).to eq([])
    end
  end

  describe "#save and #load" do
    it "saves and loads session data" do
      # Build a minimal session payload manually
      session_data = {
        metadata: { created_at: Time.now.iso8601, model: "test", turn_count: 3 },
        messages: [
          { role: "user", content: "hello" },
          { role: "assistant", content: "hi there" }
        ]
      }

      path = File.join(test_sessions_dir, "test_session.json")
      File.write(path, JSON.pretty_generate(session_data))

      loaded = sessions.load("test_session")
      expect(loaded).not_to be_nil
      expect(loaded[:messages].size).to eq(2)
      expect(loaded[:metadata][:turn_count]).to eq(3)
    end

    it "sets current_name on load" do
      File.write(File.join(test_sessions_dir, "named.json"), JSON.pretty_generate({
        metadata: {}, messages: []
      }))
      sessions.load("named")
      expect(sessions.current_name).to eq("named")
    end

    it "returns nil for non-existent session" do
      expect(sessions.load("nonexistent")).to be_nil
    end

    it "returns nil for corrupt JSON" do
      File.write(File.join(test_sessions_dir, "corrupt.json"), "not json {{{")
      expect(sessions.load("corrupt")).to be_nil
    end
  end

  describe "#delete" do
    it "deletes a session file" do
      path = File.join(test_sessions_dir, "delete_me.json")
      File.write(path, JSON.pretty_generate({ metadata: {}, messages: [] }))
      sessions.delete("delete_me")
      expect(File.exist?(path)).to be false
    end

    it "resets current_name if deleting current session" do
      File.write(File.join(test_sessions_dir, "current.json"), JSON.pretty_generate({
        metadata: {}, messages: []
      }))
      sessions.load("current")
      sessions.delete("current")
      expect(sessions.current_name).to be_nil
    end
  end

  describe "#session_path" do
    it "sanitizes the name" do
      path = sessions.session_path("my session/../bad!")
      basename = File.basename(path)
      expect(basename).not_to include("/")
      expect(basename).not_to include("..")
      expect(basename).to end_with(".json")
      expect(basename).to eq("my_session____bad_.json")
    end
  end
end
