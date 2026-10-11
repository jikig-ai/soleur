#!/usr/bin/env bash
# Tests for the R2 probe PUT in apps/cla-evidence/infra/bootstrap.sh (#9756). RED-first per
# cq-write-failing-tests-before. bootstrap.sh had no owning suite; this one executes the REAL
# script, under PATH stubs, as far as the Step 1 probe and stops there (the stub answers the probe
# with a 500, so the script exits at "Refusing to push known-broken creds" before any Doppler write).
#
# The recording `curl` stub answers ONLY the two URLs it is scripted for (the Cloudflare token
# verify and the R2 probe) and exits 99 on any other, drains stdin unconditionally, and exits 99 on
# the probe call when stdin carries no `user = "` line. `terraform`, `doppler` and `gh` record every
# call. `jq` is real. Fixture credentials are synthesized at run time; nothing here prints a value.
#
# Rows: (1) a valid pair — the recorded URL list is exactly [verify, probe] (the positive control
# for row 2), the probe's argv holds neither value, its stdin carries the user line, no Doppler
# write follows the 500; (2) a malformed pair — non-zero exit, the marker once, URL list exactly
# [verify]; (3) `bash -x` exits 78 before any stub is called; (4) the probe body file is a mktemp
# file that is gone afterwards.
# shellcheck disable=SC2166  # `test a -a b` keeps each row one predicate; every operand is a quoted scalar
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$(cd "$SCRIPT_DIR/../infra" && pwd)/bootstrap.sh"

TMP_ROOT=$(mktemp -d -t bootprobetest.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (comments stripped). Edit there, then re-sync here.
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
assert_fixture_dir "$TMP_ROOT"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Instrument self-test: drive both helpers before any real case. Reports with printf + exit,
# never through the helpers it guards.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0

t() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
_not() { ! "$@"; }

# Dispatcher self-test: every real row goes through t (and many through _not); drive both once in both
# directions so a rewritten t/_not that always passes cannot hide behind intact pass/fail counters.
_p0=$passes; _f0=$fails
t "dispatcher self-test (t pass path)" true
t "dispatcher self-test (t fail path — expected, subtracted)" false
t "dispatcher self-test (_not pass path)" _not false
t "dispatcher self-test (_not fail path — expected, subtracted)" _not true
if [[ "$passes" -ne $((_p0 + 2)) || "$fails" -ne $((_f0 + 2)) ]]; then
  printf 'FATAL: the t/_not dispatchers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=$((passes - 2)); fails=$((fails - 2))

echo "bootstrap-r2-probe.test.sh"

[[ -f "$BOOT" ]] || { echo "  FAIL: $BOOT missing"; echo "0 passed, 1 failed"; exit 1; }
for tool in jq od tr timeout; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL: $tool not on PATH — a missing tool is a hard FAIL, not a skip"; exit 1; }
done

# ── Synthesized fixtures ─────────────────────────────────────────────────────
rand_hex() { od -An -N"$(( $1 / 2 ))" -tx1 /dev/urandom | tr -d ' \n'; }
while :; do
  ID="$(rand_hex 32)"; SECRET="$(rand_hex 64)"
  [[ "${#ID}" -eq 32 && "${#SECRET}" -eq 64 ]] || continue
  [[ "$SECRET" != *"$ID"* && "$ID" != *"$SECRET"* ]] || continue
  break
done
ACCT="$(rand_hex 32)"
CF_TOKEN="$(rand_hex 40)"
BUCKET=soleur-cla-evidence

BIN="$TMP_ROOT/bin"; LOGD="$TMP_ROOT/log"; RUNTMP="$TMP_ROOT/runtmp"
assert_fixture_dir "$BIN"; assert_fixture_dir "$LOGD"; assert_fixture_dir "$RUNTMP"
mkdir -p "$BIN" "$LOGD" "$RUNTMP"

# ── Stubs (quoted heredocs: nothing expands at write time; values arrive by env at run time) ──
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
log="${STUB_LOG:?}"
url="${*: -1}"
printf '%s\n' "$url" >> "$log/urls"
{ printf 'CALL %s\n' "$url"; printf '%s\n' "$@"; } >> "$log/curl.argv"
stdin=$(cat; printf x); stdin=${stdin%x}
printf 'CALL %s\n%s' "$url" "$stdin" >> "$log/curl.stdin"
case "$url" in
  https://api.cloudflare.com/client/v4/user/tokens/verify)
    printf '{"result":{"status":"active","id":"stub-token-id"}}'
    exit 0 ;;
  "https://${STUB_ACCT:?}.r2.cloudflarestorage.com/${STUB_BUCKET:?}/bootstrap-probe/"*)
    [[ "$stdin" == *'user = "'* ]] || { echo "stub: probe stdin carries no user line" >&2; exit 99; }
    prev=""
    for a in "$@"; do
      if [[ "$prev" == "-o" ]]; then printf '%s\n' "$a" >> "$log/probe.outpath"; printf '<Error><Code>InternalError</Code></Error>' > "$a"; fi
      prev="$a"
    done
    [[ "${STUB_PROBE_FAIL:-0}" != 1 ]] || exit 7
    printf '%s' "${STUB_PROBE_CODE:-500}"
    exit 0 ;;
  *) echo "stub: unscripted URL" >&2; exit 99 ;;
esac
EOF
cat > "$BIN/terraform" <<'EOF'
#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >> "${STUB_LOG:?}/calls"
if [[ "${1:-}" == output && "${2:-}" == -raw ]]; then
  case "${3:-}" in
    bucket_name) printf '%s' "${STUB_BUCKET:?}" ;;
    bucket_endpoint) printf 'https://%s.r2.cloudflarestorage.com' "${STUB_ACCT:?}" ;;
    *) printf 'stub-%s' "${3:-}" ;;
  esac
fi
exit 0
EOF
cat > "$BIN/doppler" <<'EOF'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "${STUB_LOG:?}/calls"
printf 'doppler %s\n' "$*" >> "${STUB_LOG:?}/doppler.calls"
stdin=$(cat; printf x); stdin=${stdin%x}
if [[ "${1:-}" == secrets && "${2:-}" == set ]]; then
  printf 'SET %s <<%s>>\n' "${3:-}" "$stdin" >> "${STUB_LOG:?}/doppler.stdin"
fi
if [[ "${1:-}" == secrets && "${2:-}" == get ]]; then
  case "${3:-}" in
    CF_ACCOUNT_ID) printf '%s' "${STUB_ACCT:?}" ;;
    *) printf 'stub-%s' "${3:-}" ;;
  esac
fi
# Step 2 lists configs (jq reads it) and Step 3 mints the service token: fail THAT call so the script
# stops right after Step 2, before anything that would run the real live Lock Rules check.
if [[ "${1:-}" == configs && "${2:-}" == tokens && "${3:-}" == create ]]; then exit 1; fi
if [[ "${1:-}" == configs && "${2:-}" != create && "${2:-}" != tokens ]]; then printf '[]'; fi
if [[ "${1:-}" == configs && "${2:-}" == tokens && "${3:-}" != create ]]; then printf '[]'; fi
exit 0
EOF
for tool in gh openssl; do
  cat > "$BIN/$tool" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${STUB_LOG:?}/calls"
exit 0
EOF
done
chmod +x "$BIN"/*

export STUB_LOG="$LOGD" STUB_ACCT="$ACCT" STUB_BUCKET="$BUCKET"

reset_log() { rm -rf -- "$LOGD" "$RUNTMP"; mkdir -p "$LOGD" "$RUNTMP"; : > "$LOGD/doppler.stdin"; : > "$LOGD/calls"; : > "$LOGD/urls"; : > "$LOGD/curl.argv"; : > "$LOGD/curl.stdin"; : > "$LOGD/doppler.calls"; : > "$LOGD/probe.outpath"; }

# run_boot ID SECRET [bash flags...] — runs the real bootstrap.sh; stdout+stderr in $OUT, status in $RC.
OUT=""; RC=0
run_boot() {
  local id="$1" secret="$2"; shift 2
  RC=0
  OUT=$(PATH="$BIN:$PATH" TMPDIR="$RUNTMP" CF_ADMIN_TOKEN_BOOTSTRAP="$CF_TOKEN" \
        R2_S3_ACCESS_KEY_ID="$id" R2_S3_SECRET_ACCESS_KEY="$secret" \
        timeout 60 bash "$@" "$BOOT" </dev/null 2>&1) || RC=$?
}

normalized_urls() { sed "s#/bootstrap-probe/.*#/bootstrap-probe/<ts>.json#; s#https://${ACCT}\\.#https://<acct>.#" "$LOGD/urls"; }
VERIFY_URL='https://api.cloudflare.com/client/v4/user/tokens/verify'
PROBE_URL_N="https://<acct>.r2.cloudflarestorage.com/${BUCKET}/bootstrap-probe/<ts>.json"

# ── Row 1: a valid pair; the probe answers 500 ──────────────────────────────
reset_log
run_boot "$ID" "$SECRET"
t "1.1 valid pair: the script stops at the probe (exit 1, the refusal message names status=500)" \
  test "$RC" -eq 1 -a "$(grep -cF 'status=500' <<<"$OUT" || true)" -ge 1
t "1.2 valid pair: the recorded URL list is exactly [verify, probe] (the positive control for row 2.2)" \
  test "$(normalized_urls)" = "$(printf '%s\n%s' "$VERIFY_URL" "$PROBE_URL_N")"
probe_argv="$(awk '/^CALL /{on = (index($0, "bootstrap-probe") > 0)} on' "$LOGD/curl.argv")"
probe_stdin="$(awk '/^CALL /{on = (index($0, "bootstrap-probe") > 0); next} on' "$LOGD/curl.stdin")"
t "1.3 valid pair: the probe call's argv was recorded (non-empty, carries --aws-sigv4)" \
  grep -qxF -- '--aws-sigv4' <<<"$probe_argv"
t "1.4 valid pair: the probe's recorded argv holds neither the key id nor the secret" \
  _not grep -qF -e "$ID" -e "$SECRET" <<<"$probe_argv"
t "1.5 valid pair: the probe's recorded stdin carries the user config line" \
  grep -qxF "user = \"$ID:$SECRET\"" <<<"$probe_stdin"
t "1.6 valid pair: neither value is printed to the operator terminal" _not grep -qF -e "$ID" -e "$SECRET" <<<"$OUT"
t "1.7 valid pair: no Doppler write follows the 500 (the reads before the probe were recorded, no set/configs/tokens call)" \
  test "$(grep -c '^doppler secrets get ' "$LOGD/doppler.calls" || true)" -ge 1 -a "$(grep -cE 'secrets set|configs|tokens' "$LOGD/doppler.calls" || true)" -eq 0
outpath="$(head -n 1 "$LOGD/probe.outpath")"
t "1.8 the probe body file is a mktemp file under TMPDIR, not the fixed /tmp/r2-probe-body" \
  test -n "$outpath" -a "$outpath" != /tmp/r2-probe-body -a "${outpath#"$RUNTMP"/}" != "$outpath"
t "1.9 the probe body file is gone afterwards (the scratch TMPDIR is empty)" test -z "$(ls -A "$RUNTMP")"

# ── Row 2: a malformed pair (a control byte in the secret, length still 64) ──
reset_log
bad_secret="${SECRET:0:10}"$'\x01'"${SECRET:11}"
run_boot "$ID" "$bad_secret"
t "2.1 malformed secret: the script exits 2 (the pre-judge, not the probe's exit 1)" test "$RC" -eq 2
t "2.2 malformed secret: the recorded URL list is exactly [verify] (no probe request was made)" \
  test "$(normalized_urls)" = "$VERIFY_URL"
t "2.3 malformed secret: the marker is printed exactly once with reason=control_char" \
  test "$(grep -c '^SOLEUR_CREDENTIAL_REFUSED script=bootstrap reason=control_char$' <<<"$OUT" || true)" -eq 1
t "2.3b malformed secret: the annotation names the variable the operator set (R2_S3_SECRET_ACCESS_KEY), not a cla-evidence one" \
  test "$(grep -c '^::error::bootstrap: R2_S3_SECRET_ACCESS_KEY unusable$' <<<"$OUT" || true)" -eq 1 -a "$(grep -c 'R2_CLA_EVIDENCE_SECRET' <<<"$OUT" || true)" -eq 0
t "2.4 malformed secret: no value is printed" _not grep -qF -e "$ID" -e "$bad_secret" -e "$SECRET" <<<"$OUT"
t "2.5 malformed secret: no Doppler write" _not grep -qE 'secrets set|configs|tokens' "$LOGD/doppler.calls"
t "2.6 malformed secret: the scratch TMPDIR is empty afterwards" test -z "$(ls -A "$RUNTMP")"

# ── Row 4: a transport failure (curl exits 7, prints nothing) reads as status 000, never as success ──
reset_log
STUB_PROBE_FAIL=1 run_boot "$ID" "$SECRET"
t "4.1 curl failure: exit 1 and the refusal message names status=000" \
  test "$RC" -eq 1 -a "$(grep -cF 'status=000' <<<"$OUT" || true)" -ge 1
t "4.2 curl failure: the direct-egress hint is printed" test "$(grep -cF 'direct egress to R2' <<<"$OUT" || true)" -ge 1
t "4.3 curl failure: no Doppler write follows" _not grep -qE 'secrets set|configs|tokens' "$LOGD/doppler.calls"
t "4.4 curl failure: the URL list is exactly [verify, probe] (the request WAS attempted)" \
  test "$(normalized_urls)" = "$(printf '%s\n%s' "$VERIFY_URL" "$PROBE_URL_N")"

# ── Row 5: the probe passes (200), so Step 2 runs: the pair reaches Doppler on STDIN, never on argv ──
reset_log
STUB_PROBE_CODE=200 run_boot "$ID" "$SECRET"
t "5.1 probe ok: the script reaches Step 2 and stops at the (stubbed) service-token mint (exit 1)" test "$RC" -eq 1
t "5.2 Step 2 wrote the key id and the secret as single-name stdin writes (NAME on argv, no =value)" \
  test "$(grep -cE '^doppler secrets set R2_CLA_EVIDENCE_ACCESS_KEY_ID --project' "$LOGD/doppler.calls" || true)" -eq 1 \
    -a "$(grep -cE '^doppler secrets set R2_CLA_EVIDENCE_SECRET --project' "$LOGD/doppler.calls" || true)" -eq 1
t "5.3 neither value appears on ANY doppler argv" _not grep -qF -e "$ID" -e "$SECRET" "$LOGD/doppler.calls"
t "5.4 each value arrived on stdin exactly" \
  test "$(grep -cxF "SET R2_CLA_EVIDENCE_ACCESS_KEY_ID <<$ID>>" "$LOGD/doppler.stdin" || true)" -eq 1 \
    -a "$(grep -cxF "SET R2_CLA_EVIDENCE_SECRET <<$SECRET>>" "$LOGD/doppler.stdin" || true)" -eq 1
t "5.5 the non-secret endpoint and bucket still go as NAME=value arguments" \
  test "$(grep -cE 'R2_CLA_EVIDENCE_ENDPOINT=https://.*R2_CLA_EVIDENCE_BUCKET=' "$LOGD/doppler.calls" || true)" -eq 1
t "5.6 neither value is printed to the operator terminal" _not grep -qF -e "$ID" -e "$SECRET" <<<"$OUT"

# ── Row 3: xtrace is refused before any stub runs ───────────────────────────
reset_log
run_boot "$ID" "$SECRET" -x
t "3.1 bash -x: exit 78 (the unconditional xtrace refusal)" test "$RC" -eq 78
t "3.2 bash -x: no stub was called (no curl, terraform, doppler, gh or openssl call recorded)" \
  test ! -s "$LOGD/calls" -a ! -s "$LOGD/urls"
t "3.3 bash -x: neither value reaches the trace" _not grep -qF -e "$ID" -e "$SECRET" <<<"$OUT"

# SELFTEST_PASSES is a LITERAL on the line directly above its use: guard-vacuity-floor.test.sh slices
# the floor plus its contiguous assignments, and the self-test above asserts passes == 1.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=29
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
if [[ "$fails" -eq 0 ]]; then
  echo "ALL bootstrap R2 probe tests passed."
fi
[[ "$fails" -eq 0 ]] || exit 1
