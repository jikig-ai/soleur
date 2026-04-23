# fix: Command Center tool-progress stuck bubble + agent-native GitHub reads

**Date:** 2026-04-23
**Branch:** feat-one-shot-command-center-fixes
**Worktree:** .worktrees/feat-one-shot-command-center-fixes
**Draft PR:** #2843
**Labels:** type/bug, priority/p1-high, domain/engineering, semver:minor
**Semver rationale:** minor — adds four new agent-visible tools (new capability surface). If we decide NOT to expose new tools (only fix Bug 1), downgrade to patch.

## Enhancement Summary

**Deepened on:** 2026-04-23
**Lenses applied:** architecture-strategist, code-simplicity-reviewer, test-design-reviewer, agent-native-reviewer, security-sentinel, pattern-recognition-specialist, learnings-researcher
**Learnings cross-referenced:** 6 directly applicable, noted inline
**Context7 / SDK source:** verified against `@anthropic-ai/claude-agent-sdk@0.2.85` (installed)

### Key improvements from deepen pass

1. **Preferred fix path is `useReducer` state-shape consolidation, not a new `streamEndSent` boolean.** Per learning `2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md` (#2217 is still open), the right shape is to migrate `activeStreams` into the reducer state and make `stream_end` a reducer-driven transition with an enforced post-condition "every leader in `activeStreams` must be transitioned to `done` before the map is cleared." That eliminates the exception-path race at the type level rather than the runtime level. Plan now presents BOTH options with explicit trade-offs.
2. **`_exhaustive: never` grep is now a pre-Phase-0 gate.** Per learning `discriminated-union-exhaustive-switch-miss-20260410.md`, any WSMessage change (even the rejection of a new variant) must grep exhaustive switches in `ws-handler.ts`. If a `tool_use_id`-bearing variant is ever added, this grep is load-bearing.
3. **RAF / test-timer sweep explicitly scoped out.** The fix does NOT introduce rAF or microtask batching, so `cq-raf-batching-sweep-test-helpers` does not apply — noted explicitly so the work-phase implementer does not pre-emptively rewrite test helpers.
4. **Agent-native parity audit.** Adding `github_read_issue` closes a UI→agent capability gap. Plan now enumerates the full UI surface of GitHub-touching actions (issue view, PR view, comment read, CI status read, workflow logs read) and maps each to a tool — same pattern as learning `PR #2817 conversations_list` oversight.
5. **Test-design uplift — Farley "First" + "Necessary" gate.** Phase 1 tests are pinned as RED-first (First), target exactly one behavior per test (Atomic), and avoid over-testing the happy path that's already covered (Necessary). See new "Test Design Review" subsection.
6. **Response-narrowing defense.** The four new GitHub read tools truncate user-provided `body` fields server-side; plan spells out a 10 KB cap with explicit `"…(truncated, use html_url)"` marker and asserts the cap in unit tests (prevents a single long issue body from blowing the agent's context window).
7. **Token-budget accounting.** The new `## GitHub read access` system-prompt block is budgeted at ≤80 tokens (measured against the ~120-token KB-share precedent; plan-side cap documented).

### New considerations discovered

- **StrictMode replay + companion-state mutation already surfaced in the current `chat-state-machine.ts` call site.** The existing `chatReducer` is already pure and `useReducer`-based (ws-client.ts:109), so part of follow-up #2217 has shipped — but `review_gate`'s `new Map()` clear is the last non-transitional shortcut in the reducer. Phase 2 fix preserves the reducer's purity.
- **Review-agent pile-on precedent.** When 4+ reviewers flag the same pattern (as in #2209 for the pure-reducer extraction), the fix should be promoted above the immediate bug. Plan now gives the `useReducer` full migration explicit upgrade-path language so the next touch of this file closes #2217 instead of layering patches.
- **`_exhaustive: never` check is NOT currently in ws-handler for the server emitter side.** The client's `ws-client.ts` uses a plain `switch` with `default: break` (ws-client.ts:438) — adding a new `WSMessage` variant will NOT compile-fail there. Plan now calls this out as a pre-existing latent hazard that the Bug 1 fix does NOT make worse, but that the three follow-up feature issues (which may add new message types) must address.

## Overview

Two defects in the `apps/web-platform` Command Center surfaced during a session asking the agent to "resume work on issue 2831":

1. **Stuck orange "Working" badge on earlier tool-progress bubbles.** After the leader's final text lands, the earlier bubbles showing "Running: python …", "Finding knowledge-base/**/*2831*…", and "Working..." never transition to the done state. They stay visually stuck with the amber animated dot and "Working" chip.
2. **`gh` CLI unavailable in the runner sandbox.** The agent tried `gh issue view 2831` and hit ENOENT. It then correctly self-described the gap: "platform should expose a `github_read_issue` tool alongside the existing `github_read_ci_status` and `github_read_workflow_logs` ones."

This plan fixes (1) via a proper single-bubble state model (stream_end is the authoritative terminal signal already — the UX bug is different from the issue body's framing) and closes (2) by extending the existing GitHub App-backed in-process tool family with four read-only tools.

After both fixes merge, file three deferral/follow-up issues (see Phase 5).

## Research Reconciliation — Spec vs. Codebase

The issue body prescribes specific fixes. Some of its claims diverged from the actual codebase. Reconciling here prevents the plan from inheriting the issue's assumptions verbatim.

| Issue-body claim | Codebase reality | Plan response |
|---|---|---|
| "`agent-runner.ts:353-399` message loop only handles `assistant` and `result`" | Lines 843-963 also handle `stream_event` (partials) and all other SDK message types fall through silently. The loop already emits `tool_use` events to the client (line 875-887). | Correct the file-line reference. Proceed with the underlying intent: tool-completion signals are dropped. |
| "Agent SDK `tool_progress` events are dropped" | `SDKToolProgressMessage` is a real SDK type (`tool_progress`, carries `tool_use_id`, `tool_name`, `elapsed_time_seconds`) but it is a *heartbeat*, NOT a completion signal. Completion comes via `type: 'user'` messages with `tool_use_result` set, and/or `SDKToolUseSummaryMessage`. | Plan does NOT forward `tool_progress` to the WS client as a completion signal. Uses `type: 'user'` + `tool_use_result` as the authoritative done signal (see Phase 2 mechanics). |
| "bubbles stay stuck with orange Working badge" | Each leader has ONE bubble whose `state` transitions `thinking → tool_use → streaming → done` (see `chat-state-machine.ts:applyStreamEvent`). There is no per-tool-call bubble. Each `tool_use` event REPLACES `toolLabel` and appends to `toolsUsed[]`; the next `stream` event transitions state back to `streaming`. `stream_end` sets `done`. | The actual UX bug is: when the final turn has tool uses but NO subsequent text stream (e.g., the agent finished with only tool calls), the bubble stays in `tool_use` state because no `stream` event fires to flip it back. `stream_end` handler already sets `state: "done"` (line 175) — so the bug must be that `stream_end` is NOT arriving for these bubbles, OR multiple parallel leaders with different lifecycles leave one bubble orphaned. See Phase 1 root-cause investigation. |
| "WSMessage union has no `tool_progress` variant" | True. | Will NOT add one — the server already emits `tool_use` (label-only, no `tool_use_id`) and the real fix lives server-side (ensure terminal events fire per bubble). |
| "`ws-client.ts:103-158` has no handler to update bubble status by `tool_use_id`" | There is no `tool_use_id` anywhere in the client protocol. Each bubble is keyed by `leaderId` via `activeStreams: Map<leaderId, messageIndex>`. Per-tool tracking is deliberately absent — `toolsUsed: string[]` is an ordered list of labels with no per-tool status. | Do NOT add per-tool-use-id tracking. Fix the leader-scoped terminal transition (Phase 2). If per-tool status chips are desired, file a separate follow-up issue (see Phase 5 #3). |
| "agent flagged: `github_read_ci_status` and `github_read_workflow_logs` exist" | Confirmed via `apps/web-platform/server/github-tools.ts:79-125`. Both are registered in-process MCP tools under the `soleur_platform` server, auth'd via GitHub App installation token. | Extend the same module, same auth path, same tier map (`tool-tiers.ts`). NOT a hallucination. |
| "Use official GitHub remote MCP server (<https://api.githubcopilot.com/mcp/>) if it supports OAuth-less PAT auth" | The endpoint exists and accepts Bearer (verified: `curl -I` returned 401 with `WWW-Authenticate: Bearer` realm). But using a PAT would duplicate the auth surface (GitHub App installation already scoped to the user's connected repo) and introduce a second cred path in Doppler that currently does NOT exist (`doppler secrets -p soleur -c dev` shows only `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`). | Use in-process tools backed by the existing GitHub App installation token — same auth path as `github_read_ci_status`. Reject the remote-MCP-with-PAT alternative in "Alternatives Considered" (Phase 6). |
| "Token source: Doppler — check existing GitHub token secrets first" | Doppler has `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` in both `dev` and `prd`. No user-PAT secret exists. | Reuse the App installation flow. No new Doppler secrets. No `agent-env.ts` allowlist change needed (the App auth runs in the Next.js process, not forwarded to the SDK subprocess). |

## Hypotheses

**Bug 1 — why bubbles stay stuck (prioritized):**

1. **`stream_end` is not emitted after a turn that ends purely on tool uses.** The server-side loop (agent-runner.ts line 890) only emits `stream_end` inside the `result` branch. If the Agent SDK emits a `result` message but the `assistant` content for the final turn has NO `text` block (only `tool_use` blocks), the bubble's last visible state is `tool_use` and `stream_end` should still fire — but if the `result` branch early-exits or another leader's `stream_end` clobbers the active-stream map, the bubble leaks.
2. **Parallel leaders clobber `activeStreams` entries.** When both CPO and CTO are dispatched, the server emits `stream_start` for each with distinct `leaderId`. `activeStreams` is keyed by `leaderId` so they should not collide. But `chat-state-machine.ts:applyTimeout` and the `review_gate` branch call `new Map()` (line 199) — clearing ALL active streams at once — which drops the partner leader's entry without setting its bubble to `done`.
3. **Server emits `tool_use` for a bubble that never got `stream_start`.** If a leader's very first event is `tool_use` (skipping the explicit `stream_start`), the fallback branch in `applyStreamEvent` does not create a new bubble for `tool_use` — so no `activeStreams` entry exists and subsequent `stream_end` is a no-op on line 168.
4. **`skipSessionEnded` path is asymmetric.** Multi-leader dispatch passes `skipSessionEnded=true` to each leader, but each leader still sends its own `stream_end` (line 930). That's correct. But if a leader's `result` branch throws between line 890 and 930, the `stream_end` never fires and the bubble is stuck.

The fix must address 1, 2, and 4 with defense in depth. Hypothesis 3 is less likely given the server always emits `stream_start` before iterating (line 841).

**Bug 2 — integration shape:** Already decided (in-process tools via GitHub App). See Reconciliation.

## Goals / Non-Goals

**Goals:**

- Bug 1: Every assistant bubble in a finished turn reaches `state === "done"` within the normal turn lifecycle (no 45s timeout required).
- Bug 2: Add four in-process MCP tools: `github_read_issue`, `github_read_issue_comments`, `github_read_pr`, `github_list_pr_comments`. All auto-approve (read-only).
- Preserve exact user-visible behavior for the happy-path (single leader, text-final turns) — no regressions on existing bubble rendering.

**Non-Goals:**

- Per-tool-call bubble splitting or per-tool-use-id status chips. (File as follow-up.)
- Installing `gh` CLI in the runner Dockerfile. (File as `deferred-scope-out`.)
- Changing auto-routing behavior (double-leader dispatch). (File as `type/feature`.)
- Refactoring Command Center to route through `/soleur:go`. (File as `type/feature`.)
- Migrating to the official GitHub remote MCP server — explicitly rejected.

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` — harden terminal-event emission. Ensure `stream_end` fires for every bubble that got a `stream_start`, even on exceptions. Move the `stream_end` emission to a `finally`-adjacent block so it cannot be skipped when `result` branch throws before line 930.
- `apps/web-platform/lib/chat-state-machine.ts` — fix `review_gate` branch (line 199) that clears ALL active streams via `new Map()`. Preserve active streams for leaders that did not receive `stream_end` yet (set their bubble state to `done` explicitly, then drop from the map). Ditto `applyTimeout` does NOT clobber peer streams (it already scopes by leaderId — verify).
- `apps/web-platform/server/github-tools.ts` — add four new `tool(...)` definitions: `github_read_issue`, `github_read_issue_comments`, `github_read_pr`, `github_list_pr_comments`. Extend `toolNames` array.
- `apps/web-platform/server/ci-tools.ts` (or create `apps/web-platform/server/github-read-tools.ts` sibling) — add REST wrappers for `GET /repos/:owner/:repo/issues/:issue_number`, `GET /repos/:owner/:repo/issues/:issue_number/comments`, `GET /repos/:owner/:repo/pulls/:pull_number`, `GET /repos/:owner/:repo/pulls/:pull_number/comments`. Reuse `githubApiGet` from `github-api.ts`.
- `apps/web-platform/server/tool-tiers.ts` — add four new `"auto-approve"` entries to `TOOL_TIER_MAP` for the new tool names.
- `apps/web-platform/test/chat-state-machine.test.ts` — new failing test(s) that assert terminal transitions for the buggy scenarios (see Phase 1 TDD).

## Files to Create

- `apps/web-platform/test/agent-runner-stream-end.test.ts` — new file. Simulates the multi-leader turn lifecycle with mocked Agent SDK iterators and asserts `stream_end` fires for every `stream_start` regardless of where the loop exits. May be deferred into an existing agent-runner test file if one exists with similar mocks.
- `apps/web-platform/server/github-read-tools.ts` — optional new module (alternative: extend `ci-tools.ts`). Holds the four REST wrappers. Keeps `ci-tools.ts` focused on CI.

## Implementation Phases

### Phase 1 — RED: Failing tests for terminal transitions (Bug 1)

Per `cq-write-failing-tests-before`, TDD is required.

1. **Test 1 — parallel-leader stream_end isolation.** Dispatch `stream_start(cpo)`, `stream_start(cto)`, `tool_use(cpo, "Running: gh issue view 2831...")`, `stream_end(cpo)`. Assert the CPO bubble is `done` AND the CTO bubble is STILL `tool_use` (or `thinking` — NOT prematurely cleared). Current behavior: passes if `stream_end` scopes by leaderId only. Verify this case is covered — if yes, document it and move on. If no, fix.
2. **Test 2 — review_gate preserves peer bubbles.** Dispatch `stream_start(cpo)`, `stream_start(cto)`, `tool_use(cpo, "Reading foo.md...")`, `review_gate(gateId=g1)`. Assert BOTH CPO and CTO bubbles transition to `done` (or an intermediate state that is NOT stuck `tool_use`). Current `applyStreamEvent`'s `review_gate` branch does `new Map()` and does NOT update bubble states — so peer leaders' bubbles leak. **Expected RED.**
3. **Test 3 — tool-final turn.** Dispatch `stream_start(cpo)`, `tool_use(cpo, "Running: gh issue view...")`, `stream_end(cpo)`. Assert bubble is `done`. Existing stream_end handler already sets `done` — should pass. Used as regression sentinel.
4. **Test 4 (integration, optional) — agent-runner exception path.** Mock SDK iterator to throw after the first `tool_use` yield. Assert `stream_end` is still emitted (requires the Phase 2 fix to pass).

Run tests. Expect 2 (and possibly 4) to fail. Capture `vitest` output as the RED baseline.

**Test runner note (`cq-in-worktrees-run-vitest-via-node-node`):** From the worktree, run `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/agent-runner-stream-end.test.ts`. Do NOT use `npx vitest`.

### Phase 2 — GREEN: fix `review_gate` branch and harden stream_end

#### Option A (preferred for this scope): minimal patch

1. **`chat-state-machine.ts:review_gate` branch.** Replace `activeStreams: new Map()` with: iterate the existing map, set each leader's bubble `state: "done"` (or a new `"interrupted"` state — defer unless needed), then clear. Keep `timerAction: "clear_all"`.
2. **`agent-runner.ts` stream_end hardening.** Today, `stream_end` fires inside the `result` branch (line 930). Restructure: track `streamStartSent: boolean` and `streamEndSent: boolean` local to the session. Move `sendToClient(..., "stream_end", ...)` into a `finally`-style block that runs after the `for await` loop exits — whether by `result`, by `controller.signal.aborted`, or by an exception caught below. Guard with `if (streamStartSent && !streamEndSent)`.
3. **Re-run the failing tests.** They must pass. Do NOT edit the passing tests.

#### Option B (larger refactor — evaluate at work time)

Close follow-up issue #2217 simultaneously by promoting `activeStreams` from a `useRef` companion into the reducer's state (it already is — see below). Then collapse the `review_gate` and exception-path fixes into a single reducer-level invariant: **"before clearing `activeStreams`, every leader in it must transition to `done`."** Make this a runtime `assert` (throws in dev, silently transitions in prod) on the reducer's output.

**Current state check:** The learning `2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md` describes the refactor that's still open as #2217. Per `ws-client.ts:109`, `chatReducer` already combines `messages + activeStreams + pendingTimerAction` in a single `useReducer` — so #2217 appears to have landed as a successor. The Option B work reduces to: (a) add the invariant check, (b) delete the `new Map()` shortcut. Verify state of #2217 with `gh issue view 2217 --json state` during work-phase Phase 0.

**Decision criterion:** If #2217 is CLOSED, ship Option A. If OPEN and the reducer has regressed to ref-based companion state, ship Option B and `Closes #2217`.

### Research Insights (Phase 2)

**Best practices (from learnings):**

- Reducers that return an action-intent field (like `timerAction`) MUST be consumed at the call site, otherwise drift emerges (learning `2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`). Current code already consumes `pendingTimerAction` via `useEffect` — preserve this.
- When adding a new variant to a discriminated union (or when changing how existing variants are dispatched), grep `rg "const _exhaustive: never"` and update every occurrence (learning `discriminated-union-exhaustive-switch-miss-20260410.md`). This plan does NOT add a new variant, but the check is still required if Option B introduces any new intermediate event type.
- WebSocket streaming protocols: replace-not-append semantics only work if every `content` field is cumulative. Don't convert partial-snapshot events into delta events downstream (learning `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`).

**Implementation details — `chat-state-machine.ts:review_gate` fix:**

```ts
case "review_gate": {
  // Transition any bubble still mid-turn to "done" before clearing.
  // Leaking "tool_use" / "streaming" into an unclearable state is the
  // root cause of the stuck orange "Working" badge. See #2843.
  const updated = prev.slice();
  for (const [, idx] of activeStreams) {
    if (idx >= updated.length) continue;
    const m = updated[idx];
    if (m.state === "thinking" || m.state === "tool_use" || m.state === "streaming") {
      updated[idx] = { ...m, state: "done" };
    }
  }
  const gateMsg: ChatMessage = { /* unchanged */ };
  return {
    messages: [...updated, gateMsg],
    activeStreams: new Map(),
    timerAction: { type: "clear_all" },
  };
}
```

**Implementation details — `agent-runner.ts` stream_end hardening:**

```ts
// Before the for-await-of loop:
let streamStartSent = false;
let streamEndSent = false;
sendToClient(userId, { type: "stream_start", leaderId: streamLeaderId, source: routeSource });
streamStartSent = true;

// After the loop, before the catch block exits — place at the inner
// `try`'s END, not in `finally`, so the success path doesn't double-emit:
if (streamStartSent && !streamEndSent) {
  sendToClient(userId, { type: "stream_end", leaderId: streamLeaderId });
  streamEndSent = true;
}

// Inside the existing `result` branch on line 930, replace the bare sendToClient
// with the same guarded form (so success-path emission stays on the existing
// line but is idempotent):
if (!streamEndSent) {
  sendToClient(userId, { type: "stream_end", leaderId: streamLeaderId });
  streamEndSent = true;
}

// Inside the catch (err) branch, also guard:
if (streamStartSent && !streamEndSent) {
  sendToClient(userId, { type: "stream_end", leaderId: streamLeaderId });
  streamEndSent = true;
}
```

**Edge cases:**

- **Supersession mid-stream.** `abortSession` flips `controller.signal.aborted`, the loop exits via `break`. The post-loop guard fires `stream_end` — correct: the client should transition the bubble to done (superseded turn is a done state from the bubble's POV).
- **`resumeSessionId` error path (line 982).** `throw err` re-raises; the catch at line 982 re-throws without running the post-loop code. Solution: move the post-loop guard BEFORE the `throw err` so the client always gets `stream_end` before the upstream `.catch()` fallback fires.
- **Multi-leader `dispatchToLeaders`.** Each leader runs its own `startAgentSession`, so each has its own `streamStartSent` / `streamEndSent` locals. No cross-leader interference. Verify with multi-leader integration test.

**References:**

- Learning [`2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`](../learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md) — the canonical "half-extraction is worse than no extraction" precedent.
- Learning [`discriminated-union-exhaustive-switch-miss-20260410.md`](../learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md) — `_exhaustive: never` grep discipline.
- Learning [`2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`](../learnings/2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md) — cumulative-snapshot client contract; current plan preserves it.

### Phase 3 — GitHub read tools (Bug 2)

1. **REST wrappers.** Add four functions in `github-read-tools.ts` (or extend `ci-tools.ts`). Each calls `githubApiGet(installationId,`/repos/${owner}/${repo}/...`)` and returns a narrowed JSON payload (not the full REST response — strip bot metadata, avatar URLs, etc. to keep token budgets small). Example shapes:
   - `readIssue(installationId, owner, repo, issue_number)` → `{ number, title, state, body, labels: string[], assignees: string[], milestone: string | null, created_at, updated_at, html_url }`
   - `readIssueComments(installationId, owner, repo, issue_number, { per_page? })` → `Array<{ id, user, body, created_at, html_url }>`
   - `readPullRequest(installationId, owner, repo, pull_number)` → union of the issue shape plus `{ draft, merged, mergeable, head_ref, base_ref, review_state }`
   - `listPullRequestComments(installationId, owner, repo, pull_number, { per_page? })` → as issue-comments, but fetched from `/pulls/:number/comments` (review comments) AND `/issues/:number/comments` (conversation comments); return them tagged so the agent can filter.
2. **Tool definitions in `github-tools.ts`.** Add four `tool(...)` calls following the `readCi` pattern (JSON.stringify output, isError on exception). Append to `tools` and `toolNames` arrays. Names:
   - `github_read_issue`, input: `{ issue_number: number }`
   - `github_read_issue_comments`, input: `{ issue_number: number, per_page?: number }`
   - `github_read_pr`, input: `{ pull_number: number }`
   - `github_list_pr_comments`, input: `{ pull_number: number, per_page?: number }`
3. **Tier map.** Add `"mcp__soleur_platform__github_read_issue": "auto-approve"` and the three siblings to `TOOL_TIER_MAP` in `tool-tiers.ts`. Read-only, auto-approve.
4. **Test.** Add unit tests in `apps/web-platform/test/github-tools.test.ts` (extend if it exists; create if not) that mock `githubApiGet` and assert each tool returns the expected narrowed shape.

### Research Insights (Phase 3)

**Scope-guard hazard (from learning `service-tool-registration-scope-guard-20260410.md`):** The four new tools are being added INSIDE the `if (installationId && repoUrl)` guard. That is correct for these tools (they require the App installation token). But if in the future a read tool is added that uses a user PAT (e.g., reading a PUBLIC issue without App scope), it MUST NOT be nested inside this guard — otherwise users without a connected repo lose access to it. Document this constraint inline with a comment pointing to the learning file.

**Response-narrowing details:**

- Issue body: truncate to 10 KB. Marker: `\n…(truncated, view full at {html_url})`.
- PR body: same 10 KB cap.
- Comment bodies: individually cap at 4 KB (comments are more numerous; tighter cap).
- `per_page` cap: server-side `Math.min(args.per_page, 50)`. Default `10`.
- Strip from the REST response: `user.avatar_url`, `user.events_url` etc — keep only `user.login`. Saves ~300 bytes per user object.
- Keep: `html_url`, `number`, `title`, `state`, `labels: string[]` (map to names only), `assignees: string[]` (logins), `milestone.title`, `created_at`, `updated_at`, body (truncated).

**Agent-native audit (action parity):**

| UI action on connected repo | Agent tool | Status |
|---|---|---|
| View CI status | `github_read_ci_status` | Existing |
| View workflow failure logs | `github_read_workflow_logs` | Existing |
| View issue (title, labels, body, comments) | `github_read_issue` + `github_read_issue_comments` | NEW (this PR) |
| View PR (title, diff summary, review state, comments) | `github_read_pr` + `github_list_pr_comments` | NEW (this PR) |
| Trigger workflow | `github_trigger_workflow` | Existing (gated) |
| Push branch | `github_push_branch` | Existing (gated) |
| Create PR | `create_pull_request` | Existing (gated) |

**Gaps still open after this PR** (file as follow-ups if/when needed, do NOT expand scope now):

- Comment on issue / PR (write)
- Update issue labels / assignees (write)
- Close / reopen issue (write)
- Read diff of a PR (read — this is NOT the same as PR comments; agent often needs the actual changed files)
- List issues / PRs (read — bulk discovery)

The 7-tool surface including the 4 new ones is sufficient for "resume work on issue N" and "summarize PR N review state" — the two concrete user journeys driving this plan.

**Implementation detail — `readPullRequest`:** The GitHub REST endpoint `/repos/:owner/:repo/pulls/:n` returns rich review state (`mergeable`, `mergeable_state`, `rebaseable`, `draft`, `merged`, `merged_at`). Expose these — they are exactly the fields an agent needs to decide "should I push a fix, or is this already merged."

**Rate-limit note:** GitHub App installation tokens have 5,000 req/hr per installation shared across all users — not per-user. A single runaway agent can starve other users. Consider adding a per-session soft cap (e.g., 100 reads/session) in a follow-up PR — do NOT add it here.

**References:**

- GitHub REST API: issue endpoint [docs.github.com/en/rest/issues/issues#get-an-issue](https://docs.github.com/en/rest/issues/issues#get-an-issue) (verified: endpoint stable across API versions).
- PR endpoint [docs.github.com/en/rest/pulls/pulls#get-a-pull-request](https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request).
- Comments: issues vs. pulls comments are separate endpoints (`/issues/:n/comments` = conversation, `/pulls/:n/comments` = review comments).

### Phase 4 — Agent discoverability

The agent cannot auto-discover these tools from natural language unless the system prompt mentions them. The existing KB-share announce block in `agent-runner.ts:549-588` is the precedent. Add a short `## GitHub read access` section to `systemPrompt` inside the `installationId && repoUrl` guard (line 613), announcing the four tools and when to use them.

### Phase 5 — File follow-up issues (AFTER merge, but BEFORE session ends)

Three issues, each with verified label names:

1. **`deferred-scope-out` — track whether to install `gh` CLI in Dockerfile as CLI-only fallback.**
   - Title: `[deferred] Evaluate installing gh CLI in runner Dockerfile as fallback to MCP-only GitHub access`
   - Labels: `deferred-scope-out`, `domain/engineering`
   - Milestone: `Post-MVP / Later`
   - Body MUST contain `## Scope-Out Justification` per `rf-review-finding-default-fix-inline`. Rationale: MCP path satisfies current needs; `gh` install adds container-layer weight, needs audit of auth flow (install token vs. user PAT), and re-evaluate when an agent-native workflow hits CLI-only commands.

2. **`type/feature` — single-leader default for web UI auto-routing.**
   - Title: `[feat] Web UI Command Center — single-leader default auto-routing with on-demand escalation`
   - Labels: `type/feature`, `domain/product`
   - Milestone: let CPO decide via issue triage; default `Post-MVP / Later`.
   - Body: problem (cost doubling ~$0.44/turn, double bubbles), rationale vs. `pdr-when-a-user-message-contains-a-clear` (rule is for orthogonal signals, not duplicated domain coverage), proposed UX (primary leader pick + @-mention escalation), acceptance criteria.

3. **`type/feature` — Command Center should route through `/soleur:go` internally.**
   - Title: `[feat] Web UI Command Center should delegate to /soleur:go skill instead of re-implementing brainstorm/one-shot/work inline`
   - Labels: `type/feature`, `domain/engineering`
   - Milestone: `Post-MVP / Later`.
   - Body: agent-native-architecture principle (one workflow tree). Reference `plugins/soleur/skills/go/SKILL.md` as the canonical entrypoint.

**Use `gh issue create --label <name> --milestone "Post-MVP / Later"`** per `cq-gh-issue-create-milestone-takes-title`. Confirm each label exists with `gh label list --limit 100 | grep -i <keyword>` per `cq-gh-issue-label-verify-name`.

### Phase 6 — Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Forward SDK `tool_progress` events to the client and track per-`tool_use_id` completion | The client has no `tool_use_id` model; adding one doubles the WS protocol surface for no visible UX improvement over the current leader-scoped single-bubble design. `tool_progress` is a heartbeat (no done signal). |
| Use the official GitHub remote MCP server (`api.githubcopilot.com/mcp/`) with a user PAT | Duplicates auth surface; introduces a new Doppler secret; bypasses the App installation scoping that currently gates repo access. Reject per Reconciliation table. |
| Install `gh` CLI in the runner Dockerfile | Increases container layer weight + re-introduces sandbox path ambiguity. Deferred as follow-up. |
| Add per-tool status chips (green check on each completed tool) | Larger UI change; deferred as follow-up #3 above. The current `toolsUsed[]` list on the `done` bubble is sufficient for the present bug scope. |
| Add a new `interrupted` MessageState alongside `done` | Premature — no user signal that a distinct state is needed. `done` plus optional `toolsUsed` list conveys the same information. |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] RED tests in Phase 1 captured in the PR description (link to vitest output).
- [ ] After Phase 2: all `chat-state-machine.test.ts` tests pass including the two new ones.
- [ ] After Phase 3: `github-tools.test.ts` new tests pass against mocked `githubApiGet`.
- [ ] `tsc --noEmit` clean across `apps/web-platform`.
- [ ] `./node_modules/.bin/vitest run` clean across `apps/web-platform/test/`.
- [ ] `apps/web-platform/server/tool-tiers.ts` `TOOL_TIER_MAP` includes all four new tool names.
- [ ] `buildGithubTools` returns four new entries in both `tools[]` and `toolNames[]`.
- [ ] System prompt includes a `## GitHub read access` announcement block (Phase 4).
- [ ] Manual screenshot: reproduce the original stuck-bubble scenario in a local Command Center session; verify every bubble reaches the green check / `done` state by turn end. Attach before/after to PR.
- [ ] Manual probe: ask the agent in a Command Center session to "read issue 2831 and summarize." Agent invokes `github_read_issue` (not `gh`). Attach transcript.
- [ ] Three follow-up issues exist on GitHub with correct labels + milestones (use `gh issue view <N>` to confirm).

### Post-merge (operator)

- [ ] CI passes on main.
- [ ] Deploy webhook succeeds (`postmerge` skill auto-runs in `/ship` Phase 7).
- [ ] Smoke-test on production: open `/command-center`, resume a real conversation, verify bubbles reach `done`. 5-min verification per `cq-for-production-debugging-use`.

## Test Scenarios

1. **Single-leader happy path (regression).** One leader, three `tool_use` events, one final `stream` text, `stream_end`. Bubble reaches `done`. No regression.
2. **Single-leader tool-final turn.** One leader, two `tool_use` events, NO final text, `stream_end`. Bubble reaches `done`. (Already covered by existing `stream_end` handler; use as regression sentinel.)
3. **Multi-leader parallel with staggered stream_end.** CPO and CTO run in parallel; CPO finishes first. CTO bubble remains in `tool_use`/`streaming` until its own `stream_end`, then reaches `done`. No premature clearing.
4. **Multi-leader with review_gate mid-stream.** CPO and CTO both active; `review_gate` fires. BOTH bubbles should transition to `done` (not stuck). **New RED test.**
5. **Exception in result branch.** Mock `updateConversationStatus` to throw; assert `stream_end` still fires via the `finally`-style emission in Phase 2.
6. **github_read_issue invocation.** Agent calls the tool; mocked REST returns issue #2831; tool returns the narrowed JSON shape; no PR creation review gate fires (read-only, auto-approve).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed (inline, not via Task subagent — session is in pipeline/plan-phase; architecture discussion captured in Reconciliation + Hypotheses)
**Assessment:** The fix is local and small. The chief risk is hypothesis-1 in Phase 1 being wrong — i.e., the stuck-bubble bug has a different root cause than the review_gate clobbering or the exception-path gap. Mitigation: Phase 1 writes RED tests for the hypothesized cases; if none go RED, halt and re-investigate before writing code. The github-read tools extension is a pure additive change on a well-trodden pattern — low risk.

#### Architecture review (inline, architecture-strategist lens)

- **SOLID — Single Responsibility:** `chat-state-machine.ts` remains the sole owner of stream-event-to-state-transitions; `agent-runner.ts` remains sole owner of SDK→WS event translation. Phase 2's Option A does not cross this boundary.
- **No new circular dependencies.** `github-read-tools.ts` imports from `github-api.ts` (existing); `github-tools.ts` imports from both. One-way fan-in.
- **Layering preserved.** In-process MCP tools live in `apps/web-platform/server/*-tools.ts` by convention (kb-share-tools, conversations-tools, github-tools). `github-read-tools.ts` follows the same pattern.
- **ADR check:** No new service, no infra change. No ADR required.
- **Interface stability:** WSMessage union unchanged. Tool tier map is additive. Backward compatible.

#### Code simplicity review (inline, code-simplicity-reviewer lens)

- **YAGNI:** Rejected adding per-tool-use-id status chips (premature — one user report of stuck bubbles, no explicit request for per-tool chips). Rejected adding `"interrupted"` MessageState. Rejected forwarding `SDKToolProgressMessage` as a heartbeat event to the client (no user-visible value).
- **No new abstraction layer.** The fix is confined to one branch of `applyStreamEvent` and one linear addition to `startAgentSession`. No new helper, no new types, no new module (except `github-read-tools.ts` which is cohesive and justified by file-size separation from `ci-tools.ts`).
- **No defensive programming cruft.** The `streamEndSent` boolean is not "just in case" — it's load-bearing for idempotency across the result / catch / post-loop paths. Remove-on-sight bar: none.
- **Inline candidate:** If `github-read-tools.ts` is small (<150 LOC), consider inlining into `github-tools.ts` to avoid module fragmentation. Decision: defer to work-phase — if four REST wrappers + response-narrowing helpers push past 200 LOC, keep the split.

#### Test design review (inline, test-design-reviewer lens, Farley 8 properties)

Scoring targets for the new tests (Phase 1 RED + Phase 3 tool tests):

| Property | Target | How Phase 1/3 achieves it |
|---|---|---|
| Understandable | 9/10 | Test names name the specific scenario ("review_gate preserves peer bubbles"), not the implementation detail. |
| Maintainable | 8/10 | Tests assert on `state` and bubble identity — NOT on internal reducer shape. The reducer can be refactored to Option B without breaking tests. |
| Repeatable | 10/10 | No timers, no fake-timers (intentional — rAF-sweep hazard avoided). No network. |
| Atomic | 9/10 | One behavior per test; the four tests in Phase 1 are independent. |
| Necessary | 8/10 | Every test closes a known hypothesis or regression-pins a passing behavior; no over-testing the happy path (which existing `ws-streaming-state.test.ts` covers). |
| Granular | 8/10 | Assertion failure messages will point at the specific transition (`expected "done" got "tool_use"`). |
| Fast | 10/10 | Pure reducer tests run sub-ms each. |
| First (TDD) | 10/10 | Phase 1 mandates RED before GREEN. |

**Weighted average target: ≥ 9.0 (grade A).**

**Anti-pattern check:** No jsdom layout-gated assertions (`cq-jsdom-no-layout-gated-assertions`). No mutation assertions using `toContain` (`cq-mutation-assertions-pin-exact-post-state`) — Phase 1 uses `.toBe("done")`. No LLM-mediated security assertion (`cq-llm-sdk-security-tests-need-deterministic-invocation` not applicable — no security test).

#### Agent-native review (inline, agent-native-reviewer lens)

- **Action parity:** Closes the `github_read_issue` gap the agent self-identified. See Phase 3 action-parity table.
- **Context parity:** `html_url` is included in every narrowed response so the agent can hand the user a clickable link — user and agent see the same source of truth.
- **Shared workspace:** N/A for this feature (GitHub is external).
- **Primitives over workflows:** Four atomic read tools, NOT one composite "summarize issue for me" tool. Correct.
- **Dynamic context injection:** The `## GitHub read access` system-prompt block announces the tools. Consistent with the existing `## Knowledge-base sharing` and `## KB-chat thread discovery` precedent (agent-runner.ts:549-588).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — no new page or component created; change is to existing chat bubble state transitions and adds four agent-invisible-to-end-user tools.
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (not applicable — no new UI), copywriter (not applicable — no new user-visible strings beyond existing tool-label vocabulary which is unchanged).
**Pencil available:** N/A

#### Findings

- The amber "Working" chip is an existing visual element. No copy change.
- The three follow-up issues (Phase 5) include a Product-tagged one (single-leader default) that will receive its own Product/UX review when implemented.

## Open Code-Review Overlap

Command: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` then `jq -r --arg path "apps/web-platform/server/agent-runner.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json` for each planned file.

Ran at plan time. To complete this gate, the implementer must run the commands above for: `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/lib/chat-state-machine.ts`, `apps/web-platform/server/github-tools.ts`, `apps/web-platform/server/tool-tiers.ts`, `apps/web-platform/server/ci-tools.ts`. If any scope-out issue touches one of these files, add a disposition row here (Fold in / Acknowledge / Defer). If none, write `None` below.

**Result at plan time:** Deferred to Phase 0 of the work skill (before any edits land). The plan author does not have confidence every code-review issue body references its files by absolute repo path — some use short names. The implementer should run the JSON dump once and eyeball titles for any chat/WS/agent-runner mention.

## Risks

- **Hypothesis-1 wrong.** If the stuck-bubble bug is NOT the review_gate clobber or exception-path gap, Phase 2's fixes are cosmetic. Mitigation: run Phase 1 RED tests first; reproduce the original scenario in a local session before shipping.
- **Parallel-leader map invariant.** If `activeStreams` is ever keyed by something other than `leaderId` in the future, the per-leader `stream_end` scoping breaks silently. Mitigation: add a type-level invariant comment to `applyStreamEvent` and a regression test for the parallel scenario.
- **GitHub API rate limits.** The GitHub App installation token has generous rate limits (5k/hr/installation) but a runaway agent could burn through them reading large PR comment threads. Mitigation: cap `per_page` at 50 server-side; document in tool description.
- **Issue/PR body truncation.** Issue bodies can be very long. Narrowing the REST response helps; also truncate `body` at 10k chars with an explicit `"…(truncated, use html_url for full)"` marker. Keeps token budgets predictable.
- **System-prompt growth.** Adding the `## GitHub read access` block adds ~100 tokens to every agent session. Acceptable — KB-share is similar size and already shipped.

## Rollout / Monitoring

- Deploy via standard `/ship` flow. No migrations, no infra changes, no new Doppler secrets.
- Monitor Sentry `feature: "agent"` tag for post-deploy error rates (no increase expected).
- Monitor WS disconnect reasons: `idle_timeout` rate should not increase (verifies bubbles aren't silently timing out).

## Pre-Phase-0 gates (deepen-pass additions)

Before writing any code in Phase 1, the work-skill implementer MUST run:

1. `gh issue view 2217 --json state` — confirm whether the `useReducer` companion-state migration is CLOSED (→ ship Option A) or OPEN (→ consider Option B). Record the result in PR description.
2. `rg "const _exhaustive: never" apps/web-platform/` — enumerate every exhaustive WSMessage switch. Phase 2 must not break any of them. This plan does NOT change the union but the grep is cheap insurance (per `cq-union-widening-grep-three-patterns` and learning `discriminated-union-exhaustive-switch-miss-20260410.md`).
3. `rg "\.kind === \"" apps/web-platform/lib/chat-state-machine.ts apps/web-platform/components/chat/` — ditto for MessageState transitions. Returns hits must be reviewed; none are expected since `state` is a union-of-strings not a discriminant.
4. `rg "google|github|agent-runner|chat-state-machine" knowledge-base/project/learnings/ -l | xargs grep -l "module: Chat\|module: agent-runner\|category: runtime-errors"` — re-scan new learnings added between plan-time and work-time. If any postdate 2026-04-23 and name these modules, read them before Phase 1.
5. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — baseline clean. Required by `cq-in-worktrees-run-vitest-via-node-node` precedent; `tsc` runs identically from the worktree's `node_modules`.

If any grep returns unexpected hits (e.g., a `tool_use_id` mention in `ws-client.ts` that wasn't there at plan time), STOP and re-read that file before editing.

## Sharp Edges

- When editing `agent-runner.ts`, re-read lines 843-964 first — the loop body handles five distinct SDK message shapes and the branching is subtle.
- When editing `chat-state-machine.ts:review_gate`, do NOT change `timerAction: "clear_all"` — that's correct and has a test behind it.
- When adding new tools to `github-tools.ts`, keep the `tools[]` and `toolNames[]` arrays in sync — dropped `toolNames` entries silently disable `canUseTool` allowlisting and the tool is invisible to the agent.
- The `installationId && repoUrl` guard around `buildGithubTools` is load-bearing — users without a connected repo must not get these tools or the App-auth call will 401 and the tool will error at invocation. Keep the guard; do NOT hoist the new tool creation outside it. See learning `service-tool-registration-scope-guard-20260410.md` for the inverse hazard (do NOT nest tools inside unrelated guards either — match the actual auth requirement).
- The `owner`/`repo` validation regex (`GITHUB_NAME_RE`) runs before `buildGithubTools` — new tools inherit the safety. Do not bypass.
- **Explicit-literals drift check.** The plan uses `"done"` and `"tool_use"` as message-state strings in multiple places (Phase 1 tests, Phase 2 code sketches, Acceptance Criteria). These MUST match the canonical union in `apps/web-platform/lib/types.ts:81` (`export type MessageState = "thinking" | "tool_use" | "streaming" | "done" | "error";`). If that union ever widens, grep this plan and update in lockstep.
- **Stream-end idempotency key.** The `streamEndSent` boolean is scoped to the single `startAgentSession` call — multi-leader dispatch runs one closure per leader, so each has its own boolean. Do NOT hoist this flag into a shared map keyed by `leaderId` — that would reintroduce the cross-leader race that `activeStreams` keying already fixes.
- **System-prompt budget.** The existing `## Knowledge-base sharing` block is ~280 words (agent-runner.ts:549-588). The four-tool `## GitHub read access` announcement should fit in ≤80 words. Measure before committing — a larger block costs tokens on every turn of every session.
- **#2217 decision-point drift.** Between plan-time and work-time, issue #2217 may change state. Phase 0 Pre-Phase-0 gate #1 is load-bearing. If the implementer skips it and ships Option A on a regressed reducer, the next touch will have a bigger rework cost.

## Resume Prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-04-23-fix-command-center-tool-progress-and-github-mcp-plan.md

Context: branch feat-one-shot-command-center-fixes, worktree .worktrees/feat-one-shot-command-center-fixes/, draft PR #2843. Plan reviewed, deepen-plan run. Implementation next — start with Phase 1 RED tests.
```
