---
title: "feat: Install ffmpeg and rclone on demand for feature-video pipeline"
type: feat
date: 2026-02-27
version_bump: PATCH
---

# feat: Install ffmpeg and rclone on demand for feature-video pipeline

## Enhancement Summary

**Deepened on:** 2026-02-27
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Implementation Plan, Test Scenarios)
**Research sources:** Project learnings (5), web research (cross-platform install patterns), codebase patterns (worktree-manager.sh, pencil-setup, rclone skill)

### Key Improvements
1. Concrete script skeleton with OS detection pattern matching existing codebase conventions
2. `read -r` interactive prompt pattern from worktree-manager.sh (line 84) -- proven in this codebase
3. Explicit resolution of `set -e` exception with per-command error guards
4. One-shot `--auto` mechanism documented with SKILL.md `$ARGUMENTS` bypass pattern

### Applicable Learnings
- **pencil-mcp-auto-registration-via-skill**: Skills with ~5 sequential commands don't need script abstractions. However, `check_deps.sh` already exists as a script, so extending it is the right call (no new abstraction).
- **command-substitution-in-plugin-markdown**: All `$()` logic stays in the script. SKILL.md uses angle-bracket placeholders only.
- **extract-command-substitution-into-scripts**: Confirms the script-as-boundary pattern -- SKILL.md invokes `bash ./path/to/script.sh`, script handles all shell features internally.
- **quoted-dash-strings-trigger-approval-prompts**: When SKILL.md references the `--auto` flag, use it in a plain `bash` invocation, not a quoted string that could trigger approval heuristics.
- **skill-code-fence-permission-flow**: Ensure `check_deps.sh` path is in the allow list or invoked via standard Bash tool (not `!` code fence).

## Overview

Extend the `feature-video` skill's Phase 0 dependency check to offer automatic installation of ffmpeg and rclone when they are missing, rather than silently degrading. PR #331 (v3.5.2) added preflight detection with graceful degradation. This is part 2: converting that detection into an install-or-skip prompt so new users get full pipeline capability without manual setup.

## Problem Statement / Motivation

Currently, when ffmpeg or rclone are missing, `check_deps.sh` prints `[skip]` and the skill degrades silently. This means:

- New Soleur users get screenshots-only output with no explanation of what they are missing
- The user must read the script output, find the install command, run it manually, and re-run the skill
- The one-shot pipeline produces lower-quality PR descriptions (no embedded demo videos) on fresh machines
- The rclone skill has its own separate `check_setup.sh` with overlapping install instructions

The pencil-setup skill (v3.6.0) established a pattern for auto-detection and installation of external dependencies. This plan follows that pattern for ffmpeg and rclone.

## Proposed Solution

Enhance `check_deps.sh` to offer installation of missing soft dependencies and verify success. The script accepts a `--auto` flag for non-interactive pipeline use (one-shot).

### Architecture

**Single script enhancement** -- modify the existing `check_deps.sh` rather than creating new scripts. The script already owns the dependency check responsibility; adding installation is a natural extension.

**No new skills or agents** -- this is a script-level change plus a SKILL.md Phase 0 update. The rclone skill's `check_setup.sh` remains separate (it handles configuration, not installation).

### Key Design Decisions

1. **Interactive by default, auto-install with `--auto` flag** -- when called from SKILL.md interactively, prompt the user. When called from one-shot pipeline, pass `--auto` to install without prompting. The `--auto` flag IS the consent mechanism -- no state tracking needed.

2. **Two OS families: Debian/Ubuntu (apt-get) and macOS (brew)** -- covers the actual user base. Falls back to manual instructions for unsupported systems. Fedora/RHEL support deferred until a user requests it.

3. **No `sudo` assumption** -- check `sudo -n true` inline before install commands. If no sudo, print the command they need to run and continue with `[skip]`.

4. **Package manager install for both tools in auto mode** -- use `sudo apt-get install -y rclone` on Debian and `brew install rclone` on macOS. The `curl | sudo bash` method is reserved for manual install instructions only (not safe for unattended auto mode). Users who want the latest rclone version can run the official script manually.

5. **Verification after install** -- re-run `command -v` after installation to confirm success. Print `[ok]` on success, `[FAILED]` with troubleshooting on failure.

6. **No `set -euo pipefail`** -- the script intentionally omits `set -e` because install failures and soft dependency checks must not abort the script. A header comment documents this exception to the constitution convention. Individual install commands use explicit `if`/`then` checks instead.

### Research Insights

**OS Detection Pattern:**
Use `uname -s` for top-level Darwin/Linux split, then `/etc/debian_version` for Debian family detection. This is simpler than parsing `/etc/os-release` and matches the pattern used in cross-platform install scripts:

```bash
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -f /etc/debian_version ]]; then echo "debian"
      else echo "unknown"
      fi ;;
    *) echo "unknown" ;;
  esac
}
```

**Interactive Prompt Pattern (from worktree-manager.sh:84):**
```bash
echo "  ffmpeg not installed. Install it? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
  # install
fi
```

**Idempotency:**
Both `apt-get install -y` and `brew install` are idempotent -- they succeed silently if the package is already installed. No guard needed beyond the initial `command -v` check.

**`-y` flag is essential** for `apt-get` to avoid hanging on interactive prompts in automated environments. Always pair with `apt-get` (not `apt`) for scripting stability.

## Technical Considerations

- **Idempotency**: Running the script twice is safe -- `apt-get install` and `brew install` are idempotent.
- **No configuration**: This plan covers installation only. rclone configuration (setting up R2 remotes) remains in the rclone skill's `check_setup.sh` and SKILL.md.
- **SKILL.md code blocks**: All prompting and install logic lives in the shell script. SKILL.md Phase 0 references the script with `--auto` flag via an angle-bracket placeholder, not shell variable expansion. Per the `command-substitution-in-plugin-markdown` learning, no `$()` in SKILL.md code blocks.
- **One-shot mechanism**: One-shot (step 9) invokes `soleur:feature-video` via the Skill tool. SKILL.md Phase 0 should instruct: "If this skill is invoked from a pipeline (one-shot), pass `--auto` to the check_deps script." The agent executing the skill can determine pipeline context from the conversation.
- **Permission flow**: The `check_deps.sh` script is invoked via standard `bash ./path/to/script.sh` (not `!` code fence), so it goes through the normal Bash tool permission flow. If the path is not pre-authorized, the user gets a one-time approval prompt.
- **`apt-get` over `apt`**: Scripts should use `apt-get` (not `apt`) because `apt` is designed for interactive terminal use and its output format is not stable across versions.

### Edge Cases

- **`sudo` password required**: `sudo -n true` only succeeds if the user has passwordless sudo or a cached credential. If it fails, the script prints the exact command to run manually and continues with `[skip]`. The user can re-run the skill after installing.
- **Homebrew not installed on macOS**: Detect with `command -v brew`. If missing, print Homebrew installation instructions and continue with `[skip]`.
- **`apt` lock held by another process**: `apt-get install -y` will wait briefly then fail. The script catches the non-zero exit and prints `[FAILED]` with advice to retry.
- **Network unavailable**: Package manager commands fail with non-zero exit. Script catches and prints `[FAILED]`.

## Non-Goals

- Configuring rclone remotes (handled by rclone skill)
- Installing agent-browser (hard dependency, separate concern)
- Building a general-purpose package manager abstraction
- Supporting Windows/WSL or Fedora/RHEL (no current user base)
- Updating the rclone skill's `check_setup.sh` (installation vs configuration boundary)

## Acceptance Criteria

- [x] `check_deps.sh` offers to install ffmpeg when missing (interactive prompt)
- [x] `check_deps.sh` offers to install rclone when missing (interactive prompt)
- [x] `check_deps.sh --auto` installs without prompting (for pipeline use)
- [x] Installation is verified after each tool install (re-check `command -v`)
- [x] Script prints `[ok]` with version after successful install
- [x] Script prints `[FAILED]` with manual instructions if install fails
- [x] Script handles missing `sudo` gracefully (prints command, continues with `[skip]`)
- [x] SKILL.md Phase 0 updated to mention `--auto` for pipeline use
- [x] Existing `[skip]` behavior preserved when user declines installation
- [ ] Version bumped (PATCH) in plugin.json, CHANGELOG.md, README.md, marketplace.json, bug_report.yml

## Test Scenarios

### Installation flow

- Given ffmpeg is not installed, when `check_deps.sh` runs interactively, then user is prompted "Install ffmpeg? (y/N)" and installation proceeds on "y"
- Given rclone is not installed, when `check_deps.sh` runs interactively, then user is prompted "Install rclone? (y/N)" and installation proceeds on "y"
- Given `--auto` flag is passed, when ffmpeg is missing, then ffmpeg is installed without prompting
- Given both tools are already installed, when `check_deps.sh` runs, then both show `[ok]` with no install prompts
- Given user responds "N" to install prompt, then existing `[skip]` behavior is preserved

### OS detection

- Given running on Debian/Ubuntu (`/etc/debian_version` exists), when installing ffmpeg, then `sudo apt-get install -y ffmpeg` is used
- Given running on macOS (`uname -s` returns Darwin), when installing ffmpeg, then `brew install ffmpeg` is used
- Given running on unsupported OS, when tools are missing, then manual install instructions are printed and script continues

### Error handling

- Given user has no sudo access (`sudo -n true` fails), when install is attempted, then script prints the exact command needed and continues with `[skip]`
- Given Homebrew not installed on macOS, when install is attempted, then script prints Homebrew install URL and continues with `[skip]`
- Given network is unavailable, when install fails (non-zero exit from apt-get/brew), then script prints `[FAILED]` and continues
- Given install command exits 0 but binary not found in PATH, then script prints `[FAILED]` with troubleshooting steps

### Pipeline integration

- Given one-shot pipeline invokes feature-video skill, when agent passes `--auto` to check_deps.sh, then ffmpeg and rclone are installed without prompting
- Given one-shot pipeline calls `check_deps.sh --auto`, when install fails, then pipeline degrades gracefully (same as current behavior)

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| `sudo` not available in CI/container | Detect inline with `sudo -n true` and skip with clear message |
| `apt` lock contention | Use `apt-get` with `-y` flag, catch non-zero exit |
| Homebrew not installed on macOS | Detect with `command -v brew`, print install instructions |
| Older rclone version from apt | Acceptable for auto mode; manual instructions reference official script for latest |

## Implementation Plan

### Phase 1: Script Enhancement (`check_deps.sh`)

**File:** `plugins/soleur/skills/feature-video/scripts/check_deps.sh`

1. Add `--auto` flag parsing at top of script (`AUTO_INSTALL=false; [[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true`)
2. Add `detect_os` function using `uname -s` + `/etc/debian_version` pattern
3. Add `install_ffmpeg` function with Debian/macOS branches and inline `sudo -n true` check
4. Add `install_rclone` function with Debian/macOS branches and inline `sudo -n true` check
5. Wire install functions into existing missing-tool `else` branches: if `$AUTO_INSTALL` is true, install directly; otherwise prompt with `read -r`
6. Add post-install verification (`command -v` + version output via `ffmpeg -version | head -1` / `rclone version | head -1`)
7. Update header comment documenting the `set -e` exception: "No set -euo pipefail: soft dependency checks and install failures must not abort the script. Each install command uses explicit if/then checks."

**Estimated script size:** ~90-100 lines (up from 44), well within single-file maintainability.

### Phase 2: SKILL.md Update

**File:** `plugins/soleur/skills/feature-video/SKILL.md`

1. Update Phase 0 to document the `--auto` flag: "When invoked from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts and install missing tools automatically."
2. Use angle-bracket placeholder in code block: `bash ./plugins/soleur/skills/feature-video/scripts/check_deps.sh <auto-flag-if-pipeline>`
3. Update the prerequisite section to note: "ffmpeg and rclone can be installed automatically by the dependency check script."

### Phase 3: Version Bump

1. Bump version (PATCH) across all five files: plugin.json, CHANGELOG.md, README.md badge, marketplace.json, bug_report.yml
2. Add CHANGELOG entry under `### Changed`: "feature-video: check_deps.sh now offers to install ffmpeg and rclone when missing"

## Script Skeleton

Reference implementation structure for `check_deps.sh` (not final code -- implementation may vary):

```text
#!/usr/bin/env bash
# feature-video dependency checker with optional auto-install
# No set -euo pipefail: soft dependency checks and install failures
# must not abort the script. Each install uses explicit if/then checks.

AUTO_INSTALL=false
[[ "${1:-}" == "--auto" ]] && AUTO_INSTALL=true

echo "=== feature-video Dependency Check ==="
echo

# --- OS detection ---
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -f /etc/debian_version ]]; then echo "debian"
      else echo "unknown"
      fi ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)

# --- Install helpers ---
install_ffmpeg() {
  case "$OS" in
    debian)
      if sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y ffmpeg
      else
        echo "  Run: sudo apt-get install -y ffmpeg" >&2
        return 1
      fi ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi ;;
    *)
      echo "  Manual install: https://ffmpeg.org/download.html" >&2
      return 1 ;;
  esac
}

install_rclone() {
  case "$OS" in
    debian)
      if sudo -n true 2>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y rclone
      else
        echo "  Run: sudo apt-get install -y rclone" >&2
        return 1
      fi ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install rclone
      else
        echo "  Install Homebrew first: https://brew.sh" >&2
        return 1
      fi ;;
    *)
      echo "  Manual install: https://rclone.org/install/" >&2
      return 1 ;;
  esac
}

# --- Hard dependency: agent-browser ---
[existing agent-browser check unchanged]

# --- Soft dependency: ffmpeg ---
if command -v ffmpeg >/dev/null 2>&1; then
  echo "  [ok] ffmpeg"
else
  if [[ "$AUTO_INSTALL" == "true" ]]; then
    echo "  [installing] ffmpeg..."
    if install_ffmpeg; then
      # verify
    else
      echo "  [FAILED] ffmpeg installation"
    fi
  else
    echo "  ffmpeg not installed. Install it? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      # install + verify
    else
      echo "  [skip] ffmpeg (declined)"
    fi
  fi
fi

# --- Soft dependency: rclone ---
[same pattern as ffmpeg]

echo
echo "=== Check Complete ==="
```

## References

- PR #331: Preflight dependency check (part 1) -- `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- Issue #325: Original ffmpeg/rclone installation request
- Learning: `knowledge-base/learnings/2026-02-27-feature-video-graceful-degradation.md`
- Learning: `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Learning: `knowledge-base/learnings/2026-02-22-command-substitution-in-plugin-markdown.md`
- Learning: `knowledge-base/learnings/2026-02-24-extract-command-substitution-into-scripts.md`
- Learning: `knowledge-base/learnings/2026-02-25-quoted-dash-strings-trigger-approval-prompts.md`
- Pattern: `plugins/soleur/skills/pencil-setup/SKILL.md` -- auto-detection and installation pattern
- Pattern: `plugins/soleur/skills/rclone/scripts/check_setup.sh` -- rclone check pattern
- Pattern: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:84` -- `read -r` interactive prompt pattern
- External: [Cross-platform bash install automation](https://dev.to/devopsking/automation-with-bash-creating-a-script-to-install-and-configure-applications-on-multiple-flavours-of-os-4o0k)
- External: [Bash dependency installation best practices](https://www.linuxbash.sh/post/installing-software-and-managing-dependencies-in-scripts)
- rclone official install: https://rclone.org/install.sh
