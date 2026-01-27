# frozen_string_literal: true

module RuboCop
  module Cop
    module SpecParity
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

        def on_def(node)
          check_method(node)
        end

        def on_defs(node)
          check_method(node)
        end

        private

        def check_method(node) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          return unless in_covered_directory?
          return if excluded_method?(method_name(node))

          branches = count_branches(node)
          return if branches < 2 # Only check methods with branches

          spec_file = spec_file_path
          return unless File.exist?(spec_file)

          spec_content = File.read(spec_file)
          contexts = count_contexts_for_method(spec_content, method_name(node))

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
          COVERED_DIRECTORIES.any? { |dir| processed_source.path.start_with?(dir) }
        end

        def excluded_method?(method_name)
          return true if EXCLUDED_METHODS.include?(method_name)

          EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(method_name) }
        end

        def spec_file_path
          path = processed_source.path
          path.sub(%r{^app/}, "spec/").sub(/\.rb$/, "_spec.rb")
        end

        def count_branches(node)
          branches = 0
          elsif_nodes = Set.new

          # First pass: collect all elsif nodes (if nodes in else branches)
          node.each_descendant(:if) do |if_node|
            elsif_nodes.add(if_node.else_branch) if if_node.else_branch&.if_type?
          end

          # Second pass: count branches, skipping elsif nodes
          node.each_descendant do |descendant|
            next if elsif_nodes.include?(descendant)

            branches += branch_count_for_node(descendant)
          end
          branches
        end

        def branch_count_for_node(node)
          case node.type
          when :if then count_if_branches(node)
          when :case then count_case_branches(node)
          when :and, :or then 1
          when :send then node.method?(:&) || node.method?(:|) ? 1 : 0
          else 0
          end
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

        # rubocop:disable Metrics/MethodLength
        def count_contexts_for_method(spec_content, method_name)
          method_pattern = Regexp.escape(method_name)
          in_method_block = false
          context_count = 0
          base_indent = 0

          spec_content.each_line do |line|
            current_indent = line[/^\s*/].length

            # Entering a describe block for this method
            if matches_method_describe?(line, method_pattern)
              in_method_block = true
              base_indent = current_indent
              # Don't count the describe itself, only nested contexts
              next
            end

            # Process lines inside the method block
            if in_method_block
              in_method_block = false if exiting_block?(line, current_indent, base_indent)
              context_count += 1 if nested_context?(line)
            elsif matches_context_pattern?(line, method_pattern)
              context_count += 1
            end
          end

          context_count
        end

        # rubocop:enable Metrics/MethodLength
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
      end
    end
  end
end
