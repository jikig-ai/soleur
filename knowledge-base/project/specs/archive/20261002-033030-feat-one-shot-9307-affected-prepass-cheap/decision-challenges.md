# Decision challenges: feat-one-shot-9307-affected-prepass-cheap

Plan: `knowledge-base/project/plans/2026-10-01-feat-cheap-affected-prepass-and-pr1-residuals-plan.md`.
Recorded by plan-review (headless): the operator's stated direction stays the default for each item below
unless the operator reverses it; `ship` renders this file.

## DC1: one PR or three

- **What you said:** do A, B, C, D in this order, each its own commit, "one PR unless review says split".
- **What both signals recommend:** split into PR-A (byte-identical speedup), PR-B (re-demotion, recorder,
  ratchet breadth, minting fixes) and PR-C (runner leaf, REPO_ROOT idiom, heavy batteries). Three of four
  review seats (DHH, CTO, simplicity) said split; the plan applied the operator's own "unless review says
  split" clause.
- **Why:** Phase A is the only phase whose acceptance is "output byte-identical". Bundling selection-changing
  work into the same diff destroys that review contract, and the diff touches `scripts/test-all.sh`, which
  degrades the local gate to a full run so CI is the only gate. The plan's own risk table concedes D1 can be
  split out.
- **What context we might be missing:** the operator may want one merge event for the umbrella's residual
  checklist, or may have capacity for a single larger review.
- **If we're wrong, the cost is:** PR-B and PR-C are separate pipeline runs on #9307 (re-filed with measured
  reasons) instead of one; the byte-identical series loses nothing.

## DC2: "order of magnitude with byte-identical selection"

- **What you said:** pre-pass wall time drops by an order of magnitude with byte-identical selection.
- **What was measured:** 4.0x on the README probe and 4.4 (3.1 at the minimum, 280 s to 89 s, because the base side was noisy)x on a multi-path probe (median CPU, interleaved,
  load 3 to 12), selection identical on both; the figures and the profile are in ADR-242, Amendment — 2026-10-01.
  The only measured route to 10x or better is the runner as a closure leaf (61.9 s CPU, from the plan), which narrows
  selection (18 rows lose about 450 edges each) and so cannot count as byte-identical; it is PR-C.
- **Why:** no identity-preserving change with a measured gain of that size is known; a memo-index lever prototyped in
  review is unmeasured on the full walk. Reporting 10x for the identity-preserving series would be false.
- **What context we might be missing:** whether a ~4.0x, identical-selection result is "good enough" to merge
  before PR-C, or whether PR-A should wait for the runner-leaf decision.
- **If we're wrong, the cost is:** PR-A ships a smaller headline than the brief asked for and the order of
  magnitude arrives in PR-C with a documented selection delta.

## DC3: where B1 (recorder), D3 and Phase C land

- **What you said:** B re-price the demotions with a committed recorder; C narrow the nine batteries with
  evidence; D3 subcommand forms.
- **What both signals recommend:** keep all three as follow-on work, not in PR-A; build the recorder only if B2
  or Phase C needs its verdicts; narrow Phase C to the four candidates whose subject is explicit and record the
  other five as keep; ship D3 as rows plus a two-line change, filed with the measured reason that no
  registration mints those forms today.
- **Why:** the plan itself predicts "a handful of narrowings, not nine", and the recorder plus perturbation plus
  60-commit corpus is the cost of the evidence, not the saving.
- **What context we might be missing:** the operator asked for the recorder to be committed this time
  explicitly, and Phase C's saving (about 1,371 s of 39.3 minutes of always-on time) is larger than the whole
  pre-pass cost.
- **If we're wrong, the cost is:** the local docs-only diff keeps paying the heavy batteries a PR longer.
