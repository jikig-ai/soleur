#!/usr/bin/env bash
# Follow-through verification for #4178.
#
# Verifies that the MANIFEST_DRIFT_SUPPRESS_UNTIL file landed in #4174 is
# safe to delete: at least one `scheduled-github-app-drift-guard.yml` run
# has fired AFTER the suppress expiry timestamp (2026-05-21T16:00:00Z) AND
# completed green (conclusion=success). Returns:
#   0 = PASS (close-criteria met -> sweeper auto-closes #4178)
#   1 = FAIL (no green post-expiry tick yet -> sweeper leaves open, comments)
#   * = TRANSIENT (e.g. GH API failure -> sweeper retries next day)
#
# No secrets required (uses the workflow's default GITHUB_TOKEN, exposed
# as GH_TOKEN by the sweeper's `env:` block).
#
# Close criteria (from #4178 body):
#   - At least one drift-guard cron run with createdAt >= EXPIRY AND
#     conclusion == "success" exists in the most recent N runs.
#
# After PASS, the operator opens a 1-line PR deleting
# `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`. The script does
# NOT delete the file (that's a code change, not a verification).

set -uo pipefail

EXPIRY="2026-05-21T16:00:00Z"
WORKFLOW="scheduled-github-app-drift-guard.yml"
RUN_LIMIT=20

# `gh run list` supports `--created '>=<ISO>'` to scope to runs created on
# or after the timestamp. Combined with `--status success` it filters to
# the green-only set we care about.
RUNS_JSON=$(gh run list \
  --workflow "$WORKFLOW" \
  --created ">=${EXPIRY}" \
  --status success \
  --limit "$RUN_LIMIT" \
  --json databaseId,createdAt,conclusion \
  2>/dev/null)

GH_RC=$?
if [[ "$GH_RC" -ne 0 ]]; then
  echo "TRANSIENT: gh run list exited ${GH_RC} (network or auth failure)"
  exit 2
fi

if [[ -z "$RUNS_JSON" || "$RUNS_JSON" == "[]" ]]; then
  echo "FAIL: no green ${WORKFLOW} runs created >= ${EXPIRY} (waiting for first post-expiry tick)"
  exit 1
fi

GREEN_COUNT=$(printf '%s' "$RUNS_JSON" | jq 'length' 2>/dev/null || echo 0)
if [[ "$GREEN_COUNT" -lt 1 ]]; then
  echo "FAIL: parsed 0 green post-expiry runs from gh response"
  exit 1
fi

FIRST_RUN_ID=$(printf '%s' "$RUNS_JSON" | jq -r '.[0].databaseId')
FIRST_RUN_AT=$(printf '%s' "$RUNS_JSON" | jq -r '.[0].createdAt')

echo "PASS: ${GREEN_COUNT} green ${WORKFLOW} run(s) post-expiry."
echo "First green post-expiry run: id=${FIRST_RUN_ID} at=${FIRST_RUN_AT}"
echo ""
echo "Suppress file is safe to delete. Open a 1-line PR removing"
echo "apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL when convenient."
echo "exit: PASS"
exit 0
