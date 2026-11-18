# shellcheck shell=bash
# bastion-boot-verify.sh — the bastion birth's readiness decision (#12866, ADR-327 step 2a).
#
# One decision, in a library, because #12879's replace job needs the same one and inline copies of
# git-data's boot poll drifted within a single PR (git-data-boot-signal-poll.sh records why).
#
#   bastion_boot_verify <boot-trail-since-epoch> <apply-outcome>   # 0 = ready, 1 = not ready
#
# READY ONLY ON A POSITIVE VERDICT. Runs fresh-host-boot-trail.sh in strict mode for soleur-bastion;
# ready means the reader printed exactly one line `verdict=ready` AND exited 0. The reader's web-mode
# exit is 0 on a SKIPPED read, so no exit code alone is ever trusted (plan-sharp-edges, #12866).
#
# EVERYTHING ELSE POWERS THE HOST OFF: not_ready, skipped, a missing or doubled verdict, a failed
# apply that still created the server. The bastion has no heartbeat until #12879, so a host that did
# not prove ready must not sit running on the private network. Power-off (not delete) keeps the disk
# for the post-mortem; the recovery is bastion-host-replace. The run URL is commented on #12879.
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

_bbv_poweroff() {  # power off the one soleur-bastion; never guesses between two
  local resp code body n id
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    echo "::error::bastion-boot-verify: HCLOUD_TOKEN is not set, so soleur-bastion could NOT be powered off. Power it off in the Hetzner console now (Servers > soleur-bastion > Power > Power off)."
    return 1
  fi
  resp="$(_bbv_call GET "https://api.hetzner.cloud/v1/servers?name=soleur-bastion")"
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  if [[ "$code" != 200 ]] || ! n="$(jq -e '.servers | length' <<<"$body" 2>/dev/null)"; then
    echo "::error::bastion-boot-verify: the Hetzner server lookup failed (HTTP ${code}), so soleur-bastion could NOT be powered off. Power it off in the Hetzner console now."
    return 1
  fi
  if [[ "$n" -eq 0 ]]; then
    echo "bastion-boot-verify: no soleur-bastion server exists (the apply did not create it); nothing to power off."
    return 0
  fi
  if [[ "$n" -ne 1 ]]; then
    echo "::error::bastion-boot-verify: ${n} servers are named soleur-bastion; refusing to guess which to power off. Inspect the Hetzner project now."
    return 1
  fi
  id="$(jq -r '.servers[0].id' <<<"$body")"
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "::error::bastion-boot-verify: the server id '${id}' is not numeric; soleur-bastion was NOT powered off."; return 1; }
  resp="$(_bbv_call POST "https://api.hetzner.cloud/v1/servers/${id}/actions/poweroff")"
  code="${resp##*$'\n'}"
  if [[ "$code" != 201 && "$code" != 200 ]]; then
    echo "::error::bastion-boot-verify: the poweroff call for server ${id} failed (HTTP ${code}). Power soleur-bastion off in the Hetzner console now."
    return 1
  fi
  echo "bastion-boot-verify: soleur-bastion (server ${id}) powered off; its disk is kept for the post-mortem."
}

bastion_boot_verify() {
  local since="${1:-}" apply_outcome="${2:-}" job_status=failure reader out rc=0 verdicts
  reader="${BASTION_BOOT_TRAIL:-${_BBV_DIR}/../../apps/web-platform/infra/scripts/fresh-host-boot-trail.sh}"
  [[ "$apply_outcome" == success ]] && job_status=success
  if [[ -f "$reader" ]]; then
    out="$(BOOT_TRAIL_STRICT=1 BOOT_TRAIL_HOST_NAME=soleur-bastion BOOT_TRAIL_SINCE="$since" JOB_STATUS="$job_status" \
      DISPATCH_LABEL=bastion-host-create bash "$reader" 2>&1)" || rc=$?
  else
    out="bastion-boot-verify: the boot-trail reader is missing at ${reader}"; rc=2
  fi
  printf '%s\n' "$out"
  verdicts="$(grep '^verdict=' <<<"$out" || true)"
  if [[ "$verdicts" == "verdict=ready" && "$rc" -eq 0 ]]; then
    echo "bastion-boot-verify: READY — soleur-bastion reported fresh_boot_ready after the run anchor (apply ${apply_outcome})."
    return 0
  fi
  echo "::error::bastion-boot-verify: soleur-bastion is NOT ready (reader exit ${rc}; verdict lines: '${verdicts//$'\n'/ | }'; apply ${apply_outcome}). Powering it off."
  local poweroff_note="soleur-bastion powered off or absent"
  _bbv_poweroff || poweroff_note="the power-off FAILED, see the run log"
  echo "::error::Recovery: read the trail above for the stage that died, fix bastion-cloud-init.yml if it is a template fault, then dispatch bastion-host-replace (#12879). Do not re-run bastion-host-create: the server exists, so its gate refuses."
  if [[ -n "${GH_TOKEN:-}" ]]; then
    local repo=()
    [[ -n "${GITHUB_REPOSITORY:-}" ]] && repo=(--repo "$GITHUB_REPOSITORY")
    gh issue comment 12879 "${repo[@]}" --body "bastion-host-create did not reach ready (${poweroff_note}). Run: ${RUN_URL:-unknown}. Recovery is bastion-host-replace." >/dev/null 2>&1 \
      || echo "::warning::bastion-boot-verify: the comment on #12879 failed; post the run URL there by hand."
  else
    echo "::warning::bastion-boot-verify: GH_TOKEN is not set; the run URL was not commented on #12879."
  fi
  return 1
}
