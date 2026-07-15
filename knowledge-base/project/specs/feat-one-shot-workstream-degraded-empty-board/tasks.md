---
title: "Tasks — fix Workstream board false 'No issues' flash on a degraded read"
lane: single-domain
plan: knowledge-base/project/plans/2026-07-15-fix-workstream-degraded-empty-board-false-empty-state-plan.md
brand_survival_threshold: single-user incident
created: 2026-07-15
---

# Tasks

Derived from the deepened plan. TDD: write the RED test for each behavior before the
implementation. Order matters — the `readCurrentRepoUrlResult` contract (1.x) lands before its
consumer (2.x) per phase-order discipline.

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `WorkstreamWriteError` convention (`server/workstream/mutate-workstream-issue.ts:63`).
- [ ] 0.2 Confirm `lib/workstream.ts` is a leaf module (no server-only imports) — client-safe home
      for the new error class.
- [ ] 0.3 Confirm `swr-config.ts` sets no `errorRetryCount`/`shouldRetryOnError` (indefinite retry
      with backoff) — informs the FINDING-1 note and AC7 test harness.
- [ ] 0.4 `git grep -n "getCurrentRepoUrl"` — re-confirm the ~11 call sites across 10 files consume
      only `string | null` (no consumer inspects the null reason).
- [ ] 0.5 Open-review overlap: two-stage `gh issue list --label code-review --json` + standalone
      `jq --arg` sweep over the Files-to-Edit paths.

## Phase 1 — Degrade-aware repo read (contract first)
- [ ] 1.1 RED: `test/current-repo-url.test.ts` — `readCurrentRepoUrlResult` returns
      `{url:null, degraded:true}` on `RuntimeAuthError` (WARN mirror) and on `workspaces` query
      error (ERROR mirror); `{url:null, degraded:false}` on no-repo; `{url, degraded:false}` on a
      normalized url. `getCurrentRepoUrl` wrapper returns `.url` unchanged. (AC4)
- [ ] 1.2 GREEN: add `readCurrentRepoUrlResult` to `server/current-repo-url.ts`; reimplement
      `getCurrentRepoUrl` as a thin wrapper. **Preserve the WARN (tenant-mint `warnSilentFallback`)
      vs ERROR (query-error `reportSilentFallback`) split** (ADR-059).

## Phase 2 — Typed error + accessor throws on degrade
- [ ] 2.1 Add `export class WorkstreamDegradedError extends Error` to `lib/workstream.ts`
      (no `status`/`code`; sole purpose = route `instanceof` skip + mirror-precedes-throw test).
- [ ] 2.2 RED: `test/server/workstream/get-workstream-issues.test.ts` — **switch the `vi.mock`
      from `getCurrentRepoUrl` to `readCurrentRepoUrlResult`**; then:
      - P2 degrade (`{degraded:true}`) → throws `WorkstreamDegradedError` AND
        `reportSilentFallback({feature:"workstream", op:"repo-unresolved"})` fired **before** the
        throw (spy). (AC1)
      - P1 (`installationId===null` on connected repo) → `reportSilentFallback({op:"no-installation"})`
        AND throws. (AC2)
      - no-repo → `[]`; connected repo with `listRepoIssues → []` → `[]` (no throw). (AC3)
- [ ] 2.3 GREEN: in `get-workstream-issues.ts` — consume `readCurrentRepoUrlResult`; on
      `degraded` add the workstream-scoped mirror (`op:"repo-unresolved"`) then throw; on P1 keep
      the existing mirror then throw; update the file-header "Empty-vs-throw" doc block
      (`[]` ⟺ no-repo OR genuine-zero-issue; every degrade throws).

## Phase 3 — Route + agent-tool surfaces
- [ ] 3.1 RED: `test/workstream-issues-route.test.ts` — degrade → HTTP **502**
      `{error:"workstream_query_error"}` (mock `resolveWorkstreamBoardMeta` as resolving so
      `Promise.all` rejects on the accessor throw); route does NOT double-`captureException` a
      `WorkstreamDegradedError`. (AC5)
- [ ] 3.2 GREEN: `route.ts` GET catch — `if (!(e instanceof WorkstreamDegradedError)) captureException(...)`; still 502.
- [ ] 3.3 RED+GREEN: `test/workstream-tools.test.ts` — degrade makes `workstream_issues_list`
      return `isError:true` (was `{issues:[]}`). No production change (tool already try/catches). (AC6)

## Phase 4 — Client guard (FINDING 2)
- [ ] 4.1 RED: RTL test under `test/components/workstream/` (jsdom `.test.tsx` include glob) — a
      create attempt during a first-load degrade does NOT resurrect `<EmptyState>`; New-Issue
      button disabled while `error && !data`. Use shared `SwrTestProvider`
      (`shouldRetryOnError:false`, `dedupingInterval:0`); drive failure via `global.fetch → {ok:false}`;
      do NOT race `mutate()`. (AC7)
- [ ] 4.2 GREEN: `workstream-board.tsx` — `const firstLoadFailed = error != null && data == null;`
      `disabled={readOnly || firstLoadFailed}` on the toolbar `+ New Issue` (:528) and the
      `EmptyState` button (:642). No other client change.

## Phase 5 — Verify + deferrals
- [ ] 5.1 `tsc --noEmit` clean; run the edited vitest suites (per `package.json scripts.test`).
- [ ] 5.2 `git diff --stat` — board diff limited to the FINDING-2 guard; everything else server+test.
- [ ] 5.3 File the two deferral issues (labels verified via `gh label list`): (1) board read-path
      reconnect affordance (FINDING 1); (2) mirror the generic non-403 GitHub LIST failure
      (`github-api.ts:238-245`, obs G1). Use `Ref #N` / tracking, not `Closes`.
- [ ] 5.4 PR body: `Closes` the originating bug; note "pre-existing (not PR #6308)".
