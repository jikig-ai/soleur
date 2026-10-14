---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: "#4654"
type: focused
worktree: feat-inngest-oneshot-scheduler
branch: feat-inngest-oneshot-scheduler
draft_pr: "#4655"
refs: ["#4650", "#4649", "#3948", "#3990"]
---

# Generalized Inngest-Based One-Time (`--once`) Scheduler — Brainstorm

**Date:** 2026-05-30
**Issue:** [#4654](https://github.com/jikig-ai/soleur/issues/4654)
**Worktree:** `.worktrees/feat-inngest-oneshot-scheduler`
**Branch:** `feat-inngest-oneshot-scheduler`
**Draft PR:** [#4655](https://github.com/jikig-ai/soleur/pull/4655)

## What We're Building

**Chosen scope (Approach A — Consumer + self-arming + docs):** the *minimum* that delivers value and closes the one real gap, deferring the n=1 abstraction.

1. **One hand-written pure-TS oneshot** (`oneshot-*.ts`) — the #4650 first consumer: on/after 2026-05-31 09:00 UTC, query the Sentry Crons API for three monitors (`scheduled-gh-pages-cert-state`, `scheduled-community-monitor`, `scheduled-inngest-cron-watchdog`) and auto-close #4650 if all show a fresh `ok` check-in.
2. **Self-arming in code** — commit the arming `inngest.send({ name, id: <stable>, ts: <future-epoch-ms>, data })` so the fire is enqueued **deploy-and-forget**. The stable event `id` makes redeploys idempotent (Inngest dedups on `id`). This replaces the *manual* `pnpm exec inngest send …` operator command that all three existing oneshots rely on today.
3. **One ADR + docs note** (ADR-046) capturing two durable decisions: (a) the GHA `--once` vs Inngest-oneshot decision boundary, and (b) the self-arming-in-code pattern. Plus the registered-functions-only substrate boundary.

**Explicitly NOT building now:** no scaffolding skill, no declarative registry, no arbitrary-task-spec executor, no retrofit of the existing 3 oneshots. Re-evaluate a generalization/skill when oneshot consumers reach ~5 (the threshold the recurring-cron substrate earned `_cron-shared.ts` at ~34).

## Why This Approach

- **n=1 consumer, low stakes.** #4650 self-recovers via Sentry auto-resolve + the #4649 watchdog backstop regardless; the oneshot is autonomous *bookkeeping*. Building a generic abstraction at one consumer contradicts the cron-substrate precedent (abstracted only at ~34) and **K26** (TR9 deferred the `/soleur:migrate-cron-to-inngest` skill #3990 on the same "don't productize before the corpus exists" logic).
- **But the arming gap is real and cheap to close.** Research found the initial arm is a *manual* command for every existing oneshot (e.g., gdpr spec PM.1 still unchecked) — a "merge then remember to run a command on the right date" hazard, the same class of fragility that made GHA `--once`'s merge-before-fire a problem. Committing the arm with a stable `id` removes the manual step at near-zero cost without building a handler abstraction.
- **Registered-only is security-load-bearing**, not a convenience. See Key Decisions K3.

## Key Decisions

| # | Decision | Why |
|---|----------|-----|
| K1 | **Build only the #4650 consumer oneshot + self-arming + ADR-046. No scaffolding skill / registry now.** | YAGNI at n=1; cron-substrate + K26 precedent. Re-eval at ~5 oneshot consumers. (Operator chose Approach A.) |
| K2 | **Schedule via `inngest.send({ ts: <future>, id: <stable> })`; NOT `step.sleepUntil`.** | Zero `sleepUntil` precedent in-tree; future-`ts` delivery is the proven primitive and more durable than holding a sleeping step open. |
| K3 | **Registered/code-reviewed functions ONLY. Never an arbitrary fetched-task-spec executor.** | CTO+CLO convergence: arbitrary specs on the shared-`process.env` persistent Inngest worker recreate the `followthrough-sweeper` boundary that **K21** kept off the substrate permanently (Art. 32 selective-secret TOM + Art. 25(1)). This is the operator's credential-leak vector. |
| K4 | **Coexist with GHA `soleur:schedule --once`; do not replace it.** | GHA `--once` stays correct for no-secret / no-repo-write report tasks. Inngest oneshot is the home only when fire-time secrets or App-token repo writes are needed. ADR-046 documents the boundary. |
| K5 | **Idempotency = stable event `id` (Inngest dedup) + D3 date guard (`today === expected_date`, with validated `date_override` test hook) as defense-in-depth.** | Carry-forward from the 3 existing oneshots; date guard protects against a desync/replay firing on the wrong day. |
| K6 | **Honor ADR-033: oneshots get NO Sentry cron monitor** (would false-alert on a non-recurring fn); errors via `reportSilentFallback` only. Reuse `mintInstallationToken()` (has 401 retry) + `sendInngestWithRetry`; don't hand-roll token/send paths. `actor:"platform"` (I6), concurrency `cron-platform`, `retries:1`. | ADR-033 I1–I6 + the installation-token-401 + heartbeat-Doppler learnings. |
| K7 | **Self-arm execution site is a plan-time HOW** (commit the `inngest.send`; exact trigger so it runs once-per-deploy idempotently TBD). | Stay WHAT-not-HOW; see Open Question 1. |

## Open Questions (for plan-time)

1. **Self-arm execution site.** Where does the committed arming `inngest.send({ts,id})` actually run so it fires once on deploy (idempotent via stable `id`) without a manual command and without a module-load side-effect that's unreliable in the Next.js route runtime? Candidate sites: a tiny dedicated trigger, the gdpr-style conditional re-arm shape, or an explicit registration hook. The gdpr **re-arm** is committed in code (`oneshot-gdpr-gate-50d-eval.ts:367-385`); only the **initial** arm is manual — mirror the committed shape for the initial arm.
2. **Net-new Sentry Crons *read* code + auth token.** CORRECTION to the issue premise: `cron-inngest-cron-watchdog.ts` queries the **Inngest** `/v1/functions` registry, **not** Sentry monitors — there is **no** Sentry read code to reuse. Sentry is write-only (heartbeat POST) repo-wide. Querying check-in status is net-new and needs a Sentry **auth token** env var (e.g. `SENTRY_API_TOKEN`) that the project does not define today. Plan must add it to Doppler `prd` (read-only scope to monitors) — automate via doppler CLI, do not defer as an operator step.
3. **Timing risk on the #4650 consumer.** #4650 fires ~2026-05-31 09:00 UTC (≈tomorrow) and self-recovers regardless. If this PR cannot merge+deploy before the fire window, the consumer becomes a **documented example task** (the close is done manually / by the watchdog) rather than load-bearing. Decide at plan time whether to keep #4650 as the consumer or pick a later example.
4. **Long-horizon durability bound.** Future-`ts` sends survive the #4650 cron-desync class (they enqueue a concrete event, not a re-planned cron), BUT ADR-030 documents Inngest state as local SQLite on a single non-HA host — a far-future `ts` (weeks/months) is only as durable as that store surviving host loss. Document the near-horizon-reliable / long-horizon-bounded distinction in ADR-046.
5. **Registration is hand-maintained.** `app/api/inngest/route.ts` requires a manual import + array entry per function (RV6 deliberately rejects a barrel/auto-discovery module). "Drop a file and it auto-registers" is false — the consumer touches route.ts.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

Triad spawned mandatory (`USER_BRAND_CRITICAL=true`): CPO + CLO + CTO.

### Engineering (CTO)

**Summary:** Substrate gap is minimal — 3 shipped oneshots prove the pattern; the only net-new capability the consumer needs is a Sentry Crons API *read* (does not exist today). Recommends registered-functions-only (Q3 is the brand-critical axis: arbitrary specs = K21 boundary), `ts+id` over `sleepUntil`, coexist with GHA. YAGNI: a generic abstraction is *not* warranted and would re-introduce the arbitrary-execution surface Q3 forbids. Suggested an ADR for the durable boundary decisions.

### Product (CPO)

**Summary:** Defer the generalization — one low-stakes consumer (#4650 self-recovers); the cron substrate earned abstraction only at ~34 consumers and K26 (#3990) honored the same "wait for the corpus" call. Smallest valuable surface = the single hand-written oneshot + a docs note on the GHA-vs-Inngest boundary. Keep `soleur:schedule` and don't front-run #3990. (Operator's Approach A adds self-arming on top of CPO's floor — closes the manual-arming hazard cheaply.)

### Legal (CLO)

**Summary:** A registered-function-only scheduler needs **no** Article 30 register change and **no** new sub-processor (identical to the 3 existing oneshots; inherits ADR-033 I2 operator-key-only + I6 `actor:"platform"`). An arbitrary-task-spec variant **crosses** the Art. 32 / Art. 25(1) line and is barred by K21 — do not build it. Any registered oneshot that touches dev Supabase or user data must run `/soleur:gdpr-gate` at plan time (bucket-ii); the #4650 consumer (Sentry read + GitHub issue close) does not touch user PII.

## Capability Gaps

**1. Sentry Crons API read path + auth-token env var.**
- **What is missing:** No code anywhere GETs Sentry monitor check-in status; Sentry is write-only (heartbeat POST). No Sentry auth-token env var defined.
- **Domain:** Engineering / Operations.
- **Why needed:** The #4650 consumer must read 3 monitors' check-in status before deciding to close.
- **Evidence:** repo-research grep for `sentry.io/api`, `/monitors/.../check-ins`, `SENTRY_AUTH`, `/api/0/` across `apps/web-platform/server/inngest/` returned nothing; `cron-inngest-cron-watchdog.ts:274-293` (`fetchRegistry`) reads Inngest `/v1/functions`, not Sentry. Shared `_cron-shared.ts:8-10` Sentry regexes validate the *ingest/heartbeat* DSN, not a read auth token.

## Productize Candidate

Per Phase 2.5: oneshot scheduling is recurring work, but productization is **deliberately deferred** (K1). Candidate: a `soleur:schedule-oneshot` scaffolding skill — but design it together with the deferred `/soleur:migrate-cron-to-inngest` skill (**#3990**) once oneshot consumers reach ~5, to avoid front-running the same "wait for the corpus" decision twice. No new follow-up issue needed; #3990 already tracks the adjacent productization.

## References

- ADR-033 (Inngest cron/oneshot substrate, I1–I6, prefix taxonomy): `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
- ADR-030 (Inngest durable trigger layer, single-host SQLite): `knowledge-base/engineering/architecture/decisions/ADR-030-*.md`
- TR9 Phase 2 brainstorm (K21 followthrough-sweeper boundary, K26 productization defer): `knowledge-base/project/brainstorms/2026-05-26-tr9-phase-2-migrate-all-remaining-gha-to-inngest-brainstorm.md`
- Existing oneshots: `apps/web-platform/server/inngest/functions/oneshot-{gdpr-gate-50d-eval,recheck-4217-calibration,f2-defer-gate-review}.ts`
- Sentry/registry IO template to mirror: `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts`
- GHA `--once` boundary to document: `plugins/soleur/skills/schedule/SKILL.md` (`:727` merge-before-fire, `:730` D4 cleanup cost)
- Learnings: `2026-05-04-schedule-once-template-missing-id-token.md`, `2026-05-07-claude-code-action-boundaries-and-once-schedule-bundle.md`, `2026-05-19-inngest-substrate-five-bug-cascade.md`, `bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md`, `bug-fixes/2026-05-26-inngest-github-installation-token-401-resilience-gap.md`, `bug-fixes/2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md`

## User-Brand Impact

**Threshold:** `single-user incident` (operator selected "All of them" — credential leak, silent no-op, no-direct-user-impact — at Phase 0.1).

| Vector | Worst-case | Load-bearing invariant |
|--------|-----------|------------------------|
| Credential leak / over-broad repo writes | A scheduler running an arbitrary task spec with full prd env + GitHub App installation token leaks secrets or makes unintended repo/infra writes | **K3** registered-functions-only (no arbitrary spec); K21 boundary; ADR-033 I2 operator-key-only |
| Silent no-op bookkeeping | The #4650 oneshot never fires (desync) or wrongly closes #4650 | K5 stable-`id` + D3 date guard; K6 `reportSilentFallback`; #4650 self-recovers as backstop |
| New secret surface | The new Sentry auth token over-scoped or leaked | Open Q2: read-only-to-monitors scope, Doppler `prd` only, no env passthrough |
