---
title: "Extend retry-budget arbitration into test-fix-loop, review fix-rounds, and qa skills"
date: 2026-11-27
slug: feat-one-shot-extend-retry-budget-arbitration-slice2
branch: feat-one-shot-extend-retry-budget-arbitration-slice2
issue: 12526
---

# Plan: Extend retry-budget arbitration (slice 2)

## Overview

Slice 1 (PR #12815) wired the retry-budget ruling mechanism into `soleur:one-shot`: when a child skill halts with a `budget-capped` marker, the parent spawns a blank-context ruling agent that emits `continue` / `goto <phase>` / `fail`, and `retry-budget-ruling.sh` appends a ledger section to `session-state.md`. Slice 2 extends the same mechanism into the three skills that own their own iteration/fix-round surfaces — `soleur:test-fix-loop`, `soleur:review` (fix-rounds), and `soleur:qa` — so a budget-capped halt in any of them can be arbitrated the same way instead of terminating outright.

The mechanism is already self-contained: `plugins/soleur/scripts/retry-budget-ruling.sh` (the only parser), `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md` (the procedure), and the stop-hook marker. Slice 2 does **not** change the script; it adds the wiring (read the reference, run the procedure on a budget-capped halt) to the three target skills and makes the `phase` token set / `goto` allow-list cover their phases.

## Premise Validation

- Issue #12526 is open (slice 1 shipped via PR #12815). Verified via `gh issue view 12526 --json state,title`.
- `retry-budget-ruling.sh` exists at `plugins/soleur/scripts/retry-budget-ruling.sh` and its `--phase` allow-list (`phase_stored_ok`) is `""|plan|work|review|qa|test-fix-loop`, and the stdin classifier's `goto` allow-list is `plan|work|review|qa|test-fix-loop`. Both already name `qa` and `test-fix-loop`, so no script change is needed for the new goto targets — only the skills need to invoke the procedure.
- `one-shot/references/retry-budget-ruling.md` already documents `goto` semantics for `test-fix-loop` ("read SKILL.md and run that skill") and `qa` (step 5.5), so the parent-side mapping exists; the gap is that the three skills themselves do not *trigger* the ruling when *they* cap.

## Property List

1. A budget-capped halt inside `test-fix-loop`, a `review` fix-round, or `qa` can be arbitrated by the same ruling agent instead of terminating outright, matching one-shot's behavior.
2. The ruling's `goto` targets are constrained to phases earlier than the halt boundary; a not-earlier `goto` halts.
3. No second spawn after `ruling_spawn: used` is set (spent bit preserved).
4. The three skills' existing termination/reset semantics are unchanged when the ruling resolves to `fail` or `continue`.

## Cut List

- No change to `retry-budget-ruling.sh`: the `phase`/`goto` allow-lists already cover `qa` and `test-fix-loop`; the script's identity/spent/empty-history gates are reusable as-is.
- No new registered agent: the ruling spawn stays the blank-context exception documented in the reference.
- No change to pipeline-tally: it already writes the `budget-capped` marker these skills read.

## Research Insights

- The ruling reference lives under `one-shot/references/` and is Read (not delivered by the skill loader), so `${CLAUDE_PLUGIN_ROOT}` is not substituted; consumers must resolve the root per the reference's header. Each target skill should link to it the same way one-shot does.
- `review` already has fix-round budget tallying (`risk-tier-and-fix-rounds.md` §3: `gate seats <N>` / `incr seats <N>` with `STOP` → classified-stop path writing `budget-capped`). That is the natural trigger point for the ruling.
- `test-fix-loop` gates `fix_rounds` per iteration (SKILL.md Phase 1) — the trigger point is the per-iteration `STOP`.
- `qa` has no explicit budget gate today; the plan must decide whether qa gains a tally gate or only consumes a parent's capped marker. Recommend: qa gains a lightweight `qa` dimension? The script has no `qa` dimension in pipeline-tally (dimensions are seats/ci_cycles/fix_rounds/agent_rounds). qa's budget surface is the parent's `agent_rounds`/`seats`; the ruling trigger is the parent one-shot halt, not a qa-local cap. So qa's wiring is: when one-shot (or a caller) hits a capped halt at the qa step, invoke the ruling with `--phase qa` — which the reference already supports. The skill itself documents the halt handling.

## Files to Edit

- `plugins/soleur/skills/test-fix-loop/SKILL.md` — add a "Retry-budget ruling" subsection in Phase 1 pointing at the reference and defining the trigger (per-iteration `STOP` on `fix_rounds`) and the apply-verb mapping; keep existing reset semantics on `fail`/`continue`.
- `plugins/soleur/skills/review/SKILL.md` — add the same wiring to the fix-rounds section (trigger: classified-stop on `seats`); add reference link.
- `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` — add the ruling trigger + apply-verb note next to the tally bullet.
- `plugins/soleur/skills/qa/SKILL.md` — add a "Retry-budget ruling" section documenting halt handling when invoked under a capped parent (`--phase qa`), and the not-earlier goto rule; tighten two verbose notes so `qa/SKILL.md` stays within its 37,000-byte lifecycle ceiling (`lint-skill-body-budget.py`).
- `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md` — note slice 2 callers (`test-fix-loop`, `review` fix-rounds, `qa`) in the opening trigger sentence (`one-shot/SKILL.md` already carries both canonical cues at 51,999 / 52,000 bytes from slice 1 and is left byte-unchanged).

## Files to Create

- `plugins/soleur/skills/test-fix-loop/references/retry-budget-ruling.md` — a thin skill-local pointer (or reuse the one-shot reference via relative link). Prefer reusing the canonical reference to avoid drift; create only if a skill-local wrapper is needed for path resolution. Decision: reuse canonical via `${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/retry-budget-ruling.md` link; no new file. (Listed here to record the decision.)
- Optional: `plugins/soleur/skills/qa/references/retry-budget-ruling.md` — same decision: reuse canonical.

## Implementation Phases

### Phase A — test-fix-loop wiring
1. Read the canonical reference path resolution header; add a "Retry-budget ruling (on a budget-capped halt)" block after the Phase 1 tally bullet.
2. Define trigger: the existing per-iteration `STOP` on `fix_rounds`. Under parent `one-shot`, exit after writing `budget-capped` so the parent runs the ruling once (`--phase test-fix-loop`); standalone, run the ruling procedure with `--phase test-fix-loop` to record the ruling ledger before halting. Per the canonical phase order (`plan` < `work` < `review` < `qa` < `test-fix-loop`), `goto` targets must be strictly earlier than the halt boundary: under parent `one-shot`, `plan`/`work`/`review`/`qa` are earlier while `goto test-fix-loop` is not earlier and halts (`capped=fix_rounds` stays set); in a standalone `test-fix-loop` run with no parent pipeline, any `goto` halts because no earlier phase exists in-process.
3. Apply verb: `continue` → run no unit, preserve commits, later halt is spent; `goto <earlier-phase>` → parent `one-shot` re-enters that earlier phase (sticky capped line does not re-trigger until the action starts); `fail` → today's halt with existing reset rules.
4. Keep existing termination/reset semantics (Max iterations, Regression, etc.) untouched when ruling resolves to `fail`/`continue`.

### Phase B — review fix-rounds wiring
1. In `risk-tier-and-fix-rounds.md` §3 and `review/SKILL.md`, after the classified-stop path (`STOP` on `seats`), wire the ruling with `--phase review` (under parent `one-shot`, return after writing `budget-capped` so the parent evaluates the single ruling once; standalone, run the ruling to record the ledger before halting).
2. `goto` targets strictly earlier than a `--phase review` halt: `plan`/`work` are earlier (under a parent pipeline; standalone halts on any `goto`); `review`, `qa`, and `test-fix-loop` are not earlier (halt, since `capped=seats` stays set). Document.
3. `continue`/`fail` as above; fix-round seats tally unchanged.

### Phase C — qa wiring
1. Add a section to `qa/SKILL.md` documenting: when qa runs under a capped parent and halts at the qa step, the parent invokes the ruling with `--phase qa`; qa itself does not own a tally dimension.
2. `goto` targets earlier than qa: `plan`/`work`/`review` are earlier; `test-fix-loop` and `qa` are not earlier (halt).
3. Link to canonical reference.

### Phase D — consistency
1. Update `one-shot/references/retry-budget-ruling.md` trigger header to include slice-2 callers (`test-fix-loop`, `review` fix-rounds, `qa`), keeping `one-shot/SKILL.md` within its 52,000-byte ceiling (`python3 scripts/lint-skill-body-budget.py --base origin/main`).
2. Run `bun test plugins/soleur/test/components.test.ts` (description budget) and `bash plugins/soleur/scripts/retry-budget-ruling.test.sh` — verify no regression.
3. Verify `phase_stored_ok`/goto allow-list already include needed tokens (done in premise validation).

## Test Scenarios

- integration: Given the updated skill files (`test-fix-loop/SKILL.md`, `review/SKILL.md`, `review/references/risk-tier-and-fix-rounds.md`, `qa/SKILL.md`), when `grep -l "retry-budget-ruling"` and `python3 scripts/lint-skill-body-budget.py --base origin/main` run, then all four files match `retry-budget-ruling` (the three `SKILL.md` files carry `[retry-budget-ruling.md](${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/retry-budget-ruling.md)` and `review/references/risk-tier-and-fix-rounds.md` delegates via `review/SKILL.md` to preserve W4a/W4b non-Read-surface status) and all 10 lifecycle skills pass their byte ceilings.
- unit: Given `plugins/soleur/scripts/retry-budget-ruling.test.sh`, when the test suite runs, then all 495 assertions pass and `retry-budget-ruling.sh` is unmodified.

No end-to-end browser scenario (no UI surface; `no-test-scenarios` for Browser/API steps).

## Acceptance Criteria

- [x] `test-fix-loop/SKILL.md` contains a "Retry-budget ruling" section referencing the canonical reference and defining the trigger + apply-verb mapping.
- [x] `review/SKILL.md` and `review/references/risk-tier-and-fix-rounds.md` contain the same wiring for fix-rounds.
- [x] `qa/SKILL.md` contains a "Retry-budget ruling" section for the qa step.
- [x] No change to `retry-budget-ruling.sh` (verify via git diff).
- [x] `bun test plugins/soleur/test/components.test.ts` and `python3 scripts/lint-skill-body-budget.py --base origin/main` pass.
- [x] Each skill's existing termination/reset behavior is preserved (no removal of reset rules).

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering

**Status:** reviewed
**Assessment:** Pure skill-doc wiring; no new infrastructure, no regulated data. Engineering review confirms the `phase`/`goto` allow-lists already cover `qa` and `test-fix-loop`, so no script change is required. Recommend a follow-up test that asserts the three SKILL.md files contain the ruling reference link (guard-style), but that is out of scope for slice 2.

## User-Brand Impact

**If this lands broken, the user experiences:** a budget-capped halt in test-fix-loop/review/qa terminates outright instead of offering arbitration — same as pre-slice-1 one-shot, no data loss.
**If this leaks:** N/A (no data surface).
**Brand-survival threshold:** none

## Observability

liveness_signal: n/a (docs-only skill change; no runtime surface)
error_reporting: n/a
failure_modes: []
logs: n/a
discoverability_test:
  command: grep -R "retry-budget-ruling" plugins/soleur/skills/test-fix-loop/SKILL.md plugins/soleur/skills/review/SKILL.md plugins/soleur/skills/qa/SKILL.md
  expected_output: "retry-budget-ruling"

## Scope Check

### Ask Mapping

| Ask (from issue #12526 / feature description) | Status | Plan item |
|---|---|---|
| Extend retry-budget arbitration into test-fix-loop | mapped | Phase A |
| Extend retry-budget arbitration into review fix-rounds | mapped | Phase B |
| Extend retry-budget arbitration into qa | mapped | Phase C |
| Reference existing mechanism (script + reference + stop-hook) | mapped | Premise Validation + Files to Edit |

### Plan-Item Provenance

| Plan item | Provenance | Justification |
|---|---|---|
| Phase A test-fix-loop wiring | asked | issue #12526 |
| Phase B review fix-rounds wiring | asked | issue #12526 |
| Phase C qa wiring | asked | issue #12526 |
| Phase D consistency (one-shot cross-ref) | inferred | keeps goto map coherent; no new behavior |

### Split Assessment

Recommendation: keep as single slice (slice 2 of #12526); no split needed — all three targets share one mechanism and one reference doc.
