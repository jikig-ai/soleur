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

## Session Errors

**1. A one-line lint fix referenced a variable from the sibling gate.** Fixing shellcheck
SC2010 in gate 2, I reached for `canon_files` — gate **1**'s array. Under `set -u` that aborted
the gate and took its suite from 25/0 to 12 passed / 13 failed.
**Prevention:** re-read the surrounding file before applying a "trivial" cleanup; the two gates
were written back-to-back and share structure, which is exactly what makes cross-file variable
names look plausible. Caught by SC2154 plus the suite's fail-closed cases — the property the
gate exists to provide, paying out against its own author.

**2. A Python edit block asserts before writing, so a partial re-apply silently drops the rest.**
The block is atomic (good: no half-applied state), but when it raised on sub #4, subs #1–#3 were
also discarded — and my follow-up block re-applied only some of them. The empty-normalisation
floor vanished that way and shipped absent.
**Prevention:** after a failed edit block, re-apply the WHOLE block, never a remembered subset.
The gap surfaced only because the corresponding mutation row reported "did not land" rather than
"survived" — a battery that distinguishes those two states is what made it visible.

**3. `str.replace` with no match is a silent no-op.** A `tasks.md` edit targeted text that had
already changed; the write succeeded and changed nothing.
**Prevention:** never use bare `str.replace` for a targeted edit. Assert the occurrence count
first (`n = s.count(old); assert n == 1`). This is the same family as #2 and the reason both
went unnoticed for several steps.

**4. A `sed` delimiter collided with the pattern's own alternation.** `s|^(docs/legal|plugins/…)|`
terminates the pattern at the first `|` inside the group. `sed` reported `unknown option to 's'`
and the gate exited 1 on every run.
**Prevention:** when a pattern contains `|`, pick a delimiter that cannot appear in it (`#`, `@`).

**5. I supplied a false premise to the review panel, and it propagated.** My spawn prompt told
six agents that the shared normaliser computes `TC_DOCUMENT_SHA`, the value written into the WORM
consent ledger and CLA Object-Lock evidence. It does not — that is `sha256sum` over the RAW file;
the normalisers feed only the body-equivalence comparison. Two agents corrected it independently;
had they not, the PR would have shipped an inflated blast-radius claim in its own commit message.
**Prevention:** a review prompt is not neutral framing — every premise in it is inherited by
every agent and comes back wearing their authority. State premises as questions ("what does this
feed?") rather than as facts, and re-derive any premise the findings then build on.

**6. `MIN_ASSERTIONS` was calibrated against the suite it replaced.** Set to 30 for a suite that
now runs 20 assertions, so the floor failed a green suite.
**Prevention:** derive a floor from a green run of the CURRENT suite, never from its predecessor.

**7. Environment, no action.** GitHub SSH (port 22 and the `ssh.github.com:443` fallback) began
timing out mid-session while HTTPS stayed healthy; worked around with a one-shot
`credential.helper` for the push rather than mutating the operator's git config. Separately, ~29
probe repositories were left under `/tmp` — mine, from interactive verification, not the suites
(which pin `TMPDIR=/var/tmp` and leak zero). The delete guard blocks `rm -rf` on `.git`-bearing
directories, so they are left for the tmpfs reaper.
