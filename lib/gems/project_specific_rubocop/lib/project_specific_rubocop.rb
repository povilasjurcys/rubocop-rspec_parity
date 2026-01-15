# frozen_string_literal: true

require 'rubocop'

require_relative 'rubocop/cop/test_coverage/public_method_has_spec'
require_relative 'rubocop/cop/rspec/no_let_bang'

# Inject default configuration
default_config = File.expand_path('../../config/default.yml', __dir__)
RuboCop::ConfigLoader.inject_defaults!(default_config) if File.exist?(default_config)
