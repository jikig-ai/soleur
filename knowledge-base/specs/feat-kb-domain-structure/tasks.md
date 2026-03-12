# Tasks: Knowledge-Base Domain Structure

## Phase 1: Prep

- [ ] 1.1 Rename `knowledge-base/marketing/content-strategy.md` → `case-study-distribution-plan.md` (resolve name collision)
- [ ] 1.2 Create target directories: `mkdir -p knowledge-base/{product,operations,support,engineering/audits,marketing/audits}`

## Phase 2: Execute git mv

- [ ] 2.1 Move strategy docs from overview/ to domains (brand-guide, content-strategy, marketing-strategy → marketing; business-validation, competitive-intelligence, pricing-strategy → product)
- [ ] 2.2 Move audits/soleur-ai → marketing/audits, security audit → engineering/audits
- [ ] 2.3 Move design/ → product/design/
- [ ] 2.4 Move ops/ files → operations/
- [ ] 2.5 Move community/ → support/community/

## Phase 3: Update path references

- [ ] 3.1 Update ~15 agent files — brand-guide refs (overview/ → marketing/)
- [ ] 3.2 Update 3 agent files — business-validation refs (overview/ → product/)
- [ ] 3.3 Update competitive-intelligence agent — competitive-intelligence, content-strategy, pricing-strategy refs
- [ ] 3.4 Update 5 ops agents — ops/ → operations/
- [ ] 3.5 Update 2 support agents + 1 skill — community/ → support/community/
- [ ] 3.6 Update ux-design-lead — design/ → product/design/
- [ ] 3.7 Update skills — brand-guide refs in brainstorm workshops, competitive-analysis, discord-content, content-writer, social-distribute, growth, community, release-docs, ship
- [ ] 3.8 Update workflows — scheduled-competitive-analysis.yml, scheduled-community-monitor.yml
- [ ] 3.9 Update todos/ — business-validation refs (informational)

## Phase 4: Verify

- [ ] 4.1 Grep for all old path patterns — must return zero results
- [ ] 4.2 Commit all changes as single atomic commit
