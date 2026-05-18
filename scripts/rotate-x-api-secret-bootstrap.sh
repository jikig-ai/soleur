#!/usr/bin/env bash
# Post-merge rotation chain for issue #4029 (X_API_SECRET compromised via
# doppler-stdout-echo on the post-deletion surviving-secrets table during
# PR #3983 cleanup).
#
# Pre-requisite: Playwright MCP session has captured the new secret to
# .playwright-mcp/x-api-secret.txt via the `browser_evaluate(filename:)`
# vendor-token-mint pattern (see
# knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md
# §Playwright vendor-token extraction). NEVER let the new secret enter the
# transcript via raw return values.
#
# Operator runs this from the worktree root after the PR merges (so the
# widened hook on main protects subsequent operators) and BEFORE
# `gh issue close 4029`.
set -euo pipefail

TOKEN_FILE=".playwright-mcp/x-api-secret.txt"
test -f "$TOKEN_FILE" || {
  echo "Missing $TOKEN_FILE — run the Playwright extraction step first." >&2
  echo "See plan §Phase 4 + the vendor-token-mint learning for the pattern." >&2
  exit 1
}

# Validate the extraction sentinel: the Playwright function returns
# COUNT-ERROR:N / LEN-ERROR:N on failure, OK on success.
FIRST6="$(head -c 6 "$TOKEN_FILE")"
case "$FIRST6" in
  COUNT-|LEN-ER)
    echo "Extraction failed: $(cat "$TOKEN_FILE")" >&2
    echo "Re-run the Playwright extraction; do not proceed." >&2
    exit 1
    ;;
esac

# Strip JSON quotes (the `filename:` parameter JSON-encodes the result).
SECRET_VALUE="$(python3 -c "import json,sys; sys.stdout.write(json.loads(open('$TOKEN_FILE').read()))")"

# (1) Doppler prd — --silent suppresses the just-set value echo;
#     >/dev/null 2>&1 is belt-and-suspenders against stderr drift.
printf '%s' "$SECRET_VALUE" \
  | doppler secrets set X_API_SECRET --silent --no-interactive -p soleur -c prd >/dev/null 2>&1

# (2) GitHub Actions repo secret — `gh secret set --body -` reads from stdin
#     and does NOT echo the value (safer than --body "$VALUE" which exposes
#     the value in process argv visible to `ps aux`).
printf '%s' "$SECRET_VALUE" | gh secret set X_API_SECRET --body -

# (3) Live verification — sources Doppler prd to validate the just-written
#     value against the X API. validate-credentials returns HTTP 2xx +
#     `Credentials valid. Account: @<handle> (<name>)` on success; 401 →
#     rotation failed.
doppler run -p soleur -c prd -- bash plugins/soleur/skills/community/scripts/x-setup.sh validate-credentials

# (4) Cron pipeline smoke — workflow_dispatch trigger; the workflow no-ops
#     cleanly if today is not a publish date.
gh workflow run scheduled-content-publisher.yml

# (5) Cleanup — shred the extraction artifact so it cannot be re-leaked.
shred -u "$TOKEN_FILE"

echo "[rotate-x-api-secret] OK — secret rotated, both write targets confirmed."
echo "  Verify cron smoke run at:"
echo "    gh run list --workflow=scheduled-content-publisher.yml --limit 1"
echo "  Then close the issue:"
echo "    gh issue close 4029 --comment \"Rotated via PR <N> + bootstrap. Doppler prd + GH secret updated; validate-credentials 200; cron smoke green.\""
