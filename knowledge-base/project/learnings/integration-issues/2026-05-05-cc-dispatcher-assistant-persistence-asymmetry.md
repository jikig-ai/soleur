---
module: cc-chat / cc-dispatcher
date: 2026-05-05
problem_type: integration_issue
component: nextjs_route
symptoms:
  - 'Continue thread on KB doc shows routing chip ("Soleur Concierge is routing to the right experts...") instead of the prior assistant reply'
  - "Resumed cc-chat thread returns user-only message history"
  - "isClassifying flips true on already-answered conversations"
root_cause: missing_persistence_in_parallel_runner_path
severity: high
tags: [cc-chat, persistence-asymmetry, parallel-runner-paths, supabase-messages, isClassifying-gate]
related_prs: ["#3286", "#3251", "#3276", "#3263", "#3267", "#3237", "#3254"]
synced_to: [work]
---

# Persistence asymmetry between parallel runner paths surfaces as UI-only bug on resume

## Problem

Clicking "Continue thread" on a KB document with an already-answered cc-chat thread caused the right-sidebar to:

1. Open with the "Continuing from <date>" banner
2. Render the user's prior message
3. NOT render the assistant's prior reply — instead, the routing chip ("Soleur Concierge is routing to the right experts...") re-rendered as if the question were unanswered

The server was not actually re-running routing on resume — `ws-handler.ts:755-787` confirms `session_resumed` does not dispatch the agent. The chip was a lie produced by `chat-surface.tsx:368-372`'s `isClassifying` predicate evaluating true on a user-only message snapshot returned by `api-messages.ts`.

## Investigation

### Red herrings traced and rejected

| Suspect | Verification | Verdict |
| --- | --- | --- |
| PR #3251 introduced the regression | `git show b6bed202` — only renamed chip text and extracted `RoutedLeadersStrip`; render-condition unchanged | Reject. PR #3251 surfaced a latent bug by making the chip identifiable |
| `api-messages.ts` filters role on hydration | `api-messages.ts:76-82` selects all roles ordered by `created_at` | Reject |
| Race between `historyLoading` and `isClassifying` | Possible secondary surface but not load-bearing — even with perfect timing, the chip would render indefinitely if assistant rows are not in the DB | Real but not primary |

### Load-bearing root cause (verified via grep)

`grep -n "saveMessage\|messages.*insert" apps/web-platform/server/cc-dispatcher.ts` returned ONE call site (line 763, role: `"user"` only).

`grep -n "saveMessage" apps/web-platform/server/agent-runner.ts` returned TWO call sites: line 1346 (user role) AND line 1079 (`await saveMessage(conversationId, "assistant", fullText, ...)`).

The cc-dispatcher / soleur-go-runner path persisted ONLY the user message per turn. Assistant text streamed via `onText` WS events was treated as transient (the SDK's session-id resume mechanism was assumed to own transcript replay — but resume goes through `api-messages.ts`, not the SDK session, when the user closes and re-opens the doc tab). On resume, the DB returned user-only history → `isClassifying === true` → chip rendered on every cc-chat thread that was answered before tab close.

## Solution

### Server: persist assistant text at per-turn boundary

Inside `dispatchSoleurGo` in `apps/web-platform/server/cc-dispatcher.ts`, accumulate per-turn assistant text via `onText` and persist it at `onTextTurnEnd` — mirror of `agent-runner.ts:1079`:

```ts
let accumulatedAssistantText = "";

async function saveAssistantMessage(): Promise<void> {
  // Snapshot-then-reset must precede `await` so a turn N+1 onText cannot
  // mutate fullText while this insert is in flight.
  const fullText = accumulatedAssistantText;
  accumulatedAssistantText = "";
  if (!fullText) return; // skip empty (tool-only) turns

  const { error } = await supabase().from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role: "assistant",
    content: fullText,
    tool_calls: null,
    leader_id: CC_ROUTER_LEADER_ID,
  });
  if (error) {
    // Mirror via existing per-(userId, errorClass) 5-min debounce
    // — undebounced per-turn mirrors flood Sentry on misconfigured RLS.
    mirrorWithDebounce(
      error,
      { feature: "cc-dispatcher", op: "save-assistant-message-failed",
        extra: { userId, conversationId, length: fullText.length } },
      userId,
      "save-assistant-message-failed",
    );
  }
}

const events: DispatchEvents = {
  onText: (text) => { accumulatedAssistantText += text; sendToClient(...); },
  onTextTurnEnd: () => {
    void saveAssistantMessage(); // fire-and-forget — user already saw stream
    sendToClient(userId, { type: "stream_end", leaderId: CC_ROUTER_LEADER_ID });
  },
  // ...
};
```

### UI: defense-in-depth gate

In `apps/web-platform/components/chat/chat-surface.tsx:368-381`, widen `isClassifying` so legacy user-only conversations (pre-#3286) and in-flight history fetches don't resurrect the false-routing chip:

```ts
const isClassifying =
  hasUserMessage && !hasAssistantMessage &&
  routeSource === null && workflow.state === "idle" &&
  !historyLoading &&        // never during hydration round-trip
  resumedFrom === null;     // never on a confirmed resume — chip lies regardless of cause
```

## Key Insight

**When two parallel runner paths exist in the same codebase (here `agent-runner.ts` for full-leader sessions and `cc-dispatcher.ts` for the cc-router fast path), persistence asymmetry between them is a silent class of bugs that surfaces only via the resume code path.** Unit tests on each path pass independently; the bug only manifests when the consumer (here `api-messages.ts` hydration → reducer state → `chat-surface.tsx isClassifying`) reads what was supposed to have been written.

The work-time grep that prevents this:

```bash
# In the new path:
grep -n "saveMessage\|messages.*insert" apps/web-platform/server/<new-runner>.ts
# In the reference path:
grep -n "saveMessage" apps/web-platform/server/<reference-runner>.ts
```

If the new path has only one role's persistence call and the reference has both, the asymmetry will land as a UI bug downstream. The plan for PR #3286 foreshadowed this exact insight at its line 348 — recording it here as the canonical artifact.

## Prevention

1. **Persistence-symmetry grep at plan time.** When planning any feature that extends or mirrors a parallel runner / dispatcher / writer path, run the dual grep above and require role-count parity. If the reference path persists user + assistant + result and the new path persists only user, that's the bug class — fix in the same PR or document the deliberate divergence with rationale.

2. **Sentry-mirror debounce sweep at review time.** When adding a `reportSilentFallback` / `Sentry.captureException` call inside a per-turn or per-request callback, grep the surrounding module for an existing debounce primitive (here `mirrorWithDebounce`) and route through it. An undebounced per-turn mirror at production scale → ~1000 events/hr per misconfigured user. The test that catches this: a `mockResolvedValueOnce` failure path + an assertion that `mockReportSilentFallback` was called exactly once (not N times for N turns) when the same error class repeats.

3. **Resume-path UI gates accept "data was never written" as a valid state.** A UI predicate like `isClassifying = hasUserMessage && !hasAssistantMessage` assumes the absence of an assistant row means routing is genuinely pending. On resume that assumption breaks for any conversation that pre-dates the persistence fix. Defense-in-depth: gate any "still routing" UI on `!resumedFrom` so resumed threads never re-render the chip regardless of why `hasAssistantMessage` is false.

4. **Test the AND truth-table corners on multi-clause predicates.** A new gate of the form `existing && A && B` needs at least three test cases: A-suppress (B normal), B-suppress (A normal), and BOTH-suppress. Two cases (one per leg) cannot distinguish AND from OR; a regression to `||` would still pass per-leg tests. T5d in `chat-surface-resume-classifying.test.tsx` covers this corner.

## Session Errors

1. **Bash CWD non-persistence — `./node_modules/.bin/vitest` not found.** First call to vitest after a prior `cd` chain failed because the Bash tool does NOT persist CWD across calls. **Recovery:** prefix with `cd <worktree-abs-path>/apps/web-platform && ./node_modules/.bin/vitest`. **Prevention:** Already covered by AGENTS.md learning at "When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call." Discoverable via clear error message — no new rule needed.

2. **`git add apps/web-platform/...` from non-worktree CWD.** Same root cause as #1: a prior `cd apps/web-platform &&` left subsequent calls running from worktree root, so `apps/web-platform/server/...` was interpreted as `apps/web-platform/apps/web-platform/...`. **Recovery:** chain `cd <worktree> && git add ...` in one call. **Prevention:** same rule as #1.

## References

- PR #3286 — this fix.
- Scope-out filed: #3289 — pre-existing missing `conversation_messages` MCP tool (agent-parity gap exposed but not introduced by this PR).
- PR #3237 — `fix(kb-chat): hydrate prior messages on resume` — first hydration fix; established the `historyLoading`/`resumedFrom` guard pattern this PR extends.
- PR #3251 / #3276 — `fix(cc-chat): keep Soleur Concierge visible in routing panel` — surfaced this regression by making the chip text more identifiable.
- PR #3263 — `fix(cc-concierge): drop resume when persisted session ends with assistant` — adjacent fix on the same dispatch path; introduced the `agent-prefill-guard.ts` shared helper pattern.
- PR #3267 — `fix(kb-chat): close H1/H5 observability gaps for continuing-from regression` — the Sentry breadcrumb (`history-fetch-success-empty`) that quiets after this fix lands is the post-deploy success signal.
- `apps/web-platform/server/agent-runner.ts:1076-1080` — canonical per-turn assistant persistence pattern this fix mirrors.
- `apps/web-platform/server/cc-dispatcher.ts:756-761` — the comment that documented the design ("SDK's session-id resume mechanism still owns transcript replay") and silently dropped the `api-messages.ts` hydration use case.
