---
title: Doppler service token config scope mismatch in CI
date: 2026-03-29
category: engineering
tags: [doppler, ci, github-actions, service-tokens, secrets]
symptoms: [doppler run -c prd fails with 403 or token scope error, CI workflow step cannot access secrets from expected Doppler config, Doppler CLI ignores DOPPLER_CONFIG env var in CI]
module: System
component: ci_cd
problem_type: best_practice
resolution_type: prevention_strategy
root_cause: config_mismatch
severity: high
---

# Learning: Doppler service token config scope mismatch in CI

> **CORRECTION (2026-08-04, #7234) — `-c` IS NOT IGNORED FOR `doppler secrets` /
> `doppler secrets get`, AND THIS PAGE'S ADVICE TO DROP IT IS WRONG FOR THAT VERB.**
> This page says a config-scoped token makes `-c` a no-op ("the token's built-in scope
> wins") and, in §3 below, tells you to remove the config from the invocation. Measured
> against live Doppler on both `main` and the #7234 branch, with CLI v3.75.3: a
> config-scoped service token given a MISMATCHED `-c` **errors** — it does not silently
> serve its own config's value. A MATCHING `-c` succeeds normally.
>
> That distinction is load-bearing rather than academic. `scripts/check-cloudflare-token-drift.sh`
> holds one config-scoped read token per config and passes `-p`/`-c` on every read
> **because** the mismatch errors: the read is the binding control, which is why the
> scan needs no self-identification probe (there isn't one that works — `doppler me --json`
> returns the CALLER-SUPPLIED name). Following §3's advice there would delete the only
> thing that detects a mis-bound token, turning a loud failed read into a confident wrong
> answer. See
> [ADR-168](../../engineering/architecture/decisions/ADR-168-per-config-read-tokens-for-the-token-drift-scan.md).
>
> What this page still gets right: service tokens are scoped to one project+config at
> creation, a generic `DOPPLER_TOKEN` secret name hides that scope, and pointing one at
> the wrong config fails. Only the *mechanism* was wrong — it fails **loudly on the flag**,
> not by silently ignoring it. The `doppler run` claim below has NOT been re-measured; the
> #7234 probes covered `doppler secrets --only-names` and `doppler secrets get`. Do not
> generalise either direction without measuring the verb you actually call.

## Problem

A GitHub Actions workflow used `doppler run -c prd` but the `DOPPLER_TOKEN` GitHub
secret contained a service token scoped to a different config (e.g., `prd_terraform`
or `ci`). Doppler service tokens are scoped to exactly one project+config at creation
time. The token's built-in scope is what it can reach, so naming a different config
fails -- see the correction above for how it fails per verb (`doppler secrets get`
errors on the mismatch rather than ignoring the flag).

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

> **SCOPE OF THIS ADVICE (see the correction at the top).** It applies to the
> AMBIENT `DOPPLER_PROJECT` / `DOPPLER_CONFIG` **env vars** in a workflow `env:` block,
> where they imply a configurability the token does not have. It does **not** apply to an
> EXPLICIT `-p`/`-c` on a `doppler secrets` / `doppler secrets get` call: there the
> mismatch errors, which makes the flag a binding assertion worth keeping. Do not read
> this section as "drop `-c`" —
> `scripts/check-cloudflare-token-drift.sh` depends on that error being reachable, and
> deliberately UNSETS the ambient vars so every read must name its config.

When using service tokens, do NOT set `DOPPLER_PROJECT` or `DOPPLER_CONFIG` as env
vars alongside `DOPPLER_TOKEN`. These env vars suggest the config is freely
configurable, when the token can only ever reach the one it was scoped to. Instead, let
the service token's built-in scope determine the config, and document the scope in a
comment:

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
