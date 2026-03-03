# Tasks: Headless Mode for Repeatable Workflows

**Plan:** `knowledge-base/plans/2026-03-03-feat-headless-mode-repeatable-workflows-plan.md`
**Issue:** #393
**Branch:** feat-headless-mode

## Phase 1: Foundation

### 1.1 Add `--yes` flag to worktree-manager.sh
- [ ] Add `--yes` flag detection at script level (parse from `$@` before dispatching to subcommands)
- [ ] Modify `create_worktree()`: skip `read -r` at lines 84 and 96 when `--yes` is set
- [ ] Modify `cleanup_worktrees()`: skip `read -r` at line 316 when `--yes` is set
- [ ] Modify `switch_worktree()`: require name argument when `--yes` is set (no interactive prompt)
- [ ] Test: `worktree-manager.sh create feat-test --yes` completes without prompt
- [ ] Test: `worktree-manager.sh cleanup --yes` completes without prompt

**Files:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

### 1.2 Update constitution.md with `--headless` convention
- [ ] Add headless mode convention to the `$ARGUMENTS` bypass rule section
- [ ] Document: word-boundary matching (exact token, not substring)
- [ ] Document: strip `--headless` before processing remaining args
- [ ] Document: forward `--headless` to child Skill invocations
- [ ] Document: abort on unrecoverable errors (non-zero exit)
- [ ] Document: never run headless compound on main/master

**Files:** `knowledge-base/overview/constitution.md`

## Phase 2: Core Skill Bypass

### 2.1 Add `--headless` bypass to work skill
- [ ] Add `--headless` detection: word-boundary match in `$ARGUMENTS`
- [ ] Strip `--headless` from `$ARGUMENTS` before treating remainder as plan path
- [ ] Phase 1 branch decision: auto-continue on current branch
- [ ] Phase 1 clarifying questions: auto-skip
- [ ] Phase 2 Tier 0/A/B offers: auto-select without prompting (align with existing pipeline mode behavior)
- [ ] Phase 4 handoff: detect invocation context, auto-continue
- [ ] Verify: `--headless` and pipeline mode (file path detection) are complementary, not conflicting

**Files:** `plugins/soleur/skills/work/SKILL.md`

### 2.2 Add `--headless` bypass to compound skill
- [ ] Add `--headless` detection: word-boundary match in `$ARGUMENTS`
- [ ] Add branch safety check: abort if on main/master when `--headless` is set
- [ ] Constitution promotion: auto-promote using LLM judgment (max 3 per run)
- [ ] Route-to-definition: auto-accept LLM-proposed edit
- [ ] Auto-consolidation: auto-accept all proposals, auto-confirm archival
- [ ] Decision menu: auto-select "Continue workflow"
- [ ] Worktree cleanup: auto-skip
- [ ] YAML validation failure: skip problematic learning, continue with remaining
- [ ] Verify HARD RULE compliance: promotion RUNS (auto-approved), it is NOT skipped

**Files:** `plugins/soleur/skills/compound/SKILL.md`

### 2.3 Add `--headless` bypass to ship skill
- [ ] Add `--headless` detection: word-boundary match in `$ARGUMENTS`
- [ ] Phase 2 compound invocation: auto-invoke `skill: soleur:compound --headless` (forward flag)
- [ ] Phase 4 test failure: abort pipeline with non-zero exit (do not prompt to fix)
- [ ] Phase 6 PR title/body: auto-accept generated content from diff analysis
- [ ] Phase 6.5 merge conflict: abort pipeline, log conflicting files
- [ ] Verify: `--headless` is forwarded to compound invocation

**Files:** `plugins/soleur/skills/ship/SKILL.md`

## Phase 3: Enforcement

### 3.1 Add lefthook pre-commit check
- [ ] Create check script that greps skill SKILL.md files for `AskUserQuestion`
- [ ] Verify each match also has `--headless` or bypass pattern in the same file
- [ ] Exclude intentionally-interactive skills: brainstorm, plan, brainstorm-techniques, deepen-plan, content-writer, discord-content, legal-generate, legal-audit
- [ ] Output warning (not blocking error) for skills missing bypass
- [ ] Add to lefthook.yml as a pre-commit check

**Files:** `scripts/check-headless-bypass.sh` (new), `lefthook.yml`

## Phase 4: Follow-Up Issues

### 4.1 Create follow-up issues for descoped items
- [ ] Issue: "feat: scheduled-ship-merge workflow" — define qualifying criteria, workflow architecture, concurrency
- [ ] Issue: "feat: scheduled-compound-review workflow" — design sessionless compound for cron execution
- [ ] Issue: "feat: verify PreToolUse hooks in claude-code-action" — empirical test, add inline fallbacks if needed
- [ ] Update spec.md to reference follow-up issues

**Files:** GitHub Issues (via `gh issue create`)

## Phase 5: Documentation & Cleanup

### 5.1 Update spec.md with final decisions
- [ ] Update acceptance criteria to reflect descoped items
- [ ] Add SpecFlow gap resolutions (branch safety, volume cap, error handling)

### 5.2 Update README.md counts if needed
- [ ] Verify component counts are accurate after changes

**Files:** `knowledge-base/specs/feat-headless-mode/spec.md`, `README.md`
