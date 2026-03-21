---
title: "infra: add Lefthook pre-commit hooks for Terraform"
type: feat
date: 2026-03-21
---

# infra: Add Lefthook Pre-Commit Hooks for Terraform

## Enhancement Summary

**Deepened on:** 2026-03-21
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios)
**Research sources:** Lefthook GitHub docs (glob.md, stage_fixed.md, run.md, glob_matcher.md), Terraform fmt CLI help, repo file analysis

### Key Improvements

1. **Critical glob pattern fix**: `apps/*/infra/**/*.tf` does NOT match current `.tf` files with Lefthook's default `gobwas` glob matcher (`**` requires 1+ directories, but `.tf` files sit directly in `infra/`). Corrected to `apps/*/infra/*.tf`.
2. **Added `glob_matcher: doublestar` option** as future-proofing alternative if nested modules are introduced.
3. **Documented Lefthook command-length splitting behavior**: when many `.tf` files are staged, Lefthook splits `{staged_files}` into multiple sequential `terraform fmt` invocations to stay within OS command-line limits.

### New Considerations Discovered

- Pre-existing glob issue: `plugins/soleur/**/*.md` in current `lefthook.yml` also misses root-level `.md` files under `plugins/soleur/` due to same `**` behavior. Out of scope but worth a follow-up.
- Lefthook `stage_fixed` re-stages using the same glob filter applied to `{staged_files}`, so only matching files are re-added (no risk of staging unrelated changes).

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
  glob: "apps/*/infra/*.tf"
  run: terraform fmt {staged_files}
  stage_fixed: true
```

Design decisions:

- **Auto-format, not check-only.** The issue title says `-check`, but the existing lefthook pattern (rust-format) auto-fixes and re-stages. Auto-format is strictly better for pre-commit: it fixes the problem instead of just complaining. Reserve `-check` for CI where auto-fix is not appropriate.
- **`glob: "apps/*/infra/*.tf"`** (single `*`, not `**`) scopes to actual Terraform directories. All 12 current `.tf` files sit directly in `apps/<name>/infra/`, not in subdirectories. Using `**` with Lefthook's default `gobwas` glob matcher would require 1+ intermediate directories and silently skip every file. See "Lefthook Glob Behavior" below.
- **`stage_fixed: true`** re-stages auto-formatted files so the commit includes the fix. Lefthook applies the same glob filter when determining which files to `git add`, so only `.tf` files are re-staged.
- **`{staged_files}`** passes individual staged `.tf` files to `terraform fmt`, which accepts file paths (confirmed via `terraform fmt -help`). Lefthook automatically splits long file lists into multiple sequential invocations to stay within OS command-line length limits.

### Phase 2: Optionally Add `tflint` Hook (Conditional)

`tflint` is not installed on this machine. Adding a `tflint` hook is valuable but creates a dependency that every committer must satisfy. Two options:

**Option A (recommended): Skip tflint for now.** `terraform fmt` covers formatting. Linting can be added to CI (where `tflint` installation is controlled) without requiring every developer to install it locally. File a follow-up issue for CI `tflint`.

**Option B: Add tflint with graceful skip.** If `tflint` is desired in pre-commit, use a wrapper script:

```yaml
terraform-tflint:
  priority: 8
  glob: "apps/*/infra/*.tf"
  run: |
    if command -v tflint >/dev/null 2>&1; then
      tflint --chdir=apps/telegram-bridge/infra && tflint --chdir=apps/web-platform/infra
    else
      echo "tflint not installed, skipping (install: https://github.com/terraform-linters/tflint)"
    fi
```

Caveat: `tflint` operates on directories (not individual files), so `{staged_files}` is not useful. The hook would need to run against each infra directory, not per-file. The glob still serves its skip-if-no-match purpose.

### Phase 3: Verify and Document

- Run `lefthook run pre-commit` to verify the new hook works.
- Confirm `terraform fmt` is available in the environment (already confirmed: Terraform v1.10.5 at `~/.local/bin/terraform`).

## Non-Goals

- **`terraform validate`**: Excluded from pre-commit because it requires `terraform init` first (downloads providers, needs backend credentials). Leave to CI.
- **CI `terraform plan` workflow**: Separate issue (Phase 4 item 1 from #973).
- **Drift detection**: Separate issue (Phase 4 item 3 from #973).
- **`tflint` installation or configuration**: If Option A is chosen, tflint is deferred entirely.
- **`glob_matcher: doublestar` migration**: The existing `plugins/soleur/**/*.md` glob has the same `**` issue. Fixing all globs to use `doublestar` is a separate concern.

## Technical Considerations

### Lefthook Glob Behavior (Critical)

Lefthook uses the [`gobwas/glob`](https://github.com/gobwas/glob) library by default. The `**` pattern matches **1 or more** directories, unlike most glob implementations where `**` matches **0 or more**. This means:

| Pattern | File | Default (gobwas) | doublestar |
|---------|------|:-:|:-:|
| `apps/*/infra/**/*.tf` | `apps/web-platform/infra/main.tf` | NO MATCH | MATCH |
| `apps/*/infra/**/*.tf` | `apps/web-platform/infra/modules/vpc.tf` | MATCH | MATCH |
| `apps/*/infra/*.tf` | `apps/web-platform/infra/main.tf` | MATCH | MATCH |

Since all 12 `.tf` files are directly in `apps/<name>/infra/` (no subdirectories), the correct glob is `apps/*/infra/*.tf`.

If the project later adds nested Terraform modules (e.g., `apps/web-platform/infra/modules/`), either:

1. Add a second glob entry: `glob: ["apps/*/infra/*.tf", "apps/*/infra/**/*.tf"]` (supported since lefthook 1.10.10)
2. Set `glob_matcher: doublestar` at the top level of `lefthook.yml` (changes `**` behavior globally)

**Reference:** [Lefthook glob documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/glob.md)

### `terraform fmt` on Individual Files

`terraform fmt` accepts file paths as arguments (not just directories). This works correctly with lefthook's `{staged_files}` expansion. Each staged `.tf` file is formatted independently -- no need to run against the entire directory.

When the staged file list exceeds OS command-line limits, Lefthook automatically splits it into multiple sequential `terraform fmt` invocations. This is transparent and requires no special handling.

**Reference:** [Lefthook run documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/run.md)

### `stage_fixed` Behavior

When `stage_fixed: true`, Lefthook runs `git add` on the files after the command completes. It uses the same glob filter applied to `{staged_files}`, so only matching `.tf` files are re-staged. There is no risk of accidentally staging unrelated files.

**Reference:** [Lefthook stage_fixed documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/stage_fixed.md)

### Priority Ordering

Current priorities: rust-format (1), rust-lint-fix (2), rust-lint-check (3), markdown-lint (4), bun-test (5), plugin-component-test (6). Terraform formatting is fast and independent -- priority 7 places it after existing hooks. If `parallel: true` were ever enabled, priority would matter less.

## Acceptance Criteria

- [x] `lefthook.yml` contains a `terraform-fmt` command with `glob: "apps/*/infra/*.tf"`
- [x] Staging a misformatted `.tf` file and committing results in auto-formatting and clean commit
- [x] Non-Terraform commits are not affected (hook skips when no `.tf` files are staged)
- [x] `lefthook run pre-commit` passes with no errors when `.tf` files are already formatted

## Test Scenarios

- Given a correctly formatted `.tf` file is staged, when committing, then the terraform-fmt hook passes with no changes
- Given a misformatted `.tf` file is staged (extra whitespace, wrong indentation), when committing, then `terraform fmt` auto-formats it and `stage_fixed: true` re-stages the corrected file
- Given only `.md` files are staged, when committing, then the terraform-fmt hook is skipped entirely
- Given `terraform` is not installed, when committing a `.tf` file, then the hook fails with a clear error (lefthook does not suppress command-not-found errors)
- Given a `.tf` file exists at `apps/web-platform/infra/main.tf` (direct child of infra/), when the glob `apps/*/infra/*.tf` is evaluated, then the file matches (verifying the gobwas `**` fix)

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `terraform` not in PATH for other developers | Low | Medium (hook fails) | Document requirement; `terraform` is already required for infra work |
| Glob pattern mismatch (wrong `**` behavior) | Was High (now fixed) | High (hook silently skips all files) | Corrected from `**/*.tf` to `*.tf`; verified against Lefthook gobwas matcher docs |
| Future nested `.tf` files not matched | Low | Low (hook skips nested files) | Document: switch to list glob or `glob_matcher: doublestar` when modules are added |
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

- [Lefthook glob documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/glob.md) -- critical `**` behavior difference
- [Lefthook glob_matcher documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/glob_matcher.md) -- doublestar option
- [Lefthook run documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/run.md) -- {staged_files} and command splitting
- [Lefthook stage_fixed documentation](https://github.com/evilmartians/lefthook/blob/master/docs/configuration/stage_fixed.md)
- [Terraform fmt command](https://developer.hashicorp.com/terraform/cli/commands/fmt)
- [tflint](https://github.com/terraform-linters/tflint)
- [pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform) -- reference implementation for pre-commit framework (not Lefthook)

Closes #976
