# Learning: a green lock suite and a 10-row mutation battery still shipped a stealable lock

## Problem

P4c of #10924 added a per-(repo, PR) lock to `monitor-pr-checks.sh` so a second monitor is refused (rc 4) instead of
layered beside the first. The first implementation passed its own 54-assertion suite and a 10-mutant battery. A
9-seat review then found, with reproductions, that the lock could be stolen from a live holder and that the battery
could not tell a kill from a setup failure.

## Solution

- Lock: a symlink holding `pid|lstart|epoch`, reclaimed when the holder is dead, a zombie, pid-reused or has no start
  time, released by the single EXIT trap (no TERM trap, so a stopped watch frees it in about a second).
- Review fixes, each pinned by an arm that goes red when the fix is reverted in a sandbox copy: a record naming our own
  pid with a foreign start time is rewritten, not adopted; the stale-reclaim is serialised under a `mkdir` guard
  (two contenders both won in about 20% of two-racer rounds); the PR number is normalised (`007` is `7`) and numeric
  fields are read as decimal and length-bounded (`08` aborted the acquire); the lock dir must not be group/other
  writable; the key follows `--repo`, then `GH_REPO`, then `git remote get-url` (which resolves `insteadOf`);
  `GH_HOST` on another host fails open.
- Suite fixes: a check returns 2 for its own setup failure and only 1 counts as a kill; the `ps` stub refuses
  unexpected argv; the self-test exits directly instead of reporting through the helper it tests; the floor is the
  exact arm count and counts skips.

## Key Insight

Three independent classes, all invisible to the author's own green run:

1. A battery that scores any non-zero return as a kill measures its own setup. `hold()` waited for a lock link named
   after the unmutated key, so the two key mutants timed out in setup and were credited as kills.
2. A record field read back from disk is input, not state: a leading zero is octal, an empty field skips a check, a
   field equal to our own pid is not proof of ownership. Validate every field the way a hostile writer would fill it.
3. An exclusion guarantee needs the compare AND the remove under one guard. `[ "$(readlink l)" = "$stale" ] && rm l`
   is two operations; with two contenders the second removes the first's fresh lock.

## Session Errors

- **Stub `ps` rejected its own argv (count 7, lib sends 8).** Recovery: counted the argv words. **Prevention:** derive a strict stub's expected argv from the SUT's call by running it once, not by counting by hand.
- **`newdir` counter lost in a `$(...)` subshell, so every arm shared one lock dir.** Recovery: `mktemp -d`. **Prevention:** helpers called through command substitution must be stateless (already in `work/SKILL.md`).
- **`ln -s` into an existing directory creates the link inside it.** Recovery: refuse a real directory before `ln`, use `-n`. **Prevention:** U3d/U3f pin both.
- **`hold()` waited on a derived link name, making key mutants vacuous.** Recovery: wait for any `*.lock`; checks return 2 on setup failure. **Prevention:** a mutant counts as killed only when the targeted check returns the guard-failed code.
- **Counted `--agents-expected` from every seat considered, so the trailer said `degraded 9/11`.** Recovery: reset the two unpushed empty commits and re-emit with the panel the skill's own substitution rules prescribe. **Prevention:** a comment above `usage()` in `plugins/soleur/skills/review/scripts/emit-review-trailer.sh` (not `review/SKILL.md`, whose body ceiling has 27 bytes of headroom).
- **Affected gate rc=6 (queued behind sibling runs, zero suites ran).** Recovery: recorded CI as the authoritative gate and ran the consumer suites directly. **Prevention:** this is exactly what P4d (bounded wait, then "CI is the gate") addresses.
- **Plan premise: "the report-only hook backs up the script lock".** The hook's `monitor_sig` yields no signature for the canonical command. Recovery: corrected the harness prose, filed #11312. **Prevention:** run the extractor on the command a doc claims it covers before writing the claim.
- **Tool refusals** (write after external mtime change, `rm -rf "$(…)"`, `pgrep -f`, chained `sleep`, issue-filing gate, duplicate Monitor): one-offs; each recovered by the dedicated path the message named.

## Tags
category: logic-errors
module: plugins/soleur/scripts/monitor-pr-checks.sh
