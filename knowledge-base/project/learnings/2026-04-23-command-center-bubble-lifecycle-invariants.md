---
date: 2026-04-23
category: integration-issues
module: web-platform
component: command-center
tags: [websocket, state-machine, mcp-tools, agent-native, stream-lifecycle, github-app]
pr: 2843
related:
  - 2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md
  - 2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md
  - integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md
  - service-tool-registration-scope-guard-20260410.md
---

# Command Center bubble-lifecycle invariants + agent-native GitHub read tools

## Problem

Two defects surfaced in the web-platform Command Center during a session asking the agent to "resume work on issue 2831":

1. **Stuck orange "Working" badge** on earlier tool-progress bubbles after the leader posted its final text. The bubbles showing "Running: python ...", "Finding knowledge-base/**/*2831*...", and "Working..." never transitioned to the done state. They stayed visually stuck with the animated amber dot.

2. **`gh` CLI unavailable** in the remote agent sandbox. The agent tried `gh issue view 2831` and hit ENOENT. It correctly self-described the gap: *"platform should expose a `github_read_issue` tool alongside the existing `github_read_ci_status` and `github_read_workflow_logs` ones."*

## Root cause

**Bug 1 was a two-part invariant violation:**

- `chat-state-machine.ts` `review_gate` case cleared `activeStreams` via `new Map()` without transitioning the bubbles' `state` field. Peer-leader bubbles (e.g., CTO while CPO is still streaming a `review_gate`) leaked "thinking" / "tool_use" / "streaming" state into a stuck "Working" badge the client could not clear. Pre-existed the single-bubble design (latent since #2209).
- `agent-runner.ts` `startAgentSession` only emitted `stream_end` inside the `result` branch. If the SDK iterator threw mid-stream, `updateConversationStatus` failed after the final text landed, or the controller aborted with a `tool_use` as the last event, the bubble never transitioned to done.

**Bug 2 was a platform capability gap, not a runtime config error.** The sandbox is a minimal Node/Next.js runtime — `gh` isn't installed and shouldn't be, given agent-native architecture principles. The UI reads issues/PRs via Supabase + GitHub REST; the agent should too, via in-process MCP tools (the pattern already established by `github_read_ci_status` + `github_read_workflow_logs` in PR #1927).

## Solution

**Bug 1 — state machine + server-side emission:**

1. `chat-state-machine.ts` `review_gate` now iterates `activeStreams.values()` and transitions every bubble whose `state` is "thinking" / "tool_use" / "streaming" to "done" BEFORE clearing the map. Done/error bubbles are untouched.
2. `agent-runner.ts` declares `streamStartSent` and `streamEndSent` locals before the try block. The success-branch emission, resume-error emission, and a new finally-block fallback all guard with `if (streamStartSent && !streamEndSent)`. The finally block wraps `sendToClient` in try/catch so a WebSocket-write failure can't skip `activeSessions.delete(key)`.

**Bug 2 — agent-native in-process tools:**

1. New `apps/web-platform/server/github-read-tools.ts` with four REST wrappers: `readIssue`, `readIssueComments`, `readPullRequest`, `listPullRequestComments`. Each uses `githubApiGet` (installation-token auth) and returns a narrowed shape (10 KB body truncation on issues/PRs, 4 KB on comments, `per_page` clamped at 50).
2. `apps/web-platform/server/github-tools.ts` adds four `tool(...)` definitions (`github_read_issue`, `github_read_issue_comments`, `github_read_pr`, `github_list_pr_comments`) — all auto-approve, nested inside the `installationId && repoUrl` guard. A shared `wrapToolHandler` helper dedups the try/JSON.stringify/catch scaffold across all nine tools in the file.
3. `tool-tiers.ts` adds four `"auto-approve"` entries; default is `gated` (fail-closed).
4. System prompt gains a `## GitHub read access` block inside the `owner && repo` guard announcing the tools and adding an issue-vs-PR disambiguation hint ("call `github_read_pr` first — 404s for non-PRs").

## Key insight

**Capability gaps surface at the exact moment the agent tries to use a missing primitive.** When the agent self-identifies a gap ("platform should expose a `github_read_issue` tool"), that is an agent-native parity signal — not a workaround to route around. The fix is to add the primitive at the same conceptual layer as the existing tools, with the same auth path, tier, and response-narrowing discipline. Adding `gh` to the Dockerfile would have worked but would have bypassed the agent-native architecture (one workflow system, not two).

**State-transition invariants must be enforced at the reducer's exit boundary, not the caller.** The `review_gate` bug existed because a reducer branch performed a state-affecting operation (clearing activeStreams) without discharging the state invariants it was implicitly responsible for (no leader stays in an in-flight state). The fix is a small iteration inside the same branch; the architectural lesson is that any time a reducer branch touches `activeStreams`, the companion `state` field on each referenced message must be considered in the same edit.

**Stream-lifecycle idempotency needs defense-in-depth across every exit path.** Success-branch emission, resume-error emission, and finally-block fallback all emit `stream_end`, all guarded by the same boolean. Each site handles a distinct exit: happy path, typed re-throw, catch-all exception. Removing the redundancy ("just use finally") was rejected because the ordering of `stream_end` relative to `session_ended` matters for client-side bubble cleanup in multi-leader mode (#2428).

## Session Errors

1. **Initial Explore agent's bug-mapping was shallow and wrong.** First `Agent(Explore)` reported Bug 1 as "missing `tool_progress` variant + per-`tool_use_id` tracking in ws-client.ts:103-158". The plan subagent's Reconciliation table caught it — codebase has ONE bubble per leader with a state machine. Implementing the Explore framing verbatim would have shipped the wrong fix. Recovery: plan subagent pushed back. **Prevention:** for Explore tasks investigating state-transition bugs, explicitly instruct the agent to "trace the actual state transitions in the reducer and report the state machine's terminal invariants," not "find where X is referenced."

2. **Line-range fabrication in scoping prompt.** `/one-shot` args cited `agent-runner.ts:353-399` as the message loop; actual loop is lines 843-964 and already handles `stream_event`, `tool_use`, etc. **Prevention:** verify line-range citations with `wc -l` and `grep -n` before embedding them in scoping prompts. Already covered by `hr-when-a-plan-specifies-relative-paths-e-g` in spirit; extend to line-range citations as well.

3. **SDK event semantics hallucinated.** Explore claimed `SDKToolProgressMessage` is a completion signal. It is a heartbeat (`elapsed_time_seconds`); completion comes via `type: 'user'` with `tool_use_result` or `SDKToolUseSummaryMessage`. **Prevention:** for any SDK event-handling bug, require Explore to cross-reference the installed SDK's type definitions (`.d.ts`) before prescribing the fix shape.

4. **tsc type errors in first test-file draft.** `fetchSpy.mock.calls[0][0] as string` had tuple-length-0 and undefined-to-string conversion errors. **Prevention:** run `tsc --noEmit` incrementally when writing typed-mock helpers — don't accumulate 50+ lines before verifying.

5. **`as const` on test event builders caused readonly-vs-mutable mismatch** with `StreamEvent` parameter typing. Five call sites failed tsc. **Prevention:** in test factories, use explicit return-type annotations instead of `as const`. Readonly tuples do NOT widen to mutable arrays the consumer expects.

6. **`as any` casts copied from pre-existing tests.** New review_gate tests used `as any` on event objects — reviewer flagged as defeating the `StreamEvent` union-widening guard. **Prevention:** introduce typed event builders at the top of new describe blocks by default; do not pattern-match existing `as any` from sibling tests — that propagates tech debt into the fresh code.

## Prevention

- **Reducer branches that touch `activeStreams` must sweep companion message state.** Any future branch in `applyStreamEvent` that writes to `activeStreams` must first review the `MessageState` of every index the map references and transition transitional states to a terminal one.
- **Every new MCP tool goes through the full review matrix:** auth path (installation token vs PAT), tier (auto-approve vs gated), scope guard (nested inside the right capability gate), response narrowing (body truncation, avatar-URL filter), input validation (`z.number().int().positive()` not bare `z.number()`).
- **Silent fallbacks surface via `reportSilentFallback`.** Any code path that catches an error and returns 4xx/5xx OR continues with fallback data must mirror the pino log to Sentry (AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`). Remediated two pre-existing sites in this PR (cost-tracking RPC, `defaultBranch` 404) and one new site (`listPullRequestComments` partial failure) — in the same file the PR was already touching.
- **Review agents catch the class that tests miss.** The 10-agent review surfaced 14 P2 findings across security (Zod tightening), observability (silent-fallback violations), and data-integrity (partial-failure semantics) — none of which would have shown up as failing tests. Multi-agent review is load-bearing.

## Cross-references

- PR #2843 (this change)
- #2217 closed via #2765 (pure-reducer extraction with companion state migration — precondition for this fix)
- #2428 (multi-leader session lifecycle — established `skipSessionEnded` pattern preserved by this fix)
- #1925, #1927, #1956 (established `soleur_platform` in-process MCP pattern extended by this fix)
- `knowledge-base/project/learnings/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`
- `knowledge-base/project/learnings/2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`
- `knowledge-base/project/learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md`
- `knowledge-base/project/learnings/service-tool-registration-scope-guard-20260410.md`
- `knowledge-base/project/learnings/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`
