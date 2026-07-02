---
plan: L5 Runaway Guard — doom-loop detection + token/cost circuit breaker
issue: 5767
branch: feat-l5-runaway-guard
draft_pr: 5881
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
created: 2026-07-02
brainstorm: knowledge-base/project/brainstorms/2026-07-01-l5-runaway-guard-brainstorm.md
spec: knowledge-base/project/specs/feat-l5-runaway-guard/spec.md
---

# ✨ Plan: L5 Runaway Guard

Full-scope L5 "agent-as-process safety" layer, staged as a dependency-ordered multi-PR train. Stops an
unattended autonomous run from silently burning a non-technical founder's own BYOK credits.

## Overview

Six gaps from the brainstorm, re-scoped after plan-time verification against ADR-041/042/077 + the CFO
consult. Much of the "circuit breaker" is **already built** (see Research Reconciliation); the genuine,
high-value work is **notification on trip**, a **founder-facing 24h budget ceiling**, a **pre-run
estimate**, a **doom-loop detector**, and **cron-substrate token metering**.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Verified reality | Plan response |
|---|---|---|
| "No run-wide cost ceiling exists" | **False.** `record_byok_use_and_check_cap` (`apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`) enforces a per-founder **rolling-1h** cap vs `users.runtime_cost_cap_cents`, sets `runtime_paused_at` on breach | Do NOT rebuild. PR-A adds a **founder-facing rolling-24h budget** window alongside the internal 1h safety valve (operator decision 2026-07-02) |
| "Ceiling is not operator-tunable" | Partial — `runtime_cost_cap_cents` (per-founder) exists; no settings UI confirmed | PR-A surfaces + makes tunable; adds a distinct 24h-window column (do NOT overload the 1h column — CFO) |
| "No notification when a ceiling trips" | **True.** Both the cap RPC and `persistFailure` (`agent-on-spawn-requested.ts:913-962`) are silent (Sentry-only) | PR-A: core deliverable — wire `notifyOfflineUser` + new `cost_breaker_tripped` type |
| "Per-turn Inngest step checks cumulative tokens" (issue framing) | Misconception for crons: `_cron-claude-eval-substrate.ts:818` spawns opaque `claude --print`. The **leader loop** (`agent-on-spawn-requested.ts:323-399`) does meter per-turn (3-layer guard) | PR-D switches crons to `stream-json`; PR-A/C extend the leader loop |
| Pre-run estimate / doom-loop detection | **Both MISSING** (confirmed) | PR-B (estimate), PR-C (doom-loop) |
| ADR needed for enforcement topology | ADR-041 explicitly isolates cap-policy changes; ADR-042 = loop topology; ADR-077 = live-state | **Amend ADR-041** (not a new ADR) + note C4 |

## User-Brand Impact

**If this lands broken, the user experiences:** the agent-run supervisor
(`agent-on-spawn-requested.ts`) fails to halt or fails to notify — an unattended run keeps spending the
founder's own Anthropic credits with no signal.
**If this leaks, the user's money is exposed via:** a silent overnight doom-loop / runaway consuming the
founder's BYOK credits (hundreds/thousands of dollars) with no artifact shipped and no notice.
**Brand-survival threshold:** single-user incident.

> **Residual risk (operator-accepted 2026-07-02):** PR-A ships a rolling-**24h-per-founder** window, not a
> per-**run** ceiling. A single runaway run can still legitimately consume the entire 24h budget in one
> overnight event before the window resets. The per-run guard (CFO-recommended, default $20) is deferred
> as a tracked follow-up (see Non-Goals) — not silently dropped.

CPO sign-off carried forward from brainstorm (`USER_BRAND_CRITICAL=true`, triad spawned). `user-impact-reviewer`
runs at review time (review/SKILL.md conditional-agent block).

## Goals

1. **Notification on any cost/loop halt** (core) — reuse `notifications.ts` WS→Push→Email; new
   `cost_breaker_tripped` payload type; wire into `persistFailure` AND the cap-RPC breach path.
2. **Founder-facing rolling-24h budget ceiling** — new per-founder 24h-window column, operator-tunable
   (dollars), notified, coexisting with the internal rolling-1h safety valve.
3. **Pre-run cost estimate** — always shown at kickoff, derived from `audit_byok_use` history per
   `agent_role`; **opt-in** HITL approval for founder-armed high-cost routines (no blanket gate — honors
   `wg-verified-work-ships-without-asking`).
4. **Doom-loop detector** — nudge→halt on repeated no-progress edits; web leader loop + CC plugin; reuse
   `stop-hook.sh` hash+Jaccard math.
5. **Cron-substrate token metering** — switch heavy crons to `--output-format stream-json --verbose`;
   tally cumulative tokens in `routine_run_progress`.
6. **Legal/architecture reconciliation** — amend ToS §3a.5/§11, Article 30 register, `/soleur:gdpr-gate`,
   amend ADR-041.

## Non-Goals

- **Per-run cost ceiling** (CFO-recommended, default $20). Deferred to a tracked follow-up issue — the
  rolling-24h-per-founder window was chosen instead (operator, 2026-07-02). Re-eval when overnight-burn
  telemetry shows a single-run event consuming the full 24h budget.
- A single unified runtime primitive across web + CC — surfaces diverge on enforcement (web = pre-emptive
  kill; CC = best-effort at tool/Stop boundaries). Share policy schema + hash math only.
- Blanket per-kickoff HITL approval gate.
- A new per-edit-event table (WAL-budget risk — fold counters into `routine_run_progress`).
- Metering the two crons that bypass `spawnClaudeEval` (`cron-daily-triage`, `cron-follow-through-monitor`)
  — deferred per ADR-077 v1 (never false-stuck).

## Build Sequence (multi-PR train)

### PR-A — Safety floor (notification + 24h budget) — MVP
**Files to Edit / Create:**
- `apps/web-platform/supabase/migrations/<next>_runtime_daily_cost_cap.sql` (**create**) — add
  `users.runtime_daily_cost_cap_cents int` (default 2000 = $20; tunable) + a rolling-24h SUM check helper
  (mirror the mig-061 RPC window pattern, `ts > now() - interval '24 hours'`). **gdpr-gate (Phase 2.7):**
  annotate the column `-- LAWFUL_BASIS: Art. 6(1)(b) contract performance — operator's own spend-control
  preference`; if the `cost_breaker_tripped` event is persisted (beyond ephemeral WS/Push/Email), declare
  Art. 5(1)(e) retention on that row. No Art. 9 / no new FK-to-`users` / no new non-EEA vendor.
- `apps/web-platform/server/notifications.ts:72-91` — extend `NotificationPayload` union with
  `CostBreakerNotificationPayload { type: "cost_breaker_tripped"; reason: <failure_reason subset>; context: {...cents} }`; add push body (`:224-250`) + email template (`:314-344`).
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts:913-962` — call
  `notifyOfflineUser(founderId, payload)` from `persistFailure` for cost/loop reasons, BEFORE the row
  UPDATE (mirror the existing Sentry-mirror ordering). **Return terminal `ok:false`; never throw** (TR1).
- `apps/web-platform/server/byok-cap-rpc.ts` — wire notification on `killTripped` / `runtime_paused_at`.
- Settings UI (dollars) surfacing `runtime_cost_cap_cents` (existing) + `runtime_daily_cost_cap_cents`
  (new). UI files per wireframes.
- `docs/legal/terms-and-conditions.md` §3a.5 + §11 (clo-attestation); `knowledge-base/legal/article-30-register.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-041-byok-cap-enforcement-model.md` (amend).

### PR-B — Pre-run estimate + opt-in HITL
- Estimate: query `audit_byok_use` p95/avg `unit_cost_cents` per `agent_role` over 30d × max-turns.
- Kickoff surface renders the estimate (dollars); opt-in HITL modal for armed high-cost routines.
- Wireframes: `knowledge-base/product/design/runaway-guard/screenshots/01-*`, `02-*`.

### PR-C — Doom-loop detector (web + CC)
- Extract `stop-hook.sh:88-258` hash+Jaccard+repeat logic into a shared helper.
- Web: per-target `(file_path+diff)` hash counter in `routine_run_progress` (`progress_counters jsonb`);
  nudge → halt after N; terminal `ok:false` (TR1).
- CC: PostToolUse(Edit|Write) hook (template: `.claude/hooks/agent-token-tee.sh`); best-effort.

### PR-D — Cron-substrate token metering (gated)
- `_cron-claude-eval-substrate.ts:818` → prepend `--output-format stream-json --verbose`; parse per-line
  JSON in the readline loop (`:828-846`); redact within `.message`/`.content` before logging; tally
  `usage` into `routine_run_progress.cumulative_tokens`.
- **Go/no-go gate:** touches redaction + bounded-tail; if not approved, cron cost control stays coarse
  (wall-clock + `--max-turns`) and this PR degrades to a documented limitation.

### ADR / C4
- Amend ADR-041 `## Decision` + `## Alternatives Considered` (24h founder-facing window, notification
  layer, per-run guard deferral rationale).
- C4: notification reuses the existing `webapp → resend` outbound edge + `founder` actor
  (`model.c4:8,234,258`); web-push is the one candidate new edge — verify against all three `.c4` files
  at work time and add the edge + `views.c4` include only if genuinely unmodeled.

## Acceptance Criteria

### Pre-merge (per PR)
- **AC1 (PR-A):** A cost/loop halt calls `notifyOfflineUser` with `type: "cost_breaker_tripped"` BEFORE
  the `action_sends` UPDATE — assert via unit test capturing call order.
- **AC2 (PR-A):** New `runtime_daily_cost_cap_cents` column exists, default 2000; a rolling-24h SUM ≥ cap
  sets `runtime_paused_at` and fires the notification. Verify: `BEGIN; SELECT rpc(...); ROLLBACK;` on a
  seeded row (DEV only — never prod, per `hr-dev-prd-distinct-supabase-projects`).
- **AC3 (PR-A):** Halt notification payload contains dollars (not tokens), amount-vs-ceiling, reason,
  what-shipped, one next action (matches wireframe copy).
- **AC4 (PR-A):** ToS §3a.5 no longer states "does not include a Jikigai-provided cost ceiling"; §11
  overage carve-out cross-references the breaker. Art.30 register updated. `/soleur:gdpr-gate` clean.
- **AC5 (PR-A):** ADR-041 amended; drift-guard test (`expect(src).not.toMatch(/\b20\b.../)` scope) still passes.
- **AC6 (PR-B):** Kickoff shows an estimate derived from `audit_byok_use`; no approval prompt unless the
  routine is opted-in high-cost.
- **AC7 (PR-C):** A synthetic run repeating an identical `(file_path+diff)` N times emits a nudge then
  halts terminally (returns `ok:false`, no Inngest replay). Test drives the reducer directly (LLM removed
  from the assertion path).
- **AC8 (PR-D, if go):** A cron run records non-zero `routine_run_progress.cumulative_tokens`; redaction
  still strips secrets from stream-json lines.

### Post-merge (operator)
- **AC9:** `Ref #5767` (NOT `Closes` — multi-PR train); close #5767 after PR-D (or its deferral) lands.

## Observability

```yaml
liveness_signal:
  what: cost_breaker_tripped notifications + routine_run_progress rows
  cadence: per-halt (event-driven) + 30s heartbeat (existing)
  alert_target: Sentry (existing reportSilentFallback op) + operator WS/Push/Email
  configured_in: apps/web-platform/infra/sentry/*.tf (extend), notifications.ts
error_reporting:
  destination: Sentry via reportSilentFallback (agent-on-spawn-requested.ts:927)
  fail_loud: notification-send failure mirrors to Sentry (cq-silent-fallback-must-mirror-to-sentry); never swallow
failure_modes:
  - {mode: notification send fails, detection: Sentry op=notify-cost-breaker fail_loud, alert_route: Sentry issue alert}
  - {mode: 24h-cap RPC read error, detection: fail-closed THROW → Sentry, alert_route: Sentry}
  - {mode: doom-loop counter false-positive (halts real work), detection: in-surface structured event source/editHash/repeatCount, alert_route: Sentry}
  - {mode: cron stream-json parse error (PR-D), detection: in-surface parse-fail event emitted from the cron, alert_route: Sentry}
logs:
  where: pino structured (existing) + routine_run_progress
  retention: existing
discoverability_test:
  command: "gh api / supabase execute_sql read-only: SELECT count(*) FROM routine_run_progress; + Sentry op query — NO ssh"
  expected_output: non-empty on active run; halt events queryable in Sentry
```

**2.9.2 affected-surface:** the doom-loop detector + cron metering touch blind surfaces (Inngest
worker, agent-run dispatch). Each `failure_mode.detection` above names an **in-surface** probe emitting
discriminating structured fields (`source`/`editHash`/`repeatCount` for the loop; `parse_ok`/`token_delta`
for the cron), not just a host-side gate — per `hr-observability-as-plan-quality-gate` +
`observability-coverage-reviewer` §4.6.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-041** (`## Decision` + `## Alternatives Considered`): add the founder-facing rolling-24h
window as a new cap layer, the notification layer, and record the per-run-ceiling deferral + rationale.
Cap-policy changes isolate to ADR-041 by its own design (no new ADR; ADR-042 loop topology untouched).

### C4 views
Enumerated against all three `.c4` files: `founder` actor (`model.c4:8`), `anthropic` + `resend` systems
(`:206,234`), `webapp/api → resend` outbound-email edge (`:258,291`) — all already modeled. The
notification reuses these. **One candidate new edge:** web-push (VAPID) delivery — verify at work time
whether a push endpoint/system is modeled; if not, add the element + `#external` tag + edge +
`views.c4` include, and run `apps/web-platform/test/c4-*.test.ts`. No new external human actor.

### Sequencing
ADR-041 amendment ships in PR-A (describes target state; per-run deferral noted as a tracked follow-up).

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance

### Engineering (CTO — carry-forward from brainstorm)
**Status:** reviewed. Hard-halt only via the `AbortController` SIGTERM→SIGKILL seam; terminal `ok:false`
never throw (replay-safety); counters in `routine_run_progress`, not a new table; surfaces diverge, share
policy+hash. ADR-041 amendment.

### Product (CPO — carry-forward)
**Status:** reviewed. Table-stakes; conservative default-on tunable; honest halt copy (dollars, never
imply completion); roadmap flag — prerequisite for Phase-4 unattended cohort (#1442).

### Product/UX Gate
**Tier:** blocking (UI surfaces: estimate panel, HITL modal, halt banner, halt email).
**Decision:** reviewed (brainstorm carry-forward — wireframes PRODUCED, not just idea-validated).
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55), spec-flow-analyzer (Phase 3, below).
**Skipped specialists:** none.
**Pencil available:** yes — `.pen` committed at `knowledge-base/product/design/runaway-guard/l5-runaway-guard-surfaces.pen`, referenced in FR2/FR4/FR5.

### Legal (CLO — carry-forward)
**Status:** reviewed. **P0:** ToS §3a.5 already false in prod (per-founder cap shipped) — amend §3a.5/§11
in PR-A (clo-attestation, counsel-review gate). Notification payload minimized to cost aggregates + run-id.
Art.30 + DPD + GDPR Policy lockstep. `/soleur:gdpr-gate` at Phase 2.7.

### Finance (CFO — plan-time consult, 2026-07-02)
**Status:** reviewed. Recommended a per-**run** ceiling (default $20, range $5–$50) nested below existing
aggregate caps; operator chose the rolling-24h-per-founder window instead. Per-run guard recorded as a
tracked deferral (Non-Goals). For the 24h window, default $20 (aligns with the existing daily soft-cap
anchor), tunable in dollars.

## Risks & Mitigations

- **Replay-loop on throw** (TR1): a doom-loop/budget halt that throws re-enters `spawnClaudeEval` on
  Inngest replay and loops the runaway → **return terminal `ok:false`, check counter on entry.**
- **Counter reset per attempt** (ADR-077): `routine_run_progress` upsert resets on `attempt>1`; counters
  that must survive retries need idempotency-keyed accumulation, not reset. Verify at work time.
- **Two windows coexist:** internal 1h safety valve (`runtime_cost_cap_cents`) + new founder-facing 24h
  budget — whichever is tighter trips first; document both in settings copy so the founder isn't confused.
- **Notification-send failure** must fail loud to Sentry, never swallow (`cq-silent-fallback-must-mirror-to-sentry`).

## Open Code-Review Overlap

None. Checked all 61 open `code-review` issues against the 6 planned files
(`agent-on-spawn-requested.ts`, `notifications.ts`, `byok-cap-rpc.ts`,
`_cron-claude-eval-substrate.ts`, `routine-run-progress`, `stop-hook.sh`) — zero matches.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — filled above.
- Per-run guard deferral must produce a tracking issue (Step 6 deferral check) — not silent.
