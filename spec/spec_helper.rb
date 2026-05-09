# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "code_agent"
require "json"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = false
  config.default_formatter = "doc" if config.files_to_run.one?

  # Reset CodeAgent config between tests
  config.before do
    CodeAgent.configure!
  end

  # Temp workspace for tool/file tests — avoids rspec-mocks in around hook
  config.before(:each, :tmpdir) do
    @tmpdir = Dir.mktmpdir("code_agent_test")
    CodeAgent.config.data["agent"] ||= {}
    CodeAgent.config.data["agent"]["workspace"] = @tmpdir
  end

  config.after(:each, :tmpdir) do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end
end
