---
title: "fix: the Concierge shows the raw Claude CLI 'Not logged in' line - root cause plus a friendly error"
type: fix
date: 2026-10-29
slug: concierge-not-logged-in-friendly-error
branch: feat-one-shot-11086-concierge-not-logged-in
issue: 11086
refs: [11086, 10455, 11085]
closes: none
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: the Concierge shows the raw Claude CLI "Not logged in" line - root cause plus a friendly error

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** Research Insights (measured CLI table, plan-review dispositions), Part 1, Part 2, Guard Contract (3 guards), Observability, Domain Review, Acceptance Criteria.
**Agents used:** learnings-researcher, CTO (rulings F1-F13, three rounds), CPO (two passes), plan-review panel of seven (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, UX lead, CPO), plus bounded local measurement (bundled CLI binaries, `env -i`, synthesized values) and code verification.

### Key Improvements

1. Root cause reproduced locally instead of inferred: the exact Sentry tuple is produced by a stored subscription-token value of an API-key shape or with an embedded space; the "Cloud gateway" lead is closed as the `claude auth status` renderer.
2. Review-driven corrections that change behavior: the `key_invalid` frame is sent only for terminal kinds and only after `stream_end` (a mid-stream frame would turn the friendly bubble into an interrupted chip); the lease predicate is narrowed to measured classes so a future token shape is never locked out; the matcher is extracted into a permanent module so the #11085 removal checklist cannot delete what the friendly error depends on; one frame builder covers all four producers of the frame.
3. Scope trimmed where reviewers showed no property bought (`BYOK_LEASE_CAUSES` edit, source-grep and logger-scan tests, a second warn latch); two real gaps filed as tracked follow-ups (#11524, #11525).

### New Considerations Discovered

- The legacy runner has no tap: it calls the probe inline, so the "matcher before rewrite" guarantee needs a per-runner test (Guard 2).
- Old browser tabs parse the error frame with the previous strict schema and drop a frame carrying the new key (accepted for the rollout window; the persisted bubble still shows).
- The deepen halts ran mechanically: Phase 4.6, 4.7, 4.8, 4.11 (`lint-guard-contract.py`: 3 entries, green), 4.12 pass; 4.10, 4.13, 4.55 not triggered (no store, no new autonomous task, no downtime operation). Phase 4.9 matches the UI glob superset through `components/chat/chat-surface.tsx` with no committed `.pen`; resolved as the "pure copy" exclusion and recorded as a challengeable taste row in `decision-challenges.md` because Pencil Desktop is unavailable here.
- Cited issues verified live (all OPEN): #11086, #10455, #11085, #11524, #11525, #3242, #3243, #3374, #3280, #8629; cited rule ids verified active in `AGENTS.md`/`AGENTS.rules.md`.

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this one-shot branch.

## Overview

Concierge turns surfaced the Claude CLI's own sign-in prompt to the user and ran no command. Two deliverables ship together:

1. **Root cause.** The first real Sentry tuple (`runner=cc-soleur-go`, `credential_scheme=oauth_token`, `auth_env_present=true`, `auth_mode=api-key`, `cli_key_source=none`, `match_kind=not_logged_in`) is reproduced locally by a stored subscription-token value that the bundled CLI silently drops. The server stores that value with no validation and hands it to the CLI unchanged. The plan closes the class at the write boundary, at the lease boundary, and with a contract test against the bundled binary.
2. **Friendly error.** Both runners replace the raw CLI line with server-authored copy chosen from the closed `match_kind` and the credential scheme, and send one `key_invalid` frame so the existing card carries a recovery action. The diagnostic matcher still runs on the raw text first.

PR body uses `Ref #11086`, `Ref #10455`, `Ref #11085` (CTO ruling F6: the mechanism is established, the operator's stored row was never read, so the issue closes on post-deploy evidence). Nothing from #11085 is removed here.

## Premise Validation

Checked 2026-10-29. Held: #11086 OPEN, #10455 untouched context, #11085 OPEN ("downgrade, then remove the diagnostic"); `server/agent-auth-failure.ts`, `server/byok-lease.ts`, `app/api/keys/route.ts`, `components/settings/key-rotation-form.tsx` all exist on this branch. Collision pre-check: the only open PR naming #11086 is this branch's own draft PR #11523; the foreign `test-all.sh` processes belong to unrelated worktrees. Stale/adjusted premises are listed under Research Reconciliation. ADR corpus: ADR-048 (operator CC oauth credential selection) already says the oauth read is "fail-closed - never a silent api_key fallback", which the CTO ruling extends rather than contradicts; ADR-272 covers the env-injection isolation this plan must not weaken.

## Research Reconciliation - Spec vs. Codebase

| Claim (issue / brief) | Reality (verified) | Plan response |
|---|---|---|
| "Happens under both authentication modes (managed and api-key) and with a freshly validated key." | `byok-lease.ts fetchAgentCredentialIntoSlot` prefers the `anthropic_oauth` row whenever `CC_OAUTH_ENABLED` is on, **regardless of the conversation's persisted `authMode` binding**. The binding is an engine-egress-policy notion; no credential-choice code reads it. A validated API key is irrelevant while an oauth row exists. | Explains the "both modes" symptom. The binding/scheme mismatch (the brief's "first lead") is benign by design and **not** the cause; record it so nobody re-chases it. |
| "BYOK customers who paid have no recovery path." | Only `ADMIN_USER_IDS` can store an oauth row (`/api/keys` returns 403 otherwise). The dead-credential class is operator-only; tenants reach the same raw-line symptom only through their own revoked/invalid API key. | Friendly error covers every matcher hit for both schemes; tenant copy names only the Anthropic API key (legal audit 2026-10-06). |
| "Decode: the CLI saw no credential although the token was a non-empty string, so it points at the token itself or the hand-off." | **Measured** (Research Insights, table): the CLI silently drops a `CLAUDE_CODE_OAUTH_TOKEN` value that starts `sk-` but is not an `sk-ant-(oat\|sid)NN-<non-space>` token, or is blank, with **no network call**, and replies exactly `Not logged in · Please run /login`. | Root cause class = unusable stored value. Which of (API key pasted via the toggle, wrapped `claude setup-token` copy with an embedded space) the operator's row is stays **unverified** (secret, not read). |
| Lead: "Not logged in. This session uses a Cloud gateway; ..." is uncovered by the matcher. | Bounded strings read of the bundled binary: both "Not logged in" variants sit in the `claude auth status` text renderer (`if(!S)g.push(T?"...Cloud gateway...":"Not logged in. Run claude auth login...")`), next to `loggedIn`/`orgName` keys. The stream reply is the `· Please run /login` constant. | Close the lead as "status renderer, not a stream reply" with that evidence; no matcher change. |
| Brief: `Closes #11086` only if both parts ship. | Both parts ship, but the operator's stored row is unread; CTO ruling F6. | `Ref #11086`; closure criterion below; one `action-required` issue for the operator's re-save. |

## Research Insights

### Property List (Phase 0.6b)

- P1. A stored subscription-token value the CLI is proven to drop is never handed to the CLI.
- P2. A malformed subscription token cannot be saved; the operator is told why, without the value echoed.
- P3. A user whose credential fails sees an actionable message and a path to Settings, never the raw CLI line, in the live turn and in reloaded history.
- P4. The diagnostic matcher/probe still sees the raw text of every turn, unmodified.
- P5. No credential value, prefix or fragment reaches Sentry, pino, the WS frame or a test snapshot.
- P6. The billing basis never changes silently (no subscription-to-API fallback).

### Cut List (Phase 0.6b)

| Mechanism | Property bought | Already covered by / why cut |
|---|---|---|
| New `match_kind` values for the three measured wordings | none | The structured `authentication_failed` arm already classifies them; widening the tag enum enlarges what #11085 deletes (F4). |
| New WS errorCode (e.g. `agent_auth_failed`) | P3 | `key_invalid` + the optional `credentialScheme` field covers it with no union widening (F2, F7). |
| Fallback from oauth row to api_key row on a dropped value | none (violates P6) | Fail closed with `oauth_unusable` (F1). |
| Render-time/history rewrite in the client | P3 for old rows | Forward-only (F5); a second matcher consumer is a worse cost than inert old text. |
| `Cloud gateway` matcher pattern | none | Status renderer, not a stream reply. |
| Tag/enum additions to the temporary diagnostic | none | Telemetry for the new lease guard lives in the lease, not in `agent-auth-failure.ts`. |

### Plan-review dispositions (2026-10-29, seven reviewers)

| Finding | Disposition |
|---|---|
| DHH 1-2: delete the lease guard, its cause plumbing and the contract test | **Kept.** The lease event's `shape_class` is the only instrument that can close #11086 with evidence (CTO F6); the contract test is the only thing that re-derives the CLI's behavior on an SDK bump. Operator-requested root-cause scope (ask 1) cannot be cut. |
| DHH 3: one inline check instead of a module | **Kept as one module** used by route and lease (a single source for both boundaries); lease predicate narrowed to measured classes (CTO F10). |
| DHH 4-5: drop `credentialScheme`; bubble or card, not both | **Kept** per CTO F7/F8 (existing tests stay byte-identical; the persisted bubble is the only recovery path after reload). |
| Simplicity 1: helper fail-open wrapper | **Applied**: no second warn latch; fail-open is the matcher's own try/catch composed with a lookup that cannot throw. |
| Simplicity 2 / Kieran 8: `BYOK_LEASE_CAUSES` | **Cut**: that path calls `getRestApiKey()` only. |
| Simplicity 4: source-grep and logger-scan tests, sink self-check | **Cut.** |
| Simplicity 5: ADR/C4 weight | **Partly applied**: ADR-048 gets one sentence; Part 2 gets its own ADR (architecture finding 8); only `c4-count-parity` runs. |
| Kieran 1, architecture 2, UX 1, CPO 1, spec-flow 7: frame mid-stream, `session_expired` teardown | **Applied**: frame after `stream_end`; terminal kinds only. |
| Kieran 3: contract arm (ii) not hermetic | **Applied**: loopback stub. |
| Kieran 4, architecture 4: predicate over-claims | **Applied**: measured classes only; newline not guarded. |
| Kieran 5-6: multi-block message, chapter prefix | **Applied**: single-text-block only; short-circuit past prefix logic. |
| Architecture 1 | **Applied**: matcher extracted (CTO F9). |
| Architecture 3, 5 | **Applied**: per-runner Guard 2; one frame builder, `ws-handler.ts` added. |
| Spec-flow 1: operator has no way to remove a dead oauth row | **Deferred**, tracked #11524. |
| Spec-flow 2, 10; UX 2-3: post-teardown composer, multi-tab, card lifecycle | **Deferred**, tracked #11525 (pre-existing `key_invalid` behavior). |
| Spec-flow 3: warm Query reuse | **Applied**: eviction after a terminal failure. |
| Spec-flow 4, CPO 4: null scheme / managed credential | **Applied**: neutral cell; the lease only ever returns an operator oauth token or the user's own API key (verified), so no platform-supplied credential reaches a tenant. |
| Spec-flow 5 | **Accepted**: a lease-time failure persists no assistant row, as every existing lease-failure path. |
| Spec-flow 8 | **Accepted**: oauth tokens cannot be validated by an unauthenticated probe (route comment); shape-only at save. |
| CPO 2-3 | **Applied**: dated-pair closure evidence; action-required issue with owner and review date; "Nothing was billed to your API key." in the `oauth_unusable` copy. |

### Measured CLI behavior (bundled SDK binary claude 2.1.284 and @anthropic-ai/claude-code 2.1.293, `env -i`, HOME in scratch, FAKE values only, 2026-10-29)

Value placed in `CLAUDE_CODE_OAUTH_TOKEN` -> result text (system/init `apiKeySource` is `none` in every row):

| Value shape (synthesized) | Result |
|---|---|
| unset | `Not logged in · Please run /login` |
| `sk-ant-api03-...`, `sk-ant-api02-...`, `sk-ant-admin01-...`, `sk-ant-X`, `sk-X`, `sk-proj-...` | `Not logged in · Please run /login` (dropped, no network) |
| `sk-ant-oatAAAA` (no dash), `sk-ant-oat01-AAAA BBBB` (embedded space), tab-embedded, `" "` (blank), `" sk-ant-api03-X"` | `Not logged in · Please run /login` (dropped, no network) |
| `sk-ant-oat01-...`, `sk-ant-oat02-...`, `sk-ant-oat01-` (empty tail), `sk-ant-oat01-A.B`, `sk-ant-oat01-A+B=`, leading/trailing whitespace around a valid oat value | used -> `Failed to authenticate. API Error: 401 OAuth access token is invalid.` |
| `sk-ant-sid01-...` | used -> `...401 Credential is invalid.` |
| non-`sk-` strings (`garbage`, `garbage with space`, quoted, `Bearer ...`, upper-case) | used -> `...401 Invalid bearer token.` |
| `sk-ant-oat01-AAAA\nBBBB` (embedded newline) | `Invalid auth token · Fix external auth token · Invalid Authorization header value from CLAUDE_CODE_OAUTH_TOKEN: it contains a line break` |
| API-key-shaped value in `ANTHROPIC_API_KEY` | `Invalid API key · Fix external API key` |

Every non-used row's assistant message is `model: "<synthetic>"`, `error: "authentication_failed"`, `is_api_error_message: true`. The observed CLI rule is: any `sk-`-prefixed value that is not `sk-ant-(oat|sid)NN-<non-space>`, or a blank value, is dropped. The lease predicate enforces only the measured subset (below), applied to the **trimmed** value `t`: `t === ""` OR `/^sk-ant-(?:api|admin)/.test(t)` OR (`t.startsWith("sk-")` AND `/[ \t]/.test(t)`). The three non-dropped wordings above are not in `CLI_AUTH_FAILURE_REPLIES`; they classify as `structured` (CTO F4).

### Institutional learnings carried in

- `2026-10-25-a-diagnostic-that-can-go-blind-must-say-so-...md`: a diagnostic's silence has three meanings; do not write "undocumented"/"only" from a truncated read.
- `2026-06-02-brainstorm-framing-split-flips-tos-verdict-...md`: both-keys precedence trap; injection must stay mutually exclusive (`buildAgentEnv` untouched).
- `2026-03-20-websocket-error-sanitization-cwe-209.md`: raw SDK/CLI text never crosses to the client; copy is allowlisted by enum.
- `2026-03-18-typed-error-codes-websocket-key-invalidation.md`, `2026-03-27-websocket-close-code-routing-reconnect-loop.md`: keep `WSErrorCode` limited to produced codes; `key_invalid` stops the reconnect loop.
- `knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md`: subscription auth is operator-only; tenant copy must not mention it.
- `knowledge-base/engineering/operations/post-mortems/concierge-cli-not-logged-in-postmortem.md`: open PIR; this PR adds the root-cause addendum.

### Code-review overlap (Phase 1.7.5)

Open `code-review` issues touching planned files: #3242 (tool_use WS event raw-name field; `agent-runner.ts`, `cc-dispatcher.ts`, `lib/types.ts`, `lib/ws-zod-schemas.ts`), #3243 (decompose `cc-dispatcher.ts`), #3374 and #3280 (`ws-client.ts` / `ws-zod-schemas.ts`). **Acknowledge all four**: different concerns; this plan makes narrow additive edits and does not touch their subject code. They stay open.

## Problem Statement / Motivation

Every Concierge request from the affected account ended in `Not logged in · Please run /login` with no recovery. Two independent gaps: (a) the server hands the CLI a credential it will silently discard, without ever checking its shape; (b) when any CLI auth failure happens, its raw line is streamed and persisted as the assistant's reply.

## Proposed Solution

### Part 1 - root cause (one shared predicate module, three enforcement points)

New `server/oauth-token-shape.ts` (dependency-free; **must not name** `CLAUDE_CODE_OAUTH_TOKEN` or `OAUTH_ENV_VAR` - `test/oauth-token-injection-site.test.ts` pins who may name them):

- `isAcceptableSubscriptionToken(value)`: strict allowlist `^sk-ant-oat\d{2}-[A-Za-z0-9_-]+$` on the trimmed value (what `claude setup-token` prints). Used at the write boundary only.
- `classifyCliDroppedValue(value)`: the measured-class predicate described here, returning a closed class `api_key_shaped | embedded_whitespace | blank` or `null`. Used at the lease boundary. **Only classes with direct measured evidence** (CTO F10, architecture finding 4: a generic "any other `sk-` prefix" class could lock the operator out of a future token shape the CLI would accept, with no bypass): `api_key_shaped` = trimmed value matches `^sk-ant-(?:api|admin)`; `embedded_whitespace` = trimmed value starts `sk-` and contains a space or a tab (both measured dropped; an embedded NEWLINE is deliberately NOT guarded - the CLI uses it and fails loudly with "Invalid auth token ... line break", which reaches the user through the friendly `structured` rewrite); `blank` = trimmed value is empty. Values like `sk-X`, `sk-proj-`, `sk-ant-oatAAAA` (measured dropped, unrealistic for a stored token) are caught only by the strict write-time allowlist. Never returns or logs any part of the value.
- Consistency invariant: nothing `isAcceptableSubscriptionToken` accepts is ever classified by the lease predicate.

Enforcement:

1. **Write boundary** (`app/api/keys/route.ts`, oauth branch): after `.trim()`, a value failing the allowlist returns 400 `{ error, code: "oauth_token_shape_invalid" }` **before** `encryptKey`/RPC. Message is shape-only and never echoes the value; for an `sk-ant-api`/`sk-ant-admin` prefix it may say "That looks like an API key, not a subscription token" (CPO), otherwise neutral ("should start with `sk-ant-oat` and contain no spaces; copy it again from `claude setup-token`"). The form already renders `data.error`.
2. **Lease boundary** (`byok-lease.ts fetchAgentCredentialIntoSlot`): after `decryptRow` and the alive check, before `slot.agentCredentialBuffer = buf`, run `classifyCliDroppedValue(buf.toString("utf8"))`. On a class: `zeroize(buf)`, report one event (below), throw `ByokLeaseError("oauth_unusable", ...)`. **No fallback** to the `anthropic` row (CTO F1; P6). `ByokLeaseError`'s cause union (two copies at the class) and `mapByokLeaseCauseToErrorCode` (`: never` rail) gain the case, mapping to `key_invalid`; `agent-on-spawn-requested.ts BYOK_LEASE_CAUSES` gains it so the scheduled-agent classifier does not page it as `leader_internal_error`.
3. **Contract test against the bundled binary** (`test/agent-auth-cli-contract.test.ts`): spawns the SDK's platform binary under `env -i` with synthesized fake values and asserts (i) dropped-class samples reply exactly the not-logged-in line (offline arm), (ii) a valid-shaped sample is USED: `ANTHROPIC_BASE_URL` points at a loopback stub returning 401 and the stub must observe the request (hermetic, no external network; per-spawn timeout 15 s; if the CLI refuses a non-Anthropic base URL with an oauth token, fall back to asserting only "not the not-logged-in line" under the same timeout and say so in the test header), (iii) when the binary is absent the test SKIPS visibly locally but FAILS when `process.env.CI` is set (a skipped test exits 0, so CI-side the binary's presence is asserted, not assumed). Fails on an SDK bump if measured behavior changes; re-derive on every bump (same sentence as the wording comment).

Lease telemetry (P5): `reportSilentFallback(null, { feature: "byok-lease", op: "oauth-credential-unusable", message: "byok-lease: stored subscription credential is not usable by the CLI", tags: { shape_class }, extra: { shape_class } })` - literal `null` first argument (pino-mirror dedupe, #8629); `shape_class` is the closed enum (`api_key_shaped | embedded_whitespace | blank`) only; no user id, no length, no prefix.

### Part 2 - friendly error (new `server/agent-auth-user-message.ts`, outside the diagnostic file)

- `rewriteAgentAuthFailure(rawMessage, scheme)`: calls `matchAgentAuthFailure(rawMessage)` imported from the permanent `./agent-auth-match` (CTO F9; one matcher, no second regex list; the model-forgery gating stays inside it). **Matcher extraction:** `matchAgentAuthFailure`, `classifyReplyText`, `onlyTextBlock`, the forgery gate, `MAX_REPLY_LENGTH`, `CLI_SYNTHETIC_MODEL`, `isRec` and the `AgentAuthMatchKind` type move into new `server/agent-auth-match.ts`; `agent-auth-failure.ts` imports and re-exports the same names (its only edits: that swap plus a pointer comment), so every existing import, the guard tests, the Sentry rule and the tap/probe behavior are unchanged. The `agent-auth-mode.ts` REMOVAL CHECKLIST text is amended (step 1 keeps `agent-auth-match.ts`; step 2 keeps `CLI_AUTH_FAILURE_REPLIES`, `CliAuthFailureKind` and `SDK_AUTHENTICATION_FAILED` if the matcher body uses it - verify - and deletes `SDK_API_KEY_SOURCES`; step 6 keeps the matcher test, to be renamed at removal). An import-boundary test asserts `agent-auth-match.ts` and `agent-auth-user-message.ts` import none of `agent-auth-failure`, `agent-auth-mode`, `@sentry/*` or the probe. On null returns null. It rewrites ONLY when the message content is a single text block with no `tool_use` (a multi-block or tool-bearing `authentication_failed` message is left raw, still observed by the probe, and recorded in the wording comment). Otherwise returns `{ kind, content: [{ type: "text", text }], terminal, notice: { message, credentialScheme } }`, building a **new** content array (never mutates the SDK message). Copy comes from a table keyed `match_kind x scheme`; `scheme` unknown/null uses a **neutral** cell ("check your credentials in Settings and try again", naming neither an API key nor a subscription), so an operator with a null scheme is never told the wrong credential and a tenant is never shown subscription wording. The helper does only a table lookup and an array build (cannot throw); the matcher it calls already swallows its own faults and returns null, which means "raw passes through", so the helper adds no second warn latch (plan review: the CTO's fail-open requirement is met by that composition). `terminal` is true for `not_logged_in | invalid_api_key | oauth_token_revoked | structured | oauth_unusable` and false for `session_expired`.
- `match_kind` values: `not_logged_in | invalid_api_key | oauth_token_revoked | session_expired | structured`; plus a sixth cell `oauth_unusable` (lease guard) that reuses the `not_logged_in x oauth_token` copy and adds "Nothing was billed to your API key." `oauth_token_revoked x api_key` is unreachable and maps to the `invalid_api_key` cell at lookup (typed away, not a dead table cell). Copy carries no backticks (the card is plain text; `claude setup-token` is written as plain words).
- Copy table (CPO-drafted, tenant cells name only the API key; bubble copy names the recovery in words because the card is lost on reload, F8):

| kind | api_key (tenant) | oauth_token (operator only) |
|---|---|---|
| not_logged_in / oauth_unusable | "We couldn't sign in to Claude with your Anthropic API key, so nothing ran. Re-enter your API key in Settings and try again." | "We couldn't sign in to Claude with your saved subscription token, so nothing ran. Generate a new token with claude setup-token, save it in Settings, then try again." |
| invalid_api_key | "Anthropic rejected your API key. Check that it is active and copied in full, then re-enter it in Settings." | "Anthropic rejected your saved credential. Generate a new token with claude setup-token and save it in Settings." |
| oauth_token_revoked | (unreachable) uses invalid_api_key / api_key copy | "Your subscription token has been revoked or has expired. Generate a new one with claude setup-token and save it in Settings." |
| session_expired | "Your Claude session expired before we could finish. Start a new message, and if it happens again, re-enter your API key in Settings." | "Your Claude session expired before we could finish. Start a new message, and if it happens again, save a fresh token from claude setup-token." |
| structured | "Claude couldn't authenticate your request. Re-enter your Anthropic API key in Settings and try again." | "Claude couldn't authenticate your request. Save a fresh token from claude setup-token in Settings and try again." |

  Final wording gets a CLO pass at deepen-plan (tenant cells are tied to the operator-only legal posture).

- **cc path** (`server/soleur-go-runner.ts consumeStream`, assistant branch): `const rw = rewriteAgentAuthFailure(msg, state.authScheme)`. When non-null the runner delivers the friendly text through a **short-circuit in `handleAssistantMessage`** that calls `onText` directly - it must NOT pass through `stripStopGateMarkup`, the chapter-prefix/rotation logic or `recordAssistantBlock` (a chapter-routed turn must not render `[Answering from chapter ...] We couldn't sign in...`; the turn ends at the `result` right after). The short-circuit keeps the `onText` / `onTextTurnEnd` pairing and the text-turn bookkeeping balanced and the friendly text in the persisted accumulation (a runner test pins both; otherwise reload history is empty and F8 fails). If `rw.terminal`, set a per-turn `pendingAuthNotice` on the state. The `key_invalid` frame is sent **after the bubble is finalized**: from `handleResultMessage` after `onTextTurnEnd` (the `stream_end`), via a new optional `DispatchEvents.onAgentAuthFailure?.({ message, credentialScheme })`, then the flag resets (the latch). Reason (plan review, verified): `ws-client` handles `key_invalid` with `clear_streams` + `teardown()`, `sweepTransitional` turns a still-`streaming` bubble into an `interrupted` chip, and the cc `onText` emits `partial: true` until `stream_end`; a frame sent mid-stream would corrupt the very bubble that carries the recovery copy. `server/cc-dispatcher.ts` wires the event to `ctx.sendToClient(userId, { type: "error", message, errorCode: "key_invalid", credentialScheme })`. The `result` message's own text is never rendered by the runner (it forwards no `result` text), so the rewrite is assistant-branch only; the flag guards against a second frame. `session_expired` is bubble-only (no frame, no teardown): its copy says "start a new message", which a torn-down socket cannot honor.
- **Warm-Query eviction:** after a terminal auth failure the runner closes the Query once the `result` has been processed, so the next turn is cold and re-leases the credential the user just fixed in Settings (a warm Query keeps its old env and would fail with the same friendly error). Terminal kinds only (CTO F12). The work phase verifies at the result boundary that `closeQuery(state)` neither aborts a queued user message nor loses the persisted session id on resume; if either is unsafe, do NOT evict and record the limitation in the PR body, the PIR addendum and Dependencies & Risks instead.
- **One frame builder:** `buildAuthFailureFrame(err | match, scheme)` in `server/agent-auth-user-message.ts` returns `{ message, errorCode: "key_invalid", credentialScheme }` and is the single producer used at every site that can emit this frame: the cc dispatch catch, the two legacy `handleSessionError` sends (`agent-runner.ts ~2935`, `~3228`, which today pass `sanitizeErrorForClient(err)`; that returns "An unexpected error occurred" for a `ByokLeaseError`) and the `startAgentSession` catch in `server/ws-handler.ts ~2590` (maps only `KeyInvalidError` today). The `"api_key" | "oauth_token"` literal is defined once in `lib/` and imported by the server (not a third copy next to `AgentAuthScheme`).
- **Lease-time failure (cc dispatch catch):** a `ByokLeaseError` with cause `oauth_unusable` gets its own arm **above** the generic `else` in `reportDispatchSoleurGoError`: it sends the `key_invalid` frame with the oauth copy immediately (a lease failure precedes any stream, so there is no `stream_end` to wait for), does NOT clear `session_id`, and does NOT re-mirror to Sentry (the lease already reported; the runner catch at `soleur-go-runner.ts ~3200` is skipped for this cause the way it is for `RepoNotReadyError`/`WorkspaceNotReadyError`), so exactly one Sentry event is produced per failed turn. No assistant row is persisted for a lease-time failure (same as every existing lease-failure path; accepted and stated).
- **Ordering guarantee (P4):** the rewrite sits in the consumer of the **tapped** Query. `tapAgentAuthFailure` registers its `.then` observe on the original `next()` promise **before** returning it, so `probe.observe` runs on the raw object before the consumer's continuation; the rewrite never mutates that object. Pinned by test (see Guard 2).
- **Legacy path** (`server/agent-runner.ts ~2362`): same helper on the assistant message; friendly blocks feed `fullText`, the streamed `stream` frame and the persisted row; for a terminal kind the `key_invalid` frame is sent from the `result` branch **after** `stream_end`. The scheme comes from the credential the lease returned (`credential.scheme`), never from the binding. `resolveSessionErrorCode` already routes `ByokLeaseError` through `mapByokLeaseCauseToErrorCode`, so the lease-time failure maps with the table change; its human message for `oauth_unusable` uses the oauth copy.
- **Client** (CTO F7): `error` frame gains optional `credentialScheme: "api_key" | "oauth_token"` in `lib/ws-zod-schemas.ts` (strictObject, add explicitly) and the `WSMessage` error variant in `lib/types.ts`. `ws-client.ts` `key_invalid` branch: when `credentialScheme` is present (and one of the two enum values) use `msg.message` plus `credentialScheme` in `lastError` (the `WebSocketError` type is declared in `lib/ws-client.ts`, not `lib/types.ts`); when absent or unrecognised keep the hardcoded text byte-identical. Tests: a `ws-zod-schemas` parse test (accepts both values, rejects an unknown one), a `chat-surface` test for the "Claude Sign-in Failed" / "Update token" pair, and a reducer test that the bubble's final state is not `interrupted` after the frame. Old-tab skew: a tab loaded before the deploy parses with the old strict schema and drops a frame carrying the new key; accepted for the short rollout window. `chat-surface.tsx` picks title/label from the enum (`oauth_token`: "Claude Sign-in Failed" / "Update token"; `api_key`: unchanged "Invalid API Key" / "Update key"; both link `/dashboard/settings`, which hosts `KeyRotationForm`).
- **History (F5):** forward-only; old persisted raw lines stay inert text.

## Architecture Decision (ADR/C4)

### ADR

Two records, both deliverables of this PR via `soleur:architecture` (plan review: keep ADR-048 to one Consequences sentence and record the Part 2 decisions separately):

1. **ADR-048 addendum** (one Consequences sentence): a stored `anthropic_oauth` value of a measured CLI-dropped class is a new fail-closed lease cause (`oauth_unusable`), still never a silent api_key fallback; the write boundary validates the allowlist shape.
2. **New ADR** (ordinal provisional: 308 at plan time, ADR-307 is claimed on a pushed branch; re-verify against all remote refs at ship): server-authored auth-failure copy keyed by `match_kind` x credential scheme; the optional `credentialScheme` field on the `key_invalid` error frame; promotion of `matchAgentAuthFailure` and `CLI_AUTH_FAILURE_REPLIES` from temporary diagnostic to product code (F9); rejected alternatives: new WS errorCode, client-side rewrite, history rewrite, subscription-to-API fallback.

### C4 views

No C4 model change. Checked against all three of `diagrams/{model.c4,views.c4,spec.c4}` (read at work time, per the completeness mandate): external human actors (operator, tenant user) unchanged; external systems (Anthropic API, Claude CLI process, Sentry) unchanged; data store `api_keys` (Supabase) unchanged - no table, column or RPC change; the actor-to-surface relationship ("operator holds an oauth row") is already modeled and unchanged. Work phase runs `plugins/soleur/test/c4-count-parity.test.sh` green (the derived-cardinality gate named by the C4 completeness mandate); the code-syntax/render tests are not run because no `.c4` file is edited.

### Sequencing

Single PR; ADR addendum describes the post-merge state (no soak-gated slice).

## Technical Considerations

- **Single-injection-site guard:** `test/oauth-token-injection-site.test.ts` bans naming `CLAUDE_CODE_OAUTH_TOKEN`/`OAUTH_ENV_VAR` outside `agent-env.ts`, the names module and (temporarily) `agent-auth-failure.ts`. The two new modules and the lease must not import or spell them. `buildAgentEnv` and ADR-272's sandbox credential deny are untouched.
- **Union widening sweep (`cq-union-widening-grep-three-patterns`):** `ByokLeaseError.cause` consumers - `byok-lease.ts` (two union copies, `mapByokLeaseCauseToErrorCode`), `agent-runner.ts resolveSessionErrorCode`, `auto-sync-trigger.ts` (duck-types `escape` only; verify unaffected). WS error frame consumers of the new optional field: `ws-zod-schemas.ts`, `lib/types.ts`, `ws-client.ts`, `chat-surface.tsx`, plus any `_SchemaCovers` proof (#5394).
- **Matcher is product code after #11085:** made structural by the extraction above (CTO F9), not by a comment; a one-line pointer comment on #11085 at ship.
- **Performance:** the rewrite runs once per assistant message; matcher is O(1) on <=200 chars. Lease guard adds one regex on the decrypted string.
- **Security:** values never leave the lease scope; the buffer is zeroized before the throw; telemetry is the closed class only; the 400 never echoes input; client copy is allowlisted by enum (CWE-209 learning).
- **GDPR/compliance:** no new personal data, no new store, no new processor; the lease event carries no user id. The `/api/keys` route is a listed surface, so run `soleur:gdpr-gate` at deepen-plan (advisory).
- **NFR:** reliability (fail-open rewrite, fail-closed lease), observability, security; `nfr-register.md` read at work time.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Concierge still answers every request with `Not logged in · Please run /login` (or, worse, a friendly message that points a tenant at the wrong credential), with no way to recover in-product.
- **If this leaks, the user's workflow/credential is exposed via:** a lease or WS-frame telemetry field that carries any part of the stored subscription-token or API-key value (a prefix, a length, the raw CLI text), or a tenant-facing message that advertises subscription-token auth.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one paying user locked out of the Concierge with no recovery, or one credential fragment in Sentry, is enough to damage trust; the surface is small (operator-only row) but the failure is total and the data class is a secret.

CPO sign-off: advisory taken at plan time (draft copy, title/label variants, dual-surface and client-ignores-`msg.message` gaps, all folded in above). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Files to Edit

- `apps/web-platform/server/byok-lease.ts` - new cause `oauth_unusable`, guard in `fetchAgentCredentialIntoSlot`, `mapByokLeaseCauseToErrorCode` case, lease event.
- `apps/web-platform/app/api/keys/route.ts` - allowlist check on the oauth branch.
- `apps/web-platform/server/soleur-go-runner.ts` - rewrite in `consumeStream`, short-circuit in `handleAssistantMessage`, `DispatchEvents.onAgentAuthFailure` fired from `handleResultMessage`, per-turn flag, warm-Query eviction, mirror skip for `oauth_unusable`.
- `apps/web-platform/server/cc-dispatcher.ts` - wire `onAgentAuthFailure`; dispatch catch branch for `oauth_unusable`.
- `apps/web-platform/server/agent-runner.ts` - rewrite before `fullText`/stream/persist; frame after `stream_end` in the result branch; the two `handleSessionError` sends use the frame builder.
- `apps/web-platform/server/ws-handler.ts` - `startAgentSession` catch uses the frame builder.
- `apps/web-platform/server/agent-auth-failure.ts` - ONLY the import/re-export swap for the extracted matcher plus a pointer comment (CTO F9); tap, probe, `ENUMS`, `closed()` untouched.
- `apps/web-platform/server/agent-auth-mode.ts` - REMOVAL CHECKLIST text only (steps 1, 2, 6).
- `apps/web-platform/server/claude-error-signatures.ts` - wording-evidence comment only (three measured wordings stay `structured`; Cloud-gateway lead closed).
- `apps/web-platform/lib/ws-zod-schemas.ts`, `apps/web-platform/lib/types.ts` - optional `credentialScheme` on the error frame (the `_SchemaCovers` proof forces both together); the `lastError` field lives in `lib/ws-client.ts`.
- `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/components/chat/chat-surface.tsx` - scheme-aware message/title/label.
- Tests to extend (all exist; verified by `ls`): `apps/web-platform/test/api-keys-oauth-gate.test.ts`, `byok-lease-credential-type.test.ts`, `agent-auth-failure-tap.test.ts`, `error-states.test.tsx`, `ws-client-key-invalid-teardown.test.tsx`; plus `ws-client-key-invalid-source-gate.test.ts` (slices from `msg.errorCode === "key_invalid"` to the first `teardown();`, so the new branching must keep that shape), `ws-protocol.test.ts` and `chat-reducer.test.ts`.
- `knowledge-base/engineering/architecture/decisions/ADR-048-operator-cc-oauth-credential-selection-by-consumer-class.md` - addendum.
- `knowledge-base/engineering/operations/post-mortems/concierge-cli-not-logged-in-postmortem.md` - root-cause addendum (mechanism, evidence, what is unverified).

## Files to Create

- `apps/web-platform/server/oauth-token-shape.ts` - the two predicates + closed class enum.
- `apps/web-platform/server/agent-auth-match.ts` - the extracted pure matcher (CTO F9), permanent.
- `apps/web-platform/server/agent-auth-user-message.ts` - copy table + `rewriteAgentAuthFailure` + `buildAuthFailureFrame`.
- `apps/web-platform/test/agent-auth-import-boundary.test.ts` - the two permanent modules import none of `agent-auth-failure`, `agent-auth-mode`, `@sentry/*`, the probe.
- `apps/web-platform/test/oauth-token-shape.test.ts` - predicates, generated-alphabet consistency property.
- `apps/web-platform/test/agent-auth-user-message.test.ts` - total table, no-mutation, fail-open, no-raw-text.
- `apps/web-platform/test/agent-auth-cli-contract.test.ts` - bundled-binary contract.
- `apps/web-platform/test/agent-auth-friendly-error-wire.test.ts` - real tap + real cc runner + legacy runner ordering/persistence.

## Implementation Phases

Phase 0 - RED first (`cq-write-failing-tests-before`): write every test above; each must fail on `main`.

Phase 1 - `oauth-token-shape.ts` + its test + the CLI contract test (the contract test is the anchor for the whole class).

Phase 2 - write boundary (`/api/keys`) + route test.

Phase 3 - lease guard + cause plumbing + lease test (zeroize asserted; api row never read; event tags closed).

Phase 4 - `agent-auth-user-message.ts` + test; cc-runner rewrite + `onAgentAuthFailure` + dispatcher wiring + dispatch-catch branch.

Phase 5 - legacy runner; wire test for both runners.

Phase 6 - client: schema/types/ws-client/chat-surface; update/extend the two existing client tests (default path byte-identical).

Phase 7 - evidence and records: wording comment, ADR-048 addendum, post-mortem addendum, `c4-count-parity`, full web-platform vitest run, `tsc`.

## Guard Contract

### Guard 1 - Stored-credential shape (predicate + enforcement + CLI contract)

**Property.** No subscription-token value that the bundled CLI silently drops can be stored through `/api/keys` or handed to the CLI by the lease, and no value the strict allowlist accepts is ever classified dropped.

**Assembly.** The chokepoints are the two writers/readers of the `anthropic_oauth` row: the `/api/keys` oauth branch (sole writer via `store_oauth_credential`, migration 096) and `fetchAgentCredentialIntoSlot`'s oauth branch (sole reader). Both import the one module `server/oauth-token-shape.ts`. `lease.getAgentCredential()` has exactly two callers outside the lease (`server/agent-runner.ts`, `server/cc-dispatcher.ts`; measured by grep 2026-10-29, so the oauth row can reach the CLI only through those two runners; `pdf-chapter-router.ts` and the scheduled agents use the REST key).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the shape check from the `/api/keys` oauth branch | RED (route test: API-key-shaped value now stored) |
| 2 | Make `classifyCliDroppedValue` return `null` for every input (a guard reporting "0 dropped") | RED (lease test expects `oauth_unusable`; property test expects non-null on the dropped corpus) |
| 3 | Make the guard test only the first of two classes (stop after `api_key_shaped`; `embedded_whitespace` then passes through) | RED (lease test iterates every class) |
| 4 | Move the guard to AFTER `slot.agentCredentialBuffer = buf` (reorder, not delete) | RED (test asserts the slot buffer is null/zeroized when the throw happens, observed INSIDE the window) |
| 5 | Widen the allowlist to accept `sk-ant-api03-...` | RED (consistency property + contract test: allowlist-accepted value classified dropped) |
| 6 | Make the contract test's `skipIf` condition always true (binary "absent") with `CI` set | RED (the CI arm must fail, not skip) |

**Harness rows.** (a) Break the suite: make the contract test's spawn helper return a canned string without spawning - the "binary actually ran" assertion (`apiKeySource` read from the real stream, and for the valid-shape arm the loopback stub's request log) goes RED. (b) Must-PASS non-canonical inputs: `" sk-ant-oat01-A.B "` (padded, dotted tail), `sk-ant-sid01-X`, `garbage with space`, `sk-ant-oat01-AAAA\nBBBB` (newline: not guarded), `sk-ant-oat02-` + 90 random `[A-Za-z0-9_-]` characters - none is classified by the lease predicate.

**Anchor.** The stored value is the CLI's measured behavior, not a hash: the anchor outside the commit is the bundled binary itself via the contract test, which re-derives on every SDK bump (a bump that changes behavior reddens CI rather than being edited around). A skip is printed, never silent.

### Guard 2 - Matcher sees raw text before any rewrite, in both runners

**Property.** For every assistant message the matcher classifies, `probe.observe` receives the original unmodified message object (emitting per the existing once-per-turn latch), and the user-visible and persisted text is the friendly copy, never the raw line.

**Assembly.** Two runners, two different observation mechanisms (plan review, architecture finding 3): the cc runner consumes a Query wrapped in place by `tapAgentAuthFailure` (the tap registers `.then(observe)` on the original `next()` promise before returning it, so the synchronous half of `observe` runs on the raw object before `consumeStream`'s continuation); the legacy runner has NO tap and calls `void authProbe.observe(message)` inline at the top of its loop (`agent-runner.ts ~2284`), before the assistant branch. One rewrite helper, one matcher (`matchAgentAuthFailure`, now defined in the permanent `server/agent-auth-match.ts`, CTO F9). Chokepoint: the helper is the only place raw text is replaced, and it builds a new content array.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | In the helper, mutate `message.message.content[0].text` in place | RED (a deep-frozen input throws; this is the catcher - `observe` reads the message synchronously, so the probe assertion alone would not notice a mutation after it) |
| 2 | cc: install the rewrite upstream of `tapAgentAuthFailure` (consumer sees friendly text before the tap observes) | RED (probe emitted 0 times) |
| 2b | legacy: move the rewrite above the inline `authProbe.observe(message)` call | RED (probe emitted 0 times; the legacy wire test uses a REAL `createAgentAuthFailureProbe`) |
| 3 | Rewrite only in the cc runner, leave legacy raw | RED (legacy wire test asserts friendly `fullText` / `saveMessage` content) |
| 4 | Helper keeps a second regex list instead of calling `matchAgentAuthFailure` | RED (a `structured`-only message - `error: "authentication_failed"` with unrecognised text - is not rewritten) |
| 5 | Send the `key_invalid` frame from the assistant branch instead of after `stream_end` / the result branch | RED (reducer test: the bubble ends `interrupted`; ordering test asserts `stream_end` before `error`) |
| 6 | Rewrite a multi-block or `tool_use`-bearing `authentication_failed` message | RED (such a message stays raw) |
| 7 | `agent-auth-user-message.ts` imports the matcher from `./agent-auth-failure` instead of `./agent-auth-match` | RED (import-boundary test: the removal checklist can never reach product code) |

**Harness rows.** (a) Replace the real tap (cc) / real probe (legacy) with a pass-through in the wire test: the "probe emitted once" assertion goes RED, proving the test exercises the real mechanism. (b) Must-PASS non-canonical: a model-authored assistant message carrying the exact CLI string but a non-synthetic model and no `is_api_error_message` is NOT rewritten and NOT emitted (forgery gate preserved).

**Anchor.** The matcher keeps its existing independently reviewed suite (`agent-auth-failure-matcher.test.ts`, unchanged because `agent-auth-failure.ts` re-exports the same names); this plan adds no pattern to it, so a weakening needs an edit to that suite in the same diff.

### Guard 3 - No credential fragment in any emitted artifact

**Property.** The lease event, the WS frames and logs produced by the new paths contain only closed-enum strings and server-authored copy, never any substring of the stored value.

**Assembly.** Emit sites: the lease `reportSilentFallback`, `onAgentAuthFailure` frame, dispatch-catch frame, route 400 body, and the helper's constant warn.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `length` or `slice(0, 6)` of the value to the lease event extra | RED (test seeds a canary value and asserts no canary substring, no value-derived number, in any captured sink) |
| 2 | Echo the submitted value in the route 400 body | RED |
| 3 | Include the raw CLI text in the `onAgentAuthFailure` payload | RED (canary text absent) |

**Harness rows.** (a) Must-PASS: a legitimate event carrying `shape_class` only passes. (b) A deliberate leak in the test double proves the capture would see a canary.

**Anchor.** Canary values are synthesized in-test (`cq-test-fixtures-synthesized-only`); no stored secret is read anywhere.

## Observability

```yaml
liveness_signal:
  what: Sentry issue stream event feature=byok-lease op=oauth-credential-unusable (fires when a stored subscription credential is refused by the lease guard) plus the existing feature=agent-auth op=cli-auth-failure event
  cadence: per occurrence (one lease attempt per Concierge message while the row is bad; Sentry groups them into one issue)
  alert_target: Sentry issue stream (level error, default high-priority workflow)
  configured_in: apps/web-platform/server/byok-lease.ts
error_reporting:
  destination: Sentry project web-platform via reportSilentFallback (DSN env var SENTRY_DSN) with the pino second sink to Better Stack
  fail_loud: the Concierge turn ends with a key_invalid frame carrying the recovery copy; the lease throws ByokLeaseError oauth_unusable (no silent fallback)
failure_modes:
  - mode: stored subscription credential is of a CLI-dropped shape
    detection: lease guard event with closed shape_class tag
    alert_route: Sentry issue stream
  - mode: friendly-rewrite helper throws on an unreadable message
    detection: one constant-text warn per process, raw message passes through, probe still emits
    alert_route: Better Stack log line
  - mode: a bundled-CLI upgrade changes the dropped-value behavior
    detection: agent-auth-cli-contract test goes red in CI
    alert_route: CI failure on the SDK bump PR
logs:
  where: Better Stack (pino JSON from the web container), fields feature and op only
  retention: Better Stack plan retention
discoverability_test:
  command: rg -c "oauth-credential-unusable" apps/web-platform/server/byok-lease.ts
  expected_output: "1"
```

Affected-surface note (2.9.2): the Concierge turn runs inside the agent sandbox/cc dispatch path, but every new signal is emitted by the server process (lease, dispatcher), not from inside the sandbox; the in-surface discriminator is the CLI's own `system/init` `apiKeySource` already captured by the probe.

## Test Scenarios

Layers: unit unless noted.

- Given a tenant whose API key the CLI rejects (`Invalid API key · Fix external API key`, `error=authentication_failed`, synthetic model), when the cc runner consumes the turn, then the persisted/streamed text is the api_key `structured` copy, the probe emitted once with the raw message, and exactly one `key_invalid` frame with `credentialScheme: "api_key"` follows the bubble. (integration)
- Given the operator whose oauth row decrypts to `sk-ant-api03-...`, when a Concierge turn starts, then the lease throws `oauth_unusable`, the buffer is zeroized, the api row is never queried, one lease event with `shape_class: "api_key_shaped"` is captured, and the dispatch catch sends the oauth-copy `key_invalid` frame. (integration)
- Given the same value, when saved through the toggle, then 400 `oauth_token_shape_invalid`, RPC not called, body does not contain the value.
- Given a valid-shaped fake `sk-ant-oat01-...`, then neither boundary rejects it.
- Given a message whose model is not `<synthetic>` and without `is_api_error_message` carrying the exact CLI line, then no rewrite, no emit.
- Given a throwing-getter message, then the turn completes, raw passes through, one warn.
- Given `credentialScheme` absent on a `key_invalid` frame (existing server sites), then the client renders the unchanged hardcoded text/title/label; given it present, then scheme copy renders and the persisted bubble survives `clear_streams` + `teardown`.
- Contract (integration, visible skip when the binary is absent): dropped corpus replies exactly the not-logged-in line offline; valid-shaped does not.
- Regression: a raw `Failed to authenticate. API Error: 401 ...` assistant message with the structured code returns `structured` from the matcher (F4).
- Browser verification (QA, post-implementation): sign in as a non-operator test account with a deliberately invalid synthesized API key, send a Concierge message, expect the friendly bubble + "Invalid API Key" card with an "Update key" action to `/dashboard/settings`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `server/oauth-token-shape.ts` exports the allowlist and the negative predicate; the consistency property test passes over a generated alphabet; neither new module names `CLAUDE_CODE_OAUTH_TOKEN` or `OAUTH_ENV_VAR` (`oauth-token-injection-site.test.ts` green).
- [x] `/api/keys` oauth branch rejects non-allowlist values with 400 `oauth_token_shape_invalid` before any encryption/RPC; no echo of the value.
- [x] `fetchAgentCredentialIntoSlot` throws `ByokLeaseError("oauth_unusable")` on a dropped class, zeroizes first, never reads the api row; `mapByokLeaseCauseToErrorCode` (`: never` rail) updated. `agent-on-spawn-requested.ts BYOK_LEASE_CAUSES` is deliberately NOT edited: that path calls `getRestApiKey()` only (verified at `agent-on-spawn-requested.ts:736`), so `oauth_unusable` cannot reach it.
- [x] Lease event emitted with `feature=byok-lease op=oauth-credential-unusable` and only `shape_class`; canary test shows no value fragment in any sink.
- [x] Both runners rewrite every matcher hit on a single-text-block message (all five kinds + `oauth_unusable`) to copy chosen from `kind x scheme`; unknown/null scheme uses the neutral cell; raw SDK message never mutated; a chapter-routed turn renders no chapter prefix on the friendly text; the frame is sent only for terminal kinds (`session_expired` is bubble-only) and after `stream_end`; a terminal failure evicts the warm Query (or the limitation is recorded).
- [x] Wire tests: cc uses the REAL tap, legacy uses a REAL `createAgentAuthFailureProbe`; in both the probe emitted on the raw message AND user-visible/persisted text is friendly; `stream_end` precedes the `key_invalid` frame; one frame per turn; lease-time `oauth_unusable` produces exactly one Sentry event, no `session_id` clear, and the oauth-copy frame via the builder on the cc and both legacy producers.
- [x] Client: `credentialScheme` added in schema and types together; scheme-less `key_invalid` path byte-identical (existing `error-states` and `ws-client-key-invalid-teardown` tests unchanged and green); scheme path renders scheme copy/title/label.
- [x] Bundled-binary contract test present, runs offline arms only; absent binary = visible skip locally, hard FAIL under `CI`; a mutation row proves the `skipIf` call site is covered.
- [x] The Sentry rule, `infra/sentry/**` and the diagnostic's guard tests are untouched (`git diff --name-only $(git merge-base HEAD origin/main)` contains none of `apps/web-platform/infra/sentry/**`, `test/agent-auth-failure-*.test.ts`, `test/sentry-agent-auth-failure-*.test.ts`); `server/agent-auth-failure.ts` changes only by the import/re-export swap and a pointer comment; `agent-auth-mode.ts` only in its REMOVAL CHECKLIST text; `claude-error-signatures.ts` only in its comment. The matcher lives in `server/agent-auth-match.ts` and `agent-auth-import-boundary.test.ts` is green.
- [x] ADR-048 addendum merged; post-mortem root-cause addendum merged; `c4-count-parity.test.sh` green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and the web-platform vitest suite (`package.json` `scripts.test`) green; `npx markdownlint-cli2` clean on the plan and `tasks.md`.
- [ ] PR body: `Ref #11086`, `Ref #10455`, `Ref #11085` (never `Closes`); `## Changelog` section present.

### Post-merge (tracked, not operator checklists)

- [ ] One `action-required` issue filed at ship, BEFORE deploy where possible, with an owner (the operator) and a review date (deploy date + 3 days): the operator re-saves the subscription token as the bare `sk-ant-oat01-...` value in Settings (operator's own secret; this PR performs no production write).
- [ ] #11086 closes on a dated pair of cited evidence taken on the FIRST operator-account Concierge turn after deploy: either the lease-guard event fires with its `shape_class` (an agent reads it with the README Discover query) or the turn completes without the raw line. No turn sent by the review date means still open, not evidence. If a turn is sent, no event fires and the raw line still appears, the row is valid-shaped, contradicting the mechanism: reopen the root-cause investigation.
- [ ] One-line pointer comment on #11085 at ship: the removal checklist in `agent-auth-mode.ts` now keeps `agent-auth-match.ts` and `CLI_AUTH_FAILURE_REPLIES`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled forks F1-F8 (decision-challenges.md): fail-closed lease with `oauth_unusable` and no fallback; strict write allowlist plus negative lease predicate in one module; text rewrite plus `key_invalid` frame, no new code; same-matcher/no-mutation/fail-open ordering with a real-tap test; no new `match_kind`; forward-only history; `Ref` closure; scheme transported by an optional closed-enum frame field; keep both bubble and card.

### Legal (CLO)

**Status:** error (not spawned in the planning pass; constraint carried)
**Assessment:** The 2026-10-06 CLO audit is the authority: subscription auth is owner-only; tenant-facing copy must not mention or advertise it. Carried as a hard constraint on every tenant cell; a CLO read of the final copy table is queued for deepen-plan.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** hard-blocked (Pencil Desktop not installed; `check_deps.sh --auto` did not complete). No `.pen` is committed: the only `components/**` edit is two strings (title, action label) chosen by an enum on the existing `ErrorCard` in `chat-surface.tsx`, which `ui-surface-terms.md` excludes as a pure copy tweak with no structural change; the UX lead advised no wireframe. Recorded as a challengeable taste row in `decision-challenges.md`; QA covers four visual states (tenant card, operator card, reloaded history, the Settings 400).

#### Findings

CPO: client must stop discarding the server copy for `key_invalid` and vary title/label by scheme (done via `credentialScheme`); dual surface acceptable because the bubble is the only recovery path after reload (CTO F8); "Invalid API Key" is wrong for the operator scheme; copy table drafted and adopted; threshold `single-user incident` agreed; save-time reject must not echo the value and may say "looks like an API key" only for `sk-ant-api`/`sk-ant-admin` prefixes.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "(1) root cause" | Part 1: shape module, write boundary, lease guard, contract test, post-mortem addendum | mapped |
| 2 | "(2) friendly user-visible error with a recovery path" | Part 2: rewrite module, both runners, `key_invalid` frame, client scheme-aware card | mapped |
| 3 | "The matcher in server/agent-auth-failure.ts MUST keep running on the raw text before any rewrite" | Guard 2, ordering section, wire test | mapped |
| 4 | "the temporary diagnostic removal (#11085) is NOT part of this PR; do not remove the rule or its guard tests here" | AC diff-scope check; #11085 retention comment | mapped |
| 5 | "Route technical forks to soleur:engineering:cto" | decision-challenges.md F1-F8 | mapped |
| 6 | "PR body must use Closes #11086 only if both parts ship; otherwise Ref" | PR body line, CTO F6 | mapped |
| 7 | "Production writes need explicit per-command operator go-ahead" | No production write; operator re-save filed as action-required | mapped |
| 8 | "Lead on #11086 comments: ... Cloud gateway ... which the matcher does not cover" | Research Reconciliation row, evidence comment | mapped |
| 9 | "the mismatch between binding and credential scheme is the first lead" | Research Reconciliation row (verified benign) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Shape module + write boundary | "(1) root cause" | asked |
| Lease guard (fail closed) | "(1) root cause" | asked |
| Bundled-binary contract test | "(1) root cause" | inferred - pins the measured mechanism so an SDK bump cannot silently reintroduce the class (CTO F1) |
| Rewrite module + both runners | "friendly user-visible error with a recovery path" | asked |
| `key_invalid` frame + `credentialScheme` + client changes | "a recovery path" | asked |
| Matcher extraction into `agent-auth-match.ts` + checklist text + import-boundary test | "The matcher in server/agent-auth-failure.ts MUST keep running on the raw text before any rewrite" | asked - CTO F9: the removal checklist (#11085) would otherwise delete the matcher the friendly error depends on |
| One frame builder + `ws-handler.ts` edit | "a recovery path" | asked - four producers of the frame, one mapping a lease failure to a generic message (architecture finding 5) |
| Warm-Query eviction after a terminal auth failure | "a recovery path" | asked - without it the user fixes Settings and the same warm Query fails again (spec-flow gap 3) |
| New ADR (Part 2), ADR-048 addendum, post-mortem addendum | "(1) root cause" | inferred - Phase 2.10 and the open PIR's root-cause section |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/server`, `apps/web-platform/{app,lib,components}`, `knowledge-base`
- Planned files: ~18 edits + 8 creates (~26, counting two knowledge-base records and test files) | Estimated changed lines: ~800 (mostly tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (below every threshold; the two parts share the `oauth_unusable` copy cell and the `key_invalid` frame)

## Dependencies & Risks

- **Unverified:** which stored shape the operator's row has (cannot read a secret). Mitigation: both shapes are in the dropped class; post-deploy event carries `shape_class`.
- **Risk:** a future valid token shape not matched by the strict write allowlist locks the operator out of saving. Mitigation: single named regex constant; lease-time predicate is negative-only so an already-stored future-shaped token still works; contract test reddens on SDK bump.
- **Risk:** `teardown()` after the frame could discard an in-flight bubble (unverified). Mitigation: bubble is finalized first and a test asserts it survives.
- **Risk:** `agent-sandbox` unaffected; `buildAgentEnv`/ADR-272 untouched.
- **Out of scope (tracked elsewhere):** #11085 removal; account-level changes to `ADMIN_USER_IDS`/`CC_OAUTH_ENABLED`; any prod DB write.

## Sharp Edges

- `## User-Brand Impact` must stay filled and keep its threshold or deepen-plan Phase 4.6 halts.
- Do not add a `match_kind` or Sentry tag to the temporary diagnostic; the lease event is its own feature/op.
- The wire test must use the REAL `tapAgentAuthFailure`; a stubbed tap makes the ordering assertion vacuous.
- Do not name `CLAUDE_CODE_OAUTH_TOKEN` or `OAUTH_ENV_VAR` in new files, comments included (the guard greps source text).
- The client reads `msg.message` for `key_invalid` only when `credentialScheme` is present; flipping that to "always" rewrites tenant-visible text in two existing tests.
- The contract test uses only synthesized fake values; never feed it a real token.
- Re-derive the dropped-class table on every SDK bump (same discipline as `CLI_AUTH_FAILURE_REPLIES`).

## References

- Issue #11086; umbrella #10455; removal #11085; PIR `knowledge-base/engineering/operations/post-mortems/concierge-cli-not-logged-in-postmortem.md`
- `apps/web-platform/server/{agent-auth-failure,byok-lease,agent-env,soleur-go-runner,cc-dispatcher,agent-runner,claude-error-signatures}.ts`, `apps/web-platform/app/api/keys/route.ts`, `apps/web-platform/lib/{ws-client,ws-zod-schemas,types}.ts`, `apps/web-platform/components/chat/chat-surface.tsx`
- ADR-048, ADR-272; `apps/web-platform/infra/sentry/README.md` ("Diagnostic rule: agent-auth-failure")
