---
title: "Tenant offboarding runbook — multi-tenant deploy substrate v1"
type: runbook
date: 2026-05-14
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
issue: 3723
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
related: [tenant-provisioning]
status: draft-v1
audience: Soleur operator (Jean) acting as agent for a departing tenant
---

# Tenant offboarding runbook — multi-tenant deploy substrate v1

This runbook walks the Soleur operator through offboarding a tenant from
the multi-tenant deploy substrate. The runbook is the inverse of
`tenant-provisioning.md` plus three additional cleanup steps that the
provisioning runbook's individual teardown paths do **not** cover:

1. The Art. 17 anonymise cascade on `public.tenant_deploy_audit` (must run
   BEFORE any `auth.users` deletion per `ON DELETE RESTRICT` FK ordering).
2. The ruleset `bypass_actors` sweep on the tenant repo (GitHub does NOT
   auto-prune bypass actors when an App is uninstalled — `bypass_actors`
   become dangling ghost entries per learning
   `2026-03-19-github-ruleset-stale-bypass-actors.md`).
3. Provider-side account-ownership-transfer or wind-down steps where the
   tenant continues to operate the provider account without Soleur as
   agent (e.g., transferring the Hetzner sub-project to the tenant's own
   master account billing).

### Step 0 — Pre-offboarding gate

Confirm the tenant has either (a) signed a written notice of offboarding
or (b) breached the Tenant DPA in a way that justifies termination per
the DPA's termination clause. Record the basis in
`knowledge-base/legal/tenant-dpa-register.md` row before proceeding.

### Step 1 — Art. 17 audit-log anonymise (MUST run before any auth.users
delete)

**Action**: From a `psql` session against Soleur's prd Supabase with
service_role context, call the cascade RPC:

```sql
SELECT public.anonymise_tenant_deploy_audit('<tenant-founder-uuid>'::uuid);
```

This UPDATEs every `tenant_deploy_audit` row's `founder_id` to NULL
within the GUC-gated WORM-bypass window (per migration 043). The row
count is preserved — audit-trail integrity is maintained.

**Verify**: row count before and after must match; founder_id values
for the tenant must be NULL after:

```sql
-- Before (capture as baseline)
SELECT count(*) AS total, count(*) FILTER (WHERE founder_id IS NOT NULL) AS attributed
  FROM public.tenant_deploy_audit;

-- (run anonymise above)

-- After
SELECT count(*) AS total, count(*) FILTER (WHERE founder_id = '<tenant-founder-uuid>'::uuid) AS remaining_attributed
  FROM public.tenant_deploy_audit;
```

`total` before == `total` after. `remaining_attributed` after == 0.

### Step 2 — GitHub App uninstall + ruleset bypass-actor sweep

**Action**:

1. Uninstall the Soleur GitHub App from the tenant repo:

   ```bash
   gh api -X DELETE /app/installations/<install-id>
   ```

2. **Then** sweep the tenant repo's rulesets for any `bypass_actors`
   entries referencing the now-uninstalled App. Per learning
   `2026-03-19-github-ruleset-stale-bypass-actors.md`, GitHub does **not**
   auto-prune `bypass_actors` when an App is uninstalled — the entries
   remain as dangling references (and could be re-attached to a future
   install of an unrelated App if the IDs collide).

   For each ruleset on the tenant repo:

   ```bash
   gh api /repos/<tenant-org>/<tenant-repo>/rulesets --jq '.[].id' | \
     while read ruleset_id; do
       gh api /repos/<tenant-org>/<tenant-repo>/rulesets/$ruleset_id --jq '.bypass_actors'
     done
   ```

   For each entry pointing at the Soleur App's installation ID, edit the
   ruleset (UI-only — the API path is `PUT /repos/.../rulesets/<id>` but
   API edits of `bypass_actors` are unreliable per the same learning;
   prefer the GitHub UI's "Rulesets" page for this step).

3. Remove the tenant's installation_id from Soleur Doppler:

   ```bash
   doppler secrets delete TENANT_<id>_INSTALLATION_ID \
     -p soleur -c prd_orchestration
   ```

**Verify** (the silent-skip risk on the ruleset sweep is real — the cheap "no output" check from earlier wording cannot distinguish "swept clean" from "operator skipped the UI step entirely", because a repo with zero rulesets also produces no output. The verification below explicitly counts rulesets first and forces an attestation if any exist):

```bash
# 1. App is uninstalled
gh api /repos/<tenant-org>/<tenant-repo>/installation
# Must return 404 Not Found.

# 2. Enumerate rulesets and assert sweep coverage. The two outputs MUST
# both be inspected — a zero ruleset count silently passes the
# bypass-actor check even if Step 2 sub-step 2 was skipped.
RULESET_COUNT=$(gh api /repos/<tenant-org>/<tenant-repo>/rulesets --jq 'length')
echo "Ruleset count: $RULESET_COUNT"

if [[ "$RULESET_COUNT" -gt 0 ]]; then
  echo "Manual attestation required: confirm you opened each ruleset"
  echo "in the GitHub UI and removed any bypass_actor entry whose"
  echo "actor_id matches the (now-uninstalled) Soleur App. Paste the"
  echo "edit timestamps from the GitHub UI into the offboarding row in"
  echo "knowledge-base/legal/tenant-dpa-register.md BEFORE proceeding."
  # API-side ghost check (best-effort; UI is the source of truth):
  gh api /repos/<tenant-org>/<tenant-repo>/rulesets --jq '.[].id' | \
    while read ruleset_id; do
      gh api /repos/<tenant-org>/<tenant-repo>/rulesets/$ruleset_id \
        --jq '.bypass_actors[] | select(.actor_id == <soleur-app-install-id>)'
    done
  # Must produce no output AND the tenant-dpa-register row must carry
  # the UI-edit-timestamp attestation.
fi

# 3. Doppler secret is removed
doppler secrets get TENANT_<id>_INSTALLATION_ID -p soleur -c prd_orchestration --plain 2>&1
# Must return a "secret not found" error.
```

### Step 3 — Provider-side account wind-down (per tenant agreement)

For each upstream provider, follow the tenant's chosen wind-down path:

#### Hetzner

- **Tenant continues to operate** the Hetzner sub-project: transfer
  billing ownership to the tenant's master account (UI-only via
  Hetzner's project settings).
- **Tenant wants full wind-down**: delete the sub-project entirely
  via the Hetzner Cloud Console (`Project → Settings → Delete project`).
  All resources must be deleted first (servers, volumes, networks, etc.).
- **Always**: revoke the project-scoped API token from
  `Security → API tokens`.

#### Cloudflare

- **Tenant continues**: revoke only the Soleur-issued scoped account-API
  token from `My Profile → API Tokens`. The tenant retains the account
  and all configuration.
- **Tenant wants wind-down**: tenant's choice to close the CF account
  (My Profile → Account → Close); Soleur does not perform this step.

#### Doppler

- **Tenant continues**: revoke the Service Account Identity from
  `Settings → Service Accounts → <identity-name> → Revoke`. Tenant
  retains the project + configs.
- **Tenant wants wind-down**: tenant's choice to delete the project
  (`Projects → <project-name> → Delete`); Soleur does not perform this
  step.

#### GitHub

- The repository remains under the tenant's organization unless the
  tenant explicitly requests Soleur to delete it (Soleur should not
  delete the tenant's repo by default; tenant data lives there).
- If the tenant requests deletion: `gh api -X DELETE /repos/<tenant-org>/<tenant-repo>`.
  **One-way; not reversible.** Confirm in writing first.

**Verify**: per the tenant's chosen wind-down path, run the
provider's `me`/`whoami` command with the previously-active token; the
command must return 401/403 confirming revocation.

### Step 4 — Tenant data subject deletion (per Art. 17 if requested)

If the tenant invokes Art. 17 erasure for the founder's personal data:

1. **First** confirm Step 1 (`anonymise_tenant_deploy_audit`) has run
   successfully. Re-run if not.
2. Call `auth.admin.deleteUser('<tenant-founder-uuid>')` via Supabase
   service_role context.
3. Verify the FK `ON DELETE RESTRICT` does NOT raise an error (it would
   only raise if Step 1 was skipped or failed).

If `auth.admin.deleteUser` raises a FK constraint error, **STOP**:
Step 1 did not anonymise all `tenant_deploy_audit` rows. Investigate
(possibly the founder_id used in Step 1 did not match the actual
auth.users.id — common cause: a copy-paste UUID typo).

**Verify**: `SELECT count(*) FROM auth.users WHERE id = '<tenant-founder-uuid>'::uuid;`
returns 0.

### Step 5 — Document offboarding outcome

Update `knowledge-base/legal/tenant-dpa-register.md` row with:

- Status: `offboarded` (or `offboarded-with-data-deleted` if Step 4 ran).
- Date of offboarding.
- Provider wind-down disposition per Step 3 (transferred / wound-down /
  retained).

## References

- Provisioning runbook: `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`
- ADR-030: `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- Migration 043: `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql`
- Tenant DPA register: `knowledge-base/legal/tenant-dpa-register.md`
- Learning — ruleset bypass actors: `knowledge-base/project/learnings/2026-03-19-github-ruleset-stale-bypass-actors.md`
