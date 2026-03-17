# Tasks: Consolidate SEO Audit into Weekly Growth Audit

## Phase 1: Workflow Prompt Update

- [ ] 1.1 Read `scheduled-growth-audit.yml` to confirm current structure
- [ ] 1.2 Add Step 2.5 (Technical SEO Audit) prompt block between Step 2 and Step 3
  - Launch `seo-aeo-analyst` agent via Task tool
  - Instruct agent to audit https://soleur.ai using WebFetch
  - Save report to `knowledge-base/marketing/audits/soleur-ai/<date>-seo-audit.md`
- [ ] 1.3 Update Step 4 (GitHub Issue) to include SEO audit findings summary
- [ ] 1.4 Increase `timeout-minutes` from 45 to 55

## Phase 2: Validation

- [ ] 2.1 Verify the `git add` path in Step 5 already covers the new file (directory glob)
- [ ] 2.2 Verify `--allowedTools` includes `WebFetch` and `Task` (both already present)
- [ ] 2.3 Run markdownlint on modified workflow file
- [ ] 2.4 Run compound (`skill: soleur:compound`)

## Phase 3: Ship

- [ ] 3.1 Commit changes
- [ ] 3.2 Push and create PR with `semver:patch` label
