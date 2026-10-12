# Tasks: affected edges — under-cover siblings (issue #9969)

Plan: `knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md`

## Phase 1: Battery rows, RED-first

- [ ] 1.1 In `scripts/test-all-affected.test.sh`, add `scripts/guard-vacuity-floor`,
  `scripts/lint-orphan-test-suites`, and `scripts/lib/repo-write-boundary.test.sh`
  to `build_sandbox`'s injected `run_suite` case keep-list.
- [ ] 1.2 Add `th1` — `SANDBOX_DIFF_NAMES=knowledge-base/x.test.sh` selects all three labels.
- [ ] 1.3 Add `th2` — `knowledge-base/x.sh` selects only `scripts/lib/repo-write-boundary.test.sh` of the three.
- [ ] 1.4 Add `th3` — `knowledge-base/x.md` selects none of the three.
- [ ] 1.5 Add `th4` — per-root loop: `bin/x.test.sh`, `infra/a/b.test.sh`, `docs/x.test.sh`,
  `test/x.test.sh`, `tests/x.test.sh`, `knowledge-base/a/b/c.test.sh` each select the
  `*.test.sh` pair.
- [ ] 1.6 Add `th5` — `--print-affected-set` receipt reports `edge:declared` for
  `scripts/lib/repo-write-boundary.test.sh`.
- [ ] 1.7 Run `bash scripts/test-all-affected.test.sh`; record the unlisted-root `th` rows RED
  (the `test/`/`tests/` members may pass already — they are regression pins).

## Phase 2: Declared-edge arrays

- [ ] 2.1 Re-run `git ls-files | awk -F/ 'NF>1{print $1}' | sort -u`; reconcile the root set
  against the plan's 20-root list.
- [ ] 2.2 Rewrite `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` in
  `scripts/lib/test-affected-paths.sh`: `glob:<root>/**.test.sh` for every root +
  `scripts/fixtures/` + `scripts/test-all.sh` + `scripts/lib/test-affected-paths.sh`.
- [ ] 2.3 Rewrite `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS`: `glob:<root>/**.test.sh`
  for every root; keep `.github/` and `scripts/` dir prefixes; explicit
  `apps/web-platform/infra/run-registered-suites.sh`, `scripts/lint-orphan-test-suites.test.sh`,
  `scripts/lib/test-affected-paths.sh`.
- [ ] 2.4 Add `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`:
  `glob:<root>/**.sh` for every root + `scripts/test-all.sh` +
  `scripts/lib/repo-write-boundary.sh` + `scripts/lib/repo-write-boundary.test.sh` +
  `scripts/lib/test-affected-paths.sh`.
- [ ] 2.5 Update each array's comment block with the verified read set the disposition
  derives from.

## Phase 3: Verification

- [ ] 3.1 `bash scripts/test-all-affected.test.sh` exits 0 — all `th` rows GREEN.
- [ ] 3.2 `bash scripts/lint-orphan-test-suites.sh` exits 0 — census green, zero dead edges.
- [ ] 3.3 `bash scripts/guard-vacuity-floor.test.sh` and `bash scripts/lint-orphan-test-suites.test.sh` exit 0.
- [ ] 3.4 `bash scripts/test-all.sh --affected --print-affected-set` shows `edge:declared`
  for the three labels.
- [ ] 3.5 `git diff --name-only $(git merge-base HEAD origin/main)` limited to
  `scripts/lib/test-affected-paths.sh`, `scripts/test-all-affected.test.sh`, and planning
  artifacts — no edits to `_affected_add_edge`, `_diff_edge_hit`, the census arm, or `GLOBENT`.
