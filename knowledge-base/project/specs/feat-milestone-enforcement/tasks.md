# Tasks: Milestone Enforcement on Issue Creation

## Phase 1: Governance (AGENTS.md + Constitution)

- [ ] 1.1 Add milestone enforcement hard rule to AGENTS.md
- [ ] 1.2 Add milestone convention to constitution.md Architecture > Always section

## Phase 2: Shell Scripts

- [ ] 2.1 Update `scripts/content-publisher.sh` to add `--milestone "Post-MVP / Later"` to `gh issue create`
- [ ] 2.2 Update `scripts/strategy-review-check.sh` to add `--milestone "Post-MVP / Later"` to `gh issue create`

## Phase 3: GitHub Actions Workflows (Direct `gh issue create`)

- [ ] 3.1 Update `.github/workflows/review-reminder.yml` to add `--milestone "Post-MVP / Later"`
- [ ] 3.2 Update `.github/workflows/scheduled-terraform-drift.yml` to add `--milestone "Post-MVP / Later"`
- [ ] 3.3 Update `.github/workflows/scheduled-linkedin-token-check.yml` to add `--milestone "Post-MVP / Later"`
- [ ] 3.4 Update `.github/workflows/scheduled-cf-token-expiry-check.yml` to add `--milestone "Post-MVP / Later"`

## Phase 4: GitHub Actions Workflows (Agent-Prompted)

- [ ] 4.1 Update `.github/workflows/scheduled-roadmap-review.yml` prompt to instruct milestone assignment
- [ ] 4.2 Update `.github/workflows/scheduled-content-generator.yml` prompt to instruct milestone assignment
- [ ] 4.3 Update `.github/workflows/scheduled-growth-audit.yml` to assign milestones at creation time (not just CPO follow-up)
- [ ] 4.4 Update `.github/workflows/scheduled-seo-aeo-audit.yml` prompt to instruct milestone assignment
- [ ] 4.5 Update `.github/workflows/scheduled-growth-execution.yml` prompt to instruct milestone assignment
- [ ] 4.6 Update `.github/workflows/scheduled-competitive-analysis.yml` prompt to instruct milestone assignment

## Phase 5: Skills

- [ ] 5.1 Update `plugins/soleur/skills/plan/SKILL.md` issue creation section to include milestone assignment
- [ ] 5.2 Update `plugins/soleur/skills/brainstorm/SKILL.md` issue creation to include milestone assignment
- [ ] 5.3 Update `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` to include milestone assignment
- [ ] 5.4 Update `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` to include milestone assignment

## Phase 6: Fix Existing Issues

- [ ] 6.1 Assign milestones to all 10 un-milestoned open issues (CPO determines correct milestone for each)
  - [ ] 6.1.1 #1149 fix: Cloudflare challenge script blocked by CSP on docs site
  - [ ] 6.1.2 #1146 feat: add functional QA agent/skill for end-to-end feature verification
  - [ ] 6.1.3 #1142 feat: website conversion flow review -- waitlist-first funnel
  - [ ] 6.1.4 #1117 pencil integration: I() insert does not support positional placement
  - [ ] 6.1.5 #1116 pencil integration: export_nodes uses node IDs as filenames
  - [ ] 6.1.6 #1108 pencil integration: set_variables requires {type, value} objects
  - [ ] 6.1.7 #1107 pencil integration: padding on text nodes silently rejected
  - [ ] 6.1.8 #1106 pencil integration: alignSelf not supported on frames
  - [ ] 6.1.9 #1083 [Content Publisher] LinkedIn API failed -- Vibe Coding post
  - [ ] 6.1.10 #1082 [Content Publisher] LinkedIn API failed -- Brand Guide post

## Phase 7: Verification

- [ ] 7.1 Run `gh issue list --state open --json number,milestone --jq '[.[] | select(.milestone == null)] | length'` to verify zero un-milestoned issues
- [ ] 7.2 Grep all `gh issue create` invocations to verify all include `--milestone`
