---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: "#4654"
draft_pr: "#4655"
brainstorm: "knowledge-base/project/brainstorms/2026-05-30-inngest-oneshot-scheduler-brainstorm.md"
status: draft
---

# Spec: Inngest One-Time (`--once`) Scheduler — First Consumer + Self-Arming Pattern

## Problem Statement

The GHA `soleur:schedule --once` mechanism cannot host one-time tasks that need fire-time
secrets or repo writes: it has no Doppler secret access at fire time, requires a
default-branch merge before the fire date, and has fragile self-neutralization. The Inngest
substrate runs in-container with the full prd env + the GitHub App installation token and
already proves the fire-once pattern via three hand-written `oneshot-*.ts` functions — but
each is **armed by a manual `inngest send` operator command**, a "merge then remember to run
a command on the right date" hazard. This feature ships the first secret+repo-write consumer
on the Inngest substrate and removes the manual-arming step, while explicitly deferring a
generalized scaffolding abstraction.

## Goals

- G1: Ship one pure-TS Inngest oneshot that, on/after 2026-05-31 09:00 UTC, reads three
  Sentry Crons monitors and auto-closes #4650 if all show a fresh `ok` check-in.
- G2: Arm the oneshot via committed-in-code `inngest.send({ ts, id })` (deploy-and-forget,
  idempotent on redeploy via stable `id`) — no manual command.
- G3: Record the durable decisions in ADR-046: GHA `--once` vs Inngest-oneshot boundary,
  self-arming-in-code pattern, and registered-functions-only substrate boundary.

## Non-Goals

- NG1: No scaffolding skill, declarative registry, or auto-discovery (re-eval at ~5 consumers; coordinate with #3990).
- NG2: No arbitrary-task-spec / fetched-spec executor — barred by K21 (Art. 32 / Art. 25(1)); registered functions only.
- NG3: No retrofit of the three existing oneshots onto a new abstraction.
- NG4: No replacement of `soleur:schedule --once` (GHA) — coexist.
- NG5: No `step.sleepUntil` (no in-tree precedent; less durable than future-`ts` delivery).

## Functional Requirements

- FR1: A pure-TS oneshot function (Octokit + `fetch`), registered on a `oneshot/*.fire`
  event, that queries the Sentry Crons API for `scheduled-gh-pages-cert-state`,
  `scheduled-community-monitor`, `scheduled-inngest-cron-watchdog`.
- FR2: If all three monitors show a fresh `ok` check-in, close #4650 with an explanatory
  comment; otherwise post status / no-op and `reportSilentFallback` on read errors.
- FR3: Committed self-arming `inngest.send({ name, id: <stable>, ts: <2026-05-31T09:00Z epoch ms>, data: { expected_date, actor:"platform", ... } })` that fires once and dedups across redeploys.
- FR4: D3 date guard (`today === expected_date`, `date_override` test hook validated `^\d{4}-\d{2}-\d{2}$`).
- FR5: Manual import + array entry in `app/api/inngest/route.ts` (RV6 — no barrel).
- FR6: ADR-046 documenting the three durable decisions (boundary, self-arming, registered-only).

## Technical Requirements

- TR1: Net-new Sentry Crons **read** path + a Sentry auth-token env var (e.g. `SENTRY_API_TOKEN`),
  added to Doppler `prd` read-only-to-monitors scope via doppler CLI (do NOT defer as an operator step).
  Mirror the IO shape of `cron-inngest-cron-watchdog.ts:274-293` (bearer fetch + `AbortSignal.timeout`).
- TR2: Honor ADR-033 I1–I6; oneshots get **no** Sentry cron monitor (errors via `reportSilentFallback` only).
  Concurrency `cron-platform`, `retries:1`, `actor:"platform"` (I6).
- TR3: Reuse `mintInstallationToken()` (has 401 retry) and `sendInngestWithRetry`; no hand-rolled token/send paths.
- TR4: `## Observability` block required at plan/deepen time (liveness_signal, error_reporting via
  `reportSilentFallback`, failure_modes, no-SSH `/v1/functions` discoverability test) — `hr-observability-as-plan-quality-gate`.
- TR5: GitHub App auth (installation token), not PAT (`hr-github-app-auth-not-pat`).

## Open Questions (carry from brainstorm)

1. Self-arm execution site (committed send that runs once-per-deploy idempotently, not a flaky module-load side-effect).
2. `SENTRY_API_TOKEN` scope/provisioning (read-only to monitors, Doppler `prd`).
3. Timing: #4650 fires ~2026-05-31 and self-recovers — if PR can't merge in time, keep #4650 as a documented example or pick a later consumer.
4. Long-horizon durability bound (single-host SQLite, ADR-030) — document near-reliable / far-bounded.

## Acceptance Criteria

- The oneshot is registered, self-arms on deploy without a manual command, and (if merged before
  the window) closes #4650 on all-`ok`; ADR-046 merged; no manual operator step in the PR/ship message.
