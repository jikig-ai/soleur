---
title: "sec: secure tmp paths in version-bump-and-release workflow"
type: fix
date: 2026-03-04
semver: patch
deepened: 2026-03-04
---

# sec: secure tmp paths in version-bump-and-release workflow

The `version-bump-and-release.yml` workflow uses five predictable `/tmp` paths across multiple steps. While GitHub-hosted runners are ephemeral VMs (low practical risk), predictable temp paths are bad practice and a real vulnerability on self-hosted runners where a malicious process could pre-create symlinks to hijack file writes (symlink attack) or exploit time-of-check-to-time-of-use races.

Fixes #426.

## Enhancement Summary

**Deepened on:** 2026-03-04
**Sections enhanced:** 4 (Proposed Solution, Implementation, Test Scenarios, References)
**Research sources:** security-sentinel review, code-simplicity review, CWE-377, GitHub Actions docs, institutional learnings

### Key Improvements

1. Added `$RUNNER_TEMP` analysis and confirmed `mktemp` is the correct choice
2. Added consideration for the `give_up()` function needing env var access pattern
3. Added edge case for tmpfiles step placement relative to conditional `if:` guards
4. Incorporated learnings from prior version-bump-and-release.yml fixes (#420)

### Institutional Learnings Applied

- `2026-02-21-github-actions-workflow-security-patterns.md` -- confirms this repo's security posture for workflow hardening
- `2026-03-03-fix-release-notes-pr-extraction.md` -- documents the exact workflow file being modified, including the `give_up()` function structure and prior `sed` portability issues
- `2026-02-27-github-actions-sha-pinning-workflow.md` -- confirms `security_reminder_hook.py` will block the first Edit call on workflow files (expect retry)

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

### Why `mktemp` over alternatives

| Alternative | Verdict | Reason |
|---|---|---|
| `mktemp` | **Selected** | Unpredictable names, atomic creation via `O_CREAT\|O_EXCL`, standard Unix idiom, no prep needed |
| `$GITHUB_WORKSPACE/.github/tmp/` | Rejected | Requires `mkdir -p`, `.gitignore` management, filenames still predictable |
| `$RUNNER_TEMP/filename` | Rejected | Provides a per-job directory but filenames are still predictable within it -- does not solve the core CWE-377 vulnerability; `mktemp` within `$RUNNER_TEMP` would be redundant since `mktemp` already creates files in the system temp directory |

### Research Insights

**Security Properties of `mktemp`:**

- `mktemp` internally uses `mkstemp()` which creates files with `O_CREAT|O_EXCL` flags -- the kernel guarantees atomic creation that fails if the file already exists, preventing symlink substitution ([Secure Coding Practices](https://securecodingpractices.com/avoiding-insecure-temporary-file-creation-scripts-mktemp-usage/))
- Default permissions are `0600` (owner read/write only), preventing other processes from reading the temp files
- The random suffix is generated from `/dev/urandom`, making names unpredictable ([CWE-377](https://cwe.mitre.org/data/definitions/377.html))

**GitHub Actions Context:**

- `$RUNNER_TEMP` (`runner.temp`) provides a job-specific temp directory that is cleaned up after each job -- useful for isolation but does not address filename predictability ([GitHub Actions Contexts](https://docs.github.com/en/actions/learn-github-actions/contexts))
- `GITHUB_OUTPUT` is the standard mechanism for passing data between steps within the same job ([GitHub Docs](https://docs.github.com/actions/reference/workflow-commands-for-github-actions))

### Implementation

Add a new step after checkout and `check_plugin` but before "Find merged PR" that creates all temp files and exports their paths:

```yaml
# .github/workflows/version-bump-and-release.yml -- new step
- name: Create secure temp files
  if: steps.check_plugin.outputs.changed == 'true'
  id: tmpfiles
  run: |
    echo "pr_body=$(mktemp)" >> $GITHUB_OUTPUT
    echo "release_notes=$(mktemp)" >> $GITHUB_OUTPUT
    echo "current_tag=$(mktemp)" >> $GITHUB_OUTPUT
    echo "gh_err=$(mktemp)" >> $GITHUB_OUTPUT
```

Then replace every `/tmp/pr_body.txt` with `${{ steps.tmpfiles.outputs.pr_body }}`, and so on for the other three paths. Each step receives the path via its `env:` block.

**Step placement rationale:** The tmpfiles step goes after `check_plugin` with the same `if:` guard (`steps.check_plugin.outputs.changed == 'true'`). This avoids creating temp files when no plugin files changed and the workflow short-circuits. The temp files are only needed by downstream steps that all share this same condition.

**`give_up()` function pattern:** The `give_up()` function in the "Find merged PR" step is a shell function defined inline. It cannot access `${{ }}` expressions directly -- those are resolved before the shell runs. Pass the temp path via `env:` and reference `$PR_BODY_FILE` inside the function:

```yaml
- name: Find merged PR
  if: steps.check_plugin.outputs.changed == 'true'
  id: pr
  env:
    GH_TOKEN: ${{ github.token }}
    EVENT_NAME: ${{ github.event_name }}
    COMMIT_MSG: ${{ github.event.head_commit.message }}
    PR_BODY_FILE: ${{ steps.tmpfiles.outputs.pr_body }}
  run: |
    give_up() {
      local reason="$1"
      echo "::warning::${reason}, using commit message as title"
      echo "number=" >> $GITHUB_OUTPUT
      echo "title=$(echo "$COMMIT_MSG" | head -1)" >> $GITHUB_OUTPUT
      echo "labels=" >> $GITHUB_OUTPUT
      echo "" > "$PR_BODY_FILE"
      echo "body_file=$PR_BODY_FILE" >> $GITHUB_OUTPUT
      exit 0
    }
    # ... rest of step uses $PR_BODY_FILE throughout
```

### Cross-step data flow after the fix

```
[checkout] --> [check_plugin] --> [Create secure temp files]
                                         |
                              outputs: pr_body, release_notes,
                                       current_tag, gh_err
                                         |
                                         v
                              [Find merged PR]
                              env: PR_BODY_FILE
                              writes --> $PR_BODY_FILE
                                         |
                                         v
                              [Compute next version]
                              env: CURRENT_TAG_FILE, GH_ERR_FILE
                              writes/reads --> $CURRENT_TAG_FILE, $GH_ERR_FILE
                                         |
                                         v
                              [Extract changelog]
                              env: BODY_FILE, RELEASE_NOTES_FILE
                              reads $BODY_FILE, writes --> $RELEASE_NOTES_FILE
                                         |
                                         v
                              [Create GitHub Release]
                              env: RELEASE_NOTES_FILE
                              reads --> $RELEASE_NOTES_FILE
                                         |
                                         v
                              [Post to Discord]
                              env: RELEASE_NOTES_FILE
                              reads --> $RELEASE_NOTES_FILE
```

## Acceptance Criteria

- [x] No hardcoded `/tmp/` paths remain in `version-bump-and-release.yml`
- [x] All temp files are created via `mktemp` in a dedicated step
- [x] Temp file paths are passed between steps via `GITHUB_OUTPUT`
- [x] Existing step conditions (`if:`) and logic are unchanged
- [x] The `give_up()` function uses the secure path via `$PR_BODY_FILE` env var
- [x] The workflow_dispatch branch uses the secure path via `$PR_BODY_FILE` env var
- [x] The tmpfiles step has the same `if:` guard as downstream steps
- [x] `grep -n '/tmp/' .github/workflows/version-bump-and-release.yml` returns zero results

## Test Scenarios

- Given a push to main with plugin changes, when the workflow runs, then temp files are created with unpredictable names and the release is created identically to before
- Given a workflow_dispatch trigger, when the workflow runs, then temp files are created and manual bump succeeds
- Given no plugin files changed, when the workflow runs, then it short-circuits at `check_plugin` and the tmpfiles step is skipped (no unnecessary temp files created)
- Given `gh release view` fails with an error, when the compute-version step runs, then the error is captured in the secure `$GH_ERR_FILE` path and reported correctly
- Given no prior releases exist, when the compute-version step runs, then it detects "release not found" from `$GH_ERR_FILE` and defaults to `0.0.0`
- Given the `give_up()` function is called (no PR found), when it writes to `$PR_BODY_FILE`, then the file path is the mktemp-generated path, not a hardcoded `/tmp` path

### Edge Cases

- **Empty `body_file` output:** The `body_file` output from the "Find merged PR" step stores the temp path itself (not the content). Downstream steps read the file at that path. Verify the `body_file` output value is the mktemp path, not an empty string.
- **Pre-existing PreToolUse hook rejection:** The `security_reminder_hook.py` will block the first Edit call on `.github/workflows/*.yml` files. Expect a retry on the first edit (documented in learning `2026-02-27-github-actions-sha-pinning-workflow.md`).

## Non-Goals

- Scanning other workflow files for `/tmp` usage (grep confirms only this file uses `/tmp`)
- Adding cleanup (`trap ... EXIT`) for the temp files -- the runner VM is destroyed after the job
- Using `$RUNNER_TEMP` as the temp directory -- it does not solve filename predictability

## Simplicity Assessment

This fix has minimal complexity:

- **1 file changed:** `.github/workflows/version-bump-and-release.yml`
- **1 new step added:** 5 lines for the tmpfiles step
- **Mechanical substitution:** Every `/tmp/X` becomes `$ENV_VAR` -- no logic changes
- **No new dependencies, no new patterns** -- `mktemp` and `GITHUB_OUTPUT` are both standard
- **LOC delta:** approximately +10 lines (env vars in each step), -0 lines (replacements are same length)

## Context

- Issue: #426
- File: `.github/workflows/version-bump-and-release.yml`
- Discovered during: PR #420 review
- Labels: `bot-fix/attempted` (previous automated fix attempt failed)
- Prior fixes to this workflow: PR #420 (API-based PR lookup), commit `17ad7a2` (headless mode bug)

## References

- [CWE-377: Insecure Temporary File](https://cwe.mitre.org/data/definitions/377.html)
- [Avoiding Insecure Temporary File Creation](https://securecodingpractices.com/avoiding-insecure-temporary-file-creation-scripts-mktemp-usage/)
- [GitHub Actions: Workflow Commands](https://docs.github.com/actions/reference/workflow-commands-for-github-actions)
- [GitHub Actions: Contexts Reference (runner.temp)](https://docs.github.com/en/actions/learn-github-actions/contexts)
- [GitHub Actions: Passing Data Between Steps](https://www.ackama.com/articles/values-github-actions/)
- [Time-of-check to time-of-use (Wikipedia)](https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use)
- Learning: `2026-02-21-github-actions-workflow-security-patterns.md`
- Learning: `2026-03-03-fix-release-notes-pr-extraction.md`
- Learning: `2026-02-27-github-actions-sha-pinning-workflow.md`
- Constitution: "Shell scripts must use `set -euo pipefail`" (enforced by GitHub Actions default shell)
