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
# /build is a FILTERED copy of /src, produced by scripts/lib/in-image-copy-src.sh
# (node_modules and .terraform excluded — the next command, `npm ci`, rebuilds the
# former and nothing here reads the latter; #7007). $APP_DIR must therefore carry
# that file: the /src contract is "a directory carrying its own copy tool at
# scripts/lib/in-image-copy-src.sh", not "any directory".
#
# Auth: the capture drives one real (paid) Haiku turn; ANTHROPIC_API_KEY must be
# exported (the gate only reaches here when creds are present). permissionMode is
# "default" (NOT bypassPermissions, which claude.exe refuses under the container's
# root) — see sandbox-canary.mjs.
set -euo pipefail

# An xtrace of this script would print the credential bound below into whatever
# captures stderr (see #7797). Refuse rather than trace.
case "$-" in
  *x*)
    if [ -n "${ANTHROPIC_API_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

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
# The in-image bun is the CI-pinned one (.bun-version, consumed by setup-bun in
# ci.yml): bun.sh/install takes a `bun-v<version>` argument, so the canary runs on
# the same runtime as every other bun surface instead of whatever bun.sh serves.
# Read host-side: /src is apps/web-platform, and the pin lives at the repo root.
BUN_VERSION="$(tr -d '[:space:]' < .bun-version)"
export BUN_VERSION # `docker run -e NAME` reads the client ENVIRONMENT, not shell variables

# SANDBOX_CANARY_MODE=capture (#8623; ADR-079 amendment) re-captures the
# committed fixture INSIDE the same image instead of verifying it, and copies it
# out through a writable /out mount. Default stays `verify` (the CI gate).
MODE="${SANDBOX_CANARY_MODE:-verify}"
case "$MODE" in
  verify) OUT_MOUNT=() ;;
  capture) OUT_MOUNT=(-v "$PWD/$APP_DIR/infra:/out") ;;
  *) printf 'sandbox-canary-verify-in-image: unknown SANDBOX_CANARY_MODE %s\n' "$MODE" >&2; exit 2 ;;
esac
export SANDBOX_CANARY_MODE="$MODE"

docker run --rm \
  -e ANTHROPIC_API_KEY \
  -e BUN_VERSION \
  -e SANDBOX_CANARY_MODE \
  -e SANDBOX_CANARY_CAPTURE=1 \
  -v "$PWD/$APP_DIR:/src:ro" \
  "${OUT_MOUNT[@]}" \
  "$IMG" bash -c '
    set -e
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends socat curl unzip ca-certificates >/dev/null
    bash /src/scripts/lib/in-image-copy-src.sh /src /build
    cd /build
    npm ci --no-audit --no-fund >/dev/null
    curl -fsSL https://bun.sh/install 2>/dev/null | bash -s "bun-v${BUN_VERSION}" >/dev/null
    export PATH="/root/.bun/bin:$PATH"
    if [ "$SANDBOX_CANARY_MODE" = capture ]; then
      bun scripts/sandbox-canary.mjs --capture infra/sandbox-canary-argv.json
      cp infra/sandbox-canary-argv.json /out/sandbox-canary-argv.json
    else
      bun scripts/sandbox-canary.mjs --verify infra/sandbox-canary-argv.json
    fi
  '
