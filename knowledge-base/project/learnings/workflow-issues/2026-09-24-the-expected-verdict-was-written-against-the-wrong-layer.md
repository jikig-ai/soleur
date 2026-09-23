---
title: "The expected verdict was written against the guard's totality layer — the refusal layer underneath answered first"
date: 2026-09-24
category: workflow-issues
tags: [testing, expected-verdicts, mutation-testing, fail-closed, layered-contracts, shard-manifests]
issue: 8006
pr: 8665
---

## The shape

Phase 2 of the CI test-shard speedup added a second committed manifest for the `scripts-heavy`
group — `n=3` over exactly 3 registered labels. The mutation battery grew three rows
(M7–M9) with expected verdicts written in the plan: minus-one table → GREEN (hash fallback
covers the missing label), phantom row → GREEN (inert), header-only table → GREEN (all labels
hash, still total). The first two passed. **M9 came back RED — and RED was the correct answer.**

## What actually happened

The expectation was derived at the guard's *totality* layer: "every registered label is
assigned to exactly one leg." Under a header-only heavy manifest, all three labels fall back
to `cksum` hashing, which distributes them `{3,2,2}` — every label IS assigned to exactly one
leg, so totality holds.

But totality is not the lowest layer in this system. The runner's **zero-assignment
refusal** sits underneath it: a leg whose enumerate yields nothing exits 2, because a leg
assigned no work reports a green that means nothing. Under `{3,2,2}`, leg 1 starves, the
enumerate refuses, and the guard's leg row fails — before totality is ever evaluated.

At `n=489` over 6 legs the refusal is unreachable through stale data (a hash distribution
cannot starve six legs with that many labels). At `n=3` over 3 legs it is one unlucky hash
away. The plan's expectation was written from a mental model calibrated on the light group,
where the refusal layer can never fire — so it was never consulted.

Two sibling findings from the same review round were the same defect one layer over:

- **The generator inherited `SCRIPTS_SHARD`.** `registered_labels()` shells out to
  `test-all.sh --enumerate` to derive "the full registration set" — a top-layer contract.
  An *environment* layer underneath (an exported `SCRIPTS_SHARD` in the caller's env)
  silently narrows the enumerate to one leg, and the generated manifest would have tabled a
  subset. Same class the guard and orphan-lint already close with `env -u`; the generator
  was written before it had to care.
- **Per-leg range accounting cannot see the gap between legs.** Each mutation-battery leg
  asserts `_row_seq == DECLARED_TOTAL` and `EXECUTED == in-range count`. Every leg's own
  books balance — but a new row plus a bumped `DECLARED_TOTAL` without a matrix re-split
  executes in NO CI leg. The union property lives one layer above every leg's accounting,
  so no leg can see its absence.

## The generalisable rule

**When a system has ordered refusal layers, an expected verdict is only valid at the layer
that answers FIRST — and that layer is the one furthest from the property you are reasoning
about.** The fix for each instance was identical in shape: stop deriving the expectation
from the top layer and enumerate the layers that can answer before it.

The cheap check: before writing an expected verdict (or a fixture, or a "this cannot fire"
comment), ask *which layers can refuse, refuse-then-degrade, or narrow the input before my
property is evaluated* — and if the answer is "none can," name the mechanism that proves it.
At small `n` or under a non-default environment, "none can" is usually wrong.

The same rule governs *fixes*: the `fetch_timings_from_dir` artifact-name filter was a
correct review fix applied at the input layer that broke fixture C's `leg1/leg2/` layout —
the fixture layer underneath assumed unfiltered merging. The consumer test caught it
immediately because it was re-run in the same pass. A fix at one layer without a re-run of
the layer it feeds is a guess.

## Session Errors

1. **M7/M9 planned verdicts were wrong (GREEN → M9 is RED).** Expected verdicts written at
   the totality layer without simulating the zero-assignment refusal, which is reachable at
   n=3 over 3 labels. **Prevention:** when a guard has an ordered refusal → evaluate → verdict
   pipeline, trace the expected outcome through every layer that can answer first — especially
   at boundary sizes (n == label count) where distributions degenerate.
2. **Generator subprocess inherited the caller's shard environment.** An exported
   `SCRIPTS_SHARD` would have produced a one-leg partial manifest. **Prevention:** any
   subprocess whose contract is "the full set" gets a scrubbed env — grep new
   `subprocess.run`/`bash` call sites for `env=` the same way the guard and orphan-lint pin
   `env -u`.
3. **A review-suggested fix (`fetch_timings_from_dir` group filter) broke fixture C on first
   re-run.** The filter assumed CI-artifact-named dirs; local fixture dirs are not.
   **Prevention:** re-run the consumer suite in the same pass as any fix, even "safe" ones —
   the fixture layer is a contract too.
4. **Rebase onto the remote feature branch replayed an already-merged main commit** (the
   remote init's parent predated it), producing 30+ foreign files and a merge-tree conflict.
   **Prevention:** before `git rebase origin/<feature-branch>`, diff the remote tip against
   `origin/main` — if it carries commits you did not write, rebase `--onto origin/main`
   from your own first commit instead.
5. **A pipeline masked an exit code** (the empty-override check read rc=0 through a pipe;
   direct run = exit 2). **Prevention:** exit-code assertions run the command directly, never
   through `| tail`/`| head` — `pipefail` protects pipelines you own, not observations of rc.
6. **Reading `test-all.sh` mid-battery** returned a mutated file's content (enumerate emitted
   nothing). **Prevention:** while the mutation battery runs, treat its three target files as
   write-locked — sequence reads after the half completes.
7. **Partial-update comment drift** — K=6 edits updated the engagement comment at the manifest
   block but left the sibling `_shard_selects` doc, the 8-leg probe comment, ci.yml's
   "all three legs"/"1/3" literals, and the battery's "eight ways" header describing the old
   topology. **Prevention:** after a topology/count change, grep the NUMERIC referent (`/5`,
   `three legs`, `eight ways`, `K+1`) repo-wide, not the sentence you remember writing — same
   class as the subject-not-phrasing sweep rule.

## What did NOT need fixing

- `EXECUTED < 1` belt-and-suspenders floor — subsumed by range validation but retained as
  documented defense-in-depth.
- Empty-label TSV rows (`\t3`) skip silently — same behavior as the lint; the hash fallback
  covers the label, so it is table-staleness, not a coverage defect.
- The heavy group's reduced malformed-spec list — a documented class-sample (4 of 10) over a
  shared validator, not a coverage gap.
