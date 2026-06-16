---
category: engineering
tags: [inngest, oneshot, reminder, scheduling, observability]
date: 2026-06-03
---

# Future-dated actions: Inngest oneshot + generic reminder primitive

How to schedule a **one-time, future-dated, server-side action** (a verification,
an issue comment, a check) in this codebase. Read the decision matrix first, then
the integration steps for whichever mechanism fits.

## Decision matrix — "I need a future-dated action"

| Mechanism | Autonomous? | Needs a deploy? | Fire-time secrets / repo write? | Dies with session? | Use when |
|-----------|-------------|-----------------|---------------------------------|--------------------|----------|
| **Session cron** (`CronCreate`, `/loop`) | no — needs the Claude session alive | no | no | **YES** | Never for anything durable. Only for in-session polling you'll watch. |
| **GitHub-Actions follow-through sweeper** (`scripts/sweep-followthroughs.sh`, `/ship` Step 3.5) | semi — CI-driven | no (script + `earliest` in an issue) | no fire-time Doppler secret (CI env only) | no | A check expressible as a shell script run by CI on/after a date; operator-confirmable gates. |
| **Self-armed Inngest oneshot** (ADR-046) | **yes** — server-side | **yes** — a new reviewed `oneshot-*.ts` per action | **yes** — full prd env + installation token | no | A one-off verification with bespoke logic that needs fire-time secrets / repo writes (e.g. `oneshot-4650-monitor-close`, `oneshot-heartbeat-recovery-verify`). |
| **Generic reminder primitive** (`event-scheduled-reminder`) | **yes** — server-side | **NO per-reminder deploy** (only the one-time function deploy) | **yes** — installation token, allowlisted | no | A one-off **issue comment** or a **registered check** — arm via `POST /api/internal/schedule-reminder`, no code change. |

**Rule of thumb:** if the action is "post this comment / run this *registered*
check at time T," use the **reminder primitive** (no deploy). If the logic is
bespoke and not expressible as a registered check, ship a **self-armed oneshot**.

## A. Generic reminder primitive (no per-reminder deploy)

Arm a reminder by POSTing to the secret-gated endpoint — no code change, no deploy:

```bash
SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -fsS -X POST "https://app.soleur.ai/api/internal/schedule-reminder" \
  -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" \
  -d '{
    "reminder_id": "verify-x-2026-07-01",
    "fire_at": "2026-07-01T09:00:00Z",
    "actor": "platform",
    "action": { "type": "issue-comment", "issue": 2714, "body": "Reminder: verify X." }
  }'
# → 202 { "scheduled": "verify-x-2026-07-01", "fire_at": "..." }
```

`action` is an **allowlisted discriminated union** (`apps/web-platform/lib/inngest/scheduled-reminder-action.ts`):

- `{ type: "issue-comment", issue, body }` — posts a comment (body ≤ 65000 chars).
- `{ type: "named-check", check, params?, report_to_issue }` — runs a server-side
  **registered** check (`CHECK_REGISTRY` in `event-scheduled-reminder.ts`), posts
  its result to `report_to_issue`, and routes a `verdict:"fail"` to Sentry.

To add a new check, add a code-reviewed entry to `CHECK_REGISTRY` (this IS a deploy,
once) — thereafter that check is schedulable by name with no further deploy.

### Worked example: `sentry-issue-rate` (the reusable verification check)

`{ type: "named-check", check: "sentry-issue-rate", report_to_issue, params: {
tag, max_per_day, window_hours, close_on_pass? } }` reads the events/day of the
Sentry issue matched by `tag` (a single `key:value` search term) over
`window_hours` and posts a `pass`/`fail` verdict to `report_to_issue`. PASS iff
`events/day <= max_per_day`. Reuses fire-time prd env (`SENTRY_API_HOST`,
`SENTRY_ORG`, `SENTRY_PROJECT`, and **`SENTRY_ISSUE_RW_TOKEN`** — the issue-scoped
token; `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` 403 on the org issues endpoint, per
the 2026-06-16 live probe). Every future "did Sentry issue X drop below N/day?"
verification is now a **zero-deploy POST** (no new code). Example arm:

```
POST /api/internal/schedule-reminder   (Bearer INNGEST_MANUAL_TRIGGER_SECRET)
{ "reminder_id": "verify-server-startup-rate-5417", "fire_at": "2026-06-19T09:00:00Z",
  "actor": "platform",
  "action": { "type": "named-check", "check": "sentry-issue-rate", "report_to_issue": 5417,
    "params": { "tag": "event_type:server-startup", "max_per_day": 1, "window_hours": 72, "close_on_pass": true } } }
```

**Close-mutation invariant (v1.1).** A check may set `close: boolean` on its
result; the handler then closes **`action.report_to_issue`** (state=closed,
state_reason=completed) — NEVER a check-returned issue number. The boolean shape
makes an arbitrary-issue close structurally unrepresentable. Fail-closed (`info`,
never close) on missing env / invalid params / Sentry HTTP error / 0-or->1
matching issues. See ADR-063.

**Security model:** the endpoint is gated by `INNGEST_MANUAL_TRIGGER_SECRET`
(operator-held in Doppler), the same trust boundary as `trigger-cron`. A
secret-holder gains the **same capability the operator already has** (`gh issue
comment` / a registered check / close the check's own report issue),
time-delayed. No arbitrary code; v1.1 close is scoped to `report_to_issue` only.
The action allowlist is validated at BOTH the endpoint (pre-send 400) and the
handler (post-receive guard) — defense-in-depth. The route↔handler
`CHECK_REGISTRY` asymmetry (route accepts any string `check`; handler owns the
membership reject at fire time) is intentional.

**`soleur:schedule` routes here automatically.** That skill's `create` Step 0
execution-substrate gate sends any fire-time-secret / server-side scheduled task
to this primitive (named-check for verification shapes) instead of generating
GHA-cron — Inngest is the structural default; GHA is the pure-GH-ops exception.

## B. Self-armed Inngest oneshot (bespoke logic, one deploy)

A oneshot is a function triggered by a `oneshot/<name>.fire` event, **armed at
container boot** in `server/index.ts` via `inngest.send({ name, id, ts, data })`
with a **future `ts`** (Inngest natively schedules the delayed delivery — no
`step.sleepUntil`). Copy `oneshot-TEMPLATE.ts.template` and fill it in.

### The 3 integration points (+ 1 easy-to-forget)

1. **New function file** `server/inngest/functions/oneshot-<name>.ts` (copy the template).
2. **Register** it in `app/api/inngest/route.ts` — add the import AND the entry in
   the `functions: [...]` array.
3. **Self-arm** in `server/index.ts` inside the `if (process.env.INNGEST_SIGNING_KEY)`
   boot block — a guarded `void (async () => { try … catch })()` IIFE that calls
   `sendInngestWithRetry(() => inngest.send({ name, id, ts: new Date("…").getTime(), data: { …, actor: "platform" } }), { feature: "<name>-arm" })`.
4. **(easy to forget)** Bump the count in
   `test/server/inngest/function-registry-count.test.ts` `(a)` — the array length
   is hard-asserted. A new `event-*`/`oneshot-*` function is NOT a cron, so do
   NOT add it to `EXPECTED_CRON_FUNCTIONS` / `KNOWN_UNMONITORED_SLUGS` /
   `cron-monitors.tf` (those guards are cron-only and would trip).

### Gotchas

- **Stable event `id` dedups within Inngest's ~24h window** — it is NOT the
  cross-boot idempotency guarantee. The handler's own state check (e.g.
  "is the issue already closed?") is what makes a re-fire safe.
- **Future-`ts` delivery; a late re-deploy past `ts` re-fires (degrades
  gracefully).** Because boot == deploy, the arm re-sends on every deploy. If the
  deploy lands after `ts`, the event fires immediately — make the handler's effect
  idempotent (or accept a duplicate, e.g. an extra informational comment).
- **NO Sentry cron monitor** for a oneshot (ADR-033 I3 / ADR-046 I3) — a
  non-recurring function would false-alert on "missed" check-ins. The **guarded
  boot-IIFE `catch` is the only lost-arm signal** (`reportSilentFallback feature:
  "<name>-arm"`); errors at fire time route via `reportSilentFallback`.
- **Mint the installation token INSIDE `step.run` and never return it** into
  persisted step state (`mintInstallationToken` from `_cron-shared.ts`). Each
  `step.run` that needs a token mints its own.

## References

- ADR-046 — Inngest oneshot scheduler: self-arm + registered-functions-only.
- ADR-033 — Inngest cron/oneshot runtime invariants.
- Precedent: `apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts`.
- Scaffold: `apps/web-platform/server/inngest/functions/oneshot-TEMPLATE.ts.template`.
- Reminder primitive: `event-scheduled-reminder.ts` + `lib/inngest/scheduled-reminder-action.ts` + `app/api/internal/schedule-reminder/route.ts`.
