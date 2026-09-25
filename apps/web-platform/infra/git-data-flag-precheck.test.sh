#!/usr/bin/env bash
#
# git-data-flag-precheck.sh — Guard 1 of #8189: the flag read fails closed and stays away from
# host bytes.
#
# Property: no run of git-data-cutover.yml reaches the bridge unless the GIT_DATA_STORE_ENABLED
# read succeeded and the value is not exactly `true`, and the `prd` read token
# (DOPPLER_TOKEN_PRD) is bound in no step other than the flag precheck.
#
# Host-key pin (#7226, plan D3): the same step reads GIT_DATA_SSH_HOST_KEY, validates the ED25519
# shape, writes $RUNNER_TEMP/git-data.pin and prints only its SHA256 fingerprint. An absent,
# invalid or unreadable pin refuses with verdict=git_data_host_key_unavailable reason=<word> (an
# unreadable one through the flag read's own classifier: reason=<auth_invalid|...> rc=<n>). An
# informational `TOFU_ARM present|absent|unknown` line reads the file GIT_AUTH_TS_PATH names
# (fixtures here; one row runs the default path in a mirrored tree) for the accept-new ssh option
# itself, not for a constant's name. Every fixture that must carry that option builds it by
# concatenation (TOFU_OPT below), so this suite is not itself a tests/scripts/test-no-tofu-ssh.sh hit.
#
# The script is driven through a PER-NAME Doppler shim that answers per project/config/secret
# AND per --no-exit-on-missing-secret presence, mirroring the measured CLI v3.75.3 semantics
# recorded in the script's header. The workflow is parsed as YAML (`on:` via the True-key lookup).
#
# Harness conventions (plan › Guard Contract): each matrix row runs as a MUTANT through mutate()
# (copy, sed the copy, assert the edit landed on the expected diff-line count, point the suite's
# override at the copy, require the NAMED case RED). Floors are reported with printf + exit.
#
# Seams of the SUITE: GDC_PRECHECK (the script), GDC_WORKFLOW (git-data-cutover.yml).
#
# Run: bash apps/web-platform/infra/git-data-flag-precheck.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
PRECHECK="${GDC_PRECHECK:-$DIR/git-data-flag-precheck.sh}"
WF="${GDC_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
IV="$ROOT/.github/workflows/infra-validation.yml"

passes=0; fails=0; SKIPPED=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193).
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$PRECHECK" "$WF" "$IV"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/gdf-precheck.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
BIN="$T/bin"
mkdir -p "$BIN" "$T/mut" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data flag precheck (Guard 1, #8189) ===\n\n'

# Per-name Doppler shim. A store is $DOPPLER_STORE/<project>/<config>/<NAME>; a missing config
# directory is "nonexistent or unauthorized config" (exit 1 even with the flag). Every config also
# answers the reserved secrets DOPPLER_PROJECT / DOPPLER_CONFIG with its own project / config name
# (docs.doppler.com/docs/secrets › reserved secrets). SHIM_BOUND_PROJECT / SHIM_BOUND_CONFIG model a
# service token bound to ANOTHER config: the -p/-c the caller passes are not what gets read.
# SHIM_ERR forces one error class, with a canary in its text so a printed stderr is visible.
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$DOPPLER_LOG"
[ "${1:-}" = secrets ] && [ "${2:-}" = get ] || { echo "doppler-shim: unsupported: $*" >&2; exit 64; }
name="${3:-}"; shift 3
plain=0; noexit=0; proj=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plain) plain=1; shift ;;
    --no-exit-on-missing-secret) noexit=1; shift ;;
    -p|--project) proj="${2:-}"; shift 2 ;;
    -c|--config) cfg="${2:-}"; shift 2 ;;
    *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
# SHIM_PIN_ERR forces one error class on the pin read ONLY (the flag and scope reads succeed).
if [ "$name" = GIT_DATA_SSH_HOST_KEY ]; then
  case "${SHIM_PIN_ERR:-}" in
    auth)    echo "Doppler Error: Invalid Auth token STDERR-CANARY-3b" >&2; exit 1 ;;
    network) echo "Doppler Error: dial tcp: lookup api.doppler.com: i/o timeout STDERR-CANARY-3b" >&2; exit 3 ;;
  esac
fi
[ "${SHIM_SCOPE_ERROR:-0}" = 1 ] && { echo "Doppler Error: This token does not have access to requested config '$cfg' STDERR-CANARY-3b" >&2; exit 1; }
case "${SHIM_ERR:-}" in
  auth)    echo "Doppler Error: Invalid Auth token STDERR-CANARY-3b" >&2; exit 1 ;;
  network) echo "Doppler Error: Get \"https://api.doppler.com/v3/configs/config/secret\": dial tcp: lookup api.doppler.com: no such host STDERR-CANARY-3b" >&2; exit 1 ;;
  other)   echo "Doppler Error: something unforeseen STDERR-CANARY-3b" >&2; exit 2 ;;
esac
[ "$plain" = 1 ] || { echo "doppler-shim: --plain required" >&2; exit 64; }
proj="${SHIM_BOUND_PROJECT:-$proj}"; cfg="${SHIM_BOUND_CONFIG:-$cfg}"
d="$DOPPLER_STORE/$proj/$cfg"
if [ -z "$proj" ] || [ -z "$cfg" ] || [ ! -d "$d" ]; then echo "Doppler Error: Could not find requested config '$cfg' STDERR-CANARY-3b" >&2; exit 1; fi
case "$name" in
  DOPPLER_PROJECT) printf '%s' "$proj"; exit 0 ;;
  DOPPLER_CONFIG)  printf '%s' "$cfg"; exit 0 ;;
esac
if [ -f "$d/$name" ]; then cat "$d/$name"; exit 0; fi
# SHIM_IGNORE_FLAG models an argument-blind shim (or a CLI that ignores the flag).
if [ "$noexit" = 1 ] && [ "${SHIM_IGNORE_FLAG:-0}" != 1 ]; then exit 0; fi
echo "Doppler Error: Could not find requested secret: $name" >&2; exit 1
SHIM
chmod +x "$BIN/doppler" || { printf 'FAIL SETUP: chmod shim\n' >&2; exit 1; }

# Pin fixtures: a key generated at test time (never a real host key), its fingerprint as ssh-keygen
# prints it, and two git-auth.ts fixtures (with and without the shared fallback constant).
command -v ssh-keygen >/dev/null 2>&1 || { printf 'FAIL SETUP: ssh-keygen not found\n' >&2; exit 1; }
ssh-keygen -q -t ed25519 -N '' -C pin-fixture -f "$T/pinkey" || { printf 'FAIL SETUP: ssh-keygen pin\n' >&2; exit 1; }
PIN="$(cut -d' ' -f1,2 "$T/pinkey.pub")"
PIN_FP="$(ssh-keygen -lf "$T/pinkey.pub" | awk '{print $2}')"
case "$PIN_FP" in SHA256:*) : ;; *) printf 'FAIL SETUP: fixture fingerprint unreadable\n' >&2; exit 1 ;; esac
ssh-keygen -q -t ecdsa -b 256 -N '' -f "$T/ecdsakey" || { printf 'FAIL SETUP: ssh-keygen ecdsa\n' >&2; exit 1; }
ECDSA_PIN="$(cut -d' ' -f1,2 "$T/ecdsakey.pub")"
# One base64 character short, and a regex-valid body that is still 68 characters (shape-only).
PIN_SHORT="${PIN%?}"
TOFU_OPT="StrictHostKeyChecking=accept-""new"
printf 'const TOFU_FALLBACK_OPTS = ["-o", "%s"];\n' "$TOFU_OPT" > "$T/git-auth-tofu.ts"
printf 'export const PINNED_ONLY = true;\n' > "$T/git-auth-strict.ts"
# The constant's NAME without the option (a stale comment or a rename-in-progress) is not the arm.
printf '// TOFU_FALLBACK_OPTS was here\nexport const PINNED_ONLY = true;\n' > "$T/git-auth-name-only.ts"
# The option under a RENAMED constant, and in lower case: both are still the arm.
printf 'const UNPINNED_OPTS = ["-o", "%s"];\n' "$TOFU_OPT" > "$T/git-auth-renamed.ts"
printf 'const UNPINNED_OPTS = ["-o", "%s"];\n' "$(printf '%s' "$TOFU_OPT" | tr 'A-Z' 'a-z')" > "$T/git-auth-lower.ts"
# A mirrored checkout for the DEFAULT-path row: <tree>/apps/web-platform/{infra,server}, the same
# relative layout the script's default resolves against, so a mutant that miscounts the `..`
# lands on a path that does not exist instead of on the real checkout.
MIRROR="$T/tree/apps/web-platform"
mkdir -p "$MIRROR/infra" "$MIRROR/server" || { printf 'FAIL SETUP: mirror\n' >&2; exit 1; }
cp "$T/git-auth-tofu.ts" "$MIRROR/server/git-auth.ts" || { printf 'FAIL SETUP: mirror git-auth\n' >&2; exit 1; }

# run_case <name> <value|ABSENT> [VAR=value ...] — the flag's stored value (printf, no newline
# unless given), then the script (CASE_SCRIPT, default the real one). Sets OUT, RC, DLOG, CTMP
# (the case's own TMPDIR, so a leaked tempfile is visible) and RT (its RUNNER_TEMP). A store also
# carries soleur/prd_terraform (flag absent there) and other-project/prd, the two configs a
# mis-bound token would read. The pin stored in soleur/prd is CASE_PIN (default the valid fixture;
# ABSENT stores none), and GIT_AUTH_TS_PATH defaults to the fixture carrying the fallback constant.
run_case() {
  local name="$1" value="$2"; shift 2
  local store="$T/store-$name" pin="${CASE_PIN-$PIN}"
  assert_fixture_dir "$store"
  rm -rf "$store"; mkdir -p "$store/soleur/prd" "$store/soleur/prd_terraform" "$store/other-project/prd" || { printf 'FAIL SETUP: store\n' >&2; exit 1; }
  [ "$value" = ABSENT ] || printf '%s' "$value" > "$store/soleur/prd/GIT_DATA_STORE_ENABLED"
  [ "$pin" = ABSENT ] || printf '%s' "$pin" > "$store/soleur/prd/GIT_DATA_SSH_HOST_KEY"
  CTMP="$T/tmp-$name"; RT="$T/rt-$name"
  assert_fixture_dir "$CTMP"
  assert_fixture_dir "$RT"
  rm -rf "$CTMP" "$RT"; mkdir -p "$CTMP" "$RT" || { printf 'FAIL SETUP: case tmp\n' >&2; exit 1; }
  OUT="$T/$name.out"; DLOG="$T/$name.dlog"; : > "$DLOG"
  # CASE_DEFAULT_GIT_AUTH=1 leaves GIT_AUTH_TS_PATH genuinely UNSET (not empty).
  local gat=(GIT_AUTH_TS_PATH="$T/git-auth-tofu.ts")
  [ "${CASE_DEFAULT_GIT_AUTH:-0}" = 1 ] && gat=()
  timeout -k 3 30 env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$CTMP" DOPPLER_STORE="$store" DOPPLER_LOG="$DLOG" \
    RUNNER_TEMP="$RT" "${gat[@]}" \
    DOPPLER_TOKEN=fixture-prd-read "$@" bash "${CASE_SCRIPT:-$PRECHECK}" > "$OUT" 2>&1
  RC=$?
}
ARGV='doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd
doppler secrets get DOPPLER_PROJECT --plain -p soleur -c prd
doppler secrets get DOPPLER_CONFIG --plain -p soleur -c prd
doppler secrets get GIT_DATA_SSH_HOST_KEY --plain --no-exit-on-missing-secret -p soleur -c prd'
refusal() { # <verdict-detail> — the exact two-line output of a refusal
  printf '[git-data-flag-precheck] verdict=%s\n::error title=git-data-flag-precheck::verdict=%s' "$1" "$1"
}
TOFU_PRESENT='TOFU_ARM present
::warning title=git-data-flag-precheck::TOFU_ARM present - the app still carries the unpinned git-data fallback (#5914); it must be deleted before GIT_DATA_STORE_ENABLED is ever set'
# ok_out <flag-line> — the exact output of a clear run with the default fixtures.
ok_out() { printf '%s\ngit_data_pin=present fp=%s\n%s' "$TOFU_PRESENT" "$PIN_FP" "$1"; }
detail() { printf 'rc=%s out=[%s]' "$RC" "$(tr '\n' '|' < "$OUT" | sed 's/::/: :/g')"; }

# ── cases (functions, so a mutant re-runs exactly the case its row names) ──────────────
case_absent() {
  run_case absent ABSENT "$@"
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(ok_out flag=unset)" ]
}
case_scope_error() {
  run_case scope false SHIM_SCOPE_ERROR=1
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(refusal 'flag_read_failed reason=forbidden rc=1')" ]
}
case_token_absent() {
  run_case notoken false DOPPLER_TOKEN=
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(refusal flag_token_absent)" ] && [ ! -s "$DLOG" ]
}
case_reason() { # <label> <expected-word> <expected-rc> [VAR=value ...] — the word, never the stderr
  local label="$1" word="$2" rc="$3"; shift 3
  run_case "reason-$label" false "$@"
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(refusal "flag_read_failed reason=$word rc=$rc")" ] && ! grep -q 'CANARY' "$OUT"
}
case_scope_mismatch() { # <label> [VAR=value ...]
  local label="$1"; shift
  run_case "mismatch-$label" ABSENT "$@"
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(refusal 'flag_read_failed reason=scope_mismatch')" ]
}
case_true() {
  run_case "true$1" "$2"
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(refusal flag_already_true)" ]
}
case_off() { # <label> <value>
  run_case "off$1" "$2"
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(ok_out flag=off)" ]
}

if case_absent; then pass "P1: an absent flag (exit 0, empty stdout WITH the flag) prints exactly the TOFU_ARM line, the pin fingerprint and flag=unset, exit 0"
else fail "P1: an absent flag was not flag=unset" "$(detail)"; fi
if [ "$(cat "$DLOG")" = "$ARGV" ]; then pass "P1: doppler is called exactly four times — the flag read, DOPPLER_PROJECT, DOPPLER_CONFIG, then the pin read WITH --no-exit-on-missing-secret, all -p soleur -c prd"
else fail "P1: the doppler argv differs" "$(tr '\n' '|' < "$DLOG")"; fi
if [ -z "$(ls -A "$CTMP")" ]; then pass "P1: the stderr capture file is removed on exit (TMPDIR left empty)"
else fail "P1: a tempfile survived the run" "$(ls -A "$CTMP" | tr '\n' ' ')"; fi
if ! case_absent SHIM_IGNORE_FLAG=1 && [ "$RC" = 5 ] && grep -qF 'verdict=flag_read_failed' "$OUT"; then
  pass "H1: against a shim that exits non-zero on absent (ignores the flag) the absent case goes RED as flag_read_failed — the shim is flag-sensitive"
else fail "H1: the absent case did not react to a flag-blind shim" "$(detail)"; fi
if case_scope_error; then pass "P4/S2: a token without access to the config -> verdict=flag_read_failed reason=forbidden rc=1, exit 5 — never read as unset"
else fail "P4/S2: a scope error was not flag_read_failed reason=forbidden" "$(detail)"; fi
if [ -z "$(ls -A "$CTMP")" ]; then pass "P4/S2: the stderr capture file is removed on a refusal too"
else fail "P4/S2: a tempfile survived a refusal" "$(ls -A "$CTMP" | tr '\n' ' ')"; fi
if case_token_absent; then pass "P4b: an empty DOPPLER_TOKEN -> verdict=flag_token_absent, exit 5, doppler never called"
else fail "P4b: an empty token was not flag_token_absent before any doppler call" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_reason auth auth_invalid 1 SHIM_ERR=auth; then pass "C2a: 'Invalid Auth token' -> reason=auth_invalid, the stderr text never printed"
else fail "C2a: an invalid token was not reason=auth_invalid (or its stderr was printed)" "$(detail)"; fi
if case_reason config config_not_found 1 SHIM_BOUND_CONFIG=prd_missing; then pass "C2b: a config the token cannot find -> reason=config_not_found"
else fail "C2b: a missing config was not reason=config_not_found" "$(detail)"; fi
if case_reason network network 1 SHIM_ERR=network; then pass "C2c: a DNS/dial failure -> reason=network"
else fail "C2c: a network failure was not reason=network" "$(detail)"; fi
if case_reason other unknown 2 SHIM_ERR=other; then pass "C2d: unrecognized stderr -> reason=unknown, keeping doppler's rc (2)"
else fail "C2d: unrecognized stderr was not reason=unknown rc=2" "$(detail)"; fi
if case_scope_mismatch config SHIM_BOUND_CONFIG=prd_terraform; then pass "C2e: a token bound to soleur/prd_terraform (flag absent there) -> reason=scope_mismatch, never flag=unset"
else fail "C2e: a token bound to another config read the flag as unset" "$(detail)"; fi
if case_scope_mismatch project SHIM_BOUND_PROJECT=other-project; then pass "C2f: a token bound to another project's prd -> reason=scope_mismatch"
else fail "C2f: a token bound to another project was accepted" "$(detail)"; fi
if case_true plain true; then pass "P3/S3: exactly true -> verdict=flag_already_true, exit 5"
else fail "P3/S3: true was not refused" "$(detail)"; fi
if case_true nl $'true\n'; then pass "P3b: true with a trailing newline (as --plain may print) is still refused"
else fail "P3b: true + newline was not refused" "$(detail)"; fi
if case_off false false; then pass "P2: false -> exactly flag=off, exit 0"
else fail "P2: false was not flag=off" "$(detail)"; fi
if case_off upper TRUE; then pass "P5: TRUE is not true (the app compares === \"true\") -> flag=off"
else fail "P5: TRUE was not flag=off" "$(detail)"; fi
if case_off space 'true '; then pass "P5b: 'true ' (trailing space) is not true -> flag=off"
else fail "P5b: 'true ' was not flag=off" "$(detail)"; fi
if case_off canary 'off-CANARY-5d1e' && ! grep -q 'CANARY' "$OUT"; then pass "P6: the flag value itself is never printed"
else fail "P6: the flag value was printed" "out=[$(tr '\n' '|' < "$OUT")]"; fi
# ── host-key pin (#7226, plan D3) ─────────────────────────────────────────────────────
case_pin_ok() { # the pin file holds exactly the key line, read-only (0444); only its fingerprint is printed
  run_case pin-ok false
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(ok_out flag=off)" ] \
    && [ "$(cat "$RT/git-data.pin" 2>/dev/null)" = "$PIN" ] && ! grep -qF "${PIN#* }" "$OUT" \
    && [ "$(stat -c %a "$RT/git-data.pin" 2>/dev/null)" = 444 ]
}
case_pin_refused() { # <label> <reason> [VAR=value ...] — CASE_PIN set by the caller
  local label="$1" reason="$2"; shift 2
  run_case "pin-$label" false "$@"
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(printf '%s\n%s' "$TOFU_PRESENT" "$(refusal "git_data_host_key_unavailable reason=$reason")")" ] \
    && [ ! -e "$RT/git-data.pin" ] && ! grep -q 'CANARY' "$OUT"
}
case_tofu() { # <label> <git-auth-path> <expected-line>
  run_case "tofu-$1" false GIT_AUTH_TS_PATH="$2"
  [ "$RC" = 0 ] && [ "$(head -1 "$OUT")" = "$3" ] && ! grep -q '::warning' "$OUT"
}
if case_pin_ok; then pass "K1: a valid ED25519 pin -> \$RUNNER_TEMP/git-data.pin holds exactly the key line, mode 444; stdout carries its SHA256 fingerprint, never the key"
else fail "K1: a valid pin was not written read-only, or was printed raw" "$(detail) mode=$(stat -c %a "$RT/git-data.pin" 2>/dev/null) pin=[$(head -c 120 "$RT/git-data.pin" 2>/dev/null)]"; fi
if CASE_PIN=ABSENT case_pin_refused absent absent; then pass "K2: GIT_DATA_SSH_HOST_KEY absent (exit 0, empty WITH the flag) -> verdict=git_data_host_key_unavailable reason=absent, exit 5, no pin file"
else fail "K2: an absent pin was not refused as reason=absent" "$(detail)"; fi
if CASE_PIN=ABSENT case_pin_refused unreadable 'unknown rc=1' SHIM_IGNORE_FLAG=1; then pass "K3: a pin read that exits non-zero -> git_data_host_key_unavailable reason=unknown rc=1 (never absent, never flag_read_failed), stderr not printed"
else fail "K3: a failed pin read was not git_data_host_key_unavailable reason=unknown rc=1" "$(detail)"; fi
if case_pin_refused unreadable-auth 'auth_invalid rc=1' SHIM_PIN_ERR=auth; then pass "K3b: a pin read refused as 'Invalid Auth token' -> reason=auth_invalid rc=1, the flag read's own classifier"
else fail "K3b: a pin auth failure was not reason=auth_invalid rc=1" "$(detail)"; fi
if case_pin_refused unreadable-net 'network rc=3' SHIM_PIN_ERR=network; then pass "K3c: a pin read that times out -> reason=network, keeping doppler's rc (3)"
else fail "K3c: a pin network failure was not reason=network rc=3" "$(detail)"; fi
_inv_n=0
for spec in "ecdsa|$ECDSA_PIN" "short|$PIN_SHORT" "comment|$PIN pin@host-CANARY" "twolines|$PIN"$'\n'"$PIN" \
            "lead-space| $PIN" "marker|@cert-authority $PIN" "rsa|ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ-CANARY" "cr|$PIN"$'\r'; do
  _l="${spec%%|*}"
  if CASE_PIN="${spec#*|}" case_pin_refused "invalid-$_l" invalid; then _inv_n=$((_inv_n + 1))
  else fail "K4 ($_l): a malformed pin was not refused as reason=invalid" "$(detail)"; fi
done
if [ "$_inv_n" = 8 ]; then pass "K4: 8 malformed pins (ECDSA, truncated, trailing comment, two lines, leading space, marker, RSA, CR) -> reason=invalid, exit 5, no pin file, value never printed"
else fail "K4: only $_inv_n of 8 malformed pins were refused as reason=invalid"; fi
CASE_PIN="$PIN"$'\n' run_case pin-nl false
if [ "$RC" = 0 ] && [ "$(cat "$RT/git-data.pin" 2>/dev/null)" = "$PIN" ]; then pass "K5 (must-PASS): the pin as --plain prints it with a trailing newline is accepted"
else fail "K5: a pin with one trailing newline was refused" "$(detail)"; fi
case_tofu_present() {
  run_case tofu-present false GIT_AUTH_TS_PATH="$T/git-auth-tofu.ts"
  [ "$RC" = 0 ] && [ "$(head -2 "$OUT")" = "$TOFU_PRESENT" ]
}
if case_tofu_present; then pass "K6: git-auth.ts carrying TOFU_FALLBACK_OPTS -> TOFU_ARM present plus a ::warning naming #5914"
else fail "K6: the present fixture did not print TOFU_ARM present" "$(detail)"; fi
if case_tofu absent "$T/git-auth-strict.ts" "TOFU_ARM absent"; then pass "K7: git-auth.ts without the fallback constant -> TOFU_ARM absent, no warning"
else fail "K7: the strict fixture did not print TOFU_ARM absent" "$(detail)"; fi
if case_tofu missing "$T/no-such-git-auth.ts" "TOFU_ARM unknown"; then pass "K8: an unreadable git-auth.ts -> TOFU_ARM unknown (never absent)"
else fail "K8: an unreadable git-auth.ts was not TOFU_ARM unknown" "$(detail)"; fi
case_tofu_file() { # <label> <git-auth-path> — the probe reports present, with its warning
  run_case "tofu-$1" false GIT_AUTH_TS_PATH="$2"
  [ "$RC" = 0 ] && [ "$(head -2 "$OUT")" = "$TOFU_PRESENT" ]
}
if case_tofu_file renamed "$T/git-auth-renamed.ts"; then pass "K10: the accept-new option under a RENAMED constant -> TOFU_ARM present (the probe keys on the behaviour, not the name)"
else fail "K10: a renamed constant carrying the option was not TOFU_ARM present" "$(detail)"; fi
if case_tofu_file lower "$T/git-auth-lower.ts"; then pass "K10b: the option in lower case (ssh reads option names case-insensitively) -> TOFU_ARM present"
else fail "K10b: the lower-case option was not TOFU_ARM present" "$(detail)"; fi
if case_tofu name-only "$T/git-auth-name-only.ts" "TOFU_ARM absent"; then pass "K10c: the constant's NAME without the option -> TOFU_ARM absent"
else fail "K10c: a name-only mention was read as the arm" "$(detail)"; fi
# K11 — GIT_AUTH_TS_PATH UNSET: the script's own default resolves to <infra>/../server/git-auth.ts.
# Run from the mirrored tree, whose server/git-auth.ts carries the option; the real checkout must
# have the same layout for the mirror to model it.
cp "$PRECHECK" "$MIRROR/infra/git-data-flag-precheck.sh" || { printf 'FAIL SETUP: mirror script\n' >&2; exit 1; }
case_tofu_default() { # [script] — defaults to the mirrored copy of the real script
  CASE_DEFAULT_GIT_AUTH=1 CASE_SCRIPT="${1:-$MIRROR/infra/git-data-flag-precheck.sh}" run_case tofu-default false
  [ "$RC" = 0 ] && [ "$(head -2 "$OUT")" = "$TOFU_PRESENT" ]
}
if [ -f "$DIR/../server/git-auth.ts" ] && case_tofu_default; then pass "K11: GIT_AUTH_TS_PATH unset -> the default <infra>/../server/git-auth.ts resolves (real layout present) -> TOFU_ARM present"
else fail "K11: the default git-auth.ts path did not resolve to TOFU_ARM present" "$(detail) real=$([ -f "$DIR/../server/git-auth.ts" ] && echo yes || echo no)"; fi
run_case pin-no-rt false RUNNER_TEMP=
if [ "$RC" = 5 ] && [ "$(tail -2 "$OUT")" = "$(refusal pin_write_failed)" ]; then pass "K9: RUNNER_TEMP unset -> verdict=pin_write_failed, exit 5"
else fail "K9: an unset RUNNER_TEMP was not refused" "$(detail)"; fi

run_case xtrace false
: > "$DLOG"
timeout -k 3 30 env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" DOPPLER_STORE="$T/store-xtrace" DOPPLER_LOG="$DLOG" DOPPLER_TOKEN=fixture-prd-read \
  bash -x "$PRECHECK" > "$OUT" 2>&1
RC=$?
if [ "$RC" = 78 ] && [ ! -s "$DLOG" ]; then pass "P7: under bash -x the precheck exits 78 before calling doppler"
else fail "P7: the xtrace refusal did not fire first" "rc=$RC"; fi

# ── workflow rows ─────────────────────────────────────────────────────────────────────
cat > "$T/wf.py" <<'PY'
import sys, yaml, json
wf_path, iv_path = sys.argv[1:3]
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
wf = yaml.safe_load(open(wf_path)) or {}
on = wf.get(True) or wf.get("on") or {}
check("G1-on: workflow_dispatch trigger read through the True-key lookup", isinstance(on, dict) and "workflow_dispatch" in on, type(on).__name__)
steps = ((wf.get("jobs") or {}).get("cutover") or {}).get("steps") or []
pre = [i for i, s in enumerate(steps) if s.get("id") == "flag_precheck"]
bridge = [i for i, s in enumerate(steps) if s.get("uses") == "./.github/actions/cf-tunnel-ssh-bridge"]
key = [i for i, s in enumerate(steps) if s.get("id") == "key_fetch"]
run = [i for i, s in enumerate(steps) if isinstance(s.get("run"), str) and "git-data-cutover.sh" in s["run"]]
check("G1-order: exactly one flag precheck step, and it precedes the bridge, the key fetch and the script step",
      len(pre) == 1 and len(bridge) == 1 and len(key) == 1 and len(run) == 1 and pre[0] < bridge[0] and pre[0] < key[0] and pre[0] < run[0],
      (pre, bridge, key, run))
p = steps[pre[0]] if len(pre) == 1 else {}
check("G1-step: the precheck step runs the script, with no if: and no continue-on-error",
      str(p.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-flag-precheck.sh" and "if" not in p and not p.get("continue-on-error"), p)
check("G1-env: the precheck step binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD}",
      p.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}"}, p.get("env"))
cfg = [i for i, s in enumerate(steps) if s.get("id") == "ssh_config"]
pin_users = [s.get("id") or s.get("name") for s in steps if "git-data.pin" in json.dumps(s)]
check("G1-pin: the pin the precheck writes is read by the ssh_config step, which runs after the precheck and the bridge",
      len(cfg) == 1 and len(pre) == 1 and len(bridge) == 1 and pre[0] < bridge[0] < cfg[0]
      and "ssh_config" in pin_users and all(u in ("ssh_config", "Tear down cloudflared SSH bridge") for u in pin_users), (pre, bridge, cfg, pin_users))
sites = [("step", s.get("id") or s.get("name")) for s in steps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
job = (wf.get("jobs") or {}).get("cutover") or {}
sites += [("job", k) for k, v in job.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("top", k) for k, v in wf.items() if k != "jobs" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("job", j) for j, b in (wf.get("jobs") or {}).items() if j != "cutover" and "DOPPLER_TOKEN_PRD" in json.dumps(b, default=str)]
check("G1-census: DOPPLER_TOKEN_PRD is named only by the flag precheck step (%d steps scanned)" % len(steps),
      len(steps) >= 1 and sites == [("step", "flag_precheck")], sites)
iv = yaml.safe_load(open(iv_path))
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
# Since #8736 this suite is registered by PRESENCE (the deploy-script-tests
# legs glob-derive it), so the step under test is the legs' runner invocation —
# one step definition (the matrix fans it out), unmasked.
mine = [s for s in ivsteps if isinstance(s.get("run"), str) and s["run"].strip() == "bash apps/web-platform/infra/run-registered-suites.sh"]
check("AC10: infra-validation.yml's legs invoke the suite runner in exactly one step with no if:/continue-on-error",
      len(mine) == 1 and "if" not in mine[0] and not mine[0].get("continue-on-error"), len(mine))
print("\n".join(out))
PY
# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# YAML leg crashed on a mutant) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }
python3 "$T/wf.py" "$WF" "$IV" > "$T/wf.tsv" 2> "$T/wf.err"
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -ge 7 ] || fail "G1: only $_wf_n workflow verdicts were produced (expected 7) — the YAML leg crashed" "$(head -c 300 "$T/wf.err")"

# ── mutation matrix (Guard 1) ─────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its named case RED)"
MUTANT=""
mutate() { # <name> <file> <expected-diff-lines> <sed -E program | python:<program-file>>
  local name="$1" src="$2" want="$3" expr="$4" got
  MUTANT="$T/mut/$name.$(basename "$src")"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if [ "${expr#python:}" != "$expr" ]; then
    python3 "${expr#python:}" "$MUTANT" 2>"$T/mut/$name.err" || { fail "M-$name: mutation program failed" "$(head -1 "$T/mut/$name.err")"; return 1; }
  elif ! sed -E -i "$expr" "$MUTANT" 2>"$T/mut/$name.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.err")"; return 1
  fi
  got="$(diff "$src" "$MUTANT" | grep -cE '^[<>]' || true)"
  if [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want" "[$expr]"; return 1
  fi
  if [ "${src%.sh}" != "$src" ] && ! bash -n "$MUTANT" 2>/dev/null; then
    fail "M-$name: the mutant does not parse (bash -n)"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
mutant_red() {
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named case stayed GREEN against the mutant"
  else pass "M-$name: the named case goes RED against the mutant"; fi
}
# mutant_red self-test (ADR-193), both directions, in a subshell so the counters roll back: a case
# that stays GREEN must count one failure, a case that goes RED one pass. Reported with printf + exit.
_mr="$( (mutant_red st-green true >/dev/null; printf '%s,%s ' "$passes" "$fails"; mutant_red st-red false >/dev/null; printf '%s,%s' "$passes" "$fails") )"
if [ "$_mr" != "$passes,$((fails + 1)) $((passes + 1)),$((fails + 1))" ]; then
  printf 'FAIL INSTRUMENT: mutant_red self-test read "%s" (from %s,%s) — a GREEN case must fail, a RED case must pass\n' "$_mr" "$passes" "$fails" >&2; exit 1
fi

# Row 1 — restore `|| echo ""` semantics: a non-zero rc reads as an empty value.
# shellcheck disable=SC2016  # sed programs are data
if mutate read-error-as-unset "$PRECHECK" 2 's#2>"\$ERRF"\)" \|\| rc=\$\?$#2>"$ERRF")" || VAL=""#'; then
  CASE_SCRIPT="$MUTANT" mutant_red read-error-as-unset case_scope_error
fi
# Row 2 — REORDER: move the flag precheck step after the bridge step.
cat > "$T/mut/reorder.py" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split("\n")
def block(start_pred):
    s = next(i for i, l in enumerate(lines) if start_pred(l))
    e = next(i for i in range(s + 1, len(lines)) if lines[i].startswith("      - ") or (lines[i].startswith("      # ") and i + 1 < len(lines) and lines[i + 1].startswith("      ")) and not lines[i].startswith("        "))
    return s, e
s, e = block(lambda l: l.startswith("      - name: Flag precheck"))
chunk = lines[s:e]; del lines[s:e]
b = next(i for i, l in enumerate(lines) if l.strip() == "uses: ./.github/actions/cf-tunnel-ssh-bridge")
be = next(i for i in range(b + 1, len(lines)) if lines[i].startswith("      - ") or lines[i].startswith("      # "))
lines[be:be] = chunk
open(p, "w").write("\n".join(lines))
PY
if mutate precheck-after-bridge "$WF" 12 "python:$T/mut/reorder.py"; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-order.tsv" 2>&1
  mutant_red precheck-after-bridge wf_row "$T/mut/wf-order.tsv" "G1-order:"
fi
# Row 3 — bind DOPPLER_TOKEN_PRD in the script step's env as well.
# shellcheck disable=SC2016
if mutate prd-in-script-step "$WF" 1 's#^          GIT_DATA_SSH: ssh -F .*$#&\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-census.tsv" 2>&1
  mutant_red prd-in-script-step wf_row "$T/mut/wf-census.tsv" "G1-census:"
fi
# Row 4 — compare `true` case-insensitively.
# shellcheck disable=SC2016
if mutate true-case-insensitive "$PRECHECK" 2 's#^if \[ "\$flag" = true \]; then$#if [ "${flag,,}" = true ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red true-case-insensitive case_off upper TRUE
fi
# Row 5 — drop the reserved-secret scope check.
# shellcheck disable=SC2016
if mutate no-scope-check "$PRECHECK" 2 's#^if \[ "\$project" != soleur \] \|\| \[ "\$config" != prd \]; then$#if false; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red no-scope-check case_scope_mismatch mconfig SHIM_BOUND_CONFIG=prd_terraform
fi
# Row 6 — drop the empty-token guard (the read then fails with reason=unknown instead).
# shellcheck disable=SC2016
if mutate no-token-guard "$PRECHECK" 2 's#^if \[ -z "\$\{DOPPLER_TOKEN:-\}" \]; then$#if false; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red no-token-guard case_token_absent
fi
# Row 7 — collapse the auth reason word into unknown.
if mutate auth-reason-collapsed "$PRECHECK" 2 's#then echo auth_invalid$#then echo unknown#'; then
  CASE_SCRIPT="$MUTANT" mutant_red auth-reason-collapsed case_reason mauth auth_invalid 1 SHIM_ERR=auth
fi
# Row 8 — print doppler's captured stderr on a failed read.
# shellcheck disable=SC2016
if mutate stderr-printed "$PRECHECK" 2 's#^    refuse "\$2 reason=\$\(reason_of "\$ERRF"\) rc=\$\{rc\}"$#    cat "$ERRF"; &#'; then
  CASE_SCRIPT="$MUTANT" mutant_red stderr-printed case_reason mprint auth_invalid 1 SHIM_ERR=auth
fi

# Row 9 — drop the pin shape check (an ECDSA key would then be written as the git-data pin).
# shellcheck disable=SC2016
if mutate pin-shape-unchecked "$PRECHECK" 2 's#^if ! \[\[ \$pin =~ \$PIN_RE \]\]; then$#if false; then#'; then
  CASE_PIN="$ECDSA_PIN" CASE_SCRIPT="$MUTANT" mutant_red pin-shape-unchecked case_pin_refused m-ecdsa invalid
fi
# Row 10 — read a failed pin read as an absent pin.
# shellcheck disable=SC2016
if mutate pin-unreadable-as-absent "$PRECHECK" 2 's#^read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable --no-exit-on-missing-secret$#VAL="$(doppler secrets get GIT_DATA_SSH_HOST_KEY --plain --no-exit-on-missing-secret -p soleur -c prd 2>/dev/null)" || VAL=""#'; then
  CASE_PIN=ABSENT CASE_SCRIPT="$MUTANT" mutant_red pin-unreadable-as-absent case_pin_refused m-unreadable 'unknown rc=1' SHIM_IGNORE_FLAG=1
fi
# Row 10b — the pin read's failure reported under the FLAG's verdict (the classifier reused, the
# verdict not): an operator reading the log would chase the flag, not the pin.
if mutate pin-verdict-as-flag "$PRECHECK" 2 's#^read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable #read_secret GIT_DATA_SSH_HOST_KEY flag_read_failed #'; then
  CASE_SCRIPT="$MUTANT" mutant_red pin-verdict-as-flag case_pin_refused m-auth 'auth_invalid rc=1' SHIM_PIN_ERR=auth
fi
# Row 11 — print the raw pin next to its fingerprint.
# shellcheck disable=SC2016
if mutate pin-printed "$PRECHECK" 2 's#^echo "git_data_pin=present fp=\$\{fp\}"$#echo "git_data_pin=present fp=${fp} key=${pin}"#'; then
  CASE_SCRIPT="$MUTANT" mutant_red pin-printed case_pin_ok
fi
# Row 12 — the TOFU_ARM probe never reports present.
# shellcheck disable=SC2016
if mutate tofu-arm-blind "$PRECHECK" 2 's#^elif grep -qiF "StrictHostKeyChecking=accept-""new" "\$GIT_AUTH_TS"; then$#elif false; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red tofu-arm-blind case_tofu_present
fi
# Row 13 — key the probe on the constant's NAME again: a renamed constant then reads absent.
if mutate tofu-arm-by-name "$PRECHECK" 2 's#^elif grep -qiF "StrictHostKeyChecking=accept-""new" "\$GIT_AUTH_TS"; then$#elif grep -qw TOFU_FALLBACK_OPTS "$GIT_AUTH_TS"; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red tofu-arm-by-name case_tofu_file m-renamed "$T/git-auth-renamed.ts"
fi
# Row 14 — case-sensitive match: the lower-case spelling ssh accepts then reads absent.
if mutate tofu-arm-case-sensitive "$PRECHECK" 2 's#^elif grep -qiF #elif grep -qF #'; then
  CASE_SCRIPT="$MUTANT" mutant_red tofu-arm-case-sensitive case_tofu_file m-lower "$T/git-auth-lower.ts"
fi
# Row 15 — miscount the default path's `..`: GIT_AUTH_TS_PATH unset then reads unknown. The mutant
# runs from the SAME mirrored location as K11's control, so only the edit differs.
if mutate tofu-default-path "$PRECHECK" 2 's#/\.\./server/git-auth\.ts\}"$#/../../server/git-auth.ts}"#'; then
  cp "$MUTANT" "$MIRROR/infra/mut-default.sh" || { printf 'FAIL SETUP: mirror mutant\n' >&2; exit 1; }
  mutant_red tofu-default-path case_tofu_default "$MIRROR/infra/mut-default.sh"
fi
# Row 16 — drop the read-only chmod on the pin file.
if mutate pin-writable "$PRECHECK" 2 's#^chmod 0444 "\$PIN_OUT" \|\| refuse pin_write_failed$#:#'; then
  CASE_SCRIPT="$MUTANT" mutant_red pin-writable case_pin_ok
fi

# ── FLOOR + LEDGER ────────────────────────────────────────────────────────────────────
MUTANT_FLOOR=17  # Guard 1 matrix rows 1-8, pin rows 9-16 (with 10b)
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2; exit 1
fi
# Assertion FLOOR: script cases 20 + pin/TOFU_ARM cases 15 (K1-K11 with K3b/K3c/K10b/K10c) + workflow rows 7 + mutants 17 x 2 = 76 (exact).
FLOOR=76
_ran=$((passes + fails + SKIPPED))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s\n' "$_ran" "$FLOOR" >&2; exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-flag-precheck: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
