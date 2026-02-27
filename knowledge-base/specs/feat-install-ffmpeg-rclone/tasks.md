# Tasks: Install ffmpeg and rclone on demand

## Phase 1: Script Enhancement

- [ ] 1.1 Add `--auto` flag parsing and OS detection to `check_deps.sh`
  - Parse `$1` for `--auto`, set `AUTO_INSTALL=false` / `true`
  - Add `detect_os` function: `uname -s` for Darwin/Linux, `/etc/debian_version` for Debian family, return `debian`/`macos`/`unknown`
  - Update header comment documenting `set -e` exception
- [ ] 1.2 Add install functions and wire into missing-tool branches
  - Add `install_ffmpeg`: Debian (`sudo apt-get update -qq && sudo apt-get install -y ffmpeg`), macOS (`brew install ffmpeg`), unknown (print manual URL)
  - Add `install_rclone`: Debian (`sudo apt-get update -qq && sudo apt-get install -y rclone`), macOS (`brew install rclone`), unknown (print manual URL)
  - Inline `sudo -n true 2>/dev/null` check before apt-get commands; `command -v brew` check before brew commands
  - If `AUTO_INSTALL=true`: call install function directly
  - If `AUTO_INSTALL=false`: prompt with `read -r` (pattern from worktree-manager.sh:84), call on "y", print `[skip]` on "N"
- [ ] 1.3 Add post-install verification
  - After each install: `command -v <tool>` to verify, print `[ok] <tool> (installed)` with `<tool> -version | head -1`
  - On verification failure: print `[FAILED] <tool> installation failed` with troubleshooting (check PATH, retry manually)

## Phase 2: SKILL.md Update

- [ ] 2.1 Update Phase 0 section in `plugins/soleur/skills/feature-video/SKILL.md`
  - Document `--auto` flag via angle-bracket placeholder (no `$()` in code blocks per command-substitution learning)
  - Add note: "When invoked from a pipeline (e.g., one-shot), pass --auto to skip interactive prompts"
  - Update prerequisite section to note auto-install capability

## Phase 3: Version Bump and CHANGELOG

- [ ] 3.1 Bump PATCH version across all five files (plugin.json, CHANGELOG.md, README.md badge, marketplace.json, bug_report.yml)
- [ ] 3.2 Add CHANGELOG entry under `### Changed`: "feature-video: check_deps.sh now offers to install ffmpeg and rclone when missing"

## Phase 4: Verification

- [ ] 4.1 Run `check_deps.sh` with tools installed -- verify `[ok]` for both
- [ ] 4.2 Run `bun test` to ensure no regressions
- [ ] 4.3 Verify script conventions: `#!/usr/bin/env bash` shebang, snake_case functions, `[[ ]]` tests, error messages to stderr
