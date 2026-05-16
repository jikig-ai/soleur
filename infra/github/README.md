# infra/github/ -- GitHub branch-protection Terraform root

Mirrors `apps/web-platform/infra/sentry/` pattern. State key:
`github/terraform.tfstate` in R2 bucket `soleur-terraform-state`.

Managed resource: ruleset 14145388 ("CI Required") on the `main` branch of
`jikig-ai/soleur`. Adopted via `terraform import` (see Phase 2 below).

Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, every change to
the required-status-check set must flow through this root. UI edits will
produce drift on the next `terraform plan` -- reconcile by editing this
config to match live state OR re-applying to restore the configured set.

## Phase 0 -- Doppler setup (one-time)

1. Mint a fine-grained PAT at
   <https://github.com/settings/personal-access-tokens/new>:
   - Resource owner: `jikig-ai`
   - Repository access: select `jikig-ai/soleur` ONLY
   - Permissions: `Administration: Read+Write` (Metadata: Read auto-granted)
   - Expiration: 90 days
   - Name: `terraform-infra-github-rulesets`

2. Stash in Doppler `prd_terraform`:

   ```bash
   doppler secrets set GH_RULESET_PAT='<token>' -p soleur -c prd_terraform
   ```

3. Verify:

   ```bash
   GH_TOKEN=$(doppler secrets get GH_RULESET_PAT -p soleur -c prd_terraform --plain) \
     gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.id'
   # Expected: 14145388
   ```

## Phase 1 -- Init

```bash
cd infra/github/

# R2 backend creds must be RAW (NOT tf-var-transformed -- the TF_VAR_aws_*
# shape silently fails to authenticate the S3 backend). Canonical triplet per
# knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md.
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

terraform init -input=false
```

## Phase 2 -- Import + plan + apply (one-time bootstrap)

Capture the import oracle FIRST so the plan-diff probe in step 3 has a
deterministic reference:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 > /tmp/ruleset-live-pre-import.json
```

Import the existing ruleset. The `github_repository_ruleset` import address
is `<repo>:<id>` (the owner comes from the provider block):

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.ci_required soleur:14145388
```

Plan and verify the diff is exactly the 9 additions:

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -out=tfplan.binary

terraform show -json tfplan.binary | jq '
  .resource_changes[]
  | select(.address == "github_repository_ruleset.ci_required")
  | .change.after.rules[0].required_status_checks[0].required_check
  | length
'
# Expected: 14 (5 pre-existing + 9 new)
```

If the diff includes anything beyond the 9 `required_check` additions
(re-ordering, condition tweaks, bypass-actor changes), **STOP** and
reconcile this config to match live state before applying. See ADR-032
Risks R6 / R7 for the provider rough edges that can surface here.

Apply (operator-attested per `hr-menu-option-ack-not-prod-write-auth`):

```bash
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply tfplan.binary
```

## Phase 3 -- Verify post-apply

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq '.rules[0].parameters.required_status_checks | length'
# Expected: 14
```

Spot-check the 9 new contexts are present:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq -r '.rules[0].parameters.required_status_checks[].context' \
  | sort
```

## Phase 4 -- Rotation (every 90 days)

1. Mint new PAT (same scope as Phase 0).
2. `doppler secrets set GH_RULESET_PAT='<new-token>' -p soleur -c prd_terraform`
3. Revoke old PAT at <https://github.com/settings/personal-access-tokens>.

Calendar reminder: schedule for +75 days from mint to leave a 15-day window.

## Phase 5 -- Rollback

If a Terraform apply broke the ruleset:

1. List prior state versions in R2:

   ```bash
   aws --endpoint-url=https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com \
     s3api list-object-versions --bucket soleur-terraform-state \
     --prefix github/terraform.tfstate
   ```

2. Restore the prior version (operator-attested):

   ```bash
   aws --endpoint-url=https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com \
     s3api copy-object \
     --copy-source soleur-terraform-state/github/terraform.tfstate?versionId=<prev> \
     --bucket soleur-terraform-state --key github/terraform.tfstate
   ```

3. `terraform apply -refresh-only` to sync R2-restored state to the GitHub API.

For catastrophic ruleset corruption: emergency fallback is the GitHub UI at
<https://github.com/jikig-ai/soleur/rules/14145388> -- operator can manually
restore the 5 baseline checks; then re-import from clean state via Phase 2.
