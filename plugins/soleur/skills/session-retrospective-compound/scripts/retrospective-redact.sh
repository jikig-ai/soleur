#!/usr/bin/env bash
# Fail-closed redaction gate for retrospective proposal output.
# Usage: retrospective-redact.sh <input-file> [output-file]
# Exit 0 = clean (scrubbed output written), non-zero = fail (no output written).
set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "retrospective-redact: input file required" >&2
  exit 2
fi

# gitleaks-shaped patterns (subset). Add new patterns here.
PATTERNS=(
  'dp\.(pt|st|sa|ct)\.[A-Za-z0-9]+'
  'sk-[A-Za-z0-9]{20,}'
  'whsec_[A-Za-z0-9]+'
  'sbp_[A-Za-z0-9]+'
  'postgres://[^[:space:]]*:[^[:space:]@]*@'
  'sk-soleur-[A-Za-z0-9]+'
)

TMP="$(mktemp)"
cp "$INPUT" "$TMP"

for p in "${PATTERNS[@]}"; do
  if grep -Eq "$p" "$TMP"; then
    # attempt redaction
    sed -i -E "s/$p/[REDACTED]/g" "$TMP"
  fi
done

# Post-scrub verification: if any pattern still matches, fail closed.
for p in "${PATTERNS[@]}"; do
  if grep -Eq "$p" "$TMP"; then
    rm -f "$TMP"
    echo "retrospective-redact: scrub failed (pattern: $p)" >&2
    exit 1
  fi
done

if [[ -n "$OUTPUT" ]]; then
  mv "$TMP" "$OUTPUT"
else
  cat "$TMP"
  rm -f "$TMP"
fi
exit 0
