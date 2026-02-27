# Tasks: Competitive Intelligence Agent and Skill

**Issue:** #330
**Branch:** feat-competitive-intelligence
**Plan:** `knowledge-base/plans/2026-02-27-feat-competitive-intelligence-agent-plan.md`

## Phase 1: Core Components

### 1.0 Trim existing agent descriptions for budget headroom
- [x] Measure current budget: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`
- [x] Identify verbose descriptions to trim (`pricing-strategist`, `programmatic-seo-specialist` are candidates)
- [x] Trim 15-20 words to create safe headroom for new agent + sibling disambiguation updates
- [x] Re-verify word count after trimming

### 1.1 Create competitive-intelligence agent
- [x] Create `plugins/soleur/agents/product/competitive-intelligence.md`
- [x] Frontmatter: `name: competitive-intelligence`, `description:` (under 25 words), `model: inherit`
- [x] Description includes disambiguation vs. `business-validator`
- [x] Body: context loading, research process, output contract (with CI fallback), sharp edges
- [x] Verify cumulative description word count under 2,500

### 1.2 Create competitive-analysis skill
- [x] Create `plugins/soleur/skills/competitive-analysis/SKILL.md`
- [x] Frontmatter: `name: competitive-analysis`, third-person description with trigger phrases
- [x] Non-interactive detection: any `$ARGUMENTS` present = skip prompts, use default tiers (0,3)
- [x] Interactive path: AskUserQuestion for tier selection
- [x] Delegates to competitive-intelligence agent via Task tool

## Phase 2: Integration

### 2.1 Update CPO routing
- [x] Add delegation row to `plugins/soleur/agents/product/cpo.md`: competitive analysis signals -> competitive-intelligence
- [x] Update CPO description to include competitive-intelligence in orchestrated agents list

### 2.2 Update sibling agent disambiguation (both directions)
- [x] Update `plugins/soleur/agents/product/business-validator.md` description: add disambiguation referencing competitive-intelligence
- [x] Update `plugins/soleur/agents/marketing/growth-strategist.md` description: add disambiguation referencing competitive-intelligence
- [x] Re-verify cumulative description word count after all description changes

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
