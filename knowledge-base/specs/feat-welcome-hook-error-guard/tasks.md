# Tasks: fix welcome-hook.sh error guard

Source: `knowledge-base/plans/2026-03-18-fix-welcome-hook-error-guard-plan.md`
Closes: #692

## Phase 1: Core Implementation

- [x] 1.1 Add `|| { exit 0; }` guard to `plugins/soleur/hooks/welcome-hook.sh` line 6 after the `source` command
- [x] 1.2 Add inline comment matching stop-hook.sh pattern: `# Not in a git repo -- skip welcome silently`

## Phase 2: Testing

- [x] 2.1 Verify hook exits 0 outside a git repo (run in a temp dir with no `.git`)
- [x] 2.2 Verify hook still works inside a git repo (sentinel check + welcome JSON output)
- [x] 2.3 Run existing `resolve-git-root.test.sh` to confirm no regressions

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit, push, create PR with `Closes #692` in body
- [ ] 3.3 Set `semver:patch` label
