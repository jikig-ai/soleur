---
title: Tasks — Fix analytics-track `path` prop PII leak
issue: 2462
plan: knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md
branch: fix-analytics-track-path-pii
---

# Tasks: Fix analytics-track `path` prop PII leak (#2462)

Derived from `2026-04-17-fix-analytics-track-path-pii-plan.md`. Execute via
`skill: soleur:work`.

## Phase 1 — RED tests (write failing tests first)

- [ ] **1.1** Create `apps/web-platform/test/sanitize-props.test.ts` with
      `describe("sanitizeProps — path PII scrub")` block.
  - [ ] **1.1.1** Add test case 1: email in path → `[email]`,
        `scrubbed: ["email"]`.
  - [ ] **1.1.2** Add test case 2: UUID v4 (lowercase) in path →
        `[uuid]`, `scrubbed: ["uuid"]`.
  - [ ] **1.1.3** Add test case 3: 6-digit run in path → `[id]`,
        `scrubbed: ["id"]`.
  - [ ] **1.1.4** Add test case 4: `/blog/2026-04-17-foo` unchanged,
        `scrubbed: []`.
  - [ ] **1.1.5** Add test case 5: `/docs/v12.4.1/install` unchanged,
        `scrubbed: []`.
  - [ ] **1.1.6** Add test case 6: `/?q=hello` unchanged, `scrubbed: []`.
  - [ ] **1.1.7** Add test case 7: email + uuid in same path → both
        sentinels, `scrubbed: ["email","uuid"]`.
  - [ ] **1.1.8** Add test case 8: `/kb/docs/getting-started` unchanged
        (regression guard for current happy path).
  - [ ] **1.1.9** Add test case 9: non-string `path` (number 42) passes
        through untouched, `scrubbed: []`.
  - [ ] **1.1.10** Add test case 10: 500-char path, no PII → truncated to
        200, `scrubbed: []`.
  - [ ] **1.1.11** Add case 11: uppercase UUID scrubs (case-insensitive
        regex flag).
  - [ ] **1.1.12** Add case 12: scrub runs BEFORE 200-char slice (email
        at char 195, output contains `[email]` AND length ≤ 200).
  - [ ] **1.1.13** Add case 13: `scrubbed` is unique-per-pattern (two
        emails → one `"email"` entry).
  - [ ] **1.1.14** Add case 14: order stability — email + uuid + id in
        one path produces `scrubbed: ["email","uuid","id"]` in that order.
  - [ ] **1.1.15** Add case 15: non-allowlisted keys still flow to
        `dropped`, unaffected by scrub changes.
- [ ] **1.2** Add T8 integration test to
      `apps/web-platform/test/api-analytics-track.test.ts`:
  - [ ] **1.2.1** Assert forwarded payload has scrubbed path.
  - [ ] **1.2.2** Assert `logDebug` called with `{ scrubbed: ["email"] }` and
        message including `"scrubbed"`.
  - [ ] **1.2.3** Assert raw pre-scrub value never appears in any
        `logDebug.mock.calls` context.
- [ ] **1.3** Run tests: `cd apps/web-platform && ./node_modules/.bin/vitest
      run test/sanitize-props.test.ts test/api-analytics-track.test.ts`.
      Expect RED (TS error on missing `scrubbed` field + 16 assertion
      failures).

## Phase 2 — GREEN implementation

- [ ] **2.1** Edit `apps/web-platform/app/api/analytics/track/sanitize.ts`:
  - [ ] **2.1.1** Add module-scope constants `EMAIL_RE`, `UUID_V4_RE`,
        `LONG_DIGIT_RUN_RE`.
  - [ ] **2.1.2** Add private `scrubPath(value: string)` helper returning
        `{ clean, scrubbed }` in order email → uuid → id.
  - [ ] **2.1.3** Widen `sanitizeProps` return type to
        `{ clean, dropped, scrubbed: string[] }`.
  - [ ] **2.1.4** In the `sanitizeProps` loop, when `k === "path"` AND `v` is
        string, call `scrubPath` BEFORE the 200-char slice; collect pattern
        names into a `Set<string>`.
  - [ ] **2.1.5** Return `scrubbed: [...scrubbedSet]` to preserve insertion
        order (email → uuid → id).
- [ ] **2.2** Edit `apps/web-platform/app/api/analytics/track/route.ts`:
  - [ ] **2.2.1** Destructure `scrubbed` from `sanitizeProps` result (line 73).
  - [ ] **2.2.2** After the existing `dropped` log block (lines 74–76), add
        `if (scrubbed.length > 0) log.debug({ scrubbed }, "analytics.track
        scrubbed PII from path");`.
- [ ] **2.3** Re-run tests: all 15 unit cases + T8 + existing T1–T7 GREEN.
- [ ] **2.4** Run full web-platform unit suite:
      `cd apps/web-platform && ./node_modules/.bin/vitest run`. Expect no
      regressions.
- [ ] **2.5** Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc
      --noEmit`. Expect no errors.

## Phase 3 — JSDoc contract

- [ ] **3.1** Edit `apps/web-platform/lib/analytics-client.ts`:
  - [ ] **3.1.1** Add JSDoc block above `export async function track` with
        `/users/[uid]/settings` example, `/kb/docs/[slug]` example, and
        `/billing/customer/[id]/invoices` example.
  - [ ] **3.1.2** Document `@param goal` and `@param props`.
  - [ ] **3.1.3** Note fail-soft semantics and the server-side scrubber as
        safety net.

## Phase 4 — Verification & ship

- [ ] **4.1** Lint changed markdown: `npx markdownlint-cli2 --fix
      knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md
      knowledge-base/project/specs/feat-fix-analytics-track-path-pii/tasks.md`.
- [ ] **4.2** Run `skill: soleur:compound` to capture learnings.
- [ ] **4.3** Run `skill: soleur:ship` — it enforces:
  - Title: `fix(analytics-track): scrub PII from path prop (#2462)`
  - Body includes `Closes #2462`.
  - Labels: `type/security`, `priority/p3-low`.
  - PR review gate + QA gate + compound gate.
