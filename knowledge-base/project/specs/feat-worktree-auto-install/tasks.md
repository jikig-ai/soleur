# Tasks: fix worktree auto-install subdirectory deps

Source plan: `knowledge-base/project/plans/2026-03-28-fix-worktree-auto-install-subdirectory-deps-plan.md`

## Phase 1: Core Implementation

- [x] 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- [x] 1.2 Extend `install_deps()` with subdirectory install block (reference implementation in plan)
  - [x] 1.2.1 Add `for app_dir in "$worktree_path"/apps/*/` loop with `[[ -d ]]` null-glob guard
  - [x] 1.2.2 Skip directories with existing `node_modules/`
  - [x] 1.2.3 Detect package manager per directory: `bun.lockb` -> bun, `package-lock.json` -> `npm ci --prefix`, `yarn.lock` -> yarn
  - [x] 1.2.4 Skip directories without any lockfile (warn to stderr)
  - [x] 1.2.5 Run install command, warn on failure but never block
  - [x] 1.2.6 Declare all variables with `local`; warning messages to stderr via `>&2`
- [x] 1.3 Verify `create_worktree()` and `create_for_feature()` both benefit (they already call `install_deps`)

## Phase 2: Testing

- [x] 2.1 Manual test: create a new worktree and verify `apps/web-platform/node_modules/` is created
- [x] 2.2 Manual test: verify `apps/telegram-bridge/` is skipped (no lockfile) with a warning
- [x] 2.3 Manual test: verify existing `node_modules/` directories are skipped
- [x] 2.4 Verify script still passes `set -euo pipefail` (no unguarded variables)

## Phase 3: Ship

- [ ] 3.1 Run `npx markdownlint --fix` on changed `.md` files
- [ ] 3.2 Run compound (`soleur:compound`)
- [ ] 3.3 Ship via `soleur:ship`
