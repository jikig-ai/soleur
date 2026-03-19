---
title: "feat: add infrastructure validation to CI and work skill"
type: feat
date: 2026-03-19
semver: patch
---

# feat: Add Infrastructure Validation to CI and Work Skill

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 6 (Proposed Solution, Technical Considerations, Dependencies & Risks, Implementation Sketch, Edge Cases, Acceptance Criteria)
**Research sources:** GitHub runner image inventory, `hashicorp/setup-terraform` API, 5 institutional learnings, Terraform best practices doc, `cloud-init schema` local testing

### Key Improvements

1. **SHA-pinned action references** -- all actions use commit SHA with version comment, consistent with existing workflow conventions (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`, `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0`)
2. **cloud-init NOT pre-installed on ubuntu-24.04 runners** -- explicit `apt-get install` required; PyYAML also not pre-installed but comes as a transitive dependency of `cloud-init`
3. **Simplified YAML check** -- `cloud-init schema` performs YAML parsing as its first step; separate PyYAML check is redundant for `cloud-init.yml` files. Replaced with a single `cloud-init schema` step that covers both syntax and schema validation.
4. **Pure-bash directory detection** -- avoids third-party actions (`tj-actions/changed-files`, `dorny/paths-filter`) that introduce supply-chain risk; uses `git diff --name-only` with shell extraction instead
5. **GITHUB_OUTPUT sanitization** -- directory paths written to `$GITHUB_OUTPUT` use `printf '%s\n'` pattern per institutional learning on newline injection

### New Considerations Discovered

- `hashicorp/setup-terraform` latest is **v4.0.0** (not v3 as originally sketched)
- The `security_reminder_hook.py` PreToolUse hook will block the first Edit to `.github/workflows/*.yml` -- the implementer should expect a retry on first edit (documented in `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`)
- `telegram-bridge/infra/.gitignore` excludes `.terraform.lock.hcl` -- `terraform init -backend=false` will download providers fresh each CI run (~5-10s)

## Overview

Infrastructure files (`cloud-init.yml`, `*.tf`) in `apps/*/infra/` are currently unvalidated by CI and the agent work loop. A malformed cloud-init YAML or an unformatted Terraform file can merge silently, only discovered during a live deploy. This plan adds two complementary validation layers:

1. **GitHub Actions CI workflow** -- validates cloud-init schema (which includes YAML syntax) and `terraform fmt`/`terraform validate` on PRs touching `apps/*/infra/` files.
2. **Work skill Phase 2 infra-aware test rule** -- detects infrastructure file changes during agent work and runs config-specific validation (cloud-init schema, `terraform fmt -check`, `terraform validate`) instead of only relying on the app test suite.

## Problem Statement

The work skill's Phase 2 test loop currently says: "For infrastructure-only tasks (config, CI, scaffolding), tests may be skipped." This means cloud-init YAML typos, Terraform formatting violations, and schema errors pass through the agent workflow unchecked. CI (`ci.yml`) only runs `bun test` -- it has no infrastructure-specific validation.

Evidence of the gap:
- `apps/web-platform/infra/dns.tf` currently fails `terraform fmt -check` (exit code 3) -- this was never caught.
- The SSH hardening plan (`2026-03-19-security-harden-sshd-config-plan.md`) modified `cloud-init.yml` without any automated schema validation.
- Constitution already recommends SpecFlow analysis on infrastructure changes, but has no enforcement.

## Non-Goals

- **Remote Terraform state validation** -- validating against a remote backend or real provider credentials is out of scope. CI uses `terraform init -backend=false` and validates syntax/structure only.
- **Full cloud-init integration testing** -- we validate YAML syntax and cloud-init schema only, not runtime behavior.
- **Terraform plan** -- `terraform plan` requires provider credentials. Only `fmt -check` and `validate` are in scope for CI.
- **Modifying compound or ship skills** -- only the work skill's Phase 2 test loop is modified.
- **Auto-fixing formatting** -- CI reports errors; developers fix them. No `terraform fmt -write` in CI.
- **Committing `.terraform.lock.hcl` for telegram-bridge** -- that gitignore decision is a separate concern; the workflow handles missing lockfiles gracefully.

## Proposed Solution

### Component 1: GitHub Actions Workflow (`.github/workflows/infra-validation.yml`)

A new workflow triggered on PRs that modify files matching `apps/*/infra/**`. The workflow runs validation steps per infra directory that has changed files.

**Trigger:**

```yaml
on:
  pull_request:
    paths:
      - "apps/*/infra/**"
  workflow_dispatch:
```

**Jobs:**

1. **detect-changes** -- Uses pure bash with `git diff --name-only` to determine which `apps/*/infra/` directories have changes. Outputs a JSON matrix of changed directories. For `workflow_dispatch`, discovers all infra dirs via `find`.

2. **validate** (matrix strategy on changed directories) -- For each changed infra directory:
   - **cloud-init schema**: Install `cloud-init` via apt (NOT pre-installed on `ubuntu-24.04` runners), run `cloud-init schema -c cloud-init.yml`. This validates both YAML syntax and cloud-init schema in a single step. Warnings about missing datasource are expected (exit code remains 0 for valid schemas).
   - **terraform fmt**: Run `terraform fmt -check -recursive .` on the infra directory. Exit code 3 means formatting violations.
   - **terraform validate**: Run `terraform init -backend=false` then `terraform validate`. This catches HCL syntax errors and undefined variable references without provider credentials.

### Research Insights: CI Workflow

**Supply-chain security (from institutional learnings):**
- Pin ALL action references to commit SHAs with version comments -- mutable tags are a supply-chain risk (ref: `2026-02-27-github-actions-sha-pinning-workflow.md`, tj-actions/changed-files compromise March 2025)
- Avoid third-party change detection actions (`tj-actions/changed-files`, `dorny/paths-filter`) -- use `git diff` directly to minimize attack surface. The `tj-actions/changed-files` action was specifically compromised in 2025.
- Use `printf '%s\n'` instead of `echo` for `$GITHUB_OUTPUT` writes, and always quote `"$GITHUB_OUTPUT"` (ref: `2026-03-05-github-output-newline-injection-sanitization.md`)

**Runner environment findings:**
- `ubuntu-latest` (24.04) does NOT have `cloud-init` pre-installed -- requires explicit `sudo apt-get install -y cloud-init`
- `python3` IS pre-installed (3.12.3) but PyYAML is NOT -- however, `cloud-init` depends on `python3-yaml`, so installing `cloud-init` provides PyYAML as a transitive dependency
- This means the separate `python3 -c "import yaml; ..."` YAML syntax check is redundant -- `cloud-init schema` performs YAML parsing as its first validation step. Removing the separate step simplifies the workflow.

**Terraform action pinning:**
- `hashicorp/setup-terraform` latest stable is **v4.0.0** (SHA: `5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85`)
- `actions/checkout` is consistently pinned to `34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1) across all existing workflows

**Security comment header** (per constitution preference):

```yaml
# Security: No secrets required. All validation is offline (cloud-init schema,
# terraform fmt/validate with -backend=false).
# Inputs: only paths from the PR diff (not user-controlled content).
# All action references are SHA-pinned.
```

**Key design decisions:**

- **Matrix strategy per infra dir**: Each app's infra is validated independently. A failure in telegram-bridge does not block web-platform validation results.
- **`workflow_dispatch` included**: Per constitution, new workflows start with `workflow_dispatch` for manual testing before PR triggers are relied upon.
- **No provider credentials needed**: `terraform init -backend=false` skips remote state and provider auth. `terraform validate` still catches syntax/reference errors.
- **`cloud-init` installed via apt**: Ubuntu runners have `cloud-init` in apt repositories. `sudo apt-get install -y -qq cloud-init` in CI.
- **Terraform installed via `hashicorp/setup-terraform` action**: SHA-pinned for supply-chain security.
- **Pure bash change detection**: No third-party actions for detecting changed files -- `git diff --name-only` with shell pipeline extraction is sufficient and avoids supply-chain risk from the `tj-actions` compromise precedent.

**Edge cases:**

- **Terraform template variables in cloud-init.yml**: The `${image_name}` syntax in `cloud-init.yml` is valid YAML (unquoted `${...}` is a string literal in YAML). `cloud-init schema` accepts it without errors. Verified locally on both `apps/web-platform/infra/cloud-init.yml` and `apps/telegram-bridge/infra/cloud-init.yml`.
- **No `.terraform.lock.hcl`**: `telegram-bridge/infra/.gitignore` excludes the lockfile. `terraform init -backend=false` will download providers fresh in CI (~5-10s per provider). This is acceptable for validation-only runs.
- **New apps added later**: The `apps/*/infra/**` glob and dynamic directory detection automatically cover new apps without workflow changes.
- **`workflow_dispatch` with no changes**: When triggered manually, the workflow discovers ALL `apps/*/infra/` directories via `find` instead of `git diff`, validating everything.
- **cloud-init `schema` exit code**: `cloud-init schema` returns exit 0 for valid configs even with WARNING-level messages about missing datasource. The workflow should check exit code, not parse stderr.
- **Multiple matrix runners**: Each matrix job installs `cloud-init` and `terraform` independently. This adds ~15s per matrix entry but avoids cross-job state issues.

### Component 2: Work Skill Phase 2 Infra-Aware Test Rule

Modify `plugins/soleur/skills/work/SKILL.md` Phase 2 section 5 ("Test Continuously") and the "Test-First Enforcement" note to add an infrastructure-aware validation path.

**Current text** (line 198):

> **Test-First Enforcement**: If the plan includes a "Test Scenarios" section, write tests for each scenario BEFORE writing implementation code. If no test scenarios exist in the plan, derive them from acceptance criteria. For infrastructure-only tasks (config, CI, scaffolding), tests may be skipped.

**Proposed replacement:**

> **Test-First Enforcement**: If the plan includes a "Test Scenarios" section, write tests for each scenario BEFORE writing implementation code. If no test scenarios exist in the plan, derive them from acceptance criteria. For infrastructure-only tasks (config, CI, scaffolding), unit tests may be skipped, but config-specific validation is required -- see Infrastructure Validation below.

**New subsection after section 5 ("Test Continuously"), as section 5b:**

Add an "Infrastructure Validation" block that triggers when `git diff --name-only` shows changes to files matching `apps/*/infra/**`:

```text
5b. **Infrastructure Validation**

   When any task modifies files in `apps/*/infra/`, run these checks after each change (in addition to or instead of the app test suite):

   1. **cloud-init schema**: For each modified `cloud-init.yml`:
      `cloud-init schema -c <file>` -- validates YAML syntax AND cloud-init schema in one step. Warnings about missing datasource are expected; only errors (non-zero exit) are failures.

   2. **Terraform format**: For each infra directory with modified `.tf` files:
      `terraform fmt -check <dir>` -- exit 0 means formatted; exit 3 means violations. Fix with `terraform fmt <dir>`.

   3. **Terraform validate**: For each infra directory with modified `.tf` files:
      `terraform init -backend=false` then `terraform validate` -- catches HCL syntax errors and undefined references without requiring provider credentials.

   These checks replace the "tests may be skipped" exemption for infra files. If any check fails, fix before proceeding to the next task.
```

### Research Insights: Work Skill Modification

**Pattern consistency:**
- The work skill already checks for UI file patterns in Phase 0.5 scope check 7 (`page.tsx`, `layout.tsx`, etc.) and routes to UX review. Adding infra file pattern detection (`apps/*/infra/**`) follows the same pattern.
- Per constitution: "Prefer inline instructions over Task agents for deterministic checks (shell commands with binary pass/fail outcomes)." These validation commands are deterministic -- no subagent needed.

**Skill-enforced convention pattern** (from `2026-03-19-skill-enforced-convention-pattern.md`):
- Constitution rules that require semantic judgment cannot use PreToolUse hooks. But infra validation is not semantic -- it's syntactic, using shell commands.
- This means the work skill change is enforcement via instruction, complementing the CI enforcement. Both layers are needed: CI catches issues at PR time, the work skill catches them during development.

**cloud-init availability on dev machines:**
- `cloud-init` is available on the developer's machine (verified: version 25.3). On machines without `cloud-init`, the work skill should degrade gracefully -- warn and continue rather than block.

## Acceptance Criteria

- [x] New workflow `.github/workflows/infra-validation.yml` exists and passes on PRs with valid infra files
- [x] All action references in the new workflow use SHA-pinned format (`@<sha> # vX.Y.Z`)
- [x] Workflow uses pure bash for change detection (no third-party `changed-files` actions)
- [x] Workflow detects which `apps/*/infra/` directories have changes and validates only those
- [x] `cloud-init schema` check validates both YAML syntax and schema in one step
- [x] `terraform fmt -check` catches unformatted `.tf` files (currently `dns.tf` would fail)
- [x] `terraform validate` catches HCL syntax errors (e.g., undefined variable references)
- [x] Workflow includes `workflow_dispatch` trigger for manual testing
- [x] Workflow `workflow_dispatch` validates ALL infra dirs (not just changed ones)
- [x] Work skill SKILL.md Phase 2 includes infrastructure validation instructions as section 5b
- [x] Work skill infrastructure validation covers: cloud-init schema, terraform fmt, terraform validate
- [x] Work skill detects infra file changes via `git diff --name-only` path matching
- [x] Existing `dns.tf` formatting issue is fixed (so the new CI passes on the same PR)
- [x] Security comment header present at top of workflow file

## Test Scenarios

- Given a PR that modifies `apps/web-platform/infra/cloud-init.yml` with valid YAML, when CI runs, then the cloud-init schema check passes
- Given a PR that introduces a cloud-init.yml with an unknown top-level key (e.g., `bogus_key: true`), when CI runs, then `cloud-init schema` reports an error and fails
- Given a PR that modifies `apps/telegram-bridge/infra/server.tf` with invalid HCL syntax, when CI runs, then `terraform validate` fails and blocks merge
- Given a PR that modifies `.tf` files with inconsistent formatting, when CI runs, then `terraform fmt -check` reports the files and fails
- Given a PR that only modifies `plugins/soleur/` files (no infra changes), when CI runs, then `infra-validation.yml` does not trigger
- Given `workflow_dispatch` is triggered manually, when the workflow runs, then ALL infra directories are validated (not just changed ones)
- Given the work skill processes a task that edits `cloud-init.yml`, when Phase 2 test loop runs, then the agent executes `cloud-init schema` check
- Given the work skill processes a task that edits `.tf` files, when Phase 2 test loop runs, then the agent runs `terraform fmt -check` and `terraform validate`
- Given a PR modifies infra in both `telegram-bridge` and `web-platform`, when CI runs, then both directories are validated independently via matrix strategy
- Given `cloud-init` is not installed on the dev machine, when the work skill runs infra validation, then it warns and continues (graceful degradation)

## Technical Considerations

- **cloud-init NOT pre-installed in CI**: Ubuntu `ubuntu-latest` (24.04) runners do NOT have `cloud-init` pre-installed. The workflow must `sudo apt-get install -y -qq cloud-init`. This also installs `python3-yaml` (PyYAML) as a transitive dependency.
- **Terraform action version**: Use `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0` (latest stable, SHA-pinned).
- **Checkout action**: Use `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` (consistent with all other workflows in the repo).
- **Terraform template variables**: `cloud-init.yml` files contain `${image_name}` Terraform template syntax. `cloud-init schema` treats these as literal strings -- verified locally on both existing cloud-init files. No preprocessing needed.
- **No provider credentials in CI**: `terraform init -backend=false` skips remote backend. When lockfile is absent (telegram-bridge), providers download but no credentials are needed for `validate`.
- **Pre-existing `dns.tf` formatting**: `terraform fmt -check` on `apps/web-platform/infra/dns.tf` currently returns exit 3. This must be fixed in the same PR to avoid immediate CI failure.
- **Security hook behavior**: The `security_reminder_hook.py` PreToolUse hook will block the first Edit attempt on `.github/workflows/*.yml` files. This is advisory, not blocking -- retry the edit. (Ref: `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`)
- **GITHUB_OUTPUT sanitization**: Directory paths written to `$GITHUB_OUTPUT` must use `printf '%s\n'` and `tr -d '\n\r'` to prevent injection. (Ref: `2026-03-05-github-output-newline-injection-sanitization.md`)

## Dependencies & Risks

- **Risk**: `cloud-init schema` behavior may differ between Ubuntu versions. Mitigation: pin to `ubuntu-24.04` explicitly (not `ubuntu-latest`) and test with `workflow_dispatch` before relying on PR triggers.
- **Risk**: `terraform validate` may require provider downloads that add latency. Mitigation: `terraform init -backend=false` only downloads providers, not state -- typically <10s per provider. Verified locally.
- **Risk**: `cloud-init` apt install adds ~5-10s to CI run time. Mitigation: acceptable for validation-only workflow that only triggers on infra changes.
- **Risk**: Developer machine may not have `cloud-init` installed. Mitigation: work skill should attempt the command and warn on failure, not block.
- **Dependency**: The PR must fix `dns.tf` formatting to pass the new CI check on the same PR.
- **Dependency**: Post-merge manual trigger (`gh workflow run infra-validation.yml`) required to verify the workflow works, per constitution gate.

## Implementation Sketch

### `.github/workflows/infra-validation.yml`

```yaml
# Security: No secrets required. All validation is offline (cloud-init schema,
# terraform fmt/validate with -backend=false).
# Inputs: only paths from the PR diff (not user-controlled content).
# All action references are SHA-pinned.
name: Infra Validation

on:
  pull_request:
    paths:
      - "apps/*/infra/**"
  workflow_dispatch:

jobs:
  detect-changes:
    runs-on: ubuntu-24.04
    outputs:
      directories: ${{ steps.dirs.outputs.directories }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0

      - name: Find changed infra directories
        id: dirs
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            # Manual trigger: validate ALL infra directories
            DIRS=$(find apps/*/infra -maxdepth 0 -type d 2>/dev/null | jq -R -s -c 'split("\n") | map(select(. != ""))')
          else
            # PR trigger: only changed directories
            DIRS=$(git diff --name-only origin/${{ github.base_ref }}...HEAD -- 'apps/*/infra/' \
              | sed 's|/[^/]*$||' \
              | sort -u \
              | jq -R -s -c 'split("\n") | map(select(. != ""))')
          fi
          printf 'directories=%s\n' "$DIRS" >> "$GITHUB_OUTPUT"

  validate:
    needs: detect-changes
    if: needs.detect-changes.outputs.directories != '[]'
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        directory: ${{ fromJSON(needs.detect-changes.outputs.directories) }}
      fail-fast: false

    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Validate cloud-init schema
        run: |
          if [[ -f cloud-init.yml ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq cloud-init 2>&1 | tail -1
            cloud-init schema -c cloud-init.yml
          else
            echo "No cloud-init.yml found, skipping"
          fi
        working-directory: ${{ matrix.directory }}

      - uses: hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0

      - name: Terraform format check
        run: terraform fmt -check -recursive .
        working-directory: ${{ matrix.directory }}

      - name: Terraform validate
        run: |
          terraform init -backend=false
          terraform validate
        working-directory: ${{ matrix.directory }}
```

### Work Skill SKILL.md Modification

Edit `plugins/soleur/skills/work/SKILL.md`:

1. **Line 198** -- Replace the "Test-First Enforcement" text to reference infra validation
2. **After section 5** -- Add section 5b "Infrastructure Validation" with the three check commands
3. Keep the text concise and actionable -- the agent follows inline instructions, not verbose documentation

### `apps/web-platform/infra/dns.tf` Fix

Run `terraform fmt apps/web-platform/infra/dns.tf` to fix the existing formatting issue so CI passes on the PR that introduces the workflow.

## References

### Internal

- `apps/telegram-bridge/infra/cloud-init.yml` -- cloud-init with Terraform template vars
- `apps/web-platform/infra/cloud-init.yml` -- cloud-init with `write_files` section
- `apps/web-platform/infra/main.tf` -- Terraform providers (hcloud, cloudflare)
- `apps/telegram-bridge/infra/main.tf` -- Terraform providers (hcloud only)
- `.github/workflows/ci.yml` -- existing CI workflow (bun test only)
- `plugins/soleur/skills/work/SKILL.md:198` -- current "tests may be skipped" exemption
- `knowledge-base/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` -- prior infra deployment learning
- `knowledge-base/project/learnings/integration-issues/2026-02-10-cloud-deploy-infra-and-sdk-integration.md` -- Terraform + cloud-init volume mount learning
- `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- workflow security patterns (SHA pinning, input validation)
- `knowledge-base/project/learnings/2026-02-27-github-actions-sha-pinning-workflow.md` -- SHA pinning audit process and tj-actions compromise precedent
- `knowledge-base/project/learnings/2026-03-05-github-output-newline-injection-sanitization.md` -- GITHUB_OUTPUT sanitization patterns
- `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md` -- security hook retry behavior for workflow edits
- `knowledge-base/learnings/2026-03-19-skill-enforced-convention-pattern.md` -- enforcement tier pattern for semantic vs syntactic rules
- `knowledge-base/project/learnings/2026-02-13-terraform-best-practices-research.md` -- Terraform module structure and best practices

### External

- [hashicorp/setup-terraform v4.0.0](https://github.com/hashicorp/setup-terraform) -- GitHub Action for Terraform CLI (SHA: `5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85`)
- [cloud-init schema validation](https://cloudinit.readthedocs.io/en/latest/reference/cli.html#schema) -- cloud-init CLI schema subcommand
- [terraform fmt](https://developer.hashicorp.com/terraform/cli/commands/fmt) -- Terraform format check
- [terraform validate](https://developer.hashicorp.com/terraform/cli/commands/validate) -- Terraform syntax validation
- [GitHub ubuntu-24.04 runner image](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) -- pre-installed packages reference
