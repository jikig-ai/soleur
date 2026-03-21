---
title: "infra: add scheduled drift detection for Terraform"
type: feat
date: 2026-03-21
---

# infra: add scheduled drift detection for Terraform

## Overview

Add a scheduled GitHub Actions workflow that runs `terraform plan -detailed-exitcode` every 12 hours against both Terraform stacks (`telegram-bridge` and `web-platform`). When drift is detected (exit code 2), the workflow creates a GitHub issue and sends a Discord notification. When Terraform errors occur (exit code 1), it sends an alert without creating a drift issue.

## Problem Statement / Motivation

The brainstorm (2026-03-21) identified drift detection as open question #1. Both stacks now have remote state in Cloudflare R2 (#972), Doppler-integrated credentials (#970), and CI validation (#971), but no mechanism to detect when live infrastructure diverges from the Terraform state. Drift can occur from:

- Manual changes via cloud dashboards (Hetzner, Cloudflare)
- External automation modifying resources outside Terraform
- Provider-side defaults changing between API versions
- State corruption in R2

Without detection, drift accumulates silently until the next `terraform apply` produces unexpected changes -- or worse, destroys resources.

## Proposed Solution

A single workflow file `.github/workflows/scheduled-terraform-drift.yml` that:

1. Runs on `schedule` (every 12 hours) and `workflow_dispatch`
2. Uses a matrix strategy to cover both stacks: `["apps/telegram-bridge/infra", "apps/web-platform/infra"]`
3. Installs Doppler CLI and Terraform
4. Sets R2 backend credentials as plain env vars (not through `--name-transformer tf-var` -- see learning from #970)
5. Runs `doppler run --name-transformer tf-var -- terraform plan -detailed-exitcode`
6. Handles exit codes: 0 = clean, 1 = error (alert), 2 = drift (issue + alert)
7. Creates a GitHub issue on drift with the plan output
8. Sends Discord notification on drift or error
9. Deduplicates issues by checking for existing open drift issues before creating new ones

### `.github/workflows/scheduled-terraform-drift.yml`

```yaml
name: Terraform Drift Detection

on:
  schedule:
    - cron: '0 6,18 * * *'   # Every 12 hours (06:00 UTC, 18:00 UTC)
  workflow_dispatch:

concurrency:
  group: terraform-drift
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  drift-check:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    strategy:
      matrix:
        directory:
          - apps/telegram-bridge/infra
          - apps/web-platform/infra
      fail-fast: false

    steps:
      - uses: actions/checkout@<SHA-PIN> # v4.3.1

      - uses: hashicorp/setup-terraform@<SHA-PIN> # v4.0.0
        with:
          terraform_version: "1.10.5"

      - name: Install Doppler CLI
        run: |
          mkdir -p ~/.local/bin
          ARCH=$(uname -m)
          case "$ARCH" in x86_64) ARCH="amd64";; aarch64) ARCH="arm64";; esac
          curl -Ls "https://cli.doppler.com/download?os=linux&arch=${ARCH}&format=tar" \
            | tar -xz -C ~/.local/bin doppler
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Generate SSH key for plan
        run: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q

      - name: Terraform init
        working-directory: <matrix.directory>
        env:
          AWS_ACCESS_KEY_ID: <from secrets>
          AWS_SECRET_ACCESS_KEY: <from secrets>
        run: terraform init -input=false

      - name: Terraform plan (drift check)
        id: plan
        working-directory: <matrix.directory>
        env:
          DOPPLER_TOKEN: <from secrets>
          AWS_ACCESS_KEY_ID: <from secrets>
          AWS_SECRET_ACCESS_KEY: <from secrets>
        run: |
          set +e
          PLAN_OUTPUT=$(doppler run \
            --project soleur --config prd_terraform \
            --name-transformer tf-var -- \
            terraform plan -detailed-exitcode -no-color -input=false 2>&1)
          EXIT_CODE=$?
          set -e
          echo "exit_code=$EXIT_CODE" >> "$GITHUB_OUTPUT"
          # Truncate plan output to 60000 chars for GitHub issue body limit
          echo "$PLAN_OUTPUT" | head -c 60000 > plan-output.txt
          if [[ $EXIT_CODE -eq 0 ]]; then
            echo "No drift detected"
          elif [[ $EXIT_CODE -eq 2 ]]; then
            echo "::warning::Drift detected in <matrix.directory>"
          else
            echo "::error::Terraform plan failed in <matrix.directory>"
          fi

      - name: Create GitHub issue (drift)
        if: steps.plan.outputs.exit_code == '2'
        env:
          GH_TOKEN: <github.token>
        run: |
          STACK_NAME=$(basename $(dirname "<matrix.directory>"))
          TITLE="infra: drift detected in ${STACK_NAME}"
          # Check for existing open issue to avoid duplicates
          EXISTING=$(gh issue list --label "infra-drift" --state open \
            --search "$TITLE" --json number --jq '.[0].number // empty')
          if [[ -n "$EXISTING" ]]; then
            # Comment on existing issue instead
            gh issue comment "$EXISTING" \
              --body "Drift still detected as of $(date -u '+%Y-%m-%d %H:%M UTC').

<details><summary>Plan output</summary>

\`\`\`
$(cat plan-output.txt)
\`\`\`
</details>"
            echo "Updated existing issue #$EXISTING"
          else
            gh issue create \
              --title "$TITLE" \
              --label "infra-drift" \
              --body "## Drift detected ...
              (plan output in details block)"
          fi

      - name: Discord notification
        if: steps.plan.outputs.exit_code != '0'
        env:
          DISCORD_WEBHOOK_URL: <from secrets>
          EXIT_CODE: <steps.plan.outputs.exit_code>
        run: |
          # Drift = warning, Error = alert
          # curl to Discord webhook with JSON payload
```

## Technical Considerations

### Credential Architecture

The R2 backend and Terraform providers require different credential paths:

| Credential | Source | Env Var Format | Why |
|---|---|---|---|
| R2 access key | GitHub Secrets (synced from Doppler) | `AWS_ACCESS_KEY_ID` (plain) | S3 backend reads standard AWS env vars, NOT `TF_VAR_*` |
| R2 secret key | GitHub Secrets (synced from Doppler) | `AWS_SECRET_ACCESS_KEY` (plain) | Same as above |
| `DOPPLER_TOKEN` | GitHub Secrets | `DOPPLER_TOKEN` (plain) | Bootstrap for `doppler run` |
| Hetzner token, CF token, etc. | Doppler `prd_terraform` config | `TF_VAR_*` via `--name-transformer tf-var` | Injected by `doppler run` |

This split is documented in the learning `2026-03-21-doppler-tf-var-naming-alignment.md` -- `--name-transformer tf-var` converts ALL keys including backend credentials, breaking S3 auth.

### SSH Key File Dependency

Both stacks use `file(var.ssh_key_path)` to read a public SSH key at plan time. The default path `~/.ssh/id_ed25519.pub` won't exist in CI runners. The workflow must generate a dummy SSH key before `terraform plan`. This key is never pushed to infrastructure -- it's only needed for Terraform to evaluate the `file()` function. The `hcloud_ssh_key` resource has `public_key` tracked in state, so plan will show a diff between the dummy key and the real key in state. This is expected and should NOT be treated as drift.

**Mitigation options:**
1. **Generate dummy key in CI** (simplest) -- `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""`. The plan will show the SSH key as changed, but this is a known false positive.
2. **Add `lifecycle { ignore_changes = [public_key] }` to `hcloud_ssh_key`** -- prevents the diff entirely. Better long-term but modifies infrastructure code.
3. **Store the real public key in Doppler** as a `TF_VAR_ssh_key_path` variable pointing to a file written from secrets -- more complex, avoids false positives.

**Recommendation:** Option 2 (add `ignore_changes`) is the cleanest. The SSH key is a create-time attribute that should never change via Terraform -- it's already an import artifact. Option 1 is the fallback if modifying `.tf` files is out of scope for this PR.

### Exit Code Semantics

| Exit Code | Meaning | Action |
|---|---|---|
| 0 | No changes | Log success, no notification |
| 1 | Error (syntax, auth, provider) | Discord alert, workflow annotation |
| 2 | Drift detected (changes needed) | GitHub issue + Discord alert |

### Issue Deduplication

Before creating a new drift issue, search for existing open issues with the `infra-drift` label and matching title. If found, append a comment with updated plan output and timestamp. This prevents issue flooding when drift persists across multiple runs (e.g., an intentional manual change not yet codified).

### Concurrency

The `concurrency` group `terraform-drift` with `cancel-in-progress: false` ensures:
- Scheduled runs don't cancel each other (if one takes >12h, which shouldn't happen)
- Manual `workflow_dispatch` waits for any running scheduled check
- Matrix jobs within a single run execute in parallel (safe -- they read different state files)

### Known False Positives

Resources with `lifecycle { ignore_changes }` blocks may still show plan output for attributes Terraform tracks but doesn't manage. The SSH key dummy-key diff (option 1) is the primary false positive. The plan should document expected non-zero diff lines so operators can distinguish real drift from noise.

## Acceptance Criteria

- [ ] Workflow file `.github/workflows/scheduled-terraform-drift.yml` exists and passes `actionlint`
- [ ] Workflow runs on `schedule` (every 12 hours) and `workflow_dispatch`
- [ ] Both stacks (`telegram-bridge`, `web-platform`) are checked via matrix strategy
- [ ] R2 backend credentials are set as plain env vars, not through `--name-transformer tf-var`
- [ ] `terraform plan -detailed-exitcode` correctly detects drift (exit code 2)
- [ ] GitHub issue with `infra-drift` label is created on drift detection
- [ ] Existing open drift issues receive a comment instead of duplicate creation
- [ ] Discord notification fires on drift (exit code 2) and error (exit code 1)
- [ ] No notification on clean plan (exit code 0)
- [ ] SSH key `file()` dependency is handled (dummy key or `ignore_changes`)
- [ ] Plan output in GitHub issues is truncated to stay under body size limits
- [ ] All action references are SHA-pinned per project convention
- [ ] `infra-drift` label is created idempotently (check before create)
- [ ] Workflow includes security comment header documenting secrets used and trust boundaries

## Test Scenarios

- Given both stacks have zero drift, when the workflow runs, then both matrix jobs exit 0 with no issues created and no Discord notifications sent.
- Given the `web-platform` stack has a manually-added DNS record, when the workflow runs, then a GitHub issue is created with `infra-drift` label containing the plan diff, and a Discord notification is sent.
- Given an existing open `infra-drift` issue for `web-platform`, when drift is detected again, then a comment is appended to the existing issue instead of creating a duplicate.
- Given the `DOPPLER_TOKEN` secret is missing or expired, when the workflow runs, then `terraform plan` exits 1, a Discord error alert is sent, but no drift issue is created.
- Given R2 credentials (`AWS_ACCESS_KEY_ID`) are missing, when the workflow runs, then `terraform init` fails, the plan step is skipped, and the workflow reports an error.
- Given `~/.ssh/id_ed25519.pub` does not exist in CI, when the workflow runs, then the dummy key generation step creates it before `terraform plan` so `file()` does not fail.
- Given a `workflow_dispatch` trigger, when invoked manually, then the workflow runs identically to the scheduled trigger.

## Dependencies and Risks

### Dependencies

- **GitHub Secrets** (synced from Doppler): `DOPPLER_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DISCORD_WEBHOOK_URL`
- **Doppler `prd_terraform` config**: Must contain all `TF_VAR_*` secrets for both stacks
- **R2 remote backend** (#972): State must be accessible from CI
- **Terraform 1.10.5**: Pinned version matching `infra-validation.yml`

### Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| SSH key false positive noise | High (if option 1) | Low | Use option 2 (`ignore_changes`) or filter known diffs |
| Doppler rate limiting on 2x daily runs | Very Low | Medium | 4 API calls/day is well within free tier |
| Plan output exceeds GitHub issue body limit (65,536 chars) | Low | Low | Truncate to 60,000 chars with `head -c` |
| R2 credentials expire | Low | High | Doppler sync keeps GH Secrets updated; token rotation is a separate concern |

## References and Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-21-terraform-state-mgmt-brainstorm.md` (open question #1)
- R2 backend config: `apps/telegram-bridge/infra/main.tf:1-14`, `apps/web-platform/infra/main.tf:1-14`
- Doppler credential pattern: `apps/telegram-bridge/infra/variables.tf:1-2` (comment documenting `doppler run` usage)
- Existing CI validation: `.github/workflows/infra-validation.yml` (offline validation pattern)
- Discord notification pattern: `.github/workflows/post-merge-monitor.yml:200-235`
- Issue creation pattern: `.github/workflows/scheduled-linkedin-token-check.yml:78-81`
- Learning -- credential split: `knowledge-base/learnings/2026-03-21-doppler-tf-var-naming-alignment.md`
- Learning -- R2 backend: `knowledge-base/learnings/2026-03-21-terraform-state-r2-migration.md`
- Learning -- Doppler install: `knowledge-base/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`

### External References

- [Terraform plan -detailed-exitcode](https://developer.hashicorp.com/terraform/cli/commands/plan#detailed-exitcode)
- [GitHub Actions scheduled events](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule)
- [Discord webhook API](https://discord.com/developers/docs/resources/webhook)

### Related Issues

- #977 (this issue)
- #972 (R2 remote backend -- prerequisite, merged)
- #970 (Doppler + Terraform integration -- prerequisite, merged)
- #971 (Cloudflare Tunnel provisioning -- prerequisite, merged)

## MVP

### `.github/workflows/scheduled-terraform-drift.yml`

```yaml
# Security: Requires DOPPLER_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# (from GitHub Secrets, synced via Doppler). DISCORD_WEBHOOK_URL for notifications.
# R2 backend credentials are set as plain env vars -- not through --name-transformer
# tf-var, which would convert them to TF_VAR_* format and break S3 auth.
# Plan output is included in GitHub issues (truncated to 60k chars).
name: Terraform Drift Detection

on:
  schedule:
    - cron: '0 6,18 * * *'
  workflow_dispatch:

concurrency:
  group: terraform-drift
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  drift-check:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    strategy:
      matrix:
        directory:
          - apps/telegram-bridge/infra
          - apps/web-platform/infra
      fail-fast: false

    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - uses: hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0
        with:
          terraform_version: "1.10.5"

      - name: Install Doppler CLI
        run: |
          mkdir -p ~/.local/bin
          ARCH=$(uname -m)
          case "$ARCH" in x86_64) ARCH="amd64";; aarch64) ARCH="arm64";; esac
          curl -Ls "https://cli.doppler.com/download?os=linux&arch=${ARCH}&format=tar" \
            | tar -xz -C ~/.local/bin doppler
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Generate CI SSH key
        run: |
          mkdir -p ~/.ssh
          ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q

      - name: Terraform init
        working-directory: ${{ matrix.directory }}
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
        run: terraform init -input=false

      - name: Terraform plan (drift detection)
        id: plan
        working-directory: ${{ matrix.directory }}
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
          AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
        run: |
          set +e
          PLAN_OUTPUT=$(doppler run \
            --project soleur --config prd_terraform \
            --name-transformer tf-var -- \
            terraform plan -detailed-exitcode -no-color -input=false 2>&1)
          EXIT_CODE=$?
          set -e

          echo "exit_code=$EXIT_CODE" >> "$GITHUB_OUTPUT"
          echo "$PLAN_OUTPUT" | head -c 60000 > plan-output.txt

          STACK_NAME=$(echo "${{ matrix.directory }}" | sed 's|apps/||;s|/infra||')
          echo "stack_name=$STACK_NAME" >> "$GITHUB_OUTPUT"

          if [[ $EXIT_CODE -eq 0 ]]; then
            echo "No drift detected in $STACK_NAME"
          elif [[ $EXIT_CODE -eq 2 ]]; then
            echo "::warning::Drift detected in $STACK_NAME"
          else
            echo "::error::Terraform plan failed in $STACK_NAME (exit $EXIT_CODE)"
          fi

      - name: Ensure infra-drift label exists
        if: steps.plan.outputs.exit_code == '2'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "infra-drift" \
            --description "Terraform detected infrastructure drift" \
            --color "D93F0B" 2>/dev/null || true

      - name: Create or update drift issue
        if: steps.plan.outputs.exit_code == '2'
        env:
          GH_TOKEN: ${{ github.token }}
          STACK_NAME: ${{ steps.plan.outputs.stack_name }}
        run: |
          TITLE="infra: drift detected in ${STACK_NAME}"
          TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')
          PLAN_CONTENT=$(cat plan-output.txt)

          EXISTING=$(gh issue list --label "infra-drift" --state open \
            --search "drift detected in ${STACK_NAME}" \
            --json number --jq '.[0].number // empty')

          if [[ -n "$EXISTING" ]]; then
            gh issue comment "$EXISTING" --body "$(cat <<EOF
          Drift still present as of ${TIMESTAMP}.

          <details><summary>Plan output</summary>

          \`\`\`
          ${PLAN_CONTENT}
          \`\`\`

          </details>
          EOF
          )"
            echo "Updated existing issue #$EXISTING"
          else
            gh issue create \
              --title "$TITLE" \
              --label "infra-drift" \
              --body "$(cat <<EOF
          ## Drift Detected

          **Stack:** \`${STACK_NAME}\`
          **Detected:** ${TIMESTAMP}
          **Workflow:** [Run #${{ github.run_number }}](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})

          Terraform \`plan -detailed-exitcode\` returned exit code 2, indicating infrastructure has drifted from the Terraform state.

          <details><summary>Plan output</summary>

          \`\`\`
          ${PLAN_CONTENT}
          \`\`\`

          </details>

          ## Next Steps

          1. Review the plan output above
          2. If the drift is intentional, run \`terraform apply\` locally to update state
          3. If the drift is unintentional, revert the manual change
          4. Close this issue when resolved

          _Auto-created by the [terraform-drift workflow](${{ github.server_url }}/${{ github.repository }}/actions/workflows/scheduled-terraform-drift.yml)._
          EOF
          )"
            echo "Created new drift issue for $STACK_NAME"
          fi

      - name: Discord notification
        if: steps.plan.outputs.exit_code != '0'
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
          EXIT_CODE: ${{ steps.plan.outputs.exit_code }}
          STACK_NAME: ${{ steps.plan.outputs.stack_name }}
        run: |
          if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
            echo "DISCORD_WEBHOOK_URL not set, skipping"
            exit 0
          fi

          REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
          RUN_URL="${REPO_URL}/actions/runs/${GITHUB_RUN_ID}"

          if [[ "$EXIT_CODE" == "2" ]]; then
            MESSAGE=$(printf '**[DRIFT] Infrastructure drift detected in %s**\n\nRun: %s\n\nRun `terraform plan` locally to review changes.' \
              "$STACK_NAME" "$RUN_URL")
          else
            MESSAGE=$(printf '**[ERROR] Terraform plan failed for %s**\n\nRun: %s\n\nCheck the workflow logs for details.' \
              "$STACK_NAME" "$RUN_URL")
          fi

          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$DISCORD_WEBHOOK_URL")

          if [[ "$HTTP_CODE" =~ ^2 ]]; then
            echo "Discord notification sent (HTTP $HTTP_CODE)"
          else
            echo "::warning::Discord notification failed (HTTP $HTTP_CODE)"
          fi
```
