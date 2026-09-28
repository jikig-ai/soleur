#!/usr/bin/env bash
# Tests the registry-host zot LIVENESS heartbeat feeder (#6537, cloud-init-registry.yml).
#
# WHY THIS EXISTS. `betteruptime_heartbeat.registry_prd` was provisioned paused=true on
# 2026-07-07 as a bootstrap step, to be armed once "the web-host probe cron ships". That probe
# was never written, so the monitor sat inert for 9 days while its own source comment claimed a
# feeder existed. This suite covers the feeder that finally arms it.
#
# WHAT IT COVERS. The disk heartbeat (registry_disk_prd, 900s) already alarms HOST death by
# absence, so this feeder's job is the narrower gap it cannot see: **zot process dead, host
# alive, disk fine**. The ping is therefore ABSENCE-BASED and gated on a real zot probe.
#
# THE FIXTURE MODELS HTTP STATUS CODES, NOT curl EXIT CODES — and that is load-bearing.
# An earlier version of this suite modelled "zot answers" as curl exit 0. The real host never
# produces that: zot auth-gates /v2/ (htpasswd + "defaultPolicy": []), so an anonymous probe
# gets **401**. The feeder then used `curl -f`, which exits 22 on any >=400 — so the ping was
# unreachable and the monitor would have stayed dark forever, with this suite green over it.
# The fixture encoded the bug, so its assertions certified a feeder that could never emit a
# beat. T1 is now the 401 case: the shape production actually returns.
#
# THE OTHER LOAD-BEARING CHOICE: the probe targets the host's OWN PRIVATE IP (10.0.1.30:5000),
# never loopback. zot binds `0.0.0.0`, so a loopback probe answers even when the private NIC is
# absent — which is precisely how #6400 stayed green for ~14 days (cloud-init-registry.yml
# documents this verbatim at the private-NIC guard preamble). T3 is the test that FAILS a
# loopback implementation every other test would pass.
#
# TWO layers (mirrors private-nic-guard.test.sh):
#   1. BEHAVIORAL: RENDER the feeder out of the Terraform template and EXECUTE it against
#      synthesized PATH stubs (cq-test-fixtures-synthesized-only). No live host, no network.
#   2. STRUCTURAL grep assertions over a COMMENT-STRIPPED view, anchored on syntax.
#
# NON-VACUITY: T1 is the positive control for the emit path, so every "NO ping" case can never
# pass merely because the script died at line 1 — each is paired with a probe-happened assert.
#
# Static + pure-bash — no docker, no network, no doppler, no root.
#
# Run: bash apps/web-platform/infra/zot-liveness-heartbeat.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"
FEEDER_PATH="/usr/local/bin/zot-liveness-heartbeat.sh"
TEST_IP="10.0.1.30"
# Escaped for use inside grep -E, where a bare dot is a wildcard.
TEST_IP_RE="${TEST_IP//./\\.}"
TEST_HB_URL="https://uptime.betterstack.com/api/v1/heartbeat/synthetic-liveness"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Resolved before any fixture strips PATH; bounds a runaway feeder (see run_feeder / T5).
TIMEOUT_BIN="$(command -v timeout || true)"

echo "=== registry zot liveness heartbeat feeder (#6537) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"
assert "the timeout binary is available (bounds a runaway feeder; T5 depends on it)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- RENDER: template -> executable bash -------------------------------------------------
RENDERED="$TMP/feeder.sh"
awk -v want="  - path: $FEEDER_PATH" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent {
    if ($0 ~ /^      /) { print substr($0, 7); next }
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    exit
  }
' "$CI" > "$RENDERED"

assert "feeder block extracted from the template (non-empty)" "[[ -s '$RENDERED' ]]"
assert "extracted block is the feeder (has a shebang)" "head -1 '$RENDERED' | grep -c '^#!' >/dev/null"

sed -i "s|\${private_ip}|$TEST_IP|g" "$RENDERED"
sed -i "s|\${liveness_heartbeat_url}|$TEST_HB_URL|g" "$RENDERED"
# TF-escaped shell expansions: $${VAR} -> ${VAR}. And %%{ -> %{ — the templatefile directive
# escape: `-w '%{http_code}'` MUST be written `%%{http_code}` in the template or terraform's
# directive scanner rejects the render outright.
sed -i 's|\$\${|${|g' "$RENDERED"
sed -i 's|%%{|%{|g' "$RENDERED"
# (#7270) The per-boot state seam: the feeder keeps its counters in tmpfs under
# /run/soleur-registry/, re-rooted here the same way the redaction suite re-roots the reporter's
# reads. Rewritten WITHOUT a trailing slash so the directory the feeder creates moves too.
STATE_DIR="$TMP/run-soleur-registry"
STATE="$STATE_DIR/zot-liveness.state"
sed -i "s|/run/soleur-registry|$STATE_DIR|g" "$RENDERED"
mkdir -p "$STATE_DIR"

# Charset must be at least as wide as Terraform's own var names (digits included) — a missed
# digit-bearing var never trips `set -u` inside quotes, so the suite would silently execute a
# broken feeder. Mirrors private-nic-guard.test.sh's identical assert + rationale.
assert "render left no unrendered TF interpolation" "! grep -qE '\\\$\{[A-Za-z0-9_.]+\}' '$RENDERED'"
assert "render left no unescaped TF directive" "! grep -qF '%%{' '$RENDERED'"
assert "rendered feeder is syntactically valid bash" "bash -n '$RENDERED'"
assert "(#7270) the state seam landed (the feeder now writes under the fixture dir)" \
  "grep -qF '$STATE_DIR/zot-liveness.state' '$RENDERED' && ! grep -qF '/run/soleur-registry' '$RENDERED'"

# (#7270) RAW-template escaping, asserted on the SOURCE block rather than the sed render above.
# The render converts every `$${` to `${`, so a bare `${x}` the author forgot to escape survives it
# as plain bash and passes; Terraform would instead reject it, or silently fill it in when the
# name matches a real template variable. In the source block the only legal `${` are the two
# template variables and the `$${` escape; the only legal `%{` is the `%%{` escape.
RAW_BLOCK="$TMP/feeder.raw"
awk -v want="  - path: $FEEDER_PATH" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent { if ($0 ~ /^      / || $0 ~ /^[[:space:]]*$/) { print; next } exit }
' "$CI" > "$RAW_BLOCK"
assert "(#7270) raw feeder block extracted (non-empty)" "[[ -s '$RAW_BLOCK' ]]"
# Scrub the legal forms, then COUNT what remains (a count cannot fold grep's rc 2 into "clean").
RAW_SCRUBBED="$TMP/feeder.raw.scrubbed"
sed -e 's/[$][$][{]//g' -e 's/[$][{]private_ip[}]//g' -e 's/[$][{]liveness_heartbeat_url[}]//g' \
  -e 's/%%[{]//g' "$RAW_BLOCK" > "$RAW_SCRUBBED"
assert "(#7270) raw template: no \${ except the two template variables and the \$\${ escape" \
  "[[ \$(grep -cF '\${' '$RAW_SCRUBBED') == 0 ]]"
assert "(#7270) raw template: no %{ except the %%{ escape" \
  "[[ \$(grep -cF '%{' '$RAW_SCRUBBED') == 0 ]]"
chmod +x "$RENDERED"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# ONE curl stub serves both callers, discriminating by target, and models the REAL contract:
#   * an HTTP response -> print the status code (what -w '%{http_code}' emits), exit 0
#   * no HTTP response -> print 000, exit 7 (curl's connect-failure code)
# It records EVERY probed URL to $STUB_PROBES, which is what makes T3's negative-space assert
# ("loopback was never probed") observable rather than inferred.
#
# It also HONORS -m: with STUB_HANG=1 and no -m on the probe it sleeps past the outer timeout,
# which is what makes "the probe is bounded" testable behaviorally (T5) instead of by grep.
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# Models the three curl behaviours this feeder's correctness actually depends on. Each is here
# because omitting it made the suite green over a broken feeder:
#   -f  : exit 22 on any HTTP >=400 and suppress the body. This is THE P1 — an -f probe treats
#         zot's healthy 401 as failure. A stub that ignores -f cannot catch it.
#   -w  : ONLY with `-w '%{http_code}'` does curl print the status code. A stub that prints the
#         code unconditionally hands the feeder a value real curl would never have given it.
#   -m  : without it, a hung zot hangs the unit (STUB_HANG models this; see T5).
target=""; has_m=0; has_f=0; has_w_code=0; prev=""
for a in "$@"; do
  case "$a" in
    http://*|https://*) target="$a" ;;
    -f|-fsS|-fs|-fS)    has_f=1 ;;
    '%{http_code}')     has_w_code=1 ;;
  esac
  [[ "$prev" == "-m" ]] && has_m=1
  prev="$a"
done
printf '%s\n' "$target" >> "$STUB_PROBES"
respond() {
  local code="$1"
  if [[ "${STUB_HANG:-0}" == "1" && "$has_m" == "0" ]]; then sleep 30; fi
  # Connect failure: no HTTP response at all. -w prints 000; curl exits 7 either way.
  if [[ "$code" == "000" ]]; then
    [[ "$has_w_code" == "1" ]] && printf '000'
    exit 7
  fi
  [[ "$has_w_code" == "1" ]] && printf '%s' "$code"
  # -f: any >=400 is a failure exit (22), regardless of what it means semantically.
  if [[ "$has_f" == "1" && "$code" -ge 400 ]]; then exit 22; fi
  exit 0
}
case "$target" in
  *10.0.1.30:5000*) respond "${STUB_PRIVATE_CODE:-401}" ;;
  *localhost:5000*) respond "${STUB_LOCALHOST_CODE:-401}" ;;
  *127.0.0.1:5000*) respond "${STUB_LOCALHOST_CODE:-401}" ;;
  # The ping is RECORDED whether or not it succeeds (it was attempted), and logged to the ORDER
  # file the mv stub also writes to. STUB_PING_CODE is the HTTP status Better Stack answers the
  # beat with; `respond` models -f, so a 429 is an exit 22 ONLY while the feeder keeps `-f`
  # (without it curl exits 0 on a 429 and a rejected beat would count as sent: #7270's
  # ping_fail_cum arm depends on that flag).
  *heartbeat*)      printf '%s\n' "$target" >> "$STUB_EMIT"; printf 'PING\n' >> "$STUB_ORDER"
                    respond "${STUB_PING_CODE:-200}" ;;
esac
exit 0
EOS
# (#7270) A pass-through `mv` that logs itself to the ORDER file. The feeder's only `mv` is the
# state write, so `PING` before `MV` in that file proves the state work runs AFTER the ping.
# (The feeder has no `set -e`, so a merely FAILING state step placed before the ping would not
# stop it: ordering has to be observed, not inferred from the ping landing.)
REAL_MV="$(command -v mv)"
cat > "$BIN/mv" <<EOS
#!/usr/bin/env bash
printf 'MV\n' >> "\$STUB_ORDER"
exec "$REAL_MV" "\$@"
EOS
chmod +x "$BIN"/*

# --- Fixture harness ---------------------------------------------------------------------
# run_feeder <private_http_code> <loopback_http_code>
#   Codes are what an HTTP GET /v2/ returns; "000" means no HTTP response at all (connection
#   refused / timeout / absent NIC). The two args diverge in exactly one real-world shape —
#   #6400's private-NIC-absent host — which is what T3 pins.
RUN_RC=0
run_feeder() {
  local private_code="$1" loopback_code="$2"
  STUB_EMIT="$TMP/emit.$$.$RANDOM"
  STUB_PROBES="$TMP/probes.$$.$RANDOM"
  : > "$STUB_EMIT"
  STUB_ORDER="$TMP/order.$$.$RANDOM"
  : > "$STUB_ORDER"
  : > "$STUB_PROBES"
  env -i \
    PATH="$BIN:/usr/bin:/bin" \
    STUB_EMIT="$STUB_EMIT" \
    STUB_PROBES="$STUB_PROBES" \
    STUB_PRIVATE_CODE="$private_code" \
    STUB_LOCALHOST_CODE="$loopback_code" \
    STUB_HANG="${STUB_HANG:-0}" \
    STUB_ORDER="$STUB_ORDER" \
    STUB_PING_CODE="${STUB_PING_CODE:-200}" \
    "$TIMEOUT_BIN" 10 bash "$RENDERED" >/dev/null 2>&1
  RUN_RC=$?
}

# --- T1: positive control — zot answers 401 (auth-gated) => ping -------------------------
# THE REGRESSION TEST FOR THE P1. 401 is what the real host returns to an anonymous /v2/ probe:
# zot is up, listening, and enforcing auth. A `curl -f` probe exits 22 here and never pings.
echo ""
echo "--- T1: zot answers 401 (auth-gated — the production shape) => ping emitted"
run_feeder 401 401
assert "T1 emits a heartbeat ping on 401" "[[ -s '$STUB_EMIT' ]]"
assert "T1 probed the private IP" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

echo ""
echo "--- T1b: zot answers 200 => ping emitted"
run_feeder 200 200
assert "T1b emits a heartbeat ping on 200" "[[ -s '$STUB_EMIT' ]]"

# --- T2: zot dead, host alive, disk fine => NO ping --------------------------------------
# The gap the 900s disk heartbeat structurally cannot see: it pings on `df` alone, so it stays
# green with zot dead. If this fails, the feeder pings unconditionally and the monitor is
# decorative.
echo ""
echo "--- T2: zot dead (no HTTP response), host alive => NO ping"
run_feeder 000 000
assert "T2 emits NO heartbeat ping" "[[ ! -s '$STUB_EMIT' ]]"
assert "T2 still probed zot (non-vacuous: the script ran)" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

# --- T3: THE test — private NIC absent, loopback still answers => NO ping ----------------
# #6400's exact shape. zot binds 0.0.0.0, so loopback answers 401 on a host holding no
# 10.0.1.30. A loopback implementation passes every other test and FAILS ONLY HERE.
echo ""
echo "--- T3: private NIC absent (000), loopback still answers 401 => NO ping"
run_feeder 000 401
assert "T3 emits NO heartbeat ping (loopback must not satisfy the probe)" "[[ ! -s '$STUB_EMIT' ]]"
assert "T3 never probed loopback at all" "! grep -qE 'localhost:5000|127\\.0\\.0\\.1:5000' '$STUB_PROBES'"
assert "T3 probed the private IP (non-vacuous)" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

# --- T4: wedged zot (5xx) => NO ping -----------------------------------------------------
# The case the original `-f` was reaching for, and it must survive -f's removal: a zot returning
# 503 is answering the socket but is not serving images. A distinct code path from T2 (a real
# HTTP response, not a connect failure), so this is not a duplicate of it.
echo ""
echo "--- T4: zot wedged (503) => NO ping"
run_feeder 503 503
assert "T4 emits NO heartbeat ping on 5xx" "[[ ! -s '$STUB_EMIT' ]]"
assert "T4 probed zot (non-vacuous)" "grep -q '$TEST_IP:5000' '$STUB_PROBES'"

# --- T5: the probe is bounded (behavioral, not a grep) -----------------------------------
# Proves -m is present ON THE PROBE by making the stub hang when it is absent: the outer
# `timeout 10` fires (rc 124) only if the feeder failed to bound its own probe. An unbounded
# probe against a 60s timer is the unit-stacking hazard the feeder's comment cites.
echo ""
echo "--- T5: the probe carries its own -m bound (stub hangs without it)"
STUB_HANG=1 run_feeder 401 401
STUB_HANG=0
assert "T5 the feeder completed (rc != 124 => the probe was -m bounded)" "[[ '$RUN_RC' != '124' ]]"
assert "T5 still emitted its ping" "[[ -s '$STUB_EMIT' ]]"

# --- #7270: per-boot counters that say WHY a beat was withheld ---------------------------
# The state is ONE line: `miss_cum ping_fail_cum ok_cum late_ok_cum last_miss_code last_ok_ts`.
# st <key> -> the value the feeder stored for <key> ("" when absent).
st() {
  local i
  case "$1" in
    miss_cum) i=1 ;; ping_fail_cum) i=2 ;; ok_cum) i=3 ;;
    late_ok_cum) i=4 ;; last_miss_code) i=5 ;; last_ok_ts) i=6 ;; *) return 1 ;;
  esac
  awk -v i="$i" 'NR == 1 { print $i }' "$STATE" 2>/dev/null
}
reset_state() { rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; }

echo ""
echo "--- L1: zot silent (000) => miss_cum=1, last_miss_code=000, no ping"
reset_state
run_feeder 000 000
assert "L1 no ping" "[[ ! -s '$STUB_EMIT' ]]"
assert "L1 miss_cum=1" "[[ \"\$(st miss_cum)\" == 1 ]]"
assert "L1 last_miss_code=000" "[[ \"\$(st last_miss_code)\" == 000 ]]"
assert "L1 ok_cum=0 and ping_fail_cum=0" "[[ \"\$(st ok_cum)\" == 0 && \"\$(st ping_fail_cum)\" == 0 ]]"
assert "L1 exit 0" "[[ '$RUN_RC' == 0 ]]"

echo ""
echo "--- L2: then zot wedged (503) => counters ACCUMULATE, code updates"
run_feeder 503 503
assert "L2 miss_cum=2 (read back, not reset)" "[[ \"\$(st miss_cum)\" == 2 ]]"
assert "L2 last_miss_code=503" "[[ \"\$(st last_miss_code)\" == 503 ]]"

echo ""
echo "--- L3: zot answers 401, ping OK => ok_cum+1, misses untouched"
run_feeder 401 401
assert "L3 pinged" "[[ -s '$STUB_EMIT' ]]"
assert "L3 ok_cum=1" "[[ \"\$(st ok_cum)\" == 1 ]]"
assert "L3 miss_cum still 2, code still 503" "[[ \"\$(st miss_cum)\" == 2 && \"\$(st last_miss_code)\" == 503 ]]"
assert "L3 ping_fail_cum=0" "[[ \"\$(st ping_fail_cum)\" == 0 ]]"
assert "L3 first OK after boot is never counted late" "[[ \"\$(st late_ok_cum)\" == 0 ]]"
assert "L3 last_ok_ts recorded as epoch seconds" "[[ \"\$(st last_ok_ts)\" =~ ^[0-9]{9,10}$ ]]"

echo ""
echo "--- L4: zot answers 401 but Better Stack answers the beat 429 => ping_fail_cum+1, ok_cum unchanged"
STUB_PING_CODE=429 run_feeder 401 401
STUB_PING_CODE=200
assert "L4 the ping was attempted" "[[ -s '$STUB_EMIT' ]]"
assert "L4 ping_fail_cum=1" "[[ \"\$(st ping_fail_cum)\" == 1 ]]"
assert "L4 ok_cum still 1" "[[ \"\$(st ok_cum)\" == 1 ]]"
assert "L4 miss_cum still 2 (zot DID answer)" "[[ \"\$(st miss_cum)\" == 2 ]]"
assert "L4 a failed beat clears last_ok_ts, so the recovery beat is not counted late" \
  "[[ \"\$(st last_ok_ts)\" == 0 ]]"

echo ""
echo "--- L5: an OK beat more than 75s after the previous OK => late_ok_cum+1; a prompt one does not"
reset_state
printf '0 0 4 0 none %s\n' "$(( $(date +%s) - 100 ))" > "$STATE"
run_feeder 401 401
assert "L5 late_ok_cum=1 after a 100s gap" "[[ \"\$(st late_ok_cum)\" == 1 ]]"
assert "L5 ok_cum=5" "[[ \"\$(st ok_cum)\" == 5 ]]"
run_feeder 401 401
assert "L5 a prompt next beat leaves late_ok_cum=1" "[[ \"\$(st late_ok_cum)\" == 1 ]]"
assert "L5 last_miss_code keeps the pre-miss token 'none'" "[[ \"\$(st last_miss_code)\" == none ]]"
# The threshold's edges: 80s is late, 70s is not.
printf '0 0 4 0 none %s\n' "$(( $(date +%s) - 80 ))" > "$STATE"
run_feeder 401 401
assert "L5 an 80s gap counts late" "[[ \"\$(st late_ok_cum)\" == 1 ]]"
printf '0 0 4 0 none %s\n' "$(( $(date +%s) - 70 ))" > "$STATE"
run_feeder 401 401
assert "L5 a 70s gap does not" "[[ \"\$(st late_ok_cum)\" == 0 ]]"
# A recovery beat after a miss is not late, however old the previous OK is.
printf '0 0 4 0 none %s\n' "$(( $(date +%s) - 500 ))" > "$STATE"
run_feeder 000 000
assert "L5 a miss clears last_ok_ts" "[[ \"\$(st last_ok_ts)\" == 0 ]]"
run_feeder 401 401
assert "L5 the recovery beat after a miss is not counted late" "[[ \"\$(st late_ok_cum)\" == 0 ]]"

echo ""
echo "--- L6: a corrupt state file => counters restart from 0, and the ping still fires"
printf '1x "x abc 0"0\n' > "$STATE"
run_feeder 401 401
assert "L6 pinged" "[[ -s '$STUB_EMIT' ]]"
assert "L6 ok_cum=1 (restarted from 0)" "[[ \"\$(st ok_cum)\" == 1 ]]"
assert "L6 miss_cum=0 (the hostile value was discarded)" "[[ \"\$(st miss_cum)\" == 0 ]]"
assert "L6 last_miss_code=none (the hostile code was discarded)" "[[ \"\$(st last_miss_code)\" == none ]]"
# A leading zero is octal to $(( )), and `08` is an arithmetic ERROR that would freeze the
# counters until reboot; the shape check resets it instead.
printf '08 0 0 0 none 0\n' > "$STATE"
run_feeder 000 000
assert "L6 a leading-zero field restarts from 0 (08 -> 0, +1 miss)" "[[ \"\$(st miss_cum)\" == 1 ]]"

echo ""
echo "--- L7: the state dir cannot be created => the ping still fires, exit 0"
rm -rf "$STATE_DIR"; : > "$STATE_DIR"
run_feeder 401 401
assert "L7 pinged although no state could be written" "[[ -s '$STUB_EMIT' ]]"
assert "L7 exit 0" "[[ '$RUN_RC' == 0 ]]"
rm -f "$STATE_DIR"; mkdir -p "$STATE_DIR"

echo ""
echo "--- L8: the state step runs AFTER the ping (PING precedes MV in the order log)"
reset_state
run_feeder 401 401
assert "L8 both the ping and the state write happened" \
  "[[ \"\$(grep -c -e PING -e MV '$STUB_ORDER')\" == 2 ]]"
assert "L8 the ping came first" "[[ \"\$(sed -n 1p '$STUB_ORDER')\" == PING ]]"

# --- STRUCTURAL --------------------------------------------------------------------------
echo ""
echo "--- structural assertions"

# A COMMENT-STRIPPED view is what makes the asserts below real, in BOTH directions. This
# feeder's comments necessarily NAME loopback (to explain why it is forbidden) and the private
# IP (to explain why it is required) — so a raw body-grep would false-FAIL the negative on
# prose, and false-PASS the positive on prose. Strip whole-line AND trailing comments, then
# assert on the surviving CODE: a comment cannot survive the strip, and a real call cannot be
# removed by it. See AGENTS.md — "narrowing is not anchoring; anchor on syntax".
CODE="$TMP/feeder.code.sh"
sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#[^"'"'"']*$//' "$RENDERED" > "$CODE"
assert "comment-strip left executable code behind (non-vacuous)" "[[ -s '$CODE' ]]"
assert "comment-strip removed the prose that names loopback" "! grep -q 'boot readiness loop' '$CODE'"

assert "feeder never issues a curl against loopback" \
  "! grep -qE 'curl.*(localhost|127\\.0\\.0\\.1):5000' '$CODE'"
assert "feeder probes the private IP via curl" \
  "grep -qE 'curl.*${TEST_IP_RE}:5000/v2/' '$CODE'"
# Scoped to the PROBE line, not the file: the ping curl's own -m would otherwise satisfy a
# file-wide grep and leave an unbounded probe green. T5 is the behavioral half of this.
assert "the PROBE curl carries its own -m bound" \
  "grep -E 'curl.*${TEST_IP_RE}:5000/v2/' '$CODE' | grep -cE -- >/dev/null '-m[[:space:]]+[0-9]+'"
# -f on an auth-gated /v2/ exits 22 on the 401 that means "alive", so an -f probe can never
# ping. This is the P1 regression guard; T1 is its behavioral half.
assert "the PROBE curl does NOT use -f (401 IS liveness; -f exits 22 on it)" \
  "! grep -E 'curl.*${TEST_IP_RE}:5000/v2/' '$CODE' | grep -cE -- >/dev/null '-f'"
assert "the feeder discriminates on the HTTP status code" \
  "grep -qF '%{http_code}' '$CODE' && grep -qE '200\\|401' '$CODE'"

# Delivery asserted on the write_files `- path:` construct — a syntactic anchor prose cannot
# forge — rather than a bare mention of the unit name anywhere in the file.
assert "systemd service unit is delivered" \
  "grep -qE '^[[:space:]]*- path: /etc/systemd/system/zot-liveness-heartbeat.service[[:space:]]*$' '$CI'"
assert "systemd timer unit is delivered" \
  "grep -qE '^[[:space:]]*- path: /etc/systemd/system/zot-liveness-heartbeat.timer[[:space:]]*$' '$CI'"
# The timer, not cron: cron's 60s floor leaves zero margin against the 60s period + 30s grace.
assert "timer fires every 60s" "grep -qE '^[[:space:]]*OnUnitActiveSec=60s[[:space:]]*$' '$CI'"
assert "timer arms shortly after boot" "grep -qE '^[[:space:]]*OnBootSec=[0-9]+s[[:space:]]*$' '$CI'"
assert "timer is enabled in runcmd" \
  "grep -qE '^[[:space:]]*- systemctl.*enable.*zot-liveness-heartbeat\\.timer' '$CI'"
# The CADENCE claim is executable too, not just the arming claim. Without AccuracySec, systemd
# defaults to 1min and the interval becomes 60s+delta (bound: 120s) against a 90s deadline —
# measured drift up to 72.6s on this unit shape. Deleting this line is a silent false-page
# regression on a no-SSH host, so it is asserted rather than trusted to a comment.
assert "timer pins AccuracySec (systemd defaults to 1min => up to 120s interval vs a 90s deadline)" \
  "grep -qE '^[[:space:]]*AccuracySec=1s[[:space:]]*$' '$CI'"
# (#7270) The service bounds its own run: a state step that hangs (a FIFO planted at the state
# path) must cost at most one tick, never wedge every later beat. Scoped to THIS unit's block,
# and bounded on both sides: above the two 10s curls, below the 60s timer period.
SVC_BLOCK="$(awk '/^  - path: \/etc\/systemd\/system\/zot-liveness-heartbeat\.service$/{f=1;next} f && /^  - path: /{exit} f' "$CI")"
SVC_TO="$(sed -n 's/^[[:space:]]*TimeoutStartSec=\([0-9]*\)s[[:space:]]*$/\1/p' <<<"$SVC_BLOCK")"
assert "the liveness service pins TimeoutStartSec between 20s and 60s (got '$SVC_TO')" \
  "[[ '$SVC_TO' =~ ^[0-9]+$ ]] && (( SVC_TO > 20 && SVC_TO < 60 ))"

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
