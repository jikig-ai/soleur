# Tasks: fix schedule skill template remaining gaps

Issue: #382
Plan: `knowledge-base/plans/2026-03-05-fix-schedule-template-remaining-gaps-plan.md`

## Phase 1: Template Updates

- [ ] 1.1 Add `timeout-minutes` input to Step 1 (interactive collection) with default 30
- [ ] 1.2 Add `--max-turns` input to Step 1 (interactive collection) with default 30
- [ ] 1.3 Add `--timeout` and `--max-turns` flags to Step 0 argument bypass path
- [ ] 1.4 Update template YAML in Step 3:
  - [ ] 1.4.1 Add `timeout-minutes: <TIMEOUT>` to the job block
  - [ ] 1.4.2 Add `--max-turns <MAX_TURNS>` to `claude_args`
  - [ ] 1.4.3 Add label pre-creation step between checkout and claude-code-action

## Phase 2: Known Limitations Cleanup

- [ ] 2.1 Remove stale Known Limitations that have been resolved
- [ ] 2.2 Verify remaining limitations are accurate
- [ ] 2.3 Update Step 4 confirmation summary to include timeout and max-turns

## Phase 3: Validation

- [ ] 3.1 Run markdownlint on updated SKILL.md
- [ ] 3.2 Verify template YAML is valid (manual review of indentation)
- [ ] 3.3 Compare generated template structure against reference workflows
