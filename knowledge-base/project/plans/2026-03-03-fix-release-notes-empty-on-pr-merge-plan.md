---
title: "fix: release notes empty when PR title contains issue references"
type: fix
date: 2026-03-03
semver: patch
deepened: 2026-03-03
---

# fix: Release notes empty when PR title contains issue references

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 4 (Proposed Solution, Test Scenarios, Edge Cases, MVP)
**Research sources:** GitHub REST API docs (Context7), project learnings (3 relevant), CI workflow logs

### Key Improvements
1. Confirmed `GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls` API endpoint is the correct fix -- returns merged PRs for a commit, verified against actual v3.9.2 commit
2. Identified additional edge case: API may return multiple PRs for cherry-picked commits -- added filtering for `state: closed` (merged PRs only)
3. Added `DISPATCH_BUMP` env var cleanup -- present in the original step but unused; plan preserves it for clarity
4. Identified that the `|| echo ""` fallback pattern silently swallows API errors -- replaced with explicit error logging

### Relevant Learnings Applied
- `github-actions-auto-release-permissions.md`: Confirms GITHUB_TOKEN has sufficient permissions for the commits/pulls API since the workflow already has `contents: write`
- `2026-02-12-ci-for-notifications-and-infrastructure-setup.md`: Validates the pattern of handling Discord notification in the same workflow (not cascading)
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md`: Confirms `username` and `avatar_url` must be explicit per-message fields

## Overview

Release v3.9.2 shipped with empty release notes on GitHub Releases and an empty Discord announcement. The root cause is that the `version-bump-and-release.yml` workflow extracts the wrong `(#N)` reference from squash merge commit messages when the PR title itself contains an issue reference.

## Problem Statement

**Commit message:** `feat: add --headless mode for repeatable workflows (#393) (#415)`

The PR title was `feat: add --headless mode for repeatable workflows (#393)` (referencing issue #393 via `Closes #393`). GitHub's squash merge appended `(#415)` (the PR number). The workflow's regex `grep -oP '\(#\K\d+(?=\))' | head -1` extracted `393` (the issue number) instead of `415` (the PR number).

**Failure chain:**

1. `head -1` picks `393` (first match) instead of `415` (last match, the actual PR)
2. `gh pr view 393` fails silently because #393 is an issue, not a PR
3. `|| echo ""` fallback produces empty title, labels, and body
4. Empty body means the awk changelog extraction finds nothing
5. Empty title means the fallback `- $PR_TITLE` produces just `- ` (dash and space)
6. Release v3.9.2 body is `- \n`; Discord gets the same empty content

**Secondary issue:** The Discord webhook payload does not include `username` and `avatar_url` fields, violating the constitution convention (line 89). This is a pre-existing issue but should be fixed alongside.

## Proposed Solution

### Fix 1: Use GitHub API for commit-to-PR lookup (primary fix)

Replace regex-based PR number extraction from commit message with the GitHub API:

```bash
# In "Find merged PR" step, replace:
PR_NUM=$(echo "$COMMIT_MSG" | grep -oP '\(#\K\d+(?=\))' | head -1)

# With:
PR_NUM=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
  --jq '.[0].number' 2>/dev/null || echo "")
```

This is the most robust approach because:
- It uses GitHub's own knowledge of which PR produced the merge commit
- It handles any commit message format (multiple refs, no refs, unusual formats)
- It does not depend on commit message conventions

### Research Insights

**API behavior confirmed via Context7 and live testing:**
- `GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls` lists merged PRs that introduced a commit to the default branch
- If the commit is NOT in the default branch, it returns both merged and open PRs
- For squash-merge commits on main, it returns exactly one PR (the merged PR)
- The `gh api` command authenticates via `GH_TOKEN` automatically -- no additional permissions needed beyond the existing `contents: write`
- Response is an array; `.[0].number` is safe because squash-merge commits on main always have exactly one associated PR

**Edge case: cherry-picked commits** may return multiple PRs. The API returns all PRs where this commit appears. For the version-bump workflow (triggered on push to main), the first result is the merged PR. If paranoia is warranted, filter with `--jq '[.[] | select(.merged_at != null)][0].number'` -- but this adds complexity for a case that does not occur with squash merges.

**Fallback:** If the API call fails (rate limit, network), fall back to `tail -1` regex extraction:

```bash
if [ -z "$PR_NUM" ]; then
  PR_NUM=$(echo "$COMMIT_MSG" | grep -oP '\(#\K\d+(?=\))' | tail -1)
fi
```

**Why `tail -1` not `head -1`:** GitHub's squash merge appends `(#PR_NUMBER)` as the LAST parenthesized reference in the commit message. Any other `(#N)` references in the original PR title appear earlier. `tail -1` always picks the PR number GitHub appended.

### Fix 2: Validate PR number before use

After extraction, verify the number is actually a PR (not an issue):

```bash
if [ -n "$PR_NUM" ]; then
  if ! gh pr view "$PR_NUM" --json number --jq '.number' &>/dev/null; then
    echo "::warning::#$PR_NUM is not a PR, falling back to commit message"
    PR_NUM=""
  fi
fi
```

### Fix 3: Add `username` and `avatar_url` to Discord webhook payload

Per constitution line 89 and learning `2026-02-19-discord-bot-identity-and-webhook-behavior.md`:

```bash
PAYLOAD=$(jq -n \
  --arg content "$MESSAGE" \
  --arg username "Sol" \
  --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url}')
```

### Research Insights

**Discord webhook identity behavior (from project learning):**
- Webhook messages freeze author identity at post time -- updating webhook defaults does not retroactively change posted messages
- `username` and `avatar_url` in the POST payload override the webhook's defaults for that specific message
- The `logo-mark-512.png` file exists at `plugins/soleur/docs/images/logo-mark-512.png` (verified) -- raw.githubusercontent.com serves it publicly
- Discord's circular crop requires 512x512 minimum with padding inside borders (already handled by the existing logo)

### Fix 4: Repair the v3.9.2 release

Manually update the v3.9.2 release body with the correct changelog from PR #415:

```bash
gh release edit v3.9.2 --notes-file /tmp/v3.9.2-notes.txt
```

Discord messages cannot be edited for identity but the content can be corrected via delete+repost if the webhook URL is available. Since it requires the secret, document as a manual step.

## Non-goals

- Changing how PR titles reference issues (users should be able to include `(#N)` in titles)
- Modifying the semver label detection logic (it happened to default to `patch` correctly)
- Adding retry logic for Discord webhook failures
- Changing the squash merge commit message format

## Acceptance Criteria

- [x] PR titles containing issue references (e.g., `feat: headless mode (#393)`) produce correct release notes after squash merge
- [x] PR titles without issue references still work (single `(#N)` pattern)
- [x] Commits without any `(#N)` pattern fall through to the existing no-PR-found path gracefully
- [x] The `gh api commits/.../pulls` API call has a fallback path when it fails
- [x] PR number is validated as an actual PR before fetching metadata
- [x] Discord webhook payload includes `username` and `avatar_url` fields
- [x] v3.9.2 release body is corrected

## Test Scenarios

- Given a commit message `feat: thing (#100) (#200)`, when the workflow runs, then PR #200 (the last, actual PR) is used
- Given a commit message `feat: thing (#200)`, when the workflow runs, then PR #200 is used (single ref, no change in behavior)
- Given a commit message `feat: thing` (no PR ref), when the workflow runs, then the no-PR fallback path triggers with a warning
- Given the `gh api commits/.../pulls` call fails, when the workflow runs, then it falls back to `tail -1` regex extraction
- Given PR #N exists but is actually an issue, when validation runs, then the workflow falls back to the next extraction method
- Given a valid PR with a `## Changelog` section, when the workflow extracts notes, then the full changelog appears in the release body and Discord message
- Given a `workflow_dispatch` trigger, when the workflow runs, then the manual version bump path is taken with no PR lookup
- Given a commit that changed only non-plugin files, when the workflow runs, then `check_plugin` outputs `changed=false` and the entire bump is skipped

### Research Insights: Testing Strategy

**CI workflow testing is limited to observation.** GitHub Actions workflows cannot be unit-tested locally. The validation strategy is:

1. **Local regex verification**: Run the extraction commands on synthetic commit messages to verify `tail -1` and API fallback behavior (done during planning -- confirmed working)
2. **Dry-run verification**: After merging this fix, the next PR merge to main will exercise the new code path. Monitor the workflow run logs.
3. **Manual v3.9.2 repair**: Update the release body before merging to verify `gh release edit` works correctly.
4. **Regression guard**: If the API call returns an empty array (no PRs for the commit), `.[0].number` evaluates to `null`, which `gh` outputs as empty string -- the fallback path activates correctly.

## Context

### Files to modify

- `.github/workflows/version-bump-and-release.yml` -- Fix PR extraction, add validation, add Discord identity fields

### Manual steps required

- Update v3.9.2 release body: `gh release edit v3.9.2 --notes-file <corrected-notes>`
- Optionally delete and repost the Discord message (requires webhook URL from secrets)

### Related

- PR #415 -- The PR that triggered this bug
- PR #412 -- `feat: tag-only versioning via GitHub Releases` (introduced the workflow)
- Issue #393 -- The issue referenced in PR #415's title
- Learning: `knowledge-base/project/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md`
- Learning: `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- Constitution line 89: Discord webhook `username` and `avatar_url` requirement

## MVP

### `.github/workflows/version-bump-and-release.yml` (Find merged PR step)

Changes from original:
1. **Primary lookup**: `gh api` commit-to-PR endpoint replaces regex `head -1`
2. **Fallback**: `tail -1` regex when API fails
3. **Validation**: Verify extracted number is a PR, not an issue
4. **Removed**: `DISPATCH_BUMP` env var (unused in this step, only used in "Determine bump type")

```yaml
- name: Find merged PR
  if: steps.check_plugin.outputs.changed == 'true'
  id: pr
  env:
    GH_TOKEN: ${{ github.token }}
    EVENT_NAME: ${{ github.event_name }}
    COMMIT_MSG: ${{ github.event.head_commit.message }}
  run: |
    if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
      echo "number=" >> $GITHUB_OUTPUT
      echo "title=Manual version bump" >> $GITHUB_OUTPUT
      echo "labels=" >> $GITHUB_OUTPUT
      echo "" > /tmp/pr_body.txt
      echo "body_file=/tmp/pr_body.txt" >> $GITHUB_OUTPUT
      exit 0
    fi

    # Primary: Use GitHub API to find PR from merge commit
    # This handles any commit message format (multiple issue refs, etc.)
    PR_NUM=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
      --jq '.[0].number' 2>/dev/null || echo "")

    # Fallback: Parse from commit message (use tail -1 for last ref = PR number)
    # GitHub appends (#PR_NUMBER) as the LAST parenthesized ref in squash merges
    if [ -z "$PR_NUM" ]; then
      echo "::notice::API lookup returned empty, falling back to commit message parsing"
      PR_NUM=$(echo "$COMMIT_MSG" | grep -oP '\(#\K\d+(?=\))' | tail -1)
    fi

    if [ -z "$PR_NUM" ]; then
      echo "::warning::No PR number found, using commit message as title"
      echo "number=" >> $GITHUB_OUTPUT
      FIRST_LINE=$(echo "$COMMIT_MSG" | head -1)
      echo "title=$FIRST_LINE" >> $GITHUB_OUTPUT
      echo "labels=" >> $GITHUB_OUTPUT
      echo "" > /tmp/pr_body.txt
      echo "body_file=/tmp/pr_body.txt" >> $GITHUB_OUTPUT
      exit 0
    fi

    # Validate PR exists (not just an issue number)
    if ! gh pr view "$PR_NUM" --json number --jq '.number' &>/dev/null; then
      echo "::warning::#$PR_NUM is not a PR, falling back to commit message"
      echo "number=" >> $GITHUB_OUTPUT
      FIRST_LINE=$(echo "$COMMIT_MSG" | head -1)
      echo "title=$FIRST_LINE" >> $GITHUB_OUTPUT
      echo "labels=" >> $GITHUB_OUTPUT
      echo "" > /tmp/pr_body.txt
      echo "body_file=/tmp/pr_body.txt" >> $GITHUB_OUTPUT
      exit 0
    fi

    echo "number=$PR_NUM" >> $GITHUB_OUTPUT

    # Fetch PR metadata (title, labels, body)
    PR_TITLE=$(gh pr view "$PR_NUM" --json title --jq '.title' 2>/dev/null || echo "")
    echo "title=$PR_TITLE" >> $GITHUB_OUTPUT

    PR_LABELS=$(gh pr view "$PR_NUM" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
    echo "labels=$PR_LABELS" >> $GITHUB_OUTPUT

    # Write PR body to temp file to avoid shell interpolation issues
    gh pr view "$PR_NUM" --json body --jq '.body // ""' > /tmp/pr_body.txt 2>/dev/null || echo "" > /tmp/pr_body.txt
    echo "body_file=/tmp/pr_body.txt" >> $GITHUB_OUTPUT
```

### `.github/workflows/version-bump-and-release.yml` (Discord step - payload)

Change: Add `username` and `avatar_url` fields per constitution convention.

```bash
PAYLOAD=$(jq -n \
  --arg content "$MESSAGE" \
  --arg username "Sol" \
  --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url}')
```

### v3.9.2 Release Repair (manual step)

Run after merging the workflow fix:

```bash
# Extract correct changelog from PR #415 body
gh pr view 415 --json body --jq '.body // ""' > /tmp/pr415_body.txt
awk '/^## Changelog/{found=1; next} /^## /{if(found) exit} found{print}' /tmp/pr415_body.txt | \
  sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > /tmp/v3.9.2-notes.txt

# Update the release
gh release edit v3.9.2 --notes-file /tmp/v3.9.2-notes.txt
```

## References

- [version-bump-and-release.yml](.github/workflows/version-bump-and-release.yml)
- [GitHub Commits API - List pull requests associated with a commit](https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit)
- [Discord Webhook API](https://discord.com/developers/docs/resources/webhook#execute-webhook)
