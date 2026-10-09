# Tasks: bound the in-container apt cycle in the provision-unit and cutover-access suites (#9395)

Plan: `knowledge-base/project/plans/2026-10-08-ci-bound-in-container-apt-provision-unit-cutover-access-plan.md`

Spec lacks a valid `lane:`, so the plan defaults to cross-domain (fail-closed).

## Phase 0: Preflight

- 0.1 `git fetch origin main`; if PR #9783 has merged, rebase onto `origin/main` before touching the PU suite
- 0.2 Record baselines: `apt-bounded.test.sh` (19 passed) and `git-data-cutover-access.test.sh` totals (`N + S = 549`)

## Phase 1: Guard first (RED)

- 1.1 Extend A10 in `apps/web-platform/infra/apt-bounded.test.sh`
  - 1.1.1 Add the cutover and provision-unit suites to the spec list as `file:want_unmounted:statevar` (`T`, `W`); parse with `IFS=: read`
  - 1.1.2 Define the docker-site and raw-apt grammars once as named variables (widened prefix set, optional `timeout [-k N] N`); add positive and negative sample lines
  - 1.1.3 Widen the arm-adjacency awk and the `g_ok` regex (per-suite variable); census `-eq 8`; pass text `8 mounted sites + 2 declared unmounted`
  - 1.1.4 Add the population census (docker-run site plus apt text must be a declared consumer; all four consumers seen); failure messages name the suite, property, file and remediation
- 1.2 Run the suite: A10 must be RED naming both unconverted suites; A1-A19 green

## Phase 2: Convert the consumers (GREEN)

- 2.1 Cutover suite (`git-data-cutover-access.test.sh`)
  - 2.1.1 `APT_LIB`, `APT_BUDGET_S=270` (comment: 55 s healthy, 2026-10-08), readable guard, shellcheck source line, source the lib
  - 2.1.2 Replace the `drive.sh` apt loop with the lib source line and `gd_apt_install_bounded ... || exit $?`
  - 2.1.3 Arm just before `timeout -k 10 480 docker run`, add the `/work/apt` mount, `gd_apt_state_summary` after `docker rm -f`
  - 2.1.4 Leave `FLOOR`, `MUTANT_FLOOR`, `RUNTIME_ROWS` and the result classification untouched
- 2.2 Provision-unit suite (`cloud-init-inngest-provision-unit.test.sh`, hunks clear of PR #9783)
  - 2.2.1 After `tb_ok()`: `APT_LIB`, `APT_BUDGET_S=150` (comment: 20 s healthy, 2026-10-08); add `rc` to `tierb()`'s locals
  - 2.2.2 Restructure the build block: lib guard, source, arm with the exact tail, multi-line `bash -c` body, `rc=$?`, `gd_apt_state_summary`
  - 2.2.3 Classify: marker or rc 125 -> `tb_skip` carrying the cause line; any other rc -> counted Tier B FAIL with rc and log tail
- 2.3 `apt-bounded.test.sh` -> `19 passed, 0 failed`; shellcheck the three edited scripts
- 2.4 ADR-188: two-line addition inside the 2026-10-01 amendment

## Phase 3: Real-docker proof

- 3.1 Cutover suite with docker: totals equal the baseline; one `GD_APT:` line
- 3.2 Forced decline (one-second-budget dot-prefixed temporary copy): local SKIP of 27 rows, `CI=true` FAIL, floor exact in both; delete the copy
- 3.3 PU suite with the Tier B image removed: build path runs and passes; forced decline under `CI=true` is a named SKIP

## Phase 4: Mutation battery and ratchets

- 4.1 Drive the Guard Contract matrix in the scratchpad; record results for the PR body
- 4.2 `git add` the edited suites, then run `scripts/guard-vacuity-floor.test.sh` and `plugins/soleur/test/fixture-env-adoption.test.sh`

## Phase 5: Record

- 5.1 PR body: `Closes #9395`, `Refs #8744`, `Refs #9379`; do not close #8211, #9377 or #8609
