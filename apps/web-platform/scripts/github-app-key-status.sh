#!/usr/bin/env bash
# Which GitHub App key source did web-1's last deploy run on? (#8609 discoverability test)
#   doppler run -p soleur -c prd_terraform -- bash apps/web-platform/scripts/github-app-key-status.sh
# Signs the empty-body GET to /hooks/deploy-status exactly as web-platform-release.yml's deploy-status
# reader does (HMAC over "" with WEBHOOK_DEPLOY_SECRET, plus the CF Access pair) and prints, one
# `name=value` per line:
#   github_app_key_source= / github_app_key_fetch= / github_app_key_probe= — a field the state
#     lacks prints as `absent` (the deploy never reached the overlay);
#   github_app_key_probe_reason= — the probe's closed `rejected` sub-reason, `none` otherwise;
#   component= / tag= / exit_code= / reason= / end_ts= / host_id= — WHICH deploy those came from:
#     the state file is shared by every ci-deploy action, so a verdict is only as good as the
#     deploy it is attributed to (an inngest action or a failed deploy overwrites it).
# Every value is reduced to [A-Za-z0-9._:/@+-] (max 80 chars) before it is printed.
# Exit 3 = credentials not injected, 6 = the read failed (the HTTP code is on stderr) — neither is a
# verdict.
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
# The credentials reach curl on its stdin config channel and the HMAC key reaches a python3 child in its
# environment, never an argument list (tracker #9597, ADR-280). The library is found from THIS file's own
# location: this diagnostic is run from anywhere. A refusal (an unusable value, or python3 missing) makes
# no request, prints the value-free SOLEUR_CREDENTIAL_REFUSED marker, and reaches the exit-6 arm below.
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/bearer-curl.sh" \
  || { printf 'could not load scripts/lib/bearer-curl.sh from this checkout\n' >&2; exit 6; }
# shellcheck disable=SC2034  # read by NAME inside bc_curl
SIG=$(printf '' | bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET) || SIG=""
# The HTTP code rides the last line (`-w`), so a CF Access 403, an HMAC 403 and a 5xx stay distinct.
RESP=$(bc_curl github-app-key-status \
  'X-Signature-256:sha256=:SIG' \
  'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
  'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- \
  -s --max-time 15 -w '\n%{http_code}' -X GET \
  "https://deploy.${SOLEUR_DEPLOY_DOMAIN:-soleur.ai}/hooks/deploy-status")
CURL_RC=$?
CODE=${RESP##*$'\n'}
BODY=${RESP%$'\n'*}
if [[ "$CURL_RC" -ne 0 || "$CODE" != 200 ]]; then
  printf 'deploy-status read failed: http_code=%s curl_rc=%s\n' "$(printf '%s' "$CODE" | tr -cd '0-9' | cut -c1-3)" "$CURL_RC" >&2
  exit 6
fi
printf '%s' "$BODY" | jq -er '
  def v: if . == null then "absent" else (tostring | gsub("[^A-Za-z0-9._:/@+-]"; "_") | .[0:80]) end;
  "github_app_key_source=\(.github_app_key_source | v)",
  "github_app_key_fetch=\(.github_app_key_fetch | v)",
  "github_app_key_probe=\(.github_app_key_probe | v)",
  "github_app_key_probe_reason=\(.github_app_key_probe_reason // "none" | v)",
  "component=\(.component | v)",
  "tag=\(.tag | v)",
  "exit_code=\(.exit_code | v)",
  "reason=\(.reason | v)",
  "end_ts=\(.end_ts | v)",
  "host_id=\(.host_id | v)"' || { echo 'deploy-status body is not JSON' >&2; exit 6; }
