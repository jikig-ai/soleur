---
title: "fix: release notes empty when PR title contains issue references"
type: fix
date: 2026-03-03
semver: patch
---

# fix: Release notes empty when PR title contains issue references

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

**Fallback:** If the API call fails (rate limit, network), fall back to `tail -1` regex extraction:

```bash
if [ -z "$PR_NUM" ]; then
  PR_NUM=$(echo "$COMMIT_MSG" | grep -oP '\(#\K\d+(?=\))' | tail -1)
fi
```

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

- [ ] PR titles containing issue references (e.g., `feat: headless mode (#393)`) produce correct release notes after squash merge
- [ ] PR titles without issue references still work (single `(#N)` pattern)
- [ ] Commits without any `(#N)` pattern fall through to the existing no-PR-found path gracefully
- [ ] The `gh api commits/.../pulls` API call has a fallback path when it fails
- [ ] PR number is validated as an actual PR before fetching metadata
- [ ] Discord webhook payload includes `username` and `avatar_url` fields
- [ ] v3.9.2 release body is corrected

## Test Scenarios

- Given a commit message `feat: thing (#100) (#200)`, when the workflow runs, then PR #200 (the last, actual PR) is used
- Given a commit message `feat: thing (#200)`, when the workflow runs, then PR #200 is used (single ref, no change in behavior)
- Given a commit message `feat: thing` (no PR ref), when the workflow runs, then the no-PR fallback path triggers with a warning
- Given the `gh api commits/.../pulls` call fails, when the workflow runs, then it falls back to `tail -1` regex extraction
- Given PR #N exists but is actually an issue, when validation runs, then the workflow falls back to the next extraction method
- Given a valid PR with a `## Changelog` section, when the workflow extracts notes, then the full changelog appears in the release body and Discord message

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
- Learning: `knowledge-base/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md`
- Learning: `knowledge-base/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- Constitution line 89: Discord webhook `username` and `avatar_url` requirement

## MVP

### `.github/workflows/version-bump-and-release.yml` (Find merged PR step)

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
    PR_NUM=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
      --jq '.[0].number' 2>/dev/null || echo "")

    # Fallback: Parse from commit message (use tail -1 for last ref = PR number)
    if [ -z "$PR_NUM" ]; then
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

    # Validate PR exists (not just an issue)
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

    PR_TITLE=$(gh pr view "$PR_NUM" --json title --jq '.title' 2>/dev/null || echo "")
    echo "title=$PR_TITLE" >> $GITHUB_OUTPUT

    PR_LABELS=$(gh pr view "$PR_NUM" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
    echo "labels=$PR_LABELS" >> $GITHUB_OUTPUT

    gh pr view "$PR_NUM" --json body --jq '.body // ""' > /tmp/pr_body.txt 2>/dev/null || echo "" > /tmp/pr_body.txt
    echo "body_file=/tmp/pr_body.txt" >> $GITHUB_OUTPUT
```

### `.github/workflows/version-bump-and-release.yml` (Discord step - payload)

```bash
PAYLOAD=$(jq -n \
  --arg content "$MESSAGE" \
  --arg username "Sol" \
  --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
  '{content: $content, username: $username, avatar_url: $avatar_url}')
```

## References

- [version-bump-and-release.yml](.github/workflows/version-bump-and-release.yml)
- [GitHub Commits API - List pull requests associated with a commit](https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit)
- [Discord Webhook API](https://discord.com/developers/docs/resources/webhook#execute-webhook)
