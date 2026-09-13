#!/usr/bin/env bash
# Tests for the #7095 re-read in the two webhook-executed scripts that still called Doppler on
# the webhook unit's boot-baked token (revoked 2026-07-30): inngest-rearm-reminders.sh (the
# cutover's 2.1 capture and the post-deploy re-arm) and inngest-wiped-volume-verify.sh.
#
# Found live on 2026-09-13: the first op=execute dispatch to clear 2.0 after #8056 died one step
# later — `2.1 capture returned HTTP 500: ERROR: INNGEST_MANUAL_TRIGGER_SECRET unavailable (env +
# doppler both empty)` — because read_secret() ran `doppler secrets get … 2>/dev/null` on the
# unit's revoked DOPPLER_TOKEN, discarded the 401, and fell into its fail-closed branch. ci-deploy.sh
# and infra-config-apply.sh had been re-pointed at /etc/default/soleur-doppler-token by #7095;
# these two had not. This suite pins the CLASS fix: one function, two byte-identical copies.
#
# Seams: SOLEUR_DOPPLER_TOKEN_FILE (the re-deliverable credential file; cat-deploy-state.sh already
# honours the same variable), a mock `doppler` on PATH that answers ONLY to the fresh token, a mock
# `logger` that records what the script would have sent to journald, and the suites' existing mock
# curl/systemctl/sudo/enumerate stubs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REARM="$SCRIPT_DIR/inngest-rearm-reminders.sh"
WIPED="$SCRIPT_DIR/inngest-wiped-volume-verify.sh"
CIDEPLOY="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc"; else fail "$desc"; echo "    expected: $expected"; echo "    actual:   $actual"; fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$desc"; else fail "$desc — '$needle' not found"; fi
}
assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$desc"; else fail "$desc — '$needle' FOUND"; fi
}

# Instrument self-test (ADR-193): both counters must move before anything is graded.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — EXPECTED, discounted below)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then printf 'instrument self-test did not move both counters\n' >&2; exit 1; fi
FAIL=$((FAIL - 1))

# The fresh token the re-deliverable file carries, and the revoked one the unit still exports.
# Synthetic, shape-valid (dp.st.<...>) so the scrub regex in the scripts has something to bite on.
FRESH="dp.st.fresh_synthetic_token_0000000000000000000000000000000000000000"
REVOKED="dp.st.revoked_synthetic_token_00000000000000000000000000000000000000"
SECRET_VALUE="synthetic-bearer-secret-for-tests"

MOCKBIN=""
setup() {
  MOCKBIN=$(mktemp -d)
  # mock doppler: answers ONLY when the fresh token is in the environment — exactly the live
  # discriminator (the unit exports the revoked one; the file carries the fresh one).
  cat > "${MOCKBIN}/doppler" <<MOCK
#!/usr/bin/env bash
echo "DOPPLER_TOKEN_SEEN=\${DOPPLER_TOKEN:-<unset>} ARGS=\$*" >> "${MOCKBIN}/doppler.log"
if [[ "\${DOPPLER_TOKEN:-}" == "$FRESH" ]]; then printf '%s\n' "$SECRET_VALUE"; exit 0; fi
echo "Doppler Error: Invalid Auth token (token=\${DOPPLER_TOKEN:-<unset>})" >&2
exit 1
MOCK
  chmod +x "${MOCKBIN}/doppler"
  # mock logger: record what would have gone to journald (Better Stack is the read path).
  cat > "${MOCKBIN}/logger" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/logger.log"
MOCK
  chmod +x "${MOCKBIN}/logger"
  # mock curl (rearm + wiped share the shape: record args + body, emit scripted code).
  cat > "${MOCKBIN}/curl" <<MOCK
#!/usr/bin/env bash
body=""; prev=""; url=""
for a in "\$@"; do
  case "\$prev" in --data-binary|-d) body="\$a" ;; -o) : > "\$a" 2>/dev/null || true ;; esac
  case "\$a" in http*) url="\$a" ;; esac
  prev="\$a"
done
{ echo "ARGS: \$*"; echo "BODY: \$body"; } >> "${MOCKBIN}/curl.log"
case "\$url" in
  *health*)  printf '200' ;;
  *v0/gql*)  printf '%s' '{"data":{"functions":[{"slug":"cron-x"}]}}' ;;
  *)         printf '%s' "\${MOCK_HTTP_CODE:-202}" ;;
esac
MOCK
  chmod +x "${MOCKBIN}/curl"
  cat > "${MOCKBIN}/systemctl" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/systemctl.log"
case "\$*" in *"show inngest-server.service"*) echo 'ExecStart=/usr/local/bin/inngest start --postgres-max-open-conns 10' ;; esac
exit 0
MOCK
  chmod +x "${MOCKBIN}/systemctl"
  cat > "${MOCKBIN}/sudo" <<'MOCK'
#!/usr/bin/env bash
while [[ "$1" == -* ]]; do shift; done
exec "$@"
MOCK
  chmod +x "${MOCKBIN}/sudo"
  cat > "${MOCKBIN}/enum.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s' '[]'
MOCK
  chmod +x "${MOCKBIN}/enum.sh"
  : > "${MOCKBIN}/doppler.log"; : > "${MOCKBIN}/logger.log"; : > "${MOCKBIN}/curl.log"
}
teardown() { rm -rf "$MOCKBIN"; MOCKBIN=""; }

write_token_file() { printf 'DOPPLER_TOKEN=%s\nSENTRY_INGEST_DOMAIN=o1.ingest.sentry.io\nSENTRY_PROJECT_ID=1\nSENTRY_PUBLIC_KEY=k\n' "$1" > "${MOCKBIN}/soleur-doppler-token"; }

# Run rearm in capture mode the way the webhook does: no stdin records, self-enumerate stub,
# secret NOT in env (the webhook passes only INNGEST_REARM_MODE), unit env carries the REVOKED token.
run_rearm_capture() {
  local rc=0
  env -u INNGEST_MANUAL_TRIGGER_SECRET \
    PATH="${MOCKBIN}:$PATH" DOPPLER_TOKEN="$REVOKED" \
    SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
    INNGEST_REARM_MODE=capture INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" \
    bash "$REARM" </dev/null >"${MOCKBIN}/rearm.out" 2>&1 || rc=$?
  return "$rc"
}

# Run wiped-volume-verify to its arm step with the same credential environment.
run_wiped() {
  local rc=0 data_dir="${MOCKBIN}/inngest-data"; mkdir -p "$data_dir"; echo "sqlite" > "$data_dir/main.db"
  env -u INNGEST_MANUAL_TRIGGER_SECRET \
    PATH="${MOCKBIN}:$PATH" DOPPLER_TOKEN="$REVOKED" \
    SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
    INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" INNGEST_DATA_DIR="$data_dir" \
    INNGEST_VERIFY_EXECSTART="/usr/local/bin/inngest start --postgres-max-open-conns 10" \
    INNGEST_VERIFY_STATE="${MOCKBIN}/verify.state" INNGEST_VERIFY_SETTLE_SECS=0 \
    bash "$WIPED" >"${MOCKBIN}/wiped.out" 2>&1 || rc=$?
  return "$rc"
}

echo "=== webhook Doppler token re-read (#7095 class) ==="

# --- A. the CLASS: one function, byte-identical in both consumers, shaped like ci-deploy's ---
extract_fn() { awk '/^soleur_refresh_doppler_token\(\) \{$/,/^\}$/' "$1"; }
FN_REARM="$(extract_fn "$REARM")"
FN_WIPED="$(extract_fn "$WIPED")"
assert_eq "A1 rearm defines soleur_refresh_doppler_token" "1" "$([[ -n "$FN_REARM" ]] && echo 1 || echo 0)"
assert_eq "A2 wiped-volume-verify defines soleur_refresh_doppler_token" "1" "$([[ -n "$FN_WIPED" ]] && echo 1 || echo 0)"
assert_eq "A3 the two copies are byte-identical (the assert_fixture_dir precedent — a helper re-derived per file drifts)" "1" "$([[ -n "$FN_REARM" && "$FN_REARM" == "$FN_WIPED" ]] && echo 1 || echo 0)"
# Parsed, not sourced: the same security property ci-deploy.sh documents above its own block.
assert_eq "A4 the function never sources the file (no '. ' / 'source ' of the credential path)" "0" "$(printf '%s\n' "$FN_REARM" | grep -cE '(^|[[:space:];])(\.|source)[[:space:]]+"?\$' || true)"
assert_contains "A5 reads with IFS='=' read -r (ci-deploy's parse shape)" "$FN_REARM" "IFS='=' read -r"
assert_contains "A6 honours SOLEUR_DOPPLER_TOKEN_FILE with the /etc/default/soleur-doppler-token default" "$FN_REARM" '${SOLEUR_DOPPLER_TOKEN_FILE:-/etc/default/soleur-doppler-token}'
assert_eq "A7 ci-deploy.sh still reads the same path (the class has three members, not two)" "1" "$(grep -c '^if \[ -r /etc/default/soleur-doppler-token \]; then$' "$CIDEPLOY")"
# Each consumer must CALL the function before its doppler read, inside read_secret.
for f in "$REARM" "$WIPED"; do
  body="$(awk '/^read_secret\(\) \{$/,/^\}$/' "$f")"
  call_ln=$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*soleur_refresh_doppler_token([[:space:]]|$)' | head -1 | cut -d: -f1 || true)
  dopp_ln=$(printf '%s\n' "$body" | grep -nE 'doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET' | head -1 | cut -d: -f1 || true)
  assert_eq "A8 $(basename "$f"): read_secret calls the refresh BEFORE its doppler read (call@${call_ln:-none} < doppler@${dopp_ln:-none})" "1" \
    "$([[ -n "$call_ln" && -n "$dopp_ln" && "$call_ln" -lt "$dopp_ln" ]] && echo 1 || echo 0)"
done

# --- B. rearm (2.1 capture path): the live 2026-09-13 failure, reproduced then fixed ---
setup; write_token_file "$FRESH"
rc=0; run_rearm_capture || rc=$?
assert_eq "B1 capture succeeds with the revoked token in env and the fresh one in the file (rc 0)" "0" "$rc"
assert_contains "B2 doppler was invoked with the FRESH token (later-wins over the unit's export)" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
assert_not_contains "B3 the revoked token never reached doppler" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$REVOKED"
assert_eq "B4 the capture file was written" "1" "$([[ -s "${MOCKBIN}/capture.json" ]] && echo 1 || echo 0)"
teardown

# --- C. file ABSENT: behaviour is exactly the old one (fail closed on the revoked token), and the
#        reason is now observable in journald instead of swallowed by 2>/dev/null ---
setup
rc=0; run_rearm_capture || rc=$?
assert_eq "C1 fails closed when the file is absent and the env token is revoked (rc 1)" "1" "$rc"
LOG="$(cat "${MOCKBIN}/logger.log")"
assert_contains "C2 the doppler failure is logged (rc + token_file state), not swallowed" "$LOG" "doppler read failed rc=1"
assert_contains "C3 …and names the credential file as absent" "$LOG" "token_file=absent"
assert_not_contains "C4 the logged stderr never carries a credential-shaped token (dp.xx.…)" "$LOG" "$REVOKED"
assert_contains "C5 the scrub leaves a marker where the token was" "$LOG" "dp.**.REDACTED"
assert_contains "C6 the original FATAL line still fires (fail-closed contract unchanged)" "$LOG" "FATAL: INNGEST_MANUAL_TRIGGER_SECRET unavailable"
teardown

# --- D. an EMPTY value in the file must not blank a working credential (the EnvironmentFile=- hole
#        ci-deploy's block closes; a bare `DOPPLER_TOKEN=` passes the installer's shape check) ---
setup; printf 'DOPPLER_TOKEN=\n' > "${MOCKBIN}/soleur-doppler-token"
rc=0
env -u INNGEST_MANUAL_TRIGGER_SECRET PATH="${MOCKBIN}:$PATH" DOPPLER_TOKEN="$FRESH" \
  SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
  INNGEST_REARM_MODE=capture INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
  SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" bash "$REARM" </dev/null >/dev/null 2>&1 || rc=$?
assert_eq "D1 a bare DOPPLER_TOKEN= line does not blank a working env token (rc 0)" "0" "$rc"
assert_contains "D2 doppler still saw the working token" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
teardown

# --- E. a hostile line is DATA, not code (parsed, not sourced) ---
setup; printf 'DOPPLER_TOKEN=%s\nSENTRY_PROJECT_ID=$(touch %s/PWNED)\n' "$FRESH" "$MOCKBIN" > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture || rc=$?
assert_eq "E1 the script still succeeds with a hostile sibling line present" "0" "$rc"
assert_eq "E2 the command substitution in the file was NOT executed" "0" "$([[ -e "${MOCKBIN}/PWNED" ]] && echo 1 || echo 0)"
teardown

# --- F. env secret already present: no file read, no doppler call (unchanged fast path) ---
setup; write_token_file "$FRESH"
rc=0
env PATH="${MOCKBIN}:$PATH" DOPPLER_TOKEN="$REVOKED" INNGEST_MANUAL_TRIGGER_SECRET="$SECRET_VALUE" \
  SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
  INNGEST_REARM_MODE=capture INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
  SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" bash "$REARM" </dev/null >/dev/null 2>&1 || rc=$?
assert_eq "F1 env secret path still works" "0" "$rc"
assert_eq "F2 doppler not called when the secret is already in env" "0" "$(grep -c . "${MOCKBIN}/doppler.log" || true)"
teardown

# --- G. wiped-volume-verify: same class, same fix ---
setup; write_token_file "$FRESH"
rc=0; run_wiped || rc=$?
assert_eq "G1 wiped-volume-verify arms its marker with the fresh token (rc 0)" "0" "$rc"
assert_contains "G2 doppler saw the FRESH token" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
assert_contains "G3 the marker POST carried the Bearer secret doppler returned" "$(cat "${MOCKBIN}/curl.log")" "Bearer ${SECRET_VALUE}"
teardown
setup
rc=0; run_wiped || rc=$?
assert_eq "G4 …and still aborts no_secret when the file is absent and the env token is revoked" "1" "$rc"
assert_contains "G5 the abort reason is no_secret" "$(cat "${MOCKBIN}/logger.log")" "ABORT: no_secret"
assert_contains "G6 the doppler failure reason is logged there too" "$(cat "${MOCKBIN}/logger.log")" "doppler read failed rc=1"
teardown

# --- H. #7797 hygiene the touched files now carry (paid down in this PR) ---
for f in "$REARM" "$WIPED"; do
  assert_eq "H1 $(basename "$f") refuses xtrace" "1" "$(grep -c 'refusing to run under xtrace' "$f")"
  # Each `curl` invocation (joined across its backslash continuations) that carries an
  # Authorization header must open `curl --disable --noproxy '*'` — the position is load-bearing.
  n_cred=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$f" | grep -E '\bcurl\b.*Authorization: Bearer' | grep -c . || true)
  n_bad=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$f" | grep -E '\bcurl\b.*Authorization: Bearer' | grep -vE "curl --disable --noproxy '\*' " | grep -c . || true)
  assert_eq "H2 $(basename "$f") every credentialed curl is transport-confined (--disable --noproxy '*'): $n_cred credentialed, $n_bad unconfined" "1" "$([[ "$n_cred" -ge 1 && "$n_bad" -eq 0 ]] && echo 1 || echo 0)"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
MIN_ASSERTIONS=34
if (( PASS + FAIL < MIN_ASSERTIONS )); then printf 'assertion floor not met: %d < %d\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2; exit 1; fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
