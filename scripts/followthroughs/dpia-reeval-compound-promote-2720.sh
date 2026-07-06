#!/usr/bin/env bash
# Follow-through: week-4 DPIA re-evaluation for the Compound Promotion Loop
# (#2720 DPIA candidacy, Art. 35). The loop was ENABLED 2026-07-06 (#6039),
# which started the "first 4 weeks of operation" clock recorded in
# knowledge-base/legal/compliance-posture.md (#2720 row). The tracker's
# `earliest=2026-08-03` directive gates the sweeper so this only runs once
# ≥28 days of operation have elapsed.
#
# PASS criterion (self-closing): a DPIA re-evaluation has been RECORDED as a
# committed audit artifact under knowledge-base/legal/audits/ whose filename
# names both the assessment class (dpia) and the loop (compound-promote OR
# 2720). Recording the outcome — whether "full DPIA required" or "not required
# at single-operator scale" (the #5103 / inbox-triage precedent shape) — is
# the closure signal. Until that artifact exists, the sweep surfaces the
# reminder daily (never rots).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (re-eval recorded; sweeper closes the tracker)
#   1 = FAIL       (≥28d elapsed, no re-eval artifact; sweeper comments, leaves open)
#   * = TRANSIENT  (repo root not resolvable; retry next sweep)
#
# Required env: none (reads git-tracked files only; no `secrets=` clause).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "TRANSIENT: not inside a git repo; cannot locate audits dir" >&2
  exit 2
}

AUDITS_DIR="$ROOT/knowledge-base/legal/audits"
if [[ ! -d "$AUDITS_DIR" ]]; then
  echo "TRANSIENT: audits dir not found at $AUDITS_DIR" >&2
  exit 2
fi

# Match a DPIA re-eval artifact for the compound-promote loop: filename must
# contain "dpia" AND ("compound-promote" OR "2720") (case-insensitive).
shopt -s nullglob nocaseglob
matches=()
for f in "$AUDITS_DIR"/*dpia*compound-promote*.md \
         "$AUDITS_DIR"/*compound-promote*dpia*.md \
         "$AUDITS_DIR"/*dpia*2720*.md; do
  matches+=("$f")
done
shopt -u nullglob nocaseglob

if (( ${#matches[@]} > 0 )); then
  echo "PASS: DPIA re-evaluation recorded — ${matches[0]#$ROOT/}"
  exit 0
fi

cat >&2 <<'MSG'
FAIL: Compound Promotion Loop (#2720) has been running ≥4 weeks (enabled
2026-07-06, #6039) and the Art. 35 DPIA re-evaluation has not been recorded.

Action: assess the first 4 weeks of empirical data — cluster count,
false-positive rate, and operator merge ratio (source:
knowledge-base/project/learnings/promotion-log.md + merged self-healing/auto
PRs) — and record the outcome as an audit artifact under
knowledge-base/legal/audits/ named like
`<date>-dpia-reeval-compound-promote-2720.md` (mirror the
2026-06-11-dpia-screening-operator-inbox-triage.md shape). Recording the
decision — full DPIA required, or not required at single-operator scale —
closes this follow-through automatically on the next sweep.
MSG
exit 1
