---
title: "refactor: remove sudo from check_deps.sh and use curl/tar installs"
type: refactor
date: 2026-03-20
---

# refactor: remove sudo from check_deps.sh and use curl/tar installs (#944)

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Acceptance Criteria, Test Scenarios, Edge Cases, References)
**Research sources:** WebFetch (johnvansickle.com, rclone.org, downloads.rclone.org), 3 institutional learnings, constitution shell conventions

### Key Improvements

1. Verified download URLs are live and correct (ffmpeg static builds confirmed at johnvansickle.com with amd64/arm64/armhf/armel/i686; rclone confirmed at downloads.rclone.org with amd64/arm64/arm/386)
2. Added `trap`-based temp directory cleanup from shell defensive patterns learning -- the rclone install creates a temp dir that must be cleaned on all exit paths
3. Incorporated parameterized install function pattern from learning -- `install_tool()` should remain a single parameterized function but now dispatches to tool-specific download logic internally, keeping the external API unchanged
4. Added `--wildcards` flag verification for tar -- GNU tar on Linux supports `--wildcards` but BSD tar on macOS does not (irrelevant since macOS uses brew, but worth noting for portability)

### New Considerations Discovered

- rclone arm64 URL confirmed: `rclone-current-linux-arm64.zip` (pattern matches amd64)
- ffmpeg static builds are ~80-90MB compressed, ~150MB extracted -- the install output should note the download size
- The `install_tool()` function can no longer be a simple passthrough to a package manager -- it needs tool-specific download logic for Linux, which breaks the parameterized pattern. Resolution: keep `install_tool()` as the dispatch function but add `install_ffmpeg_linux()` and `install_rclone_linux()` as internal helpers. This preserves the single entry point from the learning while accommodating tool-specific download URLs.

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

### Architecture detection

Reuse the pencil-setup pattern (`plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` lines 16-21):

```bash
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)        ARCH_SUFFIX="amd64" ;;
  aarch64|arm64) ARCH_SUFFIX="arm64" ;;
  *)             ARCH_SUFFIX="" ;;  # unsupported -- fall through to manual instructions
esac
```

### ffmpeg install strategy

ffmpeg provides static builds at `https://johnvansickle.com/ffmpeg/` (Linux) and via `brew` (macOS). Verified live 2026-03-20: release builds available for amd64, arm64, armhf, armel, i686. Current release version: 7.0.2.

```bash
install_ffmpeg_linux() {
  local arch_suffix="$1"
  if [[ -z "$arch_suffix" ]]; then
    echo "  Unsupported architecture: $(uname -m). Install ffmpeg manually." >&2
    return 1
  fi
  local url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${arch_suffix}-static.tar.xz"
  echo "  Downloading ffmpeg static build (~80MB)..."
  mkdir -p "$HOME/.local/bin"
  if curl -sL "$url" | tar -xJf - --strip-components=1 -C "$HOME/.local/bin" --wildcards '*/ffmpeg'; then
    chmod +x "$HOME/.local/bin/ffmpeg"
    return 0
  else
    echo "  Download failed. Install ffmpeg manually: https://johnvansickle.com/ffmpeg/" >&2
    return 1
  fi
}
```

### Research Insights (ffmpeg)

**Best Practices:**

- Use `$HOME/.local/bin` (not `~`) in scripts -- tilde expansion is not guaranteed in all contexts (e.g., inside double quotes)
- The `--strip-components=1` flag removes the version-specific directory prefix from the tarball, extracting `ffmpeg` directly to the target
- The `--wildcards '*/ffmpeg'` extracts only the ffmpeg binary, skipping ffprobe and qt-faststart (~50MB savings)

**Edge Case:** The tarball also contains `ffprobe`. The feature-video skill only uses `ffmpeg`, but `ffprobe` is occasionally useful for inspecting video metadata. Consider extracting both with `--wildcards '*/ffmpeg' '*/ffprobe'` -- minimal cost, potential future value.

### rclone install strategy

rclone provides official static binaries at `https://downloads.rclone.org/`. Verified live 2026-03-20: current version dated 2026-03-06, available for amd64, arm64, arm, 386, mips, mipsle in .zip/.deb/.rpm formats.

```bash
install_rclone_linux() {
  local arch_suffix="$1"
  if [[ -z "$arch_suffix" ]]; then
    echo "  Unsupported architecture: $(uname -m). Install rclone manually." >&2
    return 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "  unzip is required to install rclone. Install unzip first." >&2
    echo "  Then re-run this script." >&2
    return 1
  fi
  local url="https://downloads.rclone.org/rclone-current-linux-${arch_suffix}.zip"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT  # cleanup on all exit paths (learning: shell defensive patterns)
  echo "  Downloading rclone (~25MB)..."
  mkdir -p "$HOME/.local/bin"
  if curl -sL "$url" -o "$tmpdir/rclone.zip" && \
     unzip -q "$tmpdir/rclone.zip" -d "$tmpdir" && \
     cp "$tmpdir"/rclone-*/rclone "$HOME/.local/bin/rclone" && \
     chmod +x "$HOME/.local/bin/rclone"; then
    rm -rf "$tmpdir"
    trap - EXIT  # clear trap after manual cleanup
    return 0
  else
    echo "  Download failed. Install rclone manually: https://rclone.org/install/" >&2
    rm -rf "$tmpdir"
    trap - EXIT
    return 1
  fi
}
```

### Research Insights (rclone)

**Best Practices:**

- The `trap 'rm -rf "$tmpdir"' EXIT` pattern ensures cleanup even on unexpected exits (from learning: `2026-03-13-shell-script-defensive-patterns.md` -- "Pair every `mktemp` with a `trap` on the next line")
- Clear the trap after manual cleanup to avoid double-free if the function is called multiple times in the same process
- Chain the download/extract/copy commands with `&&` so a failure at any step skips subsequent steps

**Caution:** The `trap ... EXIT` is function-scoped in bash 4.4+ but global in earlier versions. Since `check_deps.sh` does not use `set -euo pipefail` and the trap only cleans a temp dir, this is safe in practice. If the script later adds subshell-based parallelism, the trap would need to be moved to the subshell scope.

### Refactored install_tool() dispatcher

Keep the parameterized entry point (per learning: `2026-02-27-parameterized-shell-install-eliminates-duplication.md`) but dispatch to tool-specific Linux installers:

```bash
install_tool() {
  local tool="$1"
  case "$OS" in
    debian|linux)
      case "$tool" in
        ffmpeg) install_ffmpeg_linux "$ARCH_SUFFIX" ;;
        rclone) install_rclone_linux "$ARCH_SUFFIX" ;;
        *)
          echo "  No installer for $tool. Install manually." >&2
          return 1
          ;;
      esac
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install "$tool"
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi
      ;;
    *)
      echo "  Unsupported OS. Install $tool manually." >&2
      return 1
      ;;
  esac
}
```

**Note:** The `*)` catch-all in the inner `case` follows the shell defensive patterns learning: "Every `case` statement that dispatches on a parameter must have a terminal catch-all that fails loudly."

### PATH consideration

`$HOME/.local/bin` must be in `$PATH` for `command -v` to find the installed binaries. Add at the top of the script:

```bash
# Ensure ~/.local/bin is in PATH for user-local installs
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"
```

### check_setup.sh update

Replace lines 18-20 in `plugins/soleur/skills/rclone/scripts/check_setup.sh`:

```bash
# Before:
echo "  Linux:  curl https://rclone.org/install.sh | sudo bash"
echo "          or: sudo apt install rclone"

# After:
echo "  Linux:  mkdir -p ~/.local/bin && curl -sL https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rclone.zip && unzip -q /tmp/rclone.zip -d /tmp && cp /tmp/rclone-*/rclone ~/.local/bin/ && chmod +x ~/.local/bin/rclone"
```

This is a one-liner that can be copy-pasted. It avoids sudo entirely.

## Acceptance Criteria

- [x] `install_tool()` in `check_deps.sh` no longer uses `sudo` in any code path
- [x] ffmpeg installs via static binary to `$HOME/.local/bin` on Linux, `brew install` on macOS
- [x] rclone installs via static binary to `$HOME/.local/bin` on Linux, `brew install` on macOS
- [x] Architecture detection (amd64 vs arm64) selects the correct binary URL
- [x] `$HOME/.local/bin` is added to PATH within the script if not already present
- [x] `verify_install()` confirms the tool is in PATH after installation
- [x] `check_setup.sh` install instructions no longer reference `sudo`
- [x] `--auto` flag behavior preserved (auto-install without prompting)
- [x] Graceful degradation preserved: network failure or download failure prints manual instructions and returns 1
- [x] No `set -euo pipefail` added (existing design decision documented in script header: soft checks must not abort)
- [x] Temp directories cleaned via `trap ... EXIT` pattern (not scattered `rm -rf`)
- [x] Inner `case` dispatchers include catch-all `*)` branch
- [x] `curl` availability checked before download attempts
- [x] `unzip` availability checked before rclone extraction

## Test Scenarios

- Given a Linux system without ffmpeg and without sudo, when `check_deps.sh --auto` runs, then ffmpeg is downloaded to `$HOME/.local/bin` and `command -v ffmpeg` succeeds
- Given a Linux system without rclone and without sudo, when `check_deps.sh --auto` runs, then rclone is downloaded to `$HOME/.local/bin` and `command -v rclone` succeeds
- Given a macOS system with brew, when `check_deps.sh --auto` runs, then `brew install` is used (unchanged behavior)
- Given an arm64 Linux system, when `check_deps.sh --auto` runs, then the arm64 binary variant is downloaded (URL contains `arm64`)
- Given no network access, when `check_deps.sh --auto` runs, then the install fails gracefully with manual instructions and returns 1
- Given a system without `curl`, when `check_deps.sh --auto` runs, then a "curl required" message is printed and install returns 1
- Given a system without `unzip`, when rclone install is attempted, then a "unzip required" message is printed and install returns 1
- Given the rclone skill's `check_setup.sh`, when reading the install instructions, then no `sudo` appears in output
- Given ffmpeg and rclone are already installed, when `check_deps.sh` runs, then no downloads are attempted and `[ok]` is printed for both
- Given a system with an unsupported architecture (e.g., mips), when `check_deps.sh --auto` runs, then manual install instructions are printed

## Context

### Files to modify

- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- primary target, rewrite `install_tool()` and add architecture detection, PATH prepend, and tool-specific Linux installers
- `plugins/soleur/skills/rclone/scripts/check_setup.sh` -- update install instruction text (lines 18-20)

### Existing patterns to follow

- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` -- architecture detection pattern (`uname -m` with case mapping, lines 16-21)
- AGENTS.md guidance: "Install with `curl`/`tar` or `npm` to `~/.local/bin` -- no `sudo` needed"
- Brainstorm: `knowledge-base/project/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md`
- Learning: `knowledge-base/project/learnings/2026-02-27-parameterized-shell-install-eliminates-duplication.md` -- keep single `install_tool()` entry point
- Learning: `knowledge-base/project/learnings/2026-02-27-feature-video-graceful-degradation.md` -- hard vs soft dependency classification
- Learning: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md` -- trap cleanup, catch-all cases, curl prerequisite check

### Edge cases

1. **unzip not available:** rclone's official download is a `.zip`. Check for `unzip` before attempting rclone install; print install instruction if missing. Alternative: `python3 -c "import zipfile; ..."` as a fallback, but this adds complexity for marginal gain -- `unzip` is in `apt` base installs and `brew` on macOS.
2. **Disk space:** Static ffmpeg binary is ~80-90MB compressed, ~150MB extracted. rclone is ~25MB compressed. The install output should note the download size so the user knows what to expect.
3. **Existing binary in $HOME/.local/bin:** If the binary already exists, skip download. The `command -v` check at the top of `attempt_install()` already handles this -- no change needed.
4. **curl not available:** Check `command -v curl` before download attempts. Print "curl is required for auto-install" and return 1 if missing.
5. **trap scope in bash < 4.4:** The `trap ... EXIT` is global, not function-scoped. Since the script runs sequentially (not in subshells), this is safe. Clear the trap after manual cleanup with `trap - EXIT`.
6. **Partial download / corrupted file:** If `curl` succeeds but `tar` or `unzip` fails (corrupted download), the error message should suggest retrying. The chained `&&` ensures partial failures are caught.
7. **OS detection rename:** Current script uses `OS="debian"` detected from `/etc/debian_version`. Consider also detecting generic Linux (`OS="linux"`) for non-Debian distributions (Fedora, Arch, Alpine) where static binaries work equally well. The static binary install does not depend on any Debian-specific tooling.

## References

- Issue: #944
- Prior brainstorm: `knowledge-base/project/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md`
- AGENTS.md hard rule on sudo
- Constitution shell script conventions (shebang, variable naming, error handling)
- ffmpeg static builds: <https://johnvansickle.com/ffmpeg/> (verified 2026-03-20, release 7.0.2, amd64/arm64/armhf/armel/i686)
- rclone downloads: <https://downloads.rclone.org/> (verified 2026-03-20, dated 2026-03-06, amd64/arm64/arm/386)
- Learning: parameterized shell install -- `knowledge-base/project/learnings/2026-02-27-parameterized-shell-install-eliminates-duplication.md`
- Learning: feature video graceful degradation -- `knowledge-base/project/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Learning: shell defensive patterns (trap, catch-all) -- `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`
