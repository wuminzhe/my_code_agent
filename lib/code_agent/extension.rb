# frozen_string_literal: true

module CodeAgent
  # Extension system
  #
  # Extensions are Ruby files loaded from:
  #   1. ~/.code_agent/extensions/   (user-level, always loaded)
  #   2. .code_agent/extensions/     (project-level)
  #
  # Each extension can:
  #   - Register custom tools (RubyLLM::Tool subclasses)
  #   - Add system prompt fragments
  #   - Hook into agent lifecycle events
  #   - Define skills (pre-packaged prompts + tools)
  #
  # Usage in an extension file:
  #
  #   CodeAgent::Extension.define "my_rails_helper" do
  #     description "Adds Rails-aware tools and context"
  #
  #     tool MyRailsTool
  #
  #     system_prompt do
  #       "You are working on a Rails #{Rails.version} project."
  #     end
  #
  #     on_load do |agent|
  #       puts "Rails helper loaded!"
  #     end
  #   end
  class Extension
    attr_reader :name, :description

    @registry = {}

    class << self
      attr_reader :registry

      # Define a new extension (called from extension files)
      def define(name, &block)
        ext = new(name)
        ext.instance_eval(&block)
        registry[name.to_s] = ext
        ext
      end

      # Load extensions from a directory
      def load_from_directory(dir)
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*.rb")).sort.map do |file|
          load file
          # The loaded file should call Extension.define
          registry.values.last
        rescue StandardError => e
          warn "[CodeAgent] Failed to load extension #{file}: #{e.message}"
          nil
        end.compact
      end

      # Load all extensions (user + project)
      def load_all(project_root = nil)
        @registry = {}  # reset

        # User-level extensions
        load_from_directory(File.expand_path("~/.code_agent/extensions"))

        # Project-level extensions
        if project_root
          load_from_directory(File.join(project_root, ".code_agent", "extensions"))
        end

        registry.values
      end
    end

    def initialize(name)
      @name = name.to_s
      @description = nil
      @tool_classes = []
      @system_prompt_blocks = []
      @load_hooks = []
      @skills = {}
    end

    # DSL methods called inside Extension.define block

    def description(text = nil)
      @description = text if text
      @description
    end

    def tool(klass)
      @tool_classes << klass
    end

    def system_prompt(&block)
      @system_prompt_blocks << block
    end

    def on_load(&block)
      @load_hooks << block
    end

    def skill(name, prompt: nil, tools: [], &block)
      @skills[name.to_s] = {
        prompt: prompt,
        tools: tools,
        block: block
      }
    end

    # Runtime methods called by AgentLoop

    def tool_instances
      @tool_classes.map(&:new)
    end

    def build_system_prompt_fragment
      @system_prompt_blocks.map(&:call).compact.join("\n\n")
    end

    def run_load_hooks(agent)
      @load_hooks.each { |h| h.call(agent) }
    end

    def get_skill(name)
      @skills[name.to_s]
    end
  end
end
