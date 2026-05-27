---
title: "Bash set -e inside functions leaks to caller scope — use || true pattern"
date: 2026-05-27
problem_type: runtime_error
component: ci_deploy_shell_script
severity: medium
symptoms:
  - "Function return code capture (VERIFY_RC=$?) never executes"
  - "Script exits on non-zero function return despite set +e at call site"
  - "local: can only be used in a function (bash error)"
root_cause: bash_set_e_function_scope_leak
tags: [bash, set-e, pipefail, functions, ci-deploy, shell-scripting]
related_issues:
  - 4538
related_prs:
  - 4539
synced_to: []
---

# Bash set -e inside functions leaks to caller scope — use || true pattern

## Problem

When writing `verify_inngest_functions()` for ci-deploy.sh (#4538), three bash scoping issues surfaced in sequence:

1. **`set -e` inside a function leaks globally.** The function toggled `set +e` before curl and `set -e` after. But `set -e` inside a function re-enables it for the entire shell, not just the function scope. When the function returned non-zero (exit 1 or 2), the caller's `VERIFY_RC=$?` never executed — the script exited at the function call line despite the caller wrapping it in `set +e`.

2. **`local` keyword outside a function.** The restart handler at script top level used `local verify_rc=$?`, which is illegal outside a function body.

3. **Mock sudo bypasses absolute paths.** After changing `sudo systemctl` to `sudo /usr/bin/systemctl` (matching sudoers Cmnd_Alias), the test mock sudo's `exec "$@"` passed `/usr/bin/systemctl` directly to the kernel, bypassing the mock systemctl in PATH.

4. **Case pattern outside `esac`.** The curl mock's `/v1/functions` handler was accidentally placed after `esac`, making it unreachable dead code with no syntax error.

## Solution

**For set -e leakage:** Never toggle `set -e` inside a bash function. Use `|| true` after commands that may fail:

```bash
# WRONG — set -e leaks to caller
verify_inngest_functions() {
  set +e
  response=$(curl -sf ... 2>/dev/null)
  local curl_rc=$?
  set -e  # This re-enables -e GLOBALLY, not just in-function
  ...
}

# RIGHT — || true prevents -e from triggering
verify_inngest_functions() {
  response=$(curl -sf ... 2>/dev/null) || true
  if [[ -z "$response" ]]; then ...
}
```

**For local outside function:** Use uppercase global variable names at script top level.

**For mock sudo:** Updated the mock to resolve absolute paths via PATH so mocks shadow system binaries:

```bash
create_mock_sudo() {
  cat > "$1/sudo" << 'MOCK'
#!/bin/bash
while [[ "${1:-}" == -* ]]; do shift; done
cmd="$1"; shift
if [[ "$cmd" == /* ]]; then
  base=$(basename "$cmd")
  resolved=$(type -P "$base" 2>/dev/null || true)
  if [[ -n "$resolved" ]]; then exec "$resolved" "$@"; fi
fi
exec "$cmd" "$@"
MOCK
}
```

## Key Insight

In bash, `set -e` and `set +e` modify global shell state, even when called inside a function. A function that toggles `set -e` internally makes it impossible for the caller to capture non-zero return codes via `$?` — the script exits before the assignment runs. The `|| true` pattern is the correct idiom for suppressing non-zero exit codes inside functions under `set -euo pipefail`.

## Session Errors

1. **Curl mock case placed outside `esac`** — The new `/v1/functions` pattern was inserted after the closing `esac` tag instead of inside the case block. Recovery: moved the pattern before `esac`. **Prevention:** Always verify case statement structure with `grep -n 'case\|esac'` after editing mock factories.

2. **`local` used at script top level** — `local verify_rc=$?` in the restart handler (not inside a function). Recovery: changed to `VERIFY_RC=$?`. **Prevention:** Only use `local` inside function bodies; use UPPERCASE for script-level variables.

3. **`set -e` function leak** — `verify_inngest_functions` toggled set -e internally, leaking to caller scope. Recovery: rewrote to use `|| true`. **Prevention:** Never toggle set -e inside functions; use `|| true` or `cmd || true` pattern.

4. **Mock sudo absolute path bypass** — `sudo /usr/bin/systemctl` bypassed mock via absolute path. Recovery: updated mock sudo to resolve via PATH. **Prevention:** When mock sudo receives absolute paths, resolve basename via PATH first.

## Tags
category: best-practices
module: ci-deploy
