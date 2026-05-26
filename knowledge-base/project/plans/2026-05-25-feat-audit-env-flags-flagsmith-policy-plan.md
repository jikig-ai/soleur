---
title: "feat: ENV→Flagsmith flag migration with per-org capability and dual-control"
type: feat
date: 2026-05-25
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adr: ADR-038
follow_on_adr: ADR-043
related_specs:
  - knowledge-base/project/specs/feat-audit-env-flags-flagsmith-policy/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-25-audit-env-flags-flagsmith-policy-brainstorm.md
umbrella_issue: 4456
draft_pr: 4455
---

# feat: ENV→Flagsmith flag migration with per-org capability and dual-control

**Decomposition plan for umbrella #4456.** Master/orchestration plan describing the 3-PR sequence (collapsed from initial 6-PR draft per DHH + Code Simplicity plan-review consensus, 2026-05-25). Each PR will get its own dedicated `/soleur:plan` cycle when ready to ship — the per-phase Acceptance Criteria below are the umbrella-level gates the per-PR plans must satisfy.

## Overview

Migrate two tenant-boundary ENV feature flags (`team-workspace-invite`, `byok-delegations`) from env-var toggling to Flagsmith RUNTIME flags under a **dual-control architecture**: Flagsmith carries the skill-operable boolean AND the per-org cohort (via identity-trait `orgId` + `org-targeted` segment rule); env-allowlist (`*_ALLOWLIST_ORG_IDS`) is preserved as defense-in-depth (two independent failure domains per CLO §3). Build the missing per-org Flagsmith capability (ADR-043) **inline with the first consumer** and Flagsmith sub-processor disclosure first; the migration is meaningful, not a no-op. `dev-signin` is **permanently excluded** (DCE tripwire).

Operator override of triad consensus (CTO + CPO + CLO independently said "don't migrate today"); override accepted on basis that the migration buys skill-operable per-org rollout without container restarts AND the missing capability ships with the consumers that use it, not as standalone scaffolding. Full rationale in brainstorm §"Why This Approach".

## Plan-Review History

**v1 (initial draft, 2026-05-25 morning)**: 6-PR sequence (PR-1 legal, PR-2 capability standalone, PR-3 WORM standalone, PR-4 team-workspace-invite, PR-5 byok-delegations, PR-6 dev-signin docs).

**v2 (this version, 2026-05-25 afternoon)**: Collapsed to 3 PRs per plan-review convergence:
- **DHH + Code Simplicity** (independent agreement): cut PR-2 + PR-3 + PR-6 as standalone artifacts. PR-2 per-org capability has zero consumers at merge (placeholder segment matches nothing); WORM ledger ships before any writer; PR-6 ADR appendix is cargo-cult.
- **Kieran P0s** (SQL correctness, blocking): WORM trigger TG_OP check missing; single trigger BEFORE UPDATE OR DELETE creates UPDATE-via-replica-GUC bypass; `session_replication_role='replica'` precedent miscited as mig 043 when 043 actually uses row-state bypass.
- **Code Simplicity tactical YAGNI**: WORM schema collapsed (`target_type + target_value` → single `target` text with prefix; `before_state`/`after_state` jsonb → `before bool`/`after bool` for boolean flips); LRU-bound `_roleCache`; `actor` canonical-format CHECK; pg_cron heartbeat; tenant-dpa-register grep guard at PR-2 merge time.

The collapsed shape: per-org capability + WORM table ship in the SAME PR as the first consumer (PR-2). Both flags migrate in one PR (BYOK's hot-path memoization is the only delta between them and addressable inline).

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| New ADR to be drafted as **ADR-039** | ADR-039 already taken (`departed-member-removal-ledger.md`). Next monotonic slot is **043**. | Renumbered to ADR-043 in plan, brainstorm, spec, umbrella issue. |
| WORM table named `flag_audit_log` | Codebase convention is suffix-led `_audit` (`tenant_deploy_audit` mig 043, `audit_byok_use` mig 037, `workspace_member_actions` mig 063). | Renamed to `flag_flip_audit`. Spec FR7 + AC4 updated. |
| WORM precedent migration is 043 (`session_replication_role='replica'` bypass) | **Mig 043 actually uses row-state bypass** (`TG_OP='DELETE' AND OLD.retention_until IS NOT NULL AND OLD.retention_until < now()`). The `replica` GUC pattern is real in 037/044/051/052/053. | Adopt 043's row-state bypass (preferred — narrower attack surface, no GUC-setting privilege required). Risks row 3 citation corrected. |
| Single trigger BEFORE UPDATE OR DELETE on flag_flip_audit | Mig 043 splits into two triggers (`tenant_deploy_audit_no_update` BEFORE UPDATE; `tenant_deploy_audit_no_delete` BEFORE DELETE). Combined with TG_OP-less bypass, single-trigger pattern allows UPDATE via replica role. | Two separate triggers. |
| Migration number TBD | Next monotonic is **071** (070 is latest). | Pinned `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql`. |
| `getRuntimeFlag` is a working surface with existing consumers | Zero direct *server-side tenant-boundary* consumers today. `kb-chat-sidebar` reads via `getFeatureFlags()` snapshot hydrated by `/api/flags`. | PR-2 is the **first real tenant-boundary consumer** of `getRuntimeFlag`. Per-org capability + first consumer ship together (per DHH+Simplicity YAGNI). |
| `resolveIdentity()` needs to be created for orgId widening | Exists at `apps/web-platform/lib/feature-flags/identity.ts` using React `cache()`. | Extend the existing function; do not create. |
| Flagsmith identity-trait call shape | Verified `getIdentityFlags(identifier, traits?, transient?: boolean)` in `node_modules/flagsmith-nodejs/build/cjs/sdk/index.d.ts:89` — third arg optional. | PR-2 mandates `transient: true` on every trait call (data-min lever — opts out of Flagsmith server-side identity persistence). |
| `_roleCache` shape | Currently `Map<Role, ...>` max 2 entries. Widening to `(role, orgId)` composite is unbounded by user-controllable input → DDoS amplification risk. | Bounded LRU (N=1000, configurable via env) with 30s TTL; fall through to env fallback on cap-hit. |
| `actor` column shape | No precedent enforces format on operator-id columns. SOC2 CC8.1 evidence requires consistent identity strings. | CHECK constraint enforces lowercase email shape (`actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'`); skill normalizes via `toLowerCase()` before insert. |
| `before_state` / `after_state` as jsonb | For boolean flips (`on`/`off`), jsonb is over-engineered. | Boolean flips use `before bool`, `after bool`. Reserve jsonb only if a future non-boolean flag type emerges; not in scope for this plan. |
| CI workflow needs new Doppler service token | Brainstorm Decision #7 picked HTTP probe. No `DOPPLER_TOKEN_CLI_OPS` provisioned. | HTTP probe to `/api/flags?role=prd`; no new secret. |

## User-Brand Impact

**If this lands broken, the user experiences:**
A non-allowlisted org sees the workspace invite UI/API (cross-tenant exposure on `team-workspace-invite`), OR a paying org's BYOK delegation is silently misrouted mid-billing-cycle (cross-tenant billing breach OR locked-out paying user on `byok-delegations`), OR Flagsmith outage drops dev-cohort preview unexpectedly with no audit trail.

**If this leaks, the user's data/workflow/money is exposed via:**
Flagsmith segment misconfiguration (fat-finger that includes wrong orgId in `org-targeted` segment), `orgId` identity-trait egress to a third party not disclosed in our sub-processor list, mid-cycle flag flip without WORM audit trail, BYOK key delegation misrouted to wrong grantor.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` agent runs at PR review per threshold.

## Files to Create (across the 3 PRs)

| PR | Path |
|---|---|
| PR-1 | `knowledge-base/legal/data-processing-agreements/flagsmith.md` |
| PR-2 | `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` |
| PR-2 | `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql` |
| PR-2 | `apps/web-platform/supabase/migrations/071_flag_flip_audit.down.sql` |
| PR-2 | `apps/web-platform/server/byok-delegations-boot.ts` (Sentry boot breadcrumb parity with `team-workspace-boot.ts`) |
| PR-2 | `knowledge-base/legal/legitimate-interest-assessments/2026-XX-XX-flag-flip-audit-lia.md` (Art. 6(1)(f) LIA — GDPR-Art-6 forward action) |

## Files to Edit (across the 3 PRs)

**PR-1 (Flagsmith sub-processor disclosure):**
- `knowledge-base/legal/compliance-posture.md` — Vendor DPA Status row
- `knowledge-base/legal/data-processing-agreement-template.md` — Schedule 2 + §11.2 SCCs classification
- `knowledge-base/legal/article-30-register.md` — PA-1 + PA-2 Recipients
- `knowledge-base/legal/tenant-dpa-register.md` — Art. 28(4) flow-down note (no-op today; document)
- `docs/legal/privacy-policy.md`
- `docs/legal/data-protection-disclosure.md` (root + Eleventy mirror per dual-file pattern, learning `2026-03-18-dpd-processor-table-dual-file-sync.md`)
- `docs/legal/gdpr-policy.md`
- AUP file if it exists and lists sub-processors (grep at PR-1 plan time per learning `2026-05-14-discrete-enumeration-relockstep-and-pr-introduced-asymmetry.md`)

**PR-2 (migrate both flags + per-org capability + WORM audit inline):**

*Capability layer:*
- `apps/web-platform/lib/feature-flags/server.ts` — move both flags to `RUNTIME_FLAGS`; extend `getRuntimeFlag(name, identity)` to pass `orgId` trait via `getIdentityFlags(identifier, { role, orgId }, true)` (`transient: true`); widen `_roleCache` to bounded LRU keyed on `(role, orgId)` (N=1000, env-tunable)
- `apps/web-platform/lib/feature-flags/identity.ts` — widen `Identity = { userId, role, orgId }`; extend `resolveIdentity()` to derive `orgId` from `workspace_members`
- `plugins/soleur/skills/flag-bootstrap/SETUP.md` — add `org-targeted` segment creation step
- `plugins/soleur/skills/flag-set-role/SKILL.md` — extend with `--target role|org` arg (recommend extension over sibling-skill split)
- `apps/web-platform/lib/feature-flags/server.test.ts` — new tests for orgId trait + LRU eviction

*WORM audit:*
- `apps/web-platform/lib/feature-flags/server.ts` — `audit_flag_flip()` RPC wrapper called by skills
- `plugins/soleur/skills/flag-create/SKILL.md` — append audit row before Flagsmith feature-create
- `plugins/soleur/skills/flag-set-role/SKILL.md` — append audit row before Flagsmith flip; fail skill on audit-row error (no silent skip)
- `plugins/soleur/skills/user-set-role/SKILL.md` — append audit row before identity-trait write

*team-workspace-invite consumers:*
- `apps/web-platform/server/team-membership-resolver.ts` — await at gate site
- `apps/web-platform/server/team-workspace-boot.ts` — async Sentry breadcrumb
- `apps/web-platform/app/api/workspace/invite-member/route.ts` — await
- `apps/web-platform/app/api/workspace/remove-member/route.ts` — await
- `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` — await
- `apps/web-platform/test/team-membership-resolver.test.ts`
- `apps/web-platform/test/team-workspace-boot.test.ts`
- `apps/web-platform/e2e/team-membership.e2e.ts`

*byok-delegations consumers (with hot-path care):*
- `apps/web-platform/server/byok-resolver.ts` — async boundary at `resolveKeyOwnerThenLease()`; delete duplicate `envOnly()` helper; per-request memoization (React `cache()` for RSC + AsyncLocalStorage for Inngest — see Sharp Edge)
- `apps/web-platform/server/agent-runner.ts` — propagate await (verified sites: 895, 2461)
- `apps/web-platform/server/cc-dispatcher.ts` — propagate await (site: 890 ±drift)
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`
- `apps/web-platform/server/inngest/functions/github-on-event.ts`
- `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
- `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts`
- `apps/web-platform/test/server/inngest/github-on-event.test.ts`

*CI + invariants:*
- `.github/workflows/scheduled-membership-health.yml` — replace `vars.FLAG_TEAM_WORKSPACE_INVITE` with HTTP probe `/api/flags?role=prd`; reuse `strip_log_injection()` from `scheduled-realtime-probe.yml`; fail-closed-to-OFF on 5xx; `curl --max-time 5`
- `apps/web-platform/scripts/verify-required-secrets.sh` — preserve env-fallback mirror invariant for both flags

**PR-3 (`dev-signin` stay-ENV inline comment):**
- `apps/web-platform/lib/feature-flags/server.ts:16-24` — comment block above `ENV_FLAGS` documenting the partition rule (DCE tripwire for `dev-signin`; historic migration of `team-workspace-invite` + `byok-delegations` in PR-2). No ADR-038 appendix (cut per Simplicity).

## Open Code-Review Overlap

Two open scope-outs touch files PR-2 will edit. Disposition: **Acknowledge** (distinct concerns):

- **#3242** — `review: tool_use WS event lacks raw name field for agent consumers` (touches `agent-runner.ts`, `cc-dispatcher.ts`). Distinct concern (WS event schema, not flag-gating). PR-2 adds awaits; no field-shape changes. Scope-out remains open.
- **#3243** — `arch: decompose cc-dispatcher.ts into focused modules` (touches `cc-dispatcher.ts`). PR-2 adds 1 await at line 890; safe in either order. Scope-out remains open.

## Implementation Phases (3 PRs)

### Phase 1 — PR-1: Flagsmith sub-processor disclosure (legal lockstep)

**Blocks:** PR-2 (any code PR that adds `orgId` egress to Flagsmith).
**Scope:** doc-only PR. ~8 legal artifacts touched in one commit per learning `2026-05-22-dpa-template-pre-draft-and-cross-document-disclosure-drift.md`.

**Sub-tasks:**
1. Sign / verify the Flagsmith DPA (Bullet Train Ltd's published DPA URL). Capture URL + signature evidence in `data-processing-agreements/flagsmith.md`.
2. Confirm Flagsmith data region. Edge endpoint is `edge.api.flagsmith.com`. Cite transfer mechanism (EU-US DPF status, region-pinning availability on current tier) in the DPA Schedule.
3. Add Flagsmith to `compliance-posture.md` Vendor DPA Status table.
4. Add Flagsmith to `data-processing-agreement-template.md` Schedule 2, classified §11.2 (UK-based; non-EEA; SCCs Modules 2+3).
5. Add Flagsmith recipient line to Article 30 PA-1 (Account) and PA-2 (Conversation).
6. Sub-processor disclosure update across `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md` (root + Eleventy mirror), `docs/legal/gdpr-policy.md`, AUP if present.
7. `tenant-dpa-register.md` Art. 28(4) flow-down note (zero customer DPAs today; document state).
8. §6.1 30-day notification clock: not triggered (zero executed customer DPAs); document in `data-processing-agreements/flagsmith.md`.

**Acceptance Criteria (Pre-merge):**
- `git grep -i "flagsmith" knowledge-base/legal/ docs/legal/` returns non-zero in EVERY artifact listed above (≥7 files).
- `data-processing-agreements/flagsmith.md` exists with: DPA URL, signature evidence, data region, transfer mechanism, Flagsmith's own sub-processors, execution date.
- `compliance-posture.md` Vendor DPA Status table has "Flagsmith / Bullet Train Ltd" row with `status: signed | active`.
- Markdownlint passes.
- DPD root + Eleventy mirror agree (`diff` returns zero) per learning `2026-03-18-dpd-processor-table-dual-file-sync.md`.

**Acceptance Criteria (Post-merge):**
- Annual DPA-review cron picks up Flagsmith row.

**Risks:** Cross-document drift (mitigation: single-PR lockstep; dual-file diff gate). §11.1/§11.2 misclassification (mitigation: verify hosting region first).

**Estimated complexity:** Medium.

---

### Phase 2 — PR-2: Both flags migrated + per-org capability + WORM audit (combined)

**Blocked by:** PR-1.
**Scope:** Large PR combining the capability layer, the WORM audit shim, and both flag migrations. Justified by Code Simplicity + DHH consensus: per-org capability is YAGNI without consumers, and the consumers (both flags) ship together. WORM ledger ships with its first writer rather than as standalone scaffolding.

**Pre-merge guard:** Immediately before merging PR-2, grep `knowledge-base/legal/tenant-dpa-register.md` for `status: dpa-signed` rows. If non-empty, the §6.1 30-day notice clock applies to PR-2's data-flow expansion — pause PR-2 merge and escalate to CLO. (Per LC-04 GDPR gate finding.)

**Sub-tasks:**

*A. ADR-043:*
1. Draft `ADR-043-flagsmith-per-org-targeting.md`. Decision: identity-trait `orgId` + single `org-targeted` segment with rule `orgId IN [...]` (preferred over N per-org segments). Rationale: segment-count explosion avoided; per-org rollout becomes a Flagsmith Management API rule-update via skill (no segment-create per org).

*B. Identity widening:*
2. Widen `Identity` type in `lib/feature-flags/identity.ts`: `{ userId: string | null, role: Role, orgId: string | null }`.
3. Extend `resolveIdentity()` to derive `orgId` from `workspace_members` (single SELECT, cached via existing React `cache()`).
4. Extend `getRuntimeFlag(name, identity)` to call `getIdentityFlags(identifier, { role, orgId }, true)` — `transient: true` opts out of Flagsmith server-side identity persistence.

*C. Cache:*
5. Replace `Map<Role, ...>` cache with bounded LRU keyed on `(role, orgId)` composite. Size cap N=1000 (env-tunable via `FLAGSMITH_CACHE_MAX_ENTRIES`). 30s TTL preserved. On cap-hit eviction, evicted entries simply re-fetch on next request (no error).

*D. Flagsmith segment bootstrap:*
6. Flagsmith Management API: create `org-targeted` segment in both envs (dev=90722, prd=90721) with rule `orgId IN ($ORG_IDS_placeholder)`. Initial `$ORG_IDS_placeholder` is empty list — segment exists but matches no one until per-flag attachment.
7. Update `plugins/soleur/skills/flag-bootstrap/SETUP.md` with the segment-creation step.
8. Extend `soleur:flag-set-role` with `--target role|org` argument (extension chosen over sibling-skill split to minimize operator-memory churn).

*E. WORM `flag_flip_audit` migration (071):*

Schema (simplified per Code Simplicity tactical YAGNI):

```sql
-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest — operational evidence of
-- skill-driven flag-flip operations for Art. 32(1)(d) effectiveness-of-TOMs
-- and SOC2 CC8.1 change management. LIA:
-- knowledge-base/legal/legitimate-interest-assessments/2026-XX-XX-flag-flip-audit-lia.md

CREATE TABLE public.flag_flip_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_name text NOT NULL,
  env text NOT NULL CHECK (env IN ('dev','prd')),
  target text NOT NULL,                  -- 'role:prd' | 'role:dev' | 'org:<orgId>' | 'feature:<name>'
  action text NOT NULL CHECK (action IN ('on','off','create','archive')),
  before_bool bool,                      -- null for non-boolean actions (create/archive)
  after_bool bool,                       -- null for non-boolean actions
  actor text NOT NULL CHECK (actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  retention_until timestamptz NOT NULL DEFAULT (now() + interval '7 years')
);
ALTER TABLE public.flag_flip_audit ENABLE ROW LEVEL SECURITY;
-- ZERO RLS POLICIES (no owner-insert per learning 2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md)
```

WORM via TWO separate triggers (mirrors mig 043 exactly per Kieran P0-1 + P0-2):

```sql
CREATE FUNCTION public.flag_flip_audit_no_update() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'flag_flip_audit is WORM (insert-only); UPDATE forbidden';
END $$;
REVOKE ALL ON FUNCTION public.flag_flip_audit_no_update() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.flag_flip_audit_no_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  -- Row-state bypass for Art. 5(1)(e) retention sweep (mirrors mig 043 precedent).
  -- pg_cron retention only deletes rows past retention_until; no GUC required.
  IF TG_OP = 'DELETE' AND OLD.retention_until IS NOT NULL AND OLD.retention_until < now() THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'flag_flip_audit is WORM; DELETE only permitted for retention sweep on expired rows';
END $$;
REVOKE ALL ON FUNCTION public.flag_flip_audit_no_delete() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_flag_flip_audit_no_update
  BEFORE UPDATE ON public.flag_flip_audit
  FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_update();

CREATE TRIGGER trg_flag_flip_audit_no_delete
  BEFORE DELETE ON public.flag_flip_audit
  FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_delete();
```

Writer RPC:

```sql
CREATE FUNCTION public.audit_flag_flip(
  p_flag_name text, p_env text, p_target text, p_action text,
  p_before_bool bool, p_after_bool bool, p_actor text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.flag_flip_audit (flag_name, env, target, action, before_bool, after_bool, actor)
  VALUES (p_flag_name, p_env, p_target, p_action, p_before_bool, p_after_bool, lower(p_actor))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) TO service_role;
```

Down migration `071_flag_flip_audit.down.sql` drops triggers, functions, table in correct dependency order.

9. Skill-side append in `flag-create`, `flag-set-role`, `user-set-role`: call `audit_flag_flip(...)` via Supabase service-role client BEFORE the Flagsmith API call. If audit fails, skill exits code 4 (no silent skip).
10. **pg_cron retention heartbeat** (per Code Simplicity hidden assumption): the retention sweep cron writes a row to a separate `public.flag_flip_audit_sweep_heartbeat` table on every run. A separate scheduled workflow alerts if no heartbeat row appears within 32 days (sweep cadence is 30 days). Defers retention-sweep heartbeat table to a Phase-2 sub-task if scope creeps; otherwise inline.

*F. team-workspace-invite migration:*
11. Move `team-workspace-invite` from `ENV_FLAGS` to `RUNTIME_FLAGS`.
12. Convert `isTeamWorkspaceInviteEnabled(orgId)` from sync to async; new signature `(orgId, identity)`. Body: `return (await getRuntimeFlag('team-workspace-invite', identity)) && getTeamWorkspaceAllowlist().has(orgId)`. Dual-control: both must hold.
13. Propagate await to 5 sites: `team-membership-resolver.ts:70`, `settings/layout.tsx:22`, `invite-member/route.ts:40`, `remove-member/route.ts:30`, `team-workspace-boot.ts:13`.
14. Flagsmith feature create + attach to `org-targeted` segment + audit row.

*G. byok-delegations migration (hot-path care):*
15. Move `byok-delegations` to RUNTIME_FLAGS; delete duplicate `envOnly()` helper.
16. Introduce async boundary at `resolveKeyOwnerThenLease()`. Per-request memoization decision (Sharp Edge below): RSC paths use React `cache()`; Inngest contexts use `AsyncLocalStorage` (Node 16+ stable) to thread a per-step memo Map. Document the decision in PR-2's own plan cycle if AsyncLocalStorage adoption requires a separate ADR; otherwise inline.
17. Propagate await to `agent-runner.ts:895, 2461`, `cc-dispatcher.ts:890`, `inngest/cfo-on-payment-failed.ts`, `inngest/github-on-event.ts`.
18. Create `apps/web-platform/server/byok-delegations-boot.ts` — Sentry boot breadcrumb parity with `team-workspace-boot.ts` (closes pre-existing gap CTO research surfaced).
19. Flagsmith feature create + segment attach + audit row.

*H. CI + invariants:*
20. Rewrite `.github/workflows/scheduled-membership-health.yml` to HTTP-probe `/api/flags?role=prd`; reuse `strip_log_injection()` shell fn from `scheduled-realtime-probe.yml`; fail-closed-to-OFF on 5xx; `curl --max-time 5`.
21. `verify-required-secrets.sh` preserves env-fallback mirror invariant for both flags.

**Acceptance Criteria (Pre-merge):**

*Capability layer:*
- ADR-043 exists with decision + rationale + alternatives.
- `Identity` widened; `tsc --noEmit` green; `resolveIdentity()` returns 3 fields.
- `getRuntimeFlag` calls `getIdentityFlags(..., { role, orgId }, true)`.
- `_roleCache` is LRU-bounded; cap-hit test triggers eviction without error.
- `org-targeted` segment exists in both Flagsmith envs.

*WORM:*
- Migration 071 + down apply cleanly to dev Supabase.
- `flag_flip_audit` has RLS enabled with ZERO policies (`select polname from pg_policies where tablename='flag_flip_audit'` returns 0).
- Two separate triggers visible (`\dft+ public.flag_flip_audit*`).
- UPDATE negative test: `BEGIN; INSERT INTO flag_flip_audit (...); UPDATE flag_flip_audit SET action='off' WHERE id=...; ROLLBACK;` raises exception on UPDATE.
- DELETE negative test on unexpired row: `BEGIN; INSERT INTO flag_flip_audit (..., retention_until=now()+'1 day'); DELETE FROM flag_flip_audit WHERE id=...; ROLLBACK;` raises exception.
- DELETE positive test on expired row: `BEGIN; INSERT INTO flag_flip_audit (..., retention_until=now()-'1 day'); DELETE FROM flag_flip_audit WHERE id=...; ROLLBACK;` succeeds (row-state bypass branch).
- `actor` CHECK constraint rejects malformed strings.
- Skills (`flag-create`, `flag-set-role`, `user-set-role`) append audit row BEFORE Flagsmith mutation; rollback on audit failure.
- LIA doc filed at `legitimate-interest-assessments/2026-XX-XX-flag-flip-audit-lia.md`.

*Dual-control invariants:*
- `isTeamWorkspaceInviteEnabled` and `isByokDelegationsEnabled` both return `Promise<boolean>`.
- E2E test: dual-control truth table — `(Flagsmith=T, allowlist=T)→T`; all other combos `→F`.
- E2E test: Flagsmith outage → env-fallback path engages, dual-control still holds.
- E2E test: Flagsmith misconfig (segment includes all orgs) → env-allowlist still gates.

*Hot path (byok):*
- Latency regression test: simulate 10 BYOK-bearing operations in one HTTP request; assert Flagsmith call count ≤ 1.
- Inngest function memo test: assert ≤1 Flagsmith call per step execution.

*CI:*
- `scheduled-membership-health.yml` probes `/api/flags?role=prd`; smoke-run via `gh workflow run` returns expected JSON shape.
- `verify-required-secrets.sh` green; env-fallback mirror invariant preserved for both flags.

*Env-var sweep:*
- `git grep -nE 'process\.env\.FLAG_TEAM_WORKSPACE_INVITE' apps/` shows only fallback site + test stubs.
- `git grep -nE 'process\.env\.FLAG_BYOK_DELEGATIONS' apps/` shows only fallback site + test stubs.

*Pre-merge tenant-DPA guard:*
- `awk '/^\| /' knowledge-base/legal/tenant-dpa-register.md | grep -c 'status: dpa-signed' == 0` (no customer DPAs signed in the PR-1 → PR-2 lag window; if non-zero, halt merge and escalate to CLO).

**Acceptance Criteria (Post-merge):**
- `/api/flags?role=prd` returns `"team-workspace-invite": false` and `"byok-delegations": false` (prd OFF default).
- `select count(*) from public.flag_flip_audit where flag_name in ('team-workspace-invite','byok-delegations');` returns ≥2 (feature-create rows for each flag).
- Sentry boot breadcrumb fires for `byok-delegations` when feature flips ON for any allowlisted org.
- **#4444 storage-object lifecycle blocker remains open**; flip-ON in prd gated on #4444 closure per umbrella tracking. PR-2 migrates the *mechanism*; does NOT flip ON.
- Run `gh variable delete FLAG_TEAM_WORKSPACE_INVITE` post-merge (legacy GH Actions Variable now orphaned).

**Risks:**

| Risk | Mitigation | Citation |
|---|---|---|
| WORM trigger TG_OP missing → UPDATE silently allowed via replica GUC | Two separate triggers (no_update, no_delete); row-state bypass on DELETE only (matches mig 043) | Kieran P0-1, P0-2; mig 043 `tenant_deploy_audit.sql:165-168` |
| Owner-insert RLS becomes RPC bypass | ZERO RLS policies; service-role-only via SECURITY DEFINER writer | learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` |
| BEFORE-DELETE blocks pg_cron retention | Row-state bypass (no GUC required) — narrower attack surface than `session_replication_role` | learning `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` (note: learning recommends row-state, plan follows) |
| WORM blocks Art. 17 erasure cascade | No FK from `flag_flip_audit` to `users`; `actor` is operator-keyed text with CHECK | learning `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md` |
| RESTRICTIVE + column GRANT silently fails tenant writes | No RESTRICTIVE policies; no column-level GRANTs | learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` |
| Async hot-path proxy collapses error mapping | Widen the contract — `resolveKeyOwnerThenLease()` becomes async; no sync proxy | learning `2026-04-27-widen-async-contract-instead-of-deferred-construction-proxy.md` |
| Inngest contexts lack React `cache()` — naive await N+1s Flagsmith | AsyncLocalStorage per Inngest step; regression test ≤1 call/request | new (Kieran P1-4 surfaced; design committed) |
| `_roleCache` unbounded growth under DDoS | LRU-bounded N=1000 (env-tunable); cap-hit re-fetches | Code Simplicity hidden assumption |
| `actor` drift undermines SOC2 evidence | CHECK constraint + `lower()` normalization in writer RPC | Code Simplicity hidden assumption |
| pg_cron retention silently fails for years | Heartbeat table + scheduled-workflow alert (32-day staleness threshold) | Code Simplicity hidden assumption |
| Env-var sweep miss | Plan-time grep in pre-merge AC | learnings `2026-03-20-verify-env-var-consumption-at-code-level.md`, `2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md` |
| Doppler env baked at `docker run` | Flagsmith SDK resolves at request time; E2E verifies | learning `2026-05-19-doppler-env-hot-reload-limitation.md` |
| Flag flip creates new error class downstream | Sentry breadcrumb + WORM audit row + boot breadcrumb parity for byok-delegations | learning `2026-05-04-flag-boundary-creates-new-error-class-mapper-must-handle.md` |
| Customer DPA signing during PR-1 → PR-2 lag triggers §6.1 30-day clock | Pre-merge tenant-dpa-register grep guard (AC above) | GDPR-gate LC-04; learning `2026-05-22-dpa-template-pre-draft-and-cross-document-disclosure-drift.md` |
| Cross-tenant billing breach if `byok-delegations` resolves true for wrong org | Dual-control via env-allowlist; E2E covers misconfig | brainstorm User-Brand Impact |
| Per-org segment misconfig (wrong orgIds in `org-targeted`) | audit_flag_flip rows + weekly review of segment rule contents via Flagsmith API | new |

**Estimated complexity:** Very large (genuine — this is the load-bearing PR of the umbrella).

---

### Phase 3 — PR-3: `dev-signin` stay-ENV inline comment

**Independent — parallel with all other PRs.**
**Scope:** Single comment block in `lib/feature-flags/server.ts`. No ADR-038 appendix (cut per Code Simplicity — comment alone suffices; ADR appendix would duplicate the prose).

**Sub-task:**

Add comment above `ENV_FLAGS` in `apps/web-platform/lib/feature-flags/server.ts:16-24`:

```ts
// dev-signin stays ENV by design. It pairs with the DCE tripwire
// `apps/web-platform/scripts/assert-dev-signin-eliminated.sh` which fails the
// prd build if "dev-signin", isDevSignInEnabled, or dev-sign-in-panel tokens
// leak into client bundles. Sync getFlag() + `process.env.NODE_ENV !== "development"`
// literals are what SWC/Terser need to eliminate the panel.
//
// team-workspace-invite and byok-delegations were historically ENV (per-org
// allowlist gate) and migrated to RUNTIME_FLAGS in PR #<TBD> (umbrella #4456)
// under dual-control (Flagsmith boolean + env-allowlist as defense-in-depth).
//
// New flags: if the call-site needs DCE elimination → ENV. Otherwise → RUNTIME.
// See ADR-038 + ADR-043.
```

(PR number filled in at PR-3 plan-cycle time after PR-2 merges.)

**Acceptance Criteria (Pre-merge):**
- Comment exists at `server.ts:16-24` with the partition rule.
- `assert-dev-signin-eliminated.sh` still passes (no code change in this PR; verify).
- Markdownlint passes.

**Risks:** None substantive — single comment edit.

**Estimated complexity:** Trivial.

---

## Acceptance Criteria (Plan-level, spanning all PRs)

### Pre-merge (umbrella — invariants only, per Kieran P1-3 ceremony cut)

- 3-PR sequence ordering honored: PR-1 → PR-2 → PR-3 (PR-3 parallel-OK).
- Dual-control invariant: both migrated flags gate via `(Flagsmith && env-allowlist)`.
- `assert-dev-signin-eliminated.sh` still passes after PR-2 + PR-3 (DCE tripwire intact).
- `verify-required-secrets.sh` env-fallback mirror invariant preserved.

### Post-merge (operator)

- Umbrella issue #4456 closes when PR-3 merges AND audit-row spot-check returns ≥2 rows.
- Annual Flagsmith DPA review enters compliance cadence.
- **#4444 storage-object lifecycle blocker remains open**; flip-ON in prd gated separately.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

Carry-forward from brainstorm 2026-05-25 §"Domain Assessments". Per AGENTS.md lifecycle-staging (plan-phase: CPO sign-off only; CLO + CTO concerns carry forward in plan body):

### Engineering (CTO)

**Status:** carry-forward
**Assessment:** Original recommendation "stay ENV for all 3." Override builds the missing capability + audit + disclosure so migration is meaningful. CTO recommendations preserved as binding plan constraints (dual-control, async boundary at `resolveKeyOwnerThenLease`, CI HTTP probe, `dev-signin` exclusion).

### Product (CPO)

**Status:** carry-forward (sign-off required per `requires_cpo_signoff: true`)
**Assessment:** Original recommendation defer. Override accepted on basis that per-org capability ships with first consumer (not standalone). Per-role weakness of ADR-038 V1 closed by ADR-043. **Pending: explicit CPO sign-off on this plan body before `/work` begins.**

### Legal (CLO)

**Status:** carry-forward
**Assessment:** Override acceptable conditional on PR-1 landing BEFORE any code PR adding `orgId` egress. PR sequencing honors that. `transient: true` is data-min mitigation, not disclosure substitute. WORM audit shim addresses Art. 32(1)(d) effectiveness-of-TOMs evidence.

## GDPR / Compliance Gate Findings (Phase 2.7)

Gate output: **0 Critical, 3 Important, 4 PASS**. Forward actions baked into the 3 PRs:

| `check_id` | Severity | Forward action | PR |
|---|---|---|---|
| `GDPR-Art-6` | Important | Add `-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest — operational evidence of skill-driven flag flips for Art. 32(1)(d) TOM-effectiveness + SOC2 CC8.1` annotation to `071_flag_flip_audit.sql`; file LIA doc | PR-2 |
| `GDPR-Chapter-V` | Important | PR-1 (Flagsmith DPA + §11.2 SCCs) MUST land before PR-2 (orgId egress). Enforced in Pre-merge ACs | PR-1 → PR-2 |
| `LC-04` (Art. 28(2) notice) | Important | Pre-merge guard on PR-2: grep `tenant-dpa-register.md` for `status: dpa-signed` rows; if non-empty, §6.1 30-day clock applies | PR-2 |
| `GDPR-Art-5e` | PASS | `retention_until + 7 years`; pg_cron sweep + heartbeat verified | — |
| `GDPR-Art-17` | PASS | No FK to users/workspaces; actor is operator-keyed text | — |
| `GDPR-Art-9` | PASS | No special-category columns. Drift-check at PR-2 migration-write time | — |
| `TS-01..05` | PASS | Real-Postgres tests mandated; synthesized actor strings (e.g., `test-operator@example.test`) | — |

Disclaimer: This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.

## Observability

Per Phase 2.9 — required because plan edits code-class files under `apps/web-platform/server/`, `apps/web-platform/lib/`, and `apps/web-platform/supabase/migrations/`.

```yaml
liveness_signal:
  what: "every flag-flip operation appends a row to public.flag_flip_audit"
  cadence: "synchronous — at skill invocation time"
  alert_target: "operator (skill exit code 4 on audit append failure); Sentry breadcrumb on flag-state change in prd"
  configured_in: "apps/web-platform/supabase/migrations/071_flag_flip_audit.sql + plugins/soleur/skills/flag-*/SKILL.md"

error_reporting:
  destination: "Sentry via reportSilentFallback() (apps/web-platform/server/observability.ts)"
  fail_loud: true   # skills abort exit code 4 on audit-row append failure

failure_modes:
  - mode: "Flagsmith SDK timeout / network error"
    detection: "reportSilentFallback fired with op='flagsmith.getIdentityFlags' (already wired)"
    alert_route: "Sentry project routing per AGENTS.md hr-no-dashboard-eyeball-pull-data-yourself"
  - mode: "Flagsmith segment misconfiguration"
    detection: "audit_flag_flip rows + weekly review of segment rule contents via Flagsmith API"
    alert_route: "operator skill rejects suspicious update via dry-run preview; weekly cron summary issue"
  - mode: "env-allowlist drift from Flagsmith prd-segment state"
    detection: "verify-required-secrets.sh assertion in CI"
    alert_route: "CI build failure → blocks merge"
  - mode: "CI probe /api/flags 5xx (fail-closed-to-OFF)"
    detection: "scheduled-membership-health.yml workflow output captures failure path"
    alert_route: "GH Actions workflow failure notification"
  - mode: "audit-row write failure mid-flag-flip"
    detection: "skill exits code 4; operator sees in terminal; reportSilentFallback also fires"
    alert_route: "operator-facing terminal + Sentry"
  - mode: "Inngest function context N+1 Flagsmith calls (hot-path regression)"
    detection: "latency regression test asserts ≤1 Flagsmith call per BYOK request"
    alert_route: "CI test failure → blocks merge"
  - mode: "pg_cron retention sweep silently fails"
    detection: "flag_flip_audit_sweep_heartbeat table missing rows >32 days; scheduled workflow alerts"
    alert_route: "scheduled-workflow alert → operator issue"

logs:
  where: "Sentry (errors/breadcrumbs, 90d) + Supabase public.flag_flip_audit (7y via Art. 5(1)(e)) + GH Actions workflow logs (90d)"
  retention: "Sentry 90d, audit 7y, workflow logs 90d"

discoverability_test:
  command: "doppler run -p soleur -c prd_supabase_ro -- psql \"$DATABASE_URL\" -c \"SELECT count(*) FROM public.flag_flip_audit WHERE created_at > now() - interval '7 days';\""
  expected_output: "non-negative integer; non-zero after any flag-flip in the last 7 days"
```

(NO `ssh` in `discoverability_test.command` — uses Doppler-resident prd Supabase read-only credentials per AGENTS.md `hr-no-ssh-fallback-in-runbooks`.)

## Infrastructure (IaC)

Skip silently. No new infrastructure: new Supabase migration goes through existing `apps/web-platform/supabase/migrations/` substrate; Flagsmith segment + feature creation is operator-skill-driven per ADR-038; no new servers / cron / DNS / TLS / firewall / vendor.

## Test Strategy

- **Unit:** `lib/feature-flags/server.test.ts` (resolution paths, orgId trait, LRU eviction); `lib/feature-flags/identity.test.ts` (orgId extraction).
- **Integration:** real-Postgres for `flag_flip_audit` (RLS + WORM bypasses); mocked Flagsmith SDK with documented response shapes.
- **E2E:** Flagsmith outage, misconfig (wrong orgIds in segment), dual-control truth table.
- **CI:** `verify-required-secrets.sh` env-fallback invariant; lockfile-sync gate green.
- **Hot-path:** `byok-resolver.ts` latency regression test (≤1 Flagsmith call per request).

Test framework: **vitest** (per `apps/web-platform/package.json scripts.test`). NOT bun test — `bunfig.toml` `pathIgnorePatterns = ["**"]` blocks bun discovery.

## Rollback Plan

- **PR-3 revert:** comment removal; no behavior change.
- **PR-2 revert:** big rollback. Apply `071_flag_flip_audit.down.sql`; revert TypeScript edits; restore `envOnly()` helper in `byok-resolver.ts`; CI workflow restored to `vars.FLAG_*` read; `gh variable set FLAG_TEAM_WORKSPACE_INVITE` restored; `org-targeted` Flagsmith segment manually deleted via UI; existing audit rows retained or purged per operator decision.
- **PR-1 revert:** legal docs reverted. **CAUTION:** if customer DPAs signed between PR-1 merge and revert, §6.1 30-day notice clock fires (currently zero customer DPAs — revert is currently no-op).

Cross-PR rollback risk: PR-1 rollback expensive after customer-DPA signings. Mitigate by completing PR-1 well before any customer DPA execution; check `tenant-dpa-register.md` immediately before revert.

## Sharp Edges (plan-specific)

- A future PR plan (PR-1, PR-2, PR-3) whose `## User-Brand Impact` is empty will fail deepen-plan Phase 4.6. Carry forward this plan's framing.
- Each future PR plan MUST grep for all `process.env.FLAG_<NAME>` references on the affected flag — silent stragglers break dual-control.
- Use `transient: true` on every Flagsmith `getIdentityFlags(identifier, traits, transient)` call. Verified against SDK signature at `node_modules/flagsmith-nodejs/build/cjs/sdk/index.d.ts:89`.
- ADR-043, NOT ADR-039 (correction). PR-2's plan cycle drafts as `ADR-043-flagsmith-per-org-targeting.md`.
- Per-org Flagsmith segment uses identity-trait `orgId` + single segment rule `orgId IN [...]`. NOT N per-org segments.
- WORM table name `flag_flip_audit` (suffix-led per codebase convention).
- WORM trigger MUST split into two functions (`flag_flip_audit_no_update` + `flag_flip_audit_no_delete`) per mig 043 precedent. Single trigger BEFORE UPDATE OR DELETE with TG_OP-less bypass silently allows UPDATE via replica role (Kieran P0-2).
- Retention bypass MUST be row-state (`OLD.retention_until < now()`), NOT `session_replication_role='replica'`. Row-state matches mig 043; GUC bypass requires `replica` privilege which is broader (Kieran P0-1).
- Writer RPC and trigger functions both pin `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- `actor` field has CHECK constraint `actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'`. Writer RPC normalizes via `lower()`. SOC2 CC8.1 evidence requires canonical form.
- `_roleCache` is bounded LRU (N=1000, env-tunable). Cap-hit re-fetches (no error). Prevents DDoS-amplified unbounded growth.
- **Inngest hot-path memoization decision:** AsyncLocalStorage (Node 16+ stable) for cross-step memo within one cron execution. If PR-2 plan-cycle reveals AsyncLocalStorage adoption requires an ADR, defer to follow-up issue. The naive alternative (4th arg threading) requires modifying 5+ Inngest function signatures, which is broader scope.
- pg_cron retention heartbeat: separate `flag_flip_audit_sweep_heartbeat` table; scheduled workflow alerts if no row within 32 days.
- PR-2 pre-merge guard: `tenant-dpa-register.md` row count must show zero `status: dpa-signed` at PR-2 merge time. Non-zero → §6.1 30-day notice clock applies → escalate to CLO.
- This plan IS the cap-coupling enforcer for the 3-PR sequence. Each future PR plan-cycle MUST re-cite the umbrella ACs. Staleness anchor: 2026-05-25. If any PR plans more than 30 days after this date, re-run premise probes (`gh issue view 4444`, `gh issue view 4232`, `ls apps/web-platform/supabase/migrations/`).
