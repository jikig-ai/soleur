---
title: A check added after the write that commits fires once; and a fail-closed comment true for one state was written for two
date: 2026-10-30
category: logic-errors
tags: [engine-binding, fail-closed, review-fix-round, source-pins, auth-mode]
---

# Learning: a post-commit check fires once, and a "fails closed" comment was true for one of two states

## Problem

PR #11590 made the "Authentication mode" setting select the Concierge credential. To stop a non-Claude
engine binding from being run by the Claude runner, the first review round added `assertLegacyEngineBinding`
after `bind_agent_engine_run` at the support-thread and auto-sync bind sites. Round 1 of the targeted fix
review then found four seats converging on two defects *inside that fix*:

1. The bind RPC commits the run and flips the row to `bound` in one transaction, so the assert throws on the
   request that binds and never again: the next message sees a `bound` row, skips both the bind and the
   assert, and runs Claude under a non-Claude binding. `ws-handler` avoids this by re-checking on every resume.
2. The comment said a failed bind "leaves the lease failing closed for a subscription holder". That holds for
   `pending` rows (no run, `unbound`). A sticky `legacy` row with no run resolves to `managed` (the
   subscription), so a failed bind served the subscription to an owner who had chosen "My API key".

Same family, in tests: the source-pin helper stripped only whole-line `//` comments, so a JSDoc line quoting
the pinned call satisfied it while the code hard-coded `resolveAuthMode: async () => "managed"`.

## Solution

- Re-check the persisted engine on the sticky `bound` path too (one single-row indexed read per message).
- On a `legacy` row, rethrow a non-duplicate bind failure (the route falls back to its canned reply);
  `pending` and new rows stay soft because the lease already fails closed. Key duplicate detection on SQLSTATE
  `23505`, which `bind()` now carries, with the message match as fallback.
- Pins strip block comments and trailing `//` and count per file instead of summing across files.

## Key Insight

A guard placed after the state transition it protects runs only on the request that makes the transition.
For every check added "after the bind/insert/commit", ask what the *next* request sees and where its guard is.
And a comment that says "X fails closed" is a claim per state: enumerate the states (`new`, `pending`,
`legacy`, `bound`) and name the one that does not. A review fix is the least-audited surface in the diff, so
a fix round that re-reads only the fix commits earns its cost.

## Session Errors

1. **Fix asserted the engine only on the binding request** — Recovery: assert on the sticky `bound` path, mutation-checked — Prevention: for any check added after a state transition, list the next request's path and its guard (review skill sharp edge).
2. **Comment claimed fail-closed for `legacy` rows** — Recovery: rethrow for `legacy`, ADR-048 reworded — Prevention: write fail-closed claims per state, not per feature.
3. **Source pin satisfied by a JSDoc quote** — Recovery: strip block and trailing comments, per-file counts — Prevention: a source-text pin must be comment-stripped in all three comment forms.
4. **`git push … | grep -v remote` produced a false non-zero `PUSH_RC`** — Recovery: compared `HEAD` with `origin/<branch>` — Prevention: never pipe a command whose exit code is the result.
5. **Affected-test gate ended `budget-deferred` under contention** — Recovery: ran the consumer and source-text suites by name on the combined tree (77 files, 1451 tests) — Prevention: none new; CI is the authoritative gate.
6. **Stop hook blocked a turn ending on a promised action** — Recovery: did the action in the same turn — Prevention: end a waiting turn with a `Paused:`/`Blocked:` sentence.
7. **tsc failed on 6 test call sites when `LeaseModeOpts` became required** — Recovery: updated the call sites in the same change — Prevention: none; the required type did its job.

## Tags
category: logic-errors
module: apps/web-platform/server (support-conversation, byok-lease, engine-binding-auth-mode)
