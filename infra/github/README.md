# infra/github/ -- GitHub branch-protection Terraform root

Mirrors `apps/web-platform/infra/sentry/` pattern. State key:
`github/terraform.tfstate` in R2 bucket `soleur-terraform-state`.

Managed resource: ruleset 14145388 ("CI Required") on the `main` branch of
`jikig-ai/soleur`. Adopted via `terraform import` (idempotent, runs in CI on
first apply — see Phase 1 below).

Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, every change to
the required-status-check set must flow through this root. UI edits will
produce drift on the next `terraform plan` -- reconcile by editing this
config to match live state OR re-applying to restore the configured set.

## Authorization model: apply-on-merge

Apply runs **automatically in CI** when a PR touching `infra/github/*.tf`
merges to `main` -- see `.github/workflows/apply-github-infra.yml`. The PR
merge IS the human authorization (`hr-menu-option-ack-not-prod-write-auth`),
mirroring the ADR-031 boundary for `apps/web-platform/infra/sentry/`.

CODEOWNERS (`/.github/CODEOWNERS`) pins `/infra/github/` to `@deruelle` — a
PR cannot merge without code-owner review, so a leaked `DOPPLER_TOKEN` alone
is insufficient to push a ruleset change to production.

Kill switch: include `[skip-github-apply]` on its own line in the merge
commit message to skip the auto-apply for that merge. Destructive plans
(any `delete` action) additionally require `[ack-destroy]` in the merge
commit message, or the apply fails closed.

Manual escape hatch: `gh workflow run apply-github-infra.yml -f reason='...'`
for the first apply post-Phase-0 (when no `infra/github/*.tf` files have
changed yet) or for re-runs after a transient failure.

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

## Phase 1 -- First apply (one-time, post-Phase-0)

After Phase 0 lands the PAT in Doppler, kick the first apply via the manual
escape hatch (no `infra/github/*.tf` files have changed yet, so the path-filter
push trigger will not fire):

```bash
gh workflow run apply-github-infra.yml \
  -f reason='first-apply-post-PAT-mint'
gh run watch
```

The workflow performs:

1. `terraform init -lockfile=readonly`.
2. **Idempotent import**: if the resource is not in state, runs
   `terraform import github_repository_ruleset.ci_required soleur:14145388`.
   On subsequent applies, this step is a no-op.
3. `terraform plan -out=tfplan` with destroy-guard (`[ack-destroy]` required
   in commit message for any `delete` action).
4. `terraform apply tfplan` (auto-approved — PR merge is the human
   authorization).
5. **Post-apply verify**: `gh api .../rulesets/14145388` count probe,
   recorded in the workflow run summary.

If you want to reproduce the local-terminal Phase 2 plan-diff probe before
the first apply (sanity check that the diff is exactly the 9 additions),
the canonical sequence is:

```bash
cd infra/github/
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform import github_repository_ruleset.ci_required soleur:14145388
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan
# Expected: 9 required_check additions, no destroys.
```

(This is read-only against R2 state once import runs — apply still belongs in CI.)

## Phase 2 -- Subsequent applies (auto-on-merge)

Open a PR that edits `infra/github/*.tf` (e.g. adding a new required check
to `ruleset-ci-required.tf`). On merge to `main`, the `apply-github-infra`
workflow:

- Re-runs init + plan in CI.
- Aborts with `[ack-destroy]` guidance if the plan removes any required check
  without explicit acknowledgement in the commit message.
- Applies the change (PR merge is the human authorization per ADR-031).
- Records the post-apply ruleset count in the workflow run summary.

No terminal-side `terraform apply` is required for any normal flow.

## Phase 3 -- Manual verification (optional / debug)

The auto-apply workflow already runs a count probe and writes it to the run
summary. If you want to manually re-verify the live state:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  | jq '.rules[0].parameters.required_status_checks | length'
# Expected: matches the current ruleset-ci-required.tf set
```

Spot-check the active contexts:

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

3. Apply the restored state with operator attestation (`apply` — NOT
   `apply -refresh-only`; the latter pulls state FROM the API and would
   reconcile the rollback away):

   ```bash
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform plan -out=tfplan-rollback.binary
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform apply tfplan-rollback.binary
   ```

For catastrophic ruleset corruption: emergency fallback is the GitHub UI at
<https://github.com/jikig-ai/soleur/rules/14145388> -- operator can manually
restore the 5 baseline checks; then re-import from clean state via Phase 2.
