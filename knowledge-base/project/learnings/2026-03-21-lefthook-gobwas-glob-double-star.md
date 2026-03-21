# Learning: Lefthook gobwas glob `**` matches 1+ directories, not 0+

## Problem

When adding a Lefthook pre-commit hook for Terraform files at `apps/*/infra/*.tf`,
the intuitive glob `apps/*/infra/**/*.tf` silently skips every file. All 12 `.tf`
files sit directly in `infra/` with no subdirectories, so `**` (which requires at
least one intermediate directory in gobwas) matches nothing.

## Solution

Use `apps/*/infra/*.tf` (single `*`) for files directly in `infra/`. The `**`
pattern in Lefthook's default `gobwas` glob matcher requires 1+ directory levels
between segments, unlike most glob implementations where `**` matches 0+.

If nested directories are later needed, two options:

1. Array glob: `glob: ["apps/*/infra/*.tf", "apps/*/infra/**/*.tf"]` (supported since lefthook 1.10.10)
2. Set `glob_matcher: doublestar` at the top level of `lefthook.yml` to switch to Go's doublestar library

## Key Insight

Lefthook's default glob matcher (gobwas/glob) has different `**` semantics than
bash, ripgrep, and most developer tools. This is a silent failure — the hook runs
but matches zero files and reports "skip: no files for inspection." Always test
glob patterns with `lefthook run pre-commit` after adding a new hook to verify
files actually match.

## Session Errors

- Markdown lint failure on first commit: `session-state.md` had missing blank lines
  around headings/lists (MD022/MD032). Fixed by adding blank lines per markdownlint rules.

## Tags

category: integration-issues
module: lefthook
