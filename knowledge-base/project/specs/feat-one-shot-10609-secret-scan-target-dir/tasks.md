# Tasks: fix(hooks): git-commit-secret-scan derives the repo from the commit's target directory

Plan: `knowledge-base/project/plans/2026-10-20-fix-secret-scan-hook-target-dir-plan.md`
Issue: #10609 (closes). Reference only: the closed epic. Deferred sibling gap: #10696.

## Phase 0: RED first (guard design before code)

- 0.1 Baseline: run `bash .claude/hooks/git-commit-secret-scan.test.sh` (expect 20 passed, 0 failed, 0 skipped).
- 0.2 Measure the strict regex (line 113) against `git -C x commit`, `git --work-tree=x commit`, `git -c a=b commit`, `git --no-pager commit`, `cd x && git commit`, `GIT_DIR=x git commit`; record MATCH/NOMATCH.
- 0.3 Add the `_run_cmd <cwd> <command> [path]` helper and `_mk_bare_root_with_worktree` (core.bare=true root with no `.gitleaks.toml`, linked worktree carrying the toml and a staged `_mk_pem` secret, `t5_`-style payload) with the mandatory fixture control (plain gitleaks in the worktree exits non-zero).
- 0.4 Write T21-T43 and S-repair as failing tests against the unmodified hook; must-ALLOW controls (T23, T34, T35, T37, T43) green. Register every `mktemp` with `_TMP_DIRS`.
- 0.5 Capture the RED count per fixture.

## Phase 1: Library `.claude/hooks/lib/commit-target-roots.sh`

- 1.1 `ctr_wants_lex` pre-filter (cd, pushd, GIT_DIR, GIT_WORK_TREE, --git-dir, --work-tree, `git` + option); pin its token list with a unit row.
- 1.2 `ctr_collect`: guarded `perl "$LEXER"` fed by `printf '%s'`; LEXER path from `${BASH_SOURCE[0]}`; `IFS= read -r -d ''`, parse by count, `OK` terminator as the only success signal; sets CTR_TARGETS, CTR_BAD, CTR_COMMIT_SEEN, CTR_LEX_STATE.
- 1.3 Record walker: assignments and wrappers; `cd`/`pushd` operands (expansion, `-`, `~` -> bad); `git` global options (`-C`, `-c`, `--git-dir`/`--work-tree` -> bad); subcommand `commit`; runner records with an expansion operand -> bad.
- 1.4 `ctr_resolve_roots`: absolute and relative joins against {PWD, payload cwd, earlier candidates}, `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C ... rev-parse --show-toplevel`, string-membership de-dup (bash 3.2).
- 1.5 Hand-check every Test Scenario command with `perl plugins/soleur/hooks/lib/shell-argv.pl --trace < file`.

## Phase 2: Hook refactor `.claude/hooks/git-commit-secret-scan.sh`

- 2.1 Keep line 113 byte-identical; add the loose detection test after line 115; keep header edits line-neutral.
- 2.2 Memoized `gitleaks_runnable` (main shell, not inside `$(...)`), same two bypass rows.
- 2.3 Undeterminable deny (library missing, lexer unavailable, `E`, non-literal target) after the probe and before the legacy bypass; deny text per the plan (separate-`cd` repair first).
- 2.4 `scan_root <root>`: returns a status, per-root local state (`gl_nodiff`, nodiff scratch dir and report, `report_file` truncated), single final `allow` after the loop, root named in a finding reason.
- 2.5 Root set = CTR_ROOTS union cwd root union payload-cwd root; legacy bypass reasons when no roots; per-root toml-absent bypass.
- 2.6 Run the 20 pre-existing arms unchanged, then the new fixtures green.

## Phase 3: Mutation battery (on COPIES)

- 3.1 Run mutation rows 1-13 and harness rows H1-H4; record the arms that redden; restore.
- 3.2 Confirm the CI=true skip contract still exits 1 on a skipped arm.

## Phase 4: Pins and docs

- 4.1 `bash plugins/soleur/test/boundary-prefix.test.sh`: line-113 pin intact or updated with its comment; new lib and loose test pass the census.
- 4.2 `shell-argv-parity.test.sh`, `c4-count-parity.test.sh`, `hook-input-contract.test.sh`, `shellcheck`, markdownlint.
- 4.3 `.claude/hooks/README.md` paragraph (resolution, deny, separate-`cd` repair, lexer coupling).
- 4.4 ADR-157 addendum via `soleur:architecture`.
- 4.5 `gitleaks detect --no-git` over the diff: 0 findings.

## Phase 5: Ship

- 5.1 PR body: `Closes #10609`; separate line with the word Ref, a space, the hash sign and 10331 (no closing keyword); mention #10696; `## Changelog` (semver:patch). Do not edit `plugins/soleur/skills/work/SKILL.md`.
- 5.2 `soleur:ship`, then `soleur:postmerge`; if BEHIND with auto-merge armed, wait for the merge queue (arm the watch).
- 5.3 Post-merge ledger check: payload `.cwd` follows a separate `cd`; `cannot determine` false-deny rate.
