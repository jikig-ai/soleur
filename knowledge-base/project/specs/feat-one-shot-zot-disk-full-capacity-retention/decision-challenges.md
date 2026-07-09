# Decision Challenges — feat-one-shot-zot-disk-full-capacity-retention

Per ADR-084 (decision-principles). Surfaced in a headless one-shot run, so persisted here for
`ship` to render into the PR body + file as an `action-required` issue. The operator's stated
direction is the DEFAULT; these are challenges to weigh, not silently-applied changes.

## Challenge 1 — Drop the `sha256-.*` retention bound from this PR

**Operator's stated direction:** "tighten the keep-set … lower `mostRecentlyPushedCount` from 10 to a
smaller count, AND bound the currently-unbounded `sha256-.*` sig-referrer retention so signatures are
dropped alongside their subject image."

**The challenge (all 3 deepen-plan reviewers converged — architecture-strategist P1, code-simplicity
P1/User-Challenge, terraform-review raised no objection to dropping):** drop the `sha256-.*` bound
from this incident PR; keep only lever A (volume 30→60 GB) + the v*/commit-sha `mostRecentlyPushedCount`
10→5. Reasons:

1. **~Zero disk benefit.** The 60 GB volume is filled by multi-GB IMAGES; cosign sigs/attestations are
   KB–MB. The grow + v*/commit-sha 10→5 already solve the disk with margin. Bounding sigs saves
   single-digit MB.
2. **Real contract downside.** It is the only lever touching a recorded invariant (ADR-087:
   "ALWAYS keep every `sha256-*`"). It converts an absolute into a heuristic and needs an ADR-087
   consequence note + a `registry-boot-guard.test.sh` reword + an Observability `cosign_verify_event`
   failure mode — all of which vanish if the bound is dropped.
3. **GHCR fallback does NOT rescue a zot-pruned sig on a KEPT image** (ADR-096 atomic-move fetches the
   `.sig` from whichever registry serves the pull — zot for a kept image). WARN-mode today; blocking at
   the WARN→ENFORCE flip (#6129).
4. **`mostRecentlyPushedCount` breaks under backfill/re-sign** (ADR-096's own `crane copy` path
   re-pushes old sigs out of order), and no zot mechanism ties a tag-based sig to its subject.

**Plan's resolution (default = operator direction):** the plan RETAINS the bound but at the safe count
**50** (not 20) — "bounded-but-inert-now": it caps forever-growth without pruning any kept-image sig at
current scale (~5–6 releases/repo). This honors "both levers" while removing the near-term risk.

**Operator decision needed:** 
- **Keep at 50** (current plan default), OR 
- **Drop the `sha256-.*` bound** from this PR (reviewers' recommendation) and, if the forever-growth
  hygiene is still wanted, file it as a separate non-incident spike that sizes the count against the
  live registry catalog.

`/work` MAY drop the bound (and the ADR-087 note + test reword) if the operator resolves this before
implementation; otherwise it ships at count 50.
