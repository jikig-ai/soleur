# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
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
# scripts/check-deploy-script-parity.sh and the followthrough probes that remain in HMAC_MANIFEST. Same canonical HMAC snippet as the
# cutover copies (key on the python3 child's ENVIRONMENT only), `_bearer_ok` (a copy of the cutover function) on both
# Cloudflare Access values, `--disable --noproxy '*'` first, `--config -` with three `header = "..."` lines on a
# process substitution. A refusal sends nothing and prints the value-free marker; the exit code is the SURFACE'S
# non-verdict code (2 for the parity script and the 10548 probe, whose contract reads 2 as TRANSIENT; 3 for the soak
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

# ---- the audit of the converted files: ONE function, so the real rows and the mutant rows judge identically ----
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
# DERIVED from HMAC_MANIFEST (plus the parity script), never hand-listed: a hand-written list let a manifest probe (10548) sit unaudited, and a
# swapped entry kept the row count while dropping a probe's audit.
HM5_FILES="scripts/check-deploy-script-parity.sh
$(printf '%s\n' "$HMAC_MANIFEST" | cut -d'|' -f1 | sed 's|^|scripts/followthroughs/|; s|$|.sh|')"
# a malformed manifest row (empty name, no separator) derives a bogus path: refuse it here, by name, before the audit and its mutants run on nothing
while IFS= read -r hf; do
  [[ -f "$hf" ]] || fatal "HM5_FILES derived a path that is not a file ($hf): an HMAC_MANIFEST row is malformed"
done <<< "$HM5_FILES"
# the files that hold the canonical HMAC program (outside *.test.sh) must be exactly the audited set: a probe classified into another manifest, or moved
# out of this one, would otherwise leave the audit green with that probe unaudited
HM5_HOLDERS="$(git ls-files 'scripts/*.sh' 'scripts/followthroughs/*.sh' | grep -v '\.test\.sh$' | xargs grep -lF 'HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3' | sort)"
if [[ -n "$HM5_HOLDERS" && "$HM5_HOLDERS" == "$(printf '%s\n' "$HM5_FILES" | sort)" ]]; then row "census: the files holding the canonical HMAC program are exactly the audited set (the parity script and every HMAC_MANIFEST probe)" ok
else row "census: the files holding the canonical HMAC program are exactly the audited set (the parity script and every HMAC_MANIFEST probe)" fail "holders='${HM5_HOLDERS//$'\n'/,}' audited='${HM5_FILES//$'\n'/,}'"; fi
while IFS= read -r hf; do
  hm5_audit "$hf"
  if [[ -z "$HM5_BAD" ]]; then row "$hf: the canonical HMAC program with the deploy key (guarded, 64-hex checked), _bearer_ok on both Cloudflare Access values, curl --disable --noproxy '*' with the three header lines on a process substitution, no openssl, xtrace refusal" ok
  else row "$hf: the canonical HMAC program with the deploy key (guarded, 64-hex checked), _bearer_ok on both Cloudflare Access values, curl --disable --noproxy '*' with the three header lines on a process substitution, no openssl, xtrace refusal" fail "failed facets:$HM5_BAD"; fi
done <<< "$HM5_FILES"
hm_hmacflag="$(git grep -nE -- '-hmac' -- $HM5_FILES | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -c . || true)"
if [[ "$hm_hmacflag" == 0 ]]; then row "census: no -hmac operand remains in the parity script or the manifest probes (the key is on no openssl argv)" ok
else row "census: no -hmac operand remains in the parity script or the manifest probes (the key is on no openssl argv)" fail "$hm_hmacflag non-comment -hmac lines"; fi

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
  base="$(basename "$hf" .sh)"; hm5_fbad=""; hm5_fn=0
  for hm5_facet in guard openssl config config-hdr-cf config-nodisable config-barecurl config-noprintf config-twoprintf preamble; do
    hm5_facet_mut "$hf" "$hm5_facet"; hm5_audit "$HM5_MUT"; hm5_fn=$((hm5_fn + 1))
    [[ "$HM5_BAD" == " ${hm5_facet%%-*}" ]] || hm5_fbad+=" [$hm5_facet:${HM5_BAD:-none}]"
  done
  # a facet deleted from the list above and from hm5_audit together leaves every remaining mutant green: count the facets driven
  [[ "$hm5_fn" -eq 9 ]] || hm5_fbad+=" [facet count $hm5_fn, expected 9]"
  if [[ -z "$hm5_fbad" ]]; then row "mutation ($base): dropping the || VAR=\"\" guard, adding an openssl line, removing the xtrace refusal, and (for the config facet, each conjunct and alternative ALONE) adding an X-Signature -H header, adding a CF-Access -H header, dropping --disable, adding a second bare curl command, dropping the header printf and repeating it each fail exactly their own facet" ok
  else row "mutation ($base): dropping the || VAR=\"\" guard, adding an openssl line, removing the xtrace refusal, and (for the config facet, each conjunct and alternative ALONE) adding an X-Signature -H header, adding a CF-Access -H header, dropping --disable, adding a second bare curl command, dropping the header printf and repeating it each fail exactly their own facet" fail "facets that did not fire alone:$hm5_fbad"; fi
done <<< "$HM5_FILES"

# ---- running the parity script under the hmac-cf profile ------------------------------------------------------------
PARBIN="$HMX/parbin"; PYSEL="$HMX/pysel"; PYGARB="$HMX/pygarb"
for d in "$PARBIN" "$PYSEL" "$PYGARB"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
ln -s "$(type -P sha256sum)" "$PARBIN/sha256sum"                        # the parity script hashes ci-deploy.sh; not added to REALBIN
printf '#!%s\nprintf "not-a-digest"\n' "$BASH_BIN" > "$PYGARB/python3"                # python3 that prints a non-digest
printf '#!%s\n[[ "${1:-}" == "-I" ]] && exit 1\nexec "%s" "$@"\n' "$BASH_BIN" "$REAL_PY" > "$PYSEL/python3"   # fails ONLY the HMAC call (-I -c), runs the host-key parse
chmod +x "$PYGARB/python3" "$PYSEL/python3"
HMX_ENV=("WEBHOOK_DEPLOY_SECRET=$HMX_KEY" "CF_ACCESS_CLIENT_ID=$HMX_CFID" "CF_ACCESS_CLIENT_SECRET=$HMX_CFSEC"
  "BETTERSTACK_QUERY_HOST=bs.example.test" "BETTERSTACK_QUERY_USERNAME=bsu" "BETTERSTACK_QUERY_PASSWORD=bsp"
  "SHIM_AUTH=hmac-cf" "SHIM_HMAC_KEY=$HMX_KEY" "SHIM_CF_ID=$HMX_CFID" "SHIM_CF_SECRET=$HMX_CFSEC")
HMX_PATH="$HMBIN:$PYDIR:$PARBIN"   # recording python3/openssl (real tool behind them), then the real python3, then sha256sum
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


while IFS='|' read -r h_name h_kind h_hosts h_min h_body h_test; do
  [[ -n "$h_name" ]] || continue
  case "$h_kind" in
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
# E4 (moved here from the retired per-probe rows; CTO F7): a 100,000-byte (class-clean) Cloudflare Access secret with a never-reading shim under
# pipefail: the process-substitution writer dies silently, and the script must still reach its recorded call and exit 0 with no broken-pipe text.
par_run par-E4 SHIM_MODE=noread "CF_ACCESS_CLIENT_SECRET=$BIGTOK"; rc=$RUN_RC
if [[ "$rc" -eq 0 ]] && grep -qF 'PARITY(status)' "$RUN_ROW/stdout" && [[ "$(bk_calls "$RUN_ROW")" -ge 1 ]] && ! grep -aqi 'broken pipe' "$RUN_ROW/stderr"; then
  row "check-deploy-script-parity: a 100,000-byte Cloudflare Access secret with a never-reading shim under pipefail: rc 0, a recorded call, no broken pipe" ok
else row "check-deploy-script-parity: a 100,000-byte Cloudflare Access secret with a never-reading shim under pipefail: rc 0, a recorded call, no broken pipe" fail "rc=$rc calls=$(bk_calls "$RUN_ROW")"; fi
hm5_mut "$PAR" bearer '*[!A-Za-z0-9._~+/=-]*) return 1' '*[!A-Za-z0-9._~+/=\"-]*) return 1'
PARSB="$HMX/sb-par"; assert_fixture_dir "$PARSB"; mkdir -p "$PARSB/scripts"; ln -sfn "$REPO_ROOT/apps" "$PARSB/apps"   # ROOT = the sandbox; the infra files it reads come through the symlink
cp "$HM5_MUT" "$PARSB/scripts/check-deploy-script-parity.sh"
PAR_SCRIPT="$PARSB/scripts/check-deploy-script-parity.sh"
par_run par-Mbearer "CF_ACCESS_CLIENT_SECRET=$(tok_for quote)"; evaluate_hmac "$RUN_ROW" 'deploy\.soleur\.ai' 0
PAR_SCRIPT=""
if [[ "$(bk_calls "$RUN_ROW")" -ge 1 && " $EV_FAILED " == *" injected "* ]]; then row "check-deploy-script-parity: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED" ok
else row "check-deploy-script-parity: mutant admitting the double quote in _bearer_ok sends the hostile secret and the shim records INJECTED" fail "calls=$(bk_calls "$RUN_ROW") failed='$EV_FAILED'"; fi
echo "=== stage S2-C: deploy-webhook triple (parity script and the HMAC manifest probes) done ==="

