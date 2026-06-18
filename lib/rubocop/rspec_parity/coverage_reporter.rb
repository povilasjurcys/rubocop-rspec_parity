# frozen_string_literal: true

require "rubocop_rspec_parity"

module RuboCop
  module RSpecParity
    # Lists the branches a method still needs covered and renders ready-to-paste
    # `context '...' do # rspec_parity:covers <branch>` stubs. Backs the
    # `rspec-parity-cover` executable, reusing SufficientContexts' branch analysis.
    #
    # When the spec file exists, only branches without a covering annotation are
    # listed (and only for methods that aren't already fully covered). When it is
    # missing, every branch is listed so a new spec can be bootstrapped.
    class CoverageReporter
      Entry = Struct.new(:method_name, :branches, :spec_exists, :notes, keyword_init: true)

      # +line+ narrows the report to the single method enclosing that source
      # line, so `rspec-parity-cover file.rb:20` targets one method.
      def initialize(source_path, spec_path: nil, line: nil)
        @source_path = source_path
        @spec_path = spec_path || derive_spec_path(source_path)
        @line = line
        @cop = RuboCop::Cop::RSpecParity::SufficientContexts.new
      end

      def entries
        ast = parse
        return [] unless ast

        spec_content = File.read(@spec_path) if File.exist?(@spec_path)
        method_nodes(ast).filter_map { |node| entry_for(node, spec_content) }
      end

      def render
        entries.map { |entry| render_entry(entry) }.join("\n\n")
      end

      private

      def method_nodes(ast)
        nodes = ast.each_node(:def, :defs)
        return nodes unless @line

        # The method enclosing the target line (innermost wins if nested).
        nodes.select { |node| @line.between?(node.first_line, node.last_line) }
             .max_by(&:first_line)
             .then { |node| node ? [node] : [] }
      end

      def entry_for(node, spec_content)
        method_name = @cop.send(:method_name, node)
        return bootstrap_entry(node, method_name) unless spec_content

        gap = @cop.coverage_gap(node, spec_content)
        return unless gap

        Entry.new(method_name: method_name, branches: gap.uncovered, spec_exists: true, notes: notes_for(gap))
      end

      def bootstrap_entry(node, method_name)
        branches = @cop.all_branches(node)
        return if branches.empty?

        Entry.new(method_name: method_name, branches: branches, spec_exists: false, notes: [])
      end

      # FYI lines: what we already know is covered, and a caveat when there are
      # plain examples we can't attribute to a branch.
      def notes_for(gap)
        notes = []
        if gap.annotated.any?
          notes << "# already annotated as covered: #{gap.annotated.map(&:annotation_token).join(", ")}"
        end
        if gap.unannotated_specs.positive?
          notes << "# note: #{gap.unannotated_specs} example(s)/context(s) here aren't annotated, so we can't tell " \
                   "which branches they cover — all are listed below; drop or annotate the ones already tested."
        end
        notes
      end

      def render_entry(entry)
        count = entry.branches.size
        word = count == 1 ? "branch" : "branches"
        qualifier = entry.spec_exists ? "uncovered " : ""
        header = "# #{entry.method_name} — #{count} #{qualifier}#{word}:"
        # Every branch has a unique label, so one stub per branch (one annotation
        # covers exactly one branch).
        stubs = entry.branches.map { |branch| context_stub(branch.annotation_token) }
        [header, *entry.notes, stubs.join("\n\n")].join("\n")
      end

      def context_stub(token)
        ["context '...' do", "  # rspec_parity:covers #{token}", "", "  it '...' do", "  end", "end"].join("\n")
      end

      def parse
        RuboCop::ProcessedSource.new(File.read(@source_path), RUBY_VERSION.to_f, @source_path).ast
      end

      def derive_spec_path(path)
        path.sub(%r{(^|/)app/}, '\1spec/').sub(/\.rb\z/, "_spec.rb")
      end
    end
  end
end
