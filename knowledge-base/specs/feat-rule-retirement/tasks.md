# Tasks: Automated Rule Retirement

**Plan:** `knowledge-base/plans/2026-03-05-feat-rule-retirement-audit-plan.md`
**Issue:** #422
**Branch:** feat-rule-retirement

## Phase 1: Audit Script Foundation

- [ ] 1.1 Create `plugins/soleur/skills/rule-retirement/scripts/rule-audit.sh` with `set -euo pipefail`
- [ ] 1.2 Implement constitution.md parser: count `^- ` bullets per `## Domain` > `### Always/Never/Prefer` section with structural validation
- [ ] 1.3 Implement AGENTS.md parser: count bullets under Hard Rules, Workflow Gates, Communication
- [ ] 1.4 Implement hook parser: read `.claude/settings.json` registered hooks, extract comment headers from each script
- [ ] 1.5 Add hardcoded hook-to-prose mapping table (6 guards -> 9 prose rules)
- [ ] 1.6 Implement cross-reference logic: for each mapping entry, verify prose rule still exists at expected location
- [ ] 1.7 Implement duplicate detection: find rules appearing in both constitution.md and AGENTS.md
- [ ] 1.8 Generate markdown audit report (table: rule text, location, tier, proposed action)
- [ ] 1.9 Add fingerprint generation (`<!-- audit-fingerprint: constitution=N,agents=N,superseded=N -->`)

## Phase 2: Idempotency and Issue/PR Management

- [ ] 2.1 Implement idempotency check: search open issues by label `rule-audit/report`, compare fingerprint
- [ ] 2.2 Implement close-and-replace: close stale issue with "Superseded by #N" when findings change
- [ ] 2.3 Implement GitHub issue creation with audit report body and labels
- [ ] 2.4 Implement PR creation: generate branch, apply `[hook-enforced]` annotations to constitution.md and AGENTS.md cross-references
- [ ] 2.5 Implement PR idempotency: search by label `rule-audit/migration`, close-and-replace
- [ ] 2.6 Add exit-code checking for all `gh` CLI calls
- [ ] 2.7 Handle partial state: if issue succeeds but PR fails, note in issue body

## Phase 3: GitHub Actions Workflow

- [ ] 3.1 Create `.github/workflows/scheduled-rule-audit.yml` with `workflow_dispatch` trigger only (no cron yet)
- [ ] 3.2 Add label pre-creation step: `rule-audit/report`, `rule-audit/migration`, `rule-audit/compound-finding`
- [ ] 3.3 Pin action references to commit SHAs with version comments
- [ ] 3.4 Add explicit permissions block (`contents: write`, `issues: write`, `pull-requests: write`)
- [ ] 3.5 Add concurrency group to prevent parallel runs
- [ ] 3.6 Add `$GITHUB_OUTPUT` sanitization with `printf` + `tr -d '\n\r'`
- [ ] 3.7 Test with `workflow_dispatch` and verify issue + PR creation

## Phase 4: Compound Rule Budget Gate

- [ ] 4.1 Add Phase 1.6 to `plugins/soleur/skills/compound/SKILL.md` after Phase 1.5 (Deviation Analyst)
- [ ] 4.2 Implement rule count per layer (reuse parser logic from audit script via inline instructions)
- [ ] 4.3 Implement always-loaded total calculation with token estimate (~4 tokens per rule)
- [ ] 4.4 Implement threshold warning (250 default) with budget display format
- [ ] 4.5 Implement Deviation Analyst cross-reference: check Phase 1.5 proposals against hook mapping
- [ ] 4.6 Implement GitHub issue auto-filing for warnings with label `rule-audit/compound-finding`
- [ ] 4.7 Implement issue deduplication: search by label, compare fingerprint, skip if identical
- [ ] 4.8 Support headless mode (warn without prompting, still file issues)

## Phase 5: Documentation and Integration

- [ ] 5.1 Update spec.md with resolved open questions (guard count, threshold, matching algorithm)
- [ ] 5.2 Add comment in hook scripts pointing to mapping table location for maintenance
- [ ] 5.3 Update README.md component counts if new skill directory created
- [ ] 5.4 Run compound to validate Phase 1.6 works in the current session
