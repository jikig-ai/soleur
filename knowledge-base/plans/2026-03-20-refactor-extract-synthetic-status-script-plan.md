---
title: "refactor: extract synthetic status posting to shared script"
type: refactor
date: 2026-03-20
deepened: 2026-03-20
---

# refactor: extract synthetic status posting to shared script

Nine scheduled bot workflows each copy-paste the same 8-line block to post synthetic `cla-check` and `test` status checks on bot commits. Adding a new required status check means editing all 9 files -- O(n) instead of O(1).

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Context, MVP, SpecFlow Edge Cases, Test Scenarios)
**Research sources:** GitHub REST API docs, GitHub Actions shell behavior, project shell script conventions (`scripts/content-publisher.sh`, `scripts/create-ci-required-ruleset.sh`)

### Key Improvements

1. Identified two distinct workflow categories (claude-code-action prompts vs. direct `run:` steps) that require different awareness during implementation
2. Added header comment documentation convention matching `scripts/content-publisher.sh` (Usage, Environment variables, Exit codes)
3. Expanded edge case analysis with `gh api` idempotency insight and `GH_TOKEN` propagation details

### New Considerations Discovered

- The 7 workflows using `${GITHUB_REPOSITORY}` embed bash in claude-code-action `prompt:` fields; the 2 using `${{ github.repository }}` use direct `run:` steps -- the replacement approach is identical but awareness prevents confusion during review
- The GitHub Commit Statuses API is idempotent per (context, SHA) pair -- re-posting the same status is safe, which means retries or duplicate runs cause no harm

## Acceptance Criteria

- [ ] New script `scripts/post-bot-statuses.sh` posts synthetic `cla-check` and `test` statuses for a given commit SHA
- [ ] Script follows project shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCREAMING_SNAKE_CASE` globals, `snake_case` locals, `[[ ]]` tests
- [ ] Script header comment follows the project pattern from `scripts/content-publisher.sh`: Usage, Environment variables, Exit codes sections
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
- Given the script is run twice for the same SHA (idempotency), when both runs complete, then the statuses reflect the latest POST (GitHub Statuses API is idempotent per context+SHA)
- Given the script syntax is validated with `bash -n scripts/post-bot-statuses.sh`, when it runs, then it exits 0 with no parse errors

## Context

### Current State

The duplicated block appears in these 9 files (`.github/workflows/`):

| Workflow File | Variable Style | Execution Context |
|---|---|---|
| `scheduled-campaign-calendar.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-community-monitor.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-competitive-analysis.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-content-generator.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-content-publisher.yml` | `${{ github.repository }}` | direct `run:` step |
| `scheduled-growth-audit.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-growth-execution.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-seo-aeo-audit.yml` | `${GITHUB_REPOSITORY}` | claude-code-action `prompt:` |
| `scheduled-weekly-analytics.yml` | `${{ github.repository }}` | direct `run:` step |

Two files use `${{ github.repository }}` (Actions expression) while seven use `${GITHUB_REPOSITORY}` (shell env var). Both resolve to the same value. The shared script standardizes on the shell env var.

### Research Insights

**Two execution contexts exist across the 9 workflows:**

1. **claude-code-action prompts (7 workflows):** The bash code lives inside a YAML `prompt:` field. The Claude agent parses the prompt and executes the bash commands via its Bash tool. The `GH_TOKEN` env var is set at the step level (`env: GH_TOKEN: ${{ github.token }}`), which propagates to the agent's shell environment. `GITHUB_REPOSITORY` is a default GitHub Actions runner env var, also available to the agent. `Bash` is in `--allowedTools` for all 7 workflows.

2. **Direct `run:` steps (2 workflows):** `scheduled-content-publisher.yml` and `scheduled-weekly-analytics.yml` use native YAML `run:` blocks. These have the same env var access. The `${{ github.repository }}` Actions expression gets pre-resolved to the literal value before bash sees it, but `${GITHUB_REPOSITORY}` also works in `run:` blocks because GitHub Actions injects it as an environment variable.

**The replacement is identical in both contexts** -- `bash scripts/post-bot-statuses.sh "$SHA"` -- because the script uses only shell env vars (`GITHUB_REPOSITORY`), not Actions expressions (`${{ }}`).

**GitHub Commit Statuses API behavior:**
- The [POST /repos/{owner}/{repo}/statuses/{sha}](https://docs.github.com/en/rest/commits/statuses) endpoint is idempotent per (context, SHA) -- re-posting the same context overwrites the previous status, it does not create duplicates
- Each status requires `state` (success/pending/failure/error), `context` (string identifier), and optionally `description` and `target_url`
- The `gh api` command automatically authenticates using `GH_TOKEN` or `GITHUB_TOKEN` env vars

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
#
# Environment variables:
#   GITHUB_REPOSITORY - owner/repo (set automatically by GitHub Actions)
#   GH_TOKEN          - GitHub token for API auth (set by workflow step env)
#
# Exit codes:
#   0 - All statuses posted successfully
#   1 - Missing argument or gh api failure
#
# Refs: #841, #826, #827

# --- Argument Validation ---

if [[ $# -lt 1 ]]; then
  echo "Usage: post-bot-statuses.sh <commit-sha>" >&2
  exit 1
fi

local_sha="$1"

# --- Status Definitions ---
# Add new required status checks here. Each entry: "context|description"
# When adding a new entry, also update scripts/create-ci-required-ruleset.sh
# to include the new context in the required_status_checks array.

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

### Research Insights for Script Design

**Conventions followed (from `scripts/content-publisher.sh`):**
- Header comment block with Usage, Environment variables, Exit codes sections
- `set -euo pipefail` at top
- Section headers using `# --- Section Name ---` format (per constitution.md)
- Double-quoted all variable expansions
- Error messages to stderr (`>&2`)

**Design decision -- pipe-delimited array vs. associative array:**
A bash associative array (`declare -A`) would be cleaner but is less readable for non-bash experts reviewing CI workflow code. The pipe-delimited string array with `%%` and `#` parameter expansion is the simplest approach that preserves O(1) extensibility.

**Design decision -- no `local` keyword at script scope:**
The `local` keyword is only valid inside functions. Since this script has no functions (it is a linear script), variables use `local_` prefix naming convention to signal intent without the `local` keyword.

### Workflow file changes (x9)

Replace the inline `gh api` status blocks with a single call. Example diff for `scheduled-campaign-calendar.yml` (claude-code-action prompt):

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

Example diff for `scheduled-content-publisher.yml` (direct `run:` step):

```diff
           SHA=$(git rev-parse HEAD)
-          gh api "repos/${{ github.repository }}/statuses/$SHA" \
-            -f state=success \
-            -f context=cla-check \
-            -f description="CLA not required for automated PRs"
-          gh api "repos/${{ github.repository }}/statuses/$SHA" \
-            -f state=success \
-            -f context=test \
-            -f description="Bot commit - CI not required"
+          bash scripts/post-bot-statuses.sh "$SHA"
```

Note: The 2 direct `run:` workflows also had inline comments (`# Set CLA check status to success -- ...`) above the status block. These comments can be replaced with a single-line reference: `# Post synthetic statuses for branch protection (see scripts/post-bot-statuses.sh)`.

## SpecFlow Edge Cases

- **`gh api` partial failure:** If the first status posts but the second fails, `set -e` aborts the script. This is correct -- a partial status post should be visible in the workflow logs. The workflow's existing error handling (Discord notification on failure) catches this.
- **Checkout depth:** The `SHA=$(git rev-parse HEAD)` line stays in the workflow, not the script. If a workflow uses `fetch-depth: 1` (the default), `HEAD` is still valid -- `git rev-parse HEAD` only needs the current commit.
- **Script path resolution:** Workflows run with repo root as CWD. `bash scripts/post-bot-statuses.sh` resolves correctly. No `$GITHUB_WORKSPACE` prefix needed. For claude-code-action workflows, the action checks out the repo and sets CWD to the repo root before the agent starts.
- **Permissions:** All 9 workflows already declare `statuses: write` permission. The script inherits this from the workflow's `GITHUB_TOKEN`. No permission changes needed.
- **Idempotency:** The GitHub Statuses API overwrites existing statuses for the same (context, SHA) pair. If the script runs twice (e.g., retry), no duplicate statuses are created. This is safe by design.
- **`GH_TOKEN` propagation in claude-code-action:** The 7 claude-code-action workflows set `GH_TOKEN` at the step level via `env: GH_TOKEN: ${{ github.token }}`. This propagates to the Bash tool's environment. The script's `gh api` calls authenticate via this token automatically.
- **Adding a new status context:** When adding a new entry to `STATUSES`, the implementer must also update `scripts/create-ci-required-ruleset.sh` to include the new context in the `required_status_checks` array. The script comment documents this cross-reference.

## References

- Issue: [#841](https://github.com/jikig-ai/soleur/issues/841)
- Original PR adding synthetic statuses: [#827](https://github.com/jikig-ai/soleur/pull/827)
- Architecture review issue: [#826](https://github.com/jikig-ai/soleur/issues/826)
- Related script: `scripts/create-ci-required-ruleset.sh`
- [GitHub REST API -- Commit Statuses](https://docs.github.com/en/rest/commits/statuses)
- [GitHub REST API -- Best Practices](https://docs.github.com/rest/guides/best-practices-for-using-the-rest-api)
- [GitHub Actions -- shell -e -o pipefail behavior](https://copdips.com/2023/11/github-actions-bash-shell--e--o-pipefail.html)
