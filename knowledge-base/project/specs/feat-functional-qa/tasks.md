# Tasks: Functional QA Skill

## Phase 1: Create SKILL.md

- [ ] 1.1 Create `plugins/soleur/skills/qa/SKILL.md` with YAML frontmatter (`name: qa`, third-person description)
- [ ] 1.2 Implement XML body structure: `<objective>`, `<quick_start>`, `<workflow>`, `<success_criteria>`
- [ ] 1.3 Implement plan parsing — read plan file (passed as arg), extract Test Scenarios section
- [ ] 1.4 Implement environment detection inline — check `DEPLOY_URL`, set Doppler config to `prd` or `dev`
- [ ] 1.5 Implement scenario execution — Playwright MCP for browser steps, `doppler run` + `curl` for API verification
- [ ] 1.6 Implement cleanup step execution — run cleanup commands regardless of pass/fail
- [ ] 1.7 Implement eventual consistency handling — wait + retry up to 3 times before failing
- [ ] 1.8 Implement inline report generation — pass/fail markdown with screenshots and API responses
- [ ] 1.9 Implement graceful degradation — missing prerequisites skip with warning, don't block

## Phase 2: Update Plan Skill + Pipeline

- [ ] 2.1 Update plan skill Test Scenarios format to include explicit verification commands (curl + jq + cleanup templates)
- [ ] 2.2 Update `plugins/soleur/skills/one-shot/SKILL.md` — insert QA step (5.5) between resolve-todo-parallel and compound

## Phase 3: Compliance + Documentation

- [ ] 3.1 Update README.md skill count
- [ ] 3.2 Run `bun test plugins/soleur/test/components.test.ts` — verify description word count under 1,800
- [ ] 3.3 Verify SKILL.md uses XML structure (no markdown headings in body)
