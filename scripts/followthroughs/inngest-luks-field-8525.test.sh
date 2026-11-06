#!/usr/bin/env bash
# Test battery for scripts/followthroughs/inngest-luks-field-8525.sh (#8525).
# Convention: cq-test-fixtures-synthesized-only — every row is fabricated here; the
# betterstack-query.sh seam is replaced by a fixture-emitting stub via INNGEST_SERVING_QUERY_BIN.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SELF_DIR/inngest-luks-field-8525.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS_N=0; FAIL_N=0
pass() { PASS_N=$((PASS_N + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL_N=$((FAIL_N + 1)); printf 'FAIL  %s — got rc=%s out=%s\n' "$1" "$2" "$3"; }

MSG_OK='SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=failed cutover_flag=rolled-back probe_schema=9 host_role=dedicated data_mount_src=/dev/mapper/inngest-redis data_mount_devid=scsi-0HC_Volume_1 registry_fns=7 data_luks=crypto_LUKS'
MSG_S8='SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=failed cutover_flag=rolled-back probe_schema=8 host_role=dedicated data_mount_src=/dev/sdb registry_fns=7'
MSG_UNREAD='SOLEUR_INNGEST_SERVER_PROBE probe_schema=9 host_role=dedicated data_luks=__UNREADABLE__'
MSG_EXT4='SOLEUR_INNGEST_SERVER_PROBE probe_schema=9 host_role=dedicated data_luks=ext4'
MSG_NA='SOLEUR_INNGEST_SERVER_PROBE probe_schema=9 host_role=web data_luks=n/a'
MSG_SPLIT_A='SOLEUR_INNGEST_SERVER_PROBE probe_schema=9 host_role=dedicated data_luks=__UNREADABLE__'
MSG_SPLIT_B='SOLEUR_INNGEST_SERVER_PROBE probe_schema=8 host_role=dedicated data_luks=crypto_LUKS'

bs_line() { # bs_line <host> <host_name> <message> [emitter]
  jq -cn --arg h "$1" --arg hn "$2" --arg m "$3" --arg id "${4:-inngest-server-probe}" \
    '{dt:"2026-11-05 00:00:00", raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$id, message:$m} | tojson)}'
}

stub_query() { # stub_query <file> — a query stub that cats the fixture file (or exits)
  cat > "$TMP/query-$1.sh" <<QE
#!/usr/bin/env bash
[ -f "$TMP/fixture-$1" ] && cat "$TMP/fixture-$1" || exit 22
QE
  chmod +x "$TMP/query-$1.sh"
  printf '%s' "$TMP/query-$1.sh"
}

run() { # run <fixture-file|-> <extra-env...>
  local fx="$1"; shift
  if [ "$fx" != "-" ]; then printf '%s' "$fx" > "$TMP/fixture-q"; fi
  env -i PATH="$PATH" \
    BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x \
    INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" "$@" \
    bash "$PROBE" 2>&1
}
cat > "$TMP/query-q.sh" <<'QE'
#!/usr/bin/env bash
[ -f "${FT_FIXTURE:?}" ] && cat "$FT_FIXTURE" || exit 22
QE
chmod +x "$TMP/query-q.sh"

# 1. PASS: a serving-host schema-9 row carrying data_luks=crypto_LUKS.
out="$(FT_FIXTURE=<(bs_line soleur-inngest soleur-inngest-prd "$MSG_OK") bash -c '
  env -i PATH="$PATH" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x \
    INNGEST_SERVING_QUERY_BIN="'"$TMP"'/query-q.sh" FT_FIXTURE=/dev/stdin bash "$0" </dev/null 2>&1' bash 2>/dev/null)"
# ^ process substitution is fragile under env -i; use a real file instead:
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_OK")" > "$TMP/f-pass"
rc=0; out="$(FT_FIXTURE="$TMP/f-pass" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-pass" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 0 && "$out" == PASS:* ]] && pass "schema9+crypto_LUKS => PASS rc0" || fail "schema9+crypto_LUKS => PASS rc0" "$rc" "$out"

# 2. TRANSIENT: schema-8 rows only (the baked carrier has not landed).
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_S8")" > "$TMP/f-s8"
rc=0; out="$(FT_FIXTURE="$TMP/f-s8" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-s8" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 && "$out" == *not_schema9_luks* ]] && pass "schema8 only => TRANSIENT not_schema9_luks" || fail "schema8 only => TRANSIENT" "$rc" "$out"

# 3. TRANSIENT: schema-9 row whose data_luks is __UNREADABLE__ (the question applied, unanswered).
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_UNREAD")" > "$TMP/f-un"
rc=0; out="$(FT_FIXTURE="$TMP/f-un" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-un" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 ]] && pass "schema9+__UNREADABLE__ => TRANSIENT (never PASS)" || fail "schema9+UNREADABLE" "$rc" "$out"

# 4. TRANSIENT: schema-9 row with data_luks=ext4 (the confident-wrong-answer — must NOT pass).
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_EXT4")" > "$TMP/f-e4"
rc=0; out="$(FT_FIXTURE="$TMP/f-e4" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-e4" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 ]] && pass "schema9+ext4 => TRANSIENT (never PASS)" || fail "schema9+ext4" "$rc" "$out"

# 5. TRANSIENT: a web-host n/a row under the DEDICATED filter cannot pass; and the same
#    crypto_LUKS row on the WRONG host cannot pass either.
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_NA")" "$(bs_line web-1 web-1 "$MSG_OK")" > "$TMP/f-wh"
rc=0; out="$(FT_FIXTURE="$TMP/f-wh" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-wh" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 ]] && pass "n/a row + wrong-host crypto_LUKS => TRANSIENT" || fail "host isolation" "$rc" "$out"

# 6. TRANSIENT: split tokens — schema9 in one row, crypto_LUKS in another — never assembled.
printf '%s\n' "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_SPLIT_A")" "$(bs_line soleur-inngest soleur-inngest-prd "$MSG_SPLIT_B")" > "$TMP/f-sp"
rc=0; out="$(FT_FIXTURE="$TMP/f-sp" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-sp" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 ]] && pass "split tokens across rows => TRANSIENT" || fail "split tokens" "$rc" "$out"

# 7. TRANSIENT channel_dark: the query answers nothing.
printf '' > "$TMP/f-empty"
rc=0; out="$(FT_FIXTURE="$TMP/f-empty" env -i PATH="$PATH" FT_FIXTURE="$TMP/f-empty" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 && "$out" == *channel_dark* ]] && pass "zero rows => TRANSIENT channel_dark" || fail "channel_dark" "$rc" "$out"

# 8. TRANSIENT query_failed: the read path exits non-zero.
rm -f "$TMP/fixture-q"; cat > "$TMP/query-q.sh" <<'QE'
#!/usr/bin/env bash
exit 22
QE
chmod +x "$TMP/query-q.sh"
rc=0; out="$(env -i PATH="$PATH" FT_FIXTURE="$TMP/f-empty" BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 && "$out" == *query_failed* ]] && pass "query rc!=0 => TRANSIENT query_failed" || fail "query_failed" "$rc" "$out"

# 9. TRANSIENT credentials_unprovisioned: missing warehouse env.
rc=0; out="$(env -i PATH="$PATH" INNGEST_SERVING_QUERY_BIN="$TMP/query-q.sh" bash "$PROBE" 2>&1)" || rc=$?
[[ "$rc" -eq 2 && "$out" == *credentials_unprovisioned* ]] && pass "missing creds => TRANSIENT credentials_unprovisioned" || fail "credentials" "$rc" "$out"

printf '\n%d passed, %d failed\n' "$PASS_N" "$FAIL_N"
[ "$FAIL_N" -eq 0 ]
