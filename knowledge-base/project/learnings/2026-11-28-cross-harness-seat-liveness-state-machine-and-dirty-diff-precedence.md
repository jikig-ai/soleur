---
title: "Cross-Harness Spawned-Agent Liveness State Machine and Dirty-Diff Precedence"
date: 2026-11-28
category: workflow-patterns
tags:
  - agent-liveness
  - subagents
  - harness-parity
  - bounded-recovery
  - data-integrity
module: plugins/soleur
issue: 12524
pr: 13093
---

# Learning: Cross-Harness Spawned-Agent Liveness State Machine and Dirty-Diff Precedence

## Problem

When building cross-harness spawned-agent liveness monitoring and bounded 1x recovery (`#12524`, `ADR-332`) across `plugins/soleur/lib/agent-liveness.ts`, `plugins/soleur/scripts/seat-liveness.sh`, and `plugins/soleur/scripts/run-health-emit.sh`, multi-agent review surfaced three subtle state-machine and recovery-precedence traps:

1. **Premature `status: "recovered"` on retry decision:** Marking a seat `"recovered"` inside `seat-liveness.sh decide` when emitting `action=nudge` or `action=respawn` records recovery *before* the retry executes. If the retry subsequently crashes, `sweep` updates `classification` without updating `status`, leaving a dead seat counted as `recovered`. Conversely, if the retry succeeds and `sweep --exited true --exit-code 0` runs, an unconditional `status = "completed"` overwrites `"recovered"` even when `attempt > 0`.
2. **Re-running `init` on a respawned seat resets `attempt: 0`:** If an orchestrator calls `seat-liveness.sh init` when respawning a seat, overwriting `attempt: 0` erases the prior attempt count and defeats the max-1 recovery cap.
3. **`artifactVerified` masking an unverified dirty diff on a `writable` seat:** Checking `diskState.artifactVerified === true` before `seat.writable && diskState.dirtyDiff === true` allows a crashed writable seat that left corrupted uncommitted worktree changes to return `action: "accept"` instead of `verify_disk` / `escalate`.

## Solution

1. **Defer `"recovered"` until post-retry verification, or attribute in-flight retries accurately:**
   - In `seat-liveness.sh decide`, only `action=accept` immediately sets `status = "recovered"`. On `action=nudge` or `action=respawn`, increment `attempt`, keep `status = "running"`, refresh `last_progress_at = now_ms` (and extend `deadline_at` by the seat's duration budget on `respawn`).
   - In `seat-liveness.sh sweep`, when a seat exits cleanly (`exited && exit_code == 0 && art_ok && floor_ok`), transition `status` to `"recovered"` if `attempt > 0`, else `"completed"`. In batch sweeps (`--seat` omitted), skip seats already in terminal states (`completed`, `recovered`, `escalated`).
   - In `seat-liveness.sh init`, preserve `attempt` from any existing non-terminal `<seat>.json` record on disk and automatically run the 24-hour TTL cleanup sweep so stale seats in `.soleur/runs/default/seats/` never pollute later runs.
2. **Enforce dirty-diff precedence over `artifactVerified`:**
   - In both `decideSeatRecovery()` (`agent-liveness.ts`) and `seat-liveness.sh decide`, evaluate `seat.writable && diskState.dirtyDiff` *before* `artifactVerified` so an unverified or failed worktree diff always returns `verify_disk` or `escalate`.
3. **Clamp `reviewed_coverage` in `run-health-emit.sh`:**
   - Downgrade `run_health.json`'s `reviewed_coverage` from `"full"` (set by an earlier phase) to `"degraded"` whenever any seat in `seats_dir` has `status == "escalated"` or `reviewed_coverage == "degraded"`.

## Key Insight

A recovery decision (`nudge` or `respawn`) is an *intent to retry*, not a *completed recovery*: the state machine must keep `status = "running"` with `attempt = 1` at decision time and transition to `"recovered"` or `"escalated"` only when the retry's outcome is observed, while preserving `attempt` across re-initialization so the max-1 retry bound cannot be reset.

## Session Errors

1. **`completion-floor.sh --phase plan` reported `missing=no-out-of-scope-edits` when `brainstorm` committed a brainstorm doc earlier on the same branch** — Recovery: Verified that `4de79ca8bf` committed `knowledge-base/project/brainstorms/2026-11-27-agent-liveness-monitoring-brainstorm.md` before `plan` ran, and confirmed `completion-floor.sh --phase work` passed once implementation commits landed. — **Prevention:** When resuming a branch that ran `soleur:brainstorm` before `soleur:plan`, note that `completion-floor.sh --phase plan` scopes `no-out-of-scope-edits` to `knowledge-base/project/{plans,specs}/`.
2. **`one-shot/SKILL.md` byte-ceiling collision (`51,999` bytes against `52,000` ceiling in `skill-body-budget.json`)** — Recovery: Trimmed ~200 bytes of redundant explanatory prose in `one-shot/SKILL.md` and `review/SKILL.md` in the same edit that wired `seat-liveness.sh`, bringing `one-shot/SKILL.md` to `51,894` bytes (`lint-skill-body-budget.py --base origin/main` green). — **Prevention:** Before editing any lifecycle `SKILL.md` listed in `plugins/soleur/test/skill-body-budget.json`, check `wc -c` against its ceiling first and trim verbose prose inline when headroom is under 500 bytes.
3. **`review-scan-gate.sh` invoked via bare-root path resolved `$ROOT` to the bare repo root instead of the active worktree** — Recovery: Invoked `bash "plugins/soleur/skills/review/scripts/review-scan-gate.sh"` via its worktree-relative path so `BASH_SOURCE[0]` resolved `$ROOT` to the worktree, then fixed `SC1091` and `SC2317` to reach `SOLEUR_REVIEW_SCAN_GATE ok engine=mixed files=11 rules=219 findings=0`. — **Prevention:** Always invoke `plugins/soleur/skills/review/scripts/review-scan-gate.sh` using the worktree's own `plugins/soleur/...` path so its relative `ROOT` resolution targets the worktree checkout rather than the bare repository root.
4. **7 of 11 parallel review subagents hit `OpenCode Go 5 hour usage limit reached`** — Recovery: 4 seats (`data-integrity-guardian`, `user-impact-reviewer`, `security-sentinel`, `test-design-reviewer`) completed with full reports and all 5 deduplicated findings were fixed inline; swept and escalated the 7 rate-limited seats via `seat-liveness.sh` and emitted honest `Reviewed-Coverage: degraded 4/11 agents` trailers. — **Prevention:** Always pass exact `--agents-ran`, `--agents-expected`, and `--agents-missing` counts to `emit-review-trailer.sh` and `seat-liveness.sh` when provider usage caps truncate a parallel review panel.
