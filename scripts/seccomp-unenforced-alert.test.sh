#!/usr/bin/env bash
# Tests for seccomp-unenforced-alert.sh (#6512, ADR-079 Fix 2a).
# Verifies the two-surface actionable alert: a deduped plain-language GitHub issue
# (create-when-absent, comment-when-present) + a Sentry op:seccomp-remediation-failed
# event, and the FAIL-OPEN contract (a telemetry failure never aborts the caller).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/seccomp-unenforced-alert.sh"
PASS=0; FAIL=0

mk_mocks() {
  local dir="$1"
  cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'GH:%s\n' "$*" >> "$MOCK_GH_FILE"
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  [[ "${MOCK_GH_LIST_FAIL:-}" == "1" ]] && exit 3
  [[ -n "${MOCK_EXISTING_ISSUE:-}" ]] && printf '%s\n' "$MOCK_EXISTING_ISSUE"
  exit 0
fi
[[ "${MOCK_GH_WRITE_FAIL:-}" == "1" ]] && exit 4
exit 0
EOF
  chmod +x "$dir/gh"
  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
ARGS=("$@"); URL=""; PAYLOAD=""
for ((i=0; i<${#ARGS[@]}; i++)); do
  [[ "${ARGS[$i]}" == https://* ]] && URL="${ARGS[$i]}"
  [[ "${ARGS[$i]}" == "-d" ]] && PAYLOAD="${ARGS[$((i+1))]}"
done
[[ "$URL" == *"/store/"* ]] && printf 'CURL_STORE:%s\n' "$PAYLOAD" >> "$MOCK_CURL_FILE"
exit 0
EOF
  chmod +x "$dir/curl"
}

run_alert() {
  # run_alert <detail> ; caller pre-exports MOCK_* + SENTRY_* + arm vars
  local detail="$1"
  ( set -euo pipefail   # mimic the workflow step's strict mode — the fail-open contract
    source "$SCRIPT"     # must hold under set -e
    seccomp_unenforced_alert "$detail"
    echo "RET:$?" )
}

# --- (1) no open issue + Sentry creds present → CREATE issue + Sentry POST ---
T=$(mktemp -d)
export MOCK_GH_FILE="$T/gh.txt"; : > "$MOCK_GH_FILE"
export MOCK_CURL_FILE="$T/curl.txt"; : > "$MOCK_CURL_FILE"
export SENTRY_INGEST_DOMAIN="sentry.example" SENTRY_PROJECT_ID="42" SENTRY_PUBLIC_KEY="pk"
export SECCOMP_ALERT_RUN_URL="https://ci/run/1" SECCOMP_ALERT_SHA="abc123"
unset MOCK_EXISTING_ISSUE
mk_mocks "$T"
OUT="$(PATH="$T:$PATH" run_alert "image_pull_failed on v0.214.7")"
if grep -q 'GH:issue create' "$MOCK_GH_FILE" \
   && grep -q -- '--label ci/seccomp-unenforced' "$MOCK_GH_FILE" \
   && ! grep -q 'GH:issue comment' "$MOCK_GH_FILE" \
   && grep -q 'seccomp-remediation-failed' "$MOCK_CURL_FILE" \
   && grep -q 'CURL_STORE' "$MOCK_CURL_FILE" \
   && grep -q 'RET:0' <<<"$OUT"; then
  PASS=$((PASS+1)); echo "  PASS: no open issue → create + Sentry op:seccomp-remediation-failed, ret 0"
else
  FAIL=$((FAIL+1)); echo "  FAIL: (1) create+sentry"; echo "    gh:"; sed 's/^/      /' "$MOCK_GH_FILE"; echo "    curl:"; sed 's/^/      /' "$MOCK_CURL_FILE"; echo "    out=$OUT"
fi
unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY MOCK_EXISTING_ISSUE
rm -rf "$T"

# --- (2) an open issue exists → COMMENT, never CREATE (dedupe) ---
T=$(mktemp -d)
export MOCK_GH_FILE="$T/gh.txt"; : > "$MOCK_GH_FILE"
export MOCK_CURL_FILE="$T/curl.txt"; : > "$MOCK_CURL_FILE"
export MOCK_EXISTING_ISSUE="777"
mk_mocks "$T"
OUT="$(PATH="$T:$PATH" run_alert "recurrence")"
if grep -q 'GH:issue comment 777' "$MOCK_GH_FILE" \
   && ! grep -q 'GH:issue create' "$MOCK_GH_FILE" \
   && grep -q 'RET:0' <<<"$OUT"; then
  PASS=$((PASS+1)); echo "  PASS: open issue present → comment on #777, no duplicate create (dedupe)"
else
  FAIL=$((FAIL+1)); echo "  FAIL: (2) dedupe-comment"; echo "    gh:"; sed 's/^/      /' "$MOCK_GH_FILE"; echo "    out=$OUT"
fi
unset MOCK_EXISTING_ISSUE
rm -rf "$T"

# --- (3) Sentry creds absent → NO curl POST, but the GitHub issue still files (fail-open, independent surfaces) ---
T=$(mktemp -d)
export MOCK_GH_FILE="$T/gh.txt"; : > "$MOCK_GH_FILE"
export MOCK_CURL_FILE="$T/curl.txt"; : > "$MOCK_CURL_FILE"
unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY MOCK_EXISTING_ISSUE
mk_mocks "$T"
OUT="$(PATH="$T:$PATH" run_alert "no sentry creds")"
if grep -q 'GH:issue create' "$MOCK_GH_FILE" \
   && ! grep -q 'CURL_STORE' "$MOCK_CURL_FILE" \
   && grep -q 'RET:0' <<<"$OUT"; then
  PASS=$((PASS+1)); echo "  PASS: no Sentry creds → issue still filed, no Sentry POST, ret 0"
else
  FAIL=$((FAIL+1)); echo "  FAIL: (3) sentry-absent-failopen"; echo "    gh:"; sed 's/^/      /' "$MOCK_GH_FILE"; echo "    curl:"; sed 's/^/      /' "$MOCK_CURL_FILE"; echo "    out=$OUT"
fi
rm -rf "$T"

# --- (4) gh write fails under set -e → the function STILL returns 0 (fail-open never masks the caller's exit 1) ---
T=$(mktemp -d)
export MOCK_GH_FILE="$T/gh.txt"; : > "$MOCK_GH_FILE"
export MOCK_CURL_FILE="$T/curl.txt"; : > "$MOCK_CURL_FILE"
export MOCK_GH_WRITE_FAIL=1
unset MOCK_EXISTING_ISSUE
mk_mocks "$T"
OUT="$(PATH="$T:$PATH" run_alert "gh down")"
if grep -q 'RET:0' <<<"$OUT"; then
  PASS=$((PASS+1)); echo "  PASS: gh write failure under set -e → fail-open (ret 0), caller's exit 1 not masked"
else
  FAIL=$((FAIL+1)); echo "  FAIL: (4) failopen-on-gh-error"; echo "    out=$OUT"
fi
unset MOCK_GH_WRITE_FAIL
rm -rf "$T"

echo ""
echo "=== seccomp-unenforced-alert: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
