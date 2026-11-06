---
title: "A declared AFFECTED_*_PATHS block unions with derived edges at runtime — it does not replace them"
date: 2026-11-06
category: workflow-patterns
tags: [affected-index, ratchet, ci, s4]
related: [ADR-276, "#10865", "#12217"]
---

# Declared edge blocks union with derived edges, not replace them

When a suite row gains an `AFFECTED_<LABEL>_PATHS` block in `scripts/lib/test-affected-paths.sh`, its derived edges are NOT dropped: `scripts/test-all.sh` computes `declared ∪ derived` at execution time (and the audit's edge_hit reads the same union — `test-all.sh` rungs 2-3 union with rung 4; `ci-pr-affected-replay.py` `edge_hit` consults the union). Only the `--print-selection` presentation can mislead one into reading the block as the whole edge set.

Consequences measured while repairing the #10865 soak pause (PR #12217):

- Literal-mention derived edges (e.g. `apps/web-platform/scripts/constraint-gates.sh` named in fixture text) persist after the block lands — the pair is never re-flagged, so **no accept row is needed** and the suite keeps over-selecting on those files (the designed fail-safe direction; structurally unremovable by declaration).
- Status text written against the "replaces" premise over-claims: say "the index no longer *declares* X", never "the suite is un-selected by X".
- Accept-anchor staleness still applies to edits of the suite's mention lines — re-verify the ratchet on the merged tree before arming, after every sibling merge while queued.
