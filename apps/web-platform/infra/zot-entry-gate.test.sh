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
url=""; want_code=0
for a in "$@"; do
  case "$a" in
    http*) url="$a" ;;
    -w) want_code=1 ;;  # crude but the gate always pairs -w with %{http_code}
  esac
done
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

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
