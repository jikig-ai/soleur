# Tasks — feat-cc-cap-raise-resume

Plan: `knowledge-base/project/plans/2026-10-05-feat-resumable-concierge-cost-cap-plan.md`
Issue: #9565 · PR: #9560

## Phase 1: Provenance + managed exemption

- [x] 1.1 Add `setAuthScheme` optional sink to `QueryFactoryArgs`/`DispatchArgs`;
      call `args.setAuthScheme?.(credential.scheme)` after
      `lease.getAgentCredential()` in `cc-dispatcher.ts › realSdkQueryFactory`
      (mirror `setDelegationContext` at :1713-1720)
- [x] 1.2 Store `authScheme` on `ActiveQuery` at creation in `soleur-go-runner.ts`
- [x] 1.3 Skip cap enforcement when `authScheme === "oauth_token"` at
      `handleResultMessage` (:2432) and `dispatchChapterRouted` (:2912 —
      `perConvCap` `Infinity`/skip for managed)
- [x] 1.4 `cc-cost-caps.ts`: add exported `readCcManagedWarnCap` reader +
      `CC_MANAGED_WARN_USD` env var (default `50`)
- [x] 1.5 Emit one warn-level Sentry breadcrumb per ActiveQuery when managed
      `totalCostUsd` crosses the warn threshold
- [x] 1.6 Fallback: `authScheme` unset/unknown ⇒ enforce (fail toward protective)

## Phase 2: Cap-hit prompt (BYOK path)

- [x] 2.1 `emitCostCapPrompt(state)` in `soleur-go-runner.ts`: register
      `ask_user` prompt with sentinel `toolUseId: "cost-cap:<promptId>"`, tier
      options ascending above current cap + "Keep the cap"; emit
      `interactive_prompt`; `notifyAwaitingUser(convId, true)`; arm bounded
      `capPromptParkTimer` (registry TTL + grace) that un-parks, drops the
      parked message, and emits an expiry error frame; mirror
      `PendingPromptCapExceededError` handling
- [x] 2.2 Apply at both cap sites: `handleResultMessage` + chapter-router
      `cost-cap-hit` (park in-flight `userMessage` with `chapterRouted: true`)
- [x] 2.3 `cc-interactive-prompt-response.ts`: branch on `cost-cap:` sentinel
      `toolUseId` before `deliverToolResult` → injected `deliverCostCapResponse`
- [x] 2.4 `cc-dispatcher.ts › handleInteractivePromptResponseCase`: wire
      `deliverCostCapResponse` → `runner.applyCostCapRaise`
- [x] 2.5 `applyCostCapRaise`: parse + validate tier vs effective cap at
      response time; "Keep the cap" → `notifyAwaitingUser(false)` + error frame
      + drop parked; tier → `state.costCapOverrideUsd`, `notifyAwaitingUser(false)`,
      `persistCostCapOverride`, confirmation line, chapter-aware parked-message
      release (`dispatchChapterRouted` vs `pushUserMessage`)
- [x] 2.6 Dispatch-time gate: over-cap enforced send → park message + emit/refresh
      cap prompt (consume + re-register), no SDK push

## Phase 3: Persistence

- [x] 3.1 Migration `156_conversations_cc_cost_cap_usd.sql` + `.down.sql` with
      `-- LAWFUL_BASIS: Art. 6(1)(b)` annotation
- [x] 3.2 `conversation-writer.ts`: `cc_cost_cap_usd` in `ConversationPatch`
- [x] 3.3 `ws-handler.ts`: chat-case SELECT += `cc_cost_cap_usd`; `ClientSession`
      field; `costCapOverride` → `DispatchArgs` → seed at ActiveQuery creation
- [x] 3.4 `.env.example`: document `CC_MANAGED_WARN_USD`; mark daily-cap vars
      unwired

## Phase 4: Copy + tests

- [x] 4.1 Update Architecture-F4 comment (`cc-dispatcher.ts:4109-4116`) —
      recovery mechanism is now in-chat raise, not next-turn retry
- [x] 4.2 Tests: runner cap→prompt, managed skip, raise→override+persist+release,
      parked/decline/expiry paths, sentinel routing, authScheme sink,
      migration up/down per `test/supabase-migrations/` convention
- [x] 4.3 Fallback path test: no `pendingPrompts` dep ⇒ legacy `cost_ceiling` end
