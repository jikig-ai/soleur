---
title: "sec: CodeQL alert #268 — js/request-forgery (in-source suppression of an egress-pinned false positive)"
branch: feat-one-shot-codeql-268-request-forgery
plan: knowledge-base/project/plans/2026-11-03-sec-codeql-alert-268-request-forgery-suppression-plan.md
lane: cross-domain
---

# Tasks — feat-one-shot-codeql-268-request-forgery

Derived from `knowledge-base/project/plans/2026-11-03-sec-codeql-alert-268-request-forgery-suppression-plan.md`.

## 1. Setup

- [x] 1.1 Confirm CWD is `.worktrees/feat-one-shot-codeql-268-request-forgery/` and branch `feat-one-shot-codeql-268-request-forgery`.
- [x] 1.2 Re-read `apps/web-platform/server/github-app.ts` `githubFetch` (lines ~244-264) and `apps/web-platform/test/github-url.test.ts` (census helpers `fetchSites`, `LINE_COMMENT`, `isCommentSite`) before editing.

## 2. Phase 1 — Suppression comment + sentinel test

- [x] 2.1 `apps/web-platform/server/github-app.ts`: insert justification comment block ending with `// codeql[js/request-forgery]` immediately above `const response = await fetch(url, {` in `githubFetch`. The `codeql[…]` line must be the last comment line and the first node on its line (`AlertSuppression.qll` `covers` semantics); product-code diff stays comment-only.
- [x] 2.2 `apps/web-platform/test/github-url.test.ts`: add the drift-sentinel test (CTO caveats) — content-anchored (no line numbers): locate the `fetch(url,` call inside `githubFetch` in `server/github-app.ts`; assert the immediately preceding line contains `codeql[js/request-forgery]`; assert the annotation appears exactly once in `github-app.ts`.
- [x] 2.3 Mutation matrix (Guard 1): (a) delete the annotation line → sentinel RED; (b) insert a statement between comment and sink → RED; (c) move the `fetch(url,` call → RED; (d) revert each → green.

## 3. Phase 2 — Verify

- [x] 3.1 `cd apps/web-platform && npx vitest run test/github-url.test.ts` — green (existing census + sentinel).
- [x] 3.2 `cd apps/web-platform && npx vitest run test/github-app-token-hardening.test.ts test/github-url.test.ts` — green.
- [x] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 3.4 Adjacency probe: `sed -n '250,265p' apps/web-platform/server/github-app.ts` — annotation on the line directly above `const response = await fetch(url, {` (alert start line 255).
- [ ] 3.5 `npx markdownlint-cli2` on changed `.md` files (specific paths only).

## 4. Phase 3 — PR + close

- [ ] 4.1 Commit with the repo CLA identity (Jean Deruelle); do NOT author as a bot.
- [ ] 4.2 PR body: `Closes #9953` on its own line; false-positive verdict; sanitizer-enumeration evidence; statement that the alert is suppressed in-source (no API dismissal — operator sign-off not obtained); labels verified via `gh label list` first (`type/security`, `domain/engineering` if they exist).
- [ ] 4.3 Post-merge: `gh api repos/jikig-ai/soleur/code-scanning/alerts/268 --jq .state` after the merge-triggered analysis completes — record the observed state on #9953 / PR body; if still `open`, document the residual rather than silently leaving it.
