# Tasks: Domain Leader Pattern

**Plan:** `knowledge-base/plans/2026-02-20-feat-domain-leaders-plan.md`
**Issue:** #154

## Phase 1: CMO Agent

- [x] 1.1 Create `plugins/soleur/agents/marketing/cmo.md` with frontmatter and body (absorb marketing-strategist sharp edges + add orchestration)
- [x] 1.2 Delete `plugins/soleur/agents/marketing/marketing-strategist.md`
- [x] 1.3 Update disambiguation in `plugins/soleur/agents/marketing/conversion-optimizer.md` (marketing-strategist -> cmo)
- [x] 1.4 Update disambiguation in `plugins/soleur/agents/marketing/retention-strategist.md` (marketing-strategist -> cmo)
- [x] 1.5 Verify token budget: `grep -h 'description:' agents/**/*.md | wc -w` < 2500

## Phase 2: CTO Agent (Lightweight)

- [x] 2.1 Create `plugins/soleur/agents/engineering/cto.md` (brainstorm participation only, no orchestration duplication)
- [x] 2.2 Verify token budget stays under 2500 words

## Phase 3: `/soleur:marketing` Skill

- [x] 3.1 Create `plugins/soleur/skills/marketing/SKILL.md` with audit, strategy, launch sub-commands (third-person description)
- [x] 3.2 Register skill in `plugins/soleur/docs/_data/skills.js` under "Content & Release" category

## Phase 4: Brainstorm Domain Detection (LLM-Based)

- [x] 4.1 Rewrite brainstorm.md Phase 0.5 with LLM-based domain assessment (replace keyword matching)
- [x] 4.2 Preserve brand workshop bypass for brand-specific detections
- [x] 4.3 Add marketing domain routing (CMO joins brainstorm when marketing-relevant)
- [x] 4.4 Add engineering domain routing (CTO joins brainstorm when architecture-relevant)
- [x] 4.5 Update extension comment for future domains

## Phase 5: Documentation and Versioning

- [x] 5.1 Add Domain Leader Interface section to `plugins/soleur/AGENTS.md`
- [x] 5.2 Update `plugins/soleur/README.md` tables and counts (45 agents, 45 skills)
- [x] 5.3 Update `plugins/soleur/.claude-plugin/plugin.json` version (MINOR) and description ("45 agents...45 skills")
- [x] 5.4 Update `plugins/soleur/CHANGELOG.md`
- [x] 5.5 Update `plugins/soleur/NOTICE` (marketing-strategist -> cmo)
- [x] 5.6 Update root `README.md` version badge
- [x] 5.7 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- [x] 5.8 Update `plugins/soleur/docs/_data/agents.js` if domain labels need changes
- [x] 5.9 Final token budget verification
