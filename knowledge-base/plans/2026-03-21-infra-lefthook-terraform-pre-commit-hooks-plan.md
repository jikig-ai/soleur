---
title: "infra: add Lefthook pre-commit hooks for Terraform"
type: feat
date: 2026-03-21
---

# infra: Add Lefthook Pre-Commit Hooks for Terraform

## Overview

Add `terraform fmt` auto-formatting and optionally `tflint` linting to the existing `lefthook.yml` for pre-commit validation of `.tf` files. Deferred from #973 (Terraform state migration plan, Phase 4 item 2).

## Problem Statement

Terraform files in `apps/*/infra/` have no pre-commit formatting or linting enforcement. Developers can commit misformatted `.tf` files that drift from the canonical format. The parent plan (#973) deferred this to a follow-up issue to keep the state migration scope small.

## Proposed Solution

### Phase 1: Add `terraform-fmt` Hook

Add a `terraform-fmt` command to `lefthook.yml` that auto-formats staged `.tf` files and re-stages them. This mirrors the existing `rust-format` pattern (auto-fix + `stage_fixed: true`).

**`lefthook.yml`** -- add after `plugin-component-test` (priority 7):

```yaml
terraform-fmt:
  priority: 7
  glob: "apps/*/infra/**/*.tf"
  run: terraform fmt {staged_files}
  stage_fixed: true
```

Design decisions:

- **Auto-format, not check-only.** The issue title says `-check`, but the existing lefthook pattern (rust-format) auto-fixes and re-stages. Auto-format is strictly better for pre-commit: it fixes the problem instead of just complaining. Reserve `-check` for CI where auto-fix is not appropriate.
- **`glob: "apps/*/infra/**/*.tf"`** scopes to actual Terraform directories. Using `"*.tf"` would scan the entire repo tree unnecessarily.
- **`stage_fixed: true`** re-stages auto-formatted files so the commit includes the fix.
- **`{staged_files}`** passes individual staged `.tf` files to `terraform fmt`, which accepts file paths (confirmed via `terraform fmt -help`).

### Phase 2: Optionally Add `tflint` Hook (Conditional)

`tflint` is not installed on this machine. Adding a `tflint` hook is valuable but creates a dependency that every committer must satisfy. Two options:

**Option A (recommended): Skip tflint for now.** `terraform fmt` covers formatting. Linting can be added to CI (where `tflint` installation is controlled) without requiring every developer to install it locally. File a follow-up issue for CI `tflint`.

**Option B: Add tflint with graceful skip.** If `tflint` is desired in pre-commit, use `lefthook`'s `skip` mechanism or a wrapper script:

```yaml
terraform-tflint:
  priority: 8
  glob: "apps/*/infra/**/*.tf"
  run: |
    if command -v tflint >/dev/null 2>&1; then
      tflint --chdir=apps/telegram-bridge/infra && tflint --chdir=apps/web-platform/infra
    else
      echo "tflint not installed, skipping (install: https://github.com/terraform-linters/tflint)"
    fi
```

Caveat: `tflint` operates on directories (not individual files), so `{staged_files}` is not useful. The hook would need to run against each infra directory, not per-file.

### Phase 3: Verify and Document

- Run `lefthook run pre-commit` to verify the new hook works.
- Confirm `terraform fmt` is available in the environment (already confirmed: Terraform v1.10.5 at `~/.local/bin/terraform`).

## Non-Goals

- **`terraform validate`**: Excluded from pre-commit because it requires `terraform init` first (downloads providers, needs backend credentials). Leave to CI.
- **CI `terraform plan` workflow**: Separate issue (Phase 4 item 1 from #973).
- **Drift detection**: Separate issue (Phase 4 item 3 from #973).
- **`tflint` installation or configuration**: If Option A is chosen, tflint is deferred entirely.

## Technical Considerations

### Lefthook Glob Behavior

Lefthook's `glob` field filters staged files by pattern. `apps/*/infra/**/*.tf` matches all `.tf` files under any app's infra directory. If no staged files match the glob, the hook is skipped entirely (zero overhead for non-Terraform commits).

### `terraform fmt` on Individual Files

`terraform fmt` accepts file paths as arguments (not just directories). This works correctly with lefthook's `{staged_files}` expansion. Each staged `.tf` file is formatted independently -- no need to run against the entire directory.

### Priority Ordering

Current priorities: rust-format (1), rust-lint-fix (2), rust-lint-check (3), markdown-lint (4), bun-test (5), plugin-component-test (6). Terraform formatting is fast and independent -- priority 7 places it after existing hooks. If `parallel: true` were ever enabled, priority would matter less.

## Acceptance Criteria

- [ ] `lefthook.yml` contains a `terraform-fmt` command with `glob: "apps/*/infra/**/*.tf"`
- [ ] Staging a misformatted `.tf` file and committing results in auto-formatting and clean commit
- [ ] Non-Terraform commits are not affected (hook skips when no `.tf` files are staged)
- [ ] `lefthook run pre-commit` passes with no errors when `.tf` files are already formatted

## Test Scenarios

- Given a correctly formatted `.tf` file is staged, when committing, then the terraform-fmt hook passes with no changes
- Given a misformatted `.tf` file is staged (extra whitespace, wrong indentation), when committing, then `terraform fmt` auto-formats it and `stage_fixed: true` re-stages the corrected file
- Given only `.md` files are staged, when committing, then the terraform-fmt hook is skipped entirely
- Given `terraform` is not installed, when committing a `.tf` file, then the hook fails with a clear error (lefthook does not suppress command-not-found errors)

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `terraform` not in PATH for other developers | Low | Medium (hook fails) | Document requirement; `terraform` is already required for infra work |
| Glob pattern mismatch | Low | Low (hook skips valid files) | Tested against actual file paths in repo |
| `stage_fixed` conflict with other hooks | Very Low | Low | Terraform-fmt runs after all other hooks (priority 7) |

## Semver

`semver:patch` -- configuration-only change to an existing hook file, no new features or breaking changes.

## References

### Internal

- Parent plan: `knowledge-base/plans/2026-03-21-feat-terraform-state-r2-migration-plan.md` (Phase 4 item 2)
- Existing lefthook config: `lefthook.yml`
- Terraform files: `apps/telegram-bridge/infra/*.tf`, `apps/web-platform/infra/*.tf`
- Learning: `knowledge-base/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` (notes pre-existing fmt issue)

### External

- [Lefthook documentation](https://github.com/evilmartians/lefthook)
- [Terraform fmt command](https://developer.hashicorp.com/terraform/cli/commands/fmt)
- [tflint](https://github.com/terraform-linters/tflint)

Closes #976
