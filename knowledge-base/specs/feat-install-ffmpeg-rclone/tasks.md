# Tasks: Install ffmpeg and rclone on demand

## Phase 1: Script Enhancement

- [ ] 1.1 Add `--auto` flag parsing and install functions to `check_deps.sh`
  - Parse `$1` for `--auto`, set `AUTO_INSTALL` variable
  - Add `install_ffmpeg` function: Debian (`apt-get install -y ffmpeg`), macOS (`brew install ffmpeg`), fallback (print manual instructions)
  - Add `install_rclone` function: Debian (`apt-get install -y rclone`), macOS (`brew install rclone`), fallback (print manual instructions with official script URL)
  - Inline `sudo -n true` check before install commands; print command and `[skip]` if no sudo
- [ ] 1.2 Wire install functions into missing-tool branches
  - If not `--auto`: prompt "Install <tool>? (y/N)" via `read -p`
  - If `--auto`: install without prompting
  - On decline: preserve existing `[skip]` behavior
- [ ] 1.3 Add post-install verification and update header comment
  - Re-run `command -v` after install; print `[ok] <tool> (installed)` with version on success
  - Print `[FAILED] <tool> installation failed` with troubleshooting on failure
  - Update script header comment documenting `set -e` exception

## Phase 2: SKILL.md Update

- [ ] 2.1 Update Phase 0 section to document `--auto` flag
  - Use angle-bracket placeholder for the flag, not shell variable expansion
  - Add note about one-shot pipeline passing `--auto`
  - Update prerequisite section to note auto-install capability

## Phase 3: Version Bump and CHANGELOG

- [ ] 3.1 Bump PATCH version across all five files (plugin.json, CHANGELOG.md, README.md badge, marketplace.json, bug_report.yml)
- [ ] 3.2 Add CHANGELOG entry under `### Changed`

## Phase 4: Verification

- [ ] 4.1 Run `check_deps.sh` with tools installed -- verify `[ok]` for both
- [ ] 4.2 Run `bun test` to ensure no regressions
- [ ] 4.3 Verify script shebang and style conventions match constitution
