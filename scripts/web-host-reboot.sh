#!/usr/bin/env bash
# The one Hetzner write of the web-host reboot workflow (#9372): a soft (ACPI) reboot request for ONE allow-listed web host
# (web-2 today), as a testable subcommand. Called by .github/workflows/web-host-reboot.yml, job `reboot`, behind the Tier-B
# environment approval. Retires together with scripts/web2-rebirth.sh and scripts/web2-rebirth-never-pooled.sh.
#
#   reboot <host> <confirm>   refusals, in this order (each a named ::error:: and each leaves the world untouched):
#                               1 xtrace, no HCLOUD_TOKEN, or a token of an unusable shape   2 host not on the allow-list
#                               3 confirm is not REBOOT-<host>-<digits>      4 NEVER_POOLED is not `absent`
#                               5 not exactly one server by that name        6 id not numeric, or web-1's id
#                               7 id differs from the one typed in confirm   8 Terraform state does not agree, holds no
#                                                                              numeric id for web-1, or holds the resolved id for it
#                             then the anchor epoch is written to GITHUB_OUTPUT (immediately before the POST, never earlier
#                             and never after), the one POST is sent, and the action is polled:
#                               9 the POST is not HTTP 201 or returns no action id (a definite 4xx withdraws the anchor: an
#                                 empty `anchor_epoch=` is appended, last write wins, because Hetzner refused the request; any
#                                 other answer, or none, keeps it and says the request may have been sent)
#                              10 the action ends in error or has not ended after 24 polls (a poll that is not HTTP 200, or
#                                 whose body is not JSON, is not an answer: it is retried, and the end is still unconfirmed)
#   summary                   the run summary (names, ids and measured values only). It makes no Hetzner call.
#
# The accepted request is a request: Hetzner's `success` for the action means the ACPI request was sent, not that the host
# restarted. The evidence reader (scripts/web-host-reboot-evidence.sh) reports what the rows show. This file never names the
# rows helper: the census in workspaces-luks-verify-workflow.test.sh keeps writers and readers apart.
#
# Reads Hetzner with `-w`, never `-f` (a 404 is an ANSWER), the token on stdin (`--config - < <(printf ...)`, the #9594 form: a
# process substitution, not a pipe, after a token-shape check), never in argv. The state is only
# ever piped straight into ONE field-selecting jq program (it holds passphrases): nothing from it is printed or written.
#
# Exit: 0 ok, 1 refused or failed (named ::error::), 2 usage, 78 xtrace refused. Every annotation is %/CR/LF-escaped.
# The fixed footer is printed on every exit the shell itself controls (an uncatchable kill, and a failed mktemp before the trap is installed, excepted).
set -euo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to trace: a Hetzner token and Terraform state are in scope\n' >&2; printf '%s\n' 'This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78 ;;
esac

# A UTF-8 locale would let `[0-9]` match non-ASCII digits in the confirm regex below: pin the byte locale for this script.
export LC_ALL=C

FOOTER='This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'

HBODY="$(mktemp)"
FOOTER_DONE=""
finish() { rm -f "$HBODY"; [[ -n "$FOOTER_DONE" ]] || printf '%s\n' "$FOOTER"; }
trap finish EXIT

# --- constants. The allow-list is a case arm below; the workflow's `host` options and the suite's expected set must agree. ---
WEB1_SERVER_ID="123931471"
INFRA_DIR="${INFRA_DIR:-apps/web-platform/infra}"
ACTION_POLL_S="${WEB_HOST_REBOOT_ACTION_POLL_S:-5}"
[[ "$ACTION_POLL_S" =~ ^[0-9]{1,3}$ ]] || ACTION_POLL_S=5   # a seam for the suite only: anything but 1-3 digits is the default
GRADE_CMD='bash scripts/web-host-reboot-evidence.sh grade --anchor'

# hapi <METHOD> <path> [json] -> prints the HTTP status ("000" on a transport error); the body goes to $HBODY.
# (`extra=()` is a line-start assignment of its own on purpose: the credentialed-curl lint reads a never-assigned name as environment-settable.)
hapi() {
  local code rc=0
  local -a extra
  extra=()
  [[ -n "${3:-}" ]] && extra=(-H 'Content-Type: application/json' --data "$3")
  : > "$HBODY"   # a transport error must not leave the PREVIOUS call's body to be read as this one's
  code="$(curl --disable --noproxy '*' -sS --max-time 15 --config - -X "$1" "${extra[@]}" -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$2" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$HCLOUD_TOKEN"))" || rc=$?
  [[ "$rc" -eq 0 ]] || code="000"
  printf '%s' "$code"
}
# errcode — the API's .error.code only (never the body), at most 64 bytes.
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
# A token outside the bearer alphabet could carry a second curl-config directive (newline, quote): refused before any curl, by name only.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
need_token() {
  [[ -n "${HCLOUD_TOKEN:-}" ]] || fail "the infra-credentials loader exported no HCLOUD_TOKEN"
  _bearer_ok "$HCLOUD_TOKEN" || fail "the infra-credentials loader exported an HCLOUD_TOKEN of an unusable shape; nothing is rebooted"
  printf '::add-mask::%s\n' "$HCLOUD_TOKEN" >&2
}
# (the mask goes to STDERR: a workflow step that captures this script's stdout to a file must never capture a masked value; the runner reads commands from both streams)
# One line per output: a value with a newline (a Hetzner name, an API field) must not be able to start a second `key=value` line.
out() { local v="${2//$'\r'/ }"; v="${v//$'\n'/ }"; [[ -z "${GITHUB_OUTPUT:-}" ]] || printf '%s=%s\n' "$1" "$v" >> "$GITHUB_OUTPUT"; }
# clean — a value printed into the run log or the step-summary table: no newline (so no value can start a line of its own, and every table row starts
# with `|`, which a workflow command cannot), no table pipe, bounded.
clean() { local v="$*"; v="${v//$'\r'/ }"; v="${v//$'\n'/ }"; v="${v//|//}"; printf '%s' "${v:0:300}"; }
# The loader's legacy arm exports a READ-ONLY Hetzner token first; a write verb answered 403 almost always means that.
# shellcheck disable=SC2015  # the body is byte-identical to scripts/web2-rebirth.sh (parity row), so it is not rewritten
write_hint() { [[ "$1" == 403 ]] && printf ' (403: the loader exported a read-only Hetzner token; the write verbs need the Tier-B write token)' || true; }

# shellcheck disable=SC2016  # $h is a jq variable, bound by --arg in state_ident
# state_ident <host key> — the ONLY read of the state: the web-2 server id selected by EXACT type, name and index, whether web-1 is there,
# and web-1's own id (the live id must never equal it).
STATE_JQ='{server: ([.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == $h) | (.attributes.id | tostring)] | first // "none"),
  web1: ([.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == "web-1")] | length),
  web1id: ([.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == "web-1") | (.attributes.id | tostring)] | first // "none")}'
state_ident() { (cd "$INFRA_DIR" && terraform state pull | jq -c --arg h "$1" "$STATE_JQ"); }

# post_failed <http code> <anchor> — the POST was not HTTP 201. Only a definite 4xx means Hetzner refused the request: the anchor is
# then withdrawn (an empty line wins over the earlier one in GITHUB_OUTPUT), so the observe job does not poll 40 minutes for a reboot
# nobody asked for. Anything else (000, 5xx, a 2xx that is not 201) may have been accepted: the anchor stays and the message says so.
post_failed() {
  local code="$1" anchor="$2" base
  base="reboot -> ${code} (error.code=$(errcode))$(write_hint "$code")"
  if [[ "$code" =~ ^4[0-9][0-9]$ ]]; then
    out anchor_epoch ""
    fail "${base}; Hetzner refused the request, so none was sent and the anchor is withdrawn; fix the cause and re-dispatch"
  fi
  fail "${base}; the request may have been sent: DO NOT re-dispatch; the anchor is ${anchor}; grade with: ${GRADE_CMD} ${anchor} --window-min 0"
}

cmd_reboot() {
  local host="${1:-}" confirm="${2:-}" name sid state_sid state_shown web1_sid code action_id st ident anchor
  need_token
  # 2: the explicit allow-list. A new host is a reviewable edit here, in the workflow's options and in the suite together.
  name=""
  case "$host" in
    web-2) name="soleur-web-2" ;;
    *) fail "reboot: host '$(clean "$host")' is not on the reboot allow-list (web-2 only); nothing is rebooted" ;;
  esac
  # 3: the typed confirm carries the server id, so an approval that lands after a replace cannot be redirected.
  [[ "$confirm" =~ ^REBOOT-${host}-[1-9][0-9]{0,11}$ ]] || fail "reboot: confirm must be REBOOT-${host}-<server id> (digits, no leading zero); nothing is rebooted"
  # 4: with the soak marker present web-2 may already hold data: no reboot without the names-only evidence that it is absent.
  [[ "${NEVER_POOLED:-}" == absent ]] || fail "reboot refused: no never-pooled evidence (got '$(clean "${NEVER_POOLED:-}")'); nothing is rebooted"
  # 5: exactly one server by name, and it must carry the allow-list's name for this host.
  code="$(hapi GET "/servers?name=${name}")"
  [[ "$code" == 200 && "$(jq -r '.servers | length' "$HBODY")" == 1 && "$(jq -r '.servers[0].name' "$HBODY")" == "$name" ]] || fail "reboot: could not resolve exactly one server named ${name} (HTTP ${code}); nothing is rebooted"
  sid="$(jq -r '.servers[0].id | tostring' "$HBODY")"
  # 6: the id is numeric (checked before it is printed anywhere) and is not web-1's.
  [[ "$sid" =~ ^[0-9]+$ ]] || fail "reboot: the resolved id is not numeric; nothing is rebooted"
  [[ "$sid" != "$WEB1_SERVER_ID" ]] || fail "reboot: the server named ${name} has web-1's id ${WEB1_SERVER_ID}; refusing to reboot the live origin"
  # 7: the live id is the id the dispatcher typed.
  [[ "$sid" == "${confirm##*-}" ]] || fail "reboot: the resolved id ${sid} differs from the id typed in confirm; use confirm REBOOT-${host}-${sid} (the live id is ${sid}); nothing is rebooted"
  # 8: the Terraform state is the right object and holds the same id.
  ident="$(state_ident "$host")" || fail "reboot: could not read the Terraform state; nothing is rebooted"
  [[ "$(jq -r '.web1' <<<"$ident")" == 1 ]] || fail "reboot: hcloud_server.web[\"web-1\"] is not in this state: wrong state object; nothing is rebooted"
  state_sid="$(jq -r '.server' <<<"$ident")"
  state_shown="absent or not numeric"; [[ "$state_sid" =~ ^[0-9]+$ ]] && state_shown="$state_sid"
  [[ "$state_sid" =~ ^[0-9]+$ && "$state_sid" == "$sid" ]] || fail "reboot: the resolved id ${sid} differs from the id in the Terraform state (${state_shown}); nothing is rebooted"
  web1_sid="$(jq -r '.web1id' <<<"$ident")"
  [[ "$web1_sid" =~ ^[0-9]+$ ]] || fail "reboot: the Terraform state holds no numeric id for web-1, so the live id cannot be shown to differ from web-1's; nothing is rebooted"
  [[ "$web1_sid" != "$sid" ]] || fail "reboot: the server named ${name} carries the id the Terraform state holds for web-1; refusing to reboot the live origin; nothing is rebooted"
  anchor="$(date -u +%s)"
  out anchor_epoch "$anchor"; out server_id "$sid"
  echo "target: server_id=${sid} name=${name} created=$(clean "$(jq -r '.servers[0].created // "unknown"' "$HBODY")")"
  echo "anchor_epoch=${anchor}"
  code="$(hapi POST "/servers/${sid}/actions/reboot" '{}')"
  [[ "$code" == 201 ]] || post_failed "$code" "$anchor"
  action_id="$(jq -r '.action.id | tostring' "$HBODY" 2>/dev/null)" || action_id=""
  [[ "$action_id" =~ ^[0-9]+$ ]] || fail "reboot -> ${code} returned no numeric action id; the request may have been sent, DO NOT re-dispatch; grade with: ${GRADE_CMD} ${anchor} --window-min 0"
  for _ in $(seq 1 24); do
    code="$(hapi GET "/actions/${action_id}")"
    if [[ "$code" == 200 ]]; then
      st="$(jq -r '.action.status' "$HBODY" 2>/dev/null)" || st=unknown
      if [[ "$st" == success ]]; then
        echo "action: id=${action_id} status=success"
        echo "reboot request accepted by Hetzner (action ${action_id} success). That means the request was sent; it does not show that the host restarted or came back."
        return 0
      fi
      [[ "$st" == error ]] && break
    fi   # a poll that is not HTTP 200 is not an answer: retry, and the end is still unconfirmed
    sleep "$ACTION_POLL_S"
  done
  fail "reboot request outcome unconfirmed: action ${action_id} did not end in success. The request was sent and the reboot may still happen. DO NOT re-dispatch; grade the rows with: ${GRADE_CMD} ${anchor} --window-min 0"
}

cmd_summary() {
  # The run summary: names, ids and measured values only. It claims only what THIS run measured (JOB_STATUS and the anchor decide
  # which sentence is true). EVERY value is passed through clean(): `reason` is free text from the dispatcher and the API fields
  # come from outside, so none may start a workflow command or break the table. Printed to the run log as well as the step summary.
  local approvers="unavailable (not queried)" status="${JOB_STATUS:-unknown}" now_utc reason_shown sq="'" anchor="${ANCHOR_EPOCH:-}" sid="${SERVER_ID:-}"
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$anchor" =~ ^[0-9]{1,10}$ ]] || anchor=""
  [[ "$sid" =~ ^[0-9]{1,12}$ ]] || sid=""
  if [[ -n "${GH_TOKEN:-}" && -n "${RUN_ID:-}" && -n "${REPO:-}" ]]; then
    if approvers="$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/approvals" --jq '[.[] | "\(.user.login) (\(.state))"] | join(", ")' 2>/dev/null)"; then
      [[ -n "$approvers" ]] || approvers="none recorded"
    else
      approvers="unavailable (the approvals API did not answer)"
    fi
  fi
  reason_shown="$(clean "${REASON:-n/a}")"; reason_shown="${reason_shown//\`/$sq}"   # a code span, so the free text is never live markdown
  {
    echo "## web host reboot (#9372)"
    echo ""
    echo "| item | value |"
    echo "|---|---|"
    echo "| job status | $(clean "$status") |"
    echo "| host | $(clean "${HOST:-n/a}") |"
    echo "| server id | $(clean "${sid:-n/a}") |"
    echo "| anchor epoch (the request time) | $(clean "${anchor:-none}") |"
    echo "| reason | \`${reason_shown}\` |"
    echo "| commit / run | $(clean "${SHA:-n/a}") / $(clean "${RUN_URL:-n/a}") |"
    echo "| dispatcher / approver(s) | $(clean "${ACTOR:-n/a}") / $(clean "$approvers") |"
    echo "| started / summarised (UTC) | $(clean "${STARTED_AT:-n/a}") / ${now_utc} |"
    echo ""
    if [[ "$status" == success ]]; then
      echo "The reboot request was accepted by Hetzner. That means the request was sent; it does not show that the host restarted or came back. The evidence job reads the rows that follow."
    elif [[ "$status" == cancelled ]]; then
      echo "**The reboot step was cancelled (job status $(clean "$status")).** It is unknown whether a request was sent: do not re-dispatch until the run log has been read.${anchor:+ Grade the rows with: ${GRADE_CMD} ${anchor} --window-min 0}"
    elif [[ -n "$anchor" ]]; then
      echo "**The reboot step did not complete (job status $(clean "$status")).** The request may have been sent: do not re-dispatch. Grade the rows with: ${GRADE_CMD} ${anchor} --window-min 0"
    else
      echo "**The reboot step did not complete (job status $(clean "$status")), and no anchor was written: no request was sent.** Fix the named refusal and re-dispatch."
    fi
    echo ""
    echo "$FOOTER"
  } | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
  FOOTER_DONE=1
}

case "${1:-}" in
  reboot) shift; cmd_reboot "$@" ;;
  summary) cmd_summary ;;
  *) echo "usage: web-host-reboot.sh reboot <host> <confirm> | summary" >&2; exit 2 ;;
esac
