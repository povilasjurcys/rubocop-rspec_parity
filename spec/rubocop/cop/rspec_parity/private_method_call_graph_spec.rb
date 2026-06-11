# frozen_string_literal: true

# The graph aggregates whatever the counter returns, as long as it responds to
# `+` and `total`. This stand-in mirrors that contract without depending on the
# cop's own BranchTally.
GraphTallyDouble = Struct.new(:total) do
  def +(other)
    GraphTallyDouble.new(total + other.total)
  end
end

RSpec.describe RuboCop::Cop::RSpecParity::PrivateMethodCallGraph do
  def parse_class(source)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
    processed.ast
  end

  def find_def(container_node, name)
    container_node.each_descendant(:def, :defs).find { |n| n.method_name.to_s == name }
  end

  def branch_counter
    lambda do |node|
      count = 0
      node.each_descendant do |descendant|
        case descendant.type
        when :if then count += 2
        when :case then count += descendant.when_branches.count
        end
      end
      GraphTallyDouble.new(count)
    end
  end

  describe "#dynamic_dispatch?" do
    it "returns false for a plain class" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call; end
          private
          def helper; end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be false
    end

    it "returns true when send is used with a non-literal arg" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(name); send(name); end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end

    it "returns false when send is used with a literal symbol" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call; send(:helper); end
          private
          def helper; end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be false
    end

    it "returns true for define_method" do
      ast = parse_class(<<~RUBY)
        class Foo
          define_method(:dyn) { 1 }
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end

    it "returns true for method_missing" do
      ast = parse_class(<<~RUBY)
        class Foo
          def method_missing(name, *); end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end

    it "returns true for class_eval with a string" do
      ast = parse_class(<<~RUBY)
        class Foo
          class_eval("def dyn; end")
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end

    it "returns true for method(:foo) references" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call; method(:helper); end
          private
          def helper; end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end

    it "returns true for symbol-to-proc block pass" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call; [1,2,3].map(&:helper); end
          private
          def helper; end
        end
      RUBY
      expect(described_class.new(ast).dynamic_dispatch?).to be true
    end
  end

  describe "#inlinable_from" do
    it "returns zero for a method with no callees" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call; 1; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally).to be_nil
      expect(result.traced_methods).to eq([])
    end

    it "inlines branches from a single-use private helper" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x)
            helper(x)
          end

          private

          def helper(x)
            x ? 1 : 2
          end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["helper"])
    end

    it "inlines branches transitively through a chain of single-use helpers" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); a(x); end
          private
          def a(x); b(x); end
          def b(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["b"])
    end

    it "does not inline a helper called from multiple places" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call_a(x); helper(x); end
          def call_b(x); helper(x); end
          private
          def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call_a"), branch_counter)
      expect(result.branch_tally).to be_nil
      expect(result.traced_methods).to eq([])
    end

    it "does not inline a public helper even if called once" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); helper(x); end
          def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally).to be_nil
    end

    it "inlines protected helpers" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); helper(x); end
          protected
          def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["helper"])
    end

    it "handles `private def foo` inline form" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); helper(x); end
          private def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["helper"])
    end

    it "handles `private :foo` declaration form" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); helper(x); end
          def helper(x); x ? 1 : 2; end
          private :helper
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["helper"])
    end

    it "skips branchless helpers from traced_methods but follows their callees" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); a(x); end
          private
          def a(x); b(x); end
          def b(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["b"])
    end

    it "handles diamond shapes — shared deep helper not inlined" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); a(x); b(x); end
          private
          def a(x); x ? c(x) : 0; end
          def b(x); x ? c(x) : 0; end
          def c(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      # a and b each contribute 2 branches; c is called twice so it does not inline
      expect(result.branch_tally.total).to eq(4)
      expect(result.traced_methods).to eq(%w[a b])
    end

    it "does nothing when dynamic dispatch is present in the class" do
      ast = parse_class(<<~RUBY)
        class Foo
          def call(x); helper(x); end
          def fancy(name); send(name); end
          private
          def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally).to be_nil
      expect(result.traced_methods).to eq([])
    end

    it "treats class methods as a separate namespace from instance methods" do
      ast = parse_class(<<~RUBY)
        class Foo
          def self.call(x); helper(x); end
          def helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      # def self.call -> helper resolves to a class-level helper, which doesn't exist; instance helper is unrelated
      expect(result.branch_tally).to be_nil
    end

    it "traces single-use private class methods" do
      ast = parse_class(<<~RUBY)
        class Foo
          def self.call(x); helper(x); end
          private_class_method def self.helper(x); x ? 1 : 2; end
        end
      RUBY
      graph = described_class.new(ast)
      result = graph.inlinable_from(find_def(ast, "call"), branch_counter)
      expect(result.branch_tally.total).to eq(2)
      expect(result.traced_methods).to eq(["helper"])
    end
  end
end
