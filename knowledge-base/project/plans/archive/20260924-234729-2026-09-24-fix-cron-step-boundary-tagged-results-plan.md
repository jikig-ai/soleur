---
title: "fix(inngest): cron deploy-defer and drift-guard leak verdicts cross the step boundary as returned values, not instanceof"
type: fix
date: 2026-09-24
slug: fix-cron-step-boundary-tagged-results
branch: feat-one-shot-8726-cron-step-tagged-results
issue: 8726
closes: 8726
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix(inngest): cron step-boundary verdicts as returned values

## Enhancement Summary

> **Amended at review (2026-09-24).** `throwIfDeployDeferred` shipped as `unwrapSetupVerdict`
> (returns the workspace and accepts the pre-#8726 memoized shape); the verdict type is not generic;
> a leak THROWN inside `drift-check` takes the leak path; the census walks `server/inngest/`
> recursively and checks wiring. See the PR's review commits.

**Deepened on:** 2026-09-24. **Plan review:** DHH, Kieran, code-simplicity, CTO (devex). **Deepen
seats:** security-sentinel, observability-coverage-reviewer, test-design-reviewer,
architecture-strategist, a verify-the-negative sweep (15 claims, 0 contradicted), Context7 (Inngest
docs: per-step retry counters, `RetryAfterError`), a plan-time advisor consult.

### Key Improvements

1. **A second secret channel closed in the drift guard.** `drift-check` returned raw upstream
   error text (PEM included) as its step output, persisted in Inngest run state. It now scans its
   result with `assertNoLeak("drift-result", …)` and rethrows other errors already redacted.
2. **Every leak arm reports to Sentry** (`op: "leak-tripwire"`); before, a leak caught in
   `notify-ops-email` left only a red heartbeat.
3. **The harness is specified against the SDK's real behaviour where it matters** (`undefined` →
   `null`, per-invocation duplicate-ID check, `HarnessError` for its own failures) and its
   self-test asserts fixed facts instead of comparing the harness with itself.
4. **One final-attempt predicate** (`isFinalAttempt`), shared with `finalizeOutputAwareHeartbeat`,
   with its one divergence from the SDK documented and tested.
5. **Mechanisms cut at review** (`label`, SDK pin, Guard 2's positive set, harness extras); Guard 2
   became a token census over the whole functions directory.

### New Considerations Discovered

- Posting no heartbeat still alerts: each claude-eval monitor opens a *missed* check-in issue after
  60 minutes, and `sentry-correlation` captures the deferral twice (DC-1).
- Whether a cron-monitor issue pages anyone is not in Terraform; Phase 4 reads it live.
- `RetryAfterError` could time the deferral retry after the deploy, but only for handler-level
  rejections in SDK 3.54.2 (DC-2).
- Follow-ups filed: #8762 (8 callers with no deferral arm), #8764 (move boundary-crossing suites
  onto the harness; a general census).

## Overview

Nine claude-eval cron handlers and the GitHub App drift guard decide how to react to a failure by
checking `instanceof` on an error that was thrown inside an Inngest `step.run`. After the step's
retries are exhausted, the handler receives a rebuilt error whose class and name did not survive the
round-trip, so those checks never match in production. This plan moves the verdict across the step
boundary as a returned value, and gives the cron test suites a step harness that rebuilds the
escaping error the way Inngest does.

Two outcomes change in production:

1. **Deploy-lease deferral (9 crons).** A deploy that outlasts the one step retry currently reads as
   a setup failure: a Sentry `op: setup-ephemeral-workspace` report plus a red Sentry heartbeat. After
   this fix it takes the ADR-078 deferral arm that the unit suites have asserted all along: no
   heartbeat, and a `DeployInProgressError` thrown from the handler body (outside any step), so the
   Sentry events (one per handler-level attempt) carry the real class name. The cron monitor then records a
   *missed* check-in (about an hour later, per its 60-minute margin) instead of a *failed* one:
   the alert still fires, but it now says what happened (the fire was skipped) rather than
   reporting a setup failure that did not occur. Whether a deferral should alert at all is a
   separate decision, recorded as DC-1 in `decision-challenges.md`.
2. **Drift-guard leak routing.** A leak tripwire fired inside the `drift-check` step currently files
   a routine `ci/guard-broken` issue (`github_api_network`). After this fix it files the
   `[security/leak-suspected]` issue. A second defect of the same class in the same file is folded in:
   `leakDetected = true` is assigned inside two step callbacks, and Inngest re-enters the handler from
   the top after every step, so that assignment is lost for every later step (the ops email, the
   heartbeat colour and the return value all read `false`).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / task brief) | Reality on `origin/main` (7909263fae) | Plan response |
|---|---|---|
| "Return a tagged value from the step instead of throwing" | Throwing is what buys the deferral's retry. Inngest retries the **step** (the SDK sends `StepOpCode.StepError` on a non-final attempt, `node_modules/inngest/components/execution/v2.js` `errorIsRetriable`), and that retry re-checks the lease. A step that *returns* is memoized and never re-run, so returning on every attempt would turn every deferral into an immediate skip. | Attempt-aware: the step **throws** on a non-final attempt (unchanged retry) and **returns** `{ kind: "deploy-deferred" }` on the final attempt, using `finalizeOutputAwareHeartbeat`'s final-attempt predicate (which agrees with the SDK's `StepFailed`-vs-`StepError` choice whenever `maxAttempts` is present). |
| "18 `DeployInProgressError` sites" | 9 files x 2 sites. The first (setup-workspace catch) is the broken one. The second (inner body catch) is **unreachable**: the only producer is `setupEphemeralWorkspace` (`_cron-claude-eval-substrate.ts`, the `throw new DeployInProgressError` after `deployLeaseAgeMsIfFresh`), which no inner body calls. | Remove the inner-body checks. ADR-126 "Named residual 1" names an error with no producer there; reword it in place to the real hazard it was reaching for (see Architecture Decision). |
| "The handler rethrows bare so Inngest retries after the container swap" (code comment at every first site, from PR #5729) | The handler `catch` never sees the error on a non-final attempt: the SDK ends the request and retries the step. The catch only ever sees a `StepError` after exhaustion, when there is no retry left to buy. | Comments rewritten to state the real mechanism. |
| "Custom `name` does not survive" (learning, #8717) | Measured against the installed SDK (3.54.2): `serializeError(new DeployInProgressError(...))` yields `name: "Error"`, `leaseAgeMs` absent; `new StepError(id, json)` has `name "Error"`, `instanceof DeployInProgressError === false`; `message` survives verbatim. | The harness uses the real `serializeError` + `StepError` exported from `inngest`, not a hand model. |
| Issue lists 9 cron files + drift guard | Census of `instanceof` / `.name ===` / `.status ===` on errors under `server/inngest/`: `cron-anthropic-cost-report.ts`, `cron-anthropic-credit-probe.ts`, `cron-gh-pages-cert-reissue.ts` and every `(err as { status?: number }).status` site test a **live** error inside a step callback or a helper. Correct as is. | No other file in scope. |
| Deploy-lease gate reaches "the 9 crons" | The substrate's `setupEphemeralWorkspace` has **17** callers. 8 have no deferral arm at all (never had one) and pass no `attempt`/`maxAttempts`. Six more files (`cron-compound-promote`, `cron-content-publisher`, `cron-content-vendor-drift`, `cron-github-cidr-refresh`, `cron-rule-prune`, `cron-strategy-review`) define their **own** local `setupEphemeralWorkspace`, do not import the substrate, and have no lease gate, so they never throw `DeployInProgressError` (a plan-review count of 23 included them). | Deferred to **#8762** (blocked by #8726). Not the `instanceof` defect. |

## Research Insights

**Premise Validation.** #8726 is OPEN (checked 2026-09-24). PR #8717 is MERGED (2026-09-24T17:30Z)
and its returned-verdict pattern is on `origin/main` (`agent-on-spawn-requested.ts`,
`classifyLiveRejection` / `kind: "turn_rejection"`). Every cited file and symbol exists on
`origin/main`. ADR corpus grep for the mechanism (returned verdict, `DeployInProgressError`, step
retry): ADR-078 records the deferral as "rethrow bare, no heartbeat" and does not reject a returned
verdict; ADR-126's amendment names the inner-body deferral as residual 1. Neither rejects this
mechanism. Nothing stale.

**Property List (Phase 0.6b).**

- P1. A deploy deferral that outlasts the step retry reaches the ADR-078 deferral arm (no heartbeat,
  no `setup-ephemeral-workspace` failure report), not the setup-failure arm.
- P2. A deploy lease that clears before the step retry still gets the retry: the run proceeds.
- P3. A genuine setup failure on the final attempt still takes the setup-failure arm.
- P4. A leak tripwire fired anywhere in the drift guard reaches every downstream decision (issue
  routing, ops email, heartbeat colour, return value), including after Inngest re-enters the handler.
- P5. The cron suites can see this defect class: a test whose step mock re-throws the raw error, or
  never re-enters the handler, cannot.

**Cut List.**

- Message-marker predicate (`err.message` contains "deploy in progress") → P1 → rejected, not cut:
  covered by the returned verdict, which is type-checked; a marker is string routing across the
  boundary and a wording change silently re-breaks it (#8717 learning, Key Insight).
- Returning the verdict on every attempt → would break P2 → cut.
- A new Sentry op or metric for the deferral → P1 visibility → already covered by the substrate's
  `reportSilentFallback(op: "deploy-lease-fresh")` on every attempt, plus the function-final Sentry
  capture in `middleware/sentry-correlation.ts`.
- Migrating `makeRetryingStep` in `agent-on-spawn-requested-leader-loop.test.ts` to the new shared
  harness → buys no property here → out of scope.
- Added at plan review, then cut (DHH + code-simplicity seats): a `label` field on
  `LeakDetectedError` and the leak verdict (nothing reads it; `handleLeakIssue` takes no label); an
  SDK-version pin in the harness self-test (`package.json` already pins `inngest` exactly, and the
  rebuild uses the SDK's own code); Guard 2's pinned 9-name set and size check (`tsc` and S1 already
  carry "every cron routes through the helper"); harness extras with no scenario depending on them
  (handler-body retry modelling, an `invocations[]` trace, a `NonRetriableError` row, a by-hand
  mutation run).

**Inngest execution facts (SDK 3.54.2, measured in `node_modules/inngest`).**

- Non-final attempt, step throws: op `StepError` (retriable), request ends, handler code after the
  step does not run in that request. Final attempt: op `StepFailed`. Predicate:
  `fnArg.maxAttempts - 1 === fnArg.attempt` (`v2.js`), and `fnArg` is the handler's `ctx`.
- After exhaustion, `step.run` rejects with `new StepError(stepId, result.error)`
  (`components/StepError.js`). `jsonErrorSchema` defaults `name` to `"Error"`; `serializeError`
  already writes `name: "Error"` for a subclass. Only `message`, `stack`, `cause` carry data.
- A handler that rethrows *that* `StepError` is non-retriable (`recentlyRejectedStepError`). A fresh
  error thrown from the handler body is retriable until the final attempt.
- No `checkpointing` is configured (`server/inngest/client.ts`), so execution is async mode: one new
  step per request, then the handler is re-entered from the top with memoized results. A variable
  assigned inside a step callback exists only in the request that ran it.
- `StepError` and `serializeError` are both exported from the `inngest` package root (subpath
  `inngest/helpers/errors` is not exported — `ERR_PACKAGE_PATH_NOT_EXPORTED`).

**Downstream observers of a function-final throw.** `middleware/sentry-correlation.ts`
`transformOutput` captures the function-final error to Sentry; `middleware/run-log.ts` writes a
`failed` `routine_runs` row on a final thrown attempt. Both already apply to the intended ADR-078
arm; this plan does not change them.

**Relevant files.**

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — `DeployInProgressError`, the
  `finalizeOutputAwareHeartbeat` final-attempt predicate `(attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`.
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` —
  `setupEphemeralWorkspace`, the only `DeployInProgressError` producer.
- The 9 crons: `cron-seo-aeo-audit.ts`, `cron-community-monitor.ts`, `cron-growth-audit.ts`,
  `cron-growth-execution.ts`, `cron-architecture-diagram-sync.ts`, `cron-campaign-calendar.ts`,
  `cron-competitive-analysis.ts`, `cron-content-generator.ts`, `cron-roadmap-review.ts`. All
  `retries: 1`, all receive `attempt`/`maxAttempts` (already passed to `finalizeOutputAwareHeartbeat`).
- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — `LeakDetectedError`,
  `assertNoLeak`; handler sites: the `drift-check` step catch, and `leakDetected = true` inside the
  `issue-handling` and `notify-ops-email` step callbacks.
- Tests: `test/server/inngest/cron-cohort-dedup.test.ts` (8 of the 9 crons via `ROWS`; substrate
  fully mocked, `_cron-shared` partially mocked with `importOriginal`),
  `cron-community-monitor-heartbeat.test.ts` (the 9th), `cron-producer-output-wiring.test.ts`
  (source-scan wiring guard, asserts `toContain("instanceof DeployInProgressError")` today),
  `cron-github-app-drift-guard.test.ts` (non-memoizing `makeStep`), `test/server/cron-drain-lease.test.ts`
  (substrate throw, unchanged).

**Institutional learnings applied.**

- `integration-issues/2026-09-24-a-thrown-error-loses-its-status-at-the-inngest-step-boundary-so-return-the-verdict.md`
  — read the live error inside the step and return the verdict; a harness that re-throws the raw
  error cannot see this class; a boundary harness must model the boundary on every row.
- `2026-06-11-pipeline-consolidation-behavior-preserving-migration-traps.md` — swapping a throw for a
  returned value drops the retry the throw was buying. Drove the attempt-aware design and P2.
- `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md` — the canonical
  final-attempt predicate and fail-safe defaults.
- `best-practices/2026-07-02-inngest-side-effect-outside-step-run-duplicates-on-replay.md` — code
  outside `step.run` re-runs on every re-entry. The harness therefore re-enters the handler after
  every step; assertions on out-of-step side effects use "was called" / "never called", not counts.
- `2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md` — assert
  against an external referent (the real SDK's rebuild), not the harness's own output.

**CLAUDE.md / AGENTS.md conventions.** `cq-write-failing-tests-before` (RED first), `cq-silent-fallback-must-mirror-to-sentry`,
`hr-type-widening-cross-consumer-grep` (the `LeakDetectedError` constructor gains a field; the
setup-step return type changes — grep all consumers), `cq-test-fixtures-synthesized-only` (PEM/JWT
fixtures are synthetic strings).

**Related.** #8717 (the pattern), #5728/#5729 (introduced the `instanceof` checks), #5669/ADR-078
(the lease), ADR-126 (liveness, residual 1), #8762 (deferred: 8 callers with no deferral arm).

## Problem Statement

`instanceof` on an error that crossed a step boundary is always `false` in production, because the
handler receives an Inngest `StepError`, not the thrown class. The suites are green because every
mock `step.run` either calls the callback inline (the raw error propagates in-process) or never
re-enters the handler (closure assignments inside step callbacks survive). Two consequences:

- A long deploy (up to the 4800 s ceiling in ADR-078) outlasts the one step retry, and nine crons
  report it as a setup failure with a red heartbeat. False alarm, no data loss.
- A leak tripwire in `drift-check` files a `ci/guard-broken` issue instead of
  `[security/leak-suspected]`; a leak tripwire in `issue-handling` or `notify-ops-email` is forgotten
  by every step after it.

## Proposed Solution

### Deploy deferral (9 crons)

Add to `_cron-shared.ts` (next to `DeployInProgressError`, so the partial `_cron-shared` mocks in the
suites keep the real implementation):

```ts
// _cron-shared.ts

/** The one final-attempt predicate. finalizeOutputAwareHeartbeat is refactored to call it too. */
export function isFinalAttempt(ctx: { attempt?: number; maxAttempts?: number }): boolean {
  return (ctx.attempt ?? 0) >= ((ctx.maxAttempts ?? 1) - 1);
}

// Generic over the workspace so _cron-shared.ts never imports the substrate (which imports
// _cron-shared.ts) and the substrate's return type cannot drift from a copy.
export type WorkspaceSetupVerdict<W> =
  | { kind: "ready"; workspace: W }
  | { kind: "deploy-deferred"; leaseAgeMs: number };

/** Run INSIDE step.run("setup-workspace"). The error is live here, so instanceof is valid. */
export async function deferDeployOnFinalAttempt<W>(
  setup: () => Promise<W>,
  ctx: { attempt: number | undefined; maxAttempts: number | undefined }, // keys required: see below
): Promise<WorkspaceSetupVerdict<W>>;
// non-final attempt + DeployInProgressError -> rethrow (Inngest retries the step, re-checking the lease)
// final attempt     + DeployInProgressError -> return { kind: "deploy-deferred", leaseAgeMs }
// any other error                            -> rethrow unchanged
// success                                    -> { kind: "ready", workspace }

/** Call in the handler body, AFTER the setup-workspace try/catch and BEFORE the body's try/finally. */
export function throwIfDeployDeferred<W>(
  v: WorkspaceSetupVerdict<W>,
  cronName: string,
): asserts v is { kind: "ready"; workspace: W };
```

The `ctx` keys are required (their values may be `undefined`), so a future caller that has not
plumbed `attempt` / `maxAttempts` fails `tsc` instead of silently losing the retry (#8762's 8
callers pass neither today). `HandlerArgs.attempt` is `number | undefined`, so the 9 crons pass
`{ attempt, maxAttempts }` unchanged.

Each cron's setup block becomes (growth-audit shown; the other 8 are the same shape):

```ts
let verdict: WorkspaceSetupVerdict<{ ephemeralRoot: string; spawnCwd: string }>;
try {
  verdict = await step.run("setup-workspace", async () =>
    deferDeployOnFinalAttempt(
      () => setupEphemeralWorkspace({ installationToken, cronName: "cron-growth-audit" }),
      { attempt, maxAttempts },
    ),
  );
} catch (err) {
  // unchanged setup-failure arm, minus the `instanceof DeployInProgressError` line
  ...
  return { ok: false };
}
// ADR-078 deferral. Deliberately OUTSIDE the catch: a live DeployInProgressError thrown inside
// the try would be caught by the setup-failure arm above.
throwIfDeployDeferred(verdict, "cron-growth-audit");
ephemeralRoot = verdict.workspace.ephemeralRoot;
spawnCwd = verdict.workspace.spawnCwd;
```

The inner-body `if (err instanceof DeployInProgressError) throw err;` line is deleted in all 9.

Why this final-attempt predicate: `isFinalAttempt` is `finalizeOutputAwareHeartbeat`'s existing
`(attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`, extracted so both helpers call one function and cannot
drift. When `maxAttempts` is present it agrees with the SDK's own choice between a retriable
`StepError` and a terminal `StepFailed` (`maxAttempts - 1 === attempt`, `v2.js`), so "throw" happens
exactly when a throw buys a retry. They diverge only when `maxAttempts` is absent: the SDK then
treats the step as retriable, this predicate treats it as final (see Fail-safe default; S4 pins it).
The same `if (!isFinalAttempt) throw err` shape already exists in `cron-anthropic-cost-report.ts`.

### Drift guard

- `LeakDetectedError` is unchanged. Nothing downstream reads which call site tripped
  (`handleLeakIssue({ octokit, detectedAtIso, runUrl })` takes no label), so the verdicts carry a
  boolean only.
- All three steps return the same shape:
  - `drift-check` → `{ result: DriftResult; leakDetected: boolean }`. Inside the callback:
    1. a live `LeakDetectedError` from the probe returns `{ result: EMPTY_RESULT, leakDetected: true }`;
    2. **before returning a probe result, the callback runs
       `assertNoLeak("drift-result", JSON.stringify(result))`**, and a match takes the same arm.
       Without this, `probeDriftGuard`'s network branch
       (`` `GET /app -> network error: ${e.name}: ${e.message}` ``) puts raw upstream error text,
       PEM included, into the step output, which Inngest persists in run state (pre-existing; found
       at deepen-plan by the security seat);
    3. any other error is rethrown as `redactedError(err)`, so the error Inngest stores for a
       failed step is the redacted one (today the raw error is stored before the outer catch
       redacts it). The outer catch reads no `.status`, so nothing is lost; it keeps the
       `github_api_network` conversion, builds `failureDetail` from the already-redacted message,
       and loses its dead `instanceof` branch.
  - `issue-handling` → `{ leakDetected: boolean }`. The callback holds a local `let leak = false`,
    sets it in the inner `catch (innerErr)` arm, and returns `{ leakDetected: leak }` **after** its
    outer try/catch, so a leak followed by a failing `handleLeakIssue` (for example a 403 on the
    issue write, which the outer catch reports and swallows) still returns `true`. The outer catch's
    `reportSilentFallback` reports `extra.leakDetected: leak` (the local), not the handler variable.
  - `notify-ops-email` → `{ leakDetected: boolean }`, same local-variable shape. Its outer catch keeps
    the literal `op: "notify-ops-email"`: the `issue-alerts.tf` rule filters on it and
    `test/sentry-ops-email-delivery-alert-op-contract.test.ts` pins it.
- Each leak arm (all three steps) emits, inside the step so a replay does not repeat it,
  `reportSilentFallback(null, { feature: "cron-github-app-drift-guard", op: "leak-tripwire", extra: { step: "<step-id>" } })`
  with no matched text. Today no leak arm reports to Sentry at all, and a leak caught in
  `notify-ops-email` files no issue and sends no email, so the red heartbeat was its only trace.
- The handler folds each returned value into its own `leakDetected`. No step callback assigns a
  handler-scope variable.

### Test harness

New `apps/web-platform/test/helpers/inngest-step-harness.ts`, built on the real SDK. It models what
the scenarios need and nothing more:

- `rebuildAsStepError(stepId, err)` → `new StepError(stepId, JSON.parse(JSON.stringify(serializeError(err))))`,
  both imported from `"inngest"`.
- `runLikeInngest(invoke, { maxAttempts, memo? })` drives a handler the way async-mode Inngest does:
  - one memo map shared across invocations. The caller may pass its own `Map`, to read step outputs
    (AC7) or to **seed** a step's memoized output (S6, S6b, S7 seed `drift-check`);
  - step outputs are memoized as `JSON.parse(JSON.stringify(v ?? null))`: `undefined` becomes
    `null`, as the SDK's `undefinedToNull` does. A bare `JSON.stringify(undefined)` returns
    `undefined` and the parse throws, which would crash every `sentry-heartbeat` step;
  - on the first un-memoized step in an invocation: run it; success → memoize, then end the
    invocation, re-enter; throw on a non-final attempt → end the invocation, re-enter with
    `attempt + 1`; throw on the final attempt → memoize `rebuildAsStepError(...)`, end, re-enter.
    The interruption fires only after the memo write;
  - a memoized failure makes `step.run` reject with the stored `StepError`;
  - "end the invocation" = `step.run` returns a never-settling promise and the driver races it, so
    the handler's own `catch` cannot observe an interruption (as in production). A pending promise
    holds no event-loop handle, so vitest does not hang; an interrupted invocation's `finally`
    never runs, exactly as in the SDK, so no scenario asserts teardown counts;
  - a handler-body throw ends the run (outcome `threw`); a handler return ends it (outcome
    `returned`);
  - harness-detected problems throw a dedicated `HarnessError` class: the invocation cap, a step ID
    seen twice **within one invocation** (the SDK would suffix it as `id:1`; counting across
    invocations would trip on every replay), and an output that cannot be JSON-serialized. A RED
    run therefore shows either a scenario assertion or a `HarnessError`, never one disguised as the
    other;
  - returns `{ outcome: "returned" | "threw", value?, error? }`.
- The docstring states the one guessed behaviour: `attempt` after a successful step is reset to 0.
  Inngest's docs say each `step.run` has its own retry counter, which supports it, but the value the
  server sends is not in the SDK. No scenario's assertion depends on it.

## Technical Considerations

- **Retry preserved (P2).** Non-final behaviour is byte-for-byte today's: the step throws
  `DeployInProgressError`, the SDK sends a retriable `StepError`. Only the final attempt changes.
- **Replay after the deferred verdict.** `throwIfDeployDeferred` throws in the request after the step
  memoized; in async mode that request starts at `attempt` 0, so Inngest retries once more, replays
  the memoized verdict and throws again on the final attempt. `middleware/sentry-correlation.ts`
  captures every handler-level rejection (not only the final one), so a deferral produces **two**
  `DeployInProgressError` Sentry events, one per attempt. No side effect is repeated: token mint
  and setup are memoized. Checked at plan time: between each of the 9 handler entries and
  `"setup-workspace"`, the only un-stepped emitter is `emitCronDedupSkip`, which sits on the
  dedup early-return path and cannot run on a deferral (the run that defers is the one that did
  not dedup-skip).
- **Fail-safe default.** `maxAttempts` absent → predicate reads "final" → the deferral returns on
  attempt 0 with no retry (the SDK would have retried; this is the one divergence, and it is
  deliberate). Same degradation direction as `finalizeOutputAwareHeartbeat`: it can
  skip a fire, it cannot mask a real failure.
- **Type widening (`hr-type-widening-cross-consumer-grep`).** The setup step's return type becomes
  `WorkspaceSetupVerdict`; `tsc` flags every `.ephemeralRoot` read before narrowing. The
  `drift-check` step's return type changes from `DriftResult` to `{ result, leakDetected }`; grep
  `step.run("drift-check"` and every `result.` read in the handler and its test.
  `LeakDetectedError` and `assertNoLeak` are unchanged.
- **What reaches Inngest run state.** A step's return value and a failed step's error are both
  persisted and shown in the Inngest dashboard. Today three drift-guard channels put secret-derived
  text there: the `drift-check` result's `failureDetail` (raw upstream error text); a thrown
  `LeakDetectedError`, whose message carries a 16-character prefix of the match and then flows on
  into a `ci/guard-broken` issue body, the ops email and Sentry (the prefix is mostly a non-secret
  header such as `eyJhbGciOi` or `BEGIN RSA PRIVAT`, so the impact is low); and any other probe
  error, stored raw before the outer catch redacts it. After the fix: verdicts are booleans, the
  result is scanned before it is returned, a leak never escapes the step as an error, and other
  errors leave the step already redacted.
- **`assertNoLeak` blocking is unchanged.** Every emission site still throws before emitting; only
  the routing after the block changes.
- **The step type hides the JSON boundary.** All 10 handlers take `HandlerArgs`
  (`_cron-shared.ts`), whose `step.run<T>(…): Promise<T>` is not Inngest's `Jsonify<T>`. `tsc`
  therefore accepts a verdict field that would not survive JSON (a `Date`, `undefined`, a class
  instance). Keep every verdict field a string, number or boolean; the harness's JSON round-trip is
  the only check that sees a violation.
- **Performance / NFR.** None: one extra memoized re-entry on the deferral path only.

### Attack Surface Enumeration (drift-guard leak routing)

Every `assertNoLeak` call site and the step it runs in:

| Site | Step | Today after exhaustion / replay | After |
|---|---|---|---|
| `suppress-warning` (in `probeDriftGuard`) | `drift-check` | `StepError` → `github_api_network`, `ci/guard-broken` | returned `{ leakDetected: true }` → `[security/leak-suspected]` |
| `drift-result` (new: the probe result, scanned before `drift-check` returns it) | `drift-check` | raw upstream error text, PEM included, persisted as the step output | returned `{ leakDetected: true }`; the result is replaced by `EMPTY_RESULT` |
| `issue-body`, `issue-comment` (in `handleFailureIssue`) | `issue-handling` | live catch files leak issue; `leakDetected` lost on re-entry | returned `{ leakDetected: true }` |
| `resend-body`, `resend-subject`, `resend-error-body` (in `notifyOpsEmail`) | `notify-ops-email` | `leakDetected` lost on re-entry | returned `{ leakDetected: true }` |

No other `assertNoLeak` call exists today (`grep -n "assertNoLeak(" cron-github-app-drift-guard.ts`); `drift-result` is the one this plan adds.

## Implementation Phases

### Phase 1 — Harness first (RED)

1. Write `test/helpers/inngest-step-harness.ts` and `test/helpers/inngest-step-harness.test.ts`
   (harness self-test: see Guard 1).
2. Add the failing scenarios (Test Scenarios S1, S2, S3, S5, S5b) using the harness. Confirm S1,
   S5, S5b fail on the current code for the stated reason (setup-failure arm reached; leak routed
   as `github_api_network`; `leakDetected` false).

### Phase 2 — Deploy deferral (GREEN)

1. `_cron-shared.ts`: add `isFinalAttempt` and refactor `finalizeOutputAwareHeartbeat` to call it;
   add `WorkspaceSetupVerdict<W>`, `deferDeployOnFinalAttempt<W>`, `throwIfDeployDeferred<W>`; update the `DeployInProgressError` doc comment and the
   `finalizeOutputAwareHeartbeat` comment ("excluded by the caller BEFORE…") to name the helper.
2. The 9 crons: wrap the setup step, delete both `instanceof DeployInProgressError` lines, add
   `throwIfDeployDeferred` after the setup try/catch, rewrite the "#5728 G1" comments to state the
   real mechanism. Update the "DeployInProgressError still rethrows bare" comment beside
   `retryEligible: false` in **all 9** crons, and drop the now-unused `DeployInProgressError` import.
3. Update `cron-community-monitor-heartbeat.test.ts` (delete the inner-body scenario, which injects
   an error with no production producer; move the setup-workspace scenario onto the harness),
   `cron-cohort-dedup.test.ts` scenario 11 (delete: it injects `DeployInProgressError` at
   `safe-commit-pr`, where nothing produces one, and it goes red once the inner check is gone; S1
   over `ROWS` replaces it), refresh the stale `DeployInProgressError` comment near the top of
   `cron-community-monitor-dedup.test.ts`, and
   `cron-producer-output-wiring.test.ts` (Guard 2).

### Phase 3 — Drift guard (GREEN)

1. `drift-check` returns `{ result, leakDetected }`, scans its result with
   `assertNoLeak("drift-result", …)` before returning, and rethrows other errors as
   `redactedError(err)`; `issue-handling` / `notify-ops-email` return `{ leakDetected }` from a
   callback-local variable (the 403 report reads the local); every leak arm reports
   `op: "leak-tripwire"`; fold all three into the handler; keep `op: "notify-ops-email"` verbatim.
2. In `cron-github-app-drift-guard.test.ts`, move the leak scenarios onto the harness (S5b replaces
   the old "leak tripwire fires" setup; add S6, S6b, S7 with a seeded `drift-check` memo); keep the
   in-process `makeStep` for the rest of that file.

### Phase 4 — Docs and verification

1. ADR-078 amendment; ADR-126 residual 1 reworded in place; principles-register AP-028 (see
   Architecture Decision). AP-028 is provisional: re-check the next free AP number against
   `origin/main` before merge.
2. Read the live alert-workflow binding of the 10 cron monitors (read-only Sentry API, token from
   Doppler) and record in the PR which of them page anyone; if some do not, say so in the PR body
   and comment on #8764 rather than widening this PR.
3. The AC10 `vitest run` and `tsc --noEmit` commands, then `bash plugins/soleur/test/c4-count-parity.test.sh`.

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts`
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts`
- `apps/web-platform/server/inngest/functions/cron-architecture-diagram-sync.ts`
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts`
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts`
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`
- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`
- `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts`
- `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts`
- `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts`
- `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-078-graceful-cron-drain-before-container-swap.md`
- `knowledge-base/engineering/architecture/decisions/ADR-126-cron-liveness-must-assert-the-consumed-artifact.md`
- `knowledge-base/engineering/architecture/principles-register.md`

`_cron-claude-eval-substrate.ts` is **not** edited: `setupEphemeralWorkspace` keeps throwing, so its
8 other callers (#8762) and `test/server/cron-drain-lease.test.ts` are unaffected.

## Files to Create

- `apps/web-platform/test/helpers/inngest-step-harness.ts`
- `apps/web-platform/test/helpers/inngest-step-harness.test.ts`

## Open Code-Review Overlap

Checked the 17 planned paths against 78 open `code-review` issues. The only match is **#8726** itself
(this plan closes it). No other overlap.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Match on `err.message` (a shared marker constant) in the handler catch | Keeps retry semantics with a 9-line diff, but routes a decision on a string across the boundary; a message edit re-breaks it silently, and the drift guard would need the same trick. The #8717 learning's Key Insight rejects it. |
| Use `@inngest/test` (`InngestTestEngine`) instead of a bespoke harness | Not installed (`apps/web-platform/package.json` has no `@inngest/*` test package); adds a devDependency and lockfile churn. The retry and attempt policy lives in the Inngest **server**, which neither it nor a bespoke harness contains, so the executor model would still be ours to write. The bespoke harness delegates the part that matters (error serialization) to the real SDK, which `package.json` pins exactly (`"inngest": "3.54.2"`). |
| Return `{ deferred }` from the step on every attempt (advisor consult's simplification) | Memoization means the step never re-runs, so the lease is never re-checked: every deferral becomes an immediate skip (drops P2). The consult argued the retry buys little against a lease that can last ~80 min; that is true for a deploy that drains a long cron and unmeasured for the common short swap. Keeping the retry is the ADR-078 contract ("`retries: 1` re-dispatches the run; the retry normally lands after the bounded deploy completes"), the attempt predicate is the one `finalizeOutputAwareHeartbeat` and `middleware/run-log.ts` already use, and the harness must model final-vs-non-final step failures anyway (S1's RED run and S3 need them). The substrate's `op: "deploy-lease-fresh"` events carry the lease age per attempt, which is the data that would justify dropping the retry later. |
| Change `setupEphemeralWorkspace` to return a union | 17 callers, 8 of which have no deferral arm and no `attempt` plumbing; widens this fix into #8762. |
| On the final-attempt deferral, return `{ ok: false }` instead of throwing | Changes the ADR-078 contract (a `failed` `routine_runs` row with no Sentry event instead of the documented thrown deferral). A separate decision; this plan restores the documented behaviour the suites already assert. |
| `NonRetriableError` for the handler-body throw | Saves one memoized re-entry and one of the two Sentry events, but renames the event to `NonRetriableError`, losing the queryable class name. Worth revisiting with DC-1. |

## Non-Goals

- The 8 `setupEphemeralWorkspace` callers with no deferral arm — **#8762**.
- Out-of-step side effects that repeat on re-entry (e.g. `reportSilentFallback` in each
  setup-failure catch runs again on the request that follows the heartbeat step). Pre-existing, a
  duplicate Sentry event rather than a wrong verdict; not changed here.
- Migrating `makeRetryingStep` in the leader-loop suite to the shared harness.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: these are internal scheduled
  jobs. The operator sees either the same false "setup failed" alerts as today, or (worse) a genuine
  setup failure hidden behind the deferral arm, or a drift-guard leak routed to the wrong label.
  S3 and Guard 2 exist to catch the second; S5 the third.
- **If this leaks, the user's data is exposed via:** the drift guard protects the GitHub App private
  key, which can act on every installation. This plan does not change what `assertNoLeak` blocks; it
  changes where the verdict is routed afterwards. The returned leak verdict is a boolean, never the
  matched text or the error message, because step outputs persist in Inngest run state.
- **Brand-survival threshold:** `aggregate pattern`

`threshold: aggregate pattern` rather than `single-user incident`: the change touches
`apps/web-platform/server/` (sensitive path) but no emission site's blocking behaviour, and the
failure modes are mislabelled operator alerts, not user data movement.

## Observability

```yaml
liveness_signal:
  what: "Existing Sentry cron monitor per cron (postSentryHeartbeat via finalizeOutputAwareHeartbeat) and the drift guard's scheduled-github-app-drift-guard monitor; the deferral arm deliberately posts no check-in (ADR-078)"
  cadence: "per scheduled fire (weekly / twice-monthly per claude-eval cron; drift guard hourly)"
  alert_target: "Sentry cron-monitor issue. Measured 2026-09-24 (read-only Sentry API): all 10 monitors are bound to workflow 1297055 `cron-monitor-failure` (enabled; email to issue owners, fallthrough ActiveMembers), so a failed or missed check-in emails the team. The binding is not in Terraform; this plan does not change it."
  configured_in: "apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat), apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN)"
  fail_loud: "Every deferral attempt: reportSilentFallback feature=cron-claude-eval op=deploy-lease-fresh (layer 2, pino + Sentry). Deferral that outlasts the retry: two Sentry events named DeployInProgressError from middleware/sentry-correlation.ts transformOutput (layer 1; one per handler-level attempt; a live throw, so the name now survives), then a missed check-in. Drift-guard leak in any step: reportSilentFallback op=leak-tripwire with extra.step (new), plus a ?status=error check-in."

failure_modes:
  - mode: "A deploy outlasts the step retry"
    detection: "layer 2: op=deploy-lease-fresh on both attempts; layer 1: two DeployInProgressError events from sentry-correlation; no op=setup-ephemeral-workspace report"
    alert_route: "Sentry issue stream, plus the cron monitor's MISSED check-in: all 9 monitors have checkin_margin_minutes = 60 and failure_issue_threshold = 1 (apps/web-platform/infra/sentry/cron-monitors.tf), so a skipped fire opens a missed-check-in issue about an hour later. True (the job did not run) and the documented ADR-078 outcome; see decision-challenges DC-1."
  - mode: "A genuine setup failure on the final attempt"
    detection: "layer 2: reportSilentFallback op=setup-ephemeral-workspace; Sentry monitor: ?status=error check-in (both unchanged)"
    alert_route: "Sentry cron-monitor issue (routing as in alert_target)"
  - mode: "Leak tripwire in drift-check"
    detection: "layer 2 (pino -> Sentry mirror, reportSilentFallback(null) message path, tags feature/op=leak-tripwire, extra.step=drift-check); Sentry monitor ?status=error check-in (scheduled-github-app-drift-guard -> workflow 1297055); [security/leak-suspected] issue filed by issue-handling; return failureMode leak_tripwire_fired"
    alert_route: "GitHub issue labelled security/leak-suspected + priority/p1-high; no sentry_alert rule pages on op=leak-tripwire (stated, not added)"
  - mode: "Leak tripwire in issue-handling (issue body or comment)"
    detection: "layer 2 (pino -> Sentry mirror, op=leak-tripwire extra.step=issue-handling); Sentry monitor ?status=error check-in (workflow 1297055); the same step files the [security/leak-suspected] issue; the leak email variant follows"
    alert_route: "GitHub issue + ops email; no sentry_alert rule pages on op=leak-tripwire"
  - mode: "Leak tripwire in notify-ops-email (Resend body, subject or error body)"
    detection: "layer 2 (pino -> Sentry mirror, op=leak-tripwire extra.step=notify-ops-email); Sentry monitor ?status=error check-in (workflow 1297055); no email is sent and no leak issue is filed (issue-handling already ran); return leakDetected true"
    alert_route: "Sentry issue stream only (op=leak-tripwire) plus the cron-monitor error check-in; no sentry_alert rule pages on it"

logs:
  where: "pino logger via the Inngest bound-logger middleware, shipped to Better Stack"
  retention: "Better Stack plan retention"

discoverability_test:
  command: "rg -c -F 'unwrapSetupVerdict(verdict' apps/web-platform/server/inngest/functions/"
  expected_output: "cron-growth-audit.ts:1"
```

The regression guard for this defect class (Guard 2 and the harness scenarios, red in CI) is in
`## Guard Contract`, not listed here as a runtime failure mode.

## Guard Contract

### Guard 1 — Inngest step-boundary harness

**Property.** A handler driven by `runLikeInngest` observes the three things production observes at
a step boundary that an in-process mock hides: a step-crossing error arrives as the SDK's rebuilt
`StepError` (no custom class, `name === "Error"`), a non-final step failure is never visible to
handler code, and a variable assigned inside a step callback does not survive to the next step.

**Assembly.** One chokepoint: `runLikeInngest` in `test/helpers/inngest-step-harness.ts`, whose
error rebuild delegates to the real `serializeError` and `StepError` from `inngest` (pinned exactly
at `3.54.2` in `apps/web-platform/package.json`, so a serializer change arrives only through a
deliberate bump and the rebuild follows it). Every step-boundary scenario in this plan (S1–S3,
S5–S7, S6b) goes through it; suites that do not cross a boundary keep their in-process mocks (their
migration is #8764). Anchor: the self-test compares against `new StepError(...)` from the SDK,
never against the harness's own output.

**Mutation matrix** (each row is an assertion in `inngest-step-harness.test.ts`, not a hand-run):

| # | Mutation | Expected |
|---|---|---|
| 1 | Harness re-throws the raw error on the final attempt instead of `rebuildAsStepError` | RED (self-test asserts fixed facts, not a comparison with the harness's own rebuild: the caught error has `name === "Error"`, is not `instanceof DeployInProgressError`, has no `leaseAgeMs`, and keeps the original `message`) |
| 2 | Harness surfaces a non-final step failure to the handler (rejects instead of never settling) | RED (self-test: the probe handler's `catch` records an error on attempt 0) |
| 3 | Harness stops re-entering the handler after a successful step | RED (self-test: a flag assigned inside step A's callback is still `true` when step B runs) |
| 4 | Harness dispatch: `runLikeInngest` returns after the first invocation | RED (self-test: a two-step probe handler's second step never ran) |
| 5 | Harness memoizes `undefined` by bare `JSON.stringify` (drops `?? null`) | RED (self-test: a step returning nothing crashes with a `SyntaxError` instead of memoizing `null`) |
| 6 | Duplicate-step-ID or invocation-cap check removed, or counted across invocations | RED (self-test: a handler calling `step.run("a")` twice in one invocation throws `HarnessError`; a two-step handler replayed normally does not; a handler that never returns hits the cap with `HarnessError`) |

**Harness rows.**

- Negative control, kept as a permanent test (not a manual edit): the same probe handler driven by
  a naive inline driver (the `makeStep` shape used in `cron-cohort-dedup.test.ts`) is asserted to
  MISS what `runLikeInngest` sees (the caught error IS `instanceof DeployInProgressError`; the
  in-step flag survives). This shows the old mock is blind and the harness is not.
- Suite edit that must go RED: S1, S5 and S5b run against the pre-fix handler source (AC3 / AC6
  record this RED run; each entry names the first failing assertion and shows it is not a
  `HarnessError`).
- Must-PASS input that is not the canonical: a probe handler whose first step fails once and then
  succeeds, and whose second step is exhausted, produces exactly one rebuilt `StepError`, for the
  second step, and the first step's value is memoized.

### Guard 2 — Step-boundary `DeployInProgressError` census

**Property.** No file under `server/inngest/functions/` refers to `DeployInProgressError` in code
except its producer (`_cron-claude-eval-substrate.ts`) and `_cron-shared.ts` (the class and the
live check inside the setup step). After the fix the 9 crons use only the helpers, so any
reference elsewhere (an `instanceof`, a `.name === "DeployInProgressError"`, or sniffing the
rebuilt `StepError`'s `message`/`stack`, which still begin with the class name) is a
step-boundary check reintroduced.

**Assembly.** A directory walk over every `.ts` file in `server/inngest/functions/` (not a list of
the 9 crons), replacing the `toContain("instanceof DeployInProgressError")` assertion in
`cron-producer-output-wiring.test.ts`. The walk covers the 8 callers in #8762 as well. That each
of the 9 crons still routes through the helper is carried by `tsc` (an un-narrowed
`WorkspaceSetupVerdict` has no `workspace`) and by S1, which runs all 9; a source scan adds nothing
there.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `if (err instanceof DeployInProgressError) throw err;` in any one of the 9 crons | RED |
| 1b | Add `if (/DeployInProgressError/.test(String((err as Error).stack))) throw err;` in any one cron | RED (token census, not an `instanceof` pattern) |
| 2 | Guard dispatch: the walk resolves zero files (wrong directory or glob) | RED (floor: the walk must see at least the 9 cron files plus `_cron-shared.ts`, asserted by name) |
| 3 | A second file adds the check after a first compliant one (e.g. `cron-legal-audit.ts`, one of #8762's callers) | RED (the walk does not stop at the first file) |
| 4 | Move `throwIfDeployDeferred(` inside the setup `catch` block (reorder) | RED via S1, not via this scan: a source scan cannot see order |

**Harness rows.** Must-PASS: `_cron-shared.ts` and `_cron-claude-eval-substrate.ts` pass; a comment mentioning `instanceof DeployInProgressError` in a
cron file is NOT a false positive (strip comments before scanning, using
`test/helpers/strip-comments.ts`).

## Architecture Decision (ADR/C4)

Not a new architectural decision: the deferral mechanism, its trigger and its outcome stay as ADR-078
records them; the change is how the verdict crosses the step boundary. Two ADR texts become false or
stale and are corrected in this PR, and the pattern, now used three times, gets a principles-register
row.

### ADR

- **ADR-078 — amend** (a dated `## Amendment 2026-09-24 (#8726)` section; one paragraph plus a short
  list):
  - the substrate still throws `DeployInProgressError`; the 9 deferral-aware crons wrap the setup
    step so a non-final attempt throws (Inngest's per-step retry re-checks the lease) and the final
    attempt returns a `deploy-deferred` verdict, which the handler re-materializes as
    `DeployInProgressError` after the setup catch and before the body's try/finally;
  - correct the sentence "`retries: 1` re-dispatches the run; the retry normally lands after the
    bounded deploy completes": it is a **step** retry on Inngest's default backoff, and that backoff
    has not been measured against the lease lifetime (DC-2);
  - state what a deferral that outlasts the retry now visibly produces, since the ADR calls a skip
    "benign": two `DeployInProgressError` Sentry events, a `failed` `routine_runs` row, and a missed
    check-in about 60 minutes later (DC-1);
  - record the handler-level retry after the verdict as an accepted cost: it replays the memoized
    verdict and cannot re-check the lease, the same "a replay cannot recover" shape as ADR-126
    decision 6, acceptable here because no workspace exists yet;
  - cite the ADR-042 amendment of 2026-09-24 (the leader loop's returned `turn_rejection`) as the
    precedent, and list the rejected alternatives one line each (message marker; return on every
    attempt; `NonRetriableError`).
- **ADR-126 — amend in place, no renumbering** (the same section later refers to "Residual 4"):
  - Named residual 1 ("`DeployInProgressError` mid-spawn") names an error with no producer inside
    the guarded body, and a step-crossing one could not have matched `instanceof` anyway. Reword it
    to the hazard it was reaching for: a deploy's drain **timeout** kills an in-flight `claude`
    (`op=cron-drain-timeout`, ADR-078), after which Inngest retries the step against a workspace the
    handler's `finally` already deleted. Mark the `DeployInProgressError` wording resolved by #8726.
  - Accepted negative 2's closing "`DeployInProgressError` still rethrows bare" becomes "a deploy
    deferral exits before the guarded body (see ADR-078 amendment 2026-09-24)".
- **Principles register — add AP-028**
  (`knowledge-base/engineering/architecture/principles-register.md`): "A verdict that crosses an
  Inngest step boundary is returned from the step, never read from a caught error's class, `name`
  or `status`." Canonical source: ADR-042 amendment 2026-09-24 and ADR-078 amendment 2026-09-24.
  Enforcement: advisory (Guard 2 enforces it for `DeployInProgressError` only; #8764 tracks a
  general census).

### C4 views

No C4 impact. Enumerated against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
external actors (none added or changed: the operator and GitHub are unchanged), external systems
(Inngest Server, Sentry, GitHub, Resend — all already modeled, no new edge), containers/data stores
(none touched; step state already lives in the modeled Inngest Server/Redis), access relationships
(none change). The only drift-guard mention in `model.c4` is audit-row prose on the `api -> supabase`
edge, which this change does not touch (architecture seat, deepen-plan). No cron or monitor is added
or removed, so no cardinality in `model.c4` edge prose moves; verified by running
`plugins/soleur/test/c4-count-parity.test.sh` green in Phase 4.

## Acceptance Criteria

- [x] AC1 — Guard 2's census passes: with comments stripped (`test/helpers/strip-comments.ts`), the only files under `apps/web-platform/server/inngest/functions/` whose code contains the token `DeployInProgressError` are `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`. Comments may still name the class.
- [x] AC2 — Each of the 9 cron files contains `deferDeployOnFinalAttempt(` inside the `"setup-workspace"` step and `throwIfDeployDeferred(` after the setup try/catch (carried by `tsc` and S1 over all 9; Guard 2 carries the negative half).
- [x] AC3 — S1 passes for all 9 crons under `runLikeInngest` and fails on `origin/main` code (recorded in the PR body as the RED run).
- [x] AC4 — S2: a lease present on attempt 0 and absent on attempt 1 reaches the spawn (retry preserved).
- [x] AC5 — S3: a non-deferral setup error on the final attempt still produces `op: "setup-ephemeral-workspace"` and a `?status=error` check-in.
- [x] AC6 — Drift guard: S5, S5b, S6, S6b, S7 pass under `runLikeInngest`; S5 and S5b fail on `origin/main` code (recorded in the PR body); deleting either fold (S6, S7) turns its scenario RED. No `step.run` callback in `cron-github-app-drift-guard.ts` assigns a handler-scope variable; a text grep cannot scope a match to a callback, so this is carried by S6/S7 (the re-entering harness is what makes such an assignment observable), and the reviewer checks the three callbacks by reading them.
- [x] AC7 — In S5 and S5b, no memoized step output contains any substring of the injected synthetic secret (read from the caller-owned memo; memoized failures are scanned after `serializeError`, because `JSON.stringify` of an `Error` is `"{}"` and would pass vacuously); `drift-check`'s output has exactly the keys `result` and `leakDetected`.
- [x] AC8 — `test/helpers/inngest-step-harness.test.ts` passes and contains one assertion per Guard 1 mutation-matrix row (rows 1–6), the must-PASS row and the permanent negative control, each asserting fixed facts (not a comparison with the harness's own rebuild).
- [x] AC9 — ADR-078 `## Amendment 2026-09-24 (#8726)` present with the four points listed under Architecture Decision; ADR-126 residual 1 reworded in place (residual numbering unchanged, so "Residual 4" still resolves); principles-register row for the step-boundary rule present at the next free AP number; `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [x] AC10 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `cd apps/web-platform && ./node_modules/.bin/vitest run test/helpers/inngest-step-harness.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-producer-output-wiring.test.ts test/server/inngest/cron-github-app-drift-guard.test.ts test/server/cron-drain-lease.test.ts test/sentry-ops-email-delivery-alert-op-contract.test.ts` green. (The package runner is vitest; `bun test` is blocked by `apps/web-platform/bunfig.toml`, and `npm run -w` fails for lack of a root `workspaces` field.)
- [x] AC11 — Drift guard: every leak arm emits `op: "leak-tripwire"` (S5, S5b, S6, S7 assert it with the matching `extra.step`), and `test/sentry-ops-email-delivery-alert-op-contract.test.ts` is green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (internal cron error routing;
no user-facing surface, content, pricing, legal document or vendor change).

## Test Scenarios

All step-boundary scenarios run under `runLikeInngest({ maxAttempts: 2 })` (the crons' `retries: 1`).
Spies called inside a step (the substrate, the heartbeat `fetch`, reports inside a step callback)
are deterministic and may use exact counts; spies called outside any step run again on every
re-entry, so assert presence or absence only. Filter `fetch` calls by URL: the heartbeat and the
Resend POST both go through it.

- **S1 (P1, fleet).** `it.each(ROWS)` over the 8 `ROWS` crons in `cron-cohort-dedup`, plus one case
  in `cron-community-monitor-heartbeat` (per-cron cases, so counts reset and a failure names the
  cron). Given the substrate throws `DeployInProgressError` on every call, then, asserted in this
  order: outcome is `threw` (on `origin/main` code it is `returned { ok: false }`, which is the RED
  reason); the error is `instanceof DeployInProgressError`; the substrate was called exactly twice
  (the retry happened, and the run got past the dedup early-return, which also posts a heartbeat);
  no heartbeat `fetch`; no `reportSilentFallback` with `op: "setup-ephemeral-workspace"`.
- **S2 (P2).** Given the substrate throws `DeployInProgressError` on its first call and returns a
  workspace on its second, then the spawn runs and the run returns normally.
- **S3 (P3).** Given the substrate throws a plain `Error("git clone failed")` on every call, then
  `op: "setup-ephemeral-workspace"` is reported and the check-in is `?status=error`; outcome
  `returned` with `{ ok: false }`; and no memoized step output contains the installation token.
- **S4 (predicate).** Unit tests of `isFinalAttempt` and `deferDeployOnFinalAttempt`: with
  `maxAttempts` undefined the deferral returns on attempt 0 (the documented divergence from the
  SDK, which would retry); with `attempt: 0, maxAttempts: 2` it rethrows the same error object; a
  non-`DeployInProgressError` on the final attempt is rethrown; `finalizeOutputAwareHeartbeat`'s
  existing suites stay green on the extracted predicate.
- **S5 (P4, `drift-check`, live `LeakDetectedError`).** Given the mocked suppression file
  (`readFileSpy` for the `MANIFEST_DRIFT_SUPPRESS_UNTIL` path) holds a JWT-shaped string built at
  runtime (`"eyJ" + "A".repeat(24)`, as the existing test near the `assertNoLeak` cases does; never
  a committed three-part JWT literal), so `readSuppression` puts it in `warning`. A PEM header does
  NOT work here: `readSuppression` strips all whitespace before building the warning and the PEM
  regex needs the spaces in `BEGIN RSA PRIVATE KEY`. Then: a `[security/leak-suspected]` issue is
  filed; no `github_api_network` / `ci/guard-broken` failure issue; `op: "probeDriftGuard"` never
  reported; `op: "leak-tripwire"` with `extra.step: "drift-check"` reported;
  `out.leakDetected === true`; `out.failureMode === "leak_tripwire_fired"`; heartbeat `?status=error`.
  RED on `origin/main` code.
- **S5b (P4, `drift-check`, secret in upstream error text).** The existing "leak tripwire fires"
  setup (a PEM in the `GET /app` error): after the fix the `drift-result` scan trips inside
  `drift-check`, so the same outcomes as S5 hold, and the memoized `drift-check` output contains no
  PEM (AC7). RED on `origin/main` code (there the leak trips later, at `issue-body`, and the flag is
  lost on re-entry, so `out.leakDetected` is `false`).
- **S6 (P4, `issue-handling` fold).** After the fix no probe result can carry a secret past
  `drift-check`, so the `issue-handling` and `notify-ops-email` leak arms are defence in depth and
  are reached by **seeding** the harness memo with an unscanned `drift-check` output
  (`{ result: <failure whose failureDetail holds a PEM>, leakDetected: false }`), which is exactly
  the state Inngest hands a re-entered handler. Then `issue-body` trips inside `issue-handling`:
  the leak issue is filed, the ops email is the leak variant, `op: "leak-tripwire"` with
  `extra.step: "issue-handling"` is reported, and `out.leakDetected === true`. Deleting the fold of
  `issue-handling`'s returned value must turn this RED.
- **S6b (P4, leak then failed leak-issue write).** As S6, plus `handleLeakIssue`'s
  `POST /repos/{owner}/{repo}/issues` rejects with a 403: `out.leakDetected === true` (the callback
  returns its local flag after the outer catch swallows the 403), and `op: "issue_write_403"` is
  reported with `extra.leakDetected: true`.
- **S7 (P4, `notify-ops-email` fold).** Seed the memo as in S6, and make `issue-handling` fail for a
  non-leak reason (`createProbeOctokit` rejects), so the only leak is the one
  `assertNoLeak("resend-body")` raises inside `notify-ops-email`. Positive anchors first: the
  `notify-ops-email` step ran, `createProbeOctokit` was called, `op: "handleIssue"` was reported
  (inside a step, so an exact count is fine). Then: no Resend POST (filtered by URL),
  `op: "leak-tripwire"` with `extra.step: "notify-ops-email"`, and `out.leakDetected === true`.
  Deleting the `notify-ops-email` fold must turn this RED.
- **S8 (P5, harness self-test).** Guard 1 rows 1–6 as assertions on fixed facts, the must-PASS row,
  and the permanent negative control.
- **Regression.** `test/server/cron-drain-lease.test.ts` unchanged and green (the substrate still
  throws); `test/sentry-ops-email-delivery-alert-op-contract.test.ts` green (the
  `notify-ops-email` op literal is kept).

## Risks

- **The harness diverges from a future SDK's execution model** (e.g. checkpointing enabled later
  runs several steps per request). Mitigation: the harness self-test states the async-mode
  assumption and cites `server/inngest/client.ts`; enabling checkpointing is a client change a
  reviewer would see next to this helper.
- **Suites that fully mock `_cron-shared`** would lose the real helper. Mitigation: the two suites
  that drive the 9 crons use partial `importOriginal` mocks (verified); the implementer greps for any
  full-factory `_cron-shared` mock that imports one of the 9 handlers.
- **Re-entry changes call counts** of out-of-step spies. Mitigation: harness scenarios assert
  presence/absence, not counts, for anything outside `step.run`.
- **Unverified server-side detail: the attempt number after a step succeeds.** The SDK source shows
  how a request *uses* `attempt`; what the Inngest server sends for the request after a successful
  step is not in the SDK. The harness resets it to 0. No scenario's assertion depends on it: after
  the deferred verdict is memoized, the handler throws either at a non-final attempt (one more
  replay, then final) or at the final attempt directly, and both end in outcome `threw` with no
  heartbeat.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled here; keep it filled through review.
- `throwIfDeployDeferred` must sit **after** the setup `try/catch`, never inside it: inside, the live
  throw is caught by the setup-failure arm (Guard 2 row 4 is carried by S1, not by the source scan).
  Do not "simplify" it back into the try because the error is live there now: a live `instanceof`
  in the catch would work, but a later reorder lets the setup-failure arm swallow the deferral.
- Do not put the matched secret, or `err.message` of a `LeakDetectedError`, into any step return
  value: step outputs are persisted by Inngest.
- Import `StepError` and `serializeError` from `"inngest"`, not `"inngest/helpers/errors"` (not an
  exported subpath).
- `throwIfDeployDeferred` must also run **before** the body's `try { … } finally { teardownEphemeralWorkspace }`.
  All 9 crons have that shape today; moving the deferral inside the teardown scope would run a
  teardown for a workspace that was never created.
- Keep the literal `op: "notify-ops-email"` in the drift guard: a `sentry_alert` in
  `apps/web-platform/infra/sentry/issue-alerts.tf` filters on it and
  `test/sentry-ops-email-delivery-alert-op-contract.test.ts` pins it.
- The harness memoizes `v ?? null`, never a bare `JSON.stringify(v)`: `sentry-heartbeat`,
  `issue-handling` and `notify-ops-email` return nothing today.
- Build JWT-shaped fixtures at runtime (`"eyJ" + "A".repeat(24)`); never commit a three-part JWT
  literal (GitHub push protection and the repo's `lint-fixture-content` hook).
