# Tasks: Knowledge-Base Domain Structure

## Phase 1: Prep

- [x] 1.1 Rename `knowledge-base/marketing/content-strategy.md` → `case-study-distribution-plan.md` (resolve name collision)
- [x] 1.2 Create target directories: `mkdir -p knowledge-base/{product,operations,support,engineering/audits,marketing/audits}`

## Phase 2: Execute git mv

- [x] 2.1 Move strategy docs from overview/ to domains (brand-guide, content-strategy, marketing-strategy → marketing; business-validation, competitive-intelligence, pricing-strategy → product)
- [x] 2.2 Move audits/soleur-ai → marketing/audits, security audit → engineering/audits
- [x] 2.3 Move design/ → product/design/
- [x] 2.4 Move ops/ files → operations/
- [x] 2.5 Move community/ → support/community/

## Phase 3: Update path references

- [x] 3.1 Update ~15 agent files — brand-guide refs (overview/ → marketing/)
- [x] 3.2 Update 3 agent files — business-validation refs (overview/ → product/)
- [x] 3.3 Update competitive-intelligence agent — competitive-intelligence, content-strategy, pricing-strategy refs
- [x] 3.4 Update 5 ops agents — ops/ → operations/
- [x] 3.5 Update 2 support agents + 1 skill — community/ → support/community/
- [x] 3.6 Update ux-design-lead — design/ → product/design/
- [x] 3.7 Update skills — brand-guide refs in brainstorm workshops, competitive-analysis, discord-content, content-writer, social-distribute, growth, community, release-docs, ship
- [x] 3.8 Update workflows — scheduled-competitive-analysis.yml, scheduled-community-monitor.yml
- [x] 3.9 Update todos/ — business-validation refs (informational)

## Phase 4: Verify

- [x] 4.1 Grep for all old path patterns — must return zero results
- [ ] 4.2 Commit all changes as single atomic commit
