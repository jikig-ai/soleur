---
title: The guard was deleted, the plan still cited it, and the linter validated the citation
date: 2026-09-08
category: test-failures
component: plugins/soleur/skills/qa
tags:
  - qa
  - guard-contract
  - acceptance-criteria
  - verification
  - awk
  - shard
  - deploy-gate
related:
  - knowledge-base/project/plans/archive/20260908-132617-2026-09-07-fix-release-await-ci-ceiling-vs-ci-duration-plan.md
  - knowledge-base/engineering/architecture/decisions/ADR-208-deploy-gate-measures-its-own-gated-quantity.md
  - knowledge-base/project/learnings/2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md
  - knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md
  - knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md
---

# Learning: the guard was deleted, the plan still cited it, and the linter validated the citation

## Problem

QA on #7902 (raise the `await-ci` deploy ceiling + shard `test-scripts`) found four defects that
had survived plan, deepen-plan, work, AND a full review panel. They share one shape: **a claim and
its referent drifted apart, and every instrument positioned to catch it was measuring something
adjacent to what the claim asserted.**

### 1. The plan cited a guard that had been deleted

Mid-implementation, Guard 2 ("CI's declared budget is bounded by the deploy gate's ceiling") was
built, mutation-proven at 10/10, and then **deleted** on a CTO ruling: arithmetic over *declared*
job ceilings omits the concurrency-queue term, so the guard is green on exactly the configurations
the gate cannot absorb. The deletion was recorded in a Correction stanza and in ADR-208.

Two other places still cited it as live:

- the observability `failure_modes` block, whose `detection:` field for the plan's sharpest hazard
  read "Guard 2 asserts max(declared ceilings...)"
- the `## Guard Contract` section, carrying a full property statement, assembly notes and a
  seven-row mutation matrix for a suite that does not exist

So the hazard read as **mitigated by a control that does not exist** — and it read that way in the
one document a reviewer consults to decide whether the hazard is mitigated.

`scripts/lint-guard-contract.py` passed throughout, at exit 0 over 30 guard entries. It is not
broken. It resolves plan **entries** — it has no notion of whether a described guard was ever
implemented, and cannot acquire one cheaply. A green lint here means "the section parses", which
is a sentence about the document and never about the tree.

### 2. Two acceptance criteria were literally false, and were about to be ticked

- **AC3** asserted the release-workflow diff "touches only the two constants and their comment".
  It also adds the soft-ceiling warning, two job outputs, `id: await`, and a whole consumer job.
- **AC5** asserted the `test:` job block is "byte-unchanged (`git diff origin/main` shows no change
  within it)". Measured: 41 → 48 lines.

Both would have been ticked from memory of intent. Both were caught only by running the command
the AC itself names. An AC written early describes the change the author *planned*; by ship time it
describes a change that no longer exists, and its checkbox is the least-audited surface in the plan.

### 3. My own QA harness produced false REDs — from a bug documented four months earlier

Three harness rows failed in ways that read as product defects:

```
FAIL: REG3 — ci.yml legs inconsistent: 5 legs, 3 distinct k, 2 distinct N
FAIL: REG3 — ci.yml legs inconsistent: 1 legs, 1 distinct k, 1 distinct N
line 87: 360\n960\n480: arithmetic syntax error
```

None was a product defect. In order: a file-wide `grep '"[0-9]+/[0-9]+"'` conflated `test-webplat`'s
**pre-existing** `["1/2","2/2"]` matrix with the new one; a bare `MAX_ATTEMPTS` grep also matched
`STATUS_POLL_MAX_ATTEMPTS` and `HEALTH_POLL_MAX_ATTEMPTS`, returning three values where the
arithmetic expected one; and — the important one — this:

```bash
awk '/^  test-scripts:$/,/^  [a-zA-Z0-9_-]+:$/' ci.yml     # WRONG
```

An awk range `/start/,/end/` terminates at the next line matching `end` **including the start line
itself**, because the start line also matches `^  [a-zA-Z0-9_-]+:$`. The range collapses to one
line. Every downstream grep then reads a one-line haystack and finds nothing — and *finds nothing*
is indistinguishable from *the property is absent*.

This exact failure mode is already written up in
`2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`, **with the
correct flag-based fix in it**. I re-derived it wrongly four months later. Per #7822's lesson, when
a documented class recurs the finding is the propagation failure, not the defect.

The saving grace here was direction: a collapsed extraction made my assertions fail RED. Had the
predicate been phrased the other way ("assert the block does NOT contain X"), the same collapse
would have reported GREEN over an empty haystack.

### 4. Adding a test suite silently invalidated a measured table

The new guard suite took the scripts group 375 → 376 registrations. `ci.yml`'s K table carries its
own rule: *"Any change to the registered suite set invalidates this table — RE-SIMULATE before
touching K."* I was not touching K, so the instruction did not obviously address me. Measured
effect: the 8.14-min floor suite keeps its leg (ordinal 148, before the insertion at 189), but
**187 of the 375 pre-existing suites move legs.**

## Solution

**For the deleted guard.** Rewrite the section under an explicit `REJECTED, NOT SHIPPED` heading and
keep the original design verbatim beneath it — the retention is the point, so the rejected approach
is not re-proposed. Correct the `failure_modes` `detection:` field to name what actually detects the
mode. Say plainly, in the section, that `lint-guard-contract.py` cannot distinguish a shipped guard
from a described one, so the next reader does not mistake its green for coverage.

**For the false ACs.** Correct in place to what shipped, keep the property each AC was protecting,
and state it as something measured rather than intended:

> **CORRECTED (QA).** Measured: the `test:` block is NOT byte-unchanged — it gains
> `timeout-minutes: 10` and its comment (41 → 48 lines). The property it existed to prove holds:
> the `needs:` list, the `if:`, and the aggregation loop are byte-identical to `origin/main`.

**For the extraction bug.** Use the flag form, and — the part the 2026-05-15 learning did not carry
— **assert the extraction is non-empty before scoring anything against it**:

```bash
job_block() {  # $1 = workflow path, $2 = job key
  awk -v job="$2" '
    $0 ~ "^  " job ":$" { inb=1; print; next }
    inb && /^  [a-zA-Z0-9_-]+:$/ { exit }
    inb { print }
  ' "$1"
}

_blk_lines=$(job_block "$REL" await-ci | wc -l)
if (( _blk_lines > 1 )) && job_block "$REL" await-ci | grep -q '^  await-ci:$'; then
  pass "EXTRACTION — the block is $_blk_lines lines and starts at its own key"
else
  fail "EXTRACTION — job_block returned $_blk_lines line(s); every invariant below would be scored against an empty haystack"
fi
```

Three sibling suites in this repo already guard their extraction this way. Note that
`terraform-drift-step-order.test.sh` **deliberately duplicates** the extractor rather than sourcing
a shared one, on the reasoning that a cross-file source makes one suite's failure look like
another's. That is a considered trade — do not "fix" it into a shared lib without re-opening it.
The importable unit here is the *sanity row*, not the extractor.

**For the invalidated table.** Do not re-simulate an order that the next added suite invalidates
again. Record an **order-independent bound** alongside the optimisation table:

> The whole group is 35.25 min = 2115s, so ANY leg of ANY partition is bounded by 2115s. Against
> the worst measured concurrency-group queue (1260s) that is 3375s, inside the 3600s `CEILING_S`.
> The bound holds even where one leg ran the entire group.

The table now justifies K=3 as *optimal*; the bound is what makes any K=3 assignment *safe*.
Re-simulate to re-optimise, never to re-establish safety.

**Also added** `plugins/soleur/test/await-ci-ceiling-invariants.test.sh` (11/11): ADR-072
invariant #7, `MAX_ATTEMPTS x INTERVAL_S == CEILING_S`, the soft ceiling derived not restated, and
`soft_breach` still having a consumer. Before it, all four were unenforced prose in a workflow
comment reading "do NOT lower CEILING_S, MAX_ATTEMPTS, or timeout-minutes without re-reading
ADR-072" — and #7902's own plan is the proof that such prose does not hold: it raised `CEILING_S`
3000 → 3600 and omitted `MAX_ATTEMPTS`, which left at 300 would have bought 60 seconds instead of
ten minutes while every constant still looked right.

## Key Insight

**A plan's claims about its own guards outlive the guards, and the lint that "validates" the claim
usually validates the sentence rather than the referent.** Three of these four defects are the same
motion: something was deleted, changed, or added, and a document that asserted a fact about it was
not re-derived. The gates all stayed green because each was measuring an adjacent quantity — the
section parses, the residual count is zero, the suite exits 0.

The operational form is a question to ask of a plan at QA time, not at review time: **for every
control this document names as a mitigation, does that control exist in the tree right now?** It is
one `ls` per named guard. Review reads the diff and cannot see a guard that is absent from it; QA
is the last phase that reads the plan as a whole while there is still time to correct it.

And the corollary for verification scaffolding: **a false RED costs a real investigation.** The
repo's existing learnings are all about instruments that fail green. An instrument that fails red
sends the next reader hunting a phantom, which is how #7902's own issue body describes a suite it
had to dismiss as flaky. Assert that your extraction found something before you score anything
against it.

## Session Errors

Full inventory (30 items) is in the PR discussion; the ones with a prevention vector:

- **The plan cited a deleted guard in two places (`failure_modes`, Guard Contract).** Recovery:
  rewrote both under a REJECTED heading naming what actually detects the mode. **Prevention:** at
  QA, `ls` every control the plan names as a mitigation before recording the hazard as mitigated.
- **AC3 and AC5 were literally false and about to be ticked.** Recovery: corrected to measured
  fact, preserving the property each protects. **Prevention:** tick an AC only by running the
  command it names; never from memory of intent.
- **QA harness awk range collapsed to one line** — a class documented 2026-05-15 and re-derived
  wrongly. Recovery: flag-based extractor + a non-empty extraction row. **Prevention:** the sanity
  row is the importable unit; ship it with any hand-rolled block extractor.
- **File-wide greps conflated sibling jobs** (`test-webplat`'s pre-existing `["1/2","2/2"]`;
  `STATUS_POLL_MAX_ATTEMPTS` vs `MAX_ATTEMPTS`). Recovery: scoped every read to the job block and
  anchored the key. **Prevention:** in a multi-job workflow, scope before you match, and anchor
  the key — a suffix match is a different variable.
- **Adding a suite invalidated the K table by that table's own rule.** Recovery: recorded an
  order-independent safety bound. **Prevention:** when a measured table warns that a set change
  invalidates it, adding to the set IS the change — pair every positional optimum with a bound
  that does not depend on position.
- **Read `list_runs` (worktree-scoped) as a global capacity check** and launched a full gate that
  was correctly refused `rc=4` behind three sibling gates. Recovery: read the contention preamble
  instead. **Prevention:** `list_runs` resolves ownership via `/proc/<pid>/cwd` and answers "mine",
  not "the box's" — `test-all.sh`'s own contention preamble is the authority for capacity.
- **Ran `bunx vitest@latest --reporter=basic` on a `.test.ts`** — wrong runner and a nonexistent
  reporter; the stack trace read as a test failure. Recovery: `bun test <file>`, 11/11.
  **Prevention:** take the runner from `scripts/test-all.sh`'s registration for that path, never
  from the file extension.
- **Stopped mid-pipeline after review**, listing remaining steps instead of executing them (user:
  "why did you stop?"). Recovery: resumed immediately. **Prevention:** an exit summary from a child
  skill is a continuation gate, not a turn boundary.
