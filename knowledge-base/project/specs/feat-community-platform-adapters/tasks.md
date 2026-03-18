# Tasks: Community Platform Adapter Interface

**Issue:** #470
**Branch:** feat/community-platform-adapters
**Plan:** `knowledge-base/plans/2026-03-13-refactor-community-platform-adapter-interface-plan.md`

[Updated 2026-03-13] Radically simplified. Single phase, 6 tasks.

## Implementation

- [x] 1. Merge `origin/main` into worktree to bring `hn-community.sh`
- [x] 2. Create `community-router.sh` (~50 lines)
  - [x] 2.1 Hardcoded PLATFORMS array (name, script, env vars, auth command)
  - [x] 2.2 `platforms` command — iterate table, check auth, print status
  - [x] 2.3 `<platform> <command> [args]` dispatch via `exec`
  - [x] 2.4 Unknown platform error handling
- [x] 3. Update `SKILL.md` — replace inline platform detection with router reference
- [x] 4. Update `community-manager.md` — replace hardcoded script paths with router dispatch
- [x] 5. Update `scheduled-community-monitor.yml` — replace inline platform logic with router
- [x] 6. End-to-end verification: digest, health, platforms, engage
