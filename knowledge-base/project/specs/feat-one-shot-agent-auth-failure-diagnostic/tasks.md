# Tasks: agent auth-failure diagnostic

Plan: `knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md`
Branch: `feat-one-shot-agent-auth-failure-diagnostic`. Refs #10455 and #10548; never Closes either.

## Phase 0: Setup and baseline

- 0.1 Install dependencies in `apps/web-platform` (the worktree has no `node_modules`).
- 0.2 Run the baseline suites named in the plan (Phase 0) and record exit codes and counts.
- 0.3 Re-grep direct `.next(` callers in `server/soleur-go-runner.ts` and `server/cc-dispatcher.ts` (tap boundary).

## Phase 1: RED tests first

- 1.1 `test/agent-auth-failure-matcher.test.ts`: positive family (real U+00B7 separator), negative near-misses, FORGERY row (plain assistant block with the exact text emits nothing), text-first ordering, 200-char adversarial-whitespace timing row, no-leak property, non-object inputs, negative-corpus floor.
- 1.2 `test/agent-auth-failure-probe.test.ts`: context derivation from real `buildAgentQueryOptions` (single seccomp predicate), once-latch reset per `result`, debounce per user and tuple, process-wide cap of 10 per 5 minutes, `cli_key_source` from init, authMode normalisation and timeout, real resolver against a fake `PersistenceClient`, no lookup without a claimed match, claim release on emit failure, structural no-retained-`options` check, no-unhandled-rejection case, factory-throw fallback.
- 1.2b `test/agent-auth-failure-tap.test.ts`: the tap against a fixture modelling the REAL Query shape (own `next`/`return`/`throw`, iterator method returning a separate single-use stream), identity, order, no added microtask, `break`, throw, frozen and non-iterable, no double-wrap, plus a real `consumeStream` path case.
- 1.3 `test/agent-auth-failure-sentry-path.test.ts`: real logger and `reportSilentFallback`, Sentry SDK spied (real `withIsolationScope`), captured real stream fixture (trimmed, synthetic ids), secret canary in whole and derived forms across call args and the logger's breadcrumb mirror with a positive control (LOG_LEVEL set), real `scrubSentryEvent` leaves every key intact (control: a key named `tag` is redacted), payload keys absent from the sensitive and Vector drop-list sets, pre-seeded outer scope (`setUser`, other-tenant breadcrumb) absent from the event, extra equals payload plus `err: null`.
- 1.4 `test/sentry-agent-auth-failure-alert-op-contract.test.ts`: Guard 1 (emit sites by walk, op set equality, null first arg, rule fields, unique frequency, reference entry via `toEqual`), harness self-tests.
- 1.5 Extend `test/agent-runner-unix-deny-wire.test.ts` and `test/cc-dispatcher-real-factory.test.ts` with auth-failure stream cases plus source pins (stub the resolver module; `vi.waitFor` the emit).
- 1.6 Confirm each new test fails for the right reason before any implementation.

## Phase 2: Implement the leaf modules

- 2.1 `server/claude-error-signatures.ts`: add `CLI_AUTH_FAILURE_REPLIES`, header sentence, SDK-bump re-derive note.
- 2.2 `server/agent-auth-failure.ts`: matcher (cheap-first, text then structured, CLI-set-field requirement for the text arm), context derivation, payload builder, probe (try/catch, `.catch(noop)`, constant warn on swallowed throw), tap, local TTL map with a global-cap key and test reset seam, emit inside `withIsolationScope` with breadcrumbs and user cleared, removal checklist in the header.
- 2.3 `server/agent-auth-mode.ts`: `makeAuthModeResolver` (null row maps to unbound), mint-cost comment.

## Phase 3: Wire the runners and widen one pin

- 3.1 `server/agent-runner.ts`: probe, `authProbe.bindOptions(buildAgentQueryOptions({...}))`, `void authProbe.observe(message)` at the loop top.
- 3.2 `server/cc-dispatcher.ts`: guarded probe and `bindOptions` (fallback to no-op probe, raw options, untapped Query on a throw), `tapAgentAuthFailure(sdkQuery({...}), authProbe)`; confirm `withIsolationScope` is exported by the installed `@sentry/nextjs`.
- 3.3 `test/server/cc-dispatcher-bash-sandbox-mirror.test.ts`: widen the source pin with the wrapper REQUIRED; note the wrapper in the A6a census comment.
- 3.4 `git grep` every changed literal across `test/` and `scripts/` (`options: buildAgentQueryOptions`, `recordCcSeccompArtifact(`, `const q = query(`).

## Phase 4: Alert rule, reference, counts

- 4.1 `infra/sentry/issue-alerts.tf`: `sentry_alert.agent_auth_failure` (frequency 40), comment block with the decode key and lifecycle, updated taken-list.
- 4.2 `infra/sentry/alert-reference.json`: key-sorted `agent-auth-failure` entry derived from the masked-dir entry shape.
- 4.3 `infra/sentry/README.md`: both T25 strings to 48, the 46/45 sentence, issue refs, decode table, Better Stack query, lifecycle.

## Phase 5: Verification and hand-off

- 5.1 Run every gate in the plan's Quality Gates by name on the combined tree; read exit codes.
- 5.2 Re-check `frequency_minutes = 40` after the last merge of `origin/main`.
- 5.3 File Issue A (downgrade the email within 48 hours of the first event, remove with Issue B or at 30 days) and Issue B (root-cause fix plus friendly error; proposes an escalation date for the operator to confirm); verify labels exist first.
- 5.4 PR body: first line answers "does merging this alone mutate production?"; states it does not resolve the outage; Refs only; hypothesis paragraph (egress drops to AWS IPs such as 98.91.39.95 and Flagsmith `getIdentityFlags` failures appear in Sentry at the same time, WEB-PLATFORM-2K is old noise since 2026-06-10, no causal claim); renders `decision-challenges.md`.
- 5.5 Post-merge, read-only: confirm the apply run succeeded and the rule is in the reference, then query Sentry for `feature:agent-auth`; record the tag tuple on #10455.
