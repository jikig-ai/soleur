# Tasks: fix worktree auto-install subdirectory deps

Source plan: `knowledge-base/project/plans/2026-03-28-fix-worktree-auto-install-subdirectory-deps-plan.md`

## Phase 1: Core Implementation

- [ ] 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- [ ] 1.2 Extend `install_deps()` to scan `apps/*/package.json` after root install
  - [ ] 1.2.1 Add loop over `"$worktree_path"/apps/*/package.json`
  - [ ] 1.2.2 Skip directories with existing `node_modules/`
  - [ ] 1.2.3 Detect package manager per directory (`bun.lockb` -> bun, `package-lock.json` -> npm)
  - [ ] 1.2.4 Skip directories without any lockfile (warn)
  - [ ] 1.2.5 Run install command, warn on failure but never block
  - [ ] 1.2.6 Declare all variables with `local`; error messages to stderr
- [ ] 1.3 Verify `create_worktree()` and `create_for_feature()` both benefit (they already call `install_deps`)

## Phase 2: Testing

- [ ] 2.1 Manual test: create a new worktree and verify `apps/web-platform/node_modules/` is created
- [ ] 2.2 Manual test: verify `apps/telegram-bridge/` is skipped (no lockfile) with a warning
- [ ] 2.3 Manual test: verify existing `node_modules/` directories are skipped
- [ ] 2.4 Verify script still passes `set -euo pipefail` (no unguarded variables)

## Phase 3: Ship

- [ ] 3.1 Run `npx markdownlint --fix` on changed `.md` files
- [ ] 3.2 Run compound (`soleur:compound`)
- [ ] 3.3 Ship via `soleur:ship`
