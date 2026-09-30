---
title: "perf: stream the Workstream issues feed progressively instead of one bulk JSON read"
type: perf
date: 2026-09-30
slug: perf-workstream-progressive-issues-feed
branch: feat-one-shot-workstream-progressive-issues
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# perf: stream the Workstream issues feed progressively instead of one bulk JSON read

## Overview

The Workstream board (`/dashboard/workstream`) renders its shell — nav, heading,
search/filter toolbar, Refresh button, skeleton columns — quickly, then leaves the
board body in that skeleton state for the ENTIRE duration of one bulk
`GET /api/workstream/issues` read. That read is a serial upstream chain: workspace
repo resolution → App-installation resolution → `listRepoIssues` (up to 20
sequential REST pages of open issues + 3 of closed) → `fetchBoardStatusMap` (up to
10 sequential GraphQL pages) → bot-slug resolution. Nothing reaches the client
until all of it resolves.

This plan converts the single bulk read into a progressive feed **over the same
endpoint and the same SWR key**: the route negotiates `text/event-stream` on
`Accept`, streams one frame per upstream GitHub page as it resolves, and the client
commits each batch into the existing `{issues, board}` cache entry. Columns fill in
gradually, the Refresh button's existing `isValidating`-driven spinner stays active
for the whole feed, and the final committed payload is byte-shape-identical to
today's `{issues, board}` — every write-path `mutate` reconciler and the shared-key
nav badge are untouched.

## Problem Statement / Motivation

Operator report: `app.soleur.ai/dashboard/workstream` sits on skeleton cards +
a spinning "Refreshing…" button for a long time (screenshot
`/home/jean/Pictures/screenshot-2026-09-29_20-09-27.png`). Verified against code —
the operator's guess ("fetches the GitHub issues in one go") is **correct in shape**:
the board shows nothing until a single awaited response carries every issue.

Cost anatomy (measured by reading the code, not asserted):

- `listRepoIssues` (`server/github-read-tools.ts`) pages REST
  `?state=open&per_page=100&page=N` **sequentially**, cap `MAX_OPEN_PAGES = 20`
  (2 000-issue headroom — the dogfood repo's open count is in the thousands), then
  `state=closed` cap `MAX_CLOSED_PAGES = 3`. Each `githubApiGet` awaits the previous
  page — up to ~23 serial GitHub calls.
- `fetchBoardStatusMap` then walks the org Project v2 board over GraphQL,
  `items(first:100, after:cursor)` sequential, cap `MAX_BOARD_STATUS_PAGES = 10`.
- All of it happens inside `getWorkstreamIssues` before the route can write a
  single byte. At ~300–700 ms per GitHub round-trip the feed is a 5–20 s skeleton.

Adjacent work checked and NOT covering this: #9178 /
`2026-09-28-perf-dashboard-fcp-redux-cwv-observability-plan.md` fixed mount-path
fan-out dedup (the board already uses a shared `swrKeys.workstreamIssues()` SWR
key plus the `usePostFcp`-gated badge) and landed field RUM. The workstream feed itself is a
route-primary content fetch — outside that census's scope (`SCAN_DIRS` in
`test/dashboard-mount-fetch-dedup.test.tsx` does not include
`components/workstream`).

## Research Reconciliation — Spec vs. Codebase

| Operator-premise claim | Codebase reality | Plan response |
|---|---|---|
| "It fetches the GitHub issues in one go and it takes time" | True — one SWR GET → one awaited `Promise.all` → serial upstream paging | Convert that same read to a streamed feed |
| "Load the page shell first (fast first paint)" | Already true — `page.tsx` awaits only cookie-session auth; shell + skeleton paint immediately (screenshot confirms) | No work; verified, not rebuilt |
| "Load the issues gradually" | Not possible today — `jsonFetcher` awaits the whole body | SSE frames + progressive `mutate` commits |
| "Refreshing button active at the top" | Already wired — `loading={isValidating}` is true for the whole in-flight fetch | Kept; the stream keeps `isValidating` true until `done` |

## Research Insights

**Relevant file paths:**

- `apps/web-platform/app/(dashboard)/dashboard/workstream/page.tsx` — server
  component; auth gate + `<Suspense>` (required for `useSearchParams`). No issues
  await — TTFB is NOT the bottleneck.
- `apps/web-platform/components/workstream/workstream-board.tsx` — client board;
  `useSWR(swrKeys.workstreamIssues(), jsonFetcher)`; `!data` → `BoardSkeleton`;
  toolbar + Refresh (`loading={isValidating}`) render regardless.
- `apps/web-platform/app/api/workstream/issues/route.ts` — GET/POST; GET =
  `Promise.all([getWorkstreamIssues, resolveWorkstreamBoardMeta])` →
  `{issues, board}` JSON; 401/502 semantics (`WorkstreamDegradedError` skips
  re-capture).
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — the shared
  accessor (also called directly by `server/workstream/workstream-tools.ts`, the
  agent `workstream_issues_list` tool). Empty-vs-throw contract is load-bearing:
  `[]` ONLY for no-repo / genuinely-zero; every degrade throws
  `WorkstreamDegradedError` after a Sentry mirror (mirror-precedes-throw).
- `apps/web-platform/server/github-read-tools.ts` — `listRepoIssues` /
  `pageIssuesInto` (sequential REST pages), `fetchBoardStatusMap` (sequential
  GraphQL pages), `BOARD_PER_PAGE = 100`, `MAX_OPEN_PAGES = 20`,
  `MAX_CLOSED_PAGES = 3`, `MAX_BOARD_STATUS_PAGES = 10`.
- `apps/web-platform/lib/workstream.ts` — pure leaf (client-safe):
  `WorkstreamIssue`, `deriveColumn` (boardStatus wins → label/state fallback,
  ADR-097), `deriveLive` (= column === in_progress), `boardStatusToWorkstreamStatus`,
  `WorkstreamDegradedError`.
- `apps/web-platform/lib/swr-config.ts` — `swrKeys.workstreamIssues()` =
  `["/api/workstream/issues"]`; `swrConfig` = `dedupingInterval: 2000`,
  `errorRetryCount: 3`, `revalidateOnFocus: true`; `ScopedMutator` convention via
  `useSWRConfig().mutate` (`clearSwrCache` precedent).
- `apps/web-platform/components/dashboard/workstream-nav-badge.tsx` — **shares
  the same SWR key** with `jsonFetcher` (post-FCP gated). Any fetcher change must
  keep the `{issues, board}` resolved shape or the badge breaks.
- Prior art: `app/api/support/route.ts` + `lib/support-sse.ts` — SSE over a
  `ReadableStream` route (`text/event-stream`, `Cache-Control: no-cache,
  no-transform`), `formatXxxSseFrame`/`parseXxxSseChunks` pure helpers, terminal-
  frame close + hard cap (`SUPPORT_TURN_MAX_MS`), client `res.body.getReader()` +
  `TextDecoder` in `components/support/use-support-chat.ts`.

**Applicable institutional learnings:**

- `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` — declare frame
  semantics explicitly (delta-vs-cumulative ambiguity caused duplicated chat
  output). This feed uses **delta `issues` frames with upsert-by-id**; never
  cumulative snapshots mid-stream.
- `2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md` —
  `error && data` keeps stale data + amber banner; the mid-stream-error arm
  deliberately lands on this same split.
- `2026-07-15-fix-workstream-degraded-empty-board-false-empty-state-plan.md` —
  the sibling on this surface: empty-vs-throw invariants, mirror-precedes-throw,
  `firstLoadFailed`/`refreshFailed` split this design reuses verbatim.
- `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`
  — the consumer that *pins* the shared key (nav badge) is invisible to a
  route-shaped grep; both fetcher call sites enumerated.
- Constitution line 46: "design for progressive/gradual rendering from the start"
  — the precedent this plan follows.

**Premise Validation (Phase 0.6):** #9178 verified OPEN (`gh issue view 9178`) —
its scope is mount-fan-out dedup + CWV RUM, not the workstream feed read; no
conflict. All cited paths exist on this branch (`page.tsx`, `workstream-board.tsx`,
`app/api/workstream/issues/`). The UI exists and behaves as described (screenshot +
code agree). Proposed mechanism (SSE transport for a data feed) checked against the
ADR corpus: ADR-113 already established dedicated-SSE-transport for
browser→server pushes (support chat, `server/inngest/stream-detach.ts` is the other
stream prior art); no ADR lists SSE-on-a-read-route as rejected.

**Property List (Phase 0.6b):**

1. P1 — Shell paints fast: ALREADY TRUE (`page.tsx` awaits auth only; screenshot
   shows skeleton + toolbar live).
2. P2 — Issues render incrementally as upstream pages arrive (the new property).
3. P3 — A visible "still loading" signal persists for the whole feed
   (`isValidating` + Refresh spinner already wired; keep).
4. P4 — Degraded reads stay loud (empty-vs-throw + `error && data` banner
   semantics preserved end-to-end; a TRUNCATED stream must never read as a
   finished feed).
5. P5 — The final committed board state is IDENTICAL to today's bulk result
   (same `{issues, board}` shape, same `deriveColumn` board-precedence).

**Cut List (Phase 0.6b):**

- Shell-first-paint / SSR-streaming rework — CUT. P1 is already bought by the
  current `page.tsx` (Suspense + client SWR); nothing to rebuild.
- New "still loading" indicator — CUT. `loading={isValidating}` on Refresh +
  the skeleton already cover P3.
- Per-column or split endpoints — CUT. Would fragment the shared SWR key the nav
  badge piggybacks on (P5/cache-coherence); one stream over the existing key
  covers it.
- New data store / server-side issue cache — CUT. No property requires it; adds
  a staleness boundary and an Encryption-Posture surface for zero gain.

**Measurement (Phase 0.6c):** the claimed expensive block is upstream paging —
`grep -n "MAX_OPEN_PAGES\|MAX_CLOSED_PAGES\|MAX_BOARD_STATUS_PAGES\|per_page"
apps/web-platform/server/github-read-tools.ts` → 20+3+10 serial calls worst case.
The plan does not claim to shorten total upstream time (sequential pages stay
sequential); it claims first-contentful-issue arrives after ~1 page instead of
~23+10.

## Proposed Solution

Stream the existing feed. `GET /api/workstream/issues` gains a second response
shape negotiated by `Accept: text/event-stream` — a Server-Sent-Events stream of
small frames (the support-chat transport convention, ADR-113 prior art). The board
swaps `jsonFetcher` for a streaming fetcher on the SAME `swrKeys.workstreamIssues()`
key; each `issues` frame merges into the SWR cache via the hook-scoped mutator
(`revalidate: false`) so columns fill while the fetch is still in flight. The
fetcher resolves the SAME `{issues, board}` object at stream end, so the SWR commit
is identical to today's and every write reconciler (`mutate(cur => …)` sites in
`workstream-board.tsx`) works unchanged.

The default `Accept` arm stays `application/json` `{issues, board}` — the nav
badge's `jsonFetcher`, the existing route test, and any out-of-tree consumer are
untouched.

### Frame vocabulary (delta semantics — each frame carries only new information)

```text
data: {"type":"meta","board":{"onKanbanOrg":bool,"projectWritable":bool}}
data: {"type":"issues","issues":[WorkstreamIssue, ...]}      // one per upstream page
data: {"type":"statuses","overrides":[{"id":"123","status":"in_review","live":false}, ...]}
data: {"type":"done","openTruncated":false}                  // terminal
data: {"type":"error","code":"workstream_query_error"}       // terminal, mid-stream failure
```

- `meta` — first frame; board-precedence meta (same payload as today's `board`).
- `issues` — the WorkstreamIssue[] mapped from ONE upstream REST page (open pages
  in order, then closed pages). **Delta with upsert-by-id**; never a cumulative
  snapshot (learning 2026-04-13). Frames with zero issues (all-PR page) are not
  emitted client-side (they carry nothing).
- `statuses` — emitted at most once, when `fetchBoardStatusMap` resolves AFTER
  issues were already streamed: minimal `{id, status, live}` overrides for the
  emitted issues whose derived column CHANGED once board Status (ADR-097
  precedence) is applied. Pages emitted after the map lands arrive with
  `boardStatus` already applied — no override needed for them.
- `done` — terminal success; `openTruncated` mirrors the existing
  `MAX_OPEN_PAGES`-cap warning (`list-repo-issues-open-cap` Sentry mirror
  unchanged, server-side).
- `error` — terminal failure after bytes already flowed (a pre-stream failure —
  auth, repo/installation degrade — still returns a real non-200 status, never a
  stream).

### Client merge semantics

The fetcher accumulates `{issues: Map<id, WorkstreamIssue>, board}` locally. On
each `issues`/`statuses` frame it `mutate`s the shared key with the accumulated
snapshot — preserving any **optimistic temp cards** (`id` not a positive integer —
the `SOLAA-N*` create cards) already in `cur.issues`. Commits with an empty
accumulator are skipped so `data` stays `undefined` (skeleton) until the first
real issue — an early `meta`-only commit would flash a false EmptyState.

Terminal rules: `done` → resolve `{issues, board}`; `error` frame OR stream ending
without `done` (truncated response) → throw so SWR records `error` — accumulated
partials already committed surface as the existing `error && data` amber
"showing the last loaded issues" banner, or `error && !data` → `ErrorCard` on a
cold failure. A truncated stream can never masquerade as a complete feed (P4).

## Technical Approach

### Architecture

1. **`server/github-read-tools.ts`** — add an optional `onBatch?: (items:
   BoardIssueInput[]) => void` parameter to `listRepoIssues` and thread it through
   `pageIssuesInto` (invoked once per fetched REST page with that page's
   non-PR items). Additive; existing signature and return value unchanged; the
   only other consumer is the tests file (cross-consumer grep clean —
   `get-workstream-issues.ts` is the sole production caller).
2. **`server/workstream/get-workstream-issues.ts`** —
   - Extract the shared resolution preamble into
     `resolveBoardReadContext(userId)` → `{ kind: "empty" } | { kind: "ok",
     owner, repo, installationId, botSlug }`. It performs
     `readCurrentRepoUrlResult` → `parseConnectedRepo` →
     `resolveInstallationId`/`resolveEffectiveInstallationId` → `resolveBotSlug`,
     keeps the SAME degrade throw sites and their Sentry mirrors (moved into the
     helper, not duplicated — mirror-precedes-throw is preserved verbatim).
   - `getWorkstreamIssues` calls it, then runs `listRepoIssues` +
     `readBoardStatuses` + map exactly as today (unchanged downstream).
   - New `streamWorkstreamIssues(userId, emit)`:
     a. `ctx = await resolveBoardReadContext(userId)` — throws BEFORE the first
        emit (caller maps to a real 502, not a stream).
     b. `empty` → emit `meta` (board meta via `resolveWorkstreamBoardMeta`) +
        `done` and return (honest empty board).
     c. Emit `meta`; kick `readBoardStatuses` off in parallel (`let boardMap`).
     d. `await listRepoIssues(installationId, owner, repo, onBatch)` where the
        batch callback maps each item via `githubIssueToWorkstreamIssue` with
        `boardStatus: boardMap?.get(number)` when the map has landed, collects
        `{input, issue}` pairs of everything emitted, and `emit`s an `issues`
        frame per non-empty page.
     e. When `boardMap` resolves, recompute column+`live` for already-emitted
        inputs (`{...input, boardStatus: map.get(input.number)}`) and emit ONE
        `statuses` frame listing only the overrides that changed.
        Board-map failure keeps the existing degrade path (`reportSilentFallback`
        → null map → label derivation — unchanged).
     f. Emit `done` with the `openTruncated` flag.
     g. A throw inside the loop → emit `error` frame, re-throw for the route's
        Sentry capture (the HTTP status is already committed; the frame + the
        server-side capture are the observability path).
   - The agent tool (`workstream-tools.ts`) keeps calling `getWorkstreamIssues` —
     zero tool change.
3. **`app/api/workstream/issues/route.ts`** — in GET, after `verifiedUserId`:
   `Accept` containing `text/event-stream` → SSE arm; else the existing JSON arm
   untouched. The SSE arm awaits `resolveBoardReadContext`-equivalent resolution
   (so 401/502 arrive as real status codes — `WorkstreamDegradedError` → 502
   `{error:"workstream_query_error"}` with the re-capture skip preserved), then
   returns `new Response(ReadableStream)` with `Content-Type:
   text/event-stream; charset=utf-8`, `Cache-Control: no-cache, no-transform`
   (support-route header set). The stream writes frames via a
   `formatWorkstreamSseFrame` helper, holds open until a terminal frame
   (`done`/`error`) or a hard cap (~90 s, mirroring `SUPPORT_TURN_MAX_MS`'s
   backstop role), then closes.
4. **`lib/workstream-feed.ts`** (NEW — client-safe leaf, mirrors
   `lib/support-sse.ts`): `WorkstreamFeedEvent` union, `formatWorkstreamSseFrame`,
   `parseWorkstreamSseChunks` (rest-tail threading; malformed frames dropped),
   `mergeStreamedIssues(current, partial)` (upsert-by-id preserving optimistic
   `SOLAA-N*` temps), and `applyStatusOverrides(issues, overrides)`.
5. **`lib/swr-config.ts`** — comment update on `workstreamIssues` noting the
   negotiated SSE fetcher; the key tuple is UNCHANGED.
6. **`components/workstream/workstream-board.tsx`** —
   - `useSWRConfig()` for the cache-scoped `mutate`; the SWR call becomes
     `useSWR(swrKeys.workstreamIssues(), (key) => fetchWorkstreamIssuesFeed(key,
     partial => void scopedMutate(swrKeys.workstreamIssues(), cur =>
     mergeStreamedIssues(cur, partial), { revalidate: false })))`.
   - `fetchWorkstreamIssuesFeed` (in `lib/workstream-feed.ts`): fetch with
     `Accept: text/event-stream`; non-SSE `content-type` → `res.json()` fallback
     (defensive against an older deploy/proxy); `!res.ok` → throw (jsonFetcher
     parity); else reader/decoder/`parseWorkstreamSseChunks` loop applying the
     terminal rules above.
   - `IssueDetailSheet` gating: `notFound` becomes `activeId != null &&
     !isValidating && issues != null && selected == null` (a deep-linked
     `?issue=N` must not flash "not found" while its page hasn't streamed yet);
     `loading` covers `selected == null && (issues == null || isValidating)`.

### Implementation Phases

#### Phase 1 — Feed vocabulary + streamed accessor (server, test-first)

- RED: `test/workstream-feed.test.ts` — frame round-trip, rest-tail across chunk
  boundaries, malformed-frame drop, `mergeStreamedIssues` upsert + temp
  preservation, `applyStatusOverrides`.
- GREEN: `lib/workstream-feed.ts`.
- RED: `test/server/workstream/get-workstream-issues.test.ts` — event ordering
  (meta → issues* → [statuses?] → done), degrade throws before first emit,
  honest-empty emits meta+done, `statuses` overrides only for changed columns,
  open-truncation flag.
- GREEN: `resolveBoardReadContext` extraction + `streamWorkstreamIssues` +
  `onBatch` in `github-read-tools.ts`; `getWorkstreamIssues` behavior identical
  (existing tests stay green unmodified).

#### Phase 2 — Route SSE arm

- RED: `test/workstream-issues-route.test.ts` — `Accept: text/event-stream` →
  `content-type` SSE + decodable meta/issues/done frames; default Accept →
  unchanged JSON (existing test stays green); pre-stream degrade → 502 JSON (not
  a stream); mid-stream accessor throw → `error` frame + `captureException`.
- GREEN: negotiation + ReadableStream arm + cap timer.

#### Phase 3 — Client streaming fetcher + board wiring

- RED: board RTL test — mock `fetch` returning a `ReadableStream` of frames;
  assert columns render after the first `issues` frame while the stream is still
  open; `?issue=N` deep-link to a late-arriving issue does NOT flash notFound;
  mid-stream `error` keeps partial board + amber banner; zero-issue `done` →
  EmptyState; Refresh button `loading` for the whole feed.
- GREEN: `fetchWorkstreamIssuesFeed` + the board wiring + `notFound`/`loading`
  gating.

#### Phase 4 — Verify

- `tsc --noEmit`, the touched vitest suites green, `next build` clean.
- Probe/manual: `doppler run -c dev --` dev server, navigate to
  `/dashboard/workstream`, confirm progressive fill + spinner lifecycle.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **Server-side parallel page fan-out, keep single JSON** | **Rejected as the fix; deferred as a follow-up.** REST pages are number-addressed (Link `last` reveals the tail), so pages 2..N could fan out concurrently — that cuts wall-clock ~5× but still paints nothing until the last page. Does not satisfy the "load gradually" ask. Compatible follow-up to the stream (emit on each completed parallel page); tracked in Deferral Tracking. |
| **Cursor/page query-param pagination + client auto-advance** (`useSWRInfinite` or a loop) | **Rejected.** N serial client→server round-trips, each re-running the resolution preamble; reshapes the SWR entry into a pages array → every write-path `mutate` call site (~8) changes. Same upstream serialization, more plumbing. |
| **NDJSON instead of SSE frames** | **Rejected (in-repo convention).** Functionally equivalent, but `text/event-stream` + `data:` frames is the established transport here (`lib/support-sse.ts`, support route, ADR-113) — consistency beats marginal byte savings. |
| **Always-SSE (no JSON arm)** | **Rejected.** The nav badge shares the key with `jsonFetcher` (`res.json()` on an SSE body throws), the existing route test asserts JSON, and plain `curl`/out-of-tree consumers get a worse contract. Content negotiation keeps both honest. |
| **Board-status map first, then stream** | **Rejected.** `fetchBoardStatusMap` is itself up to 10 sequential GraphQL pages — gating issues behind it reproduces the stall for exactly the dogfood org where board precedence applies. Parallel + one `statuses` reconcile frame is strictly better; transient label-derived placement only shows while the spinner is already communicating "still loading". |
| **Cache the feed server-side (Supabase/KV)** | **Rejected.** New store + staleness boundary + Encryption-Posture surface for no property in the list. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the Workstream board showing a
  partial issue set as if complete (e.g. a silently truncated stream with no
  spinner/banner), or cards parked in wrong columns when the `statuses` reconcile
  is dropped — a silent under-count on the founder's triage surface.
- **If this leaks, the user's data is exposed via:** the same authenticated feed
  it already flows over — the change moves no new data class and adds no new
  reader; the risk is a stream bug extending a session's read window, not a new
  disclosure path.
- **Brand-survival threshold:** `single-user incident` — same surface and same
  reasoning as `2026-07-15-fix-workstream-degraded-empty-board` (a board that
  lies about its contents is a trust defect on the primary triage surface).

CPO sign-off required at plan time before `soleur:work` begins (pipeline context:
Product/UX Gate ran advisory auto-accepted; `soleur:engineering:review:
user-impact-reviewer` runs at review time to enumerate failure modes against the
diff — specifically the truncated-stream-as-complete and reconcile-drop cases).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — SSE arm negotiates cleanly:** `GET /api/workstream/issues` with
      `Accept: text/event-stream` returns `content-type: text/event-stream` and a
      decodable `meta` → `issues*` → `done` frame sequence; with a plain Accept it
      returns the unchanged `{issues, board}` JSON (existing route test stays
      green).
- [ ] **AC2 — pre-stream failures keep real status codes:** unauthenticated →
      401; `WorkstreamDegradedError` from resolution → 502
      `{error:"workstream_query_error"}` with NO double `captureException`
      (mirror-precedes-throw unchanged).
- [ ] **AC3 — progressive commit:** the board RTL test renders issue cards after
      the FIRST `issues` frame while the stream is still open, and the Refresh
      button shows `loading` until `done`.
- [ ] **AC4 — identical final state:** given a fixed issue set + board map, the
      streamed result deep-equals the bulk accessor's `{issues, board}` (same
      `deriveColumn`/`deriveLive` results — pin via a test feeding both paths the
      same fixtures).
- [ ] **AC5 — statuses reconcile, minimally:** `statuses` overrides apply only to
      already-emitted issues whose column/`live` changed under board precedence;
      issues streamed after the map lands carry the board status already applied
      (no override frame for them). Assert the frame lists ONLY changed ids.
- [ ] **AC6 — truncated stream is loud:** a stream that ends without `done`
      (network drop / cap) rejects the fetcher → `error && data` amber banner
      with partial issues kept, or `error && !data` → `ErrorCard` — never a
      silently-complete board.
- [ ] **AC7 — mid-stream error semantics:** an `error` frame after partial issues
      keeps them rendered + shows the refresh-failed banner; before any issues →
      `ErrorCard` with working Retry.
- [ ] **AC8 — deep-link honesty:** `?issue=N` where N arrives in a late page
      keeps the detail sheet in `loading` (not `notFound`) while `isValidating`;
      `notFound` only after `done` with the issue absent.
- [ ] **AC9 — optimistic-write survival:** a `SOLAA-N*` temp card created
      mid-stream survives every subsequent `issues`-frame commit (merge preserves
      non-integer-id entries) and reconciles on POST ack exactly as today.
- [ ] **AC10 — honest empty:** `meta` + `done` with zero `issues` frames resolves
      `{issues:[]}` → `EmptyState`; no `data={issues:[]}` commit happens before
      `done` (no mid-stream EmptyState flash).
- [ ] **AC11 — shared key intact:** the nav badge still resolves `{issues,
      board}` whether it triggers the fetch (JSON arm) or joins an in-flight SSE
      read (dedup); `test/dashboard-mount-fetch-dedup.test.tsx` stays green
      (all mount GETs still flow through `swrKeys`).
- [ ] **AC12 — agent tool unchanged:** `workstream-tools.test.ts` green
      unmodified — `workstream_issues_list` still calls `getWorkstreamIssues`
      and gets the full array.
- [ ] **AC13 — truncation flag parity:** an open-page-cap hit still mirrors to
      Sentry (`list-repo-issues-open-cap`) AND surfaces `openTruncated: true` on
      `done`.
- [ ] **AC14:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
      (no `-w` workspaces form — the root package.json declares none); vitest
      green for every touched suite (`apps/web-platform/vitest.config.ts`
      collects `test/**/*.test.ts` + `lib/**/*.test.ts` + `test/**/*.test.tsx` —
      all new/edited test paths satisfy these globs).

### Post-merge (verification — automatable)

- [ ] **AC15 — field evidence:** Sentry pageload transactions for
      `/dashboard/workstream` (field RUM landed with #9178) show the route's
      LCP/FCP; the `workstream board read` log line and a new stream-summary log
      (`frames`, `issues`, `durationMs`, `openTruncated`) appear per feed. No
      new alert — this is a perception fix, not a liveness surface.
      `Automation:` Sentry MCP query (no SSH). Verdict rule: ≥1 vital-bearing
      pageload transaction for the route within 24 h of deploy.

## Test Scenarios

- Given a 3-page open feed, when the route streams, then the client commits three
  `issues` frames and columns fill incrementally.
- Given `boardMap` resolving after page 2 of 4, when the `statuses` frame emits,
  then only pages 1–2 issues whose column changed appear in `overrides`.
- Given a stream that dies after `meta` + one `issues` frame (no `done`), when the
  reader sees EOF, then the fetcher throws and the board shows partial data +
  amber banner.
- Given `?issue=9999` where issue 9999 arrives on the last page, when the user
  loads the URL, then the sheet reads loading until `done`, then renders it.
- Given an `Accept: application/json` request (badge/`jsonFetcher`), when it
  fires first, then the response is the unchanged bulk JSON.
- Given an all-PR upstream page, when `pageIssuesInto` yields zero items, then no
  `issues` frame is emitted for it.
- Given a mid-stream `SOLAA-N*` optimistic create, when the next `issues` frame
  commits, then the temp card is still present.

## Files to Edit

- `apps/web-platform/server/github-read-tools.ts` — optional `onBatch` on
  `listRepoIssues`, threaded through `pageIssuesInto` (one invoke per REST page).
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — extract
  `resolveBoardReadContext`; add `streamWorkstreamIssues`; keep
  `getWorkstreamIssues` semantics byte-identical (mirrors stay at the same
  decision points — moved into the helper, never duplicated).
- `apps/web-platform/app/api/workstream/issues/route.ts` — Accept negotiation;
  SSE `ReadableStream` arm; cap timer; mid-stream error → `error` frame +
  `captureException`.
- `apps/web-platform/lib/swr-config.ts` — comment noting the negotiated SSE
  fetcher on `swrKeys.workstreamIssues`.
- `apps/web-platform/components/workstream/workstream-board.tsx` — streaming
  fetcher + `useSWRConfig`-bound progressive `mutate`; `notFound`/`loading`
  gating on `!isValidating`.
- `apps/web-platform/test/workstream-issues-route.test.ts` — SSE-arm cases.
- `apps/web-platform/test/server/workstream/get-workstream-issues.test.ts` —
  streaming-event cases.
- `apps/web-platform/test/components/workstream/workstream-board.test.tsx` —
  progressive-render, deep-link, and mid-stream-error cases.

## Files to Create

- `apps/web-platform/lib/workstream-feed.ts` — frame union, SSE format/parse
  helpers, `mergeStreamedIssues`, `applyStatusOverrides`,
  `fetchWorkstreamIssuesFeed`. Client-safe leaf (types from `./workstream` only).
- `apps/web-platform/test/workstream-feed.test.ts` — helper tests.

## Open Code-Review Overlap

None — the two-stage sweep (`gh issue list --label code-review --state open
--json number,title,body` → 87 issues → `jq --arg` contains-match) returned zero
hits for every Files-to-Edit/Create path: `workstream-board.tsx`,
`get-workstream-issues.ts`, `github-read-tools.ts`, `api/workstream/issues`,
`swr-config.ts`, `lib/workstream.ts`.

## Observability

```yaml
liveness_signal:
  what: "existing 'workstream board read' log.info + NEW stream-summary log.info (frames, issueCount, durationMs, openTruncated) at feed completion"
  cadence: "per board GET / per feed"
  alert_target: "none new — perception-path metric; regressions ride Sentry error events + field RUM"
  configured_in: "server/workstream/get-workstream-issues.ts (existing log.info site) + the stream completion site"
error_reporting:
  destination: "Sentry (surface:workstream-issues captureException; reportSilentFallback mirrors at degrade sources)"
  fail_loud: "pre-stream degrade → HTTP 502 JSON; mid-stream failure → error frame + captureException + client amber banner/ErrorCard; truncated stream → fetcher throw (never silent-complete)"
failure_modes:
  - mode: "GitHub REST page fails mid-feed"
    detection: "error frame to client + Sentry surface:workstream-issues captureException"
    alert_route: "existing workstream Sentry rules"
  - mode: "Project board Status GraphQL read fails"
    detection: "existing reportSilentFallback feature:workstream op:board-status-read; feed continues on label derivation (no statuses frame)"
    alert_route: "existing workstream Sentry rules"
  - mode: "open-page cap hit (active columns under-counted)"
    detection: "existing warn + Sentry list-repo-issues-open-cap + done.openTruncated"
    alert_route: "existing workstream Sentry rules"
  - mode: "stream hangs / proxy buffers the whole body"
    detection: "server-side ~90s cap emits error frame; client sees done-absent EOF → error path. (Whole-body buffering degrades to today's bulk behavior — the JSON arm is not regressed either way.)"
    alert_route: "Sentry error events"
logs:
  where: "pino stdout → container logs → Better Stack; Sentry events"
  retention: "per existing retention (unchanged)"
discoverability_test:
  command: "grep -n 'text/event-stream' apps/web-platform/app/api/workstream/issues/route.ts"
  expected_output: "text/event-stream"
```

Field-RUM note (recipe `webapp-cwv-observability.md`): `sentry.client.config.ts`
already wires `browserTracingIntegration` + probe-armed `tracesSampler` (#9178) —
no new RUM plumbing here; the post-deploy check is a Sentry Web Vitals query on
`/dashboard/workstream` pageload transactions (LCP is the metric this change
moves; FCP was already fast). Per-route sampling escalation is NOT proposed —
dashboard volume at 0.1 is adequate.

## Domain Review

**Domains relevant:** Product, Engineering

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed; no
`specs/feat-one-shot-workstream-progressive-issues/spec.md` exists on this
one-shot path).

### Engineering

**Status:** reviewed (inline — no Task spawn available in this subagent context)
**Assessment:** incremental transport change on an existing endpoint; SSE
convention already established by the support route (ADR-113). The engineering
risks are ordering/reconcile correctness (covered by AC4/AC5/AC6) and the
shared-SWR-key constraint (nav badge) — both pinned by tests.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — a behavioral change on an existing
surface that adds no new pages, flows, or components. UX deltas: columns fill
incrementally instead of swapping skeleton→full-board in one shot, and cards may
settle into their canonical column when the `statuses` reconcile lands while the
Refresh spinner already signals in-flight work. No new component files under
`components/**/*.tsx` / `app/**/page.tsx` are created (the one new production
file is a `lib/` leaf + tests) → no mechanical BLOCKING escalation.
`components/workstream/workstream-board.tsx` does match the UI-surface glob in
Files-to-Edit — per the `2026-07-15` sibling precedent on this same surface, a
behavioral change to an existing component is ADVISORY.
**Agents invoked:** none (pipeline advisory auto-accept; deepen-plan + one-shot
review provide the substantive passes)
**Skipped specialists:** ux-design-lead (no new UI surface — reuses the existing
columns/skeleton/spinner), copywriter (no new copy)
**Pencil available:** N/A

#### Findings

No new user journey. The change makes an existing wait honest and progressive.
`user-impact-reviewer` runs at review time (threshold = single-user incident) —
queue: truncated-stream-as-complete, reconcile-drop, EmptyState-flash.

## GDPR / Compliance Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` +
`soleur:legal:legal-compliance-auditor` before merging.**

The gate fires because `app/api/workstream/issues/route.ts` matches the canonical
regex (`apps/web-platform/app/api/.*`). Findings: **none.**

- Same data categories (the user's own connected-repo issues), same recipient
  (the authenticated session owner), same auth gate (`verifiedUserId`), no new
  storage — SSE changes transport only; nothing is persisted that wasn't already.
- No new schema columns (Art. 6/5e/17 checks inapplicable), no Art. 9 data, no new
  third-party processor, no new Art. 30 processing activity (same read of GitHub
  issues for display, re-shaped).
- SSE holds a response open ~seconds longer than a buffered JSON read — no
  session/security posture change (cookie-auth GET, no CSRF surface — GET has no
  `validateOrigin` requirement today and gains none).

## Infrastructure (IaC) — Phase 2.8

None — no new infrastructure, service, secret, vendor, or runtime process.

## Architecture Decision (ADR/C4) — Phase 2.10

**None required.** No ownership/tenancy boundary moves, no new substrate (SSE over
HTTP is established in-repo — ADR-113 support transport), no resolver/dispatch/
trust-boundary change, no ADR reversed. Enumerated per the C4 rubric: new external
human actors — none; new external systems — none (GitHub API edge already
modelled, `github` system + `webapp.api -> github` edges exist); new containers/
data-stores — none; changed access relationships — none. An engineer reading the
existing ADRs + C4 is not misled by a second SSE route; the transport choice is
recorded in the route's header comment.

## Success Metrics

- Time-to-first-issue rendered: from full-feed duration (worst-case ~23+10 serial
  GitHub calls) to ~1 upstream page after resolution (~sub-second typical).
- Total feed duration: unchanged (sequential paging preserved — explicitly a
  non-goal; the deferred parallel-fan-out follow-up owns it).
- Post-deploy: Sentry Web Vitals shows `/dashboard/workstream` LCP improvement;
  stream-summary log emits per feed with `openTruncated` visible.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Shared SWR key coherence — badge `jsonFetcher` vs board streaming fetcher fire-order | Accept negotiation: whichever arm fires, the resolved shape is `{issues, board}`; dedup shares the in-flight result; the other hook just subscribes. AC11 pins it. |
| Column snap when `statuses` reconcile lands mid-load | Overrides are minimal `{id,status,live}`; only fires on the dogfood-org board-precedence path; spinner already communicates in-flight work. |
| Mid-stream `mutate` racing a user write (optimistic edit) | Merge preserves optimistic temps; racing a background revalidate can clobber optimistic edits — that hazard predates this change (SWR semantics), not introduced here; PATCH reconcile restores canonical state. |
| Proxy/infra buffering the SSE body whole | `Cache-Control: no-transform`; support route proves SSE works on this stack; worst case degrades to today's bulk UX, never broken. |
| ReadableStream backpressure / unbounded enqueue | Frames are ≤100-issue pages; enqueue volume is bounded by design (~23 frames). Optional `desiredSize` check noted for implementer. |
| Stream survives component unmount (no abort) | Same as today's `jsonFetcher` — SWR doesn't abort fetchers; the feed completes into cache harmlessly. Non-goal. |
| Long-held connection on serverless/host limits | Hard cap (~90 s) mirrors `SUPPORT_TURN_MAX_MS`; Node route handler, same posture as the support SSE route. |

## Deferral Tracking

Two follow-ups to file as GitHub issues at work time (labels `domain/engineering`
and `type/feature` — both verified via `gh label list` at plan time; milestone
`Phase 4: Validate + Scale`, the internal-tooling milestone per
`knowledge-base/product/roadmap.md` §Current State):

1. **Upstream parallel page fan-out.** Once `Link: …rel="last"` is read off page
   1, pages 2..N are independent and could fetch ~5-wide, emitting `issues`
   frames out of order (client upsert is order-agnostic). Re-evaluate if the
   streamed feed still ends >3 s on the dogfood repo, and mind GitHub secondary
   rate limits.
2. **`notFound`/`loading` audit of `MobileBoard`.** The mobile single-column path
   consumes the same `filtered` array; confirm its sheet gating inherits the
   `!isValidating` fix identically (it shares `IssueDetailSheet`, so likely free —
   verify at work time rather than assume).

## Sharp Edges

- The `IssuesResponse`/`{issues, board}` shape is a **cross-consumer contract**
  (board + nav badge + writes reconcilers). The SSE fetcher MUST resolve exactly
  this shape; a frame that resolves anything else breaks `hr-type-widening`'s
  consumer set invisibly.
- `getWorkstreamIssues` is consumed by the agent tool **directly** — do not
  convert it into an emit-loop consumer; keep it collecting the same array so
  `workstream-tools.test.ts` stays untouched (AC12).
- Mirror-precedes-throw moves INTO `resolveBoardReadContext`, not beside it — a
  second mirror site at the same decision point double-counts Sentry events (the
  defect the route's `instanceof` skip exists to prevent, now at the source).
- Never commit a partial `{issues: []}` — `data != null && issues.length === 0`
  renders EmptyState; the first commit must wait for a non-empty accumulation or
  terminal `done`.
- `issues` frames are DELTA + upsert-by-id, never cumulative snapshots — the
  2026-04-13 cumulative-vs-delta learning; the frame schema names the delta
  semantics so no consumer can misread it.
- Board precedence (ADR-097) is canonical only through `deriveColumn`/`deriveLive`
  — the reconcile must re-derive BOTH fields (`live` flips with column); a
  status-only patch leaves `live` stale.
- A plan whose `## User-Brand Impact` section is empty, placeholder-only, or omits
  the threshold fails `deepen-plan` Phase 4.6 — filled above (single-user
  incident).

## References & Research

- Sibling plan (same surface, same invariants):
  `knowledge-base/project/plans/2026-07-15-fix-workstream-degraded-empty-board-false-empty-state-plan.md`
- Adjacent perf work (verified non-overlapping): #9178,
  `knowledge-base/project/plans/2026-09-28-perf-dashboard-fcp-redux-cwv-observability-plan.md`
- SSE prior art: `apps/web-platform/app/api/support/route.ts`,
  `apps/web-platform/lib/support-sse.ts`,
  `apps/web-platform/components/support/use-support-chat.ts`
- Board precedence: ADR-097 (`deriveColumn` boardStatus arm); SSE transport
  precedent: ADR-113.
- Learnings: `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md`,
  `2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md`.
