#!/usr/bin/env bash
# strip-vendor-credit.sh — emit-path strip for vendored legal substrates.
#
# Vendored templates carry two General Legal provenance marks: the line-1
# `<!-- Adapted from General-Legal/legal-templates (CC0-1.0) — see NOTICE -->`
# header and the trailing `---` + credit paragraph. Both stay in the corpus
# (provenance, NOTICE blob pins) but neither may reach emitted documents —
# CC0 requires no attribution and the paragraph is third-party marketing
# surface inside a user's deliverable.
#
# Usage: strip-vendor-credit.sh <substrate-file>   # stripped doc to stdout
#
# Exit codes:
#   0 — stripped
#   1 — usage / unreadable input
#   2 — provenance anomaly: the credit-paragraph marker is absent, sits
#       mid-document, or the `---` fence before it is missing. Fail closed:
#       a substrate missing its marks may be corrupted or wrongly routed,
#       and silently passing it through would emit whatever it contains.
#
# This script operates on SUBSTRATE (template-fill) output only. From-scratch
# generator output has no credit block and must NOT be piped through here —
# the exit-2 contract would (correctly) refuse it.

set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 <substrate-file>" >&2
  exit 1
fi
input="$1"

MARKER='prepared and made publicly available by General Legal'

# Marker must be present exactly once. Multiple hits mean duplicated credit
# blocks (a corrupted concatenation) — treat as anomaly rather than strip one.
marker_count=$(grep -cF "$MARKER" "$input" || true)
if [[ "$marker_count" -eq 0 ]]; then
  echo "strip-vendor-credit: $input has no General Legal credit marker — is this a vendored substrate? (refusing to pass through)" >&2
  exit 2
fi
if [[ "$marker_count" -gt 1 ]]; then
  echo "strip-vendor-credit: $input has $marker_count credit markers — refusing to guess which block to strip" >&2
  exit 2
fi

marker_ln=$(grep -nF "$MARKER" "$input" | cut -d: -f1) || true
total_ln=$(wc -l < "$input" | tr -d '[:space:]')

# The credit paragraph is the LAST block: only blank lines may follow it.
if tail -n +"$((marker_ln + 1))" "$input" | grep -qE '[^[:space:]]'; then
  echo "strip-vendor-credit: content follows the credit marker in $input — not a trailing credit block" >&2
  exit 2
fi

# The block opens with a `---` fence; only blank lines may sit between the
# fence and the marker. Anchoring the cut on the fence nearest the marker —
# never on a bare `---` alone — keeps mid-document rules intact.
fence_ln=$(head -n "$((marker_ln - 1))" "$input" | grep -nE '^---[[:space:]]*$' | tail -1 | cut -d: -f1) || true
if [[ -z "${fence_ln:-}" ]]; then
  echo "strip-vendor-credit: no \`---\` fence before the credit marker in $input" >&2
  exit 2
fi
if [[ $((marker_ln - fence_ln)) -gt 1 ]] &&
   sed -n "$((fence_ln + 1)),$((marker_ln - 1))p" "$input" | grep -qE '[^[:space:]]'; then
  echo "strip-vendor-credit: non-blank content between the \`---\` fence and the credit marker in $input" >&2
  exit 2
fi

# Emit lines 1..fence_ln-1 (dropping the line-1 attribution header), trim
# trailing blank lines left by the cut, and drop literal invisible
# codepoints the upstream corpus carries (ZWJ separators between <mark>
# fields, stray ZWJs at line ends — the same class the redact sentinel's
# AC6 scan forbids). They are provenance-neutral upstream artifacts and
# must not reach emitted documents.
head -n "$((fence_ln - 1))" "$input" | awk '
  NR == 1 && /^<!-- Adapted from General-Legal\/legal-templates \(CC0-1\.0\)/ { next }
  { lines[++n] = $0 }
  END { while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }
' | LC_ALL=C sed -e 's/\xe2\x80[\x8b\x8c\x8d\xa8\xa9\xaa\xab\xac\xad\xae]//g' \
                 -e 's/\xe2\x81\xa0//g' \
                 -e 's/\xef\xbb\xbf//g' \
                 -e 's/\xc2\xad//g' \
                 -e 's/\xef\xbf\xbd//g'
