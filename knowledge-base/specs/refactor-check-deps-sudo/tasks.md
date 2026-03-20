# Tasks: refactor check_deps.sh sudo removal (#944)

## Phase 1: Setup

- [ ] 1.1 Read and understand current `check_deps.sh` implementation
- [ ] 1.2 Read pencil-setup `check_deps.sh` for architecture detection pattern
- [ ] 1.3 Read rclone `check_setup.sh` for secondary sudo reference

## Phase 2: Core Implementation

- [ ] 2.1 Add architecture detection to `check_deps.sh` (reuse pencil-setup pattern: `uname -m` with case mapping for amd64/arm64)
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] 2.2 Add `~/.local/bin` PATH prepend at script top (if not already in PATH)
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] 2.3 Rewrite `install_tool()` function:
  - [ ] 2.3.1 Linux ffmpeg: download static binary from johnvansickle.com to `~/.local/bin`
  - [ ] 2.3.2 Linux rclone: download zip from downloads.rclone.org, extract to `~/.local/bin`
  - [ ] 2.3.3 macOS: keep `brew install` path (unchanged)
  - [ ] 2.3.4 Unknown OS: keep manual instruction fallback (unchanged)
  - [ ] 2.3.5 Add `curl` availability check before download attempts
  - [ ] 2.3.6 Add `unzip` availability check before rclone extraction
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] 2.4 Update rclone `check_setup.sh` install instructions to remove sudo references
  - File: `plugins/soleur/skills/rclone/scripts/check_setup.sh`
  - Change line 19 from `curl https://rclone.org/install.sh | sudo bash` to curl/unzip to `~/.local/bin`
  - Change line 20 from `sudo apt install rclone` to the same static binary approach

## Phase 3: Testing

- [ ] 3.1 Run `check_deps.sh` with ffmpeg and rclone already installed -- verify `[ok]` output unchanged
- [ ] 3.2 Run `check_deps.sh --auto` in sandboxed environment -- verify no sudo errors in stderr
- [ ] 3.3 Verify `grep -r 'sudo' plugins/soleur/skills/feature-video/` returns no matches
- [ ] 3.4 Verify `grep -r 'sudo' plugins/soleur/skills/rclone/scripts/check_setup.sh` returns no matches
- [ ] 3.5 Run compound skill before commit
