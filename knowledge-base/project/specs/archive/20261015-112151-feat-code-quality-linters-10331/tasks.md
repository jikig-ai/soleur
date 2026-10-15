# Tasks: triage Code Quality findings and wire deterministic linters (#10331)

Plan: `knowledge-base/project/plans/2026-10-15-chore-code-quality-linters-triage-plan.md`
Each slice is its own PR (`Ref #10331`; the final merged slice carries `Closes #10331`).
PR1 ships from this branch (draft PR #10342); PR2 to PR4 branch from `main` after the previous slice merges. PR3b is off the critical path.

## PR1 — comparison findings

- 1.1 Locate the two `js/comparison-between-incompatible-types` sites (timeboxed)
  - 1.1.1 Browser automation (Playwright MCP) against the repository's Code Quality alert list
  - 1.1.2 If unauthenticated: local CodeQL CLI, JS quality suite over `apps/web-platform/server/`
  - 1.1.3 If neither works: ask the operator for the two file:line pairs; else close PR1 as "unlocatable" and file a follow-up issue
- 1.2 Write failing regression tests per located site in `apps/web-platform/test/` (RED first)
- 1.3 Decide per site: fix (tests GREEN) or dismiss the alert with a stated reason and link it in the PR body
  - 1.3.1 If a guard is defeatable: halt PR1, route to the CLO for the Art. 33 assessment; PR2 to PR4 continue
- 1.4 Run `soleur:gdpr-gate` on the diff
- 1.5 Add a "Resolution" section to `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`

## PR2 — shipped-script handlers

- 2.1 Derive the work list: pinned `uvx ruff==0.17.0` with S110,S112,BLE001 and `check-typed-exception = true` over `plugins/soleur/**/*.py` excluding `test/` and fixtures (five scripts at plan time)
- 2.2 Write tests first
  - 2.2.1 Proxy canary-secret test run as a real subprocess; assert the canary never reaches stderr and refuse/withhold results are unchanged
  - 2.2.2 Stderr-note cases for `founder-check.py`, `resolve-debt.py`, `scan-ancestor-signal-helpers.py`, `redact-engine.py`
- 2.3 Add a guarded `_note(exc)` helper per script (class name only, own `OSError` guard) and call it from teardown handlers; leave fail-closed arms untouched
- 2.4 File the tracking issue for the `py/empty-except` unknown with its decision rule

## PR3a — repo linters

- 3a.1 Ruff baseline ratchet
  - 3a.1.1 Write `scripts/ruff-ratchet.test.sh` first: six Guard 1 mutation rows plus harness rows
  - 3a.1.2 Add `ruff.toml` (`required-version`, selected rules, `check-typed-exception`, exclude `knowledge-base/**`)
  - 3a.1.3 Add `scripts/ruff-ratchet.py` modelled on `lint-shell-capture-exit.py`: repo-relative paths, multiset baseline, `--changed --base`, `--check-shrink --base`, only-shrinks `--write-baseline`
  - 3a.1.4 Generate `scripts/ruff-ratchet.baseline.txt` (82 findings at plan time)
- 3a.2 Wire into required contexts
  - 3a.2.1 Register the suite and the live run in `scripts/test-all.sh`
  - 3a.2.2 Add the `ALWAYS_ON_SUITES` entry in `scripts/lib/test-affected-paths.sh`; verify with `scripts/lint-orphan-test-suites.sh`
  - 3a.2.3 Add the lefthook entry (dual-glob convention) and the pinned ruff install in an existing job; report added job-minutes
- 3a.3 ESLint scope
  - 3a.3.1 Extend `apps/web-platform/package.json` lint args, `lintScriptArgs()`, `MIN_FILES_BY_DIR` (key `plugins/soleur/test`, floor 100) and re-pin `BASELINE_BY_RULE` in `eslint-config.test.ts`; add the `eslint-disable` count pin
  - 3a.3.2 Only if flat config ignores the paths: fall back to a root config resolved via `createRequire`
- 3a.4 Add one paragraph to ADR-242; offsetting trim plus pointer line in `work/SKILL.md`

## PR3b — plugin detect-and-run

- 3b.1 Write Guard 3 fixture tests first (eslint-only, ruff-only, none, `lint`-script sentinel, errored config, timeout, output cap)
- 3b.2 Add `plugins/soleur/scripts/detect-project-linters.sh` (root-level `eslint.config.*` and `ruff.toml` only; never executes anything)
- 3b.3 Add the run step to `work/SKILL.md` and `review/SKILL.md` (installed binaries, explicit changed-file paths, timeout, output cap, base-branch config in review, advisory); ship offsetting trims within the byte ceilings

## PR4 — Code Quality decision

- 4.1 Write `knowledge-base/engineering/audits/2026-10-15-code-quality-rule-overlap.md` (22 rules, covered or none, uncovered share)
- 4.2 Write the dated ADR-276 amendment citing Decision 6 (do not edit the S5 row); record CLO and CTO sign-off
- 4.3 Add the Code Quality row to `knowledge-base/operations/expenses.md` with a `verify_by` estimate marker

## Every slice

- Run `plugins/soleur/test/c4-count-parity.test.sh`
- PR body: `Ref #10331`, precondition, and the action if the precondition fails
