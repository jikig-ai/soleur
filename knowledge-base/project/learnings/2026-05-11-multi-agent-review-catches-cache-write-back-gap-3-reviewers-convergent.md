---
title: Multi-agent review catches in-process cache write-back gap (3 reviewers convergent)
date: 2026-05-11
category: best-practices
module: cc-soleur-go
related_prs: [3263, 3574]
related_issues: [3266, 3250]
tags: [multi-agent-review, cache-write-back, dispatcher-event-hooks, runner-reap]
---

# Multi-agent review catches in-process cache write-back gap (3 reviewers convergent)

## Problem

PR #3574 (issue #3266) wired `conversations.session_id` reader+writer for the
cc-soleur-go path. The implementation correctly:

- Persisted `session_id` to DB via `onSessionIdCaptured` event
- Threaded the persisted value from `conversations.session_id` SELECT through
  `ClientSession.sessionId` cache into `dispatchSoleurGo({ sessionId })`
- Cleared stale values on non-KeyInvalidError dispatch failures

All 11 new vitest scenarios passed (3 RED→GREEN files), `tsc --noEmit` clean,
3973 tests green. The shape matched the plan's §Phase 2-4 prescriptions exactly.

But the implementation **defeated its own feature in the most common scenario** —
runner idle-reap (10-30 min idle window) with the WS session still alive. The
gap: `onSessionIdCaptured` wrote to DB only, never updating the in-process
`ClientSession.sessionId` cache. On the next chat-case turn after a reap, the
cache-hit branch forwarded stale `null` to `dispatchSoleurGo`, so cold-Query
construction used `resumeSessionId = undefined`, the SDK started a fresh
session, and the persisted DB value was never read.

The bug surface (`ws-handler.ts:1486-1521` cache predicate × `cc-dispatcher.ts:1123-1132`
event handler × `soleur-go-runner.ts:1781-1792` idle reap) spans three modules
with no single test that exercised the cross-module post-reap interaction.

## Discovery

Three reviewers independently surfaced this gap with the same root cause:

1. **performance-oracle (F1, HIGH)** — traced the post-reap data flow step-by-step
   and identified the cache staleness as a P1 functional bug.
2. **data-integrity-guardian (F1, P2)** — flagged the cache vs DB divergence
   from the stale-clear path angle.
3. **user-impact-reviewer (F3)** — named the artifact (`ClientSession.sessionId`
   cache) and the exposure vector (stale `null` after writer persists), tying it
   to the plan's `single-user incident` brand-survival threshold.
4. **git-history-analyzer (P2)** — independently traced the same data flow
   citing `persistActiveWorkflow`'s analogous self-update at `ws-handler.ts:874-883`
   as the parity reference the new writer was missing.

No vitest scenario covered this — the existing tests:
- Verified the writer fires correctly (`cc-dispatcher-session-id-writer.test.ts`)
- Verified the runner emits the event correctly (`soleur-go-runner-session-id-rebound.test.ts`)
- Verified the reader forwards the param correctly (`ws-handler-cc-session-id-wiring.test.ts`)

Each was internally consistent. The bug was at the seam between writer side
effects and reader cache state — exactly the seam multi-agent review excels at
finding because each reviewer reads the surface from a different angle (perf
traces data flow over time; user-impact names artifacts and exposure vectors;
git-history compares to the parity reference).

## Solution

Thread a synchronous `onSessionIdPersisted: (sessionId | null) => void` callback
through `DispatchSoleurGoArgs`. The ws-handler provides a closure that mutates
`sessions.get(userId).sessionId` (guarded on `conversationId` equality to avoid
clobbering a value bound to a different conversation that the user switched to
mid-dispatch). The cc-dispatcher invokes the callback synchronously BEFORE the
async DB write commits — so the next turn can read the value even if the user
fires a follow-up before persistence lands.

The fire-and-forget cache update + async DB write is symmetric on both paths:
- `onSessionIdCaptured` event → `onSessionIdPersisted(sessionId)` + `persistCcSessionId`
- Catch-block stale-clear → `onSessionIdPersisted(null)` + `clearCcSessionId`

This eliminates the runner-reap-defeat scenario AND keeps the cache aligned
with DB through the stale-clear path.

## Why three reviewers caught what one author + tests missed

The shared bug-shape across all three convergent findings: **a feature whose
correctness depends on data flowing across N modules, where each module's
contract is internally satisfied but the cross-module invariant (cache mirrors
DB) is violated**. This is a sibling pattern to the 2026-04-24 learning
"multi-agent review catches feature wiring bugs" — module A correct in
isolation, module B correct in isolation, A+B together violate an invariant in
module C (the cache).

Specific lessons:

1. **Cache write-back is a separate invariant from DB write.** When a feature
   adds a DB column read+write, audit for in-process caches of that column.
   `persistActiveWorkflow` had the same pattern at `ws-handler.ts:874-883` —
   updating `liveSession.routing` alongside the DB write — which the new code
   should have mirrored.

2. **Convergent findings from independent reviewers are high-confidence signals.**
   When 3+ reviewers cite the same root cause via different framings (perf,
   data-integrity, user-impact, git-history), the finding is load-bearing for
   merge. No author dismissal regardless of "but my tests pass".

3. **Plan-time review and unit tests cannot substitute for multi-agent code
   review.** The plan-time CPO sign-off, plan-time CTO review, deepen-plan
   step, and unit tests all left this gap untouched because none of them
   exercised the cross-module post-reap interaction. Only review agents
   reading the diff against the live runtime model surfaced it.

## Pattern: Cross-Module Cache Write-Back Audit

When a PR adds a DB column read+write hot path, grep the codebase for **in-process
caches** of that column. For Soleur, the canonical caches live on
`ClientSession` (`apps/web-platform/server/ws-handler.ts:105-152`). Every
column that has a `ClientSession.<field>` mirror MUST have a writer-side
update site alongside the DB write — see `persistActiveWorkflow` at
`ws-handler.ts:874-883` for the canonical shape (the writer updates DB then
updates `liveSession.routing`).

The audit is a single grep: `grep -n "session\.\(routing\|contextPath\|sessionId\)" apps/web-platform/server/ws-handler.ts`
to enumerate every cache mirror, then verify each has a writer-side update
site for its corresponding DB column write.

Place the audit at **Phase 2 of `/work`** (before the per-task RED/GREEN loop)
when the plan touches a column that has a `ClientSession.<field>` mirror. This
catches the gap before tests are written — the test author would otherwise
miss the cross-module invariant for the same reason the implementer did.

## Session Errors

1. **Edit collision on soleur-go-runner.ts** — Edit failed with "File has
   been modified since read" after a concurrent agent-completion notification
   arrived between Read and Edit. Recovery: re-read the file, re-applied the
   edit. **Prevention:** Edit tool's stale-read detection already handles
   this; no rule change needed.

2. **CWD lost across Bash calls in worktree** — `cd apps/web-platform` in
   one Bash call did not persist to a subsequent `grep` call. CWD reverted to
   worktree root, where the path resolved against bare repo paths. Recovery:
   chained `cd && cmd` in a single Bash invocation, or used absolute paths.
   **Prevention:** Already covered by AGENTS.md / plan / work skill guidance
   on bash CWD non-persistence; no new rule.

3. **Implementation drift from plan: latch vs rebind-aware gate** — Initial
   `handleResultMessage` used once-only-per-state latch
   (`!sessionIdEverEmitted`) instead of the plan's prescribed rebind-aware
   gate (`Re-fire only when the value changes`). Caught by
   pattern-recognition reviewer (F1+F2). The latch worked functionally but
   produced a redundant DB write per cold-Query on warm-resume.
   **Prevention:** Skip rule proposal — discoverable via review, not a
   silent-failure or blast-radius incident. Add a workflow note to the work
   skill's Phase 2 TDD section: "When the plan specifies a state-machine
   gate condition ('fire on X', 'fire on transition'), implement the exact
   condition rather than a once-only latch unless the plan explicitly
   prescribes 'once'." (Domain-scoped to the work skill, not AGENTS.md.)

## References

- PR #3574 — feat-one-shot-3266-cc-session-id-wiring
- Issue #3266 — wire conversations.session_id reader+writer for cc-soleur-go
- Prior PR #3263 — legacy fold-in (Approach C parent)
- Related learning:
  `knowledge-base/project/learnings/best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`
- Related learning:
  `knowledge-base/project/learnings/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`
- Parity reference: `apps/web-platform/server/ws-handler.ts:874-883`
  (`persistActiveWorkflow` self-update of `liveSession.routing`)
- AGENTS.md rules referenced: `hr-weigh-every-decision-against-target-user-impact`,
  `rf-review-finding-default-fix-inline`, `cq-silent-fallback-must-mirror-to-sentry`
