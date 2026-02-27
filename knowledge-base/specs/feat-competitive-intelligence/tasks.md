# Tasks: Competitive Intelligence Agent and Skill

**Issue:** #330
**Branch:** feat-competitive-intelligence
**Plan:** `knowledge-base/plans/2026-02-27-feat-competitive-intelligence-agent-plan.md`

## Phase 1: Core Components

### 1.0 Trim existing agent descriptions for budget headroom
- [ ] Measure current budget: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`
- [ ] Identify verbose descriptions to trim (`pricing-strategist`, `programmatic-seo-specialist` are candidates)
- [ ] Trim 15-20 words to create safe headroom for new agent + sibling disambiguation updates
- [ ] Re-verify word count after trimming

### 1.1 Create competitive-intelligence agent
- [ ] Create `plugins/soleur/agents/product/competitive-intelligence.md`
- [ ] Frontmatter: `name: competitive-intelligence`, `description:` (under 25 words), `model: inherit`
- [ ] Description includes disambiguation vs. `business-validator`
- [ ] Body: context loading, research process, output contract (with CI fallback), sharp edges
- [ ] Verify cumulative description word count under 2,500

### 1.2 Create competitive-analysis skill
- [ ] Create `plugins/soleur/skills/competitive-analysis/SKILL.md`
- [ ] Frontmatter: `name: competitive-analysis`, third-person description with trigger phrases
- [ ] Non-interactive detection: any `$ARGUMENTS` present = skip prompts, use default tiers (0,3)
- [ ] Interactive path: AskUserQuestion for tier selection
- [ ] Delegates to competitive-intelligence agent via Task tool

## Phase 2: Integration

### 2.1 Update CPO routing
- [ ] Add delegation row to `plugins/soleur/agents/product/cpo.md`: competitive analysis signals -> competitive-intelligence
- [ ] Update CPO description to include competitive-intelligence in orchestrated agents list

### 2.2 Update sibling agent disambiguation (both directions)
- [ ] Update `plugins/soleur/agents/product/business-validator.md` description: add disambiguation referencing competitive-intelligence
- [ ] Update `plugins/soleur/agents/marketing/growth-strategist.md` description: add disambiguation referencing competitive-intelligence
- [ ] Re-verify cumulative description word count after all description changes

## Phase 3: Version Bump and Documentation

### 3.1 Version bump (MINOR)
- [ ] Verify actual counts via `find`: `find plugins/soleur/agents -name '*.md' | wc -l` and `find plugins/soleur/skills -mindepth 1 -name 'SKILL.md' | wc -l`
- [ ] `plugins/soleur/.claude-plugin/plugin.json` -- bump version, update description counts
- [ ] `plugins/soleur/CHANGELOG.md` -- new version entry
- [ ] `plugins/soleur/README.md` -- update agent/skill counts and tables
- [ ] `.claude-plugin/marketplace.json` -- match version
- [ ] Root `README.md` -- version badge
- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml` -- placeholder
- [ ] `docs/_data/skills.js` -- register competitive-analysis skill under "Review & Planning" category

### 3.2 Validate
- [ ] Agent description word count under 2,500
- [ ] No `<example>` blocks in agent descriptions
- [ ] Skill description uses third person
- [ ] All files use correct frontmatter fields
- [ ] Disambiguation sentences present in both directions (new agent references siblings, siblings reference new agent)
