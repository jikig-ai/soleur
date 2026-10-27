#!/usr/bin/env bash
# supabase-pre-pull-images.sh — serial, per-image-retried pre-pull of the
# Supabase image set — #10868 follow-up (measured on runs 40525753531 and
# 40561028313).
#
# WHY. The org-namespace pull budget (`allowed: 44000/minute`, identical under
# anonymous AND authenticated pulls) saturates on GLOBAL load, so a single
# `supabase start` fan-out fires ~150 requests into the same bucket each
# attempt — bounded whole-command retry cannot win when every attempt
# re-bursts. Splitting the fan-out into ~10 independent `docker pull`s makes
# each pull a small retryable unit: a pull needs ONE calm instant per
# registry request, and the retry helper (ghcr-pull-with-retry.sh) paces
# throttle-signature failures per image instead of re-firing the whole fan-out.
# A completed pull lands in the daemon cache, so `supabase start` afterwards
# issues minimal (often zero) registry traffic.
#
# IMAGE ENUMERATION. The CLI embeds its pinned refs in the binary as bare
# `supabase/<name>:<tag>` strings (verified against CLI 2.84.2 — there is NO
# `ghcr.io/` prefix in the binary; the CLI prepends the registry at pull
# time). `strings` glues adjacent Go literals together, so raw refs come out
# corrupted (`supabase/edge-runtime:v1.68.4password_verification_attemptfailed`,
# `supabase/postgres:14.1.0.89failed`, `supabase/postgres:orioledb-failed`).
# The tag alternation below only accepts version-shaped tags — it CUTS the
# glue after the last numeric component instead of mispulling a fake tag —
# and non-supabase-org refs (e.g. postgrest/postgrest, pulled from Docker
# Hub, not the throttled GHCR bucket) are excluded by the `supabase/` anchor.
# A floor check fails the step LOUDLY if extraction goes dark.
#
# ECR MIRROR. Run 40572250940 showed the ghcr bucket still saturated under
# serial pulls (every attempt lost the contention lottery — retry-after ~1ms
# yet always rejected). Supabase also publishes to the public ECR gallery
# (`public.ecr.aws/supabase/*`), a DIFFERENT registry bucket with anonymous
# pulls. Each ref tries ECR first; a success is `docker tag`ed onto the ghcr
# ref so `supabase start` sees the image as already-present and skips its
# own pull. An ECR miss (unmirrored image) or failure falls back to ghcr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRY="${SCRIPT_DIR}/ghcr-pull-with-retry.sh"
MIN_IMAGES=8

SUPABASE_BIN="$(command -v supabase || true)"
if [[ -z "$SUPABASE_BIN" ]]; then
  printf '::error::supabase CLI not on PATH — pre-pull needs the embedded image refs\n' >&2
  exit 2
fi

# `v?[0-9]+(\.[0-9]+)+` cuts glued suffixes at the last numeric boundary
# (`v1.68.4password...` -> `v1.68.4`, `14.1.0.89failed` -> `14.1.0.89`);
# `-sha-<hex>` keeps studio's date-sha tags; `cli-X.Y` keeps pgadmin-schema-diff.
# `orioledb-failed` and other non-version tags never match.
mapfile -t IMAGES < <(
  strings "$SUPABASE_BIN" \
    | grep -oE 'supabase/[a-z0-9-]+:(v?[0-9]+(\.[0-9]+)+(-sha-[0-9a-f]{6,})?|cli-[0-9.]+)' \
    | sort -u
)

if (( ${#IMAGES[@]} < MIN_IMAGES )); then
  printf '::error::extracted %d supabase image ref(s) from %s, expected >= %d — the CLI changed how it stores image pins; extraction needs a rework\n' \
    "${#IMAGES[@]}" "$SUPABASE_BIN" "$MIN_IMAGES" >&2
  exit 2
fi

printf 'pre-pull: %d images from %s\n' "${#IMAGES[@]}" "$SUPABASE_BIN"
for img in "${IMAGES[@]}"; do
  ecr="public.ecr.aws/$img"
  ghcr="ghcr.io/$img"
  if bash "$RETRY" docker pull "$ecr"; then
    docker tag "$ecr" "$ghcr"
    printf 'pre-pull: %s via ecr mirror\n' "$img"
  else
    printf 'pre-pull: %s via ghcr\n' "$img"
    bash "$RETRY" docker pull "$ghcr"
  fi
done
