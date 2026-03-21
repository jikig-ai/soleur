# Learning: Document Plan Conditional Omissions

## Problem

The deepened plan identified 4 surfaces to check after provisioning, including `base.njk` with a conditional qualifier ("if social icon links exist there"). The implementation correctly dropped `base.njk` because the footer renders links from `site.json` footerLinks, not direct social icon references. But the omission was silent — no documentation of why 3 surfaces were implemented instead of 4. Three independent review agents flagged the plan-implementation mismatch.

## Solution

When a plan includes conditional items ("if X exists", "if applicable"), the implementation should explicitly document why conditions were or were not met. Options:

- Add a brief note in the commit message explaining the delta
- Update the plan's acceptance criteria to reflect the actual scope
- Add a comment in the implementation noting the intentional omission

## Key Insight

Silent omissions from plans create review noise. Every conditional plan item that gets dropped should leave a trace — either in the code, the commit, or the plan itself. This is especially true when multiple reviewers will independently flag the same gap.

## Tags

category: workflow
module: planning
