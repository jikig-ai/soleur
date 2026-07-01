---
title: When a plan prescribes editing a generic runner's teardown, prefer the existing close-seam + register/drain precedent
date: 2026-07-01
category: best-practices
module: apps/web-platform/server
tags: [integration-design, cc-soleur-go, onCloseQuery, plan-vs-codebase, telemetry, precedent-mirror]
issue: 5843
pr: 5834
---

# When a plan prescribes editing a generic runner's teardown, prefer the existing close-seam + register/drain precedent

## Problem

The TR3 tool-attempt-telemetry plan (#5843) needed a per-query collector's
`flush()` to fire once at the abort-covering teardown of a cc-soleur-go
conversation. The plan prescribed the mechanism literally:

> Phase 3.2 — `soleur-go-runner.ts`: call `collector.flush()` from `closeQuery()`
> (`:1972`) … add `enableToolAttemptTelemetry?: boolean` to `buildAgentQueryOptions`.

Taken literally, that means editing the **generic** SDK runner (`soleur-go-runner.ts`,
shared by every caller) to hard-code a call to a **cc-only** feature, and threading
the collector's `flush` handle into the runner's `ActiveQuery` state — coupling a
reusable module to one feature.

## Solution

Trace the runner for an existing teardown seam before editing its body. Two
precedents already solved the identical shape for the sibling worktree-lease
feature:

1. **`onCloseQuery` dep** — `soleur-go-runner.ts closeQuery` already invokes an
   optional `deps.onCloseQuery({conversationId, userId, reason})` on **every**
   close path (natural end, idle reap, disconnect-abort, SIGTERM drain), *before*
   `activeQueries.delete`. The cc dispatcher wires it as `handleCcCloseQuery`.
2. **`_ccWorktreeLeases` register/drain Map** — a module-level
   `Map<`${userId}:${conversationId}`, handle>` populated in `realSdkQueryFactory`
   and drained in `handleCcCloseQuery`.

Mirroring both kept the generic runner **untouched**: create the collector in
`realSdkQueryFactory`, register it in a sibling `_ccToolAttemptCollectors` Map,
pass only its `preToolUseHook` into `buildAgentQueryOptions` (as a hook, not a
boolean — the paired `flush` handle must escape to the close seam), and
`flush()+delete` it in `handleCcCloseQuery`. The factory-throw catch drops the
entry (mirroring `releaseCcWorktreeLease`) so a startup throw can't leak the map.

`architecture-strategist` (post-implementation review) ruled this SOUND and
"architecturally *superior* to the plan's literal prescription" — same
exactly-once guarantee (every `closeQuery` call site is `if (state.closed) return;
state.closed = true`), abort-covered identically, and no feature coupling in the
runner.

## Key Insight

A plan is authoritative for **intent** (flush once, abort-covered, cc-only
opt-in), never for the exact edit site (same class as
`hr-when-a-plan-specifies-relative-paths-e-g`). When a plan says "edit generic
module M's teardown to call feature F", first grep M for (a) an existing
close/teardown **dep hook** it already invokes on every exit path, and (b) a
sibling **register-in-factory / drain-in-close-hook Map** precedent for a
per-conversation handle. If both exist, mirror them — the generic module stays
uncoupled and you inherit a proven exactly-once + abort-coverage guarantee.

The plan's own Sharp Edge ("NOT a module-level `Map<sessionId>`") is about the
**accumulator** (re-identification/leak/unbounded growth), NOT a **routing** Map
that holds a closure-collector, keys on `(userId, conversationId)` in memory only,
and drains on every close — that distinction is what makes the mirror safe.

## Session Errors

- **`git push` rejected (non-fast-forward) after the Phase 0.5 rebase.** The
  remote feature branch still held the pre-rebase commits. Recovery:
  `git push --force-with-lease`. Prevention: expected consequence of
  rebase-before-applying on an already-pushed branch — reach for
  `--force-with-lease` (never bare `--force`) immediately after any local rebase
  of a pushed feature branch; no rule change needed.
- **Dropping an out-of-band `execute_sql` dev-apply "to keep dev pristine" CAUSED a
  schema-vs-ledger drift CI failure.** During /work I applied migration 118 to dev
  via Supabase MCP `execute_sql` (validation), then at review-time dropped the table
  to resolve a *hypothetical* "ledger-absent" drift the data-integrity agent flagged
  (P3-a). But CI's `tenant-integration` suite runs `run-migrations.sh` against dev on
  every branch push, which had ALREADY applied 118 and written the
  `public._schema_migrations` ledger row. My drop removed the table but not the ledger
  row \u2192 the `Preflight schema-vs-ledger consistency check` failed at merge time
  ("ledger claims 118 applied, but public.tool_attempts is missing"). Recovery:
  re-created the table on dev (idempotent migration body) so schema+ledger+content_sha
  agree again. Prevention: an out-of-band `execute_sql` migration apply on dev is NOT
  "pristine-revertible" once CI has ledgered it \u2014 LEAVE the applied state (CI keeps dev
  applied anyway), or reconcile BOTH the ledger row AND the table together, never the
  table alone. See `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`.
- **`\u2028`/`\u2029` regex escapes materialized as literal U+2028/U+2029 bytes**
  when authoring `lib/tool-name-sanitize.ts` via both Write and Edit (confirmed
  with `grep … | cat -v` showing `M-bM-^@M-(`). Recovery: rewrote the line with a
  Python heredoc emitting explicit ASCII `\u2028\u2029` text. Prevention: when a
  source line must contain literal backslash-`u` unicode-separator escapes
  (`cq-regex-unicode-separators-escape-only`), verify the written bytes with
  `cat -v` and, if literal separators appear, rewrite deterministically via
  `python3`/`sed` rather than re-issuing Write/Edit with the same input.
