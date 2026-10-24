#!/usr/bin/env bash
# check-inngest-bootstrap-build.sh — the no-push candidate build lane (#8781, option a).
#
# WHY THIS EXISTS. #8747 made build-inngest-bootstrap-image.yml refuse to publish any
# `vinngest-v*` tag whose commit is not on main — correct, but it deleted the ONLY way to
# prove an image-buildable tree before merge: every baked-carrier edit (inngest-bootstrap.sh,
# vector.toml, the redis/cutover/LUKS assets) now goes to merge green with its Dockerfile never
# exercised, and the FIRST build of a broken carrier is the tag mint itself.
#
# WHAT THIS IS. A faithful reproduction of the publish workflow's inline "Build + verify +
# push" step MINUS publication: same pin greps (inngest_cli_version/sha256, vector_version/
# sha256/arm64), same tarball download + sha256 check, same 14-carrier cp staging, same
# Dockerfile heredoc, same `docker build` with the org.opencontainers.image.revision label —
# and NEVER docker push, never cosign, never crane, never a tag bump.
# test-check-inngest-bootstrap-build.sh is the normalized-parity guard keeping the two
# bodies in lockstep — an edit to the publish Build step that is not mirrored here reds.
#
# It is a SCRIPT (not an inline workflow step) for the inverse of the dispatch path's
# constraint: pull_request checks out the PR's own tree, where this script exists.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

REVISION="${GITHUB_SHA:-$(git rev-parse HEAD)}"
[[ "$REVISION" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::REVISION is not a 40-hex commit"; exit 1; }

# ── pin reads (mirrors the publish workflow's pin step byte-for-byte) ─────────────────────
# `|| true` so the ERROR branch below is REACHABLE (#7242 — a no-match grep under
# pipefail would abort before the message).
version=$(grep -E '^\s*inngest_cli_version\s*=' apps/web-platform/infra/inngest.tf | sed -E 's/.*"([^"]+)".*/\1/' || true)
sha=$(grep -E '^\s*inngest_cli_sha256\s*=' apps/web-platform/infra/inngest.tf | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -z "$version" || -z "$sha" ]]; then
  echo "ERROR: failed to extract inngest_cli_version or inngest_cli_sha256 from inngest.tf"
  exit 1
fi
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: inngest_cli_version '$version' is not vX.Y.Z"; exit 1
fi
if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: inngest_cli_sha256 is not a 64-hex-char SHA256"; exit 1
fi
INNGEST_VERSION="$version"
INNGEST_SHA256="$sha"

v_version=$(grep -E '^\s*vector_version\s*=' apps/web-platform/infra/vector.tf | sed -E 's/.*"([^"]+)".*/\1/' || true)
v_sha=$(grep -E '^\s*vector_sha256\s*=' apps/web-platform/infra/vector.tf | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -n "$v_version" && ! "$v_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: vector_version '$v_version' is not X.Y.Z (no 'v' prefix per packages.timber.io)"; exit 1
fi
if [[ -n "$v_sha" && ! "$v_sha" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: vector_sha256 is not a 64-hex-char SHA256"; exit 1
fi
# #6197: format-guard the arm64 Vector SHA local too (templatefile consumer, not an image env).
v_sha_arm64=$(grep -E '^\s*vector_sha256_arm64\s*=' apps/web-platform/infra/vector.tf | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -n "$v_sha_arm64" && ! "$v_sha_arm64" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: vector_sha256_arm64 is not a 64-hex-char SHA256"; exit 1
fi
VECTOR_VERSION="$v_version"
VECTOR_SHA256="$v_sha"

# ── Build (mirrors the publish workflow's Build step, minus `docker push`) ────────────────
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

# SHA256-verify the inngest-cli binary at build time. If this fails,
# the build fails — runtime never sees a tampered binary.
curl -fsSL -o "$BUILD_DIR/inngest.tar.gz" \
  "https://github.com/inngest/inngest/releases/download/${INNGEST_VERSION}/inngest_${INNGEST_VERSION#v}_linux_amd64.tar.gz"
actual=$(sha256sum "$BUILD_DIR/inngest.tar.gz" | awk '{print $1}')
if [[ "$actual" != "$INNGEST_SHA256" ]]; then
  echo "ERROR: SHA256 mismatch at build time — expected $INNGEST_SHA256, got $actual"
  exit 1
fi
echo "Build-time SHA256 verified: $actual"

# Stage bootstrap script + Vector config with version + SHA baked
# in at build time.
cp apps/web-platform/infra/inngest-bootstrap.sh "$BUILD_DIR/inngest-bootstrap.sh"
cp apps/web-platform/infra/vector.toml "$BUILD_DIR/vector.toml"
# Durable Redis assets (#5450) — delivered the same way as vector.toml:
# baked into the image, staged to /tmp at entrypoint, installed by the
# bootstrap script after the Doppler env file exists.
cp apps/web-platform/infra/inngest-redis.conf "$BUILD_DIR/inngest-redis.conf"
cp apps/web-platform/infra/inngest-redis.service "$BUILD_DIR/inngest-redis.service"
cp apps/web-platform/infra/inngest-redis-bootstrap.sh "$BUILD_DIR/inngest-redis-bootstrap.sh"
# Cutover flip trio + arm-atomicity guard (#6178) — dedicated-host only;
# baked here, staged to /tmp at entrypoint, installed (gated on the
# soleur-inngest project) by inngest-bootstrap.sh.
cp apps/web-platform/infra/inngest-cutover-flip.sh "$BUILD_DIR/inngest-cutover-flip.sh"
cp apps/web-platform/infra/inngest-server-flip-guard.sh "$BUILD_DIR/inngest-server-flip-guard.sh"
cp apps/web-platform/infra/cat-inngest-cutover-state.sh "$BUILD_DIR/cat-inngest-cutover-state.sh"
cp apps/web-platform/infra/inngest-cutover-flip.service "$BUILD_DIR/inngest-cutover-flip.service"
cp apps/web-platform/infra/inngest-cutover-flip.timer "$BUILD_DIR/inngest-cutover-flip.timer"

# Conditional Vector env block — empty pin values produce empty
# ENV lines, which the bootstrap script's `${VECTOR_CLI_VERSION:-}`
# guard treats as "skip Vector install".
cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE
FROM alpine:3.20
RUN apk add --no-cache bash curl tar coreutils
ENV INNGEST_CLI_VERSION=${INNGEST_VERSION}
ENV INNGEST_CLI_SHA256=${INNGEST_SHA256}
ENV VECTOR_CLI_VERSION=${VECTOR_VERSION}
ENV VECTOR_CLI_SHA256=${VECTOR_SHA256}
COPY inngest-bootstrap.sh /inngest-bootstrap.sh
COPY vector.toml /vector.toml
COPY inngest-redis.conf /inngest-redis.conf
COPY inngest-redis.service /inngest-redis.service
COPY inngest-redis-bootstrap.sh /inngest-redis-bootstrap.sh
COPY inngest-cutover-flip.sh /inngest-cutover-flip.sh
COPY inngest-server-flip-guard.sh /inngest-server-flip-guard.sh
COPY cat-inngest-cutover-state.sh /cat-inngest-cutover-state.sh
COPY inngest-cutover-flip.service /inngest-cutover-flip.service
COPY inngest-cutover-flip.timer /inngest-cutover-flip.timer
RUN chmod +x /inngest-bootstrap.sh /inngest-redis-bootstrap.sh /inngest-cutover-flip.sh /inngest-server-flip-guard.sh /cat-inngest-cutover-state.sh
# The bootstrap script reads /tmp/vector.toml + /tmp/inngest-redis.* +
# /tmp/inngest-cutover-flip.* (flip trio + guard, #6178) at install time;
# stage the OCI-bundled assets there at entrypoint.
ENTRYPOINT ["/bin/bash", "-c", "cp /vector.toml /tmp/vector.toml && cp /inngest-redis.conf /inngest-redis.service /inngest-redis-bootstrap.sh /tmp/ && cp /inngest-cutover-flip.sh /inngest-server-flip-guard.sh /cat-inngest-cutover-state.sh /inngest-cutover-flip.service /inngest-cutover-flip.timer /tmp/ && /inngest-bootstrap.sh"]
DOCKERFILE

# The candidate tag is LOCAL-ONLY: -t names it so `docker build` output is inspectable,
# nothing with this name ever leaves the runner (no push, no registry credentials here —
# the workflow carries permissions: contents:read and no login step).
docker build --label "org.opencontainers.image.revision=$REVISION" \
  -t "inngest-bootstrap-candidate:${REVISION:0:12}" "$BUILD_DIR"
echo "Candidate build OK (nothing pushed — this lane verifies buildability only)."
