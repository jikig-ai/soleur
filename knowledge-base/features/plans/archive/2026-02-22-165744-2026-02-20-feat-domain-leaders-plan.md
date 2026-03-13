---
title: "feat: Add Domain Leader pattern with CTO and CMO agents"
type: feat
date: 2026-02-20
---

# Domain Leader Pattern -- CTO + CMO

## Overview

Add a Domain Leader pattern to Soleur where each business domain has a leader agent that orchestrates its specialist team. Build CMO (marketing) and CTO (engineering) as the first two leaders. Generalize the brainstorm command's domain routing to detect when domains are relevant and offer to loop in their leaders. Create a `/soleur:marketing` skill as standalone entry point for marketing work.

## Problem Statement

Soleur has 12 marketing agents but no coordinator. The brainstorm/plan/work/review/ship workflow is engineering-implicit -- marketing participation requires the user to know which marketing agent to invoke. Cross-domain features (product launches, pricing changes) get no automatic marketing consideration. The existing `marketing-strategist` agent provides strategy but does not orchestrate the marketing team.

## Proposed Solution

1. **CMO agent** -- Replaces `marketing-strategist`. Orchestrates 11 marketing specialists. Participates in brainstorm via domain detection.
2. **CTO agent** -- Lightweight. Formalizes engineering participation in brainstorm domain detection. Proves the pattern is generalizable.
3. **`/soleur:marketing` skill** -- Standalone entry point with sub-commands: `audit`, `strategy`, `launch`.
4. **Brainstorm domain detection** -- Generalize Phase 0.5 from brand-only to multi-domain. CMO absorbs brand routing.

## Technical Approach

### Architecture

The Domain Leader Interface is a documented contract, not a runtime abstraction. Each leader agent follows the same 4-phase pattern in its body:

| Phase | Contract | CMO Example |
|-------|----------|-------------|
| Assess | Evaluate current domain state | Check brand guide, SEO health, content gaps |
| Recommend | Propose domain-specific actions | "Run content audit, update landing page" |
| Delegate | Spawn specialists via Task tool | Task growth-strategist, Task seo-aeo-analyst |
| Review | Validate output against domain standards | Brand voice consistency, SEO compliance |

**Domain detection** uses LLM semantic assessment (replacing the existing keyword substring matching). The brainstorm command instructs Claude to assess whether the feature description has marketing or engineering implications. Adding a new domain means adding one assessment question. This is more accurate than keywords and naturally extensible.

**Brand routing migration:** The CMO absorbs brand detection. When brand keywords match, the CMO offers two options: (a) "Start brand workshop" (preserves existing brand-architect bypass) or (b) "Include marketing perspective" (new: CMO joins the brainstorm). This preserves backward compatibility.

### Scope Clarification

**In scope (this PR):**

- CMO agent + marketing-strategist removal
- CTO agent (lightweight)
- `/soleur:marketing` skill (audit, strategy, launch)
- Brainstorm Phase 0.5 generalization (marketing + engineering domains)
- Domain Leader Interface documented in AGENTS.md

**Deferred to follow-up issues:**

- Domain detection in plan command
- Domain detection in work command
- Domain detection in review command
- Domain detection in ship command
- Agent Teams integration for domain leaders
- Leader-to-leader communication protocol

### Implementation Phases

#### Phase 1: CMO Agent

**Deliverable:** `plugins/soleur/agents/marketing/cmo.md`

Create the CMO agent absorbing marketing-strategist's sharp edges and adding orchestration capabilities.

**Frontmatter:**

```yaml
---
name: cmo
description: "Orchestrates the marketing domain -- assesses marketing posture, creates unified strategy, and delegates to specialist agents (brand, SEO, content, community, CRO, paid, pricing, retention). Use individual marketing agents for focused tasks; use this agent for cross-cutting marketing strategy and multi-agent coordination."
model: inherit
---
```

**Body sections:**

1. **Role** -- Marketing department leader. Assess before acting. Strategy before tactics.
2. **Assess phase** -- Check brand guide existence, read it if present. Inventory marketing artifacts (docs, content, SEO state). Report gaps.
3. **Recommend phase** -- Prioritize marketing initiatives. Use marketing-strategist's sharp edges: positioning audit first, three-phase launch plans, name specific cognitive biases, structured PMM briefs.
4. **Delegate phase** -- Spawn specialists via `Task <agent>(context)`. Parallel dispatch for independent analyses (brand + SEO + content + community). Sequential for dependent work (strategy before copywriting).
5. **Review phase** -- Validate brand voice consistency. Check SEO compliance. Verify content quality.
6. **Brand workshop routing** -- When brand-specific work is requested, delegate to brand-architect for the full workshop. CMO handles brand keywords but routes to the specialist.
7. **Sharp edges** (absorbed from marketing-strategist):
   - Always start with positioning audit
   - Launch strategy requires three phases (pre-launch, launch, post-launch)
   - Name specific cognitive biases
   - PMM brief with required sections
   - Check brand-guide.md, read Voice + Identity if present
   - Output: structured tables, matrices, prioritized lists

**Tasks:**

- [ ] Create `plugins/soleur/agents/marketing/cmo.md`
- [ ] Delete `plugins/soleur/agents/marketing/marketing-strategist.md`
- [ ] Update disambiguation sentences in sibling marketing agents that reference marketing-strategist (conversion-optimizer, retention-strategist)

**Files:**

- Create: `plugins/soleur/agents/marketing/cmo.md`
- Delete: `plugins/soleur/agents/marketing/marketing-strategist.md`
- Modify: `plugins/soleur/agents/marketing/conversion-optimizer.md` (disambiguation)
- Modify: `plugins/soleur/agents/marketing/retention-strategist.md` (disambiguation)

#### Phase 2: CTO Agent (Lightweight)

**Deliverable:** `plugins/soleur/agents/engineering/cto.md`

Create a lightweight CTO agent focused on brainstorm participation. The CTO adds engineering-specific questions during brainstorm domain detection (e.g., flagging technical risks, architecture concerns, scalability implications). It does NOT wrap or duplicate existing review/work command orchestration -- those commands remain the engineering coordinators.

The CTO sits at the engineering root level (`agents/engineering/cto.md`) because it orchestrates across all engineering subdirectories. This is intentional -- it is the first file at the engineering root, mirroring how the CMO sits at the marketing root.

**Frontmatter:**

```yaml
---
name: cto
description: "Participates in brainstorm and planning phases to assess technical implications, flag architecture concerns, and identify engineering risks for proposed features. Use individual engineering agents (review, research, design) for focused tasks; use this agent for cross-cutting technical assessment during feature exploration."
model: inherit
---
```

**Body sections:**

1. **Role** -- Engineering domain leader for brainstorm participation. Assess technical implications of proposed features. Do NOT duplicate review or work command orchestration.
2. **Assess phase** -- Identify technical risks, architecture impacts, and affected components. Check for existing patterns in the codebase.
3. **Recommend phase** -- Suggest technical approach, flag security implications, estimate complexity.
4. **Sharp edges:**
   - Read CLAUDE.md conventions before making recommendations
   - Check for existing patterns before suggesting new ones (constitution: "Before designing new infrastructure, check if the existing codebase already has a pattern")
   - Output: structured assessment with risk ratings, not prose

**Tasks:**

- [ ] Create `plugins/soleur/agents/engineering/cto.md`

**Files:**

- Create: `plugins/soleur/agents/engineering/cto.md`

#### Phase 3: `/soleur:marketing` Skill

**Deliverable:** `plugins/soleur/skills/marketing/SKILL.md`

Create a standalone marketing entry point that delegates to the CMO agent.

**Sub-commands:**

| Sub-command | Description | CMO Phase |
|-------------|-------------|-----------|
| `audit` | Assess marketing posture across all domains (brand, SEO, content, community) | Assess + Delegate (parallel fan-out) |
| `strategy` | Create unified marketing strategy with prioritized initiatives | Assess + Recommend |
| `launch <feature>` | Plan marketing activities for a feature launch | Full cycle (assess, recommend, delegate, review) |

**Frontmatter:**

```yaml
---
name: marketing
description: "This skill should be used when performing cross-domain marketing assessment, unified marketing strategy creation, or marketing launch planning. It delegates to the CMO agent for orchestration of brand, SEO, content, community, and CRO specialists."
---
```

**Pattern:** Follows the growth skill's dispatch model -- parse sub-command, check prerequisites (brand guide), delegate to CMO agent via Task tool.

**Relationship to existing skills:** `/soleur:marketing audit` is a superset. It runs the CMO which delegates to growth-strategist, seo-aeo-analyst, community-manager, and brand-architect in parallel, then synthesizes a unified report. The individual skills (`/soleur:growth`, `/soleur:seo-aeo`, `/soleur:community`) remain usable standalone for focused work.

**Tasks:**

- [ ] Create `plugins/soleur/skills/marketing/SKILL.md`
- [ ] Register in `docs/_data/skills.js` SKILL_CATEGORIES under "Content & Release" category

**Files:**

- Create: `plugins/soleur/skills/marketing/SKILL.md`
- Modify: `plugins/soleur/docs/_data/skills.js`

#### Phase 4: Brainstorm Domain Detection (LLM-Based)

**Deliverable:** Rewritten Phase 0.5 in `plugins/soleur/commands/soleur/brainstorm.md`

Replace keyword-based domain routing with LLM semantic assessment. Instead of scanning for keyword substrings, instruct Claude to assess whether the feature description has implications for specific domains.

**Why LLM over keywords:** The brainstorm command runs inside Claude. Keyword matching was instructing Claude to do substring matching -- a task LLMs are worse at than semantic understanding. LLM assessment is more accurate (no "brand new feature" false positives), requires no keyword list, and is more extensible (adding a domain = adding one assessment question).

**Detection mechanism:**

Replace the existing Phase 0.5 keyword scanning with domain assessment instructions:

```
Assess the feature description for domain relevance:

1. **Marketing implications** -- Does this feature involve content changes,
   audience targeting, brand impact, go-to-market activities, SEO/AEO concerns,
   pricing communication, or public-facing messaging?

2. **Engineering architecture implications** -- Does this feature require
   significant architectural decisions, infrastructure changes, system design,
   or technical debt resolution beyond normal implementation?

If brand-specific work is detected (brand identity definition, brand guide
creation, voice and tone development), treat it as a special case within marketing.
```

**Routing flow:**

1. Claude assesses feature description against domain questions
2. If no domains relevant: continue standard brainstorm (unchanged)
3. If marketing relevant:
   - If brand-specific: offer via AskUserQuestion:
     - "Start brand workshop" (preserves existing brand-architect bypass)
     - "Include marketing perspective" (CMO joins brainstorm)
     - "Brainstorm normally" (decline)
   - If general marketing: offer:
     - "Include marketing perspective" (CMO joins brainstorm)
     - "Brainstorm normally" (decline)
4. If engineering relevant: offer:
   - "Include technical assessment" (CTO joins brainstorm)
   - "Brainstorm normally" (decline)
5. If both relevant: ask about each domain separately
6. If brand workshop selected: hand off to brand-architect (existing behavior, unchanged)
7. If marketing/engineering accepted: leader(s) participate in Phase 1.2

**Extensibility:** Adding a future domain (e.g., Legal) means adding one assessment question. No keyword tables, no command rewrites needed.

**Backward compatibility:** Brand workshop is preserved when brand-specific work is detected. Existing brand workshop users see no change.

**Tasks:**

- [ ] Rewrite brainstorm.md Phase 0.5 with LLM-based domain assessment
- [ ] Preserve brand workshop bypass for brand-specific detections
- [ ] Add marketing domain routing (CMO joins brainstorm)
- [ ] Add engineering domain routing (CTO joins brainstorm)
- [ ] Update extension comment for future domains

**Files:**

- Modify: `plugins/soleur/commands/soleur/brainstorm.md`

#### Phase 5: Documentation and Versioning

**Deliverable:** Updated README, CHANGELOG, plugin.json, docs data files, AGENTS.md

**Tasks:**

- [ ] Add Domain Leader Interface section to `plugins/soleur/AGENTS.md`
- [ ] Update agent counts: 44 -> 45 (remove marketing-strategist, add cmo + cto)
- [ ] Update skill count: 44 -> 45 (add marketing)
- [ ] Update `plugins/soleur/README.md` tables and counts
- [ ] Update `plugins/soleur/.claude-plugin/plugin.json` version (MINOR bump) and description
- [ ] Update `plugins/soleur/CHANGELOG.md`
- [ ] Update root `README.md` version badge
- [ ] Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- [ ] Update `plugins/soleur/NOTICE` (references marketing-strategist -- update to cmo)
- [ ] Update `docs/_data/agents.js` if domain labels need updating
- [ ] Update `plugins/soleur/.claude-plugin/plugin.json` description string to "45 agents...45 skills"
- [ ] Verify token budget: `grep -h 'description:' agents/**/*.md | wc -w` < 2500

**Version bump:** MINOR (new agents + new skill). Exact version determined at bump time from main's current version.

**Files:**

- Modify: `plugins/soleur/AGENTS.md`
- Modify: `plugins/soleur/README.md`
- Modify: `plugins/soleur/.claude-plugin/plugin.json`
- Modify: `plugins/soleur/CHANGELOG.md`
- Modify: `plugins/soleur/NOTICE`
- Modify: `README.md` (root)
- Modify: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Modify: `plugins/soleur/docs/_data/agents.js` (if needed)
- Modify: `plugins/soleur/docs/_data/skills.js`

## Alternative Approaches Considered

1. **Generic meta-agent** -- One parameterized domain leader. Rejected: premature abstraction for 2 domains, weaker prompts.
2. **CMO first, extract later** -- Build CMO alone. Rejected: risks divergence when CTO is added.
3. **Keyword-based detection** -- Scan feature descriptions for domain-specific keywords. Rejected: LLM semantic assessment is more accurate, avoids false positives ("brand new feature"), and requires no keyword list maintenance. The brainstorm command already runs inside Claude -- leveraging its semantic understanding is natural.
4. **Frontmatter metadata registry** -- Agents declare `role: domain-leader` in frontmatter, brainstorm discovers them dynamically. Rejected for v1: over-engineering for 2 domains. Can be added in v2 when 4+ domains exist.
5. **All 5 command hooks** -- Add domain detection to all workflow commands. Rejected for this iteration: 5x scope. Brainstorm is the entry point; other commands get hooks in follow-up issues.

## Acceptance Criteria

### Functional Requirements

- [ ] CMO agent exists and can assess marketing posture, recommend strategy, delegate to specialists, and review output
- [ ] marketing-strategist agent is removed; all its sharp edges are preserved in CMO
- [ ] CTO agent exists and can assess technical implications of features
- [ ] `/soleur:marketing audit` fans out to growth-strategist, seo-aeo-analyst, community-manager, brand-architect and synthesizes results
- [ ] `/soleur:marketing strategy` produces unified marketing strategy
- [ ] `/soleur:marketing launch <feature>` creates marketing launch plan
- [ ] Brainstorm domain detection identifies marketing-relevant features via LLM assessment
- [ ] Brainstorm domain detection identifies engineering-relevant features via LLM assessment
- [ ] Brand workshop bypass is preserved when brand-specific work is detected
- [ ] User can decline domain leader participation and continue standard brainstorm
- [ ] Existing marketing skills (`growth`, `seo-aeo`, `community`) continue working standalone

### Non-Functional Requirements

- [ ] Agent description token budget stays under 2500 words
- [ ] CMO description is 1-3 sentences with disambiguation
- [ ] CTO description is 1-3 sentences with disambiguation
- [ ] No `<example>` blocks in agent descriptions

### Deferred Spec Requirements (NOT in this PR)

The spec (knowledge-base/specs/feat-domain-leaders/spec.md) lists FR5-FR8 and FR10 which are follow-up work:

- FR5: Domain detection in plan command (follow-up issue)
- FR6: Domain detection in work command (follow-up issue)
- FR7: Domain detection in review command (follow-up issue)
- FR8: Domain detection in ship command (follow-up issue)
- FR10: Agent Teams integration (follow-up issue)

### Quality Gates

- [ ] All disambiguation sentences reference correct sibling agents
- [ ] `bun test` passes
- [ ] Markdownlint passes
- [ ] Version triad updated (plugin.json + CHANGELOG + README)

## Test Scenarios

### Acceptance Tests

- Given a brainstorm request "plan a product launch campaign", when domain detection runs, then LLM assesses marketing relevance and CMO is offered
- Given a brainstorm request "refactor the authentication module", when domain detection runs, then LLM assesses engineering relevance and CTO is offered
- Given a brainstorm request "add a pricing tier with landing page", when domain detection runs, then both marketing AND engineering are assessed as relevant
- Given domain detection offers CMO and the user declines, when brainstorm continues, then standard flow runs with no CMO involvement
- Given brand keywords "define our brand identity", when domain detection offers CMO, then the user sees both "Start brand workshop" and "Include marketing perspective" options
- Given the user selects "Start brand workshop", when the CMO routes to brand-architect, then the brand workshop runs identically to the pre-CMO behavior
- Given `/soleur:marketing audit` runs, when the CMO delegates, then growth-strategist, seo-aeo-analyst, community-manager, and brand-architect run in parallel
- Given `/soleur:marketing strategy` runs, when the CMO assesses and recommends, then a structured marketing strategy with prioritized initiatives is produced
- Given a user invokes `Task growth-strategist(...)` directly, when the request completes, then it works identically to before (no CMO gating)
- Given marketing-strategist is removed, when the plugin loads, then no errors occur and cmo is discoverable as `soleur:marketing:cmo`

### Edge Cases

- Given no brand-guide.md exists, when CMO runs audit, then it warns about missing brand guide and continues with available data
- Given brainstorm text contains "brand" in a non-marketing context (e.g., "brand new feature"), when LLM detection runs, then Claude correctly identifies no marketing relevance (LLM advantage over keyword matching)
- Given all 45 agent descriptions are loaded, when cumulative word count is checked, then total stays under 2500 words
- Given both marketing and engineering keywords match, when the user declines both, then standard brainstorm continues with no leader involvement
- Given `/soleur:marketing` is invoked with no sub-command, then a help table of available sub-commands is displayed
- Given `/soleur:marketing audit` runs without brand-guide.md, then the skill warns about missing prerequisites but continues
- Given a user invokes `Task marketing-strategist(...)` after removal, then the task fails with agent-not-found (default Claude Code behavior -- no custom migration path)

## Dependencies and Prerequisites

- Brainstorm command's Phase 0.5 extension point (exists: line 61 comment)
- Growth skill dispatch pattern (exists: growth/SKILL.md)
- Review command's parallel fan-out pattern (exists: review.md)
- Marketing-strategist sharp edges (exists: to be absorbed)

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Token budget exceeded | Low | High | Pre-calculated: net +1 agent = ~40 words. Current 2264 + 40 = 2304, under 2500 |
| Brand workshop regression | Medium | High | Explicit brand-specific routing preserves workshop bypass |
| LLM detection misjudgment | Low | Low | User always confirms; declining continues standard flow. LLM semantic assessment has fewer false positives than keyword matching |
| Marketing-strategist references in user memory | Low | Medium | Hard cutover; no deprecation mechanism exists in plugin system |

## Future Considerations

- **v2: Frontmatter discovery** -- When 4+ domain leaders exist, consider dynamic discovery via `role: domain-leader` frontmatter instead of manual assessment questions
- **v2: Plan/work/review/ship hooks** -- Add domain detection to remaining workflow commands
- **v2: Agent Teams per domain** -- CMO manages a persistent marketing Agent Team
- **v2: Leader-to-leader communication** -- Cross-domain coordination protocol
- Follow-up issues: #181 (CLO), #182 (COO), #183 (CPO)

## References

### Internal References

- Brainstorm routing: `plugins/soleur/commands/soleur/brainstorm.md:57-127`
- Review fan-out pattern: `plugins/soleur/commands/soleur/review.md:66-79`
- Work Agent Teams: `plugins/soleur/commands/soleur/work.md:146-240`
- Growth skill dispatch: `plugins/soleur/skills/growth/SKILL.md:39-48`
- Marketing-strategist: `plugins/soleur/agents/marketing/marketing-strategist.md`
- Agent token budget learning: `knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`
- Brainstorm routing learning: `knowledge-base/learnings/2026-02-13-brainstorm-domain-routing-pattern.md`
- Fan-out learning: `knowledge-base/learnings/2026-02-09-parallel-subagent-fan-out-in-work-command.md`

### Related Work

- Issue: #154
- Brainstorm: `knowledge-base/brainstorms/2026-02-20-domain-leaders-brainstorm.md`
- Spec: `knowledge-base/specs/feat-domain-leaders/spec.md`
- Follow-ups: #181, #182, #183
