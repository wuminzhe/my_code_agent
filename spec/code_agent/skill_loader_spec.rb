# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe CodeAgent::SkillLoader do
  let(:project_root) { Dir.mktmpdir }
  let(:project_skills) { File.join(project_root, ".code_agent", "skills") }

  after(:each) { FileUtils.rm_rf(project_root) }

  describe ".load_all" do
    context "when no skills directories exist" do
      it "returns an empty array" do
        skills = described_class.load_all(project_root)
        expect(skills).to eq([])
      end
    end

    context "with a valid skill in the project directory" do
      before(:each) do
        skill_dir = File.join(project_skills, "my-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: my-skill
          description: A test skill
          ---
          Do the thing correctly.
        MD
      end

      it "loads the skill with name, description, and prompt" do
        skills = described_class.load_all(project_root)

        expect(skills.size).to eq(1)
        skill = skills.first
        expect(skill.name).to eq("my-skill")
        expect(skill.description).to eq("A test skill")
        expect(skill.prompt).to eq("Do the thing correctly.")
      end

      it "returns a Skill struct with the expected attributes" do
        skill = described_class.load_all(project_root).first

        expect(skill).to have_attributes(
          name: "my-skill",
          description: "A test skill",
          prompt: "Do the thing correctly."
        )
      end
    end

    context "with a skill that has no name in frontmatter" do
      it "uses the directory name as the skill name" do
        skill_dir = File.join(project_skills, "auto-named")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          description: No name in frontmatter
          ---
          Instructions here.
        MD

        skills = described_class.load_all(project_root)
        expect(skills.first.name).to eq("auto-named")
      end
    end

    context "with a skill that has no description in frontmatter" do
      it "falls back to a file-based description" do
        skill_dir = File.join(project_skills, "desc-fallback")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: desc-fallback
          ---
          Do stuff.
        MD

        skills = described_class.load_all(project_root)
        expect(skills.first.description).to match(/Skill from/)
      end
    end

    context "with no frontmatter at all" do
      it "parses the entire content as the prompt" do
        skill_dir = File.join(project_skills, "plain-skill")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), "Just plain text, no frontmatter.")

        skills = described_class.load_all(project_root)
        expect(skills).not_to be_empty
        expect(skills.first.prompt).to include("Just plain text")
      end
    end

    context "with an invalid skill name" do
      it "rejects the skill and returns an empty array" do
        skill_dir = File.join(project_skills, "bad-name-dir")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: Bad Name!
          description: Invalid name
          ---
          content
        MD

        skills = described_class.load_all(project_root)
        expect(skills).to be_empty
      end
    end

    context "with a single-character valid name" do
      it "accepts the skill" do
        skill_dir = File.join(project_skills, "x")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: x
          description: Single char name
          ---
          content
        MD

        skills = described_class.load_all(project_root)
        expect(skills.size).to eq(1)
        expect(skills.first.name).to eq("x")
      end
    end

    context "with invalid YAML frontmatter" do
      it "handles the parse error and resorts to defaults" do
        skill_dir = File.join(project_skills, "bad-yaml")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
          ---
          name: bad-yaml
          description: [invalid, yaml
          ---
          content
        MD

        skills = described_class.load_all(project_root)
        expect(skills.size).to eq(1)
        expect(skills.first.name).to eq("bad-yaml")
      end
    end

    context "with a user-level skills directory" do
      let(:user_skills_dir) { File.join(Dir.tmpdir, "code_agent_skills_test_#{Process.pid}") }
      let(:home_dir) { File.expand_path("~") }

      before(:each) do
        # Stub the user home path so we don't clobber real user skills
        stub_const("CodeAgent::SkillLoader::USER_SKILLS_DIR",
                    File.join(user_skills_dir, ".code_agent", "skills"))
        FileUtils.mkdir_p(File.join(user_skills_dir, ".code_agent", "skills", "user-level-skill"))
        File.write(File.join(user_skills_dir, ".code_agent", "skills", "user-level-skill", "SKILL.md"), <<~MD)
          ---
          name: user-level-skill
          description: Installed globally
          ---
          Global instructions.
        MD
      end

      after(:each) { FileUtils.rm_rf(user_skills_dir) }

      it "loads skills from the user directory" do
        skills = described_class.load_all(project_root)
        names = skills.map(&:name)
        expect(names).to include("user-level-skill")
      end
    end

    context "when both user and project directories exist" do
      let(:user_skills_dir) { File.join(Dir.tmpdir, "code_agent_skills_test_#{Process.pid}") }

      before(:each) do
        stub_const("CodeAgent::SkillLoader::USER_SKILLS_DIR",
                    File.join(user_skills_dir, ".code_agent", "skills"))

        # User-level skill
        FileUtils.mkdir_p(File.join(user_skills_dir, ".code_agent", "skills", "user-skill"))
        File.write(File.join(user_skills_dir, ".code_agent", "skills", "user-skill", "SKILL.md"), <<~MD)
          ---
          name: user-skill
          description: From home
          ---
          User instructions.
        MD

        # Project-level skill
        FileUtils.mkdir_p(File.join(project_skills, "project-skill"))
        File.write(File.join(project_skills, "project-skill", "SKILL.md"), <<~MD)
          ---
          name: project-skill
          description: From project
          ---
          Project instructions.
        MD
      end

      after(:each) { FileUtils.rm_rf(user_skills_dir) }

      it "loads skills from both directories" do
        skills = described_class.load_all(project_root)
        names = skills.map(&:name)
        expect(names).to contain_exactly("user-skill", "project-skill")
      end
    end

    context "when project_root is nil" do
      it "skips project-level directory and loads only from user directory" do
        skills = described_class.load_all(nil)
        expect(skills).to eq([])
      end
    end
  end
end
