---
title: "chore(inngest): upgrade to inngest@4 and delete the stream-detach wrapper"
type: refactor
date: 2026-10-28
slug: chore-inngest-v4-upgrade-stream-detach
branch: feat-one-shot-8628-inngest-4-upgrade
issue: 8628
closes: 8628
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(inngest): upgrade to inngest@4 and delete the stream-detach wrapper

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-28 (deepen-plan, inline single-agent pass — this subagent
harness offers no Task/agent spawn, so the fan-out phases 2/3/4/5 ran as direct
repo greps, npm tarball inspection, and upstream-doc review in this session; the
coverage disclosure is honest rather than claimed independent review).
**Gates verified:** 4.6 User-Brand (single-user incident, sign-off flagged) ·
4.7 Observability (5-field block, `jq` allowlisted probe, literal `^4`
expected_output) · 4.8 PAT (clean) · 4.9 UI (no UI surface) · 4.10 Encryption
(skipped — no new store/connection) · 4.11 Guard Contract (deliverable has no
guard) · 4.12 Scope Check (1 unfenced section, all rows mapped/justified) ·
4.13 Task Design (no new autonomous surface) · 4.55 Downtime & Cutover (no
downtime-inducing operation — deploy path unchanged, ADR-078 drain intact).
**New considerations discovered during deepening:**
- v4 turns **checkpointing on by default** — a transport-shape change inside the
  very mechanism ADR-243 was written to bound; promoted to risk R1 + spike row
  S9 rather than left as an implicit behavior change. **Ruled by CTO agent,
  2026-10-28:** this PR ships `checkpointing: false` on the client — self-hosted
  support on pinned v1.45.1 is upstream-docs-only (unverified), and the unit
  harness models one-new-step-per-request, so default-on would ship an execution
  model no suite asserts. S9 runs as a measurement row; flip-on is a one-flag
  follow-up once the measurements exist.
- `onRunError.isFinalAttempt` is a native v4 signal that can retire run-log's
  manual `attempt >= maxAttempts - 1` approximation (kept as an option, not a
  mandate).
- Phase 4.5 (network-outage checklist) fired on the `timeout` keyword — the
  match is the Cloudflare origin-timeout discussion, not a connectivity
  diagnosis; no L3 firewall/DNS hypothesis is in scope and no SSH/service-layer
  fix is proposed. Recorded for the aggregator (telemetry emitted); checklist
  deep-dive not applicable.

## Overview

PR #8611 turned on `serve({ streaming: "force" })` for `/api/inngest` (ADR-243) and
worked around a heartbeat-timer leak in `inngest` 3.54.2's `helpers/stream.js`
`createStream`: a dropped step stream left the 3 s heartbeat interval running and
every tick threw `Invalid state: Controller is already closed` — an
`uncaughtException` that `server/crash-handlers.ts` exits the process on. The
workaround is `apps/web-platform/server/inngest/stream-detach.ts` (re-streams the
SDK body and drains it to the end on consumer cancel so the SDK controller never
sees a cancel), pinned by a content-hash of `stream.js` in
`test/server/inngest/stream-detach.test.ts`, with `inngest` held at exactly
`3.54.2` in `apps/web-platform/package.json`.

`inngest@4` fixes `createStream` upstream — verified against the published
`inngest@4.26.1` tarball: `cancel()` handler that clears the interval, a `closed`
flag gating `enqueue`, and a try/catch that demotes a late heartbeat write to a
`logger.debug`. This plan upgrades `apps/web-platform` to `inngest@^4` across all
71 function modules and the three client middlewares, re-runs the #8611 streaming
spike matrix (S1–S8) against the pinned self-hosted server (v1.45.1), deletes the
wrapper module / test / route-wrap, and restores the `^` semver range.

Operator-directed residuals ride along: (a) the
`scripts/followthroughs/inngest-verify-clean-10390.sh` RETIREMENT deletion — its
AC7 soak passed 2026-10-27 and the directive was retired from epic #10390 — and
(b) the four deferred P3 review items on `_cron-community-publication.ts`'s
fd-pinned write path from merged PR #11334 (squash `76ff5830ac56`).

## Problem Statement / Motivation

Three pressures make this the right time:

1. **The pin is a wedge.** `inngest: 3.54.2` is the last 3.x release and is pinned
   exactly, so every dependabot-style bump is held; v4-only SDK features and fixes
   are unreachable.
2. **The wrapper is debt with a blast radius.** `stream-detach.ts` exists only
   because of the 3.54.2 `createStream` defect. Under the fixed upstream the whole
   module, its content-hash pin, and the route POST wrapper are dead code — and the
   longer they live the more likely a future edit treats them as load-bearing
   architecture rather than a version workaround.
3. **Owed residuals.** The epic's own log says the verify-clean probe's deletion
   is "still owed" and the fd-pinning P3 items were deferred to "the next inngest
   PR" — this is that PR.

## Proposed Solution

Single PR, five workstreams in order:

1. **Dependency + mechanical API migration.** `inngest` → `^4.x` (latest stable,
   4.26.1 at plan time); `createFunction` trigger arg folded into the options
   object (`{ event }`/`{ cron }` → `triggers:`) across all call sites; `serve()`
   options moved per the v4 guide (`serveHost` → `serveOrigin`,
   `signingKey`/`baseUrl` to the client constructor, `streaming: "force"` →
   `streaming: true`).
2. **Middleware rewrite.** Port the three `InngestMiddleware` instances to v4
   `Middleware.BaseMiddleware` classes (registered as classes, fresh instance per
   request) with a documented hook mapping that preserves every behavior the
   suites pin.
3. **Delete the workaround.** Remove `stream-detach.ts`, its test, the POST
   wrapper in `route.ts`; update `signature-verify.test.ts` (drop the wrapper
   mock/wiring pin, keep the 401-in-201-envelope assertions and the
   only-serve-mount census).
4. **Evidence.** Re-run the S1–S8 spike matrix plus new checkpointing rows against
   `inngest start` v1.45.1 behind a real Cloudflare proxy, with the production
   crash handlers installed — the S7 cut-without-wrapper row is the kill-proof for
   the deletion.
5. **Residuals.** Followthrough-probe retirement census and the four fd-pinning
   P3 items.

## Technical Approach

### Migration surface (verified, v4.26.1 tarball + migration guide)

| v3 (current) | v4 | Sites |
|---|---|---|
| `createFunction(opts, trigger, handler)` | `createFunction({...opts, triggers: {...}}, handler)` | 71 function files + test helpers (`inngest.createFunction` ×151 grep hits) |
| `new InngestMiddleware({init(){onFunctionRun…}})` instances | `class X extends Middleware.BaseMiddleware`, registered as classes | 3 middleware files + `client.ts` array |
| `transformInput` | `transformFunctionInput(arg)` → returns possibly-patched `{ctx, fn, steps}` | sentry-correlation, run-log, bound-logger |
| `transformOutput({result, step})` | split into `onStepComplete`/`onStepError` (per-step, carries `isFinalAttempt`) and `onRunComplete({output})`/`onRunError({error, isFinalAttempt})` (function-final) | run-log, sentry-correlation |
| `beforeMemoization`/`afterMemoization`/`beforeExecution`/`afterExecution` | `onMemoizationEnd` + `wrapStep`/`wrapStepHandler`/`onStepStart` (observability breadcrumbs only — loss is tolerable by design, pick nearest hook) | sentry-correlation breadcrumbs |
| `serve({ serveHost, signingKey, streaming: "force" })` | `serve({ serveOrigin, servePath, streaming: true })`; `signingKey`/`baseUrl`/`fetch` move to the `Inngest` client | `route.ts`, `client.ts` |
| `streaming: "force" \| "allow"` | `streaming: true \| false` (allow/force deprecated) | `route.ts` |
| `ctx.logger` receiver-loss via `ProxyLogger.enabled` | `ProxyLogger` still exported, same `enabled` gate — bound-logger stays necessary | bound-logger, its test |
| — | **checkpointing enabled by default upstream — this PR ships `checkpointing: false`** (CTO ruling 2026-10-28, see risk R1) | `client.ts` |
| `INNGEST_SERVE_HOST` | `INNGEST_SERVE_ORIGIN` (`_HOST` still read, deprecation warning) | repo uses neither env — hardcoded `SERVE_HOST` const stays, key renamed |
| mode inferred (dev default) | **cloud default** — `isDev`/`INNGEST_DEV=1` explicit for dev; prod requires signing key | `client.ts` already enforces both keys + refuses `INNGEST_DEV=1` in prod — aligned, but error ordering/messages may shift in tests |

Verified exports still present in 4.26.1: `NonRetriableError`, `StepError`,
`serializeError`, `ProxyLogger`, `RetryAfterError`, `InngestCommHandler`,
`eventType`, `staticSchema`, `Middleware`, `inngest/next` `serve` → `{GET, POST,
PUT}`, `ctx.{event,events,runId,attempt,maxAttempts,logger,step,group,sessions}`.

Not used by this repo (no migration needed): `EventSchemas`/`schemas:`,
`step.invoke`, `step.waitForEvent`, `event.user`, `inngest/connect` serve path,
`INNGEST_SERVE_*` env vars.

### Implementation Phases

#### Phase 0 — Pin the floor: package.json + lockfile

- `apps/web-platform/package.json`: `"inngest": "3.54.2"` → `"inngest": "^4.26.1"`
  (or the latest 4.x stable at work time — `npm view inngest version`).
- Regenerate `apps/web-platform/package-lock.json` only:
  `cd apps/web-platform && npx --yes npm@11 install --package-lock-only`
  (lockfile-sync gate pins npm@11). **No `bun.lock` exists anywhere in this repo —
  `scripts/lint-dual-lockfile.sh` (ADR-191) asserts that as an existence property;
  do not run `bun install`.** The working note's "regenerate bun.lock" is stale.
- TypeScript floor: v4 requires TS ≥5.8 / Node ≥20 — repo locks TS 5.9.3 and
  declares `>=20.16.0 || >=22.3.0`; already satisfied, no change.

#### Phase 1 — Mechanical API migration

- `createFunction` codemod across `server/inngest/functions/*.ts` (71 files) and
  any test-harness `createFunction` call sites: fold the second argument into
  `triggers:` in the options object (`{ event: "x" }` → `triggers: { event: "x" }`,
  `{ cron: "0 …" }` → `triggers: { cron: "0 …" }`). Per constitution, batch-edit
  scripts must assert the needle matched and verify the post-state; the tsc gate
  is the real check.
- `route.ts`: `serveHost` → `serveOrigin`; `streaming: "force"` → `streaming: true`;
  drop `signingKey` from `serve()` → `client.ts` `new Inngest({ …, signingKey })`.
  Keep `servePath: "/api/inngest"`. Preserve every load-bearing comment block
  (#5159 serve-URL pin rationale, ADR-243 streaming rationale — edited, not deleted,
  to describe the v4 shape).
- `client.ts`: `middleware: [SentryCorrelationMiddleware, RunLogMiddleware,
  BoundLoggerMiddleware]` (classes, not instances) + `signingKey` moved here.
  `baseUrl` already client-side. Checkpointing flag decided by Phase 4 spike
  (default: absent = on).
- **Function `id:` values must not change** — renaming an id orphans in-flight
  runs and breaks cron planning. Add nothing, rename nothing.

#### Phase 2 — Middleware rewrite

Port all three to `Middleware.BaseMiddleware` subclasses. Fresh instance per
request — module-scope dedupes (bound-logger's `failOpenReported`, the WeakMap
bound-cache) stay module-scope; per-request captures (run-log's
`attempt`/`maxAttempts`/`startedAtMs`) become instance fields.

- `sentry-correlation.ts`: scope-tagging + run-start breadcrumb →
  `transformFunctionInput` (receives full ctx incl. `event`, `runId`); per-step
  breadcrumbs → `onStepComplete`/`onStepError`; memoization breadcrumbs →
  `onMemoizationEnd` (or drop with a named note — breadcrumbs are loss-tolerable);
  final-result `captureException` → `onRunError({error, isFinalAttempt})` (gated
  on `isFinalAttempt` — v4 hands the flag the v3 code approximated with
  `attempt >= maxAttempts - 1`); final-ok breadcrumb → `onRunComplete`.
- `run-log.ts`: `transformFunctionInput` for `startedAtMs` capture (v4 still
  exposes `attempt`/`maxAttempts` on ctx, but `onRunError.isFinalAttempt` is the
  native signal — prefer it and delete the manual gate if the two agree; the
  #5674 thrown-vs-returned-`ok:false` contract is preserved: thrown+non-final
  → suppress, returned-`ok:false` at any attempt → write, thrown+final → write);
  terminal-row write + `finishRoutineRunProgress` ordering unchanged —
  `onRunComplete` (output `{ok:false}` row) and `onRunError` (final thrown row).
  Fail-soft Sentry mirror unchanged.
- `bound-logger.ts`: `transformFunctionInput` returning
  `{ ...arg, ctx: { ...arg.ctx, logger } }` (the dependencyInjection pattern —
  verified in the 4.26.1 source). Proxy-invariant comment block and WeakMap
  two-level cache verbatim; fail-open + `warnSilentFallback` report verbatim.
- Ports of their test suites to the class shape (construct + invoke the hook
  directly — same style as the existing suites drive the v3 hooks).

#### Phase 3 — Delete the workaround

- Delete `server/inngest/stream-detach.ts`, `test/server/inngest/stream-detach.test.ts`.
- `route.ts`: drop the import + `streamRequestInfo`; `export const POST = handlers.POST`.
- `test/server/inngest/signature-verify.test.ts`: drop the `stream-detach` mock +
  the wrapper-wiring test; keep the 401-in-streamed-envelope assertions (the
  `streaming: true` transport still returns 201 + envelope); keep the
  only-serve-mount census test with an updated comment (a second mount is a
  duplicate-registration surface, not a wrapper bypass).
- Sweep `git grep -n "stream-detach\|detachFromConsumerCancel\|streamRequestInfo"`
  → zero outside `knowledge-base/` history.

#### Phase 4 — Evidence: spike re-run

Mirror `specs/archive/20260923-200917-feat-anthropic-spend-reduction/streaming-spike.md`
Setup verbatim, changing only the SDK: `inngest start` **v1.45.1** (the pinned
production binary — `apps/web-platform/infra/inngest.tf:33`), the app built from
this branch's `next build`, a Cloudflare quick tunnel, throwaway
`signkey-test-*`/`evtkey-test-*` keys, `env -i` + `INNGEST_DEV=0`, and the
production `installCrashHandlers()` installed for the S7 rows. Rows:

- S1–S6, S8 — identical shapes to the 2026-09-23 matrix; same pass conditions.
- S7 — the deletion's kill-proof: cut the stream mid-step with **no wrapper**;
  expected: app stays up (upstream `cancel()` clears the heartbeat), one
  server-side `error parsing SDK response stream`, retry joins or re-runs per
  `retries`. A `Controller is already closed` / `Invalid state` uncaughtException
  = v4 does not fix the defect → STOP, restore the wrapper, re-scope.
- S9 (new) — checkpointing matrix, **measurement-only** (the flag decision is
  already ruled: the PR ships `checkpointing: false`): S2 shape run once with
  client-default checkpointing (expected to fail or degrade on the pinned
  self-hosted server — record what breaks) and once with `checkpointing: false`
  (the shipped configuration — must pass); record inter-step latency, whether
  the streamed response still heartbeats through a >100 s step, and any
  server-side checkpoint errors. These measurements are the evidence a future
  one-flag flip-on decision needs — they do NOT change this PR's flag.
- Unsigned-POST row — 201 HTTP + 401 in envelope; `x-inngest-sdk` headers.
- Registration row — `PUT` sync → `modified:true`, crons planned (`inngest_crons`
  non-empty on the dev-server dashboard API if reachable) — the #5159 invariant
  under `serveOrigin`.

Artifact: `knowledge-base/project/specs/feat-one-shot-8628-inngest-4-upgrade/streaming-spike-v4.md`
— same table format as the 2026-09-23 record, plus a versions line and the
S9 checkpointing measurements (both arms recorded; shipped flag is
`checkpointing: false` per the CTO ruling).

#### Phase 5 — Residuals

**(a) `inngest-verify-clean-10390` retirement census** (per learning
`2026-09-24-followthrough-retirement-headers-underenumerate-touch-points.md` —
the census is the load-bearing step; current `git grep inngest-verify-clean-10390`
live-code footprint, each needs a disposition):

| Touch point | Disposition |
|---|---|
| `scripts/followthroughs/inngest-verify-clean-10390.sh` | delete |
| `scripts/followthroughs/inngest-verify-clean-10390.test.sh` | delete |
| `scripts/test-all.sh:5989` `run_suite` registration | delete line |
| `scripts/suite-durations.tsv:388` row | delete row |
| `scripts/suite-shard-legs.tsv:391` row | delete row |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt:453` row | delete row (regen baseline if the fixture regenerates) |
| `knowledge-base/` post-mortem + learnings + archived plans/specs | keep — point-in-time records |
| Epic #10390 directive/label | already retired 2026-10-27 by operator — verify no `soleur:followthrough` comment remains (verified at plan time: none, label absent) |

**(b) `_cron-community-publication.ts` fd-pinning P3 items** (PR #11334 residuals):

1. *procfs-less-Linux probe path*: `containedHasProcFd` assumes procfs on Linux;
   document/verify the fail-closed-loud behavior (every pinned open ENOENTs) with
   a deliberate probe — a unit test driving the procfs-absent shape through the
   same seam as (2), or a startup assertion. Decide per the seam design.
2. *non-Linux fallback test coverage*: `containedHasProcFd` is a module-level
   const with no stub seam — add a deliberate seam consistent with this file's
   `@internal test seam` precedent (the `beforeOpen` optional param /
   exported-for-test pattern), then cover the `join(current, segment)` fallback
   arm in `cron-community-publication.test.ts`.
3. *`fh.close()` lone-writeback masking* (`writeDigestFileContained`): the
   `finally { fh.close().catch(() => {}) }` masks a close error even when
   `writeFile` succeeded — a lone writeback failure becomes silent. Fix: only
   mask when a write error is already in flight (track-and-rethrow pattern);
   a successful-write + failed-close path must surface the close error.
4. *error-prefix family naming*: all errors share `writeDigestFileContained:` even
   when thrown from `openContainedDir`/`createContainedFile`. Decide one family:
   keep the single grep-able prefix with a per-operation detail token (preferred —
   consumers grep one string), or per-helper prefixes; encode the decision in the
   error messages + tests.

#### Phase 6 — ADR + sweep

- Amend `ADR-243` in place: §1 records the v4 upstream fix and the wrapper's
  deletion (the ADR already defers this to #8628); the Alternatives "Upgrade to
  `inngest@4` now" row is marked executed; the Observability table drops
  `inngest-stream-consumer-cancel` / `inngest-stream-drain-error` with a note that
  drop coverage moved to the server-side `inngest_step_524` needle; a
  checkpointing line records the `checkpointing: false` ruling and the S9
  measurements.
- Sweep: `git grep -n "stream-detach\|inngest-stream-\|serveHost" -- apps/ scripts/`
  → only intended hits; `git grep -n "3.54.2"` → only KB/history.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Stay on 3.54.2 + keep the wrapper | The pin blocks every v4 fix/feature forever and keeps a re-streaming workaround the upstream already made dead code. |
| Pin `4.21.x` exactly (version the issue names) | Issue says "inngest@4"; `4.21.0` contains the fix but later 4.x carries more fixes — `^4` restore is the ask, so track latest stable and pin the lockfile. |
| ~~`checkpointing: false` unconditionally~~ **EXECUTED — this is the CTO ruling** | The stricter option won: self-hosted support on pinned v1.45.1 is upstream-docs-only (unverified) and the unit harness models one-new-step-per-request, so default-on would ship an execution model no suite asserts. S9 still runs to measure both arms; flip-on is a future one-flag decision. |
| Split the codemod from the deletion | Both halves are gated on the same dependency; a partial v4 tree (old signature + new SDK) doesn't compile — one PR or no PR. |
| Keep a thin `inngest-stream-*` telemetry shim in v4 | The wrapper's drop attribution (fnId/stepId) is gone either way; the server-side `inngest_step_524` needle already detects drops — a shim buys attribution the open `retries` decision (#8613) can revisit if needed. Accepted coverage shift; recorded in ADR-243's observability table. |
| Wrapper kept "just in case" under v4 | Dead machinery whose precondition (leaky `createStream`) is gone; the S7 control row proves the case against it. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder-facing BYOK leader
  loop (`agent-on-spawn-requested`) — same `/api/inngest` serve handler — fails to
  start or double-bills the founder's own API key (ADR-243 held the transport
  change to this threshold for exactly this reason); or every scheduled cron
  silently stops firing if registration/`serveOrigin` regresses (#5159's failure
  shape: register HTTP 200, `inngest_crons:{}`).
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  signature-verification regression in the v4 handler → forged event dispatch to
  any of the 73 registered functions (ADR-030 invariant I4); a `INNGEST_DEV`
  misconfiguration is still refused by the client guard.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the serve handler is shared with the
  founder's paid BYOK loop — a transport/middleware regression can bill the
  founder's key twice or stall the loop; not `aggregate pattern` because the
  blast radius is one founder account, not a cohort.

`requires_cpo_signoff: true` is set; CPO sign-off is required before `soleur:work`
begins (pipeline note: recorded here for the downstream gates —
`soleur:engineering:review:user-impact-reviewer` runs at review time).

*Scope-out:* N/A — threshold is `single-user incident`, not `none`.

## Observability

```yaml
liveness_signal:
  what: "Post-deploy verify_inngest_health: inngest_register_http=2xx AND inngest_crons non-empty (cron planning actually re-armed); steady-state SOLEUR_INNGEST_SERVER_PROBE Better Stack rows + inngest-heartbeat.service"
  cadence: "every deploy (verify step); heartbeat unit per its timer; SOLEUR_INNGEST_SERVER_PROBE per scheduled-inngest-health.yml"
  alert_target: "deploy gate (verify_inngest_health blocks); Better Stack inngest alerts"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (verify_inngest_health); .github/workflows/scheduled-inngest-health.yml; apps/web-platform/infra/betterstack-logs-alerts.tf"

error_reporting:
  destination: "Sentry web-platform (SENTRY_DSN) — sentry-correlation middleware tags inngest.fn_id / inngest.run_id / inngest.event_name; routine_runs terminal rows via run-log middleware"
  fail_loud: "routine_runs failed rows + Sentry issues tagged inngest.fn_id; Sentry cron monitors per infra/sentry/cron-monitors.tf; deploy-time verify_inngest_health failure"

failure_modes:
  - mode: "v4 registration regression: PUT sync 200 but inngest_crons empty (the #5159 shape)"
    detection: "verify_inngest_health post-deploy diagnostic (inngest_register_http + inngest_crons dump)"
    alert_route: "deploy failure → operator"
  - mode: "checkpointing incompatibility if a future flip-on is attempted (this PR ships `checkpointing: false`)"
    detection: "S9 measurement row before merge; post-flip-on: step errors in Sentry + routine_runs failed rows"
    alert_route: "Sentry issue + cron monitor red"
  - mode: "stream drop post-upgrade (no wrapper)"
    detection: "inngest-server 'error parsing SDK response stream' / 'reset the connection' → inngest_step_524 Better Stack alert (server-side needle; the app-side inngest-stream-* ops are retired)"
    alert_route: "Better Stack alert → operator"
  - mode: "middleware port regression (run-log double-rows or dropped terminal rows)"
    detection: "routine_runs freshness/duplication checks (cron-inngest-cron-watchdog family) + unit suite on final-attempt semantics"
    alert_route: "Sentry + routine_runs query"

logs:
  where: "journald on web host → Vector → Better Stack (SOLEUR_* rows); inngest-server journald on soleur-inngest"
  retention: "Better Stack plan retention"

discoverability_test:
  command: "jq -r '.dependencies.inngest' apps/web-platform/package.json"
  expected_output: "^4"
```

### Affected-surface note (Phase 2.9.2)

The cron-worker surface is touched (every function runs on the new SDK). The
failure_modes above carry in-surface detection for each competing hypothesis —
registration vs checkpointing vs stream-transport vs middleware — each detected by
a signal emitted from inside the surface (routine_runs rows, Sentry-tagged
function errors), not only host-side probes.

## Encryption Posture

Skipped — no new persistent store and no new cross-component connection; the diff
is a dependency bump + deletion on an existing surface (`inngest` SDK inside the
web container; the soleur-inngest server connection is unchanged).

## Task Design

Skipped — no NEW autonomous-task surface is created (functions are modified in
place; none added, no new workflows/crons/checks).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a
dependency upgrade + workaround deletion inside `apps/web-platform/server` +
CI-manifest cleanup). Mechanical UI-surface scan of Files to Edit/Create: no
match (`app/api/**/route.ts` is a backend surface per the shared term list's
exclusions).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (98 issues) against every
planned path:

- **#8593** (`server/inngest/functions/*.ts` in `EXEC_SURFACE_GLOBS` gap for the
  gh-enumeration gate): **Acknowledge** — different concern (gate-window widening
  vs this SDK migration); the codemod touches those files for `createFunction`
  only and does not interact with the gate. Remains open for its own cycle.
- **#10112** (finish #9786 residuals — inngest Bucket-2 hold): **Acknowledge** —
  it is an Operator Hold (host-replace gated), not work this PR can absorb.
- All other hits were non-path-specific prose mentions (#10243, #8595, #8920,
  #8487, #7098) — no file-level overlap.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Upgrade `apps/web-platform` to `inngest@4` (major: ~70 functions, the sentry-correlation / bound-logger / run-log middlewares, `serve()` options)." | Phases 0–3 + Files-to-Edit (package.json, client.ts, middleware×3, route.ts, functions×71) | mapped |
| 2 | "Re-run the #8611 streaming spike rows (S1–S8) against the pinned self-hosted server version." | Phase 4 + `streaming-spike-v4.md` artifact | mapped |
| 3 | "Delete `server/inngest/stream-detach.ts`, its test and the route wrapper; restore the `^` range." | Phases 0 (^ restore) + 3 | mapped |
| 4 | "Delete scripts/followthroughs/inngest-verify-clean-10390.sh — its RETIREMENT step is owed… Remove the script and any registry/manifest references to it." [brief] | Phase 5a census table | mapped |
| 5 | "Deferred P3 review items … in apps/web-platform/server/inngest/functions/_cron-community-publication.ts and its test: (a) procfs-less-Linux probe path…, (b) non-Linux fallback test coverage…, (c) fh.close() lone-writeback masking, (d) error-prefix family naming." [brief] | Phase 5b items 1–4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 package.json + lockfile | "upgrade apps/web-platform to inngest@4" / "restore the `^` semver range" | asked |
| Phase 1 createFunction/serve codemod | "the sentry-correlation / bound-logger / run-log middlewares, serve() options" | asked |
| Phase 2 middleware rewrite | same quote | asked |
| Phase 3 stream-detach deletion | "delete server/inngest/stream-detach.ts + its test + the route wrapper" | asked |
| Phase 4 S1–S8 spike | "re-run the streaming spike rows S1-S8 … against the pinned self-hosted server" | asked |
| Phase 4 S9 checkpointing row | — | inferred — justification: v4 turns checkpointing ON by default; it rewrites the step-execution transport the spike exists to verify, so the spike measures both arms (flag decision already ruled: ship `checkpointing: false`) |
| Phase 5a retirement census | "Remove the script and any registry/manifest references to it." | asked |
| Phase 5b P3 items | "Deferred P3 review items … (a)–(d)" | asked |
| Phase 6 ADR-243 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the plan reverses a mechanism ADR-243 recorded as its Decision, so the record must move with the code |
| `signature-verify*.test.ts` edits | — | inferred — justification: they mock/assert the deleted module and the `serveHost` option; they cannot survive the deletion unedited |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `scripts/` (+1 shared file under `plugins/soleur/test/`)
- Planned files: ~85 (71 function codemods + ~14 targeted) | Estimated changed lines: ~700 (most files are one-line `triggers:` moves; middleware/route rewrites carry the mass)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split-risk noted but **single PR** — the 25-file threshold is crossed only by a mechanical one-line-per-file codemod that cannot land partially (a half-migrated tree does not compile); splitting would serialize a forced-atomic change. The code-review separation falls out naturally: codemod noise vs hand-edited middleware/route/residual files.

## Acceptance Criteria

- [ ] **AC1.** `apps/web-platform/package.json` carries `"inngest": "^4` (latest stable at work time); `apps/web-platform/package-lock.json` regenerated via `npx --yes npm@11 install --package-lock-only`; `scripts/lint-dual-lockfile.sh` green; `git ls-files` shows no `bun.lock`/`bun.lockb`.
- [ ] **AC2.** `git grep -n "stream-detach\|detachFromConsumerCancel\|streamRequestInfo" -- apps/ scripts/ plugins/` returns zero hits.
- [ ] **AC3.** Every `createFunction` call site uses the v4 `triggers:`-in-options form and no function `id:` string changed (`git diff` shows only the argument move, verified by `git diff -U0 | grep '^-.*id:'` empty on option lines — id values preserved).
- [ ] **AC4.** `route.ts` uses `serveOrigin`/`servePath`/`streaming: true`; `signingKey` lives on the `Inngest` client; `serve({` remains the ONLY inngest serve mount (existing census test passes, updated comment).
- [ ] **AC5.** All three middlewares are `Middleware.BaseMiddleware` subclasses registered as classes in `client.ts`; their suites pass with the same behavioral contract (run-log: thrown-non-final suppressed, returned-`ok:false` written immediately, thrown-final written; bound-logger: detached-method binding, frozen-prop pass-through, fail-open report once-per-process; sentry-correlation: scope tags + final-error capture).
- [ ] **AC6.** `tsc --noEmit`, `eslint`, and `scripts/test-all.sh --affected` green (do not commit while a `--affected` run is in flight in this worktree).
- [ ] **AC7.** `streaming-spike-v4.md` exists under `knowledge-base/project/specs/feat-one-shot-8628-inngest-4-upgrade/` with all S1–S8 rows run against `inngest start` v1.45.1, the S7 no-wrapper cut showing **no** `Invalid state: Controller is already closed` uncaughtException, and the S9 checkpointing measurements recorded for both arms (shipped flag is `checkpointing: false` per the CTO ruling).
- [ ] **AC8.** `git grep -n "inngest-verify-clean-10390" -- scripts/ .github/ plugins/ apps/ infra/` returns zero; `scripts/test-all.sh` no longer registers the suite.
- [ ] **AC9.** The four `_cron-community-publication.ts` P3 items are implemented: a designed seam covers the non-Linux fallback in tests; the procfs-absent path is probed and its fail-loud behavior asserted; a lone `fh.close()` writeback error is no longer masked; the error-prefix decision is encoded and pinned by tests.
- [ ] **AC10.** `signature-verify.test.ts` + `signature-verify-dev-mode.test.ts` pass and still assert the 401-in-201-envelope contract; the wrapper-wiring test is gone with the wrapper.
- [ ] **AC11.** ADR-243 amended in place (§1 v4 upstream fix + wrapper deletion + retired ops + the `checkpointing: false` ruling and S9 measurements); `git grep -n "inngest-stream-consumer-cancel\|inngest-stream-drain-error" -- apps/ knowledge-base/engineering/architecture/` returns zero outside historical learnings.
- [ ] **AC12.** `INNGEST_DEV=1`-in-production refusal and the missing-key startup throws still fire (client-startup.test.ts green, updated only for v4 error text if the SDK's own message pre-empts ours).
- [ ] **AC13.** PR body carries `Closes #8628` and names the two attached residuals (followthrough retirement, P3 fd-pinning items) so the epic's "still owed" line resolves.

## Test Scenarios

- Given `inngest@^4` installed, when `tsc --noEmit` runs, then zero errors across all 71 function modules, 3 middlewares, route.ts, and the inngest test tree. *(unit)*
- Given a POST without/with a malformed signature, when `POST` is invoked under `INNGEST_DEV=0`, then HTTP 201 + streamed envelope `status: 401` and no function dispatches. *(unit — existing suite, updated)*
- Given run-log middleware's `onRunError` firing with `isFinalAttempt: false`, when the hook completes, then no `write_routine_run` RPC call was made; with `isFinalAttempt: true`, exactly one `failed` row; given `onRunComplete` with `output.ok === false`, one `failed` row at once. *(unit)*
- Given bound-logger's `transformFunctionInput`, when `ctx.logger` is detached (`const f = l.info; f(...)`), then no receiver-loss TypeError and calls reach the underlying logger; given a frozen-property logger, the descriptor invariant returns the unbound value without throwing; given `ctx.logger` absent, the once-per-process `warnSilentFallback` fires and `undefined` propagates unmodified. *(unit)*
- Given `_cron-community-publication`'s contained write, when the seam forces the non-Linux arm, then `openContainedDir`/`createContainedFile` resolve via joined paths and refuse symlinks/non-dirs identically; when procfs is simulated-absent on Linux, the failure is loud (ENOENT-class), never a silent unpinned write; when `writeFile` succeeds and `close()` throws, the close error surfaces; when `writeFile` throws and `close()` also throws, the write error wins. *(unit)*
- Given the spike environment (v1.45.1 server, quick tunnel, crash handlers), when a signed 3-min step's stream is cut at ~30 s with no wrapper, then the app process stays up, `stream.js`'s `cancel()` runs, and the server logs the stream-parse error — no `Controller is already closed` throw. *(e2e — `pyramid-justified`: the property lives at the SDK↔server↔proxy transport boundary; no in-repo test can synthesize the real createStream + heartbeat + proxy cut)*
- Given `inngest verify` retired, when `git grep inngest-verify-clean-10390 -- scripts/ .github/ plugins/ apps/ infra/` runs, then zero hits and `test-all.sh --affected` passes with the suite row gone. *(integration)*
- **API verify (spike):** `PUT https://<tunnel>/api/inngest` returns `modified:true` and the dev-server run list shows crons planned. *(integration, manual-class step inside the spike)*

## Success Metrics

- `inngest` on `^4` with the wrapper deleted and the S7 cut surviving without it.
- All 73 registered function entries unchanged in id (zero `inngest_crons` churn
  on next deploy).
- The two owed residuals closed inside this PR (epic line + P3 deferrals resolved).

## Dependencies & Risks

- **R1 (mitigated by ruling): v4 checkpointing default-on upstream.** It executes
  steps eagerly inside a request and checkpoints via API — a different transport
  shape than the one ADR-243's streaming decision was measured against.
  **Mitigation (CTO ruling 2026-10-28):** the PR ships `checkpointing: false` —
  self-hosted support on pinned v1.45.1 is unverified and the unit harness
  models one-new-step-per-request. S9 measures both arms so a future one-flag
  flip-on decision has evidence; residual risk is deferred to that decision.
- **R2: middleware behavioral drift.** The v3 hook semantics (InitialRunInfo vs
  BaseContext traps, transformOutput step-vs-final split) map to different v4
  hooks; a wrong mapping silently degrades run-logging or Sentry tagging.
  **Mitigation:** port the existing suites first (they encode #5674/#6703's
  contracts), then the implementation; `onRunError.isFinalAttempt` is the native
  replacement for the manual `attempt >= maxAttempts - 1` gate — keep both only if
  they disagree in testing.
- **R3: `streaming: true` ≠ `"force"` on non-Vercel.** v3's `allow` didn't stream
  off-Vercel (hence `force`); v4's boolean `true` is documented to stream where
  the handler supports it — verified by S2/S3 + the unsigned-POST envelope row,
  not assumed.
- **R4: dev/test env mode.** v4 defaults to cloud mode; any test or dev path
  lacking a signing key now hard-fails differently (SDK-level throw may precede
  our guard's message). `signature-verify-dev-mode.test.ts`,
  `client-startup.test.ts`, and the `NEXT_PHASE` build-phase bypass may need
  message updates.
- **R5: `serveOrigin` env-pair.** `INNGEST_SERVE_HOST` is deprecated-but-read;
  the repo uses neither env (hardcoded const) — no Doppler change. Verified by
  the registration spike row, not assumed.
- **R6: spike reproducibility.** The 2026-09-23 spike was a workstation run, not a
  committed harness; Phase 4 rebuilds it from the archived setup section.
  Time-boxed: if the tunnel/server harness cannot be stood up, the deletion does
  not ship without S7 evidence — fall back to keeping the wrapper (it is harmless
  under v4) and de-scoping the deletion to a follow-up.
- **R7: `suite-durations.tsv` floor semantics.** Deleting the probe's `floor`
  row must not strand a shard-expectation — the two TSVs are regenerated by the
  sharding tooling; run whatever regenerates/validates them (shard-leg tests)
  rather than hand-editing blindly.
- **Merge-queue repo:** land via merge queue; lockfile regeneration is the known
  conflict surface — regen last, immediately before PR-ready.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #8628 is OPEN with no closing PR.
PR #8611 is MERGED (2026-09-23). `server/inngest/stream-detach.ts`,
`scripts/followthroughs/inngest-verify-clean-10390.sh`,
`_cron-community-publication.ts` all exist on `origin/main`; `inngest` is at
`3.54.2`. Two corrections to the brief's working notes: (a) **no `bun.lock`
exists in this repo** — `lint-dual-lockfile.sh` (ADR-191) asserts zero tracked
bun lockfiles; only `apps/web-platform/package-lock.json` regenerates (npm@11);
(b) the stream-detach **test** lives at
`apps/web-platform/test/server/inngest/stream-detach.test.ts` (not beside the
module). The pinned self-hosted server is now **v1.45.1**
(`apps/web-platform/infra/inngest.tf:33`), not the v1.19.4 the spike/ADR-243
named — the server was bumped since. Collision precheck: PR #11381 is this
branch's own pipeline draft — not a foreign duplicate. A foreign
`test-all.sh --affected` runs in a different worktree (`feat-one-shot-11195…`)
— noted; commits here wait only for same-worktree runs.

**Property List (Phase 0.6b).** (1) `inngest@^4` installed with a synced npm
lockfile; (2) all call sites compile on the v4 API; (3) the three middlewares
preserve their tested contracts on the new hook model; (4) `serve()` keeps the
#5159 registration pin and ADR-030 I4 signature gate under v4 options; (5) the
SDK heartbeat-leak workaround is deleted **only with spike evidence** the
upstream fix holds on the pinned server; (6) checkpointing is pinned off this
PR (CTO ruling — flip-on is a measured follow-up, not an assumption either
way); (7) the followthrough probe and its registry rows are fully retired;
(8) the four P3 review items ship.

**Cut List.** No proposed mechanism was cut — the asks are deletions, a codemod,
and evidence. One candidate was evaluated and rejected by the minimalism ladder:
a v4-era replacement for the `inngest-stream-*` app-side telemetry (the
server-side `inngest_step_524` needle already detects drops — rung 4, an
already-deployed mechanism).

**Key files.** `apps/web-platform/app/api/inngest/route.ts` (serve mount,
wrapper site); `server/inngest/client.ts` (client + middleware array + build-phase
bypass); `server/inngest/middleware/{sentry-correlation,run-log,bound-logger}.ts`;
`server/inngest/stream-detach.ts` + `test/server/inngest/stream-detach.test.ts`
(deletions); `test/server/inngest/signature-verify{,-dev-mode}.test.ts`;
`server/inngest/functions/*.ts` (71 `createFunction` sites incl.
`_cron-community-publication.ts` fd-pinning block ~lines 635–862);
`test/server/inngest/cron-community-publication.test.ts`;
`test/helpers/inngest-step-harness.ts` (models async step semantics — its
one-new-step-per-request model is why checkpointing ships off; comment updated
to name the ruling);
`scripts/followthroughs/inngest-verify-clean-10390.{sh,test.sh}`,
`scripts/test-all.sh`, `scripts/suite-durations.tsv`,
`scripts/suite-shard-legs.tsv`,
`plugins/soleur/test/fixture-relative-assert.baseline.txt`;
`knowledge-base/engineering/architecture/decisions/ADR-243-*.md`.

**Learnings applied.** `2026-09-23-cloudflare-524-…` (why streaming exists);
`2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-…` (run-log #5674
contract); `2026-09-24-followthrough-retirement-headers-underenumerate-…`
(retirement census is the load-bearing step — drove the 6-row table);
`respike-measured-new-binary-never-old` (spike methodology: measure the new
binary); `2026-10-22-a-verdict-function-inside-command-substitution-…`
(the probe being retired); ADR-191 (`bun.lock` must not exist).

**External sources.** Inngest v3→v4 migration guide
(inngest.com/docs/reference/typescript/v4/migrations/v3-to-v4); v4 middleware
lifecycle reference; checkpointing docs (self-hosted ✅, `checkpointing: false`
opt-out, `maxRuntime` for serverless); `inngest@4.26.1` npm tarball — `cancel()`/
`closed`/try-catch verified in `helpers/stream.js`, hook arg types verified in
`components/middleware/middleware.d.ts` (`OnRunErrorArgs.isFinalAttempt` is the
native replacement for the manual final-attempt gate).

**Research reconciliation — spec claims vs codebase.** (a) "~70 functions" → 71
`createFunction` files, 73 registered entries — matches in spirit. (b) Issue says
"its test" beside the module → test is under `test/server/inngest/`. (c) Brief's
"regenerate bun.lock" → no bun.lock exists by design. (d) ADR-243 names server
v1.19.4 → pinned server is v1.45.1. (e) Issue's own trigger list ("content-hash
pin goes red", etc.) does not gate — operator-directed drain, confirmed.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-243 in place** (task in Phase 6): §1 records the upstream fix
(`cancel()`/`closed`/try-catch in v4 `createStream`) and the wrapper deletion it
always promised; the "Upgrade to `inngest@4` now" Alternatives row is marked
executed with the spike artifact cited; the Observability table retires
`inngest-stream-consumer-cancel`/`inngest-stream-drain-error` (drop coverage
moves to the server-side `inngest_step_524` needle, attribution loss accepted);
the `checkpointing: false` ruling and the S9 measurements are recorded. Status
stays Accepted + amendment date line.

### C4 views

Read `diagrams/{model.c4,views.c4,spec.c4}` against the actor/system/relationship
rubric: (a) external human actors — none added (founder BYOK loop already
modeled); (b) external systems — self-hosted `inngest` server already modeled as
a container/system with its edges; the SDK version is not a C4 element; (c)
containers/data-stores — `api` and `inngest` containers unchanged; (d)
relationships — `inngest -> api` step calls and `api -> inngest` registration
edges are transport-identical after the upgrade. **Conclusion: no C4 impact** —
the diff changes a library version and deletes an internal workaround inside the
`api` container; nothing the C4 models moves.

## Infrastructure (IaC)

None introduced — no new server, unit, secret, vendor, firewall rule, or DNS
record. The spike's `inngest start` v1.45.1 binary and quick tunnel are
workstation test fixtures (throwaway keys, torn down with the run), not
provisioned infrastructure. The self-hosted server version is unchanged
(v1.45.1 already deployed).

## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: none

- Hold: Operator-reserved: #10382 — the INNGEST_SIGNING_KEY rotation and nftables re-read decision-challenge; production-mutating, waits for a human ruling
- Hold: Operator-reserved: Bucket 2 (#7596, #10112, #8620, #9927 host-bound subset, #6178, #9137) — gated on the next sanctioned inngest host replace; needs a fresh owner go (the 2026-10-26 replace spent the prior go)

## GDPR Gate (Phase 2.7 record)

Fires by regex — `app/api/inngest/route.ts` matches
`apps/web-platform/app/api/.*\.ts$`. Inline advisory assessment (no agent spawn
available in this subagent): the diff changes SDK transport options and deletes a
streaming wrapper; it does not change what event payloads flow, who processes
them (same self-hosted server), or how they are scrubbed (`beforeSend` redaction
unchanged; sentry-correlation's `extra` attachment preserved on the v4 port). No
Art. 9 surface, no new processing activity, no Art. 30 trigger, no new
cross-controller movement. **Finding: no Critical/High items.** This is not
legal review; findings are heuristic.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan
  Phase 4.6 — filled above.
- `discoverability_test.command` runs in a 15 s sandbox — the `jq` probe above
  is sub-second, allowlisted, and prints a literal `^4` prefix.
- Do not commit while `scripts/test-all.sh --affected` runs in this worktree.
- The 25-file scope-check threshold is advisory, not a split mandate — see the
  atomicity note in Split Assessment.
- Function `id:` strings are load-bearing identifiers (cron planning, memoized
  run history, Sentry monitor slugs) — the codemod moves arguments only.
- `serve()` `signingKey` build-phase placeholder: the v4 client-level
  `signingKey` must keep the same `NEXT_PHASE` bypass semantics or `next build`
  page-data collection breaks.

## References & Research

- Issue: #8628; epic: #10390; workaround PR: #8611; ADR: ADR-243 (+ ADR-030 I4,
  ADR-191 lockfile, ADR-033 placement).
- Spike record being re-run:
  `knowledge-base/project/specs/archive/20260923-200917-feat-anthropic-spend-reduction/streaming-spike.md`.
- P3-residual source PR: #11334 (squash `76ff5830ac56`).
- Upstream: inngest-js v3→v4 migration guide; v4 middleware lifecycle;
  checkpointing docs; `inngest@4.26.1` tarball (verified `createStream` fix +
  hook arg types + `ProxyLogger`/`StepError`/`serializeError` exports).
