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
# THE DEADLINE IS WALL CLOCK, NOT A SLEEP TALLY (#7587, and the #5795 defect class). The poll
# loop used to advance its counter by `sleep 10` alone, with the per-iteration
# `curl --max-time 15` uncounted — so a nominal `deadline` could consume up to
# `deadline + (deadline/10) × 15 = deadline × 2.5` of real wall clock. Better Stack answers in
# ~0.2 s today (measured: 235 s elapsed against a 230 s nominal deadline on run 32360734255),
# so the exposure is to vendor latency rather than to normal operation — but a budget that
# counts only its own sleeps is out-raced by its own round-trips, which is exactly what a
# step-level `timeout-minutes` cannot compensate for. `elapsed` is now re-read from the clock
# after every round-trip, so the bound holds at `deadline + one iteration` regardless of vendor
# latency.
#
# THE ROLLBACK IS ALSO RECORDED, NOT ONLY ATTEMPTED. Every id whose `PATCH {paused:false}`
# succeeded is appended to `$ARMED_UNCONFIRMED` and removed ONLY when it reaches `up` or when a
# rollback `PATCH {paused:true}` actually returns 2xx. Removing on "rollback attempted" would
# drop a FAILED rollback's id, so the `if: always()` re-pause sweep in the workflow — the last
# chance to re-pause it — would never retry the exact monitor the `::error::` is warning about.
# There is deliberately NO `trap` (Cut List C6): bash keeps only the last EXIT handler, an
# INT/TERM handler returns and then fires EXIT too (double-PATCH), and bash defers the handler
# until the foreground `sleep` returns. The state file plus the sibling sweep step is ONE
# mechanism with ONE entry point, and it survives a step-level cancellation, which a trap
# does not.
#
# ERREXIT. The caller is a GitHub `run:` step with no `shell:` key, so GitHub invokes it as
# `/usr/bin/bash -e {0}` (ADR-170) — but this file runs as its own process under its own
# shebang, so it owns its flags. `set +e` is declared EXPLICITLY anyway rather than merely
# omitted: the difference is invisible to a reader, and the whole point of the rollback path is
# that it must not abort at the first failing PATCH. For the same reason every rollback `PATCH`
# carries `|| true`, and no arithmetic is written as a bare `(( … ))` — that exits non-zero
# whenever the expression evaluates to 0.
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

now_s() { date +%s; }

# --- the unconfirmed-arm state file -------------------------------------------------------
# One id per line. `state_add` fires immediately after a successful unpause; `state_remove`
# fires ONLY on a real 2xx rollback or on reaching `up`.
state_add() { printf '%s\n' "$1" >> "$ARMED_UNCONFIRMED"; }
state_remove() {
  [[ -f "$ARMED_UNCONFIRMED" ]] || return 0
  local keep
  keep="${ARMED_UNCONFIRMED}.keep.$$"
  # `grep -vxF` exits 1 when it selects nothing, which is the ORDINARY case here (the last id
  # being removed). Guard it, and never read the source file through a pipe — a `grep -q` on a
  # pipe takes SIGPIPE on an early match under pipefail.
  grep -vxF -- "$1" "$ARMED_UNCONFIRMED" > "$keep" 2>/dev/null || true
  mv -f "$keep" "$ARMED_UNCONFIRMED"
}

# --- Better Stack ---------------------------------------------------------------------------
# HB_STATUS / HB_UPDATED_AT are set by hb_fetch and read by arm_one's terminal branch, which
# has to tell "the feeder never beat" apart from "a beat was simply not due inside our window".
HB_STATUS=""
HB_UPDATED_AT=""
hb_fetch() {  # <id> -> 0 and sets HB_STATUS/HB_UPDATED_AT; non-zero when the lookup failed
  local body
  body=$(curl -fsS --max-time 15 -H "Authorization: Bearer ${BS_TOKEN}" \
    "${BS_API_BASE}/heartbeats/$1" 2>/dev/null)
  [[ -n "$body" ]] || return 1
  HB_STATUS=$(printf '%s' "$body" | jq -r '.data.attributes.status // empty' 2>/dev/null)
  HB_UPDATED_AT=$(printf '%s' "$body" | jq -r '.data.attributes.updated_at // "unreported"' 2>/dev/null)
  [[ -n "$HB_STATUS" ]] || return 1
  return 0
}
hb_patch_paused() {  # <id> <true|false> -> exit 0 on success
  curl -fsS --max-time 15 -X PATCH \
    -H "Authorization: Bearer ${BS_TOKEN}" -H 'Content-Type: application/json' \
    "${BS_API_BASE}/heartbeats/$1" \
    --data-raw "{\"paused\":$2}" >/dev/null 2>&1
}

# ARM_ELAPSED / ARM_LAST_STATUS / ARM_LAST_UPDATED_AT report the last arm's terminal facts to
# the caller below. They are what the inngest-consumer message emits instead of a hard-coded
# deadline and a guess about which failure this was.
ARM_ELAPSED=0
ARM_LAST_STATUS=""
ARM_LAST_UPDATED_AT=""

# arm_one <state-address> <label> <deadline_seconds>
#   0 = armed or no-op          1 = the gate could not do its job (incl. a FAILED rollback)
#   2 = the gate worked and the FEEDER did not feed, monitor rolled back to paused
arm_one() {
  local addr="$1" label="$2" deadline="$3"
  local id started elapsed
  ARM_ELAPSED=0
  ARM_LAST_STATUS=""
  ARM_LAST_UPDATED_AT=""
  id=$(jq -r --arg a "$addr" '.values.root_module.resources[]? | select(.address==$a) | .values.id' "$TFSTATE_JSON")
  if [[ -z "$id" || "$id" == "null" ]]; then
    echo "::notice::${label}: not present in tfstate (address ${addr}) — skipping (this apply path did not create it)."
    return 0
  fi
  if ! hb_fetch "$id"; then
    echo "::error::${label}: GET /heartbeats/${id} failed — cannot verify arm state."
    return 1
  fi
  ARM_LAST_STATUS="$HB_STATUS"
  ARM_LAST_UPDATED_AT="$HB_UPDATED_AT"
  if [[ "$HB_STATUS" != "paused" ]]; then
    echo "${label}: already armed (status=${HB_STATUS}) — no-op."
    return 0
  fi
  echo "${label}: monitor ${id} is paused; unpausing and watching for a real beat (status→up, deadline=${deadline}s)…"
  if ! hb_patch_paused "$id" false; then
    echo "::error::${label}: PATCH paused=false FAILED — cannot begin arming."
    return 1
  fi
  # The id is on the sweep's books from the instant the monitor is live, not from the instant
  # we decide to give up: everything between those two points is exactly the window in which an
  # externally-imposed cut leaves it unpaused-and-unfed.
  state_add "$id"
  started=$(now_s)
  elapsed=0
  while [[ "$elapsed" -lt "$deadline" ]]; do
    sleep "$ARM_POLL_INTERVAL_S"
    if hb_fetch "$id"; then
      ARM_LAST_STATUS="$HB_STATUS"
      ARM_LAST_UPDATED_AT="$HB_UPDATED_AT"
    fi
    # Re-read the CLOCK rather than adding the sleep: the round-trip above is inside the loop
    # and is the term the old tally ignored.
    elapsed=$(( $(now_s) - started ))
    if [[ "$ARM_LAST_STATUS" == "up" ]]; then
      ARM_ELAPSED="$elapsed"
      state_remove "$id"
      echo "::notice::${label}: status=up within ${elapsed}s — a real beat landed. ARMED."
      return 0
    fi
  done
  ARM_ELAPSED="$elapsed"
  # No `up` in time: roll back to paused BEFORE the first absence alert.
  #
  # rc=2, NOT 1, and the distinction is load-bearing for exactly one caller. Every other
  # non-zero exit from this function ("GET failed", "PATCH failed") means the gate could not do
  # its job. THIS one means the gate worked and the FEEDER is not feeding — an assertion about
  # the monitored system, not about the arming. Callers whose feeder is expected to be healthy
  # still treat it as fatal (`|| rc=1` catches any non-zero); the inngest-consumer caller below
  # distinguishes it, because its feeder is knowingly dark.
  #
  # A FAILED rollback is NOT that case and returns 1 even for the soft caller. "The monitor is
  # unpaused and nothing is feeding it" is a statement about the arming, and it is the one
  # condition where a soft landing would leave the apply job GREEN while production uptime
  # alerting is live-and-unfed — the predicate on the notify job would be false and nobody
  # would be emailed, which is the #7586 defect reproduced inside the #7587 fix.
  if hb_patch_paused "$id" true; then
    state_remove "$id"
  else
    echo "::error::${label}: rollback PATCH paused=true FAILED — monitor ${id} is unpaused-and-unfed. Left on the re-pause sweep's books; investigate immediately."
    echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (last status=${ARM_LAST_STATUS:-unknown})."
    return 1
  fi
  echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (probe timer never pinged) — ROLLED BACK to paused. A green-but-inert monitor is the #6400 shape this gate exists to prevent. Investigate: is the web-1 timer installed + the private-net path healthy?"
  return 2
}

rc=0
# deadline = period + grace − 10 (roll back just before the first absence alert):
# zot 180+60−10, nic-guard 360+120−10, git-data 60+180−10. inngest-consumer departs from the
# formula deliberately — see its own block below and the 2026-08-20 amendment to ADR-117.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-1"]' 'web-zot-consumer (web-1)' 230 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-1"]'    'web-nic-guard (web-1)'    470 || rc=1
# (#6459/ADR-143) web-2's per-host heartbeats are born `paused` (web-probe.tf
# ignore_changes=[paused]) exactly like web-1's; the ONLY unpause path is this gate, so they
# MUST be armed here or web2-standby-soak-6459.sh reads them `paused` and false-FAILs a healthy
# web-2 as a DARK host (#6459 could never close). arm_one no-ops (return 0) when the address is
# absent from tfstate, so this is inert on any apply path that has not yet created web-2.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-2"]' 'web-zot-consumer (web-2)' 230 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-2"]'    'web-nic-guard (web-2)'    470 || rc=1
# Measured absent from the merge-path tfstate (run 32360734255, 2026-08-20: "git-data-prd: not
# present in tfstate"), so today this arm returns in milliseconds. It is still a live call site
# and still counts toward the step's wall-clock ceiling, which is why the budget guard sums it.
arm_one 'betteruptime_heartbeat.git_data_prd'              'git-data-prd'             230 || rc=1

# (#7228/#7587) inngest-consumer — the ONE caller that distinguishes rc=2 (see arm_one's
# terminal branch), and the ONE arm whose deadline deliberately departs from period+grace−10.
#
# Its feeder is inngest-consumer-probe.sh on web-1, which pings only after reading a NON-EMPTY
# function registry out of 10.0.1.40:8288. That host has not bound :8288 since 2026-07-30, and
# THIS CHANGE DOES NOT FIX THAT — the fix needs `apply_target=inngest-host-replace` plus a
# cutover window (#7462), so the probe is correctly SUPPRESSING and no beat can land.
#
# 230 → 30. Measured on run 32360734255: the five healthy arms complete in ~0.6 s of wall clock
# while this one arm burns ~235 s, which was 98.8% of the ARM step and 78.5% of the whole apply
# job, on EVERY merge. 30 s costs nothing on the happy path (a healthy arm answers in ~0.2 s)
# and it preserves the self-clearing property a short-circuit would destroy: arm_one still
# attempts the measurement every apply and returns 0 via `already armed (status=…)` the first
# time the monitor is live-up, so nothing here can outlive #7228 and there is no expiry
# mechanism to rot. The cost, owned rather than buried: with a 180 s feeder period against a
# 30 s window, roughly one apply in six catches the first beat, so after #7228 heals the monitor
# arms probabilistically over ~2 days at the measured 2.71 merge-applies/day. It was paused
# every day of the incident, so this is not a new dark state. The unpause window stays far below
# the monitor's first absence alert (period+grace = 240 s), so no false page is possible during
# a failed attempt.
ARM_INNGEST_DEADLINE=30
arc=0
arm_one 'betteruptime_heartbeat.inngest_consumer' 'inngest-consumer (web-1)' "$ARM_INNGEST_DEADLINE" || arc=$?
if [[ "$arc" -eq 2 ]]; then
  # This message is NOT the pre-#7587 one, and the rewrite is the point. That text hard-coded
  # "230s", and it instructed the reader that a sighting after #7228 closes means "the probe or
  # the private-net path is broken". Against a 30 s window and a 180 s period a HEALTHY feeder
  # produces this warning roughly five runs in six, so the old instruction would send an
  # operator to debug a surface that is working. What replaces it is the two observed fields
  # that actually discriminate: `status` (a heartbeat that has never received a beat since the
  # unpause reads `pending`; one that beat and then lapsed reads `down`) and the monitor's own
  # `updated_at` as Better Stack reports it.
  echo "::warning::inngest-consumer: no beat within ${ARM_INNGEST_DEADLINE}s (elapsed ${ARM_ELAPSED}s); monitor rolled back to paused. Observed at rollback: status=${ARM_LAST_STATUS:-unknown} updated_at=${ARM_LAST_UPDATED_AT:-unreported}. This arm polls for ${ARM_INNGEST_DEADLINE}s against a 180s feeder period, so a HEALTHY feeder misses roughly five windows in six — on its own this warning is not a fault. status=pending means no beat has arrived since the unpause, which is the expected state while the 10.0.1.40 bind failure (#7228) is open; any other non-up status means Better Stack saw something else and is worth reading before assuming the feeder is dark. It arms automatically on the first apply whose window catches a beat."
elif [[ "$arc" -ne 0 ]]; then
  rc=1
fi
exit "$rc"
