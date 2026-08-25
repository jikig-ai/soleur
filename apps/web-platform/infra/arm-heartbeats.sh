#!/usr/bin/env bash
# Measured-beat ARM gate for the web-host probe heartbeats (#6438/#6548, ADR-117 automated),
# plus the `--sweep` backstop that re-pauses whatever an externally-imposed cut left live.
#
# EXTRACTED FROM `.github/workflows/apply-web-platform-infra.yml` (#7587). It used to be ~130
# lines of bash inside a YAML scalar, which nothing asserted on: `git grep arm_one` across the
# test trees returned only comments. A guard written against bash-inside-YAML can only check
# that a clock read APPEARS in the step — which a decoy `date +%s` satisfies and an equivalent
# rewrite false-REDs. As a real script it is driven behaviourally by `arm-heartbeats.test.sh`
# with a fake clock and a fake `curl` on PATH, the house shape used by
# `web-private-nic-guard.sh` + `.test.sh` and the other pairs in this directory.
#
# THE SWEEP LIVES HERE TOO (#7659). It shipped as ~45 further lines inside the sibling step's
# YAML scalar — the same shape this file's own rationale condemns, asserted the same way, with
# its own second implementation of "PATCH a heartbeat's paused flag" and its own second copy of
# the API base literal. `--sweep` is that step's body, so there is ONE `hb_patch_paused`, ONE
# `BS_API_BASE`, and the loop, the arithmetic, the summary line and the fail-not-annotate branch
# are all executed by `arm-heartbeats.test.sh` instead of string-matched.
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
# after every round-trip.
#
# THE BOUND THAT FOLLOWS IS A LOOP BOUND, AND IT IS NOT THE FUNCTION'S BOUND (#7657 D1/D2).
# Re-reading the clock bounds the POLL LOOP at `deadline + one iteration`. `arm_one` itself
# spends four further round-trips that the `elapsed` accounting never sees — the pre-loop GET,
# the pre-loop unpause PATCH, the final iteration's own GET (the part that overshoots), and the
# terminal rollback PATCH. Each is capped by `--max-time ARM_CURL_MAX_TIME_S`, so per call site:
#
#   worst-case wall clock  =  deadline + ARM_POLL_INTERVAL_S
#                             + (3 + ARM_ROLLBACK_ATTEMPTS) × ARM_CURL_MAX_TIME_S
#                          =  deadline + 85 s  at the shipped 10 / 15 / 2
#
# ADDITIVE, not a multiplier: the overhead is per CALL SITE, so it scales with the number of
# arms and not with the size of the deadlines. `Σ(deadlines) × 1.1` was the wrong shape — it
# happened to be generous for six large deadlines and would under-budget a seventh small one.
# The step ceiling in the workflow is sized against `Σ(deadline_i + 85)`; the whole ladder is
# derived, not restated, by the `ARM gate's deadlines fit its job` describe in
# `plugins/soleur/test/terraform-target-parity.test.ts`.
#
# AND IT IS WHY THE ROLLBACK RESERVE IS 40 s, NOT 10 (#7657 D5). The deadline used to be
# `period + grace − 10`, reserving one poll interval for the rollback. The real gap between the
# unpause landing and the re-pause landing is `deadline + ARM_POLL_INTERVAL_S +
# 2 × ARM_CURL_MAX_TIME_S` — the final iteration's overshoot plus the rollback PATCH — so at as
# little as 2 s of Better Stack round-trip the old formula re-paused the monitor AFTER its first
# absence alert had already fired. A false page from the gate that exists to prevent false pages.
# The reserve is now the measured worst case: `deadline = period + grace − 40`. The rollback RETRY
# does not enter this term: it fires only when the first attempt failed, and a failed PATCH did not
# re-pause anything, so it lengthens the STEP's wall clock without lengthening the LIVE window.
#
# THE ROLLBACK IS ALSO RECORDED, NOT ONLY ATTEMPTED. Every id whose `PATCH {paused:false}`
# succeeded is appended to `$ARMED_UNCONFIRMED` and removed ONLY when it reaches `up` or when a
# rollback `PATCH {paused:true}` actually returns a 2xx. Removing on "rollback attempted" would
# drop a FAILED rollback's id, so `--sweep` — the last chance to re-pause it — would never retry
# the exact monitor the `::error::` is warning about.
# There is deliberately NO `trap` (Cut List C6): bash keeps only the last EXIT handler, an
# INT/TERM handler returns and then fires EXIT too (double-PATCH), and bash defers the handler
# until the foreground `sleep` returns. The state file plus the sibling sweep step is ONE
# mechanism with ONE entry point, and it survives a step-level cancellation, which a trap
# does not.
#
# WHAT THIS FILE DOES NOT DETECT (#7658 E9, recorded rather than fixed). `$ARMED_UNCONFIRMED`
# lives in `$RUNNER_TEMP` and dies with the runner. A monitor left unpaused by an EARLIER run
# whose runner died is read by the next run's op/state gate as `already armed (status=…)` and is
# never re-paused, and the nightly `heartbeat-live-reconcile` only flags fed-but-PAUSED monitors,
# never unpaused-and-unfed ones. The only detector for that state today is the page itself.
# Closing it means re-deriving the arm set from tfstate in the sweep rather than from a state
# file; tracked, not done here.
#
# ERREXIT. The caller is a GitHub `run:` step with no `shell:` key, so GitHub invokes it as
# `/usr/bin/bash -e {0}` (ADR-170) — but this file runs as its own process under its own
# shebang, so it owns its flags. `set +e` is declared EXPLICITLY anyway rather than merely
# omitted: the difference is invisible to a reader, and the whole point of the rollback path is
# that it must not abort at the first failing PATCH. For the same reason every PATCH result is
# read as DATA (`hb_patch_paused` returns a verdict, it never aborts), and no arithmetic is
# written as a bare `(( … ))` — that exits non-zero whenever the expression evaluates to 0.
#
# CONTRACT (env in, exit code out) — also printed by `--help`:
#   BS_TOKEN            (required for --arm; may be EMPTY for --sweep, which then reports
#                       `outcome=mint-unreadable` and names the ids it could not re-pause)
#                       Better Stack API token, already ::add-mask::ed by the caller.
#   TFSTATE_JSON        (required for --arm) path to `terraform show -json` for this root.
#   ARMED_UNCONFIRMED   (required) path to the state file `--sweep` reads.
#   BS_API_BASE         (optional) Better Stack API root; overridden only by the test harness.
#   ARM_POLL_INTERVAL_S (optional) poll period, default 10; lowered only by the test harness.
#
# EXIT CODES.
#   --arm (default)
#     0 = every arm either ARMED, was a NO-OP (already live), was ABSENT from tfstate, or — for
#         the one soft call site, inngest-consumer — measured no beat and was rolled back to
#         paused, which is an assertion about the FEEDER and not about the arming.
#     1 = at least one arm could not do its job (GET failed, unpause failed, rollback failed, or
#         the status could not be read at all during the poll), OR the pre-arm contract/tfstate
#         checks refused to start.
#   --sweep
#     0 = nothing was on the books, or every id on them is now confirmed re-paused.
#     1 = at least one monitor is STILL unpaused-and-unfed (a non-2xx re-PATCH, or the token
#         could not be minted at all).
#
# `--sweep` OUTCOME VOCABULARY (the `outcome=` tag in its annotation and run-summary line):
#   noop             the state file was absent or empty — nothing was ever unpaused.
#   repaused         every id on the books returned a 2xx to `PATCH {"paused":true}`.
#   partial          at least one id did not; those monitors are live with nothing feeding them.
#   mint-unreadable  BS_TOKEN was empty, so no id could even be attempted.

set -uo pipefail
set +e   # explicit, not inherited — see ERREXIT above.

BS_TOKEN="${BS_TOKEN:-}"
TFSTATE_JSON="${TFSTATE_JSON:-}"
ARMED_UNCONFIRMED="${ARMED_UNCONFIRMED:-}"
BS_API_BASE="${BS_API_BASE:-https://uptime.betterstack.com/api/v2}"
ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-10}"
# The per-round-trip ceiling. Read by the ladder guard as well as by `curl`: it is one of the
# two terms in the per-call-site overhead above, so it may not be spelled inline.
ARM_CURL_MAX_TIME_S=15

usage() {
  sed -n '/^# CONTRACT (env in/,/^#   mint-unreadable/p' "$0" | sed 's/^# \{0,1\}//'
  echo
  echo "usage: arm-heartbeats.sh [--arm | --sweep | --help]"
}

MODE=arm
case "${1:-}" in
  ""|--arm) MODE=arm ;;
  --sweep)  MODE=sweep ;;
  -h|--help) usage; exit 0 ;;
  *) echo "::error::arm-heartbeats.sh: unknown argument '$1' (expected --arm, --sweep or --help)."; exit 1 ;;
esac

now_s() { date +%s; }

# --- the unconfirmed-arm state file -------------------------------------------------------
# One id per line. `state_add` fires immediately after a successful unpause; `state_remove`
# fires ONLY on a 2xx rollback or on reaching `up`.
state_add() {
  # An append that fails is NOT ignorable (#7658 E4): the monitor is already LIVE at this point,
  # so a silently dropped id is a monitor off the sweep's books with nothing feeding it — the
  # exact state the file exists to make impossible.
  if ! printf '%s\n' "$1" >> "$ARMED_UNCONFIRMED"; then
    echo "::error::arm-heartbeats.sh: could not record monitor $1 in ${ARMED_UNCONFIRMED} — it is UNPAUSED and OFF the re-pause sweep's books. Re-pause it by hand: Better Stack → Heartbeats → $1 → Pause."
    return 1
  fi
}
state_remove() {
  [[ -f "$ARMED_UNCONFIRMED" ]] || return 0
  local keep grc
  keep="${ARMED_UNCONFIRMED}.keep.$$"
  # `grep -vxF` exits 1 when it selects nothing, which is the ORDINARY case here (the last id
  # being removed). Exit >= 2 is grep FAILING — an unreadable source, a broken pipe, ENOSPC on
  # the redirect — and `$keep` is then empty or truncated. Installing it would silently drop
  # every OTHER id from the books, which is precisely the failure this file claims to design out
  # (#7658 E3). Never read the source file through a pipe either: a `grep -q` on a pipe takes
  # SIGPIPE on an early match under pipefail.
  grep -vxF -- "$1" "$ARMED_UNCONFIRMED" > "$keep" 2>/dev/null
  grc=$?
  if [[ "$grc" -ge 2 || ! -f "$keep" ]]; then
    rm -f "$keep"
    echo "::error::arm-heartbeats.sh: could not rewrite ${ARMED_UNCONFIRMED} (grep rc=${grc}); leaving it INTACT. The re-pause sweep will re-PATCH ${1}, which is idempotent."
    return 1
  fi
  if ! mv -f "$keep" "$ARMED_UNCONFIRMED"; then
    rm -f "$keep"
    echo "::error::arm-heartbeats.sh: could not install the rewritten ${ARMED_UNCONFIRMED}; leaving it INTACT."
    return 1
  fi
}

# --- Better Stack ---------------------------------------------------------------------------
# HB_STATUS / HB_UPDATED_AT are set by hb_fetch and read by arm_one's terminal branch.
HB_STATUS=""
HB_UPDATED_AT=""
HB_PATCH_CODE=""
# CR/LF are stripped from every vendor-controlled string before it can reach an `echo "::…"`
# (#7658 E7). `jq -r` unescapes `\n` into a real newline, so an `updated_at` containing one
# breaks out of the annotation and emits an attacker-chosen line at column 0, which the runner
# parses as a workflow command (`::error::`, `::add-mask::`, `::stop-commands::`).
# `-f` here is belt-and-braces, NOT the load-bearing check, and this is recorded because the
# review found `-f` deletable with both suites green (#7656 C4). Where it MATTERED was the old
# `hb_patch_paused`, a bare `curl` whose exit status WAS its verdict — without `-f` a rollback that
# got HTTP 500 read as success. That call now reads `%{http_code}` and does not depend on `-f` at
# all. On this GET the flag is genuinely redundant: with or without it, a 5xx yields a body with no
# `.data.attributes.status`, so the guard below fails closed either way (verified by mutation). The
# check that decides is `[[ -n "$HB_STATUS" ]]`, and deleting THAT reds the suite (row M10).
hb_fetch() {  # <id> -> 0 and sets HB_STATUS/HB_UPDATED_AT; non-zero when the lookup failed
  local body
  body=$(curl -fsS --max-time "$ARM_CURL_MAX_TIME_S" -H "Authorization: Bearer ${BS_TOKEN}" \
    "${BS_API_BASE}/heartbeats/$1" 2>/dev/null)
  # There is deliberately no separate `[[ -n "$body" ]] || return 1` here. It was in the extracted
  # original and it is unobservable: an empty or non-JSON body makes `jq` yield nothing, so the
  # `[[ -n "$HB_STATUS" ]]` guard below already fails closed on exactly the same inputs. A second
  # guard that no input can distinguish from the first is a guard that cannot be driven red
  # (#7656 C5) — the suite's T7b/T7c drive an empty 200 and a 200 with no `.status` through the
  # ONE guard that decides, and M10 proves deleting it changes the verdict.
  HB_STATUS=$(printf '%s' "$body" | jq -r '.data.attributes.status // empty' 2>/dev/null | tr -d '\r\n')
  HB_UPDATED_AT=$(printf '%s' "$body" | jq -r '.data.attributes.updated_at // "unreported"' 2>/dev/null | tr -d '\r\n')
  [[ -n "$HB_STATUS" ]] || return 1
  return 0
}
# ONE implementation, STATUS-CODE semantics (#7658 E6, #7659 F1). `curl -fsS` alone was the
# in-script predicate while the sweep read `-w '%{http_code}'`: two halves of one mechanism with
# two different success tests, and prose claiming both were "2xx". `-f` is also weaker than the
# claim — it does not reject a 3xx, and without `-L` curl does not follow one either. Reading the
# code makes "2xx" a fact rather than a paraphrase, and it makes a 5xx impossible to mistake for
# a successful rollback.
hb_patch_paused() {  # <id> <true|false> -> 0 on a 2xx; sets HB_PATCH_CODE
  HB_PATCH_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$ARM_CURL_MAX_TIME_S" \
    -X PATCH -H "Authorization: Bearer ${BS_TOKEN}" -H 'Content-Type: application/json' \
    "${BS_API_BASE}/heartbeats/$1" --data-raw "{\"paused\":$2}" 2>/dev/null)
  HB_PATCH_CODE="${HB_PATCH_CODE//[^0-9]/}"
  # curl printed nothing at all — a transport failure or a `--max-time` kill. `000` is curl's own
  # spelling for that, and naming it keeps the retry classifier below total over the status space.
  [[ -n "$HB_PATCH_CODE" ]] || HB_PATCH_CODE=000
  [[ "$HB_PATCH_CODE" =~ ^2 ]]
}

# THE ROLLBACK RETRIES ONCE, AND ONLY ON A STATUS THAT COULD SUCCEED ON A SECOND TRY (#7658 E8).
# Deviation 3 made a FAILED rollback fatal (return 1) even for the soft inngest caller, which is
# the right direction — a monitor that is unpaused with nothing feeding it is a statement about the
# ARMING, and a soft landing there would leave the apply GREEN while production uptime alerting is
# live-and-unfed. But it made a SINGLE unretried round-trip fatal, on the one arm that can never
# take the no-op branch while #7228 is open: at 2.71 merge-applies/day that is ~990 rollback
# PATCHes a year, every one of them able to red a routine apply and raise a false ops alarm on one
# lost packet. The vendor's error rate is UNVERIFIED — this repo holds no measurement of it — so
# the cost is stated as a sensitivity: p = 0.1 % → ~1 false red/yr, p = 0.5 % → ~5, p = 1 % → ~10.
#
# One immediate retry, no backoff: `--max-time` already bounds each attempt, the failure mode being
# covered is a lost round-trip rather than a busy server, and every extra attempt is a term the
# step's wall-clock ceiling has to carry (the ladder budgets `ARM_ROLLBACK_ATTEMPTS` explicitly).
# A 4xx is NOT retried — a 401/403/404 does not fix itself on a second immediate call, and burning
# the budget on it delays the `::error::` the operator needs.
#
# The sweep deliberately does NOT layer a second retry on top of this: it IS the next attempt, it
# runs seconds later on the same id, and its own failure is reported as `outcome=partial` rather
# than swallowed.
ARM_ROLLBACK_ATTEMPTS=2
hb_rollback() {  # <id> <label> -> 0 once the monitor is confirmed paused
  local id="$1" label="$2" attempt=1
  while true; do
    hb_patch_paused "$id" true && return 0
    [[ "$attempt" -lt "$ARM_ROLLBACK_ATTEMPTS" ]] || return 1
    case "$HB_PATCH_CODE" in
      5*|000) ;;
      *) return 1 ;;
    esac
    echo "::warning::${label}: rollback PATCH paused=true returned HTTP ${HB_PATCH_CODE} — retrying once before treating the monitor as still live."
    attempt=$(( attempt + 1 ))
  done
}

# =================================================================================================
# --sweep — the rollback that survives a cancellation (#7587)
# =================================================================================================
# `arm_one` rolls a monitor back to `paused` on its own terminal branch. That line is unreachable
# on an EXTERNALLY-IMPOSED cut — a step timeout, a job timeout, a cancel — and on those paths a
# heartbeat is left unpaused with nothing feeding it, so it pages on absence at whatever hour its
# grace window expires. This is the backstop, invoked from a sibling step gated `if: always()`.
sweep_main() {
  local armed repaused failed outcome ids id rc
  if [[ ! -s "$ARMED_UNCONFIRMED" ]]; then
    # The modal case by a wide margin: an apply that never unpaused anything. Reported rather
    # than silent, so `outcome=` has a value on EVERY run and the email can tell "the sweep found
    # nothing to do" apart from "the sweep did not run".
    sweep_report 0 0 0 noop
    return 0
  fi
  armed=$(grep -c '' "$ARMED_UNCONFIRMED" 2>/dev/null || echo 0)
  ids=$(tr '\n' ' ' < "$ARMED_UNCONFIRMED" 2>/dev/null | sed 's/ *$//')
  echo "::warning::Heartbeat re-pause sweep FIRED: ${armed} monitor(s) were left unpaused-and-unconfirmed by the ARM gate (${ids}). Production uptime alerting for them was live with nothing feeding it."

  if [[ -z "$BS_TOKEN" ]]; then
    # The ids, not just the count (#7655 B3). They are the only thing that lets an operator
    # re-pause by hand, and this branch exits before the loop that would otherwise echo them.
    echo "::error::Re-pause sweep: no Better Stack API token — ${armed} monitor(s) are LIVE AND UNFED and this step cannot re-pause them: ${ids}. Re-pause each by hand: Better Stack → Heartbeats → the id → Pause. They will page when their grace window expires."
    sweep_report "$armed" 0 "$armed" mint-unreadable
    return 1
  fi

  repaused=0
  failed=0
  # Read the state file directly, never through a pipe: under `pipefail` a producer that takes
  # SIGPIPE turns a correct read into a non-zero pipeline.
  while read -r id; do
    [[ -n "$id" ]] || continue
    # Idempotent: re-PATCHing `paused:true` on an already-paused monitor is a no-op, which is
    # what lets this run after the ARM step has already cleared some ids.
    if hb_patch_paused "$id" true; then
      repaused=$(( repaused + 1 ))
      echo "re-paused heartbeat ${id} (HTTP ${HB_PATCH_CODE})"
    else
      failed=$(( failed + 1 ))
      echo "::error::Re-pause sweep: PATCH {\"paused\":true} for heartbeat ${id} returned HTTP ${HB_PATCH_CODE:-000} — it is STILL unpaused-and-unfed."
    fi
  done < "$ARMED_UNCONFIRMED"

  outcome=repaused
  rc=0
  if [[ "$failed" -gt 0 ]]; then
    outcome=partial
    rc=1
  fi
  sweep_report "$armed" "$repaused" "$failed" "$outcome"

  # FAIL, do not merely annotate. `::error::` does not fail a step, and every path that leaves
  # this file non-empty already reds the apply job — so an annotating sweep would only ever
  # soften a red, never create one. What it MUST not do is stay green on the one path where it
  # could not finish the job: a still-unpaused monitor has to keep the run non-green so
  # `notify-apply-failure` fires and the operator is emailed.
  if [[ "$failed" -gt 0 ]]; then
    echo "::error::Re-pause sweep could not re-pause ${failed} of ${armed} monitor(s). They are live with nothing feeding them and will page on absence."
    return 1
  fi
  if [[ "$armed" -gt 0 ]]; then
    echo "::warning::Heartbeat re-pause sweep re-paused ${repaused} of ${armed} monitor(s). Uptime alerting for them is PAUSED until the next apply arms them; the previously-applied infrastructure is unaffected."
  fi
  return "$rc"
}

# The structured line goes to an ANNOTATION first and the run summary second (#7659 F2).
# `$GITHUB_STEP_SUMMARY` has NO REST API — this repo has already been burned by reading a field
# that cannot say otherwise (#7307, knowledge-base/project/learnings/2026-08-09-the-monitor-
# reported-success-and-i-read-the-field-that-cannot-say-otherwise.md) — so a summary-only tag is
# human-only, readable exactly by opening the run's web page. `::notice::` annotations ARE
# retrievable: `gh api repos/{o}/{r}/check-runs/<job-id>/annotations`.
sweep_report() {  # <armed> <repaused> <failed> <outcome>
  echo "::notice::heartbeat-repause-sweep armed=$1 repaused=$2 failed=$3 outcome=$4"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  { echo "### Heartbeat re-pause sweep"; echo; echo "armed=$1 repaused=$2 failed=$3 outcome=$4"; } >> "$GITHUB_STEP_SUMMARY"
}

if [[ "$MODE" == "sweep" ]]; then
  if [[ -z "$ARMED_UNCONFIRMED" ]]; then
    echo "::error::arm-heartbeats.sh --sweep: ARMED_UNCONFIRMED is unset — refusing to run a half-configured sweep."
    exit 1
  fi
  sweep_main
  exit $?
fi

# =================================================================================================
# --arm (default)
# =================================================================================================

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
# READABLE IS NOT THE SAME AS POPULATED (#7658 E10). A readable `{}` — a `terraform show -json`
# that failed soft, a truncated write, the wrong root — makes every `jq` lookup return empty, so
# all six arms report "not present in tfstate" and the gate exits 0 having armed NOTHING, with no
# error channel fired. A state with zero resources is never a legitimate input to this step.
_resource_count=$(jq -r '[.values.root_module.resources[]?] | length' "$TFSTATE_JSON" 2>/dev/null)
if [[ ! "$_resource_count" =~ ^[0-9]+$ || "$_resource_count" -eq 0 ]]; then
  echo "::error::arm-heartbeats.sh: TFSTATE_JSON=${TFSTATE_JSON} is readable but holds no resources — a contentless state would silently 'skip' every arm and exit green. Refusing."
  exit 1
fi

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
  local id started elapsed reads_ok
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
  if [[ "$HB_STATUS" != "paused" ]]; then
    echo "${label}: already armed (status=${HB_STATUS}) — no-op."
    return 0
  fi
  echo "${label}: monitor ${id} is paused; unpausing and watching for a real beat (status→up, deadline=${deadline}s)…"
  if ! hb_patch_paused "$id" false; then
    echo "::error::${label}: PATCH paused=false FAILED (HTTP ${HB_PATCH_CODE:-000}) — cannot begin arming."
    return 1
  fi
  # The id is on the sweep's books from the instant the monitor is live, not from the instant
  # we decide to give up: everything between those two points is exactly the window in which an
  # externally-imposed cut leaves it unpaused-and-unfed.
  state_add "$id"
  started=$(now_s)
  elapsed=0
  reads_ok=0
  while [[ "$elapsed" -lt "$deadline" ]]; do
    sleep "$ARM_POLL_INTERVAL_S"
    if hb_fetch "$id"; then
      ARM_LAST_STATUS="$HB_STATUS"
      ARM_LAST_UPDATED_AT="$HB_UPDATED_AT"
      reads_ok=$(( reads_ok + 1 ))
    else
      # NEVER carry the PRE-UNPAUSE reading forward (#7658 E1). The seed value was `paused`, and
      # at rollback the monitor is unpaused — so a stale carry makes the terminal message report
      # `status=paused` as an observation, which is affirmatively false, and makes a total loss
      # of Better Stack visibility render as a benign feeder miss.
      ARM_LAST_STATUS=""
      ARM_LAST_UPDATED_AT=""
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
  #
  # NEITHER is a poll that never read a status at all. rc=2 asserts something about the feeder,
  # and no such assertion is available when every in-loop GET failed (#7658 E1) — that is a loss
  # of vendor visibility, i.e. the gate could not do its job, so it returns 1.
  if ! hb_rollback "$id" "$label"; then
    echo "::error::${label}: rollback PATCH paused=true FAILED (HTTP ${HB_PATCH_CODE:-000}) after ${ARM_ROLLBACK_ATTEMPTS} attempt(s) — monitor ${id} is unpaused-and-unfed. Left on the re-pause sweep's books; investigate immediately."
    echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (last status=${ARM_LAST_STATUS:-unknown})."
    return 1
  fi
  state_remove "$id"
  if [[ "$reads_ok" -eq 0 ]]; then
    echo "::error::${label}: every status read during the ${deadline}s poll FAILED — the monitor was unpaused, could not be observed at all, and has been rolled back to paused. This is a loss of Better Stack visibility, NOT a verdict about the feeder."
    return 1
  fi
  echo "::error::${label}: status never reached 'up' within ${elapsed}s of a ${deadline}s deadline (probe timer never pinged) — ROLLED BACK to paused. A green-but-inert monitor is the #6400 shape this gate exists to prevent. Investigate: is the web-1 timer installed + the private-net path healthy?"
  return 2
}

rc=0
# deadline = period + grace − 40, where 40 = ARM_POLL_INTERVAL_S + 2 × ARM_CURL_MAX_TIME_S is the
# worst-case gap between the poll loop's last clock read and the rollback PATCH landing (#7657
# D5; the old reserve of 10 re-paused AFTER the first absence alert at ≥2 s of vendor latency).
# zot 180+60−40, nic-guard 360+120−40, git-data 60+180−40. inngest-consumer departs from the
# formula deliberately — see its own block below and the 2026-08-20 amendment to ADR-117.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-1"]' 'web-zot-consumer (web-1)' 200 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-1"]'    'web-nic-guard (web-1)'    440 || rc=1
# (#6459/ADR-143) web-2's per-host heartbeats are born `paused` (web-probe.tf
# ignore_changes=[paused]) exactly like web-1's; the ONLY unpause path is this gate, so they
# MUST be armed here or web2-standby-soak-6459.sh reads them `paused` and false-FAILs a healthy
# web-2 as a DARK host (#6459 could never close). arm_one no-ops (return 0) when the address is
# absent from tfstate, so this is inert on any apply path that has not yet created web-2.
arm_one 'betteruptime_heartbeat.web_zot_consumer["web-2"]' 'web-zot-consumer (web-2)' 200 || rc=1
arm_one 'betteruptime_heartbeat.web_nic_guard["web-2"]'    'web-nic-guard (web-2)'    440 || rc=1
# Measured absent from the merge-path tfstate (run 32360734255, 2026-08-20: "git-data-prd: not
# present in tfstate"), so today this arm returns in milliseconds. It is still a live call site
# and still counts toward the step's wall-clock ceiling, which is why the budget guard sums it.
arm_one 'betteruptime_heartbeat.git_data_prd'              'git-data-prd'             200 || rc=1

# (#7228/#7587) inngest-consumer — the ONE caller that distinguishes rc=2 (see arm_one's
# terminal branch), and the ONE arm whose deadline deliberately departs from period+grace−40.
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
# mechanism to rot.
#
# THE COST, OWNED RATHER THAN BURIED, INCLUDING THE TAIL (#7657 D7). With a 180 s feeder period
# against a 30 s window, an attempt catches the first beat with p = 30/180 = 1/6, and attempts
# are independent, so the number of applies to arm is geometric. At the measured 2.71
# merge-applies/day: MEAN 6 attempts ≈ 2.2 days, MEDIAN 1.5 days, **p95 17 attempts ≈ 6.3 days**,
# p99 ≈ 9.6 days, and **P(still unarmed after 2 days) = (5/6)^5.4 ≈ 37 %**. Quoting only the mean
# of a geometric buries the half that matters. It was paused every day of the incident, so this
# is not a new dark state, but it IS a multi-day blind window rather than a same-apply re-arm.
# UNVERIFIED rider: p = 1/6 assumes Better Stack's `status` flips to `up` the moment a beat is
# received. If propagation lags by L, effective p is (30 − L)/180 — at L = 10 s that is 1/9, mean
# 3.3 d, p95 9.4 d. This change measured no such semantics.
#
# The unpause window stays far below the monitor's first absence alert: worst case is
# 30 + ARM_POLL_INTERVAL_S + 2 × ARM_CURL_MAX_TIME_S = 70 s against period+grace = 240 s, so no
# false page is possible during a failed attempt.
ARM_INNGEST_DEADLINE=30
arc=0
arm_one 'betteruptime_heartbeat.inngest_consumer' 'inngest-consumer (web-1)' "$ARM_INNGEST_DEADLINE" || arc=$?
if [[ "$arc" -eq 2 ]]; then
  # This message is NOT the pre-#7587 one, and the rewrite is the point. That text hard-coded
  # "230s", and it instructed the reader that a sighting after #7228 closes means "the probe or
  # the private-net path is broken". Against a 30 s window and a 180 s period a HEALTHY feeder
  # produces this warning roughly five runs in six, so the old instruction would send an
  # operator to debug a surface that is working. What replaces it is the status Better Stack
  # reported at rollback — the value actually observed, never a carried-forward pre-unpause
  # reading (#7658 E1), and `unknown` when the read itself failed.
  #
  # `updated_at` is reported but NOT claimed as a discriminator (#7658 E2). The retracted claim
  # was that status and updated_at together "separate 'the feeder never beat' from 'a beat was
  # simply not due inside our window'". This file's own header records the repo's verified
  # position — `updated_at` is a record-mutation timestamp and does NOT move when a beat arrives
  # while paused — and this script PATCHes that same record ~30 s before reading the field, so
  # the most plausible reading of any movement is OUR OWN unpause. Asserting a property of the
  # PAIR that we have not measured of either member is the same defect class this branch already
  # retracted once in 01ab1e3c4.
  echo "::warning::inngest-consumer: no beat within ${ARM_INNGEST_DEADLINE}s (elapsed ${ARM_ELAPSED}s); monitor rolled back to paused. Better Stack reported status=${ARM_LAST_STATUS:-unknown} at rollback (updated_at=${ARM_LAST_UPDATED_AT:-unreported}; that field is a record-mutation timestamp and this run PATCHed the record, so do not read a beat into it). This arm polls for ${ARM_INNGEST_DEADLINE}s against a 180s feeder period, so a HEALTHY feeder misses roughly five windows in six — on its own this warning is not a fault. While the 10.0.1.40 bind failure (#7228) is open no beat can land at all, so seeing this every apply is the expected reading. It arms automatically on the first apply whose window catches a beat."
elif [[ "$arc" -ne 0 ]]; then
  rc=1
fi
exit "$rc"
