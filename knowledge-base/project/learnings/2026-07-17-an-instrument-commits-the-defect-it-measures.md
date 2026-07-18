---
name: an-instrument-commits-the-defect-it-measures
description: A probe built to catch unmeasured counts committed that exact defect six times; the failures all pointed the same way — toward a smaller, cleaner, wronger world.
metadata:
  type: project
  category: workflow-patterns
  module: infra
---

# Learning: an instrument built to catch a defect will commit that defect

## Problem

A prior fix (merged 2026-07-17) proposed tracking ~31 sibling shell-guard files
using a "~230 affected sites" figure. The second-opinion gate rejected it: the
number counted where the code *pattern* appeared, not where the *bug* could occur.
#6578 asked for the missing step — measure first.

So this PR built a probe to answer "can this class be triaged at all?" **The probe
then committed the same defect it was built to detect, six separate times.**

## Solution

Two adversarial reviews found all six. Every one was caught by *running* something,
never by reading:

| defect | shape |
|---|---|
| counted comments/fail-messages as sites | syntax count sold as relevance count |
| counted `\|\|` as a pipe | `a \|\| grep -q P FILE` feeds grep no stdin |
| counted **itself** once committed | the instrument is in-corpus; its preflight has a real `\| grep -q` |
| discarded heredoc bodies in `.yml`/`.tf` | those bodies ARE the payload that runs on the host |
| counted matching LINES, not occurrences | fold-pipes merges two real pipes onto one line |
| `unbounded = 0` from 4 anchoring bugs | each made a site *vanish* rather than misreport |

## Key Insight

**The failures were not random — every one shrank the corpus.** An instrument that
silently drops what it cannot parse reports a smaller, cleaner, wronger world, and
each drop *looks like rigour*. That asymmetry is why none of them announced itself:
a bigger number invites scrutiny; a smaller one reads as a clean bill of health.

Three rules follow, each measured rather than reasoned:

1. **A measurement tool must fail LOUD on a broken pipeline.** `count_sites` called
   an undefined function; every payload file scored 0, the corpus shrank, and the
   shrink read as a real finding. A tool whose broken state is indistinguishable
   from its clean state cannot be trusted for either.

2. **Identity does not imply behaviour.** The plan's gate said "assert `grep
   --version` reports GNU". This host resolved GNU grep 3.12 and still drained,
   because a shell *function* shadowed it — the version check passes while every
   reading is 0/N. Gate on the behaviour that matters (`does it early-exit?`), not
   the name. The reviewer sent to audit this was caught by the same wrapper.

3. **A gate can guard a failure its subject cannot have.** The preflight's stated
   reason ("a draining grep makes every reading 0/N") was false — measured by
   neutralising the gate and diffing runs: identical. Meanwhile the *real* false
   all-clear sat unguarded: run from any subdirectory, `git grep`'s cwd-relative
   pathspec matched nothing, and the empty corpus **flipped the arm from TRACK to
   CONVERT** at exit 0 — recommending conversion of a class it never looked at.
   Guarding the fiction while the real door stood open is the characteristic shape.

**Corollary — borrowed credibility is a borrowed count.** A comment claimed the
normalisation was "lifted verbatim from scan-workflow.test.sh:138-142, where it is
already proven". Those lines are a prose comment, and that file has no heredoc or
`||` handling; the two steps carrying the headline were new and proven by nothing.

## Session Errors

1. **Uncommitted verified work silently reverted, twice.** `worktree-manager.sh`'s
   "sync on-disk files from git HEAD" restored files to HEAD mid-session, discarding
   verified edits. Worse: `python str.replace()` no-ops on a missing anchor, so the
   reconciliation scripts printed "ok" against reverted files. Caught only when a
   re-run printed numbers contradicting a result verified minutes earlier.
   **Prevention:** routed to `work` SKILL.md — commit each verified unit immediately;
   do edit+commit in ONE Bash call; assert the anchor or the edit is unverified.

2. **`/one-shot` aborted twice on self-authored args.** The closed-issue gate fired on
   `#6572` — scrubbed from prose on the second try, but still present inside a quoted
   issue title (`decision-challenge: … while fixing #6572`). The gate was right both
   times; the args were mine. **Prevention:** routed to `go.md` — grep constructed
   args for `#[0-9]+` and scrub quoted titles too, not just prose.

3. **E2 passed vacuously.** A guard copy placed in `$SANDBOX` instead of the mirrored
   `$PROBE_DIR` died on a missing artifact before reaching the rung under test: E1 red
   for the wrong reason, E2 green because its message was absent for that same wrong
   reason — a vacuous green inside the harness that exists to catch vacuous greens.
   **Prevention:** both rungs now refuse to read a mirror failure as a verdict
   (`FATAL: missing` precondition). Fixed inline.

4. **A self-imposed `timeout 900` killed the test suite**, and the `> /tmp/log`
   redirect hid output from the harness's completion notification, so "killed" looked
   like a result. **Prevention:** already covered by the work skill's background-task
   rule; one-off.

## Tags
category: workflow-patterns
module: infra
