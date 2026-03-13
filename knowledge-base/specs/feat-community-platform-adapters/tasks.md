# Tasks: Community Platform Adapter Interface

**Issue:** #470
**Branch:** feat/community-platform-adapters
**Plan:** `knowledge-base/plans/2026-03-13-refactor-community-platform-adapter-interface-plan.md`

[Updated 2026-03-13] Radically simplified. Single phase, 6 tasks.

## Implementation

- [ ] 1. Merge `origin/main` into worktree to bring `hn-community.sh`
- [ ] 2. Create `community-router.sh` (~50 lines)
  - [ ] 2.1 Hardcoded PLATFORMS array (name, script, env vars, auth command)
  - [ ] 2.2 `platforms` command — iterate table, check auth, print status
  - [ ] 2.3 `<platform> <command> [args]` dispatch via `exec`
  - [ ] 2.4 Unknown platform error handling
- [ ] 3. Update `SKILL.md` — replace inline platform detection with router reference
- [ ] 4. Update `community-manager.md` — replace hardcoded script paths with router dispatch
- [ ] 5. Update `scheduled-community-monitor.yml` — replace inline platform logic with router
- [ ] 6. End-to-end verification: digest, health, platforms, engage
