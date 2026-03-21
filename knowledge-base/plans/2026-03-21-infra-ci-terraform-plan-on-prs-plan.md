---
title: "infra: add CI terraform plan on PRs"
type: feat
date: 2026-03-21
semver: patch
---

# infra: Add CI Terraform Plan on PRs

## Overview

Add a `terraform-plan` job to the existing `infra-validation.yml` workflow that runs `terraform plan` on PRs touching `apps/*/infra/**` and posts the plan output as a sticky PR comment. Uses Doppler-first credential injection via `DopplerHQ/cli-action` with a single `DOPPLER_TOKEN` GitHub Secret as bootstrap. Gracefully skips when secrets are unavailable (fork/Dependabot PRs).

## Problem Statement

The R2 remote backend is now live (#973) and Doppler is integrated with Terraform (#970), but there is no CI validation that `terraform plan` succeeds. The existing `infra-validation.yml` runs only offline checks (`terraform fmt -check`, `terraform validate -backend=false`). A developer can merge TF changes that pass formatting and syntax checks but produce plan errors against real state -- for example, referencing a resource that was deleted, or introducing a variable mismatch.

## Proposed Solution

Extend `infra-validation.yml` with a new `plan` job that runs after the existing `validate` job. The plan job:

1. Installs the Doppler CLI via `DopplerHQ/cli-action`
2. Uses `doppler run --project soleur --config prd_terraform --name-transformer tf-var` to inject credentials
3. Runs `terraform init` (with real R2 backend) then `terraform plan -no-color`
4. Posts the plan output as a sticky PR comment using `marocchino/sticky-pull-request-comment`
5. Truncates output for large plans (GitHub comment limit is 65536 chars)

### Credential Strategy: Doppler-First

Per the brainstorm decision (2026-03-21), the approach uses a single `DOPPLER_TOKEN` GitHub Secret that bootstraps all other secrets via Doppler at runtime. This eliminates split-brain between GitHub Secrets and Doppler.

**Required GitHub Secrets:**
- `DOPPLER_TOKEN` -- a Doppler service token scoped to `soleur` project, `prd_terraform` config

**Injected by Doppler at runtime:**
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` -- R2 S3-compatible credentials for the backend
- `TF_VAR_hcloud_token`, `TF_VAR_cf_api_token`, etc. -- via `--name-transformer tf-var`

**Critical learning (from #973 session error #4):** The `--name-transformer tf-var` converts ALL keys to `TF_VAR_*` format, including `AWS_ACCESS_KEY_ID`. The S3 backend reads these as plain env vars, not `TF_VAR_*`. The Doppler CLI action must inject credentials in two steps:
1. First pass: inject `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as plain env vars (for `terraform init` backend)
2. Second pass: inject all secrets with `--name-transformer tf-var` (for `terraform plan` variables)

Alternatively, set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` explicitly via `doppler secrets get` before the `tf-var` run.

### Fork/Dependabot PR Handling

Secrets are unavailable on fork PRs and Dependabot PRs (unless the repo has explicitly allowed it). The plan job must:

1. Check if `DOPPLER_TOKEN` is set via a conditional: `if: secrets.DOPPLER_TOKEN != ''` is not valid in GitHub Actions (secrets cannot be used in `if` conditions directly)
2. Instead, use a preceding step that sets an output flag: `echo "has_token=${{ secrets.DOPPLER_TOKEN != '' }}" >> $GITHUB_OUTPUT`
3. Gate the plan job on this output
4. When skipped, post a PR comment: "Terraform plan skipped (secrets unavailable -- fork or Dependabot PR)"

### Concurrency

Per existing conventions, use `cancel-in-progress: false` to ensure plans are not cancelled mid-execution (which could leave stale comments):

```yaml
concurrency:
  group: terraform-plan-<pr-number>-<directory>
  cancel-in-progress: false
```

The concurrency group includes the directory to allow parallel plans across different stacks.

### Sticky PR Comment

Use `marocchino/sticky-pull-request-comment` (SHA-pinned) to update a single comment per stack per PR rather than creating new comments on each push. The comment header identifies the stack:

```
### Terraform Plan: <directory>
```

Output truncation: if plan output exceeds 60000 chars, truncate with a message indicating the plan was too large.

## Technical Considerations

### Dependency on #978 (Doppler Key Alignment)

Issue #978 documents that several Doppler keys in `prd_terraform` config don't align with the `tf-var` transformer output. Specifically:
- `CLOUDFLARE_ACCOUNT_ID` produces `TF_VAR_cloudflare_account_id` but TF expects `TF_VAR_cf_account_id`
- `CLOUDFLARE_API_TOKEN` produces `TF_VAR_cloudflare_api_token` but TF expects `TF_VAR_cf_api_token`
- `ADMIN_IPS` and `DOPPLER_TOKEN` may be missing from `prd_terraform`

**This must be resolved before the CI plan workflow can succeed.** The workflow can be merged first (it will show plan failures as PR comments), but clean operation requires #978 to be resolved. The plan should document this dependency clearly.

### S3 Backend Credential Separation

The R2 backend needs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as plain environment variables. The `--name-transformer tf-var` would convert these to `TF_VAR_aws_access_key_id` which the S3 backend ignores.

**Recommended approach:** Use two separate `doppler run` invocations:

```bash
# Step 1: Extract backend credentials as plain env vars
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain --project soleur --config prd_terraform)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain --project soleur --config prd_terraform)

# Step 2: Run terraform with tf-var transformer for TF variables
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- terraform plan -no-color
```

This is the same workaround discovered during #973 (learning session error #4).

### Matrix Strategy for Multiple Stacks

Reuse the existing `detect-changes` job's directory matrix. The plan job runs per-directory, same as the validate job. This means a PR touching both `apps/telegram-bridge/infra/` and `apps/web-platform/infra/` gets two separate plan outputs, each as its own sticky comment.

### SHA-Pinned Actions

Per existing conventions, all action references must be SHA-pinned with version comments:

- `actions/checkout` -- use existing pin `34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
- `hashicorp/setup-terraform` -- use existing pin `5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85` (v4.0.0)
- `DopplerHQ/cli-action` -- look up latest SHA on GitHub
- `marocchino/sticky-pull-request-comment` -- look up latest SHA on GitHub

### Security Comment Header

Per constitution.md convention, include a security header:

```yaml
# Security: DOPPLER_TOKEN from repository secrets injects Terraform credentials.
# All Doppler secrets are scoped to prd_terraform config (read-only from CI perspective).
# Fork PRs cannot access secrets — workflow gracefully skips plan step.
# All action references are SHA-pinned.
```

### Permissions

The plan job needs:
- `contents: read` -- checkout code
- `pull-requests: write` -- post PR comment

The existing `infra-validation.yml` only has `contents: read`. The permissions block must be updated at the workflow level or the plan job must declare its own permissions.

### Timeout

Per constitution.md: "GitHub Actions workflows invoking LLM agents must set `timeout-minutes`". This applies generally -- set `timeout-minutes: 10` on the plan job (terraform plan should complete in under 2 minutes per stack).

## Non-Goals

- Adding `terraform apply` automation (remains manual)
- Adding pre-commit hooks for terraform (Lefthook integration deferred)
- Resolving Doppler key naming (#978) -- that is a separate issue
- Adding plan approval gating (plan failures are informational, not blocking)
- Supporting `terraform plan` for stacks not under `apps/*/infra/`

## Acceptance Criteria

- [ ] `infra-validation.yml` has a `plan` job that runs `terraform plan` against real R2 backend state
- [ ] Plan job uses `DOPPLER_TOKEN` GitHub Secret and `DopplerHQ/cli-action` for credential injection
- [ ] Plan output is posted as a sticky PR comment per stack, identified by directory name
- [ ] Large plan output (>60000 chars) is truncated with a warning message
- [ ] Fork/Dependabot PRs where secrets are unavailable skip the plan job gracefully with a comment
- [ ] Concurrency group prevents parallel plan runs per PR per directory, with `cancel-in-progress: false`
- [ ] All action references are SHA-pinned per existing conventions
- [ ] `timeout-minutes` is set on the plan job
- [ ] Security comment header documents input trust boundaries
- [ ] Workflow permissions include `pull-requests: write`

## Test Scenarios

- Given a PR that modifies `apps/web-platform/infra/variables.tf`, when the workflow triggers, then `terraform plan` runs for `apps/web-platform/infra/` and posts the plan output as a sticky PR comment
- Given a PR that modifies both `apps/web-platform/infra/` and `apps/telegram-bridge/infra/`, when the workflow triggers, then two separate sticky comments appear (one per stack)
- Given a fork PR where `DOPPLER_TOKEN` is unavailable, when the workflow triggers, then the plan step is skipped and a comment indicates secrets were unavailable
- Given a plan output exceeding 60000 characters, when posted as a comment, then the output is truncated with a "Plan output truncated" warning
- Given a subsequent push to the same PR, when the workflow runs again, then the existing sticky comment is updated (not duplicated)
- Given #978 is unresolved (Doppler key mismatch), when the plan runs, then the plan failure is captured and posted as a comment (not a silent workflow failure)
- Given the `detect-changes` job finds no changed infra directories, when the workflow runs, then the plan job is skipped entirely

## Affected Files

### `.github/workflows/infra-validation.yml`

The primary file to modify. Changes:

1. Add `permissions: pull-requests: write` (or use job-level permissions)
2. Add `check-secrets` job to detect `DOPPLER_TOKEN` availability
3. Add `plan` job after `validate`, gated on `check-secrets` output and `detect-changes` matrix
4. Plan job steps: checkout, setup-terraform, setup-doppler-cli, extract-backend-creds, terraform-init, terraform-plan, post-comment

### No new files

All changes fit within the existing workflow file. No new scripts, actions, or configuration files needed.

## MVP

### `.github/workflows/infra-validation.yml` (plan job addition)

```yaml
  check-secrets:
    runs-on: ubuntu-24.04
    outputs:
      has-doppler-token: <steps.check.outputs.has_token>
    steps:
      - name: Check DOPPLER_TOKEN availability
        id: check
        run: |
          if [[ -n "<DOPPLER_TOKEN_SECRET>" ]]; then
            printf 'has_token=true\n' >> "$GITHUB_OUTPUT"
          else
            printf 'has_token=false\n' >> "$GITHUB_OUTPUT"
          fi
        env:
          DOPPLER_TOKEN_SECRET_CHECK: <DOPPLER_TOKEN_SECRET>

  plan:
    needs: [detect-changes, validate, check-secrets]
    if: |
      needs.detect-changes.outputs.directories != '[]' &&
      needs.check-secrets.outputs.has-doppler-token == 'true'
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    permissions:
      contents: read
      pull-requests: write
    strategy:
      matrix:
        directory: <fromJSON(needs.detect-changes.outputs.directories)>
      fail-fast: false
    concurrency:
      group: terraform-plan-<github.event.number>-<matrix.directory>
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@<sha> # v4.3.1

      - uses: hashicorp/setup-terraform@<sha> # v4.0.0
        with:
          terraform_version: "1.10.5"

      - name: Install Doppler CLI
        uses: DopplerHQ/cli-action@<sha>

      - name: Extract backend credentials
        run: |
          echo "AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain)" >> "$GITHUB_ENV"
          echo "AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)" >> "$GITHUB_ENV"
        env:
          DOPPLER_TOKEN: <DOPPLER_TOKEN_SECRET>
          DOPPLER_PROJECT: soleur
          DOPPLER_CONFIG: prd_terraform

      - name: Terraform init
        run: terraform init -input=false
        working-directory: <matrix.directory>

      - name: Terraform plan
        id: plan
        run: |
          set +e
          PLAN_OUTPUT=$(doppler run --name-transformer tf-var -- terraform plan -no-color -input=false 2>&1)
          PLAN_EXIT=$?
          set -e

          # Truncate if too large
          if [[ ${#PLAN_OUTPUT} -gt 60000 ]]; then
            PLAN_OUTPUT="${PLAN_OUTPUT:0:60000}

          ... (plan output truncated -- exceeded 60000 chars)"
          fi

          {
            printf 'plan<<PLAN_EOF\n'
            printf '%s\n' "$PLAN_OUTPUT"
            printf 'PLAN_EOF\n'
          } >> "$GITHUB_OUTPUT"

          printf 'exit_code=%d\n' "$PLAN_EXIT" >> "$GITHUB_OUTPUT"
          exit "$PLAN_EXIT"
        working-directory: <matrix.directory>
        env:
          DOPPLER_TOKEN: <DOPPLER_TOKEN_SECRET>
          DOPPLER_PROJECT: soleur
          DOPPLER_CONFIG: prd_terraform

      - name: Post plan comment
        if: always() && steps.plan.outcome != 'skipped'
        uses: marocchino/sticky-pull-request-comment@<sha>
        with:
          header: terraform-plan-<matrix.directory>
          message: |
            ### Terraform Plan: `<matrix.directory>`

            <details>
            <summary>Plan output (exit code: <steps.plan.outputs.exit_code>)</summary>

            ```
            <steps.plan.outputs.plan>
            ```

            </details>
```

## Dependencies

- **Blocking:** #978 (Doppler key alignment) must be resolved for clean plan output. The workflow itself can be merged first -- plan failures are posted as comments, not silent.
- **Resolved:** #973 (R2 remote backend) -- merged
- **Resolved:** #970 (Doppler TF integration, variable renames) -- merged

## References

- Closes #975
- Depends on #978
- Plan: `knowledge-base/plans/2026-03-21-feat-terraform-state-r2-migration-plan.md` (Phase 6, deferred)
- Learning: `knowledge-base/learnings/2026-03-21-terraform-state-r2-migration.md` (session error #4 -- tf-var backend conflict)
- Learning: `knowledge-base/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`
- Existing workflow: `.github/workflows/infra-validation.yml`
