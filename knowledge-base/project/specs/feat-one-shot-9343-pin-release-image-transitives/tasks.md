# Tasks: pin release-image CLI trees and retire the vestigial heavy-shard likec4 install

Plan: `knowledge-base/project/plans/2026-10-04-ci-pin-release-image-transitives-plan.md` (issue 9343, draft PR 9496).
Merge policy: the PR edits `.github/workflows/ci.yml`, so it must NOT be admin-merged.

## Phase 1: Guards and tests first (RED)

- 1.1 Extend `apps/web-platform/test/c4-likec4-version-pin.test.ts`
  - 1.1.1 Add `dockerfile` to `Likec4PinFiles` and `readPinFiles()`; scanner requires exactly one Dockerfile install line, with `--before`, same date, counted in `sites`
  - 1.1.2 Update self-test fixtures and loops: `good()` gets `dockerfile` and a two-line `ci`; row 5 `empty` gets `dockerfile: ""`; the date-replacement loops gain `"dockerfile"`
  - 1.1.3 ci.yml install-count assertion 3 to 2; add Dockerfile count 1
  - 1.1.4 Fix `BUMP_HINT` wording (date-only `--before` is midnight-exclusive: day AFTER the publish day)
  - 1.1.5 Structural test with a `FROM`-stage slicer and a `web-platform-build` job-block extractor: `runner` is the last `FROM` and is `FROM cli-tools`; the job has a `target: cli-tools` step with `no-cache: true`
  - 1.1.6 Add Guard 1 mutation rows (no flag, one-day date skew, second unflagged install, empty Dockerfile string, structural) and the must-PASS row (all sites moved to `2026-09-29`)
- 1.2 Add the claude-code lock assertion to `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` (app-local reads only); mutation rows from Guard 2; note the `hasInstallScript` residual
- 1.3 Edit `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`
  - 1.3.1 `likec4` row for `test-scripts` only, with an explanatory comment
  - 1.3.2 Light users list non-empty (includes `render-c4-model.test.sh`) or FAIL, not SKIP
  - 1.3.3 Synthetic-fixture mutation rows from Guard 3; leave `bun` and `gitleaks` untouched
- 1.4 Run the new tests and confirm they fail for the right reason before Phase 2

## Phase 2: Dockerfile and bump procedure

- 2.1 `apps/web-platform/Dockerfile`: add `cli-tools` stage (claude-code `RUN` byte-identical, likec4 `RUN` with `--before=2026-09-28`), `runner` becomes `FROM cli-tools AS runner`, move/renumber comments, keep the CACHE-ORDERING invariant above every `ENV BUILD_*`, no builder-stage line touched
- 2.2 `plugins/soleur/scripts/render-c4-model.sh`: `BUMPING LIKEC4` comment only (Dockerfile as literal-date site, drop "version-only ... #9343", midnight-exclusive rule, claude-code note); no literal install command in new prose

## Phase 3: Workflow (no admin merge)

- 3.1 `.github/workflows/ci.yml` `web-platform-build`: add the `cli-tools` no-cache build step (`timeout-minutes: 5`); refresh the job header comment
- 3.2 `.github/workflows/ci.yml` `test-scripts-heavy`: delete the likec4 install step; one-line comment
- 3.3 `.github/workflows/ci.yml` `test-webplat` and `test-scripts`: replace the stale "#9343 version-only" sentence; one-line keep-decision comment

## Phase 4: Records

- 4.1 ADR-050 short dated addendum (global-not-lock invariant, `--before` now covers the image, claude-code deliberately without)
- 4.2 `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`: fix the "(bun, likec4, gitleaks) on both jobs" line

## Phase 5: Verification

- 5.1 vitest on the six named files, then `./node_modules/.bin/tsc --noEmit` in `apps/web-platform`
- 5.2 `scripts-shard-runtime-coverage.test.sh`, `c4-count-parity.test.sh`, `lint-workflow-install-sites.sh` (and `.test.sh`), `in-image-copy-src.test.sh`
- 5.3 `docker build --no-cache --target cli-tools`, then a full `--target runner` build on a vendored context copy (second run shows the claude-code layer `CACHED`)
- 5.4 `git grep -n '#9343' -- .github plugins apps scripts` returns nothing
- 5.5 PR body: `Closes #9343`, no-admin-merge note, first-release rebuild cost, acceptance-wording note, recorded dissent
- 5.6 Post-merge (read-only): first `web-platform-release.yml` run is green
