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
| "18 `DeployInProgressError` sites" | 9 files x 2 sites. The first (setup-workspace catch) is the broken one. The second (inner body catch) is **unreachable**: the only producer is `setupEphemeralWorkspace` (`_cron-claude-eval-substrate.ts`, the `throw new DeployInProgressError` after `deployLeaseAgeMsIfFresh`), which no inner body calls. | Remove the inner-body checks; dissolve ADR-126 "Named residual 1", which describes an error with no producer. |
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
export type EphemeralWorkspace = { ephemeralRoot: string; spawnCwd: string };

export type WorkspaceSetupVerdict =
  | { kind: "ready"; workspace: EphemeralWorkspace }
  | { kind: "deploy-deferred"; leaseAgeMs: number };

/**
 * Run INSIDE step.run("setup-workspace"). The error is live here, so instanceof is valid.
 * Final-attempt predicate mirrors finalizeOutputAwareHeartbeat (same file).
 */
export async function deferDeployOnFinalAttempt(
  setup: () => Promise<EphemeralWorkspace>,
  ctx: { attempt: number | undefined; maxAttempts: number | undefined }, // keys required: see below
): Promise<WorkspaceSetupVerdict>;
// non-final attempt + DeployInProgressError -> rethrow (Inngest retries the step, re-checking the lease)
// final attempt     + DeployInProgressError -> return { kind: "deploy-deferred", leaseAgeMs }
// any other error                            -> rethrow unchanged
// success                                    -> { kind: "ready", workspace }

/** Call in the handler body, AFTER the setup-workspace try/catch has closed. */
export function throwIfDeployDeferred(
  v: WorkspaceSetupVerdict,
  cronName: string,
): asserts v is { kind: "ready"; workspace: EphemeralWorkspace };
```

The `ctx` keys are required (their values may be `undefined`), so a future caller that has not
plumbed `attempt` / `maxAttempts` fails `tsc` instead of silently losing the retry (#8762's 8
callers pass neither today). `HandlerArgs.attempt` is `number | undefined`, so the 9 crons pass
`{ attempt, maxAttempts }` unchanged.

Each cron's setup block becomes (growth-audit shown; the other 8 are the same shape):

```ts
let verdict: WorkspaceSetupVerdict;
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

Why this final-attempt predicate: it is `finalizeOutputAwareHeartbeat`'s `(attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`
(same file). When `maxAttempts` is present it agrees with the SDK's own choice between a retriable
`StepError` and a terminal `StepFailed` (`maxAttempts - 1 === attempt`, `v2.js`), so "throw" happens
exactly when a throw buys a retry. They diverge only when `maxAttempts` is absent: the SDK then
treats the step as retriable, this predicate treats it as final (see Fail-safe default; S4 pins it).
The same `if (!isFinalAttempt) throw err` shape already exists in `cron-anthropic-cost-report.ts`.

### Drift guard

- `LeakDetectedError` is unchanged. Nothing downstream reads which call site tripped
  (`handleLeakIssue({ octokit, detectedAtIso, runUrl })` takes no label), so the verdicts carry a
  boolean only.
- All three steps return the same shape:
  - `drift-check` → `{ result: DriftResult; leakDetected: boolean }`. Its callback catches a live
    `LeakDetectedError` and returns `{ result: EMPTY_RESULT, leakDetected: true }`; anything else
    still throws. The outer catch keeps the `github_api_network` conversion and loses its dead
    `instanceof` branch.
  - `issue-handling` → `{ leakDetected: boolean }`. The callback holds a local `let leak = false`,
    sets it in the inner `catch (innerErr)` arm, and returns `{ leakDetected: leak }` **after** its
    outer try/catch, so a leak followed by a failing `handleLeakIssue` (for example a 403 on the
    issue write, which the outer catch reports and swallows) still returns `true`.
  - `notify-ops-email` → `{ leakDetected: boolean }`, same local-variable shape.
- The handler folds each returned value into its own `leakDetected`. No step callback assigns a
  handler-scope variable.

### Test harness

New `apps/web-platform/test/helpers/inngest-step-harness.ts`, built on the real SDK. It models what
the scenarios need and nothing more:

- `rebuildAsStepError(stepId, err)` → `new StepError(stepId, JSON.parse(JSON.stringify(serializeError(err))))`,
  both imported from `"inngest"`.
- `runLikeInngest(invoke, { maxAttempts })` drives a handler the way async-mode Inngest does:
  - one memo map shared across invocations (the caller may pass its own `Map` to read step outputs,
    which AC7 does); step outputs are JSON round-tripped when memoized;
  - on the first un-memoized step in an invocation: run it; success → memoize, end the invocation,
    re-enter; throw on a non-final attempt → end the invocation, re-enter with `attempt + 1`; throw
    on the final attempt → memoize `rebuildAsStepError(...)`, end, re-enter;
  - a memoized failure makes `step.run` reject with the stored `StepError`;
  - "end the invocation" = `step.run` returns a never-settling promise and the driver races it, so
    the handler's own `catch` cannot observe an interruption (as in production);
  - a handler-body throw ends the run (outcome `threw`); a handler return ends it (outcome
    `returned`);
  - a hard cap on invocations, so a loop fails the test instead of hanging;
  - a step ID seen twice in one run fails loudly (the SDK would suffix it as `id:1`; replaying the
    first result silently would hide the bug);
  - returns `{ outcome: "returned" | "threw", value?, error? }`.
- The docstring states the one guessed behaviour: `attempt` after a successful step is reset to 0
  (the SDK shows how a request uses `attempt`, not what the server sends next). No scenario's
  assertion depends on it.

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
- **Leak verdict content.** The verdicts carry a boolean only. They must never carry the matched
  fragment or a `LeakDetectedError` message: a step's return value is persisted in Inngest run state
  and shown in the Inngest dashboard. This narrows today's exposure, where the thrown error's message
  (with a 16-char prefix of the match) is serialized into step-error state.
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
| `issue-body`, `issue-comment` (in `handleFailureIssue`) | `issue-handling` | live catch files leak issue; `leakDetected` lost on re-entry | returned `{ leakDetected: true }` |
| `resend-body`, `resend-subject`, `resend-error-body` (in `notifyOpsEmail`) | `notify-ops-email` | `leakDetected` lost on re-entry | returned `{ leakDetected: true }` |

No other `assertNoLeak` call exists (`grep -n "assertNoLeak(" cron-github-app-drift-guard.ts`).

## Implementation Phases

### Phase 1 — Harness first (RED)

1. Write `test/helpers/inngest-step-harness.ts` and `test/helpers/inngest-step-harness.test.ts`
   (harness self-test: see Guard 1).
2. Add the failing scenarios (Test Scenarios S1, S2, S3, S5, S6, S6b, S7) using the harness. Confirm S1,
   S5, S6, S7 fail on the current code for the stated reason (setup-failure arm reached; leak routed
   as `github_api_network`; `leakDetected` false).

### Phase 2 — Deploy deferral (GREEN)

1. `_cron-shared.ts`: add `WorkspaceSetupVerdict`, `deferDeployOnFinalAttempt`,
   `throwIfDeployDeferred`; update the `DeployInProgressError` doc comment and the
   `finalizeOutputAwareHeartbeat` comment ("excluded by the caller BEFORE…") to name the helper.
2. The 9 crons: wrap the setup step, delete both `instanceof DeployInProgressError` lines, add
   `throwIfDeployDeferred` after the setup try/catch, rewrite the "#5728 G1" comments to state the
   real mechanism. Update the "DeployInProgressError still rethrows bare" `retryEligible` comment.
3. Update `cron-community-monitor-heartbeat.test.ts` (delete the inner-body scenario, which injects
   an error with no production producer; move the setup-workspace scenario onto the harness),
   `cron-cohort-dedup.test.ts` scenario 11 (delete: it injects `DeployInProgressError` at
   `safe-commit-pr`, where nothing produces one, and it goes red once the inner check is gone; S1
   over `ROWS` replaces it), refresh the stale `DeployInProgressError` comment near the top of
   `cron-community-monitor-dedup.test.ts`, and
   `cron-producer-output-wiring.test.ts` (Guard 2).

### Phase 3 — Drift guard (GREEN)

1. `drift-check` returns `{ result, leakDetected }`; `issue-handling` / `notify-ops-email` return
   `{ leakDetected }` from a callback-local variable; fold all three into the handler.
2. Move the three leak scenarios (and add S6b) in `cron-github-app-drift-guard.test.ts` onto the harness; keep the
   in-process `makeStep` for the rest of that file.

### Phase 4 — Docs and verification

1. ADR-078 amendment; ADR-126 residual 1 dissolved (see Architecture Decision).
2. The AC10 `vitest run` and `tsc --noEmit` commands, then `bash plugins/soleur/test/c4-count-parity.test.sh`.

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
  cadence: "per scheduled fire (daily/weekly per cron; drift guard hourly)"
  alert_target: "Sentry cron monitor alerts to the operator email"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat), apps/web-platform/infra sentry cron monitor resources"

error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN)"
  fail_loud: "Every deferral attempt: reportSilentFallback feature=cron-claude-eval op=deploy-lease-fresh. Deferral that outlasts the retry: two Sentry events named DeployInProgressError from middleware/sentry-correlation.ts (one per handler-level attempt; a live throw, so the name now survives), then a missed check-in on the cron monitor. Drift-guard leak: [security/leak-suspected] GitHub issue + ?status=error heartbeat."

failure_modes:
  - mode: "A deploy outlasts the step retry"
    detection: "op=deploy-lease-fresh reports on both attempts, then two DeployInProgressError Sentry events (one per handler-level attempt); no op=setup-ephemeral-workspace report"
    alert_route: "Sentry issue stream, plus the cron monitor's MISSED check-in: every one of the 9 monitors has checkin_margin_minutes = 60 and failure_issue_threshold = 1 (apps/web-platform/infra/sentry/cron-monitors.tf), so a skipped fire opens a missed-check-in issue about an hour later. That is true (the job did not run) and is the documented ADR-078 outcome; see decision-challenges DC-1."
  - mode: "A genuine setup failure on the final attempt"
    detection: "reportSilentFallback op=setup-ephemeral-workspace + ?status=error check-in (unchanged)"
    alert_route: "Sentry cron monitor alert"
  - mode: "Leak tripwire inside drift-check / issue-handling / notify-ops-email"
    detection: "[security/leak-suspected] issue filed; heartbeat ?status=error; return failureMode leak_tripwire_fired"
    alert_route: "GitHub issue labelled security/leak-suspected + priority/p1-high, Sentry monitor alert"
  - mode: "Regression: someone reintroduces instanceof on a step-crossing error"
    detection: "cron-producer-output-wiring.test.ts negative assertion (Guard 2) and the harness scenarios in CI"
    alert_route: "CI red on the PR"

logs:
  where: "pino logger via the Inngest bound-logger middleware, shipped to Better Stack"
  retention: "Better Stack plan retention"

discoverability_test:
  command: "grep -c 'op: \"deploy-lease-fresh\"' apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts"
  expected_output: "1"
```

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
| 1 | Harness re-throws the raw error on the final attempt instead of `rebuildAsStepError` | RED (self-test: caught error is `instanceof DeployInProgressError`, not `instanceof StepError`) |
| 2 | Harness surfaces a non-final step failure to the handler (rejects instead of never settling) | RED (self-test: the probe handler's `catch` records an error on attempt 0) |
| 3 | Harness stops re-entering the handler after a successful step | RED (self-test: a flag assigned inside step A's callback is still `true` when step B runs) |
| 4 | Harness dispatch: `runLikeInngest` returns after the first invocation | RED (self-test: a two-step probe handler's second step never ran) |

**Harness rows.**

- Suite edit that must go RED: drive the self-test's probe handler with the in-process `makeStep`
  from `cron-cohort-dedup.test.ts` instead of `runLikeInngest` → rows 1–3 fail. This is the row that
  shows the old mock is blind and the new harness is not.
- Suite edit that must go RED: S1, S5, S6 and S7 run against the pre-fix handler source (AC3 / AC6
  record this RED run).
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
stale and are corrected in this PR:

### ADR

- **ADR-078 — amend.** Add an amendment (2026-09-24, #8726): the substrate still throws
  `DeployInProgressError`; the 9 deferral-aware crons wrap the setup step so a non-final attempt
  throws (Inngest's step retry re-checks the lease) and the final attempt returns a
  `deploy-deferred` verdict, which the handler re-materializes as `DeployInProgressError` outside the
  setup catch. Record the rejected alternatives (message marker; return on every attempt).
- **ADR-126 — amend residual 1.** "`DeployInProgressError` mid-spawn" has no producer inside the
  guarded body and could not have matched a step-crossing error anyway; mark it dissolved by #8726
  and update the §"Scoped precisely" sentence that says `DeployInProgressError` "still rethrows bare".

### C4 views

No C4 impact. Enumerated against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
external actors (none added or changed: the operator and GitHub are unchanged), external systems
(Inngest Server, Sentry, GitHub, Resend — all already modeled, no new edge), containers/data stores
(none touched; step state already lives in the modeled Inngest Server/Redis), access relationships
(none change). No cron or monitor is added or removed, so no cardinality in `model.c4` edge prose
moves; verified by running `plugins/soleur/test/c4-count-parity.test.sh` green in Phase 4.

## Acceptance Criteria

- [ ] AC1 — Guard 2's census passes: with comments stripped (`test/helpers/strip-comments.ts`), the only files under `apps/web-platform/server/inngest/functions/` whose code contains the token `DeployInProgressError` are `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`. Comments may still name the class.
- [ ] AC2 — Each of the 9 cron files contains `deferDeployOnFinalAttempt(` inside the `"setup-workspace"` step and `throwIfDeployDeferred(` after the setup try/catch (carried by `tsc` and S1 over all 9; Guard 2 carries the negative half).
- [ ] AC3 — S1 passes for all 9 crons under `runLikeInngest` and fails on `origin/main` code (recorded in the PR body as the RED run).
- [ ] AC4 — S2: a lease present on attempt 0 and absent on attempt 1 reaches the spawn (retry preserved).
- [ ] AC5 — S3: a non-deferral setup error on the final attempt still produces `op: "setup-ephemeral-workspace"` and a `?status=error` check-in.
- [ ] AC6 — Drift guard: S5, S6, S6b, S7 pass under `runLikeInngest`, and S5, S6, S7 fail on `origin/main` code. No `step.run` callback in `cron-github-app-drift-guard.ts` assigns a handler-scope variable; a text grep cannot scope a match to a callback, so this is carried by S6/S7 (the re-entering harness is what makes such an assignment observable), and the reviewer checks the three callbacks by reading them.
- [ ] AC7 — The memoized output of each of the three drift-guard steps contains no substring of the injected synthetic secret (asserted in S5, S6 and S7 by reading the harness memo); `drift-check`'s output has exactly the keys `result` and `leakDetected`.
- [ ] AC8 — `test/helpers/inngest-step-harness.test.ts` passes and contains one assertion per Guard 1 mutation-matrix row (rows 1–4) plus the must-PASS row, each compared against `new StepError(...)` from `inngest`.
- [ ] AC9 — ADR-078 amendment and ADR-126 residual-1 edit present; `plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] AC10 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `cd apps/web-platform && ./node_modules/.bin/vitest run test/helpers/inngest-step-harness.test.ts test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-producer-output-wiring.test.ts test/server/inngest/cron-github-app-drift-guard.test.ts test/server/cron-drain-lease.test.ts` green. (The package runner is vitest; `bun test` is blocked by `apps/web-platform/bunfig.toml`, and `npm run -w` fails for lack of a root `workspaces` field.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (internal cron error routing;
no user-facing surface, content, pricing, legal document or vendor change).

## Test Scenarios

All step-boundary scenarios run under `runLikeInngest({ maxAttempts: 2 })` (the crons' `retries: 1`).

- **S1 (P1, fleet: 8 `ROWS` crons in `cron-cohort-dedup`, plus `cron-community-monitor-heartbeat`).**
  Given the substrate throws `DeployInProgressError` on every call, when the run completes, then:
  outcome `threw` with an error `instanceof DeployInProgressError`; no `sentry-heartbeat` step ran and
  no heartbeat `fetch`; no `reportSilentFallback` call with `op: "setup-ephemeral-workspace"`; the
  substrate was called twice (the retry happened). On `origin/main` code this fails: the rebuilt
  `StepError` reaches the setup catch.
- **S2 (P2).** Given the substrate throws `DeployInProgressError` on its first call and returns a
  workspace on its second, then the spawn runs and the run returns normally.
- **S3 (P3).** Given the substrate throws a plain `Error("git clone failed")` on every call, then
  `op: "setup-ephemeral-workspace"` is reported and the check-in is `?status=error`; outcome
  `returned` with `{ ok: false }`.
- **S4 (fail-safe).** Unit test of `deferDeployOnFinalAttempt` with `maxAttempts` undefined:
  returns the deferred verdict on attempt 0 (the documented divergence from the SDK, which would
  retry). With `attempt: 0, maxAttempts: 2`: rethrows the same
  error object. With a non-`DeployInProgressError` on the final attempt: rethrows.
- **S5 (P4, drift-check).** Given the mocked suppression file (`readFileSpy` for the
  `MANIFEST_DRIFT_SUPPRESS_UNTIL` path) holds a synthetic JWT-shaped string (`eyJ` + 24 or more
  URL-safe characters), so `readSuppression` returns it inside `warning` — a PEM header does NOT
  work here, because `readSuppression` strips all whitespace before building the warning and the
  PEM regex needs the spaces in `BEGIN RSA PRIVATE KEY` — then a `[security/leak-suspected]` issue is filed, no `github_api_network` / `ci/guard-broken`
  failure issue is filed, `out.leakDetected === true`, `out.failureMode === "leak_tripwire_fired"`,
  heartbeat `?status=error`.
- **S6 (P4, issue-handling re-entry).** The existing "leak tripwire fires" scenario (PEM in the
  `GET /app` error, tripping `issue-body`) under `runLikeInngest`: `out.leakDetected === true` and the
  ops email is the leak variant. On `origin/main` code `out.leakDetected` is `false`.
- **S7 (P4, notify-ops-email fold).** The existing "resend-body" test uses the same PEM-in-`GET /app`
  setup as S6, so after the fix the leak trips at `issue-body` first and `resend-body` never fires.
  Rewrite it: `failureDetail` still carries the PEM, but `issue-handling` fails for a non-leak reason
  (`createProbeOctokit` rejects), so the only leak is the one `assertNoLeak("resend-body")` raises
  inside `notify-ops-email`. Assert no Resend POST was made and `out.leakDetected === true`.
  Dropping the `notify-ops-email` fold must turn this RED.
- **S6b (P4, leak then failed leak-issue write).** As S6, plus `handleLeakIssue`'s
  `POST /repos/{owner}/{repo}/issues` rejects with a 403: `out.leakDetected === true` (the
  `issue-handling` callback returns its local flag after the outer catch swallows the 403), and
  `op: "issue_write_403"` is reported.
- **S8 (P5, harness self-test).** Guard 1 rows 1–4, each asserted against the SDK referent
  (`new StepError(...)` from `inngest`), plus the must-PASS row.
- **Regression.** `test/server/cron-drain-lease.test.ts` unchanged and green (the substrate still
  throws).

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
