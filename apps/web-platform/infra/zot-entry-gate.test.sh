#!/usr/bin/env bash
set -uo pipefail

# Tests for zot-entry-gate.sh (#6122/ADR-096): the pre-flip go/no-go gate that asserts both
# platform images resolve in zot. Exit contract: 0=PASS, 1=BLOCK (tag missing), 2=TRANSIENT.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/zot-entry-gate.sh"
PASS=0; FAIL=0

# Mock curl: distinguishes the /v2/ reachability probe from a /manifests/ HEAD, and honors
# MOCK_ZOT_DOWN / MOCK_WEB_MISSING / MOCK_INNGEST_MISSING to drive the branches.
make_mock_curl() {
  cat > "$1/curl" <<'MOCK'
#!/bin/bash
url=""; want_code=0; cfg=0
[[ -n "${MOCK_CURL_LOG:-}" ]] && printf '%s\n' "$*" >> "$MOCK_CURL_LOG"
for a in "$@"; do
  case "$a" in
    http*) url="$a" ;;
    -w) want_code=1 ;;  # crude but the gate always pairs -w with %{http_code}
    --config) cfg=1 ;;
  esac
done
# The credential rides stdin (`--config -`), not argv: drain it (the writer is a process substitution)
# into MOCK_CURL_STDIN so the rows can assert its exact content. Only read when `--config -` was passed.
if [[ "$cfg" == 1 && -n "${MOCK_CURL_STDIN:-}" ]]; then cat >> "$MOCK_CURL_STDIN"; elif [[ "$cfg" == 1 ]]; then cat >/dev/null; fi
# Reachability probe: the bare /v2/ endpoint (no -w in the gate's probe call).
if [[ "$url" == */v2/ ]]; then
  [[ "${MOCK_ZOT_DOWN:-}" == "1" ]] && exit 1
  exit 0
fi
# Manifest HEAD: gate passes -w '%{http_code}'.
if [[ "$url" == *"/manifests/"* ]]; then
  if [[ "$url" == *"soleur-web-platform/manifests/"* && "${MOCK_WEB_MISSING:-}" == "1" ]]; then echo "404"; exit 0; fi
  if [[ "$url" == *"soleur-inngest-bootstrap/manifests/"* && "${MOCK_INNGEST_MISSING:-}" == "1" ]]; then echo "404"; exit 0; fi
  echo "200"; exit 0
fi
[[ "$want_code" == "1" ]] && echo "200"
exit 0
MOCK
  chmod +x "$1/curl"
}

run_gate() { # $1=extra env (eval'd); echoes nothing, returns the gate's exit code
  (
    local md; md=$(mktemp -d); trap 'rm -rf "$md"' EXIT
    make_mock_curl "$md"
    # Hermeticity: zot-entry-gate.sh falls back to `doppler secrets get … --config prd` on an
    # empty ZOT_PULL_TOKEN. Stub `doppler` to return NOTHING so the "missing creds" case is
    # deterministic — otherwise, once the cutover provisions ZOT_PULL_TOKEN into prd, a local run
    # with a real doppler on PATH resolves the live token and the exit-2 assertion flips to 0 (#6122).
    printf '#!/usr/bin/env bash\nexit 0\n' > "$md/doppler"; chmod +x "$md/doppler"
    export PATH="$md:/usr/bin:/bin"
    export ZOT_REGISTRY_URL="10.0.1.30:5000" ZOT_PULL_USER="zot-pull" ZOT_PULL_TOKEN="tok"
    eval "${1:-}"
    bash "$GATE" v1.2.3 v1.1.18 >/dev/null 2>&1
  )
}

check() { # $1=desc $2=expected-exit $3=extra-env
  run_gate "$3"; local rc=$?
  if [[ "$rc" -eq "$2" ]]; then PASS=$((PASS+1)); echo "  PASS: $1 (exit $rc)";
  else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected $2, got $rc)"; fi
}

echo "=== zot-entry-gate.sh tests ==="
check "both images resolve → PASS (exit 0)"              0 ""
check "web image missing → BLOCK (exit 1)"               1 "export MOCK_WEB_MISSING=1"
check "inngest image missing → BLOCK (exit 1)"           1 "export MOCK_INNGEST_MISSING=1"
check "zot /v2/ unreachable → TRANSIENT (exit 2)"        2 "export MOCK_ZOT_DOWN=1"
check "missing pull creds → TRANSIENT (exit 2)"          2 "export ZOT_PULL_TOKEN=''"


# #8714 review: the three values are all-or-nothing. With ONLY ZOT_REGISTRY_URL in the env and the
# pull credential in Doppler, the gate must not send that credential to the env-supplied host: it
# takes all three from Doppler instead.
LOG="$(mktemp)"
SIN="$(mktemp)"
run_gate "export ZOT_REGISTRY_URL=evil.example.invalid ZOT_PULL_USER='' ZOT_PULL_TOKEN='' MOCK_CURL_LOG=$LOG MOCK_CURL_STDIN=$SIN
printf '#!/usr/bin/env bash\ncase \"\$3\" in ZOT_REGISTRY_URL) echo 10.0.1.30:5000 ;; ZOT_PULL_USER) echo zot-pull ;; ZOT_PULL_TOKEN) echo dtok ;; esac\n' > \"\$md/doppler\""; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'dtok' "$SIN" && ! grep -q 'dtok' "$LOG" && ! grep -q 'evil.example.invalid' "$LOG"; then
  PASS=$((PASS+1)); echo "  PASS: env URL alone does not steer the Doppler credential (all three from Doppler, exit $rc)"
else
  FAIL=$((FAIL+1)); echo "  FAIL: env URL alone steered the request (rc=$rc; log: $(tr '\n' ' ' < "$LOG" | cut -c1-200))"
fi
rm -f "$LOG" "$SIN"

# The pull credential must not appear on curl's argv; it arrives as exactly one `user = "..."` config
# line per authenticated manifest HEAD (two images -> two lines) on stdin.
LOG="$(mktemp)"; SIN="$(mktemp)"
run_gate "export ZOT_PULL_TOKEN=synthetic-fixture-token-0001 MOCK_CURL_LOG=$LOG MOCK_CURL_STDIN=$SIN"; rc=$?
if [[ "$rc" -eq 0 ]] && ! grep -qF 'synthetic-fixture-token-0001' "$LOG" && ! grep -qF 'zot-pull' "$LOG" \
   && [[ "$(grep -cxF 'user = "zot-pull:synthetic-fixture-token-0001"' "$SIN")" == 2 && "$(wc -l < "$SIN")" -eq 2 ]]; then
  PASS=$((PASS+1)); echo "  PASS: credential is absent from curl argv and sent as one stdin user= line per HEAD (exit $rc)"
else
  FAIL=$((FAIL+1)); echo "  FAIL: credential channel wrong (rc=$rc; argv has token: $(grep -cF synthetic-fixture-token-0001 "$LOG"); stdin lines: $(wc -l < "$SIN"))"
fi
rm -f "$LOG" "$SIN"

# A credential that could close the quoted config string or inject a directive (quote, backslash,
# newline, tab, in the user or the token) is refused as "cannot decide" (exit 2, like a missing cred),
# and curl is never invoked at all (no probe, no HEAD), so nothing is sent anywhere.
refusal_row() { # $1=desc $2=var (ZOT_PULL_USER|ZOT_PULL_TOKEN) $3=bad value
  local LOG SIN rc; LOG="$(mktemp)"; SIN="$(mktemp)"
  export BADV="$3"
  run_gate "export $2=\"\$BADV\" MOCK_CURL_LOG=$LOG MOCK_CURL_STDIN=$SIN"; rc=$?
  if [[ "$rc" -eq 2 && ! -s "$LOG" && ! -s "$SIN" ]]; then PASS=$((PASS+1)); echo "  PASS: $1 → refused, curl not invoked (exit $rc)"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1 (rc=$rc, curl argv log bytes=$(wc -c < "$LOG"), stdin bytes=$(wc -c < "$SIN"))"; fi
  unset BADV; rm -f "$LOG" "$SIN"
}
refusal_row "token with a double quote"          ZOT_PULL_TOKEN 'tok"x'
refusal_row "token with a backslash"             ZOT_PULL_TOKEN 'tok\x'
refusal_row "token with a newline (injection)"   ZOT_PULL_TOKEN $'tok\nurl = "http://evil.invalid/"'
refusal_row "token with a tab"                   ZOT_PULL_TOKEN $'tok\tx'
refusal_row "user with a double quote"           ZOT_PULL_USER  'zot"pull'
refusal_row "user with a newline"                ZOT_PULL_USER  $'zot\npull'

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
