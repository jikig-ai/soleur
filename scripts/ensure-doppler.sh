#!/usr/bin/env bash
# Ensure the Doppler CLI is on PATH. If missing, install the checksum-verified
# release binary into ~/.local/bin. On success prints the path to the doppler
# binary and exits 0. On failure prints a diagnostic to stderr and exits
# non-zero so callers can abort rather than misreport the capability.
#
# WHY THIS EXISTS, AND WHY IT IS NOT A CONVENIENCE. Every no-SSH host read in
# this repo is gated on Doppler: `scripts/betterstack-query.sh` needs
# BETTERSTACK_QUERY_* injected via `doppler run`, and the runbook's "Reading host
# state without SSH" recipe reads WEBHOOK_DEPLOY_SECRET / CF_ACCESS_* the same
# way. On a machine without the binary, an agent runs `doppler run ...`, sees
# `command not found`, and concludes THE SESSION HAS NO OBSERVABILITY ACCESS —
# then falls back to waiting on an hourly probe, or worse, reaches for SSH
# (hr-no-ssh-fallback-in-runbooks). Measured 2026-09-17: exactly that, during an
# inngest host replace, where the operator-visible cost was a 20-minute blind
# spot on a production scheduler. A missing CLI is an INSTALL, not a verdict.
#
# INSTALL METHOD — the GitHub release tarball, checksum-verified, to a user path.
# Deliberately NOT `curl -Ls https://cli.doppler.com/install.sh | sudo sh`, which
# is Doppler's documented one-liner: it pipes a remote script into a root shell,
# so a compromised or MITM'd script executes as root with no verification step,
# and it needs sudo this repo's agents do not have non-interactively. The tarball
# path verifies a published sha256 BEFORE the bytes are made executable and needs
# no privilege escalation.
#
# THIS SCRIPT NEVER AUTHENTICATES. `doppler login` is an interactive browser
# flow; a service token is the non-interactive alternative and is the operator's
# to mint. Three states are distinct and a caller must not collapse them, because
# each has a DIFFERENT fix and only the first is this script's job:
#
#   missing         the binary is absent          -> run this script
#   unauthenticated binary present, no token      -> operator runs `doppler login`
#                                                    (interactive) or exports
#                                                    DOPPLER_TOKEN
#   ready           authenticated                 -> wrap the call in `doppler run`
#
# `--state` prints exactly one of those words and exits 0, so a caller can branch
# without parsing Doppler's human-facing error text. Collapsing `unauthenticated`
# into `missing` is the misdiagnosis this whole file exists to prevent.
#
# Exit codes:
#   0 - doppler available on PATH (pre-installed or just installed), or --state answered
#   1 - install attempted but failed (download, checksum, or extract)
#   2 - no install path available (curl, tar, or sha256sum missing)

set -euo pipefail

DOPPLER_VERSION="${DOPPLER_VERSION:-3.76.5}"
INSTALL_DIR="${DOPPLER_INSTALL_DIR:-$HOME/.local/bin}"

if [[ "${1:-}" == "--state" ]]; then
  bin=""
  if command -v doppler >/dev/null 2>&1; then
    bin="$(command -v doppler)"
  elif [[ -x "$INSTALL_DIR/doppler" ]]; then
    bin="$INSTALL_DIR/doppler"
  fi
  if [[ -z "$bin" ]]; then
    echo missing
    exit 0
  fi
  # MEASURED 2026-09-17 (v3.76.5): `doppler me` writes its error to STDERR and
  # exits 1 when no token is configured. An earlier revision of this block
  # asserted the opposite — exit 0, error on stdout — and matched on the message
  # text as a result; it reported `ready` against a CLI that had never been
  # authenticated. That false reading came from `doppler me 2>&1 | head`, where
  # `$?` is head's status, not doppler's. Do not re-derive this through a pipe.
  #
  # rc is necessary but not sufficient: a network fault also exits non-zero, and
  # calling that `unauthenticated` would send the operator to a login flow that
  # fixes nothing. So rc selects the non-ready branch and the message
  # discriminates within it; anything unrecognised is `unknown`, never a guess.
  err=""
  rc=0
  err="$("$bin" me 2>&1 >/dev/null)" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo ready
  elif grep -qiE 'must provide a token|not authenticated|invalid token|unauthorized' <<<"$err"; then
    echo unauthenticated
  else
    echo unknown
  fi
  exit 0
fi

if command -v doppler >/dev/null 2>&1; then
  command -v doppler
  exit 0
fi

# A prior run of this script installs here but cannot edit the caller's PATH.
if [[ -x "$INSTALL_DIR/doppler" ]]; then
  echo "doppler present at $INSTALL_DIR/doppler but not on PATH — add it:" >&2
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\"" >&2
  echo "$INSTALL_DIR/doppler"
  exit 0
fi

echo "doppler not found on PATH — attempting install ${DOPPLER_VERSION}" >&2

for tool in curl tar sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool is required to install doppler and is not available" >&2
    exit 2
  fi
done

case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *)
    echo "ERROR: unsupported architecture $(uname -m) — install doppler manually" >&2
    exit 2
    ;;
esac

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macOS ;;
  *)
    echo "ERROR: unsupported OS $(uname -s) — install doppler manually" >&2
    exit 2
    ;;
esac

tarball="doppler_${DOPPLER_VERSION}_${os}_${arch}.tar.gz"
base="https://github.com/DopplerHQ/cli/releases/download/${DOPPLER_VERSION}"

workdir="$(mktemp -d)"
# Keep the temp tree out of the repo and clear it on every exit path, including
# the checksum failure below — a half-downloaded tarball left on disk is the
# shape a later run would happily extract.
trap 'rm -rf "$workdir"' EXIT

if ! curl -fsSL -o "$workdir/$tarball" "$base/$tarball"; then
  echo "ERROR: could not download $base/$tarball" >&2
  exit 1
fi

if ! curl -fsSL -o "$workdir/checksums.txt" "$base/checksums.txt"; then
  echo "ERROR: could not download $base/checksums.txt — refusing to install unverified bytes" >&2
  exit 1
fi

# Verify BEFORE the bytes become executable. `grep` first so a checksums.txt that
# does not mention this tarball fails loudly instead of `sha256sum -c` reporting
# a vacuous success on an empty input list.
if ! grep -F "$tarball" "$workdir/checksums.txt" > "$workdir/expected.txt"; then
  echo "ERROR: $tarball absent from checksums.txt — refusing to install" >&2
  exit 1
fi

if ! (cd "$workdir" && sha256sum -c expected.txt >/dev/null 2>&1); then
  echo "ERROR: sha256 mismatch for $tarball — refusing to install" >&2
  exit 1
fi

if ! tar xzf "$workdir/$tarball" -C "$workdir" doppler; then
  echo "ERROR: could not extract doppler from $tarball" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
if ! install -m 0755 "$workdir/doppler" "$INSTALL_DIR/doppler"; then
  echo "ERROR: could not install doppler to $INSTALL_DIR" >&2
  exit 1
fi

echo "doppler ${DOPPLER_VERSION} installed to $INSTALL_DIR/doppler" >&2
if ! command -v doppler >/dev/null 2>&1; then
  echo "NOTE: $INSTALL_DIR is not on PATH for this shell — add it:" >&2
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\"" >&2
fi

echo "$INSTALL_DIR/doppler"
