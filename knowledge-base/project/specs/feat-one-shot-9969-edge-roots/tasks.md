# Tasks: affected edges — under-cover siblings (issue #9969)

Plan: `knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md`

## Phase 1: Battery rows, RED-first

- [x] 1.1 In `scripts/test-all-affected.test.sh`, add `scripts/guard-vacuity-floor`,
  `scripts/lint-orphan-test-suites`, and `scripts/lib/repo-write-boundary.test.sh`
  to `build_sandbox`'s injected `run_suite` case keep-list.
- [x] 1.2 Add `th1` — `SANDBOX_DIFF_NAMES=knowledge-base/x.test.sh` selects all three labels.
- [x] 1.3 Add `th2` — `knowledge-base/x.sh` selects only `scripts/lib/repo-write-boundary.test.sh` of the three.
- [x] 1.4 Add `th3` — `knowledge-base/x.md` selects none of the three.
- [x] 1.5 Add `th4` — per-root loop: `bin/x.test.sh`, `infra/a/b.test.sh`, `docs/x.test.sh`,
  `test/x.test.sh`, `tests/x.test.sh`, `knowledge-base/a/b/c.test.sh` each select the
  `*.test.sh` pair.
- [x] 1.6 Add `th5` — `--print-affected-set` receipt reports `edge:declared` for
  `scripts/lib/repo-write-boundary.test.sh`.
- [x] 1.7 Keep every `knowledge-base/` literal inside a `SANDBOX_*` env value or
  `_sandbox*`-named variable (the kb-consumers ratchet's fixture skip) — the `tg`
  rows' pattern, including the `"knowledge" + "-base/"` python concat where a bare
  literal would be scanned.
- [x] 1.8 Run `bash scripts/test-all-affected.test.sh`; record the unlisted-root `th` rows RED
  (the `test/`/`tests/` members may pass already — they are regression pins).

## Phase 2: Declared-edge arrays

- [x] 2.1 Re-run `git ls-files | awk -F/ 'NF>1{print $1}' | sort -u`; reconcile the root set
  against the plan's 20-root list.
- [x] 2.2 Append `glob:<root>/**.test.sh` for the 13 unlisted roots
  (`.agents .claude-plugin .codex .cursor-plugin .devin .grok LICENSES bin docs infra
  knowledge-base spike todos`) to `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` in
  `scripts/lib/test-affected-paths.sh` — all 9 existing entries stay verbatim.
- [x] 2.3 Append the same 13 `glob:<root>/**.test.sh` entries to
  `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS` — all 9 existing entries stay verbatim.
- [x] 2.4 Add `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`:
  `glob:<root>/**.sh` for all 20 roots + `scripts/test-all.sh` +
  `scripts/lib/repo-write-boundary.sh` + `scripts/lib/repo-write-boundary.test.sh` +
  `scripts/lib/test-affected-paths.sh`.
- [x] 2.5 Update each array's comment block with the verified read set the disposition
  derives from (recorded in the plan's Research Insights / disposition table).

## Phase 3: Verification

- [x] 3.1 `bash scripts/test-all-affected.test.sh` exits 0 — all `th` rows GREEN.
- [x] 3.2 `bash scripts/lint-orphan-test-suites.sh` exits 0 — census green, zero dead edges.
- [x] 3.3 `bash scripts/guard-vacuity-floor.test.sh` and `bash scripts/lint-orphan-test-suites.test.sh` exit 0.
- [x] 3.4 `bash scripts/test-all.sh --affected --print-affected-set` shows `edge:declared`
  for the three labels.
- [x] 3.5 `bash scripts/test-affected-kb-consumers.test.sh` exits 0 — no new baseline rows
  (a local `SKIP reason=no-trigger` is NOT proof CI skips it).
- [x] 3.6 `git diff --name-only $(git merge-base HEAD origin/main)` limited to
  `scripts/lib/test-affected-paths.sh`, `scripts/test-all-affected.test.sh`, and planning
  artifacts — no edits to `_affected_add_edge`, `_diff_edge_hit`, the census arm, or `GLOBENT`.
