# frozen_string_literal: true

require "yaml"
require "fileutils"

module CodeAgent
  # Configuration loader and provider manager.
  # Reads config/default.yml, merges with ~/.code_agent/config.yml.
  class Config
    DEFAULT_CONFIG_PATH = File.expand_path("../../config/default.yml", __dir__)
    USER_CONFIG_PATH    = File.expand_path("~/.code_agent/config.yml")

    attr_reader :data

    def initialize(custom_path = nil)
      @data = load_defaults
      merge_user_config
      merge_custom(custom_path) if custom_path
    end

    # --- accessors ---

    def provider
      data.dig("model", "provider") || "openai"
    end

    def model
      data.dig("model", "name") || "gpt-4o"
    end

    def api_key
      key = ENV.fetch(env_key, data.dig("model", "api_key"))
      key.to_s.strip.empty? ? nil : key
    end

    def system_prompt
      data["system_prompt"] || default_system_prompt
    end

    def tools
      data["tools"] || {}
    end

    def context_files_enabled?
      val = data.dig("agent", "context_files")
      val.nil? ? true : val # enabled by default
    end

    def max_turns
      data.dig("agent", "max_turns") || 50
    end

    def workspace
      ws = data.dig("agent", "workspace")
      ws ? File.expand_path(ws) : Dir.pwd
    end

    # --- helpers ---

    def env_key
      case provider
      when "deepseek"  then "DEEPSEEK_API_KEY"
      when "anthropic" then "ANTHROPIC_API_KEY"
      when "google"    then "GOOGLE_API_KEY"
      else                  "OPENAI_API_KEY"
      end
    end

    def provider_options
      {
        api_key: api_key
      }.compact
    end

    private

    def load_defaults
      YAML.safe_load_file(DEFAULT_CONFIG_PATH, permitted_classes: [])
    rescue Errno::ENOENT
      {}
    end

    def merge_user_config
      return unless File.exist?(USER_CONFIG_PATH)

      user = YAML.safe_load_file(USER_CONFIG_PATH, permitted_classes: [])
      deep_merge!(@data, user) if user
    end

    def merge_custom(path)
      custom = YAML.safe_load_file(path, permitted_classes: [])
      deep_merge!(@data, custom) if custom
    rescue Errno::ENOENT
      # pass
    end

    def deep_merge!(base, overlay)
      overlay.each do |key, val|
        if base[key].is_a?(Hash) && val.is_a?(Hash)
          deep_merge!(base[key], val)
        else
          base[key] = val
        end
      end
    end

    def default_system_prompt
      <<~PROMPT.strip
        You are an expert coding assistant. You help users write, edit, and
        understand code in their project. You have access to tools for reading
        files, writing files, editing files, running shell commands, and
        loading skills. The active tools are listed in the context section above.

        ## Guidelines

        - Before making changes, read the files you plan to modify.
        - Use small, focused edits. Prefer edit_file over rewriting entire files.
        - When running shell commands, explain what you're doing and why.
        - If unsure about something, ask before acting.
        - Be concise. The user is here to get work done.
        - Show file paths clearly when working with files.
        - When using load_skill, follow the skill's instructions exactly.

        ## Tools

        - **read_file**: Read a file with optional line ranges. Use before editing.
        - **write_file**: Create or overwrite a file. Creates parent directories.
        - **edit_file**: Search-and-replace in a file. Must match exactly and uniquely.
        - **exec_shell**: Run a shell command in the workspace. Returns stdout/stderr/exit code.
        - **load_skill**: Load a skill's instructions for specialized tasks.

        Remember to check the context section for the current date, working
        directory, git branch, and exactly which tools are active.
      PROMPT
    end
  end
end
