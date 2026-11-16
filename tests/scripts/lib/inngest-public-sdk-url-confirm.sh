#!/usr/bin/env bash
# Typed-confirm gate for every Inngest host boot that carries the public sdk_url (#10538, CTO rulings D2 and
# fix-round F1, PR #12737). It is called by two jobs in .github/workflows/apply-web-platform-infra.yml, as the
# first step after checkout and before any credential is loaded:
#   inngest_host_replace  -> expects PUBLIC-SDK-URL
#   inngest_host (birth)  -> expects PUBLIC-SDK-URL-BIRTH (distinct, so a birth token never authorizes a destroy)
# Both boot hcloud_server.inngest from user_data that polls https://app.soleur.ai/api/inngest. That carries three
# open risks tracked in #12742 (a stale registry count hiding a failing poll, the #7228 first-sync double-fire,
# and the old private-URL app row). The token is a typo-guard, not the authorization, and it does not read the
# live Cloudflare mode: #12742 item 1 must replace this script with a fail-closed preflight, never delete it bare.
#
# Usage: CONFIRM_RAW=<dispatch input> inngest-public-sdk-url-confirm.sh <expected-token>
# Exit:  0 token matches; 1 mismatch (or empty); 64 usage error. The dispatch input is never echoed.
set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "::error::inngest-public-sdk-url-confirm.sh: usage: CONFIRM_RAW=<input> $0 <expected-token>"
  exit 64
fi

if [[ "${CONFIRM_RAW:-}" != "$1" ]]; then
  echo "::error::confirm must be exactly '$1': this boots the public sdk_url (#10538) with three open risks; read #12742 first."
  exit 1
fi
echo "confirm token accepted for the public sdk_url boot (#12742 risks acknowledged)"
