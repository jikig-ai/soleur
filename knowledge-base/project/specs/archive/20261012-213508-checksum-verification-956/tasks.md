# Tasks: Checksum Verification and Version Pinning

## Phase 1: Setup

- [x] 1.1 Read current `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 1.2 Checksums already fetched and verified during plan deepening (embedded in plan):
  - rclone v1.73.2 amd64: `00a1d8cb85552b7b07bb0416559b2e78fcf9c6926662a52682d81b5f20c90535`
  - rclone v1.73.2 arm64: `2f7d8b807e6ea638855129052c834ca23aa538d3ad7786e30b8ad1e97c5db47b`
  - ffmpeg linux64: `f550cd5fad7bc9045f9e6b4370204ddd245b8120f6bc193e0c09c58569e3cb32`
  - ffmpeg linuxarm64: `89b959bed4b6d63bad2d85870468a9a52cf84efd216a12fbf577a011ef391644`

## Phase 2: Core Implementation

- [x] 2.1 Add version and checksum constants at script top
  - [x] 2.1.1 `RCLONE_VERSION="1.73.2"` with SHA256 per architecture
  - [x] 2.1.2 `FFMPEG_AUTOBUILD="2026-03-20-13-06"` and `FFMPEG_BUILD_ID="N-123570-gf72f692afa"` with SHA256 per architecture
  - [x] 2.1.3 Add update procedure comment block (including how to extract `FFMPEG_BUILD_ID` from checksums file)
- [x] 2.2 Add `FFMPEG_ARCH` mapping alongside existing `ARCH_SUFFIX`
  - [x] 2.2.1 `x86_64` -> `linux64`, `aarch64`/`arm64` -> `linuxarm64`
- [x] 2.3 Add `verify_checksum` helper function
  - [x] 2.3.1 Accept file path and expected hash as arguments
  - [x] 2.3.2 Compute SHA256 with `sha256sum` and `cut -d' ' -f1`
  - [x] 2.3.3 Compare and return 1 on mismatch with diagnostic output to stderr
  - [x] 2.3.4 Do NOT rm the file inside verify_checksum (caller handles cleanup)
- [x] 2.4 Update `install_ffmpeg_linux` function
  - [x] 2.4.1 Accept `FFMPEG_ARCH` instead of `ARCH_SUFFIX` (BtbN uses `linux64`/`linuxarm64`)
  - [x] 2.4.2 Construct URL: `https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-<FFMPEG_AUTOBUILD>/ffmpeg-<FFMPEG_BUILD_ID>-<FFMPEG_ARCH>-gpl.tar.xz`
  - [x] 2.4.3 Change from `curl | tar` pipe to download-to-tmpdir flow
  - [x] 2.4.4 Select correct checksum constant via case on `FFMPEG_ARCH`
  - [x] 2.4.5 Call `verify_checksum` before extraction
  - [x] 2.4.6 Extract: `tar -xJf` then `cp */bin/ffmpeg` (BtbN layout: `ffmpeg-*/bin/ffmpeg`)
  - [x] 2.4.7 Explicit temp dir cleanup in both success and failure branches
- [x] 2.5 Update `install_rclone_linux` function
  - [x] 2.5.1 Switch URL from `rclone-current-linux-` to `rclone-v<RCLONE_VERSION>-linux-` versioned path
  - [x] 2.5.2 Select correct checksum constant via case on `ARCH_SUFFIX`
  - [x] 2.5.3 Call `verify_checksum` on downloaded zip before unzip extraction
  - [x] 2.5.4 Ensure temp directory cleanup on both paths
- [x] 2.6 Update echo messages to print pinned version during install
  - [x] 2.6.1 ffmpeg: "Downloading ffmpeg (autobuild <date>)..."
  - [x] 2.6.2 rclone: "Downloading rclone v<version>..."

## Phase 3: Testing

- [x] 3.1 Run `bash -n plugins/soleur/skills/feature-video/scripts/check_deps.sh` for syntax check
- [x] 3.2 Verify the script prints pinned versions in output
- [x] 3.3 Run compound (`skill: soleur:compound`) before commit
