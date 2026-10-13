# Tasks: Supervised Bug-Fix Agent

## Phase 0: Prerequisites

- [ ] 0.1 Update triage workflow cron from `'0 6 * * *'` to `'0 4 * * *'` in `.github/workflows/scheduled-daily-triage.yml`

## Phase 1: Core Skill

- [ ] 1.1 Create `plugins/soleur/skills/fix-issue/SKILL.md` with frontmatter (`name: fix-issue`, third-person description)
- [ ] 1.2 Implement issue reading and open-state validation
- [ ] 1.3 Implement test baseline capture (`bun test` before changes, record pass/fail state)
- [ ] 1.4 Implement fix attempt with prompt constraints (single-file, no deps/schemas/infra, injection prevention)
- [ ] 1.5 Implement post-fix test comparison (new failures vs baseline)
- [ ] 1.6 Implement commit, push, and PR creation with `Ref #N` in body (never `Closes`)
- [ ] 1.7 Implement failure handling: comment on issue, add `bot-fix/attempted` label
- [ ] 1.8 Include PR body template with bot-fix footer and manual close instruction
- [ ] 1.9 Ensure `$ARGUMENTS` bypass works for CI callers

## Phase 2: Workflow

- [ ] 2.1 Create `.github/workflows/scheduled-bug-fixer.yml` with cron at `'0 6 * * *'`
- [ ] 2.2 Add `oven-sh/setup-bun` step
- [ ] 2.3 Add label pre-creation step for `bot-fix/attempted`
- [ ] 2.4 Add issue selection step with jq filtering (exclude `bot-fix/attempted`, sort by createdAt ascending)
- [ ] 2.5 Add `workflow_dispatch` input for manual issue override
- [ ] 2.6 Pin action SHAs (reuse from `scheduled-daily-triage.yml`)
- [ ] 2.7 Configure permissions, concurrency group, timeout, and claude_args

## Phase 3: Plugin Registration

- [ ] 3.1 Bump version 3.7.18 → 3.8.0 per AGENTS.md plugin versioning checklist
- [ ] 3.2 Register skill in `plugins/soleur/docs/_data/skills.js` under "Workflow" category
- [ ] 3.3 Update `plugin.json` description skill count
- [ ] 3.4 Update `plugins[0].version` in `.claude-plugin/marketplace.json`
