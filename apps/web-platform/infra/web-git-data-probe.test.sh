#!/usr/bin/env bash
# Tests the web-host git-data CONSUMER-perspective reachability probe (#6548,
# web-git-data-probe.sh). A fail-SOFT overlay: a single blip must never page, so the
# probe pings only on a real connect and stays silent (exit 0) otherwise.
#
# TWO layers (mirrors disk-monitor.test.sh's PATH-stub accumulator + the registry
# private-nic-guard.test.sh env-seam harness):
#   1. SEAM-DRIVEN classification: SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE injects the
#      connect result so both branches (ping / no-ping, both exit 0) are exercised
#      without a live git-data; SOLEUR_GIT_DATA_PROBE_PING_LOG re-routes the ping to a
#      file so ping/no-ping is directly observable.
#   2. BEHAVIORAL _reachable(): a real bounded connect against a localhost listener we
#      open (positive control — proves nc/`/dev/tcp` actually connects) and against a
#      closed port (127.0.0.1:1, immediate refusal — bounded, fast).
#
# ENV-DRIVEN plain bash: we EXECUTE the real .sh directly (no templatefile render).
# Pure bash + python3 + a loopback socket — no docker, network egress, or root.
#
# Run: bash apps/web-platform/infra/web-git-data-probe.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-git-data-probe.sh"
SVC="$SCRIPT_DIR/web-git-data-probe.service"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [[ -n "${LISTEN_PID:-}" ]] && kill "$LISTEN_PID" 2>/dev/null' EXIT

echo "=== web-host git-data consumer-probe (#6548) tests ==="
assert "web-git-data-probe.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"

# --- run helpers -------------------------------------------------------------------------
# EC = exit code, PINGED = yes|no (seam ping-log non-empty), OUT = combined output.
run_seam() {  # <reachable|unreachable>
  local override="$1" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE="$override" SOLEUR_GIT_DATA_PROBE_PING_LOG="$pinglog" \
    GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL \
    GIT_DATA_HEARTBEAT_URL="https://synthetic.invalid/beat/git-data" \
    bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

run_real() {  # <endpoint host:port> — real _reachable(), no override
  local endpoint="$1" pinglog outf ec=0
  pinglog="$(mktemp "$TMP/ping.XXXXXX")"; outf="$(mktemp "$TMP/out.XXXXXX")"
  GIT_DATA_ENDPOINT="$endpoint" SOLEUR_GIT_DATA_PROBE_PING_LOG="$pinglog" \
    GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL \
    GIT_DATA_HEARTBEAT_URL="https://synthetic.invalid/beat/git-data" \
    timeout 20 bash "$SUT" >"$outf" 2>&1 || ec=$?
  EC=$ec; PINGED=no; [[ -s "$pinglog" ]] && PINGED=yes; OUT="$(cat "$outf")"
}

# --- SEAM: reachable => ping + exit 0 ----------------------------------------------------
echo "--- seam: reachable => ping + exit 0 ---"
run_seam reachable
assert "reachable pings the heartbeat" "[[ '$PINGED' == yes ]]"
assert "reachable exits 0" "[[ '$EC' -eq 0 ]]"

# --- SEAM: unreachable => NO ping + exit 0 (fail-soft) -----------------------------------
echo "--- seam: unreachable => NO ping + exit 0 (fail-soft) ---"
run_seam unreachable
assert "unreachable does NOT ping (absence alarms)" "[[ '$PINGED' == no ]]"
assert "unreachable is fail-soft (exit 0, never pages inline)" "[[ '$EC' -eq 0 ]]"
assert "unreachable explains the suppression" "grep -q 'SUPPRESS ping' <<<\"\$OUT\""

# --- BEHAVIORAL: real _reachable() connects to a live loopback listener ------------------
echo "--- behavioral: real bounded connect against a live loopback listener ---"
PORT_FILE="$TMP/listen_port"
python3 - "$PORT_FILE" >/dev/null 2>&1 <<'PY' &
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
with open(sys.argv[1], "w") as f:
    f.write(str(s.getsockname()[1]))
# Accept-and-close so a connect-and-close probe completes cleanly; live for the suite.
t = time.time()
s.settimeout(1.0)
while time.time() - t < 40:
    try:
        c, _ = s.accept(); c.close()
    except socket.timeout:
        pass
PY
LISTEN_PID=$!
for _ in $(seq 1 100); do [[ -s "$PORT_FILE" ]] && break; sleep 0.1; done
assert "the loopback listener published its port" "[[ -s '$PORT_FILE' ]]"
LISTEN_PORT="$(cat "$PORT_FILE" 2>/dev/null || true)"

run_real "127.0.0.1:$LISTEN_PORT"
assert "real connect to the live listener => reachable => ping" "[[ '$PINGED' == yes ]]"
assert "real connect to the live listener => exit 0" "[[ '$EC' -eq 0 ]]"

# --- BEHAVIORAL: real _reachable() against a closed port (immediate refusal) -------------
# 127.0.0.1:1 is effectively never listening => connection refused instantly (bounded, fast).
# Positive control above proves the ping fires on a real connect, so this "no ping" is not vacuous.
echo "--- behavioral: real bounded connect against a closed port => no ping ---"
run_real "127.0.0.1:1"
assert "real connect to a closed port => unreachable => NO ping" "[[ '$PINGED' == no ]]"
assert "real connect to a closed port => fail-soft exit 0" "[[ '$EC' -eq 0 ]]"

# --- TRANSPORT (#9757): the heartbeat URL reaches curl on its stdin config, never on argv --------
# The seam above returns BEFORE the transport line, so nothing above ever executed it. This harness runs
# with the ping seam UNSET, a PATH curl stub and SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE=reachable. The stub
# records argv (`argv <words>`) and, for every `--config -` call, the stdin config's `url = "` line
# (`cfg <line>`); a call whose stdin carries no such line FAILS (rc 97, recorded as `cfg-MISSING`), so a
# SUT that dropped the config, or a stub that ignored stdin, cannot pass as a healthy ping. The first
# attempt can be made to fail (STUB_FAIL_FIRST=1) so the SECOND attempt must read its OWN fresh stdin: a
# process substitution is consumed once, and a shared one would hand attempt 2 an EOF (cfg-MISSING).
echo "--- transport: stdin config, per-attempt, shape guard (#9757) ---"
STUBDIR="$TMP/stub"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/curl" <<'STUB'
#!/usr/bin/env bash
printf 'argv %s\n' "$*" >> "$CURL_LOG"
n=$(( $(cat "$CURL_LOG.n" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$CURL_LOG.n"
case " $* " in
  *" --config - "*)
    line=""
    while IFS= read -r l || [ -n "$l" ]; do case "$l" in 'url = "'*) line="$l"; break ;; esac; done
    if [ -z "$line" ]; then printf 'cfg-MISSING\n' >> "$CURL_LOG"; exit 97; fi
    printf 'cfg %s\n' "$line" >> "$CURL_LOG" ;;
  *) printf 'cfg-MISSING\n' >> "$CURL_LOG"; exit 97 ;;
esac
if [ "${STUB_FAIL_FIRST:-}" = 1 ] && [ "$n" -eq 1 ]; then exit 7; fi
exit "${STUB_RC:-0}"
STUB
chmod +x "$STUBDIR/curl"

run_transport() {  # <url value> [extra env assignment...] — extra env may override the KEY default
  local url="$1" ec=0; shift
  CURL_LOG="$(mktemp "$TMP/curl.XXXXXX")"; : > "$CURL_LOG"; rm -f "$CURL_LOG.n"
  TOUT="$TMP/tout.$RANDOM"
  env GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL "$@" PATH="$STUBDIR:$PATH" CURL_LOG="$CURL_LOG" \
    SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE=reachable "GIT_DATA_HEARTBEAT_URL=$url" \
    bash "$SUT" >"$TOUT" 2>&1 || ec=$?
  TEC=$ec; TOUTTXT="$(cat "$TOUT")"
  N_ARGV="$(grep -c '^argv ' "$CURL_LOG" || true)"
  N_CFG="$(grep -c '^cfg url = "' "$CURL_LOG" || true)"
  N_MISSING="$(grep -c '^cfg-MISSING' "$CURL_LOG" || true)"
  N_MARK="$(grep -c 'SOLEUR_CREDENTIAL_REFUSED' "$TOUT" || true)"
}
GOOD='https://uptime.betterstack.test/api/v1/heartbeat/synthetic-token'

run_transport "$GOOD"
assert "healthy ping: exactly one curl call, exit 0" "[[ '$N_ARGV' -eq 1 && '$TEC' -eq 0 ]]"
assert "healthy ping: the stdin config carried the url line" "[[ '$N_CFG' -eq 1 && '$N_MISSING' -eq 0 ]]"
assert "healthy ping: the URL is NOT on curl's argv" "! grep -q '^argv .*betterstack' '$CURL_LOG'"
assert "healthy ping: argv is exactly the --disable --noproxy * -gfsS -m 10 -o /dev/null --config - form" \
  "grep -qxF 'argv --disable --noproxy * -gfsS -m 10 -o /dev/null --config -' '$CURL_LOG'"
assert "healthy ping: the recorded url line is the stored URL" "grep -qxF 'cfg url = \"$GOOD\"' '$CURL_LOG'"
assert "healthy ping: no marker, no WARN" "[[ '$N_MARK' -eq 0 ]] && ! grep -q WARN <<<\"\$TOUTTXT\""

# both attempts: the first fails, the second must read its OWN fresh stdin and succeed
run_transport "$GOOD" STUB_FAIL_FIRST=1
assert "retry: two curl calls, each with its own recorded url line (the second did not read EOF)" \
  "[[ '$N_ARGV' -eq 2 && '$N_CFG' -eq 2 && '$N_MISSING' -eq 0 ]]"
assert "retry: the second attempt succeeded, so no FAILED warning and exit 0" \
  "[[ '$TEC' -eq 0 ]] && ! grep -q 'ping FAILED' <<<\"\$TOUTTXT\""
run_transport "$GOOD" STUB_RC=7
assert "both attempts fail: two curl calls, one FAILED warning, still fail-soft exit 0" \
  "[[ '$N_ARGV' -eq 2 && '$N_CFG' -eq 2 && '$TEC' -eq 0 ]] && grep -q 'ping FAILED' <<<\"\$TOUTTXT\""

# SHAPE GUARD: zero requests and exactly one value-free marker, on every hostile or malformed value
hostile_row() {  # <label> <value> <reason>
  run_transport "$2"
  assert "guard refuses $1: zero curl calls, exactly one marker, exit 0 (fail-soft)" \
    "[[ '$N_ARGV' -eq 0 && '$N_MARK' -eq 1 && '$TEC' -eq 0 ]]"
  assert "guard refuses $1: marker names reason=$3 and the variable, not the value" \
    "grep -q 'SOLEUR_CREDENTIAL_REFUSED script=web-git-data-probe reason=$3 var=GIT_DATA_HEARTBEAT_URL\$' <<<\"\$TOUTTXT\" && ! grep -q 'betterstack' <<<\"\$TOUTTXT\""
}
hostile_row 'an embedded double quote' "${GOOD}\"" token_shape
hostile_row 'a quote then an injected directive (newline)' "${GOOD}
proxy = \"http://203.0.113.1:3128\"" control_char
hostile_row 'a trailing newline' "${GOOD}
" control_char
hostile_row 'a backslash' "${GOOD}\\x" token_shape
hostile_row 'an embedded space' "${GOOD} x" token_shape
hostile_row 'a hash' "${GOOD}#x" token_shape
hostile_row 'userinfo (@)' "https://u@uptime.betterstack.test/x" token_shape
hostile_row 'a scheme other than https' "http://uptime.betterstack.test/x" token_shape
hostile_row 'no scheme' "uptime.betterstack.test/x" token_shape
hostile_row 'a bare scheme (empty rest)' "https://" token_shape
hostile_row 'a whitespace-only value' " " token_shape
# unset URL is the pre-existing WARN arm (not a refusal): zero requests, no marker
run_transport ""
assert "empty URL: the existing WARN arm (zero curl calls, no marker, exit 0)" \
  "[[ '$N_ARGV' -eq 0 && '$N_MARK' -eq 0 && '$TEC' -eq 0 ]] && grep -q 'unset' <<<\"\$TOUTTXT\""
# a bare GIT_DATA_HEARTBEAT_URL with NO key resolves nothing (no bare-var fallback): the WARN arm
run_transport "$GOOD" GIT_DATA_HEARTBEAT_URL_KEY=
assert "bare var, no KEY: WARN arm (zero curl calls, no marker, exit 0); the key line names the KEY var, not the value" \
  "[[ '$N_ARGV' -eq 0 && '$N_MARK' -eq 0 && '$TEC' -eq 0 ]] && grep -q 'GIT_DATA_HEARTBEAT_URL unset' <<<\"\$TOUTTXT\" && grep -q 'GIT_DATA_HEARTBEAT_URL_KEY' <<<\"\$TOUTTXT\" && ! grep -q 'betterstack' <<<\"\$TOUTTXT\""
# must-PASS: a different well-formed token with every allowed punctuation class
run_transport 'https://uptime.betterstack.test/api/v1/heartbeat/A.b_c~d:9?x=1&y=%2B+z-Q'
assert "a well-formed URL with a different token pings once, on stdin only" \
  "[[ '$N_ARGV' -eq 1 && '$N_CFG' -eq 1 && '$N_MARK' -eq 0 ]] && ! grep -q '^argv .*A.b_c' '$CURL_LOG'"
# the seam still routes before the transport and still receives the (unguarded) argument
run_seam reachable
assert "seam still routes before the transport (ping log written, no curl needed)" "[[ '$PINGED' == yes && '$EC' -eq 0 ]]"

# --- #9639 F6: the unit stops expanding the secret; the script resolves it AFTER its refusal ----
# Same defect and fix as web-private-nic-guard / web-zot-consumer-probe / inngest-consumer-probe
# (#9639 / #10637 / #10363): the unit's ExecStart expanded GIT_DATA_HEARTBEAT_URL in an inner
# `bash -c` BEFORE the script could refuse to run under xtrace, so a traced launch
# (SHELLOPTS=xtrace propagating through `doppler run`, or a BASH_ENV `set -x`) printed the
# heartbeat URL to stderr -> journald -> off-box. The fix: the unit expands nothing and the
# script resolves the key-named variable AFTER an unconditional xtrace refusal (unconditional
# because this script's only launch context is `doppler run` and the env file always carries the
# key name — no credential-free mode exists). Rows mirror the inngest suite's F6 block.
echo "--- F6 (#9639): git-data probe unit wrapper expands nothing; lookup follows the refusal ---"
# shellcheck disable=SC2016  # the F6 conditions are single-quoted on purpose: assert() evals them in this shell
F6_URL='https://uptime.betterstack.test/api/v1/heartbeat/F6-SECRET-9639'
F6_TOK=F6-SECRET-9639
F6_SCRIPT_PATH=/usr/local/bin/web-git-data-probe.sh
F6_LINE="$(sed -n 's/^ExecStart=//p' "$SVC" | sed -n '1p' | sed 's/\$\$/$/g')"   # systemd's $$ is a literal $
# The pre-fix ExecStart, kept ONLY as the leak control's mutant (never compared with the tree).
F6_OLD_LINE="/bin/bash -c 'doppler run --project soleur --config prd -- bash -c '\\''export GIT_DATA_HEARTBEAT_URL=\"\${!GIT_DATA_HEARTBEAT_URL_KEY}\"; exec $F6_SCRIPT_PATH'\\'''"
F6_EXEC="$TMP/f6-exec-web-git-data-probe.sh"; cp "$SUT" "$F6_EXEC"; chmod +x "$F6_EXEC"
printf 'set -x\n' > "$TMP/f6-xt.env"
mkdir -p "$TMP/f6-stubbin"
# `doppler run ... -- CMD`: skip to the `--` and exec CMD. It never expands the secret itself (its own
# xtrace would print the value and void the leak control); the test env pre-exports it as doppler would.
printf '#!/usr/bin/env bash\nwhile [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n' > "$TMP/f6-stubbin/doppler"
# A recording curl: one argv line per call and, for a `--config -` call, that call's whole stdin;
# F6_HB_ENVDUMP set -> dump ITS environment (the not-exported / export-mutant rows).
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$F6_HB_ARGV"\n[ -z "${F6_HB_ENVDUMP:-}" ] || env > "$F6_HB_ENVDUMP"\ncase " $* " in\n  *" --config - "*) cat > "$F6_HB_STDIN" ;;\nesac\nexit 0\n' > "$TMP/f6-stubbin/curl"
chmod +x "$TMP/f6-stubbin/doppler" "$TMP/f6-stubbin/curl"
mkdir -p "$TMP/f6-dead"; printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/f6-dead/doppler"; chmod +x "$TMP/f6-dead/doppler"
F6_SEQ=0
run_unit() {   # <ExecStart text> <none|xtrace|benv> [extra env words, applied last] : script path rewritten to the (mutant) script
  local line="$1" form="$2" ec=0 sut="${F6_SUT:-$F6_EXEC}"; shift 2
  [[ "$line" == *"$F6_SCRIPT_PATH"* ]] || { printf '[FATAL] run_unit: the ExecStart text does not name %s; the rewrite would be a silent no-op\n' "$F6_SCRIPT_PATH" >&2; exit 1; }
  local -a fenv=()
  case "$form" in xtrace) fenv=(SHELLOPTS=xtrace) ;; benv) fenv=(BASH_ENV="$TMP/f6-xt.env") ;; esac
  F6_SEQ=$((F6_SEQ + 1))
  F6_HB_ARGV="$(mktemp "$TMP/f6argv.XXXXXX")"; F6_HB_STDIN="$(mktemp "$TMP/f6stdin.XXXXXX")"; HOUT="$(mktemp "$TMP/hbout.XXXXXX")"
  env -u SOLEUR_GIT_DATA_PROBE_PING_LOG -u SHELLOPTS -u BASH_ENV -u GIT_DATA_HEARTBEAT_URL -u GIT_DATA_HEARTBEAT_URL_KEY -u GIT_DATA_HEARTBEAT_URL_SYNTH \
    PATH="$TMP/f6-stubbin:$PATH" \
    F6_HB_ARGV="$F6_HB_ARGV" F6_HB_STDIN="$F6_HB_STDIN" \
    SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE=reachable \
    GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL_SYNTH GIT_DATA_HEARTBEAT_URL_SYNTH="$F6_URL" \
    ${fenv[@]+"${fenv[@]}"} "$@" \
    timeout 20 bash -c 'eval "$1"' _ "${line//"$F6_SCRIPT_PATH"/$sut}" >"$HOUT" 2>&1 || ec=$?
  HEC=$ec
  # shellcheck disable=SC2034  # read by NAME inside the assert() eval strings
  HOUTTXT="$(cat "$HOUT")"
  N_HB="$(grep -c . "$F6_HB_ARGV" 2>/dev/null || true)"
}
assert "F6 static: no Exec* directive of the git-data probe unit holds an indirect expansion" \
  '[[ "$(grep -cE "^[[:space:]]*Exec[A-Za-z]*=.*[$]{1,2}[{][!]" "$SVC" || true)" -eq 0 ]]'
assert "F6 static: ExecStart runs the probe directly under doppler run: names it, no dollar sign, no export" \
  '[[ "$F6_LINE" == *"$F6_SCRIPT_PATH"* && "$F6_LINE" != *\$* && "$F6_LINE" != *export* && "$F6_LINE" == *"doppler run"* ]]'
for f6_form in xtrace benv; do
  run_unit "$F6_LINE" "$f6_form"
  assert "F6 unit[$f6_form]: the real ExecStart exits 78 with the refusal on a non-trace line (the script RAN; got rc=$HEC)" \
    '[[ "$HEC" -eq 78 && "$(grep -v "^+" "$HOUT" | grep -c "refusing to run under xtrace" || true)" -ge 1 ]]'
  assert "F6 unit[$f6_form]: the heartbeat URL (and its secret path token) is in neither stream and no request was made" \
    '[[ "$HOUTTXT" != *"$F6_TOK"* && "$N_HB" -eq 0 ]]'
done
run_unit "$F6_OLD_LINE" xtrace
assert "F6 control: the PRE-FIX ExecStart under SHELLOPTS=xtrace prints the secret (the harness can see the defect; rc=$HEC)" \
  '[[ "$HOUTTXT" == *"$F6_TOK"* ]]'
run_unit "$F6_LINE" xtrace PATH="$TMP/f6-dead:$TMP/f6-stubbin:$PATH"
assert "F6 dispatch: with a doppler that never execs the probe there is NO refusal text (so the rows above discriminate)" \
  '[[ "$HOUTTXT" != *"refusing to run under xtrace"* && "$HEC" -eq 0 ]]'
run_unit "$F6_LINE" none
assert "F6 positive: the untraced real ExecStart resolves the key-named URL and delivers it to the heartbeat curl on its stdin config, once (rc=$HEC)" \
  '[[ "$HEC" -eq 0 && "$N_HB" -eq 1 && "$(cat "$F6_HB_STDIN")" == "url = \"$F6_URL\"" ]]'
run_unit "$F6_LINE" none GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL GIT_DATA_HEARTBEAT_URL="$F6_URL"
assert "F6 production-shaped identity key [GIT_DATA_HEARTBEAT_URL] resolves and delivers" \
  '[[ "$N_HB" -eq 1 && "$(cat "$F6_HB_STDIN")" == "url = \"$F6_URL\"" ]]'
run_unit "$F6_LINE" none GIT_DATA_HEARTBEAT_URL="https://uptime.betterstack.test/api/v1/heartbeat/STRAY-9639" GIT_DATA_HEARTBEAT_URL_KEY= GIT_DATA_HEARTBEAT_URL_SYNTH=
assert "F6 no-key: a bare exported GIT_DATA_HEARTBEAT_URL without the KEY name resolves nothing (exit 0, WARN arm, no curl)" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL unset"* && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL_KEY"* ]]'
run_unit "$F6_LINE" xtrace GIT_DATA_HEARTBEAT_URL_KEY= GIT_DATA_HEARTBEAT_URL_SYNTH=
assert "F6 unconditional: a traced launch with NO credential set still refuses (rc=$HEC)" \
  '[[ "$HEC" -eq 78 && "$HOUTTXT" == *"refusing to run under xtrace"* ]]'
F6_PLANT="$TMP/f6-plant"; rm -f "$F6_PLANT"
run_unit "$F6_LINE" none "GIT_DATA_HEARTBEAT_URL_KEY=a[\$(touch $F6_PLANT)]"
assert "F6 hostile key a[\$(touch ...)]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
  '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL_KEY"* && "$HOUTTXT" != *touch* ]]'
run_unit "$F6_LINE" none "GIT_DATA_HEARTBEAT_URL_KEY=lowercase"
assert "F6 lowercase key: refused, no heartbeat, a KEY_BAD line, exit 0" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL_KEY"* ]]'
# Upper-case-led hostile keys: these exercise _key_ok's BODY clause (`*[!A-Z0-9_]*` — the one that
# stops the bytes bash evaluates inside ${!name}: array subscripts, command substitutions). Both
# rows above are lowercase-led and die in the lead clause, so without this table a mutant dropping
# the body clause ships green (the zot/inngest suites' body-clause tables are the shape).
for f6_k in "A[\$(touch $F6_PLANT)]" "A[0]" "A=B" "A.B" "A/B"; do
  rm -f "$F6_PLANT"; run_unit "$F6_LINE" none "GIT_DATA_HEARTBEAT_URL_KEY=$f6_k"
  assert "F6 body-clause key [$f6_k]: nothing executed, no heartbeat, a key line that does not echo the name, exit 0" \
    '[[ ! -e "$F6_PLANT" && "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL_KEY"* && "$HOUTTXT" != *"$f6_k"* ]]'
done
# _key_ok is the FOURTH copy; each sibling suite's parity row binds only pairwise. Pin this copy to
# all three siblings — the file's own comment predicates safety on byte-identity.
assert "F6 parity: _key_ok is byte-identical to the zot, nic-guard AND inngest copies" \
  '[[ "$(grep -m1 "^_key_ok()" "$SUT")" == "$(grep -m1 "^_key_ok()" "$SCRIPT_DIR/web-zot-consumer-probe.sh")" && "$(grep -m1 "^_key_ok()" "$SUT")" == "$(grep -m1 "^_key_ok()" "$SCRIPT_DIR/web-private-nic-guard.sh")" && "$(grep -m1 "^_key_ok()" "$SUT")" == "$(grep -m1 "^_key_ok()" "$SCRIPT_DIR/inngest-consumer-probe.sh")" ]]'
# A valid key name whose variable is UNSET resolves to "" -> the WARN arm, exit 0 (the last input
# cell: empty KEY, invalid KEY, stray URL without key, and unset named var).
run_unit "$F6_LINE" none GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL_UNSETVAR GIT_DATA_HEARTBEAT_URL_SYNTH=
assert "F6 unset-named-var key: resolves to empty, WARN arm, no heartbeat, exit 0" \
  '[[ "$N_HB" -eq 0 && "$HEC" -eq 0 && "$HOUTTXT" == *"GIT_DATA_HEARTBEAT_URL unset"* ]]'
# Every Exec* directive of the unit (backslash continuations joined, as systemd reads them) is
# dollar-free and export-free — a future ExecStartPre must not be able to smuggle a plain-$ expansion
# past the ExecStart-only static rows.
F6_ALLEXEC="$(awk '{ if (sub(/\\$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' "$SVC" | grep -E '^[[:space:]]*Exec[A-Za-z]*=' || true)"
assert "F6 static: EVERY Exec* directive of the git-data probe unit (continuations joined) is dollar-free and export-free" \
  '[[ -n "$F6_ALLEXEC" && "$F6_ALLEXEC" != *\$* && "$F6_ALLEXEC" != *export* ]]'
# `unset URL; URL=""` (the resolve block) drops an inherited export attribute so the resolved secret
# cannot ride child environments: the heartbeat curl's environ must hold the URL ONLY under the
# doppler-injected key-named variable.
F6_ENVD="$TMP/f6-envdump"; rm -f "$F6_ENVD"
run_unit "$F6_LINE" none F6_HB_ENVDUMP="$F6_ENVD"
assert "F6 not exported: the resolved URL reaches no child environment (only the injected key-named variable holds it)" \
  '[[ -s "$F6_ENVD" && "$(grep -v "^GIT_DATA_HEARTBEAT_URL_SYNTH=" "$F6_ENVD" | grep -cF -- "$F6_URL" || true)" -eq 0 && "$(grep -cF -- "$F6_URL" "$F6_ENVD" || true)" -eq 1 ]]'
F6_MUT_EXP="$TMP/f6-mut-export.sh"; sed 's/^URL=""$/export URL=""/' "$SUT" > "$F6_MUT_EXP"; chmod +x "$F6_MUT_EXP"
assert "F6 mutant[export]: the edit landed (the copy differs from the SUT)" '! cmp -s "$SUT" "$F6_MUT_EXP"'
rm -f "$F6_ENVD"
F6_SUT="$F6_MUT_EXP" run_unit "$F6_LINE" none F6_HB_ENVDUMP="$F6_ENVD"
assert "F6 mutant[export]: an exported URL DOES ride the heartbeat curl's environment (the not-exported row can see it)" \
  '[[ -s "$F6_ENVD" && "$(grep -c "^URL=" "$F6_ENVD" || true)" -ge 1 && "$(grep "^URL=" "$F6_ENVD" | grep -cF -- "$F6_URL" || true)" -eq 1 ]]'
# Preset URL: an exported `URL` inherited from the environment — `unset URL` is the load-bearing
# line this row discriminates (deleting it ships green and exports the preset; the sibling suites
# carry the same arm).
rm -f "$F6_ENVD"
run_unit "$F6_LINE" none URL='https://uptime.betterstack.test/api/v1/heartbeat/PRESET-9639' F6_HB_ENVDUMP="$F6_ENVD"
assert "F6 preset URL: an exported URL inherited from the environment does not ride the heartbeat curl's environment (unset URL is load-bearing)" \
  '[[ -s "$F6_ENVD" && "$(grep -c "^URL=" "$F6_ENVD" || true)" -eq 0 && "$N_HB" -eq 1 ]]'
# Order: a mutant that resolves the URL above the refusal leaks it under SHELLOPTS=xtrace.
F6_MUT="$TMP/f6-mut-hoist-gitdata.sh"
sed '/^set -u$/a\
__leak="${!GIT_DATA_HEARTBEAT_URL_KEY:-}"' "$SUT" > "$F6_MUT"; chmod +x "$F6_MUT"
assert "F6 mutant[hoist]: the edit landed (the copy differs from the SUT)" '! cmp -s "$SUT" "$F6_MUT"'
F6_SUT="$F6_MUT" run_unit "$F6_LINE" xtrace
assert "F6 mutant[hoist]: a lookup hoisted above the refusal leaks the URL under SHELLOPTS=xtrace (the order row can see it)" '[[ "$HOUTTXT" == *"$F6_TOK"* ]]'
f6g_line_of() { awk -v n="$1" 'index($0, n) && $0 !~ /^[[:space:]]*#/ { print NR; exit }' "$SUT"; }   # first NON-comment line holding the text
assert "F6 order: the indirect lookup is on a later line than the refusal" \
  '[[ -n "$(f6g_line_of "refusing to run under xtrace")" && "$(f6g_line_of "\${!GIT_DATA_HEARTBEAT_URL_KEY")" -gt "$(f6g_line_of "refusing to run under xtrace")" ]]'

# --- static drift-guard: doppler-auth unit-start contract (#6548 unit-start fix) ----------
# The unit runs `doppler run` as ROOT. Without Environment=HOME=/root the doppler CLI's
# os.UserHomeDir() init dies "$HOME is not defined" BEFORE it exec's the probe; without a
# DOPPLER_TOKEN in the per-host env file it cannot authenticate. Both gaps together made the
# unit fail to start on web-1 (delivered-but-inert). Assert both, and that the fix does not
# re-open the #6536 /tmp/.doppler ownership clash surface.
echo "--- static: doppler-auth unit-start contract ---"
SERVER_TF="$SCRIPT_DIR/server.tf"
assert "git-data .service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert "git-data .service does NOT source webhook-deploy (deploy-owned; imports /tmp/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'webhook-deploy' >/dev/null"
assert "git-data .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'DOPPLER_CONFIG_DIR' >/dev/null"
assert "git-data .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c '/tmp/.doppler' >/dev/null"
assert "git-data .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -cE '^PrivateTmp=true' >/dev/null '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal (test-design review).
assert "server.tf git_data_probe_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-git-data-probe" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-git-data-probe' '$SERVER_TF'"

echo
echo "=== $PASS passed, $FAIL failed ==="
# Anti-vacuity floor: a skipped block or a disarmed assert() must not read as green. Raise it in the SAME edit that adds
# rows; it is reported with printf and exit, never through assert() (scripts/guard-vacuity-floor.test.sh builds its mutant
# from the literal sitting directly above the `if`).
MIN_ASSERTS=82
if [[ "$((PASS + FAIL))" -lt "$MIN_ASSERTS" ]]; then
  printf 'FAIL: only %s assertions ran (floor %s) — a block was skipped or assert() was disarmed\n' "$((PASS + FAIL))" "$MIN_ASSERTS"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
