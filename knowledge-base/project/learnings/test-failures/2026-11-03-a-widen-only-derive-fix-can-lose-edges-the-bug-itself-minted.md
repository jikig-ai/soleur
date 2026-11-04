---
title: "a widen-only derive fix can lose edges the bug itself minted — adjudge stream-diff losses by edge provenance, not by direction"
date: 2026-11-03
category: test-failures
tags: [ci-pr-affected, derive-gap, edge-declaration, guard-floor]
---

# Learning

## Problem

The extractor fix for the unwalked-SUT gap — tolerating
`$(cd "<dir>" 2>/dev/null && pwd)` prefixes and stripping
`" || var="` residue in `_affected_edge_token` — is a **widen-only** change
under the Guard-1 invariant (selection may only grow). Yet the base-vs-head
`--print-selection` stream diff reported edge **losses**: `image-cve-triage`
lost `^scripts/betterstack-query.sh` + `^scripts/lib/test-affected-paths.sh`,
`emissions` lost `^plugins/soleur/test/lib/`, ~30 suites lost similar `^dir/`
edges. On its face, Guard-1 violated.

## Root cause

The lost edges were **minted by the bug being fixed**. The var map's greedy
quoted capture carried the ` || var="` fallback tail into resolved values
(`libdir="$(cd …)" || libdir=""` in the stem-minted-SUT probe idiom), so
`$physical/.soleur-fixture-xdg`-class tokens collapsed to a *directory* —
minting `^scripts/lib/`, `^plugins/soleur/test/lib/` edges for fixture paths
that do not exist in the tree. Stripping the residue
(`scripts/test-all.sh:3491-3497`, `" || [A-Za-z_]*="` removed before any arm
runs) lets the token resolve to its true target — a nonexistent fixture path
that `-e` drops — so the phantom dir edges disappear. Every real dependency
of those suites survives as a *file* edge (`git-fixture-env.sh`,
`session-state.sh`, …). CTO ruling (`decision-challenges.md`, this spec dir):
**bug-correction, not a Guard-1 violation**. Accepted selection effect: a NEW
file created under those dirs no longer selects the suites — false-edge noise
outweighed residual coverage.

## Rule

A widen-only invariant means "no *legitimate* edge is lost", not "the edge
set is monotone". When a stream diff (or any selection/edge regression gate)
reports losses on a change that only adds tolerance/normalization arms:

1. Take each lost edge and ask **what minted it** — replay the OLD extractor
   path on the same token and check whether the edge's referent exists in the
   tree (`-e`/`test -f`). A phantom edge's referent does not exist; a real
   coverage edge's does.
2. Phantom-minted losses are bug-corrections — record the ruling (with the
   surviving real-edge list as evidence) rather than reverting the fix.
3. Check the residual selection effect before accepting: does any *real*
   future file under the stripped dir lose coverage? Name it explicitly in
   the ruling so reviewers can weigh it.
4. The same reasoning applies to the `$(cd … [redirect] && pwd)` D1 arm
   (`scripts/test-all.sh:3498-3518`): an unmatched spelling falls through to
   the greedy `$(cd*pwd)` collapse, which mints the file's own dir — a
   "lost" `^dir/` edge after a D1 widening is usually that collapse
   corrected, and D1's `_alt` re-run (:3553-3555) already protects genuine
   narrowings.

## Session Errors

(See the companion learning's full session-error inventory —
`2026-11-03-one-malformed-accept-row-reason-drops-every-exemption.md`.
Routing note: a `soleur:review` Sharp-Edges bullet carrying this adjudication
rule was drafted and then REVERTED — `review/SKILL.md` sits exactly at its
`skill-body-budget.json` ceiling (475921 bytes, zero headroom), so no
route-to-definition edit can land in this PR; re-attempt when a budget PR
opens headroom.)

- **Guard-1 stream-diff edge losses needed a ruling before the invariant
  could be certified** — Recovery: provenance check on each lost edge +
  inline-CTO ruling recorded in `decision-challenges.md` (residue-strip row).
  Prevention: run the provenance check in step 1 above before escalating any
  widen-only gate failure — most "losses" on a tolerance-adding diff are the
  bug's own mintings.

## Evidence

PR #11958, `scripts/test-all.sh` `_affected_edge_token` (:3491-3518) and the
BFS frontier seeding (:3918-3932); commit `6c606491de` (derive walks
stem-minted SUTs + 73-pair reveal drain); `47769b376d` records the Guard-1
ruling. Builds on `2026-11-02-stem-minted-suts-are-never-walked-by-the-derive.md`
(the gap this fix retired); the widened derive's drain obligation is
`2026-11-03-one-malformed-accept-row-reason-drops-every-exemption.md`.

## Tags

category: test-failures
module: ci-pr-affected
