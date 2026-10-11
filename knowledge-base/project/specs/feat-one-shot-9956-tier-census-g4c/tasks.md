# Tasks — feat-one-shot-9956-tier-census-g4c

Plan: `knowledge-base/project/plans/2026-10-11-fix-tier-census-g4c-merge-base-plan.md`
Issue: #9956

## Phase 1 — Guard fix (tests/scripts/test-infra-privileged-tier-census.sh)

- [x] 1.1 Source the canonical fixture environment BEFORE any fixture work:
  `source plugins/soleur/test/lib/git-fixture-env.sh` + `git_fixture_env "$T"`
  (the #7849 tripwire — refuses an inherited `GIT_DIR`; supplies the synthesized
  identity, `GIT_CEILING_DIRECTORIES`, config hermeticity). No hand-rolled
  `git config user.email`.
- [x] 1.2 Extract base resolution + materialization into helpers:
  `resolve_base_ref <repodir>` (honors `IPT_BASE_REF` verbatim; else echoes
  `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C <repodir>
  merge-base HEAD origin/main`; else echoes `origin/main`) and
  `materialize_base_dir <repodir> <ref> <destdir>` (the existing
  `git ls-tree`/`git show` per-root loop at `:1939-1952`, unchanged semantics).
- [x] 1.3 Replace `BASE_REF="${IPT_BASE_REF:-origin/main}"` at `:82` with the
  helper call; keep all git calls `-C "$REPODIR"`-qualified and `env -u`-scrubbed.
  *Deviation:* the assignment moved to the materialization site (~`:2006`) —
  `resolve_base_ref` guards its operand with `assert_fixture_dir`, defined after
  `:82`, so resolution is deferred to first use.
- [x] 1.4 Update the seam comment at `:69` (`IPT_BASE_REF … default origin/main`)
  and the G4c comment block at `:874` to name merge-base semantics.
- [x] 1.5 Write the failing fixture leg FIRST (TDD): synthetic git repo under
  `$T` (A,B at merge-base; C added on `origin/main` after the fork via
  `git update-ref refs/remotes/origin/main`; HEAD deletes B). Assert the merged
  semantics: G4c greens when B is claimed and C is never an orphan; assert the
  old verdict by re-running the same fixture under `IPT_BASE_REF=<tip sha>`.
  *Landed as legs b2 (post-fork invisible) and b6 (override → tip semantics).*
- [x] 1.6 Add mutation-matrix legs: unclaimed-deletion RED (B named, C not);
  second-member row (only B2 deleted → B2 named, B not); `removed{destroy=false}`
  claim → GREEN; `IPT_BASE_REF=<tip>` override → tip semantics verbatim (C named);
  no-`origin/main` repo → "base unavailable" fail-closed.
- [x] 1.7 Create `scripts/probe-tier-census-g4c-base.sh` (discoverability
  wrapper: greps the suite file for the merge-base resolution, prints the
  literal `merge-base`).
- [x] 1.8 Run `bash tests/scripts/test-infra-privileged-tier-census.sh`; all rows
  green including new legs (AC6 — 360/360). `operator-9321-stages.test.sh` only
  asserts the G7d row's verdict line and anticipated G4c reds on behind-main
  branches — unaffected.

## Phase 2 — Verification & ship

- [x] 2.1 Verify ACs 1–7 against the diff (AC1/AC7 greps; AC2–AC5 by legs b1–b7).
- [x] 2.2 `npx markdownlint-cli2` the plan file and this tasks.md before commit.
- [ ] 2.3 Commit with `Closes #9956` in the PR body via soleur:ship (not the title).
