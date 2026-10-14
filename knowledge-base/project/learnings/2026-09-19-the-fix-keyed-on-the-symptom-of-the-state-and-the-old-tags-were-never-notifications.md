---
module: System
date: 2026-09-19
problem_type: logic_error
component: tooling
symptoms:
  - "phase-7 poll printed `auto-sync 1 pushed` over a worktree left mid-merge with MERGE_HEAD present (PR #8320)"
  - "`if ! git merge origin/main --no-edit 2>&1 | tail -5` tested tail's rc (0): the conflict branch was unreachable under pipefail-off"
  - "the fixed arm's `--abort` keyed on MERGE_HEAD presence, so a merge the operator started during the fetch window (rc 128) would have been aborted"
  - "a rebase/cherry-pick conflict (rc 128, no MERGE_HEAD) was described as `refused to start (not a conflict, nothing to abort)`"
  - "every pre-existing `[ship.phase7.*] … >&2` exit line raised no Monitor notification: the tool streams stdout only and ship arms the block without 2>&1"
  - "a bare `x=\"$(cmd)\"; rc=$?` capture dies under an errexit host shell before the failure branch runs"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [ship, merge-pr, phase-7-poll, pipefail, exit-status, git-merge-abort, monitor-tool, stdout-stderr, mutation-testing, fixture-vacuity]
rule_id: hr-when-a-command-exits-non-zero-or-prints
related_issues: ["#8339", "#8378", "#8320", "#8383", "#7828", "#8334"]
synced_to: [work]
---

# The fix keyed on the symptom of the state, and the old tags were never notifications

## Problem

#8339 measured the Phase 7 poll block (`ship/SKILL.md` fence + `merge-pr/SKILL.md` §5.2
mirror) printing `auto-sync 1 pushed` immediately after `Automatic merge failed`. The BEHIND
arm's three guards were `if ! git fetch … | tail -2`, `elif ! git merge … | tail -5`,
`elif ! git push … | tail -2` — each `if` read the pipeline's status, which is `tail`'s 0.
The Monitor shell runs with pipefail off (measured: `bash -c 'set -o | grep pipefail'` →
`off`), so the conflict, refusal and push-failure branches were dead code and the loop burned
its six sync attempts re-running `git merge` on an already-conflicted tree until it printed a
`behind_exhausted` diagnosis for a condition that did not exist.

The first fix — explicit capture, then display — was correct for that defect and shipped
three narrower ones of its own, all found by the review panel:

1. **The `--abort` was keyed on MERGE_HEAD *presence*, not on git's conflict status.** An
   operator who started a merge during the fetch window makes `git merge origin/main` return
   rc 128 with MERGE_HEAD present; the arm would have classified that as "our conflict" and
   aborted their staged resolution — the exact data-loss class the precondition existed to
   prevent, one TOCTOU window later.
2. **The precondition checked MERGE_HEAD only.** A rebase, cherry-pick, revert or `am` in
   progress has no MERGE_HEAD; `git merge` refuses with rc 128 and the arm printed *"refused to
   start (not a conflict, nothing to abort) … Clear the worktree state on HEAD"* — false on
   three counts, and an instruction that steers the operator toward `reset --hard` over a live
   rebase. A detached HEAD merged and then failed at push with no branch named.
3. **The capture form `x="$(cmd)"; rc=$?` is errexit-fatal.** A bare assignment's status IS
   the substitution's, so under `set -e` (the house style for any wrapper script, and
   `sync-pr-behind.sh`'s own) the shell dies at the `git merge` assignment before `--abort` —
   MERGE_HEAD orphaned, the #8339 outcome by another route.

And one the plan had explicitly scoped out as "pre-existing, not changed": the older tagged
exits (`required_failed`, `dirty`, `behind_exhausted`) were written with `>&2`. The Monitor
tool's contract says *"Only stdout is the event stream. Stderr goes to the output file but
does not trigger notifications"*, and ship arms the block without `2>&1`. Every operator-facing
exit the block had was notification-invisible — the plan's justification ("stderr so the
Monitor surfaces it") was the inverse of the tool's contract.

## Solution

**The arm (both fences, byte-identical apart from the two documented echo deltas):**

```bash
git_dir="$(git rev-parse --git-dir 2>/dev/null)"
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   || [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" \
         || -f "$git_dir/CHERRY_PICK_HEAD" || -f "$git_dir/REVERT_HEAD" ]]; then
  echo "… kind=merge_in_progress — … not touching it … Stopping the poll."; break
fi
if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
  echo "… kind=detached_head — … Stopping the poll."; break
fi
sync_rc=0; sync_out="$(GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 git fetch origin main 2>&1)" || sync_rc=$?
[[ -n "$sync_out" ]] && printf '%s\n' "$sync_out" | tail -2   # display only — never test this pipe
if (( sync_rc != 0 )); then
  fetch_failures=$((fetch_failures+1)); echo "… kind=fetch rc=$sync_rc — … skipping this sync attempt"
else
  sync_rc=0; sync_out="$(GIT_TRACE=0 git merge origin/main --no-edit 2>&1)" || sync_rc=$?
  [[ -n "$sync_out" ]] && printf '%s\n' "$sync_out" | tail -5
  if (( sync_rc != 0 )); then
    if (( sync_rc == 1 )) && git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      # rc 1 = conflict WE produced: list paths (diff-filter=U + the merge output's CONFLICT lines), abort, stop
    elif git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      # any other rc with MERGE_HEAD: appeared during the fetch window — not ours
    else
      # refused to start: nothing to abort, print `git status --short | head -20`
    fi
    break
  fi
  … push with the same capture; success echo; re-fetch …
fi
```

Plus: every tagged line on stdout with the tick prefix; `behind_exhausted` branches on
`fetch_failures == MAX_BEHIND_SYNCS` (a fetch outage is not "main moving faster than CI");
the DIRTY arm's classifying fetch failure is reported as a fetch failure, not a conflict;
`--is-inside-work-tree` compared by OUTPUT (it prints `false` rc 0 in a bare repo) and gating
the arm via `sync_ok`; the same precondition in `sync-pr-behind.sh` (exit 9), where main's
version aborted a staged resolution on real git (`rc=6, merge_head=no, staged=`).

**The fixture** (`ship-phase-7-poll-fixtures.test.sh`, 18 → 191 assertions): the scenario
subshell runs `set +o pipefail` (under inherited pipefail the *buggy* block takes the right
branch — the vacuity trap, pinned by a quoted-heredoc self-check row that reddens when the
line is removed); `SCENARIO_SET_E=1` re-runs scenario 6 under `set -e`; mock state crosses
`$( )` via files under `$MOCK_STATE`; every scenario runs on both fences; stderr is captured
separately and `[ship.phase7.*]` on it is a failure; scenario 10 runs the ship block on real
git (conflict → clean abort with local HEAD and both remote refs unchanged; pre-staged
resolution survives; push rejected by a pre-receive hook retains the two-parent merge commit;
rebase-in-progress refused with `rebase-merge/` and `UU f` intact; detached HEAD refused);
an anti-vacuity floor of 191 verdicts reported by `printf` + `exit`, outside `pass`/`fail`.
Mutation rows: the plan's 12 + the review's 9 (drop `|| sync_rc=$?`, drop the `rc == 1`
gate, drop the sequencer check, drop the detached guard, drop `sync_ok`, revert the DIRTY-arm
fetch branch, restore one `>&2`, drop the fetch-outage branch, swallow the abort failure) each
RED on the named row; the floor reddens on a no-op `run_scenario` (35 verdicts) and on one
deleted scenario-10 row (176).

## Key Insight

**A guard that reads the *symptom* of a state (MERGE_HEAD exists) is wrong in both directions
against a guard that reads the *cause* (git said rc 1).** The symptom is shared by "we
conflicted" and "someone else was mid-merge", so keying on it aborts the wrong one; and the
symptom is absent for a rebase, so keying on it misdescribes the state git actually refused.
Ask of every precondition: *what set of states produces this observation, and is the action
correct for every member?* Then enumerate the sequencer set from git's own files, not from the
one file the bug report named.

Three companions from the same review, each a claim that read as established:

- **A plan's scope-out is a claim about the platform.** "The older tagged exits use `>&2` and
  are therefore not notification events — a pre-existing property" was scoped out unread; the
  tool schema refuted it in one sentence, and the three exits an operator most needs to see
  had been silent since they were written.
- **The capture idiom the repo teaches for `set +e` shells is a different idiom under `set -e`.**
  `x="$(cmd)"; rc=$?` is the textbook form and it is only correct where errexit is off.
  `rc=0; x="$(cmd)" || rc=$?` is correct in both, costs nothing, and is now what both fences
  and `lint-shell-capture-exit.py`'s docstring describe.
- **A third copy is a third population.** `sync-pr-behind.sh` was "correct on its own" for the
  pipe question (its `pipefail` saw git's rc) and carried the unconditional `--abort` the PR
  existed to remove; the deferral issue's body asserted the opposite until the panel measured it.

## Session Errors

1. **Planning subagent's first `gh issue create` was refused for a missing `--milestone`.** —
   Recovery: re-run with `Post-MVP / Later`. — **Prevention:** the filing gate is documented in
   `review/SKILL.md` §5; pass `--milestone` on the first attempt.
2. **`playwright` MCP disconnected during planning.** — Recovery: not needed. — **Prevention:**
   none required; note it so a later browser step does not read the failure as new.
3. **Mutation battery v1: 14 of 18 rows "MUTATION SCRIPT FAILED".** Python one-liners passed
   through shell single quotes turned every `\$` into a literal backslash-dollar, so `s.count(old)`
   was 0 and the battery — correctly — refused to score. — Recovery: re-authored each mutant as a
   quoted-heredoc `.py` file. — **Prevention:** author mutants as files via `<<'PY'`, never inline
   through a second quoting layer; a battery that refuses to score is the instrument working.
4. **A Bash call bundling a read-only `git stash list` probe with a Python edit was denied whole
   by the stash guard, and I briefly read the edit as landed.** — Recovery: `grep -c` on the new
   anchor returned 0; re-ran the edit alone. — **Prevention:** never put a hook-denied probe and a
   write in one call — the hook denies the CALL; assert the artifact changed after every scripted
   edit (`work/SKILL.md` "a scripted batch edit that fails to parse applies nothing").
5. **Scenario 10 sub-row B's forbid read the whole log and false-redded on sub-row A's
   `Manual conflict resolution required` (79/1 on the GREEN run).** — Recovery: per-sub-row
   `awk` sections; later the shared `assert_log`. — **Prevention:** when one log carries several
   rows, scope every assertion to its own section before asserting a negative.
6. **The plan's `mktemp -d -p "$(dirname "$BLOCK_FILE")"` is not provable-absolute to
   `fixture-scan.py` (`root=other-cmdsubst`); the P1b ratchet went red.** — Recovery:
   `mktemp -d -t <prefix>.XXXXXX` (same TMPDIR, no derived root). — **Prevention:** a plan-
   prescribed path SHAPE is a claim to run the fixture ratchets against before the first commit
   (`work/SKILL.md` 6.6 already says so — it caught it).
7. **Removed the fixture's only `trap … EXIT` (to avoid clobbering the helper's composed
   sandbox cleanup) and left 19 `mktemp`s unowned; `lint-trap-tempfile-ownership` went red —
   a corpus-wide ratchet no file-selected suite set can see.** — Recovery: install the owning
   trap BEFORE sourcing `test-helpers.sh` so the helper composes over it; the review found two
   sibling suites (`sync-pr-behind.test.sh`, `proc.test.sh`) with the inverted order leaking one
   sandbox per run — fixed inline (measured 0 leaks). — **Prevention:** run the repo-global
   ratchets after every guard-shaped commit; when a helper composes a trap, install yours first.
8. **`TEST_GROUP=scripts bash scripts/test-all.sh` refused (rc=4, sibling full-gate in
   flight).** — Recovery: consumer-derived substitute suites (13) + corpus ratchets; the shard
   runs at ship. — **Prevention:** none — rc 4 is its own outcome, handled as documented.
9. **Second review commit reported "nothing to commit": the docs staged by an earlier
   FAILED commit attempt rode into the first review commit.** — Recovery: verified with
   `git show --stat`. — **Prevention:** after a failed commit, `git status --short` before the
   next targeted `git add` — the index keeps what the failed attempt staged.
10. **`lint-skill-body-budget` blocked the review commit: `ship/SKILL.md` was 1,414 B over
    its 274,000 B ceiling after the review prose; three trim rounds.** — Recovery: shortened the
    in-fence comment (agents paste that block) and the expanded prose. — **Prevention:** run
    `python3 scripts/lint-skill-body-budget.py --base origin/main` BEFORE adding prose to a
    lifecycle skill near its ceiling; the lint only fires at commit.
11. **AC1 and tasks 1.10 were ticked carrying "4b's new must-not red", which did not happen
    (4b's mock fix and its forbid landed in the same RED commit).** — Recovery: amended both to
    the measured outcome (31/54; 4b green; the forbid alone measured red against the pre-branch
    mock, 17/1). — **Prevention:** tick an AC only after re-reading its SENTENCE against the run,
    not only its summary line (`work/SKILL.md` "an acceptance checkbox is a CLAIM").
12. **The plan (and my review brief) credited the fixture's introduction to PR #4807; it was
    #4388 (`873ca0e49`), de-orphaned by #4807.** — Recovery: corrected in the plan. —
    **Prevention:** a plan-time git-history claim is an inherited sentence — `git log --follow
    --diff-filter=A -- <path>` before citing an introduction commit.
13. **The plan scoped out the pre-existing `>&2` tagged exits as "not changed" with a
    justification the Monitor contract inverts; I added the new lines on stdout without
    re-checking the old ones.** — Recovery: `ToolSearch select:Monitor` read the contract; all
    tagged exits moved to stdout with a stderr invariant in the fixture. — **Prevention:** a
    scope-out justified by a platform's behaviour is a claim to check against that platform's
    schema, especially when the new code is being written to the opposite convention.
14. **My own fence extraction used loose `phase-7-poll-block` markers and swallowed a prose
    line carrying both `start/end` → a false `bash -n` error.** — Recovery: the fixture's exact
    `<!-- … -->` anchors. — **Prevention:** reuse the extractor under test rather than
    re-deriving one (`cq-assert-anchor-not-bare-token`, one level out).
15. **Mutant R8 (drop the fetch-outage branch of `behind_exhausted`) survived — scenario 8
    asserted `fetch_failures=6/6`, present in both branches.** — Recovery: assert the branch's
    own wording and forbid the other's; scenario 3 pins the converse. — **Prevention:** for every
    `if/else` a fix adds, one row per arm asserting the arm's DISTINGUISHING text, not the shared
    line.
16. **`git rev-parse origin/<branch>` failed "Needed a single revision" right after a
    successful push — the remote-tracking ref had not been fetched.** — Recovery:
    `git fetch origin <branch>`. — **Prevention:** compare against `git ls-remote` or fetch
    first; a push does not populate the tracking ref for a branch created elsewhere.
17. **`rule-metrics-aggregate.sh` failed with `Disk quota exceeded` — its `mktemp -d` landed on
    the `/tmp` tmpfs, which is per-user quota-limited on this host (3.2 G "free" and still
    EDQUOT on a multi-MB spool).** — Recovery: `TMPDIR=/var/tmp bash ./scripts/rule-metrics-aggregate.sh`
    succeeded and the aggregate was staged. — **Prevention:** run the compound aggregation under
    `TMPDIR=/var/tmp` (the same rule `work/SKILL.md` gives for every long-lived artifact); a
    "quota exceeded" on a filesystem `df` reports as 80 % is the tmpfs user quota, not the disk.

## Related

- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` — #7828, the `cmd | tail` rule this arm violated
- `knowledge-base/project/learnings/2026-04-29-canary-layer3-mount-and-pipefail-traps.md` — pipefail semantics
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the harness rows and the vacuity trap
- `knowledge-base/project/learnings/2026-09-18-every-defect-was-in-my-verification-not-the-feature.md` — panel report-only + guards added at review need their own rows
- #8383 — consolidation of the three sync-arm copies (now carrying the corrected "not correct on its own" note and the no-op-push residual)
