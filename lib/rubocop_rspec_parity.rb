# frozen_string_literal: true

require "rubocop"

require_relative "rubocop/rspec_parity"
require_relative "rubocop/rspec_parity/version"
require_relative "rubocop/rspec_parity/plugin"
require_relative "rubocop/cop/rspec_parity/file_has_spec"
require_relative "rubocop/cop/rspec_parity/public_method_has_spec"
require_relative "rubocop/cop/rspec_parity/sufficient_contexts"
