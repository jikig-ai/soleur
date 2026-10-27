#!/usr/bin/env bash
# supabase-pre-pull-images.sh — serial, per-image-retried pre-pull of the
# Supabase image set — #10868 follow-up (measured on run 40525753531).
#
# WHY. The org-namespace pull budget (`allowed: 44000/minute`, identical under
# anonymous AND authenticated pulls) saturates on GLOBAL load, so a single
# `supabase start` fan-out fires ~150 requests into the same bucket each
# attempt — bounded whole-command retry cannot win when every attempt
# re-bursts. Splitting the fan-out into ~15 independent `docker pull`s makes
# each pull a small retryable unit: a pull needs ONE calm instant per
# registry request, and the retry helper (ghcr-pull-with-retry.sh) paces
# throttle-signature failures per image instead of re-firing the whole fan-out.
# A completed pull lands in the daemon cache, so `supabase start` afterwards
# issues minimal (often zero) registry traffic.
#
# IMAGE ENUMERATION. The CLI embeds its pinned image refs as plain strings in
# the Go binary (self-updating across the pinned version bumps in
# rls-authz-fuzz.yml — no manual tag list to drift). A floor check fails the
# step LOUDLY if the extraction shape changes (e.g., refs move to a template
# form), never silently skipping the pre-pull.
#
# Pulls run through the same retry helper the start step uses, so a
# permanently-throttled image propagates the daemon's rc and an ::error::
# annotation instead of dying ambiguously.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRY="${SCRIPT_DIR}/ghcr-pull-with-retry.sh"
MIN_IMAGES=8

SUPABASE_BIN="$(command -v supabase || true)"
if [[ -z "$SUPABASE_BIN" ]]; then
  printf '::error::supabase CLI not on PATH — pre-pull needs the embedded image refs\n' >&2
  exit 2
fi

# Only fully-tagged ghcr.io/supabase refs count: template forms (`...:%s`)
# and untagged names are skipped rather than mispulled as :latest.
mapfile -t IMAGES < <(
  strings "$SUPABASE_BIN" \
    | grep -oE 'ghcr\.io/supabase/[a-z0-9._-]+:[A-Za-z0-9._-]+' \
    | sort -u
)

if (( ${#IMAGES[@]} < MIN_IMAGES )); then
  printf '::error::extracted %d supabase image ref(s) from %s, expected >= %d — the CLI changed how it stores image pins; extraction needs a rework\n' \
    "${#IMAGES[@]}" "$SUPABASE_BIN" "$MIN_IMAGES" >&2
  exit 2
fi

printf 'pre-pull: %d images from %s\n' "${#IMAGES[@]}" "$SUPABASE_BIN"
for img in "${IMAGES[@]}"; do
  printf 'pre-pull: %s\n' "$img"
  bash "$RETRY" docker pull "$img"
done
