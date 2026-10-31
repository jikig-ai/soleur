---
title: "feat: copy follow-ups for the Authentication mode setting and the delegated api-key lease"
date: 2026-10-31
slug: auth-mode-followups-recovery-copy-and-delegated-api-key
branch: feat-one-shot-11594-11599-auth-mode-followups
issue: 11599
closes: [11594, 11599]
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Two follow-ups of the merged Authentication mode work (#11590, merge f184d2dcbe) land in one PR on operator instruction.

1. **#11599 (copy).** (a) The operator-only sign-in messages gain a recovery sentence. (b) A conversation whose authentication mode cannot be resolved gets its own refusal frame and card instead of the `key_invalid` "Your API key is invalid or expired / Update key" copy with a torn-down socket, and the generic call-site error-tracker mirror skips the event the lease already reported. (c) The Settings helper line and the amber provider disclosure become accurate for non-owner viewers.
2. **#11594 (delegation).** A delegated (or owner-mismatched) lease whose grantor also holds an `anthropic_oauth` row may proceed on the grantor's `anthropic` API-key row when the conversation's mode is exactly `api-key`. The CLO ruled ALLOW-WITH-CONDITIONS (decision file), so the plan implements it under those conditions: the mode is resolved first, only an exact `api-key` skips both the subscription-row SELECT and the owner-gate throw, and every other outcome keeps today's refusal.

PR body: `Closes #11594` and `Closes #11599`, but only after the Acceptance Criteria below are verified at ship time; any item not delivered becomes `Ref` with the reason on the issue.

## Research Insights

**Premise validation (Phase 0.6).** Issues #11594 and #11599 are both OPEN and cite no blocker. Draft PR #11715 (this branch) is the only change naming them; the collision pre-check reported foreign `test-all.sh` processes in an unrelated worktree (no overlap). Cited artifacts verified on `origin/main` (ba483a9948): `fetchAgentCredentialIntoSlot`, `failAuthModeClosed`, `mapByokLeaseCauseToErrorCode` and `OauthDelegationForbiddenError` in `apps/web-platform/server/byok-lease.ts`; `authModeLabel` and the `isOwner` prop in `components/settings/agent-engine-settings.tsx`; the `COPY` table in `server/agent-auth-user-message.ts`. ADR corpus check: ADR-048 (+ its 2026-10-30 addendum) already lists the `fetch_failed` UX and the delegation refusal as deferred to exactly these issues and rejects "a new `ByokLeaseError` cause ... for no gain" for the PARENT work only; the operator instruction now overrides that rejection (decision file). ADR ordinals clean on fresh `origin/main` (`bash scripts/check-adr-ordinals.sh`).

**Property list (Phase 0.6b).**

- P1. An owner whose mode is Automatic and whose stored subscription token is unusable is told how to recover (choose "My API key", start a new conversation).
- P2. A conversation whose mode cannot be resolved shows copy that is true for the cause (deterministic: start a new conversation; transient: send again), does not tear the socket down, does not say the API key is invalid, and produces exactly one error-tracker event.
- P3. Non-owner viewers of Settings are not told things that are false for them.
- P4. A delegated run on a grantor's API key is not blocked by the grantor's unused subscription row, without the subscription row ever being selected, decrypted or served to a non-owner.

**Cut list.** Mechanism -> property -> what already covers it:

- A new module for the frame builder/predicates -> P2 -> `agent-auth-user-message.ts` already owns `isOauthUnusableLeaseError`, `logSessionFailure` and `authFailureFrameFromLeaseError`; extend it (CTO).
- A new ADR -> P4 -> ADR-048 addendum mechanism already exists (CTO).
- Blocking the "My API key" option when no key is saved, an inline Settings warning -> not asked -> the existing `MissingByokKeyError` -> `byok_key_missing` card is the exit (decision file, CPO item 2).
- Editing the sibling disclosure in `components/settings/connected-services-content.tsx` -> not asked (that page says "your provider credentials", true for every viewer).
- Retrying a failing conversation under a new mode -> non-goal from #11591 (CPO).
- A credential-type column or audit-RPC change for the delegated run -> P4 -> telemetry breadcrumb carries it (CTO (d)); cost-writer has no such column.
- Making a delegated `managed` lease skip the token and use the API key -> CLO condition 6 (silent credential substitution; needs its own ruling).
- Review cuts (CTO R6): the second "deterministic" reason set, a separate exported `isAuthModeUnresolvedLeaseError`, a separate new lease test file, two client test files, a Reconnect button on either card, a per-conversation Sentry debounce.

**Institutional learnings applied** (`knowledge-base/project/learnings/`): `2026-06-16-wserrorcode-second-canonical-copy-and-mount-fetch-sibling-test-sweep.md` (widen `WSErrorCode` AND the zod enum in the same change; `tsc`'s `_SchemaCovers` proof catches drift); `2026-05-04-flag-boundary-creates-new-error-class-mapper-must-handle.md` (new code handled in mapper, UI and telemetry in the same PR); `2026-10-05-new-consts-in-mocked-modules-break-test-factories.md` and `test-failures/2026-06-29-wholesale-module-mock-drops-named-exports-needed-by-transitive-siblings.md` (no new import from `byok-lease` at call sites: nine tests partially mock it); `best-practices/2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md` (source-text pins only for negative space); `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md` (the recovery sentence is one constant, not five literals); `best-practices/2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md` (a line-start `#NNNN` in the ADR becomes a phantom heading: keep issue refs mid-line or backticked).

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (verified in the worktree) | Plan response |
|---|---|---|
| `ByokLeaseError("fetch_failed")` with a closed `reason` "is currently rendered with the key_invalid ... copy and tears the socket down" | True only on the legacy runner: `agent-runner.ts` `resolveSessionErrorCode` -> `mapByokLeaseCauseToErrorCode("fetch_failed")` = `key_invalid`; `lib/ws-client.ts` renders "Your API key is invalid or expired." + "Update key" and calls `teardown()`. The Concierge path (`cc-dispatcher.ts` dispatch catch) falls to the generic else ("Dashboard router is unavailable", resumable `session_id` cleared) and the `ws-handler.ts` `startAgentSession` catch sends generic text with no code. Three different wrong renderings. | Fix all three emit paths with one typed frame. |
| "the lease reports one `reportSilentFallback` event op `auth-mode-unresolved`" | Verified (`failAuthModeClosed`). The generic mirrors that double it: `agent-runner.ts` (2 sites, `Sentry.captureException`), `ws-handler.ts` (1), `soleur-go-runner.ts` queryFactory `reportSilentFallback` (1), `cc-dispatcher.ts` dispatch `mirrorWithDebounce` (1). | Generalise the existing `isOauthUnusableLeaseError` skip at those five points. |
| "touches the exhaustive `never` rail ..., the WS code enum, the zod schema and the UI" | `mapByokLeaseCauseToErrorCode` (`byok-lease.ts`), `WSErrorCode` (`lib/types.ts`, "second canonical copy" comment), `errorSchema.errorCode` (`lib/ws-zod-schemas.ts`, `_SchemaCovers` proof), the `error` case of `lib/ws-client.ts`, `credentialCardCopy` + the `ErrorCard` retry predicate in `components/chat/chat-surface.tsx`. | Files to Edit below. |
| "how the client learns whether the viewer is the workspace owner" | `AgentEngineSettings` already takes `isOwner`, passed from `settings-content.tsx` as `workspaceIdentity?.isOwner ?? true`; the dropdown/radios are already `disabled={!isOwner ...}`; the footer already says "Only workspace owners can change this setting." | Reuse the prop; no API or route change. |
| "what the delegated-lease path already does for the grantor's api_key row" | `resolveKeyOwnerThenLease` (own-key-first, flag-gated) sets `keyOwnerUserId = grantor` and `delegationId`; with no grantor oauth row the lease already falls through to the grantor's `anthropic` row (pinned by the #11524 test "delegated lease with the oauth row removed falls back to the owner's api_key"). Only the oauth-row presence triggers the throw. | The change is limited to the oauth-row branch of `fetchAgentCredentialIntoSlot`. |
| Existing tests that assert the OLD behavior | `byok-lease-auth-mode-binding.test.ts` "AC16 a delegated lease is refused by the owner gate before any binding read" and `byok-lease-credential-type.test.ts` "AC4 gate order (delegated / owner mismatch): the mode is never read, in both modes" encode "no mode read for a cross-owner lease"; `auto-sync-trigger.test.ts` (lines ~417/445) builds `ByokLeaseError("fetch_failed", ..., reason)`. | Rewritten, not deleted (see Files to Edit and AC3, AC4, AC10). |
| Deterministic-reason set | Duplicated in `auto-sync-trigger.ts` (`DETERMINISTIC_AUTH_MODE_REASONS`) and implicitly in `byok-lease.ts`. | One shared TRANSIENT set (`read_failed`, `resolver_failed`) in the import-free leaf `server/auth-mode-error.ts`; every other reason, including future ones, is deterministic (fail-safe default, CTO review ruling R6). |
| Production shapes of a cross-owner lease (plan-review, architecture) | `getAgentCredential()` has two production callers (`agent-runner.ts`, `cc-dispatcher.ts`), both via `resolveKeyOwnerThenLease(userId, userId, ...)`, so in production `crossOwner` is true only when `delegationId` is set; the owner-mismatch shape without a delegation id is reachable only through a direct `runWithByokLease` call. `failAuthModeClosed` is therefore reachable only on the OWNER path: delegates never see the new `auth_mode_*` frames. | Keep both shapes in the gate (it is today's gate), test the owner-mismatch shape at lease level, and state the delegate limit in the ADR. |
| The binding's workspace vs the delegation's workspace (plan-review, architecture P1-1) | `bind_agent_engine_run` stamps `auth_mode` from the workspace of the conversation at creation; `resolveKeyOwnerThenLease` resolves the delegation against the caller's CURRENT workspace at turn time (`byok-resolver.ts` via `resolveCurrentWorkspaceId`). Resume is pinned (`ws-handler.ts:2280` rebinds the current workspace to the conversation's), an ordinary turn is not. | CTO R1: the skip additionally requires `binding.workspaceId === delegation workspace id` (Phase 2). |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the operator-only `oauth_unusable` / `oauth_token` friendly sign-in messages in apps/web-platform/server/agent-auth-user-message.ts gain one recovery sentence" [brief] | Phase 6, `agent-auth-user-message.ts` COPY table | mapped |
| 2 | "give it its own copy (touches the exhaustive `never` rail in mapByokLeaseCauseToErrorCode, the WS code enum, the zod schema and the UI)" [brief] | Phases 2, 3, 4 | mapped |
| 3 | "let the generic call-site Sentry mirror skip the event the lease already reported" [brief] | Phase 3 | mapped |
| 4 | "The deterministic reasons (unbound/invalid_value/no_resolver) need recovery wording (start a new conversation); the transient ones (read_failed/resolver_failed) need retry wording." [brief] | Phase 2 (cause split) + Phase 3/4 copy | mapped |
| 5 | "the Settings helper line ... and the amber `user-provider-disclosure` are inexact for delegated members and non-owners ...; tune or hide for them." [brief] | Phase 5 | mapped (tuned, not hidden: CLO) |
| 6 | "Let `api-key` mode bypass that refusal ONLY IF the legal read allows it" [brief] | Phase 2 (#11594 skip) after the CLO ruling | mapped |
| 7 | "Route that legal question to soleur:legal:clo (binding ruling, recorded in decision-challenges.md) BEFORE implementing" [brief] | Done at plan time; rows 1-4 of the decision file | mapped |
| 8 | "The owner-only gate for the subscription path under Automatic mode and the kill-switch/date gates must stay unchanged, with a test driving the real lease and a negative control" [brief] | Phase 1 tests (real `runWithByokLease`), Guard 1 | mapped |
| 9 | "the plan must list `git grep -l` over test/ for every changed basename and run every hit" [brief] | `## Test-impact sweep` | mapped |
| 10 | "check scripts/check-adr-ordinals.sh against fresh origin/main; markdown-lint ... if any .md changes" [brief] | Phase 7/8, AC11 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `byok-lease.ts`, `auth-mode-error.ts` (cause split, skip) | asks 2, 6 | asked |
| `agent-auth-user-message.ts` (copy, frame builder, predicate) | asks 1, 2, 3 | asked |
| `agent-runner.ts`, `ws-handler.ts`, `cc-dispatcher.ts`, `soleur-go-runner.ts` | ask 3: "let the generic call-site Sentry mirror skip the event the lease already reported" | asked |
| `lib/types.ts`, `lib/ws-zod-schemas.ts`, `lib/ws-client.ts`, `components/chat/chat-surface.tsx` | ask 2: "the WS code enum, the zod schema and the UI" | asked |
| `components/settings/agent-engine-settings.tsx` | ask 5 | asked |
| `auto-sync-trigger.ts`, `server/engine-binding-auth-mode.ts`, `server/byok-resolver.ts` | — | inferred — justification: `auto-sync-trigger` duck-types `fetch_failed` + `reason` today and its no-retry/retry decision must stay exact after the cause split (explicit `cause !== "auth_mode_unavailable"`); the resolver pair carries the delegation workspace id so the skip cannot be funded by a mode stamped in another workspace (CTO R1, the single-user-incident control) |
| `agent-on-spawn-requested.ts` (`BYOK_LEASE_CAUSES`) | — | inferred — justification: exhaustiveness map of `ByokLeaseError["cause"]` values; omitting the new causes leaves a silent hole in dead-letter classification |
| ADR-048 addendum, legal-audit addendum | ask 7 / CLO conditions | asked (CLO-required documentation edits) |
| Test files | ask 8, ask 9 | asked |
| The one follow-up issue (delegate copy) | — | inferred — justification: CTO R4 found a genuine out-of-scope defect (delegate dead-end copy); a deferral without a tracking issue is invisible (`wg-when-deferring-a-capability-create-a`) and net issue flow stays 2 closed vs 1 filed |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 33 | Estimated changed lines: ~950 (about 480 of them tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file and line counts exceed two thresholds, but the operator instruction is explicit ("Implement BOTH follow-ups ... in ONE PR"); the natural seam is #11599 (items 1-3) versus #11594 (`byok-lease.ts` skip + resolver pair + their tests + ADR/audit addenda), and the plan already splits the work into those two commits so a revert can take out one without the other.

## User-Brand Impact

- **If this lands broken, the user experiences:** a delegated member's agent run failing with a generic error although the workspace owner chose "My API key" (regression of the skip), or an owner seeing the misleading "Your API key is invalid or expired / Update key" card for an unresolvable authentication mode (regression of the card).
- **If this leaks, the user's workflow/credential is exposed via:** a bug in the cross-owner skip that selects or serves a grantor's Claude subscription token (`anthropic_oauth`) to another workspace member, putting the grantor's Claude account at Anthropic ToS risk (the owner-only, no-share basis of the 2026-06-16 CLO audit); or a mode stamped in a workspace the member owns funding a run on another workspace's grantor key.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the skip sits adjacent to the one path that could hand one user's subscription token to another, one user's account and irreversible; ruled by the CTO (decision file), signed off by the CPO with changes applied.

CPO sign-off: GRANTED-WITH-CHANGES at plan time (decision file). `soleur:engineering:review:user-impact-reviewer` runs at review (conditional-agent block of `soleur:review`), pointed at commit 1.

## Proposed Solution

### Architecture

```text
failAuthModeClosed(reason)                       api-key skip (cross-owner only)
  reason NOT in {read_failed,resolver_failed}      fetchAgentCredentialIntoSlot
     -> ByokLeaseError("auth_mode_unresolved")       isCcOauthEnabled() && crossOwner
  reason in {read_failed,resolver_failed}              -> crossOwnerChoseApiKey(slot)  [quiet; exact "api-key" only;
     -> ByokLeaseError("auth_mode_unavailable")            binding workspace must equal the delegation workspace]
  (one reportSilentFallback, op auth-mode-unresolved)   true  -> skip oauth SELECT + owner gate -> grantor "anthropic" row
        |                                                false -> today's path, byte-for-byte
        v   duck-typed (name + cause) in agent-auth-user-message.ts
 authFailureFrameFromLeaseError(err)  ->  { type:"error", errorCode:"auth_mode_unresolved"|"auth_mode_unavailable", message }
        |
   agent-runner x2 / ws-handler / cc-dispatcher dispatch catch  -> sendToClient(frame); Sentry mirror skipped
   soleur-go-runner queryFactory mirror skipped; cc-dispatcher generic else NOT reached
        |
   lib/ws-client.ts error case: mark_last_user_unanswered + setLastError({code,message,action?}) - no teardown, not a credential-blocked code
   components/chat/chat-surface.tsx: ErrorCard "Authentication Mode Unavailable", no Reconnect
```

### The #11594 skip (byok-lease.ts) — CLO conditions and CTO review rulings encoded

```ts
// sketch only; the work phase writes tests first (cq-write-failing-tests-before)
const crossOwner = slot.delegationId != null || slot.keyOwnerUserId !== slot.workspaceContextUserId; // computed ONCE
const skipSubscription = isCcOauthEnabled() && crossOwner && (await crossOwnerChoseApiKey(slot));
if (isCcOauthEnabled() && !skipSubscription) {
  /* existing block, unchanged: select oauth row, date gate, owner gate (throws when crossOwner), resolveLeaseAuthMode,
     then, immediately before decryptRow(oauthRow): if (crossOwner) throw new OauthDelegationForbiddenError()  // R2 tripwire */
}
/* existing api_key branch: fetchProviderRow(slot, "anthropic") -> MissingByokKeyError | decrypt;
   breadcrumb: owner { scheme } byte-identical; cross-owner { scheme, delegated: true } */

async function crossOwnerChoseApiKey(slot: LeaseSlot): Promise<boolean> {
  if (!slot.resolveAuthMode) { noteSkipDenied("unresolved"); return false; }
  let mode: unknown;
  let outcome: "non_api_key" | "unresolved" | "workspace_mismatch" = "non_api_key";
  try { mode = await slot.resolveAuthMode(); }
  catch (err) { mode = undefined; outcome = err instanceof ConversationAuthModeError && err.reason === "workspace_mismatch" ? "workspace_mismatch" : "unresolved"; } // quiet: no event, no failAuthModeClosed
  assertLeaseAlive(slot);                  // a dead scope propagates; it is not "false"
  if (mode === "api-key") return true;     // exact equality; never truthiness
  noteSkipDenied(outcome);                 // info log, closed enum, no ids or values
  return false;
}
```

Properties of the shape: (1) the kill-switch gate stays outermost and unchanged; (2) the owner path (`crossOwner === false`) never calls the helper, so owner behavior is byte-for-byte unchanged, including "no mode read for a key owner without a subscription row" (AC5 of #11591) and an owner breadcrumb that is exactly `{ scheme }` (the existing test pins "only the scheme"); (3) on `false` the existing block runs exactly as today, so `managed`, unresolved, invalid, no resolver, resolver error and workspace mismatch all still select the grantor row and throw `OauthDelegationForbiddenError` when it exists, and a delegated lease with no oauth row still reaches the api key (no new failure mode); (4) the resolver is called once per cold fetch and the credential is cached in the slot afterwards; (5) the date gate stays attached to the subscription-row path (the skip path never selects the row, so it never reaches `OauthNotYetPermittedError`; documented in the code comment and the ADR addendum); (6) the re-assertion before `decryptRow(oauthRow)` keeps the invariant local to the decrypt even if the skip logic is edited later.

**Workspace binding (CTO R1, the single-user-incident control).** The mode a conversation carries is stamped from the workspace it was created in; the delegation is resolved against the caller's CURRENT workspace at turn time, and only resume pins the two together (`ws-handler.ts:2280`). So the skip additionally requires equality: `resolveKeyOwnerThenLease` passes `delegationWorkspaceId` (its already-resolved `workspaceId`) to `runWithByokLease` only when `data.delegation_id` is set (optional field on `ByokLeaseArgs` and the slot); `makeConversationAuthModeResolver(userId, conversationId, expectedWorkspaceId?)` compares it with `run.binding.workspaceId` (already normalized by `normalizeRun`) and throws `ConversationAuthModeError("workspace_mismatch")` on a difference. The call sites in `agent-runner.ts` and `cc-dispatcher.ts` keep calling `makeConversationAuthModeResolver(userId, conversationId)` unchanged (the pinned wiring test counts that exact text); the delegation workspace reaches the resolver through the lease: `ByokLeaseArgs.resolveAuthMode` becomes `(ctx?: { expectedWorkspaceId?: string }) => Promise<string>` and the helper passes `{ expectedWorkspaceId: slot.delegationWorkspaceId }` for the cross-owner pre-check only. The owner path calls `resolveAuthMode()` with no argument, so it is unchanged. `workspace_mismatch` joins the closed reason union as a deterministic reason (not in the transient set). The ADR states the invariant as "binding workspace equals delegation workspace, and that workspace's owner chose `api-key`".

### Cause split (byok-lease.ts + auth-mode-error.ts)

`server/auth-mode-error.ts` (import-free leaf) gains `TRANSIENT_AUTH_MODE_REASONS = ["read_failed", "resolver_failed"]`, the reason union (adds `unbound`, `invalid_value`, `no_resolver`, `workspace_mismatch`), and `classifyAuthModeReason(reason)`: `TRANSIENT.has(reason) ? "auth_mode_unavailable" : "auth_mode_unresolved"` — every other reason, including future ones, is deterministic (fail-safe: not auto-retried). `failAuthModeClosed` throws `new ByokLeaseError(classifyAuthModeReason(reason), "Authentication unavailable; retry shortly", reason)` — the internal message is unchanged and never shown to a user. `ByokLeaseError["cause"]` and its constructor gain the two causes and `reason` narrows from `string` to the union; `mapByokLeaseCauseToErrorCode` gains two cases returning the same-named WS codes (its return type widens; `resolveSessionErrorCode`'s return type follows; the typed frame is sent before `resolveSessionErrorCode` runs, so the mapper cases are the rail's second source of truth and an equivalence test pins that the frame's code equals the mapper's). A genuine `api_keys` read failure keeps `fetch_failed` -> `key_invalid`. `auto-sync-trigger.ts` retries only `cause === "auth_mode_unavailable"` (and its existing non-lease rules) and treats any other lease refusal with a `reason` as deterministic.

### Frame and copy (agent-auth-user-message.ts)

- `COPY` oauth_token cells (all kinds except `session_expired`) end with the single constant `RECOVER_VIA_API_KEY_MODE`: `If you have an Anthropic API key saved, you can instead choose "My API key" in Settings, then start a new conversation (a conversation keeps the mode it started with).` Quoted labels match `authModeLabel` in `agent-engine-settings.tsx` exactly. The `api_key` and `neutral` cells are unchanged (no tenant sees operator wording).
- ONE new exported predicate `isLeaseRefusalReported(err)` (duck-typed on name `ByokLeaseError` + cause in {`oauth_unusable`, `auth_mode_unresolved`, `auth_mode_unavailable`}; never `instanceof`; deliberately NOT `fetch_failed`) used at every skip point, in `logSessionFailure` (INFO instead of ERROR; the `refused` message for the new class is derived from `messages.failed` so call-site strings stay) and by the client-side clear (via a tiny shared code list, see Client). `authModeUnresolvedFrame(cause)` builds the typed frame; `authFailureFrameFromLeaseError` is generalised to return `AuthFailureFrame | AuthModeUnresolvedFrame | null`, so agent-runner (x2) and ws-handler need no frame-branch change. `cc-dispatcher.ts` uses the same helper in its frame ladder.
- Card copy (term "authentication mode" matches the Settings label, CPO): deterministic `We couldn't confirm which authentication mode this conversation uses, so your message was not processed. Start a new conversation to continue.`; transient `We couldn't check which authentication mode this conversation uses just now, so your message was not processed. Please send it again in a moment.`
- The file keeps its constraints: no Sentry/observability/diagnostic imports (`test/agent-auth-import-boundary.test.ts`), no tokens `engine-binding-auth-mode` / `resolveAuthMode` (`test/byok-lease-mode-wiring.test.ts`), plain text only (no backticks, no middle dot).

### Client

`lib/types.ts` `WSErrorCode` and `lib/ws-zod-schemas.ts` `errorSchema.errorCode` gain `auth_mode_unresolved` and `auth_mode_unavailable` in the same change. `lib/ws-client.ts` `error` case, placed AFTER the `isCredentialErrorCode` branch (so the teardown source-gate test slice is unaffected) and after the `rebindArmedRef` check: dispatch `mark_last_user_unanswered` (the turn did not complete, as the credential branch does), then `setLastError({ code, message: msg.message, ...(code === "auth_mode_unresolved" ? { action: { label: "Start a new conversation", href: "/dashboard/chat/new" } } : {}) })` and return — no `teardown()`, not added to `isCredentialErrorCode` (composer stays enabled). `lastError` is cleared only on mount and `reconnect()` today, so `sendMessage` gains a scoped clear after its credential-blocked and OPEN checks: `setLastError((p) => (p && (p.code === "auth_mode_unresolved" || p.code === "auth_mode_unavailable") ? null : p))`, leaving every other code's behavior untouched. `components/chat/chat-surface.tsx`: `credentialCardCopy` returns title "Authentication Mode Unavailable" for both codes, and `onRetry` is undefined for both (Reconnect does not resend and the socket stays up; the transient copy says to send again, the deterministic card's only control is its action); both cards stay dismissible (CTO R3). A repeated deterministic refusal emits one lease event per send; accepted without a debounce (user-paced, subscription-holder population; add a per-conversation debounce if volume shows).

### Settings (agent-engine-settings.tsx, minimal edit: draft PR #9051 also touches it)

Two module-level constants plus two ternaries on the existing `isOwner` prop; no structural change, ids (`auth-mode-helper`, `user-provider-disclosure`) and `aria-describedby` unchanged, owner text byte-identical. Non-owner helper (CLO): `This setting is chosen by the workspace owner. It applies to new conversations; existing conversations keep the mode they started with.` Non-owner disclosure (CLO, kept not hidden): `Conversations in this workspace use a provider account saved by you or by another workspace member. Prompts, files, and outputs sent through this engine are subject to that provider's retention, region, and account terms, and to the account holder's own settings and access. Soleur-managed provider access remains restricted. Only submit data you are authorized to share with the provider.` The disclosure is one element, so its single ternary also covers the `api-key`-only disclosure other engines show to the same viewer (the CLO text says "this engine"). The unknown-identity default (`?? true` in `settings-content.tsx`) is unchanged.

## Files to Edit

Paths under `apps/web-platform/` unless stated. Commit 1 = #11594 lease work (first five entries + their tests); commit 2 = everything else (CTO R6).

- `server/auth-mode-error.ts` — transient set, reason union (+ `workspace_mismatch`), `classifyAuthModeReason` (stays import-free)
- `server/byok-lease.ts` — cause union + constructor, `failAuthModeClosed`, `mapByokLeaseCauseToErrorCode`, `crossOwnerChoseApiKey` + restructure, R2 tripwire, `delegationWorkspaceId` on args/slot, breadcrumb `delegated`, JSDoc updates
- `server/byok-resolver.ts` — pass `delegationWorkspaceId` to `runWithByokLease` when a delegation is active
- `server/engine-binding-auth-mode.ts` — resolver accepts `{ expectedWorkspaceId }`, throws `ConversationAuthModeError("workspace_mismatch")`
- `server/auto-sync-trigger.ts` — retry only `cause === "auth_mode_unavailable"`; drop its private deterministic set
- `server/agent-auth-user-message.ts` — recovery constant, `isLeaseRefusalReported`, frame builder, generalised helpers
- `server/agent-runner.ts` — `resolveSessionErrorCode` return type; two mirror-skip sites use `isLeaseRefusalReported`
- `server/ws-handler.ts` — `startAgentSession` catch: skip predicate (frame already via `authFailureFrameFromLeaseError`)
- `server/cc-dispatcher.ts` — dispatch catch: BOTH `isOauthUnusableLeaseError` sites (the info-log branch in the mirror ladder and the frame ladder, currently two separate branches) gain the new causes; the typed-frame branch sits above the generic else, mirrors the `oauth_unusable` branch including worktree-lease release (the credential lease also refuses before the factory's own cleanup), keeps `denied_jti` precedence
- `server/soleur-go-runner.ts` — queryFactory mirror skip predicate
- `server/inngest/functions/agent-on-spawn-requested.ts` — `BYOK_LEASE_CAUSES` becomes a `Record<ByokLeaseError["cause"], true>`-style exhaustive map including both new causes (the current `satisfies` only checks membership)
- `lib/types.ts`, `lib/ws-zod-schemas.ts`, `lib/ws-client.ts`
- `components/chat/chat-surface.tsx`, `components/settings/agent-engine-settings.tsx`
- `knowledge-base/engineering/architecture/decisions/ADR-048-operator-cc-oauth-credential-selection-by-consumer-class.md` — #11594/#11599 addendum, in-place "Superseded" markers on the "Out of scope, tracked in #11594" sentence and the "Failure surface" bullet, `related: [..., 11594, 11599]`; no trailing blank line at EOF
- `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md` — append a dated addendum section only (CLO: original content untouched)
- Tests (existing): `test/byok-lease-credential-type.test.ts` (rewrite the "AC4 gate order" rows; lines asserting `cause === "fetch_failed"` for unresolved modes; the "only the scheme" breadcrumb test stays), `test/byok-lease-auth-mode-binding.test.ts` (rewrite AC16; asserts at its `fetch_failed` lines; delegated cases), `test/engine-binding-auth-mode.test.ts` (mismatch), `test/agent-auth-user-message.test.ts`, `test/agent-engine-settings.test.tsx`, `test/server/auto-sync-trigger.test.ts` (fixtures move to the new causes), `test/agent-auth-friendly-error-wire.test.ts`, `test/agent-auth-friendly-error-wire-legacy.test.ts`, `test/cc-dispatcher-auth-failure-wiring.test.ts`, `test/chat-surface-credential-blocked.test.tsx` (negative control only), `test/server/byok-lease.test.ts` (negative control only)

## Files to Create

- `test/auth-mode-unresolved-frame.test.ts` — classify, mapper/frame equivalence, `isLeaseRefusalReported` cause table (incl. `fetch_failed` and `escape` negative controls), frames, `logSessionFailure`, zod parse of both codes
- `test/auth-mode-unresolved-client.test.tsx` — `ws-client` branch and `chat-surface` card in one file (no teardown, `mark_last_user_unanswered`, scoped clear on send, no Reconnect, action only on the deterministic code, composer enabled)
- `test/server/ws-handler-lease-refusal.test.ts` — behavioural test of the `startAgentSession` `.catch` (frame + zero mirror), reusing the mock pattern of `test/server/ws-handler-approval.test.ts`; a second case drives `handleSessionError` through `sendUserMessage` (agent-runner)
- `knowledge-base/project/specs/feat-one-shot-11594-11599-auth-mode-followups/tasks.md`

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies were searched for each path in the two lists above; no hit. Re-run at work time: the list can change.)

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-048 (no new ADR, so no ordinal to claim; `bash scripts/check-adr-ordinals.sh` passes on fresh `origin/main`). The addendum records, worded as the shipped state: (1) the cross-owner `api-key` skip and the CLO basis (the owner-only, no-share basis attaches to the token's use; the row is not selected; fail-closed set; `managed` delegated stays refused and is out of scope); (2) the invariant "binding workspace equals delegation workspace, and that workspace's owner chose `api-key`" (CTO R1); (3) the cause split and the two WS codes, and that `failAuthModeClosed` is owner-path only so delegates never see them; (4) the accepted semantic that the mode is the workspace OWNER's setting, so a delegate can run on a grantor's API key because the workspace owner chose `api-key`, and the grantor need not be the workspace owner; (5) the date gate stays on the subscription-row path; (6) the quiet-refusal limit for a transient resolver failure on a cross-owner lease and the pointer to the follow-up issue for delegate copy; (7) supersession of the 2026-10-30 "Failure surface" bullet and the "Out of scope, tracked in #11594" sentence, marked in place. Markdown rule: end the file with exactly one newline.

### C4 views

No C4 change. Read in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Checked: external actors (`founder` is the only workspace-user actor; the delegated member is a workspace user, not a separate modeled actor and none is added), external systems (`anthropic` unchanged), data stores (the web-app store at `model.c4` "Users, BYOK-encrypted API keys, conversation sessions" unchanged; no new table), access relationships (`platform.webapp.api -> platform.engine.claude.binding`, `binding -> adapter` unchanged; no lease or delegation edge exists and the lease is intentionally unmodeled). `plugins/soleur/test/c4-count-parity.test.sh` run on the worktree: `Failed: 0`. The `binding` description ("supplies the auth mode that selects the Agent-SDK credential at lease time") is not falsified by this PR.

### Sequencing

All ADR work lands in this PR; nothing is deferred.

## Domain Review

**Domains relevant:** Legal, Engineering, Product

### Legal (CLO)

**Status:** reviewed
**Assessment:** Four binding rulings recorded in the decision file. #11594 ALLOW-WITH-CONDITIONS (owner-only basis attaches to token use; no re-evaluation trigger fires; no external counsel before merge; the row must not be selected; exact `api-key` only). Non-owner disclosure kept and reworded (not hidden). Operator-only recovery sentence naming the Settings labels allowed. Follow-ups owed by this plan: confirm DPD item (w) and AUP 5.6 ("Grantor (Workspace Owner)") cover a grantor who is not the workspace owner and flag any gap to the CLO instead of editing `docs/legal/**` (Phase 7). GDPR gate: the CLO ruling states no Art. 30, Privacy Policy, DPD or GDPR Policy change; no new processing activity, no schema or migration.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Nine technical rulings at plan time (cause split A, module placement, call-site wiring, client behavior and copy, recovery-sentence scope, #11594 mechanism a-e, ADR/C4, threshold, traps) plus six rulings on the plan-review findings (R1 workspace binding, R2 tripwire, R3 client lifecycle, R4 delegate copy deferral, R5 telemetry, R6 cuts) in the decision file. Plan-review panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow (single-user-incident escalation); the named CEO/design/devex panel was not re-run because the CPO, CTO and CLO had already ruled on the same content at plan time and the UI edits are excluded copy.

### Product (CPO)

**Status:** reviewed
**Assessment:** GRANTED-WITH-CHANGES; changes applied (term "authentication mode", the existing `byok_key_missing` exit documented, backend test condition AC1/Guard 1).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer
**Skipped specialists:** soleur:product:design:ux-design-lead (no new screen, modal or flow; the shared UI-surface term list excludes pure copy changes with no structural or layout change, and the one new element is an action on the existing `ErrorCard`; ruled in the decision file), soleur:marketing:copywriter (not recommended by any domain leader)
**Pencil available:** N/A (no new UI surface)

#### Findings

Both error cards have an exit (deterministic: "Start a new conversation"; transient: send again, the card clears on the next send). The non-owner member sees no key-related action, which is correct since members cannot change the mode. Spec-flow gaps resolved: unanswered-message marking, scoped clear on send, no Reconnect, characterization of the delegate dead ends (follow-up issue), accepted per-send event volume.

## Guard Contract

### Guard 1 — cross-owner `api-key` skip is exact, quiet, workspace-bound and row-free

**Property.** A cross-owner lease selects, decrypts or serves the key owner's `anthropic_oauth` row never, in any mode, and skips the owner-gate refusal only when the conversation's mode resolves to exactly the string `api-key` AND the binding's workspace equals the delegation's workspace.

**Assembly.** The lease has ONE chokepoint for the agent credential: `fetchAgentCredentialIntoSlot` (every `getAgentCredential()` cold fetch; the slot caches afterwards). Cross-owner is `slot.delegationId != null || slot.keyOwnerUserId !== slot.workspaceContextUserId`, computed once there. Production reaches it through `resolveKeyOwnerThenLease` from `agent-runner.ts` (x1 SDK call) and `cc-dispatcher.ts` (x1), where the owner-mismatch shape without `delegationId` cannot occur (`workspaceContextUserId` equals the caller); that shape is reachable only by a direct `runWithByokLease` call and is therefore tested at lease level. All five `resolveKeyOwnerThenLease` branches flow through the single `runWithByokLease` (pinned by `byok-lease-mode-wiring.test.ts`). REST-only callers use `getRestApiKey`, which reads only `provider='anthropic'` and cannot reach the oauth row by construction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace `mode === "api-key"` with truthiness or `mode !== "managed"` | RED (parameterized negative controls: `managed`, `null`, `undefined`, `"API-KEY"`, `"api-key "` with a trailing space, `"true"` each still throw `OauthDelegationForbiddenError`) |
| 2 | Delete the `crossOwner &&` operand so the helper also runs for owners | RED (the #11591 "no mode read for a key owner without a subscription row" test; owner breadcrumb stays exactly `{ scheme }`) |
| 3 | Move the oauth SELECT back above the helper | RED (delegated `api-key` lease: the real-binding `eqs` list never contains `["api_keys","provider","anthropic_oauth"]`; credential-type harness `providersQueried` never contains `anthropic_oauth`) |
| 4 | The helper returns `true` on a throwing or absent resolver, or reports through `failAuthModeClosed` | RED (resolver-throws / no-resolver negative controls throw `OauthDelegationForbiddenError`; delegated no-oauth-row + throwing resolver reaches the api key with zero error-tracker events) |
| 5 | Remove the `isCcOauthEnabled()` operand from the skip condition | RED (a DELEGATED kill-switch-off test: resolver never called, oauth never queried; the existing owner kill-switch test cannot see this) |
| 6 | Drop `assertLeaseAlive` after the resolver await | RED (scope ends during the resolver: `escape`, nothing read afterwards) |
| 7 | Narrow `crossOwner` to `delegationId != null` | RED (owner-mismatch lease-level test, no `delegationId`, still refused in `managed`; skipped only on `api-key`) |
| 8 | Drop the workspace comparison (resolver ignores `expectedWorkspaceId`) | RED (binding `api-key` in workspace A, delegation in workspace B, grantor with both rows: `OauthDelegationForbiddenError`, no `decryptRow` of either grantor row; positive control with equal workspaces serves the grantor's api key) |
| 9 | Remove the re-assertion before `decryptRow(oauthRow)` AND force `skipSubscription` false-negative path (`managed` + `crossOwner` reaches the decrypt) | RED (test that stubs the owner gate away is not possible; instead a test calls the managed branch with `crossOwner` true via a delegated lease whose gate is bypassed by a spy on `decryptRow` count = 0 and an expected `OauthDelegationForbiddenError`) |

**Harness rows.** (H1) The suite must follow the persisted binding, not a constant: the real-binding delegated test flips the binding between two leases on one fixture; a stub that always answers `api-key` while the binding says `managed` must go RED. (H2) Must-PASS inputs that are NOT the canonical: a delegated lease whose grantor has NO oauth row and a throwing resolver (still the api key), and an owner lease with an oauth row in `managed` (still the subscription token) — a guard that rejects everything fails these.

**Anchor.** No stored value is compared. A weakening of the equality or the workspace check is caught by rows 1 and 8 in the same suite; the CLO ruling returns the change to the CLO if the skip is widened (decision file, CLO Q2 row).

### Guard 2 — "already reported by the lease" predicate is cause-exact

**Property.** The call-site error-tracker mirror is skipped exactly for lease refusals the lease itself reported (`oauth_unusable`, `auth_mode_unresolved`, `auth_mode_unavailable`) and never for a genuine `fetch_failed`.

**Assembly.** Five mirror points call the single exported `isLeaseRefusalReported`: `agent-runner.ts` startAgentSession catch and `handleSessionError`, `ws-handler.ts` startAgentSession `.catch`, `soleur-go-runner.ts` queryFactory catch, `cc-dispatcher.ts` dispatch catch (info-log branch above `mirrorWithDebounce`); `logSessionFailure` calls it too.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `fetch_failed` to the predicate, or drop one of the three causes | RED (single `it.each` over `[oauth_unusable, auth_mode_unresolved, auth_mode_unavailable]` positive, `[fetch_failed, escape, decrypt_failed]` negative, in `auth-mode-unresolved-frame.test.ts`; a real DB-read `fetch_failed` is still mirrored and still sent as `key_invalid` in the legacy-wire, friendly-wire and cc wiring suites) |
| 2 | Revert any ONE of the five call sites to `isOauthUnusableLeaseError` | RED (one behavioural wire test per site — legacy `startAgentSession`, legacy `handleSessionError`, ws-handler, soleur-go queryFactory, cc dispatch — asserts zero call-site mirror events for each new cause, with a spy that is proven live by asserting the mirror IS called for a non-lease error in the same test) |
| 3 | Key the predicate on `instanceof ByokLeaseError` | RED (tests throw a name-and-cause look-alike `Error`, as the existing `oauth_unusable` tests do, and a real class instance; both must match) |

**Harness rows.** (H1) The spy-liveness assertion in row 2. (H2) Must-PASS non-canonical: a `ByokLeaseError("escape")` and a `MissingByokKeyError` are still mirrored.

**Anchor.** The predicate lives in one file; set identity (three exact causes) is asserted by the `it.each` list, not a count floor.

## Implementation Phases

Two commits (CTO R6): commit 1 = #11594 lease work with its tests and the ADR/audit addenda for it (Phases 1a, 2, 7a); commit 2 = #11599 (Phases 1b, 3-6, 7b). `soleur:engineering:review:user-impact-reviewer` is pointed at commit 1.

### Phase 0 — Prerequisites (no code)

- Verify a clean tree on fresh `origin/main` (`git fetch origin main`; `bash scripts/check-adr-ordinals.sh`). Install dependencies if absent (`cd apps/web-platform && npm ci`).
- Re-run the Open Code-Review Overlap query for the file lists.
- Confirm the `/dashboard/chat/new` route renders (`app/(dashboard)/dashboard/chat/[conversationId]/` with `conversationId = "new"`; already linked from `components/command-palette/use-shortcuts.tsx`).
- Confirm in `lib/supabase/tenant.ts` that `getFreshTenantClient` dedups the in-flight mint per user (the extra caller-scoped mint of the cross-owner pre-check), and that `bind_agent_engine_run` is the only place `auth_mode` is stamped (it reads the workspace default; a member cannot choose it).
- Baseline: run the Test-impact sweep (below) once BEFORE editing and record failures as pre-existing (`wg-when-tests-fail-and-are-confirmed-pre`).

### Phase 1 — RED tests first (cq-write-failing-tests-before)

1a (commit 1): `describe` blocks in `byok-lease-credential-type.test.ts` and `byok-lease-auth-mode-binding.test.ts` (no separate new lease test file, CTO R6): the AC1/AC2/AC3/AC4/AC15/AC16 cases, the rewritten "AC4 gate order" and AC16 cases, `engine-binding-auth-mode.test.ts` mismatch. 1b (commit 2): `auth-mode-unresolved-frame.test.ts`, `auth-mode-unresolved-client.test.tsx`, `ws-handler-lease-refusal.test.ts`, the new cases in `agent-auth-user-message.test.ts`, the three wire suites, `auto-sync-trigger.test.ts`, `agent-engine-settings.test.tsx`. Watch each fail for the right reason before any production edit.

### Phase 2 — Lease (commit 1)

`auth-mode-error.ts` (transient set, union, classify, `workspace_mismatch`), `byok-lease.ts` (cause split, mapper, `crossOwnerChoseApiKey`, restructure, R2 tripwire, `delegationWorkspaceId`, breadcrumb, JSDoc: `ByokLease.getAgentCredential`, `ByokLeaseArgs.resolveAuthMode`, `OauthDelegationForbiddenError` now say "unless the conversation's mode is exactly api-key in the delegation's workspace"), `byok-resolver.ts`, `engine-binding-auth-mode.ts`, `auto-sync-trigger.ts`, `agent-on-spawn-requested.ts`. Make the 1a tests GREEN.

### Phase 3 — Server wiring (commit 2)

`agent-auth-user-message.ts` helpers and frames; the five mirror points; the cc-dispatcher frame branch and BOTH of its `isOauthUnusableLeaseError` sites; `resolveSessionErrorCode` type. No new import from `byok-lease` at any call site.

### Phase 4 — Client (commit 2)

`lib/types.ts` + `lib/ws-zod-schemas.ts` (same commit), `lib/ws-client.ts`, `components/chat/chat-surface.tsx`. Run `npx tsc --noEmit` (the `_SchemaCovers` proof fails the build if the two enums drift).

### Phase 5 — Settings (commit 2)

`agent-engine-settings.tsx` constants and ternaries only (one ternary per element, so the disclosure change covers every engine that shows it; the CLO text says "this engine"). Re-check against draft PR #9051 (`gh pr diff 9051 -- apps/web-platform/components/settings/agent-engine-settings.tsx`); keep the hunks small and away from the engine-radio block.

### Phase 6 — Recovery sentence (commit 2)

One constant appended to five `oauth_token` cells; update the pinned copy test.

### Phase 7 — Documentation, legal follow-ups, issues

7a (commit 1): ADR-048 addendum for #11594 (CLO basis, not-selected rule, fail-closed set, workspace invariant, accepted grantor semantics, date gate scope, delegate limit: delegates never see the `auth_mode_*` frames because `failAuthModeClosed` is owner-path only, and a transient resolver failure on a cross-owner lease is a quiet refusal with an info-log outcome) and the dated addendum appended to the CLO audit. 7b (commit 2): the #11599 addendum text, in-place supersession markers, `related:`. Verify (read-only) that DPD item (w) and AUP 5.6 ("Grantor (Workspace Owner)") cover a grantor who is not the workspace owner (check the delegation-creation RPC for an owner requirement); record the result in the decision file and flag a gap to the CLO — no `docs/legal/**` edits. File ONE follow-up issue (genuine out-of-scope defect, CTO R4): copy for a delegated member in `managed` mode (`OauthDelegationForbiddenError` renders generic text) and for a member whose grantor has no API key (`byok_key_missing` card points at the member's own Settings); label `deferred-scope-out`, milestone per `knowledge-base/product/roadmap.md`, `Ref #11599`. Net flow: 2 issues closed, 1 filed. `bash scripts/markdown-lint.sh --repo-sweep` (a trailing blank line in ADR-048 failed CI last time; verify with `tail -c 2` that the file ends with one newline).

### Phase 8 — Verification

Run every item in "Verification commands" and the Test-impact sweep. Update `tasks.md`. PR body: `Closes #11594`, `Closes #11599` (only if every AC below holds), plus the `## Changelog` section.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (#11594, Guard 1, credential-type harness). A real `runWithByokLease` lease with `delegationId` set (and a second with `keyOwnerUserId !== workspaceContextUserId`, no `delegationId`, direct-lease only), kill-switch on, grantor holding both `anthropic` and `anthropic_oauth` rows, resolver returning exactly `"api-key"`: returns `{ scheme: "api_key" }`, `providersQueried` never contains `anthropic_oauth`, exactly one buffer is decrypted, and the `agent-credential-selected` breadcrumb is `{ scheme: "api_key", delegated: true }`; the owner breadcrumb stays exactly `{ scheme }`.
- [ ] AC2 (negative controls). Same fixture with the resolver returning `"managed"`, `null`, `undefined`, `"API-KEY"`, `"api-key "`, `"true"`, throwing, or absent: each throws `OauthDelegationForbiddenError` and logs one closed `outcome` (`non_api_key` or `unresolved`) at info; with the grantor's oauth row absent each reaches the api key with zero error-tracker events; a delegated `api-key` lease whose grantor has no `anthropic` row throws `MissingByokKeyError` and never queries the oauth row; a delegated kill-switch-off lease never calls the resolver and never queries the oauth row.
- [ ] AC3 (real binding, `byok-lease-auth-mode-binding.test.ts`; the table-aware fake exposes only `eqs`, so assertions are on `eqs` and not on `providersQueried`). A delegated lease driven by `makeConversationAuthModeResolver(MEMBER, CONV, expectedWorkspaceId)` follows the persisted binding: `api-key` -> api key and `eqs` contains no `["api_keys","provider","anthropic_oauth"]`; flipping the binding to `managed` between two leases -> refused; a run bound by ANOTHER member (decoy, `created_by` mismatch) resolves `unbound` and the lease is refused, not served the API key.
- [ ] AC4 (owner path unchanged). The owner lease never calls the helper; owner `managed` still gets the subscription token; owner kill-switch off -> resolver never called; pre-date owner lease still throws `OauthNotYetPermittedError`. The old "AC4 gate order" table is rewritten: the pre-date row is kept verbatim, the delegated and owner-mismatch rows assert refusal for `managed`/unresolved and the skip for exact `api-key`. The old AC16 "refused before any binding read" test is rewritten: a delegated lease now reads the binding once and still refuses on `managed`.
- [ ] AC5 (cause split). `failAuthModeClosed` throws `auth_mode_unavailable` for `read_failed`/`resolver_failed` and `auth_mode_unresolved` for `unbound`/`invalid_value`/`no_resolver`/`workspace_mismatch` (`it.each` over all six), each with the closed `reason`, one `auth-mode-unresolved` event whose tags/extra carry only the reason; a DB read failure stays `fetch_failed` -> `key_invalid`; `mapByokLeaseCauseToErrorCode` returns the matching new codes (an equivalence test pins that the frame builder's code equals the mapper's) and the `never` rail still compiles.
- [ ] AC6 (wire, one event). For each emit path (legacy `startAgentSession`, legacy `handleSessionError` via `sendUserMessage`, Concierge dispatch, ws-handler `startAgentSession`) and each new cause: exactly one typed `error` frame with the matching `errorCode` and the exact card copy, zero call-site error-tracker events (the lease's own event is the only one), the Concierge resumable `session_id` is NOT cleared, and `logSessionFailure` logs INFO not ERROR. Behavioural tests, not source regexes. The same suites keep a negative control: a real `fetch_failed` is still mirrored and still sent as `key_invalid`.
- [ ] AC7 (client, one test file). Both codes: `mark_last_user_unanswered` is dispatched, `lastError` is set, `teardown()` is NOT called, the card has no Reconnect and stays dismissible, the next `sendMessage` clears this `lastError` (and leaves any other code untouched), neither code is a credential-blocked code (`isCredentialErrorCode` false; composer enabled). The deterministic code carries the "Start a new conversation" action (href `/dashboard/chat/new`); the transient code carries none. Card title "Authentication Mode Unavailable". The zod schema accepts both codes and still rejects an unknown one; `_SchemaCovers` compiles; `ws-client-key-invalid-source-gate.test.ts` passes unchanged.
- [ ] AC8 (recovery sentence). `authFailureCopy(kind, "oauth_token")` ends with the exact sentence for `not_logged_in`, `invalid_api_key`, `oauth_token_revoked`, `structured`, `oauth_unusable`; `session_expired`, every `api_key` cell and every `neutral` cell are byte-identical to today; the existing assertions (`/claude setup-token/`, no backticks, no middle dot, no tenant-visible subscription wording) pass; `agent-auth-import-boundary.test.ts` and `byok-lease-mode-wiring.test.ts` pass unchanged.
- [ ] AC9 (Settings). Owner render is byte-identical (existing tests unchanged); with `isOwner={false}` the helper line and the disclosure show the CLO-approved non-owner text, the disclosure is still present with `role="note"` and `data-testid="user-provider-disclosure"`, no text names a subscription, and the radios/select stay disabled.
- [ ] AC10 (auto-sync). `auth_mode_unavailable` is retried even when its message differs from the lease retry message (fixture built with a different message so deleting the explicit cause check turns it RED); every `auth_mode_unresolved` reason is not retried; fixtures at the old `fetch_failed` + reason lines move to the new causes.
- [ ] AC11 (docs). ADR-048 addendum present with both supersession markers in place; legal audit has the appended dated addendum with the original content unchanged (`git diff` shows additions only; no line removed or edited); decision file complete; `bash scripts/check-adr-ordinals.sh` passes against fresh `origin/main`; `bash scripts/markdown-lint.sh --repo-sweep` passes.
- [ ] AC12 (static gates). `cd apps/web-platform && npx tsc --noEmit` clean; `python3 scripts/lint-anthropic-content-position.py` clean (no `content[0]` added); `agent-sandbox-credential-deny.test.ts` passes (no bare lowercase word "credential" added to `server/agent-env.ts`, which is not edited); pr-quality-guards userId rule: no added `log.<level>(` line carries a bare `userId` (the new `logSessionFailure` branch and the pre-check outcome log pass closed fields only).
- [ ] AC13 (test impact). Every hit of the Test-impact sweep passes, including the suites that mock the `startAgentSession`/dispatcher graph (e.g. `test/server/email-triage-tools.test.ts`, which broke CI on #11590).
- [ ] AC14 (PR body). `Closes #11594` and `Closes #11599` only if AC1-AC13 and AC15-AC16 hold; otherwise `Ref` with the reason on the issue.
- [ ] AC15 (workspace binding, CTO R1). Lease-level: binding `api-key` stamped in workspace A, delegation active in workspace B, grantor holds both rows -> `OauthDelegationForbiddenError`, no `decryptRow` of either grantor row, info-log `outcome: workspace_mismatch`; positive control with equal workspaces serves the grantor's api key; resolver unit test for the mismatch (`ConversationAuthModeError("workspace_mismatch")`); the owner path passes no expected workspace and is unchanged.
- [ ] AC16 (characterization, CTO R4). Tests record the CURRENT rendering for a delegated member in `managed` mode (generic text) and for a grantor with no API key (`byok_key_missing` card); no copy change; the follow-up issue is filed and referenced in the ADR note.

### Post-merge (operator)

None. No production setting is touched (`CC_OAUTH_ENABLED` is already `1` in prd and unchanged); no migration; no infrastructure.

## Test-impact sweep

Source-text tests and mocked module graphs are invisible to import-edge test selection, so the work phase runs the UNION of these commands (from `apps/web-platform/`) and every hit, not only the named suites:

```bash
cd apps/web-platform
for b in agent-auth-user-message byok-lease auth-mode-error auto-sync-trigger agent-runner cc-dispatcher \
         soleur-go-runner ws-handler agent-on-spawn-requested ws-zod-schemas ws-client chat-surface \
         agent-engine-settings; do git grep -l "$b" -- test e2e; done | sort -u > "$SCRATCH/impact.txt"
wc -l "$SCRATCH/impact.txt"    # measured at plan time per basename: 6, 28, 2, 4, 140, 96, 43, 94, 10, 6, 55, 33, 2 hits before de-dup
git grep -l "fetch_failed\|auth-mode-unresolved\|resolver_failed\|no_resolver\|key_invalid\|isCredentialErrorCode\|WSErrorCode\|user-provider-disclosure\|auth-mode-helper" -- test e2e >> "$SCRATCH/impact.txt"
sort -u -o "$SCRATCH/impact.txt" "$SCRATCH/impact.txt"
npx vitest run $(cat "$SCRATCH/impact.txt" | grep -E '\.test\.(ts|tsx)$')
```

Named must-run suites (the ones that pin what this PR changes): `byok-lease-credential-type`, `byok-lease-auth-mode-binding`, `byok-lease-mode-wiring`, `server/byok-lease`, `agent-auth-user-message`, `agent-auth-import-boundary`, `agent-auth-friendly-error-wire`, `agent-auth-friendly-error-wire-legacy`, `cc-dispatcher-auth-failure-wiring`, `server/auto-sync-trigger`, `ws-client-key-invalid-source-gate`, `chat-surface-credential-blocked`, `agent-engine-settings`, `agent-sandbox-credential-deny`, `oauth-token-injection-site`, `server/email-triage-tools`, `agent-runner-unix-deny-wire`, `server/inngest/agent-on-spawn-requested-leader-loop`, `server/spawn-dead-letter`. Nine suites `vi.mock("@/server/byok-lease")` with partial factories (`byok-resolver-delegation-workspace`, `cc-dispatcher-prefill-guard`, `cc-dispatcher-real-factory`, `cc-dispatcher-warm-presandbox-mkdir`, `server/byok-effective-key`, `server/byok-resolver-fail-closed`, `server/inngest/agent-on-spawn-requested-leader-loop`, `server/inngest/cfo-on-payment-failed`, `server/inngest/github-on-event`): the plan adds NO new import from `byok-lease` outside `byok-lease` itself, and the shared reason set is imported from the import-free `server/auth-mode-error.ts`; if any of these fail the cause is a new import, not the mock.

## Verification commands

```bash
cd apps/web-platform && npx tsc --noEmit
cd apps/web-platform && npx vitest run test/byok-lease-credential-type.test.ts test/byok-lease-auth-mode-binding.test.ts test/auth-mode-unresolved-frame.test.ts test/agent-auth-user-message.test.ts
python3 scripts/lint-anthropic-content-position.py
bash scripts/check-adr-ordinals.sh
bash scripts/markdown-lint.sh --repo-sweep
python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-31-feat-auth-mode-followups-recovery-copy-and-delegated-api-key-plan.md
git grep -n "content\[0\]" -- apps/web-platform/server/agent-auth-user-message.ts   # pre-existing hits only; none added
```

## Observability

```yaml
liveness_signal:
  what: Sentry event op auth-mode-unresolved (feature byok-lease, tag reason) from the lease, and the agent-credential-selected breadcrumb {scheme, delegated}
  cadence: per cold credential fetch for a subscription holder or a cross-owner lease
  alert_target: Sentry web-platform project issue stream (existing agent_auth_failure / byok-lease routing; no new rule)
  configured_in: apps/web-platform/server/byok-lease.ts failAuthModeClosed and noteCredentialSelected
error_reporting:
  destination: Sentry web-platform via the existing reportSilentFallback in server/observability.ts (lease-owned, one event per refusal); the five call-site mirrors are skipped for these causes so there is no second event
  fail_loud: the client receives a typed error frame (auth_mode_unresolved or auth_mode_unavailable) with server-authored copy; pino logs the refusal at info with conversationId
failure_modes:
  - mode: mode cannot be resolved (unbound, invalid_value, no_resolver, read_failed, resolver_failed)
    detection: Sentry op auth-mode-unresolved with the closed reason tag
    alert_route: Sentry issue stream (bounded by the subscription-holder plus cross-owner population)
  - mode resolver throws, is absent or mismatches the workspace inside the quiet cross-owner pre-check
    detection: not an error-tracker event by design (CLO condition 1: no new failure mode); an info log with a closed outcome (non_api_key, unresolved, workspace_mismatch) is emitted and OauthDelegationForbiddenError reaches the runner mirror as before
    alert_route: existing generic runner mirror for OauthDelegationForbiddenError
  - regression serving the wrong credential to a cross-owner run
    detection: the Guard 1 mutation-checked tests in CI; breadcrumb scheme/delegated pair provable from telemetry
    alert_route: CI failure blocks merge
logs:
  where: pino to Better Stack (existing byok-lease, agent-runner, cc-dispatcher child loggers)
  retention: Better Stack default retention for the web-platform source
discoverability_test:
  command: grep -o 'op: "auth-mode-unresolved"' apps/web-platform/server/byok-lease.ts
  expected_output: auth-mode-unresolved
```

## Test Scenarios

1. Delegated, grantor holds both rows, mode `api-key` -> api key; `anthropic_oauth` never queried (AC1).
2. Delegated, grantor holds both rows, mode `managed` / junk / throws / absent -> `OauthDelegationForbiddenError` (AC2).
3. Real binding flip across two delegated leases (AC3), decoy run by another member refuses.
4. Delegated, no oauth row, throwing resolver -> api key, no events (H2).
5. Scope ends during the resolver await -> `escape`, no further read (Guard 1 row 6).
6. Each of six reasons -> correct cause, one event, correct code (AC5); `workspace_mismatch` binding in another workspace -> refusal, no decrypt (AC15).
7. Four emit paths x two causes -> one typed frame, zero call-site events, `session_id` kept (AC6); real `fetch_failed` still `key_invalid` + mirrored.
8. Client: deterministic action present, no Reconnect on either card, no teardown, last user message marked unanswered, next send clears the card, composer enabled (AC7).
9. Recovery sentence in exactly the five cells (AC8).
10. Non-owner Settings text; owner render unchanged (AC9).
11. auto-sync retry matrix (AC10).

## Dependencies & Risks

- **Risk: the extra binding read for every cross-owner lease** (CLO condition 1 forces mode-first). Bounded: cross-owner leases are rare and the caller-scoped tenant client is warm (`getFreshTenantClient` caches the in-flight mint per user; CTO). Verified in Phase 0 (`lib/supabase/tenant.ts`); the ADR addendum states the claim only if verified.
- **Risk: `isOwner` defaults to `true` when identity is unknown** (`settings-content.tsx`). A non-owner with a failed identity load briefly sees owner text. Pre-existing default; unchanged.
- **Risk: draft PR #9051 (Codex) conflicts in `agent-engine-settings.tsx`.** Minimal hunks (Phase 5 check).
- **Risk: a grantor who is not the workspace owner.** Accepted by the CLO/CTO; recorded in the ADR addendum; legal-document wording check in Phase 7.
- **Risk: a transient resolver failure on a legitimate delegated `api-key` conversation is a quiet refusal** (`OauthDelegationForbiddenError`, generic text, closed `outcome` info log) because CLO condition 1 forbids a loud new failure mode for cross-owner leases. Accepted and documented; the owner-path `auth_mode_*` frames never reach delegates. Copy for those delegate dead ends is the Phase 7 follow-up issue.
- **Risk: repeated deterministic refusals emit one lease event per send.** Accepted (CTO R3 iv); add a per-conversation debounce if volume shows.
- **Dependencies:** none external. CLO/CTO/CPO rulings are final in the decision file; the CLO must be re-consulted if the implementation deviates from conditions 1-3.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan sets `single-user incident`.
- `agent-auth-user-message.ts` and `agent-auth-match.ts` must not import Sentry/observability or name `engine-binding-auth-mode` / `resolveAuthMode`; comments are stripped by the pins, but do not rely on that for code tokens.
- Do NOT key `isLeaseRefusalReported` on `fetch_failed`: a genuine DB read failure is not reported by the lease.
- `isCredentialErrorCode` is "the pair" by design: do not add the new codes to it (it would disable the composer and force a teardown).
- Widening `WSErrorCode` without the zod enum is a `tsc` error (`_SchemaCovers`), but widening only the enum is silent: change both in one commit and grep the three patterns (`cq-union-widening-grep-three-patterns`): `git grep -n "delegation_cross_tenant" -- apps/web-platform` lists every consumer of the union.
- No `git stash`; the worktree was found deleted once during planning and was re-created with `git worktree add` on the existing branch.
- The R2 tripwire is not independently mutation-testable (it fires only if the owner gate is also edited); do not write a test that deletes the gate to reach it and call that a tripwire test.
- `makeTableAwareTenant` exposes `eqs` only: real-binding assertions on 'the oauth row was never selected' use `eqs`, while 'one buffer decrypted' lives in the credential-type harness (`providersQueried`, `sinks.decrypted`); that harness mocks one tenant for every user and cannot prove the resolver ran on the caller's client.
- The ADR must end with exactly one newline; line-start `#NNNN` becomes a phantom heading under markdownlint `--fix`.
