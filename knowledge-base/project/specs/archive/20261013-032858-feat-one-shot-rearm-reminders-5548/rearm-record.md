# #5548 re-arm record — reminders lost in the #5542 durable cutover

**Date:** 2026-06-18
**Executed by:** in-session (`/soleur:one-shot`), no operator handoff
**Endpoint:** `POST https://app.soleur.ai/api/internal/schedule-reminder` (Bearer `INNGEST_MANUAL_TRIGGER_SECRET`, read-only from Doppler `-c prd`)
**Pre-flight:** prod `/health` 200 (`version 0.154.3`, supabase connected); #5417 + #5469 confirmed OPEN with no prior `sentry-issue-rate` / re-eval comment (not already fired).

## Re-armed (HTTP 202 ×2)

### `verify-server-startup-rate-5417` — fire 2026-06-19T09:00:00Z

```json
{
  "reminder_id": "verify-server-startup-rate-5417",
  "fire_at": "2026-06-19T09:00:00Z",
  "actor": "platform",
  "action": {
    "type": "named-check",
    "check": "sentry-issue-rate",
    "report_to_issue": 5417,
    "params": { "tag": "event_type:server-startup", "max_per_day": 1, "window_hours": 72, "close_on_pass": true }
  }
}
```

- Payload copied verbatim from the blessed form in `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md` §A (ADR-063).
- `params.tag` is colon-form per `TAG_RE` (`^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$`, `apps/web-platform/lib/inngest/sentry-issue-rate.ts:22`); `window_hours=72 ∈ [24,168]`.
- Response: `{"scheduled":"verify-server-startup-rate-5417","fire_at":"2026-06-19T09:00:00Z"}`
- Distillation note: #5417's fuller AC12/AC13 task spec (OOM-pages + firewall self-heal) is intentionally out of scope; ADR-063 + the runbook blessed the one-line `sentry-issue-rate` arm (≤1/day check + auto-close on pass) as the canonical reconstruction.

### `reeval-5469-routine-runs-gate-2026-07-01` — fire 2026-07-01T09:00:00Z

```json
{
  "reminder_id": "reeval-5469-routine-runs-gate-2026-07-01",
  "fire_at": "2026-07-01T09:00:00Z",
  "actor": "platform",
  "action": {
    "type": "issue-comment",
    "issue": 5469,
    "body": "Reminder (re-armed after the #5542 cutover): re-evaluate whether heavy claude-spawning crons still need explicit `routine_runs` instrumentation, now that `routine_runs` (deployed 2026-06-16) has ≥14 days of data and the inbound-ingress fix has shipped. See #5469 re-eval criterion."
  }
}
```

- Body restates #5469's re-eval criterion; length 281 ≤ `MAX_COMMENT_BODY` (65000).
- Response: `{"scheduled":"reeval-5469-routine-runs-gate-2026-07-01","fire_at":"2026-07-01T09:00:00Z"}`

## Not re-armed (disposition recorded — AC3)

### `rebase-dependabot-5432-otel-2026-06-18` (×2) — **dropped**

- Original fire window (2026-06-18 13:00) is **already past**.
- Reminder body was **never recorded** — only inferred as `@dependabot rebase`; fabricating a payload risks a wrong/misleading comment.
- Out of the documented #5548 re-arm scope (PIR `inngest-durable-redis-missing-outage-postmortem.md` names only 5417 + 5469).
- Alternative: `@dependabot rebase` can be commented directly on #5432 (OPEN, stale branch) if the otel bump is still wanted — no future-dated reminder is needed for a past-due one-shot rebase nudge.

## Idempotency

The route recomputes the Inngest dedup keys from the body (`id`=`reminder_id`, `ts`=`Date.parse(fire_at)`, `route.ts:128-133`), so re-running the SAME re-arm POST within Inngest's ~24h dedup window dedups instead of double-firing. The dedup is window-bounded, **not** a permanent cross-boot guarantee — moot here since #5542 left the queue empty (nothing to dedup against).

## Confirmation (AC8)

The two 202 responses are the acceptance evidence (a 202 means the `reminder.scheduled` event was durably accepted by the new Postgres+Redis backend — a down backend would have returned 502, not 202). Ongoing liveness is covered by the external inngest health watchdog (`scheduled-inngest-health.yml`, shipped #5549). On-host `op=inventory` confirmation is deferred to that watchdog.
