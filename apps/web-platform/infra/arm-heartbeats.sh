#!/usr/bin/env bash
# Measured-beat ARM gate for the web-host probe heartbeats (#6438/#6548, ADR-117 automated).
#
# EXTRACTED FROM `.github/workflows/apply-web-platform-infra.yml` (#7587). It used to be ~130
# lines of bash inside a YAML scalar, which nothing asserted on: `git grep arm_one` across the
# test trees returned only comments. A guard written against bash-inside-YAML can only check
# that a clock read APPEARS in the step — which a decoy `date +%s` satisfies and an equivalent
# rewrite false-REDs. As a real script it is driven behaviourally by `arm-heartbeats.test.sh`
# with a fake clock and a fake `curl` on PATH, the house shape used by
# `web-private-nic-guard.sh` + `.test.sh` and the other pairs in this directory.
#
# THE SEQUENCE (ADR-117's, VERIFIED against the live Better Stack API). A paused heartbeat
# exposes NO usable ping timestamp — `attributes` is {status, paused, period, grace,
# updated_at, url, …} with NO last_ping_at, and `updated_at` does not move when a beat arrives
# while paused. So the only way to MEASURE a real beat is to UNPAUSE and watch `status`
# transition to `up`, rolling back BEFORE the first absence alert if it never does. Per monitor:
#   1. resolve the monitor id from TFSTATE (never a name-regex — a name collision would arm the
#      wrong monitor);
#   2. OP/STATE-GATE on live `status=="paused"`: a monitor already `up`/`pending`/`down`
#      (ignore_changes=[paused] keeps SOURCE paused=true forever, but a prior arm unpaused it
#      LIVE) is skipped, so routine re-applies are a TRUE no-op and never flake on a BS blip;
#   3. PATCH {paused:false}, then poll `status` until `up` within the deadline;
#   4. `up` ⇒ a real beat landed ⇒ ARMED. Otherwise PATCH {paused:true} IMMEDIATELY (roll back
#      BEFORE the first absence alert would fire) — never leave an unfed monitor live, never
#      leave a green-but-inert one paused-and-forgotten.
#
# ERREXIT. The caller is a GitHub `run:` step with no `shell:` key, so GitHub invokes it as
# `/usr/bin/bash -e {0}` (ADR-170) — but this file runs as its own process under its own
# shebang, so it owns its flags. `set +e` is declared EXPLICITLY anyway rather than merely
# omitting `-e`: the difference is invisible to a reader and the whole point of the rollback
# path is that it must not abort at the first failing PATCH.
#
# CONTRACT (env in, exit code out):
#   BS_TOKEN            (required) Better Stack API token, already ::add-mask::ed by the caller.
#   TFSTATE_JSON        (required) path to `terraform show -json` output for the web-platform root.
#   ARMED_UNCONFIRMED   (required) path to the state file the `if: always()` re-pause sweep reads.
#   BS_API_BASE         (optional) Better Stack API root; overridden only by the test harness.
#   ARM_POLL_INTERVAL_S (optional) poll period, default 10; lowered only by the test harness.
# Exit 0 = every arm either armed or was a no-op. Exit 1 = at least one arm could not do its job.

set -uo pipefail
set +e   # explicit, not inherited — see ERREXIT above.

BS_TOKEN="${BS_TOKEN:-}"
TFSTATE_JSON="${TFSTATE_JSON:-}"
ARMED_UNCONFIRMED="${ARMED_UNCONFIRMED:-}"
BS_API_BASE="${BS_API_BASE:-https://uptime.betterstack.com/api/v2}"
ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-10}"

for _required in BS_TOKEN TFSTATE_JSON ARMED_UNCONFIRMED; do
  if [[ -z "${!_required}" ]]; then
    echo "::error::arm-heartbeats.sh: ${_required} is unset — refusing to run a half-configured arming pass."
    exit 1
  fi
done
if [[ ! -r "$TFSTATE_JSON" ]]; then
  echo "::error::arm-heartbeats.sh: TFSTATE_JSON=${TFSTATE_JSON} is not readable — cannot resolve any monitor id."
  exit 1
fi

hb_status() {  # <id> -> prints attributes.status (empty on lookup failure)
  curl -fsS --max-time 15 -H "Authorization: Bearer ${BS_TOKEN}" \
    "${BS_API_BASE}/heartbeats/$1" 2>/dev/null \
    | jq -r '.data.attributes.status // empty' 2>/dev/null || true
}
hb_patch_paused() {  # <id> <true|false> -> exit 0 on success
  curl -fsS --max-time 15 -X PATCH \
    -H "Authorization: Bearer ${BS_TOKEN}" -H 'Content-Type: application/json' \
    "${BS_API_BASE}/heartbeats/$1" \
    --data-raw "{\"paused\":$2}" >/dev/null 2>&1
}

# arm_one <state-address> <label> <deadline_seconds>
arm_one() {
  local addr="$1" label="$2" deadline="$3"
  local id status
  id=$(jq -r --arg a "$addr" '.values.root_module.resources[]? | select(.address==$a) | .values.id' "$TFSTATE_JSON")
  if [[ -z "$id" || "$id" == "null" ]]; then
    echo "::notice::${label}: not present in tfstate (address ${addr}) — skipping (this apply path did not create it)."
    return 0
  fi
  status=$(hb_status "$id")
  if [[ -z "$status" ]]; then
    echo "::error::${label}: GET /heartbeats/${id} failed — cannot verify arm state."
    return 1
  fi
  if [[ "$status" != "paused" ]]; then
    echo "${label}: already armed (status=${status}) — no-op."
    return 0
  fi
  echo "${label}: monitor ${id} is paused; unpausing and watching for a real beat (status→up, deadline=${deadline}s)…"
  if ! hb_patch_paused "$id" false; then
    echo "::error::${label}: PATCH paused=false FAILED — cannot begin arming."
    return 1
  fi
  local waited=0
  while [[ "$waited" -lt "$deadline" ]]; do
    sleep "$ARM_POLL_INTERVAL_S"
    waited=$(( waited + ARM_POLL_INTERVAL_S ))
    status=$(hb_status "$id")
    if [[ "$status" == "up" ]]; then
      echo "::notice::${label}: status=up within ${waited}s — a real beat landed. ARMED."
      return 0
    fi
  done
  # No `up` in time: roll back to paused BEFORE the first absence alert, then fail loud.
  # Returns 2, NOT 1, and the distinction is load-bearing for exactly one caller. Every other
  # non-zero exit from this function ("GET failed", "PATCH failed") means the gate could not do
  # its job. THIS one means the gate worked and the FEEDER is not feeding — an assertion about
  # the monitored system, not about the arming. Callers whose feeder is expected to be healthy
  # still treat it as fatal (`|| rc=1` catches any non-zero); the inngest-consumer caller below
  # distinguishes it, because its feeder is knowingly dark. The rollback is unconditional in
  # both cases: this function NEVER leaves an unpaused-and-unfed monitor behind, which is the
  # property the softer caller relies on.
  hb_patch_paused "$id" true || echo "::error::${label}: rollback PATCH paused=true ALSO failed — the monitor is unpaused-and-unfed; investigate immediately."
  echo "::error::${label}: status never reached 'up' within ${deadline}s (probe timer never pinged) — ROLLED BACK to paused. A green-but-inert monitor is the #6400 shape this gate exists to prevent. Investigate: is the web-1 timer installed + the private-net path healthy?"
  return 2
}

rc=0
# deadline = period + grace − 10 (roll back just before the first absence alert):
# zot 180+60−10, nic-guard 360+120−10, git-data 60+180−10, inngest-consumer 180+60−10.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-1"]' 'web-zot-consumer (web-1)' 230 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-1"]'    'web-nic-guard (web-1)'    470 || rc=1
# (#6459/ADR-143) web-2's per-host heartbeats are born `paused` (web-probe.tf
# ignore_changes=[paused]) exactly like web-1's; the ONLY unpause path is this gate, so they
# MUST be armed here or web2-standby-soak-6459.sh reads them `paused` and false-FAILs a healthy
# web-2 as a DARK host (#6459 could never close). arm_one no-ops (return 0) when the address is
# absent from tfstate, so this is inert on any apply path that has not yet created web-2.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-2"]' 'web-zot-consumer (web-2)' 230 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-2"]'    'web-nic-guard (web-2)'    470 || rc=1
arm_one 'betteruptime_heartbeat.git_data_prd'              'git-data-prd'             230 || rc=1

# (#7228) inngest-consumer — the ONE caller that distinguishes rc=2 (see arm_one's terminal
# branch). Its feeder is inngest-consumer-probe.sh on web-1, which pings only after reading a
# NON-EMPTY function registry out of 10.0.1.40:8288. That host has not bound :8288 since
# 2026-07-30, and THIS CHANGE DOES NOT FIX THAT — the fix needs `apply_target=inngest-host-replace`
# plus a cutover window, both deferred to numbered issues. So the probe is correctly SUPPRESSING,
# no beat can land, and arming hard here would red the infra apply on EVERY merge for the whole
# deferral window.
#
# This is not the "best-effort status" anti-pattern the header rejects, and the difference is that
# the softness is self-clearing rather than permanent: arm_one returns 0 via its
# `already armed (status=…)` branch once the monitor is up, and ignore_changes=[paused] keeps it
# that way, so the FIRST apply after 10.0.1.40 actually serves arms it hard and every later apply
# is a no-op. The rollback-to-paused inside arm_one still runs, so we never leave an
# unpaused-and-unfed monitor. What we are declining to do is fail an apply because a KNOWN,
# TRACKED, OPEN outage is still open.
arc=0
arm_one 'betteruptime_heartbeat.inngest_consumer' 'inngest-consumer (web-1)' 230 || arc=$?
if [[ "$arc" -eq 2 ]]; then
  echo "::warning::inngest-consumer: no beat within 230s; monitor rolled back to paused. This is the EXPECTED state while the 10.0.1.40 bind failure (#7228) is open — the consumer probe suppresses its ping by design when the dedicated host serves nothing. It arms automatically on the first apply after that host serves. If #7228 is CLOSED and you are still seeing this, the probe or the private-net path is broken: check 'systemctl list-timers inngest-consumer-probe.timer' on web-1 and query SyslogIdentifier=inngest-consumer-probe in Better Stack for the classification."
elif [[ "$arc" -ne 0 ]]; then
  rc=1
fi
exit "$rc"
