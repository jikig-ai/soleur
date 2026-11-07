# Tasks: feat-one-shot-12251-battery-owed-c-quoted-infra-paths

Plan: `knowledge-base/project/plans/2026-11-07-fix-battery-owed-c-quoted-infra-paths-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12251-battery-owed-c-quoted-infra-paths/decision-challenges.md`
Standing constraints: file-selected suites only (this one suite; no affected battery to completion); no push to a PR in the merge queue; no `--admin`; no ruleset change; components written canonically (`soleur:ship`, `soleur:postmerge`); `git add` and `git commit` in separate calls; no `rm -rf` in the worktree; no `git stash`.

## Phase 1 - RED rows (suite only; append before the `# The floor counts` comment, never edit anything above line 1114 except the one same-length comment in 2.3)

- 1.1 Before editing, record `sed -n '96p;465p;468p;1105p;1114p' plugins/soleur/test/ship-battery-owed.test.sh` and `wc -l` of the suite for the later cite check.
- 1.2 Add the local helper `t20_commit <work> <relpath>` (special bytes travel as an argv element) and the T20 header comment naming #12251.
- 1.3 T20a: a shape loop over four names (`é`, tab, `"`, `\`), a fresh fixture each: control `Zcontrol-20/<name>.md` is SKIPPABLE; commit infra `apps/web-platform/infra/<name>.tf`; precondition (`grep -c '^"apps/web-platform/infra/'` over the plain `git diff --name-only` equals 1); infra is OWED plus `assert_reason` "diff touches the infra surface". No loop counter (the floor catches an empty table).
- 1.4 T20b: `diff.ignoreSubmodules=all` fixture; gitlink via `git update-index --add --cacheinfo 160000,<sha>,<path>`; precondition (zero `sub20` lines in plain diff), control `Zcontrol-20/sub` SKIPPABLE, `apps/web-platform/infra/sub20` OWED plus reason.
- 1.5 T20c: `diff.relative=true` set first; control from `plugins` SKIPPABLE; commit `apps/web-platform/infra/rel20.tf`; precondition (zero `rel20` lines in the plain diff run in `plugins`); `run_gate_sub ... plugins` OWED plus reason.
- 1.6 Run `bash plugins/soleur/test/ship-battery-owed.test.sh` against the UNFIXED script: confirm every infra/reason row is RED and every control and precondition row is GREEN; record the failing labels. Do not bump the floor yet.

## Phase 2 - GREEN (one production edit)

- 2.1 In `plugins/soleur/skills/ship/scripts/battery-owed.sh` replace the `CHANGED=` assignment with `git -C "${_tp:-.}" diff -z --no-renames --ignore-submodules=none --name-only refs/remotes/origin/main...HEAD -- 2>/dev/null | tr '\0' '\n'`; leave `rc=$?`, the empty-diff check, `INFRA_RE` and the final grep untouched.
- 2.2 Rewrite the comment block above it in about 6 lines (point at the token arm's rationale; add only `-C`/`diff.relative`, the `core.quotePath=false` caveat and the COPY note) and DELETE the "shares the C-quoted-path blind spot (#12251)" sentence. Name no new real file path in the comments.
- 2.3 In the suite, replace the single T5g/T5h comment line about `tr '\t' '\n'` with a same-length line about `--no-renames` (file line count above 1114 unchanged).
- 2.4 Re-run the suite: all green; set the `print_results` floor to the exact PASS count reported (expected 415; re-count).

## Phase 3 - mutation battery (scratchpad driver `mut-12251-battery-owed.sh`)

- 3.1 Driver: back up script and suite; unmutated control must pass with the expected count; per mutation apply the edit to the real file, assert the edit landed (`cmp` differs, hunk present), run the suite, compare the failing-label set (labels, never exit codes: `head` can SIGPIPE under pipefail) with the plan's matrix; restore from backup on EXIT; finish with an unchanged `git diff --stat`.
- 3.2 Script mutations 1-10 and harness edits H1-H4 from the plan's Guard Contract. A surviving mutant means a missing row: add it (fix round 1), re-run that mutation; a second miss is fix round 2; then one verification pass.

## Phase 4 - registry and ratchet re-check

- 4.1 Re-run the cite check from 1.1: identical output; `git diff --stat` empty for `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`.
- 4.2 `git grep` the added lines for any name that is a real tracked file (`git ls-files`); there must be none.
- 4.3 Run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <scratchpad file>` once (about 6 minutes; not the test battery) and record 0 new pairs. If a pair is reported, add the accept row in sorted position keyed by the 12-hex anchor with a verified file:line cite and re-check that no earlier cite moved.
- 4.4 Single-file runs of the repo-global linters that read suite text: `bash .claude/hooks/hook-suite-dep-unresolved.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-trap-tempfile-ownership.py`, `bash scripts/lint-orphan-test-suites.sh`.
- 4.5 AC-3, AC-4 and AC-6 commands from the plan, verbatim (they diff against `origin/main...HEAD`, not a moving tip).

## Phase 5 - ship and post-merge

- 5.1 `soleur:ship`: PR body `Closes #12251`, `Ref #12246`, `Ref #12247`; net issue flow files 0 closes 1; every file path backticked; Test plan says local battery NOT executed per operator constraint; `## Changelog`; `semver:patch`.
- 5.2 Before any push: `bash plugins/soleur/scripts/sync-pr-behind.sh 12326 --queue-state` must read `not_queued`. Check each push's real exit code. Poll with Monitor.
- 5.3 Required checks green (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`); read `infra-validation` and `sandbox-canary-capture-gate` by hand.
- 5.4 `soleur:postmerge`: PR MERGED, #12251 CLOSED (close by hand citing the merge commit if the queue did not, and say so), release workflow ran, required checks green on the merge commit.
