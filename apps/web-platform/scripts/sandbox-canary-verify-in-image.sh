#!/usr/bin/env bash
# In-image `--verify` for the faithful sandbox canary (#5913 / ADR-079 deferral B).
#
# The capture-env==replay-env==deploy-image invariant (ADR-079 amendment): the
# SDK's bwrap SETUP argv is a pure function of (SDK version, sandbox config, HOST
# FILESYSTEM). Host-conditional tokens (e.g. `--tmpfs /etc/ssh/ssh_config.d`, only
# emitted when the host has /etc/ssh) mean a capture/verify on the `ubuntu-latest`
# runner (which HAS /etc/ssh) would byte-diff-FAIL against the committed
# `node:22-slim` fixture — or worse, self-consistently pass a fixture that is
# wrong for the prod `node:22-slim` deploy replay. So `--verify` MUST run inside
# the deploy base image. This delegates to a `node:22-slim` container (the deploy
# Dockerfile's `FROM`), installs the SDK via `npm ci` (pinned), and re-captures +
# byte-diffs the committed fixture there. Emits the verify verdict JSON on stdout
# (the SDK-bump gate reads its last line).
#
# Auth: the capture drives one real (paid) Haiku turn; ANTHROPIC_API_KEY must be
# exported (the gate only reaches here when creds are present). permissionMode is
# "default" (NOT bypassPermissions, which claude.exe refuses under the container's
# root) — see sandbox-canary.mjs.
set -euo pipefail

APP_DIR="${SANDBOX_CANARY_APP_DIR:-apps/web-platform}"
# Pin to the same base as apps/web-platform/Dockerfile (keep in sync on a base bump).
IMG="${SANDBOX_CANARY_BASE_IMAGE:-node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d}"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  printf '{"verdict":"canary_infra_error","reason":"creds_absent"}\n'
  exit 0
fi

# Run the whole verify inside the base image. `--verify` re-captures (bwrap is
# replaced by an in-process PATH shim, so no real bubblewrap is needed here) and
# byte-diffs the committed fixture the branch carries. stdout carries the verdict.
docker run --rm \
  -e ANTHROPIC_API_KEY \
  -e SANDBOX_CANARY_CAPTURE=1 \
  -v "$PWD/$APP_DIR:/src:ro" \
  "$IMG" bash -c '
    set -e
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq --no-install-recommends socat curl unzip ca-certificates >/dev/null 2>&1
    cp -r /src /build && cd /build
    npm ci --no-audit --no-fund >/dev/null 2>&1
    curl -fsSL https://bun.sh/install 2>/dev/null | bash >/dev/null 2>&1
    export PATH="/root/.bun/bin:$PATH"
    bun scripts/sandbox-canary.mjs --verify infra/sandbox-canary-argv.json
  '
