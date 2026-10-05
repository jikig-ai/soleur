#!/usr/bin/env bash
# The stateful steps of the single-use web-2 volume REBIRTH (#9372, ADR-263 addendum), as testable subcommands.
# Called by .github/workflows/web2-luks-rebirth.yml; every destructive call here is pinned to a CONSTANT physical id
# and re-asserted at the call, so a re-dispatch after any crash heals or refuses before it writes.
#
#   presence          GET web-1 (it must hold the live LUKS volume): a token from another project answers 404 for a
#                     live volume, so no 404 below means "gone" until this passed
#   classify          observe Hetzner + Terraform state, run web2_rebirth_classify, set outputs verdict/web2_sid
#   delete-volume     detach (only if attached), DELETE the pinned plaintext volume, prove 404 + empty name lookup
#   state-rm          forget the volume and its attachment from state: ids equal the pin, serial +1, lineage unchanged
#   ready-poll        wait for a SOLEUR_FRESH_BOOT_READY row newer than the run anchor: luks=1 luks_arm=formatted escrow=ok
#   reboot            re-resolve web-2 BY NAME, refuse web-1's id, require the post-apply state id, POST reboot
#   flip-precondition the rotation HALT's create exemption is flipped and apply-web-escrow-create.yml is retired
#   summary           the dispatch summary (names, ids and booleans only; no secret value)
#
# Reads Hetzner with `-w`, never `-f` (a 404 is an ANSWER), the token on stdin (`--config -`), never in argv. The state is only
# ever piped straight into ONE field-selecting jq program (it holds passphrases): nothing from it is printed or written.
# The volume is NEVER destroyed by Terraform (prevent_destroy): it is deleted here by API and forgotten from state.
#
# Exit: 0 ok, 1 refused/failed (named ::error::), 78 xtrace refused. Every annotation is %/CR/LF-escaped.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to trace: a Hetzner token and Terraform state are in scope\n' >&2; exit 78 ;;
esac

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/scripts/lib/web2-rebirth-classify.sh
source "${_ROOT}/tests/scripts/lib/web2-rebirth-classify.sh"

# --- constants: the physical-id pins. The workflow's inputs must merely EQUAL these. -----------------------------------
PINNED_VOLUME_ID="106466179"
PINNED_VOLUME_NAME="soleur-web-platform-data-web-2"
HOST_KEY="web-2"
WEB2_NAME="soleur-web-2"
WEB1_SERVER_ID="123931471"
WEB1_SERVER_NAME="soleur-web-platform"
LUKS_VOLUME_ID="106443278"
VOLUME_LABEL_APP="soleur-web-platform"
INFRA_DIR="${INFRA_DIR:-apps/web-platform/infra}"
ACTION_POLL_S="${WEB2_REBIRTH_ACTION_POLL_S:-5}"

HBODY="$(mktemp)"; trap 'rm -f "$HBODY"' EXIT

# hapi <METHOD> <path> [json] -> prints the HTTP status ("000" on a transport error); the body goes to $HBODY.
hapi() {
  local code rc=0
  local -a extra=()
  [[ -n "${3:-}" ]] && extra=(-H 'Content-Type: application/json' --data "$3")
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$HCLOUD_TOKEN" \
    | curl -sS --max-time 15 --config - -X "$1" "${extra[@]}" -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$2")" || rc=$?
  [[ "$rc" -eq 0 ]] || code="000"
  printf '%s' "$code"
}
errcode() { local v; v="$(jq -r '.error.code // empty' "$HBODY" 2>/dev/null | head -c 64 || true)"; printf '%s' "${v:-none}"; }
fail() {
  local m="$*"
  m="${m//%/%25}"; m="${m//$'\r'/%0D}"; m="${m//$'\n'/%0A}"
  echo "::error::$m"
  exit 1
}
need_token() { [[ -n "${HCLOUD_TOKEN:-}" ]] || fail "the infra-credentials loader exported no HCLOUD_TOKEN"; printf '::add-mask::%s\n' "$HCLOUD_TOKEN"; }
out() { [[ -z "${GITHUB_OUTPUT:-}" ]] || printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }

presence_proof() {
  local code
  code="$(hapi GET "/servers/${WEB1_SERVER_ID}")"
  [[ "$code" == 200 ]] || fail "presence proof: GET /servers/${WEB1_SERVER_ID} -> ${code} (error.code=$(errcode)): this token cannot see web-1, so no 404 it returns can mean 'gone'"
  [[ "$(jq -r '.server.name' "$HBODY")" == "$WEB1_SERVER_NAME" ]] || fail "presence proof: server ${WEB1_SERVER_ID} is not named ${WEB1_SERVER_NAME}"
  jq -e --argjson l "$LUKS_VOLUME_ID" '.server.volumes | index($l) != null' "$HBODY" >/dev/null \
    || fail "presence proof: server ${WEB1_SERVER_ID} does not hold the live LUKS volume ${LUKS_VOLUME_ID}"
}

# pause_real — both push-apply workflows disabled_manually and nothing queued or running. Returns 0/1 (never exits): the
# classifier turns a false answer into refuse:push_apply_pause_not_real.
pause_real() {
  local wf st busy
  for wf in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml; do
    st="$(gh api "repos/${REPO:?}/actions/workflows/${wf}" 2>/dev/null | jq -r '.state' 2>/dev/null)" || return 1
    [[ "$st" == disabled_manually ]] || return 1
    busy="$(gh run list --repo "$REPO" --workflow "$wf" --limit 50 --json status 2>/dev/null \
      | jq '[.[] | select(.status == "queued" or .status == "waiting" or .status == "pending" or .status == "requested" or .status == "in_progress")] | length' 2>/dev/null)" || return 1
    [[ "$busy" == 0 ]] || return 1
  done
  return 0
}

# state_ident — the ONLY read of the state: serial, lineage and the web-2 instances selected by EXACT .type and .name.
STATE_JQ='{serial: .serial, lineage: .lineage,
  vol: ([.resources[] | select(.mode == "managed" and .type == "hcloud_volume" and .name == "workspaces") | .instances[] | select(.index_key == "web-2") | (.attributes.id | tostring)] | first // "none"),
  att: ([.resources[] | select(.mode == "managed" and .type == "hcloud_volume_attachment" and .name == "workspaces") | .instances[] | select(.index_key == "web-2") | (.attributes.volume_id | tostring)] | first // "none"),
  server: ([.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == "web-2") | (.attributes.id | tostring)] | first // "none"),
  web1: ([.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == "web-1")] | length)}'
state_ident() { (cd "$INFRA_DIR" && terraform state pull | jq -c "$STATE_JQ"); }

# observe — sets PIN_STATUS PIN_FORMAT PIN_NAME_OK PIN_SERVER NAMES WEB2_SID WEB2_VOLS (Hetzner) from the API.
observe_hetzner() {
  local code
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  case "$code" in
    200)
      PIN_STATUS=present
      PIN_FORMAT="$(jq -r 'if .volume.format == "ext4" then "ext4" elif .volume.format == null then "none" else "other" end' "$HBODY")"
      PIN_NAME_OK=no
      jq -e --arg n "$PINNED_VOLUME_NAME" --arg a "$VOLUME_LABEL_APP" '.volume.name == $n and .volume.labels == {app: $a}' "$HBODY" >/dev/null && PIN_NAME_OK=yes
      PIN_SERVER="$(jq -r '.volume.server // "none"' "$HBODY")" ;;
    404) PIN_STATUS=absent; PIN_FORMAT=none; PIN_NAME_OK=no; PIN_SERVER=none ;;
    *) fail "GET /volumes/${PINNED_VOLUME_ID} -> ${code} (error.code=$(errcode)): neither present nor gone; nothing is written" ;;
  esac
  code="$(hapi GET "/volumes?name=${PINNED_VOLUME_NAME}")"
  [[ "$code" == 200 ]] || fail "name lookup -> ${code} (error.code=$(errcode))"
  NAMES="$(jq -r '[.volumes[].id | tostring] | join(",")' "$HBODY")"; [[ -n "$NAMES" ]] || NAMES=none
  code="$(hapi GET "/servers?name=${WEB2_NAME}")"
  [[ "$code" == 200 ]] || fail "server lookup -> ${code} (error.code=$(errcode))"
  case "$(jq -r '.servers | length' "$HBODY")" in
    0) WEB2_SID=0; WEB2_VOLS=server_absent ;;
    1) WEB2_SID="$(jq -r '.servers[0].id | tostring' "$HBODY")"
       WEB2_VOLS="$(jq -r '[.servers[0].volumes[] | tostring] | join(",")' "$HBODY")"; [[ -n "$WEB2_VOLS" ]] || WEB2_VOLS=none ;;
    *) fail "more than one server is named ${WEB2_NAME}: ambiguous; nothing is written" ;;
  esac
  [[ "$WEB2_SID" != "$WEB1_SERVER_ID" ]] || fail "the server named ${WEB2_NAME} has web-1's id: refusing"
}

cmd_presence() { need_token; presence_proof; echo "presence proven: web-1 (${WEB1_SERVER_ID}) holds the live LUKS volume ${LUKS_VOLUME_ID}"; }

cmd_classify() { # apply=yes|no
  need_token; presence_proof
  local apply="${1:-no}" pause=no ident state_vol state_server verdict
  [[ "$apply" == yes ]] && { pause_real && pause=yes || pause=no; }
  observe_hetzner
  ident="$(state_ident)" || fail "could not read the Terraform state"
  state_vol="$(jq -r '.vol' <<<"$ident")"; state_server="absent"; [[ "$(jq -r '.server' <<<"$ident")" != none ]] && state_server=present
  [[ "$(jq -r '.web1' <<<"$ident")" == 1 ]] || fail "hcloud_server.web[\"web-1\"] is not in this state: wrong state object; nothing is written"
  verdict="$(web2_rebirth_classify apply="$apply" pause="$pause" pin="$PINNED_VOLUME_ID" pin_status="$PIN_STATUS" pin_format="$PIN_FORMAT" \
    pin_name_ok="$PIN_NAME_OK" pin_server="$PIN_SERVER" names="$NAMES" web2_sid="$WEB2_SID" web2_vols="$WEB2_VOLS" state_vol="$state_vol" state_server="$state_server")"
  echo "classifier: pin=${PIN_STATUS}/${PIN_FORMAT} attached_to=${PIN_SERVER} named_ids=${NAMES} web2_sid=${WEB2_SID} web2_vols=${WEB2_VOLS} state_vol=${state_vol} state_server=${state_server} pause=${pause}"
  out verdict "$verdict"; out web2_sid "$WEB2_SID"
  echo "verdict: ${verdict}"
  case "$verdict" in refuse:*) fail "the rebirth REFUSES before any write: ${verdict}" ;; esac
}

# stage_allowed <verdict> <allowed...> — a stage runs only in the windows it belongs to; later windows skip it (idempotent).
stage_allowed() { local v="$1" a; shift; for a in "$@"; do [[ "$v" == "$a" ]] && return 0; done; return 1; }

cmd_delete_volume() {
  need_token
  local v="${VERDICT:?VERDICT is required}" code action_id i st
  if ! stage_allowed "$v" proceed heal:detach_done; then
    case "$v" in heal:delete_done|heal:state_rm_done|heal:apply_midway|heal:volume_created) echo "delete-volume: skipped (${v}: the volume is already gone)"; return 0 ;; esac
    fail "delete-volume: refused in state '${v}'"
  fi
  presence_proof
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 200 ]] || fail "re-assert: GET /volumes/${PINNED_VOLUME_ID} -> ${code}"
  jq -e --arg n "$PINNED_VOLUME_NAME" --arg a "$VOLUME_LABEL_APP" '.volume.format == "ext4" and .volume.name == $n and .volume.labels == {app: $a}' "$HBODY" >/dev/null \
    || fail "re-assert: volume ${PINNED_VOLUME_ID} is not the empty plaintext ext4 volume named ${PINNED_VOLUME_NAME}"
  local attached; attached="$(jq -r '.volume.server // "none"' "$HBODY")"
  if [[ "$attached" != none ]]; then
    code="$(hapi GET "/servers?name=${WEB2_NAME}")"
    [[ "$code" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 && "$(jq -r '.servers[0].id | tostring' "$HBODY")" == "$attached" ]] \
      || fail "re-assert: volume ${PINNED_VOLUME_ID} is attached to ${attached}, which is not the server named ${WEB2_NAME}"
    [[ "$attached" != "$WEB1_SERVER_ID" ]] || fail "re-assert: refusing, the volume is attached to web-1"
    code="$(hapi POST "/volumes/${PINNED_VOLUME_ID}/actions/detach" '{}')"
    [[ "$code" == 201 ]] || fail "detach -> ${code} (error.code=$(errcode))"
    action_id="$(jq -r '.action.id | tostring' "$HBODY")"
    [[ "$action_id" =~ ^[0-9]+$ ]] || fail "detach returned no action id"
    for i in $(seq 1 24); do
      code="$(hapi GET "/actions/${action_id}")"
      [[ "$code" == 200 ]] || fail "action ${action_id} -> ${code}"
      st="$(jq -r '.action.status' "$HBODY")"
      [[ "$st" == success ]] && break
      [[ "$st" == error ]] && fail "detach action ${action_id} failed (error.code=$(jq -r '.action.error.code // "none"' "$HBODY" | head -c 64))"
      sleep "$ACTION_POLL_S"
    done
    [[ "$st" == success ]] || fail "detach action ${action_id} did not finish in time"
  fi
  code="$(hapi DELETE "/volumes/${PINNED_VOLUME_ID}")"
  case "$code" in 204|404) : ;; *) fail "DELETE /volumes/${PINNED_VOLUME_ID} -> ${code} (error.code=$(errcode))" ;; esac
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 404 ]] || fail "volume ${PINNED_VOLUME_ID} still answers ${code} after the delete"
  code="$(hapi GET "/volumes?name=${PINNED_VOLUME_NAME}")"
  [[ "$code" == 200 && "$(jq -r '.volumes | length' "$HBODY")" == 0 ]] || fail "a volume named ${PINNED_VOLUME_NAME} still exists after the delete"
  echo "deleted: volume ${PINNED_VOLUME_ID} (${PINNED_VOLUME_NAME}) is gone (404, empty name lookup)"
}

cmd_state_rm() {
  need_token
  local v="${VERDICT:?VERDICT is required}" pre pre_list pre_serial pre_lineage vol att post post_list want_list code
  local -a addrs=()
  if ! stage_allowed "$v" proceed heal:detach_done heal:delete_done; then
    case "$v" in heal:state_rm_done|heal:apply_midway|heal:volume_created) echo "state-rm: skipped (${v}: state is already clean)"; return 0 ;; esac
    fail "state-rm: refused in state '${v}'"
  fi
  presence_proof
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 404 ]] || fail "state-rm: volume ${PINNED_VOLUME_ID} answers ${code}, not 404: it is not gone, nothing is forgotten"
  pre="$(state_ident)"; pre_list="$(cd "$INFRA_DIR" && terraform state list | LC_ALL=C sort)"
  pre_serial="$(jq -r '.serial' <<<"$pre")"; pre_lineage="$(jq -r '.lineage' <<<"$pre")"
  [[ "$pre_serial" =~ ^[0-9]+$ && -n "$pre_lineage" && "$pre_lineage" != null ]] || fail "could not read serial/lineage from the state"
  vol="$(jq -r '.vol' <<<"$pre")"; att="$(jq -r '.att' <<<"$pre")"
  [[ "$vol" == "$PINNED_VOLUME_ID" ]] || fail "the state's volume id is '${vol}', not the pin ${PINNED_VOLUME_ID}: nothing is forgotten"
  addrs+=("hcloud_volume.workspaces[\"${HOST_KEY}\"]")
  if [[ "$att" != none ]]; then
    [[ "$att" == "$PINNED_VOLUME_ID" ]] || fail "the state's attachment volume_id is '${att}', not the pin ${PINNED_VOLUME_ID}: nothing is forgotten"
    addrs+=("hcloud_volume_attachment.workspaces[\"${HOST_KEY}\"]")
  fi
  local a; for a in "${addrs[@]}"; do grep -qxF "$a" <<<"$pre_list" || fail "${a} is not in terraform state list"; done
  (cd "$INFRA_DIR" && terraform state rm "${addrs[@]}")
  post="$(state_ident)"; post_list="$(cd "$INFRA_DIR" && terraform state list | LC_ALL=C sort)"
  web2_rebirth_state_rm_check "$PINNED_VOLUME_ID" "$vol" "$pre_serial" "$pre_lineage" "$(jq -r '.serial' <<<"$post")" "$(jq -r '.lineage' <<<"$post")" >&2 \
    || fail "state-rm: the removal was not exactly one state write of the pinned address"
  [[ "$(jq -r '.vol' <<<"$post")" == none && "$(jq -r '.att' <<<"$post")" == none ]] || fail "a web-2 volume address survived the removal"
  [[ "$(jq -r '.web1' <<<"$post")" == 1 ]] || fail "hcloud_server.web[\"web-1\"] vanished across the removal"
  want_list="$(grep -vxF -f <(printf '%s\n' "${addrs[@]}") <<<"$pre_list" || true)"
  [[ "$post_list" == "$want_list" ]] || fail "terraform state list changed by more than the removed addresses"
  echo "forgot ${#addrs[@]} address(es): ${addrs[*]} (serial ${pre_serial} -> $((pre_serial + 1)), lineage unchanged)"
}

# The readiness poll reads Better Stack through the shared rows helper, which the soak-marker census holds to READ-ONLY
# (no write verb in the file). This file carries Hetzner write verbs, so the poll lives in its own allow-listed reader.
cmd_ready_poll() { exec bash "${_ROOT}/scripts/web2-rebirth-ready-poll.sh" "$@"; }

cmd_reboot() {
  need_token
  local sid state_sid code action_id i st ident
  code="$(hapi GET "/servers?name=${WEB2_NAME}")"
  [[ "$code" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 ]] || fail "reboot: could not resolve exactly one server named ${WEB2_NAME} (${code})"
  sid="$(jq -r '.servers[0].id | tostring' "$HBODY")"
  [[ "$sid" =~ ^[0-9]+$ ]] || fail "reboot: the resolved id is not numeric"
  [[ "$sid" != "$WEB1_SERVER_ID" ]] || fail "reboot: the server named ${WEB2_NAME} has web-1's id ${WEB1_SERVER_ID}; refusing to reboot the live origin"
  ident="$(state_ident)"; state_sid="$(jq -r '.server' <<<"$ident")"
  [[ "$state_sid" == "$sid" ]] || fail "reboot: the resolved id ${sid} differs from the id in the post-apply state (${state_sid})"
  code="$(hapi POST "/servers/${sid}/actions/reboot" '{}')"
  [[ "$code" == 201 ]] || fail "reboot -> ${code} (error.code=$(errcode))"
  action_id="$(jq -r '.action.id | tostring' "$HBODY")"
  [[ "$action_id" =~ ^[0-9]+$ ]] || fail "reboot returned no action id"
  for _ in $(seq 1 24); do
    code="$(hapi GET "/actions/${action_id}")"; [[ "$code" == 200 ]] || fail "action ${action_id} -> ${code}"
    st="$(jq -r '.action.status' "$HBODY")"
    [[ "$st" == success ]] && { echo "reboot issued: server ${sid} (${WEB2_NAME}), action ${action_id} accepted. The reopen is NOT proven by this step: the next luks-monitor probe row on a new boot_id is the evidence."; return 0; }
    [[ "$st" == error ]] && fail "reboot action ${action_id} failed"
    sleep "$ACTION_POLL_S"
  done
  fail "reboot action ${action_id} did not finish in time"
}

cmd_flip_precondition() { # apply=yes|no
  local apply="${1:-no}" fx="${_ROOT}/tests/scripts/fixtures/web-host-rebirth/passphrase-create.json" jqf="${_ROOT}/tests/scripts/lib/destroy-guard-filter-web-platform.jq" n absent=yes ok=yes
  n="$(jq -f "$jqf" < "$fx" 2>/dev/null | jq -r '.luks_passphrase_rotations' 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]+$ ]] || fail "flip precondition: the destroy-guard filter could not be evaluated over the fixture"
  [[ "$n" -eq 2 ]] || ok=no
  [[ ! -e "${_ROOT}/.github/workflows/apply-web-escrow-create.yml" ]] || absent=no
  echo "flip precondition: luks_passphrase_rotations over a create of the web-class pair = ${n} (needs 2); apply-web-escrow-create.yml absent = ${absent}"
  if [[ "$ok" == yes && "$absent" == yes ]]; then echo "flip precondition: MET"; return 0; fi
  if [[ "$apply" == yes ]]; then
    fail "flip precondition NOT met: the retirement change (delete apply-web-escrow-create.yml and flip the rotation HALT's create exemption) must merge before this dispatch formats web-2"
  fi
  echo "flip precondition: PENDING (a plan_only run reports it; an apply run refuses)"
}

cmd_summary() {
  { echo "## web-2 LUKS rebirth (#9372, single-use)"
    echo ""
    echo "| item | value |"
    echo "|---|---|"
    echo "| target | ${HOST_KEY} only (${WEB2_NAME}); web-1 (${WEB1_SERVER_ID}) untouched and refused by name |"
    echo "| plaintext volume pinned for deletion | ${PINNED_VOLUME_ID} (${PINNED_VOLUME_NAME}) |"
    echo "| classifier verdict | ${VERDICT:-n/a} |"
    echo "| emptiness | ${EMPTINESS:-n/a} |"
    echo "| never pooled | ${NEVER_POOLED:-n/a} |"
    echo "| image | ${PINNED_IMAGE:-unresolved} (tag ${IMAGE_TAG:-n/a}) |"
    echo "| mode | ${MODE:-n/a} |"
    echo "| run | ${RUN_URL:-n/a} (actor ${ACTOR:-n/a}) |"
    echo ""
    echo "Nothing is claimed until the graded reboot proof: a luks-monitor probe row on a boot_id other than the readiness row's, crypto_LUKS on /dev/mapper/workspaces. Until then web-2 is *provisioned, proof pending*, stays at weight 0 and holds no workspace data."
    echo "Follow-through to enrol on #6931 (earliest = rebirth + 3 days): \`<!-- soleur:followthrough script=scripts/followthroughs/web2-luks-live-6931.sh earliest=$(date -u -d '+3 days' +%Y-%m-%d) secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->\`"
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

case "${1:-}" in
  presence) cmd_presence ;;
  classify) shift; cmd_classify "$@" ;;
  delete-volume) cmd_delete_volume ;;
  state-rm) cmd_state_rm ;;
  ready-poll) shift; cmd_ready_poll "$@" ;;
  reboot) cmd_reboot ;;
  flip-precondition) shift; cmd_flip_precondition "$@" ;;
  summary) cmd_summary ;;
  *) echo "usage: web2-rebirth.sh presence|classify <yes|no>|delete-volume|state-rm|ready-poll <epoch>|reboot|flip-precondition <yes|no>|summary" >&2; exit 2 ;;
esac
