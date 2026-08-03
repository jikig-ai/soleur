---
title: Tasks — neutralize the grep shim via a prefixed function redefinition (v2)
feature: feat-7165-grep-rewrite-updatedinput
issue: 7165
pr: 7167
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-02-feat-grep-rewrite-command-grep-plan.md
---

# Tasks (v2 — prefix design)

Phase numbers match the plan's phases exactly (v1's were off by one, breaking
AC-to-task traceability).

## Phase 1 — Preconditions (no code)

- [ ] 1.1 Isolated `claude -p` + throwaway `--settings`: `updatedInput` applies with no
      `permissionDecision`. Never touch the live session's settings.
- [ ] 1.2 Two-hook probe: sibling `deny` still wins.
- [ ] 1.3 **Merge-or-replace:** payload with `run_in_background`, `timeout`,
      `description` → assert all three survive. Build from full `tool_input` regardless.
- [ ] 1.4 **Re-entrancy:** is the rewritten command re-submitted to PreToolUse?
- [ ] 1.5 GNU grep accepts the injected flags; still errors on `-G` + `-E`.
- [ ] 1.6 Paste all results in the PR body.

## Phase 2 — Hook, observe-only

- [ ] 2.1 Create `.claude/hooks/grep-rewrite.sh` (**not** `-guard.sh`).
- [ ] 2.2 `SOLEUR_DISABLE_GREP_REWRITE` checked as the **first executable statement**,
      before any subprocess or lib sourcing.
- [ ] 2.3 Scalar-forced command extraction; no `eval` + `jq @sh` (TR5).
- [ ] 2.4 Idempotency sentinel check.
- [ ] 2.5 Sloppy `grep`-substring gate (a false positive costs an inert function def).
- [ ] 2.6 Build the prefix with all 12 shim bypass arms mirrored + the three heavy
      build dirs (D3 reversed: 5,446 ms → 590 ms measured).
- [ ] 2.7 Emit `emit_incident "grep-rewrite-would-rewrite"` and **no** `updatedInput`.
- [ ] 2.8 Every exit path `exit 0`. No `set -e` on the parse path.
- [ ] 2.9 `chmod +x`; confirm **index** mode 100755.
- [ ] 2.10 Register in `.claude/settings.json` with an explicit `timeout`.
- [ ] 2.11 No `| grep -q` anywhere (`grep-q-pipe-guard.test.sh` forbids it).

## Phase 3 — Corpus replay

- [ ] 3.1 Extract ~6,100 real Bash commands from session transcripts.
- [ ] 3.2 Replay through the hook; assert every diff is exactly the prefix insertion,
      remainder byte-identical, zero exceptions (AC5).
- [ ] 3.3 Investigate and record any exception before proceeding.

## Phase 4 — Flip live

- [ ] 4.1 Emit `updatedInput` built as `.tool_input | .command = $new` (AC4).
- [ ] 4.2 Assert `permissionDecision` appears nowhere at any depth; no top-level
      `decision`/`continue`. Handle empty and non-empty stdout separately (AC3).

## Phase 5 — Differential results

- [ ] 5.1 Synthesize a tree with `.git`, a binary file, and a gitignored dir.
- [ ] 5.2 Assert identical stdout original vs. prefixed for recursive greps (AC8).
- [ ] 5.3 Enumerate every accepted divergence in the ADR.

## Phase 6 — Gates

- [ ] 6.1 Fixture suite `.claude/hooks/grep-rewrite.test.sh` invoking `"$HOOK"`
      **directly** — not `bash "$HOOK"`, the path TR3 indicts.
- [ ] 6.2 Fail-open triad (AC10): empty stdin, non-JSON, no `.tool_input`, 1 MB binary,
      `jq` stubbed failing, `perl` stubbed failing → exit 0, empty stdout, one incident.
- [ ] 6.3 Idempotency fixed-point fixture (AC11).
- [ ] 6.4 Kill-switch fixture (AC12).
- [ ] 6.5 Seven bypass forms — `$G` and `eval "grep …"` now **rewrite** (AC6).
- [ ] 6.6 All 12 bypass arms get `command grep "$@"`, no injected flags (AC7).
- [ ] 6.7 Extend `.claude/hooks/hookeventname-coverage.test.sh`: exec-bit (non-empty +
      exactly `100755`), registration membership (AC14), single-rewriter (AC13).
      Derivation must assert a non-empty list with a minimum count; entries are
      quote-prefixed, `guardrails.sh` appears twice, one is `.py`.
- [ ] 6.8 Rewrite-inertness: original and prefixed produce identical decisions from
      every sibling Bash hook.
- [ ] 6.9 Latency: p95 < 50 ms on a 4 KB command (AC17).

## Phase 7 — Aggregator, docs, ADR/C4

- [ ] 7.1 `scripts/rule-metrics-aggregate.sh`: add the `grep-rewrite-` exclusion
      (untagged ids exit 5 at `:374`/`:426` and skip rotation).
- [ ] 7.2 Parallel test in `scripts/rule-metrics-aggregate.test.sh` (AC15).
- [ ] 7.3 `.claude/hooks/README.md`: §Hook contract gains the rewrite disposition;
      roster entry; §Escape-hatch inventory row for the kill switch.
- [ ] 7.4 Create `.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md`.
- [ ] 7.5 Author ADR-155 bounding the **authority** (mutable keys, single rewriter,
      never `permissionDecision`, idempotent, fail-open exit 0, permission matching on
      the original). Link the refuted cost models — do not restate them.
- [ ] 7.6 `model.c4`: relabel the `hooks` container + `hooks -> claude` relationship.
- [ ] 7.7 **Regenerate `model.likec4.json`**; `c4-model-freshness.test.sh` green (AC18).
- [ ] 7.8 If the ADR ordinal moves at ship time, sweep plan + tasks + ACs together.

## Phase 8 — Verification

- [ ] 8.1 AC1a/AC1b split: byte-exact emitted string, then that string under
      `ulimit -v 2000000` + `timeout`.
- [ ] 8.2 `bash scripts/test-all.sh` on the **scripts shard** (`:577` sits inside
      `if want_scripts`); assert new suites by name (AC16).
- [ ] 8.3 Walk AC1–AC18; paste evidence in the PR body.
