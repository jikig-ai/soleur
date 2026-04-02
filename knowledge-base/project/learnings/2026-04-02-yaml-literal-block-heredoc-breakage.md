# Learning: Heredocs and multi-line strings break YAML literal blocks

## Problem

The `main-health-monitor.yml` workflow failed on every push with "This run likely failed because of a workflow file issue" and zero jobs created. GitHub Actions couldn't parse the YAML at all.

## Root Cause

Three constructs inside `run: |` blocks had content at column 0 (zero indentation), which is below the YAML literal block's base indentation (~10 spaces). YAML treats any line with less indentation than the block base as the end of the block, corrupting the parse tree:

1. Multi-line `--body "...\n\nRun: $URL"` where continuation lines were unindented
2. Heredoc body content (`<<ISSUE_EOF ... ISSUE_EOF`) at column 0
3. Multi-line `--comment "...\n\nRun: $URL"` same pattern

## Solution

- Replace heredocs with `{ echo "..."; echo "..."; } > /tmp/file.md`
- Replace multi-line CLI args with shell variables built via `$'\n\n'` concatenation
- Both patterns keep all content properly indented within the YAML block

## Key Insight

YAML literal blocks (`|`) and heredocs are fundamentally incompatible in GitHub Actions workflows. Heredoc terminators must be at column 0 in bash, but YAML literal blocks require all content at the base indentation level. There is no way to satisfy both constraints simultaneously. Always use `{ echo; }` blocks or `printf` instead.

## Tags

category: build-errors
module: ci
