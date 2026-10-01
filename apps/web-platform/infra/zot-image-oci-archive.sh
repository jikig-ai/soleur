#!/usr/bin/env bash
# zot-image-oci-archive.sh — build or verify the release asset the zot registry host boots from
# (#8714 step 5.3b-iii; ADR-096 amendment 2026-09-28).
#
# WHY THIS EXISTS. The registry host cannot pull its own zot image from itself (bootstrap
# paradox), and project-zot publishes images only on ghcr.io. So the exact upstream image — the
# manifest pinned by digest D in zot-registry.tf `zot_image_amd64` and every blob it names — is
# packaged as ONE tarball and published as a GitHub release asset. The host checks the tarball's
# pinned sha256 (T), `docker load`s it and refuses to start zot unless the loaded image ID is the
# upstream config digest C (classic image store) or D (containerd store).
#
# The tarball is simultaneously:
#   - an OCI image layout (oci-layout, index.json -> D, blobs/sha256/*) — the containerd store's
#     `docker load` path; index.json names a FULLY-QUALIFIED local ref, because the containerd
#     store does not normalise a short name and `docker image inspect <short>` then fails after a
#     successful load (measured 2026-09-28, docker 29.7.2);
#   - a legacy docker-save archive (manifest.json -> config + layers) — the classic store's path.
# Both views reference the SAME upstream blobs byte-for-byte; nothing is re-compressed.
#
# REPRODUCIBLE BY CONSTRUCTION: every member is written from the manifest, and the tar is
# normalised (sorted, mtime 0, uid/gid 0, ustar). T is therefore a function of D and the GNU tar
# version, which is why the publishing/rehearsal jobs pin their runner image.
#
# Usage:
#   zot-image-oci-archive.sh build  <out.tar>   fetch D + blobs anonymously from ghcr.io, verify
#                                               every digest, write the archive, print C= / T=
#   zot-image-oci-archive.sh names              print D= VERSION= LOCAL_REF= TAG= ASSET= from the pin
#                                               (no network, no writes)
#   zot-image-oci-archive.sh verify <in.tar>    content check of an existing archive against D:
#                                               exact member set, every blob hashes to its name,
#                                               index.json -> D, manifest.json agrees with D
# Env: ZOT_REGISTRY_TF (default: zot-registry.tf beside this script).
# Exit: 0 ok · 1 refused (a digest/content check failed) · 2 usage/config error.
set -euo pipefail

TF="${ZOT_REGISTRY_TF:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zot-registry.tf}"
ARCH=amd64
LOCAL_REPO="localhost/soleur-mirror/zot-linux-${ARCH}"

die() { echo "zot-image-oci-archive: $2" >&2; exit "$1"; }

# The canonical absolute-path guard (a COPY of plugins/soleur/test/test-helpers.sh — do not reword
# it here only): every write below lands under $W, and $W is proven absolute before the first one.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# One scratch dir per run, bound at top level and owned by the EXIT trap. Two fixed subtrees:
# $W/img (the archive being built or extracted) and $W/views (verify's re-derived views).
W="$(mktemp -d)" || die 2 "mktemp failed"
assert_fixture_dir "$W"
trap 'rm -rf "$W"' EXIT

# ── the upstream pin record: ghcr.io/<repo>:<version>@sha256:<D> ─────────────────────────────────
[[ -r "$TF" ]] || die 2 "cannot read $TF"
# The upstream OWNER is fixed here, not read from the pin: the published release's notes name
# project-zot, so a lookalike owner in a pin must be refused rather than packaged under that name.
PIN="$(grep -oE "^[[:space:]]*zot_image_${ARCH}[[:space:]]*=[[:space:]]*\"ghcr\.io/project-zot/zot-linux-${ARCH}:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}\"[[:space:]]*$" "$TF" || true)"
[[ "$(printf '%s' "$PIN" | grep -c . || true)" == 1 ]] \
  || die 2 "expected exactly one digest-pinned zot_image_${ARCH} line in $TF"
REF="$(printf '%s' "$PIN" | grep -oE 'ghcr\.io/[^"]+')" || die 2 "could not extract the ref from the zot_image_${ARCH} line"
REPO="${REF#ghcr.io/}"; REPO="${REPO%%:*}"
VERSION="${REF##*:v}"; VERSION="v${VERSION%%@*}"
D="${REF##*@sha256:}"
LOCAL_REF="${LOCAL_REPO}:${VERSION}"
# Release naming, derived ONCE in bash here: the publish workflow and registry-replace-preflight.sh
# (P6, --print-asset, --check-asset; via the `names` mode below) consume it. zot-registry.tf's
# zot-mirror locals derive the same names in HCL; zot-image-fetch.test.sh pins the two equal.
# The tag carries D's 12-hex prefix: this repo's releases are IMMUTABLE once published, so a re-tagged
# upstream version (same version, new digest) must land under a NEW tag rather than collide forever.
TAG="zot-image-${VERSION}-${D:0:12}"
ASSET="zot-linux-${ARCH}-${VERSION}.oci.tar"

sha() { sha256sum "$1" | cut -d' ' -f1; }
# ustar + sorted + epoch mtime + root owner: the bytes depend only on the member contents.
pack() { tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --format=ustar \
  --mode='a=rX,u+w' -C "$1" -cf "$2" oci-layout index.json manifest.json blobs; }

# write_views <img|views> — index.json + manifest.json + oci-layout for $W/<sub>, derived from
# $W/<sub>/blobs/sha256/<D>.
write_views() {
  assert_fixture_dir "$W"
  local m="$W/$1/blobs/sha256/$D"
  printf '{"imageLayoutVersion":"1.0.0"}' > "$W/$1/oci-layout"
  jq -cn --arg mt "$(jq -r .mediaType "$m")" --arg d "sha256:$D" --argjson sz "$(stat -c %s "$m")" \
    --arg name "$LOCAL_REF" --arg tag "$VERSION" \
    '{schemaVersion:2,mediaType:"application/vnd.oci.image.index.v1+json",
      manifests:[{mediaType:$mt,digest:$d,size:$sz,
        annotations:{"io.containerd.image.name":$name,"org.opencontainers.image.ref.name":$tag}}]}' > "$W/$1/index.json"
  jq -c --arg name "$LOCAL_REF" \
    '[{Config:("blobs/sha256/"+(.config.digest|ltrimstr("sha256:"))),RepoTags:[$name],
       Layers:[.layers[].digest|ltrimstr("sha256:")|"blobs/sha256/"+.]}]' "$m" > "$W/$1/manifest.json"
}

# referenced <manifest-file> — every blob hex the manifest names (config first, layers in order).
referenced() { jq -r '.config.digest, .layers[].digest' "$1" | sed 's/^sha256://'; }

build() {
  local out="$1" tok h
  # The output path is made absolute here, so every write in this function is under a proven root.
  case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
  assert_fixture_dir "$W"; assert_fixture_dir "$out"
  mkdir -p "$W/img/blobs/sha256"
  tok="$(curl -fsS --proto =https --retry 3 "https://ghcr.io/token?scope=repository:${REPO}:pull" | jq -er .token)" \
    || die 1 "could not obtain an anonymous ghcr.io pull token for ${REPO}"
  curl -fsSL --proto =https --proto-redir =https --retry 3 -H "Authorization: Bearer ${tok}" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${REPO}/manifests/sha256:${D}" > "$W/img/blobs/sha256/$D" \
    || die 1 "could not fetch manifest sha256:${D}"
  [[ "$(sha "$W/img/blobs/sha256/$D")" == "$D" ]] || die 1 "manifest bytes do not hash to the pinned D sha256:${D}"
  for h in $(referenced "$W/img/blobs/sha256/$D"); do
    [[ "$h" =~ ^[0-9a-f]{64}$ ]] || die 1 "manifest names a malformed digest: $h"
    curl -fsSL --proto =https --proto-redir =https --retry 3 -H "Authorization: Bearer ${tok}" \
      "https://ghcr.io/v2/${REPO}/blobs/sha256:${h}" > "$W/img/blobs/sha256/$h" || die 1 "could not fetch blob sha256:${h}"
    [[ "$(sha "$W/img/blobs/sha256/$h")" == "$h" ]] || die 1 "blob bytes do not hash to sha256:${h}"
  done
  write_views img
  pack "$W/img" "$W/out.tar" && mv -f "$W/out.tar" "$out"
  echo "D=$D"
  echo "C=$(jq -r .config.digest "$W/img/blobs/sha256/$D" | sed 's/^sha256://')"
  echo "T=$(sha "$out")"
  echo "BYTES=$(stat -c %s "$out")"
  echo "LOCAL_REF=$LOCAL_REF"
  echo "TAG=$TAG"
  echo "ASSET=$ASSET"
}

verify() {
  local in="$1" h want got
  [[ -r "$in" ]] || die 2 "cannot read $in"
  assert_fixture_dir "$W"
  mkdir -p "$W/img" "$W/views/blobs/sha256"
  # Members are checked BEFORE extraction: only the layout's own names, each once, and only regular
  # files or directories. A symlink/hardlink/FIFO/device member is refused here, not after extraction
  # (a FIFO hangs sha256sum; an absolute symlink would make the digest checks read the runner's files).
  got="$(tar -tf "$in" | LC_ALL=C sort)" || die 1 "not a readable tar: $in"
  printf '%s\n' "$got" | grep -qvE '^(oci-layout|index\.json|manifest\.json|blobs/|blobs/sha256/|blobs/sha256/[0-9a-f]{64})$' \
    && die 1 "archive carries a member outside the OCI layout"
  [[ -z "$(printf '%s\n' "$got" | uniq -d)" ]] || die 1 "archive carries a duplicate member"
  tar -tvf "$in" | cut -c1 | grep -qv '^[-d]$' && die 1 "archive carries a non-regular member (link, FIFO or device)"
  tar -xf "$in" -C "$W/img" --no-same-owner
  [[ -z "$(find "$W/img" -mindepth 1 ! -type f ! -type d -print -quit)" ]] \
    || die 1 "archive extracted a non-regular member (link, FIFO or device)"
  [[ -f "$W/img/blobs/sha256/$D" ]] || die 1 "archive does not carry the pinned manifest sha256:${D}"
  [[ "$(sha "$W/img/blobs/sha256/$D")" == "$D" ]] || die 1 "manifest blob does not hash to D"
  want="$( { printf '%s\n' blobs/ blobs/sha256/ index.json manifest.json oci-layout "blobs/sha256/$D"
            referenced "$W/img/blobs/sha256/$D" | sed 's|^|blobs/sha256/|'; } | LC_ALL=C sort -u)"
  [[ "$got" == "$want" ]] || die 1 "archive member set is not exactly the layout for D (extra or missing members)"
  for h in $(referenced "$W/img/blobs/sha256/$D"); do
    [[ "$(sha "$W/img/blobs/sha256/$h")" == "$h" ]] || die 1 "blob does not hash to its name: sha256:${h}"
  done
  # The two load-path views must be exactly what write_views derives from D.
  cp "$W/img/blobs/sha256/$D" "$W/views/blobs/sha256/$D"
  write_views views
  for f in oci-layout index.json manifest.json; do
    cmp -s "$W/img/$f" "$W/views/$f" || die 1 "$f does not match the view derived from D"
  done
  echo "verified D=$D LOCAL_REF=$LOCAL_REF T=$(sha "$in")"
}

case "${1:-}" in
  names)  [[ $# -eq 1 ]] || die 2 "usage: $0 names"
          printf 'D=%s\nVERSION=%s\nLOCAL_REF=%s\nTAG=%s\nASSET=%s\n' "$D" "$VERSION" "$LOCAL_REF" "$TAG" "$ASSET" ;;
  build)  [[ $# -eq 2 ]] || die 2 "usage: $0 build <out.tar>";  build "$2" ;;
  verify) [[ $# -eq 2 ]] || die 2 "usage: $0 verify <in.tar>"; verify "$2" ;;
  *) die 2 "usage: $0 {names|build <out.tar>|verify <in.tar>}" ;;
esac
