# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-19-fix-vacuity-floor-and-subagent-gate-plan.md
- Status: **recovered from partial-artifact**, then reconciled by the lead.
- Plan artifact: complete (selector=branch)

The planning subagent produced a complete plan (`## Acceptance Criteria` present, all deepen-plan
sections landed) but stalled on a watchdog before emitting its Session Summary, mid-way through
applying a `plan-review` finding. Recovery per one-shot's plan-artifact-recovery contract: the
artifact was on disk and complete, so planning was NOT re-run.

### Errors
1. Planning subagent stalled (no progress 600s) before emitting `## Session Summary`. Recovered
   from the on-disk artifact rather than re-planned.
2. **The recovered plan was internally contradictory.** Review had superseded the Phase 0.1 /
   M12 "read a harness-injected variable" design inside Phase 3, but the Acceptance Criteria
   (AC8-AC11), Files to Edit, Test Scenarios (T7/T9/T11), the Guard 2 mutation matrix, the
   Observability failure-modes, the Risks table and the ADR-194 description all still described
   the superseded design. `/work` would have been handed a plan saying both "do not widen the
   antecedent" and "prove the widened antecedent refuses". Reconciled by the lead before `/work`;
   10 targeted edits.
3. The stalled agent's last in-flight action was verifying an ordering claim applied 11 times.
   Verified independently against ADR-193 §4 ("the conservation check runs FIRST") — the plan
   states it correctly. No fix needed.

### Decisions
- **Both issue premises re-measured and held**; four of the brief's *factual* claims did not.
  The NO_FIRE population is **eleven**, not eight (four suites the brief never named; one it named
  — `doppler-download-error-channel.test.sh` — already FIRES and is dropped from scope).
  `MAX_CONSTRUCTION_FAILURES` is **15**, not 17. `MAX_DEFERRED` is directory-derived and
  **cannot shrink** as suites are fixed, so it is not the instrument that verifies this work.
- **The guard would not have verified the fix at all** — its mutation loop reads `$COVERED` only,
  and all eleven suites are outside `COVERED_DIRS`. Phase 2 adds a per-scope deferred arm; this is
  the "per-scope ratchet first" the brief named as the precondition for widening, and it needs no
  change to `COVERED_DIRS` or `MAX_CONSTRUCTION_FAILURES`.
- **#7553's briefed fix is measurably impossible.** M1-M11 enumerated and all blocked; no
  repo-controlled spawn path exists. Verified by the lead: `lefthook.yml:234-237` runs
  `bash scripts/test-all.sh` on every `*.{ts,tsx,js,jsx}` pre-commit, so widening the antecedent
  would refuse every spawned agent's ordinary commit.
- **UC-1 put to the operator and answered** (2026-08-19): docs corrections **plus** making the
  sibling detection refuse rather than queue. `tc_preamble` already measures `sib_count` and
  banners `SIBLING_RUN_DETECTED`; Phase 3e turns that into a refusal in the
  `tc_preamble`->`tc_acquire` window. Chosen over docs-only and over full M12. Rationale: it binds
  the refusal to a condition the runner MEASURES rather than one an agent must DECLARE, so it needs
  no spawn-path cooperation, has no fail-open mode, and is testable in CI.
- **ADR-194 re-scoped** to record the measured-vs-declared decision, with M12 in its
  rejected-alternatives table carrying both disqualifying findings.

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan`, `soleur:plan-review` (via the planning subagent)
- Lead-side: collision gate, plan-artifact recovery, plan reconciliation, `AskUserQuestion` (UC-1)
