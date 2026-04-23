#!/usr/bin/env bash
set -euo pipefail

# Tests for audit-bwrap-uid.sh.
# Mocks docker; drives behavior via env vars to exercise each FAIL branch
# in check 2 (#2837) plus the unchanged check 1 / apparmor paths.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-bwrap-uid.sh"
FIXTURE_DIR="$SCRIPT_DIR/test-fixtures/audit-bwrap"

PASS=0
FAIL=0
TOTAL=0

# Hardened PATH — excludes ~/.local/bin so missing mocks fail loudly.
readonly TEST_PATH_BASE="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Mock factory -----------------------------------------------------------
# MOCK_DOCKER_MODE driven. Fixtures are files on disk:
#   DOCKER_INSPECT_FIXTURE - path to a file whose contents are returned
#                            verbatim for any `docker inspect` call.
#   DOCKER_EXEC_EXIT       - exit code for `docker exec` calls (default 0).
#   DOCKER_EXEC_STDOUT     - optional stdout for `docker exec` (default "0").

create_docker_mock() {
  cat > "$1/docker" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  inspect)
    if [[ -n "${DOCKER_INSPECT_FIXTURE:-}" && -r "${DOCKER_INSPECT_FIXTURE}" ]]; then
      cat "$DOCKER_INSPECT_FIXTURE"
    else
      exit 1
    fi
    ;;
  exec)
    echo "${DOCKER_EXEC_STDOUT:-0}"
    exit "${DOCKER_EXEC_EXIT:-0}"
    ;;
  *)
    echo "unexpected docker arg: $*" >&2
    exit 99
    ;;
esac
MOCK
  chmod +x "$1/docker"
}

echo "=== audit-bwrap-uid.sh tests ==="
echo ""

# --- Test runners -----------------------------------------------------------

run_case() {
  # Args: description, fixture-name, expected-exit, expected-stdstring, [extra-env...]
  local description="$1"
  local fixture="$2"
  local expected_exit="$3"
  local expected_string="$4"
  shift 4

  TOTAL=$((TOTAL + 1))
  local mock_dir
  mock_dir=$(mktemp -d)
  create_docker_mock "$mock_dir"

  local output actual_exit
  output=$(
    export PATH="$mock_dir:$TEST_PATH_BASE"
    export CONTAINER=test-container
    export EXPECTED_SECCOMP_PATH="$FIXTURE_DIR/valid-seccomp.json"
    export DOCKER_INSPECT_FIXTURE="$FIXTURE_DIR/$fixture"
    export DOCKER_EXEC_EXIT=0
    for kv in "$@"; do
      export "${kv?}"
    done
    bash "$AUDIT_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]] && printf '%s\n' "$output" | grep -qF "$expected_string"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, expected=$expected_exit)"
    echo "        expected substring: $expected_string"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

# --- Cases ------------------------------------------------------------------

echo "--- check 2 (#2837): seccomp hash-compare ---"

# PASS: inlined seccomp (different key order) matches on-host file after jq -cS
run_case "valid deploy — inlined seccomp matches on-host (jq-normalized)" \
  "inspect-pass.txt" 0 "seccomp matches on-host profile (sha256="

# FAIL: inlined JSON differs semantically
run_case "seccomp drift — inlined defaultAction differs" \
  "inspect-drift.txt" 1 "seccomp drift"

# FAIL: no seccomp= entry at all
run_case "no seccomp= entry — custom profile not attached" \
  "inspect-no-seccomp.txt" 1 "no seccomp= entry"

# FAIL: Docker didn't resolve --security-opt path to inlined JSON
run_case "literal path — Docker did not resolve seccomp flag" \
  "inspect-literal-path.txt" 1 "literal path, not inlined JSON"

# FAIL: on-host file missing
run_case "on-host seccomp file missing — deploy state incoherent" \
  "inspect-pass.txt" 1 "On-host seccomp profile missing" \
  "EXPECTED_SECCOMP_PATH=/nonexistent/path/soleur-bwrap.json"

# FAIL: on-host file exists but isn't valid JSON (regression guard — without
# `|| true` on the FILE_HASH pipeline, strict-mode would abort the script
# before this branch could emit).
_BAD_JSON_FIXTURE=$(mktemp --suffix=.json)
printf 'not valid json\n' > "$_BAD_JSON_FIXTURE"
run_case "on-host seccomp file malformed — explicit FAIL (not strict-mode abort)" \
  "inspect-pass.txt" 1 "is not valid JSON" \
  "EXPECTED_SECCOMP_PATH=$_BAD_JSON_FIXTURE"
rm -f "$_BAD_JSON_FIXTURE"

echo ""
echo "--- check 2 regression guard: apparmor path unchanged ---"

run_case "apparmor dropped — audit FAILs" \
  "inspect-no-apparmor.txt" 1 "missing apparmor=soleur-bwrap"

echo ""
echo "--- check 1 regression guard: bwrap exec failure ---"

run_case "docker exec bwrap fails — CLONE_NEWUSER rejected" \
  "inspect-pass.txt" 1 "CLONE_NEWUSER rejected" \
  "DOCKER_EXEC_EXIT=1"

# --- Results ----------------------------------------------------------------

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ "$FAIL" -eq 0 ]]
