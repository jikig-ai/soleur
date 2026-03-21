# Tasks: refactor check_deps.sh sudo removal (#944)

## Phase 1: Setup

- [x] 1.1 Read and understand current `check_deps.sh` implementation
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 1.2 Read pencil-setup `check_deps.sh` for architecture detection pattern (lines 16-21)
  - File: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- [x] 1.3 Read rclone `check_setup.sh` for secondary sudo reference (lines 18-20)
  - File: `plugins/soleur/skills/rclone/scripts/check_setup.sh`
- [x] 1.4 Read relevant learnings for patterns to apply:
  - `knowledge-base/project/learnings/2026-02-27-parameterized-shell-install-eliminates-duplication.md`
  - `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`

## Phase 2: Core Implementation

- [x] 2.1 Add architecture detection to `check_deps.sh` (reuse pencil-setup pattern: `uname -m` with case mapping for amd64/arm64, unknown -> empty string for unsupported)
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
  - Add after OS detection block (line 12)
- [x] 2.2 Add `$HOME/.local/bin` PATH prepend at script top (if not already in PATH)
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
  - Pattern: `[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"`
  - Use `$HOME` not `~` (tilde not guaranteed in double quotes)
- [x] 2.3 Add `install_ffmpeg_linux()` helper function:
  - URL: `https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${ARCH_SUFFIX}-static.tar.xz`
  - Extract with: `tar -xJf - --strip-components=1 -C "$HOME/.local/bin" --wildcards '*/ffmpeg'`
  - Print download size estimate (~80MB) before downloading
  - Return 1 with manual instructions on failure
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 2.4 Add `install_rclone_linux()` helper function:
  - URL: `https://downloads.rclone.org/rclone-current-linux-${ARCH_SUFFIX}.zip`
  - Check `unzip` availability first
  - Use `mktemp -d` with `trap 'rm -rf "$tmpdir"' EXIT` cleanup
  - Clear trap after manual cleanup: `trap - EXIT`
  - Print download size estimate (~25MB) before downloading
  - Return 1 with manual instructions on failure
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 2.5 Rewrite `install_tool()` dispatcher function:
  - [x] 2.5.1 Add `curl` availability check at top (before any downloads)
  - [x] 2.5.2 Linux/Debian case: dispatch to `install_ffmpeg_linux` or `install_rclone_linux` based on tool name
  - [x] 2.5.3 macOS case: keep `brew install "$tool"` path (unchanged)
  - [x] 2.5.4 Unknown OS case: keep manual instruction fallback (unchanged)
  - [x] 2.5.5 Add catch-all `*)` in inner tool-name case for unknown tools
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 2.6 Consider broadening OS detection: rename `OS="debian"` to `OS="linux"` since static binaries work on any Linux (Fedora, Arch, Alpine, etc.), not just Debian. The `/etc/debian_version` check is unnecessarily restrictive.
  - File: `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [x] 2.7 Update rclone `check_setup.sh` install instructions to remove sudo references
  - File: `plugins/soleur/skills/rclone/scripts/check_setup.sh`
  - Replace line 19: `curl https://rclone.org/install.sh | sudo bash` -> curl/unzip to `~/.local/bin`
  - Replace line 20: `sudo apt install rclone` -> same static binary approach

## Phase 3: Testing

- [x] 3.1 Run `check_deps.sh` with ffmpeg and rclone already installed -- verify `[ok]` output unchanged
- [x] 3.2 Run `check_deps.sh --auto` in sandboxed environment -- verify no sudo errors in stderr
- [x] 3.3 Verify no sudo references remain: `grep -r 'sudo' plugins/soleur/skills/feature-video/` returns no matches
- [x] 3.4 Verify no sudo references remain: `grep -r 'sudo' plugins/soleur/skills/rclone/scripts/check_setup.sh` returns no matches
- [x] 3.5 Verify architecture detection works: run `uname -m` and confirm ARCH_SUFFIX is set correctly
- [x] 3.6 Verify PATH prepend works: confirm `$HOME/.local/bin` is in PATH after script runs
- [ ] 3.7 Run compound skill before commit
