#!/bin/bash
# Shared profile table and write-out printer for the TEST doubles of curl (#10934, ADR-294). SOURCED, never executed, never delivered
# to a host. Two doubles use it: the resolver suite's $BIN/curl (inngest-link-resolver.test.sh) and the unified curl mock of
# ci-deploy.test.sh. A third "double" is real curl itself: the H6 row of the resolver suite runs the real self-gate against real curl
# and local TLS listeners and compares what real curl prints with the values below (a profile that drifts from real curl reds H6).
#
# WHY ONE FILE: a double that models part of the tool hides the defect (2026-10-22 learning: the mock docker ignored the env-file).
# The old stubs printed the HTTP code only (or nothing) and exited 0, 60 or N, so the self-gate's `-w` line could never be shown to
# say anything about the stage that failed. Both doubles now route EVERY outcome through the one printer below.
#
# THE VALUES (the measured table) are copied from knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/curl-w-measurements.md,
# measured 2026-10-23 on curl 7.81.0, 8.5.0 and 8.23.0 against real local listeners (a python `ssl` server and real stunnel 5.72);
# the values printed here are the curl 8.5.0 column. `req_partial` and `status_partial` (rc 18) were measured on 8.5.0 in the deepen
# pass. Only the four variables that exist since curl 7.19 are modelled: http_code time_connect time_appconnect ssl_verify_result.
# There is deliberately NO num_connects column (it is never printed) and NO default profile inside the printer (the callers pick ok200
# themselves when their row names none): an unknown profile or an unknown write-out variable is refused (stderr, exit 99, a sentinel
# file), because a double that "helpfully" answers 200 is how #10874 hid.
#
# PROFILE SPEC: <name> or <name>@<rc> (the rc override is for rows that pin the SAME times under a different exit code, or that pair a
# raw output with the code a failing curl would exit with). The caller exports CURL_W_SENTINEL (the sentinel path) before calling
# curlw_print; every suite asserts the sentinel absent after each row. CURL_W_PROFILES_FILE (read by the callers' `source`) overrides
# the path of this file, so a row can run against a COPY with one value flipped (the H9 row).

# name|rc|http_code|time_connect|time_appconnect|ssl_verify_result
CURLW_MEASURED='refused|7|000|0.000000|0.000000|0
fw_drop|28|000|0.000000|0.000000|0
hs_close|35|000|0.000198|0.000000|1
hs_rst|35|000|0.000140|0.000000|1
hs_plain|35|000|0.000134|0.000000|1
hs_hang|28|000|0.000201|0.000000|1
ca_file|77|000|0.000452|0.000000|1
verify18|60|000|0.000119|0.000000|18
verify10|60|000|0.000203|0.000000|10
verify1_san|60|000|0.000462|0.000000|1
req_reset|56|000|0.000138|0.004360|0
req_empty|52|000|0.000125|0.008238|0
req_hang|28|000|0.000155|0.004901|0
req_http09|1|000|0.000114|0.006970|0
req_partial|18|200|0.000329|0.012484|0
status_partial|18|502|0.000110|0.007349|0
status502|0|502|0.000235|0.010363|0
ok200|0|200|0.000503|0.009276|0'

# name|rc|the raw output curl would print (printed verbatim, whatever the -w string asked for; outside the measured-format regex)
#   raw_empty    nothing printed (the `timeout 20` wrapper killed curl: rc 124; curl 8.23 with a missing --cacert file: rc 2)
#   raw_garbage  four tokens, none usable: the first is URL-shaped (an event must never carry it), both time fields are text
#   raw_short3   a short line: only the first two fields (code, time_connect); named for the plan row, kept as is
#   raw_nonnum   both time fields non-numeric; verify field 18 (read only when the exit code is 60)
#   raw_nonnum502 the same with a 502 code
#   ok200_comma_extra   a healthy 200 with a comma decimal separator and one extra trailing token (no trailing newline, like curl)
#   req_reset_comma     the incident shape (req_reset) with comma decimal separators
#   raw_refused_comma   a refused connection (rc 7) whose zero timers use the comma separator (`0,000000`): zero is zero in either form
#   raw_hs_comma        TCP connected, no handshake (rc 35) with comma separators: a non-zero time_connect, a zero time_appconnect
#   raw_verify_nonnum   rc 60 whose verification-result field is text, not an integer (the event must print verify=0)
#   raw_status204       rc 0 with HTTP 204 and good timers: a gate that accepts "any 2xx" passes it, the real one must fail closed
#   raw_code2000        rc 0 with the four-digit code 2000: a gate that matches "200*" passes it, the real one must fail closed
#   raw_tc_bad          rc 56, time_connect text, time_appconnect a readable non-zero number (one unreadable timer beside a good one)
CURLW_RAW='raw_empty|124|
raw_garbage|56|https://leak.invalid/x 10.0.1.40 garbage 0
raw_short3|56|200 0.000503
raw_nonnum|56|000 abc def 18
raw_nonnum502|56|502 abc def 0
ok200_comma_extra|0|200 0,000503 0,009276 0 extra
req_reset_comma|56|000 0,000138 0,004360 0
raw_refused_comma|7|000 0,000000 0,000000 0
raw_hs_comma|35|000 0,000198 0,000000 1
raw_verify_nonnum|60|000 0.000119 0.000000 abc
raw_status204|0|204 0.000235 0.010363 0
raw_code2000|0|2000 0.000235 0.010363 0
raw_tc_bad|56|000 abc 0.004360 0'

CURLW_KNOWN_VARS="http_code time_connect time_appconnect ssl_verify_result"

# curlw_fail <reason>: stderr, the sentinel (when CURL_W_SENTINEL is set), return 99.
curlw_fail() {
  printf 'curl-w-profiles: %s\n' "$1" >&2
  if [ -n "${CURL_W_SENTINEL:-}" ]; then printf '%s\n' "$1" >> "$CURL_W_SENTINEL"; fi
  return 99
}

# curlw_lookup <spec>: sets CURLW_KIND (measured|raw), CURLW_RC, CURLW_CODE, CURLW_TC, CURLW_TA, CURLW_VER, CURLW_RAWOUT. Returns 1 for
# an unknown profile or a malformed rc override.
curlw_lookup() {
  local spec="$1" name rcov="" n rc code tc ta ver rest
  name="${spec%%@*}"
  if [[ "$spec" == *@* ]]; then rcov="${spec#*@}"; fi
  CURLW_KIND=""; CURLW_RC=""; CURLW_CODE=""; CURLW_TC=""; CURLW_TA=""; CURLW_VER=""; CURLW_RAWOUT=""
  if [[ -n "$rcov" && ! "$rcov" =~ ^[0-9]{1,3}$ ]]; then return 1; fi
  while IFS='|' read -r n rc code tc ta ver; do
    if [[ "$n" == "$name" ]]; then
      CURLW_KIND=measured; CURLW_RC="${rcov:-$rc}"; CURLW_CODE="$code"; CURLW_TC="$tc"; CURLW_TA="$ta"; CURLW_VER="$ver"
      return 0
    fi
  done <<< "$CURLW_MEASURED"
  while IFS='|' read -r n rc rest; do
    if [[ "$n" == "$name" ]]; then
      CURLW_KIND=raw; CURLW_RC="${rcov:-$rc}"; CURLW_RAWOUT="$rest"
      return 0
    fi
  done <<< "$CURLW_RAW"
  return 1
}

# curlw_render <fmt>: sets CURLW_OUT to what curl would print for the -w string <fmt> (the four modelled variables, %%, and the backslash
# escapes \n \r \t \\ ), no trailing newline unless the format asks for one. It renders the profile of the PRECEDING curlw_lookup (the
# CURLW_* variables it set), so call curlw_lookup first; curlw_print does. Returns 99 on an unknown variable.
curlw_render() {
  local f="$1" out="" name v known bs=$'\\'
  CURLW_OUT=""
  while [[ -n "$f" ]]; do
    case "$f" in
      '%{'*)
        if [[ "$f" != *'}'* ]]; then curlw_fail "unterminated write-out variable in: $f"; return 99; fi
        name="${f:2}"; name="${name%%\}*}"
        known=0; for v in $CURLW_KNOWN_VARS; do if [[ "$v" == "$name" ]]; then known=1; fi; done
        if [[ "$known" -ne 1 ]]; then curlw_fail "unknown write-out variable: $name"; return 99; fi
        f="${f:$((${#name} + 3))}"
        if [[ "$CURLW_KIND" == measured ]]; then
          case "$name" in
            http_code) out+="$CURLW_CODE" ;;
            time_connect) out+="$CURLW_TC" ;;
            time_appconnect) out+="$CURLW_TA" ;;
            ssl_verify_result) out+="$CURLW_VER" ;;
          esac
        fi
        ;;
      '%%'*) out+='%'; f="${f:2}" ;;
      '\n'*) out+=$'\n'; f="${f:2}" ;;
      '\r'*) out+=$'\r'; f="${f:2}" ;;
      '\t'*) out+=$'\t'; f="${f:2}" ;;
      "$bs$bs"*) out+="$bs"; f="${f:2}" ;;
      *) out+="${f:0:1}"; f="${f:1}" ;;
    esac
  done
  CURLW_OUT="$out"
  return 0
}

# curlw_print <spec> <fmt>: prints what the profile's curl would print to stdout and RETURNS the exit code curl would exit with
# (callers do `curlw_print ...; exit $?`). An unknown profile or variable returns 99 (and drops the sentinel).
curlw_print() {
  if ! curlw_lookup "$1"; then curlw_fail "unknown profile: $1"; return 99; fi
  curlw_render "$2" || return 99
  if [[ "$CURLW_KIND" == raw ]]; then printf '%s' "$CURLW_RAWOUT"; else printf '%s' "$CURLW_OUT"; fi
  return "$CURLW_RC"
}
