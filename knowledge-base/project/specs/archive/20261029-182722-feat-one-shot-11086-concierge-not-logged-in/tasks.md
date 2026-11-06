# Tasks: fix the Concierge raw "Not logged in" line (root cause plus friendly error)

Plan: knowledge-base/project/plans/2026-10-29-fix-concierge-not-logged-in-friendly-error-plan.md
Issue: Ref #11086 (never Closes), Ref #10455, Ref #11085. All paths below are under `apps/web-platform/` unless stated.

## Phase 0 - RED tests first

- 0.1 Write `test/oauth-token-shape.test.ts` (allowlist accepts a generated oat alphabet; lease predicate classes `api_key_shaped | embedded_whitespace | blank`; must-pass corpus incl. padded/dotted/newline/sid; property: nothing the allowlist accepts is classified)
- 0.2 Write `test/agent-auth-cli-contract.test.ts` (bundled binary under `env -i`, synthesized values only; dropped corpus replies exactly the not-logged-in line offline; valid shape is USED against a loopback stub returning 401 via `ANTHROPIC_BASE_URL`; skip is visible locally, hard FAIL when `CI` is set)
- 0.3 Extend `test/api-keys-oauth-gate.test.ts` (400 `oauth_token_shape_invalid`, RPC not called, body never echoes the value)
- 0.4 Extend `test/byok-lease-credential-type.test.ts` (dropped oauth row throws `oauth_unusable`, buffer zeroized, api row never read, every class iterated, closed `shape_class` event, canary absent from every sink)
- 0.5 Write `test/agent-auth-user-message.test.ts` (copy cell for every kind x scheme incl. neutral null-scheme cell; deep-frozen input not mutated; multi-block/tool_use message stays raw; `session_expired` non-terminal)
- 0.6 Write `test/agent-auth-import-boundary.test.ts` (agent-auth-match.ts and agent-auth-user-message.ts import none of agent-auth-failure, agent-auth-mode, @sentry/*, the probe)
- 0.7 Write `test/agent-auth-friendly-error-wire.test.ts` (cc: REAL tap + real runner; legacy: REAL `createAgentAuthFailureProbe`; probe emitted on the raw message; friendly text streamed and persisted; `stream_end` before the `key_invalid` frame; one frame per turn; chapter-active turn has no prefix; forgery gate preserved; lease-time `oauth_unusable` yields one Sentry event, no `session_id` clear)
- 0.8 Extend client tests: `ws-zod-schemas` parse of `credentialScheme`, `chat-surface` title/label pair, reducer (bubble not `interrupted`), keep `error-states.test.tsx`, `ws-client-key-invalid-teardown.test.tsx`, `ws-client-key-invalid-source-gate.test.ts` green
- 0.9 Confirm every new test fails on `main`

## Phase 1 - shared shape module and matcher extraction

- 1.1 Create `server/oauth-token-shape.ts` (no mention of the OAuth env var name or `OAUTH_ENV_VAR`)
- 1.2 Create `server/agent-auth-match.ts` by moving the pure matcher out of `server/agent-auth-failure.ts`; leave import/re-export plus pointer comment in the old file
- 1.3 Amend the REMOVAL CHECKLIST text in `server/agent-auth-mode.ts` (steps 1, 2, 6)

## Phase 2 - write boundary

- 2.1 `app/api/keys/route.ts` oauth branch: allowlist check after `.trim()`, before encryption; precise non-echoing message (API-key-shaped prefix gets the "looks like an API key" wording)

## Phase 3 - lease boundary

- 3.1 `server/byok-lease.ts`: `oauth_unusable` cause (both union copies), guard after `assertAliveAfterDecrypt` and before the slot assignment, zeroize then throw, `reportSilentFallback(null, ...)` with closed `shape_class` only
- 3.2 `mapByokLeaseCauseToErrorCode` case (`: never` rail) -> `key_invalid`

## Phase 4 - friendly error, cc path

- 4.1 Create `server/agent-auth-user-message.ts` (copy table, `rewriteAgentAuthFailure`, `buildAuthFailureFrame`)
- 4.2 `server/soleur-go-runner.ts`: rewrite in `consumeStream`; short-circuit past prefix/rotation/`recordAssistantBlock`; `pendingAuthNotice` flag; `onAgentAuthFailure` fired from `handleResultMessage` after `onTextTurnEnd`; warm-Query eviction (verify `closeQuery` semantics); skip the runner-catch mirror for `oauth_unusable`
- 4.3 `server/cc-dispatcher.ts`: wire `onAgentAuthFailure`; `oauth_unusable` arm above the generic `else` (frame via builder, no `session_id` clear, no second mirror)

## Phase 5 - legacy path

- 5.1 `server/agent-runner.ts`: rewrite before `fullText`/stream/persist; frame after `stream_end` in the result branch; the two `handleSessionError` sends use the builder
- 5.2 `server/ws-handler.ts`: `startAgentSession` catch uses the builder

## Phase 6 - client

- 6.1 Define the `"api_key" | "oauth_token"` literal once in `lib/`; add optional `credentialScheme` to `lib/types.ts` error variant and `lib/ws-zod-schemas.ts` (`_SchemaCovers` forces both)
- 6.2 `lib/ws-client.ts` `key_invalid` branch: use `msg.message` + scheme only when a recognised `credentialScheme` is present; otherwise byte-identical
- 6.3 `components/chat/chat-surface.tsx`: title/label from the enum ("Claude Sign-in Failed" / "Update token" for oauth_token)

## Phase 7 - records and gates

- 7.1 Comment-only edit in `server/claude-error-signatures.ts` (three measured wordings stay `structured`; Cloud-gateway lead closed as status renderer)
- 7.2 ADR-048 one-sentence addendum; new ADR (ordinal 308, re-verify against all remote refs) via `soleur:architecture`
- 7.3 Post-mortem root-cause addendum (mechanism, evidence table, what is unverified)
- 7.4 `plugins/soleur/test/c4-count-parity.test.sh` green
- 7.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; web-platform vitest suite per `package.json` `scripts.test`; `npx markdownlint-cli2` on plan and tasks
- 7.6 Run the discoverability command: `rg -c "oauth-credential-unusable" apps/web-platform/server/byok-lease.ts` prints `1`

## Ship-time (not code)

- S.1 PR body: `Ref #11086`, `Ref #10455`, `Ref #11085`; `## Changelog`; decision-challenges rendered
- S.2 File the `action-required` issue (operator re-saves the subscription token; owner operator; review date deploy + 3 days)
- S.3 One-line pointer comment on #11085
- S.4 Tracked follow-ups already filed: #11524 (remove-token action), #11525 (post-`key_invalid` chat lifecycle)
