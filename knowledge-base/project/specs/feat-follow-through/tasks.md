# Tasks: Follow-Through — Automated External Dependency Tracking

**Plan:** [2026-04-03-feat-follow-through-tracking-plan.md](../../plans/2026-04-03-feat-follow-through-tracking-plan.md)
**Spec:** [spec.md](./spec.md)

## Phase 1: /ship Step 3.5 — Detection & Issue Creation

### 1.1 Add Step 3.5 to /ship SKILL.md "If merged" block

- [ ] Read `plugins/soleur/skills/ship/SKILL.md`
- [ ] Insert Step 3.5 inside Phase 7's "If merged" block, after Step 3 (post-merge workflow validation), before Step 4 (cleanup)
- [ ] Write detection instructions: read PR body via `gh pr view`, scan for `- [ ] ⏳` pattern (also handle `- [X] ⏳` uppercase variant)
- [ ] Write label creation instructions (follow-through, needs-attention) with `gh label create`
- [ ] Write issue creation instructions with fenced YAML verification block template (all issues default to `manual` type, `5 business days` SLA)
- [ ] Add "If no ⏳-marked items found: skip silently" guard
- [ ] Ensure all instructions use angle-bracket placeholders (no `$()` command substitution)
- [ ] Run `npx markdownlint-cli2 --fix plugins/soleur/skills/ship/SKILL.md`

### 1.2 Write failing tests for detection (TDD gate)

- [ ] Create test file for ⏳ detection regex: various PR body formats
- [ ] Test: unchecked ⏳ item detected
- [ ] Test: checked ⏳ item ignored (`- [x]` lowercase)
- [ ] Test: checked ⏳ item ignored (`- [X]` uppercase)
- [ ] Test: non-⏳ unchecked item ignored
- [ ] Test: empty PR body produces zero items

## Phase 2: Daily Monitor Workflow

### 2.1 Resolve action SHAs

- [ ] Resolve `actions/checkout@v4` SHA via `gh api repos/actions/checkout/git/ref/tags/v4`
- [ ] Resolve `anthropics/claude-code-action@v1` SHA via `gh api`
- [ ] Record SHAs for use in workflow file

### 2.2 Create scheduled-follow-through.yml

- [ ] Create `.github/workflows/scheduled-follow-through.yml`
- [ ] Add security comment header (document that issue content is read by agent, not interpolated)
- [ ] Configure: `cron: '0 9 * * 1-5'`, `workflow_dispatch: {}`
- [ ] Configure: `concurrency: group: schedule-follow-through, cancel-in-progress: false`
- [ ] Configure: `permissions: contents: read, issues: write, id-token: write`
- [ ] Configure: `timeout-minutes: 15`
- [ ] Configure: `claude_args` with `--allowedTools Bash,Read,Glob,Grep`
- [ ] Add label pre-creation step (follow-through, needs-attention)
- [ ] Write agent prompt with:
  - [ ] List open follow-through issues
  - [ ] Extract fenced YAML code block from issue body
  - [ ] Calculate business days elapsed (skip weekends)
  - [ ] Execute predicates (curl for http-200, dig for dns-txt/dns-a)
  - [ ] Auto-close on predicate pass with "Verified" comment
  - [ ] Escalate on SLA exceeded: add needs-attention label, @-mention author
  - [ ] Close on 30 business day max with @-mention and escalation comment
  - [ ] No comments within SLA when no state change (silent)
- [ ] Add sharp edges (never modify issue body, never create issues, handle failures gracefully)
- [ ] Validate YAML: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-follow-through.yml'))"`
- [ ] Run `npx markdownlint-cli2 --fix` on any changed .md files

## Phase 3: Testing & Validation

### 3.1 Pre-merge validation

- [ ] Verify YAML syntax is valid
- [ ] Review /ship SKILL.md changes for consistency with existing Phase 7 style
- [ ] Verify no heredocs or multi-line strings in YAML run blocks
- [ ] Verify all `gh issue create` commands include `--milestone`

### 3.2 Post-merge validation

- [ ] Trigger manual workflow run: `gh workflow run scheduled-follow-through.yml`
- [ ] Poll until complete: `gh run view <id> --json status,conclusion`
- [ ] Verify workflow handles "no open follow-through issues" gracefully
- [ ] Create a test follow-through issue with `http-200` predicate pointing to a known-good URL
- [ ] Re-trigger workflow and verify it processes the test issue correctly
- [ ] Clean up test issue after validation
