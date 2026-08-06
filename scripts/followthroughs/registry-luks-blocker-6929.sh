#!/usr/bin/env bash
# #6929 — DEPENDENCY follow-through: the registry host's write-shaped levers are blocked until
# the LUKS recut blocker lands.
#
# TRACKER: **#7340** (dedicated). The directive cannot live on #6929 itself — this probe closes
# its host issue when #6929 closes, so hosting it there would be circular.
#
# WHAT THIS EXISTS TO STOP. #7278 / ADR-171 records three actions as BLOCKED ON A PROVISIONING
# EVENT — `restart`, `push-config` and `reclaim`. Every one of them needs a change to a
# cloud-init-written file on the registry host, which needs cloud-init to re-run, which needs a
# host REPLACE — and a replace while #6929 is open opens `/dev/mapper/registry` against a
# still-plaintext ext4 volume, takes the `refusing-non-luks-device` arm, and darks the sole pull
# path permanently. That is the deadlock ADR-171 §8 states.
#
# Left as prose, that list ROTS. It sits in a plan, an ADR and a runbook, and nothing anywhere
# notices when the condition it is predicated on stops holding. The moment #6929 closes, the
# three blocked actions become buildable and the §Blocked-actions table becomes wrong — but only
# a human re-reading three documents would ever find out. This probe is that noticing, mechanised:
# it closes its tracker the day #6929 closes, which puts the re-evaluation in front of whoever is
# sweeping instead of waiting to be remembered.
#
# TRIGGER SHAPE: **Dependency** (`Re-evaluate when #N lands`) per followthrough-convention.md.
# The canonical body for that shape is a single `gh issue view` state check, and this is it,
# expanded only for the guards the contract requires.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       #6929 is CLOSED — the blocker is gone; re-evaluate the blocked action set
#   2 = TRANSIENT  #6929 is still open, OR gh could not be authenticated / could not answer
#   1 = FAIL       *** NEVER EMITTED ***  — an open dependency is a not-yet, never a regression.
#
# `secrets=GH_TOKEN` IS MANDATORY IN THE DIRECTIVE. The sweeper runs probes under `env -i` with
# PATH + HOME + the directive-declared secrets ONLY. On a CI runner `gh` authenticates from
# `GH_TOKEN`, never from `~/.config/gh`, so a gh-using probe with no `secrets=GH_TOKEN` is
# unauthenticated, returns transient on every sweep, and the tracker NEVER closes — a silent
# never-close, not a loud failure.
#
# The `${VAR:?msg}` guard form is banned (#6757, scripts/lint-followthrough-varq-ban.sh): it
# aborts with status 1, which this contract reads as FAIL, so an unprovisioned token would post a
# daily false-FAIL. The `[[ -z "${VAR:-}" ]]` form below is the compliant one.
set -uo pipefail

DEP_ISSUE="${LUKS_BLOCKER_DEP_ISSUE:-6929}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN is unset — gh cannot authenticate under the sweeper's env -i, so" >&2
  echo "           #${DEP_ISSUE}'s state cannot be read. Add secrets=GH_TOKEN to the directive." >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "TRANSIENT: gh is not on PATH." >&2
  exit 2
fi

# Capture, then branch. An unreadable state must never be collapsed into "still open" as though
# it had been measured (AP-021: "could not check" is not "bad") — both are exit 2 here, but the
# comment the sweeper posts has to say which one happened, or the next reader debugs the wrong
# thing.
state=$(gh issue view "$DEP_ISSUE" --json state --jq .state 2>/dev/null)
rc=$?
if [[ $rc -ne 0 || -z "$state" ]]; then
  echo "TRANSIENT: 'gh issue view ${DEP_ISSUE}' exited ${rc} or returned an empty state. This is a" >&2
  echo "           query failure, NOT a reading that the blocker is still open." >&2
  exit 2
fi

if [[ "$state" == "CLOSED" ]]; then
  echo "PASS: #${DEP_ISSUE} is CLOSED — the plaintext-volume blocker on a registry host replace is gone."
  echo "      Re-evaluate the three actions ADR-171 recorded as BLOCKED ON A PROVISIONING EVENT:"
  echo "        restart      — needs host execution. NOTE it is also refuted on its own merits:"
  echo "                       zot has already restarted 15,640 times into the same full volume,"
  echo "                       so 'the blocker lifted' does NOT make restart the remedy."
  echo "        push-config  — /etc/zot/config.json and the monitor scripts are cloud-init-written."
  echo "                       This is the one that unlocks the other two (keep-set, delete grant,"
  echo "                       per-path disk telemetry)."
  echo "        reclaim      — needs a 'delete' grant that no zot user holds today (measured), which"
  echo "                       is itself a push-config change; and no on-demand GC endpoint exists."
  echo "      Also re-read the recut runbook's §Related #7278 bullet and ADR-171 §Blocked actions:"
  echo "      both assert this blocker as standing, and both are now stale."
  exit 0
fi

echo "TRANSIENT: #${DEP_ISSUE} is ${state} — the blocker still stands, so restart / push-config /" >&2
echo "           reclaim remain unbuildable and this tracker stays open. Not a defect." >&2
exit 2
