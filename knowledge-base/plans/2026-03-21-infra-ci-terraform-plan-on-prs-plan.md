---
title: "infra: add CI terraform plan on PRs"
type: feat
date: 2026-03-21
semver: patch
deepened: 2026-03-21
---

# infra: Add CI Terraform Plan on PRs

## Enhancement Summary

**Deepened on:** 2026-03-21
**Research sources:** DopplerHQ/cli-action docs, DopplerHQ/secrets-fetch-action evaluation, hashicorp/setup-terraform wrapper analysis, marocchino/sticky-pull-request-comment docs, GitHub Actions fork PR security model, existing project learnings (terraform-state-r2-migration, doppler-tf-var-naming-alignment, ci-deploy-reliability), SpecFlow analysis of conditional paths

### Key Improvements

1. Resolved SHA pins for all new actions: `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c` (v4), `marocchino/sticky-pull-request-comment@70d2764d1a7d5d9560b100cbea0077fc8f633987` (v3.0.2)
2. Identified that `setup-terraform` wrapper (`terraform_wrapper`) must be set to `false` -- the wrapper captures stdout/stderr for direct `terraform` calls, but `doppler run -- terraform plan` wraps the binary, causing interleaved or empty outputs
3. Confirmed `secrets-fetch-action` does NOT support `--name-transformer tf-var`, validating the CLI-based approach
4. Verified env var inheritance: `GITHUB_ENV`-set `AWS_ACCESS_KEY_ID` persists into `doppler run` child process because `--name-transformer tf-var` transforms it to `TF_VAR_aws_access_key_id` (different key), not overwriting the plain form
5. Added `continue-on-error: true` on the plan step so the comment step always runs, even on plan failure
6. Added `ssh_key_path` dummy variable handling -- `telegram-bridge` stack requires `ssh_key_path` which defaults to `~/.ssh/id_ed25519.pub` (a local path that won't exist in CI); plan uses `-var='ssh_key_path=/dev/null'` override

### New Considerations Discovered

- The `telegram-bridge` stack's `ssh_key_path` variable defaults to a local file path -- CI must override it or plan will fail trying to read `~/.ssh/id_ed25519.pub`
- `setup-terraform` v4 defaults `terraform_wrapper: true` which captures terraform stdout/stderr into step outputs, but this interferes with `doppler run` wrapping -- must explicitly set `terraform_wrapper: false`
- `DopplerHQ/secrets-fetch-action` (v2.0.0) was evaluated as an alternative but lacks `--name-transformer` support, confirming `cli-action` + `doppler run` is the correct approach
- GitHub Actions `GITHUB_OUTPUT` has a 1MB limit per step -- the 60000 char truncation safely stays within this (~60KB << 1MB)
- The `plan` step should use `continue-on-error: true` rather than `set +e` / `exit "$PLAN_EXIT"` to allow the comment step to run while still surfacing the failure in the workflow status

## Overview

Add a `terraform-plan` job to the existing `infra-validation.yml` workflow that runs `terraform plan` on PRs touching `apps/*/infra/**` and posts the plan output as a sticky PR comment. Uses Doppler-first credential injection via `DopplerHQ/cli-action` with a single `DOPPLER_TOKEN` GitHub Secret as bootstrap. Gracefully skips when secrets are unavailable (fork/Dependabot PRs).

## Problem Statement

The R2 remote backend is now live (#973) and Doppler is integrated with Terraform (#970), but there is no CI validation that `terraform plan` succeeds. The existing `infra-validation.yml` runs only offline checks (`terraform fmt -check`, `terraform validate -backend=false`). A developer can merge TF changes that pass formatting and syntax checks but produce plan errors against real state -- for example, referencing a resource that was deleted, or introducing a variable mismatch.

## Proposed Solution

Extend `infra-validation.yml` with a new `plan` job that runs after the existing `validate` job. The plan job:

1. Installs the Doppler CLI via `DopplerHQ/cli-action`
2. Extracts R2 backend credentials as plain env vars via `doppler secrets get`
3. Runs `terraform init -input=false` (with real R2 backend using `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`)
4. Runs `doppler run --name-transformer tf-var -- terraform plan -no-color -input=false` to inject TF variables
5. Posts the plan output as a sticky PR comment using `marocchino/sticky-pull-request-comment`
6. Truncates output for large plans (GitHub comment limit is 65536 chars; `GITHUB_OUTPUT` limit is 1MB)

### Credential Strategy: Doppler-First

Per the brainstorm decision (2026-03-21), the approach uses a single `DOPPLER_TOKEN` GitHub Secret that bootstraps all other secrets via Doppler at runtime. This eliminates split-brain between GitHub Secrets and Doppler.

**Required GitHub Secrets:**
- `DOPPLER_TOKEN` -- a Doppler service token scoped to `soleur` project, `prd_terraform` config

**Injected by Doppler at runtime:**
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` -- R2 S3-compatible credentials for the backend (extracted as plain env vars via `doppler secrets get --plain`)
- `TF_VAR_hcloud_token`, `TF_VAR_cf_api_token`, etc. -- via `doppler run --name-transformer tf-var`

**Critical learning (from #973 session error #4):** The `--name-transformer tf-var` converts ALL keys to `TF_VAR_*` format, including `AWS_ACCESS_KEY_ID` -> `TF_VAR_aws_access_key_id`. The S3 backend reads `AWS_ACCESS_KEY_ID` as a plain env var, not `TF_VAR_*`. The workflow uses a two-step approach:
1. **Step A (Extract):** `doppler secrets get AWS_ACCESS_KEY_ID --plain` -> write to `GITHUB_ENV` (persists across all subsequent steps)
2. **Step B (Plan):** `doppler run --name-transformer tf-var -- terraform plan` -- injects `TF_VAR_*` vars for TF variables; the plain `AWS_ACCESS_KEY_ID` from `GITHUB_ENV` is inherited by the child process and NOT overwritten (the transformer produces `TF_VAR_aws_access_key_id`, a different key)

### Research Insights: Alternative Approaches Evaluated

**`DopplerHQ/secrets-fetch-action` (v2.0.0):** Evaluated as a simpler alternative -- it injects all Doppler secrets as env vars via `GITHUB_ENV` in a single step with `inject-env-vars: true`. However, it does NOT support `--name-transformer tf-var`. This means it would inject `CF_API_TOKEN` (not `TF_VAR_cf_api_token`), which Terraform cannot read. The CLI-based approach (`cli-action` + `doppler run`) is the only viable option.

**`setup-terraform` wrapper:** The `terraform_wrapper: true` default in `hashicorp/setup-terraform` captures terraform stdout/stderr into step outputs (`steps.plan.outputs.stdout`). However, when terraform is invoked via `doppler run -- terraform plan`, the wrapper cannot intercept the output because it wraps a different binary. Set `terraform_wrapper: false` and capture output manually via shell variable.

### Fork/Dependabot PR Handling

Secrets are unavailable on fork PRs and Dependabot PRs (unless the repo has explicitly allowed it). The plan job must:

1. Use a preceding `check-secrets` job that probes `DOPPLER_TOKEN` availability: pass the secret as an env var and test if it's non-empty
2. Gate the plan job on the `check-secrets` output: `needs.check-secrets.outputs.has-doppler-token == 'true'`
3. When skipped, the sticky comment action is also skipped -- no orphan "secrets unavailable" comment is needed (the absence of a plan comment is self-explanatory)

### Research Insights: Fork PR Security Model

GitHub Actions does not expose repository secrets to workflows triggered by `pull_request` events from forks. The `check-secrets` job pattern (passing the secret as an env var, testing for emptiness) is the standard approach -- `if: secrets.DOPPLER_TOKEN != ''` at the job level is NOT valid because secrets are not available in `if` expressions directly. The env-var-probe pattern works because secrets resolve to empty strings when unavailable.

### Concurrency

Per existing conventions, use `cancel-in-progress: false` to ensure plans are not cancelled mid-execution (which could leave stale comments):

```yaml
concurrency:
  group: terraform-plan-${{ github.event.number }}-${{ matrix.directory }}
  cancel-in-progress: false
```

The concurrency group includes the directory to allow parallel plans across different stacks.

### Sticky PR Comment

Use `marocchino/sticky-pull-request-comment@70d2764d1a7d5d9560b100cbea0077fc8f633987` (v3.0.2, SHA-pinned) to update a single comment per stack per PR rather than creating new comments on each push. The comment header identifies the stack:

```
### Terraform Plan: `apps/web-platform/infra`
```

Output truncation: if plan output exceeds 60000 chars, truncate with a message indicating the plan was too large. This stays well within GitHub's 65536 char comment limit and `GITHUB_OUTPUT`'s 1MB step output limit.

### Research Insights: Comment Formatting

The `<details>` / `<summary>` HTML pattern collapses the plan output by default, keeping the PR timeline clean. Include the exit code in the summary line so reviewers can see pass/fail at a glance without expanding. Use triple backticks without a language identifier inside the details block -- terraform plan output does not benefit from syntax highlighting and some plan outputs contain HCL-like syntax that confuses highlighters.

## Technical Considerations

### Dependency on #978 (Doppler Key Alignment)

Issue #978 documents that several Doppler keys in `prd_terraform` config don't align with the `tf-var` transformer output. Specifically:
- `CLOUDFLARE_ACCOUNT_ID` produces `TF_VAR_cloudflare_account_id` but TF expects `TF_VAR_cf_account_id`
- `CLOUDFLARE_API_TOKEN` produces `TF_VAR_cloudflare_api_token` but TF expects `TF_VAR_cf_api_token`
- `ADMIN_IPS` and `DOPPLER_TOKEN` may be missing from `prd_terraform`

**This must be resolved before the CI plan workflow can succeed.** The workflow can be merged first (it will show plan failures as PR comments, not silent failures), but clean operation requires #978 to be resolved. The plan should document this dependency clearly.

### S3 Backend Credential Separation

The R2 backend needs `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as plain environment variables. The `--name-transformer tf-var` would convert these to `TF_VAR_aws_access_key_id` which the S3 backend ignores.

**Recommended approach:** Extract backend credentials into `GITHUB_ENV` in a dedicated step, then use `doppler run --name-transformer tf-var` for the plan step:

```bash
# Step: Extract backend credentials (writes to GITHUB_ENV, persists across steps)
echo "AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain)" >> "$GITHUB_ENV"
echo "AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)" >> "$GITHUB_ENV"
```

```bash
# Step: Terraform plan (GITHUB_ENV vars are inherited; doppler run adds TF_VAR_* vars)
doppler run --name-transformer tf-var -- terraform plan -no-color -input=false
```

The `GITHUB_ENV`-set `AWS_ACCESS_KEY_ID` is NOT overwritten by `doppler run --name-transformer tf-var` because the transformer produces `TF_VAR_aws_access_key_id` (a different key). Both the plain `AWS_ACCESS_KEY_ID` (for S3 backend) and `TF_VAR_*` vars (for TF variables) coexist in the child process environment.

### Research Insights: Terraform Wrapper Interference

`hashicorp/setup-terraform` v4 defaults to `terraform_wrapper: true`, which installs a Node.js wrapper around the `terraform` binary. This wrapper captures stdout/stderr into step outputs (`steps.<id>.outputs.stdout`). However, when terraform is invoked indirectly via `doppler run -- terraform plan`, the wrapper cannot intercept the call -- Doppler spawns the process directly, bypassing the wrapper.

**Required:** Set `terraform_wrapper: false` in the `setup-terraform` step. Capture plan output manually via shell variable (`PLAN_OUTPUT=$(... 2>&1)`).

### SSH Key Path Variable (telegram-bridge)

The `telegram-bridge` stack has a `ssh_key_path` variable defaulting to `~/.ssh/id_ed25519.pub`. In CI, this file does not exist and `terraform plan` will fail trying to read it (used in `file()` function calls).

**Solution:** Override with a dummy value: `-var='ssh_key_path=/dev/null'`. The plan job only validates that the configuration is internally consistent against real state -- it does not need a real SSH key. Alternatively, generate a temporary key: `ssh-keygen -t ed25519 -f /tmp/ci_key -N "" -q` and pass `-var='ssh_key_path=/tmp/ci_key.pub'`.

The `/dev/null` approach is simpler but may cause a plan diff (empty key vs. real key). The generated key approach is cleaner for plan accuracy. Use the generated key approach.

### Matrix Strategy for Multiple Stacks

Reuse the existing `detect-changes` job's directory matrix. The plan job runs per-directory, same as the validate job. This means a PR touching both `apps/telegram-bridge/infra/` and `apps/web-platform/infra/` gets two separate plan outputs, each as its own sticky comment.

### SHA-Pinned Actions

Per existing conventions, all action references are SHA-pinned with version comments:

- `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
- `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85` (v4.0.0)
- `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c` (v4)
- `marocchino/sticky-pull-request-comment@70d2764d1a7d5d9560b100cbea0077fc8f633987` (v3.0.2)

### Security Comment Header

Per constitution.md convention, include a security header:

```yaml
# Security: DOPPLER_TOKEN from repository secrets injects Terraform credentials.
# All Doppler secrets are scoped to prd_terraform config (read-only from CI perspective).
# Plan output is posted as a PR comment -- secrets are NOT included in plan output
# because all sensitive variables are marked sensitive = true in variables.tf.
# Fork PRs cannot access secrets -- workflow gracefully skips plan step.
# All action references are SHA-pinned.
```

### Research Insights: Secret Leakage in Plan Output

Terraform redacts variables marked `sensitive = true` in plan output, showing `(sensitive value)` instead. Both stacks mark `hcloud_token`, `cf_api_token`, `webhook_deploy_secret`, and `doppler_token` as `sensitive = true`. However, `cf_zone_id` and `cf_account_id` are NOT marked sensitive -- these values will appear in plan output posted as PR comments. Per the Doppler integration plan (#970), marking these as sensitive was deferred. For a public repo, consider adding `sensitive = true` to these variables before enabling the CI plan workflow. For a private repo, the risk is lower.

### Permissions

The plan job needs:
- `contents: read` -- checkout code
- `pull-requests: write` -- post PR comment

The existing `infra-validation.yml` only has `contents: read`. Use job-level permissions on the `plan` job to avoid granting `pull-requests: write` to jobs that don't need it (principle of least privilege).

### Timeout

Set `timeout-minutes: 10` on the plan job. Terraform plan typically completes in 30-90 seconds per stack, but network issues with R2 or Doppler could cause hangs. The 10-minute limit provides generous headroom while preventing runaway billing.

### Error Handling: `continue-on-error` vs `set +e`

The MVP originally used `set +e` / `exit "$PLAN_EXIT"` to capture the exit code while still failing the step. A cleaner approach:
- Set `continue-on-error: true` on the plan step
- The step outcome is available via `steps.plan.outcome` (`success` or `failure`)
- The comment step runs via `if: always()` and shows success/failure status
- The overall job still reports the plan step's outcome in the workflow summary

This avoids the complexity of manually propagating exit codes through `GITHUB_OUTPUT` and `set +e`/`set -e` toggling.

## Non-Goals

- Adding `terraform apply` automation (remains manual)
- Adding pre-commit hooks for terraform (Lefthook integration deferred)
- Resolving Doppler key naming (#978) -- that is a separate issue
- Adding plan approval gating (plan failures are informational, not blocking)
- Supporting `terraform plan` for stacks not under `apps/*/infra/`
- Marking `cf_zone_id`/`cf_account_id` as `sensitive = true` (deferred, tracked separately)

## Acceptance Criteria

- [x] `infra-validation.yml` has a `plan` job that runs `terraform plan` against real R2 backend state
- [x] Plan job uses `DOPPLER_TOKEN` GitHub Secret and `DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c` (v4) for credential injection
- [x] `setup-terraform` step sets `terraform_wrapper: false` to avoid output capture interference
- [x] Backend credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) are extracted as plain env vars via `doppler secrets get --plain`
- [x] TF variables are injected via `doppler run --name-transformer tf-var` in the plan step
- [x] CI generates a temporary SSH key for `ssh_key_path` variable override
- [x] Plan output is posted as a sticky PR comment per stack using `marocchino/sticky-pull-request-comment@70d2764d1a7d5d9560b100cbea0077fc8f633987` (v3.0.2)
- [x] Large plan output (>60000 chars) is truncated with a warning message
- [x] Fork/Dependabot PRs where secrets are unavailable skip the plan job gracefully
- [x] Concurrency group prevents parallel plan runs per PR per directory, with `cancel-in-progress: false`
- [x] All action references are SHA-pinned per existing conventions
- [x] `timeout-minutes: 10` is set on the plan job
- [x] Security comment header documents input trust boundaries and secret leakage considerations
- [x] Workflow permissions: `contents: read` workflow-level, `pull-requests: write` on plan job only

## Test Scenarios

- Given a PR that modifies `apps/web-platform/infra/variables.tf`, when the workflow triggers, then `terraform plan` runs for `apps/web-platform/infra/` and posts the plan output as a sticky PR comment
- Given a PR that modifies both `apps/web-platform/infra/` and `apps/telegram-bridge/infra/`, when the workflow triggers, then two separate sticky comments appear (one per stack)
- Given a fork PR where `DOPPLER_TOKEN` is unavailable, when the workflow triggers, then the plan job is skipped entirely (no error, no comment)
- Given a plan output exceeding 60000 characters, when posted as a comment, then the output is truncated with a "Plan output truncated" warning
- Given a subsequent push to the same PR, when the workflow runs again, then the existing sticky comment is updated (not duplicated)
- Given #978 is unresolved (Doppler key mismatch), when the plan runs, then the plan failure is captured and posted as a comment (not a silent workflow failure)
- Given the `detect-changes` job finds no changed infra directories, when the workflow runs, then the plan job is skipped entirely
- Given the `telegram-bridge` stack is in the matrix, when the plan runs in CI, then a temporary SSH key is generated and passed via `-var='ssh_key_path=...'` to avoid file-not-found errors
- Given `terraform plan` exits non-zero, when the comment step runs (via `if: always()`), then the comment includes the failure output and the exit code in the summary

## Affected Files

### `.github/workflows/infra-validation.yml`

The primary file to modify. Changes:

1. Update workflow-level security comment header to document Doppler credentials
2. Add `check-secrets` job to detect `DOPPLER_TOKEN` availability
3. Add `plan` job after `validate`, gated on `check-secrets` output and `detect-changes` matrix
4. Plan job uses job-level `permissions: pull-requests: write`
5. Plan job steps: checkout, setup-terraform (wrapper=false), install-doppler-cli, generate-ssh-key, extract-backend-creds, terraform-init, terraform-plan (continue-on-error), post-comment (if: always())

### No new files

All changes fit within the existing workflow file. No new scripts, actions, or configuration files needed.

## MVP

### `.github/workflows/infra-validation.yml` (plan job addition)

```yaml
  check-secrets:
    runs-on: ubuntu-24.04
    outputs:
      has-doppler-token: ${{ steps.check.outputs.has_token }}
    steps:
      - name: Check DOPPLER_TOKEN availability
        id: check
        run: |
          if [[ -n "${DOPPLER_TOKEN_CHECK}" ]]; then
            printf 'has_token=true\n' >> "$GITHUB_OUTPUT"
          else
            printf 'has_token=false\n' >> "$GITHUB_OUTPUT"
          fi
        env:
          DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN }}

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
        directory: ${{ fromJSON(needs.detect-changes.outputs.directories) }}
      fail-fast: false
    concurrency:
      group: terraform-plan-${{ github.event.number }}-${{ matrix.directory }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - uses: hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0
        with:
          terraform_version: "1.10.5"
          terraform_wrapper: false

      - name: Install Doppler CLI
        uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4

      - name: Generate CI SSH key
        run: |
          ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q
          printf 'ci_ssh_pub=%s\n' "/tmp/ci_ssh_key.pub" >> "$GITHUB_ENV"

      - name: Extract backend credentials
        run: |
          printf 'AWS_ACCESS_KEY_ID=%s\n' "$(doppler secrets get AWS_ACCESS_KEY_ID --plain)" >> "$GITHUB_ENV"
          printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)" >> "$GITHUB_ENV"
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
          DOPPLER_PROJECT: soleur
          DOPPLER_CONFIG: prd_terraform

      - name: Terraform init
        run: terraform init -input=false
        working-directory: ${{ matrix.directory }}

      - name: Terraform plan
        id: plan
        continue-on-error: true
        run: |
          PLAN_OUTPUT=$(doppler run --name-transformer tf-var -- \
            terraform plan -no-color -input=false \
            -var="ssh_key_path=${ci_ssh_pub}" 2>&1)
          PLAN_EXIT=$?

          # Truncate if too large for GITHUB_OUTPUT (1MB limit)
          if [[ ${#PLAN_OUTPUT} -gt 60000 ]]; then
            PLAN_OUTPUT="${PLAN_OUTPUT:0:60000}

          ... (plan output truncated -- exceeded 60,000 chars)"
          fi

          {
            printf 'plan<<PLAN_EOF\n'
            printf '%s\n' "$PLAN_OUTPUT"
            printf 'PLAN_EOF\n'
          } >> "$GITHUB_OUTPUT"

          printf 'exit_code=%d\n' "$PLAN_EXIT" >> "$GITHUB_OUTPUT"
          exit "$PLAN_EXIT"
        working-directory: ${{ matrix.directory }}
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
          DOPPLER_PROJECT: soleur
          DOPPLER_CONFIG: prd_terraform

      - name: Post plan comment
        if: always() && steps.plan.outcome != 'skipped'
        uses: marocchino/sticky-pull-request-comment@70d2764d1a7d5d9560b100cbea0077fc8f633987 # v3.0.2
        with:
          header: terraform-plan-${{ matrix.directory }}
          message: |
            ### Terraform Plan: `${{ matrix.directory }}`

            **Result:** ${{ steps.plan.outcome == 'success' && 'No changes' || 'Changes detected or error' }} (exit code: ${{ steps.plan.outputs.exit_code }})

            <details>
            <summary>Plan output</summary>

            ```
            ${{ steps.plan.outputs.plan }}
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
- Learning: `knowledge-base/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` (concurrency group patterns)
- Existing workflow: `.github/workflows/infra-validation.yml`
- [DopplerHQ/cli-action](https://github.com/DopplerHQ/cli-action) -- v4, SHA: `5351693ec144fc7f7a2d30025061acfc3c53c47c`
- [marocchino/sticky-pull-request-comment](https://github.com/marocchino/sticky-pull-request-comment) -- v3.0.2, SHA: `70d2764d1a7d5d9560b100cbea0077fc8f633987`
- [hashicorp/setup-terraform wrapper issue](https://github.com/hashicorp/setup-terraform/issues/405) -- stdout interleaving with wrapper enabled
- [Doppler GitHub Actions docs](https://docs.doppler.com/docs/github-actions) -- official integration guide
