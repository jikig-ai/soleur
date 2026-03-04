---
title: "sec: secure tmp paths in version-bump-and-release workflow"
type: fix
date: 2026-03-04
semver: patch
---

# sec: secure tmp paths in version-bump-and-release workflow

The `version-bump-and-release.yml` workflow uses five predictable `/tmp` paths across multiple steps. While GitHub-hosted runners are ephemeral VMs (low practical risk), predictable temp paths are bad practice and a real vulnerability on self-hosted runners where a malicious process could pre-create symlinks to hijack file writes (symlink attack) or exploit time-of-check-to-time-of-use races.

Fixes #426.

## Affected Paths

All in `.github/workflows/version-bump-and-release.yml`:

| Predictable Path | Steps Using It | Purpose |
|---|---|---|
| `/tmp/pr_body.txt` | Find merged PR (write), Extract changelog (read) | PR body content passed between steps |
| `/tmp/release_notes.txt` | Extract changelog (write), Create GitHub Release (read), Post to Discord (read) | Changelog extracted from PR body |
| `/tmp/current_tag` | Compute next version (write + read) | Current release tag from `gh release view` |
| `/tmp/gh_err` | Compute next version (write + read) | Stderr capture for `gh release view` error handling |

## Proposed Solution

Replace all predictable `/tmp` paths with `mktemp`-generated paths, created once at the start of the job and passed to subsequent steps via `GITHUB_OUTPUT`.

### Why `mktemp` over `$GITHUB_WORKSPACE/.github/tmp/`

- `mktemp` is the standard Unix idiom for secure temporary files -- unpredictable names, atomic creation, no prep needed
- Using `$GITHUB_WORKSPACE` would require `mkdir -p`, cleanup, and `.gitignore` management
- `mktemp` works identically on GitHub-hosted and self-hosted runners

### Implementation

Add a new step at the beginning of the job (after checkout, before "Find merged PR") that creates all temp files and exports their paths:

```yaml
# .github/workflows/version-bump-and-release.yml -- new step after checkout
- name: Create secure temp files
  id: tmpfiles
  run: |
    echo "pr_body=$(mktemp)" >> $GITHUB_OUTPUT
    echo "release_notes=$(mktemp)" >> $GITHUB_OUTPUT
    echo "current_tag=$(mktemp)" >> $GITHUB_OUTPUT
    echo "gh_err=$(mktemp)" >> $GITHUB_OUTPUT
```

Then replace every `/tmp/pr_body.txt` with `${{ steps.tmpfiles.outputs.pr_body }}`, and so on for the other three paths. Each step's `env:` block or inline references get updated.

### Cross-step data flow after the fix

```
[Create secure temp files] --outputs--> pr_body, release_notes, current_tag, gh_err
       |
       v
[Find merged PR] -- writes --> $pr_body
       |
       v
[Compute next version] -- writes/reads --> $current_tag, $gh_err
       |
       v
[Extract changelog] -- reads $pr_body, writes --> $release_notes
       |
       v
[Create GitHub Release] -- reads --> $release_notes
       |
       v
[Post to Discord] -- reads --> $release_notes
```

## Acceptance Criteria

- [ ] No hardcoded `/tmp/` paths remain in `version-bump-and-release.yml`
- [ ] All temp files are created via `mktemp` in a dedicated step
- [ ] Temp file paths are passed between steps via `GITHUB_OUTPUT`
- [ ] Existing step conditions (`if:`) and logic are unchanged
- [ ] The `give_up()` function uses the secure path for `pr_body`
- [ ] The workflow_dispatch branch uses the secure path for `pr_body`

## Test Scenarios

- Given a push to main with plugin changes, when the workflow runs, then temp files are created with unpredictable names and the release is created identically to before
- Given a workflow_dispatch trigger, when the workflow runs, then temp files are created and manual bump succeeds
- Given no plugin files changed, when the workflow runs, then it short-circuits at `check_plugin` (temp step still runs but files are unused -- harmless)
- Given `gh release view` fails with an error, when the compute-version step runs, then the error is captured in the secure `gh_err` path and reported correctly
- Given no prior releases exist, when the compute-version step runs, then it detects "release not found" from `gh_err` and defaults to `0.0.0`

## Non-Goals

- Scanning other workflow files for `/tmp` usage (grep confirms only this file uses `/tmp`)
- Adding cleanup (`trap ... EXIT`) for the temp files -- the runner VM is destroyed after the job

## Context

- Issue: #426
- File: `.github/workflows/version-bump-and-release.yml`
- Discovered during: PR #420 review
- Labels: `bot-fix/attempted` (previous automated fix attempt failed)

## References

- [CWE-377: Insecure Temporary File](https://cwe.mitre.org/data/definitions/377.html)
- [GitHub Actions: Passing data between steps](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/passing-information-between-jobs)
- Constitution: "Shell scripts must use `set -euo pipefail`" (already enforced by GitHub Actions default shell)
