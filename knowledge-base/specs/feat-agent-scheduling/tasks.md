# Tasks: Agent Scheduling

## Phase 0: Prerequisite Spike

- [ ] 0.1 Verify `claude-code-action` discovers Soleur plugin from checked-out repo: create a minimal test workflow, push to a test branch, trigger via `workflow_dispatch`, and confirm the plugin's skills are available. If discovery fails, design the fallback path (explicit `plugin_marketplaces`, `claude_args`, or setup step).

## Phase 1: SKILL.md Implementation

- [ ] 1.1 Create `plugins/soleur/skills/schedule/SKILL.md` with YAML frontmatter (`name: schedule`, third-person description)
- [ ] 1.2 Write `create` flow: interactive Q&A to collect schedule name, skill name, cron expression, model. Include cron validation rules (5-field format, numeric only, frequency guard). Include SHA resolution commands (two-step for annotated tags). Include the YAML template with `<PLACEHOLDER>` markers. Instruct LLM to fill placeholders and write the file.
- [ ] 1.3 Write `list` flow: glob `.github/workflows/scheduled-*.yml`, grep for `cron:`, `name:`, skill name. Display formatted output.
- [ ] 1.4 Write `delete` flow: verify file exists, confirm with user, remove file.
- [ ] 1.5 Document known limitations: skills only (no agents), issue output only, no state across runs, cron ~15 min variance, concurrency group is not a true queue.
- [ ] 1.6 Document `gh workflow run scheduled-<name>.yml` as a "how to test" tip (not a formal subcommand).

## Phase 2: Registration & Version Bump

- [ ] 2.1 Register skill in `plugins/soleur/docs/_data/skills.js` under appropriate category
- [ ] 2.2 MINOR version bump in `plugins/soleur/.claude-plugin/plugin.json` (version + description count)
- [ ] 2.3 Update `plugins/soleur/CHANGELOG.md`
- [ ] 2.4 Update `plugins/soleur/README.md` skill count
- [ ] 2.5 Update root `README.md` version badge
- [ ] 2.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder

## Phase 3: Testing

- [ ] 3.1 Test `create` with valid inputs and verify generated YAML is syntactically valid
- [ ] 3.2 Test cron validation: valid expression, invalid syntax, frequency > hourly (warn), frequency < 5 min (block), named values (reject)
- [ ] 3.3 Test `list` with 0 and 1+ scheduled workflows
- [ ] 3.4 Test `delete` with existing and non-existing schedule
