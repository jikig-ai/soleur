---
plan: knowledge-base/project/plans/2026-05-12-feat-e2e-playwright-container-plan.md
branch: feat-one-shot-e2e-playwright-container
lane: single-domain
created: 2026-05-12
---

# Tasks — Run `e2e` job inside Playwright container

## Phase 1 — Capture the version-and-digest tuple

- [x] 1.1 Verify `apps/web-platform/package-lock.json` pins `playwright@1.58.2` (done at plan-time).
- [x] 1.2 Resolve multi-arch manifest-list digest for `mcr.microsoft.com/playwright:v1.58.2-jammy` via `docker buildx imagetools inspect` (done at plan-time: `sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565`).
- [x] 1.3 Verify Node version inside the container: `docker run ... node --version` → `v24.13.0` (done at plan-time).
- [x] 1.4 Verify bash present, bun absent (done at plan-time).

## Phase 2 — Migrate `e2e` job in `.github/workflows/ci.yml`

- [ ] 2.1 Add `container.image: mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` to the `e2e:` job key.
- [ ] 2.2 Add `defaults.run.shell: bash` at the `e2e` job level.
- [ ] 2.3 Delete the `Setup Node.js` step (`actions/setup-node@... node-version: 22`).
- [ ] 2.4 Delete the `Cache Playwright browsers` step (`actions/cache@5a3ec84...`).
- [ ] 2.5 Delete the `Install Playwright Chromium` step (`npx playwright install --with-deps chromium`).
- [ ] 2.6 Delete the `Install Playwright system deps (cache hit)` step (`npx playwright install-deps chromium`).
- [ ] 2.7 Keep `actions/checkout`, `Setup Bun`, `Install dependencies`, `Install web-platform dependencies`, `Run E2E tests`, and `Upload test results on failure` BYTE-IDENTICAL.
- [ ] 2.8 Verify NO `options: --user` directive is added on the container block.
- [ ] 2.9 Verify the job key remains `e2e:` byte-identical (required by branch-protection ruleset `14145388`).

## Phase 3 — Local pre-push verification

- [ ] 3.1 Run AC1 (lockfile + tag version-match grep).
- [ ] 3.2 Run AC2 (`git diff main` grep for the digest sha256).
- [ ] 3.3 Run AC3 (section-scoped forbidden-pattern grep returns 0).
- [ ] 3.4 Run AC4 (`shell: bash` present in `e2e` section).
- [ ] 3.5 Run AC5 (no `options: --user`).
- [ ] 3.6 Run AC6 (no `actions/cache@` in `e2e` section).
- [ ] 3.7 Run AC7 (no `actions/setup-node@` in `e2e` section).
- [ ] 3.8 Run AC8 (`docker manifest inspect` exits 0).
- [ ] 3.9 Run AC9 (`critical-css-gate` UNTOUCHED via diff grep).
- [ ] 3.10 Run AC10 (`deploy-docs.yml` UNTOUCHED).
- [ ] 3.11 Run AC11 (job key `e2e:` preserved).
- [ ] 3.12 Run AC12 (ruleset still includes `e2e`).
- [ ] 3.13 (Optional) Run the e2e suite locally inside the container to exercise the exact in-container shape.

## Phase 4 — Push, observe PR CI

- [ ] 4.1 Push the branch and open the PR.
- [ ] 4.2 Watch PR Checks UI: `e2e` runs green; record wall-clock.
- [ ] 4.3 Verify AC13 (e2e wall-clock < 90 s).
- [ ] 4.4 Verify `critical-css-gate` is skipped (detect-changes emits `docs=false`).
- [ ] 4.5 Verify all other required gates remain unaffected.

## Phase 5 — Post-merge verification

- [ ] 5.1 After merge, watch first push-to-main run.
- [ ] 5.2 Verify AC15 (`e2e` on main green at the new wall-clock; within ±10 s of PR-time measurement).
- [ ] 5.3 Confirm no follow-up wall-clock regression issue is needed.

## Phase 6 — Lifecycle bookkeeping

- [ ] 6.1 Capture learnings via `/soleur:compound` if any new insight surfaced (e.g., bun-in-container behavior on v1.58.2).
- [ ] 6.2 Ensure plan + tasks committed; PR body references `Closes #<issue-if-any>` or `Ref:` to the operative learning.
