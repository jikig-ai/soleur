# Tasks: Pre-Merge Hooks for Auto-Rebase

Source plan: `knowledge-base/plans/2026-03-03-feat-pre-merge-hooks-auto-rebase-plan.md`

## Phase 1: Setup

- [ ] 1.1 Create `.claude/hooks/pre-merge-rebase.sh` with the hook script from the plan MVP
- [ ] 1.2 Make the script executable (`chmod +x`)
- [ ] 1.3 Register the hook in `.claude/settings.json` under the `PreToolUse` array

## Phase 2: Core Implementation

- [ ] 2.1 Implement early-exit for non-`gh pr merge` commands
- [ ] 2.2 Implement working directory resolution (cd extraction, `cwd` fallback)
- [ ] 2.3 Implement uncommitted changes check with `permissionDecision: "deny"`
- [ ] 2.4 Implement `git fetch origin main` with fail-open on network error
- [ ] 2.5 Implement up-to-date detection via merge-base comparison
- [ ] 2.6 Implement rebase execution with conflict handling and `rebase --abort`
- [ ] 2.7 Implement `git push --force-with-lease` after successful rebase

## Phase 3: Testing

- [ ] 3.1 Test: non-merge command passes through immediately
- [ ] 3.2 Test: branch already up-to-date with main proceeds without rebase
- [ ] 3.3 Test: branch behind main triggers rebase and force-push
- [ ] 3.4 Test: uncommitted changes blocks merge with clear message
- [ ] 3.5 Test: rebase conflict aborts and blocks with file list
- [ ] 3.6 Test: chained command detection (`&& gh pr merge`)
- [ ] 3.7 Test: network failure on fetch degrades gracefully
