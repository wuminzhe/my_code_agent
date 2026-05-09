# frozen_string_literal: true

require_relative "code_agent/config"
require_relative "code_agent/extension"
require_relative "code_agent/session_manager"
require_relative "code_agent/agent_loop"
require_relative "code_agent/repl"

module CodeAgent
  VERSION = "0.1.0"

  class Error < StandardError; end

  class << self
    def config
      @config ||= Config.new
    end

    # Reset config (useful for testing or CLI --config flag)
    def configure!(custom_path = nil)
      @config = Config.new(custom_path)
    end
  end
end
