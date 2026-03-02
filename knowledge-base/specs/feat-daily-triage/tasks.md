# Tasks: Daily Triage Automation

## Phase 1: Fix Schedule Skill Template

- [ ] 1.1 Add `--max-turns` parameter to `claude_args` in the generated YAML template
  - [ ] 1.1.1 Add AskUserQuestion step to collect max-turns value (default: 30)
  - [ ] 1.1.2 Inject `--max-turns <N>` into the claude_args line
- [ ] 1.2 Add `timeout-minutes` to the job block
  - [ ] 1.2.1 Add AskUserQuestion step to collect timeout value (default: 45)
  - [ ] 1.2.2 Inject `timeout-minutes: <N>` after `runs-on: ubuntu-latest`
- [ ] 1.3 Add label pre-creation step before claude-code-action step
  - [ ] 1.3.1 Generate `gh label create scheduled-<NAME> --description "..." --color "0E8A16" 2>/dev/null || true`
- [ ] 1.4 Add skill argument passthrough
  - [ ] 1.4.1 Add optional `--args` flag to Step 0 short-circuit and Step 1 collection
  - [ ] 1.4.2 Inject args into the prompt: `Run /soleur:<SKILL_NAME> <ARGS>`
- [ ] 1.5 Add `Task` to `--allowedTools` list in the template
- [ ] 1.6 Update Known Limitations section
  - [ ] 1.6.1 Remove stale `--allowedTools` gap (already fixed v3.7.6)
  - [ ] 1.6.2 Update remaining gaps to reflect new fixes

## Phase 2: Extend ticket-triage Agent

- [ ] 2.1 Rewrite `plugins/soleur/agents/support/ticket-triage.md`
  - [ ] 2.1.1 Update description with label/comment capability
  - [ ] 2.1.2 Add guard clause for interactive vs workflow mode
  - [ ] 2.1.3 Add 5-dimension classification rubric with criteria
  - [ ] 2.1.4 Add `gh issue edit --add-label` instructions
  - [ ] 2.1.5 Add `gh issue comment --body` instructions
  - [ ] 2.1.6 Add idempotency rule (skip issues with severity/* labels)
  - [ ] 2.1.7 Add pagination (`--limit 200`)
  - [ ] 2.1.8 Add prompt injection guard
  - [ ] 2.1.9 Update Sharp Edges (allow labels/comments, still no close/delete)
  - [ ] 2.1.10 Update disambiguation sentence

## Phase 3: Create daily-triage Skill

- [ ] 3.1 Create `plugins/soleur/skills/daily-triage/SKILL.md`
  - [ ] 3.1.1 Write YAML frontmatter (name, description with disambiguation)
  - [ ] 3.1.2 Write label pre-creation script (20 labels with colors)
  - [ ] 3.1.3 Write ticket-triage delegation via Task tool
  - [ ] 3.1.4 Write summary reporting section

## Phase 4: Generate Workflow

- [ ] 4.1 Resolve action SHAs for `actions/checkout@v4` and `anthropics/claude-code-action@v1`
- [ ] 4.2 Create `.github/workflows/scheduled-daily-triage.yml`
  - [ ] 4.2.1 Cron schedule: `0 6 * * *` + workflow_dispatch
  - [ ] 4.2.2 Concurrency group: `schedule-daily-triage`, cancel-in-progress: false
  - [ ] 4.2.3 Permissions: issues: write, contents: read, id-token: write
  - [ ] 4.2.4 timeout-minutes: 60
  - [ ] 4.2.5 Label pre-creation step (20 labels with colors and descriptions)
  - [ ] 4.2.6 claude-code-action step with direct classification prompt
  - [ ] 4.2.7 claude_args: `--model claude-sonnet-4-6 --max-turns 80 --allowedTools Bash,Read,Glob,Grep`
  - [ ] 4.2.8 Embed full classification rubric in the prompt
- [ ] 4.3 Validate YAML syntax

## Phase 5: Version Bump and Documentation

- [ ] 5.1 Bump version to 3.8.0 in `plugins/soleur/.claude-plugin/plugin.json`
- [ ] 5.2 Update skill count (reconcile 53/54 discrepancy, add 1 for daily-triage)
- [ ] 5.3 Add v3.8.0 entry to `plugins/soleur/CHANGELOG.md`
- [ ] 5.4 Update `plugins/soleur/README.md` skill count and table
- [ ] 5.5 Update `plugins/soleur/.claude-plugin/marketplace.json` version
- [ ] 5.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [ ] 5.7 Update root `README.md` version badge

## Phase 6: Testing and Validation

- [ ] 6.1 Run `bun test` to verify no regressions
- [ ] 6.2 Validate YAML syntax of generated workflow
- [ ] 6.3 Test daily-triage skill locally (dry-run against real issues)
- [ ] 6.4 Manual dispatch of workflow via `gh workflow run`
