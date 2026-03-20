---
title: "fix(sec): add checksum verification and version pinning to check_deps.sh"
type: fix
date: 2026-03-20
semver: patch
---

# fix(sec): Add Checksum Verification and Version Pinning to check_deps.sh

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research agents used:** security-sentinel, code-simplicity-reviewer, spec-flow-analyzer, WebFetch (rclone SHA256SUMS, BtbN checksums, version.txt)

### Key Improvements

1. **BtbN filename discovery**: Dated autobuild tags use versioned filenames (`ffmpeg-N-123570-gf72f692afa-linux64-gpl.tar.xz`), not `ffmpeg-master-latest-*`. Plan now includes `FFMPEG_BUILD_ID` constant and correct URL construction.
2. **Rclone version updated**: Pin to latest stable 1.73.2 (not 1.69.1) for maximum compatibility.
3. **All 4 SHA256 checksums verified**: Fetched live from both rclone.org and BtbN GitHub for both architectures.
4. **Cleanup pattern aligned**: Uses `trap`-based cleanup pattern from PR #949 learning, not `rm -f` inside `verify_checksum`.
5. **Edge case: `sha256sum` binary mode flag**: On some Linux distros, `sha256sum` outputs with ` *` (binary mode indicator) -- `cut -d' ' -f1` handles this correctly.

### New Considerations Discovered

- BtbN `latest` tag uses `ffmpeg-master-latest-*` filenames, but dated autobuild tags use `ffmpeg-N-<buildnum>-g<hash>-*` filenames -- these are different assets, not aliases
- The `verify_checksum` function should NOT `rm -f` the file (leave cleanup to the caller's trap) to avoid double-free with trap-based cleanup
- The `--wildcards` flag in `tar` extraction for ffmpeg needs updating since BtbN's tarball layout differs from johnvansickle's

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

Add version and build constants at the top of `check_deps.sh`:

```text
# --- Pinned Versions ---
# To update: change version/build constants, fetch new checksums, update SHA256 constants.
# rclone: https://downloads.rclone.org/v<NEW_VERSION>/SHA256SUMS
# ffmpeg: curl -sL https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-<NEW_DATE>/checksums.sha256
RCLONE_VERSION="1.73.2"
FFMPEG_AUTOBUILD="2026-03-20-13-06"
FFMPEG_BUILD_ID="N-123570-gf72f692afa"
```

### Research Insights

**BtbN filename discovery (critical correction):** Dated autobuild tags do NOT use `ffmpeg-master-latest-*` filenames. The actual filenames include the build number and git hash:
- Under `latest` tag: `ffmpeg-master-latest-linux64-gpl.tar.xz`
- Under `autobuild-2026-03-20-13-06` tag: `ffmpeg-N-123570-gf72f692afa-linux64-gpl.tar.xz`

These are different assets. The plan must use the versioned filename with `FFMPEG_BUILD_ID` to match the checksum.

**Verified download URLs:**
- rclone: `https://downloads.rclone.org/v1.73.2/rclone-v1.73.2-linux-amd64.zip` (HTTP 200 confirmed)
- ffmpeg: `https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-03-20-13-06/ffmpeg-N-123570-gf72f692afa-linux64-gpl.tar.xz` (HTTP 302 -> download confirmed)

**ffmpeg source change rationale**: johnvansickle.com publishes only `.md5` sidecars and uses floating URLs without version numbers. BtbN/FFmpeg-Builds provides:
- Dated autobuild tags (`autobuild-YYYY-MM-DD-HH-MM`) for reproducibility
- `checksums.sha256` file per release
- Both linux64 and linuxarm64 static builds
- GPL and LGPL variants

### Phase 2: SHA256 Checksum Constants

Embed expected SHA256 checksums as constants alongside the version pins. All checksums verified live from upstream sources:

```text
# rclone checksums (from https://downloads.rclone.org/v1.73.2/SHA256SUMS)
RCLONE_SHA256_AMD64="00a1d8cb85552b7b07bb0416559b2e78fcf9c6926662a52682d81b5f20c90535"
RCLONE_SHA256_ARM64="2f7d8b807e6ea638855129052c834ca23aa538d3ad7786e30b8ad1e97c5db47b"

# ffmpeg checksums (from BtbN autobuild-2026-03-20-13-06 checksums.sha256)
FFMPEG_SHA256_LINUX64="f550cd5fad7bc9045f9e6b4370204ddd245b8120f6bc193e0c09c58569e3cb32"
FFMPEG_SHA256_LINUXARM64="89b959bed4b6d63bad2d85870468a9a52cf84efd216a12fbf577a011ef391644"
```

**Why embed rather than download SHA256SUMS at install time?** Downloading the checksum file from the same server as the binary provides no protection against a compromised CDN -- the attacker would replace both files. Embedding the checksum in the script (which is committed to git) means the expected hash is versioned and reviewable.

### Phase 3: Verification Function

Add a `verify_checksum` helper function:

```text
verify_checksum() {
  local file="$1"
  local expected="$2"
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ "$actual" != "$expected" ]]; then
    echo "  CHECKSUM MISMATCH for $file" >&2
    echo "  Expected: $expected" >&2
    echo "  Got:      $actual" >&2
    return 1
  fi
  echo "  [ok] checksum verified"
}
```

### Research Insights

**No `rm -f` inside verify_checksum**: The function should only verify and return status. File cleanup belongs in the caller (via `trap` or explicit cleanup block). This avoids:
- Double-free with trap-based cleanup already present in the script
- Unexpected deletion if the function is reused in a context where the file should be preserved on failure for debugging

Integrate into both `install_ffmpeg_linux` and `install_rclone_linux`:
1. Download to a temp file (not pipe to tar)
2. Verify checksum
3. Extract/install only on success
4. Clean up temp files via trap or explicit cleanup

### Phase 4: Architecture Mapping Update

Update the architecture mapping for BtbN naming conventions. The script needs a second architecture variable for ffmpeg since BtbN uses different naming than rclone:

```text
# Existing rclone arch mapping (unchanged)
ARCH_SUFFIX=""
case "$ARCH" in
  x86_64)        ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
esac

# New BtbN ffmpeg arch mapping
FFMPEG_ARCH=""
case "$ARCH" in
  x86_64)        FFMPEG_ARCH="linux64" ;;
  aarch64|arm64) FFMPEG_ARCH="linuxarm64" ;;
esac
```

### Research Insights

**Two architecture mappings needed**: rclone uses `amd64`/`arm64`, BtbN uses `linux64`/`linuxarm64`. A single `ARCH_SUFFIX` cannot serve both. Add `FFMPEG_ARCH` alongside the existing `ARCH_SUFFIX`.

**Checksum lookup pattern**: Use an associative-array-like approach with variable indirection to select the right checksum based on architecture:

```text
# In install_ffmpeg_linux:
local expected_var="FFMPEG_SHA256_${FFMPEG_ARCH^^}"
local expected="${!expected_var}"
```

However, for clarity and since there are only two architectures, a simple case statement is preferable over variable indirection (which is harder to read and audit).

## Technical Considerations

### Download Flow Change

The current ffmpeg install pipes `curl | tar` directly, which prevents checksum verification. The new flow must:
1. `tmpdir=$(mktemp -d)` to create temp directory
2. `curl -sfL -o "$tmpdir/ffmpeg.tar.xz"` to download
3. `verify_checksum "$tmpdir/ffmpeg.tar.xz" "$expected_hash"`
4. `tar -xJf "$tmpdir/ffmpeg.tar.xz" -C "$tmpdir"` on success
5. Copy ffmpeg binary to `$HOME/.local/bin/`
6. `rm -rf "$tmpdir"` cleanup

### Research Insights: BtbN Tarball Layout

BtbN tarballs extract to a directory named after the build (e.g., `ffmpeg-N-123570-gf72f692afa-linux64-gpl/`), containing `bin/ffmpeg`, `bin/ffprobe`, etc. The current johnvansickle extraction uses `--strip-components=1 --wildcards '*/ffmpeg'`. The BtbN extraction should:

```text
tar -xJf "$tmpdir/ffmpeg.tar.xz" -C "$tmpdir" --strip-components=2 --wildcards '*/bin/ffmpeg'
```

Or extract fully then copy:

```text
tar -xJf "$tmpdir/ffmpeg.tar.xz" -C "$tmpdir"
cp "$tmpdir"/ffmpeg-*/bin/ffmpeg "$HOME/.local/bin/ffmpeg"
```

The second approach (full extract then copy) is more robust since `--strip-components` + `--wildcards` behavior varies across tar implementations.

### Temp Directory Handling

The rclone installer already uses `mktemp -d`. The ffmpeg installer needs the same pattern. Both should clean up on both success and failure paths.

### Research Insights: Trap-Based Cleanup

From the PR #949 learning (`2026-03-20-static-binary-install-replaces-sudo-apt.md`): use `trap 'rm -rf "$tmpdir"' EXIT` but clear the trap after manual cleanup to prevent double-free. However, since the script does NOT use `set -e`, traps are less critical -- explicit cleanup in if/else branches is sufficient and easier to follow. Use explicit cleanup rather than traps for this script.

### No `set -euo pipefail`

The script header comment explains: "No set -euo pipefail: soft dependency checks and install failures must not abort the script." The `verify_checksum` function must use explicit return codes rather than relying on `set -e`.

### macOS Path

The macOS install path (brew) is unaffected -- Homebrew handles its own integrity verification. No changes needed for macOS.

### Updating Checksums

When updating pinned versions, the maintainer must:
1. Update `RCLONE_VERSION` or `FFMPEG_AUTOBUILD` + `FFMPEG_BUILD_ID`
2. Fetch the new SHA256SUMS file
3. Update the embedded hash constants
4. Test on both amd64 and arm64 (or at least the primary dev architecture)

### Research Insights: Update Procedure

For ffmpeg, the `FFMPEG_BUILD_ID` can be extracted from the checksums file:

```text
# Find the latest autobuild tag:
curl -s "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases" | jq '.[1].tag_name'
# (index 1 because index 0 is the "latest" floating tag)

# Fetch checksums and extract build ID:
curl -sL "https://github.com/BtbN/FFmpeg-Builds/releases/download/<tag>/checksums.sha256" | grep linux64-gpl.tar.xz | grep -v shared
# Output: <hash>  ffmpeg-N-XXXXX-g<hash>-linux64-gpl.tar.xz
# The BUILD_ID is the "N-XXXXX-g<hash>" portion
```

Add this procedure as a comment block at the top of the version constants section.

## Attack Surface Enumeration

All code paths that download and install binaries in `check_deps.sh`:

| Path | Current State | After Fix |
|------|--------------|-----------|
| `install_ffmpeg_linux` (line 26-42) | No checksum, floating URL | Pinned version, SHA256 verified |
| `install_rclone_linux` (line 44-69) | No checksum, floating URL | Pinned version, SHA256 verified |
| macOS `brew install` (line 89-94) | Homebrew verifies integrity | No change needed (safe) |
| `install_tool` dispatch (line 71-101) | Routes to above | No change needed (dispatch only) |

No other download paths exist in the script.

### Research Insights: Residual Risk

- **HTTPS MITM**: If an attacker can MITM the HTTPS connection AND modify the committed script, the checksum is bypassed. This is out of scope (would require compromising both the CDN and the git repo).
- **BtbN repository compromise**: An attacker could push a malicious build with a valid checksum. GPG signature verification would mitigate this, but is out of scope (non-goal). The embedded-in-git checksum at least detects post-publication tampering.
- **sha256sum binary substitution**: If the local `sha256sum` binary is compromised, verification is meaningless. This is out of scope (local machine compromise).

## Non-Goals

- Switching the rclone download source (rclone.org is fine, it has proper versioned URLs and SHA256SUMS)
- Adding GPG signature verification (SHA256 from a committed script is sufficient for this threat model)
- Modifying the pencil-setup `check_deps.sh` (it does not download binaries from the web)
- Auto-updating pinned versions (manual update with checksum refresh is the correct workflow)
- Adding checksum verification to macOS brew installs (Homebrew handles this)
- Pinning ffmpeg to a stable release tag (BtbN only provides rolling autobuilds, not semantic versions)

## Acceptance Criteria

- [x] Version constants (`RCLONE_VERSION`, `FFMPEG_AUTOBUILD`, `FFMPEG_BUILD_ID`) pinned at script top in `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] SHA256 checksum constants embedded for each architecture (amd64/arm64 for rclone, linux64/linuxarm64 for ffmpeg)
- [x] `verify_checksum` function added and called before extraction for both ffmpeg and rclone
- [x] ffmpeg source switched from johnvansickle.com to BtbN GitHub releases
- [x] Download flow changed from `curl | tar` pipe to download-then-verify-then-extract
- [x] Temp directory cleanup on both success and failure paths
- [x] Update procedure documented in script comments (including how to find `FFMPEG_BUILD_ID`)
- [x] macOS brew path unchanged
- [x] Script still works without `set -euo pipefail` (soft failures)
- [x] Architecture mapping updated: `FFMPEG_ARCH` added for BtbN naming (`linux64`/`linuxarm64`), existing `ARCH_SUFFIX` unchanged for rclone
- [x] Version printed during install (e.g., "Downloading rclone v1.73.2...")

## Test Scenarios

- Given a clean Linux amd64 system without ffmpeg, when `check_deps.sh --auto` runs, then ffmpeg is downloaded from BtbN with the pinned autobuild tag, checksum is verified against the embedded constant, and the binary is installed to `~/.local/bin/ffmpeg`
- Given a clean Linux arm64 system without rclone, when `check_deps.sh --auto` runs, then rclone v1.73.2 is downloaded with the versioned URL, checksum is verified, and the binary is installed to `~/.local/bin/rclone`
- Given a corrupted download (simulated by replacing the downloaded file before verification), when checksum verification runs, then the script prints a CHECKSUM MISMATCH error to stderr and returns non-zero without installing
- Given ffmpeg is already installed, when `check_deps.sh` runs, then no download occurs and the script reports `[ok] ffmpeg`
- Given an unsupported architecture (e.g., i686), when the install function is called, then it prints an error and returns 1 without attempting download
- Given `curl` is not available, when install is attempted, then the script reports curl is required and returns 1

### Research Insights: Additional Edge Cases

- Given the BtbN GitHub release is deleted (404 on download URL), when install is attempted, then `curl -sfL` fails silently (due to `-f` flag) and the script reports download failure
- Given the rclone download succeeds but `unzip` is not installed, when extraction is attempted, then the existing prerequisite check catches this before download (line 50-53)

## Files Modified

- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- version pinning, checksum constants, verify function, updated URLs, architecture mapping

## References

- Issue: #956
- PR #949: sudo removal refactor that introduced the current download pattern
- Learning: `knowledge-base/learnings/2026-03-20-static-binary-install-replaces-sudo-apt.md` (trap cleanup pattern, arch detection)
- rclone SHA256SUMS: [https://downloads.rclone.org/v1.73.2/SHA256SUMS](https://downloads.rclone.org/v1.73.2/SHA256SUMS) (standard `sha256sum -c` format)
- BtbN FFmpeg Builds: [https://github.com/BtbN/FFmpeg-Builds/releases](https://github.com/BtbN/FFmpeg-Builds/releases) (daily autobuilds with `checksums.sha256`)
- BtbN checksums for pinned build: [https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-03-20-13-06/checksums.sha256](https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-03-20-13-06/checksums.sha256)
