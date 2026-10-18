# Tasks: plugin detect-and-run lint ratchet (slice 2 of #10331)

Plan: `knowledge-base/project/plans/2026-10-18-feat-plugin-detect-and-run-lint-ratchet-plan.md`. Ref #10331 (stays open); Closes #10507 when both carry-ins are green. Rulings: `decision-challenges.md` (rows 11-20 bind over rows 2-5 and 8 where they conflict).

## Phase 0: Setup and preconditions

- 0.1 Verify: `python3 scripts/lint-skill-body-budget.py --base origin/main` (green today); `wc -c` of both SKILL.md files against `plugins/soleur/test/skill-body-budget.json` (work headroom 265 B, review 48 B)
- 0.2 Exercise ruff without `--config` and without `--ignore-noqa` with the pinned wheel in a tmp repo for each of `ruff.toml`, `.ruff.toml`, `pyproject.toml` with `[tool.ruff]`; paste the verified line into the PR body
- 0.3 File one tracking issue for the deferrals (user-mode JS/TS eslint, monorepo and workspace support, changed-files-only mode, opt-in telemetry gated on `soleur:legal:clo`, evaluating `ever-better`); milestone from `knowledge-base/product/roadmap.md`; reference #10331
- 0.4 Read all three of `model.c4`, `views.c4`, `spec.c4` before finalising the ADR addendum (the plan's C4 conclusion is "No C4 impact")
- 0.5 Confirm `git grep -n 'ruff-requirements' -- .github` is empty (plan time: empty)
- 0.6 Create `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` and run it once before the first commit

## Phase 1: Tests first (RED)

- 1.1 Add user-mode classes to `tests/scripts/test_lint_ratchet.py` using the `Repo` helper: exit-code matrix, totality rows, fingerprint rows, waiver rows, `--update` rows, master-only and `origin/HEAD` rows, deleted-baseline row, Soleur self-skip row, not-adopted-never-provisions row, cache-hint row
- 1.2 Add the SKILL.md anchor pin test (work and review; fences and HTML comments stripped; review pointer between the Bootstrap paragraph and the next `**What this agent checks:**` heading)
- 1.3 Add the second `it` to `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (runs `TestEslintConfigBehaviour`, asserts ran-not-skipped with the class's case count)
- 1.4 Grow `MIN_CASES` and the guard-class set in `test_every_guard_class_is_loaded`; scope `test_baseline_paths_follow_the_lint_convention` to the Soleur scopes
- 1.5 Run the four mutation rows and the harness rows from the plan's Guard Contract in a scratch sandbox

## Phase 2: Move and re-point

- 2.1 `git mv scripts/lint-ratchet.py plugins/soleur/scripts/lint-ratchet.py`; `git mv scripts/ruff-requirements.txt plugins/soleur/scripts/ruff-requirements.txt`
- 2.2 Replace `REPO_ROOT` with `resolve_root()` (git toplevel from the cwd); make pins script-relative; set `SCRIPT_REL`
- 2.3 Re-point `lefthook.yml` (commands and both glob lists), `ruff.toml` header, `scripts/test-all.sh` comment and command path, `scripts/lib/test-affected-paths.sh` (verify only), `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`, `apps/web-platform/eslint.test-dirs.config.mjs` header (and its pinned sha256 in the test), baseline headers via `--update`, the `tests/scripts/test_lint_ratchet.py` constants and patches
- 2.4 `git add` all new tracked files, then run `scripts/lint-orphan-test-suites.sh`

## Phase 3: Core implementation (GREEN)

- 3.1 Ruff-cache recovery hint in `ensure_ruff` and the version-probe message
- 3.2 `user-ruff` scope: detection (`ruff.toml`, `.ruff.toml`, `pyproject.toml` line anchored at line start), no `--config`, waivers honoured via a scope-dict key, three-check totality, no floor, `drawdown` and `script` None, absolute `recovery_cmd`, pinned-version hint on config-caused exit 2
- 3.3 Baseline `.lint-ratchet/ruff.baseline.txt`, adoption check before provisioning, `git check-ignore` line in `--update`
- 3.4 Merge-base ladder (`--base`, origin/HEAD, origin/main, origin/master, else skip-with-warning), not-a-git-repo `Skip`, deleted-baseline rule
- 3.5 Ruff-only toolchain fingerprint header, growth-skip when fingerprints differ, `--update` growth only on differing fingerprints
- 3.6 `auto` CLI scope (detect, Soleur self-skip, no-linter line, `user-ruff` verdict, catches `Skip`); docstring updated

## Phase 4: SKILL.md edits (byte-budgeted)

- 4.1 `work/SKILL.md` Phase 3 step 1: replace the `linting-agent` comment line with the `auto` call (net +92 B)
- 4.2 `review/SKILL.md`: add the `auto` pointer after the Bootstrap paragraph and remove the bench-pattern provenance sentence (net +13 B)
- 4.3 `work/references/key-principles.md`: reword the `use linting-agent` checkbox
- 4.4 `python3 scripts/lint-skill-body-budget.py --base origin/main` green; record the measured deltas

## Phase 5: Architecture record

- 5.1 ADR-290 addendum via `soleur:architecture`; update the PR3b contract paragraph; add rejected alternatives; delete residual 7
- 5.2 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` (no C4 edit is planned)

## Phase 6: Verification and ship

- 6.1 Run `python3 -m unittest tests.scripts.test_lint_ratchet`, both Soleur scope checks, the vitest arm, `bash scripts/test-all.sh --affected` (full battery if it degrades)
- 6.2 Run the discoverability wrapper and the acceptance greps
- 6.3 PR body: first line `Ref #10331`, `Closes #10507`, `## Changelog`, `semver:patch`, measured byte deltas, CI-log evidence for carry-in 2
- 6.4 After push, inspect the `test-webplat` shard log for both `it` names; `soleur:ship`, then `soleur:postmerge`
