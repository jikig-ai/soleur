#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy.sh forced command script.
# Tests validation logic by sourcing the script with mock docker/curl/logger/chown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
TOTAL=0

run_deploy() {
  # Run ci-deploy.sh in a subshell with SSH_ORIGINAL_COMMAND set.
  # Mock out docker, curl, logger, chown, flock so the script only tests validation logic.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    # Create temp bin dir with mocks
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT

    # Use temp lock file for flock
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    # Mock logger (accept any args silently)
    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Mock docker (accept any args silently)
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
# For 'docker run -d' print a fake container ID
if [[ "${1:-}" == "run" ]]; then
  echo "abc123"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    # Mock curl (simulate healthy endpoint)
    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
# Handle -w '%{http_code}' for telegram-bridge health check
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then
    echo "200"
    exit 0
  fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    # Mock sudo (just runs the command without privilege escalation)
    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    # Mock chown
    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    # Mock seq (for health check loops)
    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
# Just return "1" so the loop runs once
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    # Mock flock (always succeeds -- lock not contended)
    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    # Mock df (reports plenty of disk space; MOCK_DF_LOW=1 simulates low disk)
    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
if [[ "${MOCK_DF_LOW:-}" == "1" ]]; then
  echo "1000000"
else
  echo "20000000"
fi
MOCK
    chmod +x "$MOCK_DIR/df"

    # Mock doppler (simulate successful secrets download)
    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

assert_exit() {
  local description="$1"
  local expected_exit="$2"
  local cmd="${3:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit, got $actual_exit)"
    echo "        output: $output"
  fi
}

assert_exit_contains() {
  local description="$1"
  local expected_exit="$2"
  local expected_text="$3"
  local cmd="${4:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]] && printf '%s\n' "$output" | grep -qF "$expected_text"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit with '$expected_text')"
    echo "        actual exit: $actual_exit"
    echo "        output: $output"
  fi
}

run_deploy_traced() {
  # Like run_deploy but docker mock prints DOCKER_TRACE:<subcommand> markers to stdout.
  # Supports MOCK_DOCKER_PULL_FAIL, MOCK_DOCKER_RUN_FAIL_CANARY,
  # MOCK_DOCKER_RUN_FAIL_PROD, and MOCK_CURL_CANARY_FAIL env vars.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT

    # Use temp lock file for flock
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Docker mock with trace markers and configurable failures
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
echo "DOCKER_TRACE:$1"
# Configurable pull failure
if [[ "${1:-}" == "pull" ]] && [[ "${MOCK_DOCKER_PULL_FAIL:-}" == "1" ]]; then
  exit 1
fi
# Configurable canary run failure
if [[ "${1:-}" == "run" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == *"-canary" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_CANARY:-}" == "1" ]]; then
      exit 1
    fi
  done
  # Configurable production run failure (after canary)
  for arg in "$@"; do
    if [[ "$arg" == "soleur-web-platform" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_PROD:-}" == "1" ]]; then
      exit 1
    fi
  done
  echo "abc123"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    # Curl mock with port-based routing for canary health checks
    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then echo "200"; exit 0; fi
  # Canary port failure
  if [[ "$arg" == *"localhost:3001"* ]] && [[ "${MOCK_CURL_CANARY_FAIL:-}" == "1" ]]; then
    exit 1
  fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    # Mock df (reports plenty of disk space; MOCK_DF_LOW=1 simulates low disk)
    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
if [[ "${MOCK_DF_LOW:-}" == "1" ]]; then
  echo "1000000"
else
  echo "20000000"
fi
MOCK
    chmod +x "$MOCK_DIR/df"

    # Mock doppler (simulate successful secrets download)
    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

echo "=== ci-deploy.sh tests ==="
echo ""

echo "--- Happy path ---"
assert_exit "web-platform deploy succeeds" 0 \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

assert_exit "telegram-bridge deploy succeeds" 0 \
  "deploy telegram-bridge ghcr.io/jikig-ai/soleur-telegram-bridge v2.3.1"

echo ""
echo "--- Empty/missing command ---"
assert_exit_contains "empty command rejected" 1 "no command provided" ""

echo ""
echo "--- Field count validation ---"
assert_exit_contains "single word rejected" 1 "expected 4 fields, got 1" "whoami"

assert_exit_contains "two fields rejected" 1 "expected 4 fields, got 2" "deploy web-platform"

assert_exit_contains "three fields rejected" 1 "expected 4 fields, got 3" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform"

assert_exit_contains "five fields rejected (extra arg)" 1 "expected 4 fields, got 5" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0 extra-arg"

echo ""
echo "--- Action validation ---"
assert_exit_contains "unknown action rejected" 1 "unknown action" \
  "exec web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Component validation ---"
assert_exit_contains "unknown component rejected" 1 "unknown component" \
  "deploy unknown-svc ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Image allowlist (exact match, not prefix) ---"
assert_exit_contains "suffix injection rejected" 1 "invalid image" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-attacker-repo v1.0.0"

assert_exit_contains "wrong image for component rejected" 1 "invalid image" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-telegram-bridge v1.0.0"

assert_exit_contains "arbitrary image rejected" 1 "invalid image" \
  "deploy web-platform evil-image:latest v1.0.0"

echo ""
echo "--- Tag format validation ---"
assert_exit_contains "latest tag rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"

assert_exit_contains "tag without v prefix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform 1.0.0"

assert_exit_contains "tag with extra suffix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0-rc1"

echo ""
echo "--- Adversarial input (shell injection) ---"
assert_exit_contains "command substitution in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform $(whoami)'

assert_exit_contains "semicolon injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0;id'

assert_exit_contains "backtick injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform `whoami`'

assert_exit_contains "newline injection rejected" 1 "expected 4 fields" \
  $'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0\nwhoami'

assert_exit_contains "pipe injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0|id'

echo ""
echo "--- Docker prune before pull ---"

assert_prune_before_pull() {
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy_traced "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  # Check that DOCKER_TRACE:image appears before DOCKER_TRACE:pull in output
  local prune_line pull_line
  prune_line=$(printf '%s\n' "$output" | { grep -n "DOCKER_TRACE:image" || true; } | head -1 | cut -d: -f1)
  pull_line=$(printf '%s\n' "$output" | { grep -n "DOCKER_TRACE:pull" || true; } | head -1 | cut -d: -f1)

  if [[ "$actual_exit" -eq 0 ]] && [[ -n "$prune_line" ]] && [[ -n "$pull_line" ]] && [[ "$prune_line" -lt "$pull_line" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (prune_line=$prune_line pull_line=$pull_line exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_prune_before_pull "web-platform: prune runs before pull" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

assert_prune_before_pull "telegram-bridge: prune runs before pull" \
  "deploy telegram-bridge ghcr.io/jikig-ai/soleur-telegram-bridge v2.3.1"

echo ""
echo "--- Disk space pre-flight check ---"

assert_disk_space_rejection() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_DF_LOW=1; run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "insufficient disk space"; then
    PASS=$((PASS + 1))
    echo "  PASS: low disk space rejects deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: low disk space rejects deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_disk_space_rejection

echo ""
echo "--- Canary rollback (web-platform) ---"

assert_canary_trace_order() {
  # Verify canary deploy produces correct Docker trace ordering.
  local description="$1"
  local cmd="$2"
  local expected_order="$3"  # pipe-separated trace markers, e.g., "image|pull|stop|rm|run|stop|rm|run|stop|rm"
  local extra_env="${4:-}"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    eval "$extra_env"
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Extract ordered DOCKER_TRACE lines
  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  if [[ "$traces" == "$expected_order" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected traces: $expected_order"
    echo "        actual traces:   $traces"
    echo "        exit: $actual_exit"
  fi
}

# Canary success: prune → pull → stop(stale canary) → rm(stale canary) → run(canary) →
#   bwrap sandbox check (docker exec) → stop(old) → rm(old) → run(prod) → stop(canary) → rm(canary)
assert_canary_trace_order "canary success: correct docker trace order" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "image|pull|stop|rm|run|exec|stop|rm|run|stop|rm"

# Canary failure / rollback: prune → pull → stop(stale) → rm(stale) → run(canary) →
#   logs(canary) → stop(canary) → rm(canary)
# Old container is NOT stopped or removed.
assert_canary_rollback() {
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_CURL_CANARY_FAIL=1
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Expected: system|pull|stop|rm|run|stop|rm
  # (prune, pull, stale canary cleanup [stop, rm], canary run, canary stop, canary rm)
  # Note: docker logs is piped to logger so its trace marker is consumed.
  # Crucially: only 2 stop/rm pairs (stale cleanup + canary cleanup), NOT 3 (no old production stop/rm)
  local expected="image|pull|stop|rm|run|stop|rm"

  if [[ "$actual_exit" -eq 1 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected traces: $expected (exit 1)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_canary_rollback "canary failure: rollback preserves old container" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Docker pull failure: no canary started
assert_pull_failure() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_PULL_FAIL=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Should only have prune and pull (which fails), then script exits
  local expected="image|pull"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: docker pull failure: no canary started"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: docker pull failure: no canary started"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_pull_failure

# Canary crash on start: docker run fails for canary
assert_canary_crash() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_RUN_FAIL_CANARY=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # prune, pull, stale cleanup (stop, rm), canary run (fails) → script exits via set -e
  local expected="image|pull|stop|rm|run"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: canary crash on start: no health check, old untouched"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: canary crash on start: no health check, old untouched"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_canary_crash

# Production start failure after canary success
assert_prod_start_failure() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_RUN_FAIL_PROD=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # prune, pull, stale cleanup (stop, rm), canary run (ok), canary health ok,
  # bwrap sandbox check, old stop, old rm, prod run (fails), canary stop, canary rm
  local expected="image|pull|stop|rm|run|exec|stop|rm|run|stop|rm"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: production start failure after canary success"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: production start failure after canary success"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_prod_start_failure

# Flock rejects concurrent deploy
assert_flock_rejection() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    # Mock flock to simulate lock contention
    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/flock"

    # Standard mocks for validation to pass
    for cmd in logger docker curl sudo chown seq; do
      cat > "$MOCK_DIR/$cmd" << 'MOCK'
#!/bin/bash
exit 0
MOCK
      chmod +x "$MOCK_DIR/$cmd"
    done

    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "another deploy in progress"; then
    PASS=$((PASS + 1))
    echo "  PASS: flock rejects concurrent deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: flock rejects concurrent deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_flock_rejection

echo ""
echo "--- Doppler hardening (resolve_env_file) ---"

# Helper: run deploy with Doppler-specific environment controls.
# MOCK_DOPPLER_MISSING=1  -> doppler binary not in PATH
# MOCK_DOPPLER_TOKEN=""   -> DOPPLER_TOKEN unset
# MOCK_DOPPLER_FAIL=1     -> doppler secrets download fails
run_deploy_doppler() {
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then echo "200"; exit 0; fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    # Doppler mock: present unless MOCK_DOPPLER_MISSING=1
    if [[ "${MOCK_DOPPLER_MISSING:-}" != "1" ]]; then
      if [[ "${MOCK_DOPPLER_FAIL:-}" == "1" ]]; then
        cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
echo "Doppler Error: mkdir /home/deploy/.doppler: read-only file system" >&2
exit 1
MOCK
      else
        cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
# Simulate successful secrets download
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
echo "doppler mock"
exit 0
MOCK
      fi
      chmod +x "$MOCK_DIR/doppler"
    fi

    # Set DOPPLER_TOKEN unless explicitly empty
    if [[ "${MOCK_DOPPLER_TOKEN_UNSET:-}" != "1" ]]; then
      export DOPPLER_TOKEN="dp.st.prd.mock-token"
    else
      unset DOPPLER_TOKEN
    fi

    # Restrict PATH to mock dir + standard system dirs (excludes ~/.local/bin
    # where real doppler lives, so MOCK_DOPPLER_MISSING=1 actually works)
    export PATH="$MOCK_DIR:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

# Test: Doppler CLI not installed -> exit with error
assert_doppler_missing() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_MISSING=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "Doppler CLI not installed"; then
    PASS=$((PASS + 1))
    echo "  PASS: missing doppler CLI exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: missing doppler CLI exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_missing

# Test: DOPPLER_TOKEN not set -> exit with error
assert_doppler_token_missing() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_TOKEN_UNSET=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "DOPPLER_TOKEN environment variable not set"; then
    PASS=$((PASS + 1))
    echo "  PASS: missing DOPPLER_TOKEN exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: missing DOPPLER_TOKEN exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_token_missing

# Test: Doppler download fails -> exit with error (no .env fallback)
assert_doppler_download_fails() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_FAIL=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "Failed to download secrets from Doppler:"; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler download failure exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler download failure exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_download_fails

# Test: Doppler download fails -> error message includes actual Doppler error
assert_doppler_error_logged() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_FAIL=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "read-only file system"; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler error message included in output"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler error message included in output (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_error_logged

# Test: No fallback to /mnt/data/.env in any failure case
assert_no_env_fallback() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  # With Doppler missing, the old code would fall back to /mnt/data/.env
  # The new code must never reference /mnt/data/.env
  output=$(
    export MOCK_DOPPLER_MISSING=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if ! printf '%s\n' "$output" | grep -qF "/mnt/data/.env"; then
    PASS=$((PASS + 1))
    echo "  PASS: no fallback to /mnt/data/.env"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: no fallback to /mnt/data/.env (output references .env)"
    echo "        output: $output"
  fi
}

assert_no_env_fallback

# Test: Doppler works -> deploy succeeds
assert_doppler_success() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler success deploys successfully"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler success deploys successfully (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_success

echo ""
echo "--- AppArmor unconfined on docker run ---"

assert_apparmor_unconfined() {
  # Verify that docker run commands include --security-opt apparmor=unconfined
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Docker mock that logs full args for 'run' commands
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then
  echo "DOCKER_RUN_ARGS:$*"
  echo "abc123"
fi
if [[ "${1:-}" == "exec" ]]; then
  echo "DOCKER_EXEC_ARGS:$*"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then echo "200"; exit 0; fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then echo "KEY=value"; exit 0; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check that all DOCKER_RUN_ARGS lines contain apparmor=unconfined
  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_apparmor=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF "apparmor=unconfined"; then
      all_have_apparmor=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_apparmor" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing --security-opt apparmor=unconfined)"
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5
  fi
}

assert_apparmor_unconfined "web-platform: docker run has apparmor=unconfined" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Bwrap canary sandbox check ---"

assert_bwrap_canary_check() {
  # Verify that a bwrap check runs against the canary container after health check.
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Docker mock that traces exec calls
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
if [[ "${1:-}" == "exec" ]]; then
  echo "DOCKER_EXEC:$*"
  # Check if this is a bwrap check
  for arg in "$@"; do
    if [[ "$arg" == *"bwrap"* ]]; then
      echo "BWRAP_CANARY_CHECK"
      exit 0
    fi
  done
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then echo "200"; exit 0; fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then echo "KEY=value"; exit 0; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "BWRAP_CANARY_CHECK"; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap canary sandbox check runs during deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap canary sandbox check runs during deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_bwrap_canary_check

assert_bwrap_canary_failure_rollback() {
  # Verify that bwrap check failure triggers canary rollback.
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"

    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Docker mock: bwrap exec fails
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
if [[ "${1:-}" == "exec" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == *"bwrap"* ]]; then
      echo "bwrap: No permissions to create new namespace" >&2
      exit 1
    fi
  done
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then echo "200"; exit 0; fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    cat > "$MOCK_DIR/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then echo "KEY=value"; exit 0; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -ne 0 ]] && printf '%s\n' "$output" | grep -qiF "sandbox"; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap canary failure triggers rollback"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap canary failure triggers rollback (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_bwrap_canary_failure_rollback

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
