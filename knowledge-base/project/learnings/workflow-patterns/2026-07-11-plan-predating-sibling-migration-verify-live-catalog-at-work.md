---
title: "A plan authored against an unmerged PR's HEAD can go stale when a sibling migration lands — verify LIVE catalog facts at /work Phase 0, not the plan's quoted premises"
date: 2026-07-11
category: workflow-patterns
tags: [plan-staleness, precondition-verification, rls-fuzz, catalog-facts, sibling-migration, dependency-rebase]
issue: 6307
---

# A plan authored against an unmerged dependency can carry stale premises — re-verify the live catalog at /work

## Problem

The #6307 plan (deepen the RLS/authz-fuzz harness) was *deepened* on 2026-07-11
against the **HEAD of the still-unmerged #6255 branch** (its hard dependency). It
gated `/work` on "#6255 merged + rebase onto main," which is correct — but between
plan time and merge, a **sibling migration** (`128_revoke_definer_rpc_residual_grants`,
PR #6318) landed on that same branch and **closed #6306** (revoked the residual
anon/authenticated EXECUTE on `find_stuck_active_conversations` +
`acquire/release/touch_conversation_slot`).

So the plan's **Item 4 — "drive the 4 #6306 fns under `anon`"** rested on a premise
that was already false in the merged tree: those fns are revoked, dropped from the
`securityDefinerAuthenticatedFns` catalog, and `KNOWN_EXPOSURES = {}`. The plan even
*validated* the premise at plan time ("the four fns carry `has_function_privilege('anon',
…)`") — but that was a plan-time reading of a moving target. A second premise was also
stale: the plan assumed "Supabase default privileges grant anon EXECUTE broadly → the
anon set ≈ authenticated set," but the LIVE anon-EXECUTE SECURITY DEFINER set was
**empty** (0 fns).

Both were caught at **/work Phase 0** by running the actual catalog query against the
migrated local DB (`has_function_privilege('anon'/'authenticated', oid, 'EXECUTE')`)
rather than trusting the plan — which is exactly what the plan's own G0.4 "confirm the
premise against the live catalog" gate prescribed. Had the premises been trusted, Item 4
would have produced test cases attacking fns that no longer exist in the catalog (a
vacuous or un-compilable dimension).

## Solution

When a plan is authored against an **unmerged dependency's HEAD** and quotes catalog /
grant / policy facts (`has_function_privilege`, `pg_policies` shapes, which fns are in
`KNOWN_EXPOSURES`), treat every such fact as a **precondition to re-derive at /work
Phase 0 against the freshly-migrated live DB**, not a fact. A sibling commit on the same
dependency branch — especially a migration — can obsolete a whole plan item between plan
and merge. Reconcile explicitly:

- Item 4's concrete "attack the 4 #6306 fns under anon" was **dropped as obsolete**.
- The **durable half** — a `securityDefinerAnonFns()` enumerator + an anon coverage gate
  (a forward tripwire that reds if any *future* migration re-introduces an anon EXECUTE
  grant, the exact #6306 root cause) — was shipped in its place. The reconciliation was
  recorded in-code, in the ADR amendment, and surfaced to the operator before committing
  the rest of the pipeline.

## Key Insight

"The plan validated the premise at plan time" is NOT "the premise holds at /work" when
the plan predates the dependency's merge. This is `hr-when-a-plan-specifies-relative-paths-e-g`
and the "plan-quoted numbers are preconditions to verify" rule applied to **catalog
state**: the highest-risk staleness is not a line number but a *grant/policy fact a
sibling migration silently flipped*. Re-run the authoritative query at Phase 0; if it
falsifies a plan item, salvage the durable/general capability (an enumerator tripwire
that would have auto-caught the very thing that changed) rather than either forcing the
obsolete work or dropping the item entirely.

## Session Errors

None materialised — the /work Phase 0 catalog verification caught the stale premises
before any obsolete code was written. Recorded here so the next plan-against-unmerged-
dependency run re-derives catalog facts by default.
