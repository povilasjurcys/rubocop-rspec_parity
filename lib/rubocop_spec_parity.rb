# frozen_string_literal: true

require "rubocop"

require_relative "rubocop/spec_parity"
require_relative "rubocop/spec_parity/version"
require_relative "rubocop/cop/spec_parity/no_let_bang"
require_relative "rubocop/cop/spec_parity/public_method_has_spec"

# Inject default configuration
default_config = File.expand_path("../config/default.yml", __dir__)
RuboCop::ConfigLoader.inject_defaults!(default_config) if File.exist?(default_config)
