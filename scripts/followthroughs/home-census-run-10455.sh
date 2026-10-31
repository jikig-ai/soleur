#!/usr/bin/env bash
# (#10455) Notify-only reminder that the production-HOME census may now be run.
#
# NOTIFY-ONLY: this probe can never close its tracker, so it never exits 0 (the close verb) and never exits 1.
# Exit codes: 2 = NOT YET (before `earliest`), 3 = CANNOT ESTABLISH (no usable clock), 5 = ACTION REQUIRED
# (the earliest time has passed; a session must run the census under the conditions in the runbook).
#
# CREDENTIAL POSTURE: none. It reads no secret, calls no network endpoint, runs no census, and reads no HOME. The
# sweeper republishes this output near-verbatim into a public comment, so it prints only the constant preflight
# command and a pointer to the runbook, never a count, a build, an uptime or a result.
#
# The real run needs the CLO's C8 DISCHARGED comment, a mature container (24 h of uptime) and the two-run cap; the
# trigger script enforces them. See knowledge-base/engineering/operations/runbooks/home-census.md.
#
# RETIREMENT: delete with the route (#11714), together with
#   scripts/followthroughs/home-census-run-10455.test.sh   (delete)
#   scripts/test-all.sh                                    (drop the run_suite line)
#   apps/web-platform/scripts/home-census-trigger.sh and its tests (deleted by #11714)
set -uo pipefail

CLOCK="${SOLEUR_FT_EARLIEST:-}"
if [[ ! "$CLOCK" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "CANNOT ESTABLISH: no canonical earliest time (SOLEUR_FT_EARLIEST)." >&2
  exit 3
fi
EARLIEST_EPOCH="$(date -u -d "$CLOCK" +%s 2>/dev/null)" || { echo "CANNOT ESTABLISH: the earliest time is not parseable." >&2; exit 3; }
NOW_EPOCH="${HOME_CENSUS_PROBE_NOW:-$(date -u +%s)}"
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || { echo "CANNOT ESTABLISH: no usable clock." >&2; exit 3; }

if (( NOW_EPOCH < EARLIEST_EPOCH )); then
  echo "NOT YET: the earliest time for the home census has not passed."
  exit 2
fi
echo "ACTION REQUIRED: the home census can now be considered. Start with the preflight, then follow the runbook:"
echo "  bash apps/web-platform/scripts/home-census-trigger.sh --mode dry_run --run-id <N>"
echo "  runbook: knowledge-base/engineering/operations/runbooks/home-census.md"
exit 5
