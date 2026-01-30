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

        def initialize(config = nil, options = nil)
          super
          @skip_method_describe_paths = cop_config.fetch("SkipMethodDescribeFor", [])
        end

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

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def check_method_has_spec(node, instance_method:)
          class_name = extract_class_name(node)
          return unless class_name

          base_spec_path = expected_spec_path
          spec_paths = find_valid_spec_files(class_name, base_spec_path)
          return if spec_paths.empty?

          method_name = node.method_name.to_s

          # Check if relaxed validation applies
          if matches_skip_path? && count_public_methods(node) == 1
            # For single-method classes in configured paths, just check for examples
            return if spec_paths.any? { |spec_path| spec_has_examples?(spec_path, class_name) }
          elsif spec_paths.any? { |spec_path| spec_covers_method?(spec_path, method_name, instance_method) }
            # Normal validation: check for method describe
            return
          end

          add_method_offense(node, method_name, spec_paths.first)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

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

        def matches_skip_path?
          return false if @skip_method_describe_paths.empty?

          file_path = processed_source.file_path
          return false unless file_path

          @skip_method_describe_paths.any? do |pattern|
            # Match against both absolute path and relative path
            File.fnmatch?(pattern, file_path, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
              File.fnmatch?(pattern, extract_relative_path(file_path), File::FNM_PATHNAME | File::FNM_EXTGLOB)
          end
        end

        def extract_relative_path(file_path)
          # Extract path starting from 'app/' directory
          app_index = file_path.split("/").index("app")
          return file_path unless app_index

          file_path.split("/")[app_index..].join("/")
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def count_public_methods(node)
          class_node = find_class_or_module(node)
          return 0 unless class_node&.body

          public_methods = []
          visibility = :public

          # Get all child nodes, handling both single method and begin-wrapped bodies
          children = if class_node.body.begin_type?
                       class_node.body.children
                     else
                       [class_node.body]
                     end

          children.each do |child|
            next unless child

            case child.type
            when :send
              visibility = VISIBILITY_METHODS[child.method_name] if VISIBILITY_METHODS.key?(child.method_name)
            when :def
              # Only count instance methods (def), not class methods (defs)
              if visibility == :public
                method_name = child.method_name.to_s
                public_methods << method_name unless excluded_method?(method_name)
              end
            end
          end

          public_methods.size
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        def spec_has_examples?(spec_path, class_name)
          spec_content = File.read(spec_path)
          escaped_class_name = Regexp.escape(class_name)

          # Check that the spec describes the correct class
          return false unless spec_content.match?(/(?:RSpec\.)?describe\s+#{escaped_class_name}(?:\s|,|do)/)

          # Check for any it/example/specify blocks
          spec_content.match?(/^\s*(?:it|example|specify)\s+/)
        end
      end
    end
  end
end
