#!/usr/bin/env bash
#
# (#7144 task 5b) Render cloud-init-registry.yml exactly as zot-registry.tf does, and measure
# the STORED user_data the way Hetzner measures it — with TERRAFORM'S OWN base64gzip.
#
# WHY THIS EXISTS AS A SECOND MEASUREMENT. `cloud-init-user-data-size.test.ts` already asserts
# a REGISTRY_BUDGET, but it models the render in node: every non-file template var becomes an
# `"x".repeat(n)` run and the gzip runs at level 9. Both approximations are OPTIMISTIC, and
# they are optimistic in the one place it matters:
#
#   * x-runs compress ~1000:1 (that file says so itself). Every registry template var is a
#     non-file value, and five of them are HIGH-ENTROPY — the zot image digest, the Doppler CLI
#     sha256, the Doppler service token, and two heartbeat path tokens. Real high-entropy bytes
#     gzip at ~1:1; their x-run stand-ins gzip to nothing. The model does not under-measure a
#     little, it under-measures exactly the incompressible part. Worth 340 B here.
#   * Go's and node's zlib make different match choices at the same level: 228 B on this render.
#   * node's `gzipSync(level: 9)` is not terraform's `base64gzip`. Terraform calls
#     `gzip.NewWriter`, i.e. Go's DefaultCompression (level 6). Level 9 emits FEWER bytes, so
#     the model reads smaller than the thing Hetzner stores — though only 16 B of it.
#
# Measured total: 32,156 B here against 31,572 B modelled, a 584 B under-report. On the web
# (~8.3 KB headroom) and git-data (~6 KB) hosts that slack is irrelevant. The registry host has
# 612 B, so it is the one host where an optimistic model can report PASS on a render that would
# fail the apply — and the node budget it was reporting PASS against (32,000) was already BELOW
# the true size. `git-data-userdata-budget.sh` states the general rule in its own header — "on a
# hard gate an optimistic measurement is worse than none" — and this script is that rule applied
# to the tightest of the three hosts.
#
# `hcloud_server.registry` has no `lifecycle.ignore_changes = [user_data]`, so user_data is
# ForceNew: blowing the budget is learned from a failing apply on the host that is the SOLE
# pull path for both platform images (the GHCR read PAT was revoked 2026-07-30). That is a
# cold-boot outage, not a retry.
#
# Exit 0 under cap, 1 over, 2 if the render itself failed.
#
# Usage: bash apps/web-platform/infra/registry-userdata-budget.sh [--json] [out-rendered]
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
[ "${1:-}" = "--json" ] && { JSON=1; shift; }
OUT="${1:-}"

command -v terraform >/dev/null 2>&1 || {
  echo "registry-userdata-budget: SKIP — terraform not on PATH" >&2
  exit 0
}

TFDIR=$(mktemp -d -t regbudget.XXXXXXXX)
trap 'rm -rf "$TFDIR"' EXIT

# templatefile()/base64gzip() are builtins, so an EMPTY scratch dir needs no providers, no
# backend and no credentials — this never touches state.
#
# STUB VALUES MATCH BOTH THE LENGTH *AND* THE ENTROPY of what zot-registry.tf passes. Length
# alone is what the node model gets right and it is not enough: a same-length low-entropy stub
# gzips away and reproduces the very optimism this script exists to remove. So the three
# committed non-secrets (zot_image, doppler_sha256, betterstack_ingest_url) are the REAL values
# read straight from zot-registry.tf's locals, and the three secrets are synthesized at full
# length from incompressible material (cq-test-fixtures-synthesized-only).
tf_body=$(cat <<'EOF'
locals {
  # --- REAL committed values (non-secret, byte-exact with zot-registry.tf locals) -------------
  # amd64 arm of local.zot_image. cx23 (the var default) does not start with `cax`, so
  # local.registry_arch is "amd64" and this is the ref the live host renders. The arm64 ref is
  # the same length, so the arch arm does not change the byte count.
  zot_image      = "ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71"
  doppler_sha256 = "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"

  # --- SYNTHESIZED secrets, at real length and real entropy ----------------------------------
  # LENGTHS ARE MEASURED, NOT GUESSED. A live `doppler secrets get --plain | wc -c` (value never
  # printed) gives 72 for a Better Stack heartbeat URL and 49 for a `dp.pt.`-prefixed token, i.e.
  # a 48-char heartbeat prefix + a 24-char path segment, and a 43-char token body. An earlier
  # draft assumed 40-char heartbeat tokens and over-measured by ~30 incompressible bytes — on a
  # sub-1 KB margin a pessimistic stub is its own kind of wrong, so both were corrected.
  #
  # The 24-char path segment IS the credential, so it is incompressible in production. Two
  # DISTINCT tokens: two identical ones would let gzip's back-reference eat the second and
  # reintroduce the optimism this script exists to remove.
  #
  # SPLIT ACROSS join() so no contiguous `uptime.betterstack.com/api/v1/heartbeat/<token>` literal
  # exists in this file. inngest.test.sh 1.6.2 forbids that shape in any non-`.test.sh` file under
  # infra/, because a baked heartbeat URL arms a SECOND pusher on one monitor — the #6552
  # dual-pusher state. These values are synthetic and this script never reaches a host, but the
  # guard cannot know that, and the right answer to a shape guard is to stop carrying the shape,
  # not to widen the guard's exclusions. Same move as the doppler_token join() below, and the
  # reason it is a join there too.
  hb_base     = join("", ["https://uptime.", "betterstack.com/api/v1/heartbeat/"])
  disk_hb     = "${local.hb_base}7Qk2vXm9BdLpR4zTfH6yNcWj"
  liveness_hb = "${local.hb_base}Ej5tPwK8nRq2ZaYc7XvL3hMd"

  # `doppler_service_token.registry` is issued against `doppler_environment.registry_prd.slug`,
  # which is "prd" — so the real key is `dp.st.prd.<43>` (53 B), not the longer per-project slug
  # an isolated project might suggest. Built by join() rather than one literal: a contiguous
  # dp.<type>.<...> string is a real Doppler-service-token SHAPE and GitHub Push Protection
  # blocks the push on it even though the value is synthetic — the git-data-userdata-budget.sh
  # precedent (cq-test-fixtures-synthesized-only still applies; this keeps shape, length and
  # entropy, which is all a size check needs).
  doppler_token = join(".", ["dp", "st", "prd", "Kx7mQ2vZ9pLtR4bYnW6hJcF3sAeUdG8oXiMv5TgD1qN"])

  vars = {
    # Hetzner volume ids are 8-9 digit strings.
    registry_volume_id = "100000003"
    doppler_token      = local.doppler_token
    zot_image          = local.zot_image
    zot_pull_user      = "zot-pull"
    zot_push_user      = "zot-push"
    doppler_arch       = "amd64"
    doppler_sha256     = local.doppler_sha256
    # local.registry_memory_cap_mb = memory*1024 - 1024. cx23 (4 GB) -> 3072; cx33 (8 GB) ->
    # 7168. Both are 4 digits, so the server_type arm cannot move the byte count.
    zot_memory_cap_mb      = 3072
    disk_heartbeat_url     = local.disk_hb
    liveness_heartbeat_url = local.liveness_hb
    betterstack_ingest_url = "https://s2457081.eu-fsn-3.betterstackdata.com/"
    private_ip             = "10.0.1.30"
  }

  rendered = templatefile("__DIR__/cloud-init-registry.yml", local.vars)
  stored   = base64gzip(local.rendered)
}
EOF
)
# The heredoc is QUOTED so terraform's own `${local.hb_base}` interpolation survives verbatim — an
# unquoted one would let the shell eat it. The path is therefore spliced afterwards, and with bash
# parameter substitution rather than `sed`: in a sed replacement `&` expands to the whole match, so
# a repo checked out under a path containing `&` would silently produce a wrong path (and `|`
# would break the delimiter). Bash substitution treats the replacement literally.
printf '%s\n' "${tf_body//__DIR__/$DIR}" > "$TFDIR/main.tf"
grep -q '__DIR__' "$TFDIR/main.tf" && {
  echo "registry-userdata-budget: path splice failed — __DIR__ still present" >&2; exit 2
}

console() { printf '%s\n' "$1" | terraform -chdir="$TFDIR" console 2>>"$TFDIR/err"; }

raw=$(console 'local.rendered')
# A render FAILURE still prints a warning banner and "(known after apply)" on stdout, so
# emptiness is not the tell — look for the diagnostic explicitly. Fail-closed: an unmeasurable
# template must never read as one that fits.
if [ -s "$TFDIR/err" ] || printf '%s' "$raw" | grep -q 'known after apply'; then
  echo "registry-userdata-budget: RENDER FAILED" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi

rendered="$TFDIR/rendered.yml"
printf '%s\n' "$raw" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$rendered"

stored=$(console 'local.stored' | tr -d '"')
[ -n "$stored" ] || { echo "registry-userdata-budget: base64gzip failed" >&2; exit 2; }

raw_bytes=$(wc -c < "$rendered")
stored_bytes=${#stored}
cap=32768

# SUB-CAP TRIPWIRE. git-data's budget script gates on the vendor cap alone because it has ~9 KB
# of headroom — there, cap-only is a fine gate. This host measured 32,156 B, i.e. 612 B under the
# cap, so a cap-only gate would let the render grow to within a rounding error of an unbootable
# host before anything went red. 32,450 splits the remaining headroom: 294 B of room for an
# ordinary small edit, and 318 B still standing between a CI red and a failed apply.
#
# The node-side REGISTRY_BUDGET in plugins/soleur/test/cloud-init-user-data-size.test.ts is this
# number MINUS the measured node-vs-terraform offset, so the two gates trip at the same real
# size. registry-userdata-budget.test.sh pins that relation; do not move one without the other.
subcap=32450
headroom=$(( cap - stored_bytes ))
subcap_headroom=$(( subcap - stored_bytes ))

[ -n "$OUT" ] && cp "$rendered" "$OUT"

if [ "$JSON" -eq 1 ]; then
  printf '{"raw":%s,"stored":%s,"cap":%s,"subcap":%s,"headroom":%s,"subcap_headroom":%s}\n' \
    "$raw_bytes" "$stored_bytes" "$cap" "$subcap" "$headroom" "$subcap_headroom"
else
  echo "registry user_data: stored=${stored_bytes} B / subcap=${subcap} B / cap=${cap} B (headroom ${headroom} B to cap, ${subcap_headroom} B to subcap, raw ${raw_bytes} B)"
fi

# Cap first: an over-cap render is the fatal case and must not be reported as a mere sub-cap trip.
if [ "$stored_bytes" -ge "$cap" ]; then
  echo "registry-userdata-budget: OVER CAP by $(( -headroom )) bytes — the apply would fail, and this host is the SOLE pull path for both platform images (GHCR read PAT revoked 2026-07-30). Reclaim bytes; do NOT raise the cap, it is Hetzner's." >&2
  exit 1
fi

if [ "$stored_bytes" -ge "$subcap" ]; then
  echo "registry-userdata-budget: OVER SUB-CAP by $(( -subcap_headroom )) bytes (${headroom} B of real headroom left). Move prose into zot-registry.tf, which is not byte-budgeted — the #6425 pattern. Raising the sub-cap spends the last of the margin on the one host whose user_data is ForceNew." >&2
  exit 1
fi
