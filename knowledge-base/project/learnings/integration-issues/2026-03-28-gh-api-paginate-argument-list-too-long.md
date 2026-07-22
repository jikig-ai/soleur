---
title: gh api --paginate output exceeds shell argument limits
date: 2026-03-28
category: engineering
tags: [gh-api, paginate, jq, argument-list, shell-limits, community-monitor]
symptoms: [jq: Argument list too long when passing paginated gh api output via --argjson, github-community.sh fetch-interactions fails on repos with many comments]
module: community
component: tooling
problem_type: integration_issue
resolution_type: code_fix
root_cause: config_error
severity: medium
---

# Troubleshooting: gh api --paginate output exceeds shell argument limits

## Problem

When using `gh api --paginate` to fetch all issue comments, the output can exceed the shell's **per-argument** size limit. Passing the result to `jq` via `--argjson` in a command substitution fails with "Argument list too long."

> **CORRECTION (2026-07-19, #6695).** This file originally attributed the limit to
> `ARG_MAX` (~2 MB, the *total* argv+envp ceiling). That is the wrong model. The
> binding constraint is **`MAX_ARG_STRLEN` = 131,072 B PER ARGUMENT** (32 x 4 KB
> pages), a hard kernel constant that `getconf` does not report. Bisected:
> 131,071 B passes, 131,072 B fails with E2BIG.
>
> The wrong model is why this fix was applied to `cmd_fetch_interactions` only
> and never back-propagated. Judged against a 2 MB ceiling the sibling call
> sites look safe; judged against the real 128 KB per-argument ceiling,
> `cmd_activity` and `cmd_contributors` were **already over it** and had been
> failing on as few as 10 commits, every run, for months (#6695). The correct
> model was independently recorded in
> `learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md`.

## Environment

- Module: community (github-community.sh)
- Affected Component: `cmd_fetch_interactions()` in `github-community.sh`
- Date: 2026-03-28

## Symptoms

- `jq: Argument list too long` error when running `fetch-interactions 7` on a repo with many comments
- Only affects paginated endpoints returning large datasets; non-paginated commands with `per_page=100` work fine

## What Didn't Work

**Attempted Solution 1:** Store paginated output in a shell variable, then pass via `jq -n --argjson comments "$comments"`

- **Why it failed:** Shell variables can hold large strings, but passing one as a single `jq --argjson` argument exceeds **`MAX_ARG_STRLEN` (131,072 B per argument)** -- not `ARG_MAX` (~2 MB total), see the correction above. The `issues/comments` endpoint returns the full comment body for every comment, making payloads large even with pagination merged via `jq -s 'add // []'`.

## Solution

Use a temp file instead of a shell variable. Write the paginated output to a temp file, then pass the file as an argument to `jq` (file input, not `--argjson`).

**Code changes:**

```bash
# Before (broken):
comments=$(gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" \
  --paginate 2>&1 | jq -s 'add // []') || { ... }
jq -n --argjson comments "$comments" '{ ... }'

# After (fixed):
tmpfile=$(mktemp)
if ! gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" \
  --paginate 2>/dev/null | jq -s 'add // []' > "$tmpfile"; then
  rm -f "$tmpfile"
  exit 1
fi
jq '{ ... }' "$tmpfile"
rm -f "$tmpfile"
```

## Why This Works

1. **Root cause:** The per-argument size limit (`MAX_ARG_STRLEN`, 131,072 B) applies to EACH single argument -- so one large binding breaches it even when total argv is far under `ARG_MAX`. `jq -n --argjson key "$variable"` expands the variable into a command-line argument, which is subject to this limit.
2. **File input bypasses the limit:** When `jq` reads from a file argument (not `--argjson`), it reads the file via file I/O, not command-line argument expansion. No size limit applies.
3. **The existing `cmd_repo_stats()` uses `--argjson` for stargazers:** ~~This works because stargazers are small (just login + date).~~ **This conclusion was wrong and is retracted (#6695).** It was derived from the 2 MB model; against the real 128 KB per-argument ceiling the stargazer binding was also unsafe, and `cmd_activity`/`cmd_contributors` were already failing. All five unbounded bindings in `github-community.sh` were converted to spooled files + `--slurpfile` in #6695. **Generalize: after fixing one call site of an argv-size defect, grep every sibling binding in the file and measure it against 131,072 B -- "X is unaffected" is a hypothesis, not a fact.**

## Prevention

- When using `gh api --paginate` on endpoints that return large payloads (comments, PR reviews, file contents), always use temp files instead of shell variables + `--argjson`.
- The existing `gh api --paginate` learning (2026-03-24) covers the `jq -s 'add // []'` merge pattern but does not cover the argument-size issue. This learning extends it.
- Rule of thumb: if the API response includes user-generated content (comment bodies, PR descriptions), expect large payloads and use file-based `jq` input.

## Related Issues

- See also: [2026-03-24-gh-api-paginate-concatenated-arrays.md](../2026-03-24-gh-api-paginate-concatenated-arrays.md) -- pagination merge pattern
- See also: [2026-03-09-shell-api-wrapper-hardening-patterns.md](../2026-03-09-shell-api-wrapper-hardening-patterns.md) -- five-layer hardening
