# frozen_string_literal: true

require_relative "spec_file_finder"

module RuboCop
  module Cop
    module RSpecParity
      # Ensures that specs have at least as many contexts as the method has branches.
      #
      # This cop helps ensure thorough test coverage by checking that complex methods
      # with multiple branches (if/elsif/else, case/when, &&, ||, ternary) have
      # corresponding context blocks in their specs to test each branch.
      #
      # @example
      #   # bad - method has 3 branches, spec has only 1 context
      #   # app/services/user_creator.rb
      #   def create_user(params)
      #     if params[:admin]
      #       create_admin(params)
      #     elsif params[:moderator]
      #       create_moderator(params)
      #     else
      #       create_regular_user(params)
      #     end
      #   end
      #
      #   # spec/services/user_creator_spec.rb
      #   context 'when creating a user' do
      #     # only one context for 3 branches
      #   end
      #
      #   # good - method has 3 branches, spec has 3 contexts
      #   # spec/services/user_creator_spec.rb
      #   context 'when creating an admin' do
      #   end
      #   context 'when creating a moderator' do
      #   end
      #   context 'when creating a regular user' do
      #   end
      class SufficientContexts < Base # rubocop:disable Metrics/ClassLength
        include SpecFileFinder

        MSG = "Method `%<method_name>s` has %<branches>d %<branch_word>s but only %<contexts>d %<context_word>s " \
              "in spec. Add %<missing>d more %<missing_word>s to cover all branches."

        COVERED_DIRECTORIES = %w[
          app/models
          app/controllers
          app/services
          app/jobs
          app/mailers
          app/helpers
        ].freeze

        EXCLUDED_METHODS = %w[initialize].freeze

        EXCLUDED_PATTERNS = [
          /^before_/,
          /^after_/,
          /^around_/,
          /^validate_/,
          /^autosave_/
        ].freeze

        def initialize(config = nil, options = nil)
          super
          @ignore_memoization = cop_config.fetch("IgnoreMemoization", true)
          @skip_method_describe_paths = cop_config.fetch("SkipMethodDescribeFor", [])
        end

        def on_def(node)
          check_method(node)
        end

        def on_defs(node)
          check_method(node)
        end

        private

        def check_method(node) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          return unless in_covered_directory?
          return if excluded_method?(method_name(node))

          branches = count_branches(node)
          return if branches < 2 # Only check methods with branches

          class_name = extract_class_name(node)
          return unless class_name

          base_spec_path = spec_file_path
          spec_files = find_valid_spec_files(class_name, base_spec_path)
          return if spec_files.empty?

          # Aggregate contexts from all valid spec files
          contexts = if matches_skip_path? && count_public_methods(node) == 1
                       # For single-method classes, count top-level contexts instead
                       spec_files.sum { |spec_file| count_top_level_contexts(File.read(spec_file), class_name) }
                     else
                       # Normal path: look for method describes
                       spec_files.sum { |spec_file| count_contexts_for_method(File.read(spec_file), method_name(node)) }
                     end

          return if contexts.zero? # Method has no specs at all - PublicMethodHasSpec handles this
          return if contexts >= branches

          missing = branches - contexts
          add_offense(node,
                      message: format(MSG,
                                      method_name: method_name(node),
                                      branches: branches,
                                      branch_word: pluralize("branch", branches),
                                      contexts: contexts,
                                      context_word: pluralize("context", contexts),
                                      missing: missing,
                                      missing_word: pluralize("context", missing)))
        end

        def method_name(node)
          if node.def_type?
            node.method_name.to_s
          else
            node.children[1].to_s
          end
        end

        def in_covered_directory?
          path = processed_source.path
          # Handle both absolute and relative paths
          COVERED_DIRECTORIES.any? do |dir|
            path.start_with?(dir) || path.include?("/#{dir}/") || path.match?(%r{/#{Regexp.escape(dir)}$})
          end
        end

        def excluded_method?(method_name)
          return true if EXCLUDED_METHODS.include?(method_name)

          EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(method_name) }
        end

        def source_file_path
          processed_source.path
        end

        def spec_file_path
          path = processed_source.path
          # Handle both absolute and relative paths
          path.sub(%r{/app/}, "/spec/").sub(%r{^app/}, "spec/").sub(/\.rb$/, "_spec.rb")
        end

        def count_branches(node)
          branches = 0
          elsif_nodes = collect_elsif_nodes(node)

          node.each_descendant do |descendant|
            next if elsif_nodes.include?(descendant)
            next if should_skip_node?(descendant)

            branches += branch_count_for_node(descendant)
          end
          branches
        end

        def collect_elsif_nodes(node)
          elsif_nodes = Set.new
          node.each_descendant(:if) do |if_node|
            elsif_nodes.add(if_node.else_branch) if if_node.else_branch&.if_type?
          end
          elsif_nodes
        end

        def should_skip_node?(node)
          @ignore_memoization && memoization_pattern?(node)
        end

        def branch_count_for_node(node)
          case node.type
          when :if then count_if_branches(node)
          when :case then count_case_branches(node)
          when :and, :or then 1
          when :or_asgn, :and_asgn then 2 # ||= and &&= create 2 branches (set vs already set)
          when :send then send_node_branch_count(node)
          else 0
          end
        end

        def send_node_branch_count(node)
          node.method?(:&) || node.method?(:|) ? 1 : 0
        end

        def count_if_branches(node)
          # if/else is 2 branches, each elsif adds 1
          branches = 2
          current = node
          while current&.if_type? && current.else_branch&.if_type?
            branches += 1
            current = current.else_branch
          end
          branches
        end

        def count_case_branches(node)
          # Each when clause is a branch, plus default/else
          when_count = node.when_branches.count
          has_else = !node.else_branch.nil?
          when_count + (has_else ? 1 : 0)
        end

        def count_contexts_for_method(spec_content, method_name)
          method_pattern = Regexp.escape(method_name)
          context_count, has_examples = parse_spec_content(spec_content, method_pattern)

          # If no contexts but has examples, count as 1 scenario
          context_count.zero? && has_examples ? 1 : context_count
        end

        # rubocop:disable Metrics/MethodLength
        def parse_spec_content(spec_content, method_pattern)
          in_method_block = false
          context_count = 0
          has_examples = false
          base_indent = 0

          spec_content.each_line do |line|
            current_indent = line[/^\s*/].length

            if matches_method_describe?(line, method_pattern)
              in_method_block = true
              base_indent = current_indent
              next
            end

            if in_method_block
              context_count, has_examples, in_method_block = process_method_block_line(
                line, current_indent, base_indent, context_count, has_examples
              )
            elsif matches_context_pattern?(line, method_pattern)
              context_count += 1
            end
          end

          [context_count, has_examples]
        end
        # rubocop:enable Metrics/MethodLength

        def process_method_block_line(line, current_indent, base_indent, context_count, has_examples)
          in_method_block = !exiting_block?(line, current_indent, base_indent)

          if nested_context?(line)
            context_count += 1
          elsif nested_example?(line)
            has_examples = true
          end

          [context_count, has_examples, in_method_block]
        end

        def matches_method_describe?(line, method_pattern)
          line =~ /^\s*describe\s+['"](?:#|\.)?#{method_pattern}['"]/ ||
            line =~ /^\s*describe\s+:#{method_pattern}/
        end

        def matches_context_pattern?(line, method_pattern)
          line =~ /^\s*(?:context|describe)\s+.*(?:#|\.)?#{method_pattern}/
        end

        def nested_context?(line)
          line =~ /^\s*(?:context|describe)\s+/
        end

        def nested_example?(line)
          line =~ /^\s*(?:it|example|specify)\s+/
        end

        def exiting_block?(line, current_indent, base_indent)
          current_indent <= base_indent && line =~ /^\s*(?:describe|context|end)/
        end

        def pluralize(word, count)
          return word if count == 1

          case word
          when "branch" then "branches"
          when "context" then "contexts"
          else "#{word}s"
          end
        end

        def memoization_pattern?(node)
          # Pattern: @var ||= value
          return true if or_asgn_ivar_pattern?(node)

          # Pattern: return @var if defined?(@var)
          return true if defined_check_pattern?(node)

          # Pattern: @var = value if @var.nil? or similar
          return true if nil_check_pattern?(node)

          # Pattern: || with instance variable (part of @var ||= which creates both :or and :or_asgn nodes)
          return true if or_with_ivar_pattern?(node)

          false
        end

        # @var ||= value
        def or_asgn_ivar_pattern?(node)
          node.or_asgn_type? && node.children[0]&.ivasgn_type?
        end

        # return @var if defined?(@var)
        def defined_check_pattern?(node)
          return false unless node.if_type?

          condition = node.condition
          return false unless condition&.defined_type?

          # Check if it's checking an instance variable
          condition.children[0]&.ivar_type?
        end

        # @var = value if @var.nil? or @var = value unless @var
        def nil_check_pattern?(node)
          return false unless node.if_type?

          condition = node.condition
          body = node.body

          # Check if body is an ivasgn
          return false unless body&.ivasgn_type?

          ivar_name = body.children[0]

          # Check if condition checks the same ivar for nil
          checks_same_ivar_for_nil?(condition, ivar_name)
        end

        def checks_same_ivar_for_nil?(condition, ivar_name)
          return false unless condition

          nil_check?(condition, ivar_name) || negation_check?(condition, ivar_name)
        end

        def nil_check?(condition, ivar_name)
          return false unless condition.send_type? && condition.method?(:nil?)

          condition.receiver&.ivar_type? && condition.receiver.children[0] == ivar_name
        end

        def negation_check?(condition, ivar_name)
          return false unless condition.send_type? && condition.method?(:!)

          receiver = condition.receiver
          receiver&.ivar_type? && receiver.children[0] == ivar_name
        end

        # || operator with instance variable on left side
        def or_with_ivar_pattern?(node)
          return false unless node.or_type?

          left = node.children[0]
          left&.ivar_type?
        end

        def matches_skip_path?
          return false if @skip_method_describe_paths.empty?

          path = processed_source.path
          return false unless path

          @skip_method_describe_paths.any? do |pattern|
            File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
          end
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def count_public_methods(node)
          class_node = find_class_or_module(node)
          return 0 unless class_node&.body

          public_methods = []
          visibility = :public
          visibility_methods = { private: :private, protected: :protected, public: :public }

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
              visibility = visibility_methods[child.method_name] if visibility_methods.key?(child.method_name)
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

        def find_class_or_module(node)
          node.each_ancestor.find { |n| n.class_type? || n.module_type? }
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def count_top_level_contexts(spec_content, class_name)
          # Find the class describe block
          describe_pattern = /^\s*(?:RSpec\.)?describe\s+#{Regexp.escape(class_name)}(?:\s|,|do)/

          lines = spec_content.lines
          describe_line_index = lines.index { |line| line.match?(describe_pattern) }
          return 0 unless describe_line_index

          # Count contexts/describes and examples at the top level (under class describe)
          base_indent = lines[describe_line_index].match(/^(\s*)/)[1].length
          context_count = 0
          has_examples = false

          lines[(describe_line_index + 1)..].each do |line|
            indent = line.match(/^(\s*)/)[1].length
            break if indent <= base_indent && !line.strip.empty? && line.match?(/^\s*(?:describe|context|end)/)

            next unless indent > base_indent

            if line.match?(/^\s*(?:context|describe)\s+/)
              context_count += 1
            elsif line.match?(/^\s*(?:it|example|specify)\s+/)
              has_examples = true
            end
          end

          # If no contexts but has examples, count as 1
          context_count.zero? && has_examples ? 1 : context_count
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      end
    end
  end
end
