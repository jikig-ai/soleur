#!/usr/bin/env bash
# Follow-through verification for the #7431 ledger flip — reconcile against the real invoice.
#
# WHY THIS CANNOT BE AUTOMATED, STATED HONESTLY. Every figure in the flip is CATALOG-derived, from
# the Hetzner API's `/v1/server_types`. The API returns IDENTICAL `net` and `gross` for this
# account, so `cpx22 EUR 19.49 - cx23 EUR 5.49 = +EUR 14.00/mo` is arithmetic on those values and
# NOT a VAT-adjusted quote. Only the invoice settles what is actually drawn, and the invoice
# arrives by email to ops@ — there is no billing API in scope here. So this is the sanctioned
# operator-confirmed pattern from ship/SKILL.md §3.5.B: the SCRIPT reads the human's verdict from
# an issue comment; the human does not read a dashboard on the script's behalf.
#
# That distinction is the whole point of the pattern. `hr-no-dashboard-eyeball-pull-data-yourself`
# forbids "operator looks at a thing and decides"; it does not forbid "operator supplies a fact
# only they can obtain, mechanically". This is the latter.
#
# WHAT THE OPERATOR MUST CONFIRM (all three, or it is not a reconciliation):
#   1. the invoice line for `soleur-registry` bills the cpx22 rate from 2026-08-10, not cx23;
#   2. the delta against the prior month is ~EUR 14.00 for this host (state the actual figure);
#   3. whether VAT changes the picture — if gross != net on the invoice, the ledger's caveat was
#      right and both expenses.md and cost-model.md need the corrected basis.
#
# Then comment on the issue with a line of its own:
#     RESULT: PASS   <actual figure, and any VAT correction>
#   or
#     RESULT: FAIL   <what the invoice actually shows>
#
# A bare "looks right" is not accepted — the grep is anchored, deliberately, because a
# reconciliation whose evidence is not written down is indistinguishable from one nobody did.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       an anchored `RESULT: PASS` comment exists
#   1 = FAIL       an anchored `RESULT: FAIL` comment exists — the ledger overstates or understates
#   * = TRANSIENT  no verdict comment yet (the invoice has not arrived, or nobody has read it),
#                  or the GitHub API was unreachable. NOT a pass.
#
# Required env: GH_TOKEN (declare `secrets=GH_TOKEN` in the directive — the sweeper's env -i
#   sandbox strips everything not named, and a gh probe without it is unauthenticated and would
#   never close).
#
# Anchoring note: the verdict regex is `^RESULT: (PASS|FAIL)\b`, anchored at the start of a line
# but NOT at the end — peers use `$`, which would reject the figure the operator is required to
# state. An unanchored grep would instead match this script's own instructions if they were pasted
# into the issue, the token-in-prose collision that has bitten this repo repeatedly.
set -uo pipefail

# soleur:followthrough cpx22-invoice-reconcile-7431

command -v gh >/dev/null || { echo "TRANSIENT: gh is not on PATH"; exit 2; }

# The sweeper invokes verification scripts with NO ARGUMENTS (`"$script"` bare, under `env -i`),
# so a probe cannot be told which issue it belongs to — it must find itself. The repo convention
# is to search for this script's own filename, which appears in the tracking issue's
# `<!-- soleur:followthrough script=... -->` directive and is unique across the backlog.
#
# `--state all`, not the peers' `--state open`: the sweeper runs a CLOSED set too, where the whole
# point is re-verifying issues already closed and reopening any whose criteria stopped holding. A
# probe that can only find its issue while open returns TRANSIENT forever on that pass and the
# re-verification silently never happens.
ISSUE=$(gh issue list --label follow-through --state all \
  --search "cpx22-invoice-reconcile-7431.sh" \
  --json number --jq '.[0].number // empty' 2>/dev/null)
if [[ -z "$ISSUE" ]]; then
  echo "TRANSIENT: could not locate the tracking issue for cpx22-invoice-reconcile-7431"; exit 2
fi

body="$(gh issue view "$ISSUE" --json comments --jq '.comments[].body' 2>/dev/null)" || {
  echo "TRANSIENT: could not read comments on #${ISSUE} (API/auth). NOT evidence of absence."; exit 2; }

# Anchored at line start. An unanchored grep would match this script's own instructions if they
# were ever pasted into the issue, which is the token-in-prose collision that has bitten this repo
# repeatedly.
if printf '%s\n' "$body" | grep -qE '^RESULT: PASS'; then
  echo "cpx22-invoice-reconcile[#${ISSUE}]: PASS — operator confirmed against the invoice"
  printf '%s\n' "$body" | grep -E '^RESULT: PASS' | head -1
  exit 0
fi
if printf '%s\n' "$body" | grep -qE '^RESULT: FAIL'; then
  echo "cpx22-invoice-reconcile[#${ISSUE}]: FAIL — the invoice contradicts the ledger"
  printf '%s\n' "$body" | grep -E '^RESULT: FAIL' | head -1
  echo "Correct expenses.md AND cost-model.md together; the registry rows move as a pair."
  exit 1
fi

echo "TRANSIENT: no anchored RESULT: line on #${ISSUE} yet — the invoice covering 2026-08-10 onward has not been reconciled."
exit 2
