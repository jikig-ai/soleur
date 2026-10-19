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
[ "${1:-}" = secrets ] && { [ "${2:-}" = get ] || [ "${2:-}" = set ] || [ "${2:-}" = delete ]; } || { echo "doppler-shim: unsupported: $*" >&2; exit 64; }
# One line per call naming the verb, the secret and WHICH token carried it (fixture tokens only), so a row can prove
# the stamp delete rode DOPPLER_TOKEN_GIT_DATA_FLAG and not the read token. A separate file: DOPPLER_LOG stays argv-only.
printf '%s %s %s\n' "${2:-}" "${3:-}" "${DOPPLER_TOKEN:-<none>}" >> "$DOPPLER_LOG.tok"
if [ "${2:-}" = delete ]; then
  # secrets delete NAME -p P -c C --yes (#10297). SHIM_DELETE_ERR forces a classified failure (forbidden = the token lacks
  # DELETE on prd, the unverified permission); SHIM_DELETE_NOOP models a delete that exits 0 and leaves the value.
  name="${3:-}"; shift 3
  proj=""; cfg=""; yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--project) proj="${2:-}"; shift 2 ;;
      -c|--config) cfg="${2:-}"; shift 2 ;;
      -y|--yes) yes=1; shift ;;
      *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
    esac
  done
  [ "$yes" = 1 ] || { echo "doppler-shim: delete without --yes would prompt" >&2; exit 64; }
  [ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
  case "${SHIM_DELETE_ERR:-}" in
    forbidden) echo "Doppler Error: This token does not have access to delete secrets STDERR-CANARY-3b" >&2; exit 1 ;;
    network)   echo "Doppler Error: dial tcp: i/o timeout STDERR-CANARY-3b" >&2; exit 3 ;;
    other)     echo "Doppler Error: something unforeseen STDERR-CANARY-3b" >&2; exit 2 ;;
  esac
  d="$DOPPLER_STORE/$proj/$cfg"
  [ -d "$d" ] || { echo "Doppler Error: Could not find requested config '$cfg'" >&2; exit 1; }
  if [ "${SHIM_DELETE_NOOP:-0}" != 1 ]; then rm -f "$d/$name"; : > "$DOPPLER_STORE/.deleted-$name"; fi
  # The real CLI prints the config's REMAINING secrets on a delete (cutover-inngest.sh keeps its delete >/dev/null for that
  # reason; the repo hook doppler-secrets-delete-redirect refuses one without the redirect). The canary stands for that table,
  # so a caller that stops discarding stdout puts it in the run log and RB1 goes RED.
  echo "STDOUT-CANARY-DELETE GIT_DATA_SSH_HOST_KEY=fixture-remaining-secret"
  exit 0
fi
if [ "${2:-}" = set ]; then
  # secrets set NAME -p P -c C — value on stdin (the only supported form here; the caller
  # must never pass a value on argv). SHIM_SET_ERR forces a classified failure;
  # SHIM_WRITE_STORE redirects the store so the write lands where the case expects.
  # The value is read FIRST (#9217): the caller pipes it in under pipefail, so an arm that exits on the
  # missing token or a classified failure before reading would let the writer take SIGPIPE. Not a terminal only.
  value=""; [ -t 0 ] || value="$(timeout 2 cat)"
  name="${3:-}"; shift 3
  proj=""; cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--project) proj="${2:-}"; shift 2 ;;
      -c|--config) cfg="${2:-}"; shift 2 ;;
      *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
    esac
  done
  [ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
  case "${SHIM_SET_ERR:-}" in
    auth)    echo "Doppler Error: Invalid Auth token STDERR-CANARY-3b" >&2; exit 1 ;;
    network) echo "Doppler Error: dial tcp: i/o timeout STDERR-CANARY-3b" >&2; exit 3 ;;
  esac
  d="$DOPPLER_STORE/$proj/$cfg"
  [ -d "$d" ] || { echo "Doppler Error: Could not find requested config '$cfg'" >&2; exit 1; }
  printf '%s' "$value" > "$d/$name"
  # the real CLI prints the whole config on set; the shim prints nothing (the caller
  # discards stdout anyway — what matters is that nothing the caller needs is on stdout).
  exit 0
fi
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
# SHIM_STAMP_READBACK_ERR forces one error class on the stamp read that follows a delete ONLY (the delete's read-back).
if [ "$name" = GIT_DATA_LUKS_CUTOVER_AT ] && [ -e "$DOPPLER_STORE/.deleted-$name" ]; then
  case "${SHIM_STAMP_READBACK_ERR:-}" in
    network) echo "Doppler Error: dial tcp: lookup api.doppler.com: i/o timeout STDERR-CANARY-3b" >&2; exit 3 ;;
  esac
fi
# SHIM_STAMP_ERR forces one error class on the GIT_DATA_LUKS_CUTOVER_AT read ONLY (wipe modes).
if [ "$name" = GIT_DATA_LUKS_CUTOVER_AT ]; then
  case "${SHIM_STAMP_ERR:-}" in
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
# SHIM_READBACK_DIFFER models a write that "succeeded" but read-back returns another value.
if [ "$name" = GIT_DATA_STORE_ENABLED ] && [ -n "${SHIM_READBACK_DIFFER:-}" ]; then
  printf '%s' "$SHIM_READBACK_DIFFER"; exit 0
fi
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

# SANDBOX_DENY_ROOTS fixtures (#9725): a source dir carrying both markers
# (resolver exports workspaceTenantDenyRoots + config calls it), one where the
# config marker is missing (the pre-fix posture), and a nonexistent dir for
# `unknown` (files unreadable → never "absent").
mkdir -p "$T/deny-present" "$T/deny-absent" || { printf 'FAIL SETUP: deny fixtures\n' >&2; exit 1; }
printf 'export function workspaceTenantDenyRoots() { return [process.env.WORKTREE_ROOT]; }\n' > "$T/deny-present/workspace-resolver.ts"
printf 'const denyRoots = workspaceTenantDenyRoots();\n' > "$T/deny-present/agent-runner-sandbox-config.ts"
printf 'export function workspacePathForWorkspaceId() { return ""; }\n' > "$T/deny-absent/workspace-resolver.ts"
printf 'const denyRead = [];\n' > "$T/deny-absent/agent-runner-sandbox-config.ts"
mkdir -p "$T/deny-collapsed" || { printf 'FAIL SETUP: deny-collapsed fixture\n' >&2; exit 1; }
# The #9725 regression shape: helper exists and env read exists FILE-wide
# (inside getWorkspaceWorktreeRoot) — but NOT inside the deny helper's body.
printf 'function getWorkspaceWorktreeRoot() { return process.env.WORKTREE_ROOT || "/x"; }\nexport function workspaceTenantDenyRoots() { return [getWorkspaceWorktreeRoot()]; }\n' > "$T/deny-collapsed/workspace-resolver.ts"
printf 'const denyRoots = workspaceTenantDenyRoots();\n' > "$T/deny-collapsed/agent-runner-sandbox-config.ts"

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
  [ "${CASE_STAMP-ABSENT}" = ABSENT ] || printf '%s' "$CASE_STAMP" > "$store/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT"
  CTMP="$T/tmp-$name"; RT="$T/rt-$name"
  assert_fixture_dir "$CTMP"
  assert_fixture_dir "$RT"
  rm -rf "$CTMP" "$RT"; mkdir -p "$CTMP" "$RT" || { printf 'FAIL SETUP: case tmp\n' >&2; exit 1; }
  OUT="$T/$name.out"; DLOG="$T/$name.dlog"; : > "$DLOG"; : > "$DLOG.tok"
  # CASE_DEFAULT_GIT_AUTH=1 leaves GIT_AUTH_TS_PATH genuinely UNSET (not empty).
  local gat=(GIT_AUTH_TS_PATH="$T/git-auth-tofu.ts")
  [ "${CASE_DEFAULT_GIT_AUTH:-0}" = 1 ] && gat=()
  timeout -k 3 30 env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$CTMP" DOPPLER_STORE="$store" DOPPLER_LOG="$DLOG" \
    RUNNER_TEMP="$RT" "${gat[@]}" \
    SANDBOX_SRC_DIR="$(dirname "$PRECHECK")/../server" \
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
DENY_LINE='SANDBOX_DENY_ROOTS present'
ok_out() { printf '%s\n%s\ngit_data_pin=present fp=%s\n%s' "$TOFU_PRESENT" "$DENY_LINE" "$PIN_FP" "$1"; }
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

# ── write path + mode-aware read (#8211 PR2) ──────────────────────────────────
case_write() { # <label> <stored-flag> <write-value> [VAR=value ...]
  local label="$1" stored="$2" wv="$3"; shift 3
  run_case "write-$label" "$stored" FLAG_WRITE_VALUE="$wv" "$@"
}
if case_write ok ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write \
  && [ "$(cat "$OUT")" = "flag_write=ok value=true" ] \
  && [ "$(cat "$DLOG")" = "$(printf 'doppler secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd\ndoppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd')" ] \
  && [ "$(cat "$T/store-write-ok/soleur/prd/GIT_DATA_STORE_ENABLED")" = "true" ]; then
  pass "W1: the write path sets the flag through stdin, reads it back with the SAME credential, prints flag_write=ok — and never touches the read probes (exactly 2 doppler calls)"
else fail "W1: the write path did not write+read-back cleanly" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_write cred-absent ABSENT true \
  && [ "$RC" = 5 ] && grep -qF 'verdict=flag_write_credential_absent' "$OUT" && [ ! -s "$DLOG" ]; then
  pass "W2: FLAG_WRITE_VALUE without DOPPLER_TOKEN_GIT_DATA_FLAG -> verdict=flag_write_credential_absent, exit 5, doppler never called"
else fail "W2: a write without the #8573 credential was not refused" "$(detail)"; fi
if case_write bad-value ABSENT yes DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write \
  && [ "$RC" = 2 ] && grep -qF 'verdict=flag_write_value_invalid' "$OUT" && [ ! -s "$DLOG" ]; then
  pass "W3: a value other than true/false -> verdict=flag_write_value_invalid, exit 2, doppler never called"
else fail "W3: an invalid write value was not refused" "$(detail)"; fi
if case_write set-fail ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SHIM_SET_ERR=auth \
  && [ "$RC" = 5 ] && grep -qF 'verdict=flag_write_failed reason=auth_invalid' "$OUT" && ! grep -q 'CANARY' "$OUT"; then
  pass "W4: a failed set -> verdict=flag_write_failed reason=auth_invalid, exit 5, stderr never printed"
else fail "W4: a failed set was not refused" "$(detail)"; fi
if case_write readback-differs ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SHIM_READBACK_DIFFER=false \
  && [ "$RC" = 5 ] && grep -qF 'verdict=flag_write_readback_failed reason=value_mismatch' "$OUT"; then
  pass "W5: a set whose read-back returns another value -> verdict=flag_write_readback_failed reason=value_mismatch, exit 5"
else fail "W5: a mismatched read-back was not refused" "$(detail)"; fi
# W6 — the write arm is gated on SANDBOX_DENY_ROOTS too: a `true` write under
# ANY mode must refuse when the source lacks the #9725 deny coverage (the
# read-side refuse fires only under flip; the write arm exits before it).
if case_write deny-absent ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SANDBOX_SRC_DIR="$T/deny-absent" \
  && [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_absent' "$OUT" && [ ! -s "$DLOG" ]; then
  pass "W6: a `true` write without deny coverage -> verdict=sandbox_deny_coverage_absent, exit 5, doppler never called"
else fail "W6: a true write without deny coverage was not refused" "$(detail)"; fi
if case_write deny-ok ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SANDBOX_SRC_DIR="$T/deny-present" \
  && [ "$(cat "$OUT")" = "flag_write=ok value=true" ]; then
  pass "W7: a `true` write WITH deny coverage proceeds to the set+readback path"
else fail "W7: a covered true write did not reach the write path" "$(detail)"; fi
# W8 — a `false` write must NOT be gated (a rollback needs no deny coverage —
# it moves toward less exposure, and the served-image side is floored by
# GIT_DATA_DENY_FLOOR on flip). Pins the `= true` scope of the write gate.
if case_write deny-absent-false ABSENT false DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SANDBOX_SRC_DIR="$T/deny-absent" \
  && [ "$(cat "$OUT")" = "flag_write=ok value=false" ]; then
  pass "W8: a `false` write proceeds WITHOUT deny coverage (rollback must never be blocked by it)"
else fail "W8: a false write was incorrectly gated on deny coverage" "$(detail)"; fi

# ── rollback arm clears GIT_DATA_LUKS_CUTOVER_AT (#10297, design-rollback-rehearsal section 6) ───────────────────
# The stamp is the wipe's 7-day soak anchor, so a rollback that leaves it behind leaves a stale anchor. The delete rides the write
# step's own token, runs BEFORE the flag-off write (a failed delete then leaves the flag true and the fleet unchanged, so the
# rollback can be re-dispatched; a delete AFTER the flag-off write that failed would strand a fleet still running the store
# against a flag that reads false, and a re-dispatch would then read nothing_to_rollback and never redeploy), and is read back.
# The DELETE permission of that token on prd is UNVERIFIED: every row here runs against the shim, none proves the real API.
RB_STAMP="2026-10-19T10:00:00Z"
RB_WRITE=(DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write FLAG_MODE=rollback)
RB_STORE="$T/store-write-rb"
case_rb() { # <label> <stored-flag> <write-value> [VAR=value ...] — a stamp is stored unless CASE_STAMP=ABSENT
  local label="$1" stored="$2" wv="$3"; shift 3
  CASE_STAMP="${CASE_STAMP-$RB_STAMP}" run_case "write-$label" "$stored" FLAG_WRITE_VALUE="$wv" "$@"
  RB_STORE="$T/store-write-$label"
}
rb_flag() { cat "$RB_STORE/soleur/prd/GIT_DATA_STORE_ENABLED" 2>/dev/null; }
RB_DLOG_OK="$(printf '%s\n' \
  'doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd' \
  'doppler secrets delete GIT_DATA_LUKS_CUTOVER_AT -p soleur -c prd --yes' \
  'doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd' \
  'doppler secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd' \
  'doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd')"
case_rb_clears() {
  case_rb rb-clear true false "${RB_WRITE[@]}" \
    && [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(printf 'cutover_at=cleared\nflag_write=ok value=false')" ] \
    && [ "$(cat "$DLOG")" = "$RB_DLOG_OK" ] \
    && [ ! -e "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT" ] && [ "$(rb_flag)" = false ] \
    && ! grep -qF "$RB_STAMP" "$OUT" "$DLOG" && ! grep -qF 'STDOUT-CANARY' "$OUT"
}
case_rb_token() { # every call of the clear rode the write token
  case_rb rb-token true false "${RB_WRITE[@]}" && [ "$RC" = 0 ] \
    && [ "$(wc -l < "$DLOG.tok")" = 5 ] && [ -z "$(grep -vF ' fixture-prd-write' "$DLOG.tok")" ] \
    && [ -n "$(grep -F 'delete GIT_DATA_LUKS_CUTOVER_AT fixture-prd-write' "$DLOG.tok")" ]
}
case_rb_absent() { # no stamp: nothing to delete, no delete call, still green
  CASE_STAMP=ABSENT case_rb rb-absent true false "${RB_WRITE[@]}" \
    && [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(printf 'cutover_at=absent\nflag_write=ok value=false')" ] \
    && [ -z "$(grep -F 'secrets delete' "$DLOG")" ] && [ "$(rb_flag)" = false ]
}
case_rb_delete_refused() { # <label> <expected-step-reason> [VAR=value ...] — a failed clear stops BEFORE the flag write
  local label="$1" want="$2"; shift 2
  case_rb "$label" true false "${RB_WRITE[@]}" "$@"
  [ "$RC" = 5 ] && grep -qF "verdict=cutover_at_clear_failed ${want}" "$OUT" && ! grep -q 'CANARY' "$OUT" \
    && grep -qF 'R8' "$OUT" && grep -qF 'owner-gated delete' "$OUT" && grep -qF 'mode=rollback' "$OUT" \
    && [ "$(rb_flag)" = true ] && [ -z "$(grep -F 'secrets set' "$DLOG")" ] && ! grep -qF "$RB_STAMP" "$OUT"
}
case_rb_flip_untouched() { # the flip's own flag-on write never reads, deletes or sets the stamp
  case_rb rb-flip true true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write FLAG_MODE=flip SANDBOX_SRC_DIR="$T/deny-present" \
    && [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "flag_write=ok value=true" ] && [ -z "$(grep -F GIT_DATA_LUKS_CUTOVER_AT "$DLOG")" ] \
    && [ "$(cat "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT")" = "$RB_STAMP" ] && [ "$(wc -l < "$DLOG")" = 2 ]
}
case_rb_value_true() { # a rollback-mode TRUE write (never dispatched) must not clear the anchor either
  case_rb rb-vtrue false true "${RB_WRITE[@]}" SANDBOX_SRC_DIR="$T/deny-present" \
    && [ "$RC" = 0 ] && [ -z "$(grep -F GIT_DATA_LUKS_CUTOVER_AT "$DLOG")" ] && [ -e "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT" ]
}
case_rb_other_modes() { # <mode> — only rollback clears: unfreeze/proof/wipe-class FALSE writes leave the stamp
  case_rb "rb-mode-$1" true false DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write FLAG_MODE="$1" \
    && [ "$RC" = 0 ] && [ -z "$(grep -F GIT_DATA_LUKS_CUTOVER_AT "$DLOG")" ] && [ -e "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT" ]
}
rb_ws_cleared() { CASE_STAMP=' ' case_rb rb-ws true false "${RB_WRITE[@]}" && [ "$RC" = 0 ] && [ ! -e "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT" ] && [ -n "$(grep -F 'secrets delete' "$DLOG")" ]; }
rb_ws_noop_refused() { CASE_STAMP=' ' case_rb_delete_refused rb-ws-noop 'step=readback reason=still_present' SHIM_DELETE_NOOP=1; }
rb_nocred_refused() { case_rb rb-nocred true false DOPPLER_TOKEN_GIT_DATA_FLAG= FLAG_MODE=rollback && [ "$RC" = 5 ] && grep -qF 'verdict=flag_write_credential_absent' "$OUT" && [ ! -s "$DLOG" ]; }
if case_rb_clears; then pass "RB1: a rollback flag-off write reads the stamp, deletes it with --yes, reads it back absent, THEN sets the flag false and reads it back (exactly 5 doppler calls in that order); the stamp value is never printed"
else fail "RB1: the rollback arm did not clear the stamp then write the flag" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_token; then pass "RB2: all five calls of the clear (read, delete, read-back, set, read-back) ride DOPPLER_TOKEN_GIT_DATA_FLAG, never the read token"
else fail "RB2: a clear call did not use the write token" "$(detail) tok=[$(tr '\n' '|' < "$DLOG.tok")]"; fi
if case_rb_absent; then pass "RB3: no stamp present: cutover_at=absent, no delete call, the flag-off write still lands (a rollback that finds nothing to clear is green)"
else fail "RB3: an absent stamp was not a green no-op" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_delete_refused rb-forbidden 'step=delete reason=forbidden' SHIM_DELETE_ERR=forbidden; then
  pass "RB4: a delete the token is not permitted to make -> verdict=cutover_at_clear_failed step=delete reason=forbidden, exit 5, the message names R8 (owner-gated delete with read-back) and the re-dispatch, stderr never printed, and the flag is NOT written"
else fail "RB4: a refused delete was not a hard failure before the flag write" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_delete_refused rb-noop 'step=readback reason=still_present' SHIM_DELETE_NOOP=1; then
  pass "RB5: a delete that exits 0 but leaves the stamp -> verdict=cutover_at_clear_failed step=readback reason=still_present, exit 5, flag NOT written"
else fail "RB5: a delete that did not take was accepted" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_delete_refused rb-rbread 'step=readback reason=network' SHIM_STAMP_READBACK_ERR=network; then
  pass "RB6: a read-back that cannot be read -> verdict=cutover_at_clear_failed step=readback reason=network, exit 5 (an unreadable stamp is never read as absent), flag NOT written"
else fail "RB6: an unreadable read-back was accepted" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_delete_refused rb-read 'step=read reason=network' SHIM_STAMP_ERR=network; then
  pass "RB7: a stamp that cannot be read before the delete -> verdict=cutover_at_clear_failed step=read reason=network, exit 5, flag NOT written"
else fail "RB7: an unreadable stamp was treated as absent" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_delete_refused rb-other 'step=delete reason=unknown' SHIM_DELETE_ERR=other; then
  pass "RB8: an unclassified delete failure -> step=delete reason=unknown, exit 5, flag NOT written"
else fail "RB8: an unclassified delete failure was accepted" "$(detail)"; fi
if case_rb_flip_untouched; then pass "RB9: the FLIP's flag-on write never reads, deletes or sets the stamp (2 doppler calls, the stamp value intact)"
else fail "RB9: the flip write touched the stamp" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_rb_value_true; then pass "RB10: a TRUE write under rollback mode leaves the stamp alone (the clear is keyed on mode=rollback AND value=false)"
else fail "RB10: a true write cleared the stamp" "$(detail)"; fi
if case_rb_other_modes unfreeze; then pass "RB11a: a FALSE write under unfreeze mode leaves the stamp alone (only mode=rollback clears)"
else fail "RB11a: an unfreeze-mode false write cleared the stamp" "$(detail)"; fi
if case_rb_other_modes proof; then pass "RB11b: a FALSE write under proof mode leaves the stamp alone (only mode=rollback clears)"
else fail "RB11b: a proof-mode false write cleared the stamp" "$(detail)"; fi
# RB12/RB13: the wipe reads ANY non-empty stamp as present (a garbage stamp counts as present), so the clear must too.
if CASE_STAMP=' ' case_rb rb-ws true false "${RB_WRITE[@]}" && [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "$(printf 'cutover_at=cleared\nflag_write=ok value=false')" ] \
  && [ ! -e "$RB_STORE/soleur/prd/GIT_DATA_LUKS_CUTOVER_AT" ] && [ -n "$(grep -F 'secrets delete' "$DLOG")" ]; then
  pass "RB12: a whitespace-only stamp is PRESENT (as the wipe reads it): it is deleted, read back absent, and the flag-off write lands"
else fail "RB12: a whitespace-only stamp was treated as absent" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if CASE_STAMP=' ' case_rb_delete_refused rb-ws-noop 'step=readback reason=still_present' SHIM_DELETE_NOOP=1; then
  pass "RB13: a delete that leaves a whitespace-only stamp behind is still step=readback reason=still_present (the read-back compares the raw value), flag NOT written"
else fail "RB13: a residual whitespace-only stamp was accepted as cleared" "$(detail)"; fi
# RB14: with the write credential absent, a rollback refuses BEFORE any doppler call (the clear must not run on an empty or ambient token).
if case_rb rb-nocred true false DOPPLER_TOKEN_GIT_DATA_FLAG= FLAG_MODE=rollback && [ "$RC" = 5 ] && grep -qF 'verdict=flag_write_credential_absent' "$OUT" && [ ! -s "$DLOG" ]; then
  pass "RB14: a rollback flag-off write without DOPPLER_TOKEN_GIT_DATA_FLAG -> verdict=flag_write_credential_absent, exit 5, doppler never called (the clear sits below the credential guard)"
else fail "RB14: the clear ran without the write credential" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi

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
# ── mode-aware read (#8211 PR2) ────────────────────────────────────────────────────
case_mode() { # <label> <flag-value|ABSENT> <mode> — the flag=true mode branch runs BEFORE TOFU/pin
  run_case "mode-$1" "$2" FLAG_MODE="$3"
}
case_deny() { # <label> <src-dir> <mode> — SANDBOX_DENY_ROOTS arm (#9725): emits SANDBOX_SRC_DIR + FLAG_MODE
  run_case "deny-$1" false SANDBOX_SRC_DIR="$2" FLAG_MODE="$3"
}
case_write_deny_absent_true_refused() { # asserts the WRITE gate refuses a `true` write over absent coverage (mutant row 18)
  case_write m-write-gate ABSENT true DOPPLER_TOKEN_GIT_DATA_FLAG=fixture-prd-write SANDBOX_SRC_DIR="$T/deny-absent" \
    && [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_absent' "$OUT"
}
case_deny_absent_flip_refused() { # asserts the flip gate refuses absent coverage (mutant row)
  case_deny absent-flip "$T/deny-absent" flip
  [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_absent' "$OUT"
}
if case_mode flip-true true flip \
  && [ "$(cat "$OUT")" = "$(printf 'flag=true resume=arm_b\n%s\n%s\ngit_data_pin=present fp=%s' "$TOFU_PRESENT" "$DENY_LINE" "$PIN_FP")" ] && [ "$RC" = 0 ]; then
  pass "M-flip-true: flip with flag already true -> flag=true resume=arm_b, exit 0 (NOT a refusal — a prior flip died post-write)"
else fail "M-flip-true: resume arm B was not reported" "$(detail)"; fi
if case_mode rollback-true true rollback \
  && [ "$(cat "$OUT")" = "$(printf 'flag=true mode=rollback\n%s\n%s\ngit_data_pin=present fp=%s' "$TOFU_PRESENT" "$DENY_LINE" "$PIN_FP")" ] && [ "$RC" = 0 ]; then
  pass "M-rb-true: rollback with flag=true -> the expected entry, exit 0"
else fail "M-rb-true: flag=true under rollback was not accepted" "$(detail)"; fi
if case_mode rollback-off false rollback \
  && [ "$RC" = 0 ] && grep -qF 'verdict=nothing_to_rollback' "$OUT" && grep -qF 'flag=off' "$OUT"; then
  pass "M-rb-off: rollback with flag off -> verdict=nothing_to_rollback, exit 0 (desired state already holds)"
else fail "M-rb-off: nothing-to-rollback was not reported" "$(detail)"; fi
if case_mode unfreeze-true true unfreeze \
  && [ "$RC" = 0 ] && grep -qF 'flag=true mode=unfreeze' "$OUT"; then
  pass "M-uf-true: unfreeze with flag=true is ACCEPTED (a died-mid-window flip leaves flag on + freeze held — unfreeze is exactly that recovery)"
else fail "M-uf-true: unfreeze wrongly refused flag=true" "$(detail)"; fi
if case_mode bogus false bogus \
  && [ "$RC" = 2 ] && grep -qF 'verdict=flag_mode_invalid' "$OUT" && [ ! -s "$DLOG" ]; then
  pass "M-invalid: an unknown FLAG_MODE -> verdict=flag_mode_invalid, exit 2, doppler never called"
else fail "M-invalid: an unknown mode was not refused" "$(detail)"; fi
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
  [ "$RC" = 5 ] && [ "$(cat "$OUT")" = "$(printf '%s\n%s\n%s' "$TOFU_PRESENT" "$DENY_LINE" "$(refusal "git_data_host_key_unavailable reason=$reason")")" ] \
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

# ── wipe modes (#10138, W3 / W7b): three separate predicates, one pinned floor ─────────────────────
# Stamps are relative to the real clock with +-1 day margins (the script has no clock hook by design).
ST8="$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)"
ST6="$(date -u -d '6 days ago' +%Y-%m-%dT%H:%M:%SZ)"
STFUT="$(date -u -d '1 day' +%Y-%m-%dT%H:%M:%SZ)"
ST8_EPOCH="$(date -u -d "$ST8" +%s)"
WIPE_ARGV='doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd
doppler secrets get DOPPLER_PROJECT --plain -p soleur -c prd
doppler secrets get DOPPLER_CONFIG --plain -p soleur -c prd
doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain --no-exit-on-missing-secret -p soleur -c prd
doppler secrets get GIT_DATA_SSH_HOST_KEY --plain --no-exit-on-missing-secret -p soleur -c prd'
# wipe_run <label> <flag> <stamp|ABSENT> <mode> [VAR=value ...]
wipe_run() {
  local label="$1" flagv="$2" stamp="$3" mode="$4"; shift 4
  CASE_STAMP="$stamp" run_case "wipe-$label" "$flagv" FLAG_MODE="$mode" "$@"
}
case_wipe_ok() { # flag true + an 8-day stamp: passes, prints the mode line first and the soak line second
  wipe_run ok true "$ST8" wipe
  [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=flip_chained" ] && [ "$(sed -n 2p "$OUT")" = "flag=true mode=wipe" ] \
    && [ "$(sed -n 3p "$OUT" | sed -E 's/elapsed_s=[0-9]+$/elapsed_s=N/')" = "wipe_soak floor_days=7 stamp_epoch=${ST8_EPOCH} elapsed_s=N" ] \
    && [ "$(cat "$DLOG")" = "$WIPE_ARGV" ] && ! grep -qF 'flag_already_true' "$OUT"
}
case_wipe_refuses() { # <label> <flag> <stamp> <expected-verdict-prefix> [VAR=value ...]
  local label="$1" flagv="$2" stamp="$3" want="$4"; shift 4
  wipe_run "$label" "$flagv" "$stamp" wipe "$@"
  [ "$RC" = 5 ] && grep -qE "^\[git-data-flag-precheck\] verdict=${want}( |$)" "$OUT" && ! grep -qF 'git_data_pin=' "$OUT"
}
case_wipe_flag() { case_wipe_refuses flag-off false "$ST8" wipe_precondition_flag_not_true && grep -qxF 'wipe_variant=flip_chained' "$OUT" && grep -qF GIT_DATA_LUKS_CUTOVER_AT "$DLOG"; }
case_wipe_stamp_absent() { case_wipe_refuses stamp-absent true ABSENT wipe_precondition_stamp_absent; }
case_wipe_soak() { case_wipe_refuses soak6 true "$ST6" wipe_precondition_soak_not_elapsed && grep -qE 'floor_days=7 elapsed_s=[0-9]+' "$OUT"; }
case_wipe_soak_env0() { case_wipe_refuses soak6-env0 true "$ST6" wipe_precondition_soak_not_elapsed WIPE_SOAK_FLOOR_SECONDS=0; }

if case_wipe_ok; then pass "WP1: mode=wipe, flag true, an 8-day-old stamp -> 'wipe_variant=flip_chained', 'flag=true mode=wipe' then 'wipe_soak floor_days=7 stamp_epoch=<n> elapsed_s=<n>', exit 0; doppler called 5 times (flag, project, config, stamp with --no-exit-on-missing-secret, pin)"
else fail "WP1: the passing wipe precheck output differs" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if case_wipe_flag; then pass "WP2: mode=wipe with the flag false and a stamp present -> wipe_variant=flip_chained (a stamp never reaches the separated variant), verdict=wipe_precondition_flag_not_true, exit 5, no pin work"
else fail "WP2: wipe over a false flag was not refused" "$(detail)"; fi
if wipe_run unset ABSENT "$ST8" wipe && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT"; then pass "WP2b: an UNSET flag under wipe refuses too (the final case no longer falls through to flag=unset exit 0)"
else fail "WP2b: wipe over an unset flag was not refused" "$(detail)"; fi
if wipe_run upper TRUE "$ST8" wipe && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT"; then pass "WP2c: 'TRUE' is not true under wipe either (exact compare)"
else fail "WP2c: TRUE passed the wipe flag predicate" "$(detail)"; fi
if case_wipe_stamp_absent; then pass "WP3: flag true and no GIT_DATA_LUKS_CUTOVER_AT -> verdict=wipe_precondition_stamp_absent, exit 5"
else fail "WP3: an absent stamp was not refused as stamp_absent" "$(detail)"; fi
_stn=0
for bad in '2026-10-07' '2026-10-07T00:00:00+00:00' '2026-13-45T99:99:99Z' '2026-02-30T00:00:00Z' 'not-a-timestamp' ' 2026-10-01T00:00:00Z' '2026-10-01T00:00:00Z extra' '2026-10-01 00:00:00Z' '@1700000000'; do
  if case_wipe_refuses "stamp-bad-$_stn" true "$bad" wipe_precondition_stamp_malformed; then :; else fail "WP4: malformed stamp [$bad] was not refused as stamp_malformed" "$(detail)"; fi
  _stn=$((_stn + 1))
done
if [ "$_stn" = 9 ]; then pass "WP4: 9 malformed or unparseable stamps (date-only, offset form, impossible month, 30 Feb, words, leading space, trailing text, no T, @epoch) each refuse as stamp_malformed (a non-empty stamp is PRESENT: never the separated variant)"
else fail "WP4: stamp loop ran $_stn rows, expected 9"; fi
if case_wipe_soak; then pass "WP5: a 6-day-old stamp -> verdict=wipe_precondition_soak_not_elapsed floor_days=7 elapsed_s=<n>, exit 5"
else fail "WP5: a 6-day stamp was not refused as soak_not_elapsed" "$(detail)"; fi
if case_wipe_refuses stamp-future true "$STFUT" wipe_precondition_soak_not_elapsed; then pass "WP5b: a stamp in the FUTURE is not elapsed time (soak_not_elapsed)"
else fail "WP5b: a future stamp was not refused" "$(detail)"; fi
if case_wipe_soak_env0; then pass "WP6: WIPE_SOAK_FLOOR_SECONDS=0 exported in the environment still refuses a 6-day stamp (no env path relaxes the floor)"
else fail "WP6: an exported zero floor relaxed the soak" "$(detail)"; fi
if case_wipe_refuses stamp-absent-env0 true ABSENT wipe_precondition_stamp_absent WIPE_SOAK_FLOOR_SECONDS=0; then pass "WP6b: with the floor env at 0 an absent stamp still refuses stamp_absent"
else fail "WP6b: a zero floor env let an absent stamp through" "$(detail)"; fi
if [ "$(grep -c '^readonly WIPE_SOAK_FLOOR_SECONDS=604800$' "$PRECHECK")" = 1 ] && ! grep -qF 'WIPE_SOAK_FLOOR_SECONDS:-' "$PRECHECK" && ! grep -qF 'WIPE_SOAK_FLOOR_SECONDS-' "$PRECHECK"; then pass "WP7: the floor is the unconditional constant 'readonly WIPE_SOAK_FLOOR_SECONDS=604800' (7 days), with no default-expansion form anywhere"
else fail "WP7: the soak floor line is not exactly the pinned constant"; fi
if wipe_run nl true "$ST8"$'\n' wipe && [ "$RC" = 0 ]; then pass "WP8 (must-PASS): a stamp with the trailing newline --plain prints is accepted"
else fail "WP8: a stamp with a trailing newline was refused" "$(detail)"; fi
wipe_run nostamp-probe true ABSENT wipe
if [ "$RC" = 5 ]; then pass "WP8b (harness): removing the stamp fixture turns the passing row RED (the soak rows are not vacuous)"
else fail "WP8b: the passing wipe row survived without a stamp fixture" "$(detail)"; fi
if wipe_run stamp-auth true "$ST8" wipe SHIM_STAMP_ERR=auth && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_stamp_read_failed reason=auth_invalid rc=1' "$OUT" && ! grep -q CANARY "$OUT"; then pass "WP9: an unreadable stamp -> verdict=wipe_stamp_read_failed reason=auth_invalid rc=1 (never stamp_absent), stderr not printed"
else fail "WP9: a failed stamp read was not wipe_stamp_read_failed" "$(detail)"; fi

# wipe_check: report-only. Every would-be refusal prints would_refuse=<word> and exits 0; the pin work still runs.
case_check() { # <label> <flag> <stamp> <expected-word>
  wipe_run "chk-$1" "$2" "$3" wipe_check
  [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT" | cut -d' ' -f1)" != "[git-data-flag-precheck]" ] && grep -qxF "would_refuse=$4" "$OUT" \
    && ! grep -qF 'verdict=' "$OUT" && grep -qF 'git_data_pin=present' "$OUT" && grep -qF GIT_DATA_LUKS_CUTOVER_AT "$DLOG"
}
if case_check off false "$ST8" wipe_precondition_flag_not_true; then pass "WC1: wipe_check with the flag false -> would_refuse=wipe_precondition_flag_not_true, exit 0, no verdict= line, the stamp read and the pin work still run"
else fail "WC1: wipe_check flag-off report differs" "$(detail)"; fi
if case_check stamp true ABSENT wipe_precondition_stamp_absent; then pass "WC2: wipe_check with no stamp -> would_refuse=wipe_precondition_stamp_absent, exit 0"
else fail "WC2: wipe_check stamp-absent report differs" "$(detail)"; fi
if case_check soak true "$ST6" wipe_precondition_soak_not_elapsed; then pass "WC3: wipe_check with a 6-day stamp -> would_refuse=wipe_precondition_soak_not_elapsed, exit 0"
else fail "WC3: wipe_check soak report differs" "$(detail)"; fi
if case_check ok true "$ST8" none && [ "$(sed -n 1p "$OUT")" = "wipe_variant=flip_chained" ] && [ "$(sed -n 2p "$OUT")" = "flag=true mode=wipe_check" ]; then pass "WC4: wipe_check with every predicate satisfied -> wipe_variant=flip_chained, flag=true mode=wipe_check, would_refuse=none, exit 0"
else fail "WC4: wipe_check pass report differs" "$(detail)"; fi
if wipe_run chk-stamp-auth true "$ST8" wipe_check SHIM_STAMP_ERR=network && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_stamp_read_failed reason=network rc=3' "$OUT"; then pass "WC5: an unreadable stamp is a read failure (exit 5) even in report-only mode, not a would_refuse"
else fail "WC5: wipe_check swallowed a stamp read failure" "$(detail)"; fi
if wipe_run chk-env0 true "$ST6" wipe_check WIPE_SOAK_FLOOR_SECONDS=0 && grep -qxF 'would_refuse=wipe_precondition_soak_not_elapsed' "$OUT"; then pass "WC6: the exported zero floor does not relax wipe_check's report either"
else fail "WC6: the zero floor env changed wipe_check's report" "$(detail)"; fi

# wipe_reread (W7b): flag only. No stamp, no pin, no TOFU, no deny-roots probe.
case_reread_ok() {
  wipe_run reread-ok true ABSENT wipe_reread WIPE_VARIANT=flip_chained
  [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "flag=true mode=wipe_reread" ] \
    && [ "$(cat "$DLOG")" = "$(printf '%s\n%s\n%s' 'doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd' 'doppler secrets get DOPPLER_PROJECT --plain -p soleur -c prd' 'doppler secrets get DOPPLER_CONFIG --plain -p soleur -c prd')" ] \
    && [ ! -e "$RT/git-data.pin" ]
}
if case_reread_ok; then pass "WR1: wipe_reread with the flag true -> exactly 'flag=true mode=wipe_reread', exit 0; 3 doppler calls (flag, project, config); no stamp read, no pin file, no TOFU or deny-roots line"
else fail "WR1: wipe_reread output or side effects differ" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if wipe_run reread-off false ABSENT wipe_reread WIPE_VARIANT=flip_chained && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT" && [ ! -e "$RT/git-data.pin" ]; then pass "WR2: wipe_reread with the flag no longer true -> verdict=wipe_precondition_flag_not_true, exit 5"
else fail "WR2: wipe_reread over a false flag was not refused" "$(detail)"; fi
if wipe_run reread-unset ABSENT ABSENT wipe_reread WIPE_VARIANT=flip_chained && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT"; then pass "WR3: wipe_reread over an unset flag refuses"
else fail "WR3: wipe_reread over an unset flag was not refused" "$(detail)"; fi
if wipe_run reread-scope ABSENT ABSENT wipe_reread SHIM_BOUND_CONFIG=prd_terraform && [ "$RC" = 5 ] && grep -qF 'verdict=flag_read_failed reason=scope_mismatch' "$OUT"; then pass "WR4: wipe_reread keeps the scope check (a token bound to another config is scope_mismatch)"
else fail "WR4: wipe_reread dropped the scope check" "$(detail)"; fi
if wipe_run reread-notoken true ABSENT wipe_reread DOPPLER_TOKEN= && [ "$RC" = 5 ] && grep -qF 'verdict=flag_token_absent' "$OUT" && [ ! -s "$DLOG" ]; then pass "WR5: wipe_reread without DOPPLER_TOKEN -> flag_token_absent, doppler never called"
else fail "WR5: wipe_reread ran without a token" "$(detail)"; fi
if wipe_run bogus true ABSENT wipe_bogus && [ "$RC" = 2 ] && grep -qF 'verdict=flag_mode_invalid' "$OUT"; then pass "WM1: the FLAG_MODE set stays closed (wipe_bogus -> flag_mode_invalid, exit 2)"
else fail "WM1: an unknown wipe-ish mode was accepted" "$(detail)"; fi

case_env_cannot_select() { wipe_run env-sep true "$ST8" wipe WIPE_VARIANT=separated && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=flip_chained" ] && wipe_run env-flip false ABSENT wipe WIPE_VARIANT=flip_chained && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=separated" ]; }
case_stamp_forces_flip_chained() { wipe_run stampbad-flagfalse false 'not-a-timestamp' wipe && [ "$RC" = 5 ] && grep -qxF 'wipe_variant=flip_chained' "$OUT" && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT"; }
case_flag_out_of_set() { wipe_run flag-bad-m off ABSENT wipe && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_unreadable' "$OUT" && ! grep -qxF 'wipe_variant=separated' "$OUT"; }
case_reread_no_expectation() { wipe_run rr-novar-m false ABSENT wipe_reread WIPE_VARIANT= && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_variant_changed expected=none' "$OUT"; }
case_reread_sep_stamp_appeared() { wipe_run rr-sep-stamp-m false "$ST8" wipe_reread WIPE_VARIANT=separated && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_variant_changed expected=separated got=flip_chained' "$OUT"; }
# ── A1 (2026-10-15): the separated variant. Chosen ONLY from in-session reads (flag, stamp); never from an input. ──
# Guard 6 rows 6a-6g (plan Amendment A1.2). The scan and boot_complete predicates run in a later workflow step.
if wipe_run sep-false false ABSENT wipe && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=separated" ] && grep -qF 'git_data_pin=present' "$OUT" && [ "$(tail -n 1 "$OUT")" = "flag=off" ] && ! grep -qF 'verdict=' "$OUT"; then pass "WV1: flag false and no stamp -> wipe_variant=separated as the FIRST line, exit 0, the pin work still runs"
else fail "WV1: the separated variant (flag false, no stamp) was not selected" "$(detail)"; fi
if wipe_run sep-unset ABSENT ABSENT wipe && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=separated" ] && [ "$(tail -n 1 "$OUT")" = "flag=unset" ]; then pass "WV2: an UNSET flag and no stamp -> wipe_variant=separated, exit 0"
else fail "WV2: the separated variant (flag unset, no stamp) was not selected" "$(detail)"; fi
_vn=0
for badflag in off disabled FALSE True 0 1 ' false' 'false ' yes; do
  if wipe_run "flag-bad-$_vn" "$badflag" ABSENT wipe && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_unreadable' "$OUT" && ! grep -qxF 'wipe_variant=separated' "$OUT" && ! grep -qF 'git_data_pin=' "$OUT"; then :; else fail "WV3: flag value [$badflag] with no stamp was not refused as flag_unreadable" "$(detail)"; fi
  _vn=$((_vn + 1))
done
if [ "$_vn" = 9 ]; then pass "WV3: 9 flag values outside the closed set (true|false|unset) with no stamp each refuse wipe_precondition_flag_unreadable and never select the separated variant"
else fail "WV3: flag loop ran $_vn rows, expected 9"; fi
if wipe_run flag-error false ABSENT wipe SHIM_ERR=network && [ "$RC" = 5 ] && grep -qF 'verdict=flag_read_failed' "$OUT" && ! grep -qF 'wipe_variant=separated' "$OUT"; then pass "WV4: a flag READ error stays flag_read_failed (exit 5) and never selects a variant"
else fail "WV4: a flag read error selected or masked a variant" "$(detail)"; fi
if wipe_run stampbad-flagfalse false 'not-a-timestamp' wipe && [ "$RC" = 5 ] && grep -qxF 'wipe_variant=flip_chained' "$OUT" && grep -qF 'verdict=wipe_precondition_flag_not_true' "$OUT"; then pass "WV5: a garbage stamp with the flag false is PRESENT: flip_chained, never separated (flag_not_true fires first)"
else fail "WV5: a garbage stamp reached the separated variant" "$(detail)"; fi
if wipe_run env-sep true "$ST8" wipe WIPE_VARIANT=separated && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=flip_chained" ]; then pass "WV6: an exported WIPE_VARIANT=separated does not select the variant: flag true and a stamp are still flip_chained"
else fail "WV6: an environment value selected the variant" "$(detail)"; fi
if wipe_run env-flip false ABSENT wipe WIPE_VARIANT=flip_chained && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=separated" ]; then pass "WV7: an exported WIPE_VARIANT=flip_chained does not select the variant either: flag false and no stamp are still separated"
else fail "WV7: an environment value selected the variant" "$(detail)"; fi
if wipe_run chk-sep false ABSENT wipe_check && [ "$RC" = 0 ] && [ "$(sed -n 1p "$OUT")" = "wipe_variant=separated" ] && grep -qxF 'would_refuse=none' "$OUT"; then pass "WV8: wipe_check in the separated state -> wipe_variant=separated, would_refuse=none, exit 0"
else fail "WV8: wipe_check did not report the separated variant" "$(detail)"; fi
if wipe_run chk-badflag off ABSENT wipe_check && [ "$RC" = 0 ] && grep -qxF 'would_refuse=wipe_precondition_flag_unreadable' "$OUT" && grep -qxF 'wipe_variant=none' "$OUT"; then pass "WV9: wipe_check over an out-of-set flag value -> wipe_variant=none, would_refuse=wipe_precondition_flag_unreadable, exit 0"
else fail "WV9: wipe_check over an out-of-set flag differs" "$(detail)"; fi
# wipe_reread: the variant W3 printed is passed back as WIPE_VARIANT (an EXPECTATION, compared, never a selector).
if wipe_run rr-sep false ABSENT wipe_reread WIPE_VARIANT=separated && [ "$RC" = 0 ] && [ "$(cat "$OUT")" = "wipe_variant=separated mode=wipe_reread" ] \
   && [ "$(wc -l < "$DLOG")" = 4 ] && grep -qF GIT_DATA_LUKS_CUTOVER_AT "$DLOG" && [ ! -e "$RT/git-data.pin" ]; then pass "WV10: wipe_reread expecting separated, flag still false and no stamp -> 'wipe_variant=separated mode=wipe_reread', exit 0; 4 doppler calls (flag, project, config, stamp); no pin file"
else fail "WV10: wipe_reread did not re-confirm the separated variant" "$(detail) dlog=[$(tr '\n' '|' < "$DLOG")]"; fi
if wipe_run rr-sep-stamp false "$ST8" wipe_reread WIPE_VARIANT=separated && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_variant_changed expected=separated got=flip_chained' "$OUT"; then pass "WV11: wipe_reread expecting separated but a stamp appeared -> wipe_precondition_variant_changed expected=separated got=flip_chained"
else fail "WV11: a stamp appearing between W3 and W7b was not refused" "$(detail)"; fi
if wipe_run rr-sep-flagtrue true ABSENT wipe_reread WIPE_VARIANT=separated && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_variant_changed expected=separated got=flip_chained' "$OUT"; then pass "WV12: wipe_reread expecting separated but the flag turned true -> wipe_precondition_variant_changed (a flip began in between)"
else fail "WV12: a flag flip between W3 and W7b was not refused" "$(detail)"; fi
if wipe_run rr-sep-badflag off ABSENT wipe_reread WIPE_VARIANT=separated && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_flag_unreadable' "$OUT"; then pass "WV13: wipe_reread expecting separated over an out-of-set flag value -> wipe_precondition_flag_unreadable"
else fail "WV13: wipe_reread accepted an out-of-set flag value" "$(detail)"; fi
_wn=0
for badvar in '' none 'separated ' SEPARATED flip_chained2 sep; do
  if wipe_run "rr-novar-$_wn" false ABSENT wipe_reread WIPE_VARIANT="$badvar" && [ "$RC" = 5 ] && grep -qF 'verdict=wipe_precondition_variant_changed expected=none' "$OUT"; then :; else fail "WV14: wipe_reread with WIPE_VARIANT=[$badvar] was not refused as expected=none" "$(detail)"; fi
  _wn=$((_wn + 1))
done
if [ "$_wn" = 6 ]; then pass "WV14: wipe_reread with an empty or off-set WIPE_VARIANT refuses wipe_precondition_variant_changed expected=none (fail closed: the expectation is required)"
else fail "WV14: expectation loop ran $_wn rows, expected 6"; fi

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
run = [i for i, s in enumerate(steps) if isinstance(s.get("env"), dict) and s["env"].get("MODE") in ("proof", "freeze", "unfreeze", "probe")]
check("G1-order: exactly one flag precheck step, and it precedes the bridge, the key fetch and every host-side verb step",
      len(pre) == 1 and len(bridge) == 1 and len(key) == 1 and len(run) == 4 and pre[0] < bridge[0] and pre[0] < key[0] and all(pre[0] < r for r in run),
      (pre, bridge, key, run))
p = steps[pre[0]] if len(pre) == 1 else {}
check("G1-step: the precheck step runs the script, gated only off redeploy (the mode that never touches git-data), no continue-on-error",
      "git-data-flag-precheck.sh" in str(p.get("run", "")) and "redeploy" in str(p.get("if")) and not p.get("continue-on-error"), p)
check("G1-env: the precheck step binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD, FLAG_MODE}",
      p.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}", "FLAG_MODE": "${{ steps.confirm.outputs.mode }}"}, p.get("env"))
cfg = [i for i, s in enumerate(steps) if s.get("id") == "ssh_config"]
pin_users = [s.get("id") or s.get("name") for s in steps if "git-data.pin" in json.dumps(s)]
check("G1-pin: the pin the precheck writes is read by the ssh_config step, which runs after the precheck and the bridge",
      len(cfg) == 1 and len(pre) == 1 and len(bridge) == 1 and pre[0] < bridge[0] < cfg[0]
      and "ssh_config" in pin_users and all(u in ("ssh_config", "Tear down cloudflared SSH bridge") for u in pin_users), (pre, bridge, cfg, pin_users))
sites = [("step", s.get("id") or s.get("name")) for s in steps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
job = (wf.get("jobs") or {}).get("cutover") or {}
sites += [("job", k) for k, v in job.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("top", k) for k, v in wf.items() if k != "jobs" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
# The wipe job (#10138) legitimately reads the prd flag in exactly two steps (the W3 precheck and the W7b
# re-read); every OTHER job, and every other wipe-job site, is still a violation.
wipe = (wf.get("jobs") or {}).get("wipe") or {}
wsteps = wipe.get("steps") or []
wsites = [("step", s.get("id") or s.get("name")) for s in wsteps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
wsites += [("job", k) for k, v in wipe.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
sites += [("job", j) for j, b in (wf.get("jobs") or {}).items() if j not in ("cutover", "wipe") and "DOPPLER_TOKEN_PRD" in json.dumps(b, default=str)]
# The exact shape of each allowed site: the secret is named ONCE, as env.DOPPLER_TOKEN of the step, nowhere in its run text.
def prd_once_as_env(s):
    return (json.dumps(s).count("DOPPLER_TOKEN_PRD") == 1 and (s.get("env") or {}).get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN_PRD }}")
allowed = [s for s in steps if s.get("id") == "flag_precheck"] + [s for s in wsteps if s.get("id") in ("wipe_flag_precheck", "wipe_flag_reread")]
check("G1-census: DOPPLER_TOKEN_PRD is named only by cutover.flag_precheck, wipe.wipe_flag_precheck and wipe.wipe_flag_reread, once each, as the step's env DOPPLER_TOKEN (%d + %d steps scanned)" % (len(steps), len(wsteps)),
      len(steps) >= 1 and len(wsteps) >= 1 and sites == [("step", "flag_precheck")]
      and wsites == [("step", "wipe_flag_precheck"), ("step", "wipe_flag_reread")]
      and len(allowed) == 3 and all(prd_once_as_env(s) for s in allowed), (sites, wsites))
# #9725: the flip must also require the SERVED image to carry the dual-root
# tenant deny — the GIT_DATA_DENY_FLOOR arm (env bound, refusal emitted).
fp = [s for s in steps if s.get("id") == "flip_preconditions"]
check("G1-denyfloor: flip_preconditions binds vars.GIT_DATA_DENY_FLOOR and refuses via sandbox_deny_floor",
      len(fp) == 1 and "GIT_DATA_DENY_FLOOR" in json.dumps(fp[0].get("env", {}))
      and "sandbox_deny_floor" in str(fp[0].get("run", "")), fp)
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
[ "$_wf_n" -ge 8 ] || fail "G1: only $_wf_n workflow verdicts were produced (expected 8) — the YAML leg crashed" "$(head -c 300 "$T/wf.err")"

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
if mutate precheck-after-bridge "$WF" 28 "python:$T/mut/reorder.py"; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-order.tsv" 2>&1
  mutant_red precheck-after-bridge wf_row "$T/mut/wf-order.tsv" "G1-order:"
fi
# Row 3 — bind DOPPLER_TOKEN_PRD in the script step's env as well.
# shellcheck disable=SC2016
if mutate prd-in-script-step "$WF" 1 's#^          MODE: proof$#&\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-census.tsv" 2>&1
  mutant_red prd-in-script-step wf_row "$T/mut/wf-census.tsv" "G1-census:"
fi
# Row 3b — the wipe job's root-key fetch step is re-pointed at the prd flag token: a third wipe site.
# shellcheck disable=SC2016
if mutate prd-in-wipe-key-fetch "$WF" 2 '/id: wipe_key_fetch/,/^        run:/ s#DOPPLER_TOKEN_GIT_DATA_ROOT#DOPPLER_TOKEN_PRD#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-census-wipe.tsv" 2>&1
  mutant_red prd-in-wipe-key-fetch wf_row "$T/mut/wf-census-wipe.tsv" "G1-census:"
fi
# Row 3c — a fourth job (not cutover, not wipe) binds the prd flag token: the per-job allow-list is closed.
# shellcheck disable=SC2016
if mutate prd-in-notify-job "$WF" 2 '/^  notify-failure:/,/^    steps:/ s#^    steps:$#    env:\n      DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}\n    steps:#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" > "$T/mut/wf-census-job.tsv" 2>&1
  mutant_red prd-in-notify-job wf_row "$T/mut/wf-census-job.tsv" "G1-census:"
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
# Row 17 — neuter the SANDBOX_DENY_ROOTS flip gate: an absent-coverage flip
# must then proceed (the refusal is the arm's whole point).
if mutate deny-flip-gate "$PRECHECK" 2 's#"\$FLAG_MODE" = flip#"\$FLAG_MODE" = flip_never#'; then
  CASE_SCRIPT="$MUTANT" mutant_red deny-flip-gate case_deny_absent_flip_refused
fi
# Row 18 — neuter the WRITE-arm deny gate: a `true` write over absent coverage
# then reaches doppler (the write arm is the gate the flip-gate can't cover —
# it exits before the read probes run).
if mutate deny-write-gate "$PRECHECK" 2 's#"\$FLAG_WRITE_VALUE" = true#"\$FLAG_WRITE_VALUE" = never#'; then
  CASE_SCRIPT="$MUTANT" mutant_red deny-write-gate case_write_deny_absent_true_refused
fi

# ── Guard 6 mutation rows (#10138): the soak floor is one pinned constant ──────────────────────────
# M-wipe-floor-zero: the constant at zero. A 6-day stamp then passes (the soak row goes RED); an absent stamp must
# STILL refuse stamp_absent (the predicates are separate), checked against the same mutant copy.
# shellcheck disable=SC2016
if mutate wipe-floor-zero "$PRECHECK" 2 's#^readonly WIPE_SOAK_FLOOR_SECONDS=604800$#readonly WIPE_SOAK_FLOOR_SECONDS=0#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-floor-zero case_wipe_soak
  if CASE_SCRIPT="$MUTANT" case_wipe_stamp_absent; then pass "M-wipe-floor-zero (must-refuse): with the floor at zero an absent stamp STILL refuses stamp_absent"
  else fail "M-wipe-floor-zero: a zero floor let an absent stamp through" "$(detail)"; fi
fi
# M-wipe-floor-default-form: the constant becomes `${VAR:-604800}`; an exported 0 then relaxes it.
# shellcheck disable=SC2016
if mutate wipe-floor-default-form "$PRECHECK" 2 's#^readonly WIPE_SOAK_FLOOR_SECONDS=604800$#readonly WIPE_SOAK_FLOOR_SECONDS="${WIPE_SOAK_FLOOR_SECONDS:-604800}"#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-floor-default-form case_wipe_soak_env0
fi
# M-wipe-flag-predicate: drop the flag-true predicate. A false flag then passes under wipe.
if mutate wipe-flag-predicate "$PRECHECK" 2 's#wipe_word=wipe_precondition_flag_not_true$#wipe_word=#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-flag-predicate case_wipe_flag
fi
# M-wipe-stamp-predicate: drop the stamp-present predicate.
# shellcheck disable=SC2016
if mutate wipe-stamp-predicate "$PRECHECK" 2 's#^          absent\)    wipe_word=wipe_precondition_stamp_absent ;;$#          absent)    : ;;#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-stamp-predicate case_wipe_stamp_absent
fi
# M-wipe-soak-predicate: drop the elapsed-time comparison.
# shellcheck disable=SC2016
if mutate wipe-soak-predicate "$PRECHECK" 2 's#elapsed_s" -lt "\$WIPE_SOAK_FLOOR_SECONDS" \]; then$#elapsed_s" -lt 0 ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-soak-predicate case_wipe_soak
fi
# M-wipe-reread-gone: wipe_reread falls into the generic path (stamp-free, but pin + TOFU + deny lines appear).
# shellcheck disable=SC2016
if mutate wipe-reread-gone "$PRECHECK" 2 's#^if \[ "\$FLAG_MODE" = wipe_reread \]; then$#if [ "$FLAG_MODE" = wipe_reread_never ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-reread-gone case_reread_ok
fi
# M-wipe-check-refuses: the report-only mode refuses like wipe.
# shellcheck disable=SC2016
if mutate wipe-check-refuses "$PRECHECK" 2 's#^  if \[ "\$FLAG_MODE" = wipe \]; then$#  if [ "$FLAG_MODE" = wipe ] || [ "$FLAG_MODE" = wipe_check ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red wipe-check-refuses case_check soak true "$ST6" wipe_precondition_soak_not_elapsed
fi

# ── A1 mutants (Guard 6 rows 6a-6g): the separated variant is reachable only from in-session reads ──────────
# M-sep-from-env: the variant honours an exported WIPE_VARIANT. WV6 goes RED.
# shellcheck disable=SC2016
if mutate sep-from-env "$PRECHECK" 2 's#^  wipe_variant="\$\(select_variant "\$flag" "\$CLS_STAMP_STATE"\)"$#  wipe_variant="${WIPE_VARIANT:-$(select_variant "$flag" "$CLS_STAMP_STATE")}"#'; then
  CASE_SCRIPT="$MUTANT" mutant_red sep-from-env case_env_cannot_select
fi
# M-sep-ignores-stamp: a present stamp no longer forces flip_chained. WV5 (garbage stamp, flag false) goes RED.
# shellcheck disable=SC2016
if mutate sep-ignores-stamp "$PRECHECK" 2 's#^  if \[ "\$1" = true \] \|\| \[ "\$2" != absent \]; then echo flip_chained$#  if [ "$1" = true ]; then echo flip_chained#'; then
  CASE_SCRIPT="$MUTANT" mutant_red sep-ignores-stamp case_stamp_forces_flip_chained
fi
# M-sep-open-set: any flag value outside true|false|unset still selects separated. WV3 goes RED.
# shellcheck disable=SC2016
if mutate sep-open-set "$PRECHECK" 2 's#^  elif \[ -z "\$1" \] \|\| \[ "\$1" = false \]; then echo separated$#  elif true; then echo separated#'; then
  CASE_SCRIPT="$MUTANT" mutant_red sep-open-set case_flag_out_of_set
fi
# M-reread-no-expect: wipe_reread without a valid expectation exits 0 instead of refusing. WV14 goes RED.
# shellcheck disable=SC2016
if mutate reread-no-expect "$PRECHECK" 2 's#^      refuse "wipe_precondition_variant_changed expected=none"$#      echo ok; exit 0#'; then
  CASE_SCRIPT="$MUTANT" mutant_red reread-no-expect case_reread_no_expectation
fi
# M-reread-sep-no-compare: the separated re-read stops comparing the recomputed variant. WV11 goes RED.
# shellcheck disable=SC2016
if mutate reread-sep-no-compare "$PRECHECK" 2 's#^      if \[ "\$got" != separated \]; then$#      if false; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red reread-sep-no-compare case_reread_sep_stamp_appeared
fi

# ── Stamp-clear mutants (#10297): each guard of the rollback arm goes RED when removed ───────────────────────────
# M-rb-no-delete: the delete call becomes a read (exit 0, nothing deleted). RB1 goes RED.
if mutate rb-no-delete "$PRECHECK" 2 's#doppler secrets delete GIT_DATA_LUKS_CUTOVER_AT -p soleur -c prd --yes#doppler secrets get GIT_DATA_LUKS_CUTOVER_AT --plain -p soleur -c prd#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-no-delete case_rb_clears
fi
# M-rb-no-readback: a delete that did not take is accepted. RB5 goes RED.
# shellcheck disable=SC2016
if mutate rb-no-readback "$PRECHECK" 2 's#^      \[ -z "\$cur" \] \|\| clear_fail readback still_present$#      :#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-no-readback case_rb_delete_refused rb-noop 'step=readback reason=still_present' SHIM_DELETE_NOOP=1
fi
# M-rb-delete-failure-ignored: a refused delete no longer fails the step at the delete. RB4 goes RED.
# shellcheck disable=SC2016
if mutate rb-delete-failure-ignored "$PRECHECK" 2 's#^        clear_fail delete "\$\(reason_of "\$ERRF"\)"$#        :#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-delete-failure-ignored case_rb_delete_refused rb-forbidden 'step=delete reason=forbidden' SHIM_DELETE_ERR=forbidden
fi
# M-rb-read-failure-as-absent: an unreadable stamp reads as absent and the flag is written. RB7 goes RED.
# shellcheck disable=SC2016
if mutate rb-read-failure-as-absent "$PRECHECK" 2 's#\|\| clear_fail read "#|| : "#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-read-failure-as-absent case_rb_delete_refused rb-read 'step=read reason=network' SHIM_STAMP_ERR=network
fi
# M-rb-delete-without-yes: the delete would prompt on the real CLI (the shim refuses it). RB1 goes RED.
# shellcheck disable=SC2016
if mutate rb-delete-without-yes "$PRECHECK" 2 's#(secrets delete GIT_DATA_LUKS_CUTOVER_AT -p soleur -c prd) --yes#\1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-delete-without-yes case_rb_clears
fi
# M-rb-delete-stdout-leaked: the delete's stdout (the config's remaining secrets on the real CLI) is no longer discarded. RB1 goes RED.
# shellcheck disable=SC2016
if mutate rb-delete-stdout-leaked "$PRECHECK" 2 's#(secrets delete GIT_DATA_LUKS_CUTOVER_AT -p soleur -c prd --yes) >/dev/null#\1#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-delete-stdout-leaked case_rb_clears
fi
# M-rb-read-token: the delete rides the read token, not the write seam. RB2 goes RED.
# shellcheck disable=SC2016
if mutate rb-read-token "$PRECHECK" 2 's#DOPPLER_TOKEN="\$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets delete#doppler secrets delete#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-read-token case_rb_token
fi
# M-rb-any-mode: the clear loses its mode key, so an unfreeze/proof false write clears the anchor. RB11 goes RED.
# shellcheck disable=SC2016
if mutate rb-any-mode "$PRECHECK" 2 's#^  if \[ "\$FLAG_MODE" = rollback \] && \[ "\$FLAG_WRITE_VALUE" = false \]; then$#  if [ "$FLAG_WRITE_VALUE" = false ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-any-mode case_rb_other_modes unfreeze
fi
# M-rb-any-value: the clear loses its value key, so a true write under rollback mode clears the anchor. RB10 goes RED.
# shellcheck disable=SC2016
if mutate rb-any-value "$PRECHECK" 2 's#^  if \[ "\$FLAG_MODE" = rollback \] && \[ "\$FLAG_WRITE_VALUE" = false \]; then$#  if [ "$FLAG_MODE" = rollback ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-any-value case_rb_value_true
fi
# M-rb-after-flag: the clear block moves AFTER the flag write and its read-back (the stranded-fleet order). RB4 goes RED
# because the flag is then already written when the delete is refused.
cat > "$T/mut/rb-after-flag.py" <<'PY'
import sys
p = sys.argv[1]
src = open(p).read().split("\n")
a = next(i for i, l in enumerate(src) if l.startswith("  # #10297: the rollback arm clears"))
b = next(i for i, l in enumerate(src) if l.startswith("  # stdin carries the value (never argv)"))
block = src[a:b]
rest = src[:a] + src[b:]
c = next(i for i, l in enumerate(rest) if l.startswith('  echo "flag_write=ok value='))
open(p, "w").write("\n".join(rest[:c] + block + rest[c:]))
PY
if mutate rb-after-flag "$PRECHECK" 36 "python:$T/mut/rb-after-flag.py"; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-after-flag case_rb_delete_refused rb-forbidden 'step=delete reason=forbidden' SHIM_DELETE_ERR=forbidden
fi

# M-rb-readback-failure-as-absent: an unreadable read-back reads as cleared. RB6 goes RED.
# shellcheck disable=SC2016
if mutate rb-readback-failure-as-absent "$PRECHECK" 2 's#\|\| clear_fail readback "#|| : "#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-readback-failure-as-absent case_rb_delete_refused rb-rbread 'step=readback reason=network' SHIM_STAMP_READBACK_ERR=network
fi
# M-rb-trimmed-presence: a whitespace-only stamp reads as absent and is never deleted. RB12 goes RED.
# shellcheck disable=SC2016
if mutate rb-trimmed-presence "$PRECHECK" 2 's#^    if \[ -n "\$cur" \]; then$#    if [ -n "${cur//[[:space:]]/}" ]; then#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-trimmed-presence rb_ws_cleared
fi
# M-rb-trimmed-readback: a residual whitespace-only stamp reads as cleared. RB13 goes RED.
# shellcheck disable=SC2016
if mutate rb-trimmed-readback "$PRECHECK" 2 's#^      \[ -z "\$cur" \] \|\| clear_fail readback still_present$#      [ -z "${cur//[[:space:]]/}" ] || clear_fail readback still_present#'; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-trimmed-readback rb_ws_noop_refused
fi
# M-rb-clear-before-credential-guard: the clear block moves above the write-credential guard. RB14 goes RED.
cat > "$T/mut/rb-before-cred.py" <<'PY'
import sys
p = sys.argv[1]
src = open(p).read().split("\n")
a = next(i for i, l in enumerate(src) if l.startswith("  # #10297: the rollback arm clears"))
b = next(i for i, l in enumerate(src) if l.startswith("  # stdin carries the value (never argv)"))
block = src[a:b]
rest = src[:a] + src[b:]
c = next(i for i, l in enumerate(rest) if l.startswith('  if [ -z "${DOPPLER_TOKEN_GIT_DATA_FLAG:-}" ]; then'))
open(p, "w").write("\n".join(rest[:c] + block + rest[c:]))
PY
if mutate rb-clear-before-credential-guard "$PRECHECK" 14 "python:$T/mut/rb-before-cred.py"; then
  CASE_SCRIPT="$MUTANT" mutant_red rb-clear-before-credential-guard rb_nocred_refused
fi

# ── SANDBOX_DENY_ROOTS arm (#9725) ────────────────────────────────────────────────
if case_deny absent "$T/deny-absent" proof   && [ "$RC" = 0 ] && grep -qF 'SANDBOX_DENY_ROOTS absent' "$OUT"; then
  pass "D1: source without the deny-root markers under proof -> SANDBOX_DENY_ROOTS absent, informational only (exit 0)"
else fail "D1: absent markers were not reported" "$(detail)"; fi
if case_deny present "$T/deny-present" proof   && [ "$RC" = 0 ] && grep -qF 'SANDBOX_DENY_ROOTS present' "$OUT"; then
  pass "D2: source carrying the markers -> SANDBOX_DENY_ROOTS present"
else fail "D2: a present fixture was not reported" "$(detail)"; fi
if case_deny unknown "$T/no-such-src" proof   && [ "$RC" = 0 ] && grep -qF 'SANDBOX_DENY_ROOTS unknown' "$OUT"; then
  pass "D3: unreadable source dir -> SANDBOX_DENY_ROOTS unknown (never absent)"
else fail "D3: an unreadable dir was not unknown" "$(detail)"; fi
if case_deny absent-flip "$T/deny-absent" flip   && [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_absent' "$OUT"; then
  pass "D4: flip without the deny coverage -> verdict=sandbox_deny_coverage_absent, exit 5 (blocking)"
else fail "D4: a flip over absent coverage was not refused" "$(detail)"; fi
if case_deny unknown-flip "$T/no-such-src" flip   && [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_unknown' "$OUT"; then
  pass "D5: flip with unreadable source -> verdict=sandbox_deny_coverage_unknown, exit 5 (fail closed)"
else fail "D5: a flip over unknown coverage was not refused" "$(detail)"; fi
if case_deny present-flip "$T/deny-present" flip   && [ "$RC" = 0 ] && grep -qF 'SANDBOX_DENY_ROOTS present' "$OUT" && grep -qF 'flag=off' "$OUT"; then
  pass "D6: flip WITH the coverage -> SANDBOX_DENY_ROOTS present, proceeds to pin + flag=off"
else fail "D6: a covered flip was refused or lost the pin" "$(detail)"; fi
if case_deny collapsed-flip "$T/deny-collapsed" flip   && [ "$RC" = 5 ] && grep -qF 'verdict=sandbox_deny_coverage_absent' "$OUT"; then
  pass "D7: the flag-COLLAPSED helper shape (env read outside the deny fn) -> sandbox_deny_coverage_absent — the function-scope needle catches the #9725 form"
else fail "D7: flag-collapsed helper shape was not detected as absent" "$(detail)"; fi

# ── pin_only (review of #10352): snapshot_clear needs the host-key pin and nothing else from this script ────────────
# The REAL script, a doppler shim for the store: the pin is written and fingerprinted, no variant line, no flag verdict.
case_pin_only_ok() { # <flag value>
  wipe_run "po-$1" "$1" ABSENT pin_only && [ "$RC" = 0 ] && grep -qF 'git_data_pin=present fp=SHA256:' "$OUT" \
    && ! grep -qF 'wipe_variant=' "$OUT" && ! grep -qF 'verdict=' "$OUT" && [ -s "$RT/git-data.pin" ] && [ "$(stat -c %a "$RT/git-data.pin")" = 444 ]
}
if case_pin_only_ok false && case_pin_only_ok true; then pass "PO1: pin_only writes the 0444 host-key pin and prints git_data_pin=present with NO wipe_variant line and NO verdict, whether the flag is false or true (the flag value is irrelevant to it)"
else fail "PO1: pin_only did not write the pin cleanly" "$(detail)"; fi
CASE_PIN=ABSENT wipe_run po-pinabsent false ABSENT pin_only
if [ "$RC" = 5 ] && grep -qF 'verdict=git_data_host_key_unavailable reason=absent' "$OUT" && [ ! -e "$RT/git-data.pin" ]; then pass "PO2: pin_only with the pin ABSENT still refuses git_data_host_key_unavailable reason=absent and writes no pin file"
else fail "PO2: pin_only accepted an absent pin" "$(detail)"; fi
if wipe_run po-badmode false ABSENT pin_only_x && [ "$RC" = 2 ] && grep -qF 'verdict=flag_mode_invalid' "$OUT"; then pass "PO3: a near-miss mode name is still refused flag_mode_invalid (pin_only is an exact member of the closed set)"
else fail "PO3: an unknown mode was accepted" "$(detail)"; fi
# shellcheck disable=SC2016  # sed programs are data
if mutate pin-only-dropped "$PRECHECK" 2 's#\|wipe_reread\|pin_only\) : ;;#|wipe_reread) : ;;#'; then
  CASE_SCRIPT="$MUTANT" mutant_red pin-only-dropped case_pin_only_ok false
fi

# ── FLOOR + LEDGER ────────────────────────────────────────────────────────────────────
MUTANT_FLOOR=48  # Guard 1 matrix rows 1-8, pin rows 9-16 (with 10b), deny-refusal 17, wipe Guard 6 rows (7), census rows 3b and 3c, A1 variant rows (5), stamp-clear rows (14, #10297)
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2; exit 1
fi
# Assertion FLOOR: script cases 33 + pin/TOFU_ARM cases 15 (K1-K11 with K3b/K3c/K10b/K10c) + workflow rows 8 + deny-arm rows 7 + mutants 19 x 2 + census mutants 2 x 2 + wipe rows 26 + wipe mutants 7 x 2 + 1 must-refuse row = 146, plus the A1 (2026-10-15) variant rows WV1-WV14 (14) and 5 A1 mutants x 2 (10) = 170 (exact).
# #10297 stamp-clear: RB1-RB10, RB11a/b, RB12-RB14 (15) + 14 mutants x 2 (28) = 43 more, so the count is 175 + 43 = 218 (a -lt floor: scripts/guard-vacuity-floor.test.sh only recognises -lt/-le/-ge, so this suite stays out of -ne).
FLOOR=218
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
