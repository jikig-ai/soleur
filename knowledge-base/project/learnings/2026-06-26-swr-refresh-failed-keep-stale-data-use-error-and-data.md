# Learning: "couldn't refresh, showing last loaded" should be `error && data`, not a manual flag

## Problem

The Workstream board needed an honest "Refresh failed — showing the last loaded
issues" inline notice when an explicit **Refresh** (SWR `mutate()` revalidation)
fails but stale data is still on screen. The first implementation used a manual
`const [refreshFailed, setRefreshFailed] = useState(false)` flipped by
`mutate().catch(() => setRefreshFailed(true))` and cleared by an `onSuccess`
callback.

Two problems:
1. **Hard to test.** The unit test that clicked Refresh against a failing
   `fetch` **timed out at 10s** — the bound `mutate().catch` did not reject
   reliably in the SWR test harness (the shared `SwrTestProvider` sets
   `shouldRetryOnError: false` + `dedupingInterval: 0`), so the `.catch` never
   fired and the notice never appeared.
2. **Stale-notice risk.** Clearing the flag only inside the Refresh handler
   meant a later *background* focus/reconnect revalidation that succeeded would
   leave the now-false "couldn't refresh" notice on screen.

## Solution

Drive the notice off SWR's own state instead of a manual flag:

```ts
const { data, error, mutate, isValidating } = useSWR(key, fetcher);
// failed first load → ErrorCard; failed REFRESH (error present BUT stale data
// retained) → inline "couldn't refresh" notice.
const refreshFailed = error != null && data != null;
```

- SWR keeps `data` from the last success while `error` is set on a failed
  revalidation, so `error && data` is exactly "refresh failed, stale data
  retained." `error && !data` stays the first-load ErrorCard branch.
- SWR **clears `error` on the next successful validation** (explicit Refresh OR
  background revalidation), so the notice can never outlive the failure — no
  manual `onSuccess` reset needed.
- It's trivially testable: swap `global.fetch` to an `{ok:false}` mock, click
  Refresh, assert the notice; swap back to ok, click again, assert it clears.
  No reliance on `mutate()`'s promise-rejection timing.

This also collapsed the `refetch`/`refresh` duplication — both are just
`() => void mutate()`.

## Key Insight

For "operation failed but keep showing the last good data" UX over SWR, read the
hook's `error && data` pair rather than threading a manual boolean through a
`mutate().catch`. SWR already tracks failure-with-retained-data and auto-resets
`error` on success; a hand-rolled flag is both harder to test (mutate-rejection
timing is harness-dependent) and prone to outliving the failure it described.

## Session Errors

- **Committed the filter-bar test before running `tsc`** — a `readonly` tuple
  fixture (`as const`) wasn't assignable to the mutable `FilterOptions` shape;
  caught only on the next tsc, forcing a `--amend`. Recovery: typed the fixture
  as `ReturnType<typeof deriveFilterOptions>`, dropped `as const`. **Prevention:**
  run `./node_modules/.bin/tsc --noEmit` before committing a new test file, not
  after.
- **Assumed a `roleLabel` helper + a `soleur-gold` Tailwind token existed** —
  neither did (roles label via `.toUpperCase()`; the token is
  `soleur-accent-gold-{fill,fg,text}`). Recovery: grepped the real names and
  fixed. **Prevention:** grep the app for a helper/token before importing it
  (reinforces "grep lib before writing format helpers").
- **SWR refresh-failure test timed out** — see Problem/Solution above; the fix
  also removed the test flakiness. **Prevention:** prefer `error && data` over
  `mutate().catch` for refresh-failure UX (this learning).
- **Changing the NoResults copy broke its existing assertion** — expected when
  replacing search-only "Clear search" with the combined "Reset filters" state;
  updated the test. One-off.

## Tags
category: ui-bugs
module: apps/web-platform (SWR / workstream board)
