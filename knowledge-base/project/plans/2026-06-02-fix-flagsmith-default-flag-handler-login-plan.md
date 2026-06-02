---
title: "fix: configure Flagsmith defaultFlagHandler so a /login flag timeout stops surfacing the SDK throw"
date: 2026-06-02
type: fix
status: planned
branch: feat-one-shot-flagsmith-default-flag-handler-login
lane: single-domain
issue: null
sentry_id: 8563c7e88cc240c1a44d1427d4fdf33e
related_pr: 4571
requires_cpo_signoff: false
---

# 🐛 fix: configure Flagsmith `defaultFlagHandler` so a `/login` flag timeout stops surfacing the SDK throw

## Overview

A production Sentry **WARNING** (handled, `8563c7e88cc240c1a44d1427d4fdf33e`,
release `web-platform@0.101.100`) fires on `GET /login` with the chain:

```
TimeoutError: The operation was aborted due to timeout
  → "getIdentityFlags failed and no default flag handler was provided"
```

`op: flagsmith.getIdentityFlags`, `feature: feature-flags`, `level: warning`,
`handled: yes`, `environment: production`.

The Flagsmith edge API (`https://edge.api.flagsmith.com`) sometimes exceeds the
`REQUEST_TIMEOUT_SECONDS = 0.2` (200 ms) ceiling on the cache-cold `/login`
render path. The `flagsmith-nodejs` SDK's `getIdentityFlags` wraps the abort in
the error message above **because no `defaultFlagHandler` is configured on the
client** (`node_modules/flagsmith-nodejs/sdk/index.ts:242-246`).

This plan configures a Flagsmith `defaultFlagHandler` so the SDK **no longer
throws** on evaluation failure — it returns a `DefaultFlag` (built from our
existing `FLAG_*` env-var mirror) and logs via its own logger instead. The
misleading `"...no default flag handler was provided"` wrapper disappears from
the cause chain, and the recovered-timeout path becomes a normal SDK fallback
rather than a caught throw.

### What this is NOT (premise correction — read before scoping)

The Sentry framing ("the SDK throws instead of degrading gracefully... the
`/login` route surfaces an error") is **partially stale**. The exact same
premise was evaluated and corrected in **#4571** (merged, commit `17f5fa7f`):

- `fetchRuntimeFlagsFromFlagsmith` (`lib/feature-flags/server.ts:104-132`)
  **already** wraps `getIdentityFlags` in `try/catch`, returns `null` on throw,
  and `getRuntimeSnapshot` (`:139`) **already** substitutes
  `runtimeEnvFallback()`. **The `/login` page already renders.** The route does
  NOT 4xx/5xx.
- The Sentry event is the **deliberate WARNING-level, debounced mirror** added
  by #4571 (`mirrorWarnWithDebounce`, `observability.ts:416`), not an uncaught
  error. #4571 chose the *reporting-side* fix (severity + per-segment debounce);
  it explicitly deferred the *SDK-side* `defaultFlagHandler` fix.

This plan finishes the job #4571 started: it removes the SDK throw at the source
so the cause chain no longer carries the `"no default flag handler"` wrapper, and
so a recovered timeout no longer produces a `captureException`-shaped Sentry
event at all on the happy-degradation path. It does **not** change the
env-fallback fidelity contract (ADR-038 §"Fallback semantics") — the
`defaultFlagHandler` reads the **same** `FLAG_*` env mirror that
`runtimeEnvFallback()` reads today.

## Research Reconciliation — Spec vs. Codebase

| Stated premise (from Sentry framing) | Reality (verified in codebase) | Plan response |
| --- | --- | --- |
| "The SDK throws instead of degrading gracefully; `/login` surfaces an error." | `server.ts:113` catches the throw; `:139` substitutes `runtimeEnvFallback()`. Page renders. The Sentry event is the #4571 WARNING mirror, not a route failure. | Reframe: scope is to remove the SDK throw at its source so the cause chain + the recovered-path Sentry shape stop carrying the "no default flag handler" wrapper. No route-rendering change. |
| "No default flag handler is configured." | TRUE — `client()` (`server.ts:76-81`) omits `defaultFlagHandler`. SDK throws the named error at `index.ts:242-246`. | Configure `defaultFlagHandler` on the `Flagsmith` ctor. |
| "Configure fallback defaults so a timeout does not surface as an error." | Fallback defaults already exist as `FLAG_*` env mirror (`runtimeEnvFallback`, `:90-96`). | Route the `defaultFlagHandler` through the SAME `FLAG_*` env mirror — single source of truth for the disabled/enabled default per flag. |
| (implicit) handler receives identity/role to pick a default | SDK contract: `defaultFlagHandler?: (featureName: string) => DefaultFlag` (`index.ts:82`) — receives only the flag name, NOT identity. | Acceptable: our env mirror is already role/org-agnostic per ADR-038, so a name→`envIsOn(RUNTIME_FLAGS[name])` mapping is exact-parity with `runtimeEnvFallback()`. |

### Premise Validation note

No GitHub issue is cited by the trigger (Sentry-driven). The cited prior artifact
is **#4571** — verified MERGED (`git log` shows commit `17f5fa7f` "fix(feature-flags):
warn-level debounced mirror for Flagsmith timeout on /login (#4571)"). The cited
file/symbol paths all exist on the working tree: `lib/feature-flags/server.ts`
(`client`, `fetchRuntimeFlagsFromFlagsmith`, `runtimeEnvFallback`,
`getRuntimeSnapshot`), `server/observability.ts` (`mirrorWarnWithDebounce`).
SDK contract verified against the installed version (`flagsmith-nodejs@8.1.0`,
`package.json:32` declares `^8.1.0`): `getIdentityFlags` throws the exact
error string only when `!this.defaultFlagHandler` (`sdk/index.ts:242-246`);
`DefaultFlag(value, enabled)` constructor at `sdk/models.ts:39-43`;
`FlagsmithConfig.defaultFlagHandler?: (flagKey: string) => DefaultFlag` at
`sdk/types.ts:103`. The two Sentry IDs differ (`8563...` vs #4571's
`ac2d...`), confirming the warning still fires post-#4571 — by design, since
#4571 only debounces; first-in-window still emits. No external premises remain
unvalidated.

## User-Brand Impact

**If this lands broken, the user experiences:** a flag default that disagrees with
the env-fallback mirror — e.g. `byok-delegations` or `team-workspace-invite`
silently reading the wrong on/off state during a Flagsmith outage, so a user
either sees a feature that should be hidden or loses one that should be on. The
`/login` page itself still renders (the route-level degradation is untouched).

**If this leaks, the user's data/workflow is exposed via:** N/A — this change moves
flag-default resolution from a throw-then-catch path to an SDK-callback path
reading the **same** `process.env.FLAG_*` values. No user data, identity, secret,
or cross-tenant value enters the `defaultFlagHandler` (it receives only a flag
name string). No new data-movement surface.

**Brand-survival threshold:** none

- threshold: none, reason: the change preserves the exact env-fallback semantics already shipped (ADR-038 §"Fallback semantics") — the worst failure mode is a flag reading its already-defined fallback default, not a security/data-exposure regression.

> Sensitive-path note: `apps/web-platform/server/observability.ts` DOES match the
> preflight Check 6 sensitive-path regex (the `apps/web-platform/server` prefix),
> which is why the explicit `threshold: none, reason:` scope-out bullet above is
> required. The edit to that file is **doc-comment-only** (the `feature-flags`
> errorClass-registry comment) — no executable change to the observability layer.
> The other edits (`lib/feature-flags/server.ts`, two tests, ADR-038 markdown) do
> not match the sensitive-path regex.

## Goals

1. Configure a `defaultFlagHandler` on the `Flagsmith` client so `getIdentityFlags`
   (and `getEnvironmentFlags`, for symmetry) **stop throwing** on evaluation
   failure — the SDK returns `DefaultFlag` + logs via its own logger.
2. Make the handler's per-flag default read the **existing** `FLAG_*` env mirror
   so env-fallback fidelity (ADR-038) is preserved bit-for-bit.
3. Keep the application-layer `try/catch` + `runtimeEnvFallback()` as
   defense-in-depth (a `defaultFlagHandler` returning a `Flags` object does NOT
   make `isFeatureEnabled` throw, but a malformed handler or a future SDK change
   could — the catch stays).
4. Decide and document what happens to the #4571 WARNING mirror once the SDK no
   longer throws (see Sharp Edges — the mirror's trigger condition changes).

## Non-Goals

- **No change** to the `/login` route, `app/layout.tsx`, `resolveIdentity`, or any
  page-rendering path. The route already degrades correctly.
- **No change** to `REQUEST_TIMEOUT_SECONDS` (200 ms ceiling stays — never block
  the request path on Flagsmith). Raising it is a separate latency trade-off and
  is explicitly out of scope.
- **No change** to the Flagsmith segment model, ADR-043 per-org targeting, or the
  `soleur:flag-set-role` / `soleur:flag-create` skill contracts.
- **No** offline-mode / `enableLocalEvaluation` adoption — the SDK forbids
  `defaultFlagHandler` + `offlineHandler` together (`index.ts:133-134`); we use
  `defaultFlagHandler` only.

## Implementation Phases

### Phase 1 — Add a default-flag-handler that reads the env mirror

**File: `apps/web-platform/lib/feature-flags/server.ts`**

1. Import `DefaultFlag` from `flagsmith-nodejs` alongside the existing `Flagsmith`
   import:

   ```ts
   import { Flagsmith, DefaultFlag } from "flagsmith-nodejs";
   ```

2. Add a module-level handler that maps a flag name to its env-mirror default.
   It must be total over arbitrary strings (the SDK may ask for any feature name
   present in the environment, not just our `RUNTIME_FLAGS` keys). For names we
   own, read the `FLAG_*` env var; for anything else, return disabled — the
   fail-safe default (no dark-launch on the fallback path, per ADR-038 §Identity
   model "Fail-safe (no dark-launch)").

   ```ts
   // SDK default-flag handler (flagsmith-nodejs). Invoked by getIdentityFlags /
   // getEnvironmentFlags ONLY when remote evaluation fails (timeout, network,
   // non-2xx) — so the SDK returns a DefaultFlag instead of throwing
   // "getIdentityFlags failed and no default flag handler was provided".
   // The default value mirrors the FLAG_* env state, the SAME source
   // runtimeEnvFallback() reads — ADR-038 §"Fallback semantics". Receives only
   // the flag NAME (no identity/role/orgId); our env mirror is role/org-agnostic
   // by design, so this is exact-parity with runtimeEnvFallback().
   function defaultFlagHandler(featureName: string): DefaultFlag {
     const envVar = (RUNTIME_FLAGS as Record<string, string | undefined>)[featureName];
     const enabled = envVar ? envIsOn(envVar) : false;
     return new DefaultFlag(null, enabled);
   }
   ```

   - Note the cast: `RUNTIME_FLAGS` is typed with `RuntimeFlagName` keys; the SDK
     passes a `string`, so index it through `Record<string, string | undefined>`
     and default unknown names to disabled.
   - `DefaultFlag(value, enabled)` — pass `value: null` (we only consume
     `isFeatureEnabled`, never flag *values*; confirmed: all call sites use
     `flags.isFeatureEnabled(name)` at `:110`).

3. Wire it into the client ctor (`client()`, `:76-81`):

   ```ts
   _client = new Flagsmith({
     environmentKey: key,
     apiUrl: process.env.FLAGSMITH_API_URL ?? DEFAULT_FLAGSMITH_API_URL,
     enableLocalEvaluation: false,
     requestTimeoutSeconds: REQUEST_TIMEOUT_SECONDS,
     defaultFlagHandler,
   });
   ```

4. **Keep `fetchRuntimeFlagsFromFlagsmith`'s `try/catch` + `runtimeEnvFallback`**
   as defense-in-depth (Goal 3). Do NOT delete it. With the handler configured,
   the `catch` arm should rarely fire on a remote timeout (the SDK now resolves
   instead of rejecting), but it still guards: `client()` returning `null`
   (missing key → handled by the `if (!c) return null` at `:103`), and any
   non-evaluation throw (e.g. a malformed identifier — `index.ts:226-228` throws
   *before* the try/catch, so the handler never sees it).

   **Decision required — the #4571 WARNING mirror trigger.** Once the SDK stops
   throwing on timeout, the `mirrorWarnWithDebounce` call at `:121` no longer
   fires for the *timeout* case (the value path returns a `DefaultFlag`-backed
   `Flags`). Two observability sub-options — pick **(a)** unless deepen-plan/review
   argues otherwise:

   - **(a) Accept reduced Sentry noise (recommended).** The whole point of #4571
     was to stop the timeout flood; removing the SDK throw removes the flood at
     the source. The SDK's own `this.logger.error(error, 'getIdentityFlags failed')`
     (`index.ts:248`) still emits to the configured SDK logger on each failure,
     so the signal is not lost — it moves from a Sentry WARNING to an SDK-logger
     line. Verify what logger the SDK uses by default and whether it routes to our
     pino sink (see Phase 3 step / deepen-plan observability gate). Keep the
     `try/catch` mirror for the **non-timeout** residual throws only.
   - **(b) Preserve an explicit low-volume Sentry breadcrumb on DefaultFlag use.**
     If observability review wants a count of "served defaults" events, detect
     `flags.isFeatureEnabled(name)`-via-default by checking `flag.isDefault`
     (`BaseFlag.isDefault`, `models.ts:31`) on the returned flag and emit a
     debounced WARNING through the existing `mirrorWarnWithDebounce` with a NEW
     `errorClass` (e.g. `flagsmith:served-defaults`). Register the new errorClass
     in the `observability.ts` registry comment (`:278-298`).

   This decision is the load-bearing observability call — defer the final choice
   to deepen-plan Phase 4.7 (Observability Quality Gate), but the plan's default
   is **(a)**.

### Phase 2 — Tests (RED → GREEN)

Runner is **vitest** (`apps/web-platform/package.json:15` → `"test": "vitest"`;
NOT bun test — `bunfig.toml [test]` blocks bun discovery). vitest collects
`lib/**/*.test.ts` under the **node** project (`vitest.config.ts:44`), so files
under `lib/feature-flags/` are auto-discovered. Run a single file with
`./node_modules/.bin/vitest run lib/feature-flags/<file>.test.ts`.

**File: `apps/web-platform/lib/feature-flags/server.test.ts`** (extend) — write
failing tests first:

1. **Handler returns env-mirror default for a known flag.** With
   `FLAG_BYOK_DELEGATIONS=1`, `defaultFlagHandler("byok-delegations")` returns a
   `DefaultFlag` whose `enabled === true`; with the env unset/`0`, `enabled === false`.
   (Export `defaultFlagHandler` for direct test, or assert via the integration
   seam below — prefer the integration seam to avoid widening the module's public
   surface unnecessarily; if direct test is chosen, export it.)
2. **Handler returns disabled for an unknown flag name.**
   `defaultFlagHandler("not-a-flag")` → `enabled === false`.
3. **Client ctor receives `defaultFlagHandler`.** Assert the `Flagsmith` mock was
   constructed with an options object containing a `defaultFlagHandler` function.
   (The existing `server.test.ts` already mocks `flagsmith-nodejs`; extend that
   mock to capture ctor args.)

**File: `apps/web-platform/lib/feature-flags/timeout-mirror-integration.test.ts`**
(update) — the existing tests assert the **pre-fix** behavior (`getIdentityFlags`
rejecting → WARNING mirror). Under option (a) the SDK no longer rejects on a
remote timeout. Update the contract:

4. **SDK-resolves-with-default path.** Mock `getIdentityFlags` to **resolve** with
   a `Flags`-like object whose `isFeatureEnabled` returns the env-mirror default
   (simulating the SDK's internal default-handler path). Assert
   `getFeatureFlags(ANON_IDENTITY)` resolves to the env-mirror snapshot AND
   `mockCaptureException` is **not** called (no Sentry WARNING for the recovered
   timeout). **Why this test matters:** it is the regression guard for the whole
   change — it proves the timeout no longer surfaces as a Sentry event.
5. **Residual-throw path still mirrors.** Keep one test where `getIdentityFlags`
   **rejects** (e.g. a non-timeout throw the handler can't catch) and assert the
   `try/catch` + `mirrorWarnWithDebounce` still emits exactly one debounced
   WARNING — defense-in-depth is intact.

> **Sharp edge for the test author:** the `Flags` SDK object's `isFeatureEnabled`
> must be mocked to return the env-mirror value, NOT a hardcoded boolean — assert
> the snapshot reflects `FLAG_*` env state so the test would fail if the handler
> diverged from `runtimeEnvFallback()`. This is the proxy-vs-invariant guard:
> assert flag **evaluation** equals the env mirror, not merely "the call resolved".

**File: `apps/web-platform/lib/feature-flags/server.test.ts`** — also re-run the
existing suite to confirm no regression in `getRuntimeFlag` / `getFeatureFlags` /
`isByokDelegationsEnabled` / `isTeamWorkspaceInviteEnabled`.

### Phase 3 — Observability doc + ADR note

**File: `apps/web-platform/server/observability.ts`** (doc-comment only) — update
the `feature-flags` family registry entry (`:288-290`) to reflect that the
`flagsmith:getidentityflags-timeout` errorClass now fires **only on residual
non-timeout throws**, not on the common remote-timeout case (which the SDK
`defaultFlagHandler` now absorbs). If option (b) is chosen, add the new
`flagsmith:served-defaults` errorClass to the registry instead.

**File: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`**
— add a short note under "Fallback semantics" that the env mirror is now consumed
by TWO mechanisms with identical values: (1) the SDK `defaultFlagHandler` (first
line of defense — stops the SDK throw), (2) `runtimeEnvFallback()` (defense-in-depth
for client-null / pre-try throws). Both read `FLAG_*`; the single-source-of-truth
invariant is preserved.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `client()` constructs `Flagsmith` with a `defaultFlagHandler` function
      (assert via ctor-arg capture in `server.test.ts`).
- [ ] `defaultFlagHandler("byok-delegations")` returns `enabled === true` iff
      `FLAG_BYOK_DELEGATIONS === "1"`, else `false`; same shape for
      `team-workspace-invite` (`FLAG_TEAM_WORKSPACE_INVITE`) and `kb-chat-sidebar`
      (`FLAG_KB_CHAT_SIDEBAR`). Verify the value tracks the env, not a constant.
- [ ] `defaultFlagHandler("<unknown>")` returns `enabled === false`.
- [ ] Integration test: a simulated remote-timeout that resolves via the SDK
      default path makes `getFeatureFlags(ANON_IDENTITY)` return the env-mirror
      snapshot AND emits **zero** `captureException` calls.
- [ ] Integration test: a residual `getIdentityFlags` **rejection** still produces
      exactly one debounced WARNING mirror (defense-in-depth intact).
- [ ] `runtimeEnvFallback()` and the `try/catch` in `fetchRuntimeFlagsFromFlagsmith`
      are NOT deleted (defense-in-depth retained).
- [ ] `./node_modules/.bin/vitest run lib/feature-flags/` passes (server.test.ts +
      timeout-mirror-integration.test.ts).
- [ ] `npx tsc --noEmit` (or the package's typecheck script) clean — the
      `RUNTIME_FLAGS` index cast compiles without `any`-leak.
- [ ] `observability.ts` registry comment for the `feature-flags` family updated to
      reflect the new trigger condition.
- [ ] ADR-038 "Fallback semantics" note added.
- [ ] PR body uses `Ref` (not `Closes`) for the Sentry context — there is no
      GitHub issue; reference the Sentry ID `8563c7e88cc240c1a44d1427d4fdf33e` and
      `Ref #4571` (the prior reporting-side fix this completes).

### Post-merge (operator)

- [ ] After deploy, confirm the `flagsmith:getidentityflags-timeout` WARNING volume
      drops in Sentry for `op: flagsmith.getIdentityFlags` on `/login`.
      **Automation:** Sentry MCP / API query is feasible — prescribe in
      deepen-plan / ship rather than dashboard-eyeballing (per
      `hr-no-dashboard-eyeball-pull-data-yourself`). Deterministic verdict: event
      count for the issue group over a 24h post-deploy window < pre-deploy 24h
      baseline.

## Observability

```yaml
liveness_signal:
  what: Flagsmith remote-evaluation failures now surface via the SDK's own
        logger.error("getIdentityFlags failed") + (defense-in-depth) the
        warn-level Sentry mirror for residual non-timeout throws.
  cadence: per remote-eval failure (SDK logger); debounced 5-min/segment (Sentry residual)
  alert_target: Sentry issue group for op=flagsmith.getIdentityFlags (WARNING); no paging
  configured_in: apps/web-platform/lib/feature-flags/server.ts (defaultFlagHandler + try/catch);
                 apps/web-platform/server/observability.ts (mirrorWarnWithDebounce)
error_reporting:
  destination: Sentry (WARNING level, debounced) for residual throws; SDK logger for default-served
  fail_loud: false  # recovered degraded path by design — env mirror serves the value
failure_modes:
  - mode: Flagsmith remote eval times out (the reported case)
    detection: SDK invokes defaultFlagHandler returning env-mirror DefaultFlag; SDK logger.error line
    alert_route: none (recovered; reduced Sentry noise is the goal — see #4571)
  - mode: FLAGSMITH_ENVIRONMENT_KEY missing so client() returns null
    detection: fetchRuntimeFlagsFromFlagsmith returns null then runtimeEnvFallback()
    alert_route: none (deploy-config gap; env mirror serves)
  - mode: residual non-timeout throw (malformed identifier, SDK contract change)
    detection: try/catch in fetchRuntimeFlagsFromFlagsmith
    alert_route: debounced WARNING via mirrorWarnWithDebounce (errorClass flagsmith:getidentityflags-timeout)
logs:
  where: Sentry (WARNING) + pino stdout via warnSilentFallback + SDK logger.error
  retention: Sentry default (30-90d); pino to stdout (Better Stack ingestion per existing pipeline)
discoverability_test:
  command: ./node_modules/.bin/vitest run lib/feature-flags/timeout-mirror-integration.test.ts
  expected_output: "the SDK-default-resolve test asserts zero captureException; the residual-throw test asserts exactly one debounced WARNING"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an internal reliability/observability
change to a single module (`lib/feature-flags/server.ts`) plus its tests and a doc
comment. No user-facing UI, no schema, no auth flow, no new data movement, no
infrastructure. Product/UX gate: NONE (no user-facing surface created or modified —
the `/login` render is unchanged; only the SDK's internal failure handling changes).

## Infrastructure (IaC)

No new infrastructure. Pure code change against an already-provisioned surface
(`lib/feature-flags/server.ts`, a test, a doc comment). No new server, service,
secret, vendor, DNS record, or runtime process. `FLAGSMITH_ENVIRONMENT_KEY` and
`FLAG_*` env vars already exist in Doppler (consumed by the shipped code). Phase
2.8 IaC routing gate: skipped (no detected infra phrases).

## Test Scenarios

| Scenario | Setup | Expected |
| --- | --- | --- |
| Remote timeout, handler serves default | SDK resolves with default-backed Flags; `FLAG_BYOK_DELEGATIONS=1` | `getFeatureFlags` to snapshot with `byok-delegations: true`; 0 `captureException` |
| Remote timeout, flag disabled in env | same; `FLAG_BYOK_DELEGATIONS` unset | snapshot `byok-delegations: false`; 0 `captureException` |
| Residual throw (non-timeout) | SDK `getIdentityFlags` rejects | env-fallback snapshot; exactly 1 debounced WARNING |
| Missing env key | `FLAGSMITH_ENVIRONMENT_KEY` unset | `client()` null then env-fallback snapshot; 0 Sentry |
| Unknown flag name to handler | `defaultFlagHandler("xyz")` | `DefaultFlag` `enabled=false` |
| Debounce burst | 2 residual throws, same segment, cache reset between | 1 `captureException` (TtlDedupMap coalesces) |

## Sharp Edges

- **The `defaultFlagHandler` receives only the flag NAME, never identity.** Do NOT
  attempt to make the default role/org-aware inside the handler — the SDK contract
  (`index.ts:82`, `types.ts:103`) passes `(featureName: string)` only. Our env
  mirror is role/org-agnostic by ADR-038 design, so name to `envIsOn` is exact-parity.
  A handler that tried to read identity would be reading stale/absent context.
- **`enableLocalEvaluation` must stay `false`.** The SDK throws
  `'Cannot use both defaultFlagHandler and offlineHandler'` (`index.ts:133-134`) —
  but that is the *offline handler*, not local evaluation; still, do not introduce
  `offlineHandler` alongside `defaultFlagHandler`. Local evaluation is a separate,
  out-of-scope adoption.
- **`getIdentityFlags` throws BEFORE the SDK try/catch for a missing/empty
  identifier** (`index.ts:226-228`). The `defaultFlagHandler` does NOT catch this
  class — our application `try/catch` does. This is why the application-layer catch
  must stay (Goal 3). Our identifier is always non-empty (`role:${role}` or
  `org:${orgId}:${role}`, `server.ts:105`), so this is latent, but keep the guard.
- **The #4571 WARNING is not "broken" — it is the prior reporting-side fix.** Do
  not "revert #4571." This plan changes WHEN that mirror fires (residual throws
  only), not whether the mirror exists. The debounce + warn-level machinery stays.
- **Test the env-mirror invariant, not a proxy.** The integration test MUST assert
  the returned snapshot equals the `FLAG_*` env state (flag *evaluation*), not just
  that "the promise resolved." A handler that returned a hardcoded `false` for every
  flag would pass a resolve-only assertion while silently breaking the fidelity
  contract. (Plan-skill proxy-vs-invariant Sharp Edge.)
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled with threshold `none` + rationale.)

## Files to Edit

- `apps/web-platform/lib/feature-flags/server.ts` — add `DefaultFlag` import,
  `defaultFlagHandler` function, wire into `client()` ctor; keep `try/catch` +
  `runtimeEnvFallback`.
- `apps/web-platform/lib/feature-flags/server.test.ts` — handler unit tests +
  ctor-arg capture.
- `apps/web-platform/lib/feature-flags/timeout-mirror-integration.test.ts` —
  update to the SDK-resolves-with-default contract + keep residual-throw mirror test.
- `apps/web-platform/server/observability.ts` — registry doc-comment update
  (feature-flags family trigger condition).
- `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
  — "Fallback semantics" note (two consumers of the env mirror, identical values).

## Files to Create

None.

## Open Code-Review Overlap

To be populated at deepen-plan / work time via:
`gh issue list --label code-review --state open --json number,title,body --limit 200`
then `jq` per file path in `## Files to Edit`. (Deferred per plan-skill Phase 1.7.5
— the file list is finalized above; run the overlap query before implementation.)

## Research Insights (deepen-plan)

### SDK contract — verified verbatim against installed `flagsmith-nodejs@8.1.0`

Source: `apps/web-platform/node_modules/flagsmith-nodejs/sdk/` (read via a sibling
worktree's materialized `node_modules`; this planning worktree is a sparse
`knowledge-base/project/` checkout and has no `node_modules` of its own).

- **Throw site (the reported error string):** `sdk/index.ts:242-246`
  ```ts
  } catch (error) {
      if (!this.defaultFlagHandler) {
          throw new Error(
              'getIdentityFlags failed and no default flag handler was provided',
              { cause: error }
          );
      }
      this.logger.error(error, 'getIdentityFlags failed');   // :248
      return new Flags({ flags: {}, defaultFlagHandler: this.defaultFlagHandler }); // :249-252
  }
  ```
  With `defaultFlagHandler` set, the SDK takes the `else` arm: `logger.error` +
  return a `Flags` object whose `getFlag` misses route to the handler. **No throw.**
- **Handler invocation signature:** `sdk/types.ts:103` →
  `defaultFlagHandler?: (flagKey: string) => DefaultFlag;` and `sdk/index.ts:82`
  → `(featureName: string) => DefaultFlag`. The handler receives the **flag name
  only** — no identity, traits, secret, or cross-tenant value. (Confirms the
  `## User-Brand Impact` "no new data-movement surface" claim — verify-the-negative
  pass: **confirms**.)
- **`DefaultFlag` ctor:** `sdk/models.ts:39-43` → `constructor(value, enabled)` (calls
  `super(value, enabled, /* isDefault */ true)`). Pass `value: null`.
- **`isFeatureEnabled` → `getFlag` chain:** `sdk/models.ts:205-206` →
  `isFeatureEnabled(name)` calls `getFlag(name).enabled`.

### Behavior-change discovery (success-path miss, NOT just timeout) — load-bearing

`Flags.getFlag` at `sdk/models.ts:183-192`:

```ts
getFlag(featureName: string): BaseFlag {
  const flag = this.flags[featureName];
  if (!flag) {
    if (this.defaultFlagHandler) {
      return this.defaultFlagHandler(featureName);   // :188  <-- NEW behavior
    }
    return { enabled: false, isDefault: true, value: undefined };  // :191  current behavior
  }
  ...
}
```

There are **two** paths that reach the handler, not one:

1. **Whole-request failure** (timeout/network/non-2xx) → `index.ts:249-252` builds a
   `Flags` with empty `flags` → every `isFeatureEnabled` misses → handler serves
   every flag's env-mirror default. (This is the reported `/login` timeout case.)
2. **Successful response that simply omits a flag** → `getFlag` miss at
   `models.ts:186` → handler serves that flag's env-mirror default.

**Impact on path 2:** today (no handler), a flag absent from a *successful*
Flagsmith response evaluates to `enabled: false` (`models.ts:191`). After this
change, the same absent flag evaluates to its **env-mirror default**
(`envIsOn(FLAG_*)`). For a flag whose `FLAG_*` is `1` (enabled-in-prd), this flips
the absent-flag default from `false` to `true`. For our three current
`RUNTIME_FLAGS` this is the *intended* semantics (the env mirror IS the prd default
per ADR-038), so it is a correctness improvement, not a regression — **but the
implementer and reviewer MUST be aware it is not purely a timeout-path change.**

> **Action:** Add a test asserting path 2 explicitly — `getIdentityFlags` resolves
> with a `Flags` whose `isFeatureEnabled` misses a known flag (simulate by mocking
> `getIdentityFlags` to resolve with an `isFeatureEnabled` that returns the
> env-mirror value for absent flags), and assert the snapshot reflects the env
> mirror, not a hardcoded `false`. This guards the success-path semantics, which the
> reported Sentry event (timeout-only) does not exercise.

### Precedent-diff (Phase 4.4)

The `defaultFlagHandler` is **not a novel pattern** — it is the SDK-callback form of
the existing `runtimeEnvFallback()` (`server.ts:90-96`):

```ts
// EXISTING precedent — runtimeEnvFallback (application-layer, all flags at once):
function runtimeEnvFallback(): RuntimeSnapshot {
  const out = {} as RuntimeSnapshot;
  for (const [name, envVar] of Object.entries(RUNTIME_FLAGS) as [RuntimeFlagName, string][]) {
    out[name] = envIsOn(envVar);   // <-- same envIsOn(FLAG_*) read
  }
  return out;
}

// NEW handler (SDK-callback, one flag at a time) — exact-parity per-flag:
function defaultFlagHandler(featureName: string): DefaultFlag {
  const envVar = (RUNTIME_FLAGS as Record<string, string | undefined>)[featureName];
  return new DefaultFlag(null, envVar ? envIsOn(envVar) : false);   // <-- same read
}
```

Both read `envIsOn(RUNTIME_FLAGS[name])`. The single-source-of-truth invariant
(ADR-038 §"Fallback semantics") is preserved — there is exactly one place the
env-mirror semantics live conceptually, expressed in two shapes (batch vs per-flag).
The handler's only divergence is the unknown-name arm (returns disabled), which
`runtimeEnvFallback()` never hits because it iterates only known keys. Note both
should agree for known flags — a unit test asserting
`defaultFlagHandler(name).enabled === runtimeEnvFallback()[name]` for each
`RuntimeFlagName` would lock the parity (recommended belt-and-suspenders AC).

### Test-mock implementation detail (self-audit of existing `server.test.ts`)

The existing mock (`lib/feature-flags/server.test.ts:5-11`) is:

```ts
vi.mock("flagsmith-nodejs", () => ({
  Flagsmith: vi.fn().mockImplementation(() => ({ getIdentityFlags: mockGetIdentityFlags })),
}));
```

The `mockImplementation(() => ...)` **ignores constructor args**. To satisfy the AC
"client ctor receives a `defaultFlagHandler`", the implementer must either:

- capture ctor opts: `mockImplementation((opts) => { capturedOpts = opts; return {...} })`
  and assert `typeof capturedOpts.defaultFlagHandler === "function"`; OR
- assert via `vi.mocked(Flagsmith).mock.calls[0]?.[0]` after a client init, checking
  the first ctor arg contains `defaultFlagHandler`.

The mock must ALSO add `DefaultFlag` to the `flagsmith-nodejs` mock export (the new
`server.ts` imports it): `DefaultFlag: class { constructor(public value: unknown, public enabled: boolean) {} }`.
Without it, the `import { Flagsmith, DefaultFlag } from "flagsmith-nodejs"` resolves
`DefaultFlag` to `undefined` under the mock and `new DefaultFlag(...)` throws at
module-eval time — every test in the file fails with a confusing error. **This is the
single most likely /work-time stumble; flagged here so it is fixed in the first pass.**

### Observability decision (Phase 4.7) — default is option (a)

The plan's option (a) (accept reduced Sentry noise; SDK `logger.error` + residual-throw
mirror) satisfies the Observability gate: the `## Observability` section declares a
`discoverability_test` (vitest, no SSH), `failure_modes` with detection + alert_route
per mode, and `error_reporting`. The SDK's `this.logger.error(error, 'getIdentityFlags failed')`
(`index.ts:248`) fires on every failed eval — confirm at /work whether the SDK's
default logger routes to our pino sink or to `console`; if `console`, the residual
signal is stdout-only (acceptable — Better Stack ingests stdout), but note it in the
ADR-038 update so the next operator knows where to look. Option (b) remains available
if review wants an explicit served-defaults counter.

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Research Insights added; User-Brand Impact scope-out corrected
**Gates run:** 4.4 (precedent-diff — precedent is `runtimeEnvFallback`), 4.45
(verify-the-negative — SDK handler receives flag-name-only: **confirmed**), 4.6
(User-Brand Impact halt — **pass**, scope-out bullet added for the sensitive
`server/observability.ts` path), 4.7 (Observability gate — **pass**, 5 fields
present, no SSH), 4.8 (PAT-shaped variable — **pass**, none).

### Key Improvements

1. **SDK contract pinned verbatim** to `flagsmith-nodejs@8.1.0` source (throw site,
   handler signature, `DefaultFlag` ctor) — removes any reliance on training-data
   recollection of the SDK API.
2. **Behavior-change discovery:** the handler also fires on the *success-path
   flag-miss* (`models.ts:188`), not only on timeout — flips an absent flag's default
   from hardcoded `false` to the env-mirror value. Added an explicit test + reviewer
   callout so this is not a surprise at /work or in prod.
3. **Test-mock landmine surfaced:** the existing mock ignores ctor args AND must export
   `DefaultFlag` or every test in the file fails at import. Pre-empted in the plan.
4. **Parity AC recommended:** `defaultFlagHandler(name).enabled === runtimeEnvFallback()[name]`
   per known flag — locks the single-source-of-truth invariant mechanically.

### New Considerations Discovered

- The change has a (benign, intended) effect on the **success** path, widening the
  test surface beyond the reported timeout case.
- `apps/web-platform/server/observability.ts` matches the preflight sensitive-path
  regex (doc-comment-only edit), so the `none`-threshold plan needs the explicit
  scope-out bullet — now present.
- This planning worktree is a sparse `knowledge-base/project/` checkout (no `apps/`,
  no full `knowledge-base/`); the `/work` phase must run against a full checkout. All
  `apps/...` and ADR-038 paths in this plan are valid repo-relative paths verified
  against the bare-root tree, even though they are not materialized in THIS worktree.
