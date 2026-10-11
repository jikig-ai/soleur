#!/usr/bin/env bash
# Suite for scripts/audit-dev-scheduled-shapes.sh (#9995 Phase 3).
#
# PROPERTY. Every name in the soleur/dev_scheduled census is either shape-checked
# against its declared class or reported UNCLASSIFIED — never silently `ok`. A value
# failing its class (or the control-byte floor every name shares) prints a FAIL line
# NAMING the secret (never the value) and the run exits nonzero. An empty, unreadable,
# or wrongly-shaped census fails closed: "0 checked" can never exit 0.
#
# INSTRUMENT. The SUT runs as a child with PATH=shimdir:PATH; the `doppler` shim models
# `secrets --only-names --json` (census from MOCK_DIR/census.json, or rc 1 when
# MOCK_CENSUS_FAIL=1) and `secrets get NAME --plain` (value from MOCK_DIR/val_<NAME>,
# rc 1 when absent); every other argv is a hard stub error (rc 64). All values are
# SYNTHESIZED — none is a real credential shape, and no swept literal is assembled
# contiguously (the audit sweeps Doppler VALUES, but a repo-side token sweep must not
# join this file's fixtures to its population).
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/audit-dev-scheduled-shapes.sh"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_FAILS=1    # proven by the check immediately above (PASS==1 and FAIL==1 there)
FAIL=$(( FAIL - SELFTEST_FAILS ))

command -v openssl >/dev/null 2>&1 || { printf '[FATAL] openssl is required\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

TMPD="$(mktemp -d -t audit-dev-scheduled-shapes-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

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
SHIMDIR="$TMPD/shim"; MOCK_DIR="$TMPD/mock"
for d in "$SHIMDIR" "$MOCK_DIR"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
export MOCK_DIR

# --- doppler shim --------------------------------------------------------------------
# `secrets --only-names --json -p soleur -c dev_scheduled` -> MOCK_DIR/census.json
# (rc 1 when MOCK_CENSUS_FAIL=1). `secrets get NAME --plain` -> MOCK_DIR/val_<NAME>
# (rc 1 when absent). No token is ever logged; argv shape only.
cat > "$SHIMDIR/doppler" <<'SHIM'
#!/usr/bin/env bash
if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: Invalid Auth token\n' >&2; exit 1
fi
[[ "${1:-}" == "secrets" ]] || { echo "STUB ERROR: unexpected subcommand '$*'" >&2; exit 64; }
shift
sub=""; only=0; json=0; proj=""; cfg=""; plain=0; name=""
while (($#)); do
  case "$1" in
    get) sub=get ;;
    --only-names) only=1 ;;
    --json) json=1 ;;
    --plain) plain=1 ;;
    -p|--project) proj="${2:-}"; shift ;;
    -c|--config)  cfg="${2:-}"; shift ;;
    --no-check-version) ;;
    -*) echo "STUB ERROR: unexpected flag '$1'" >&2; exit 64 ;;
    *) name="$1" ;;
  esac
  shift
done
[[ "$proj" == soleur && "$cfg" == dev_scheduled ]] || { echo "STUB ERROR: scope p=$proj c=$cfg" >&2; exit 64; }
if [[ "$only" == 1 ]]; then
  [[ "$json" == 1 ]] || { echo "STUB ERROR: --only-names without --json" >&2; exit 64; }
  if [[ "${MOCK_CENSUS_FAIL:-0}" == 1 ]]; then
    printf 'Unable to fetch secret names\nDoppler Error: vendor outage\n' >&2; exit 1
  fi
  cat "$MOCK_DIR/census.json"; exit $?
fi
if [[ "$sub" == get ]]; then
  [[ "$plain" == 1 && -n "$name" ]] || { echo "STUB ERROR: get shape" >&2; exit 64; }
  if [[ -f "$MOCK_DIR/val_$name" ]]; then cat "$MOCK_DIR/val_$name"; exit 0; fi
  printf 'Unable to fetch secret\nDoppler Error: not found\n' >&2; exit 1
fi
echo "STUB ERROR: unmodelled argv" >&2; exit 64
SHIM
chmod +x "$SHIMDIR/doppler"

# census <json-pairs...> — writes MOCK_DIR/census.json from a JSON literal argument.
census() { printf '%s' "$1" > "$MOCK_DIR/census.json"; }
putval() { printf '%s' "$2" > "$MOCK_DIR/val_$1"; }   # name, value — value never a real secret

# run_sut <env-assignments...> bash scripts/audit-dev-scheduled-shapes.sh
run_sut() {
  OUT="$TMPD/out.txt"; ERR="$TMPD/err.txt"
  PATH="$SHIMDIR:$PATH" "$@" >"$OUT" 2>"$ERR"; RC=$?
}

# A real RSA key for the pem-class rows (synthetic; generated in the fixture dir).
openssl genrsa -out "$TMPD/key.pem" 2048 2>/dev/null

# ====================================================================================
echo "== audit-dev-scheduled-shapes.test.sh =="

# --- Guard-2 row 1: a CR byte inside a *_TOKEN value is named -------------------------
census '{"A_TOKEN":"computed","B_TOKEN":"computed"}'
printf 'abc\rdef' > "$MOCK_DIR/val_A_TOKEN"
putval B_TOKEN 'abc123_X.Y~+/=-'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "row1 nonzero on CR-corrupted token"; else fail "row1 rc=0"; fi
if grep -q 'name=A_TOKEN .*FAIL' "$OUT" || grep -q 'FAIL.*A_TOKEN' "$OUT"; then
  pass "row1 FAIL names A_TOKEN"
else
  fail "row1 no FAIL naming A_TOKEN (out: $(head -c 300 "$OUT"))"
fi
if ! grep -q 'abc' "$OUT"; then pass "row1 value never printed"; else fail "row1 printed the value"; fi
if grep -q 'name=B_TOKEN .*verdict=ok' "$OUT" || grep -q 'B_TOKEN.*ok' "$OUT"; then
  pass "row1 sibling B_TOKEN judged ok (no stop-at-first)"
else
  fail "row1 B_TOKEN verdict missing"
fi

# --- Guard-2 row 2: empty census fails closed ------------------------------------------
census '{}'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "row2 nonzero on empty census"; else fail "row2 rc=0 on empty census"; fi
if ! grep -q 'AUDIT_SUMMARY checked=0.*ok=0' "$OUT" || [[ "$RC" -ne 0 ]]; then
  pass "row2 no clean-zero green"
else
  fail "row2 printed a clean-zero pass"
fi

# --- Guard-2 row 3: compliant first, malformed second — FAIL names the second ----------
census '{"A_INSTALLATION_ID":"computed","B_INSTALLATION_ID":"computed"}'
putval A_INSTALLATION_ID '12345'
putval B_INSTALLATION_ID '12x'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "row3 nonzero"; else fail "row3 rc=0"; fi
if grep -q 'B_INSTALLATION_ID.*FAIL' "$OUT" || grep -q 'FAIL.*B_INSTALLATION_ID' "$OUT"; then
  pass "row3 FAIL names the second name"
else
  fail "row3 no FAIL naming B_INSTALLATION_ID"
fi
if grep -q 'A_INSTALLATION_ID.*ok' "$OUT"; then pass "row3 first name judged ok"; else fail "row3 first name missing ok"; fi

# --- Guard-2 row 4: unclassified name -> UNCLASSIFIED, not ok ---------------------------
census '{"ZZZ_MISC_VALUE":"computed"}'
putval ZZZ_MISC_VALUE 'somethingfreeform'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if grep -q 'ZZZ_MISC_VALUE.*UNCLASSIFIED' "$OUT"; then pass "row4 unclassified names verdict UNCLASSIFIED"; else fail "row4 verdict missing (out: $(head -c 300 "$OUT"))"; fi
if ! grep -q 'ZZZ_MISC_VALUE.*verdict=ok' "$OUT"; then pass "row4 unclassified is not ok"; else fail "row4 read UNCLASSIFIED as ok"; fi
if [[ "$RC" -eq 0 ]]; then pass "row4 unclassified alone does not fail the run"; else fail "row4 rc=$RC on unclassified-only census"; fi
if grep -q 'unclassified=1' "$OUT"; then pass "row4 summary counts unclassified"; else fail "row4 summary wrong"; fi

# --- Guard-2 row 5 (must-PASS): a *_B64 value in strict base64 alphabet -----------------
census '{"A_B64":"computed"}'
putval A_B64 'aGVsbG8gd29ybGQ='
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -eq 0 ]]; then pass "row5 clean census exits 0"; else fail "row5 rc=$RC"; fi
if grep -q 'A_B64.*verdict=ok' "$OUT" || grep -q 'A_B64.*ok' "$OUT"; then pass "row5 A_B64 ok"; else fail "row5 A_B64 not ok"; fi

# --- pem class: parseable RSA -> ok; garbage -> FAIL ------------------------------------
census '{"M_PEM":"computed","BAD_PEM":"computed","VAPID_PRIVATE_KEY":"computed"}'
cp "$TMPD/key.pem" "$MOCK_DIR/val_M_PEM"
putval BAD_PEM 'this is not a pem at all'
# A bare base64url blob (VAPID shape, measured live: 43 chars, alphabet-clean) is a
# second LEGAL *PRIVATE_KEY shape — the class guards parseability, not PEM wrapping.
putval VAPID_PRIVATE_KEY 'AbC123xYz-KeyBlob_43charsTotal.NoPemWrapxx='
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if grep -q 'M_PEM.*verdict=ok' "$OUT" || grep -q 'M_PEM.*ok' "$OUT"; then pass "pem parseable ok"; else fail "pem parseable not ok"; fi
if grep -q 'BAD_PEM.*FAIL' "$OUT"; then pass "pem garbage FAIL"; else fail "pem garbage not FAIL"; fi
if [[ "$RC" -ne 0 ]]; then pass "pem garbage nonzero"; else fail "pem garbage rc=0"; fi
if grep -q 'VAPID_PRIVATE_KEY.*verdict=ok' "$OUT"; then pass "pem-class bare key blob ok (VAPID shape)"; else fail "bare key blob under *PRIVATE_KEY not ok"; fi

# --- url class --------------------------------------------------------------------------
census '{"A_URL":"computed","B_URL":"computed"}'
putval A_URL 'postgres://db.example.co:5432/x'
putval B_URL 'notaurl'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if grep -q 'A_URL.*verdict=ok' "$OUT" || grep -q 'A_URL.*ok' "$OUT"; then pass "url scheme ok (non-https scheme accepted)"; else fail "url ok not detected"; fi
if grep -q 'B_URL.*FAIL' "$OUT"; then pass "url malformed FAIL"; else fail "url malformed not FAIL"; fi

# --- token alphabet permitted variants ----------------------------------------------------
census '{"GOOD_TOKEN":"computed","BAD_TOKEN":"computed"}'
putval GOOD_TOKEN 'AbC.123_def~g+h/i=-'
printf 'tok with space' > "$MOCK_DIR/val_BAD_TOKEN"
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if grep -q 'GOOD_TOKEN.*verdict=ok' "$OUT" || grep -q 'GOOD_TOKEN.*ok' "$OUT"; then pass "token RFC6750 alphabet ok"; else fail "token alphabet ok not detected"; fi
if grep -q 'BAD_TOKEN.*FAIL' "$OUT"; then pass "token interior-space FAIL"; else fail "token interior-space not FAIL"; fi

# --- fetch failure on an individual name ----------------------------------------------------
census '{"GHOST_TOKEN":"computed"}'
# no val_GHOST_TOKEN file — the get fails
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "unreadable name nonzero"; else fail "unreadable name rc=0"; fi
if grep -q 'GHOST_TOKEN.*FAIL' "$OUT" || grep -q 'FAIL.*GHOST_TOKEN' "$OUT"; then pass "unreadable name FAILed"; else fail "unreadable name not flagged"; fi

# --- census read failure ---------------------------------------------------------------------
MOCK_CENSUS_FAIL=1 run_sut env DOPPLER_TOKEN=stubtok MOCK_CENSUS_FAIL=1 bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "census read failure nonzero"; else fail "census read failure rc=0"; fi

# --- missing DOPPLER_TOKEN ---------------------------------------------------------------------
census '{"A_B64":"computed"}'
run_sut env -u DOPPLER_TOKEN bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "missing token nonzero"; else fail "missing token rc=0"; fi

# --- non-object census (envelope shape) ---------------------------------------------------------
printf '["A","B"]' > "$MOCK_DIR/census.json"
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "non-object census nonzero"; else fail "non-object census rc=0"; fi

# --- lowercase-keyed census (envelope, not names) -------------------------------------------------
census '{"names":["A_B64"],"success":true}'
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if [[ "$RC" -ne 0 ]]; then pass "lowercase-envelope census nonzero"; else fail "lowercase-envelope rc=0"; fi

# --- empty value ----------------------------------------------------------------------------------
census '{"E_TOKEN":"computed"}'
printf '' > "$MOCK_DIR/val_E_TOKEN"
run_sut env DOPPLER_TOKEN=stubtok bash "$SUT"
if grep -q 'E_TOKEN.*FAIL' "$OUT"; then pass "empty value FAIL"; else fail "empty value not FAIL"; fi
if [[ "$RC" -ne 0 ]]; then pass "empty value nonzero"; else fail "empty value rc=0"; fi

# --- xtrace refusal is UNCONDITIONAL (the script acquires values mid-run via get) -------------------
OUTX="$TMPD/outx.txt"; ERRX="$TMPD/errx.txt"
env DOPPLER_TOKEN=stubtok bash -x "$SUT" >"$OUTX" 2>"$ERRX"; RCX=$?
if [[ "$RCX" -eq 78 ]]; then pass "xtrace refusal rc=78"; else fail "xtrace rc=$RCX expected 78"; fi
# and with NO credentials bound it still refuses — the guard must not key on env
env -u DOPPLER_TOKEN bash -x "$SUT" >"$OUTX" 2>"$ERRX"; RCX=$?
if [[ "$RCX" -eq 78 ]]; then pass "xtrace refusal holds with empty env"; else fail "xtrace w/o env rc=$RCX expected 78"; fi

# ====================================================================================
TOTAL=$((PASS + FAIL))
printf '== %d/%d rows passed ==\n' "$PASS" "$TOTAL"
[[ "$FAIL" -eq 0 ]]
