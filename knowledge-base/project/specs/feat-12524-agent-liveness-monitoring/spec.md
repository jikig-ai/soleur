---
title: "Spawned-Agent Liveness Monitoring"
issue: 12524
epic: 12533
branch: feat-12524-agent-liveness-monitoring
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Feature Spec: Spawned-Agent Liveness Monitoring (`#12524`)

## Problem Statement

Soleur gates spawned-agent *behavior* (hooks, completion floors `#12527`, saturation fallback `#12529`), but has no in-flight *process-health* monitoring. Dead, rate-limited, stalled, or silently truncated subagents look identical to slow turns until parent timeout or manual inspection. Because harnesses expose different primitives (`SendMessage` on Codex/Antigravity vs. `read_subagent`-only on Devin; `exec`/`write` absent on Devin `subagent_explore`; zero hooks on Devin Cloud), a uniform pane-scraping watcher cannot work.

## Goals

- Detect dead, stalled, rate-limited, and silently truncated spawned subagents across Soleur's fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`).
- Support bounded auto-recovery (max 1 nudge or saturation-fallback respawn on safe seats) after inspecting on-disk artifacts/diffs first, and fail-fast with honest escalation when recovery is exhausted or unsafe.
- Keep all liveness and checkpoint state strictly metadata-only, workspace-isolated, and ephemeral (TTL-cleaned) with zero AGPL-3.0 code/prompt reuse from `HephaestusNG`.

## Non-Goals

- Hosted sandbox/gVisor supervisor contract (tracked in `#9842`).
- Agent work visualization UI / dashboard surfaces (tracked in `#2004`).
- Multi-retry unbounded auto-restart loops or raw transcript/prompt persistence.

## User-Brand Impact

- **Artifact:** Cross-harness spawned-agent liveness monitor (`lib/harness.ts`, `scripts/run-health-emit.sh`, and fan-out workflow monitors).
- **Vector:** Silent hangs/rate-limit deaths stall founder pipelines indefinitely, or blind respawns/transcript dumps leak PII/secrets or duplicate side-effecting mutations.
- **Threshold:** `single-user incident`

## Functional Requirements

- **FR1 — Harness Liveness Capability Matrix:** `plugins/soleur/lib/harness.ts` exposes a per-harness capability descriptor (`inBandNudge`, `asyncWait`, `childDiskHeartbeat`, `subagentHooks`) covering Claude Code, Devin CLI/Cloud, Grok Build, Codex, OpenCode, and Antigravity.
- **FR2 — Metadata-Only Seat Liveness State:** `plugins/soleur/scripts/run-health-emit.sh` (and `.soleur/runs/<run-id>/`) records ephemeral per-seat metadata (`seat_id`, `harness`, `started_at`, `last_progress_at`, `attempt`, `classification`, `artifact_path`) with automatic TTL cleanup and zero raw transcript/prompt/secret content.
- **FR3 — Deterministic Silence & Failure Classification:** An orchestrator sweep classifies seat silence/exit into `rate_limit` (via `#12529` `isSaturationError`), `truncated` (via `#12527` `completion-floor.sh` / expected artifact check), `crash` / `hook_deferred`, or `legit_long_turn`, enforcing an absolute turn-duration cap that progress heartbeats cannot reset.
- **FR4 — Bounded Recovery & On-Disk Verification:** Before any nudge/respawn, the orchestrator inspects on-disk artifacts (`git status`/`git diff` for write-capable seats, expected output files for read-only seats). Safe/idempotent seats allow at most 1 nudge (where `inBandNudge` is true) or 1 respawn with `#12529` tier fallback; write-capable seats with dirty partial diffs are verified rather than blindly overwritten; non-idempotent external side-effect seats never auto-respawn.
- **FR5 — Honest Escalation & Coverage Disclosure:** Exhausted, unrecoverable, or degraded seats emit explicit status into `run_health.json` and surface honest `Reviewed-Coverage` / operator escalation with actionable diagnostics.
- **FR6 — Fan-Out Workflow Integration:** Wire the liveness monitor contract into `one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, and `drain-labeled-backlog`.

## Technical Requirements

- **TR1 — AGPL-3.0 Clean-Room Boundary:** Zero copied code, prompt text, or state schemas from `hmuhlestein/HephaestusNG`.
- **TR2 — Graceful Degradation:** On harnesses without child `exec`/`write` or hooks (Devin `subagent_explore`, Devin Cloud, OpenCode), liveness degrades to parent-side deadlines + artifact verification without failing or blocking execution.
- **TR3 — Liveness Probe Test Controls:** Automated tests must include live, slow-progress, and dead/zombie/rate-limited controls (per `2026-10-07` liveness-probe learning).
- **TR4 — Architecture Decision Record:** Document the cross-harness liveness contract via `soleur:architecture create` during planning.
