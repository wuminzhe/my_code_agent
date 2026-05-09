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
  #   - Intercept tool calls (on_tool_call) and results (on_tool_result)
  #     for permission gates, path protection, result modification, etc.
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
  #
  #     # Intercept tool execution — return { block: true, reason: "..." } to deny
  #     on_tool_call do |tool_name, params|
  #       if tool_name == "exec_shell" && params[:command]&.include?("rm -rf")
  #         { block: true, reason: "Dangerous command blocked" }
  #       end
  #     end
  #   end
  class Extension
    attr_reader :name, :description

    @registry = {}

    class << self
      attr_reader :registry

      # ── Class-level hook registries ──────────────────────────────────
      # Collected from all loaded extensions. Each entry is a Proc.
      #   tool_call:  |tool_name, params|
      #   tool_result: |tool_name, params, result|
      @tool_call_hooks = []
      @tool_result_hooks = []

      attr_reader :tool_call_hooks, :tool_result_hooks

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

      # ── Hook management (called by AgentLoop) ───────────────────────

      # Register hooks from an extension instance.  Called after load_all.
      def register_hooks(ext)
        # Ensure hooks arrays are initialized (safety in case of load ordering issues)
        @tool_call_hooks ||= []
        @tool_result_hooks ||= []

        (ext.instance_variable_get(:@tool_call_hooks) || []).each do |hook|
          @tool_call_hooks << hook
        end
        (ext.instance_variable_get(:@tool_result_hooks) || []).each do |hook|
          @tool_result_hooks << hook
        end
      end

      # Clear all registered hooks (called on agent reset)
      def clear_hooks!
        @tool_call_hooks = []
        @tool_result_hooks = []
      end

      # Run all on_tool_call hooks before a tool executes.
      # Returns nil if all hooks pass, or { block: true, reason: "..." }
      # if any hook blocks.
      def run_tool_call_hooks(tool_name, params)
        @tool_call_hooks.each do |hook|
          result = hook.call(tool_name, params)
          next unless result.is_a?(Hash)

          blocked = result[:block] || result["block"]
          if blocked
            reason = result[:reason] || result["reason"] || "Blocked by extension hook"
            return { block: true, reason: reason }
          end
        end
        nil
      end

      # Run all on_tool_result hooks after a tool executes.
      # Returns the (potentially modified) result hash.
      def run_tool_result_hooks(tool_name, params, result)
        modified = result
        @tool_result_hooks.each do |hook|
          hooked = hook.call(tool_name, params, modified)
          modified = hooked if hooked.is_a?(Hash)
        end
        modified
      end

      # Return info about all active hooks for REPL inspection.
      def hook_summary
        {
          tool_call: @tool_call_hooks.size,
          tool_result: @tool_result_hooks.size,
          total: @tool_call_hooks.size + @tool_result_hooks.size
        }
      end
    end

    # ── Instance ──────────────────────────────────────────────────────

    def initialize(name)
      @name = name.to_s
      @description = nil
      @tool_call_hooks = []
      @tool_result_hooks = []
      @tool_classes = []
      @system_prompt_blocks = []
      @load_hooks = []
      @skills = {}
    end

    # ── DSL methods called inside Extension.define block ──────────────

    def description(text = nil)
      @description = text if text
      @description
    end

    # Register a tool execution hook.  Fires before the tool executes.
    #
    # The block receives (tool_name, params) where params is a hash of
    # keyword arguments.  Return nil / nothing to allow execution.
    # Return { block: true, reason: "..." } to deny the tool call.
    #
    #   on_tool_call do |tool_name, params|
    #     if tool_name == "exec_shell" && params[:command]&.include?("rm -rf")
    #       { block: true, reason: "Dangerous: rm -rf is not allowed" }
    #     end
    #   end
    def on_tool_call(&block)
      @tool_call_hooks << block
    end

    # Register a tool result hook.  Fires after the tool executes.
    # The block receives (tool_name, params, result) and can return a
    # modified result hash.  Return nil to keep the original result.
    #
    #   on_tool_result do |tool_name, params, result|
    #     result.merge(annotated_by: @name)
    #   end
    def on_tool_result(&block)
      @tool_result_hooks << block
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

    # ── Runtime methods called by AgentLoop ───────────────────────────

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

    # For REPL /hooks inspection
    def hook_counts
      {
        tool_call: @tool_call_hooks.size,
        tool_result: @tool_result_hooks.size
      }
    end
  end
end
