#!/usr/bin/env bash
# Sentinel: PA-22 register + Anthropic Vendor Mapping + Zero-Retention status.
#
# Source-of-truth for PA-22 substrate completeness in
# knowledge-base/legal/article-30-register.md. PR-B introduces PA-22 as a
# pre-merge blocker per the brainstorm Key Decisions table.
#
# Four assertions (per AC19 in 2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md;
# strengthened per Kieran review M1 to detect partial-write, not just header
# presence):
#   (i)   PA-22 header present exactly once.
#   (ii)  Anthropic Vendor Mapping row references PA-22 + autonomous activity.
#   (iii) PA-22 (f) records Zero-Retention status (signed / unsigned / amendment).
#   (iv)  PA-22 (g) TOMs section present inside the PA-22 block.
#
# Fails closed: exit 1 on any check trip.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
REG=knowledge-base/legal/article-30-register.md

if [ ! -f "$REG" ]; then
  echo "Article-30 register not found at $REG" >&2
  exit 1
fi

# (i) PA-22 header present exactly once.
header_count=$(grep -c "^## Processing Activity 22" "$REG" || true)
if [ "$header_count" -ne 1 ]; then
  echo "Expected 1 PA-22 header, found ${header_count}" >&2
  exit 1
fi

# (ii) Anthropic Vendor Mapping row references PA-22 + autonomous activity.
if ! grep -E "Anthropic.*PA-22.*autonomous" "$REG" >/dev/null; then
  echo "Anthropic Vendor Mapping row does not reference PA-22 + autonomous activity" >&2
  exit 1
fi

# (iii) PA-22 (f) records Zero-Retention status.
if ! grep -E "Zero-Retention.*(signed|unsigned|amendment)" "$REG" >/dev/null; then
  echo "PA-22 (f) does not record Anthropic Zero-Retention status" >&2
  exit 1
fi

# (iv) PA-22 (g) TOMs section exists inside the PA-22 block.
if ! awk '/^## Processing Activity 22/,/^## Processing Activity 23|^# [^#]/' "$REG" | grep -q "TOMs"; then
  echo "PA-22 missing (g) TOMs section inside the PA-22 block" >&2
  exit 1
fi

echo "PA-22 substrate checks passed."
