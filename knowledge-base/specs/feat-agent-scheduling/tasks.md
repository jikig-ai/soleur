# Tasks: Agent Scheduling

## Phase 1: Setup

- [ ] 1.1 Create skill directory structure: `plugins/soleur/skills/schedule/` and `plugins/soleur/skills/schedule/scripts/`
- [ ] 1.2 Verify `claude-code-action` plugin discovery: create a minimal test workflow that invokes a Soleur skill via `claude-code-action` and confirm the plugin is auto-discovered from the checked-out repo
- [ ] 1.3 Resolve current SHAs for `anthropics/claude-code-action@v1` and `actions/checkout@v4` using `gh api`

## Phase 2: Core Implementation — Bash Script

- [ ] 2.1 Create `plugins/soleur/skills/schedule/scripts/schedule-manager.sh` with subcommand routing (create, list, delete, run, validate-cron)
- [ ] 2.2 Implement `validate-cron` subcommand
  - [ ] 2.2.1 Validate 5-field format
  - [ ] 2.2.2 Validate field ranges (minutes 0-59, hours 0-23, day 1-31, month 1-12, dow 0-6)
  - [ ] 2.2.3 Warn if effective interval < 1 hour
  - [ ] 2.2.4 Block if effective interval < 5 minutes
- [ ] 2.3 Implement `create` subcommand (YAML generation via heredoc)
  - [ ] 2.3.1 Generate workflow YAML for `issue` output mode with correct permissions and prompt
  - [ ] 2.3.2 Generate workflow YAML for `pr` output mode with correct permissions and prompt
  - [ ] 2.3.3 Generate workflow YAML for `discord` output mode with correct permissions and prompt
  - [ ] 2.3.4 Include concurrency group, SHA-pinned actions, and failure notification step in all templates
  - [ ] 2.3.5 Validate name (lowercase, hyphens, no collisions with existing files)
  - [ ] 2.3.6 Check for `ANTHROPIC_API_KEY` secret and warn if missing
- [ ] 2.4 Implement `list` subcommand
  - [ ] 2.4.1 Glob `scheduled-*.yml` and parse YAML for name, cron, skill, output mode
  - [ ] 2.4.2 Add run status column from `gh run list` if `gh` is authenticated (graceful degradation)
- [ ] 2.5 Implement `delete` subcommand (verify file exists, remove it)
- [ ] 2.6 Implement `run` subcommand (`gh workflow run scheduled-<name>.yml`)

## Phase 3: SKILL.md

- [ ] 3.1 Create `plugins/soleur/skills/schedule/SKILL.md` with YAML frontmatter (name, description in third person)
- [ ] 3.2 Document subcommands with usage examples
- [ ] 3.3 Write `create` flow: interactive Q&A using AskUserQuestion pattern to collect skill name, cron, output mode, model
- [ ] 3.4 Write routing logic for subcommands (parse args, invoke `schedule-manager.sh`)
- [ ] 3.5 Document known limitations (skills only for v1, no state across runs, cron variance)

## Phase 4: Registration & Version Bump

- [ ] 4.1 Register skill in `plugins/soleur/docs/_data/skills.js` under appropriate category
- [ ] 4.2 MINOR version bump in `plugins/soleur/.claude-plugin/plugin.json`
- [ ] 4.3 Update `plugins/soleur/CHANGELOG.md`
- [ ] 4.4 Update `plugins/soleur/README.md` skill count
- [ ] 4.5 Update root `README.md` version badge
- [ ] 4.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder

## Phase 5: Testing

- [ ] 5.1 Test `create` with each output mode and verify generated YAML is valid
- [ ] 5.2 Test cron validation (valid, invalid syntax, < 5 min, < 1 hour)
- [ ] 5.3 Test `list` with 0, 1, and multiple scheduled workflows
- [ ] 5.4 Test `delete` with existing and non-existing schedule
- [ ] 5.5 Test `run` with a workflow that exists on the default branch
- [ ] 5.6 Validate generated YAML against GitHub Actions schema (basic syntax check)
