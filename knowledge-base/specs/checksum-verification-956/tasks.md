# Tasks: Checksum Verification and Version Pinning

## Phase 1: Setup

- [ ] 1.1 Read current `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] 1.2 Fetch rclone SHA256SUMS from `https://downloads.rclone.org/v1.69.1/SHA256SUMS` to extract checksums for `rclone-v1.69.1-linux-amd64.zip` and `rclone-v1.69.1-linux-arm64.zip`
- [ ] 1.3 Fetch BtbN ffmpeg checksums from `https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-03-20-13-06/checksums.sha256` to extract checksums for `ffmpeg-master-latest-linux64-gpl.tar.xz` and `ffmpeg-master-latest-linuxarm64-gpl.tar.xz`

## Phase 2: Core Implementation

- [ ] 2.1 Add version and checksum constants at script top
  - [ ] 2.1.1 `RCLONE_VERSION="1.69.1"` with SHA256 per architecture
  - [ ] 2.1.2 `FFMPEG_AUTOBUILD="2026-03-20-13-06"` with SHA256 per architecture
  - [ ] 2.1.3 Add update procedure comment block
- [ ] 2.2 Add `verify_checksum` helper function
  - [ ] 2.2.1 Accept file path and expected hash
  - [ ] 2.2.2 Compute SHA256 with `sha256sum`
  - [ ] 2.2.3 Compare and return 1 on mismatch with diagnostic output to stderr
  - [ ] 2.2.4 Remove corrupt file on mismatch
- [ ] 2.3 Update `install_ffmpeg_linux` function
  - [ ] 2.3.1 Add BtbN architecture mapping (`x86_64` -> `linux64`, `aarch64`/`arm64` -> `linuxarm64`)
  - [ ] 2.3.2 Switch URL to BtbN GitHub releases with pinned autobuild tag
  - [ ] 2.3.3 Change from `curl | tar` pipe to download-to-tmpfile flow
  - [ ] 2.3.4 Call `verify_checksum` before extraction
  - [ ] 2.3.5 Extract ffmpeg binary from tar after verification
  - [ ] 2.3.6 Clean up temp files on both success and failure
- [ ] 2.4 Update `install_rclone_linux` function
  - [ ] 2.4.1 Switch URL from `rclone-current-` to `rclone-v<VERSION>-` versioned path
  - [ ] 2.4.2 Call `verify_checksum` on downloaded zip before extraction
  - [ ] 2.4.3 Ensure temp directory cleanup on both paths

## Phase 3: Testing

- [ ] 3.1 Run `bash -n plugins/soleur/skills/feature-video/scripts/check_deps.sh` for syntax check
- [ ] 3.2 Verify the script prints pinned versions in output when installing
- [ ] 3.3 Run compound (`skill: soleur:compound`) before commit
