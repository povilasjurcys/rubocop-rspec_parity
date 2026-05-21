# Trace branches through single-use private methods

## Problem

`RSpecParity/SufficientContexts` currently counts branches only inside the body of the public method under inspection. When a public method is decomposed into private helpers — idiomatic Ruby style — the branches in those helpers don't count toward the required spec-context total. The cop effectively penalizes clean decomposition.

## Goal

When a private (or protected) method is called from exactly one place in the same class/module, treat its branches as belonging to the caller. Apply transitively: if public `P` calls single-use private `A` which calls single-use private `B`, `B`'s branches roll into `P`'s total.

## Configuration

Single key on `RSpecParity/SufficientContexts`:

```yaml
RSpecParity/SufficientContexts:
  TraceSingleUsePrivateMethods: true   # default
```

Set to `false` to restore the prior behavior.

No max-depth knob — depth is unlimited.

## Behavior

### What gets inlined

A private or protected method's branches roll into the caller's total when:

- the method is defined in the same class/module body as the caller
- it has exactly one static call site across the whole class/module body
- the enclosing class/module has no dynamic dispatch (see below)

Inlining is transitive: traversal follows the call graph from the public method, descending into any callee that satisfies the rules. A visited-set prevents double counting in diamond shapes and protects against mutual-recursion cycles.

Instance methods (`def foo`) and class methods (`def self.foo`) live in separate namespaces in the graph — a class method calling `bar` resolves only to a class-level `bar`.

### Dynamic dispatch — class-wide opt out

If the class/module body contains any of the following, the call graph is considered untrustworthy and **no inlining occurs anywhere in that class**:

- `send` / `public_send` with a non-symbol-literal argument
- `define_method`
- `method_missing` / `respond_to_missing?` definitions
- `class_eval` / `instance_eval` / `module_eval` with a string argument
- `method(:foo)` / `&:foo` (symbol-to-proc) references — these resolve methods symbolically and may extend reach beyond statically visible call sites

This is conservative by design — a false-positive "missing context" warning is worse UX than a missed inlining opportunity.

### Branchless helpers

A private method whose own body contributes zero branches:

- still has its callees traversed (it may call branchy helpers)
- is **not** named in the `traced_methods` list reported to the user
- doesn't count toward the user-visible "branches came from these methods" message

### Visibility tracking

The class-body walker recognizes all visibility forms:

- modifier `send` nodes — `public`, `private`, `protected` on their own lines
- declaration form — `private :foo, :bar`, `private_class_method :foo`
- inline form — `private def foo …` and `private_class_method def self.foo …`
- `class << self` blocks for class-method visibility

## Architecture

### New file: `lib/rubocop/cop/rspec_parity/private_method_call_graph.rb`

Class `RuboCop::Cop::RSpecParity::PrivateMethodCallGraph`.

**Constructor**

```ruby
PrivateMethodCallGraph.new(container_node)
```

`container_node` is the enclosing `:class`, `:module`, or `:sclass` AST node, or `nil` when the def is at top level (in which case nothing inlines).

**Public API**

```ruby
graph.dynamic_dispatch?
# => Boolean

graph.inlinable_from(method_node, branch_counter)
# branch_counter: a callable (->(node) { Integer })
# returns: Struct.new(:branches, :traced_methods)
#   branches        — total extra branches from reachable single-use helpers
#   traced_methods  — Array<String> of names of helpers that contributed > 0 branches,
#                     ordered by source position (deterministic)
```

**Internal data**

```
@methods = {
  [:instance, "foo"] => { node:, visibility: :private, callees: Set[[:instance, "bar"]] },
  [:class, "build"]  => { node:, visibility: :public,  callees: Set[…] },
  …
}

@call_count = { method_key => Integer }   # union-count across all methods' callees
```

The graph is built lazily on first use and memoized on the instance. `SufficientContexts` keeps one graph per container node (memoized via `node.equal?` identity).

### Changes to `SufficientContexts`

1. New instance var `@trace_single_use_private = cop_config.fetch("TraceSingleUsePrivateMethods", true)` in `initialize`.
2. New instance var `@call_graphs = {}.compare_by_identity` for per-container memoization.
3. In `check_method`, after computing `branches = count_branches(node)`:
   ```ruby
   traced_methods = []
   if @trace_single_use_private
     container = find_class_or_module(node)
     if container
       graph = (@call_graphs[container] ||= PrivateMethodCallGraph.new(container))
       extra = graph.inlinable_from(node, method(:count_branches))
       branches += extra.branches
       traced_methods = extra.traced_methods
     end
   end
   ```
4. Pass `traced_methods` into the message format. Update `MSG` to a base + optional suffix:
   ```ruby
   BASE_MSG = "Method `%<method_name>s` has %<branches>d %<branch_word>s but only " \
              "%<contexts>d %<context_word>s in spec. Add %<missing>d more %<missing_word>s " \
              "to cover all branches."
   TRACED_SUFFIX = " (including branches from: %<traced>s)"
   ```
   Append `TRACED_SUFFIX` only when `traced_methods` is non-empty.

### Config defaults

`config/default.yml` — add under `RSpecParity/SufficientContexts`:

```yaml
TraceSingleUsePrivateMethods: true
```

## Edge cases

- **Top-level defs** — no container → no inlining (graph is never built).
- **`include`d / inherited methods** — invisible; not in `@methods`; never inflate counts. Calls *to* such methods don't appear in any helper's `callees`, so they don't push another method's call count up either. Correct.
- **`super`** — doesn't reference a name we track. No effect on counts. Correct.
- **Mutual recursion** — `priv_a` calls `priv_b`, `priv_b` calls `priv_a`, both used once from `pub`. Call count for each is 2 (one from `pub`, one from the other). Neither inlines. Correct.
- **Diamond** — `pub` → `priv_a`, `pub` → `priv_b`, both call `priv_c`. `priv_c` call count is 2, doesn't inline. `priv_a` and `priv_b` each have call count 1 → do inline.
- **`private def foo …`** — at AST level this is a `:send` whose argument is the `:def`. Walker handles both: detects the `:def` child, registers visibility, recurses into the def body for callees.
- **`class << self`** — the `:sclass` body adds class-method entries with their own visibility state.
- **Method named the same as a Kernel method** (e.g. `format`) — call-site detection uses receiver=`nil` send nodes whose method name matches a defined method in the same container. Kernel calls without a same-named local def are not in `@methods` and are ignored.

## Testing

### New file: `spec/rubocop/cop/rspec_parity/private_method_call_graph_spec.rb`

Pure unit tests on the graph class — no RuboCop cop infrastructure. Parse a source string via `RuboCop::ProcessedSource`, get the class node, exercise the API. Covers:

- Empty class → graph returns 0 branches, no traced methods
- Single-use private with one branch → 1, [name]
- Two-deep chain → both contribute, both named
- Branchless intermediate → traversal continues, intermediate excluded from traced list
- Two-caller helper → not inlined
- Diamond → only single-use intermediates inline
- Mutual recursion → neither inlines
- Class method calling private class method → traced
- Class method calling instance method of same name → not linked
- `private def foo …` form recognized
- `private :foo` declaration form recognized
- Dynamic dispatch markers each trigger `dynamic_dispatch?`:
  - `send(var)` (non-literal)
  - `send(:foo)` with literal — does NOT trigger (literal symbol is safe — but per design we still treat it as dynamic because we can't statically prove the symbol set is closed; cover this in tests as a deliberate conservative choice — see Open Questions)
  - `define_method(:foo) { … }`
  - `method_missing` def
  - `class_eval("def x; end")`
  - `method(:foo)`
  - `&:foo` block argument

### Extensions to `spec/rubocop/cop/rspec_parity/sufficient_contexts_spec.rb`

- Public method with single-use private helper → reports inflated branch count, message includes helper name
- Multi-context spec satisfies inflated count → no offense
- Two callers of same helper → no inflation
- `TraceSingleUsePrivateMethods: false` config → behavior identical to current cop
- Class with dynamic dispatch → no inflation, no traced_methods in message
- Branchless helper that calls branchy helper → only branchy helper named in message

## Performance

Per file, RuboCop already parses and walks the AST. The new work is:

- One pass over each class/module body to populate `@methods` (linear in body size)
- One additional pass to count callees per method (linear in total send nodes)
- Per public-method check: DFS over reachable single-use helpers — bounded by total methods in the class

Class graphs are memoized by container identity, so a file with N public methods builds the graph once, not N times. Negligible compared to RuboCop's existing parsing and node-walking.

## Open questions resolved during design

- **Default value** — `true`. Opt-out rather than opt-in. The user accepts that existing users may see new offenses on their next gem update; the new behavior is more accurate.
- **Protected methods** — treated the same as private (still internal API).
- **Class methods** — same treatment as instance methods, separate namespace in the graph.
- **Symbol-to-proc / `method(:foo)`** — treated as dynamic dispatch (conservative). The set of method references through these forms is hard to bound statically, and the cost of being conservative is just "no inlining for this class" not "wrong behavior".
