---
title: "Tenant provisioning skills — Terraform-first automation of runbook Steps 1-4+7"
date: 2026-05-26
type: feat
issues: [3769, 3770, 3771, 3772]
parent_issue: 3723
deferred_issues: [3773, 4507]
brainstorm: knowledge-base/project/brainstorms/2026-05-26-tenant-provisioning-skills-brainstorm.md
spec: knowledge-base/project/specs/feat-tenant-provisioning-skills/spec.md
adr: knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md
runbook: knowledge-base/engineering/operations/runbooks/tenant-provisioning.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
pr: 4501
review_revision: v2 (5-agent panel applied 6 P0 + 16 P1 fixes)
---

# Plan: Tenant provisioning skills — Terraform-first automation (v2)

## Overview

Build 4 Soleur skills automating the tenant provisioning runbook Steps 1-4+7. Each skill generates a per-tenant Terraform provisioning root where TF resources exist, falling back to guided CLI/API where they don't. Build order: Doppler → Cloudflare → Hetzner → GitHub.

**Trigger:** N=2 re-evaluation — operator starting 2nd non-Soleur project.

## User-Brand Impact

**If this lands broken, the user experiences:** A tenant's cloud credentials (Hetzner API token, Cloudflare scoped token, Doppler OIDC identity) provisioned with wrong scope, leaked to shell history, or persisted on Soleur infrastructure — enabling unauthorized access to the tenant's production deploy pipeline.

**If this leaks, the user's credentials are exposed via:** Token leaked to MCP parameter logs, env export surviving session, CLI arg in bash history, or TF state stored outside the per-tenant R2 backend.

**Brand-survival threshold:** single-user incident. Inherited from brainstorm Phase 0.1 (CPO + CLO + CTO triad sign-off).

## Research Insights

### Terraform Resource Availability (verified 2026-05-26)

| Provider | Operation | TF Resource | Provider Version |
|---|---|---|---|
| Cloudflare | `cloudflare_api_token` | YES | `cloudflare/cloudflare ~> 4.0` (existing) |
| Doppler | `doppler_project` + `doppler_config` | YES | `DopplerHQ/doppler ~> 1.21` (existing) |
| Doppler | OIDC service-account-identity | NO | Doppler API `POST /v3/workplace/service_accounts` only — no CLI subcommand, no TF resource |
| Hetzner | Project creation + token minting | NO | Console-only |
| GitHub | `github_repository` + `github_repository_environment` | YES | `integrations/github ~> 6.0` (exists in `main.tf:42-44`) |
| GitHub | App install | NO | Human consent per ToS B.3 |

### Credential Handoff Pattern (review P0-4 fix)

Skills emit `terraform apply` for the operator — they do NOT execute TF directly (per `hr-all-infrastructure-provisioning-servers`). Bootstrap credentials reach the emitted `terraform apply` via a copy-pasteable compound command:

```bash
read -rs -p "Bootstrap token: " TF_VAR_<provider>_bootstrap_token && \
  export TF_VAR_<provider>_bootstrap_token && \
  terraform apply && \
  unset TF_VAR_<provider>_bootstrap_token
```

The token is re-entered at apply time (not carried from the skill's `read -s`). This avoids long-lived env exports and keeps the quarantine discipline intact.

### DPA Gate Pattern (review P0-6 fix)

All 4 skills share this gate (inline in each script, not a shared file):

```bash
DPA_FILE="knowledge-base/legal/tenant-dpa-register.md"
[[ -f "$DPA_FILE" ]] || { echo "DPA register not found at $DPA_FILE. Run from Soleur monorepo root." >&2; exit 3; }
awk -F'|' -v slug="$SLUG" '/^\|/ && $2 ~ slug && $7 ~ /dpa-signed|provisioning-in-progress/' "$DPA_FILE" | grep -q . \
  || { echo "No active DPA row for '$SLUG'. Sign DPA (Step 0) first." >&2; exit 3; }
```

## Open Code-Review Overlap

None.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carried forward from brainstorm 2026-05-26)

### Product (CPO) — carry-forward
**Status:** reviewed
**Assessment:** N=2 trigger valid. Operator overrode CPO recommendation to defer #3772. Automation is a correctness play for token-quarantine discipline.

### Legal (CLO) — carry-forward
**Status:** reviewed
**Assessment:** No new legal risk. Three gaps tracked as #4502 (separate PR): ToS/LIA/PA-10 amendments.

### Engineering (CTO) — carry-forward
**Status:** reviewed
**Assessment:** Shared conventions inline, not shared framework. `--dry-run` per skill. No orchestration.

## Implementation Phases

### Phase 0: Shared Setup

**Goal:** Prepare the repo for provisioning skill output.

**Files to edit:**

| File | Change |
|---|---|
| `.gitignore` | Add `provisioning/` entry — TF configs, `.terraform/`, and `.tfstate` must not be committed |

**Output directory:** `provisioning/<slug>/` at the Soleur monorepo root (gitignored). Each skill generates `.tf` files here. The 6-line R2 backend block is inlined per skill — no shared template (premature at N=2).

**Per `hr-every-new-terraform-root-must-include-an`:** Each generated TF root includes R2 remote backend at key `tenants/<slug>/provisioning.tfstate`. Deviation from `<app-name>/terraform.tfstate` pattern is justified: per-tenant isolation via key path.

**Per `hr-tf-variable-no-operator-mint-default`:** Bootstrap tokens (`doppler_bootstrap_token`, `cf_bootstrap_token`, `github_token`) are operator-minted by nature — bootstrapping requires tokens that create resources that will later generate scoped tokens. Justified exception.

### Phase 1: #3771 — `provision-doppler` skill (Closes #3771)

**Goal:** Create Doppler project + config via Terraform, configure OIDC service-account-identity via Doppler API.

**Files to create:**

| File | Purpose |
|---|---|
| `plugins/soleur/skills/provision-doppler/SKILL.md` | Skill definition |
| `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh` | Main script |

**SKILL.md description (12 words):**
`"This skill should be used when provisioning Doppler projects and OIDC identities for tenants."`

**Script flow:**
1. Parse args: `<tenant-slug>`, `<tenant-org>`, `<tenant-repo>`, `--dry-run`
2. Pre-checks: `doppler --version`, `curl --version`, DPA gate, slug validation
3. **Idempotency check:** `doppler projects | grep -q "$SLUG"` — if project exists, warn and offer to skip TF or abort
4. Accept bootstrap Doppler token: `read -rs -p "Doppler personal token: " DOPPLER_TOKEN`
5. Generate `provisioning/<slug>/doppler.tf` (inline backend block + `doppler_project` + `doppler_config`)
6. `--dry-run`: print generated TF, print copy-pasteable apply command, print OIDC API curl, exit 0
7. Operator ack → emit copy-pasteable compound command:
   ```
   read -rs -p "Doppler token: " TF_VAR_doppler_bootstrap_token && \
     export TF_VAR_doppler_bootstrap_token && \
     cd provisioning/<slug> && terraform init && terraform apply && \
     unset TF_VAR_doppler_bootstrap_token
   ```
8. **Operator gate:** `read -p "TF apply complete? Type 'yes': " ACK; [[ "$ACK" == "yes" ]]`
9. **Verify TF apply:** `doppler projects get "$SLUG" --plain` — if missing, abort with "TF apply may not have completed"
10. Configure OIDC service-account-identity via Doppler API in subshell:
    ```bash
    (
      export DOPPLER_TOKEN
      curl -sS -X POST "https://api.doppler.com/v3/workplace/service_accounts" \
        -H "Authorization: Bearer $DOPPLER_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "'"$SLUG"'-deploy", "workplace_role": {"identifier": "viewer"}}'
      # Then configure OIDC trust with two-claim binding via API
    )
    unset DOPPLER_TOKEN
    ```
11. **Smoke-test:** Verify service account exists via API. Print warning: "OIDC trust binding cannot be fully verified locally — test via deploy workflow (Step 9) after all provisioning."
12. Print teardown commands (always, not just on success): `doppler projects delete "$SLUG"`, revoke service account
13. Print: "**Bootstrap cleanup:** Revoke the Doppler personal token used for bootstrapping — it is no longer needed."
14. Print next-step hint: "Run `soleur:provision-cloudflare <slug> <zone-id> <account-id>` next."

**On failure:** Trap handler prints which resources were created and their teardown commands.

### Phase 2: #3770 — `provision-cloudflare` skill (Closes #3770)

**Goal:** Create scoped Cloudflare API token via Terraform `cloudflare_api_token`.

**Files to create:**

| File | Purpose |
|---|---|
| `plugins/soleur/skills/provision-cloudflare/SKILL.md` | Skill definition |
| `plugins/soleur/skills/provision-cloudflare/scripts/provision-cloudflare.sh` | Main script |

**SKILL.md description (12 words):**
`"This skill should be used when provisioning scoped Cloudflare API tokens for tenant deploys."`

**Script flow:**
1. Parse args: `<tenant-slug>`, `<cf-zone-id>`, `<cf-account-id>`, `--dry-run`
2. Pre-checks: `curl --version`, DPA gate, format validation
3. **Idempotency check:** warn if `provisioning/<slug>/cloudflare.tf` already exists
4. Accept bootstrap CF token: `read -rs -p "Cloudflare API token: " CF_API_TOKEN`
5. Generate `provisioning/<slug>/cloudflare.tf` (inline backend + `cloudflare_api_token` with 4 permission groups + TF output block with `sensitive = true`)
6. `--dry-run`: print generated TF, print copy-pasteable apply command, print smoke-test commands, exit 0
7. Operator ack → emit compound apply command (same pattern as Doppler)
8. **Operator gate:** `read -p "TF apply complete? Type 'yes': " ACK`
9. **Token extraction + smoke-test** in one pipeline (no terminal scrollback):
   ```bash
   cd provisioning/<slug> && terraform output -raw cf_deploy_token | (
     read -r TOKEN
     curl -sS -H "Authorization: Bearer $TOKEN" \
       https://api.cloudflare.com/client/v4/user/tokens/verify | jq .result.status
   )
   ```
   Fallback if `wrangler` installed: `terraform output -raw cf_deploy_token | (read -r T; CLOUDFLARE_API_TOKEN="$T" wrangler whoami)`
10. Print teardown commands + bootstrap revocation reminder
11. Print next-step hint: "Run `soleur:provision-hetzner <slug>` next."

### Phase 3: #3769 — `provision-hetzner` skill (Closes #3769)

**Goal:** Guide operator through Console project creation, accept token, run write-class smoke-test.

**Files to create:**

| File | Purpose |
|---|---|
| `plugins/soleur/skills/provision-hetzner/SKILL.md` | Skill definition |
| `plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh` | Main script |

**SKILL.md description (13 words):**
`"This skill should be used when provisioning Hetzner sub-projects and tokens for tenant infrastructure."`

**Script flow (guided + verify):**
1. Parse args: `<tenant-slug>`, `--dry-run`
2. Pre-checks: `hcloud version`, DPA gate, slug validation
3. Display guided instructions (Console project creation + token minting)
4. Accept token: `read -rs -p "Hetzner project-scoped API token: " HCLOUD_TOKEN`
5. `--dry-run`: print smoke-test commands, exit 0
6. Write-class smoke-test in subshell **with trap handler:**
   ```bash
   PROBE_NAME="probe-provision-${SLUG}"
   (
     export HCLOUD_TOKEN
     trap 'hcloud server delete "$PROBE_NAME" 2>/dev/null' EXIT INT TERM
     hcloud server create --name "$PROBE_NAME" --type cx11 --image ubuntu-22.04 --location nbg1
     hcloud server delete "$PROBE_NAME"
   )
   unset HCLOUD_TOKEN
   ```
   Deterministic name (`probe-provision-<slug>`) so orphans are findable. Aligned to runbook's cx11.
7. On failure: distinct messages for create-fail (scope issue) vs delete-fail (orphan — print `hcloud server delete <name>`)
8. Print teardown + revocation reminder
9. Print next-step hint: "Run `soleur:provision-github <slug> <org> <reviewers>` next."

### Phase 4: #3772 — `provision-github` skill (Closes #3772)

**Goal:** Create repo + Environment via Terraform, drive App install to consent screen.

**Files to create:**

| File | Purpose |
|---|---|
| `plugins/soleur/skills/provision-github/SKILL.md` | Skill definition |
| `plugins/soleur/skills/provision-github/scripts/provision-github.sh` | Main script |

**SKILL.md description (12 words):**
`"This skill should be used when provisioning GitHub repos and environments for tenant workflows."`

**Script flow:**
1. Parse args: `<tenant-slug>`, `<tenant-org>`, `<reviewer-github-username>`, `--dry-run`
2. Pre-checks: `gh auth status`, `terraform --version`, DPA gate, slug/org validation
3. **Idempotency check:** `gh repo view <org>/<slug>` — if exists, warn and offer to skip
4. **Resolve org-id:** `ORG_ID=$(gh api /orgs/<tenant-org> --jq .id)` for the install URL
5. Generate `provisioning/<slug>/github.tf`:
   ```hcl
   provider "github" {
     owner = var.tenant_org
     token = var.github_token  # GitHub PAT with repo + admin:org scope
   }
   resource "github_repository" "tenant" { ... }
   resource "github_repository_environment" "production" { ... }
   resource "github_repository_environment_deployment_policy" "main_only" {
     repository     = github_repository.tenant.name
     environment    = github_repository_environment.production.environment
     branch_pattern = "main"
   }
   ```
   Reviewers: if `<reviewer-github-username>` provided, add `reviewers { users = [data.github_user.<reviewer>.id] }` block
6. `--dry-run`: print TF plan + install URL, exit 0
7. Operator ack → emit compound apply command (with `TF_VAR_github_token`)
8. **Operator gate:** `read -p "TF apply complete? Type 'yes': "`
9. **Human consent gate (TR8):**
   ```
   Install app/soleur on <org>/<slug>:
   https://github.com/apps/soleur/installations/new/permissions?target_id=<org-id>
   ```
   `read -p "App installed? Type 'yes': " ACK`
10. Verify: `gh api /repos/<org>/<slug>/installation` — check permissions
11. Print teardown + bypass_actors sweep reminder + bootstrap revocation
12. Print: "All provisioning complete. Run runbook Steps 5-10 manually."

### Phase 5: Runbook Update

**Files to edit:**

| File | Change |
|---|---|
| `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md` | Add skill references to Steps 1-4+7 |

### Phase 6: REMOVED — Legal Amendments (tracked as #4502)

Legal amendments (ToS research delta, PA-10 amendment, LIA delta) are documentation-only changes with different review scope. Tracked as #4507 to avoid mixing code + legal review.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `provision-doppler --dry-run` prints correct TF plan + Doppler API curl commands for OIDC
- [x] AC2: `provision-cloudflare --dry-run` prints TF plan without `User Details:Read` + smoke-test pipeline
- [x] AC3: `provision-hetzner --dry-run` prints Console guidance + smoke-test with trap handler
- [x] AC4: `provision-github --dry-run` prints TF plan with `token` auth block + install URL with numeric org-id
- [x] AC5: All 4 skills enforce DPA gate with `test -f` + status-column validation (not raw substring grep)
- [x] AC6: All 4 skills use credential quarantine: `read -s` + subshell + `unset`. Emitted TF commands use the re-entry pattern.
- [x] AC7: All 4 SKILL.md files include Art. 32 pre-condition
- [x] AC8: All 4 skills print teardown commands on ANY non-zero exit (not just success)
- [x] AC9: All 4 skills have idempotency pre-checks (warn if resources already exist)
- [x] AC10: `bun test plugins/soleur/test/components.test.ts` passes (actual: 1950/1950)
- [x] AC11: Runbook Steps 1-4+7 reference the corresponding skill
- [x] AC12: `.gitignore` includes `provisioning/` entry
- [x] AC13: Hetzner probe uses deterministic name + trap handler

### Post-merge (operator)

- [ ] AC14: Verify Doppler DPA status. Automation: `doppler configure get token --plain` (Ref #4502)
- [ ] AC15: Verify GitHub DPA status. Automation: check GitHub Settings (Ref #4502)
- [ ] AC16: Run each skill with `--dry-run` against real tenant slug to validate flow

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **TF state contains sensitive tokens in plaintext** | High | R2 backend is encrypted + Soleur-scoped credentials. Post-apply: once token is stored in tenant's GitHub secrets, consider `terraform state rm` of the sensitive resource. Per-tenant R2 access isolation deferred to N=3 re-eval (ADR-030 amendment candidate). |
| Hetzner probe server orphaned on failure | Medium | Trap handler + deterministic name. Teardown printed on failure. |
| CF provider v4→v5 breaking changes | Medium | Pin `~> 4.0`; upgrade when Soleur's main root upgrades |
| Skill run in CI violates ADR-030 | High | Art. 32 pre-condition + `read -s` blocks non-interactive shells |
| Re-run creates duplicate resources | Medium | Idempotency pre-checks warn before proceeding |
| R2 backend has no state locking | Low | Single operator at N=2. Document in each SKILL.md Sharp Edges. |

## Sharp Edges

- Skills emit `terraform apply` — they do NOT invoke TF directly. Per `hr-all-infrastructure-provisioning-servers`, infra apply stays operator-initiated.
- The `provisioning/<slug>/` directory is at the monorepo root, gitignored. Write-once artifacts, not living infrastructure. Provider versions are pinned hard.
- Doppler OIDC service-account-identity uses the Doppler API (`POST /v3/workplace/service_accounts`), NOT a CLI subcommand (none exists) and NOT a TF resource (none exists).
- GitHub TF provider requires explicit `token` auth — does NOT inherit from `gh` CLI. The existing `apps/web-platform/infra/main.tf:42-44` uses `app_auth {}` but provisioning uses a PAT.
- OIDC trust binding cannot be fully smoke-tested locally. Verification requires a GitHub Actions workflow presenting the correct OIDC claims (runbook Step 9).
- Next-step hints follow build order (Doppler→CF→Hetzner→GitHub), which differs from runbook step order (Step 1→2→3→4). Teardown on failure lists what THIS skill provisioned, not the full reverse chain.
- Description budget after this PR: ~1943/1950 (7 words headroom).
- CPO sign-off via brainstorm carry-forward (2026-05-26). `user-impact-reviewer` runs at PR review time.

## Infrastructure (IaC)

### Terraform changes

Each skill generates `.tf` files into `provisioning/<slug>/` at the monorepo root (gitignored). No changes to `apps/web-platform/infra/`.

Providers in provisioning root:
- `cloudflare/cloudflare ~> 4.0`
- `DopplerHQ/doppler ~> 1.21`
- `integrations/github ~> 6.0`

Sensitive variables (re-entered at apply time, never in `.tf` files):
- `TF_VAR_doppler_bootstrap_token`
- `TF_VAR_cf_bootstrap_token`
- `TF_VAR_github_token`

### Apply path

Operator-initiated. Skills emit copy-pasteable compound commands that include credential re-entry via `read -s`.

### Distinctness / drift safeguards

- Per-tenant isolation via R2 key path (`tenants/<slug>/provisioning.tfstate`).
- No `lifecycle.ignore_changes` — create-once resources.
- `required_version = ">= 1.5"` in each generated root.

## Observability

N/A — operator-local CLI skills. Exit codes (0=success, 1=error) are the observability surface. Each skill prints what was created and teardown commands on every exit.
