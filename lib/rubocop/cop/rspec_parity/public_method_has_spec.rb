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
              "Expected %<expected>s in %<spec_path>s"

        COVERED_DIRECTORIES = %w[models controllers services jobs mailers helpers].freeze
        EXCLUDED_METHODS = %w[initialize].freeze
        EXCLUDED_HOOK_METHODS = %w[included extended inherited prepended].freeze
        EXCLUDED_PATTERNS = [/^before_/, /^after_/, /^around_/, /^validate_/, /^autosave_/].freeze
        VISIBILITY_METHODS = { private: :private, protected: :protected, public: :public }.freeze

        def initialize(config = nil, options = nil)
          super
          @skip_method_describe_paths = cop_config.fetch("SkipMethodDescribeFor", [])
          @describe_aliases = cop_config.fetch("DescribeAliases", {})
        end

        def on_def(node)
          return unless checkable_method?(node) && public_method?(node)
          return if inside_inner_class?(node)

          check_method_has_spec(node, instance_method: !inside_eigenclass?(node) && !inside_class_methods_block?(node))
        end

        def on_defs(node)
          return unless checkable_method?(node) && public_class_method?(node)
          return if EXCLUDED_HOOK_METHODS.include?(node.method_name.to_s)
          return if inside_inner_class?(node)

          check_method_has_spec(node, instance_method: false)
        end

        private

        def public_class_method?(node)
          # Inline form: private_class_method def self.method_name
          return false if node.parent&.send_type? && node.parent.method_name == :private_class_method

          # Post-hoc form: private_class_method :method_name
          class_node = find_class_or_module(node)
          return true unless class_node&.body

          !private_class_method_declared?(class_node, node.method_name)
        end

        def private_class_method_declared?(class_node, method_name)
          children = class_node.body.begin_type? ? class_node.body.children : [class_node.body]
          children.any? { |child| private_class_method_call?(child, method_name) }
        end

        def private_class_method_call?(node, method_name)
          node&.send_type? &&
            node.method_name == :private_class_method &&
            node.arguments.any? { |arg| arg.sym_type? && arg.value == method_name }
        end

        def checkable_method?(node)
          should_check_file? && !excluded_method?(node.method_name.to_s)
        end

        def inside_eigenclass?(node)
          node.each_ancestor.any? { |a| a.sclass_type? && a.children.first&.self_type? }
        end

        def inside_class_methods_block?(node)
          node.each_ancestor(:block).any? do |block_node|
            block_node.send_node.method_name == :class_methods
          end
        end

        def inside_inner_class?(node)
          enclosing = find_class_or_module(node)
          return false unless enclosing

          enclosing.each_ancestor.any? { |a| a.class_type? && class_has_methods?(a) }
        end

        def class_has_methods?(class_node)
          return false unless class_node.body

          children = class_node.body.begin_type? ? class_node.body.children : [class_node.body]
          children.any? { |child| child.def_type? || child.defs_type? || eigenclass_with_methods?(child) }
        end

        def eigenclass_with_methods?(node)
          return false unless node.sclass_type? && node.children.first&.self_type?

          body = node.body
          return false unless body

          body_children = body.begin_type? ? body.children : [body]
          body_children.any?(&:def_type?)
        end

        def should_check_file?
          path = processed_source.file_path
          return false if path.nil? || !path.include?("/app/") || path.end_with?("_spec.rb")

          COVERED_DIRECTORIES.any? { |dir| path.include?("/app/#{dir}/") }
        end

        def public_method?(node)
          return false if node.nil?

          # Inline form: private def method_name / protected def method_name
          if node.parent&.send_type? && VISIBILITY_METHODS.key?(node.parent.method_name)
            return node.parent.method_name == :public
          end

          scope = find_enclosing_scope(node)
          return true unless scope

          # Post-hoc targeted form overrides section-level visibility
          targeted = targeted_visibility(scope, node.method_name)
          return targeted == :public unless targeted.nil?

          compute_visibility(scope, node) == :public
        end

        def find_enclosing_scope(node)
          node.each_ancestor.find do |n|
            n.class_type? || n.module_type? || n.sclass_type? || class_methods_block?(n)
          end
        end

        def class_methods_block?(node)
          node.block_type? && node.send_node.method_name == :class_methods
        end

        def find_class_or_module(node)
          node.each_ancestor.find { |n| n.class_type? || n.module_type? }
        end

        def targeted_visibility(scope, method_name)
          return nil unless scope.body

          scope_children(scope).each do |child|
            next unless targeted_visibility_call?(child, method_name)

            return VISIBILITY_METHODS[child.method_name]
          end
          nil
        end

        def targeted_visibility_call?(node, method_name)
          node&.send_type? &&
            VISIBILITY_METHODS.key?(node.method_name) &&
            node.arguments.any? { |arg| arg.sym_type? && arg.value == method_name }
        end

        def scope_children(scope)
          scope.body.begin_type? ? scope.body.children : [scope.body]
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
          return current_visibility if child.arguments.any? # targeted/inline, not section-level

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

          add_method_offense(node, method_name, spec_paths.first, instance_method: instance_method)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        def spec_covers_method?(spec_path, method_name, instance_method)
          return true if method_tested_in_spec?(spec_path, method_name, instance_method)

          prefix = instance_method ? "#" : "."
          describe_key = "#{prefix}#{method_name}"
          describe_aliases_for(describe_key).any? do |alias_desc|
            alias_name = alias_desc.sub(/^[#.]/, "")
            alias_instance = !alias_desc.start_with?(".")
            method_tested_in_spec?(spec_path, alias_name, alias_instance)
          end
        end

        def add_method_offense(node, method_name, spec_path, instance_method:)
          prefix = instance_method ? "#" : "."
          expected = expected_describes(prefix, method_name)
          add_offense(
            node.loc.keyword.join(node.loc.name),
            message: format(MSG, method_name: method_name, expected: expected, spec_path: relative_spec_path(spec_path))
          )
        end

        def expected_describes(prefix, method_name)
          describes = ["describe '#{prefix}#{method_name}'"]
          describe_aliases_for("#{prefix}#{method_name}").each do |alias_desc|
            describes << "describe '#{alias_desc}'"
          end
          describes.join(" or ")
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
          targeted_non_public = []
          targeted_public = []
          visibility = :public
          children = scope_children(class_node)

          children.each do |child|
            next unless child

            case child.type
            when :send
              result = count_handle_visibility_send(child, targeted_non_public, targeted_public)
              visibility = result if result
            when :def
              if visibility == :public
                method_name = child.method_name.to_s
                public_methods << method_name unless excluded_method?(method_name)
              end
            end
          end

          ((public_methods - targeted_non_public) | targeted_public).size
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        def count_handle_visibility_send(child, targeted_non_public, targeted_public)
          return nil unless VISIBILITY_METHODS.key?(child.method_name)
          return VISIBILITY_METHODS[child.method_name] if child.arguments.empty?

          collect_targeted_methods(child, targeted_non_public, targeted_public)
          nil
        end

        def collect_targeted_methods(child, targeted_non_public, targeted_public)
          target_list = VISIBILITY_METHODS[child.method_name] == :public ? targeted_public : targeted_non_public

          child.arguments.each do |arg|
            name = targeted_method_name(arg)
            target_list << name if name && !excluded_method?(name)
          end
        end

        def targeted_method_name(arg)
          if arg.sym_type?
            arg.value.to_s
          elsif arg.def_type?
            arg.method_name.to_s
          end
        end

        def spec_has_examples?(spec_path, class_name)
          spec_content = File.read(spec_path)

          # Check that the spec describes the correct class (supports module-wrapped specs)
          return false unless class_name_variants(class_name).any? do |name|
            spec_content.match?(/(?:RSpec\.)?describe\s+#{Regexp.escape(name)}(?:\s|,|do)/)
          end

          # Check for any it/example/specify blocks
          spec_content.match?(/^\s*(?:it|example|specify)\s+/)
        end
      end
    end
  end
end
