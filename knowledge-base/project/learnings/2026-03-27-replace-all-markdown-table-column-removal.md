---
module: Claude Code Edit Tool
date: 2026-03-27
problem_type: logic_error
component: edit_tool
symptoms:
  - "Markdown table cells lose leading space after replace_all column removal"
  - "Table renders with |Value instead of | Value after bulk edit"
root_cause: adjacent_whitespace_destruction
severity: medium
tags: [replace-all, markdown-tables, edit-tool, spacing]
synced_to: []
---

# Learning: replace_all on markdown table columns destroys adjacent cell spacing

## Problem

When using `replace_all` to remove a redundant column from markdown tables (e.g., removing an "Applicable" column that was always "Yes"), the replacement pattern `" | Yes | "` replaced with `" |"` collapses the whitespace before the next cell value.

Before: `"| Dashboard | Yes | Partial | console.log | evidence |"`
Pattern: `" | Yes | "` -> `" |"`
After: `"| Dashboard |Partial | console.log | evidence |"`

The missing space before "Partial" (should be `| Partial |`) breaks markdown table readability and could break strict parsers.

## Solution

After removing the column with a single `replace_all`, run follow-up replacements to restore spacing for each possible cell value:

```text
replace_all: " |Partial |"  -> " | Partial |"
replace_all: " |Implemented |"  -> " | Implemented |"
replace_all: " |Not Implemented |"  -> " | Not Implemented |"
replace_all: " |N/A |"  -> " | N/A |"
```

Alternatively, use a two-step approach: replace `" | Yes |"` with `" |"` (keeping the trailing space from "Yes"), then verify the result. The safer approach is to replace with `" | "` (pipe-space) instead of just `" |"` (pipe only).

## Key Insight

When removing a column from markdown tables via `replace_all`, the replacement string must account for the spacing convention of the adjacent column. Replace `" | ColumnValue | "` with `" | "` (not `" |"`) to preserve the leading space of the next cell. This is a specific instance of the broader pattern: `replace_all` operates on exact byte sequences and does not understand markdown table structure.

## Session Errors

1. **Markdownlint rejected session-state.md on first commit attempt** — Missing blank lines around headings and lists. Recovery: rewrote file with correct markdown formatting. **Prevention:** When writing markdown files inline (not from templates), add blank lines around every heading and list.

2. **replace_all destroyed table cell spacing** — Removing "Applicable" column with `replace_all` of `" | Yes | "` -> `" |"` collapsed whitespace before status values. Recovery: four additional `replace_all` operations to restore spacing for each status value (Partial, Implemented, Not Implemented, N/A). **Prevention:** When removing markdown table columns, replace with `" | "` (pipe with spaces) not `" |"` (pipe only) to preserve adjacent cell spacing.

## Tags

category: logic-errors
module: edit-tool
