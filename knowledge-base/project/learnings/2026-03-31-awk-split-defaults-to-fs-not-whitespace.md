---
module: System
date: 2026-03-31
problem_type: logic_error
component: tooling
symptoms:
  - "awk split() returns 1 field for a multi-word string when -F is set to TAB"
  - "wcount=1 despite rule text containing 12+ words"
  - "Jaccard similarity always 0 because all words treated as single token"
root_cause: config_error
resolution_type: code_fix
severity: high
tags: [awk, mawk, split, field-separator, tokenization, bash]
---

# Troubleshooting: awk split() Defaults to FS, Not Whitespace

## Problem

When awk is invoked with `-F'\t'` (TAB field separator), `split(string, array)` without a third argument uses FS (TAB) as the delimiter, not whitespace. Rule text containing spaces but no tabs is treated as a single field, causing all tokenization to fail silently.

## Environment

- Module: System (scripts/rule-audit.sh)
- Affected Component: Phase 2.5 Jaccard duplicate detection
- Date: 2026-03-31
- awk version: mawk 1.3.4 20250131

## Symptoms

- `split(t, parts)` returns `m=1` for a string like "priority chain for services 1 mcp tools"
- `wcount` stays at 1 (entire string stored as one "word")
- All rules appear to have < 4 content words and are skipped
- Duplicate detection finds 0 matches despite known duplicates existing

## What Didn't Work

**Attempted Solution 1:** Initial implementation used nested bash `while` loops with `comm -12` per pair for Jaccard computation.

- **Why it failed:** Performance — at 15K pairs, subprocess overhead would take ~26 minutes. Killed after 6 minutes. Rewrote to single awk pass.

**Attempted Solution 2:** Awk rewrite with `split(t, parts)` (no third argument).

- **Why it failed:** With `-F'\t'`, split() defaults to FS (TAB), not whitespace. The string has no tabs, so the entire string becomes parts[1]. This caused wcount=1 for all rules, and the < 4 word filter excluded everything.

## Session Errors

**`extract_hook_enforced()` crash under `set -euo pipefail`**

- **Recovery:** Added `|| true` to the `while` loop's pipeline to prevent grep exit code 1 from killing the script when no `[hook-enforced:]` annotations exist.
- **Prevention:** When adding `grep | while` pipelines in `set -euo pipefail` scripts, always append `|| true` after the `done`. This is documented in the existing learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` but was not applied to the pre-existing `extract_hook_enforced` function.

**Nested bash loop performance (26+ minute estimated runtime)**

- **Recovery:** Killed the process and rewrote to single awk pass with in-memory pairwise comparison (0.4s).
- **Prevention:** Never use per-pair subprocess invocations (`comm`, `sort`, `diff`) inside nested bash loops for O(n*m) comparisons. Use awk's in-memory arrays for set operations at scale.

**awk `split()` bug occurring in two locations**

- **Recovery:** Fixed `split(t, parts)` to `split(t, parts, " ")` in all three locations (main block tokenization and two END block wordset re-splits).
- **Prevention:** See Key Insight below — always pass explicit separator to `split()` when `-F` is set.

## Solution

Change all `split()` calls to use explicit space separator:

```bash
# Before (broken — split uses FS=TAB, not whitespace):
m = split(t, parts)
split(wordsets[i], wi)
split(wordsets[j], wj)

# After (fixed — explicit space separator):
m = split(t, parts, " ")
split(wordsets[i], wi, " ")
split(wordsets[j], wj, " ")
```

## Why This Works

In awk, `split(string, array)` without a third argument uses the current FS (Field Separator) as the delimiter. When the script is invoked with `-F'\t'`, FS is TAB. Strings that contain spaces but no tabs are not split at all — they become a single array element.

The POSIX spec says: "If fieldsep is not given, the value of FS shall be used." This is consistent across gawk, mawk, and nawk. It is NOT a mawk-specific bug — it is the correct behavior per spec.

The fix is to always pass an explicit third argument when the intended split character differs from FS: `split(t, parts, " ")`.

## Prevention

- When using awk with `-F` set to a non-space character (TAB, colon, pipe, etc.), ALWAYS pass an explicit third argument to `split()` calls that split on whitespace: `split(str, arr, " ")`
- This applies to all awk implementations (gawk, mawk, nawk) — it is POSIX behavior, not a vendor bug
- A standalone awk script (without `-F`) defaults FS to whitespace, which masks this issue in unit tests — the bug only appears when the script is invoked with a non-default `-F`

## Related Issues

- See also: [2026-03-03-set-euo-pipefail-upgrade-pitfalls.md](./2026-03-03-set-euo-pipefail-upgrade-pitfalls.md) — grep pipeline exit code under pipefail
- See also: [2026-03-05-awk-scoping-yaml-frontmatter-shell.md](./2026-03-05-awk-scoping-yaml-frontmatter-shell.md) — awk scoping gotcha
