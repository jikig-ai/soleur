---
title: A follow-through's `earliest=` gate coupled to the probe's own deadline made its other time bound dead code
date: 2026-10-01
category: workflow-patterns
tags: [follow-through, sweeper, earliest, probe, test-design]
---

# A follow-through's `earliest=` gate coupled to the probe's own deadline

## What happened

PR #9381 shipped a probe for tracker #9380 with two time bounds: an abandon deadline (2026-10-15) and a
48 h bound after a plaintext-forget run. The tracker directive carried `earliest=2026-10-15`, and
`scripts/sweep-followthroughs.sh` does not run a probe before `earliest`. Every in-production run therefore
had `now >= deadline`, so the deadline arm always fired first and the 48 h arm was unreachable except through
the test clock seam. The plan had even recorded "the 48 h bound is enforced by the sweep only from that date" as
an accepted limitation, so no gate flagged it; three of four review seats found it independently.

## Second finding on the same PR

The suite's stub `gh` dispatched on `$1 $2` only, so `PR=9347` (or `9380`, the tracker's own number) left it fully
green while real `gh` would report some other merged PR and the probe would exit 0 and close the tracker.

## Prevention

- When a probe has a time bound of its own, set the tracker's `earliest=` to the FILING date and let the probe
  answer 2 (NOT YET) before its own bound. `earliest` is the sweeper's gate, not the probe's deadline.
- A stub for an external CLI should accept exactly the argv the probe must send and exit 64 on anything else, and
  the suite should check every logged call against a read-only allowlist.
- Re-read an "accepted limitation" in a plan against the mechanism it depends on before inheriting it.
