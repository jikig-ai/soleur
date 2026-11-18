#!/usr/bin/env bash
# Repo-wide arm/merge walker (ADR-328, #12739). Verifies that every known merge site
# either invokes the review-evidence arm check or carries a ledger row.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LEDGER="$REPO_ROOT/knowledge-base/engineering/review-evidence-exemption-ledger.yml"
LINK="review-evidence-comment.md#arm-check"

fail=0
ledger_sites=""
if [[ -f "$LEDGER" ]]; then
  ledger_sites=$(grep -E '^[[:space:]]*-[[:space:]]*site:' "$LEDGER" | sed 's/.*site:[[:space:]]*//;s/^"//;s/"$//' || true)
fi

# Known merge sites (code paths that arm or merge PRs)
MERGE_SITES=(
  ".github/scripts/bump-inngest-bootstrap-pin.sh"
  ".github/actions/bot-pr-with-synthetic-checks/action.yml"
  "apps/web-platform/server/inngest/functions/_cron-safe-commit.ts"
)

for f in "${MERGE_SITES[@]}"; do
  full="$REPO_ROOT/$f"
  [[ -f "$full" ]] || { echo "MISSING MERGE SITE: $f"; fail=1; continue; }
  gated=0
  if grep -qF "$LINK" "$full" 2>/dev/null; then gated=1; fi
  if grep -qF -- '--match-head-commit "${H:?' "$full" 2>/dev/null; then gated=1; fi
  ledgered=0
  while IFS= read -r site; do
    [[ -z "$site" ]] && continue
    site_path="${site%%#*}"
    if [[ "$f" == "$site_path" ]]; then ledgered=1; break; fi
  done <<< "$ledger_sites"
  if [[ $gated -eq 0 && $ledgered -eq 0 ]]; then
    echo "UN-GATED MERGE SITE: $f"
    fail=1
  fi
done

# Ledger sanity: must exist and contain the three seed rows
if [[ ! -f "$LEDGER" ]]; then
  echo "MISSING LEDGER: $LEDGER"; fail=1
else
  for s in bump-inngest-bootstrap-pin.sh bot-pr-with-synthetic-checks/action.yml _cron-safe-commit.ts; do
    grep -qF "$s" "$LEDGER" || { echo "LEDGER MISSING SEED: $s"; fail=1; }
  done
fi

if [[ $fail -eq 0 ]]; then
  echo "review-evidence-arm-walker: all merge sites gated or ledgered"
  exit 0
else
  exit 1
fi