# Tasks — fix-live-verify-rail-budget

Plan: `knowledge-base/project/plans/2026-10-06-fix-live-verify-rail-budget-plan.md`
Issue: #9581 (Closes)

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [ ] 1.1 Create `apps/web-platform/test/live-verify/rail-assert-verdict.test.ts`
  covering every verdict path with synthesized fake-Page / fake-supabase
  fixtures only (`cq-test-fixtures-synthesized-only`):
  - [ ] 1.1.1 row visible on tick 1 → `appeared` `via=direct`; `page.reload`
    never invoked
  - [ ] 1.1.2 visible on tick N inside observe window → `via=direct`, no reload
  - [ ] 1.1.3 visible only after `page.reload()` → `via=reload`; PASS detail
    contains `via=reload` and `elapsed=`
  - [ ] 1.1.4 never visible + RPC membership `no` (or resolved `repoUrl=null`)
    → `absent` → `RESULT: FAIL —` with `rpc_row=no`; `page.reload` never
    called (fail-fast)
  - [ ] 1.1.5 never visible through both windows + `rpc_row=yes` → FAIL
    carries `rpc_row=yes` + `rail_state=<branch>`
  - [ ] 1.1.6 RPC probe / `page.request` throws → `rpc_row=unreadable:<…>`,
    reload still runs; diagnostics never throw
  - [ ] 1.1.7 `page.reload()` throws nav-timeout but `isVisible()` keeps
    resolving → polling continues; `reload_err=<name>` in FAIL diagnostics
  - [ ] 1.1.8 `isVisible()` throws target-closed class → `CANT-RUN` carrying
    the waitFailureState diagnostic
  - [ ] 1.1.9 verdict→`emitLine` output matches
    `/^RESULT: (PASS —|FAIL —|CANT-RUN:)/`
  - [ ] 1.1.10 `rail_state` enumeration: `conversations-rail-error` → `error`,
    empty-state testid → `empty`, K other anchors → `rows:K`, wrapper absent
    → `rail-absent`
- [ ] 1.2 Extend `apps/web-platform/test/live-verify/no-bare-visibility-wait.test.ts`:
  - [ ] 1.2.1 assert the rail-verdict call site routes through the exported
    seam (`assertRailRowVisible`) — wire pin
  - [ ] 1.2.2 assert no `railRow.waitFor(` (and no new bare
    `input.waitFor`/`page.waitForSelector`) returns
  - [ ] 1.2.3 assert the new suite's `it(` floor from this file
    (cross-file anti-vacuity split, matching the established pattern)

## Phase 2 — Seam + mapper (run.ts)

- [ ] 2.1 Add exported `assertRailRowVisible` seam in
  `apps/web-platform/scripts/live-verify/run.ts`:
  - Phase A: poll `railRow.isVisible()` ~1.5s interval up to ~45s
  - scope probe (~10s bounded each, FIELD_TIMEOUT_MS race pattern):
    `page.request.get(<prod>/api/workspace/active-repo)` →
    `{workspaceId, repoUrl}`; `supabase.rpc("list_conversations_enriched",
    { p_repo_url, p_workspace_id, p_archive:"active", p_status:null,
    p_domain:null, p_limit:15 })` membership check →
    `rpc_row = yes|no|unreadable:<reason>`
  - `rpc_row=no` or `repoUrl=null` → `absent` immediately (no reload)
  - otherwise `page.reload({waitUntil:"domcontentloaded",
    timeout: 30_000})` — the d.ts default is `0` = no timeout; the explicit
    bound is mandatory (thrown reload → `reload_err` diagnostic, keep
    polling) + Phase B poll to ~45s
  - `isVisible()` target-closed/context-destroyed → `unverifiable`
  - one named total ceiling (`RAIL_ASSERT_TOTAL_BUDGET_MS` = 150s (raised at review: worst-case observe+probes+reload+observe = 140s))
- [ ] 2.2 Add `railRowState` collector (error | empty | rows:n | rail-absent |
  unreadable) — never-throws, bounded, same `safe()` discipline as
  `waitFailureState`
- [ ] 2.3 Add pure `railVerdictToResult` mapper → `Result`:
  `appeared` → PASS detail `…appeared in the rail (via=<…> elapsed=<N>s
  checks=<n>)`; `absent` → FAIL detail `…persisted but did NOT appear in the
  rail within <total>s budget (checks=<n> reloads=<m> rail_state=<…>
  rpc_row=<…> active_repo=<…>) (the #5391/#5436 class, #9581)`;
  `unverifiable` → CANT-RUN `rail-check:<waitFailureState diagnostic>`
- [ ] 2.4 Replace the `railRow.waitFor` block at ~:738-745 with the seam call;
  keep `RESULT:` emit shapes byte-compatible; keep teardown ordering
  (verdict → `teardownConversation` → emit)

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/live-verify/` green (NOT `bun test` — bunfig `pathIgnorePatterns`)
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [ ] 3.3 `eslint` clean on touched files
- [ ] 3.4 Confirm zero edits under `.github/workflows/` (wire format is
  unchanged by construction)

## AC map

- AC1 → 2.1, 1.1.1-1.1.3
- AC2 → 2.1 (probe + fail-fast), 1.1.4
- AC3 → 2.3, 1.1.3
- AC4 → 2.3/2.4, 1.1.9, 3.4
- AC5 → 2.2/2.3, 1.1.5-1.1.7, 1.1.10
- AC6 → 2.1, 1.1.8
- AC7 → 1.1, 1.2
- AC8 → 3.1-3.3
- AC9 → 2.4
