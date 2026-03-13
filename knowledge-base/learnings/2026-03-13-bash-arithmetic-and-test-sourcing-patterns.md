# Learning: Bash Arithmetic Underscore Separators and Test-Sourcing via BASH_SOURCE Guard

## Problem 1: Bash arithmetic rejects underscore digit separators

The week-number calculation used `86_400` (seconds per day) as a readability separator:

```bash
local seconds_per_week=$((7 * 86_400))
```

This works in Python, Rust, Ruby, and Java. It fails in Bash. Bash's `$(( ))` arithmetic
treats `86_400` as a variable name (identifiers can contain underscores), not a numeric
literal. If unset, it evaluates to `0`, producing a division-by-zero.

**Fix:** Remove underscores. Use comments for readability:

```bash
local seconds_per_week=$((7 * 86400))  # 7 days * 86400 sec/day
```

**Detection:** Any `$(( ))` expression with `[0-9]_[0-9]` is suspect.

## Problem 2: Copy-pasted test functions diverge from production code

The test file copy-pasted `detect_phase()`, `determine_status()`, and other functions from
the production script. This meant tests verified a copy, not the real code. A bug in
production would not be caught.

**Fix:** Two-part refactor:

1. Guard `main()` with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` (Bash equivalent of Python's
   `if __name__ == "__main__"`)
2. Test file sources the production script: `source "$SCRIPT_DIR/weekly-analytics.sh"`
3. Extract duplicated patterns (e.g., `to_epoch()` helper replacing 11 copies of the
   GNU/BSD date fallback)

**Structural rule:** Testable bash functions must live outside `main()`. Test files must
`source` the production script, never copy functions.

## Key Insight

Patterns that work in other languages (underscore separators, class-based test isolation)
do not transfer to Bash. Bash arithmetic is a thin wrapper around C `long` operations with
variable-name substitution. Bash has no module system, so the `BASH_SOURCE` guard is the
closest equivalent to Python's `__name__` check.

## Session Errors

1. `soleur:plan_review` skill unavailable in subagent session (non-blocking)
2. `worktree-manager.sh cleanup-merged` failed from bare repo root (recovered from worktree)
3. `86_400` caused "value too great for base" in bash arithmetic
4. GitHub Actions workflow edit blocked by security hook (fixed with env: variables)

## Tags
category: prevention
module: scripts/weekly-analytics
