# frozen_string_literal: true

require_relative "lib/rubocop/rspec_parity/version"

Gem::Specification.new do |spec|
  spec.name = "rubocop-rspec_parity"
  spec.version = RuboCop::RSpecParity::VERSION
  spec.authors = ["Povilas Jurcys"]
  spec.email = ["po.jurcys@gmail.com"]

  spec.summary = "RuboCop plugin for enforcing RSpec spec parity and best practices"
  spec.description = "A RuboCop plugin that provides custom cops to ensure RSpec test coverage parity and " \
                     "enforce RSpec best practices in your Ruby projects."
  spec.homepage = "https://github.com/povilasjurcys/rubocop-rspec_parity"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/povilasjurcys/rubocop-rspec_parity"
  spec.metadata["changelog_uri"] = "https://github.com/povilasjurcys/rubocop-rspec_parity/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["default_lint_roller_plugin"] = "RuboCop::RSpecParity::Plugin"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "lint_roller", "~> 1.1"
  spec.add_dependency "rubocop", ">= 1.72.0"
end
