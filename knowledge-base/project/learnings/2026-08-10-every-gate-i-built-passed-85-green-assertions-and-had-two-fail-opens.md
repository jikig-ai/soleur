---
title: Every gate I built passed 85 green assertions and shipped two fail-opens
date: 2026-08-10
category: workflow-patterns
tags: [gates, mutation-testing, legal-corpus, review, fail-open, vacuity]
issue: 7387
---

# Every gate I built passed 85 green assertions and shipped two fail-opens

## What happened

#7387 asked for write-time gates over the legal corpus — the class of defect that had been
costing multi-agent review panels on work that was mechanically checkable. I built two gates
and three suites, ran them, and reported 85 passing assertions with mutation batteries
reporting every arm load-bearing.

A ten-agent review found ~55 findings: 2 CRITICAL, 1 BLOCKER, ~15 HIGH. **Every one passed
those 85 assertions.** I reproduced, inside the tool built to catch a defect class, the defect
class itself.

## The five that matter

**1. A `|| true` on a pipeline turned every git failure into a clean pass.**

```bash
git diff -U0 … 2>/dev/null | awk '…' > "$ADDED" || true
if [[ ! -s "$ADDED" ]]; then echo "no added lines"; exit 0
```

`2>/dev/null` discarded the diagnostic, `|| true` discarded the status, and an empty file was
read unconditionally as "the PR touched no legal doc". Measured with `chmod 000` on one corpus
file: git exits 128, the gate prints *"no added lines in the legal corpus; nothing to check"*
and exits 0 — on a tree that exits 1 when the file is readable. My own file header forbade
exactly this four lines above it.

**2. A greedy regex, quantified against the real corpus.** `sub(/^.*\+/, "", plus)` on a hunk
header eats to the LAST `+`, and `git diff -U0` appends funcname context. The corpus has 88
`+`-bearing lines and two are already git-default funcname anchors. Effects: `start=0` (the
section scan dead for that hunk) and `count=1` (a 3-line insertion emitting one row).

**3. The battery mutated one axis, four times.** Every mutation flipped an `ARM_*_ENABLED`
toggle. Toggles are the cheapest thing to mutate and the least likely thing to regress — nobody
accidentally sets `ARM_A_ENABLED=0`. The mutations that matter are to regexes, field parsing and
stream transforms, and none were probed. Worse, the toggles existed *only* so the battery could
neuter an arm: they let it test a **simulated** defect, which is why the real ones walked past.

**4. Nothing asserted that the assertions ran.** Neutering `pass()`/`fail()` yielded
`passed: 0 failed: 0`, exit 0, and `run_suite` recorded `[ok]`. Eighty-five assertions and zero
assertions were indistinguishable to the runner.

**5. A pin anchored to the wrong thing.** The parity baseline hashed `normalize(live document)`
for all nine pairs to prove the *extraction* was behaviour-preserving — an engine claim, true
once. But a hash is a function of the engine AND the document, so a one-word edit to any legal
doc red-lined the required `test` context with an extraction-failure message, no remediation and
no bypass. I had added a third content pin over the corpus, and the only one with no refresh
path, in a PR whose thesis is that gates must not be silently unsatisfiable.

## The generalisation

Each of these is the same shape: **I verified the thing I was thinking about, and the defect
lived in the thing I wasn't.**

- I verified the gate detects a planted defect. I did not verify it can *reach* the input.
- I verified each arm fires. I did not verify the arms are reachable from the real vocabulary.
- I verified mutations are killed. I did not verify the battery's axes span the SUT.
- I verified the suite passes. I did not verify the suite *runs*.

The mutation battery is the sharpest instance, because it *feels* like the check that closes
this gap and is bounded by the same imagination that wrote the code.

## What to do instead

1. **Audit a battery's AXES, not its count.** Enumerate the layers a mutation could edit —
   dispatch, fixture shape, fixture direction, population cardinality, regex, field parse,
   stream transform — and ask which the battery never touches. N mutations of one shape is one
   mutation.
2. **Assert the EXPECTED verdict, not just non-zero.** Two of my rows were vacuous because a
   different arm fired; one hand-verification was a false positive for the same reason (a
   fixture said `See 9.`, which is not a cross-reference, so arm (c) fired and I credited arm
   (b)). A row whose pristine verdict is rc=2 needs its own block — an rc=1 positive-control
   contract cannot express it.
3. **Put a `MIN_ASSERTIONS` floor at every suite's exit.** A floor, never an equality: equality
   makes each added assertion a spurious failure.
4. **Anchor a pin to a synthesized fixture when the claim is about the ENGINE.** Then prove it
   is load-bearing by weakening the engine and asserting the hash moves.
5. **When a fix widens a matcher, re-run the discrimination cases.** Dropping the
   paragraph-referent exemption closed a laundering path and introduced a NEW false positive:
   `the Section` inside a cross-reference read as a referent, red-lining a correctly-narrowed
   block — the exact class the CLO had withdrawn the gate's first draft over.
6. **A surviving mutant has two readings — label which.** Breaking heading *detection* widened
   the scan to the whole file, so the gate stayed at least as aggressive and the fixture still
   fired: an EQUIVALENT mutant, not a fixture gap.

## The compliance-specific one

The gate header listed six "measured omissions" on the published mirror as Art. 83(2)(b)/(c)
evidence. Two were wrong — the mirror *does* disclose the Anthropic/US transfer
(`gdpr-policy.md:206`, 18 occurrences on each surface) — and two more were narrower than stated.
The list came from an issue body and I reproduced it under the word "measured" without checking
it, into the gate, its runtime output, the plan, and a comment on #7349.

**A compliance artifact asserting a measurement it did not perform, on a point the corpus
contradicts, weakens the exact claim it was written to support.** A smaller accurate list is
worth more than a larger inherited one. Litmus: *what command would falsify this, and did I run
it?*

## Related

- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md`
- `2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it.md`
