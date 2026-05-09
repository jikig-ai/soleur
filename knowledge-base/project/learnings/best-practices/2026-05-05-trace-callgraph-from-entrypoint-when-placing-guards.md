---
date: 2026-05-05
category: best-practices
module: cc-dispatcher / agent-runner / ws-handler
issue: 3250
pr: 3263
related_issues: [3266, 3269, 3270]
tags: [planning, call-graph-trace, multi-agent-review, sentry-deferral-gate, test-mock-sweep]
---

# Trace the call-graph from the entry-point when placing a defensive guard, not just from the chosen call-site outward

## Problem

PR #3263 added a thread-shape prefill guard inside `realSdkQueryFactory` (`apps/web-platform/server/cc-dispatcher.ts`) to prevent the Anthropic 400 "model does not support assistant message prefill" on session resume. The plan chose the cc-soleur-go path as the guard location based on the issue's pointer to `soleur-go-runner.ts:1078,1101` (where `args.sessionId → resumeSessionId → buildAgentQueryOptions` flows correctly inside the runner).

Multi-agent review surfaced a **production-effective dormancy**: the guard cannot fire today because the upstream wiring from the WebSocket frame to the runner is broken on the cc path:

1. `apps/web-platform/server/ws-handler.ts:539-630` (`dispatchSoleurGoForConversation`) does NOT thread `session_id` to `dispatchSoleurGo`. The SELECT at `ws-handler.ts:1138` reads `session_id` but discards it.
2. There is no writer that persists `state.sessionId` from `apps/web-platform/server/soleur-go-runner.ts:972` back to `conversations.session_id` for the cc path. The legacy `agent-runner.ts:951-957` writer has no cc-side equivalent.

Together: `args.resumeSessionId` reaches the cc-side `realSdkQueryFactory` as `undefined` on every cold start, the guard short-circuits, and the SDK starts a fresh server-side session.

The actual prefill 400 the user reported in #3250 fires on the **legacy** `startAgentSession` path (`apps/web-platform/server/agent-runner.ts:468`), which IS resume-wired (`agent-runner.ts:1355` reads `conv.session_id`) and shares the same default model `claude-sonnet-4-6`. The guard, as originally placed, does not protect the user-facing surface that produced the bug report.

## Solution

Extract the guard logic into a shared helper and call from BOTH paths:

```typescript
// apps/web-platform/server/agent-prefill-guard.ts (new)
export interface ApplyPrefillGuardArgs {
  resumeSessionId: string | undefined;
  workspacePath: string;
  userId: string;
  conversationId: string;
  feature: "cc-concierge" | "agent-runner"; // distinguishes call sites in Sentry
  leaderId?: string;
}

export async function applyPrefillGuard(
  args: ApplyPrefillGuardArgs,
): Promise<{ safeResumeSessionId: string | undefined }> {
  if (!args.resumeSessionId) return { safeResumeSessionId: undefined };

  let history: SessionMessage[];
  try {
    history = await getSessionMessages(args.resumeSessionId, {
      dir: args.workspacePath,
    });
  } catch (err) {
    warnSilentFallback(sanitizeProbeError(err), {
      feature: args.feature,
      op: "prefill-guard-probe-failed",
      extra: { /* baseExtra */ },
    });
    return { safeResumeSessionId: args.resumeSessionId };
  }

  const last = history[history.length - 1];
  if (last && last.type === "assistant") {
    warnSilentFallback(null, {
      feature: args.feature,
      op: "prefill-guard",
      /* ... */
    });
    return { safeResumeSessionId: undefined };
  }

  return { safeResumeSessionId: args.resumeSessionId };
}
```

Both paths invoke it before `buildAgentQueryOptions`:

```typescript
// cc-dispatcher.ts realSdkQueryFactory (parallelized with patchWorkspacePermissions)
const [, prefillGuardResult] = await Promise.all([
  patchWorkspacePermissions(workspacePath),
  applyPrefillGuard({
    resumeSessionId: args.resumeSessionId,
    workspacePath,
    userId: args.userId,
    conversationId: args.conversationId,
    feature: "cc-concierge",
    leaderId: CC_ROUTER_LEADER_ID,
  }),
]);

// agent-runner.ts startAgentSession (sequential — patchWorkspacePermissions already serialized with syncPull)
const { safeResumeSessionId } = await applyPrefillGuard({
  resumeSessionId,
  workspacePath,
  userId,
  conversationId,
  feature: "agent-runner",
  leaderId: effectiveLeaderId,
});
```

The cc-path guard becomes forward-compatible plumbing (activates when cc resume wiring lands, tracked in #3266); the legacy guard fixes the actual production exposure today.

## Key Insight

**A guard added at function-internal layer X protects only the inputs that reach X. Tracing where the value-of-interest comes from is part of placing the guard, not a separate verification step.** The plan's "Research Reconciliation — Spec vs. Codebase" table confirmed threading at `soleur-go-runner.ts:1078,1101` (runner-internal) but did not trace the value upstream from `ws-handler.ts → dispatchSoleurGo → runner.dispatch({sessionId})`. The trace would have surfaced the missing `dispatchSoleurGoForConversation → dispatchSoleurGo` thread immediately.

This generalizes: whenever a plan places a defensive guard, trace the value the guard inspects from the **entry point** (WS frame, route handler, queue worker, cron tick) all the way to the guard's input — not just from the guard outward. The "outward" trace verifies the guard's correctness given an input; the "inward" trace verifies the input ever exists.

## Session Errors

1. **Plan-time guard-placement blind spot** — Plan chose `realSdkQueryFactory` based on runner-internal threading without tracing upstream from `ws-handler.ts`. The cc-path guard is dormant in prod. **Recovery:** Helper extraction (Approach A) called from both paths. **Prevention:** When a plan adds a defensive guard at a chosen call-site, trace the value-of-interest from the entry point through every frame to the guard's input — proposed as a Sharp Edge in the `plan` skill.

2. **Outdated source comment misled production-reachability reasoning** — `cc-dispatcher.ts:7-10` claimed "Behind FLAG_CC_SOLEUR_GO=0 in prod (default) this code path is unreachable." Doppler showed `FLAG_CC_SOLEUR_GO=1` in both `prd` and `dev`. **Recovery:** `doppler secrets get FLAG_CC_SOLEUR_GO -p soleur -c prd --plain`. **Prevention:** When reasoning about a guard's production reachability, verify env-flag values from Doppler (or other source of truth), not from in-source comments — already aligned with `hr-exhaust-all-automated-options-before` (Doppler is tier-1).

3. **Sentry zero-hits as a deferral gate without title-shape verification** — Plan's Phase 3 trigger ("Sentry 90d hits → fold in / 0 hits → defer") returned 0 against 680 baseline events for queries on `prefill`/`claude-sonnet-4-6`/`invalid_request_error`. Architecture review pointed out Anthropic 400s land as `Error: Claude Code returned an error result: …` titles without the request body fields, so substring matching would not catch them. **Recovery:** Broader query (`anthropic OR claude OR APIError`) confirmed the original was too narrow; legacy fold-in landed regardless via the architectural-fact path. **Prevention:** When using Sentry as a deferral gate, run a representative substring-broadening sweep first (e.g. error-class wrappers, stripped-status-code variants) AND confirm at least one matching event exists for a known-recent error class — a query that returns 0 against an empty result space proves nothing.

4. **Test mock drift on observability imports** — Adding `applyPrefillGuard` (imports `warnSilentFallback`) broke `session-resume-fallback.test.ts` whose `vi.mock("../server/observability", …)` factory omitted that export. Same defect class as `cq-supabase-wrapper-test-mock-chain-sweep` (PR #2722 / wrapper-extension sweep) but for observability imports rather than Supabase fluent chains. **Recovery:** Added `warnSilentFallback: vi.fn()` to the mock. **Prevention:** When a new server-side helper imports from a heavily-mocked module (`observability.ts`, `logger.ts`, supabase wrappers), grep `apps/web-platform/test/` for `vi.mock(['"](\.\./server/|@/server/)<module>['"]` and extend each mock factory in the same edit cycle.

## Test Coverage

Pinned in `apps/web-platform/test/agent-prefill-guard.test.ts` (7 scenarios): short-circuit on undefined, drift-guard on `dir: workspacePath`, user-terminated pass-through, assistant-terminated drop, empty-history distinct op, probe-failure sanitization (preserves `name` and `code`, scrubs absolute paths), feature-tag forwarding for cc/legacy distinction.

Integration coverage: `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` (helper invocation + result threading); `agent-runner` legacy invocation indirectly covered by `session-resume-fallback.test.ts` and `agent-runner-query-options.test.ts`.

## Cross-references

- PR #3263 — landed
- Issue #3250 — primary cc-path bug report (closed by #3263 once cc wiring lands; legacy fold-in covers production exposure today)
- Issue #3266 — narrowed to cc-path `conversations.session_id` reader+writer wiring (Approach C, scope-out: architectural-pivot)
- Issue #3269 — context-reset signal to model + user (scope-out: contested-design, second-reviewer co-signed)
- Issue #3270 — separate cleanup: remove `FLAG_CC_SOLEUR_GO` (always-on)
- Plan: `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §"Phase 3" updated post-review
- Helper: `apps/web-platform/server/agent-prefill-guard.ts`
- Related learning: `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — this session is another instance of the multi-agent review pattern catching a class of bug that unit tests cannot reach (production-effective dormancy of a guard whose tests pass)
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — observability contract this guard satisfies
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — single-user-incident threshold satisfied by the legacy fold-in
