---
module: rule-metrics-telemetry
date: 2026-04-18
problem_type: integration_issue
component: shell_script
symptoms:
  - "SCHEMA_VERSION constant defined but not load-bearing at consumer boundary"
  - "Bash ERE vs Python re regex drift risk protected only by prose comments"
  - "flock subshell variable assignments silently escape outer scope"
root_cause: missing_consumer_side_contract_assertion
severity: medium
tags:
  - schema-versioning
  - shell-scripting
  - flock
  - regex-parity
  - telemetry
  - drift-prevention
synced_to:
  - one-shot
  - work
  - review
  - compound
---

# Learning: Schema versioning is only load-bearing when asserted at the consumer boundary

## Problem

PR #2573 drained 10 review-backlog issues against the rule-utility telemetry stack shipped in PR #2213. Several reviewers flagged a pattern-level concern:

- `SCHEMA_VERSION=1` was defined in `scripts/lib/rule-metrics-constants.sh` and emitted on every jsonl telemetry line + the aggregator's top-level output.
- The aggregator's own "self-check" (`jq -e '.schema == 1'`) was self-referential — it asserted against a value it had just written.
- The real consumer (`scripts/rule-prune.sh`) read `.rules[]` and `.first_seen` without ever checking `.schema`.

If the aggregator ever emitted schema 2 with a different rules shape, `rule-prune.sh` would silently produce garbage issues. The "schema version" was cosmetic.

A second failure mode surfaced in the same refactor: the rule_id validation regex is defined twice — bash ERE in `rule-prune.sh`, Python `re` in `lint-rule-ids.py`. Constants file couldn't host the regex string (bash and Python regex syntax differ), so the drift guard was a prose comment in both files. Prose comments don't fail CI.

## Solution

**(1) Consumer-side schema assertion.** Every downstream script reading the aggregator output gates on the expected schema version:

```bash
jq -e --argjson v "$SCHEMA_VERSION" '.schema == $v' "$METRICS" >/dev/null 2>&1 \
  || { echo "ERROR: $METRICS has unexpected schema (expected $SCHEMA_VERSION)." >&2; exit 3; }
```

This makes `SCHEMA_VERSION` load-bearing: a silent bump blows up loudly instead of producing garbage.

**(2) Active regex parity enforcement.** Replace prose drift comments with a test that fails if the two regexes disagree:

```python
CORPUS = [("hr-abc", True), ("xx-bad-prefix", False), ("hr-" + "a"*61, False), ...]

def test_parity_across_corpus(self):
    for rule_id, expected in CORPUS:
        py = bool(PY_RE.match(rule_id))
        sh = bash_match(rule_id)  # spawns bash with the exact ERE from rule-prune.sh
        self.assertEqual(py, expected)
        self.assertEqual(sh, expected)
```

21-row corpus. Catches drift automatically in CI. `bash_match` shells out to bash with the ERE pasted verbatim so a later regex edit in rule-prune.sh is covered.

**(3) flock subshell scope.** The original rotation block looked like:

```bash
archive="$REPO_ROOT/.claude/.rule-incidents-${ts}.jsonl"
(
  flock -x 9
  if [[ -f "${archive}.gz" ]]; then
    archive="$REPO_ROOT/.claude/.rule-incidents-${ts}-$(date -u +%H%M%S).jsonl"  # ← scoped to subshell
  fi
  cat "$INCIDENTS" >> "$archive"
  : > "$INCIDENTS"
) 9>>"$INCIDENTS"
gzip -f "$archive" 2>/dev/null || true  # ← sees OLD archive value, gzips nothing
```

The reassignment inside `( ... )` does not propagate to the parent shell. The outer `gzip` targeted the non-suffixed path, which didn't exist. Fix: uniquify BEFORE entering the subshell. General rule: if a variable is consumed after a subshell, assign it in the outer scope.

## Key Insight

A constant named `SCHEMA_VERSION` is not a schema contract. A schema contract is the set of places it is asserted. Three asymmetric cases map to three enforcement strategies:

| Concern | Ineffective approach | Load-bearing approach |
|---|---|---|
| Schema versioning | Write `.schema: 1` on output | Consumer reads and gates on expected value |
| Multi-language regex drift | Prose comment "keep in sync" | Parity test with shared corpus |
| Subshell variable scope | Assign inside `( ... )` for locality | Assign outside when outer scope consumes |

The common shape: **a mechanism is load-bearing only when the side that depends on it actively asserts it**. Writing the value is half the work; the consumer's explicit check is what converts a field into a contract.

## Session Errors

1. **flock rotation subshell-scope bug** — `archive=` reassigned inside `( flock -x 9; ... ) 9>>"$INCIDENTS"` did not propagate to the outer `gzip -f "$archive"`, which then targeted a non-existent path and T9 failed with `suffixed=0`. Recovery: moved uniquify `if` block BEFORE the flock subshell. Prevention: when a subshell + outer-command pair is used, keep variable assignments on the side whose scope the later consumer requires.

2. **Second-granularity rotation suffix was flake-prone** — review caught that `date +%H%M%S` can produce identical values for two rotations within the same second, causing T9 to intermittently fail on fast CI. Recovery: nanosecond suffix (`%H%M%S%N`) + `RULE_METRICS_ROTATE_SUFFIX` env override for deterministic test paths. Prevention: when an algorithm's correctness depends on timestamp uniqueness, pair higher-resolution clocks with a test-only env override.

## Cross-References

- Plan: `knowledge-base/project/plans/2026-04-18-refactor-drain-pr2213-review-backlog-plan.md`
- Related telemetry patterns learning: `knowledge-base/project/learnings/best-practices/2026-04-15-rule-utility-scoring-telemetry-patterns.md`
- Related negative-space tests learning: `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`
- PR #2573 (this refactor), closes #2253 #2254 #2255 #2256 #2257 #2259 #2260 #2261 #2262 #2263
- PR #2213 (original rule-utility scoring feature)
- PR #2486 (one-PR-many-closures pattern reference)
