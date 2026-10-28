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
#
# ECR-DEAD LATCH (#11386, runs 40653699076/40657761446/40661730763). Under
# sustained ECR saturation EVERY image pays the dead tax (~65s of throttled
# retries before the ghcr fallback), so a cold-cache run could not fit
# pull+save inside timeout-minutes:30 — the cache that makes later runs
# cheap could never be populated while the throttle window lasted (two runs
# cancelled at the deadline; the same code in a calmer window fit ~20 min).
# After SUPABASE_ECR_DEAD_AFTER (default 2) CONSECUTIVE ECR throttle
# exhaustions the latch trips (one ::warning::, on the transition only) and
# remaining images skip ECR entirely. ANY non-throttle ECR outcome — success
# or a deterministic answer — resets the consecutive counter, because a
# deterministic reply is evidence the registry RESPONDS, i.e. against
# saturation. Classification reads the helper's own terminal verdict: the
# LAST ::error:: line of the helper's tee'd output carries `toomanyrequests`
# iff its final attempt died on the throttle signature. Grepping the whole
# aggregate log would misclassify a throttle-then-deterministic sequence —
# an earlier attempt's quoted signature survives in it.
#
# ACTIONS CACHE. Run 40573437435 showed ECR's shared-IP bandwidth cap also
# trips (`toomanyrequests: Data limit exceeded`) — every registry quota is
# a shared-runner lottery. The workflow therefore restores an
# `actions/cache` tarball of the pulled image set BEFORE this script: a hit
# restores the refs with `docker load` and issues ZERO registry requests
# (fork PRs get the base branch's read-only cache — no credentials needed).
# After the pulls the script rewrites the tarball from the
# inspect-verified PRESENT subset — never the intended refs[] set, which a
# single absent ref would make `docker save` die on — through `pigz -1`
# (falling back to `gzip -1`; the default level costs ~10 min on the set).
# A run that still leaves images unfetched completes the step FAILED: the
# post-job cache save still uploads the partial tar (it is skipped only on
# timeout-cancel, never on failure), so progress banks monotonically across
# runs while missing images keep failing the job loudly. A CLI bump
# degrades the hit to a partial restore (stale tags simply don't satisfy
# new refs) and only the missing images pull.
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

CACHE_TAR="${SUPABASE_IMG_CACHE_DIR:-}/images.tar.gz"
if [[ -s "$CACHE_TAR" ]] && docker load -i "$CACHE_TAR" >/dev/null; then
  present=0
  for img in "${IMAGES[@]}"; do
    docker image inspect "ghcr.io/$img" >/dev/null 2>&1 && present=$((present + 1)) || true
  done
  if (( present == ${#IMAGES[@]} )); then
    printf 'pre-pull: cache hit — %d images restored, zero registry requests\n' "$present"
    exit 0
  fi
  printf 'pre-pull: cache restore gave %d/%d images — pulling the rest\n' "$present" "${#IMAGES[@]}"
else
  printf 'pre-pull: no usable image cache — pulling the full set\n'
fi

# Latch state (ECR-DEAD LATCH above): consecutive throttle exhaustions, the
# tripped flag, the unfetched set, and a per-image ECR log dir (owning trap,
# same pattern as the helper's). `ecr_dead` is in-memory only — a false latch
# costs ECR upside for the rest of ONE run, never the next.
ECR_DEAD_AFTER="${SUPABASE_ECR_DEAD_AFTER:-2}"
# Gate the env before arithmetic touches it: a non-numeric value aborts the
# run on `unbound variable` under set -u (`(( x >= banana ))`), an
# octal-looking one (`08`) makes the trip check silently never true — the
# latch would go inert with no fatal — and the value is interpolated into
# the ::warning:: below, so it must be digit-shaped before either use.
if [[ ! "$ECR_DEAD_AFTER" =~ ^[0-9]+$ ]]; then
  printf '::warning::ecr latch: SUPABASE_ECR_DEAD_AFTER is not a non-negative integer — defaulting to 2\n'
  ECR_DEAD_AFTER=2
fi
ECR_DEAD_AFTER=$((10#$ECR_DEAD_AFTER))
ecr_consec_throttle=0
ecr_dead=0
failed=()
ecr_log_dir="$(mktemp -d "${TMPDIR:-/tmp}/supabase-pre-pull-ecr.XXXXXX")"
trap 'rm -rf "$ecr_log_dir"' EXIT

img_idx=0
for img in "${IMAGES[@]}"; do
  ecr="public.ecr.aws/$img"
  ghcr="ghcr.io/$img"
  img_idx=$((img_idx + 1))
  if docker image inspect "$ghcr" >/dev/null 2>&1; then
    printf 'pre-pull: %s already cached\n' "$img"
    continue
  fi
  if (( ecr_dead == 0 )); then
    ecr_log="$ecr_log_dir/ecr-${img_idx}.log"
    # The helper call sits inside the `if` so its nonzero rc never aborts
    # under set -e; tee captures the FULL invocation for classification.
    if bash "$RETRY" docker pull "$ecr" 2>&1 | tee "$ecr_log"; then
      docker tag "$ecr" "$ghcr"
      printf 'pre-pull: %s via ecr mirror\n' "$img"
      ecr_consec_throttle=0
      continue
    fi
    # Throttle exhaustion increments; anything else (a deterministic answer,
    # or a failure with no ::error:: at all) resets — see ECR-DEAD LATCH.
    # No `grep -q` on a pipe: under pipefail an early match can SIGPIPE the
    # producer and read as a miss (grep-q-pipe-guard, #9217).
    last_err_line=$(grep '^::error::' "$ecr_log" | tail -n 1)
    if [[ "${last_err_line,,}" == *toomanyrequests* ]]; then
      ecr_consec_throttle=$((ecr_consec_throttle + 1))
      if (( ecr_consec_throttle >= ECR_DEAD_AFTER )); then
        ecr_dead=1
        printf '::warning::ecr latch: %d consecutive ECR throttle exhaustions (SUPABASE_ECR_DEAD_AFTER=%s) — skipping public.ecr.aws for the remaining images\n' \
          "$ecr_consec_throttle" "$ECR_DEAD_AFTER"
      fi
    else
      ecr_consec_throttle=0
    fi
  else
    printf 'pre-pull: %s ecr skipped (latch)\n' "$img"
  fi
  # ghcr fallback is best-effort: a failure is recorded and the loop walks
  # on so partial progress still banks into the cache tar at the end.
  if ! bash "$RETRY" docker pull "$ghcr"; then
    failed+=("$img")
    printf '::warning::pre-pull: %s unpulled after ecr+ghcr — continuing; the run still fails at the end\n' "$img"
    continue
  fi
  printf 'pre-pull: %s via ghcr\n' "$img"
done

# Save the inspect-verified PRESENT subset, never the intended image set — a
# single absent ref makes `docker save` die, forfeiting the whole partial.
present_refs=()
for img in "${IMAGES[@]}"; do
  if docker image inspect "ghcr.io/$img" >/dev/null 2>&1; then
    present_refs+=("ghcr.io/$img")
  fi
done

if [[ -n "${SUPABASE_IMG_CACHE_DIR:-}" && ${#present_refs[@]} -gt 0 ]]; then
  mkdir -p "$SUPABASE_IMG_CACHE_DIR"
  # Fastest first: pigz parallelizes; level 1 is enough for an image-set tar
  # (the default level cost ~10 min on this set — run 40657761446).
  if command -v pigz >/dev/null 2>&1; then COMPRESS=(pigz -1); else COMPRESS=(gzip -1); fi
  # Write via .tmp + mv: a mid-save failure must not clobber the tar the
  # cache action restored — that partial set is still warm for the next run.
  # A failed save degrades to a warning (the run's images are pulled and the
  # suite can proceed); only unfetched refs fail the step below.
  if docker save "${present_refs[@]}" | "${COMPRESS[@]}" > "$CACHE_TAR.tmp"; then
    mv "$CACHE_TAR.tmp" "$CACHE_TAR"
    printf 'pre-pull: wrote %s (%d refs)\n' "$CACHE_TAR" "${#present_refs[@]}"
  else
    rm -f "$CACHE_TAR.tmp"
    printf '::warning::pre-pull: cache tar write failed — restored tar left intact\n'
  fi
fi

if (( ${#failed[@]} > 0 )); then
  printf '::error::pre-pull: %d image(s) unpulled: %s\n' "${#failed[@]}" "${failed[*]}"
  exit 1
fi
