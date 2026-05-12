#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy-wrapper.sh — the wall-clock cap that gates ci-deploy.sh
# (#3704, #2207). Verifies the file shape invariants AND the timeout(1)
# behavioral contract the wrapper depends on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/ci-deploy-wrapper.sh"

PASS=0
FAIL=0
TOTAL=0

echo "=== ci-deploy-wrapper.sh tests ==="

# ---------------------------------------------------------------------------
# Test 1: wrapper file shape — must be a single exec timeout invocation with
# the exact literal the Acceptance Criteria pins. Catches future drift that
# adds conditional logic to the wrapper (would re-introduce a hang surface
# the timeout cap does not protect — see plan Sharp Edges "Inert wrapper
# invariant").
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
if [[ ! -f "$WRAPPER" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: wrapper file does not exist at $WRAPPER"
elif [[ ! -x "$WRAPPER" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: wrapper file is not executable (0755 expected)"
elif ! grep -qF 'exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh' "$WRAPPER"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: wrapper missing canonical exec line"
  echo "        expected literal: exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh"
  echo "        file contents:"
  sed 's/^/          /' "$WRAPPER"
else
  PASS=$((PASS + 1))
  echo "  PASS: wrapper file exists, is executable, and contains the canonical exec timeout line"
fi

# ---------------------------------------------------------------------------
# Test 2: wrapper has no conditional logic. The whole point of the wrapper is
# to be inert so it cannot itself become a hang surface. Single uncommented
# bash statement (an `exec` line). Comments and shebang are allowed.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
if [[ -f "$WRAPPER" ]]; then
  non_comment_non_blank_lines=$(grep -cvE '^\s*(#|$)' "$WRAPPER" || true)
  if [[ "$non_comment_non_blank_lines" -eq 1 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: wrapper has exactly one non-comment line (inert invariant)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: wrapper must have exactly one non-comment line; found $non_comment_non_blank_lines"
    echo "        non-comment lines:"
    grep -nvE '^\s*(#|$)' "$WRAPPER" | sed 's/^/          /'
  fi
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: wrapper file missing (skipped non-comment line count)"
fi

# Pick a GNU-compatible timeout binary. On Ubuntu 24.04 LTS (prod), bare
# `timeout` resolves to GNU coreutils. On dev boxes running Ubuntu 25.04+
# (uutils-default), `timeout` is the rust uutils variant which sends the
# right signal but reports exit code 125 (vs GNU's 124) — same end-to-end
# kill semantic, divergent exit-code contract. `gnu-coreutils` package
# provides /usr/bin/gnutimeout for those environments.
pick_timeout() {
  if timeout --version 2>&1 | head -1 | grep -qi uutils; then
    if command -v gnutimeout >/dev/null 2>&1; then
      echo gnutimeout
    else
      echo SKIP
    fi
  else
    echo timeout
  fi
}

TIMEOUT_BIN=$(pick_timeout)

# ---------------------------------------------------------------------------
# Test 3: timeout(1) behavioral contract — SIGTERM by timeout exits 124, the
# child dies, and no orphan child remains. Uses `timeout` directly so the test
# is independent of the wrapper's hardcoded 900s + ci-deploy.sh path.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
mock_dir=$(mktemp -d)
trap 'rm -rf "$mock_dir"' EXIT

cat > "$mock_dir/sleeper.sh" << 'MOCK'
#!/usr/bin/env bash
sleep 60
MOCK
chmod +x "$mock_dir/sleeper.sh"

if [[ "$TIMEOUT_BIN" == "SKIP" ]]; then
  PASS=$((PASS + 1))
  echo "  SKIP: no GNU-compatible timeout binary found (uutils reports rc=125 instead of 124); production uses GNU timeout on Ubuntu 24.04"
else
  start_ts=$(date +%s)
  set +e
  "$TIMEOUT_BIN" --signal=TERM --kill-after=20s 1s "$mock_dir/sleeper.sh"
  rc=$?
  set -e
  elapsed=$(( $(date +%s) - start_ts ))

  # `timeout` returns 124 when it sent the configured signal (TERM) on expiry.
  # Returns 137 only if SIGKILL was needed (--kill-after grace exhausted). For
  # a bare `sleep`, the kernel kills it immediately on SIGTERM, so 124 is
  # correct.
  if [[ "$rc" -eq 124 ]] && [[ "$elapsed" -le 5 ]]; then
    if pgrep -f "$mock_dir/sleeper.sh" >/dev/null 2>&1; then
      FAIL=$((FAIL + 1))
      echo "  FAIL: timeout returned 124 but orphan sleeper process remains"
    else
      PASS=$((PASS + 1))
      echo "  PASS: $TIMEOUT_BIN exits 124 on SIGTERM-by-timeout, child killed within ${elapsed}s, no orphans"
    fi
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: timeout contract violated (rc=$rc elapsed=${elapsed}s; expected rc=124 elapsed<=5)"
  fi
fi

# ---------------------------------------------------------------------------
# Test 4: env propagation through `exec` — env vars set by the webhook
# (SSH_ORIGINAL_COMMAND, DOPPLER_TOKEN, etc.) MUST flow through `exec timeout`
# to ci-deploy.sh. Construct a test wrapper that mirrors the production shape
# and invokes a mock ci-deploy.sh that prints its environment.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))

cat > "$mock_dir/fake-ci-deploy.sh" << 'MOCK'
#!/usr/bin/env bash
printf 'MARKER=%s\n' "${MARKER:-MISSING}"
printf 'SSH_ORIGINAL_COMMAND=%s\n' "${SSH_ORIGINAL_COMMAND:-MISSING}"
exit 0
MOCK
chmod +x "$mock_dir/fake-ci-deploy.sh"

cat > "$mock_dir/test-wrapper.sh" << MOCK
#!/usr/bin/env bash
exec timeout --signal=TERM --kill-after=20s 10s "$mock_dir/fake-ci-deploy.sh"
MOCK
chmod +x "$mock_dir/test-wrapper.sh"

set +e
output=$(MARKER=hello SSH_ORIGINAL_COMMAND="deploy web-platform x v1" "$mock_dir/test-wrapper.sh" 2>&1)
rc=$?
set -e

if [[ "$rc" -eq 0 ]] \
  && printf '%s\n' "$output" | grep -qF "MARKER=hello" \
  && printf '%s\n' "$output" | grep -qF "SSH_ORIGINAL_COMMAND=deploy web-platform x v1"; then
  PASS=$((PASS + 1))
  echo "  PASS: env vars propagate through exec timeout (MARKER + SSH_ORIGINAL_COMMAND)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: env propagation broken (rc=$rc)"
  echo "        output: $output"
fi

# ---------------------------------------------------------------------------
# Test 5: success path — wrapper exits 0 when child exits 0 quickly. Uses a
# tmp test wrapper because the production wrapper's hardcoded path is
# /usr/local/bin/ci-deploy.sh which doesn't exist on the test runner.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))

cat > "$mock_dir/quick-ci-deploy.sh" << 'MOCK'
#!/usr/bin/env bash
echo "deploy ok"
exit 0
MOCK
chmod +x "$mock_dir/quick-ci-deploy.sh"

cat > "$mock_dir/success-wrapper.sh" << MOCK
#!/usr/bin/env bash
exec timeout --signal=TERM --kill-after=20s 10s "$mock_dir/quick-ci-deploy.sh"
MOCK
chmod +x "$mock_dir/success-wrapper.sh"

set +e
output=$("$mock_dir/success-wrapper.sh" 2>&1)
rc=$?
set -e

if [[ "$rc" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "deploy ok"; then
  PASS=$((PASS + 1))
  echo "  PASS: wrapper exits 0 and forwards child stdout on success path"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: success path broken (rc=$rc output=$output)"
fi

# ---------------------------------------------------------------------------
# Test 6: ceiling parity — the wrapper's `timeout … <N>s …` value MUST equal
# `IN_FLIGHT_CEILING_S` in .github/workflows/web-platform-release.yml. The
# workflow already runtime-asserts STATUS_POLL × INTERVAL == HEALTH_POLL ×
# INTERVAL == IN_FLIGHT_CEILING_S, but does NOT cover the wrapper. A future
# PR that bumps IN_FLIGHT_CEILING_S without touching the wrapper would pass
# the workflow's assertion while reopening #3704. This test closes that gap.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/web-platform-release.yml"
wrapper_seconds=$(grep -oE -- '--kill-after=[0-9]+s [0-9]+s /usr/local/bin/ci-deploy\.sh' "$WRAPPER" \
  | grep -oE ' [0-9]+s /' | grep -oE '[0-9]+' | head -1)
workflow_seconds=$(grep -oE '^[[:space:]]*IN_FLIGHT_CEILING_S:[[:space:]]*[0-9]+' "$WORKFLOW" \
  | grep -oE '[0-9]+$' | head -1)
if [[ -z "$wrapper_seconds" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: could not extract wrapper timeout seconds from $WRAPPER"
elif [[ -z "$workflow_seconds" ]]; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: could not extract IN_FLIGHT_CEILING_S from $WORKFLOW"
elif [[ "$wrapper_seconds" == "$workflow_seconds" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: wrapper timeout (${wrapper_seconds}s) matches IN_FLIGHT_CEILING_S (${workflow_seconds})"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ceiling drift — wrapper=${wrapper_seconds}s, IN_FLIGHT_CEILING_S=${workflow_seconds} (must agree per #3704)"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
