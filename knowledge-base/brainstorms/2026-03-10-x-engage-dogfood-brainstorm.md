# X Engagement Dogfood Brainstorm

**Date:** 2026-03-10
**Status:** Decided
**Branch:** feat-x-engage-dogfood
**PR:** #495

## What We're Building

Graceful degradation in the `/soleur:community engage` sub-command so it can be dogfooded on the X API Free tier. When `fetch-mentions` returns a 403 (paid tier required), the workflow catches it and prompts the user to paste a mention URL/text manually. The rest of the pipeline (brand-voice draft, human-in-the-loop approval, post-tweet --reply-to) runs as normal.

Additionally:
- Light moderation guardrails added to the brand guide (topics to avoid, when to skip, max reply cadence)
- Deferred expense tracking for the $100/mo Basic tier upgrade (GitHub issue + expense ledger entry with DEFERRED status)

## Why This Approach

The engage features are fully built on main (fetch-mentions, fetch-timeline, post-tweet --reply-to, since-id state tracking, community-manager Capability 4). The only blocker is the X API Free tier, which excludes read endpoints like `/2/users/:id/mentions`. Rather than upgrading to the $100/mo Basic tier before validating the feature's value, we dogfood the posting path first at zero cost.

Graceful degradation was chosen over a separate `--manual` flag because:
1. It requires no new API surface -- the 403 handling is transparent
2. When the paid tier is eventually activated, the manual fallback disappears automatically
3. It tests the real pipeline path users will experience

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Paid tier timing | Deferred until revenue justifies it | $100/mo recurring on a pre-revenue account with zero followers is premature |
| Dogfood mode | Graceful degradation on 403 | Re-uses existing pipeline, zero new flags, disappears when paid tier activates |
| Cold-start strategy | Mix of #buildinpublic replies + quote-tweets | Replies build relationships, quote-tweets build visibility. Both on-strategy. |
| Moderation | Light guardrails in brand guide | Human-in-the-loop on every reply is the primary safety net at <50 tweets/month |
| Success criteria | Brand voice quality (>80% first-try approval) + reliability + content signal (engagement metrics) | All three validate the feature for different stakeholders |
| Expense tracking | GitHub issue + expense ledger DEFERRED entry | Issue provides visibility, ledger provides COO review surface. Scheduled cron deferred. |

## Domain Leader Assessments

### CMO Assessment
- X engagement aligns with marketing strategy ("share insights from building, not product announcements")
- "Built with Soleur" narrative is strongest social proof -- product running itself
- Cold-start problem: near-zero followers means no inbound mentions. Proactive engagement in #buildinpublic solves this.
- 50 tweets/month ceiling requires rate awareness (not yet tracked in x-community.sh)
- Recommended path: posting-only first, defer paid tier until 2-4 weeks of data validates the loop

### CCO Assessment
- No moderation policy, SLAs, or escalation paths exist for X -- high risk on a public adversarial platform
- Community digest is 19 days stale -- baseline digest should be generated before dogfooding
- Bug #478 (cmd_fetch_metrics bypasses x_request hardening) and #492 (response handling inconsistency) are P2 and affect X reliability
- Recommended: fix bugs + create moderation guardrails before going live

## Open Questions

1. Should we track tweet count against the 50/month cap programmatically, or is manual tracking sufficient during dogfooding?
2. What revenue milestone triggers the paid tier review? (e.g., first paying customer, $500 MRR, $1000 MRR?)
3. Should we generate a fresh community digest before starting dogfooding to establish a baseline?

## Scope

### In Scope
- 403 graceful degradation in engage sub-command (catch + manual URL prompt)
- URL-to-tweet-ID parsing for manual mention input
- X engagement guardrails section in brand guide
- GitHub issue for deferred paid tier upgrade
- Expense ledger DEFERRED entry

### Out of Scope
- Paid tier upgrade or procurement
- Rate-limit tracking (separate issue)
- Full moderation runbook (brand guide guardrails are sufficient at this volume)
- Browser automation for thread discovery (Approach B -- deferred)
- Fixes for #478 and #492 (separate issues, can run in parallel)
