#!/usr/bin/env bash
# Read-only state probe for the retired plaintext git-data volume (id 106867358, name
# soleur-git-data-store). Used three ways, from ONE implementation so the copies cannot drift:
#   - the destroy workflow's pre-plan read (decides the already-gone short-circuit and refuses
#     unexpected Hetzner shapes before any plan exists),
#   - the destroy workflow's post-apply read-back (404 by id, empty list by name, LUKS volume still
#     present on the server),
#   - the plan's `## Observability` discoverability command, run locally with a read-only token.
#
# It only issues GETs. It prints key=value lines (counts and identifiers only — never a response
# body) and the FIRST line is always the summary: `plaintext_volume=present` or
# `plaintext_volume=absent`. `shape=` names the full state so a refusal can say which:
#   present_attached   volume exists on server 170370833 (both the attachment and the volume remain)
#   present_detached   volume exists, attached to no server (attachment already gone: re-dispatch)
#   gone               volume 404 and the name list is empty (the end event)
#   name_other_id      volume 404 but soleur-git-data-store exists under ANOTHER id (refuse)
#   attached_elsewhere volume exists but is attached to a server other than 170370833 (refuse)
#   identity_mismatch  volume 106867358 exists but is not named soleur-git-data-store (refuse)
# Exit: 0 determined; 3 no credential; 4 API/transport error; 5 presence proof failed (the token
# cannot see server 170370833 holding the LUKS volume, so no 404 it returns can mean "gone").
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PINNED_VOLUME_ID=106867358
VOLUME_NAME=soleur-git-data-store
SERVER_ID=170370833
SERVER_NAME=soleur-git-data
LUKS_VOLUME_ID=107140231
RETRY_SLEEP_S="${HAPI_RETRY_SLEEP_S:-2}"

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

# (a) presence proof FIRST: a token that cannot see the git-data server holding the LUKS volume is a
# token for another project, and its 404s mean nothing.
code="$(hapi "/servers/${SERVER_ID}")"
[[ "$code" == 200 ]] || { echo "plaintext_volume=unknown"; echo "error=presence_proof server ${SERVER_ID} -> ${code}"; exit 5; }
[[ "$(jq -r '.server.name' "$HBODY")" == "$SERVER_NAME" ]] \
  || { echo "plaintext_volume=unknown"; echo "error=presence_proof server ${SERVER_ID} is not named ${SERVER_NAME}"; exit 5; }
jq -e --argjson l "$LUKS_VOLUME_ID" '.server.volumes | index($l) != null' "$HBODY" >/dev/null \
  || { echo "plaintext_volume=unknown"; echo "error=presence_proof server ${SERVER_ID} does not hold LUKS volume ${LUKS_VOLUME_ID}"; exit 5; }
server_volumes="$(jq -c '.server.volumes' "$HBODY")"

# (b) the pinned volume
code="$(hapi "/volumes/${PINNED_VOLUME_ID}")"
vol_present=0; vol_name=""; vol_server="null"
case "$code" in
  200)
    vol_present=1
    vol_name="$(jq -r '.volume.name // ""' "$HBODY")"
    vol_server="$(jq -r '.volume.server // "null"' "$HBODY")"
    ;;
  404) : ;;
  *) api_fail "GET /volumes/${PINNED_VOLUME_ID}" "$code" ;;
esac

# (c) the name lookup
code="$(hapi "/volumes?name=${VOLUME_NAME}")"
[[ "$code" == 200 ]] || api_fail "GET /volumes?name=${VOLUME_NAME}" "$code"
name_ids="$(jq -c '[.volumes[].id]' "$HBODY")"
name_count="$(jq -r '.volumes | length' "$HBODY")"

# (d) the LUKS volume (must survive the destroy)
code="$(hapi "/volumes/${LUKS_VOLUME_ID}")"
luks_server="null"; luks_present=0
case "$code" in
  200) luks_present=1; luks_server="$(jq -r '.volume.server // "null"' "$HBODY")" ;;
  404) : ;;
  *) api_fail "GET /volumes/${LUKS_VOLUME_ID}" "$code" ;;
esac

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
echo "name_lookup_ids=${name_ids}"
echo "luks_volume=$([[ "$luks_present" -eq 1 ]] && echo present || echo absent)"
echo "luks_server_id=${luks_server}"
echo "server_volumes=${server_volumes}"
