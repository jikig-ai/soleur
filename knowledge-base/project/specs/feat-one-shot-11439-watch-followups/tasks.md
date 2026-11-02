# Tasks: watch follow-ups (#11439)

Plan: `knowledge-base/project/plans/2026-11-02-fix-watch-census-scope-and-git-egress-plan.md`
Branch: `feat-one-shot-11439-watch-followups` | Issue: #11439 (P3) | Parent epic #10331 stays closed (`Ref #10331`, no closing keyword)

Rule for every phase: write the failing suite rows first, then the change (`cq-write-failing-tests-before`). Do not touch the workflow `cron:` line. Never write the literal `git -C "$WT"` / `git -C "$REPO_ROOT"` in either suite (use `gitx`, or assemble at run time); the fixture ratchets count them as sites.

## Phase 1: Census - scope the plumbing allowlist (item 1)

File: `scripts/watch-code-quality-reeval-9730.test.sh`

- 1.0 File follow-up issue `#<F2>` (census residual bypass classes: wrappers, case/YAML command positions, quoted env-prefix values, the `for x in git;` strip, `printf -v`/`read`/`+=` assignments, `type -P`, `-c` config and `--output=` through read-only verbs, the `git "$@"` exemption, quoted `"gh"`, dashed `git-x`). Labels `deferred-scope-out`, `priority/p3-low`, `type/chore`, `domain/engineering`; milestone `Post-MVP / Later`; re-evaluation criterion "a watcher edit needs one of these shapes, or a review finds a census false negative".
- 1.1 Add `probe_census_as NAME TEXT` and `mutcopy_as NAME SRC BASENAME` (both `assert_fixture_dir` before `mkdir -p` and before the file redirect); `mutsubst` takes a file operand with its own control and `MUT_LANDED` check (a rename-only row is landed by basename inequality plus content equality). `probe_census` uses basename `probe.sh`; grep for other readers of `$ROOT/probe.txt` first.
- 1.2 Write failing rows: T1 forbidden (see plan Guard 1 H2 must-FAIL list, one isolated cause each; `reset --hard` via `gitx -C "$REPO_ROOT"` or an absolute literal), T2 must-PASS plumbing probes under the 11177 basename (move `reset --mixed` out of G1e into T1). Run `bash plugins/soleur/test/fixture-relative-assert.test.sh` and the two `fixture-scan.py` commands right after.
- 1.3 `census_scan`: pass `basename "$f"` to perl as argv; perl sets `$plumb` for `watch-brand-hex-triggers-11177.sh` only (yml and every other file false).
- 1.4 `CENSUS_PERL`: remove the six verbs from global `%ro`; add `%plumb` (five verbs, no `reset`); capture `-C` operands only (never `-c`) into a list; `$cfg` true on any `-c`, `--git-dir*`, `--work-tree*`; pins: `read-tree`/`hash-object`/`update-index` need exactly one `-C` matching `"$WT"`/`"${WT}"`/`$WT`; `update-ref` the same plus exactly `--no-deref HEAD <one non-dash word>`; `worktree` needs exactly one `-C` matching `$REPO_ROOT` and `add` (with `--detach`, no `-b`/`-B`) or `remove --force <one word>`.
- 1.5 Mutation rows X7-X9 (Guard 1 matrix rows 1-3) with `mutcopy`/`mutcopy_as`, control first; assert the specific finding text per mutated line.
- 1.6 Write the census contract comment (tripwire for accidental, plainly spelled additions; basename-keyed, fails closed on rename; residuals in `#<F2>`); fix the stale comment that lists the plumbing verbs as globally read-only and the G1d/G1e pass messages.

## Phase 2: Census - close the git egress shapes (item 2)

File: `scripts/watch-code-quality-reeval-9730.test.sh`

- 2.1 Write failing rows T3 (RED set: `\git fetch origin`, `'git' fetch`, `"git" fetch`, `g=git; $g push`, `GIT=git; "$GIT" push`, `G=$(command -v git)`, `git_bin=git`; isolating probes `GIT=$(pick_tool)`, `echo hi; "$GIT" fetch`, `type -p git`; regression-only `\git push origin HEAD`, `/usr/bin/git fetch`, `${GIT:-git} push`, `which git`) and T4 (must-PASS: `echo ${GIT_UNSET[@]}`, `env "${GIT_UNSET[@]}" git "$@"`, `GIT_UNSET=(-u X)`, `x=gitlab`, `legit_ok=1`, `git -C "$d" log --first-parent`, `echo "git" push`, `printf '%s\n' 'git' status`, `echo "run git fetch later"`). Run the RED set against the unmodified census first and confirm it fails.
- 2.2 `CENSUS_EGRESS_RE`: add `$GIT`/`${GIT}` use, `GIT=`, and `git` to the `command -v|which|type -p` alternative.
- 2.3 Extend the `VAR=gh` assignment regex to `VAR=gh|git` (keep `GIT_UNSET=(`, `GIT_CONFIG_*`, `x=gitlab` clean; accepted false positives `x="git"` and `grep -q "git push" f` stated in the suite).
- 2.4 `CENSUS_PERL` command-position match: optional leading backslash and quotes around the tool name.
- 2.5 Mutation row X10 (Guard 2 matrix row 3, `mutcopy`); re-run the census over the real lib, three scripts and workflow: 0 findings.

## Phase 3: `env -0` failure check (item 3)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `scripts/watch-brand-hex-triggers-11177.test.sh`

- 3.1 Write three registered scenarios first: `chk_envfail_a` (shim rejects `-0`, real `env` by absolute path otherwise, logging `git` shim -> `RC=3`, zero posts, `::error::` naming `env -0`, zero logged git calls, empty `$MOCKD/tmp`), `chk_envfail_b` (pass-through shim on a one-commit clean repo -> `RC==0`, `examined=1`, no `env -0` error), `chk_envfail_c` (single `PATH=` record -> same assertions as b).
- 3.2 Add the seen-flag counter to the scrub loop and the `exit 3` check immediately after it, before `gitx` is defined or used.
- 3.3 Update the header comment about the scrub.
- 3.4 Mutation rows (Guard 3 matrix 1, 2, 3, 3b) via `mutation_row`: delete the check; reorder it to just before the `wn_preflight` line (two `sut` triples); count only matching records; `-gt 0` -> `-gt 1`.

## Phase 4: Forged-header guidance (item 4)

Files: `scripts/watch-brand-hex-triggers-11177.sh`, `.github/workflows/code-quality-followups-watch.yml` (comments only), `scripts/watch-brand-hex-triggers-11177.test.sh`

- 4.0 File the ONE follow-up issue first: parse the trigger-2 log stream NUL-safely so a header-shaped path cannot forge a header (same labels and milestone; criterion "first time this exit fires in a real run"). Use its number as `#<F>`.
- 4.1 Failing rows first: extend `chk_forged_header` (remedy clauses `re-run`, `does not clear`, `trigger 1`, the pointer, and `#[0-9]{4,}`); add the parity row with its vacuity guards (single `T2_STREAM_HINT=`, non-empty `^[A-Z ]+$` token, FAIL when the workflow is absent, paragraph = `# RED RUN:` line through the next bare `#` line containing `trigger 1` and `does not clear`); add the sibling-unchanged pin; add the `! grep` hint-absence assertion to `chk_gitconf`.
- 4.2 Add `T2_STREAM_HINT` and append it to the `does not match the first-parent list` message only (present text stays the prefix). Leave the `ended before the window base` message alone.
- 4.3 Workflow header: `# RED RUN:` paragraph after `RESIDUAL RISK` (same content, cites `#<F>`); one RETIREMENT line (when the 11177 script goes, also delete the census `%plumb` allowlist, the `probe_census_as` rows and the 11177 mutation copies; update the accept-row counts if the replay ratchet forces a change). No non-comment line changes.
- 4.4 Mutation rows (Guard 4 matrix 1-4), including the row that keeps the heading but guts the paragraph body (build the workflow copy with `sed`).

## Phase 5: Verification and PR

- 5.1 Run the three watcher suites and `bash -n` on the edited scripts; `python3 scripts/lint-guard-contract.py`.
- 5.2 Run the repo-global checks: `scripts/check-adr-ordinals.sh`; `plugins/soleur/test/boundary-prefix.test.sh`; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `scripts/guard-vacuity-floor.test.sh`; `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`; plus `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash .claude/hooks/incident-sandbox-coverage.test.sh`; and `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative|operand` over both edited suites (`SITES=0`).
- 5.3 Run the AC6 comment-only diff check on the workflow and confirm the cron line still matches once.
- 5.4 PR body (via `--body-file`; ship rewrites it, so re-verify with `gh pr view <N> --json body,title,closingIssuesReferences` after its last edit): `Closes #11439`, literal `Ref #10331`, Decision Classes table, attribution line; no closing keyword in the title.
- 5.5 Run `soleur:ship` then `soleur:postmerge` to completion per the brief (Monitor for Phase 7 polling, never `run_in_background`).
- 5.6 After merge, compound should capture two gaps: `env -0` failure checks, and the control-character-plus-40-hex header forgery with its permanent-window consequence.
