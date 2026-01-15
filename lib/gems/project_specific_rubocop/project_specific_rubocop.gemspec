# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'project_specific_rubocop'
  spec.version = '0.1.0'
  spec.authors = ['NextPage Team']
  spec.email = ['team@nextpage.dev']

  spec.summary = 'Project-specific RuboCop cops for ensuring test coverage'
  spec.description = 'Custom RuboCop cops that check if Ruby files and public methods have corresponding tests'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir['lib/**/*', 'config/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'rubocop', '>= 1.0'
end
