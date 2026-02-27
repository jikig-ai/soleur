# Learning: Adapting check_deps.sh Pattern for GUI Desktop Apps

## Problem
PR #337 established a `check_deps.sh` pattern for CLI tool dependencies (ffmpeg, rclone) using `install_tool()` with apt-get/brew. When applying this pattern to Pencil Desktop (a GUI app not in any package manager), the automated install approach breaks down: there's no `apt-get install pencil` or `brew install pencil`.

## Solution
Adapted the pattern by replacing `install_tool()`/`attempt_install()`/`verify_install()` with platform-specific `detect_*` functions:

1. **Detection replaces installation for Desktop apps**: `detect_pencil_desktop()` uses platform-specific checks (macOS: app bundle test + mdfind Spotlight fallback, Linux: AppImage search in ~/Applications, ~/.local/bin, /opt, cross-platform: command -v) instead of trying to install. **Correction (v3.7.7):** Linux detection was originally `dpkg -s pencil` but Pencil has no .deb package -- fixed to AppImage glob.
2. **Informational notice instead of hard exit**: Missing Desktop app shows `[info]` with download URL. **Correction (v3.7.7):** Originally exited 1, but dogfooding proved Pencil Desktop is optional -- the MCP server comes from the IDE extension, not the Desktop app.
3. **`--auto` flag scope is narrower**: Only applies to IDE extension install (`cursor --install-extension`), not to the Desktop app itself. IDE extension marketplaces have their own signing/review, making auto-install safe
4. **CLI name collision mitigation**: `command -v pencil` is a cross-platform fallback, not the primary check, because evolus/pencil (a different tool) uses the same binary name

The output convention from feature-video is preserved: `[ok]`, `[MISSING]`, `[installing]`, `[FAILED]`, `[info]`.

## Key Insight
The check_deps.sh pattern has two layers: the **structure** (banner, detection, status tags, --auto flag, exit codes) and the **installation mechanism** (install_tool with package managers). The structure is reusable across any dependency type. The installation mechanism only works for package-manager dependencies. For GUI apps distributed as .dmg/.deb/.AppImage, replace automated install with clear manual instructions and a download URL. Never auto-download desktop app binaries via curl -- package managers provide integrity verification that raw downloads lack.

## Session Errors
1. Version drift: worktree created at v3.7.2 but main had advanced to v3.7.3, requiring `git merge origin/main` before version bump
2. marketplace.json path: attempted read at `plugins/soleur/.claude-plugin/marketplace.json` (wrong), actual path is root `.claude-plugin/marketplace.json`

## Tags
category: integration-issues
module: pencil-setup, check-deps
symptoms: dependency check for GUI app without package manager, pencil CLI name collision with evolus/pencil
