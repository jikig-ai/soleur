---
title: "Tasks: 3 pre-existing plugin-test flakes (#4112)"
date: 2026-05-20
plan: knowledge-base/project/plans/2026-05-20-fix-plugin-test-flakes-4112-plan.md
lane: single-domain
---

# Tasks: fix(test) #4112

> Deepen-plan revision (2026-05-20): root cause simplified from "3
> distinct flakes" to "1 root cause: default 5 s hook timeout vs.
> Eleventy subprocess startup of 3–10 s". `github-stats-data.test.ts`
> is **innocent in isolation** and removed from the edit list.

## Phase 0 — Preconditions

- [ ] 0.1 Verify branch is `feat-one-shot-plugin-test-flakes-4112`
  and cwd is the worktree.
- [ ] 0.2 `bun --version` ≥ 1.3.11.
- [ ] 0.3 Repro AC3 command and capture stderr (before-state).
- [ ] 0.4 Read `githubStats.js:1-67` + `communityStats.js:1-50` to
  internalise the AbortController mirror pattern.
- [ ] 0.5 Re-confirm bun-types `HookOptions` signature at
  `~/.bun/install/cache/bun-types@<version>/test.d.ts:308 + :325`.

## Phase 1 — Source: bound `github.js` fetch (defense-in-depth)

- [ ] 1.1 Edit `plugins/soleur/docs/_data/github.js`:
  - [ ] 1.1.1 Add `FETCH_TIMEOUT_MS = 5000` constant + comment
    block copied from `githubStats.js:4-5`.
  - [ ] 1.1.2 Add `AbortController` + `setTimeout` arming before
    the fetch call.
  - [ ] 1.1.3 Pass `signal: controller.signal` into `fetch`.
  - [ ] 1.1.4 Wrap try/catch in `try { ... } finally { clearTimeout
    (timer); }`.
- [ ] 1.2 Verify `npm run docs:build` exits 0.

## Phase 2 — Test: `marketing-content-drift` hook timeout (primary)

- [ ] 2.1 Edit `plugins/soleur/test/marketing-content-drift.test.ts`:
  change `beforeAll(async () => { ... });` (line 62) to
  `beforeAll(async () => { ... }, 30_000);` with inline comment
  citing PR #4097 and the Eleventy build timing rationale.
- [ ] 2.2 Verify `bun test plugins/soleur/test/marketing-content-
  drift.test.ts` exits 0.

## Phase 3 — Test: `jsonld-escaping` hook timeout (primary)

- [ ] 3.1 Edit `plugins/soleur/test/jsonld-escaping.test.ts`: same
  `30_000` third arg on `beforeAll` (line 20) + comment.
- [ ] 3.2 Verify `bun test plugins/soleur/test/jsonld-escaping
  .test.ts` exits 0.

## Phase 4 — Integration

- [ ] 4.1 Run AC3 repro across the three files in order — exit 0,
  no `beforeEach/afterEach hook timed out` strings.
- [ ] 4.2 Run AC4: three isolated invocations.
- [ ] 4.3 Run AC5: `bun test plugins/soleur/` — exit 0 in ≤120 s.
- [ ] 4.4 Run AC6: `TEST_GROUP=bun bash scripts/test-all.sh` — exit 0.
- [ ] 4.5 Capture timing log + before/after diff for PR body.

## Phase 5 — Commit + PR

- [ ] 5.1 Single commit:
  `fix(test): raise eleventy beforeAll timeout + bound github.js
  fetch (Closes #4112)`.
- [ ] 5.2 PR body: AC checklist + repro output + root-cause
  diagnosis from Enhancement Summary § Key Corrections.

## Phase 6 — Review + Compound + Ship

- [ ] 6.1 `/soleur:review` — multi-agent pass.
- [ ] 6.2 Resolve any P1 findings inline; defer P2 via tracking
  issues if any.
- [ ] 6.3 `/soleur:compound` to capture the bun-test
  `HookOptions` + `beforeAll`-mislabel learnings.
- [ ] 6.4 `/soleur:ship` to push, mark ready, request auto-merge.

## Files NOT Edited (out of scope)

- `plugins/soleur/test/github-stats-data.test.ts` — passes in
  isolation (7/7, 262 ms); the v1 plan's `Promise.reject(...)`
  rewrite was based on a misattribution and is dropped.

## Out of Scope / Non-Goals

- Refactoring `github.js` to share a timeout helper with sibling
  `_data` files. Three near-duplicates (`github.js`, `githubStats.js`,
  `communityStats.js`) ≠ helper boundary yet; fold in if a 4th appears.
- Replacing `Bun.spawn(["npm", "run", "docs:build"])` in
  `marketing-content-drift.test.ts` with a direct `Eleventy` import
  to avoid the subprocess. Cheap-but-not-here; the 30 s timeout
  closes the same gap with no behavioural risk.
- Filing an upstream bun issue about the "before/after EACH" mislabel
  on `beforeAll` timeouts. Inline code comment in the edited files
  is sufficient documentation for future debuggers.
