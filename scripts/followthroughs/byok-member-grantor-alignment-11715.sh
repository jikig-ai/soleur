#!/usr/bin/env bash
# Follow-through for the BYOK member-grantor alignment tracker (filed from the PR #11715 review, CLO ruling 2026-10-31).
# NOTIFY-ONLY: the tracker is closed by a person once the RPC and the documents agree (or the documents are reworded), so this
# probe never takes exit 0 (the close verb) and never exit 1 (which would read as a regression). From the directive's `earliest=`
# date it reports ACTION REQUIRED (exit 5) every sweep; the sweeper gates the run on that date, so earlier sweeps never run it.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md (reserved codes 2/3/5).
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1
echo "ACTION REQUIRED: re-evaluate the BYOK member-grantor gap (grant_byok_delegation requires membership, DPD 2.3(w) / AUP 5.6 say Workspace Owner). Decide: owner check or revoke from authenticated, or reword the documents. Do this before the byok-delegations flag is turned on for any org beyond tenant zero."
exit 5
