---
date: 2026-04-17
category: process
module: web-platform
tags: [duplication, helpers, formatting, tdd-edge-cases, mock-supabase]
issues: ["#1691", "#2464", "#2478"]
---

# Learning: Grep lib/ for existing helpers before writing new ones; test identity values first

## Problem

Three session errors during PR #2464 (BYOK usage dashboard restoration), each
a different shape of the same root pattern — writing new code without
checking what already exists or what edge values behave like:

1. **Duplicate `formatRelativeTime`.** Wrote a new `formatRelativeTime(date,
   now)` inside `apps/web-platform/server/api-usage.ts`. A canonical
   `relativeTime(dateStr)` already lived at
   `apps/web-platform/lib/relative-time.ts`. Caught by the
   pattern-recognition-specialist in review — not caught by typecheck, tests,
   or any local grep I ran. Root cause: I never grepped
   `apps/web-platform/lib/` for existing time-formatting helpers before
   writing the new one.

2. **`formatUsd(0)` returned `$0.0000`.** The sub-cent branch was `if (n <
   0.01) return $${n.toFixed(4)}`. For `n = 0`, that branch fires and
   produces four-decimal zero. Test expected `$0.00`. Fix: `if (n > 0 && n <
   0.01)`. Root cause: I tested sub-cent values (`0.0043`, `0.0001`) and
   supra-cent values (`0.01`, `4.27`) but didn't test the identity value
   (`0`) as the first case.

3. **Mock-supabase helper was missing operators the new code used.** The
   shared `test/helpers/mock-supabase.ts` thenable chain didn't include
   `gt`, `gte`, `lt`, `lte` or a `count` field on the resolved result. My
   data-layer tests hit a cryptic "chain.gte is not a function" failure
   before I realized the helper needed extension. Cost: two backtracking
   steps before I thought to read the helper file.

## Solution

**For future work sessions:**

- Before writing a new format/util helper in any app, run one
  targeted grep against the canonical utility location:

  ```bash
  # For web-platform:
  ls apps/web-platform/lib/ && grep -rn "function <verb>" apps/web-platform/lib/
  ```

  Cost: seconds. Value: avoids an entire category of P1 review findings.

- When writing tests for a helper with branching behavior, the **first**
  test case is the identity/edge value (`0`, `""`, `null`, `undefined`),
  not the happy-path example. The identity value is where conditional
  branches collide, and it's the cheapest way to trip the branch you
  didn't think about.

- Before writing data-layer tests that use new PostgREST operators, read
  the shared mock helper to confirm it covers every operator the code
  under test uses. If not, extend it at the START of the work phase, not
  after the first test failure.

## Key Insight

Three errors, one root cause: "write code first, discover existing
abstractions later." The cheapest mitigation is one ~5-second grep in
each of two places (`lib/` for helpers, `test/helpers/` for mock
surfaces) as the first action of a work phase. These checks should be
baked into the `work` skill's Phase 2 preamble, not discovered via
review.

## Session Errors

- **Duplicate formatRelativeTime** — Recovery: pattern-recognition-specialist
  flagged in review; I deleted the local helper and re-exported the canonical
  `relativeTime` from `@/lib/relative-time` via `server/api-usage.ts`.
  Prevention: work skill Phase 2 checklist item: "Before writing a new format
  or util helper, `ls` + grep the app's canonical `lib/` directory for
  equivalents."

- **formatUsd(0) → "$0.0000"** — Recovery: added `n > 0 &&` guard to the
  sub-cent branch. Prevention: for format helpers with special-case branches,
  add an identity-value test case (`0`, `""`, `null`) as the FIRST test,
  before branch-specific fixtures.

- **Mock helper missing gt/gte/lt/lte/count** — Recovery: extended
  `test/helpers/mock-supabase.ts` with the missing operators and an
  optional `count` parameter (backwards compatible). Prevention: before
  writing data-layer tests that use new PostgREST operators, grep the
  mock helper for each operator; extend at Phase 2 start, not mid-test.

## Tags

category: process
module: web-platform
