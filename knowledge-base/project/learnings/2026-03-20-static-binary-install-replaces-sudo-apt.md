# Learning: Static binary downloads replace sudo apt-get in agent scripts

## Problem

`check_deps.sh` used `sudo apt-get install` for ffmpeg and rclone on Linux. AGENTS.md prohibits sudo — the Bash tool runs without elevated privileges. The `sudo -n` guard prevented hangs but produced stderr warnings and was dead code in agent context.

## Solution

Replaced `sudo apt-get` with static binary downloads to `$HOME/.local/bin`:

- **ffmpeg**: `curl -sL` piped to `tar -xJf` from johnvansickle.com static builds (amd64/arm64)
- **rclone**: `curl -sL` to temp dir, `unzip`, copy binary from downloads.rclone.org (amd64/arm64)

Key implementation details:

- Architecture detection via `uname -m` with case mapping (reused pencil-setup pattern)
- `$HOME/.local/bin` PATH prepend at script top (tilde unreliable in double quotes)
- `trap 'rm -rf "$tmpdir"' EXIT` for temp dir cleanup (cleared after manual cleanup to prevent double-free)
- Prerequisite checks: `curl` before any download, `unzip` before rclone extraction
- Broadened OS detection from debian-only (`/etc/debian_version`) to all Linux (`uname -s == Linux`)

## Key Insight

Static binary downloads eliminate the sudo dependency entirely while working on any Linux distribution — not just Debian. The parameterized `install_tool()` dispatcher pattern scales by adding tool-specific helper functions internally while keeping the external API unchanged.

## Session Errors

- Wrong script path for `setup-ralph-loop.sh` (used `skills/one-shot/scripts/` instead of `scripts/`). Self-corrected after glob lookup.

## Tags

category: runtime-errors
module: feature-video
