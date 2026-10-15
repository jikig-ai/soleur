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
#      The post-bring-up liveness check is a bounded poll (wait_for_gw_tcp): its
#      call-site shape is pinned statically and its behaviour (late-open passes,
#      never-open fails closed with diagnostics, log tail redacted) is driven against
#      a loopback listener, using the functions extracted from the shipped script.
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
LISTEN_PIDS=""
cleanup_suite() {
  # shellcheck disable=SC2086 # LISTEN_PIDS is a space-separated pid list; splitting is the point
  if [[ -n "$LISTEN_PIDS" ]]; then kill $LISTEN_PIDS 2>/dev/null || true; fi
  assert_fixture_dir "$SUITE_SCRATCH"
  rm -rf "$SUITE_SCRATCH"
}
trap cleanup_suite EXIT

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

# Case state read by check_cmd's failure line (set by run_wait; empty for static checks).
CASE_RC=0
CASE_ELAPSED=0
CASE_OUT=""
# check_cmd <description> <command...>: PASS when the command exits 0. Takes the command
# itself rather than a captured `$?`, so no status is read after another command ran.
# (Distinct from the `check <desc> <want> <got>` / `check <desc> <cond>` helpers in the
# cron-egress-* suites: do not copy lines between them.)
check_cmd() {
  local description="$1"
  shift
  if "$@" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (last case: rc=$CASE_RC elapsed=${CASE_ELAPSED}s)"
    if [[ -n "$CASE_OUT" && -s "$CASE_OUT" ]]; then tail -n 3 "$CASE_OUT" | sed 's/^/    | /'; fi
  fi
}
# Negative control: a failing command must move FAIL and a passing one PASS, or every
# check_cmd verdict below is vacuous. Unwound so the real counts stay honest.
nc_p=$PASS; nc_f=$FAIL
check_cmd "negative control (expected FAIL, unwound)" false > /dev/null
check_cmd "positive control (unwound)" true > /dev/null
if (( FAIL - nc_f != 1 || PASS - nc_p != 1 )); then
  printf '[FATAL] check_cmd did not record exactly one FAIL and one PASS (dFAIL=%d dPASS=%d).\n' "$((FAIL - nc_f))" "$((PASS - nc_p))" >&2
  exit 1
fi
PASS=$nc_p; FAIL=$nc_f

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

echo "-- squid.conf: decision-log status field (#9545 attribution hardening) --"
# %un logs the PRESENTED username even when authentication fails (measured on the pinned
# Squid 6.13: a victim id with a bogus token logs workspace=<victim>), so the rollup must
# be able to drop failed-authentication rows. %>Hs carries the HTTP status (407 on failed
# auth, 403 on a policy deny, 200 on an established tunnel).
LOGFORMAT_LINE="$(grep -E '^logformat soleur_json' "$SQUID_CONF")"
LOGFORMAT_FILE="$SUITE_SCRATCH/logformat.txt"
printf '%s\n' "$LOGFORMAT_LINE" > "$LOGFORMAT_FILE"
assert_grep "logformat carries the HTTP status (%>Hs)" '"status":"%>Hs"' "$LOGFORMAT_FILE"
assert_grep "status is the LAST field, so a requested_host that injects JSON keys cannot override it" '"status":"%>Hs"\}$' "$LOGFORMAT_FILE"
assert_grep "workspace (%un) precedes status in the line" '"workspace":"%un".*"status":"%>Hs"' "$LOGFORMAT_FILE"
FIXTURE_LINES="$SCRIPT_DIR/test-fixtures/egress-gw-decision-lines.jsonl"
check_cmd "decision-line fixture exists and is non-empty" test -s "$FIXTURE_LINES"
LOGFORMAT_KEYS="$(grep -oE '"[a-z_]+":' "$LOGFORMAT_FILE" | LC_ALL=C sort -u)"
FIXTURE_KEY_MISMATCH=0
FIXTURE_N=0
while IFS= read -r fx_line; do
  [[ -n "$fx_line" ]] || continue
  FIXTURE_N=$((FIXTURE_N + 1))
  fx_keys="$(printf '%s\n' "$fx_line" | grep -oE '"[a-z_]+":' | LC_ALL=C sort -u)"
  [[ "$fx_keys" == "$LOGFORMAT_KEYS" ]] || FIXTURE_KEY_MISMATCH=$((FIXTURE_KEY_MISMATCH + 1))
done < "$FIXTURE_LINES"
check_cmd "every fixture line has exactly the logformat's keys (fixtures cannot drift from the conf)" test "$FIXTURE_KEY_MISMATCH" -eq 0
check_cmd "fixture covers allowed, policy-denied and failed-authentication lines" test "$FIXTURE_N" -ge 5

echo "-- egress-deny-cidrs.txt: mandatory ranges --"
for cidr in '10.0.0.0/8' '172.16.0.0/12' '192.168.0.0/16' '100.64.0.0/10' \
            '169.254.0.0/16' '127.0.0.0/8' 'fc00::/7' 'fe80::/10' \
            '64:ff9b::/96' '2002::/16' '::ffff:0:0/96'; do
  assert_grep "deny file contains $cidr" "^${cidr//./\\.}([[:space:]]|\$)" "$DENY_FILE"
done

# Format pin (2026-10-10 post-merge incident): the nftables loader strips
# "<space>#..." but does NOT trim whitespace, so a trailing comment leaves
# "<cidr><spaces>" → strict CIDR validation dies → cron-egress-firewall.service
# wedges on BOTH hosts. Every non-comment non-blank line must be a BARE CIDR
# token — no trailing whitespace, no trailing comment.
assert_not_grep "no trailing whitespace on any deny line" \
  '[[:space:]]+$' "$DENY_FILE"
assert_not_grep "no trailing comments (loader leaves pre-# whitespace)" \
  '^[[:space:]]*[^#[:space:]][^#]*[[:space:]]#' "$DENY_FILE"
assert_not_grep "no leading whitespace" \
  '^[[:space:]]' "$DENY_FILE"
bad_lines=$(grep -cvE '^[[:space:]]*(#|$)|^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$|^[0-9a-fA-F:]+/[0-9]{1,3}$' "$DENY_FILE" || true)
if [[ "$bad_lines" == "0" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: every non-comment deny line is a bare CIDR token"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: non-CIDR non-comment deny lines present (loader reject-whole-file)"
fi

echo "-- auth helper: token-file model --"
assert_grep "validates token file existence" 'session-tokens' "$AUTH_HELPER"
assert_grep "emits OK/ERR" 'OK|ERR' "$AUTH_HELPER"
assert_not_grep "no static shared secret" 'EGRESS_PROXY_SECRET|MASTER_SECRET' "$AUTH_HELPER"

echo "-- forwarder: localhost-only + per-session --"
assert_grep "binds loopback" '127\.0\.0\.1|localhost' "$FORWARDER"
assert_grep "strips/injects Proxy-Authorization" 'Proxy-Authorization' "$FORWARDER"
assert_grep "gateway upstream" '8443|soleur-egress-gw' "$FORWARDER"

echo "-- bootstrap: bring-up shape --"
assert_grep "named bridge" 'BRIDGE_IF="soleur-egress0"' "$BOOTSTRAP"
assert_grep "bridge name pinned into create option" 'com\.docker\.network\.bridge\.name="\$BRIDGE_IF"' "$BOOTSTRAP"
assert_grep "subnet probe (collision-safe)" 'docker network (inspect|ls)' "$BOOTSTRAP"
# Docker >= 28 drops cross-bridge dials to container IPs at raw-PREROUTING
# (moby #49325/#49829), killing docker0->gw:8443 before DOCKER-USER can
# accept it (measured: 1611 dropped SYNs, allow_rc=28 on web-1).
# nat-unprotected keeps masquerade but omits that drop; our SOLEUR-EGRESS*
# chains plus the loader's oifname drop are the boundary.
assert_grep "bridge created nat-unprotected (docker >=28 direct-routing escape)" 'com\.docker\.network\.bridge\.gateway_mode_ipv4=nat-unprotected' "$BOOTSTRAP"
assert_grep "old-daemon fallback: a second create without the option exists" 'docker network create --subnet="\$SUBNET" \\$' "$BOOTSTRAP"
N_CREATES="$(grep -c 'docker network create' "$BOOTSTRAP")"
if [[ "$N_CREATES" -eq 2 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: exactly two create arms (optioned + old-daemon fallback)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: expected exactly 2 'docker network create' sites, found $N_CREATES"
fi
assert_grep "post-create mode verify (a wrong-mode create on >=28 dies loud, never silently)" 'require_mode' "$BOOTSTRAP"
assert_grep "existing bridge mode is inspected (immutable opts need rebuild)" 'index \.Options "com\.docker\.network\.bridge\.gateway_mode_ipv4"' "$BOOTSTRAP"
assert_grep "rebuild gated on daemon >= 28 (<28 cannot set the mode — unconditional check would tear down every run)" 'SERVER_MAJOR.*-ge 28' "$BOOTSTRAP"
assert_grep "sanitized version parse (no set -u abort on 'v28'/'4.x-podman' strings)" 'grep -oE .\^\[0-9\]' "$BOOTSTRAP"
assert_grep "wrong-mode rebuild requires a successful mode inspect (no teardown on inspect blip)" 'MODE_RC == 0' "$BOOTSTRAP"
assert_grep "foreign endpoints refuse the rebuild BEFORE the gw dies" 'non-gateway endpoints' "$BOOTSTRAP"
assert_grep "gw container removed before bridge rm" 'docker rm -f "\$GW_NAME"' "$BOOTSTRAP"
assert_grep "wrong-mode bridge is rebuilt (network rm)" 'docker network rm "\$NET_NAME"' "$BOOTSTRAP"
assert_grep "network rm retries teardown-lag (rm -f return != endpoint release)" 'until docker network rm' "$BOOTSTRAP"
# set -e aborts on a bare `[[ ]] && cmd` / `(( )) && cmd` in command position —
# the foreign-endpoint filter, the retry cap and the subnet-clash probe all
# carry false-evaluating runs. Every one must be an if-guard (an `if`-led
# compound is exempt — the anchors start the line with the test itself).
assert_not_grep "no bare [[ ]] && idiom (set -e aborts on the false leg)" '^[[:space:]]*\[\[[^]]*\]\] && ' "$BOOTSTRAP"
assert_not_grep "no bare (( )) && idiom (set -e aborts on the false leg)" '^[[:space:]]*\(\([^)]*\)\) && ' "$BOOTSTRAP"
assert_grep "image guaranteed local before teardown (registry blip cannot strand the rebuild)" 'docker image inspect "\$IMAGE"' "$BOOTSTRAP"
assert_grep "rebuild emits a Better Stack-visible event (lands beside the probe stream)" 'egress_gw_bridge action=rebuilt' "$BOOTSTRAP"
assert_not_grep "gateway_mode is never 'routed' (drops masquerade — gw could not dial upstream)" 'gateway_mode_ipv4="?routed' "$BOOTSTRAP"
assert_grep "token dir" 'egress-tokens' "$BOOTSTRAP"
assert_grep "digest-pinned image" '@sha256:' "$BOOTSTRAP"
assert_grep "journald log driver" 'log-driver.*journald|--log-driver' "$BOOTSTRAP"
assert_grep "restart policy" 'restart.*unless-stopped|--restart' "$BOOTSTRAP"

echo "-- bootstrap: post-bring-up poll (static) --"
# `docker run -d` / `docker restart` return before Squid binds its listener, so a
# single probe at t~0 is refused; the check is a bounded poll. The static verdicts pin
# the SHAPE of the call site (what the extracted-function tests below cannot see):
# the budget default, the single call after both bring-up arms, and that nothing else
# in the script can reach the OK line or shadow the extracted functions.
assert_grep "wait budget default is 30 s (EGRESS_GW_WAIT_S overrides, for tests)" 'GW_WAIT_S="\$\{EGRESS_GW_WAIT_S:-30\}"' "$BOOTSTRAP"
assert_grep "the die text is preserved verbatim" 'did not answer a TCP open post-bring-up' "$BOOTSTRAP"
assert_not_grep "no single-shot top-level probe (the one that raced squid)" '^[[:space:]]*timeout [0-9]+ bash -c .exec 3<>' "$BOOTSTRAP"
assert_not_grep "nothing can end the script green before the poll (no exit 0 / trap)" '^[[:space:]]*(exit 0|trap )' "$BOOTSTRAP"
check_cmd "exactly one GW_WAIT_S assignment (a later one would silently change the budget)" test "$(grep -c '^GW_WAIT_S=' "$BOOTSTRAP" || true)" -eq 1
check_cmd "wait_for_gw_tcp is called exactly once at top level" test "$(grep -c '^wait_for_gw_tcp$' "$BOOTSTRAP" || true)" -eq 1
# Both bring-up arms (docker restart / docker run -d) must flow through the one call,
# and the call must be followed directly by the OK line (nothing can skip past it).
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
CALL_LN="$(grep -n '^wait_for_gw_tcp$' "$BOOTSTRAP" | head -n 1 | cut -d: -f1 || true)"
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
RESTART_LN="$(grep -n 'restarted \$GW_NAME' "$BOOTSTRAP" | head -n 1 | cut -d: -f1 || true)"
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
START_LN="$(grep -n 'started \$GW_NAME' "$BOOTSTRAP" | head -n 1 | cut -d: -f1 || true)"
check_cmd "the poll call sits after the docker restart arm" test "${CALL_LN:-0}" -gt "${RESTART_LN:-999999}"
check_cmd "the poll call sits after the docker run arm" test "${CALL_LN:-0}" -gt "${START_LN:-999999}"
check_cmd "the poll call is followed by a blank line" test -z "$(sed -n "$((${CALL_LN:-0} + 1))p" "$BOOTSTRAP")"
check_cmd "the poll call is followed directly by the OK log" grep -q '^log "OK: gateway up' <(sed -n "$((${CALL_LN:-0} + 2))p" "$BOOTSTRAP")
for fn in wait_for_gw_tcp gw_diag die log; do
  check_cmd "exactly one definition of $fn (a redefinition would shadow the extracted copy)" test "$(grep -cE "^${fn}[[:space:]]*\(\)" "$BOOTSTRAP" || true)" -eq 1
done
check_cmd "no function shadows timeout/sleep/docker/bash" test "$(grep -cE '^(function[[:space:]]+)?(timeout|sleep|docker|bash)[[:space:]]*(\(\)|\{)' "$BOOTSTRAP" || true)" -eq 0

# The budget lines are EXECUTED, not just grepped: the default, the env override and the
# fail-closed validation of a non-numeric value are the production env -> budget path,
# which the extracted-function tests (they set GW_WAIT_S directly) never run.
GW_LINE="$(grep -m1 '^GW_WAIT_S=' "$BOOTSTRAP" || true)"
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
GUARD_LINE="$(grep -m1 '^\[\[ "\$GW_WAIT_S" =~' "$BOOTSTRAP" || true)"
check_cmd "the budget validation line exists" test -n "$GUARD_LINE"
budget_probe() { # budget_probe [NAME=value]  -> prints the effective budget, or fails closed like die
  local prog
  # shellcheck disable=SC2016 # the program text is single-quoted on purpose
  prog="$(printf 'die() { echo "$*" >&2; exit 1; }\n%s\n%s\necho "$GW_WAIT_S"\n' "$GW_LINE" "$GUARD_LINE")"
  # shellcheck disable=SC2086 # ${1-} is either empty or ONE NAME=value word
  env -u EGRESS_GW_WAIT_S ${1-} bash -c "$prog"
}
fails() { ! "$@"; }
check_cmd "budget defaults to 30 with EGRESS_GW_WAIT_S unset" test "$(budget_probe)" = 30
check_cmd "EGRESS_GW_WAIT_S overrides the budget" test "$(budget_probe EGRESS_GW_WAIT_S=7)" = 7
check_cmd "a leading-zero budget is accepted and stays decimal-safe" test "$(budget_probe EGRESS_GW_WAIT_S=08)" = 08
check_cmd "a non-numeric budget fails closed" fails budget_probe EGRESS_GW_WAIT_S=abc
check_cmd "an arithmetic-expression budget fails closed" fails budget_probe 'EGRESS_GW_WAIT_S=1+1'
check_cmd "a negative budget fails closed" fails budget_probe EGRESS_GW_WAIT_S=-5
check_cmd "an over-long budget fails closed" fails budget_probe EGRESS_GW_WAIT_S=12345

echo "-- bootstrap: post-bring-up poll (behavioural) --"
# The functions are EXTRACTED from the shipped script (no logic copy) and driven against
# a real loopback socket that binds immediately and listen()s after a delay.
extract_fn() { # extract_fn name  (definition line `name() {` through the closing `}` at col 0)
  awk -v n="$1" '
    $0 == n "() {" { p = 1 }
    p { print }
    p && $0 == "}" { exit }' "$BOOTSTRAP"
}
WORK="$SUITE_SCRATCH/poll"
assert_fixture_dir "$WORK"
mkdir -p "$WORK/fakes"
extract_fn gw_diag > "$WORK/gw_diag.txt"
extract_fn wait_for_gw_tcp > "$WORK/wait_fn.txt"
{
  echo '# generated by egress-gateway.test.sh from egress-gateway-bootstrap.sh'
  grep -E '^(log|die)\(\) \{' "$BOOTSTRAP" || true
  cat "$WORK/gw_diag.txt" "$WORK/wait_fn.txt"
} > "$WORK/lib.sh"
check_cmd "extracted gw_diag (>= 8 lines)" test "$(wc -l < "$WORK/gw_diag.txt")" -ge 8
check_cmd "extracted wait_for_gw_tcp (>= 14 lines)" test "$(wc -l < "$WORK/wait_fn.txt")" -ge 14
check_cmd "the generated lib carries log and die" test "$(grep -cE '^(log|die)\(\) \{' "$WORK/lib.sh")" -eq 2
check_cmd "the generated lib parses" bash -n "$WORK/lib.sh"
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
assert_grep "the probe is a bash /dev/tcp open (no curl dependency)" '/dev/tcp/\$1/\$2' "$WORK/wait_fn.txt"
# The decision lines of the loop are pinned by exact text: a one-line edit of any of them
# (an early `return 0`, a larger deadline, a longer per-attempt timeout) stays inside the
# budgets the behavioural cases below use, so only the spelling can catch it.
check_cmd "success is reachable from exactly one return 0" test "$(grep -c 'return 0' "$WORK/wait_fn.txt")" -eq 1
# shellcheck disable=SC2016 # literal $ in a fixed-string pattern, not an expansion
check_cmd "success is gated on exactly one connect attempt, the whole line (no extra disjunct)" test "$(grep -cxF '    if err="$(timeout 2 bash -c '"'"'exec 3<>"/dev/tcp/$1/$2"'"'"' gw-probe "$GW_IP" "$GW_PORT" 2>&1)"; then' "$WORK/wait_fn.txt")" -eq 1
# shellcheck disable=SC2016 # literal $ in a grep pattern, not an expansion
check_cmd "the deadline is SECONDS + the budget, assigned once" test "$(grep -cF 'local deadline=$(( SECONDS + 10#$GW_WAIT_S ))' "$WORK/wait_fn.txt")" -eq 1
check_cmd "the loop leaves only when the deadline passes" test "$(grep -cF 'if (( SECONDS >= deadline )); then break; fi' "$WORK/wait_fn.txt")" -eq 1

# An EXECUTABLE docker stub: `timeout 10 docker logs` execs the binary, so a shell
# function would be bypassed. It refuses argv the production call must not omit, and
# plays back what a real gateway log carries: cache.log lines, a per-request JSON
# decision line (workspace id + requested host), a session-token path and control bytes.
cat > "$WORK/fakes/docker" <<'STUB'
#!/usr/bin/env bash
case "${1-}" in
  inspect)
    [[ $# -eq 4 && "${2-}" == "-f" && "${3-}" == *State.Status* && "${4-}" == "soleur-egress-gw" ]] || exit 64
    echo "STUB-STATE running running=true restarting=false" ;;
  logs)
    [[ $# -eq 4 && "${2-}" == "--tail" && "${3-}" =~ ^[0-9]+$ && "${4-}" == "soleur-egress-gw" ]] || exit 64
    echo "STUB-LOG squid starting"
    echo '{"decision":"TCP_DENIED","requested_host":"leak-host.example","workspace":"ws-LEAK-1234"}'
    echo "STUB-LOG helper read /etc/squid/session-tokens/tok-LEAK-5678 failed"
    printf 'STUB-CTRL a\033[31mred\033[0m\r\n' ;;
  *) echo "unexpected docker $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/fakes/docker"

# Binds a loopback port immediately; listen()s after DELAY seconds ("0" = before the
# port is announced, "never" = never). The port is held from the start: no free-port race.
# It exits when its parent (this suite) dies, so a SIGKILLed run leaks nothing for long.
cat > "$WORK/listener.py" <<'LISTENER'
import os, socket, sys, time
pf, host, delay = sys.argv[1], sys.argv[2], sys.argv[3]
ppid = os.getppid()
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, 0))
if delay == "0":
    s.listen(8)
with open(pf, "w") as f:
    f.write(str(s.getsockname()[1]))
if delay not in ("0", "never"):
    time.sleep(float(delay))
    s.listen(8)
end = time.time() + 600
while os.getppid() == ppid and time.time() < end:
    time.sleep(1)
LISTENER

LISTEN_N=0
LISTEN_PORT=""
start_listener() { # start_listener <host> <delay|never>  -> sets LISTEN_PORT
  local pf="$WORK/port.$LISTEN_N" w=0
  LISTEN_N=$((LISTEN_N + 1))
  python3 -I "$WORK/listener.py" "$pf" "$1" "$2" >/dev/null 2>&1 &
  LISTEN_PIDS="$LISTEN_PIDS $!"
  while [[ ! -s "$pf" ]]; do
    w=$((w + 1))
    if (( w > 100 )); then break; fi
    sleep 0.1
  done
  LISTEN_PORT="$(cat "$pf" 2>/dev/null || true)"
  check_cmd "listener bound a port ($1, delay $2)" test -n "$LISTEN_PORT"
}

run_wait() { # run_wait <outfile> <ip> <port> <budget>  -> sets CASE_RC, CASE_ELAPSED, CASE_OUT
  local out="$1" ip="$2" port="$3" budget="$4" t0="$SECONDS"
  CASE_RC=0
  CASE_OUT="$out"
  assert_fixture_dir "$out"
  # Called bare under set -euo pipefail, like production (an `f || ...` caller would
  # suppress errexit inside it). The outer timeout turns an infinite loop into rc 124.
  # LC_ALL=C pins the strerror text the refused-connect assertion greps for.
  # shellcheck disable=SC2016 # the program text is single-quoted on purpose: $1..$4 are bash -c positionals
  LC_ALL=C PATH="$WORK/fakes:$PATH" timeout $((budget + 15)) bash -c \
    'set -euo pipefail; source "$1"; GW_IP="$2"; GW_PORT="$3"; GW_NAME=soleur-egress-gw; GW_WAIT_S="$4"; wait_for_gw_tcp' \
    _ "$WORK/lib.sh" "$ip" "$port" "$budget" > "$out" 2>&1 || CASE_RC=$?
  CASE_ELAPSED=$((SECONDS - t0))
}

if ! command -v python3 >/dev/null 2>&1; then
  FAIL=$((FAIL + 1)); echo "  FAIL: python3 is required for the loopback listener fixture"
else
  # T1: already listening -> attempt 1 (positive control: the probe really connects).
  start_listener 127.0.0.1 0
  run_wait "$WORK/t1.out" 127.0.0.1 "$LISTEN_PORT" 8
  check_cmd "T1 already-listening gw: rc 0" test "$CASE_RC" -eq 0
  check_cmd "T1 answered on attempt 1" grep -q 'answered a TCP open (attempt 1)' "$WORK/t1.out"

  # T2: listens 2 s after bring-up, 8 s budget -> succeeds on a retry.
  start_listener 127.0.0.1 2
  run_wait "$WORK/t2.out" 127.0.0.1 "$LISTEN_PORT" 8
  check_cmd "T2 late-listening gw (2 s) within an 8 s budget: rc 0" test "$CASE_RC" -eq 0
  check_cmd "T2 needed a retry (attempt >= 2)" grep -qE 'answered a TCP open \(attempt ([2-9]|[1-9][0-9]+)\)' "$WORK/t2.out"

  # T3: bound but never listens, 3 s budget -> fails closed with the diagnostics.
  start_listener 127.0.0.1 never
  run_wait "$WORK/t3.out" 127.0.0.1 "$LISTEN_PORT" 3
  check_cmd "T3 never-listening gw fails closed (nonzero rc)" test "$CASE_RC" -gt 0
  check_cmd "T3 fails by the die, not by the outer timeout" test "$CASE_RC" -ne 124
  check_cmd "T3 prints the existing die text" grep -q 'did not answer a TCP open post-bring-up' "$WORK/t3.out"
  check_cmd "T3 prints the container state" grep -q 'STUB-STATE' "$WORK/t3.out"
  check_cmd "T3 prints the gw log tail" grep -q 'STUB-LOG squid starting' "$WORK/t3.out"
  check_cmd "T3 reports the last probe error (refused, not a timeout)" grep -qi 'last probe error: rc=1 .*connection refused' "$WORK/t3.out"
  # The gateway log goes into the apply log of a PUBLIC repository: the decision line
  # (workspace id, requested host) must not reach it, token paths are masked, control
  # bytes are stripped.
  check_cmd "T3 drops the per-request decision line (workspace id)" fails grep -q 'ws-LEAK-1234' "$WORK/t3.out"
  check_cmd "T3 drops the per-request decision line (requested host)" fails grep -q 'leak-host.example' "$WORK/t3.out"
  check_cmd "T3 masks the session-token path" fails grep -q 'tok-LEAK-5678' "$WORK/t3.out"
  check_cmd "T3 keeps the rest of that cache.log line" grep -q 'session-tokens/<redacted> failed' "$WORK/t3.out"
  check_cmd "T3 strips control bytes (ESC, CR) from the log tail" fails grep -q $'\033' "$WORK/t3.out"
  check_cmd "T3 keeps the printable text around the stripped control bytes" grep -q 'STUB-CTRL a\[31mred\[0m' "$WORK/t3.out"
  # SECONDS is an integer counter, so a budget of 3 can end ~1 s early; the worst real
  # overrun is the last 2 s attempt plus the 1 s sleep (about 6 s), so 9 leaves margin
  # under load and still rejects a deadline that grew by seconds.
  check_cmd "T3 waited at least about its 3 s budget" test "$CASE_ELAPSED" -ge 2
  check_cmd "T3 did not wait past its budget plus one attempt" test "$CASE_ELAPSED" -le 9
  # The die line is the LAST line: diagnostics come first.
  assert_fixture_dir "$WORK"
  tail -n 1 "$WORK/t3.out" > "$WORK/t3.last"
  check_cmd "T3 die line follows the diagnostics" grep -q 'did not answer a TCP open post-bring-up$' "$WORK/t3.last"

  # H2: a non-canonical must-PASS row (other loopback address, other budget).
  start_listener 127.0.0.2 0
  run_wait "$WORK/h2.out" 127.0.0.2 "$LISTEN_PORT" 7
  check_cmd "H2 non-canonical gw address/budget: rc 0" test "$CASE_RC" -eq 0
fi

echo "-- guard contract --"
# Mutation matrix (Guard 1): each row names a structural weakening and the
# expected RED. The fixtures above pin the positive shape; these pin the
# negative space.
assert_not_grep "no privileged squid" 'privileged|--cap-add' "$BOOTSTRAP"
assert_not_grep "no host networking" 'network host|--net=host' "$BOOTSTRAP"
assert_grep "firewall suite knows the new chains" 'SOLEUR-EGRESS-GW' "$TEST_SH"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $((PASS + FAIL)) -lt 130 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 130.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
