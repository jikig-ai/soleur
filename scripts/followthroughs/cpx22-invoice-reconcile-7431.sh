#!/usr/bin/env bash
# Follow-through verification for the #7431 ledger flip — reconcile against the real invoice.
# Tracking issue: #7437.
#
# WHY THIS CANNOT BE AUTOMATED, STATED HONESTLY. Every figure in the flip is CATALOG-derived, from
# the Hetzner API's `/v1/server_types`. The API returns IDENTICAL `net` and `gross` for this
# account, so `cpx22 EUR 19.49 - cx23 EUR 5.49 = +EUR 14.00/mo` is arithmetic on those values and
# NOT a VAT-adjusted quote. Hetzner exposes no invoice endpoint, so the settled figure is not
# obtainable with any credential this repo holds — it arrives by email to ops@.
#
# That is the precise reason this is compliant with `hr-no-dashboard-eyeball-pull-data-yourself`,
# and the earlier version of this comment got the reason wrong. It claimed "the human does not read
# a dashboard on the script's behalf", which is false: the human does read a document and does
# render a judgement, including a VAT interpretation. What actually makes it sound is narrower and
# stronger — the fact is MACHINE-UNOBTAINABLE, and the verdict is anchored, durable, machine-read,
# and re-verifiable after close.
#
# WHAT THE OPERATOR MUST CONFIRM (all three, or it is not a reconciliation):
#   1. the invoice line for `soleur-registry` bills the cpx22 rate from 2026-08-10, not cx23;
#   2. the delta against the prior month is ~EUR 14.00 for this host (state the actual figure);
#   3. whether VAT changes the picture — if gross and net differ on the invoice, the ledger's
#      caveat was right and both expenses.md and cost-model.md need the corrected basis.
#
# Then comment on the issue with a line of its own:
#     RESULT: PASS   <actual figure, and any VAT correction>
#   or
#     RESULT: FAIL   <what the invoice actually shows>
#
# ── TRUST MODEL. READ THIS BEFORE CHANGING ANY GREP OR THE ISSUE LOOKUP. ─────────────────────
#
# `jikig-ai/soleur` is a PUBLIC repo with issues open to the world, and this script's exit code
# makes the sweeper AUTO-CLOSE a financial-ledger tracker. So the set of people who can influence
# the verdict is, by default, every authenticated GitHub user. Three controls close that, and all
# three were added after a security review of PR #7435 found the original version forgeable by a
# stranger with one HTTP POST:
#
#   1. AUTHOR FILTER. Only OWNER / MEMBER / COLLABORATOR comments are read. `.comments[].body`
#      with no author filter is the whole vulnerability: an anonymous `RESULT: PASS` closed the
#      issue, and the sweeper's own `### Sweeper run: PASS` comment then satisfied its
#      closed-set reopen guard forever, laundering the forgery into the evidence trail.
#   2. FIXED ISSUE NUMBER. Self-location by `gh issue list --search <filename>` is hijackable:
#      GitHub's issue search matches COMMENT bodies, not just issue bodies (verified — a string
#      appearing only in sweeper comments returned #7296/#6522/#6168), and `.[0]` is
#      relevance-ordered, so commenting this filename on any of the ~100 other follow-through
#      issues can make the probe read the WRONG issue's comments while the sweeper still closes
#      THIS one. The tracker number is known at authoring time; there is no reason to search.
#   3. FENCE STRIPPING. A fenced code block quoting the template must not arm the probe. This is
#      not a hypothetical attacker: it is a helpful contributor pasting the instructions. The
#      directive parser one layer up (sweep-followthroughs.sh) already skips fences; so does this.
#
# The verdict regex is `^RESULT: (PASS|FAIL)\b`. The word boundary is load-bearing and its absence
# was a live fail-open — `RESULT: PASSing on this for now, invoice not here yet` exited 0 and would
# have closed the tracker on a comment that explicitly DECLINES to verify. PASS additionally
# requires evidence after the verb, because the issue asks the operator to state the figure and a
# bare `RESULT: PASS` is exactly the "looks right" this check exists to reject. FAIL needs no
# evidence: failing closed is always safe.
#
# Note what is NOT true, though an earlier version of this comment asserted it: GitHub issue
# comments are editable and deletable by their author, so they are NOT append-only. That mattered —
# the false premise was the stated justification for an earlier "any FAIL outranks any PASS" rule
# which, combined with echoing the matched line, latched the issue permanently unclosable. See the
# verdict-selection comment below.
#
# This probe follows the operator-confirmed shape already established by
# `inngest-doublefire-reading-6617.sh`; it is not a new pattern. Two things are genuinely different
# and are argued where they occur: the author filter, and the last-verdict-wins selection.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       an anchored `RESULT: PASS <evidence>` from a repo member
#   1 = FAIL       an anchored `RESULT: FAIL` from a repo member — the ledger is wrong
#   * = TRANSIENT  no qualifying verdict yet, or the GitHub API was unreachable. NOT a pass.
#
# Required env: GH_TOKEN (declare `secrets=GH_TOKEN` in the directive — the sweeper's env -i
#   sandbox strips everything not named, and a gh probe without it is unauthenticated and would
#   never close).
set -uo pipefail

# soleur:followthrough cpx22-invoice-reconcile-7431

ISSUE=7437   # fixed by design — see control 2 in the trust model above. Never make this a search.

command -v gh >/dev/null || { echo "TRANSIENT: gh is not on PATH"; exit 2; }

# Confirm the hardcoded number still points at THIS probe's tracker before trusting its comments.
# Cheap, and it catches the one thing hardcoding can get wrong: the issue being closed as a
# duplicate and the work re-filed elsewhere, which would otherwise leave this reading a stale
# thread forever.
dir_err="$(mktemp)"; trap 'rm -f "$dir_err"' EXIT
if ! issue_body="$(gh issue view "$ISSUE" --json body --jq .body 2>"$dir_err")"; then
  echo "TRANSIENT: could not read #${ISSUE} (rc from gh): $(head -c 400 "$dir_err")"; exit 2
fi
if ! printf '%s' "$issue_body" | grep -q 'script=scripts/followthroughs/cpx22-invoice-reconcile-7431.sh'; then
  echo "TRANSIENT: #${ISSUE} no longer carries this probe's followthrough directive — retarget the script, do not guess."
  exit 2
fi

# Author-filtered comment bodies. `authorAssociation` is on the payload already, so this costs
# nothing. An unauthenticated read (missing/expired GH_TOKEN) returns nothing and must land in
# TRANSIENT, never in "no verdict, therefore fine" — hence the rc check rather than `2>/dev/null`.
err="$(mktemp)"; trap 'rm -f "$dir_err" "$err"' EXIT
if ! body="$(gh issue view "$ISSUE" --json comments --jq '
      .comments[]
      | select(.authorAssociation == "OWNER"
            or .authorAssociation == "MEMBER"
            or .authorAssociation == "COLLABORATOR")
      | .body' 2>"$err")"; then
  echo "TRANSIENT: could not read comments on #${ISSUE} (rc from gh): $(head -c 400 "$err"). NOT evidence of absence."
  exit 2
fi

# Drop fenced blocks so a quoted template cannot arm the probe (control 3).
body="$(printf '%s\n' "$body" | awk '/^[[:space:]]*```/ { f = !f; next } !f { print }')"

# THE LAST MEMBER VERDICT WINS. Not "any FAIL outranks any PASS", which was the previous rule and
# was wrong in both directions:
#
#   * It could not recover from a premature FAIL. Once any FAIL existed the probe returned 1 on
#     every sweep forever, whatever the operator wrote afterwards, and the follow-through stayed
#     permanently red. GitHub comments are editable, so the stated justification for FAIL-absorbing
#     ("verdicts are append-only") was also simply false.
#   * It was SELF-POISONING. This script echoes the matched verdict line; the sweeper captures
#     stdout+stderr and posts it into a FAIL comment on this very issue; `--json comments` then
#     returns that comment on the next run, where `^RESULT: FAIL` matches the sweeper's own echo.
#     One genuine FAIL therefore latched the issue closed-to-closing for good, and on the closed
#     set it drove `gh issue reopen` until REOPEN_MAX gave up. No sibling probe has this because
#     none of them echo the matched line at column 1.
#
# Both are fixed here: order by position and take the last, and REDACT the anchor before echoing
# so nothing this script prints can ever be re-read as a verdict. Chronological order is safe
# because `.comments[]` returns oldest-first and the author filter above means only members can
# place a verdict at all — so "the latest member judgement" is exactly the right rule.
verdicts="$(printf '%s\n' "$body" | grep -E '^RESULT: (PASS|FAIL)\b' || true)"
last="$(printf '%s\n' "$verdicts" | grep -E '^RESULT: (PASS|FAIL)\b' | tail -1)"

redact() { printf '%s\n' "$1" | sed 's/^RESULT:/RESULT (quoted, not a verdict):/'; }

if [[ "$last" =~ ^RESULT:\ FAIL ]]; then
  echo "cpx22-invoice-reconcile[#${ISSUE}]: FAIL — the invoice contradicts the ledger"
  redact "$last"
  echo "Correct expenses.md AND cost-model.md together; the registry rows move as a pair."
  exit 1
fi
if [[ "$last" =~ ^RESULT:\ PASS[[:space:]]+[^[:space:]] ]]; then
  echo "cpx22-invoice-reconcile[#${ISSUE}]: PASS — member-authored, evidence-bearing verdict"
  redact "$last"
  exit 0
fi
if [[ "$last" =~ ^RESULT:\ PASS ]]; then
  echo "TRANSIENT: #${ISSUE}'s latest verdict is a bare 'RESULT: PASS' with no figure. The issue asks"
  echo "  for the actual delta and any VAT correction; a verdict with no evidence is exactly the"
  echo "  'looks right' this check exists to reject."
  exit 2
fi

echo "TRANSIENT: no member-authored, anchored RESULT: line on #${ISSUE} yet — the invoice covering 2026-08-10 onward has not been reconciled."
exit 2
