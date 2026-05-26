---
title: Defense-in-depth recovery layer mirroring a SQL predicate — name the load-bearing sub-value or it reads as dead code
date: 2026-05-06
category: best-practices
component: concurrency
problem_type: architecture-review
related_prs: [3354, 3295, 3217, 2617]
related_issues: [3372, 3373, 3374]
related_migrations: [029_plan_tier_and_concurrency_slots, 036_release_slot_on_archive, 037_stuck_active_finder_rpc]
tags:
  - concurrency
  - defense-in-depth
  - sql-layer-vs-application-layer
  - threshold-coupling
  - sentry-observability
  - plan-time-architecture-review
---

# Defense-in-depth recovery layer mirroring a SQL predicate

## Problem

PR #3354 widened `tryLedgerDivergenceRecovery` (TS, `apps/web-platform/server/ws-handler.ts`) with a second SELECT for `last_heartbeat_at < now() - 120s` slots so the application layer can reap stale-heartbeat rows synchronously at cap-hit time. The plan framed this as the load-bearing fix that closes a 0-180 s dead-end window where users dead-end on the `WS_CLOSE_CODES.CONCURRENCY_CAP` modal.

Multi-agent code review (architecture-strategist, deepened) surfaced that the new branch is largely **tautological at 120 s threshold**: `acquire_conversation_slot` (migration 029 line ~131) runs the IDENTICAL `last_heartbeat_at < now() - interval '120 seconds'` predicate inside the RPC's transaction BEFORE the count-check. So when the RPC returns `cap_hit`, every surviving slot is necessarily fresh — the new application-layer SELECT only finds stale rows in narrow boundary races (50–200 ms between RPC commit and helper SELECT) or if the RPC's lazy sweep is later refactored away.

Filed as scope-out #3372 with three named alternatives (tighten threshold to ~45 s, drop the branch, keep as defense-in-depth).

## Solution

The fix's actual value is NOT cap-hit recovery acceleration (the lazy sweep already does that). It is three narrower sub-values:

1. **Status-flip on the conversation row.** The lazy sweep deletes the slot but does NOT update `conversations.status`. The application-layer reap runs `updateConversationFor(userId, cid, { status: 'failed' }, ...)` so the dashboard rail's stuck-Executing row trues up immediately rather than waiting up to 60 s for the agent-runner async reaper.
2. **Sentry observability.** The lazy sweep is silent. The application-layer reap mirrors a single `concurrency-ledger-divergence` event with `staleHeartbeatCount` and `recoveryCause` extras, exposing the rate to operator dashboards.
3. **Defense-in-depth for future RPC drift.** If a future migration removes or reshapes the lazy sweep in `acquire_conversation_slot`, the application-layer reap remains a backstop.

When extending an application-layer recovery primitive that mirrors a SQL-layer primitive, the code MUST name which sub-value is load-bearing in an inline comment. Otherwise a future reader will look at the SQL primitive, look at the TS primitive, conclude they're identical, and prune the TS one — losing whichever sub-value was actually pulling weight.

## Key Insight

When you add a defense-in-depth layer at the same threshold as an existing automatic primitive (here: 120 s appearing in five sites — migration 029 lazy sweep, migration 029 pg_cron, migration 037 RPC default, agent-runner.ts, and now ws-handler.ts), the **code reads as dead code unless the load-bearing sub-value is documented at the call site**. Common sub-values that justify mirroring:

- **Cross-layer state truing** (here: status-flip the SQL primitive doesn't perform).
- **Observability** the SQL primitive doesn't emit (Sentry, structured logs).
- **Drift-resilience** if the SQL primitive is later refactored.

If NONE of these apply, the layer IS dead and should be removed or its threshold tightened so it catches what the SQL primitive misses (one missed ping = ~45 s, one half-heartbeat = ~30 s). Tightening introduces an asymmetric ceiling (TS=45 s vs SQL=120 s) that requires defense-relaxation analysis per `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — naming the new ceiling is the cost.

**Plan-time architecture review** should explicitly probe this gap during the Domain Review / CTO Engineering phase. Question: *"Does this new code path mirror a predicate that already exists in another layer (SQL, async reaper, scheduled job)? If yes, name the load-bearing sub-value or tighten the threshold."* The architecture-strategist agent at PR-review time is too late — by then the code is written and the contested-design alternatives are filed as follow-ups instead of debated in the plan.

## Threshold-coupling rule

When a constant is referenced across N sites, the THRESHOLD-COUPLING comment block at every site MUST list the OTHER sites by file:line. The pre-existing comment at `agent-runner.ts:513` said "120 s appears in three places" before this PR — that count was already stale (migration 037 was the third, agent-runner the fourth, ws-handler the fifth as of this PR). Comment-as-coupling is weaker than import-as-coupling, but until SQL + TS share a single source of truth (a Postgres GUC + a TS constant derived from it), the comment block is the fallback. When you add a new site, update every existing comment block in the same commit.

Long-term direction: hoist the TS-side constant to `apps/web-platform/lib/concurrency-thresholds.ts` exporting `STUCK_ACTIVE_THRESHOLD_SECONDS`. SQL sites can stay coupled by comment + a `concurrency_constants()` SQL function migration if needed.

## Test-anchor sub-insight

When a copy-rewrite removes a misleading clause (here: "Archive a completed conversation to free a slot") and the new copy legitimately retains the offending substring (here: "Archive an active or completed conversation from the dashboard"), the regression-anchor test MUST forbid the FULL misleading verbatim phrase, not a substring. A first-pass `not.toContain("completed conversation")` would have failed against the correct new copy. Pin: `expect(reason).not.toContain("Archive a completed conversation to free a slot")`.

## Session Errors

- **Test anchor was too strict on first pass** — `not.toContain("completed conversation")` failed against the correct new copy that legitimately says "active or completed conversation". **Recovery:** tightened to forbid the verbatim misleading clause. **Prevention:** anchor copy-rewrite asserts on the FULL misleading instruction, not a substring the new copy may retain. Domain-scoped to test writing — captured in this learning's "Test-anchor sub-insight" section above; no AGENTS.md rule warranted.
- **Bash CWD reset between calls** caused a `./node_modules/.bin/vitest` invocation to fail with "No such file or directory". **Recovery:** chained `cd <worktree-abs-path> && cmd` in a single Bash call. **Prevention:** already covered by existing learning `bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`. No new rule.
- **Transient `gh issue list --json` rate-limit message** despite REST showing 4997/5000 remaining. **Recovery:** verified via `gh api rate_limit --jq`, retried with separate API call shape. **Prevention:** treat first "rate limit exceeded" as possible secondary/burst limit; verify with `rate_limit` before assuming hard exhaustion. Not rule-worthy on its own.
- **Duplicate review-agent spawns across two parallel batches** (security-sentinel × 2, architecture-strategist × 2, pattern-recognition × 2). The second prompts pulled different angles but produced overlapping findings. **Recovery:** manual dedup at synthesis. **Prevention:** before launching a review parallel batch, inventory agent types already spawned in this session — the review skill's main batch (8 always-on + conditional) covers everything in one shot; do not fan out twice. Domain-scoped to review skill — propose updating review skill to track spawned-agent inventory, OR simply an instruction to the review skill author/runner.
- **Plan used `## Test Strategy` heading instead of `## Test Scenarios`** so QA skill skipped gracefully. **Recovery:** none needed — graceful skip honored the skill spec. **Prevention:** either standardize plan template on `## Test Scenarios` (one canonical heading) OR expand QA skill to detect `## Test Strategy` as a fallback heading. Domain-scoped to plan/qa skills.
- **Architecture finding F3 (helper tautology at 120 s) surfaced only at review-time, not plan-time** — the plan author committed to 120 s deliberately to match four sibling sites without surfacing the tautology trade-off. **Recovery:** filed scope-out #3372 naming three alternatives (tighten / drop / document-as-defense-in-depth). **Prevention:** plan-skill domain-review should probe SQL/application-layer mirroring at plan time so contested-design alternatives are debated before implementation, not after. Captured in this learning's "Plan-time architecture review" paragraph.

## Cross-references

- PR #3354 (this PR) — application-layer stale-heartbeat reap widening
- PR #3295 — May-5 stuck-active 4-layer fix introducing `tryLedgerDivergenceRecovery` (orphan-only)
- PR #3217 — migration 036 archive-trigger releases concurrency slot
- PR #2617 — migration 029 introduced the slot ledger + lazy sweep + pg_cron + advisory-xact-lock
- Issue #3372 (this PR's scope-out) — threshold tautology debate (tighten / drop / keep)
- Issue #3373 (this PR's scope-out) — `SLOT_TRIGGER_INTEGRATION_TEST` not wired into nightly CI
- Issue #3374 (this PR's scope-out) — emit `slot_reclaimed` WS frame for in-band agent observability
- Learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — applies if scope-out #3372 picks the "tighten threshold" alternative
- Migration 029 (`apps/web-platform/supabase/migrations/029_plan_tier_and_concurrency_slots.sql`) — lazy sweep at line ~131, pg_cron sweep at line ~224, index `user_concurrency_slots_user_heartbeat_idx` at line ~83
- Migration 037 (`apps/web-platform/supabase/migrations/037_stuck_active_finder_rpc.sql`) — RPC default `p_threshold_seconds = 120` at line ~39
- `apps/web-platform/server/agent-runner.ts:519` — `STUCK_ACTIVE_THRESHOLD_SECONDS = 120` (4-site THRESHOLD-COUPLING comment updated this PR to reflect the 5th site)
