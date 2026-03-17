# Tasks: Consolidate SEO Audit into Weekly Growth Audit

## Phase 1: Workflow Prompt Update

- [x] 1.1 Read `scheduled-growth-audit.yml` to confirm current structure
- [x] 1.2 Renumber existing steps: Content Audit (1), AEO Audit (2), Content Plan (3->4), GitHub Issue (4->5), Persist (5->6)
- [x] 1.3 Insert new Step 3 (Technical SEO Audit) between AEO Audit and Content Plan
  - Launch `seo-aeo-analyst` agent via Task tool
  - Instruct agent to audit https://soleur.ai using WebFetch
  - Save report to `knowledge-base/marketing/audits/soleur-ai/$(date +%Y-%m-%d)-seo-audit.md`
  - Add failure continuation instruction: "If the SEO audit agent fails, note the failure and continue to Step 4"
- [x] 1.4 Update Step 5 (GitHub Issue) to include SEO audit findings summary bullet
- [x] 1.5 Increase `timeout-minutes` from 45 to 55
- [x] 1.6 Increase `--max-turns` from 45 to 55 in `claude_args`

## Phase 2: Validation

- [x] 2.1 Verify the `git add` path in Step 6 already covers the new file (directory glob)
- [x] 2.2 Verify `--allowedTools` includes `WebFetch` and `Task` (both already present)
- [ ] 2.3 Run markdownlint on modified workflow file
- [ ] 2.4 Run compound (`skill: soleur:compound`)

## Phase 3: Ship

- [ ] 3.1 Commit changes
- [ ] 3.2 Push and create PR with `semver:patch` label
