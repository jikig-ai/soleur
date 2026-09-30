#!/usr/bin/env bash
# Which GitHub App key source did web-1's last deploy run on? (#8609 discoverability test)
#   doppler run -p soleur -c prd_terraform -- bash apps/web-platform/scripts/github-app-key-status.sh
# Signs the empty-body GET to /hooks/deploy-status exactly as web-platform-release.yml's deploy-status
# reader does (HMAC over "" with WEBHOOK_DEPLOY_SECRET, plus the CF Access pair) and prints ONLY the
# github_app_key_{source,fetch,probe}= lines. A field the state lacks prints as `absent` (the deploy
# never reached the overlay). Exit 3 = credentials not injected, 6 = the read failed (not a verdict).
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${CF_ACCESS_CLIENT_SECRET:+x}${WEBHOOK_DEPLOY_SECRET:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
for v in WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  [[ -n "${!v:-}" ]] || { printf 'missing %s — run under doppler run -p soleur -c prd_terraform\n' "$v" >&2; exit 3; }
done
SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')
BODY=$(curl --disable --noproxy '*' -sf --max-time 15 -X GET -H "X-Signature-256: sha256=$SIG" \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  "https://deploy.${SOLEUR_DEPLOY_DOMAIN:-soleur.ai}/hooks/deploy-status") || { echo 'deploy-status read failed' >&2; exit 6; }
printf '%s' "$BODY" | jq -er '"github_app_key_source=\(.github_app_key_source // "absent")",
  "github_app_key_fetch=\(.github_app_key_fetch // "absent")",
  "github_app_key_probe=\(.github_app_key_probe // "absent")"' || { echo 'deploy-status body is not JSON' >&2; exit 6; }
