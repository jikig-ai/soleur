# Tasks: Dogfood Competitive-Intelligence Schedule

## Phase 1: Setup

- [x] 1.1 Verify `ANTHROPIC_API_KEY` repository secret exists (`gh secret list`)
- [x] 1.2 Verify `.claude-plugin/marketplace.json` exists and has correct plugin version (3.7.0)

## Phase 2: Core Implementation

- [x] 2.1 Run `/soleur:schedule create --name competitive-analysis --skill competitive-analysis --cron "0 9 1 * *" --model claude-sonnet-4-6`
- [x] 2.2 Verify generated workflow file at `.github/workflows/scheduled-competitive-analysis.yml`
- [x] 2.3 Confirm actions are SHA-pinned (not mutable tags like `@v4`)
- [x] 2.4 Edit prompt to include `--tiers 0,3` after `/soleur:competitive-analysis` (template does not support skill-specific args)
- [x] 2.5 Add `--max-turns 30` to `claude_args` field for sufficient scan depth
- [x] 2.6 Validate YAML syntax passes (`python3 -c "import yaml; ..."`)
- [x] 2.7 Confirm concurrency group is set with `cancel-in-progress: false`
- [x] 2.8 Confirm permissions include `contents: read` and `issues: write`

## Phase 3: Ship and Validate

- [ ] 3.1 Commit workflow file
- [ ] 3.2 Push to `feat/dogfood-competitive-intel` branch
- [ ] 3.3 Create PR targeting main
- [ ] 3.4 After PR merges, trigger `gh workflow run scheduled-competitive-analysis.yml`
- [ ] 3.5 Monitor run via `gh run watch`
- [ ] 3.6 Verify the workflow run creates a GitHub Issue with competitive intelligence content
- [ ] 3.7 Verify the issue has `scheduled-competitive-analysis` label
- [ ] 3.8 Verify the issue contains: executive summary, overlap matrix, source URLs
