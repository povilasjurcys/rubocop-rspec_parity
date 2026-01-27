# frozen_string_literal: true

require "rubocop"

require_relative "rubocop/spec_parity"
require_relative "rubocop/spec_parity/version"
require_relative "rubocop/spec_parity/plugin"
require_relative "rubocop/cop/spec_parity/no_let_bang"
require_relative "rubocop/cop/spec_parity/public_method_has_spec"
require_relative "rubocop/cop/spec_parity/sufficient_contexts"

# Inject default configuration (legacy support for RuboCop < 1.72)
# For RuboCop >= 1.72, use `plugins: rubocop-spec_parity` in .rubocop.yml
default_config = File.expand_path("../config/default.yml", __dir__)
RuboCop::ConfigLoader.inject_defaults!(default_config) if File.exist?(default_config)
