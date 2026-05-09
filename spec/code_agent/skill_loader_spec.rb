# frozen_string_literal: true

require "tmpdir"

RSpec.describe CodeAgent::SkillLoader do
  describe ".load_all" do
    it "returns empty array when no skills dir exists" do
      Dir.mktmpdir do |dir|
        extensions = described_class.load_all(dir)
        expect(extensions).to eq([])
      end
    end

    it "loads skills from .code_agent/skills/<name>/SKILL.md" do
      Dir.mktmpdir do |dir|
        skill_dir = File.join(dir, ".code_agent", "skills", "my-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: my-skill
          description: A test skill
          ---
          Do the thing correctly.
        MD

        extensions = described_class.load_all(dir)
        names = extensions.map(&:name)
        expect(names).to include("skill/my-skill")

        ext = extensions.find { |e| e.name == "skill/my-skill" }
        skill = ext.get_skill("my-skill")
        expect(skill).not_to be_nil
        expect(skill[:prompt]).to include("Do the thing correctly")
      end
    end

    it "uses directory name when frontmatter name is missing" do
      Dir.mktmpdir do |dir|
        skill_dir = File.join(dir, ".code_agent", "skills", "auto-named")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          description: No name in frontmatter
          ---
          Instructions here.
        MD

        extensions = described_class.load_all(dir)
        ext = extensions.find { |e| e.name == "skill/auto-named" }
        expect(ext).not_to be_nil
        skill = ext.get_skill("auto-named")
        expect(skill).not_to be_nil
      end
    end

    it "rejects invalid skill names" do
      Dir.mktmpdir do |dir|
        skill_dir = File.join(dir, ".code_agent", "skills", "Bad Name!")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: Bad Name!
          description: Invalid name
          ---
          content
        MD

        extensions = described_class.load_all(dir)
        expect(extensions).to be_empty
      end
    end

    it "handles missing frontmatter gracefully" do
      Dir.mktmpdir do |dir|
        skill_dir = File.join(dir, ".code_agent", "skills", "plain-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), "Just plain text, no frontmatter.")

        extensions = described_class.load_all(dir)
        expect(extensions).not_to be_empty
        ext = extensions.first
        skill = ext.get_skill("plain-skill")
        expect(skill[:prompt]).to include("Just plain text")
      end
    end
  end
end
