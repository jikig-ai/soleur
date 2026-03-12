---
title: Restructure knowledge-base by domain taxonomy
type: refactor
date: 2026-03-12
updated: 2026-03-12
---

# Restructure knowledge-base by Domain Taxonomy

[Updated 2026-03-12] Simplified after plan review — cut `features/` grouping (#568) and `overview/` → `project/` rename (#569) to separate PRs.

## Overview

Move domain-specific content from `knowledge-base/overview/` and scattered directories into canonical domain folders. ~12 git mv operations, ~37 file updates.

## Non-Goals

- Moving specs/, plans/, brainstorms/, learnings/ (tracked in #568)
- Renaming overview/ to project/ (tracked in #569)
- Updating archived file contents (prose, not executable)
- Creating empty domain dirs with .gitkeep (create on demand)

## Problem Statement

`knowledge-base/overview/` conflates project infrastructure (constitution, components) with domain strategy docs (brand-guide, pricing, competitive-intelligence). Domain leaders read/write to scattered locations. Navigation is unclear — finding a marketing doc requires knowing it's in `overview/` or `audits/`.

## Proposed Solution

Move domain content into canonical department folders in a single atomic commit. `overview/` stays but loses its domain docs. specs/, plans/, brainstorms/, learnings/ stay at root.

## Technical Approach

### Pre-move fix

| Action | Source | Destination | Reason |
|--------|--------|-------------|--------|
| Rename | `knowledge-base/marketing/content-strategy.md` | `knowledge-base/marketing/case-study-distribution-plan.md` | Name collision — this is a distribution plan, not the content strategy |

### Move Manifest

| Source | Destination |
|--------|-------------|
| `knowledge-base/overview/brand-guide.md` | `knowledge-base/marketing/brand-guide.md` |
| `knowledge-base/overview/content-strategy.md` | `knowledge-base/marketing/content-strategy.md` |
| `knowledge-base/overview/marketing-strategy.md` | `knowledge-base/marketing/marketing-strategy.md` |
| `knowledge-base/audits/soleur-ai/` | `knowledge-base/marketing/audits/soleur-ai/` |
| `knowledge-base/overview/business-validation.md` | `knowledge-base/product/business-validation.md` |
| `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` |
| `knowledge-base/overview/pricing-strategy.md` | `knowledge-base/product/pricing-strategy.md` |
| `knowledge-base/design/` | `knowledge-base/product/design/` |
| `knowledge-base/ops/expenses.md` | `knowledge-base/operations/expenses.md` |
| `knowledge-base/ops/domains.md` | `knowledge-base/operations/domains.md` |
| `knowledge-base/community/` | `knowledge-base/support/community/` |
| `knowledge-base/audits/2026-03-05-pr438-security-audit.md` | `knowledge-base/engineering/audits/2026-03-05-pr438-security-audit.md` |

### Unchanged directories

- `knowledge-base/overview/` — stays with constitution.md, README.md, components/
- `knowledge-base/specs/` — stays at root (deferred to #568)
- `knowledge-base/plans/` — stays at root (deferred to #568)
- `knowledge-base/brainstorms/` — stays at root (deferred to #568)
- `knowledge-base/learnings/` — stays at root (deferred to #568)
- `knowledge-base/sales/` — already conforms to domain taxonomy

### Implementation Steps

#### Step 1: Prep

```bash
# Rename conflicting file
git mv knowledge-base/marketing/content-strategy.md knowledge-base/marketing/case-study-distribution-plan.md

# Create target directories
mkdir -p knowledge-base/{product,operations,support,engineering/audits,marketing/audits}
```

#### Step 2: Execute git mv

```bash
# Strategy docs from overview/ to domain folders
git mv knowledge-base/overview/brand-guide.md knowledge-base/marketing/
git mv knowledge-base/overview/content-strategy.md knowledge-base/marketing/
git mv knowledge-base/overview/marketing-strategy.md knowledge-base/marketing/
git mv knowledge-base/overview/business-validation.md knowledge-base/product/
git mv knowledge-base/overview/competitive-intelligence.md knowledge-base/product/
git mv knowledge-base/overview/pricing-strategy.md knowledge-base/product/

# Directory moves
git mv knowledge-base/audits/soleur-ai knowledge-base/marketing/audits/
git mv knowledge-base/audits/2026-03-05-pr438-security-audit.md knowledge-base/engineering/audits/
git mv knowledge-base/design knowledge-base/product/
git mv knowledge-base/ops/expenses.md knowledge-base/operations/
git mv knowledge-base/ops/domains.md knowledge-base/operations/
git mv knowledge-base/community knowledge-base/support/
```

#### Step 3: Update path references

All old→new replacements across plugins/, scripts/, .github/:

| Old Pattern | New Pattern | Files |
|-------------|------------|-------|
| `knowledge-base/overview/brand-guide.md` | `knowledge-base/marketing/brand-guide.md` | ~15 agents, ~10 skills, 1 workflow |
| `knowledge-base/overview/business-validation.md` | `knowledge-base/product/business-validation.md` | 3 agents, 2 skills |
| `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` | 1 agent, 1 skill, 1 workflow |
| `knowledge-base/overview/content-strategy.md` | `knowledge-base/marketing/content-strategy.md` | 1 agent |
| `knowledge-base/overview/pricing-strategy.md` | `knowledge-base/product/pricing-strategy.md` | 1 agent |
| `knowledge-base/ops/` | `knowledge-base/operations/` | 5 agents |
| `knowledge-base/community/` | `knowledge-base/support/community/` | 2 agents, 1 skill, 1 workflow |
| `knowledge-base/design/` | `knowledge-base/product/design/` | 1 agent |

**Specific files to update:**

Agents:
- `plugins/soleur/agents/marketing/brand-architect.md` — brand-guide
- `plugins/soleur/agents/marketing/{cmo,growth-strategist,programmatic-seo-specialist,paid-media-strategist,pricing-strategist,analytics-analyst,conversion-optimizer,copywriter,retention-strategist}.md` — brand-guide
- `plugins/soleur/agents/product/{business-validator,competitive-intelligence,cpo}.md` — business-validation, competitive-intelligence, brand-guide
- `plugins/soleur/agents/product/design/ux-design-lead.md` — brand-guide, design/
- `plugins/soleur/agents/operations/{ops-advisor,ops-research,ops-provisioner,coo}.md` — ops/
- `plugins/soleur/agents/finance/cfo.md` — ops/, brand-guide
- `plugins/soleur/agents/sales/cro.md` — brand-guide
- `plugins/soleur/agents/support/{community-manager,cco}.md` — community/, brand-guide

Skills:
- `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` — brand-guide
- `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` — business-validation
- `plugins/soleur/skills/competitive-analysis/SKILL.md` — competitive-intelligence
- `plugins/soleur/skills/community/SKILL.md` — brand-guide, community/
- `plugins/soleur/skills/{discord-content,content-writer,social-distribute,growth,release-docs,ship}/SKILL.md` — brand-guide

Workflows:
- `.github/workflows/scheduled-competitive-analysis.yml` — competitive-intelligence
- `.github/workflows/scheduled-community-monitor.yml` — community/, brand-guide

Scripts:
- `scripts/content-publisher.sh` — already correct (`knowledge-base/marketing/distribution-content`), verify only

Todos (informational, not runtime):
- `todos/013-complete-p1-star-count-inconsistency.md` — business-validation
- `todos/016-complete-p2-stale-polsia-business-validation.md` — business-validation

#### Step 4: Verify

```bash
# Must all return zero results
grep -r 'knowledge-base/overview/brand-guide' plugins/ scripts/ .github/ AGENTS.md todos/
grep -r 'knowledge-base/overview/business-validation' plugins/ scripts/ .github/ todos/
grep -r 'knowledge-base/overview/competitive-intelligence' plugins/ scripts/ .github/
grep -r 'knowledge-base/overview/content-strategy' plugins/ scripts/ .github/
grep -r 'knowledge-base/overview/pricing-strategy' plugins/ scripts/ .github/
grep -r 'knowledge-base/overview/marketing-strategy' plugins/ scripts/ .github/
grep -r 'knowledge-base/ops/' plugins/ scripts/ .github/
grep -r 'knowledge-base/community/' plugins/ scripts/ .github/
grep -r 'knowledge-base/design/' plugins/ scripts/ .github/
grep -r 'knowledge-base/audits/' plugins/ scripts/ .github/
```

## Acceptance Criteria

- [ ] Domain content moved to canonical domain folders (marketing, product, operations, support, engineering)
- [ ] `overview/` retains only project-level docs (constitution, README, components)
- [ ] All hardcoded path references updated (grep verification returns zero stale refs)
- [ ] CI workflows reference new paths
- [ ] Security audit lives under `engineering/`, not `marketing/`
- [ ] `sales/` unchanged

## Test Scenarios

- Given `scheduled-competitive-analysis.yml` runs, when the agent writes, then the report lands at `knowledge-base/product/competitive-intelligence.md`
- Given `scheduled-community-monitor.yml` runs, when the agent writes, then the digest lands at `knowledge-base/support/community/`
- Given a brand workshop runs, when brand-architect writes, then the guide lands at `knowledge-base/marketing/brand-guide.md`
- Given ops-advisor runs, when it reads expenses, then it reads from `knowledge-base/operations/expenses.md`

## Rollback Plan

`git revert HEAD` on main cleanly undoes all `git mv` operations and reference updates.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-12-kb-domain-structure-brainstorm.md`
- Spec: `knowledge-base/specs/feat-kb-domain-structure/spec.md`
- Issue: #567
- Deferred: #568 (features/ grouping), #569 (overview/ rename)
