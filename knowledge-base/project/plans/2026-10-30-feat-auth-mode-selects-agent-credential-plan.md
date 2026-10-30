---
title: "feat: the Authentication mode setting selects which credential the Concierge uses"
date: 2026-10-30
slug: auth-mode-selects-agent-credential
branch: feat-one-shot-auth-mode-selects-credential
issue: 11591
closes: none
pr: 11590
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: the Authentication mode setting selects which credential the Concierge uses

Tracker: #11591 (milestone "Phase 4: Validate + Scale", labels `type/feature`, `domain/engineering`). Linked, never closed, from #11086 and #11541 with `Ref`. Draft PR: #11590. Decisions: `knowledge-base/project/specs/feat-one-shot-auth-mode-selects-credential/decision-challenges.md`.

`lane:` is `cross-domain` because no `spec.md` exists for this branch (fail-closed default, the one-shot path skips brainstorm).

## Enhancement Summary

**Deepened on:** 2026-10-30
**Sections enhanced:** Phases 1-2, Acceptance Criteria (AC3, AC5-AC7, AC16, AC17), Guard Contract rows, Test Scenarios, Observability, Risks, Domain Review.
**Research agents used:** security-sentinel, spec-flow-analyzer, test-design-reviewer, observability-coverage-reviewer, a verify-the-negative grep sweep (Explore), plus the earlier plan-review panel (DHH, Kieran, code-simplicity, CTO, CPO, UX lead) and the CPO / CTO / CLO rulings.

### Key Improvements
1. Mode reads are scoped to the caller (`created_by` / `user_id` filters) so a co-member's conversation id cannot lend another member's mode (security P2-1).
2. The post-resolver liveness check is restored; without it a scope that ended during the read still queried and decrypted a row, and the escape scenario could not be asserted (test-design P1, security).
3. The wiring and forwarding guards are now falsifiable: two-file `grep -c` pins for the Agent-SDK call sites, identity (`toBe`) assertions per branch, a single-chokepoint count, a table-aware mock with decoy runs, and cache tests with an oauth row present.
4. Success is observable: one closed-enum `agent-credential-selected` breadcrumb; failure modes cite telemetry layers; passive alerting stated honestly (no rule keys on `byok-lease`).

### New Considerations Discovered
- Legacy (pre-binding) conversations behave as Automatic, so P1 holds only for bound conversations; documented as an explicit exception (AC16, ADR-048 amendment).
- A non-owner member's lease is still refused by the owner gate before any mode read when the key owner holds a subscription row; the bypass is #11594.
- The operator-only `oauth_unusable` recovery sentence remains an open operator scope row; spec-flow rates the missing hint High because the failing conversation cannot self-recover (it must be restarted).
- Verified (grep sweep): exactly five non-test `resolveKeyOwnerThenLease` callers, two `getAgentCredential` callers, five `runWithByokLease` branches, and three `conversations` inserts (ws-handler, support, auto-sync); `agent-on-spawn-requested.ts` calls `runWithByokLease` directly but only `getRestApiKey`.

### Deepen-plan gate dispositions
- 4.6 User-Brand Impact: present, threshold `aggregate pattern`: pass. 4.7 Observability: all five fields present, command verb allowlisted, literal `expected_output`; the probe string appears only after implementation, which is fine because Check 10 runs at ship time: pass. 4.8 PAT: no hits. 4.10 Encryption: no store, connection, `.tf`, migration or compose file: skip. 4.11 Guard Contract: `lint-guard-contract.py` green; assembly is structural (type, single helper, runtime floor): pass. 4.12 Scope Check: one unfenced section, no `unmapped` row, justifications present: pass. 4.13, 4.5, 4.55: no new autonomous task, network symptom or downtime operation: skip.
- 4.9 UI-wireframe: the glob superset matches `components/settings/agent-engine-settings.tsx` and no `.pen` is referenced. Disposition: NOT halted. `wg-ui-feature-requires-pen-wireframe` defines UI surface as excluding copy/style, `ui-surface-terms.md` lists "Pure copy or style tweaks with no structural/layout change" as excluded, the CPO and UX lead both confirmed no new surface, and this run may only write under `knowledge-base/project/{plans,specs}/`, where a `.pen` (which belongs under `knowledge-base/product/design/`) cannot be committed. If a reviewer reads the glob as binding, the remedy is `pencil-setup --auto` plus a one-card wireframe at work time. Recorded in decision-challenges.md.

## Overview

The "Authentication mode" dropdown (`managed` / `api-key`) in Settings > Agent engine is persisted and shown but never consulted when the Claude agent picks its secret. The pick happens in exactly one place, `fetchAgentCredentialIntoSlot` in `apps/web-platform/server/byok-lease.ts`: with the `CC_OAUTH_ENABLED` kill-switch on and an `anthropic_oauth` row saved, the subscription token wins and the `anthropic` api_key row is never read. An owner whose saved subscription token is unusable (the #11086 incident) therefore cannot say "use my API key" without deleting the token.

This plan makes the lease honour the conversation's engine-binding auth mode, fail-closed, with the date, owner-only and kill-switch gates unchanged, and corrects the dropdown copy so it tells the truth. Semantics, all ruled (see decision-challenges.md):

| Mode | Lease behaviour |
|---|---|
| `api-key` | Skip the subscription row entirely (never decrypted, no shape check) and lease the saved API key. No API key saved: `MissingByokKeyError`. Never falls back to the subscription token. |
| `managed` | Today's behaviour: subscription token if saved and the kill-switch is on, else the saved API key. For any user without a subscription row (everyone except the operator) this already means "your saved API key". |
| Mode unreadable, junk, or no resolver wired | `ByokLeaseError("fetch_failed")`, one Sentry event, nothing decrypted or cached. Only reachable for an owner who holds a subscription row with the kill-switch on. |

Source of truth is the conversation's immutable engine binding (`agent_engine_runs.auth_mode`), snapshotted from the workspace default at conversation creation. A dropdown change therefore applies to **new** conversations (the card copy already says so); the plan adds the helper line that makes it explicit.

## Research Reconciliation — Spec vs. Codebase

| Brief / assumption | Reality (verified on this branch) | Plan response |
|---|---|---|
| "`makeAuthModeResolver` is a reuse candidate" | Its own header says the diagnostic it serves is temporary and its removal checklist deletes the file. | Extract the binding read into `server/engine-binding-auth-mode.ts`; `agent-auth-mode.ts` delegates to it (Phase 1). |
| "per-workspace default vs per-conversation binding" | The binding is a one-time snapshot of the default (`bind_agent_engine_run`, migration 138); ADR-233 calls it immutable and authoritative; `agent-engine-dispatch.ts` already fails closed on egress-vs-binding mismatch. | Binding is the source (CTO ruling 1). |
| "the lease knows the key owner and workspace context" | The lease knows two user ids and a delegation id, no conversation id and no workspace id. | Caller injects a lazy resolver; callers have `conversationId` in scope; the resolver argument is required by type on `resolveKeyOwnerThenLease` (Phase 2). |
| "a mode read can fail open?" | A conversation with no engine-run row is not always legacy: the auto-sync system conversation (`server/auto-sync-trigger.ts`) and the support conversation (`server/support-conversation.ts`, reached from `app/api/support/route.ts` via `dispatchSoleurGo`) are inserted without `bind` and have `engine_binding_state='pending'`, yet both reach `getAgentCredential`. | Legacy-with-no-run resolves to `managed`; any other no-run state fails closed; both creation paths now bind with plain `bind` calls before dispatch (Phase 3). |
| CPO: "put the mode check before the oauth read" | The lease must read the subscription row's ciphertext to know whether a subscription exists at all; the CPO's concern (never decrypt a token the user declined) is met by deciding before decrypt. | CTO order: kill-switch, read row, date gate, owner gate, mode, then decrypt/shape (Phase 2). |
| CPO helper line names a Claude subscription | CLO: no customer-facing copy may name a subscription (owner-only/no-share basis, `agent-auth-user-message.ts` copy rule "no tenant is ever shown subscription-token wording"). | CLO wins; helper line is credential-neutral (Phase 4). |
| "NOTHING reads authMode" | True for the credential choice. The auth-failure diagnostic reads the binding via `makeAuthModeResolver` at `agent-runner.ts` (~L2196) and `cc-dispatcher.ts` (~L3166). | Lease and diagnostic read the same binding value, so their labels agree by construction; the unbound divergence is documented (AC10). |
| Card copy says "new conversations and routine runs" | Routine runs lease through `getRestApiKey` (Inngest `agent-on-spawn-requested`), not `getAgentCredential`; the mode has no routine effect for the Claude engine. | Out of scope; helper line scopes the claim to conversations. |
| CTO risk: cost cap | `soleur-go-runner.ts` skips the per-conversation cost cap when `authScheme === "oauth_token"`. Forcing `api-key` for the operator flips those sessions to `api_key`, so the cap now applies. | Correct behaviour, noted in Risks; `setAuthScheme` derives from `credential.scheme` and needs no change. |

## Research Insights

### Premise Validation (Phase 0.6)

- #11086 and #11541 are OPEN (`gh issue view`); no open PR names either (`collision-precheck.sh` exit 10 reported only foreign `test-all.sh` runs in `feat-one-shot-ci-head-verdict-required-set`, no PR collision). Draft PR #11590 is this branch.
- Searched issues for "Authentication mode": no tracker; filed #11591.
- Cited paths all exist on `origin/main`: `byok-lease.ts`, `agent-engine-settings.tsx`, `agent-engine/route.ts`, `agent-engine-persistence.ts`, `agent-auth-mode.ts`, `key-rotation-form.tsx`. "UI exists but is broken" = the dropdown works as a setting but is wired to nothing; this is a build-the-wiring plan, not a patch.
- ADR corpus grep for the mechanism: ADR-048 (selection by consumer class, gates centralized on the oauth read) and ADR-233 (immutable binding). Neither rejects mode-driven selection; ADR-048's "no silent api_key fallback" rule is preserved because `api-key` is an explicit choice, not a fallback. No rejected-alternatives hit.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) an owner who chose `api-key` is never served the subscription token for a new conversation; (P2) an owner who chose `managed` keeps today's behaviour exactly; (P3) the mode can only narrow what the lease hands out, never widen it: the date, owner and kill-switch gates fire before the mode is read; (P4) an unreadable or invalid mode fails closed; (P5) the friendly sign-in error and `credentialScheme` frame reflect the credential actually leased; (P6) the diagnostic's `auth_mode` label and the lease read the same fact.

Cut list: a new column or table for the mode (the binding already stores it); a new feature flag (`CC_OAUTH_ENABLED` already gates); a per-request mode in the WS payload (the binding is the authority, and the payload is user-controlled); a new `ByokLeaseError` cause (would touch the exhaustive `never` rail, the WS code and the UI for no benefit); passing a mode from the three REST-only callers (they pass `{ restOnly: true }`); an `ensureConversationBound` repository method with a race re-read (a plain `bind` on a just-inserted row has no concurrent binder); changes to `getRestApiKey` (structurally api_key only already).

### Key code facts

- `getAgentCredential` callers: `server/agent-runner.ts` (`startAgentSession`, ~L1138-1146) and `server/cc-dispatcher.ts` (`realSdkQueryFactory`, ~L1895-1921). The routing-side lease at `agent-runner.ts` ~L3302 uses `getRestApiKey` only. Both Agent-SDK callers go through `resolveKeyOwnerThenLease` in `server/byok-resolver.ts`, which has five `runWithByokLease` branches.
- Credential scheme flows to the UI from the leased value: `credentialScheme: credential.scheme` at `agent-runner.ts` ~L2194 and `cc-dispatcher.ts` ~L3164; `setAuthScheme(credential.scheme)` at `cc-dispatcher.ts` ~L1929. Nothing there reads the mode.
- `agent-engine-route-guard.ts` `assertLegacyConversationEngineBinding` already defines "legacy" (no run row + `engine_binding_state='legacy'`); `getConversationBindingState` exists on the repository.
- `bind_agent_engine_run` (live definition: the `CREATE OR REPLACE` in migration 141, which also flips `engine_binding_state` to `bound`) is granted to `service_role` and `authenticated`; for service callers it requires `created_by` workspace membership and a conversation in that workspace.
- Existing lease tests: `apps/web-platform/test/byok-lease-credential-type.test.ts` (provider-aware Supabase mock recording `providersQueried`, `sinks.decrypted` for zeroize assertions, `UNUSABLE` shape fixtures).

### Institutional learnings applied

- `2026-06-02-two-row-by-provider-credential-and-lease-accessor-rename-sweep.md`: gates only in the accessor that reads the gated row; never inject both auth vars. This plan adds no second injection site.
- `2026-10-29-the-cli-dropped-my-credential-...` (#11086): the shape check is a negative predicate that fails closed with `oauth_unusable`; keep it byte-identical on the `managed` path and pin each half with the other half's real output.
- `security-issues/2026-10-06-i-claimed-a-mechanism-from-an-outcome-...`: pin the wire at what call sites hand over, claim outcomes not mechanisms. The wiring sentinel pins the call sites, not the builder.
- `2026-03-20-middleware-error-handling-fail-open-vs-closed.md`: always destructure `{ data, error }`; pick the direction on purpose (fail closed here).
- `best-practices/2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`: the fail-closed event is bounded by the subscription-holder population (one operator), so raw `reportSilentFallback` is the right tool; no debounce needed.
- `test-failures/2026-06-15-source-grep-test-breaks-on-symbol-extraction-only-full-suite-catches.md` and `...2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q...`: source-text tests are invisible to import-edge selection; use `grep -c ... >/dev/null`, never `grep -v | grep -q`, in any new pin.
- `2026-10-15-my-diagnostic-helper-copied-hint-...`: no `hint`/`details` on regulated surfaces (`workspace_engine_settings`, `agent_engine_runs`); the new resolver surfaces closed reasons only.

## Open Code-Review Overlap

Queried open `code-review` issues against every planned file path.

- #3242 (tool_use WS event lacks raw name field) touches `server/agent-runner.ts`, `server/cc-dispatcher.ts`: **Acknowledge**, unrelated concern (WS event shape); remains open.
- #3243 (decompose cc-dispatcher.ts) touches `server/cc-dispatcher.ts`: **Acknowledge**, this plan adds one argument at one call site and does not grow the monolith; remains open.
- All other planned paths: none.

## User-Brand Impact

- **If this lands broken, the user experiences:** an owner who selected "My API key" in Settings > Agent engine is still served by the saved Claude subscription token (the dropdown looks honoured but is not), or an owner on "Automatic" is refused with "Authentication unavailable; retry shortly" in the Concierge because the mode read failed.
- **If this leaks, the user's workflow / data is exposed via:** the prompts and files of a conversation flowing under a provider account the owner explicitly declined (consent recorded against one mode, executed under the other). The subscription token itself is not newly exposed: in `api-key` mode it is never decrypted, and no new log or Sentry field carries a secret, a stored value or the mode string.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** Ruled by CPO agent, 2026-10-30: both secrets belong to the same owner, only the operator can hold a subscription row, and the owner-only/delegation gates are untouched, so a failure harms one account holder's own consent boundary, not another principal; it escalates to `single-user incident` only if any path could use another principal's credential, which AC4 pins with a delegation test.

## Architecture Decision (ADR/C4)

Detection fires: this changes a resolver/trust-boundary rule (credential selection by consumer class now also depends on the binding's auth mode) and amends ADR-048's "prefers oauth" decision.

### ADR

- **Amend ADR-048** (`knowledge-base/engineering/architecture/decisions/ADR-048-operator-cc-oauth-credential-selection-by-consumer-class.md`) via `soleur:architecture`: dated amendment "Credential selection by the binding's auth mode". Decision text: for the Agent-SDK consumer class, selection is `anthropic_oauth` only when the kill-switch is on AND a row exists AND the date gate and owner gate pass AND the conversation binding's auth mode is exactly `managed`; `api-key` selects the `anthropic` row and never decrypts the subscription row; unreadable/invalid mode and a missing resolver fail closed with `fetch_failed`; `api-key` with no api_key row is `MissingByokKeyError`, never a subscription fallback. Add the alternatives considered (live workspace default; pre-resolving on every lease; lease reads the workspace itself; new error cause) with the rejection reason. State the two documented lease-vs-diagnostic divergences (no run + `legacy`: probe `unbound`, lease `managed`; no run + `pending`: probe `unbound`, lease fails closed) and the one P1 exception (pre-binding conversations behave as Automatic). Update the front matter `related` list with 11591.
- **Cross-reference ADR-233** with one line under its binding paragraph: the binding's `authMode` now also drives Agent-SDK credential selection (so "immutable binding" is load-bearing for credential selection, not only egress).
- No new ADR, so no ordinal to claim; run `bash scripts/check-adr-ordinals.sh` against freshly fetched `origin/main` anyway as the work-phase gate.

### C4 views

I READ `knowledge-base/engineering/architecture/diagrams/model.c4` (and the engine container's `registry`, `binding`, `adapter`, `factory`, `composition` components), and the existing edges that carry this flow: `engine -> anthropic "LLM calls with BYOK keys ..."`, `engine -> supabase "Sessions and encrypted keys"`, `platform.webapp.api -> platform.engine.claude.binding "Binds runs before dispatch and persists events"`. Checked against the four enumerations:

- External human actors: the owner/operator who changes the setting and the subscription holder: already modelled; no new human role.
- External systems / vendors: Anthropic (already `engine -> anthropic`); no new vendor, webhook or API.
- Containers / data stores: Supabase `api_keys` and `agent_engine_runs` (already `engine -> supabase`); no new store.
- Actor-to-surface access relationships: the lease reading the binding is the existing engine-to-Supabase edge; no new relationship.

Conclusion: no element or edge is added. One description edit is required because the current text is falsified by the change: the `binding` component ("Binds each conversation or routine run to one engine and records lifecycle events") now also supplies the auth mode that selects the Agent-SDK credential at lease time. Edit that line in `model.c4` directly in this PR; run `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh` (a description edit moves no count, but the parity run is the evidence, not the reasoning).

### Sequencing

The ADR amendment describes the target state and lands in this PR; nothing is gated on a later slice.

## Implementation Phases

TDD order inside every phase (`cq-write-failing-tests-before`): write the failing test first, then the code. Revised after plan review (2026-10-30): the agent-path resolver is **required by type** (the compiler, not a source scan, catches a forgotten caller), the five-branch forwarding is built once, and the binding of unbound conversations uses plain `bind` calls.

### Phase 1 — Shared binding auth-mode resolver

- Create `apps/web-platform/server/auth-mode-error.ts`: a dependency-free leaf (no imports) exporting `AUTH_MODE_ERROR_REASONS = ["unbound", "read_failed"] as const` and `class ConversationAuthModeError extends Error { reason }`. The lease imports it with `instanceof` (the lease already imports the tenant client, so the earlier "must not import the Supabase graph" rationale was false; the leaf keeps the error class free of that graph anyway).
- Create `apps/web-platform/server/engine-binding-auth-mode.ts`, exporting only two functions:
  - `readConversationBindingAuthMode(userId, conversationId): Promise<string | null>`: today's `makeAuthModeResolver` body (`getFreshTenantClient` + `AgentEnginePersistenceRepository.getConversationRun`), `null` when there is no run. The temporary diagnostic keeps using it. Both functions scope the read to the caller: `getConversationRun(conversationId, createdBy?)` gains an optional second argument that adds `.eq("created_by", userId)`, and the binding-state read adds `.eq("user_id", userId)`, so a co-member's conversation id (the select policies are workspace-member-wide) looks unbound to the caller and fails closed instead of lending the caller another member's mode (security review P2-1). Auto-sync, support and `ws-handler` all bind with `createdBy = userId`, so owner-created runs match.
  - `makeConversationAuthModeResolver(userId, conversationId): () => Promise<string>`: builds one repository from the tenant client and returns the lease-facing resolver. Run found: its `authMode`. No run: `getConversationBindingState`; `"legacy"` returns `"managed"`; anything else (including null) throws `ConversationAuthModeError("unbound")`. Any read error is rethrown as `ConversationAuthModeError("read_failed")` carrying no row, message text or id.
  - No Sentry or logger import in either module (the lease owns the single event).
- Edit `apps/web-platform/server/agent-auth-mode.ts`: `makeAuthModeResolver` delegates to `readConversationBindingAuthMode` (keeps its `string | null` contract: `null` is the probe's `unbound`). Update the REMOVAL CHECKLIST: step 1 also says KEEP `server/engine-binding-auth-mode.ts` and `server/auth-mode-error.ts` (the lease reads them), and step 6 lists the AC10 divergence test for deletion with the diagnostic tests.

### Phase 2 — Lease honours the mode

- Edit `apps/web-platform/server/byok-lease.ts`:
  - `ByokLeaseArgs.resolveAuthMode?: () => Promise<string>` and the same optional field on `LeaseSlot`. It stays optional at the lease level on purpose: `runWithByokLease` is also called directly by REST-only paths, and a missing resolver with an oauth row present is a runtime fail-closed (`no_resolver`) rather than a type error there. Add one JSDoc paragraph on `getAgentCredential`: a caller with no conversation binding (for example an Inngest routine using the Agent SDK) always fails closed for an owner who holds a subscription row.
  - New private `resolveLeaseAuthMode(slot): Promise<"managed" | "api-key">`: no resolver: reason `no_resolver`; resolver throws: reason is the error's `reason` when it is a `ConversationAuthModeError` (`instanceof`) else `resolver_failed`; value not exactly `"managed"` or `"api-key"`: `invalid_value`. Each case reports once via `reportSilentFallback(null, { feature: "byok-lease", op: "auth-mode-unresolved", message, tags: { reason }, extra: { reason } })` (null error and no raw value, mirroring `oauth-credential-unusable`) and throws `ByokLeaseError("fetch_failed", "Authentication unavailable; retry shortly")`. Call `assertLeaseAlive(slot)` synchronously right after the resolver `await` (restored after review: without it a scope that ended during the read still queries and decrypts a row before `assertAliveAfterDecrypt` throws `escape`, so "nothing read after scope end" would be false and untestable).
  - Reorder `fetchAgentCredentialIntoSlot`: kill-switch, read oauth row, (row exists) date gate, owner/delegation gate, **mode**, then for `managed` the unchanged decrypt, liveness re-check, shape check, cache and return; for `api-key` fall through to the unchanged api_key branch. Decrypt and `classifyCliDroppedValue` move under the `managed` arm only, which lets `api-key` recover from an unusable stored token. `MissingByokKeyError` for a missing api_key row in both modes.
  - On a successful agent lease add one closed-enum breadcrumb (`Sentry.addBreadcrumb({ category: "byok", level: "info", message: "agent-credential-selected", data: { scheme } })`; `scheme` is `api_key | oauth_token`, already a non-secret field on the WS frame) so telemetry can prove which credential was chosen. No mode string, id or value in the payload.
- Edit `apps/web-platform/server/byok-resolver.ts`: `resolveKeyOwnerThenLease(callerUserId, workspaceContextUserId, fn, opts: LeaseModeOpts)` where `LeaseModeOpts = { resolveAuthMode: () => Promise<string> } | { restOnly: true }`. The argument is **required**, so `tsc` fails any future caller that omits it. Build the lease args once (`const run = (keyOwnerUserId, delegationId?) => runWithByokLease({ workspaceContextUserId, keyOwnerUserId, delegationId, resolveAuthMode: "resolveAuthMode" in opts ? opts.resolveAuthMode : undefined }, fn)`) and call `run` from all five branches. Update the header comment's call-site list and add the third-caller note.
- Callers: `server/agent-runner.ts` `startAgentSession` (~L1138) passes `{ resolveAuthMode: makeConversationAuthModeResolver(userId, conversationId) }`; `server/cc-dispatcher.ts` `realSdkQueryFactory` (~L1895) passes `{ resolveAuthMode: makeConversationAuthModeResolver(args.userId, args.conversationId) }`; the REST-only callers pass `{ restOnly: true }`: the routing-side lease at `agent-runner.ts` ~L3302, `server/inngest/functions/cfo-on-payment-failed.ts` and `server/inngest/functions/github-on-event.ts` (each only calls `getRestApiKey`; verify with `git grep -n "getAgentCredential" apps/web-platform/server/inngest`).
- Do NOT touch `server/agent-env.ts` (the sandbox fence forbids the bare lowercase word `credential` there, including import paths), `server/agent-auth-user-message.ts` or `server/agent-auth-match.ts` (import-boundary pinned), or any added line pairing `log.<level>` with a bare `userId` (pr-quality-guards).

### Phase 3 — Bind the two unbound agent-running conversation paths

The live `bind_agent_engine_run` is the `CREATE OR REPLACE` in migration 141 (ownership check plus `UPDATE conversations SET engine_binding_state = 'bound'`), granted to `authenticated` and `service_role`. After a successful bind the state is `bound`, so `pending` means "no run yet".

- Edit `apps/web-platform/server/auto-sync-trigger.ts`: after the conversation insert and before `startAgentSession`, `await new AgentEnginePersistenceRepository(serviceClient as unknown as PersistenceClient).bind({ workspaceId: conversationWorkspaceId, executionKind: "conversation", conversationId, createdBy: userId })`. The conversation was just inserted, so there is no concurrent binder and no re-read is needed. A bind failure is non-fatal: `reportSilentFallback` (`feature: "repo-setup"`, `op: "auto-sync-bind"`, no user id in `extra`) and continue, because the lease already fails closed for a subscription holder and every other user is unaffected. Accepted cost, stated explicitly: `isLeaseRetryable` matches the "retry shortly" message, so a permanent `unbound` for the operator would retry four times with backoff (about 13 s, each a JWT mint) before surfacing; bounded, one user.
- Edit `apps/web-platform/server/support-conversation.ts` (tenant client, not the service client): bind the newly inserted row the same way. For the sticky existing row, extend the existing `.select("id")` to `id, engine_binding_state` and bind only when the state is `pending`; never when `legacy` (old rows must keep their pre-binding meaning) and never an extra read per message. Same non-fatal mirror (`feature: "support"`, `op: "bind"`). Caveat to record: a sticky `pending` conversation binds at its first post-deploy message and snapshots the then-current default, not the default at creation.
- Tests: locate the auto-sync test with `git grep -l "auto-sync-trigger" apps/web-platform/test`; `test/support-conversation.test.ts` exists but its Supabase mock has **no `rpc`**, so add `rpc` to the mock first, otherwise the bind throws a TypeError the non-fatal catch swallows and the AC11 tests pass vacuously.

### Phase 4 — Dropdown copy that tells the truth

Edit `apps/web-platform/components/settings/agent-engine-settings.tsx` (stored values `managed` / `api-key` unchanged; PUT body, rollback and every `toHaveValue` assertion stay valid):

- One small `authModeLabel(engineId, mode)` helper used by BOTH the select options and the radio sub-label (`engine.authModes.join(" or ")`, currently "local · managed or api-key", which would otherwise contradict the select). Claude engine only: `managed` shows "Automatic", `api-key` shows "My API key"; other engines keep the raw strings (Codex is "Coming soon" and disabled).
- A static helper paragraph, neutral `text-xs text-soleur-text-secondary`, Claude engine only: "Applies to new conversations. Automatic uses the credential saved to your account; My API key uses your saved API key." (two sentences; no word "subscription", per the CLO ruling). Give it an id.
- Move the helper and the amber `user-provider-disclosure` note **outside** the wrapping `<label>` (they currently would pollute the select's accessible name) and set `aria-describedby="<helper-id> <disclosure-id>"` on the select.
- The amber note renders in **both** modes (true in both; a normal customer on Automatic already runs on their own key with no notice today). Text verbatim, so the sibling string in `connected-services-content.tsx` does not drift and no legal re-read is triggered.
- Update `apps/web-platform/test/agent-engine-settings.test.tsx`: option labels, radio sub-label, helper present for Claude and absent for Codex, disclosure visible under both modes, `aria-describedby` wiring, stored values in the PUT body unchanged. The card intro ("new conversations and routine runs") is left as is: it is engine-generic and routine runs are real for other engines.

### Phase 5 — Architecture records

ADR-048 amendment (with one sentence cross-referencing ADR-233's binding paragraph and the two documented lease-vs-diagnostic divergences), `model.c4` binding description (see the Architecture Decision section). Run `bash scripts/check-adr-ordinals.sh` and the C4 tests.

### Phase 6 — Test sweep and local gates

- Existing tests that lease with an oauth row and no resolver now fail closed by design: `git grep -l "anthropic_oauth\|CC_OAUTH_ENABLED" apps/web-platform/test`; add one shared fixture (`managedResolver = async () => "managed"`) in the lease test file and pass it where the intent is the subscription path. Do not weaken the no-resolver rule to make them pass.
- Tests asserting `resolveKeyOwnerThenLease` mock calls: `git grep -ln "resolveKeyOwnerThenLease" apps/web-platform/test` and update `toHaveBeenCalledWith` for the required fourth argument.
- Source-text tests are invisible to import-edge selection: run `git grep -l readFileSync apps/web-platform/test | xargs grep -l "byok-lease\|byok-resolver\|agent-runner\|cc-dispatcher\|agent-engine-settings\|auto-sync-trigger\|support-conversation\|agent-auth-mode\|engine-binding-auth-mode"` and every file it lists, including `agent-sandbox-credential-deny.test.ts`, `oauth-token-injection-site.test.ts` and `agent-auth-import-boundary.test.ts`.
- Check `bash scripts/test-all.sh --capacity` before waiting on the affected-test gate; run the targeted files directly first with `cd apps/web-platform && ./node_modules/.bin/vitest run <files>`.
- `cd apps/web-platform && npx tsc --noEmit` (this is the enforcement for the required `LeaseModeOpts`), the lint scripts CI runs for `server/` changes, and the pr-quality-guards userId check on the diff before pushing.

## Files to Create

- `apps/web-platform/server/auth-mode-error.ts`
- `apps/web-platform/server/engine-binding-auth-mode.ts`
- `apps/web-platform/test/engine-binding-auth-mode.test.ts`: resolver unit tests with a mocked repository (run present; no run + `legacy`; no run + `pending` throws `unbound`; no run + null state throws; state read error; run read error).
- `apps/web-platform/test/byok-lease-auth-mode-binding.test.ts`: the real binding resolver wired to a mocked tenant client serving `agent_engine_runs`, `conversations` and `api_keys`, driving the real `runWithByokLease` (Test Scenarios 10-11).

## Files to Edit

- `apps/web-platform/server/byok-lease.ts`
- `apps/web-platform/server/byok-resolver.ts`
- `apps/web-platform/server/agent-runner.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` and `apps/web-platform/server/inngest/functions/github-on-event.ts` (pass `{ restOnly: true }`)
- `apps/web-platform/server/agent-auth-mode.ts`
- `apps/web-platform/server/agent-engine-persistence.ts` (optional filters; `test/agent-engine-persistence.test.ts` covers them)
- `apps/web-platform/server/auto-sync-trigger.ts`
- `apps/web-platform/server/support-conversation.ts`
- `apps/web-platform/components/settings/agent-engine-settings.tsx`
- `apps/web-platform/test/byok-lease-credential-type.test.ts` (new `describe` for the matrix and the order/lazy/fail-closed cases; existing oauth cases use the shared `managedResolver`)
- `apps/web-platform/test/byok-resolver-delegation-workspace.test.ts` (five-branch forwarding, Guard 1)
- `apps/web-platform/test/agent-engine-settings.test.tsx`
- `apps/web-platform/test/support-conversation.test.ts` (mock gains `rpc`) and the auto-sync-trigger test found by grep
- `knowledge-base/engineering/architecture/decisions/ADR-048-operator-cc-oauth-credential-selection-by-consumer-class.md`
- `knowledge-base/engineering/architecture/decisions/ADR-233-pluggable-web-agent-engine-boundary.md` (one line)
- `knowledge-base/engineering/architecture/diagrams/model.c4`

`agent-engine-persistence.ts` gains only the optional `createdBy`/`userId` filters (no `ensureConversationBound`). Glob check: every path above was verified to exist (`git ls-files`) or is listed under Files to Create.

## Non-Goals (with tracking)

- **Delegated lease whose grantor holds a subscription row still throws `OauthDelegationForbiddenError` even under `api-key`.** Pre-existing, ruled out of scope because the brief fixes the owner-only gate. Tracked: #11594 (filed during planning), milestone "Phase 4: Validate + Scale", re-evaluate when the first delegated workspace includes a grantor with a subscription row.
- **Retry the failing conversation under the new mode (in-flight switch).** Not built (CPO ruling); revisit only if "start a new conversation" proves to be real friction for the owner after the re-save (#11541). No issue: a speculative affordance, not committed work.
- **A recovery sentence in the operator-only `oauth_unusable` copy cell.** Operator scope row, defaulted to excluded (decision-challenges.md).
- **Hiding the dropdown for users with no subscription row**, tightening the disclosure sentence, and relabelling `connected-services-content.tsx`: not needed for honesty once the labels change.
- **Changing `key-rotation-form.tsx`** ("Credential type" only chooses what is being saved) and **`getRestApiKey`** (structurally api_key only).
- **Closing or editing #11086 / #11541.** `Ref` only; #11086 stays open until the owner re-saves the token (#11541).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make the \"Authentication mode\" dropdown choose which credential the Claude Concierge uses" | Phases 1-2 | mapped |
| 2 | "file a new issue for this work (milestone \"Phase 4: Validate + Scale\", labels type/feature, domain/engineering)" | #11591 filed during planning | mapped |
| 3 | "link it from #11086 and #11541 (both open; use `Ref #N`, never `Closes`" | comments on #11086 and #11541; no `Closes` anywhere | mapped |
| 4 | "The lease honours the mode, fail-closed, with the owner-only and kill-switch gates unchanged" | Phase 2, AC1-AC6 | mapped |
| 5 | "a test that DRIVES the selection through the real lease (not a mocked mode)" | `byok-lease-auth-mode-binding.test.ts` + AC7 | mapped |
| 6 | "Include a negative control: mode=api-key with a valid subscription row present must read the api_key row, and mode=managed must not." | AC1, AC2, Test Scenarios 1-2 | mapped |
| 7 | "The auth-failure friendly error and credentialScheme frame still pick the right copy (the frame is built from the leased scheme, not the mode)." | AC9, Guard 1 row 5 | mapped |
| 8 | "The diagnostic's `auth_mode` label and the lease agree, or the mismatch is documented." | AC10 | mapped |
| 9 | "whether the dropdown copy needs updating (the amber `user-provider-disclosure` note ...)" | Phase 4 | mapped |
| 10 | "confirm or amend first; ... route to soleur:product:cpo with soleur:engineering:cto" | decision-challenges.md rows | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Shared resolver module + `agent-auth-mode.ts` delegation | "server/agent-auth-mode.ts `makeAuthModeResolver(userId, conversationId)` already reads a conversation's binding authMode and is a reuse candidate" | asked (reuse; the module move is the CTO-ruled way to reuse a file slated for deletion) |
| Binding the auto-sync and support conversations | — | inferred — justification: without it the fail-closed rule would break the operator's auto-sync/support runs, and DHH's alternative (map no-run to `managed`) reopens the hole where an owner who chose `api-key` is served the subscription on those runs; CTO-ruled prerequisite |
| Option relabelling and helper line | "whether the dropdown copy needs updating" | asked |
| ADR-048 amendment / ADR-233 one-line cross-reference / `model.c4` description edit | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; trust-boundary rule changes; the C4 line is falsified by the change (the ADR-233 line and C4 edit are taste-level, kept at one line each) |
| Required `LeaseModeOpts` + five-branch forwarding test | "a test that DRIVES the selection through the real lease" | asked (the type plus one behavioural test replace the earlier source-scan sentinel) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (server, components, tests), `knowledge-base/engineering`
- Planned files: 4 created + 19 edited (23) | Estimated changed lines: about 750 (about 280 production, 40 records, 430 tests after plan review cut the source-scan sentinel and the repository method)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The line threshold is crossed only by tests; splitting the lease change from the copy change would ship a dropdown whose labels promise behaviour the server lacks, or enforcement behind labels that still say "managed". One vertical, one revert unit.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 (negative control, api-key): `runWithByokLease` with `CC_OAUTH_ENABLED=1`, date passed, owner match, a valid-shaped `anthropic_oauth` row AND an `anthropic` row, and `resolveAuthMode: async () => "api-key"` returns `{ scheme: "api_key", value: <api key plaintext> }`; `sinks.decrypted` holds exactly one buffer (the api key) so the subscription value was never decrypted; deleting the mode branch makes this test red.
- [ ] AC2 (negative control, managed): same fixtures with `"managed"` return `scheme: "oauth_token"` and `providersQueried` does not contain `"anthropic"`.
- [ ] AC3: `api-key` + a malformed subscription value (each `UNUSABLE` fixture) returns the api key (`value === REST_PLAINTEXT`, asserted on the RETURNED value, never through the suite's `.catch((e) => e)` swallow), `sinks.decrypted.length === 1`, and zero `captureMessage` calls of any kind (not merely none with that op); `managed` + the same value still throws `oauth_unusable` byte-identically to today.
- [ ] AC4 (gates unchanged): a delegated lease, a keyOwner/workspace mismatch, and a pre-effective-date clock each still throw `OauthDelegationForbiddenError` / `OauthNotYetPermittedError` when an oauth row exists, and the `resolveAuthMode` spy is called zero times in those cases; kill-switch off with `api-key` leases the api key, calls the resolver zero times and never queries `anthropic_oauth`.
- [ ] AC5 (lazy and cached): no oauth row means the resolver is never called, for both `managed` and `api-key`; WITH an oauth row present, in both modes, two `getAgentCredential()` calls in one scope call the resolver exactly once; a fail-closed call caches nothing (the resolver is called again on the next call).
- [ ] AC6 (fail closed): resolver rejects; resolver returns `""`, `"api_key"`, `undefined` (representative junk values: `""`, `"api_key"`, `"MANAGED"`, `"managed "`, `null`, `undefined`, `{}`); a plain `Error` whose `name` or `reason` is spoofed to `"unbound"` tags `resolver_failed`, while a real `ConversationAuthModeError("unbound" | "read_failed")` reaches its own tag; no resolver passed with an oauth row present. Each throws `ByokLeaseError` with `cause === "fetch_failed"`, reads no `anthropic` row, decrypts nothing, caches nothing, and emits exactly one `reportSilentFallback` with `op: "auth-mode-unresolved"`, a `reason` from the closed set (`no_resolver | resolver_failed | invalid_value` from the lease, plus `unbound | read_failed` from `ConversationAuthModeError`, matched by `instanceof` so a spoofed reason cannot reach a tag) and no raw value, row, stored secret or user id in any captured sink (the `sinks.calls` dump contains none of the fixture strings). `mapByokLeaseCauseToErrorCode` is unchanged and still exhaustive.
- [ ] AC7 (real lease, real binding): `byok-lease-auth-mode-binding.test.ts` drives `runWithByokLease` with `makeConversationAuthModeResolver` over a mocked tenant client; the mocked tenant client is TABLE-AWARE (it routes on the table name and honours the `conversation_id`, `created_by` and `user_id` `eq`s, instead of the existing table-blind `from: () =>`), a decoy run for another conversation (and one created by another member) with the opposite mode is never served, and flipping the persisted binding between two leases flips the leased scheme (so the test cannot pass against a constant mode); no run + `legacy` leases per `managed`; no run + `pending` and any read error fail closed.
- [ ] AC8: `api-key` with no `anthropic` row throws `MissingByokKeyError` and never leases the subscription token.
- [ ] AC16 (member and legacy semantics, stated not implied): a non-owner workspace member's conversation resolves its mode from a binding created by that member (`created_by` filter), and a delegated lease still throws `OauthDelegationForbiddenError` before any mode read (the grantor-subscription case is #11594). Pre-feature (`legacy`, no run) conversations always behave as Automatic: P1 ("never served the subscription token") is scoped to conversations that have a binding, and that exception is one sentence in ADR-048's amendment.
- [ ] AC17 (success telemetry): a successful `managed`+subscription lease and a successful `api-key` lease each emit exactly one `agent-credential-selected` breadcrumb carrying only `{ scheme }`.
- [ ] AC9: `buildAuthFailureFrame`/`authFailureCopy` call sites still receive `credential.scheme` (Guard 1 row 5): an `api-key` lease surfaces the API-key copy and `credentialScheme: "api_key"` ("Invalid API Key" title), a `managed` + subscription lease surfaces the operator copy; neither reads the mode. `agent-auth-user-message.ts` and `agent-auth-match.ts` are unmodified (`git diff --stat` shows neither).
- [ ] AC10: a small test over one fake repository covers ONLY the two cases where the diagnostic (`makeAuthModeResolver`: `null` -> `unbound`) and the lease resolver differ, and names them: no run + `legacy` (probe `unbound`, lease `managed`) and no run + `pending` (probe `unbound`, lease fails closed); for a bound run both return the same string. The same two divergences are one sentence in ADR-048's amendment. The test is listed in `agent-auth-mode.ts`'s REMOVAL CHECKLIST so the diagnostic-removal PR deletes it.
- [ ] AC11: `bind` is called before dispatch by `auto-sync-trigger` (service client) and `support-conversation` (tenant client; new row, and a sticky row only when `engine_binding_state` is `pending`, never `legacy`, with no extra read per message); a thrown bind is Sentry-mirrored and does not abort the session. The support test mock gains `rpc` and the test asserts the `bind_agent_engine_run` call, so it cannot pass vacuously.
- [ ] AC12: UI tests per Phase 4 pass (including the radio sub-label and `aria-describedby`); `getByLabelText("Authentication mode")` still matches; PUT bodies still carry `managed` / `api-key`.
- [ ] AC13: `bash scripts/check-adr-ordinals.sh` passes; C4 syntax/render tests and `plugins/soleur/test/c4-count-parity.test.sh` pass; ADR-048 and ADR-233 edits present.
- [ ] AC14: `tsc --noEmit` fails when `resolveKeyOwnerThenLease` is called without `LeaseModeOpts` (verified once by temporarily removing the argument at one caller); the traps run clean locally before push: `agent-sandbox-credential-deny.test.ts`, `oauth-token-injection-site.test.ts`, `agent-auth-import-boundary.test.ts`, the `git grep -l readFileSync ...` set, `tsc --noEmit`, the lint-anthropic-content-position lint, and the pr-quality-guards userId check on the diff.
- [ ] AC15: PR body uses `Ref #11591`, `Ref #11086`, `Ref #11541` only (no `Closes`); the PR renders the `taste` and `operator (scope)` rows of decision-challenges.md.

### Post-merge

- [ ] Nothing is flipped in production (no `CC_OAUTH_ENABLED` or setting change). Production effect appears only when the owner re-saves the token (#11541) and picks a mode; that is the owner's own action and is tracked on #11541, not by this PR.

## Guard Contract

### Guard 1 — the lease's mode resolver cannot be silently dropped on the Agent-SDK path

**Property.** Every path that reaches `lease.getAgentCredential()` hands the lease a mode resolver, and every `runWithByokLease` branch inside `resolveKeyOwnerThenLease` forwards it; a path that does not fails closed at the lease instead of serving a subscription token.

**Assembly.** Three layers, none a hand-kept list of today's call sites. (a) The type: `resolveKeyOwnerThenLease` takes a required `LeaseModeOpts` (`{ resolveAuthMode } | { restOnly: true }`), so every caller, present or future, must choose; `tsc --noEmit` is the scan. (b) The single `run` helper inside `resolveKeyOwnerThenLease` is the one chokepoint all five lease branches go through; the behavioural test exercises the real function once per branch (workspace-lookup catch, flag off, resolver RPC error, no data, delegated) with `createServiceClient`, the flag reader and `resolveCurrentWorkspaceId` mocked per branch and `runWithByokLease` mocked to capture its first argument. (c) The runtime floor: the lease with an oauth row and no resolver throws `fetch_failed` (`no_resolver`), exercised through the real lease.

**Mutation matrix.**

| # | Mutation (edit that MUST drive the guard RED) | Targets |
|---|---|---|
| 1 | Change `run` so ONE branch (the last, delegated one) builds its lease args inline without `resolveAuthMode` while the other four stay compliant | second-member-after-compliant-first: a check that stops at the first branch passes |
| 2 | Change one Agent-SDK caller (`cc-dispatcher.ts` or `agent-runner.ts` `startAgentSession`) to pass `{ restOnly: true }` | the type admits it and the lease tests never go through the dispatcher, so the guard is a two-file wiring pin: `grep -c 'resolveAuthMode: makeConversationAuthModeResolver'` must be exactly 1 in each of `agent-runner.ts` and `cc-dispatcher.ts` (counted with `grep -c ... >/dev/null`-style, never `| grep -q`) |
| 3 | Make the five-branch test iterate zero branches (empty table), or forward `async () => "managed"` from one branch instead of `opts.resolveAuthMode` | anti-vacuity and identity: the test asserts it ran five branches and that each captured resolver `toBe(opts.resolveAuthMode)`; the chokepoint is pinned too: `grep -c 'runWithByokLease(' byok-resolver.ts` equals 1 (a sixth inline branch would sit outside the table) |
| 4 | REORDER inside the lease: move the mode read above the date/owner gates | order property: the delegated-lease and pre-date cases assert the resolver spy is never called; a delete-only row would not catch a move |
| 5 | Replace `credentialScheme: credential.scheme` (or `setAuthScheme?.(credential.scheme)` in `cc-dispatcher.ts`) with a mode-derived value at one site | the frame and cost-cap bridge must come from the leased scheme (AC9); a two-file source pin with `grep -c ... >/dev/null` counts the exact expressions |

Harness rows: (H1) mutate the SUITE, not the guard: the named case `five-branch table cannot be empty` injects a stub that drives zero branches and must go RED; deleting the "five branches" assertion must make that case red; (H2) a must-PASS input that is not the canonical: call `resolveKeyOwnerThenLease` with `{ restOnly: true }` and confirm the forwarded argument carries no resolver and the REST-only lease still leases (a guard that rejects everything would fail this).

**Anchor.** The behavioural lease matrix (AC1-AC6) and the real-binding test (AC7) are the independent anchor: weakening the type or the helper in one commit still turns the operator's Concierge into a visible fail-closed `fetch_failed` in those tests. No stored hash or count floor is used.

## Observability

```yaml
liveness_signal:
  what: "Error-driven only (no heartbeat): Sentry event feature:byok-lease op:auth-mode-unresolved on every fail-closed mode read, plus one closed-enum agent-credential-selected breadcrumb ({scheme}) on every successful agent lease so the chosen credential is provable from telemetry. The existing agent_auth_failure alert still covers CLI sign-in failures."
  cadence: "per credential lease (once per cold agent session for an owner who holds a subscription row; never for other users)"
  alert_target: "Sentry web-platform issue stream, byok-lease feature; passive, no page (same as op:oauth-credential-unusable, no alert rule keys on byok-lease)"
  configured_in: "apps/web-platform/server/byok-lease.ts (reportSilentFallback call in resolveLeaseAuthMode)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN, through reportSilentFallback in @/server/observability"
  fail_loud: "The Concierge shows the existing key_invalid frame with 'Authentication unavailable; retry shortly' (ByokLeaseError fetch_failed) and the session does not start; the Sentry event carries the closed reason tag."

failure_modes:
  - mode: "Binding read fails (RLS deny, tenant JWT mint failure, DB error)"
    detection: "Layer 2 (reportSilentFallback null-error message path to Sentry) op:auth-mode-unresolved reason:read_failed; release tag (layer 5) bounds the regression window; up to four events per failure when isLeaseRetryable retries (AC6's one event is per lease call)"
    alert_route: "Sentry issue stream, byok-lease (passive)"
  - mode: "Conversation has no engine-run row and is not legacy (a new unbound creation path)"
    detection: "Layer 2 op:auth-mode-unresolved reason:unbound; AC11 pins the two known creation paths"
    alert_route: "Sentry issue stream, byok-lease (passive)"
  - mode: "A new Agent-SDK caller forgets to pass a resolver"
    detection: "`tsc --noEmit` fails first (required LeaseModeOpts); at runtime Sentry op:auth-mode-unresolved reason:no_resolver"
    alert_route: "CI failure plus Sentry issue stream"
  - mode: "Stored binding value is not managed or api-key"
    detection: "Layer 2 op:auth-mode-unresolved reason:invalid_value"
    alert_route: "Sentry issue stream, byok-lease (passive)"
  - mode: "Auto-sync or support bind fails (non-fatal)"
    detection: "Layer 2 (reportSilentFallback in the route handler and headless sync, not an Inngest step, so no sentry-correlation layer is claimed) feature:repo-setup op:auto-sync-bind and feature:support op:bind"
    alert_route: "Sentry issue stream"

logs:
  where: "Sentry (structured, closed tags) as above; the lease writes no pino line for these paths"
  retention: "Sentry project retention for web-platform"

discoverability_test:
  command: grep -rhoE -m1 auth-mode-unresolved apps/web-platform/server
  expected_output: auth-mode-unresolved
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent (2026-10-30) ruled the mechanism: binding as source of truth, lazy injected resolver, gate order (kill-switch, row, date, owner, mode, decrypt), fail closed with `fetch_failed` and no new cause, `MissingByokKeyError` for `api-key` without a key, ADR-048 amendment plus an ADR-233 cross-reference, injected-resolver test seam plus a real-binding layer, and the unbound-conversation rule (legacy -> managed, other -> fail closed, bind the auto-sync and support conversations). Risks adopted: cost-cap now applies to the operator under `api-key`; the cold-Query mint cost is bounded by the subscription-holder population.

### Legal

**Status:** reviewed
**Assessment:** CLO agent (2026-10-30), reading the 2026-06-16 CC-OAuth re-review and the DPD/privacy documents: forcing `api-key` only narrows use and does not change the subscription-token basis; erroring instead of falling back is right; disclosure in both modes is advisable and true in both; do not name a subscription in customer-facing copy; no Art. 30, Privacy Policy, DPD or GDPR Policy change. No new operator legal-risk call. The standing watch on Anthropic's paused-policy article is unchanged.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none for a UI feature in the sense of `wg-ui-feature-requires-pen-wireframe`: that rule's UI surface "excludes copy/style", and `ui-surface-terms.md` lists "Pure copy or style tweaks with no structural/layout change" as excluded. The mechanical glob matches the edited component, so this is recorded rather than assumed: the change relabels two options, adds one static paragraph under an existing select and widens the visibility predicate of an existing note; no new page, modal, flow or interactive control. CPO agent confirmed no wireframe is needed.
**Pencil available:** N/A (no new UI surface; copy and visibility only)

#### Findings

CPO agent (2026-10-30): keep `managed` behaviour but fix the dishonest label ("Automatic" / "My API key" display text, stored values unchanged); apply to new conversations only with a helper line; `api-key` with no key saved errors through the existing banner and never falls back; show the disclosure in both modes; threshold `aggregate pattern`. Genuine operator taste calls (labels, hiding the dropdown later, an in-flight retry affordance) are recorded as `taste` rows with defaults applied. The CPO's helper wording that named a subscription is superseded by the CLO ruling.

## Test Scenarios

1. `api-key` + valid subscription row + api row: api key leased, subscription never decrypted (AC1).
2. `managed` + the same rows: subscription leased, `anthropic` never queried (AC2).
3. `api-key` + each malformed subscription class: api key leased, no `oauth_unusable`; `managed` + same: `oauth_unusable` unchanged (AC3).
4. Gate-order block: delegated, owner mismatch, pre-date, with an `api-key` resolver spy: gate error, spy uncalled (AC4).
5. Kill-switch off + `api-key`: api key, resolver uncalled, oauth never queried (AC4).
6. No oauth row: resolver uncalled (AC5); cached second call does not re-invoke.
7. Resolver rejects / junk values / absent resolver: `fetch_failed`, one event, closed reason, no secret in any sink (AC6).
8. `api-key` with no api row: `MissingByokKeyError` (AC8).
9. Scope escape: start the lease call inside the scope with a deferred resolver, end the scope, snapshot `providersQueried.length`, then settle the resolver; await the rejection explicitly (no unhandled rejection): `escape` thrown by the post-await `assertLeaseAlive`, `providersQueried.length` unchanged from the snapshot (no row read after scope end), `sinks.decrypted` adds nothing, nothing cached.
10. Real binding layer: binding `api-key` then flipped to `managed` between two leases flips the scheme; no run + legacy; no run + pending; read error (AC7).
11. Diagnostic agreement table (AC10).
12. Auto-sync/support bind-before-dispatch, sticky support row bound only when `pending`, non-fatal bind failure (AC11); five-branch forwarding and the `{ restOnly: true }` must-pass row (Guard 1).
13. UI: labels, helper line (Claude only), disclosure in both modes, PUT bodies (AC12).
14. Gate order with BOTH resolvers: delegated, owner-mismatch and pre-date cases run once with an `api-key` resolver and once with a `managed` resolver; the spy is asserted after awaiting the rejection (with `api-key` a mode-first mutation changes the error type; with `managed` only the call count catches it).
15. Environment hygiene: kill-switch-off cases `delete process.env.CC_OAUTH_ENABLED` (never set it to "0"); every new test file copies the existing `afterEach` (`vi.restoreAllMocks()` plus saved-env restore) verbatim so `Date.now` and `CC_OAUTH_ENABLED` cannot leak.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder text fails `deepen-plan` Phase 4.6; this one names concrete artifacts and a threshold with its reasoning.
- **Fail-closed blast radius** is the operator: the mode read runs only when an oauth row exists and the kill-switch is on. Anyone without a subscription row sees no behavioural change and no extra DB read. Verify with AC5.
- **Existing tests that lease with an oauth row and no resolver now fail closed by design.** Phase 6 sweeps them; do not "fix" them by weakening the no-resolver rule.
- **Cost cap flips for the operator under `api-key`** (cap enforced because the scheme becomes `api_key`): correct and intended; `soleur-go-runner.ts` needs no change.
- **A conversation keeps the mode it was created under.** The owner recovering from #11086 flips the dropdown and must start a new conversation; the helper line says so, and the existing conversation continues to fail closed. This is the documented CPO trade-off.
- **Migration immutability**: no migration is added or edited; `agent_engine_runs` and `workspace_engine_settings` are read through existing repository methods only.
- **`agent-env.ts` fence**: nothing under review adds the lowercase word `credential` to `server/agent-env.ts`; new file names and import paths use `auth-mode`.
- **userId guard**: no added line pairs `log.<level>` with a bare `userId`; the lease logs nothing new and the new `reportSilentFallback` events carry a closed reason only.
- **Source-text pins**: any new pin counts with `grep -c ... >/dev/null`; never `grep -v ... | grep -q`.
- **Pinned import boundaries**: `server/agent-auth-user-message.ts` and `server/agent-auth-match.ts` are untouched; `engine-binding-auth-mode.ts` imports no Sentry or logger, and the lease imports it by duck-typed `name` + `reason` only (no static edge to the Supabase graph).
- **Misleading retry copy for deterministic causes.** `fetch_failed` shows "Authentication unavailable; retry shortly" even for `unbound`, `invalid_value` and `no_resolver`, where retrying cannot help. Accepted for this PR (operator-only population, no new error cause, per the CTO ruling); recorded as a `taste` row so the owner can ask for distinct copy.
- **Sticky support conversations bind late.** A `pending` support conversation binds at its first post-deploy message and snapshots that day's default, not the default at creation.
- **Auto-sync retry on a permanent `unbound`.** `isLeaseRetryable` matches the lease message and would retry four times (about 13 s) before surfacing; bounded to one user, accepted.
- **Concurrent first calls.** Two concurrent `getAgentCredential()` misses each run the fetch and the second assignment overwrites `slot.agentCredentialBuffer` without zeroizing the first plaintext buffer. Pre-existing; the new `await` widens the window slightly but the binding is immutable (no INSERT/UPDATE/DELETE for `authenticated`, unique index on `conversation_id`), so both calls resolve the same mode. Not changed here; noted for the review phase.
- **Legacy conversations and the sticky legacy support row** behave as Automatic by ruling (AC16); for the operator a pre-feature conversation can still use the subscription token after `api-key` was chosen. Documented as the one P1 exception.
- **Codex.** `default_auth_mode` is one value shared by engines; a Codex run never reaches the Claude lease (`assertLegacyEngineBinding`), and Codex is not live. If Codex is later enabled, validate `auth_mode` per engine in the settings PUT; out of scope here.
- **`api-key` selected with no API key saved** surfaces only when the next conversation fails (an inline Settings warning was considered and not added; recorded in decision-challenges.md).
- **Passive alerting.** No Sentry alert rule keys on `byok-lease` ops (verified: none under `apps/web-platform/infra/sentry`), so `auth-mode-unresolved` is a passive issue stream that pages nobody, exactly like `oauth-credential-unusable`; adding a rule is infra work outside this PR.
- Draft PR #9051 (Codex lifecycle) also edits `components/settings/agent-engine-settings.tsx`: do not touch it; expect a rebase conflict in that file if it merges first, and keep this edit to the option text, one paragraph and one visibility predicate to keep that conflict small.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Lease reads the live workspace default (`default_auth_mode`) | Can disagree with the binding the egress policy, disclosure and diagnostic label were recorded against; needs the lease to know a workspace id it does not hold; flips behaviour mid-conversation. |
| Caller pre-resolves the mode before opening every lease | Adds a DB read to every lease for every user to serve a population of one. |
| New `ByokLeaseError` cause (`mode_unresolved`) | Touches the exhaustive `never` switch, the WS code, the Zod enum and the UI for no behavioural gain; `fetch_failed` already maps to the retry message. |
| Mode decided before reading the oauth row | The row must be read to know a subscription exists; deciding before decrypt already keeps a declined token out of memory. |
| Fail open to `managed` on a failed read | Would serve the declined account exactly when the system is least able to say so. |
| Reuse `makeAuthModeResolver` as-is | The file is deleted with the temporary diagnostic; the lease would then break. |
