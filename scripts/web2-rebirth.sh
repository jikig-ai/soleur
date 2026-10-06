#!/usr/bin/env bash
# The stateful steps of the single-use web-2 volume REBIRTH (#9372, ADR-263 addendum), as testable subcommands.
# Called by .github/workflows/web2-luks-rebirth.yml; every destructive call here is pinned to a CONSTANT physical id
# and re-asserted at the call, so a re-dispatch after any crash heals or refuses before it writes.
#
#   classify          presence proof (web-1 must hold the live LUKS volume: a token from another project answers 404 for a live
#                     volume, so no 404 below means "gone" until this passed), observe Hetzner + Terraform state, run
#                     web2_rebirth_classify, set outputs verdict/web2_sid/pin_desc
#   delete-volume     detach (only if attached), DELETE the pinned plaintext volume, prove 404 + empty name lookup
#   state-rm          forget the volume and its attachment from state: ids equal the pin, serial +1, lineage unchanged
#   ready-poll        wait for a SOLEUR_FRESH_BOOT_READY row newer than web-2's Hetzner creation time:
#                     luks=1 luks_arm=formatted escrow=ok (read-only; scripts/web2-rebirth-ready-poll.sh)
#   reboot            re-resolve web-2 BY NAME, refuse web-1's id, require the post-apply state id, POST reboot
#   flip-precondition the rotation HALT counts a create of the web-class passphrase and apply-web-escrow-create.yml stays retired
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
  : > "$HBODY"   # a transport error must not leave the PREVIOUS call's body to be read as this one's
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$HCLOUD_TOKEN" \
    | curl --disable --noproxy '*' -sS --max-time 15 --config - -X "$1" "${extra[@]}" -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$2")" || rc=$?
  [[ "$rc" -eq 0 ]] || code="000"
  printf '%s' "$code"
}
# errcode — the API's .error.code only (never the body), at most 64 bytes. Byte-identical (modulo whitespace) to the forget
# workflow's copy; the workflow suite pins that.
errcode() {
  local v
  v="$(jq -r '.error.code // empty' "$HBODY" 2>/dev/null | head -c 64 || true)"
  printf '%s' "${v:-none}"
}
fail() {
  local m="$*"
  m="${m//%/%25}"; m="${m//$'\r'/%0D}"; m="${m//$'\n'/%0A}"
  echo "::error::$m"
  exit 1
}
need_token() { [[ -n "${HCLOUD_TOKEN:-}" ]] || fail "the infra-credentials loader exported no HCLOUD_TOKEN"; printf '::add-mask::%s\n' "$HCLOUD_TOKEN" >&2; }
# (the mask goes to STDERR: a workflow step that captures this script's stdout to a file must never capture a masked value; the runner reads commands from both streams)
# One line per output: a value with a newline (a Hetzner name, an API field) must not be able to start a second `key=value` line.
out() { local v="${2//$'\r'/ }"; v="${v//$'\n'/ }"; [[ -z "${GITHUB_OUTPUT:-}" ]] || printf '%s=%s\n' "$1" "$v" >> "$GITHUB_OUTPUT"; }
# clean — a value printed into the run log or the step-summary table: no newline (so no value can start a line of its own, and every table row starts
# with `|`, which a workflow command cannot), no table pipe, bounded.
clean() { local v="$*"; v="${v//$'\r'/ }"; v="${v//$'\n'/ }"; v="${v//|//}"; printf '%s' "${v:0:300}"; }
# Every subcommand that WRITES refuses unless the dispatch is an apply run: plan_only can never reach a write through this file,
# whatever the workflow's step conditions say.
require_apply() { [[ "${APPLY:-}" == yes ]] || fail "$1 refused: this is not an apply dispatch (APPLY='${APPLY:-}'); plan_only never writes"; }
# The loader's legacy arm exports a READ-ONLY Hetzner token first; a write verb answered 403 almost always means that.
write_hint() { [[ "$1" == 403 ]] && printf ' (403: the loader exported a read-only Hetzner token; the write verbs need the Tier-B write token)' || true; }

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
  local code created created_epoch
  WEB2_AGE_S=none; PIN_DESC=unknown
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  case "$code" in
    200)
      PIN_STATUS=present
      PIN_FORMAT="$(jq -r 'if .volume.format == "ext4" then "ext4" elif .volume.format == null then "none" else "other" end' "$HBODY")"
      PIN_NAME_OK=no
      jq -e --arg n "$PINNED_VOLUME_NAME" --arg a "$VOLUME_LABEL_APP" '.volume.name == $n and .volume.labels == {app: $a}' "$HBODY" >/dev/null && PIN_NAME_OK=yes
      PIN_SERVER="$(jq -r '.volume.server // "none"' "$HBODY")"
      PIN_DESC="$(jq -r '"id=\(.volume.id) name=\(.volume.name) size_gb=\(.volume.size) format=\(.volume.format // "none") labels=\(.volume.labels | tojson) attached_to=\(.volume.server // "none")"' "$HBODY")" ;;
    404) PIN_DESC=absent; PIN_STATUS=absent; PIN_FORMAT=none; PIN_NAME_OK=no; PIN_SERVER=none ;;
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
       WEB2_VOLS="$(jq -r '[.servers[0].volumes[] | tostring] | join(",")' "$HBODY")"; [[ -n "$WEB2_VOLS" ]] || WEB2_VOLS=none
       created="$(jq -r '.servers[0].created // empty' "$HBODY")"
       # An absent creation time must stay UNKNOWN: `date -d ""` is midnight today, which would read as an age of hours and offer a resume.
       if [[ -n "$created" ]] && created_epoch="$(date -u -d "$created" +%s 2>/dev/null)" && [[ "$created_epoch" =~ ^[0-9]+$ ]]; then
         WEB2_AGE_S="$(( $(date -u +%s) - created_epoch ))"; (( WEB2_AGE_S >= 0 )) || WEB2_AGE_S=none
       fi ;;
    *) fail "more than one server is named ${WEB2_NAME}: ambiguous; nothing is written" ;;
  esac
  [[ "$WEB2_SID" != "$WEB1_SERVER_ID" ]] || fail "the server named ${WEB2_NAME} has web-1's id: refusing"
}

cmd_classify() { # apply=yes|no
  need_token; presence_proof
  local apply="${1:-no}" pause=no ident state_vol state_server verdict
  [[ "$apply" == yes ]] && { pause_real && pause=yes || pause=no; }
  observe_hetzner
  ident="$(state_ident)" || fail "could not read the Terraform state"
  state_vol="$(jq -r '.vol' <<<"$ident")"; state_server="absent"; [[ "$(jq -r '.server' <<<"$ident")" != none ]] && state_server=present
  [[ "$(jq -r '.web1' <<<"$ident")" == 1 ]] || fail "hcloud_server.web[\"web-1\"] is not in this state: wrong state object; nothing is written"
  verdict="$(web2_rebirth_classify apply="$apply" pause="$pause" pin="$PINNED_VOLUME_ID" pin_status="$PIN_STATUS" pin_format="$PIN_FORMAT" \
    pin_name_ok="$PIN_NAME_OK" pin_server="$PIN_SERVER" names="$NAMES" web2_sid="$WEB2_SID" web2_vols="$WEB2_VOLS" state_vol="$state_vol" state_server="$state_server" web2_age_s="$WEB2_AGE_S")"
  echo "classifier: pin=${PIN_STATUS}/${PIN_FORMAT} attached_to=${PIN_SERVER} named_ids=${NAMES} web2_sid=${WEB2_SID} web2_vols=${WEB2_VOLS} state_vol=${state_vol} state_server=${state_server} pause=${pause} web2_age_s=${WEB2_AGE_S}"
  echo "pinned volume: $(clean "$PIN_DESC")"
  out verdict "$verdict"; out web2_sid "$WEB2_SID"; out pin_desc "$PIN_DESC"
  echo "verdict: ${verdict}"
  case "$verdict" in refuse:*) fail "the rebirth REFUSES before any write: ${verdict}" ;; esac
}

# stage_allowed <verdict> <allowed...> — a stage runs only in the windows it belongs to; later windows skip it (idempotent).
stage_allowed() { local v="$1" a; shift; for a in "$@"; do [[ "$v" == "$a" ]] && return 0; done; return 1; }

cmd_delete_volume() {
  need_token
  require_apply delete-volume
  local v="${VERDICT:?VERDICT is required}" code action_id st
  if ! stage_allowed "$v" proceed heal:detach_done; then
    case "$v" in heal:delete_done|heal:state_rm_done|heal:apply_midway|heal:volume_created|resume:post_apply) echo "delete-volume: skipped (${v}: the volume is already gone)"; return 0 ;; esac
    fail "delete-volume: refused in state '${v}'"
  fi
  # THE CHOKEPOINT for the irreversible step: a skipped or failed evidence step leaves its output EMPTY, and an empty proof
  # refuses here whatever the workflow's step conditions did. (The workflow passes each step's own output.)
  case "${EMPTINESS:-}" in PASS*) : ;; *) fail "delete-volume refused: no PASS emptiness verdict from the evidence step (got '${EMPTINESS:-}'); nothing is deleted" ;; esac
  [[ "${NEVER_POOLED:-}" == absent ]] || fail "delete-volume refused: no never-pooled proof (got '${NEVER_POOLED:-}'); nothing is deleted"
  [[ "${PRE_PLAN:-}" == graded ]] || fail "delete-volume refused: the pre plan was not graded (got '${PRE_PLAN:-}'); nothing is deleted"
  [[ "${FLIP:-}" == met ]] || fail "delete-volume refused: the flip precondition was not reported MET by its step (got '${FLIP:-}'); nothing is deleted"
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
    [[ "$code" == 201 ]] || fail "detach -> ${code} (error.code=$(errcode))$(write_hint "$code")"
    action_id="$(jq -r '.action.id | tostring' "$HBODY")"
    [[ "$action_id" =~ ^[0-9]+$ ]] || fail "detach returned no action id"
    for _ in $(seq 1 24); do
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
  case "$code" in 204|404) : ;; *) fail "DELETE /volumes/${PINNED_VOLUME_ID} -> ${code} (error.code=$(errcode))$(write_hint "$code")" ;; esac
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 404 ]] || fail "volume ${PINNED_VOLUME_ID} still answers ${code} after the delete"
  code="$(hapi GET "/volumes?name=${PINNED_VOLUME_NAME}")"
  [[ "$code" == 200 && "$(jq -r '.volumes | length' "$HBODY")" == 0 ]] || fail "a volume named ${PINNED_VOLUME_NAME} still exists after the delete"
  echo "deleted: volume ${PINNED_VOLUME_ID} (${PINNED_VOLUME_NAME}) is gone (404, empty name lookup)"
  out volume_deleted "${PINNED_VOLUME_ID} (404 and an empty name lookup proven)"
}

cmd_state_rm() {
  need_token
  require_apply state-rm
  local v="${VERDICT:?VERDICT is required}" pre pre_list pre_serial pre_lineage vol att post post_list want_list code
  local -a addrs=()
  if ! stage_allowed "$v" proceed heal:detach_done heal:delete_done; then
    case "$v" in heal:state_rm_done|heal:apply_midway|heal:volume_created|resume:post_apply) echo "state-rm: skipped (${v}: state is already clean)"; return 0 ;; esac
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
  out state_forgotten "${addrs[*]} (serial ${pre_serial} -> $((pre_serial + 1)), lineage unchanged)"
}

# The readiness poll reads Better Stack through the shared rows helper, which the soak-marker census holds to READ-ONLY
# (no write verb in the file). This file carries Hetzner write verbs, so the poll lives in its own allow-listed reader.
# The anchor is web-2's own Hetzner creation time, so the readiness row must be newer than THIS server (it also makes a resume
# dispatch correct: the row emitted at birth is newer than the server, whichever run is polling for it).
cmd_ready_poll() {
  need_token
  local code created created_epoch
  code="$(hapi GET "/servers?name=${WEB2_NAME}")"
  [[ "$code" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 ]] || fail "ready-poll: could not resolve exactly one server named ${WEB2_NAME} (${code})"
  created="$(jq -r '.servers[0].created // empty' "$HBODY")"
  # An empty creation time must refuse: `date -d ""` is midnight today and would anchor the poll hours in the past.
  [[ -n "$created" ]] && created_epoch="$(date -u -d "$created" +%s 2>/dev/null)" && [[ "$created_epoch" =~ ^[0-9]+$ ]] || fail "ready-poll: the server's creation time is unreadable ('${created}')"
  exec bash "${_ROOT}/scripts/web2-rebirth-ready-poll.sh" "$created_epoch"
}

cmd_reboot() {
  need_token
  require_apply reboot
  # A reboot is only for a host that was never certified: with the soak marker present web-2 may already hold data, and a resume must not touch it.
  [[ "${NEVER_POOLED:-}" == absent ]] || fail "reboot refused: no never-pooled proof (got '${NEVER_POOLED:-}'); nothing is rebooted"
  local sid state_sid code action_id st ident
  code="$(hapi GET "/servers?name=${WEB2_NAME}")"
  [[ "$code" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 ]] || fail "reboot: could not resolve exactly one server named ${WEB2_NAME} (${code})"
  sid="$(jq -r '.servers[0].id | tostring' "$HBODY")"
  [[ "$sid" =~ ^[0-9]+$ ]] || fail "reboot: the resolved id is not numeric"
  [[ "$sid" != "$WEB1_SERVER_ID" ]] || fail "reboot: the server named ${WEB2_NAME} has web-1's id ${WEB1_SERVER_ID}; refusing to reboot the live origin"
  ident="$(state_ident)"; state_sid="$(jq -r '.server' <<<"$ident")"
  [[ "$state_sid" == "$sid" ]] || fail "reboot: the resolved id ${sid} differs from the id in the post-apply state (${state_sid})"
  code="$(hapi POST "/servers/${sid}/actions/reboot" '{}')"
  [[ "$code" == 201 ]] || fail "reboot -> ${code} (error.code=$(errcode))$(write_hint "$code")"
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
  local apply="${1:-no}" fx="${_ROOT}/tests/scripts/fixtures/web-host-rebirth/passphrase-create-password-only.json" jqf="${_ROOT}/tests/scripts/lib/destroy-guard-filter-web-platform.jq" n absent=yes ok=yes
  n="$(jq -f "$jqf" < "$fx" 2>/dev/null | jq -r '.luks_passphrase_rotations' 2>/dev/null)" || n=""
  [[ "$n" =~ ^[0-9]+$ ]] || fail "flip precondition: the destroy-guard filter could not be evaluated over the fixture"
  [[ "$n" -eq 1 ]] || ok=no
  [[ ! -e "${_ROOT}/.github/workflows/apply-web-escrow-create.yml" ]] || absent=no
  echo "flip precondition: luks_passphrase_rotations over a create of the web-class passphrase = ${n} (needs 1: the passphrase create; widening the arm to the key copy is caught by the destroy-guard suite, not here); apply-web-escrow-create.yml absent = ${absent}"
  if [[ "$ok" == yes && "$absent" == yes ]]; then echo "flip precondition: MET"; out met met; return 0; fi
  if [[ "$apply" == yes ]]; then
    fail "flip precondition NOT met: the escrow-create workflow file is present again, or the rotation HALT no longer counts a create of the web-class passphrase (the closing change for #9372 retired the one and flipped the other, so this is a regression to revert, not a step to perform); this dispatch will not format web-2"
  fi
  echo "flip precondition: PENDING (a plan_only run reports it; an apply run refuses)"
}

cmd_summary() {
  # The dispatch summary: names, ids, booleans and measured values only (no secret value). It claims only what THIS run measured:
  # MODE, JOB_STATUS and the verdict decide which sentence is true. EVERY value is passed through clean(): `reason` is free text from the
  # dispatcher and the API fields come from outside, so none may start a workflow command or break the table. Printed to the run log as
  # well as the step summary (the step summary has no API; the log does).
  local approvers="unavailable (not queried)" new_host="n/a" status="${JOB_STATUS:-unknown}" now_utc started="${STARTED_AT:-n/a}" created_epoch="" earliest resumed=no
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "${VERDICT:-}" == resume:post_apply ]] && resumed=yes
  if [[ -n "${GH_TOKEN:-}" && -n "${RUN_ID:-}" && -n "${REPO:-}" ]]; then
    if approvers="$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/approvals" --jq '[.[] | "\(.user.login) (\(.state))"] | join(", ")' 2>/dev/null)"; then
      [[ -n "$approvers" ]] || approvers="none recorded"
    else
      approvers="unavailable (the approvals API did not answer)"
    fi
  fi
  if [[ "${MODE:-}" == apply && "$status" == success && -n "${HCLOUD_TOKEN:-}" ]]; then
    if [[ "$(hapi GET "/servers?name=${WEB2_NAME}")" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 ]]; then
      new_host="$(jq -r '.servers[0] | "server_id=\(.id) location=\(.datacenter.location.name // "unknown") volumes=\([.volumes[] | tostring] | join(",")) created=\(.created // "unknown")"' "$HBODY")"
      # An absent creation time must stay unknown: `date -d ""` is midnight today.
      created="$(jq -r '.servers[0].created // empty' "$HBODY")"
      if [[ -n "$created" ]]; then created_epoch="$(date -u -d "$created" +%s 2>/dev/null || true)"; fi
    fi
  fi
  # The follow-through's `earliest` is the REBIRTH + 3 days, i.e. the server's own creation time (never "today", which on a resume is wrong).
  if [[ "$created_epoch" =~ ^[0-9]+$ ]]; then earliest="$(date -u -d "@$((created_epoch + 259200))" +%Y-%m-%d)"; else earliest="(read the server's creation time from Hetzner and add 3 days)"; fi
  {
    echo "## web-2 LUKS rebirth (#9372, single-use)"
    echo ""
    echo "| item | value |"
    echo "|---|---|"
    echo "| mode / job status | $(clean "${MODE:-n/a}") / $(clean "$status") |"
    echo "| reason | $(clean "${REASON:-n/a}") |"
    echo "| commit / run | $(clean "${SHA:-n/a}") / $(clean "${RUN_URL:-n/a}") |"
    echo "| dispatcher / approver(s) | $(clean "${ACTOR:-n/a}") / $(clean "$approvers") |"
    echo "| started / summarised (UTC) | $(clean "$started") / ${now_utc} |"
    echo "| target | ${HOST_KEY} only (${WEB2_NAME}); web-1 (${WEB1_SERVER_ID}) is never targeted: by-name refusal in the plan gate, reboot re-resolves web-2 by name |"
    echo "| classifier verdict | $(clean "${VERDICT:-not reached}") |"
    echo "| plaintext volume (pinned) | $(clean "${PIN_DESC:-not reached}") |"
    echo "| emptiness evidence | $(clean "${EMPTINESS:-not run}") |"
    echo "| never pooled (soak marker absent, names only) | $(clean "${NEVER_POOLED:-not run}") |"
    echo "| image | $(clean "${PINNED_IMAGE:-unresolved}") (tag $(clean "${IMAGE_TAG:-n/a}")); host-scripts hash equal to the checkout: $(clean "${COHERENCE:-not run}") |"
    echo "| volume delete | $(clean "${DELETED:-not run}") |"
    echo "| state forget | $(clean "${FORGOT:-not run}") |"
    echo "| readiness row | $(clean "${READY:-not run}") |"
    echo "| recovery check | $(clean "${RECOVERY:-not run}") |"
    echo "| web-2 now | $(clean "${new_host}") |"
    echo ""
    case "${MODE:-}:${status}" in
      plan_only:*) echo "**plan_only: no write of any kind occurred. Nothing has been rebirthed.**" ;;
      apply:success)
        if [[ "$resumed" == yes ]]; then
          echo "**This was a RESUME:** nothing was replaced or deleted. The post plan may only have added what a partly failed apply left missing; then the readiness poll, the recovery check and a reboot ran."
        else
          echo "The rebirth applied and a reboot was **issued**."
        fi
        echo "**Nothing is claimed until the graded reboot proof:** a luks-monitor probe row on a boot_id other than the readiness row's, crypto_LUKS on /dev/mapper/workspaces. Until then web-2 is *provisioned, proof pending*; the soak marker (and so any weight) waits for that proof, and web-2 holds no workspace data."
        echo ""
        echo "Follow-through: a directive for scripts/followthroughs/web2-luks-live-6931.sh is already enrolled on #6931; UPDATE its \`earliest=\` to ${earliest} (rebirth + 3 days). Do not add a second directive." ;;
      *) echo "**The rebirth did not complete (job status $(clean "$status")).** Re-dispatch with the same inputs: the classifier names the window and heals it, resumes the post-apply stages (resume:post_apply), or refuses before writing." ;;
    esac
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

case "${1:-}" in
  classify) shift; cmd_classify "$@" ;;
  delete-volume) cmd_delete_volume ;;
  state-rm) cmd_state_rm ;;
  ready-poll) shift; cmd_ready_poll "$@" ;;
  reboot) cmd_reboot ;;
  flip-precondition) shift; cmd_flip_precondition "$@" ;;
  summary) cmd_summary ;;
  *) echo "usage: web2-rebirth.sh classify <yes|no>|delete-volume|state-rm|ready-poll <epoch>|reboot|flip-precondition <yes|no>|summary" >&2; exit 2 ;;
esac
