# frozen_string_literal: true

module RuboCop
  module Cop
    module RSpecParity
      # Builds a static call graph for the methods defined directly inside a
      # class/module node. Used by SufficientContexts to inline branches from
      # private/protected helpers that are called from exactly one place in
      # the same container.
      class PrivateMethodCallGraph # rubocop:disable Metrics/ClassLength
        # `branch_tally` is whatever the branch_counter returns (a BranchTally),
        # or nil when nothing was inlined. It must respond to `+` and `total`.
        Result = Struct.new(:branch_tally, :traced_methods)

        DYNAMIC_DISPATCH_SENDS = %i[send public_send __send__].freeze
        EVAL_METHODS = %i[class_eval instance_eval module_eval].freeze

        def initialize(container_node)
          @container = container_node
          @methods = {}
          @order = []
          @built = false
        end

        def dynamic_dispatch?
          return false unless @container

          @dynamic_dispatch ||= detect_dynamic_dispatch
          @dynamic_dispatch == :yes
        end

        def inlinable_from(method_node, branch_counter)
          return Result.new(nil, []) unless @container
          return Result.new(nil, []) if dynamic_dispatch?

          build! unless @built

          key = key_for(method_node)
          return Result.new(nil, []) unless @methods.key?(key)

          traverse(key, branch_counter)
        end

        private

        def traverse(start_key, branch_counter)
          state = { visited: Set.new([start_key]), tally: nil, traced: [] }
          stack = callees_of(start_key)
          until stack.empty?
            key = stack.shift
            next unless inlinable?(key, state[:visited])

            visit_callee(key, branch_counter, state)
            stack.concat(callees_of(key))
          end
          Result.new(state[:tally], sorted_names(state[:traced]))
        end

        def callees_of(key)
          @methods[key][:callees].to_a
        end

        def visit_callee(key, branch_counter, state)
          state[:visited] << key
          tally = branch_counter.call(@methods[key][:node])
          return unless tally.total.positive?

          state[:tally] = combine_tally(state[:tally], tally, @methods[key][:name])
          state[:traced] << key
        end

        # Attribute the inlined branches to the helper they came from so the cop
        # can show "label (helper, line N)" and accept origin-prefixed
        # `# rspec_parity:covers` annotations. Duck-typed: a plain count would skip.
        def combine_tally(existing, tally, name)
          tally = tally.with_origin(name) if tally.respond_to?(:with_origin)
          existing ? existing + tally : tally
        end

        def inlinable?(key, visited)
          return false if visited.include?(key)
          return false unless @methods.key?(key)
          return false if @methods[key][:visibility] == :public

          call_count(key) == 1
        end

        def call_count(key)
          @call_counts ||= compute_call_counts
          @call_counts[key] || 0
        end

        def compute_call_counts
          counts = Hash.new(0)
          @methods.each_value do |entry|
            entry[:callees].each { |callee_key| counts[callee_key] += 1 }
          end
          counts
        end

        def sorted_names(keys)
          keys.sort_by { |k| @order.index(k) || @order.size }
              .map { |k| @methods[k][:name] }
        end

        def key_for(node)
          [node.defs_type? ? :class : :instance, node.method_name.to_s]
        end

        # ---------- Build phase ----------

        def build!
          @built = true
          walk_body(body_children(@container), :public, :instance)
          @methods.each_value { |entry| entry[:callees] = collect_callees(entry[:node], entry[:namespace]) }
        end

        def walk_body(children, visibility, namespace) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
          children.each do |child|
            next unless child

            case child.type
            when :def
              register_method(child, :instance, visibility) if namespace == :instance
              register_method(child, :class, visibility) if namespace == :class
            when :defs
              register_method(child, :class, :public)
            when :send
              visibility = handle_visibility_send(child, visibility, namespace) || visibility
            when :sclass
              walk_body(body_children(child), :public, :class)
            end
          end
        end

        def register_method(def_node, kind, visibility)
          name = def_node.method_name.to_s
          key = [kind, name]
          @methods[key] = { name: name, node: def_node, visibility: visibility, namespace: kind, callees: Set.new }
          @order << key
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def handle_visibility_send(send_node, current_visibility, namespace)
          name = send_node.method_name
          args = send_node.arguments

          if %i[public private protected].include?(name)
            kind = namespace == :class ? :class : :instance
            if args.empty?
              return name
            elsif args.first.def_type?
              register_method(args.first, kind, name)
              return current_visibility
            else
              apply_named_visibility(args, name, kind)
              return current_visibility
            end
          end

          if %i[private_class_method public_class_method].include?(name)
            target_vis = name == :private_class_method ? :private : :public
            if args.first&.defs_type? || args.first&.def_type?
              register_method(args.first, :class, target_vis)
            else
              apply_named_visibility(args, target_vis, :class)
            end
          end

          current_visibility
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        def apply_named_visibility(args, visibility, kind)
          args.each do |arg|
            next unless arg.sym_type? || arg.str_type?

            key = [kind, arg.value.to_s]
            @methods[key][:visibility] = visibility if @methods.key?(key)
          end
        end

        # ---------- Callee collection ----------

        def collect_callees(def_node, namespace)
          callees = Set.new
          body = def_node.body
          return callees unless body

          each_send(body) do |send_node|
            add_callee(callees, send_node, namespace)
          end
          callees
        end

        def each_send(node, &block)
          return unless node.is_a?(RuboCop::AST::Node)
          return if node.def_type? || node.defs_type?

          yield node if node.send_type?
          node.children.each { |child| each_send(child, &block) if child.is_a?(RuboCop::AST::Node) }
        end

        def add_callee(callees, send_node, namespace)
          receiver = send_node.receiver
          return unless receiver.nil? || receiver.self_type?

          name = literal_send_target(send_node) || send_node.method_name.to_s
          key = [namespace, name]
          callees << key if @methods.key?(key)
        end

        # `send(:foo)` / `public_send(:foo)` with a literal symbol → treat as a static call to `foo`.
        def literal_send_target(send_node)
          return nil unless DYNAMIC_DISPATCH_SENDS.include?(send_node.method_name)

          first_arg = send_node.arguments.first
          return nil unless first_arg&.sym_type? || first_arg&.str_type?

          first_arg.value.to_s
        end

        # ---------- Dynamic dispatch detection ----------

        def detect_dynamic_dispatch
          return :no unless @container&.body

          found = false
          walk_for_dynamic(@container.body) { found = true }
          found ? :yes : :no
        end

        def walk_for_dynamic(node, &block)
          return unless node.is_a?(RuboCop::AST::Node)
          return yield if dynamic_dispatch_node?(node)

          node.children.each { |child| walk_for_dynamic(child, &block) if child.is_a?(RuboCop::AST::Node) }
        end

        def dynamic_dispatch_node?(node)
          return method_missing_def?(node) if node.def_type?
          return symbol_to_proc_block_pass?(node) if node.block_pass_type?
          return false unless node.send_type?

          dynamic_send?(node) || define_method?(node) || string_eval?(node) || method_reference?(node)
        end

        def method_missing_def?(node)
          %i[method_missing respond_to_missing?].include?(node.method_name)
        end

        def symbol_to_proc_block_pass?(node)
          node.children.first&.sym_type?
        end

        def dynamic_send?(node)
          return false unless DYNAMIC_DISPATCH_SENDS.include?(node.method_name)

          first = node.arguments.first
          return false if first.nil?
          return false if first.sym_type? || first.str_type?

          true
        end

        def define_method?(node)
          node.method_name == :define_method
        end

        def string_eval?(node)
          return false unless EVAL_METHODS.include?(node.method_name)

          node.arguments.any? { |arg| arg.str_type? || arg.dstr_type? }
        end

        def method_reference?(node)
          node.method_name == :method && node.arguments.size == 1 && node.arguments.first.sym_type?
        end

        def body_children(node)
          return [] unless node&.body

          node.body.begin_type? ? node.body.children : [node.body]
        end
      end
    end
  end
end
