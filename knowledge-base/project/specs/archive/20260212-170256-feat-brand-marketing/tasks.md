# Tasks: Brand Vision, Strategy & Marketing Tools

**Feature:** feat-brand-marketing
**Issue:** #71
**Plan:** `knowledge-base/plans/2026-02-12-feat-brand-marketing-tools-plan.md`

## Phase 1: Brand Architect Agent + Brand Guide

- [x] 1.1 Create `plugins/soleur/agents/marketing/` directory
- [x] 1.2 Write `brand-architect.md` with YAML frontmatter (name, description with 2 example blocks, model: inherit)
- [x] 1.3 Implement full workshop flow: Identity, Voice, Visual Direction, Channel Notes -- one section at a time via AskUserQuestion
- [x] 1.4 Implement visual direction step with gemini-imagegen (graceful skip when GEMINI_API_KEY missing)
- [x] 1.5 Implement atomic write of brand-guide.md with last_updated frontmatter and all four ## sections per Brand Guide Contract
- [x] 1.6 Implement update mode: detect existing brand-guide.md, present summary, allow section-by-section editing, preserve untouched sections

## Phase 2: Discord Content Skill

- [x] 2.1 Create `plugins/soleur/skills/discord-content/` directory
- [x] 2.2 Write `SKILL.md` with YAML frontmatter (name, third-person description with triggers)
- [x] 2.3 Implement prerequisite checks (brand-guide.md exists, DISCORD_WEBHOOK_URL set -- with setup instructions on failure)
- [x] 2.4 Implement freeform topic input with optional git activity summary shortcut
- [x] 2.5 Implement content generation referencing brand guide ## Voice and ## Channel Notes > ### Discord sections
- [x] 2.6 Implement inline brand voice check (validate against Do's/Don'ts before presenting)
- [x] 2.7 Implement 2000-char limit enforcement
- [x] 2.8 Implement user approval flow (Accept/Edit/Reject via AskUserQuestion)
- [x] 2.9 Implement Discord webhook posting via curl with JSON-escaped plain content field
- [x] 2.10 Implement error handling (display error + draft for manual copy-paste on webhook failure)

## Phase 3: Plugin Versioning and Documentation

- [x] 3.1 Bump version in `plugins/soleur/.claude-plugin/plugin.json` (MINOR: 2.1.1 -> 2.2.0)
- [x] 3.2 Update description counts in plugin.json (23 agents, 35 skills)
- [x] 3.3 Update `plugins/soleur/CHANGELOG.md` with v2.2.0 section
- [x] 3.4 Update `plugins/soleur/README.md` -- add marketing agents section, add discord-content to skills table, update counts
- [x] 3.5 Update root `README.md` version badge
- [x] 3.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [ ] 3.7 Run code review on all changes
- [ ] 3.8 Run `/soleur:compound` to capture learnings
