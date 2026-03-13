# Tasks: Growth Strategist Agent & Skill

**Plan:** `knowledge-base/plans/2026-02-19-feat-growth-strategist-agent-skill-plan.md`
**Branch:** feat-growth-strategist
**Issue:** #148

## Phase 1: Agent

- [ ] 1.1 Create `plugins/soleur/agents/marketing/growth-strategist.md` with frontmatter (name, description with 2 examples, model: inherit)
- [ ] 1.2 Write opening paragraph (third-person summary, extracted by docs)
- [ ] 1.3 Write body: information requirements per capability, brand guide integration, AEO content-level checks, exclusion rule

## Phase 2: Skill

- [ ] 2.1 Create `plugins/soleur/skills/growth/SKILL.md` with frontmatter (name: growth, third-person description)
- [ ] 2.2 Write sub-command table (audit, plan, aeo) and default behavior (no sub-command -> show table)
- [ ] 2.3 Write each sub-command section with input parsing and agent delegation via Task tool
- [ ] 2.4 Write Important Guidelines section

## Phase 3: Registration

- [ ] 3.1 Add `"growth": "Content & Release"` to `plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES
- [ ] 3.2 Update `plugins/soleur/README.md` -- agent table, skill table, component counts
- [ ] 3.3 Version bump (MINOR) -- plugin.json, CHANGELOG.md, README.md
- [ ] 3.4 Check root README badge, bug_report.yml placeholder, hardcoded version strings in docs HTML

## Phase 4: Verification

- [ ] 4.1 Run `bun test` -- no regressions
- [ ] 4.2 Run `npx @11ty/eleventy` -- docs build succeeds
- [ ] 4.3 Validate agent and skill YAML frontmatter

## Phase 5: Live Test

- [ ] 5.1 Run `growth audit https://soleur.ai`
- [ ] 5.2 Run `growth plan "agentic company" --site https://soleur.ai`
- [ ] 5.3 Run `growth aeo https://soleur.ai`
- [ ] 5.4 Review outputs for quality and usefulness
