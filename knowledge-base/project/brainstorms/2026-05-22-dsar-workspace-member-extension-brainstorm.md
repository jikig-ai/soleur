---
date: 2026-05-22
issue: 4230
umbrella: 4229
status: brainstormed
brand_survival_threshold: single-user incident
lane: cross-domain
user_brand_critical: true
---

# DSAR Departed-Member Coverage — Brainstorm (#4230)

## What We're Building

A scoped extension to the DSAR pipeline so members who have **left** a workspace
can still serve GDPR Art. 15 / 17 / 20 requests over their identifiable data in
workspaces they have departed. Combined Approach **A + B**:

- **A (workspaceIds union fix):** `dsar-export.ts:609-670` derives workspace
  metadata from `workspace_members.user_id = X` → empty after removal. UNION with
  historical `workspace_member_attestations.invitee_user_id = X` to restore
  workspace context in the export bundle. Symmetric fix at `:678-697` so
  inviter-side attestation rows surface under a departed inviter's identifier.
- **B (removal-event ledger):** new `workspace_member_removals` WORM table
  matching the existing attestations pattern, written by `remove_workspace_member`
  RPC inside the same transaction as the DELETE. Closes the Art. 15 lineage gap
  ("you were removed from $workspace on $date by $whom"). Added to the DSAR
  allowlist with WORM-bypass + GUC for retention sweep.
- **Mixed-ownership predicate:** `dsar-export-allowlist.ts` gains an
  author-only predicate; ex-member's own messages are returned in full;
  messages they sent that **other members later quoted/replied to** are
  returned with author-content redaction + thread-position metadata only.
- **Integration test:** golden-fixture for the departed-Harry path.
- **Legal docs ride PR #4289** (open WIP `feat-team-workspace-legal-scaffolding`)
  — DPD §2.3, privacy-policy, gdpr-policy, `article-30-register.md` departed-member
  language. This PR cross-links #4289.

**Scope cut (explicit):** no public/unauthenticated DSAR intake form, no
`workspace_members.left_at` soft-delete column, no JWT/session changes to
`dsar-reauth.ts`. Accountless ex-members are served via `legal@jikigai.com`
admin-mediated runbook (documented, not built as UI).

## Why This Approach

Reframing established by Phase 0.5 leader + research convergence:

1. **Issue title was misframed.** No `workspace_member_id` surrogate exists;
   composite PK is `(workspace_id, user_id)`. And `dsar-reauth.ts` needs no
   changes — `auth.users` row survives workspace removal, the existing
   service-role export already returns the ex-member's user-keyed rows
   (CTO + learnings consensus; see `tasks.md` 7.1 re-scope from #4225).
2. **A alone closes the brand-survival path.** Approach A is ~1-2 days and
   eliminates the orphan-rows-without-context outcome. But operator chose
   A + B together to capture Art. 15 lineage ("removed on $date by $whom") in
   the same PR rather than spawning a follow-up. Cost: 3-5 days total. Risk:
   medium (new WORM table + RPC). ADR required per CTO assessment.
3. **Author-only redaction** satisfies Art. 15 (subject's own data) and
   Art. 17(3)(b)/(e) carve-outs (don't leak surviving members' data when
   they appear adjacent in threads). CLO + CPO converged on this rule.
4. **Authenticated-only intake** matches the EDPB 01/2022 step-up baseline
   already embedded in `dsar-reauth.ts`. Expected ex-member volume at the
   first-external-workspace gate is &lt;5 lifetime (CPO estimate) — a public
   form is YAGNI before that volume materializes; `legal@jikigai.com` is
   the audited fallback today.
5. **Legal-doc updates ride PR #4289**, not this one. #4289 is the umbrella's
   coordinated legal corpus PR; landing fragmented departed-member text in
   #4230's PR risks stale framing if #4289 lands first.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Brand-survival threshold: **single-user incident**.

Vectors and the surface that gates each:

1. **Cross-tenant leak via departed-member export** — the author-only
   redaction predicate in `dsar-export-allowlist.ts` is load-bearing. If
   absent, ex-member's bundle contains surviving members' message content.
   Mitigated by: integration test asserting redaction; predicate review.
2. **Incomplete export breaching Art. 15** — workspaceIds union fix is
   load-bearing. If absent, ex-member receives rows without workspace
   metadata and the export fails Art. 15 completeness.
3. **Statutory clock missed** — operator-side admin runbook for
   accountless ex-members is load-bearing. Documented in `knowledge-base/legal/`
   so support@ handoff has a defensible path within the 1-month Art. 12(3)
   window.

The `user-impact-reviewer` agent at PR review is the load-bearing gate;
plan must inherit this section verbatim and the integration test for the
departed-Harry redaction path must be present.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Approach | A + B combined in same PR | Operator chose to capture lineage now rather than follow-up |
| `left_at` soft-delete column? | No | Hard DELETE preserved; lineage moves to new `workspace_member_removals` table |
| Identity verification surface | Authenticated `/dashboard/settings/data-export` only | EDPB 01/2022 + YAGNI for &lt;5 lifetime volume at gate |
| Accountless ex-members | `legal@jikigai.com` runbook (documented, not UI) | CPO + learnings; no separate public form |
| Mixed-ownership rule | Author-only redaction with thread-position metadata | Art. 15 own-data + Art. 17(3)(b)/(e) carve-outs |
| Legal docs PR | Ride in PR #4289 (legal scaffolding WIP) | Avoids fragmented framing; cross-link both PRs |
| Pre-existing `ON DELETE RESTRICT` Art. 17 cascade bug | File separate P1 issue | Surfaced here but not owned by #4230 |
| `runtime_cost_state` RLS coverage | File separate issue to confirm | Repo-research flagged it absent from #4225 sweep |
| Public/unauth DSAR form | Defer; needs separate brainstorm | Learnings + CPO; no demand signal at gate |
| `workspace_member_removals` WORM ledger | Build now (Approach B) | Operator chose to bundle in same PR |
| ADR required? | Yes — schema invariant per CTO | `workspace_member_removals` is a permanent invariant future Art. 17 cascades must respect |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.
**Spawned:** Engineering (CTO), Product (CPO), Legal (CLO). Triad spawned per
`USER_BRAND_CRITICAL=true` cross-domain lane.

### Engineering (CTO)

**Summary:** Issue title misframed (no `workspace_member_id` surrogate; `dsar-reauth.ts` already handles departed users via surviving auth row). Real gap is workspace context orphaning at `dsar-export.ts:609-670`. Approach A (1-2 days, zero schema), B (3-5 days, new WORM ledger + ADR), C (1-2 weeks, soft-delete column) sized. Recommends A; flags pre-existing `ON DELETE RESTRICT` blocking Art. 17 cascade and `runtime_cost_state` not in #4225 RLS sweep.

### Product (CPO)

**Summary:** Target user at gate is operator's 10-person prospect; ex-member volume &lt;5 lifetime. Recommends extending authenticated `/dashboard/settings/data-export` for case-(a) ex-members (active Soleur login), `legal@jikigai.com` runbook for case-(b) accountless ex-members. Endorses author-only redaction with thread-position metadata for mixed-ownership. Scope: 1-3 days minimum. Flags roadmap.md staleness (team-workspace pivot not reflected).

### Legal (CLO)

**Summary:** 3 GO/NO-GO gates for `FLAG_TEAM_WORKSPACE_INVITE=1` flag-flip: (1) resolve `workspace_members.user_id ON DELETE RESTRICT` vs Art. 17 cascade (pre-existing, surfaced here); (2) `dsar-export-allowlist.ts` gains quoted-content predicate before ex-member export path; (3) unauthenticated inbound DSAR route + admin clock tracker. Operator selected scope-cut: gate (1) becomes separate issue, gate (2) ships in this PR, gate (3) defers to runbook. Art. 5(1)(e) defensibility: 36-mo retention if any new ledger.

## Capability Gaps

- **Engineering:** schema migration for `workspace_member_removals` WORM table (Approach B). Evidence: `grep -rn "CREATE TABLE.*workspace_member_removals" apps/web-platform/supabase/migrations/` → zero hits.
- **Engineering:** `remove_workspace_member` RPC needs to write the removal-event row before DELETE inside the same transaction. Evidence: `058_workspace_member_attestations.sql:320-321` shows current RPC is a single DELETE with no audit-side write.
- **Engineering:** `dsar-export-allowlist.ts` needs author-only/quoted-content predicate. Evidence: `grep "quoted\|author_only" apps/web-platform/server/dsar-export-allowlist.ts` → zero hits.
- **Engineering:** Integration test fixture for departed-Harry path. Evidence: `grep -l "departed\|left_workspace\|ex-member" test/server/dsar-*.test.ts` → zero hits.
- **Legal:** Departed-member language in DPD §2.3, privacy-policy.md, gdpr-policy.md, `article-30-register.md` row. Evidence: repo-research `grep "departed|leaver|former member|left workspace|removed member" docs/legal/` → zero hits. Will land in PR #4289.
- **Operations:** `legal@jikigai.com` admin runbook for accountless ex-member DSAR fulfillment. Evidence: no existing runbook found under `knowledge-base/operations/runbooks/`.

## Open Questions

1. Does `workspace_member_removals` use the existing `anonymise_workspace_member_attestations` shape (NULL-out PII columns, preserve `id` + timestamps) or introduce a new shape? Plan time.
2. Should the removal row include `removed_by_user_id` (for "who removed me" lineage) or just `removed_at`? CLO leans yes; CTO neutral. Plan time.
3. Retention window for `workspace_member_removals`: CLO suggested 36 mo (Art. 82 limitation). Confirm against existing 24-mo `dsar_export_audit_pii` envelope at plan time.

## Productize Candidates

None this brainstorm — work is project-specific, not a recurring pattern.

## Deferred Follow-ups (to file as separate issues)

1. **Pre-existing P0:** `workspace_members.user_id ON DELETE RESTRICT` blocks Art. 17 cascade. Surfaced by this brainstorm but pre-existing in PR #4225 / mig 053. Should be P1; resolve before next user-account-deletion attempt against a workspace member.
2. **`runtime_cost_state` RLS coverage** — was NOT in the #4225 RLS sweep (only `046` owns it). Confirm whether the table needs a `workspace_id` column + `is_workspace_member` predicate or has a defensible reason for exclusion.
3. **Public/email-proof DSAR intake form** — re-evaluate when first accountless ex-member DSAR fires OR when external workspace count exceeds 5. Requires its own brainstorm.
4. **Roadmap.md update** — add team-workspace pivot post-PR #4225; CPO flagged staleness.

## Session Errors

None significant. All cited blockers verified open/closed (umbrella #4229 CLOSED; #3637 CLOSED via #3634 on 2026-05-12; `dsar-reauth.ts` exists on main). Premise probe at Phase 0 caught no stale claims before leader spawn.
