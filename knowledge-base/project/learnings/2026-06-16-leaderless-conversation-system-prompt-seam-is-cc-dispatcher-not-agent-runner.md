# Per-surface agent system-prompt directives attach at the cc-dispatcher seam, NOT agent-runner, for leader-less conversations

**Date:** 2026-06-16
**Surfaced by:** plan-review (kieran + architecture-strategist) of PR #5402 (routines Concierge tab). Caught as a P1 BEFORE implementation.

## The trap

To scope agent behavior per UI surface (a "mode directive" in the system prompt), the obvious seam is `agent-runner.ts` where `startAgentSession` assembles `systemPrompt` (`leaderIdentityOpener → artifactDirective → leaderBaselineRest`, ~line 1304). **For a leader-less `conversationId="new"` conversation, that path is dead code.**

Such a conversation materializes as `routing.kind === "soleur_go_pending"` and dispatches via `ws-handler.ts` `dispatchSoleurGoForConversation` → `dispatchSoleurGo` (cc-dispatcher) → the cc-soleur-go runner — explicitly bypassing `startAgentSession`/agent-runner (the post-#3270 always-on cc path). Appending a directive at the agent-runner seam would compile, pass type-checks, and silently never fire.

Worse: `context.type` is accepted on the wire and validated, but read NOWHERE that selects a directive — even the existing `"kb-viewer"` type is inert (only a display string in `domain-router.ts`). The artifact directive gates on `context.content`/`.path`, never `.type`. So a new `context.type`-driven directive is **net-new behavior, not an established pattern** — do not assume precedent.

## The correct seam

The cc path builds the base prompt in `soleur-go-runner.ts` `buildSoleurGoSystemPrompt`, then the factory (`realSdkQueryFactory` in `cc-dispatcher.ts`) wraps it into `effectiveSystemPrompt` and appends capability addenda (`contextResetNotice`, `c4PromptAddendum`, the gh-403 directive). A per-surface directive belongs right there, alongside `c4PromptAddendum`.

Threading a per-dispatch flag to that factory crosses the deferred-construction boundary — it must hop **all** of: `DispatchSoleurGoArgs` (cc-dispatcher) → `runner.dispatch` call → `DispatchArgs` (soleur-go-runner) → the `queryFactory({...})` construction site → `QueryFactoryArgs` → the factory read site. Five hops; tsc enforces each, but a dropped hop = a silently-inert directive (the exact failure the wrong-seam choice would have produced).

## Takeaways

1. Before placing an agent-behavior guard/directive, trace which dispatch path the *actual* trigger conversation takes. For dashboard chat (`conversationId="new"`, no leader), it's cc-dispatcher, not agent-runner. `grep "dispatchSoleurGoForConversation\|startAgentSession" ws-handler.ts` and read the routing branch.
2. `context.type` being accepted by validation ≠ `context.type` doing anything. Grep for actual reads before claiming precedent.
3. When threading a per-dispatch value to the cold-Query factory, enumerate every hop (Args → dispatch → runner Args → factory-construction → factory read) — type-check is the safety net, but list them so none is dropped.
4. This was caught at plan-review for ~4 agents' cost; the wrong seam would have shipped a directive that never fired, discoverable only by noticing the Concierge didn't behave differently in the tab. Plan-review on agent-prompt-plumbing changes earns its keep.
