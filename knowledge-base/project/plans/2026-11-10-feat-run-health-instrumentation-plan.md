---
title: "Instrument one-shot and test-fix-loop to emit run_health.json + phase_prompts/"
date: 2026-11-10
slug: run-health-instrumentation
branch: feat-12532-degraded-run-forensics
issue: 12573
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Plan: run-health instrumentation (#12573)

## Overview

Phase 1 prerequisite for `session-retrospective-compound` (epic #12532). Neither `one-shot` nor `test-fix-loop` currently emits a structured run-health artifact. The forensic agent (#12574) and degraded-run trigger need a sealed, append-only record of what ran, when, with what prompt text, and whether it errored. This plan instruments both skills to emit `run_health.json` plus a `phase_prompts/` snapshot directory at every phase boundary, so a degraded run can be forensically reconstructed from disk rather than from self-report.

## Acceptance Criteria

- [ ] `run_health.json` schema documented (fields: run_id, issue, branch, harness, started_at, completed_at, status, phases[], errors[], reviewed_coverage)
- [ ] `phase_prompts/<phase>.md` snapshot written at each phase boundary in one-shot (steps 0–8) and test-fix-loop (phases 0–4)
- [ ] Emission is append-only / idempotent: re-running a phase updates the existing phase entry rather than duplicating
- [ ] Storage under a gitignored scratch path with TTL purge (per TR4); never committed
- [ ] Emission failures never block the pipeline (fail-open on write errors, logged)
- [ ] one-shot writes a final `status: completed|failed|budget-capped` with completed_at
- [ ] test-fix-loop writes terminal status + remaining failures on termination
- [ ] No regression in existing skill behavior / tests

## Files to Create

- `plugins/soleur/skills/one-shot/references/run-health-schema.md` — schema + emission contract
- `plugins/soleur/skills/test-fix-loop/references/run-health-schema.md` — (or shared) schema reference
- `plugins/soleur/scripts/run-health-emit.sh` — helper to upsert a phase entry into run_health.json and snapshot a prompt file

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md` — add emission calls at step boundaries (0b, 1-2, 3, 4, 5, 5.5, 6, 7, 8)
- `plugins/soleur/skills/test-fix-loop/SKILL.md` — add emission at phase boundaries (detect, loop iterations, termination)
- `.gitignore` — ensure `.soleur/runs/` (or chosen scratch path) is ignored

## Implementation Phases

### Phase A — Schema + helper script
Define `run_health.json` schema. Write `run-health-emit.sh` that accepts `--run-dir`, `--phase`, `--status`, `--prompt-file` and upserts. Make idempotent.

### Phase B — one-shot instrumentation
At each step boundary, call helper to record phase start/end + snapshot prompt. Final write sets status.

### Phase C — test-fix-loop instrumentation
Same pattern per phase.

### Phase D — tests
Add a smoke test that invokes helper and validates JSON schema.

## Scope Check

All asks from #12573 map to schema + helper + two skill edits. No inferred items.

## Research Insights

Premise validation: #12573 is open (verified). Brainstorm + spec confirm run-health emission is a hidden prerequisite (TR2). No existing run_health/phase_prompts references in either skill (grep confirmed).

Property List:
- P1: A degraded run leaves a recoverable on-disk record (run_health.json + phase_prompts/).
- P2: The record is produced by the executing skill, not self-reported after the fact.

Cut List: none — both skills need instrumentation; no existing mechanism covers it.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| run_health.json not emitted | confirmed absent (grep) | implement per this plan |
| phase_prompts/ not emitted | confirmed absent | implement per this plan |

## Open Code-Review Overlap

None.
---

## Notes

Storage path: `.soleur/runs/<run-id>/` under repo root (gitignored). run-id = `<branch>-<utc-timestamp>`. TTL purge via existing cleanup hooks (follow-up if needed).
