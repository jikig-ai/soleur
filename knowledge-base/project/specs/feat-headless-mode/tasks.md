# Tasks: Headless Mode for Repeatable Workflows

**Plan:** `knowledge-base/project/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
**Issue:** #393
**Branch:** feat-headless-mode

## Phase 1: Implementation

### 1.1 Add `--yes` flag to worktree-manager.sh
- [x] Add `--yes` flag detection at script level (parse from `$@` before dispatching to subcommands)
- [x] Modify `create_worktree()`: skip `read -r` at lines 84 and 96 when `--yes` is set
- [x] Modify `cleanup_worktrees()`: skip `read -r` at line 316 when `--yes` is set
- [x] Modify `switch_worktree()`: require name argument when `--yes` is set (no interactive prompt)

**Files:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

### 1.2 Update constitution.md with `--headless` convention
- [x] Add headless mode convention to the `$ARGUMENTS` bypass rule section (strip flag, forward to children, abort on errors, no headless compound on main)

**Files:** `knowledge-base/overview/constitution.md`

### 1.3 Add `--headless` bypass to work skill
- [x] Strip `--headless` from `$ARGUMENTS` before treating remainder as plan path
- [x] Forward `--headless` to compound and ship in Phase 4 handoff (when invoked directly)
- [x] Verify pipeline mode (file path detection) already covers all prompt bypasses — `--headless` should be redundant for work's own prompts

**Files:** `plugins/soleur/skills/work/SKILL.md`

### 1.4 Add `--headless` bypass to compound skill
- [x] Add `--headless` detection and branch safety check (abort if on main/master)
- [x] Constitution promotion: auto-promote using LLM judgment, deduplicate via substring match
- [x] Route-to-definition: auto-accept LLM-proposed edit
- [x] Auto-consolidation: auto-accept all proposals, auto-confirm archival
- [x] Decision menu: auto-select "Continue workflow"
- [x] Worktree cleanup: auto-skip
- [x] Forward `--headless` to compound-capture invocation

**Files:** `plugins/soleur/skills/compound/SKILL.md`

### 1.5 Add `--headless` bypass to compound-capture skill
- [x] Add `--headless` detection
- [x] Step 2 (missing context): infer from session context, skip fields that can't be inferred
- [x] Step 3 (similar issue): default to "create new doc with cross-reference"
- [x] Auto-consolidation Step E (archival): auto-archive
- [x] YAML validation failure: skip problematic learning, continue with remaining

**Files:** `plugins/soleur/skills/compound-capture/SKILL.md`

### 1.6 Add `--headless` bypass to ship skill
- [x] Add `--headless` detection
- [x] Phase 2: auto-invoke `skill: soleur:compound --headless` (forward flag)
- [x] Phase 4 (missing tests): continue without writing
- [x] Phase 6: auto-accept generated PR title/body
- [x] Phase 7 (flaky CI): abort pipeline
- [x] All failure conditions: abort with clear error, do not prompt

**Files:** `plugins/soleur/skills/ship/SKILL.md`

## Phase 2: Follow-Up Issues

### 2.1 Create follow-up issues for descoped items
- [x] Issue: "feat: scheduled-ship-merge workflow" — #417
- [x] Issue: "feat: scheduled-compound-review workflow" — #418
- [x] Issue: "feat: verify PreToolUse hooks in claude-code-action" — #419
