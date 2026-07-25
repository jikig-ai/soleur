---
title: Inngest one-time scheduler — registered-functions-only + self-arm-in-code
status: active
date: 2026-05-30
issue: "#4654"
related: [ADR-030, ADR-033, 5450]
---

# ADR-046: Inngest one-time scheduler — registered-functions-only + self-arm-in-code

## Context

The GHA `soleur:schedule --once` mechanism cannot host one-time tasks that need
fire-time secrets or repo writes: it has no Doppler secret access at fire time,
requires a default-branch merge before the fire date, and has fragile
self-neutralization (#4654 motivation). The Inngest substrate (ADR-030, ADR-033)
runs in-container with the full prd env + the GitHub App installation token, and
three hand-written `oneshot-*.ts` functions already prove the fire-once pattern
(`inngest.send({ ts, id })` + a D3 date guard).

Two recurring weaknesses motivated this ADR while shipping the first
secret/repo-write consumer (the #4650 monitor-close oneshot):

1. **Arming was a manual operator command.** Every existing oneshot is armed by
   a hand-typed `pnpm exec inngest send … --ts … --id …` — a "merge then
   remember to run a command on the right date" hazard, and an operator step a
   non-technical founder should never own.
2. **The substrate could be tempted toward an arbitrary-task-spec executor** (a
   generalized "run whatever spec this event carries" oneshot), which TR9 Phase 2
   (#3948, K21) already decided to keep OFF the substrate permanently.

## Considered Options

- **(A) Generalized scaffolding skill / declarative registry now** — rejected:
  one concrete consumer; the recurring-cron substrate earned `_cron-shared.ts`
  only at ~34 consumers; K26 (#3990) deferred the analogous migrate-skill on the
  same "don't productize before the corpus exists" logic.
- **(B) Arbitrary fetched-task-spec executor** — rejected: on the persistent,
  shared-`process.env` Inngest worker this reproduces the `followthrough-sweeper`
  model that K21 kept on ephemeral GHA runners (the selective-secret Art. 32 TOM
  is defeated when the full prd env is ambient to any spec). Art. 25(1) concern.
- **(C) Registered-functions-only + commit the arm in code** — chosen.

## Decision

1. **Registered-functions-only.** One-time tasks ship as code-reviewed
   `oneshot-*.ts` functions registered in `app/api/inngest/route.ts` (RV6 —
   manual, no barrel). The substrate MUST NOT run an arbitrary fetched task spec.
   Blast radius = what passed review. (Security-load-bearing; K3/K21.)
2. **Self-arm in code.** The initial `inngest.send({ name, id, ts, data })` is
   committed in the `server/index.ts` boot block (`app.prepare().then()`),
   fire-and-forget inside a guarded `void (async () => { try … catch })()` whose
   catch routes to `reportSilentFallback`. boot == deploy (web-platform-release.yml
   restarts the container on every `apps/web-platform/**` merge), so the arm fires
   each deploy; the stable event `id` dedups within Inngest's window. No manual
   `inngest send`.
3. **`inngest.send({ ts })`, not `step.sleepUntil`** — future-dated event
   delivery is the proven primitive (zero `sleepUntil` precedent in-tree) and is
   more durable than holding a sleeping step open. ~~Bounded by single-host SQLite
   durability (ADR-030) for far-future fires.~~ **Updated 2026-06-17 (#5450):** that
   bound changed — ADR-030's backend is now Supabase Postgres + self-hosted Redis
   (AOF on /mnt/data), so a far-future armed event now survives a host re-provision.
   The boot-arm/re-arm-every-deploy mechanism (item 2 above / ADR-030 I4) is **NOT**
   made redundant by the durable backend: it remains the recovery path within
   Inngest's dedup window and the re-plan-on-deploy path for de-planned crons.
4. **GHA `--once` coexists** — keep it for no-secret / no-repo-write
   analyze-report tasks; route fire-time-secret / repo-write tasks to Inngest.

**Load-bearing invariants:**

- **I1** — registered, reviewed functions only; no arbitrary-spec executor (K21
  boundary; the credential-leak vector).
- **I2** — idempotency lives in the handler's load-bearing state check (e.g.
  already-closed), NOT in stable-`id` dedup (bounded ~24h window).
- **I3** — per ADR-033's prefix table, oneshots get **no** Sentry cron monitor
  (a non-recurring fn would false-alert on missed check-ins); errors route via
  `reportSilentFallback`. `oneshot-gdpr-gate-50d-eval.ts` declares a monitor — a
  **known deviation** we do NOT follow.
- **I4** — boot-arm send wrapped so a synchronous throw cannot escape as an
  unhandledRejection; the catch is the only signal for a lost arm under I3.

## Consequences

**Easier:** new one-time secret/repo-write tasks ship as a single reviewed file +
a committed boot-arm, with no operator command and no GHA merge-before-fire dance.

**Harder:** each oneshot still touches the hand-maintained `route.ts` array
(RV6); a generalized scaffold is deliberately deferred (#3990) until oneshot
consumers reach the critical mass that earned the cron substrate.

**Boundary preserved (AP-014):** platform-loop / per-founder cohabitation is
upheld — `actor:"platform"`, `cron-platform` concurrency, operator-token-only, no
`runWithByokLease`.
