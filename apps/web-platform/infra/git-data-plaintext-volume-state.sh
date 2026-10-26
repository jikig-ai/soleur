#!/usr/bin/env bash
# Read-only state probe for the retired plaintext git-data volume (id 106867358, name
# soleur-git-data-store). Used three ways, from ONE implementation so the copies cannot drift:
#   - the destroy workflow's pre-plan read (decides the already-gone short-circuit and refuses
#     unexpected Hetzner shapes before any plan exists),
#   - the destroy workflow's post-apply read-back (404 by id, empty list by name, LUKS volume still
#     present on the git-data server),
#   - the plan's `## Observability` discoverability command, also documented in the runbook section
#     "Plaintext-volume destroy (Option B...)", run locally with a read-only token.
#
# It only issues GETs. It prints key=value lines (counts and identifiers only — never a response
# body) and the FIRST line is always the summary: `plaintext_volume=present`, `plaintext_volume=absent`
# or `plaintext_volume=unknown` (no credential, API/parse error, failed presence proof). `shape=` names
# the full state so a refusal can say which:
#   present_attached   volume exists on the git-data server (both the attachment and the volume remain)
#   present_detached   volume exists, attached to no server (attachment already gone: re-dispatch)
#   gone               volume 404 and the name list is empty (the end event)
#   name_other_id      volume 404 but soleur-git-data-store exists under ANOTHER id (refuse)
#   attached_elsewhere volume exists but is attached to a server other than the git-data server (refuse)
#   identity_mismatch  volume 106867358 exists but is not named soleur-git-data-store (refuse)
#
# ONLY the volume id and name are hard pins (they name the object that is destroyed). The git-data
# server and its LUKS volume are resolved LIVE BY NAME, never by a hard-coded id: a host rotate re-mints
# both, and a stale pin would fail the destroy closed at exit 5 after the rotate (CTO ruling 2026-10-26).
# `server_id=`, `luks_volume_id=` and `luks_server_id=` are printed so the caller can bind the plan to
# the live server.
#
# Exit: 0 determined; 3 no credential; 4 API, transport or response-parse error; 5 presence proof failed
# (the token cannot see exactly one server named soleur-git-data holding exactly one volume named
# soleur-git-data-luks-store, so no 404 it returns can mean "gone").
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PINNED_VOLUME_ID=106867358
VOLUME_NAME=soleur-git-data-store
SERVER_NAME=soleur-git-data
LUKS_NAME=soleur-git-data-luks-store
RETRY_SLEEP_S="${HAPI_RETRY_SLEEP_S:-2}"

# The read-only token is preferred; the write token is the fallback only because the destroy workflow's
# infra-credentials loader exports HCLOUD_TOKEN alone. This script never issues a non-GET.
HCLOUD_TOKEN="${HCLOUD_TOKEN_READONLY:-${HCLOUD_TOKEN:-}}"
if [[ -z "$HCLOUD_TOKEN" ]] && command -v doppler >/dev/null 2>&1; then
  HCLOUD_TOKEN="$(doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain 2>/dev/null || true)"
fi
if [[ -z "$HCLOUD_TOKEN" ]]; then
  echo "plaintext_volume=unknown"
  echo "error=no_credential (set HCLOUD_TOKEN_READONLY or HCLOUD_TOKEN, or have Doppler prd_terraform readable)"
  exit 3
fi

HBODY="$(mktemp)"
trap 'rm -f "$HBODY"' EXIT

# hapi <path> -> prints the HTTP status ("000" on a transport error); body -> $HBODY. -w, never -f
# (a 404 is an ANSWER), and the token rides stdin (--config -). 429/5xx are retried; a persistent one
# is returned to the caller, which treats it as an API error — never as "absent".
hapi() {
  local code rc attempt
  for attempt in 1 2 3; do
    rc=0
    code="$(printf 'header = "Authorization: Bearer %s"\n' "$HCLOUD_TOKEN" \
      | curl --disable --noproxy '*' -sS --max-time 15 --config - -X GET -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$1")" || rc=$?
    [[ "$rc" -eq 0 ]] || code="000"
    case "$code" in
      429|5??|000) [[ "$attempt" -lt 3 ]] && sleep "$RETRY_SLEEP_S" ;;
      *) break ;;
    esac
  done
  printf '%s' "$code"
}
api_fail() { echo "plaintext_volume=unknown"; echo "error=api $1 -> $2"; exit 4; }
presence_fail() { echo "plaintext_volume=unknown"; echo "error=presence_proof $1"; exit 5; }
# jq over a response body; a parse failure is an API error (exit 4), never the collision with exit 5 that a
# bare jq failure under `set -e` would produce. It always runs inside $(...), where stdout is captured, so the
# reason goes to stderr and the exit status (4) is what propagates through the assignment.
jqb() { jq "$@" "$HBODY" 2>/dev/null || { echo "error=api parse -> response body is not the expected JSON" >&2; exit 4; }; }

# (a) presence proof FIRST: a token that cannot see exactly one git-data server holding the LUKS volume is
# a token for another project, and its 404s mean nothing.
code="$(hapi "/servers?name=${SERVER_NAME}")"
[[ "$code" == 200 ]] || presence_fail "server lookup -> ${code}"
n_servers="$(jqb -r '.servers | length')"
[[ "$n_servers" == 1 ]] || presence_fail "server_$([[ "$n_servers" == 0 ]] && echo missing || echo ambiguous) (${n_servers} servers named ${SERVER_NAME})"
SERVER_ID="$(jqb -r '.servers[0].id | tostring')"
[[ "$SERVER_ID" =~ ^[0-9]+$ ]] || presence_fail "server id is not numeric"
server_volumes="$(jqb -c '.servers[0].volumes')"

code="$(hapi "/volumes?name=${LUKS_NAME}")"
[[ "$code" == 200 ]] || presence_fail "luks lookup -> ${code}"
n_luks="$(jqb -r '.volumes | length')"
[[ "$n_luks" == 1 ]] || presence_fail "luks_volume_$([[ "$n_luks" == 0 ]] && echo missing || echo ambiguous) (${n_luks} volumes named ${LUKS_NAME})"
LUKS_VOLUME_ID="$(jqb -r '.volumes[0].id | tostring')"
luks_server="$(jqb -r '.volumes[0].server // "null" | tostring')"
[[ "$LUKS_VOLUME_ID" =~ ^[0-9]+$ ]] || presence_fail "luks volume id is not numeric"
[[ "$luks_server" == "$SERVER_ID" ]] || presence_fail "luks_volume_missing (the LUKS volume is attached to server ${luks_server}, not the git-data server ${SERVER_ID})"
printf '%s' "$server_volumes" | jq -e --argjson l "$LUKS_VOLUME_ID" 'index($l) != null' >/dev/null 2>&1 \
  || presence_fail "luks_volume_missing (server ${SERVER_ID} does not list LUKS volume ${LUKS_VOLUME_ID})"

# (b) the pinned volume
code="$(hapi "/volumes/${PINNED_VOLUME_ID}")"
vol_present=0; vol_name=""; vol_server="null"; vol_created="none"; vol_protected="none"
case "$code" in
  200)
    vol_present=1
    vol_name="$(jqb -r '.volume.name // ""')"
    vol_server="$(jqb -r '.volume.server // "null" | tostring')"
    vol_created="$(jqb -r '.volume.created // "unknown"')"
    vol_protected="$(jqb -r '.volume.protection.delete | if . == null then "unknown" else tostring end')"
    ;;
  404) : ;;
  *) api_fail "GET /volumes/${PINNED_VOLUME_ID}" "$code" ;;
esac

# (c) the name lookup
code="$(hapi "/volumes?name=${VOLUME_NAME}")"
[[ "$code" == 200 ]] || api_fail "GET /volumes?name=${VOLUME_NAME}" "$code"
name_ids="$(jqb -c '[.volumes[].id]')"
name_count="$(jqb -r '.volumes | length')"

if [[ "$vol_present" -eq 1 ]]; then
  summary="present"
  if [[ "$vol_name" != "$VOLUME_NAME" ]]; then shape="identity_mismatch"
  elif [[ "$vol_server" == "null" ]]; then shape="present_detached"
  elif [[ "$vol_server" == "$SERVER_ID" ]]; then shape="present_attached"
  else shape="attached_elsewhere"; fi
else
  summary="absent"
  if [[ "$name_count" -eq 0 ]]; then shape="gone"; else shape="name_other_id"; fi
fi

echo "plaintext_volume=${summary}"
echo "shape=${shape}"
echo "volume_id=${PINNED_VOLUME_ID}"
echo "volume_server_id=${vol_server}"
echo "volume_created=${vol_created}"
echo "volume_delete_protected=${vol_protected}"
echo "name_lookup_ids=${name_ids}"
echo "server_id=${SERVER_ID}"
echo "luks_volume=present"
echo "luks_volume_id=${LUKS_VOLUME_ID}"
echo "luks_server_id=${luks_server}"
echo "server_volumes=${server_volumes}"
