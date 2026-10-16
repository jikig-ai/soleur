---
title: "chore(quality): ruff and widened eslint no-unused-vars with shrink-only baselines (PR3a of #10331)"
type: chore
date: 2026-10-16
slug: ruff-eslint-ratcheting-linters-pr3a
branch: feat-one-shot-10331-pr3a-ruff-eslint-scope
issue: 10331
lane: cross-domain
brand_survival_threshold: none
---

# chore(quality): ruff and widened eslint no-unused-vars with shrink-only baselines (PR3a of #10331)

Tracker #10331 stays open: the PR body says `Ref #10331`, never `Closes`. Draft PR #10426 already exists for this branch.

## Overview

Third slice of #10331. PR1 (#10342, comparison triage) and PR2 (#10375, shipped-script handler notes) merged on 2026-10-15. This slice adds two deterministic linters to the repository's own gates, each with a baseline that can only shrink:

1. **ruff** over every tracked Python file outside `knowledge-base/`, selecting unclosed files (`SIM115`), empty handlers (`S110`, `S112`, typed handlers included), unused imports (`F401`) and unused variables (`F841`). Measured: 59 findings in 64 files.
2. **A second eslint scan** (`@typescript-eslint/no-unused-vars` for TS, core `no-unused-vars` for JS) over the test and fixture directories the web-platform run never reaches. Measured: 20 findings in 123 files.

Both flow through one script, `scripts/lint-ratchet.py`, with a small adapter per tool (an `if` on the scope name, not a plugin framework; PR3b can extend it). The "work/review gates" of this repository are, for this slice, the lefthook pre-commit hook (work) and the required `test` CI context (review). The plugin `work`/`review` SKILL.md files are untouched (PR3b). No existing finding is fixed here; a drawdown issue tracks them.

**Plan-review revision (2026-10-16).** Three reviewers (DHH, Kieran, code-simplicity) converged on cutting the `(digest, epoch)` header, the anchor-at-merge-base lookup, the two shell wrappers, the `--findings-json` seam, per-root floors and glob-liveness checks; the CTO agent accepted the cuts (decision-challenges.md rows 7 and 8) and superseded the header clauses of his first row-2 ruling. The shrink-only rule is now: live equals baseline exactly, and per `(path, rule)` the baseline count may not exceed the merge-base count.

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

**Premise Validation.** #10331 is OPEN. PRs #10342 and #10375 are merged (git log on main). The "no Python linter" claim holds: `git grep -w ruff|flake8|pyflakes` outside `knowledge-base/` hits one docs page only; no `ruff.toml`, `pyproject.toml` or `setup.cfg` exists. The "eslint scans only apps/web-platform" claim holds. The ADR corpus was grepped for "ratchet" and "linter" (ADR-076, 105, 106, 129, 133, 139, 151, 160 hit): none decides the mechanism proposed here, none lists it as rejected. Latest ADR ordinal on disk is ADR-288, so ADR-289 is the provisional next.

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
- `2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`: why the digest header was cut; the anchor is the merge-base copy plus CODEOWNERS review of the tooling and the pin test.
- `2026-09-27-a-blocking-gate-diffing-against-moving-main-...md`: diff against the merge base, never moving `origin/main`.
- `2026-03-21-lefthook-gobwas-glob-double-star.md`: dual globs.
- `2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`: neither linter may run with a fix mode; fixtures are test input.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-...md`: unregistered suites are invisible to `--affected`; register both labels in `ALWAYS_ON_SUITES`.
- `2026-10-15-lint-wiring-issue-premises-were-half-shipped-and-misscoped.md`: measure scan scope before framing; its session error 8 names the S110 typed-handler blind spot and the non-blocking-job contradiction this plan avoids.

**Repository facts (file anchors).**

- `apps/web-platform/eslint.config.mjs` and `apps/web-platform/test/eslint-config.test.ts` (`BASELINE_FINDINGS = 192`, `MIN_FILES_SCANNED = 1900`): untouched.
- `scripts/lint-trap-tempfile-ownership.py` (`check_highwater`, `merge_base`): the merge-base comparison precedent; `scripts/lint-shell-capture-exit.baseline.txt`: the "keyed by path + class + normalised text, may only SHRINK" precedent.
- `scripts/test-all.sh` (run_suite pair at the `lint-workflow-step-env-refs` registration), `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`): suite registration. `scripts/*.test.sh` is not in `SUITE_GLOBS`, so explicit lines are the only registration. Python unit suites register as `python3 -m unittest tests.scripts.test_x` (precedent: `tests/scripts/lint-rule-ids`; `tests/` and `tests/scripts/` are namespace packages with no `__init__.py`).
- CI: `test-webplat` and `test-scripts` both check out with `fetch-depth: 0` (ci.yml near lines 1229 and 1470), so the merge base resolves. `test-scripts` has bash, python3 and stock node; no `setup-python`, no `apps/web-platform/node_modules`. `test-webplat` has the node_modules and runs `bash scripts/test-all.sh webplat` (vitest, which collects `test/**/*.test.ts`).
- Provisioning experiment: `python3 -m pip install --target <dir> --only-binary=:all: --require-hashes -r <requirements>` with the 17 PyPI wheel hashes of `ruff==0.16.10` installs `<dir>/bin/ruff` and reports `ruff 0.16.10`. Pin choice: 0.16.10 was released 2026-10-01 (15 days old); 0.17.1 is one day old. Both give identical counts.
- CLI verification (gate #2566): flags used and exercised locally on 2026-10-16 (ruff 0.16.10 / 0.17.1 via `uvx`, eslint 9.39.4): ruff `--config`, `--ignore-noqa`, `--output-format json`, `--no-cache`, `--no-fix`, `--force-exclude`, `--show-files`, `--statistics`; eslint `--config`, `--no-inline-config`, `--no-error-on-unmatched-pattern`, `-f json`.

## Open Code-Review Overlap

Queried open `code-review` issues for every planned file path. Matches, each acknowledged (different concern, remains open):

- `scripts/test-all.sh`: #8659 (EXIT-trap replacement in 33 suites), #7942 (mutation batteries run in no gate). Acknowledge: unrelated to this registration.
- `scripts/lib/test-affected-paths.sh`: #8800 (census sandbox inode sharing). Acknowledge.
- `.github/CODEOWNERS`: #3321 (learnings subtree coverage). Acknowledge: this PR adds rows only for its own files.
- `tests/scripts`: #10112 (#9786 residuals, unrelated infra). Acknowledge.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-289 via `soleur:architecture`: "Lint findings are admitted to a baseline by identity (`path|rule|anchor|n`), the baseline always equals the live census, and per `(path, rule)` its count may not exceed the merge-base count". It records the alternatives rejected in the Cut List (count highwater, advisory job, extending `eslint .`, digest/epoch header, anchor-at-base lookup), the CODEOWNERS control, and the accepted residuals: a fix-A/add-B swap inside one `(path, rule)` is invisible; a rename below `git diff -M` similarity reads as growth (fix the findings or add an escape hatch when first needed); config weakening followed by `--update` is a legal shrink, stopped only by the pin test plus CODEOWNERS review; a diff that edits the baseline-path constant presents "absent at base". The ordinal is provisional; `soleur:ship` re-verifies against `origin/main`. When renumbering, sweep `grep -rn 'ADR-289' knowledge-base/project/{plans,specs}/feat-one-shot-10331-pr3a-ruff-eslint-scope/`. Probe ordinal claims across every pushed branch (`git ls-tree -r --name-only <ref> -- knowledge-base/engineering/architecture/decisions/ | grep ADR-289` for each `origin/*`), not only `origin/main`, and again right before merge.

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
| `scripts/lint-ratchet-baselines/*.baseline` | "Each linter needs a baseline" | asked |
| `apps/web-platform/eslint.test-dirs.config.mjs` | "widen the existing web-platform eslint `no-unused-vars` ratchet" | asked |
| `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` | "the repo's own work/review gates" | asked |
| `lefthook.yml` entries | "the repo's own work/review gates" | asked |
| `scripts/test-all.sh` + `test-affected-paths.sh` registration | "the repo's own work/review gates" | asked |
| `tests/scripts/test_lint_ratchet.py` (unit + pin test) | "a baseline that only ratchets down" | asked |
| `scripts/ruff-requirements.txt` and the install logic inside `lint-ratchet.py` | — | inferred — justification: the brainstorm CTO ruling "pin ruff and eslint versions" needs an install path that CI, which has no ruff, can execute; unpinned `pip install ruff` is the unpinned-resolution defect class the repo already bans for `npx tsc` |
| `.github/CODEOWNERS` rows | — | inferred — justification: the pin test and the baselines are edited by the same diff that could weaken them; review ownership is the only control outside the commit (Guard 1 Anchor) |
| ADR-289 | — | inferred — justification: plan Phase 2.10 requires an ADR for a cross-PR design contract, and the brainstorm states PR3b "depends on 3a's ratchet design" |
| Drawdown tracking issue | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracked issue for the 79 baselined findings deferred by the brief's baseline approach |

### Split Assessment

- Subsystems touched: 6 (`scripts`, `tests`, `apps/web-platform`, `knowledge-base`, `.github`, repo root files `lefthook.yml` / `ruff.toml`)
- Planned files: 15 | Estimated changed lines: about 900 (roughly half tests and generated baselines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Over two thresholds, so a split was considered: ruff and eslint could ship separately, but both are adapters over one script, the brief names both under "PR3a", and a second PR would reopen the script's contract and its ADR. The boundary, if the reviewer insists, is script + ruff first, eslint adapter + vitest guard second.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the test file lands red first.

### Phase 0: tests first (RED)

- `tests/scripts/test_lint_ratchet.py` (stdlib `unittest`; loads `scripts/lint-ratchet.py` with `importlib.util.spec_from_file_location` because the filename is hyphenated; git fixtures through `tests/scripts/_git_fixture_env.py`): entry formatting and anchor normalisation, `n` counting, `check` verdicts (new, stale, grew, edit-swap, rename map, floors), adapters over canned tool JSON, base degradation, the Guard 1 to 3 mutation rows, and the **pin test** (below). Run it red before any implementation exists. Tool fixtures are the REAL JSON shapes, captured by running the pinned ruff and eslint once on a synthetic snippet and committing the output (ruff reports absolute `filename` and 1-based `location.row`; eslint `-f json` reports absolute `filePath` and per-message `line`), never hand-written from the author's model of the tool; the adapters relativise against the repo root.
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (vitest, live arm only): spawn `python3 scripts/lint-ratchet.py eslint-test-dirs --check` from the repo root, expect exit 0; `expect.assertions(n)`.

### Phase 1: the ratchet script (`scripts/lint-ratchet.py`)

Stdlib-only Python. `python3 scripts/lint-ratchet.py <scope> [--check | --update | --list] [--base <ref>]`, scopes `ruff` and `eslint-test-dirs` in one table (baseline path, runner argv, adapter, floor, scope tuple). `--list` prints the LIVE findings (never the baseline), so counts can be compared with the tool's own totals. Exit codes: 0 clean; 1 drift or vacuity; 2 infrastructure (tool missing, unparsable output, no merge base under `CI`).

- **Entry:** `path|RULE|anchor|n`. `anchor` = first 12 hex of sha256 over the finding's start-line text with whitespace runs collapsed and trimmed (read from the working tree; the source text is never written). `n` = 1-based ordinal among identical `(path, rule, anchor)` in line order, so two identical lines are two entries.
- **Baseline file:** `#` comment lines (scope, shrink-only statement, drawdown issue number), then sorted entries. Parsing ignores blank and `#` lines, so ordering and comments never matter.
- **`--check` order:** (1) run the tool; exit 2 on a crash or unparsable output, and on any fatal eslint parse error (a file that did not parse hides its findings); an empty `[]` is valid output and falls through to step 3; (2) total floor (ruff 55 files from `ruff check --show-files`, eslint 105 from the report length): exit 1; (3) live minus baseline non-empty is a new finding, baseline minus live non-empty is a stale entry (delete it or run `--update`): exit 1; (4) merge-base delta: base = `--base` or `git merge-base origin/main HEAD`; apply `git diff -M --name-status <base>...HEAD` renames to the base baseline; for every `(path, rule)` the head count must be <= the base count, so an edit-swap in the same file and rule is not growth and a copy to a new path is. Baseline absent at base: print "introduced by this diff" and skip. Base unresolvable: warn locally, exit 2 when `CI` is set. On a push to main the base equals HEAD and the delta is empty.
- **Counting is waiver-proof:** ruff runs with `--ignore-noqa`; eslint with `--no-inline-config`. No `--fix`, `--unsafe-fixes` or `--write` is ever passed (fixtures are test input).
- **Ruff provisioning is inside the script:** read the pin from `scripts/ruff-requirements.txt`; use `$RUFF_BIN` or a `ruff` on PATH only if `--version` equals the pin; otherwise install into `${SOLEUR_SCRATCH_ROOT:-${TMPDIR:-/tmp}}/soleur-ruff-<first 12 hex of the requirements file's sha256>` by `python3 -m pip install --quiet --target <tmpdir> --only-binary=:all: --require-hashes -r scripts/ruff-requirements.txt` into a temp directory and an atomic `os.rename` into place (lefthook and `test-all.sh` can race). Hashing uses `hashlib`; no `timeout`, `sha256sum` or GNU-only flag, because lefthook reaches macOS contributors. If the install is impossible: exit 2 when `CI` is set, otherwise print `SKIP lint-ratchet(ruff): <reason>` and exit 0. The version is asserted where the binary executes, not only where it is installed.
- **Adapters:** ruff (`ruff check --config ruff.toml --ignore-noqa --no-cache --no-fix --force-exclude --output-format json <git ls-files -z '*.py'>`) and eslint (`apps/web-platform/node_modules/.bin/eslint --config apps/web-platform/eslint.test-dirs.config.mjs --no-inline-config --no-error-on-unmatched-pattern -f json` over the scope globs, cwd = repo root; a missing binary exits 2 with `recover with npm ci --ignore-scripts --prefix apps/web-platform`, mirroring the tsc entry).
- **Residual noted in the script header:** anchors are read from the working tree, so a partially staged commit can mismatch; the full-tree CI run is the backstop.

### Phase 2: ruff wiring

- `ruff.toml`: `target-version = "py311"`, `extend-exclude = ["knowledge-base"]`, `[lint] select = ["SIM115","S110","S112","F401","F841"]`, `[lint.flake8-bandit] check-typed-exception = true`.
- `scripts/ruff-requirements.txt`: `ruff==0.16.10` with `--hash=sha256:` lines for all 17 wheels (no trailing comments after the backslash: pip rejects them).
- Derive the baseline with `--update`; commit `scripts/lint-ratchet-baselines/ruff.baseline` (59 entries).

### Phase 3: eslint wiring

- `apps/web-platform/eslint.test-dirs.config.mjs`: `linterOptions.reportUnusedDisableDirectives: "off"`; TS block (`@typescript-eslint/parser`, `@typescript-eslint/no-unused-vars` with `argsIgnorePattern`/`varsIgnorePattern` `^_`), JS block (core `no-unused-vars`, same patterns). No other rule. The scope tuple lives in `lint-ratchet.py`: `test/**`, `plugins/soleur/test/**`, `plugins/soleur/skills/*/test/**`, `scripts/*.test.mjs`. `*.workflow.js` sit outside every glob (top-level `return`).
- Derive the baseline with `--update`; commit `scripts/lint-ratchet-baselines/eslint-test-dirs.baseline` (20 entries).

### Phase 4: registration

- `scripts/test-all.sh`: `run_suite "tests/scripts/lint-ratchet" python3 -m unittest tests.scripts.test_lint_ratchet` and `run_suite "scripts/lint-ratchet-ruff-live" python3 scripts/lint-ratchet.py ruff --check`, with the "unit proves the rule, live proves the tree" comment the neighbouring pairs carry.
- `scripts/lib/test-affected-paths.sh`: both labels in `ALWAYS_ON_SUITES`, the classification the neighbouring `lint-workflow-step-env-refs` pair and the "ratchet baselines" clause of that file's header use. Its consumer is `scripts/test-all.sh` (`_affected_in_list "$_label" ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"}`, the `always_on` class); an added entry is admitted by the declarations-lib shape check only for a suite added in the same diff, which holds here. Confirm both labels appear in `bash scripts/test-all.sh --print-selection` and run `bash scripts/lint-orphan-test-suites.sh` once the files are tracked (the census, not the glob prose, proves registration). Check the shard-totality and manifest tests before relying on "unknown labels degrade".
- `lefthook.yml`: `ruff-ratchet` (dual globs `*.py` / `**/*.py` plus `ruff.toml`, `scripts/ruff-requirements.txt`, `scripts/lint-ratchet.py`, the ruff baseline; run `python3 scripts/lint-ratchet.py ruff --check`) and `eslint-test-dirs-ratchet` (dual globs over the four scope roots plus the config, the script and its baseline; run `python3 scripts/lint-ratchet.py eslint-test-dirs --check`).
- `.github/CODEOWNERS`: two rows, `@deruelle` like the neighbours: the tooling family (`/scripts/lint-ratchet.py`, `/tests/scripts/test_lint_ratchet.py`, `/ruff.toml`, `/scripts/ruff-requirements.txt`, `/apps/web-platform/eslint.test-dirs.config.mjs`) and the two baseline files. CODEOWNERS rows are per-file in this repo; "two rows" means two comment-headed groups.
- No `.github/workflows/ci.yml` edit: the pair runs inside `test-scripts` and the vitest guard inside `test-webplat`, both already `fetch-depth: 0`. If `bash scripts/test-all.sh --print-selection` shows the pair landing on a leg that cannot run `python3 -m pip install --target`, stop and re-plan; do not add `setup-python` without a ruling. Verify on the first CI run that `pip install --target` is not blocked by the runner image's PEP 668 marker.

### Phase 5: records

- ADR-289 and, in the same PR, the drawdown issue: `gh issue create` titled `chore(quality): draw down the ruff and eslint-test-dir baselines`, body `Ref #10331` plus links to the two baseline files, labels `deferred-scope-out`, `chore`, `domain/engineering`, `priority/p3-low` (all verified to exist with `gh label list`), milestone `Post-MVP / Later` unless `knowledge-base/product/roadmap.md` names a closer phase. Put the issue number in each baseline's comment header.
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
| 2 | Adapter returns `[]` while the baseline has entries (tool silently found nothing) | RED, exit 1 (every baseline entry is stale); the floor also trips |
| 3 | Duplicate a baselined line inside the same file (second identical finding) | RED (`n=2` absent from baseline) |
| 4 | Append one baseline entry (and the matching live finding) in a path and rule that had none at the base | RED (per-`(path, rule)` count grew vs base) |
| 5 | Edit a baselined violating line in place (`except OSError: pass` to `except (OSError, ValueError): pass`) then `--update` | GREEN (must-pass: stale-plus-new in one `(path, rule)` is not growth) |
| 6 | Insert blank lines above a baselined finding (line number moves) | GREEN (must-pass: identity is the anchor, not the row) |
| 7 | `git mv` a file carrying baselined findings, then `--update` | GREEN (rename map; a rename under `git diff -M` similarity reads as growth, documented) |
| 8 | Copy a file carrying baselined findings to a new path while keeping the old | RED (new entries at the new path) |
| 9 | Delete one baseline entry whose finding is still live | RED (new finding) |
| 10 | Baseline file missing | RED (exit 2) |
| 11 | Remove the `git diff -M` rename map from `check` | RED on row 7 (the unit test pins it) |

**Harness rows.** H1 (suite edit that must go RED): remove the finding from the unit suite's "new finding" fixture; the suite must fail because each case asserts the exit code and the module asserts a minimum executed-case count (a `0 tests` run exits non-zero). H2 (must-pass that is not the canonical): a hand-written baseline with shuffled entry order, blank lines and extra `#` comments passes. H3: rows 4, 7 and 8 run in fixture git repos with `--base`, because the baselines do not exist at `origin/main`.

**Anchor.** The merge-base copy of the baseline (a diff cannot rewrite history) and CODEOWNERS review of `lint-ratchet.py`, the pin test, the baselines, `ruff.toml`, the requirements file and the eslint config. Known residuals (ADR-289): fix-A/add-B inside one `(path, rule)`; a diff that also changes the baseline-path constant presents "absent at base"; the same diff can edit the pin test and the config together.

### Guard 2 — anti-vacuity and scope pin

**Property.** A scan that saw (almost) none of the tree can never report green, and the scan's rule set and scope cannot narrow without editing a pinned test.

**Assembly.** Ruff: the file list from `ruff check --show-files` (`ruff.toml` is the single source of truth for exclusion), total floor 55 (measured 64). ESLint: `results.length` of the JSON report, total floor 105 (measured 123). The pin test (in `tests/scripts/test_lint_ratchet.py`) parses `ruff.toml` with `tomllib` and asserts the exact `select` set, `check-typed-exception = true`, `extend-exclude`, the eslint scope tuple, and both floor values; a text grep is the wrong tool and is not used. The floors and scope tuple are code constants in `lint-ratchet.py`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | eslint config `ignores: ["**"]` (scan nothing) | RED (floor, or exit 2 if eslint refuses) |
| 2 | Ruff run with an empty file list (own dispatch: "0 checked" must not be green) | RED (floor) |
| 3 | `ruff.toml` `extend-exclude = ["knowledge-base", "plugins"]` | RED (floor) |
| 4 | Remove `SIM115` from `ruff.toml` `select`, then `--update` | RED in the pin test (the check alone accepts a legal shrink) |
| 5 | Drop `test/**` from the eslint scope tuple, then `--update` | RED in the pin test |
| 6 | Lower a floor constant to 0 | RED in the pin test |

**Harness rows.** H1: the unit test that asserts the floor fires must itself fail if the floor comparison is inverted (`<` mutated to `>`). H2: must-pass: removing 10 finding-free fixture files from a 123-file report (still above 105) passes.

**Anchor.** CODEOWNERS on the tooling family; editing the pin test together with the config is stopped only by that review (stated in ADR-289, not claimed as independent of review).

### Guard 3 — pin integrity

**Property.** The ruff that produces the census is the pinned one and nothing else.

**Assembly.** Pin chain: `scripts/ruff-requirements.txt` (version + hashes) to the install step inside `lint-ratchet.py` (`--require-hashes`, `--only-binary=:all:`) to the version assertion at the point `lint-ratchet.py` executes ruff. `lint-ratchet.py` is the only executor of ruff, so no other step resolves it by bare name.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Corrupt one hash in `ruff-requirements.txt` and clear the scratch install | RED (pip refuses; exit 2 under `CI`) |
| 2 | `RUFF_BIN` points at a different ruff version | RED (exit 2, version mismatch) |
| 3 | Pin line edited to a version with no hash line | RED (pip refuses) |

**Harness rows.** H1: rows 1 and 3 use a stubbed `pip` that fails on a hash mismatch AND a stub that succeeds; the suite must pass with the succeeding stub (must-pass non-canonical input). H2: row 2 also runs with the correct version through `RUFF_BIN` and must pass.

**Anchor.** The hash list is independently verifiable against PyPI (`curl -s https://pypi.org/pypi/ruff/0.16.10/json`); the plan records the 15-day release age; CODEOWNERS on the requirements file.

## Files to Create

- `ruff.toml`
- `scripts/lint-ratchet.py`
- `scripts/ruff-requirements.txt`
- `scripts/lint-ratchet-baselines/ruff.baseline`
- `scripts/lint-ratchet-baselines/eslint-test-dirs.baseline`
- `tests/scripts/test_lint_ratchet.py`
- `apps/web-platform/eslint.test-dirs.config.mjs`
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-289-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md`
- `knowledge-base/project/specs/feat-one-shot-10331-pr3a-ruff-eslint-scope/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10331-pr3a-ruff-eslint-scope/decision-challenges.md`

## Files to Edit

- `scripts/test-all.sh` (two `run_suite` lines)
- `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`)
- `lefthook.yml` (two commands)
- `.github/CODEOWNERS` (two row groups for the new guard files)

Path-glob verification (`hr-when-a-plan-specifies-relative-paths-e-g`): `git ls-files 'plugins/soleur/skills/*/test/**'` matches 4 JS/TS files (`code-to-prd/test/fixture/**`); `git ls-files 'plugins/soleur/test/*'` matches 114; `git ls-files 'test/*'` matches 4; `git ls-files 'scripts/*.test.mjs'` matches `scripts/md-to-mrkdwn.test.mjs`; `git ls-files '*.py' | grep -v '^knowledge-base/'` returns 64. Re-run each at implementation and paste the counts.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1. `python3 -m unittest tests.scripts.test_lint_ratchet` passes and was observed RED before `scripts/lint-ratchet.py` existed (record both in the PR body).
- [ ] AC2. `python3 scripts/lint-ratchet.py ruff --check` exits 0 on the final tree; the ruff baseline has exactly the 59 entries `python3 scripts/lint-ratchet.py ruff --list` (live findings) prints, and the per-code counts (S110 21, SIM115 21, S112 10, F841 4, F401 3) equal the independent `ruff check --statistics` totals from the pinned binary.
- [ ] AC3. `python3 scripts/lint-ratchet.py eslint-test-dirs --check` exits 0; the baseline has exactly the 20 entries `--list` prints, equal to the eslint JSON report's message count; the vitest guard passes inside `bash scripts/test-all.sh webplat`.
- [ ] AC4. `apps/web-platform/test/eslint-config.test.ts`, `apps/web-platform/eslint.config.mjs` and `apps/web-platform/package.json` are unchanged versus the merge base (`git diff --stat origin/main...HEAD -- <those three>` prints nothing).
- [ ] AC5. Six live rows were run on a scratch commit stacked on the PR head with `--base <PR head>` (the baselines do not exist at `origin/main`, so the delta cannot run there), and their verdicts are in the PR body: Guard 1 rows 1 (new finding RED), 4 (growth RED), 6 (line move GREEN), 7 (rename GREEN), and Guard 2 rows 2 (empty scan RED) and 4 (pin test RED).
- [ ] AC6. After deleting one finding's line on the scratch commit and running `--update`, `--check --base <PR head>` passes and the baseline shrank by exactly one entry; after hand-appending one entry for a new finding it exits 1.
- [ ] AC7. `lefthook run pre-commit` on a staged `scripts/x.py` and on a staged root-level `y.py` both trigger the ruff entry (dual glob), and a staged `test/*.test.ts` triggers the eslint entry (if `lefthook` is not on PATH, use the repo's `uv run lefthook` form from `scripts/hooks/pre-commit`).
- [ ] AC8. `bash scripts/test-all.sh --print-selection` lists both `tests/scripts/lint-ratchet` and `scripts/lint-ratchet-ruff-live`; `bash scripts/lint-orphan-test-suites.sh` passes; the ADR passes the markdown/components lint.
- [ ] AC9. `scripts/ruff-requirements.txt` pins `ruff==0.16.10` with a sha256 for every wheel PyPI lists for that release (17), verified by `curl -s https://pypi.org/pypi/ruff/0.16.10/json`, and the install command line in `lint-ratchet.py` carries `--require-hashes` and `--only-binary=:all:` (asserted by the unit test on the constructed pip argv, not by grepping the file).
- [ ] AC10. No tool invocation passes a fix mode: a unit test builds both argv lists the script executes and asserts none contains `--fix`, `--unsafe-fixes` or `--write` while the ruff one contains `--no-fix`. (Asserted on the constructed argv, because the files legitimately mention the prohibition in comments.)
- [ ] AC11. The baseline files contain no source text: every non-comment line matches `^[^|]+\|[@A-Za-z0-9/_.-]+\|[0-9a-f]{12}\|[0-9]+$` (rule ids such as `@typescript-eslint/no-unused-vars` contain `@` and `/`).
- [ ] AC12. Diff scope: `git diff --name-only origin/main...HEAD -- plugins/soleur/skills plugins/soleur/scripts .claude/hooks apps/web-platform/server apps/web-platform/app apps/web-platform/components` prints nothing (no shipped script, hook, SKILL.md or product code edited).
- [ ] AC13. ADR-289 exists, names the rejected alternatives (count highwater, advisory job, extending `eslint .`, digest/epoch header, anchor-at-base lookup), the CODEOWNERS control and the four residuals; `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC14. The PR body says `Ref #10331` and does not contain `Closes #10331` or `Fixes #10331`; the drawdown issue exists and the baseline headers cite its number.
- [ ] AC15. CI is green on the PR, including the `test` context with both new suites visible in the `scripts` and `webplat` shard logs, and the first CI run confirms `pip install --target` works on the runner image.

## Test Scenarios

- Given a tracked `.py` with a new unclosed `open()`, when the ruff scope is checked with real-shape tool JSON, then exit 1 naming `path|SIM115|<anchor>|1` (unit).
- Given a baselined finding whose line moves 40 rows down, when checked, then exit 0 (unit).
- Given two identical `except OSError: pass` lines in one file with one baselined, when checked, then exit 1 for `n=2` (unit).
- Given a baselined violating line edited in place, when `--update` is run, then `--check` exits 0 and the baseline entry count for that `(path, rule)` is unchanged (unit).
- Given a baseline that gained an entry in a `(path, rule)` with none at the base, when checked in a fixture git repo with `--base`, then exit 1 (integration, fixture repo).
- Given a `git mv` of a file with baselined findings followed by `--update`, when checked, then exit 0; given a copy that keeps the original, exit 1 (integration, fixture repo).
- Given ruff absent and pip unable to install, when run locally, then it prints the `SKIP` line and exits 0; with `CI=true` it exits 2 (unit with a stubbed pip).
- Given eslint output with a fatal parse error, when checked, then exit 2 (unit).
- Given the real tree, when the vitest guard runs, then exit 0 (integration, runs under `test-webplat`).
- Given a corrupt hash, when the install runs, then pip refuses and the script exits 2 under `CI` (unit with a stubbed pip).
- Regression: the existing `eslint-config.test.ts` still reports 192 findings (unit, unchanged file).
- No e2e scenario: nothing user-facing changes.

## Dependencies & Risks

- **R1: baseline merge conflicts.** Line-per-entry sorted files merge cleanly; two PRs deleting different entries do not conflict. Two PRs fixing the same finding conflict harmlessly.
- **R2: ruff install in CI.** First-time `pip --target` needs PyPI reachability; the hash pin turns a poisoned index into a hard failure; the atomic rename removes the concurrent-install race. If the `test-scripts` legs prove unable to run `pip`, the fallback is the pinned-and-checksummed release tarball shape used for actionlint in ci.yml; that is a re-plan, not an in-flight change.
- **R3: Dependabot eslint bump moves findings.** The vitest guard fails; fix the new findings or hold the bump. No escape hatch is built (CTO row 7); one is added when first needed.
- **R4: new test files that add unused bindings now fail CI** where they were silent before (20 baselined, any new one reds). This is the intended signal; the failure message names the entry and the `_`-prefix remedy.
- **R5: `ruff.toml` at the root changes bare `ruff check` for everyone.** Intended: the same narrow rule set an editor would apply.
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
