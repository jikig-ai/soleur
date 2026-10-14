# Tasks — fix: critical-css-gate path-filter + cache-key (#3624)

Derived from `knowledge-base/project/plans/2026-05-12-fix-critical-css-gate-path-filter-and-cache-key-plan.md`.

## 1. Setup

- [x] 1.1 Read the failing run logs once more (`gh run view 25718834192 --log | grep critical-css-gate`) to confirm error string.
- [x] 1.2 Read `.github/workflows/ci.yml` (full file) — note all jobs, the canonical action-pin format, and any pre-existing `needs:` dependencies.
- [x] 1.3 Read `.github/workflows/deploy-docs.yml` lines 6-11 — capture the `paths:` prefix list verbatim (will be re-used in the per-job filter).
- [x] 1.4 Read `.github/workflows/infra-validation.yml:24-52` — confirm the `detect-changes` + `outputs.directories` + `if:` pattern that this plan mirrors (single boolean output instead of matrix).

## 2. Core Implementation

### 2.1 Add `detect-changes` job (hand-rolled, mirrors `infra-validation.yml:24-52`)

- [x] 2.1.1 Insert a new `detect-changes` job at the top of the `jobs:` block in `.github/workflows/ci.yml` (immediately after `readme-counts`).
- [x] 2.1.2 Use `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` with `fetch-depth: 0` (REQUIRED — shallow clone breaks the `origin/${BASE_REF}...HEAD` diff).
- [x] 2.1.3 Add a `filter` step that runs `git diff --name-only "origin/${BASE_REF}...HEAD" | grep -qE '<regex>'` against the regex anchor list from Phase 1 of the plan. Short-circuit `push` events to `docs=true` unconditionally.
- [x] 2.1.4 Emit `outputs.docs` as `'true'` or `'false'` via `$GITHUB_OUTPUT`.
- [x] 2.1.5 Run the three-shape fixture test from the plan against the regex BEFORE committing (deep-nested, root, negative).

### 2.2 Gate `critical-css-gate` with the conditional

- [x] 2.2.1 Add `needs: detect-changes` to the `critical-css-gate` job.
- [x] 2.2.2 Add `if: needs.detect-changes.outputs.docs == 'true'` to the job.
- [x] 2.2.3 Confirm no other job in the workflow has `needs: critical-css-gate` (grep verifies — none today).
- [x] 2.2.4 Run `actionlint` against the modified workflow file. Do NOT use `bash -n` (Sharp Edge — YAML parses as bash and fails on header).

### 2.3 Realign cache key

- [x] 2.3.1 Change line 234 of `.github/workflows/ci.yml`: `key: playwright-critical-css-gate-${{ hashFiles('plugins/soleur/docs/scripts/screenshot-gate.mjs') }}` → `key: playwright-critical-css-gate-${{ hashFiles('package-lock.json') }}`.
- [x] 2.3.2 No other edits needed — the install-on-cache-miss branch already runs `npx playwright install --with-deps chromium` and will fire on first lockfile-keyed cache miss.

### 2.4 Capture learning

- [x] 2.4.1 Create `knowledge-base/project/learnings/best-practices/<date>-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md` (author picks date at write-time per `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` convention).
- [x] 2.4.2 Cover two lessons: per-job conditional vs workflow-level `paths`, and Playwright cache-key invariants must advance with binary version.

## 3. Verification

### 3.1 Path-filter verification (positive + negative)

- [ ] 3.1.1 Push the branch. Inspect the PR checks UI: `critical-css-gate` should appear and run (PR touches `.github/workflows/ci.yml` which is in the filter — gate self-runs).
- [ ] 3.1.2 Create a throwaway test branch from main with a one-line edit to `apps/web-platform/server/cc-dispatcher.ts`. Push, open PR. Confirm `critical-css-gate` is absent or skipped in checks list. Close test PR without merging.
- [ ] 3.1.3 Create a second throwaway branch with a one-line edit to `plugins/soleur/docs/_includes/base.njk` (e.g., add a comment). Push, open PR. Confirm `critical-css-gate` runs and passes. Close without merging.

### 3.2 Cache-key verification

- [ ] 3.2.1 After the gate runs once on the feature PR, run `gh cache list --key playwright-critical-css-gate` and confirm a new cache entry exists keyed by `package-lock.json` hash.
- [ ] 3.2.2 Confirm via run logs that the cache-miss install path fired ONCE (first run after key change), then subsequent runs on the same lockfile hit the cache.

### 3.3 No regression on required checks

- [ ] 3.3.1 Confirm `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate` all still appear and pass on the feature PR (these are the required checks per ruleset 14145388).

## 4. Documentation / PR hygiene

- [ ] 4.1 PR body uses `Closes #3624` (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] 4.2 PR title: `fix(ci): scope critical-css-gate to docs changes + fix stale Playwright cache (#3624)`.
- [ ] 4.3 Run `/soleur:compound` after merge to capture the workflow-conditional + cache-key learnings.
- [ ] 4.4 Confirm `/soleur:ship` Phase 7 on a server-only PR no longer flags `critical-css-gate` as a blocking check (smoke-verify via the next non-docs PR after merge).

## 5. Post-merge monitoring

- [ ] 5.1 Watch first 5 non-docs PRs after merge — gate must be skipped on each.
- [ ] 5.2 Watch first docs-touching PR after merge — gate must run green.
- [ ] 5.3 If gate fails with chromium-binary error within 14 days on a docs PR, escalate to "drop cache entirely" fallback per plan's Alternatives section.
