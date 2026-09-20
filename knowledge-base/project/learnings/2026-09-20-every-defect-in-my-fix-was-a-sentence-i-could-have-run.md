---
module: Plugin
date: 2026-09-20
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "A `-D` → `-d` ancestry downgrade shipped green through 21 arms and broke the squash-merged cohort — every PR in this repo — because every fixture used `merge --no-ff`, which is always an ancestor"
  - "A comment added in the fix said `git checkout main` refuses on a dirty tree; measured, it succeeds whenever the dirty paths would not be overwritten and carries the edit onto main"
  - "The reaper printed nothing at all for a held branch because the skip line was `verbose`-gated and `verbose` is `[[ -t 1 ]]`; the failure read as a broken merge-evidence block for a round"
  - "A backstop's comment said warn-and-proceed; its code printed `[warn] proceeding:` and then ran `bash \"\"` and `|| exit 1`'d"
  - "Eight mutants survived three batteries: a fail-open helper, a floor where a set was meant, a grace value unpinned between 5s and 27.8h, and a MUST-PASS row whose verdict was a property of the host"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
synced_to: [review, git-worktree, work]
tags: [measured-claim, fixture-shape, verbose-gated, dry-run, mutation-survivor, exact-count, host-independence, superseded-in-place, plugin-root, worktree-reaper, devin-cache]
---

# Every defect in my fix was a sentence I could have run

PR #8418 closed #8400 (worktree-less merged branches skipped every reap guard), #8401 (Step 0 dead on
Devin cloud) and #8402 (the fleet resolved the Devin cache by basename). The fix was reviewed by a
ten-seat panel, a test-design seat, and a QA pass that read the plan whole. Not one defect they found
was in the three issues. Every one was a sentence — in a comment, a fixture, a plan AC, a test's
threshold — that asserted something about git, bash or the tree, that nobody had run, and that was
false.

## Problem

The shape repeated eleven times in one branch, at every phase:

**In the fix.** The first `-D` → `-d` downgrade was correct reasoning about `[gone]` branches and
wrong about every squash-merged one, and no mutation of the implementation could have surfaced it
because the fixture *shape* (`--no-ff`, always an ancestor) could not instantiate the cohort. A
comment I wrote claimed `git checkout main` refuses on a dirty tree; git refuses only when the dirty
paths would be overwritten, so the ordinary case — editing a file that also exists on main — carried
the edit onto `main` for the next session's `reset --hard` to destroy. The resolver's arm 3 fired on
`[ -z "$ROOT" ]`, which *narrowed* Step 0.5 rather than widening Step 0.

**In the diagnosis.** The A9 fixture failed with the reaper emitting no per-branch output at all. I
spent a round on "the merge-evidence block is broken" before the silence explained itself: the branch
had a worktree, so the *worktree* grace arm held it, and that arm's skip line was `verbose`-gated —
`[[ -t 1 ]]`, false under any redirect, false under `claude --bg`. My own worktree-less arm two blocks
below printed unconditionally and its comment gave that exact reason.

**In the batteries.** A test-design pass drove mutants and eight survived at full green:
`remote_branch_exists() { return 0; }` (both call sites expected TRUE, so the one irreversible write
had no witness); a grace widened from 600s to 86400s (fixtures at 5s and 27.8h satisfy any window
between them); a third directory added to the `for d in` list (`-ge 2` is a floor, and `-eq 2` over
*known* spellings still passed); the containment lever `${SOLEUR_DEVIN_CACHE_OPT:-…}` replaced with
the bare literal (green *on this host*, which has no `/opt/.devin/plugins`); `_l2_composite`'s
`-ge 1` threshold (whichever sub-row fired first made the rest free); and the derived-population scan
that was line-scoped while every file it enumerated was written in the multi-line `for d … done`
shape it could not see.

**In the plan.** Its `## Observability` block declared `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED` "new in
this change"; it was demoted during implementation and never existed. FR9 required an allowlist
"holding exactly one entry"; the allowlist was cut. FR11 named `SOLEUR_PRECOMMIT_GUARD_UNRESOLVED`;
what shipped was `…_HALT reason=…`. Each was found only by ticking the AC by running its command.

**In the prose that executes.** `work/SKILL.md`'s commit backstop, on a local session with no
resolvable guard, printed `[warn] proceeding:` and then ran `bash "$GUARD" … || exit 1` on the empty
string. The comment said proceed. The code halted. Found by extracting the block and running it in
both session classes, not by reading it — the panel had read it.

## Solution

Every fix was the same fix: name the command that falsifies the sentence, run it, and pin the answer.

- **Fixture-shape gaps get a fixture, not a mutant.** A9 (`merge --squash`) and A10 (`[gone]` with
  no merge evidence) instantiate the cohorts the `--no-ff` fixtures structurally could not. Merge
  evidence is now computed BEFORE the first write and `-D` is unconditional once we own the decision.
- **A claim about git behaviour is a claim to run.** The dirty-tree state is read once and gates both
  the checkout and the reset (A11 + mutant M3). The comment now records that the earlier sentence
  was measured false.
- **A skip line that can be silent is a skip line that misdiagnoses.** Ungated, and A13 asserts the
  hold names itself with no tty; A2c asserts the worktree-less arm's reason, not only survival.
- **Every irreversible write gets a positive witness.** A3b asserts the remote ref is gone; A3c reads
  the `remote=` field the sentinel already carried. `remote_branch_exists(){ return 0; }` now reds.
- **Cardinality is the arity of the list, not a count of known members.** R9 counts the words of the
  `for d in` line itself; a third execute-from directory reds all three fences.
- **A composite self-test's threshold is an exact count, one break per sub-row class.** Disarming
  either new `check_r9` sub-row now drops the count and is reported by name.
- **A test's own containment lever is asserted, not assumed.** R9 greps the parameter expansion.
- **Prose that executes gets a dry run.** The backstop is now an `if/else`; all five arms measured.
- **A plan sentence that shipped differently is superseded in place**, at every site, with what
  shipped — never silently corrected, never left.

## Key Insight

Reading is not executing, and the sentences that most need executing are the ones that read as
already established: a comment that explains git, a fixture whose shape looks representative, a
threshold that "obviously" catches the mutant, an AC copied forward from the plan. A review panel
reads. A QA phase can run. The panel found the class in principle ("every fixture is `--no-ff`");
only running A9 found that the *replacement* was also wrong, and only running the backstop found
that its comment and its code disagreed.

## Session Errors

1. **Forbidden mechanism inherited from the brief** (plan phase) — #8401's "move the cache arms into
   the shared resolver" is named and prohibited by ADR-179 d11. Recovery: capability feature-detect
   narrowed to `devin-cache`. **Prevention:** grep the ADR corpus for the mechanism's name before
   adopting a brief's approach as the plan's.
2. **Falsified premise "no test drives the reap loop"** (plan) — `lease-protects-active.test.sh` does,
   and its arming stamp is required for Guard 1 mutants to red. **Prevention:** `git grep -l
   <function>` before asserting the absence of a test.
3. **"Verified at plan time" never executed** (plan) — the R6b breakage prediction was reasoned; a
   reviewer ran it and measured the opposite. **Prevention:** a plan may say "verified" only beside
   the command's output.
4. **Unlisted CI gate** (plan) — new sentinels would have reddened `git-lock-marker-telemetry.test.ts`,
   whose scan set derives from the script's directory. **Prevention:** for every new `SOLEUR_*`
   marker, run the telemetry drift guard before the plan lists its gates.
5. **Mis-measured guard population** (plan) — 71 by the stated derivation, not 69; and
   `/opt/.devin/plugins` had no test override. **Prevention:** run the derivation the plan states
   and paste the number; never carry a count forward.
6. **Plan derivation "every `skills/*/SKILL.md` is marked" measured 64/100.** Recovery: kept the
   Anchor's committed sorted set. **Prevention:** a simplification of a guard is a claim to measure
   against the current tree before it replaces the guard.
7. **Mutant harness could not resolve `../../../scripts/lib/session-state.sh`** from a flat
   `$TMP/mutants/`, so the fail-closed stub held every branch and M1/M2 passed for the wrong reason.
   Recovery: build mutants at the shipped script's own depth with a symlinked lib and a presence
   assertion. **Prevention:** every mutant run asserts the SUT's load-time sentinel
   (`LEASE_LIB_OK`) before reading its verdict.
8. **M3 deleted the check instead of reordering it** — Guard 1 row 5 requires a reorder. Recovery:
   rewrote the perl to restore the pre-fix ordering. **Prevention:** a mutant models the *stated*
   mutation; "removes the guard" and "moves the guard below the write" are different rows.
9. **L2 decider self-test silently no-op'd** — its fixture anchored on `[ -n "$ROOT" ] || SRC=none`,
   a line my change removed. Recovery: re-anchor on the RESOLVE echo and make `sub()` raise on a
   non-landing edit. **Prevention:** every fixture edit asserts it landed (`out == text → raise`).
10. **Nested triple-quotes in a Python heredoc** → SyntaxError, edit silently not applied.
    **Prevention:** heredoc-driven edits print `ok` on success and are followed by a grep.
11. **Byte-ratchet breach found only by a repo-global gate** — `postmerge` had 2 bytes of headroom.
    Recovery: tightened the block and extracted two sections to `references/`. **Prevention:**
    `work/SKILL.md` §"a file-selected suite set cannot see a repo-global ratchet" — run them by hand.
12. **`WM="${ROOT}/…"` indirection broke ADR-179's anchoring contract** (P1/P8). Recovery: inlined.
    **Prevention:** the anchoring test is in the diff-selected set; run it before committing a fence.
13. **Three blocking defects in my own fix, two by measuring a sentence** — the `-D`→`-d` downgrade
    (fixture-shape), "checkout refuses on dirty" (false), arm 3 on `-z "$ROOT"` (narrowing).
    **Prevention:** for every causal sentence the diff ADDS, name the falsifying command and run it
    (`review/SKILL.md` §"check every claim the diff's PROSE asserts").
14. **A9 misdiagnosed for a round** — the worktree grace arm's `verbose`-gated line produced total
    silence. **Prevention:** a reaper that prints nothing per-branch is a diagnosis in itself: grep
    the SUT for `verbose`-gated lines on the path before reading any guard's logic.
15. **Enumeration comment carried two cancelling errors** (AGENTS.md left, the test file entered; 71
    both ways) and my edit's anchor missed on a wrap. **Prevention:** derive the membership list in
    the comment from the same scan the test runs, or state only the property.
16. **`fixture-relative-assert` moved 1543→1545** by two new `printf > "$ws/.mcp.json"` lines —
    invisible to diff-derived selection. Recovery: `assert_fixture_dir "$ws"` before each.
    **Prevention:** same as 11; every new fixture write gets its guard in the same edit.
17. **`bunx vitest` ran in the MAIN repo** — `cd apps/web-platform` resolved outside the worktree
    because the path exists there too, and the result described the wrong tree. Recovery: re-ran
    with the worktree-absolute path. **Prevention:** in a worktree, never `cd` a relative path that
    also exists at the bare root; use `$PWD`-anchored absolutes.
18. **`pgrep -f "lefthook run"` self-matches** — the guardrail blocked it, and my Monitor's
    "lefthook gone" arm used the same pattern and was permanently false. **Prevention:** `pgrep
    <name>` or `/proc/<pid>/cwd` ownership (`proc.sh`), never `-f` from inside a wrapper.
19. **Commit wedged 41 minutes on the repo-global `test-all.lock`** — another worktree held it 1h47m
    with three more queued; `SOLEUR_ALLOW_FULL_GATE=1` in the hook turned the sanctioned refusal into
    an unbounded `flock -w 3600` queue. Recovery: killed my tree by `/proc/<pid>/cwd`, ran the two
    unrun steps by hand, committed `LEFTHOOK=0` with the substitution disclosed. **Prevention:**
    file-tracked — the pre-commit gate should bound its wait (e.g. `-w 300`) and refuse with the
    #7553 message rather than queue behind an unbounded sibling.
20. **`n_cache -eq 2` did not kill the third-directory mutant** — it counted known spellings.
    Recovery: count the `for d in` list's own words. **Prevention:** a cardinality pin counts the
    container, never occurrences of expected members.
21. **JSDoc comment containing `*/` (a glob) closed the block comment** → syntax error.
    **Prevention:** glob patterns in TS comments go in `//` lines.
22. **`MIN_ASSERTIONS=181` while 184 ran** — forgot `check_r9` runs per gate. Exactness caught it.
    **Prevention:** set the floor from the run's own count, in the same edit, then re-run.
23. **Test-design seat measured a moving tree** — its baseline (177/1/178) was a snapshot taken
    while I was editing underneath it. **Prevention:** spawn report-only seats at a SHA and apply
    from that SHA; a seat that re-copies mid-run reports on no tree in particular.
24. **Plan ACs FR9/FR11 named artifacts that never shipped.** Recovery: superseded in place.
    **Prevention:** QA ticks each AC by running the command it names; a marker or file an AC names is
    `ls`'d, not remembered.
25. **`work/SKILL.md` backstop: comment said proceed, code halted** (`bash ""`). Recovery: `else`
    arm; five arms dry-run. **Prevention:** `qa/SKILL.md` — prose that executes gets a constrained
    dry run in every branch the comment claims, not a read.
26. **`MIN_ASSERTIONS` raised four times from LOCAL counts** (178, 184, 190, 196) while the
    comment above it said "the H3-SKIPPED total; H3 running adds two more". CI has no `claude`
    binary, ran 194, and reddened. Recovery: floor 194, measured with `SOLEUR_GO_GATES_SKIP_H3=1`.
    **Prevention:** a floor whose comment names an environment-dependent arm is measured on the
    arm that runs in CI, with the lever the suite provides for that purpose.
27. **`lint-shell-capture-exit` reddened CI on two new `x="$(… | grep …)"` captures** with no
    `|| true` — the fourth repo-global ratchet this branch reached only by running it, after
    `fixture-relative-assert` (twice) and `skill-body-budget`. **Prevention:** before every push,
    run the ratchets `test-all.sh` registers under `scripts/lint-*-live` with their baselines —
    they reference no changed file and never appear in a diff-derived selection.

## Related

- [The gate that caught it was the one suite I had no reason to run](2026-09-20-the-gate-that-caught-it-was-the-one-suite-i-had-no-reason-to-run.md) — same repo-global-ratchet class (errors 11, 16).
- [Every instrument that answered instead of failing](2026-09-20-every-instrument-that-answered-instead-of-failing.md) — fail-open helpers and floors (errors 7, 20, 22).
- [Every defect was in my verification, not the feature](2026-09-18-every-defect-was-in-my-verification-not-the-feature.md) — records asserting delivery that the deletion never swept (error 24).
- [I tested both endpoints and left the wire between them unpinned](2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md) — the block-scoped detector is the seam this learning prescribes.
- ADR-179 A16; plan `plans/archive/20260920-210944-2026-09-20-fix-plugin-root-cloud-mode-resolution-plan.md`; PR #8418; scope-out tracker #8440.
