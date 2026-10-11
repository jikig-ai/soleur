#!/usr/bin/env bash
# Harness for inngest-probe-heartbeat-feeder.sh (#9703, Guard 1 and the wiring half of Guard 2).
#
# WHAT THE VERIFIER IS. It beats betteruptime_heartbeat.inngest_server_probe ONLY while the newest
# host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row is at most 4500 s old, the heartbeat resolves
# uniquely and is unpaused. The failure this suite exists to stop is a SPURIOUS BEAT: a feeder that
# keeps the heartbeat fed while the probe is dead suppresses the one alarm that backs the wrong-volume
# alert. Exit 0 must mean exactly {beat, fresh_heartbeat_paused}.
#
# THE FAKE TREE. The verifier is copied to $root/scripts/ and resolves its repo from its own location,
# so the stub scripts/betterstack-query.sh and the shared lib at $root/scripts/lib are what it reads.
# It runs under `env -i` with a PRIVATE PATH ($root/bin holds only a stub curl and symlinks to the
# tools it needs), and a canary proves curl resolves inside it. The stub curl models EXACTLY two
# request shapes (the API GET and the beat) and refuses anything else with status 64 and a line in
# its call log; every case asserts there is no refusal line. A beat is any curl call that is not the
# API GET, so an unconditional beater is caught even if it changes shape. The stub helper asserts its
# argv by exact value and deliberately IGNORES --grep, so the verifier's own predicate is what the
# row fixtures test.
#
# THE CLOCK IS PINNED (INNGEST_FEEDER_NOW). Values are synthesized (cq-test-fixtures-synthesized-only).
#
# MUTATIONS ARE COMMITTED, NOT HAND-RUN. M1-M7 are applied to scratch copies, asserted to have LANDED
# inside the target region, and expected to red; a known-positive and a known-negative run prove the
# red-detector first. M8-M11 are covered by their fixtures.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PROBE_NAME="inngest-probe-heartbeat-feeder.sh"
PROBE_SRC="$HERE/$PROBE_NAME"
LIB_SRC="$REPO/scripts/lib/inngest-probe-row.sh"
WORKFLOW="$REPO/.github/workflows/scheduled-inngest-probe-heartbeat.yml"
TABLE="$REPO/apps/web-platform/server/watchdog-dispatch-table.ts"
UPTIME_TF="$REPO/apps/web-platform/infra/uptime-alerts.tf"

fails=0
passes=0
cases=0
beat_asserts=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE_SRC" ]] || { echo "FATAL: verifier not found at $PROBE_SRC" >&2; exit 1; }
[[ -f "$LIB_SRC" ]] || { echo "FATAL: probe-row lib not found at $LIB_SRC" >&2; exit 1; }

# Canonical guard, copied byte-for-byte from plugins/soleur/test/test-helpers.sh.
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
WORK="$(mktemp -d "${TMPDIR}/inngest-probe-heartbeat-feeder.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/fx" "$WORK/mut"

BASH_BIN="$(type -P bash)"
# ── fabricated identities and the pinned clock ────────────────────────────────────────────────
NOW="2026-10-11T12:00:00Z"
NOW_EPOCH="$(date -u -d "$NOW" +%s)"
TOKEN="SYNTHtokenAbCdEf0123456789xyz"
HB_URL="https://uptime.betterstack.com/api/v1/heartbeat/SYNTHping9Xk2Zq"
HB_ID_SENTINEL="SYNTHping9Xk2Zq"
FAKE_CRED="dp.ct.NOT_A_REAL_TOKEN_9703_synthetic"
Q_PASS="pw-SYNTH-9f2c1d7a"
Q_USER="user-SYNTH-77aa"
NAME="soleur-inngest-server-probe-prd"

# ── fixture builders ──────────────────────────────────────────────────────────────────────────
dt_ago() { date -u -d "@$((NOW_EPOCH - $1))" '+%Y-%m-%d %H:%M:%S.000000'; }
dt_ago_t() { date -u -d "@$((NOW_EPOCH - $1))" '+%Y-%m-%dT%H:%M:%S.000000'; }
msg() { # <host_role> [tail]
  printf 'SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active redis_active=active uptime_s=900 boot_id=synthetic probe_schema=8 host_role=%s%s' "$1" "${2:+ $2}"
}
row() { # <dt> <message> [host] [host_name] [emitter] -> one JSONEachRow line with the double-encoded raw
  jq -cn --arg dt "$1" --arg m "$2" --arg h "${3:-soleur-inngest}" --arg hn "${4:-soleur-inngest-prd}" --arg e "${5:-inngest-server-probe}" \
    '{dt: $dt, raw: ({host: $h, host_name: $hn, SYSLOG_IDENTIFIER: $e, message: $m} | tojson)}'
}
ded() { row "$(dt_ago "$1")" "$(msg dedicated)"; }                            # <age_s>
fx() { cat > "$WORK/fx/$1.jsonl"; printf '%s' "$WORK/fx/$1.jsonl"; }
hb_json() { # <name> <paused-literal|__absent__> <url> -> one-heartbeat API body
  jq -cn --arg n "$1" --arg p "$2" --arg u "$3" '
    {data: [{id: "504655", type: "heartbeat",
      attributes: ({name: $n, url: $u, period: 3600, grace: 1800, status: "paused"}
        + (if $p == "__absent__" then {} else {paused: ($p | fromjson)} end))}], pagination: {}}'
}
api_ok_paused()   { hb_json "$NAME" false "$HB_URL"; }
api_ok_unpaused() { hb_json "$NAME" false "$HB_URL"; }
api_paused()      { hb_json "$NAME" true "$HB_URL"; }

# ── the runner ────────────────────────────────────────────────────────────────────────────────
# Per-case seams (reset_case clears them):
#   C_ROWS    fixture rows file the stub helper cats       C_STUB   ok | fail | garbage | none
#   C_API     API body file (default: unpaused heartbeat)  C_APIMODE ok | fail
#   C_BEATMODE 200 | 500 | 302 | curlfail                  C_NOW    INNGEST_FEEDER_NOW (or __unset__ | raw)
#   C_TOKEN   __unset__ | value                            C_UNSET  a BETTERSTACK_QUERY_* to blank
#   C_LIB     lib file copied into the tree (__none__ skips) C_LIBENV INNGEST_PROBE_ROW_LIB value
#   C_XTRACE  1 -> bash -x                                 C_ARGS   argv for the verifier
#   C_PROBE   verifier source (default shipped)            C_BEATS / C_APIS expected call counts
reset_case() {
  C_ROWS="/dev/null"; C_STUB="ok"; C_API=""; C_APIMODE="ok"; C_BEATMODE="200"; C_NOW="$NOW"
  C_TOKEN="$TOKEN"; C_UNSET=""; C_LIB="$LIB_SRC"; C_LIBENV=""; C_XTRACE=0; C_ARGS=""
  C_PROBE="$PROBE_SRC"; C_BEATS=0; C_APIS=0; C_REQUIRE=""; C_EXPECT_URL="$HB_URL"
}
reset_case

OUT="$WORK/out"
# Static: run_probe executes inside a command substitution, so a variable it assigned would not survive.
CALLS="$WORK/root/calls.log"
write_stubs() { # <root>
  local root="$1"
  assert_fixture_dir "$root"
  mkdir -p "$root/bin" "$root/scripts/lib"
  local t p
  for t in jq date grep sed tr cut head tail sort wc mktemp rm cat dirname bash env; do
    p="$(type -P "$t")" || { echo "FATAL: $t not found" >&2; exit 1; }
    ln -s "$p" "$root/bin/$t"
  done
  cat > "$root/bin/curl" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
LOG="\$R/calls.log"
argv="\$*"
stdin="\$(cat)"
tok="\$(cat "\$R/token.txt")"
A_ARGV='--disable --noproxy * -fsS --max-time 20 --config - https://uptime.betterstack.com/api/v2/heartbeats?per_page=250'
B_ARGV='--disable --noproxy * -fsS --max-time 15 -o /dev/null -w %{http_code} --config -'
if [[ "\$argv" == "\$A_ARGV" ]]; then
  if [[ "\$stdin" != "header = \"Authorization: Bearer \$tok\"" ]]; then echo "refused api-stdin" >> "\$LOG"; exit 64; fi
  echo api >> "\$LOG"
  [[ "\$(cat "\$R/api.mode")" == fail ]] && exit 7
  cat "\$R/api.body"
  exit 0
elif [[ "\$argv" == "\$B_ARGV" ]]; then
  echo beat >> "\$LOG"
  exp="\$(cat "\$R/expect_url")"
  if [[ "\$stdin" != "url = \"\$exp\"" ]]; then echo "refused beat-stdin" >> "\$LOG"; exit 64; fi
  case "\$(cat "\$R/beat.mode")" in
    200) printf 200; exit 0 ;;
    500) printf 500; exit 22 ;;
    302) printf 302; exit 0 ;;
    *)   exit 7 ;;
  esac
fi
echo "refused argv" >> "\$LOG"
exit 64
STUB
  chmod +x "$root/bin/curl"
}

run_probe() { # -> echoes the status; combined output in $OUT
  local root="$WORK/root" probe
  probe="$root/scripts/$PROBE_NAME"
  case "$root" in "$WORK"/root) rm -rf -- "$root" ;; *) echo 199; return ;; esac
  write_stubs "$root"
  cp "$C_PROBE" "$probe"
  if [[ "$C_LIB" != "__none__" ]]; then cp "$C_LIB" "$root/scripts/lib/inngest-probe-row.sh"; fi
  : > "$CALLS"
  printf '%s' "$TOKEN" > "$root/token.txt"
  printf '%s' "$C_EXPECT_URL" > "$root/expect_url"
  printf '%s' "$C_APIMODE" > "$root/api.mode"
  printf '%s' "$C_BEATMODE" > "$root/beat.mode"
  if [[ -n "$C_API" ]]; then cp "$C_API" "$root/api.body"; else api_ok_unpaused > "$root/api.body"; fi

  if [[ "$C_STUB" != "none" ]]; then
    cat > "$root/scripts/betterstack-query.sh" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
argv="\$*"
echo "\$argv" >> "\$R/helper.log"
# Asserted as the EXACT argument list: a substring check lets a suffixed grep value or a repeated
# --since/--limit (the helper keeps the last one) pass silently.
[[ "\$argv" == "--since 2h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500" ]] || { echo "STUB: unexpected argv: \$argv" >&2; exit 64; }
case "$C_STUB" in
  fail)
    echo "betterstack-query: auth failed for user=$Q_USER password=$FAKE_CRED" >&2
    echo "curl: (22) https://stub/?token=$FAKE_CRED"
    exit 7 ;;
  garbage)
    echo "<html>502 Bad Gateway</html>"
    echo "Code: 62. DB::Exception: Syntax error"
    exit 0 ;;
esac
# --grep is IGNORED on purpose; every fixture row comes back.
cat "$C_ROWS"
STUB
    chmod +x "$root/scripts/betterstack-query.sh"
  fi

  local -a envv=(PATH="$root/bin" HOME="$HOME" TMPDIR="$TMPDIR")
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ "$C_UNSET" == "$v" ]]; then
      envv+=("$v=")
    else
      case "$v" in
        BETTERSTACK_QUERY_PASSWORD) envv+=("$v=$Q_PASS") ;;
        BETTERSTACK_QUERY_USERNAME) envv+=("$v=$Q_USER") ;;
        *) envv+=("$v=stub.example") ;;
      esac
    fi
  done
  [[ "$C_TOKEN" == "__unset__" ]] || envv+=("BETTERSTACK_API_TOKEN_READONLY=$C_TOKEN")
  case "$C_NOW" in
    __unset__) : ;;
    *) envv+=("INNGEST_FEEDER_NOW=$C_NOW") ;;
  esac
  [[ -z "$C_LIBENV" ]] || envv+=("INNGEST_PROBE_ROW_LIB=$C_LIBENV")
  local -a sh=("$BASH_BIN")
  [[ "$C_XTRACE" == "1" ]] && sh=("$BASH_BIN" -x)
  # shellcheck disable=SC2086
  env -i "${envv[@]}" "${sh[@]}" "$probe" $C_ARGS >"$OUT" 2>&1
  echo $?
}

markers_of() { grep -oE 'verdict=[a-z_]+' "$OUT" | cut -d= -f2 | paste -sd, - || true; }
count_calls() { # <pattern>
  { grep -cE "$1" "$CALLS" 2>/dev/null || true; } | head -1
}

# The generic invariant: exit 0 if and only if the verdict is beat or fresh_heartbeat_paused.
assert_exit_zero_iff_fed() { # <rc> <verdict-token> <label>
  local good=0
  [[ "$2" == beat || "$2" == fresh_heartbeat_paused ]] && good=1
  if [[ "$1" == "0" && "$good" != 1 ]] || [[ "$1" != "0" && "$good" == 1 ]]; then
    fail "INVARIANT: rc=$1 with verdict=$2 ($3) — exit 0 must mean exactly {beat, fresh_heartbeat_paused}"
    return 1
  fi
  return 0
}

expect() { # <name> <rc> <verdict> [reason-or-extra-token]
  cases=$((cases + 1))
  local name="$1" want="$2" verdict="$3" extra="${4:-}" got ok=1 all
  got="$(run_probe)"
  [[ -s "$OUT" ]] || { fail "$name — the verifier produced NO output; did it run?"; return; }
  all="$(cat "$OUT")"
  assert_exit_zero_iff_fed "$got" "$verdict" "$name" || return
  [[ "$got" == "$want" ]] || ok=0
  grep -qE "verdict=${verdict}( |\$)" "$OUT" || ok=0
  if [[ -n "$extra" ]] && ! grep -qF -- "$extra" "$OUT"; then
    ok=0; printf '        | missing required token: %s\n' "$extra" >&2
  fi
  local beats apis refused
  beats=$(( $(count_calls '^beat$') + $(count_calls '^refused argv$') ))
  apis="$(count_calls '^api$')"
  refused="$(count_calls '^refused')"
  beat_asserts=$((beat_asserts + 1))
  if [[ "$beats" != "$C_BEATS" ]]; then ok=0; printf '        | beat calls: expected %s, saw %s\n' "$C_BEATS" "$beats" >&2; fi
  if [[ "$apis" != "$C_APIS" ]]; then ok=0; printf '        | API calls: expected %s, saw %s\n' "$C_APIS" "$apis" >&2; fi
  if [[ "$refused" != 0 ]]; then ok=0; printf '        | the stub curl REFUSED %s call(s): %s\n' "$refused" "$(grep '^refused' "$CALLS" | paste -sd, -)" >&2; fi
  # No secret, bearer, URL or helper error text anywhere: stdout, stderr and every argv log.
  local s
  for s in "$TOKEN" "$HB_ID_SENTINEL" "$FAKE_CRED" "$Q_PASS" "$Q_USER"; do
    if grep -qF -- "$s" <<<"$all" || grep -qF -- "$s" "$CALLS" || { [[ -f "$WORK/root/helper.log" ]] && grep -qF -- "$s" "$WORK/root/helper.log"; }; then
      ok=0; printf '        | a secret-shaped sentinel leaked into output or an argv log\n' >&2
    fi
  done
  if [[ "$C_XTRACE" != "1" ]] && grep -qiE '\bexit' <<<"$all"; then
    ok=0; printf '        | human-readable output contains the word "exit"\n' >&2
  fi
  if (( ok )); then
    pass "$name (status $got, verdict $verdict)"
  else
    fail "$name — expected status $want + verdict=$verdict, got status $got [$(markers_of)]"
    sed 's/^/        | /' "$OUT" >&2
  fi
}

# ── self-tests of the machinery ───────────────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass "SELFTEST pass() moves its counter"
fail "SELFTEST fail() moves its counter (expected, reversed below)" 2>/dev/null
assert_exit_zero_iff_fed 0 query_failed SELFTEST 2>/dev/null
if (( passes != _p0 + 1 || fails != _f0 + 2 )); then
  echo "FATAL: the verdict helpers do not move their counters — every assertion below is unbacked." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo "== private PATH canary =="
cases=$((cases + 1))
reset_case; _c="$(run_probe)"
if [[ "$(PATH="$WORK/root/bin" type -P curl)" == "$WORK/root/bin/curl" ]]; then pass "canary: curl resolves inside the private PATH"
else fail "canary: curl resolves OUTSIDE the private PATH"; fi
cases=$((cases + 1))
if ! PATH="$WORK/root/bin" type -P nc >/dev/null 2>&1 && ! PATH="$WORK/root/bin" type -P wget >/dev/null 2>&1; then pass "canary: no other network client on the private PATH"
else fail "canary: nc or wget is reachable from the private PATH"; fi

echo "== static: exit contract =="
allowlist_violations() { # <file> -> "line:token" for every exit token not followed by 0|3|4|64|78
  sed -E 's/^[[:space:]]*#.*$//' "$1" \
    | grep -noE "\bexit\b[[:space:]]*[^[:space:];)'\"]*" \
    | sed -E 's/[[:space:]]+$//' \
    | grep -vE ':exit[[:space:]]+(0|3|4|64|78)$' || true
}
last_nonblank() { grep -vE '^[[:space:]]*$' "$1" | tail -1; }
printf '#!/usr/bin/env bash\nexit 0\nfoo; exit 1\nexit "$rc"\n' > "$WORK/scan-positive.sh"
cases=$((cases + 1))
_v="$(allowlist_violations "$WORK/scan-positive.sh")"
if [[ "$_v" == $'3:exit 1\n4:exit' ]]; then pass "scanner known-positive: flags exit 1 and a bare/variable exit"
else fail "scanner known-positive: got [$_v]"; fi
cases=$((cases + 1))
_v="$(allowlist_violations "$PROBE_SRC")"
if [[ -z "$_v" ]]; then pass "verifier: every exit token is in {0,3,4,64,78}"
else fail "verifier: non-allowlisted exit token(s): $_v"; fi
cases=$((cases + 1))
if [[ "$(last_nonblank "$PROBE_SRC")" == "exit 3" ]]; then pass "verifier: last non-blank line is literally 'exit 3'"
else fail "verifier: last non-blank line is '$(last_nonblank "$PROBE_SRC")', not 'exit 3'"; fi
STRIPPED="$(sed -E 's/^[[:space:]]*#.*$//' "$PROBE_SRC")"
cases=$((cases + 1))
if grep -qxF 'trap on_exit EXIT' "$PROBE_SRC" && [[ "$(grep -cE '(^|[;&|[:space:]])trap[[:space:]]' <<<"$STRIPPED" || true)" == 1 ]]; then pass "verifier: exactly one trap statement, the EXIT trap"
else fail "verifier: expected exactly one 'trap on_exit EXIT'"; fi
cases=$((cases + 1))
if ! grep -qE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' <<<"$STRIPPED"; then pass "verifier: no exec or kill (both bypass the EXIT trap's remap)"
else fail "verifier: exec/kill found"; fi
cases=$((cases + 1))
if grep -qE '^set -uo pipefail$' "$PROBE_SRC" && ! grep -qE '^set -e' "$PROBE_SRC"; then pass "verifier uses set -uo pipefail, never -e"
else fail "verifier must use 'set -uo pipefail' and no -e"; fi
cases=$((cases + 1))
if [[ -x "$PROBE_SRC" ]]; then pass "verifier is executable"; else fail "verifier is not executable"; fi
cases=$((cases + 1))
if grep -qF 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' "$PROBE_SRC" && ! grep -q 'rev-parse' "$PROBE_SRC"; then pass "verifier resolves REPO_ROOT from its own location"
else fail "verifier must derive REPO_ROOT from BASH_SOURCE, not git"; fi

echo "== static: one beat call site =="
cases=$((cases + 1))
if [[ "$(grep -cE "%\{http_code\}" <<<"$STRIPPED" || true)" == 1 ]]; then pass "exactly one curl carries the beat write-out"
else fail "expected exactly one beat curl, found $(grep -cE "%\{http_code\}" <<<"$STRIPPED" || true)"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^[[:space:]]*beat_once$' <<<"$STRIPPED" || true)" == 1 && "$(grep -cE '^beat_once\(\) \{' <<<"$STRIPPED" || true)" == 1 ]]; then pass "beat_once is defined once and called once"
else fail "beat_once must be defined once and called once"; fi
cases=$((cases + 1))
# The beat is called after the freshness and resolution checks, in the main flow.
_m="$(grep -nxE 'check_freshness|resolve_heartbeat|beat_once' <<<"$STRIPPED" | cut -d: -f2 | paste -sd, -)"
if [[ "$_m" == "check_freshness,resolve_heartbeat,beat_once" ]]; then pass "main flow order: check_freshness, resolve_heartbeat, beat_once"
else fail "main flow order is [$_m]"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '\| curl --disable' <<<"$STRIPPED" || true)" == 2 ]]; then pass "exactly two curl invocations (API GET and beat)"
else fail "expected exactly two curl invocations, found $(grep -cE '\| curl --disable' <<<"$STRIPPED" || true)"; fi

echo "== static: wiring and budget anchors =="
cases=$((cases + 1))
_tfname="$(awk '/^resource "betteruptime_heartbeat" "inngest_server_probe"/{on=1} on && /^[[:space:]]*name[[:space:]]*=/{gsub(/.*=[[:space:]]*"|".*/,""); print; exit}' "$UPTIME_TF")"
_scname="$(sed -n 's/^HEARTBEAT_NAME="\(.*\)"$/\1/p' "$PROBE_SRC")"
if [[ -n "$_tfname" && "$_tfname" == "$_scname" ]]; then pass "the verifier's heartbeat name equals the .tf name ($_tfname)"
else fail "heartbeat name mismatch: tf='$_tfname' verifier='$_scname'"; fi

_tfperiod="$(awk '/^resource "betteruptime_heartbeat" "inngest_server_probe"/{on=1} on && /^[[:space:]]*period[[:space:]]*=/{gsub(/[^0-9]/,""); print; exit}' "$UPTIME_TF")"
_tfgrace="$(awk '/^resource "betteruptime_heartbeat" "inngest_server_probe"/{on=1} on && /^[[:space:]]*grace[[:space:]]*=/{gsub(/[^0-9]/,""); print; exit}' "$UPTIME_TF")"
# The slot is read from the table row selected BY workflowFile, never by position.
_slot="$(awk '/workflowFile: "scheduled-inngest-probe-heartbeat.yml"/{on=1} on && /intervalMinutes:/{gsub(/[^0-9]/,""); print; exit}' "$TABLE")"
# Clock and queue constants are named here; their source is sentry-monitor-iac-parity.test.ts
# (CLOCK_DELAY_MINUTES = 12) and the measured runner queue maximum recorded in cron-monitors.tf.
CLOCK_DELAY_MIN=12; QUEUE_MAX_MIN=41; RUNTIME_MIN=2
cases=$((cases + 1))
if [[ "$_tfperiod" =~ ^[0-9]+$ && "$_tfgrace" =~ ^[0-9]+$ && "$_slot" =~ ^[0-9]+$ ]] \
   && (( 2 * _slot + CLOCK_DELAY_MIN + QUEUE_MAX_MIN + RUNTIME_MIN < (_tfperiod + _tfgrace) / 60 )); then
  pass "budget inequality: 2 x ${_slot} + ${CLOCK_DELAY_MIN}+${QUEUE_MAX_MIN}+${RUNTIME_MIN} < $(( (_tfperiod + _tfgrace) / 60 )) min (period ${_tfperiod} + grace ${_tfgrace})"
else fail "budget inequality failed or unreadable: period='$_tfperiod' grace='$_tfgrace' slot='$_slot'"; fi
cases=$((cases + 1))
_bound="$(sed -n 's/^FRESH_MAX_SECS=\([0-9]*\)$/\1/p' "$PROBE_SRC")"
if [[ "$_bound" == 4500 && "$_tfperiod" =~ ^[0-9]+$ ]] && (( _bound + 3600 > 3600 && _bound < _tfperiod + _tfgrace )); then
  pass "freshness bound 4500 s is above the hourly cadence and below period + grace"
else fail "freshness bound is '$_bound'"; fi

cases=$((cases + 1))
if python3 - "$WORKFLOW" <<'PY' 2>/dev/null
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get(True) or wf.get("on")
assert "workflow_dispatch" in on and "schedule" in on, "triggers"
assert wf["concurrency"]["group"] == "scheduled-inngest-probe-heartbeat" and wf["concurrency"]["cancel-in-progress"] is False
assert wf["permissions"] == {"contents": "read"}
steps = wf["jobs"]["feeder"]["steps"]
feeder = [s for s in steps if s.get("id") == "feeder"][0]
run = feeder["run"]
assert "bash scripts/inngest-probe-heartbeat-feeder.sh" in run, "pattern on a run line"
assert re.search(r'out="\$\(bash scripts/inngest-probe-heartbeat-feeder\.sh 2>&1\)" \|\| rc=\$\?', run), "|| rc=$? capture"
assert "exit_code=${rc}" in run
sent = steps[-1]
assert sent["uses"] == "./.github/actions/sentry-heartbeat" and sent["with"]["monitor-slug"] == "scheduled-inngest-probe-heartbeat"
st = sent["with"]["status"]
assert "steps.feeder.outputs.exit_code == '0'" in st and "'ok' || 'error'" in st
assert sent.get("if") == "always()" and sent.get("continue-on-error") is True
PY
then pass "workflow wiring: triggers, concurrency, run line, || rc=\$? capture, Sentry status expression"
else fail "workflow wiring assertions failed"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^[^#]*bash scripts/inngest-probe-heartbeat-feeder\.sh' "$WORKFLOW" || true)" == 1 ]]; then pass "the manifest evidence pattern appears once, on the run line"
else fail "the evidence pattern must appear exactly once outside comments"; fi
cases=$((cases + 1))
if grep -qF 'workflowFile: "scheduled-inngest-probe-heartbeat.yml"' "$TABLE"; then pass "a WATCHDOG_DISPATCH_TABLE row exists for the workflow"
else fail "no dispatch-table row for the workflow"; fi

echo "== selftest and usage =="
cases=$((cases + 1))
_t0=$SECONDS
_o="$(env -i PATH=/usr/bin:/bin "$BASH_BIN" "$PROBE_SRC" --selftest 2>&1)"; _rc=$?
if [[ "$_rc" == 0 && "$_o" == "inngest-probe-feeder: selftest=ok" ]] && (( SECONDS - _t0 < 15 )); then pass "--selftest under env -i prints selftest=ok inside the 15 s cap"
else fail "--selftest: rc=$_rc output=[$_o]"; fi
reset_case; C_ARGS="--selftest"; C_LIBENV="/dev/null"
expect "--selftest with a lib that defines nothing" 3 query_failed "reason=selector_unavailable"
reset_case; C_ARGS="--whatever"
expect "any other argument" 64 usage
reset_case; C_ARGS="--selftest extra"
expect "--selftest with an extra argument" 64 usage
reset_case; C_XTRACE=1
expect "traced with a credential set" 78 xtrace_refused

echo "== fresh row and the bound =="
reset_case; C_ROWS="$(ded 60 | fx fresh)"; C_BEATS=1; C_APIS=1
expect "fresh row (60 s), heartbeat unpaused" 0 beat "http=200"
reset_case; C_ROWS="$(ded 4500 | fx b4500)"; C_BEATS=1; C_APIS=1
expect "boundary: age 4500 s still beats" 0 beat "age_s=4500"
reset_case; C_ROWS="$(ded 4501 | fx b4501)"
expect "boundary: age 4501 s is producer_silent" 3 producer_silent "limit_s=4500"
reset_case; C_ROWS="$(ded 3 | fx young)"; C_BEATS=1; C_APIS=1
expect "a 3 s old row beats" 0 beat

echo "== row selection =="
reset_case; C_ROWS="$(printf '' | fx empty)"
expect "no rows: funnel is all zero" 3 no_rows "rows_total=0 rows_probe=0 rows_host=0 rows_dedicated=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg dedicated)" soleur-web-1 | fx otherhost)"
expect "only another host (host differs)" 3 no_rows "rows_probe=1 rows_host=0 rows_dedicated=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg dedicated)" soleur-inngest soleur-web-prd | fx otherhn)"
expect "only another host_name (host matches)" 3 no_rows "rows_host=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg web)" | fx webrole)"
expect "only host_role=web rows" 3 no_rows "rows_host=1 rows_dedicated=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg web host_role=dedicated)" | fx firstweb)"
expect "first host_role token web, second dedicated: first wins, withheld" 3 no_rows "rows_dedicated=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg dedicated host_role=web)" | fx firstded)"; C_BEATS=1; C_APIS=1
expect "first host_role token dedicated, second web: first wins, beats" 0 beat
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg dedicated)" soleur-inngest soleur-inngest-prd doppler | fx quoting)"
expect "emitter doppler quoting the marker is not a probe row" 3 no_rows "rows_probe=0"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "{\"body\":\"$(msg dedicated)\"}" | fx unanch)"
expect "probe emitter with an unanchored marker is not a probe row" 3 no_rows "rows_probe=0"
reset_case; C_ROWS="$({ ded 4000; row "$(dt_ago 10)" "$(msg dedicated)" soleur-inngest soleur-inngest-prd doppler; } | fx quotenewer)"; C_BEATS=1; C_APIS=1
expect "newer quoting row is set aside; the 4000 s probe row decides" 0 beat "age_s=4000"
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 10)" "$(msg dedicated)" soleur-inngest soleur-inngest-prd doppler; } | fx quotestale)"
expect "newer quoting row does not rescue a stale probe row" 3 producer_silent
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg web)"; } | fx webnewer)"
expect "fresh web-role row newer than a stale dedicated one" 3 producer_silent
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg dedicated)" soleur-web-1; } | fx hostnewer)"
expect "fresh row from another host newer than a stale dedicated one" 3 producer_silent
reset_case; C_ROWS="$({ ded 5000; ded 60; } | fx staleFirst)"; C_BEATS=1; C_APIS=1
expect "stale row ordered before a fresh one: newest by dt wins" 0 beat "age_s=60"
reset_case; C_ROWS="$({ ded 60; ded 5000; } | fx freshFirst)"; C_BEATS=1; C_APIS=1
expect "fresh row ordered before a stale one: order does not matter" 0 beat "age_s=60"
reset_case; C_ROWS="$({ ded 60; row "$(dt_ago -400)" "$(msg dedicated)"; } | fx futureAfter)"
expect "fresh row first, future-dated newest row after it" 3 row_unusable "field=dt_future"
reset_case; C_ROWS="$(row "$(dt_ago_t 60)" "$(msg dedicated)" | fx tsep)"; C_BEATS=1; C_APIS=1
expect "dt using T instead of a space" 0 beat
reset_case; C_ROWS="$(row "$(dt_ago -300)" "$(msg dedicated)" | fx fut300)"; C_BEATS=1; C_APIS=1
expect "future slack boundary: +300 s is accepted" 0 beat
reset_case; C_ROWS="$(row "$(dt_ago -301)" "$(msg dedicated)" | fx fut301)"
expect "future slack boundary: +301 s is withheld" 3 row_unusable "field=dt_future"
reset_case; C_ROWS="$(row "$(dt_ago -120)" "$(msg dedicated)" | fx skewPlus)"; C_BEATS=1; C_APIS=1
expect "skew: a row stamped 120 s ahead of the runner clock" 0 beat
reset_case; C_ROWS="$(row "$(dt_ago 4380)" "$(msg dedicated)" | fx skewMinus)"; C_BEATS=1; C_APIS=1
expect "skew: a row 120 s inside the bound" 0 beat
reset_case; C_ROWS="$(row "not-a-date" "$(msg dedicated)" | fx baddt)"
expect "unparseable dt" 3 row_unusable "field=dt"
reset_case; C_ROWS="$(jq -cn --arg m "$(msg dedicated)" '{raw: ({host:"soleur-inngest",host_name:"soleur-inngest-prd",SYSLOG_IDENTIFIER:"inngest-server-probe",message:$m}|tojson)}' | fx nodt)"
expect "a row with no dt at all" 3 row_unusable "field=dt"
reset_case; C_ROWS="$(row "$(dt_ago 60)" "$(msg dedicated "extra_unknown=1 other=2")" | fx extra)"; C_BEATS=1; C_APIS=1
expect "extra unknown fields do not matter" 0 beat

echo "== warehouse failures =="
reset_case; C_UNSET="BETTERSTACK_QUERY_PASSWORD"
expect "query secret unset" 3 query_failed "reason=secret_unset"
reset_case; C_STUB="none"
expect "helper missing" 3 query_failed "reason=helper_missing"
reset_case; C_STUB="fail"
expect "helper fails with a credential-bearing error body" 3 query_failed "class=auth"
reset_case; C_STUB="garbage"
expect "helper answers an HTML error page with status 0" 3 query_failed "reason=malformed"
reset_case; C_LIB="__none__"; C_ROWS="$(ded 60 | fx f1)"
expect "shared lib missing" 3 query_failed "reason=selector_unavailable"
reset_case; C_LIBENV="/dev/null"; C_ROWS="$(ded 60 | fx f2)"
expect "shared lib that defines nothing" 3 query_failed "reason=selector_unavailable"
reset_case; C_NOW="2026-10-11 12:00:00"; C_ROWS="$(ded 60 | fx f3)"
expect "malformed INNGEST_FEEDER_NOW is never a wall-clock fallback" 3 clock_malformed

echo "== heartbeat resolution =="
reset_case; C_ROWS="$(ded 60 | fx fp1)"; C_API="$(api_paused | fx apiPaused)"; C_APIS=1
expect "heartbeat paused: nothing is sent" 0 fresh_heartbeat_paused "age_s=60"
reset_case; C_ROWS="$(ded 60 | fx fp2)"; C_API="$(hb_json "$NAME" __absent__ "$HB_URL" | fx apiNoPaused)"; C_APIS=1
expect "paused attribute absent" 4 beat_failed "reason=paused_not_boolean"
reset_case; C_ROWS="$(ded 60 | fx fp3)"; C_API="$(hb_json "$NAME" null "$HB_URL" | fx apiNullPaused)"; C_APIS=1
expect "paused attribute null" 4 beat_failed "reason=paused_not_boolean"
reset_case; C_ROWS="$(ded 60 | fx fp4)"; C_API="$(hb_json "$NAME" '"false"' "$HB_URL" | fx apiStrPaused)"; C_APIS=1
expect "paused attribute the string \"false\"" 4 beat_failed "reason=paused_not_boolean"
reset_case; C_ROWS="$(ded 60 | fx fp5)"; C_API="$(hb_json "soleur-other-heartbeat" false "$HB_URL" | fx apiOtherName)"; C_APIS=1
expect "heartbeat name absent" 4 beat_failed "reason=heartbeat_not_unique matches=0"
reset_case; C_ROWS="$(ded 60 | fx fp6)"; C_API="$(hb_json "${NAME}-old" false "$HB_URL" | fx apiPrefix)"; C_APIS=1
expect "prefix decoy (name plus a suffix) is not a match" 4 beat_failed "reason=heartbeat_not_unique matches=0"
reset_case; C_ROWS="$(ded 60 | fx fp7)"; C_API="$(jq -cn --argjson a "$(hb_json "$NAME" false "$HB_URL")" '{data: ($a.data + $a.data)}' | fx apiTwo)"; C_APIS=1
expect "two heartbeats with the name (second member after a compliant first)" 4 beat_failed "reason=heartbeat_not_unique matches=2"
for _u in "https://evil.example/api/v1/heartbeat/abc123" "http://uptime.betterstack.com/api/v1/heartbeat/abc123" \
          "https://uptime.betterstack.com/api/v1/heartbeat/abc123/extra" "https://uptime.betterstack.com/api/v1/heartbeat/abc123?x=1" \
          "https://uptime.betterstack.com.evil.example/api/v1/heartbeat/abc123" 'https://uptime.betterstack.com/api/v1/heartbeat/abc"123' \
          $'https://uptime.betterstack.com/api/v1/heartbeat/abc\n123' "" ; do
  reset_case; C_ROWS="$(ded 60 | fx fpu)"; C_API="$(hb_json "$NAME" false "$_u" | fx apiurl)"; C_APIS=1; C_EXPECT_URL="$_u"
  expect "URL shape refused: $(printf '%s' "${_u:-<empty>}" | tr '\n' '~' | head -c 60)" 4 beat_failed "reason=url_shape"
done
reset_case; C_ROWS="$(ded 60 | fx fp8)"; C_APIMODE="fail"; C_APIS=1
expect "uptime API unreadable" 4 beat_failed "reason=api_unreadable"
reset_case; C_ROWS="$(ded 60 | fx fp9)"; printf '<html>not json</html>' > "$WORK/fx/notjson"; C_API="$WORK/fx/notjson"; C_APIS=1
expect "uptime API answers something that is not a heartbeat list" 4 beat_failed "reason=api_malformed"
reset_case; C_ROWS="$(ded 60 | fx fp10)"; C_TOKEN="__unset__"
expect "read-only token unset" 4 beat_failed "reason=api_token_unset"
reset_case; C_ROWS="$(ded 60 | fx fp11)"; C_TOKEN='short"token'
expect "read-only token malformed (quote, too short)" 4 beat_failed "reason=api_token_malformed"
reset_case; C_ROWS="$(ded 4501 | fx fp12)"; C_TOKEN="__unset__"
expect "a stale row withholds before the credential is even read (no API call)" 3 producer_silent

echo "== beat delivery =="
reset_case; C_ROWS="$(ded 60 | fx bd1)"; C_BEATMODE="500"; C_BEATS=1; C_APIS=1
expect "beat answered 500" 4 beat_failed "reason=http_status"
reset_case; C_ROWS="$(ded 60 | fx bd2)"; C_BEATMODE="302"; C_BEATS=1; C_APIS=1
expect "beat answered 302 (passes curl -f; only 2xx counts)" 4 beat_failed "http=302"
reset_case; C_ROWS="$(ded 60 | fx bd3)"; C_BEATMODE="curlfail"; C_BEATS=1; C_APIS=1
expect "beat curl fails outright" 4 beat_failed "reason=http_status"

echo "== mutation runner self-test =="
verdict_holds() { [[ "$1" == "$LAST_RC" ]] && grep -qE "verdict=$2( |\$)" "$OUT"; }
run_case() { LAST_RC="$(run_probe)"; }
landed_within() { # <orig> <mutant> "<lo>-<hi> ..."
  local hunks
  hunks="$(diff "$1" "$2" | grep -E '^[0-9]' || true)"
  [[ -n "$hunks" ]] || return 1
  awk -v ranges="$3" '
    BEGIN { n = split(ranges, R, " ") }
    { split($0, p, /[acd]/); k = split(p[1], ab, ","); a = ab[1] + 0; b = (k > 1) ? ab[2] + 0 : a
      ok = 0
      for (i = 1; i <= n; i++) { split(R[i], lh, "-"); if (a >= lh[1] + 0 && b <= lh[2] + 0) ok = 1 }
      if (!ok) bad = 1 }
    END { if (bad) print "out" }' <<<"$hunks" | grep -c out >/dev/null && return 1
  return 0
}
fn_range() { awk -v f="$2" '$0 == f "() {" { s = NR } s && !e && NR > s && $0 == "}" { e = NR } END { if (s && e) print s "-" e }' "$1"; }
line_of() { grep -nxF -- "$2" "$1" | cut -d: -f1; }
MUT_TABLE="$WORK/mutations.tsv"; : > "$MUT_TABLE"
expect_red() { # <row> <name> <orig-rc> <orig-verdict>
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if verdict_holds "$3" "$4"; then fail "mutation row $1 ($2) SURVIVED: still status $3 + verdict=$4"
  else pass "mutation row $1 ($2) is RED: status $LAST_RC, verdicts [$seen]"; fi
}
assert_landed() { # <row> <mutant> <ranges>
  cases=$((cases + 1))
  if landed_within "$PROBE_SRC" "$2" "$3"; then pass "mutation row $1 landed inside $3"
  else fail "mutation row $1 did NOT land inside $3 — its RED would be vacuous"; fi
}

# Known-positive: the shipped verifier on a fresh unpaused fixture HOLDS (the detector must say "survived").
reset_case; C_ROWS="$(ded 60 | fx kp)"; C_BEATS=1; C_APIS=1; run_case
cases=$((cases + 1))
if verdict_holds 0 beat; then pass "runner known-positive: shipped verifier + fresh fixture holds"
else fail "runner known-positive: got status $LAST_RC"; fi
# Known-negative: the same detector on a stale fixture does NOT hold 0 beat.
reset_case; C_ROWS="$(ded 4501 | fx kn)"; run_case
cases=$((cases + 1))
if ! verdict_holds 0 beat; then pass "runner known-negative: a stale fixture does not read as a beat"
else fail "runner known-negative: the detector reports a beat on a stale fixture"; fi

FRESH_R="$(fn_range "$PROBE_SRC" check_freshness)"
MAIN_START="$(line_of "$PROBE_SRC" '# ── MAIN')"
TOTAL="$(wc -l < "$PROBE_SRC")"
MAIN_R="${MAIN_START:-0}-$TOTAL"
CONST_LINE="$(line_of "$PROBE_SRC" 'FRESH_MAX_SECS=4500')"
cases=$((cases + 1))
if [[ -n "$FRESH_R" && -n "$MAIN_START" && -n "$CONST_LINE" ]]; then pass "mutation seams located (check_freshness $FRESH_R, main $MAIN_R, bound line $CONST_LINE)"
else fail "mutation seams not found — every code mutation below would be vacuous"; fi

echo "== committed mutation rows =="
# M1: raise the bound by one second.
M="$WORK/mut/m1.sh"; sed -E 's/^FRESH_MAX_SECS=4500$/FRESH_MAX_SECS=4501/' "$PROBE_SRC" > "$M"
assert_landed M1 "$M" "$CONST_LINE-$CONST_LINE"
reset_case; C_ROWS="$(ded 4501 | fx m1)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M1 "bound raised by one second" 3 producer_silent
# M2a/M2b: drop the host filter, or the host_name filter.
M="$WORK/mut/m2a.sh"; sed -E 's/\(\.host == \$h and \.host_name == \$hn\)/(.host_name == $hn)/' "$PROBE_SRC" > "$M"
assert_landed M2a "$M" "$FRESH_R"
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg dedicated)" soleur-web-1; } | fx m2a)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M2a "host filter dropped" 3 producer_silent
M="$WORK/mut/m2b.sh"; sed -E 's/\(\.host == \$h and \.host_name == \$hn\)/(.host == $h)/' "$PROBE_SRC" > "$M"
assert_landed M2b "$M" "$FRESH_R"
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg dedicated)" soleur-inngest soleur-web-prd; } | fx m2b)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M2b "host_name filter dropped" 3 producer_silent
# M3: the shared predicate replaced by a substring match on the marker.
M="$WORK/mut/m3.sh"; sed -E 's/\[select\(inngest_probe_row\)\]/[select(((.message \/\/ "") | tostring) | contains("SOLEUR_INNGEST_SERVER_PROBE"))]/' "$PROBE_SRC" > "$M"
assert_landed M3 "$M" "$FRESH_R"
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg dedicated)" soleur-inngest soleur-inngest-prd doppler; } | fx m3)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M3 "substring match instead of the shared predicate" 3 producer_silent
# M4: drop the dedicated role rule.
M="$WORK/mut/m4.sh"; sed -E 's/\.r\) == "dedicated" then 1/.r) != "__never__" then 1/' "$PROBE_SRC" > "$M"
assert_landed M4 "$M" "$FRESH_R"
reset_case; C_ROWS="$({ ded 5000; row "$(dt_ago 30)" "$(msg web)"; } | fx m4)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M4 "role filter dropped" 3 producer_silent
# M5: take the oldest row instead of the newest by dt.
M="$WORK/mut/m5.sh"; sed -E 's/LC_ALL=C sort -s \| tail -1/LC_ALL=C sort -s | head -1/' "$PROBE_SRC" > "$M"
assert_landed M5 "$M" "$FRESH_R"
reset_case; C_ROWS="$({ ded 5000; ded 60; } | fx m5)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M5 "oldest row selected instead of newest by dt" 0 beat
# M6: call the beat BEFORE the freshness verdict (reorder, not delete).
M="$WORK/mut/m6.sh"
awk '$0 == "check_freshness" { print "beat_once" } { print }' "$PROBE_SRC" > "$M"
assert_landed M6 "$M" "$MAIN_R"
reset_case; C_ROWS="$(ded 4501 | fx m6)"; C_PROBE="$M"; C_BEATS=1
expect_red M6 "beat called before the freshness verdict" 3 producer_silent
cases=$((cases + 1))
if [[ "$(( $(count_calls '^beat$') ))" -ge 1 ]]; then pass "mutation row M6: the stub observed the beat call during the run"
else fail "mutation row M6: no beat call observed — the reorder did not reach the beat"; fi
# M7: ignore paused == true.
M="$WORK/mut/m7.sh"; sed -E 's/^if \[\[ "\$HB_PAUSED" == "true" \]\]; then$/if false; then/' "$PROBE_SRC" > "$M"
assert_landed M7 "$M" "$MAIN_R"
reset_case; C_ROWS="$(ded 60 | fx m7)"; C_API="$(api_paused | fx m7api)"; C_PROBE="$M"; C_BEATS=1; C_APIS=1
expect_red M7 "paused ignored" 0 fresh_heartbeat_paused
# A detached trap: a fall-off that exits 0 without a verdict is remapped to 3, never 0.
M="$WORK/mut/falloff.sh"; awk '$0 == "beat_once" { print "DECIDED=0; exit 0"; next } { print }' "$PROBE_SRC" > "$M"
assert_landed falloff "$M" "$MAIN_R"
reset_case; C_ROWS="$(ded 60 | fx fo)"; C_PROBE="$M"; C_APIS=1; run_case
cases=$((cases + 1))
if [[ "$LAST_RC" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "an undecided exit 0 is remapped to 3 trap_remapped, never 0"
else fail "undecided exit 0: expected 3 trap_remapped, got $LAST_RC [$(markers_of)]"; fi

echo
echo "== measured mutation verdicts (row, edit, verdicts seen, status) =="
sed 's/^/  /' "$MUT_TABLE"

# ── conservation and the floors ───────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases, $beat_asserts beat-call assertions ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# A HARD-CODED floor: a runtime-derived one falls when a case is deleted.
MIN_PASSES=104
MIN_BEAT_ASSERTS=61
if (( passes < MIN_PASSES )); then
  printf 'FATAL: only %s passes, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
if (( beat_asserts < MIN_BEAT_ASSERTS )); then
  printf 'FATAL: only %s beat-call assertions, below the floor of %s.\n' "$beat_asserts" "$MIN_BEAT_ASSERTS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
