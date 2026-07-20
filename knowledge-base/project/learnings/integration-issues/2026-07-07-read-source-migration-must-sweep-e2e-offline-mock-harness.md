---
title: A read-source migration must sweep the e2e offline-mock harness at BOTH layers, not just unit-test mocks
date: 2026-07-07
category: integration-issues
module: apps/web-platform/e2e
tags: [e2e, playwright, mock-supabase, offline-harness, read-source-migration, rpc, endpoint-swap]
related:
  - 2026-06-11-worm-mutation-matrix-and-e2e-harness-mock-for-new-fetches.md
severity: moderate
---

# A read-source migration must sweep the e2e offline-mock harness at BOTH layers

## Problem

A dashboard perf PR MOVED two existing reads to new sources:
- the dashboard's foundation-card state: `/api/kb/tree` (whole-tree walk) → a new
  `/api/dashboard/foundation-status` (targeted stat);
- the conversation rail's list read: two direct client queries
  (`.from("conversations")` + unbounded `.from("messages").in(ids)`) → one
  `supabase.rpc("list_conversations_enriched")` (migration 125).

The **unit-test** mock sweep (`vi.mock` of `@/lib/supabase/client`, the `page.tsx`
fetch stubs) was done and green. But the **e2e offline-mock harness** is a
*separate* mock layer that the unit sweep never touches — and it silently went
stale across **four** files:
- `e2e/nav-states-shell.e2e.ts` (per-test `page.route("**/api/kb/tree*")`)
- `e2e/start-fresh-onboarding.e2e.ts` (per-test kb-tree + conversations/messages routes)
- `e2e/start-fresh-conversations-rail.e2e.ts` (seeded conversations/messages)
- `e2e/mock-supabase.ts` (the base mock **server** — path handlers for
  `/rest/v1/conversations` + `/rest/v1/messages`, with a 404 catch-all)

The stale harness fails at **browser-render time**: the dashboard's new
render-gating fetch (`/api/dashboard/foundation-status`) and the rail's new
`/rest/v1/rpc/list_conversations_enriched` were unmocked → the base server's 404
catch-all (or an unmocked real fetch on a throttled dev server) breaks or wedges
the tests. This is the #5125 class ("a new client fetch needs a harness mock in
the same PR"), but for a *moved* read rather than a purely new one.

Compounding factor: on this machine Playwright could not install any browser
build (`ubuntu26.04-x64`), so the e2e gate was **unrunnable locally** — the only
pre-merge validation was `tsc` + `playwright test --list` (parse/collect) + CI.

## Solution

For any read-source migration (endpoint swap, direct-query → RPC, table rename),
sweep **three** mock layers, not one:

1. **Unit-test mocks** — `vi.mock` factories + component fetch stubs.
2. **e2e per-test browser mocks** — every `page.route("**/<old-path>*")` across
   `e2e/*.e2e.ts`. Grep: `git grep -nE '<old-endpoint>|rest/v1/<old-table>' e2e/`.
3. **e2e base mock server** — `e2e/mock-supabase.ts` path handlers (a Node HTTP
   server with a 404 catch-all). Add a handler for the NEW path mirroring the old
   default (e.g. default the new RPC to `[]` like the old `/rest/v1/conversations`
   → `[]`), so every e2e file gets a safe default and only files seeding a
   *populated* result need a per-test override.

Prefer fixing the **base server default** first — one edit covers every e2e file's
empty-case, shrinking the per-file sweep to just the populated-fixture cases.

Validate without a browser when the local OS can't run Playwright:
`./node_modules/.bin/tsc --noEmit` + `./node_modules/.bin/playwright test <specs> --list`
(parses + collects the test files, catching syntax/import errors) — then rely on
CI's containerized `e2e` job as the authoritative gate.

## Key Insight

The e2e offline-mock harness is a **distinct mock layer** from the unit-test
mocks, with **two sub-layers** of its own (per-test `page.route` + a base mock
*server*). A read-source migration that only sweeps unit-test mocks ships a green
unit suite and a red (or wedged) e2e job. When you MOVE a read, `git grep` the old
endpoint/table across `e2e/` AND read `e2e/mock-supabase.ts`'s path handlers —
the base server's 404 catch-all turns an unmocked new path into a render-time
failure that no unit test and (on an unsupported OS) no local browser can catch.

## Session Errors

- **Data-integrity review subagent exited after its opening thought** (0 tool
  uses). Recovery: `SendMessage` resume made it perform the full review.
  Prevention: when a review agent returns with 0 tool uses and only a preamble,
  treat it as a premature exit and resume it before synthesizing — don't count it
  as "clean." One-off.
- **Playwright refused to install any browser build on `ubuntu26.04-x64`.**
  Recovery: deferred the structural-UI gate to CI, validated via tsc + `--list`.
  Prevention: on an unsupported OS, the structural-UI/e2e gate is CI-authoritative;
  validate harness edits with `playwright test --list` locally instead of failing
  the pipeline. Machine-specific; recurring for this operator's local runs.
- **e2e harness stale after read-source migration** (the subject of this
  learning). Recovery: swept all three mock layers. Prevention: the three-layer
  sweep above.
- **Route-to-definition Edit targeted the bare-repo-root `plugins/soleur/skills/qa/SKILL.md`
  path** → the worktree guardrail hook DENIED it ("Writing to main repo checkout
  while worktrees exist"). Recovery: re-issued against the worktree-absolute path.
  Prevention: already hook-enforced; when routing a learning into a skill from a
  worktree, always use `<worktree-root>/plugins/soleur/…`. One-off.
- **Minor: `grep 'dashboard)/dashboard'` failed on the unescaped `(` under ugrep**,
  and one grep ran from the bare root before a `cd`. Recovery: escaped/quoted +
  chained `cd`. One-off (shell quoting).
