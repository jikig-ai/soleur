# Tasks: watch follow-ups (#11439)

Plan: `knowledge-base/project/plans/2026-11-02-fix-watch-census-scope-and-git-egress-plan.md`
Branch: `feat-one-shot-11439-watch-followups` | Issue: #11439 (P3) | Parent epic #10331 stays closed (`Ref #10331`, no closing keyword)

Rule for every phase: write the failing suite rows first, then the change (`cq-write-failing-tests-before`). Do not touch the workflow `cron:` line.

## Phase 1: Census - scope the plumbing allowlist (item 1)

File: `scripts/watch-code-quality-reeval-9730.test.sh`

- 1.1 Add `probe_census_as NAME TEXT` (probe file written under its real basename in an absolute `$ROOT` subdirectory).
- 1.2 Write failing rows: T1 forbidden (`update-ref -d`, `update-ref refs/heads/x`, `worktree prune`, `reset --hard` via `gitx -C "$REPO_ROOT"` or an absolute literal, never `git -C "$REPO_ROOT"`; plumbing verbs under the 9730 and lib basenames; wrong operands under the 11177 basename: `-C "$REPO_ROOT"` on `update-ref`/`read-tree`, two `-C` operands, `-c`, `--git-dir=`); run `bash plugins/soleur/test/fixture-relative-assert.test.sh` right after. T2 must-PASS plumbing probes under the 11177 basename (move `reset --mixed` out of G1e into a forbidden row).
- 1.3 `census_scan`: pass `basename "$f"` to perl as argv; perl sets `$plumb` for `watch-brand-hex-triggers-11177.sh` only. Add `mutcopy_as` and `probe_census_as` (both with `assert_fixture_dir`); `probe_census` uses basename `probe.sh`.
- 1.4 `CENSUS_PERL`: remove the six verbs from global `%ro`; add `%plumb` (five verbs, no `reset`); capture `-C` operands only (not `-c`); require exactly one `-C` operand matching `"$WT"`/`"${WT}"`/`$WT` for `read-tree`/`hash-object`/`update-index`/`update-ref`, `update-ref --no-deref HEAD`, `worktree add|remove`; a `-c`, `--git-dir*` or `--work-tree*` token on a pinned verb is a violation.
- 1.6 Mutation rows X7+ (Guard 1 matrix rows 1-4) with `mutcopy`/`mutsubst`, control first; copies of the 11177 script keep the real basename (rows 2, 5) or a different one (row 3).
- 1.8 Write the census contract comment (tripwire, basename-keyed, fails closed on rename, not an adversarial defence); fix the stale comment that lists the plumbing verbs as globally read-only.

## Phase 2: Census - close the git egress shapes (item 2)

File: `scripts/watch-code-quality-reeval-9730.test.sh`

- 2.1 Write failing rows T3 (G1d: `\git fetch origin`, `\git push origin HEAD`, `g=git; $g push`, `GIT=git; "$GIT" push`, `${GIT:-git} push`, `'git' fetch`, `"git" fetch`, `G=$(command -v git)`, `which git`, `git_bin=git`, `/usr/bin/git fetch`) and T4 (G1e must-PASS: `echo ${GIT_UNSET[@]}`, `env "${GIT_UNSET[@]}" git "$@"`, `GIT_UNSET=(-u X)`, `x=gitlab`, `legit_ok=1`, `git -C "$d" log --first-parent`).
- 2.2 `CENSUS_EGRESS_RE`: add `$GIT`/`${GIT}` use, `GIT=`, and `git` to the `command -v|which|type -p` alternative.
- 2.3 Extend the `VAR=gh` assignment regex to `VAR=gh|git` (keep `GIT_UNSET=(`, `GIT_CONFIG_*`, `x=gitlab` clean).
- 2.4 `CENSUS_PERL` command-position match: optional leading backslash and quotes around the tool name.
- 2.5 Mutation row (Guard 2 matrix row 3, `mutcopy`; rows 1, 2, 4 are the T3 probe rows); re-run the census over the real lib, three scripts and workflow: 0 findings.

## Phase 3: `env -0` failure check (item 3)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `scripts/watch-brand-hex-triggers-11177.test.sh`

- 3.1 Write `chk_envfail` first, three scenarios in one function: (a) PATH-prepended `env` shim rejecting `-0` (real `env` resolved before the PATH change) plus a logging `git` shim -> `RC=3`, zero posts, `::error::` naming `env -0`, zero logged git calls, empty `$MOCKD/tmp`; (b) pass-through shim -> not 3; (c) shim whose `-0` output is a single `PATH=` record -> not 3.
- 3.2 Add the seen-flag counter to the scrub loop and the `exit 3` check immediately after it, before `gitx` is defined or used.
- 3.3 Update the header comment about the scrub.
- 3.4 Mutation rows (Guard 3 matrix 1-3) via `mutation_row`: delete the check; reorder it to just before `wn_preflight || exit 3` (two `sut` triples); count only matching records.

## Phase 4: Forged-header guidance (item 4)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `.github/workflows/code-quality-followups-watch.yml` (comments only), `scripts/watch-brand-hex-triggers-11177.test.sh`

- 4.0 File the ONE follow-up issue first: parse the trigger-2 log stream NUL-safely so a header-shaped path cannot forge a header (labels `deferred-scope-out`, `priority/p3-low`, `type/chore`, `domain/engineering`; roadmap milestone; re-evaluation criterion "first time this exit fires in a real run"). Use its number as `#<F>`.
- 4.1 Failing rows first: extend `chk_forged_header` (remedy clauses `re-run`, `does not clear`, `trigger 1`, and the pointer) and add the parity row (line-start `^# RED RUN:` heading plus the clauses inside that paragraph).
- 4.2 Add `T2_STREAM_HINT` and append it to the `does not match the first-parent list` message only (present text stays the prefix): re-run once; if it repeats a commit in the window touches a path named like a commit header, rename or delete does not clear it, trigger 1 is held on every run, exits are closing #11177 or fixing the parser (#<F>); see `RED RUN` in the workflow. Leave the `ended before the window base` message alone.
- 4.3 Workflow header: `# RED RUN:` paragraph after `RESIDUAL RISK` (same content, cites #<F>); one RETIREMENT line (when the 11177 script goes, also delete the census `%plumb` allowlist, the `probe_census_as` rows and the 11177 mutation copies; update the accept-row counts if the replay ratchet forces a change). No non-comment line, and not the cron line, changes.
- 4.4 Mutation rows (Guard 4 matrix 1-4), including the row that keeps the heading but guts the paragraph body.

## Phase 5: Verification and PR

- 5.1 Run the three watcher suites and `bash -n` on the edited scripts; `python3 scripts/lint-guard-contract.py`.
- 5.2 Run the repo-global checks: `scripts/check-adr-ordinals.sh`; `plugins/soleur/test/boundary-prefix.test.sh`; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `scripts/guard-vacuity-floor.test.sh`; `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`; plus `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/incident-sandbox-coverage.test.sh`.
- 5.3 `git diff origin/main...HEAD -- .github/workflows/code-quality-followups-watch.yml` shows comments only; the cron line still matches.
- 5.4 PR body (via `--body-file`; ship rewrites it, so re-verify with `gh pr view <N> --json body,title,closingIssuesReferences` after its last edit): `Closes #11439`, literal `Ref #10331`, Decision Classes table, attribution line; no closing keyword in the title.
- 5.6 After merge, compound should capture two gaps: `env -0` failure checks, and the control-character-plus-40-hex header forgery with its permanent-window consequence.
- 5.5 Run `soleur:ship` then `soleur:postmerge` to completion per the brief (Monitor for Phase 7 polling, never `run_in_background`).
