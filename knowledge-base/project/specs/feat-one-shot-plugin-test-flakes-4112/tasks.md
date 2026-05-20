---
title: "Tasks: 3 pre-existing plugin-test flakes (#4112)"
date: 2026-05-20
plan: knowledge-base/project/plans/2026-05-20-fix-plugin-test-flakes-4112-plan.md
lane: single-domain
---

# Tasks: fix(test) #4112

## Phase 0 — Preconditions

- [ ] 0.1 Verify branch is `feat-one-shot-plugin-test-flakes-4112` and
  cwd is the worktree.
- [ ] 0.2 `bun --version` ≥ 1.3.11.
- [ ] 0.3 Repro AC4 command and capture stderr (before-state).
- [ ] 0.4 Read `githubStats.js:1-67` + `communityStats.js:1-50` to
  internalize the mirror pattern.

## Phase 1 — Source: bound github.js fetch

- [ ] 1.1 Edit `plugins/soleur/docs/_data/github.js`:
  - [ ] 1.1.1 Add `FETCH_TIMEOUT_MS = 5000` constant + comment.
  - [ ] 1.1.2 Add `AbortController` + `setTimeout` arming before
    the fetch call.
  - [ ] 1.1.3 Pass `signal: controller.signal` into `fetch`.
  - [ ] 1.1.4 Wrap try/catch in `try { ... } finally { clearTimeout
    (timer); }`.
- [ ] 1.2 Verify `npm run docs:build` exits 0.

## Phase 2 — Test: marketing-content-drift hook timeout

- [ ] 2.1 Edit `plugins/soleur/test/marketing-content-drift.test.ts`:
  add `30_000` third arg on `beforeAll` + code comment citing #4097.
- [ ] 2.2 Verify `bun test plugins/soleur/test/marketing-content-
  drift.test.ts` exits 0.

## Phase 3 — Test: jsonld-escaping hook timeout

- [ ] 3.1 Edit `plugins/soleur/test/jsonld-escaping.test.ts`: same
  `30_000` third arg on `beforeAll` + comment.
- [ ] 3.2 Verify `bun test plugins/soleur/test/jsonld-escaping.test.ts`
  exits 0.

## Phase 4 — Test: github-stats-data dangling timer

- [ ] 4.1 Rewrite the three `throw new Error(...)` fetch stubs in
  `github-stats-data.test.ts` (lines ~99-111, ~113-122, ~124-135) to
  `Promise.reject(new Error(...))` form. Preserve error messages.
- [ ] 4.2 Verify `bun test plugins/soleur/test/github-stats-data
  .test.ts` exits 0 with **no** `killed N dangling process` on stderr.

## Phase 5 — Integration

- [ ] 5.1 Run AC4 repro across the three files in order — exit 0,
  no warnings.
- [ ] 5.2 Run AC5: `bun test plugins/soleur/` — exit 0 in ≤120 s.
- [ ] 5.3 Run AC6: `TEST_GROUP=bun bash scripts/test-all.sh` — exit 0.
- [ ] 5.4 Capture timing log + before/after diff for PR body.

## Phase 6 — Commit + PR

- [ ] 6.1 Single commit:
  `fix(test): bound github.js fetch + raise eleventy beforeAll
  timeout + reject-via-promise (Closes #4112)`.
- [ ] 6.2 PR body: AC checklist + repro output + root-cause summary.
  Use `Closes #4112` (not in title).

## Phase 7 — Review + Compound + Ship

- [ ] 7.1 `/soleur:review` — multi-agent pass.
- [ ] 7.2 Resolve any P1 findings inline; defer P2 via tracking
  issues if any.
- [ ] 7.3 `/soleur:compound` to capture the dangling-timer +
  beforeAll-mislabel learnings.
- [ ] 7.4 `/soleur:ship` to push, mark ready, request auto-merge.

## Out of Scope / Non-Goals

- Refactoring `github.js` to share the timeout helper with sibling
  `_data` files. Three files (3 if you count `pdfjs` prewarms) ≠ a
  helper boundary yet; this can be folded in if a 4th appears.
- Replacing `bun.spawn(["npm", "run", "docs:build"])` in
  `marketing-content-drift.test.ts` with a direct `Eleventy` import
  to avoid the subprocess. Cheap-but-not-here; the 30s timeout
  closes the same gap with no behavioral risk.
