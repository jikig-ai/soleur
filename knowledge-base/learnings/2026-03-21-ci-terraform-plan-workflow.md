# Learning: CI Terraform Plan Workflow Patterns

## Problem

Adding a CI job that runs `terraform plan` with Doppler-injected credentials and posts results as PR comments requires solving several non-obvious GitHub Actions interactions. Each pattern below was discovered through a failure during implementation of the `plan` job in `.github/workflows/infra-validation.yml` (issue #975).

## Solution

### 1. Heredoc delimiter collision in `GITHUB_OUTPUT`

Writing multiline output (like `terraform plan`) to `$GITHUB_OUTPUT` requires a heredoc delimiter. A fixed delimiter like `PLAN_EOF` creates an injection risk: if Terraform plan output contains the literal string `PLAN_EOF` on its own line, GitHub Actions will prematurely close the heredoc, corrupting the output and potentially allowing command injection.

**Fix:** Randomize the delimiter with a cryptographic suffix.

```bash
DELIMITER="PLAN_EOF_$(openssl rand -hex 8)"
{
  printf 'plan<<%s\n' "$DELIMITER"
  printf '%s\n' "$PLAN_OUTPUT"
  printf '%s\n' "$DELIMITER"
} >> "$GITHUB_OUTPUT"
```

This is a general GitHub Actions security pattern applicable to any multiline output where the content is not fully controlled.

### 2. Doppler-fetched secrets are NOT auto-masked

When fetching secrets from Doppler via CLI (e.g., `doppler secrets get KEY --plain`), GitHub Actions does NOT automatically mask them in logs. This differs from `secrets.*` context references, which are always masked. Any Doppler-fetched value that appears in subsequent step logs will be printed in plaintext.

**Fix:** Explicitly call `::add-mask::` immediately after fetching each secret.

```bash
KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain)
SECRET=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)
printf '::add-mask::%s\n' "$KEY_ID"
printf '::add-mask::%s\n' "$SECRET"
```

### 3. Two-step credential injection for S3 backend + `--name-transformer tf-var`

The `doppler run --name-transformer tf-var` flag converts ALL environment variable names to `TF_VAR_` prefix format. This means `AWS_ACCESS_KEY_ID` becomes `TF_VAR_aws_access_key_id`, which the Terraform S3 backend ignores -- it only reads `AWS_ACCESS_KEY_ID`. Running `terraform init` inside `doppler run --name-transformer tf-var` will fail with authentication errors.

**Fix:** Extract backend credentials to `GITHUB_ENV` in a prior step (persists as plain env vars), then use `doppler run --name-transformer tf-var` only for the plan step. The plain `AWS_ACCESS_KEY_ID` from `GITHUB_ENV` coexists with the `TF_VAR_aws_access_key_id` injected by Doppler.

```yaml
# Step 1: Extract backend creds to GITHUB_ENV (plain names)
- name: Extract backend credentials
  run: |
    KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain)
    SECRET=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)
    printf 'AWS_ACCESS_KEY_ID=%s\n' "$KEY_ID" >> "$GITHUB_ENV"
    printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$SECRET" >> "$GITHUB_ENV"

# Step 2: terraform init reads AWS_ACCESS_KEY_ID from GITHUB_ENV
- name: Terraform init
  run: terraform init -input=false

# Step 3: doppler run injects TF_VAR_* for plan; AWS_* still in env for backend
- name: Terraform plan
  run: |
    doppler run --name-transformer tf-var -- \
      terraform plan -no-color -input=false
```

### 4. `continue-on-error: true` masks job status

Setting `continue-on-error: true` on a step means the job reports overall success even when that step fails. This is needed so that the comment-posting step runs after a plan failure, but it silently hides the failure from the PR check status.

**Fix:** Add an explicit final step that checks the captured exit code and fails the job.

```yaml
- name: Terraform plan
  id: plan
  continue-on-error: true
  run: |
    # ... capture output and exit code ...
    printf 'exit_code=%d\n' "$PLAN_EXIT" >> "$GITHUB_OUTPUT"
    exit "$PLAN_EXIT"

- name: Post plan comment
  if: always() && steps.plan.outcome != 'skipped'
  # ... post the comment ...

- name: Fail job on plan failure
  if: steps.plan.outputs.exit_code != '0'
  run: exit 1
```

The three-step sequence is: (1) plan with `continue-on-error`, (2) post comment with `if: always()`, (3) re-surface failure with explicit `exit 1`.

### 5. `terraform_wrapper: false` is mandatory with `doppler run`

The `hashicorp/setup-terraform` action installs a wrapper script that intercepts `terraform` stdout/stderr for use in GitHub Actions outputs. This wrapper only intercepts direct `terraform` calls. When `terraform` is invoked through `doppler run -- terraform plan`, the wrapper cannot intercept the output, leading to empty outputs and broken comment posting.

**Fix:** Disable the wrapper and capture output manually.

```yaml
- uses: hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0
  with:
    terraform_version: ${{ env.TERRAFORM_VERSION }}
    terraform_wrapper: false

# Then capture output manually:
- run: |
    PLAN_OUTPUT=$(doppler run --name-transformer tf-var -- \
      terraform plan -no-color -input=false 2>&1)
```

### 6. Fork PR secret detection

GitHub Actions `if:` expressions cannot test secret emptiness directly. The expression `secrets.DOPPLER_TOKEN != ''` is NOT valid syntax in `if:` conditions because secrets are not exposed to expression evaluation in that context.

**Fix:** Use a dedicated `check-secrets` job that passes the secret as an env var and tests emptiness in a `run:` block, then exposes the result as a job output.

```yaml
check-secrets:
  runs-on: ubuntu-24.04
  outputs:
    has-doppler-token: ${{ steps.check.outputs.has_token }}
  steps:
    - name: Check DOPPLER_TOKEN availability
      id: check
      env:
        DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN }}
      run: |
        if [[ -n "${DOPPLER_TOKEN_CHECK}" ]]; then
          printf 'has_token=true\n' >> "$GITHUB_OUTPUT"
        else
          printf 'has_token=false\n' >> "$GITHUB_OUTPUT"
        fi

plan:
  needs: [check-secrets]
  if: needs.check-secrets.outputs.has-doppler-token == 'true'
```

This pattern allows the plan job to gracefully skip on fork PRs (where secrets are unavailable) without producing a confusing error.

## Key Insight

GitHub Actions, Terraform, and Doppler each make reasonable assumptions about their environment that conflict when composed. The S3 backend expects standard `AWS_*` env var names; `--name-transformer tf-var` renames everything; `setup-terraform` wraps the binary but only for direct invocations; `secrets.*` is masked but CLI-fetched secrets are not; `continue-on-error` hides failures from the check API. Each tool works correctly in isolation -- the bugs only appear at integration boundaries. When building CI pipelines that chain multiple tools, test each integration seam independently rather than debugging the composed pipeline end-to-end.

## Session Errors

None

## Tags

category: integration-issues
module: github-actions, terraform, doppler
