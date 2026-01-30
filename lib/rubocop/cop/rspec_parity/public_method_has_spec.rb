# frozen_string_literal: true

require_relative "spec_file_finder"

module RuboCop
  module Cop
    module RSpecParity
      # Checks that each public method in a class has a corresponding spec test.
      #
      # @example
      #   # bad - public method `perform` exists but no describe '#perform' in spec
      #
      #   # good - public method `perform` has describe '#perform' in spec
      #
      class PublicMethodHasSpec < Base # rubocop:disable Metrics/ClassLength
        include SpecFileFinder

        MSG = "Missing spec for public method `%<method_name>s`. " \
              "Expected describe '#%<method_name>s' or describe '.%<method_name>s' in %<spec_path>s"

        COVERED_DIRECTORIES = %w[models controllers services jobs mailers helpers].freeze
        EXCLUDED_METHODS = %w[initialize].freeze
        EXCLUDED_PATTERNS = [/^before_/, /^after_/, /^around_/, /^validate_/, /^autosave_/].freeze
        VISIBILITY_METHODS = { private: :private, protected: :protected, public: :public }.freeze

        def on_def(node)
          return unless checkable_method?(node) && public_method?(node)

          check_method_has_spec(node, instance_method: !inside_eigenclass?(node))
        end

        def on_defs(node)
          return unless checkable_method?(node)

          check_method_has_spec(node, instance_method: false)
        end

        private

        def checkable_method?(node)
          should_check_file? && !excluded_method?(node.method_name.to_s)
        end

        def inside_eigenclass?(node)
          node.each_ancestor.any? { |a| a.sclass_type? && a.children.first&.self_type? }
        end

        def should_check_file?
          path = processed_source.file_path
          return false if path.nil? || !path.include?("/app/") || path.end_with?("_spec.rb")

          COVERED_DIRECTORIES.any? { |dir| path.include?("/app/#{dir}/") }
        end

        def public_method?(node)
          return false if node.nil?

          class_or_module = find_class_or_module(node)
          return true unless class_or_module

          compute_visibility(class_or_module, node) == :public
        end

        def find_class_or_module(node)
          node.each_ancestor.find { |n| n.class_type? || n.module_type? }
        end

        def compute_visibility(class_or_module, target_node)
          visibility = :public
          class_or_module.body&.each_child_node do |child|
            break if child == target_node

            visibility = update_visibility(child, visibility)
          end
          visibility
        end

        def update_visibility(child, current_visibility)
          return current_visibility unless child.send_type?

          VISIBILITY_METHODS.fetch(child.method_name, current_visibility)
        end

        def excluded_method?(method_name)
          EXCLUDED_METHODS.include?(method_name) ||
            EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(method_name) }
        end

        def source_file_path
          processed_source.file_path
        end

        def check_method_has_spec(node, instance_method:)
          class_name = extract_class_name(node)
          return unless class_name

          base_spec_path = expected_spec_path
          spec_paths = find_valid_spec_files(class_name, base_spec_path)
          return if spec_paths.empty?

          method_name = node.method_name.to_s
          return if spec_paths.any? { |spec_path| spec_covers_method?(spec_path, method_name, instance_method) }

          add_method_offense(node, method_name, spec_paths.first)
        end

        def spec_covers_method?(spec_path, method_name, instance_method)
          return true if method_tested_in_spec?(spec_path, method_name, instance_method)

          service_call_method?(method_name) && method_tested_in_spec?(spec_path, method_name, !instance_method)
        end

        def service_call_method?(method_name)
          method_name == "call" && processed_source.file_path&.include?("/app/services/")
        end

        def add_method_offense(node, method_name, spec_path)
          add_offense(
            node.loc.keyword.join(node.loc.name),
            message: format(MSG, method_name: method_name, spec_path: relative_spec_path(spec_path))
          )
        end

        def method_tested_in_spec?(spec_path, method_name, instance_method)
          spec_content = File.read(spec_path)
          prefix = instance_method ? "#" : "."
          test_patterns(prefix, method_name).any? { |pattern| spec_content.match?(pattern) }
        end

        def test_patterns(prefix, method_name)
          escaped_prefix = Regexp.escape(prefix)
          escaped_name = Regexp.escape(method_name)
          [
            /describe\s+['"]#{escaped_prefix}#{escaped_name}['"]/,
            /context\s+['"]#{escaped_prefix}#{escaped_name}['"]/,
            /it\s+['"](tests?|checks?|verifies?|validates?)\s+#{escaped_name}/i,
            /describe\s+['"]#{escaped_name}['"]/
          ]
        end

        def expected_spec_path
          processed_source.file_path&.sub("/app/", "/spec/")&.sub(/\.rb$/, "_spec.rb")
        end

        def relative_spec_path(spec_path)
          root = find_project_root
          root ? spec_path.sub("#{root}/", "") : spec_path
        end

        def find_project_root
          path = processed_source.file_path
          return nil if path.nil?

          app_index = path.split("/").index("app")
          app_index ? path.split("/")[0...app_index].join("/") : nil
        end
      end
    end
  end
end
