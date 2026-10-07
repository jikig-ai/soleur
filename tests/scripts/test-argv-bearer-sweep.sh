#!/usr/bin/env bash
# Guard 2 of the argv-bearer sweep (#7843, plan 2026-10-06-chore-sweep-argv-bearer-tokens-
# to-curl-config-stdin): the CONVERSION BATTERY.
#
# PROPERTY. For every followthrough probe that holds a credentialed curl, a run that
# reaches the call records the bearer on curl's STDIN and never in curl's argument list;
# an unusable credential produces zero calls and never the script's PASS outcome; a
# stripped or rejected credential produces the script's TRANSIENT status, never PASS.
#
# THE CHOKEPOINT is a PATH-shim `curl` that every row runs the script under
# (`env -i PATH=<shim>:<symlink dir of needed real tools> HOME TMPDIR`, fail-closed
# gh/doppler/ssh stubs). It records each call to calls/<n>.argv (NUL-delimited) and
# calls/<n>.stdin (a `--data-binary @-` / `-d @-` body goes to calls/<n>.body), models real
# curl (reads stdin ONLY for `--config -`/`-K -`/`-H @-`/`--data-binary @-`/`-d @-`; an
# arity table for flags with values; -o, -D, -w in both the real-newline and `\n` forms;
# exit 22 on HTTP >= 400 with -f/--fail/--fail-with-body; exit 99 `UNMODELLED FLAG` for
# anything outside its table), parses stdin config lines against
# `^header = "[^"\\]*"$` and records INJECTED for any other line, and is AUTH-GATED: 200
# and a canned body only when `Authorization: Bearer <fixture>` arrives, else 401.
#
# INSTRUMENT CONTROLS run first and abort the suite with FATAL (a green battery over a
# blind shim is the failure this suite exists to prevent):
#   C1 a canonical-compliant synthetic probe must be GREEN;
#   C2 an argv-bearer synthetic probe must be RED on the 'token in recorded argv' check;
#   C3 the real-curl ORACLE: `curl --libcurl` against http://127.0.0.1:9/ (nothing
#      listens; no server needed) must show exactly one Authorization header append for
#      the stdin config form and a SECOND CURLOPT_URL for a hostile token
#      (quote + newline + `url = "..."`) -- so the shim's INJECTED model is calibrated to
#      the real tool, not to the author's belief about it.
#
# EVERY DERIVED PROBE ASSERTS THE FULL CONTRACT (bearer on stdin, token in no argv, hostile
# tokens refused, xtrace refusal, 100 KB pipefail). Baseline E (scripts/lint-shell-trace-
# credential-refusal-e.baseline.txt) lists only the deferred host-deployed infra scripts, so a
# followthrough probe reappearing there is itself a failure (population row below).
#
# THE POPULATION IS DERIVED (git ls-files scripts/followthroughs/*.sh holding a
# credentialed curl), never counted: each member must be in exactly one of the dynamic
# manifest, the static-only exclusions (with a justification and a row that goes RED when
# the probe becomes hermetically reachable) or the delegated list (owning test named).
#
# All tokens are SYNTHESIZED. No network, no Doppler, no real credential is ever read.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

pass=0; fail=0; CASES=0

# ONE scratch root, ONE EXIT trap, installed before anything is written under it.
TMPD="$(mktemp -d -t argv-bearer-sweep.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the verbatim body; see plugins/soleur/test/test-helpers.sh). Every fixture in
# this suite is written under $TMPD and the EXIT trap removes it recursively, so
# a relative or `..`-bearing root would put both the writes and the `rm -rf`
# somewhere other than the scratch dir.
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
assert_fixture_dir "$TMPD"

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}
# Every row goes through `row`, which counts at the CALL SITE. `pass + fail` is reconciled
# against CASES at the bottom, so a `_report` that silently stops counting cannot hide.
row() { CASES=$((CASES + 1)); _report "$@"; }

# INSTRUMENT SELF-TEST of the pass/fail helper. Both counters are moved only inside
# `_report`; a floor over `pass + fail` is computed from the very helper it backstops
# (measured elsewhere: routing the fail branch into `pass` left a suite green with two
# failing rows). Only driving the helper in BOTH directions can see that. Counters are
# restored so the row count stays exact. Failures are reported with printf + exit, never
# through the helpers they guard.
_selftest_report() {
  local p0=$pass f0=$fail c0=$CASES
  row "instrument self-test: ok moves pass" ok
  if [[ "$pass" -ne $((p0 + 1)) || "$fail" -ne "$f0" ]]; then
    printf '[FATAL] _report ok did not move pass alone (pass %s->%s, fail %s->%s)\n' "$p0" "$pass" "$f0" "$fail" >&2
    exit 2
  fi
  row "instrument self-test: fail moves fail (expected; retracted immediately)" fail
  if [[ "$fail" -ne $((f0 + 1)) || "$pass" -ne $((p0 + 1)) ]]; then
    printf '[FATAL] _report fail did not move fail alone (pass %s->%s, fail %s->%s)\n' "$p0" "$pass" "$f0" "$fail" >&2
    exit 2
  fi
  pass=$p0; fail=$f0; CASES=$c0
}
_selftest_report

# --------------------------------------------------------------------------------------
# TOOLING: the real tools a probe needs, symlinked into ONE dir. curl/gh/doppler/ssh/git are
# deliberately absent: the shim dir supplies curl, and the others are fail-closed stubs.
# --------------------------------------------------------------------------------------
BASH_BIN="$(type -P bash)" || { echo "FATAL: no bash" >&2; exit 2; }
REAL_CURL="$(type -P curl || true)"
[[ -n "$REAL_CURL" ]] || { echo "FATAL: no real curl for the --libcurl oracle (control C3)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required (every probe parses with it)" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git is required (the population is derived from git ls-files)" >&2; exit 2; }

REALBIN="$TMPD/realbin"; SHIMDIR="$TMPD/shimbin"; SYN="$TMPD/synth"; BODIES="$TMPD/bodies"; ROWS="$TMPD/rows"
for d in "$REALBIN" "$SHIMDIR" "$SYN" "$BODIES" "$ROWS"; do
  assert_fixture_dir "$d"
  mkdir -p "$d"
done
for t in bash cat date grep egrep head tail jq sed tr awk sort uniq wc mktemp rm mkdir env dirname basename cut tee expr sleep readlink ls cp mv xargs true false id uname paste openssl stat; do
  p="$(type -P "$t" || true)"
  [[ -n "$p" ]] && ln -s "$p" "$REALBIN/$t"
done

# THE SHIM. A quoted heredoc so nothing expands at write time; the interpreter line is
# rewritten to the absolute bash afterwards (an `env -i` PATH has no /usr/bin/env guarantee).
cat > "$SHIMDIR/curl" <<'SHIM_EOF'
#!/usr/bin/env bash
# PATH-shim curl for tests/scripts/test-argv-bearer-sweep.sh. Synthesized fixtures only.
set -u
D="${SHIM_DIR:?SHIM_DIR unset}"
mkdir -p "$D/calls"
n=0
[[ -r "$D/counter" ]] && read -r n < "$D/counter"
n=$((n + 1))
printf '%s\n' "$n" > "$D/counter"
C="$D/calls/$n"
printf '%s\0' "$@" > "$C.argv"

unmodelled() {
  printf 'UNMODELLED FLAG: %s\n' "$1" >&2
  printf '%s\n' "$1" >> "$D/unmodelled"
  exit 99
}

args=("$@"); i=0
hdrs=(); urls=(); out=""; dump=""; wfmt=""; failmode=""
use_cfg_stdin=0; use_hdr_stdin=0; body_stdin=""

apply_value() { # $1 flag, $2 value
  case "$1" in
    -H|--header)
      case "$2" in
        @-) use_hdr_stdin=1 ;;
        @*) unmodelled "$1 @file" ;;
        *) hdrs+=("$2") ;;
      esac ;;
    -K|--config)
      if [[ "$2" == "-" ]]; then use_cfg_stdin=1; else unmodelled "$1 <file>"; fi ;;
    -w|--write-out)
      case "$2" in @*) unmodelled "$1 @file" ;; esac
      wfmt="$2" ;;
    -o|--output) out="$2" ;;
    -D|--dump-header) dump="$2" ;;
    -d|--data|--data-binary|--data-raw|--data-urlencode)
      # A body on STDIN (`@-`) is read below, once the whole argv is parsed. `--data-binary @-`
      # keeps CR/LF; `-d/--data @-` strips them, exactly as real curl does (calibrated by
      # control C4 against `curl --libcurl`). A body FILE is not modelled: no probe uses one.
      case "$2" in
        @-) case "$1" in
              --data-binary) body_stdin=binary ;;
              -d|--data) body_stdin=strip ;;
              *) unmodelled "$1 @- (body on stdin)" ;;
            esac ;;
        @*) unmodelled "$1 @file" ;;
      esac ;;
    -X|--request|-m|--max-time|--connect-timeout|--max-redirs|--proto|--proto-redir|--retry|--retry-delay|--retry-max-time|-A|--user-agent|-u|--user|-e|--referer|--noproxy) : ;;
    --url) urls+=("$2") ;;
    *) unmodelled "$1" ;;
  esac
}

while (( i < ${#args[@]} )); do
  a="${args[i]}"; i=$((i + 1))
  case "$a" in
    --disable|--silent|--show-error|--globoff|--get|--location|--compressed|--http1.1) : ;;
    --fail) failmode=fail ;;
    --fail-with-body) failmode=body ;;
    --*=*) apply_value "${a%%=*}" "${a#*=}" ;;
    --header|--write-out|--output|--dump-header|--request|--data|--data-binary|--data-raw|--data-urlencode|--max-time|--connect-timeout|--max-redirs|--proto|--proto-redir|--retry|--retry-delay|--retry-max-time|--user-agent|--user|--referer|--noproxy|--url|--config)
      (( i < ${#args[@]} )) || unmodelled "$a (missing value)"
      apply_value "$a" "${args[i]}"; i=$((i + 1)) ;;
    --) while (( i < ${#args[@]} )); do urls+=("${args[i]}"); i=$((i + 1)); done ;;
    --*) unmodelled "$a" ;;
    -?*)
      c="${a:1}"
      while [[ -n "$c" ]]; do
        ch="${c:0:1}"; c="${c:1}"
        case "$ch" in
          s|S|g|G|L) : ;;
          f) failmode=fail ;;
          H|w|o|D|X|d|m|K|u|A|e)
            if [[ -n "$c" ]]; then val="$c"; c=""
            else
              (( i < ${#args[@]} )) || unmodelled "-$ch (missing value)"
              val="${args[i]}"; i=$((i + 1))
            fi
            apply_value "-$ch" "$val" ;;
          *) unmodelled "-$ch" ;;
        esac
      done ;;
    *) urls+=("$a") ;;
  esac
done

mode="${SHIM_MODE:-auth}"
case "$mode" in auth|deny|noauth|noread|fail7) : ;; *) unmodelled "SHIM_MODE=$mode" ;; esac

# stdin is read ONLY for the forms real curl reads it for.
if [[ -n "$body_stdin" ]]; then
  data="$(cat; printf x)"; data="${data%x}"
  if [[ "${SHIM_MUTATE:-}" != nobody ]]; then
    if [[ "$body_stdin" == strip ]]; then printf '%s' "$data" | tr -d '\r\n' > "$C.body"; else printf '%s' "$data" > "$C.body"; fi
  fi
fi
if (( use_cfg_stdin || use_hdr_stdin )); then
  if [[ "$mode" == noread ]]; then
    : > "$C.stdin-unread"
  else
    data="$(cat; printf x)"; data="${data%x}"
    [[ "${SHIM_MUTATE:-}" == nostdin ]] || printf '%s' "$data" > "$C.stdin"
    lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      lineno=$((lineno + 1))
      [[ -z "$line" || "$line" == \#* ]] && continue
      if (( use_cfg_stdin )); then
        if [[ "$line" =~ ^header\ =\ \"([^\"\\]*)\"$ ]]; then
          hdrs+=("${BASH_REMATCH[1]}")
        else
          # The line CONTENT is never written: it may be the secret itself.
          printf 'INJECTED: stdin config line %s is not a bare header directive\n' "$lineno" >> "$C.injected"
        fi
      else
        if [[ "$line" =~ ^[A-Za-z][A-Za-z0-9-]*:\  ]]; then
          hdrs+=("$line")
        else
          printf 'INJECTED: stdin header line %s is not Name: value\n' "$lineno" >> "$C.injected"
        fi
      fi
    done < <(printf '%s' "$data")
  fi
fi

url="${urls[0]:-}"
hostpart="${url#*://}"; hostpart="${hostpart%%[/?#]*}"; hostpart="${hostpart##*@}"; hostpart="${hostpart%%:*}"
printf '%s\n' "$hostpart" > "$C.host"
# fail7: a transport failure (curl exit 7, connection refused), calibrated against real curl (control C4).
if [[ "$mode" == fail7 ]]; then printf 'curl: (7) Failed to connect\n' >&2; exit 7; fi

have_auth=0
for h in "${hdrs[@]:-}"; do
  [[ -n "${SHIM_FIXTURE_TOKEN:-}" && "$h" == "Authorization: ${SHIM_SCHEME:-Bearer} ${SHIM_FIXTURE_TOKEN}" ]] && have_auth=1
done

case "$mode" in
  deny) status=401 ;;
  noauth|noread) status=200 ;;
  auth) if (( have_auth )); then status=200; else status=401; fi ;;
esac
[[ "${SHIM_MUTATE:-}" == noauth ]] && status=200
[[ -n "${SHIM_STATUS:-}" ]] && status="$SHIM_STATUS"

if (( status == 200 )) || (( status < 400 )); then
  if [[ -n "${SHIM_BODY_FILE:-}" ]]; then body="$(cat "$SHIM_BODY_FILE"; printf x)"; body="${body%x}"
  else body='{"data":[]}'; fi
else
  body='{"detail":"Invalid token"}'
fi

expand_w() {
  local s="$1" o=""
  while [[ -n "$s" ]]; do
    case "$s" in
      '%{http_code}'*) o+="$status"; s="${s#'%{http_code}'}" ;;
      '%{'*) unmodelled "-w ${s%%\}*}}" ;;
      '%%'*) o+="%"; s="${s#%%}" ;;
      '\n'*) o+=$'\n'; s="${s#\\n}" ;;
      '\r'*) o+=$'\r'; s="${s#\\r}" ;;
      '\t'*) o+=$'\t'; s="${s#\\t}" ;;
      '\\'*) o+='\'; s="${s#\\\\}" ;;
      *) o+="${s:0:1}"; s="${s:1}" ;;
    esac
  done
  printf '%s' "$o"
}

failed=0
if (( status >= 400 )) && [[ -n "$failmode" ]]; then failed=1; fi

hdr_block="HTTP/2 ${status}"$'\r\n'
[[ -n "${SHIM_LINK_HEADER:-}" ]] && hdr_block+="link: ${SHIM_LINK_HEADER}"$'\r\n'
hdr_block+=$'\r\n'
if [[ -n "$dump" ]]; then
  if [[ "$dump" == "-" ]]; then printf '%s' "$hdr_block"; else printf '%s' "$hdr_block" > "$dump"; fi
fi
if (( failed )) && [[ "$failmode" == fail ]]; then
  :
elif [[ -n "$out" ]]; then
  printf '%s' "$body" > "$out"
else
  printf '%s' "$body"
fi
[[ -n "$wfmt" ]] && expand_w "$wfmt"
if (( failed )); then
  printf 'curl: (22) The requested URL returned error: %s\n' "$status" >&2
  exit 22
fi
exit 0
SHIM_EOF
sed -i "1s|.*|#!${BASH_BIN}|" "$SHIMDIR/curl"
chmod +x "$SHIMDIR/curl"
# `jq` shim: records its argv (a `jq --arg pw "$PW"` regression is invisible to the curl shim: jq's own
# argv is world-readable too) and then runs the real jq. Passthrough, so every probe is unchanged.
REAL_JQ="$(type -P jq)"
cat > "$SHIMDIR/jq" <<'JQ_EOF'
#!/usr/bin/env bash
D="${SHIM_DIR:-}"
if [[ -n "$D" ]]; then
  mkdir -p "$D/jq"; n=0
  [[ -r "$D/jq/counter" ]] && read -r n < "$D/jq/counter"
  n=$((n + 1)); printf '%s\n' "$n" > "$D/jq/counter"
  printf '%s\0' "$@" > "$D/jq/$n.argv"
fi
exec "@REAL_JQ@" "$@"
JQ_EOF
sed -i "1s|.*|#!${BASH_BIN}|; s|@REAL_JQ@|${REAL_JQ}|" "$SHIMDIR/jq"
chmod +x "$SHIMDIR/jq"
for t in gh doppler ssh; do
  printf '#!%s\nset -u\nprintf "%%s\\n" "%s" >> "${SHIM_DIR:-/dev/null}/unexpected"\nprintf "UNEXPECTED CALL to %s (fail-closed stub)\\n" >&2\nexit 97\n' "$BASH_BIN" "$t" "$t" > "$SHIMDIR/$t"
  chmod +x "$SHIMDIR/$t"
done

# The ONE fixture credential. Synthesized, never a real value.
FIXTURE_TOKEN="synthetic-fixture-token-0001"

# run_probe <rowname> <script> [NAME=value ...]  -> RUN_RC, $ROWS/<rowname>/{stdout,stderr,shim/}
# RUN_FLAGS (array) holds extra `bash` flags for this one call (e.g. -x). Every run is under
# `env -i`, so the only environment a probe sees is the one spelled out here.
RUN_RC=0; RUN_ROW=""; RUN_FLAGS=(); RUN_ARGS=(); RUN_EXTRA_PATH=""
run_probe() {
  local name="$1" script="$2"; shift 2
  RUN_ROW="$ROWS/$name"
  assert_fixture_dir "$RUN_ROW"
  mkdir -p "$RUN_ROW/home" "$RUN_ROW/tmp" "$RUN_ROW/shim"
  (
    cd "$RUN_ROW" || exit 99
    env -i PATH="${RUN_EXTRA_PATH:+$RUN_EXTRA_PATH:}$SHIMDIR:$REALBIN" HOME="$RUN_ROW/home" TMPDIR="$RUN_ROW/tmp" \
      SHIM_DIR="$RUN_ROW/shim" SHIM_FIXTURE_TOKEN="$FIXTURE_TOKEN" "$@" \
      "$BASH_BIN" ${RUN_FLAGS[@]+"${RUN_FLAGS[@]}"} "$script" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"} < /dev/null > "$RUN_ROW/stdout" 2> "$RUN_ROW/stderr"
  )
  RUN_RC=$?
}

# --------------------------------------------------------------------------------------
# EVALUATION. Sets EV_FAILED to a space-separated list of failed check NAMES (empty = GREEN),
# so a mutation row can assert WHICH check fired, not merely that something did.
#   calls-below-min      fewer calls to the manifest hosts than min_calls
#   bearer-not-on-stdin  a call to a manifest host whose stdin did not carry the bearer
#   token-in-argv        the token marker appears in ANY recorded argv
#   token-in-jq-argv     the token marker appears in ANY recorded jq argv (the jq shim)
#   injected             the shim recorded an INJECTED stdin line
#   unexpected-host      a call to a host outside the manifest
#   unexpected-tool      a gh/doppler/ssh stub was called
#   unmodelled-flag      the probe used a curl flag the shim does not model
#   token-in-output      the token marker is in the probe's stdout or stderr
#   bash-error           a `<script>: line N:` bash error in stderr
# --------------------------------------------------------------------------------------
EV_FAILED=""; EV_CALLS=0; EV_HOST_CALLS=0
count_calls() { # <rowdir> -> sets EV_CALLS
  local f; EV_CALLS=0
  for f in "$1"/shim/calls/*.argv; do [[ -e "$f" ]] && EV_CALLS=$((EV_CALLS + 1)); done
  return 0
}
evaluate() { # <rowdir> <hosts-regex> <min_calls> <token-or-marker> [scheme, default Bearer]
  local row="$1" hosts="$2" min="$3" tok="$4" scheme="${5:-Bearer}" f c h
  EV_FAILED=""; EV_HOST_CALLS=0; count_calls "$row"
  for f in "$row"/shim/calls/*.argv; do
    [[ -e "$f" ]] || continue
    c="${f%.argv}"; h=""
    [[ -r "$c.host" ]] && h="$(<"$c.host")"
    if [[ "$h" =~ ^(${hosts})$ ]]; then
      EV_HOST_CALLS=$((EV_HOST_CALLS + 1))
      if ! { [[ -r "$c.stdin" ]] && { grep -qxF -- "header = \"Authorization: $scheme $tok\"" "$c.stdin" || grep -qxF -- "Authorization: $scheme $tok" "$c.stdin"; }; }; then
        EV_FAILED+=" bearer-not-on-stdin"
      fi
    else
      EV_FAILED+=" unexpected-host"
    fi
    grep -aqF -- "$tok" "$f" && EV_FAILED+=" token-in-argv"
    [[ -s "$c.injected" ]] && EV_FAILED+=" injected"
  done
  for f in "$row"/shim/jq/*.argv; do
    [[ -e "$f" ]] || continue
    grep -aqF -- "$tok" "$f" && EV_FAILED+=" token-in-jq-argv"
  done
  (( EV_HOST_CALLS < min )) && EV_FAILED+=" calls-below-min"
  [[ -e "$row/shim/unexpected" ]] && EV_FAILED+=" unexpected-tool"
  [[ -e "$row/shim/unmodelled" ]] && EV_FAILED+=" unmodelled-flag"
  if grep -aqF -- "$tok" "$row/stdout" "$row/stderr" 2>/dev/null; then EV_FAILED+=" token-in-output"; fi
  if grep -aqE ': line [0-9]+: ' "$row/stderr" 2>/dev/null; then EV_FAILED+=" bash-error"; fi
  # de-duplicate, keep order
  EV_FAILED="$(printf '%s\n' $EV_FAILED | awk '!s[$0]++' | paste -sd' ' -)"
  return 0
}
has_check() { [[ " $EV_FAILED " == *" $1 "* ]]; }

# A TRANSIENT-style outcome: rc 2, never PASS, a TRANSIENT marker on stderr, no bash error.
transient_outcome() { # <rowdir> <rc>
  local row="$1" rc="$2"
  [[ "$rc" -eq 2 ]] || return 1
  grep -q '^PASS' "$row/stdout" && return 1
  grep -q 'TRANSIENT' "$row/stderr" || return 1
  grep -aqE ': line [0-9]+: ' "$row/stderr" && return 1
  return 0
}

# --------------------------------------------------------------------------------------
# SYNTHETIC PROBES. Modelled on the followthrough probes (xtrace refusal, token guard,
# curl, TRANSIENT/PASS/FAIL contract). Variants are assembled from fragments so each
# mutation differs from the canonical in exactly one place.
# --------------------------------------------------------------------------------------
SYN_HOST='synthetic\.example\.test'
SYN_URL='https://synthetic.example.test/api/0/ok'
synth_head() {
  cat <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${SYNTH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SYNTH_TOKEN).\n' >&2
      exit 78
    fi
    ;;
esac
EOF
}
synth_guard() {
  cat <<'EOF'
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "${SYNTH_TOKEN:-}"; then echo "TRANSIENT: token unusable" >&2; exit 2; fi
EOF
}
synth_tail() {
  cat <<'EOF'
rc=$?
if [[ "$rc" -ne 0 ]]; then echo "TRANSIENT: curl rc=$rc" >&2; exit "$rc"; fi
HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')
if [[ "$HTTP_STATUS" != "200" ]]; then echo "TRANSIENT: API returned $HTTP_STATUS" >&2; exit 2; fi
N=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)
if ! [[ "$N" =~ ^[0-9]+$ ]]; then echo "TRANSIENT: unparseable body" >&2; exit 2; fi
if [[ "$N" -eq 0 ]]; then echo "PASS: 0 events"; exit 0; fi
echo "FAIL: $N events"; exit 1
EOF
}
# call fragments (each ends the `RESP=` assignment; synth_tail starts with `rc=$?`)
synth_call() { # <variant>
  case "$1" in
    canonical) cat <<EOF
RESP=\$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  --config - -H "Accept: application/json" \\
  "$SYN_URL" \\
  < <(printf 'header = "Authorization: Bearer %s"\n' "\${SYNTH_TOKEN}"))
EOF
    ;;
    argv) cat <<EOF
RESP=\$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  -H "Authorization: Bearer \${SYNTH_TOKEN}" -H "Accept: application/json" \\
  "$SYN_URL")
EOF
    ;;
    pipe) cat <<EOF
RESP=\$(printf 'header = "Authorization: Bearer %s"\n' "\${SYNTH_TOKEN}" | curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  --config - -H "Accept: application/json" \\
  "$SYN_URL")
EOF
    ;;
    hdrfile) cat <<EOF
RESP=\$(printf 'Authorization: Bearer %s\n' "\${SYNTH_TOKEN}" | curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  -H @- -H "Accept: application/json" \\
  "$SYN_URL")
EOF
    ;;
    wrapper) cat <<EOF
synth_curl() {
  _bearer_ok "\${SYNTH_TOKEN:-}" || { echo "synth_curl: token unusable" >&2; return 2; }
  curl --disable --noproxy '*' "\$@" --config - \\
    < <(printf 'header = "Authorization: Bearer %s"\n' "\${SYNTH_TOKEN}")
}
RESP=\$(synth_curl -sS -w '\nHTTP_STATUS:%{http_code}' -H "Accept: application/json" "$SYN_URL")
EOF
    ;;
    two-curls-second-argv) cat <<EOF
FIRST=\$(curl --disable --noproxy '*' -sS -o /dev/null -w '%{http_code}' \\
  --config - "$SYN_URL" \\
  < <(printf 'header = "Authorization: Bearer %s"\n' "\${SYNTH_TOKEN}"))
RESP=\$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  -H "Authorization: Bearer \${SYNTH_TOKEN}" "$SYN_URL")
EOF
    ;;
    bot) cat <<EOF
RESP=\$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \\
  --config - -H "Accept: application/json" \\
  "$SYN_URL" \\
  < <(printf 'header = "Authorization: Bot %s"\n' "\${SYNTH_TOKEN}"))
EOF
    ;;
    *) echo "FATAL: unknown synth variant $1" >&2; exit 2 ;;
  esac
}
make_synth() { # <variant> [noguard] -> path
  local v="$1" guard="${2:-guard}" p="$SYN/synth-$1${2:+-$2}.sh"
  { synth_head; [[ "$guard" == noguard ]] || synth_guard; synth_call "$v"; synth_tail; } > "$p"
  printf '%s\n' "$p"
}

# canned bodies
printf '%s' '{"data":[]}' > "$BODIES/sentry_empty.json"
printf '%s' '{"data":[{"title":"synthetic","timestamp":"2026-10-01T00:00:00"}]}' > "$BODIES/sentry_events.json"
printf '%s' "[{\"dateAdded\":\"$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"ok\"}]" > "$BODIES/checkins.json"
printf '%s' '[{"relname":"user_concurrency_slots","autovacuum_count":142,"stats_reset":null},{"relname":"mint_rate_window","autovacuum_count":50,"stats_reset":null},{"relname":"runtime_mint_intent","autovacuum_count":49,"stats_reset":null}]' > "$BODIES/autovac.json"
printf '%s' '[{"relname":"user_concurrency_slots","n_tup_upd":7635,"n_tup_ins":700,"stats_reset":null}]' > "$BODIES/slots.json"
printf '%s' '{"data":[{"attributes":{"name":"soleur-web-zot-consumer-web-1","status":"up"}},{"attributes":{"name":"soleur-web-nic-guard-web-1","status":"up"}},{"attributes":{"name":"soleur-git-data-prd","status":"up"}},{"attributes":{"name":"soleur-web-zot-consumer-web-2","status":"up"}},{"attributes":{"name":"soleur-web-nic-guard-web-2","status":"up"}}]}' > "$BODIES/bs_up.json"

# =====================================================================================
# INSTRUMENT CONTROLS (abort with FATAL; counted as rows when they pass)
# =====================================================================================
fatal() { printf '[FATAL] instrument control failed: %s\n' "$1" >&2; exit 2; }

# C1: the canonical-compliant synthetic probe must be GREEN.
P_CANON="$(make_synth canonical)"
run_probe c1-canonical "$P_CANON" "SYNTH_TOKEN=$FIXTURE_TOKEN"
C1_RC=$RUN_RC
evaluate "$ROWS/c1-canonical" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if [[ "$C1_RC" -ne 0 || -n "$EV_FAILED" ]] || ! grep -q '^PASS' "$ROWS/c1-canonical/stdout"; then
  fatal "C1 canonical-compliant synthetic probe is not GREEN (rc=$C1_RC failed='$EV_FAILED')"
fi
row "control C1: canonical-compliant synthetic probe is GREEN (rc 0, PASS, bearer on stdin only)" ok

# C2: an argv-bearer synthetic probe must be RED on the 'token in recorded argv' check.
P_ARGV="$(make_synth argv)"
run_probe c2-argv "$P_ARGV" "SYNTH_TOKEN=$FIXTURE_TOKEN"
evaluate "$ROWS/c2-argv" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
has_check token-in-argv || fatal "C2 argv-bearer synthetic probe was not caught on token-in-argv (failed='$EV_FAILED')"
has_check calls-below-min && fatal "C2 argv-bearer probe made no calls; RED must come from the argv check, not from silence"
row "control C2: argv-bearer synthetic probe is RED on 'token in recorded argv' (not on silence)" ok

# C3: the REAL-CURL ORACLE. The shim's model of the stdin config channel is calibrated against
# curl itself: `--libcurl` writes the C program curl WOULD run. Nothing listens on port 9, so the
# transfer fails with rc 7 -- the generated program is still written.
ORA="$TMPD/oracle"; assert_fixture_dir "$ORA"; mkdir -p "$ORA"
printf 'header = "Authorization: Bearer %s"\n' "$FIXTURE_TOKEN" \
  | "$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/ok.c" --config - http://127.0.0.1:9/ >/dev/null 2>&1 || true
HOSTILE="$(printf 'SYNTHMARK0001"\nurl = "http://127.0.0.1:9/second')"
printf 'header = "Authorization: Bearer %s"\n' "$HOSTILE" \
  | "$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/hostile.c" --config - http://127.0.0.1:9/ >/dev/null 2>&1 || true
[[ -s "$ORA/ok.c" && -s "$ORA/hostile.c" ]] || fatal "C3 real curl did not write --libcurl output (curl built without --libcurl?)"
ora_appends=$(grep -c 'curl_slist_append(slist1, "Authorization: Bearer' "$ORA/ok.c" || true)
ora_urls_ok=$(grep -c 'CURLOPT_URL' "$ORA/ok.c" || true)
ora_urls_hostile=$(grep -c 'CURLOPT_URL' "$ORA/hostile.c" || true)
[[ "$ora_appends" -eq 1 ]] || fatal "C3 oracle: expected exactly one Authorization append for the stdin config form, saw $ora_appends"
[[ "$ora_urls_ok" -eq 1 ]] || fatal "C3 oracle: expected one CURLOPT_URL for a clean token, saw $ora_urls_ok"
[[ "$ora_urls_hostile" -eq 2 ]] || fatal "C3 oracle: expected a SECOND CURLOPT_URL for the hostile token (config injection), saw $ora_urls_hostile"
# ...and the shim must agree with the oracle on the SAME hostile token: INJECTED recorded.
run_probe c3-shim-hostile "$(make_synth canonical noguard)" "SYNTH_TOKEN=$HOSTILE"
count_calls "$ROWS/c3-shim-hostile"
shim_injected=0; for f in "$ROWS"/c3-shim-hostile/shim/calls/*.injected; do [[ -s "$f" ]] && shim_injected=1; done
[[ "$shim_injected" -eq 1 ]] || fatal "C3 shim did not record INJECTED for the token the real-curl oracle shows injecting a request"
row "control C3: real-curl oracle (--libcurl): 1 Authorization append (stdin config), 2nd CURLOPT_URL for a hostile token, shim records INJECTED for it" ok

# =====================================================================================
# MUTATION ROWS against SYNTHETIC probes (plan matrix #1-#9), so they run before any real
# conversion exists. Each variant differs from the canonical in exactly one place.
# =====================================================================================
canon_env=("SYNTH_TOKEN=$FIXTURE_TOKEN")
sorted_failed() { [[ -n "$EV_FAILED" ]] && printf '%s\n' $EV_FAILED | sort | paste -sd' ' - || true; }

# 1: revert a converted probe to `-H "Authorization: Bearer ${TOK}"` -> RED on check (ii) SPECIFICALLY.
run_probe m1-revert "$P_ARGV" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check token-in-argv && ! has_check calls-below-min && [[ "$(sorted_failed)" == "bearer-not-on-stdin token-in-argv" ]]; then
  row "mutation 1: reverting a converted probe to an argv bearer is RED on token-in-argv (not on 'no calls')" ok
else row "mutation 1: reverting a converted probe to an argv bearer is RED on token-in-argv (not on 'no calls')" fail "failed='$EV_FAILED'"; fi

# 2: a covered script exits before its curl -> RED on the call-count check.
P_EARLY="$SYN/synth-early-exit.sh"; sed '/^RESP=/i exit 0' "$P_CANON" > "$P_EARLY"
grep -q '^exit 0$' "$P_EARLY" || fatal "mutation 2 did not land (no inserted exit)"
run_probe m2-early "$P_EARLY" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check calls-below-min && [[ "$(sorted_failed)" == "calls-below-min" ]]; then
  row "mutation 2: a probe that exits before its curl is RED on calls-below-min (the recorded failing check)" ok
else row "mutation 2: a probe that exits before its curl is RED on calls-below-min (the recorded failing check)" fail "failed='$EV_FAILED'"; fi

# 3: two curls, first converted, second left on argv, 200 mode so the second is reached -> RED.
P_TWO="$(make_synth two-curls-second-argv)"
run_probe m3-two "$P_TWO" "${canon_env[@]}"
evaluate "$RUN_ROW" "$SYN_HOST" 2 "$FIXTURE_TOKEN"
if has_check token-in-argv && [[ "$EV_HOST_CALLS" -eq 2 ]]; then
  row "mutation 3: first call converted, second left on argv (both reached) is RED on token-in-argv" ok
else row "mutation 3: first call converted, second left on argv (both reached) is RED on token-in-argv" fail "calls=$EV_HOST_CALLS failed='$EV_FAILED'"; fi

# 4: harness mutations. The shim stops recording stdin -> RED; the shim stops being auth-gated ->
# a stripped-header probe reaches PASS, which transient_outcome must catch.
run_probe m4a-nostdin "$P_CANON" "${canon_env[@]}" SHIM_MUTATE=nostdin
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "mutation 4a: a shim that stops recording stdin turns the canonical probe RED" ok
else row "mutation 4a: a shim that stops recording stdin turns the canonical probe RED" fail "failed='$EV_FAILED'"; fi
P_STRIP="$SYN/synth-stripped.sh"; sed 's/Authorization: Bearer/X-Stripped: Bearer/g' "$P_CANON" > "$P_STRIP"
grep -q 'X-Stripped' "$P_STRIP" || fatal "mutation 4 (stripped copy) did not land"
run_probe m4b-noauth "$P_STRIP" "${canon_env[@]}" SHIM_MUTATE=noauth
if transient_outcome "$RUN_ROW" "$RUN_RC"; then
  row "mutation 4b: a shim that stops being auth-gated lets a stripped header reach PASS, and the check sees it" fail "stripped probe still read as TRANSIENT"
else row "mutation 4b: a shim that stops being auth-gated lets a stripped header reach PASS, and the check sees it" ok; fi

# 5: must-PASS shapes that are NOT the canonical: `-H @-` fed by printf, a wrapper (form B), and a
# realistic JWT-shaped token in the allowed charset that must reach the call with the bearer on stdin.
for v in hdrfile wrapper; do
  p="$(make_synth "$v")"
  run_probe "m5-$v" "$p" "${canon_env[@]}"
  rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
  if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 5: must-PASS shape '$v' is GREEN" ok
  else row "mutation 5: must-PASS shape '$v' is GREEN" fail "rc=$rc failed='$EV_FAILED'"; fi
done
b64u() { printf '%s' "$1" | base64 | tr -d '=\n' | tr '+/' '-_'; }
JWT="$(b64u '{"alg":"HS256","typ":"JWT"}').$(b64u '{"sub":"synthetic-subject-0001"}').$(b64u 'synthetic-signature-0001')"
run_probe m5-jwt "$P_CANON" "SYNTH_TOKEN=$JWT" "SHIM_FIXTURE_TOKEN=$JWT"
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$JWT"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 5: a JWT-shaped token in the allowed charset reaches the call, bearer on stdin only" ok
else row "mutation 5: a JWT-shaped token in the allowed charset reaches the call, bearer on stdin only" fail "rc=$rc failed='$EV_FAILED'"; fi

# 6: negative paths: header stripped by a mutated copy, and a 401 from the shim -> TRANSIENT, never PASS.
run_probe m6-stripped "$P_STRIP" "${canon_env[@]}"
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "mutation 6: a probe copy with the header stripped is TRANSIENT (rc 2, marker on stderr), never PASS" ok
else row "mutation 6: a probe copy with the header stripped is TRANSIENT (rc 2, marker on stderr), never PASS" fail "rc=$RUN_RC"; fi
run_probe m6-401 "$P_CANON" "${canon_env[@]}" SHIM_MODE=deny
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "mutation 6: a shim 401 on the canonical probe is TRANSIENT (rc 2, marker on stderr), never PASS" ok
else row "mutation 6: a shim 401 on the canonical probe is TRANSIENT (rc 2, marker on stderr), never PASS" fail "rc=$RUN_RC"; fi

# 7: token shapes -> zero calls, no INJECTED, token absent from stderr, TRANSIENT rc.
# MARK is a distinctive substring; grep -F with a multi-line token would match any LINE of it.
tok_for() {
  case "$1" in
    quote-newline-url) printf 'SYNTHMARK0001"\nurl = "http://127.0.0.1:9/second' ;;
    newline-only)      printf 'SYNTHMARK0001\nSYNTHMARK0002' ;;
    non-ascii)         printf 'SYNTHMARK0001\xc3\xa9' ;;
    quote)             printf 'SYNTHMARK0001"x' ;;
    space)             printf 'SYNTHMARK0001 x' ;;
    *) fatal "unknown token class $1" ;;
  esac
}
# shape_row <label> <probe-script> <tokvar> <class|unset|empty> <rowname> [extra env...]
shape_check() { # sets SHAPE_DETAIL; rc 0 = contract held
  local script="$1" tokvar="$2" cls="$3" name="$4"; shift 4
  local -a e=("$@"); local tv=""
  case "$cls" in
    unset) : ;;
    empty) e+=("$tokvar=") ;;
    *) tv="$(tok_for "$cls")"; e+=("$tokvar=$tv") ;;
  esac
  run_probe "$name" "$script" ${e[@]+"${e[@]}"}
  local rc=$RUN_RC; count_calls "$RUN_ROW"
  SHAPE_DETAIL="rc=$rc calls=$EV_CALLS"
  [[ "$EV_CALLS" -eq 0 ]] || return 1
  [[ ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]] || { SHAPE_DETAIL+=" stub-called"; return 1; }
  transient_outcome "$RUN_ROW" "$rc" || { SHAPE_DETAIL+=" not-TRANSIENT"; return 1; }
  if grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr"; then SHAPE_DETAIL+=" token-in-output"; return 1; fi
  return 0
}
for cls in quote-newline-url newline-only non-ascii quote space empty unset; do
  if shape_check "$P_CANON" SYNTH_TOKEN "$cls" "m7-$cls"; then row "mutation 7: synthetic converted probe, token class '$cls': zero calls, TRANSIENT rc 2, token not echoed" ok
  else row "mutation 7: synthetic converted probe, token class '$cls': zero calls, TRANSIENT rc 2, token not echoed" fail "$SHAPE_DETAIL"; fi
done
# ...and the guard-removed mutant is RED: the instrument SEES the injected request line.
P_NOGUARD="$(make_synth canonical noguard)"
run_probe m7-noguard "$P_NOGUARD" "SYNTH_TOKEN=$(tok_for quote-newline-url)"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "SYNTHMARK0001"
if has_check injected; then row "mutation 7: removing the token-shape guard is RED on injected (the shim records the injected config line)" ok
else row "mutation 7: removing the token-shape guard is RED on injected (the shim records the injected config line)" fail "failed='$EV_FAILED'"; fi

# 8: pipe-form mutant under pipefail with a 100,000-byte token and a shim that never reads stdin:
# the converted probe stays rc 0 (the process-substitution writer dies silently); the `printf | curl`
# rewrite dies with 141 (SIGPIPE on the writer, promoted by pipefail).
BIGTOK="$(head -c 100000 /dev/zero | tr '\0' 'A')"
[[ "${#BIGTOK}" -eq 100000 ]] || fatal "100 KB token was not built (${#BIGTOK})"
run_probe m8-converted "$P_CANON" "SYNTH_TOKEN=$BIGTOK" SHIM_MODE=noread
rc=$RUN_RC
if [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then row "mutation 8: converted probe, 100,000-byte token, never-reading shim, pipefail: rc 0" ok
else row "mutation 8: converted probe, 100,000-byte token, never-reading shim, pipefail: rc 0" fail "rc=$rc"; fi
P_PIPE="$(make_synth pipe)"
run_probe m8-pipe "$P_PIPE" "SYNTH_TOKEN=$BIGTOK" SHIM_MODE=noread
rc=$RUN_RC
# 141 is the writer dying of SIGPIPE. A harness that starts this suite with SIGPIPE IGNORED (CI runners do)
# turns the same event into a write error: the builtin printf returns 1 and says "Broken pipe". Both are
# the pipe-form failing where the process-substitution form stayed rc 0, which is the property under test;
# any other non-zero status, or a 1 without the broken-pipe message, is not that event and stays RED.
if [[ "$rc" -eq 141 ]] || { [[ "$rc" -eq 1 ]] && grep -aqi 'broken pipe' "$RUN_ROW/stderr" "$RUN_ROW/stdout" 2>/dev/null; }; then row "mutation 8: pipe-form mutant (printf | curl), same inputs: rc 141 (or 1 with a broken-pipe message when SIGPIPE is ignored)" ok
else row "mutation 8: pipe-form mutant (printf | curl), same inputs: rc 141 (or 1 with a broken-pipe message when SIGPIPE is ignored)" fail "rc=$rc"; fi

# 9: xtrace: SHELLOPTS=xtrace and `bash -x`, token only in env -> refuse rc 78, zero calls, no token on stderr.
xtrace_check() { # <script> <tokvar> <rowname> <mode: env|flag>
  local script="$1" tokvar="$2" name="$3" mode="$4"
  XT_DETAIL=""
  if [[ "$mode" == env ]]; then run_probe "$name" "$script" "$tokvar=$FIXTURE_TOKEN" SHELLOPTS=xtrace
  else RUN_FLAGS=(-x); run_probe "$name" "$script" "$tokvar=$FIXTURE_TOKEN"; RUN_FLAGS=(); fi
  local rc=$RUN_RC; count_calls "$RUN_ROW"
  XT_DETAIL="rc=$rc calls=$EV_CALLS"
  [[ "$rc" -eq 78 && "$EV_CALLS" -eq 0 ]] || return 1
  if grep -aqF -- "$FIXTURE_TOKEN" "$RUN_ROW/stdout" "$RUN_ROW/stderr"; then XT_DETAIL+=" token-on-output"; return 1; fi
  return 0
}
for mode in env flag; do
  if xtrace_check "$P_CANON" SYNTH_TOKEN "m9-$mode" "$mode"; then row "mutation 9: synthetic converted probe refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "mutation 9: synthetic converted probe refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
done

# =====================================================================================
# STAGE 2: THE MANIFEST, KEYED OFF BASELINE E
# =====================================================================================
BASE_E="scripts/lint-shell-trace-credential-refusal-e.baseline.txt"
[[ -f "$BASE_E" ]] || fatal "baseline E is missing ($BASE_E); the population row reads it"

# DYNAMIC: name | token env var | hosts (regex) | min_calls | canned 200 body. Outcome contract of
# every row: the OK body reaches `^PASS` with rc 0; a 401 / stripped header / unusable token is
# TRANSIENT rc 2. Members hold ONE credentialed curl except accounted-beacon (three queries).
DYN_MANIFEST='ac10-workspace-reconcile-sentry-4246|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
ac8-founder-ambiguous-soak-5673|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
accounted-beacon-live-6462|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|3|sentry_events
community-monitor-checkin-soak-5728|SENTRY_ACTIONS_RO_TOKEN|de\.sentry\.io|1|checkins
dashboard-cold-tiers-8978|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
reconcile-ff-only-sentry-4977|SENTRY_ACTIONS_RO_TOKEN|sentry\.io|1|sentry_empty
autovacuum-thrash-6168|SUPABASE_ACCESS_TOKEN|api\.supabase\.com|1|autovac
concurrency-slot-wal-backoff|SUPABASE_ACCESS_TOKEN|api\.supabase\.com|1|slots
l3-probe-armed-6438|BETTERSTACK_API_TOKEN|uptime\.betterstack\.com|1|bs_up
web2-standby-soak-6459|BETTERSTACK_API_TOKEN|uptime\.betterstack\.com|1|bs_up'

# STATIC-ONLY: name | kind | argument | justification. Each carries a row that goes RED when
# the probe becomes hermetically reachable (so it must move to the dynamic manifest).
#   placeholder  runs under the shim and must make ZERO calls (RED the day the placeholder is pinned)
#   fixed-tmp    must still name the fixed path (RED the day the fixed /tmp write is gone)
#   gh-chained   must still call gh issue/pr/api (the second curl is only reachable through a gh model)
#   bs-chained   must still chain into the named script (a second credentialed tool)
STATIC_MANIFEST='phase3-ga-soak-5274|placeholder|<POST_CUTOVER_UTC>|exits TRANSIENT on the literal START placeholder before any curl; a hermetic run can never reach its credentialed call
sentry-checkins-3859|fixed-tmp|/tmp/ck.json|writes the fixed path /tmp/ck.json, which a hermetic row must not touch
sync-health-residual-5689|fixed-tmp|/tmp/sh5689.json|writes the fixed path /tmp/sh5689.json, which a hermetic row must not touch
cron-machinery-soak-9272|gh-chained|gh|its second and third credentialed curls (-D header file, paging) are reachable only through a gh issue/pr/api model; the fail-closed gh stub makes it exit TRANSIENT after the first call
zot-soak-6122|gh-chained|gh|its credentialed curl sits behind START-anchor and blocker arms that call gh pr/issue view; unreachable under a fail-closed gh stub
workspaces-luks-soak-6604|bs-chained|betterstack-query.sh|after the Sentry call it chains into betterstack-query.sh, a second credentialed tool with basic auth that this shim does not model'

# DELEGATED: name | owning test (extended in place by the conversion; not re-modelled here).
DELEGATED_MANIFEST='anthropic-admin-key-6297|scripts/followthroughs/anthropic-admin-key-6297.test.sh
cwv-field-rum-9178|scripts/followthroughs/cwv-field-rum-9178.test.sh
send-failed-alert-probe-8097|scripts/followthroughs/send-failed-alert-probe-8097.test.sh
betterstack-roundtrip-latency-7855|tests/scripts/test-betterstack-roundtrip-latency.sh'

# --- the DERIVED population: tracked followthrough probes holding a credentialed curl ---------
derive_population() {
  local f
  git ls-files 'scripts/followthroughs/*.sh' | while IFS= read -r f; do
    case "$f" in *.test.sh) continue ;; esac
    [[ -f "$f" ]] || continue
    if grep -qE -e 'Authorization: *Bearer' -e '--config -' -e '-K -' "$f"; then basename "$f" .sh; fi
  done | sort -u
}
POP="$(derive_population)"
CLASSIFIED="$({ printf '%s\n' "$DYN_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$STATIC_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$DELEGATED_MANIFEST" | cut -d'|' -f1; } | sort)"
DUP="$(printf '%s\n' "$CLASSIFIED" | uniq -d)"
UNCLASSIFIED="$(comm -23 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
STALE_ENTRY="$(comm -13 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
if [[ -n "$POP" && -z "$DUP" && -z "$UNCLASSIFIED" && -z "$STALE_ENTRY" ]]; then
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" ok
else
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" fail "unclassified='${UNCLASSIFIED//$'\n'/,}' stale='${STALE_ENTRY//$'\n'/,}' duplicated='${DUP//$'\n'/,}' derived=$(printf '%s\n' "$POP" | grep -c . || true)"
fi
# Baseline E may list followthrough probes ONLY for the S2-owned set (they still carry a credential
# header outside the Bearer vocabulary and are converted in S2); every other followthrough is converted,
# so a listed one is an argv bearer that crept back. The row asserts the listed set EQUALS the S2 list
# (a shrink in S2 updates this list in the same diff), and a floor row keeps it from being vacuous.
S2_OWNED="canary-promotion-5875
infra-config-activation-7220
infra-config-fatal-channel-7220
inngest-soak-6178"
BE_FOLLOWTHROUGH="$(awk -F'\t' '!/^#/ && $1 ~ /^scripts\/followthroughs\// {print $1}' "$BASE_E" | sed 's|^scripts/followthroughs/||; s|\.sh$||' | sort -u)"
if [[ "$BE_FOLLOWTHROUGH" == "$S2_OWNED" ]]; then row "population: the followthrough probes listed in baseline E equal the S2-owned list" ok
else row "population: the followthrough probes listed in baseline E equal the S2-owned list" fail "listed='${BE_FOLLOWTHROUGH//$'\n'/,}' want='${S2_OWNED//$'\n'/,}'"; fi
BE_FT_N="$(printf '%s\n' "$BE_FOLLOWTHROUGH" | grep -c . || true)"
if [[ "$BE_FT_N" -lt 4 ]]; then row "population: anti-vacuity floor, baseline E lists at least the 4 S2-owned followthroughs" fail "anti-vacuity floor: only $BE_FT_N listed"
else row "population: anti-vacuity floor, baseline E lists at least the 4 S2-owned followthroughs" ok; fi

# --- DYNAMIC rows ----------------------------------------------------------------------------
N_DYN=0
probe_rows() { # name tokvar hosts min body
  local name="$1" tokvar="$2" hosts="$3" min="$4" body="$5"
  local rel="scripts/followthroughs/$name.sh" script="$REPO_ROOT/scripts/followthroughs/$name.sh" rc
  N_DYN=$((N_DYN + 1))
  if [[ ! -f "$script" ]]; then row "$name: manifest entry names an existing probe" fail "$rel is missing"; return 0; fi
  local -a okenv=("$tokvar=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/$body.json")

  # A. the full contract
  run_probe "$name-A" "$script" "${okenv[@]}"
  rc=$RUN_RC; evaluate "$RUN_ROW" "$hosts" "$min" "$FIXTURE_TOKEN"
  local outcome_ok=0; [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout" && outcome_ok=1
  if [[ "$outcome_ok" -eq 1 && -z "$EV_FAILED" ]]; then
    row "$name: full contract (every call to the manifest hosts has the bearer on stdin, token in no argv, >= $min call(s))" ok
  else row "$name: full contract (every call to the manifest hosts has the bearer on stdin, token in no argv, >= $min call(s))" fail "rc=$rc calls=$EV_HOST_CALLS failed='$EV_FAILED'"; fi

  # B. a 401 must never reach the PASS outcome
  run_probe "$name-B" "$script" "${okenv[@]}" SHIM_MODE=deny
  if transient_outcome "$RUN_ROW" "$RUN_RC" && [[ ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]]; then
    row "$name: a 401 never reaches PASS (rc 2, TRANSIENT on stderr)" ok
  else row "$name: a 401 never reaches PASS (rc 2, TRANSIENT on stderr)" fail "rc=$RUN_RC"; fi

  # C. header stripped by a mutated COPY of the real probe
  local cdir="$ROWS/$name-C-copy"; assert_fixture_dir "$cdir"; mkdir -p "$cdir"
  sed 's/Authorization: Bearer/X-Stripped: Bearer/g' "$script" > "$cdir/$name.sh"
  if ! grep -q 'X-Stripped' "$cdir/$name.sh"; then row "$name: header-stripped copy" fail "the sed did not land; the probe has no 'Authorization: Bearer' text"
  else
    run_probe "$name-C" "$cdir/$name.sh" "${okenv[@]}"
    if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "$name: a header-stripped copy never reaches PASS (rc 2, TRANSIENT on stderr)" ok
    else row "$name: a header-stripped copy never reaches PASS (rc 2, TRANSIENT on stderr)" fail "rc=$RUN_RC"; fi
  fi

  # D. unset and empty token: zero calls, TRANSIENT rc 2
  local cls d_ok=1 d_detail=""
  for cls in unset empty; do
    shape_check "$script" "$tokvar" "$cls" "$name-D-$cls" "SHIM_BODY_FILE=$BODIES/$body.json" || { d_ok=0; d_detail+=" [$cls: $SHAPE_DETAIL]"; }
  done
  if [[ "$d_ok" -eq 1 ]]; then row "$name: an unset or empty token produces zero calls and a TRANSIENT rc 2" ok
  else row "$name: an unset or empty token produces zero calls and a TRANSIENT rc 2" fail "$d_detail"; fi

  # CONVERTED-ONLY rows: they assert properties a conversion adds, so they switch on when the
  # probe leaves baseline E (rows only grow; EXPECTED_TESTS is a lower bound).

  # E1. hostile token shapes
  local e_ok=1 e_detail=""
  for cls in quote-newline-url newline-only non-ascii quote space; do
    shape_check "$script" "$tokvar" "$cls" "$name-E1-$cls" "SHIM_BODY_FILE=$BODIES/$body.json" || { e_ok=0; e_detail+=" [$cls: $SHAPE_DETAIL]"; }
  done
  if [[ "$e_ok" -eq 1 ]]; then row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" ok
  else row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" fail "$e_detail"; fi
  # E2/E3. xtrace refusal
  for mode in env flag; do
    if xtrace_check "$script" "$tokvar" "$name-E-xtrace-$mode" "$mode"; then row "$name: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
    else row "$name: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
  done
  # E4. 100,000-byte token, never-reading shim, pipefail: a converted probe is unaffected
  run_probe "$name-E4" "$script" "$tokvar=$BIGTOK" "SHIM_BODY_FILE=$BODIES/$body.json" SHIM_MODE=noread
  # A 64-byte PREFIX stands in for the 100 KB token in the greps: `grep -F` with a 100,000-byte
  # pattern is pathologically slow (measured: minutes), and the token being in argv implies its
  # prefix is.
  rc=$RUN_RC; evaluate "$RUN_ROW" "$hosts" 0 "${BIGTOK:0:64}"
  if [[ "$rc" -eq 0 ]] && grep -q '^PASS' "$RUN_ROW/stdout" && ! has_check token-in-argv; then
    row "$name: a 100,000-byte token with a never-reading shim under pipefail: rc 0 (no pipe-form SIGPIPE), token in no argv" ok
  else row "$name: a 100,000-byte token with a never-reading shim under pipefail: rc 0 (no pipe-form SIGPIPE), token in no argv" fail "rc=$rc failed='$EV_FAILED'"; fi
  # E5/E6. harness mutations against the real converted probe: RED for every row
  run_probe "$name-E5" "$script" "${okenv[@]}" SHIM_MUTATE=nostdin
  evaluate "$RUN_ROW" "$hosts" "$min" "$FIXTURE_TOKEN"
  if has_check bearer-not-on-stdin; then row "$name: a shim that stops recording stdin turns this row RED" ok
  else row "$name: a shim that stops recording stdin turns this row RED" fail "failed='$EV_FAILED'"; fi
  run_probe "$name-E6" "$cdir/$name.sh" "${okenv[@]}" SHIM_MUTATE=noauth
  if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "$name: a shim that stops being auth-gated lets the stripped copy reach PASS, and the check sees it" fail "stripped copy still TRANSIENT"
  else row "$name: a shim that stops being auth-gated lets the stripped copy reach PASS, and the check sees it" ok; fi
}
while IFS='|' read -r m_name m_tokvar m_hosts m_min m_body; do
  [[ -n "$m_name" ]] || continue
  probe_rows "$m_name" "$m_tokvar" "$m_hosts" "$m_min" "$m_body"
done <<< "$DYN_MANIFEST"

# --- STATIC-ONLY rows -----------------------------------------------------------------------
N_STATIC=0
while IFS='|' read -r s_name s_kind s_arg s_why; do
  [[ -n "$s_name" ]] || continue
  N_STATIC=$((N_STATIC + 1))
  s_script="$REPO_ROOT/scripts/followthroughs/$s_name.sh"
  if [[ ! -f "$s_script" ]]; then row "static-only $s_name: names an existing probe" fail "missing"; continue; fi
  case "$s_kind" in
    placeholder)
      run_probe "$s_name-S" "$s_script" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN"
      count_calls "$RUN_ROW"
      if grep -qF -- "$s_arg" "$s_script" && [[ "$EV_CALLS" -eq 0 && "$RUN_RC" -eq 2 ]]; then
        row "static-only $s_name: still unreachable (placeholder $s_arg, rc 2, zero calls) -- $s_why" ok
      else row "static-only $s_name: still unreachable (placeholder $s_arg, rc 2, zero calls)" fail "rc=$RUN_RC calls=$EV_CALLS: the probe is now hermetically reachable; move it to the dynamic manifest" ; fi ;;
    fixed-tmp)
      if grep -qF -- "$s_arg" "$s_script"; then row "static-only $s_name: still writes the fixed path $s_arg -- $s_why" ok
      else row "static-only $s_name: still writes the fixed path $s_arg" fail "the fixed path is gone: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    gh-chained)
      # `grep -q` over a PROCESS SUBSTITUTION, not a pipe: under pipefail the early-exiting -q
      # SIGPIPEs the upstream grep on a large file and reads as "no match" (measured on zot-soak).
      if grep -qE '(^|[^[:alnum:]_-])gh (issue|pr|api)' < <(grep -vE '^[[:space:]]*#' "$s_script"); then row "static-only $s_name: still chained behind gh -- $s_why" ok
      else row "static-only $s_name: still chained behind gh" fail "no gh issue/pr/api call remains: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    bs-chained)
      if grep -qF -- "$s_arg" < <(grep -vE '^[[:space:]]*#' "$s_script"); then row "static-only $s_name: still chained into $s_arg -- $s_why" ok
      else row "static-only $s_name: still chained into $s_arg" fail "the chain is gone: the probe is now hermetically reachable; move it to the dynamic manifest"; fi ;;
    *) row "static-only $s_name: known kind" fail "unknown kind '$s_kind'" ;;
  esac
done <<< "$STATIC_MANIFEST"

# --- DELEGATED rows -------------------------------------------------------------------------
N_DELEGATED=0
while IFS='|' read -r d_name d_test; do
  [[ -n "$d_name" ]] || continue
  N_DELEGATED=$((N_DELEGATED + 1))
  if [[ -f "$d_test" ]] && git ls-files --error-unmatch -- "$d_test" >/dev/null 2>&1 && grep -qF -- "$d_name" "$d_test"; then
    row "delegated $d_name: owning test $d_test exists, is tracked and names the probe" ok
  else row "delegated $d_name: owning test $d_test exists, is tracked and names the probe" fail "the owning test is missing, untracked or no longer names the probe"; fi
done <<< "$DELEGATED_MANIFEST"

echo "=== manifest: $N_DYN dynamic, $N_STATIC static-only, $N_DELEGATED delegated; population $(printf '%s\n' "$POP" | grep -c . || true) ==="

# =====================================================================================
# STAGE 3: THE LIVE-IN-APPLY INFRA SCRIPTS (#9597). Two scripts run by the push-triggered
# infra apply carried a bearer on curl's argv; the changed transport is proven HERE, before
# merge, by running each under the PATH-shim curl:
#   fresh-host-boot-trail.sh   two Sentry reads (org events query + polled project read)
#   verify-tunnel-ingress-origin.sh  two calls: the Cloudflare config read (Bearer) and the
#                              deploy-status read (webhook HMAC + CF Access id/secret headers)
# A failure of the second blocks the apply, so its refusal path is exercised too.
# =====================================================================================
INFRA_SCRIPTS="$REPO_ROOT/apps/web-platform/infra/scripts"
FHBT="$INFRA_SCRIPTS/fresh-host-boot-trail.sh"
VTIO="$INFRA_SCRIPTS/verify-tunnel-ingress-origin.sh"
[[ -f "$FHBT" && -f "$VTIO" ]] || fatal "stage 3: the live-in-apply scripts are missing ($FHBT, $VTIO)"
printf '%s' '[]' > "$BODIES/empty_array.json"
printf '%s' '{"data":[{"timestamp":"2026-10-01T00:00:00+00:00","stage":"app_zot","host_name":"soleur-web-9","detail":"synthetic"}]}' > "$BODIES/origin_event.json"
printf '%s' '{"success":true,"result":{"config":{"ingress":[{"hostname":"deploy.soleur.example","service":"http://10.0.1.10:9000"},{"hostname":"ssh.soleur.example","service":"ssh://10.0.1.10:22"},{"service":"http_status:404"}]}}}' > "$BODIES/cf_tunnel_cfg.json"

# mutated_copy <script> <outfile> <from-literal> <to-literal>: a copy with ONE literal replaced;
# FATAL if the literal is absent (a mutation that does not land reports the baseline, which is
# indistinguishable from a pass).
mutated_copy() {
  local src="$1" out="$2" from="$3" to="$4" text
  text="$(cat "$src"; printf x)"; text="${text%x}"
  [[ "$text" == *"$from"* ]] || fatal "mutation did not land: '${from:0:60}...' not found in $src"
  assert_fixture_dir "$out"
  printf '%s' "${text/"$from"/"$to"}" > "$out"
}
assert_fixture_dir "$SYN"
BEARER_FN='_bearer_ok() { local LC_ALL=C; case "${1:-}" in '"''"'|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }'

# --- fresh-host-boot-trail.sh ------------------------------------------------------------------
trail_env() { # <rowname> -> prints NAME=value args for run_probe (summary file lives in the row dir)
  printf '%s\n' "GITHUB_STEP_SUMMARY=$ROWS/$1/summary" "WEB_HOST_KEY=web-9" "JOB_STATUS=failure" "BOOT_TRAIL_SINCE=0" "SHIM_BODY_FILE=$BODIES/empty_array.json"
}
mkdir -p "$ROWS/t1-origin" "$ROWS/t2-main"
RUN_ARGS=(--image-origin web-9)
run_probe t1-origin "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/origin_event.json" "BOOT_TRAIL_SINCE=0"
RUN_ARGS=()
rc=$RUN_RC; evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -qF 'image-origin: stage=app_zot' "$RUN_ROW/stdout"; then
  row "fresh-host-boot-trail --image-origin: both Sentry org reads carry the bearer on stdin only (>= 2 calls), token in no argv" ok
else row "fresh-host-boot-trail --image-origin: both Sentry org reads carry the bearer on stdin only (>= 2 calls), token in no argv" fail "rc=$rc failed='$EV_FAILED'"; fi

mapfile -t _t2env < <(trail_env t2-main)
run_probe t2-main "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_t2env[@]}"
rc=$RUN_RC; evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]]; then
  row "fresh-host-boot-trail main flow: the polled project read AND the image-origin read carry the bearer on stdin only (>= 2 calls)" ok
else row "fresh-host-boot-trail main flow: the polled project read AND the image-origin read carry the bearer on stdin only (>= 2 calls)" fail "rc=$rc failed='$EV_FAILED'"; fi
if ! grep -qF '/tmp/sentry-events.json' "$FHBT"; then row "fresh-host-boot-trail: no fixed /tmp/sentry-events.json path remains (script-owned mktemp)" ok
else row "fresh-host-boot-trail: no fixed /tmp/sentry-events.json path remains (script-owned mktemp)" fail "the fixed path is back"; fi

# hostile token classes: zero calls, the skip is NAMED, the token is never echoed.
ft_ok=1; ft_detail=""
for cls in quote-newline-url newline-only non-ascii quote space; do
  mkdir -p "$ROWS/t3-main-$cls" "$ROWS/t3-origin-$cls"
  mapfile -t _e < <(trail_env "t3-main-$cls"); _e=("${_e[@]/JOB_STATUS=failure/JOB_STATUS=success}")
  run_probe "t3-main-$cls" "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for "$cls")" "${_e[@]}"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 0 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'failed the token-shape check' "$RUN_ROW/stdout" && ! grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr" "$RUN_ROW/summary"; } \
    || { ft_ok=0; ft_detail+=" [main/$cls rc=$RUN_RC calls=$EV_CALLS]"; }
  mapfile -t _e < <(trail_env "t3-origin-$cls")
  RUN_ARGS=(--image-origin web-9)
  run_probe "t3-origin-$cls" "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for "$cls")" "${_e[@]}"
  RUN_ARGS=()
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 2 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'TRANSIENT' "$RUN_ROW/stdout" && ! grep -aq 'SYNTHMARK000' "$RUN_ROW/stdout" "$RUN_ROW/stderr"; } \
    || { ft_ok=0; ft_detail+=" [origin/$cls rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$ft_ok" -eq 1 ]]; then row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" ok
else row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" fail "$ft_detail"; fi
for mode in env flag; do
  if xtrace_check "$FHBT" SENTRY_ACTIONS_RO_TOKEN "t4-$mode" "$mode"; then row "fresh-host-boot-trail: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "fresh-host-boot-trail: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
done
# harness + code mutations against the real script
mapfile -t _e < <(trail_env t5-nostdin)
run_probe t5-nostdin "$FHBT" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_e[@]}" SHIM_MUTATE=nostdin
evaluate "$RUN_ROW" 'de\.sentry\.io' 2 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "fresh-host-boot-trail: a shim that stops recording stdin turns the row RED" ok
else row "fresh-host-boot-trail: a shim that stops recording stdin turns the row RED" fail "failed='$EV_FAILED'"; fi
FROM_PS='< <(printf '"'"'header = "Authorization: Bearer %s"\n'"'"' "$SENTRY_ACTIONS_RO_TOKEN")'
mutated_copy "$FHBT" "$SYN/fhbt-argv.sh" "$FROM_PS" '-H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN"'
mapfile -t _e < <(trail_env t6-argv)
run_probe t6-argv "$SYN/fhbt-argv.sh" "SENTRY_ACTIONS_RO_TOKEN=$FIXTURE_TOKEN" "${_e[@]}"
evaluate "$RUN_ROW" 'de\.sentry\.io' 1 "$FIXTURE_TOKEN"
if has_check token-in-argv; then row "fresh-host-boot-trail: restoring the argv bearer on either read is RED on token-in-argv" ok
else row "fresh-host-boot-trail: restoring the argv bearer on either read is RED on token-in-argv" fail "failed='$EV_FAILED'"; fi
mutated_copy "$FHBT" "$SYN/fhbt-noguard.sh" "$BEARER_FN" '_bearer_ok() { return 0; }'
mapfile -t _e < <(trail_env t7-noguard)
run_probe t7-noguard "$SYN/fhbt-noguard.sh" "SENTRY_ACTIONS_RO_TOKEN=$(tok_for quote-newline-url)" "${_e[@]}"
evaluate "$RUN_ROW" 'de\.sentry\.io' 1 "SYNTHMARK0001"
if has_check injected; then row "fresh-host-boot-trail: removing the token-shape guard is RED on injected (the shim records the injected config line)" ok
else row "fresh-host-boot-trail: removing the token-shape guard is RED on injected (the shim records the injected config line)" fail "failed='$EV_FAILED'"; fi

# --- verify-tunnel-ingress-origin.sh ----------------------------------------------------------
VT_STUBS="$TMPD/vt-stubs"; assert_fixture_dir "$VT_STUBS"; mkdir -p "$VT_STUBS"
cat > "$VT_STUBS/doppler" <<'VT_DOPPLER'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  run) printf '"10.0.1.10"\n' ;;
  secrets)
    case "${3:-}" in
      CF_API_TOKEN) printf '%s' "${VT_CF_API_TOKEN:-}" ;;
      CF_ACCOUNT_ID) printf 'acct0001' ;;
      APP_DOMAIN_BASE) printf 'soleur.example' ;;
      WEBHOOK_DEPLOY_SECRET) printf 'webhook-secret-0001' ;;
      CF_ACCESS_CLIENT_ID) printf '%s' "${VT_CF_ACCESS_ID:-cfid0001}" ;;
      CF_ACCESS_CLIENT_SECRET) printf '%s' "${VT_CF_ACCESS_SECRET:-cfsecret0001}" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
VT_DOPPLER
cat > "$VT_STUBS/terraform" <<'VT_TERRAFORM'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "state show") printf '    id = "11111111-2222-3333-4444-555555555555"\n' ;;
  *) exit 1 ;;
esac
VT_TERRAFORM
sed -i "1s|.*|#!${BASH_BIN}|" "$VT_STUBS/doppler" "$VT_STUBS/terraform"
chmod +x "$VT_STUBS/doppler" "$VT_STUBS/terraform"
vt_run() { # <rowname> <script> [env...] -- runs under the stub set; CF token defaults to the fixture
  local name="$1" script="$2"; shift 2
  RUN_EXTRA_PATH="$VT_STUBS"
  run_probe "$name" "$script" "VT_CF_API_TOKEN=$FIXTURE_TOKEN" "SHIM_BODY_FILE=$BODIES/cf_tunnel_cfg.json" SHIM_MODE=noauth "$@"
  RUN_EXTRA_PATH=""
}
vt_stdin() { cat "$ROWS/$1/shim/calls/$2.stdin" 2>/dev/null; }
# The script echoes `::add-mask::<secret>` on purpose (that is how the runner learns to mask it), so
# "never echoed" means: not on stderr, and not on any ::error:: / ::warning:: annotation line.
vt_leaks() { # <rowdir> <marker> -> 0 when the marker leaks outside ::add-mask::
  local ann; ann="$(grep -aE '^::(error|warning|notice)::' "$1/stdout" "$1/stderr" || true)"
  [[ "$ann" == *"$2"* ]] || grep -aqF -- "$2" "$1/stderr"
}
vt_argv_has() { local f; for f in "$ROWS/$1"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$2" "$f" && return 0; done; return 1; }

vt_run v1-ok "$VTIO"
v_rc=$RUN_RC; count_calls "$RUN_ROW"
v_hmac="$(printf '' | openssl dgst -sha256 -hmac webhook-secret-0001 | sed 's/.*= //')"
v_s1="$(vt_stdin v1-ok 1)"; v_s2="$(vt_stdin v1-ok 2)"
v_want2="$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: cfid0001"\nheader = "CF-Access-Client-Secret: cfsecret0001"' "$v_hmac")"
v_bad=""
[[ "$v_rc" -eq 0 && "$EV_CALLS" -eq 2 ]] || v_bad+=" rc=$v_rc calls=$EV_CALLS"
[[ "$v_s1" == "header = \"Authorization: Bearer $FIXTURE_TOKEN\"" ]] || v_bad+=" call1-stdin"
[[ "$v_s2" == "$v_want2" ]] || v_bad+=" call2-stdin"
for needle in "$FIXTURE_TOKEN" cfid0001 cfsecret0001 "$v_hmac" webhook-secret-0001; do vt_argv_has v1-ok "$needle" && v_bad+=" argv-has-credential"; done
for f in "$ROWS"/v1-ok/shim/calls/*.injected; do [[ -s "$f" ]] && v_bad+=" injected"; done
[[ ! -e "$ROWS/v1-ok/shim/unexpected" && ! -e "$ROWS/v1-ok/shim/unmodelled" ]] || v_bad+=" stub-called"
if [[ -z "$v_bad" ]]; then row "verify-tunnel-ingress-origin: the Cloudflare read carries the bearer on stdin; the deploy-status read carries the HMAC + CF Access id + CF Access secret as three stdin headers in order; no credential in any argv" ok
else row "verify-tunnel-ingress-origin: the Cloudflare read carries the bearer on stdin; the deploy-status read carries the HMAC + CF Access id + CF Access secret as three stdin headers in order; no credential in any argv" fail "$v_bad"; fi

# unusable CF API token: gate failure (exit 1), zero calls, token never echoed
vt_ok=1; vt_detail=""
for cls in quote-newline-url newline-only non-ascii quote space; do
  vt_run "v2-$cls" "$VTIO" "VT_CF_API_TOKEN=$(tok_for "$cls")"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 1 && "$EV_CALLS" -eq 0 ]] && grep -aqF 'CF_API_TOKEN failed the token-shape check' "$RUN_ROW/stdout" "$RUN_ROW/stderr" && ! vt_leaks "$RUN_ROW" 'SYNTHMARK000'; } \
    || { vt_ok=0; vt_detail+=" [$cls rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$vt_ok" -eq 1 ]]; then row "verify-tunnel-ingress-origin: a malformed CF API token is a gate failure (exit 1) with zero calls and is never echoed" ok
else row "verify-tunnel-ingress-origin: a malformed CF API token is a gate failure (exit 1) with zero calls and is never echoed" fail "$vt_detail"; fi
# unusable CF Access secret: the config read may run, the deploy-status call must NOT, and it is a gate failure
vt_ok=1; vt_detail=""
v3_i=0
for sec in 'SYNTHMARK0001"x' $'SYNTHMARK0001\nheader = "X-Injected: 1"' 'SYNTHMARK0001\x'; do
  v3_i=$((v3_i + 1))
  vt_run "v3-secret-$v3_i" "$VTIO" "VT_CF_ACCESS_SECRET=$sec"
  count_calls "$RUN_ROW"
  { [[ "$RUN_RC" -eq 1 && "$EV_CALLS" -eq 1 ]] && grep -aqF 'header-value check' "$RUN_ROW/stdout" "$RUN_ROW/stderr" && ! vt_leaks "$RUN_ROW" 'SYNTHMARK000'; } \
    || { vt_ok=0; vt_detail+=" [rc=$RUN_RC calls=$EV_CALLS]"; }
done
if [[ "$vt_ok" -eq 1 ]]; then row "verify-tunnel-ingress-origin: a CF Access secret carrying a quote, backslash or injected newline stops BEFORE the deploy-status call (exit 1) and is never echoed" ok
else row "verify-tunnel-ingress-origin: a CF Access secret carrying a quote, backslash or injected newline stops BEFORE the deploy-status call (exit 1) and is never echoed" fail "$vt_detail"; fi
for mode in env flag; do
  RUN_EXTRA_PATH="$VT_STUBS"
  if xtrace_check "$VTIO" CF_API_TOKEN "v4-$mode" "$mode"; then row "verify-tunnel-ingress-origin: refuses xtrace ($mode form): rc 78, zero calls, no token on output" ok
  else row "verify-tunnel-ingress-origin: refuses xtrace ($mode form): rc 78, zero calls, no token on output" fail "$XT_DETAIL"; fi
  RUN_EXTRA_PATH=""
done
# mutations: argv restored on the second call; guards removed
mutated_copy "$VTIO" "$SYN/vtio-argv.sh" '< <(printf '"'"'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n'"'"' \
          "$HMAC" "$CF_ACCESS_ID" "$CF_ACCESS_SECRET")' '-H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}"'
vt_run v5-argv "$SYN/vtio-argv.sh"
if vt_argv_has v5-argv cfsecret0001; then row "verify-tunnel-ingress-origin: restoring a CF Access header on argv is RED (the credential shows in a recorded argv)" ok
else row "verify-tunnel-ingress-origin: restoring a CF Access header on argv is RED (the credential shows in a recorded argv)" fail "the mutant's credential did not reach argv"; fi
mutated_copy "$VTIO" "$SYN/vtio-noguard.sh" '_cfg_ok() { local LC_ALL=C; case "${1:-}" in '"''"'|*'"'"'"'"'"'*|*'"'"'\'"'"'*|*[[:cntrl:]]*) return 1 ;; esac; }' '_cfg_ok() { return 0; }'
vt_run v6-noguard "$SYN/vtio-noguard.sh" 'VT_CF_ACCESS_SECRET=SYNTHMARK0001"x'
v6_inj=0; for f in "$ROWS"/v6-noguard/shim/calls/*.injected; do [[ -s "$f" ]] && v6_inj=1; done
if [[ "$v6_inj" -eq 1 ]]; then row "verify-tunnel-ingress-origin: removing the header-value guard is RED (the shim records the injected config line)" ok
else row "verify-tunnel-ingress-origin: removing the header-value guard is RED (the shim records the injected config line)" fail "no INJECTED recorded for the unguarded mutant"; fi
echo "=== stage 3: fresh-host-boot-trail + verify-tunnel-ingress-origin transport rows done ==="

# =====================================================================================
# STAGE 4: SHIM EXTENSIONS for the community-script conversions (#9597, S1 Phase 2). Each
# extension is proven on SYNTHETIC probes first, so a shim that accepts too much cannot make
# the later per-script rows (plugins/soleur/skills/community/test/community-argv.test.sh)
# vacuous:
#   (a) the shim and `evaluate` are parameterised by auth SCHEME (Discord sends `Bot`, and
#       rejects `Bearer`): a Bot-to-Bearer mutation must go RED;
#   (b) the shim records a `--data-binary @-` stdin body, models `-d @-` stripping CR/LF as real
#       curl does, and has a `fail7` transport-failure mode, calibrated against real curl;
#   (c) a `jq` shim records jq's argv (jq's own argv is world-readable too);
#   (d) static rows over the converted sources and docs.
# =====================================================================================
# C4: the real-curl oracle for the body semantics and the transport-failure exit code.
CR_FILE="$ORA/crlf.txt"
printf 'SYNTHA\r\nSYNTHB\n' > "$CR_FILE"
"$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/bin.c" --data-binary @- http://127.0.0.1:9/ < "$CR_FILE" >/dev/null 2>&1; REAL_RC7=$?
"$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$ORA/d.c" -d @- http://127.0.0.1:9/ < "$CR_FILE" >/dev/null 2>&1 || true
[[ -s "$ORA/bin.c" && -s "$ORA/d.c" ]] || fatal "C4 real curl did not write --libcurl output for a stdin body"
grep -qF 'SYNTHA\r\nSYNTHB\n' "$ORA/bin.c" || fatal "C4 oracle: --data-binary @- did not keep CR/LF"
grep -qF 'SYNTHASYNTHB' "$ORA/d.c" || fatal "C4 oracle: -d @- did not strip CR/LF"
[[ "$REAL_RC7" -eq 7 ]] || fatal "C4 oracle: real curl against a refused connection exited $REAL_RC7, the shim's fail7 models 7"
row "control C4: real curl keeps CR/LF for --data-binary @-, strips them for -d @-, and exits 7 on a refused connection" ok

# (a) scheme rows ----------------------------------------------------------------------
P_BOT="$(make_synth bot)"
run_probe s1-bot "$P_BOT" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_SCHEME=Bot
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN" Bot
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout" \
   && grep -qxF -- "header = \"Authorization: Bot $FIXTURE_TOKEN\"" "$RUN_ROW/shim/calls/1.stdin"; then
  row "scheme: a Bot probe sends exactly the line header = \"Authorization: Bot <tok>\" on stdin and is GREEN under the Bot-aware shim" ok
else row "scheme: a Bot probe sends exactly the line header = \"Authorization: Bot <tok>\" on stdin and is GREEN under the Bot-aware shim" fail "rc=$rc failed='$EV_FAILED'"; fi
P_BOT_AS_BEARER="$SYN/synth-bot-as-bearer.sh"; sed 's/Authorization: Bot /Authorization: Bearer /' "$P_BOT" > "$P_BOT_AS_BEARER"
grep -q 'Authorization: Bearer' "$P_BOT_AS_BEARER" || fatal "scheme mutation did not land"
run_probe s2-bearer "$P_BOT_AS_BEARER" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_SCHEME=Bot
rc=$RUN_RC; evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN" Bot
if has_check bearer-not-on-stdin && transient_outcome "$RUN_ROW" "$rc"; then
  row "scheme: swapping Bot for Bearer is RED (the exact-line check fires, and the Bot-aware shim answers 401, never PASS)" ok
else row "scheme: swapping Bot for Bearer is RED (the exact-line check fires, and the Bot-aware shim answers 401, never PASS)" fail "rc=$rc failed='$EV_FAILED'"; fi
evaluate "$ROWS/s1-bot" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "scheme: evaluating the Bot probe as a Bearer probe is RED (the default scheme did not loosen)" ok
else row "scheme: evaluating the Bot probe as a Bearer probe is RED (the default scheme did not loosen)" fail "failed='$EV_FAILED'"; fi
run_probe s3-bot-default-shim "$P_BOT" "SYNTH_TOKEN=$FIXTURE_TOKEN"
if transient_outcome "$RUN_ROW" "$RUN_RC"; then row "scheme: a default (Bearer) shim rejects a Bot probe with 401, TRANSIENT (the auth gate is scheme-aware)" ok
else row "scheme: a default (Bearer) shim rejects a Bot probe with 401, TRANSIENT (the auth gate is scheme-aware)" fail "rc=$RUN_RC"; fi

# (b)+(c) stdin-body rows ----------------------------------------------------------------
make_body_probe() { # <variant: stdin|dstdin|argv|jqarg> -> path
  local v="$1" p="$SYN/synth-body-$1.sh"
  {
    cat <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${SYNTH_PW:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SYNTH_PW).\n' >&2
      exit 78
    fi
    ;;
esac
EOF
    # The body is built by jq and piped to curl's STDIN: no file, no trap. The values reach jq only
    # through its environment (an inline assignment prefix), never `jq --arg` and never `export`.
    case "$1" in
      stdin) printf '%s\n' "RESP=\$(SYNTH_ID_E=\"\$SYNTH_ID\" SYNTH_PW_E=\"\$SYNTH_PW\" jq -n '{identifier:\$ENV.SYNTH_ID_E,password:\$ENV.SYNTH_PW_E}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- '$SYN_URL')" ;;
      jqarg) printf '%s\n' "RESP=\$(jq -n --arg id \"\$SYNTH_ID\" --arg pw \"\$SYNTH_PW\" '{identifier:\$id,password:\$pw}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- '$SYN_URL')" ;;
      dstdin) printf '%s\n' "RESP=\$(SYNTH_ID_E=\"\$SYNTH_ID\" SYNTH_PW_E=\"\$SYNTH_PW\" jq -n '{identifier:\$ENV.SYNTH_ID_E,password:\$ENV.SYNTH_PW_E}' | curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' -d @- '$SYN_URL')" ;;
      argv) printf '%s\n' "RESP=\$(curl --disable --noproxy '*' -sS -w '\\nHTTP_STATUS:%{http_code}' -X POST -H 'Content-Type: application/json' -d \"{\\\"identifier\\\":\\\"\$SYNTH_ID\\\",\\\"password\\\":\\\"\$SYNTH_PW\\\"}\" '$SYN_URL')" ;;
    esac
    synth_tail
  } > "$p"
  printf '%s\n' "$p"
}
BODY_PW="SYNTHPW""-aaaa-bbbb-cccc"
BODY_ID="synthetic.bsky.social"
evaluate_body() { # <rowdir> -> EV_FAILED names: pw-in-argv, pw-in-jq-argv, body-not-recorded, body-content, no-calls
  local row="$1" f c
  EV_FAILED=""; count_calls "$row"
  [[ "$EV_CALLS" -ge 1 ]] || EV_FAILED+=" no-calls"
  for f in "$row"/shim/calls/*.argv; do
    [[ -e "$f" ]] || continue
    c="${f%.argv}"
    grep -aqF -- "$BODY_PW" "$f" && EV_FAILED+=" pw-in-argv"
    [[ -s "$c.body" ]] || EV_FAILED+=" body-not-recorded"
    jq -e --arg i "$BODY_ID" --arg p "$BODY_PW" '.identifier == $i and .password == $p' "$c.body" >/dev/null 2>&1 || EV_FAILED+=" body-content"
  done
  for f in "$row"/shim/jq/*.argv; do
    [[ -e "$f" ]] || continue
    grep -aqF -- "$BODY_PW" "$f" && EV_FAILED+=" pw-in-jq-argv"
  done
  EV_FAILED="$(printf '%s\n' $EV_FAILED | awk '!s[$0]++' | paste -sd' ' -)"
  return 0
}
body_env=("SYNTH_PW=$BODY_PW" "SYNTH_ID=$BODY_ID" SHIM_MODE=noauth)

P_BF="$(make_body_probe stdin)"
run_probe b1-file "$P_BF" "${body_env[@]}"
rc=$RUN_RC; evaluate_body "$RUN_ROW"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout" && [[ -z "$(ls -A "$RUN_ROW/tmp")" ]]; then
  row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv, no file written)" ok
else row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv, no file written)" fail "rc=$rc failed='$EV_FAILED' pass-line=$(grep -c '^PASS' "$RUN_ROW/stdout" || true) leftover=$(ls -A "$RUN_ROW/tmp" | tr "\n" ",")"; fi
if [[ -s "$ROWS/b1-file/shim/jq/counter" ]] && grep -aqF 'ENV.SYNTH_PW_E' "$ROWS/b1-file/shim/jq/1.argv"; then
  row "jq shim: records jq's argv (the body writer's program text is on file; recording works)" ok
else row "jq shim: records jq's argv (the body writer's program text is on file; recording works)" fail "no jq argv recorded"; fi

P_BA="$(make_body_probe argv)"
run_probe b2-argv "$P_BA" "${body_env[@]}"
evaluate_body "$RUN_ROW"
if has_check pw-in-argv; then row "body: handing the password to curl as -d \"\$body\" is RED on pw-in-argv" ok
else row "body: handing the password to curl as -d \"\$body\" is RED on pw-in-argv" fail "failed='$EV_FAILED'"; fi

P_BJ="$(make_body_probe jqarg)"
run_probe b3-jqarg "$P_BJ" "${body_env[@]}"
evaluate_body "$RUN_ROW"
if has_check pw-in-jq-argv && ! has_check pw-in-argv; then
  row "body: passing the password to jq as --arg is RED on pw-in-jq-argv, which the curl shim alone cannot see" ok
else row "body: passing the password to jq as --arg is RED on pw-in-jq-argv, which the curl shim alone cannot see" fail "failed='$EV_FAILED'"; fi

run_probe b4-nobody "$P_BF" "${body_env[@]}" SHIM_MUTATE=nobody
evaluate_body "$RUN_ROW"
if has_check body-not-recorded && has_check body-content; then row "body: a shim that stops recording the stdin body turns the body rows RED" ok
else row "body: a shim that stops recording the stdin body turns the body rows RED" fail "failed='$EV_FAILED'"; fi

P_BD="$(make_body_probe dstdin)"
run_probe b5-dfile "$P_BD" "${body_env[@]}"
nl_bin="$(wc -l < "$ROWS/b1-file/shim/calls/1.body")"; nl_d="$(wc -l < "$ROWS/b5-dfile/shim/calls/1.body")"
if [[ "$nl_bin" -ge 2 && "$nl_d" -eq 0 ]]; then
  row "body: the shim keeps CR/LF for --data-binary @- and strips them for -d @- on stdin, as real curl does (control C4)" ok
else row "body: the shim keeps CR/LF for --data-binary @- and strips them for -d @- on stdin, as real curl does (control C4)" fail "binary-lines=$nl_bin d-lines=$nl_d"; fi

# fail7: the transport-failure mode, calibrated to real curl's exit 7 by control C4.
run_probe b6-fail7 "$P_CANON" "SYNTH_TOKEN=$FIXTURE_TOKEN" SHIM_MODE=fail7
count_calls "$RUN_ROW"
if [[ "$RUN_RC" -eq 7 && "$EV_CALLS" -eq 1 ]] && ! grep -q '^PASS' "$RUN_ROW/stdout" && grep -q 'TRANSIENT' "$RUN_ROW/stderr"; then
  row "fail7: a transport failure (curl exit 7) reaches the probe's TRANSIENT path with the call recorded, never PASS" ok
else row "fail7: a transport failure (curl exit 7) reaches the probe's TRANSIENT path with the call recorded, never PASS" fail "rc=$RUN_RC calls=$EV_CALLS"; fi

# (d) static rows over the converted sources and docs. `git grep` reads TRACKED files by default: on an
# uncommitted tree a new file is invisible, so the helper searches untracked files too (--untracked) and
# requires every operand to exist. It passes ONLY on `git grep -q` rc 1 (no match): rc 128 (not a repo, as
# in a mutation sandbox; a bad pathspec) and rc 0 (a match) are both failures, so `! git grep` can no
# longer pass vacuously.
static_absent() { # <ere> <file...>
  local ere="$1" f rc=0; shift
  for f in "$@"; do [[ -f "$f" ]] || return 1; done
  git grep -q --untracked -E -e "$ere" -- "$@" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]]
}
COMM="plugins/soleur/skills/community/scripts"
SETUP_MD="plugins/soleur/skills/flag-bootstrap/SETUP.md"
n_apikey_argv="$(grep -cE -e '-H +"?Authorization: *Api-Key' "$SETUP_MD" || true)"
n_apikey_cfg="$(grep -cF 'header = "Authorization: Api-Key %s"' "$SETUP_MD" || true)"
if [[ "$n_apikey_argv" -eq 0 && "$n_apikey_cfg" -ge 5 ]]; then
  row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" ok
else row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" fail "argv=$n_apikey_argv stdin-config=$n_apikey_cfg"; fi
if static_absent '-H +"Authorization: *Bot' "$COMM/discord-community.sh" "$COMM/discord-setup.sh" \
   && grep -qF 'header = "Authorization: Bot %s"' "$COMM/discord-community.sh" "$COMM/discord-setup.sh"; then
  row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" ok
else row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" fail "an argv Bot header is back, or the stdin config line is gone"; fi
# A password variable inside a -d/--data* operand of the two bsky scripts (lint equality says nothing about
# a body: it is not a header, so these two files are not in baseline E).
# BSKY_BODY_FILE / bsky-body: the retired 0600 temp-file mechanism must not come back.
if static_absent '(-d|--data[a-z-]*)[ =]+"([^"\\]|\\.)*\$\{?BSKY_(APP_PASSWORD|PW)|--arg +[a-z_]+ +"\$\{?BSKY_(APP_PASSWORD|PW)|BSKY_BODY_FILE|bsky-body' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" \
   && [[ "$(grep -c -F -e '--data-binary @- \' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]] \
   && [[ "$(grep -c -F -e '$ENV.BSKY_PW' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]]; then
  row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg or a temp file, both pipe jq to --data-binary @-" ok
else row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg or a temp file, both pipe jq to --data-binary @-" fail "the password is back on an argv, the temp-file form is back, or the stdin form is gone"; fi
echo "=== stage 4: shim extensions (scheme, stdin body, fail7, jq shim, static rows) done ==="

# =====================================================================================
# VERDICT. The floor and the conservation check are reported with printf + exit 1, never
# through the helpers they guard. Rows only grow as probes convert, so the floor is a LOWER bound.
# =====================================================================================
echo "=== $pass passed, $fail failed ==="

# Conservation: `row` counts at the call site, `_report` counts the verdict. If they diverge the
# helper stopped counting (or a row bypassed it).
if [[ "$((pass + fail))" -ne "$CASES" ]]; then
  printf '[FAIL] harness: pass+fail=%s but %s rows were dispatched -- the reporting helper stopped counting\n' "$((pass + fail))" "$CASES" >&2
  exit 1
fi

# BOTH operands are literals on the lines IMMEDIATELY above the `if`.
SELFTEST_PASSES=0
EXPECTED_TESTS=169
REAL=$((pass + fail - SELFTEST_PASSES))
if [[ "$REAL" -lt "$EXPECTED_TESTS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s rows ran, floor is %s -- rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$EXPECTED_TESTS" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
