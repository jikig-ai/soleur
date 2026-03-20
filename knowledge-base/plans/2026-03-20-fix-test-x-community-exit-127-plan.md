---
title: "fix: resolve x-community.test.ts exit 127 and integrate bash tests into CI"
type: fix
date: 2026-03-20
---

# fix: resolve x-community.test.ts exit 127 and integrate bash tests into CI

Closes #879

## Problem

Two distinct test failures block `git push` via the pre-push hook:

### 1. x-community.test.ts exits 127 instead of 1

All tests in `test/x-community.test.ts` that spawn shell commands fail with exit code 127 (command not found) on some developer machines. The tests define `NO_CREDS_ENV` and `FAKE_CREDS_ENV` with a restricted environment:

```typescript
// test/x-community.test.ts:25-28
const NO_CREDS_ENV: Record<string, string> = {
  PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin",
  HOME: process.env.HOME ?? "/tmp",
};
```

`Bun.spawnSync` replaces the entire environment (does not merge). If `process.env.PATH` is available (the common case), the spawned process inherits the developer's PATH. However, exit 127 can occur when:

- **jq is missing**: The jq transform tests (lines 202, 227, 250, 276, 301, 326, 346, 370, 393) call `Bun.spawnSync(["jq", ...], { env: NO_CREDS_ENV })`. If `jq` is not installed, these tests get exit 127 rather than the expected exit 0.
- **openssl is missing**: The `x-community.sh` script calls `require_openssl` in `main()`, but the pre-flight dependency check uses `command -v` which exits 1, not 127. However, with `set -euo pipefail`, if a later command in the script pipeline fails to find a binary, bash exits 127.
- **Fallback PATH is too narrow**: If `process.env.PATH` is somehow undefined (rare but possible in sandboxed/containerized environments), the fallback `/usr/bin:/bin:/usr/local/bin` may not include `jq` or `openssl` on all systems.

**Root cause hypothesis**: The most likely cause is that `jq` is not installed on the developer's machine. The x-community.sh script has its own `require_jq` check that exits 1 with a descriptive error, but the jq transform tests (lines 161-401) invoke `jq` directly via `Bun.spawnSync(["jq", ...])`, bypassing the script's dependency check entirely. When `jq` is not installed, those tests get exit 127 from the OS, not exit 1 from the script.

### 2. Bash test files not executed by CI

`plugins/soleur/test/ralph-loop.test.sh` and `plugins/soleur/test/resolve-git-root.test.sh` exist and pass locally, but are never executed by CI because:

- `bun test` only discovers `.test.ts` and `.test.js` files, not `.test.sh`
- `scripts/test-all.sh` runs `bun test plugins/soleur/` which also only discovers Bun test files
- The CI workflow (`ci.yml`) runs `bun test` which cannot discover bash test files
- Only the pre-push hook discovers and runs `.test.sh` files (when their paths appear in the diff)

This means the bash tests only run locally via the pre-push hook and never in CI, creating a coverage gap where CI can pass but local pushes fail.

## Acceptance Criteria

- [ ] `test/x-community.test.ts` gracefully handles missing `jq` (skip or exit cleanly, not 127)
- [ ] `plugins/soleur/test/ralph-loop.test.sh` runs in CI
- [ ] `plugins/soleur/test/resolve-git-root.test.sh` runs in CI
- [ ] Pre-push hook works without blocking for ALL branches
- [ ] No regression in existing test pass rate

## Test Scenarios

- Given `jq` is not installed, when running `bun test test/x-community.test.ts`, then jq-dependent tests skip with a clear message (not exit 127)
- Given `jq` is installed, when running `bun test test/x-community.test.ts`, then all tests pass as before
- Given CI runs on ubuntu-latest, when the test step executes, then both `.test.ts` and `.test.sh` files are run
- Given a developer pushes a branch that modifies `plugins/soleur/hooks/stop-hook.sh`, when the pre-push hook runs, then `ralph-loop.test.sh` executes and passes
- Given a clean main branch, when `scripts/test-all.sh` runs, then bash test files in `plugins/soleur/test/` are included

## Implementation Plan

### Phase 1: Fix jq dependency guard in x-community.test.ts

**File: `test/x-community.test.ts`**

Add a jq availability check at module scope before any tests run. Use `Bun.spawnSync(["jq", "--version"])` to detect jq. If jq is not found, use `describe.skip` for the jq transform test block (lines 161-401) instead of `describe`. This follows Bun's test API for conditional skipping.

```typescript
// test/x-community.test.ts (top of file, after imports)
const HAS_JQ = Bun.spawnSync(["jq", "--version"], {
  env: { PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin" },
}).exitCode === 0;
```

Then change the jq transform describe block:

```typescript
// Before:
describe("x-community.sh fetch-mentions -- jq transform", () => { ... });

// After:
(HAS_JQ ? describe : describe.skip)("x-community.sh fetch-mentions -- jq transform", () => { ... });
```

Similarly, check for `openssl` availability for the script invocation tests that depend on it:

```typescript
const HAS_OPENSSL = Bun.spawnSync(["openssl", "version"], {
  env: { PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin" },
}).exitCode === 0;
```

For the script invocation tests, the x-community.sh script's own `require_jq`/`require_openssl` handle missing dependencies by exiting 1. So these tests should pass regardless. The issue is only with direct `jq` invocation in the jq transform tests.

### Phase 2: Integrate bash tests into scripts/test-all.sh

**File: `scripts/test-all.sh`**

Add a new section after the existing Bun test suites that discovers and runs `.test.sh` files:

```bash
# --- Run Bash Tests ---
while IFS= read -r bt; do
  [[ -z "$bt" ]] && continue
  run_bash_suite "$bt"
done < <(find plugins/soleur/test -name '*.test.sh' -type f 2>/dev/null)
```

Add a `run_bash_suite` helper:

```bash
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

### Phase 3: Add bash tests to CI workflow

**File: `.github/workflows/ci.yml`**

Add a step after the existing Bun test step to run bash test files:

```yaml
- name: Run bash tests
  run: |
    for f in plugins/soleur/test/*.test.sh; do
      [ -f "$f" ] || continue
      echo "--- $f ---"
      bash "$f"
    done
```

Alternatively, if `scripts/test-all.sh` already runs bash tests after Phase 2, change the CI test step from `bun test` to `bash scripts/test-all.sh`. This is the simpler approach and ensures CI and local test runners use the same discovery logic.

### Phase 4: Ensure pre-push hook works cleanly

The pre-push hook already handles `.test.sh` files correctly (lines 80-99 in `scripts/hooks/pre-push`). No changes needed to the hook itself, but verify the fix from Phase 1 prevents exit 127 in the pre-push context.

## Impact Analysis

- **test/x-community.test.ts**: Modified to skip jq-dependent tests when jq is not installed
- **scripts/test-all.sh**: Modified to also run `.test.sh` files
- **.github/workflows/ci.yml**: May be modified to run bash tests (or switch to `test-all.sh`)
- **No changes to source code** (plugins/soleur/skills/community/scripts/x-community.sh is not modified)

## Risks

- Skipping jq tests reduces coverage on machines without jq. Mitigation: CI (ubuntu-latest) has jq, so CI always runs the full suite. Add a console warning when skipping.
- Changing CI from `bun test` to `scripts/test-all.sh` changes test isolation behavior. Mitigation: `test-all.sh` already runs each suite sequentially, which is the established pattern for avoiding Bun FPE crashes.

## References

- Issue: #879
- PR that surfaced the issue: #873
- Bun FPE crash learning: `knowledge-base/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
- Pre-push hook: `scripts/hooks/pre-push`
- Sequential test runner: `scripts/test-all.sh`
- x-community script: `plugins/soleur/skills/community/scripts/x-community.sh`
- Test file: `test/x-community.test.ts`
- Bash tests: `plugins/soleur/test/ralph-loop.test.sh`, `plugins/soleur/test/resolve-git-root.test.sh`
