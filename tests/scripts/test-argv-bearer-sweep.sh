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
inngest-soak-6178|delegated|||none|scripts/followthroughs/inngest-soak-6178.test.sh'

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
# 17 of the 19 `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"` sites become the CANONICAL SNIPPET: the key rides
# the python3 child's ENVIRONMENT only (per-command prefix). The two sites in the `registry-probe)` and
# `doublefire-probe)` arms are HELD BACK (plan decision D1: the infra suite's tool census counts a python3 token
# in those arms; the suite edit is tracked with S4/S5). The committed oracle is the OTHER implementation,
# `openssl dgst -hmac`, only ever run here with a synthetic key.
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

# --- parity: every converted copy equals the canonical string; the -hmac operand lives only at the two held-back arms ---
hm_arm_count() { # <from-arm-regex> <to-arm-regex> <ere> <file> -> count of lines matching <ere> inside the arm range [from, to)
  awk -v from="$1" -v to="$2" -v re="$3" '$0 ~ from {f=1; next} $0 ~ to {f=0} f && $0 ~ re {n++} END {print n+0}' "$4"
}
# hm_audit <script>: ONE function reads the parity facts, so the real rows and the mutation rows below judge with the same code.
#   HM_BAD    space-separated copy indices that differ from the canonical snippet, lost the SIG=$(printf <body> | ...) shape, lost the
#             `|| VAR=""` fallback, or sign a body other than the one their own request carries (derived per site, see below)
#   HM_NCOPY  converted copies; HM_NOLD lines carrying the -hmac operand; HM_RP / HM_DP of those inside the registry-probe) /
#   doublefire-probe) arms; HM_PYARMS python3 tokens inside the registry-probe) .. rearm) range
hm_audit() {
  local f="$1" ln rest seg i=0 shape n j k var tail blk want
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
    want=""
    if [[ -n "$blk" ]]; then
      if [[ "$blk" == *'-d "$PAYLOAD"'* || "$blk" == *' --data'* ]]; then want=payload; else want=empty; fi
    fi
    case "$want:$ln" in
      empty:'    '[A-Z]*'=$(printf '"''"' | HMAC_KEY='*|payload:'    '[A-Z]*'=$(printf '"'%s'"' "$PAYLOAD" | HMAC_KEY='*) shape=1 ;;
    esac
    [[ "$seg" == "$HM_CANON" && "$shape" == 1 ]] || HM_BAD+=" $i"
  done
  HM_NCOPY=$i
  HM_NOLD="$(grep -cF -e '-hmac' "$f" || true)"
  HM_RP="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+doublefire-probe[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_DP="$(hm_arm_count '^[[:space:]]+doublefire-probe[)]$' '^[[:space:]]+rearm[)]$' 'openssl dgst -sha256 -hmac "[$]WEBHOOK_SECRET"' "$f")"
  HM_PYARMS="$(hm_arm_count '^[[:space:]]+registry-probe[)]$' '^[[:space:]]+rearm[)]$' 'python3' "$f")"
}
# hm_audit_ok: the whole parity contract at once (17 identical copies, -hmac only at the two held-back arm anchors).
hm_audit_ok() { [[ -z "$HM_BAD" && "$HM_NCOPY" == 17 && "$HM_NOLD" == 2 && "$HM_RP" == 1 && "$HM_DP" == 1 && "$HM_PYARMS" == 0 ]]; }
hm_audit "$CUT"
for hm_i in $(seq 1 17); do
  if [[ " $HM_BAD " != *" $hm_i "* && "$hm_i" -le "$HM_NCOPY" ]]; then row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" ok
  else row "cutover HMAC copy $hm_i equals the canonical snippet, keeps the SIG=\$(printf <body> | ...) || SIG=\"\" shape and signs the body its own request carries" fail "copy missing or differs from the canonical string, lost its fallback, or signs the wrong body (bad:$HM_BAD copies=$HM_NCOPY)"; fi
done
if [[ "$HM_NCOPY" == 17 && -z "$HM_BAD" ]]; then row "cutover HMAC: exactly 17 converted copies (19 sites minus the 2 held back by plan decision D1), no extra or divergent copy" ok
else row "cutover HMAC: exactly 17 converted copies (19 sites minus the 2 held back by plan decision D1), no extra or divergent copy" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
if [[ "$HM_NOLD" == 2 && "$HM_RP" == 1 && "$HM_DP" == 1 && "$HM_PYARMS" == 0 ]]; then
  row "cutover HMAC: the -hmac operand appears exactly twice, once in the registry-probe) arm and once in the doublefire-probe) arm, and no python3 token is in those arms" ok
else row "cutover HMAC: the -hmac operand appears exactly twice, once in the registry-probe) arm and once in the doublefire-probe) arm, and no python3 token is in those arms" fail "file=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS"; fi
hm_cm=0
while IFS= read -r ln; do
  n="${ln%%:*}"; prev="$(sed -n "$((n - 1))p" "$CUT" | sed 's/^[[:space:]]*//')"
  [[ "$prev" == '#'* && "$prev" == *D1* && "$prev" == *S4/S5* && "$prev" == *'#9757'* ]] && hm_cm=$((hm_cm + 1))
done < <(grep -n -F -e '-hmac' "$CUT")
if [[ "$hm_cm" == 2 ]]; then row "cutover HMAC: each held-back site carries a one-line comment naming plan decision D1, the S4/S5 suite edit and its tracker #9757" ok
else row "cutover HMAC: each held-back site carries a one-line comment naming plan decision D1, the S4/S5 suite edit and its tracker #9757" fail "commented=$hm_cm"; fi

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
for idx in $(seq 1 17); do
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
if [[ "$HM_NCOPY" == 16 && "$HM_NOLD" == 3 ]] && ! hm_audit_ok; then row "mutation: the key put back on openssl's argv in copy 5 is caught (16 copies, a third -hmac operand outside the held-back arms)" ok
else row "mutation: the key put back on openssl's argv in copy 5 is caught (16 copies, a third -hmac operand outside the held-back arms)" fail "copies=$HM_NCOPY -hmac=$HM_NOLD"; fi
{ cat "$CUT"; printf '%s\n' "    SIGX=\$(printf '' | ${HM_CANON/sha256/sha1})"; } > "$BKDIR/hm-mut-extra.sh"
hm_audit "$BKDIR/hm-mut-extra.sh"
if [[ "$HM_NCOPY" == 18 && " $HM_BAD " == *" 18 "* ]] && ! hm_audit_ok; then row "mutation: an 18th inline copy that differs by one byte is caught (copy count and byte comparison)" ok
else row "mutation: an 18th inline copy that differs by one byte is caught (copy count and byte comparison)" fail "copies=$HM_NCOPY bad:$HM_BAD"; fi
nth_replace "$CUT" "$BKDIR/hm-mut-heldpy.sh" 'openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed '"'"'s/.*= //'"'"')' "$HM_CANON)" 1 || fatal "parity mutation heldpy did not land"
hm_audit "$BKDIR/hm-mut-heldpy.sh"
if [[ "$HM_NOLD" == 1 && "$HM_RP" == 0 && "$HM_DP" == 1 && "$HM_PYARMS" -ge 1 ]] && ! hm_audit_ok; then row "mutation: converting the held-back registry-probe) site (python3 inside the census range) is caught, pinned by its arm anchor (registry-probe) count 0, doublefire-probe) count 1)" ok
else row "mutation: converting the held-back registry-probe) site (python3 inside the census range) is caught, pinned by its arm anchor (registry-probe) count 0, doublefire-probe) count 1)" fail "-hmac=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS"; fi
nth_replace "$CUT" "$BKDIR/hm-mut-heldpy2.sh" 'openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed '"'"'s/.*= //'"'"')' "$HM_CANON)" 2 || fatal "parity mutation heldpy2 did not land"
hm_audit "$BKDIR/hm-mut-heldpy2.sh"
if [[ "$HM_NOLD" == 1 && "$HM_RP" == 1 && "$HM_DP" == 0 && "$HM_PYARMS" -ge 1 ]] && ! hm_audit_ok; then row "mutation: converting the held-back doublefire-probe) site is caught, pinned by its arm anchor (registry-probe) count 1, doublefire-probe) count 0)" ok
else row "mutation: converting the held-back doublefire-probe) site is caught, pinned by its arm anchor (registry-probe) count 1, doublefire-probe) count 0)" fail "-hmac=$HM_NOLD registry-probe=$HM_RP doublefire-probe=$HM_DP python3-in-arms=$HM_PYARMS"; fi

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
[[ -n "$hm_idx_payload" && -n "$hm_idx_empty" && "$hm_last" == 17 && -z "$HM_BAD" ]] || fatal "parity mutations: could not derive a payload-body copy and an empty-body copy from the real script"
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
EXPECTED_TESTS=410
REAL=$((pass + fail - SELFTEST_PASSES))
if [[ "$REAL" -lt "$EXPECTED_TESTS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s rows ran, floor is %s -- rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$EXPECTED_TESTS" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
