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

# STDIN IS CLOSED FOR THE WHOLE SUITE (#11572 item 13). Children inherit this process's stdin, and the S6 stub `docker`
# (written below) drains it unconditionally with `pw="$(cat)"` on every arm: under an open stdin (a terminal, a CI pipe
# that never closes) any call that reaches it without its own piped stdin blocks forever. Other readers of stdin exist too
# (the curl shim cats its body for `@-` and `--config -`); only the `read` loops in this file are all fed by a here-string, a
# file, a process substitution or a pipe. This line gives every child that is not handed its own stdin an immediate EOF.
# The pin rows after `_selftest_report` assert that it stays the FIRST statement after `set -uo pipefail`, and that fd 0
# really is /dev/null at run time.
exec < /dev/null

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

# Pin of the `exec < /dev/null` above (Guard 3 of #11572 item 13): it must be the FIRST statement after the first
# `set -uo pipefail`, at column 0 and unconditional. A layout where it sits later, inside a function, an `if` or a `case` arm
# is refused (each of those lets a child be started with the inherited stdin before it runs, or never runs it).
_pin_exec_stdin() { # <suite file>
  awk '
    !s && $0 == "set -uo pipefail" { s = 1; next }
    s && !r && $0 !~ /^[[:space:]]*(#|$)/ { r = 1; ok = ($0 == "exec < /dev/null") }
    END { exit !(s && r && ok) }' "$1"
}
if _pin_exec_stdin "${BASH_SOURCE[0]}"; then row "stdin: the suite closes its stdin (exec < /dev/null) as the first statement after set -uo pipefail" ok
else row "stdin: the suite closes its stdin (exec < /dev/null) as the first statement after set -uo pipefail" fail "the exec line is missing, not first, conditional, or nested"; fi
# Runtime: fd 0 really is /dev/null (the file pin above cannot see an exec that never ran). Without /proc, a read that returns
# EOF at once (rc 1) stands in; an open stdin would time out (rc > 128) instead.
_fd0="$(readlink /proc/self/fd/0 2>/dev/null || true)"
if [[ -z "$_fd0" ]]; then IFS= read -r -t 2 _fd0_line; _fd0_rc=$?; [[ "$_fd0_rc" == 1 ]] && _fd0=/dev/null; fi
if [[ "$_fd0" == /dev/null ]]; then row "stdin: fd 0 is /dev/null at run time" ok
else row "stdin: fd 0 is /dev/null at run time" fail "fd 0 is '$_fd0'"; fi
# Controls: the pin accepts the canonical layout and refuses each broken one (written under the scratch root).
printf '#!/usr/bin/env bash\n# c\nset -uo pipefail\n\n# note\nexec < /dev/null\nX=1\n' > "$TMPD/pin-good.sh"
printf '#!/usr/bin/env bash\nset -uo pipefail\nX=1\nexec < /dev/null\n' > "$TMPD/pin-late.sh"
printf '#!/usr/bin/env bash\nset -uo pipefail\nf() {\nexec < /dev/null\n}\nX=1\n' > "$TMPD/pin-nested.sh"
printf '#!/usr/bin/env bash\nset -uo pipefail\nif false; then\nexec < /dev/null\nfi\nX=1\n' > "$TMPD/pin-conditional.sh"
# A comment above the real `set` that quotes it: an anchor loosened to a substring match would start counting at the comment,
# and then accept the exec line that sits between the comment and the real `set`.
printf '#!/usr/bin/env bash\n# note: set -uo pipefail\nexec < /dev/null\nset -uo pipefail\nX=1\n' > "$TMPD/pin-set-quoted.sh"
printf '#!/usr/bin/env bash\nset -uo pipefail\n exec < /dev/null\nX=1\n' > "$TMPD/pin-exec-indented.sh"
printf '#!/usr/bin/env bash\nset -uo pipefail\nexec < /dev/null || true\nX=1\n' > "$TMPD/pin-exec-trailing.sh"
if _pin_exec_stdin "$TMPD/pin-good.sh"; then row "stdin pin control: the canonical layout (exec first after set, comments and blanks between) is accepted" ok
else row "stdin pin control: the canonical layout (exec first after set, comments and blanks between) is accepted" fail "a good layout was refused"; fi
for _pin_bad in late nested conditional set-quoted; do
  if _pin_exec_stdin "$TMPD/pin-$_pin_bad.sh"; then row "stdin pin control: the $_pin_bad layout is refused" fail "the pin accepted a $_pin_bad layout"
  else row "stdin pin control: the $_pin_bad layout is refused" ok; fi
done
if _pin_exec_stdin "$TMPD/pin-exec-indented.sh" || _pin_exec_stdin "$TMPD/pin-exec-trailing.sh"; then
  row "stdin pin control: an exec line with a leading space, or with trailing text, is refused" fail "the pin accepted an altered exec line"
else row "stdin pin control: an exec line with a leading space, or with trailing text, is refused" ok; fi

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
# STRUCTURAL PREAMBLE (#13099): the split-driver invariant. The fragments under
# tests/scripts/argv-bearer-sweep/ are SOURCED by this driver and share this process's
# counters, scratch root, shim and helpers; they are NOT independently runnable. The
# population is DERIVED (git ls-files), never counted by hand: the exact set AND order
# of the unconditional, column-0 `source` statements below must equal the tracked
# fragment list or the suite reds before any fragment runs. The check is embedded here
# rather than registered as a separate suite so the manifest check cannot drift from
# the only supported entry point and no second runner surface can be omitted, misregistered
# or bypassed. A conditionally sourced fragment is caught two ways: indented (or otherwise
# non-canonical) source lines are absent from the static manifest, and a fragment skipped
# at run time drops the row count below the exact EXPECTED_TESTS floor.
_structural_fragments=()
while IFS= read -r _structural_f; do
  _structural_fragments+=("$_structural_f")
done < <(git ls-files 'tests/scripts/argv-bearer-sweep/*.sh')
_structural_sources=()
while IFS= read -r _structural_f; do
  _structural_sources+=("$_structural_f")
done < <(awk '$0 ~ /^source / && NF == 2 && $2 ~ /^tests\/scripts\/argv-bearer-sweep\/[^[:space:]]+\.sh$/ { print $2 }' "${BASH_SOURCE[0]}")
_structural_mismatch=""
if [[ "${#_structural_fragments[@]}" -eq 0 ]]; then
  _structural_mismatch="the tracked fragment population is empty"
elif [[ "${#_structural_fragments[@]}" -ne "${#_structural_sources[@]}" ]]; then
  _structural_mismatch="${#_structural_sources[@]} unconditional sources for ${#_structural_fragments[@]} tracked fragments"
else
  for (( _structural_i = 0; _structural_i < ${#_structural_fragments[@]}; _structural_i++ )); do
    if [[ "${_structural_sources[$_structural_i]}" != "${_structural_fragments[$_structural_i]}" ]]; then
      _structural_mismatch="position $((_structural_i + 1)): source '${_structural_sources[$_structural_i]}' != tracked '${_structural_fragments[$_structural_i]}'"
      break
    fi
  done
fi
if [[ -n "$_structural_mismatch" ]]; then
  row "structure: the driver sources exactly the tracked fragment set, once each, unconditionally and in order" fail "$_structural_mismatch"
  printf 'FATAL: structural fragment mismatch: %s\n' "$_structural_mismatch" >&2
  exit 2
fi
row "structure: the driver sources exactly the tracked fragment set, once each, unconditionally and in order" ok
unset _structural_fragments _structural_sources _structural_mismatch _structural_f _structural_i

source tests/scripts/argv-bearer-sweep/01-controls-stages-2-4-s2a-backup.sh
source tests/scripts/argv-bearer-sweep/02-s2a-hmac.sh
source tests/scripts/argv-bearer-sweep/03-s2b-s2c.sh
source tests/scripts/argv-bearer-sweep/04-s3-workflow.sh
source tests/scripts/argv-bearer-sweep/05-s4-through-guard2-row12.sh
source tests/scripts/argv-bearer-sweep/06-s4-guard2-rows13-24.sh
source tests/scripts/argv-bearer-sweep/07-s5-apply-registry.sh
source tests/scripts/argv-bearer-sweep/08-s6-heartbeat.sh
source tests/scripts/argv-bearer-sweep/09-s7-markdown.sh
source tests/scripts/argv-bearer-sweep/10-s8-s9.sh

# =====================================================================================
# VERDICT. The floor and the conservation check are reported with printf + exit 1, never
# through the helpers they guard. The floor is EXACT (a count above it is a STALE FLOOR, see the -ne branch at the end): raise it in the same PR as the rows.
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
# 841 -> 874 at #9757 item 2 (stage S9, terraform -var credentials off argv: derived scan, rehearsal-workflow pins, the four terraform step bodies executed under strict stubs): the 33 S9 rows. The tree measured 841 after merging main (the floor said 840, so it had 1 row of slack), so the new floor is the measured total (874 passed, 0 failed).
# 874 -> 875 at the second merge of main: #10566 added one S4 manifest row (git-data-rehearsal-evidence), so the base is 842 and the total is the measured 875 (875 passed, 0 failed).
# 875 -> 880 at the #10697 fix round (rebased onto the 875 above; was 842 -> 847 on its own base) (#10455): web-bash-synthetic.sh joins S6H_CONVERTED (1 row), its _hb_url_ok digest and _hb_curl line pins (2 rows) and one mutation row each (2): measured (847 passed, 0 failed). S6H_FILE_FLOOR stays 7: it detects a mis-resolved directory (the derived population is 17 files), and the S6-HB scratch tree holds only the converted scripts plus two controls.
# 880 -> 824 at G1 PR-4a (#10937; S4_GUARD_FLOOR 76 -> 74, the measured count): the four retired followthrough probes take their per-probe HMAC rows (the dynamic rows of three, the delegated row of the fourth, their hm5_audit and mutation rows and the manifest rows) with them; the parity block gains one E4 row and HM5_FILES gains sdk-bash-smoke-verdict-10548.sh (its audit and mutation rows): measured (824 passed, 0 failed); 824 -> 825 at the same PR's review round: one census row (the files holding the canonical HMAC program are exactly the audited set): measured (825 passed, 0 failed).
# 825 -> 824 at #6590 PR-B: the orphan-sweeps-relook-10972 suite was retired (monitor destroyed);
# its DELEGATED_MANIFEST row left with it. Rebased over #11483's dispatch-recovery-sweeper-11211
# (+1, main 825): net floor stays 824.
# 824 -> 830 at #11572 (item 13): 829 measured on main before this change, plus the one stdin pin row (830 passed, 0 failed).
# 830 -> 837 at the #11572 review rounds (2026-10-30): the pin is "first statement after set -uo pipefail" (1 row), plus the run-time fd 0 row, the canonical-layout control, four refused-layout controls (late, nested, conditional, a quoted `set` above the real one) and one altered-exec-line control: measured (837 passed, 0 failed).
# 837 -> 831 at #9927 item 8 (this PR): lead (b), the op=arm mask battery (the G2/G3 control, hostile and empty drives, the G3.5 control, hostile and empty drives, and the
#   mutants row: seven rows), left with op=arm; the tree measured 838 rows before (floor 837, one row of slack) and 831 after (831 passed, 0 failed), so the floor is now the exact measured count.
# 832 -> 833 at #13099 (the split): one structural row (the driver sources exactly the tracked fragment set, once each, unconditionally and in
#   order). The 832 pre-split rows moved byte-for-byte into the ten sourced fragments; the split itself adds no assertion rows. Measured post-split (833 passed, 0 failed).
EXPECTED_TESTS=833
REAL=$((pass + fail - SELFTEST_PASSES))
if [[ "$REAL" -lt "$EXPECTED_TESTS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s rows ran, floor is %s -- rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$EXPECTED_TESTS" >&2
  exit 1
elif [[ "$REAL" -ne "$EXPECTED_TESTS" ]]; then
  printf 'STALE FLOOR: %s rows ran, EXPECTED_TESTS is %s -- set EXPECTED_TESTS=%s (the count is exact by design; rows were added without updating it).\n' "$REAL" "$EXPECTED_TESTS" "$REAL" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
