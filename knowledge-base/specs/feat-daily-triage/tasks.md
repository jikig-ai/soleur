# Tasks: Daily Triage Automation

## Phase 1: Update ticket-triage Agent

- [ ] 1.1 Rewrite description in third person ("Classifies and routes..." not "Use this agent...")
- [ ] 1.2 Add disambiguation sentence for daily triage workflow
- [ ] 1.3 No behavioral changes (agent stays read-only for interactive use)

## Phase 2: Create Workflow

- [ ] 2.1 Resolve action SHAs
  - [ ] 2.1.1 `actions/checkout@v4` -- two-step dereference for annotated tag
  - [ ] 2.1.2 `anthropics/claude-code-action@v1` -- two-step dereference
- [ ] 2.2 Create `.github/workflows/scheduled-daily-triage.yml`
  - [ ] 2.2.1 Copy `scheduled-competitive-analysis.yml` as base
  - [ ] 2.2.2 Set cron: `0 6 * * *` + workflow_dispatch
  - [ ] 2.2.3 Set concurrency: `schedule-daily-triage`, cancel-in-progress: false
  - [ ] 2.2.4 Set permissions: contents: read, issues: write, id-token: write
  - [ ] 2.2.5 Set timeout-minutes: 60
  - [ ] 2.2.6 Write label pre-creation step (15 labels with colors and descriptions)
  - [ ] 2.2.7 Write claude-code-action step with direct classification prompt
  - [ ] 2.2.8 Set claude_args: `--model claude-sonnet-4-6 --max-turns 80 --allowedTools Bash,Read,Glob,Grep`
  - [ ] 2.2.9 Embed classification rubric (priority, type, domain criteria)
  - [ ] 2.2.10 Add idempotency: skip issues with existing priority/* labels
  - [ ] 2.2.11 Add prompt injection guard in prompt text
- [ ] 2.3 Validate YAML syntax
- [ ] 2.4 Update `plugins/soleur/skills/triage/SKILL.md` -- add daily-triage disambiguation

## Phase 3: Version Bump and Documentation

- [ ] 3.1 Count components from disk: `ls plugins/soleur/skills/*/SKILL.md | wc -l` and `find plugins/soleur/agents -name '*.md' | wc -l`
- [ ] 3.2 MINOR bump in `plugins/soleur/.claude-plugin/plugin.json` -- update version and counts
- [ ] 3.3 Add changelog entry in `plugins/soleur/CHANGELOG.md`
- [ ] 3.4 Verify/update `plugins/soleur/README.md` counts
- [ ] 3.5 Update `plugins/soleur/.claude-plugin/marketplace.json` version
- [ ] 3.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [ ] 3.7 Update root `README.md` version badge

## Phase 4: Deferred Work

- [ ] 4.1 File GitHub issue for schedule skill template gaps (6 items)
