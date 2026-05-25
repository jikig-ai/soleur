---
title: WORM ledger tables with SECURITY DEFINER RPC writers must NOT carry an owner-insert RLS policy
date: 2026-05-21
category: security-issues
module: apps/web-platform/supabase
related_prs: [4213]
related_issues: [4078, 4236]
related_learnings:
  - 2026-04-18-rls-for-all-using-applies-to-writes.md
  - 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
tags:
  - rls
  - worm
  - security-definer
  - supabase
  - postgrest
  - multi-agent-review
  - bounded-columns
---

# WORM ledger RLS owner-insert policy is an RPC bypass

## Problem

PR-I (#4078, PR #4213) added the `template_authorizations` WORM ledger at migration 053. The migration mirrored mig 051's `action_sends` shape, including an owner-insert RLS policy:

```sql
CREATE POLICY template_authorizations_owner_insert ON public.template_authorizations
  FOR INSERT TO authenticated
  WITH CHECK (founder_id = auth.uid());
```

This policy looks correct in isolation — the founder can only INSERT their own rows. But the table is designed to be written **exclusively** through the `authorize_template` SECURITY DEFINER RPC, which:

- Validates `p_template_hash` length (1-128 chars).
- Validates `p_action_class` regex.
- Catches 23505 partial-UNIQUE conflicts and returns the existing winner's id (idempotent first-writer-wins).
- Uses `auth.uid()` to populate `founder_id` (caller cannot specify it).

With the owner-insert policy present, an authenticated founder can bypass the RPC entirely by calling supabase-js directly:

```ts
await supabase.from("template_authorizations").insert({
  founder_id: user.id,
  template_hash: "deadbeef...",
  action_class: "finance.payment_failed",
  grant_id: "<any-active-grant>",
  max_sends: 999999,
  expires_at: "2099-01-01",
});
```

This admits an arbitrary-bound authorization row, defeating the plan's Art. 7(3) "specific" + "informed" consent envelope (provisional bounds 100 sends / 30-day soft re-confirm / 90-day hard expiry).

Surfaced by PR-I multi-agent review (user-impact-reviewer FINDING 8); the four prior plan-review and brainstorm rounds did NOT catch it.

## Root cause

The mistake was treating mig 051 (`action_sends`) as the universal template for ledger RLS. The two tables have different writer paths:

| Table | Writer | RLS owner-insert policy correctness |
|---|---|---|
| `action_sends` | Cookie-scoped supabase-js INSERT from `apps/web-platform/server/action-sends/write-action-send.ts` | **NEEDED** — the legitimate writer is a direct INSERT, so RLS gates it. |
| `template_authorizations` | SECURITY DEFINER RPC `authorize_template` only | **HARMFUL** — the RPC ignores RLS (SECURITY DEFINER), so the policy provides nothing to the legitimate writer but opens a bypass to the same client. |

The mirror failed because the surface I copied (RLS policy block) was correct for the source table but wrong for the destination's writer architecture. **A correct policy for table A can be a vulnerability on table B if A's and B's writer paths differ.**

## Solution

Remove the owner-insert policy from mig 053; keep owner-select (founders still need to read their own rows for the scope-grants page). The down migration runs `DROP POLICY IF EXISTS template_authorizations_owner_insert` as belt-and-suspenders so re-applying on a dev DB that landed the prior shape converges to the right posture.

```sql
-- (d) RLS — owner-select only. NO FOR ALL USING per learning
--     2026-04-18-rls-for-all-using-applies-to-writes.md. NO owner-insert
--     policy because the SECURITY DEFINER `authorize_template` RPC
--     is the ONLY supported writer; SECURITY DEFINER bypasses RLS so
--     the RPC is unaffected, while the absence of an INSERT policy
--     denies direct supabase-js INSERTs that would otherwise bypass
--     the RPC's input validation and let a founder self-mint an
--     arbitrary-bound authorization row.
ALTER TABLE public.template_authorizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS template_authorizations_owner_select ON public.template_authorizations;
CREATE POLICY template_authorizations_owner_select ON public.template_authorizations
  FOR SELECT TO authenticated
  USING (founder_id = auth.uid());

-- Belt-and-suspenders: explicitly drop any pre-existing owner-insert
-- policy from earlier mig 053 drafts.
DROP POLICY IF EXISTS template_authorizations_owner_insert ON public.template_authorizations;
```

This collapses the writer surface to the single SECURITY DEFINER RPC, which is the load-bearing invariant ADR-035 promised but the original RLS didn't enforce.

## Key insight

When writing a new RLS policy block on a WORM ledger, FIRST classify the table's writer path:

1. **Cookie-scoped supabase-js writes** (e.g., action_sends, scope_grants): keep owner-insert policy; the RLS IS the gate.
2. **SECURITY DEFINER RPC writes only** (e.g., template_authorizations, anonymise_*, runtime_mint_intent): OMIT owner-insert policy. SECURITY DEFINER bypasses RLS; the policy gates nothing for the legitimate writer but admits a direct-INSERT bypass to anyone who reads the schema.

The "implicit deny on no policy" is the correct posture for the SECURITY-DEFINER-only case. Adding a policy "for parity with sibling tables" is a load-bearing security mistake when the sibling's writer architecture differs.

## Detection

Cheapest grep: for any new RLS owner-insert policy on a WORM table, find the table's writer site:

```bash
# Does any supabase-js call write to this table?
git grep -nE "\.from\(['\"]<table_name>['\"]\)\s*\.insert\(" apps/web-platform/

# Does a SECURITY DEFINER RPC write to it?
git grep -nE "INSERT\s+INTO\s+public\.<table_name>" apps/web-platform/supabase/migrations/
```

If the first grep returns zero hits AND the second returns ≥1, the owner-insert policy is gating nothing and creating a bypass — remove it.

## Cross-cutting implication

The same anti-pattern may exist on other tables that ship a SECURITY DEFINER writer + an owner-insert RLS policy. Issue [#4236](https://github.com/jikig-ai/soleur/issues/4236) tracks the broader audit (5 anonymise RPCs share a related cross-cutting concern — `GRANT EXECUTE TO authenticated` admits direct self-erasure without ceremony). The RLS-vs-RPC writer audit is adjacent: walk every RLS policy on a table that ALSO has a SECURITY DEFINER INSERT/UPDATE RPC and verify the policy is gating something real.

## Prevention

1. **Migration template checklist:** Before copying an RLS policy block from a sibling migration, identify the destination table's writer architecture and confirm it matches the source. Add a 3-row table to mig comments (writer, gates needed, policy decision) so the reasoning is visible to future reviewers.
2. **Multi-agent review is the load-bearing detection mechanism here.** Plan-time review by 5 specialist agents missed this; post-implementation review by 6 specialist agents caught it. The pattern is consistent with learning `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` (defect class: "Validator scope on sibling message fields" generalizes to "policy scope on sibling table writer architectures").
3. **Routing rule for /plan:** When the plan declares a new WORM table with SECURITY DEFINER RPC writers, the plan template MUST specify the RLS policy block EXPLICITLY (not "mirrors sibling table"). The owner-insert decision is per-table, not template-derived.

## Session Errors

(See compound Phase 0.5 inventory for the full list; the most generalizable items below feed into prevention proposals.)

- **CWD persistence trap in Bash tool** — Recovery: used absolute paths or re-cd from worktree root. Prevention: prefer absolute paths in skill-emitted Bash commands; verify CWD via `pwd` before relative `cd`.
- **Migration preflight failures only surfaced by full vitest** — Touched-file subset (test/server/templates/) missed migration-grant lint + DSAR allowlist completeness lint. Recovery: full `vitest run` after Phase 11 caught both. Prevention: work-skill Phase 2 §9 already calls for full-suite exit gate; reinforce that touched-file tests are inner loop, not exit gate.
- **Plan workflow reference drift** — Plan named `apply-web-platform-migrations.yml` which doesn't exist. Recovery: corrected to `web-platform-release.yml#migrate`. Prevention: /plan should grep `.github/workflows/` before naming a workflow file.
- **Plan §Risks transactional claim contradicted by API surface** — Plan claimed supabase-js wraps two RPC calls in a single transaction (the API can't). Recovery: rewrote the §Risks row at multi-agent review. Prevention: /plan's mitigation prose should be falsifiable against the prescribed implementation surface.
- **PA number collision in Article 30 register** — Plan said append PA-16 but PA-16 was already taken. Recovery: filed as PA-18 with documented divergence. Prevention: /plan should grep `## Processing Activity` headings before naming a new PA number.
- **DSAR allowlist file location drift** — Plan said `dsar-export.ts`; actual is `dsar-export-allowlist.ts`. Recovery: edited the correct file. Prevention: /plan should `ls` or `find` the prescribed file before stating its path.
- **RPC accepted entire enum from authenticated callers, gated only at route layer** — `revoke_template_authorization` accepted all 8 reasons; the /api route filtered to founder_revoked but direct RPC call bypassed. Recovery: added `IF auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked'` gate inside the RPC. Prevention: when an enum has N values but only M < N are user-callable, gate at BOTH the route and the RPC. Route gating alone leaves a vector via direct supabase-js RPC calls.
- **23505 recovery SELECT with index-predicate filter creates a race window** — `WHERE revoked_at IS NULL` matched the partial-UNIQUE's WHERE clause; a concurrent revoke between INSERT-fail and SELECT emptied the result, forcing a false re-raise. Recovery: dropped the filter, ORDER BY authorized_at DESC LIMIT 1. Prevention: 23505 recovery queries against partial-UNIQUE indexes must NOT mirror the index's WHERE predicate — the partial-UNIQUE guarantees a winner at INSERT time, but read-committed lets state change before recovery.

## References

- PR #4213 (PR-I) — the implementation.
- Plan v2: `knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md`.
- ADR-035: `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md` (the "writes go through SECURITY DEFINER RPCs" invariant).
- Sibling pattern (different writer architecture, owner-insert legitimately needed): `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql`.
- Multi-agent review surfaced this: user-impact-reviewer FINDING 8 (codified in learning `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` patterns).
- Cross-cutting audit follow-up: [#4236](https://github.com/jikig-ai/soleur/issues/4236).
