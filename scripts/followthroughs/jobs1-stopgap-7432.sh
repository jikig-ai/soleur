#!/usr/bin/env bash
# Follow-through: #7432 — remove the JOBS=1 stopgap from main-health-monitor.yml.
#
# The stopgap is pinned at two steps (the tests step, which nests the runner via test-all.sh,
# and the infra step). #7432 is done exactly when both pins are gone from main.
#
# Probed against main's CURRENT content via the GitHub API rather than the checkout, so the
# sweeper does not depend on where it is run from.
#
# Exit: 0 = PASS (both pins gone → close)
#       2 = TRANSIENT (still pinned, or the fetch failed — never FAIL)
set -uo pipefail

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN unset — cannot read the workflow from main" >&2
  exit 2
fi

body=$(gh api 'repos/{owner}/{repo}/contents/.github/workflows/main-health-monitor.yml?ref=main' \
  --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo "")
if [[ -z "$body" ]]; then
  echo "TRANSIENT: could not read main-health-monitor.yml from main" >&2
  exit 2
fi

# Liveness marker: prove we actually read the workflow, so "zero JOBS: 1" cannot pass
# vacuously on an empty/garbled fetch.
if ! grep -q 'main-health-monitor' <<<"$body"; then
  echo "TRANSIENT: fetched content does not look like the monitor workflow" >&2
  exit 2
fi

count=$(grep -c 'JOBS: 1' <<<"$body" || true)
if [[ "$count" == "0" ]]; then
  echo "PASS: no 'JOBS: 1' pin remains in main-health-monitor.yml on main." >&2
  exit 0
fi

echo "TRANSIENT: ${count} 'JOBS: 1' pin(s) still present on main." >&2
exit 2
