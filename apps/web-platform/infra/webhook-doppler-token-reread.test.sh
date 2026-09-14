#!/usr/bin/env bash
# Tests for the #7095 re-read in the two webhook-executed scripts that still called Doppler on
# the webhook unit's boot-baked token (revoked 2026-07-30): inngest-rearm-reminders.sh (the
# cutover's 2.1 capture and the post-deploy re-arm) and inngest-wiped-volume-verify.sh.
#
# Found live on 2026-09-13: the first op=execute dispatch to clear 2.0 after #8056 died one step
# later — `2.1 capture returned HTTP 500: ERROR: INNGEST_MANUAL_TRIGGER_SECRET unavailable (env +
# doppler both empty)` — because read_secret() ran `doppler secrets get … 2>/dev/null` on the
# unit's revoked DOPPLER_TOKEN, discarded the 401, and fell into its fail-closed branch. ci-deploy.sh
# had been re-pointed at /etc/default/soleur-doppler-token by #7095 (its parsed CRED_FILE_STATE
# block); these two had not. This suite pins the CLASS fix: one block, two byte-identical copies,
# and — section I — that no OTHER webhook-executed script reads Doppler without the re-read.
#
# Seams: SOLEUR_DOPPLER_TOKEN_FILE (the re-deliverable credential file; cat-deploy-state.sh already
# honours the same variable), a mock `doppler` on PATH that answers ONLY to the fresh token and
# prints the REAL CLI's four-line coloured stderr otherwise (measured against doppler v3.75.3 under
# the unit's DOPPLER_CONFIG_DIR/DOPPLER_ENABLE_VERSION_CHECK env), a mock `logger` that records what
# the script would have sent to journald, and the suites' existing mock curl/systemctl/sudo/enumerate
# stubs. The mock curl also records the Sentry /store/ POST the failure path now emits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REARM="$SCRIPT_DIR/inngest-rearm-reminders.sh"
WIPED="$SCRIPT_DIR/inngest-wiped-volume-verify.sh"
CIDEPLOY="$SCRIPT_DIR/ci-deploy.sh"
HOOKS_TMPL="$SCRIPT_DIR/hooks.json.tmpl"

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before every write under
# "$MOCKBIN" so the P1b relative-operand ratchet can see the operand is absolute.
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
# Anchored grep over a text: the needle is an ERE that must match at a code position, so a
# comment restating the token cannot satisfy it (cq-assert-anchor-not-bare-token).
assert_code_match() {
  local desc="$1" text="$2" ere="$3"
  # `grep >/dev/null`, never `grep -q` behind a pipe: under pipefail an early -q exit SIGPIPEs the
  # upstream writer on a long input and the whole condition reads false (measured on ci-deploy.sh).
  if printf '%s\n' "$text" | grep -vE '^[[:space:]]*#' | grep -E -- "$ere" >/dev/null; then pass "$desc"; else fail "$desc — no code line matches /$ere/"; fi
}

# Instrument self-test (ADR-193): every verdict-emitting helper must be able to REJECT before
# anything is graded, and both counters must move. The comparators are driven through their
# own failing branch — a comparator rewritten as `if true; then pass` would leave pass()/fail()
# intact and every counter reconciling.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — EXPECTED, discounted below)"
assert_eq "instrument self-test (assert_eq must fail on a mismatch — EXPECTED)" "a" "b" >/dev/null
assert_contains "instrument self-test (assert_contains must fail on a miss — EXPECTED)" "haystack" "zzz" >/dev/null
assert_not_contains "instrument self-test (assert_not_contains must fail on a hit — EXPECTED)" "haystack" "hay" >/dev/null
assert_code_match "instrument self-test (assert_code_match must fail when only a comment matches — EXPECTED)" "# token here" "token" >/dev/null
if (( PASS != _p0 + 1 || FAIL != _f0 + 5 )); then printf 'instrument self-test did not move both counters as expected (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL" >&2; exit 1; fi
FAIL=$((FAIL - 5))

# The fresh token the re-deliverable file carries, and the revoked one the unit still exports.
# Synthetic, shape-valid (dp.st.<...>) so the scrub regex in the scripts has something to bite on.
FRESH="dp.st.fresh_synthetic_token_0000000000000000000000000000000000000000"
REVOKED="dp.st.revoked_synthetic_token_00000000000000000000000000000000000000"
SECRET_VALUE="synthetic-bearer-secret-for-tests"

MOCKBIN=""
# The EXIT trap owns whatever mock dir is live when the suite dies between setup and teardown
# (lint-trap-tempfile-ownership rule c); teardown() still removes it on the normal path.
trap '[[ -n "$MOCKBIN" ]] && rm -rf -- "$MOCKBIN"' EXIT
setup() {
  MOCKBIN=$(mktemp -d)
  assert_fixture_dir "$MOCKBIN"
  # mock doppler: answers ONLY when the fresh token is in the environment — exactly the live
  # discriminator (the unit exports the revoked one; the file carries the fresh one). On a reject
  # it prints the REAL four-line stderr the CLI emits under this unit's env: two `Using …` notices,
  # the constant `Unable to fetch secrets`, then the coloured cause line LAST. DOPPLER_MOCK_MODE
  # selects a different shape: `empty` (rc 0, no stdout), `transport`, `notfound`.
  cat > "${MOCKBIN}/doppler" <<MOCK
#!/usr/bin/env bash
echo "DOPPLER_TOKEN_SEEN=\${DOPPLER_TOKEN:-<unset>} ARGS=\$*" >> "${MOCKBIN}/doppler.log"
case "\${DOPPLER_MOCK_MODE:-}" in
  empty) exit 0 ;;
  transport) printf 'Unable to fetch secrets\n\033[31mDoppler Error:\033[0m Get "https://api.doppler.com/v3/configs/config/secret?project=soleur&config=prd&name=INNGEST_MANUAL_TRIGGER_SECRET": dial tcp 104.18.1.1:443: connect: connection refused\n' >&2; exit 1 ;;
  notfound) printf '\033[31mDoppler Error:\033[0m Could not find requested secret: INNGEST_MANUAL_TRIGGER_SECRET\n' >&2; exit 1 ;;
  partial) printf 'PARTIAL-STDOUT-NOT-A-SECRET\n'; printf '\033[31mDoppler Error:\033[0m Invalid Auth token\n' >&2; exit 1 ;;
esac
if [[ "\${DOPPLER_TOKEN:-}" == "$FRESH" ]]; then printf '%s\n' "$SECRET_VALUE"; exit 0; fi
printf 'Using DOPPLER_CONFIG_DIR from the environment. To disable this, use --no-read-env.\n' >&2
printf 'Using DOPPLER_ENABLE_VERSION_CHECK from the environment. To disable this, use --no-read-env.\n' >&2
printf 'Unable to fetch secrets\n' >&2
printf '\033[31mDoppler Error:\033[0m Invalid Auth token (token=%s)\n' "\${DOPPLER_TOKEN:-<unset>}" >&2
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

# The re-deliverable file as soleur-doppler-token.tmpl renders it: token + the three baked Sentry
# DSN components (server.tf webhook_doppler_token_env), LF-terminated.
write_token_file() {
  assert_fixture_dir "$MOCKBIN"
  printf 'DOPPLER_TOKEN=%s\nSENTRY_INGEST_DOMAIN=o1.ingest.sentry.io\nSENTRY_PROJECT_ID=1\nSENTRY_PUBLIC_KEY=k\n' "$1" > "${MOCKBIN}/soleur-doppler-token"
}

# Run rearm in capture mode the way the webhook does: no stdin records, self-enumerate stub,
# secret NOT in env (the webhook passes only INNGEST_REARM_MODE). ENV_TOKEN is the unit's export
# (default: the REVOKED one; pass "" to run with DOPPLER_TOKEN unset, the post-cleanup shape).
run_rearm_capture() {
  local env_token="${1-$REVOKED}" rc=0
  assert_fixture_dir "$MOCKBIN"
  local -a tok=(); if [[ -n "$env_token" ]]; then tok=(DOPPLER_TOKEN="$env_token"); else tok=(-u DOPPLER_TOKEN); fi
  env -u INNGEST_MANUAL_TRIGGER_SECRET "${tok[@]}" \
    PATH="${MOCKBIN}:$PATH" \
    SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
    INNGEST_REARM_MODE=capture INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" \
    bash "$REARM" </dev/null >"${MOCKBIN}/rearm.out" 2>"${MOCKBIN}/rearm.err" || rc=$?
  return "$rc"
}

# Run wiped-volume-verify to its arm step with the same credential environment.
run_wiped() {
  local rc=0 data_dir="${MOCKBIN}/inngest-data"
  assert_fixture_dir "$MOCKBIN"
  mkdir -p "$data_dir"; echo "sqlite" > "$data_dir/main.db"
  env -u INNGEST_MANUAL_TRIGGER_SECRET \
    PATH="${MOCKBIN}:$PATH" DOPPLER_TOKEN="$REVOKED" \
    SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
    INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" INNGEST_DATA_DIR="$data_dir" \
    INNGEST_VERIFY_EXECSTART="/usr/local/bin/inngest start --postgres-max-open-conns 10" \
    INNGEST_VERIFY_STATE="${MOCKBIN}/verify.state" INNGEST_VERIFY_SETTLE_SECS=0 \
    bash "$WIPED" >"${MOCKBIN}/wiped.out" 2>"${MOCKBIN}/wiped.err" || rc=$?
  return "$rc"
}

# Comment-stripped source of a file (whole-line comments removed) for anchored assertions.
code_of() { grep -vE '^[[:space:]]*#' "$1"; }

echo "=== webhook Doppler token re-read (#7095 class) ==="

# --- A. the CLASS: one block, byte-identical in both consumers, shaped like ci-deploy's ---
extract_fn() { awk -v fn="$2" '$0 == fn "() {" {f=1} f {print} f && /^\}$/ {f=0}' "$1"; }
FN_REARM="$(extract_fn "$REARM" soleur_refresh_doppler_token)"
FN_WIPED="$(extract_fn "$WIPED" soleur_refresh_doppler_token)"
assert_eq "A1 rearm defines soleur_refresh_doppler_token" "1" "$([[ -n "$FN_REARM" ]] && echo 1 || echo 0)"
assert_eq "A2 wiped-volume-verify defines soleur_refresh_doppler_token" "1" "$([[ -n "$FN_WIPED" ]] && echo 1 || echo 0)"
assert_eq "A3 the two refresh copies are byte-identical (the assert_fixture_dir precedent — a helper re-derived per file drifts)" "1" "$([[ -n "$FN_REARM" && "$FN_REARM" == "$FN_WIPED" ]] && echo 1 || echo 0)"
for helper in soleur_doppler_read_class soleur_log_doppler_read_failure; do
  h1="$(extract_fn "$REARM" "$helper")"; h2="$(extract_fn "$WIPED" "$helper")"
  assert_eq "A3b $helper is defined in both and byte-identical (the scrub lives here — the copy that would drift)" "1" "$([[ -n "$h1" && "$h1" == "$h2" ]] && echo 1 || echo 0)"
done
# Parsed, not sourced: the same security property ci-deploy.sh documents above its own block.
assert_eq "A4 the function never sources the file (no '. ' / 'source ' of the credential path)" "0" "$(printf '%s\n' "$FN_REARM" | grep -cE '(^|[[:space:];])(\.|source)[[:space:]]+"?\$' || true)"
assert_code_match "A5 reads with \`while IFS='=' read -r … || [[ -n \"\$k\" ]]\` (ci-deploy's parse shape, plus the trailing-newline keep)" "$FN_REARM" "^[[:space:]]*while IFS='=' read -r k v \|\| \[\[ -n \"\\\$k\" \]\]; do$"
assert_code_match "A6 honours SOLEUR_DOPPLER_TOKEN_FILE with the /etc/default/soleur-doppler-token default" "$FN_REARM" '^[[:space:]]*local f="\$\{SOLEUR_DOPPLER_TOKEN_FILE:-/etc/default/soleur-doppler-token\}"'
assert_eq "A7 ci-deploy.sh still reads the same path (the class has three members, not two)" "1" "$(grep -c '^if \[ -r /etc/default/soleur-doppler-token \]; then$' "$CIDEPLOY")"
# Each consumer must CALL the function before its doppler read, inside read_secret — anchored on
# the call form and on the assignment form, so a comment naming either cannot satisfy it.
for f in "$REARM" "$WIPED"; do
  body="$(awk '/^read_secret\(\) \{$/,/^\}$/' "$f" | grep -vE '^[[:space:]]*#' || true)"
  call_ln=$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*soleur_refresh_doppler_token[[:space:]]*$' | head -1 | cut -d: -f1 || true)
  dopp_ln=$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*out="\$\(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET ' | head -1 | cut -d: -f1 || true)
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
assert_eq "B5 no credential-failure line on the happy path (the capture summary line is expected)" "0" "$(grep -c 'SOLEUR_DEPLOY_CRED_FAIL' "${MOCKBIN}/logger.log" || true)"
teardown
# The unit export is the thing #7095 will eventually remove: the read must not depend on it.
setup; write_token_file "$FRESH"
rc=0; run_rearm_capture "" || rc=$?
assert_eq "B6 capture succeeds with DOPPLER_TOKEN UNSET in env and the fresh one in the file (the parse must export, not merely assign)" "0" "$rc"
assert_contains "B7 doppler saw the FRESH token from the file alone" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
teardown

# --- C. file ABSENT: behaviour is exactly the old one (fail closed on the revoked token), and the
#        reason is now observable in journald, in the hook's response body, and in Sentry ---
setup
rc=0; run_rearm_capture || rc=$?
assert_eq "C1 fails closed when the file is absent and the env token is revoked (rc 1)" "1" "$rc"
LOG="$(cat "${MOCKBIN}/logger.log")"
assert_contains "C2 the doppler failure is logged with the SOLEUR_DEPLOY_CRED_FAIL marker Better Stack queries already key on" "$LOG" "SOLEUR_DEPLOY_CRED_FAIL secret=INNGEST_MANUAL_TRIGGER_SECRET rc=1"
assert_contains "C3 …names the credential file as absent" "$LOG" "token_file=absent"
assert_contains "C3b …classifies the revoked token as invalid_auth (the CAUSE line, not the constant head line)" "$LOG" "class=invalid_auth"
assert_contains "C3c …and the err field carries the Doppler Error cause, ANSI stripped" "$LOG" "err=\"Doppler Error: Invalid Auth token"
assert_not_contains "C3d …never the constant 'Using DOPPLER_CONFIG_DIR' notice the real CLI prints first" "$LOG" "Using DOPPLER_CONFIG_DIR"
assert_not_contains "C3e …no ESC byte survives" "$LOG" $'\033'
assert_not_contains "C4 the logged stderr never carries a credential-shaped token (dp.xx.…)" "$LOG" "$REVOKED"
assert_contains "C5 the scrub leaves a marker where the token was" "$LOG" "dp.**.REDACTED"
assert_contains "C5b the line is tagged for Vector's SYSLOG_IDENTIFIER allowlist" "$LOG" "-t inngest-rearm-reminders SOLEUR_DEPLOY_CRED_FAIL"
assert_contains "C6 the original FATAL line still fires (fail-closed contract unchanged)" "$LOG" "FATAL: INNGEST_MANUAL_TRIGGER_SECRET unavailable"
assert_contains "C7 the reason ALSO reaches stderr → the hook's response body → the cutover run log" "$(cat "${MOCKBIN}/rearm.err")" "ERROR: SOLEUR_DEPLOY_CRED_FAIL secret=INNGEST_MANUAL_TRIGGER_SECRET rc=1 class=invalid_auth token_file=absent token_applied=0"
assert_eq "C8 no Sentry POST when the file (and so the DSN components) is absent" "0" "$(grep -c '/store/' "${MOCKBIN}/curl.log" || true)"
assert_eq "C9 no reminder POST was made" "0" "$(grep -c 'schedule-reminder' "${MOCKBIN}/curl.log" || true)"
teardown

# --- C'. file PRESENT but its token ALSO rejected (delivery is stale): the state the 'present'
#         value exists to name, plus the Sentry beacon the DSN components enable ---
setup; write_token_file "$REVOKED"
rc=0; run_rearm_capture || rc=$?
assert_eq "C10 fails closed when the file's token is itself rejected" "1" "$rc"
LOG="$(cat "${MOCKBIN}/logger.log")"
assert_contains "C11 …and the line says the file WAS read AND its token applied (token_file=present token_applied=1) so diagnosis goes to the file's token, not to delivery" "$LOG" "token_file=present token_applied=1"
CURL="$(cat "${MOCKBIN}/curl.log")"
assert_contains "C12 a Sentry event was POSTed to the DSN the file carries" "$CURL" "https://o1.ingest.sentry.io/api/1/store/"
assert_contains "C13 …with the class enum in its tags" "$CURL" '"class":"invalid_auth"'
assert_not_contains "C14 …and never the raw stderr or a token" "$CURL" "$REVOKED"
assert_not_contains "C15 …nor the Doppler Error text" "$CURL" "Invalid Auth token"
assert_contains "C16 the Sentry curl is transport-confined (#7797)" "$CURL" "ARGS: --disable --noproxy * -s -o /dev/null --max-time 10 -X POST https://o1.ingest.sentry.io"
teardown
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=%s\nSENTRY_INGEST_DOMAIN=attacker.example.org\nSENTRY_PROJECT_ID=1\nSENTRY_PUBLIC_KEY=k\n' "$REVOKED" > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture || rc=$?
assert_eq "C16b a non-Sentry ingest host in the file receives NO credentialed POST (destination pinned by shape, #7873)" "0" "$(grep -c 'attacker.example.org' "${MOCKBIN}/curl.log" || true)"
assert_contains "C16c …while the journald line still fires" "$(cat "${MOCKBIN}/logger.log")" "class=invalid_auth token_file=present"
teardown

# --- C''. the other classes the CLI can produce ---
setup; write_token_file "$FRESH"
rc=0; DOPPLER_MOCK_MODE=transport run_rearm_capture || rc=$?
assert_eq "C17 a transport failure fails closed" "1" "$rc"
assert_contains "C18 …and is classified transport, distinct from invalid_auth" "$(cat "${MOCKBIN}/logger.log")" "class=transport"
assert_not_contains "C19 …with the cause line capped at 160 bytes (the dial-tcp URL is longer)" "$(grep SOLEUR_DEPLOY_CRED_FAIL "${MOCKBIN}/logger.log" | sed -E 's/.*err="//; s/"$//' | awk '{ print (length($0) > 160) ? "TOO_LONG" : "ok" }')" "TOO_LONG"
teardown
setup; write_token_file "$FRESH"
rc=0; DOPPLER_MOCK_MODE=notfound run_rearm_capture || rc=$?
assert_eq "C20 a missing secret fails closed" "1" "$rc"
assert_contains "C21 …and is classified secret_not_found" "$(cat "${MOCKBIN}/logger.log")" "class=secret_not_found"
teardown
setup; write_token_file "$FRESH"
rc=0; DOPPLER_MOCK_MODE=empty run_rearm_capture || rc=$?
assert_eq "C22 an rc-0 EMPTY value fails closed" "1" "$rc"
assert_contains "C23 …and is classified empty_value with rc=0" "$(cat "${MOCKBIN}/logger.log")" "rc=0 class=empty_value"
teardown
# rc≠0 with stdout: whatever a failing CLI (or a shim named doppler) printed must NOT become the secret.
setup; write_token_file "$FRESH"
rc=0; DOPPLER_MOCK_MODE=partial run_rearm_capture || rc=$?
assert_eq "C28 a failing read with partial stdout still fails closed (rc 1)" "1" "$rc"
assert_eq "C29 …and no POST carried the partial stdout as a Bearer" "0" "$(grep -c 'PARTIAL-STDOUT-NOT-A-SECRET' "${MOCKBIN}/curl.log" || true)"
teardown
# binary absent: PATH without the mock doppler (and without the developer's real one).
setup; write_token_file "$FRESH"; rm -f "${MOCKBIN}/doppler"
rc=0
env -u INNGEST_MANUAL_TRIGGER_SECRET DOPPLER_TOKEN="$REVOKED" PATH="${MOCKBIN}:/usr/bin:/bin" \
  SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/soleur-doppler-token" \
  INNGEST_REARM_MODE=capture INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
  SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" bash "$REARM" </dev/null >/dev/null 2>&1 || rc=$?
if [[ -x /usr/bin/doppler || -x /bin/doppler ]]; then
  pass "C24 (skipped: a real doppler lives in /usr/bin or /bin on this host, so the binary-absent shape cannot be staged)"
  pass "C25 (skipped with C24)"
else
  assert_eq "C24 a missing doppler binary fails closed" "1" "$rc"
  assert_contains "C25 …and is classified binary_absent (rc=127), distinguishable from the SKIP seam" "$(cat "${MOCKBIN}/logger.log")" "rc=127 class=binary_absent"
fi
teardown
# unreadable: the third token_file state (mode 000; only stageable as non-root).
setup; write_token_file "$FRESH"; chmod 000 "${MOCKBIN}/soleur-doppler-token"
if (( EUID == 0 )); then
  pass "C26 (skipped: running as root, an unreadable file cannot be staged)"
  pass "C27 (skipped with C26)"
else
  rc=0; run_rearm_capture || rc=$?
  assert_eq "C26 an unreadable file fails closed on the env token" "1" "$rc"
  assert_contains "C27 …and the line says token_file=unreadable (a DAC/mount-namespace defect, not a delivery one)" "$(cat "${MOCKBIN}/logger.log")" "token_file=unreadable"
fi
chmod 600 "${MOCKBIN}/soleur-doppler-token"; teardown

# --- D. an EMPTY value in the file must not blank a working credential (the EnvironmentFile=- hole
#        ci-deploy's block closes; a bare `DOPPLER_TOKEN=` passes the installer's shape check) ---
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=\n' > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture "$FRESH" || rc=$?
assert_eq "D1 a bare DOPPLER_TOKEN= line does not blank a working env token (rc 0)" "0" "$rc"
assert_contains "D2 doppler still saw the working token" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
teardown
# A final line WITHOUT a trailing newline (a hand-delivered file) must still be read.
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=%s' "$FRESH" > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture || rc=$?
assert_eq "D3 a token on an unterminated final line is still read (the \`|| [[ -n \"\$k\" ]]\` keep)" "0" "$rc"
teardown
# CRLF: a `DOPPLER_TOKEN=\r` line is EMPTY, not a one-byte token — must not blank a working env token.
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=\r\n' > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture "$FRESH" || rc=$?
assert_eq "D4 a CRLF-terminated bare DOPPLER_TOKEN= does not blank a working env token (rc 0)" "0" "$rc"
teardown
# A CRLF-terminated REAL token is read with the CR stripped (the file was hand-delivered from Windows).
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=%s\r\n' "$FRESH" > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture || rc=$?
assert_eq "D5 a CRLF-terminated token is applied with the CR stripped (rc 0)" "0" "$rc"
teardown
# A QUOTED value (systemd EnvironmentFile accepts it; this parser deliberately does not) must be
# reported as present-but-not-applied, not as a revoked token.
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN="%s"\n' "$FRESH" > "${MOCKBIN}/soleur-doppler-token"
rc=0; run_rearm_capture || rc=$?
assert_eq "D6 a quoted token is not applied (fails closed on the env token)" "1" "$rc"
assert_contains "D7 …and the line says token_file=present token_applied=0 — a file-shape fix, not a rotation" "$(cat "${MOCKBIN}/logger.log")" "token_file=present token_applied=0"
teardown

# --- E. a hostile line is DATA, not code (parsed, not sourced) ---
setup; assert_fixture_dir "$MOCKBIN"; printf 'DOPPLER_TOKEN=%s\nSENTRY_PROJECT_ID=$(touch %s/PWNED)\n' "$FRESH" "$MOCKBIN" > "${MOCKBIN}/soleur-doppler-token"
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

# --- G. wiped-volume-verify: same class, same fix, same scrub ---
setup; write_token_file "$FRESH"
rc=0; run_wiped || rc=$?
assert_eq "G1 wiped-volume-verify arms its marker with the fresh token (rc 0)" "0" "$rc"
assert_contains "G2 doppler saw the FRESH token" "$(cat "${MOCKBIN}/doppler.log")" "DOPPLER_TOKEN_SEEN=$FRESH"
assert_contains "G3 the marker POST carried the Bearer secret doppler returned" "$(cat "${MOCKBIN}/curl.log")" "Bearer ${SECRET_VALUE}"
teardown
setup
rc=0; run_wiped || rc=$?
assert_eq "G4 …and still aborts no_secret when the file is absent and the env token is revoked" "1" "$rc"
LOG="$(cat "${MOCKBIN}/logger.log")"
assert_contains "G5 the abort reason is no_secret" "$LOG" "ABORT: no_secret"
assert_contains "G6 the doppler failure reason is logged there too, under the wiped tag" "$LOG" "-t inngest-wiped-volume-verify SOLEUR_DEPLOY_CRED_FAIL secret=INNGEST_MANUAL_TRIGGER_SECRET rc=1 class=invalid_auth token_file=absent token_applied=0"
assert_not_contains "G7 the wiped copy's log never carries the token (the scrub is pinned on BOTH copies, not inferred from A3b)" "$LOG" "$REVOKED"
assert_contains "G8 …and leaves the redaction marker" "$LOG" "dp.**.REDACTED"
assert_contains "G9 the reason reaches the wiped script's stderr too" "$(cat "${MOCKBIN}/wiped.err")" "ERROR: SOLEUR_DEPLOY_CRED_FAIL"
teardown

# --- H. #7797 hygiene the touched files now carry (paid down in this PR) ---
for f in "$REARM" "$WIPED"; do
  assert_code_match "H1 $(basename "$f") refuses xtrace (the \`*x*)\` arm exits 78 — a call form a comment cannot produce)" "$(cat "$f")" "^[[:space:]]*\*x\*\) .*refusing to run under xtrace.*exit 78 ;;$"
  # Each `curl` invocation (joined across its backslash continuations) that carries an
  # Authorization header must open `curl --disable --noproxy '*'` — the position is load-bearing.
  n_cred=$(code_of "$f" | sed -e ':a' -e '/\\$/N; s/\\\n//; ta' | grep -E '\bcurl\b.*Authorization: Bearer' | grep -c . || true)
  n_bad=$(code_of "$f" | sed -e ':a' -e '/\\$/N; s/\\\n//; ta' | grep -E '\bcurl\b.*Authorization: Bearer' | grep -vE "curl --disable --noproxy '\*' " | grep -c . || true)
  assert_eq "H2 $(basename "$f") every credentialed curl is transport-confined (--disable --noproxy '*'): $n_cred credentialed, $n_bad unconfined" "1" "$([[ "$n_cred" -ge 1 && "$n_bad" -eq 0 ]] && echo 1 || echo 0)"
done

# --- I. the ASSEMBLY equals the property: every webhook-executed script (hooks.json.tmpl
#        execute-command targets, plus ci-deploy.sh behind its wrapper) that reads Doppler
#        either carries the byte-identical refresh function or is ci-deploy.sh with its own
#        parsed block. A fourth doppler-reading hook script added tomorrow reddens this. ---
mapfile -t HOOK_SCRIPTS < <(grep -oE '"execute-command": "/usr/local/bin/[A-Za-z0-9._-]+\.sh"' "$HOOKS_TMPL" | grep -oE '[A-Za-z0-9._-]+\.sh' | sort -u)
HOOK_SCRIPTS+=("ci-deploy.sh")
assert_eq "I1 the hooks.json.tmpl enumeration is non-vacuous (>= 10 execute-command scripts)" "1" "$(( ${#HOOK_SCRIPTS[@]} >= 10 ? 1 : 0 ))"
readers=0; uncovered=""; covered_names=""
for s in "${HOOK_SCRIPTS[@]}"; do
  f="$SCRIPT_DIR/$s"; [[ -f "$f" ]] || continue
  if code_of "$f" | grep -E '\bdoppler (secrets (get|download)|run)\b' >/dev/null; then
    readers=$((readers + 1))
    if [[ "$s" == "ci-deploy.sh" ]]; then
      if grep -q '^if \[ -r /etc/default/soleur-doppler-token \]; then$' "$f"; then covered_names="$covered_names $s"; else uncovered="$uncovered $s"; fi
    else
      fn="$(extract_fn "$f" soleur_refresh_doppler_token)"
      if [[ -n "$fn" && "$fn" == "$FN_REARM" ]] && awk '/^read_secret\(\) \{$/,/^\}$/' "$f" | grep -E '^[[:space:]]*soleur_refresh_doppler_token[[:space:]]*$' >/dev/null; then covered_names="$covered_names $s"; else uncovered="$uncovered $s"; fi
    fi
  fi
done
assert_eq "I2 exactly three webhook-executed scripts read Doppler today (ci-deploy.sh, inngest-rearm-reminders.sh, inngest-wiped-volume-verify.sh) — a new member must be classified here, not silently admitted" "3" "$readers"
assert_eq "I3 every webhook-executed Doppler reader re-reads the re-delivered token (uncovered:${uncovered:- none}; covered:$covered_names)" "" "$uncovered"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact count, not a floor: a floor with slack equal to one section lets that section vanish
# green. Bump this in the same commit as any assertion change. Emitted directly (ADR-193), never
# through the helper it backstops.
EXPECTED_ASSERTIONS=82
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then printf 'assertion count drifted: %d != %d (update EXPECTED_ASSERTIONS in the same commit as the assertion change)\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS" >&2; exit 1; fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
