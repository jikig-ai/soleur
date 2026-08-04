#!/usr/bin/env bash
# Tests for infra-config-red-alert.sh (#7220).
#
# This emitter exists because reusing `seccomp_unenforced_alert`'s TRANSPORT reused its
# IDENTITY: an infra-config delivery failure filed an issue TITLED "Security profile (seccomp)
# not enforced", deduped against the seccomp label (so an open seccomp incident swallowed it),
# and paged the seccomp Sentry rule. So the properties under test are mostly about IDENTITY and
# about the two-state split — not about "does it call gh".
#
# The reachable/unreachable split is the second P1: the alert fires on ANY gate failure, and on
# 000/502/503 the listener is DOWN, where `-replace` on the handler bootstrap IS the documented
# route back. Emitting the reachable text there told the operator not to pull the exact lever the
# gate had just prescribed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/infra-config-red-alert.sh"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
has()  { grep -qF "$2" "$1"; }

mk_mocks() {
  local dir="$1"
  cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'GH:%s\n' "$*" >> "$MOCK_GH_FILE"
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  [[ -n "${MOCK_EXISTING_ISSUE:-}" ]] && printf '%s\n' "$MOCK_EXISTING_ISSUE"
  exit 0
fi
[[ "${MOCK_GH_WRITE_FAIL:-}" == "1" ]] && exit 4
exit 0
EOF
  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  [[ "$a" == https://* ]] && printf 'CURL_URL:%s\n' "$a" >> "$MOCK_CURL_FILE"
  case "$a" in '{'*) printf 'CURL_BODY:%s\n' "$a" >> "$MOCK_CURL_FILE" ;; esac
done
[[ "${MOCK_CURL_FAIL:-}" == "1" ]] && exit 7
exit 0
EOF
  chmod +x "$dir/gh" "$dir/curl"
}

run_alert() {  # <detail> <reach>
  T=$(mktemp -d); mk_mocks "$T"
  export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"
  : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
  PATH="$T:$PATH" \
  SENTRY_INGEST_DOMAIN=sentry.example SENTRY_PROJECT_ID=1 SENTRY_PUBLIC_KEY=k \
  INFRA_CONFIG_ALERT_RUN_URL=https://example/run INFRA_CONFIG_ALERT_SHA=abc123 \
    bash "$SCRIPT" "$1" "$2" >/dev/null 2>&1
  RC=$?
}

echo "infra-config-red-alert.test.sh"

# --- IDENTITY: the whole reason this file exists ------------------------------------------
run_alert "delivery channel is RED" reachable
if has "$MOCK_GH_FILE" 'ci/infra-config-red'; then
  ok "files under its OWN label, not ci/seccomp-unenforced"
else bad "did not use the ci/infra-config-red label"; fi
if grep -qF 'ci/seccomp-unenforced' "$MOCK_GH_FILE"; then
  bad "LEAKED the seccomp label — an open seccomp incident would swallow this alert"
else ok "never touches the seccomp label (no dedupe collision)"; fi
if grep -qiF 'seccomp' "$MOCK_GH_FILE"; then
  bad "issue text mentions seccomp — the fabricated-security-claim defect"
else ok "issue text makes no security claim"; fi
# jq -n pretty-prints, so the payload carries `"feature": "infra-config"` WITH a space —
# assert the rendered shape, whitespace-tolerant, rather than a compact form the code never emits.
if grep -qE '"feature":[[:space:]]*"infra-config"' "$MOCK_CURL_FILE"; then
  ok "Sentry tags feature:infra-config, not agent-sandbox"
else bad "Sentry payload did not carry feature:infra-config"; fi
if grep -qE '"feature":[[:space:]]*"agent-sandbox"' "$MOCK_CURL_FILE"; then
  bad "Sentry payload still tags agent-sandbox — would page the seccomp rule"
else ok "Sentry never tags agent-sandbox (no rule misroute)"; fi

# --- THE TWO-STATE SPLIT: reachable vs unreachable must NOT say the same thing ------------
run_alert "listener did not answer" unreachable
UNREACH_GH=$(cat "$MOCK_GH_FILE"); UNREACH_CURL=$(cat "$MOCK_CURL_FILE")
run_alert "died at a known line" reachable
REACH_GH=$(cat "$MOCK_GH_FILE")

if [[ "$UNREACH_GH" != "$REACH_GH" ]]; then
  ok "the two states produce DIFFERENT operator-facing output"
else bad "reachable and unreachable emit identical text — the contradiction defect"; fi
if grep -qF 'is not responding' <<<"$UNREACH_GH"; then
  ok "unreachable title says the channel is not responding"
else bad "unreachable state did not use its own title"; fi
# The load-bearing one: on 000/502/503 the gate PRESCRIBES -replace, so the alert must not
# assert app health or forbid the lever.
if grep -qiF 'app health is unaffected' <<<"$UNREACH_GH"; then
  bad "unreachable body asserts app health — it cannot know that when the listener is down"
else ok "unreachable body makes no app-health claim"; fi
if grep -qF 'Do NOT run' <<<"$UNREACH_GH"; then
  bad "unreachable body forbids -replace, contradicting the gate's own recovery guidance"
else ok "unreachable body does not contradict the gate on the -replace lever"; fi
if printf '%s' "$UNREACH_CURL" | grep -qF 'infra-config-listener-down'; then
  ok "unreachable Sentry op is distinguishable from the gate-red op"
else bad "unreachable state reused the gate-red Sentry op"; fi

# --- DEDUPE: comment on an open issue rather than filing a second -------------------------
T=$(mktemp -d); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_EXISTING_ISSUE=4242 bash "$SCRIPT" "recurred" reachable >/dev/null 2>&1
if has "$MOCK_GH_FILE" 'issue comment 4242' && ! has "$MOCK_GH_FILE" 'issue create'; then
  ok "comments on the open issue instead of filing a duplicate"
else bad "did not dedupe onto the existing open issue"; fi

# --- FAIL-OPEN: this runs on the failure path and must never abort the caller -------------
T=$(mktemp -d); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_GH_WRITE_FAIL=1 MOCK_CURL_FAIL=1 bash "$SCRIPT" "everything broken" reachable >/dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
  ok "returns 0 even when BOTH gh and curl fail (fail-open contract)"
else bad "non-zero exit on telemetry failure — would mask the real failure it reports"; fi

# Sentry is skipped, not fatal, when its env is absent.
T=$(mktemp -d); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
env -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY \
  PATH="$T:$PATH" bash "$SCRIPT" "no sentry env" reachable >/dev/null 2>&1
rc_nosentry=$?
if [[ "$rc_nosentry" -eq 0 ]] && [[ ! -s "$MOCK_CURL_FILE" ]] && has "$MOCK_GH_FILE" 'issue'; then
  ok "skips Sentry when its env is unset and still files the issue"
else bad "unset Sentry env broke the GitHub surface (rc=$rc_nosentry)"; fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
