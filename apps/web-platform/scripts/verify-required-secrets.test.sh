#!/usr/bin/env bash
# Tests for verify-required-secrets.sh, the release-time Doppler prd presence gate run by the
# `verify-doppler-secrets` job that `deploy` needs (PR A of #8211 / #12167, #12289, CTO ruling F2).
#
# Run via:  bash apps/web-platform/scripts/verify-required-secrets.test.sh
#
# WHAT IS PINNED. PROXY_HELLO_HMAC_KEY is in REQUIRED (presence only, as ruled in F2: the 64-hex shape is
# checked by the app's startup guard, and the Terraform-minted value cannot be malformed without an owner
# write). A missing or empty key blocks every deploy, hotfixes included, until it exists. The entry is
# removed in the SAME change that turns host_proxy_tls_enabled off (the parity suite pins that coupling).
#
# HOW. Every row runs the script under `env -i` with an EXPLICIT, SYNTHESIZED environment (no ambient
# Doppler/CI variable can satisfy or poison a row), PATH pointing at a stub `doppler` that serves a
# synthesized flag value and refuses every argv shape the script is not meant to send. The live Doppler
# API is never called. The key value is minted per run (never a literal) and is a sentinel: it must not
# appear on any stream.
#
# ROWS (ids fixed by the plan; each id is exactly ONE pass/fail call):
#   V1 all required present, the key included -> exit 0, an `ok` line per required name
#   V2 the key missing -> exit 1, naming only the key
#   V3 the key empty -> exit 1, same verdict as missing
#   V4 the key's value never appears on stdout/stderr (success, missing-sibling and shape-violation paths)
#   V5 the xtrace refusal (rc 78) still holds, with no `ok` line and no value on either stream
#   V6 suite-level mutant: removing the REQUIRED entry is caught by V2 (control green, mutant red)

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/verify-required-secrets.sh"
[[ -f "$SCRIPT" ]] || { printf 'ERROR: %s not found\n' "$SCRIPT" >&2; exit 1; }

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Helper self-test (ADR-193): both helpers must move their counters.
( pass probe >/dev/null; [[ "$PASS" == 1 ]] ) || { printf '[FATAL] pass() does not count\n' >&2; exit 1; }
( fail probe >/dev/null; [[ "$FAIL" == 1 ]] ) || { printf '[FATAL] fail() does not count\n' >&2; exit 1; }

ROOT="$(mktemp -d)"
trap 'rm -rf -- "$ROOT"' EXIT
case "$ROOT" in /*) : ;; *) printf '[FATAL] mktemp returned a non-absolute path\n' >&2; exit 2 ;; esac

BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/doppler" <<'FAKE'
#!/usr/bin/env bash
# The script's only doppler call: doppler secrets get <FLAG> -p soleur -c prd --plain
if [[ $# -eq 8 && "$1 $2 $4 $5 $6 $7 $8" == "secrets get -p soleur -c prd --plain" && "$3" == FLAG_* ]]; then
  printf '1\n'; exit 0
fi
echo "fake doppler: unexpected argv: $*" >&2
exit 64
FAKE
chmod +x "$BIN/doppler"

# --- the synthesized environment ----------------------------------------------------------------------
# TEST-SIDE literal of the REQUIRED names (never parsed from the script under test: a parsed list would
# shrink with the entry a mutant removes). Adding a name to REQUIRED means adding it here AND to BASE_ENV.
RQ=(
  NEXT_PUBLIC_APP_URL
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  NEXT_PUBLIC_SENTRY_DSN
  NEXT_PUBLIC_VAPID_PUBLIC_KEY
  NEXT_PUBLIC_GITHUB_APP_SLUG
  SUPABASE_ACCESS_TOKEN
  PROXY_HELLO_HMAC_KEY
)
KEY_NAME=PROXY_HELLO_HMAC_KEY
KEY_VAL="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"   # 64 lowercase hex, minted per run
[[ "$KEY_VAL" =~ ^[0-9a-f]{64}$ ]] || { printf '[FATAL] could not synthesize the sentinel key\n' >&2; exit 2; }

b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
REF="abcdefghijklmnopqrst"   # 20 chars [a-z0-9]; not a test*/placeholder*/... prefix
JWT_H="$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)"
JWT_P="$(printf '{"iss":"supabase","role":"anon","ref":"%s"}' "$REF" | b64url)"
JWT_S="$(printf 'synthetic-signature' | b64url)"

BASE_ENV=(
  "NEXT_PUBLIC_APP_URL=https://app.example.test"
  "NEXT_PUBLIC_SUPABASE_URL=https://${REF}.supabase.co"
  "NEXT_PUBLIC_SUPABASE_ANON_KEY=${JWT_H}.${JWT_P}.${JWT_S}"
  "NEXT_PUBLIC_SENTRY_DSN=synthetic-dsn-value"
  "NEXT_PUBLIC_VAPID_PUBLIC_KEY=synthetic-vapid-value"
  "NEXT_PUBLIC_GITHUB_APP_SLUG=synthetic-app-slug"
  "SUPABASE_ACCESS_TOKEN=synthetic-management-token-$RANDOM"
  "GITHUB_CLIENT_ID=Iv23AAAAAAAAAAAAAAAA"
  "${KEY_NAME}=${KEY_VAL}"
)

GATE_SCRIPT="$SCRIPT"
RC=0; OUT=""; ERR=""

# run_gate <omit-name|-> [VAR=value ...]: run GATE_SCRIPT under env -i with BASE_ENV minus <omit-name>, plus the extras.
run_gate() {
  local omit="$1"; shift
  local -a envv=()
  local kv
  for kv in "${BASE_ENV[@]}"; do
    [[ "${kv%%=*}" == "$omit" ]] || envv+=("$kv")
  done
  envv+=("$@")
  RC=0
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$ROOT" "${envv[@]}" bash "$GATE_SCRIPT" > "$ROOT/out" 2> "$ROOT/err" || RC=$?
  OUT="$(cat "$ROOT/out")"; ERR="$(cat "$ROOT/err")"
}

# The V2/V3 verdict, shared with V6 so the mutant row cannot restate it: exit 1, exactly ONE missing-secret error and
# it names the key, plus the summary line.
missing_verdict_holds() {
  local n
  [[ "$RC" == 1 ]] || return 1
  grep -qxF "::error::Required secret missing from Doppler prd: ${KEY_NAME}" <<<"$OUT" || return 1
  n="$(grep -c '^::error::Required secret missing' <<<"$OUT" || true)"
  [[ "$n" == 1 ]] || return 1
  grep -qxF '::error::1 required secret(s) missing from Doppler prd' <<<"$OUT" || return 1
  ! grep -qxF "ok ${KEY_NAME}" <<<"$OUT"
}

echo "verify-required-secrets.sh"

# --- V1 ----------------------------------------------------------------------------------------------
v1() {
  local n detail=''
  run_gate -
  [[ "$RC" == 0 ]] || detail=" rc=${RC} (want 0): $(tr '\n' '|' <<<"$OUT$ERR" | cut -c1-300);"
  for n in "${RQ[@]}"; do
    grep -qxF "ok ${n}" <<<"$OUT" || detail="${detail} no 'ok ${n}' line;"
  done
  grep -qxF "::notice::All ${#RQ[@]} required secrets present in Doppler prd" <<<"$OUT" || detail="${detail} notice count != ${#RQ[@]};"
  if [[ -z "$detail" ]]; then
    pass "V1 all required secrets present, the hello key included: exit 0 and an ok line per required name"
  else
    fail "V1 all required present passes:${detail}"
  fi
}

# --- V2 ----------------------------------------------------------------------------------------------
v2() {
  run_gate "$KEY_NAME"
  if missing_verdict_holds; then
    pass "V2 the hello key missing: exit 1, one error naming only ${KEY_NAME}"
  else
    fail "V2 the hello key missing fails naming only the key: rc=${RC} out=$(tr '\n' '|' <<<"$OUT" | cut -c1-300)"
  fi
}

# --- V3 ----------------------------------------------------------------------------------------------
v3() {
  run_gate "$KEY_NAME" "${KEY_NAME}="
  if missing_verdict_holds; then
    pass "V3 the hello key set but EMPTY: exit 1, treated exactly like missing"
  else
    fail "V3 the hello key empty fails like missing: rc=${RC} out=$(tr '\n' '|' <<<"$OUT" | cut -c1-300)"
  fi
}

# --- V4 ----------------------------------------------------------------------------------------------
v4() {
  local detail='' shape='https://placeholder.example.test'
  # success path
  run_gate -
  [[ "$RC" == 0 ]] || detail="${detail} success-path rc=${RC};"
  grep -qF -- "$KEY_VAL" <<<"$OUT$ERR" && detail="${detail} value printed on the success path;"
  # failure path: the key is present, a SIBLING is missing
  run_gate NEXT_PUBLIC_APP_URL
  [[ "$RC" == 1 ]] || detail="${detail} missing-sibling-path rc=${RC};"
  grep -qF -- "$KEY_VAL" <<<"$OUT$ERR" && detail="${detail} value printed on the missing-sibling path;"
  # failure path: the key is present, a shape check fails
  run_gate NEXT_PUBLIC_SUPABASE_URL "NEXT_PUBLIC_SUPABASE_URL=${shape}"
  [[ "$RC" == 1 ]] || detail="${detail} shape-violation-path rc=${RC};"
  grep -qF -- "$KEY_VAL" <<<"$OUT$ERR" && detail="${detail} value printed on the shape-violation path;"
  if [[ -z "$detail" ]]; then
    pass "V4 the hello key's value never appears on stdout or stderr (success, missing-sibling and shape-violation paths)"
  else
    fail "V4 the hello key's value never appears on a stream:${detail}"
  fi
}

# --- V5 ----------------------------------------------------------------------------------------------
v5() {
  local detail=''
  RC=0
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$ROOT" "${BASE_ENV[@]}" bash -x "$GATE_SCRIPT" > "$ROOT/out" 2> "$ROOT/err" || RC=$?
  OUT="$(cat "$ROOT/out")"; ERR="$(cat "$ROOT/err")"
  [[ "$RC" == 78 ]] || detail="${detail} rc=${RC} (want 78);"
  grep -q '^ok ' <<<"$OUT" && detail="${detail} an ok line was printed before the refusal;"
  grep -qF -- "$KEY_VAL" <<<"$OUT$ERR" && detail="${detail} the value reached a stream under -x;"
  grep -qF 'refusing to run under xtrace' <<<"$ERR" || detail="${detail} refusal text missing;"
  if [[ -z "$detail" ]]; then
    pass "V5 the xtrace refusal holds: rc 78, no ok line, no value on either stream"
  else
    fail "V5 the xtrace refusal holds:${detail}"
  fi
}

# --- V6 ----------------------------------------------------------------------------------------------
v6() {
  local mut="$ROOT/mutant.sh" ctl_ok=0 mut_red=0 saved="$GATE_SCRIPT"
  sed '/^REQUIRED=(/,/^)/{/^  PROXY_HELLO_HMAC_KEY$/d;}' "$SCRIPT" > "$mut"
  if cmp -s "$SCRIPT" "$mut"; then
    fail "V6 mutant: removing the REQUIRED entry did not land (the REQUIRED entry is absent from the script)"
    return
  fi
  # control: the real script satisfies the V2 verdict
  GATE_SCRIPT="$SCRIPT"; run_gate "$KEY_NAME"
  if missing_verdict_holds; then ctl_ok=1; fi
  # mutant: the same run against the entry-less copy must NOT satisfy it (it exits 0: the key is no longer required)
  GATE_SCRIPT="$mut"; run_gate "$KEY_NAME"
  if ! missing_verdict_holds; then mut_red=1; fi
  GATE_SCRIPT="$saved"
  if [[ "$ctl_ok" == 1 && "$mut_red" == 1 && "$RC" == 0 ]]; then
    pass "V6 mutant: removing the REQUIRED entry is caught by V2 (control green, mutant exits 0 and fails the verdict)"
  else
    fail "V6 mutant: removing the REQUIRED entry is caught by V2: control=${ctl_ok} mutant_red=${mut_red} mutant_rc=${RC}"
  fi
}

v1
v2
v3
v4
v5
v6

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
# Anti-vacuity floor (ADR-193): exact, V1-V6. Reported outside the helpers, by printf + exit 1.
MIN_ASSERTIONS=6
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran (floor %d)\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
(( FAIL == 0 ))
