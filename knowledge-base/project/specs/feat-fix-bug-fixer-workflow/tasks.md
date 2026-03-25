# Tasks: Fix Bug Fixer Workflow Resilience

## Phase 1: Core Changes

- [ ] 1.1 Open `.github/workflows/scheduled-bug-fixer.yml`
- [ ] 1.2 Change `--max-turns 25` to `--max-turns 35` in the `Fix issue` step (line 126)
- [ ] 1.3 Change `if: steps.select.outputs.issue` to `if: always() && steps.select.outputs.issue` on the "Detect bot-fix PR" step (line 136)
- [ ] 1.4 Change `if: steps.detect_pr.outputs.pr_number` to `if: always() && steps.detect_pr.outputs.pr_number` on the "Auto-merge gate" step (line 157)
- [ ] 1.5 Change `if: steps.detect_pr.outputs.pr_number` to `if: always() && steps.detect_pr.outputs.pr_number` on the "Discord notification" step (line 214)

## Phase 2: Documentation Update

- [ ] 2.1 Update `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` to reflect bug fixer budget change from 25 to 35

## Phase 3: Validation

- [ ] 3.1 Run `actionlint` or YAML syntax check on the modified workflow file
- [ ] 3.2 Run compound before committing
