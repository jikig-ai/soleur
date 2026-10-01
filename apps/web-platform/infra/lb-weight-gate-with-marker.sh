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
#   6. exec()s the gate with every DOPPLER_* variable removed — the gate never calls Doppler and must
#      not inherit a read/write token.
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

PINNED_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
PATH="$PINNED_PATH"
export PATH
unset BASH_ENV ENV

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

# The child environment of every Doppler call is built explicitly: nothing but the pinned PATH, HOME
# (the CLI's config dir) and the token reaches it, and the config/project come from FLAGS (the CLI is
# last-value-wins on flags and an ambient DOPPLER_CONFIG/DOPPLER_PROJECT must not be able to steer it).
doppler_ro() {
  env -i PATH="$PINNED_PATH" HOME="${HOME:-/nonexistent}" DOPPLER_TOKEN="$doppler_token" \
    DOPPLER_ENABLE_VERSION_CHECK=false doppler "$@"
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

# The gate never calls Doppler: drop every DOPPLER_* variable (token, host, config, project, ...).
unset doppler_token
while IFS= read -r v; do
  case "$v" in DOPPLER_*) unset "$v" ;; esac # seam:unset-doppler
done < <(compgen -e)
unset BASH_ENV ENV

exec bash "$GATE" # seam:exec
exit 97
