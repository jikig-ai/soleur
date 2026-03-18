# Learning: Extract shared bash test helpers to prevent implementation drift

## Problem

Two test files -- `ralph-loop-stuck-detection.test.sh` (79 assertions) and `resolve-git-root.test.sh` (11 assertions) -- duplicated four assert helpers (`assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists`), PASS/FAIL counters, and a results summary block. The implementations had drifted:

- **ralph-loop** used `[[ "$haystack" == *"$needle"* ]]` for `assert_contains` (safe under `set -euo pipefail`)
- **resolve-git-root** used `echo "$haystack" | grep -qF "$needle"` (latent failure: `grep -qF` returns exit code 1 on no-match, which triggers `set -e` abort before the function can print a FAIL message)

The `grep -qF` variant had not surfaced a bug yet because test assertions all happened to pass. A single failing assertion would abort the entire test run instead of reporting a FAIL line.

## Solution

Created `plugins/soleur/test/test-helpers.sh` with unified implementations:

- `assert_contains` uses the `[[ glob ]]` pattern, which is a bash conditional that returns true/false without triggering `set -e`
- `assert_eq`, `assert_file_exists`, `assert_file_not_exists`, PASS/FAIL counters, and `print_results` consolidated into the single file
- Both test files now `source "$SCRIPT_DIR/test-helpers.sh"` instead of inlining helpers

Also renamed `ralph-loop-stuck-detection.test.sh` to `ralph-loop.test.sh` since the file covers stuck detection, session isolation, TTL, and setup defaults.

## Key Insight

When two test files duplicate helper functions, implementation drift is inevitable. Extract shared helpers early. The cost of a `source` line is zero; the cost of divergent implementations is a latent bug that only surfaces when a test actually fails -- exactly the moment you need your test harness to be reliable.

For substring checks in bash: use `[[ "$haystack" == *"$needle"* ]]`, not `echo | grep -qF`. The `[[` conditional does not trigger `set -e` on false evaluation; `grep -qF` returns exit 1 on no match, which `set -euo pipefail` interprets as fatal.

## Session Errors

- Minor `git add` error: tried to stage old filename after `git mv` rename (exit 128). Recovered immediately by removing the stale path.

## Related Documentation

- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- same class of bug (grep exit 1 under pipefail)
- `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md` -- structural rule that test files must source, not copy
- `knowledge-base/project/learnings/2026-03-05-ralph-loop-stuck-detection-shell-counter.md` -- grep under pipefail in stop hook
- `knowledge-base/project/learnings/2026-03-14-bare-repo-helper-extraction-patterns.md` -- helper extraction design constraints

## Tags
category: test-failures
module: plugins/soleur/test
