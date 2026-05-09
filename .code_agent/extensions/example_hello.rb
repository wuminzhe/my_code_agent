# frozen_string_literal: true

# Example extension: adds a "hello world" tool and extra system prompt context.
CodeAgent::Extension.define "example_hello" do
  description "A simple example extension"

  system_prompt do
    "You are working in the my_code_agent project. Be helpful and concise."
  end
end
