---
category: learnings
tags: [supabase, postgrest, rpc, security-definer, numeric-precision, index-only-scan]
date: 2026-04-17
pr: 2501
issue: 2478
---

# Supabase hosted PostgREST disables aggregates — plan-claimed Option A is unavailable

## Problem

PR #2478's plan preferred "Option A" — a pure PostgREST-side aggregate via
`service.from("conversations").select("total_cost_usd.sum()", { head: true })` —
on the grounds that it required no migration. Live probe during Phase 0
returned:

```text
{"code":"PGRST123","details":null,"hint":null,"message":"Use of aggregate functions is not allowed"}
HTTP 400
```

Supabase's hosted PostgREST pins `db-aggregates-enabled = false` project-wide
as a DoS defense. The flag is not exposed in the Supabase dashboard; flipping
it would be an infrastructure-side policy change affecting every tenant.

## Solution

Option B (security-definer RPC + migration) became the only path. Key
decisions applied to migration 027:

1. **Security pattern mirrors migration 017** — `SECURITY DEFINER`,
   `SET search_path = public`, `REVOKE EXECUTE … FROM PUBLIC/authenticated/anon`,
   `GRANT EXECUTE … TO service_role`. The REVOKEs run on every apply (not
   "cleanup after CREATE") to close the first-create default-PUBLIC-EXECUTE
   gap.
2. **Partial index needed an `INCLUDE` column** — the existing
   `idx_conversations_user_cost ON conversations (user_id, created_at DESC)
   WHERE total_cost_usd > 0` covered the filter but forced heap revisit for
   `total_cost_usd`. Extending the same migration with
   `DROP INDEX … ; CREATE INDEX … INCLUDE (total_cost_usd)` enables true
   Index Only Scan for both the aggregate and the existing list query.
3. **PostgREST NUMERIC wire shape** — `.rpc()` returns a JSON string for
   NUMERIC to preserve precision. Read it once at the Node boundary via
   `Number(monthRow?.total ?? 0)`. IEEE 754 has ~15 significant decimal
   digits of headroom — enough for MTD totals < $10K at NUMERIC(12,6).
4. **Zero-match RPC shape** — an aggregate with no `GROUP BY` always emits
   one row. Combined with `COALESCE(SUM(...), 0)`, PostgREST returns
   `[{total:"0", n:0}]` (not `[]`) for a user with no qualifying
   conversations.

## Key Insight

"No migration required" is a spec claim that can be falsified by a 30-second
live probe. Always probe hosted-database claims in Phase 0 before letting
them shape the plan's implementation path. The plan explicitly preserved the
verbatim probe output in its Research Reconciliation section so no
implementer or reviewer needs to re-probe to confirm the rejection.

## Parity test drift-provocation

A parity test that sums the **same strings** on both sides (client reduce
vs. server SUM, both decoded from `"0.004200"`) cannot detect drift because
both paths operate on identical float representations. The drift-provoking
fixture is `1000 × "0.1"` — JS reduce yields `99.9999999999986`, Postgres
NUMERIC SUM yields exactly `100`. This is the fixture that proves the RPC
is doing what it claims.

## Session Errors

1. **Permission denied on `git stash` in worktree** — attempted to stash to
   verify if kb-chat-sidebar test failures were pre-existing on main.
   Recovery: searched `gh issue list` for existing tracking issues (found
   #2386 covering the exact flaky patterns).
   **Prevention:** already hook-enforced by `guardrails.sh
   guardrails:block-stash-in-worktrees` — the hook correctly caught the
   violation. To verify pre-existing test failures, use `gh issue list
   --search "<test-name>"` or check the commit history of the test file
   instead of stashing.

2. **TypeScript strict-typing error on `mockRpcResult` return type** —
   first implementation declared `PromiseLike<{data, error}>` which
   conflicted with the `onfulfilled` callback signature that other test
   mocks use. Recovery: loosened to `{ then: (onfulfilled?: (v:
   unknown) => unknown) => Promise<unknown> }` to match the pattern
   already used by `single()` in `mock-supabase.ts`.
   **Prevention:** when extending an existing helper file, match the
   return-type shape of sibling helpers in the same file before inventing
   new typings. `tsc --noEmit` after every helper addition catches this
   before implementation code adopts it.

3. **Silent stall of 6 of 12 review subagents** — architecture-strategist,
   code-quality-analyst, pattern-recognition, git-history-analyzer,
   semgrep-sast, silent-failure-hunter were spawned but never emitted
   completion notifications. Transcripts stopped growing ~15s after spawn
   and the user had to ask "did the agents get killed?" after a long
   silence. Recovery: proceeded with partial coverage from the 6 agents
   that returned — adequate for the synthesis, but represents degraded
   coverage.
   **Prevention:** review skill should monitor spawn-to-response latency
   and report "N of 12 agents stalled" proactively after a timeout (e.g.
   5 minutes) rather than silently waiting. A parallel-batch size of 12
   may exceed provider-side concurrency budget; consider batching as 6+6
   with an explicit wait between batches, or adding a "stalled agent
   detector" to the review skill.

## Tags

category: database-issues
module: apps/web-platform/server/api-usage.ts + supabase/migrations/027
