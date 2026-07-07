#!/usr/bin/env bash
# In-image runner for the CLAUDE_PLUGIN_ROOT sandbox-propagation probe
# (Slice B / AC7a, #6121). See plugin-root-sandbox-propagation-probe.mjs.
#
# WHY in-image (NOT the runner): the property under test — does the value
# `buildAgentEnv` injects reach the bwrap-SANDBOXED Bash — is a function of the
# SDK's claude-CLI → bwrap env projection, which the SDK exercises only when the
# sandbox actually ENGAGES. The SDK's sandbox availability check requires BOTH
# bubblewrap AND socat; the deploy base image (node:22-slim) ships NEITHER by
# default, so the probe must run in that base image with socat installed to be
# faithful (same capture-env==replay-env==deploy-image invariant as ADR-079's
# sandbox-canary-verify-in-image.sh). bwrap itself is replaced by an in-process
# PATH shim inside the probe (no real bubblewrap needed), but socat must be a
# real binary for the availability check to pass.
#
# Emits the probe verdict JSON on stdout (last line). Exit non-zero on
# `does_not_propagate` (fail-closed) so the CI gate reddens on a regression;
# `infra_error` (no creds / sandbox didn't engage) exits 0 with the verdict for
# the caller to classify (mirrors the canary's ack-fallback posture).
set -euo pipefail

APP_DIR="${PLUGIN_ROOT_PROBE_APP_DIR:-apps/web-platform}"
# Pin to the same base as apps/web-platform/Dockerfile (keep in sync on a base bump).
IMG="${PLUGIN_ROOT_PROBE_BASE_IMAGE:-node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d}"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  printf '{"verdict":"infra_error","reason":"creds_absent"}\n'
  exit 0
fi

docker run --rm \
  -e ANTHROPIC_API_KEY \
  -v "$PWD/$APP_DIR:/src:ro" \
  "$IMG" bash -c '
    set -e
    apt-get update -qq >/dev/null 2>&1
    # socat is required by the SDK sandbox availability check (bwrap is shimmed).
    apt-get install -y -qq --no-install-recommends socat ca-certificates >/dev/null 2>&1
    cp -r /src /build && cd /build
    npm ci --no-audit --no-fund >/dev/null 2>&1
    npm i -g bun@1.3.11 >/dev/null 2>&1
    bun scripts/plugin-root-sandbox-propagation-probe.mjs
  '
