#!/usr/bin/env bash
# Behavioural tests for the measured-beat ARM gate and its re-pause sweep
# (apps/web-platform/infra/arm-heartbeats.sh, #7587/#7659).
#
# WHY THIS FILE EXISTS. Before #7587 the gate was ~130 lines of bash inside a YAML scalar and
# `git grep arm_one` across the test trees returned only comments — it was asserted by NOTHING.
# The first design for asserting it was a regex over the workflow, which the plan's test-design
# review showed is not merely brittle but WEAK: "the counter advances by measured elapsed time" is
# checkable that way only as "a clock read appears in the step", which a decoy `date +%s` satisfies
# and an equivalent `SECONDS`-based rewrite false-REDs. So the gate is a real script and this suite
# drives it BEHAVIOURALLY, against a fake clock and a fake `curl` on PATH — the house shape used by
# `web-private-nic-guard.sh` + `.test.sh` and the other pairs in this directory.
#
# THE SWEEP IS DRIVEN THE SAME WAY (#7659). It shipped as bash inside the sibling step's YAML
# scalar, guarded by regexes over the step text — which is how an `exit 1` assertion came to be
# satisfied by an unrelated `exit 1` several lines away. It is now `arm-heartbeats.sh --sweep` and
# cases S1–S7 below execute its loop, its arithmetic, its summary line, its outcome vocabulary and
# its fail-not-annotate branch.
#
# WHAT IS FAKED, AND WHAT IS NOT. `curl`, `sleep` and `date` are PATH stubs. `jq`, `grep`, `mv` and
# every other utility the SUT uses are REAL, and so is the SUT: this executes
# `apps/web-platform/infra/arm-heartbeats.sh` itself, never a reconstruction of it.
#
# THE FAKE CLOCK IS THE WHOLE POINT, AND IT IS WHY THE ASSERTIONS READ TWO DIFFERENT NUMBERS.
# `sleep N` advances the clock by N and returns instantly; every `curl` advances it by
# FAKE_CURL_COST. The SUT REPORTS an elapsed, and the harness separately OBSERVES the clock. Under
# the pre-#7587 sleep-tally those two diverge — the reported elapsed stops at the nominal deadline
# while the real clock reaches deadline x 2.5 — so an assertion on the reported number alone cannot
# see the defect. Mutation row M1 reverts the fix and requires the OBSERVED clock to blow its
# bound; that is the row the reported-elapsed assertion would have passed over.
#
# THE FAKE `curl` MODELS HTTP STATUS, NOT ONLY TRANSPORT (#7656 C4). It used to dispatch on method,
# URL and body and IGNORE every flag, which made three separate dependencies structurally
# unexpressible: `-f` (without it curl exits 0 on a 5xx, so a rollback that got HTTP 500 read as
# success and the id left the sweep's books), the `Authorization` header, and `--max-time`. The
# stub now:
#   * REQUIRES `--max-time` and a non-empty `Authorization: Bearer …` — which now arrives as a curl
#     config on STDIN (`--config -`), never on argv — and `exit 64`s / answers 401 without them, so
#     deleting either from the SUT reds this suite. It also refuses (rc 65/66) a bearer on argv, a
#     call whose first argument is not `--disable`, and one with no `--noproxy '*'`;
#   * carries a per-id, per-method HTTP STATUS fixture, so a 500 on the rollback is expressible;
#   * honours `-f` (fail on >= 400) and `-o /dev/null -w '%{http_code}'` (print the code, not the
#     body), so both curl calling conventions in the SUT are modelled rather than assumed.
# It still `exit 64`s when handed no URL or an unrecognised PATCH body, so a SUT that starts
# querying the wrong thing is detectable rather than silently served the same fixture (the
# PATH-shimmed-fake trap, #7081). Monitor ids are synthesized (`cq-test-fixtures-synthesized-only`);
# no real Better Stack id appears in this file.
#
# Pure bash + jq + PATH stubs — no network, no docker, no doppler, no root, no terraform.
#
# Run: bash apps/web-platform/infra/arm-heartbeats.test.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"   # a self-invoked suite must not inherit the bare 4 GiB /tmp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/arm-heartbeats.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ $# -lt 2 ]] || echo "        $2"; }
assert() {  # <desc> <condition>
  if eval "$2"; then pass "$1"; else fail "$1" "condition: $2"; fi
}
assert_eq() {  # <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# A harness that fails to SET UP must abort, never continue: the next case would then run against
# the previous case's state and produce a confident verdict about the SUT that the harness authored.
[[ -d "$WORK" ]] || { echo "FATAL: mktemp -d failed"; exit 2; }

REAL_DATE="$(command -v date)"
[[ -x "$REAL_DATE" ]] || { echo "FATAL: no real date binary"; exit 2; }

echo "=== ARM gate (arm-heartbeats.sh, #7587/#7659) behavioural tests ==="
assert "the SUT exists" "[[ -f '$SUT' ]]"
assert "the SUT is syntactically valid bash" "bash -n '$SUT'"
[[ -f "$SUT" ]] || { echo "FATAL: SUT missing"; exit 2; }

# --- PATH stubs ---------------------------------------------------------------------------
BIN="$WORK/bin"
mkdir -p "$BIN" || { echo "FATAL: mkdir stub dir failed"; exit 2; }

cat > "$BIN/date" <<EOS
#!/usr/bin/env bash
if [[ "\${1:-}" == "+%s" ]]; then cat "\$FAKE_CLOCK"; exit 0; fi
exec "$REAL_DATE" "\$@"
EOS

cat > "$BIN/sleep" <<'EOS'
#!/usr/bin/env bash
# Instant, but it MOVES THE CLOCK. A sleep stubbed to a no-op silently voids every wall-clock
# assertion in this suite (#6441 (c)).
n="${1:-0}"
c=$(cat "$FAKE_CLOCK")
echo $(( c + n )) > "$FAKE_CLOCK"
# THE EXTERNAL CUT (#7587, plan scenario 8). GitHub ends a step that hits its `timeout-minutes`
# by signalling it, and the modal moment for that is BETWEEN two polls — which is exactly here.
# `sleep` is invoked directly by `arm_one` (no subshell, no pipeline), so $PPID is the SUT's own
# bash and a SIGKILL here models the cut deterministically, with no race against the fake clock.
if [[ -n "${FAKE_CUT_AFTER:-}" ]]; then
  seen=$(( $(cat "$FAKE_CUT_COUNT" 2>/dev/null || echo 0) + 1 ))
  echo "$seen" > "$FAKE_CUT_COUNT"
  if [[ "$seen" -ge "$FAKE_CUT_AFTER" ]]; then kill -9 "$PPID" 2>/dev/null; exit 0; fi
fi
EOS

cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# Fake Better Stack heartbeats API. Dispatches on ARGV (flags + method + URL + body), NOT on
# argument count: a stub that answers identically regardless of what it was asked cannot detect a
# SUT querying the wrong thing, and a fixture keyed per id is what makes "one clean, one dirty"
# real. It also models the HTTP STATUS, which is what makes `-f` and the `%{http_code}` convention
# testable rather than assumed (#7656 C4).
args=("$@")
url=""; method="GET"; data=""; auth=""; maxtime=""; failflag=0; writeout=""; outfile=""
cfg=""; noproxy=""; argv_bearer=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -X)          method="${args[i+1]:-}" ;;
    --data-raw)  data="${args[i+1]:-}" ;;
    # The bearer is NOT read from argv any more: it travels on stdin as a curl config (`--config -`).
    # An Authorization header (or the token itself) on argv is a harness-fidelity refusal below.
    --config)    cfg="${args[i+1]:-}" ;;
    --noproxy)   noproxy="${args[i+1]:-}" ;;
    --max-time)  maxtime="${args[i+1]:-}" ;;
    -w)          writeout="${args[i+1]:-}" ;;
    -o)          outfile="${args[i+1]:-}" ;;
    -f|-fsS|-sSf) failflag=1 ;;
    https://*)   url="${args[i]}" ;;
  esac
  case "${args[i]}" in
    *Authorization*|*Bearer*|*"${BS_TOKEN:-@@none@@}"*) argv_bearer=1 ;;
  esac
done
# The bearer header arrives as a curl config on stdin; read it ONLY when asked to (`--config -`),
# so a stub invoked without it can never block on the harness's own stdin.
if [[ "$cfg" == "-" ]]; then
  cfg_in="$(cat)"
  if [[ "$cfg_in" =~ ^header\ =\ \"(Authorization:\ Bearer\ ?[^\"]*)\"$ ]]; then auth="${BASH_REMATCH[1]}"; fi
fi
# HARNESS-FIDELITY REFUSALS. These are not vendor behaviours — they are the stub asserting that the
# SUT still calls it the way the contract says. A round-trip with no ceiling is exactly what the
# wall-clock ladder cannot survive, and an unauthenticated call is not a call this API answers.
if [[ -z "$url" ]]; then
  echo "fake curl: invoked with no URL argument" >&2
  exit 64
fi
if [[ -z "$maxtime" ]]; then
  echo "fake curl: invoked with no --max-time — every round-trip must carry a ceiling" >&2
  exit 64
fi
# Transport-confinement fidelity (#7797/#7873): the SUT must call curl with `--disable` as its FIRST
# argument, `--noproxy '*'`, and the bearer off argv. Deleting any of them reds this suite.
if [[ "$argv_bearer" -eq 1 ]]; then
  echo "fake curl: a bearer / Authorization value is on ARGV — it must ride stdin (--config -)" >&2
  exit 65
fi
if [[ "${args[0]:-}" != "--disable" ]]; then
  echo "fake curl: --disable is not the FIRST argument" >&2
  exit 66
fi
if [[ "$noproxy" != "*" ]]; then
  echo "fake curl: no --noproxy '*'" >&2
  exit 66
fi
id="${url##*/}"
# THE LIST ENDPOINT (#9980): `GET <base>/heartbeats` or `GET <base>/heartbeats?<query>`. Detected BEFORE
# `id="${url##*/}"` is trusted — that expansion would turn `.../heartbeats?per_page=250` into an id.
is_list=0
case "$url" in
  */heartbeats|*/heartbeats\?*) is_list=1 ;;
esac

# Every round-trip costs wall clock. This is the term the pre-#7587 sleep-tally ignored.
c=$(cat "$FAKE_CLOCK")
now=$(( c + ${FAKE_CURL_COST:-15} ))
echo "$now" > "$FAKE_CLOCK"

if [[ "$is_list" -eq 1 ]]; then
  # Logged as its own LIST row (never GET), so the id-keyed helpers below cannot count it.
  printf '%s\tLIST\t%s\t%s\n' "$now" "$url" "$data" >> "$FAKE_CALLS"
  # A list call to any host but the vendor's is refused AFTER logging it, so an off-origin follow
  # of `pagination.next` is observable in the call log rather than only as an exit code.
  case "$url" in
    https://uptime.betterstack.com/api/v2/heartbeats*) ;;
    *) echo "fake curl: off-origin list call $url" >&2; exit 67 ;;
  esac
else
  printf '%s\t%s\t%s\t%s\n' "$now" "$method" "$id" "$data" >> "$FAKE_CALLS"
fi

emit() {  # <http-status> <body>
  local code="$1" body="$2"
  if [[ -n "$writeout" ]]; then
    # `-o <file> -w '%{http_code}'`: the body goes to the file, the CODE goes to stdout. curl
    # still exits 0 on a 4xx/5xx in this mode unless -f is also given.
    [[ -z "$outfile" ]] || printf '%s' "$body" > "$outfile" 2>/dev/null
    printf '%s' "${writeout//'%{http_code}'/$code}"
    if [[ "$failflag" -eq 1 && "$code" -ge 400 ]]; then exit 22; fi
    exit 0
  fi
  if [[ "$failflag" -eq 1 && "$code" -ge 400 ]]; then
    echo "fake curl: HTTP $code (--fail)" >&2
    exit 22
  fi
  # WITHOUT -f curl prints the error body and exits 0. This is the door C4 named.
  printf '%s' "$body"
  exit 0
}

if [[ -z "$auth" || "$auth" == "Authorization: Bearer" || "$auth" == "Authorization: Bearer " ]]; then
  emit 401 '{"errors":"unauthorized"}'
fi

if [[ "$is_list" -eq 1 ]]; then
  [[ "$method" == "GET" ]] || { echo "fake curl: list endpoint takes GET only, got $method" >&2; exit 64; }
  page=1
  if [[ "$url" =~ [\?\&]page=([0-9]+) ]]; then page="${BASH_REMATCH[1]}"; fi
  # per_page=250 is required on the FIRST page only: a vendor `next` URL may carry `page=` alone.
  if [[ "$page" -eq 1 && "$url" != *per_page=250* ]]; then
    echo "fake curl: first list page requested without per_page=250" >&2; exit 64
  fi
  # FAKE_LIST_FAIL: 500 | empty | garbage; FAKE_LIST_FAIL_PAGE restricts it to one page.
  if [[ -n "${FAKE_LIST_FAIL:-}" && ( -z "${FAKE_LIST_FAIL_PAGE:-}" || "$FAKE_LIST_FAIL_PAGE" == "$page" ) ]]; then
    case "$FAKE_LIST_FAIL" in
      500)     emit 500 '{"errors":"boom"}' ;;
      empty)   emit 200 '' ;;
      garbage) emit 200 'this is not json' ;;
    esac
  fi
  lf="${FAKE_LIST_DIR:-/nonexistent}/page-$page.json"
  [[ -r "$lf" ]] || { echo "fake curl: no list fixture $lf" >&2; exit 64; }
  emit 200 "$(cat "$lf")"
fi

status_for() {  # <method> -> the fixture HTTP status, default 200
  local f="$FAKE_HTTP/$id.$1"
  if [[ -r "$f" ]]; then cat "$f"; else echo 200; fi
}

case "$method" in
  GET)
    # FAKE_HOOK_GET: a command run at every by-id GET, before it answers (a case's way to change the world mid-run).
    if [[ -n "${FAKE_HOOK_GET:-}" ]]; then eval "$FAKE_HOOK_GET"; fi
    if grep -qxF -- "$id" "$FAKE_GET_FAIL" 2>/dev/null; then emit 500 '{"errors":"boom"}'; fi
    # A GET that succeeds and THEN fails: "<id> <n>" means every GET after the nth returns 500.
    n_after="$(awk -v i="$id" '$1==i{print $2}' "$FAKE_GET_FAIL_AFTER" 2>/dev/null | sed -n '1p')"
    if [[ -n "$n_after" ]]; then
      seen="$(awk -F'\t' -v i="$id" '$2=="GET" && $3==i' "$FAKE_CALLS" | grep -c '')"
      if [[ "$seen" -gt "$n_after" ]]; then emit 500 '{"errors":"boom"}'; fi
    fi
    if grep -qxF -- "$id" "$FAKE_EMPTY_BODY" 2>/dev/null; then emit 200 ''; fi
    if grep -qxF -- "$id" "$FAKE_BAD_JSON" 2>/dev/null; then emit 200 '{"data":{"id":"x","attributes":{}}}'; fi
    status="$(cat "$FAKE_STATE/$id.status" 2>/dev/null || true)"
    [[ -n "$status" ]] || { echo "fake curl: no fixture for id $id" >&2; exit 64; }
    upat="$(cat "$FAKE_STATE/$id.upat" 2>/dev/null || true)"
    if [[ -n "$upat" && "$now" -ge "$upat" ]]; then status="up"; fi
    updated="$(cat "$FAKE_STATE/$id.updated" 2>/dev/null || echo "2026-08-20T00:00:00.000Z")"
    emit "$(status_for get)" "$(printf '{"data":{"id":"%s","attributes":{"status":"%s","updated_at":"%s"}}}' "$id" "$status" "$updated")"
    ;;
  PATCH)
    # Keyed on the id AND the paused value, so a fixture can fail the ROLLBACK without also
    # failing the unpause that precedes it — those are different SUT branches and a fixture that
    # cannot separate them tests neither.
    case "$data" in
      *'"paused":false'*) want=false ;;
      *'"paused":true'*)  want=true ;;
      *) echo "fake curl: PATCH with an unrecognised body [$data]" >&2; exit 64 ;;
    esac
    # FAKE_SNAP_BOOKS <file>: on the unpause PATCH, copy that file to "$FAKE_CALLS.booksnap" BEFORE anything else happens,
    # so a case can read what the books held at the instant the request arrived. FAKE_HOOK_PATCH_FALSE then runs.
    if [[ "$want" == false ]]; then
      if [[ -n "${FAKE_SNAP_BOOKS:-}" ]]; then cat "$FAKE_SNAP_BOOKS" > "$FAKE_CALLS.booksnap" 2>/dev/null; fi
      if [[ -n "${FAKE_HOOK_PATCH_FALSE:-}" ]]; then eval "$FAKE_HOOK_PATCH_FALSE"; fi
    fi
    # FAKE_PATCH_LOST "<id> <want>": the change APPLIES server-side and the REPLY is a 500 (a lost reply).
    if grep -qxF -- "$id $want" "${FAKE_PATCH_LOST:-/dev/null}" 2>/dev/null; then
      if [[ "$want" == "false" ]]; then printf 'pending' > "$FAKE_STATE/$id.status"
      else printf 'paused' > "$FAKE_STATE/$id.status"; fi
      emit 500 '{"errors":"reply lost"}'
    fi
    if grep -qxF -- "$id $want" "$FAKE_PATCH_FAIL" 2>/dev/null; then emit 500 '{"errors":"boom"}'; fi
    # "<id> <want> <code>": only the FIRST matching PATCH answers <code>; later ones succeed. This
    # is what makes a RETRY distinguishable from a first-attempt success (#7658 E8).
    once="$(awk -v i="$id" -v w="$want" '$1==i && $2==w{print $3}' "$FAKE_PATCH_FAIL_ONCE" 2>/dev/null | sed -n '1p')"
    if [[ -n "$once" ]]; then
      seen="$(awk -F'\t' -v i="$id" '$2=="PATCH" && $3==i && $4 ~ /"paused":'"$want"'/' "$FAKE_CALLS" | grep -c '')"
      if [[ "$seen" -le 1 ]]; then emit "$once" '{"errors":"boom"}'; fi
    fi
    if [[ "$want" == "false" ]]; then printf 'pending' > "$FAKE_STATE/$id.status"
    else printf 'paused' > "$FAKE_STATE/$id.status"; fi
    emit "$(status_for "patch-$want")" "$(printf '{"data":{"id":"%s"}}' "$id")"
    ;;
  *)
    echo "fake curl: unsupported method $method" >&2; exit 64 ;;
esac
EOS
chmod +x "$BIN/date" "$BIN/sleep" "$BIN/curl" || { echo "FATAL: chmod stubs failed"; exit 2; }

# Stub fidelity, asserted rather than assumed.
FAKE_CLOCK="$WORK/clock-selftest"; echo 0 > "$FAKE_CLOCK"
FAKE_CALLS="$WORK/calls-selftest"; : > "$FAKE_CALLS"
FAKE_GET_FAIL="$WORK/getfail-selftest"; : > "$FAKE_GET_FAIL"
FAKE_GET_FAIL_AFTER="$WORK/getfailafter-selftest"; : > "$FAKE_GET_FAIL_AFTER"
FAKE_PATCH_FAIL="$WORK/patchfail-selftest"; : > "$FAKE_PATCH_FAIL"
FAKE_PATCH_FAIL_ONCE="$WORK/patchfailonce-selftest"; : > "$FAKE_PATCH_FAIL_ONCE"
FAKE_EMPTY_BODY="$WORK/emptybody-selftest"; : > "$FAKE_EMPTY_BODY"
FAKE_BAD_JSON="$WORK/badjson-selftest"; : > "$FAKE_BAD_JSON"
FAKE_STATE="$WORK/state-selftest"; mkdir -p "$FAKE_STATE"
FAKE_HTTP="$WORK/http-selftest"; mkdir -p "$FAKE_HTTP"
FAKE_LIST_DIR="$WORK/list-selftest"; mkdir -p "$FAKE_LIST_DIR"
FAKE_LIST_FAIL=""; FAKE_LIST_FAIL_PAGE=""
export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_GET_FAIL_AFTER FAKE_PATCH_FAIL FAKE_PATCH_FAIL_ONCE FAKE_EMPTY_BODY FAKE_BAD_JSON FAKE_STATE FAKE_HTTP FAKE_LIST_DIR FAKE_LIST_FAIL FAKE_LIST_FAIL_PAGE
# The SUT hands the bearer to curl as a stdin config (`--config -`), so the self-tests do too.
ST_HDR='header = "Authorization: Bearer x"'
ST_FLAGS="--disable --noproxy '*'"
st_curl() {  # <curl args...> — runs the stub with the SUT's transport flags and the bearer on stdin
  PATH="$BIN:$PATH" bash -c "curl $ST_FLAGS \"\$@\"" _ "$@" <<< "$ST_HDR"
}
st_curl -fsS --max-time 15 --config - >/dev/null 2>&1
assert_eq "the fake curl exits 64 when handed no URL (argv fidelity, not a fixture echo)" "64" "$?"
st_curl -fsS --config - https://x.test/heartbeats/1 >/dev/null 2>&1
assert_eq "the fake curl exits 64 when the call carries no --max-time" "64" "$?"
st_curl -fsS --max-time 15 -X PATCH --config - https://x.test/heartbeats/1 --data-raw "{}" >/dev/null 2>&1
assert_eq "the fake curl exits 64 on a PATCH body it does not recognise" "64" "$?"
printf 'up' > "$FAKE_STATE/1.status"
st_curl -fsS --max-time 15 https://x.test/heartbeats/1 >/dev/null 2>&1
assert_eq "the fake curl answers 401 (and -f turns that into rc 22) with no Authorization header" "22" "$?"
printf '%s\n' 'header = "Authorization: Bearer "' | PATH="$BIN:$PATH" bash -c "curl $ST_FLAGS -fsS --max-time 15 --config - https://x.test/heartbeats/1" >/dev/null 2>&1
assert_eq "the fake curl answers 401 for an EMPTY bearer on stdin" "22" "$?"
st_curl -fsS --max-time 15 --config - https://x.test/heartbeats/1 >/dev/null 2>&1
assert_eq "the fake curl accepts a non-empty bearer arriving on stdin (200)" "0" "$?"
printf '%s\n' "$ST_HDR" | PATH="$BIN:$PATH" bash -c "curl $ST_FLAGS -fsS --max-time 15 -H 'Authorization: Bearer x' --config - https://x.test/heartbeats/1" >/dev/null 2>&1
assert_eq "the fake curl REFUSES (rc 65) a bearer on argv, even with a valid stdin config" "65" "$?"
printf '%s\n' "$ST_HDR" | PATH="$BIN:$PATH" bash -c "curl -fsS --noproxy '*' --max-time 15 --disable --config - https://x.test/heartbeats/1" >/dev/null 2>&1
assert_eq "the fake curl REFUSES (rc 66) a call whose FIRST argument is not --disable" "66" "$?"
printf '%s\n' "$ST_HDR" | PATH="$BIN:$PATH" bash -c "curl --disable -fsS --max-time 15 --config - https://x.test/heartbeats/1" >/dev/null 2>&1
assert_eq "the fake curl REFUSES (rc 66) a call with no --noproxy '*'" "66" "$?"
printf '500' > "$FAKE_HTTP/1.get"
st_curl -fsS --max-time 15 --config - https://x.test/heartbeats/1 >/dev/null 2>&1
assert_eq "the fake curl honours -f: a 500 is rc 22" "22" "$?"
# shellcheck disable=SC2034  # consumed by `assert` through eval
out_nf="$(st_curl -sS --max-time 15 --config - https://x.test/heartbeats/1 2>/dev/null; echo "rc=$?")"
assert "the fake curl WITHOUT -f exits 0 on a 500 and prints the error body (the C4 door)" \
  "[[ \"\$out_nf\" == *'rc=0'* ]]"
code_out="$(st_curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --config - https://x.test/heartbeats/1 2>/dev/null)"
assert_eq "the fake curl honours -o/-w and prints the STATUS CODE, not the body" "500" "$code_out"
rm -f "$FAKE_HTTP/1.get"
# The probes above legitimately advanced the clock, so re-zero it rather than asserting against a
# number several probes contributed to.
echo 0 > "$FAKE_CLOCK"
PATH="$BIN:$PATH" bash -c 'sleep 7'
assert_eq "the fake sleep MOVES the clock rather than no-opping" "7" "$(cat "$FAKE_CLOCK")"
assert_eq "the fake date reads that clock" "7" "$(PATH="$BIN:$PATH" bash -c 'date +%s')"
# H1 (#9980): the list endpoint is a plain stub self-test, not a mutation row. A list read without
# per_page=250 on the first page, a missing fixture and an off-origin host are all refusals, and a
# later page is reachable without per_page (a vendor `next` URL may carry `page=` alone).
printf '{"data":[],"pagination":{"next":null}}' > "$FAKE_LIST_DIR/page-1.json"
printf '{"data":[],"pagination":{"next":null}}' > "$FAKE_LIST_DIR/page-2.json"
st_curl -fsS --max-time 15 --config - 'https://uptime.betterstack.com/api/v2/heartbeats' >/dev/null 2>&1
assert_eq "H1 the fake curl exits 64 for a first list page requested WITHOUT per_page=250" "64" "$?"
st_curl -fsS --max-time 15 --config - 'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' >/dev/null 2>&1
assert_eq "H1 the fake curl serves the first list page when per_page=250 is present" "0" "$?"
st_curl -fsS --max-time 15 --config - 'https://uptime.betterstack.com/api/v2/heartbeats?page=2' >/dev/null 2>&1
assert_eq "H1 a later list page is reachable with page= alone" "0" "$?"
st_curl -fsS --max-time 15 --config - 'https://uptime.betterstack.com/api/v2/heartbeats?page=9' >/dev/null 2>&1
assert_eq "H1 a list page with no fixture exits 64 rather than answering an empty page" "64" "$?"
st_curl -fsS --max-time 15 --config - 'https://evil.example/api/v2/heartbeats?per_page=250' >/dev/null 2>&1
assert_eq "H1 an off-origin list call is refused (rc 67)" "67" "$?"
assert "H1 and the off-origin call is LOGGED first, as its own LIST row" \
  "grep -q -P '^[0-9]+\tLIST\thttps://evil.example/' '$FAKE_CALLS'"
FAKE_LIST_FAIL=500 st_curl -fsS --max-time 15 --config - 'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' >/dev/null 2>&1
assert_eq "H1 FAKE_LIST_FAIL=500 makes the list read fail (rc 22 under -f)" "22" "$?"
echo 0 > "$FAKE_CLOCK"

# --- the declared env contract is discoverable (#7659 F3) ------------------------------------
# shellcheck disable=SC2034  # consumed by `assert` through eval
help_out="$(PATH="$BIN:$PATH" bash "$SUT" --help 2>&1)"
help_rc=$?
assert_eq "--help exits 0" "0" "$help_rc"
for var in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED BS_API_BASE ARM_POLL_INTERVAL_S; do
  assert "--help documents $var" "[[ \"\$help_out\" == *'$var'* ]]"
done
for word in noop repaused partial mint-unreadable; do
  assert "--help closes the sweep outcome vocabulary at '$word'" "[[ \"\$help_out\" == *'$word'* ]]"
done
# shellcheck disable=SC2034  # consumed by `assert` through eval
bad_out="$(PATH="$BIN:$PATH" bash "$SUT" --wat 2>&1)"; bad_rc=$?
assert_eq "an unknown argument refuses with rc=1 rather than silently arming" "1" "$bad_rc"
assert "…and names the argument it rejected" "[[ \"\$bad_out\" == *'--wat'* ]]"

# --- fixture -----------------------------------------------------------------------------
# Synthesized ids only. The ADDRESSES are the SUT's real ones — they are its contract with
# tfstate, so a rename there must red this suite.
ID_ZOT1=900101; ID_NIC1=900102; ID_ZOT2=900103; ID_NIC2=900104; ID_GITDATA=900105; ID_INNGEST=900106

write_tfstate() {  # <path> [omit-id ...]
  local out="$1"; shift
  local omit=" $* "
  {
    printf '{"values":{"root_module":{"resources":['
    local first=1 pair addr id
    for pair in \
      "betteruptime_heartbeat.web_zot_consumer[\"web-1\"]|$ID_ZOT1" \
      "betteruptime_heartbeat.web_nic_guard[\"web-1\"]|$ID_NIC1" \
      "betteruptime_heartbeat.web_zot_consumer[\"web-2\"]|$ID_ZOT2" \
      "betteruptime_heartbeat.web_nic_guard[\"web-2\"]|$ID_NIC2" \
      "betteruptime_heartbeat.git_data_prd|$ID_GITDATA" \
      "betteruptime_heartbeat.inngest_consumer|$ID_INNGEST"
    do
      addr="${pair%|*}"; id="${pair##*|}"
      [[ "$omit" == *" $id "* ]] && continue
      [[ $first -eq 1 ]] || printf ','
      first=0
      printf '{"address":%s,"values":{"id":"%s"}}' "$(printf '%s' "$addr" | jq -Rs .)" "$id"
    done
    printf ']}}}\n'
  } > "$out"
}

case_setup() {  # <name> — fresh clock/calls/state for one run; every id defaults to `up`
  CASE="$WORK/$1"
  mkdir -p "$CASE/state" "$CASE/http" || { echo "FATAL: case setup failed for $1"; exit 2; }
  FAKE_CLOCK="$CASE/clock"; echo 0 > "$FAKE_CLOCK"
  FAKE_CALLS="$CASE/calls"; : > "$FAKE_CALLS"
  FAKE_GET_FAIL="$CASE/getfail"; : > "$FAKE_GET_FAIL"
  FAKE_GET_FAIL_AFTER="$CASE/getfailafter"; : > "$FAKE_GET_FAIL_AFTER"
  FAKE_PATCH_FAIL="$CASE/patchfail"; : > "$FAKE_PATCH_FAIL"
  FAKE_PATCH_FAIL_ONCE="$CASE/patchfailonce"; : > "$FAKE_PATCH_FAIL_ONCE"
  FAKE_PATCH_LOST="$CASE/patchlost"; : > "$FAKE_PATCH_LOST"
  FAKE_EMPTY_BODY="$CASE/emptybody"; : > "$FAKE_EMPTY_BODY"
  FAKE_BAD_JSON="$CASE/badjson"; : > "$FAKE_BAD_JSON"
  FAKE_CUT_COUNT="$CASE/cutcount"; : > "$FAKE_CUT_COUNT"
  FAKE_STATE="$CASE/state"
  FAKE_HTTP="$CASE/http"
  FAKE_LIST_DIR="$CASE/list"; mkdir -p "$FAKE_LIST_DIR" || { echo "FATAL: list dir failed for $1"; exit 2; }
  FAKE_LIST_FAIL=""; FAKE_LIST_FAIL_PAGE=""
  STATEFILE="$CASE/armed-unconfirmed"
  SUMMARY="$CASE/summary"; : > "$SUMMARY"
  TFSTATE="$CASE/tfstate.json"
  write_tfstate "$TFSTATE"
  local id
  for id in "$ID_ZOT1" "$ID_NIC1" "$ID_ZOT2" "$ID_NIC2" "$ID_GITDATA" "$ID_INNGEST"; do
    printf 'up' > "$FAKE_STATE/$id.status"
  done
  export FAKE_CLOCK FAKE_CALLS FAKE_GET_FAIL FAKE_GET_FAIL_AFTER FAKE_PATCH_FAIL \
         FAKE_PATCH_FAIL_ONCE FAKE_EMPTY_BODY FAKE_BAD_JSON FAKE_STATE FAKE_HTTP FAKE_CUT_COUNT \
         FAKE_LIST_DIR FAKE_LIST_FAIL FAKE_LIST_FAIL_PAGE FAKE_PATCH_LOST
}

run_sut() {  # [sut-path] -> sets OUT and RC
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token \
        TFSTATE_JSON="$TFSTATE" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        ARM_POLL_INTERVAL_S=10 \
        bash "$sut" --arm 2>&1)"
  RC=$?
}
run_sut_defaults() {  # like run_sut but exercises the OPTIONAL vars' documented defaults
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token \
        TFSTATE_JSON="$TFSTATE" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        bash "$sut" --arm 2>&1)"
  RC=$?
}
run_sweep() {  # [sut-path] -> sets OUT and RC; SWEEP_TOKEN may be set to "" by a case
  local sut="${1:-$SUT}"
  OUT="$(PATH="$BIN:$PATH" \
        BS_TOKEN="${SWEEP_TOKEN-fake-token}" \
        ARMED_UNCONFIRMED="$STATEFILE" \
        GITHUB_STEP_SUMMARY="$SUMMARY" \
        bash "$sut" --sweep 2>&1)"
  RC=$?
}
patch_bodies() { awk -F'\t' '$2=="PATCH"{print $3" "$4}' "$FAKE_CALLS"; }
patch_count()  { patch_bodies | grep -c '' ; }
get_urls()     { awk -F'\t' '$2=="GET"{print $3}' "$FAKE_CALLS"; }
state_lines()  { if [[ -f "$STATEFILE" ]]; then grep -c '' "$STATEFILE"; else echo 0; fi; }
observed_clock() { cat "$FAKE_CLOCK"; }
reported_elapsed() {  # <deadline> — the elapsed the SUT PRINTS, distinct from the observed clock
  printf '%s' "$OUT" | sed -n "s/.*never reached 'up' within \([0-9]*\)s of a $1s deadline.*/\1/p" | sed -n '1p'
}

# --- T1: the steady state — every monitor already up ---------------------------------------
echo "--- T1 the modal merge: every monitor already armed"
case_setup t1
run_sut
assert_eq "T1 exits 0" "0" "$RC"
assert_eq "T1 reports every one of the six arms as a no-op" "6" \
  "$(printf '%s' "$OUT" | grep -c 'already armed (status=up)')"
assert_eq "T1 issues NO PATCH at all" "0" "$(patch_count)"
assert_eq "T1 never writes the unconfirmed-arm state file" "0" "$(state_lines)"
assert "T1 positive control: the fake curl was actually invoked" "[[ -s '$FAKE_CALLS' ]]"
assert "T1 enters no poll loop (observed clock is six GETs, nothing more)" \
  "[[ \$(observed_clock) -le 120 ]]"

# --- T1b: the op/state gate SKIP SET is every not-paused status, not just `up` ---------------
# Every fixture used to start `up`, so narrowing the gate to `== "up"` was invisible — and it
# would unpause a monitor sitting `down` and poll it to its deadline on every apply (#7656 C5).
echo "--- T1b a monitor sitting down / pending is skipped, not unpaused"
case_setup t1b
printf 'down'    > "$FAKE_STATE/$ID_ZOT1.status"
printf 'pending' > "$FAKE_STATE/$ID_NIC1.status"
run_sut
assert_eq "T1b exits 0" "0" "$RC"
assert "T1b treats a DOWN monitor as already armed (the gate skips every non-paused status)" \
  "[[ \"\$OUT\" == *'already armed (status=down)'* ]]"
assert "T1b treats a PENDING monitor the same way" \
  "[[ \"\$OUT\" == *'already armed (status=pending)'* ]]"
assert_eq "T1b issues NO PATCH — neither monitor is unpaused" "0" "$(patch_count)"
assert "T1b enters no poll loop for either (observed clock is six GETs)" \
  "[[ \$(observed_clock) -le 120 ]]"

# --- T2: inngest paused, feeder dark — the soft landing -------------------------------------
echo "--- T2 inngest_consumer paused with a dark feeder"
case_setup t2
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '2026-08-20T09:15:00.000Z' > "$FAKE_STATE/$ID_INNGEST.updated"
run_sut
assert_eq "T2 exits 0 — a dark feeder is soft-landed, not an apply failure" "0" "$RC"
assert "T2 emits the ::warning:: rather than an apply-failing error" \
  "[[ \"\$OUT\" == *'::warning::inngest-consumer'* ]]"
assert "T2 names the 30s deadline from the variable, never a literal 230" \
  "[[ \"\$OUT\" == *'no beat within 30s'* ]]"
assert "T2 does NOT tell the reader the probe is broken (the pre-#7587 instruction)" \
  "[[ \"\$OUT\" != *'the probe or the private-net path is broken'* ]]"
# The fixture makes an unpaused-but-unfed monitor read `pending`; what is asserted is that the SUT
# ECHOES whatever status it observed, not that `pending` is the value Better Stack would return —
# this change measured no vendor semantics and the message claims none.
assert "T2 echoes the status Better Stack reported AT ROLLBACK" \
  "[[ \"\$OUT\" == *'status=pending'* ]]"
assert "T2 emits the monitor's updated_at" \
  "[[ \"\$OUT\" == *'updated_at=2026-08-20T09:15:00.000Z'* ]]"
# #7658 E2: the retracted claim. `updated_at` is a record-mutation timestamp and this run PATCHes
# the record, so the pair cannot separate 'never beat' from 'not due yet' — and the repo measured
# no such semantics.
assert "T2 does NOT claim the two fields discriminate a missed beat (unmeasured vendor semantics)" \
  "[[ \"\$OUT\" != *'separate '* ]]"
assert "T2 warns the reader off reading a beat into updated_at" \
  "[[ \"\$OUT\" == *'record-mutation timestamp'* ]]"
assert "T2 says a healthy feeder misses most windows, so the warning is not read as a fault" \
  "[[ \"\$OUT\" == *'five windows in six'* ]]"
assert_eq "T2 unpauses then rolls back — exactly two PATCHes" "2" "$(patch_count)"
assert "T2's FIRST PATCH is the unpause" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert "T2's LAST PATCH is paused:true — the inverse would leave it live-and-unfed" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T2 clears the state file once the rollback returns 2xx" "0" "$(state_lines)"

# --- T2b: a rollback that gets HTTP 500 is NOT a successful rollback -------------------------
# `curl -fsS` used to be the whole predicate. Without -f curl exits 0 on a 5xx, so this case is
# the door C4 named: the id would leave the books and the monitor would stay live-and-unfed under
# a GREEN apply. `hb_patch_paused` now reads `%{http_code}`.
echo "--- T2c the rollback PATCH returns HTTP 500"
case_setup t2c
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '500' > "$FAKE_HTTP/$ID_INNGEST.patch-true"
run_sut
assert_eq "T2c exits 1 — a 5xx rollback is a FAILED rollback, not a soft landing" "1" "$RC"
assert "T2c names the HTTP status in the error" "[[ \"\$OUT\" == *'HTTP 500'* ]]"
assert_eq "T2c leaves the id on the re-pause sweep's books" "1" "$(state_lines)"

# --- T2d: an unpause that gets HTTP 500 never puts the id on the books -----------------------
echo "--- T2d the unpause PATCH returns HTTP 500"
case_setup t2d
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '500' > "$FAKE_HTTP/$ID_INNGEST.patch-false"
run_sut
assert_eq "T2d exits 1" "1" "$RC"
assert "T2d says the unpause failed, with its status" \
  "[[ \"\$OUT\" == *'PATCH paused=false FAILED (HTTP 500)'* ]]"
assert_eq "T2d writes no state — nothing was ever unpaused" "0" "$(state_lines)"

# --- T2e/T2f: the rollback retries a transient, and does NOT retry a 4xx (#7658 E8) -----------
# The rollback is the one write whose failure reds a routine apply, and while #7228 is open the
# inngest arm executes it on EVERY merge — ~990 unretried round-trips a year, any one of which
# could raise a false ops alarm on a lost packet.
echo "--- T2e a 5xx rollback that succeeds on the retry is NOT a failed rollback"
case_setup t2e
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true 500\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL_ONCE"
FAKE_CURL_COST=1 run_sut
assert_eq "T2e exits 0 — a transient lost round-trip is not an unpaused-and-unfed monitor" "0" "$RC"
assert "T2e says it retried, rather than retrying silently" \
  "[[ \"\$OUT\" == *'returned HTTP 500 — retrying once'* ]]"
assert "T2e does NOT declare the monitor unpaused-and-unfed" "[[ \"\$OUT\" != *'unpaused-and-unfed'* ]]"
assert_eq "T2e issues three PATCHes: unpause, failed rollback, successful rollback" "3" "$(patch_count)"
assert "T2e's LAST PATCH is paused:true" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T2e clears the books" "0" "$(state_lines)"
assert "T2e still soft-lands with the feeder verdict (the arm itself worked)" \
  "[[ \"\$OUT\" == *'no beat within 30s'* ]]"

echo "--- T2f a 403 rollback is NOT retried: a 4xx does not fix itself on an immediate second call"
case_setup t2f
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '403' > "$FAKE_HTTP/$ID_INNGEST.patch-true"
FAKE_CURL_COST=1 run_sut
assert_eq "T2f exits 1" "1" "$RC"
assert_eq "T2f issues exactly two PATCHes — no wasted retry" "2" "$(patch_count)"
assert "T2f does not claim to have retried" "[[ \"\$OUT\" != *'retrying once'* ]]"
assert "T2f names the status and the attempt count" "[[ \"\$OUT\" == *'HTTP 403'* ]]"

# --- T3: the wall-clock bound (Guard 2 row 6) -----------------------------------------------
echo "--- T3 the deadline is wall clock, not a sleep tally"
case_setup t3
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
FAKE_CURL_COST=15 run_sut
assert_eq "T3 exits 1 — a zot-consumer that never beats is fatal, unlike inngest" "1" "$RC"
e_t3="$(reported_elapsed 200)"
assert "T3 reports an elapsed at all" "[[ -n '$e_t3' ]]"
# Correct accounting stops one iteration past the deadline: 200 <= reported <= 200 + (10 + 15).
assert "T3 reports an elapsed inside one iteration of the 200s deadline" \
  "[[ '${e_t3:-99999}' -ge 200 && '${e_t3:-99999}' -le 225 ]]"
# The OBSERVED clock is the assertion that can actually see the defect. Correct: ~340s
# (arm GET+PATCH 30, nine 25s iterations 225, rollback 15, five trailing GETs 75).
# Pre-#7587 sleep-tally: ~620s, because it needs 20 iterations to tally 200.
assert "T3 the OBSERVED clock stays under 420s — the reported number alone cannot see this" \
  "[[ \$(observed_clock) -le 420 ]]"
assert "T3 positive control: the clock did advance past the deadline" "[[ \$(observed_clock) -ge 200 ]]"

# --- T4: a beat lands inside the window -----------------------------------------------------
echo "--- T4 a real beat lands: ARMED, and the id leaves the books"
case_setup t4
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '10'     > "$FAKE_STATE/$ID_INNGEST.upat"   # flips to up once the clock passes 10s
FAKE_CURL_COST=1 run_sut
assert_eq "T4 exits 0" "0" "$RC"
assert "T4 declares the monitor ARMED on a measured beat" "[[ \"\$OUT\" == *'a real beat landed. ARMED'* ]]"
assert_eq "T4 issues ONLY the unpause — no rollback on a successful arm" "1" "$(patch_count)"
assert "T4's single PATCH is the unpause" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert_eq "T4 removes the id from the state file on reaching up" "0" "$(state_lines)"
# The second half of the self-clearing property the 30s deadline is chosen to PRESERVE: the next
# apply must be a no-op, reached through `already armed`, not through a second unpause. Asserted
# as a SEQUENCE against the same fixture — T1 proves the no-op on a monitor that was never
# touched, which is a different premise from one this gate armed a moment ago.
patches_after_arm="$(patch_count)"
FAKE_CURL_COST=1 run_sut
assert_eq "T4 the NEXT apply exits 0" "0" "$RC"
assert "T4 the next apply no-ops via already armed, never a second unpause" \
  "[[ \"\$OUT\" == *'inngest-consumer (web-1): already armed (status=up)'* ]]"
assert_eq "T4 the next apply issues no PATCH at all" "$patches_after_arm" "$(patch_count)"

# --- T5: the rollback itself fails ----------------------------------------------------------
echo "--- T5 the rollback PATCH fails: the id STAYS on the sweep's books and the apply reds"
case_setup t5
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"   # the ROLLBACK fails; the unpause succeeds
run_sut
assert_eq "T5 exits 1 even for the SOFT caller — a failed rollback is about the arming" "1" "$RC"
assert "T5 reached the rollback (positive control: the unpause did succeed)" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert "T5 says the monitor is unpaused-and-unfed" "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
assert "T5 does NOT emit the soft FEEDER verdict (that would leave the job green)" \
  "[[ \"\$OUT\" != *'no beat within'* ]]"
assert_eq "T5 leaves exactly the failed id on the re-pause sweep's books" "1" "$(state_lines)"
assert "T5's remaining id is the right one" "[[ \"\$(cat '$STATEFILE')\" == '$ID_INNGEST' ]]"

# --- T6: per-id removal, not truncation -----------------------------------------------------
echo "--- T6 two arms unpaused, one rollback fails: the file keeps ONE id, not zero and not two"
case_setup t6
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_sut
assert_eq "T6 exits 1" "1" "$RC"
assert_eq "T6 keeps exactly one id" "1" "$(state_lines)"
assert "T6 keeps the FAILED rollback's id, not the successful one" \
  "[[ \"\$(cat '$STATEFILE')\" == '$ID_INNGEST' ]]"

# --- T6b: state_remove cannot install a TRUNCATED file (#7658 E3) -----------------------------
# `grep -vxF … > keep || true` swallowed grep's exit >= 2 as readily as its exit 1, so an
# unreadable source produced an EMPTY `keep` that `mv -f` then installed over the whole state
# file — dropping a PRIOR arm's failed-rollback id, which is the only reason the file ever holds
# more than one line, and leaving that monitor live-and-unfed.
echo "--- T6b a state file that cannot be read is left INTACT, never replaced with nothing"
case_setup t6b
printf '%s\n%s\n' "$ID_ZOT2" "$ID_NIC2" > "$STATEFILE"
chmod 000 "$STATEFILE"
# shellcheck disable=SC2034  # consumed by `assert` through eval
sr_out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" \
  ARMED_UNCONFIRMED="$STATEFILE" \
  bash -c 'source /dev/stdin <<< "$(sed -n "/^state_remove()/,/^}/p" "$1")"; state_remove 999; echo "rc=$?"' _ "$SUT" 2>&1)"
chmod 644 "$STATEFILE"
assert "T6b state_remove REFUSES rather than returning 0 on an unreadable source" \
  "[[ \"\$sr_out\" == *'rc=1'* ]]"
assert "T6b it says so loudly" "[[ \"\$sr_out\" == *'::error::'* ]]"
assert_eq "T6b the state file still holds BOTH ids" "2" "$(state_lines)"
assert "T6b no .keep temp file is left behind" \
  "[[ -z \"\$(find '$CASE' -name 'armed-unconfirmed.keep.*' 2>/dev/null)\" ]]"

# --- T7: a GET that fails is not a feeder verdict --------------------------------------------
echo "--- T7 GET failure is 'the gate could not do its job', never a rollback"
case_setup t7
printf '%s\n' "$ID_ZOT1" > "$FAKE_GET_FAIL"
run_sut
assert_eq "T7 exits 1" "1" "$RC"
assert "T7 names the failing GET" "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7 issues no PATCH — nothing was ever unpaused" "0" "$(patch_count)"
assert_eq "T7 writes no state" "0" "$(state_lines)"

# --- T7b: hb_fetch fails CLOSED on an empty 200 and on a 200 with no status -------------------
# Both guards were unreachable: no fixture could produce a 200 whose body was empty or whose JSON
# lacked `.data.attributes.status`, so `|| return 1` could be deleted from either with both suites
# green (#7656 C5).
echo "--- T7b a 200 with an empty body, and a 200 with no status field, both fail CLOSED"
case_setup t7b
printf '%s\n' "$ID_ZOT1" > "$FAKE_EMPTY_BODY"
run_sut
assert_eq "T7b (empty body) exits 1" "1" "$RC"
assert "T7b (empty body) reports it as a failed lookup, not as a status" \
  "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7b (empty body) issues no PATCH" "0" "$(patch_count)"
case_setup t7c
printf '%s\n' "$ID_ZOT1" > "$FAKE_BAD_JSON"
run_sut
assert_eq "T7c (200 with no .status) exits 1" "1" "$RC"
assert "T7c (200 with no .status) reports a failed lookup rather than arming on an empty status" \
  "[[ \"\$OUT\" == *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
assert_eq "T7c (200 with no .status) issues no PATCH" "0" "$(patch_count)"

# --- T7d: a MID-LOOP loss of visibility is not a feeder verdict (#7658 E1) --------------------
# The first GET succeeds (so the arm starts) and every later one fails. `ARM_LAST_STATUS` used to
# retain the PRE-UNPAUSE reading, so the terminal message reported `status=paused` as an
# observation — affirmatively wrong, since at rollback the monitor is unpaused — and a total loss
# of Better Stack visibility rendered as a benign feeder miss with the apply exiting 0.
echo "--- T7d every in-loop GET fails after the first: unknown, and rc=1 rather than a soft landing"
case_setup t7d
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '%s 1\n' "$ID_INNGEST" > "$FAKE_GET_FAIL_AFTER"
FAKE_CURL_COST=1 run_sut
assert_eq "T7d exits 1 — no status was read, so no assertion about the FEEDER is available" "1" "$RC"
assert "T7d does NOT report the stale pre-unpause status" "[[ \"\$OUT\" != *'status=paused'* ]]"
assert "T7d names the visibility loss explicitly" \
  "[[ \"\$OUT\" == *'every status read during the 30s poll FAILED'* ]]"
assert "T7d does NOT emit the soft feeder verdict" "[[ \"\$OUT\" != *'no beat within'* ]]"
assert "T7d still rolled the monitor back to paused" \
  "[[ \"\$(patch_bodies | tail -1)\" == '$ID_INNGEST {\"paused\":true}' ]]"
assert_eq "T7d clears the books — the rollback did return 2xx" "0" "$(state_lines)"

# --- T7e: a vendor string cannot forge a workflow command (#7658 E7) --------------------------
echo "--- T7e a CR/LF inside updated_at cannot break out of the annotation"
case_setup t7e
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
printf '2026-01-01T00:00:00Z\\n::error::FORGED-BY-VENDOR-STRING' > "$FAKE_STATE/$ID_INNGEST.updated"
FAKE_CURL_COST=1 run_sut
assert "T7e no line in the output BEGINS with the forged workflow command" \
  "! printf '%s' \"\$OUT\" | grep -c '^::error::FORGED-BY-VENDOR-STRING' >/dev/null"
assert "T7e the vendor text is still carried, inline, where it cannot be parsed as a command" \
  "[[ \"\$OUT\" == *'FORGED-BY-VENDOR-STRING'* ]]"

# --- T8: an address absent from tfstate is a no-op --------------------------------------------
echo "--- T8 git_data_prd absent from the merge-path tfstate"
case_setup t8
write_tfstate "$TFSTATE" "$ID_GITDATA"
run_sut
assert_eq "T8 exits 0" "0" "$RC"
assert "T8 reports the absent address by name" "[[ \"\$OUT\" == *'git-data-prd: not present in tfstate'* ]]"
assert_eq "T8 still arms the other five" "5" \
  "$(printf '%s' "$OUT" | grep -c 'already armed (status=up)')"

# --- W: web-bash-synthetic (#10455 b), one literal arm per host --------------------------------
# The two ids are added to a COPY of the standard fixture so every row above keeps its six-address premise (T8 counts five
# "already armed" lines). The beat is born paused and this gate is its only unpause path.
ID_WBS1=900107; ID_WBS2=900108
add_wbs() {  # adds both web_bash_synthetic addresses to $TFSTATE and gives them a status
  jq --arg a1 'betteruptime_heartbeat.web_bash_synthetic["web-1"]' --arg i1 "$ID_WBS1" \
     --arg a2 'betteruptime_heartbeat.web_bash_synthetic["web-2"]' --arg i2 "$ID_WBS2" \
     '.values.root_module.resources += [{"address":$a1,"values":{"id":$i1}},{"address":$a2,"values":{"id":$i2}}]' \
     "$TFSTATE" > "$TFSTATE.wbs" || { echo "FATAL: add_wbs jq failed"; exit 2; }
  mv "$TFSTATE.wbs" "$TFSTATE" || { echo "FATAL: add_wbs mv failed"; exit 2; }
  printf 'paused' > "$FAKE_STATE/$ID_WBS1.status"
  printf 'paused' > "$FAKE_STATE/$ID_WBS2.status"
}
echo "--- W1 both web-bash-synthetic beats dark: a SOFT landing, one rollback per host"
case_setup w1
add_wbs
run_sut
assert_eq "W1 exits 0: an unlanded beat is soft (the first merge can precede the image that carries the resolver)" "0" "$RC"
assert "W1 names web-1 in a ::warning::" "[[ \"\$OUT\" == *'::warning::web-bash-synthetic (web-1): no beat within 300s'* ]]"
assert "W1 names web-2 in a ::warning::" "[[ \"\$OUT\" == *'::warning::web-bash-synthetic (web-2): no beat within 300s'* ]]"
assert "W1 says the first-apply case is expected (probe_absent), not a fault" "[[ \"\$OUT\" == *'reason=probe_absent'* ]]"
assert_eq "W1 issues four PATCHes: unpause and rollback, per host" "4" "$(patch_count)"
assert "W1 sequence is web-1 unpause, web-1 rollback, web-2 unpause, web-2 rollback" \
  "[[ \"\$(patch_bodies | tr '\n' '|')\" == '$ID_WBS1 {\"paused\":false}|$ID_WBS1 {\"paused\":true}|$ID_WBS2 {\"paused\":false}|$ID_WBS2 {\"paused\":true}|' ]]"
assert_eq "W1 leaves nothing on the re-pause sweep's books (both rolled back)" "0" "$(state_lines)"

echo "--- W2 a beat lands for web-1 only: web-1 ARMED, web-2 soft-lands"
case_setup w2
add_wbs
printf '10' > "$FAKE_STATE/$ID_WBS1.upat"
FAKE_CURL_COST=1 run_sut
assert_eq "W2 exits 0" "0" "$RC"
assert "W2 declares web-1 ARMED on a measured beat" "[[ \"\$OUT\" == *'web-bash-synthetic (web-1): status=up within'* ]]"
assert "W2 soft-lands web-2" "[[ \"\$OUT\" == *'::warning::web-bash-synthetic (web-2): no beat within 300s'* ]]"

echo "--- W3 a FAILED rollback on a web-bash-synthetic arm is a real failure, never the soft landing"
case_setup w3
add_wbs
printf '%s true\n' "$ID_WBS2" > "$FAKE_PATCH_FAIL"
run_sut
assert_eq "W3 exits 1" "1" "$RC"
assert "W3 says the monitor is unpaused-and-unfed" "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
assert "W3 leaves exactly the failed id on the sweep's books" "[[ \"\$(cat '$STATEFILE')\" == '$ID_WBS2' ]]"

echo "--- W4 already armed: a true no-op naming each host"
case_setup w4
add_wbs
printf 'up' > "$FAKE_STATE/$ID_WBS1.status"; printf 'up' > "$FAKE_STATE/$ID_WBS2.status"
run_sut
assert_eq "W4 exits 0" "0" "$RC"
assert "W4 no-ops web-1" "[[ \"\$OUT\" == *'web-bash-synthetic (web-1): already armed (status=up)'* ]]"
assert "W4 no-ops web-2" "[[ \"\$OUT\" == *'web-bash-synthetic (web-2): already armed (status=up)'* ]]"
assert_eq "W4 issues no PATCH" "0" "$(patch_count)"

echo "--- W5 host coverage: every var.web_hosts member has a literal arm_one for each per-host beat"
# The keys come from variables.tf, not from this file: a member added there with no arm_one makes its beat born paused and
# DARK forever, and nothing else notices (the post-merge read-back is the only other net).
INFRA_DIR_W="$(cd "$(dirname "$SUT")" && pwd)"
web_hosts_keys() { awk '/variable "web_hosts"/{f=1} f&&/default *= *\{/{d=1} d&&/^    "web-[0-9]+" *= *\{/{gsub(/[ ="{]/,"",$1); print $1} f&&/^}/{exit}' "$INFRA_DIR_W/variables.tf"; }
host_coverage_missing() {  # <sut path> <keys...>: prints each "<beat>/<key>" lacking a literal arm_one
  local sut="$1" k beat; shift
  for beat in web_zot_consumer web_nic_guard web_bash_synthetic; do
    for k in "$@"; do
      grep -vE '^[[:space:]]*#' "$sut" | grep -qF "arm_one 'betteruptime_heartbeat.${beat}[\"${k}\"]'" || echo "${beat}/${k}"
    done
  done
}
mapfile -t WH_KEYS < <(web_hosts_keys)
assert "W5 read at least web-1 and web-2 from variables.tf (the extraction is not vacuous)" "[[ \" \${WH_KEYS[*]} \" == *' web-1 '* && \" \${WH_KEYS[*]} \" == *' web-2 '* ]]"
assert_eq "W5 no per-host beat lacks an arm_one" "" "$(host_coverage_missing "$SUT" "${WH_KEYS[@]}")"
grep -v "web_bash_synthetic\[\"web-2\"\]" "$SUT" > "$WORK/w5-no-web2.sh" || { echo "FATAL: w5 mutant build failed"; exit 2; }
assert "W5 RED control: a SUT without the web-2 web_bash_synthetic arm is reported missing" \
  "[[ \"\$(host_coverage_missing '$WORK/w5-no-web2.sh' \"\${WH_KEYS[@]}\")\" == 'web_bash_synthetic/web-2' ]]"
assert "W5 RED control: a new var.web_hosts member (web-3) with no arm_one is reported for every beat" \
  "[[ \"\$(host_coverage_missing '$SUT' web-3 | tr '\n' ' ')\" == 'web_zot_consumer/web-3 web_nic_guard/web-3 web_bash_synthetic/web-3 ' ]]"

# --- T8b: a READABLE but CONTENTLESS tfstate refuses (#7658 E10) -------------------------------
echo "--- T8b a readable-but-empty tfstate is a refusal, not six silent skips and a green apply"
case_setup t8b
printf '{"values":{"root_module":{"resources":[]}}}\n' > "$TFSTATE"
run_sut
assert_eq "T8b exits 1" "1" "$RC"
assert "T8b says the state holds no resources" "[[ \"\$OUT\" == *'holds no resources'* ]]"
assert_eq "T8b issues no API call at all" "0" "$(get_urls | grep -c '' || true)"

# --- T9: a half-configured invocation refuses ------------------------------------------------
echo "--- T9 missing contract env fails closed"
case_setup t9
for missing in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED; do
  out="$(PATH="$BIN:$PATH" \
        BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
        env -u "$missing" bash "$SUT" --arm 2>&1)"
  rc=$?
  assert_eq "T9 refuses with rc=1 when $missing is unset" "1" "$rc"
  assert "T9 names $missing in the refusal" "[[ \"\$out\" == *'$missing is unset'* ]]"
done

# --- T10: the two OPTIONAL contract vars' documented defaults are exercised (#7659 F3) --------
# `run_sut` always exported both, so neither default was ever executed: `ARM_POLL_INTERVAL_S`
# could go `:-10 → :-1` (a 6x production API-call rate) and `BS_API_BASE` could point anywhere,
# with both suites green.
echo "--- T10 running with NEITHER optional var set exercises the shipped defaults"
case_setup t10
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CURL_COST=0 run_sut_defaults
assert_eq "T10 exits 0 (the soft inngest landing)" "0" "$RC"
# With cost 0 the clock advances only by the sleeps, so the observed clock IS the poll interval
# times the iteration count. A 30s deadline at the documented default of 10 is exactly 3 sleeps.
assert_eq "T10 the DEFAULT poll interval is 10s: a 30s deadline costs exactly 3 sleeps" "30" "$(observed_clock)"
# The GET COUNT is what a shrunken poll interval moves; the clock alone does not (30 sleeps of 1s
# reach 30 exactly as 3 sleeps of 10 do). Baseline: five no-op GETs + inngest's pre-loop GET +
# three in-loop polls = 9.
assert_eq "T10 the default interval costs exactly 9 GETs, not one per second" "9" "$(get_urls | grep -c '')"
assert "T10 the DEFAULT BS_API_BASE is the production Better Stack API" \
  "grep -q 'https://uptime.betterstack.com/api/v2/heartbeats/' <<< \"\$(grep -o 'BS_API_BASE:-[^}]*' '$SUT')/heartbeats/\""

# --- T12: the bearer's destination and shape are guarded BEFORE any request (#7797/#7873) ------
# The token rides curl's stdin config channel. Two things must hold before a single request: it is
# sent only to the production API root (BS_API_BASE is env-settable, so it is pinned against that
# literal — a test needing another destination shims curl instead), and a token whose shape could
# smuggle a config directive onto that channel (a newline, a quote, a space) is never sent at all.
echo "--- T12 off-pin BS_API_BASE, unusable token and xtrace all refuse with ZERO requests"
case_setup t12a
out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
      BS_API_BASE="https://evil.example/api/v2" bash "$SUT" --arm 2>&1)"; rc=$?
assert_eq "T12 --arm refuses an off-pin BS_API_BASE with rc=1" "1" "$rc"
assert "T12 and names BS_API_BASE in the refusal" "[[ \"\$out\" == *'BS_API_BASE must be https://uptime.betterstack.com/api/v2'* ]]"
assert_eq "T12 and made ZERO requests" "0" "$(grep -c '' "$FAKE_CALLS")"
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token ARMED_UNCONFIRMED="$STATEFILE" \
      BS_API_BASE="https://evil.example/api/v2" bash "$SUT" --sweep 2>&1)"; rc=$?
assert_eq "T12 --sweep refuses an off-pin BS_API_BASE with rc=1" "1" "$rc"
assert_eq "T12 and the sweep made ZERO requests" "0" "$(grep -c '' "$FAKE_CALLS")"
case_setup t12b
for bad_tok in $'tok\nurl = "https://evil.example/"' 'tok en' 'tok"en'; do
  out="$(PATH="$BIN:$PATH" BS_TOKEN="$bad_tok" TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
        bash "$SUT" --arm 2>&1)"; rc=$?
  assert_eq "T12 --arm refuses an unusable-shape token with rc=1" "1" "$rc"
  assert_eq "T12 and made ZERO requests" "0" "$(grep -c '' "$FAKE_CALLS")"
done
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
out="$(PATH="$BIN:$PATH" BS_TOKEN=$'tok\nurl = "https://evil.example/"' ARMED_UNCONFIRMED="$STATEFILE" \
      GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SUT" --sweep 2>&1)"; rc=$?
assert_eq "T12 --sweep with an unusable-shape token fails (rc=1)" "1" "$rc"
assert "T12 and reports outcome=mint-unreadable naming the id it could not re-pause" \
  "[[ \"\$out\" == *'outcome=mint-unreadable'* && \"\$out\" == *'cannot re-pause them: $ID_ZOT1'* ]]"
assert_eq "T12 and the sweep made ZERO requests" "0" "$(grep -c '' "$FAKE_CALLS")"
case_setup t12c
out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token-fp-xtrace TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
      bash -x "$SUT" --arm 2>&1)"; rc=$?
assert_eq "T12 refuses to run under xtrace with rc=78" "78" "$rc"
assert "T12 and no fingerprint of the token reaches the trace" "[[ \"\$out\" != *'fake-token-fp-xtrace'* ]]"
assert_eq "T12 and made ZERO requests under xtrace" "0" "$(grep -c '' "$FAKE_CALLS")"

# --- T11: THE EXTERNAL CUT — the window the sweep exists for (plan scenario 8) ----------------
# The premise every S-case takes as given: that when the apply job is ended at its budget while an
# arm is in flight, the id is ALREADY on the sweep's books. Nothing asserted it. The script says so
# in a comment ("the id is on the sweep's books from the instant the monitor is live, not from the
# instant we decide to give up") and MEASURED: moving `state_add` from before the poll loop to just
# before the rollback left all 190 assertions green — every case that reads the state file reads it
# after `arm_one` has returned, which is the one moment the cut never happens at. So this case
# stops the SUT mid-poll and reads the books at that instant, then hands them to the real sweep.
echo "--- T11 the job is cut mid-poll: the id is on the books, and the sweep re-pauses it"
case_setup t11
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CUT_AFTER=2 FAKE_CURL_COST=1 run_sut
assert "T11 the SUT really was cut (non-zero, and not its own soft landing)" "[[ \"\$RC\" -ne 0 ]]"
assert "T11 the cut landed INSIDE the poll, before any rollback could run" \
  "[[ \"\$OUT\" != *'no beat within'* && \"\$OUT\" != *'ROLLED BACK'* ]]"
assert_eq "T11 exactly one PATCH was issued — the unpause, with no rollback behind it" "1" "$(patch_count)"
assert "T11 that PATCH was the unpause, so the monitor is LIVE at the moment of the cut" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_INNGEST {\"paused\":false}' ]]"
assert_eq "T11 the id is on the re-pause sweep's books AT THE CUT, not only after a give-up" "1" "$(state_lines)"
assert "T11 and it is the right id" "[[ \"\$(cat '$STATEFILE')\" == '$ID_INNGEST' ]]"
# …and the `always()` sweep, reading the file the cut left behind, closes the window.
run_sweep
assert_eq "T11 the sweep exits 0 on the books the cut left" "0" "$RC"
assert "T11 the sweep re-pauses exactly the cut monitor" \
  "[[ \"\$OUT\" == *'armed=1 repaused=1 failed=0 outcome=repaused'* ]]"
assert_eq "T11 the monitor is paused again — the window is closed" "paused" "$(cat "$FAKE_STATE/$ID_INNGEST.status")"

# =================================================================================================
# --- S: the re-pause sweep (#7659) --------------------------------------------------------------
# =================================================================================================
# No suite executed the sweep at all before this: it was ~45 lines of bash inside a YAML scalar,
# and the ten regexes that "guarded" it included an `exit 1` assertion satisfied by an unrelated
# `exit 1` in the mint-unreadable branch.
echo "--- S1 nothing on the books: the modal case reports outcome=noop and exits 0"
case_setup s1
run_sweep
assert_eq "S1 exits 0" "0" "$RC"
assert "S1 reports outcome=noop rather than staying silent" "[[ \"\$OUT\" == *'outcome=noop'* ]]"
assert "S1 emits the structured tag as an ANNOTATION, which has a REST API" \
  "[[ \"\$OUT\" == *'::notice::heartbeat-repause-sweep armed=0 repaused=0 failed=0 outcome=noop'* ]]"
assert "S1 also writes the run summary block, so 'the counts are in the run summary' is TRUE" \
  "grep -q '^armed=0 repaused=0 failed=0 outcome=noop$' '$SUMMARY'"
assert_eq "S1 issues no API call" "0" "$(patch_count)"

echo "--- S2 two ids on the books, both re-pause cleanly"
case_setup s2
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
run_sweep
assert_eq "S2 exits 0" "0" "$RC"
assert_eq "S2 issues exactly two PATCHes" "2" "$(patch_count)"
assert "S2's PATCHes are both paused:true" \
  "[[ \"\$(patch_bodies | grep -c '{\"paused\":true}')\" == 2 ]]"
assert "S2 counts them: armed=2 repaused=2 failed=0" \
  "[[ \"\$OUT\" == *'armed=2 repaused=2 failed=0 outcome=repaused'* ]]"
assert "S2 names the ids it found, not just the count" \
  "[[ \"\$OUT\" == *\"$ID_ZOT1 $ID_NIC1\"* ]]"
assert "S2 says the previously-applied infrastructure is unaffected" \
  "[[ \"\$OUT\" == *'previously-applied infrastructure is unaffected'* ]]"

echo "--- S3 one of two returns HTTP 500: partial, and the step FAILS rather than annotating"
case_setup s3
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
run_sweep
assert_eq "S3 exits 1 — ::error:: does not fail a step, and a still-live monitor must red the run" "1" "$RC"
assert "S3 counts the split: armed=2 repaused=1 failed=1" \
  "[[ \"\$OUT\" == *'armed=2 repaused=1 failed=1 outcome=partial'* ]]"
assert "S3 names the id it could not re-pause, with its HTTP status" \
  "[[ \"\$OUT\" == *'heartbeat $ID_NIC1 returned HTTP 500'* ]]"
assert "S3 still re-paused the one it could (the loop does not abort at the first failure)" \
  "[[ \"\$OUT\" == *'re-paused heartbeat $ID_ZOT1'* ]]"
assert "S3 writes the partial outcome to the run summary too" \
  "grep -q 'outcome=partial' '$SUMMARY'"

echo "--- S4 the token could not be minted: mint-unreadable, and the IDS are printed"
case_setup s4
printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
SWEEP_TOKEN="" run_sweep
assert_eq "S4 exits 1" "1" "$RC"
assert "S4 reports outcome=mint-unreadable" "[[ \"\$OUT\" == *'outcome=mint-unreadable'* ]]"
assert "S4 prints the monitor IDS — the only thing that lets an operator re-pause by hand" \
  "[[ \"\$OUT\" == *\"$ID_ZOT1 $ID_NIC1\"* ]]"
assert "S4 tells the operator where to click" "[[ \"\$OUT\" == *'Better Stack'* ]]"
# `::error::` is not decoration: it is what puts the line in the run's annotation list, which has
# a REST API — and it is that API the notify job's `cause` step reads. Downgrading the prefix to a
# plain `echo` left every other S4 assertion green while the operator's only machine-readable
# signal disappeared. The credential is named in the same line, so the reader knows WHAT failed.
assert "S4 emits it as an ::error:: ANNOTATION, naming the credential it could not read" \
  "[[ \"\$OUT\" == *'::error::Re-pause sweep: no Better Stack API token'* ]]"
assert_eq "S4 attempts no PATCH (it has no credential to attempt one with)" "0" "$(patch_count)"

echo "--- S5 the sweep is IDEMPOTENT: re-PATCHing an already-paused monitor is a no-op"
case_setup s5
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
run_sweep
assert_eq "S5 exits 0 — an already-paused monitor is still a clean re-pause" "0" "$RC"
assert "S5 counts it as re-paused" "[[ \"\$OUT\" == *'armed=1 repaused=1 failed=0'* ]]"
assert_eq "S5 the monitor is still paused afterwards" "paused" "$(cat "$FAKE_STATE/$ID_ZOT1.status")"

echo "--- S6 a blank line in the state file is skipped, not PATCHed as an empty id"
case_setup s6
printf '%s\n\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
run_sweep
assert_eq "S6 exits 0" "0" "$RC"
assert_eq "S6 issues two PATCHes, not three" "2" "$(patch_count)"

echo "--- S7 --sweep refuses when its one required var is unset"
case_setup s7
# shellcheck disable=SC2034  # consumed by `assert` through eval
s7_out="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token env -u ARMED_UNCONFIRMED bash "$SUT" --sweep 2>&1)"
s7_rc=$?
assert_eq "S7 exits 1" "1" "$s7_rc"
assert "S7 names ARMED_UNCONFIRMED" "[[ \"\$s7_out\" == *'ARMED_UNCONFIRMED is unset'* ]]"

# =================================================================================================
# --- ST / AX / AO: `--status <name>` and `--arm-one <name> [--id <id>]` (#9980) -------------------
# =================================================================================================
# The named-monitor arm resolves its id by EXACT name over the whole paginated list, never from tfstate,
# so everything that can go wrong with that resolution (a near-name, a duplicate on a later page, a
# vendor 200 with no `.data`, a `next` that leaves the vendor's origin) is a case here, and every refusal
# asserts ZERO PATCH: a refusal that happens after the unpause is not a refusal.
HOST_NAME="soleur-git-data-host-prd"
ID_HOST=900201; ID_DUP=900202; ID_OTHER=900203; ID_DECOY=900204
LIST_BASE="https://uptime.betterstack.com/api/v2/heartbeats"

hb_row() {  # <id> <name> <status> [period] [grace] -> one list row
  local paused=false
  [[ "$3" == paused ]] && paused=true
  printf '{"id":"%s","type":"heartbeat","attributes":{"name":%s,"status":"%s","paused":%s,"period":%s,"grace":%s}}' \
    "$1" "$(printf '%s' "$2" | jq -Rs .)" "$3" "$paused" "${4:-60}" "${5:-300}"
}
write_page() {  # <n> <next-url-or-empty> <row>... -> $FAKE_LIST_DIR/page-<n>.json
  local n="$1" next="$2" nxt=null joined
  shift 2
  [[ -z "$next" ]] || nxt="\"$next\""
  joined="$(IFS=,; printf '%s' "$*")"
  printf '{"data":[%s],"pagination":{"first":"f","last":"l","prev":null,"next":%s}}' "$joined" "$nxt" > "$FAKE_LIST_DIR/page-$n.json"
}
run_named() {  # <args...> -> OUT/RC. tfstate and books are UNSET unless a case sets NEW_TFSTATE / ARMONE_BOOKS.
  OUT="$(PATH="$BIN:$PATH" BS_TOKEN="${NEW_TOKEN-fake-token}" ARM_POLL_INTERVAL_S="${NEW_POLL:-10}" TMPDIR="$CASE" \
        env -u TFSTATE_JSON -u ARMED_UNCONFIRMED ${NEW_TFSTATE:+TFSTATE_JSON="$TFSTATE"} ${ARMONE_BOOKS:+ARMED_UNCONFIRMED="$ARMONE_BOOKS"} \
        bash "${NEW_SUT:-$SUT}" "$@" 2>&1)"
  RC=$?
}
list_count() { awk -F'\t' '$2=="LIST"' "$FAKE_CALLS" | grep -c ''; }
call_count() { grep -c '' "$FAKE_CALLS"; }
books_files() { ls "$CASE"/arm-one-unconfirmed.* 2>/dev/null; }
books_count() { books_files | grep -c ''; }
new_case() {  # <name> — a case with the monitor under test PAUSED and listed once
  case_setup "$1"
  printf 'paused' > "$FAKE_STATE/$ID_HOST.status"
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
}

echo "--- ST1 --status: one exact match prints its fields, rc 0, zero PATCH, no tfstate needed"
new_case st1
run_named --status "$HOST_NAME"
assert_eq "ST1 exits 0" "0" "$RC"
assert "ST1 prints name, id, paused, status, period and grace" \
  "[[ \"\$OUT\" == *'name=$HOST_NAME id=$ID_HOST paused=true status=paused period=60 grace=300'* ]]"
assert_eq "ST1 issues no PATCH" "0" "$(patch_count)"
assert_eq "ST1 reads the list exactly once and nothing by id" "1" "$(list_count)"
assert_eq "ST1 makes no per-id GET" "0" "$(get_urls | grep -c '')"

echo "--- ST2 --status: zero matches is rc 1"
new_case st2
write_page 1 "" "$(hb_row "$ID_OTHER" "some-other-monitor" up)"
run_named --status "$HOST_NAME"
assert_eq "ST2 exits 1" "1" "$RC"
assert "ST2 says nothing is named that" "[[ \"\$OUT\" == *'no heartbeat is named'* ]]"
assert_eq "ST2 issues no PATCH" "0" "$(patch_count)"

echo "--- ST3 --status: two exact-name rows are a collision, rc 1, both ids named"
new_case st3
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST3 exits 1" "1" "$RC"
assert "ST3 names both ids" "[[ \"\$OUT\" == *'$ID_HOST'* && \"\$OUT\" == *'$ID_DUP'* ]]"

echo "--- ST3b near-names, case variants and regex bait never match; the exact name still does"
new_case st3b
write_page 1 "" "$(hb_row "$ID_DECOY" "Soleur-Git-Data-Host-Prd" paused)" \
  "$(hb_row "$ID_DECOY" "${HOST_NAME}-staging" paused)" \
  "$(hb_row "$ID_DECOY" "x-${HOST_NAME}" paused)" \
  "$(hb_row "$ID_DECOY" "soleur.git.data.host.prd" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST3b decoys alone: exits 1 (zero matches)" "1" "$RC"
write_page 1 "" "$(hb_row "$ID_DECOY" "Soleur-Git-Data-Host-Prd" paused)" \
  "$(hb_row "$ID_DECOY" "${HOST_NAME}-staging" paused)" \
  "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" \
  "$(hb_row "$ID_DECOY" "soleur.git.data.host.prd" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST3b next to the exact row: exits 0" "0" "$RC"
assert "ST3b and resolves the EXACT id, not a decoy" "[[ \"\$OUT\" == *'id=$ID_HOST '* ]]"
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
run_named --status "soleur.git.data.host.prd"
assert_eq "ST3b a name with '.' where the monitor has '-' matches nothing (no regex)" "1" "$RC"

echo "--- ST4 --status: the match sits on page 2 of 3"
new_case st4
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
write_page 2 "$LIST_BASE?page=3&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
write_page 3 "" "$(hb_row "$ID_DECOY" "decoy-two" up)"
run_named --status "$HOST_NAME"
assert_eq "ST4 exits 0" "0" "$RC"
assert_eq "ST4 read all three pages" "3" "$(list_count)"
assert "ST4 resolves the page-2 id" "[[ \"\$OUT\" == *'id=$ID_HOST '* ]]"

echo "--- ST4b an off-origin pagination.next is refused and never requested"
new_case st4b
write_page 1 "https://evil.example/api/v2/heartbeats?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
run_named --status "$HOST_NAME"
assert_eq "ST4b exits 1" "1" "$RC"
assert_eq "ST4b makes exactly one list request (the off-origin one is never made)" "1" "$(list_count)"
assert "ST4b nothing was sent to the evil host" "! grep -q 'evil.example' '$FAKE_CALLS'"

echo "--- ST4c an endless next chain is cut at exactly 20 requests"
new_case st4c
for n in $(seq 1 25); do
  write_page "$n" "$LIST_BASE?page=$((n + 1))&per_page=250" "$(hb_row "$ID_DECOY" "decoy-$n" up)"
done
run_named --status "$HOST_NAME"
assert_eq "ST4c exits 1" "1" "$RC"
assert_eq "ST4c made exactly 20 list requests" "20" "$(list_count)"

echo "--- ST4d a next URL carrying a parameter other than page/per_page is refused"
new_case st4d
write_page 1 "$LIST_BASE?page=2&per_page=250&name=$HOST_NAME" "$(hb_row "$ID_DECOY" "decoy-one" up)"
run_named --status "$HOST_NAME"
assert_eq "ST4d exits 1" "1" "$RC"
assert_eq "ST4d the extra-parameter URL is never requested" "1" "$(list_count)"

echo "--- ST5 --status: an unreadable list is a FAILED read, never zero or one match"
new_case st5a
FAKE_LIST_FAIL=500 run_named --status "$HOST_NAME"
assert_eq "ST5a a 500 is rc 1" "1" "$RC"
new_case st5b
FAKE_LIST_FAIL=empty run_named --status "$HOST_NAME"
assert_eq "ST5b an empty 200 is rc 1" "1" "$RC"
new_case st5c
FAKE_LIST_FAIL=garbage run_named --status "$HOST_NAME"
assert_eq "ST5c a non-JSON 200 is rc 1" "1" "$RC"
new_case st5d
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
printf '{}' > "$FAKE_LIST_DIR/page-2.json"
run_named --status "$HOST_NAME"
assert_eq "ST5d a 200 with no .data on a LATER page is rc 1 (a hidden duplicate could sit there)" "1" "$RC"
new_case st5e
write_page 1 "" "$(hb_row "not-a-number" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST5e a matching row with a malformed id is rc 1, never skipped" "1" "$RC"
new_case st5f
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused null 300)"
run_named --status "$HOST_NAME"
assert_eq "ST5f a null period still lets --status read the row" "0" "$RC"
assert "ST5f and prints it as null, with grace NOT shifted into period" \
  "[[ \"\$OUT\" == *'period=null grace=300'* ]]"

echo "--- AX argument refusals make zero requests"
new_case ax1
run_named --status
assert_eq "AX1 --status with no name exits 1" "1" "$RC"
assert "AX1 and says so rather than dying on an unbound variable" \
  "[[ \"\$OUT\" == *'::error::'* && \"\$OUT\" != *'unbound variable'* ]]"
run_named --status -- 
assert_eq "AX2 a leading-dash name exits 1" "1" "$RC"
run_named --status "bad name"
assert_eq "AX3 a name outside the charset exits 1" "1" "$RC"
run_named --status "$HOST_NAME" --id 5
assert_eq "AX4 --id with --status exits 1" "1" "$RC"
run_named --arm-one "$HOST_NAME" --id abc
assert_eq "AX5 a non-numeric --id exits 1" "1" "$RC"
run_named --arm-one "$HOST_NAME" extra
assert_eq "AX6 an extra argument exits 1" "1" "$RC"
run_named --arm-one "$HOST_NAME" --id
assert_eq "AX6b a dangling --id exits 1" "1" "$RC"
NEW_TOKEN="" run_named --status "$HOST_NAME"
assert_eq "AX7 an empty token exits 1" "1" "$RC"
NEW_TOKEN='a"b' run_named --status "$HOST_NAME"
assert_eq "AX8 a token of an unexpected shape exits 1" "1" "$RC"
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token BS_API_BASE="https://evil.example/api/v2" bash "$SUT" --status "$HOST_NAME" 2>&1)"; RC=$?
assert_eq "AX9 an off-pin BS_API_BASE exits 1" "1" "$RC"
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token bash -x "$SUT" --status "$HOST_NAME" 2>&1)"; RC=$?
assert_eq "AX10 --status refuses to run under xtrace (rc 78)" "78" "$RC"
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token bash -x "$SUT" --arm-one "$HOST_NAME" 2>&1)"; RC=$?
assert_eq "AX11 --arm-one refuses to run under xtrace (rc 78)" "78" "$RC"
assert_eq "AX makes no request at all, across every refusal above" "0" "$(call_count)"

echo "--- AO1 --arm-one: a unique exact name is unpaused, reaches up, rc 0, books left empty and removed"
new_case ao1
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO1 exits 0" "0" "$RC"
assert_eq "AO1 issues exactly one PATCH" "1" "$(patch_count)"
assert "AO1 and it is the unpause of the resolved id" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_HOST {\"paused\":false}' ]]"
assert "AO1 reports a real beat" "[[ \"\$OUT\" == *'a real beat landed. ARMED.'* ]]"
assert "AO1 printed the private books path BEFORE the first PATCH (it is in the output)" \
  "[[ \"\$OUT\" == *'$CASE/arm-one-unconfirmed.'* ]]"
assert_eq "AO1 the empty private books file was removed" "0" "$(books_count)"
assert_eq "AO1 read the list and only the resolved id (never the six per-merge ids)" "$ID_HOST" "$(get_urls | sort -u | tr '\n' ' ' | sed 's/ $//')"
assert "AO1 listed before it touched anything" "[[ \$(list_count) -ge 1 ]]"

echo "--- AO2 --arm-one: never up is rolled back to paused, rc 2, exactly two PATCHes"
new_case ao2
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO2 exits 2 (the gate worked and the feeder did not feed)" "2" "$RC"
assert_eq "AO2 issues exactly two PATCHes" "2" "$(patch_count)"
assert "AO2 the first is paused:false, the second paused:true" \
  "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_HOST {\"paused\":false}' && \"\$(patch_bodies | sed -n '2p')\" == '$ID_HOST {\"paused\":true}' ]]"
assert_eq "AO2 the monitor is paused again" "paused" "$(cat "$FAKE_STATE/$ID_HOST.status")"
assert_eq "AO2 the books file is empty again and removed" "0" "$(books_count)"
ao2_rep="$(reported_elapsed 150)"
assert "AO2 reports an elapsed within one iteration of the 150s deadline (${ao2_rep:-none}s)" \
  "[[ -n '$ao2_rep' && '${ao2_rep:-0}' -ge 150 && '${ao2_rep:-999}' -le 175 ]]"
assert "AO2 the OBSERVED clock stays inside deadline + 85s + list ($(observed_clock)s)" "[[ \$(observed_clock) -le 245 ]]"
assert "AO2 on rc 2 it names the git-data-liveness events to read, not web-1" \
  "[[ \"\$OUT\" == *'stage liveness'* ]]"

echo "--- AO2b --arm-one: a failed rollback keeps the books, prints the recovery, and --sweep closes it"
new_case ao2b
printf '%s true\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO2b exits 1" "1" "$RC"
assert_eq "AO2b the books file is KEPT" "1" "$(books_count)"
assert "AO2b and holds the id" "[[ \"\$(cat \"\$(books_files | sed -n '1p')\")\" == '$ID_HOST' ]]"
ao2b_path="$(printf '%s\n' "$OUT" | sed -n 's/.*ARMED_UNCONFIRMED=\([^ ]*\) bash .*--sweep.*/\1/p' | sed -n '1p')"
assert "AO2b the printed recovery command names that very file" \
  "[[ -n '$ao2b_path' && '$ao2b_path' == \"\$(books_files | sed -n '1p')\" ]]"
: > "$FAKE_PATCH_FAIL"
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token ARMED_UNCONFIRMED="$ao2b_path" bash "$SUT" --sweep 2>&1)"; RC=$?
assert_eq "AO2b the printed sweep command re-pauses the monitor (rc 0)" "0" "$RC"
assert_eq "AO2b and the monitor is paused again" "paused" "$(cat "$FAKE_STATE/$ID_HOST.status")"

echo "--- AO3 --arm-one: a name collision refuses with zero PATCH, even when the duplicate is on page 2"
new_case ao3
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
write_page 2 "" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME"
assert_eq "AO3 exits 1" "1" "$RC"
assert_eq "AO3 issues no PATCH" "0" "$(patch_count)"
assert_eq "AO3 reads no monitor by id" "0" "$(get_urls | grep -c '')"
assert "AO3 names both ids" "[[ \"\$OUT\" == *'$ID_HOST'* && \"\$OUT\" == *'$ID_DUP'* ]]"

echo "--- AO4 --arm-one: the --id pin must equal the resolved id"
new_case ao4a
run_named --arm-one "$HOST_NAME" --id "$ID_OTHER"
assert_eq "AO4a a pin that differs from the resolved id exits 1" "1" "$RC"
assert "AO4a and says the pin does not match" "[[ \"\$OUT\" == *'id pin mismatch'* ]]"
assert_eq "AO4a issues no PATCH" "0" "$(patch_count)"
new_case ao4b
write_page 1 "" "$(hb_row "$ID_OTHER" "some-other-monitor" paused)"
run_named --arm-one "$HOST_NAME" --id "$ID_OTHER"
assert_eq "AO4b a pin never substitutes for the name: zero name matches exits 1" "1" "$RC"
assert_eq "AO4b issues no PATCH" "0" "$(patch_count)"
new_case ao4c
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO4c a matching pin proceeds and arms" "0" "$RC"
new_case ao4d
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME"
assert_eq "AO4d no pin at all also proceeds (the pin is optional)" "0" "$RC"

echo "--- AO5 --arm-one: an already-live monitor is never reported as armed unless it is up"
for st in up down pending; do
  new_case "ao5-$st"
  printf '%s' "$st" > "$FAKE_STATE/$ID_HOST.status"
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" "$st")"
  FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  if [[ "$st" == up ]]; then
    assert_eq "AO5 ($st) exits 0 (nothing to change, and it is beating)" "0" "$RC"
    assert "AO5 ($st) reports outcome=already-up" "[[ \"\$OUT\" == *'outcome=already-up rc=0'* ]]"
  else
    assert_eq "AO5 ($st) exits 1: live but not up is NOT an arm" "1" "$RC"
    assert "AO5 ($st) reports outcome=live-not-up" "[[ \"\$OUT\" == *'outcome=live-not-up rc=1'* ]]"
    assert "AO5 ($st) says no beat was measured" "[[ \"\$OUT\" == *'did NOT arm it'* ]]"
  fi
  assert "AO5 ($st) says already armed (arm_one's own no-op line)" "[[ \"\$OUT\" == *'already armed (status=$st)'* ]]"
  assert_eq "AO5 ($st) issues no PATCH" "0" "$(patch_count)"
  assert_eq "AO5 ($st) leaves nothing on the books" "0" "$(books_count)"
done

echo "--- AO6 --arm-one: the ceiling is the monitor's own period + grace - 40, both sides of the boundary"
new_case ao6a
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 100)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6a grace 100 (ceiling 120 < 150) is refused, rc 1" "1" "$RC"
assert_eq "AO6a with zero PATCH" "0" "$(patch_count)"
new_case ao6b
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 130)"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6b grace 130 (ceiling == 150) is ALLOWED and arms" "0" "$RC"
new_case ao6c
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 129)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6c grace 129 (ceiling 149 < 150) is refused" "1" "$RC"
assert_eq "AO6c with zero PATCH" "0" "$(patch_count)"
new_case ao6d
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused null 300)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6d a null period fails CLOSED (rc 1)" "1" "$RC"
assert_eq "AO6d with zero PATCH" "0" "$(patch_count)"
new_case ao6e
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 null)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6e a null grace fails CLOSED (rc 1)" "1" "$RC"
assert_eq "AO6e with zero PATCH" "0" "$(patch_count)"

echo "--- AO7 --arm-one with a caller-supplied ARMED_UNCONFIRMED uses it and leaves it alone when empty"
new_case ao7
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO7 exits 0" "0" "$RC"
assert_eq "AO7 creates no private mktemp file of its own" "0" "$(books_count)"

echo "--- AO8 an exported ARM_ONE_ID is inert on --arm"
case_setup ao8
ARM_ONE_ID=1 run_sut
assert_eq "AO8 --arm still exits 0" "0" "$RC"
assert "AO8 and never reads id 1" "! grep -qx 1 < <(get_urls)"

echo "--- AO9 --help documents the new modes"
# shellcheck disable=SC2034  # consumed by `assert` through eval
help2="$(PATH="$BIN:$PATH" bash "$SUT" --help 2>&1)"
for word in '--status' '--arm-one' '--id'; do
  assert "AO9 --help documents $word" "[[ \"\$help2\" == *'$word'* ]]"
done

# --- review round (#9980): behaviours the panel found missing ------------------------------------
echo "--- ST1b --status prints an up monitor's paused=false"
new_case st1b
printf 'up' > "$FAKE_STATE/$ID_HOST.status"
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" up)"
run_named --status "$HOST_NAME"
assert "ST1b paused=false status=up is printed verbatim" "[[ \"\$OUT\" == *'paused=false status=up period=60 grace=300'* ]]"

echo "--- ST3c the SAME row twice (an overlapping page) is a collision, never de-duplicated"
new_case st3c
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST3c exits 1" "1" "$RC"
assert "ST3c says two heartbeats carry the name" "[[ \"\$OUT\" == *'2 heartbeats are named'* ]]"

echo "--- ST5g-i a malformed .pagination is a FAILED read, never the end of the list"
new_case st5g
printf '{"data":[%s],"pagination":"oops"}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5g a string .pagination exits 1" "1" "$RC"
assert "ST5g and names the malformed pagination" "[[ \"\$OUT\" == *'malformed .pagination'* ]]"
new_case st5h
printf '{"data":[%s],"pagination":[]}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5h an array .pagination exits 1" "1" "$RC"
new_case st5i
printf '{"data":[%s],"pagination":{"next":5}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5i a numeric pagination.next exits 1" "1" "$RC"
new_case st5i2
printf '{"data":[%s]}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5i2 NO .pagination at all is a single page and resolves (exit 0)" "0" "$RC"

echo "--- ST5j-k ids are validated BEFORE any stripping, and an empty/null id is refused"
new_case st5j
printf '{"data":[{"id":"42\\n43","attributes":{"name":"%s","status":"paused","period":60,"grace":300}}],"pagination":{"next":null}}' "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5j an id of '42<LF>43' exits 1 (it must not become 4243)" "1" "$RC"
assert "ST5j and names the non-numeric id" "[[ \"\$OUT\" == *'non-numeric id'* ]]"
new_case st5k
printf '{"data":[{"id":"","attributes":{"name":"%s","status":"paused","period":60,"grace":300}}],"pagination":{"next":null}}' "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5k an EMPTY-string id exits 1 (not silently skipped)" "1" "$RC"
new_case st5k2
printf '{"data":[{"id":null,"attributes":{"name":"%s","status":"paused","period":60,"grace":300}}],"pagination":{"next":null}}' "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5k2 a null id exits 1" "1" "$RC"

echo "--- ST5l-m later-page failures"
new_case st5l
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
printf '{"data":{"k":%s},"pagination":{"next":null}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-2.json"
run_named --status "$HOST_NAME"
assert_eq "ST5l a .data OBJECT on page 2 exits 1" "1" "$RC"
new_case st5m
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
write_page 2 "" "$(hb_row "$ID_DECOY" "decoy-one" up)"
FAKE_LIST_FAIL=500 FAKE_LIST_FAIL_PAGE=2 run_named --status "$HOST_NAME"
assert_eq "ST5m an HTTP 500 on page 2 exits 1 although page 1 resolved" "1" "$RC"

echo "--- ST5n vendor strings never reach the terminal raw"
new_case st5n
printf '{"data":[{"id":"%s","attributes":{"name":"%s","status":"up\\u001b]52;c;x\\u0007","period":60,"grace":300}}],"pagination":{"next":null}}' "$ID_HOST" "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST5n exits 0" "0" "$RC"
st5n_ctl=0
[[ "$OUT" == *$'\x1b'* || "$OUT" == *$'\x07'* ]] && st5n_ctl=1
assert_eq "ST5n the output carries no ESC or BEL byte" "0" "$st5n_ctl"
assert "ST5n the vendor status is shown reduced to a harmless charset" "[[ \"\$OUT\" == *'status=up??52?c?x?'* ]]"

echo "--- AX2 more argument and environment refusals (zero requests)"
new_case ax2
run_named --arm-one "$HOST_NAME" --id ""
assert_eq "AX2a an EMPTY --id exits 1 (the pin cannot be dropped by an empty variable)" "1" "$RC"
run_named --arm-one "$HOST_NAME" --bogus 7
assert_eq "AX2b an unknown flag in the --id slot exits 1" "1" "$RC"
for bad in abc 0 -5 1000 1.5; do
  NEW_POLL="$bad" run_named --status "$HOST_NAME"
  assert_eq "AX2c ARM_POLL_INTERVAL_S='$bad' exits 1" "1" "$RC"
  assert "AX2c ARM_POLL_INTERVAL_S='$bad' says why" "[[ \"\$OUT\" == *'ARM_POLL_INTERVAL_S must be'* ]]"
done
run_named --status $'x\ny'
assert_eq "AX2d a name with a newline exits 1" "1" "$RC"
assert "AX2d and echoes it sanitised, never as a second line" "[[ \"\$OUT\" == *'got '\\''x?y'\\'''* ]]"
assert_eq "AX2 makes no request at all" "0" "$(call_count)"
run_named --arm-one --help
assert_eq "AX2e --arm-one --help prints the help and exits 0" "0" "$RC"
assert "AX2e and documents the machine verdict" "[[ \"\$OUT\" == *'arm-one-result'* ]]"

echo "--- AO11 the machine verdict line, per outcome"
new_case ao11a
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO11a armed: the LAST line is the verdict" \
  "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == \"::notice::arm-one-result name=$HOST_NAME id=$ID_HOST outcome=armed rc=0\" ]]"
new_case ao11b
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO11b never up: outcome=rolled-back rc=2" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=rolled-back rc=2' ]]"
new_case ao11c
printf '%s true\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO11c failed rollback: outcome=rollback-failed rc=1" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=rollback-failed rc=1' ]]"
assert_eq "AO11c the kept private books file is mode 600" "600" "$(stat -c %a "$(books_files | sed -n '1p')")"
assert "AO11c the recovery command is printed again at the end, not only up front" \
  "[[ \$(printf '%s\\n' \"\$OUT\" | grep -c -- '--sweep') -ge 2 ]]"
assert "AO11c and it names the write-scope token the sweep needs" "[[ \"\$OUT\" == *'WRITE-scope BS_TOKEN'* ]]"
new_case ao11d
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
run_named --arm-one "$HOST_NAME"
assert "AO11d a refusal: outcome=refused rc=1" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=refused rc=1' ]]"

echo "--- AO12 the books path is printed BEFORE the first PATCH"
new_case ao12
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO12 the books notice precedes the unpausing line" \
  "[[ \"\$(printf '%s\\n' \"\$OUT\" | awk '/arm-one books:/{a=NR} /unpausing/{b=NR} END{print (a>0 && b>0 && a<b) ? 1 : 0}')\" == 1 ]]"

echo "--- AO6f the ceiling reads the monitor's own PERIOD too"
new_case ao6f
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 30 130)"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6f period 30 + grace 130 (ceiling 120 < 150) is refused" "1" "$RC"
assert_eq "AO6f with zero PATCH" "0" "$(patch_count)"
new_case ao6g
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 80 110)"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6g period 80 + grace 110 (ceiling exactly 150) is allowed" "0" "$RC"

echo "--- AO7b-d a caller-supplied books file"
new_case ao7b
printf '%s\n' 777 > "$CASE/mine"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO7b arms (rc 0) although the caller's file already lists an unrelated id" "0" "$RC"
assert "AO7b and does NOT blame this run for the unrelated line" "[[ \"\$OUT\" != *'still lists'* ]]"
assert_eq "AO7b the caller's file is left exactly as it was" "777" "$(cat "$CASE/mine")"
new_case ao7c
ARMONE_BOOKS="$CASE/nope/dir/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO7c an unwritable books path exits 1" "1" "$RC"
assert_eq "AO7c BEFORE the first PATCH" "0" "$(patch_count)"
assert "AO7c and says so" "[[ \"\$OUT\" == *'must be absent or a readable, writable regular file'* ]]"
new_case ao7d
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
ARMONE_BOOKS="$CASE/mine2" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO7d a caller-supplied EMPTY books file is never deleted" "[[ -e '$CASE/mine2' && ! -s '$CASE/mine2' ]]"

echo "--- AO10 an unpause whose REPLY was lost is read back and rolled back"
new_case ao10
printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO10 exits 1 (the arm did not complete)" "1" "$RC"
assert_eq "AO10 the monitor that really went live is paused again" "paused" "$(cat "$FAKE_STATE/$ID_HOST.status")"
assert_eq "AO10 two PATCHes: the lost unpause, then the rollback" "2" "$(patch_count)"
assert "AO10 the verdict says it recovered" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=unpause-recovered rc=1' ]]"
assert_eq "AO10 nothing is left on the books" "0" "$(books_count)"
new_case ao10b
printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
printf '%s 1\n' "$ID_HOST" > "$FAKE_GET_FAIL_AFTER"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO10b exits 1" "1" "$RC"
assert "AO10b the unreadable monitor is NOT assumed paused: it says so" "[[ \"\$OUT\" == *'could not be read back'* ]]"
assert_eq "AO10b and its id is kept on the books for the sweep" "$ID_HOST" "$(cat "$(books_files | sed -n '1p')")"

echo "--- AO10c-e an unpause that FAILED is recorded before it was sent, and read back"
new_case ao10c
printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO10c an unpause that answers 500 (not applied) exits 1" "1" "$RC"
assert_eq "AO10c exactly one PATCH: a monitor that reads paused is not 'rolled back'" "1" "$(patch_count)"
assert "AO10c the verdict is unpause-unknown (the request may still land late), not failed" \
  "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=unpause-unknown rc=1' ]]"
assert_eq "AO10c its id stays on the books (an ambiguous 5xx can still apply)" "$ID_HOST" "$(cat "$(books_files | sed -n '1p')")"
assert "AO10c and the books file is named with a status-read instruction" "[[ \"\$OUT\" == *'read --status after 60-120 s'* ]]"
new_case ao10d
printf '%s false 403\n' "$ID_HOST" > "$FAKE_PATCH_FAIL_ONCE"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO10d a definite 4xx rejection exits 1" "1" "$RC"
assert "AO10d the verdict is failed (nothing can land later)" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=failed rc=1' ]]"
assert_eq "AO10d and the books are clean again (the private file was removed)" "0" "$(books_count)"
new_case ao10e
printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
printf '%s true\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO10e a lost unpause whose rollback also fails exits 1" "1" "$RC"
assert "AO10e the verdict is rollback-failed" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=rollback-failed rc=1' ]]"
assert_eq "AO10e the monitor is LIVE (the fixture's lost unpause applied)" "pending" "$(cat "$FAKE_STATE/$ID_HOST.status")"
assert_eq "AO10e and its id is on the books for the sweep" "$ID_HOST" "$(cat "$(books_files | sed -n '1p')")"

echo "--- AO21-AO27 the id is on the books BEFORE the unpause request arrives, and the books are checked, not trusted"
# A permission-based case is only meaningful where chmod is enforced (not as root). The same number of assertions
# runs either way, so the exact floor below holds on every host.
PERMS_ENFORCED=1
: > "$WORK/perm-probe"; chmod 444 "$WORK/perm-probe"
if ( : >> "$WORK/perm-probe" ) 2>/dev/null; then PERMS_ENFORCED=0; fi
chmod 644 "$WORK/perm-probe"
perm_assert() {  # <description> <condition> -- skipped (counted as a pass) where the filesystem ignores chmod
  if [[ "$PERMS_ENFORCED" -eq 1 ]]; then assert "$1" "$2"; else pass "$1 (skipped: chmod is not enforced for this user)"; fi
}
perm_restore() { chmod 755 "$CASE/bk" 2>/dev/null; chmod 644 "$CASE/bk/books" 2>/dev/null; return 0; }
last_verdict() { printf '%s\n' "$OUT" | tail -n 1; }

new_case ao21
printf '777\n' > "$CASE/mine"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_SNAP_BOOKS="$CASE/mine" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO21 the arm succeeds (rc 0)" "0" "$RC"
assert "AO21 the books ALREADY held the id when the unpause PATCH arrived" "grep -qxF '$ID_HOST' '$FAKE_CALLS.booksnap'"
assert "AO21 and the caller's other line was kept alongside it" "grep -qxF 777 '$FAKE_CALLS.booksnap'"

new_case ao22
printf '99' > "$CASE/mine"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_SNAP_BOOKS="$CASE/mine" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO22 a books file with no trailing newline keeps its last line (99) on a line of its own" "grep -qxF 99 '$FAKE_CALLS.booksnap'"
assert "AO22 and the id is its OWN line, never glued onto it (99$ID_HOST)" "grep -qxF '$ID_HOST' '$FAKE_CALLS.booksnap' && ! grep -qF '99$ID_HOST' '$FAKE_CALLS.booksnap'"
assert_eq "AO22 the arm succeeds (rc 0)" "0" "$RC"

new_case ao23
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
FAKE_HOOK_GET="chmod 444 '$CASE/bk/books'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
perm_restore
perm_assert "AO23 an id that cannot be recorded stops the run BEFORE any PATCH" "[[ \$(patch_count) -eq 0 ]]"
perm_assert "AO23 rc 1, outcome failed" "[[ \$RC -eq 1 && \"\$(last_verdict)\" == *'outcome=failed rc=1' ]]"
perm_assert "AO23 and it says nothing was changed" "[[ \"\$OUT\" == *'nothing was changed'* ]]"
assert_eq "AO23 the monitor is still paused" "paused" "$(cat "$FAKE_STATE/$ID_HOST.status")"

new_case ao24a
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_HOOK_PATCH_FALSE="chmod 555 '$CASE/bk'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
perm_restore
perm_assert "AO24a armed stays armed (rc 0) when the cleanup cannot rewrite the books" "[[ \$RC -eq 0 && \"\$(last_verdict)\" == *'outcome=armed rc=0' ]]"
perm_assert "AO24a and the leftover line is reported" "[[ \"\$OUT\" == *'still lists $ID_HOST'* ]]"
new_case ao24b
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
FAKE_HOOK_PATCH_FALSE="chmod 555 '$CASE/bk'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
perm_restore
perm_assert "AO24b rolled-back stays rolled-back (rc 2) with an unrewritable books file" "[[ \$RC -eq 2 && \"\$(last_verdict)\" == *'outcome=rolled-back rc=2' ]]"
new_case ao24c
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
FAKE_HOOK_PATCH_FALSE="chmod 555 '$CASE/bk'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
perm_restore
perm_assert "AO24c unpause-recovered stays unpause-recovered (rc 1) with an unrewritable books file" "[[ \$RC -eq 1 && \"\$(last_verdict)\" == *'outcome=unpause-recovered rc=1' ]]"

new_case ao25
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_HOOK_PATCH_FALSE="chmod 000 '$CASE/bk/books'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
perm_restore
perm_assert "AO25 a books file that became UNREADABLE counts as still listing the id" "[[ \"\$OUT\" == *'still lists $ID_HOST'* ]]"
perm_assert "AO25 and the outcome is unchanged (armed, rc 0)" "[[ \$RC -eq 0 && \"\$(last_verdict)\" == *'outcome=armed rc=0' ]]"

new_case ao26
printf '%s\n' "$ID_HOST" > "$CASE/mine"
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
printf '%s\n' "$ID_HOST" > "$FAKE_GET_FAIL"
ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO26 a gate read that never answers is outcome=failed, zero PATCH" "[[ \"\$(last_verdict)\" == *'outcome=failed rc=1' && \$(patch_count) -eq 0 ]]"
assert "AO26 the leftover line does NOT claim the monitor was left paused (this run never read it)" "[[ \"\$OUT\" != *'left paused'* ]]"
assert "AO26 it says the state was not established and to read --status first" "[[ \"\$OUT\" == *'did not establish whether'* && \"\$OUT\" == *'Read --status FIRST'* ]]"

new_case ao27
printf '%s false 000\n' "$ID_HOST" > "$FAKE_PATCH_FAIL_ONCE"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO27 an unpause that dies with HTTP 000 (a --max-time kill) is unpause-unknown" "[[ \"\$(last_verdict)\" == *'outcome=unpause-unknown rc=1' ]]"
assert_eq "AO27 and its id stays on the books" "$ID_HOST" "$(cat "$(books_files | sed -n '1p')")"
new_case ao28
: > "$CASE/mine"; chmod 200 "$CASE/mine"
ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
chmod 644 "$CASE/mine"
perm_assert "AO28 a write-only (unreadable) books file is refused before any PATCH" "[[ \$(patch_count) -eq 0 && \$RC -eq 1 ]]"
new_case ao29
mkdir -p "$CASE/ro"; chmod 555 "$CASE/ro"
ARMONE_BOOKS="$CASE/ro/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
chmod 755 "$CASE/ro"
perm_assert "AO29 a books path whose directory cannot be written is refused before any PATCH" "[[ \$(patch_count) -eq 0 && \$RC -eq 1 ]]"
new_case ao30
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"; chmod 555 "$CASE/bk"
ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
chmod 755 "$CASE/bk"
perm_assert "AO30 a books file with no room for a scratch file beside it is refused (the cleanup could never run)" "[[ \$(patch_count) -eq 0 && \$RC -eq 1 ]]"

echo "--- AO31 a page-2 failure never names an id; a non-printing character in a books path is shown as ?"
new_case ao31
write_page 1 "https://uptime.betterstack.com/api/v2/heartbeats?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
FAKE_LIST_FAIL=garbage FAKE_LIST_FAIL_PAGE=2 FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO31 the verdict after a page-2 failure says id=none" "[[ \"\$(last_verdict)\" == *'id=none outcome=refused rc=1' ]]"
new_case ao32
BIDI="$(printf '\xe2\x80\xae')"
UTF8_OK=0
if LC_ALL=C.UTF-8 grep -q x < <(printf x) 2>/dev/null && [[ "$(LC_ALL=C.UTF-8 bash -c 'printf "%s" "$LC_ALL"' 2>/dev/null)" == C.UTF-8 ]]; then UTF8_OK=1; fi
LC_ALL=C.UTF-8 FAKE_CURL_COST=1 ARMONE_BOOKS="$CASE/x${BIDI}Y/books" run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO32 the refusal for that path is printed" "[[ \"\$OUT\" == *'must be absent or a readable, writable regular file'* ]]"
if [[ "$UTF8_OK" -eq 1 ]]; then
  assert "AO32 a bidi override in the books path is not printed raw, even in a UTF-8 locale" "[[ \"\$OUT\" != *\"\$BIDI\"* ]]"
else
  pass "AO32 a bidi override in the books path is not printed raw (skipped: no UTF-8 locale)"
fi
new_case ao34
mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
FAKE_HOOK_GET="rm -f '$CASE/bk/books'; ln -s /dev/null '$CASE/bk/books'" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO34 an id appended into a file that does not keep it is caught by the read-back: zero PATCH, outcome=failed" "[[ \$(patch_count) -eq 0 && \"\$(last_verdict)\" == *'outcome=failed rc=1' && \"\$OUT\" == *'could not be read back'* ]]"
new_case ao33
printf '{"data":[%s],"pagination":{"next":"\\n"}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert "AO33 a pagination.next that is only a newline is a refused partial read, not the end of the list" "[[ \$RC -eq 1 && \"\$OUT\" == *'malformed .pagination'* ]]"

echo "--- AO13 the books path must be a real, readable regular file (or absent)"
new_case ao13a
ARMONE_BOOKS=/dev/null FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO13a /dev/null is refused (it would swallow every write)" "1" "$RC"
assert_eq "AO13a with zero PATCH" "0" "$(patch_count)"
new_case ao13b
: > "$CASE/real"; ln -s "$CASE/real" "$CASE/link"
ARMONE_BOOKS="$CASE/link" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO13b a symlinked books path is refused" "1" "$RC"
assert_eq "AO13b with zero PATCH" "0" "$(patch_count)"
new_case ao13c
mkdir "$CASE/adir"
ARMONE_BOOKS="$CASE/adir" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO13c a directory is refused" "1" "$RC"
assert_eq "AO13c with zero PATCH" "0" "$(patch_count)"
new_case ao13e
ARMONE_BOOKS="$CASE/odd"$'\n'"::notice::arm-one-result name=x id=1 outcome=armed rc=0" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO13e a books path with an embedded newline cannot forge a second verdict line" "1" "$(printf '%s\n' "$OUT" | grep -c '^::notice::arm-one-result')"

echo "--- AO14 already up: a stale own line is stripped, other ids are kept"
new_case ao14
printf 'up' > "$FAKE_STATE/$ID_HOST.status"
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" up)"
printf '777\n%s\n' "$ID_HOST" > "$CASE/mine"
ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO14 exits 0" "0" "$RC"
assert_eq "AO14 the stale line for THIS (up) monitor is gone and the unrelated id is kept" "777" "$(cat "$CASE/mine")"
assert "AO14 the verdict is already-up" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=already-up rc=0' ]]"

echo "--- AO15 the list and the live read can disagree: the LIVE status decides"
new_case ao15a
printf 'up' > "$FAKE_STATE/$ID_HOST.status"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO15a list says paused, live says up: nothing is unpaused" "0" "$(patch_count)"
assert "AO15a and it is reported already-up" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'outcome=already-up rc=0' ]]"
new_case ao15b
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" up)"
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO15b list says up, live says paused: the live read governs and it arms" "0" "$RC"
assert_eq "AO15b via exactly one unpause PATCH" "1" "$(patch_count)"

echo "--- AO6h the reserve in the ceiling is the live ARM_POLL_INTERVAL_S, not a literal 40"
new_case ao6h
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 130)"
NEW_POLL=11 FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO6h poll 11 makes the ceiling 149 < 150: refused" "1" "$RC"
assert_eq "AO6h with zero PATCH" "0" "$(patch_count)"
assert "AO6h and the refusal quotes the computed ceiling" "[[ \"\$OUT\" == *'ceiling of 149s'* ]]"

echo "--- AO16 numeric hygiene: oversized or newline-tailed digit strings are INVALID, never arithmetic"
new_case ao16a
printf '{"data":[{"id":"%s","attributes":{"name":"%s","status":"paused","paused":true,"period":"100000000000000000000000","grace":300}}],"pagination":{"next":null}}' "$ID_HOST" "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "AO16a a 24-digit period is refused" "1" "$RC"
assert_eq "AO16a with zero PATCH" "0" "$(patch_count)"
new_case ao16b
printf '{"data":[{"id":"%s\\n","attributes":{"name":"%s","status":"paused","paused":true,"period":60,"grace":300}}],"pagination":{"next":null}}' "$ID_HOST" "$HOST_NAME" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "AO16b an id with a trailing newline is refused (jq's \$ would have matched it)" "1" "$RC"
assert "AO16b and names the non-numeric id" "[[ \"\$OUT\" == *'non-numeric id'* ]]"

echo "--- ST6 pagination shapes that are a partial read, never the end of the list"
new_case st6a
write_page 1 "$LIST_BASE?" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST6a a next of '.../heartbeats?' (empty query) exits 1" "1" "$RC"
new_case st6b
printf '{"data":[%s],"pagination":{"next":false}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
run_named --status "$HOST_NAME"
assert_eq "ST6b next:false exits 1" "1" "$RC"
new_case st6c
write_page 1 "$LIST_BASE?page=" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST6c a next of 'page=' with no number exits 1" "1" "$RC"
assert_eq "ST6c and is never requested" "1" "$(list_count)"
new_case st6d
write_page 1 "/api/v2/heartbeats?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
run_named --status "$HOST_NAME"
assert_eq "ST6d a RELATIVE next exits 1" "1" "$RC"
assert_eq "ST6d and is never requested" "1" "$(list_count)"
new_case st6e
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
printf '{"data":["not-an-object"],"pagination":{"next":null}}' > "$FAKE_LIST_DIR/page-2.json"
run_named --status "$HOST_NAME"
assert_eq "ST6e a rows-parse failure on page 2 exits 1" "1" "$RC"
assert "ST6e and names page 2" "[[ \"\$OUT\" == *'could not parse page 2'* ]]"
new_case st6f
write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
printf '{"data":[%s],"pagination":"oops"}' "$(hb_row "$ID_DECOY" "decoy-two" up)" > "$FAKE_LIST_DIR/page-2.json"
run_named --status "$HOST_NAME"
assert_eq "ST6f a malformed .pagination on page 2 exits 1" "1" "$RC"
assert "ST6f and names page 2" "[[ \"\$OUT\" == *'page 2 of the heartbeat list carries a malformed .pagination'* ]]"

echo "--- AO17 the verdict claims an id only for exactly one match, and exists for a token refusal"
new_case ao17a
write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
run_named --arm-one "$HOST_NAME"
assert "AO17a a collision's verdict carries id=none" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *' id=none outcome=refused rc=1' ]]"
new_case ao17b
NEW_TOKEN='' run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert "AO17b a token refusal still ends in a verdict line" "[[ \"\$(printf '%s\\n' \"\$OUT\" | tail -n 1)\" == *'id=none outcome=refused rc=1' ]]"
assert_eq "AO17b and made no request" "0" "$(call_count)"

echo "--- AO18 the printed recovery command survives an exported CDPATH"
new_case ao18
printf '%s true\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
mkdir -p "$CASE/decoy/apps/web-platform/infra"
OUT="$(cd "$SCRIPT_DIR/../../.." && PATH="$BIN:$PATH" BS_TOKEN=fake-token CDPATH="$CASE/decoy:." TMPDIR="$CASE" ARM_POLL_INTERVAL_S=10 \
      env -u TFSTATE_JSON -u ARMED_UNCONFIRMED FAKE_CURL_COST=1 bash apps/web-platform/infra/arm-heartbeats.sh --arm-one "$HOST_NAME" --id "$ID_HOST" 2>&1)"
RC=$?
assert_eq "AO18 the run still reports the failed rollback" "1" "$RC"
assert "AO18 the recovery command names the REAL script's absolute path, not a CDPATH decoy" "[[ \"\$OUT\" == *\"bash $SUT --sweep\"* ]]"

echo "--- AO19 --sweep does not depend on the arm-one poll interval"
new_case ao19
: > "$CASE/books"
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token ARM_POLL_INTERVAL_S=0 ARMED_UNCONFIRMED="$CASE/books" bash "$SUT" --sweep 2>&1)"; RC=$?
assert_eq "AO19 --sweep with ARM_POLL_INTERVAL_S=0 exits 0" "0" "$RC"
assert "AO19 and reports outcome=noop" "[[ \"\$OUT\" == *'outcome=noop'* ]]"

echo "--- AO20 an interval that is arithmetic never executes"
new_case ao20
OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token ARM_POLL_INTERVAL_S='RES_ID[$(touch "'"$CASE"'/pwned")]' TMPDIR="$CASE" bash "$SUT" --arm-one "$HOST_NAME" --id "$ID_HOST" 2>&1)"; RC=$?
assert_eq "AO20 exits 1" "1" "$RC"
assert "AO20 and nothing was executed" "[[ ! -e '$CASE/pwned' ]]"

# --- Mutation battery -------------------------------------------------------------------------
# Each row mutates a COPY of the SUT and requires a verdict this suite asserts to CHANGE. A guard
# that cannot be driven RED is vacuous; and a mutation that does not LAND reports the baseline,
# which is indistinguishable from a pass — so every row asserts the edit applied, and asserts HOW
# MANY lines it applied to (#7656 C9: `s|^    return 1$|    return 2|` silently landed in three
# regions, and `cmp -s` reports only THAT the file differs, never where or how widely).
echo "--- M mutation battery (each row must change a verdict this suite asserts)"
MUTANT=""
mutate() {  # <name> <expected-changed-lines> <sed-expr> -> 0 and sets MUTANT, or 1
  # Separate `local` statements deliberately: `local a=$1 b=$WORK/$a` expands EVERY argument
  # before the builtin runs, so `$a` is unbound there and `set -u` kills the function.
  local name="$1"
  local want="$2"
  local expr="$3"
  local mutant="$WORK/mutant-$name.sh"
  local changed
  cp "$SUT" "$mutant" || { echo "FATAL: mutation copy failed for $name"; exit 2; }
  sed -i "$expr" "$mutant" || { echo "FATAL: sed failed for $name"; exit 2; }
  changed=$(diff <(cat "$SUT") <(cat "$mutant") | grep -c '^<' || true)
  if [[ "$changed" -eq 0 ]]; then
    fail "M-$name mutation LANDED" "sed [$expr] changed nothing — the row would test the baseline"
    return 1
  fi
  if [[ "$changed" -ne "$want" ]]; then
    fail "M-$name mutation landed on exactly $want line(s)" \
      "sed [$expr] changed $changed lines — the row does not mutate what its title says"
    return 1
  fi
  pass "M-$name mutation landed on exactly $want line(s) of a pristine copy"
  MUTANT="$mutant"
}

# M1 — revert the wall-clock accounting to the pre-#7587 sleep tally (Guard 2 row 6).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate wallclock 1 's|elapsed=\$(( \$(now_s) - started ))|elapsed=$(( elapsed + ARM_POLL_INTERVAL_S ))|g'; then
  case_setup m1
  printf 'paused' > "$FAKE_STATE/$ID_ZOT1.status"
  FAKE_CURL_COST=15 run_sut "$MUTANT"
  m1_reported="$(reported_elapsed 200)"
  assert "M1 RED: the sleep-tally blows T3's 420s observed-clock bound (measured $(observed_clock)s)" \
    "[[ \$(observed_clock) -gt 420 ]]"
  # `-n` first: `[[ "" -le 225 ]]` is TRUE — `[[ ]]` coerces an empty string to 0 — so without a
  # positive control this row passes vacuously the moment the message changes shape (#7656 C9).
  assert "M1 positive control: the mutant still PRINTS an elapsed to compare against" \
    "[[ -n '$m1_reported' ]]"
  assert "M1 and it does so while REPORTING a compliant elapsed (${m1_reported:-none}s) — which is why T3 asserts the clock" \
    "[[ '${m1_reported:-99999}' -le 225 ]]"
fi

# M2 — flip the rollback to paused:false (Guard 2 row 7 at the script layer).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate unpause-rollback 1 's|hb_patch_paused "\$id" true && return 0|hb_patch_paused "$id" false \&\& return 0|'; then
  case_setup m2
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  run_sut "$MUTANT"
  assert "M2 RED: the terminal PATCH is no longer paused:true" \
    "[[ \"\$(patch_bodies | tail -1)\" != '$ID_INNGEST {\"paused\":true}' ]]"
fi

# M3 — stop recording the id at the unpause, which is what a "remove on attempt" design amounts to.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-state-add 1 's|^  if \[\[ -z "\$given_id" \]\]; then state_add "\$id"; fi$|  : "state_add removed by mutation"|'; then
  case_setup m3
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert "M3 RED: a failed rollback no longer leaves the id on the sweep's books (T5 would be vacuous)" \
    "[[ \$(state_lines) -eq 0 ]]"
fi

# M4 — soft-land a FAILED rollback back to rc=2, the pre-#7587 behaviour. ANCHORED to the rollback
# branch: the old `s|^    return 1$|    return 2|` landed in three regions at once.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate soft-failed-rollback 1 '/rollback PATCH paused=true FAILED/,/^    return 1$/ s|^    return 1$|    return 2|'; then
  case_setup m4
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL"
  run_sut "$MUTANT"
  assert_eq "M4 RED: the apply job goes GREEN while a monitor is live-and-unfed" "0" "$RC"
  assert "M4 positive control: the mutant really did take the failed-rollback branch" \
    "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
fi

# M5 — restore the 230s inngest deadline.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate deadline-230 1 's|^ARM_INNGEST_DEADLINE=30$|ARM_INNGEST_DEADLINE=230|'; then
  case_setup m5
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert "M5 RED: the inngest arm advertises its old 230s budget again" \
    "[[ \"\$OUT\" == *'no beat within 230s'* ]]"
  assert "M5 and burns it: the observed clock passes 230s" "[[ \$(observed_clock) -ge 230 ]]"
fi

# M6 — strip the Authorization header from the stdin config the bearer travels on. Ignored by the old
# stub, so deletable with both suites green.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-auth-header 1 's|header = "Authorization: Bearer %s"|header = "X-Stripped: %s"|'; then
  case_setup m6
  run_sut "$MUTANT"
  assert_eq "M6 RED: an unauthenticated gate cannot verify a single arm" "1" "$RC"
  assert "M6 and it says the lookup failed rather than reporting a status" \
    "[[ \"\$OUT\" == *'failed — cannot verify arm state'* ]]"
fi

# M7 — strip the per-round-trip ceiling. The whole ladder is priced on `--max-time`.
# The landing count is 3 since #9980: the list resolver's read carries the same literal as the two
# pre-existing round-trips (hb_fetch, hb_patch_paused). A deliberate edit, not a loosening.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-max-time 3 's|--max-time "\$ARM_CURL_MAX_TIME_S" ||g'; then
  case_setup m7
  run_sut "$MUTANT"
  assert_eq "M7 RED: an unbounded round-trip is a term the wall-clock ladder cannot price" "1" "$RC"
fi

# M8 — narrow the op/state gate to `== "up"`, so a `down` or `pending` monitor is unpaused and
# polled to its deadline on every apply.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate gate-up-only 1 's|^  if \[\[ "\$HB_STATUS" != "paused" \]\]; then|  if [[ "$HB_STATUS" == "up" ]]; then|'; then
  case_setup m8
  printf 'down' > "$FAKE_STATE/$ID_ZOT1.status"
  FAKE_CURL_COST=0 run_sut "$MUTANT"
  assert "M8 RED: a DOWN monitor is now unpaused rather than skipped" \
    "[[ \"\$(patch_bodies | sed -n '1p')\" == '$ID_ZOT1 {\"paused\":false}' ]]"
  assert "M8 and it is polled to its deadline: the clock passes 200s" "[[ \$(observed_clock) -ge 200 ]]"
fi

# M10 — remove hb_fetch's empty-status guard: a 200 whose JSON has no status would arm on "".
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-status-guard 1 's@^  \[\[ -n "\$HB_STATUS" \]\] || return 1$@  :@'; then
  case_setup m10
  printf '%s\n' "$ID_ZOT1" > "$FAKE_BAD_JSON"
  FAKE_CURL_COST=0 run_sut "$MUTANT"
  assert "M10 RED: an empty status is no longer a failed lookup" \
    "[[ \"\$OUT\" != *'GET /heartbeats/$ID_ZOT1 failed'* ]]"
fi

# M11 — lower the documented poll-interval default to 1: a 6x production API-call rate, invisible
# while every case exported the value.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate poll-default-1 1 's|ARM_POLL_INTERVAL_S="\${ARM_POLL_INTERVAL_S:-10}"|ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-1}"|'; then
  case_setup m11
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CURL_COST=0 run_sut_defaults "$MUTANT"
  assert "M11 RED: the default interval is no longer 10s — T10's 9 GETs become one per second" \
    "[[ \$(get_urls | grep -c '') -gt 12 ]]"
fi

# M12 — delete the sweep's fail-not-annotate branch. This is the mutation that survived the
# regex guard: `expect(body).toMatch(/^\s*exit 1\s*$/m)` was satisfied by an unrelated `exit 1`
# in the mint-unreadable branch, so the sweep could annotate-and-exit-0 with 159/0 green.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-annotate-only 1 '/Re-pause sweep could not re-pause/{n; s|^    return 1$|    return 0|}'; then
  case_setup m12
  printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
  printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
  run_sweep "$MUTANT"
  assert_eq "M12 RED: the sweep now exits 0 with a monitor still live-and-unfed" "0" "$RC"
  assert "M12 positive control: it really did fail to re-pause one" \
    "[[ \"\$OUT\" == *'returned HTTP 500'* ]]"
fi

# M13 — make the sweep's arithmetic lie: count a failure as a success.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-count-lie 1 's|^      failed=\$(( failed + 1 ))$|      repaused=$(( repaused + 1 ))|'; then
  case_setup m13
  printf '%s\n%s\n' "$ID_ZOT1" "$ID_NIC1" > "$STATEFILE"
  printf '500' > "$FAKE_HTTP/$ID_NIC1.patch-true"
  run_sweep "$MUTANT"
  assert "M13 RED: the sweep reports a clean outcome while a monitor is still live" \
    "[[ \"\$OUT\" == *'armed=2 repaused=2 failed=0'* ]]"
fi

# M14 — drop the ids from the mint-unreadable message, leaving only the count.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-no-ids 1 's|and this step cannot re-pause them: \${ids}\.|and this step cannot re-pause them.|'; then
  case_setup m14
  printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
  SWEEP_TOKEN="" run_sweep "$MUTANT"
  assert "M14 RED: the operator is told a count with no id to act on" \
    "[[ \"\$OUT\" != *\"cannot re-pause them: $ID_ZOT1\"* ]]"
fi

# M16 — flip the SWEEP's PATCH to paused:false, i.e. a backstop that unpauses what it was built
# to re-pause. Anchored separately from M2 because the two call sites are different branches.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate sweep-unpause 1 's|^    if hb_patch_paused "\$id" true; then$|    if hb_patch_paused "$id" false; then|'; then
  case_setup m16
  printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
  run_sweep "$MUTANT"
  assert "M16 RED: the sweep now UNPAUSES the monitor it exists to re-pause" \
    "[[ \"\$(patch_bodies | tail -1)\" == '$ID_ZOT1 {\"paused\":false}' ]]"
fi

# M17 — drop the rollback retry, i.e. Deviation 3 as it first shipped: one unretried round-trip
# reds a routine apply and raises a false ops alarm.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-rollback-retry 1 's|^ARM_ROLLBACK_ATTEMPTS=2$|ARM_ROLLBACK_ATTEMPTS=1|'; then
  case_setup m17
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  printf '%s true 500\n' "$ID_INNGEST" > "$FAKE_PATCH_FAIL_ONCE"
  FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert_eq "M17 RED: a single lost round-trip now reds the apply" "1" "$RC"
  assert "M17 and it calls the monitor unpaused-and-unfed on a transient" \
    "[[ \"\$OUT\" == *'unpaused-and-unfed'* ]]"
fi

# M18 — move `state_add` from the instant the monitor goes LIVE to the instant the gate gives up.
# This is the row T11 exists to make possible. Before T11 the edit was invisible: every case that
# reads the state file reads it after `arm_one` has RETURNED, and by then the late `state_add` has
# already run — so all 190 assertions stayed green while the whole poll window, which is precisely
# the window the `always()` sweep exists to cover, silently stopped being recorded.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
# `mutate`'s line count is DELETIONS only, and this edit is one delete plus one pure insertion, so
# the count it can see is 1. That is too weak on its own: if the insertion half silently stopped
# matching (a reflow of the rollback line), the count would still read 1 and this row would be
# running M3's mutation — no `state_add` anywhere — and passing for the wrong reason. So the
# re-insertion is asserted directly.
if mutate late-state-add 1 '/^  if \[\[ -z "\$given_id" \]\]; then state_add "\$id"; fi$/d; s|^  if ! hb_rollback "\$id" "\$label"; then$|  state_add "$id"\n&|'; then
  assert "M18 the mutation MOVED state_add rather than deleting it (that is M3's row)" \
    "grep -q '^  state_add \"\$id\"$' '$MUTANT'"
  case_setup m18
  printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
  FAKE_CUT_AFTER=2 FAKE_CURL_COST=1 run_sut "$MUTANT"
  assert_eq "M18 RED: a cut mid-poll leaves the monitor LIVE and OFF the sweep's books" "0" "$(state_lines)"
fi

# M19 — drop `--disable` (curl would then read the ambient ~/.curlrc with the bearer in scope).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-disable 1 "s|curl --disable --noproxy '\\*' |curl --noproxy '*' |"; then
  case_setup m19
  run_sut "$MUTANT"
  assert_eq "M19 RED: a call whose first argument is not --disable cannot verify a single arm" "1" "$RC"
fi

# M20 — drop `--noproxy '*'` (an inherited ALL_PROXY/HTTPS_PROXY would carry the bearer elsewhere).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-noproxy 1 "s|curl --disable --noproxy '\\*' |curl --disable |"; then
  case_setup m20
  run_sut "$MUTANT"
  assert_eq "M20 RED: a call with no --noproxy '*' cannot verify a single arm" "1" "$RC"
fi

# M21 — delete the BS_API_BASE pin: an env override then redirects the bearer. The positive control
# is that the unmutated copy (M15) never reaches this destination.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-destination-pin 1 's|^  https://uptime.betterstack.com/api/v2) ;;$|  *) ;;|'; then
  case_setup m21
  OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token TFSTATE_JSON="$TFSTATE" ARMED_UNCONFIRMED="$STATEFILE" \
        BS_API_BASE="https://evil.example/api/v2" bash "$MUTANT" --arm 2>&1)"; RC=$?
  assert "M21 RED: without the pin the bearer is sent to the overridden destination" \
    "[[ \$(get_urls | grep -c '') -gt 0 ]]"
fi

# --- M22-M33 (#9980): the named-monitor modes ---------------------------------------------------
# Each row mutates ONE guard of --status/--arm-one on a copy and requires a verdict a case above asserts
# to CHANGE. `NEW_SUT` points run_named at the mutant. Every mutant arm is judged by a PATCH the baseline
# must not issue (or, for M27/M29, a refusal the baseline must not make), so none can pass on the
# baseline's own behaviour.

# M22 — exact name equality becomes substring containment: a near-name arms the wrong monitor.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate name-contains 1 's@select(\.attributes\.name == \$n)@select(.attributes.name | contains($n))@'; then
  new_case m22
  printf 'paused' > "$FAKE_STATE/$ID_DECOY.status"
  write_page 1 "" "$(hb_row "$ID_DECOY" "${HOST_NAME}-old" paused)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME"
  assert "M22 RED: the mutant unpauses a monitor whose name merely CONTAINS the requested one" \
    "[[ \$(patch_count) -ge 1 ]]"
fi

# M23 — the collision refusal is disabled: two exact rows arm the last one read.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate collision-allowed 1 's@^  if \[\[ "\$RES_COUNT" -gt 1 \]\]; then@  if false; then@'; then
  new_case m23
  printf 'paused' > "$FAKE_STATE/$ID_DUP.status"
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME"
  assert "M23 RED: with two monitors of that name the mutant arms one of them" "[[ \$(patch_count) -ge 1 ]]"
fi

# M24 — stop reading after page 1: a duplicate on a later page is never seen.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate first-page-only 1 's@^    next="\${next//.*$@    next=""@'; then
  new_case m24
  write_page 1 "$LIST_BASE?page=2&per_page=250" "$(hb_row "$ID_HOST" "$HOST_NAME" paused)"
  write_page 2 "" "$(hb_row "$ID_DUP" "$HOST_NAME" paused)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME"
  assert "M24 RED: a compliant first match plus a duplicate on page 2 is armed by the mutant" \
    "[[ \$(patch_count) -ge 1 ]]"
fi

# M25 — drop the id-pin equality: the pin no longer anchors anything.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate pin-ignored 1 's@^  if \[\[ "\$HAVE_ID" -eq 1 && "\$PIN_ID" != "\$RES_ID" \]\]; then@  if false; then@'; then
  new_case m25
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_OTHER"
  assert "M25 RED: a pin that differs from the resolved id still arms" "[[ \$(patch_count) -ge 1 ]]"
fi

# M26 — delete the ceiling comparison: a short-window monitor is unpaused for 150 s.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-ceiling 1 's@^  if \[\[ "\$ARM_ONE_DEADLINE" -gt "\$max" \]\]; then@  if false; then@'; then
  new_case m26
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 100)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M26 RED: a monitor whose first alert lands inside the window is unpaused" "[[ \$(patch_count) -ge 1 ]]"
fi

# M27 — off-by-one on the ceiling: `-gt` becomes `-ge`, so a monitor the contract ALLOWS (ceiling == 150)
# is refused. The suite pins both sides of the boundary (grace 130 allowed, 129 refused).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate ceiling-off-by-one 1 's@^  if \[\[ "\$ARM_ONE_DEADLINE" -gt "\$max" \]\]; then@  if [[ "$ARM_ONE_DEADLINE" -ge "$max" ]]; then@'; then
  new_case m27
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 60 130)"
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert_eq "M27 RED: the monitor sitting exactly on the ceiling is now refused" "1" "$RC"
fi

# M28 — disable the id override: arm_one falls back to the tfstate lookup that --arm-one never has.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate override-off 1 's@^  if \[\[ -n "\$given_id" \]\]; then@  if false; then@'; then
  new_case m28
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert_eq "M28 RED: the resolved id never reaches arm_one, so nothing is unpaused" "0" "$(patch_count)"
fi

# M29 — hoist the --arm preflight out of its gate: --arm-one then demands a tfstate it never had.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate preflight-ungated 1 's@^if \[\[ "\$MODE" == arm \]\]; then@if true; then@'; then
  new_case m29
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert_eq "M29 RED: the named-monitor mode is refused for want of a tfstate" "1" "$RC"
  assert "M29 and says so" "[[ \"\$OUT\" == *'TFSTATE_JSON is unset'* ]]"
fi

# M30 — drop the query pin: a vendor `pagination.next` that is NOT a bare page/per_page query is then followed.
# The destination is always the pinned base plus that query, so the bearer never leaves the vendor's host;
# what the pin buys is that nothing but a page number reaches a request. The mutant makes a second list call.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate query-unpinned 1 's@^    if \[\[ ! "\$query" =~ .*$@    if false; then@'; then
  new_case m30
  write_page 1 "https://evil.example/api/v2/heartbeats?page=2&per_page=250" "$(hb_row "$ID_DECOY" "decoy-one" up)"
  NEW_SUT="$MUTANT" run_named --status "$HOST_NAME"
  assert "M30 RED: the mutant makes a request for a next URL the baseline refuses ($(list_count) list calls)" \
    "[[ \$(list_count) -gt 1 ]]"
fi

# M31 — drop the `.data is an array` check. A 200 whose `.data` is an OBJECT iterates its values in
# `.data[]`, so without the check an error-shaped body can read as a unique match.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-data-array-check 1 's@^    if ! printf .%s. "\$body" | jq -e .*$@    if false; then@'; then
  new_case m31
  printf '{"data":{"k":%s},"pagination":{"next":null}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M31 RED: a list whose .data is an object is armed from by the mutant" "[[ \$(patch_count) -ge 1 ]]"
fi

# M32 — drop the positive-integer check on period/grace. period 0 passes the arithmetic (0 + 300 - 40 >= 150),
# so only the check stops it; a NULL period would abort in the arithmetic under set -u and prove nothing.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-int-check 1 's@^  if \[\[ ! "\$RES_PERIOD" =~ .*$@  if false; then@'; then
  new_case m32
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" paused 0 300)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M32 RED: a monitor with period 0 is unpaused by the mutant" "[[ \$(patch_count) -ge 1 ]]"
fi

# M33 — let the override fall back to the ENVIRONMENT: an exported variable then steers --arm's ids.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate override-from-env 1 's@given_id="\${4:-}"@given_id="${4:-${ARM_ONE_ID:-}}"@'; then
  case_setup m33
  ARM_ONE_ID=1 run_sut "$MUTANT"
  assert "M33 RED: --arm reads monitor id 1 because the environment said so" "grep -qx 1 < <(get_urls)"
fi

# --- M35-M42 (#9980 review round) ------------------------------------------------------------------
# M35 — the id pin is read from the parser's HAVE_ID flag: an EMPTY --id must not silently drop it. The parser
# check and the pin comparison are belt and braces (either alone still refuses), so the row removes BOTH.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate pin-by-emptiness 2 's@^  \[\[ "\$HAVE_ID" -eq 0 || .*$@  :@; s@^  if \[\[ "\$HAVE_ID" -eq 1 && @  if [[ -n "$PIN_ID" \&\& @'; then
  new_case m35
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id ""
  assert "M35 RED: with --id '' the mutant arms although the owner asked for a pin" "[[ \$(patch_count) -ge 1 ]]"
fi

# M36 — drop the ARM_POLL_INTERVAL_S validation: the variable reaches a $(( )) and a negative value loosens the ceiling.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-poll-validation 1 's@^\[\[ "\$MODE" == sweep || "\$ARM_POLL_INTERVAL_S" =~ .*$@:@'; then
  new_case m36
  NEW_SUT="$MUTANT" NEW_POLL=abc run_named --status "$HOST_NAME"
  assert "M36 RED: the mutant no longer names the invalid interval" "[[ \"\$OUT\" != *'ARM_POLL_INTERVAL_S must be'* ]]"
  OUT="$(PATH="$BIN:$PATH" BS_TOKEN=fake-token ARM_POLL_INTERVAL_S='RES_ID[$(touch "'"$CASE"'/pwned")]' TMPDIR="$CASE" timeout 60 bash "$MUTANT" --arm-one "$HOST_NAME" --id "$ID_HOST" 2>&1)"
  assert "M36 RED: the mutant EXECUTES the arithmetic payload (the real SUT refuses first, AO20)" "[[ -e '$CASE/pwned' ]]"
fi

# M37/M38 — a mode that is never dispatched checks nothing: delete either dispatch exit and the run falls into the
# six per-merge arms (here with a tfstate exported, as an operator's shell might have).
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate status-falls-through 1 's@^if \[\[ "\$MODE" == status \]\]; then status_main; exit \$?; fi@if [[ "$MODE" == status ]]; then status_main; fi@'; then
  new_case m37
  NEW_SUT="$MUTANT" NEW_TFSTATE=1 run_named --status "$HOST_NAME"
  assert "M37 RED: --status then reads the six per-merge monitors" "grep -qx '$ID_ZOT1' < <(get_urls)"
fi
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate armone-falls-through 1 's@^if \[\[ "\$MODE" == armone \]\]; then armone_main; exit \$?; fi@if [[ "$MODE" == armone ]]; then armone_main; fi@'; then
  new_case m38
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" NEW_TFSTATE=1 FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M38 RED: --arm-one then walks the six per-merge monitors too" "grep -qx '$ID_ZOT1' < <(get_urls)"
fi

# M39 — a malformed .pagination reads as "no next page": a duplicate on the unread pages is never seen.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate pagination-tolerant 1 's@else error("malformed pagination") end@else "" end@'; then
  new_case m39
  printf '{"data":[%s],"pagination":"oops"}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
  NEW_SUT="$MUTANT" run_named --status "$HOST_NAME"
  assert_eq "M39 RED: the mutant resolves from a partial list (exit 0)" "0" "$RC"
fi

# M40 — drop the read-back after an unpause that answers an error: a monitor whose reply was lost stays live.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-unpause-recovery 1 's@^  elif \[\[ "\$ARM_RESULT" == unpause-failed \]\]; then@  elif false; then@'; then
  new_case m40
  printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M40 RED: the monitor that went live is left live (the real SUT rolls it back, AO10)" \
    "[[ \"\$(cat '$FAKE_STATE/$ID_HOST.status')\" != paused ]]"
fi

# M41 — rc 0 for a live monitor that is not `up`: the runbook reads rc 0 as "the soak is satisfied".
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate noop-any-status 1 's@^    if \[\[ "\$HB_STATUS" == "up" \]\]; then@    if true; then@'; then
  new_case m41
  printf 'pending' > "$FAKE_STATE/$ID_HOST.status"
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" pending)"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert_eq "M41 RED: a PENDING monitor is reported as already up (exit 0)" "0" "$RC"
fi

# M42 — judge the books file by being non-empty rather than by this run's own id: an unrelated line is blamed on this run.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate books-by-size 1 's@^  \[\[ \$? -eq 1 \]\] || on_books=1$@  [[ -s "$ARMED_UNCONFIRMED" ]] \&\& on_books=1@'; then
  new_case m42
  printf '%s\n' 777 > "$CASE/mine"
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M42 RED: the mutant blames this run for the caller's unrelated line" "[[ \"\$OUT\" == *'still lists'* ]]"
fi

# M43 — record the id only AFTER the unpause request (the pre-#9980 order): at the instant the PATCH arrives the books are
# empty, and a lost reply whose read-back also fails leaves a live monitor off the books.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate record-after-act 2 's@^  if \[\[ -n "\$given_id" \]\] \&\& ! state_add "\$id" pre-unpause; then$@  if false; then@
s@^  if \[\[ -z "\$given_id" \]\]; then state_add "\$id"; fi$@  state_add "$id"@'; then
  new_case m43
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  FAKE_SNAP_BOOKS="$CASE/mine" ARMONE_BOOKS="$CASE/mine" NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M43 RED: the books were EMPTY when the unpause PATCH arrived (the real SUT already holds the id, AO21)" "! grep -qxF '$ID_HOST' '$FAKE_CALLS.booksnap'"
  new_case m43b
  printf '%s false\n' "$ID_HOST" > "$FAKE_PATCH_LOST"
  printf '%s 1\n' "$ID_HOST" > "$FAKE_GET_FAIL_AFTER"
  NEW_SUT="$MUTANT" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert_eq "M43 RED: the live, unreadable monitor is on NO books (the real SUT keeps its id, AO10b)" "0" "$(books_count)"
fi

# M44 — accept any books path that `: >>` can open: /dev/null, a symlink, a FIFO all pass and swallow the record.
# The sibling-scratch probe and the pre-unpause read-back would each refuse /dev/null on their own, so the mutant removes all three.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate books-any-path 3 's@^  elif \[\[ -L "\$ARMED_UNCONFIRMED" \]\].*$@  elif false \\@
s@^       || ! { probe=.*$@       || false; then@
s@^  if \[\[ "\${2:-}" == pre-unpause \]\] \&\& ! grep -qxF -- "\$1".*$@  if false; then@'; then
  new_case m44
  NEW_SUT="$MUTANT" ARMONE_BOOKS=/dev/null FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M44 RED: /dev/null is accepted and the monitor is unpaused" "[[ \$(patch_count) -ge 1 ]]"
fi

# M54 — trust the pre-unpause append instead of reading the id back: a books file swapped for /dev/null after the preflight swallows it.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate no-readback 1 's@^  if \[\[ "\${2:-}" == pre-unpause \]\] \&\& ! grep -qxF -- "\$1".*$@  if false; then@'; then
  new_case m54
  mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
  FAKE_HOOK_GET="rm -f '$CASE/bk/books'; ln -s /dev/null '$CASE/bk/books'" NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M54 RED: the monitor is unpaused although its id went into /dev/null (the real SUT refuses, AO34)" "[[ \$(patch_count) -ge 1 ]]"
fi

# M45 — leave a stale line for an UP monitor on the books: a later --sweep would re-pause a fed monitor.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate keep-stale-line 1 's@^        state_remove "\$RES_ID" && echo "::notice::arm-heartbeats.sh: removed the stale line.*$@        :@'; then
  new_case m45
  printf 'up' > "$FAKE_STATE/$ID_HOST.status"
  write_page 1 "" "$(hb_row "$ID_HOST" "$HOST_NAME" up)"
  printf '777\n%s\n' "$ID_HOST" > "$CASE/mine"
  NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M45 RED: the up monitor's id is still on the books" "grep -qxF '$ID_HOST' '$CASE/mine'"
fi

# M46 — drop the CDPATH guard on the printed recovery command's `cd`.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate cdpath-unguarded 1 "s@CDPATH='' cd --@cd --@"; then
  new_case m46
  printf '%s true\n' "$ID_HOST" > "$FAKE_PATCH_FAIL"
  mkdir -p "$WORK/m46/sub/dir" "$WORK/m46-decoy/sub/dir" || { echo "FATAL: M46 mkdir failed"; exit 2; }
  cp "$MUTANT" "$WORK/m46/sub/dir/x.sh" || { echo "FATAL: M46 copy failed"; exit 2; }
  # shellcheck disable=SC2034  # read by the assert string below
  m46_out="$(cd "$WORK/m46" && PATH="$BIN:$PATH" BS_TOKEN=fake-token CDPATH="$WORK/m46-decoy:." TMPDIR="$CASE" \
        env -u TFSTATE_JSON -u ARMED_UNCONFIRMED FAKE_CURL_COST=1 bash sub/dir/x.sh --arm-one "$HOST_NAME" --id "$ID_HOST" 2>&1)"
  assert "M46 RED: the mutant resolves the script through CDPATH to the decoy directory" "[[ \"\$m46_out\" != *\"bash $WORK/m46/sub/dir/x.sh --sweep\"* ]]"
fi

# M47 — ignore a failed pre-unpause record: the monitor is unpaused although its id could not be written anywhere.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate ignore-failed-record 1 's@\&\& ! state_add "\$id" pre-unpause; then$@\&\& ! { state_add "$id" pre-unpause; :; }; then@'; then
  new_case m47
  mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
  FAKE_HOOK_GET="chmod 444 '$CASE/bk/books'" NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  perm_restore
  perm_assert "M47 RED: the mutant unpauses a monitor that has nowhere to be recorded" "[[ \$(patch_count) -ge 1 ]]"
fi

# M48 — append without a leading newline: a hand-edited books file with no final newline gets its last line GLUED to the id.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate glued-append 1 's@-n "\$(tail -c1@-z "$(tail -c1@'; then
  new_case m48
  printf '99' > "$CASE/mine"
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M48 RED: the id was glued onto the unterminated last line (99$ID_HOST)" "grep -qxF '99$ID_HOST' '$CASE/mine'"
fi

# M49 — let the residual-books check change the outcome: a successful arm is re-labelled a failure because cleanup could not run.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate residual-changes-outcome 1 's@^        left=paused$@        left=paused; ARM_ONE_OUTCOME=rollback-failed@'; then
  new_case m49
  mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  FAKE_HOOK_PATCH_FALSE="chmod 555 '$CASE/bk'" NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  perm_restore
  perm_assert "M49 RED: the armed run is re-labelled by the leftover line" "[[ \"\$(last_verdict)\" == *'outcome=rollback-failed'* ]]"
fi

# M50 — an unreadable books file (grep rc 2) read as "not listed".
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate unreadable-is-unlisted 1 's@^  \[\[ \$? -eq 1 \]\] || on_books=1$@  [[ $? -ge 1 ]] || on_books=1@'; then
  new_case m50
  mkdir -p "$CASE/bk"; : > "$CASE/bk/books"
  echo 30 > "$FAKE_STATE/$ID_HOST.upat"
  FAKE_HOOK_PATCH_FALSE="chmod 000 '$CASE/bk/books'" NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/bk/books" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  perm_restore
  perm_assert "M50 RED: the unreadable books file is not reported as listing the id" "[[ \"\$OUT\" != *'still lists'* ]]"
fi

# M51 — the `failed` outcome asserts "left paused" for a monitor this run never read.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate failed-claims-paused 1 's@^      armed|already-up|rolled-back|unpause-recovered)$@      armed|already-up|rolled-back|unpause-recovered|failed)@'; then
  new_case m51
  printf '%s\n' "$ID_HOST" > "$CASE/mine"
  printf '%s\n' "$ID_HOST" > "$FAKE_GET_FAIL"
  NEW_SUT="$MUTANT" ARMONE_BOOKS="$CASE/mine" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  assert "M51 RED: the warning claims the unread monitor was left paused" "[[ \"\$OUT\" == *'left paused'* ]]"
fi

# M52 — show() in the operator's UTF-8 locale: U+202E (bidi override) is "printable" there.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate show-locale 1 's@^show() { local LC_ALL=C t=@show() { local t=@'; then
  new_case m52
  LC_ALL=C.UTF-8 NEW_SUT="$MUTANT" FAKE_CURL_COST=1 ARMONE_BOOKS="$CASE/x${BIDI}Y/books" run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
  if [[ "$UTF8_OK" -eq 1 ]]; then
    assert "M52 RED: the bidi override reaches the terminal" "[[ \"\$OUT\" == *\"\$BIDI\"* ]]"
  else
    pass "M52 RED (skipped: no UTF-8 locale)"
  fi
fi

# M53 — an empty-after-strip pagination.next ("\n") ends the list as if it were complete.
# shellcheck disable=SC2016  # the sed program is data; expanding it here is the bug
if mutate blank-next-ends-list 1 's@then error("empty pagination.next") else . end@then "" else . end@'; then
  new_case m53
  printf '{"data":[%s],"pagination":{"next":"\\n"}}' "$(hb_row "$ID_HOST" "$HOST_NAME" paused)" > "$FAKE_LIST_DIR/page-1.json"
  NEW_SUT="$MUTANT" run_named --status "$HOST_NAME"
  assert_eq "M53 RED: the mutant resolves from a list that said it continued (exit 0)" "0" "$RC"
fi

# New-mode control: an UNMUTATED copy, run through the same harness, still arms.
cp "$SUT" "$WORK/mutant-control-new.sh" || { echo "FATAL: control copy failed"; exit 2; }
new_case m34
echo 30 > "$FAKE_STATE/$ID_HOST.upat"
NEW_SUT="$WORK/mutant-control-new.sh" FAKE_CURL_COST=1 run_named --arm-one "$HOST_NAME" --id "$ID_HOST"
assert_eq "M34 control: the UNMUTATED --arm-one still arms (rc 0)" "0" "$RC"
assert_eq "M34 control: with exactly one PATCH" "1" "$(patch_count)"

# M15 — the anti-vacuity control. An UNMUTATED copy, run through the same harness, must still be
# GREEN; without it a red baseline is indistinguishable from a caught mutation.
cp "$SUT" "$WORK/mutant-control.sh" || { echo "FATAL: control copy failed"; exit 2; }
case_setup m15
printf 'paused' > "$FAKE_STATE/$ID_INNGEST.status"
FAKE_CURL_COST=15 run_sut "$WORK/mutant-control.sh"
assert_eq "M15 control: the UNMUTATED copy still soft-lands at rc=0" "0" "$RC"
assert "M15 control: and still advertises the 30s deadline" "[[ \"\$OUT\" == *'no beat within 30s'* ]]"
case_setup m15b
printf '%s\n' "$ID_ZOT1" > "$STATEFILE"
run_sweep "$WORK/mutant-control.sh"
assert_eq "M15 control: the UNMUTATED sweep still exits 0 on a clean re-pause" "0" "$RC"

echo
echo "arm-heartbeats: ${PASS} passed, ${FAIL} failed ($((PASS + FAIL)) assertions)"
# MINIMUM-CARDINALITY FLOOR. A harness whose case loop silently ran nothing would otherwise report
# "0 failed" and read as success. Absolute and hand-ratcheted — there is no second producer here to
# derive it from. Ratcheted 55 → 190, the EXACT shipped count (#7656 C8: 55 against an actual 69
# left room to delete a whole ten-assertion case without tripping it). Exact, not "shipped minus a
# margin": a margin is precisely the room a silent narrowing hides in, and removing an assertion on
# purpose should cost one deliberate edit here. Ratcheted 190 → 206 for T11 (the external cut),
# T4's self-clearing sequence, S4's annotation, and mutation row M18. Ratcheted 206 → 234 for the
# stdin-bearer conversion (#7797): the stub's argv/--disable/--noproxy refusals and their self-tests,
# T12 (destination pin, token shape, xtrace) and mutation rows M19-M21. Ratcheted 234 -> 374 for #9980:
# the list endpoint's stub self-tests (H1), cases ST1-ST5/AX/AO1-AO9, mutation rows M22-M33 and the
# new-mode control M34. Ratcheted 374 -> 454 for the review round: ST1b-ST5n, AX2, AO5 (up/down/pending),
# AO6f-g, AO7b-d, AO10-AO12 and mutation rows M35-M42. Ratcheted 454 -> 562 for the second fix-round: AO13-AO34 (record-before-act pinned
# by a snapshot taken at the unpause PATCH, the books read-back, residual-books independence) and mutation rows M43-M54.
# Ratcheted 562 -> 583 for the web-bash-synthetic arms (#10455 b): W1-W5 (soft landing, one-host arming, failed rollback, no-op, host coverage + RED controls).
ASSERT_FLOOR=583
if [[ $((PASS + FAIL)) -lt "$ASSERT_FLOOR" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran against a floor of ${ASSERT_FLOOR} — the suite is narrowed or a case aborted early."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
