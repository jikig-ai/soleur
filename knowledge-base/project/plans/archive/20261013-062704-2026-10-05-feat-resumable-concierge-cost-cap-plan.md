---
title: "feat: resumable Concierge cost cap — no hard-kill on managed sessions, raise-and-continue on BYOK"
date: 2026-10-05
slug: feat-resumable-concierge-cost-cap
branch: feat-cc-cap-raise-resume
issue: 9565
closes: 9565
type: feat
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: resumable Concierge cost cap — no hard-kill on managed sessions, raise-and-continue on BYOK

## Overview

The Concierge cc runner's per-conversation cost cap terminates the conversation's
SDK Query on breach (`cost_ceiling`), which is wrong twice over: managed sessions
(where the user still pays Soleur) should not be hard-stopped at all, and BYOK
sessions need a resumable raise affordance instead of a dead end that discards
the conversation's in-memory context. This plan reuses the existing
`interactive_prompt` machinery (the dormant `ask_user` kind) to make cap-hit an
in-chat "raise cap and continue" prompt, keeps the Query alive, threads
credential provenance into cap enforcement, and persists the per-conversation
override.

## Research Insights

### Premise Validation

- Issue #9565 was created this session — verified OPEN.
- Code claims in the spec were verified directly AND corrected by two repo
  research passes (see Research Reconciliation below — the spec's framing of the
  kill mechanism was wrong and has been amended in-place).
- No ADR conflict: grepped `knowledge-base/engineering/architecture/decisions/`
  for cost-cap/cap mechanisms — ADR-041 covers the BYOK *cumulative* kill-switch
  (a different layer, untouched by this plan); no ADR rejects an in-chat cap
  override.

### Property List

1. A managed-session conversation is never terminated by the per-conversation
   spend cap.
2. A BYOK-session cap breach presents an in-chat raise affordance; accepting it
   lets the same conversation continue with context intact.
3. A raised cap survives reload/reconnect (persisted per conversation).
4. Declining or ignoring the prompt keeps the cap; the next agent-bound send
   re-prompts rather than silently spending past it.
5. An operator can still observe runaway managed spend (telemetry-only
   threshold).

### Cut List

- **Dedicated `cost_cap_hit` wire event + custom banner (Approach B)** → property
  2 → already covered by `interactive_prompt` + the dormant `ask_user` card.
- **Per-user cap in dashboard settings (Approach C)** → deprioritized by the
  operator; does not resume mid-conversation.
- **New `cost_cap` InteractivePromptKind** → property 2 → `ask_user` reuse avoids
  six union-exhaustiveness rails (`INTERACTIVE_PROMPT_KINDS`, payload/response
  unions, `KIND_MAP`, `normalizeResponse`, Zod schema, card builder) and avoids
  the `.pen` wireframe gate entirely (no `components/**` file changes).
- **Wiring `readCcDailyCaps`** (`CC_USER_DAILY_USD_CAP`/`CC_GLOBAL_DAILY_USD_CAP`)
  → these env vars are parsed but enforced nowhere today (zero production
  callers). Out of scope; recorded as a finding.

### Relevant file paths

- `apps/web-platform/server/soleur-go-runner.ts` — cap check at `handleResultMessage`
  (~:2432) and `dispatchChapterRouted` (~:2958); `emitWorkflowEnded`→`closeQuery`
  teardown (:2034+); `capFor` (:1868); `ActiveQuery` cost state (:2751);
  `bridgeInteractivePromptIfApplicable` (:1815); `respondToToolUse` (:3309);
  `notifyAwaitingUser` (:3346) / `reapIdle` skip on `awaitingUser` (:3264).
- `apps/web-platform/server/cc-dispatcher.ts` — `realSdkQueryFactory` lease +
  `credential.scheme` (:1703-1729); `setDelegationContext` sink precedent
  (:1713-1720, runner :1092); `getSoleurGoRunner` dep wiring (:3055-3072);
  `handleInteractivePromptResponseCase` → `deliverToolResult` (:4503-4552).
- `apps/web-platform/server/byok-lease.ts` — `fetchAgentCredentialIntoSlot`
  (:495-539): `oauth_token` = managed, `api_key` = BYOK.
- `apps/web-platform/server/cc-interactive-prompt-response.ts` —
  `handleInteractivePromptResponse` + `normalizeResponse` + `KIND_MAP`.
- `apps/web-platform/server/conversation-writer.ts` — `ConversationPatch`
  allowlist (:90-97), `updateConversationFor` (:151).
- `apps/web-platform/server/ws-handler.ts` — chat-case cache-miss SELECT
  (:2580-2584), `ClientSession` fields (:341-356), `persistActiveWorkflow`
  (:1257-1302).
- `apps/web-platform/server/cc-workflow-end-messages.ts` /
  `apps/web-platform/lib/session-ended-copy.ts` — copy maps + parity test.
- `apps/web-platform/components/chat/interactive-prompt-card.tsx` — dormant
  `AskUserCard` (:166-259), reused verbatim (no edit).
- `apps/web-platform/server/pending-prompt-registry.ts` — record shape
  (`toolUseId` required, :49-57), 50/conv cap, 5-min TTL.

### Institutional learnings applied

- `best-practices/2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates.md` —
  ordering of guard vs. recovery.
- `cq-union-widening-grep-three-patterns` — avoided entirely by reusing
  `ask_user` instead of widening `InteractivePromptKind`.
- Filing-gate taxonomy: `User-Impact:` must name a token from
  `.claude/hooks/lib/user-surface-taxonomy.txt`.

### Related issues / PRs

- #9565 (this work), draft PR #9560.
- Overlap-checked open code-review issues: see `## Open Code-Review Overlap`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `cost_ceiling` routes through `TERMINAL_WORKFLOW_END_STATUSES` → `session_ended` | It emits a non-terminal `{type:"error"}` frame; the kill is `emitWorkflowEnded`→`closeQuery` Query teardown (`soleur-go-runner.ts:2034-2095`, `cc-dispatcher.ts:4151-4155`) | Keep the Query open at cap-hit; no `session_ended` changes needed for the happy path |
| Composer disabled on cap | Composer stays enabled (`chat-surface.tsx:1328` gates on `workflowEnded`/`status`, neither fires) | The affordance is additive; users could always type — but a send while over cap would previously just die |
| Cap is per-conversation | `state.totalCostUsd` resets per ActiveQuery — effectively per-Query-lifetime | Persisted override keyed on `conversations` row; note that cap accrual itself still resets on cold Query (pre-existing quirk, documented in Open Questions) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a paying user's Concierge
  conversation is destroyed mid-task by a spend guardrail, or (BYOK) a raise
  that silently doesn't take lets an agent overspend the user's own Anthropic
  key.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  stuck or mis-routed cap prompt stranding a live paid conversation; a managed
  exemption bug applying to BYOK (user's own money spent uncapped).
- **Brand-survival threshold:** `single-user incident`.
- **Threshold decision (challengeable):** touches a billing-adjacent guardrail
  on a paid conversation surface; a misapplied managed exemption or a lost raise
  is a single-user money incident, not a fleet event.

`requires_cpo_signoff: true` is set in frontmatter per plan Phase 2.6 Step 3.
On this Devin CLI harness the named `soleur:product:cpo` agent is not invocable —
the sign-off obligation is recorded here and satisfied at review time by
`soleur:engineering:review:user-impact-reviewer` (the load-bearing gate) plus
operator ack of this plan.

## Implementation Phases

### Phase 1 — Provenance + managed exemption

1. `cc-dispatcher.ts › realSdkQueryFactory`: after `lease.getAgentCredential()`
   (:1729), call `args.setAuthScheme?.(credential.scheme)` — a new optional sink
   on `QueryFactoryArgs`/`DispatchArgs`, mirroring `setDelegationContext`
   (:1713-1720).
2. `soleur-go-runner.ts`: store `authScheme` on `ActiveQuery` at creation.
   In `handleResultMessage`'s cap check AND `dispatchChapterRouted`'s
   `perConvCap` (pass `Infinity`/skip for managed so `selectChapter` never
   returns `cost-cap-hit` and the message routes normally), skip enforcement
   when `state.authScheme === "oauth_token"` (managed). Emit a warn-level Sentry
   breadcrumb **once per ActiveQuery** (per-Query flag; re-arms on cold Query —
   accrual is per-Query anyway) when managed `totalCostUsd` crosses
   `CC_MANAGED_WARN_USD` (default `50`, parsed by a new exported
   `readCcManagedWarnCap` reader in `cc-cost-caps.ts` — `parsePositive` is
   module-private today and stays so) — telemetry-only, never blocks.
3. Fallback safety: if `authScheme` is unset (older queries, tests), enforce the
   cap — fail toward the protective behavior, not the permissive one.

### Phase 2 — Cap-hit prompt (BYOK path)

1. `soleur-go-runner.ts` new `emitCostCapPrompt(state)`:
   - Gate on `pendingPrompts && emitInteractivePrompt` — absent ⇒ keep today's
     `emitWorkflowEnded({status:"cost_ceiling"}` fallback (non-WS contexts,
     tests).
   - Register a `PendingPromptRecord` with `kind: "ask_user"` and sentinel
     `toolUseId: "cost-cap:<promptId>"`; payload `{question, options,
     multiSelect:false}` where options are tier strings derived from the current
     cap (e.g. `["Raise to $5", "Raise to $10", "Raise to $25", "Keep the cap"]`,
     always ascending above `cap`).
   - Emit the `interactive_prompt` event; call the runner's existing
     `notifyAwaitingUser(conversationId, true)` (public method, :3346) — it owns
     `awaitingUser`, `pausedAt`, and the runaway/turnHardCap clears, so
     `reapIdle` skips the parked conversation (:3264-3270). Do NOT hand-roll the
     flag writes.
   - **Bounded park (permanent-leak fix):** `PendingPromptRegistry.reap()` has
     NO expiry callback, so TTL expiry alone would leave `awaitingUser` stuck
     forever. Arm a `capPromptParkTimer` on emit (duration = registry TTL + a
     small grace); on fire, call `notifyAwaitingUser(convId, false)`, emit an
     error frame ("Cap prompt expired — send your message again to re-raise"),
     and drop `state.parkedUserMessage`. The conversation then rejoins normal
     idle reaping — same absolute bound the review-gate gets from
     `REVIEW_GATE_TIMEOUT_MS`.
   - Re-emit on repeat sends: the registry has no update op — consume the
     existing `cost-cap:*` record and re-register (mirror the bridge's
     `PendingPromptCapExceededError` handling at :1837-1849; a workflow that
     burns 50 prompts is a real warning, not a silent drop).
   - Do NOT call `emitWorkflowEnded` — the Query stays open.
   - Apply at both cap sites: `handleResultMessage` (:2432) and the
     chapter-router `cost-cap-hit` branch (:2958). **At the chapter-routed
     site, park the in-flight `userMessage`** (`state.parkedUserMessage =
     {text, chapterRouted: true}`) — that branch fires *after* `selectChapter`
     already spent a routing turn, so the dispatch-entry gate cannot cover it,
     and dropping the message is the bug being fixed.
2. `cc-interactive-prompt-response.ts › handleInteractivePromptResponse`: before
   `deliverToolResult`, branch on `record.toolUseId` starting with `cost-cap:` →
   call new injected dep `deliverCostCapResponse({conversationId, response})`
   instead (the record's `toolUseId` is never a real SDK tool_use id — feeding a
   `tool_result` would corrupt the stream).
3. `cc-dispatcher.ts › handleInteractivePromptResponseCase`: wire
   `deliverCostCapResponse` → `runner.applyCostCapRaise(conversationId, response)`.
4. `soleur-go-runner.ts` new `applyCostCapRaise(conversationId, response)`:
   - Parse the option string → new cap; validate it against the **effective cap
     at response time** (not emit time — a raise→re-trip window can leave a
     stored option below the current cap; reject those →
     `interactive_prompt_rejected` path already exists).
   - "Keep the cap" → `notifyAwaitingUser(conversationId, false)` (resume path
     re-arms timers + accumulates `totalPausedMs`, :3386-3405), emit a
     `{type:"error"}` with honest copy ("Cap unchanged — raise it to keep
     going"), and drop the parked message saying so.
   - Tier → set `state.costCapOverrideUsd` (checked first in `capFor` call
     sites), `notifyAwaitingUser(convId, false)`, persist via new
     `DispatchArgs` `persistCostCapOverride` →
     `updateConversationFor({cc_cost_cap_usd})`.
   - Emit a confirmation text/stream line ("Cap raised to $10 — continuing.")
     and release the parked message **chapter-aware**: if
     `state.parkedUserMessage.chapterRouted` / `chapterChunkedContext` is set,
     re-dispatch through `dispatchChapterRouted` (the `pushUserMessage` path is
     deliberately bypassed for chapter-chunked conversations, :2842); otherwise
     `pushUserMessage`.
5. Dispatch-time gate in `dispatchSoleurGo` (or the runner's `dispatch`): for an
   enforced session whose `totalCostUsd >= cap` (override-aware), park the
   inbound user message on state and emit/refresh the cap prompt instead of
   pushing it to the SDK — prevents spend-past-cap on a dead prompt.

### Phase 3 — Persistence

1. `supabase/migrations/156_conversations_cc_cost_cap_usd.sql` +
   `.down.sql`: `alter table conversations add column cc_cost_cap_usd numeric
   null;` with `-- LAWFUL_BASIS: Art. 6(1)(b) contract performance —
   per-conversation spend ceiling chosen by the user` (gdpr-gate GDPR-Art-6
   finding).
2. `conversation-writer.ts`: add `cc_cost_cap_usd` to `ConversationPatch`.
3. `ws-handler.ts`: chat-case cache-miss SELECT (:2580-2584) += `cc_cost_cap_usd`;
   new `ClientSession` field; pass `costCapOverride` into `dispatchSoleurGo` →
   `DispatchArgs` → seed `state.costCapOverrideUsd` at ActiveQuery creation.
4. `.env.example`: document `CC_MANAGED_WARN_USD`; annotate
   `CC_USER_DAILY_USD_CAP`/`CC_GLOBAL_DAILY_USD_CAP` as currently unwired
   (accurate-advertising fix, not enforcement).

### Phase 4 — Copy + tests

1. `cc-workflow-end-messages.ts` `cost_ceiling` copy stays (fallback path when
   prompt machinery is absent — still honest: query dies there). Update the
   Architecture-F4 comment at `cc-dispatcher.ts:4109-4116`: `cost_ceiling` was
   already recoverable-as-retry; what changes is the recovery mechanism moves
   from next-turn retry (Query already dead) to in-chat raise (Query alive).
2. Tests: `test/soleur-go-runner-*.test.ts` (cap→prompt emission with fake deps;
   managed skip; raise→override; parked-message release; decline path),
   `test/cc-interactive-prompt-response.test.ts` (sentinel routing),
   `test/cc-dispatcher.test.ts` (authScheme sink, persistCostCapOverride wiring),
   migration test per `test/supabase-migrations/` convention.

## Files to Create

- `apps/web-platform/supabase/migrations/156_conversations_cc_cost_cap_usd.sql`
- `apps/web-platform/supabase/migrations/156_conversations_cc_cost_cap_usd.down.sql`
- `apps/web-platform/test/soleur-go-runner-cost-cap-resume.test.ts` (or extend
  the existing lifecycle suite — match file convention at implement time)

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/cc-interactive-prompt-response.ts` (sentinel
  routing branch; KIND_MAP untouched — `ask_user` reuse)
- `apps/web-platform/server/conversation-writer.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/server/cc-cost-caps.ts` (new `readCcManagedWarnCap` export)
- `apps/web-platform/server/cc-workflow-end-messages.ts` (comment only)
- `apps/web-platform/lib/session-ended-copy.ts` (comment/parity only if copy moves)
- `apps/web-platform/.env.example`

(No `components/**` or `app/**/page.tsx` edits — the dormant `AskUserCard`
renderer is reused verbatim.)

## Observability

```yaml
liveness_signal:
  what: Sentry breadcrumb "cc-managed-soft-cap" when managed spend crosses CC_MANAGED_WARN_USD; pino log line "cost-cap-prompt emitted" per cap-hit
  cadence: per-event
  alert_target: Sentry issue stream (warn level)
  configured_in: apps/web-platform/server/soleur-go-runner.ts (emitCostCapPrompt / managed warn branch)

error_reporting:
  destination: Sentry web-platform via reportSilentFallback (existing util)
  fail_loud: "{type:\"error\", errorCode:\"interactive_prompt_rejected\"}" WS frame on invalid raise; error frame on dropped parked message

failure_modes:
  - mode: Cap prompt emitted but never answered; parked conversation leaks (awaitingUser skips reapIdle)
    detection: bounded park timer fires at registry TTL + grace → notifyAwaitingUser(false) re-arms normal idle reaping; warn log "cost-cap park expired" per conversation
    alert_route: none (bounded by construction); Sentry breadcrumb if expiry count > 3 per conversation
  - mode: Headless / MCP-driven BYOK conversation hits cap — interactive_prompt is WS-only, no client can answer
    detection: parked + park-timer expiry path above bounds it; Sentry warn on expiry (same breadcrumb)
    alert_route: none (v1); V2 tracking issue for an MCP/agent-native raise path is a named follow-up
  - mode: Managed exemption misapplied to BYOK (authScheme wrong)
    detection: authScheme asserted from lease.getAgentCredential() scheme, not user input; unit test pins api_key→enforce
    alert_route: Sentry warn on unknown scheme values
  - mode: Persisted override write fails
    detection: updateConversationFor Sentry mirror (existing) + raise confirmation emitted only after persist succeeds
    alert_route: Sentry issue

logs:
  where: pino stdout → Better Stack (existing web-platform log pipeline)
  retention: Better Stack configured retention

discoverability_test:
  command: grep -q deliverCostCapResponse apps/web-platform/server/cc-dispatcher.ts && printf 'ok'
  expected_output: "ok"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "in case of managed session not API Key session, we should not enforce a conversation cap" | Phase 1 (authScheme provenance + managed skip) | mapped |
| 2 | "this is not actionable, opening a new conversation will have exactly the same issue" | Phase 2 (in-chat raise prompt keeps Query+context) | mapped |
| 3 | "We should allow to increase the cap and not break the conversation or resume it once the cap has been increased" | Phase 2 (applyCostCapRaise) + Phase 3 (persisted override) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Managed soft-warn breadcrumb (`CC_MANAGED_WARN_USD`) | none — inferred | inferred: runaway-spend visibility after removing enforcement; telemetry-only, cheap |
| Persisted per-conversation override | "resume it once the cap has been increased" | asked (persistence is the only honest reading of resume across reload) |
| Parked-message dispatch gate | "not actionable" | inferred: a send while over cap must not silently spend or silently drop |
| Daily-cap env wiring | none | parked — vars are dead config today; recorded as finding, not scope |
| BYOK cumulative kill-switch interaction | none | parked — ADR-041 layer is founder-bill protection; orthogonal |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` server + lib + supabase
- Planned files: ~10 | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] A conversation on a managed (`oauth_token`) credential never receives
  `cost_ceiling` / never has its Query closed by the per-conversation cap;
  crossing `CC_MANAGED_WARN_USD` emits one Sentry breadcrumb per ActiveQuery
  (the warn flag lives per-Query, matching the per-Query accrual it measures).
- [ ] A BYOK conversation crossing its cap emits an `interactive_prompt`
  (`ask_user` kind, sentinel `toolUseId`) and the Query stays open
  (`awaitingUser` set; `reapIdle` skips).
- [ ] Answering the prompt with a raise tier sets the per-conversation override,
  persists it to `conversations.cc_cost_cap_usd`, emits a confirmation, and
  delivers any parked user message to the live Query.
- [ ] Answering "Keep the cap" (or prompt TTL expiry) leaves the cap enforced;
  the next agent-bound send re-emits the prompt without spending.
- [ ] After a reload/reconnect, the raised cap is honored (SELECT seeds the
  override).
- [ ] With `pendingPrompts`/`emitInteractivePrompt` absent, behavior falls back
  to today's `cost_ceiling` end (no regression in non-WS contexts).
- [ ] `emitWorkflowEnded` is never called for per-conversation cap breach when
  the prompt path is active; `totalCostUsd` and workflow context survive.
- [ ] Migration `156_*` applies cleanly up and down; the column carries a
  `-- LAWFUL_BASIS:` annotation.

## Test Scenarios

- Given a managed session (`authScheme="oauth_token"`), when `totalCostUsd`
  crosses the per-workflow cap, then no `cost_ceiling` is emitted and the Query
  stays open; crossing the warn threshold emits one Sentry breadcrumb.
- Given a BYOK session at cap, when the result lands, then an
  `interactive_prompt` with `kind:"ask_user"` and `toolUseId:"cost-cap:*"` is
  emitted and `state.closed` stays false.
- Given a pending cap prompt, when the user picks "Raise to $10", then
  `applyCostCapRaise` sets the override, persists `cc_cost_cap_usd=10`, clears
  `awaitingUser`, and pushes the parked message.
- Given a pending cap prompt, when the user picks "Keep the cap", then no raise
  is applied and an honest error frame says the parked message was not sent.
- Given a BYOK conversation over cap with no pending prompt, when the user sends
  a message, then the message is parked and the cap prompt is (re-)emitted
  without any SDK spend.
- Given `pendingPrompts` is undefined (test harness), when the cap trips, then
  `cost_ceiling` is emitted exactly as today.
- Given a response to a `cost-cap:` record, then `handleInteractivePromptResponse`
  routes to `deliverCostCapResponse` and never calls `deliverToolResult`.

## Domain Review

**Domains relevant:** Engineering, Finance, Legal (weak)

### Engineering

**Status:** reviewed (in-harness: two repo research passes by
`subagent_explore` agents — the named `soleur:*` leader agents are not invocable
via `run_subagent` on Devin CLI)
**Assessment:** See Research Insights — mechanism reuse verdict, persistence
design, and the two spec corrections are all grounded in traced code paths.

### Finance

**Status:** reviewed
**Assessment:** Removing per-conversation enforcement on managed sessions shifts
runaway-spend risk to the metered bill; mitigated by the warn-only
`CC_MANAGED_WARN_USD` breadcrumb and the unchanged founder-wide BYOK kill-switch
(ADR-041). The per-conversation cap was also found to be weaker than believed —
it resets per Query lifetime — so managed spend was already softer than the
nominal $2/$5.

### Product/UX Gate

**Tier:** none — no `components/**` / `app/**` file changes; the dormant
`AskUserCard` renderer is reused verbatim, so the mechanical UI-surface override
does not fire and `wg-ui-feature-requires-pen-wireframe` does not trigger (no
new/changed UI surface file).
**Pencil available:** yes (headless CLI verified) — unused this change.

## GDPR Gate (Phase 2.7 output)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

### `GDPR-Art-6` — new column needs lawful-basis annotation

- **Severity:** Important
- **Article:** GDPR Art. 6
- **Location:** `supabase/migrations/156_conversations_cc_cost_cap_usd.sql` (planned)
- **Pattern matched:** new schema column on `conversations`
- **Why this matters:** every new column carries a lawful-basis annotation per the
  gate's mandatory check.
- **What to do:** ship the migration with `-- LAWFUL_BASIS: Art. 6(1)(b) contract
  performance — per-conversation spend ceiling chosen by the user`.

No Critical findings — the column is a non-PII numeric; no Art. 9 field names, no
new FK to `users`, no new vendor.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` against every planned
file path:

- #3243 `arch: decompose cc-dispatcher.ts` — **Acknowledge** (large refactor,
  different concern; this plan's edits are localized and don't worsen it).
- #3242 `tool_use WS event lacks raw name` — **Acknowledge** (unrelated field).
- #2963 `Supabase typegen for ConversationPatch` — **Acknowledge** (this plan
  adds `cc_cost_cap_usd` to `ConversationPatch`; typegen would help but is its
  own cycle).
- #3374 `slot_reclaimed WS frame` — **Acknowledge** (unrelated WS frame).
- #2191 `clearSessionTimers` — **Acknowledge** (unrelated ws-handler refactor).

## Sharp Edges

- **`PendingPromptRecord.toolUseId` is required.** The cap prompt uses a sentinel
  (`cost-cap:<promptId>`) — the response router MUST branch on it before
  `deliverToolResult`, or a `tool_result` with a bogus id corrupts the SDK stream.
- **`awaitingUser` must be set explicitly.** The existing setters are the
  `waiting_for_user` status writes from `permission-callback.ts`; a
  runner-emitted cap prompt writes no status, so it must call
  `notifyAwaitingUser` itself — without it `reapIdle` reaps the parked
  conversation at 10 min.
- **Pending-prompt TTL is 5 min.** A cap prompt can legitimately sit longer; on
  expiry the next send re-prompts (designed) — do NOT extend TTL in this PR.
- **Fail toward enforcement.** `authScheme` unset/unknown ⇒ enforce the cap.
  The managed exemption keys ONLY on `oauth_token` provenance captured inside
  the lease, never on user-controlled input.
- **Cap accrual resets per Query lifetime** (pre-existing `state.totalCostUsd`
  behavior). This plan does not fix that — the *override* persists, accrual does
  not. Recorded as a known limitation.
- **Scope note:** the legacy `agent-runner.ts` leader loop has its own
  `cost-cap-hit` branch (:2038-2047, Sentry-mirrored "unexpected") sharing
  `selectChapter` — this plan scopes to the cc runner only; the legacy branch
  stays as-is.
- **Spec correction already applied:** `cost_ceiling` was never terminal; the
  fix targets Query teardown, not `session_ended` routing.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. Filled above.

## Open Questions

- Should a raise also lift the chapter-router `perConvCap`? (Yes —
  `dispatchChapterRouted` reads `capFor`, which will consult the override —
  same code path.)
- Should the managed soft-warn threshold be per-conversation only, or also a
  daily user aggregate? (Per-conversation in v1; daily aggregates are the
  dead-config `readCcDailyCaps` problem — parked.)
- Copy for the prompt/confirmation — placeholder text in phases; tighten at
  review.
