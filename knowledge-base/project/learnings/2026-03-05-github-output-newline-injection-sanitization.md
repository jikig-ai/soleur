---
title: "GitHub Actions GITHUB_OUTPUT newline injection vulnerability"
date: 2026-03-05
category: security-issues
module: ci-cd
tags:
  - github-actions
  - supply-chain-security
  - output-sanitization
  - shellcheck
  - version-bump
severity: high
related_issues:
  - 425
---

# Learning: GITHUB_OUTPUT newline injection sanitization

## Problem

The `version-bump-and-release.yml` workflow wrote untrusted values (commit messages, PR titles) to `$GITHUB_OUTPUT` using `echo "key=value"`. Since `$GITHUB_OUTPUT` uses a `key=value\n` format, a value containing embedded newlines creates additional key=value pairs — allowing an attacker with merge access to forge step outputs like `labels=semver:major`.

Two attack vectors confirmed via shell testing:

1. **`\r` (carriage return)** passes through `head -1` and may be treated as a line separator on some runners
2. **`\n` in `jq -r` output** — a PR title containing a literal newline causes `echo "title=..."` to write two separate lines to `$GITHUB_OUTPUT`

## Solution

Replace `echo "key=$(untrusted)"` with `printf 'key=%s\n'` and strip newlines from values:

```bash
# Before (vulnerable)
echo "title=$(echo "$PR_JSON" | jq -r '.title')" >> $GITHUB_OUTPUT

# After (safe)
printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')" >> "$GITHUB_OUTPUT"
```

Three specific changes:

1. Line 77 (give_up fallback): `head -1 | tr -d '\n\r'` for commit message title
2. Line 118 (PR title from API): `jq -r '.title' | tr -d '\n\r'`
3. Line 119 (PR labels from API): `jq -r '...' | tr -d '\n\r'`

Also quoted all `$GITHUB_OUTPUT` references as `"$GITHUB_OUTPUT"` for shellcheck SC2086 compliance.

## Key Insight

When writing untrusted values to `$GITHUB_OUTPUT`, always use `printf '%s\n'` (treats argument as literal) instead of `echo` (may interpret escapes), and strip `\n\r` from values with `tr -d '\n\r'`. Categorize each write as "untrusted" or "controlled" — only untrusted values need sanitization, but all `$GITHUB_OUTPUT` references should be quoted.

GitHub's heredoc/delimiter syntax for multiline outputs is NOT a solution here — their own docs warn "if the value is completely arbitrary then you shouldn't use this format" because the delimiter itself could appear in the value.

## Session Errors

1. PreToolUse security_reminder_hook.py blocked the first Edit on the workflow file — expected behavior documented in `2026-02-27-github-actions-sha-pinning-workflow.md`. Retry succeeded.
2. Stale branch from previous session required using existing worktree instead of creating a new one.

## Related

- `2026-02-21-github-actions-workflow-security-patterns.md` — broader workflow security patterns (SHA pinning, input validation)
- `2026-02-27-github-actions-sha-pinning-workflow.md` — documents the security hook behavior
- `2026-03-03-fix-release-notes-pr-extraction.md` — prior changes to the same workflow
- `2026-03-03-serialize-version-bumps-to-merge-time.md` — workflow architecture and design decisions

## Tags

category: security-issues
module: ci-cd
