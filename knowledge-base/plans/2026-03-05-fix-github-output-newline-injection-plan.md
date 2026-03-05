---
title: "fix: sanitize GITHUB_OUTPUT writes against newline injection"
type: fix
date: 2026-03-05
deepened: 2026-03-05
---

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 4 (Attack Scenario, Proposed Solution, Technical Considerations, Test Scenarios)
**Research sources:** GitHub official docs, OpenSSF guidance, local shell testing, institutional learnings

### Key Improvements

1. Corrected the attack scenario analysis -- `head -1` inside command substitution is safe against `\n` injection; the real vector is `\r` (carriage return) on line 77 and raw `jq -r` output on lines 118-119
2. Added verified shell test results proving the `jq -r` vector produces real output forging
3. Added GitHub's official multiline delimiter guidance and explained why it is inappropriate here
4. Strengthened test scenarios with concrete shell verification commands

### New Considerations Discovered

- The `give_up` fallback (line 77) is only vulnerable to `\r` injection, not `\n` -- command substitution strips trailing newlines and `head -1` filters to one line
- The `jq -r` vector (line 118) is the primary confirmed vulnerability -- verified with shell testing
- GitHub's official docs do not provide specific GITHUB_OUTPUT sanitization guidance -- this is a gap in their security documentation
- The `tr -d '\n\r'` approach concatenates rather than truncates, which is acceptable for single-line fields like titles and labels

# fix: sanitize GITHUB_OUTPUT writes against newline injection

## Overview

The `version-bump-and-release.yml` workflow writes untrusted values (commit messages, PR titles) to `$GITHUB_OUTPUT` using `echo "key=value"` format. A commit message or PR title containing embedded newlines could inject arbitrary step outputs -- for example, forging `labels=semver:major` to trigger an unintended major version bump.

Related issue: #425. Found during review of PR #420.

## Problem Statement

GitHub Actions' `$GITHUB_OUTPUT` file uses a `key=value\n` format. When a value itself contains newlines, each newline starts a new key=value pair in the output file. The workflow has two high-risk injection points:

1. **Line 77** (`give_up` fallback): `echo "title=$(echo "$COMMIT_MSG" | head -1)"` -- `head -1` strips trailing lines but does not strip `\r` (carriage return), which can forge outputs on Windows-authored commits
2. **Line 118** (PR metadata): `echo "title=$(echo "$PR_JSON" | jq -r '.title')"` -- PR titles from the GitHub API are arbitrary strings that could contain newline characters

### Attack Scenario

#### Vector 1: `give_up` fallback (line 77) -- `\r` only

The `give_up` function uses `echo "title=$(echo "$COMMIT_MSG" | head -1)"`. Shell testing confirms that command substitution `$(...)` strips trailing newlines, and `head -1` filters to the first line. A commit message with embedded `\n` does NOT inject because `head -1` runs inside the substitution:

```bash
# Verified: \n is not injectable through head -1 in command substitution
COMMIT_MSG=$'feat: innocent title\nlabels=semver:major'
echo "title=$(echo "$COMMIT_MSG" | head -1)"
# Output: title=feat: innocent title  (safe -- second line is stripped)
```

However, `\r` (carriage return) IS preserved. A commit message containing `feat: innocent title\rlabels=semver:major` passes through `head -1` as a single line but includes the `\r`:

```bash
# Verified: \r passes through head -1
COMMIT_MSG=$'feat: innocent title\rlabels=semver:major'
echo "title=$(echo "$COMMIT_MSG" | head -1)" | cat -A
# Output: title=feat: innocent title^Mlabels=semver:major$
```

Whether `$GITHUB_OUTPUT` parsing treats `\r` as a line separator depends on the runner OS. Defense-in-depth: strip `\r` unconditionally.

#### Vector 2: PR title from API (line 118) -- CONFIRMED VULNERABILITY

This is the primary attack vector. When `jq -r '.title'` outputs a PR title containing a literal newline, the `echo "title=..."` format writes TWO separate lines to `$GITHUB_OUTPUT`:

```bash
# Verified: jq -r passes newlines through, echo writes them as separate lines
PR_JSON='{"title":"feat: innocent title\nlabels=semver:major"}'
echo "title=$(echo "$PR_JSON" | jq -r '.title')" | cat -A
# Output:
#   title=feat: innocent title$
#   labels=semver:major$
# ^^ TWO lines written to GITHUB_OUTPUT -- second line forges the labels output
```

The fix correctly prevents this:

```bash
printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')" | cat -A
# Output: title=feat: innocent titlelabels=semver:major$
# ^^ Single line -- newlines stripped, no injection possible
```

Note: `tr -d '\n\r'` concatenates the value rather than truncating it. For PR titles, this produces a garbled but safe value. The alternative (truncating at first newline) would require `head -1` instead of `tr -d`, but `tr -d` is more defensive since it also strips `\r`.

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

### Research Insights

**Why `printf` over `echo`:** `printf '%s\n'` treats the argument as a literal string and appends exactly one newline. `echo` has inconsistent behavior across shells (some interpret escape sequences, some don't) and can output multiple lines if the argument contains newlines. Using `printf` is the POSIX-portable safe choice.

**Why NOT heredoc/delimiter syntax:** GitHub Actions supports a multiline output format using delimiters (`{name}<<{delimiter}\n{value}\n{delimiter}`). However, GitHub's own documentation warns: "If the value is completely arbitrary then you shouldn't use this format" because the delimiter itself could appear in the value. Since our values are single-line by design, `printf` + `tr` is simpler and more robust.

**Why NOT environment variables as intermediary:** GitHub and OpenSSF recommend using `env:` blocks to pass untrusted inputs into shell scripts (prevents expression injection). This workflow already does that -- `COMMIT_MSG`, `PR_JSON` are passed via `env:`. The remaining vulnerability is in the `echo` output format, not the input handling.

**Alternative considered -- `head -1` instead of `tr -d`:** Using `head -1` would truncate at the first newline rather than stripping all newlines (concatenating). For PR titles, truncation is arguably better (preserves meaning of the first line). However, `head -1` does not strip `\r`, requiring an additional `tr -d '\r'` regardless. The `tr -d '\n\r'` approach is a single operation that handles both characters.

Sources:
- [GitHub docs: workflow commands -- setting output parameters](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#setting-an-output-parameter)
- [GitHub docs: script injection](https://docs.github.com/en/actions/concepts/security/script-injections)
- [OpenSSF: mitigating attack vectors in GitHub workflows](https://openssf.org/blog/2024/08/12/mitigating-attack-vectors-in-github-workflows/)
- [GitHub blog: four tips for secure workflows](https://github.blog/security/supply-chain-security/four-tips-to-keep-your-github-actions-workflows-secure/)

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

### Edge Cases

**`mktemp` paths with spaces:** On some runners, `mktemp` creates paths in `/tmp` which should never contain spaces, but `$TMPDIR` on macOS or custom environments could theoretically produce paths with special characters. The `echo "key=$(mktemp)"` pattern is safe because `mktemp` output is a single line without newlines. However, quoting `"$GITHUB_OUTPUT"` is still good practice for SC2086 compliance.

**Empty `jq` output:** If `PR_JSON` is malformed and `jq -r '.title'` returns empty, `printf 'title=%s\n' ""` writes `title=\n` which sets an empty title output. This matches the current `echo` behavior -- no regression.

**`jq -r` on missing field:** If `.title` is `null`, `jq -r` outputs the literal string `null`. The `// ""` fallback in jq (`'.title // ""'`) is not used here because the PR JSON is fetched from a validated PR number. If this becomes a concern, add `// ""` to the jq expression.

### Non-goals

- Switching to GitHub's heredoc/delimiter-based multiline output syntax -- the values here are single-line by design, and delimiter syntax adds complexity without benefit; GitHub docs warn "If the value is completely arbitrary then you shouldn't use this format"
- Auditing `scheduled-bug-fixer.yml` -- its GITHUB_OUTPUT writes use numeric issue numbers from validated sources (workflow_dispatch input or jq-filtered API output)
- Adding a reusable shell function for output writes -- the fix is 3 lines; abstraction would be overengineering
- Adding `set -euo pipefail` to workflow steps -- out of scope and would require its own audit (see learning: `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` for the three failure modes to check)

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

### Research Insights: Verification Commands

These shell commands can verify the fix locally without running the full workflow:

```bash
# Test 1: Verify \n injection is blocked on jq -r output
PR_JSON='{"title":"feat: title\nlabels=semver:major"}'
OUTPUT=$(printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')")
[[ $(echo "$OUTPUT" | wc -l) -eq 1 ]] && echo "PASS: single line" || echo "FAIL: multi-line"

# Test 2: Verify \r is stripped from commit message
COMMIT_MSG=$'feat: title\rlabels=semver:major'
OUTPUT=$(printf 'title=%s\n' "$(echo "$COMMIT_MSG" | head -1 | tr -d '\r')")
echo "$OUTPUT" | cat -A | grep -q '\^M' && echo "FAIL: \\r present" || echo "PASS: \\r stripped"

# Test 3: Verify clean input passes through unchanged
PR_JSON='{"title":"feat: add user auth (#123)"}'
OUTPUT=$(printf 'title=%s\n' "$(echo "$PR_JSON" | jq -r '.title' | tr -d '\n\r')")
[[ "$OUTPUT" == "title=feat: add user auth (#123)" ]] && echo "PASS" || echo "FAIL: $OUTPUT"

# Test 4: Verify labels pass through unchanged
PR_JSON='{"labels":[{"name":"semver:patch"},{"name":"bug"}]}'
OUTPUT=$(printf 'labels=%s\n' "$(echo "$PR_JSON" | jq -r '[.labels[].name] | join(",")' | tr -d '\n\r')")
[[ "$OUTPUT" == "labels=semver:patch,bug" ]] && echo "PASS" || echo "FAIL: $OUTPUT"
```

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

### Internal

- Issue: #425
- PR #420 (where the vulnerability was found during review)
- `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md` -- SHA pinning, input validation, exit code checks
- `knowledge-base/learnings/2026-03-03-fix-release-notes-pr-extraction.md` -- recent workflow fix that consolidated API calls
- `knowledge-base/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md` -- version bump workflow design rationale
- `knowledge-base/learnings/2026-02-27-github-actions-sha-pinning-workflow.md` -- action pinning patterns
- `knowledge-base/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- why not to casually add `set -euo pipefail`

### External

- [GitHub docs: workflow commands -- setting output parameters](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#setting-an-output-parameter)
- [GitHub docs: script injection](https://docs.github.com/en/actions/concepts/security/script-injections)
- [GitHub docs: security hardening for Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [OpenSSF: mitigating attack vectors in GitHub workflows](https://openssf.org/blog/2024/08/12/mitigating-attack-vectors-in-github-workflows/)
- [GitHub blog: four tips for secure workflows](https://github.blog/security/supply-chain-security/four-tips-to-keep-your-github-actions-workflows-secure/)
- [GitHub blog: catch workflow injections before attackers](https://github.blog/security/vulnerability-research/how-to-catch-github-actions-workflow-injections-before-attackers-do/)
