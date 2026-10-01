---
title: "I documented a mutant as EQUIVALENT and told the next reader not to kill it — it was reachable"
date: 2026-09-06
category: test-failures
module: test-all
tags: [mutation-testing, guards, false-green, span-replacement, capacity, adr-181]
symptom: "A guard's own comment asserted an equivalence that was false, and two index-based text edits silently deleted sibling lines"
root_cause: "Claims about a guard were asserted from reasoning rather than measured, and text edits were scoped by byte index rather than by anchor"
related_prs: [7870]
related_issues: [7869]
---

# Learning: the claims I made about my own guards were the defects

## Problem

#7869: a `scripts/test-all.sh` run whose owning session dies keeps working through its
suite list holding the repo-global advisory lock. Two guards shipped — a runtime ceiling
on the holder, and a stale-sibling filter so an orphan cannot pin full-gate capacity at
zero. Both were green, mutation-proven, and wrong in ways only review found.

Six merge-blocking defects, **all in the guards or in the claims about them**, none in
the mechanism.

## Key insights

### 1. A documented EQUIVALENT mutant needs the enumeration of input shapes it surveyed

I wrote, in the code and echoed in the test:

> THE `$3 ~ /^[0-9]+$/` TERM IS UNREACHABLE-BY-CONSTRUCTION AND KEPT ANYWAY. Mutating it
> away is an EQUIVALENT mutation, verified rather than assumed … Recorded here so the next
> reader does not spend a round trying to write the fixture that kills it.

Every clause was confident and the conclusion was false. The producer's `elapsed` field is
always numeric — true. But the filter reads `$3` of a *projected* row, and rows are
TAB-separated: a worktree path **containing a tab** shifts every field right, so `$3`
becomes a cwd fragment. Measured, for `wt<TAB>99999x` holding a 60-second-old run:

```
sibs field 3 = "99999x"   numeric? NO
with the term:    counted   (the gate refuses — correct)
without it:       EXCLUDED  (awk coerces "99999x" -> 99999 >= 14400)
```

Dropping the term silently admits a **live** sibling. The comment was worse than absent:
it instructed the next reader not to write the fixture that finds it.

**Prevention:** an equivalence claim must carry the enumeration of input shapes it
surveyed, so a reader can see which shape was missed rather than being told not to look.
"The producer cannot emit X" is a claim about the producer; the guard reads a *projection*
of the producer, and the projection is a different value.

### 2. One derivation serving two questions answers one of them with the other's instrument

The filter was placed at the single `sibs=` derivation, argued for on count-vs-report
parity grounds. That derivation feeds two consumers asking different questions:

- `tc_capacity_line` / the `-> pid` rows: *can this box absorb another gate?* An orphan
  still burns CPU and tmpfs — it counts.
- the exported refusal operand: *is anyone reading the run already in flight?* An orphan
  is exactly what that must ignore.

Filtering the shared derivation made `--capacity` print `CAPACITY_OK measured_runs=0` with
a 46-hour orphan live — an idle verdict on a wedged box, in the one diagnostic
`work/SKILL.md` routes the operator to from the lock-wait banner.

**Prevention:** before placing a filter at a shared derivation, list its consumers and ask
whether they are asking the SAME question. Parity of count-and-report is about
non-atomic snapshots, not about policy.

### 3. A guard that curtails must keep its declines in the denominator

The early `return` sat above `suites=$((suites + 1))`, so declined suites left both
numerator and denominator and the terminal marker printed `=== 1/1 suites passed ===` on a
run that never started 2 of 3 suites — while `rc` was correctly 3. That marker is this
repo's documented completion anchor. ADR-181 records the identical defect for relevance
declines ("a green that is not evidence, produced by the very change that added the gate"),
30 lines below the code that reproduced it.

**Prevention:** when a change adds a new way to NOT run a suite, the summary line is part
of the change. Assert the marker text, not only the exit code.

### 4. Index-scoped text edits swallow siblings — twice, in one session

Two edits scoped by byte index (`s[start:end]`) silently deleted a line between the
anchors:

- `suite_sibs=$(awk ...)` sat between the filter comment and the next marker → 7 sibling
  assertions broke, all reporting suite-sibling failures with no obvious cause.
- `suites=$((suites + 1))` sat between the ceiling block and `local tmp_before=` → the
  block was re-inserted after the *first remaining* increment, which was in `skip_suite`,
  and the runner executed **zero** suites.

Both were caught only by running the FULL suite, never by the new arms. This is the
documented "`indexOf` block scoping swallows siblings" class, hit twice by someone who had
read it.

**Prevention:** replace by ANCHOR with `count == 1`, never by index span. When a span is
unavoidable, print the extracted text and assert what it does NOT contain.

### 5. An errored command's empty output is not evidence of absence

`git grep 'all\.rc'` run from the bare repo root failed with `fatal: this operation must be
run in a work tree`. The error was not noticed, the empty result stood in for evidence, and
the issue's `all.log`/`all.rc` premise survived several plan revisions as property P4. Re-run
from the worktree it returns **zero** occurrences repo-wide — the artifacts do not exist.

**Prevention:** the repo already states this for telemetry ("an empty query is not evidence
of absence until you have verified the signal is instrumented"). It applies to local
commands: check the exit code before reading a count as zero.

### 6. Re-asserting a framing the record already retracted

I wrote that ADR-133's addendum "records siblings legitimately **holding** 3775/5787/5763 s".
That addendum published a correction saying precisely the opposite — the figures are
elapsed-at-probe on three runs executing *concurrently*, and at most one held the lock —
and I attributed it to the wrong addendum besides. The retraction sat ~60 lines above my
own text in the same file.

The nuance that makes it a correction rather than a revert: for a RUNTIME CEILING the
operand genuinely is elapsed runtime, so the numbers stand for this knob. The word
"holding", the attribution, and "worst observed maximum" do not.

**Prevention:** when quoting a figure from a dated record, read the record's later
addenda for a correction before restating its framing.

## Session Errors

1. **A planning subagent stalled twice** (harness watchdog, no progress for 600s).
   **Prevention:** on a stall, check for a partial on-disk artifact and continue INLINE
   rather than re-spawning; the plan-artifact recovery contract already prescribes this.
2. **`git grep` run from the bare repo root errored; its empty output was read as evidence.**
   **Prevention:** see insight 5 — check the exit code before treating a count as zero.
3. **Two review agents died** (one API timeout, one stream watchdog), so the per-mechanism
   simplicity pass and one correctness pass did not run in the plan panel.
   **Prevention:** name the missing agents in the summary rather than reporting full coverage.
4. **`str.replace` without a count inserted a block twice**, once mid-sentence inside an
   unrelated section, because a backticked mention of the anchor matched first.
   **Prevention:** always pass a count and assert the occurrence count first.
5. **Two index-scoped span edits swallowed sibling lines.** **Prevention:** see insight 4.
6. **A mutant was documented as EQUIVALENT and was reachable.** **Prevention:** see insight 1.
7. **A retracted framing was re-asserted.** **Prevention:** see insight 6.
8. **A shared derivation was filtered for one consumer's policy.** **Prevention:** see insight 2.
9. **Declines were dropped from the denominator.** **Prevention:** see insight 3.
10. **The repo's own `10#` idiom was not carried into new arithmetic**, so a zero-padded
    ceiling was read as octal by bash and decimal by awk — two parsers, one knob, diverging
    below the documented healthy band. **Prevention:** when adding arithmetic on a value a
    sibling consumer also parses, grep the file for how the existing code normalises it.
11. **A guard whose premise is "no consumer" shipped with no CI exemption**, under a job
    timeout larger than the ceiling. **Prevention:** when a guard's justification names a
    consumer, enumerate the environments where that consumer exists.
12. **An early `return` broke a caller's invariant** (`_infra_ran=1` recorded coverage for a
    suite that never started). **Prevention:** when a function gains a "did nothing" return,
    grep its call sites for state set on the assumption that returning means it ran.
13. **A marker was declared in the plan, asserted by an AC, and its task ticked — and never
    implemented.** **Prevention:** a ticked task naming an emission needs the grep that finds it.
14. **`rc=$?` after a pipe reported `tail`'s status.** **Prevention:** already documented;
    capture into a variable on its own line.
15. **Two mutation rows scored the wrong thing** — one mutated a marker latch instead of the
    comparison, one scored a marker property on `rc`, which cannot see it.
    **Prevention:** score each row on the channel the property lives in.
16. **A mutation sandbox had a RED control** (a subtree copy broke path resolution), voiding
    every row until re-run against the real tree with a pristine restore.
17. **An empty ceiling was expected to disable the guard**; `${VAR:-default}` treats empty as
    unset, so it resolves to the default. Pinned explicitly as its own arm.
18. **An agent reported the ADR amendment was not in the diff.** It was (47 insertions, 0
    deletions). **Prevention:** verify an agent's claim about the tree against `git diff`.

## Tags
category: test-failures
module: test-all
