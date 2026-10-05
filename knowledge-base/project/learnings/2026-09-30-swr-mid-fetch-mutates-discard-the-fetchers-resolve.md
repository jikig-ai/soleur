---
title: SWR mid-fetch mutates discard the fetcher's resolve — a progressive feed must commit its canonical set at `done`
date: 2026-09-30
category: logic-errors
tags: [swr, sse, progressive-loading, mutation-overlap, workstream, streaming]
module: apps/web-platform
pr: 9267
---

# Learning: SWR mid-fetch mutates discard the fetcher's resolve — a progressive feed must commit its canonical set at `done`

## Problem

`GET /api/workstream/issues` fetched the entire GitHub issue list before the
page could render, so the Workstream board sat on a skeleton while ~30 serial
upstream calls completed. Streaming one SSE frame per REST page
(`meta → issues* → done`) and committing each frame into the shared SWR key
with `mutate(key, merge, { revalidate: false })` fixed the paint — and silently
created a second defect: **SWR's mutation-overlap rule discards the fetcher's
resolved value once any mid-fetch `mutate` has committed.** The cache kept the
merge product forever: upstream-deleted/transferred cards were never pruned
("ghosts"), and ordering could diverge from the canonical stream.

A second trap sits inside the same seam: a mid-feed PATCH ack writes the
canonical card into `cur`, but the stream's accumulator may still hold the
pre-write copy from an earlier page — a final replace-all commit reverts the
user's confirmed move. And a card created mid-feed (real id ack'd after its
page already passed) is absent from the accumulator entirely.

## Solution

- **Authoritative terminal commit.** The fetcher accumulates `acc` internally;
  at `done` the last commit is `acc ∪ locally-pending ids`
  (`mergeFinalIssues`), not a merge of `cur`. Ghosts prune; canonical order
  restores.
- **Pending/in-flight registries.** `markLocallyWrittenIssueId` on EVERY
  write-path reconcile (create AND each PATCH — the post-ack/pre-`done` window
  is unguarded otherwise); `markInflightWriteId` while a PATCH is in flight so
  a stale streamed copy can't snap the optimistic card back. Marks carry a
  **feed epoch** — a mark from an older feed expires at the next `done`, so an
  id that never re-streams (deleted upstream) can't hold a ghost forever.
- **`partial: true` on mid-stream commits** so other consumers of the shared
  key (the nav badge) hold their last COMPLETE snapshot instead of counting a
  streamed subset.
- **Write-path mutates must spread `...cur`** — a rebuild `{issues, board}`
  silently drops `partial`/`openTruncated` and re-opens the subset-count bug.

## Key Insight

Any pattern that writes to a SWR key *while* its fetcher is still in flight
changes the resolution contract: the fetcher's return is no longer what lands.
The final in-stream commit must BE the canonical payload, and every local write
must carry a mark that survives it (bounded by feed epoch so marks can't leak).

Secondary: Supabase SSR session cookies for curl/Playwright probes are the
**raw JSON session object** (not base64/base64url) — recipe lives in
`test/fixtures/qa-auth.ts`.

## Session Errors

1. **Pre-commit affected battery ran ~15 min locally** — Recovery: operator authorized skipping (`LEFTHOOK=0`), CI carries it — Prevention: none needed (sanctioned escape hatch exists).
2. **QA cookie minted in base64 then base64url, both rejected** — Recovery: `test/fixtures/qa-auth.ts` showed the cookie is the raw JSON session — Prevention: this learning records the recipe.
3. **`resolveWorkstreamBoardMeta` refactor left stale mocks in three test files** — Recovery: grep the removed symbol across `test/` after a refactor — Prevention: `grep -rn '<deleted-symbol>' test/` before declaring refactor done.
4. **Python heredoc splice inserted a statement inside a call's argument literal** (syntax error) — Recovery: repaired with a targeted edit — Prevention: use structural edits for inserts inside expressions; a blind `str.replace` on a call-prefix lands mid-call.
5. **Hooks-contract fixture used a short page where the pager requires a full page to continue** — Recovery: returned 100 items — Prevention: when testing pagination callbacks, remember the short-page-terminates rule IS the contract under test.
6. **`tsc --noEmit` OOM'd under host memory pressure** — Recovery: `NODE_OPTIONS=--max-old-space-size=8192` — Prevention: on a loaded box, retry with a larger heap before suspecting the diff.
7. **Two review seats hit model rate limits** — Recovery: retried after reset — Prevention: none (platform constraint; retry policy exists).
8. **Planning subagent returned empty summary** (forwarded from Phase 1) — Recovery: partial-artifact check found the committed plan — Prevention: already covered by the recovery-selector protocol.
9. **`playwright install chromium` idled post-download** — Recovery: cache already held the build; ran the gate directly — Prevention: check `~/.cache/ms-playwright/` before waiting on install.
10. **nav-states e2e flaked locally (shifting failures + browser kills on a memory-starved host)** — Recovery: #5009 discriminator applied; CI containerized gate authoritative — Prevention: already documented.

## References

- `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` (delta + upsert-by-id)
- `2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md` (error && data)
- `2026-09-29-...swr-in-flight-read...` conventions (#9178/#9180 lineage)
- PR #9267; deferral #9282 (parallel page fan-out)
