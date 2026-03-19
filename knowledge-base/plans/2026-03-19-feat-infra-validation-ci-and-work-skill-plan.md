---
title: "feat: add infrastructure validation to CI and work skill"
type: feat
date: 2026-03-19
semver: patch
---

# feat: Add Infrastructure Validation to CI and Work Skill

## Overview

Infrastructure files (`cloud-init.yml`, `*.tf`) in `apps/*/infra/` are currently unvalidated by CI and the agent work loop. A malformed cloud-init YAML or an unformatted Terraform file can merge silently, only discovered during a live deploy. This plan adds two complementary validation layers:

1. **GitHub Actions CI workflow** -- validates cloud-init YAML syntax, cloud-init schema, and `terraform fmt`/`terraform validate` on PRs touching `apps/*/infra/` files.
2. **Work skill Phase 2 infra-aware test rule** -- detects infrastructure file changes during agent work and runs config-specific validation (YAML syntax, cloud-init schema, `terraform fmt -check`, `terraform validate`) instead of only relying on the app test suite.

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

## Proposed Solution

### Component 1: GitHub Actions Workflow (`.github/workflows/infra-validation.yml`)

A new workflow triggered on PRs that modify files matching `apps/*/infra/**`. The workflow runs three validation steps per infra directory that has changed files.

**Trigger:**

```yaml
on:
  pull_request:
    paths:
      - "apps/*/infra/**"
  workflow_dispatch:
```

**Jobs:**

1. **detect-changes** -- Uses `tj-actions/changed-files` or `dorny/paths-filter` to determine which `apps/*/infra/` directories have changes. Outputs a JSON matrix of changed directories.

2. **validate** (matrix strategy on changed directories) -- For each changed infra directory:
   - **YAML lint**: Run `python3 -c "import yaml; yaml.safe_load(open('cloud-init.yml'))"` to validate YAML syntax. Lightweight, no extra deps.
   - **cloud-init schema**: Install `cloud-init` via apt, run `cloud-init schema -c cloud-init.yml`. Warnings about missing datasource are expected and suppressed (exit code is still 0 for valid schemas).
   - **terraform fmt**: Run `terraform fmt -check -recursive .` on the infra directory. Exit code 3 means formatting violations.
   - **terraform validate**: Run `terraform init -backend=false` then `terraform validate`. This catches HCL syntax errors and undefined variable references without provider credentials.

**Security comment header** (per constitution preference):

```yaml
# Security: No secrets required. All validation is offline (YAML parsing,
# cloud-init schema, terraform fmt/validate with -backend=false).
# Inputs: only paths from the PR diff (not user-controlled content).
```

**Key design decisions:**

- **Matrix strategy per infra dir**: Each app's infra is validated independently. A failure in telegram-bridge does not block web-platform validation results.
- **`workflow_dispatch` included**: Per constitution, new workflows start with `workflow_dispatch` for manual testing before PR triggers are relied upon.
- **No provider credentials needed**: `terraform init -backend=false` skips remote state and provider auth. `terraform validate` still catches syntax/reference errors.
- **`cloud-init` installed via apt**: Ubuntu runners include `cloud-init` in apt repositories. `sudo apt-get install -y cloud-init` in CI.
- **Terraform installed via `hashicorp/setup-terraform` action**: Standard pinned action for reproducible Terraform version.

**Edge cases:**

- **Terraform template variables in cloud-init.yml**: The `${image_name}` syntax in `cloud-init.yml` is valid YAML (unquoted `${...}` is a string literal in YAML). Python's `yaml.safe_load` and `cloud-init schema` both accept it. No preprocessing needed.
- **No `.terraform.lock.hcl`**: `telegram-bridge/infra/.gitignore` excludes the lockfile. `terraform init -backend=false` will download providers fresh in CI -- this is acceptable for validation-only runs and avoids requiring lockfiles to be committed.
- **New apps added later**: The `apps/*/infra/**` glob and dynamic directory detection automatically cover new apps without workflow changes.

### Component 2: Work Skill Phase 2 Infra-Aware Test Rule

Modify `plugins/soleur/skills/work/SKILL.md` Phase 2 section 5 ("Test Continuously") and the "Test-First Enforcement" note to add an infrastructure-aware validation path.

**Current text** (line 198):

> **Test-First Enforcement**: If the plan includes a "Test Scenarios" section, write tests for each scenario BEFORE writing implementation code. If no test scenarios exist in the plan, derive them from acceptance criteria. For infrastructure-only tasks (config, CI, scaffolding), tests may be skipped.

**Proposed replacement:**

> **Test-First Enforcement**: If the plan includes a "Test Scenarios" section, write tests for each scenario BEFORE writing implementation code. If no test scenarios exist in the plan, derive them from acceptance criteria. For infrastructure-only tasks (config, CI, scaffolding), unit tests may be skipped, but config-specific validation is required -- see Infrastructure Validation below.

**New subsection after section 5 (or as part of section 5):**

Add an "Infrastructure Validation" block in the test loop that triggers when `git diff --name-only` shows changes to files matching `apps/*/infra/**`:

```text
**Infrastructure Validation**: When any task modifies files in `apps/*/infra/`, run these checks after each change (in addition to or instead of the app test suite):

1. **YAML syntax**: For each modified `*.yml` or `*.yaml` in the infra directory:
   `python3 -c "import yaml; yaml.safe_load(open('<file>'))"` -- catches indentation errors, invalid YAML constructs.

2. **cloud-init schema**: For each modified `cloud-init.yml`:
   `cloud-init schema -c <file>` -- validates against the cloud-init JSON schema. Warnings about missing datasource are expected; only errors are failures.

3. **Terraform format**: For each infra directory with modified `.tf` files:
   `terraform fmt -check <dir>` -- exit 0 means formatted; exit 3 means violations. Fix with `terraform fmt <dir>`.

4. **Terraform validate**: For each infra directory with modified `.tf` files:
   `terraform init -backend=false` then `terraform validate` -- catches HCL syntax errors and undefined references without requiring provider credentials.

These checks replace the "tests may be skipped" exemption for infra files. If any check fails, fix before proceeding to the next task.
```

**Key design decisions:**

- **Detection via git diff**: The work skill already has access to `git diff` for various checks. Adding a path-based heuristic (`apps/*/infra/`) is consistent.
- **Not a subagent**: These are deterministic shell commands with binary pass/fail outcomes -- per constitution, prefer inline instructions over Task agents for such checks.
- **Complements CI, not replaces it**: CI catches issues on PRs. The work skill catches issues during development, providing faster feedback before push.

## Acceptance Criteria

- [ ] New workflow `.github/workflows/infra-validation.yml` exists and passes on PRs with valid infra files
- [ ] Workflow detects which `apps/*/infra/` directories have changes and validates only those
- [ ] YAML syntax check catches malformed `cloud-init.yml` (e.g., bad indentation)
- [ ] cloud-init schema check catches invalid cloud-init directives (e.g., unknown top-level key)
- [ ] `terraform fmt -check` catches unformatted `.tf` files (currently `dns.tf` would fail)
- [ ] `terraform validate` catches HCL syntax errors (e.g., undefined variable references)
- [ ] Workflow includes `workflow_dispatch` trigger for manual testing
- [ ] Work skill SKILL.md Phase 2 includes infrastructure validation instructions
- [ ] Work skill infrastructure validation covers: YAML syntax, cloud-init schema, terraform fmt, terraform validate
- [ ] Work skill detects infra file changes via `git diff --name-only` path matching
- [ ] Existing `dns.tf` formatting issue is fixed (so the new CI passes on the same PR)

## Test Scenarios

- Given a PR that modifies `apps/web-platform/infra/cloud-init.yml` with valid YAML, when CI runs, then the YAML syntax and cloud-init schema checks pass
- Given a PR that modifies `apps/telegram-bridge/infra/server.tf` with invalid HCL syntax, when CI runs, then `terraform validate` fails and blocks merge
- Given a PR that modifies `.tf` files with inconsistent formatting, when CI runs, then `terraform fmt -check` reports the files and fails
- Given a PR that only modifies `plugins/soleur/` files (no infra changes), when CI runs, then `infra-validation.yml` does not trigger
- Given the work skill processes a task that edits `cloud-init.yml`, when Phase 2 test loop runs, then the agent executes YAML syntax + cloud-init schema checks
- Given the work skill processes a task that edits `.tf` files, when Phase 2 test loop runs, then the agent runs `terraform fmt -check` and `terraform validate`
- Given a PR modifies infra in both `telegram-bridge` and `web-platform`, when CI runs, then both directories are validated independently via matrix strategy

## Technical Considerations

- **cloud-init availability in CI**: Ubuntu `ubuntu-latest` runners have `cloud-init` available via apt. No custom action needed.
- **Terraform version pinning**: Use `hashicorp/setup-terraform@v3` with a pinned version matching the project's `required_version = ">= 1.0"` constraint.
- **Terraform template variables**: `cloud-init.yml` files contain `${image_name}` Terraform template syntax. Both `yaml.safe_load` and `cloud-init schema` treat these as literal strings, not interpolation -- no preprocessing needed.
- **No provider credentials in CI**: `terraform init -backend=false` skips remote backend and provider download when lockfile exists. When lockfile is absent (telegram-bridge), providers download but no credentials are needed for `validate`.
- **Pre-existing `dns.tf` formatting**: `terraform fmt -check` on `apps/web-platform/infra/dns.tf` currently returns exit 3. This must be fixed in the same PR to avoid immediate CI failure.

## Dependencies & Risks

- **Risk**: `cloud-init schema` behavior may differ between Ubuntu versions. Mitigation: pin `ubuntu-latest` (currently 24.04) and test with `workflow_dispatch` before relying on PR triggers.
- **Risk**: `terraform validate` may require provider downloads that add latency. Mitigation: `terraform init -backend=false` only downloads providers, not state -- typically <10s per provider.
- **Dependency**: The PR must fix `dns.tf` formatting to pass the new CI check on the same PR.

## Implementation Sketch

### `.github/workflows/infra-validation.yml`

```yaml
# Security: No secrets required. All validation is offline.
# Inputs: only paths from the PR diff (not user-controlled content).
name: Infra Validation

on:
  pull_request:
    paths:
      - "apps/*/infra/**"
  workflow_dispatch:

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      directories: # JSON array of changed infra dirs
    steps:
      - uses: actions/checkout@v4
      - name: Find changed infra directories
        id: dirs
        # Extract unique apps/*/infra/ prefixes from changed files
        run: |
          # For PRs: diff against base
          # For workflow_dispatch: validate all infra dirs
          ...

  validate:
    needs: detect-changes
    if: needs.detect-changes.outputs.directories != '[]'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        directory: # fromJSON(needs.detect-changes.outputs.directories)
      fail-fast: false
    steps:
      - uses: actions/checkout@v4
      - name: YAML syntax check
        run: python3 -c "import yaml; yaml.safe_load(open('cloud-init.yml'))"
        working-directory: # matrix.directory
      - name: cloud-init schema
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq cloud-init
          cloud-init schema -c cloud-init.yml 2>&1 | grep -v WARNING || true
          cloud-init schema -c cloud-init.yml
        working-directory: # matrix.directory
      - uses: hashicorp/setup-terraform@v3
      - name: terraform fmt
        run: terraform fmt -check -recursive .
        working-directory: # matrix.directory
      - name: terraform validate
        run: |
          terraform init -backend=false
          terraform validate
        working-directory: # matrix.directory
```

### Work Skill SKILL.md Modification

Edit the Phase 2 "Test-First Enforcement" note and add an "Infrastructure Validation" subsection after section 5.

### `apps/web-platform/infra/dns.tf` Fix

Run `terraform fmt` to fix the existing formatting issue so CI passes on the PR that introduces the workflow.

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

### External

- [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform) -- GitHub Action for Terraform CLI
- [cloud-init schema validation](https://cloudinit.readthedocs.io/en/latest/reference/cli.html#schema) -- cloud-init CLI schema subcommand
- [terraform fmt](https://developer.hashicorp.com/terraform/cli/commands/fmt) -- Terraform format check
- [terraform validate](https://developer.hashicorp.com/terraform/cli/commands/validate) -- Terraform syntax validation
