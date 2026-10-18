# Tasks: plugin detect-and-run lint ratchet (slice 2 of #10331)

Plan: `knowledge-base/project/plans/2026-10-18-feat-plugin-detect-and-run-lint-ratchet-plan.md`. Ref #10331 (stays open); Closes #10507 when both carry-ins are green. Rulings: `decision-challenges.md` (rows 21-32 bind over rows 11-20, which bind over rows 1-9, where they conflict).

## Phase 0: Setup and preconditions

- 0.1 Verify: `python3 scripts/lint-skill-body-budget.py --base origin/main` (green today); `wc -c` of both SKILL.md files against `plugins/soleur/test/skill-body-budget.json` (work headroom 265 B, review 48 B)
- 0.2 Exercise ruff without `--config` and without `--ignore-noqa` with the pinned wheel in a tmp repo for each of `ruff.toml`, `.ruff.toml`, `pyproject.toml` with `[tool.ruff]`; paste the verified line into the PR body
- 0.3 File one tracking issue for the deferrals (user-mode JS/TS eslint, monorepo and workspace support, changed-files-only mode, opt-in telemetry gated on `soleur:legal:clo`, evaluating `ever-better`); milestone from `knowledge-base/product/roadmap.md`; reference #10331
- 0.4 Read all three of `model.c4`, `views.c4`, `spec.c4` in full before the C4 and ADR edits
- 0.5 Confirm `git grep -n 'ruff-requirements' -- .github` is empty (plan time: empty)
- 0.6 Create `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` (two stages: not-adopted and deleted-baseline; absolute script path; git under `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE`; `trap` cleanup; prints `LINT_RATCHET_PROBE_OK`) and run it once before the first commit

## Phase 1: Tests first (RED)

- 1.1 Add user-mode classes to `tests/scripts/test_lint_ratchet.py` using the `Repo` helper: state matrix (incl. `classify_user` parity between `auto` and `user-ruff --check`), totality rows, safety rows (symlinked config, `fix-only`, env scrub, relative `XDG_CACHE_HOME`), fingerprint rows (header-only edit still growth-checked, sentinel, stale header, deps-only `pyproject.toml` edit), waiver rows, `--update` rows, ladder rows (master-only, dangling `origin/HEAD`, `upstream/main`, shallow), deleted-baseline and baseline-without-config rows, script-identity self-skip row with a planted Soleur baseline, not-adopted-never-provisions row, injected raising stub for `auto`, cache-hint row, Soleur byte-identical-output row, poisoned-`SCOPES` isolation row
- 1.2 Add the SKILL.md anchor pin test (work and review; fences and HTML comments stripped; review pointer between the Bootstrap paragraph and the next `**What this agent checks:**` heading)
- 1.3 Add the second `it` to `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (runs `TestEslintConfigBehaviour`, asserts ran-not-skipped with the class's case count)
- 1.4 Grow `MIN_CASES` and the guard-class set in `test_every_guard_class_is_loaded`; scope `test_baseline_paths_follow_the_lint_convention` to the Soleur scopes
- 1.5 Run the four mutation rows and the harness rows from the plan's Guard Contract in a scratch sandbox (four rows only; the swallowed-`Skip` case is a unit row)

## Phase 2: Move and re-point

- 2.1 `git mv scripts/lint-ratchet.py plugins/soleur/scripts/lint-ratchet.py`; `git mv scripts/ruff-requirements.txt plugins/soleur/scripts/ruff-requirements.txt`
- 2.2 Keep `REPO_ROOT` for the Soleur scopes derived from the script location (`parents[3]`, assert `SCRIPT_REL` exists under it); add `resolve_root()` (git toplevel from the cwd) for user scopes only; make pins script-relative; set `SCRIPT_REL`
- 2.3 Re-point `lefthook.yml` (commands and both glob lists), `ruff.toml` header, `scripts/test-all.sh` comment and command path, `scripts/lib/test-affected-paths.sh` (verify only), `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`, `apps/web-platform/eslint.test-dirs.config.mjs` header (and its pinned sha256 in the test), baseline headers via `--update`, the `tests/scripts/test_lint_ratchet.py` constants and patches
- 2.4 `git add` all new tracked files, then run `scripts/lint-orphan-test-suites.sh`

## Phase 3: Core implementation (GREEN)

- 3.1 Ruff-cache recovery hint in `ensure_ruff` and the version-probe message
- 3.1b `sys.version_info` guard at the top; extend `argparse choices`, dispatch before `build_config`, root resolution inside the `try`; scope-dict keys (`waiver_note`, `strict_totality`, `ignore_noqa`, `header_tracker`, `floor`, `ladder`)
- 3.2 `user-ruff` scope: detection (`ruff.toml`, `.ruff.toml`, `pyproject.toml` line anchored at line start, tracked and root-level only), `lstat` refusal of symlinked/non-regular/over-1-MiB configs, no `--config`, `--no-fix --no-fix-only`, waivers honoured via a scope-dict key, `RUFF_*`/`PYTHON*` scrub, relative `XDG_CACHE_HOME` ignored, git with `-c core.fsmonitor=false`, three-check totality, no floor, first-stderr-line only, `REPO-CONTENT:` prefix, `drawdown` and `script` None, machine-independent header, pinned-version hint on config-caused exit 2
- 3.3 Pure `classify_user` (script-identity Soleur self-skip, no-linter, not-adopted, baseline-without-config, deleted, untracked) run before provisioning; baseline `.lint-ratchet/ruff.baseline.txt`; `git check-ignore` line in `--update`
- 3.4 Merge-base ladder (each rung verified: `--base`, origin/HEAD, origin/main, origin/master, upstream/main, upstream/master, local main, local master, else skip-with-warning; local rung WARN; shallow hint), not-a-repository `Skip` only on git's own stderr, bare-repo message, deleted-baseline rule
- 3.5 Ruff-only toolchain header (16-hex hash of ruff configs and `[tool.ruff...]` tables); growth skipped only when merge-base header differs from HEAD header and HEAD header equals live; `CONFIG CHANGED` sentinel; stale-header and older-plugin lines; `--update` growth only when the HEAD header differs from live
- 3.6 `auto` CLI scope (maps `classify_user` to a line and exit, delegates to `check`, catches `Skip`, accepts only `--check` and `--base`); SKIP/WARN lines never `OK`; docstring updated

## Phase 4: SKILL.md edits (byte-budgeted)

- 4.1 `work/SKILL.md` Phase 3 step 1: replace the `linting-agent` comment line (48 B) with the 293 B guarded `auto` line from the plan (net +245 B of 265 B)
- 4.2 `review/SKILL.md`: add the 213 B `auto` pointer after the Bootstrap paragraph and remove the bench-pattern provenance sentence (149 B) and the `(parses ~100% ... vacuous "0 findings")` parenthetical (69 B) in the Bash-only bullet (net -5 B)
- 4.3 `work/references/key-principles.md`: reword the `use linting-agent` checkbox
- 4.4 `python3 scripts/lint-skill-body-budget.py --base origin/main` green; record the measured deltas

## Phase 5: Architecture record

- 5.1 ADR-290 Amendment 1 via `soleur:architecture`: edit the now-conditional Decision and Consequences sentences, update the PR3b contract paragraph, list the residuals, add rejected alternatives and the self-certifying-header tension, add `amended:`, delete residual 7
- 5.2 Add one sentence to the `platform.plugin` description in `model.c4` (lint-ratchet user mode, ADR-290: writes tracked files, PyPI egress, executes a downloaded hash-pinned binary; PyPI deliberately not modelled); regenerate `model.likec4.json`; run the five C4 tests

## Phase 6: Verification and ship

- 6.1 Run `python3 -m unittest tests.scripts.test_lint_ratchet`, both Soleur scope checks, the vitest arm, `bash scripts/test-all.sh --affected` (full battery if it degrades)
- 6.2 Run the discoverability wrapper and the acceptance greps
- 6.3 PR body: first line `Ref #10331`, `Closes #10507`, `## Changelog`, `semver:patch`, measured byte deltas, CI-log evidence for carry-in 2
- 6.4 After push, inspect the `test-webplat` shard log for both `it` names; `soleur:ship`, then `soleur:postmerge`
