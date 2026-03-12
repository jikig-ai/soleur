# Tasks: Knowledge-Base Domain Structure

## Phase 1: Pre-move conflict resolution

- [ ] 1.1 Rename `knowledge-base/marketing/content-strategy.md` → `case-study-distribution-plan.md`
- [ ] 1.2 Create target directories: project, features, product, operations, support, engineering/audits, marketing/audits, finance, legal

## Phase 2: Execute git mv operations

- [ ] 2.1 Move individual files from overview/ to domain folders (brand-guide, content-strategy, marketing-strategy → marketing; business-validation, competitive-intelligence, pricing-strategy → product)
- [ ] 2.2 Move overview/ project files to project/ (constitution.md, README.md, components/)
- [ ] 2.3 Move directory-level content (audits/soleur-ai → marketing/audits, security audit → engineering/audits, design → product/design, ops → operations, community → support/community)
- [ ] 2.4 Move feature artifacts under features/ (specs, plans, brainstorms, learnings)
- [ ] 2.5 Create .gitkeep for empty domain dirs (finance, legal)
- [ ] 2.6 Remove any remaining empty old directories

## Phase 3: Update path references — executable code (Tier 1)

- [ ] 3.1 Update `worktree-manager.sh` — specs/ → features/specs/
- [ ] 3.2 Update `archive-kb.sh` — brainstorms/, plans/, specs/ → features/
- [ ] 3.3 Update `generate-article-30-register.sh` — specs/archive/ → features/specs/archive/
- [ ] 3.4 Update `scheduled-competitive-analysis.yml` — overview/competitive-intelligence → product/competitive-intelligence
- [ ] 3.5 Update `scheduled-community-monitor.yml` — community/ → support/community/, overview/brand-guide → marketing/brand-guide
- [ ] 3.6 Verify `content-publisher.sh` and `scheduled-content-publisher.yml` — confirm marketing/ path is already correct

## Phase 4: Update path references — agent instructions (Tier 2)

- [ ] 4.1 Update brand-guide refs in ~15 agents (brand-architect, all marketing agents, cpo, cfo, cro, community-manager, ux-design-lead, ops-provisioner)
- [ ] 4.2 Update business-validation refs (business-validator, cpo, competitive-intelligence)
- [ ] 4.3 Update competitive-intelligence, content-strategy, pricing-strategy refs (competitive-intelligence agent)
- [ ] 4.4 Update ops/ → operations/ refs (ops-advisor, ops-research, ops-provisioner, coo, cfo)
- [ ] 4.5 Update community/ → support/community/ refs (community-manager, cco)
- [ ] 4.6 Update design/ → product/design/ refs (ux-design-lead)
- [ ] 4.7 Update learnings/ → features/learnings/ refs (learnings-researcher — 13 category paths, infra-security)

## Phase 5: Update path references — skill instructions (Tier 3)

- [ ] 5.1 Update compound/SKILL.md (constitution, learnings, specs, brainstorms, plans)
- [ ] 5.2 Update compound-capture/SKILL.md + references/yaml-schema.md + assets/ (learnings 30+ refs, constitution, components, README)
- [ ] 5.3 Update plan/SKILL.md (constitution, specs, plans, brainstorms, learnings)
- [ ] 5.4 Update brainstorm/SKILL.md + references/ (brainstorms, specs, learnings, brand-guide, business-validation)
- [ ] 5.5 Update work/SKILL.md + references/ (constitution, specs)
- [ ] 5.6 Update ship/SKILL.md (brainstorms, plans, specs, learnings, brand-guide)
- [ ] 5.7 Update archive-kb/SKILL.md (brainstorms, plans, specs)
- [ ] 5.8 Update merge-pr/SKILL.md (brainstorms, plans, specs)
- [ ] 5.9 Update remaining skills (one-shot, spec-templates, deepen-plan, competitive-analysis, discord-content, content-writer, social-distribute, growth, community, release-docs, brainstorm-techniques)

## Phase 6: Update commands and AGENTS.md (Tier 4)

- [ ] 6.1 Update AGENTS.md — overview/constitution → project/constitution
- [ ] 6.2 Update sync.md — new mkdir structure, new read paths

## Phase 7: Internal knowledge-base cross-references

- [ ] 7.1 Grep for old paths within knowledge-base/ (excluding archive dirs)
- [ ] 7.2 Update internal cross-references

## Phase 8: Documentation refresh

- [ ] 8.1 Update project/components/knowledge-base.md directory tree diagram
- [ ] 8.2 Update project/README.md directory structure

## Phase 9: Verification

- [ ] 9.1 Grep for all old path patterns — must return zero results
- [ ] 9.2 Commit all changes as single atomic commit
