---
title: "fix(sec): add checksum verification and version pinning to check_deps.sh"
type: fix
date: 2026-03-20
semver: patch
---

# fix(sec): Add Checksum Verification and Version Pinning to check_deps.sh

## Overview

`check_deps.sh` in the feature-video skill downloads ffmpeg and rclone binaries over HTTPS without checksum verification or version pinning. A compromised CDN or supply-chain attack would result in arbitrary code execution. This was flagged by the security-sentinel agent during review of PR #949.

## Problem Statement

Two security gaps exist in `plugins/soleur/skills/feature-video/scripts/check_deps.sh`:

1. **No checksum verification**: Both `install_ffmpeg_linux` (line 26) and `install_rclone_linux` (line 44) download and install binaries without verifying integrity via SHA256.

2. **Mutable "latest" URLs**: Both download URLs resolve to floating latest versions:
   - ffmpeg: `ffmpeg-release-${arch_suffix}-static.tar.xz` (johnvansickle.com, no version in URL)
   - rclone: `rclone-current-linux-${arch_suffix}.zip` (resolves to latest)

   This makes installs non-reproducible and prevents auditing which version was installed.

## Proposed Solution

### Phase 1: Version Constants and Pinned URLs

Add version constants at the top of `check_deps.sh`:

```text
RCLONE_VERSION="1.69.1"
FFMPEG_AUTOBUILD="2026-03-20-13-06"
```

Update download URLs to use versioned paths:
- rclone: `https://downloads.rclone.org/v<RCLONE_VERSION>/rclone-v<RCLONE_VERSION>-linux-<arch_suffix>.zip`
- ffmpeg: switch from johnvansickle.com to BtbN GitHub releases which provide versioned URLs and SHA256: `https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-<FFMPEG_AUTOBUILD>/ffmpeg-master-latest-<platform>-gpl.tar.xz`

**ffmpeg source change rationale**: johnvansickle.com publishes only `.md5` sidecars and uses floating URLs without version numbers. BtbN/FFmpeg-Builds provides:
- Dated autobuild tags (`autobuild-YYYY-MM-DD-HH-MM`) for reproducibility
- `checksums.sha256` file per release
- Both linux64 and linuxarm64 static builds
- GPL and LGPL variants

### Phase 2: SHA256 Checksum Constants

Embed expected SHA256 checksums as constants alongside the version pins:

```text
# rclone checksums (from https://downloads.rclone.org/v<VERSION>/SHA256SUMS)
RCLONE_SHA256_AMD64="<hash>"
RCLONE_SHA256_ARM64="<hash>"

# ffmpeg checksums (from BtbN checksums.sha256)
FFMPEG_SHA256_LINUX64="<hash>"
FFMPEG_SHA256_LINUXARM64="<hash>"
```

**Why embed rather than download SHA256SUMS at install time?** Downloading the checksum file from the same server as the binary provides no protection against a compromised CDN -- the attacker would replace both files. Embedding the checksum in the script (which is committed to git) means the expected hash is versioned and reviewable.

### Phase 3: Verification Function

Add a `verify_checksum` helper function:

```text
verify_checksum() {
  local file="<file>"
  local expected="<expected>"
  local actual
  actual=$(sha256sum "<file>" | cut -d' ' -f1)
  if [[ "<actual>" != "<expected>" ]]; then
    echo "  CHECKSUM MISMATCH for <file>" >&2
    echo "  Expected: <expected>" >&2
    echo "  Got:      <actual>" >&2
    rm -f "<file>"
    return 1
  fi
  echo "  [ok] checksum verified"
}
```

Integrate into both `install_ffmpeg_linux` and `install_rclone_linux`:
1. Download to a temp file (not pipe to tar)
2. Verify checksum
3. Extract/install only on success
4. Clean up temp file

### Phase 4: Architecture Mapping Update

Update the architecture mapping for BtbN naming conventions:
- `x86_64` maps to `linux64` (not `amd64`)
- `aarch64`/`arm64` maps to `linuxarm64` (not `arm64`)

The rclone mapping stays as-is (`amd64`/`arm64`).

## Technical Considerations

### Download Flow Change

The current ffmpeg install pipes `curl | tar` directly, which prevents checksum verification. The new flow must:
1. `curl -sfL -o <tmpfile>` to download
2. `verify_checksum <tmpfile> <expected_hash>`
3. `tar -xJf <tmpfile> ...` on success
4. `rm -f <tmpfile>` cleanup

### Temp Directory Handling

The rclone installer already uses `mktemp -d`. The ffmpeg installer needs the same pattern. Both should clean up on both success and failure paths.

### No `set -euo pipefail`

The script header comment explains: "No set -euo pipefail: soft dependency checks and install failures must not abort the script." The `verify_checksum` function must use explicit return codes rather than relying on `set -e`.

### macOS Path

The macOS install path (brew) is unaffected -- Homebrew handles its own integrity verification. No changes needed for macOS.

### Updating Checksums

When updating pinned versions, the maintainer must:
1. Update `RCLONE_VERSION` or `FFMPEG_AUTOBUILD`
2. Fetch the new SHA256SUMS file
3. Update the embedded hash constants
4. Test on both amd64 and arm64 (or at least the primary dev architecture)

Add a comment block at the top of the version constants section documenting this update procedure.

## Attack Surface Enumeration

All code paths that download and install binaries in `check_deps.sh`:

| Path | Current State | After Fix |
|------|--------------|-----------|
| `install_ffmpeg_linux` (line 26-42) | No checksum, floating URL | Pinned version, SHA256 verified |
| `install_rclone_linux` (line 44-69) | No checksum, floating URL | Pinned version, SHA256 verified |
| macOS `brew install` (line 89-94) | Homebrew verifies integrity | No change needed (safe) |
| `install_tool` dispatch (line 71-101) | Routes to above | No change needed (dispatch only) |

No other download paths exist in the script.

## Non-Goals

- Switching the rclone download source (rclone.org is fine, it has proper versioned URLs and SHA256SUMS)
- Adding GPG signature verification (SHA256 from a committed script is sufficient for this threat model)
- Modifying the pencil-setup `check_deps.sh` (it does not download binaries from the web)
- Auto-updating pinned versions (manual update with checksum refresh is the correct workflow)
- Adding checksum verification to macOS brew installs (Homebrew handles this)

## Acceptance Criteria

- [ ] Version constants (`RCLONE_VERSION`, `FFMPEG_AUTOBUILD`) pinned at script top in `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] SHA256 checksum constants embedded for each architecture (amd64/arm64 for rclone, linux64/linuxarm64 for ffmpeg)
- [ ] `verify_checksum` function added and called before extraction for both ffmpeg and rclone
- [ ] ffmpeg source switched from johnvansickle.com to BtbN GitHub releases
- [ ] Download flow changed from `curl | tar` pipe to download-then-verify-then-extract
- [ ] Temp directory cleanup on both success and failure paths
- [ ] Update procedure documented in script comments
- [ ] macOS brew path unchanged
- [ ] Script still works without `set -euo pipefail` (soft failures)
- [ ] Architecture mapping updated for BtbN naming conventions

## Test Scenarios

- Given a clean Linux amd64 system without ffmpeg, when `check_deps.sh --auto` runs, then ffmpeg is downloaded, checksum is verified, and the binary is installed to `~/.local/bin/ffmpeg`
- Given a clean Linux arm64 system without rclone, when `check_deps.sh --auto` runs, then rclone is downloaded with the pinned version URL, checksum is verified, and the binary is installed to `~/.local/bin/rclone`
- Given a corrupted download (simulated by replacing the downloaded file), when checksum verification runs, then the script prints a CHECKSUM MISMATCH error, removes the corrupt file, and returns non-zero
- Given ffmpeg is already installed, when `check_deps.sh` runs, then no download occurs and the script reports `[ok] ffmpeg`
- Given an unsupported architecture, when the install function is called, then it prints an error and returns 1 without attempting download

## Files Modified

- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- version pinning, checksum constants, verify function, updated URLs, architecture mapping

## References

- Issue: #956
- PR #949: sudo removal refactor that introduced the current download pattern
- rclone SHA256SUMS: `https://downloads.rclone.org/v1.69.1/SHA256SUMS` (standard `sha256sum -c` format)
- BtbN FFmpeg Builds: `https://github.com/BtbN/FFmpeg-Builds/releases` (daily autobuilds with `checksums.sha256`)
- rclone latest version: v1.73.2 (from `https://downloads.rclone.org/version.txt`) -- pin to a recent stable release
