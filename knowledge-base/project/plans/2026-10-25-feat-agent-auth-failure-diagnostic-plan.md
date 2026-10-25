---
title: "feat: server-side diagnostic for the Claude CLI not-logged-in reply"
date: 2026-10-25
slug: agent-auth-failure-diagnostic
branch: feat-one-shot-agent-auth-failure-diagnostic
issue: 10455
type: feat
priority: p1
domain: engineering
closes: none
refs: "#10455, #10548"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-25
**Passes:** halt gates 4.6-4.13 run mechanically (user-brand, observability incl. probe-verb gate, PAT, UI skip, encryption posture, guard contract lint, scope check); security-sentinel, user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer, pattern-recognition-specialist; a local SDK source read (`sdk.mjs`); CTO rulings F13-F15; a credential-free local run of the bundled CLI (earlier).

### Key improvements

1. **Closed a P0 forgery path** (security + user-impact): the text arm required nothing the model cannot produce, so a tenant could page the operator and mute the real outage's email. The text arm now needs the CLI-set `<synthetic>` model or `is_api_error_message`; the structured arm stays alone sufficient (CTO F13).
2. **The tap now matches the measured SDK shape**: the real Query returns an internal single-use Stream from its iterator method; the wrapper delegates to that object and never re-enters its iterator method. The earlier "iterator returns `this`" assumption was wrong.
3. **Emit isolation and flood bounds**: `withIsolationScope` with breadcrumbs and user cleared, a process-wide cap, `.catch(noop)` on every fire-and-forget branch (the process exits on `unhandledRejection`) (CTO F14, F15).
4. **`match_kind` keeps its variants** (text classified before the always-present structured code) and the decode key documents `has_egress` as configured-not-reachable and `cli_key_source` project/user/apiKeyHelper/org as tenant-influenced.
5. **Tests that can actually go RED**: the pino line is observed through the logger's breadcrumb mirror with a positive control, the real `scrubSentryEvent` and Vector drop-list names are in the mutation set, latch/debounce/cap each get their own row, and the wiring cases assert the context is not `unknown`.

### New considerations

- `auth_env_present` cannot separate "reached the options, not the process" (the variable is set last whenever the lease value is non-empty); only `cli_key_source` can, and its non-`none` values have no local fixture yet.
- A warm cc Query serves many turns: the latch resets per `result` and the debounce is the rate limit.
- Open for the operator (schedule): the date on which Issue B ships the friendly error alone.

## Overview

The hosted Concierge currently answers every request with the CLI text "Not logged in" plus a
login hint while a validated credential is leased, and nothing reaches Sentry or Better Stack.
This plan adds one shared server-side matcher and emitter, wired into both agent runners, that
reports the first such reply per dispatch as a single routed Sentry event carrying only
low-cardinality, non-secret context, so the cause can be read from telemetry instead of guessed.

This PR is a **diagnostic, not the fix**: it does not resolve the outage, and the PR body says so. It
refs #10455 and #10548 and never closes either. No feature-flag state is read for writing or changed.

## Research Insights

### Premise Validation

Checked before research: #10455 (open, "sandbox: post-incident follow-ups from the hosted Bash outage"),
#10548 (open, SDK Bash smoke promotion follow-through), PR #10892 (merged 2026-10-24T00:03Z, the
`op=masked-dir-precreate` precedent) all hold. Every cited path exists on this branch (which carries
`origin/main` as of `b9a01dcd01`): `server/agent-env.ts`, `server/byok-lease.ts`,
`server/agent-runner-sandbox-config.ts`, `infra/sentry/{README.md,issue-alerts.tf,alert-reference.json}`.
ADR corpus grep (`sentry`, `observab`, `alert`): ADR-031 (Sentry as IaC) supports the rule-as-code route;
nothing rejects an event-driven diagnostic alert. Stale-claim found: the brief says the Concierge result
text is consumed "in `server/cc-dispatcher.ts`"; it is consumed in `server/soleur-go-runner.ts`
`consumeStream`, and `cc-dispatcher.ts` only constructs the Query (see the reconciliation table).

### Property List (Phase 0.6b)

- P1. A CLI auth-failure reply yields exactly one routed, alertable Sentry event per dispatch tuple, whose
  fields separate every competing root-cause hypothesis in that one event.
- P2. Nothing secret or identifying (key, env value, message body, user id, workspace id/path, IP) can reach
  Sentry or the pino line, now or after a later edit.
- P3. Both runners are covered by one implementation, not two copies.
- P4. Every other path is unchanged: the observer never throws, never reorders or delays the stream.
- P5. The event reaches a person (an enabled Sentry rule with an email action), proven by a test, not by memory.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | What already covers it / why cut |
|---|---|---|
| Clone `scripts/masked-dir-alert-discoverability.sh` + its mutation suite | P5 | The vitest triple-parse contract (emit source <-> HCL rule <-> `alert-reference.json`) plus a one-line `jq` probe on the committed reference; the clone also forces a `repo-wide-suites.ts` registration. CTO ruling F5. |
| `mirrorWithDebounce` for volume control | P4 (volume) | It claims and emits in one call; the authMode lookup must sit between claim and emit. A 20-line local TTL map in the leaf also avoids an import-time `TtlDedupMap` access that partial `vi.mock("@/server/observability")` factories in the runner tests would break. CTO ruling F3. |
| Observer sink on `QueryFactoryArgs` + `soleur-go-runner` `ActiveQuery` | P3 | In-place iterator tap in `realSdkQueryFactory`; no hot shared interface widened. CTO ruling F1. |
| Thread `authMode` from `ws-handler` into both runners | P1 | Lazy failure-path lookup through an injected resolver; zero cost on the happy path. CTO ruling F2. |
| Replace the user-visible CLI text with a friendly error | (product) | Separate, tracked follow-up (CPO advisory, 2026-10-25): bundling adds a user-visible change to an invisible PR. |
| Other structured codes (`oauth_org_not_allowed`, `account_on_hold`, `verification_required`, `billing_error`) | P1 | Out of the "not logged in / invalid credential" family; billing already has `anthropic_credit_exhausted`. |
| Refactor `sentry-masked-dir-precreate-alert-op-contract.test.ts` into a shared helper | (hygiene) | About 26 sibling `sentry-*-alert-op-contract.test.ts` files exist, each embedding its own rule parser by convention; the new test follows that convention (reusing only the shared TypeScript `test/helpers/strip-comments`), and the old tests stay untouched. A shared HCL helper is a separate cleanup across the family, not this PR. |

### Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified in the tree) | Plan response |
|---|---|---|
| "Find where the SDK result / assistant text is consumed in BOTH runners (`server/agent-runner.ts` and `server/cc-dispatcher.ts`)" | Legacy: `agent-runner.ts` loop `for await (const message of q)` (the `if (message.type === "assistant")` branch and its `else if (message.type === "result")` sibling). cc: `soleur-go-runner.ts` `consumeStream` (`for await (const msg of state.query as AsyncIterable<SDKMessage>)`) consumes; `cc-dispatcher.ts` `realSdkQueryFactory` only builds the Query and has the credential/sandbox context. | cc side taps the Query's async iterator inside `realSdkQueryFactory` (the one place that knows the context). |
| "authMode (managed\|api-key)" | Neither runner reads it; it lives in the persisted engine binding (`agent-engine-persistence.ts` `getConversationRun` -> `binding.authMode`). | Lazy, injected, bounded resolver on the failure path only; `unknown` on any failure. |
| "when the SDK result/assistant text matches" | The SDK also types a structured `SDKAssistantMessage.error` (`authentication_failed`, ...) in `sdk.d.ts`. | Matcher fires on the structured code OR an anchored whole-message text pattern. |
| "frequency_minutes must be unique, 39 is taken" | `git grep` on `origin/main` shows 5, 10-39, 60-63, 120, 240, 1440-1442 taken; open PRs #10967 and #10905 add none. 40 is free. | `frequency_minutes = 40`, re-checked after the last merge of `origin/main` (provisional until then). |
| "add a Sentry rule ... only if the existing convention requires it" | `infra/sentry/README.md` + the 2026-09-23 learning: a tagged error event with no rule is the #10455 defect (an event with nobody behind it). | Rule required; added with the emit in the same PR. |
| "register any new vitest file that reads outside `apps/web-platform`" | No planned test reads outside the app (the contract test reads `../server` and `../infra/sentry`). | No registration expected; `repo-wide-containment` is still run by name (it recomputes the set from disk). |
| (unstated) wiring shape | Two census tests pin the wiring literals: `agent-sandbox-seccomp-selector.test.ts` (A6a: `routed` needs `buildAgentQueryOptions(` INSIDE the `query({...})` literal) and `cc-dispatcher-bash-sandbox-mirror.test.ts:152` (`options: recordCcSeccompArtifact(args.userId, args.conversationId, buildAgentQueryOptions(`). | `probe.bindOptions(<existing expression>)` wraps the options expression in place (identity function); the second pin's regex is widened to allow the wrapper. No `const queryOptions = ...` extraction. |
| (unstated) test mocking | Runner tests mock `@/server/observability` with partial factories (no `TtlDedupMap`, `mirrorWithDebounce` stubbed). | The leaf touches `reportSilentFallback` only at emit time, never at import time. |

### Institutional learnings applied

- `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` (#8629): emit with a literal `null` first argument on EVERY path (including the post-resolver emit); verify all three hops (tags survive, rule exists, rule reaches a person).
- `2026-10-23-fix-round-agents-reported-green-on-their-own-files-and-broke-three-repo-global-gates.md`: run the repo-global gates by name on the combined tree; re-check `frequency_minutes` after the last merge; `git grep` every changed literal across `test/`.
- `2026-06-03-sentry-alert-match-feature-only-when-feature-is-dedicated.md` weighed against the CTO ruling: both `feature` and `op` are filtered so a later `agent-auth` diagnostic op cannot page by accident (a reverse-guard test pins the op set).
- `2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md`: `frequency_minutes` throttles per rule per issue group; the message is constant so all events share one issue and the 40-minute re-notify bounds email.
- `2026-04-28-sentry-payload-pii-and-client-observability-shim.md`: explicit allowlist for the payload, never forward `error.message`.
- `claude-error-signatures.ts` (leaf module of external SDK wording): the CLI reply wording lives there so a wording change degrades every discriminator in lockstep.

### Evidence about the CLI wording (read-only, local, no credentials)

`strings` over the bundled `claude` binary of SDK 0.3.283 (the installed package; the repo pins 0.3.284) shows:
`Not logged in · Please run /login` (separator U+00B7), `API Error: 401 Invalid API key · Please run /login`,
`OAuth token revoked · Please run /login`, `Session expired. Please run /login to sign in again.` /
`Your session has expired. Please run /login to sign in again.`, `Not logged in. Run claude auth login to authenticate.`
Non-auth near-misses that must NOT match: `Invalid API key format. API key must contain only alphanumeric characters, dashes, and underscores.`
and ordinary model prose ("you are not logged in to gh"). The work phase re-derives this list from the pinned
SDK version and records the version in the signatures module comment.

**Real stream shape, captured locally with no credentials** (the SDK's bundled `claude` 2.1.283, `env -i`, an empty
`HOME`, `-p hi --output-format stream-json --verbose`; no network call, no secret read; Sharp Edges: measure the
tool with the real binary and keep the real shape as the fixture). The stream is: (1) a `system`/`init` message
carrying `apiKeySource: "none"`; (2) one `assistant` message with `message.model = "<synthetic>"`,
`message.content = [{ type: "text", text: "Not logged in · Please run /login" }]`, top-level
`error: "authentication_failed"` and `is_api_error_message: true`; (3) a `result`. Two consequences carried into the
design: the structured arm fires in the real stream (not only in the types), and the init message hands the probe the
CLI's OWN statement of which credential source it resolved (`ApiKeySource` in `sdk.d.ts`: `ANTHROPIC_API_KEY`,
`apiKeyHelper`, `/login managed key`, `none`, `user`, `project`, `org`, `temporary`, `oauth`), a closed enum that
names the source and never the value. The work phase stores a trimmed copy of these three messages (with synthetic ids)
as the integration fixture; the `<synthetic>` literal is NOT required by the matcher (CTO F10).

## Problem Statement / Motivation

In production (verified 2026-10-24 on app.soleur.ai: connected repo, new conversation, cc-soleur-go routing)
the Concierge answers every request with "Not logged in · Please run /login" and runs no command, under
both authentication modes (managed and api-key), with a freshly validated Anthropic key
(`hasEffectiveKey: true`), and with the `agent-sandbox-unix-deny` flag both OFF and ON. A month-old
conversation shows the same text. Neither Sentry (24 h Discover search) nor Better Stack holds any event
for it. `buildAgentEnv` injects exactly one of `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` per scheme and
the BYOK lease throws a distinct `MissingByokKeyError` when no key exists, so the CLI text means the CLI
subprocess saw no usable credential although a key was leased. That narrows the cause to one of: the env
var reaches the options but not the subprocess (outer-wrap spawn, env allowlist), the value is empty or
malformed, the CLI rejects a well-formed credential for a reason local to the container (egress, sandbox
posture), or the credential is genuinely invalid. Nothing in production telemetry can currently tell these
apart. The diagnostic's one event is designed to separate them.

## Proposed Solution

1. **Matcher** (pure): `matchAgentAuthFailure(message)` returns a closed `match_kind` or `null`. Check order is
   cheap-first: `typeof text === "string"`, then `length <= 200`, then the anchored regex (no nested or overlapping
   quantifiers). Fires on (a) an anchored FULL-message text pattern in a single text block with no `tool_use`
   (or a `result` with `is_error === true`), AND, for the assistant text arm, `message.model === "<synthetic>"` OR
   `is_api_error_message === true` - both are set by the CLI in the captured real stream and cannot be set by the model,
   which closes the forgery path where a tenant makes the model reply with the exact CLI string (CTO F13); or (b) the
   structured `assistant.error === "authentication_failed"` (alone sufficient, observed in the real stream). Text is
   classified FIRST and `structured` is the fallback, so `match_kind` keeps its variants (`not_logged_in`,
   `invalid_api_key`, `oauth_token_revoked`, `session_expired`), which separate "the CLI saw no credential" from "the API
   rejected one". If the SDK ever renames the two CLI-set fields the text arm goes silent and only the structured arm
   fires; that degradation is accepted and recorded here. The `authentication_failed` literal is one exported const in
   `claude-error-signatures.ts` (the message translator in `claude-code-message-translator.ts` carries its own copy of the
   code set; it is not touched in this PR, and a comment on each names the other).
2. **Context** (pure): `deriveAgentAuthContext(runner, scheme, options)` reads the FINAL SDK options object
   (after the cc seccomp recorder) and returns only enums/booleans: credential scheme, `auth_env_present`
   (the scheme's env var is a non-empty string; truthiness only, the value is never read into anything
   that is stored), seccomp artifact, `has_egress`, `sandbox` on/off, `outer_wrap`.
3. **Probe** (stateful, per Query): `createAgentAuthFailureProbe({ runner, credentialScheme, dedupeToken,
   resolveAuthMode? })` where `dedupeToken` is the user id (an in-process map key; never emitted, never logged) and
   `bindOptions(opts)` is an identity function that derives the closed-enum context EAGERLY and retains no reference
   to `opts` (its `env` holds the leased key for the stream's lifetime). `observe(msg)` never throws and returns a
   promise tests can await. The once-latch resets on every `result` message: a warm cc Query serves many turns, so
   "one event per dispatch" means per turn, and the 5-minute per-user debounce is the rate limit across turns. The probe also
   remembers the `system`/`init` message's `apiKeySource` when it is a member of the closed `ApiKeySource` list (else
   `unknown`) and reports it as `cli_key_source` - the CLI's own statement of whether it saw the credential. On a
   match it claims a 5-minute slot keyed `(dedupeToken, runner|scheme|envPresent|keySource|artifact|egress|sandbox|outerWrap)`
   synchronously (the tuple is complete at claim time because `init` precedes the failure message, which is the CTO F10
   condition for including `cli_key_source`), then resolves `auth_mode` (injected, 1.5 s bound; values `managed`,
   `api-key`, `unbound` for a conversation with no engine-run row, `unknown` for a failed or slow lookup), then emits
   fire-and-forget. If the emit throws, the claim is released so a burned window cannot swallow the next event. A process-wide cap of
   10 events per 5 minutes (a `global` key in the same local map) is checked FIRST, so a flood cannot evict per-user entries;
   suppressed events are counted in a bounded in-memory counter and never logged at warn (CTO F14). The whole `observe`
   body is inside try/catch and every fire-and-forget branch ends in `.catch(noop)` (the project's `crash-handlers.ts`
   exits the process on `unhandledRejection`, so one stray async throw would end every tenant's session).
4. **Emit** (single chokepoint): `reportSilentFallback(null, { feature: "agent-auth", op: "cli-auth-failure",
   message: <constant>, tags: payload, extra: { ...payload } })` where `payload` is ONE object of closed-enum
   strings (`runner`, `credential_scheme`, `auth_env_present`, `auth_mode`, `cli_key_source`, `seccomp_artifact`,
   `has_egress`, `sandbox`, `outer_wrap`, `match_kind`). `extra` duplicates the tags because only `extra` reaches the pino
   line (Better Stack), the second sink that still works if Sentry capture is the broken part. With a `null` first
   argument the helper sends `extra: { err: null, ...payload }` and the pino object `{ err: null, feature, op, ...payload }`,
   so the contract is "extra equals payload plus `err: null`", nothing else. The call runs inside
   `Sentry.withIsolationScope(scope => { scope.clearBreadcrumbs(); scope.setUser(null); ... })` (CTO F15): the logger mirrors
   every warn+ line from every tenant into the process-wide scope, and those breadcrumbs would otherwise ride on this event.
   The capture is synchronous inside the callback; the work phase confirms the installed `@sentry/nextjs` exports
   `withIsolationScope` and that the async-context strategy is active.
5. **Tap** (cc path): `tapAgentAuthFailure(query, probe)` captures `orig = query[Symbol.asyncIterator].bind(query)` ONCE
   and overrides `[Symbol.asyncIterator]` in place (identity preserved; a re-entry never double-wraps or recurses).
   Measured shape of the real SDK Query (`sdk.mjs`, installed 0.3.283; the repo pins 0.3.284, re-check at work time):
   the Query class has its own `next`, `return`, `throw` that delegate to an internal Stream `this.sdkMessages`, and its
   `[Symbol.asyncIterator]()` returns that Stream, whose own `[Symbol.asyncIterator]()` throws `Stream can only be iterated once`.
   So `for await` (which calls `query[Symbol.asyncIterator]()` once and then the returned object's `next`/`return`)
   never touches `Query.next`. The wrapper therefore returns a thin object whose `next`/`return`/`throw` delegate to the
   object `orig()` returned, and it must NEVER call that object's `[Symbol.asyncIterator]`. The tap test fixture models this exact
   shape (a Query-like with its own `next`, and an iterator method that returns a separate single-use stream object).
   Its `next()` returns the ORIGINAL promise unchanged and observes on a side branch (`p.then(r => safeObserve(r.value), noop)`),
   so it adds no `await` to the consumer's path and cannot reorder against `state.closed` / `close()` in
   `consumeStream`; `return`/`throw`, `.close()` and `.interrupt()` are untouched. A frozen, non-writable or
   non-iterable object is returned untouched. Stated boundary: direct `q.next()` callers are not observed - none
   exist in the runner or dispatcher today; the work phase re-greps for them (`git grep -n "\.next(" server/soleur-go-runner.ts server/cc-dispatcher.ts`).
6. **Wiring**: legacy `agent-runner.ts` creates the probe, wraps the options expression with
   `authProbe.bindOptions(...)`, and calls `void authProbe.observe(message)` at the top of its loop;
   `cc-dispatcher.ts` `realSdkQueryFactory` does the same and returns `tapAgentAuthFailure(sdkQuery({...}), authProbe)`.
   The probe, `bindOptions` and the tap sit INSIDE the factory's existing try, whose catch releases the lease and
   mirrors a `sandbox sdk-startup` event, so each of them is individually guarded (a throw falls back to a no-op probe,
   the raw options, the untapped Query); a bug in the diagnostic can neither break a dispatch nor be misreported as a
   sandbox failure.
7. **Alert**: `sentry_alert.agent_auth_failure` (email `issue_owners` -> `ActiveMembers`, `value 0` / `1h`,
   `frequency_minutes = 40`, filters `feature eq agent-auth` AND `op eq cli-auth-failure`) plus its
   `alert-reference.json` entry and the README counts. It is declared a temporary diagnostic (see
   Follow-ups).

## Technical Approach

### Architecture

```text
SDK stream message ──► authProbe.observe(msg) ──► matchAgentAuthFailure ──► (first match only)
   legacy: loop top in agent-runner.ts                                   │ sync: claim (dedupeToken|tuple) 5 min
   cc:     tapAgentAuthFailure(...) in realSdkQueryFactory               │ async: resolveAuthMode (1.5 s) -> enum
                                                                         ▼
                              reportSilentFallback(null, {feature:"agent-auth", op:"cli-auth-failure", tags, extra})
                                   ├─► Sentry captureMessage (level error) ─► sentry_alert.agent_auth_failure ─► email
                                   └─► pino logger.error ─► Better Stack (level >= 40)
```

Modules (all under `apps/web-platform/server/`, server-only; the client/server import boundary in
`server/README.md` is unaffected because only server modules import them):

- `claude-error-signatures.ts` (edit): add `CLI_AUTH_FAILURE_REPLIES` (kind + anchored regex, separators as
  `\u00B7` escapes per `cq-regex-unicode-separators-escape-only`), with the SDK version and date the wording
  was read, one sentence in the module header saying this const is a REPLY signature (a message the CLI prints) unlike
  the thrown-error signature beside it, and a "re-derive on every SDK bump" note (the structured arm covers most of a
  wording change; nothing else re-checks this list).
- `agent-auth-failure.ts` (new leaf): matcher, context derivation, payload builder, probe, tap, local TTL
  dedupe map (cap 1024, oldest evicted) with a `__resetAgentAuthDedupeForTests` seam. Imports only
  `./observability` (call-time use of `reportSilentFallback`), `./agent-auth-env-vars`,
  `./agent-sandbox-seccomp`, `./claude-error-signatures`. No Supabase import.
- `agent-auth-mode.ts` (new): `makeAuthModeResolver(userId, conversationId)` -> `() => Promise<string | null>`
  via `getFreshTenantClient` + `AgentEnginePersistenceRepository.getConversationRun`, returning
  `binding.authMode` or `null` (no engine-run row, as for an old or unbound conversation, maps to `unbound`);
  injected at both call sites. The probe maps any other value outside `managed | api-key` to `unknown`. Accepted
  cost, stated in a code comment: `getFreshTenantClient` may mint a JWT (about 750 ms, against the 60/hour
  `precheck_jwt_mint` ceiling) and the 1.5 s `Promise.race` leaves a slow mint running after the timeout; the claim-before-lookup
  ordering caps it at one lookup per tuple per 5 minutes per user. The module header carries the removal checklist
  (see Follow-ups) so deleting the diagnostic is one pass.

### Decode key (how to read the event)

Carried verbatim into the rule's `.tf` comment and the README entry, so the person who receives the email does not
have to reconstruct the hypotheses:

| Tags | Reading |
|---|---|
| `auth_env_present=false` | The built agent env has no usable credential variable: look at the lease value/scheme, not the CLI. |
| `auth_env_present=true` and `cli_key_source=none` | The variable was in the options but the CLI process resolved no credential: a spawn or env-hand-off problem (read `outer_wrap`, `sandbox`, `seccomp_artifact` next). |
| `auth_env_present=true` and `cli_key_source` is `ANTHROPIC_API_KEY` or `oauth` | The CLI saw the credential and the API refused it: invalid or revoked key, or an account state. UNVERIFIED locally - only the `none` value has a captured fixture. |
| `cli_key_source=unknown` | The `init` message was not seen or carried a value outside the closed list: no conclusion from this field. |
| `auth_mode=unbound` / `unknown` | No engine-run row for the conversation (an old or unbound conversation) / the lookup failed or timed out: no conclusion from this field. |
| `seccomp_artifact`, `sandbox`, `has_egress` | Posture dimensions for comparing runs where the failure appears and where it does not (for example the `agent-sandbox-unix-deny` flag OFF vs ON). |
| `match_kind` | Which closed pattern matched: `not_logged_in` (the CLI saw no credential), `invalid_api_key` / `oauth_token_revoked` / `session_expired` (a credential was presented and refused or lapsed), `structured` (the SDK's own `authentication_failed` code with no recognised text; it fires in every real stream, which is why text is classified first). |
| `has_egress` | A build-time flag (a GitHub token or web-egress handle was configured), not a reachability result: do not read it as proof of network access. |
| `cli_key_source` of `project`, `user`, `apiKeyHelper` or `org` | Tenant-influenced: a workspace's own settings can select the credential source, so a single tenant can legitimately trigger this event; the process-wide cap bounds the volume. |

Limitation, accepted (CTO F12): a spawn-time throw (the CLI never starts, or the SDK iterator throws instead of yielding
the synthetic message) is invisible to this probe. Trigger to add a `thrown` arm: the outage persists and no event
appears, or a user reports the auth text with no matching event.

### Implementation Phases

#### Phase 0: Setup and baseline

- The worktree has no `node_modules`; install per `apps/web-platform/package.json` (`npm ci`) before `tsc`/`vitest`.
- Baseline (record rc and counts): `npx vitest run test/agent-sandbox-seccomp-selector.test.ts test/sdk-query-sites.test.ts test/server/cc-dispatcher-bash-sandbox-mirror.test.ts test/cc-dispatcher-real-factory.test.ts test/agent-runner-unix-deny-wire.test.ts test/sentry-masked-dir-precreate-alert-op-contract.test.ts`.
- Success: baseline green, so any later red is attributable to this change.

#### Phase 1: RED tests first (`cq-write-failing-tests-before`)

Write all of the following against the not-yet-existing modules; each must fail for the right reason:

1. `test/agent-auth-failure-matcher.test.ts` - positive family (every `CLI_AUTH_FAILURE_REPLIES` kind with the real
   U+00B7 separator and its variants, plus `error: "authentication_failed"` with arbitrary text), negative near-misses
   (the "Invalid API key format" sentence, model prose, lower-case variant, text inside a multi-block message, text
   beside a `tool_use`, text > 200 chars, a successful `result` quoting the text, `stream_event` partials, non-object
   inputs), the FORGERY row (a plain assistant block with a real model id, no `is_api_error_message`, carrying the exact
   CLI text, must be `null`; the same block with `model: "<synthetic>"` or `is_api_error_message: true` matches), the
   text-first ordering (a real-stream message with both the text and `error: "authentication_failed"` reports the text
   variant, not `structured`), a 200-character adversarial-whitespace timing row, and the no-leak property (the returned
   value is always a member of the closed enum or `null`; never a substring of the input).
2. `test/agent-auth-failure-probe.test.ts` - context derivation from real `buildAgentQueryOptions` output (both
   schemes, egress on/off, flag on/off, sandbox present/absent, outer wrap on/off, a mocked builder returning
   `undefined`; `has_egress` and `seccomp_artifact` both read from `sandboxPostureOf` and `usesUnixDenyArtifact`, the single
   predicate, not a fourth hand-written spelling), probe semantics (one event per probe, debounce per user x tuple, a
   different tuple re-emits, the process-wide cap, authMode normalisation and 1.5 s timeout via an injected clock/timer,
   resolver throw -> `unknown`, and a test that no resolver call happens without a claimed match).
2b. `test/agent-auth-failure-tap.test.ts` - tap semantics against a fixture that models the REAL Query shape (own
   `next`/`return`/`throw`; an iterator method returning a separate single-use stream object that throws on a second
   `[Symbol.asyncIterator]` call): identity, order, `break` runs the underlying `finally`, underlying throw propagates,
   observer throw swallowed, non-writable and non-iterable objects untouched, no double-wrap on re-entry.
3. `test/agent-auth-failure-sentry-path.test.ts` - REAL path: real logger, real `reportSilentFallback`, real probe, real
   `buildAgentQueryOptions`; only `@sentry/nextjs` is replaced by spies (precedent:
   `agent-sandbox-precreate-sentry-path.test.ts`, whose mock spreads the real module so `withIsolationScope` stays real).
   Includes the secret canary: canaries are fake key, fake OAuth token, fake workspace path, fake user id, the CLI body
   and a canary-shaped authMode, in whole AND derived forms (a key prefix, a length) over `JSON.stringify` of every spy
   call. The pino line is observed through the logger's own Sentry breadcrumb mirror (`mirrorToSentry` hands the same
   redacted args to `Sentry.addBreadcrumb`), with `LOG_LEVEL` set so the line exists, plus a POSITIVE control asserting a
   breadcrumb carrying `feature`, `op` and all ten keys is present (a canary over an empty capture proves nothing);
   leak mutants use non-sensitive key names so the logger's redaction cannot mask them. The captured tags and extra are
   also passed through the REAL `scrubSentryEvent` (control: a payload key named `tag` is redacted there), and every
   payload key is asserted absent from `SENSITIVE_LOWER` and from the Vector drop-list names. The isolation-scope case
   pre-seeds an outer `setUser` and breadcrumb, then asserts they are absent from the captured event and the outer scope
   is unchanged. The wiring cases additionally assert the context tags are not `unknown` (a runner that skips
   `bindOptions` would otherwise still pass).
4. `test/sentry-agent-auth-failure-alert-op-contract.test.ts` - emit site <-> rule <-> reference (Guard 1).
5. Wiring: extend `test/agent-runner-unix-deny-wire.test.ts` (legacy, drives `startAgentSession`) and
   `test/cc-dispatcher-real-factory.test.ts` (cc, mocked `sdkQuery`) with one auth-failure stream case each, asserting
   exactly one `reportSilentFallback(null, ...)` with `feature: "agent-auth"` and the right `runner`. Both mock
   `@/server/observability` with an inline `vi.fn()` and no hoisted handle in the legacy file, so import the mocked
   `reportSilentFallback`, `await vi.waitFor(...)` the fire-and-forget emit, and mock `server/agent-auth-mode` (or pass a
   stub resolver) so the Supabase graph stays out. Add the source pins here (not in Guard 1): each runner imports the
   module, calls `createAgentAuthFailureProbe(`, wraps with `authProbe.bindOptions(`; the legacy loop calls `.observe(`;
   cc returns `tapAgentAuthFailure(sdkQuery(`.
6. Extra cases in `test/agent-auth-failure-probe.test.ts`: a warm Query (two `result` boundaries) re-emits after the
   debounce window and not before; the latch resets on `result`; a throwing `bindOptions`/probe construction/tap in the
   cc factory falls back to a working untapped Query and is not mirrored as a sandbox failure; the tap adds no microtask
   to the consumer path (observe a `for await` over a tapped generator and an untapped one: identical resolution order
   against a concurrent `close()`); the probe holds no reference to `options` (a structural check only - nothing reachable from the probe is the options
   object or its `env`; no GC-timing `WeakRef` check); a failing emit releases the claim;
   the REAL `makeAuthModeResolver` against a fake `PersistenceClient` (row present -> `managed`/`api-key`, no row ->
   `unbound`, client throws -> `unknown`); and one case that feeds a tapped Query through the real
   `createSoleurGoRunner` `consumeStream` path (a `state.query`-shaped fake), so a later switch from `for await` to direct
   `.next()` consumption fails loudly; and a no-unhandled-rejection case (resolver rejecting after the timeout, the race
   loser rejecting late, the emit throwing: a `process.on("unhandledRejection")` listener never fires).

#### Phase 2: Implement the leaf modules

`claude-error-signatures.ts` edit, `agent-auth-failure.ts`, `agent-auth-mode.ts`. The seccomp artifact comes from the
single predicate `usesUnixDenyArtifact(posture.hasEgress, posture.unixDenyFlag)`; the two existing ternaries that spell the
same expression (`recordCcSeccompArtifact`, `agent-runner-sandbox-config.ts`) are NOT refactored here (non-goal; a shared
`seccompArtifactKindOf` is a separate cleanup). The local TTL map is deliberate (partial-mock safety, and
`conversation-writer.ts` has a local-map precedent); a lazily built `TtlDedupMap` created on first claim inside the try is
the accepted alternative if the work phase prefers one fewer copy of the sweep bookkeeping. Hot path: `observe` checks
`type`/`error` first and only regex-tests a single-text-block message of <= 200 chars; no allocation otherwise.

#### Phase 3: Wire the runners and widen one pin

- `server/agent-runner.ts`: import; create the probe before `const q = query({`; `options: authProbe.bindOptions(buildAgentQueryOptions({...}))`
  (re-indent only the closing parens); `void authProbe.observe(message);` as the first statement after the abort guard in
  `for await (const message of q)`.
- `server/cc-dispatcher.ts` `realSdkQueryFactory`: import; probe after `credential` is known; `options:
  authProbe.bindOptions(recordCcSeccompArtifact(args.userId, args.conversationId, buildAgentQueryOptions({...})))`;
  `return tapAgentAuthFailure(sdkQuery({ prompt: args.prompt, options: ... }), authProbe);`.
- `test/server/cc-dispatcher-bash-sandbox-mirror.test.ts` (the `options: recordCcSeccompArtifact(` source pin): widen the regex to
  `/options: authProbe\.bindOptions\(recordCcSeccompArtifact\(args\.userId, args\.conversationId, buildAgentQueryOptions\(/`
  (the wrapper is REQUIRED, so the pin now also proves the probe is bound, and the recorder still wraps the builder).
  Add `authProbe.bindOptions(` to the A6a census comment in `agent-sandbox-seccomp-selector.test.ts` so the next reader
  knows the wrapper is expected there.
- `git grep` every changed literal across `test/` and `scripts/` before committing (`options: buildAgentQueryOptions`,
  `recordCcSeccompArtifact(`, `const q = query(`).

#### Phase 4: Alert rule, reference, counts

- `infra/sentry/issue-alerts.tf`: new `sentry_alert.agent_auth_failure` after `masked_dir_precreate_failed`, cloned from it
  verbatim except the name, `frequency_minutes`, the `feature`/`op` values and the comment block (so `monitor_ids` and
  `lifecycle { ignore_changes = [environment] }` carry over), with a
  comment block naming the emit site, the `null`-first-argument reason (#8629), the constant message / one-issue
  grouping, the temporary-diagnostic status, and the updated "taken" list (5, 10-40, 60-63, 120, 240, 1440-1442).
- `infra/sentry/alert-reference.json`: new `agent-auth-failure` entry, key-sorted (`jq -S`), `detectorIds` identical to the
  masked-dir entry, `frequency: 40`. Derive it LOCALLY in the work phase, because the
  PR is red until the file matches the plan projection: the new entry has exactly the shape of the
  `masked-dir-precreate-failed` entry (same `detectorIds`, same single `email` action, same trigger), differing only in
  name, `feature` value, `op` value and `frequency`; read `tests/scripts/lib/sentry-alert-projection.jq` to confirm the
  field set, and treat CI as the proof, not the producer (the `sentry-alert-reference-expected-<run-id>` artifact is
  the fallback if a byte differs; README "Adding or editing a rule").
- `infra/sentry/README.md`: bump BOTH T25-pinned strings - `**48 \`sentry_alert\` rules**` and `(48 alert rules total)`
  (T25 in `scripts/sentry-monitors-audit.test.sh` greps each literally) - plus the unpinned "45 are fully Terraform-owned
  (44 in `issue-alerts.tf`" sentence -> 46 / 45 and this PR's issue refs. Add an entry for the rule with (a) a
  hypothesis-to-tag decode table (below), (b) the Better Stack query for the pino copy (`feature=agent-auth`), and
  (c) the lifecycle (Follow-ups). The same decode table sits in the comment block above the rule in the Terraform file.

#### Phase 5: Verification and hand-off

Run by name, on the combined tree, and read exit codes (not tail lines): the gate list in Acceptance Criteria. Compose the PR
body (requirements below). File the two follow-up issues before merge.

### Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Text-only matching (no structured arm) | A wording change in the CLI silently blinds it again; the structured code is independent of wording (CTO F4). |
| Per-conversation registry like `_ccSeccompArtifact` | Adds a second keyed map and a cleanup obligation (`handleCcCloseQuery`, the factory catch); the tap needs no lifecycle. |
| Emit from `soleur-go-runner.ts` `consumeStream` | The runner has no credential/sandbox context; threading it widens `QueryFactoryArgs` (CTO F1 B). |
| `captureMessage` with a per-tuple message | Splits one outage into N issues and N emails; constant message + tags groups into one. |
| Level `warning` | The operator asked for a routed error event; a warning still trips the rule but hides in default Sentry views (learning 2026-05-27). |

## Files to Create

- `apps/web-platform/server/agent-auth-failure.ts` - matcher, context derivation, payload builder, probe, tap, local TTL dedupe.
- `apps/web-platform/server/agent-auth-mode.ts` - `makeAuthModeResolver(userId, conversationId)`.
- `apps/web-platform/test/agent-auth-failure-matcher.test.ts` - positive family, negative near-misses, no body leak.
- `apps/web-platform/test/agent-auth-failure-probe.test.ts` - context derivation, probe, cap, resolver normalisation.
- `apps/web-platform/test/agent-auth-failure-tap.test.ts` - the Query tap against the measured real shape.
- `apps/web-platform/test/agent-auth-failure-sentry-path.test.ts` - real logger + real `reportSilentFallback`, Sentry SDK spied, secret canary.
- `apps/web-platform/test/sentry-agent-auth-failure-alert-op-contract.test.ts` - Guard 1.
- `knowledge-base/project/specs/feat-one-shot-agent-auth-failure-diagnostic/tasks.md` (and the existing `decision-challenges.md`).

## Files to Edit

- `apps/web-platform/server/claude-error-signatures.ts` - add `CLI_AUTH_FAILURE_REPLIES`.
- `apps/web-platform/server/agent-runner.ts` - probe creation, `bindOptions` wrap, `observe` call in the stream loop.
- `apps/web-platform/server/cc-dispatcher.ts` - probe creation, `bindOptions` wrap, `tapAgentAuthFailure` on the returned Query.
- `apps/web-platform/infra/sentry/issue-alerts.tf` - `sentry_alert.agent_auth_failure` + updated taken-list comment.
- `apps/web-platform/infra/sentry/alert-reference.json` - `agent-auth-failure` entry.
- `apps/web-platform/infra/sentry/README.md` - counts 47 -> 48 (and 45/44 -> 46/45), issue refs.
- `apps/web-platform/test/server/cc-dispatcher-bash-sandbox-mirror.test.ts` - widen the line-152 source pin to allow the wrapper.
- `apps/web-platform/test/agent-runner-unix-deny-wire.test.ts` - legacy auth-failure stream case.
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` - cc auth-failure stream case.

Glob/path check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was confirmed with `ls`/`git grep` against this tree; none is a glob.

## Open Code-Review Overlap

- #3243 (arch: decompose `cc-dispatcher.ts` into focused modules) - **Acknowledge.** This plan adds an import and about 20 lines at the factory tail, isolated enough to move with the factory when that decomposition happens; folding the decomposition in would multiply the diff by an order of magnitude. The issue stays open.
- #3242 (review: `tool_use` WS event lacks raw name field) - **Acknowledge.** Unrelated concern (`WS` payload shape); touches the same files only incidentally. The issue stays open.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) a Concierge turn that arrives late, out of order, or never
  completes - the tap sits on the stream every cc turn flows through - pinned out by the order/completion/no-added-microtask
  tests; (b) a crashed server session for every concurrent user if a fire-and-forget branch rejects unhandled (the
  process exits on `unhandledRejection`), pinned out by the try/catch plus `.catch(noop)` rule and a no-unhandled-rejection
  test; (c) unchanged status quo otherwise: BYOK customers who paid for a working Concierge keep seeing the raw CLI line
  "Not logged in" with no recovery path (a month-old failure) until Issue B ships - this PR does not fix it and its Issue B
  carries a proposed escalation date.
- **If this leaks, the user's workflow and credential is exposed via:** a later edit that serialises the leased
  key, the env value, the CLI message body, a user/workspace id or a workspace path into the Sentry event or the
  pino line (a third-party subprocessor and the log pipeline), e.g. `extra: { env }` or `tags: { match: text }`.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's BYOK key landing in Sentry is a credential disclosure to a
  subprocessor, which is brand-survival for a product that holds user keys; the diff also touches
  `apps/web-platform/server/` and `infra/`, so the sensitive-path clamp would resolve this tier anyway. CPO
  advisory (2026-10-25): tier confirmed.

CPO plan-time sign-off: **yes, with conditions** (2026-10-25), all carried as acceptance criteria: the secret canary
is a blocking CI test; a removal-trigger issue with a date; event rate bounded (per-probe once + 5-minute debounce);
both follow-up issues exist before merge; the PR states it does not resolve the outage. CLO (2026-10-25): the
closed-enum payload is not personal data (no id, no hashed id, no workspace, no IP, no text), so no gdpr-gate run,
Art. 30 entry or policy change; conditions carried as AC: never add any identifier, `sendDefaultPii` stays unset
(verified: no occurrence in `sentry.server.config.ts`), no `setUser`/`user` on this path, `match_kind` stays a closed
enum. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "Event-driven, so no heartbeat exists: the signal is the Sentry rule agent-auth-failure being declared, enabled and routed, proven from the committed live-fidelity reference (checked daily against live Sentry by scheduled-sentry-alert-drift) and from the contract test"
  cadence: "per failing dispatch (debounced to one per user per tuple per 5 minutes); rule re-notifies every 40 minutes while the issue is unresolved"
  alert_target: "operator email via issue_owners with ActiveMembers fallthrough"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.agent_auth_failure)"

error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback(null, ...) in apps/web-platform/server/agent-auth-failure.ts (message path, level error); the same call writes a pino error line that Vector ships to Better Stack"
  fail_loud: "Sentry issue 'agent-auth: the Claude CLI reported an authentication failure' with the ten closed-enum tags, plus the pino error line carrying the same keys via extra"

failure_modes:
  - mode: "The CLI replies not-logged-in although the lease produced a credential (the outage itself)"
    detection: "In-surface structured event emitted from the server process that owns the CLI subprocess and its stream (pino layer 2 + Sentry capture, release-tagged); runner, credential_scheme, auth_env_present, auth_mode, seccomp_artifact, has_egress, sandbox, outer_wrap and match_kind separate env-empty vs env-present, scheme, managed vs api-key, artifact, egress, sandbox and outer-wrap hypotheses in ONE event"
    alert_route: "sentry_alert.agent_auth_failure -> operator email (issue_owners, ActiveMembers fallthrough)"
  - mode: "Matcher misses because the CLI wording AND the structured error code both changed"
    detection: "Residual blind spot, bounded: the structured arm is independent of wording and fires in the real stream (captured locally: error authentication_failed). Post-merge check reads Sentry for tag feature:agent-auth within 15 minutes of any Concierge request while the outage persists; absence while the outage persists reopens this plan (pino layer 2 absence check)"
    alert_route: "none by design (absence cannot page); caught by the post-merge read-only Sentry query"
  - mode: "Sentry capture is dropped or the SDK is uninitialised"
    detection: "pino layer 2: the same call writes logger.error with feature, op and the ten keys (extra); Vector Source 3 app_container_journald feeds app_container_warn_filter (keeps level >= 40, none of the ten keys is on the drop list or in the sensitive-key set), then the scrub stages, then Better Stack"
    alert_route: "none (Better Stack log search by feature=agent-auth); the first-sink loss is itself visible because the pino line exists without a Sentry issue"
  - mode: "authMode lookup fails or times out"
    detection: "pino layer 2 / Sentry tag auth_mode=unknown on the event; the emit is never skipped"
    alert_route: "none (degrades to unknown, event still routed)"
  - mode: "The observer itself throws inside a runner loop"
    detection: "Swallowed by design (try/catch in observe and in the tap) but NOT silent: each catch emits one constant-text logger.warn per probe (pino layer 2, no err, no payload) so a defect in the diagnostic is visible in Better Stack; it deliberately does not use reportSilentFallback with a second op, because Guard 1 pins the op set to cli-auth-failure"
    alert_route: "none (Better Stack log search on the constant warn text); pinned by the tap and wiring tests"

logs:
  where: "Sentry web-platform project (issue + tags + extra); container stdout pino -> Vector -> Better Stack web source (filter feature=agent-auth)"
  retention: "Sentry project event retention (plan default); Better Stack retention as configured for the web source (not asserted here; the git-data source documents 90d in apps/web-platform/infra/variables.tf)"

discoverability_test:
  command: "jq -r '.[\"agent-auth-failure\"].enabled' apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "true"
```

Layer citations (`hr-observability-layer-citation`): pino layer 2 (`server/logger.ts` hook + `reportSilentFallback`) and
the Sentry release-context layer 5. Affected-surface rule (2.9.2): the dispatch/stream surface is
`agent-runner.ts` / `cc-dispatcher.ts`; the probe's fields discriminate all competing hypotheses in one event, and the
emit comes from the process that actually observes the CLI's reply, not from a host-side gate.

## Encryption Posture

Triggered by the `.tf` glob only (the Sentry rule file); the plan introduces no persistent store and no new
cross-component or network connection, so there is nothing to declare per store or per connection.

```yaml
at_rest: []        # no store introduced: a Sentry alert rule is configuration of the existing vendor project, not a data store
in_transit: []     # no new connection: the event rides the existing app -> Sentry SDK transport that reportSilentFallback already uses
```

Evidence: `sentry_alert` is already classified in the ledger's non-store types, and
`python3 scripts/lint-encryption-posture.py --repo-sweep` reports `21 stores, 10 connections, 0 unledgered, 0 failing checks -> PASS` on this tree (re-run after the rule lands; the new resource is an existing type).

## Guard Contract

### Guard 1 - emit-site / alert-rule contract

**Property.** Every `feature: "agent-auth"` event the server can emit is matched by one live, enabled Sentry rule that mails a person, and the committed reference equals that rule.

**Assembly.** The set quantified over is every non-test source under `apps/web-platform/server/**` (walked, comment-stripped), not a named file: the single chokepoint is the `reportSilentFallback(null, {...})` call in `server/agent-auth-failure.ts`, but the guard asserts the SET of `op` values emitted under `feature: "agent-auth"` equals `{cli-auth-failure}` (a second emit file or a second op reds), the token count of `cli-auth-failure` equals the count of literal emit sites (no constant/indirection hides one), the rule block `agent_auth_failure` in `infra/sentry/*.tf` (for frequency uniqueness across ALL root files), and the `agent-auth-failure` entry in `alert-reference.json`. The runner wiring pins live in the wiring tests, not here, so one mutation does not red two suites.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the emit's first argument from literal `null` to an identifier or `new Error(...)` (pino-mirror dedupe class #8629) | RED |
| 2 | Comment out the rule block, or set `enabled = false`, or drop the email action, or set `fallthrough_type = "NoOne"` | RED |
| 3 | Rename `op` in the emit only, or in the rule only | RED |
| 4 | Add a second emit site (new file under `server/`) with `feature: "agent-auth"` and a different op after the compliant first | RED |
| 5 | Dispatch of the guard itself: make the server walk find zero files, or hide the emit behind a constant so the literal count is 0 while the token count is 1 | RED |
| 6 | Give another rule `frequency_minutes = 40` | RED |
| 7 | Remove the `alert-reference.json` entry, or change its `frequency`/`tagged_event` values | RED |
| 8 | Change the emit's level to warning, or make its `message` variable (interpolated), or drop the `op` condition from the rule (the extractor requires exactly `feature` and `op`) | RED |

**Harness rows.** (a) Suite edit that must go RED: make the emit-site extractor stop after the first site - the self-test fixture with two sites then fails; (b) must-PASS inputs that are NOT the canonical: the two tag conditions in the opposite order, and a different unique `frequency_minutes`, both still pass; a fixture emit with `extra` keys in another order passes.

**Anchor.** The vitest contract proves consistency between three committed artifacts, which one diff can edit together; integrity is anchored OUTSIDE the commit by `scripts/sentry-alert-reference-gate.sh` (the `plan_pr` job holds `alert-reference.json` equal to the Terraform PLAN, which a hand-edited pair cannot fake) and by the daily `sentry-alert-live-fidelity.sh` probe against live Sentry.

### Guard 2 - payload allowlist and secret canary

**Property.** No value the diagnostic hands to Sentry or the pino line can be anything other than one of ten closed-enum strings (plus the constant message), whatever the input message, env or options contain.

**Assembly.** One builder produces `payload`; `tags` and `extra` are both derived from that one object; the paths into it are `deriveAgentAuthContext` (options/env), `matchAgentAuthFailure` (message), the authMode normaliser (resolver output) and the dedupe key (never emitted). Everything the SDK message, `options.env`, `options.cwd`/workspace path, the resolver's raw return and `dedupeToken` can carry is an input to prove absent from EVERY contributor to the event, not only the call args: the `captureMessage` arguments (message, tags, extra, user, fingerprint), the pino line and the breadcrumb the logger mirrors, the ambient isolation scope (`user` / request data a surrounding `withIsolationScope` could have set - the probe runs in the long-lived stream loop, outside any request scope, and the test asserts no `user` key), and the `beforeSend` boundary (`scrubSentryEvent`, which matches payload KEY NAMES against `SENSITIVE_KEY_NAMES` case-insensitively and exactly, e.g. `tag`, `token`, `secret`, `iv`, `subject`, `sender`: a payload key that collides is silently rewritten to `[Redacted]`, which would blind the diagnostic).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `userId` / `workspaceId` / a hashed id key to the payload | RED |
| 2 | Put the matched text (or any slice of the message body) into a tag, into `extra`, or into the Sentry message | RED |
| 3 | Put the env value, the key length, or a prefix of the key into the payload | RED |
| 4 | Add an eleventh key after ten compliant ones (key SET equality, not a prefix or first-key check) | RED |
| 5 | Make `matchAgentAuthFailure` return a kind for every input (the negative corpus must be non-empty and every entry asserted `null`; a floor on the corpus size) | RED |
| 6 | Make `tags` and `extra` diverge | RED |
| 7 | Let the authMode resolver's raw return flow through un-normalised (resolver returns a workspace-path-shaped string) | RED |
| 8a | Neuter the per-probe once-latch with the cross-probe debounce intact: two probes, same user and tuple, one emit | RED if two |
| 8b | Neuter the debounce with the latch intact: two probes, same user and tuple, one emit | RED if two |
| 8c | Neuter the process-wide cap: eleven distinct users inside the window emit at most ten | RED if eleven |
| 8d | Forgery: a plain assistant block (model id `claude-...`, no `is_api_error_message`) with the exact CLI text | RED if it emits |
| 9 | Rename a payload key to a name in `SENSITIVE_KEY_NAMES` or to a name on the Vector drop list (for example `match_kind` -> `tag` or `message`): the real `scrubSentryEvent` redacts it / the Better Stack path deletes it | RED |
| 9b | Emit outside `withIsolationScope`: a pre-seeded other-tenant breadcrumb or `setUser` appears on the captured event | RED |
| 10 | Let a value outside the closed `ApiKeySource` list (a path- or key-shaped string in the init message) reach `cli_key_source` | RED |

**Harness rows.** (a) Suite edit that must go RED: remove the seeded canary strings from the fixtures - a non-vacuity assertion that each canary appears in the INPUTS (env, message, cwd, resolver return, dedupe token) fails first; (b) must-PASS non-canonical: a run with `oauth_token` + `auth_mode=managed` + `sandbox=off` + `outer_wrap=true` (different enum values) passes; an input message containing a canary only inside a multi-block message (so it never matches) passes with zero events.

**Anchor.** The allowlist lives in both source and test, so one diff can widen both; the outside anchors are the CLO condition recorded in `decision-challenges.md` and this plan, the review-time `soleur:engineering:review:user-impact-reviewer` seat (mandatory at this tier), and the unchanged Sentry default `sendDefaultPii` (unset) that a widened test would not touch.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a server-side diagnostic for the Claude CLI auth-failure reply (\"Not logged in · Please run /login\") in apps/web-platform." | Proposed Solution 1-6, Phases 1-3 | mapped |
| 2 | "emit ONE routed Sentry event via reportSilentFallback(null, ...) (first arg null per the #8629 pino-mirror dedupe class" | Emit chokepoint, Guard 1 rows 1 and 4 | mapped |
| 3 | "tagged feature=agent-auth, a constant op" | `feature: "agent-auth"`, `op: "cli-auth-failure"` | mapped |
| 4 | "with SAFE extras only: credential scheme (api_key\|oauth_token), whether the auth env var was present in the built agent env (boolean), authMode (managed\|api-key), runner path (legacy\|cc-soleur-go), seccompArtifact (base\|unixdeny), hasEgress, sandbox on/off" | payload keys `credential_scheme`, `auth_env_present`, `auth_mode`, `runner`, `seccomp_artifact`, `has_egress`, `sandbox` | mapped |
| 5 | "NEVER include key material, the env value, the message body beyond a fixed enum of which pattern matched, user ids, or workspace paths." | Guard 2, secret canary, `match_kind` enum | mapped |
| 6 | "Cover both runners (server/agent-runner.ts legacy and server/cc-dispatcher.ts) through ONE shared helper" | `agent-auth-failure.ts` + wiring in Phase 3 | mapped |
| 7 | "add a Sentry issue-alert rule + alert-reference.json entry only if the existing routed-alert convention requires it for a new op" | Phase 4 (convention requires it: Research Reconciliation row 5) | mapped |
| 8 | "Tests: unit for the matcher (positive family, negative near-misses, no body leak), contract test tying emit site to any alert rule, and a real-path test with only the Sentry SDK mocked." | Phase 1 items 1, 4, 3 | mapped |
| 9 | "Also report in the PR body, as a hypothesis not a finding, that dozens of web-container egress drops to AWS IPs (e.g. 98.91.39.95) and Flagsmith getIdentityFlags failures appear in Sentry at the same time" | PR body requirements | mapped |
| 10 | "Ref #10548 and #10455, never Closes; do not touch any feature flag state." | frontmatter `closes: none`, PR body, no flag writes | mapped |
| 11 | "before pushing, run by name npx tsc --noEmit in apps/web-platform, scripts/guard-vacuity-floor.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh, plugins/soleur/test/fixture-relative-assert.test.sh and test/repo-wide-containment" | Acceptance Criteria gate list | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `server/agent-auth-failure.ts` (matcher, context, probe, tap) | "through ONE shared helper" | asked |
| `server/agent-auth-mode.ts` (authMode resolver) | "authMode (managed\|api-key)" | asked |
| `server/claude-error-signatures.ts` edit | "the message body beyond a fixed enum of which pattern matched" | asked |
| Structured `error === "authentication_failed"` arm | — | inferred - justification: the SDK types a wording-independent discriminator; text-only matching goes blind on a CLI wording change (CTO F4) |
| `cli_key_source` tag (the init message's `apiKeySource`) | — | inferred - justification: the CLI's own statement of which credential source it resolved is the single field that separates "our env var never reached the process" from "it reached it and was rejected" (CTO F10) |
| Tenant-forgery guard on the text arm, process-wide cap, `withIsolationScope` emit, try/catch plus `.catch(noop)`, constant warn on swallowed throw, the tap test file, structural-only retention check | — | inferred - justification: the deepen security and user-impact passes found a forgeable text arm that could mute the real outage's email, a flood and eviction path, other tenants' breadcrumbs riding on the event, and a process exit on a stray rejection; each is a safety property of the brief's "ONE routed event" with no user-visible scope change (CTO F13-F15) |
| `unbound` auth_mode value, decode-key table, removal checklist, factory-throw isolation, latch reset per `result` | — | inferred - justification: plan-review (spec-flow, devex, architecture) found each is needed for the event to be readable or safe: old conversations have no engine-run row, the reader needs the hypothesis mapping, and a diagnostic bug must not be reported as a sandbox failure or stall a warm Query's later turns |
| `outer_wrap` tag | — | inferred - justification: the outer wrap changes how env reaches the CLI, so it separates a competing hypothesis the listed fields cannot (CTO F6) |
| `extra` duplicating the tags | — | inferred - justification: only `extra` reaches the pino line / Better Stack, the second sink if Sentry capture is the broken part (CTO F6b) |
| 5-minute per-user debounce + per-probe once | "emit ONE routed Sentry event" | asked |
| `bindOptions` identity wrapper and the widened pin regex | — | inferred - justification: two existing census tests pin the `query({...})` literal shape; extracting a variable would red `agent-sandbox-seccomp-selector.test.ts` A6a |
| `infra/sentry/issue-alerts.tf` rule, `alert-reference.json`, README counts | "add a Sentry issue-alert rule + alert-reference.json entry" | asked |
| `test/sentry-agent-auth-failure-alert-op-contract.test.ts` | "contract test tying emit site to any alert rule" | asked |
| `test/agent-auth-failure-sentry-path.test.ts` | "a real-path test with only the Sentry SDK mocked" | asked |
| `test/agent-auth-failure-matcher.test.ts` | "unit for the matcher (positive family, negative near-misses, no body leak)" | asked |
| `test/agent-auth-failure-probe.test.ts` (context, probe, tap) | — | inferred - justification: the tap mutates an SDK-owned object in a hot shared path; its identity/order/cleanup semantics need pins or a later refactor silently stalls the stream |
| Wiring cases in `agent-runner-unix-deny-wire.test.ts` and `cc-dispatcher-real-factory.test.ts` | "Cover both runners" | asked |
| Two follow-up issues (removal-trigger with date; root-cause + friendly error pair) | — | inferred - justification: CPO sign-off condition; a temporary alert and a known user-visible gap without a tracker are invisible deferrals |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform`
- Planned files: 18 | Estimated changed lines: ~1,250 (about 750 are tests; production code about 400)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the line count crosses the threshold on test volume only; a split would have to separate the emit from its rule, and an emit with no rule is exactly the #10455 defect class (an event with nobody behind it).

## Acceptance Criteria

### Functional Requirements

- [ ] A fake SDK stream with an assistant message whose `error` is `authentication_failed`, and one with the exact `Not logged in · Please run /login` single text block, each produce exactly ONE `Sentry.captureMessage` (level error, `tags.feature = agent-auth`, `tags.op = cli-auth-failure`) in BOTH runner paths (legacy loop; cc tap), and zero `captureException` calls tagged `pino-mirror`.
- [ ] The ten tag keys are exactly `runner, credential_scheme, auth_env_present, auth_mode, cli_key_source, seccomp_artifact, has_egress, sandbox, outer_wrap, match_kind`, every value a member of its closed enum, and `extra` equals the tags (after stringification) plus `err: null` and nothing else (the helper's `null` path always sends `err`), pinned on the Sentry call AND the pino object.
- [ ] `auth_env_present` is `false` when the scheme's env var is missing or the empty string, `true` for a non-empty value, and the value is never stored anywhere reachable by the emit.
- [ ] `auth_mode` is `managed`, `api-key`, `unbound` (no engine-run row) or `unknown`; a failing or slow (> 1.5 s) resolver yields `unknown` and the event is still emitted; the real resolver is exercised against a fake `PersistenceClient`, not only injected.
- [ ] A warm Query that fails again on a later turn emits again once the 5-minute window has passed (the latch resets on every `result`), and not before it.
- [ ] The second auth-failure message in one probe, and a second probe with the same user + tuple within 5 minutes, emit nothing; a probe whose tuple differs (e.g. `credential_scheme` flipped) emits.
- [ ] The tap preserves the returned Query's identity, message order and completion, delegates `return`/`throw`, and returns a frozen/non-iterable object untouched; an observer throw never alters the stream.
- [ ] `sentry_alert.agent_auth_failure` exists, enabled, `frequency_minutes = 40` unique in the root, filters `feature eq agent-auth` AND `op eq cli-auth-failure`, email `issue_owners` + `ActiveMembers`, trigger `event_frequency_count` 1h / 0; `alert-reference.json` carries the matching `agent-auth-failure` entry; README counts read 48.
- [ ] `cli_key_source` is the init message's `apiKeySource` when (and only when) it is a member of the closed `ApiKeySource` list, else `unknown`; a stream with no init message yields `unknown`.
- [ ] No feature-flag state is read for writing or changed: `test "$(git diff --name-only origin/main...HEAD | grep -c -e feature-flags -e flagsmith -e doppler)" = 0` (merge-base diff; count form so a grep error cannot read as a pass; `grep -c` exits 1 on zero, which the `test` form absorbs); no `Closes` appears in the PR body (it carries `Ref #10455` and `Ref #10548`).
- [ ] The PR body's FIRST line answers "does merging this alone mutate production?": yes - the push-triggered Sentry root workflow creates the `agent-auth-failure` rule and the app deploy ships the observer (Sharp Edges: infra diffs).

### Non-Functional Requirements

- [ ] Secret canary (CPO condition, blocking CI): seeded fake key, fake OAuth token, fake workspace path, fake user id, the CLI message body and a canary-shaped authMode string appear in NONE of: the serialised `captureMessage` arguments, the pino line, the mirrored breadcrumb; each canary is asserted present in the inputs first.
- [ ] `server/agent-auth-failure.ts` accesses nothing from `./observability` at import time (partial `vi.mock` factories in the runner tests must keep working).
- [ ] The client/server boundary gate (`bash scripts/constraint-gates.sh` in `apps/web-platform`) shows no new violation; `agent-auth-failure.ts` is imported only from `server/`.
- [ ] CLO conditions: no user/workspace identifier (raw or hashed), IP, text or env content in the event; no `setUser`/`user` on this path; `sendDefaultPii` unset. The dedupe key holds the raw user id in an in-process map only (never emitted, never logged, asserted by a canary on every `logger.*` call); hashing it was considered and rejected because the BYOK lease already holds the raw id in the same heap.
- [ ] Tenant-forgery and flood bounds hold: a forged plain-assistant block with the exact CLI text emits nothing; the eleventh distinct-user event inside five minutes is suppressed; the emit runs inside `withIsolationScope` with breadcrumbs and user cleared.

### Quality Gates (run BY NAME on the combined tree; read exit codes and `[FAIL]` lines, not tail lines)

- [x] `cd apps/web-platform && npx tsc --noEmit` (vitest does not type-check; spawn-env literals and empty-array defaults are the known traps)
- [x] `bash scripts/guard-vacuity-floor.test.sh` (smoke: the plan adds no shell suite, so this cannot fail on this diff; it is run because the brief names it, and each new vitest contract test carries its own anti-vacuity floor - the walk finds more than zero files, the negative corpus has at least N entries)
- [x] `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- [x] `bash plugins/soleur/test/fixture-relative-assert.test.sh`
- [x] `cd apps/web-platform && npx vitest run test/repo-wide-containment.test.ts` (any new test that reads outside the app is registered in `test/repo-wide-suites.ts`; none is planned)
- [x] `cd apps/web-platform && npx vitest run test/agent-sandbox-seccomp-selector.test.ts test/sdk-query-sites.test.ts test/server/cc-dispatcher-bash-sandbox-mirror.test.ts test/cc-dispatcher-real-factory.test.ts test/agent-runner-unix-deny-wire.test.ts test/sentry-masked-dir-precreate-alert-op-contract.test.ts test/agent-auth-failure-matcher.test.ts test/agent-auth-failure-probe.test.ts test/agent-auth-failure-tap.test.ts test/agent-auth-failure-sentry-path.test.ts test/sentry-agent-auth-failure-alert-op-contract.test.ts` exits 0 (eleven explicit files; a bare `npx vitest run` would run the whole suite)
- [x] `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` from the repo root (T25 pins `**48 \`sentry_alert\` rules**` and `(48 alert rules total)`)
- [x] `cd apps/web-platform && bash scripts/constraint-gates.sh` (client/server boundary: no new violation)
- [x] From the repo root: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md` reports 2 guard entries, exit 0
- [x] `bash scripts/lint-orphan-test-suites.sh` once the new test files are tracked (a new suite that no runner registers is the silent-green gap #11045 closed)
- [x] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-agent-auth-failure-diagnostic` passes
- [x] From the repo root: `npx --no-install markdownlint-cli2 knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md knowledge-base/project/specs/feat-one-shot-agent-auth-failure-diagnostic/tasks.md` reports 0 issues
- [ ] Every literal command in this plan (the discoverability `jq`, the gate list) was run once before the plan was committed; the `jq` returns `true` only after the reference entry exists (it prints `null` on the unmodified tree)
- [ ] `frequency_minutes` re-checked against `origin/main` after the LAST merge of `origin/main` (provisional until then)
- [ ] The affected-test gate printing `ran=- of=-` / `budget-deferred` is no verdict; the named runs above are the evidence

### Follow-ups and PR body (CPO conditions)

- [x] Issue A (before merge): "downgrade, then remove, the agent-auth-failure diagnostic alert" (CTO F11). Step 1: within 48 hours of the first recorded real event (its tag tuple recorded on #10455), a PR drops the rule's email action and keeps the Sentry issue and the pino line. Step 2: the rule, its `alert-reference.json` entry, the README counts and entry, both guard tests, the wiring pins, the widened regex and the module header checklist are removed when Issue B merges or 30 days after the first event, whichever comes first. Milestone from `knowledge-base/product/roadmap.md`; labels verified with `gh label list --limit 200` before filing. Filed: #11085.
- [x] Issue B (before merge): root-cause fix and a friendly user-visible error as one P1 pair with a named owner; the matcher must keep running on the raw text before any rewrite. The body proposes an escalation for the operator to confirm: if the cause fix has not merged 14 days after the first recorded event, ship the friendly error alone (a schedule call, recorded as an operator row in `decision-challenges.md`, not decided here). Filed: #11086.
- [ ] PR body states this does not resolve the outage; includes a "Hypothesis (not a finding)" paragraph: dozens of web-container egress drops to AWS IPs (e.g. 98.91.39.95) and Flagsmith `getIdentityFlags` failures appear in Sentry at the same time; issue WEB-PLATFORM-2K is old noise since 2026-06-10; no causal claim is made.
- [ ] Post-merge, read-only, BLOCKING (not advisory): while the outage persists, a Sentry query for `feature:agent-auth` within 15 minutes of a Concierge request returns the event; the tuple is recorded on #10455.

## Test Scenarios

(unit = pure functions; integration = real logger + real `reportSilentFallback` + real option builders, Sentry SDK spied; no e2e.)

- unit - Given `{type:"assistant", error:"authentication_failed", message:{content:[{type:"text",text:"anything"}]}}`, when matched, then `structured`.
- unit - Given a single text block `Not logged in · Please run /login`, when matched, then `not_logged_in`; likewise each family member and the `Not logged in. Run claude auth login to authenticate.` variant.
- unit - Given `Invalid API key format. API key must contain only alphanumeric characters, dashes, and underscores.`, `You are not logged in to GitHub; run gh auth login`, `not logged in · please run /login`, a 300-char message starting with `Not logged in`, a two-block message, a text+`tool_use` message, a `result` with `is_error:false` quoting the text, a `stream_event`, `null`, `42`, then `null` for each.
- unit - Given a plain assistant block (`model: "claude-sonnet-5-5"`, no `is_api_error_message`) with the exact text `Not logged in · Please run /login`, then `null` and zero emits (forgery); given the same text with `model: "<synthetic>"`, then `not_logged_in`; given the real message with both the text and `error: "authentication_failed"`, then `not_logged_in` (text first).
- unit - Given eleven distinct users failing inside five minutes, then ten emits and a suppressed counter of one, with no warn log.
- integration - Given a pre-seeded outer scope (`setUser`, another tenant's breadcrumb), when the probe emits, then the captured event carries neither and the outer scope is unchanged.
- unit - Given the captured real stream (init with `apiKeySource: "none"`, then the synthetic assistant message, then the result), when observed, then one emit with `cli_key_source = none` and `match_kind = structured`; given init values `ANTHROPIC_API_KEY`, `oauth`, a value outside the list, and no init at all, then `ANTHROPIC_API_KEY`, `oauth`, `unknown`, `unknown`.
- unit - Given options with `env.ANTHROPIC_API_KEY = ""`, when the context is derived with scheme `api_key`, then `auth_env_present = "false"`; with a non-empty value, `"true"`; the OAuth scheme reads only `CLAUDE_CODE_OAUTH_TOKEN`.
- unit - Given a `ghToken` or `webEgress` build, then `has_egress = "true"`; Given `sandboxUnixDeny: true` and no egress, then `seccomp_artifact = "unixdeny"`; Given a builder that returned `undefined`, then every derived field is `unknown` and nothing throws.
- unit - Given a resolver returning `"managed"`, `"api-key"`, `"codex"`, a workspace-path-shaped string, `null`, a rejection, and a never-settling promise (fake timers past 1.5 s), then the tag is `managed`, `api-key`, `unknown`, `unknown`, `unknown`, `unknown`, `unknown`.
- unit - Given two matching messages in one probe, then one emit; Given a second probe, same user, same tuple, inside 5 minutes, then zero; after 5 minutes, one; with `credential_scheme` flipped, one.
- unit - Given a generator-backed Query with extra methods, when tapped, then `tap(q) === q`, a `for await` sees every message in order, a `break` runs the generator's `finally`, a thrown error propagates unchanged, and `Object.freeze(q)` / a non-iterable are returned untouched.
- integration - Given the canary-laden fixtures (fake key, token, workspace path, user id, message body), when the real path runs, then the serialised Sentry call arguments, the breadcrumb and the pino line contain none of them and `captureException` has no `pino-mirror` capture.
- integration - Given `startAgentSession` driven with a mocked `query` that streams the auth-failure message, then one `reportSilentFallback(null, {feature:"agent-auth", tags.runner:"legacy"})`; given `realSdkQueryFactory` with a mocked `sdkQuery` streaming it, then one with `runner:"cc-soleur-go"`; given a clean stream, zero.
- integration (contract) - Given the repo sources, then the Guard 1 matrix holds; the harness self-tests (two-site extractor, reordered conditions, alternate frequency) pass.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Technical forks F1-F9 (including F6b) ruled by the CTO agent on 2026-10-25 and recorded in `knowledge-base/project/specs/feat-one-shot-agent-auth-failure-diagnostic/decision-challenges.md`. CPO advisory: sign-off yes with conditions (carried above). CLO advisory: closed-enum payload is not personal data; no gdpr-gate run needed; conditions carried above. No UI surface (Product/UX gate: none); no ADR or C4 change - the only new edge is the runner-to-Sentry emit that already exists, and no new store, substrate or trust boundary is introduced. No infrastructure beyond one rule in the existing Sentry root (applied by the existing push-to-main workflow, same path as #10892).

**gdpr-gate (plan Phase 2.7, trigger (b) single-user incident threshold; advisory):** this is not legal review. The five v1 checks do not fire: no schema column or migration (Art. 6, Art. 5(1)(e)), no FK to `users` (Art. 17), no new vendor or SDK (Chapter V: Sentry is the existing subprocessor), no special-category column (Art. 9). Nothing Critical, nothing Important. Suggestion only: keep the event free of any identifier (raw or hashed), which is also the CLO condition above.

**Deepen passes recorded:** security-sentinel (1 P0 forgery path, 3 P1), user-impact-reviewer (5 P1), observability-coverage-reviewer (1 P1 layer citation, 3 P2), test-design-reviewer (2 P1 vacuity risks), pattern-recognition-specialist (3 P2 reuse points); each folded in above or recorded as a taste row in `decision-challenges.md`.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan).

## Non-Goals

- No thrown-error arm (CTO F12, declined): the credential-free local run produced a normal synthetic assistant message and exit code 0, not a throw; triggers to add it are in the Decode key limitation.
- No fix for the outage and no change to the text users see (CPO: separate P1 pair, tracked by Issue B).
- No change to `server/pdf-chapter-router.ts` (a single routing turn that inherits the server env and runs no Concierge session) or to the scheduled-agent spawns in `server/inngest/` (they build their own env through a per-function allowlist and use no BYOK lease): the observed outage is on the two runners, and the same helper can be attached to another consumer later without a redesign. This is a coverage statement about the population measured (the sites in `sdk-query-sites.test.ts`), not a claim about unmeasured paths.
- No new Sentry or Better Stack surface beyond the one rule; no change to `sendDefaultPii`, `beforeSend` or `server/sentry-scrub.ts`.
- No feature-flag read for writing, flip or Doppler change.

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| Tap mutates an SDK-owned object | In place, identity preserved, `return`/`throw` delegated, frozen/non-iterable no-op, pinned by tests (CTO risk 1). |
| A user-revoked BYOK token also matches and pages ops | Declared temporary diagnostic; constant message -> one issue; 40-minute re-notify; Issue A downgrades the email within 48 hours of the first event and removes the rule with Issue B or at 30 days (CTO F11). |
| The app deploys and emits before the Sentry root workflow has created the rule | A rule notifies only for events after it exists. The post-merge check first confirms the apply run succeeded and the rule is in the reference (`jq ... .enabled` = `true`), then reads the event; an event earlier than the rule is capture proof, not delivery proof. |
| `cli_key_source` non-`none` values have no local fixture | The decode table marks them UNVERIFIED; the first production event is the fixture, recorded on #10455. `auth_env_present` alone cannot separate "reached options, not the process" because `buildAgentEnv` sets the variable last whenever the lease value is non-empty. |
| Warm cc Query serves many turns | Latch resets per `result`; the debounce is the rate limit. |
| `frequency_minutes = 40` collides after a sibling merge | Re-check after the last `origin/main` merge; the contract test asserts uniqueness across all root files. |
| A hand-built `alert-reference.json` entry differs by a byte | `plan_pr` gate prints the expected file; copy it from the `sentry-alert-reference-expected-<run-id>` artifact. |
| Pino-mirror dedupe drops the tagged capture | Literal `null` first argument on every path, asserted by source parse and by a spy in the real-path test. |
| The authMode lookup mints a JWT against the user's own `precheck_jwt_mint` ceiling (60/hour) while the user is retrying through an outage | The lookup runs only after a claimed match: at most one per user per tuple per 5 minutes, so at most 12 per hour per user against the 60 ceiling, plus the process-wide cap; the race loser gets `.catch(noop)`; a test pins "no lookup without a claimed match". |
| Hot-path cost | Fast path checks `type`/`error` only; regex only on single-text-block messages <= 200 chars; DB read only after a claimed slot, at most one per tuple per 5 minutes per user. |
| Worktree lacks `node_modules` | Phase 0 installs before any `tsc`/`vitest`. |

## References

- Precedent: PR #10892, `server/agent-runner-sandbox-config.ts` (`op: "masked-dir-precreate"`), `test/sentry-masked-dir-precreate-alert-op-contract.test.ts`, `test/agent-sandbox-precreate-sentry-path.test.ts`.
- `apps/web-platform/infra/sentry/README.md` (rule convention, counts, reference regeneration), `server/README.md` (import boundary).
- `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` (briefing fix agents on the repo-global ratchets) and the 2026-10-23 learning.
- Related: #10455 (hosted Bash outage follow-ups), #10548 (SDK Bash smoke follow-through) - both Ref only.
