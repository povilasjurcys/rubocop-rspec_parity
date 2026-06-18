# frozen_string_literal: true

require "did_you_mean"

require_relative "spec_file_finder"
require_relative "private_method_call_graph"

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
        include DepartmentConfig
        include SpecFileFinder

        # Used when CoversAnnotations is on: names one still-uncovered branch and
        # gives the exact context to add. Re-running advances to the next gap as
        # branches get annotated, so the message stays short instead of listing all.
        COVERAGE_MSG = "Missing coverage for `%<token>s` (%<location>s) — " \
                       "%<missing>d of %<branches>d %<branch_word>s untested. " \
                       "Add `context '...' do # rspec_parity:covers %<token>s` to mark it covered."

        # Used when many branches are missing: too many to walk one at a time, so
        # point at the CLI that lists them all instead.
        MANY_MSG = "%<missing>d of %<branches>d %<branch_word>s untested. " \
                   "Run `bundle exec rspec-parity-cover %<location>s` for the full list."

        # Above this many missing branches, switch from the per-branch message to
        # the CLI pointer.
        MANY_UNCOVERED_BRANCHES = 3

        # Used when CoversAnnotations is off (no annotation guidance to give).
        COUNT_MSG = "Method `%<method_name>s` is missing coverage for %<missing>d of %<branches>d %<branch_word>s."

        TRACED_SUFFIX = " (including branches from: %<traced>s)"

        ORPHAN_SUFFIX = " `rspec_parity:covers` annotation `%<label>s` matches no branch%<hint>s"

        ANNOTATION_PATTERN = /#\s*rspec_parity:covers\s+(.+?)\s*\z/

        APP_DIR_PATTERN = %r{/app/}

        EXCLUDED_METHODS = %w[initialize].freeze

        EXCLUDED_PATTERNS = [
          /^before_/,
          /^after_/,
          /^around_/,
          /^validate_/,
          /^autosave_/
        ].freeze

        # Tallies extracted from a spec's text for a single method describe block.
        # `annotations` holds raw `# rspec_parity:covers` label strings found in the
        # block (empty unless CoversAnnotations is on).
        ParsedSpec = Struct.new(:context_count, :example_count, :has_examples, :has_direct_examples, :annotations)

        # A spec's contribution to coverage: scenarios counted from un-annotated
        # contexts/examples, plus the raw annotation labels gathered from it.
        SpecCoverage = Struct.new(:scenarios, :annotations)

        # Line-by-line scanner state shared by both spec-counting paths. Tracks
        # the scenario tallies (mirroring the prior behaviour) and, when
        # CoversAnnotations is on, gathers `# rspec_parity:covers` labels and
        # collapses an annotated context's body so its examples count as the one
        # annotated branch rather than as separate scenarios.
        class ScanState
          def initialize(annotations_enabled)
            @annotations_enabled = annotations_enabled
            @context_count = 0
            @example_count = 0
            @has_examples = false
            @has_direct_examples = false
            @child_indent = nil
            @annotations = []
            @annotated_indent = nil
            @last_context_indent = nil
            @last_context_counted = false
          end

          def reset_child_indent
            @child_indent = nil
          end

          def inside_annotated_context?
            !@annotated_indent.nil?
          end

          def exit_annotated_context(indent)
            @annotated_indent = nil if @annotated_indent && indent <= @annotated_indent
          end

          def count_context(line, indent)
            @last_context_indent = indent
            labels = annotation_labels(line)
            return annotate_context_line(indent, labels) if labels.any?

            @child_indent ||= indent
            @context_count += 1
            @last_context_counted = true
          end

          # A comment-only annotation line, typically placed just inside a context
          # block when a trailing comment would overflow the line length. It is
          # attributed to the enclosing context, which then collapses like a
          # context annotated on its opening line. Returns the labels (truthy)
          # when it consumes the line, else nil. Place it before the context's
          # examples; an annotation after an example only collapses what follows.
          def collect_standalone_annotation(line)
            return unless @annotations_enabled
            return unless line.lstrip.start_with?("#")

            labels = annotation_labels(line)
            return if labels.empty?

            @annotations.concat(labels)
            annotate_enclosing_context
            labels
          end

          # Coarse path for method-named context lines (e.g. `context '.call'`):
          # count the block and gather any annotation, but don't collapse — this
          # path doesn't track the block's interior.
          def count_named_context(line)
            @context_count += 1
            @annotations.concat(annotation_labels(line))
          end

          def count_example(line, indent)
            labels = annotation_labels(line)
            if labels.any?
              @annotations.concat(labels)
            else
              @has_examples = true
              @example_count += 1
              @child_indent ||= indent
              @has_direct_examples = true if indent == @child_indent
            end
          end

          def to_parsed_spec
            ParsedSpec.new(@context_count, @example_count, @has_examples, @has_direct_examples, @annotations)
          end

          private

          # Annotation found on a context's own opening line: record the labels
          # and collapse the block from this indent. Nothing was counted yet.
          def annotate_context_line(indent, labels)
            @annotations.concat(labels)
            @annotated_indent = indent
            @last_context_counted = false
          end

          # Mark the most-recently-opened context as annotated: undo its generic
          # scenario count (it now counts as its labels) and collapse the rest of
          # its body. No-op if that context is already annotated.
          def annotate_enclosing_context
            return if @annotated_indent && @annotated_indent == @last_context_indent

            if @last_context_counted
              @context_count -= 1
              @last_context_counted = false
            end
            @annotated_indent = @last_context_indent
          end

          def annotation_labels(line)
            return [] unless @annotations_enabled

            match = line.match(ANNOTATION_PATTERN)
            return [] unless match

            match[1].split(";").map(&:strip).reject(&:empty?)
          end
        end

        # A single counted branch. `kind` is :guard or :regular (preserving the
        # guard fall-through accounting in #branches_from). `label` is the
        # normalized condition/operator source used both for display and for
        # matching `# rspec_parity:covers` annotations. `origin` is nil for the
        # method's own branches, or the helper method name when inlined from a
        # single-use private method. `detail` is an optional semantic qualifier
        # (e.g. "b decides", "assigns") applied only when the plain label collides
        # with another branch — see #disambiguate.
        Branch = Struct.new(:kind, :label, :line, :origin, :detail) do
          # The string an author types after `# rspec_parity:covers` to claim this
          # branch. The origin prefix disambiguates identical conditions in
          # different helpers; it is optional when the condition is unique.
          def annotation_token
            origin ? "#{origin}: #{label}" : label
          end
        end

        # Collection of Branch descriptors. Exposes the guard/regular/total/+
        # interface the rest of the cop (and PrivateMethodCallGraph) relies on —
        # a sequence of guard clauses (`return/raise/next ... if/unless`) shares
        # a single "all guards pass" fall-through counted once per method (see
        # #branches_from) rather than once per guard. `with_origin` tags inlined
        # branches as the call graph descends into single-use helpers.
        class BranchTally
          attr_reader :branches

          def initialize(branches = [])
            @branches = branches
          end

          def +(other)
            BranchTally.new(branches + other.branches)
          end

          def guard
            branches.count { |branch| branch.kind == :guard }
          end

          def regular
            branches.count { |branch| branch.kind == :regular }
          end

          def total
            branches.size
          end

          def with_origin(name)
            BranchTally.new(branches.map do |branch|
              branch.origin ? branch : Branch.new(branch.kind, branch.label, branch.line, name, branch.detail)
            end)
          end
        end

        # Node types whose presence as a one-armed `if` body makes it a guard clause.
        GUARD_TERMINATOR_TYPES = %i[return break next redo retry].freeze

        def initialize(config = nil, options = nil)
          super
          @ignore_memoization = cop_config.fetch("IgnoreMemoization", true)
          @trace_single_use_private = cop_config.fetch("TraceSingleUsePrivateMethods", true)
          @covers_annotations = cop_config.fetch("CoversAnnotations", true)
          @call_graphs = {}.compare_by_identity
        end

        def on_def(node)
          check_method(node)
        end

        def on_defs(node)
          check_method(node)
        end

        # ---- Tooling API (used by CoverageReporter / the rspec-parity-cover CLI) ----

        # Every counted branch for a method node, including those traced from
        # single-use private helpers. Empty when the method has fewer than two
        # branches or is excluded. Also aliased as +all_branches+ for callers that
        # want the full set regardless of spec coverage.
        def branch_inventory_for(method_node)
          return [] if excluded_method?(method_name(method_node))

          tally = branch_tally(method_node)
          if @trace_single_use_private
            extra = inlined_branches(method_node)
            tally += extra.branch_tally if extra.branch_tally
          end
          return [] if branches_from(tally) < 2

          branch_inventory(tally, method_node)
        end
        alias all_branches branch_inventory_for

        # What's left to cover for a method, given the spec text:
        #   uncovered          — branches with no covering annotation
        #   annotated          — branches an annotation already claims (known-covered)
        #   unannotated_specs  — count of plain (un-annotated) examples/contexts whose
        #                        branch we can't determine
        # Nil when the method has no spec describe block or is already fully covered.
        CoverageGap = Struct.new(:uncovered, :annotated, :unannotated_specs, keyword_init: true)

        def coverage_gap(method_node, spec_content)
          inventory = branch_inventory_for(method_node)
          return nil if inventory.empty?

          build_gap(inventory, count_contexts_for_method(spec_content.to_s, method_name(method_node)))
        end

        def build_gap(inventory, coverage)
          matched, = match_annotations(inventory, coverage.annotations)
          covered = coverage.scenarios + matched.size
          return nil if covered.zero? || covered >= inventory.size

          CoverageGap.new(uncovered: inventory.reject { |branch| matched.include?(branch) },
                          annotated: matched, unannotated_specs: coverage.scenarios)
        end

        private

        def check_method(node) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          return unless in_covered_directory?
          return if excluded_method?(method_name(node))

          tally = branch_tally(node)
          traced_methods = []
          if @trace_single_use_private
            extra = inlined_branches(node)
            tally += extra.branch_tally if extra.branch_tally
            traced_methods = extra.traced_methods
          end
          branches = branches_from(tally)
          return if branches < 2 # Only check methods with branches

          class_name = extract_class_name(node)
          return unless class_name

          spec_files = find_valid_spec_files(class_name, expected_spec_paths)
          return if spec_files.empty?

          dual_access = node.def_type? && module_with_dual_access?(node)

          coverage = gather_coverage(node, class_name, spec_files, dual_access)
          inventory = branch_inventory(tally, node)
          matched, orphans = match_annotations(inventory, coverage.annotations)
          # Annotations only ever raise coverage: matched branches + un-annotated
          # scenarios + orphan claims (counted so a typo'd annotation never lowers
          # coverage below the un-annotated baseline).
          covered = coverage.scenarios + matched.size + orphans.size

          return if covered.zero? # Method has no specs at all - PublicMethodHasSpec handles this
          return if covered >= branches

          missing = branches - covered
          add_offense(node, message: build_message(
            node: node, branches: branches, missing: missing,
            traced_methods: traced_methods, inventory: inventory, matched: matched, orphans: orphans
          ))
        end

        def gather_coverage(node, class_name, spec_files, dual_access)
          if matches_skip_path? && count_public_methods(node) == 1
            # For single-method classes, count top-level contexts instead
            aggregate_coverage(spec_files) { |file| count_top_level_contexts(File.read(file), class_name) }
          else
            # Normal path: look for method describes
            aggregate_coverage(spec_files) do |file|
              count_method_contexts(File.read(file), method_name(node), dual_access: dual_access)
            end
          end
        end

        def aggregate_coverage(spec_files)
          spec_files.reduce(SpecCoverage.new(0, [])) do |acc, file|
            merge_coverage(acc, yield(file))
          end
        end

        def merge_coverage(first, second)
          SpecCoverage.new(first.scenarios + second.scenarios, first.annotations + second.annotations)
        end

        # The branches counted, sorted for stable output. Adds the synthetic
        # "all guards pass" fall-through so the inventory size matches the count,
        # then makes every token unique so one annotation covers exactly one branch.
        def branch_inventory(tally, node)
          inventory = tally.branches.dup
          if tally.guard.positive? && tally.regular.zero?
            inventory << Branch.new(:guard, "all guards pass", node.first_line, nil)
          end
          disambiguate(inventory.sort_by { |branch| [branch.line, branch.label] })
        end

        # Makes every token unique so one annotation covers exactly one branch.
        # First qualifies colliding branches that carry a semantic `detail` (e.g.
        # the operator vs. the whole condition, or `||=`'s two cases); then appends
        # a positional `(N)` to anything still identical (e.g. two `if`s with the
        # same condition). Plain, non-colliding labels are left untouched.
        def disambiguate(inventory)
          inventory = requalify(inventory) { |branch| branch.detail && "#{branch.label} (#{branch.detail})" }
          counter = Hash.new(0)
          requalify(inventory) do |branch|
            counter[branch.annotation_token] += 1
            "#{branch.label} (#{counter[branch.annotation_token]})"
          end
        end

        # Rewrites the label of each branch whose token still collides, using the
        # block's result (skips the rewrite when the block returns nil).
        def requalify(inventory)
          totals = inventory.group_by(&:annotation_token).transform_values(&:size)
          inventory.map do |branch|
            next branch if totals[branch.annotation_token] == 1

            new_label = yield(branch)
            new_label ? Branch.new(branch.kind, new_label, branch.line, branch.origin, branch.detail) : branch
          end
        end

        # Splits the spec's raw annotation labels into the inventory branches they
        # cover and orphans that match nothing. A bare condition matches a traced
        # branch when its label is unambiguous; otherwise the `origin:` prefix is
        # needed. One annotation covers *every* branch sharing that token — a
        # compound condition like `a && b` is counted as several MC/DC branches
        # but reads as a single thing to annotate.
        def match_annotations(inventory, raw_annotations)
          tokens = inventory.map(&:annotation_token).uniq
          label_tokens = inventory.group_by(&:label).transform_values do |branches|
            branches.map(&:annotation_token).uniq
          end
          matched_tokens, orphans = partition_annotations(raw_annotations, tokens, label_tokens)
          [inventory.select { |branch| matched_tokens.include?(branch.annotation_token) }, orphans]
        end

        def partition_annotations(raw_annotations, tokens, label_tokens)
          matched_tokens = Set.new
          orphans = []
          raw_annotations.each do |raw|
            label = normalize_label(raw)
            token = resolve_annotation(label, tokens, label_tokens)
            token ? matched_tokens << token : orphans << label
          end
          [matched_tokens, orphans]
        end

        # The inventory token an annotation label refers to: an exact token match,
        # or a bare condition whose origin is unambiguous. Nil when it matches none.
        def resolve_annotation(label, tokens, label_tokens)
          return label if tokens.include?(label)
          return label_tokens[label].first if label_tokens[label]&.one?

          nil
        end

        # rubocop:disable Metrics/ParameterLists
        def build_message(node:, branches:, missing:, traced_methods:, inventory:, matched:, orphans:)
          uncovered = @covers_annotations ? inventory.reject { |branch| matched.include?(branch) } : []
          return count_message(node, branches, missing) + traced_suffix(traced_methods) if uncovered.empty?

          if missing > MANY_UNCOVERED_BRANCHES
            return many_message(node, branches, missing) + orphan_suffix(orphans, inventory)
          end

          coverage_message(preferred_example(uncovered), branches, missing) +
            traced_suffix(traced_methods) + orphan_suffix(orphans, inventory)
        end
        # rubocop:enable Metrics/ParameterLists

        def traced_suffix(traced_methods)
          traced_methods.any? ? format(TRACED_SUFFIX, traced: traced_methods.join(", ")) : ""
        end

        def count_message(node, branches, missing)
          format(COUNT_MSG, method_name: method_name(node), missing: missing,
                            branches: branches, branch_word: pluralize("branch", branches))
        end

        def many_message(node, branches, missing)
          format(MANY_MSG, missing: missing, branches: branches,
                           branch_word: pluralize("branch", missing),
                           location: "#{source_file_path}:#{node.first_line}")
        end

        def coverage_message(branch, branches, missing)
          format(COVERAGE_MSG, token: branch.annotation_token, location: branch_location(branch),
                               missing: missing, branches: branches, branch_word: pluralize("branch", branches))
        end

        # Prefer a branch with a real condition label over an `else`/guard
        # fall-through so the showcased annotation reads clearly; fall back to the
        # first.
        def preferred_example(branches)
          branches.find { |branch| !unhelpful_example?(branch.label) } || branches.first
        end

        def unhelpful_example?(label)
          label == "all guards pass" || label.start_with?("else")
        end

        def branch_location(branch)
          branch.origin ? "#{branch.origin} line #{branch.line}" : "line #{branch.line}"
        end

        def orphan_suffix(orphans, inventory)
          orphans.uniq.map do |label|
            nearest = nearest_label(label, inventory)
            hint = nearest ? " — did you mean `#{nearest}`?" : "."
            format(ORPHAN_SUFFIX, label: label, hint: hint)
          end.join
        end

        def nearest_label(label, inventory)
          return nil if inventory.empty?

          DidYouMean::SpellChecker.new(dictionary: inventory.map(&:annotation_token)).correct(label).first
        end

        def inlined_branches(node)
          container = find_class_or_module(node)
          return PrivateMethodCallGraph::Result.new(nil, []) unless container

          graph = (@call_graphs[container] ||= PrivateMethodCallGraph.new(container))
          graph.inlinable_from(node, method(:branch_tally))
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
          path.include?("/app/") || path.match?(%r{^app/})
        end

        def excluded_method?(method_name)
          return true if EXCLUDED_METHODS.include?(method_name)

          EXCLUDED_PATTERNS.any? { |pattern| pattern.match?(method_name) }
        end

        def source_file_path
          processed_source.path
        end

        # Total scenario count from a tally. Guard clauses share one "all guards
        # pass" fall-through; count it once, but only when guards are the sole
        # branching — otherwise the happy path is already represented by the
        # other branches and adding it would over-count.
        def branches_from(tally)
          total = tally.total
          total += 1 if tally.guard.positive? && tally.regular.zero?
          total
        end

        def branch_tally(node)
          elsif_nodes = collect_elsif_nodes(node)
          guard_operators = collect_guard_condition_operators(node)

          branches = []
          node.each_descendant do |descendant|
            next if elsif_nodes.include?(descendant)
            next if should_skip_node?(descendant)

            branches.concat(branches_for(descendant, guard_operators))
          end

          BranchTally.new(branches)
        end

        # Descriptors contributed by a single AST node. Counts match the prior
        # integer tally exactly — each `+= N` became N descriptors — so existing
        # branch totals are unchanged; the descriptors just carry labels/lines.
        def branches_for(descendant, guard_operators)
          case descendant.type
          when :if then if_node_descriptors(descendant)
          when :case then case_branch_descriptors(descendant)
          when :and, :or then [boolean_operator_branch(descendant, guard_operators)]
          when :or_asgn, :and_asgn then asgn_branch_descriptors(descendant)
          when :send then send_branch_descriptors(descendant)
          else []
          end
        end

        def if_node_descriptors(node)
          if guard_clause?(node)
            [Branch.new(:guard, branch_label(node.condition), node.condition.first_line, nil)]
          else
            if_branch_descriptors(node)
          end
        end

        # An `&&`/`||` operator's own branch is the MC/DC scenario where its right
        # operand is decisive. Kept as the plain expression unless it collides with
        # the whole-condition branch, in which case `detail` qualifies it.
        def boolean_operator_branch(node, guard_operators)
          kind = guard_operators.include?(node) ? :guard : :regular
          Branch.new(kind, branch_label(node), node.first_line, nil, "#{branch_label(node.rhs)} decides")
        end

        # A guard clause is a one-armed `if`/`unless` whose single body exits the
        # method early (`return`/`raise`/`next`/`break`/...). Its non-exit path is
        # the shared fall-through, so it is not a branch of its own.
        def guard_clause?(node)
          return false unless node.if_type?

          present = [node.if_branch, node.else_branch].compact
          return false unless present.size == 1

          guard_terminator?(present.first)
        end

        def guard_terminator?(node)
          return false unless node
          return true if GUARD_TERMINATOR_TYPES.include?(node.type)
          return true if node.send_type? && (node.method?(:raise) || node.method?(:throw))
          return guard_terminator?(node.children.last) if node.begin_type?

          false
        end

        # The `&&`/`||` nodes that live inside a guard clause's condition. Each
        # such operator is a distinct way for the guard to fire (one scenario per
        # operand), so it counts as a guard branch rather than an "other" branch.
        def collect_guard_condition_operators(node)
          operators = Set.new
          node.each_descendant(:if) do |if_node|
            next unless guard_clause?(if_node)

            condition = if_node.condition
            next unless condition

            operators.add(condition) if condition.and_type? || condition.or_type?
            condition.each_descendant(:and, :or) { |op| operators.add(op) }
          end
          operators
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

        def send_branch_descriptors(node)
          return [] unless node.method?(:&) || node.method?(:|)

          [Branch.new(:regular, branch_label(node), node.first_line, nil)]
        end

        # if/else is 2 branches (the `if` condition + the trailing `else`
        # fall-through), each `elsif` adds one more.
        def if_branch_descriptors(node)
          descriptors = [condition_branch(node)]
          current = node
          while current&.if_type? && current.else_branch&.if_type?
            current = current.else_branch
            descriptors << condition_branch(current)
          end
          # Tie the else to its `if` condition so two separate if/else blocks get
          # distinct, individually-annotatable labels instead of two bare "else"s.
          descriptors << Branch.new(:regular, "else of #{branch_label(node.condition)}", node.first_line, nil)
          descriptors
        end

        def condition_branch(if_node)
          Branch.new(:regular, branch_label(if_node.condition), if_node.condition.first_line, nil)
        end

        # Each `when` clause is a branch, plus a default/else when present.
        def case_branch_descriptors(node)
          descriptors = node.when_branches.map do |when_node|
            label = normalize_label("when #{when_node.conditions.map(&:source).join(", ")}")
            Branch.new(:regular, label, when_node.first_line, nil)
          end
          descriptors << Branch.new(:regular, case_else_label(node), node.first_line, nil) if node.else_branch
          descriptors
        end

        def case_else_label(node)
          node.condition ? "else of case #{branch_label(node.condition)}" : "else of case"
        end

        # `||=` / `&&=` create 2 branches sharing the expression's source: the
        # target was already set, or the right-hand side is assigned. `detail`
        # tells them apart once #disambiguate sees the collision.
        def asgn_branch_descriptors(node)
          label = branch_label(node)
          [
            Branch.new(:regular, label, node.first_line, nil, "already set"),
            Branch.new(:regular, label, node.first_line, nil, "assigns")
          ]
        end

        def branch_label(node)
          normalize_label(node.source)
        end

        def normalize_label(text)
          text.gsub(/\s+/, " ").strip
        end

        def count_method_contexts(spec_content, mname, dual_access: false)
          base = count_contexts_for_method(spec_content, mname)
          alias_method_names(mname, dual_access).reduce(base) do |coverage, alias_name|
            merge_coverage(coverage, count_contexts_for_method(spec_content, alias_name))
          end
        end

        def alias_method_names(mname, dual_access)
          prefixes = dual_access ? ["#", "."] : ["#"]
          prefixes.flat_map { |prefix| describe_aliases_for("#{prefix}#{mname}") }
                  .map { |alias_desc| alias_desc.sub(/^[#.]/, "") }
                  .uniq.reject { |alias_name| alias_name == mname }
        end

        def count_contexts_for_method(spec_content, method_name)
          method_pattern = Regexp.escape(method_name)
          result = parse_spec_content(spec_content, method_pattern)

          scenarios = scenario_count(
            result.context_count, result.example_count,
            has_examples: result.has_examples, has_direct_examples: result.has_direct_examples
          )
          SpecCoverage.new(scenarios, result.annotations)
        end

        # A test scenario is the smaller unit between "a context block" and "an
        # `it`/`example`". A single context whose examples each exercise a branch
        # covers as many scenarios as it has examples, so the scenario count is
        # the larger of the context-based count and the raw example count. Empty
        # placeholder contexts (no examples) still count via the context-based
        # path, so this never under-counts relative to the old behaviour.
        def scenario_count(context_count, example_count, has_examples:, has_direct_examples:)
          context_based =
            if context_count.positive? && has_direct_examples
              context_count + 1
            elsif context_count.zero? && has_examples
              1
            else
              context_count
            end

          [context_based, example_count].max
        end

        # rubocop:disable Metrics/MethodLength
        def parse_spec_content(spec_content, method_pattern) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          in_method_block = false
          scan = ScanState.new(@covers_annotations)
          base_indent = 0

          spec_content.each_line do |line|
            current_indent = line[/^\s*/].length

            if matches_method_describe?(line, method_pattern)
              in_method_block = true
              base_indent = current_indent
              scan.reset_child_indent
              next
            end

            if in_method_block
              scan.exit_annotated_context(current_indent)
              next if scan.collect_standalone_annotation(line)
              next if scan.inside_annotated_context? # collapsed: belongs to one annotated branch

              if exiting_block?(line, current_indent, base_indent)
                in_method_block = false
              elsif nested_context?(line)
                scan.count_context(line, current_indent)
              elsif nested_example?(line)
                scan.count_example(line, current_indent)
              end
            elsif matches_context_pattern?(line, method_pattern)
              scan.count_named_context(line)
            end
          end

          scan.to_parsed_spec
        end
        # rubocop:enable Metrics/MethodLength

        def matches_method_describe?(line, method_pattern)
          line =~ /^\s*describe\s+['"](?:#|\.)?#{method_pattern}['"]/ ||
            line =~ /^\s*describe\s+:#{method_pattern}(?!\w)/
        end

        def matches_context_pattern?(line, method_pattern)
          line =~ /^\s*(?:context|describe)\s+['"](?:#|\.)?#{method_pattern}(?:\s|['"])/
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
          else "#{word}s"
          end
        end

        def memoization_pattern?(node)
          # Pattern: var ||= value (any target: ivar, lvar, hash element, etc.)
          return true if or_asgn_pattern?(node)

          # Pattern: return @var if defined?(@var)
          return true if defined_check_pattern?(node)

          # Pattern: @var = value if @var.nil? or similar
          return true if nil_check_pattern?(node)

          # Pattern: || inside ||= (which creates both :or and :or_asgn nodes)
          return true if or_inside_or_asgn_pattern?(node)

          false
        end

        # var ||= value (any target)
        def or_asgn_pattern?(node)
          node.or_asgn_type?
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

        # || inside ||= (||= generates both :or_asgn and :or child nodes)
        def or_inside_or_asgn_pattern?(node)
          node.or_type? && node.parent&.or_asgn_type?
        end

        def matches_skip_path?
          skip_paths = shared_skip_method_describe_paths
          return false if skip_paths.empty?

          path = processed_source.path
          return false unless path

          skip_paths.any? do |pattern|
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
          return SpecCoverage.new(0, []) unless describe_line_index

          # Count contexts/describes and examples at the top level (under class describe)
          base_indent = lines[describe_line_index].match(/^(\s*)/)[1].length
          scan = ScanState.new(@covers_annotations)

          lines[(describe_line_index + 1)..].each do |line|
            indent = line.match(/^(\s*)/)[1].length
            break if indent <= base_indent && !line.strip.empty? && line.match?(/^\s*(?:describe|context|end)/)

            next unless indent > base_indent

            scan.exit_annotated_context(indent)
            next if scan.collect_standalone_annotation(line)
            next if scan.inside_annotated_context?

            if line.match?(/^\s*(?:context|describe)\s+/)
              scan.count_context(line, indent)
            elsif line.match?(/^\s*(?:it|example|specify)\s+/)
              scan.count_example(line, indent)
            end
          end

          parsed = scan.to_parsed_spec
          scenarios = scenario_count(parsed.context_count, parsed.example_count,
                                     has_examples: parsed.has_examples, has_direct_examples: parsed.has_direct_examples)
          SpecCoverage.new(scenarios, parsed.annotations)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      end
    end
  end
end
