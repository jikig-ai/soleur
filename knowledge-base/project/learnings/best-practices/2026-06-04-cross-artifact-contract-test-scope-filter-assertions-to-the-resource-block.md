---
title: "Cross-artifact contract test: scope filter-side assertions to the resource block, not the whole file"
date: 2026-06-04
category: best-practices
tags: [testing, contract-test, sentry, terraform, observability, vacuous-assertion]
pr: 4920
issue: 4918
---

# Learning: cross-artifact contract test must scope filter-side assertions to the resource block

## Problem

A cross-artifact contract test (`sentry-kb-tenant-mint-alert-op-contract.test.ts`,
mirroring `sentry-chat-alert-op-contract.test.ts`) pins op slugs + a feature tag
in BOTH the emit sites (`*.ts`) AND the Sentry alert's Terraform filter
(`issue-alerts.tf`), so a rename on either side breaks CI instead of silently
zeroing the alert's `filter_match = "all"` matches.

The first cut asserted the filter side with whole-file `toContain`:
`expect(tf).toContain(slug)`. That is **vacuous-prone**: the new alert resource's
own leading doc comment mentions one of the slugs literally
(`# ... kb-sync.tenant-mint (sync/route.ts:62) is the identical RuntimeAuthError ...`).
So the per-slug assertion for that slug would pass even if the slug were deleted
from the rule's `IS_IN` value — the comment alone satisfies `toContain`.
`user-impact-reviewer` flagged this as the gate failing open on the removal case.

## Solution

Slice the asserted file down to the **specific resource block** before asserting:

```ts
const RESOURCE_DECL = 'resource "sentry_issue_alert" "kb_tenant_mint_silent_fallback"';
const blockStart = tf.indexOf(RESOURCE_DECL);
const nextResource = tf.indexOf("\nresource ", blockStart + RESOURCE_DECL.length);
const tfBlock = blockStart === -1 ? "" : tf.slice(blockStart, nextResource === -1 ? undefined : nextResource);
// then assert against tfBlock, not tf
```

Two assertions carry the contract:
1. **Per-slug** `expect(tfBlock).toContain(slug)` + `expect(emitFile).toContain(slug)` — proves the slug is present on both sides.
2. **Composite** `expect(tfBlock).toContain(slugs.join(","))` — the comma-joined `IS_IN` value is the LOAD-BEARING removal guard: removing/reordering ANY slug breaks the contiguous substring → RED. This composite string exists ONLY at the filter value, never in prose.

## Key Insight

For a contract test that asserts a literal appears in a config file, the literal
frequently ALSO appears in that block's own explanatory comment. Whole-file (or
even whole-block) per-literal `toContain` is therefore weakly non-vacuous — the
real guarantee comes from a **composite assertion** (the exact comma-joined
multi-value string) that only the live config line can satisfy. Scope per-literal
assertions to the resource block to shrink the comment-collision surface, and lean
on the composite string for the removal/reorder guarantee.

Validation method that settled it: `data-integrity-guardian` empirically mutated
the slug in ONLY the `IS_IN` value (leaving the comment intact) and confirmed the
composite assertion went RED — proving the suite catches removals even before the
block-scoping hardening. The hardening reduces the surface further for the
per-slug checks.

## Review cross-reconcile note

`user-impact-reviewer` (single agent, reasoned-only) rated the whole-file
weakness HIGH; `data-integrity-guardian` (orthogonal, empirical mutation proof)
falsified the stated harm ("removal stays green") because the composite assertion
already caught it. Per the `multi-agent-review-cross-reconcile` sharp edge, the
HIGH was downgraded from a blocker — but the cheap, pr-introduced hardening it
pointed at was still applied inline (block-scoping). Falsified-severity does not
mean "do nothing" when the underlying nudge is a ≤30-line robustness win.

## Session Errors

1. **Multi-match `Edit` on `issue-alerts.tf`** — anchoring on `lifecycle { ignore_changes = [environment] }` matched all 4 alert-resource tails. **Recovery:** re-anchored on the unique `workspace_sync_health` feature-only filter tail. **Prevention:** when appending after the LAST of N structurally-identical blocks, anchor on a token unique to that specific block (here, the only feature-only `filters_v2` with no `op` sub-block), not on the shared closing shape.
2. **`Edit` before `Read` on `apply-sentry-infra.yml`** — tool rejected with "File has not been read yet" (`hr-always-read-a-file-before-editing-it`). **Recovery:** read the target lines, re-applied. **Prevention:** already tool-enforced; no workflow change needed — the harness blocks it deterministically.

Both one-off; no recurrence vector warranting a hook or rule change.
