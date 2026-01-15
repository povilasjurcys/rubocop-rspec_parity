# frozen_string_literal: true

module RuboCop
  module Cop
    module TestCoverage
      # Checks that each public method in a class has a corresponding spec test.
      #
      # @example
      #   # bad - public method `perform` exists but no describe '#perform' in spec
      #
      #   # good - public method `perform` has describe '#perform' in spec
      #
      class PublicMethodHasSpec < Base
        MSG = 'Missing spec for public method `%<method_name>s`. ' \
              "Expected describe '#%<method_name>s' or describe '.%<method_name>s' in %<spec_path>s"

        # Directories that should have spec coverage
        COVERED_DIRECTORIES = %w[
          models
          controllers
          services
          jobs
          mailers
          helpers
        ].freeze

        # Methods that are typically inherited/framework methods and don't need explicit tests
        EXCLUDED_METHODS = %w[
          initialize
        ].freeze

        # Patterns for methods that are typically callbacks or framework hooks
        EXCLUDED_PATTERNS = [
          /^before_/,
          /^after_/,
          /^around_/,
          /^validate_/,
          /^autosave_/
        ].freeze

        def on_def(node)
          return unless should_check_file?
          return unless public_method?(node)
          return if excluded_method?(node.method_name.to_s)

          # Check if this method is inside a `class << self` block (eigenclass)
          is_class_method = inside_eigenclass?(node)

          check_method_has_spec(node, instance_method: !is_class_method)
        end

        # Handle class methods (def self.method_name)
        def on_defs(node)
          return unless should_check_file?
          return if excluded_method?(node.method_name.to_s)

          check_method_has_spec(node, instance_method: false)
        end

        private

        # Check if the method is defined inside a `class << self` block
        def inside_eigenclass?(node)
          node.each_ancestor.any? do |ancestor|
            ancestor.sclass_type? && ancestor.children.first&.self_type?
          end
        end

        def should_check_file?
          file_path = processed_source.file_path
          return false if file_path.nil?
          return false unless file_path.include?('/app/')
          return false if file_path.end_with?('_spec.rb')
          return false if file_path.include?('/spec/')

          COVERED_DIRECTORIES.any? { |dir| file_path.include?("/app/#{dir}/") }
        end

        def public_method?(node)
          # Check if method is in public scope
          return false if node.nil?

          # Get the parent to check scope
          ancestors = node.each_ancestor.to_a

          # Check for explicit private/protected declarations before this method
          class_or_module = ancestors.find { |n| n.class_type? || n.module_type? }
          return true unless class_or_module

          # Track visibility as we scan through the class body
          visibility = :public
          class_or_module.body&.each_child_node do |child|
            break if child == node

            if child.send_type?
              case child.method_name
              when :private
                visibility = :private
              when :protected
                visibility = :protected
              when :public
                visibility = :public
              when :private_class_method
                # Handle private_class_method declarations
                next
              end
            end
          end

          visibility == :public
        end

        def excluded_method?(method_name)
          return true if EXCLUDED_METHODS.include?(method_name)
          return true if EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(method_name) }

          false
        end

        def check_method_has_spec(node, instance_method: true)
          spec_path = expected_spec_path
          return unless spec_path && File.exist?(spec_path)

          method_name = node.method_name.to_s

          # For service objects with 'call' method, allow testing either .call or #call
          if in_service_directory? && method_name == 'call'
            return if method_tested_in_spec?(spec_path, method_name, instance_method: true) ||
                      method_tested_in_spec?(spec_path, method_name, instance_method: false)
          else
            return if method_tested_in_spec?(spec_path, method_name, instance_method: instance_method)
          end

          add_offense(
            node.loc.keyword.join(node.loc.name),
            message: format(
              MSG,
              method_name: method_name,
              spec_path: relative_spec_path(spec_path)
            )
          )
        end

        def in_service_directory?
          file_path = processed_source.file_path
          return false if file_path.nil?

          file_path.include?('/app/services/')
        end

        def method_tested_in_spec?(spec_path, method_name, instance_method: true)
          spec_content = File.read(spec_path)

          # Look for describe blocks with the method name
          # For instance methods: describe '#method_name'
          # For class methods: describe '.method_name'
          prefix = instance_method ? '#' : '.'
          patterns = [
            /describe\s+['"]#{Regexp.escape(prefix)}#{Regexp.escape(method_name)}['"]/,
            /context\s+['"]#{Regexp.escape(prefix)}#{Regexp.escape(method_name)}['"]/,
            /it\s+['"](tests?|checks?|verifies?|validates?)\s+#{Regexp.escape(method_name)}/i,
            /describe\s+['"]#{Regexp.escape(method_name)}['"]/
          ]

          patterns.any? { |pattern| spec_content.match?(pattern) }
        end

        def expected_spec_path
          file_path = processed_source.file_path
          return nil if file_path.nil?

          file_path
            .sub('/app/', '/spec/')
            .sub(/\.rb$/, '_spec.rb')
        end

        def relative_spec_path(spec_path)
          project_root = find_project_root
          return spec_path unless project_root

          spec_path.sub("#{project_root}/", '')
        end

        def find_project_root
          file_path = processed_source.file_path
          return nil if file_path.nil?

          parts = file_path.split('/')
          app_index = parts.index('app')
          return nil unless app_index

          parts[0...app_index].join('/')
        end
      end
    end
  end
end
