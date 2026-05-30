# Learning: a "reuse the X-query code in file Y" premise needs a symbol grep — POSTing to a vendor ≠ being able to READ from it

## Problem

The #4654 brainstorm issue body instructed: "Reuse the Sentry-query code in
`apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts`." Taken at
face value, the first-consumer oneshot looked like a copy-paste of existing Sentry code.

It isn't. The watchdog queries the **Inngest** `/v1/functions` registry (`fetchRegistry`,
`cron-inngest-cron-watchdog.ts:274-293`) — it has **no** Sentry Crons API *read* code.
Repo-wide, Sentry is **write-only**: the only Sentry calls are heartbeat `POST`s via
`postSentryHeartbeat` (`_cron-shared.ts:46`). A grep for `sentry.io/api`,
`/monitors/.../check-ins`, `SENTRY_AUTH`, `/api/0/` across the inngest tree returns nothing.
The shared `SENTRY_*` regexes (`_cron-shared.ts:8-10`) validate the ingest/heartbeat **DSN**,
not a read **auth token** — which the project does not define at all. So the consumer needs
net-new Sentry-read code **and** a new auth-token env var, not a reuse.

## Solution

When an issue or plan says "reuse the <vendor>-query code in file Y," grep file Y for the
**specific external API symbol** the new code needs before accepting the reuse premise:

- For a *read*: grep for the read endpoint / auth symbol (`/monitors`, `/api/0/`,
  `<vendor>_AUTH`, `Authorization: Bearer`), not just the vendor name.
- A file that **writes** to a vendor (POST heartbeat, webhook, ingest DSN) is **not**
  evidence it can **read** from that vendor. Write-auth and read-auth are different
  credential classes with different env vars.

Surface the correction in the brainstorm doc's Open Questions / Capability Gaps with the exact
grep as evidence (per `hr` capability-gap evidence rule), so the plan budgets the net-new work
and provisions the missing token instead of inheriting a false "it's a copy-paste" estimate.

## Key Insight

Two compounding lessons from this brainstorm:

1. **POST ≠ GET on the same vendor.** "We already talk to Sentry" hid that we only *write* to
   it. Direction of the integration (read vs write) is the load-bearing detail, and it maps to
   distinct auth/env surfaces. Verify direction, not just vendor presence. This is the
   read-direction analog of the existing "verify is-X-mounted by grepping the consuming symbol"
   rule.

2. **For the oneshot pattern, the unsolved gap was *arming*, not the handler.** The 3 existing
   `oneshot-*.ts` handlers are ~96% mechanical (the 2 claude-eval ones differ in 4 identifier
   strings). What's genuinely unsolved is the **initial arm**: every oneshot is fired by a
   *manual* `pnpm exec inngest send … --ts … --id …` operator command (gdpr spec PM.1 still
   unchecked). When evaluating "generalize pattern P," locate the part that is *actually*
   repeated-by-hand-and-error-prone (here: the dated arming command, a "merge then remember to
   run a command" hazard), not the part that merely *looks* like boilerplate. The cheap win was
   committing the arm in code with a stable `id` (idempotent on redeploy), not abstracting the
   handler.

## Tags
category: workflow-patterns
module: inngest-oneshot-scheduler
refs: #4654, #4650, #3948
related: 2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md (leader substrate-claim cross-check)
