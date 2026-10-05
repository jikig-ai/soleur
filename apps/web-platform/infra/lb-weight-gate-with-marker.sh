#!/usr/bin/env bash
# lb-weight-gate-with-marker.sh — the ONE seam through which WORKSPACES_LUKS_CUTOVER_AT reaches
# lb-weight-gate.sh (#9358, ADR-143 D3 coupling #2, ADR-263).
#
# lb-weight-gate.sh is PURE and env-only: it never calls Doppler. Until this file existed nothing
# sourced the soak marker into its environment, so the web-2 flip precondition could only ever read
# "absent" (fail closed, correctly, but unusable). This wrapper reads the marker ONCE, from the exact
# dedicated config the daily workspaces-luks-verify.yml `web2_marker` job writes, and then exec()s the
# gate. The deferred cutover orchestrator calls THIS file; no other script may invoke the gate (the
# census in lb-weight-gate-with-marker.test.sh fails if one does).
#
# WHAT IT DOES, IN ORDER (each step is a Guard 5 mutation row in the test):
#   1. Pins PATH, unsets BASH_ENV/ENV, and DISCARDS any caller-supplied WORKSPACES_LUKS_CUTOVER_AT: a
#      value planted in the caller's environment must never stand in for the Doppler value.
#   2. Requires DOPPLER_TOKEN. (No read-only token on the marker config exists today — the CI write
#      token is read/write — so minting one is a prerequisite recorded on #9358 for the orchestrator;
#      this wrapper only ever READS: `secrets --only-names` and `secrets get`.)
#   3. Tells "not found" from a transport error WITHOUT parsing stderr: list the config's secret NAMES
#      first (any failure => exit 3, the gate never runs), then an EXACT-name membership test. A
#      prefix-colliding name (WORKSPACES_LUKS_CUTOVER_AT_OLD) does not satisfy it.
#   4. Absent name  => the variable stays unset and the gate fails closed on
#      B_workspaces_luks_marker_absent. Present name => read it with the single-secret form
#      (`get NAME --plain`, never `doppler run` / `secrets download`: CWE-522). A failure of that get
#      AFTER a positive membership test is exit 3, never "absent": the two calls are a TOCTOU window.
#   5. Shape-validates the value (the ISO shape the gate expects; a malformed value exits 4 and is
#      never exported).
#   6. exec()s the gate through `env -i` with an EXPLICIT ALLOWLIST: the pinned PATH plus exactly the
#      variables lb-weight-gate.sh reads (GATE_ENV_ALLOW below; the test derives that set from the gate
#      itself and fails on drift). Nothing else is inherited — no DOPPLER_* (valid or not as a shell
#      identifier: `DOPPLER-API-HOST`), no exported function (`BASH_FUNC_date%%`), no token. The gate
#      never calls Doppler and must not inherit a read/write token or a spoofed `date`.
#      The Doppler calls themselves get DOPPLER_CONFIG_DIR pointed at an empty private directory, so a
#      planted ~/.doppler config cannot steer them (api-host, token, scope).
#
# The wrapper handles ONLY the WORKSPACES marker. GIT_DATA_LUKS_CUTOVER_AT and the rest of the gate's
# environment (weights, rotation, roster, soak days) remain the orchestrator's.
#
# PROVENANCE IS NOT ASSERTED. The value is advisory and shape-only downstream: a value planted in the
# shared `prd` config shows through the branch config (ADR-263 records this), and nothing here
# validates who wrote it.
#
# EXIT CODES: 0/1 are the gate's own (exec propagates them); 3 = the marker could not be read from
# Doppler (no token, transport/credential/query fault; the gate did NOT run); 4 = the marker value is
# present but malformed (the gate did NOT run); 97 is unreachable (guards the exec).
set -euo pipefail
case "$-" in
  *x*)
    if [ -n "${DOPPLER_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

PINNED_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PATH="$PINNED_PATH"
export PATH
TMPDIR=/tmp # the private Doppler config dir below is created here whatever TMPDIR the caller exported
export TMPDIR
unset BASH_ENV ENV
# Exported functions (BASH_FUNC_*) must not shadow env/rm/mktemp/... inside this wrapper either.
while IFS= read -r _fn; do builtin unset -f -- "$_fn"; done < <(builtin compgen -A function) # seam:purge-functions
unset _fn

# The ONLY variables the gate may inherit besides PATH. DERIVED from lb-weight-gate.sh (every NAME that
# the gate expands as `${NAME-`, `${NAME:-` or `${NAME+`), not guessed; lb-weight-gate-with-marker.test.sh
# re-derives the set from the gate and fails if this array drifts from it. A variable that is UNSET here
# stays unset in the gate (the gate distinguishes unset from empty for SOLEUR_SERVING_ROTATION).
GATE_ENV_ALLOW=(
  SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_SERVING_ROTATION
  SOLEUR_PROXY_BIND SOLEUR_PROXY_PEER_ALLOWLIST SOLEUR_HOST_ROSTER
  GIT_DATA_STORE_ENABLED GIT_DATA_LUKS_SOAK_DAYS GIT_DATA_LUKS_CUTOVER_AT
  WORKSPACES_LUKS_SOAK_DAYS WORKSPACES_LUKS_CUTOVER_AT
)

# Constants — parity-pinned to scripts/lib/web2-luks-rows.sh W2L_MARKER_NAME/PROJECT/CONFIG by the test.
MARKER_NAME="WORKSPACES_LUKS_CUTOVER_AT"
MARKER_PROJECT="soleur"
MARKER_CONFIG="prd_workspaces_luks_marker"

# Parity-pinned to lb-weight-gate.sh's own ISO_RE by the test.
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$'

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${SELF_DIR}/lb-weight-gate.sh"

unset WORKSPACES_LUKS_CUTOVER_AT # seam:unset-caller

src_fail() {
  # $1 = class. Never prints Doppler's own output (it can carry request detail).
  echo "marker_source_fail class=$1 marker=${MARKER_NAME} config=${MARKER_CONFIG} gate_not_run=true" >&2
  exit 3
}

[[ -n "${DOPPLER_TOKEN-}" ]] || src_fail "no_token" # seam:token-required
doppler_token="$DOPPLER_TOKEN"

# The child environment of every Doppler call is built explicitly: nothing but the pinned PATH, HOME,
# the token and an EMPTY PRIVATE DOPPLER_CONFIG_DIR reaches it (a planted ~/.doppler/.doppler.yaml or a
# caller-supplied DOPPLER_CONFIG_DIR therefore cannot set api-host/token/scope; the dir is created under a
# pinned /tmp so a caller TMPDIR cannot break or steer it), and the config/project
# come from FLAGS (the CLI is last-value-wins on flags and an ambient DOPPLER_CONFIG/DOPPLER_PROJECT
# must not be able to steer it).
DOPPLER_CFG_DIR="$(mktemp -d)" || src_fail "no_confdir" # seam:confdir
trap 'rm -rf "$DOPPLER_CFG_DIR"' EXIT
doppler_ro() {
  env -i PATH="$PINNED_PATH" HOME="${HOME:-/nonexistent}" DOPPLER_TOKEN="$doppler_token" \
    DOPPLER_CONFIG_DIR="$DOPPLER_CFG_DIR" DOPPLER_ENABLE_VERSION_CHECK=false doppler "$@"
}

names_rc=0
names="$(doppler_ro secrets --only-names --project "$MARKER_PROJECT" --config "$MARKER_CONFIG" 2>/dev/null)" || names_rc=$?
if [[ "$names_rc" -ne 0 ]]; then src_fail "names_rc_${names_rc}"; fi # seam:names-fail

present=0
while IFS= read -r line; do
  line="${line//│/}"
  line="${line//|/}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ "$line" == "$MARKER_NAME" ]]; then present=1; fi # seam:exact-name
done <<<"$names"

if [[ "$present" -eq 1 ]]; then
  get_rc=0
  value="$(doppler_ro secrets get "$MARKER_NAME" --plain --project "$MARKER_PROJECT" --config "$MARKER_CONFIG" 2>/dev/null)" || get_rc=$?
  # A failure here is NEVER "absent": the name was present a moment ago (TOCTOU), so the gate must not run.
  if [[ "$get_rc" -ne 0 ]]; then src_fail "get_rc_${get_rc}"; fi # seam:get-fail
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ -z "$value" || ! "$value" =~ $ISO_RE ]]; then # seam:shape
    echo "marker_source_fail class=malformed_value marker=${MARKER_NAME} gate_not_run=true" >&2
    exit 4
  fi
  export WORKSPACES_LUKS_CUTOVER_AT="$value"
fi

# The gate never calls Doppler: it gets an environment built from scratch (`env -i`), holding the pinned
# PATH and the allowlisted gate inputs that are SET here — nothing else. This closes what an `unset` loop
# over `compgen -e` cannot: exported names that are not shell identifiers (DOPPLER-API-HOST) and exported
# functions (BASH_FUNC_date%%).
unset doppler_token
gate_env=(PATH="$PINNED_PATH")
for v in "${GATE_ENV_ALLOW[@]}"; do
  if [[ -n "${!v+x}" ]]; then gate_env+=("$v=${!v}"); fi
done
# exec replaces this shell, so the EXIT trap would not run: remove the private config dir first.
rm -rf "$DOPPLER_CFG_DIR"
trap - EXIT

exec env -i "${gate_env[@]}" bash "$GATE" # seam:exec
exit 97
