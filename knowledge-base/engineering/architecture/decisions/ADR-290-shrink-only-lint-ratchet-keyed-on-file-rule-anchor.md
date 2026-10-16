---
title: Shrink-only lint ratchet keyed on path, rule and anchor
status: active
date: 2026-10-16
---

# ADR-290: Shrink-only lint ratchet keyed on path, rule and anchor

## Context

GitHub Code Quality reported 169 findings on `main` (tracker #10331). Most were the recurring habits of agent-written code: unclosed files, empty handlers, unused imports and bindings. The repository needed deterministic linters in its own gates, and existing findings could not all be fixed in the PR that introduces a linter (shipped scripts are a brand-risk surface), so each linter needs a baseline that can only shrink.

The existing count ratchets (`apps/web-platform/test/eslint-config.test.ts`, 192 findings) are rename-blind: a count survives a file being swapped for another. They also live inside a required-context test, so folding new directories into them would force a re-baseline of an unrelated gate.

Alternatives rejected:

- **A count highwater file per scope.** Rename-blind and swap-blind; the brainstorm CTO ruling already chose identity keys over counts.
- **An advisory CI job (as `lint-webplat` is).** It cannot block a regression, which is the whole point.
- **Extending the web-platform `eslint .` run and its 192-count test.** It would re-pin that required-context test's counts and file-count floors for directories it does not own.
- **A `(digest, epoch)` header, or an anchor-at-merge-base lookup, to police baseline edits.** A header that carries its own hash certifies itself, and the lookup was vacuous for generic lines while making an in-place edit of a baselined line a dead end (plan review, CTO rulings of 2026-10-16).

## Decision

`scripts/lint-ratchet.py` owns two scopes, `ruff` and `eslint-test-dirs`, each with a baseline file (`scripts/lint-ratchet-<scope>.baseline.txt`) of entries `path|rule|anchor|n`. `anchor` is the first 12 hex of the sha256 of the finding's whitespace-normalised source line (the text is never stored); `n` is the ordinal among identical `(path, rule, anchor)` triples. `--check` enforces, in order: the baseline exists; the tool ran and its report parsed; the scan saw at least a floor of files (ruff 55, eslint 105); the baseline EQUALS the live census (a new finding fails, and so does a stale entry); and per `(path, rule)` the baseline never holds more entries than at the merge base, after applying `git diff -M30%` renames measured against the working tree (so a staged `git mv` passes at pre-commit time). `--update` rewrites the baseline from the live census and refuses to grow it; `--list` prints the live findings.

Counting is waiver-proof (ruff `--ignore-noqa`, eslint `--no-inline-config`) and no tool runs in a fix mode. Ruff is provisioned by the script itself: `scripts/ruff-requirements.txt` pins `ruff==0.16.10` with a sha256 for each of the 17 wheels, installed with `pip --isolated --require-hashes --only-binary=:all:` into a per-user `0700` cache with ownership checks and a scrubbed `PIP_*`/`PYTHON*` environment. A hash mismatch is exit 2 everywhere; an unreachable index is a loud `SKIP` locally and exit 2 under `CI`. `ruff.toml` selects `SIM115`, `S110`, `S112`, `F401`, `F841` with `check-typed-exception = true`.

Registration: a `run_suite` pair (`tests/scripts/lint-ratchet`, `scripts/lint-ratchet-ruff-live`) in the required `test` context, both always-on in `scripts/lib/test-affected-paths.sh`; the eslint live arm is `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (in `REPO_WIDE_SUITES`); two lefthook pre-commit entries with dual globs. Exit codes: 0 clean, 1 drift or vacuity, 2 infrastructure.

**Control.** CODEOWNERS is documentation only here: the repository has a `* @deruelle` fallback and no ruleset requires code-owner review. The controls are the merge-base comparison, the pin test in `tests/scripts/test_lint_ratchet.py` (parses `ruff.toml` with `tomllib` and asserts the rule set, `check-typed-exception`, `extend-exclude`, the scope tuple and both floors), and human PR review of the tooling.

**PR3b contract.** The entry format, the exit codes and the scope-config dict that `check()` takes (`name`, `baseline`, `floor`, `run`, `remedy`, `drawdown`) are the interface. PR3b will `git mv` the script into the plugin and change one path constant in the tests; it supplies its own scope-config for user repos.

**Bumping ruff.** Take the version and one sha256 per wheel from `https://pypi.org/pypi/ruff/<version>/json`, replace the pin and all hash lines in `scripts/ruff-requirements.txt`, then run `python3 scripts/lint-ratchet.py ruff --update`; any finding the new version adds is fixed or the bump is held.

## Consequences

A new unclosed file, empty handler, unused import or unused binding in tracked Python, or an unused binding in the scoped test and fixture directories, now fails `lefthook` and the required `test` context. The 59 ruff and 20 eslint findings that exist today are baselined and tracked for drawdown in #10433; none is fixed here. A Dependabot eslint bump that moves findings fails the vitest arm and is fixed or held (no escape hatch is built until one is first needed).

Accepted residuals, none of which the check can see:

1. A fix of finding A plus a new finding B inside one `(path, rule)` is invisible: the count is unchanged.
2. A rename below the `git diff -M30%` similarity cutoff reads as growth; fix the findings in the same PR.
3. A diff that also changes the baseline-path constant presents the baseline as "absent at base" and skips the delta.
4. The pin test and the config can be edited together in one diff; only human review stops it.

Two PRs that each delete one of two identical baselined lines merge cleanly and leave a stale `n=1`; the stale message and the baseline header say to take the base branch's copy and re-run `--update`. Anchors are read from the working tree, so a partially staged commit can disagree with the index; the full-tree CI run is the backstop.

Tracker: Ref #10331. Drawdown: #10433.
