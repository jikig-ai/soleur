#!/usr/bin/env bash
# Assert that a telemetry payload (or any text passed via stdin or as
# the first argument file path) contains no Linear identifiers, no Linear
# CDN URLs, and no UUID-style Linear IDs. Used to enforce spec TR7.
#
# Usage:
#   echo "$payload" | bash assert-no-linear-telemetry.sh
#   bash assert-no-linear-telemetry.sh /path/to/file.jsonl
#
# Exit 0 if clean. Exit 1 if any forbidden pattern matches. The first
# offending pattern is printed to stderr with the matched substring.
#
# Forbidden patterns:
#   1. Linear issue identifier:  [A-Z]{2,}-[0-9]+  (matches SOL-39, LIN-12, etc.)
#   2. Linear CDN URL:           uploads\.linear\.app
#   3. Linear UUID-style ID:     8-4-4-4-12 hex (Linear's internal issue IDs)
#
# Note: this helper is INTENTIONALLY strict. Operator-facing stdout (the
# Phase E warning line that names the failed identifier) is NOT routed
# through this assertion — only telemetry payloads emitted to
# .claude/hooks/lib/incidents.sh are gated. The skill currently has zero
# emit_incident call sites; this helper exists so a future maintainer
# adding one cannot regress TR7 silently.

set -eu

if [[ $# -ge 1 && -r "$1" ]]; then
  input=$(cat "$1")
else
  input=$(cat -)
fi

# Pattern 1: Linear issue identifier shape.
if printf '%s' "$input" | grep -oE '\b[A-Z]{2,}-[0-9]+\b' | head -n 1 | grep -q .; then
  match=$(printf '%s' "$input" | grep -oE '\b[A-Z]{2,}-[0-9]+\b' | head -n 1)
  echo "FAIL: telemetry payload contains Linear identifier shape: $match" >&2
  exit 1
fi

# Pattern 2: Linear CDN hostname (any form, signed-URL fragments included).
if printf '%s' "$input" | grep -qiE 'uploads\.linear\.app'; then
  echo "FAIL: telemetry payload contains uploads.linear.app reference" >&2
  exit 1
fi

# Pattern 3: UUID-style ID (Linear's internal issue UUIDs).
if printf '%s' "$input" | grep -oE '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' | head -n 1 | grep -q .; then
  match=$(printf '%s' "$input" | grep -oE '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' | head -n 1)
  echo "FAIL: telemetry payload contains UUID-style identifier: $match" >&2
  exit 1
fi

exit 0
