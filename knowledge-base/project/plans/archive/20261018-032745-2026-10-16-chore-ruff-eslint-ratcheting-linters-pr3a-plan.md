---
title: "chore(quality): ruff and widened eslint no-unused-vars with shrink-only baselines (PR3a of #10331)"
type: chore
date: 2026-10-16
slug: ruff-eslint-ratcheting-linters-pr3a
branch: feat-one-shot-10331-pr3a-ruff-eslint-scope
issue: 10331
closes: none (Ref #10331 only)
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(quality): ruff and widened eslint no-unused-vars with shrink-only baselines (PR3a of #10331)

## Enhancement Summary

**Deepened on:** 2026-10-16
**Sections enhanced:** Overview, Research Insights, Architecture Decision, Observability (new), Implementation Phases 0 to 4, Guard Contract (all three guards), Files, Acceptance Criteria (AC16 to AC18 added), Test Scenarios, Risks, Sharp Edges
**Agents used:** security-sentinel, architecture-strategist, test-design-reviewer, spec-flow-analyzer (plus the earlier plan-review panel and two CTO rulings)

### Key Improvements

1. Supply-chain and local-execution hardening of the ruff install: per-user 0700 cache with ownership checks, isolated and scrubbed pip, no `RUFF_BIN` or PATH shortcut, hash mismatch never a SKIP.
2. Contributor-facing behaviour: failures print the live `path:row`, rule, tool message and remedy; a staged rename passes at pre-commit; `--update` refuses growth; the conflict recipe is in the baseline header.
3. Registration and conventions: the eslint arm joins `REPO_WIDE_SUITES`; baseline files follow `scripts/lint-*.baseline.txt`; CODEOWNERS rows dropped because no ruleset enforces them.
4. Test-design fixes: guard rows walked through the algorithm (several verdicts corrected), hermetic `setUp`, no committed violating `.py` fixtures, real-shape tool fixtures, boundary rows.

### New Considerations Discovered

- `ruff check` with no file arguments lints the current directory, so an empty file list must be refused before invocation.
- The new script and test join the ruff census and must themselves be clean (floor 55 of 64 leaves little slack).
- The first PR after merge is the first real run of the merge-base delta path; the scratch-commit harness (AC5) substitutes until then.

Tracker #10331 stays open: the PR body says `Ref #10331`, never `Closes`. Draft PR #10426 already exists for this branch.

## Overview

Third slice of #10331. PR1 (#10342, comparison triage) and PR2 (#10375, shipped-script handler notes) merged on 2026-10-15. This slice adds two deterministic linters to the repository's own gates, each with a baseline that can only shrink:

1. **ruff** over every tracked Python file outside `knowledge-base/`, selecting unclosed files (`SIM115`), empty handlers (`S110`, `S112`, typed handlers included), unused imports (`F401`) and unused variables (`F841`). Measured: 59 findings in 64 files.
2. **A second eslint scan** (`@typescript-eslint/no-unused-vars` for TS, core `no-unused-vars` for JS) over the test and fixture directories the web-platform run never reaches. Measured: 20 findings in 123 files.

Both flow through one script, `scripts/lint-ratchet.py`, with a small adapter per tool (an `if` on the scope name, not a plugin framework; PR3b can extend it). The "work/review gates" of this repository are, for this slice, the lefthook pre-commit hook (work) and the required `test` CI context (review). The plugin `work`/`review` SKILL.md files are untouched (PR3b). No existing finding is fixed here; a drawdown issue tracks them.

**Plan-review revision (2026-10-16).** Three reviewers (DHH, Kieran, code-simplicity) converged on cutting the `(digest, epoch)` header, the anchor-at-merge-base lookup, the two shell wrappers, the `--findings-json` seam, per-root floors and glob-liveness checks; the CTO agent accepted the cuts (decision-challenges.md rows 7 and 8) and superseded the header clauses of his first row-2 ruling. The shrink-only rule is now: live equals baseline exactly, and per `(path, rule)` the baseline count may not exceed the merge-base count.

**Deepen-plan revision (2026-10-16).** Security, architecture, test-design and flow reviews of the revised plan were applied: a per-user 0700 cache with ownership checks and a scrubbed, isolated pip run (no `RUFF_BIN`, no PATH-ruff shortcut); `--base` and path hardening; findings printed with `path:row`, rule, tool message and a fixed remedy text; the delta compares the working tree (staged renames pass at commit time); the eslint arm joins `REPO_WIDE_SUITES`; CODEOWNERS rows dropped (the repo has no required code-owner review, so they were not a control); baseline files renamed to the `scripts/lint-*.baseline.txt` convention; `check()` takes a plain scope-config so PR3b can move the file.

## Research Reconciliation: Spec vs. Codebase

| Spec / brainstorm claim | Reality (measured 2026-10-16) | Plan response |
|---|---|---|
| FR3: ruff scoped to "shipped Python" | The brief says "repo scripts and plugin scripts"; 17 of the 30 default-rule findings sit in `agent-browser/test/fixtures/*.py` | CTO ruling: all tracked `.py` outside `knowledge-base/`, fixtures included (row 4 of decision-challenges.md) |
| FR3: "root eslint config covering `test/` and `plugins/soleur/test/`" | Root `node_modules` has no TS parser; plugins resolve relative to the config file. `eslint --config apps/web-platform/<cfg>` run with cwd = repo root works (123 files, 3 s) | Config lives at `apps/web-platform/eslint.test-dirs.config.mjs`, run from the repo root; the 192-count ratchet is untouched |
| Brainstorm: "empty `except`" maps to ruff | `S110` defaults to untyped handlers only; typed `except OSError: pass` is invisible (learning 2026-10-15, session error 8). With `check-typed-exception = true` S110+S112 give 31 findings, close to CodeQL's 20 `py/empty-except` | `ruff.toml` sets `check-typed-exception = true` |
| Brainstorm: 76 tracked `.py`, 16 shipped | 78 tracked now; 64 outside `knowledge-base/` | Floor 55 measured on the 64 |
| Spec TR1: ratchet like the existing count ratchets | Count ratchets are rename-blind (learning 2026-08-04); brainstorm CTO ruling keyed on `file:rule` + content anchor | One new script with entry-level baselines; the existing 192 ratchet is left alone |
| Spec FR3 lefthook `glob: "**/*.py"` | gobwas `**` needs one intermediate directory (learning 2026-03-21), so root-level files would not match | Dual globs (`*.py` and `**/*.py`) |
| Baselines "ratchet down" against the merge base | The baselines do not exist at `origin/main`, so on this PR the merge-base comparison is skipped as "introduced by this diff" | `--base <ref>` option; the delta rows run on a scratch commit stacked on the PR head and in fixture repos (AC5) |

## Research Insights

**Premise Validation.** #10331 is OPEN. PRs #10342 and #10375 are merged (git log on main). The "no Python linter" claim holds: `git grep -w ruff|flake8|pyflakes` outside `knowledge-base/` hits one docs page only; no `ruff.toml`, `pyproject.toml` or `setup.cfg` exists. The "eslint scans only apps/web-platform" claim holds. The ADR corpus was grepped for "ratchet" and "linter" (ADR-076, 105, 106, 129, 133, 139, 151, 160 hit): none decides the mechanism proposed here, none lists it as rejected. Latest ADR ordinal on disk is ADR-288, so ADR-290 is the provisional next.

**Property List (Phase 0.6b).**

- P1. A newly introduced unclosed file, empty handler, unused import or unused variable in tracked Python fails a gate; the 59 existing ones do not.
- P2. A newly introduced unused binding in test or fixture JS/TS outside `apps/web-platform` fails a gate; the 20 existing ones do not.
- P3. Neither baseline grows: per `(path, rule)` the count may not exceed the merge-base count, and the baseline always equals the live census.
- P4. Both run where contributors and CI already run (lefthook, required `test` context) with a pinned ruff and a floor that proves the scan saw the tree.

**Cut List (Phase 0.6b and plan review).**

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| Extend the `lint` script and `eslint-config.test.ts` to the new directories | P2 | A separate config covers P2 without re-pinning the 192 / 1900-file floors of a required-context test (CTO row 1) |
| Count-only `.highwater` file for the new scopes | P1, P2 | Rename-blind; brainstorm CTO ruling already chose identity keys |
| Advisory CI job for ruff, like `lint-webplat` | P4 | Not blocking; the run_suite pair inside the required `test` context blocks (CTO row 3) |
| `work`/`review` SKILL.md edits | P1, P2 for user repos | PR3b scope |
| `E722`, `F811`, `BLE001` | none motivated | No incident; a later rule is added with its own baseline entries |
| Fixing the 79 baselined findings | none | Shipped scripts are a brand-risk surface; drawdown issue |
| `(digest, epoch)` header, `--rebaseline`, anchor-at-merge-base lookup | P3 | Live-equals-baseline plus per-`(path, rule)` count non-growth already give P3; the lookup was vacuous for generic lines and made editing a baselined line a dead end (reviews, CTO row 7) |
| `scripts/lib/ensure-ruff.sh` and `scripts/lint-ratchet-ruff.sh` | P4 | Folded into `lint-ratchet.py` (hashing was already Python) |
| `--findings-json` CLI seam, vitest "dispatch arm" | testability | Unit tests import the module with importlib and call its functions |
| Per-root floors, glob-liveness checks, Guard 3 text-grep tests | vacuity | Two total floors plus a unit test that parses the config and pins the scope tuple |
| Tool-agnostic adapter framework | PR3b reuse | Speculative; two scopes, one `if` |

**Value-proposition (Phase 0.6c).** No cost or performance saving is claimed. The one cost figure in the tracker (Code Quality at 4.4 % of CI job-minutes) belongs to PR4.

**Institutional learnings applied.**

- `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`: apply `git diff -M` renames before comparing against the merge base; fail closed when the base is unreachable under CI.
- `best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`: why the digest header was cut; the anchor is the merge-base copy plus human PR review of the tooling and the pin test (CODEOWNERS is not enforced here: no ruleset requires code-owner review).
- `workflow-issues/2026-09-27-a-blocking-gate-diffing-against-moving-main-fails-on-drift-and-staging-then-merging-deadlocks.md`: diff against the merge base, never moving `origin/main`.
- `2026-03-21-lefthook-gobwas-glob-double-star.md`: dual globs.
- `2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`: neither linter may run with a fix mode; fixtures are test input.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md`: unregistered suites are invisible to `--affected`; register both labels in `ALWAYS_ON_SUITES`.
- `2026-10-15-lint-wiring-issue-premises-were-half-shipped-and-misscoped.md`: measure scan scope before framing; its session error 8 names the S110 typed-handler blind spot and the non-blocking-job contradiction this plan avoids.

**Repository facts (file anchors).**

- `apps/web-platform/eslint.config.mjs` and `apps/web-platform/test/eslint-config.test.ts` (`BASELINE_FINDINGS = 192`, `MIN_FILES_SCANNED = 1900`): untouched.
- `scripts/lint-trap-tempfile-ownership.py` (`check_highwater`, `merge_base`): the merge-base comparison precedent; `scripts/lint-shell-capture-exit.baseline.txt`: the "keyed by path + class + normalised text, may only SHRINK" precedent.
- `scripts/test-all.sh` (run_suite pair at the `lint-workflow-step-env-refs` registration), `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`): suite registration. `scripts/*.test.sh` is not in `SUITE_GLOBS`, so explicit lines are the only registration. Python unit suites register as `python3 -m unittest tests.scripts.test_x` (precedent: `tests/scripts/lint-rule-ids`; `tests/` and `tests/scripts/` are namespace packages with no `__init__.py`).
- CI: `test-webplat` and `test-scripts` both check out with `fetch-depth: 0` (ci.yml near lines 1229 and 1470), so the merge base resolves. `test-scripts` has bash, python3 and stock node; no `setup-python`, no `apps/web-platform/node_modules`. `test-webplat` has the node_modules and runs `bash scripts/test-all.sh webplat` (vitest, which collects `test/**/*.test.ts`).
- Provisioning experiment: `python3 -m pip install --target <dir> --only-binary=:all: --require-hashes -r <requirements>` with the 17 PyPI wheel hashes of `ruff==0.16.10` installs `<dir>/bin/ruff` and reports `ruff 0.16.10`. Pin choice: 0.16.10 was released 2026-10-01 (15 days old); 0.17.1 is one day old. Both give identical counts.
- CLI verification (gate #2566): flags used and exercised locally on 2026-10-16 (ruff 0.16.10 / 0.17.1 via `uvx`, eslint 9.39.4): ruff `--config`, `--ignore-noqa`, `--output-format json`, `--no-cache`, `--no-fix`, `--force-exclude`, `--show-files`, `--statistics`; eslint `--config`, `--no-inline-config`, `--no-error-on-unmatched-pattern`, `-f json`.

**Phase 2.11 skip rationale (encryption posture).** No persistent data store and no runtime connection is introduced: the only data written is a hash-pinned ruff install in a per-user `0700` cache directory (scratch, no user data) and the baseline files (12-hex source-line fingerprints). The one network call is the build-time wheel fetch from PyPI over TLS with certificate verification on and the wheel's sha256 enforced by `--require-hashes`; it is the same class as the existing `npm ci`, actionlint and gitleaks installs in ci.yml and adds no component-to-component connection. Skipped per the "no persistent store and no new cross-component connection" rule.

## Open Code-Review Overlap

Queried open `code-review` issues for every planned file path. Matches, each acknowledged (different concern, remains open):

- `scripts/test-all.sh`: #8659 (EXIT-trap replacement in 33 suites), #7942 (mutation batteries run in no gate). Acknowledge: unrelated to this registration.
- `scripts/lib/test-affected-paths.sh`: #8800 (census sandbox inode sharing). Acknowledge.
- `apps/web-platform/test/repo-wide-suites.ts` and `lefthook.yml` matched no open code-review issue.
- `tests/scripts`: #10112 (#9786 residuals, unrelated infra). Acknowledge.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-290 via `soleur:architecture`: "Lint findings are admitted to a baseline by identity (`path|rule|anchor|n`), the baseline always equals the live census, and per `(path, rule)` its count may not exceed the merge-base count". It records the alternatives rejected in the Cut List (count highwater, advisory job, extending `eslint .`, digest/epoch header, anchor-at-base lookup), the human-review control (CODEOWNERS is documentation only: the repo has `* @deruelle` as a fallback and no ruleset sets `require_code_owner_review`), the PR3b contract (entry format, exit codes, the scope-config shape; PR3b will `git mv` the script into the plugin and change one path constant in the tests), a "bumping ruff" recipe (regenerate hashes from `https://pypi.org/pypi/ruff/<version>/json`), and the accepted residuals: a fix-A/add-B swap inside one `(path, rule)` is invisible; a rename below `git diff -M` similarity reads as growth (fix the findings or add an escape hatch when first needed); config weakening followed by `--update` is a legal shrink, stopped only by the pin test plus human PR review, and editing the pin test in the same diff is unenforced; a diff that edits the baseline-path constant presents "absent at base". The ordinal is provisional; `soleur:ship` re-verifies against `origin/main`. When renumbering, sweep `grep -rn 'ADR-290' knowledge-base/project/{plans,specs}/feat-one-shot-10331-pr3a-ruff-eslint-scope/`. Probe ordinal claims across every pushed branch (`git ls-tree -r --name-only <ref> -- knowledge-base/engineering/architecture/decisions/ | grep ADR-290` for each `origin/*`), not only `origin/main`, and again right before merge.

### C4 views

No change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors: `contributor` and `founder` already modeled, no new role; (b) external systems: GitHub CI is the existing `github` system; PyPI and the npm registry are not modeled today (the existing ci.yml `npm ci`, actionlint and gitleaks installs are likewise unmodeled build-time fetches), so a build-time ruff wheel fetch adds no modeled edge; (c) no container or data store touched; (d) no actor-to-surface access relationship changes. The derived-cardinality gate is unaffected (no cron monitors, heartbeats or workflows are added); run `bash plugins/soleur/test/c4-count-parity.test.sh` to confirm.

### Sequencing

The ADR describes the target state now (status accepted) and ships in this PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; a mis-tuned gate turns the repository's own required `test` context red (a blocked or delayed merge for a maintainer). No shipped script, server code or user data changes.
- **If this leaks, the user's data is exposed via:** no path: the ratchet reads source text only, stores 12-hex hashes of source lines (never the text), and runs no network call beyond one hash-pinned wheel fetch in CI.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the brainstorm's `single-user incident` came from PR1 (GDPR server code) and PR2 (redaction proxy); this slice changes neither (AC12 pins the diff scope), so the tier does not carry forward.

`threshold: none, reason: the diff adds lint configuration, a baseline and a check script; it edits no shipped script, no server or app code and no sensitive-path runtime logic.`

## Observability

The change ships developer tooling, not a runtime service; the surface a maintainer reads is CI and the local hook output. Phase 2.9's code-class path list does not name `scripts/`, so this section is the conservative reading of the deepen gate.

```yaml
liveness_signal:
  what: required `test` CI context runs the suites `tests/scripts/lint-ratchet` and `scripts/lint-ratchet-ruff-live`, plus the vitest `eslint-test-dirs-ratchet` file in `test-webplat`; each prints its verdict line
  cadence: per pull request, merge-queue run and push to main
  alert_target: a red required `test` check blocks the merge and shows on the PR
  configured_in: scripts/test-all.sh (run_suite pair), scripts/lib/test-affected-paths.sh (ALWAYS_ON_SUITES), apps/web-platform/test/repo-wide-suites.ts

error_reporting:
  destination: GitHub Actions job log; no Sentry project (no runtime process, nothing to mirror under cq-silent-fallback-must-mirror-to-sentry)
  fail_loud: exit 1 (drift or vacuity) or exit 2 (infrastructure) with the offending path:row, rule, tool message and remedy text printed to stderr

failure_modes:
  - mode: a new finding enters tracked Python or the scoped JS/TS directories
    detection: step 3 of the check, exit 1 with the live path:row
    alert_route: red required `test` check on the PR
  - mode: the scan sees (almost) nothing, or the tool crashes or prints garbage
    detection: total floor (ruff 55, eslint 105) and the unparsable-output exit 2
    alert_route: red required `test` check on the PR
  - mode: ruff cannot be installed under CI, or a wheel hash mismatches, or the merge base is unresolvable under CI
    detection: exit 2 with the named cause (hash mismatch is never a SKIP)
    alert_route: red required `test` check on the PR

logs:
  where: GitHub Actions job logs of the `test-scripts` and `test-webplat` jobs; local lefthook output
  retention: GitHub Actions log retention (90 days by default)

discoverability_test:
  command: grep -c -e SIM115 scripts/lint-ratchet-ruff.baseline.txt
  expected_output: 21
```

The baseline header comments never name a rule code (a unit test pins this), so the count above is the entry count for `SIM115` and moves down as the drawdown issue is worked.

## Domain Review

**Domains relevant:** Engineering (Product and Legal carried forward from the brainstorm)

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled on six forks on 2026-10-16 (decision-challenges.md rows 1 to 6) and adjudicated the plan-review dissent (rows 7 and 8): separate eslint config, entry-level shrink-only ratchet without a header, hash-pinned wheel installed by the script itself, all tracked Python outside `knowledge-base/`, CI plus lefthook only, baseline everything and fix nothing.

### Product

**Status:** reviewed (carry-forward)
**Assessment:** Brainstorm CPO read this as internal hygiene; no user-facing surface here. No Product/UX gate: no file under `components/`, `app/**/page.tsx` or other UI-surface paths.

### Legal

**Status:** reviewed (carry-forward)
**Assessment:** No regulated-data surface touched; `gdpr-gate` not triggered. Fixtures stay synthetic: the ratchet never prints or stores source text.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add deterministic linters to the repo's own work/review gates with ratcheting baselines" [brief] | Phases 2 to 4 (lefthook entries, run_suite pair, vitest guard) | mapped |
| 2 | "ruff for Python (unclosed files `SIM115`/`py/file-not-closed` equivalent, empty `except`, unused imports and variables) over repo scripts and plugin scripts" [brief] | Phase 2 (`ruff.toml`, ruff adapter, ruff baseline) | mapped |
| 3 | "widen the existing web-platform eslint `no-unused-vars` ratchet to the currently unscanned test and fixture directories" [brief] | Phase 3 (`eslint.test-dirs.config.mjs`, vitest guard, eslint baseline) | mapped |
| 4 | "Each linter needs a baseline that only ratchets down." [brief] | Phase 1 (`lint-ratchet.py` check semantics), Guard 1 | mapped |
| 5 | "keep #10331 open; use "Ref #10331", not "Closes"" [brief] | AC14, PR body | mapped |
| 6 | "The remaining slices are separate PRs and out of scope here: plugin detect-and-run for user repos (PR3b) and the per-PR GitHub Code Quality keep/drop decision (PR4)." [brief] | Non-goals; AC12 (no `plugins/soleur/skills/**/SKILL.md` edit) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ruff.toml` | "ruff for Python" | asked |
| `scripts/lint-ratchet.py` | "a baseline that only ratchets down" | asked |
| `scripts/lint-ratchet-ruff.baseline.txt`, `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` | "Each linter needs a baseline" | asked |
| `apps/web-platform/eslint.test-dirs.config.mjs` | "widen the existing web-platform eslint `no-unused-vars` ratchet" | asked |
| `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` | "the repo's own work/review gates" | asked |
| `lefthook.yml` entries | "the repo's own work/review gates" | asked |
| `scripts/test-all.sh` + `test-affected-paths.sh` registration | "the repo's own work/review gates" | asked |
| `tests/scripts/test_lint_ratchet.py` (unit + pin test) | "a baseline that only ratchets down" | asked |
| `scripts/ruff-requirements.txt` and the install logic inside `lint-ratchet.py` | — | inferred — justification: the brainstorm CTO ruling "pin ruff and eslint versions" needs an install path that CI, which has no ruff, can execute; unpinned `pip install ruff` is the unpinned-resolution defect class the repo already bans for `npx tsc` |
| `apps/web-platform/test/repo-wide-suites.ts` entry | — | inferred — justification: `repo-wide-containment.test.ts` fails when a repo-reading vitest file is missing from the manifest, and a gated project would silently skip the guard on diffs under `plugins/soleur/test` and `test/` |
| ADR-290 | — | inferred — justification: plan Phase 2.10 requires an ADR for a cross-PR design contract, and the brainstorm states PR3b "depends on 3a's ratchet design" |
| Drawdown tracking issue | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracked issue for the 79 baselined findings deferred by the brief's baseline approach |

### Split Assessment

- Subsystems touched: 6 (`scripts`, `tests`, `apps/web-platform`, `knowledge-base`, `.github`, repo root files `lefthook.yml` / `ruff.toml`)
- Planned files: 15 | Estimated changed lines: about 900 (roughly half tests and generated baselines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Over two thresholds, so a split was considered: ruff and eslint could ship separately, but both are adapters over one script, the brief names both under "PR3a", and a second PR would reopen the script's contract and its ADR. The boundary, if the reviewer insists, is script + ruff first, eslint adapter + vitest guard second.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the test file lands red first.

### Phase 0: tests first (RED)

- `tests/scripts/test_lint_ratchet.py` (stdlib `unittest`; loads `scripts/lint-ratchet.py` with `importlib.util.spec_from_file_location` because the filename is hyphenated; git fixtures through `tests/scripts/_git_fixture_env.py`): entry formatting and anchor normalisation, `n` counting, `check` verdicts (new, stale, grew, edit-swap, rename map, floors), adapters over canned tool JSON, base degradation, the Guard 1 to 3 mutation rows, and the **pin test** (below). Run it red before any implementation exists (red means per-case assertion failures against a stub script that exits 3, not an `ImportError` on every case). `setUp` scrubs `CI`, `PIP_*`, `PYTHON*`, `XDG_CACHE_HOME`, `HOME` and `PATH` (a fake-bin directory only) so a developer's ruff, cache or CI flag cannot leak into a case; violating sample sources are built at runtime in a temp directory and never committed as `.py` files (ruff scans `tests/**`, so a committed violation becomes a baseline entry and breaks AC2's count); the test file and the script must themselves be ruff-clean. A loaded-case-count sentinel replaces any reliance on unittest's exit code for zero tests. Tool fixtures are the REAL JSON shapes, captured by running the pinned ruff and eslint once on a synthetic snippet and committing the output (ruff reports absolute `filename` and 1-based `location.row`; eslint `-f json` reports absolute `filePath` and per-message `line`), never hand-written from the author's model of the tool; the adapters relativise against the repo root, the tests rewrite the captured absolute paths onto the fixture root, and a test asserts that each captured row's text hashes to the committed anchor.
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (vitest, live arm only): spawn `python3 scripts/lint-ratchet.py eslint-test-dirs --check` from the repo root, expect exit 0; `expect.assertions(n)`; explicit test timeout of 120 s (a cold eslint run exceeds vitest's 5 s default). Add the file to `REPO_WIDE_SUITES` in `apps/web-platform/test/repo-wide-suites.ts`: it reads the repo root, and `repo-wide-containment.test.ts` fails when such a file is missing from the manifest (and a gated project would skip it on diffs under `test/` and `plugins/soleur/test`).

### Phase 1: the ratchet script (`scripts/lint-ratchet.py`)

Stdlib-only Python that must run on contributors' Python 3 (macOS system Python included): no `tomllib` and no 3.11-only syntax in the script (the unit tests may use `tomllib`; CI's python3 is 3.12). `python3 scripts/lint-ratchet.py <scope> [--check | --update | --list] [--base <ref>]`, scopes `ruff` and `eslint-test-dirs` defined as plain data (`SCOPES = {name: {baseline_path, argv_builder, adapter, floor, scope_tuple}}`); `check(scope_config, ...)` takes that dict and assumes no repo-root layout, so PR3b can move the file and supply its own. `--list` prints the LIVE findings (never the baseline). Exit codes: 0 clean; 1 drift or vacuity; 2 infrastructure (tool missing, unparsable output, hash mismatch, baseline absent, no merge base under `CI`).

- **Entry:** `path|RULE|anchor|n`. `anchor` = first 12 hex of sha256 over the finding's start-line text with whitespace runs collapsed and trimmed (read from the working tree; the source text is never written; a tracked symlink is skipped, and a finding whose row is past the end of the file hashes the empty string). `n` = 1-based ordinal among identical `(path, rule, anchor)` in line order, so two identical lines are two entries. A path containing `|` or a newline exits 2 (the format cannot carry it). The 12-hex value is a fingerprint, not secret-safe; the baseline stores nothing else from the source.
- **Baseline file:** `#` comment lines (scope, the shrink-only statement, the `--list` / `--update` instructions, "after a merge conflict take the base's file and re-run `--update`", the drawdown issue number), then sorted entries. Parsing ignores blank and `#` lines, so ordering and comments never matter. The header never names a rule code (a unit test pins this, because the observability probe counts rule codes with `grep -c`).
- **`--check` order:** (0) the working baseline must exist (exit 2; `--update` creates it); (1) run the tool: never invoke ruff with an empty file list (ruff would lint the current directory), exit 1 for an empty list; exit 2 on a tool crash, an unparsable or non-list report, ruff rc other than 0/1, and any fatal eslint parse error (a file that did not parse hides its findings); a valid empty report `[]` falls through; (2) total floor (ruff 55 files from `ruff check --show-files`, eslint 105 from the report length): exit 1; for ruff an adapter that returns `[]` does not trip the floor (the floor reads the file list), so it is caught at step 3; (3) live minus baseline non-empty is a new finding, baseline minus live non-empty is a stale entry: exit 1; (4) merge-base delta: base = `--base` or `git merge-base origin/main HEAD`, resolved with `git rev-parse --verify --end-of-options "<ref>^{commit}"` to a SHA (a ref starting with `-` is rejected) and used only as that SHA; the rename map comes from `git diff -M30% -z --name-status <sha>` (base against the WORKING TREE plus index, so a staged `git mv` is seen at pre-commit time, not only after commit); apply it to the base baseline (read with `git show <sha>:<path>`); for every `(path, rule)` the head count must be <= the base count, so an edit-swap in the same file and rule is not growth and a copy to a new path is. Baseline absent at base: print "introduced by this diff" and skip. Base unresolvable: warn locally, exit 2 when `CI` is set. On a push to main the base equals HEAD and the delta is empty. All git calls use `-z`, `--` before pathspecs, an argument list and no shell.
- **`--update`** writes the sorted live census and refuses (exit 1, naming the `(path, rule)`) when the result would exceed the base count, so a contributor cannot commit a failing state by reflex.
- **Failure output is actionable.** A new finding prints the LIVE `path:row`, rule, the tool's message and a fixed remedy: ruff rules: fix the code (`SIM115` use a context manager, `S110`/`S112` handle or log the exception, `F401` remove the import, `F841` use the value or prefix `_`); eslint: remove the binding or prefix `_` (arguments and variables only; for a catch parameter use `catch {}`); then: inline `# noqa` / `eslint-disable` waivers are NOT honoured here and `--update` must not be used to admit a NEW finding. A stale entry prints "fixed: run `--update` and commit the baseline". Tool messages go to the console only, never into the baseline.
- **Counting is waiver-proof:** ruff runs with `--ignore-noqa`; eslint with `--no-inline-config`. No `--fix`, `--unsafe-fixes` or `--write` is ever passed (fixtures are test input).
- **Ruff provisioning is inside the script, with no `RUFF_BIN` override and no PATH shortcut:** read the pin from `scripts/ruff-requirements.txt`; the cache root is per user, `${XDG_CACHE_HOME:-$HOME/.cache}/soleur`, created `0700`; before use `lstat` it and require a real directory owned by the current uid with no group or other write bit, otherwise refuse and install into a fresh `tempfile.mkdtemp` directory (never `chmod` a directory the script did not create); the install directory is `ruff-<first 12 hex of the requirements file's sha256>`. Install by running `[sys.executable, "-I", "-m", "pip", "install", "--isolated", "--no-input", "--no-deps", "--disable-pip-version-check", "--index-url", "https://pypi.org/simple", "--only-binary=:all:", "--require-hashes", "--target", <fresh mkdtemp inside the cache root>, "-r", "scripts/ruff-requirements.txt", "--quiet"]` with every `PIP_*` and `PYTHON*` variable removed from the environment, then an atomic `os.rename` into place (if the target already exists, discard the new directory and use the existing one after the same ownership checks). After installation run `<dir>/bin/ruff --version` and require the pin (mismatch: exit 2, never a fallthrough). Print a one-time `lint-ratchet: installing ruff <version> (first run only)` notice. A pip failure whose output contains `THESE PACKAGES DO NOT MATCH THE HASHES` or a requirements error exits 2 everywhere; only a network or index failure outside `CI` prints `SKIP lint-ratchet(ruff): <reason; recover with: python3 scripts/lint-ratchet.py ruff --check>` and exits 0 (under `CI` it exits 2). Hashing uses `hashlib`; no `timeout`, `sha256sum` or GNU-only flag, because lefthook reaches macOS contributors.
- **Adapters:** ruff (`ruff check --config ruff.toml --ignore-noqa --no-cache --no-fix --force-exclude --output-format json -- <git ls-files -z -- '*.py'>`) and eslint (`apps/web-platform/node_modules/.bin/eslint --config apps/web-platform/eslint.test-dirs.config.mjs --no-inline-config --no-error-on-unmatched-pattern -f json` over the scope globs, cwd = repo root; results are filtered to `git ls-files` so untracked scratch files do not differ between local and CI; a missing binary exits 2 with `recover with npm ci --ignore-scripts --prefix apps/web-platform`, mirroring the tsc entry).
- **Residual noted in the script header:** anchors are read from the working tree, so a partially staged commit can mismatch; the full-tree CI run is the backstop.

### Phase 2: ruff wiring

- `ruff.toml`: `target-version = "py311"`, `extend-exclude = ["knowledge-base"]`, `[lint] select = ["SIM115","S110","S112","F401","F841"]`, `[lint.flake8-bandit] check-typed-exception = true`.
- `scripts/ruff-requirements.txt`: leading `#` comment lines giving the bump recipe (take the version and wheel sha256 values from `https://pypi.org/pypi/ruff/<version>/json`, one `--hash=sha256:` line per wheel, then `python3 scripts/lint-ratchet.py ruff --update`), then `ruff==0.16.10` with `--hash=sha256:` lines for all 17 wheels (no trailing comments after a backslash: pip rejects them).
- Derive the baseline with `--update`; commit `scripts/lint-ratchet-ruff.baseline.txt` (59 entries; the flat `scripts/lint-*.baseline.txt` naming follows `scripts/lint-shell-capture-exit.baseline.txt`).

### Phase 3: eslint wiring

- `apps/web-platform/eslint.test-dirs.config.mjs`: `linterOptions.reportUnusedDisableDirectives: "off"`; TS block (`@typescript-eslint/parser`, `@typescript-eslint/no-unused-vars` with `argsIgnorePattern`/`varsIgnorePattern` `^_`), JS block (core `no-unused-vars`, same patterns). No other rule. The scope tuple lives in `lint-ratchet.py`: `test/**`, `plugins/soleur/test/**`, `plugins/soleur/skills/*/test/**`, `scripts/*.test.mjs`. `*.workflow.js` sit outside every glob (top-level `return`).
- Derive the baseline with `--update`; commit `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (20 entries).

### Phase 4: registration

- `scripts/test-all.sh`: `run_suite "tests/scripts/lint-ratchet" python3 -m unittest tests.scripts.test_lint_ratchet` and `run_suite "scripts/lint-ratchet-ruff-live" python3 scripts/lint-ratchet.py ruff --check`, with the "unit proves the rule, live proves the tree" comment the neighbouring pairs carry.
- `scripts/lib/test-affected-paths.sh`: both labels in `ALWAYS_ON_SUITES`, the classification the neighbouring `lint-workflow-step-env-refs` pair and the "ratchet baselines" clause of that file's header use. Its consumer is `scripts/test-all.sh` (`_affected_in_list "$_label" ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"}`, the `always_on` class); an added entry is admitted by the declarations-lib shape check only for a suite added in the same diff, which holds here. Confirm both labels appear in `bash scripts/test-all.sh --print-selection` and run `bash scripts/lint-orphan-test-suites.sh` once the files are tracked (the census, not the glob prose, proves registration). Check the shard-totality and manifest tests before relying on "unknown labels degrade".
- `lefthook.yml`: `ruff-ratchet` (dual globs `*.py` / `**/*.py` plus `ruff.toml`, `scripts/ruff-requirements.txt`, `scripts/lint-ratchet.py`, the ruff baseline; run `python3 scripts/lint-ratchet.py ruff --check`) and `eslint-test-dirs-ratchet` (dual globs over the four scope roots plus the config, the script and its baseline; run `python3 scripts/lint-ratchet.py eslint-test-dirs --check`). A missing `node_modules` exits 2 with the recovery line, as the tsc entry does.
- `apps/web-platform/test/repo-wide-suites.ts`: add `test/eslint-test-dirs-ratchet.test.ts`, then run `repo-wide-containment.test.ts`. No CODEOWNERS rows: the repo's fallback `* @deruelle` already owns every path and no ruleset requires code-owner review, so rows would add nothing.
- No `.github/workflows/ci.yml` edit: the pair runs inside `test-scripts` and the vitest guard inside `test-webplat`, both already `fetch-depth: 0`. If `bash scripts/test-all.sh --print-selection` shows the pair landing on a leg that cannot run `python3 -m pip install --target`, stop and re-plan; do not add `setup-python` without a ruling. pip exempts `--target` from the PEP 668 externally-managed check; the first CI run is still the proof.

### Phase 5: records

- ADR-290 and, in the same PR, the drawdown issue: `gh issue create` titled `chore(quality): draw down the ruff and eslint-test-dir baselines`, body `Ref #10331` plus links to the two baseline files, labels `deferred-scope-out`, `chore`, `domain/engineering`, `priority/p3-low` (all verified to exist with `gh label list`), milestone `Post-MVP / Later` unless `knowledge-base/product/roadmap.md` names a closer phase. Put the issue number in each baseline's comment header.
- `knowledge-base/project/specs/feat-one-shot-10331-pr3a-ruff-eslint-scope/decision-challenges.md` is written by this plan run.

### Phase 6: verification (evidence, not assertion)

Run the six live rows named in AC5 on a scratch commit stacked on the PR head (the baselines exist at that commit, so the merge-base delta is real), and the full unit suite plus `bash scripts/test-all.sh scripts` for the shard containing the new labels.

## Guard Contract

### Guard 1 — shrink-only ratchet (`lint-ratchet.py --check`)

**Property.** For each scope, the baseline always equals the live census, and per `(path, rule)` it never holds more entries than the merge-base baseline.

**Assembly.** Two scopes (`ruff`, `eslint-test-dirs`) dispatch through one `check(scope)` chokepoint in `scripts/lint-ratchet.py`; the adapters only translate tool JSON to `(path, rule, row)`. Inputs the property quantifies over: the live census, the working baseline, the merge-base baseline (rename-mapped). Consumers: the `tests/scripts/lint-ratchet` unit suite, `scripts/lint-ratchet-ruff-live`, the vitest live arm, two lefthook entries; all call the same script and none re-implements the comparison.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `open("x")` without a context manager to a tracked `.py` (new SIM115 finding) | RED (new finding) |
| 2 | Ruff adapter returns `[]` while the baseline has entries (tool silently found nothing) | RED, exit 1 (every baseline entry is stale; the ruff floor reads the file list, so it does not trip); an eslint report of `[]` trips the floor, exit 1 |
| 3 | Duplicate a baselined line inside the same file (second identical finding) | RED (`n=2` absent from baseline) |
| 4 | In a fixture repo: commit a new finding plus `--update` in a path and rule that had none at the base, then `--check --base <base>` | RED (per-`(path, rule)` count grew vs base; the message names the growth, not the step-3 drift) |
| 5 | Edit a baselined violating line in place (`except OSError: pass` to `except (OSError, ValueError): pass`) then `--update` | GREEN (must-pass: stale-plus-new in one `(path, rule)` is not growth) |
| 6 | Insert blank lines above a baselined finding (line number moves) | GREEN (must-pass: identity is the anchor, not the row) |
| 7 | `git mv` a file carrying baselined findings, then `--update`, staged but NOT committed (the pre-commit state) and again committed | GREEN both times (rename map from base-vs-working-tree; a rename below the 30% similarity reads as growth, documented) |
| 8 | Copy a file carrying baselined findings to a new path while keeping the old, `--update`, committed | RED (new entries at the new path) |
| 9 | Delete one baseline entry whose finding is still live | RED (new finding) |
| 10 | Working baseline file missing (step 0) | RED, exit 2 |
| 11 | Remove the rename map from `check` (the harness copies the script into a sandbox and mutates the copy) | RED on row 7 |
| 12 | Two identical baselined lines in one file; one PR deletes `n=2`, another deletes `n=2` too; merge both | RED: a stale `n=1` remains until `--update` (the stale message tells the contributor to take the base file and re-run `--update`) |

**Harness rows.** H1 (suite edit that must go RED): remove the finding from the unit suite's "new finding" fixture; the suite must fail because each case asserts the exit code and the module asserts a minimum executed-case count (a `0 tests` run exits non-zero). H2 (must-pass that is not the canonical): a hand-written baseline with shuffled entry order, blank lines and extra `#` comments passes. H3: rows 4, 7 and 8 run in fixture git repos with `--base`, because the baselines do not exist at `origin/main`.

**Anchor.** The merge-base copy of the baseline (a diff cannot rewrite history) and human PR review of `lint-ratchet.py`, the pin test, the baselines, `ruff.toml`, the requirements file and the eslint config; CODEOWNERS is not an enforced control here. Known residuals (ADR-290): fix-A/add-B inside one `(path, rule)`; a rename below the similarity cutoff reads as growth; a diff that also changes the baseline-path constant presents "absent at base" and skips the delta; the same diff can edit the pin test and the config together (unenforced).

### Guard 2 — anti-vacuity and scope pin

**Property.** A scan that saw (almost) none of the tree can never report green, and the scan's rule set and scope cannot narrow without editing a pinned test.

**Assembly.** Ruff: the file list from `ruff check --show-files` (`ruff.toml` is the single source of truth for exclusion), total floor 55 (measured 64). ESLint: `results.length` of the JSON report, total floor 105 (measured 123). The pin test (in `tests/scripts/test_lint_ratchet.py`) parses `ruff.toml` with `tomllib` and asserts the exact `select` set, `check-typed-exception = true`, `extend-exclude`, the eslint scope tuple, and both floor values; a text grep is the wrong tool and is not used. The floors and scope tuple are code constants in `lint-ratchet.py`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | eslint config `ignores: ["**"]` (scan nothing) | RED (the report is `[]`, so the floor trips, exit 1; if eslint instead refuses with rc 2 the run is exit 2, and the row pins whichever eslint 9.39.4 does when exercised) |
| 2 | Ruff adapter handed an empty file list (own dispatch: "0 checked" must not be green; ruff would lint `.`) | RED, exit 1 before ruff is invoked |
| 3 | `ruff.toml` `extend-exclude = ["knowledge-base", "plugins"]` | RED (floor) |
| 4 | Remove `SIM115` from `ruff.toml` `select`, then `--update` | RED in the pin test (the check alone accepts a legal shrink) |
| 5 | Drop `test/**` from the eslint scope tuple, then `--update` | RED in the pin test |
| 6 | Lower a floor constant to 0 | RED in the pin test |

**Harness rows.** H1: the unit test that asserts the floor fires must itself fail if the floor comparison is inverted (`<` mutated to `>`). H2: must-pass: removing 10 finding-free fixture files from a 123-file report (still above 105) passes.

**Anchor.** Human PR review; editing the pin test together with the config is stopped only by that review (stated in ADR-290 as unenforced). Boundary rows in the unit suite: floors 54 red / 55 green (ruff) and 104 red / 105 green (eslint).

### Guard 3 — pin integrity

**Property.** The ruff that produces the census is the pinned one and nothing else.

**Assembly.** Pin chain: `scripts/ruff-requirements.txt` (version + hashes) to the install step inside `lint-ratchet.py` (`--require-hashes`, `--only-binary=:all:`) to the version assertion at the point `lint-ratchet.py` executes ruff. `lint-ratchet.py` is the only executor of ruff, so no other step resolves it by bare name.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Corrupt one hash in `ruff-requirements.txt` (the cache is keyed on the file hash, so a fresh directory) | RED, exit 2 everywhere (a hash mismatch is never a SKIP) |
| 2 | The installed `bin/ruff` in the cache reports a different version than the pin | RED (exit 2, never a fallthrough to another ruff; there is no `RUFF_BIN` override or PATH shortcut) |
| 3 | Pin line edited to a version with no hash line | RED (pip refuses) |
| 4 | Cache root is a symlink, or owned by another uid, or group/other-writable | RED (refused; the script installs into a fresh `mkdtemp` directory instead of using it) |
| 5 | Environment sets `PIP_INDEX_URL`, `PIP_REQUIRE_VIRTUALENV=1` and `PYTHONPATH` | GREEN (must-pass: the pip run scrubs `PIP_*`/`PYTHON*` and uses `--isolated`) |

**Harness rows.** H1: rows 1 and 3 use a stubbed `pip` that fails with the hash-mismatch text AND a stub that succeeds; the suite must pass with the succeeding stub (must-pass non-canonical input), and a stub failing with a network error must SKIP locally and exit 2 under `CI`. H2: row 2 also runs with a cache binary reporting the correct version and must pass. The pip argv is asserted in full (AC9), which is the only guard on `--require-hashes`.

**Anchor.** The hash list is independently verifiable against PyPI (`curl -s https://pypi.org/pypi/ruff/0.16.10/json`); the plan records the 15-day release age; human review of the requirements file.

## Files to Create

- `ruff.toml`
- `scripts/lint-ratchet.py`
- `scripts/ruff-requirements.txt`
- `scripts/lint-ratchet-ruff.baseline.txt`
- `scripts/lint-ratchet-eslint-test-dirs.baseline.txt`
- `tests/scripts/test_lint_ratchet.py`
- `apps/web-platform/eslint.test-dirs.config.mjs`
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md`
- `knowledge-base/project/specs/feat-one-shot-10331-pr3a-ruff-eslint-scope/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10331-pr3a-ruff-eslint-scope/decision-challenges.md`

## Files to Edit

- `scripts/test-all.sh` (two `run_suite` lines)
- `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`)
- `lefthook.yml` (two commands)
- `apps/web-platform/test/repo-wide-suites.ts` (manifest entry for the vitest guard)

Path-glob verification (`hr-when-a-plan-specifies-relative-paths-e-g`): `git ls-files 'plugins/soleur/skills/*/test/**'` matches 4 JS/TS files (`code-to-prd/test/fixture/**`); `git ls-files 'plugins/soleur/test/*'` matches 114; `git ls-files 'test/*'` matches 4; `git ls-files 'scripts/*.test.mjs'` matches `scripts/md-to-mrkdwn.test.mjs`; `git ls-files '*.py' | grep -v '^knowledge-base/'` returns 64. Re-run each at implementation and paste the counts.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1. `python3 -m unittest tests.scripts.test_lint_ratchet` passes and was observed RED before the script existed, as per-case assertion failures against a stub script that exits 3 (not an ImportError on every case); record both in the PR body.
- [ ] AC2. `python3 scripts/lint-ratchet.py ruff --check` exits 0 on the final tree; the ruff baseline has exactly the 59 entries `python3 scripts/lint-ratchet.py ruff --list` (live findings) prints, and the per-code counts (S110 21, SIM115 21, S112 10, F841 4, F401 3) equal the independent `ruff check --statistics` totals from the pinned binary (the `ruff.toml` census is taken with the final tree, so `scripts/lint-ratchet.py` and `tests/scripts/test_lint_ratchet.py` are ruff-clean and contribute zero entries).
- [ ] AC3. `python3 scripts/lint-ratchet.py eslint-test-dirs --check` exits 0; the baseline has exactly the 20 entries `--list` prints, equal to the eslint JSON report's message count; the vitest guard passes inside `bash scripts/test-all.sh webplat`.
- [ ] AC4. `apps/web-platform/test/eslint-config.test.ts`, `apps/web-platform/eslint.config.mjs` and `apps/web-platform/package.json` are unchanged versus the merge base (`git diff --stat origin/main...HEAD -- <those three>` prints nothing).
- [ ] AC5. Six live rows were run by one scripted harness on a scratch commit stacked on the PR head with `--base <PR head>` (the baselines do not exist at `origin/main`, so the delta cannot run there), and their verdicts are in the PR body: Guard 1 rows 1 (new finding RED), 4 (growth RED), 6 (line move GREEN), 7 (staged rename GREEN, committed rename GREEN), and Guard 2 rows 2 (empty ruff file list RED) and 4 (pin test RED).
- [ ] AC6. After deleting one finding's line on the scratch commit and running `--update`, `--check --base <PR head>` passes and the baseline shrank by exactly one entry; after hand-appending one entry for a new finding it exits 1.
- [ ] AC7. `lefthook run pre-commit` (or the repo's `uv run lefthook` form from `scripts/hooks/pre-commit` when `lefthook` is not on PATH) on a staged `scripts/x.py` and on a staged root-level `y.py` both trigger the ruff entry (dual glob), a staged `test/*.test.ts` triggers the eslint entry, a clean staging passes, a staged new unclosed `open()` is refused with the failure output of AC16, and a staged `git mv` of a file with baselined findings passes.
- [ ] AC8. `bash scripts/test-all.sh --print-selection` lists both `tests/scripts/lint-ratchet` and `scripts/lint-ratchet-ruff-live`; `bash scripts/lint-orphan-test-suites.sh` passes; the ADR passes the markdown/components lint.
- [ ] AC9. `scripts/ruff-requirements.txt` pins `ruff==0.16.10` with a sha256 for every wheel PyPI lists for that release (17; the unit suite snapshots the count, and the plan's `curl -s https://pypi.org/pypi/ruff/0.16.10/json` check is the one-time derivation), and a unit test asserts the FULL constructed pip argv: `-I`, `--isolated`, `--no-input`, `--no-deps`, `--disable-pip-version-check`, `--index-url https://pypi.org/simple`, `--only-binary=:all:`, `--require-hashes`, `--target <fresh dir>` (the only guard on `--require-hashes`; not a grep of the file).
- [ ] AC10. No tool invocation passes a fix mode: a unit test builds every argv list the script executes (check, update and list paths) and asserts none contains `--fix`, `--unsafe-fixes` or `--write` while the ruff one contains `--no-fix`. (Asserted on the constructed argv, because the files legitimately mention the prohibition in comments.)
- [ ] AC11. The baseline files contain no source text: every non-comment line matches `^[^|]+\|[@A-Za-z0-9/_.-]+\|[0-9a-f]{12}\|[0-9]+$` (rule ids such as `@typescript-eslint/no-unused-vars` contain `@` and `/`).
- [ ] AC12. Diff scope: `git diff --name-only origin/main...HEAD -- plugins/soleur/skills plugins/soleur/scripts .claude/hooks apps/web-platform/server apps/web-platform/app apps/web-platform/components` prints nothing (no shipped script, hook, SKILL.md or product code edited).
- [ ] AC13. ADR-290 exists, names the rejected alternatives (count highwater, advisory job, extending `eslint .`, digest/epoch header, anchor-at-base lookup), states that CODEOWNERS is documentation only and human PR review is the control, records the PR3b contract (entry format, exit codes, scope-config shape, `git mv` plan) and the "bumping ruff" recipe, and lists the four residuals (fix-A/add-B swap; rename below the similarity cutoff; baseline-path constant change presents "absent at base"; pin test and config edited together); `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC14. The PR body says `Ref #10331` and does not contain `Closes #10331` or `Fixes #10331`; the drawdown issue exists and the baseline headers cite its number.
- [ ] AC15. CI is green on the PR, including the `test` context with both new suites visible in the `scripts` and `webplat` shard logs, and the first CI run confirms the pinned ruff installs on the runner image.
- [ ] AC16. A new finding's failure output contains the live `path:row`, the rule, the tool's message and the fixed remedy text (including that inline waivers are not honoured and `--update` must not admit a new finding); a stale entry's output says `fixed: run --update and commit the baseline`; asserted by unit tests on the captured output.
- [ ] AC17. `apps/web-platform/test/repo-wide-suites.ts` lists `test/eslint-test-dirs-ratchet.test.ts` and `apps/web-platform/test/repo-wide-containment.test.ts` passes (`cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-wide-containment.test.ts`).
- [ ] AC18. `bash scripts/lint-shell-trace-credential-refusal.test.sh` (it sweeps tracked `*.py`, `*.toml` and `*.txt` outside `knowledge-base/`) still passes with the new files present.

## Test Scenarios

- Given a tracked `.py` with a new unclosed `open()`, when the ruff scope is checked with real-shape tool JSON, then exit 1 naming `path|SIM115|<anchor>|1` (unit).
- Given a baselined finding whose line moves 40 rows down, when checked, then exit 0 (unit).
- Given two identical `except OSError: pass` lines in one file with one baselined, when checked, then exit 1 for `n=2` (unit).
- Given a baselined violating line edited in place, when `--update` is run, then `--check` exits 0 and the baseline entry count for that `(path, rule)` is unchanged (unit).
- Given a baseline that gained an entry in a `(path, rule)` with none at the base, when checked in a fixture git repo with `--base`, then exit 1 (integration, fixture repo).
- Given a `git mv` of a file with baselined findings followed by `--update`, staged and again committed, when checked, then exit 0; given a copy that keeps the original, exit 1 (integration, fixture repo).
- Given pip failing with a network error, when run locally, then it prints the `SKIP` line and exits 0; with `CI=true` it exits 2; given pip failing with the hash-mismatch text, exit 2 in both (unit with a stubbed pip).
- Given identical baselined lines where an earlier identical line is added or removed, when checked, then the `n` ordinals shift and the verdict follows the multiset rule (unit).
- Given ruff exiting with rc 2 or printing non-JSON, when checked, then exit 2; given a zero-finding clean run, exit 0; given `--update` run twice, the file is byte-identical and sorted (unit).
- Given a path containing `|` or a newline, or a tracked symlink, when checked, then exit 2 or skipped respectively; given `--base -x` or an unresolvable ref, exit 2 and nothing reaches git as an option (unit).
- Given a cache root that is a symlink or group-writable, when run, then it is refused and a fresh directory is used (unit).
- Given eslint output with a fatal parse error, when checked, then exit 2 (unit).
- Given the real tree, when the vitest guard runs, then exit 0 (integration, runs under `test-webplat`).
- Regression: the existing `eslint-config.test.ts` still reports 192 findings (unit, unchanged file).
- No e2e scenario: nothing user-facing changes.

## Dependencies & Risks

- **R1: baseline merge conflicts.** Adjacent sorted lines can conflict textually, and two PRs that each delete one of two identical lines both delete `n=2`, which merges cleanly and leaves a stale `n=1` on main. The baseline header and the stale message say: after a conflict or a red stale entry take the base file and re-run `--update`; Guard 1 row 12 pins the duplicate-delete case.
- **R2: ruff install in CI.** First-time `pip --target` needs PyPI reachability; the hash pin turns a poisoned index into a hard failure; the atomic rename removes the concurrent-install race. If the `test-scripts` legs prove unable to run `pip`, the fallback is the pinned-and-checksummed release tarball shape used for actionlint in ci.yml; that is a re-plan, not an in-flight change.
- **R3: Dependabot eslint bump moves findings.** The vitest guard fails; fix the new findings or hold the bump. No escape hatch is built (CTO row 7); one is added when first needed. A bot cannot regenerate the 17 ruff hashes: the "bumping ruff" recipe (derive them from `https://pypi.org/pypi/ruff/<version>/json`) lives in the ADR and as comment lines at the top of `ruff-requirements.txt`.
- **R4: new test files that add unused bindings now fail CI** where they were silent before (20 baselined, any new one reds). This is the intended signal; the failure message names the entry and the `_`-prefix remedy.
- **R5: `ruff.toml` at the root changes bare `ruff check` for everyone.** Intended: the same narrow rule set an editor would apply.
- **R7: the SKIP path is a silent bypass if ignored.** It prints the reason and the recovery command, only occurs outside `CI`, and CI is the backstop; a hash mismatch is never a SKIP.
- **R8: the first PR after merge is the first real run of the delta path** (the baselines do not exist at `origin/main` now); the scratch-commit harness (AC5) is the substitute proof.
- **R6: pre-commit time.** The ruff arm is about 1 s after the first install; the eslint arm about 3 s. Both run only on matching staged globs.

## Non-Goals

- Fixing any baselined finding (drawdown issue).
- Plugin `work`/`review` detect-and-run for user repos (PR3b) and the Code Quality keep/drop decision (PR4); `knowledge-base/operations/expenses.md` is PR4's.
- Migrating the existing 192-count web-platform ratchet to entry identity.
- Rules beyond the five ruff codes and the one eslint rule.
- `pre-push-ratchet-lane.sh` membership (its deps-free scratch worktree has neither ruff nor node_modules).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only filler, or omits the threshold, fails `deepen-plan` Phase 4.6. This one carries `none` with the scope-out reason.
- pip rejects a `\` continuation followed by a trailing `# comment` in a requirements file; the hash lines carry no trailing comments.
- ESLint 9 resolves plugins relative to the config file and the file base path from the cwd: run it from the repo root with `--config apps/web-platform/...`. A directory glob with no lintable files (for example `plugins/soleur/skills/*/test`) errors; use `.../test/**` plus `--no-error-on-unmatched-pattern`.
- `ruff.toml` holds the exclusion and `lint-ratchet.py` the scope tuple; `ruff check --show-files` keeps the ruff floor tied to `ruff.toml` alone.
- Do not copy tool JSON `message`/`source` text into the baseline; messages can contain code.
- Hyphenated module name: tests load `scripts/lint-ratchet.py` through `importlib.util.spec_from_file_location`; a plain `import` is a parse error.
- Unit tests use `tomllib` (Python 3.11+, CI's python3 is 3.12); the script itself stays stdlib-only and 3.9-safe for macOS contributors.
- `ruff check` with no file arguments lints the current directory: the adapter must refuse an empty file list before invoking it.
- vitest's default 5 s test timeout is below a cold eslint run; the guard sets its own.
