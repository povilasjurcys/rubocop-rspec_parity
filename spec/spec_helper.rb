# frozen_string_literal: true

require "rubocop_spec_parity"
require "rubocop/rspec/support"

# Override _investigate to use Commissioner instead of Team
# Team doesn't trigger callbacks for some cops, but Commissioner does
module InvestigateOverride
  def _investigate(cop, processed_source)
    commissioner = RuboCop::Cop::Commissioner.new([cop], [], raise_error: true)
    report = commissioner.investigate(processed_source)
    @last_corrector = report.correctors.first || RuboCop::Cop::Corrector.new(processed_source)
    report.offenses.reject(&:disabled?)
  end
end

RSpec.configure do |config|
  config.include InvestigateOverride

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
