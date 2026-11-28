# ADR-332: Capability-Tiered Cross-Harness Spawned-Agent Liveness and Bounded Recovery

## Status

Accepted

## Context

Soleur gates spawned-agent *behavior* (hooks, completion floors in ADR-330 / `#12527`, and saturation tier fallback in `#12529`), but previously had no in-flight *process-health* contract for spawned subagents (`#12524`, parent epic `#12533`). Dead, rate-limited, stalled, or silently truncated subagents in fan-out workflows (`one-shot`, `review`, `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel`, `drain-labeled-backlog`) looked identical to legitimate long turns until parent timeout or manual inspection. Because harnesses expose asymmetric primitives (`SendMessage` on Claude Code, `send_input` on Codex, `send_message` on Antigravity vs. completion-only `run_subagent` on Devin and `subagent` on OpenCode; no `exec`/`write` on Devin `subagent_explore`; zero subagent hooks on Devin Cloud), a uniform PTY/tmux scraper cannot operate across all supported harnesses.

## Decision

Introduce a capability-tiered, metadata-only spawned-agent liveness and bounded-recovery contract:

1. **Harness Liveness Capability Matrix (`plugins/soleur/lib/harness.ts`):** `getLivenessCapabilities(harness)` exposes `{ inBandNudge, asyncWait, childDiskHeartbeat, subagentHooks }` for all eight `Harness` members (`claude`, `grok`, `codex`, `devin`, `cursor`, `opencode`, `antigravity`, `unknown`). Harnesses without `inBandNudge` (`devin`, `opencode`, `cursor`, `grok`) or `childDiskHeartbeat` (`devin`, `cursor`) degrade cleanly to parent-side deadlines and on-disk artifact verification.
2. **Metadata-Only Ephemeral Seat State (`plugins/soleur/lib/agent-liveness.ts`, `plugins/soleur/scripts/seat-liveness.sh`, `plugins/soleur/scripts/run-health-emit.sh`):** Per-seat state lives under `.soleur/runs/<run-id>/seats/<seat-id>.json` with a closed field allowlist (`seat_id`, `harness`, `role`, `tier`, `writable`, `side_effecting`, `started_at`, `last_progress_at`, `deadline_at`, `idle_timeout_ms`, `attempt`, `status`, `classification`, `artifact_path`), workspace isolation, and 24-hour TTL cleanup. Raw prompts, transcripts, and secret-shaped tokens are rejected at write time.
3. **Deterministic Silence Classification (`classifySeatSilence`):** Classifies seat state into `alive`, `legit_long_turn`, `rate_limit` (via `#12529` `isSaturationError`), `truncated` (via `#12527` completion-floor / expected-artifact check), `hook_deferred`, or `crash`. Progress heartbeats reset only the idle window (`last_progress_at`), never the absolute turn cap (`deadline_at`).
4. **On-Disk Verification & Bounded 1x Recovery (`decideSeatRecovery`):**
   - Inspects on-disk artifacts and `git status`/`git diff` first; if the deliverable is already valid on disk, returns `accept` without respawning.
   - Refuses blind auto-respawn on `side_effecting` seats (`escalate`) and on `writable` seats with unverified dirty worktree diffs (`verify_disk` first, then `escalate` if verification fails).
   - Allows at most 1 recovery attempt (`attempt < 1`): in-band `nudge` where `inBandNudge` is supported for `hook_deferred`/`truncated`, or 1 `respawn` (using `resolveFallbackTier()` on `rate_limit`).
   - Escalates honestly at `attempt >= 1` with `Reviewed-Coverage: degraded` and `SOLEUR_SEAT_LIVENESS` telemetry markers.

## Alternatives Considered

- **Out-of-band PTY/tmux pane scraper:** Rejected. Soleur does not own the OS process tree for `Task`, `run_subagent`, `spawn_agent`, or `subagent` across harnesses; hosted container supervision is scoped separately to `#9842`.
- **Multi-attempt retry loop with raw transcript checkpointing:** Rejected. Violates metadata-only privacy at the `single-user incident` brand-survival threshold and risks unbounded BYOK quota burn.

## Consequences

- Fan-out workflows detect dead, rate-limited, and truncated subagent seats deterministically and recover at most once before failing fast with honest coverage disclosure.
- All liveness state remains strictly metadata-only and local to `.soleur/runs/<run-id>/seats/`.

## Clean-Room Provenance

Provenance: Independent clean-room design and implementation of cross-harness subagent liveness classification and bounded recovery.
Zero source code, AST schemas, prompts, or tests read, inspected, or copied from hmuhlestein/HephaestusNG (AGPL-3.0).
No AGPL notice applies.
