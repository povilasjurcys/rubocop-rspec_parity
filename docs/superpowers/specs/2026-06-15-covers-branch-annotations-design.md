# Pinpoint missing branches with `# rspec_parity:covers` annotations

## Problem

`RSpecParity/SufficientContexts` reports a bare numeric gap: "method has 21
branches but the spec covers only 20 scenarios." When the gap is 1 out of 21,
there is no way to tell *which* branch is uncovered. Both sides of the
comparison are pure counts — branches are tallied as integers from the AST, and
scenarios are tallied as integers from spec text — so there is no axis along
which a specific branch maps to a specific context.

## Goal

1. Make the offense name the branches it counted, so a human can reconcile the
   gap by eye instead of guessing.
2. Let authors *opt in* to precise per-branch tracking by tagging contexts with
   a `# rspec_parity:covers <label>` magic comment. Annotations are purely additive —
   they can only ever *help* (raise coverage / narrow the reported gap), never
   create a new violation and never make a passing method fail.
3. Report annotations that match no known branch (typos / renamed branches),
   with a did-you-mean suggestion.

## Configuration

```yaml
RSpecParity/SufficientContexts:
  CoversAnnotations: true   # default
```

Set to `false` to restore the prior numeric-only message and skip all
annotation handling.

## Concepts

### Branch descriptors

`branch_tally` stops returning integer counters and instead collects a list of
**branch descriptors**, one per counted branch:

```
Branch = Struct.new(:kind, :label, :line, :origin)
#   kind   — :guard or :regular (preserves the guard fall-through logic)
#   label  — the normalized condition/operator source (what you annotate with)
#   line   — source line of the branch
#   origin — nil for the method's own branches; the helper method name when the
#            branch was inlined from a single-use private method
```

`BranchTally` becomes a thin wrapper over an array of `Branch`, still exposing
`guard`, `regular`, `total`, and `+` so `branches_from` and
`PrivateMethodCallGraph` keep working unchanged. A new `with_origin(name)`
returns a copy with each not-yet-tagged descriptor's `origin` set — the call
graph tags descriptors as it inlines each helper.

### Labels

A label is the branch's source, whitespace-collapsed (`source.gsub(/\s+/, " ")
.strip`), case-sensitive. No truncation — the displayed label is exactly the
string you type into the annotation, so it is always copy-pasteable.

Per branch kind:

| AST | descriptors |
|-----|-------------|
| `if`/`elsif`/`else` (non-guard) | one per condition (`if`, each `elsif`) + `else of <if condition>` |
| guard `if`/`unless` | one, label = guard condition source, kind `:guard` |
| `case`/`when` | one per `when` + `else of case <subject>` (only if present) |
| `&&` / `\|\|` | one, label = operator source; carries `detail` `<rhs> decides` |
| `\|\|=` / `&&=` | two, label = `<src>`; carry `detail` `already set` / `assigns` |
| `&` / `\|` send | one, label = node source |

**Every branch ends up with a unique token, so one annotation covers exactly one
branch.** `#disambiguate` enforces this in two passes: branches whose plain token
still collides get their `detail` applied (`a && b` → `a && b (b decides)`,
`||=` → `… (assigns)`/`… (already set)`); anything still identical (e.g. two
`if`s with the same condition) gets a positional `(1)`, `(2)`. Non-colliding
labels (including standalone `&&`/`||` expressions) keep their plain source, so
they stay naturally typeable.

When a branch was inlined from a private helper, its annotation token is
prefixed with the origin: `admin_role?: role == 'admin'`. The prefix is
**optional when unambiguous** — typing just `role == 'admin'` matches when
exactly one branch has that condition; the prefix is only required to
disambiguate identical conditions in different helpers.

### Annotations

A trailing magic comment on a `context`/`describe`/`it`/`example`/`specify`
line:

```ruby
context 'when admin by role' do # rspec_parity:covers admin_role?: role == 'admin'
  it 'returns true'
end
```

- An annotated **context** collapses its inner examples: the whole block counts
  as the branch(es) it declares, *not* as N example scenarios. This overrides
  the "multiple `it`s = multiple scenarios" heuristic for that block — the
  author has explicitly said "this block is one branch."
- An annotated **example** counts as its own branch.
- One annotation may list several labels separated by `;` (semicolon — commas
  appear inside conditions). Or repeat the comment.
- The annotation may also be a **standalone comment line inside the context**
  (handy when a trailing comment would overflow the line length); it is
  attributed to the enclosing context. Place it before the context's examples.

## Coverage rule

```
covered = distinct_matched_annotations
        + numeric_scenarios(from the un-annotated parts only)

offense fires when  covered < branches      # same trigger as before
```

Annotations only raise `covered`. With zero annotations this reduces exactly to
today's `scenario_count` over the whole block.

## Messages (single line — RuboCop offense constraint)

Rather than listing every branch (unreadable for branchy methods), the message
names **one** still-uncovered branch and gives the exact context to add. Each
re-run advances to the next gap as branches get annotated.

**With annotations on** (the default):

```
Missing coverage for `user.staff?` (line 4) — 2 of 3 branches untested.
Add `context '...' do # rspec_parity:covers user.staff?` to mark it covered.
```

The showcased branch is the first uncovered one, preferring a real condition
over `else`/guard fall-through so the example reads clearly. A branch traced
from a helper shows its origin in the location (`helper line N`) and token
(`helper: condition`). The existing `(including branches from: …)` suffix still
appends when branches were inlined.

**With annotations off** — just the count, no annotation guidance:

```
Method `classify` is missing coverage for 9 of 10 branches.
```

**Orphan annotations** (appended when the method offends):

```
… `rspec_parity:covers` annotation `params[:admni]` matches no branch — did you
mean `params[:admin]`?
```

Nearest match via `DidYouMean::SpellChecker`; omit the "did you mean" clause
when nothing is close. An orphan annotation alone never triggers an offense
(opt-in): orphans are only reported when the method is already offending.

## Architecture

### `SufficientContexts`

- `initialize`: `@covers_annotations = cop_config.fetch("CoversAnnotations", true)`.
- `BranchTally` rewritten over `Branch` descriptors (`guard`/`regular`/`total`/
  `+`/`with_origin`/`branches`).
- `branch_tally`, `count_if_branches`→`if_branch_descriptors`,
  `count_case_branches`→`case_branch_descriptors`, `send_node_branch_count`,
  `or_asgn`/`and_asgn` handling all push descriptors.
- `branches_from` unchanged (operates on `guard`/`regular`/`total`).
- Spec parsing (`parse_spec_content`, `count_top_level_contexts`): collect
  trailing `# rspec_parity:covers` labels, suppress example counting inside annotated
  contexts, return labels + un-annotated numeric scenario count.
- `check_method`: compute `matched`/`unannotated`/`orphans` by intersecting
  annotation labels with the descriptor inventory; `covered = matched.size +
  unannotated_scenarios`; build the enriched message.
- New helpers: `match_annotations`, `nearest_label` (DidYouMean), message
  builders.

### `PrivateMethodCallGraph`

`visit_callee` tags the inlined tally: `tally = tally.with_origin(name) if
tally.respond_to?(:with_origin)`. No other change; the `Result`/traverse logic
is untouched.

### `config/default.yml`

Add `CoversAnnotations: true` under `RSpecParity/SufficientContexts`.

## Edge cases

- **`CoversAnnotations: false`** — message reverts to today's exact
  string; annotation comments are ignored entirely.
- **No spec annotations** — `matched` is empty, `unannotated_scenarios` equals
  today's `scenario_count`; coverage and trigger are identical to today. Only
  the message gains the inventory suffix.
- **Duplicate identical labels** (two branches, same source, same origin) — a
  single annotation covers both; acceptable for "good enough" precision and
  logged via the inventory line.
- **Annotated context with nested contexts** — the whole subtree collapses to
  the declared label(s).
- **Multi-line / very long condition** — collapsed to one line; long but exact
  and matchable.

## Testing

Extend `spec/rubocop/cop/rspec_parity/sufficient_contexts_spec.rb`:

- inventory appears in the message when no annotations exist
- a matching annotation removes a branch from the uncovered list / satisfies the
  count
- annotated context with several `it`s counts as one branch (collapse)
- optional origin prefix: bare condition matches when unambiguous
- orphan annotation reported with did-you-mean
- `CoversAnnotations: false` reproduces the legacy message
- interaction with `TraceSingleUsePrivateMethods` (origin-prefixed labels)

Existing message assertions are updated to the new output (captured from an
actual run).

## Open questions resolved

- **Default** — `true` (opt-out), consistent with `TraceSingleUsePrivateMethods`.
  The richer message is strictly more informative; annotations are additive.
- **Message is single-line** — RuboCop offense messages are single-line; the
  inventory is joined with `; ` rather than rendered as a list.
- **Annotations never trigger** — opt-in means an annotation can only narrow or
  satisfy; it never creates an offense.
