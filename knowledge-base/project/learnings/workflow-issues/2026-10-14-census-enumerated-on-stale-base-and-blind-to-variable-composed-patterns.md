---
title: Derived censuses inherit the enumeration base and the shape assumption — both must be re-proven, not assumed
date: 2026-10-14
category: workflow-issues
tags: [consumption-census, derived-vs-member-list, worktree-rebase, regex-factoring, review-panel]
symptoms: [a boundary-anchored gate (ship-kb-archive-gate.sh) was absent from the plan's site inventory and invisible to the new consumption census while green]
module: plugins/soleur
component: test-machinery
problem_type: silent_drift
resolution_type: guard_widened
root_cause: enumeration ran on the pre-rebase base; the candidacy predicate assumed the pattern shape (literal `(^|` + gated command on one line)
severity: medium
---

# Learning: a census certifies the sites its DERIVATION can see — the derivation is the attack surface, not the registry

## Problem

Two independent blind spots in `plugins/soleur/test/boundary-prefix.test.sh` (PR #10288), both found by the review panel after the suite was green:

1. **Base staleness.** The site inventory ran on `feat-fcc-token-optimizations` (the pre-rebase base). `ship-kb-archive-gate.sh` landed on `origin/main` mid-work via a different PR; after `rebase --onto origin/main` the branch's diff was clean — but the enumeration had already been checked off. The gate's `_MERGE_PREFIX` had no `rtk` atom, so `rtk gh pr merge` bypassed `wg-kb-artifacts-archived-in-pr` — the exact severity-1 class the PR existed to close, on a gate enforcing a hard rule.
2. **Shape assumption.** The candidacy predicate required a literal `(^|` alternation AND a gated-command literal on the same line. `ship-kb-archive-gate.sh` factors its trigger into `_MERGE_BOUNDARY`/`_MERGE_PREFIX`/`_GH_GFLAGS` variables — zero candidate lines, so the census passed while the site was unhandled. The newest sibling gate had already chosen the factored-var idiom, making the blind spot a recurring class, not an accident. Three further shape gaps surfaced in review: consumption grepped the raw line while candidacy stripped comments (a `${SOLEUR_BOUNDARY_PFX` inside a trailing comment faked compliance), provision was grepped without comment-stripping (`# shellcheck source=` satisfied it), and interpolation ≠ provision (a site could reference the var without sourcing the carrier).

## Solution

- **Re-derive post-rebase.** Any enumeration gated on a list derived from a base commit must re-run after `rebase --onto` — the diff going clean does not mean the inventory stayed true; new files arrive silently. The guard that catches this is a census that cannot see the file, so the fix compounds with the next one.
- **Second candidacy class for variable-composed patterns.** Lines referencing `${…BOUNDARY|PREFIX…}` next to a gated literal become `composed` candidates; consumption is judged at file level (the composed definition must name a shared atom var), not line level, because variable composition exists precisely to avoid restating the var at every usage site.
- **Comment-strip EVERYTHING the census reads.** Candidacy strips comments; consumption, provision, and composed checks must strip identically (and `grep -v | grep -q` under pipefail SIGPIPEs the producer on early match — use one awk pass).
- **Provision arm separate from consumption.** Interpolating `${SOLEUR_BOUNDARY_PFX` is not the same as sourcing `incidents.sh`/`wrapper-boundary.sh` — a file can green the census while running the `:-` degraded path forever. Assert the carrier `source` on every consuming file.

## Key Insight

A derived census's failure mode is not a stale member list — it is the *derivation itself*: the base it ran on, the pattern shapes it assumes, and the strip rules its separate arms apply asymmetrically. Each arm of the census needs the same rigor as the thing it guards. When a review seat says "the newest sibling already uses idiom X", widen candidacy to that idiom — the newest file is the most likely to have been missed.

Evidence: `plugins/soleur/test/boundary-prefix.test.sh` (composed pass, provision arm, comment-strip symmetry); `.claude/hooks/ship-kb-archive-gate.sh:133-140`; panel reports in session-state.md (PR #10288).
