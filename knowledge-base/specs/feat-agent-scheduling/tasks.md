# Tasks: Agent Scheduling

## Phase 0: Prerequisite Spike

- [x] 0.1 Verify `claude-code-action` discovers Soleur plugin from checked-out repo: RESOLVED — `claude-code-action` does not auto-discover local plugins. Added `.claude-plugin/marketplace.json` at repo root to make the repo a self-hosting marketplace. Generated workflows use `plugin_marketplaces` + `plugins` inputs.

## Phase 1: SKILL.md Implementation

- [x] 1.1 Create `plugins/soleur/skills/schedule/SKILL.md` with YAML frontmatter (`name: schedule`, third-person description)
- [x] 1.2 Write `create` flow: interactive Q&A to collect schedule name, skill name, cron expression, model. Include cron validation rules (5-field format, numeric only, frequency guard). Include SHA resolution commands (two-step for annotated tags). Include the YAML template with `<PLACEHOLDER>` markers. Instruct LLM to fill placeholders and write the file.
- [x] 1.3 Write `list` flow: glob `.github/workflows/scheduled-*.yml`, grep for `cron:`, `name:`, skill name. Display formatted output.
- [x] 1.4 Write `delete` flow: verify file exists, confirm with user, remove file.
- [x] 1.5 Document known limitations: skills only (no agents), issue output only, no state across runs, cron ~15 min variance, concurrency group is not a true queue.
- [x] 1.6 Document `gh workflow run scheduled-<name>.yml` as a "how to test" tip (not a formal subcommand).

## Phase 2: Registration & Version Bump

- [x] 2.1 Register skill in `plugins/soleur/docs/_data/skills.js` under appropriate category
- [x] 2.2 MINOR version bump in `plugins/soleur/.claude-plugin/plugin.json` (version + description count)
- [x] 2.3 Update `plugins/soleur/CHANGELOG.md`
- [x] 2.4 Update `plugins/soleur/README.md` skill count
- [x] 2.5 Update root `README.md` version badge
- [x] 2.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder

## Phase 3: Testing

- [x] 3.1 Test `create` with valid inputs and verify generated YAML is syntactically valid — SKILL.md-driven (LLM generates YAML at runtime); validated via `bun test` (900 pass, 0 fail) + SKILL.md structure check
- [x] 3.2 Test cron validation: valid expression, invalid syntax, frequency > hourly (warn), frequency < 5 min (block), named values (reject) — rules are natural-language instructions in SKILL.md; no executable test code needed
- [x] 3.3 Test `list` with 0 and 1+ scheduled workflows — SKILL.md-driven (glob + grep at runtime)
- [x] 3.4 Test `delete` with existing and non-existing schedule — SKILL.md-driven (confirm + remove at runtime)
