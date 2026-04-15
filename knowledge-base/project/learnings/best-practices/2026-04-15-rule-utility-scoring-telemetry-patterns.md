---
module: System
date: 2026-04-15
problem_type: best_practice
component: tooling
symptoms:
  - "AGENTS.md rules grew without signal about which earn their keep"
  - "Raw rule counts alone desensitize users to prune decisions"
  - "Hook denies were invisible — no way to count which guardrails actually fire"
root_cause: missing_tooling
resolution_type: tooling_addition
severity: medium
tags: [rule-utility, telemetry, flock, jsonl, aggregator, hooks, compound, agents-md]
synced_to: [plan, issue#2266]
---

# Rule Utility Scoring — Telemetry Patterns

PR #2213 introduced data-driven pruning signals for `AGENTS.md` rules. Four
reusable patterns fell out of the implementation worth capturing for future
telemetry work.

## Problem

`AGENTS.md` carries ~72 governance rules and `knowledge-base/project/learnings/`
has 500+ files. The `2026-04-07 rule-budget-false-alarm-fix` learning showed
that raw counts without utility data desensitize reviewers: rules that fire
daily look identical to rules that have never fired once. We needed a signal
telling us which rules earn their keep — without auto-retiring anything.

## Solution

Four moving pieces, plus a bunch of reusable patterns:

1. **Stable rule IDs** on every bullet (`[id: hr-<slug>]` etc.), backfilled via
   a PyYAML-free Python script with body-hash safety.
2. **Hook telemetry library** `.claude/hooks/lib/incidents.sh` that every
   existing hook sources; emits JSONL to `.claude/.rule-incidents.jsonl` on
   deny + bypass.
3. **Weekly aggregator** `scripts/rule-metrics-aggregate.sh` →
   `knowledge-base/project/rule-metrics.json` (committed).
4. **`/soleur:sync rule-prune`** files GitHub issues for zero-hit rules;
   explicit "does NOT authorize removal" body — humans prune, not automation.

## Reusable patterns

### Pattern 1: flock-guarded single-file JSONL telemetry (ADR-3)

Per-session files + rollup is overkill at ~10 events/day. A single
`flock -x`-guarded append-only file adds microseconds per hook invocation
and eliminates filename generation, weekly concat, 7-day truncation, and
CLAUDE_SESSION_ID fallback. Writer shape:

```bash
local line
line=$(jq -nc --arg ts "$ts" --arg r "$rule_id" ... '{...}' 2>/dev/null) || return 0
(
  flock -x 9
  printf '%s\n' "$line" >&9
) 9>>"$file" 2>/dev/null || true
```

Key details: build the JSON *outside* the flock subshell so only the append
is serialized; use `jq -nc` for guaranteed single-line output so lines
never interleave; wrap every jq invocation on external input in
`2>/dev/null || true` (learning 2026-03-18 TOCTOU).

### Pattern 2: Side-effect telemetry without contract change (ADR-2)

Claude Code's PreToolUse hook contract is `jq -n '{hookSpecificOutput: {...}}'
&& exit 0`. Adding fields (sibling keys or inside `hookSpecificOutput`) has
undefined behavior across CC versions. Instead: call
`emit_incident "<id>" "<event>" "<prefix>"` **before** the deny payload.
The hook response JSON is unchanged; telemetry is a pure side-effect write.

Use `${BASH_SOURCE[0]}` (not `$(dirname "$0")`) to resolve the library's
location when sourced — `$0` returns the caller, not the sourced file.

### Pattern 3: Tolerant JSONL parse with warning

`jq -s .` on a corrupt jsonl exits non-zero on the first malformed line,
poisoning every downstream run until a human repairs the file. Better:

```bash
valid_stream=$(jq -R 'fromjson? | select(.)' < "$file" 2>/dev/null || echo "")
bad_lines=$(( total_lines - $(echo "$valid_stream" | jq -s 'length') ))
[[ "$bad_lines" -gt 0 ]] && echo "::warning::Dropped $bad_lines malformed line(s)" >&2
```

`fromjson?` yields null on parse failure; `select(.)` drops nulls. Bad
lines are skipped with a visible warning (GitHub Actions picks up
`::warning::` as a workflow annotation).

### Pattern 4: Orphan bucket for hash-joined telemetry

When aggregating telemetry keyed by an ID that lives in a governance file
(AGENTS.md), any ID emitted to JSONL that isn't in the governance file
*silently vanishes from the aggregate*. Add a `summary.orphan_rule_ids[]`
surface so unknown IDs are visible rather than dropped:

```bash
($rules | map(.id)) as $known_ids |
($counts | keys | map(select(. as $id | ($known_ids | index($id)) | not))) as $orphan_ids
```

CI shape-check validates `summary.orphan_rule_ids` exists. Operators see
"hook emitted `cq-foo-bar` but that ID isn't in AGENTS.md" at aggregate
time instead of discovering it months later when someone wonders why a
specific bypass pattern has no metrics.

## Key Insight

**Telemetry designs must be resilient to both their own failures (jsonl
corruption, missing files) and to governance drift (IDs emitted that don't
exist anywhere). The worst failure mode is silent data loss; design every
layer to surface unknowns instead of dropping them.**

## Session Errors

**Test-slug assertion drift (backfill tests)** — My fixture-based tests
asserted `[id: hr-mcp-tools-resolve-paths-from-repo-root]` but `slugify`
actually produced `hr-mcp-tools-resolve-paths-from-the-repo` (the 40-char
word-boundary bound cuts "root" off "from the repo root").
**Recovery:** Updated assertions to match the actual slug.
**Prevention:** When asserting on slugs derived from a deterministic
function, either compute the expected value by calling the function or
use a regex (`assertRegex r"\[id: wg-use-closes-[a-z0-9-]+\]"`). Hand-
written slug strings in tests are fragile.

**`jq_counts='[]'` initial value (aggregator)** — Set empty default to an
array `[]`, but downstream code indexes via `$counts[$e.rule_id]` which
only works on objects. First empty-jsonl test failed with
"Cannot index array with string".
**Recovery:** Changed to `{}`.
**Prevention:** The sentinel's type must match the type the downstream
code expects. When sentinels are tricky (jq, yaml), write the sentinel
branch into the test-the-empty-case path explicitly.

**`jq -e empty` misleading exit** — `jq -e empty file.jsonl` returns exit
1 because `-e` interprets "no output" as falsy, even on valid JSON input
(`empty` filter produces no output by definition). Test reported FAIL
on the success path.
**Recovery:** Removed the `-e` flag.
**Prevention:** `jq empty` validates JSON — exits 0 on valid, non-zero
on malformed. `jq -e` tests truthiness of the last output. Never combine
them. If you want to validate-AND-fail-on-empty, use `jq -e '. | length > 0'`
or similar explicit check.

**Security-reminder hook false positive on workflow edits** — PreToolUse
hook on GitHub Actions YAML flagged `${{ github.server_url }}`,
`${{ github.repository }}`, and `${{ github.run_id }}` as "untrusted user
input" even though those are trusted GitHub context values. I had to
re-apply the same edit and move the metrics filename into an `env:` block
to satisfy the hook.
**Recovery:** Added `env: INCIDENTS_FILE: ...` block even though the path
was a static repo-local string.
**Prevention:** Route `github.server_url`, `github.repository`,
`github.run_id`, `github.ref`, and `github.workflow` through a whitelist
in `hooks/security_reminder_hook.py` — these are not user-controlled
fields and should not trigger the advisory.

**ID rename without repo-wide grep** — Renamed
`cq-lefthook-worktree-hang` → `cq-when-lefthook-hangs-in-a-worktree-60s`
in `incidents.sh` to match the existing AGENTS.md rule, but forgot to
update `tests/hooks/test_incidents.sh` and `tests/hooks/test_hook_emissions.sh`
assertions. Tests caught it.
**Recovery:** grep'd the old id, updated both test files.
**Prevention:** Before renaming any AGENTS.md rule ID, run
`grep -rn '<old-id>' .` (excluding `.git`) and update every call site in
the same commit. The `cq-rule-ids-are-immutable` rule in AGENTS.md only
covers AGENTS.md itself — not downstream references.

## Prevention

- Add a test for the `orphan_rule_ids` bucket in
  `tests/scripts/test-rule-metrics-aggregate.sh`: emit an event with an id
  not in the AGENTS.md fixture, assert it lands in `summary.orphan_rule_ids`.
- When renaming an AGENTS.md rule id, grep the whole repo before committing
  (consider a lefthook `rename-rule-id-check` that flags references to
  ids absent from the current AGENTS.md).
- Lift the security-reminder hook false-positive pattern into a whitelist
  issue (tracked separately).

## Cross-references

- Plan: `knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-rule-utility-scoring-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-rule-utility-scoring/spec.md`
- Inspiration: `knowledge-base/project/learnings/2026-04-07-rule-budget-false-alarm-fix.md`
- Hook source rule: [AGENTS.md `cq-rule-ids-are-immutable`](../../../AGENTS.md)
- Prior art (cron aggregator): `scripts/rule-audit.sh`,
  `.github/workflows/rule-audit.yml`
- Prior art (PyYAML migration): `scripts/backfill-frontmatter.py`
- Review findings: #2249 #2250 #2251 #2252 #2253-#2264
- Deferrals filed: #2238-#2243
