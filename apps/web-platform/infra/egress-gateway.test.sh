#!/usr/bin/env bash
# Drift-guard for the egress gateway (open-web egress, #9534 / feat-open-web-egress).
#
# Locks the load-bearing invariants of the Squid CONNECT gateway:
#   1. squid.conf: CONNECT-only + 443-only + auth-required + deny-set coverage.
#      `to_localhost` alone does NOT cover ULA/link-local (Kieran review) — the
#      file-backed dst deny is the real boundary and it MUST reference the
#      shared egress-deny-cidrs.txt (two-table drift class, not a copy).
#   2. egress-deny-cidrs.txt: the single source — every mandatory range present.
#   3. egress-auth-helper.sh: password = session-token file exists, never a
#      static secret (spec-flow P0: no static credential anywhere).
#   4. egress-forwarder.mjs: localhost-only, per-session token in, workspace
#      attribution out.
#   5. egress-gateway-bootstrap.sh: named bridge, subnet probe, token dir,
#      digest-pinned image, journald logging, restart policy.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQUID_CONF="$SCRIPT_DIR/egress-gateway-squid.conf"
AUTH_HELPER="$SCRIPT_DIR/egress-auth-helper.sh"
FORWARDER="$SCRIPT_DIR/egress-forwarder.mjs"
BOOTSTRAP="$SCRIPT_DIR/egress-gateway-bootstrap.sh"
DENY_FILE="$SCRIPT_DIR/egress-deny-cidrs.txt"
TEST_SH="$SCRIPT_DIR/cron-egress-firewall.test.sh"

PASS=0
FAIL=0

SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/egress-gateway-test.XXXXXX")"
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$SUITE_SCRATCH"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (pattern not found in $(basename "$file"): $pattern)"
  fi
}

assert_not_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (forbidden pattern present in $(basename "$file"): $pattern)"
  else
    PASS=$((PASS + 1)); echo "  PASS: $description"
  fi
}

assert_file() {
  local description="$1" file="$2"
  if [[ -f "$file" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (missing: $file)"
  fi
}

echo "--- egress gateway drift-guard ---"

echo "-- artifacts exist --"
assert_file "squid.conf exists" "$SQUID_CONF"
assert_file "auth helper exists" "$AUTH_HELPER"
assert_file "forwarder exists" "$FORWARDER"
assert_file "bootstrap exists" "$BOOTSTRAP"
assert_file "deny-cidrs file exists" "$DENY_FILE"

echo "-- squid.conf: protocol surface --"
assert_grep "CONNECT-only" 'http_access deny !CONNECT' "$SQUID_CONF"
assert_grep "443-only SSL_ports" 'acl SSL_ports port 443' "$SQUID_CONF"
assert_grep "deny CONNECT !SSL_ports" 'http_access deny CONNECT !SSL_ports' "$SQUID_CONF"
assert_grep "proxy auth required" 'http_access deny !auth_ok|proxy_auth REQUIRED' "$SQUID_CONF"
assert_not_grep "dns_v4_first directive not set (obsolete + config error under Squid 6)" '^[[:space:]]*dns_v4_first ' "$SQUID_CONF"
assert_not_grep "no open allow-all" 'http_access allow all' "$SQUID_CONF"
assert_grep "terminal deny-all" 'http_access deny all' "$SQUID_CONF"
assert_grep "listener is 8443" 'http_port 8443' "$SQUID_CONF"

echo "-- squid.conf: deny coverage --"
# to_localhost alone covers only 127/8 + ::1 — ULA/link-local need explicit lines.
assert_grep "to_localhost ACL" 'to_localhost' "$SQUID_CONF"
assert_grep "to_linklocal ACL" 'to_linklocal' "$SQUID_CONF"
assert_grep "file-backed dst deny references the SHARED file" \
  'acl egress_deny dst ".*egress-deny-cidrs\.txt"' "$SQUID_CONF"
assert_not_grep "no inline CIDR duplication (single-source drift)" \
  'acl egress_deny dst [0-9]' "$SQUID_CONF"

echo "-- squid.conf: auth + logging --"
assert_grep "basic auth program is the baked helper" 'auth_param basic program.*egress-auth-helper' "$SQUID_CONF"
assert_grep "workspace attribution (%un)" '%un' "$SQUID_CONF"
assert_grep "structured decision log (JSON-ish)" 'logformat.*\{|logformat.*decision' "$SQUID_CONF"

echo "-- egress-deny-cidrs.txt: mandatory ranges --"
for cidr in '10.0.0.0/8' '172.16.0.0/12' '192.168.0.0/16' '100.64.0.0/10' \
            '169.254.0.0/16' '127.0.0.0/8' 'fc00::/7' 'fe80::/10' \
            '64:ff9b::/96' '2002::/16' '::ffff:0:0/96'; do
  assert_grep "deny file contains $cidr" "^${cidr//./\\.}([[:space:]]|\$)" "$DENY_FILE"
done

echo "-- auth helper: token-file model --"
assert_grep "validates token file existence" 'session-tokens' "$AUTH_HELPER"
assert_grep "emits OK/ERR" 'OK|ERR' "$AUTH_HELPER"
assert_not_grep "no static shared secret" 'EGRESS_PROXY_SECRET|MASTER_SECRET' "$AUTH_HELPER"

echo "-- forwarder: localhost-only + per-session --"
assert_grep "binds loopback" '127\.0\.0\.1|localhost' "$FORWARDER"
assert_grep "strips/injects Proxy-Authorization" 'Proxy-Authorization' "$FORWARDER"
assert_grep "gateway upstream" '8443|soleur-egress-gw' "$FORWARDER"

echo "-- bootstrap: bring-up shape --"
assert_grep "named bridge" 'com\.docker\.network\.bridge\.name=soleur-egress0' "$BOOTSTRAP"
assert_grep "subnet probe (collision-safe)" 'docker network (inspect|ls)' "$BOOTSTRAP"
assert_grep "token dir" 'egress-tokens' "$BOOTSTRAP"
assert_grep "digest-pinned image" '@sha256:' "$BOOTSTRAP"
assert_grep "journald log driver" 'log-driver.*journald|--log-driver' "$BOOTSTRAP"
assert_grep "restart policy" 'restart.*unless-stopped|--restart' "$BOOTSTRAP"

echo "-- guard contract --"
# Mutation matrix (Guard 1): each row names a structural weakening and the
# expected RED. The fixtures above pin the positive shape; these pin the
# negative space.
assert_not_grep "no privileged squid" 'privileged|--cap-add' "$BOOTSTRAP"
assert_not_grep "no host networking" 'network host|--net=host' "$BOOTSTRAP"
assert_grep "firewall suite knows the new chains" 'SOLEUR-EGRESS-GW' "$TEST_SH"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $((PASS + FAIL)) -lt 30 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 30.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
