---
spec: feat-one-shot-critical-css-gate-playwright-container
lane: single-domain
plan: knowledge-base/project/plans/2026-05-12-feat-critical-css-gate-playwright-container-plan.md
---

# Tasks — Critical-CSS Gate Playwright Container

## Phase 1 — Pin resolution (plan-time, already done)

- [x] 1.1 Resolve `playwright@1` floating tag → `1.60.0` (`npm view playwright@1 version`).
- [x] 1.2 Resolve container top-level multi-arch digest for `mcr.microsoft.com/playwright:v1.60.0-jammy` → `sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` (`docker buildx imagetools inspect`).
- [x] 1.3 Verify ruleset 14145388 does NOT include `critical-css-gate` in required checks.

## Phase 2 — `ci.yml` migration

- [x] 2.1 Read current `.github/workflows/ci.yml` `critical-css-gate` job (lines ~240–326).
- [x] 2.2 Add `container.image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` to the job key.
- [x] 2.3 Delete the `Setup Node.js` step inside `critical-css-gate` only (leave other jobs' setup-node steps intact).
- [x] 2.4 Delete the `Cache Playwright browsers` step (`actions/cache@5a3ec84...` keyed on `~/.cache/ms-playwright`).
- [x] 2.5 Delete the two `Install Playwright + http-server (cache miss)` and `(cache hit)` steps.
- [x] 2.6 Add a single `Install Playwright + http-server` step running `npm install --no-save playwright@1.60.0 http-server@14`.
- [x] 2.7 Add `defaults.run.shell: bash` at the `critical-css-gate` job level (container `/bin/sh` defaults to dash on Jammy).
- [x] 2.8 Update or add the in-file comment to document the keep-in-sync-with-deploy-docs.yml relationship, the Playwright-version exact-match requirement, the no-`--user` constraint, and the Node-24 note.
- [x] 2.9 Verify `needs: detect-changes` and `if: needs.detect-changes.outputs.docs == 'true'` are present and unchanged.

## Phase 3 — `deploy-docs.yml` migration (parity)

- [x] 3.1 Read current `.github/workflows/deploy-docs.yml` `deploy` job.
- [x] 3.2 Add `container.image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` to the `deploy` job key.
- [x] 3.3 Delete the `Setup Node.js` step.
- [x] 3.4 Rewrite `Install Playwright (Chromium only) for screenshot gate` to a single `npm install --no-save playwright@1.60.0 http-server@14` (drop the `npx playwright install --with-deps chromium` line).
- [x] 3.5 Add `defaults.run.shell: bash` at the `deploy` job level.
- [x] 3.6 Update or add the in-file comment to document keep-in-sync-with-ci.yml, the Playwright-version exact-match requirement, and the no-`--user` constraint.
- [x] 3.7 Verify `actions/{configure,upload,deploy}-pages` steps remain byte-identical.

## Phase 4 — Verification

- [x] 4.1 `git diff main -- .github/workflows/ci.yml .github/workflows/deploy-docs.yml | grep -c 'sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc'` returns ≥ 2.
- [x] 4.2 `git diff main -- .github/workflows/ci.yml .github/workflows/deploy-docs.yml | grep -cE 'playwright@1\.60\.0|v1\.60\.0-jammy'` returns ≥ 4.
- [x] 4.3 `git grep -E 'ms-playwright|playwright-cache|install-deps chromium' .github/workflows/ci.yml .github/workflows/deploy-docs.yml` returns nothing.
- [x] 4.4 `docker manifest inspect mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` exits 0.
- [x] 4.5 Best-effort local container run: build `_site` via Eleventy, run screenshot-gate.mjs against `_site` from inside the container, confirm exit 0. **Result:** 9.8 s wall-clock, screenshot-gate PASS (20/20 routes), check-critical-css-coverage PASS (18/18 classes). Node 24.15.0, bash 5.1.16.

## Phase 5 — PR open + observe

- [ ] 5.1 Push branch, open PR with body template from plan.
- [ ] 5.2 Wait for `critical-css-gate` to complete on PR. Verify exit green AND wall-clock < 90 s.
- [ ] 5.3 Record wall-clock in PR body.
- [ ] 5.4 Verify other CI jobs unchanged (test, e2e, web-platform-build, lockfile-sync, etc.).
- [ ] 5.5 Verify required-status-checks ruleset 14145388 still excludes `critical-css-gate` at PR time.

## Phase 6 — Post-merge

- [ ] 6.1 After merge, watch the next `deploy-docs.yml` run on `main`.
- [ ] 6.2 Verify the `deploy` job completes successfully, including the GitHub Pages deploy step.
- [ ] 6.3 Verify screenshot-gate step exits 0 against post-build `_site`.
- [ ] 6.4 Record `deploy-docs.yml` wall-clock in a post-merge commit message or session learning. Compare against pre-PR baseline.

## Learning capture

- [ ] L1 If any unexpected behavior surfaces with `actions/{configure,upload,deploy}-pages` under container, write a learning to `knowledge-base/project/learnings/<topic>.md` (date selected at write-time, per plan-sharp-edge).
