# Tasks: Milestone Enforcement on Issue Creation

## Phase 1: PreToolUse Hook Guard (strongest enforcement)

- [ ] 1.1 Add Guard 5 to `.claude/hooks/guardrails.sh` blocking `gh issue create` without `--milestone`
  - [ ] 1.1.1 Add guard logic using `(^|&&|\|\||;)` anchoring pattern (match Guards 1-4)
  - [ ] 1.1.2 Update header comment (line 4) to include Guard 5 in the block list
  - [ ] 1.1.3 Add Guard 5 prose rule comment referencing AGENTS.md and constitution.md
- [ ] 1.2 Test Guard 5 does not false-positive on `gh issue edit`, `gh issue list`, `gh issue view`
- [ ] 1.3 Test Guard 5 correctly catches chained commands (`&& gh issue create`)

## Phase 2: Governance (AGENTS.md + Constitution)

- [ ] 2.1 Add milestone enforcement hard rule to AGENTS.md Hard Rules section
  - Use one-line format with `[hook-enforced: guardrails.sh Guard 5]` annotation
- [ ] 2.2 Update AGENTS.md PreToolUse hooks awareness line to include Guard 5
- [ ] 2.3 Add milestone convention to `constitution.md` Architecture > Always section

## Phase 3: Shell Scripts (direct `gh issue create`)

- [ ] 3.1 Update `scripts/content-publisher.sh` line 452 -- add `--milestone "Post-MVP / Later"`
- [ ] 3.2 Update `scripts/strategy-review-check.sh` line 145 -- add `--milestone "Post-MVP / Later"`

## Phase 4: GitHub Actions Workflows (direct `gh issue create`)

- [ ] 4.1 Update `.github/workflows/review-reminder.yml` line 129 -- add `--milestone "Post-MVP / Later"`
- [ ] 4.2 Update `.github/workflows/scheduled-terraform-drift.yml` line 180 -- add `--milestone "Post-MVP / Later"`
- [ ] 4.3 Update `.github/workflows/scheduled-linkedin-token-check.yml` line 78 -- add `--milestone "Post-MVP / Later"`
- [ ] 4.4 Update `.github/workflows/scheduled-cf-token-expiry-check.yml` line 121 -- add `--milestone "Post-MVP / Later"`

## Phase 5: GitHub Actions Workflows (agent-prompted)

- [ ] 5.1 Add standard MILESTONE RULE instruction block to `.github/workflows/scheduled-roadmap-review.yml` prompt
- [ ] 5.2 Add MILESTONE RULE to `.github/workflows/scheduled-content-generator.yml` prompt (5 issue creation points)
- [ ] 5.3 Add MILESTONE RULE to `.github/workflows/scheduled-growth-audit.yml` tracking issue step
- [ ] 5.4 Add MILESTONE RULE to `.github/workflows/scheduled-seo-aeo-audit.yml` prompt
- [ ] 5.5 Add MILESTONE RULE to `.github/workflows/scheduled-growth-execution.yml` prompt
- [ ] 5.6 Add MILESTONE RULE to `.github/workflows/scheduled-competitive-analysis.yml` prompt

## Phase 6: Skills

- [ ] 6.1 Update `plugins/soleur/skills/plan/SKILL.md` Issue Creation section -- two-step pattern with default milestone
- [ ] 6.2 Update `plugins/soleur/skills/brainstorm/SKILL.md` line 234 -- add `--milestone` and roadmap read instruction
- [ ] 6.3 Update `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` line 11 -- add `--milestone`
- [ ] 6.4 Update `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md` line 13 -- add `--milestone`

## Phase 7: Fix Existing Issues

- [ ] 7.1 Assign milestones to all 10 un-milestoned open issues (CPO determines correct milestone)
  - [ ] 7.1.1 #1149 fix: Cloudflare challenge script blocked by CSP on docs site -> Post-MVP / Later
  - [ ] 7.1.2 #1146 feat: add functional QA agent/skill -> Post-MVP / Later
  - [ ] 7.1.3 #1142 feat: website conversion flow review -> CPO to determine (Phase 3 or Marketing Gate?)
  - [ ] 7.1.4 #1117 pencil: I() insert positional placement -> Post-MVP / Later
  - [ ] 7.1.5 #1116 pencil: export_nodes filenames -> Post-MVP / Later
  - [ ] 7.1.6 #1108 pencil: set_variables error -> Post-MVP / Later
  - [ ] 7.1.7 #1107 pencil: padding on text nodes -> Post-MVP / Later
  - [ ] 7.1.8 #1106 pencil: alignSelf not supported -> Post-MVP / Later
  - [ ] 7.1.9 #1083 Content Publisher LinkedIn failure -> Post-MVP / Later
  - [ ] 7.1.10 #1082 Content Publisher LinkedIn failure -> Post-MVP / Later

## Phase 8: Verification

- [ ] 8.1 Run `gh issue list --state open --json number,milestone --jq '[.[] | select(.milestone == null)] | length'` to confirm zero un-milestoned issues
- [ ] 8.2 Grep all `gh issue create` invocations in active code to confirm all include `--milestone`:
  - `grep -rn 'gh issue create' scripts/ .github/workflows/ plugins/soleur/skills/ --include='*.sh' --include='*.yml' --include='*.md' | grep -v 'milestone'`
- [ ] 8.3 Verify Guard 5 is active by attempting `gh issue create` without `--milestone` in the worktree shell
