#!/usr/bin/env bash
set -uo pipefail
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
