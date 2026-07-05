#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy.sh forced command script.
# Tests validation logic by sourcing the script with mock docker/curl/logger/chown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
TOTAL=0

# Hardened PATH for all test subshells.
# Excludes ~/.local/bin (where real doppler lives) so missing mocks fail loudly
# rather than falling through to real commands.
readonly TEST_PATH_BASE="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Mock factories ---------------------------------------------------------
# All specialized mocks are driven by env vars. Tests set MOCK_DOCKER_MODE /
# MOCK_CURL_MODE before invoking a runner; the runner calls create_base_mocks
# which emits a single unified mock binary per command.
#
# MOCK_DOCKER_MODE values:
#   default        - echo abc123 on run, exit 0 otherwise (minimal)
#   trace          - emit DOCKER_TRACE:<subcmd> for each call; honor
#                    MOCK_DOCKER_PULL_FAIL / MOCK_DOCKER_RUN_FAIL_CANARY /
#                    MOCK_DOCKER_RUN_FAIL_PROD
#   apparmor-trace - emit DOCKER_RUN_ARGS:<args> and DOCKER_EXEC_ARGS:<args>
#   bwrap-trace    - emit DOCKER_EXEC:<args> and BWRAP_CANARY_CHECK marker on
#                    a successful bwrap exec
#   bwrap-fail     - like bwrap-trace but `docker exec ... bwrap ...` fails
#
# MOCK_CURL_MODE values:
#   default        - healthy endpoint (200 / OK); honor MOCK_CURL_CANARY_FAIL
#                    to fail the localhost:3001 canary probe

create_mock_logger() {
  cat > "$1/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$1/logger"
}

create_mock_sudo() {
  cat > "$1/sudo" << 'MOCK'
#!/bin/bash
# Skip sudo flags (--preserve-env=..., -E, etc.)
while [[ "${1:-}" == -* ]]; do shift; done
cmd="$1"; shift
# Resolve absolute paths via PATH so mocks shadow system binaries.
if [[ "$cmd" == /* ]]; then
  base=$(basename "$cmd")
  resolved=$(type -P "$base" 2>/dev/null || true)
  if [[ -n "$resolved" ]]; then
    exec "$resolved" "$@"
  fi
fi
exec "$cmd" "$@"
MOCK
  chmod +x "$1/sudo"
}

create_mock_chown() {
  cat > "$1/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$1/chown"
}

create_mock_seq() {
  cat > "$1/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
  chmod +x "$1/seq"
}

create_mock_flock() {
  cat > "$1/flock" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_FLOCK_CONTENDED:-}" == "1" ]]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/flock"
}

create_mock_systemctl() {
  cat > "$1/systemctl" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_SYSTEMCTL_FAIL:-}" == "1" ]]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/systemctl"
}

create_mock_df() {
  cat > "$1/df" << 'MOCK'
#!/bin/bash
echo "Avail"
if [[ "${MOCK_DF_LOW:-}" == "1" ]]; then
  echo "1000000"
else
  echo "20000000"
fi
MOCK
  chmod +x "$1/df"
}

create_mock_doppler() {
  cat > "$1/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" && "${2:-}" == "get" ]]; then
  # #6005 ghcr_prelude_and_login: `secrets get <NAME> --plain` → bare per-name value.
  # A non-empty distinguishable value so the prelude exports (SENTRY_*, GHCR_*) are
  # observably set. MOCK_DOPPLER_GET_EMPTY simulates the pre-provisioning state
  # (credential not yet in Doppler) → empty value, prelude skips docker login.
  if [[ "${MOCK_DOPPLER_GET_EMPTY:-}" == "1" ]]; then exit 0; fi
  echo "mock-${3:-VALUE}"
  exit 0
fi
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
exit 0
MOCK
  chmod +x "$1/doppler"
}

# Unified docker mock. Behavior selected at runtime via MOCK_DOCKER_MODE env var.
# Writing one mock (not five) eliminates drift across test scenarios.
create_docker_mock() {
  cat > "$1/docker" << 'MOCK'
#!/bin/bash
mode="${MOCK_DOCKER_MODE:-default}"

# #5669 cron-drain in-flight probe: `docker exec soleur-web-platform pgrep -f
# claude`. Handled BEFORE the mode case so every swap-reaching test (trace AND
# default) gets a bounded drain — without this the generic `exec`→exit-0 path
# makes cron_in_flight loop until CRON_DRAIN_TIMEOUT. Default: NO claude in
# flight (exit 1) → zero-wait drain, no hang. Armed via MOCK_CRON_INFLIGHT_FILE
# (a countdown of remaining in-flight polls; decremented each call). The `bwrap`
# canary sandbox `docker exec` has no `pgrep` arg so it falls through untouched.
if [[ "${1:-}" == "exec" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == "pgrep" ]]; then
      _f="${MOCK_CRON_INFLIGHT_FILE:-}"
      if [[ -n "$_f" && -f "$_f" ]]; then
        _n=$(cat "$_f" 2>/dev/null || echo 0)
        if [[ "$_n" =~ ^[0-9]+$ ]] && (( _n > 0 )); then
          echo $(( _n - 1 )) > "$_f"
          exit 0   # claude in flight
        fi
      fi
      exit 1       # no claude in flight (default)
    fi
  done
fi

# #5933 Item 4 image-verify handlers, BEFORE the mode case so they work in every
# mode and the app-run failure arming (canary/prod) cannot misfire on them.
#
# cosign verify runs as `docker run --rm <cosign-image> verify --offline ...` —
# detect the `verify` arg. Default: verify PASSES (exit 0). MOCK_COSIGN_VERIFY_FAIL
# simulates a signature failure (WARN mode must still NOT block the deploy).
if [[ "${1:-}" == "run" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == "verify" ]]; then
      # #6005: capture the full cosign `docker run` argv + whether SENTRY_* were
      # already in the script env AT VERIFY TIME (proves the Phase-3 early Doppler
      # fetch ran before verify, so the WARN telemetry is not dark). ci-deploy.sh
      # discards the cosign container stdout (>/dev/null), so record to a file.
      if [[ -n "${MOCK_COSIGN_ARGS_FILE:-}" ]]; then
        printf 'COSIGN_VERIFY_ARGS:%s\n' "$*" >> "$MOCK_COSIGN_ARGS_FILE"
        printf 'SENTRY_AT_VERIFY:%s\n' "${SENTRY_INGEST_DOMAIN:-UNSET}" >> "$MOCK_COSIGN_ARGS_FILE"
      fi
      if [[ "${MOCK_COSIGN_VERIFY_FAIL:-}" == "1" ]]; then
        echo "Error: no matching signatures found" >&2
        exit 1
      fi
      exit 0
    fi
  done
fi
# `docker inspect --format '{{index .RepoDigests 0}}' <img>` resolves the pulled
# tag to its immutable digest. Return a synthetic digest ref unless the test arms
# MOCK_INSPECT_NO_DIGEST (exercises the inspect_failed WARN fallback). Scoped to
# the RepoDigests format so the inngest-case `-f '{{range .Config.Env}}'` inspect
# is untouched.
if [[ "${1:-}" == "inspect" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == *"RepoDigests"* ]]; then
      if [[ "${MOCK_INSPECT_NO_DIGEST:-}" == "1" ]]; then
        echo ""
      else
        echo "ghcr.io/jikig-ai/soleur-web-platform@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      fi
      exit 0
    fi
  done
fi

case "$mode" in
  trace)
    # `ps` is read by the ADR-027 pre-run assertion; the script greps stdout
    # for the container name, so the DOCKER_TRACE marker must not appear on
    # stdout for ps calls. Route the trace to stderr and emit name only when
    # explicitly armed.
    if [[ "${1:-}" == "ps" ]]; then
      echo "DOCKER_TRACE:ps" >&2
      if [[ "${MOCK_DOCKER_PS_PROD_RUNNING:-}" == "1" ]]; then
        echo "soleur-web-platform"
      fi
      exit 0
    fi
    echo "DOCKER_TRACE:$1"
    if [[ "${1:-}" == "pull" ]] && [[ "${MOCK_DOCKER_PULL_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    if [[ "${1:-}" == "run" ]]; then
      for arg in "$@"; do
        if [[ "$arg" == *"-canary" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_CANARY:-}" == "1" ]]; then
          exit 1
        fi
      done
      for arg in "$@"; do
        if [[ "$arg" == "soleur-web-platform" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_PROD:-}" == "1" ]]; then
          exit 1
        fi
      done
      echo "abc123"
    fi
    exit 0
    ;;
  apparmor-trace)
    if [[ "${1:-}" == "run" ]]; then
      echo "DOCKER_RUN_ARGS:$*"
      echo "abc123"
    fi
    if [[ "${1:-}" == "exec" ]]; then
      echo "DOCKER_EXEC_ARGS:$*"
    fi
    exit 0
    ;;
  bwrap-trace)
    if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
    if [[ "${1:-}" == "exec" ]]; then
      echo "DOCKER_EXEC:$*"
      for arg in "$@"; do
        if [[ "$arg" == *"bwrap"* ]]; then
          echo "BWRAP_CANARY_CHECK"
          exit 0
        fi
      done
    fi
    exit 0
    ;;
  bwrap-fail)
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
    ;;
  default|*)
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
    if [[ "${1:-}" == "ps" ]]; then
      # ADR-027 pre-run assertion mock — emit the leftover prod container name
      # only when the test explicitly arms this mode.
      if [[ "${MOCK_DOCKER_PS_PROD_RUNNING:-}" == "1" ]]; then
        echo "soleur-web-platform"
      fi
      exit 0
    fi
    exit 0
    ;;
esac
MOCK
  chmod +x "$1/docker"
}

# Unified curl mock. Behavior selected at runtime via env vars:
#   MOCK_CURL_CANARY_FAIL=1     /health probe fails (existing rollback path)
#   MOCK_CURL_LOGIN_5XX=1       /login returns 503 (canary rejects the swap)
#   MOCK_CURL_DASH_5XX=1        /dashboard returns 503
#   MOCK_CURL_DASH_ERROR_BODY=1 /dashboard returns 200 but body contains the
#                               error.tsx sentinel string
#   MOCK_CURL_LOGIN_EMPTY=1     /login returns 200 with empty body
create_curl_mock() {
  cat > "$1/curl" << 'MOCK'
#!/bin/bash
ARGS=("$@")
URL=""
OUTPUT_FILE=""
WANT_HTTP_CODE=0
for ((i=0; i<${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    -o) OUTPUT_FILE="${ARGS[$((i+1))]}" ;;
    -w)
      if [[ "${ARGS[$((i+1))]}" == *"http_code"* ]]; then WANT_HTTP_CODE=1; fi
      ;;
    http*) URL="${ARGS[$i]}" ;;
  esac
done

# Legacy /health failure path used by existing rollback tests.
if [[ "${MOCK_CURL_CANARY_FAIL:-}" == "1" ]] && [[ "$URL" == *"localhost:3001/health"* ]]; then
  exit 1
fi

write_body() {
  if [[ -n "$OUTPUT_FILE" ]]; then printf '%s' "$1" > "$OUTPUT_FILE"; else printf '%s' "$1"; fi
}

# Per-route mock behavior. Order matters: 8288 must match before generic /health
# because the canary loop's curl -sf for /health does NOT pass -w.
case "$URL" in
  *"8288/v0/gql"*)
    # Cron-plan registry probe (#4650 AC9, #5520). Must match before 8288/health
    # so the substring routes here. Default: a function WITH a cron trigger
    # (healthy plan). Overrides simulate the two H9 failure modes.
    if [[ "${MOCK_CURL_INNGEST_FUNCTIONS_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    if [[ "${MOCK_CURL_INNGEST_FUNCTIONS_NOCRON:-}" == "1" ]]; then
      # H9b: registered but cron de-planned — only the event trigger survives.
      write_body '{"data":{"functions":[{"slug":"soleur-runtime-cron-community-monitor","triggers":[{"type":"EVENT","value":"cron/community-monitor.manual-trigger"}]}]}}'
      exit 0
    fi
    write_body '{"data":{"functions":[{"slug":"soleur-runtime-cron-community-monitor","triggers":[{"type":"CRON","value":"0 8 * * *"},{"type":"EVENT","value":"cron/community-monitor.manual-trigger"}]}]}}'
    exit 0
    ;;
  *"8288/health"*)
    if [[ "${MOCK_CURL_INNGEST_HEALTH_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    write_body '{"status":200,"message":"OK"}'
    exit 0
    ;;
  *"/health"*)
    write_body "OK"
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
    exit 0
    ;;
  *"/login"*)
    if [[ "${MOCK_CURL_LOGIN_5XX:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "503"; fi
      exit 0
    fi
    if [[ "${MOCK_CURL_LOGIN_EMPTY:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
      exit 0
    fi
    write_body "<html><body>Sign in</body></html>"
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
    exit 0
    ;;
  *"/dashboard"*)
    if [[ "${MOCK_CURL_DASH_5XX:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "503"; fi
      exit 0
    fi
    if [[ "${MOCK_CURL_DASH_ERROR_BODY:-}" == "1" ]]; then
      # Structured marker from `components/error-boundary-view.tsx`. Replaces
      # the brittle copy-string sentinel — `data-error-boundary=` survives copy
      # edits and digest-populated renders.
      write_body '<html><body><div data-error-boundary="dashboard"><h2>Something went wrong</h2></div></body></html>'
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
      exit 0
    fi
    # Default: middleware-redirected unauthenticated request.
    write_body ""
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "307"; fi
    exit 0
    ;;
esac

# Fallback for unmatched URLs (legacy callers without an URL arg).
if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; exit 0; fi
write_body "OK"
exit 0
MOCK
  chmod +x "$1/curl"
}

# Layer 3 mock — passes by default; honors MOCK_LAYER3_FAIL=1 to simulate a
# malformed inlined JWT in the canary bundle.
create_mock_layer3() {
  cat > "$1/canary-bundle-claim-check.sh" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_LAYER3_FAIL:-}" == "1" ]]; then
  echo "canary-bundle-claim-check: simulated bad JWT" >&2
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/canary-bundle-claim-check.sh"
}

# Shared mock scaffold: creates all common mock binaries in $MOCK_DIR.
# Docker/curl behavior is driven by MOCK_DOCKER_MODE / MOCK_CURL_MODE env vars
# (see factory docs above). Specialized overrides are rare after consolidation.
create_base_mocks() {
  local mock_dir="$1"
  create_mock_logger "$mock_dir"
  create_docker_mock "$mock_dir"
  create_curl_mock "$mock_dir"
  create_mock_sudo "$mock_dir"
  create_mock_chown "$mock_dir"
  create_mock_seq "$mock_dir"
  create_mock_flock "$mock_dir"
  create_mock_systemctl "$mock_dir"
  create_mock_df "$mock_dir"
  create_mock_doppler "$mock_dir"
  create_mock_layer3 "$mock_dir"
}

# Parse .reason and .exit_code out of a ci-deploy.state JSON file.
# Prefers jq; falls back to grep/sed so tests run without jq installed.
# Usage: read_state_reason_and_exit <state_file> <reason_var> <exit_var>
read_state_reason_and_exit() {
  local state_file="$1"
  local reason_var="$2"
  local exit_var="$3"
  local _reason _exit
  if command -v jq >/dev/null 2>&1; then
    _reason=$(jq -r '.reason // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
    _exit=$(jq -r '.exit_code // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
  else
    _reason=$(grep -oE '"reason":"[^"]*"' "$state_file" | sed 's/.*:"\(.*\)"/\1/')
    _exit=$(grep -oE '"exit_code":-?[0-9]+' "$state_file" | sed 's/.*://')
  fi
  printf -v "$reason_var" '%s' "$_reason"
  printf -v "$exit_var" '%s' "$_exit"
}

run_deploy() {
  # Run ci-deploy.sh in a subshell with SSH_ORIGINAL_COMMAND set.
  # Mock out docker, curl, logger, chown, flock so the script only tests validation logic.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    # CI_DEPLOY_STATE defaults to a per-run temp path unless the caller already set one.
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    create_base_mocks "$MOCK_DIR"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
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
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    export MOCK_DOCKER_MODE="trace"
    create_base_mocks "$MOCK_DIR"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

echo "=== ci-deploy.sh tests ==="
echo ""

echo "--- Happy path ---"
assert_exit "web-platform deploy succeeds" 0 \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# PR-F follow-up (#3960): inngest component branch.
#
# The inngest branch in ci-deploy.sh now extracts the script + ENV vars from
# the OCI image and runs the script on the HOST (not in a container), because
# the Alpine base image lacks `systemctl`. The branch routes through:
#   docker pull → docker create → docker cp → docker inspect → docker rm → sudo
# Each of these is exercised below.
#
# Image mismatch: an attacker-style image suffix injection should be rejected.
assert_exit_contains "inngest: wrong image rejected" 1 "invalid image" \
  "deploy inngest ghcr.io/attacker/soleur-inngest-bootstrap v1.0.0"

# Branch routing in trace mode: verify the inngest branch actually invokes
# `docker pull` (the first observable docker call). Default mode exits 0
# unconditionally; trace mode emits DOCKER_TRACE:<subcmd> markers we can
# assert against. The branch routes pull → create → cp → inspect → rm → sudo,
# but the mock docker's trace output for `inspect` doesn't contain the ENV
# vars the script greps for (INNGEST_CLI_VERSION, INNGEST_CLI_SHA256), so
# the branch exits with "inngest_image_env_missing" after `cp`. The pull
# marker is reliable; a deeper test would need a richer docker-inspect mock.
assert_inngest_docker_trace() {
  local description="$1"
  local cmd="deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.0.0"
  TOTAL=$((TOTAL + 1))

  local output
  output=$(
    export MOCK_DOCKER_MODE="trace"
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1 || true
  )

  # The inngest branch's first observable docker call is `pull`. If we see
  # the trace marker, the branch routed correctly.
  if printf '%s' "$output" | grep -qF "DOCKER_TRACE:pull"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_TRACE:pull found)"
    echo "        output: $output"
  fi
}

assert_inngest_docker_trace "inngest deploy routes through docker pull (trace mode)"

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
#   bwrap sandbox check (docker exec) → stop(canary) → rm(canary) [#5669 memory-dwell:
#   torn down BEFORE the drain] → stop(old) → rm(old) →
#   ps(ADR-027 single-replica assertion) → run(prod)
# (#5669/ADR-078: the post-success canary teardown was removed — the canary is now
#  torn down before the cron drain gate, so it no longer appears after run(prod).)
assert_canary_trace_order "canary success: correct docker trace order" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "image|pull|stop|rm|run|exec|stop|rm|stop|rm|ps|run"

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

# Layered canary probe set (#3014): /health success alone is not enough — the
# probe must also exercise /login (public route) and /dashboard (auth-required)
# and reject any rendered body containing the error.tsx sentinel string. These
# tests cover the failure modes the legacy /health-only probe missed.
assert_canary_layered_rollback() {
  local description="$1"
  local fail_var="$2"  # e.g., MOCK_CURL_LOGIN_5XX
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export "$fail_var"=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Expected on rollback (CANARY_HEALTHY=false): no swap to prod.
  # image|pull|stop|rm|run|stop|rm — same shape as the existing rollback test.
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

assert_canary_layered_rollback \
  "layered canary: /login 5xx → rollback (no swap)" \
  "MOCK_CURL_LOGIN_5XX"

assert_canary_layered_rollback \
  "layered canary: /dashboard 5xx → rollback (no swap)" \
  "MOCK_CURL_DASH_5XX"

assert_canary_layered_rollback \
  "layered canary: /dashboard renders error.tsx sentinel in body → rollback" \
  "MOCK_CURL_DASH_ERROR_BODY"

assert_canary_layered_rollback \
  "layered canary: /login returns empty body → rollback" \
  "MOCK_CURL_LOGIN_EMPTY"

assert_canary_layered_rollback \
  "layered canary: Layer 3 JWT-claims check fails → rollback" \
  "MOCK_LAYER3_FAIL"

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
  # bwrap sandbox check, #5669 pre-drain canary teardown (stop, rm), old stop,
  # old rm, ADR-027 ps assertion (empty in this mock mode), prod run (fails),
  # production_start_failed defensive canary teardown (stop, rm)
  local expected="image|pull|stop|rm|run|exec|stop|rm|stop|rm|ps|run|stop|rm"

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
    export MOCK_FLOCK_CONTENDED=1
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
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
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    create_base_mocks "$MOCK_DIR"

    # Effective tool PATH: mocks first, then standard system dirs.
    local effective_path="$MOCK_DIR:$TEST_PATH_BASE"

    # Override: doppler mock with MOCK_DOPPLER_MISSING/MOCK_DOPPLER_FAIL support
    if [[ "${MOCK_DOPPLER_MISSING:-}" == "1" ]]; then
      rm -f "$MOCK_DIR/doppler"
      # ci-deploy.sh gates on `command -v doppler`. Removing the MOCK_DIR mock is
      # NOT enough on hosts that ALSO ship a system-wide doppler in a TEST_PATH_BASE
      # dir (e.g. /usr/bin/doppler on many dev boxes — NOT the CI runner): it leaks
      # past the removed mock, the real binary runs against the fake token, and the
      # "not installed" branch is never exercised (false FAIL, local-only). When we
      # detect such a leak, mirror the base dirs into a farm WITHOUT doppler so the
      # negative path is reachable everywhere. No-op on CI (no system doppler).
      if PATH="$TEST_PATH_BASE" command -v doppler >/dev/null 2>&1; then
        local _farm="$MOCK_DIR/nodoppler-bin"; mkdir -p "$_farm"
        local _d _f _b _oldifs="$IFS"; IFS=:
        for _d in $TEST_PATH_BASE; do
          [[ -d "$_d" ]] || continue
          for _f in "$_d"/*; do
            _b="${_f##*/}"
            [[ "$_b" == doppler ]] && continue
            [[ -e "$_farm/$_b" ]] || ln -s "$_f" "$_farm/$_b" 2>/dev/null || true
          done
        done
        IFS="$_oldifs"
        effective_path="$MOCK_DIR:$_farm"
      fi
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

    # MOCK_DIR mocks win over system tools; for MOCK_DOPPLER_MISSING on a host with
    # a system doppler, effective_path is a doppler-free farm (see above).
    export PATH="$effective_path"
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

# --- #5933 Item 4: image signature verify (WARN default; ENFORCE gate) ---------
# WARN mode (default) must NEVER block a healthy deploy on a verify failure —
# these two pass IDENTICALLY with or without the gate, so the ENFORCE test below
# is what proves the gate is actually load-bearing (WARN and ENFORCE diverge on
# the SAME MOCK_COSIGN_VERIFY_FAIL input).
assert_verify_warn_does_not_block() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_COSIGN_VERIFY_FAIL=1; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: WARN cosign verify FAIL does not block the deploy (#5933 Item 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: WARN cosign verify FAIL blocked the deploy (exit=$actual_exit)"; echo "        output: $output"
  fi
}
assert_verify_warn_does_not_block

assert_inspect_warn_does_not_block() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_INSPECT_NO_DIGEST=1; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: WARN inspect_failed (no RepoDigest) does not block the deploy (#5933 Item 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: WARN inspect_failed blocked the deploy (exit=$actual_exit)"; echo "        output: $output"
  fi
}
assert_inspect_warn_does_not_block

# ENFORCE mode MUST block the SAME verify failure (proves the gate is load-bearing,
# not vacuous) and keep the old container live via final_write_state 1.
assert_verify_enforce_blocks() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit sf reason exitc
  sf=$(mktemp)
  output=$(export IMAGE_VERIFY_MODE=enforce MOCK_COSIGN_VERIFY_FAIL=1 CI_DEPLOY_STATE="$sf"; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  read_state_reason_and_exit "$sf" reason exitc
  rm -f "$sf"
  if [[ "$actual_exit" -ne 0 && "$reason" == "cosign_verify_failed" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: ENFORCE cosign verify FAIL blocks the deploy (reason=$reason — gate is load-bearing)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: ENFORCE verify fail did not block as expected (exit=$actual_exit reason=$reason)"; echo "        output: $output"
  fi
}
assert_verify_enforce_blocks

# --- #6005 Design B′: cosign invocation shape + SENTRY-before-verify ordering -----
# The verify `docker run` MUST run `--network host` (host-egress .sig fetch, ADR-087),
# mount the deploy docker config :ro (private-pull auth) and the pinned trusted root
# :ro, and pass `--offline --trusted-root` (offline verify). SENTRY_* MUST already be
# in the script env at verify time (the Phase-3 early Doppler fetch ran first → the
# WARN telemetry is not dark, which is the whole point of this ENFORCE-prep issue).
assert_bprime_cosign_invocation() {
  TOTAL=$((TOTAL + 1))
  local argsfile args sentry ok=1
  argsfile=$(mktemp)
  ( export MOCK_COSIGN_ARGS_FILE="$argsfile"; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" >/dev/null 2>&1 ) || true
  args=$(grep '^COSIGN_VERIFY_ARGS:' "$argsfile" 2>/dev/null | head -1)
  sentry=$(grep '^SENTRY_AT_VERIFY:' "$argsfile" 2>/dev/null | head -1)
  rm -f "$argsfile"
  [[ -n "$args" ]] || ok=0
  printf '%s' "$args" | grep -qF -- '--network host' || ok=0
  printf '%s' "$args" | grep -qE -- '-v [^ ]+:/root/\.docker/config\.json:ro' || ok=0
  printf '%s' "$args" | grep -qE -- '-v [^ ]+:/etc/cosign/trusted_root\.json:ro' || ok=0
  printf '%s' "$args" | grep -qF -- '--offline' || ok=0
  printf '%s' "$args" | grep -qF -- '--trusted-root=/etc/cosign/trusted_root.json' || ok=0
  # SENTRY_* set at verify time (not the UNSET sentinel) — telemetry not dark.
  [[ -n "$sentry" && "$sentry" != "SENTRY_AT_VERIFY:UNSET" ]] || ok=0
  if [[ "$ok" == "1" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: B′ cosign run (--network host + config/trusted-root :ro mounts + --offline --trusted-root) and SENTRY set before verify (#6005)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: B′ cosign invocation/ordering (#6005)"; echo "        args: $args"; echo "        sentry: $sentry"
  fi
}
assert_bprime_cosign_invocation

# ADR-087 rejects widening the shared container egress allowlist — ghcr.io reach is
# confined to the ephemeral host-net verifier. Guard against a regression that adds
# ghcr.io back into cron-egress-allowlist.txt.
assert_no_ghcr_allowlist_widening() {
  TOTAL=$((TOTAL + 1))
  local allowlist
  allowlist="$(dirname "$DEPLOY_SCRIPT")/cron-egress-allowlist.txt"
  if [[ -f "$allowlist" ]] && grep -qiE '(^|[^a-z0-9.-])ghcr\.io' "$allowlist"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: ghcr.io must NOT be in cron-egress-allowlist.txt (ADR-087 host-net design) (#6005)"
  else
    PASS=$((PASS + 1)); echo "  PASS: ghcr.io absent from cron-egress-allowlist.txt (ADR-087 — no container allowlist widening) (#6005)"
  fi
}
assert_no_ghcr_allowlist_widening

# AC: the ENFORCE flip stays OUT OF SCOPE — the default MUST remain warn.
TOTAL=$((TOTAL + 1))
if grep -qE 'IMAGE_VERIFY_MODE:-warn' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: IMAGE_VERIFY_MODE default is still 'warn' (no ENFORCE flip) (#6005)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: IMAGE_VERIFY_MODE default must remain 'warn' — ENFORCE flip is out of scope (#6005)"
fi

echo ""
echo "--- AppArmor profile on docker run ---"

assert_apparmor_profile() {
  # Verify that docker run commands include --security-opt apparmor=soleur-bwrap
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
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
echo "--- tmpfs /tmp on docker run (closes #2473) ---"

assert_tmpfs_flag() {
  # Verify every docker run line contains --tmpfs /tmp:…size=256m AND that
  # noexec is NOT on the tmpfs argument. The negative check locks the
  # regression class documented in Research Reconciliation row 5: Docker's
  # default --tmpfs set applies noexec, which silently breaks git credential
  # helpers in /tmp/git-cred-<uuid> (randomCredentialPath in github-app.ts,
  # consumed by workspace.ts / session-sync.ts / push-branch.ts).
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_tmpfs=true
  local any_has_noexec=false
  while IFS= read -r line; do
    # Positive: --tmpfs /tmp:<opts with size=256m>
    if ! printf '%s\n' "$line" | grep -qE -- "--tmpfs /tmp:[^ ]*size=256m"; then
      all_have_tmpfs=false
    fi
    # Negative: no noexec on the /tmp tmpfs argument specifically.
    if printf '%s\n' "$line" | grep -qE -- "--tmpfs /tmp:[^ ]*noexec"; then
      any_has_noexec=true
    fi
  done <<< "$run_lines"

  if [[ "$all_have_tmpfs" == "true" ]] && [[ "$any_has_noexec" == "false" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    if [[ "$all_have_tmpfs" != "true" ]]; then
      echo "  FAIL: $description (missing --tmpfs /tmp:…size=256m on some docker run)"
    fi
    if [[ "$any_has_noexec" == "true" ]]; then
      echo "  FAIL: $description (tmpfs has noexec — breaks git credential helper)"
    fi
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_tmpfs_flag "web-platform: docker run has --tmpfs /tmp:size=256m without noexec" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- CRON_WORKSPACE_ROOT on docker run (#4684/#4689) ---"

assert_cron_workspace_root() {
  # Verify every docker run line carries -e CRON_WORKSPACE_ROOT=/workspaces.
  # Crons mkdtemp their ephemeral clone workspace under this root; in prod it
  # must be the roomy /mnt/data/workspaces volume, NOT the 256 MB /tmp tmpfs,
  # or a git clone of the ~100 MB soleur tree ENOSPCs. The assertion spans ALL
  # docker run lines (canary AND prod) — scoping it to one line would let a
  # canary/prod environment skew ship silently. (The `.cron` subdir isolation
  # was reverted in the #4886 follow-up — a deploy-critical-path mkdir on a full
  # volume deadlocked the deploy; cron-workspace-gc sweeps /workspaces directly,
  # guarded by the `soleur-` prefix. Dedicated-volume isolation deferred to #4891.)
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_root=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF -- "-e CRON_WORKSPACE_ROOT=/workspaces"; then
      all_have_root=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_root" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing -e CRON_WORKSPACE_ROOT=/workspaces)"
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_cron_workspace_root "web-platform: docker run has -e CRON_WORKSPACE_ROOT=/workspaces" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- SOLEUR_HOST_ID on docker run (#5274 Phase 3, ADR-068) ---"

assert_soleur_host_id() {
  # Verify EVERY docker run line (canary AND prod) carries -e SOLEUR_HOST_ID=<id> —
  # the per-user worktree write-lease's placement authority (host-identity.ts). A
  # canary/prod skew (one host-id-tagged, one not) would let a lease-mismatch ship
  # silently once the git-data flag flips. Uses SOLEUR_HOST_ID_OVERRIDE so the id is
  # deterministic (the on-host metadata/machine-id resolution is unit-tested in
  # host-identity.test.ts; here we prove the INJECTION reaches both containers).
  local description="$1"
  local cmd="$2"
  local expected="host-under-test-42"

  TOTAL=$((TOTAL + 1))

  local output
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    export SOLEUR_HOST_ID_OVERRIDE="$expected"
    run_deploy "$cmd" 2>&1
  ) || true

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    return
  fi

  local all_have_id=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF -- "-e SOLEUR_HOST_ID=${expected}"; then
      all_have_id=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_id" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing -e SOLEUR_HOST_ID=${expected})"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_soleur_host_id "web-platform: docker run has -e SOLEUR_HOST_ID on both canary and prod" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Deploy fan-out loop-prevention (#5274 Phase 3, ADR-068) ---"
# The 2-host fan-out is loop-safe ONLY if the /hooks/deploy-peer hook does NOT
# receive the peer list — otherwise a forwarded deploy would re-fan (A->B->A...).
# The invariant lives in hooks.json.tmpl: /hooks/deploy passes SOLEUR_DEPLOY_PEERS,
# /hooks/deploy-peer does NOT. Parsed structurally (jq over each hook's
# pass-environment envnames) so a future edit that leaks peers into deploy-peer
# fails CI. Template exprs (${jsonencode(...)}) are neutralised to valid JSON first.
HOOKS_TMPL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks.json.tmpl"
if [[ -f "$HOOKS_TMPL" ]]; then
  rendered="$(sed -E 's/\$\{jsonencode\([^)]*\)\}/"REDACTED"/g' "$HOOKS_TMPL")"
  deploy_env="$(printf '%s' "$rendered" | jq -r '.[] | select(.id=="deploy") | (.["pass-environment-to-command"] // [])[].envname' 2>/dev/null)"
  peer_env="$(printf '%s' "$rendered" | jq -r '.[] | select(.id=="deploy-peer") | (.["pass-environment-to-command"] // [])[].envname' 2>/dev/null)"

  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$deploy_env" | grep -qx "SOLEUR_DEPLOY_PEERS"; then
    PASS=$((PASS + 1)); echo "  PASS: /hooks/deploy passes SOLEUR_DEPLOY_PEERS (fan-out trigger)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: /hooks/deploy is missing SOLEUR_DEPLOY_PEERS — fan-out would never fire"
  fi

  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$peer_env" | grep -qx "SOLEUR_DEPLOY_PEERS"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: /hooks/deploy-peer passes SOLEUR_DEPLOY_PEERS — a forwarded deploy would RE-FAN (loop)"
  else
    PASS=$((PASS + 1)); echo "  PASS: /hooks/deploy-peer does NOT pass SOLEUR_DEPLOY_PEERS (loop-prevented)"
  fi
else
  echo "  SKIP: hooks.json.tmpl not found at $HOOKS_TMPL"
fi

echo ""
echo "--- Bwrap canary sandbox check ---"

assert_bwrap_canary_check() {
  # Verify that a bwrap check runs against the canary container after health check.
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="bwrap-trace"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
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
    export MOCK_DOCKER_MODE="bwrap-fail"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
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
echo "--- Bwrap userns sysctl drift detector (non-blocking) ---"

assert_bwrap_userns_drift_detector_nonblocking() {
  # Follow-up to #4932/#4941: ci-deploy.sh must read the host sysctl
  # kernel.apparmor_restrict_unprivileged_userns after the prod container starts
  # and surface a drift WARN — but it must be NON-BLOCKING (detection only), so a
  # drift reading never rolls back a deploy the way the reverted #4932 gating
  # probe did. Source-level guard: the drift branch must use `logger`, and the
  # whole userns check must NOT call `final_write_state 1` or `exit` (anchored on
  # the unique message tokens; non-vacuous — neither token existed pre-#4941).
  TOTAL=$((TOTAL + 1))

  local block
  # Extract the userns check block: the logger lines from the first
  # BWRAP_USERNS_SYSCTL token through the trailing "Deploy succeeded".
  block=$(awk '/BWRAP_USERNS_SYSCTL/{f=1} f{print} /Deploy succeeded/{f=0}' "$DEPLOY_SCRIPT" 2>/dev/null)

  # `|| true`: grep -c exits 1 on zero matches, which would abort under set -e.
  local has_ok has_drift gates
  has_ok=$(printf '%s\n' "$block" | grep -cF "BWRAP_USERNS_SYSCTL_CHECK: ok" || true)
  has_drift=$(printf '%s\n' "$block" | grep -cF "BWRAP_USERNS_SYSCTL_DRIFT" || true)
  # Non-blocking: the block must not contain a failure-write or exit.
  gates=$(printf '%s\n' "$block" | grep -cE 'final_write_state 1|exit 1|exit 0' || true)

  if [[ "$has_ok" -ge 1 && "$has_drift" -ge 1 && "$gates" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: userns sysctl drift detector present and non-blocking"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: userns drift detector must be present and non-blocking (ok=$has_ok drift=$has_drift gating_calls=$gates)"
  fi
}

assert_bwrap_userns_drift_detector_nonblocking

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
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    export ENV_FILE_TRACKER="$tracker_dir/env_file_path"
    create_base_mocks "$MOCK_DIR"
    # Default docker mock already honors MOCK_DOCKER_RUN_FAIL_CANARY and returns
    # exit 0 for exec (the cleanup scenario never needs bwrap tracing).

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
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
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
# Signature: assert_state_contains <description> <expected_reason> <expected_exit_code> [<cmd>] [<extra_env>] [<runner>]
#   <runner> defaults to run_deploy_traced. Pass run_deploy_doppler for scenarios
#   that need the restricted PATH + configurable doppler mock (doppler_* reasons).
assert_state_contains() {
  local description="$1"
  local expected_reason="$2"
  local expected_exit_code="$3"
  # Use ${4-default} (no colon) so an explicitly empty "" for cmd is preserved
  # -- needed to exercise the command_missing branch.
  local cmd="${4-deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0}"
  local extra_env="${5:-}"
  local runner="${6:-run_deploy_traced}"

  TOTAL=$((TOTAL + 1))

  # State file lives outside the per-run MOCK_DIR so we can read it after the subshell cleans up.
  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    eval "$extra_env"
    export CI_DEPLOY_STATE="$state_file"
    "$runner" "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

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

# Docker pull failure -> reason=image_pull_failed (#6005). The pull is now against a
# PRIVATE package (M2 SPOF), so a denial is caught explicitly and a scrubbed, no-SSH
# pull_failure_event fires before aborting — replacing the legacy "unhandled" EXIT-trap
# fallthrough (the #2202 follow-up this comment anticipated).
assert_state_contains "docker pull fail writes reason=image_pull_failed (#6005)" \
  "image_pull_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_PULL_FAIL=1"

# Canary container run crash -> unhandled via set -e. Today's behavior: docker run
# failures for the canary container fall through to the EXIT trap as "unhandled"
# (no explicit canary_crashed handler). When the follow-up adds a canary_crashed
# reason, this assertion will fail and force a single-direction update.
assert_state_contains "canary container run crash writes reason=unhandled" \
  "unhandled" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_RUN_FAIL_CANARY=1"

# Canary health probe failure -> reason=canary_health_failed (per-layer reason
# taxonomy added in #3014 — replaces the legacy generic canary_failed reason).
assert_state_contains "canary health failure writes reason=canary_health_failed" \
  "canary_health_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_CANARY_FAIL=1"

# Per-layer canary failure reasons — each layer fails independently and writes
# its own reason for incident attribution.
assert_state_contains "canary /login 5xx writes reason=canary_login_failed" \
  "canary_login_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_LOGIN_5XX=1"

assert_state_contains "canary /dashboard 5xx writes reason=canary_dashboard_5xx" \
  "canary_dashboard_5xx" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_DASH_5XX=1"

assert_state_contains "canary error-boundary marker in body writes reason=canary_error_boundary" \
  "canary_error_boundary" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_DASH_ERROR_BODY=1"

assert_state_contains "canary Layer 3 JWT-claims failure writes reason=canary_layer3_jwt_claims" \
  "canary_layer3_jwt_claims" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_LAYER3_FAIL=1"

# -- Command parsing reason coverage (#2202) --
# These validations run BEFORE flock and Doppler resolution, so run_deploy_traced
# (with its generic docker/doppler mocks) exercises them correctly.

# Empty SSH_ORIGINAL_COMMAND -> reason=command_missing
assert_state_contains "empty command writes reason=command_missing" \
  "command_missing" "1" \
  ""

# Wrong field count (not 4) -> reason=command_malformed
assert_state_contains "malformed command writes reason=command_malformed" \
  "command_malformed" "1" \
  "deploy"

# Unknown action verb -> reason=action_unknown
assert_state_contains "unknown action writes reason=action_unknown" \
  "action_unknown" "1" \
  "notify web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Unknown component -> reason=component_unknown
assert_state_contains "unknown component writes reason=component_unknown" \
  "component_unknown" "1" \
  "deploy unknown-app ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Wrong image for component -> reason=image_mismatch
assert_state_contains "wrong image writes reason=image_mismatch" \
  "image_mismatch" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-attacker-repo v1.0.0"

# Malformed semver tag -> reason=tag_malformed
assert_state_contains "bad tag writes reason=tag_malformed" \
  "tag_malformed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"

# -- Doppler reason coverage (#2202) --
# Doppler reasons require run_deploy_doppler (restricted PATH + configurable doppler mock);
# pass it as the 6th arg to assert_state_contains.

# Doppler binary absent -> reason=doppler_unavailable
assert_state_contains "missing doppler binary writes reason=doppler_unavailable" \
  "doppler_unavailable" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_MISSING=1" \
  "run_deploy_doppler"

# DOPPLER_TOKEN unset -> reason=doppler_token_missing
assert_state_contains "unset DOPPLER_TOKEN writes reason=doppler_token_missing" \
  "doppler_token_missing" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_TOKEN_UNSET=1" \
  "run_deploy_doppler"

# Doppler secrets download fails -> reason=doppler_fetch_failed
assert_state_contains "doppler fetch failure writes reason=doppler_fetch_failed" \
  "doppler_fetch_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_FAIL=1" \
  "run_deploy_doppler"

# -- Bwrap sandbox verification failure (#2202) --
# canary_sandbox_failed is written when `docker exec soleur-web-platform-canary bwrap ...`
# fails after the canary is running and healthy. Needs a custom docker mock that accepts
# `run` and curl-health-check but fails on `exec ... bwrap`.
assert_canary_sandbox_failed_state() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    export CI_DEPLOY_STATE="$state_file"
    export MOCK_DOCKER_MODE="bwrap-fail"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: canary_sandbox_failed writes reason (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

  if [[ "$actual_reason" == "canary_sandbox_failed" ]] && [[ "$actual_exit_code" == "1" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap sandbox failure writes reason=canary_sandbox_failed"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap sandbox failure writes reason=canary_sandbox_failed"
    echo "        expected: reason=canary_sandbox_failed exit_code=1"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
    echo "        output:   $output"
  fi

  rm -rf "$state_dir"
}

assert_canary_sandbox_failed_state

# Production container start failure (after canary passes) -> reason=production_start_failed
assert_state_contains "production start failure writes reason=production_start_failed" \
  "production_start_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_RUN_FAIL_PROD=1"

# Note: no_handler is unreachable without modifying ci-deploy.sh (requires a
# component allowlisted in ALLOWED_IMAGES but missing from the case statement).
# Skipped per #2202 scope.

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
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
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
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
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

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

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

# ADR-027 — pre-`docker run` single-replica assertion. When a leftover
# soleur-web-platform container is still running after docker stop|| rm
# masked a failure (|| true), the script must abort with a clear,
# ADR-027-referencing error rather than letting docker run produce a
# cryptic "name already in use".
echo ""
echo "--- ADR-027 pre-run single-replica assertion ---"

assert_adr027_pre_run_assertion() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="trace"
    export MOCK_DOCKER_PS_PROD_RUNNING=1
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Three invariants must hold:
  # 1. Exit non-zero (assertion fired).
  # 2. Output names ADR-027 (operator can grep the doc).
  # 3. The production docker-run trace must NOT appear after the assertion —
  #    without this, a regression that fired the assertion but still ran the
  #    `docker run -d --name soleur-web-platform` would pass invariants 1&2
  #    while corrupting the deploy. The canary trace uses a -canary suffix and
  #    is permitted; the bare prod-name run is what we forbid.
  local prod_run_lines
  prod_run_lines=$(
    printf '%s\n' "$output" \
      | awk '/ADR-027/{found=1} found' \
      | grep -E 'DOCKER_TRACE:run' \
      | grep -vE -- '-canary' \
      || true
  )

  if [[ "$actual_exit" -ne 0 ]] \
    && printf '%s\n' "$output" | grep -qF "ADR-027" \
    && [[ -z "$prod_run_lines" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: leftover soleur-web-platform aborts deploy with ADR-027 message (no prod docker-run after abort)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: leftover soleur-web-platform aborts deploy with ADR-027 message"
    echo "        expected: non-zero exit AND output contains 'ADR-027' AND no prod 'docker run' after abort"
    echo "        actual exit: $actual_exit"
    echo "        prod_run_after_abort: $prod_run_lines"
    echo "        output: $output"
  fi
}

assert_adr027_pre_run_assertion

# SIGTERM trap (#3704). The trap pattern in ci-deploy.sh writes terminal
# state (exit_code=124 reason=timeout) when SIGTERM is delivered to the
# script's bash AND bash can run the trap. The latter holds when bash is
# between commands, in `wait`, or in shell logic — NOT during a hung
# foreground command (bash queues the trap until the foreground command
# returns). For the hung-foreground case, the wall-clock fallback is
# ci-deploy-wrapper.sh's `--kill-after=20s`, which sends SIGKILL after the
# 20s grace; the bash dies, no trap fires, the state stays at "running"
# until the workflow's pre-rerun probe sees `elapsed > 900s` and falls
# through (degraded-permissive). This is documented in the plan's Risks
# section.
#
# Two assertions:
#   1. STATIC: ci-deploy.sh has `set -m` AND the canonical TERM/INT trap.
#   2. RUNTIME: the trap pattern, exercised in an isolated reproduction
#      (bash script in `sleep & wait $!`), writes the expected state file
#      and exits 124. Covers the trap's correctness contract without
#      depending on ci-deploy.sh's specific code path.
echo ""
echo "--- SIGTERM trap (#3704) ---"

assert_ci_deploy_has_trap_installed() {
  TOTAL=$((TOTAL + 1))
  local found_set_m found_trap
  found_set_m=$(grep -cE '^set -m\b' "$DEPLOY_SCRIPT" || true)
  # Canonical trap shape: final_write_state 124 "timeout" followed by
  # pkill -P $$ and exit 124, bound to TERM/INT. We don't pin every
  # token (set -m vs trap order can shift), just the load-bearing parts.
  found_trap=$(grep -cE 'trap .*final_write_state 124 "timeout".*pkill -TERM -P .*TERM INT' "$DEPLOY_SCRIPT" || true)
  if [[ "$found_set_m" -ge 1 ]] && [[ "$found_trap" -ge 1 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: ci-deploy.sh has 'set -m' and the canonical TERM/INT trap installed"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: trap-install static check (set -m matches: $found_set_m, trap matches: $found_trap)"
  fi
}

assert_ci_deploy_has_trap_installed

assert_trap_writes_timeout_state_in_isolation() {
  TOTAL=$((TOTAL + 1))
  local verdict
  verdict=$(
    set +e
    local mock_dir state_file repro pid i
    mock_dir=$(mktemp -d)
    state_file="$mock_dir/state"
    repro="$mock_dir/repro.sh"

    # Minimal reproduction of ci-deploy.sh's trap setup. Uses `sleep & wait`
    # so the TERM trap fires immediately (vs. foreground `sleep` which would
    # defer until the sleep returns — the production limitation called out
    # above). The trap line MUST be byte-identical to ci-deploy.sh's.
    cat > "$repro" <<REPRO
#!/usr/bin/env bash
set -euo pipefail
set -m
STATE_FILE="$state_file"
START_TS=\$(date +%s)
COMPONENT="web-platform"
IMAGE="test"
TAG="v1.0.0"
write_state() {
  local tmp
  tmp=\$(mktemp "\$STATE_FILE.XXXXXX") || return 0
  printf '{"start_ts":%d,"end_ts":%d,"exit_code":%d,"component":"%s","image":"%s","tag":"%s","reason":"%s"}\n' \\
    "\$START_TS" "\$(date +%s)" "\$1" "\$COMPONENT" "\$IMAGE" "\$TAG" "\$2" > "\$tmp"
  mv "\$tmp" "\$STATE_FILE"
}
final_write_state() {
  touch "\$STATE_FILE.final" 2>/dev/null || true
  write_state "\$1" "\$2"
}
trap 'final_write_state 124 "timeout"; trap - TERM INT; pkill -TERM -P \$\$ 2>/dev/null || true; exit 124' TERM INT
sleep 30 &
wait \$!
REPRO
    chmod +x "$repro"

    "$repro" &
    pid=$!

    # Let the script enter `wait` (interruptible builtin).
    sleep 0.3

    kill -TERM "$pid" 2>/dev/null || true

    # Wait up to 5s for the script to exit.
    for i in $(seq 1 50); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "FAIL: repro script did not exit within 5s after SIGTERM"
      rm -rf "$mock_dir"
      return 0
    fi
    wait "$pid" 2>/dev/null
    local exit_rc=$?

    # Verify state file
    if [[ ! -f "$state_file" ]]; then
      echo "FAIL: state file not written by trap (exit_rc=$exit_rc)"
      rm -rf "$mock_dir"
      return 0
    fi

    local actual_reason actual_exit_code
    read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

    # Verify no orphan sleep child (pkill -P $$ should have killed it).
    local orphan
    orphan=$(pgrep -P "$pid" 2>/dev/null || true)
    if [[ -n "$orphan" ]]; then
      kill -KILL $orphan 2>/dev/null || true
      echo "FAIL: orphan child PIDs survived pkill -P (pids: $orphan)"
      rm -rf "$mock_dir"
      return 0
    fi

    if [[ "$actual_reason" == "timeout" ]] && [[ "$actual_exit_code" == "124" ]] && [[ "$exit_rc" -eq 124 ]]; then
      echo "PASS: trap writes exit_code=124 reason=timeout, repro exits 124, no orphan children"
      rm -rf "$mock_dir"
      return 0
    else
      echo "FAIL: state/exit mismatch (expected reason=timeout exit_code=124 rc=124; got reason=$actual_reason exit_code=$actual_exit_code rc=$exit_rc)"
      rm -rf "$mock_dir"
      return 0
    fi
  )

  if [[ "$verdict" == PASS:* ]]; then
    PASS=$((PASS + 1))
    echo "  $verdict"
  else
    FAIL=$((FAIL + 1))
    echo "  $verdict"
  fi
}

assert_trap_writes_timeout_state_in_isolation

# --- Restart action tests (#4538) ---
echo ""
echo "--- Restart action ---"

# AC1: restart inngest succeeds with healthy server + registered functions
assert_state_contains "restart inngest succeeds" \
  "success" "0" \
  "restart inngest _ latest"

# AC2: restart of non-inngest component rejected
assert_state_contains "restart web-platform rejected" \
  "component_not_restartable" "1" \
  "restart web-platform _ latest"

# AC5(a): systemctl restart failure
assert_state_contains "restart inngest systemctl failure" \
  "inngest_restart_failed" "1" \
  "restart inngest _ latest" \
  "export MOCK_SYSTEMCTL_FAIL=1"

# AC5(b): restart with inngest health check failure
assert_state_contains "restart inngest health failure" \
  "inngest_health_failed" "1" \
  "restart inngest _ latest" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1"

# #4650 AC9, reframed #5159: the cron-plan check is now ADVISORY. A server that
# is /health-healthy but whose cron triggers are de-planned (H9b) no longer FAILS
# the deploy — a standalone inngest restart de-plans crons until a web-platform
# redeploy (modified:true sync) or the --poll-interval self-heal re-arms them, so
# failing the deploy on a de-planned registry would be a false negative. The
# Sentry cron monitors are the real safety net for persistent de-plans. The
# default mock returns a cron-triggered function, so the AC1 "restart inngest
# succeeds" test above exercises the cron-present path; this exercises the
# cron-absent path now resolving to `success`.
assert_state_contains "restart inngest succeeds when cron plan de-planned (advisory, #5159)" \
  "success" "0" \
  "restart inngest _ latest" \
  "export MOCK_CURL_INNGEST_FUNCTIONS_NOCRON=1"

# #4652 AC3: the `deploy inngest` SUCCESS path must gate on verify_inngest_health
# (the restart action already does — see the four restart tests above; the
# deploy path did NOT before #4652). verify_inngest_health's runtime behavior
# (healthy → success, /health-fail → inngest_health_failed, cron-deplaned →
# inngest_health_failed) is execution-tested via those restart-action tests.
# Driving the deploy-inngest path to its success branch would need a new
# docker-inspect ENV mode + a sudo-bootstrap stub (the existing trace test stops
# at inngest_image_env_missing) — out of scope here; instead assert the WIRING:
# in the deploy-inngest branch verify_inngest_health runs BEFORE the success
# state-write, with an inngest_health_failed branch between them.
# ORDERING DEPENDENCY: the `tail -1` anchors below assume the `deploy inngest`
# case arm appears AFTER the `restart inngest` arm in ci-deploy.sh (so the last
# verify_inngest_health / last inngest_health_failed belong to the deploy arm).
# That holds today; if the case arms are reordered, re-anchor these greps to the
# deploy-inngest block (e.g. via awk between the arm's case label and `;;`).
TOTAL=$((TOTAL + 1))
DI_VERIFY_LINE=$(grep -nE '^[[:space:]]*verify_inngest_health[[:space:]]*$' "$DEPLOY_SCRIPT" | tail -1 | cut -d: -f1)
DI_SUCCESS_LINE=$(grep -nE 'SUCCESS: inngest .* deployed' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1)
DI_FAIL_LINE=$(grep -nE 'final_write_state 1 "inngest_health_failed"' "$DEPLOY_SCRIPT" | tail -1 | cut -d: -f1)
if [[ -n "$DI_VERIFY_LINE" && -n "$DI_SUCCESS_LINE" && -n "$DI_FAIL_LINE" \
      && "$DI_VERIFY_LINE" -lt "$DI_FAIL_LINE" && "$DI_FAIL_LINE" -lt "$DI_SUCCESS_LINE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: deploy inngest success path gates on verify_inngest_health (#4652 AC3 wiring)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: deploy inngest verify_inngest_health wiring (verify=$DI_VERIFY_LINE fail=$DI_FAIL_LINE success=$DI_SUCCESS_LINE)"
fi

# Existing deploy validation still rejects `deploy inngest restart latest`
# (image mismatch since "restart" != expected image)
assert_state_contains "deploy inngest restart latest rejected as image_mismatch" \
  "image_mismatch" "1" \
  "deploy inngest restart latest"

# Regression guard for #5062: the long-running foreground docker children
# (prune/pull) MUST close the FD-200 advisory lock (`200>&-`) so an orphaned
# child (bash SIGKILLed mid-`docker pull`, TERM trap never dispatched) cannot
# hold the flock past ci-deploy.sh's death and block all future deploys. A
# source-grep gate — a future edit that drops `200>&-` re-introduces the
# 40-min-stuck-lock class the v0.116.1 PIR documented.
TOTAL=$((TOTAL + 1))
# NB: the web-platform pull is wrapped in an `if ! docker pull … ; then` failure
# guard (#6005), so the pull match is not line-anchored — the load-bearing assertion
# is that `200>&-` still rides the pull (FD-200 close preserved through the wrap).
if grep -qE 'docker pull "\$IMAGE:\$TAG" 200>&-' "$DEPLOY_SCRIPT" \
   && grep -qE '^[[:space:]]*docker image prune -af 200>&-' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1))
  echo "  PASS: long-running docker children close FD-200 lock (200>&-) — #5062 guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: docker pull/prune must close FD-200 via '200>&-' (#5062) — an orphaned pull would hold the deploy lock"
fi

# #5145 / reframed #5159: the cron-plan loop owns its own (advisory) budget,
# distinct from the /health loop. Post-#5159 the cron-plan check is best-effort
# (crons re-arm async via redeploy or --poll-interval), so the budget is the
# narrower cron_max_attempts=10 rather than the old 40.
# Budget VALUES are runtime-untestable here: create_mock_seq collapses every
# loop to one iteration (that mock is what keeps this suite inside
# infra-validation.yml's 5-min job timeout — do not weaken it), so these are
# static source pins. Regression classes guarded:
#   - shared-budget collapse (cron loop reverting to $max_attempts)
#   - loop swap (the cron budget driving the FIRST loop instead of the second)
#   - curl-tail retune (--max-time 5 is the source of the drift guard's +5
#     term below; retuning it silently invalidates that arithmetic)
# The `seq` FORM pin is itself load-bearing: a C-style for ((...)) refactor
# would escape the seq mock and blow the 5-min CI timeout.
echo ""
echo "--- verify_inngest_health cron-plan budget (#5145) ---"
TOTAL=$((TOTAL + 1))
CRON_PIN_COUNT=$(grep -cE '^[[:space:]]*local cron_max_attempts=10\b' "$DEPLOY_SCRIPT" || true)
CRON_SEQ_COUNT=$(grep -cE 'seq 1 "\$cron_max_attempts"' "$DEPLOY_SCRIPT" || true)
HEALTH_SEQ_LINE=$(grep -nE 'seq 1 "\$max_attempts"' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
CRON_SEQ_LINE=$(grep -nE 'seq 1 "\$cron_max_attempts"' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
FUNCTIONS_CURL_LINE=$(grep -nE 'curl -sf --max-time 5 .*http://127\.0\.0\.1:8288/v0/gql' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
# Probe pin scoped to the function region — a third `curl -sf --max-time 5`
# exists outside verify_inngest_health (the deploy-arm web-platform health
# probe), so a file-global count would be wrong.
VERIFY_FN_MAXTIME=$(awk '/^verify_inngest_health\(\) \{/,/^\}/' "$DEPLOY_SCRIPT" | grep -c 'curl -sf --max-time 5' || true)
if [[ "$CRON_PIN_COUNT" -eq 1 && "$CRON_SEQ_COUNT" -eq 1 \
      && -n "$HEALTH_SEQ_LINE" && -n "$CRON_SEQ_LINE" && -n "$FUNCTIONS_CURL_LINE" \
      && "$HEALTH_SEQ_LINE" -lt "$CRON_SEQ_LINE" && "$CRON_SEQ_LINE" -lt "$FUNCTIONS_CURL_LINE" \
      && "$VERIFY_FN_MAXTIME" -eq 2 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: cron-plan loop owns its pinned budget (cron_max_attempts=10 drives the second loop; both probes --max-time 5) — #5145"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: cron-budget pin (#5145) (pin=$CRON_PIN_COUNT seq_form=$CRON_SEQ_COUNT health_seq_line=$HEALTH_SEQ_LINE cron_seq_line=$CRON_SEQ_LINE functions_curl_line=$FUNCTIONS_CURL_LINE fn_maxtime=$VERIFY_FN_MAXTIME)"
fi

# #5145 cross-file drift guard: the restart workflow's client-side poll window
# must exceed ci-deploy.sh's server-side verify worst case, or the workflow
# times out on exactly the slow-resync case the wider budget tolerates.
# Values are extracted generically BY SHAPE (not pinned literals) so a
# legitimate retune re-runs the inequality with the new numbers instead of
# dying as "unparseable" — exact-value pinning is the assertion above's job.
# Server worst case (right side of the inequality):
#   (health_attempts + cron_attempts) * (interval + 5)
#     +5 = per-attempt `curl --max-time 5` tail (source: the --max-time pin
#          above; sleep-only arithmetic undercounts the true worst case ~2.6x)
#   +stop = TimeoutStopSec hung-stop budget the systemd restart can consume
#          BEFORE the verify starts — extracted by shape from the
#          inngest-server unit heredoc in inngest-bootstrap.sh (scoped: a
#          second TimeoutStopSec=30 exists in the vector unit)
#   +60  = webhook handoff/flock/client-curl margin
# Same invariant class as web-platform-release.yml's STATUS_POLL ==
# IN_FLIGHT_CEILING_S runtime assert.
TOTAL=$((TOTAL + 1))
RESTART_WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/restart-inngest-server.yml"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/inngest-bootstrap.sh"
# tail -1 on the digit runs: "${1:-10}" tokenizes to "1" then "10" — the
# DEFAULT is the last run, not the first.
DG_HEALTH=$(grep -oE '\$\{1:-[0-9]+\}' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' | tail -1 || true)
DG_INTERVAL=$(grep -oE '\$\{2:-[0-9]+\}' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' | tail -1 || true)
DG_CRON=$(grep -oE '^[[:space:]]*local cron_max_attempts=[0-9]+' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' || true)
DG_INNGEST_UNIT=$(awk '/Description=Inngest self-hosted server/,/^UNITEOF$/' "$BOOTSTRAP_SCRIPT")
DG_STOP=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -oE '^TimeoutStopSec=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
DG_MAX_POLLS=$(grep -oE 'MAX_POLLS=[0-9]+' "$RESTART_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
DG_POLL_INTERVAL=$(grep -oE 'POLL_INTERVAL=[0-9]+' "$RESTART_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
# Exactly-one assignment per extraction shape — a duplicate (or zero) match
# makes the head -1 extraction silently ambiguous (e.g. a future helper
# earlier in ci-deploy.sh with its own ${1:-N} default would hijack
# DG_HEALTH and shrink the inequality's right side without failing).
DG_HEALTH_COUNT=$(grep -cE '\$\{1:-[0-9]+\}' "$DEPLOY_SCRIPT" || true)
DG_INTERVAL_COUNT=$(grep -cE '\$\{2:-[0-9]+\}' "$DEPLOY_SCRIPT" || true)
DG_CRON_COUNT=$(grep -cE '^[[:space:]]*local cron_max_attempts=[0-9]+' "$DEPLOY_SCRIPT" || true)
DG_STOP_COUNT=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -cE '^TimeoutStopSec=[0-9]+' || true)
DG_MAX_POLLS_COUNT=$(grep -cE 'MAX_POLLS=[0-9]+' "$RESTART_WORKFLOW" || true)
DG_POLL_INTERVAL_COUNT=$(grep -cE 'POLL_INTERVAL=[0-9]+' "$RESTART_WORKFLOW" || true)
DG_OK=1
DG_WHY=""
# Validate BEFORE arithmetic: bash $((v * 5)) on an empty string evaluates to
# 0 silently and the inequality would pass for the wrong reason.
for pair in "health:$DG_HEALTH" "interval:$DG_INTERVAL" "cron:$DG_CRON" "stop:$DG_STOP" "max_polls:$DG_MAX_POLLS" "poll_interval:$DG_POLL_INTERVAL"; do
  if ! [[ "${pair#*:}" =~ ^[0-9]+$ ]]; then
    DG_OK=0
    DG_WHY="non-integer extraction: ${pair%%:*}"
  fi
done
for pair in "health:$DG_HEALTH_COUNT" "interval:$DG_INTERVAL_COUNT" "cron:$DG_CRON_COUNT" "stop:$DG_STOP_COUNT" "max_polls:$DG_MAX_POLLS_COUNT" "poll_interval:$DG_POLL_INTERVAL_COUNT"; do
  if [[ "$DG_OK" -eq 1 && "${pair#*:}" -ne 1 ]]; then
    DG_OK=0
    DG_WHY="expected exactly one assignment match for ${pair%%:*} (got ${pair#*:})"
  fi
done
DG_LEFT=""
DG_RIGHT=""
if [[ "$DG_OK" -eq 1 ]]; then
  DG_LEFT=$((DG_MAX_POLLS * DG_POLL_INTERVAL))
  DG_RIGHT=$(((DG_HEALTH + DG_CRON) * (DG_INTERVAL + 5) + DG_STOP + 60))
  if [[ "$DG_LEFT" -lt "$DG_RIGHT" ]]; then
    DG_OK=0
    DG_WHY="client window ${DG_LEFT}s < server worst case ${DG_RIGHT}s"
  fi
fi
if [[ "$DG_OK" -eq 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: restart workflow client window (${DG_LEFT}s) covers verify worst case (${DG_RIGHT}s) — #5145 drift guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: client/server budget drift guard (#5145): $DG_WHY (health=$DG_HEALTH interval=$DG_INTERVAL cron=$DG_CRON stop=$DG_STOP MAX_POLLS=$DG_MAX_POLLS POLL_INTERVAL=$DG_POLL_INTERVAL left=$DG_LEFT right=$DG_RIGHT; files: ci-deploy.sh, inngest-bootstrap.sh, .github/workflows/restart-inngest-server.yml)"
fi

echo ""
echo "--- Container memory caps (#5417 AC3) ---"

# Both docker-run blocks (canary --restart no, prod --restart unless-stopped)
# must carry --memory + --memory-swap + --init so a heavy-cron memory spike
# becomes a deterministic cgroup-OOM of the container instead of an arbitrary
# HOST-OOM victim. Source-grep gate (the AC3 verification shape): mutating any
# flag out of ci-deploy.sh fails this. Counts assert BOTH sites are covered.
TOTAL=$((TOTAL + 1))
MEM_FLAG_COUNT=$(grep -cE -- '--memory "\$(PROD|CANARY)_MEMORY_CAP"' "$DEPLOY_SCRIPT" || true)
SWAP_FLAG_COUNT=$(grep -cE -- '--memory-swap "\$(PROD|CANARY)_MEMORY_CAP"' "$DEPLOY_SCRIPT" || true)
INIT_FLAG_COUNT=$(grep -cE -- '^[[:space:]]+--init \\' "$DEPLOY_SCRIPT" || true)
# Both docker runs pass a COMPOSED NODE_OPTIONS (Doppler value + our cap appended
# so -e does not clobber an operator-set value — #5417 review). Assert both
# call-sites use the composed var AND that each composed var sets the heap cap.
NODE_OPT_COUNT=$(grep -cE -- '-e NODE_OPTIONS="\$(PROD|CANARY)_NODE_OPTIONS"' "$DEPLOY_SCRIPT" || true)
NODE_OPT_COMPOSE_COUNT=$(grep -cE -- '^[[:space:]]+(PROD|CANARY)_NODE_OPTIONS=.*--max-old-space-size=\$(PROD|CANARY)_NODE_MAX_OLD_SPACE_MB' "$DEPLOY_SCRIPT" || true)
CAP_CONST_COUNT=$(grep -cE '^readonly (PROD_MEMORY_CAP|CANARY_MEMORY_CAP|PROD_NODE_MAX_OLD_SPACE_MB|CANARY_NODE_MAX_OLD_SPACE_MB)=' "$DEPLOY_SCRIPT" || true)
if [[ "$MEM_FLAG_COUNT" -eq 2 && "$SWAP_FLAG_COUNT" -eq 2 && "$INIT_FLAG_COUNT" -eq 2 \
   && "$NODE_OPT_COUNT" -eq 2 && "$NODE_OPT_COMPOSE_COUNT" -eq 2 && "$CAP_CONST_COUNT" -eq 4 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: prod+canary docker run carry --memory/--memory-swap/--init from named caps; both set --max-old-space-size (appended to any Doppler NODE_OPTIONS) below the cap (#5417 AC1/AC3)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: memory-cap source gate (mem=$MEM_FLAG_COUNT/2 swap=$SWAP_FLAG_COUNT/2 init=$INIT_FLAG_COUNT/2 node_opt=$NODE_OPT_COUNT/2 compose=$NODE_OPT_COMPOSE_COUNT/2 consts=$CAP_CONST_COUNT/4; file: ci-deploy.sh)"
fi

echo ""
echo "--- #5547 Gap 1: existing-host deploy stages the durable Redis assets ---"
# The existing-host deploy path runs inngest-bootstrap.sh DIRECTLY on the host
# (the Alpine extract container has no systemctl), bypassing the OCI image
# ENTRYPOINT that stages /tmp/inngest-redis.* on the fresh-host cloud-init path.
# So ci-deploy.sh's `case "inngest")` MUST docker-cp the three Redis assets to
# the /tmp staging path itself, or inngest-bootstrap.sh's Redis-install guard
# (`[[ -f /tmp/inngest-redis.conf && ... ]]`) is always false → Redis never
# installed → the durable ExecStart crash-loops (#5547 Gap 1).
# Per-asset line-start greps (NOT a `grep -c >= 3`, which a WHY-comment naming
# inngest-redis would inflate — AC1).
TOTAL=$((TOTAL + 1))
G1_CONF=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis\.conf' "$DEPLOY_SCRIPT" || true)
G1_SERVICE=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis\.service' "$DEPLOY_SCRIPT" || true)
G1_BOOTSTRAP=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis-bootstrap\.sh' "$DEPLOY_SCRIPT" || true)
if [[ "$G1_CONF" -ge 1 && "$G1_SERVICE" -ge 1 && "$G1_BOOTSTRAP" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: ci-deploy.sh stages inngest-redis.{conf,service} + inngest-redis-bootstrap.sh to /tmp (#5547 Gap 1 / AC1)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ci-deploy.sh must docker cp all three Redis assets in case inngest (conf=$G1_CONF service=$G1_SERVICE bootstrap=$G1_BOOTSTRAP; file: ci-deploy.sh / #5547 AC1)"
fi

echo ""
echo "--- #5547 Gap 3: verify_inngest_health degraded advisory + success_degraded_durability ---"
# Source-scoped (runtime-driving the deploy path is out of scope per the #4652
# AC3 wiring comment above). AC5 — verify_inngest_health emits a degraded
# ADVISORY (NOT return 1) via `logger -t "$LOG_TAG"` when the ExecStart lacks the
# durable sentinel (the SQLite-only fail-safe), while the durable FAIL branch
# (inngest-redis not active) still `return 1`. #5560: the "--redis-uri absent" FAIL
# branch was REMOVED — the postgres/redis URIs are env-delivered now, so the only
# durable-failure signal on argv is the sentinel + the redis-service-active check.
VIH_FN=$(awk '/^verify_inngest_health\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")
VIH_ADVISORY=$(printf '%s\n' "$VIH_FN" | grep -cE 'logger -t "\$LOG_TAG" "INNGEST_DURABLE: advisory' || true)
VIH_FAIL_NOT_ACTIVE=$(printf '%s\n' "$VIH_FN" | grep -cE 'INNGEST_DURABLE: FAIL .*not active' || true)
VIH_SENTINEL=$(printf '%s\n' "$VIH_FN" | grep -cF -- '--postgres-max-open-conns' || true)
# Negative: the removed --redis-uri-absent FAIL branch must NOT reappear (it would
# be dead code — redis-uri is never on argv after #5560).
VIH_FAIL_NO_REDIS=$(printf '%s\n' "$VIH_FN" | grep -cE 'INNGEST_DURABLE: FAIL .*--redis-uri absent' || true)
TOTAL=$((TOTAL + 1))
if [[ "$VIH_ADVISORY" -ge 1 && "$VIH_FAIL_NOT_ACTIVE" -ge 1 && "$VIH_SENTINEL" -ge 1 && "$VIH_FAIL_NO_REDIS" -eq 0 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: verify_inngest_health emits degraded advisory + redis-not-active FAIL, keys on --postgres-max-open-conns sentinel, no dead --redis-uri-absent branch (#5547 AC5 / #5560)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC5 (advisory=$VIH_ADVISORY fail_not_active=$VIH_FAIL_NOT_ACTIVE sentinel=$VIH_SENTINEL dead_redis_branch=$VIH_FAIL_NO_REDIS; verify_inngest_health in ci-deploy.sh)"
fi

# AC5b — on a 0-exit bootstrap that left inngest on the SQLite-only ExecStart,
# the case "inngest") block writes final_write_state 0 "success_degraded_durability"
# (NOT plain "success") so /hooks/deploy-status .reason distinguishes a degraded
# deploy from a healthy durable one. Detection re-derives from the WRITTEN
# ExecStart via a case-local `inngest_exec_start=` (verify_inngest_health uses a
# `local exec_start=`, so this name is unique to the deploy arm).
G3_REASON=$(grep -cE 'final_write_state 0 "success_degraded_durability"' "$DEPLOY_SCRIPT" || true)
G3_DETECT=$(grep -cE 'inngest_exec_start=' "$DEPLOY_SCRIPT" || true)
TOTAL=$((TOTAL + 1))
if [[ "$G3_REASON" -ge 1 && "$G3_DETECT" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: case inngest writes success_degraded_durability on a degraded 0-exit deploy (#5547 AC5b)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC5b (degraded_reason=$G3_REASON detect=$G3_DETECT; file: ci-deploy.sh)"
fi

echo ""
echo "--- Cron drain (#5669 / ADR-078) ---"

# This section drives real (mocked) deploys whose runners return non-zero on the
# negative paths (L2) and uses grep|head extractions that SIGPIPE under
# `set -o pipefail`; turn errexit/pipefail off for the section (each test below
# reports PASS/FAIL explicitly, so errexit adds no safety here).
set +e +o pipefail

# T6 (AC4c memory-dwell): inside the swap success branch the canary is
# stopped+removed BEFORE the `while cron_in_flight` drain loop, so the up-to-70min
# drain wait does not hold the 1536m canary resident on the 8GB host. Source-order
# assertion scoped to the swap block (the stale-canary cleanup in the canary-start
# block far above is a false match otherwise).
TOTAL=$((TOTAL + 1))
# `f &&` guards the exit rule so the same literal in the top-of-file comment does
# not terminate awk before the swap section begins.
SWAP_BLOCK=$(awk '/SUCCESS: swap canary to production/{f=1} f{print} f && /docker stop --time=12 soleur-web-platform/{exit}' "$DEPLOY_SCRIPT")
T6_CANARY=$(printf '%s\n' "$SWAP_BLOCK" | grep -nE 'docker stop soleur-web-platform-canary' | head -1 | cut -d: -f1)
T6_DRAIN=$(printf '%s\n' "$SWAP_BLOCK" | grep -nE 'while cron_in_flight' | head -1 | cut -d: -f1)
if [[ -n "$T6_CANARY" && -n "$T6_DRAIN" && "$T6_CANARY" -lt "$T6_DRAIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T6 canary torn down before the drain loop in the swap branch (memory-dwell fix)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T6 canary-before-drain ordering (canary=$T6_CANARY drain=$T6_DRAIN; file: ci-deploy.sh)"
fi

# T7 (AC4d probe own timeout): cron_in_flight wraps the pool-agnostic detection
# probe in its own `timeout "${CRON_DRAIN_PROBE_TIMEOUT}"` so a hung docker exec
# cannot extend the drain past the wall-clock (G5).
TOTAL=$((TOTAL + 1))
T7_FN=$(awk '/^cron_in_flight\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$DEPLOY_SCRIPT")
if printf '%s' "$T7_FN" | grep -qF 'timeout "${CRON_DRAIN_PROBE_TIMEOUT}"' \
   && printf '%s' "$T7_FN" | grep -qF 'pgrep -f "claude"'; then
  PASS=$((PASS + 1))
  echo "  PASS: T7 cron_in_flight is pool-agnostic (pgrep -f claude) with its own probe timeout"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T7 cron_in_flight probe shape (file: ci-deploy.sh)"
fi

# T9 (AC1): CRON_DRAIN_TIMEOUT default ≥ MAX per-function maxTurnDurationMs, so
# the longest cron (cron-growth-audit, 70min) survives the drain rather than being
# killed by the timeout. Re-derives the max from the actual function source — a
# future cron raising its ceiling above the drain default fails this gate.
TOTAL=$((TOTAL + 1))
FN_DIR="$(dirname "$DEPLOY_SCRIPT")/../server/inngest/functions"
T9_MAX_MIN=$(grep -rhoE 'MAX_TURN_DURATION_MS = [0-9]+ \* 60 \* 1000' "$FN_DIR" 2>/dev/null \
  | grep -oE '= [0-9]+ \*' | grep -oE '[0-9]+' | sort -n | tail -1)
T9_DRAIN_DEFAULT=$(grep -oE 'CRON_DRAIN_TIMEOUT:-[0-9]+' "$DEPLOY_SCRIPT" | grep -oE '[0-9]+$')
if [[ -n "$T9_MAX_MIN" && -n "$T9_DRAIN_DEFAULT" && "$T9_DRAIN_DEFAULT" -ge $(( T9_MAX_MIN * 60 )) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T9 CRON_DRAIN_TIMEOUT default ${T9_DRAIN_DEFAULT}s ≥ max per-function ceiling ${T9_MAX_MIN}min ($(( T9_MAX_MIN * 60 ))s)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T9 drain default ${T9_DRAIN_DEFAULT}s < max ceiling ${T9_MAX_MIN}min (raise CRON_DRAIN_TIMEOUT)"
fi

# T-PARITY (#5669 cross-language drift guard): the lease basename is replicated in
# bash (ci-deploy.sh CRON_DEPLOY_LEASE_FILE default path) AND TypeScript
# (_cron-shared.ts DEPLOY_LEASE_BASENAME). The host writes the file and the
# container substrate reads it; a silent divergence reopens the start-race while
# both sides' own tests stay green. Assert they agree.
TOTAL=$((TOTAL + 1))
PARITY_SHARED="$(dirname "$DEPLOY_SCRIPT")/../server/inngest/functions/_cron-shared.ts"
BASH_LEASE_BASENAME=$(grep -oE 'CRON_DEPLOY_LEASE_FILE:-[^}]+' "$DEPLOY_SCRIPT" | sed -E 's#.*/##')
TS_LEASE_BASENAME=$(grep -oE 'DEPLOY_LEASE_BASENAME = "[^"]+"' "$PARITY_SHARED" | sed -E 's/.*"([^"]+)"/\1/')
if [[ -n "$BASH_LEASE_BASENAME" && "$BASH_LEASE_BASENAME" == "$TS_LEASE_BASENAME" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-PARITY lease basename agrees across bash + TS ('$BASH_LEASE_BASENAME')"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-PARITY lease basename drift (ci-deploy.sh='$BASH_LEASE_BASENAME' vs _cron-shared.ts='$TS_LEASE_BASENAME')"
fi

# T-WALLCLOCK (pattern review): the wrapper / IN_FLIGHT_CEILING_S wall-clock must
# stay >= CRON_DRAIN_TIMEOUT + overhead, else the wrapper SIGKILLs ci-deploy.sh
# mid-drain (killing the very cron the drain protects). T9 ties CRON_DRAIN_TIMEOUT
# UP to the cron ceiling; this ties it UNDER the wall-clock — so a future ceiling
# raise that lifts the drain default can't silently exceed the wrapper budget while
# T6/T9/wrapper-Test-6 all stay green.
TOTAL=$((TOTAL + 1))
WC_YML="$(dirname "$DEPLOY_SCRIPT")/../../../.github/workflows/web-platform-release.yml"
WC_CEILING=$(grep -oE 'IN_FLIGHT_CEILING_S:[[:space:]]*[0-9]+' "$WC_YML" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
WC_DRAIN=$(grep -oE 'CRON_DRAIN_TIMEOUT:-[0-9]+' "$DEPLOY_SCRIPT" | grep -oE '[0-9]+$')
WC_MARGIN=300
if [[ -n "$WC_CEILING" && -n "$WC_DRAIN" && $(( WC_CEILING - WC_DRAIN )) -ge "$WC_MARGIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-WALLCLOCK IN_FLIGHT_CEILING_S ${WC_CEILING}s − CRON_DRAIN_TIMEOUT ${WC_DRAIN}s ≥ ${WC_MARGIN}s overhead"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-WALLCLOCK wall-clock ${WC_CEILING}s − drain ${WC_DRAIN}s < ${WC_MARGIN}s margin (wrapper would SIGKILL mid-drain)"
fi

# T-LEASE-ORDER (test-design review): the lease MUST be written BEFORE the drain
# loop and the prod stop — that ordering is what closes the start-race (a new run
# launching claude into the about-to-die container while the loop drains). Source
# order: lease write < `while cron_in_flight` < `docker stop --time=12`.
TOTAL=$((TOTAL + 1))
LO_BLOCK=$(awk '/SUCCESS: swap canary to production/{f=1} f{print} f && /docker stop --time=12 soleur-web-platform/{exit}' "$DEPLOY_SCRIPT")
LO_LEASE=$(printf '%s\n' "$LO_BLOCK" | grep -nE ': > "\$CRON_DEPLOY_LEASE_FILE"' | head -1 | cut -d: -f1)
LO_DRAIN=$(printf '%s\n' "$LO_BLOCK" | grep -nE 'while cron_in_flight' | head -1 | cut -d: -f1)
if [[ -n "$LO_LEASE" && -n "$LO_DRAIN" && "$LO_LEASE" -lt "$LO_DRAIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-LEASE-ORDER lease written (L$LO_LEASE) before drain loop (L$LO_DRAIN) — start-race closed"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-LEASE-ORDER lease-write/drain ordering (lease=$LO_LEASE drain=$LO_DRAIN)"
fi

# T1 (AC1): with a cron in flight for N polls then gone, the drain loops until the
# probe goes false (counter drains to 0), does NOT time out, and clears the lease
# on success.
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
echo 3 > "$DTMP/inflight"
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  MOCK_CRON_INFLIGHT_FILE="$DTMP/inflight" CRON_DRAIN_POLL=0
T1_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T1_RC=0 || T1_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE MOCK_CRON_INFLIGHT_FILE CRON_DRAIN_POLL
T1_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
T1_LEFT=$(cat "$DTMP/inflight" 2>/dev/null || echo "MISSING")
T1_LEASE=$([[ -f "$DTMP/lease" ]] && echo yes || echo no)
if [[ "$T1_RC" -eq 0 && "$T1_TIMED" == "false" && "$T1_LEFT" == "0" && "$T1_LEASE" == "no" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T1 drain waited for in-flight cron (counter→0), no timeout, lease cleared on success"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T1 (rc=$T1_RC timed_out=$T1_TIMED inflight_left=$T1_LEFT lease_present=$T1_LEASE)"
fi
rm -rf "$DTMP"

# T3 (AC3 no-cron fast path): no claude in flight → zero-wait drain, immediate
# stop, no timeout, lease cleared.
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" CRON_DRAIN_POLL=0
T3_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T3_RC=0 || T3_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE CRON_DRAIN_POLL
T3_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
T3_WAIT=$(jq -r '.cron_drain_wait_secs' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
# `^[0-9]+$` already excludes the never-reached -1 sentinel (no minus sign); the
# `-le 2` upper bound pins the no-cron FAST path (a single false probe, 0–1s of
# wall-clock tick) and excludes any real multi-second drain — without asserting a
# brittle exact 0 (the single docker-exec probe can cross a 1s boundary).
if [[ "$T3_RC" -eq 0 && "$T3_TIMED" == "false" && "$T3_WAIT" =~ ^[0-9]+$ && "$T3_WAIT" -le 2 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T3 no-cron deploy: zero-wait drain (${T3_WAIT}s), no timeout"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T3 (rc=$T3_RC timed_out=$T3_TIMED wait=$T3_WAIT)"
fi
rm -rf "$DTMP"

# T2 (AC2 bounded, not infinite): a cron that never finishes is killed once the
# drain passes CRON_DRAIN_TIMEOUT — the state records cron_drain_timed_out=true and
# the deploy still proceeds (a drain timeout must NOT fail the deploy under set -e).
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
echo 99 > "$DTMP/inflight"
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  MOCK_CRON_INFLIGHT_FILE="$DTMP/inflight" CRON_DRAIN_TIMEOUT=0 CRON_DRAIN_POLL=0
T2_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T2_RC=0 || T2_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE MOCK_CRON_INFLIGHT_FILE CRON_DRAIN_TIMEOUT CRON_DRAIN_POLL
T2_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
if [[ "$T2_RC" -eq 0 && "$T2_TIMED" == "true" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T2 drain timeout sets cron_drain_timed_out=true and does not fail the deploy"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T2 (rc=$T2_RC timed_out=$T2_TIMED)"
fi
rm -rf "$DTMP"

# L2 (lease lifecycle): on a FAILED swap (new prod run fails), the lease is NOT
# cleared — it is left for the substrate's TTL fail-open backstop (CTO guardrail
# 2). Proves the lease was written (exists) and that clear is gated on swap
# success (T1 proves the success-clear).
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  CRON_DRAIN_POLL=0 MOCK_DOCKER_RUN_FAIL_PROD=1
L2_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && L2_RC=0 || L2_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE CRON_DRAIN_POLL MOCK_DOCKER_RUN_FAIL_PROD
L2_LEASE=$([[ -f "$DTMP/lease" ]] && echo yes || echo no)
if [[ "$L2_RC" -ne 0 && "$L2_LEASE" == "yes" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: L2 lease written + retained on swap failure (TTL backstop, not cleared)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: L2 (rc=$L2_RC lease_present=$L2_LEASE; expected nonzero rc + lease retained)"
fi
rm -rf "$DTMP"

# Restore strict mode for the summary/exit.
set -e -o pipefail

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
