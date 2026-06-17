#!/usr/bin/env bash
set -uo pipefail

# Tests for sentry-issue.sh (#5495). Mirrors container-restart-monitor.test.sh:
# PATH-prepended mock `curl` logging every invocation to $mock_dir/curl_args,
# subshell isolation, env toggles. Mocks `curl` only; the script reads its token
# from env (doppler-run injection) so no `doppler` call is mocked.
#
# Security invariants under test (deepen-plan security-sentinel P1):
#   - GET-only: every curl invocation is -X GET, never -d/--data/-X POST|PUT|DELETE
#   - URL allowlist + org-subdomain host pinning (jikigai-eu.sentry.io)
#   - issue-id charset validation (^[A-Za-z0-9_-]+$) — hostile ids rejected, no curl
#   - token preference RO→RW (warns on RW), absent → non-zero + mint hint
#   - script's own stderr never echoes the token value
#   - source contains no `set -x`
#   - 403 mapped to "token lacks event:read"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sentry-issue.sh"

PASS=0; FAIL=0; TOTAL=0
RO_TOKEN="ro_fake_TESTTOKEN_3f9a"   # distinctive — used in stderr-no-echo assertion
RW_TOKEN="rw_fake_TESTTOKEN_b2c7"

# Run the SUT under a mock curl. Captures stdout, stderr, and curl_args separately.
# Env toggles: MOCK_HTTP_CODE (default 200), MOCK_BODY, USE_RW_ONLY=1, NO_TOKEN=1.
run_sut() {
  local mock_dir; mock_dir="$(mktemp -d)"
  cat > "$mock_dir/curl" <<MOCK
#!/bin/bash
echo "\$*" >> "$mock_dir/curl_args"
echo "\${MOCK_BODY:-{\\"id\\":\\"12345\\",\\"title\\":\\"boom\\"}}"
echo "\${MOCK_HTTP_CODE:-200}"
exit 0
MOCK
  chmod +x "$mock_dir/curl"

  ( export PATH="$mock_dir:$PATH"
    export SENTRY_API_HOST="jikigai-eu.sentry.io"
    export SENTRY_ORG="jikigai-eu"
    if [[ "${NO_TOKEN:-}" != "1" ]]; then
      [[ "${USE_RW_ONLY:-}" == "1" ]] || export SENTRY_ISSUE_RO_TOKEN="$RO_TOKEN"
      export SENTRY_ISSUE_RW_TOKEN="$RW_TOKEN"
    fi
    bash "$SUT" "$@" >"$mock_dir/out" 2>"$mock_dir/err"
    echo "rc=$?" > "$mock_dir/rc"
  )
  LAST_OUT="$(cat "$mock_dir/out" 2>/dev/null)"
  LAST_ERR="$(cat "$mock_dir/err" 2>/dev/null)"
  LAST_CURL="$(cat "$mock_dir/curl_args" 2>/dev/null || true)"
  LAST_RC="$(sed 's/rc=//' "$mock_dir/rc" 2>/dev/null || echo 1)"
  rm -rf "$mock_dir"
}

check() { # desc, condition (0=pass)
  TOTAL=$((TOTAL+1))
  if [[ "$2" == "0" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi
}

# 1. issue detail → org-scoped issues URL, GET, host-pinned
run_sut 12345
check "issue-detail returns body" "$([[ "$LAST_OUT" == *'"id":"12345"'* ]] && echo 0 || echo 1)"
check "issue-detail GET org-scoped URL" "$([[ "$LAST_CURL" == *'-X GET'* && "$LAST_CURL" == *'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/12345/'* ]] && echo 0 || echo 1)"

# 2. latest-event → org-scoped events/latest URL
run_sut --latest-event 12345
check "latest-event org-scoped URL" "$([[ "$LAST_CURL" == *'/organizations/jikigai-eu/issues/12345/events/latest/'* ]] && echo 0 || echo 1)"

# 3. GET-only invariant: no write verb / body across all invocations
run_sut 12345
check "no -d/--data" "$([[ "$LAST_CURL" != *' -d '* && "$LAST_CURL" != *'--data'* ]] && echo 0 || echo 1)"
check "no -X POST/PUT/DELETE" "$([[ "$LAST_CURL" != *'-X POST'* && "$LAST_CURL" != *'-X PUT'* && "$LAST_CURL" != *'-X DELETE'* ]] && echo 0 || echo 1)"

# 4. hostile issue-id rejected, no curl fired
run_sut "../../etc/passwd"
check "hostile id non-zero exit" "$([[ "$LAST_RC" != "0" ]] && echo 0 || echo 1)"
check "hostile id fired no curl" "$([[ -z "$LAST_CURL" ]] && echo 0 || echo 1)"
run_sut "12345/events/latest"
check "slashed id non-zero exit" "$([[ "$LAST_RC" != "0" ]] && echo 0 || echo 1)"

# 5. token preference: RW-only warns but works
USE_RW_ONLY=1 run_sut 12345
check "RW-only works" "$([[ "$LAST_RC" == "0" ]] && echo 0 || echo 1)"
check "RW-only warns" "$([[ "$LAST_ERR" == *'RO_TOKEN'* || "$LAST_ERR" == *'RW token'* ]] && echo 0 || echo 1)"

# 6. no token → non-zero + mint hint
NO_TOKEN=1 run_sut 12345
check "no-token non-zero" "$([[ "$LAST_RC" != "0" ]] && echo 0 || echo 1)"
check "no-token mint hint" "$([[ "$LAST_ERR" == *'SENTRY_ISSUE_RO_TOKEN'* ]] && echo 0 || echo 1)"

# 7. 403 mapped to event:read message
MOCK_HTTP_CODE=403 run_sut 12345
check "403 maps to event:read" "$([[ "$LAST_ERR" == *'event:read'* ]] && echo 0 || echo 1)"
check "403 non-zero exit" "$([[ "$LAST_RC" != "0" ]] && echo 0 || echo 1)"

# 8. token never echoed to the script's own stderr (on a normal + error run)
MOCK_HTTP_CODE=500 run_sut 12345
check "stderr never echoes token" "$([[ "$LAST_ERR" != *"$RO_TOKEN"* && "$LAST_ERR" != *"$RW_TOKEN"* ]] && echo 0 || echo 1)"

# 9. source never ACTIVATES `set -x` (anchored to line start so the doc comment
#    that mentions `set -x` is not a false positive).
check "no set -x directive in source" "$(grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*x' "$SUT" && echo 1 || echo 0)"

echo "----"
echo "sentry-issue.sh: $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" == "0" ]]
