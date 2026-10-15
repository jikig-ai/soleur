---
title: "fix: resolve x-community.test.ts exit 127 and integrate bash tests into CI"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

# fix: resolve x-community.test.ts exit 127 and integrate bash tests into CI

Closes #879

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Problem, Implementation, Test Scenarios, Impact, Risks)

### Key Improvements

1. Refined root cause from hypothesis to confirmed two-vector failure: jq-direct tests exit 127, script-based tests exit 1 with wrong stderr
2. Added concrete failure-mode matrix showing exactly which tests fail and how
3. Identified that `HAS_OPENSSL` check is unnecessary -- `require_openssl` in x-community.sh already catches missing openssl with exit 1
4. Recommended switching CI from `bun test` to `scripts/test-all.sh` (not adding a separate step) for DRY parity with local runner
5. Added edge case: script-based tests with `FAKE_CREDS_ENV` also fail when jq is missing because `require_jq` fires before argument validation

### Relevant Learnings Applied

- `2026-03-20-bun-fpe-spawn-count-sensitivity.md`: CI should use `test-all.sh` (sequential isolation) to prevent Bun FPE crashes under high spawn counts
- `2026-03-18-bun-test-segfault-missing-deps.md`: Defense-in-depth via `bunfig.toml` already excludes worktrees; no additional pathIgnorePatterns needed
- `2026-03-18-stop-hook-jq-invalid-json-guard.md`: Confirms jq dependency management pattern in the codebase -- `command -v jq` guard, then use jq

## Problem

Two distinct test failures block `git push` via the pre-push hook:

### 1. x-community.test.ts exits 127 instead of expected values

The test file contains **two categories of test** with different failure modes when `jq` is missing:

**Category A: Direct jq invocation (exit 127)**

Lines 202, 227, 250, 276, 301, 326, 346, 370, 393 call `Bun.spawnSync(["jq", ...], { env: NO_CREDS_ENV })`. When jq is not installed, Bun cannot find the `jq` executable and the process exits 127 (command not found). These tests expect exit code 0.

**Category B: Script invocation via bash (exit 1, wrong stderr)**

Lines 52, 68, 78, 89, 100, 117, 127, 145, 526, 536, 547, 558, 568 call `Bun.spawnSync(["bash", SCRIPT_PATH, ...])`. The script's `main()` function calls `require_jq` (line 628) before dispatching to any command handler. When jq is missing, `require_jq` exits 1 with `"Error: jq is required but not installed."`. The tests expect either specific validation messages (`"Missing X API credentials"`, `"must be a numeric value"`, etc.) that never appear because `require_jq` terminates the script first. Exit code is 1 (matches for some tests) but stderr assertion fails.

**The handle_response tests (lines 408-518)** are also affected: `test-handle-response.sh` sources `x-community.sh` which defines `handle_response()`. When handle_response calls `jq` (lines 181, 199, 215, 232 of x-community.sh) and jq is missing, bash exits 127 under `set -euo pipefail`.

**Failure matrix:**

| Test Block | Lines | Spawns | jq Missing | openssl Missing |
|---|---|---|---|---|
| jq transform | 161-401 | `jq` directly | Exit 127 (not 0) | N/A (jq only) |
| Credential validation | 50-59 | `bash x-community.sh` | Exit 1, wrong stderr | Exit 1, wrong stderr |
| Argument validation | 66-155 | `bash x-community.sh` | Exit 1, wrong stderr | Exit 1, wrong stderr |
| handle_response | 408-518 | `bash test-handle-response.sh` | Exit 127 (jq in pipeline) | N/A |
| Unknown flag | 144-155 | `bash x-community.sh` | Exit 1, wrong stderr | Exit 1, wrong stderr |
| fetch-user-timeline | 524-575 | `bash x-community.sh` | Exit 1, wrong stderr | Exit 1, wrong stderr |
| Rename verification | 581-591 | `grep` directly | Passes (grep always available) | Passes |

**Root cause**: `jq` is not installed on the developer's machine. The env setup (`NO_CREDS_ENV`) correctly passes `process.env.PATH` to subprocesses, but jq is simply not available.

### 2. Bash test files not executed by CI

`plugins/soleur/test/ralph-loop.test.sh` and `plugins/soleur/test/resolve-git-root.test.sh` exist and pass locally but are never executed by CI:

- **`bun test`** only discovers `.test.ts` and `.test.js` files
- **`scripts/test-all.sh`** runs `bun test plugins/soleur/` which also only discovers Bun test files
- **CI workflow (`ci.yml`)** runs `bun test` at line 25
- **Pre-push hook** (`scripts/hooks/pre-push`) is the only runner that discovers and executes `.test.sh` files

The bash tests depend on `jq` (ralph-loop.test.sh line 79: `jq -n --arg msg "$message"`). If a developer without jq pushes a branch that modifies stop-hook.sh or resolve-git-root.sh, the pre-push hook discovers these bash tests and they fail with exit 127 from the jq call inside the test.

## Acceptance Criteria

- [x] `test/x-community.test.ts` gracefully handles missing `jq` (skip jq-dependent tests, not exit 127)
- [x] `plugins/soleur/test/ralph-loop.test.sh` runs in CI
- [x] `plugins/soleur/test/resolve-git-root.test.sh` runs in CI
- [x] Pre-push hook works without blocking for ALL branches when deps are present
- [x] No regression in existing test pass rate
- [x] Console warning emitted when jq tests are skipped locally

## Test Scenarios

- Given `jq` is not installed, when running `bun test test/x-community.test.ts`, then jq-dependent tests are skipped with a console warning and non-jq tests still run
- Given `jq` is installed, when running `bun test test/x-community.test.ts`, then all 31 tests pass (no regressions)
- Given CI runs on ubuntu-latest (which has jq pre-installed), when the test step executes, then all `.test.ts` tests pass AND all `.test.sh` tests pass
- Given a developer pushes a branch that modifies `plugins/soleur/hooks/stop-hook.sh`, when the pre-push hook runs, then `ralph-loop.test.sh` executes and passes (assuming jq is installed)
- Given `scripts/test-all.sh` runs locally, then bash test files in `plugins/soleur/test/` are included in the run
- Given a branch that modifies only `knowledge-base/` files, when the pre-push hook runs, then no tests are triggered (exit 0)

## Implementation Plan

### Phase 1: Add jq availability guard to x-community.test.ts

**File: `test/x-community.test.ts`**

Add a jq availability check at module scope (after imports, before any `describe` blocks):

```typescript
// test/x-community.test.ts (after line 13, before NO_CREDS_ENV)
const HAS_JQ =
  Bun.spawnSync(["jq", "--version"], {
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin" },
  }).exitCode === 0;

if (!HAS_JQ) {
  console.warn(
    "WARNING: jq is not installed. Skipping jq-dependent tests in x-community.test.ts. " +
    "Install jq for full test coverage: https://jqlang.github.io/jq/download/"
  );
}
```

Then conditionally skip the jq-dependent describe blocks:

```typescript
// jq transform tests (line 161) -- directly invokes jq
(HAS_JQ ? describe : describe.skip)(
  "x-community.sh fetch-mentions -- jq transform",
  () => { /* existing tests unchanged */ }
);

// handle_response tests (lines 408-518) -- sources x-community.sh, calls jq in pipeline
(HAS_JQ ? describe : describe.skip)(
  "x-community.sh handle_response -- 2xx",
  () => { /* existing tests unchanged */ }
);
// ... same pattern for all handle_response describe blocks (401, 403, default error)
```

**Why not skip script-based tests too?** The script-based tests (credential validation, argument validation, fetch-user-timeline, unknown flag, rename verification) should NOT be skipped. When jq is missing:

- `require_jq` exits 1 with a clear error -- this is correct behavior
- The tests will fail assertion on stderr message, but the exit code is correct
- Better approach: adjust these tests to accept EITHER the expected validation message OR the jq-missing message

Alternative for script-based tests (optional, lower priority):

```typescript
// For tests that invoke x-community.sh directly, accept jq-missing as a valid early exit
test("missing credentials exits 1 with descriptive error", () => {
  const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-mentions"], {
    env: NO_CREDS_ENV,
  });

  expect(result.exitCode).toBe(1);
  const stderr = decode(result.stderr);
  // Accept either the expected error or the jq-missing early exit
  if (!HAS_JQ) {
    expect(stderr).toContain("jq is required");
  } else {
    expect(stderr).toContain("Missing X API credentials");
  }
});
```

**Recommended approach**: Skip ALL jq-dependent blocks (including handle_response) and conditionally test script-based blocks. This is cleaner than conditional assertions.

### Phase 2: Integrate bash tests into scripts/test-all.sh

**File: `scripts/test-all.sh`**

The existing `run_suite` function uses `bun test`. Add a parallel `run_bash_suite` function and discovery loop:

```bash
# After existing run_suite function (line 32)
run_bash_suite() {
  local label="$1"
  suites=$((suites + 1))
  echo "--- $label ---"
  if bash "$label"; then
    echo "[ok] $label"
  else
    echo "[FAIL] $label" >&2
    failed=$((failed + 1))
  fi
}
```

After existing bun test suites (after line 39), add:

```bash
# --- Bash Tests ---
for f in plugins/soleur/test/*.test.sh; do
  [[ -f "$f" ]] || continue
  run_bash_suite "$f"
done
```

**Why `for` loop instead of `find`**: The glob `plugins/soleur/test/*.test.sh` is deterministic (sorted by locale) and doesn't recurse. `find` adds unnecessary complexity and non-deterministic ordering. The `[[ -f "$f" ]]` guard handles the no-match case where the glob expands to the literal string.

### Phase 3: Switch CI from `bun test` to `scripts/test-all.sh`

**File: `.github/workflows/ci.yml`**

Replace line 25:

```yaml
# Before:
      - name: Run tests
        run: bun test

# After:
      - name: Run tests
        run: bash scripts/test-all.sh
```

**Why switch rather than add a separate step:**

1. **DRY**: `test-all.sh` is the single source of truth for which test suites run. Adding bash tests to CI separately means maintaining two discovery lists.
2. **FPE defense**: The Bun FPE crash (documented in `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`) is mitigated by sequential isolation. `bun test` from root discovers all files and runs them in-process. `test-all.sh` runs each suite in a separate `bun test` invocation.
3. **Consistency**: Local `bun run test` (from package.json) already runs `scripts/test-all.sh`. CI should match.

**Caveat**: The existing CI also runs `bun test --coverage` for telegram-bridge in a second step (line 27-29). That step is independent and should remain unchanged.

### Phase 4: Verification

No code changes. Run:

1. `bun test test/x-community.test.ts` -- all 31 tests pass (jq available locally)
2. `bash scripts/test-all.sh` -- all suites pass including bash tests
3. `git push` -- pre-push hook runs cleanly

## Impact Analysis

| File | Change | Risk |
|---|---|---|
| `test/x-community.test.ts` | Add HAS_JQ guard, conditional skip | Low -- additive only, no logic change when jq present |
| `scripts/test-all.sh` | Add `run_bash_suite` + glob loop | Low -- additive, existing suites unchanged |
| `.github/workflows/ci.yml` | Switch `bun test` to `bash scripts/test-all.sh` | Medium -- changes test isolation. Mitigated by test-all.sh being the established runner |
| Source code | **No changes** | None |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Skipping jq tests reduces local coverage | Medium (devs without jq) | Low (CI always runs full suite) | Console warning + jq install URL in skip message |
| `test-all.sh` in CI runs slower than `bun test` | Low | Low (sequential adds ~5s overhead) | Bun FPE defense justifies the tradeoff |
| New bash tests in `plugins/soleur/test/` not automatically discovered | Low (glob handles it) | Low | Glob `*.test.sh` auto-discovers new files |
| `ralph-loop.test.sh` requires jq (line 79) | Medium | Medium (fails in CI if ubuntu drops jq) | ubuntu-latest includes jq; add `apt-get install jq` step as defense-in-depth if needed |

## Edge Cases

1. **Both jq and openssl missing**: Script-based tests still exit 1 (from `require_jq` early exit). Handle_response tests get exit 127 but are skipped by HAS_JQ guard. Covered.
2. **process.env.PATH is undefined**: Falls back to `/usr/bin:/bin:/usr/local/bin`. HAS_JQ check runs with this fallback PATH, so skip behavior is consistent with test behavior.
3. **jq installed but different version**: `jq --version` exits 0 regardless of version. The jq transform tests use standard jq features (INDEX, //, array indexing) available since jq 1.5. No version gating needed.
4. **Bash tests fail in CI due to git env leakage**: Both `ralph-loop.test.sh` and `resolve-git-root.test.sh` already have `unset GIT_DIR GIT_WORK_TREE` guards at the top. Covered.
5. **Pre-push hook discovers bash tests on branches that modify hook scripts**: This is correct behavior (intended by the pre-push hook's source-to-test mapping). No change needed.

## References

- Issue: [#879](https://github.com/jikig-ai/soleur/issues/879)
- PR that surfaced the issue: [#873](https://github.com/jikig-ai/soleur/pull/873)
- Bun FPE crash learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
- Bun segfault on missing deps: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
- jq guard pattern: `knowledge-base/project/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md`
- Pre-push hook: `scripts/hooks/pre-push`
- Sequential test runner: `scripts/test-all.sh`
- CI workflow: `.github/workflows/ci.yml`
- x-community script: `plugins/soleur/skills/community/scripts/x-community.sh`
- Test file: `test/x-community.test.ts`
- Test helper: `test/helpers/test-handle-response.sh`
- Bash tests: `plugins/soleur/test/ralph-loop.test.sh`, `plugins/soleur/test/resolve-git-root.test.sh`
- Bash test helpers: `plugins/soleur/test/test-helpers.sh`
