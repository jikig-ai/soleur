---
title: Soleur-managed multi-tenant deploy substrate — v1 scaffolding
date: 2026-05-14
issue: 3723
sibling_issue: 3756
brainstorm: knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md
spec: knowledge-base/project/specs/feat-soleur-managed-deploy-substrate-3723/spec.md
draft_pr: 3744
branch: feat-soleur-managed-deploy-substrate-3723
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: more
status: plan-complete
revision: 2 (post 5-reviewer pass; scope cut ~50% + P0 correctness fixes)
---

# feat: Soleur-managed multi-tenant deploy substrate — v1 scaffolding

## Overview

v1 of the multi-tenant deploy substrate per Approach A (per-tenant GitHub Actions OIDC + tenant-owned cloud accounts, brainstorm `2026-05-14`). Brainstorm chose this approach because it is the **only candidate satisfying the hard credential-aggregation constraint by construction** — each tenant's cloud credentials live exclusively in that tenant's own GitHub repo secrets and OIDC trust relationships, never on Soleur-owned infrastructure.

**Revision 2 (post-review) scope.** Five reviewers (DHH + Kieran + code-simplicity + spec-flow + legal-compliance) converged on a substantial scope reduction for N=1. The original draft shipped a scaffold template, an orchestration TS module, and a cross-tenant integration test against synthesized founders. All three are premature factoring at N=1 — the substrate's value is the **pattern + the runbook**, not pre-built abstractions for tenants who don't exist yet.

**What v1 actually is:**

1. The legal pre-flight (RoPA + LIA + ToS-research + ADR-030 + gdpr-gate report) that the CLO mandates before any multi-tenant code path exists. This is load-bearing for the trajectory.
2. The audit-log Supabase migration that establishes the "Soleur agent triggered deploy for founder X" event substrate. Day-1 per CLO mandate (preserved through review).
3. A manual provisioning runbook walking Jean through provisioning Hetzner + CF + Doppler + GitHub on behalf of his first non-Soleur project.
4. A capability-gap learning + 5 follow-up issues for the deferred-automation work whose shape will only be knowable after the runbook is exercised once.

**What v1 is NOT:** a scaffold-template directory, an orchestration TS module, a tenant_installations registry table, a cross-tenant isolation test against synthesized founders. The "Right thing to extract at N=2" — meaning extract these abstractions when Jean's second project arrives and provides a real call-site to factor against.

Note: this PR is the foundations PR for #3723. Sibling issue #3756 covers the symptom-fix for Soleur's own monorepo (replacing the SSH provisioner in `terraform_data.deploy_pipeline_fix` with the existing #749 CF Tunnel + webhook pattern). The two PRs are independent — #3756 unblocks Jean's existing pipeline; this PR (#3744) lays the substrate for Jean's next project.

## User-Brand Impact

**If this lands broken, the user experiences:** A deploy that silently fails to reach the tenant's prod server, while Soleur's UI shows green. Tenant continues operating on a stale, possibly vulnerable build with no signal anything is wrong. (Approach A inherits the silent-deploy-failure risk if the orchestration-plane audit log or the failure-mirror are absent.)

**If this leaks, the user's tenant cloud credentials are exposed via:** A Soleur-owned process holding credentials for >1 tenant simultaneously (eliminated by Approach A's construction), OR a cross-tenant read leak in the meta-audit log (Supabase RLS bypass), OR a compromised Soleur GitHub App install token within its 1-hour TTL dispatching arbitrary workflows on tenant repos.

**Brand-survival threshold:** `single-user incident`. Carried forward verbatim from the brainstorm's Phase 0.1 framing. One tenant's credentials exposed OR one tenant's prod silently stuck = brand-survival event. `user-impact-reviewer` is the load-bearing PR-time gate per `hr-weigh-every-decision-against-target-user-impact`. CPO sign-off required at plan time.

## Research Reconciliation — Spec vs. Codebase

The repo-research-analyst surfaced four divergences between spec.md and the codebase; the plan-review surfaced two more. Resolutions:

| Spec/plan claim | Reality | Plan response |
|---|---|---|
| Spec TR5: "tenant_id" column on the meta-audit log | Codebase uses `founder_id` / `user_id`; **no `tenant_id` column exists anywhere** | Use `founder_id` (the data-layer term for what the brainstorm calls "tenant"). One founder ↔ one tenant at v1. ADR-030 documents the 1:1 mapping. Spec.md updated. |
| Spec TR2: "GitHub App install is greenfield" (implied) | `apps/web-platform/server/github-app.ts` already implements `createAppJwt` + `generateInstallationToken` + `tokenCache` for the existing Soleur App | **v1 cuts the orchestration TS module** per DHH + simplicity. The existing GH App module's existence is noted for the N=2 follow-up. v1's manual runbook calls `gh workflow run` directly. |
| Spec TR3: "Per-tenant Terraform roots, R2 backend" | The existing `apps/web-platform/infra/` is the only Terraform root in this repo; per-tenant roots would live in *tenant* repos, not in this repo. | **v1 cuts the scaffold template directory** per DHH + simplicity. The runbook instructs `git clone apps/web-platform/infra/` into the tenant repo + `sed` placeholder substitution. Extract a template at N=2. |
| Spec TR4: "CF Tunnel + webhook" auth envelope | Repo research shows TWO auth layers required (CF Access service-token AT EDGE + HMAC-SHA256 AT WEBHOOK) | Runbook instructs replicating BOTH auth layers. Plan TR4 prose elaborated. |
| Plan v1 draft: `SET search_path = pg_temp, public` | AGENTS.core.md `cq-pg-security-definer-search-path-pin-pg-temp` verbatim: `SET search_path = public, pg_temp` (in that order). Precedent at `041_dsar_export_jobs.sql:184,239,280,320` is COMPLIANT. | **Fixed in revision 2.** All SECURITY DEFINER functions in migration 043 use `SET search_path = public, pg_temp`. Revision-1 inversion has been removed from plan, spec, and ADR draft. |
| Plan v1 draft: `oidc_jti uuid` | RFC 7519 §4.1.7 defines `jti` as a case-sensitive string. GitHub's OIDC `jti` is currently UUID-shaped but the spec does not guarantee it. | **Fixed in revision 2.** `oidc_jti text NOT NULL CHECK (length(oidc_jti) BETWEEN 1 AND 255)`. |

## Open Code-Review Overlap

Three open code-review issues touch files this plan will modify (verified via `gh issue list --label code-review`):

- **#3221** (ci: nightly cron for env-gated integration tests, review #3217) — references `apps/web-platform/supabase/migrations`. **Acknowledge** — orthogonal CI hygiene.
- **#3220** (ci: postmerge verification of trigger-bearing migrations in prd, review #3217) — same. **Acknowledge** — orthogonal.
- **#3703** (review: add client-pii-grep CI + lefthook gate) — touches `apps/web-platform/lib/client-observability.ts`. **Acknowledge** — about a CI gate, not the audit-log path. (v1 no longer consumes the orchestration module that would have used `reportSilentFallback`; the manual runbook surfaces deploy failures via GH Actions UI directly at N=1.)

No fold-in required.

## Implementation Phases

### Phase 0 — Legal pre-flight: ToS + LIA + RoPA + ADR + gdpr-gate report

**Why first:** CLO mandate from brainstorm. Four pre-merge primitives before any code that touches multi-tenant data ships. Legal-compliance review (revision 2) sharpened the list with LIA + 7 Art. 30(1) limbs + Art. 32 TOMs enumeration.

**Files to Create:**

- `knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md` — Single consolidated ToS-research artifact with four sections (Hetzner, Cloudflare, Doppler, GitHub). Each section must end with a greppable verdict sentinel: `Verdict: ALLOWED` | `Verdict: ALLOWED_WITH_CONDITIONS` | `Verdict: NOT_ALLOWED`. Each section cites the ToS URL + clause number + the attribution / disclosure requirement (if any). Per code-simplicity: 4 separate files is filing-cabinet theatre; the research is one operator-reviewer-approval workflow.
- `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md` — Art. 6(1)(f) three-part test: (i) purpose (operate the multi-tenant deploy substrate for Soleur-as-tenant-zero + future contracted tenants), (ii) necessity (the orchestration plane requires recording dispatch events to evidence Art. 28(3) sub-processor instructions + Art. 32 evidence), (iii) balancing (founder data subjects are the operators triggering deploys; no end-user PII flows through the substrate at v1). Cites ICO + CNIL three-part guidance. Mirrors the structure of any existing LIA in `knowledge-base/legal/` (or establishes the format if absent — this is the first LIA in the repo).
- `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md` — Created via `/soleur:architecture create "Multi-tenant deploy substrate: per-tenant GH Actions OIDC + tenant-owned cloud accounts"`. Six required sub-sections as `## H2` headings (so AC can grep for them):
  - `## Hard constraint — credential-aggregation ceiling`
  - `## Validation gate — founder-as-first-tenant`
  - `## Open escape hatches — Approach B (CF Worker), Approach C (BYOInfra)` with explicit re-evaluation triggers (per brainstorm Open Questions 1 + 2)
  - `## Prior decision #749 — preserved end-to-end`
  - `## OIDC subject-claim binding — repository_owner + environment` (chosen now per Kieran P2-7: tenant repos trust `repository_owner:<tenant-org>` AND `environment:production`; two-claim binding is the canonical pattern)
  - `## Data-layer reconciliation — founder_id ↔ tenant 1:1` (one founder owns one tenant stack at v1; multi-stack-per-founder is out of v1 scope)
- `knowledge-base/legal/gdpr-gate-report-2026-05-14.md` — Committed artifact recording the `/soleur:gdpr-gate` run output. Required by Kieran P1-6 (post-hoc verifiability). Report enumerates: triggers fired, findings (Critical / Should / Defer), operator acknowledgments for any Critical. If gate run produces zero Critical findings, the report still ships as a positive-evidence artifact.

**Files to Edit:**

- `knowledge-base/legal/article-30-register.md` — Add a new processing-activity row enumerating all 7 Art. 30(1) limbs (b)-(g) explicitly (per legal-compliance SHOULD #5):
  - (b) Purposes: orchestrate deploys on behalf of Soleur-operators authoring projects via Soleur agents; record evidence of Art. 28(3) sub-processor instructions.
  - (c) Categories of data subjects: founder-operators (Soleur users acting as tenant operators). NOT end-users of tenant apps (their data does NOT flow through this substrate).
  - (c) Categories of personal data: `founder_id` UUID (pseudonymous identifier); `target_repo` text (user-controlled, length-CHECK-constrained); `target_workflow` text (length-CHECK-constrained); `gh_run_id` bigint (non-PII); `oidc_jti` text (non-PII).
  - (d) Recipients: Soleur internal (service_role); no third-party recipients at v1.
  - (e) Transfers: data resides in Supabase eu-west-1 (Germany). No third-country transfers.
  - (f) Retention: **12 months** (legal-compliance SHOULD #2 — orchestration-plane events do not justify 24mo; PA 8 P0 mirror precedent uses ≤12mo unless open investigation). Inline `-- RETENTION: 12 months via tenant-deploy-audit-retention pg_cron (Art. 5(1)(e))` comment in migration.
  - (g) Art. 32 TOMs enumerated (per legal-compliance SHOULD #6): RLS zero-policies (access control), WORM trigger (integrity), SECURITY DEFINER + `SET search_path = public, pg_temp` (injection defense), `::add-mask::` on Doppler/OIDC secrets in workflows (confidentiality at log layer), pg_cron retention sweep (storage limitation), GitHub Environments + required reviewers (organizational TOM), `hetznercloud/tps-action` short-lived tokens (pseudonymisation/minimisation of long-lived secrets).
- `knowledge-base/legal/compliance-posture.md` — Add note: multi-tenant trajectory means each new non-Soleur tenant deploy triggers DPA signing + Art. 28(4) flow-down obligations. v1 covers Soleur-as-tenant-zero only. **Privacy-policy / DPD sub-processor disclosure is explicit scope-out for v1** (legal-compliance SHOULD #7) — the substrate processes Soleur-operator metadata only, not `app.soleur.ai` end-user data. Re-evaluation trigger: first non-Soleur tenant onboarding.

**Acceptance Criteria (Phase 0):**

- [x] `grep -c 'Verdict: ALLOWED' knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md` returns ≥4 (one per provider section), OR explicit `ALLOWED_WITH_CONDITIONS` / `NOT_ALLOWED` with operator ack documented in `compliance-posture.md` Active Items.
- [x] LIA artifact exists with the three Art. 6(1)(f) sections present (`grep -cE '^## (Purpose|Necessity|Balancing)' knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md` returns 3).
- [x] ADR-030 published with all 6 required `## H2` sub-sections present (`grep -c '^## ' knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md` returns ≥6; each subsection title grepped explicitly).
- [x] gdpr-gate report committed at `knowledge-base/legal/gdpr-gate-report-2026-05-14.md`; if any Critical, operator-ack written to `compliance-posture.md` Active Items.
- [x] RoPA row added at `knowledge-base/legal/article-30-register.md` enumerating all 7 Art. 30(1) limbs (b)-(g) as named subsections.
- [x] `compliance-posture.md` updated with the explicit scope-out for privacy-policy disclosure at v1 + re-evaluation trigger.

### Phase 1 — Meta-audit log Supabase migration

**Why this order:** CLO mandate from brainstorm (day-1 audit log). Legal-compliance BLOCKING #3 (Art. 17 anonymise-vs-delete) + SHOULD #2 (12mo retention) + SHOULD #9 (target_repo CHECK) folded inline. Kieran P0-1 (search_path order) + P1-4 (oidc_jti type) + P0-2 (numbering collisions) + spec-flow P0 #1 (enum-without-writer) + P0 #8 (ON DELETE RESTRICT) folded inline.

**Files to Create:**

- `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql` — Clones `041_dsar_export_jobs.sql:127-216` template. Required shape:
  - Table: `public.tenant_deploy_audit` with columns:
    - `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
    - `founder_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT` (NOT `ON DELETE SET NULL` — spec-flow P0 #8 fix; the anonymise RPC runs BEFORE auth.users deletion via `Art. 17 erasure runbook`)
    - `event_type text NOT NULL CHECK (event_type IN ('workflow_dispatch_triggered','workflow_run_completed','workflow_run_failed'))` — three values only at v1. **No `provisioning_step_*` values** (spec-flow P0 #1: enum without writer is a defect; provisioning events are recorded in the runbook itself, not in this table, at v1).
    - `target_repo text NOT NULL CHECK (target_repo ~ '^[A-Za-z0-9_./-]{1,255}$')` (legal-compliance SHOULD #9 — Art. 5(1)(c) minimisation + log-injection defense)
    - `target_workflow text NOT NULL CHECK (target_workflow ~ '^[A-Za-z0-9_./-]{1,255}\.ya?ml$')` (same)
    - `gh_run_id bigint` (matches GitHub's int64 run_id range)
    - `oidc_jti text CHECK (oidc_jti IS NULL OR length(oidc_jti) BETWEEN 1 AND 255)` (Kieran P1-4 — RFC 7519 §4.1.7 jti is case-sensitive string, not uuid)
    - `trigger_outcome text NOT NULL CHECK (trigger_outcome IN ('queued','succeeded','failed','timeout'))`
    - `event_at timestamptz NOT NULL DEFAULT now()`
    - `retention_until timestamptz NOT NULL DEFAULT (now() + interval '12 months')` — 12mo per legal-compliance SHOULD #2. Inline comment: `-- RETENTION: 12 months via tenant-deploy-audit-retention pg_cron job (Art. 5(1)(e))`.
  - RLS enabled with **zero policies** (service-role-only) — same pattern as `dsar_export_audit_pii`.
  - WORM via BEFORE UPDATE/DELETE triggers raising `P0001` unless GUC `app.tenant_deploy_anonymise_in_progress` is set AND `current_user = 'service_role'`.
  - SECURITY DEFINER writer RPC `public.write_tenant_deploy_audit(p_founder_id uuid, p_event_type text, p_target_repo text, p_target_workflow text, p_gh_run_id bigint, p_oidc_jti text, p_trigger_outcome text)` returning `void`. **`SET search_path = public, pg_temp`** (public FIRST, per AGENTS.core.md verbatim — Kieran P0-1 corrected from revision-1 draft).
  - Per `2026-03-20-supabase-column-level-grant-override.md`: REVOKE INSERT/UPDATE/DELETE at TABLE level from `PUBLIC, anon, authenticated`. GRANT EXECUTE on the writer RPC to `service_role` only.
  - Index `(founder_id, event_at DESC)` for tenant-scoped tail queries.
  - Art. 17 cascade: `anonymise_tenant_deploy_audit(p_founder_id uuid)` mirroring `041_dsar_export_jobs.sql:118-126` precedent. **Must UPDATE rows to set `founder_id = NULL` (preserving row count) inside the `app.tenant_deploy_anonymise_in_progress = 't'` GUC window** — NOT DELETE. Acceptance criteria below verify this semantic.
  - 12-month retention pg_cron sweep: `SELECT cron.schedule('tenant-deploy-audit-retention', '0 4 * * *', $$ DELETE FROM public.tenant_deploy_audit WHERE retention_until < now() $$);`

**Acceptance Criteria (Phase 1):**

- [ ] Migration applies cleanly in dev (`doppler run -p soleur -c dev -- npx supabase migration up`). prd application is post-merge.
- [ ] WORM trigger rejects direct UPDATE/DELETE: `psql -c "UPDATE public.tenant_deploy_audit SET trigger_outcome = 'X' WHERE id = '<test-id>';"` → returns `P0001`.
- [ ] Writer RPC works under service_role context for valid input; rejects malformed `target_repo` / `target_workflow` per CHECK constraints.
- [ ] Anon role cannot SELECT: returns zero rows (RLS-blocked).
- [ ] **Anonymise semantics verified** (legal-compliance BLOCKING #3): `SELECT count(*) FROM public.tenant_deploy_audit;` before and after calling `anonymise_tenant_deploy_audit('<test-uuid>')` returns the same count. Per-row `founder_id` is NULL for the anonymised rows.
- [ ] `SET search_path = public, pg_temp` confirmed on the writer RPC: `SELECT prosrc FROM pg_proc WHERE proname = 'write_tenant_deploy_audit';` shows `SET search_path = public, pg_temp` (in that order; Kieran P0-1).
- [ ] Retention sweep cron scheduled: `SELECT jobname FROM cron.job WHERE jobname = 'tenant-deploy-audit-retention';` returns exactly 1 row.
- [x] Retention column + comment present: `grep -cE 'retention_until|RETENTION: 12 months' apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql` returns ≥2.
- [x] `oidc_jti` column type is `text NOT NULL CHECK (...)`, not `uuid`: `\d+ public.tenant_deploy_audit` shows `text` for that column.
- [x] `founder_id` FK uses `ON DELETE RESTRICT`: `\d+ public.tenant_deploy_audit` shows `ON DELETE RESTRICT` (not `SET NULL`).
- [x] Event-type enum has exactly 3 members (no `provisioning_step_*` ghost values).

### Phase 2 — Manual provisioning runbook + offboarding runbook

**Why this order:** With the audit-log primitive in place, the runbook walks Jean through provisioning his first non-Soleur tenant by hand. This phase is the actual v1 product per DHH + code-simplicity (the runbook IS the orchestration plane at N=1). spec-flow P0 #2 (mid-provisioning teardown) + legal-compliance SHOULD #4 (Step 0 DPA gate) + spec-flow P2 #10 (OIDC auth probes) folded inline.

**Files to Create:**

- `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` — Step-by-step manual provisioning. Each step is a numbered `### Step N` heading with an inline verify-command (per Kieran P1-5 — convert soft criteria to grep-able sentinels). 9 steps:

  0. **Tenant DPA signed + counter-signed.** Tenant Data Processing Agreement names Hetzner + Cloudflare + Doppler + GitHub as authorized sub-processors (Schedule 2). Tenant ack of Art. 28(2) prior-authorisation for sub-processor changes recorded in `knowledge-base/legal/tenant-dpa-register.md` (new file; create at first onboarding). **Verify:** the new file exists with at least one signed row.
  1. **Create Hetzner sub-project.** Smoke-test the token with a known-write op (create + delete a dummy resource per `2026-03-21-cloudflare-tunnel-server-provisioning.md` Session Error #2 — read-only tokens silently succeed for reads). **Verify:** `hcloud server create --name probe --type cx11 --image ubuntu-22.04` succeeds AND `hcloud server delete probe` succeeds.
  2. **Create Cloudflare account / scoped sub-account.** Per the ToS-research artifact's Cloudflare verdict from Phase 0. Create a scoped account-API token (Workers Deploy + Pages Deploy + the specific zone only). **Verify:** `wrangler whoami` returns the new account, AND `wrangler r2 bucket list` succeeds (a write-class operation).
  3. **Create Doppler project (`prd_tenant_<id>` config).** Set up Doppler OIDC service-account identity per `docs.doppler.com/docs/service-account-identities`. **Verify:** `doppler me` returns the new identity in the tenant context.
  4. **Create GitHub repo for the tenant + install the Soleur GitHub App.** Install with NARROW scope (`actions: write` + `metadata: read`, repo-pinned not org-wide). Use exact slug `app/soleur` (NOT `*[bot]`) per learning `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`. **Verify:** `gh api /repos/<tenant>/<repo>/installation` returns the install metadata with the expected permission set.
  5. **Clone `apps/web-platform/infra/` into the tenant repo and substitute placeholders.** `sed -i 's/<SOURCE_TOKEN>/<TENANT_VALUE>/' infra/*.tf` for each of: `app_domain_base`, `cf_zone_id`, `cf_account_id`, `hcloud_token` (env-var-fed), `webhook_deploy_secret`, plus the R2 backend `key = "tenants/<founder-id>/terraform.tfstate"`. **Verify:** `terraform validate` passes in the tenant repo's `infra/` directory.
  6. **Configure GitHub Actions OIDC trust per provider.** Hetzner via `hetznercloud/tps-action@<sha-pin>` (short-lived per-job tokens — closest substitute for native OIDC; brainstorm noted Hetzner has no OIDC GA). Cloudflare via the scoped account-API token (CF has no native OIDC). Doppler via Service Account Identity OIDC. **Verify (spec-flow P2 #10):** per-provider auth probes in the test workflow run BEFORE the deploy step — `hcloud server list` (Hetzner), `wrangler whoami` (CF), `doppler me` (Doppler). All three must succeed in the workflow's pre-deploy gate.
  7. **Configure GitHub Environment `production` on the tenant repo.** Required reviewers (Jean as tenant for v1) + deployment branch policy pinned to `main`. **This is the load-bearing security control** that limits `workflow_dispatch + actions:write` blast radius (per external-research mitigations + Kieran P2). **Verify:** `gh api /repos/<tenant>/<repo>/environments/production` returns `required_reviewers.users` matching the expected list.
  8. **Insert the tenant's installation_id into Soleur's secrets store.** v1 stores the installation_id as a **Doppler secret** (`TENANT_<id>_INSTALLATION_ID`) in `prd_orchestration` config, NOT in a Supabase registry table (migration 044 cut per code-simplicity). At N=1 there is one row to track; a table is premature. **Verify:** `doppler secrets get TENANT_<id>_INSTALLATION_ID -p soleur -c prd_orchestration --plain` returns a numeric installation ID.
  9. **Smoke-test deploy.** Trigger via `gh workflow run deploy.yml --repo <tenant>/<repo> --ref main`. Confirm the workflow run succeeds AND record one row in `public.tenant_deploy_audit` (manually call the writer RPC from a `psql` session for v1; Phase 6 follow-up will automate). **Verify:** `SELECT count(*) FROM public.tenant_deploy_audit WHERE founder_id = '<jean's founder uuid>';` returns ≥1.

  **Abort-mid-provisioning path** (spec-flow P0 #2): if Step N fails, run the reverse-order teardown commands documented inline. Each step explicitly states "If this step fails, rerun Step N-1 teardown first, then Step N teardown." Reverse-order commands:
  - Step 4 teardown: uninstall App via `gh api -X DELETE /app/installations/<install-id>` AND sweep ruleset bypass actors for ghost entries per learning `2026-03-19-github-ruleset-stale-bypass-actors.md`.
  - Step 1-3 teardown: corresponding provider `delete-project` / `delete-account` calls.

- `knowledge-base/engineering/ops/runbooks/tenant-offboarding.md` — Tenant offboarding runbook. Must explicitly include: ruleset bypass-actor sweep on tenant repo (per learning `2026-03-19-github-ruleset-stale-bypass-actors.md` — GitHub does NOT auto-prune `bypass_actors` when an App is uninstalled). Provider-side account-ownership-transfer steps per provider. Call `anonymise_tenant_deploy_audit(<founder-id>)` BEFORE `auth.users` deletion to satisfy Art. 17 cascade (the `ON DELETE RESTRICT` FK forces this ordering — runbook documents the order explicitly).

**Acceptance Criteria (Phase 2):**

- [x] Provisioning runbook has 10 steps (Step 0 through Step 9), each as a `### Step N` numbered heading: `grep -c '^### Step ' knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` returns 10.
- [x] Each step has an inline `**Verify:**` line: `grep -c '^\*\*Verify:\*\*' knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` returns ≥10.
- [x] Abort-mid-provisioning teardown path documented: `grep -c 'teardown' knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` returns ≥4 (Steps 1-4 each have teardown).
- [x] Per-provider OIDC auth probes (`hcloud server list`, `wrangler whoami`, `doppler me`) explicitly named in Step 6 verify section.
- [x] Offboarding runbook includes: bypass-actor sweep + `anonymise_tenant_deploy_audit` BEFORE `auth.users` deletion.
- [x] `knowledge-base/legal/tenant-dpa-register.md` created (initially empty; first row written at first onboarding).

### Phase 3 — Documentation: capability-gap learning + follow-up issues

**Why this order:** Per `wg-when-deferring-a-capability-create-a` — every deferred capability needs a tracking issue with explicit re-evaluation criteria. The 5 deferrals are legitimate (not scope-laundering per code-simplicity review); the 2 escape-hatch issues are dropped (ADR-030 captures them as re-evaluation triggers, not backlog).

**Files to Create:**

- `knowledge-base/project/learnings/2026-05-14-gh-oidc-subject-claim-no-precedent.md` — Capability-gap learning recording: the KB had zero prior OIDC trust-policy learnings before this work; this plan establishes the precedent (`repository_owner:<tenant-org>` + `environment:production` two-claim binding) for future tenant scaffolds. Records the chosen subject-claim shape per provider.

**Follow-up issues to file** (per `wg-when-deferring-a-capability-create-a`). Five legitimate deferrals:

- `feat: Hetzner sub-project provisioning automation (skill)` — Re-evaluation trigger: Jean ships his 2nd non-Soleur project (runbook exercised once).
- `feat: Cloudflare account/sub-account provisioning automation (skill)` — Same.
- `feat: Doppler project + OIDC identity provisioning automation (skill)` — Same.
- `feat: GitHub repo + App install + Environment configuration automation (skill)` — Same.
- `feat: Deploy-failure UI surface in Soleur (Art. 13 in-product transparency, brainstorm Open Question 4)` — Re-evaluation trigger: tenant complaint about not seeing GH Actions failures in-product (legal-compliance DEFER #8).

Approach B (CF Worker) and Approach C (BYOInfra) are **NOT filed as issues** per code-simplicity feedback — ADR-030's `## Open escape hatches` section captures their re-evaluation triggers in the canonical location for architectural-option deferrals.

All 5 follow-ups filed with `--label deferred-scope-out --milestone "Post-MVP / Later"`. Read `knowledge-base/product/roadmap.md` and adjust milestone per the canonical phase rules at filing time.

**Acceptance Criteria (Phase 3):**

- [x] Capability-gap learning published with the chosen subject-claim format documented.
- [x] All 5 follow-up issues filed with explicit re-evaluation triggers in each issue body.
- [x] Each follow-up issue body contains links to: this plan, the brainstorm, the spec, ADR-030.
- [x] Issue numbers backfilled into this plan's `## Follow-up tracking` section.

## Acceptance Criteria

### Pre-merge (PR #3744)

- [ ] All Phase 0-3 acceptance criteria met.
- [ ] CPO sign-off on ADR-030 framing (founder-as-first-tenant validation; explicit acknowledgment of unvalidated-by-external-founder demand).
- [x] `bunx tsc --noEmit` passes in `apps/web-platform/` (no orchestration TS module added in v1; the typecheck is a sanity-no-regression gate). Verified 2026-05-14 at work Phase 4.
- [ ] No new credentials added to Soleur Doppler for tenant cloud accounts EXCEPT the installation_id Doppler secret (verify: `doppler secrets -p soleur -c prd_orchestration | grep -iE 'TENANT_'` returns at most installation_id rows; no Hetzner/CF/Doppler tokens).
- [ ] `Ref #3723` in the PR body (NOT `Closes #3723`) — #3723 remains open because v1 ships scaffolding; the issue closes when Jean's first non-Soleur project actually deploys via this substrate.

### Post-merge (operator)

- [ ] Apply migration 043 to prd Supabase: `doppler run -p soleur -c prd -- npx supabase migration up`. Verify with the smoke-test queries from Phase 1 acceptance.
- [ ] Run `gh workflow run` for any modified workflow files per `wg-after-merging-a-pr-that-adds-or-modifies` (likely none in this PR — verify via `gh pr diff 3744 --name-only | grep '^\.github/workflows/'`).
- [ ] Close each of the 5 follow-up issues' parent comment threads with this PR's merge URL.

## Risks

**R1 — GitHub App install token TTL = 1 hour blast radius.** Within the 1-hour install-token TTL, a compromised orchestration plane (Soleur's own infrastructure compromise) can call `workflow_dispatch` on every tenant repo the App is installed on. Mitigation stack: (a) `actions: write` + `metadata: read` only at App-level (hard ceiling), (b) repo-pinned installs not org-wide, (c) GitHub Environments + required reviewers + deployment branch policy pinned to `main` on the tenant side (the actual security boundary — load-bearing per external research). All three are documented in Phase 2 runbook Steps 4 + 7.

**R2 — Hetzner has no native OIDC; `tps-action` is the closest substitute.** The `hetznercloud/tps-action` mints short-lived project tokens. Falls back to long-lived `HCLOUD_TOKEN` repo secret if the tenant's Hetzner project tier is incompatible. v1 documents both paths in the runbook. Acceptable under the hard constraint because each tenant holds ONLY their own Hetzner token in their own GH repo secrets — no Soleur-side aggregation.

**R3 — Cloudflare has no native OIDC.** Same shape as R2: tenant-side scoped account-API token in tenant's GH repo secrets. Token scope is the load-bearing control — `Workers + Pages Deploy + zone-specific` only. Rotation cadence: quarterly, documented in the offboarding runbook.

**R4 — ToS surprise.** ToS research for one of {Hetzner, Doppler} may return NOT_ALLOWED for "account creation on behalf of user." Phase 0 ToS-research artifact is the gate; if any return NOT_ALLOWED, the substrate v1 may need to flip Approach C (BYOInfra) for that provider. ADR-030 captures the conditional in `## Open escape hatches`.

**R5 — Founder-as-first-tenant is N=1.** The validation gate is one user (Jean). Design choices may be biased toward Jean's workflow; design surfaces that look adequate at N=1 may break at N=2. Mitigation: revision-2 cuts (no scaffold template, no orchestration module, no cross-tenant test, no registry table) preserve maximum flexibility for the N=2 case to inform the abstraction shape. Runbook + audit log are the only durable v1 artifacts; everything else extracts at N=2.

**R6 — pg_cron retention sweep silent-failure** (spec-flow P1 #4). Defer cron-health probe to a follow-up issue (the `tenant-deploy-audit-retention` job uses the same pg_cron substrate as PA 8 P0 mirror retention; that substrate's health is monitored repo-wide, not per-job). Document deferral in this plan's `## Follow-up tracking` section.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm + revision-2 plan review by Kieran).
**Assessment:** Approach A is the only candidate satisfying the hard credential-aggregation constraint by construction; inherits the #749 CF Tunnel + webhook pattern inside each tenant repo. Revision-2 plan review caught a P0 search_path-order inversion + jti type defect + ON DELETE SET NULL Art. 17 break — all fixed inline. The substrate shape is right; revision-2 narrows execution to runbook + migration only.

### Legal (CLO)

**Status:** reviewed (carry-forward + revision-2 plan review by legal-compliance-auditor).
**Assessment:** Conditional greenlight v1. Phase 0/1 gating (legal artifacts before any non-Soleur code) is structurally sound. Revision-2 added: LIA artifact, gdpr-gate committed report, Art. 17 anonymise-vs-delete AC, RoPA 7-limb completeness, Art. 32 TOMs enumeration, 12mo retention (down from 24mo), `target_repo` minimisation CHECK, Phase 2 Step 0 tenant DPA gate, explicit scope-out for privacy-policy disclosure at v1. v1 single-tenant gating (Soleur-as-tenant-zero, no non-Soleur code paths) remains the load-bearing legal-risk control.

### Product (CPO)

**Status:** reviewed (carry-forward from brainstorm + revision-2 plan review by DHH + code-simplicity).
**Assessment:** Multi-tenant deploy substrate is not on the roadmap (T1-T4); no external founder has asked. The work proceeds anyway because operator-as-first-tenant validation signal is load-bearing. Revision-2 cut scaffold template + orchestration module + cross-tenant test + registry table per DHH + code-simplicity ("templates earn their keep on the third copy" / "at N=1 there's nothing to orchestrate"). What remains is the smallest honest v1: legal pre-flight + audit-log migration + manual runbook + capability-gap learning + 5 follow-up issues.

### Product/UX Gate

**Tier:** NONE
**Decision:** auto-accepted (infrastructure-only plan; no user-facing UI surfaces, no new component files under `components/**/*.tsx`, no new `app/**/page.tsx` or `app/**/layout.tsx`).
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

**Brainstorm-recommended specialists:** none — brainstorm did not name any specialist outside the triad.

## Test Strategy

- **Migration tests:** Phase 1 acceptance criteria includes WORM trigger smoke-test, anon-read rejection, writer RPC success, anonymise-with-NULL semantics, search_path order verification, CHECK constraint enforcement. All run in dev before prd application. No vitest TS tests needed in v1 since no TS module ships (orchestration module cut per scope reduction).
- **Cross-tenant integration test deferred to N=2.** Once a real second tenant exists, the test becomes meaningful (two real founders with real installation IDs). v1's anon-read-rejection AC validates the RLS invariant at the construction level without synthesizing a fake second founder.
- **Runbook test:** the runbook IS the v1 test — when Jean exercises it for his first non-Soleur project, every Step's `**Verify:**` command is a manual acceptance criterion. Runbook-as-acceptance-test is consistent with DHH + code-simplicity framing.

## Follow-up tracking

Filed at Phase 3 issue-filing time (2026-05-14):

- [x] Hetzner provisioning automation skill: #3769
- [x] Cloudflare provisioning automation skill: #3770
- [x] Doppler provisioning automation skill: #3771
- [x] GitHub repo + App install + Environment automation skill: #3772
- [x] Deploy-failure UI surface (Art. 13 transparency): #3773
- [ ] pg_cron `tenant-deploy-audit-retention` health probe (deferred per Risks R6): #TBD (file at first cron-failure signal; uses same pg_cron substrate as PA 8 P0 mirror retention)

Approach B (CF Worker executor) and Approach C (BYOInfra OAuth) — captured in ADR-030's `## Open escape hatches`, NOT filed as backlog issues. Re-evaluation triggers documented inline in the ADR.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled.
- **SECURITY DEFINER `search_path` order is `public, pg_temp` (in that order)**, per `cq-pg-security-definer-search-path-pin-pg-temp`. The 041 precedent at `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:184,239,280,320` is COMPLIANT — clone it verbatim. (Revision-1 of this plan inverted the order; fixed in revision-2.)
- **Migration numbering collisions** (Kieran P0-2): `apps/web-platform/supabase/migrations/` has 11 duplicate-numbered pairs (017×4, 019×2, 029×2, 037×2, 038×2, 041×2, 042×2). At /work time, verify migration 043 is not in use on another open PR via `gh pr list --state open --json files --jq '.[] | select(.files[].path | test("supabase/migrations/04[3-9]")) | .number'` before final commit. If 043 is taken, increment to next free number.
- **`oidc_jti` is text, not uuid.** Per RFC 7519 §4.1.7 jti is a case-sensitive string. GitHub's OIDC currently uses UUID-shape jti, but the spec does not guarantee it.
- **`ON DELETE RESTRICT` on `founder_id` FK** (NOT `SET NULL`). The Art. 17 cascade requires `anonymise_tenant_deploy_audit()` to run BEFORE `auth.users` deletion; `ON DELETE SET NULL` would nullify the row before the anonymise RPC can run, breaking the audit row's discriminator field. Runbook documents the explicit ordering.
- **No `provisioning_step_*` event types in the v1 enum.** spec-flow P0 #1: enum members without writer code are a defect class. v1 records provisioning events in the runbook itself, not in the audit table. Follow-up issue for Hetzner/CF/Doppler/GitHub automation skills will add writers AND the corresponding event-type enum extensions in the same migration that ships each skill.
- **Per `2026-03-20-supabase-column-level-grant-override.md`**: REVOKE at TABLE level, GRANT-only-on-RPC. Column-level REVOKE is silently ineffective under table-level GRANT.
- **The `app/soleur` GitHub App appears as `app/<slug>` in `pull_request.author.login`, NOT `<name>[bot]`.** Any tenant-side allowlist matching `*[bot]` will silently exclude the Soleur App. Runbook Step 4 + Step 7 (Environment configuration) must use the exact slug.
- **`github-actions[bot]` integration cannot be added as a ruleset bypass actor** (HTTP 422). Only installed GitHub Apps qualify. Tenant rulesets add the Soleur App as the bypass actor via the GitHub UI (not API).
- **GitHub does NOT auto-prune ruleset `bypass_actors` when an App is uninstalled.** Offboarding runbook MUST sweep and remove ghost entries.
- **GDPR Art. 5(1)(e) retention basis is the `retention_until` column**, NOT a timestamp-proximity sweep. The cron job's WHERE clause uses `WHERE retention_until < now()`.
- **OIDC subject-claim binding is fixed at v1** (Kieran P2-7): `repository_owner:<tenant-org>` AND `environment:production`. Documented in ADR-030. Future tenants follow the same two-claim shape unless ADR-030 is amended.

## References

- Issue: #3723 (state: OPEN, reframed to multi-tenant substrate only at brainstorm).
- Sibling symptom-fix issue: #3756.
- Draft PR: #3744.
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md`.
- Spec: `knowledge-base/project/specs/feat-soleur-managed-deploy-substrate-3723/spec.md`.
- Brainstorm cross-check learning: `knowledge-base/project/learnings/2026-05-14-brainstorm-cross-check-leader-substrate-and-issue-body-rule-citations.md`.
- Prior decision #749: `apps/web-platform/infra/firewall.tf:15` + `apps/web-platform/infra/tunnel.tf:1-4`.
- Audit-log template: `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql:127-216` (clone verbatim including `SET search_path = public, pg_temp` order).
- Sentry helper (deferred to N=2 follow-up since v1 has no orchestration module): `apps/web-platform/lib/client-observability.ts:91`.
- CF Tunnel scaffold reference: `apps/web-platform/infra/tunnel.tf`, `webhook.service`, `hooks.json.tmpl`.
- ADR-028 (DSAR substrate + audit retention precedent).
- ADR-030 (this work — created in Phase 0).
- External research citations:
  - Doppler OIDC GA: https://docs.doppler.com/docs/github-oidc-examples
  - Hetzner TPS-action: https://github.com/hetznercloud/tps-action
  - Cloudflare GH Actions deploy patterns: https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/
  - GitHub App permissions reference: https://docs.github.com/en/actions/concepts/security/github_token
  - GitHub Environments deployment-protection: https://docs.github.com/actions/managing-workflow-runs/reviewing-deployments
  - Supabase RLS + custom claims: https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac

## Revision history

- **Revision 1 (2026-05-14)**: Initial draft, 6 phases. Reviewed by DHH + Kieran + code-simplicity + spec-flow-analyzer + legal-compliance-auditor.
- **Revision 2 (2026-05-14)**: Track A applied per operator approval. Scope cut ~50%: removed scaffold template directory, orchestration TS module, migration 044 (tenant_installations registry), cross-tenant integration test against synthesized founders. Cut 2 of 7 follow-up issues (Approach B/C → ADR-030 escape hatches). Consolidated 4 ToS-research files to 1. Fixed P0 correctness: `search_path = public, pg_temp` (was inverted), `oidc_jti text` (was uuid), `ON DELETE RESTRICT` (was SET NULL), no provisioning_step_* event types without writers. Added LIA artifact, gdpr-gate committed report, Step 0 tenant DPA gate, per-provider OIDC auth probes, abort-mid-provisioning teardown path, target_repo/target_workflow CHECK constraints, 12mo retention (was 24mo). Picked OIDC subject-claim now (no defer): `repository_owner:<tenant-org>` + `environment:production`.
