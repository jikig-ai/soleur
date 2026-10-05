#!/usr/bin/env bash
# Never-pooled evidence for the single-use web-2 volume rebirth (#9372): web-2 has not been certified for traffic or
# data, so the soak marker WORKSPACES_LUKS_CUTOVER_AT does not exist in its dedicated Doppler config.
#
# READ-ONLY, NAMES ONLY. It lists the config's secret NAMES (never a value) and tests EXACT-name membership, the
# discipline lb-weight-gate-with-marker.sh uses: a prefix-colliding name does not count, and a failed list is NOT
# "absent" (exit 3: "I could not read it" is not evidence). It never calls a Doppler write verb; the census in
# workspaces-luks-verify-workflow.test.sh holds this file to that (it is an allow-listed READER).
#
# CAVEAT, stated plainly: the only token that reaches the marker config today (DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER)
# is READ/WRITE. A read-only token is a prerequisite recorded on #9358; until it exists this script is the only user of
# that token in the rebirth workflow, bound to one step, and it is constrained by the census, not by the token.
#
# Exit: 0 absent (never pooled), 1 present (web-2 was certified: REFUSE), 3 the config could not be read.
set -euo pipefail
case "$-" in
  *x*) if [ -n "${DOPPLER_TOKEN:+x}" ]; then printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2; exit 78; fi ;;
esac

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/web2-luks-rows.sh
source "${_dir}/lib/web2-luks-rows.sh" || { echo "web2-rebirth-never-pooled: the shared rows helper could not be loaded"; exit 3; }

if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  echo "web2-rebirth-never-pooled: DOPPLER_TOKEN (the marker config's token) is not set; the marker config was NOT read."
  exit 3
fi

cfg="$(mktemp -d)" || exit 3
trap 'rm -rf "$cfg"' EXIT
export DOPPLER_CONFIG_DIR="$cfg"   # a planted ~/.doppler cannot steer the call (api host, token, scope)

if ! names="$(doppler secrets --only-names --json -p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG" 2>/dev/null)"; then
  echo "web2-rebirth-never-pooled: could not list the secret names of ${W2L_MARKER_PROJECT}/${W2L_MARKER_CONFIG}. A failed read is not 'absent'."
  exit 3
fi
# STRICT SHAPE: an absence answer is only as good as the shape it was read from. Accept exactly (a) an array of secret NAMES, or
# (b) an object KEYED by secret name, where every name matches ^[A-Z][A-Z0-9_]*$ (Doppler secret names). Anything else
# (a wrapper object such as {"names":[...]}, an array of objects, a lowercase key) is a shape this script cannot read an
# absence from, so it is exit 3, never "absent". An EMPTY array or object is legitimate (the config holds only the marker).
if ! jq -e '(type == "array" and all(.[]; type == "string" and test("^[A-Z][A-Z0-9_]*$")))
          or (type == "object" and all(keys[]; test("^[A-Z][A-Z0-9_]*$")))' >/dev/null 2>&1 <<<"$names"; then
  echo "web2-rebirth-never-pooled: the name list is not an array of secret names or an object keyed by secret name. A shape this script cannot read an absence from is not 'absent'."
  exit 3
fi
if jq -e --arg n "$W2L_MARKER_NAME" '(if type == "array" then . else keys end) | any(. == $n)' >/dev/null 2>&1 <<<"$names"; then
  echo "web2-rebirth-never-pooled: REFUSED — the soak marker exists in ${W2L_MARKER_PROJECT}/${W2L_MARKER_CONFIG}: web-2 was certified, so its volume may carry data. This operation is only for a never-pooled host."
  exit 1
fi
echo "web2-rebirth-never-pooled: the soak marker is absent from ${W2L_MARKER_PROJECT}/${W2L_MARKER_CONFIG} (exact-name membership over the secret NAMES; no value was read)."
