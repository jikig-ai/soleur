# Tasks: Rolling Campaign Calendar

## Phase 1: Skill Implementation

- [ ] 1.1 Create `plugins/soleur/skills/campaign-calendar/SKILL.md`
  - [ ] 1.1.1 Frontmatter: `name: campaign-calendar`, third-person description with trigger keywords
  - [ ] 1.1.2 Phase 1: Glob `knowledge-base/marketing/distribution-content/*.md`, read each file's frontmatter
  - [ ] 1.1.3 Phase 2: Classify entries into 4 groups (overdue, upcoming, draft, published) using publish_date + status
  - [ ] 1.1.4 Phase 3: Generate markdown table per group, write to `knowledge-base/marketing/campaign-calendar.md` with `last_updated` frontmatter
  - [ ] 1.1.5 Phase 4 (CI only): `git add`, `git diff --cached --quiet` guard, `git commit -m "ci: update campaign calendar [skip ci]"`, `git push` with rebase-retry
  - [ ] 1.1.6 Manual mode: write file, print "Calendar written. To persist, run: gh workflow run scheduled-campaign-calendar.yml"
  - [ ] 1.1.7 Handle edge cases: zero files (empty state message), malformed frontmatter (skip with note)

## Phase 2: CI Workflow

- [ ] 2.1 Resolve action SHAs: `actions/checkout@v4`, `anthropics/claude-code-action@v1`
- [ ] 2.2 Create `.github/workflows/scheduled-campaign-calendar.yml`
  - [ ] 2.2.1 Cron: `0 16 * * 1` (Monday 16:00 UTC, after content-publisher's 14:00)
  - [ ] 2.2.2 `workflow_dispatch` for on-demand
  - [ ] 2.2.3 Concurrency group: `schedule-campaign-calendar`, `cancel-in-progress: false`
  - [ ] 2.2.4 Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] 2.2.5 `plugin_marketplaces` and `plugins` inputs for Soleur discovery
  - [ ] 2.2.6 `--allowedTools Bash,Read,Write,Edit,Glob,Grep`
  - [ ] 2.2.7 Prompt includes AGENTS.md main-commit override and commit/push instructions
  - [ ] 2.2.8 Discord failure notification step
- [ ] 2.3 Validate workflow YAML syntax with `python3 -c "import yaml; yaml.safe_load(...)"`

## Phase 3: Registration

- [ ] 3.1 Add `campaign-calendar` to `docs/_data/skills.js` `SKILL_CATEGORIES`
- [ ] 3.2 Update skill count in `plugins/soleur/README.md`
- [ ] 3.3 Update skill count in `README.md` (root)
- [ ] 3.4 Update skill count in `knowledge-base/overview/brand-guide.md` (2 occurrences)
- [ ] 3.5 Update skill count in `plugin.json` description

## Phase 4: Testing

- [ ] 4.1 Invoke `/soleur:campaign-calendar` manually and verify output has 4 status groups
- [ ] 4.2 Verify overdue detection (file with scheduled + past date)
- [ ] 4.3 Verify empty directory handling
- [ ] 4.4 Verify `components.test.ts` passes (SKILL.md present and valid)
