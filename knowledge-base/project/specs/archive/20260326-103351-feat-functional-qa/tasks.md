# Tasks: Functional QA Skill

## Phase 1: Create SKILL.md

- [x] 1.1 Create `plugins/soleur/skills/qa/SKILL.md` with YAML frontmatter (`name: qa`, third-person description)
- [x] 1.2 Implement markdown body structure (following codebase convention, not XML)
- [x] 1.3 Implement plan parsing — read plan file (passed as arg), extract Test Scenarios section
- [x] 1.4 Implement environment detection inline — check `DEPLOY_URL`, set Doppler config to `prd` or `dev`
- [x] 1.5 Implement scenario execution — Playwright MCP for browser steps, `doppler run` + `curl` for API verification
- [x] 1.6 Implement cleanup step execution — run cleanup commands regardless of pass/fail
- [x] 1.7 Implement eventual consistency handling — wait + retry up to 3 times before failing
- [x] 1.8 Implement inline report generation — pass/fail markdown with screenshots and API responses
- [x] 1.9 Implement graceful degradation — missing prerequisites skip with warning, don't block

## Phase 2: Update Plan Skill + Pipeline

- [x] 2.1 Update plan skill Test Scenarios format to include explicit verification commands (curl + jq + cleanup templates)
- [x] 2.2 Update `plugins/soleur/skills/one-shot/SKILL.md` — insert QA step (5.5) between resolve-todo-parallel and compound

## Phase 3: Compliance + Documentation

- [x] 3.1 Update README.md skill count (59 → 60) and add QA to skill table
- [x] 3.2 Run `bun test plugins/soleur/test/components.test.ts` — 943 pass, 0 fail (trimmed triage description to stay under 1,800 word budget)
- [x] 3.3 Verify SKILL.md uses markdown headings (matching codebase convention, not XML — all existing skills use markdown)
