---
feature: feat-one-shot-6178-soak-explained-pins
issue: 6178
plan: knowledge-base/project/plans/2026-09-25-feat-inngest-soak-6178-explained-pins-plan.md
---

# Decision challenges — feat-one-shot-6178-soak-explained-pins

Taste findings from plan review, persisted headless for `ship` to render. None changes this
PR's scope.

## DC-1 — Pluralise "outside the explained bucket" in the verdict lines (taste, for #8626)

**Source:** CTO plan-review seat (devex lens), P2.

**Finding:** after this PR, the verdict lines still say "outside the explained bucket" (singular),
while the comment above them lists four `explained_why: bucket=` lines.

**Why this PR does not change it:** both verdict printfs are lines that draft PR #8626 rewrites
(its SNAPSHOTS change). Editing them here would conflict with #8626 and take over its scope, which
the brief forbids.

**Disposition at review (2026-09-25):** the NOT CLEAN verdict line is not in #8626's diff, so this
PR changed it to "outside the explained set" (the phrase ADR-100 uses). The CLEAN verdict line
is inside #8626's hunk and stays singular here; a note on #8626 asks for the same wording there.

**Original suggested disposition:** #8626 pluralises the wording ("outside the explained buckets") when it
rewrites those printfs. The reading stays correct either way: every explained bucket is named on
its own line. This is wording only, and the probe is retired after the #6178 close.

## DC-2 — Prefix each `why` with its exact bucket window (taste)

**Source:** CTO plan-review seat, P3.

**Finding:** `bucket=1491540` is opaque to a reader. Proposal: start each `why` with the exact
window (e.g. `2026-09-19T20:00–20:20Z`).

**Why not adopted by default:** each `why` already starts with its date and time, and the exact
window is printed on the matching `explained:` line directly above. It would also spend about
20 bytes per line against the sweeper's 4000-byte tail, where the clean-arm estimate is already
about 3600 bytes.

**Suggested disposition:** do not adopt. At deepen-plan, a scratch build measured C26q at 3881 of
4000 bytes, so only 119 bytes of headroom. The why strings were shortened to 110 bytes or less for
this reason.
