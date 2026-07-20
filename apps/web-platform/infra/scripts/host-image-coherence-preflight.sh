#!/usr/bin/env bash
# Host image/apply coherence preflight (LOAD-BEARING — spec-flow P1-2/P1-4, AC10b).
#
# HOST-AGNOSTIC as of #6575 (2026-07-20). Renamed from web2-recreate-preflight.sh when
# the web-2 dispatch jobs were deleted: the logic never had anything web-2-specific in
# it, only its name and its single call site did. It is RETAINED (not deleted with the
# rest of that surface) because it is named in a procedure an operator can execute
# today — the pinned-image chain in the host_creates HALT.
#
# Runs OFF-HOST, BEFORE the destructive `terraform apply -replace`, to prove the
# pinned `@sha256` image's baked /opt/soleur/host-scripts recompute to the SAME
# combined content-hash that Terraform applied (local.host_scripts_content_hash).
# If they diverge, recreating the host would RE-ABORT at cloud-init stage=verify
# (the `STAGE=verify` block in cloud-init.yml) — the exact ADR-080 stale-image
# trap the hash-verify surfaces. Catching it here means NO destruction happens
# on a doomed boot.
#
# The GOT recompute is BYTE-IDENTICAL to the boot check (the `GOT=$(cd "$SEED"`
# pipeline in cloud-init.yml):
#   find . -type f -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort \
#     | tr -d '\n' | sha256sum | awk '{print $1}'
#
# Extracted + standalone (NOT inline workflow YAML) so a pre-merge test can drive
# it with a mismatching fixture and assert a non-zero exit without any prod write.
#
# Inputs (env):
#   PINNED                 REQUIRED. The frozen pinned image ref
#                          `ghcr.io/jikig-ai/soleur-web-platform@sha256:<64hex>`
#                          (resolved ONCE upstream; AC3b TOCTOU — this script does
#                          NOT re-resolve a tag).
#   INFRA_DIR              terraform root for the WANT hash (default: the script's
#                          ../  = apps/web-platform/infra). Used only when
#                          HOST_SCRIPTS_WANT_HASH is unset.
#
# Test seams (env; unset in prod):
#   HOST_SCRIPTS_WANT_HASH   inject the applied hash instead of `terraform
#                              console local.host_scripts_content_hash`.
#   HOST_SCRIPTS_SEED_DIR    inject an already-extracted host-scripts dir instead
#                              of `docker create` + `docker cp` from $PINNED.
#
# Exit: 0 = coherent (safe to -replace); non-zero = ABORT (do NOT -replace).
set -euo pipefail

die() { echo "::error::host-image-coherence-preflight: $*" >&2; exit 1; }

: "${PINNED:?PINNED (pinned @sha256 image ref) is required}"

# 1. Validate the pinned ref shape and extract the digest. Format-validate BEFORE
#    any use (spec-flow P1-2): a moved/garbage tag can never slip through.
DIGEST="${PINNED##*@}"
if [[ "$DIGEST" == "$PINNED" ]]; then
  die "PINNED must be an immutable digest ref (repo@sha256:<64hex>), got '${PINNED}' (no @digest)."
fi
if [[ ! "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  die "PINNED digest '${DIGEST}' is not ^sha256:[0-9a-f]{64}\$ — refusing to proceed."
fi

# 2. WANT = the applied combined content-hash (single source of truth: terraform
#    console local.host_scripts_content_hash — do NOT re-implement the file list
#    in bash, which would drift from server.tf's lockstep-with-Dockerfile list).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${INFRA_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
if [[ -n "${HOST_SCRIPTS_WANT_HASH:-}" ]]; then
  WANT="$HOST_SCRIPTS_WANT_HASH"
else
  WANT="$(cd "$INFRA_DIR" && terraform console <<<'local.host_scripts_content_hash' | tr -d '"')" \
    || die "terraform console failed to resolve local.host_scripts_content_hash."
fi
if [[ ! "$WANT" =~ ^[0-9a-f]{64}$ ]]; then
  die "applied hash WANT='${WANT}' is not ^[0-9a-f]{64}\$ (terraform console failure or unresolved vars)."
fi

# 3. Extract the pinned image's baked host-scripts. In prod, docker-cp them out of
#    a `docker create` container; in tests, use the injected seed dir.
CLEANUP_DIR=""
if [[ -n "${HOST_SCRIPTS_SEED_DIR:-}" ]]; then
  SEED="$HOST_SCRIPTS_SEED_DIR"
  [[ -d "$SEED" ]] || die "HOST_SCRIPTS_SEED_DIR='${SEED}' is not a directory."
else
  command -v docker >/dev/null 2>&1 || die "docker not available to extract baked host-scripts."
  SEED="$(mktemp -d)"
  CLEANUP_DIR="$SEED"
  CNAME="host-image-coherence-preflight-seed-$$"
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
  docker create --name "$CNAME" "$PINNED" >/dev/null \
    || { rm -rf "$CLEANUP_DIR"; die "docker create from '${PINNED}' failed."; }
  if ! docker cp "$CNAME:/opt/soleur/host-scripts/." "$SEED/"; then
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    rm -rf "$CLEANUP_DIR"
    die "docker cp of /opt/soleur/host-scripts from '${PINNED}' failed."
  fi
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
fi

# 4. Recompute GOT — BYTE-IDENTICAL to the cloud-init boot check (the
#    `GOT=$(cd "$SEED"` pipeline in cloud-init.yml).
GOT="$(cd "$SEED" && find . -type f -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort | tr -d '\n' | sha256sum | awk '{print $1}')" \
  || { [[ -n "$CLEANUP_DIR" ]] && rm -rf "$CLEANUP_DIR"; die "GOT recompute over the baked host-scripts failed."; }
[[ -n "$CLEANUP_DIR" ]] && rm -rf "$CLEANUP_DIR"

if [[ ! "$GOT" =~ ^[0-9a-f]{64}$ ]]; then
  die "recomputed hash GOT='${GOT}' is not ^[0-9a-f]{64}\$ (empty/garbage extraction)."
fi

# 5. The load-bearing comparison.
if [[ "$GOT" != "$WANT" ]]; then
  die "COHERENCE MISMATCH: the pinned digest ${DIGEST} bakes host-scripts hashing to ${GOT}, but the applied local.host_scripts_content_hash is ${WANT}. Creating or replacing a host on this image would RE-ABORT at cloud-init stage=verify, leaving it dark (runcmd is once-per-instance; no reboot repairs it). The checkout has drifted from the pinned image — either pin an older digest whose baked scripts match this tree, or wait for the image rebuild that matches this commit (web-platform-release.yml rebuilds on every merge to main). NOT proceeding."
fi

echo "host-image-coherence-preflight: COHERENT — pinned ${DIGEST} baked host-scripts hash == applied ${WANT}. Safe to -replace."
