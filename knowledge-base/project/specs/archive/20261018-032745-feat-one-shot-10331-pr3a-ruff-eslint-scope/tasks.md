# Tasks: ruff and widened eslint no-unused-vars with shrink-only baselines (PR3a of #10331)

Plan: knowledge-base/project/plans/2026-10-16-chore-ruff-eslint-ratcheting-linters-pr3a-plan.md
Issue: #10331 (Ref only; never Closes) | Draft PR: #10426 | Branch: feat-one-shot-10331-pr3a-ruff-eslint-scope | lane: cross-domain

## Phase 0: Tests first (RED)

- 0.1 Capture real tool output as fixtures: run the pinned ruff (`uvx ruff@0.16.10`) and `apps/web-platform/node_modules/.bin/eslint` once on a synthetic snippet; commit the JSON under `tests/scripts/fixtures/lint-ratchet/` (synthetic source only)
- 0.2 Write `tests/scripts/test_lint_ratchet.py` (importlib loader for the hyphenated script; git fixtures via `tests/scripts/_git_fixture_env.py`)
  - 0.2.1 Entry formatting, anchor normalisation, `n` counting, baseline parsing (shuffled order, blank and `#` lines)
  - 0.2.2 `check` verdicts: new finding, stale entry, `[]` output, count growth per `(path, rule)`, edit-swap, line move, rename map, copy to new path, baseline missing, base absent, base unresolvable under `CI`
  - 0.2.3 Guard 2: floors fire (and an inverted comparison reddens the test), empty scan, pin test (parse `ruff.toml` with `tomllib`; assert `select` set, `check-typed-exception`, `extend-exclude`, scope tuple, floors)
  - 0.2.4 Guard 3: pip argv carries `--require-hashes --only-binary=:all:`; stubbed pip fail/succeed; wrong `RUFF_BIN` version; AC10 argv assertion (no fix flags, ruff has `--no-fix`)
  - 0.2.5 Loaded-case-count sentinel so a zero-test run fails; `setUp` scrubs `CI`, `PIP_*`, `PYTHON*`, `XDG_CACHE_HOME`, `HOME`, `PATH`; violating samples built at runtime, never committed as `.py`
- 0.2.6 Extra rows from deepen review: ordinal shift, ruff rc 2 / garbage output, zero-finding run, `--update` idempotent and sorted, floor boundaries (54/55, 104/105), `|` in a path, symlink, hostile `--base`, cache root symlink / foreign owner / group-writable, duplicate-delete merge case, staged-rename state
- 0.3 Write `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (live arm only, `expect.assertions`)
- 0.4 Run both red; record the red output for the PR body (AC1)

## Phase 1: Ratchet script

- 1.1 `scripts/lint-ratchet.py`: scope table, entry model, baseline read/write, `--check`, `--update`, `--list` (live findings), `--base`
- 1.2 Merge-base logic: default `git merge-base origin/main HEAD`, `git diff -M --name-status` rename map, per-`(path, rule)` count rule, introduction note, exit 2 under `CI` when unresolvable
- 1.3 Floors: ruff 55 (`ruff check --show-files`), eslint 105 (report length); fatal eslint parse error exits 2
- 1.4 Ruff provisioning inside the script (no `RUFF_BIN`, no PATH shortcut): per-user `0700` cache with lstat/uid/mode checks, `[sys.executable, -I, -m, pip, ...]` with `--isolated --no-input --no-deps --disable-pip-version-check --index-url https://pypi.org/simple --only-binary=:all: --require-hashes --target <fresh mkdtemp>`, scrubbed `PIP_*`/`PYTHON*` env, atomic rename, version assertion at execution, hash mismatch always exit 2, network failure SKIP locally / exit 2 under `CI`, one-time install notice; no `timeout`, `sha256sum` or GNU-only flags
- 1.4.1 Hardening: `--base` resolved by `git rev-parse --verify --end-of-options`, `-z` and `--` on every git call, reject paths containing `|` or a newline, skip tracked symlinks, never invoke ruff with an empty list
- 1.4.2 Failure output: live `path:row`, rule, tool message, fixed remedy text (AC16); `--update` refuses growth vs the base; baseline header documents `--list`/`--update` and the conflict recipe
- 1.4.3 Delta compares base against the WORKING TREE (`git diff -M30% -z --name-status <sha>`) so a staged rename passes at pre-commit
- 1.4.4 `check()` takes a plain scope-config dict (PR3b can move the file)
- 1.5 Counting flags: ruff `--ignore-noqa --no-cache --no-fix --force-exclude`; eslint `--no-inline-config --no-error-on-unmatched-pattern`; never a fix mode

## Phase 2: Ruff wiring

- 2.1 `ruff.toml` (`py311`, `extend-exclude = ["knowledge-base"]`, select `SIM115 S110 S112 F401 F841`, `check-typed-exception = true`)
- 2.2 `scripts/ruff-requirements.txt`: `ruff==0.16.10` plus all 17 wheel hashes (from the PyPI JSON; no trailing comments after the backslash)
- 2.3 Derive `scripts/lint-ratchet-ruff.baseline.txt` with `--update`; confirm 59 entries and per-code counts against `ruff check --statistics` (AC2)

## Phase 3: ESLint wiring

- 3.1 `apps/web-platform/eslint.test-dirs.config.mjs` (one rule per language family, `^_` patterns, `reportUnusedDisableDirectives: "off"`)
- 3.2 Scope tuple in the script: `test/**`, `plugins/soleur/test/**`, `plugins/soleur/skills/*/test/**`, `scripts/*.test.mjs`
- 3.3 Derive `scripts/lint-ratchet-eslint-test-dirs.baseline.txt`; confirm 20 entries (AC3)
- 3.4 Confirm AC4: the existing eslint config, its guard test and `package.json` are untouched

## Phase 4: Registration

- 4.1 `scripts/test-all.sh`: `tests/scripts/lint-ratchet` and `scripts/lint-ratchet-ruff-live` run_suite lines
- 4.2 `scripts/lib/test-affected-paths.sh`: both labels in `ALWAYS_ON_SUITES`; check `--print-selection` and `scripts/lint-orphan-test-suites.sh` (AC8); check shard-totality and manifest tests
- 4.3 `lefthook.yml`: `ruff-ratchet` and `eslint-test-dirs-ratchet` (dual globs); verify with a staged `scripts/x.py`, a staged root-level `y.py` and a staged `test/*.test.ts` (AC7)
- 4.4 `apps/web-platform/test/repo-wide-suites.ts`: add `test/eslint-test-dirs-ratchet.test.ts`; run `repo-wide-containment.test.ts` (AC17). No CODEOWNERS rows (not an enforced control here)

## Phase 5: Records

- 5.1 ADR-290 via `soleur:architecture` (alternatives, human-review control with CODEOWNERS documented as non-enforcing, PR3b contract, bumping-ruff recipe, four residuals); probe the ordinal across every pushed `origin/*` ref
- 5.2 Run `bash plugins/soleur/test/c4-count-parity.test.sh` (AC13)
- 5.3 File the drawdown issue (labels `deferred-scope-out`, `chore`, `domain/engineering`, `priority/p3-low`; milestone `Post-MVP / Later`; body `Ref #10331` plus baseline links); put its number in both baseline headers
- 5.4 PR body: `Ref #10331`, mutation evidence (AC5), decision-challenges rendering by `ship`

## Phase 6: Verification

- 6.1 Six live mutation rows on a scratch commit stacked on the PR head with `--base` (AC5, AC6)
- 6.2 AC12 diff-scope command; AC11 baseline-shape regex; AC9 hash count
- 6.3 `bash scripts/test-all.sh scripts` shard for the new labels and `bash scripts/test-all.sh webplat` for the vitest guard
- 6.4 First CI run: confirm the pinned ruff installs on the runner image
- 6.5 AC16 failure-output assertions; AC18 `bash scripts/lint-shell-trace-credential-refusal.test.sh`
