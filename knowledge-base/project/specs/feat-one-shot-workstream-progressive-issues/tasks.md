---
title: "Tasks — perf: stream the Workstream issues feed progressively"
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-30-perf-workstream-progressive-issues-feed-plan.md
brand_survival_threshold: single-user incident
created: 2026-09-30
---

# Tasks

Derived from the plan. TDD: write the RED test for each behavior before the
implementation. Phase order is dependency order — the feed vocabulary (1.x) lands
before the route arm (2.x), which lands before the client wiring (3.x).

## Phase 0 — Preconditions

- [ ] 0.1 Re-read `server/workstream/get-workstream-issues.ts` header block —
      the empty-vs-throw + mirror-precedes-throw contract is load-bearing and
      must survive the `resolveBoardReadContext` extraction verbatim.
- [ ] 0.2 Confirm `swr` exports `useSWRConfig` + `ScopedMutator` in the installed
      version (`grep useSWRConfig apps/web-platform/node_modules/swr/dist/index/index.d.ts`).
- [ ] 0.3 Confirm `components/dashboard/workstream-nav-badge.tsx` still shares
      `swrKeys.workstreamIssues()` with `jsonFetcher` — the JSON arm must keep
      working for it.
- [ ] 0.4 Confirm `listRepoIssues` callers are only `get-workstream-issues.ts` +
      tests before adding the `onBatch` param (`git grep -n listRepoIssues`).

## Phase 1 — Feed vocabulary + streamed accessor (server, RED first)

- [ ] 1.1 RED: `test/workstream-feed.test.ts` — `formatWorkstreamSseFrame` /
      `parseWorkstreamSseChunks` round-trip; rest-tail across chunk boundary;
      malformed frame dropped not thrown; `mergeStreamedIssues` upserts by id and
      preserves `SOLAA-N*` temps; `applyStatusOverrides` patches status+live.
- [ ] 1.2 GREEN: `lib/workstream-feed.ts` — `WorkstreamFeedEvent` union
      (meta/issues/statuses/done/error), format/parse helpers, merge + override
      helpers. Client-safe leaf: imports types from `./workstream` only.
- [ ] 1.3 RED: `test/server/workstream/get-workstream-issues.test.ts` — event
      ordering meta → issues* → (statuses?) → done; degrade throws BEFORE first
      emit; honest-empty emits meta+done only; `statuses` lists ONLY changed ids;
      `openTruncated` propagates to `done`.
- [ ] 1.4 GREEN: `server/github-read-tools.ts` — optional `onBatch` on
      `listRepoIssues`/`pageIssuesInto` (one invoke per REST page, non-PR items).
      Existing signature/return unchanged.
- [ ] 1.5 GREEN: `server/workstream/get-workstream-issues.ts` — extract
      `resolveBoardReadContext` (mirrors moved, not duplicated); add
      `streamWorkstreamIssues(userId, emit)` with the parallel
      `readBoardStatuses` + changed-only `statuses` reconcile; keep
      `getWorkstreamIssues` byte-identical behavior (agent tool untouched).

## Phase 2 — Route SSE arm

- [ ] 2.1 RED: `test/workstream-issues-route.test.ts` — `Accept:
      text/event-stream` → SSE content-type + decodable frames; default Accept →
      unchanged JSON (existing tests stay green); pre-stream degrade → 502 JSON;
      mid-stream throw → `error` frame + `captureException`.
- [ ] 2.2 GREEN: `app/api/workstream/issues/route.ts` — Accept negotiation;
      resolution before Response construction (real 401/502 preserved);
      `ReadableStream` + `text/event-stream; charset=utf-8` +
      `Cache-Control: no-cache, no-transform`; ~90 s cap mirroring
      `SUPPORT_TURN_MAX_MS`; terminal-frame close.

## Phase 3 — Client streaming fetcher + board wiring

- [ ] 3.1 RED: `test/components/workstream/workstream-board.test.tsx` (or new
      sibling file under the same dir) — mock `fetch` returning a
      `ReadableStream` of frames: cards render after the FIRST `issues` frame
      with stream still open (AC3); Refresh `loading` until `done`; `?issue=N`
      late-arriving deep-link shows loading not notFound (AC8); mid-stream error
      → partial board + amber banner (AC7); zero-issue `done` → EmptyState
      (AC10); `SOLAA-N*` temp survives a mid-stream commit (AC9).
- [ ] 3.2 GREEN: `fetchWorkstreamIssuesFeed` in `lib/workstream-feed.ts` —
      `Accept: text/event-stream`, `res.body.getReader()` + `TextDecoder` +
      `parseWorkstreamSseChunks`; non-SSE content-type falls back to
      `res.json()`; `!res.ok` throws (jsonFetcher parity); stream ending without
      `done` throws (truncated feed is never silent-complete).
- [ ] 3.3 GREEN: `components/workstream/workstream-board.tsx` — fetcher swap
      via `useSWRConfig()`-bound `scopedMutate` progressive commits
      (`revalidate: false`); `IssueDetailSheet` `notFound`/`loading` gated on
      `!isValidating`.
- [ ] 3.4 `lib/swr-config.ts` — comment on `workstreamIssues` noting the
      negotiated SSE fetcher (key tuple unchanged).

## Phase 4 — Verify + deferral issues

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.2 vitest green for touched suites: `workstream-feed`,
      `get-workstream-issues`, `workstream-issues-route`, board tests, plus
      `dashboard-mount-fetch-dedup` (AC11) and `workstream-tools` (AC12).
- [ ] 4.3 Dev-server smoke: `/dashboard/workstream` shows progressive card fill
      with Refresh spinning until done (screenshot or probe record in PR).
- [ ] 4.4 File the two Deferral Tracking issues (labels `domain/engineering`,
      `type/feature`; milestone `Phase 4: Validate + Scale`): upstream parallel
      page fan-out; MobileBoard sheet-gating audit.
- [ ] 4.5 `next build` clean.
