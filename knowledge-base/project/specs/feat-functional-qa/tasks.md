# Tasks: Functional QA Skill

## Phase 1: Skill Skeleton + Environment Detection

- [ ] 1.1 Create skill directory `plugins/soleur/skills/qa/`
- [ ] 1.2 Create `SKILL.md` with YAML frontmatter (name: qa, third-person description) and XML body structure
- [ ] 1.3 Create `scripts/detect-environment.sh` — auto-detect dev vs prd Doppler config
- [ ] 1.4 Create `references/qa-scenario-format.md` — guide for writing verifiable test scenarios in plans
- [ ] 1.5 Verify skill appears in `/soleur:help` output
- [ ] 1.6 Run `bun test plugins/soleur/test/components.test.ts` — verify description word count under 1,800

## Phase 2: Core QA Logic in SKILL.md

- [ ] 2.1 Implement plan parsing — read plan file, extract Test Scenarios section
- [ ] 2.2 Implement scenario classification — browser-only, API-only, browser+API
- [ ] 2.3 Implement browser flow execution — Playwright MCP navigate, fill, submit, verify UI state
  - [ ] 2.3.1 Handle absolute paths for worktree compatibility
  - [ ] 2.3.2 Handle Playwright MCP unavailability (graceful skip with warning)
- [ ] 2.4 Implement API verification — Doppler credential injection, curl construction, response parsing
  - [ ] 2.4.1 Handle missing Doppler secrets (graceful skip per-scenario)
  - [ ] 2.4.2 Handle eventual consistency (retry with exponential backoff: 3s, 6s, 12s)
- [ ] 2.5 Implement error path testing — Playwright route interception for network failures
- [ ] 2.6 Implement graceful degradation for missing prerequisites (no Test Scenarios, no Playwright, no Doppler)

## Phase 3: Report Generation + Pipeline Integration

- [ ] 3.1 Create `scripts/generate-report.sh` — format pass/fail markdown report with evidence
- [ ] 3.2 Implement report generation in SKILL.md — aggregate results, include screenshots and API responses
- [ ] 3.3 Update `plugins/soleur/skills/one-shot/SKILL.md` — insert QA step between resolve-todo-parallel (step 5) and compound (step 6)
- [ ] 3.4 Verify pipeline integration — QA blocks on failure, passes through on success

## Phase 4: Compliance + Documentation

- [ ] 4.1 Verify SKILL.md uses pure XML structure (no markdown headings in body)
- [ ] 4.2 Verify all reference files linked with proper markdown links (not backtick paths)
- [ ] 4.3 Update README.md skill count
- [ ] 4.4 Run `bun test plugins/soleur/test/components.test.ts` — final compliance check
