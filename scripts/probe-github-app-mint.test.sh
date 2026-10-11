#!/usr/bin/env bash
# Suite for scripts/probe-github-app-mint.sh (#9995).
#
# PROPERTY. Given GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY in env, the probe signs a JWT and
# calls GET /app. HTTP 200 -> prints `GITHUB_APP_MINT status=200 slug=<slug> fp=<8>` and
# exits 0. ANYTHING else -- a valid but unregistered key (401), an empty/unset var, an
# unparseable PEM, a transport failure (curl rc!=0 / http_code 000) -- exits 1 with a
# ::error:: line and NEVER prints `GITHUB_APP_MINT`. A missing/invalid env makes ZERO
# requests: the curl shim's call count is asserted, not just the exit code.
#
# INSTRUMENT. Rows run the REAL script as a child process with PATH=shimdir:PATH so the
# `curl` the script (and the bearer-curl.sh library it sources) resolves is a shim that
# records each call (argv NUL-delimited, stdin verbatim) and answers from env
# (SHIM_CODE / SHIM_BODY / SHIM_RC). JWT rows decode the captured Bearer token's payload
# through python3 and assert `iss` equals the configured GITHUB_APP_ID. Every credential
# is SYNTHESIZED (openssl genrsa in the fixture dir); no value is ever printed.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/probe-github-app-mint.sh"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both helpers once; refuse to continue unless both moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_FAILS=1    # proven by the check immediately above (PASS==1 and FAIL==1 there)
FAIL=$(( FAIL - SELFTEST_FAILS ))

command -v openssl >/dev/null 2>&1 || { printf '[FATAL] openssl is required\n' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 is required (JWT payload decode)\n' >&2; exit 2; }

TMPD="$(mktemp -d -t probe-github-app-mint-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
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
SHIMDIR="$TMPD/shim"; CALLS="$TMPD/calls"
for d in "$SHIMDIR" "$CALLS"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
export CALLS_DIR="$CALLS"

# --- curl shim ---------------------------------------------------------------------
# Records argv (NUL-delimited) and, when `--config -` is present (the bearer-curl.sh
# stdin channel), the config text. Answers: body then `\n` then SHIM_CODE (the probe
# appends its own `-w '\n%{http_code}'`), exit SHIM_RC.
cat > "$SHIMDIR/curl" <<'SHIM'
#!/usr/bin/env bash
n=$(( $(find "$CALLS_DIR" -name '*.argv' | wc -l) + 1 ))
printf '%s\0' "$@" > "$CALLS_DIR/$n.argv"
prev=""
for a in "$@"; do
  if [[ "$prev" == "--config" && "$a" == "-" ]]; then cat > "$CALLS_DIR/$n.stdin"; break; fi
  prev="$a"
done
printf '%s' "${SHIM_BODY:-}"
printf '\n%s' "${SHIM_CODE:-000}"
exit "${SHIM_RC:-0}"
SHIM
chmod +x "$SHIMDIR/curl"

# --- fixtures ----------------------------------------------------------------------
# A real RSA key (generated, synthetic — never a stored secret). PEM_NL holds the
# real-newline form; PEM_ESC the Doppler single-line literal-\n variant.
openssl genrsa -out "$TMPD/key.pem" 2048 2>/dev/null
PEM_NL="$(cat "$TMPD/key.pem")"
PEM_ESC="$(printf '%s' "$PEM_NL" | awk '{printf "%s\\n", $0}')"
EXPECTED_FP="$(printf '%s' "$PEM_NL" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-8)"

# run_sut <label> -- clears the call log, runs the SUT as a child under the shimmed
# PATH, captures stdout+stderr separately, leaves RC/OUT/ERR/NCALLS set.
run_sut() {
  rm -f "$CALLS_DIR"/*.argv "$CALLS_DIR"/*.stdin 2>/dev/null || true
  OUT="$TMPD/out.txt"; ERR="$TMPD/err.txt"
  PATH="$SHIMDIR:$PATH" "$@" >"$OUT" 2>"$ERR"; RC=$?
  NCALLS=$(find "$CALLS_DIR" -name '*.argv' | wc -l)
}

# jwt_iss -- decode the payload (2nd segment) of the Bearer JWT captured on the last
# call's stdin config; prints the iss string or nothing.
jwt_iss() {
  local last
  last=$(ls "$CALLS_DIR"/*.stdin 2>/dev/null | sort -n | tail -1)
  [[ -n "$last" ]] || { echo ""; return 0; }
  local tok
  tok=$(sed -n 's/^header = "Authorization: Bearer \([^"]*\)"$/\1/p' "$last" | head -1)
  [[ -n "$tok" ]] || { echo ""; return 0; }
  TOK="$tok" python3 - <<'PY'
import base64, json, os
tok = os.environ["TOK"]
seg = tok.split(".")[1]
seg += "=" * (-len(seg) % 4)
try:
    print(json.loads(base64.urlsafe_b64decode(seg)).get("iss", ""))
except Exception:
    print("")
PY
}

# ====================================================================================
echo "== probe-github-app-mint.test.sh =="

# --- Guard-1 row 1: a valid RSA PEM not registered on the app (today's live state) ---
# GitHub answers 401 -> exit 1, ::error:: names the status AND the fingerprint (the same
# fp the CI leg logs as pemFingerprint); a request WAS made (the credential was present).
run_sut env GITHUB_APP_ID=3261325 GITHUB_APP_PRIVATE_KEY="$PEM_NL" \
  SHIM_CODE=401 SHIM_BODY='{"message":"A JSON web token could not be decoded"}' \
  bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "row1 exit 1 on 401"; else fail "row1 rc=$RC expected 1"; fi
if grep -q '::error::' "$ERR" && grep -q 'status=401' "$ERR"; then
  pass "row1 ::error:: names status=401"
else
  fail "row1 missing ::error:: status=401 (err: $(head -c 200 "$ERR"))"
fi
if grep -q "fp=$EXPECTED_FP" "$ERR"; then pass "row1 error carries fp=$EXPECTED_FP"; else fail "row1 error missing fp=$EXPECTED_FP"; fi
if ! grep -q 'GITHUB_APP_MINT' "$OUT"; then pass "row1 no MINT line on failure"; else fail "row1 printed MINT on failure"; fi
if [[ "$NCALLS" -ge 1 ]]; then pass "row1 request attempted (ncalls=$NCALLS)"; else fail "row1 zero requests"; fi
ISS="$(jwt_iss)"
if [[ "$ISS" == "3261325" ]]; then pass "row1 JWT iss=3261325 on the wire"; else fail "row1 JWT iss='$ISS' expected 3261325"; fi
# The token must travel on the stdin config, never in argv (ADR-280).
if ! grep -rqa 'Authorization' "$CALLS_DIR"/*.argv; then pass "row1 no Authorization in curl argv"; else fail "row1 Authorization leaked into argv"; fi

# --- Guard-1 row 2: GITHUB_APP_PRIVATE_KEY unset --------------------------------------
run_sut env GITHUB_APP_ID=3261325 SHIM_CODE=200 SHIM_BODY='{"slug":"x"}' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "row2 exit 1 on unset key"; else fail "row2 rc=$RC expected 1"; fi
if [[ "$NCALLS" -eq 0 ]]; then pass "row2 zero requests (unset env must not reach curl)"; else fail "row2 made $NCALLS requests"; fi

# --- Guard-1 row 3: appId-vs-key mismatch --------------------------------------------
# A compliant second credential shape: valid key, but GITHUB_APP_ID names another app —
# GitHub answers 401 and the wire must carry the MISMATCHED iss (the probe does not
# silently substitute an id of its own).
run_sut env GITHUB_APP_ID=999999999 GITHUB_APP_PRIVATE_KEY="$PEM_NL" \
  SHIM_CODE=401 SHIM_BODY='{}' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "row3 exit 1 on id/key mismatch"; else fail "row3 rc=$RC expected 1"; fi
ISS="$(jwt_iss)"
if [[ "$ISS" == "999999999" ]]; then pass "row3 JWT carried the configured (wrong) iss"; else fail "row3 JWT iss='$ISS'"; fi

# --- Guard-1 row 4: curl-status-000 stub (transport dead) -----------------------------
run_sut env GITHUB_APP_ID=3261325 GITHUB_APP_PRIVATE_KEY="$PEM_NL" \
  SHIM_CODE=000 SHIM_RC=7 SHIM_BODY='' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "row4 exit 1 on curl rc=7/000"; else fail "row4 rc=$RC expected 1"; fi
if ! grep -q 'GITHUB_APP_MINT' "$OUT"; then pass "row4 no MINT line"; else fail "row4 printed MINT on transport failure"; fi

# --- Guard-1 row 5 (must-PASS): PEM stored with literal \n escapes still mints --------
run_sut env GITHUB_APP_ID=3261325 GITHUB_APP_PRIVATE_KEY="$PEM_ESC" \
  SHIM_CODE=200 SHIM_BODY='{"slug":"soleur-ci-fixture"}' bash "$SUT"
if [[ "$RC" -eq 0 ]]; then pass "row5 exit 0 on escaped-newline PEM"; else fail "row5 rc=$RC (err: $(head -c 200 "$ERR"))"; fi
if grep -q 'GITHUB_APP_MINT status=200 slug=soleur-ci-fixture' "$OUT"; then
  pass "row5 MINT line names slug=soleur-ci-fixture"
else
  fail "row5 MINT line wrong (out: $(head -c 200 "$OUT"))"
fi
# fp is of the EXPANDED value — the form github-app.ts's pemFingerprint hashes —
# so row5's fp equals EXPECTED_FP even though the env carried the escaped variant.
if grep -q "fp=$EXPECTED_FP" "$OUT"; then pass "row5 fp=$EXPECTED_FP pins the expanded form"; else fail "row5 fp missing/wrong"; fi
ESC_FP="$(printf '%s' "$PEM_ESC" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-8)"
if [[ "$ESC_FP" != "$EXPECTED_FP" ]]; then pass "row5 fixture sound: env-form fp differs ($ESC_FP) — hashing the env form would silently diverge"; else fail "row5 fixture vacuous: escaped and plain PEM share fp"; fi

# --- Missing GITHUB_APP_ID ------------------------------------------------------------
run_sut env GITHUB_APP_PRIVATE_KEY="$PEM_NL" SHIM_CODE=200 SHIM_BODY='{}' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "missing ID exit 1"; else fail "missing ID rc=$RC"; fi
if [[ "$NCALLS" -eq 0 ]]; then pass "missing ID zero requests"; else fail "missing ID made $NCALLS requests"; fi

# --- Non-numeric GITHUB_APP_ID ---------------------------------------------------------
run_sut env GITHUB_APP_ID="abc" GITHUB_APP_PRIVATE_KEY="$PEM_NL" SHIM_CODE=200 SHIM_BODY='{}' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "non-numeric ID exit 1"; else fail "non-numeric ID rc=$RC"; fi
if [[ "$NCALLS" -eq 0 ]]; then pass "non-numeric ID zero requests"; else fail "non-numeric ID made $NCALLS requests"; fi

# --- Unparseable PEM (not an RSA key at all) -------------------------------------------
run_sut env GITHUB_APP_ID=3261325 GITHUB_APP_PRIVATE_KEY="this is not a pem" \
  SHIM_CODE=200 SHIM_BODY='{}' bash "$SUT"
if [[ "$RC" -eq 1 ]]; then pass "garbage PEM exit 1"; else fail "garbage PEM rc=$RC"; fi
if [[ "$NCALLS" -eq 0 ]]; then pass "garbage PEM zero requests (rsa -check gate)"; else fail "garbage PEM made $NCALLS requests"; fi

# --- xtrace refusal with live creds -----------------------------------------------------
OUTX="$TMPD/outx.txt"; ERRX="$TMPD/errx.txt"
env GITHUB_APP_ID=3261325 GITHUB_APP_PRIVATE_KEY="$PEM_NL" bash -x "$SUT" >"$OUTX" 2>"$ERRX"; RCX=$?
if [[ "$RCX" -eq 78 ]]; then pass "xtrace refusal rc=78"; else fail "xtrace rc=$RCX expected 78"; fi
if grep -q 'refusing to trace' "$ERRX"; then pass "xtrace refusal names the class"; else fail "xtrace refusal silent"; fi
# The JWT must never appear in the trace (the refusal fires before signing).
if ! grep -q 'BEGIN RSA' "$ERRX"; then pass "xtrace trace carries no PEM"; else fail "xtrace leaked PEM into trace"; fi

# ====================================================================================
TOTAL=$((PASS + FAIL))
printf '== %d/%d rows passed ==\n' "$PASS" "$TOTAL"
[[ "$FAIL" -eq 0 ]]
