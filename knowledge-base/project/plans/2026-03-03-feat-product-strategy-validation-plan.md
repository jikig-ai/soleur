---
title: Product Strategy Validation Plan
type: feat
date: 2026-03-03
---

# Product Strategy Validation Plan

[Updated 2026-03-03 -- simplified after plan review: removed telemetry, split-cohort, blog infra; compressed from 12 to 6 weeks]

## Overview

A 6-week validation sprint to determine if the CaaS thesis is real. Two phases: (1) ship content and recruit, (2) talk to people and let them use the product.

Soleur has 61 agents, 55 skills, and 420+ PRs but zero confirmed external users. The business validation (2026-02-25) issued a PIVOT verdict. This plan answers one question: **do solo founders have multi-domain pain that Soleur can solve, and will they pay for it?**

## Timeline

```
Week:  1         2         3         4         5         6
       [===SETUP + CONTENT===]
                 [=====INTERVIEWS + RECRUIT=====]
                            [====PRODUCT USAGE (2 wks)====]
                                               [DEBRIEF + DECISION]
```

## Phase 1: Setup + Content (Weeks 1-2)

### Task 1: Onboarding Audit [auto]

Fix the first-run experience so a stranger can install and use Soleur in 10 minutes.

**Audit checklist:**
- [ ] Check Getting Started nav position (must be top 3 -- learning 2026-02-17)
- [ ] Fresh install test: `claude plugin install soleur` then `/soleur:go` on a new project
- [ ] Test `/soleur:sync` on a project with no `knowledge-base/`
- [ ] Test 3 non-engineering domain tasks end-to-end (legal doc, brand guide, competitive analysis)
- [ ] Document the "first 5 minutes" flow: install -> sync -> one domain task -> see result
- [ ] Fix any blockers found

**Deliverable:** Onboarding audit report + fixes shipped (`knowledge-base/project/specs/feat-product-strategy/onboarding-audit.md`)

**Files to modify (if needed):**
- `plugins/soleur/docs/pages/getting-started.md`
- `plugins/soleur/commands/go/COMMAND.md`

### Task 2: Write Case Studies [auto + human]

Write 5 case studies from Soleur's own non-engineering usage. Each follows a consistent structure.

**Case studies (prioritized by non-engineering value):**

| # | Domain | Case Study | Source |
|---|--------|-----------|--------|
| 1 | Legal | Generated 9 legal documents from scratch | `docs/pages/legal/` |
| 2 | Marketing | Created brand guide (identity, voice, visual direction) | `knowledge-base/overview/brand-guide.md` |
| 3 | Marketing | Competitive intelligence scan with 6-tier threat analysis | `knowledge-base/overview/competitive-intelligence.md` |
| 4 | Product | Business validation with 6 sequential gates | `knowledge-base/overview/business-validation.md` |
| 5 | Operations | Expense tracking, hosting research, infrastructure provisioning | `knowledge-base/ops/` |

**Structure per case study:**
1. The problem -- what non-engineering task needed doing?
2. The AI approach -- which domain/agent, what workflow?
3. The result -- concrete artifact produced
4. The cost comparison -- consultant/agency equivalent cost and time
5. The compound effect -- how this feeds future work

**Deliverable:** 5 case study drafts reviewed against brand guide voice

### Task 3: Interview Guide [auto]

One file with everything needed to conduct 10 interviews.

**Contents of `knowledge-base/project/specs/feat-product-strategy/interview-guide.md`:**

1. **Questions (30 min):**
   - What are you building? How far along? Team size? (5 min)
   - Walk me through what you did last week that wasn't coding. Which tasks felt like a distraction? Have you tried using AI for any of those? (15 min)
   - [Show list: legal, marketing, ops, finance, sales, support] Which have you spent time on? Which are you ignoring? (5 min)
   - If a tool handled [their top pain domain], what would it need to do? How much time per week would it save? What would you pay? (5 min)

2. **"Independent pain" definition:** Pain mentioned in questions 2 (open-ended) BEFORE the structured list in question 3. Question 3 responses are "prompted," not "independent."

3. **Response recording table:**

   | Founder | Stage | Team | Domains (independent) | Domains (prompted) | Top pain | WTP signal | Key quote |
   |---------|-------|------|----------------------|-------------------|----------|-----------|-----------|
   | | | | | | | | |

4. **Screening:** Solo technical founder (team <= 3), uses AI tools, building a product (not freelancing)

5. **Recruitment channels:** Inbound from case studies first. Fallback: IndieHackers, Claude Code Discord, Twitter/X.

### Task 4: Publish Case Studies [human]

Post case studies across channels. 1-2 per week through Weeks 1-4.

**Channels:**
1. Discord (via `discord-content` skill)
2. Twitter/X (manual)
3. IndieHackers (manual)
4. Claude Code Discord (manual)

**Inbound tracking:** Simple markdown file (`knowledge-base/project/specs/feat-product-strategy/inbound-tracker.md`). "Expression of interest" = Discord message, GitHub star from a non-creator, social reply asking to try it, or DM requesting access.

## Phase 2: Interviews + Product Test (Weeks 2-5)

### Task 5: Recruit 10 Founders [human]

Source from case study inbound first. If insufficient by Week 3, cold outreach via recruitment channels. Minimum viable: 7 founders (not 10).

**Screening:** Use criteria from interview guide (Task 3).

**Bias note:** Creator conducts interviews with standardized script, no product demo. Have a second person review response coding for consistency. Acknowledge this is imperfect -- at this stage, directional signal matters more than experimental purity.

### Task 6: Interview + Onboard (Weeks 2-4) [human]

For each founder, in sequence:

1. **Interview (30 min):** Follow the interview guide. Code responses immediately after.
2. **Guided onboarding (30 min):** Install Soleur, run `/soleur:sync`, walk through one non-engineering domain task together.
3. **Leave for 2 weeks of unassisted usage.**

All 10 founders get the same guided domain task (pick the strongest -- likely legal doc generation based on case study strength).

**Observation during unassisted period:**
- Weekly 15-minute check-in call (replaces telemetry): "What did you use this week? Any questions?"
- Note which domains they mention using on their own
- Note what broke or confused them

**"Unprompted usage" = founder describes using a domain other than the guided one, without researcher suggestion. Counted from check-in calls and debrief.**

**Attrition protocol:** If a founder drops out mid-test, they count as a non-pass for all gates. Denominator is always 10 (intent-to-treat), not "whoever completed."

### Task 7: Debrief + Gate Assessment (Weeks 5-6) [human]

After each founder's 2-week unassisted period, conduct a debrief call.

**Debrief questions (3 questions, 15 min):**
1. What did you use Soleur for? What worked, what didn't? Which domains were useful vs. irrelevant?
2. Would you pay for this? How much per month? (open-ended, no anchoring)
3. If I removed Soleur from your setup tomorrow, what would you miss?

**Gate assessment (Week 6):**

| Gate | Pass Criteria | Fail Path |
|------|--------------|-----------|
| G1: Multi-domain pain | 5/10 founders independently describe multi-domain pain (intensity >= 3) | If 3-4/10: extend to 15 interviews. If <= 2: CaaS thesis not validated -- pivot. |
| G2: Product delivers value | 3/10 use a non-guided domain unprompted during unassisted period | If 1-2/10: investigate product discovery issues. If 0: fundamental product gap. |
| G3: WTP signal | 3/10 express WTP >= $25/month | If WTP exists but < $25: investigate price sensitivity. If zero WTP: product not valuable enough to charge. |
| G4: Cowork risk (monitoring) | No existential Cowork CaaS threat shipped during weeks 1-6 | If Cowork ships 3+ domain coverage: trigger multi-platform evaluation regardless of other gates. |

**Check Cowork weekly:** Review Anthropic blog, Cowork changelog, and Claude Code Discord announcements every Monday morning.

**Decision rules:**
- **All validation gates pass (G1-G3) + risk clear (G4):** Build a real roadmap.
- **2/3 validation gates pass:** Iterate on the failing dimension for 4 more weeks with 5 new people.
- **0-1/3 validation gates pass:** CaaS thesis invalidated. Pivot or wind down non-engineering domains.

**Deliverable:** Gate assessment report (`knowledge-base/project/specs/feat-product-strategy/gate-assessment.md`) with decision.

## Acceptance Criteria

- [ ] Onboarding works for a stranger (fresh install test passes)
- [ ] 5 case studies published across at least 2 channels
- [ ] 10+ problem interviews conducted and recorded
- [ ] 10 founders complete 2-week product usage test (with check-in calls, not telemetry)
- [ ] Debrief interviews completed for all participants
- [ ] Week 6 gate assessment completed with documented decision

## Test Scenarios

- Given a fresh project with no knowledge-base, when a founder runs `claude plugin install soleur && /soleur:go`, then the first action is clear and completes without errors
- Given 10 recorded interview responses, when analyzing for multi-domain pain, then the response table produces a clear pass/fail signal against gate criteria
- Given weekly check-in call notes over 2 weeks, when reviewing domain mentions, then unprompted usage is distinguishable from guided usage
- Given a gate failure (e.g., only 2/10 describe multi-domain pain), when reaching the decision point, then the fail path is documented and actionable

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Cannot recruit 10 founders | Medium | High | Multiple channels, lower bar to 7 minimum |
| Creator bias inflates WTP | High | High | Standardized script, no demos, second coder |
| Founders only use engineering domains | Medium | High | Accept the signal -- it invalidates CaaS thesis |
| Anthropic ships Cowork CaaS | Medium | Critical | Weekly monitoring, multi-platform escape hatch |
| Founders drop out mid-test | Medium | Medium | Intent-to-treat: dropouts count as non-pass |

## Separate Initiative: Blog Infrastructure

Blog for soleur.ai is a separate initiative for ongoing SEO/AEO and regular communication -- not part of this validation plan. Track as a separate GitHub issue. Case studies from this plan can be migrated to the blog once infrastructure exists.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-03-product-strategy-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-product-strategy/spec.md`
- Business validation: `knowledge-base/overview/business-validation.md`
- Competitive intelligence: `knowledge-base/overview/competitive-intelligence.md`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- GitHub issue: #430
