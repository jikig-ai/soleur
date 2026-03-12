---
title: Restructure knowledge-base by domain taxonomy
type: refactor
date: 2026-03-12
---

# Restructure knowledge-base by Domain Taxonomy

## Overview

Reorganize `knowledge-base/` to align with Soleur's canonical 8-department taxonomy. Domain-specific content moves into domain folders, shared feature artifacts group under `features/`, and `overview/` becomes `project/`. ~60 files outside knowledge-base/ contain ~200+ hardcoded path references that must update atomically.

## Problem Statement

`knowledge-base/overview/` conflates project infrastructure (constitution, components) with domain strategy docs (brand-guide, pricing, competitive-intelligence). Domain leaders read/write to scattered locations. Navigation is unclear — finding a marketing doc requires knowing it's in `overview/` or `audits/`.

## Proposed Solution

Three structural changes in a single atomic commit:

1. **Domain directories** — move domain content into 8 canonical department folders
2. **Features grouping** — move specs/, plans/, brainstorms/, learnings/ under `features/`
3. **Project directory** — rename `overview/` to `project/` (project-level docs only)

## Technical Approach

### Complete Move Manifest

#### Pre-move fixes (resolve conflicts first)

| Action | Source | Destination | Reason |
|--------|--------|-------------|--------|
| Rename | `knowledge-base/marketing/content-strategy.md` | `knowledge-base/marketing/case-study-distribution-plan.md` | Name collision — this is a distribution plan, not the content strategy |

#### Domain moves

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

#### Project rename (overview/ → project/)

| Source | Destination |
|--------|-------------|
| `knowledge-base/overview/constitution.md` | `knowledge-base/project/constitution.md` |
| `knowledge-base/overview/README.md` | `knowledge-base/project/README.md` |
| `knowledge-base/overview/components/` | `knowledge-base/project/components/` |

#### Features grouping

| Source | Destination |
|--------|-------------|
| `knowledge-base/specs/` | `knowledge-base/features/specs/` |
| `knowledge-base/plans/` | `knowledge-base/features/plans/` |
| `knowledge-base/brainstorms/` | `knowledge-base/features/brainstorms/` |
| `knowledge-base/learnings/` | `knowledge-base/features/learnings/` |

#### Empty domain dirs (with .gitkeep)

- `knowledge-base/finance/.gitkeep`
- `knowledge-base/legal/.gitkeep`

(engineering/ and support/ get content from moves; marketing/, product/, operations/, sales/ already exist or get content)

### Implementation Phases

#### Phase 1: Pre-move conflict resolution

1. Rename `knowledge-base/marketing/content-strategy.md` → `knowledge-base/marketing/case-study-distribution-plan.md`
2. Create target directories: `mkdir -p knowledge-base/{project,features,product,operations,support,engineering/audits,marketing/audits,finance,legal}`

#### Phase 2: Execute git mv operations

Order matters — move files before directories to avoid conflicts:

```bash
# 1. Individual files from overview/ to domain folders
git mv knowledge-base/overview/brand-guide.md knowledge-base/marketing/
git mv knowledge-base/overview/content-strategy.md knowledge-base/marketing/
git mv knowledge-base/overview/marketing-strategy.md knowledge-base/marketing/
git mv knowledge-base/overview/business-validation.md knowledge-base/product/
git mv knowledge-base/overview/competitive-intelligence.md knowledge-base/product/
git mv knowledge-base/overview/pricing-strategy.md knowledge-base/product/

# 2. overview/ project-level files → project/
git mv knowledge-base/overview/constitution.md knowledge-base/project/
git mv knowledge-base/overview/README.md knowledge-base/project/
git mv knowledge-base/overview/components knowledge-base/project/

# 3. Directory moves
git mv knowledge-base/audits/soleur-ai knowledge-base/marketing/audits/
git mv knowledge-base/audits/2026-03-05-pr438-security-audit.md knowledge-base/engineering/audits/
git mv knowledge-base/design knowledge-base/product/
git mv knowledge-base/ops/expenses.md knowledge-base/operations/
git mv knowledge-base/ops/domains.md knowledge-base/operations/
git mv knowledge-base/community knowledge-base/support/

# 4. Features grouping
git mv knowledge-base/specs knowledge-base/features/
git mv knowledge-base/plans knowledge-base/features/
git mv knowledge-base/brainstorms knowledge-base/features/
git mv knowledge-base/learnings knowledge-base/features/

# 5. Cleanup empty dirs (git doesn't track them, but remove if still present)
# 6. Create .gitkeep for empty domain dirs
touch knowledge-base/finance/.gitkeep
touch knowledge-base/legal/.gitkeep
```

#### Phase 3: Update path references (Tier 1 — executable code)

These cause runtime failures if missed:

| File | Old Pattern | New Pattern |
|------|------------|-------------|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | `knowledge-base/specs/` | `knowledge-base/features/specs/` |
| `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` | `knowledge-base/{brainstorms,plans,specs}/` | `knowledge-base/features/{brainstorms,plans,specs}/` |
| `scripts/generate-article-30-register.sh` | `knowledge-base/specs/archive/` | `knowledge-base/features/specs/archive/` |
| `scripts/content-publisher.sh` | (verify — may already be correct at `knowledge-base/marketing/`) | no change if already correct |
| `.github/workflows/scheduled-competitive-analysis.yml` | `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` |
| `.github/workflows/scheduled-community-monitor.yml` | `knowledge-base/community/`, `knowledge-base/overview/brand-guide.md` | `knowledge-base/support/community/`, `knowledge-base/marketing/brand-guide.md` |

#### Phase 4: Update path references (Tier 2 — agent instructions)

~25 agent files. Use `replace_all` for common patterns:

| Old Pattern | New Pattern | Files Affected |
|-------------|------------|----------------|
| `knowledge-base/overview/brand-guide.md` | `knowledge-base/marketing/brand-guide.md` | ~15 agents (brand-architect, all marketing agents, cpo, cfo, cro, community-manager, ux-design-lead, ops-provisioner) |
| `knowledge-base/overview/business-validation.md` | `knowledge-base/product/business-validation.md` | business-validator, cpo, competitive-intelligence |
| `knowledge-base/overview/competitive-intelligence.md` | `knowledge-base/product/competitive-intelligence.md` | competitive-intelligence |
| `knowledge-base/overview/content-strategy.md` | `knowledge-base/marketing/content-strategy.md` | competitive-intelligence |
| `knowledge-base/overview/pricing-strategy.md` | `knowledge-base/product/pricing-strategy.md` | competitive-intelligence |
| `knowledge-base/ops/` | `knowledge-base/operations/` | ops-advisor, ops-research, ops-provisioner, coo, cfo |
| `knowledge-base/community/` | `knowledge-base/support/community/` | community-manager, cco |
| `knowledge-base/design/` | `knowledge-base/product/design/` | ux-design-lead |
| `knowledge-base/learnings/` | `knowledge-base/features/learnings/` | learnings-researcher (13 category paths), infra-security |

#### Phase 5: Update path references (Tier 3 — skill instructions)

~20 skill files. Biggest changes:

| File | Scope |
|------|-------|
| `plugins/soleur/skills/compound/SKILL.md` | constitution, learnings, specs, brainstorms, plans |
| `plugins/soleur/skills/compound-capture/SKILL.md` | learnings (30+ refs), constitution, components, README |
| `plugins/soleur/skills/compound-capture/references/yaml-schema.md` | 13 category-to-directory learnings paths |
| `plugins/soleur/skills/compound-capture/assets/resolution-template.md` | learnings cross-ref |
| `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md` | learnings paths |
| `plugins/soleur/skills/plan/SKILL.md` | constitution, specs, plans, brainstorms, learnings |
| `plugins/soleur/skills/brainstorm/SKILL.md` | brainstorms, specs, learnings |
| `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` | brand-guide |
| `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` | business-validation |
| `plugins/soleur/skills/work/SKILL.md` | constitution, specs |
| `plugins/soleur/skills/work/references/work-lifecycle-parallel.md` | specs |
| `plugins/soleur/skills/ship/SKILL.md` | brainstorms, plans, specs, learnings, brand-guide |
| `plugins/soleur/skills/archive-kb/SKILL.md` | brainstorms, plans, specs |
| `plugins/soleur/skills/merge-pr/SKILL.md` | brainstorms, plans, specs |
| `plugins/soleur/skills/one-shot/SKILL.md` | specs |
| `plugins/soleur/skills/spec-templates/SKILL.md` | specs, components |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | plans, learnings |
| `plugins/soleur/skills/competitive-analysis/SKILL.md` | competitive-intelligence |
| `plugins/soleur/skills/discord-content/SKILL.md` | brand-guide |
| `plugins/soleur/skills/content-writer/SKILL.md` | brand-guide |
| `plugins/soleur/skills/social-distribute/SKILL.md` | brand-guide |
| `plugins/soleur/skills/growth/SKILL.md` | brand-guide |
| `plugins/soleur/skills/community/SKILL.md` | brand-guide, community |
| `plugins/soleur/skills/release-docs/SKILL.md` | brand-guide |
| `plugins/soleur/skills/brainstorm-techniques/SKILL.md` | brainstorms |

#### Phase 6: Update path references (Tier 4 — commands and AGENTS.md)

| File | Old Pattern | New Pattern |
|------|------------|-------------|
| `AGENTS.md` | `knowledge-base/overview/constitution.md` | `knowledge-base/project/constitution.md` |
| `plugins/soleur/commands/sync.md` | `knowledge-base/{learnings,brainstorms,specs,plans,overview/components}` | `knowledge-base/features/{learnings,brainstorms,specs,plans}`, `knowledge-base/project/components` |

#### Phase 7: Update internal knowledge-base cross-references

Files within knowledge-base/ that reference other knowledge-base/ files by path (e.g., brand-guide referencing constitution). Grep for old paths within the new knowledge-base/ structure and update.

Skip archived files (`features/specs/archive/`, `features/plans/archive/`, `features/brainstorms/archive/`) — these are historical and updating them adds risk with no functional benefit.

#### Phase 8: Update documentation

- Update `knowledge-base/project/components/knowledge-base.md` directory tree diagram
- Update `knowledge-base/project/README.md` directory structure
- Verify README.md component counts still accurate

#### Phase 9: Verification

```bash
# Must all return zero results
grep -r 'knowledge-base/overview/' plugins/ scripts/ .github/ AGENTS.md
grep -r 'knowledge-base/ops/' plugins/ scripts/ .github/
grep -r 'knowledge-base/community/' plugins/ scripts/ .github/
grep -r 'knowledge-base/design/' plugins/ scripts/ .github/
grep -r 'knowledge-base/audits/' plugins/ scripts/ .github/
grep -rP 'knowledge-base/(specs|plans|brainstorms|learnings)/' plugins/ scripts/ .github/ --include='*.md' --include='*.yml' --include='*.sh' | grep -v 'knowledge-base/features/'
```

## Acceptance Criteria

- [ ] All 8 canonical domain directories exist under knowledge-base/
- [ ] `overview/` no longer exists — renamed to `project/`
- [ ] specs, plans, brainstorms, learnings under `features/`
- [ ] All hardcoded path references updated (grep verification returns zero stale refs)
- [ ] `worktree-manager.sh` creates spec dirs under `features/specs/`
- [ ] `archive-kb.sh` discovers artifacts under `features/`
- [ ] CI workflows (`scheduled-competitive-analysis`, `scheduled-community-monitor`) reference new paths
- [ ] `sync.md` bootstraps new directory structure
- [ ] Security audit lives under `engineering/`, not `marketing/`

## Test Scenarios

- Given a new worktree `feat-test`, when `worktree-manager.sh feature test` runs, then spec dir is created at `knowledge-base/features/specs/feat-test/`
- Given artifacts exist for a merged branch, when `cleanup-merged` runs, then artifacts are archived from `knowledge-base/features/` paths
- Given `scheduled-competitive-analysis.yml` runs, when the agent writes, then the report lands at `knowledge-base/product/competitive-intelligence.md`
- Given a brand workshop runs, when brand-architect writes, then the guide lands at `knowledge-base/marketing/brand-guide.md`

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Silent archiving breakage (92 artifacts missed in prior restructure) | Verify archive-kb.sh and compound-capture paths work before committing |
| CI workflow silent failure | Update workflow paths before merge; monitor first scheduled run after merge |
| Open PRs/worktrees have stale paths | This branch's brainstorm/spec/plan are already written to old paths — they'll be part of the migration itself |
| Grep misses a reference | Post-move verification (Phase 9) catches stale refs; `git revert HEAD` is clean rollback |

## Rollback Plan

If CI workflows fail after merge: `git revert HEAD` on main and push. This cleanly undoes all `git mv` operations and reference updates in a single revert commit.

## Dependencies

- Resolve `content-strategy.md` name collision before any moves
- No other active PRs should be modifying knowledge-base/ structure simultaneously

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-12-kb-domain-structure-brainstorm.md`
- Spec: `knowledge-base/specs/feat-kb-domain-structure/spec.md`
- Issue: #567
- Prior migration learning: `knowledge-base/learnings/2026-02-06-docs-consolidation-migration.md`
- Archiving breakage learning: `knowledge-base/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`
- Overview staleness learning: `knowledge-base/learnings/technical-debt/2026-02-12-overview-docs-stale-after-restructure.md`
