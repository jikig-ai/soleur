#!/usr/bin/env bash
set -uo pipefail
curl -sS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" https://example.invalid/ || true
