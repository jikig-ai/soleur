---
title: "feat(quality): plugin detect-and-run lint ratchet for user repositories (slice 2 of #10331)"
date: 2026-10-18
slug: plugin-detect-and-run-lint-ratchet
branch: feat-one-shot-10331-plugin-detect-and-run
issue: 10331
refs: [10331, 10433]
closes: [10507]
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(quality): plugin detect-and-run lint ratchet for user repositories (slice 2 of #10331)

Ref #10331 (keep OPEN; the PR body says `Ref #10331` and uses no closing keyword for it). This PR may say `Closes #10507` once both carry-ins are delivered. Drawdown stays with #10433.

## Overview

Slice 2 (PR3b) of the code-quality arc. Slice 1 (silent and catch-all handler restructure, ruff baseline 62 to 44) is merged and is not redone. The repository's own shrink-only ratchets (`scripts/lint-ratchet.py`, ADR-290) give Soleur a deterministic lint signal. This slice ships the same engine to plugin users: the `work` and `review` skills detect whether the user's repository has a Python (ruff) configuration, run the hash-pinned ruff against it, and ratchet the findings against a baseline that the user opted into and committed. User mode is Python-only in this slice (JS/TS user support is deferred, see Deferrals). The two carry-in residuals of #10507 (ruff-cache recovery hint, eslint per-extension test not run in CI) ride along because they live in the file this slice moves.

All technical forks were ruled by the CTO agent on 2026-10-18, in two passes (the second after the plan-review seats dissented); every ruling is recorded in `knowledge-base/project/specs/feat-one-shot-10331-plugin-detect-and-run/decision-challenges.md`. No technical question goes to the operator.

## Research Reconciliation: Spec vs. Codebase

| Claim (brief, brainstorm, ADR) | Reality (verified 2026-10-18) | Plan response |
|---|---|---|
| Brainstorm FR4: run the user's linter "on changed files only, report the changed-line delta" | The ratchet's gate is baseline-equals-census over the whole tree (ADR-290 Decision); a changed-file delta cannot express stale entries or totality | Whole-tree `auto`; changed-files-only is cut (deferral) |
| Brainstorm: "no bundled linters, no imposed rule sets" vs brief: "hash-pinned ruff" | Both hold: the pinned wheel is the BINARY; the rule set is the user's | User config always wins, no Soleur default rule set, pinned ruff wheel reused |
| Brainstorm FR4 says "detect the project's eslint/ruff config" | The existing eslint scope is Soleur-specific (test dirs, a pinned Soleur config); user eslint would be a new engine plus an arbitrary-code-execution surface | CTO second pass: user mode is ruff-only; Soleur's own `eslint-test-dirs` scope and the #10507 vitest carry-in are untouched |
| work/SKILL.md Phase 3 says "Use linting-agent before pushing" | `grep -r linting-agent plugins/soleur` hits only `work/SKILL.md` and `work/references/key-principles.md`; no agent or skill by that name exists | The stale comment line is replaced by the real call; the `key-principles.md` checkbox is reworded (references/ are not byte-capped) |
| ADR-290 residual 7: the per-extension eslint test "runs only locally" | Confirmed from CI: run 39150560896 (PR #10503), job `test-webplat (2/2)` runs `test/eslint-test-dirs-ratchet.test.ts` (1 test, passes, ~5.7 s) and `(1/2)` runs `test/eslint-config.test.ts`; that vitest arm only spawns the live `eslint-test-dirs --check`. `TestEslintConfigBehaviour` (`tests/scripts/test_lint_ratchet.py`, `skipUnless` node_modules) runs in neither (`test-scripts` has no `npm ci`) | Second `it` in the vitest file runs that class and asserts ran-not-skipped |
| "Plugin scripts under plugins/soleur/scripts need a sibling test" | No such requirement; `SUITE_GLOBS` in `scripts/test-all.sh` deliberately excludes `plugins/soleur/skills/*/scripts/*.test.sh`; the whole plugin tree is delivered (`plugins/soleur/AGENTS.md` Manifest versioning) | Tests stay in `tests/scripts/test_lint_ratchet.py` (no new test file, no new registration) |
| Lifecycle SKILL.md byte ceilings | `work`: ceiling 359189, size 358924 (headroom 265 B). `review`: ceiling 475921, size 475873 (headroom 48 B). Measured with `wc -c` and `plugins/soleur/test/skill-body-budget.json`; `python3 scripts/lint-skill-body-budget.py --base origin/main` is green today | Pointer-only edits (below); `skill-body-budget.json` is not touched |
| `lefthook.yml:239` and `scripts/test-all.sh:5150` call `lint-ratchet.py ruff --check` | Confirmed (also `argparse choices=sorted(SCOPES)` at the script's CLI); those names mean the Soleur scopes | User scopes get distinct CLI names (`user-ruff`, `auto`); Soleur names keep their meaning |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10331 OPEN (tracker), #10507 OPEN (both residuals as stated), #10433 OPEN (drawdown). ADR-290 "PR3b contract" read in full: entry format, exit codes, the scope-config dict (`name`, `baseline`, `floor`, `run`, `remedy`, `drawdown`, optional `script`, `recovery_cmd`) and the list of module constants to re-point match the script on `origin/main` (`REPO_ROOT`, `RUFF_REQUIREMENTS`, `SCRIPT_REL`, `ESLINT_CONFIG`, `ESLINT_BIN`, `EXCLUDED_DIRS`, `DRAWDOWN`, `--config ruff.toml` in `tool_argv` and `show_files_argv`). ADR corpus grepped for the mechanism nouns (ratchet, baseline, detect-and-run): no ADR rejects user-mode detect-and-run; ADR-290 reserves it. No cited artifact was stale.

**Property List (Phase 0.6b).**

1. A user who opted in gets the same census-equals-baseline, shrink-only guarantee on their own Python lint findings that Soleur has.
2. A user who did not opt in sees no install, no file written, no behaviour change beyond one informational line.
3. The tool never silently reports green on a scan that failed or whose baseline was removed (the exit-code contract is preserved).
4. The user's own ruff configuration, not a Soleur rule set, defines a finding.
5. `work` and `review` invoke it without exceeding the lifecycle SKILL.md byte ceilings.
6. A corrupt ruff cache and the never-run eslint config test stop being silent gaps (#10507).

**Cut List (Phase 0.6b).** Each mechanism the brief, brainstorm or first-draft plan named, with the property it buys and what already covers it:

- Changed-files-only delta (brainstorm FR4): buys nothing property 1 needs; whole-tree census equality is the ADR-290 gate. Cut.
- Bundled Soleur default rule set for user repos: property 4 forbids it. Cut.
- Separate `detect-and-run` wrapper script: the engine already has the scope machinery; an `auto` CLI scope buys the same. Cut.
- A new `references/*.md` doc: the docstring, printed remedies and the ADR-290 addendum carry the docs, and a reference needs link bytes in a capped SKILL.md. Cut.
- User-mode eslint, `--no-exec`, eslint half of the fingerprint (first-draft plan): a new engine and the only arbitrary-code-execution surface, with no demand evidence. Cut (CTO second pass, D1).
- `--rebaseline` flag: the same lever as plain `--update` gated on the fingerprint. Cut (D2).
- `--root` flag and the committed fixture repo: `--root` existed only for the fixture and caused a git path-base bug. Cut (D6).
- win32 `Skip`, C4 component, learning edit: no ask requires them. Cut (D9).
- Telemetry from customer machines, exit code 3, kill-switch flag, monorepo and workspace support: cut (first CTO pass, ruling 8); tracked in the deferral issue.

**Cost or performance claim (Phase 0.6c).** No cost saving justifies this plan. The only cost claim is "a repo that did not opt in pays nothing": the adoption check precedes ruff provisioning, verified by the discoverability command below (no network, under 15 s) and by a test row that asserts pip is never invoked in the not-adopted state.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md`: totality per tool, pin the whole config, fail-closed `--update`, registrations pinned.
- `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`: keep identity keys, compare to the merge base, not the `origin/main` tip.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: budget the SKILL.md prose as a delta first (done below); the review trim removes a pure provenance pointer, not a condition.
- `2026-09-25-an-env-scoped-skipif-lets-ci-go-green-with-the-check-dark.md` and `2026-10-09-an-rc0-verdict-is-not-proof-the-suite-ran-vacuous-green.md`: the CI wiring must assert the class RAN and was not skipped.
- `2026-02-22-shell-expansion-codebase-wide-fix.md`: repo-root-relative paths do not resolve in user repos; the skills use `${CLAUDE_PLUGIN_ROOT}` and the script resolves its own location (`Path(__file__)`).
- `2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md`: run the orphan census after the change (`scripts/lint-orphan-test-suites.sh`).
- `2026-04-19-enoent-on-optional-mount-should-not-alarm.md`: an expected degraded state on a customer machine (no linter, no baseline, no network) is a documented skip, not an error.

**Repo findings** (repo research): `plugins/soleur/scripts/` and `plugins/soleur/skills/*/scripts/` both ship; callers use `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>"`; precedent for a tool bootstrap in review is `skills/review/scripts/ensure-semgrep.sh`; default-branch fallback precedent is `skills/constraint-scaffold/scripts/constraint-scaffold.sh` `resolve_base_ref`; `.soleur/` is the repo's gitignored-ephemeral directory (written by `scripts/emit-decision.sh` with a `.gitignore` of `*`), which is why the user baseline lives elsewhere; `.github/` has no reference to `ruff-requirements` or `lint-ratchet`; the `test-scripts` shard uses stock `python3` (3.12) and has no `npm ci`.

**Functional overlap (Phase 1.5b).** Registry check found no verified equivalent combining ruff detection with a path/rule/line-hash shrink-only baseline. Closest: `ever-better` (isamu, 27 stars, github.com/isamu/ever-better; installs lint tooling and freezes a ceiling; eslint/TypeScript focused; its baseline keying and ruff support were not verified). Weaker: `holistic-linting`, `code-quality-plugin`, `bully`. Decision: proceed; the engine already exists and is tested, and adopting an external one would add a dependency and lose the keyed identity guarantee. Evaluating `ever-better` is a deferral item.

**Community discovery (Phase 1.5).** Stack is Python, bash and Markdown, covered by built-in agents; skipped.

**External research (Phase 1.6).** Skipped: strong local context (an existing 773-line engine, ADR, tests, CTO rulings) and not a high-risk external-API topic. CLI-verification gate: every ruff flag reused (`check --output-format json --no-cache --no-fix --force-exclude --show-files`) is already in `tool_argv`/`show_files_argv` and pinned by tests (real captured output lives in `tests/scripts/fixtures/lint-ratchet/`). The only NEW argv shape is ruff without `--config` (and without `--ignore-noqa`); work Phase 0 task 0.2 exercises it with the pinned binary and pastes the verified line into the PR body before relying on hierarchical discovery.

## Problem Statement / Motivation

Most findings GitHub Code Quality reported on Soleur are habits of agent-written code (unclosed files, empty handlers, unused imports). The same habits appear in Soleur users' repositories, and Soleur's own pipeline should catch them deterministically instead of leaving them in a GitHub tab. Slice 1 made Soleur's own tree clean-or-baselined; the repository ratchet cannot reach a user's repo because the engine, its pinned ruff and its configs are repo-local. The operator chose to build this slice despite the CPO finding no demand evidence, so it stays small: opt-in, Python-only, no bundled rule set, almost no new SKILL.md weight.

## Proposed Solution

Ruled by CTO agent, 2026-10-18 (two passes; the second amends the first where the plan-review seats dissented; full text in `decision-challenges.md`):

1. **Distribution.** `git mv scripts/lint-ratchet.py plugins/soleur/scripts/lint-ratchet.py` and `git mv scripts/ruff-requirements.txt plugins/soleur/scripts/ruff-requirements.txt` (bytes unchanged, so existing ruff caches stay valid). The Soleur scopes stay in the same file as a labelled "Soleur block"; no library/client split (the suite patches module attributes `lr.ensure_ruff`, `lr._git`, `lr.tracked_files`, `lr.REPO_ROOT`, `lr.build_config`). No shim at the old path. `REPO_ROOT` becomes a `resolve_root()` function: `git rev-parse --show-toplevel` from the cwd (no `--root` flag; every git call uses the toplevel, so cwd-relative and toplevel-relative paths cannot mix). Pins become script-relative (`Path(__file__).resolve().parent`). `SCRIPT_REL` becomes `plugins/soleur/scripts/lint-ratchet.py`. The Soleur baselines `scripts/lint-ratchet-{ruff,eslint-test-dirs}.baseline.txt`, `ruff.toml` and `apps/web-platform/eslint.test-dirs.config.mjs` stay where they are (moving a baseline in the same diff as the script trips ADR-290 residual 3 and would exit 2 in CI).
2. **Scope names.** User scopes are not in the `SCOPES` dict, so the Soleur pins and `argparse choices=sorted(SCOPES)` stay untouched; `ruff` and `eslint-test-dirs` keep their Soleur meaning everywhere (lefthook, `test-all.sh`, the vitest arm). Two new CLI scope names: `user-ruff` (the real user scope: `--check`, `--update`, `--list`) and `auto` (detects, then runs `user-ruff`).
3. **Tool config (user mode, ruff only).** The user's own config always wins; Soleur applies no rule set. `user-ruff` is active only when a tracked `ruff.toml`, `.ruff.toml`, or a `pyproject.toml` with a line matching `^\[tool\.ruff` exists (line grep anchored at line start, no `tomllib`: py3.9-safe; a commented `# [tool.ruff]` does not match). Ruff runs with NO `--config`, so its hierarchical discovery applies, using the same hash-pinned wheel. The user's waivers (`# noqa`) are honoured (no `--ignore-noqa`); the waiver-proof flag stays on for the Soleur scopes only, carried by a scope-dict key. User mode has its own remedy and waiver text (`REMEDY_RUFF` and the "inline waivers are NOT honoured" line are Soleur-specific). When ruff exits 2 for a config reason, one fixed line is appended: `pinned ruff is <pin>; a config with required-version or rules newer than the pin fails here`.
4. **User-mode totality (exactly three checks).** (a) A `Failed to` or IO error on stderr, a ruff exit code outside {0, 1}, or an unparsable JSON result is exit 2. (b) `--show-files` supplies only the "(<m> files scanned)" count and the zero-file case; there is no tracked-versus-listed comparison and no `EXCLUDED_DIRS` check (ruff default excludes such as `build/`, `dist/`, `venv/` and the user's own `extend-exclude` would otherwise be a false red forever). (c) No numeric floor: an adopted repo with zero files in ruff's own listing is exit 0 with a hint when the baseline has zero entries; if the baseline has entries, the ordinary STALE rule gives exit 1. Accepted residual: excluding everything with an empty baseline passes; that edit changes the config hash and takes the fingerprint path (human review).
5. **Baseline lifecycle.** Adoption is opt-in, no auto-baselining. Location `.lint-ratchet/ruff.baseline.txt` at the repository root, tracked in git (not under `.soleur/`, which is gitignored-ephemeral by convention; a root `.soleur/` ignore cannot be undone with a negation). With a detected ruff config and no baseline, `auto` exits 0 and prints `not adopted: run python3 <abs script path> user-ruff --update once, then commit .lint-ratchet/`, before any ruff provisioning. `--update` with no baseline at HEAD writes the census; `--check` never writes; `--update` prints the written path plus "commit it", and when `git check-ignore -q` matches the path it prints one line saying the path is git-ignored and must be un-ignored to be committed (it never edits the user's `.gitignore`). **Deleted-baseline rule:** if the baseline exists at the resolved merge base and is missing from the working tree, `check` exits 1 in all modes including CI with `baseline deleted since the merge base: restore it; if you are un-adopting on purpose, the check passes once the deletion is on the base branch` (a deliberate un-adoption PR is therefore blocked in `work` until the deletion merges; accepted). **Merge base ladder:** `--base <ref>`, else `git symbolic-ref -q refs/remotes/origin/HEAD`, else the first of `origin/main`, `origin/master`, else the existing skip-with-warning (exit 0 locally, exit 2 under `CI`). Not in a git repository: `Skip` (exit 0). In user mode `drawdown` is None (header omits the line), `script` is None (the "baseline moved" rule is off), `recovery_cmd` is `python3 <resolved absolute script path> user-ruff`. **Soleur self-skip:** `auto` run in the Soleur repository (test: `scripts/lint-ratchet-ruff.baseline.txt` exists at the git toplevel) prints `Soleur repository: scopes run via lefthook and CI; nothing to ratchet here` and exits 0, before any adoption message and before provisioning (it does not dispatch to the Soleur scopes: that would duplicate lefthook and `test-all.sh`).
6. **Toolchain fingerprint (ruff only, no flag).** The baseline header records `# toolchain: ruff <pin> ; config sha256:<12hex>` (hash over the bytes of the detected ruff config files; for `pyproject.toml` the whole file, noise only forces a harmless re-baseline). Census equality stays the gate. Plain `--update` may grow the baseline only when the stored and live fingerprints differ (otherwise it refuses real growth exactly as today); when the fingerprints differ the merge-base growth comparison is skipped; a NEW-findings failure prints `toolchain or config changed since the baseline: run --update`. Accepted residual, stated in the ADR addendum and at the `--update` print site: an agent can edit the config, run `--update`, and go green; the control is PR review.
7. **Invocation.** No wrapper. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" auto` detects, then checks the whole tree (baseline equality is whole-tree). No ruff config detected: print `lint-ratchet: no linter configured (looked for ruff.toml, .ruff.toml, pyproject.toml [tool.ruff]); nothing to ratchet`, exit 0. `auto` catches `Skip` itself and exits with the `user-ruff` verdict.
   - `work`, Phase 3 step 1: replace the stale `# Use linting-agent before pushing to origin` line (48 B) with `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" auto  # exit 1: fix per its output (blocks handoff); 2 or skip: report, continue` (140 B): net +92 B of the 265 B headroom. Exit 1 blocks handoff to Phase 4 (acceptable: the user opted in by committing a baseline); exit 2 and Skip get one in-session sentence and work continues.
   - `review`: one pointer between the `**Bootstrap (mandatory before spawning the agent):**` paragraph and the next `**What this agent checks:**` heading after it: `**Lint ratchet (user repos):** python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" auto; exit 1 = one P2 finding, 2 or skip = a summary note, never a block.` (162 B). Ruff config is declarative, so no `--no-exec` is needed. The 48 B headroom does not fit 162 B, so the same edit removes the pure provenance sentence in the Bash-only bullet that begins "See" and names the learning `2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` and "the bench-pattern session that surfaced this" (149 B; the `**Why:** PR #4045` clause that carries the condition stays; `git grep` shows no other reference to that learning from `plugins`, `scripts`, `tests` or `.github`). Measured net for review: +13 B (leaving 35 B of headroom).
   - Cloud mode: `CLAUDE_PLUGIN_ROOT` may be unset in cloud shells; the existing `${CLAUDE_PLUGIN_ROOT}/scripts/...` calls in `work/SKILL.md` set the precedent, no new resolver.
8. **Byte budget.** Pointer-only edits, no reference file, `skill-body-budget.json` untouched. Run `python3 scripts/lint-skill-body-budget.py --base origin/main` before every push.
9. **Carry-ins (#10507).** (1) In `ensure_ruff`, after the install/rename block, if `exe` still does not exist raise `InfraError("ruff cache {final} exists without bin/ruff; delete it and retry: rm -rf {final}")`, and append the same `rm -rf {final}` hint to the version-probe failure message; hint only, no auto-delete; one test builds `final` without `bin/ruff` and asserts the message names the directory; remove ADR-290 residual 7 once both land. (2) Add a second `it` to `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` that spawns `python3 -m unittest tests.scripts.test_lint_ratchet.TestEslintConfigBehaviour -v`, asserts exit 0, `Ran (\d+) tests?` with N at least the class's pinned case count (1 today; derive it from the class, do not hard-code a second copy) and no `skipped` in the unittest footer; porting to vitest is rejected (it would duplicate the oracle in a second language). The `test-webplat (2/2)` shard already has `node_modules`.

## Technical Considerations

- **Moving the script.** The sweep list is: `lefthook.yml` (`ruff-ratchet` and `eslint-test-dirs-ratchet` commands, and both glob lists so they name the new script and requirements path), `ruff.toml` header comment, `scripts/test-all.sh` (comment near line 3806; the two `run_suite` lines keep their labels, the command of `scripts/lint-ratchet-ruff-live` changes path), `scripts/lib/test-affected-paths.sh` (verify only; labels unchanged), `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (labels unchanged, so no edit), `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`, `apps/web-platform/eslint.test-dirs.config.mjs` header comment (its sha256 is pinned in the test: update the digest in the same commit), both baseline headers (regenerate with `--update`, header text only), `tests/scripts/test_lint_ratchet.py`, ADR-290. `git grep -n 'ruff-requirements\|lint-ratchet' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` is the closing check; `.github/` has no reference (verified).
- **`tests/scripts/test_lint_ratchet.py` sweep (verified against the file).** `SCRIPT` (line 40) and `SCRIPT_REL` pin (line 1141); the ruff-requirements reads (lines 1247, 1252, 1323, 1334); the `run_suite` regex pin (1175-1179); the lefthook block pins and the expected glob list (1187-1204); `TestRegistration.test_the_vitest_arm_is_registered_as_repo_wide` pins the string `"scripts/lint-ratchet.py", "eslint-test-dirs", "--check"` in the vitest file (line 1220), so it follows the new path; the `lr.REPO_ROOT` patch (line 1496) becomes a `resolve_root` patch; the cache-directory assertion (line 1354); `MIN_CASES = 60` (line 42) and the class set in `test_every_guard_class_is_loaded` (line 1614) must grow with the new classes; `test_baseline_paths_follow_the_lint_convention` (line 1157) assumes `scripts/lint-` and is scoped to the Soleur scopes.
- **Lefthook globs.** After the move the ruff entry's glob list must name the new requirements path (pin test `test_lefthook_ruff_globs_are_exactly_the_scope_plus_the_inputs` otherwise fails) and the eslint entry's list names the new script path.
- **Ruff scans the moved script.** `plugins/soleur/scripts/lint-ratchet.py` is a tracked `*.py`; the ruff baseline has no entry for it (the three `lint-ratchet` matches in the baseline are header lines), so it must stay finding-free.
- **Hyphenated module.** The test loads the script with `importlib.util.spec_from_file_location`; keep that.
- **Portability.** The script is stdlib-only and py3.9-safe; no GNU-only external binaries beyond `git`; subprocess timeouts instead of `timeout`.
- **Supply chain.** The ruff wheel install keeps `pip --isolated --require-hashes --only-binary=:all:`, scrubbed `PIP_*`/`PYTHON*`, private `0700` cache; a hash mismatch is exit 2 everywhere; an unreachable index is a loud `SKIP` locally and exit 2 under `CI`.
- **Tests.** Stay in `tests/scripts/test_lint_ratchet.py` (a new file would need four registrations). The discoverability wrapper is not a `*.test.sh`, so the suite globs and the orphan census do not pick it up.

## Open Code-Review Overlap

Queried 96 open `code-review` issues against the planned files. Matches: `scripts/test-all.sh` is named by #8659 (test-helpers composed EXIT trap leak) and #7942 (two mutation batteries run in no gate). **Acknowledge** both: different concern (the file is edited only for a comment and path strings); they remain open. No match for `scripts/lint-ratchet.py`, `tests/scripts/test_lint_ratchet.py`, the work/review SKILL.md files, `lefthook.yml`, the vitest arm, or ADR-290.

## Files to Edit

- `scripts/lint-ratchet.py` -> moved to `plugins/soleur/scripts/lint-ratchet.py` (see Files to Create), then edited
- `tests/scripts/test_lint_ratchet.py` (new classes, re-points, mutation rows; see the sweep above)
- `plugins/soleur/skills/work/SKILL.md` (Phase 3 step 1: replace the `linting-agent` comment line; net +92 B)
- `plugins/soleur/skills/review/SKILL.md` (lint-ratchet pointer; trim the bench-pattern provenance sentence; net +13 B)
- `plugins/soleur/skills/work/references/key-principles.md` (the `Linting passes (use linting-agent)` checkbox; not byte-capped)
- `lefthook.yml`, `ruff.toml` (header comment), `scripts/test-all.sh` (comment and command path), `scripts/lib/test-affected-paths.sh` (verify only)
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (second `it`; new script path), `apps/web-platform/eslint.test-dirs.config.mjs` (header comment; update the pinned digest in the test)
- `scripts/lint-ratchet-ruff.baseline.txt`, `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (regenerated headers only; entries identical)
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md` (addendum; delete residual 7 once delivered)

## Files to Create

- `plugins/soleur/scripts/lint-ratchet.py` (via `git mv`; adds `resolve_root`, `user-ruff` and `auto` scopes, detection, fingerprint, deleted-baseline rule, ruff-cache hint)
- `plugins/soleur/scripts/ruff-requirements.txt` (via `git mv`; bytes unchanged)
- `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` (discoverability wrapper: builds a throwaway repo and runs `auto`; synthetic content only, per `cq-test-fixtures-synthesized-only`; not named `*.test.sh`)
- `knowledge-base/project/specs/feat-one-shot-10331-plugin-detect-and-run/{tasks.md,decision-challenges.md}`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "PR3b, plugin detect-and-run, so users of the Soleur plugin get the same deterministic lint signal on their own repositories" | Proposed Solution 1-7 | mapped |
| 2 | "READ ADR-290's \"PR3b contract\" first and reuse scripts/lint-ratchet.py's contract: exit 0/1/2 semantics, scan totality, the hash-pinned ruff" | Proposed Solution 1, 3, 4, 7; Guard Contract | mapped |
| 3 | "The change edits the work and review SKILL.md files (detect which linters apply to the user's repo, run them, ratchet against a baseline)" | Proposed Solution 7; Files to Edit | mapped |
| 4 | "the CTO agent (soleur:engineering:cto) rules every technical fork (distribution of the script to plugin users, baseline location in a user repo, detection rules, how work/review invoke it, byte-budget impact on the lifecycle SKILL.md ceilings)" | decision-challenges.md rows 1-20 | mapped |
| 5 | "a corrupt ruff cache gives no recovery hint, add a one-line hint naming the cache directory" | Proposed Solution 9(1) | mapped |
| 6 | "the eslint per-extension test only runs off-CI, wire it into a CI-run suite or confirm the webplat shard already runs the eslint vitest guard (inspect the CI logs; this was never separately inspected)" | Research Reconciliation row 6; Proposed Solution 9(2) | mapped |
| 7 | "Close #10507 in this PR if both are delivered." | frontmatter `closes: [10507]`; PR body reminder | mapped |
| 8 | "the PR body must say \"Ref #10331\" and must not use any closing keyword for it" | PR body reminder (below) | mapped |
| 9 | "run soleur:ship and soleur:postmerge to completion" | downstream pipeline, not a plan item | descoped - justification: executed by the pipeline after this plan |
| 10 | "drawdown of the baselined findings tracked in open issue #10433, and the decision on whether per-PR GitHub Code Quality stays on" | Not in this slice | descoped - justification: the brief lists them as remaining after this slice |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Move the engine into the plugin | "the CTO agent ... rules every technical fork (distribution of the script to plugin users" | asked |
| `auto` and `user-ruff` CLI scopes | "how work/review invoke it" | asked |
| Python-only user mode | "detect which linters apply to the user's repo" | asked (the brief names ruff's hash pin; JS/TS user support is a deferral, CTO D1) |
| Toolchain fingerprint | "ratchet against a baseline" | inferred - justification: with the user's own config as the rule set, a config or ruff-pin change moves the census; without it Soleur bumping the pin would wedge every opted-in user (CTO D2) |
| Deleted-baseline rule | "same deterministic lint signal" | inferred - justification: judging adoption on the working tree alone lets a PR dodge the ratchet by deleting the file (CTO D5) |
| Soleur self-skip | "reuse scripts/lint-ratchet.py's contract" | inferred - justification: `auto` run in the Soleur repo would otherwise tell Soleur's own agents to adopt (CTO D4) |
| Lefthook, ADR and test re-points | "this slice moves and re-points" | asked |
| Discoverability wrapper | "reuse ... the hash-pinned ruff" | inferred - justification: the Observability gate needs one local command that proves the not-adopted arm without network (CTO D6) |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur/scripts`, `plugins/soleur/skills`, `tests/scripts` with `scripts/` and `lefthook.yml`, `apps/web-platform/test` (plus KB docs)
- Planned files: about 20 | Estimated changed lines: about 550 (the script gains roughly 180 lines; tests about 250; the rest are path edits)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The subsystem count meets the threshold nominally, but the roots are the engine, its callers and its registrations, which must move atomically (a script move split across PRs breaks `lefthook`, `test-all.sh` and the required `test` context in between).

## User-Brand Impact

- **If this lands broken, the user experiences:** `work` refusing to hand off (exit 1) on a repo that opted in because of a mis-detected config or a deleted-baseline false positive, or a `.lint-ratchet/` directory written where they did not expect one; all require the user to have run `--update` themselves, and a not-adopted repo sees one informational line.
- **If this leaks, the user's workflow is exposed via:** the one-time pip install of a hash-pinned ruff wheel; no user data is read beyond file paths, rule ids and 12-hex line fingerprints, and nothing is sent anywhere (no telemetry). User mode runs ruff only, so no repository-supplied JavaScript is executed.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: the tool is opt-in, local, Python-only, never writes without an explicit `--update`, and executes no repository code; a one-user failure is a skipped or noisy lint line, not a data or money loss.

## Observability

Customer-machine surface (layer 7 of `hr-observability-layer-citation`: plugin code that executes on a customer's self-hosted CLI). There is no telemetry from customer machines by decision (CTO ruling 7; phoning home from a customer's machine is a consent and legal matter, deferred to `soleur:legal:clo` only if ever proposed); every failure mode surfaces locally as a `lint-ratchet(<scope>): ...` stderr line plus an exit code that `work` and `review` report in-session. Soleur's own CI runs the engine on every PR (`scripts/lint-ratchet-ruff-live`, the vitest arm), which is the fleet-side signal.

```yaml
liveness_signal:
  what: "lint-ratchet(user-ruff): OK (<n> findings baselined, <m> files scanned) line and exit 0 on every opted-in run; the Soleur-side run is the required test context"
  cadence: "per work Phase 3 run, per review run, per Soleur PR in CI"
  alert_target: "the invoking skill's in-session report; Soleur CI required check for the Soleur scopes"
  configured_in: "plugins/soleur/skills/work/SKILL.md (Phase 3 step 1), plugins/soleur/skills/review/SKILL.md (lint-ratchet pointer), scripts/test-all.sh (run_suite scripts/lint-ratchet-ruff-live)"
error_reporting:
  destination: "stderr of the script and the skill transcript; no Sentry (customer machine, no consent for outbound telemetry)"
  fail_loud: "exit 2 with a lint-ratchet(<scope>): line naming the infrastructure fault and the recovery command; exit 1 with NEW/STALE/baseline-deleted lines; Skip prints one SKIP line and exits 0"
failure_modes:
  - mode: "ruff cache directory exists without bin/ruff"
    detection: "InfraError naming the cache path and 'rm -rf <dir>' (new test row)"
    alert_route: "work/review in-session report"
  - mode: "ruff failed to lint a file, exited outside 0/1, or printed unparsable JSON"
    detection: "totality check (a) exits 2 with the ruff stderr line"
    alert_route: "work/review in-session report"
  - mode: "baseline deleted or git-ignored so it never reaches the base branch"
    detection: "deleted-baseline rule exits 1; --update prints the git check-ignore line"
    alert_route: "the invoking skill's in-session report and the --update output"
logs:
  where: "stdout/stderr of the invoking skill session"
  retention: "session transcript only"
discoverability_test:
  command: bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh
  expected_output: not adopted
```

The wrapper `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` runs `mktemp -d`, `git init`, writes a `pyproject.toml` with a `[tool.ruff]` table and one `.py` file, `git add`s both (no commit needed), and runs `python3 plugins/soleur/scripts/lint-ratchet.py auto` from there. It reaches the not-adopted arm before ruff provisioning, so there is no network and no pip, and it finishes in well under 15 s. The command does not exist until this PR's work phase creates it, so it cannot be run at plan time; work Phase 0 task 0.6 runs it once before the first commit and again before ship (Sharp Edge: run every command the plan prescribes).

## Encryption Posture

```yaml
at_rest:
  - store: ".lint-ratchet/ruff.baseline.txt in the user's repository"
    mechanism: "the user's own repository storage and their git hosting at-rest controls; Soleur adds none"
    evidence: "the file holds only paths, rule ids and 12-hex line fingerprints (no source text, no secrets); format pinned by ENTRY_RE in plugins/soleur/scripts/lint-ratchet.py"
    defends_against: "none claimed by Soleur"
    does_not_defend: "disclosure of file paths and rule ids to anyone with read access to the repository"
    disclosed_as: "ADR-290 addendum and the script docstring"
    live_verification: "tests/scripts/test_lint_ratchet.py asserts a rendered baseline contains no source line text"
in_transit:
  - connection: "pip to https://pypi.org/simple for the pinned ruff wheel (first run only)"
    tls: "HTTPS to pypi.org via pip defaults"
    cert_verification: on
    does_not_defend: "a compromised PyPI account or CDN serving a wheel is caught only by the pinned sha256 for each of the 17 wheels (--require-hashes), not by TLS; a user behind a TLS-intercepting proxy trusts that proxy"
    disclosed_as: "ADR-290 Decision (hash-pinned ruff) and the addendum"
```

## Guard Contract

### Guard 1 - lint-ratchet user-mode scan (opt-in, totality, shrink-only)

**Property.** For a user repo that opted in, the check exits 0 only when the live census of the user's own ruff findings equals the committed baseline and has not grown since the merge base (unless the toolchain fingerprint changed), the baseline has not been deleted since the merge base, and the scan did not fail; it never provisions ruff for a repo that did not opt in.

**Assembly.** The property quantifies over: every entry path into a verdict (`check`, `update`, `list_live`, and the `auto` dispatcher, which must not compute a verdict of its own but call `check` for `user-ruff`); both baseline readers (head working tree and merge base via `baseline_at`); the three config-detection inputs (`ruff.toml`, `.ruff.toml`, a `pyproject.toml` `^\[tool\.ruff` line) and the fingerprint reader; the three totality checks of Proposed Solution 4; every code path that can decide the scope is NOT applicable or skipped (Soleur self-skip, no ruff config, not adopted, not a git repository, unresolvable base) — each must return exit 0 only with its documented line, never a bare 0; and the provisioning chokepoint (`ensure_ruff`, reached from `run_ruff` only), which the adoption check must precede. The chokepoint every verdict flows through is `check()`.

**Mutation matrix** (four rows, CTO D11; each is derived from the design, not from the finished code):

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the adoption check so a not-adopted repo provisions ruff (also covers a dead `auto` dispatch: `auto` returns 0 on a repo with a ruff config and a baseline holding a stale entry) | RED (the not-adopted row asserts pip is never invoked and the whole line `not adopted` is printed; the stale-entry row must exit 1, not 0) |
| 2 | Pass `--ignore-noqa` in user mode | RED (the waiver-honoured row: a finding with `# noqa` must not count; the Soleur waiver-ignored row still counts) |
| 3 | Let `--update` grow the baseline when the stored and live fingerprints are equal, or skip the merge-base growth comparison when they are equal | RED (growth-refused row with equal fingerprints; fingerprint-differs row proves growth is allowed only then) |
| 4 | Remove the deleted-baseline rule | RED (a repo whose baseline exists at the merge base and is missing at HEAD must exit 1) |

**Harness rows.**

- Suite edit that MUST redden: let `TestEslintConfigBehaviour` skip (or delete the `skipped` assertion) in the new vitest `it` and confirm the vitest test goes RED; delete the `work` or `review` anchor pin and confirm the anchor test goes RED.
- Must-PASS inputs that are not the canonical: a repo whose default branch is `master` with no `origin/main` and a ruff config in `.ruff.toml` (not `ruff.toml`); a `pyproject.toml` carrying `[tool.ruff.lint]` rather than `[tool.ruff]`; an adopted repo whose baseline is empty and whose tree is clean (OK with 0 findings and files scanned >= 1).

**Anchor.** The stored value is the baseline and its toolchain fingerprint. What outside the commit must move for a weakening to pass: the merge-base comparison reads the baseline at the merge base, so a diff that edits both the baseline and the code is caught by growth; a diff that also edits the user's ruff config changes the fingerprint and legitimately skips the growth comparison. That is an accepted residual (an agent can disable a rule, run `--update` and go green), the control is PR review, and it is stated in the ADR-290 addendum and at the `--update` print site. Soleur's own scopes keep ADR-290's controls (pin tests, registration test).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-290 (no new ADR; CTO ruling 7) via the `soleur:architecture` skill: an addendum realizing the PR3b contract (script moved to `plugins/soleur/scripts/`; user mode is Python-only, honours the user's config and waivers; adoption is opt-in; baseline in `.lint-ratchet/`; toolchain fingerprint without a flag and the accepted weakening; deleted-baseline rule; user-mode totality is three checks; Soleur self-skip; `SCRIPT_REL` change and why the Soleur baselines stayed put). Update the "PR3b contract" paragraph from future to past tense, add the rejected alternatives to `## Alternatives Considered` (bundled default rule set, wrapper script, shim at the old path, library/client split, changed-files-only, user-mode eslint in this slice, a `--rebaseline` flag, a `--root` flag), and delete residual 7 once both carry-ins land. This is a task in Phase 5 of `tasks.md`, not a follow-up.

### C4 views

No C4 impact. Mandate satisfied by reading the C4 model before concluding: this plan read `views.c4` (the `components` view include list), `spec.c4` element kinds, and the `platform.plugin` description and `constraintscaffold` component in `model.c4`; the full three-file read is repeated in work task 0.4 before the ADR addendum is finalised. Enumerated against the feature: (a) external human actor: the Soleur plugin user is the already-modelled `founder` (no new actor); (b) external system: PyPI (the ruff wheel source) is not modelled and `model.c4` carries no package-registry element or registry edge (a grep for `pypi|npm registry|registry` found only the engine registry component), and the CTO ruled no edge is invented for it; the user's repository is the existing connected-repo concept, not a new system; (c) container or data store: none (the baseline is a file in the user's repo); (d) actor-surface access relationships: unchanged. A green `bash plugins/soleur/test/c4-count-parity.test.sh` (run at plan time: `ALL TESTS PASSED`, Failed: 0) backs the cardinality side; no skill or agent is added, so the "103 workflow skills" and "67 domain agents" counts do not move. The `platform.plugin` description sentence on shipped scripts ("shared bash primitives shipped for execution on an installed user's machine") is not falsified by one more shipped script; if work finds otherwise it is reworded in the same commit.

### Sequencing

Single PR: the ADR addendum describes the shipped state; no status flip is deferred.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/scripts/lint-ratchet.py` and `plugins/soleur/scripts/ruff-requirements.txt` exist; `scripts/lint-ratchet.py` and `scripts/ruff-requirements.txt` do not (`git diff -M --stat origin/main...HEAD` reports them as renames, `ruff-requirements.txt` at 100% similarity).
- [ ] `git grep -n 'scripts/lint-ratchet\.py\|scripts/ruff-requirements\.txt' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings' ':!**/archive/**'` returns only hits that carry the `plugins/soleur/` prefix (own planning artifacts, learnings and archives are point-in-time records).
- [ ] The exit-code matrix passes (`python3 -m unittest tests.scripts.test_lint_ratchet` exits 0) with these rows, implemented in `plugins/soleur/scripts/lint-ratchet.py` (`check`, `auto`, `main`) and asserted as WHOLE lines where a line is specified: no ruff config -> 0 with the `no linter configured` line; ruff config without baseline -> 0 with the `not adopted` line and pip never invoked; adopted and clean -> 0; NEW finding -> 1; STALE entry -> 1; growth against a repo whose default branch is `master` (no `origin/main`) -> 1; baseline deleted since the merge base -> 1 (also under `CI`); unresolvable base -> 0 with the warning locally and 2 under `CI`; fake-ruff infrastructure failure -> 2 with the pinned-version hint line; not a git repository -> Skip/0; `auto` in a tree with `scripts/lint-ratchet-ruff.baseline.txt` -> the Soleur self-skip line and 0 without provisioning.
- [ ] Totality rows pass: a `Failed to` stderr line -> 2; a ruff exit code outside {0, 1} -> 2; unparsable JSON -> 2; a tracked `build/x.py` that ruff does not list does not read as a skipped file; an adopted repo with zero files in ruff's listing and an empty baseline -> 0 with a hint; with a non-empty baseline -> 1 (STALE).
- [ ] Fingerprint rows pass: a config change plus growth exits 1 and prints `toolchain or config changed since the baseline: run --update`; `--update` grows the baseline only when the fingerprints differ and refuses when equal; the growth comparison is skipped when they differ.
- [ ] Waiver rows pass: a `# noqa` in user mode is honoured; in Soleur mode the same finding still counts.
- [ ] `--update` rows pass: a git-ignored target path prints the check-ignore line and the written path; the rendered baseline contains no source line text.
- [ ] Carry-in 1: a `final` cache directory without `bin/ruff` produces an `InfraError` naming that directory with `rm -rf`; the version-probe failure message carries the same hint.
- [ ] Carry-in 2: `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` has a second `it` that runs `TestEslintConfigBehaviour`, asserts exit 0, `Ran N tests` with N at least the class's case count and no `skipped` in the unittest footer; it passes locally (`cd apps/web-platform && ./node_modules/.bin/vitest run test/eslint-test-dirs-ratchet.test.ts`) and the `test-webplat` shard log of the PR shows both `it` names passing. `Closes #10507` is in the PR body only if both carry-ins are green.
- [ ] `plugins/soleur/skills/work/SKILL.md` contains the anchor `lint-ratchet.py" auto` and no `linting-agent`; `review/SKILL.md` contains `lint-ratchet.py" auto` between its `**Bootstrap (mandatory before spawning the agent):**` paragraph and the next `**What this agent checks:**` heading after it; an anchor test in `tests/scripts/test_lint_ratchet.py` pins both (fences and HTML comments stripped before matching).
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` is green; measured deltas recorded in the PR body: `work` +92 B against 265 B headroom, `review` +13 B against 48 B headroom; `git diff --quiet origin/main...HEAD -- plugins/soleur/test/skill-body-budget.json` (unchanged).
- [ ] `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check` are green on this tree (Soleur scopes unchanged: 44 ruff entries, 20 eslint entries; floors 55 and 105 intact) and the lefthook entries run the new path.
- [ ] `bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` prints a line containing `not adopted` in under 15 s with no network.
- [ ] The lefthook glob pins, registration pins (`MIN_CASES`, the guard-class set) and `scripts/lint-orphan-test-suites.sh` are green after `git add` of every new tracked file.
- [ ] ADR-290 carries the addendum and no longer carries residual 7.
- [ ] `bash scripts/test-all.sh --affected` (or the full battery if the affected gate degrades) is green; CI `test`, `test-webplat` (both shards) and `test-scripts` are green.
- [ ] PR body: first line `Ref #10331`; no `Closes/Fixes/Resolves #10331`; `Closes #10507` present; `## Changelog` section; label `semver:patch`.
- [ ] Markdown lint on the plan and `tasks.md` is clean (`npx markdownlint-cli2`).

### Post-merge (operator)

None. `soleur:postmerge` verifies, with the merged `main`: `bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` prints `not adopted`, the required `test` context on `main` is green, `gh issue view 10507 --json state` is CLOSED and `gh issue view 10331 --json state` is OPEN (Automation: all steps are agent-runnable; none needs the operator).

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled all forks in two passes (2026-10-18); the second pass amended the first where the plan-review seats (DHH, Kieran, code-simplicity) dissented. See `decision-challenges.md`.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:engineering:cto
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

Brainstorm CPO assessment carried forward: no demand evidence for the user-facing half; operator overrode on 2026-10-15; the plan therefore keeps the slice opt-in, Python-only and minimal. No UI file is created or edited (the mechanical UI-surface override did not fire: no `components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx` path in the file lists). Legal: no new data processing (no telemetry, nothing leaves the machine except the existing hash-pinned PyPI wheel fetch); `gdpr-gate` is not triggered (no schema, auth, API-route or `.sql` path; none of the cross-controller triggers a-d fires: no LLM or external API on session data, threshold is `aggregate pattern`, no cron reads learnings, and no new artifact-distribution surface beyond the already-shipped plugin tree). The telemetry question goes to `soleur:legal:clo` only if telemetry is ever proposed.

## Test Scenarios

- Synthetic user repos in a tmp dir (existing `Repo` helper in `tests/scripts/test_lint_ratchet.py`): the exit-code and totality matrices above, run through `main()` and through `subprocess` for the CLI arms (`auto`, `user-ruff --update`).
- Default-branch ladder: one row for a repo with only `origin/master`; one for `refs/remotes/origin/HEAD` pointing at `develop`.
- A git-ignored baseline path row (a `.gitignore` containing `.lint-ratchet/`).
- Counter and whole-line rows: the fingerprint line, the `not adopted` line and the self-skip line are asserted as WHOLE lines, not substrings; a baseline with two identical-anchor entries; a zero-findings adopted repo.
- Vitest: both `it` blocks in `eslint-test-dirs-ratchet.test.ts`.
- Verify the verifier: the four mutation rows run in a scratch copy (use the allocator in `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`; none of these mutants touch `kill`, `pkill`, `$PPID` or `rm -r` helpers, and the `rm -rf` hint text is asserted as printed text only, never executed).

## Risks and Mitigations

- **Config detection by line grep misreads `pyproject.toml`** (a commented `# [tool.ruff]`). Mitigation: the grep is anchored at line start; a commented-line row.
- **A user config incompatible with the pinned ruff** (`required-version`, newer rules) makes ruff exit 2 on every run. Mitigation: the fixed pinned-version hint line; exit 2 is non-blocking in `work` and `review`.
- **`work` blocking on exit 1** is deliberate for opted-in repos only. A false positive from a changed config is escaped by `--update` under the fingerprint rule, not by a skip flag (kill-switch cut). A deliberate un-adoption is blocked until the deletion merges on the base branch (accepted).
- **Review byte ceiling** (48 B headroom): the trim is a provenance pointer only; `lint-skill-body-budget.py` is the gate; do not compress any condition-bearing sentence.
- **Prior-art divergence from the brainstorm** (changed-lines delta and user eslint dropped): recorded in `decision-challenges.md` so the spec and brainstorm are not read as unmet.

## Deferrals (tracked)

Phase 0 work task 0.3 files one tracking issue (milestone from `knowledge-base/product/roadmap.md`, re-evaluation criteria stated, referencing #10331) for: user-mode JS/TS (eslint) support, monorepo and workspace support, changed-files-only advisory mode, opt-in telemetry (needs `soleur:legal:clo` first), and evaluating `ever-better` as an alternative.

## PR Body Reminder

`Ref #10331` as the first line; `Closes #10507`; no closing keyword for #10331; include the measured SKILL.md byte deltas and the CI-log evidence for carry-in 2; `## Changelog`; `semver:patch`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it with `aggregate pattern`.
- The SKILL.md edits are byte-budgeted as deltas up front (work +92 B of 265 B; review +13 B of 48 B); compression under a failing hook drops conditions, so write the final wording once and measure with `wc -c` before and after.
- `git add` every new tracked file (script, wrapper, tests) before running the orphan census or repo-global ratchets; they read tracked files only.
- The hyphenated script name means tests must keep loading it with `importlib`.
- `scripts/lint-ratchet-*.baseline.txt` do not move in this PR, on purpose (ADR-290 residual 3).
- The Soleur scope names `ruff` and `eslint-test-dirs` are bound by lefthook, `test-all.sh` and argparse; never reuse them for user mode.
