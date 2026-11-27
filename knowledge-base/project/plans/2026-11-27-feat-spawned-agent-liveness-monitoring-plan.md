---
title: "feat: spawned-agent liveness monitoring"
type: feat
date: 2026-11-27
slug: feat-spawned-agent-liveness-monitoring
branch: feat-12524-agent-liveness-monitoring
issue: 12524
closes: 12524
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: spawned-agent liveness monitoring

## Overview

Implement a capability-tiered, metadata-only spawned-agent liveness monitoring and bounded-recovery contract for Soleur's fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`), grounded in [2026-11-27-agent-liveness-monitoring-brainstorm.md](../brainstorms/2026-11-27-agent-liveness-monitoring-brainstorm.md) and [spec.md](../specs/feat-12524-agent-liveness-monitoring/spec.md).

## Research Insights

- **Premise Validation (Phase 0.6):** Verified `#12524` (OPEN), parent epic `#12533` (OPEN), and adjacent hosted-supervisor epic `#9842` (OPEN). Sibling `#12527` (`plugins/soleur/lib/completion-floors.ts`, `plugins/soleur/scripts/completion-floor.sh`) and `#12529` (`plugins/soleur/lib/harness-model-map.ts`, `isSaturationError()`, `resolveFallbackTier()`) are already shipped on `origin/main`. `plugins/soleur/hooks/hooks.json` and `.claude/settings.json` have no `SubagentStart`/`SubagentStop` hooks, and no `swarm_monitor` exists. `collision-precheck.sh 12524` surfaced our own draft PR `#13093` and two unrelated `test-all.sh` runs in other worktrees.
- **Property List (Phase 0.6b):**
  - *P1:* The orchestrator can classify a spawned subagent's health (`alive`, `rate_limit`, `truncated`, `crash`, `hook_deferred`, `legit_long_turn`) using metadata-only signals.
  - *P2:* On silence or failure, the orchestrator inspects on-disk artifacts/diffs first and executes at most 1 bounded recovery (in-band nudge or saturation-fallback respawn on safe seats) before failing fast and escalating honestly.
  - *P3:* All 6 fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`) enforce this contract with graceful degradation across all harnesses (`claude`, `grok`, `codex`, `devin`, `cursor`, `opencode`, `antigravity`).
- **Cut List (Phase 0.6b):**
  - *Out-of-band PTY/tmux pane scraper* -> cut (Soleur does not own the OS process tree for `Task`/`run_subagent`/`invoke_subagent`; `harness.ts` + `run-health-emit.sh` + `completion-floor.sh` + `isSaturationError` cover P1–P3; hosted process supervision belongs to `#9842`).
  - *Raw transcript/prompt checkpointing* -> cut (violates metadata-only privacy / CLO `single-user incident` threshold; `git status`/`git diff` + artifact presence covers on-disk recovery).
- **Relevant Codebase Paths:**
  - `plugins/soleur/lib/harness.ts` (`Harness` union, `detectHarness()`, `spawnAgent()`, `pollInstructions()`)
  - `plugins/soleur/lib/harness-model-map.ts` (`isSaturationError()`, `resolveFallbackTier()`, `FALLBACK_TIER_GRAPH`)
  - `plugins/soleur/lib/completion-floors.ts` & `plugins/soleur/scripts/completion-floor.sh` (`SOLEUR_FLOOR_GATE`)
  - `plugins/soleur/scripts/run-health-emit.sh` (`.soleur/runs/<run-id>/run_health.json`)
  - `plugins/soleur/scripts/lib/session-state.sh` (`acquire_lease()`, `is_lease_active()`, `sweep_orphan_leases()`)
  - `plugins/soleur/skills/{one-shot,review,resolve-parallel,resolve-pr-parallel,resolve-todo-parallel,drain-labeled-backlog}/SKILL.md` and `workflows/*.workflow.js`
- **Institutional Learnings:**
  - `knowledge-base/project/learnings/workflow-patterns/2026-11-02-free-model-subagent-deaths-favor-lead-verification-over-respawn.md` — inspect on-disk edits before respawning.
  - `knowledge-base/project/learnings/2026-06-30-resume-throttled-background-subagents-via-sendmessage.md` — resume paused seats via `SendMessage` where supported.
  - `knowledge-base/project/learnings/2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md` — preserve/check on-disk artifacts on crash.
  - `knowledge-base/project/learnings/best-practices/2026-06-12-idle-watchdog-reset-on-sdk-heartbeat-and-upstream-fix-exposes-downstream-timeout.md` — progress heartbeats reset idle window, never absolute turn cap.
  - `knowledge-base/project/learnings/test-failures/2026-10-07-a-liveness-probe-that-only-ever-answers-gone-needs-live-and-zombie-controls.md` — liveness tests require live, slow-progress, and dead/zombie controls.

## Proposed Solution

### Architecture

1. **Harness Liveness Capability Matrix (`plugins/soleur/lib/harness.ts`):**
   Add `LivenessCapabilities` and `getLivenessCapabilities(harness: Harness)` returning `{ inBandNudge, asyncWait, childDiskHeartbeat, subagentHooks }` for every member of `Harness`. Harnesses without `inBandNudge` (`devin`, `opencode`, `cursor`) or `childDiskHeartbeat` (read-only `subagent_explore`, Devin Cloud) degrade cleanly to parent-side deadlines + artifact checks.
2. **Metadata-Only Seat Liveness State (`plugins/soleur/lib/agent-liveness.ts` + `plugins/soleur/scripts/run-health-emit.sh`):**
   Extend `run-health-emit.sh` (and add a companion `plugins/soleur/scripts/seat-liveness.sh` CLI) to upsert ephemeral per-seat JSON records under `.soleur/runs/<run-id>/seats/<seat-id>.json`: `{ seat_id, harness, role, writable, side_effecting, started_at, last_progress_at, deadline_at, attempt, status, classification, artifact_path }` with workspace-scoped isolation and automatic TTL sweep (`>24h` or on run completion). Zero transcript text, prompt bodies, or secrets are ever persisted.
3. **Deterministic Silence Classifier & Bounded Recovery (`plugins/soleur/lib/agent-liveness.ts`):**
   - `classifySeatSilence(seat, signals)`: deterministically classifies into `alive`, `legit_long_turn` (progress within idle window and `< deadline_at`), `rate_limit` (reusing `isSaturationError()`), `truncated` (expected artifact / `completion-floor.sh` miss), `hook_deferred`, or `crash`.
   - `decideSeatRecovery(seat, diskState)`: enforces max 1 recovery attempt (`attempt < 1`):
     - If `side_effecting === true`: `escalate` (never auto-respawn).
     - If `writable === true` and `diskState.dirtyDiff === true`: `verify_disk` first; if verification passes, `accept`; else `escalate` (never blindly spawn a second writer over uncommitted diffs).
     - If `inBandNudge` is available and seat is paused/stalled: `nudge` once.
     - Otherwise on safe/read-only or clean-disk seats: `respawn` once via `resolveFallbackTier()`.
     - On `attempt >= 1`: `escalate` with honest degraded-coverage status (`Reviewed-Coverage`).
4. **Fan-Out Workflow Integration:**
   Wire seat registration, liveness sweep, and bounded recovery/escalation into `one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, and `drain-labeled-backlog` (both `SKILL.md` instructions and `.workflow.js` orchestration where present).

### Implementation Phases

#### Phase 1: Capability Matrix, Metadata Schema & ADR
- Add `LivenessCapabilities` and `getLivenessCapabilities()` to `plugins/soleur/lib/harness.ts`.
- Create `plugins/soleur/lib/agent-liveness.ts` with seat state types, deterministic `classifySeatSilence()`, and `decideSeatRecovery()`.
- Author the cross-harness liveness ADR in `knowledge-base/engineering/architecture/decisions/` via `soleur:architecture create` semantics.

#### Phase 2: Ephemeral Seat State CLI & `run-health-emit.sh` Integration
- Create `plugins/soleur/scripts/seat-liveness.sh` (`init`, `heartbeat`, `sweep`, `decide`, `cleanup`) storing metadata-only JSON under `.soleur/runs/<run-id>/seats/` with TTL cleanup.
- Update `plugins/soleur/scripts/run-health-emit.sh` to include seat-liveness summary counts (`active`, `recovered`, `escalated`) when seats exist in the run directory.

#### Phase 3: Fan-Out Workflow Integration
- Update `one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, and `drain-labeled-backlog` (`SKILL.md` and `.workflow.js` files) to register spawned seats, run `seat-liveness.sh sweep` / `decide`, verify on-disk state before respawn, and surface honest `Reviewed-Coverage` on escalation.

#### Phase 4: Tests & Cross-Harness Parity
- Add `plugins/soleur/test/agent-liveness.test.ts` covering `getLivenessCapabilities()` across all 8 `Harness` values, `classifySeatSilence()`, `decideSeatRecovery()` (including dirty-diff and side-effecting guards), and TTL cleanup.
- Add `plugins/soleur/test/seat-liveness.test.sh` testing `seat-liveness.sh` with live, slow-progress, rate-limited, truncated, and dead/zombie controls.

## Files to Edit

- `plugins/soleur/lib/harness.ts` — add `LivenessCapabilities` interface and `getLivenessCapabilities()`
- `plugins/soleur/scripts/run-health-emit.sh` — summarize `.soleur/runs/<run-id>/seats/` liveness counts
- `plugins/soleur/skills/one-shot/SKILL.md` — wire seat liveness registration, sweep, and bounded recovery
- `plugins/soleur/skills/review/SKILL.md` & `plugins/soleur/skills/review/workflows/review.workflow.js` — wire seat liveness & honest `Reviewed-Coverage`
- `plugins/soleur/skills/resolve-parallel/SKILL.md` & `plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js` — wire seat liveness & dirty-diff guard
- `plugins/soleur/skills/resolve-pr-parallel/SKILL.md` & `plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js` — wire seat liveness & dirty-diff guard
- `plugins/soleur/skills/resolve-todo-parallel/SKILL.md` & `plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js` — wire seat liveness & dirty-diff guard
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` & `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js` — wire seat liveness & dirty-diff guard

## Files to Create

- `plugins/soleur/lib/agent-liveness.ts` — silence classifier, bounded recovery policy, metadata schema
- `plugins/soleur/scripts/seat-liveness.sh` — ephemeral seat state CLI (`init`, `heartbeat`, `sweep`, `decide`, `cleanup`)
- `plugins/soleur/test/agent-liveness.test.ts` — unit tests for capability matrix, classifier, and recovery policy
- `plugins/soleur/test/seat-liveness.test.sh` — integration tests with live, slow-progress, and dead/zombie controls
- `knowledge-base/engineering/architecture/decisions/ADR-332-cross-harness-agent-liveness.md` — ADR for the cross-harness liveness contract (ordinal verified against `origin/*` and sibling worktrees)

## Open Code-Review Overlap

None

## User-Brand Impact

- **If this lands broken, the user experiences:** Autonomous fan-out pipelines (`one-shot`, `review`, `drain-labeled-backlog`) either hang indefinitely on a dead/rate-limited seat or falsely claim full coverage when a seat silently died.
- **If this leaks, the user's data / workflow / money is exposed via:** Unbounded respawn loops burning BYOK quota, duplicate mutations over dirty worktree diffs, or raw transcript/secret leakage into checkpoint files.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** A single silent hang, BYOK retry storm, or transcript leak burns a solo founder's trust and data on first occurrence.

## Observability

```yaml
liveness_signal:
  what: "Per-seat metadata heartbeat & sweep status in .soleur/runs/<run-id>/seats/*.json and run_health.json"
  cadence: "per-seat start, progress heartbeat, and post-wait sweep"
  alert_target: "in-session orchestrator escalation + Reviewed-Coverage disclosure"
  configured_in: "plugins/soleur/scripts/seat-liveness.sh"

error_reporting:
  destination: "local run_health.json + operator session output"
  fail_loud: "SOLEUR_SEAT_LIVENESS seat=<id> status=<classification> action=<nudge|respawn|escalate>"

failure_modes:
  - mode: "Rate-limited or dead subagent seat"
    detection: "seat-liveness.sh sweep classifies rate_limit / crash / truncated"
    alert_route: "bounded 1x recovery or immediate operator escalation"

logs:
  where: ".soleur/runs/<run-id>/run_health.json and .soleur/runs/<run-id>/seats/"
  retention: "24h TTL auto-swept by seat-liveness.sh cleanup"

discoverability_test:
  command: "bash plugins/soleur/scripts/seat-liveness.sh --self-test"
  expected_output: "SOLEUR_SEAT_LIVENESS_SELFTEST=ok"
```

## Architecture Decision (ADR/C4)

### ADR
- Create `knowledge-base/engineering/architecture/decisions/ADR-332-cross-harness-agent-liveness.md` recording the capability-tiered cross-harness spawned-agent liveness contract, metadata-only per-seat state under `.soleur/runs/<run-id>/seats/`, deterministic silence classification, and max-1 bounded recovery with dirty-diff and side-effecting guards.

### C4 views
- Read `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, and `spec.c4`.
- Enumerated external human actors (`founder`), external systems (`claude`, `codex`, `devin`, `cursorCli`, `grokBuild`), containers/data-stores (`platform.plugin` and local `.soleur/runs/`), and actor-to-surface access relationships (local workspace owner/agent process only, zero network egress). All actors, systems, and containers are already modeled in `model.c4` and rendered in `views.c4`; no C4 impact.

### Sequencing
- Authored and shipped in this PR (`status: accepted`).

## Domain Review

*(Carried forward from [2026-11-27-agent-liveness-monitoring-brainstorm.md](../brainstorms/2026-11-27-agent-liveness-monitoring-brainstorm.md) `## Domain Assessments`.)*

- **Engineering (CTO):** Capability-tiered contract in `lib/harness.ts`, max-1 recovery cap, and dirty-diff verification before write-capable respawn.
- **Product (CPO):** Prevents silent hangs at `single-user incident` threshold while avoiding unbounded BYOK spend and `#9842`/`#2004` overlap.
- **Legal (CLO):** Strict AGPL-3.0 clean-room boundary vs `HephaestusNG`; metadata-only local ephemeral state with TTL cleanup; no blind re-execution of side-effecting calls.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Heartbeat/turn-progress signal per spawned agent + a sweep classifying silence (rate-limit, truncation, crash, legit long-turn) → nudge, respawn with checkpoint, or escalate." `[issue #12524]` | FR-1–FR-4, `agent-liveness.ts`, `seat-liveness.sh` | mapped |
| 2 | "this is about in-session spawned agents on every harness." `[issue #12524]` | `harness.ts` `getLivenessCapabilities()`, TR-2 | mapped |
| 3 | "All fan-out workflows (Recommended) — Wire into one-shot, review, resolve-parallel, resolve-pr-parallel, resolve-todo-parallel, and drain-labeled-backlog" `[brainstorm decision]` | Phase 3, `Files to Edit` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `harness.ts` `getLivenessCapabilities()` | "in-session spawned agents on every harness" | asked |
| `agent-liveness.ts` + `seat-liveness.sh` | "Heartbeat/turn-progress signal per spawned agent + a sweep classifying silence ... → nudge, respawn with checkpoint, or escalate" | asked |
| `run-health-emit.sh` summary | "Heartbeat/turn-progress signal per spawned agent" | inferred — justification: existing run-health emitter already owns `.soleur/runs/<run-id>/run_health.json` |
| 6 fan-out workflow edits | "Wire into one-shot, review, resolve-parallel, resolve-pr-parallel, resolve-todo-parallel, and drain-labeled-backlog" | asked |
| `agent-liveness.test.ts` + `seat-liveness.test.sh` | — | inferred — justification: required unit/integration test coverage with live and zombie controls |
| ADR in `decisions/` | — | inferred — justification: constitution requires ADR for cross-harness architectural contracts |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 18 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Functional Requirements

- [ ] `plugins/soleur/lib/harness.ts` exports `getLivenessCapabilities(harness)` covering all 8 `Harness` values (`claude`, `grok`, `codex`, `devin`, `cursor`, `opencode`, `antigravity`, `unknown`).
- [ ] `plugins/soleur/lib/agent-liveness.ts` and `plugins/soleur/scripts/seat-liveness.sh` manage ephemeral metadata-only seat state under `.soleur/runs/<run-id>/seats/` with 24h TTL cleanup and zero raw transcript/prompt/secret persistence.
- [ ] `classifySeatSilence()` deterministically classifies `alive`, `legit_long_turn`, `rate_limit`, `truncated`, `hook_deferred`, and `crash`, enforcing an absolute turn cap that progress heartbeats cannot reset.
- [ ] `decideSeatRecovery()` enforces max 1 recovery attempt, inspects on-disk diffs/artifacts first, blocks auto-respawn on `side_effecting` or dirty-diff `writable` seats, and emits honest escalation status.
- [ ] All 6 fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`) wire seat liveness registration, sweep, and bounded recovery.

### Quality Gates

- [ ] `bun test plugins/soleur/test/agent-liveness.test.ts` passes.
- [ ] `bash plugins/soleur/test/seat-liveness.test.sh` passes with live, slow-progress, and dead/zombie controls.
- [ ] Existing harness parity tests (`bun test plugins/soleur/test/harness.test.ts`) pass.

## Test Scenarios

- **Unit (`plugins/soleur/test/agent-liveness.test.ts`):** Given each `Harness` value, when `getLivenessCapabilities()` is called, then it returns accurate `inBandNudge`, `asyncWait`, `childDiskHeartbeat`, and `subagentHooks` flags.
- **Unit (`plugins/soleur/test/agent-liveness.test.ts`):** Given a seat with recent progress heartbeats that has exceeded `deadline_at`, when `classifySeatSilence()` runs, then it does not reset the absolute turn cap and flags timeout/escalation.
- **Unit (`plugins/soleur/test/agent-liveness.test.ts`):** Given a `writable` seat that died with `dirtyDiff: true` or a `side_effecting` seat, when `decideSeatRecovery()` runs, then it returns `verify_disk` or `escalate` (never blind `respawn`).
- **Integration (`plugins/soleur/test/seat-liveness.test.sh`):** Given live, slow-progress, rate-limited (`isSaturationError`), truncated, and dead/zombie seat fixtures, when `seat-liveness.sh sweep` and `cleanup` run, then each fixture classifies accurately and expired (>24h) seat files are removed.
