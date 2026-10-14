# Tasks — fix: Concierge stop-gate sentinel leak

Plan: knowledge-base/project/plans/archive/20260930-145106-2026-09-30-fix-concierge-stop-gate-sentinel-leak-plan.md
Every code task starts with its failing test (cq-write-failing-tests-before). Commands run from apps/web-platform/ unless noted.

## 1. Root cause — web runtime must not run the operator guard
- 1.1 RED: rows in plugins/soleur/test/unkept-promise-hook.test.sh (incident CRM closing + "Implementing the lead form now."): BLOCK without env, ALLOW with SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1; env-aware verdict(); raise the four floors (51/51/51/62) by the rows added
- 1.2 RED: test/agent-env.test.ts — buildAgentEnv sets SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1 for api_key and oauth, and an ambient "0" cannot override it
- 1.3 GREEN: early exit in plugins/soleur/hooks/unkept-promise-hook.sh after the SOLEUR_HOOK_TRACE line and before the jq fail-open; header residual + trade-off + ordering comment
- 1.4 GREEN: SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK in AGENT_ENV_OVERRIDES (server/agent-env.ts)
- 1.5 Verify env inheritance on a dev dispatch during soleur:qa (method: Debug stream, or the SDK get_hooks_listing control request / includeHookEvents to see whether the Stop hook ran) (Debug stream: one assistant text, no second <stop> message); if the hook still fires, re-plan

## 2. Defence in depth — gate markup never renders
- 2.1 RED: test/stop-gate-markup.test.ts (table: markup-only, embedded, case/attribute, unterminated, multi-tag, lookalike <stopwatch>)
- 2.2 RED: test/soleur-go-runner-stop-gate.test.ts (list, stop-tag, result -> onText once with the list; embedded markup stripped; markup-only first block -> no onText; later prose block still replaces = accepted limit)
- 2.3 RED: dispatcher test — markup-only turn persists no empty assistant row
- 2.4 GREEN: server/stop-gate-markup.ts; call in handleAssistantMessage (before chapter-prefix logic); warnSilentFallback op stop-gate-markup-stripped (no body); guard empty save in cc-dispatcher onTextTurnEnd
- 2.4b Ordering: keep recordAssistantBlock(state, "text", null) ahead of the strip (watchdog re-arm) — a markup-only block must still re-arm
- 2.5 Sweep write sites; record legacy agent-runner as acknowledged residual

## 3. Turn ends cleanly on the client
- 3.0 Grep existing tests for a Send-returns-after-stream_end assertion; if found, jump to the stop condition
- 3.1 RED: test/cc-turn-end-wire.test.ts (dispatcher events -> sendToClient frames -> real chatReducer -> idle + done bubble); stop condition if it already passes
- 3.2 RED: rows in test/chat-reducer.test.ts (cc idle; stopping preserved; multi-leader; workflow/spawnIndex untouched; review_gate; tool_use -> stream_end -> stream)
- 3.3 GREEN: chatReducer stream_event arm in lib/ws-client.ts (CC_ROUTER_LEADER_ID from @/lib/cc-router-id); update comments
- 3.4 e2e: e2e/cc-soleur-go-bubbles.e2e.ts — Send returns, live-narration absent

## 4. Parity guard
- 4.1 test/plugin-stop-hooks-web-parity.test.ts: derive Stop hooks from hooks.json; registry {stop-hook.sh: web-safe (temp git repo), unkept-promise-hook.sh: web-disabled, browser-cleanup-hook.sh: deferred #9281}; hard-fail without bash/jq; behavioural spawn under buildAgentEnv's real env
- 4.2 Demonstrate the six mutation-matrix rows RED on a scratch copy; attest in the PR body

## 5. Records
- 5.1 Amend ADR-093 (Amendment + Alternatives incl. SDK-binding exclusion and SOLEUR_RUNTIME; trade-off; Stop-only scope) via soleur:architecture
- 5.2 Fix model.c4 api container description; run c4-code-syntax, c4-render, plugins/soleur/test/c4-count-parity.test.sh
- 5.3 File follow-up issues (non-Stop hooks classification; SOLEUR_RUNTIME axis), each with Mandated-By: wg-when-deferring-a-capability-create-a
- 5.4 tsc --noEmit, vitest for touched files, bash plugins/soleur/test/unkept-promise-hook.test.sh

## Work-phase status (2026-09-30)
- Phases 1-5 implemented and committed; 1.5 (hook env inheritance on a real dev dispatch) is a soleur:qa measurement and stays open until QA.
- 2.3 dropped: the dispatcher already drops empty-text turns (`saveAssistantMessage` returns on empty text, pinned by `cc-dispatcher.test.ts` T2), so the plan's premise that a markup-only turn persists an empty row was stale. No dispatcher change.
- 3.0: no existing Send-returns-after-stream_end assertion; 3.1 wire test was RED (`streaming`), so the stop condition did not apply. The tool_use -> stream_end -> stream reducer row was not added (`onTextTurnEnd` fires once per turn).
- 4.2: six mutation rows demonstrated RED on the committed tree, control green before and after (`/var/tmp/p4-mut.sh` run; attest in the PR body).
- 5.3: the two follow-ups were consolidated into one tracker, #9289 (net-flow rule); #9281 was filed at plan time.
