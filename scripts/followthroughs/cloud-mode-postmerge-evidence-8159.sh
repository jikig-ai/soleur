#!/usr/bin/env bash
# (#8159) Has the post-merge Devin Cloud verification session recorded its
# evidence in cloud-probe.md yet?
#
# WHAT IT MEASURES. PR #8155 shipped Soleur Cloud Mode; three acceptance
# criteria are post-merge by construction (a pre-merge probe cannot measure
# the shipped implementation): SC1 (banner + disclosed sequential fallback on
# /soleur:go), SC3 (secrets/prod ack gate halts unanswered), SC4 (skills load
# via requiredPlugins on a manifest-less repo). The verification session —
# tracked at #8228, operator-gated — records its evidence under a
# "## Post-merge verification" heading in
#   knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md
# with one verdict row per SC. This probe fires when that block lands.
#
# ── EXIT CONTRACT — NOTIFY-ONLY ──────────────────────────────────────────────
#   0  NEVER TAKEN. Exit 0 is the sweeper's CLOSE verb. #8159 is a feature
#      issue whose close is an operator judgement on the evidence's content —
#      "evidence present" is not "evidence adequate" — so this probe has not
#      earned the close verb and never takes it.
#   1  NEVER TAKEN. Exit 1 is the sweeper's FAIL verb; "the session has not
#      run yet" is the normal daily state, not a regression.
#   2  NOT YET          — measured; the evidence block is absent.
#   5  ACTION REQUIRED  — the evidence block is present with SC1/SC3/SC4 rows;
#      the operator reviews the recorded verdicts and closes #8159 by hand
#      (and #8228 with it).
#   3  CANNOT ESTABLISH — the file could not be read at all.
#   64 usage.
#
# CREDENTIAL POSTURE: none. This probe reads one file out of the sweeper's
# own checkout of the default branch; the workflow checks out with
# persist-credentials: false, so even that read carries no ambient token.
# No network, no secrets= clause.
#
# WHY A HEADING + TOKEN CHECK AND NOT "IS THE ISSUE CLOSED". #8228 could be
# closed by hand without the evidence ever being written (a mistaken close),
# and evidence could be written while #8228 stays open on a residual arm. The
# artifact the ACs actually name is the recorded evidence; measuring the file
# is measuring the claim.
#
# RETIREMENT. When #8159 closes, this file and its companions go with it:
#   - the soleur:followthrough directive on #8159's body (delete the
#     <!-- soleur:followthrough script=cloud-mode-postmerge-evidence-8159.sh -->
#     marker line, or it dangles against a missing script)
#   - this file (delete)

set -uo pipefail

PROBE="knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILE="$REPO_ROOT/$PROBE"

if [[ ! -r "$FILE" ]]; then
  echo "CANNOT ESTABLISH: $PROBE is not readable in this checkout" >&2
  exit 3
fi

# The evidence block: a `## Post-merge verification` section whose body (up to
# the next `## ` heading or EOF) carries all three SC verdict tokens. awk, not
# a whole-file grep: the pre-existing `## Deferral record` already names
# "SC1/SC3/SC4" in prose, and a file-wide match would read that deferral as
# delivered evidence.
evidence="$(awk '
  /^## Post-merge verification/ { in_sec = 1; next }
  in_sec && /^## /              { in_sec = 0 }
  in_sec                        { print }
' "$FILE")"

if [[ -z "$evidence" ]]; then
  echo "NOT YET: no '## Post-merge verification' evidence block in $PROBE — #8228's session has not recorded verdicts"
  exit 2
fi

missing=""
for sc in SC1 SC3 SC4; do
  grep -q "$sc" <<<"$evidence" || missing="$missing $sc"
done

if [[ -n "$missing" ]]; then
  echo "NOT YET: '## Post-merge verification' exists but lacks verdict rows for:${missing} (partial evidence still needs the session or a human to finish it)"
  exit 2
fi

cat <<'EOF'
ACTION REQUIRED: the post-merge verification evidence block is on main —
'## Post-merge verification' in cloud-probe.md carries SC1, SC3 and SC4
verdict rows. Read the recorded verdicts, confirm they are adequate for the
ACs (this probe detects presence, not adequacy), then close #8159 and #8228
by hand and retire this probe per its RETIREMENT note.
EOF
exit 5
