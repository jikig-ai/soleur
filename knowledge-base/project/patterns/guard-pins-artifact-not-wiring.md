---
title: "Guard pins the artifact, not the wiring"
summary: "Guards that assert a string, value or helper exists stay green when the wiring is cut; reverting the central edit must turn at least one test red."
status: open
opened_on: "2026-10-24"
tags: [guards, wiring, mutation-testing, terraform, cloud-init]
evidence:
  - knowledge-base/project/learnings/2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
  - knowledge-base/project/learnings/2026-07-27-my-battery-was-green-because-it-only-tested-the-two-endpoints-not-the-wire.md
  - knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md
  - knowledge-base/project/learnings/2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md
  - knowledge-base/project/learnings/2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md
  - knowledge-base/project/learnings/2026-08-12-i-proved-the-transform-and-left-its-application-and-its-size-unpinned.md
required_reading: false
---
## Root cause

Assertions over a file search a domain wider than the property they claim. A producer test and a
consumer test can both pass while nothing proves they are connected, a helper can be unit-tested with
no check that anything calls it, an extracted expression says what it is and not whether it is
applied, and a line found in a file may sit where it never executes (another process, a data
heredoc). The binding often lives in a condition rather than in token order, so order comparisons
and presence checks read green with the wiring severed.

## Fix

Narrow the search space to the property's domain (the shell region that runs, the rendered output
that boots) and pin the connection between endpoints: a seam that makes wiring drivable, a
source-level assertion that no bypass form survives, and a check on the applied result and its size.
A useful litmus is to name the edit that reverts the change's central behaviour and confirm a test
reds; when none does, the thesis is pinned by nothing. Where one side of a symmetric design has a
ratchet, the other side gets one as well.

## Evidence

- knowledge-base/project/learnings/2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md
- knowledge-base/project/learnings/2026-07-27-my-battery-was-green-because-it-only-tested-the-two-endpoints-not-the-wire.md
- knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md
- knowledge-base/project/learnings/2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md
- knowledge-base/project/learnings/2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md
- knowledge-base/project/learnings/2026-08-12-i-proved-the-transform-and-left-its-application-and-its-size-unpinned.md
