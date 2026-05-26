---
title: "Tenant provisioning runbook — multi-tenant deploy substrate v1"
type: runbook
date: 2026-05-14
plan: knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md
issue: 3723
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
status: draft-v1
audience: Soleur operator (Jean) acting as agent for an authorized tenant
---

# Tenant provisioning runbook — multi-tenant deploy substrate v1

This runbook walks the Soleur operator (Jean) through provisioning the
**first non-Soleur tenant** by hand. The runbook IS the orchestration plane
at v1 — automation is deferred to N=2 (per ADR-030's founder-as-first-tenant
gate). Each step is numbered `### Step N`, ends with an inline `**Verify:**`
sentinel command, and documents its abort-mid-provisioning teardown path.

**Authorization precondition**: the tenant (a real legal entity with a signed
Tenant DPA — see Step 0) has authorized Soleur to act as their agent for the
specific provisioning steps below. Authorization is per-tenant, per-onboarding;
it is not re-used across tenants.

**Hard constraint** (per ADR-030): at no point during or after provisioning
may Soleur infrastructure hold long-lived credentials for more than one
tenant's cloud account at a time. Every step below preserves the constraint
by leaving long-lived credentials exclusively in the tenant's own GitHub
repository secrets and OIDC trust relationships.

---

### Step 0 — Tenant DPA signed + counter-signed

**Action**: Sign + counter-sign the tenant's Data Processing Agreement.
The DPA names Hetzner + Cloudflare + Doppler + GitHub as authorized
sub-processors (Schedule 2). Tenant acknowledges Art. 28(2) prior-authorisation
for sub-processor changes. Record the signed DPA + signatory + date in
`knowledge-base/legal/tenant-dpa-register.md` (one row per tenant). Per
legal-compliance SHOULD #4 — this gate runs BEFORE any provider account
is created on behalf of the tenant.

If the tenant has not signed: **STOP here**. Do not proceed to Step 1.
Counsel review may be required for any tenant whose DPA negotiation
deviates from the template.

**Verify:** `test -s knowledge-base/legal/tenant-dpa-register.md && grep -c '^|' knowledge-base/legal/tenant-dpa-register.md | xargs -I{} test {} -ge 3` — file exists with at least one signed row (header row + separator row + ≥1 data row = ≥3 pipe-lines).

**Teardown (if a later step fails)**: no teardown required at Step 0 itself; the DPA remains valid. Document the aborted onboarding in `knowledge-base/legal/tenant-dpa-register.md` with status `aborted-provisioning` so the next attempt knows what state was reached.

---

### Step 1 — Create Hetzner sub-project

**Action**: Log in to the tenant's Hetzner Cloud master account (the
tenant org-owner has separately accepted Hetzner's Customer terms per the
ToS-research artifact). Create a sub-project named after the tenant's
canonical slug (e.g. `tenant-<slug>-prd`). Mint a project-scoped API token
with read+write permissions limited to that sub-project. Smoke-test the
token with a known-write op (create + delete a dummy resource) per
`2026-03-21-cloudflare-tunnel-server-provisioning.md` Session Error #2 —
**read-only tokens silently succeed for reads**, so a read-only verify
gives a false-positive ALLOWED signal.

**Verify:** run (per the token-quarantine discipline below — use `read -s`
+ subshell, never inline literals that leak into shell history):

```bash
read -rs -p "Hetzner token: " HCLOUD_TOKEN; echo
(
  export HCLOUD_TOKEN
  hcloud server create --name probe --type cx11 --image ubuntu-22.04
  hcloud server delete probe
)
unset HCLOUD_TOKEN
```

Both commands inside the subshell must exit 0. If `hcloud server create`
returns 401/403, the token has insufficient scope. The `unset` removes
the token from the parent shell after the subshell exits.

**Teardown (Step 1)**: `hcloud project delete <sub-project-name>` from the
tenant's master account UI (CLI does not support project deletion at
time of writing). If the deletion fails because resources remain,
manually delete the dummy resources first.

---

### Step 2 — Create Cloudflare scoped account-API token

**Action**: Log in to the tenant's Cloudflare account (the tenant has
separately accepted CF Self-Serve Subscription Agreement per the
ToS-research artifact). Create a scoped account-API token with **only**
the following permissions:

- `Workers Scripts:Edit` (zone: All zones on the tenant account)
- `Workers Routes:Edit` (zone: the tenant's specific zone)
- `Account:Cloudflare Pages:Edit` (account: the tenant's account)
- `Zone:DNS:Edit` (zone: the tenant's specific zone)

**Do NOT** grant `User Details:Read` or `Account:Account Settings:Read`
— those are broader than the deploy use case and violate the
least-privilege control in plan §R3.

**Verify:** run

```bash
CLOUDFLARE_API_TOKEN=<tenant-token> wrangler whoami
CLOUDFLARE_API_TOKEN=<tenant-token> wrangler r2 bucket list
```

`wrangler whoami` must return the tenant's account name. `wrangler r2
bucket list` is a write-class smoke-test (lists buckets, requires R2
permissions — proves the token has account-scoped write capability).
If `wrangler r2 bucket list` returns 403, the token's scope is wrong
for the deploy flow.

**Teardown (Step 2)**: revoke the API token from the CF dashboard's
**My Profile → API Tokens** page. (Token revocation is irreversible by
the tenant org owner.)

---

### Step 3 — Create Doppler project + OIDC service-account identity

**Action**: Log in to the tenant's Doppler account (separate Customer
acceptance per the ToS-research artifact). Create a project named after
the tenant's canonical slug. Inside the project, create a `prd_tenant_<id>`
config. Then configure a **Service Account Identity** for OIDC trust against
the tenant's GitHub repository per
`https://docs.doppler.com/docs/service-account-identities`. The OIDC
subject-claim binding (per ADR-030) must be two-claim:

```text
repository_owner:<tenant-org>
environment:production
```

Do NOT trust `repository_owner` alone (too broad) or `environment` alone
(unkeyed to a specific tenant).

**Verify:** from a test workflow on the tenant repo, run

```bash
doppler me
```

The output must show the new Service Account Identity name in the
tenant's project context.

**Teardown (Step 3)**: from Doppler dashboard, **Settings → Service Accounts
→ <identity-name> → Revoke**, then **Projects → <project-name> → Delete**.

---

### Step 4 — Create GitHub repo + install Soleur GitHub App

**Action**: In the tenant's GitHub organization, create a new repository for
the tenant's project. Install the Soleur GitHub App (`app/soleur`) on
**this single repository** with the following permissions:

- `actions: write`
- `metadata: read`

**Do NOT** install org-wide. Repo-pinned is the hard ceiling on blast
radius per plan §R1.

The install must be performed by a **human** acting under the tenant org
owner's authority per GitHub ToS §B.3 (machine-account exception). Soleur
automation does not perform the install.

**Slug discipline**: the App appears as `app/soleur` in
`pull_request.author.login`, **NOT** `*[bot]`. Any tenant-side allowlists
matching `*[bot]` will silently exclude the Soleur App per learning
`2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`.

**Verify:** run

```bash
gh api /repos/<tenant-org>/<tenant-repo>/installation
```

Output must show `permissions.actions: "write"` and
`permissions.metadata: "read"` and **no other write-class permissions**.

**Teardown (Step 4)**: `gh api -X DELETE /app/installations/<install-id>`,
then sweep any tenant ruleset `bypass_actors` for ghost entries per
learning `2026-03-19-github-ruleset-stale-bypass-actors.md` (GitHub does
NOT auto-prune `bypass_actors` when an App is uninstalled — manual sweep
is mandatory).

**If Step 4 fails: rerun Step 1-3 teardowns first, then Step 4 teardown.**

---

### Step 5 — Clone `apps/web-platform/infra/` template + substitute placeholders

**Action**: From the tenant's repo working tree, clone the canonical infra
directory from Soleur's monorepo as the starting Terraform root:

```bash
# In the tenant's repo working tree (NOT in Soleur's monorepo)
cp -r ../soleur/apps/web-platform/infra/ ./infra/
```

Then `sed -i` substitute the following placeholders inside `infra/*.tf`
to the tenant's values:

| Placeholder | Tenant value |
|---|---|
| `<APP_DOMAIN_BASE>` | tenant's deploy domain (e.g. `app.tenant.example`) |
| `<CF_ZONE_ID>` | tenant's CF zone ID (from Step 2) |
| `<CF_ACCOUNT_ID>` | tenant's CF account ID (from Step 2) |
| `<HCLOUD_TOKEN_ENV_VAR_NAME>` | env-var name (token lives in repo secrets, NOT in tf code) |
| `<WEBHOOK_DEPLOY_SECRET_ENV_VAR_NAME>` | env-var name for the HMAC secret |

Update the R2 backend block (per ADR-006) to:

```hcl
terraform {
  backend "s3" {
    bucket = "<TENANT_R2_BUCKET>"
    key    = "tenants/<founder-id>/terraform.tfstate"
    # ... (other R2-backend settings per ADR-006)
  }
}
```

**Verify:** in `tenant-repo/infra/`, run

```bash
terraform fmt -check .
terraform init -backend=false
terraform validate
```

`fmt -check` exits 0 (no formatting drift). `validate` exits 0 (no HCL
syntax errors and no undefined references). If `validate` fails with
"Reference to undeclared resource", a `sed` substitution missed a
placeholder — search the diff for any remaining `<...>` token.

**Teardown (Step 5)**: `rm -rf tenant-repo/infra/`. If `terraform init`
created `.terraform/`, also `rm -rf tenant-repo/.terraform/`.

**If Step 5 fails: rerun Step 4 teardown first, then Step 5 teardown.**

---

### Step 6 — Configure GitHub Actions OIDC trust per provider

**Action**: Add the deploy workflow under `.github/workflows/deploy.yml` in
the tenant repo. The workflow's `permissions:` block must include:

```yaml
permissions:
  id-token: write          # mint OIDC JWT
  contents: read
  actions: read
  deployments: write
```

Per-provider OIDC configuration:

- **Hetzner** (no native OIDC): use `hetznercloud/tps-action@<sha-pin>`
  to mint a short-lived per-job project token from the long-lived
  `HCLOUD_TOKEN` repo secret. The long-lived token lives in the
  **tenant's** GitHub repo secrets — never in Soleur's Doppler.
- **Cloudflare** (no native OIDC): consume the scoped account-API token
  from Step 2 via the tenant repo's `CLOUDFLARE_API_TOKEN` secret.
- **Doppler** (native OIDC): use `dopplerhq/cli-action` with the OIDC
  flow against the Service Account Identity from Step 3.

**Pre-deploy authentication probes** (per spec-flow P2 #10): add a
pre-deploy job step that probes each provider's authentication and
**fails the workflow** if any probe fails — never silently proceed past
a failed probe. The probes are write-class smoke-tests:

```yaml
- name: Hetzner auth probe
  run: hcloud server list
- name: Cloudflare auth probe
  run: wrangler whoami
- name: Doppler auth probe
  run: doppler me
```

**Verify:** trigger the deploy workflow with no actual deploy payload
(pre-deploy probes only):

```bash
gh workflow run deploy.yml --repo <tenant-org>/<tenant-repo> --ref main --field probes_only=true
```

All three probe steps must report success in the workflow log. If any
probe fails (e.g., Cloudflare 403), the corresponding earlier Step's
scoping is wrong — fix the token/identity, do not work around the
failed probe.

**Teardown (Step 6)**: `git rm .github/workflows/deploy.yml` from the
tenant repo's working tree. No external state changes.

---

### Step 7 — Configure GitHub Environment `production` on tenant repo

**Action**: Create a GitHub Environment named `production` on the
tenant repo. Configure:

- **Required reviewers**: the tenant org owner (and Jean for v1
  Soleur-as-tenant-zero only). At least one reviewer must approve
  every workflow run that targets the `production` environment.
- **Deployment branch policy**: pinned to `main` only. No deploys from
  feature branches or PR head refs.
- **Wait timer**: 0 minutes (no artificial delay).
- **Environment secrets**: hold provider-specific secrets here, NOT in
  repo-level secrets (Environment scoping is tighter; environment
  secrets are only accessible to workflows targeting that environment).

**Why load-bearing**: GitHub Environments + required reviewers is the
**security control that caps `workflow_dispatch + actions:write` blast
radius** per plan §R1 + Kieran P2. Without this control, a 1-hour
install-token-mint compromise on Soleur's side could dispatch
arbitrary workflows on every tenant repo the App is installed on.
With it, every dispatch requires a tenant-side human reviewer.

**Verify:** run

```bash
gh api /repos/<tenant-org>/<tenant-repo>/environments/production
```

Output must show:
- `protection_rules` containing a `required_reviewers` entry with the
  expected user list.
- `deployment_branch_policy.protected_branches: true` and
  `custom_branch_policies: false` (or a `custom_branch_policies` rule
  pinning to `main` only).

**Teardown (Step 7)**: from GitHub dashboard, **Repository → Settings →
Environments → production → Delete**. Removes environment + scoped
secrets.

---

### Step 8 — Insert tenant's installation_id into Soleur Doppler

**Action**: After Step 4, retrieve the tenant's GitHub App installation
ID:

```bash
gh api /repos/<tenant-org>/<tenant-repo>/installation --jq .id
```

Store the installation ID as a **Doppler secret** in Soleur's own
`prd_orchestration` config:

```bash
doppler secrets set TENANT_<id>_INSTALLATION_ID=<numeric-installation-id> --silent --no-interactive -p soleur -c prd_orchestration >/dev/null 2>&1
```

> Doppler `secrets {set,delete}` echo guidance — `--silent` + `>/dev/null 2>&1` is the canonical no-leak pattern. See [`knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md`](../../../project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md) §Leak-2 (widened 2026-05-18 via #4029).

v1 stores this in Doppler (not a Supabase registry table). At N=1 there
is one row to track; a registry table is premature per plan revision-2
scope cut (migration 044 dropped). Extract a Supabase table at N=2 when
≥3 tenants exist.

**Verify:** run

```bash
doppler secrets get TENANT_<id>_INSTALLATION_ID -p soleur -c prd_orchestration --plain
```

Output must be a numeric integer (the installation ID).

**Teardown (Step 8)**: `doppler secrets delete TENANT_<id>_INSTALLATION_ID --silent --yes -p soleur -c prd_orchestration >/dev/null 2>&1`.

---

### Step 9 — Smoke-test deploy + record audit row

**Action**: From the tenant repo, trigger a smoke-test deploy:

```bash
gh workflow run deploy.yml --repo <tenant-org>/<tenant-repo> --ref main
```

Watch the workflow run via:

```bash
gh run watch --repo <tenant-org>/<tenant-repo>
```

Once the workflow completes (succeed or fail), manually record the
audit row from a `psql` session against Soleur's prd Supabase
(v1 calls the writer RPC manually; automation of this call is the
N=2 follow-up — see Phase 3 issues):

```sql
SELECT public.write_tenant_deploy_audit(
  '<jean-founder-uuid>'::uuid,
  'workflow_dispatch_triggered',
  '<tenant-org>/<tenant-repo>',
  'deploy.yml',
  <gh-run-id>::bigint,
  '<oidc-jti-from-workflow-log>',
  '<queued|succeeded|failed|timeout>'
);
```

**Verify:** run

```sql
SELECT count(*) FROM public.tenant_deploy_audit
 WHERE founder_id = '<jean-founder-uuid>'::uuid;
```

Result must be `≥ 1`. If 0, the writer RPC was rejected — check
service_role context and CHECK-constraint compliance of the inputs.

**Teardown (Step 9)**: no teardown required for the smoke-test row
itself (audit-trail integrity; the row will age out per the 12-month
retention sweep). If the entire onboarding is being aborted, run
`SELECT public.anonymise_tenant_deploy_audit('<jean-founder-uuid>'::uuid);`
to NULL-out the founder_id before any auth.users deletion (per
`ON DELETE RESTRICT` FK ordering).

---

### Step 10 — Supabase runtime-JWT substrate (#3363 Resolution C)

Required once per Soleur deployment (N=1 today; per-tenant once N>1 if
each tenant gets its own Supabase project). Skipped if the Supabase
project already shows ES256 in JWKS and the runtime hook registered.

**10.a — Verify (or enable) JWT Signing Keys on the Supabase project.**

```bash
# Probe the JWKS endpoint. Expect alg=ES256 (or RS256) on a kid.
curl -sS "${SUPABASE_URL}/auth/v1/.well-known/jwks.json" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  | jq '.keys | length as $n | {count: $n, algs: [.[].alg], kids: [.[].kid]}'
```

If `count: 0` / no asymmetric kid: enable in Supabase Dashboard →
API → "JWT Signing Keys" → Enable. Single-click, no downtime per the
Supabase rotation guarantee. There is no Mgmt API endpoint for this
toggle as of 2026-05-18 — this is the one operator-acknowledged
Dashboard click in the substrate. Re-run the probe to confirm.

**10.b — Apply migrations 047 + 048 + 049 + 050** via the standard
`apps/web-platform/scripts/apply-migrations.mjs` flow (or Doppler
`DATABASE_URL_POOLER` with port `:5432` for session-mode multi-statement
DDL — see `2026-05-18-vendor-token-mint-…-content-carrier-patterns.md`).
Migrations 049 and 050 are the Phase-4 amendment from ADR-033 §0.7 —
they add the `runtime_mint_intent` marker table and strengthen the hook
gate to consume an intent row inside an atomic CTE. Without 049+050 the
hook would silently rewrite dashboard OTP login JWTs with
`aud=soleur-runtime` and `exp=600s` (10-min auto-logout for end users).
Verify post-apply:

```bash
psql "${DATABASE_URL_POOLER/:6543/:5432}" -c "
  SELECT proname FROM pg_proc
  WHERE proname IN ('runtime_jwt_mint_hook','precheck_jwt_mint')
    AND pronamespace = 'public'::regnamespace;
  SELECT to_regclass('public.runtime_mint_intent') IS NOT NULL AS intent_table_exists;
  SELECT pg_get_functiondef(p.oid) ~ 'v_intent_consumed' AS hook_has_intent_gate
  FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE p.proname = 'runtime_jwt_mint_hook' AND n.nspname = 'public';
"
```

Expect all three:
- two procs (`runtime_jwt_mint_hook` + `precheck_jwt_mint`)
- `intent_table_exists = t`
- `hook_has_intent_gate = t`

**10.c — Register the Custom Access Token Hook via the Mgmt API.**
Operator-acknowledged write (per `hr-menu-option-ack-not-prod-write-auth`).
Mgmt API token MUST be plan-phase-only — do NOT bake into Node runtime.

```bash
PROJECT_REF=$(echo "${SUPABASE_URL}" | sed -E 's|https://([^.]+)\.supabase\.co.*|\1|')
curl -sS -X PATCH "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_MGMT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"hook_custom_access_token_enabled": true, "hook_custom_access_token_uri": "pg-functions://postgres/public/runtime_jwt_mint_hook"}'

# Verify (GET on same endpoint)
curl -sS "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_MGMT_API_TOKEN}" \
  | jq '{hook_custom_access_token_enabled, hook_custom_access_token_uri}'
```

Expected response: `enabled: true`, `uri: "pg-functions://postgres/public/runtime_jwt_mint_hook"`.

**10.d — Auth-config required state.** The Mgmt API exposes these in
`config/auth`; the Terraform provider (as of v1.9.1) does NOT manage
them, so they're documented here for drift detection rather than
codified. Tracked in the rate-limit-empirical-probe follow-up issue.

- `JWT_EXP = 3600` (Supabase default; the hook overrides exp in the
  JWT to honor `mintFounderJwt`'s `ttlSec` — see migration 047)
- `EXTERNAL_EMAIL_ENABLED = true` (required for `generateLink` to
  produce a hashed_token; no email is sent because tenant.ts reads
  `hashed_token` directly server-side)
- `RATE_LIMIT_TOKEN_REFRESH` — Supabase default 10/IP/hour. Not
  Terraform-managed. If founder concurrency at scale trips it, request
  a per-project bump via Supabase support
  (`hr-menu-option-ack-not-prod-write-auth` applies).
- `RATE_LIMIT_EMAIL_SENT` — Supabase default 10/hour. Bypassed by our
  `generateLink` path (no email sent).
- `RATE_LIMIT_VERIFY` — undocumented in public docs; precheck_jwt_mint's
  60/hour/founder is the durable canary.

**10.e — Smoke-test the substrate** (one synthesized fixture):

```bash
# Pick any auth.users row (synthesized fixtures only — cq-test-fixtures-synthesized-only).
# Run one generateLink+verifyOtp cycle; assert the JWT payload has
# {aud: "soleur-runtime", jti: <uuid>, exp-iat: 600}.
# See ADR-033 §0.5 for the reference probe script.
```

**Removed step (#3363 Resolution C cleanup):** prior versions of this
runbook (pre-#3363) instructed pasting `SUPABASE_JWT_SECRET` from the
Dashboard → Settings → API → "JWT Secret" panel into Doppler. **That
step is now retired.** Node no longer holds a signing key; the Hook
(10.c) owns the runtime mint. If the substrate is rolled back, restore
`SUPABASE_JWT_SECRET` in Doppler from the password-manager-archived
copy per the plan's Rollback Runbook.

---

## Post-provisioning

Once Steps 0–10 complete, the tenant's stack is operational. Set the
tenant's row in `knowledge-base/legal/tenant-dpa-register.md` to status
`provisioned`. Schedule the first quarterly token-rotation review per
the offboarding runbook's rotation cadence.

## Token-quarantine discipline (applies to Steps 1, 2, 3)

The hard constraint per ADR-030 is "Soleur never holds a tenant cloud
credential." During Steps 1-3 (Hetzner, Cloudflare, Doppler), the
operator's laptop is a transient quarantine zone between tenant-provider
and tenant-GitHub-repo-secret. To preserve the quarantine:

- **Do NOT `export TOKEN=...`** at any shell level — exported env vars
  leak into every subprocess and persist for the shell session lifetime.
- **Do NOT prefix commands with the token literal**
  (`HCLOUD_TOKEN=xxx hcloud ...`) — `bash` records the entire command
  (token included) in `~/.bash_history`. Use either `read -s TOKEN` (no
  echo, no history) followed by a one-shot subshell
  `( HCLOUD_TOKEN="$TOKEN" hcloud server create ... )`, or pipe the token
  in via `<<<` heredoc into a wrapper script.
- **Do NOT `echo $TOKEN`** at any point — terminal scrollback may persist
  beyond your session.
- **Do NOT paste tokens into Soleur Doppler, Soleur env files, or any
  Soleur-side store en route to Step 6.** The transit path is
  tenant-provider → operator subshell → tenant-GitHub-repo-secret. The
  installation_id in Step 8 is the only token-shaped value that may land
  in Soleur Doppler, because it is an App-mint-context identifier
  (1-hour TTL minting capability bounded by App permissions), not a
  tenant cloud credential.
- After Step 6 stores the token in the tenant's GitHub repo Secrets,
  clear it from the operator subshell with `unset TOKEN` (or just exit
  the subshell) before proceeding.

These rules apply equally to the Hetzner project-scoped API token
(Step 1), the Cloudflare scoped account-API token (Step 2), and the
Doppler Service Account Identity OIDC token / config token (Step 3).

## Abort-mid-provisioning (general)

If Step N fails:

1. **Stop**. Do not attempt to "fix forward" past the failed step.
2. **Run the teardown for Step N first**, then Step N-1, then Step N-2,
   etc. — reverse order — until you reach a steady state.
3. **Update** `knowledge-base/legal/tenant-dpa-register.md` with status
   `aborted-provisioning-at-step-N` and a one-line reason.
4. **File** an issue or learning if the failure surfaces a runbook gap.

## Outstanding deferrals (filed as follow-up issues per Phase 3)

- Automated Hetzner sub-project provisioning skill — re-evaluation trigger: 2nd non-Soleur project.
- Automated Cloudflare provisioning skill — same.
- Automated Doppler project + OIDC identity provisioning skill — same.
- Automated GitHub repo + App install + Environment configuration skill — same.
- Deploy-failure UI surface in Soleur (Art. 13 in-product transparency) — re-evaluation trigger: tenant complaint about lack of in-product visibility.

## References

- Plan: `knowledge-base/project/plans/2026-05-14-feat-soleur-managed-deploy-substrate-v1-scaffolding-plan.md`
- ADR-030: `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- ToS research: `knowledge-base/legal/tos-research/2026-05-14-tenant-account-provisioning-tos-research.md`
- LIA: `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md`
- Prior decision #749: `apps/web-platform/infra/firewall.tf:15` + `apps/web-platform/infra/tunnel.tf:1-4`.
- Hetzner tps-action: `https://github.com/hetznercloud/tps-action`
- Doppler OIDC examples: `https://docs.doppler.com/docs/github-oidc-examples`
- Cloudflare CI/CD: `https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/`
- GitHub Environments: `https://docs.github.com/actions/managing-workflow-runs/reviewing-deployments`
