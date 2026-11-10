# Learning: run_suite registrations must land inside want_scripts before the enumerate terminator

## Problem

Two registration failures in one PR: (a) suite file created but never added to test-all.sh (orphan-lint would catch it in CI but the suite never ran locally); (b) an attempt to "append last" placed `run_suite` after `_pj_drain`, the `=== N/N ===` summary, and the `--enumerate` exit — where parallel mode silently drops the verdict, enumerate omits the label (breaking shard-manifest regeneration + durations parity), and the summary marker lies. A mid-file insert inside `want_scripts_heavy` also silently skips the scripts-group enumerate stream.

## Solution

Insert `run_suite` inside `if want_scripts; then ... fi` (the block ending near `run_suite "scripts/ci-oracle-review"`), appended last within it. Verify mechanically: `bash scripts/test-all.sh --enumerate scripts | grep <label>` must print a SUITE_REGISTRATION line, then `python3 scripts/regenerate-shard-manifest.py --incremental --write` lands the suite-shard-legs.tsv + suite-durations.tsv rows.

## Key Insight

"Append last" means last INSIDE the gated registration block, not last in the file — the file's tail is an epilogue where run_suite is dead code. Never splice run_suite lines with line-number-arithmetic scripts; anchor to the enclosing `if want_scripts`/`fi` structure and re-verify enumerate output.

## Tags

category: workflow-issues
module: scripts/test-all.sh
issue: #12269
