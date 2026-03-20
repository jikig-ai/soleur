# Tasks: Add Sales Domain

## Phase 1: Setup

- [ ] 1.1 Read CLO agent (`plugins/soleur/agents/legal/clo.md`) as template for CRO
- [ ] 1.2 Read brainstorm.md Phase 0.5 Legal routing pattern (lines 77, ~130, ~285) as template for Sales routing
- [ ] 1.3 Run word count baseline: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`

## Phase 2: Token Budget Trimming

- [ ] 2.1 Trim top 5-8 bloated agent descriptions to get under ~2,340 words (leaving ~160 words headroom for 4 new agents)
- [ ] 2.2 Fix CMO description: replace "CRO" abbreviation with "conversion-optimizer"
- [ ] 2.3 Verify word count under 2,340: re-run word count check

## Phase 3: Sales Agents

- [ ] 3.1 Create `agents/sales/cro.md` (domain leader)
  - [ ] 3.1.1 Follow CLO template (3-phase: Assess, Recommend/Delegate, Sharp Edges)
  - [ ] 3.1.2 Include delegation table for 3 specialists
- [ ] 3.2 Create `agents/sales/outbound-strategist.md`
  - [ ] 3.2.1 Disambiguation: "Use copywriter for email copy; use this agent for cadence strategy and audience targeting"
- [ ] 3.3 Create `agents/sales/deal-architect.md`
  - [ ] 3.3.1 Disambiguation: "Use pricing-strategist for product pricing; use this agent for deal-level negotiation"
- [ ] 3.4 Create `agents/sales/pipeline-analyst.md`
  - [ ] 3.4.1 Disambiguation: "Use analytics-analyst for marketing attribution; use this agent for post-MQL sales pipeline metrics"

## Phase 4: Brainstorm Integration

- [ ] 4.1 Add Sales assessment question #7 to Phase 0.5 (after Legal question, before "If no domains" line)
- [ ] 4.2 Add Sales routing block (copy Legal pattern: 2 options -- include CRO / brainstorm normally)
- [ ] 4.3 Add CRO participation block (copy CLO participation template)

## Phase 5: Marketing Agent Disambiguation Updates

- [ ] 5.1 Update `agents/marketing/copywriter.md`: add "Use outbound-strategist for cadence strategy"
- [ ] 5.2 Update `agents/marketing/pricing-strategist.md`: add "Use deal-architect for deal-level negotiation"
- [ ] 5.3 Update `agents/marketing/analytics-analyst.md`: add "Use pipeline-analyst for sales pipeline metrics"
- [ ] 5.4 Update `agents/marketing/conversion-optimizer.md`: add "Use outbound-strategist for human-assisted outbound motions"
- [ ] 5.5 Update `agents/marketing/retention-strategist.md`: add "Use pipeline-analyst for deal-level expansion metrics"

## Phase 6: Docs Site

- [ ] 6.1 Update `docs/_data/agents.js`: add Sales to DOMAIN_LABELS, DOMAIN_CSS_VARS, domainOrder
- [ ] 6.2 Update `docs/css/style.css`: add `--cat-sales: #E06666;`
- [ ] 6.3 Verify docs build: `npx @11ty/eleventy --input=docs --output=docs/_site_test` from repo root
- [ ] 6.4 Clean up: `rm -r docs/_site_test`

## Phase 7: Documentation

- [ ] 7.1 Update `AGENTS.md`: add CRO to domain leader table, update directory tree
- [ ] 7.2 Update `README.md` (plugin): add Sales section to agent tables, update counts
- [ ] 7.3 Verify word count under 2,500: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`

## Phase 8: Version and Ship

- [ ] 8.1 Run `git fetch origin main && git merge origin/main`
- [ ] 8.2 Version bump (MINOR): update `.claude-plugin/plugin.json`, `CHANGELOG.md`, plugin `README.md`
- [ ] 8.3 Update `plugin.json` description agent count
- [ ] 8.4 Update root `README.md` version badge
- [ ] 8.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [ ] 8.6 Run code review
- [ ] 8.7 Run `/soleur:compound`
- [ ] 8.8 Commit, push, create PR
- [ ] 8.9 Wait for CI, merge, cleanup worktree
