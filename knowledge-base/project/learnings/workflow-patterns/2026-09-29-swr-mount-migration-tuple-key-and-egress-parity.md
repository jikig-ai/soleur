---
title: "SWR mount-migration: the fetcher gets the whole key TUPLE, clearing the cache mid-flow unmounts the consumer, and turning on tracing made request.url a live egress surface"
date: 2026-09-29
category: workflow-patterns
tags: [swr, sentry, perf, review, test-porting, followthrough, security]
issue: 9178
pr: 9180
branch: feat-one-shot-9178-fcp-redux-cwv
---

# Learning: SWR mount migration — tuple keys, cache-clear unmounts, and tracing-side egress parity

## Problem

PR #9180 (#9178) migrated every mount-time `fetch()` GET on the dashboard shell onto
shared `swrKeys.*` tuples (`useSWR`), added a post-FCP deferral primitive
(`usePostFcp`), and armed Sentry client tracing (`browserTracingIntegration` +
`tracesSampler` 1.0-under-probe/0.1-floor) for field RUM. The migration "worked" on
first pass and then produced four distinct defect classes that only surfaced in
tests and the review panel — none of them obvious from the SWR docs page alone.

## Session Errors

1. **SWR fetchers receive the whole key tuple, not its first element.** My string-param
   fetchers (`fetch(url)`) accidentally worked in prod (browser `fetch` coerces arrays
   to strings) but the test mock's `input.endsWith` threw. `jsonFetcher` already reads
   `key[0]` — every custom fetcher must too.
   **Prevention:** convention pinned: fetcher signature reads `key[0]`; never type the
   param as `string` for a tuple key.
2. **`clearSwrCache` mid-flow nulls shared-key data → component unmounts.** The
   org-switcher renders `memberships` from the SWR key; the switch-commit cache clear
   zeroed it and the whole component (dialog included) unmounted mid-RPC. Fixed with a
   principal-scoped `lastKnownMemberships` ref latch.
   **Prevention:** when a component's render gate reads a shared SWR key, assume the
   key can be cleared by sign-out/switch between any two awaits; latch last-known for
   chrome that must survive the park window.
3. **Shared global cache leaks between tests.** Every test file rendering a migrated
   consumer needed a fresh-cache provider (`SwrTestProvider` already exists at
   `test/helpers/swr-wrapper.tsx` — ~85 usages — don't hand-roll a `freshCache`; mine
   omitted `shouldRetryOnError:false` and diverged semantically).
   **Prevention:** `SwrTestProvider` is THE wrapper; override via its `value` prop
   (`focusThrottleInterval: 0` for back-to-back focus assertions — SWR's default 5s
   throttle eats them).
4. **`requestIdleCallback` without `{timeout}` can starve indefinitely** on a saturated
   main thread — the gated keys stay null for the whole mount (silent badge omission).
   Fixed `{timeout: 2000}` + rAF→setTimeout for rIC-less engines (bare `setTimeout(0)`
   fires *before* first paint — a deferral no-op on Safari).
   **Prevention:** any idle-callback gate needs a bounded timeout; assert the options
   arg with a spy.
5. **Sentry tracing turned `request.url`/transaction names/breadcrumbs into live
   egress** — the client scrub only handled JWT/email substrings, so `/invite/<token>`
   pageload URLs (bearer creds valid for days) shipped raw. Security P1; fixed by
   extracting the server's `sanitizeRequestForSentry` vocabulary into
   `lib/sentry-url-sanitize.ts` (shared — duplicating the prefix list is the
   parity-drift class) and wiring `beforeBreadcrumb`.
   **Prevention:** enabling ANY new Sentry envelope class means porting the whole
   server scrub contract — shape-driven (query/hash strip, token-path prefixes), not
   just substring.
6. **A duplicates census keyed on the emit-side reduction false-positives.** `safePath`
   collapses UUID tails + drops queries, so `/api/dashboard/today/<id>/cost` for two
   messageIds counted as one "duplicate". Fixed: hash `method|pathname|sorted param
   NAMES` (values never enter) as the count key, emit safePath only.
   **Prevention:** census keys must discriminate on raw shape, never on the redacted
   display string; and an allowlist "expected repeats" exclusion must still *report*
   the count on a separate channel (blanket suppression hid the #8985 headline path).
7. **`test-all.sh` mechanics**: `TEST_GROUP` is single-valued (`"webplat scripts"` →
   usage error, commit refused); `--affected` degrades to full when `test-all.sh` is
   in the branch diff vs origin/main (not just staged). The degraded-full gate is a
   sanctioned "hook pays the battery" — don't fight it, scope TEST_GROUP instead.
   **Prevention:** one `TEST_GROUP` shard only; expect the first commit on a branch
   touching `test-all.sh` to run full.
8. **`gh issue create` filing gate**: `--body-file` must be an ABSOLUTE path (hook's
   cwd ≠ yours), and the body needs literal `User-Impact:` + `Fix-Size: <N> lines /
   <M> files` lines (no `~`, no prose — the parser matches the format exactly). A
   Fix-Size under the ≤100-line/≤4-file threshold is REFUSED — file or fix inline.
   **Prevention:** write the body file at an absolute path first, then file; check the
   threshold before deciding defer-vs-inline (it pushed the useOnboarding dedup fix
   inline — correctly).
9. **Followthrough enrollment**: the tracker directive + `follow-through` label belong
   on the ISSUE body (the sweeper enumerates `gh issue list`, never PR bodies), and the
   ship PR should say `Ref`/`Tracks` (not `Closes`) or merge auto-closes the tracker
   before the probe's PASS arm can fire.
10. **markdownlint on appended session-state**: `<img src=` unescaped parses as an image
    (MD045); `###` headings need surrounding blank lines.
    **Prevention:** backtick-wrap angle-bracket tokens in markdown; blank lines around
    headings/lists.
11. **Python regex rewrites of test files corrupted syntax** (replacement string carried
    literal `\(` escapes).
    **Prevention:** `re.sub` replacement args need `re.escape` or function replacers;
    after any scripted edit, read the file region back — a `grep -c` count certified
    nothing here.
12. **eslint-config baseline is a real gate**: orphaned `ReactNode`/`SWRConfig` imports
    after the wrapper dedup pushed `no-unused-vars` +4 over baseline.
    **Prevention:** sweep `import type { ReactNode }` after deleting a `({ children }:
    { children: ReactNode })` helper.

## Solution Patterns Worth Keeping

- **null-key gating**: `useSWR(postFcp ? swrKeys.x() : null, fetcher)` — the deferred
  fetch never fires while `null`; consumers keep last-known via their own overlays.
  Route-primary exemption: `postFcp || onRoute ? key : null`.
- **`refreshInterval` must clear `dedupingInterval`**: a poll interval inside the dedup
  window gets coalesced and stretches the effective cadence ~2× (2.1s not 2.0s with a
  2s window).
- **`expectedRepeats` channel**: designed-repeat GETs (polls) are excluded from the
  `duplicates` AC but reported separately — suppression without observability hides
  the regression the census exists to catch.
- **Review panel first**: the P1 (URL-sanitize port) was findable only by comparing the
  client's scrub contract against the server's — a per-file review would never see it.

## Verification

- 245 vitest + 22 probe + 19 followthrough arms green; tsc clean; eslint baseline green.
- Semgrep (EIO_BACKEND=posix): 222 rules / 22 files → 1 INFO (pre-existing pattern).
- `merge-tree --write-tree` vs origin/main: clean; `middleware.ts` byte-identical (NFR1).
- Followthrough enrolled on issue #9178 (directive + label); PR body uses `Tracks`.
