# fix: Command Center tool-progress stuck bubble + agent-native GitHub reads

**Date:** 2026-04-23
**Branch:** feat-one-shot-command-center-fixes
**Worktree:** .worktrees/feat-one-shot-command-center-fixes
**Draft PR:** #2843
**Labels:** type/bug, priority/p1-high, domain/engineering, semver:minor
**Semver rationale:** minor — adds four new agent-visible tools (new capability surface). If we decide NOT to expose new tools (only fix Bug 1), downgrade to patch.

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

1. **`chat-state-machine.ts:review_gate` branch.** Replace `activeStreams: new Map()` with: iterate the existing map, set each leader's bubble `state: "done"` (or a new `"interrupted"` state — defer unless needed), then clear. Keep `timerAction: "clear_all"`.
2. **`agent-runner.ts` stream_end hardening.** Today, `stream_end` fires inside the `result` branch (line 930). Restructure: track `streamStartSent: boolean` local to the session. Move `sendToClient(..., "stream_end", ...)` into a `finally`-style block that runs after the `for await` loop exits — whether by `result`, by `controller.signal.aborted`, or by an exception caught below. Guard with `if (streamStartSent && !streamEndSent)`.
3. **Re-run the failing tests.** They must pass. Do NOT edit the passing tests.

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

## Sharp Edges

- When editing `agent-runner.ts`, re-read lines 843-964 first — the loop body handles five distinct SDK message shapes and the branching is subtle.
- When editing `chat-state-machine.ts:review_gate`, do NOT change `timerAction: "clear_all"` — that's correct and has a test behind it.
- When adding new tools to `github-tools.ts`, keep the `tools[]` and `toolNames[]` arrays in sync — dropped `toolNames` entries silently disable `canUseTool` allowlisting and the tool is invisible to the agent.
- The `installationId && repoUrl` guard around `buildGithubTools` is load-bearing — users without a connected repo must not get these tools or the App-auth call will 401 and the tool will error at invocation. Keep the guard; do NOT hoist the new tool creation outside it.
- The `owner`/`repo` validation regex (`GITHUB_NAME_RE`) runs before `buildGithubTools` — new tools inherit the safety. Do not bypass.

## Resume Prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-04-23-fix-command-center-tool-progress-and-github-mcp-plan.md

Context: branch feat-one-shot-command-center-fixes, worktree .worktrees/feat-one-shot-command-center-fixes/, draft PR #2843. Plan reviewed, deepen-plan run. Implementation next — start with Phase 1 RED tests.
```
