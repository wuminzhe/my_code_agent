# frozen_string_literal: true

require "yaml"

module CodeAgent
  # Loads skills from SKILL.md files in standard directories.
  #
  # Discovery paths:
  #   1. ~/.code_agent/skills/<name>/SKILL.md  (user-level)
  #   2. .code_agent/skills/<name>/SKILL.md     (project-level)
  #
  # Each SKILL.md file uses YAML frontmatter:
  #   ---
  #   name: my-skill
  #   description: What this skill does
  #   ---
  #   Skill instructions here...
  #
  # Returns an array of skill hashes: { name:, description:, prompt: }
  module SkillLoader
    SKILL_FILE = "SKILL.md"
    USER_SKILLS_DIR   = File.expand_path("~/.code_agent/skills")
    PROJECT_SKILLS_DIR = ".code_agent/skills"

    # Skill data returned by load_all
    Skill = Struct.new(:name, :description, :prompt, keyword_init: true)

    class << self
      # Load all file-based skills and return them as an array of Skill structs.
      def load_all(project_root = nil)
        skills = []

        load_from_directory(USER_SKILLS_DIR, skills)
        if project_root
          load_from_directory(File.join(project_root, PROJECT_SKILLS_DIR), skills)
        end

        skills
      end

      private

      def load_from_directory(dir, skills)
        return unless Dir.exist?(dir)

        # Each skill is in its own subdirectory containing SKILL.md
        Dir.glob(File.join(dir, "*", SKILL_FILE)).sort.each do |file|
          skill = build_skill(file)
          skills << skill if skill
        rescue StandardError => e
          warn "[CodeAgent] Failed to load skill #{file}: #{e.message}"
        end
      end

      def build_skill(file)
        content = File.read(file)
        frontmatter, body = parse_frontmatter(content)

        name = frontmatter["name"] || File.basename(File.dirname(file))
        description = frontmatter["description"] || "Skill from #{file}"

        # Validate name (lowercase, hyphens, alphanumeric)
        unless valid_skill_name?(name)
          warn "[CodeAgent] Invalid skill name '#{name}' in #{file}. Use lowercase a-z, 0-9, hyphens only."
          return nil
        end

        Skill.new(name: name, description: description, prompt: body.strip)
      end

      def parse_frontmatter(content)
        return [{}, content] unless content.start_with?("---")

        parts = content.split("---\n", 3)
        return [{}, content] if parts.length < 3

        begin
          frontmatter = YAML.safe_load(parts[1]) || {}
        rescue StandardError
          warn "[CodeAgent] Invalid YAML frontmatter in skill file"
          frontmatter = {}
        end

        body = parts[2] || ""
        [frontmatter, body]
      end

      def valid_skill_name?(name)
        name.match?(/\A[a-z0-9][a-z0-9-]*[a-z0-9]\z/) || name.match?(/\A[a-z0-9]\z/)
      end
    end
  end
end
