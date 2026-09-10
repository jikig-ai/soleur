# Every instrument I used to judge my own guards agreed with them

**Date:** 2026-09-10
**PR:** #7990 (#7931 parts 1-2, #5806)
**Shape:** the checker and the checked shared an assumption, so the check could only confirm it

## The one-sentence version

Three mutation batteries, three assertion floors, per-guard instrument self-tests
— and the batteries were measuring the baseline, the anchors were matching the
comments that explained them, and the probe helper I wrote to *test the probes*
reported GREEN on a guard that was red. Every instrument was built by the same
hand, from the same assumption, as the thing it measured.

## What actually happened

### 1. A mutation battery whose predicate PARAPHRASES the guard measures the baseline

`workflow-run-deploy-invariants.test.sh` re-applied a hand-rolled subset of its
own G3 row inside `mutate()`, dropping two filters the real row applies. The
unmutated file therefore violated the predicate, so **every** mutant scored
KILLED whatever it changed. Injecting `mutate "delete a blank line" '/^$/{0,//d}'`
reported **6/7 killed**.

The reported "5/5 mutants killed" was a reading of the baseline, and one mutant
(a `workflows:` name desync) was genuinely surviving — the predicate never
re-applied the comparison its defect is about.

**The rule:** a mutation predicate must BE the suite's own assertions, hoisted to
one place so it cannot drift from the rows, plus two controls that make the
verdict readable at all:

- the predicate must be **EMPTY on the pristine file** (else every row is unfalsifiable);
- a **null mutant** — one that lands but changes nothing semantic — must be reported **SURVIVING**.

A battery that cannot say "survived" cannot say "killed" either. Report each
mutant's violation token and check they are *distinct*: five rows dying on one
shared term is the signature.

### 2. An anchor is satisfied by the prose that explains it

`grep -qF 'release / release'` ran against the RAW job block. Mutating
`select(.name == "release / release")` to the bare `select(.name == "release")`
— the exact fail-open the row exists to prevent — left the suite **green**,
shadowed by the comment above the call *and* by the error string inside it.

`cq-assert-anchor-not-bare-token` already says anchor on a call form. The missing
half: **the haystack must be comment-stripped and scoped**, and the stripper
needs its own non-vacuity row, because an empty haystack passes every anchored
row.

### 3. The extractor self-test proved PRESENCE and never SCOPE

Every extractor self-test asked "did it find >= N?". None asked "did it find only
the right region?". The CI-budget extractor terminated at the next step header —
but that step is the LAST step of its job, so it ran off the end and captured 251
lines spanning TWO jobs. Every `grep -qF <jobname>` row it fed could be satisfied
by a foreign job's text.

**Assert the region's boundaries**, not just its size: no job header inside a job
block, a plausible line count, the enclosing construct rather than one line.

### 4. My probe helper had the defect I was using it to find

Twice I reported `*** GREEN — STILL SHADOWED ***` for guards that were correctly
red. The probe grepped for a two-space-dash failure prefix; one suite aborts on a control
failure with a different format, and another's message said "clean-skip path"
where I grepped `clean_skip`. **I was reading a bespoke instrument's silence as
evidence** — the identical mistake the guards were being fixed for, made in the
tool I was judging them with.

Fix: probe on **exit code**, not on a message pattern you predicted.

### 5. Substring containment is not a predicate about meaning

`"pull_request" not in cancel_expr` is satisfied by
`github.event_name != 'pull_request'` — the inversion, which cancels in-progress
`main` runs. Likewise `grep -qF test` matches inside `test-scripts`, and a path
containing `deploy` satisfied a check about command flags.

Where the property is about **meaning**, evaluate; where it is about a **set**,
compare sets. And an expression the evaluator cannot parse must be a finding,
never a silent pass.

### 6. Every guard was must-TRIP, so each was free to get more aggressive

Not one suite had a must-PASS fixture. A guard with only must-TRIP rows can
tighten without limit and nothing notices — and two already had. Adding the
far-side fixtures immediately caught an over-aggressive closure rule that would
have flagged a legitimately push-gated job.

## The non-test lesson that cost the most wall clock

**A CONFLICTING PR gets no `pull_request` workflow runs at all.** `pull_request`
workflows run against the *merge* ref, which GitHub cannot compute when the PR
conflicts. `gh pr checks` still showed checks pending — CodeQL and CLA, which
trigger differently — so the PR looked normal while `test`/`test-scripts` never
ran. A rebase fixed it and CI started immediately.

Before treating checks as evidence, assert the **required contexts are present
by name**. "Nothing failing" and "nothing ran" render identically.

## And one about carried quantities

`test-scripts + test = 70` was the correct CI budget for `await-ci`, which polled
the `test` **check**. `workflow_run: types: [completed]` waits for the **whole
run** — measured 720m. The term survived the rewrite unchanged and both the
workflow and check B9 were green on it, B9 by a 2-minute margin on a phantom.

**When a mechanism is replaced, every quantity it was measured in is suspect.**
Re-derive from the new mechanism's semantics rather than porting the constant.

## Where this knowledge lives (and why not in AGENTS.md)

I first added two AGENTS.md rules for the above. Both were wrong placements, for
different reasons, and the repo's own gates said so:

- **The CI-evidence rule was redundant.** `ship/SKILL.md` Phase 6.5 already
  documents the conflicting-PR trap in full — including the remedy I "discovered"
  (assert the checks you expect are PRESENT, not merely non-failing) and the issue
  that produced it (#6536). I hit the trap because I was reading checks ad hoc
  mid-review rather than running that phase, which is a process gap, not a
  missing rule. **Adding a rule for something already written down is how a
  corpus gets to the size where nobody reads it.**
- **The mutation-battery rule did not fit the budget, and the budget is the
  point.** `B_ALWAYS` sits at 45,999 of 46,000 bytes — one byte of headroom —
  and each of my two bodies was over the 600 B per-rule cap (1024 and 814). The
  gate rejected both. Re-reading `cq-agents-md-tier-gate`: tests and CI are
  **domain-scoped**, which routes to the owning artifact, never AGENTS.md. I had
  claimed "cross-cutting" partly to justify the placement I wanted.

So the mutation-battery contract lives here, in this file, next to the evidence
for it — which is what the tier gate means by moving context to a learning file.
The one-line version, for anyone extending a battery:

> A mutation battery must re-apply the suite's OWN assertions, not a paraphrase,
> and must prove two things before its verdict is readable: the kill predicate is
> EMPTY on the unmutated file, and a null mutant is reported SURVIVING.

## See also

- [[2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran]] — the same family, one level out: wrappers that could not distinguish clean from never-ran
- [[2026-09-04-every-fix-reintroduced-the-class-it-was-fixing]] — anchors, and fixes applied to the instance rather than the class
- [[2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances]] — the direct ancestor
- ADR-215 — the `workflow_run` split
- #8020 — the unbounded ci.yml ceilings this exposed
