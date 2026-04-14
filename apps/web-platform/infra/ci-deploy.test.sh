#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy.sh forced command script.
# Tests validation logic by sourcing the script with mock docker/curl/logger/chown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
TOTAL=0

# Shared mock scaffold: creates all common mock binaries in $MOCK_DIR.
# Each run_deploy* variant calls this first, then overlays specialized mocks.
create_base_mocks() {
  local mock_dir="$1"

  # Mock logger (accept any args silently)
  cat > "$mock_dir/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$mock_dir/logger"

  # Mock docker (accept any args, print fake container ID for 'run')
  cat > "$mock_dir/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then
  echo "abc123"
fi
exit 0
MOCK
  chmod +x "$mock_dir/docker"

  # Mock curl (simulate healthy endpoint)
  cat > "$mock_dir/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then
    echo "200"
    exit 0
  fi
done
echo "OK"
exit 0
MOCK
  chmod +x "$mock_dir/curl"

  # Mock sudo (just runs the command without privilege escalation)
  cat > "$mock_dir/sudo" << 'MOCK'
#!/bin/bash
exec "$@"
MOCK
  chmod +x "$mock_dir/sudo"

  # Mock chown
  cat > "$mock_dir/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$mock_dir/chown"

  # Mock seq (for health check loops -- return "1" so the loop runs once)
  cat > "$mock_dir/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
  chmod +x "$mock_dir/seq"

  # Mock flock (always succeeds unless MOCK_FLOCK_CONTENDED=1)
  cat > "$mock_dir/flock" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_FLOCK_CONTENDED:-}" == "1" ]]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "$mock_dir/flock"

  # Mock df (reports plenty of disk space; MOCK_DF_LOW=1 simulates low disk)
  cat > "$mock_dir/df" << 'MOCK'
#!/bin/bash
echo "Avail"
if [[ "${MOCK_DF_LOW:-}" == "1" ]]; then
  echo "1000000"
else
  echo "20000000"
fi
MOCK
  chmod +x "$mock_dir/df"

  # Mock doppler (simulate successful secrets download)
  cat > "$mock_dir/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
exit 0
MOCK
  chmod +x "$mock_dir/doppler"
}

run_deploy() {
  # Run ci-deploy.sh in a subshell with SSH_ORIGINAL_COMMAND set.
  # Mock out docker, curl, logger, chown, flock so the script only tests validation logic.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # CI_DEPLOY_STATE defaults to a per-run temp path unless the caller already set one.
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    create_base_mocks "$MOCK_DIR"

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

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    create_base_mocks "$MOCK_DIR"

    # Override: docker mock with trace markers and configurable failures
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

    # Override: curl mock with port-based routing for canary health checks
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
    create_base_mocks "$MOCK_DIR"

    # Override: flock simulates lock contention
    cat > "$MOCK_DIR/flock" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/flock"

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
    create_base_mocks "$MOCK_DIR"

    # Override: doppler mock with MOCK_DOPPLER_MISSING/MOCK_DOPPLER_FAIL support
    if [[ "${MOCK_DOPPLER_MISSING:-}" == "1" ]]; then
      rm -f "$MOCK_DIR/doppler"
    elif [[ "${MOCK_DOPPLER_FAIL:-}" == "1" ]]; then
      cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
echo "Doppler Error: mkdir /home/deploy/.doppler: read-only file system" >&2
exit 1
MOCK
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
echo "--- AppArmor profile on docker run ---"

assert_apparmor_profile() {
  # Verify that docker run commands include --security-opt apparmor=soleur-bwrap
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    create_base_mocks "$MOCK_DIR"

    # Override: docker mock that logs full args for 'run' commands
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

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check that all DOCKER_RUN_ARGS lines contain apparmor=soleur-bwrap
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
    if ! printf '%s\n' "$line" | grep -qF "apparmor=soleur-bwrap"; then
      all_have_apparmor=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_apparmor" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing --security-opt apparmor=soleur-bwrap)"
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5
  fi
}

assert_apparmor_profile "web-platform: docker run has apparmor=soleur-bwrap" \
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
    create_base_mocks "$MOCK_DIR"

    # Override: docker mock that traces exec calls
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
    create_base_mocks "$MOCK_DIR"

    # Override: docker mock where bwrap exec fails
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
echo "--- Env file cleanup on all exit paths ---"

assert_env_file_cleanup() {
  local description="$1"
  local extra_env="${2:-}"

  TOTAL=$((TOTAL + 1))

  # Tracker dir survives both the deploy process and test subshell
  local tracker_dir
  tracker_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export ENV_FILE_TRACKER="$tracker_dir/env_file_path"
    create_base_mocks "$MOCK_DIR"

    # Override: docker mock with configurable canary failure
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "run" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == *"-canary" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_CANARY:-}" == "1" ]]; then
      exit 1
    fi
  done
  echo "abc123"
fi
if [[ "${1:-}" == "exec" ]]; then
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    # Mock mktemp: create a real temp file but record its path to the tracker
    cat > "$MOCK_DIR/mktemp" << 'MOCK'
#!/bin/bash
tmpfile=$(/usr/bin/mktemp "$@")
if [[ -n "${ENV_FILE_TRACKER:-}" ]]; then
  echo "$tmpfile" > "$ENV_FILE_TRACKER"
fi
echo "$tmpfile"
MOCK
    chmod +x "$MOCK_DIR/mktemp"

    eval "$extra_env"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check: does the env file still exist?
  if [[ -f "$tracker_dir/env_file_path" ]]; then
    local env_file_path
    env_file_path=$(cat "$tracker_dir/env_file_path")
    if [[ ! -f "$env_file_path" ]]; then
      PASS=$((PASS + 1))
      echo "  PASS: $description"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: $description (env file still exists: $env_file_path)"
      rm -f "$env_file_path"  # clean up leaked file
    fi
  else
    # No env file was ever created (e.g., failure before resolve_env_file)
    PASS=$((PASS + 1))
    echo "  PASS: $description (no env file created)"
  fi

  rm -rf "$tracker_dir"
}

assert_env_file_cleanup "canary crash cleans up env file" \
  "export MOCK_DOCKER_RUN_FAIL_CANARY=1"

assert_env_file_cleanup "successful deploy cleans up env file" ""

echo ""
echo "--- Deploy state file (#2185 observability) ---"

# assert_state_contains: runs deploy, then parses the state file written by ci-deploy.sh.
# Validates .exit_code and .reason via jq (falls back to grep if jq unavailable).
# Signature: assert_state_contains <description> <expected_reason> <expected_exit_code> [<cmd>] [<extra_env>]
assert_state_contains() {
  local description="$1"
  local expected_reason="$2"
  local expected_exit_code="$3"
  local cmd="${4:-deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0}"
  local extra_env="${5:-}"

  TOTAL=$((TOTAL + 1))

  # State file lives outside the per-run MOCK_DIR so we can read it after the subshell cleans up.
  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    eval "$extra_env"
    export CI_DEPLOY_STATE="$state_file"
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    actual_reason=$(jq -r '.reason // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
    actual_exit_code=$(jq -r '.exit_code // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
  else
    # Fallback: crude grep-based parse (only used if jq missing from test environment).
    actual_reason=$(grep -oE '"reason":"[^"]*"' "$state_file" | sed 's/.*:"\(.*\)"/\1/')
    actual_exit_code=$(grep -oE '"exit_code":-?[0-9]+' "$state_file" | sed 's/.*://')
  fi

  if [[ "$actual_reason" == "$expected_reason" ]] && [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description (reason=$actual_reason exit_code=$actual_exit_code script_exit=$actual_exit)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected: reason=$expected_reason exit_code=$expected_exit_code"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
    echo "        output:   $output"
  fi

  rm -rf "$state_dir"
}

# Happy path -> reason="ok", exit_code=0
assert_state_contains "happy path writes reason=ok" "ok" "0"

# Low disk -> reason="insufficient_disk_space"
assert_state_contains "low disk writes reason=insufficient_disk_space" \
  "insufficient_disk_space" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DF_LOW=1"

# Flock contention -> reason="lock_contention"
assert_state_contains "flock contention writes reason=lock_contention" \
  "lock_contention" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_FLOCK_CONTENDED=1"

# Docker pull failure -> unhandled exit path via set -e (we do not explicitly instrument this).
# We expect exit_code=1; reason may be "unhandled" (from the EXIT trap) unless a handler is added.
# Accept either to make the test robust if we later add a pull-specific handler.
assert_state_contains_either() {
  local description="$1"
  local expected_reason_a="$2"
  local expected_reason_b="$3"
  local expected_exit_code="$4"
  local cmd="${5:-deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0}"
  local extra_env="${6:-}"

  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    eval "$extra_env"
    export CI_DEPLOY_STATE="$state_file"
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    actual_reason=$(jq -r '.reason // ""' "$state_file" 2>/dev/null || echo "")
    actual_exit_code=$(jq -r '.exit_code // ""' "$state_file" 2>/dev/null || echo "")
  else
    actual_reason=$(grep -oE '"reason":"[^"]*"' "$state_file" | sed 's/.*:"\(.*\)"/\1/')
    actual_exit_code=$(grep -oE '"exit_code":-?[0-9]+' "$state_file" | sed 's/.*://')
  fi

  if { [[ "$actual_reason" == "$expected_reason_a" ]] || [[ "$actual_reason" == "$expected_reason_b" ]]; } && \
     [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description (reason=$actual_reason exit_code=$actual_exit_code)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected: reason=$expected_reason_a|$expected_reason_b exit_code=$expected_exit_code"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
  fi

  rm -rf "$state_dir"
}

# Docker pull failure -> exit_code=1, reason=unhandled (implicit via EXIT trap, no explicit handler)
assert_state_contains_either "docker pull fail writes exit_code=1" \
  "unhandled" "pull_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_PULL_FAIL=1"

# Canary run crash (docker run for canary fails) -> exit via set -e, reason=unhandled
# (no explicit handler around `docker run ... canary` because it's controlled by set -e).
assert_state_contains_either "canary container run crash writes exit_code=1" \
  "unhandled" "canary_sandbox_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_RUN_FAIL_CANARY=1"

# Canary health check failure -> reason=canary_failed
assert_state_contains "canary health failure writes reason=canary_failed" \
  "canary_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_CANARY_FAIL=1"

# Issue #2199 fix 1: initial "running" write must happen AFTER command parsing,
# so tag/component are populated (not empty strings).
# We snapshot the state file mid-deploy by making `df` (called after the initial
# "running" write) copy the live state file to a side location before returning.
assert_initial_running_has_tag() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"
  local snapshot="$state_dir/running.snapshot"

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CI_DEPLOY_STATE="$state_file"
    export RUNNING_SNAPSHOT="$snapshot"
    create_base_mocks "$MOCK_DIR"

    # df runs immediately after the initial "running" write_state; snapshot state here.
    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
if [[ -n "${RUNNING_SNAPSHOT:-}" ]] && [[ -f "${CI_DEPLOY_STATE:-}" ]]; then
  cp "$CI_DEPLOY_STATE" "$RUNNING_SNAPSHOT"
fi
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ ! -f "$snapshot" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: initial running state snapshot was not captured"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  local snap_reason snap_exit snap_tag snap_component
  if command -v jq >/dev/null 2>&1; then
    snap_reason=$(jq -r '.reason // ""' "$snapshot" 2>/dev/null)
    snap_exit=$(jq -r '.exit_code // ""' "$snapshot" 2>/dev/null)
    snap_tag=$(jq -r '.tag // ""' "$snapshot" 2>/dev/null)
    snap_component=$(jq -r '.component // ""' "$snapshot" 2>/dev/null)
  else
    snap_reason=$(grep -oE '"reason":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
    snap_exit=$(grep -oE '"exit_code":-?[0-9]+' "$snapshot" | sed 's/.*://')
    snap_tag=$(grep -oE '"tag":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
    snap_component=$(grep -oE '"component":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
  fi

  if [[ "$snap_reason" == "running" ]] && [[ "$snap_exit" == "-1" ]] && \
     [[ "$snap_tag" == "v1.0.0" ]] && [[ "$snap_component" == "web-platform" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: initial running state has populated tag/component (tag=$snap_tag component=$snap_component)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: initial running state has populated tag/component"
    echo "        expected: reason=running exit_code=-1 tag=v1.0.0 component=web-platform"
    echo "        actual:   reason=$snap_reason exit_code=$snap_exit tag=$snap_tag component=$snap_component"
    echo "        snapshot: $(cat "$snapshot")"
  fi

  rm -rf "$state_dir"
}

assert_initial_running_has_tag

# Issue #2199 fix 3: a stale ${STATE_FILE}.final sentinel from a prior SIGKILLed
# run must not suppress the current run's failure reason. We pre-create the
# sentinel, trigger a known failure (low disk), and verify the explicit reason
# is still written (not silently dropped by the EXIT trap's "unhandled" guard).
assert_stale_sentinel_cleared() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"
  # Pre-create the stale sentinel as if a prior run was SIGKILLed.
  touch "${state_file}.final"

  local output actual_exit
  output=$(
    export CI_DEPLOY_STATE="$state_file"
    export MOCK_DF_LOW=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: stale sentinel test (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    actual_reason=$(jq -r '.reason // ""' "$state_file" 2>/dev/null)
    actual_exit_code=$(jq -r '.exit_code // ""' "$state_file" 2>/dev/null)
  else
    actual_reason=$(grep -oE '"reason":"[^"]*"' "$state_file" | sed 's/.*:"\(.*\)"/\1/')
    actual_exit_code=$(grep -oE '"exit_code":-?[0-9]+' "$state_file" | sed 's/.*://')
  fi

  if [[ "$actual_reason" == "insufficient_disk_space" ]] && [[ "$actual_exit_code" == "1" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: stale sentinel cleared; new run's explicit reason is preserved"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: stale sentinel cleared; new run's explicit reason is preserved"
    echo "        expected: reason=insufficient_disk_space exit_code=1"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
  fi

  rm -rf "$state_dir"
}

assert_stale_sentinel_cleared

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
