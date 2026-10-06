# Learning: a notify-only watcher's suite sampled one shape per axis, and my comment called a load-bearing flag redundant

## Problem

PR #9660 (`Refs #9564`) added a weekly, notify-only GitHub Actions watcher for a deferred tracker. It counts commits on `main` that touch two runner files and posts ONE bot-authored, sentinel-marked comment at a threshold of 3. The first cut passed a 17-assertion mock-`gh` suite, a 9-row self-run mutation battery, every repo ratchet and a 168-minute affected-suite gate. A six-seat panel then found 15 deduplicated defects (0 P1) and a fix round found about 12 more P3s. Nearly all of them were one defect class.

The class: **every fixture, mock and comment sampled one shape per axis the property quantifies over.**

- **argv axis.** The mock `gh` dispatched on `$1 $2` and served the same JSON whatever the issue number, `--json` fields or extra flags. Changing `ISSUE=9564` to `9565`, dropping `comments` from `--json state,comments` (which makes the dedup dead in production: real `gh` then returns no comments and the notice re-posts weekly), or adding `--edit-last` all left the suite green.
- **commit-shape axis.** Every qualifying fixture added one line to `scripts/test-all.sh`; the index file was never modified, so a mixed-file commit (delete in the index, add in the runner), a binary numstat (`-	-`), an index-only edit and a hand-resolved merge were never sampled. Three duplicated awk programs were sampled by one shape, so any one-of-three revert survived.
- **comment/claim axis.** I wrote that `--no-merges` was "defence in depth: a merge's combined diff can never carry a `+run_suite` line". Two seats refuted it by constructing a hand-resolved merge whose combined diff carries `+ run_suite ...`; the flag is load-bearing and only the conflict-merge fixture (S10c) pins it. I wrote the claim and the fixture in the same edit and never ran the one mutation (remove the flag) that would have contradicted the claim.
- **design axis.** The "registration-shaped" proxy (touches the runner, deletes nothing) overcounted: index-only commits and non-registering additions qualified, so the once-only notice would have been spent on noise. Qualification now also requires an added `run_suite` line in the runner.

Smaller real defects in the same family: a jq error on `comments:null` was read as "no sentinel" and posted anyway, contradicting the header's own "a failed read posts nothing"; a renamed or split runner file would have made the pathspec match nothing and the count read 0 forever with a green run; a short `%h` passed to `git show` can be shadowed by a branch or tag named like it; a lone CR or an entity-encoded `&#64;user` survived the subject sanitiser; a manual `workflow_dispatch --ref <branch>` would have measured that branch and could burn the notice.

## Solution

- One awk pass emitting `Q<TAB>line` / `X`, then a per-commit `git show --format= -U0 <full sha> -- scripts/test-all.sh` check for an added `^\+[[:space:]]*run_suite[[:space:]]` line. `--no-merges` kept, its comment corrected, S10c pinning it.
- jq failure and a missing runner path are exit 3; unknown arg exit 2; xtrace exit 78 (the sibling convention); sanitiser strips control bytes and neutralises `@ < > \` &`; display cut in bash.
- Workflow job guard `if: github.ref == 'refs/heads/main'`; the header states why `*-watch.yml` is deliberate.
- Suite 17 to 35 assertions: an exact two-line `gh` call-set pin, a fixture per commit shape, the off-branch base, a runner path removed, count 0, prefix-matching login and a different sentinel version, null comments, missing `.state`, usage, xtrace, the workflow contract (cron, `fetch-depth: 0`, `issues: write`, `GH_TOKEN`, the script path), the default base pinned by VALUE, an exact 102-char display length, S15b (the forbidden-verbs check) as an allowlist with a 5-verb positive control, and a behavioural exit-gate check (the suite re-run with one injected failure must exit exactly 1).
- A 44-row layout-faithful mutation battery (sandbox with `scripts/` plus `.github/workflows/`, anchor-count-1 and landing asserts, a row counts as killed only when the suite fails with a line naming the intended scenario): all killed.

## Key Insight

Ask, per axis a property quantifies over, "how many members did the fixture sample, and can the mock reject?" before the first review, not after. For an external-CLI client the cheapest first fixture is the one that pins the exact argv (`issue view 9564 --json state,comments` plus `issue comment 9564 --body-file -`), because a field dropped from `--json` is invisible to a mock and fatal to the dedup in production. This is the review skill's existing "a battery is bounded by its oracle" class (#7706) recurring on the author side, so the finding is the propagation failure: the rule lives in the review skill, and the author writes the suite without it. Second: a claim that a flag, mutant or branch is "redundant" or "equivalent" must carry the enumeration of input shapes it surveyed; mine surveyed the merge shape that is absent from `--numstat` and not the one whose combined diff carries added lines.

## Session Errors

1. **Local `main` was 393 commits behind.** Recovery: used `origin/main` for every probe. **Prevention:** fetch and compare against `origin/main` by default (already the repo rule `hr-when-in-a-worktree-never-read-from-bare`).
2. **The session-start gate overwrote a dirty `.mcp.json`.** Recovery: backed up the edit first; filed #9622 for the defect. **Prevention:** tracked in #9622 (go-gate must restore, never overwrite, a dirty tracked file).
3. **Two false measurement claims propagated into docs, an issue comment and the PR body** ("491 s unverified", "one registration-only PR since #9552"). Recovery: re-measured, corrected all carriers. **Prevention:** verify a measurement at the granularity you will claim before the first write; grep the OLD claim, not the new one, after correcting.
4. **FR2 ("cheaper path") was overbroad.** Recovery: reworded in spec and brainstorm. **Prevention:** a requirement naming an effect must name the exact arrays and files it changes.
5. **The stop hook blocked about eight turns that ended on first-person commitment language while waiting on background seats or a gate.** Recovery: end a waiting turn with a `<stop>BLOCKED: <what is blocking></stop>` line written as facts about state ("the gate is queued"), never "I'll ..." / "I'm making no writes". **Prevention:** none beyond the wording discipline (the hook is advisory-by-design).
6. **The merge hook blocked `gh pr merge` for lack of review evidence.** Recovery: ran the real review and emitted the trailer. **Prevention:** none needed (the gate worked as designed).
7. **A command containing `git stash list` was blocked by the hook.** Recovery: removed it. **Prevention:** none (`hr-never-git-stash-in-worktrees` is hook-enforced).
8. **Small slips:** H2 measured the whole comment body instead of the list lines; a Python edit aborted on an `assert` over an escaped `$` and the rerun showed baseline; shellcheck SC2097/SC2098; 13 unguarded `git -C` fixture sites; `lint-trap-tempfile-ownership.py` has no `--base` flag. Recovery: fixed each. **Prevention:** assert a mutation landed before reading a result; guard each fixture-writing window with `assert_fixture_dir`.
9. **My `--no-merges` comment ("redundant by construction") was false.** Recovery: two seats refuted it; comment corrected and S10c named as the pin. **Prevention:** run the removal mutation for any flag you describe as redundant, and fixture the shape that would break the claim.
10. **My first battery (9 rows) mutated only SUT axes; ~12 survivors on argv and fixture shapes.** Recovery: rebuilt as a 44-row layout-faithful battery. **Prevention:** before the first review, enumerate the axes the property quantifies over and give the mock a way to reject.
11. **The count proxy overcounted (index-only and non-registration commits qualified).** Recovery: required an added `run_suite` line. **Prevention:** measure the proxy against `git log` on real main before trusting its threshold.
12. **The affected gate waited about 2.8 h in the lock queue behind sibling worktrees; the monitor was re-armed three times at its 30-minute cap.** Recovery: waited on the rc file. **Prevention:** read `test-all.sh --capacity` before launching; when queued behind a multi-hour sibling run, rely on targeted suites plus the PR's CI.
13. **I reported the live count as 1; it was 2 once `main` moved and this PR's own registration counted.** Recovery: header baseline note (count=2 at merge) and the PR body. **Prevention:** a count on a moving ref is a snapshot; state its SHA and date.
14. **The seat tally recorded 5 for a round that spawned 4.** Recovery: none needed (one-off).

## Tags
category: test-failures
module: scripts/watch-registration-narrowing-9564, review, work
