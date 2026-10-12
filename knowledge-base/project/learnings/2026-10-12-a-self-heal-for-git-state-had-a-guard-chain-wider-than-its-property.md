# Learning: a self-heal that writes git state had a guard chain wider than the property it named

## Problem

The bare repo root's `.git/HEAD` was left naming a deleted branch after a PR merged, so
`git rev-parse HEAD` failed there, the SessionStart `[session-context] branch:` line read `HEAD`,
and `worktree-manager.sh sync-bare-files` (`git read-tree HEAD`) could not refresh the root.
The ask was a zero-token, fail-open repair inside the existing SessionStart hook
(PR 10105: `bare-head-self-heal.sh`, called from `session-rules-loader.sh`).

## Solution

A child-process helper that runs `git symbolic-ref HEAD refs/heads/main` only when ALL hold:
`<dir>/.git` is a real directory (not a file or symlink), its config FILE says `core.bare=true`,
git resolves to exactly that directory, HEAD names a `refs/heads/*` branch whose `show-ref --verify`
rc is exactly 1 (missing, not 128 corrupt), and `refs/heads/main` exists. The write runs with
`-c core.hooksPath=/dev/null -c core.fsmonitor=false`; inherited `GIT_*` location variables are
unset; the marker's old ref is allowlisted to `[A-Za-z0-9._/-]` and capped at 80 characters; the
loader takes only the first line behind a prefix test and time-boxes the call.

## Key Insight

My first draft passed its own 10-row mutation battery and still had three P1s in the guard chain,
because every row mutated a predicate I had written and none asked whether the chain's POPULATION
equalled the property: an inherited `GIT_DIR` overrides `cd`; `--is-bare-repository` is also true
for mirrors and, under a masked config, for any normal clone (ADR-173 says read `core.bare` from
the config file); `show-ref --verify` rc 128 (ref exists, object missing) is corruption, not
"dangling". Pin the LAYOUT the helper was designed for by a positive identity (`.git` directory +
config file + git-dir equality), never by predicates a different layout also satisfies. Eleven
review seats then found 62 items, and the one instrument that found the P1s was the structural
enumeration seat, not any adversarial one.

Two measurement lessons from the tests:

- A positive CONTROL must not share the write it measures. H17's hook control fired during the
  fixture's own `symbolic-ref` write, so the "no hook ran during the repair" assertion failed for
  the wrong reason; and the first control used `update-ref` while the helper writes with
  `symbolic-ref`. Make the control the same operation, then clear the marker before the act.
- The author's "equivalent mutant" label was wrong for the git-dir gate: a nested skeleton
  `P/sub/.git/config` under a dangling root heals the PARENT when only that gate is dropped. Prove
  equivalence by building the fixture that would distinguish, not by reasoning that another gate
  also fails.

## Session Errors

1. **Scratch harness swept from `/tmp` between turns.** Recovery: recreated under `/var/tmp`.
   **Prevention:** put any harness that must survive a turn in `/var/tmp` or the worktree, never
   `/tmp` (already documented in work/SKILL.md).
2. **Two scripted edit batches aborted on anchors I wrote from memory.** Nothing was written (the
   batch asserts before writing); caught by the unchanged suite count and `git status`.
   **Prevention:** `sed -n` the exact text before anchoring a multi-edit batch, and print the
   changed line back afterwards.
3. **First `git push` rejected by the remote (`remote rejected (failed)`).** Recovery: retry
   succeeded. **Prevention:** none beyond reading the full push output before diagnosing.
4. **Affected gate unreachable under host contention** (six sibling `test-all.sh` runs, 22+ minutes
   queued at position 5). Recovery: killed my queued run, ran the repo-global ratchet suites that
   the diff could move individually, and deferred the gate to ship Phase 4. **Prevention:** run
   `scripts/test-all.sh --capacity` before launching and run the cheap ratchets first; they found
   two real hits (fixture-relative, fixture-dir-operand) in minutes.
5. **H17 control shared the fixture's own write** (see Key Insight). **Prevention:** a control is
   the same operation as the act under test, executed before the marker is cleared.
6. **Plan ADR check grepped defect nouns, not subsystem nouns.** `symbolic-ref` and `dangling HEAD`
   missed ADR-173 (bareness) and ADR-099, which govern the bare-root layout. **Prevention:**
   routed to the plan skill's Sharp Edges (see below).
7. **Three P1s in my own guard chain** (above). **Prevention:** for a guard-shaped deliverable run
   the structural-enumeration seat BEFORE trusting a self-run battery; it is already specified in
   review/SKILL.md and cost one seat.
8. **Stop hook flagged gerund announcements while waiting on background seats.** Recovery: ended
   waiting turns with an explicit `BLOCKED:` stop tag naming the seats. **Prevention:** when only
   background work remains, say what is awaited in the stop tag instead of announcing the next step.
9. **Mislabelled which seat a report came from** (called the security seat's report data-integrity).
   Recovery: corrected in the next message. **Prevention:** none; one-off.
10. **Planner-written plan failed markdownlint (MD022/MD032).** Recovery: added blank lines.
    **Prevention:** none; one-off.

## Tags

category: workflow-patterns
module: .claude/hooks (SessionStart loader, bare-root HEAD self-heal)
