---
title: "fix: sanitize GITHUB_OUTPUT writes against newline injection"
type: fix
date: 2026-03-05
---

# fix: sanitize GITHUB_OUTPUT writes against newline injection

## Overview

The `version-bump-and-release.yml` workflow writes untrusted values (commit messages, PR titles) to `$GITHUB_OUTPUT` using `echo "key=value"` format. A commit message or PR title containing embedded newlines could inject arbitrary step outputs -- for example, forging `labels=semver:major` to trigger an unintended major version bump.

Related issue: #425. Found during review of PR #420.

## Problem Statement

GitHub Actions' `$GITHUB_OUTPUT` file uses a `key=value\n` format. When a value itself contains newlines, each newline starts a new key=value pair in the output file. The workflow has two high-risk injection points:

1. **Line 77** (`give_up` fallback): `echo "title=$(echo "$COMMIT_MSG" | head -1)"` -- `head -1` strips trailing lines but does not strip `\r` (carriage return), which can forge outputs on Windows-authored commits
2. **Line 118** (PR metadata): `echo "title=$(echo "$PR_JSON" | jq -r '.title')"` -- PR titles from the GitHub API are arbitrary strings that could contain newline characters

### Attack Scenario

An attacker with merge access crafts a commit message:

```
feat: innocent title
labels=semver:major
```

When this hits the `give_up` fallback path (API lookup fails), `$COMMIT_MSG` contains both lines. Even though `head -1` takes the first line for `title=`, the second line `labels=semver:major` is written directly to `$GITHUB_OUTPUT` via the `echo "$COMMIT_MSG"` expansion before `head -1` processes it -- because `echo` outputs the full string and `head -1` only filters its stdin, the shell command substitution `$(echo "$COMMIT_MSG" | head -1)` correctly returns only the first line. However, a more subtle attack using `\r` (carriage return) characters can bypass this:

```
feat: innocent title\rlabels=semver:major
```

The `\r` makes `head -1` see this as a single line, but `$GITHUB_OUTPUT` parsing may treat `\r` as a line separator on some runners.

The more reliable vector is line 118, where `jq -r '.title'` outputs the raw PR title string. If a PR title contains a literal newline (possible via API), the `echo` writes both lines to `$GITHUB_OUTPUT`.

### Impact

- **Version escalation**: Forge `labels=semver:major` to force a major version bump
- **Path redirection**: Forge `body_file=/attacker/path` to inject release notes content
- **Output override**: Any step output can be forged by injecting `key=value` pairs

### Mitigating Factor

Attack surface requires merge access to main (squash merge of a PR). This limits exploitation to contributors with write access, but defense-in-depth demands sanitization regardless.

## Proposed Solution

Replace all `echo "key=$(...)"` patterns that write untrusted values with `printf 'key=%s\n'` and strip newlines/carriage returns from the value:

```bash
# Before (vulnerable)
echo "title=$(echo "$PR_JSON" | jq -r '.title')" >> $GITHUB_OUTPUT

# After (safe)
printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')" >> "$GITHUB_OUTPUT"
```

For values that are controlled constants or come from validated sources (e.g., `changed=true`, `type=patch`, `exists=false`), keep `echo` but quote `"$GITHUB_OUTPUT"` consistently.

## Technical Considerations

### Categorization of GITHUB_OUTPUT writes

**Untrusted values (must sanitize with `printf` + `tr -d '\n\r'`):**

| Line | Step | Key | Source |
|------|------|-----|--------|
| 77 | pr (give_up) | `title` | `$COMMIT_MSG` via `head -1` |
| 118 | pr | `title` | `jq -r '.title'` from PR JSON |
| 119 | pr | `labels` | `jq -r` from PR labels |

**Controlled values (safe, but quote `$GITHUB_OUTPUT`):**

| Line | Step | Key | Source |
|------|------|-----|--------|
| 38,45,48 | check_plugin | `changed` | Literal `true`/`false` |
| 58-61 | tmpfiles | `pr_body`, `release_notes`, etc. | `mktemp` output (OS-controlled) |
| 76,78,80 | pr (give_up) | `number`, `labels`, `body_file` | Literals or `$PR_BODY_FILE` |
| 85-89 | pr (dispatch) | all | Literals |
| 117 | pr | `number` | `$PR_NUM` (validated integer) |
| 121 | pr | `body_file` | `$PR_BODY_FILE` (mktemp path) |
| 132,137,139,141,144 | bump | `type` | Literals `major`/`minor`/`patch` |
| 168,185,186 | version | `current`, `next`, `tag` | Computed version strings |
| 197,200 | idempotency | `exists` | Literal `true`/`false` |

### Approach

1. Sanitize the 3 untrusted writes with `printf '%s\n'` + `tr -d '\n\r'`
2. Quote `$GITHUB_OUTPUT` consistently as `"$GITHUB_OUTPUT"` across all writes (shellcheck SC2086)
3. Do not change the structure of controlled-value writes -- they are safe but should use consistent quoting

### Non-goals

- Switching to GitHub's heredoc/delimiter-based multiline output syntax -- the values here are single-line by design, and delimiter syntax adds complexity without benefit
- Auditing `scheduled-bug-fixer.yml` -- its GITHUB_OUTPUT writes use numeric issue numbers from validated sources (workflow_dispatch input or jq-filtered API output)
- Adding a reusable shell function for output writes -- the fix is 3 lines; abstraction would be overengineering

## Acceptance Criteria

- [ ] All 3 untrusted GITHUB_OUTPUT writes use `printf 'key=%s\n'` with `tr -d '\n\r'` on the value
- [ ] All `$GITHUB_OUTPUT` references are quoted as `"$GITHUB_OUTPUT"` (consistent style)
- [ ] `mktemp` output writes remain using `echo` (safe, but quoted)
- [ ] No behavioral change for clean inputs (PR titles and commit messages without embedded newlines)
- [ ] Workflow YAML passes `actionlint` (if available) or manual review

## Test Scenarios

- Given a commit message with embedded `\n` (e.g., `feat: title\nlabels=semver:major`), when the `give_up` fallback runs, then only `title=feat: title` is written (no `labels` injection)
- Given a PR title containing `\r` (carriage return), when PR metadata is extracted, then `\r` is stripped from the title output
- Given a normal PR title like `feat: add user auth (#123)`, when PR metadata is extracted, then the title output matches exactly
- Given a PR with labels `semver:patch,bug`, when labels are extracted, then the labels output matches exactly without newline contamination
- Given a `workflow_dispatch` trigger, when the workflow runs, then all outputs use literal values (no untrusted input)

## Context

### Relevant files

- `.github/workflows/version-bump-and-release.yml` -- the only file to modify
- `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- existing security patterns
- `knowledge-base/learnings/2026-03-03-fix-release-notes-pr-extraction.md` -- recent workflow fixes

### Institutional learnings applied

- **SHA-pinned actions**: Already done (line 29: `actions/checkout@34e114876b...`)
- **`// empty` jq idiom**: Already used (line 96: `'.[0].number // empty'`)
- **Consolidated API calls**: Already done (line 114: single `gh pr view --json`)
- **`set -euo pipefail` not used**: Workflow steps run with GitHub's default `set -e`. Adding `set -euo pipefail` is out of scope but noted

### Semver intent

`semver:patch` -- this is a security hardening fix with no behavioral change for clean inputs.

## MVP

### .github/workflows/version-bump-and-release.yml

The 3 lines to change (shown as diffs):

```diff
# Line 77: give_up fallback title
-            echo "title=$(echo "$COMMIT_MSG" | head -1)" >> $GITHUB_OUTPUT
+            printf 'title=%s\n' "$(echo "$COMMIT_MSG" | head -1 | tr -d '\r')" >> "$GITHUB_OUTPUT"

# Line 118: PR title from API
-          echo "title=$(echo "$PR_JSON" | jq -r '.title')" >> $GITHUB_OUTPUT
+          printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')" >> "$GITHUB_OUTPUT"

# Line 119: PR labels from API
-          echo "labels=$(echo "$PR_JSON" | jq -r '[.labels[].name] | join(",")')" >> $GITHUB_OUTPUT
+          printf 'labels=%s\n' "$(echo "$PR_JSON" | jq -r '[.labels[].name] | join(",")'  | tr -d '\n\r')" >> "$GITHUB_OUTPUT"
```

Additionally, quote all `$GITHUB_OUTPUT` references throughout the file for consistency (replace `>> $GITHUB_OUTPUT` with `>> "$GITHUB_OUTPUT"`).

## References

- Issue: #425
- PR #420 (where the vulnerability was found during review)
- [GitHub docs: workflow commands](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#setting-an-output-parameter)
- `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
