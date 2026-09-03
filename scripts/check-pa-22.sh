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
# ANCHORED ON THE SEPARATOR (#7717). The bare prefix also matched `## Processing Activity 22x`
# for ANY suffix -- `220`, `22-RENAMED` -- so a heading renamed away still counted as
# present and the "exactly once" assertion could not see its own subject leave. Caught by
# scripts/check-pa-22.test.sh, whose first attempt at this mutation was defeated by exactly
# that looseness. `[^0-9]` was the first fix and was ALSO wrong: `-` satisfies it, so
# `22-RENAMED` still matched. The register's heading convention is
# `## Processing Activity NN — Title`, so the space is the real boundary.
header_count=$(grep -cE "^## Processing Activity 22( |$)" "$REG" || true)
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
#
# BOUNDED ON THE NEXT HEADING OF ANY KIND, not on PA-23 specifically (#7717). The register does
# not order its sections PA-22, PA-23: `## Vendor / Sub-Processor Mapping` and `## Cross-Cutting
# Technical & Organisational Measures` sit between them (measured 2026-09-03 at lines 436 and
# 456, with PA-22 at 418 and PA-23 at 472), so the old range spanned FOUR headings rather than
# the PA-22 block.
#
# That was latent, not live: measured, the only `TOMs` literal in the over-spanned region was
# PA-22's own §(g), so removing it still reddened. But planting a `TOMs` literal anywhere in the
# two interloping sections made the same removal pass — so the assertion's non-vacuity depended
# on an accident of wording in sections this check does not own. `Cross-Cutting Technical &
# Organisational Measures` spells the phrase out and happens not to match the abbreviation.
# Both arms are pinned in scripts/check-pa-22.test.sh.
if ! awk '/^## Processing Activity 22/{inblk=1; next} inblk && /^## /{exit} inblk' "$REG" | grep -q "TOMs"; then
  echo "PA-22 missing (g) TOMs section inside the PA-22 block" >&2
  exit 1
fi

echo "PA-22 substrate checks passed."
