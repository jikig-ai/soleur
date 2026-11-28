# shellcheck shell=bash
# bastion-boot-verify.sh — the bastion birth's readiness decision (#12866, ADR-327 step 2a).
#
# One decision, in a library, because both routes (bastion-host-create and #12879's
# bastion-host-replace) need the same one and inline copies of git-data's boot poll drifted within a
# single PR (git-data-boot-signal-poll.sh records why).
#
#   bastion_boot_verify <boot-trail-since-epoch> <apply-outcome> <dispatch-label> <pre-ids>   # 0 ready, 1 not
#     dispatch-label: the apply_target name used in prose and in the reader's summary
#                     (bastion-host-create or bastion-host-replace; default bastion-host-create)
#     pre-ids:        the PRE-APPLY ID SET: every soleur-bastion id the job read from the API before the
#                     apply, space-separated, or the literal `none`. A server whose id is in it is NEVER
#                     read or powered off: if the apply failed before the destroy (or a birth's create
#                     failed on a live bastion after lost state), the healthy old server is left alone and
#                     the result is poweroff_result=old_untouched. Missing or malformed on the replace
#                     label, it fails closed (poweroff_result=refused_no_preids). Omitted on the create
#                     label, the 2a behaviour holds (an empty set).
#
# READY ONLY ON A POSITIVE VERDICT. Runs fresh-host-boot-trail.sh in strict mode for soleur-bastion;
# ready means the reader printed exactly one line `verdict=ready` AND exited 0. The reader's web-mode
# exit is 0 on a SKIPPED read, so no exit code alone is ever trusted (plan-sharp-edges, #12866).
#
# BOUND TO THE CREATED SERVER. After a successful apply the soleur-bastion server is looked up first
# and its numeric id is passed as BOOT_TRAIL_HOST_ID, so a fresh_boot_ready forged by anyone holding
# the (public) DSN does not satisfy the read. A successful apply with NO such server is not ready. A
# lookup that fails outright is named and the read proceeds bound by host_name only: one Hetzner API
# blip must not, by itself, waste a birth.
#
# EVERYTHING ELSE POWERS THE HOST OFF: not_ready, skipped, a missing or doubled verdict, a failed
# apply that still created the server. The bastion has no heartbeat until #13113, so a host that did
# not prove ready must not sit running on the private network. Power-off (not delete) keeps the disk
# for the post-mortem; the recovery is bastion-host-replace (the printed line pins the powered-off id).
# The run URL is commented on #9421, the open web-1 retirement epic (#12879 R4; that target must move
# again before #9421 closes).
#
# The reader's output is STREAMED: each line is written to the job's stdout as the reader prints it
# and kept in a copy for the verdict check, so a run cancelled or killed by its timeout mid-poll still
# shows the trail it had read.
#
# Outputs, when the runner provides them:
#   $GITHUB_OUTPUT        poweroff_result=not_needed|powered_off|absent|old_untouched|refused_no_preids|failed
#                         comment_result=posted|failed|no_token
#   $GITHUB_STEP_SUMMARY  one line stating what actually happened to the host (never a claim the
#                         power-off arm did not achieve)
#
# _bbv_poweroff [pre-ids] (also called on its own by the job's cancelled-path step): powers off the one
# soleur-bastion OUTSIDE the pre-apply id set; sets _BBV_POWEROFF=powered_off|absent|old_untouched|
# refused_no_preids|failed; returns 0 unless it failed or refused. With NO argument it keeps the 2a
# behaviour; an argument that is empty or malformed refuses (the guard lives at this lowest level, so
# the cancel step and the failed-apply path cannot skip it).
#
# _bbv_servers_doc <out-file>: the replace route's one Hetzner reader (the step-6 read, the TOCTOU
# re-read and the summary's next-dispatch read). HTTP 200 exactly and a `.servers` array, or non-zero
# with http=<code> and .error.code only (never the body).
#
# Inputs (environment): HCLOUD_TOKEN (Hetzner API, sent on curl's stdin config via bc_curl),
# GH_TOKEN (the issue comment; skipped by name when absent), RUN_URL, SENTRY_ACTIONS_RO_TOKEN (read by
# the reader). BASTION_BOOT_TRAIL overrides the reader path for the suite.

_BBV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/bearer-curl.sh
source "${_BBV_DIR}/bearer-curl.sh" || { echo "::error::bastion-boot-verify: cannot load bearer-curl.sh"; return 1 2>/dev/null || exit 1; }

# _bbv_call <method> <url> -> prints the body, then a final line holding the HTTP code (000 on a transport
# failure). No tempfile: curl's own -w appends the code to the body on stdout, so nothing needs a trap.
_bbv_call() {
  local resp
  resp="$(bc_curl bastion-boot-verify 'Authorization:Bearer :HCLOUD_TOKEN' -- -sS --max-time 20 -X "$1" -w '\n%{http_code}' "$2" 2>/dev/null)" || true
  [[ "$resp" == *$'\n'* ]] || resp=$'\n'"${resp:-000}"
  printf '%s' "$resp"
}

# _bbv_preids_ok <set>: `none`, or space-separated server ids, under LC_ALL=C.
_bbv_preids_ok() { local LC_ALL=C; [[ "${1:-}" =~ ^(none|[1-9][0-9]{0,11}( [1-9][0-9]{0,11})*)$ ]]; }

# _bbv_lookup [pre-ids]: the one soleur-bastion OUTSIDE the pre-apply set. Sets _BBV_SERVER_ID, and
# _BBV_PRE_PRESENT / _BBV_PRE_ID (how many pre-apply servers the API still shows, and the first). 0 =
# found, 3 = none outside the set exists, 1 = the lookup failed (named; never read as "none").
# `arrays` makes a 200 without a servers array a failure.
_bbv_lookup() {
  local pre="${1:-}" resp code body n id
  _BBV_SERVER_ID="" _BBV_PRE_PRESENT=0 _BBV_PRE_ID=""
  [[ "$pre" == none ]] && pre=""
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    echo "::error::bastion-boot-verify: HCLOUD_TOKEN is not set, so the soleur-bastion server could not be looked up."
    return 1
  fi
  resp="$(_bbv_call GET "https://api.hetzner.cloud/v1/servers?name=soleur-bastion")"
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [[ "$code" != 200 ]] || ! n="$(jq -e '.servers | arrays | length' <<<"$body" 2>/dev/null)"; then
    echo "::error::bastion-boot-verify: the Hetzner server lookup failed (HTTP ${code}, or no servers array in the answer)."
    return 1
  fi
  if [[ -n "$pre" ]]; then
    _BBV_PRE_PRESENT="$(jq --arg pre "$pre" '($pre | split(" ")) as $p | [.servers[] | select((.id | tostring) as $i | $p | any(. == $i))] | length' <<<"$body" 2>/dev/null)" || _BBV_PRE_PRESENT=""
    _BBV_PRE_ID="$(jq -r --arg pre "$pre" '($pre | split(" ")) as $p | [.servers[] | (.id | tostring) | select(. as $i | $p | any(. == $i))][0] // empty' <<<"$body" 2>/dev/null)" || _BBV_PRE_ID=""
    body="$(jq -c --arg pre "$pre" '($pre | split(" ")) as $p | .servers |= map(select((.id | tostring) as $i | ($p | any(. == $i)) | not))' <<<"$body" 2>/dev/null)" || body=""
    n="$(jq '.servers | length' <<<"$body" 2>/dev/null)" || n=""
    if [[ ! "$_BBV_PRE_PRESENT" =~ ^[0-9]+$ || ! "$n" =~ ^[0-9]+$ ]]; then
      echo "::error::bastion-boot-verify: the Hetzner answer could not be filtered by the pre-apply id set."
      return 1
    fi
  fi
  [[ "$n" -eq 0 ]] && return 3
  if [[ "$n" -ne 1 ]]; then
    echo "::error::bastion-boot-verify: ${n} servers are named soleur-bastion; refusing to guess which is this run's. Inspect the Hetzner project now."
    return 1
  fi
  id="$(jq -r '.servers[0].id' <<<"$body")"
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "::error::bastion-boot-verify: the server id '${id}' is not numeric."; return 1; }
  _BBV_SERVER_ID="$id"
}

_bbv_poweroff() {  # [pre-ids]: power off the one soleur-bastion outside the pre-apply set; never guesses between two
  local resp code lrc=0 pre=""
  _BBV_POWEROFF=failed
  if [[ $# -ge 1 ]]; then
    if ! _bbv_preids_ok "${1:-}"; then
      echo "::error::bastion-boot-verify: the pre-apply id set is missing or malformed, so NOTHING was powered off: a server that existed before the apply must never be touched, and without the set this run cannot tell it from the new one. Confirm in the Hetzner console which soleur-bastion is this run's."
      _BBV_POWEROFF=refused_no_preids
      return 1
    fi
    pre="$1"
  fi
  _bbv_lookup "$pre" || lrc=$?
  if [[ "$lrc" -eq 3 && "${_BBV_PRE_PRESENT:-0}" -gt 0 ]]; then
    echo "bastion-boot-verify: the only soleur-bastion is the pre-apply server ${_BBV_PRE_ID} (it existed before this apply); it is left untouched, never powered off."
    _BBV_POWEROFF=old_untouched
    return 0
  fi
  if [[ "$lrc" -eq 3 ]]; then
    echo "bastion-boot-verify: no soleur-bastion server exists (the apply did not create it); nothing to power off."
    _BBV_POWEROFF=absent
    return 0
  fi
  if [[ "$lrc" -ne 0 ]]; then
    echo "::error::bastion-boot-verify: soleur-bastion could NOT be powered off (see the line above). Power it off in the Hetzner console now (Servers > soleur-bastion > Power > Power off)."
    return 1
  fi
  resp="$(_bbv_call POST "https://api.hetzner.cloud/v1/servers/${_BBV_SERVER_ID}/actions/poweroff")"
  code="${resp##*$'\n'}"
  if [[ "$code" != 201 && "$code" != 200 ]]; then
    echo "::error::bastion-boot-verify: the poweroff call for server ${_BBV_SERVER_ID} failed (HTTP ${code}). Power soleur-bastion off in the Hetzner console now."
    return 1
  fi
  # A 201 means Hetzner ACCEPTED the action, not that the host is off: wait for the action itself
  # (bounded, ~60 s), so an action that ends in error is never reported as powered off.
  local aid status="" i
  aid="$(jq -r '.action.id // empty' <<<"${resp%$'\n'*}" 2>/dev/null)"
  if [[ ! "$aid" =~ ^[0-9]+$ ]]; then
    echo "::error::bastion-boot-verify: the poweroff answer for server ${_BBV_SERVER_ID} carried no action id. Confirm soleur-bastion is off in the Hetzner console now."
    return 1
  fi
  for i in $(seq 1 20); do
    resp="$(_bbv_call GET "https://api.hetzner.cloud/v1/actions/${aid}")"
    code="${resp##*$'\n'}"
    status="$(jq -r '.action.status // empty' <<<"${resp%$'\n'*}" 2>/dev/null)"
    [[ "$code" == 200 && "$status" == success ]] && break
    if [[ "$code" == 200 && "$status" == error ]]; then
      echo "::error::bastion-boot-verify: the poweroff action ${aid} for server ${_BBV_SERVER_ID} ended in error. Power soleur-bastion off in the Hetzner console now."
      return 1
    fi
    [[ "$i" -eq 20 ]] || sleep 3
  done
  if [[ "$status" != success ]]; then
    echo "::error::bastion-boot-verify: the poweroff action ${aid} for server ${_BBV_SERVER_ID} did not finish (last status '${status:-unread}'). Confirm soleur-bastion is off in the Hetzner console now."
    return 1
  fi
  echo "bastion-boot-verify: soleur-bastion (server ${_BBV_SERVER_ID}) powered off; its disk is kept for the post-mortem."
  _BBV_POWEROFF=powered_off
}

_bbv_record() {  # <poweroff_result> <summary line>
  [[ -z "${GITHUB_OUTPUT:-}" ]] || printf 'poweroff_result=%s\n' "$1" >> "$GITHUB_OUTPUT"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || printf '%s\n' "$2" >> "$GITHUB_STEP_SUMMARY"
}
_bbv_record_comment() {  # <comment_result> <summary line>
  [[ -z "${GITHUB_OUTPUT:-}" ]] || printf 'comment_result=%s\n' "$1" >> "$GITHUB_OUTPUT"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || printf '%s\n' "$2" >> "$GITHUB_STEP_SUMMARY"
}

# _bbv_dispatch_line <expected_bastion_server_id>: the ready-to-run replace dispatch (rehearsal first).
_bbv_dispatch_line() {
  printf "gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-replace -f confirm=REPLACE-bastion -f expected_bastion_server_id=%s -f plan_only=true -f reason='<why>' (rehearse, then re-run without plan_only)" "$1"
}

# _bbv_servers_doc <out-file>: GET /v1/servers?name=soleur-bastion into <out-file>; 0 only on HTTP 200
# with a `.servers` array. On anything else the file is removed and one line names http=<code> and
# .error.code (the body itself is never printed).
_bbv_servers_doc() {
  local out="${1:-}" code ecode
  if [[ -z "$out" ]]; then
    echo "::error::bastion-boot-verify: _bbv_servers_doc needs an output file."
    return 1
  fi
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    echo "bastion-boot-verify: Hetzner server read FAILED (http=000, HCLOUD_TOKEN is not set)"
    return 1
  fi
  code="$(bc_curl bastion-boot-verify 'Authorization:Bearer :HCLOUD_TOKEN' -- -sS --max-time 20 -o "$out" -w '%{http_code}' "https://api.hetzner.cloud/v1/servers?name=soleur-bastion" 2>/dev/null)" || true
  [[ "$code" =~ ^[0-9]{3}$ ]] || code=000
  if [[ "$code" != 200 ]] || ! jq -e '.servers | arrays' < "$out" >/dev/null 2>&1; then
    ecode="$(jq -r '.error.code? // empty | tostring' < "$out" 2>/dev/null | head -c 64 | tr -cd 'A-Za-z0-9_.-')" || ecode=""
    rm -f -- "$out"
    echo "bastion-boot-verify: Hetzner server read FAILED (http=${code}${ecode:+, error.code=${ecode}})"
    return 1
  fi
  return 0
}

bastion_boot_verify() {
  local since="${1:-}" apply_outcome="${2:-}" label="${3:-bastion-host-create}"
  local job_status=failure reader out rc=0 verdicts host_id="" lrc=0 reason="" pre_given=0 pre=""
  [[ "$label" =~ ^[a-z0-9-]+$ ]] || label=bastion-host-create
  # The pre-apply id set: passed (4th argument), or required (the replace label fails closed without it).
  if [[ $# -ge 4 ]]; then pre_given=1; pre="${4:-}"; fi
  [[ "$label" == bastion-host-replace && "$pre_given" -eq 0 ]] && pre_given=1
  if [[ "$pre_given" -eq 1 ]] && ! _bbv_preids_ok "$pre"; then
    reason="the pre-apply id set is missing or malformed"
  fi
  reader="${BASTION_BOOT_TRAIL:-${_BBV_DIR}/../../apps/web-platform/infra/scripts/fresh-host-boot-trail.sh}"
  [[ "$apply_outcome" == success ]] && job_status=success
  if [[ -z "$reason" && "$job_status" == success ]]; then
    _bbv_lookup "$pre" || lrc=$?
    if [[ "$lrc" -eq 0 ]]; then
      host_id="$_BBV_SERVER_ID"
    elif [[ "$lrc" -eq 3 && "${_BBV_PRE_PRESENT:-0}" -gt 0 ]]; then
      reason="the apply succeeded but the API shows only the pre-apply soleur-bastion ${_BBV_PRE_ID}"
    elif [[ "$lrc" -eq 3 ]]; then
      reason="the apply succeeded but no soleur-bastion server exists"
    else
      echo "::warning::bastion-boot-verify: the read is bound by host_name only (the server lookup above failed)."
    fi
  fi
  if [[ -n "$reason" ]]; then
    out="bastion-boot-verify: ${reason}; the boot trail was not read"; rc=1
    printf '%s\n' "$out"
  elif [[ -f "$reader" ]]; then
    # Stream the reader to the run log as it runs (its wait can last 25 minutes) and keep a copy.
    # Each line is written through a DUPLICATE of stdout, never by reopening /dev/fd/N: `tee` reopens
    # the path, which truncates a stdout that is a regular file and writes at a second offset that the
    # shell then overwrites. The substitution exits with the reader's own status.
    local fd
    exec {fd}>&1
    out="$(BOOT_TRAIL_STRICT=1 BOOT_TRAIL_HOST_NAME=soleur-bastion BOOT_TRAIL_HOST_ID="$host_id" BOOT_TRAIL_SINCE="$since" \
      JOB_STATUS="$job_status" DISPATCH_LABEL="$label" bash "$reader" 2>&1 \
      | { while IFS= read -r line || [[ -n "$line" ]]; do printf '%s\n' "$line" >&"$fd"; printf '%s\n' "$line"; done; }
      exit "${PIPESTATUS[0]}")" || rc=$?
    exec {fd}>&-
  else
    out="bastion-boot-verify: the boot-trail reader is missing at ${reader}"; rc=2
    printf '%s\n' "$out"
  fi
  verdicts="$(grep '^verdict=' <<<"$out" || true)"
  if [[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]; then
    echo "bastion-boot-verify: READY — soleur-bastion reported fresh_boot_ready after the run anchor (apply ${apply_outcome})."
    _bbv_record not_needed "- boot-verify: **READY** — soleur-bastion (server ${host_id:-id unread}) reported fresh_boot_ready; nothing was powered off."
    # The ready server's id, for the pin read-back step (the next replace dispatch pins it).
    [[ -z "${GITHUB_OUTPUT:-}" ]] || printf 'server_id=%s\n' "${host_id:-unread}" >> "$GITHUB_OUTPUT"
    return 0
  fi
  echo "::error::bastion-boot-verify: soleur-bastion is NOT ready (reader exit ${rc}; verdict lines: '${verdicts//$'\n'/ | }'; apply ${apply_outcome}). Powering it off."
  local poweroff_note next_id="<read the id from a plan_only run's summary>"
  if [[ "$pre_given" -eq 1 ]]; then _bbv_poweroff "$pre" || true; else _bbv_poweroff || true; fi
  case "$_BBV_POWEROFF" in
    powered_off) poweroff_note="soleur-bastion powered off, disk kept"; next_id="$_BBV_SERVER_ID"
      _bbv_record powered_off "- boot-verify: **NOT READY** — soleur-bastion (server ${_BBV_SERVER_ID}) was powered off; its disk is kept." ;;
    absent) poweroff_note="no soleur-bastion server exists, nothing to power off"; next_id=none
      _bbv_record absent "- boot-verify: **NOT READY** — no soleur-bastion server exists, so nothing was powered off." ;;
    old_untouched) poweroff_note="the only soleur-bastion is the pre-apply server ${_BBV_PRE_ID}, left untouched"; next_id="$_BBV_PRE_ID"
      _bbv_record old_untouched "- boot-verify: **NOT READY** — the only soleur-bastion is the pre-apply server ${_BBV_PRE_ID} (it existed before this apply); it was left untouched, never powered off." ;;
    refused_no_preids) poweroff_note="the pre-apply id set was missing or malformed, so nothing was powered off"
      _bbv_record refused_no_preids "- boot-verify: **NOT READY and the power-off was REFUSED** — the pre-apply id set was missing or malformed, so this run could not tell the new server from the old. Check the Hetzner project now." ;;
    *) poweroff_note="the power-off FAILED, soleur-bastion may still be running"
      _bbv_record failed "- boot-verify: **NOT READY and the power-off FAILED** — soleur-bastion may still be running. Power it off in the Hetzner console now." ;;
  esac
  local recovery
  if [[ "$_BBV_POWEROFF" == old_untouched ]]; then
    recovery="::error::Recovery: the apply did not replace the pre-apply soleur-bastion ${_BBV_PRE_ID}; it is untouched and still the live bastion. Read the apply log above, then re-dispatch with the same pin: $(_bbv_dispatch_line "$next_id")"
  else
    recovery="::error::Recovery: read the boot-trail stage above, fix bastion-cloud-init.yml if it is a template fault, then replace (this destroys the kept disk): $(_bbv_dispatch_line "$next_id")"
  fi
  [[ "$label" == bastion-host-create ]] && recovery="${recovery} Do not re-run bastion-host-create: the server exists, so its gate refuses."
  echo "$recovery"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    local repo=()
    [[ -n "${GITHUB_REPOSITORY:-}" ]] && repo=(--repo "$GITHUB_REPOSITORY")
    if gh issue comment 9421 "${repo[@]}" --body "${label} did not reach ready (${poweroff_note}). Run: ${RUN_URL:-unknown}. Recovery is bastion-host-replace." >/dev/null 2>&1; then
      _bbv_record_comment posted "- boot-verify: the run URL was commented on #9421."
    else
      if [[ "$label" == bastion-host-replace ]]; then
        echo "::error::bastion-boot-verify: the comment on #9421 FAILED; post the run URL there by hand."
      else
        echo "::warning::bastion-boot-verify: the comment on #9421 FAILED; post the run URL there by hand."
      fi
      _bbv_record_comment failed "- boot-verify: the #9421 comment did NOT post; post the run URL there by hand."
    fi
  else
    echo "::warning::bastion-boot-verify: GH_TOKEN is not set; the run URL was not commented on #9421."
    _bbv_record_comment no_token "- boot-verify: GH_TOKEN was not set, so no comment was posted to #9421."
  fi
  return 1
}
