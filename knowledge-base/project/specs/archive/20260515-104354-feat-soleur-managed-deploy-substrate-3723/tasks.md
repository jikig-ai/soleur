---
feature: soleur-managed-deploy-substrate-3723
issue: 3723
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: tasks-ready
---

# Tasks: Soleur-managed multi-tenant deploy substrate — v1 scaffolding

Derived from the finalized (revision-2) plan. Three phases, no scaffold template / orchestration TS module / cross-tenant test / registry table in v1 (cut by 5-reviewer pass; extract at N=2).

## Phase 1: Legal pre-flight

### 1.1 ToS-research (consolidated, 4 sections)
- 1.1.1 Create `knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md` with four `## Provider` sections (Hetzner, Cloudflare, Doppler, GitHub), each citing ToS URL + clause + attribution requirements + ending with `Verdict: ALLOWED | ALLOWED_WITH_CONDITIONS | NOT_ALLOWED`.
- 1.1.2 Verify: `grep -c 'Verdict:' knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md` returns ≥4.

### 1.2 LIA (Art. 6(1)(f) three-part test)
- 1.2.1 Create `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md` with `## Purpose` + `## Necessity` + `## Balancing` sections.
- 1.2.2 Verify: `grep -cE '^## (Purpose|Necessity|Balancing)' <file>` returns 3.

### 1.3 ADR-030
- 1.3.1 Run `/soleur:architecture create "Multi-tenant deploy substrate: per-tenant GH Actions OIDC + tenant-owned cloud accounts"`.
- 1.3.2 Fill the 6 required `## H2` sub-sections: hard-constraint ceiling, validation gate, open escape hatches (B + C with re-evaluation triggers), prior-decision #749 preservation, OIDC subject-claim binding (`repository_owner:<tenant-org>` + `environment:production`), data-layer reconciliation (founder_id ↔ tenant 1:1).
- 1.3.3 Verify: all 6 H2 subsections present via grep.

### 1.4 RoPA update
- 1.4.1 Edit `knowledge-base/legal/article-30-register.md` to add the multi-tenant deploy substrate row, enumerating all 7 Art. 30(1) limbs (b)-(g) explicitly + Art. 32 TOMs.
- 1.4.2 Verify: row matches existing Activities 1-9 column shape.

### 1.5 compliance-posture update
- 1.5.1 Edit `knowledge-base/legal/compliance-posture.md`. Add note on multi-tenant trajectory + explicit scope-out for privacy-policy / DPD sub-processor disclosure at v1.

### 1.6 GDPR gate
- 1.6.1 Run `skill: soleur:gdpr-gate` against the plan + the multi-tenant data surfaces.
- 1.6.2 Commit report to `knowledge-base/legal/gdpr-gate-report-2026-05-14.md`.
- 1.6.3 If any Critical findings, write operator-ack to `compliance-posture.md` Active Items per the gate's own contract.

## Phase 2: Audit-log Supabase migration

### 2.1 Pre-check migration number availability
- 2.1.1 Run `gh pr list --state open --json files --jq '.[] | select(.files[].path | test("supabase/migrations/04[3-9]")) | .number'` to confirm 043 is not in flight on another branch. If 043 is taken, increment until free.

### 2.2 Author migration `043_tenant_deploy_audit.sql`
- 2.2.1 Clone `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:127-216` template verbatim including `SET search_path = public, pg_temp` (in that order).
- 2.2.2 Adapt table schema per plan Phase 1 column list:
  - `founder_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT`
  - `event_type text CHECK (event_type IN ('workflow_dispatch_triggered','workflow_run_completed','workflow_run_failed'))` (3 values only; no `provisioning_step_*`)
  - `target_repo text NOT NULL CHECK (target_repo ~ '^[A-Za-z0-9_./-]{1,255}$')`
  - `target_workflow text NOT NULL CHECK (target_workflow ~ '^[A-Za-z0-9_./-]{1,255}\.ya?ml$')`
  - `gh_run_id bigint`, `oidc_jti text CHECK (...)` (NOT uuid)
  - `trigger_outcome text NOT NULL CHECK (trigger_outcome IN ('queued','succeeded','failed','timeout'))`
  - `event_at timestamptz NOT NULL DEFAULT now()`
  - `retention_until timestamptz NOT NULL DEFAULT (now() + interval '12 months')`
- 2.2.3 Add `-- RETENTION: 12 months via tenant-deploy-audit-retention pg_cron (Art. 5(1)(e))` inline comment.
- 2.2.4 Enable RLS with **zero policies**.
- 2.2.5 Add WORM BEFORE UPDATE/DELETE triggers using GUC `app.tenant_deploy_anonymise_in_progress` + `current_user = 'service_role'` gate.
- 2.2.6 Add SECURITY DEFINER writer RPC `public.write_tenant_deploy_audit(...)` with `SET search_path = public, pg_temp` (in that order).
- 2.2.7 REVOKE at table level from PUBLIC, anon, authenticated. GRANT EXECUTE on writer RPC to service_role only.
- 2.2.8 Add index `(founder_id, event_at DESC)`.
- 2.2.9 Add Art. 17 cascade function `anonymise_tenant_deploy_audit(p_founder_id uuid)` — UPDATE founder_id = NULL inside GUC window (preserves row count).
- 2.2.10 Schedule retention sweep via `cron.schedule('tenant-deploy-audit-retention', '0 4 * * *', $$ DELETE FROM public.tenant_deploy_audit WHERE retention_until < now() $$);`.

### 2.3 Apply + verify in dev
- 2.3.1 `doppler run -p soleur -c dev -- npx supabase migration up` succeeds.
- 2.3.2 `\d+ public.tenant_deploy_audit` shows all columns + RLS enabled + zero policies + `ON DELETE RESTRICT` + `oidc_jti text`.
- 2.3.3 WORM trigger smoke-test: direct UPDATE returns `P0001`.
- 2.3.4 Writer RPC under service_role succeeds for valid input; rejects malformed `target_repo` / `target_workflow`.
- 2.3.5 Anon SELECT returns zero rows (RLS-blocked).
- 2.3.6 Anonymise semantics: `count(*)` before == after `anonymise_tenant_deploy_audit('<uuid>')`; founder_id NULL on anonymised rows.
- 2.3.7 `SELECT prosrc FROM pg_proc WHERE proname = 'write_tenant_deploy_audit';` shows `SET search_path = public, pg_temp` (in that order; Kieran P0-1).
- 2.3.8 `SELECT jobname FROM cron.job WHERE jobname = 'tenant-deploy-audit-retention';` returns exactly 1 row.

## Phase 3: Runbooks

### 3.1 tenant-provisioning.md (10 steps)
- 3.1.1 Create `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`.
- 3.1.2 Write Step 0: tenant DPA signed + counter-signed; sub-processor list (Hetzner+CF+Doppler+GitHub) attached; `knowledge-base/legal/tenant-dpa-register.md` initialized.
- 3.1.3 Write Steps 1-9 per plan Phase 2; each with inline `**Verify:**` command.
- 3.1.4 Document abort-mid-provisioning teardown commands per step (Steps 1-4 each have teardown).
- 3.1.5 Step 5: `git clone` `apps/web-platform/infra/` into tenant repo + `sed` placeholder substitution. R2 backend `key = "tenants/<founder-id>/terraform.tfstate"`.
- 3.1.6 Step 6: per-provider OIDC auth probes (`hcloud server list`, `wrangler whoami`, `doppler me`) in test workflow BEFORE deploy step.
- 3.1.7 Step 7: GitHub Environment `production` with required reviewers + branch policy pinned to `main`. Use exact slug `app/soleur` (NOT `[bot]`).
- 3.1.8 Step 8: installation_id as Doppler secret `TENANT_<id>_INSTALLATION_ID` in `prd_orchestration` config (NOT a Supabase registry table at v1).
- 3.1.9 Step 9: smoke-test via `gh workflow run deploy.yml`; manual `psql` call to writer RPC for v1.
- 3.1.10 Verify: `grep -c '^### Step ' <file>` returns 10 AND `grep -c '^\*\*Verify:\*\*' <file>` returns ≥10.

### 3.2 tenant-offboarding.md
- 3.2.1 Create `knowledge-base/engineering/ops/runbooks/tenant-offboarding.md`.
- 3.2.2 Document ruleset bypass-actor sweep (enumerate `bypass_actors[].actor_id`, verify each via `gh api /apps/<id>`, remove ghost entries).
- 3.2.3 Document call to `anonymise_tenant_deploy_audit(<founder-id>)` BEFORE `auth.users` deletion.
- 3.2.4 Document per-provider account-ownership-transfer steps.

### 3.3 tenant-dpa-register.md (empty initial file)
- 3.3.1 Create `knowledge-base/legal/tenant-dpa-register.md` with header schema (founder_id, tenant_name, dpa_signed_at, sub_processors, art_28_2_ack). Initially empty; first row written at first onboarding via Step 0.

## Phase 4: Capability-gap learning + follow-up issue filing

### 4.1 OIDC capability-gap learning
- 4.1.1 Create `knowledge-base/project/learnings/2026-05-14-gh-oidc-subject-claim-no-precedent.md` documenting the chosen subject-claim shape (`repository_owner:<tenant-org>` + `environment:production`) and citing this work as the precedent for future tenants.

### 4.2 File 5 follow-up tracking issues (per `wg-when-deferring-a-capability-create-a`)
- 4.2.1 Hetzner sub-project provisioning automation (skill). Re-evaluation trigger: 2nd non-Soleur project.
- 4.2.2 Cloudflare account/sub-account provisioning automation (skill). Same.
- 4.2.3 Doppler project + OIDC identity provisioning automation (skill). Same.
- 4.2.4 GitHub repo + App install + Environment configuration automation (skill). Same.
- 4.2.5 Deploy-failure UI surface (Art. 13 in-product transparency). Re-evaluation trigger: tenant complaint about not seeing GH Actions failures in-product.
- 4.2.6 All filed with `--label deferred-scope-out --milestone "Post-MVP / Later"`. Adjust milestone per `knowledge-base/product/roadmap.md` phase rules.
- 4.2.7 Each issue body links: this plan, brainstorm, spec, ADR-030.
- 4.2.8 Backfill issue numbers into plan's `## Follow-up tracking` section.

### 4.3 Approach B/C decisions
- 4.3.1 ADR-030 `## Open escape hatches` section captures both with re-evaluation triggers (NOT filed as backlog per code-simplicity feedback).

## Phase 5: PR finalization

### 5.1 Pre-merge checks
- 5.1.1 `bunx tsc --noEmit` passes in `apps/web-platform/`.
- 5.1.2 `doppler secrets -p soleur -c prd_orchestration | grep -iE 'TENANT_'` returns only installation_id entries; zero Hetzner/CF/Doppler tokens for tenants.
- 5.1.3 CPO sign-off on ADR-030 (founder-as-first-tenant validation; explicit acknowledgment of unvalidated-by-external-founder demand).
- 5.1.4 PR body has `Ref #3723` (NOT `Closes #3723`).

### 5.2 Post-merge (operator)
- 5.2.1 Apply migration 043 to prd: `doppler run -p soleur -c prd -- npx supabase migration up`. Run smoke-test queries from 2.3.
- 5.2.2 Verify `gh pr diff 3744 --name-only | grep '^\.github/workflows/'` returns empty (no workflows changed; `wg-after-merging-a-pr-that-adds-or-modifies` is N/A).
- 5.2.3 Close 5 follow-up issue threads with PR merge URL.
