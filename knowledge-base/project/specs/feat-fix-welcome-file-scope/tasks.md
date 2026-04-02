# Tasks: fix welcome file scope

Plan: `knowledge-base/project/plans/2026-04-02-fix-welcome-file-scope-plan.md`
Issue: #1383

## Phase 1: Implementation

### 1.1 Add Soleur project detection guard to welcome-hook.sh

- [ ] Read `plugins/soleur/hooks/welcome-hook.sh`
- [ ] Add project detection block after `PROJECT_ROOT` assignment (line 10) and before sentinel check (line 13)
- [ ] Detection checks: (1) `plugins/soleur/` directory exists, (2) `CLAUDE.md` contains `soleur:` reference
- [ ] Exit 0 cleanly if neither condition is met
- [ ] Verify `set -euo pipefail` compatibility (grep with `2>/dev/null`, `[[ ]]` tests)

**File:** `plugins/soleur/hooks/welcome-hook.sh`

## Phase 2: Testing

### 2.1 Write shell script tests for the welcome hook

- [ ] Test: non-Soleur git repo -- hook exits 0, no sentinel file created
- [ ] Test: git repo with `CLAUDE.md` not referencing Soleur -- hook exits 0, no sentinel file created
- [ ] Test: git repo with `plugins/soleur/` directory -- hook creates sentinel and outputs welcome JSON
- [ ] Test: git repo with `CLAUDE.md` containing `soleur:help` -- hook creates sentinel and outputs welcome JSON
- [ ] Test: Soleur project with existing sentinel -- hook exits 0 immediately

### 2.2 Manual verification

- [ ] Run the modified hook from a non-Soleur project directory
- [ ] Confirm no `.claude/soleur-welcomed.local` is created
- [ ] Run the modified hook from the Soleur worktree
- [ ] Confirm welcome message appears on first run

## Phase 3: Cleanup

### 3.1 Run linting and commit

- [ ] Run `npx markdownlint-cli2 --fix` on changed `.md` files
- [ ] Run compound before committing
