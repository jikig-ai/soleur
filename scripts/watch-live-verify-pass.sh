#!/usr/bin/env bash
# watch-live-verify-pass.sh — record the FIRST qualifying live-verify CI PASS on
# the report-only→blocking flip-tracker issue (5463), so the flip's dark-launch
# evidence gate (wg-dark-launch-deploy-gates: "observed passing on >=1 real
# qualifying deploy") is captured automatically instead of by manual polling.
#
# Run by .github/workflows/live-verify-pass-watch.yml on a daily cron. It is a
# RECORD-ONLY watcher: it comments evidence + a record-once sentinel and stops.
# It does NOT flip the gate — the flip ships separately via /soleur:one-shot 5463
# as a SEPARATE, later deploy (never validate a gate with the deploy it gates).
#
# SELF-DISABLE: once the flip ships and issue 5463 closes, the `state != OPEN`
# guard makes every daily run a cheap no-op. The flip PR should delete this
# script + its workflow as cleanup.
#
# Authoritative PASS signal = the `RESULT: PASS` line in the live-verify job LOG.
# The harness step is `continue-on-error: true`, so its step CONCLUSION is
# `success` even on FAIL/skip and is NOT a reliable signal.
#
# Env: GH_TOKEN + GH_REPO (injected by the workflow). Uses gh + jq.
set -uo pipefail

ISSUE=5463
SENTINEL="live-verify-pass-watch:recorded"
WORKFLOW="web-platform-release.yml"

# (a) Only act while the flip-tracker issue is OPEN.
state="$(gh issue view "$ISSUE" --json state 2>/dev/null | jq -r '.state // ""' 2>/dev/null || true)"
if [[ "$state" != "OPEN" ]]; then
  echo "issue $ISSUE is '${state:-unknown}' (not OPEN) — nothing to watch"
  exit 0
fi

# (b) Idempotent record-once: bail if a prior run already recorded the evidence.
if gh issue view "$ISSUE" --json comments 2>/dev/null \
     | jq -r '.comments[].body // empty' 2>/dev/null \
     | grep -qF "$SENTINEL"; then
  echo "already recorded — sentinel present on #$ISSUE"
  exit 0
fi

# (c) Scan recent release runs newest-first for the first qualifying PASS.
runs="$(gh run list --workflow="$WORKFLOW" --limit 25 \
          --json databaseId,headSha,url,status 2>/dev/null || echo '[]')"
ids="$(printf '%s' "$runs" | jq -r '.[] | select(.status=="completed") | .databaseId' 2>/dev/null || true)"

found_run="" found_url="" found_sha="" found_line=""
for id in $ids; do
  jobs="$(gh run view "$id" --json jobs 2>/dev/null || echo '{}')"
  # The live-verify job's db id + its harness-step conclusion, on one line.
  jobinfo="$(printf '%s' "$jobs" | jq -r '
    ((.jobs // []) | map(select(.name | test("live-verify"))) | .[0]) as $j
    | (($j.steps // []) | map(select(.name | test("Run live-verify harness"))) | .[0].conclusion // "absent") as $step
    | "\($j.databaseId // "") \($step)"' 2>/dev/null || echo " absent")"
  jobid="$(printf '%s' "$jobinfo" | awk '{print $1}')"
  step="$(printf '%s' "$jobinfo" | awk '{print $2}')"
  # Not a qualifying merge if the harness step skipped or the job/step is absent.
  [[ -z "$jobid" || "$step" == "skipped" || "$step" == "absent" ]] && continue

  # Harness executed → read the authoritative RESULT line from the job log
  # (bounded: grep -m1; never echo the full log — hr-never-run-commands-with-unbounded-output).
  result="$(gh run view --job "$jobid" --log 2>/dev/null \
              | grep -m1 -oE 'RESULT: (PASS|FAIL|CANT-RUN[^[:space:]]*)' || true)"
  if [[ "$result" == "RESULT: PASS" ]]; then
    found_run="$id"
    found_url="$(printf '%s' "$runs" | jq -r --arg id "$id" \
                  '.[] | select((.databaseId|tostring)==$id) | .url' 2>/dev/null | head -1)"
    found_sha="$(printf '%s' "$runs" | jq -r --arg id "$id" \
                  '.[] | select((.databaseId|tostring)==$id) | .headSha' 2>/dev/null | head -1)"
    found_line="$result"
    break
  fi
done

if [[ -z "$found_run" ]]; then
  echo "no qualifying live-verify PASS observed yet"
  exit 0
fi

# (d) Record the evidence once, with the record sentinel.
body="$(mktemp)"
{
  echo "## live-verify PASS observed on a qualifying deploy — the flip is now unblocked"
  echo ""
  echo "The report-only live-verify gate emitted a real \`${found_line}\` on a qualifying merge (a diff touching a \`trigger-paths.txt\` surface)."
  echo ""
  echo "- Run: ${found_url}"
  echo "- Head SHA: \`${found_sha}\`"
  echo "- Result: \`${found_line}\`"
  echo ""
  echo "This is the \"observed passing on >=1 real deploy\" evidence (wg-dark-launch-deploy-gates). The report-only→blocking flip is now unblocked — run \`/soleur:one-shot 5463\` to ship it. The flip MUST merge as a separate, later deploy than the run above (never validate a gate with the deploy it gates)."
  echo ""
  echo "<!-- ${SENTINEL} run=${found_run} -->"
} > "$body"
gh issue comment "$ISSUE" --body-file "$body"
rm -f "$body"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "live-verify-pass-watch: recorded PASS from run ${found_run} on #${ISSUE}" >> "$GITHUB_STEP_SUMMARY"
fi
echo "recorded live-verify PASS from run ${found_run} on #${ISSUE}"
exit 0
