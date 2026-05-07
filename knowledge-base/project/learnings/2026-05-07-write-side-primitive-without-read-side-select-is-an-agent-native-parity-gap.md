---
date: 2026-05-07
category: best-practices
tags: [agent-native, code-review, multi-agent-review, schema-evolution, abort-feature]
related_pr: 3447
related_issue: 3448
related_commits:
  - 69502e2c # server+DB+protocol PR1
  - 1d798ff4 # legal §5.5 + §4.7
  - 550e23e7 # review-fix-inline P1/P2/P3
---

# Write-side primitive without matching read-side SELECT is an agent-native parity gap

## Problem

PR1 of feat-abort-conversation-web (#3447, #3448) added a server-side
user-initiated Stop primitive: a new `abort_turn` WS message variant,
the `agent-runner.ts` for-await abort branch that persists partial
assistant text with `messages.status = 'aborted'` plus a `usage`
snapshot, and migration 040 adding the two columns. Tests passed. tsc
clean. Plan acceptance criteria met. The implementation looked
complete.

The 13-agent code review caught a single P1 finding the implementer
(and 12 of the 13 reviewers) missed: the `GET /api/conversations/:id/messages`
endpoint at `apps/web-platform/server/api-messages.ts:78-80` did NOT
SELECT the new `status` and `usage` columns. The DB had them, the
write path filled them, the live WS subscriber received the
`session_ended:user_aborted` ack and rendered the marker — but a page
reload would silently drop the marker because the read API didn't
return the new columns.

The "honest disclosure" surface promised by the plan's G2 invariant
(user must see what they paid for after Stop) only existed for the
session in which the abort occurred. Reload the conversation, the
marker is gone. The bug class is the same silent-discard PR1 was
specifically meant to fix — moved one layer up from `fullText`
discard to `messages.usage` discard.

The agent-native-reviewer caught it. None of architecture-strategist,
security-sentinel, performance-oracle, data-integrity-guardian,
code-quality-analyst, pattern-recognition-specialist, or
git-history-analyzer flagged it. They all looked at the diff; the
diff didn't include the read API; the read API was therefore "not in
scope." The agent-native-reviewer's frame ("can an agent reading
conversation history programmatically see this?") forced the question
across the diff boundary into a file none of the other agents were
looking at.

## Root cause

Write-side primitives change the data model. Read-side projections
and consumer code paths must be updated in lockstep, even when they
live in files the implementer did not touch. The plan's "Files to
Edit" list is necessarily implementer-centric — it enumerates what
the writer must change. It does not enumerate what readers must
change to consume the new data.

The agent-native-reviewer is the only review agent whose mandate
explicitly crosses the diff boundary in this direction. Its frame is
"if a user can do X via UI, an agent must be able to do X via the
same protocol" — and "doing X" includes reading the result, not just
sending the action. That frame surfaces missing-projection bugs that
the per-file static-analysis agents (architecture, security,
performance) cannot reach because they bound their analysis to the
diff.

## Solution

Three-part fix landed in commit 550e23e7:

1. **Read API SELECT extension** —
   `apps/web-platform/server/api-messages.ts:78-80` now selects
   `status, usage` alongside the existing fields. PR2's history reload
   renders the abort marker for partial assistant text persisted on
   Stop or tab-close.

2. **`Message` type extension** in `apps/web-platform/lib/types.ts:387`
   — adds optional `status?: "complete" | "aborted"` and
   `usage?: {...} | null` fields. Optional so existing
   fixtures/snapshots don't churn; runtime persistence always sets
   `status` (DB default `'complete'`).

3. **Read-path round-trip test** added to
   `apps/web-platform/test/server/abort-turn.test.ts` covering the
   parser's acceptance of the new optional `conversationId` on
   `session_ended` (parallel issue caught by user-impact-reviewer for
   the multi-tab disambiguation surface).

## Key insight

When a PR adds a new column or a new payload field, the test
"how does an agent reading this data programmatically see the new
field?" is load-bearing. It is the question that catches the
matching-projection-update gap that scoped-by-diff review misses.

For features behind the `single-user incident` brand-survival
threshold, schedule the agent-native-reviewer FIRST in any review
pass. Its findings often invalidate or reframe the other agents'
analyses — a P1 read-side gap means the live WS subscriber's
disclosure surface is paper-thin and the deeper architecture
questions can be re-evaluated against the fixed design. Agents that
spend their analysis budget on a write path that's about to grow a
read-path constraint are wasting cycles.

## Secondary findings the multi-agent review caught

The 13-agent review surfaced 22 findings (4 P1, 8 P2, 10 P3). Two
other findings warrant their own smaller learnings:

- **Stringly-typed reason routing is fragile against future-suffix
  kinds.** `classifyAbortReason(reason)` originally read
  `reason.message.includes("user_requested_stop")`. Any future kind
  whose name contains the substring (e.g.,
  `user_requested_stop_by_admin`) would have silently misrouted. The
  fix introduced a typed `SessionAbortError` Error subclass with a
  typed `kind` discriminator property, so the for-await branch reads
  via property access. The fallback Error.message path now uses
  prefix+token-set matching to reject suffixes. Pattern lesson: when
  the runtime's only handle to a finite set of values is an Error
  message, subclass Error and attach the discriminator as a typed
  property — `String.includes` is a substring oracle and will bite.

- **Multi-tab user role is invisible to most review agents.**
  `session_ended:user_aborted` originally lacked `conversationId` —
  for a user with two tabs on different conversations, the
  non-aborting tab's reducer would mis-fire `stopping → idle`. Caught
  by user-impact-reviewer ("name a user role and a vector"), missed
  by all 6 architecture/security/performance/quality/pattern agents
  (who don't model user roles). Pattern lesson: WS-protocol changes
  must be evaluated against multi-tab and multi-device user roles
  explicitly, not just the single-tab happy path.

## Plan-time vs review-time work allocation

This PR ran 3-reviewer plan-time review (DHH/Kieran/code-simplicity)
plus an 11-agent post-implementation review at the
`single-user incident` threshold. The plan-time pass was useful for
catching the multi-leader broadcast semantics + the
ws-handler-resolves-userId TR4 invariant. The post-implementation
pass surfaced the read-API gap, the stringly-typed reason fragility,
and the multi-tab gap — all classes of bug that depend on the
implemented diff existing for the agents to compare against the
codebase.

Allocation rule: plan-time review for invariant design choices
(broadcast vs per-leader, userId-from-payload vs userId-from-session,
status-flip semantics). Post-implementation multi-agent review for
projection completeness (read-side parity, multi-tab parity,
substring-routing fragility). The two passes are complementary, not
redundant.

## Session Errors

- **Bash CWD doesn't persist between calls.** Tool returned `fatal:
  this operation must be run in a work tree` because cwd reset to
  bare repo root between invocations. Recovery: chained `cd
  <worktree-path> && <command>` into every subsequent invocation.
  Prevention: existing AGENTS.md note about chaining; the work skill
  could surface this as a Phase 0 reminder for fresh sessions.
- **Plan referenced non-existent SDK event `tool_use_complete`.** Only
  `tool_use_summary` and `tool_progress` exist in the installed
  `claude-agent-sdk` v0.x typings. Recovery: tracked tool_use via the
  `assistant.content[].type === "tool_use"` block already used by the
  existing chip-emitter. Prevention: plan skill should grep
  `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts` for actual
  event names before encoding them in plan pseudo-code.
- **Outer catch referenced variables declared inside
  `runWithByokLease` callback.** First GREEN attempt failed `tsc
  --noEmit` with TS2304 on `messagePersisted`, `fullText`,
  `accumulatedUsage`, `completedActions`, `streamLeaderId` — all
  declared inside the lease callback closure but referenced from the
  outer catch block (which is the natural home for abort handling
  because `controller.abort()` causes the SDK iterator to throw).
  Recovery: hoisted the accumulators above the outer try. Prevention:
  when extending a catch block, the implementer must verify every
  variable referenced is in scope BEFORE writing the catch body —
  `tsc --noEmit` is the load-bearing gate that catches this.
- **`replace_all` over-marked tasks.md sub-tasks as complete.** Items
  2.1.2 (`supabase migration up`) and 2.1.3 (RLS verification) were
  checked by a wide `replace_all` even though neither was actually
  run during /work (they belong to deploy-time / pre-merge QA).
  Recovery: un-checked with explanatory deferral notes. Prevention:
  after `replace_all` on a task list, audit each newly-checked item
  against actual session evidence; items that map to deferred or
  QA-time work must be un-checked. Could be a /work Phase 2 skill
  instruction.
- **Plan/code drift on conversation status enum.** Plan markdown said
  `conversation stays active` but the actual `Conversation.status`
  enum at `apps/web-platform/lib/types.ts:352` is `"active" |
  "waiting_for_user" | "completed" | "failed"`, where `active` means
  "agent currently running" (in-flight) and the continuable terminus
  is `waiting_for_user`. Caught by architecture-strategist +
  data-integrity-guardian post-implementation. Recovery: updated plan
  and spec markdown to say `waiting_for_user`. Prevention: plan skill
  should verify any enum value referenced in plan prose against the
  actual TS union type before publishing — concretely, grep the type
  definition and require an exact match.
- **`gh issue create --label "type/enhancement"`** failed with "label
  not found" — the repo's enhancement label is `enhancement`, not
  `type/enhancement`. Recovery: switched label. Prevention: scope-out
  filing skills could check `gh label list --json name --jq
  '.[].name'` once at session start and cache the valid label set, OR
  attempt the create and retry with the next-best label on
  not-found.
- **Edit tool rejected an unread file** for the
  `plugins/soleur/docs/pages/legal/terms-and-conditions.md` Eleventy
  copy. The canonical `docs/legal/` copy had been read but the
  Eleventy copy had not. Recovery: read the second copy explicitly,
  then edited. Prevention: when working with synced doc pairs (the
  legal copies are kept identical except for frontmatter), read both
  copies up-front before starting edits.

## Tags
category: best-practices
module: web-platform
domain: code-review
