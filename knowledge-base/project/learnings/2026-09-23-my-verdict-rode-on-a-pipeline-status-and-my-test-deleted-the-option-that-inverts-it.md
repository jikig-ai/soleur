---
title: "My verdict rode on a pipeline's exit status, and my test deleted the option that inverts it"
date: 2026-09-23
category: test-failures
module: plugins/soleur/skills/ship
issue: 8470
pr: 8567
tags: [guards, mutation-testing, bash, pipefail, fixtures, probes]
---

# Learning: a probe's verdict must not ride on a pipeline's exit status, and a discriminator row is vacuous until its fixture makes the two spellings disagree

## Problem

#8470: ship Phase 2 decided whether `soleur:compound` had run by asking git a
repo-wide calendar question — `git log --oneline --since="1 week ago" --
knowledge-base/project/learnings/`. That window was non-empty in 12 of 12 sampled
weeks, so the answer was always "a learning exists", the feature-scoped follow-up
check was unreachable, and compound never ran. 38 of 51 `review → ship` rows
showed no compound after review.

The fix replaced it with a branch-scoped probe printing one token
(`BRANCH_LEARNING=present|absent`) plus a suite that extracts the block from
`ship/SKILL.md` and executes it against fixture repositories. That suite was
green at 14/14, with an author-run 14-row mutation battery reporting every mutant
killed. A ten-seat review panel then found five P1s, **every one of them in the
verification rather than in the feature**.

## Solution

### 1. The verdict rode on a pipeline's exit status

The block ended:

```bash
{ …arms… } | grep -q . && echo "BRANCH_LEARNING=present" || echo "BRANCH_LEARNING=absent"
```

Two independent inversions under `set -o pipefail`, both toward `absent`:

- the brace group's status is its LAST command — a trailing `grep -E` that
  matches nothing exits 1, so a learning found by an EARLIER arm still reports
  `absent`;
- `grep -q` exits on the first byte, the still-writing producer takes SIGPIPE
  (141), and the pipeline is non-zero on a SUCCESSFUL match.

On a `pipefail` shell `present` is therefore close to unreachable — the #8470
defect mirrored, a probe whose output is decoupled from reality. This repo had
already banned the shape for hooks (`.claude/hooks/grep-q-pipe-guard.test.sh`,
"reports FAILURE on a SUCCESSFUL match"); the ban simply did not reach a skill.

The fix is to stop reading a pipeline's status at all — capture and test the
string:

```bash
if [ -n "$( { …arms… } 2>/dev/null )" ]; then echo present; else echo absent; fi
```

**The suite could not see any of this, because it deleted `SHELLOPTS`,
`BASHOPTS`, `BASH_ENV` and `ENV` and ran `bash --noprofile --norc`.** That scrub
is correct for hermeticity and it removed the one variable that flips the
verdict, so the harness was green on a shell no harness actually hands the agent.
The repair is both: keep the scrub AND add rows that drive `set -euo pipefail`
explicitly.

### 2. A discriminator row is vacuous until its fixture makes the two spellings disagree

The probe names `refs/remotes/origin/main` because `origin/main` as a REV
resolves `refs/tags/` first, so a pushed tag of that name would steer the
verdict. I wrote a row for it: create a tag `origin/main` at the root commit,
expect `absent`.

It passed — and the mutation that reverts the spelling to `origin/main`
**survived**. The fixture's root commit already contained the learning, so both
spellings produced the same range and the row discriminated nothing. Only running
the battery surfaced it; reading the row does not, because a row that passes for
the wrong reason looks exactly like one that passes.

Litmus, before trusting any row that exists to pin a SPELLING: *construct the
state where the two spellings give different answers, and assert the row fails
under the other one.* Here that meant advancing `main` with a learning AFTER the
branch point, merging it, and pointing the tag BEFORE it.

### 3. The axis a fixture set can silently omit

Rows 1–11 all built `origin/main` AT the branch point. That made three distinct
mutations invisible at once — `..`→`...`, `refs/remotes/origin/main`→`main`, and
replacing the `git fetch` with a reachability ping — because none of them can
change an answer when the range's left edge and the tracking ref agree. The
battery had 14 rows and one axis.

## Key Insight

**A green mutation battery is evidence about the mutations its author imagined,
and the author imagines mutations of the thing they were thinking about.** Three
of this PR's five P1s lived on axes the battery never edited: the SHELL the block
runs in, the FIXTURE's ability to discriminate, and everything outside the fenced
block (the prose that consumes the token, the headless bullet, a second
`## Phase 2` heading, an indented code block).

The generalisation that would have caught all three: for each guard, name the
property in one sentence, then ask *what does this check read, and who controls
it?* — `pipefail` is controlled by the operator's profile, `origin/main` by
anyone who can push a tag, and the verdict→action mapping by prose nothing
asserted.

## Prevention

- A guard's verdict must never be a pipeline's exit status when the shell's
  options are not yours to set. Capture the output and test the string.
- When a repo bans a shape for one surface (`hooks/`), grep the other surfaces
  before assuming the ban travelled. It had not.
- For every row that pins a SPELLING, assert the fixture makes the alternative
  spelling disagree; otherwise the row is a shape check wearing a discriminator's
  clothes.
- Sweep a fixture set by asking which STATE VARIABLE never varies across it. Here
  it was the position of `origin/main` relative to the branch point.
- A suite that pins a token must also pin the dispatch that consumes it, or the
  meaning of the token can be inverted in prose with the suite fully green.

## Session Errors

1. **Ran a substitute suite at a guessed path** (`plugins/soleur/test/guard-vacuity-floor.test.sh`,
   exit 127 — it lives at `scripts/guard-vacuity-floor.test.sh`). The 127 was
   recorded in the substitute-set table next to fourteen zeros, where it reads
   like a result. — Recovery: re-derived the path from its `run_suite`
   registration in `scripts/test-all.sh`. — **Prevention:** derive every suite
   path from its registration, never from where a sibling suite happens to live;
   and treat a 127 in a results table as UN-RUN, never as a verdict.
2. **Mutation-battery anchor missed on indentation** (a 4-space-indented literal
   against a 2-space line). — Recovery: the battery's `assert s.count(a)==1`
   caught it before any file was written. — **Prevention:** none needed; this is
   the anchor assert doing its job, and it is why the battery must never fall
   back to a silent `str.replace`.
3. **Wrote a vacuous discriminator row** (the `origin/main` tag row, §2 above) —
   it passed while the mutation it existed to kill survived. — Recovery: the
   battery reported `N3 … GREEN (want RED)`; rebuilt the fixture so the two
   spellings disagree. — **Prevention:** the litmus in §2; a row that pins a
   spelling owes a fixture in which the other spelling is wrong.
4. **The new `--since` backstop flagged the prose that explains it** — the
   documented "grep assertion false-matches its own comments" class
   (`cq-assert-anchor-not-bare-token`), hit again inside a test written by
   someone who had just read that rule. — Recovery: scoped inline-code spans to
   those containing a command (a space), leaving the bare `` `--since` ``
   mention alone. — **Prevention:** when a task requires both "assert X is
   absent" and "explain why X was removed", the explanation is part of the
   haystack; decide the exclusion at the same time as the assertion.
5. **Spawned ten review agents at once and hit the account's weekly rate limit** —
   7 of 10 terminated early (`HTTP 429`), two of them after doing real work whose
   transcripts were still live. — Recovery: resumed each via `SendMessage` in
   batches rather than re-spawning, which preserved their partial findings; all
   seven completed. — **Prevention:** a killed agent is RESUMABLE — resume, never
   re-spawn (a fresh spawn discards the transcript AND re-spends the budget that
   was just exhausted).
6. **Left a run-log directory (`.soleur-runs/`) in the worktree.** Harmless (it is
   gitignored) but it is scratch state in a tracked tree. — **Prevention:** write
   long-lived run logs under `/var/tmp` unless a later turn must find them by a
   stable name.

## Related

- `.claude/hooks/grep-q-pipe-guard.test.sh` — the pre-existing ban this probe
  contradicted, scoped to hooks only.
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`
  — amended here; its re-measure `SINCE` had the same class of defect (a
  `%cI` timestamp carrying a local offset, compared lexically against `Z`).
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
