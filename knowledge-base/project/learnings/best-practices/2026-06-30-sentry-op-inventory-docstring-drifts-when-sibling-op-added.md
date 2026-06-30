# Learning: a central op-inventory docstring drifts silently when a sibling op is added at the emit site

## Problem

`apps/web-platform/server/observability.ts` carries a hand-maintained
"op-inventory" docstring that enumerates each Sentry op family and its
semantics (level, dedup key, when it fires). PR #5734 added two new ops to the
`workspace-reconcile-push` family at the emit site
(`server/inngest/functions/workspace-reconcile-on-push.ts`) —
`multiple-owners-reconcile` (info breadcrumb) and `owner-attribution-probe`
(warn via `reportSilentFallback`) — beside the already-documented
`ownerless-reconcile`, but did NOT add them to the inventory docstring. The
inventory listed 1 of 3 sibling ops. `tsc` and the full vitest suite are blind
to this: the docstring is a comment, so nothing fails. The drift surfaces only
when an operator greps the inventory for the op family and finds an incomplete
list — a discoverability paper-cut, not a runtime bug. #5591 was re-scoped to
close exactly this gap.

## Solution

Add the two missing ops to the `workspace-reconcile-push` family entry,
verbatim-faithful to the emit site: each sentence states the op's level
(info breadcrumb vs. warn via `reportSilentFallback`), its trigger (≥2 owners
vs. transient owner-read DB error — explicitly NOT the zero-owner drift warn),
and its payload. Cross-check every claim against the source emit lines before
writing — a hallucinated level/trigger in an inventory is worse than an
omission. Docstring-only; no code path, no new emit site.

## Key Insight

When a PR adds a sibling member (Sentry op, enum case, error class, route)
to an emit/registration site that has a **central human-maintained inventory**
(a docstring catalogue, a README table, a `KNOWN_OPS` const), updating the
inventory belongs in the SAME PR — the compiler and the test suite cannot see
inventory-comment drift, so it ships green and rots. Cheapest gate at the emit
site: when you add an op next to a documented sibling, grep the inventory for
the sibling's name; if it's there, your new op goes beside it.

This is the observability-inventory analogue of the existing data-layer "sweep
all mock chains / all consumers when extending a shared shape" rules — same
class (a maintained list that `tsc` doesn't enforce), different artifact.

## Session Errors

1. **deepen gate 4.6 required a `threshold: none` scope-out bullet** because
   `server/observability.ts` matches the canonical sensitive-path regex via the
   `apps/web-platform/server` prefix. — Recovery: bullet added in the deepen
   pass. — Prevention: already enforced by deepen-plan 4.6 + work preflight
   Check-6; one-off, no new rule needed.
2. **`#5673` mislabeled MERGED in the plan when it is OPEN.** — Recovery:
   corrected in two places during the deepen citation-verify pass. — Prevention:
   already covered by deepen's `gh`-verify-every-citation step; one-off.

(No errors in the implementation session — collision check, tsc, and all ACs
passed first try. The MERGED-PR-#5716 collision signal was correctly
discriminated as a cited-predecessor false-positive by the existing
`closingIssuesReferences` probe.)

## Tags
category: best-practices
module: apps/web-platform/server/observability
