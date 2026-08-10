#!/usr/bin/env bash
# #6929 — DEPENDENCY follow-through: the registry host's write-shaped levers are blocked until
# the LUKS recut blocker lands.
#
# TRACKER: **#7340** (dedicated). The directive cannot live on the anchor issue itself — this
# probe closes its host issue when the anchor closes, so hosting it there would be circular.
#
# The filename keeps the 6929 suffix because the follow-through directive on #7340 names this
# path and renaming it would orphan the sweeper's lookup. The ANCHOR moved (see DEP_ISSUE
# below); the file did not.
#
# WHAT THIS EXISTS TO STOP. #7278 / ADR-172 records three actions as BLOCKED ON A PROVISIONING
# EVENT — `restart`, `push-config` and `reclaim`. Every one of them needs a change to a
# cloud-init-written file on the registry host, which needs cloud-init to re-run, which needs a
# host REPLACE — and a replace performed BEFORE the LUKS recut has been applied opens
# `/dev/mapper/registry` against a still-plaintext ext4 volume, takes the
# `refusing-non-luks-device` arm, and darks the sole pull path permanently. That is the deadlock
# ADR-172 §8 states. The condition is "the recut has not run", NOT "issue #6929 is open" — see
# the anchor note above DEP_ISSUE.
#
# Left as prose, that list ROTS. It sits in a plan, an ADR and a runbook, and nothing anywhere
# notices when the condition it is predicated on stops holding. The moment #6929 closes, the
# three blocked actions become buildable and the §Blocked-actions table becomes wrong — but only
# a human re-reading three documents would ever find out. This probe is that noticing, mechanised:
# it closes its tracker the day the recut lands, which puts the re-evaluation in front of whoever
# is sweeping instead of waiting to be remembered.
#
# TRIGGER SHAPE: **Dependency** (`Re-evaluate when #N lands`) per followthrough-convention.md.
# The canonical body for that shape is a single `gh issue view` state check, and this is it,
# expanded only for the guards the contract requires.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       the anchor issue is CLOSED — the recut has landed; re-evaluate the action set
#   2 = TRANSIENT  the anchor is still open, OR gh could not be authenticated / could not answer
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

# ANCHORED ON #7287 (the recut EXECUTION), not on #6929 (the recut VEHICLE).
#
# #6929 closed on 2026-08-09: its deliverable — the guarded `registry-luks-recut`
# workflow_dispatch — shipped in PR #6937 (merge dcae7bf1). A vehicle existing is not a
# conversion having happened. The recut has never been fired (the runbook says so verbatim:
# "This dispatch shipped with ZERO live executions"), so the volume is plausibly still
# plaintext and a replace is plausibly still fatal.
#
# Anchored on #6929 this probe would have PASSed on its first sweep after merge, announcing
# "the plaintext-volume blocker is gone" and closing #7340 — a fail-open in exactly the class
# ADR-172 was written to prevent, inside ADR-172's own follow-through. Note also that #6895,
# the issue that actually asserts "hcloud_volume.registry is plaintext ext4", is ALSO closed,
# so no issue-state anywhere encodes the posture. What does encode it is whether the recut has
# RUN: #7287 tracks firing it and is open.
#
# This is still a proxy, not a measurement. The direct signal would be a live at-rest posture
# probe, which scripts/encryption-posture-ledger.json records as
# `live_verification: "unavailable:no zot-host at-rest posture probe yet"`. Until that exists,
# an unfired recut is the closest honest anchor — and it errs toward keeping the actions
# blocked, which is the survivable direction.
DEP_ISSUE="${LUKS_BLOCKER_DEP_ISSUE:-7287}"

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
  echo "PASS: #${DEP_ISSUE} is CLOSED — the LUKS recut has been APPLIED, so a registry host"
  echo "      replace no longer opens /dev/mapper/registry against a plaintext ext4 volume."
  echo "      VERIFY BEFORE ACTING: this is a proxy for the at-rest posture, not a measurement of"
  echo "      it. Confirm the recut actually ran (a green registry-luks-recut dispatch) rather"
  echo "      than #${DEP_ISSUE} having been closed for another reason."
  echo "      Re-evaluate the three actions ADR-172 recorded as BLOCKED ON A PROVISIONING EVENT:"
  echo "        restart      — needs host execution. NOTE it is also refuted on its own merits:"
  echo "                       zot has already restarted 15,640 times into the same full volume,"
  echo "                       so 'the blocker lifted' does NOT make restart the remedy."
  echo "        push-config  — /etc/zot/config.json and the monitor scripts are cloud-init-written."
  echo "                       This is the one that unlocks the other two (keep-set, delete grant,"
  echo "                       per-path disk telemetry)."
  echo "        reclaim      — needs a 'delete' grant that no zot user holds today (measured), which"
  echo "                       is itself a push-config change; and no on-demand GC endpoint exists."
  echo "      Also re-read the recut runbook's §Related #7278 bullet and ADR-172 §Blocked actions:"
  echo "      both assert this blocker as standing, and both are now stale."
  exit 0
fi

echo "TRANSIENT: #${DEP_ISSUE} is ${state} — the blocker still stands, so restart / push-config /" >&2
echo "           reclaim remain unbuildable and this tracker stays open. Not a defect." >&2
exit 2
