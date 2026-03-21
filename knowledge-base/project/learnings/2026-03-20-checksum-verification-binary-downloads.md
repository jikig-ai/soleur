# Learning: Checksum verification and version pinning for binary downloads

## Problem

`check_deps.sh` downloaded ffmpeg and rclone binaries over HTTPS without checksum verification or version pinning. A compromised CDN or mirror could serve malicious binaries that pass the HTTPS check (valid cert, correct domain) but contain tampered content. The `latest` download URLs also meant builds could silently change between runs with no way to detect or reproduce the exact version installed.

## Solution

Pinned both tools to specific versions with SHA256 checksums embedded as constants in the script:

1. **Version pinning**: `RCLONE_VERSION=1.73.2`, `FFMPEG_AUTOBUILD_DATE=2026-03-20-13-06` with a `FFMPEG_BUILD_ID` for the exact asset filename.
2. **Embedded checksums**: Per-architecture SHA256 constants (`RCLONE_SHA256_AMD64`, `FFMPEG_SHA256_LINUX64`, etc.) committed to git, not downloaded from the same server as the binary.
3. **Download-then-verify-then-extract**: Replaced `curl | tar` pipes with explicit steps: download to tmpdir, run `sha256sum` against embedded constant, extract only on match.
4. **`verify_checksum()` function**: Reusable across both tools, exits non-zero with a clear message on mismatch.
5. **Switched ffmpeg source**: Moved from johnvansickle.com (no versioned URLs, no published checksums) to BtbN GitHub releases (versioned tags, checksums available per release).
6. **`trap ... RETURN`**: Function-scoped tmpdir cleanup instead of triplicated `rm -rf` calls. Fires on any exit path including errors.

## Key Insight

Embedded checksums are strictly stronger than downloaded checksums. Fetching `SHA256SUMS` from the same server as the binary provides zero protection against CDN compromise -- both files are controlled by the same attacker. Embedding the expected hash in source code (versioned in git, reviewed in PRs) creates a trust boundary: the hash is verified against the repository's commit history, not against the download server. This is the same principle behind lock files (`package-lock.json`, `go.sum`) and is the minimum bar for installing unsigned binaries in CI or agent scripts.

A secondary insight: when switching binary sources, asset naming conventions differ in non-obvious ways. BtbN ffmpeg uses `linux64`/`linuxarm64` for architecture suffixes while rclone uses `amd64`/`arm64`. Dated autobuild tags produce filenames like `ffmpeg-N-<buildnum>-g<hash>-*`, not the `ffmpeg-master-latest-*` pattern from the `latest` tag. Both require separate constants rather than string interpolation from a single version variable.

## Tags

category: security
module: feature-video
