#!/usr/bin/env bash
# Follow-through probe: inngest write-token revisit (tracker #12738, Ref #9927, Ref #12158).
#
# NOTIFY-ONLY. The #12158 step D2-2 build adds a SECOND standing read/write credential on
# soleur-inngest/prd — doppler_service_token.inngest_cutover_write (Doppler name
# inngest-cutover-write), delivered as the inngest-cutover environment secret
# DOPPLER_TOKEN_INNGEST_CUTOVER_WRITE. The arm-token probe (arm-token-revisit-12229.sh)
# watches only the arm token; this probe is the new token's own revisit coverage, date-only
# like its sibling: from 2027-01-08 (the tracker's earliest=, the same revisit point as
# #12229) the sweeper runs it daily, and it stays loud while the token is still in config.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   2 = NOT YET / targets gone  (none of the two members is in config)
#   3 = CANNOT ESTABLISH        (a tracked file could not be read)
#   5 = ACTION REQUIRED         (any member is still in config: the revisit decision is owed)
#   (78 under xtrace: the refusal below.) This probe NEVER exits 0 or 1: it must not close
#   the tracker (a keep or revoke decision is a human act) and it must not read as a failure
#   of the sweep.
#
# Members (a probe that stops at the first one is the defect; removing the -target line alone
# does not revoke, so the declaration counts too):
#   1. a non-comment line carrying  -target=doppler_service_token.inngest_cutover_write
#      (in .github/workflows/apply-web-platform-infra.yml; shell line continuations are joined
#      first; the name must end at any character outside [A-Za-z0-9_-], so a longer name such
#      as ..._v2 is not a member; inline, quoted, tab/space-separated and array forms count)
#   2. the declaration  resource "doppler_service_token" "inngest_cutover_write"
#      (in apps/web-platform/infra/inngest-arm-write-token.tf)
# Comment lines are not members. Known and accepted: a non-comment mention of a -target string
# (an echo, a YAML description) still counts, and an HCL block comment around the declaration
# still counts; both fail toward "notify", the safe direction.
#
# Credential posture: none. It reads two tracked files; there is no secrets= clause, no
# network and no gh call.
#
# Residuals (stated in the tracker body too): it measures config, not Doppler, so a destroy
# that was never applied is carried by #12158 and by the owner; the environment secret's
# presence on GitHub is not measured either (D1c's revoke note carries its deletion);
# revocation stays a human act.
#
# RETIREMENT: when the recorded decision on #12158 retires this token (or accepts it
# permanently), delete every site together:
#   scripts/followthroughs/inngest-write-token-revisit-12738.sh (this file),
#   scripts/followthroughs/inngest-write-token-revisit-12738.test.sh, the run_suite line in
#   scripts/test-all.sh, the rows in scripts/suite-shard-legs.tsv and
#   scripts/suite-durations.tsv (the affected-set edge is derived from the file names, so
#   there is no declared registration), and the directive in the tracker body.
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
WF="${INNGEST_WRITE_TOKEN_REVISIT_WORKFLOW:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"
TF="${INNGEST_WRITE_TOKEN_REVISIT_TF:-$ROOT/apps/web-platform/infra/inngest-arm-write-token.tf}"

m1=0; m2=0

if [ ! -f "$WF" ] || [ ! -r "$WF" ] || [ ! -s "$WF" ]; then
  echo "CANNOT ESTABLISH: the apply workflow could not be read"
  exit 3
fi
if [ ! -f "$TF" ] || [ ! -r "$TF" ] || [ ! -s "$TF" ]; then
  echo "CANNOT ESTABLISH: the arm-token Terraform file could not be read"
  exit 3
fi

wf_text="$(tr -d '\r' < "$WF" | { grep -vE '^[[:space:]]*#' || true; } | sed -e ':a;/\\$/{N;s/\\\n[[:space:]]*/ /;ba}')" || { echo "CANNOT ESTABLISH: the apply workflow could not be read"; exit 3; }
tf_text="$(tr -d '\r' < "$TF")" || { echo "CANNOT ESTABLISH: the arm-token Terraform file could not be read"; exit 3; }

has() { # text regex -> 0 present, 1 absent (comment lines are not members)
  local body
  body="$(grep -vE '^[[:space:]]*#' <<<"$1")"
  grep -qE -- "$2" <<<"$body"
}

T1=$'-target[=[:space:]]+[\\"\']?doppler_service_token\\.inngest_cutover_write([^[:alnum:]_-]|$)'
has "$wf_text" "$T1"; rc=$?
if [ "$rc" -eq 0 ]; then m1=1; elif [ "$rc" -ne 1 ]; then echo "CANNOT ESTABLISH: member 1 could not be searched"; exit 3; fi

has "$tf_text" '^[[:space:]]*resource[[:space:]]+"doppler_service_token"[[:space:]]+"inngest_cutover_write"'; rc=$?
if [ "$rc" -eq 0 ]; then m2=1; elif [ "$rc" -ne 1 ]; then echo "CANNOT ESTABLISH: member 2 could not be searched"; exit 3; fi

if [ $((m1 + m2)) -eq 0 ]; then
  echo "NOT YET: inngest write-token targets gone from config (token -target line and resource declaration both absent). Record the decision on #12158, then close this tracker and remove its label. A destroy never applied, and the inngest-cutover environment secret on GitHub, are not seen by this probe."
  exit 2
fi

echo "ACTION REQUIRED: the inngest write-token revisit is due and the token is still in config (token -target line: $m1, resource declaration: $m2). Record the decision on #12158: keep, or revoke per the D1c note in arm-token-replacement-design-12158 (remove the resource, its -target line, the credential step and the census name, then an owner-gated destroy or doppler configs tokens revoke, plus deletion of the inngest-cutover environment secret). Revocation stays a human act."
exit 5
