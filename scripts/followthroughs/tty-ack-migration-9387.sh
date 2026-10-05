#!/usr/bin/env bash
# Follow-through for tracker #9387 (migrate the TTY-ack operator scripts to the staged approval gate).
# The tracker's re-evaluation trigger is: the staged gate has recorded a real harness-approved write in
# a run ledger AND the plugin hook has been live for two weeks. The hook went live 2026-10-02, so the
# date half falls due on 2026-10-16T00:00:00Z. This probe reports that date and nothing else.
#
# NOTIFY-ONLY: this probe never exits 0, so the sweeper never closes #9387 (closing it is the
# operator's act once the migration has landed), and it never exits 1, because the sweeper reads 1 as
# FAIL. Exit 5 repeats on every daily sweep from the deadline until the tracker stops being swept.
# Closing it is not enough: while the follow-through label is on, the sweeper keeps running the probe
# of a tracker closed as completed for up to 14 more days, so the label has to come off as well (the
# message says so).
#
# It cannot read the ledger half. The run ledger (bootstrap-runs.jsonl) lives on the founder's machine,
# not in CI, and ADR-264 says a ledger line is not evidence of approval: an agent that reads the hook
# can mint its own receipt. So the ACTION REQUIRED message asks the operator to confirm the approval
# themselves before starting.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   2 = NOT YET             the deadline has not arrived.
#   5 = ACTION REQUIRED     the deadline has arrived (the deadline second itself counts).
#   3 = CANNOT ESTABLISH    the clock or the deadline did not resolve to a plain epoch.
#
# CREDENTIAL POSTURE: none. The tracker directive declares no secrets=. The probe makes no network,
# git or file read and calls no CLI other than `date`; its only inputs are the system clock and the
# NOW_EPOCH test seam, which the sweeper's `env -i` does not forward, so the seam is inert in production.
#
# Why there is no set -e and no set -u: either one aborts with a status the probe did not choose (often
# 1), which would break the never-1 contract. Every exit below is a literal 2, 3 or 5. That holds under
# the sweeper's scrubbed environment; an exported SHELLOPTS or BASH_ENV can still change the status of
# any bash script, and the sweeper never forwards either.
#
# RETIREMENT: delete this probe, scripts/followthroughs/tty-ack-migration-9387.test.sh, the
# `run_suite "scripts/followthroughs/tty-ack-migration-9387"` line with its comment in scripts/test-all.sh,
# and its row in each of scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv (regenerate with
# `python3 scripts/regenerate-shard-manifest.py --incremental --write`), once #9387 is closed. Also
# remove the follow-through label and the soleur:followthrough directive from #9387 itself. At
# retirement re-census with `git grep tty-ack-migration`; the hits under knowledge-base/project/plans and
# knowledge-base/project/specs are the planning records for this probe and stay as history.

# C locale so [0-9] below is ASCII-only: in a UTF-8 locale it can match non-ASCII digits, and the
# comparison below would then error and silently report NOT YET.
export LC_ALL=C

DEADLINE_ISO='2026-10-16T00:00:00Z'
DEADLINE_EPOCH=$(date -u -d "$DEADLINE_ISO" +%s 2>/dev/null)
NOW="${NOW_EPOCH:-$(date -u +%s 2>/dev/null)}"
# Plain ASCII digits only, and at most 12 as a sanity cap (a 12-digit epoch is far past any real clock;
# 20 digits would wrap under base-10 conversion). Anything else is "could not measure", never a verdict.
if ! [[ "$DEADLINE_EPOCH" =~ ^[0-9]{1,12}$ && "$NOW" =~ ^[0-9]{1,12}$ ]]; then
  echo "CANNOT ESTABLISH: the clock or the deadline did not resolve to a plain epoch; the next daily sweep retries" >&2
  exit 3
fi

# 10# forces base 10: a zero-padded value such as 08 is an invalid octal literal otherwise, and the
# comparison would error and silently take the NOT YET arm.
if (( 10#$NOW >= 10#$DEADLINE_EPOCH )); then
  printf '%s\n' \
    "ACTION REQUIRED: the ${DEADLINE_ISO%%T*} re-evaluation date for #9387 has arrived. Do these in order. This probe never closes the tracker and comments again on every daily sweep until the tracker leaves the sweep (step c)." \
    "  (a) Confirm the first real harness-approved write was approved by YOU at the prompt. The run ledger (bootstrap-runs.jsonl) lives on the founder's machine, so this probe cannot read it, and ADR-264 says a ledger line is not evidence of approval: an agent that reads the hook can mint its own receipt." \
    "  (b) Only then start the migration of the TTY-ack scripts to the staged approval gate." \
    "  (c) When the migration has landed, close #9387 by hand AND remove its follow-through label: a tracker closed with the label still on can be swept for up to 14 more days."
  exit 5
fi
echo "NOT YET: the ${DEADLINE_ISO%%T*} re-evaluation date for #9387 has not arrived. (Seeing this as a tracker comment means the directive's earliest= is earlier than this date.)"
exit 2
