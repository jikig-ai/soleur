#!/usr/bin/env bash
# Follow-through probe: arm-token revisit (tracker #12229, Ref #9927, Ref #12158).
#
# NOTIFY-ONLY. The 2026-11-06 owner decision keeps the standing read/write arm token
# (doppler_service_token.inngest_arm_write) and sets a revisit at the next host replace or
# 2027-01-08, whichever is first. This probe is the date half of that revisit: from 2027-01-08
# (the tracker's earliest=) the sweeper runs it daily, and it stays loud while the token is
# still in config.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   2 = NOT YET / targets gone  (none of the three members is in config)
#   3 = CANNOT ESTABLISH        (a tracked file could not be read)
#   5 = ACTION REQUIRED         (any member is still in config: the revisit decision is owed)
#   (78 under xtrace: the refusal below.) This probe NEVER exits 0 or 1: it must not close the tracker (revocation and the recorded
#   decision are human acts) and it must not read as a failure of the sweep.
#
# Members (a probe that stops at the first one is the defect; removing the -target lines alone
# does not revoke, so the declaration counts too):
#   1. a non-comment line carrying  -target=doppler_service_token.inngest_arm_write
#   2. a non-comment line carrying  -target=github_actions_secret.doppler_token_inngest_arm
#      (both in .github/workflows/apply-web-platform-infra.yml; the name must end at a boundary, so
#      a longer name such as ..._v2 is not a member; quoted and space forms count)
#   3. the declaration  resource "doppler_service_token" "inngest_arm_write"
#      (in apps/web-platform/infra/inngest-arm-write-token.tf)
# Comment lines are not members.
#
# Credential posture: none. It reads two tracked files; there is no secrets= clause, no network
# and no gh call.
#
# Residuals (stated in the tracker body too): it measures config, not Doppler, so a destroy that
# was never applied is carried by #12158 step 4 and by the owner; the "next host replace" half of
# the trigger is carried by #12158 step 4 and by prose only; revocation stays a human act.
#
# RETIREMENT: when the arm token is revoked and this tracker is closed, delete every site together:
#   scripts/followthroughs/arm-token-revisit-12229.sh (this file),
#   scripts/followthroughs/arm-token-revisit-12229.test.sh, the run_suite line in scripts/test-all.sh,
#   the rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv (the affected-set edge is
#   derived from the file names, so there is no declared registration), and the directive in the tracker body.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# Test-only override of the two file paths; the sweeper runs probes under env -i, so it is unset there.
WF="${ARM_TOKEN_REVISIT_WORKFLOW:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"
TF="${ARM_TOKEN_REVISIT_TF:-$ROOT/apps/web-platform/infra/inngest-arm-write-token.tf}"

m1=0; m2=0; m3=0

if [ ! -f "$WF" ] || [ ! -r "$WF" ] || [ ! -s "$WF" ]; then
  echo "CANNOT ESTABLISH: the apply workflow could not be read"
  exit 3
fi
if [ ! -f "$TF" ] || [ ! -r "$TF" ] || [ ! -s "$TF" ]; then
  echo "CANNOT ESTABLISH: the arm-token Terraform file could not be read"
  exit 3
fi

wf_text="$(tr -d '\r' < "$WF")" || { echo "CANNOT ESTABLISH: the apply workflow could not be read"; exit 3; }
tf_text="$(tr -d '\r' < "$TF")" || { echo "CANNOT ESTABLISH: the arm-token Terraform file could not be read"; exit 3; }

has() { # text regex -> 0 present, 1 absent (comment lines are not members)
  local body
  body="$(grep -vE '^[[:space:]]*#' <<<"$1")"
  grep -qE -- "$2" <<<"$body"
}

has "$wf_text" '-target[= ]["'"'"']?doppler_service_token\.inngest_arm_write(["'"'"'[:space:]\\;]|$)'; rc=$?
if [ "$rc" -eq 0 ]; then m1=1; elif [ "$rc" -ne 1 ]; then echo "CANNOT ESTABLISH: member 1 could not be searched"; exit 3; fi

has "$wf_text" '-target[= ]["'"'"']?github_actions_secret\.doppler_token_inngest_arm(["'"'"'[:space:]\\;]|$)'; rc=$?
if [ "$rc" -eq 0 ]; then m2=1; elif [ "$rc" -ne 1 ]; then echo "CANNOT ESTABLISH: member 2 could not be searched"; exit 3; fi

has "$tf_text" '^[[:space:]]*resource[[:space:]]+"doppler_service_token"[[:space:]]+"inngest_arm_write"'; rc=$?
if [ "$rc" -eq 0 ]; then m3=1; elif [ "$rc" -ne 1 ]; then echo "CANNOT ESTABLISH: member 3 could not be searched"; exit 3; fi

if [ $((m1 + m2 + m3)) -eq 0 ]; then
  echo "NOT YET: arm-token targets gone from config (token -target line, secret -target line, resource declaration all absent). Record the decision on #12158, then close this tracker and remove its label. A destroy never applied is not seen by this probe."
  exit 2
fi

echo "ACTION REQUIRED: the arm-token revisit is due and the token is still in config (token -target line: $m1, secret -target line: $m2, resource declaration: $m3). Record the decision on #12158: revoke with its change linked, or keep with a new date at most 90 days out and a freshly enrolled tracker. Revoke only if the four preconditions in arm-token-replacement-design-12158.md (The revisit question) hold; otherwise keep with a new date."
exit 5
