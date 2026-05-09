# frozen_string_literal: true

require_relative "base"

module CodeAgent
  module Tools
    # Loads a skill's instructions so the model can follow them.
    # Skills are defined in extensions via the `skill` DSL and appear
    # in the skill catalog within the system prompt.
    class LoadSkill < Base
      description <<~DESC.strip
        Load the instructions for a named skill. Skills provide specialized
        prompts, conventions, or tool workflows. The model should call this
        tool before performing a task that matches a skill's description.
        After loading, follow the skill's instructions.
      DESC

      def execute(name:)
        skill = agent.find_skill(name)
        return { error: "Skill not found: #{name}. Check available skills in the system prompt." } unless skill

        prompt = skill[:prompt]
        return { error: "Skill '#{name}' has no prompt defined." } unless prompt

        {
          skill: name,
          instructions: prompt.to_s,
          instruction: "Follow the instructions above when performing tasks related to #{name}."
        }
      end

      private

      # Access the AgentLoop to search for skills
      def agent
        CodeAgent::AgentLoop.current
      end
    end
  end
end
