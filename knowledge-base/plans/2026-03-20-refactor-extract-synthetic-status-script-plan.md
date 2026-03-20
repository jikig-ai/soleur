---
title: "refactor: extract synthetic status posting to shared script"
type: refactor
date: 2026-03-20
---

# refactor: extract synthetic status posting to shared script

Nine scheduled bot workflows each copy-paste the same 8-line block to post synthetic `cla-check` and `test` status checks on bot commits. Adding a new required status check means editing all 9 files -- O(n) instead of O(1).

## Acceptance Criteria

- [ ] New script `scripts/post-bot-statuses.sh` posts synthetic `cla-check` and `test` statuses for a given commit SHA
- [ ] Script follows project shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCREAMING_SNAKE_CASE` globals, `snake_case` locals, `[[ ]]` tests
- [ ] Script accepts SHA as `$1` argument (validated early with usage message on missing arg)
- [ ] Script uses `GITHUB_REPOSITORY` env var (available in all GitHub Actions runners)
- [ ] All 9 workflow files call `bash scripts/post-bot-statuses.sh "$SHA"` instead of inline `gh api` calls
- [ ] Status context names and descriptions are defined in a single array/list inside the script, making future additions O(1)
- [ ] `scripts/create-ci-required-ruleset.sh` reference comment updated if it mentions the inline pattern
- [ ] Existing behavior is preserved: same API endpoint, same `state`, `context`, and `description` values

## Test Scenarios

- Given a bot workflow pushes a commit, when `post-bot-statuses.sh` runs with the commit SHA, then both `cla-check` and `test` statuses appear as `success` on the commit
- Given `post-bot-statuses.sh` is called without arguments, when it runs, then it exits 1 with a usage message to stderr
- Given `GITHUB_REPOSITORY` is unset, when `post-bot-statuses.sh` runs, then `set -u` catches it and the script exits non-zero
- Given a new required status check is added in the future, when the check name is added to the array in `post-bot-statuses.sh`, then all 9 workflows automatically post it without any workflow file edits

## Context

### Current State

The duplicated block appears in these 9 files (`.github/workflows/`):

| Workflow File | Variable Style |
|---|---|
| `scheduled-campaign-calendar.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-community-monitor.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-competitive-analysis.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-content-generator.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-content-publisher.yml` | `${{ github.repository }}` |
| `scheduled-growth-audit.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-growth-execution.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-seo-aeo-audit.yml` | `${GITHUB_REPOSITORY}` |
| `scheduled-weekly-analytics.yml` | `${{ github.repository }}` |

Two files use `${{ github.repository }}` (Actions expression) while seven use `${GITHUB_REPOSITORY}` (shell env var). Both resolve to the same value. The shared script standardizes on the shell env var.

### Typical inline pattern (per workflow)

```bash
SHA=$(git rev-parse HEAD)
gh api repos/${GITHUB_REPOSITORY}/statuses/$SHA \
  -f state=success \
  -f context=cla-check \
  -f description="CLA not required for automated PRs"
gh api repos/${GITHUB_REPOSITORY}/statuses/$SHA \
  -f state=success \
  -f context=test \
  -f description="Bot commit - CI not required"
```

### After refactoring (per workflow)

```bash
SHA=$(git rev-parse HEAD)
bash scripts/post-bot-statuses.sh "$SHA"
```

`SHA` computation stays in the workflow because the script should be a single-responsibility tool: it posts statuses for a given SHA, not tied to git operations.

## MVP

### scripts/post-bot-statuses.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Post synthetic success statuses for bot commits so that required
# status checks (cla-check, test) do not block auto-merge.
#
# Usage: post-bot-statuses.sh <commit-sha>
# Requires: GITHUB_REPOSITORY env var (set by GitHub Actions)
# Refs: #841, #826, #827

# --- Argument Validation ---

if [[ $# -lt 1 ]]; then
  echo "Usage: post-bot-statuses.sh <commit-sha>" >&2
  exit 1
fi

local_sha="$1"

# --- Status Definitions ---
# Add new required status checks here. Each entry: "context|description"

STATUSES=(
  "cla-check|CLA not required for automated PRs"
  "test|Bot commit - CI not required"
)

# --- Post Statuses ---

for entry in "${STATUSES[@]}"; do
  local_context="${entry%%|*}"
  local_description="${entry#*|}"
  gh api "repos/${GITHUB_REPOSITORY}/statuses/${local_sha}" \
    -f state=success \
    -f context="$local_context" \
    -f description="$local_description"
done
```

### Workflow file changes (x9)

Replace the inline `gh api` status blocks with a single call. Example diff for `scheduled-campaign-calendar.yml`:

```diff
             SHA=$(git rev-parse HEAD)
-            gh api repos/${GITHUB_REPOSITORY}/statuses/$SHA \
-              -f state=success \
-              -f context=cla-check \
-              -f description="CLA not required for automated PRs"
-            gh api repos/${GITHUB_REPOSITORY}/statuses/$SHA \
-              -f state=success \
-              -f context=test \
-              -f description="Bot commit - CI not required"
+            bash scripts/post-bot-statuses.sh "$SHA"
```

## SpecFlow Edge Cases

- **`gh api` partial failure:** If the first status posts but the second fails, `set -e` aborts the script. This is correct -- a partial status post should be visible in the workflow logs. The workflow's existing error handling (Discord notification on failure) catches this.
- **Checkout depth:** The `SHA=$(git rev-parse HEAD)` line stays in the workflow, not the script. If a workflow uses `fetch-depth: 1` (the default), `HEAD` is still valid -- `git rev-parse HEAD` only needs the current commit.
- **Script path resolution:** Workflows run with repo root as CWD. `bash scripts/post-bot-statuses.sh` resolves correctly. No `$GITHUB_WORKSPACE` prefix needed.
- **Permissions:** All 9 workflows already declare `statuses: write` permission. The script inherits this from the workflow's `GITHUB_TOKEN`. No permission changes needed.

## References

- Issue: [#841](https://github.com/jikig-ai/soleur/issues/841)
- Original PR adding synthetic statuses: [#827](https://github.com/jikig-ai/soleur/pull/827)
- Architecture review issue: [#826](https://github.com/jikig-ai/soleur/issues/826)
- Related script: `scripts/create-ci-required-ruleset.sh`
