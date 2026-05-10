---
date: 2026-05-10
issue: 3507
related_prs: [3156, 2213, 2876]
category: test-failures
---

# Cross-PR coupling: a fix in #3156 silently invalidated T4's positive precondition

## What happened

`scripts/rule-metrics-aggregate.test.sh` test T4 (`rule-prune candidates use fire_count`) began failing on `main` after PR #3156 merged. The failure is `saw_a=0 saw_b=0` — neither the rule the test wants flagged (Rule A, zero events) nor the rule it wants excluded (Rule B, applied events) appears in the prune candidate list.

T4 was originally written (under #2213/#2876) to assert two things together against `scripts/rule-prune.sh`:

1. **Negative (load-bearing):** Rule B with `applied` events (`hit_count=0`, `fire_count>0`) is NOT a candidate — this is the `hit_count → fire_count` predicate switch the test exists to guard.
2. **Positive (smoke):** Rule A with zero events (`fire_count=0`) IS a candidate — confirms candidates are emitted at all.

PR #3156 (`fix(rule-prune): skip rules with null first_seen instead of treating as stale`) added a `first_seen != null` filter to the prune predicate. This was the right fix — without it, a quarterly run after metrics initialization would propose retiring 41+ healthy rules whose `first_seen` had never been populated.

But the aggregator only sets `first_seen` when it observes an event for a `rule_id`, and there is no `event_type` that increments `first_seen` without also incrementing `fire_count` (deny / bypass / applied / warn all count toward `fire_count`). So under post-#3156 semantics, **a rule cannot simultaneously have `fire_count=0` AND non-null `first_seen` from the aggregator's own write path**. T4's positive precondition (Rule A IS a candidate) became provably unsatisfiable from event seeding alone — silently. The test went red, but the symptom (`saw_a=0 saw_b=0`) misled the issue reporter into hypothesizing recency-gate or env-var bugs in `rule-prune.sh`, neither of which were the actual cause.

## Why the coupling went undetected

- The failing test is NOT wired into `scripts/test-all.sh` or any GitHub workflow. `tests/scripts/test-rule-metrics-aggregate.sh` (different path, different fixture style) is the CI-invoked sibling. So the regression surfaces only at manual invocation of `bash scripts/rule-metrics-aggregate.test.sh`, not in PR gates.
- The PR description for #3156 documented the prune-side change but did not flag the test-coverage implication for upstream tests that asserted on the *old* candidate-emission semantic.
- T4 lives in `scripts/`, not `tests/`. PR #3156's pre-merge mental model of "tests" was the `tests/` tree (which was correctly updated), missing the script-adjacent suite.

## Fix

Drop T4's unreachable positive assertion. Keep the negative one (Rule B excluded — the load-bearing #2213/#2876 invariant). Add an inline comment naming PR #3156 and issue #3507 so the next author who touches `rule-prune.sh`'s `first_seen` filter sees the breadcrumb.

No changes to `scripts/rule-prune.sh` or `scripts/rule-metrics-aggregate.sh` — the fix is fixture/assertion-only.

## Pattern to remember

When a fix tightens a predicate to exclude a class of inputs, grep every test (across `tests/`, `scripts/`, and any `*.test.sh` siblings) for fixtures that *seed* that excluded class. A test that asserts the predicate now-excludes-X may be load-bearing; a test that asserts the predicate emits-something-from-X is now unsatisfiable and will go silently red. The cheapest gate is a fixture-class grep at PR-author time, before the predicate change merges.

Specifically for `rule-prune.sh`-class predicates: any test that seeds a rule with zero events and asserts the rule appears in candidates is now testing a path that cannot be reached from event seeding. Either the test seeds `first_seen` directly via crafted JSON (like `tests/commands/test-sync-rule-prune.sh` T4 does at line 91-93), or it must drop the positive assertion.

## Adjacent tests verified unaffected

- `tests/scripts/test-rule-metrics-aggregate.sh` T7 (malformed first_seen) asserts on the **aggregator-side** `summary.rules_unused_over_8w` predicate (different code path, includes null-first_seen rules). Not affected by #3156.
- `tests/commands/test-sync-rule-prune.sh` T4 (line 91-93) crafts JSON with `first_seen:$seen` (non-null, recent) explicitly — exercises the recency gate, not the null-first_seen filter. Not affected by #3156.
