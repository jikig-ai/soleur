# Tasks: Rolling Campaign Calendar

## Phase 1: Skill Implementation

- [x] 1.1 Create `plugins/soleur/skills/campaign-calendar/SKILL.md`
  - [x] 1.1.1 Frontmatter: `name: campaign-calendar`, third-person description with trigger keywords
  - [x] 1.1.2 Phase 1: Glob `knowledge-base/marketing/distribution-content/*.md`, read each file's frontmatter
  - [x] 1.1.3 Phase 2: Classify entries into 4 groups (overdue, upcoming, draft, published) using publish_date + status
  - [x] 1.1.4 Phase 3: Generate markdown table per group, write to `knowledge-base/marketing/campaign-calendar.md` with `last_updated` frontmatter
  - [x] 1.1.5 Phase 4 (CI only): `git add`, `git diff --cached --quiet` guard, `git commit -m "ci: update campaign calendar [skip ci]"`, `git push` with rebase-retry
  - [x] 1.1.6 Manual mode: write file, print "Calendar written. To persist, run: gh workflow run scheduled-campaign-calendar.yml"
  - [x] 1.1.7 Handle edge cases: zero files (empty state message), malformed frontmatter (skip with note)

## Phase 2: CI Workflow

- [x] 2.1 Resolve action SHAs: `actions/checkout@v4`, `anthropics/claude-code-action@v1`
- [x] 2.2 Create `.github/workflows/scheduled-campaign-calendar.yml`
  - [x] 2.2.1 Cron: `0 16 * * 1` (Monday 16:00 UTC, after content-publisher's 14:00)
  - [x] 2.2.2 `workflow_dispatch` for on-demand
  - [x] 2.2.3 Concurrency group: `schedule-campaign-calendar`, `cancel-in-progress: false`
  - [x] 2.2.4 Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [x] 2.2.5 `plugin_marketplaces` and `plugins` inputs for Soleur discovery
  - [x] 2.2.6 `--allowedTools Bash,Read,Write,Edit,Glob,Grep`
  - [x] 2.2.7 Prompt includes AGENTS.md main-commit override and commit/push instructions
  - [x] 2.2.8 Discord failure notification step
- [x] 2.3 Validate workflow YAML syntax with `python3 -c "import yaml; yaml.safe_load(...)"`

## Phase 3: Registration

- [x] 3.1 Add `campaign-calendar` to `docs/_data/skills.js` `SKILL_CATEGORIES`
- [x] 3.2 Update skill count in `plugins/soleur/README.md`
- [x] 3.3 Update skill count in `README.md` (root)
- [x] 3.4 Update skill count in `knowledge-base/overview/brand-guide.md` (2 occurrences)
- [ ] 3.5 Update skill count in `plugin.json` description — N/A, plugin.json description has no skill count

## Phase 4: Testing

- [x] 4.1 SKILL.md exists with correct frontmatter (58 skills on disk confirmed)
- [ ] 4.2 Manual invocation test — deferred to post-merge (skill runs on content files)
- [ ] 4.3 Empty directory handling — covered by SKILL.md Phase 1 step 2
- [ ] 4.4 components.test.ts — N/A, no such test exists in this repo
