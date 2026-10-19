---
plan: L5 Runaway Guard — notification + working pause (safety floor)
issue: 5767
branch: feat-l5-runaway-guard
draft_pr: 5881
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
created: 2026-07-02
revised: 2026-07-02 (v2 — simplified after 5-agent plan-review)
brainstorm: knowledge-base/project/brainstorms/2026-07-01-l5-runaway-guard-brainstorm.md
spec: knowledge-base/project/specs/feat-l5-runaway-guard/spec.md
---

# ✨ Plan: L5 Runaway Guard — safety floor (v2)

Make the *existing* cost-guard actually protect a non-technical founder: (1) fix the silently-broken
pause so a tripped cap really stops spending and can be resumed, and (2) notify the founder when it trips.
Everything else the brainstorm imagined is deferred as honestly-scoped follow-ups — the 5-agent
plan-review panel + CFO converged that the safety value lives here and the rest is over-build.

## Overview

**v1 → v2 simplification.** The original 4-PR train (24h window, estimate+HITL, doom-loop, cron metering)
was cut after plan-review. Verified facts that drove the cut:
- The cost caps **already exist** (ADR-041 3-layer model). The gap is that they're **silent** and — newly
  discovered — that the **pause they set is cosmetic**.
- **`runtime_paused_at` is a write-only flag** (arch-strategist P0-A): zero readers, zero clearers repo-wide.
  The RPC trips `kill_tripped` only on the NULL→set transition, so an already-paused founder's next spawn
  returns `kill_tripped=false` and **keeps spending**; nothing clears the flag, so "resume" has no code.
- The **cron substrate writes nothing to `audit_byok_use`** (Kieran P0-1), so no dollar cap — existing or
  new — can see the surface where the overnight-burn threat mostly lives. A new 24h window would not fix
  this. → deferred as the real threat-surface follow-up.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Verified reality | Plan response |
|---|---|---|
| "No run-wide cost ceiling exists" | Per-founder rolling-1h cap exists (`migrations/061:...`, sums `audit_byok_use` over `interval '1 hour'`, sets `runtime_paused_at`) | Do not rebuild |
| Pause actually stops the run | **False** — `runtime_paused_at` has no reader/clearer; RPC trips transition-only (`061:136`) | **PR-A fixes this** (the core work) |
| "No notification on trip" | True — cap RPC + `persistFailure` (`agent-on-spawn-requested.ts:913-962`) are silent (Sentry-only) | **PR-A wires it** |
| Caps cover the overnight-burn surface | **False** — crons (`_cron-claude-eval-substrate.ts:818` `claude --print`, BYOK key injected) write nothing to `audit_byok_use` | Deferred: **cron cost-enforcement** follow-up |
| Counter lives in `routine_run_progress` | Wrong surface — that table is cron-only (ADR-077 §2); the leader loop uses `action_sends` | N/A (doom-loop deferred) |

## User-Brand Impact

**If this lands broken, the user experiences:** a tripped cost cap that still doesn't stop the run, or a
halt with no notice — the founder keeps losing BYOK dollars unattended.
**If this leaks, the user's money is exposed via:** a runaway consuming the founder's own Anthropic
credits with no working brake and no alert.
**Brand-survival threshold:** single-user incident.

> **Named residual (Non-Goal, tracked):** PR-A fixes the *leader-loop* pause + notification. The **cron
> surface remains uninsured** (writes nothing to `audit_byok_use`) — the largest real overnight-burn
> surface. This is filed as the top-priority follow-up (Kieran P0-1), not silently dropped.

CPO sign-off carried forward (`USER_BRAND_CRITICAL=true`); `user-impact-reviewer` runs at review time.

## Goals

1. **Make the pause real** — a spawn-entry gate that refuses when `runtime_paused_at IS NOT NULL`, an
   operator-resume action that clears it, and a contract that cap-checks **set but never clear** it.
2. **Notify on trip** — `notifyOfflineUser` + a new `cost_breaker_tripped` payload, wired into
   `persistFailure` at **one** site; honest dollar copy.
3. **Legal/architecture reconciliation** — ToS §3a.5/§11, ADR-041 amend, ADR-042 frontmatter fix, Art.30.

## Non-Goals (all filed as tracked follow-up issues)

- **Cron cost-enforcement** (Kieran P0-1) — **[#5902](https://github.com/jikig-ai/soleur/issues/5902), p1, top-priority** — the real threat surface.
- **Rolling-24h founder budget** — **[#5903](https://github.com/jikig-ai/soleur/issues/5903)** — product increment, not the safety floor, can't see crons.
- **Per-run cost ceiling** (CFO, default $20) — **[#5904](https://github.com/jikig-ai/soleur/issues/5904)**.
- **Pre-run cost estimate** (avg, not p95; no HITL modal) — **[#5905](https://github.com/jikig-ai/soleur/issues/5905)**.
- **Doom-loop detector** — web-only, own ADR, behind telemetry — **[#5906](https://github.com/jikig-ai/soleur/issues/5906)**.
- **Resume-from-checkpoint apparatus** — v2 uses **terminal-halt**: operator resumes by clearing the pause
  and starting a fresh run. No checkpoint/re-bill/cycle-cap machinery.

## Files to Edit / Create

- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`
  - **Spawn-entry pause gate** (before the turn loop, ~`:319`): read `users.runtime_paused_at`; if set,
    halt immediately via `persistFailure(reason: "byok_cap_exceeded")` (or a new `run_paused` reason) —
    do NOT enter the loop. Closes P0-A consequence #1.
  - **Notification** in `persistFailure` (`:913-962`), the **single** site: call `notifyOfflineUser(founderId, {type:"cost_breaker_tripped", ...})` BEFORE the `action_sends` UPDATE (mirror the existing Sentry-mirror ordering). Fire ONLY for the enumerated cost/loop subset — `cost_ceiling_exceeded | byok_cap_exceeded | leader_max_turns_exceeded` — and a new distinct **`cap_check_unavailable`** reason (P2-H) so a transient DB error does NOT send a false "budget exceeded" alert. **Never** notify on `cancelled_by_operator`.
  - Terminal contract unchanged: returns `{acknowledged:false, failureReason}`, never throws (already true, `:925/:961` — TR1 for this surface; `ok:false` is the *cron* shape, do not use it here).
- `apps/web-platform/server/byok-cap-rpc.ts` — do **NOT** add notification here (P1-4: it already funnels
  through `persistFailure`; double-notify + violates the pure-RPC-wrapper single responsibility).
- `apps/web-platform/supabase/migrations/061_...` follow-up migration — make the cap RPC return
  `kill_tripped = true` whenever `runtime_paused_at IS NOT NULL` (not transition-only), so a paused
  founder's next spawn re-blocks even if the entry-gate is bypassed. Defense-in-depth for P0-A.
- **Operator-resume clearer** — a route/action that sets `runtime_paused_at = NULL` (the only clearer);
  reachable from the halt banner/email CTA. Wireframe `03a`/`03c` "Resume" now means "clear pause + start
  a fresh run" (terminal-halt).
- `apps/web-platform/server/notifications.ts:72-91` — extend `NotificationPayload` with
  `CostBreakerNotificationPayload { type:"cost_breaker_tripped"; reason: <subset>; which_window: "spawn"|"cap-1h"; context:{cumulativeCents, ceilingCents} }` (P2-G `which_window`); add push body (`:224-250`) + email template (`:314-344`).
- `docs/legal/terms-and-conditions.md` §3a.5 (already false in prod) + §11 (clo-attestation).
- `knowledge-base/legal/article-30-register.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-041-...md` — amend `## Decision` (notification
  layer + working-pause contract) + reconcile the stale "daily soft $20/hard $50/monthly $500" prose vs
  the SQL `interval '1 hour'` (P2-9).
- `knowledge-base/engineering/architecture/decisions/ADR-042-...md` — fix frontmatter `adr: 040` → `042`
  + title (P2-I, pre-existing bug).

## Acceptance Criteria

### Pre-merge
- **AC1 — pause is real (blocking, SAFETY):** a spawn whose founder has `runtime_paused_at` set halts at
  the entry gate WITHOUT entering the turn loop (no Anthropic call). DEV repro: seed a paused founder,
  invoke, assert zero `audit_byok_use` rows added.
- **AC2 — resume clears (blocking):** the operator-resume action is the ONLY code path that sets
  `runtime_paused_at = NULL`; cap-check steps never clear it. Grep-assert no other clearer exists.
- **AC3 — notify one site, right reasons:** `notifyOfflineUser({type:"cost_breaker_tripped"})` fires from
  `persistFailure` for `cost_ceiling_exceeded|byok_cap_exceeded|leader_max_turns_exceeded|cap_check_unavailable`
  and NOT for `cancelled_by_operator`; fires BEFORE the `action_sends` UPDATE; fires from no other site
  (grep-assert single call site). `cap_check_unavailable` is a distinct reason (P2-H).
- **AC4 — honest copy (matches wireframe `03a`/`03c`):** payload carries dollars (not tokens), amount-vs-
  ceiling, `which_window`, and never implies the run completed.
- **AC5 — legal/ADR:** ToS §3a.5 no longer claims "no Jikigai-provided cost ceiling"; §11 overage
  carve-out present; ADR-041 amended + daily/monthly prose reconciled; ADR-042 frontmatter fixed; Art.30
  updated; `/soleur:gdpr-gate` clean (no Art.9).

### Post-merge (operator)
- **AC6:** `Closes #5767` (v2 is a single PR — the follow-ups get their own issues). Confirm the 5
  follow-up issues exist and are linked before marking ready.

## Observability

```yaml
liveness_signal:
  what: cost_breaker_tripped notifications + runtime_paused_at state
  cadence: per-halt (event-driven)
  alert_target: Sentry (reportSilentFallback op) + operator WS/Push/Email
  configured_in: notifications.ts; agent-on-spawn-requested.ts persistFailure
error_reporting:
  destination: Sentry via reportSilentFallback (agent-on-spawn-requested.ts:927)
  fail_loud: notification-send failure mirrors to Sentry (cq-silent-fallback-must-mirror-to-sentry); never swallowed
failure_modes:
  - {mode: notification send fails, detection: Sentry op=notify-cost-breaker fail_loud, alert_route: Sentry issue alert}
  - {mode: pause set but never blocks (P0-A regression), detection: cap-RPC returns kill_tripped when paused + entry-gate test, alert_route: CI (AC1) + Sentry}
  - {mode: transient cap-check DB error mis-notified, detection: distinct cap_check_unavailable reason, alert_route: Sentry (not a false user alert)}
logs:
  where: pino structured (existing)
  retention: existing
discoverability_test:
  command: "supabase execute_sql read-only: SELECT count(*) FROM users WHERE runtime_paused_at IS NOT NULL; + Sentry op query — NO ssh"
  expected_output: paused founders enumerable; halt events queryable in Sentry
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-041** (`## Decision` + `## Alternatives Considered`): the notification layer + the
working-pause contract (set-never-clear; entry-gate reader; RPC returns kill_tripped while paused).
Reconcile the stale daily/monthly prose. Cap-policy changes isolate to ADR-041 by its own design — **no
new ADR** (doom-loop / enforcement-topology deferred with PR-C, so ADR-042's per-turn topology is
untouched by v2 except the pre-existing frontmatter bug fix).

### C4 views
Checked against all three `.c4` files: `founder` actor (`model.c4:8`), `resend` system + `webapp/api →
resend` outbound edge (`:234,258,291`) already model the notification path. **One candidate new edge:**
web-push (VAPID) — verify at work time; add element + `#external` tag + edge + `views.c4` include only if
genuinely unmodeled, then run `apps/web-platform/test/c4-*.test.ts`. No new external actor.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance

### Engineering (CTO carry-forward + arch-strategist plan-review)
**Status:** reviewed. Terminal `{acknowledged:false}` return (never throw) — TR1 for the leader loop.
Working-pause contract (P0-A) is the core. Notify one site. ADR-041 amend (not new ADR).

### Product/UX Gate
**Tier:** blocking. **Decision:** reviewed. **Agents invoked:** ux-design-lead (brainstorm), spec-flow-analyzer (plan).
**Pencil available:** yes — `.pen` committed. **Surfaces in v2 scope:** halt banner `03a` + halt email `03c`
(notification). `01` estimate, `02` HITL modal, `03b` doom-loop banner defer with their features.
**spec-flow:** its 4 P0 recovery-flow gaps are **dissolved** by terminal-halt (no resume apparatus) — the
recovery story is "halt → notify → operator clears pause + starts fresh."
**Skipped specialists:** none.

### Legal (CLO carry-forward)
**Status:** reviewed. **P0:** ToS §3a.5 already false in prod — amend §3a.5/§11 in PR-A (clo-attestation).
Notification payload minimized to cost aggregates + run-id (TR5). Art.30 + DPD + GDPR Policy lockstep.

### Finance (CFO plan-time)
**Status:** reviewed. Recommended a per-run $20 ceiling; deferred as a follow-up. No new default value
needed in v2 (no new cap column ships).

## Plan Review (5-agent panel, 2026-07-02)

Ran DHH + Kieran + code-simplicity + architecture-strategist + spec-flow (single-user-incident → 5-agent).
**Outcome: major simplification (v1→v2).** All five converged on cutting the 24h window + doom-loop +
resume apparatus and shipping notification-on-existing-caps as the MVP. Load-bearing correctness catches
folded in: P0-A broken-pause (arch), P0-1 cron-blindness (Kieran, → top follow-up), wrong-table counter
(→ N/A, doom-loop deferred), double-notify (→ one site), TR1 return-shape per surface, PR-D redaction
fail-open (→ deferred with cron work), ADR routing + ADR-042 frontmatter, `which_window`, `cap_check_unavailable`.

## Risks & Mitigations
- **Pause-gate bypass:** defense-in-depth — entry-gate reader AND RPC-returns-kill_tripped-while-paused
  (two independent blocks) so a missed gate still can't spend.
- **Notification-send failure** fails loud to Sentry, never swallowed (`cq-silent-fallback-must-mirror-to-sentry`).
- **Terminal-halt re-does work on a fresh run** (re-spends BYOK) — accepted: the founder is explicitly in
  control at resume; simpler and safer than a checkpoint state machine that fights the attempt-reset model.

## Open Code-Review Overlap
None. Checked all 61 open `code-review` issues against the planned files — zero matches.

## Sharp Edges
- `## User-Brand Impact` filled (deepen-plan Phase 4.6 gate).
- The 5 follow-up issues MUST be filed before PR-ready (Step 6 deferral check) — cron cost-enforcement is
  top-priority; it is the real overnight-burn surface.
