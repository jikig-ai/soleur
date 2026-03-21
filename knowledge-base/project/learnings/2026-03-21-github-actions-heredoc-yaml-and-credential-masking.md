# Learning: HEREDOC in YAML `run: |` Blocks and Credential Masking in GitHub Actions

## Problem

### 1. HEREDOC content breaks YAML `run: |` block parsing

When writing a GitHub Actions workflow step that constructs a multi-line string using a bash HEREDOC inside a `run: |` block, flush-left HEREDOC content causes YAML parsing failures. YAML's `|` (literal block scalar) determines indentation from the first content line -- all subsequent lines must match or exceed that indent level. A HEREDOC body written at column 0 violates this rule, producing a syntax error that GitHub Actions surfaces as an unhelpful "workflow is not valid" message.

```yaml
# BROKEN -- HEREDOC body at column 0 breaks YAML indentation
- name: Create issue body
  run: |
    cat <<'EOF' > /tmp/body.md
    ## Drift Detected
    Stack: $STACK_NAME
    EOF
    gh issue create --body-file /tmp/body.md
```

### 2. `hashicorp/setup-terraform` wrapper swallows exit code 2

`terraform plan -detailed-exitcode` returns exit code 2 when drift is detected (changes present but no errors). The `hashicorp/setup-terraform` action installs a wrapper script that normalizes all non-zero exit codes to 1. This makes drift detection impossible -- exit code 2 is silently converted to 1, which looks like a plan error rather than detected drift.

### 3. Doppler-fetched secrets not masked in logs

Secrets retrieved via `doppler secrets get --plain` and written to `$GITHUB_ENV` are not automatically masked by GitHub Actions. Only values passed through the `secrets.*` context are auto-masked. Any Doppler-fetched credential that appears in a subsequent step's log output (e.g., in a `terraform init` debug line) will be printed in plaintext.

### 4. `gh issue list --search` uses fuzzy matching

GitHub's issue search API performs fuzzy text matching. When searching for `"[Drift] telegram-bridge"`, results can include issues titled `"[Drift] web-platform"` because the search scores partial matches. Using `--jq 'select(.title == "...")'` for exact filtering compensates, but the initial `--search` result set may still be unreliable for programmatic use.

## Solution

### 1. Replace inline HEREDOC with `echo` + `--body-file`

Avoid HEREDOC entirely inside `run: |` blocks. Write content line-by-line with `printf` or `echo`, then reference the file.

```yaml
- name: Create issue body
  run: |
    printf '## Drift Detected\n\nStack: %s\n' "$STACK_NAME" > /tmp/body.md
    gh issue create --body-file /tmp/body.md
```

### 2. Disable the Terraform wrapper

```yaml
- uses: hashicorp/setup-terraform@v4
  with:
    terraform_wrapper: false
```

This is mandatory whenever exit codes matter -- drift detection, `plan -detailed-exitcode`, or any conditional logic based on `terraform` return values.

### 3. Mask secrets immediately after fetching

Call `::add-mask::` before writing to `$GITHUB_ENV`.

```bash
KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID --plain)
SECRET=$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain)
printf '::add-mask::%s\n' "$KEY_ID"
printf '::add-mask::%s\n' "$SECRET"
printf 'AWS_ACCESS_KEY_ID=%s\n' "$KEY_ID" >> "$GITHUB_ENV"
printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$SECRET" >> "$GITHUB_ENV"
```

The `::add-mask::` must come before any line that could expose the value -- including the `>> "$GITHUB_ENV"` write itself if `set -x` is enabled.

### 4. Use `--limit` with exact `--jq` filtering instead of `--search`

```bash
gh issue list --label "drift" --state open --limit 100 \
  --json number,title \
  --jq '.[] | select(.title == "[Drift] telegram-bridge") | .number'
```

This avoids fuzzy matching entirely. The `--limit 100` upper bound is sufficient for any reasonable number of open drift issues.

## Key Insight

YAML block scalars (`|`, `>`) impose indentation rules that conflict with bash HEREDOC syntax. This is not a GitHub Actions bug -- it is a fundamental YAML constraint. Any tool that embeds shell scripts in YAML (GitHub Actions, GitLab CI, Ansible) will hit the same issue. The reliable pattern is: write multi-line content to a temp file with `printf`/`echo`, then reference the file. This also applies to `$GITHUB_OUTPUT` HEREDOC delimiters (covered in the 2026-03-21-ci-terraform-plan-workflow learning).

For credential masking: the rule is simple -- if a secret did not come from `${{ secrets.* }}`, it is NOT masked. Every CLI-fetched secret needs an explicit `::add-mask::` call. Audit every workflow step that fetches secrets from external sources (Doppler, Vault, AWS SSM, 1Password CLI) for this gap.

## Session Errors

- HEREDOC inside YAML `run: |` block caused workflow parse failure on first write attempt
- PreToolUse security hook rejected `${{ }}` expressions in `run:` blocks (correctly -- these need to be in `env:` mappings or escaped)
- Worktree `.worktrees/fix-drift-review-findings` was removed mid-session by `cleanup-merged` after PR #979 merged; had to recreate
- Shell CWD drifted to a Terraform directory after running `terraform validate`, causing subsequent git commands to fail until CWD was reset
- Missing `::add-mask::` for Doppler-fetched R2 credentials caught by review agents during PR review -- pattern existed in `infra-validation.yml` but was not carried over to the drift workflow

## Tags

category: integration-issues
module: github-actions, terraform, doppler
