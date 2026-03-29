---
module: System
date: 2026-03-29
problem_type: best_practice
component: ci_cd
symptoms:
  - "doppler run -c prd fails with 403 or token scope error"
  - "CI workflow step cannot access secrets from expected Doppler config"
  - "Doppler CLI ignores DOPPLER_CONFIG env var in CI"
root_cause: config_mismatch
resolution_type: prevention_strategy
severity: high
tags: [doppler, ci, github-actions, service-tokens, secrets]
---

# Learning: Doppler service token config scope mismatch in CI

## Problem

A GitHub Actions workflow used `doppler run -c prd` but the `DOPPLER_TOKEN` GitHub
secret contained a service token scoped to a different config (e.g., `prd_terraform`
or `ci`). Doppler service tokens are scoped to exactly one project+config at creation
time. The `-c prd` flag and `DOPPLER_CONFIG` env var are ignored when the CLI
authenticates with a service token -- the token's built-in scope wins. This always
fails silently or with a cryptic 403.

## Root Cause

Doppler has two token types with different scoping behavior:

1. **Personal/CLI tokens** -- project-wide; `-c <config>` and `DOPPLER_CONFIG` work
2. **Service tokens** -- scoped to exactly one project+config at creation; CLI flags
   for project/config are ignored

CI workflows use service tokens (the only non-interactive option). When the GitHub
secret name is generic (`DOPPLER_TOKEN`), nothing in the workflow communicates which
config the token is scoped to. A developer adding `doppler run -c prd` sees the
generic secret name, assumes it works for any config, and ships a broken workflow.

## Prevention Strategy

### 1. Naming convention: config-specific GitHub secret names

Use suffixed secret names that encode the Doppler config scope:

| GitHub Secret Name         | Doppler Config   | Used By                        |
|----------------------------|------------------|--------------------------------|
| `DOPPLER_TOKEN_PRD`        | `prd`            | web-platform-release (migrate) |
| `DOPPLER_TOKEN_PRD_TF`    | `prd_terraform`  | infra-validation, drift check  |
| `DOPPLER_TOKEN_SCHEDULED`  | `prd_scheduled`  | community-monitor              |
| `DOPPLER_TOKEN_CI`         | `ci`             | CI jobs needing ci config      |

The suffix makes the scope visible at the point of use. `DOPPLER_TOKEN` (bare) should
not exist -- it hides which config the token actually accesses.

### 2. Validation pattern: verify token scope before deploying workflows

Before adding or changing a `DOPPLER_TOKEN_*` reference in a workflow, verify the
token's scope matches the intended config:

```bash
# From a machine with the service token value:
DOPPLER_TOKEN="<token-value>" doppler secrets --only-names 2>&1 | head -5

# The output header shows the actual project+config:
#   NAME
#   ----
# If it errors: token is expired or scoped to a different config
```

For new tokens, create them with explicit config scope:

```bash
doppler configs tokens create \
  --project soleur \
  --config prd \
  --name "github-actions-prd" \
  --plain
```

Then store in GitHub with the config-specific name:

```bash
gh secret set DOPPLER_TOKEN_PRD --body "<token-value>"
```

### 3. Remove misleading DOPPLER_PROJECT/DOPPLER_CONFIG env vars

When using service tokens, do NOT set `DOPPLER_PROJECT` or `DOPPLER_CONFIG` as env
vars alongside `DOPPLER_TOKEN`. These env vars suggest the config is configurable,
but service tokens ignore them. Instead, let the service token's built-in scope
determine the config, and document the scope in a comment:

```yaml
# WRONG -- misleading; DOPPLER_CONFIG is ignored with service tokens
env:
  DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
  DOPPLER_PROJECT: soleur
  DOPPLER_CONFIG: prd_terraform

# RIGHT -- secret name encodes scope; no misleading env vars
env:
  DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD_TF }}  # scoped to prd_terraform
```

### 4. PR checklist item

When adding `doppler run -c <config>` or `doppler secrets get` to a workflow:

- [ ] GitHub secret name includes config suffix (e.g., `DOPPLER_TOKEN_PRD`)
- [ ] Service token was created with `--config <config>` matching the workflow usage
- [ ] No `DOPPLER_PROJECT`/`DOPPLER_CONFIG` env vars set alongside service token
- [ ] Tested with `doppler secrets --only-names` using the actual token value

## Current State (audit)

| Workflow                         | Secret Used            | Actual Config  | Status      |
|----------------------------------|------------------------|----------------|-------------|
| `web-platform-release.yml`       | `DOPPLER_TOKEN_PRD`    | `prd`          | Correct     |
| `scheduled-community-monitor.yml`| `DOPPLER_TOKEN_SCHEDULED` | `prd_scheduled` | Correct  |
| `scheduled-terraform-drift.yml`  | `DOPPLER_TOKEN`        | `prd_terraform`| Ambiguous   |
| `infra-validation.yml`           | `DOPPLER_TOKEN`        | `prd_terraform`| Ambiguous   |

The terraform workflows work today because `DOPPLER_TOKEN` happens to contain a
`prd_terraform`-scoped token. But the generic name is a trap -- if someone creates
a new workflow that references `DOPPLER_TOKEN` expecting `prd` access, it will fail.

**Recommended fix:** Rename `DOPPLER_TOKEN` to `DOPPLER_TOKEN_PRD_TF` in GitHub
secrets and update both terraform workflow files.

## Session Errors

1. **Stale bare-repo file read**: Read `.github/workflows/web-platform-release.yml` from the bare repo root, which showed an outdated version missing the `migrate` job entirely. Had to re-read via `git show main:` to get the actual current file. **Prevention:** Already covered by AGENTS.md Review & Feedback rule: "After merging a PR, always read files from the merged branch (using `git show main:<path>` or checking out the branch) rather than reading from the bare repo directory." This applies pre-merge too — always use `git show main:<path>` or read from the worktree, not the bare root.

## Key Insight

Doppler service tokens are config-specific credentials, not project-wide credentials.
The token name in GitHub must encode the config scope because the Doppler CLI provides
no guardrail -- it silently uses the token's built-in scope regardless of what `-c`,
`DOPPLER_PROJECT`, or `DOPPLER_CONFIG` specify. Generic names like `DOPPLER_TOKEN`
create a false sense of universality.

## Tags

category: integration-issues
module: github-actions, doppler, ci
