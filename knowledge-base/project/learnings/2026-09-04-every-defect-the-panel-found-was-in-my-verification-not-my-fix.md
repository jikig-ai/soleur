---
title: "Every defect the panel found was in my verification, not my fix"
date: 2026-09-04
category: workflow-patterns
issue: 7801
pr: 7806
tags: [mutation-testing, vacuity, guards, review, measurement]
---

# Every defect the panel found was in my verification, not my fix

## Problem

A ~30-line change to the `/ship` Incident-PIR gate (making a hypothetical strip
paragraph-scoped instead of line-scoped) shipped with a 36-test suite, a 10-row
mutation battery, clean shellcheck, and a 1903-input corpus sweep. A ten-agent
review then found ~30 findings. **Six of the most serious were in the verification
code, not the gate** — the tests, the battery, and the comments asserting what had
been measured.

That is the documented shape for a fix PR, and knowing it did not prevent it: the
fix is written while holding the defect in mind, so the assertions inherit its
framing and get written fast, because they feel like bookkeeping rather than
authorship.

## The four that generalize

### 1. A battery that emits one assertion per ROW counts rows, not discrimination

`run_row` emitted exactly one assertion however many fixtures it checked, and an
empty check list left the "all checks passed" flag true. So:

- emptying every row's check list,
- truncating an `all-of-2` row to `1-of-1`,
- deleting five fixtures from the baseline table,

each printed the **byte-identical** `20 passed, 0 failed (11 mutation rows, 20
assertions)` at exit 0. The battery could assert nothing whatsoever about behaviour
and be indistinguishable from the real one — the exact vacuity its own header
claimed to police.

**Fix:** one assertion per fixture check; a row with no checks FAILS; the baseline
table's own cardinality and file existence are asserted. A floor over rows cannot
see any of these; a floor over checks sees all four.

**Litmus:** ask of any battery *what is the unit of the floor, and can the unit stay
constant while discrimination drops to zero?*

### 2. Observability added to a verdict pipeline can flip the verdict

To make an accepted residual honest, the strip emitted a note when it suppressed an
outage line. It wrote to `/dev/stderr` from inside awk. **mawk exits 2 when that
write fails** — closed fd, `/dev/full`, no `/proc` — and the fail-toward-PIR guard
reads any non-zero as a broken pipeline. Measured: identical input gave `exit 1` on
a terminal and `INCIDENT-SIGNAL: yes` under `2>&-`, on the customer-CLI surface the
guard exists for.

**Fix:** the note leaves awk as a sentinel line on stdout; the shell converts it
after the guarded assignment, where a failed write cannot reach the verdict.

**Litmus:** any diagnostic emitted from inside a pipeline whose STATUS is a verdict
is part of that verdict. Ask what the diagnostic's own failure does.

### 3. A floor set to the number you expected is not a floor

Set three times in one session (20, 21, 22) — each time from arithmetic rather than
from a green run, and each time one off. The rule is already written down in this
repo. Deriving it takes one command:

```bash
N=$(bash <battery> 2>&1 | tail -1 | grep -oE '[0-9]+ assertions' | grep -oE '[0-9]+')
sed -i "s/^MIN_ASSERTIONS=.*/MIN_ASSERTIONS=$N/" <battery>
```

### 4. Prose that documents a matcher becomes input to that matcher

A fixture's HTML comment explaining *why* a token had to sit outside the stripped
paragraph used the word `outage` — which satisfied `OUTAGE_RE`, so the fixture
signalled under both the broken and the fixed implementation and proved nothing.
A sibling fixture's comment supplied the `PROD_RE` conjunct it warned about, making
the `## Overview` section it declared load-bearing not load-bearing at all
(measured: rc=0 before backticking, rc=1 after).

This class is documented in `review/SKILL.md` and was hit **twice more** in the
session that was fixing an instance of it. Backticking the tokens works because the
inline-code strip runs before either matcher.

## Five claims that were false

Every one was written as though measured, and each was refuted by one command:

| Claim | Truth | Falsifier |
|---|---|---|
| "nine of the original ten fixtures pass on `main`" (2 files) | seven | run `main`'s gate over the ten |
| ORDER table "25 fixtures / 2 movers" | 28 / 3 | the same commit added 3 fixtures and skipped the re-measure |
| AC6a "removing lines cannot create a match" | true of ONE stage, false of the pipeline | 3 stages above it REWRITE records |
| "the corpus grew between planning and implementation" | the GLOB changed; counts were identical at plan time | `git ls-tree` at the plan commit |
| meta-case uses "the same trust model as every `[ack]`" | bare `[ack]` is in 2 files, one of them that sentence | `grep -rn '\[ack\]'` |

The AC6a one mattered most: two `sed` stages DELETED their match and fused the
neighbours, so `pro` + `` `x` `` + `duction` produced a forged `production` and a
document with no unbroken token signalled. Both now substitute a space.

## A review finding can be a regression

A proposed fourth conjunct for the meta-case exemption — *"the gate must not signal
on the PR's own added knowledge-base artifacts"* — was implemented, measured, and
**reverted**: it voids the exemption for essentially every PR in its class,
including the one introducing it, because a plan ABOUT an incident gate is dense
with outage vocabulary whether or not an event occurred. It cannot separate the
residual case from the ordinary one, and a conjunct no legitimate user can satisfy
is a gate that gets bypassed rather than met.

Recorded in the file as tried-and-rejected WITH the measurement. That is worth more
than either shipping it or silently dropping it.

## Session Errors

1. **`| tail` masked lint exit codes.** Read `tail`'s status, reported `rc=0` for a
   failing lint. **Prevention:** already `hr-never-run-commands-with-unbounded-output`'s
   neighbour; capture to a file and inspect `rc` explicitly.
2. **`npx markdownlint` is not `markdownlint-cli`.** The wrong package reported 0
   errors — a vacuous clean that read exactly like a real one — while lefthook (which
   runs `markdownlint-cli`) reported 19. **Prevention:** read the hook's actual
   command before reproducing it; a tool that reports zero findings on a file another
   tool rejects is the wrong tool, not a disagreement.
3. **Vacuity probes relocated to `/var/tmp` exited 2 for the wrong reason.** The
   battery derives `REPO_ROOT` from `BASH_SOURCE`, so a copy outside the tree cannot
   find the SUT. Both probes "passed" while proving nothing. **Prevention:** place
   probe copies INSIDE the tree, and require a GREEN unmutated control in the same
   location before reading any probe result.
4. **An apostrophe in an awk comment closed the quoted program.** "the re-admit's
   position" → syntax error at an unrelated line. **Prevention:** documented in
   `work/SKILL.md`; grep the awk block for `'` after editing.
5. **Fixture comments satisfied the matchers under test** (twice). **Prevention:**
   backtick every vocabulary token in fixture prose; the inline-code strip runs first.
6. **Assertion floor set from expectation, not measurement** (3×). **Prevention:**
   derive it from a green run.
7. **The anchor rule "must shrink" was wrong for a replacement mutation** that
   CREATES a pattern (pristine 0 → mutant 1). **Prevention:** the anchor must MOVE,
   in either direction.
8. **Backticked `scripts/` paths in a skill body** broke `components.test.ts` (the
   repo requires markdown links). **Prevention:** the shard gate caught it; run the
   touched shard before assuming a docs-only edit is inert.
9. **Guessed three dashboard URLs before reading the navigation.** **Prevention:**
   snapshot the nav first; it cost four round-trips to save one.
10. **Over-claimed a documented trade-off as a defect** — the global `network-outage`
    strip is #6665's intent, not a bug. **Prevention:** before calling inherited
    behaviour a defect, read the comment that introduced it.

## Routing (deferred, deliberately)

The floor-UNIT class belongs in `plugins/soleur/skills/review/SKILL.md`'s defect
catalogue, beside the existing floor-derivation rule which covers the NUMBER but not
the UNIT. It is **not** routed there in this PR: editing that file would put this PR
outside conjunct 2 of the meta-case exemption it introduces, and widening a safety
gate so the author's own PR fits through it is the anti-pattern the gate exists to
resist. The insight is recorded here in full; `scheduled-compound-promote.yml`
consumes learnings and proposes exactly this kind of skill edit.

Proposed bullet, ready to lift: *ask what UNIT an anti-vacuity floor counts — a floor
over ROWS is blind to a row that asserts nothing, and the headline it prints is
byte-identical either way. Emit one assertion per CHECK, fail a row whose check list
is empty, and assert the baseline table's own cardinality. An anchor rule of "the
count must SHRINK" is wrong for a replacement mutation that CREATES a pattern; require
the anchor to MOVE in either direction, and for a REORDER assert inverted ORDER.*

## Key Insight

On a PR whose deliverable is a guard, **review the new assertions before the new
code**. The gate itself survived the panel almost unchanged; everything built to
prove the gate was correct had to be rebuilt. A green suite, a green battery, and a
clean sweep are three statements about the instruments, and instruments written in
the same sitting as the fix inherit its blind spots.

Corollary for the reviewer's own work: **five of the measurements I took to check my
own work were themselves broken** (items 1, 2, 3, 7, and a `diff` whose empty output
I nearly read as "the edit did not land"). Verify the instrument before reading its
output.
