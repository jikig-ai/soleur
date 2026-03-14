# Learning: Content publisher channel extension pattern

## Problem
Adding a new publishing channel (LinkedIn) to the multi-channel content-publisher required touching multiple files and matching existing patterns precisely. The security review flagged a potential argument injection via `--text "$content"` where content starting with `--` could be misinterpreted as flags.

## Solution
The argument injection concern was a false positive: when `--text "$content"` is parsed by a `case "$1"` loop, `$content` is consumed as the *value* of `--text` via `text="$2"; shift 2`, not as a standalone argument. Content starting with `--` is safely assigned to the variable, not parsed as a flag.

The channel extension pattern is mechanical — 6 touchpoints:
1. `channel_to_section()` — add case mapping
2. `post_<channel>()` — credential check, extract content, call script, handle error
3. `create_<channel>_fallback_issue()` — dedup issue on failure
4. Main dispatch loop — add case
5. `main()` — validate script path when credentials set
6. CI workflow — add secrets to env block

## Key Insight
When a function uses `case "$1"` with `--flag) value="$2"; shift 2`, the value argument is consumed positionally — it cannot be reinterpreted as a flag regardless of its content. The `--` end-of-options sentinel is unnecessary (and would break the parser if inserted between flag and value). Always trace through the argument parser before applying generic "add `--`" security advice.

Happy-path tests are easily missed when TDD focuses on defensive behaviors (skip conditions, error propagation). Review agents caught this gap — the success path (`[ok] LinkedIn post published.`) was the only untested path.

## Tags
category: integration-issues
module: content-publisher
