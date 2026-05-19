#!/usr/bin/env bash
# upload-bypass.sh — R2 conditional-PUT wrapper for the per-quarter
# allowlist-bypass canonical record. Companion to upload-evidence.sh (Phase 2).
#
# Differs from upload-evidence.sh only in key derivation:
#   - Evidence record key: signatures/<sha-of-payload>.json
#   - Bypass record key:   allowlist/<principal_safe>/<yyyy-qN>.json
#
# All retry / classification logic lives in r2-conditional-put.sh; this script
# computes the key and delegates so the two upload paths stay in lockstep.
#
# Security: principal_safe is RE-DERIVED here from payload.principal via the
# canonical `[bot]` -> `-bot` substitution. The payload's own principal_safe
# field is NOT trusted for key construction — if a future caller (or attacker
# in the build-bypass.ts path) emits `principal_safe: "dependabot[bot]"`, the
# `[bot]` substring would otherwise appear in object keys and defeat Kieran F8.
# By re-deriving here, the key is unforgeable from any payload field other
# than principal itself.

set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "::error::usage: upload-bypass.sh <payload-json>" >&2
  exit 64
fi

payload="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

principal=$(printf '%s' "$payload" | jq -r '.principal')
quarter=$(printf '%s' "$payload" | jq -r '.quarter')
if [[ -z "$principal" || "$principal" == "null" || -z "$quarter" || "$quarter" == "null" ]]; then
  echo "::error::upload-bypass: payload missing principal or quarter" >&2
  exit 64
fi

# Canonical sanitisation: literal `[bot]` -> `-bot`. Mirrors
# apps/web-platform/scripts/cla-evidence/allowlist-bypass.ts sanitizePrincipal().
# Per Kieran F8 the key must never contain the `[bot]` substring; deriving here
# (not trusting payload.principal_safe) is the load-bearing defense.
#
# Note the escape on `\[bot\]`: bash pattern substitution treats unescaped
# `[bot]` as a character class (matches any of b/o/t), which would mangle
# `dependabot[bot]` to `dependa-bot-bot-bot...`. The backslashes force a
# literal-substring match.
principal_safe="${principal//\[bot\]/-bot}"
key="allowlist/${principal_safe}/${quarter}.json"

LABEL=upload-bypass \
DUP_LABEL=duplicate-quarter \
  exec bash "$script_dir/r2-conditional-put.sh" "$key" "$payload"
