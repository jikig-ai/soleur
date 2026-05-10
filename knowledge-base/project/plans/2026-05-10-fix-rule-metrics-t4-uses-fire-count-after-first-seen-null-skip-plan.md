---
issue: 3507
branch: feat-one-shot-3507-rule-metrics-t4
type: bug
classification: test-fix
requires_cpo_signoff: false
---

# fix(scripts): T4 in rule-metrics-aggregate.test.sh fails after rule-prune null-first_seen skip (#3507)

## Overview

`scripts/rule-metrics-aggregate.test.sh` test T4 (`rule-prune candidates use fire_count`) fails on main:

```
FAIL: T4 rule-prune candidates wrong (saw_a=0 saw_b=0)
  candidates: No prune candidates (fire_count=0 for >=0w).
```

T4 asserts two things together:

1. Rule B (which has `applied` events → `hit_count=0`, `fire_count>0`) is NOT listed as a prune candidate. **(still valid, still load-bearing)**
2. Rule A (which has zero events → `fire_count=0`) IS listed as a prune candidate. **(no longer reachable under current `rule-prune.sh` semantics — the fixture cannot satisfy the precondition)**

The second assertion stopped being reachable after PR #3156 (`fix(rule-prune): skip rules with null first_seen instead of treating as stale`) tightened the prune predicate from "any zero-fire rule" to "any zero-fire rule whose first_seen is non-null AND older than the cutoff." Under the previous semantic, a null `first_seen` was treated as `epoch 0 < cutoff` (i.e., "ancient"), so a rule with no events at all was flagged as stale on the first quarterly run. PR #3156 fixed that production-severity bug by excluding null-first_seen rules from candidate selection. T4's "Rule A IS a candidate" precondition required the pre-#3156 semantic.

The aggregator only sets `first_seen` when it observes an event for a rule_id. There is no event_type that increments `first_seen` without also incrementing `fire_count` (deny / bypass / applied / warn all count toward `fire_count`). Therefore: under post-#3156 semantics, **a rule cannot simultaneously have `fire_count=0` AND non-null `first_seen` from the aggregator's own write path**. T4's positive assertion is provably unsatisfiable from event seeding alone.

This plan keeps T4's load-bearing assertion (the `hit_count → fire_count` predicate switch in `rule-prune.sh` — the original #2866 invariant) and drops the unreachable positive assertion, with a comment explaining why and pointing to PR #3156 + the present issue.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #3507) | Codebase reality | Plan response |
| --- | --- | --- |
| "T4 short-circuits to `No prune candidates` before the fire_count predicate is evaluated" — implies the predicate is broken or the env var is broken | The predicate is correct; what changed is an *upstream* `first_seen != null` filter (PR #3156) that excludes Rule A (zero events → null first_seen) from candidate selection. Rule B is correctly excluded by the fire_count predicate, exactly as T4 intends. | Reframe the fix: don't restore the unreachable positive assertion (`saw_a=1`). Update the test's expectation to match post-#3156 semantics — assert only that Rule B is excluded. |
| "Either the recency gate broke (week-0 floor is misclassifying ancient timestamps as recent), OR `RULE_METRICS_ROOT` env override stopped propagating after a refactor." | Neither hypothesis is correct. `RULE_METRICS_ROOT` propagates correctly (`scripts/rule-prune.sh:52` reads it before all gates). The recency gate is intentionally tighter, not broken. | Document the actual cause in the PR description and in a learning file. |
| "Root cause documented in PR description" (acceptance criterion) | n/a — work to do | Phase 4 PR-body acceptance criterion. |

## User-Brand Impact

**If this lands broken, the user experiences:** the `rule-metrics-aggregate.test.sh` suite fails in CI / pre-commit, blocking unrelated PRs. No production user impact — this script runs only against the operator's local `.claude/.rule-incidents.jsonl` and the quarterly `scheduled-rule-prune.yml` workflow.

**If this leaks, the user's data is exposed via:** N/A — test-fixture-only change with no credential surface.

**Brand-survival threshold:** none — this is a developer-tooling test fixture. Not a production code path; does not touch credentials, auth, payments, or user-owned resources.

## Hypotheses

(Not applicable — feature description does not match `1.4 Network-Outage Hypothesis Check` triggers. Skipped.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] T4 passes locally: `bash scripts/rule-metrics-aggregate.test.sh` exits 0 with `PASS=19 FAIL=0` (or equivalent — exact PASS count depends on how T4's assertions are restructured; see Phase 2).
- [ ] T4's load-bearing invariant (Rule B with `applied` events is NOT listed as a prune candidate, isolating the `hit_count → fire_count` switch from PR #2213/#2876) is still asserted.
- [ ] T4 has an inline comment naming PR #3156 (or the post-#3156 semantic) as the reason the positive `saw_a=1` assertion was dropped, with a one-line breadcrumb to issue #3507.
- [ ] Confirmed pre-existing — running the test on `main` (commit `4b601ad5` or later) reproduces the `saw_a=0 saw_b=0` failure shown in the issue.
- [ ] No changes to `scripts/rule-prune.sh` or `scripts/rule-metrics-aggregate.sh` — the fix is fixture/assertion-only.
- [ ] `Closes #3507` on its own line in PR body (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] PR description names the root cause (PR #3156 tightened the prune predicate; T4's positive assertion is unsatisfiable under the new semantic).

### Post-merge (operator)

- [ ] None — test-only change, no operator action required.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returns zero matches for `scripts/rule-prune.sh`, `scripts/rule-metrics-aggregate.sh`, and `scripts/rule-metrics-aggregate.test.sh`.

## Files to Edit

- `scripts/rule-metrics-aggregate.test.sh` — restructure T4 to assert only the negative invariant, with a comment naming PR #3156.

## Files to Create

- `knowledge-base/project/learnings/2026-05-10-rule-prune-null-first-seen-skip-invalidates-positive-prune-candidate-fixture.md` — capture the cross-PR coupling: a fix in one PR (#3156) silently invalidated the precondition of an upstream test (T4) without flipping it red, because the test had been written before the fix and merged simultaneously. The directory + topic are prescribed; date is picked at write-time per the Sharp Edges rule on prescribed dates.

## Implementation Phases

### Phase 1 — Reproduce on main (pre-edit)

1. From the worktree, run `bash scripts/rule-metrics-aggregate.test.sh` and confirm output ends with `FAIL: T4 rule-prune candidates wrong (saw_a=0 saw_b=0)` followed by `PASS=18 FAIL=1 TOTAL=19`.
2. Capture this baseline in the PR body's "Reproduction" section. (Already verified at plan time; record output verbatim.)

### Phase 2 — Restructure T4 to match post-#3156 semantics

In `scripts/rule-metrics-aggregate.test.sh`, edit the `t4_rule_prune_uses_fire_count` function:

- Keep the fixture seeding (Rule B with one ancient `applied` event; no events for Rule A).
- Run aggregator + prune as before.
- **Replace the bash assertion block** (lines ~166-178 — the `saw_a=0 saw_b=0` block plus the "saw_a -eq 1 && saw_b -eq 0" check) with a single negative assertion: Rule B's id MUST NOT appear in `$candidates`. The positive Rule-A assertion is dropped.
- Add a comment block above the new assertion explaining the post-#3156 semantic and pointing to issue #3507. Suggested form:

  ```bash
  # NOTE: We assert only that Rule B is NOT a candidate (fire_count>0 → excluded
  # by the rule-prune predicate, the original #2213/#2876 invariant). We do NOT
  # assert that Rule A IS a candidate, because PR #3156 added a `first_seen != null`
  # filter to scripts/rule-prune.sh: a rule with zero events has null first_seen
  # and is correctly skipped (see rule-prune.sh:73-80 for rationale). The
  # aggregator's write path has no event_type that sets first_seen without also
  # incrementing fire_count, so a rule with fire_count=0 AND non-null first_seen
  # is unreachable from event seeding. See issue #3507 for the analysis.
  ```

- The new pass condition: `saw_b=0`. The new fail message: `FAIL: T4 rule-prune still flags Rule B despite applied events (fire_count switch broken)`. Bump the `PASS`/`FAIL` accounting accordingly.

### Phase 3 — Re-run the suite, confirm green

1. Run `bash scripts/rule-metrics-aggregate.test.sh` and confirm `FAIL=0`.
2. Confirm T1, T2, T3, T5 are unchanged in behavior. Specifically: T2 (which uses the same `fire_count` predicate inside the aggregator's `rules_unused_over_8w` summary, not via `rule-prune.sh`) must still PASS — this is the orthogonal coverage that protects the aggregator-side fire_count switch.

### Phase 4 — Compound + commit

1. Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
2. Stage `scripts/rule-metrics-aggregate.test.sh` and the new learning file.
3. Commit message:

   ```
   fix(scripts): T4 asserts only negative invariant after rule-prune null-first_seen skip (#3507)

   T4 in scripts/rule-metrics-aggregate.test.sh asserted both that Rule B
   (with applied events) was excluded from prune candidates AND that Rule A
   (with zero events) was included. The first assertion is the load-bearing
   invariant from #2213/#2876 (the hit_count → fire_count predicate switch).
   The second became unreachable after PR #3156 tightened scripts/rule-prune.sh
   to skip rules with null first_seen — and the aggregator has no event_type
   that sets first_seen without incrementing fire_count, so a rule with
   fire_count=0 AND non-null first_seen cannot be produced from event seeding.

   Drop the unreachable positive assertion. Keep the load-bearing negative one.
   Add a breadcrumb comment naming PR #3156 + issue #3507.

   Closes #3507
   ```

## Test Strategy

The test framework is bash-native (`set -euo pipefail` + manual `assert_eq` helpers — see `scripts/rule-metrics-aggregate.test.sh:53-65`). No new framework needed. The change is in the test file itself.

Verification: re-run `bash scripts/rule-metrics-aggregate.test.sh` from the repo root. Expected post-fix output: `PASS=N FAIL=0 TOTAL=N` where the N adjusts for the dropped positive assertion (reduces by exactly the number of `assert_eq` / inline-PASS bumps the old block contributed — a single PASS bump under the old code, so new total is `TOTAL=19` with the same PASS contribution swap; if T4 is reduced to a single conditional-PASS, then `TOTAL=19 PASS=19 FAIL=0`).

## Risks

- **Risk:** removing the positive assertion silently weakens T4's coverage. **Mitigation:** the load-bearing invariant (Rule B with applied events is NOT a prune candidate — i.e., the `hit_count → fire_count` switch is correctly applied in `rule-prune.sh`) remains asserted. The dropped assertion was orthogonal smoke (it confirmed candidate emission for any zero-fire rule, which is now provably unsatisfiable from event seeding).
- **Risk:** a future PR loosens `rule-prune.sh` to re-include null-first_seen rules (reverting #3156). **Mitigation:** the comment in T4 names #3156 and #3507, so a future author who reverts #3156 will see the comment and either restore the positive assertion or update the comment in the same PR. (We do NOT add a separate guard test for the null-first_seen filter — that's #3156's own concern; T4 stays focused on the fire_count switch.)
- **Risk:** the aggregator gains a new event_type or a new schema field that sets `first_seen` independently of `fire_count`. **Mitigation:** documented in the learning file. The learning is the breadcrumb; the test comment names #3156 as the trigger.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's threshold: `none`, with sensitive-path scope-out: this change touches only `scripts/rule-metrics-aggregate.test.sh`, which is not a sensitive path under preflight Check 6's regex.)
- Do not include a date in the prescribed learning filename — the directory + topic are prescribed; the author picks the date at write-time per `cq-rule-ids-are-immutable`-adjacent convention (Sharp Edges rule on dates in tasks.md).
- The PR title MUST NOT contain `Closes #3507` — only the body, on its own line, per `wg-use-closes-n-in-pr-body-not-title-to`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a test-fixture fix in a developer-tooling script. No user surface, no credential surface, no schema change, no infra change. Per `pdr-do-not-route-on-trivial-messages-yes`, single-domain self-routing (engineering test fix in an engineering session) does not warrant cross-domain leader spawn.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| **A. Drop the positive assertion** (chosen) | Minimal change. Keeps load-bearing invariant. Documents the cross-PR coupling. | Test coverage is narrower. | Chosen — the dropped assertion is unreachable, so "removing" it doesn't lose coverage. |
| **B. Revert PR #3156** to restore old null-first_seen-treated-as-ancient semantic | Restores T4 verbatim. | Reintroduces production bug — quarterly rule-prune workflow would propose retiring 41+ healthy rules on first run after a metrics initialization. Documented severe failure mode in `rule-prune.sh:73-80`. | Rejected. |
| **C. Extend aggregator to populate `first_seen` from an AGENTS.md scan timestamp instead of events** | Would let null-first_seen-AND-zero-fire-count rules exist again, restoring T4's premise. | Schema change. Breaks SCHEMA_VERSION assertion at consumer boundary (`rule-prune.sh:60`). Out of scope for #3507 (issue scope is "T4 fails", not "rework first_seen semantics"). Would need a separate plan, brainstorm, and migration of `rule-metrics.json`. | Rejected (out of scope; tracked here for completeness only). |
| **D. Add a third synthetic rule (Rule E) seeded with an event and assert it is excluded by some non-fire mechanism** | Could exercise more of `rule-prune.sh`'s filter logic. | Overengineered for a #3507-scope fix. T2 already asserts the aggregator-side `rules_unused_over_8w` predicate uses `fire_count`. T4's job is the prune-script-side switch — adding more rules dilutes the test's focus. | Rejected. |

## Non-Goals

- Reworking `rule-prune.sh` candidate-selection logic (PR #3156's design is correct; this issue is downstream of it).
- Reworking the `rule-metrics-aggregate.sh` schema or the `first_seen` write path.
- Adding new tests for the null-first_seen filter itself (that filter is #3156's concern; if it needs its own test, file a separate issue).
- Changing T1 / T2 / T3 / T5 — they are unaffected by the post-#3156 semantic.
- Anything in #3494 (token-efficiency analysis) — explicitly out of scope per the issue body.

## References

- Issue #3507 (this plan's target).
- PR #3156 — `fix(rule-prune): skip rules with null first_seen instead of treating as stale` — the upstream change that invalidated T4's positive assertion. The rationale lives at `scripts/rule-prune.sh:73-80`.
- PR #2213 — `feat(rule-utility): telemetry, weekly aggregator, and /soleur:sync rule-prune` — the original rule-metrics infrastructure.
- PR #2876 — `chore(telemetry): close rule-metrics emit_incident coverage gap` — added `applied` / `warn` event types and the `fire_count` predicate switch that T4 was written to verify.
- PR #3123 — `feat(rule-prune): scheduled quarterly retirement-proposal PR (C2)` — the workflow that exposed the null-first_seen-treated-as-ancient bug.
- `knowledge-base/project/learnings/best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md` — the SCHEMA_VERSION pattern used at `rule-prune.sh:60`.
- `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` — the broader retirement workflow this test gates.
