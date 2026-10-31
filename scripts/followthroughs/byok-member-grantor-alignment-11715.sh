#!/usr/bin/env bash
# Follow-through for the BYOK member-grantor alignment tracker (filed from the PR #11715 review, CLO ruling 2026-10-31).
# NOTIFY-ONLY: the tracker is closed by a person once the RPC and the documents agree (or the documents are reworded), so this
# probe never takes exit 0 (the close verb) and never exit 1 (which would read as a regression). From the directive's `earliest=`
# date it reports ACTION REQUIRED (exit 5) every sweep; the sweeper gates the run on that date, so earlier sweeps never run it.
# Cost, accepted: the sweeper comments on every non-0/1 verdict with no dedup (about one comment per sweep from 2026-12-01 until
# the tracker is dealt with). End it by closing the tracker AND removing its `follow-through` label: the sweeper's closed-set arm
# keeps running the probe of a tracker closed as completed while the label is on. The body is one `echo; exit 5`, so the
# never-0/never-1 contract holds by inspection and no suite or rc-remapping trap is carried.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md (reserved codes 2/3/5).
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1
echo "ACTION REQUIRED: re-evaluate the BYOK member-grantor gap (grant_byok_delegation requires membership, DPD 2.3(w) / AUP 5.6 say Workspace Owner). Decide: owner check or revoke from authenticated, or reword the documents. Do this before the byok-delegations flag is turned on for any org beyond tenant zero."
exit 5
