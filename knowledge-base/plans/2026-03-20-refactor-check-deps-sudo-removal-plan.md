---
title: "refactor: remove sudo from check_deps.sh and use curl/tar installs"
type: refactor
date: 2026-03-20
---

# refactor: remove sudo from check_deps.sh and use curl/tar installs (#944)

## Overview

`plugins/soleur/skills/feature-video/scripts/check_deps.sh` uses `sudo -n true` and `sudo apt-get install -y` in the `install_tool()` function. AGENTS.md explicitly states the Bash tool runs without `sudo` access, and the constitution mandates installing tools via `curl`/`tar` or `npm` to `~/.local/bin`. The existing brainstorm (#325) already identified this gap: "Static binaries exist for both ffmpeg and rclone that can install to `~/.local/bin` without sudo."

The `sudo -n` guard prevents hanging and falls back to manual instructions, so this is dead code in agent context -- but it produces stderr warnings in sandboxed environments and contradicts documented conventions.

A secondary instance exists in `plugins/soleur/skills/rclone/scripts/check_setup.sh` line 19, which prints `curl https://rclone.org/install.sh | sudo bash` as an install instruction.

## Problem Statement

1. `check_deps.sh` `install_tool()` function (lines 14-35) uses `sudo apt-get` for Debian installs -- unreachable in Claude Code's sandboxed environment.
2. `check_setup.sh` line 19 prints `sudo bash` as an install instruction -- misleading in agent context.
3. Both violate the AGENTS.md hard rule: "The Bash tool runs in a non-interactive shell without `sudo` access."

## Proposed Solution

Replace `install_tool()` with `~/.local/bin` static binary installs for ffmpeg and rclone. Keep the macOS `brew install` path (brew does not require sudo). Update rclone's `check_setup.sh` install instructions to match.

### ffmpeg install strategy

ffmpeg provides static builds at `https://johnvansickle.com/ffmpeg/` (Linux) and via `brew` (macOS). The Linux static binary is a tarball containing a self-contained `ffmpeg` binary -- extract to `~/.local/bin`.

```bash
# Linux (amd64)
mkdir -p ~/.local/bin
curl -sL https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz \
  | tar -xJf - --strip-components=1 -C ~/.local/bin --wildcards '*/ffmpeg'
```

For arm64 Linux, substitute `ffmpeg-release-arm64-static.tar.xz`.

### rclone install strategy

rclone provides official static binaries at `https://downloads.rclone.org/rclone-current-linux-amd64.zip`. Extract to `~/.local/bin`.

```bash
# Linux (amd64)
mkdir -p ~/.local/bin
TMP=$(mktemp -d)
curl -sL https://downloads.rclone.org/rclone-current-linux-amd64.zip -o "$TMP/rclone.zip"
unzip -q "$TMP/rclone.zip" -d "$TMP"
cp "$TMP"/rclone-*/rclone ~/.local/bin/rclone
chmod +x ~/.local/bin/rclone
rm -rf "$TMP"
```

For arm64 Linux, substitute `linux-arm64`.

### PATH consideration

`~/.local/bin` must be in `$PATH` for `command -v` to find the installed binaries. The script should:
1. Prepend `~/.local/bin` to PATH at the top of the script if not already present
2. After install, verify the binary is findable via `command -v`

## Acceptance Criteria

- [ ] `install_tool()` in `check_deps.sh` no longer uses `sudo` in any code path
- [ ] ffmpeg installs via static binary to `~/.local/bin` on Linux, `brew install` on macOS
- [ ] rclone installs via static binary to `~/.local/bin` on Linux, `brew install` on macOS
- [ ] Architecture detection (amd64 vs arm64) selects the correct binary URL
- [ ] `~/.local/bin` is added to PATH within the script if not already present
- [ ] `verify_install()` confirms the tool is in PATH after installation
- [ ] `check_setup.sh` install instructions no longer reference `sudo`
- [ ] `--auto` flag behavior preserved (auto-install without prompting)
- [ ] Graceful degradation preserved: network failure or download failure prints manual instructions and returns 1
- [ ] No `set -euo pipefail` added (existing design decision documented in script header: soft checks must not abort)

## Test Scenarios

- Given a Debian system without ffmpeg and without sudo, when `check_deps.sh --auto` runs, then ffmpeg is downloaded to `~/.local/bin` and `command -v ffmpeg` succeeds
- Given a Debian system without rclone and without sudo, when `check_deps.sh --auto` runs, then rclone is downloaded to `~/.local/bin` and `command -v rclone` succeeds
- Given a macOS system with brew, when `check_deps.sh --auto` runs, then `brew install` is used (unchanged behavior)
- Given an arm64 Linux system, when `check_deps.sh --auto` runs, then the arm64 binary variant is downloaded
- Given no network access, when `check_deps.sh --auto` runs, then the install fails gracefully with manual instructions
- Given the rclone skill's `check_setup.sh`, when reading the install instructions, then no `sudo` appears in output

## Context

### Files to modify

- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- primary target, rewrite `install_tool()`
- `plugins/soleur/skills/rclone/scripts/check_setup.sh` -- update install instruction text (line 19)

### Existing patterns to follow

- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` -- architecture detection pattern (`uname -m` with case mapping)
- AGENTS.md guidance: "Install with `curl`/`tar` or `npm` to `~/.local/bin` -- no `sudo` needed"
- Brainstorm document: `knowledge-base/project/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md`

### Edge cases

1. **unzip not available:** rclone's official download is a `.zip`. If `unzip` is not available, fall back to `curl | funzip` or use the `.deb` download and extract with `dpkg-deb`. Alternatively, use `bsdtar` which handles zip files. Simplest approach: check for `unzip` first, print install instruction if missing.
2. **Disk space:** Static ffmpeg binary is ~80MB. This is acceptable for `~/.local/bin` but worth noting in the install output.
3. **Existing binary in ~/.local/bin:** If the binary already exists, skip download. The `command -v` check at the top of `attempt_install()` already handles this.
4. **curl not available:** Unlikely in any modern Linux but `command -v curl` should be checked before download attempts.

## References

- Issue: #944
- Prior brainstorm: `knowledge-base/project/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md`
- AGENTS.md hard rule on sudo
- Constitution shell script conventions (shebang, variable naming, error handling)
