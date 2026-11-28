---
date: 2026-11-27
topic: agent-liveness-monitoring
issue: 12524
epic: 12533
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spawned-Agent Liveness Monitoring (`#12524`)

## User-Brand Impact

- **Artifact:** Cross-harness spawned-agent liveness monitor (`plugins/soleur/lib/harness.ts` capability matrix, metadata heartbeat/health emitter in `plugins/soleur/scripts/run-health-emit.sh`, and fan-out workflow monitors).
- **Vector:** Silent subagent death/hang (e.g., Free-tier rate-limit drop or truncated turn) leaves autonomous pipelines stalled indefinitely, or blind respawn/transcript capture leaks user PII/secrets or duplicates side-effecting mutations across a single founder's session.
- **Threshold:** `single-user incident`

## What We're Building

An in-session, cross-harness liveness monitoring and bounded-recovery contract for spawned subagents across Soleur's fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`).

1. **Per-harness liveness capability matrix** in `plugins/soleur/lib/harness.ts` declaring what each harness supports (`inBandNudge`, `asyncWait`, `childDiskHeartbeat`, `subagentHooks`) so orchestration degrades gracefully instead of assuming a uniform pane scraper.
2. **Ephemeral, metadata-only seat state** under `.soleur/runs/<run-id>/` (extending `plugins/soleur/scripts/run-health-emit.sh`), recording only structural fields (`seat_id`, `harness`, `started_at`, `last_progress_at`, `attempt`, `classification`, `artifact_path`) with workspace-scoped isolation and TTL cleanup — never raw transcripts, prompt bodies, or secrets.
3. **Deterministic silence & failure classifier** distinguishing `rate_limit` (reusing `isSaturationError()` from `#12529`), `truncated` (via `#12527` `completion-floor.sh` / expected artifact check), `crash` / `hook_deferred`, and `legit_long_turn` (bounded by an absolute turn cap that progress heartbeats cannot reset).
4. **Bounded auto-recover + escalate protocol:**
   - **Check on-disk state first:** Inspect `git status`/`git diff` and expected artifacts before any respawn.
   - **Safe/idempotent seats:** Nudge via `SendMessage`/`send_message`/`followup_task` where supported, or respawn **at most once** with `#12529` saturation fallback (`resolveFallbackTier()`).
   - **Write-capable / dirty-diff seats:** Verify on-disk edits/tests first; never blindly respawn a second writer over uncommitted diffs or re-execute non-idempotent external side effects.
   - **Exhaustion / unrecoverable seats:** Fail fast, surface an honest degraded-coverage status (`Reviewed-Coverage:` / `run_health.json`), and escalate to the operator with actionable diagnostics.

## Why This Approach

- **Cross-harness reality:** Harnesses differ fundamentally — Devin lacks `SendMessage`/`ListAgents`, Devin `subagent_explore` lacks `exec`/`write`, Devin Cloud fires zero hooks, and OpenCode lacks `Stop`/`Monitor`. Approach A (Capability-Tiered Orchestrator Monitor) works across all 6 harnesses by combining child/hook heartbeats where available with parent-side deadlines and artifact verification where absent.
- **Avoids `#9842` overlap:** Hosted process/sandbox supervision belongs to `#9842` (gVisor executor). Approach A solves in-session plugin orchestration without introducing a PTY/tmux sidecar daemon.
- **AGPL-3.0 clean-room & privacy safe:** Re-implements only high-level methodology from `hmuhlestein/HephaestusNG` (no copied code, prompts, or schemas) and keeps all liveness signals strictly metadata-only and local to the workspace run directory.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Clean-room boundary | Methodology-only re-implementation of `HephaestusNG` liveness concepts | `HephaestusNG` is AGPL-3.0; zero copied source, prompts, or schemas (CLO). |
| Telemetry & checkpoint data | Ephemeral metadata-only (`seat_id`, timestamps, exit/status codes, artifact paths) with TTL sweep | Prevents PII/secret capture into checkpoints, LLM prompts, or Sentry/Better Stack (CLO, `single-user incident`). |
| Recovery posture | Bounded auto-recover (max 1 nudge/respawn on safe seats) + honest escalation | Avoids silent hangs while preventing BYOK spend/rate-limit retry storms (CPO, CTO). |
| Write-capable partial diffs | Verify on-disk `git status`/`git diff` + checks first; escalate rather than blind respawn | Matches `2026-11-02` learning; avoids concurrent writer collisions and `session-state.sh` lock contention. |
| Harness adaptation | Capability-tiered contract in `plugins/soleur/lib/harness.ts` | Degrades to parent-side deadline + artifact check on Devin `subagent_explore`, Devin Cloud, and OpenCode (CTO). |
| Pipeline scope (v1) | All 6 fan-out workflows: `one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog` | Matches `#12529` `.workflow.js` + skill fan-out footprint. |
| Architecture record | Author an ADR via `soleur:architecture create` during planning | Cross-cuts `harness.ts`, `run-health-emit.sh`, `session-state.sh`, and fan-out skills (CTO). |

## Open Questions

- Exact per-phase idle-heartbeat window vs. absolute turn-duration cap defaults (to be calibrated in `soleur:plan` / ADR).
- Whether `#12524` should be promoted from `Post-MVP / Later` to Phase 4 (`Validate + Scale`) given `USER_BRAND_CRITICAL=true` (out of scope for code; milestone hygiene).
- Hosted supervisor integration hooks for `#9842` (out of scope — tracked in `#9842`) and UI status rendering (out of scope — tracked in `#2004`).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
*(CMO omitted per `hr-new-skills-agents-or-user-facing` — internal agent-runtime/plugin infrastructure, not user-facing marketing or UI.)*

### Engineering

**Summary:** No subagent liveness monitor exists today (`SubagentStart`/`SubagentStop` are unregistered; `run-health-emit.sh` and `session-state.sh` are phase/worktree-level only). Harnesses vary sharply in `SendMessage`, async wait, and child `exec` support, so liveness must be capability-tiered in `lib/harness.ts` with a hard respawn cap (max 1) and on-disk diff verification before any write-capable respawn.

### Product

**Summary:** Silent hangs and Free-tier rate-limit deaths violate the `single-user incident` brand-survival threshold, while unbounded auto-respawn risks burning founder BYOK quota. Bounded recovery with honest degraded-coverage surfacing and clear escalation keeps the founder in control without duplicating `#9842` or `#2004`.

### Legal

**Summary:** `HephaestusNG` is AGPL-3.0, requiring strict clean-room re-implementation of methodology only. Liveness signals and respawn checkpoints must stay local, workspace-isolated, TTL-expired, and metadata-only (no raw transcript/prompt capture) to avoid PII/secret exposure and GDPR Art. 32/33 breach risk; non-idempotent external tool calls must not be blindly re-executed.
