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

## Enhancement Summary

**Deepened on:** 2026-10-18
**Sections enhanced:** Proposed Solution (items 1-8), Technical Considerations, Observability, Guard Contract, Architecture Decision, Acceptance Criteria, Risks
**Agents used:** soleur:engineering:cto (three rulings passes), soleur:engineering:review:dhh-rails-reviewer, soleur:engineering:review:kieran-rails-reviewer, soleur:engineering:review:code-simplicity-reviewer (plan-review), soleur:engineering:review:security-sentinel, soleur:engineering:review:architecture-strategist, soleur:engineering:review:observability-coverage-reviewer, soleur:product:spec-flow-analyzer, a general-purpose agent that measured ruff 0.16.10 behaviour empirically, learnings-researcher, repo-research-analyst, functional-discovery

### Key Improvements

1. The toolchain-fingerprint rule is redefined so it cannot be switched on by editing the baseline header or left open by a stale header (compare merge-base header with HEAD header AND HEAD header with the live fingerprint; a visible `CONFIG CHANGED` sentinel).
2. The evaluation order is a decision table: every verdict that needs no ruff runs before provisioning, a deleted baseline or deleted config cannot read as "not adopted", and the Soleur self-skip keys on the running script's identity, not on a repo file a PR author controls.
3. Measured ruff 0.16.10 facts are folded in: `--no-fix` alone rewrites the tree under `fix-only = true` (add `--no-fix-only`), `build/` is not default-excluded, the no-config default is a ~410-rule set (so user mode stays gated on a detected root config), nested configs apply once `--config` is dropped.
4. The SKILL.md pointers carry the safety wording (never a repo-local copy, never `--update` unprompted, relay not-adopted and un-adoption to the user) at measured byte costs: `work` +245 B of 265 B headroom, `review` -5 B.
5. Architecture record corrected: the `platform.plugin` description in `model.c4` is edited (the earlier "No C4 impact" was wrong), and ADR-290's now-conditional Decision sentences are edited, not only appended to.

### New Considerations Discovered

- A single `classify_user` function must serve both `auto` and `user-ruff --check`, or the two disagree on the same tree.
- `render_baseline` hardcodes Soleur text (PR3a, #10331, Drawdown) and the committed user header must carry no absolute path.
- Plugin tree is vendored into the production image and `CLAUDE_PLUGIN_ROOT` is set for the hosted agent's bash (`apps/web-platform/server/agent-env.ts`, `apps/web-platform/Dockerfile`): the layer-7 citation needs a hosted-path paragraph.
- Under `CI` an unresolvable base is exit 2, which the skills treat as non-blocking, so the shrink-only guard is dark in cloud runs; documented as a residual.

## Overview

Slice 2 (PR3b) of the code-quality arc. Slice 1 (silent and catch-all handler restructure, ruff baseline 62 to 44) is merged and is not redone. The repository's own shrink-only ratchets (`scripts/lint-ratchet.py`, ADR-290) give Soleur a deterministic lint signal. This slice ships the same engine to plugin users: the `work` and `review` skills detect whether the user's repository has a Python (ruff) configuration, run the hash-pinned ruff against it, and ratchet the findings against a baseline that the user opted into and committed. User mode is Python-only in this slice (JS/TS user support is deferred, see Deferrals). The two carry-in residuals of #10507 (ruff-cache recovery hint, eslint per-extension test not run in CI) ride along because they live in the file this slice moves.

All technical forks were ruled by the CTO agent on 2026-10-18, in three passes (the second after the plan-review seats dissented, the third after the deepen-plan agents reported); every ruling is recorded in `knowledge-base/project/specs/feat-one-shot-10331-plugin-detect-and-run/decision-challenges.md`, and where a later row conflicts with an earlier one the later row binds. No technical question goes to the operator.

## Research Reconciliation: Spec vs. Codebase

| Claim (brief, brainstorm, ADR) | Reality (verified 2026-10-18) | Plan response |
|---|---|---|
| Brainstorm FR4: run the user's linter "on changed files only, report the changed-line delta" | The ratchet's gate is baseline-equals-census over the whole tree (ADR-290 Decision); a changed-file delta cannot express stale entries or totality | Whole-tree `auto`; changed-files-only is cut (deferral) |
| Brainstorm: "no bundled linters, no imposed rule sets" vs brief: "hash-pinned ruff" | Both hold: the pinned wheel is the BINARY; the rule set is the user's | User config always wins, no Soleur default rule set, pinned ruff wheel reused |
| Brainstorm FR4 says "detect the project's eslint/ruff config" | The existing eslint scope is Soleur-specific (test dirs, a pinned Soleur config); user eslint would be a new engine plus an arbitrary-code-execution surface | User mode is ruff-only; Soleur's own `eslint-test-dirs` scope and the #10507 vitest carry-in are untouched |
| work/SKILL.md Phase 3 says "Use linting-agent before pushing" | `grep -r linting-agent plugins/soleur` hits only `work/SKILL.md` and `work/references/key-principles.md`; no agent or skill by that name exists | The stale comment line is replaced by the real call; the `key-principles.md` checkbox is reworded (references/ are not byte-capped) |
| ADR-290 residual 7: the per-extension eslint test "runs only locally" | Confirmed from CI: run 39150560896 (PR #10503), job `test-webplat (2/2)` runs `test/eslint-test-dirs-ratchet.test.ts` (1 test, passes, ~5.7 s) and `(1/2)` runs `test/eslint-config.test.ts`; that vitest arm only spawns the live `eslint-test-dirs --check`. `TestEslintConfigBehaviour` (`tests/scripts/test_lint_ratchet.py`, `skipUnless` node_modules) runs in neither (`test-scripts` has no `npm ci`) | Second `it` in the vitest file runs that class and asserts ran-not-skipped |
| "Plugin scripts under plugins/soleur/scripts need a sibling test" | No such requirement; `SUITE_GLOBS` in `scripts/test-all.sh` deliberately excludes `plugins/soleur/skills/*/scripts/*.test.sh`; the whole plugin tree is delivered (`plugins/soleur/AGENTS.md` Manifest versioning) | Tests stay in `tests/scripts/test_lint_ratchet.py` (no new test file, no new registration) |
| Lifecycle SKILL.md byte ceilings | `work`: ceiling 359189, size 358924 (headroom 265 B). `review`: ceiling 475921, size 475873 (headroom 48 B). Measured with `wc -c` and `plugins/soleur/test/skill-body-budget.json`; `python3 scripts/lint-skill-body-budget.py --base origin/main` is green today | Pointer edits with trims (below); `skill-body-budget.json` is not touched |
| `lefthook.yml:239` and `scripts/test-all.sh:5150` call `lint-ratchet.py ruff --check` | Confirmed (also `argparse choices=sorted(SCOPES)` in `main()`); those names mean the Soleur scopes | User scopes get distinct CLI names (`user-ruff`, `auto`); Soleur names keep their meaning |
| "Ruff with no config uses E4/E7/E9/F" (common knowledge) | Measured with the pinned 0.16.10: no config means a ~410-rule default set (ASYNC, B, BLE, D, S, SIM, UP and more) | User mode is adoption-gated on a detected root config; a repo without one is "no linter configured", never scanned |
| "`build/` is a default ruff exclude" (first CTO pass) | Measured: `dist/`, `venv/`, `.venv/`, `node_modules/`, `site-packages/`, `__pypackages__/` are excluded by default; `build/` is not | The user-mode totality design never relies on a hardcoded exclude list |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10331 OPEN (tracker), #10507 OPEN (both residuals as stated), #10433 OPEN (drawdown). ADR-290 "PR3b contract" read in full: entry format, exit codes, the scope-config dict (`name`, `baseline`, `floor`, `run`, `remedy`, `drawdown`, optional `script`, `recovery_cmd`) and the list of module constants to re-point match the script on `origin/main` (`REPO_ROOT`, `RUFF_REQUIREMENTS`, `SCRIPT_REL`, `ESLINT_CONFIG`, `ESLINT_BIN`, `EXCLUDED_DIRS`, `DRAWDOWN`, `--config ruff.toml` in `tool_argv` and `show_files_argv`). ADR corpus grepped for the mechanism nouns (ratchet, baseline, detect-and-run): no ADR rejects user-mode detect-and-run; ADR-290 reserves it. No cited artifact was stale.

**Property List (Phase 0.6b).**

1. A user who opted in gets the same census-equals-baseline, shrink-only guarantee on their own Python lint findings that Soleur has.
2. A user who did not opt in sees no install, no file written, no behaviour change beyond one informational line.
3. The tool never silently reports green on a scan that failed or whose baseline or config was removed (the exit-code contract is preserved).
4. The user's own ruff configuration, not a Soleur rule set, defines a finding.
5. `work` and `review` invoke it without exceeding the lifecycle SKILL.md byte ceilings.
6. A corrupt ruff cache and the never-run eslint config test stop being silent gaps (#10507).

**Cut List (Phase 0.6b).** Each mechanism the brief, brainstorm or first-draft plan named, with the property it buys and what already covers it:

- Changed-files-only delta (brainstorm FR4): buys nothing property 1 needs; whole-tree census equality is the ADR-290 gate. Cut.
- Bundled Soleur default rule set for user repos: property 4 forbids it. Cut.
- Separate `detect-and-run` wrapper script: the engine already has the scope machinery; an `auto` CLI scope buys the same. Cut.
- A new `references/*.md` doc: the docstring, printed remedies and the ADR-290 addendum carry the docs, and a reference needs link bytes in a capped SKILL.md. Cut.
- User-mode eslint, `--no-exec`, eslint half of the fingerprint (first-draft plan): a new engine and the only arbitrary-code-execution surface, with no demand evidence. Cut.
- `--rebaseline` flag: the same lever as plain `--update` gated on the fingerprint. Cut.
- `--root` flag and the committed fixture repo: `--root` existed only for the fixture and caused a git path-base bug. Cut.
- win32 `Skip`, C4 component, learning edit, nested-config listing: no ask requires them. Cut.
- Telemetry from customer machines, exit code 3, kill-switch flag, monorepo and workspace support, a post-run tree-unchanged assertion, an `extend` realpath scan: cut or documented as residual; tracked in the deferral issue or the ADR amendment.

**Cost or performance claim (Phase 0.6c).** No cost saving justifies this plan. The only cost claim is "a repo that did not opt in pays nothing": every decision that needs no ruff runs before provisioning, verified by the discoverability wrapper below (no network, under 15 s) and by a test row that asserts pip is never invoked in the not-adopted state.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md`: totality per tool, pin the whole config, fail-closed `--update`, registrations pinned.
- `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`: keep identity keys, compare to the merge base, not the `origin/main` tip.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: budget the SKILL.md prose as a delta first (done below); the trims remove provenance and a parenthetical aside, not a condition.
- `2026-09-25-an-env-scoped-skipif-lets-ci-go-green-with-the-check-dark.md` and `2026-10-09-an-rc0-verdict-is-not-proof-the-suite-ran-vacuous-green.md`: the CI wiring must assert the class RAN and was not skipped.
- `2026-02-22-shell-expansion-codebase-wide-fix.md`: repo-root-relative paths do not resolve in user repos; the skills use `${CLAUDE_PLUGIN_ROOT}` and the script resolves its own location (`Path(__file__)`).
- `2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md`: run the orphan census after the change (`scripts/lint-orphan-test-suites.sh`).
- `2026-04-19-enoent-on-optional-mount-should-not-alarm.md`: an expected degraded state on a customer machine (no linter, no baseline, no network) is a documented skip, not an error.

**Measured ruff 0.16.10 behaviour** (general-purpose agent, pinned binary from the existing cache, temp repos; `--no-cache --no-fix --force-exclude --output-format json`, cwd at repo root, no `--config`):

- Config discovery honours `ruff.toml`, `.ruff.toml` and `pyproject.toml` with `[tool.ruff*]`; with several at one level `.ruff.toml` won. A `pyproject.toml` without `[tool.ruff]` falls back to the ~410-rule default.
- Nested configs apply per file and replace (not merge with) the root config unless they `extend`; one invalid nested config exits 2 for the whole run. `--config ruff.toml` pins one config for every file and ignores nested ones, so dropping it gives up nothing the user did not choose.
- `--force-exclude` drops tracked `dist/`, `venv/`, `.venv/`, `node_modules/`, `site-packages/`, `__pypackages__/`; `build/` is listed. `--show-files` prints absolute paths (`_relative()` handles that).
- `required-version`, unknown rule selectors, unknown keys and invalid TOML all exit 2 with the cause on stderr's first lines.
- `fix = true` and `unsafe-fixes = true` are overridden by `--no-fix`; `fix-only = true` is NOT (the tree was rewritten, findings hidden). `--no-fix-only` restores safety.
- `extend` honours absolute and outside-the-repo paths and symlinked configs; a user-level `~/.config/ruff` applies only when there is no project config; `--isolated` ignores all config (cannot combine with `--config`).
- A syntax error is reported with code `"invalid-syntax"` (not null), `url` null, rc 1; unreadable or non-UTF-8 files print `warning: Failed to lint ...` on stderr, so the existing `Failed to` stderr scan is necessary.

**Repo findings** (repo research): `plugins/soleur/scripts/` and `plugins/soleur/skills/*/scripts/` both ship; callers use `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>"`; precedent for a tool bootstrap in review is `skills/review/scripts/ensure-semgrep.sh`; default-branch fallback precedent is `skills/constraint-scaffold/scripts/constraint-scaffold.sh` `resolve_base_ref`; `.soleur/` is the repo's gitignored-ephemeral directory (written by `scripts/emit-decision.sh` with a `.gitignore` of `*`), which is why the user baseline lives elsewhere; `.github/` has no reference to `ruff-requirements` or `lint-ratchet`; the `test-scripts` shard uses stock `python3` (3.12) and has no `npm ci`.

**Functional overlap (Phase 1.5b).** Registry check found no verified equivalent combining ruff detection with a path/rule/line-hash shrink-only baseline. Closest: `ever-better` (isamu, 27 stars, github.com/isamu/ever-better; installs lint tooling and freezes a ceiling; eslint/TypeScript focused; its baseline keying and ruff support were not verified). Weaker: `holistic-linting`, `code-quality-plugin`, `bully`. Decision: proceed; the engine already exists and is tested, and adopting an external one would add a dependency and lose the keyed identity guarantee. Evaluating `ever-better` is a deferral item.

**Community discovery (Phase 1.5).** Stack is Python, bash and Markdown, covered by built-in agents; skipped.

**External research (Phase 1.6).** Skipped as a web search: strong local context, and the one external tool behaviour that matters (ruff) was measured empirically above. CLI-verification gate: every ruff flag reused (`check --output-format json --no-cache --no-fix --force-exclude --show-files`) is already in `tool_argv`/`show_files_argv` and pinned by tests (real captured output in `tests/scripts/fixtures/lint-ratchet/`); the NEW argv shapes (no `--config`, no `--ignore-noqa`, plus `--no-fix-only`) were exercised against the pinned binary by the measurement above, and work task 0.2 repeats the check and pastes the verified lines into the PR body.

## Problem Statement / Motivation

Most findings GitHub Code Quality reported on Soleur are habits of agent-written code (unclosed files, empty handlers, unused imports). The same habits appear in Soleur users' repositories, and Soleur's own pipeline should catch them deterministically instead of leaving them in a GitHub tab. Slice 1 made Soleur's own tree clean-or-baselined; the repository ratchet cannot reach a user's repo because the engine, its pinned ruff and its configs are repo-local. The operator chose to build this slice despite the CPO finding no demand evidence, so it stays small: opt-in, Python-only, no bundled rule set, almost no new SKILL.md weight.

## Proposed Solution

Ruled by CTO agent, 2026-10-18 (three passes; later rows amend earlier ones; full text in `decision-challenges.md`):

1. **Distribution and roots.** `git mv scripts/lint-ratchet.py plugins/soleur/scripts/lint-ratchet.py` and `git mv scripts/ruff-requirements.txt plugins/soleur/scripts/ruff-requirements.txt` (bytes unchanged, so existing ruff caches stay valid). The Soleur scopes stay in the same file as a labelled "Soleur block"; no library/client split (the suite patches module attributes `lr.ensure_ruff`, `lr._git`, `lr.tracked_files`, `lr.REPO_ROOT`, `lr.build_config`). No shim at the old path. The Soleur scopes keep `REPO_ROOT` derived from the script location (`parents[3]`, which is the repo root after the move; assert `SCRIPT_REL` exists under it, else exit 2), so running the plugin's script from another git repository never runs the Soleur scopes against that repo. Only the user scopes use `resolve_root()`: `git rev-parse --show-toplevel` from the cwd (no `--root` flag; every git call uses the toplevel, so cwd-relative and toplevel-relative paths cannot mix). Pins become script-relative (`Path(__file__).resolve().parent`). `SCRIPT_REL` becomes `plugins/soleur/scripts/lint-ratchet.py`. The Soleur baselines `scripts/lint-ratchet-{ruff,eslint-test-dirs}.baseline.txt`, `ruff.toml` and `apps/web-platform/eslint.test-dirs.config.mjs` stay where they are (moving a baseline in the same diff as the script trips ADR-290 residual 3 and would exit 2 in CI).
2. **Scope names and CLI.** User scopes are not in the `SCOPES` dict, so the Soleur pins stay untouched; `ruff` and `eslint-test-dirs` keep their Soleur meaning everywhere (lefthook, `test-all.sh`, the vitest arm). Two new CLI scope names: `user-ruff` (`--check`, `--update`, `--list`) and `auto` (detects, then delegates to `check` for `user-ruff`). `argparse choices` becomes `sorted(SCOPES) + ["user-ruff", "auto"]`; dispatch happens before `build_config` (which indexes `SCOPES` and would raise a bare `KeyError`, exit 1, for a user name) and root resolution sits inside the `try`; `auto` accepts only `--check` and `--base`, anything else goes to `parser.error` (exit 2). Nothing unexpected may exit 1.
3. **One decision function.** A single pure `classify_user(root, base, env)` returns the user-mode state (NOT_GIT, NO_LINTER, NOT_ADOPTED, BASELINE_WITHOUT_CONFIG, DELETED, UNTRACKED_BASELINE, ADOPTED) and is called by both `auto` and the preamble of `user-ruff --check`; `auto` only maps the state to a line and exit code, then delegates to `check` (a parity test asserts `auto` and `user-ruff --check` agree on every state). The scope config gains explicit keys instead of Soleur-only hardcoding: `waiver_note`, `strict_totality`, `ignore_noqa`, `header_tracker`, `floor` 0, `ladder`, `remedy`; a test pins that the Soleur scopes' printed output is byte-identical before and after, and another that `user-ruff` produces the same verdict with `SCOPES`, `DRAWDOWN` and `ESLINT_*` patched to empty or poisoned values.
4. **Tool config (user mode, ruff only).** The user's own config always wins; Soleur applies no rule set. `user-ruff` is active only when a tracked root `ruff.toml`, `.ruff.toml`, or a `pyproject.toml` with a line matching `^\[tool\.ruff` exists (line grep anchored at line start, no `tomllib`: py3.9-safe; a commented `# [tool.ruff]` does not match; detection is root-level and tracked-only, message `no tracked ruff config at <root>; nested configs unsupported`). Ruff runs with NO `--config` (nested configs then apply per file) and with `--no-fix --no-fix-only`, in the pinned wheel. The user's waivers (`# noqa`) are honoured (no `--ignore-noqa`); the waiver-proof flag stays on for the Soleur scopes only, via the scope key. Safety around the user's config: `lstat` every root config candidate and refuse a symlink, a non-regular file or a file over 1 MiB with a fixed exit-2 message; limit raw ruff stderr echoed in user mode to its first line, passed through `_clean`; scrub `RUFF_*` and `PYTHON*` from the ruff environment; ignore a relative `XDG_CACHE_HOME` and fall back to `~/.cache`; run git with `-c core.fsmonitor=false`. A content-caused exit 2 (malformed baseline, invalid config, symlinked config, bad path) carries the stable prefix `lint-ratchet(user-ruff): REPO-CONTENT:` so `review` treats it as a finding rather than a clean pass; when ruff exits 2 for a config reason one fixed line is appended: `pinned ruff is <pin>; a config with required-version or rules newer than the pin fails here` (only when stderr matches a config-error pattern, otherwise print the first stderr line).
5. **User-mode totality (exactly three checks).** (a) A `Failed to` or IO error on stderr, a ruff exit code outside {0, 1}, or an unparsable JSON result is exit 2. (b) `--show-files` supplies only the "(<m> files scanned)" count and the zero-file case; there is no tracked-versus-listed comparison and no `EXCLUDED_DIRS` check (the user's own `extend-exclude` and ruff's default excludes would otherwise be a false red forever). (c) No numeric floor: zero tracked `.py` files, or zero files in ruff's own listing, is exit 0 with a `WARN` hint when the baseline has zero entries (never `OK`), and the ordinary STALE rule gives exit 1 when the baseline has entries. Accepted residual: excluding everything with an empty baseline passes; that edit changes the config hash and takes the fingerprint path (human review). `invalid-syntax` findings are ordinary findings.
6. **Baseline lifecycle and decision table.** Adoption is opt-in, no auto-baselining. Location `.lint-ratchet/ruff.baseline.txt` at the repository root, tracked in git (not under `.soleur/`, which is gitignored-ephemeral by convention; a root `.soleur/` ignore cannot be undone with a negation). Order of decisions (every row that needs no ruff runs before `ensure_ruff`): (1) resolve the toplevel; not a repository is `Skip` only when git's stderr says so (other git errors are exit 2; a bare repo prints a run-from-a-worktree message); (2) **Soleur self-skip**: when `realpath(__file__)` equals `realpath(<toplevel>/plugins/soleur/scripts/lint-ratchet.py)`, print `Soleur repository: scopes run via lefthook and CI; nothing to ratchet here` and exit 0 (keyed on the running script's identity, never on a repo file a PR could plant; accepted cost: a Soleur session running a cached plugin copy sees `not adopted`); (3) detect config; (4) read the baseline in the working tree, at HEAD and at the merge base; (5) decide: baseline present anywhere but no config detected is exit 1 `baseline exists but no ruff config detected`; baseline at HEAD, missing in the working tree, base unresolvable is exit 2 under `CI` and a warning locally, never `not adopted`; baseline at the merge base and missing from the working tree is exit 1 `baseline deleted since the merge base: restore it, or un-adopt on purpose with git rm -r .lint-ratchet` (the user confirms un-adoption in `work`; `review` files it as a finding); config present and no baseline anywhere is exit 0 `not adopted. Ask the user whether to adopt; if yes, run: <cmd>` plus, when the base is unresolvable, the stderr line `base unresolvable: baseline-deletion check not performed`; an untracked baseline is read from the working tree with the note `git add .lint-ratchet`; no config and no baseline is exit 0 `lint-ratchet: no linter configured (no tracked ruff config at <root>; nested configs unsupported); nothing to ratchet`. `--update` with no baseline at HEAD writes the census, `--check` never writes, and `--update` prints the written path plus "commit it" and one line when `git check-ignore -q` matches the path (it never edits the user's `.gitignore`). **Merge-base ladder**, each rung verified with `rev-parse --verify --end-of-options <ref>^{commit}`: `--base <ref>`, `origin/HEAD`, `origin/main`, `origin/master`, `upstream/main`, `upstream/master`, local `main`, local `master`, then the existing skip-with-warning (exit 0 locally, exit 2 under `CI`); a local-branch rung prints `WARN: using local <branch> as merge base`; a shallow clone prints `shallow clone: fetch more history (fetch-depth: 0) so the shrink-only comparison can run`. In user mode `drawdown` and `script` are None. Output lines are never `OK` when a guard did not run: unresolvable base and zero-file paths print `SKIP` or `WARN`, and a SKIP line says `no scan was performed`. The ladder is a user-mode config key; Soleur keeps `origin/main`.
7. **Toolchain fingerprint (ruff only, no flag).** The baseline header records `# toolchain: ruff <pin> ; config sha256:<16hex>` where the hash covers all of `ruff.toml` and `.ruff.toml` plus only the `[tool.ruff...]` tables of `pyproject.toml` (line scan from `^\[tool\.ruff` to the next non-ruff `^\[`, no `tomllib`). Line anchors stay 12 hex in both modes (`ENTRY_RE` and the Soleur baselines are untouched). Rules: the merge-base growth comparison is skipped only when the merge-base baseline's header differs from the HEAD baseline's header AND the HEAD header equals the live fingerprint; a missing header means unknown (no exemption); when skipped, `check` exits 0 but prints the non-green sentinel `lint-ratchet(user-ruff): CONFIG CHANGED vs merge base: shrink-only not enforced; review the config diff` (never plain `OK`); plain `--update` may grow the baseline only when the HEAD header differs from the live fingerprint (otherwise it refuses real growth exactly as today); a stale header with an equal census exits 0 with `fingerprint stale: run --update to refresh`; when the live ruff pin is older than the stored pin the line is `plugin older than the baseline's ruff <pin>: update the plugin` and `--update` is not suggested. The committed header is machine-independent: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" user-ruff --update`, no absolute path, no `#10331` text, no Drawdown line; absolute `shlex.quote`d paths appear only in runtime hints, with a conflict-resolution hint that names the concrete git command. Accepted residual, stated in the ADR amendment and at the `--update` print site: an agent can edit the config, run `--update`, and go green; the control is PR review, made visible by the sentinel.
8. **Invocation (exact wording, measured).** No wrapper; the anchor stays `lint-ratchet.py" auto`, and plain `auto` means check.
   - `work`, Phase 3 step 1: replace the stale `# Use linting-agent before pushing to origin` comment line (48 B including its three-space indent and newline) with the following line, which keeps the same three-space indent (293 B including indent and newline): `[ -n "$CLAUDE_PLUGIN_ROOT" ] && python3 "$CLAUDE_PLUGIN_ROOT/scripts/lint-ratchet.py" auto  # never a repo-local copy; NEW/STALE/exit 1 blocks handoff (baseline deleted: relay, ship only if user confirms un-adoption); not adopted: relay, never --update unprompted; skip/2: report, continue`. Net +245 B of the 265 B headroom (20 B spare). Exit 1 blocks handoff to Phase 4 (acceptable: the user opted in by committing a baseline); exit 2 and Skip get one in-session sentence and work continues.
   - `review`: one pointer between the `**Bootstrap (mandatory before spawning the agent):**` paragraph and the next `**What this agent checks:**` heading after it, 213 B including the trailing blank line: ``**Lint ratchet (user repos):** `[ -n "$CLAUDE_PLUGIN_ROOT" ] && python3 "$CLAUDE_PLUGIN_ROOT/scripts/lint-ratchet.py" auto`; exit 1, CONFIG CHANGED or REPO-CONTENT = one P2; else a note; never a repo-local copy.`` Ruff config is declarative, so no `--no-exec` is needed. Trims in the same file, both in the Bash-only bullet: the provenance sentence that begins "See", names the learning `2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` and ends "the bench-pattern session that surfaced this." (149 B), and the parenthetical `(parses ~100% of lines but matches 0 rules — vacuous "0 findings")` (69 B); the `**Why:** PR #4045` clause that carries the condition stays. Net -5 B against the 48 B headroom. `git grep` shows no other reference to that learning from `plugins`, `scripts`, `tests` or `.github`.
   - Printed output is data: the pointers and the printed lines treat baseline contents and ruff messages as untrusted text (the `REPO-CONTENT` prefix and `_clean` carry it).
   - Cloud mode: the `[ -n "$CLAUDE_PLUGIN_ROOT" ] &&` guard skips quietly when the variable is unset (an agent must never go looking for and run a repo-local `lint-ratchet.py`).
9. **Byte budget.** `skill-body-budget.json` untouched. Run `python3 scripts/lint-skill-body-budget.py --base origin/main` before every push; do not compress any condition-bearing sentence to fit.
10. **Carry-ins (#10507).** (1) In `ensure_ruff`, after the install/rename block, if `exe` still does not exist raise `InfraError("ruff cache {final} exists without bin/ruff; delete it and retry: rm -rf {final}")`, and append the same `rm -rf {final}` hint to the version-probe failure message; hint only, no auto-delete; one test builds `final` without `bin/ruff` and asserts the message names the directory; remove ADR-290 residual 7 once both land. (2) Add a second `it` to `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` that spawns `python3 -m unittest tests.scripts.test_lint_ratchet.TestEslintConfigBehaviour -v`, asserts exit 0, `Ran (\d+) tests?` with N at least the class's pinned case count (1 today; derive it from the class, do not hard-code a second copy) and no `skipped` in the unittest footer; porting to vitest is rejected (it would duplicate the oracle in a second language). The `test-webplat (2/2)` shard already has `node_modules`.
11. **Robustness.** A `sys.version_info` guard at the top of the script, written in syntax that old Pythons can parse, maps to exit 2 `lint-ratchet: needs python>=3.9` (pinned by an `ast.parse(..., feature_version=(3, 6))` test only if the script already passes it; otherwise documented as best-effort). `python3: command not found` and native Windows are documented in the ADR amendment (Windows has no `python3` and no `os.getuid`): they surface as the skill's own tool error and the pointer says "skip/2: report, continue".

## Technical Considerations

- **Moving the script.** The sweep list is: `lefthook.yml` (`ruff-ratchet` and `eslint-test-dirs-ratchet` commands, and both glob lists so they name the new script and requirements path), `ruff.toml` header comment, `scripts/test-all.sh` (comment near line 3806; the two `run_suite` lines keep their labels, the command of `scripts/lint-ratchet-ruff-live` changes path), `scripts/lib/test-affected-paths.sh` (verify only; labels unchanged), `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (labels unchanged, so no edit), `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts`, `apps/web-platform/eslint.test-dirs.config.mjs` header comment (its sha256 is pinned in the test: update the digest in the same commit), both baseline headers (regenerate with `--update`, header text only), `tests/scripts/test_lint_ratchet.py`, ADR-290. `git grep -n 'ruff-requirements\|lint-ratchet' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` is the closing check; `.github/` has no reference (verified).
- **`tests/scripts/test_lint_ratchet.py` sweep (verified against the file).** `SCRIPT` (line 40) and `SCRIPT_REL` pin (line 1141); the ruff-requirements reads (lines 1247, 1252, 1323, 1334); the `run_suite` regex pin (1175-1179); the lefthook block pins and the expected glob list (1187-1204); `TestRegistration.test_the_vitest_arm_is_registered_as_repo_wide` pins the string `"scripts/lint-ratchet.py", "eslint-test-dirs", "--check"` in the vitest file (line 1220), so it follows the new path; the Soleur scopes keep `REPO_ROOT` so the `lr.REPO_ROOT` patch at line 1496 stays valid, and user-mode tests patch `resolve_root`; the cache-directory assertion (line 1354); `MIN_CASES = 60` (line 42) and the class set in `test_every_guard_class_is_loaded` (line 1614) grow with the new classes; `test_baseline_paths_follow_the_lint_convention` (line 1157) assumes `scripts/lint-` and is scoped to the Soleur scopes.
- **Soleur-only text in shared code.** `check()` prints "inline waivers (# noqa, eslint-disable) are NOT honoured here" and uses `REMEDY_RUFF`; `render_baseline()` writes "PR3a of #10331" and an unconditional "Drawdown tracking" line; `tool_argv()`/`show_files_argv()` hardcode `--config ruff.toml --ignore-noqa`; `run_ruff()` carries the `EXCLUDED_DIRS` totality and raises `Vacuous` on zero tracked files. All of these become scope-dict-driven (item 3); the Soleur output stays byte-identical.
- **Lefthook globs.** After the move the ruff entry's glob list must name the new requirements path (pin test `test_lefthook_ruff_globs_are_exactly_the_scope_plus_the_inputs` otherwise fails) and the eslint entry's list names the new script path.
- **Ruff scans the moved script.** `plugins/soleur/scripts/lint-ratchet.py` is a tracked `*.py`; the ruff baseline has no entry for it (the three `lint-ratchet` matches in the baseline are header lines), so it must stay finding-free.
- **ADR-290 residual 3 window.** `config["script"]` changes to the plugin path; a PR in flight whose merge base predates the move sees `baseline_at(script)` as None, so the baseline-moved guard does not fire for that window. Recorded in the ADR amendment.
- **Hyphenated module.** The test loads the script with `importlib.util.spec_from_file_location`; keep that.
- **Portability.** The script is stdlib-only and py3.9-safe; no GNU-only external binaries beyond `git`; subprocess timeouts instead of `timeout`.
- **Supply chain.** The ruff wheel install keeps `pip --isolated --require-hashes --only-binary=:all:`, scrubbed `PIP_*`/`PYTHON*`, private `0700` cache; a hash mismatch is exit 2 everywhere; an unreachable index is a loud `SKIP` locally (`SKIP lint-ratchet(user-ruff): no scan was performed (ruff unavailable); no ratchet protection this run`) and exit 2 under `CI`. A test row mixes a hash mismatch with a network phrase to prove integrity is checked first.
- **Tests.** Stay in `tests/scripts/test_lint_ratchet.py` (a new file would need four registrations). The discoverability wrapper is not a `*.test.sh`, so the suite globs and the orphan census do not pick it up.

## Open Code-Review Overlap

Queried 96 open `code-review` issues against the planned files. Matches: `scripts/test-all.sh` is named by #8659 (test-helpers composed EXIT trap leak) and #7942 (two mutation batteries run in no gate). **Acknowledge** both: different concern (the file is edited only for a comment and path strings); they remain open. No match for `scripts/lint-ratchet.py`, `tests/scripts/test_lint_ratchet.py`, the work/review SKILL.md files, `lefthook.yml`, the vitest arm, or ADR-290.

## Files to Edit

- `scripts/lint-ratchet.py` -> moved to `plugins/soleur/scripts/lint-ratchet.py` (see Files to Create), then edited
- `tests/scripts/test_lint_ratchet.py` (new classes, re-points, mutation rows; see the sweep above)
- `plugins/soleur/skills/work/SKILL.md` (Phase 3 step 1: replace the `linting-agent` comment line; net +245 B)
- `plugins/soleur/skills/review/SKILL.md` (lint-ratchet pointer; trim two sentences in the Bash-only bullet; net -5 B)
- `plugins/soleur/skills/work/references/key-principles.md` (the `Linting passes (use linting-agent)` checkbox; not byte-capped)
- `lefthook.yml`, `ruff.toml` (header comment), `scripts/test-all.sh` (comment and command path), `scripts/lib/test-affected-paths.sh` (verify only)
- `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` (second `it`; new script path), `apps/web-platform/eslint.test-dirs.config.mjs` (header comment; update the pinned digest in the test)
- `scripts/lint-ratchet-ruff.baseline.txt`, `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (regenerated headers only; entries identical)
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md` (edit the now-conditional Decision and Consequences sentences, dated Amendment 1, delete residual 7 once delivered)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (one sentence in the `platform.plugin` description; no new element) and the regenerated `model.likec4.json`

## Files to Create

- `plugins/soleur/scripts/lint-ratchet.py` (via `git mv`; adds `resolve_root`, `classify_user`, `user-ruff` and `auto` scopes, detection, fingerprint, deleted-baseline rule, ruff-cache hint, version guard)
- `plugins/soleur/scripts/ruff-requirements.txt` (via `git mv`; bytes unchanged)
- `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` (discoverability wrapper, two stages; synthetic content only, per `cq-test-fixtures-synthesized-only`; not named `*.test.sh`)
- `knowledge-base/project/specs/feat-one-shot-10331-plugin-detect-and-run/{tasks.md,decision-challenges.md}`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "PR3b, plugin detect-and-run, so users of the Soleur plugin get the same deterministic lint signal on their own repositories" | Proposed Solution 1-8 | mapped |
| 2 | "READ ADR-290's \"PR3b contract\" first and reuse scripts/lint-ratchet.py's contract: exit 0/1/2 semantics, scan totality, the hash-pinned ruff" | Proposed Solution 1, 4, 5, 6; Guard Contract | mapped |
| 3 | "The change edits the work and review SKILL.md files (detect which linters apply to the user's repo, run them, ratchet against a baseline)" | Proposed Solution 8; Files to Edit | mapped |
| 4 | "the CTO agent (soleur:engineering:cto) rules every technical fork (distribution of the script to plugin users, baseline location in a user repo, detection rules, how work/review invoke it, byte-budget impact on the lifecycle SKILL.md ceilings)" | decision-challenges.md rows 1-32 | mapped |
| 5 | "a corrupt ruff cache gives no recovery hint, add a one-line hint naming the cache directory" | Proposed Solution 10(1) | mapped |
| 6 | "the eslint per-extension test only runs off-CI, wire it into a CI-run suite or confirm the webplat shard already runs the eslint vitest guard (inspect the CI logs; this was never separately inspected)" | Research Reconciliation row 6; Proposed Solution 10(2) | mapped |
| 7 | "Close #10507 in this PR if both are delivered." | frontmatter `closes: [10507]`; PR body reminder | mapped |
| 8 | "the PR body must say \"Ref #10331\" and must not use any closing keyword for it" | PR body reminder (below) | mapped |
| 9 | "run soleur:ship and soleur:postmerge to completion" | downstream pipeline, not a plan item | descoped - justification: executed by the pipeline after this plan |
| 10 | "drawdown of the baselined findings tracked in open issue #10433, and the decision on whether per-PR GitHub Code Quality stays on" | Not in this slice | descoped - justification: the brief lists them as remaining after this slice |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Move the engine into the plugin | "the CTO agent ... rules every technical fork (distribution of the script to plugin users" | asked |
| `auto` and `user-ruff` CLI scopes | "how work/review invoke it" | asked |
| Python-only user mode | "detect which linters apply to the user's repo" | asked (the brief names ruff's hash pin; JS/TS user support is a deferral) |
| Toolchain fingerprint | "ratchet against a baseline" | inferred - justification: with the user's own config as the rule set, a config or ruff-pin change moves the census; without it Soleur bumping the pin would wedge every opted-in user |
| Deleted-baseline and baseline-without-config rules | "same deterministic lint signal" | inferred - justification: judging adoption on the working tree alone lets a PR dodge the ratchet by deleting the file or the config |
| Soleur self-skip | "reuse scripts/lint-ratchet.py's contract" | inferred - justification: `auto` run in the Soleur repo would otherwise tell Soleur's own agents to adopt |
| `classify_user`, scope-dict keys, lstat/env/stderr hardening, `--no-fix-only` | "scan totality" | inferred - justification: deepen-plan review and the measured ruff facts (a user config can rewrite the tree under `fix-only`, read outside the repo, echo content) make these the minimum safe form of running a user-supplied config |
| Lefthook, ADR, test and C4-description re-points | "this slice moves and re-points" | asked |
| Discoverability wrapper | "reuse ... the hash-pinned ruff" | inferred - justification: the Observability gate needs one local command that proves the not-adopted and deleted-baseline arms without network |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur/scripts`, `plugins/soleur/skills`, `tests/scripts` with `scripts/` and `lefthook.yml`, `apps/web-platform/test` (plus KB docs and the C4 model)
- Planned files: about 22 | Estimated changed lines: about 750 (the script gains roughly 280 lines; tests about 350; the rest are path edits and docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The subsystem count meets the threshold nominally, but the roots are the engine, its callers and its registrations, which must move atomically (a script move split across PRs breaks `lefthook`, `test-all.sh` and the required `test` context in between); the estimate stays under the line threshold.

## User-Brand Impact

- **If this lands broken, the user experiences:** `work` refusing to hand off (exit 1) on a repo that opted in because of a mis-detected config or a deleted-baseline false positive, or a `.lint-ratchet/` directory written where they did not expect one; all require the user to have run `--update` themselves, and a not-adopted repo sees one informational line.
- **If this leaks, the user's workflow is exposed via:** the one-time pip install of a hash-pinned ruff wheel; no user data is read beyond file paths, rule ids and 12-hex line fingerprints, and no Soleur-side sink is added. User mode runs ruff only, so no repository-supplied JavaScript is executed; a malicious ruff config can only change which findings exist or point `extend` at a file (first stderr line only is echoed).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: the tool is opt-in, local, Python-only, never writes without an explicit `--update`, and executes no repository code; a one-user failure is a skipped or noisy lint line, not a data or money loss.

## Observability

Customer-machine surface (layer 7 of `hr-observability-layer-citation`: plugin code that executes on a customer's self-hosted CLI). No Soleur-side sink is added and no telemetry leaves a customer machine by decision (phoning home is a consent and legal matter, deferred to `soleur:legal:clo` only if ever proposed); every failure mode surfaces locally as a `lint-ratchet(<scope>): ...` stderr or stdout line plus an exit code that `work` and `review` relay in-session. Soleur's own CI runs the engine on every PR (`scripts/lint-ratchet-ruff-live`, the vitest arm), which is the fleet-side signal.

**Hosted path.** The plugin tree is vendored into the production image (`apps/web-platform/Dockerfile`) and `CLAUDE_PLUGIN_ROOT` is set for the hosted agent's bash (`apps/web-platform/server/agent-env.ts`), so `work` and `review` can run this script hosted too. The same lines land in the hosted agent's Bash tool result; a pip install inside the agent sandbox may fail, which surfaces as `SKIP` or exit 2 loudly; the script emits no `SOLEUR_*` marker, so the Bash marker extractor never fires; hosted-run failures are covered only by the transcript and, where applicable, the dispatch-level layers.

```yaml
liveness_signal:
  what: "cli-stdout-artifact: the line lint-ratchet(user-ruff): OK (<n> findings baselined, <m> files scanned) plus the committed .lint-ratchet/ruff.baseline.txt and its '# toolchain:' header; Soleur-side: the required test context"
  cadence: "per work Phase 3 run, per review run, per Soleur PR in CI"
  alert_target: "the invoking skill's in-session report; Soleur CI required check for the Soleur scopes"
  configured_in: "plugins/soleur/skills/work/SKILL.md (Phase 3 step 1), plugins/soleur/skills/review/SKILL.md (lint-ratchet pointer), scripts/test-all.sh (run_suite scripts/lint-ratchet-ruff-live)"
error_reporting:
  destination: "stdout/stderr of the script and the skill transcript; no Sentry (customer machine, no consent for outbound telemetry)"
  fail_loud: "exit 2 with a lint-ratchet(<scope>): line naming the fault and the recovery command (content-caused ones carry the REPO-CONTENT: prefix); exit 1 with NEW/STALE/baseline-deleted lines; SKIP/WARN lines for degraded paths, never OK"
failure_modes:
  - mode: "ruff cache directory exists without bin/ruff"
    detection: "cli-stdout-artifact: InfraError line naming the cache path and 'rm -rf <dir>' (new test row)"
    alert_route: "work/review in-session report"
  - mode: "ruff failed to lint a file, exited outside 0/1, or printed unparsable JSON"
    detection: "cli-stdout-artifact: totality check (a) exits 2 with the first ruff stderr line"
    alert_route: "work/review in-session report"
  - mode: "baseline deleted, config deleted, or baseline git-ignored so it never reaches the base branch"
    detection: "cli-stdout-artifact: exit 1 lines 'baseline deleted since the merge base' / 'baseline exists but no ruff config detected'; --update prints the git check-ignore line; durable artifact .lint-ratchet/ruff.baseline.txt at the merge base"
    alert_route: "the invoking skill's in-session report and the --update output"
  - mode: "scan did not run (Skip: ruff unavailable offline or on an unsupported platform, not a git repository)"
    detection: "cli-stdout-artifact: SKIP line saying no scan was performed; the stdout line is the whole signal and the skill relays it"
    alert_route: "work/review in-session report"
  - mode: "base unresolvable or shallow clone (shrink-only comparison not performed)"
    detection: "cli-stdout-artifact: SKIP/WARN line and the shallow-clone fetch hint; exit 2 under CI"
    alert_route: "work/review in-session report"
  - mode: "ruff config or pin changed since the merge base (growth comparison skipped)"
    detection: "cli-stdout-artifact: sentinel 'CONFIG CHANGED vs merge base: shrink-only not enforced' plus the '# toolchain:' header diff in the baseline"
    alert_route: "review files it as a P2"
  - mode: "wheel hash mismatch or a zero-file adopted repo"
    detection: "cli-stdout-artifact: exit 2 integrity line (hash mismatch is never a skip) / WARN zero-file line"
    alert_route: "work/review in-session report"
  - mode: "new or stale findings"
    detection: "cli-stdout-artifact: NEW/STALE lines with path:row, rule and the remedy; durable artifact is the committed baseline"
    alert_route: "work blocks handoff; review files one P2"
logs:
  where: "stdout/stderr of the invoking skill session"
  retention: "session transcript only"
discoverability_test:
  command: bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh
  expected_output: LINT_RATCHET_PROBE_OK
```

The wrapper `tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` resolves the engine path absolutely before it changes directory, runs every `git` call under `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE` with a pinned identity, makes a throwaway repo with `mktemp -d` and removes it with a `trap`, and has two stages that need no ruff and no network: stage 1 writes a `pyproject.toml` with a `[tool.ruff]` table and one `.py` file, runs `auto`, and asserts the WHOLE `not adopted` line; stage 2 commits a hand-written `.lint-ratchet/ruff.baseline.txt`, deletes it from the working tree, runs `auto --base HEAD`, and asserts the `baseline deleted since the merge base` exit-1 line. It prints the unique token `LINT_RATCHET_PROBE_OK` only when both assertions hold, otherwise exits 1. Both arms are decided before `ensure_ruff`, so the wrapper finishes in well under 15 s with no pip. Preflight Check 10 will SKIP this probe because the diff matches none of its sensitive paths, so the real wrapper output is recorded in the PR body. The command does not exist until the work phase creates it, so it cannot be run at plan time; work task 0.6 runs it once before the first commit and again before ship.

## Encryption Posture

```yaml
at_rest:
  - store: ".lint-ratchet/ruff.baseline.txt in the user's repository"
    mechanism: "the user's own repository storage and their git hosting at-rest controls; Soleur adds none"
    evidence: "the file holds only paths, rule ids and 12-hex line fingerprints plus a toolchain header (no source text, no secrets, no absolute paths); format pinned by ENTRY_RE in plugins/soleur/scripts/lint-ratchet.py"
    defends_against: "none claimed by Soleur"
    does_not_defend: "disclosure of file paths and rule ids to anyone with read access to the repository"
    disclosed_as: "ADR-290 amendment and the script docstring"
    live_verification: "tests/scripts/test_lint_ratchet.py asserts a rendered user baseline contains no source line text, no absolute path, no home directory and no issue number"
in_transit:
  - connection: "pip to https://pypi.org/simple for the pinned ruff wheel (first run only)"
    tls: "HTTPS to pypi.org via pip defaults"
    cert_verification: on
    does_not_defend: "a compromised PyPI account or CDN serving a wheel is caught only by the pinned sha256 for each of the 17 wheels (--require-hashes), not by TLS; a user behind a TLS-intercepting proxy trusts that proxy"
    disclosed_as: "ADR-290 Decision (hash-pinned ruff) and the amendment"
```

## Guard Contract

### Guard 1 - lint-ratchet user-mode scan (opt-in, totality, shrink-only)

**Property.** For a user repo that opted in, the check exits 0 only when the live census of the user's own ruff findings equals the committed baseline, has not grown since the merge base (unless the toolchain changed and the sentinel says so), the baseline and the ruff config have not been deleted since the merge base, and the scan did not fail; it never provisions ruff for a repo that did not opt in.

**Assembly.** The property quantifies over: every entry path into a verdict (`check`, `update`, `list_live`, and the `auto` dispatcher, which must not compute a verdict of its own: it maps the single `classify_user` result to a line and exit code, then delegates to `check` for `user-ruff`); both baseline readers (HEAD working tree and merge base via `baseline_at`) and the header reader that feeds the fingerprint rule; the three config-detection inputs (`ruff.toml`, `.ruff.toml`, a `pyproject.toml` `^\[tool\.ruff` line) and the `lstat` refusal of symlinked, non-regular or oversized candidates; the three totality checks of Proposed Solution 5; every code path that can decide the scope is NOT applicable or skipped (Soleur self-skip, no ruff config, not adopted, not a git repository, unresolvable base, ruff unavailable) — each must exit 0 only with its documented non-`OK` line, never a bare 0; and the provisioning chokepoint (`ensure_ruff`, reached from `run_ruff` only), which every decision that needs no ruff must precede. The chokepoints every verdict flows through are `classify_user()` for the state and `check()` for the census.

**Mutation matrix** (four rows, CTO D11/E12; each is derived from the design, not from the finished code):

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the adoption check so a not-adopted repo provisions ruff (also covers a dead `auto` dispatch: `auto` returns 0 on a repo with a ruff config and a baseline holding a stale entry) | RED (the not-adopted row asserts pip is never invoked and the whole line `not adopted. Ask the user whether to adopt; if yes, run: ...` is printed; the stale-entry row must exit 1, not 0) |
| 2 | Pass `--ignore-noqa` in user mode | RED (the waiver-honoured row: a finding with `# noqa` must not count; the Soleur waiver-ignored row still counts) |
| 3 | Break the fingerprint rule in either direction: let `--update` grow the baseline when the HEAD header equals the live fingerprint, or skip the merge-base growth comparison when the merge-base and HEAD headers are equal, or skip it when the HEAD header differs from the live fingerprint | RED (growth-refused row with equal fingerprints; header-edited-only row: a PR that edits only the HEAD header must still be growth-checked; fingerprint-differs row proves growth is exempt only when merge-base header differs from HEAD header and HEAD header equals live, and that the CONFIG CHANGED sentinel is printed) |
| 4 | Remove the deleted-baseline or baseline-without-config rule | RED (baseline at the merge base and missing at HEAD exits 1; baseline kept and config deleted exits 1; baseline at HEAD, missing in the working tree, base unresolvable exits 2 under CI and never prints `not adopted`) |

A swallowed `Skip` or `InfraError` in `auto` is covered as an ordinary unit row (an injected raising stub must yield a non-zero exit with a `lint-ratchet(` line), not a fifth mutation.

**Harness rows.**

- Suite edit that MUST redden: let `TestEslintConfigBehaviour` skip (or delete the `skipped` assertion) in the new vitest `it` and confirm the vitest test goes RED; delete the `work` or `review` anchor pin and confirm the anchor test goes RED; delete the Soleur byte-identical-output pin and confirm RED after a user-mode edit to a shared string.
- Must-PASS inputs that are not the canonical: a repo whose default branch is `master` with no `origin/main` and a ruff config in `.ruff.toml` (not `ruff.toml`); a `pyproject.toml` carrying `[tool.ruff.lint]` rather than `[tool.ruff]`; an adopted repo whose baseline is empty and whose tree is clean (OK with 0 findings and files scanned >= 1); a user repo containing a planted `scripts/lint-ratchet-ruff.baseline.txt` (must still be ratcheted, because the self-skip keys on the script's identity).

**Anchor.** The stored value is the baseline and its toolchain header. What outside the commit must move for a weakening to pass: the merge-base comparison reads the baseline at the merge base, so a diff that edits both the baseline and the code is caught by growth; the fingerprint exemption requires the MERGE-BASE header to differ from the HEAD header and the HEAD header to equal the live toolchain, so editing only the HEAD header buys nothing, and the exemption prints the `CONFIG CHANGED` sentinel that `review` raises as a P2. A diff that also edits the user's ruff config legitimately skips the growth comparison; that is an accepted residual (an agent can disable a rule, run `--update` and go green), the control is PR review, and it is stated in the ADR-290 amendment and at the `--update` print site. The amendment also names the tension with the self-certifying-header alternative ADR-290 rejected: here the header is a bounded, review-relayed exemption, not a trust root. Soleur's own scopes keep ADR-290's controls (pin tests, registration test).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-290 (no new ADR) via the `soleur:architecture` skill, as dated Amendment 1, and also edit the Decision and Consequences sentences that become conditional so they are scoped to the Soleur scopes: "per `(path, rule)` the baseline never holds more entries than at the merge base" (fingerprint exemption), "the scan must also be TOTAL" (user mode keeps three checks), "Counting is waiver-proof", and the Control paragraph (the pin tests do not cover a user's config). The amendment realizes the PR3b contract: script moved to `plugins/soleur/scripts/`; user mode is Python-only and honours the user's config and waivers; adoption is opt-in; baseline in `.lint-ratchet/`; the fingerprint rule with the sentinel; the deleted-baseline and baseline-without-config rules; the three-check totality; the script-identity self-skip; `SCRIPT_REL` change and why the Soleur baselines stayed put. Accepted residuals to list: config-edit-then-update, a stale header, `extend`/`exclude` and user-global config outside the fingerprint, the cwd-dependent root, the in-flight-PR window for residual 3, the CI-dark guard (exit 2 under `CI` is non-blocking in the skills), notebooks (`.ipynb` is outside the scan), the deletion dodge when the base is unresolvable, python3 and Windows availability, and the same-user trust in an existing cache `bin/ruff`. Update the "PR3b contract" paragraph from future to past tense, add the rejected alternatives to `## Alternatives Considered` (bundled default rule set, wrapper script, shim at the old path, library/client split, changed-files-only, user-mode eslint in this slice, a `--rebaseline` flag, a `--root` flag, a repo-file-keyed self-skip), cite ADR-178 and ADR-254 as precedents for shipped user-machine surfaces, add `amended:` to the frontmatter, and delete residual 7 once both carry-ins land. This is a task in Phase 5 of `tasks.md`, not a follow-up.

### C4 views

Edit, do not skip (CTO E11; the earlier "No C4 impact" was wrong). The `platform.plugin` description in `knowledge-base/engineering/architecture/diagrams/model.c4` enumerates every shipped customer-machine surface with its ADR and records earlier narrower wording being falsified by new capabilities; user mode adds three such surfaces (it writes tracked files into the user's repository, makes network egress to PyPI for the ruff wheel, and executes a downloaded, hash-pinned binary). Required edit: add one sentence to that description naming the lint-ratchet user mode (ADR-290) and its write and egress properties; PyPI is deliberately not modelled as an element or edge (recorded as a deliberate omission in the sentence), and no component is added. Mandate satisfied: this plan read `views.c4` (the `components` view include list), `spec.c4` element kinds, and the `platform.plugin` description and `constraintscaffold` component in `model.c4`; work task 0.4 repeats the full three-file read before the edit. Enumerated against the feature: (a) external human actor: the Soleur plugin user is the already-modelled `founder`; (b) external system: PyPI is not modelled and `model.c4` carries no package-registry element (grep for `pypi|npm registry|registry` found only the engine registry component); the user's repository is the existing connected-repo concept; (c) container or data store: none new (the baseline is a file in the user's repo); (d) actor-surface access relationships: unchanged. After the edit run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` (green at plan time: `ALL TESTS PASSED`), `c4-canonical.test.ts`, and regenerate `model.likec4.json` via `render-c4-model.sh` so `c4-model-freshness.test.sh` is green. No skill or agent is added, so the "103 workflow skills" and "67 domain agents" counts do not move.

### Sequencing

Single PR: the ADR amendment describes the shipped state; no status flip is deferred.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/scripts/lint-ratchet.py` and `plugins/soleur/scripts/ruff-requirements.txt` exist; `scripts/lint-ratchet.py` and `scripts/ruff-requirements.txt` do not (`git diff -M --stat origin/main...HEAD` reports them as renames, `ruff-requirements.txt` at 100% similarity).
- [ ] `git grep -n 'scripts/lint-ratchet\.py\|scripts/ruff-requirements\.txt' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings' ':!**/archive/**'` returns only hits that carry the `plugins/soleur/` prefix (own planning artifacts, learnings and archives are point-in-time records).
- [ ] The state matrix passes (`python3 -m unittest tests.scripts.test_lint_ratchet` exits 0) with these rows, implemented in `plugins/soleur/scripts/lint-ratchet.py` (`classify_user`, `check`, `auto`, `main`) and asserted as WHOLE lines where a line is specified: no ruff config -> 0 with the `no linter configured` line; ruff config without baseline -> 0 with the whole `not adopted. Ask the user whether to adopt; if yes, run: ...` line and pip never invoked; adopted and clean -> 0; NEW finding -> 1; STALE entry -> 1; growth against a repo whose default branch is `master` (no `origin/main`) -> 1; baseline deleted since the merge base -> 1 (also under `CI`); baseline kept and config deleted -> 1; baseline at HEAD missing in the working tree with an unresolvable base -> 2 under `CI` and never `not adopted`; config present with no baseline and an unresolvable base -> 0 plus the `base unresolvable` stderr line; unresolvable base elsewhere -> a `SKIP`/`WARN` line (never `OK`) and 0 locally, 2 under `CI`; untracked baseline -> the `git add .lint-ratchet` note; fake-ruff infrastructure failure -> 2 with the REPO-CONTENT prefix and the pinned-version hint only for config-caused errors; not a git repository -> Skip/0, a bare repository -> a run-from-a-worktree message; `auto` run as the Soleur plugin script inside the Soleur checkout -> the self-skip line and 0 without provisioning, while a user repo with a planted `scripts/lint-ratchet-ruff.baseline.txt` is still ratcheted; `auto` and `user-ruff --check` agree on every state; `auto --update` and `auto --list` are rejected with exit 2.
- [ ] Totality rows pass: a `Failed to` stderr line -> 2; a ruff exit code outside {0, 1} -> 2; unparsable JSON -> 2; a tracked `dist/x.py` that ruff does not list does not read as a skipped file; an adopted repo with zero files in ruff's listing and an empty baseline -> 0 with a `WARN` line, with a non-empty baseline -> 1 (STALE); zero tracked `.py` files in user mode -> 0 with the hint (not Vacuous); an `invalid-syntax` finding is an ordinary finding.
- [ ] Safety rows pass: a symlinked, non-regular or over-1-MiB `ruff.toml` -> exit 2 with the fixed message and no file content echoed; a config with `fix-only = true` leaves the working tree byte-identical after the run; `RUFF_*` and `PYTHON*` are absent from the ruff child environment; a relative `XDG_CACHE_HOME` is ignored; git is invoked with `-c core.fsmonitor=false`.
- [ ] Fingerprint rows pass: a PR that edits only the HEAD header is still growth-checked; merge-base and HEAD headers differing with HEAD equal to live exempts growth and prints the `CONFIG CHANGED` sentinel; a missing header gives no exemption; update-then-check is green; `--update` grows only when the HEAD header differs from live; a stale header with an equal census prints `fingerprint stale: run --update to refresh`; a `pyproject.toml` edit outside `[tool.ruff...]` leaves the hash unchanged; the rendered user baseline contains no absolute path, no home directory and no `10331`.
- [ ] Waiver rows pass: a `# noqa` in user mode is honoured; in Soleur mode the same finding still counts; the Soleur scopes' printed output is byte-identical to `origin/main`'s for the same input.
- [ ] `--update` rows pass: a git-ignored target path prints the check-ignore line and the written path; an unreadable base prints the documented message; the merge-base ladder rows (dangling `origin/HEAD`, `upstream/main` only, shallow clone message, local-branch `WARN`).
- [ ] Carry-in 1: a `final` cache directory without `bin/ruff` produces an `InfraError` naming that directory with `rm -rf`; the version-probe failure message carries the same hint.
- [ ] Carry-in 2: `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` has a second `it` that runs `TestEslintConfigBehaviour`, asserts exit 0, `Ran N tests` with N at least the class's case count and no `skipped` in the unittest footer; it passes locally (`cd apps/web-platform && ./node_modules/.bin/vitest run test/eslint-test-dirs-ratchet.test.ts`) and the `test-webplat` shard log of the PR shows both `it` names passing. `Closes #10507` is in the PR body only if both carry-ins are green.
- [ ] `plugins/soleur/skills/work/SKILL.md` contains the anchor `lint-ratchet.py" auto` and no `linting-agent`; `review/SKILL.md` contains `lint-ratchet.py" auto` between its `**Bootstrap (mandatory before spawning the agent):**` paragraph and the next `**What this agent checks:**` heading after it; an anchor test in `tests/scripts/test_lint_ratchet.py` pins both and the `never a repo-local copy` and `never --update unprompted` clauses (fences and HTML comments stripped before matching).
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` is green; measured deltas recorded in the PR body: `work` +245 B against 265 B headroom, `review` -5 B against 48 B headroom; `git diff --quiet origin/main...HEAD -- plugins/soleur/test/skill-body-budget.json` (unchanged).
- [ ] `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `eslint-test-dirs --check` are green on this tree (Soleur scopes unchanged: 44 ruff entries, 20 eslint entries; floors 55 and 105 intact) and the lefthook entries run the new path.
- [ ] `bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` prints `LINT_RATCHET_PROBE_OK` in under 15 s with no network; its real output is in the PR body.
- [ ] The lefthook glob pins, registration pins (`MIN_CASES`, the guard-class set) and `scripts/lint-orphan-test-suites.sh` are green after `git add` of every new tracked file.
- [ ] ADR-290 carries Amendment 1 with the edited Decision/Consequences sentences and no longer carries residual 7; the `platform.plugin` description carries the new sentence; the five C4 tests are green and `model.likec4.json` is regenerated.
- [ ] `bash scripts/test-all.sh --affected` (or the full battery if the affected gate degrades) is green; CI `test`, `test-webplat` (both shards) and `test-scripts` are green.
- [ ] PR body: first line `Ref #10331`; no `Closes/Fixes/Resolves #10331`; `Closes #10507` present; `## Changelog` section; label `semver:patch`.
- [ ] Markdown lint on the plan and `tasks.md` is clean (`npx markdownlint-cli2`).

### Post-merge (operator)

None. `soleur:postmerge` verifies, with the merged `main`: `bash tests/scripts/fixtures/lint-ratchet/not-adopted-demo.sh` prints `LINT_RATCHET_PROBE_OK`, the required `test` context on `main` is green, `gh issue view 10507 --json state` is CLOSED and `gh issue view 10331 --json state` is OPEN (Automation: all steps are agent-runnable; none needs the operator).

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled all forks in three passes (2026-10-18); the later passes amended the earlier where the plan-review seats (DHH, Kieran, code-simplicity) and the deepen-plan agents (security-sentinel, architecture-strategist, observability-coverage-reviewer, spec-flow-analyzer) dissented or found gaps. See `decision-challenges.md`.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:engineering:cto, soleur:product:spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

Brainstorm CPO assessment carried forward: no demand evidence for the user-facing half; operator overrode on 2026-10-15; the plan therefore keeps the slice opt-in, Python-only and minimal. No UI file is created or edited (the mechanical UI-surface override did not fire: no `components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx` path in the file lists). Spec-flow analysis of the user journey (first run, adopt, ongoing runs, config change, un-adopt, merge conflict, default-branch variants, shallow CI) produced ten findings, all folded into Proposed Solution 3-8 and 11. Legal: no new data processing (no telemetry, no Soleur-side sink; nothing leaves the machine except the existing hash-pinned PyPI wheel fetch); `gdpr-gate` is not triggered (no schema, auth, API-route or `.sql` path; none of the cross-controller triggers a-d fires: no LLM or external API on session data, threshold is `aggregate pattern`, no cron reads learnings, and no new artifact-distribution surface beyond the already-shipped plugin tree). The telemetry question goes to `soleur:legal:clo` only if telemetry is ever proposed.

## Test Scenarios

- Synthetic user repos in a tmp dir (existing `Repo` helper in `tests/scripts/test_lint_ratchet.py`): the state, totality, safety and fingerprint matrices above, run through `main()` and through `subprocess` for the CLI arms (`auto`, `user-ruff --update`).
- Default-branch ladder: one row for a repo with only `origin/master`; one for `refs/remotes/origin/HEAD` pointing at `develop`; one for a dangling `origin/HEAD`; one for `upstream/main` only; one for a shallow clone.
- A git-ignored baseline path row (a `.gitignore` containing `.lint-ratchet/`).
- Whole-line rows: the fingerprint line, the `not adopted` line, the self-skip line, the `CONFIG CHANGED` sentinel and the `baseline deleted since the merge base` line are asserted as WHOLE lines, not substrings; a baseline with two identical-anchor entries; a zero-findings adopted repo.
- Isolation rows: `user-ruff` with `SCOPES`, `DRAWDOWN`, `ESLINT_*` poisoned gives the same verdict; Soleur-scope output byte-identical.
- Vitest: both `it` blocks in `eslint-test-dirs-ratchet.test.ts`.
- Verify the verifier: the four mutation rows run in a scratch copy (use the allocator in `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`; none of these mutants touch `kill`, `pkill`, `$PPID` or `rm -r` helpers, and the `rm -rf` hint text is asserted as printed text only, never executed).

## Risks and Mitigations

- **Config detection by line grep misreads `pyproject.toml`** (a commented `# [tool.ruff]`). Mitigation: the grep is anchored at line start; a commented-line row.
- **A user config incompatible with the pinned ruff** (`required-version`, newer rules, unknown selectors) makes ruff exit 2 on every run. Mitigation: the REPO-CONTENT prefix and the pinned-version hint (only when stderr matches a config-error pattern); exit 2 is non-blocking in `work` and `review`.
- **`work` blocking on exit 1** is deliberate for opted-in repos only. A false positive from a changed config is escaped by `--update` under the fingerprint rule, not by a skip flag (kill-switch cut). A deliberate un-adoption is relayed to the user and ships only on confirmation.
- **Teammates who do not use Soleur** can land new findings, so an opted-in user's `work` run may exit 1 on findings they did not cause; the printed output names the files and the concrete `git checkout <resolved-base> -- .lint-ratchet/ruff.baseline.txt` conflict-resolution command. A minimal user-CI snippet is documented in the ADR amendment (today the ratchet runs only inside agent sessions).
- **Guard dark in cloud runs.** Under `CI` an unresolvable base is exit 2, which the skills treat as non-blocking. Documented as a residual, with the shallow-clone `fetch-depth: 0` hint.
- **Review byte ceiling** (48 B headroom): the two trims are a provenance pointer and a parenthetical aside; `lint-skill-body-budget.py` is the gate; do not compress any condition-bearing sentence. Work has 20 B spare after the new line.
- **Prior-art divergence from the brainstorm** (changed-lines delta and user eslint dropped): recorded in `decision-challenges.md` so the spec and brainstorm are not read as unmet.

## Deferrals (tracked)

Phase 0 work task 0.3 files one tracking issue (milestone from `knowledge-base/product/roadmap.md`, re-evaluation criteria stated, referencing #10331) for: user-mode JS/TS (eslint) support, monorepo and nested-config support, changed-files-only advisory mode, native Windows support, notebook (`.ipynb`) scanning, opt-in telemetry (needs `soleur:legal:clo` first), and evaluating `ever-better` as an alternative.

## PR Body Reminder

`Ref #10331` as the first line; `Closes #10507`; no closing keyword for #10331; include the measured SKILL.md byte deltas, the real discoverability wrapper output, and the CI-log evidence for carry-in 2; `## Changelog`; `semver:patch`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it with `aggregate pattern`.
- The SKILL.md edits are byte-budgeted as deltas up front (work +245 B of 265 B; review -5 B); compression under a failing hook drops conditions, so write the final wording once and measure with `wc -c` before and after.
- `git add` every new tracked file (script, wrapper, tests) before running the orphan census or repo-global ratchets; they read tracked files only.
- The hyphenated script name means tests must keep loading it with `importlib`.
- `scripts/lint-ratchet-*.baseline.txt` do not move in this PR, on purpose (ADR-290 residual 3).
- The Soleur scope names `ruff` and `eslint-test-dirs` are bound by lefthook, `test-all.sh` and argparse; never reuse them for user mode.
- Every `git` call in the engine and the wrapper must run with a constructed environment (the wrapper uses `env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE`); a bare `git init` inside a linked worktree initialises the developer's live repository.
