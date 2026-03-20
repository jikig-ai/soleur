---
title: "refactor: extract shared test helpers from ralph-loop test suite"
type: refactor
date: 2026-03-18
semver: patch
deepened: 2026-03-18
---

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Proposed Solution, Implementation Details, Edge Cases, Learnings)
**Research sources:** Project learnings (3), code analysis of both test files, lefthook config audit

### Key Improvements

1. Documented why glob-based `assert_contains` is mandatory (not just preferred) -- the grep version fails under `set -euo pipefail` when the needle is absent
2. Added implementation edge cases for `set -euo pipefail` interaction with `print_results` and sourcing semantics
3. Confirmed lefthook does not reference bash test filenames -- rename is safe with no CI impact
4. Identified `assert_eq` local variable style difference that the implementation should canonicalize

### New Considerations Discovered

- `resolve-git-root.test.sh` uses `exit 0` implicitly (no explicit exit on success path, line 127) while `ralph-loop` uses `exit 0` explicitly -- `print_results` unifies this
- Historical plan/spec documents reference the old filename extensively but are read-only artifacts -- no updates needed

# refactor: extract shared test helpers from ralph-loop test suite

Extract duplicated bash test helpers (`assert_eq`, `assert_contains`, PASS/FAIL counters) into a shared `test-helpers.sh` file. Both `ralph-loop-stuck-detection.test.sh` and `resolve-git-root.test.sh` duplicate these primitives with slight implementation differences.

Closes #660.

## Problem Statement

Two bash test files independently define the same assertion helpers:

| Helper | `ralph-loop-stuck-detection.test.sh` | `resolve-git-root.test.sh` |
|--------|--------------------------------------|---------------------------|
| `assert_eq` | `[[ "$expected" == "$actual" ]]` | Same logic, different local var style |
| `assert_contains` | `[[ "$haystack" == *"$needle"* ]]` (glob) | `echo "$haystack" \| grep -qF "$needle"` (grep) |
| `PASS`/`FAIL` counters | Global vars, `$((PASS + 1))` | Same |
| `assert_file_exists` | Present | Absent |
| `assert_file_not_exists` | Present | Absent |

The `assert_contains` implementations differ in behavior: the glob version handles multi-line strings differently from the grep version. Unifying avoids subtle test inconsistencies as more test files are added.

### Research Insights

**Why glob over grep is mandatory (not just preferred):**

The grep-based `assert_contains` in `resolve-git-root.test.sh` (line 36: `echo "$haystack" | grep -qF "$needle"`) has a latent failure mode under `set -euo pipefail`. When `grep -qF` finds no match, it returns exit code 1. Under pipefail, this propagates through the pipeline and would abort the script before reaching the FAIL counter increment. The glob-based version (`[[ "$haystack" == *"$needle"* ]]`) is a bash builtin that returns 0/1 without triggering errexit when used inside `if`. This aligns with the project learning from `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`.

**`assert_eq` local variable style canonicalization:**

The ralph-loop file uses multi-line declarations (lines 90-92):
```bash
local expected="$1"
local actual="$2"
local msg="$3"
```

The resolve-git-root file uses compact single-line (line 22):
```bash
local expected="$1" actual="$2" label="$3"
```

The plan's MVP uses multi-line declarations, which is correct -- it is more readable and follows the project's shell style convention of one declaration per line.

Also note the parameter name difference: `msg` vs `label`. The canonical version should use `msg` since that is what all 39 ralph-loop tests already use.

## Proposed Solution

1. Create `plugins/soleur/test/test-helpers.sh` containing:
   - `PASS` and `FAIL` counter initialization
   - `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists`
   - `print_results` function for the summary/exit-code block
   - Use the glob-based `assert_contains` (`[[ "$haystack" == *"$needle"* ]]`) as canonical -- it is mandatory under `set -euo pipefail` (see Research Insights above)

2. Update `ralph-loop-stuck-detection.test.sh`:
   - Replace inline helpers with `source "$SCRIPT_DIR/test-helpers.sh"`
   - Replace inline summary block with `print_results`
   - Keep domain-specific helpers (`setup_test`, `cleanup_test`, `create_state_file`, `run_hook`, `run_hook_stderr`) in the test file -- they are not shared
   - Remove the inline `set -euo pipefail` since `test-helpers.sh` sets it (or keep it for defense-in-depth -- either is acceptable since sourcing it again is a no-op)

3. Update `resolve-git-root.test.sh`:
   - Replace inline helpers with `source "$SCRIPT_DIR/test-helpers.sh"`
   - Replace inline summary block with `print_results`
   - Remove `PASS=0` and `FAIL=0` lines (now in `test-helpers.sh`)
   - Note: the 7 existing tests use `label` as the third parameter name in test calls, but the assertion functions accept positional args so no call-site changes are needed

4. Rename `ralph-loop-stuck-detection.test.sh` to `ralph-loop.test.sh` since the test file now covers session isolation, TTL, setup defaults, idle patterns, and repetition detection -- not just stuck detection.

## Non-Goals

- Adding new test assertions beyond what already exists in the two files
- Migrating bash tests to a different framework (bats, etc.)
- Converting bash tests to TypeScript (these test bash scripts that require shell-level integration)
- Refactoring the TypeScript `helpers.ts` -- it serves a different purpose (component discovery)

## Acceptance Criteria

- [x] `plugins/soleur/test/test-helpers.sh` exists with shared helpers
- [x] `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists` are defined once in `test-helpers.sh`
- [x] `print_results` function prints summary and exits with correct code
- [x] `ralph-loop-stuck-detection.test.sh` sources `test-helpers.sh` and removes inline duplicates
- [x] `resolve-git-root.test.sh` sources `test-helpers.sh` and removes inline duplicates
- [x] `ralph-loop-stuck-detection.test.sh` renamed to `ralph-loop.test.sh`
- [x] Run comment at top of renamed file updated to reflect new filename
- [x] All 39 ralph-loop tests pass: `bash plugins/soleur/test/ralph-loop.test.sh`
- [x] All 7 resolve-git-root tests pass: `bash plugins/soleur/test/resolve-git-root.test.sh`
- [x] `test-helpers.sh` uses `#!/usr/bin/env bash` shebang and `set -euo pipefail`
- [x] `test-helpers.sh` uses `local` for all function variables
- [x] No `$()` command substitution in the helper file (pure bash builtins only)

## Test Scenarios

- Given both test files source `test-helpers.sh`, when `bash plugins/soleur/test/ralph-loop.test.sh` runs, then all 39 tests pass
- Given both test files source `test-helpers.sh`, when `bash plugins/soleur/test/resolve-git-root.test.sh` runs, then all 7 tests pass
- Given `test-helpers.sh` is sourced, when `assert_contains "hello world" "world" "test"` is called, then it prints PASS
- Given `test-helpers.sh` is sourced, when `assert_contains "hello world" "xyz" "test"` is called, then it prints FAIL
- Given `test-helpers.sh` is sourced, when `assert_eq "a" "b" "test"` is called, then it prints FAIL with expected/actual diff
- Given `test-helpers.sh` is sourced, when `print_results` is called with FAIL=0, then exit code is 0
- Given `test-helpers.sh` is sourced, when `print_results` is called with FAIL>0, then exit code is 1
- Given `ralph-loop-stuck-detection.test.sh` is renamed, when old filename is used, then it does not exist
- Given the test file is renamed, when lefthook runs pre-push, then it finds and runs the renamed test file

## MVP

### plugins/soleur/test/test-helpers.sh

```bash
#!/usr/bin/env bash
# Shared test helpers for bash test suites.
# Source this file at the top of each .test.sh file.

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"

  if [[ -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1"
  local msg="$2"

  if [[ ! -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

print_results() {
  echo "=== Results ==="
  echo "Passed: $PASS"
  echo "Failed: $FAIL"
  echo ""

  if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
  else
    echo "ALL TESTS PASSED"
    exit 0
  fi
}
```

## Implementation Edge Cases

### `set -euo pipefail` sourcing semantics

When `test-helpers.sh` declares `set -euo pipefail`, this applies to the sourcing script's shell session (not a subshell). Both test files already declare `set -euo pipefail` at their top, so this is redundant but harmless. The sourcing test files should keep their own `set -euo pipefail` declaration for defense-in-depth -- if `test-helpers.sh` is ever sourced after other code, the strict mode is already active.

### `print_results` uses `exit`, not `return`

The `print_results` function uses `exit 0` and `exit 1` (not `return`). Since this function is sourced (not executed in a subshell), `exit` terminates the calling script. This is correct -- the test runner should exit with the appropriate code after printing results. Using `return` would silently continue execution after the summary, potentially running stale code or producing misleading output.

### `PASS` and `FAIL` are intentionally global

These counters are initialized in `test-helpers.sh` and modified by assertion functions. They must remain global (not local to any function) because they accumulate across all assertions in the sourcing script. The sourcing script must not re-declare them after `source test-helpers.sh` or the counters reset.

### Lefthook rename safety

The `lefthook.yml` pre-push hooks reference `bun test` and `bun test plugins/soleur/test/` for TypeScript tests but do not reference individual bash test filenames. The rename from `ralph-loop-stuck-detection.test.sh` to `ralph-loop.test.sh` has zero CI/hook impact. Bash test files are run manually or via explicit `bash plugins/soleur/test/<name>.test.sh` commands, not via lefthook.

### Historical references to old filename

24 files in `knowledge-base/project/` reference `ralph-loop-stuck-detection.test.sh` (old plans, specs, learnings). These are historical documentation artifacts and should not be updated -- they accurately reflect the state of the codebase at the time they were written.

## SpecFlow Notes

No CI/workflow changes. No conditional logic or infrastructure at risk. This is a pure file-level refactoring of test utilities. SpecFlow analysis is not applicable.

## Applicable Project Learnings

- **`2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`**: Grep in pipelines returns exit 1 on no match, which pipefail propagates. This is why the glob-based `assert_contains` is mandatory, not just preferred.
- **`2026-03-05-ralph-loop-stuck-detection-shell-counter.md`**: Documents the `|| true` pattern for grep under pipefail. Reinforces the glob choice.
- **`2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`**: Establishes the project pattern of sourcing production scripts into tests rather than copy-pasting functions. This refactoring applies the same principle to test infrastructure itself.
- **`2026-03-05-awk-scoping-yaml-frontmatter-shell.md`**: The ralph-loop test file tests awk-based frontmatter parsing. The test helper extraction does not touch these domain-specific test patterns -- only the shared assertion infrastructure.

## References

- Issue: #660
- Discovered during: #654
- `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` (39 tests, lines 89-145 contain duplicated helpers)
- `plugins/soleur/test/resolve-git-root.test.sh` (7 tests, lines 21-45 contain duplicated helpers)
- `plugins/soleur/test/helpers.ts` (TypeScript helpers -- unrelated, serves component discovery)
- `lefthook.yml` (verified: no bash test filename references)
