# Onboarding Walkthrough Brainstorm

**Date:** 2026-04-03
**Issue:** [#1375](https://github.com/jikig-ai/soleur/issues/1375)
**Parent:** [#674](https://github.com/jikig-ai/soleur/issues/674) (Phase 2: Secure for Beta)
**Status:** Phase 2 is 13/14 complete. This is the last open item.

## What We're Building

A lightweight first-time onboarding experience for the Command Center UI. Three components:

1. **Welcome card** -- appears above the chat input on first login. One declarative sentence in brand voice that frames Soleur as an AI organization ready to work. Auto-dismisses when the user sends their first message (the activation moment).

2. **Pulsing @-mention hint** -- on first visit, the existing "@-mention" hint text gets a subtle visual emphasis (pulse animation or highlight) that disappears after the user's first @-mention interaction. Drives the user toward the "aha moment."

3. **iOS PWA install banner** -- a dismissible callout for iOS Safari users explaining how to add to home screen. Detected via user agent. Remembers dismissal in the database.

Completion state tracked via an `onboarding_completed_at` timestamp column on the users table (Supabase migration).

## Why This Approach

| Factor | Decision |
|--------|----------|
| **Audience** | <10 personally invited, tech-savvy founders who already know what Soleur is |
| **UI complexity** | Dashboard is simple: chat input, @-mention, 4 suggested prompts, domain leader strip |
| **Tour library** | Rejected. Shepherd.js/React Joyride add dependency weight and multi-step chrome for a simple UI |
| **Progressive disclosure** | Rejected. No guaranteed sequence -- user might miss the @-mention explanation |
| **Guided first action** | Chosen. Minimal nudge toward the activation moment. Everything else discovered organically via existing suggested prompts and hint text |
| **Brand voice** | Declarative, bold. No "Welcome! Let's explore." No "assistant/copilot/tool/plugin." CMO requirement |

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | No tour library | <10 users on a simple UI. A 7-step spotlight tour patronizes tech-savvy founders. |
| 2 | Auto-dismiss on first message | The welcome card disappears at the activation moment. No manual dismiss button needed. |
| 3 | Database column for state | `onboarding_completed_at` on users table. Survives device/browser changes. No localStorage. |
| 4 | iOS Safari detection only | Android handles PWA install prompts natively. Only iOS Safari needs explicit "Add to Home Screen" guidance. |
| 5 | Basic analytics events | Track: onboarding_card_shown, onboarding_card_dismissed, first_message_sent, pwa_banner_shown, pwa_banner_dismissed. No analytics library exists yet -- needs instrumentation layer. |
| 6 | Copywriter agent for copy | User-facing copy goes through the copywriter specialist before implementation (per UX/content review gates learning). |
| 7 | Pulsing @-mention hint | Subtle CSS animation on first visit. Disappears after first @-mention interaction. Not a tooltip overlay. |

## Open Questions

- **Analytics implementation:** No analytics library exists in the web platform. Events need a lightweight instrumentation layer (custom events, Plausible custom events, or PostHog). Decision deferred to plan phase.
- **Welcome card visual design:** Should UX design lead produce a wireframe, or is this simple enough to implement directly from the spec?
- **Copy content:** Exact welcome card text to be produced by copywriter agent during planning. Must follow brand guide voice.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Initial assessment recommended keeping deferral based on stale data (claimed Phase 1 incomplete). Corrected assessment: Phase 1 is complete, Phase 2 is 13/14 done, tag-and-route shipped, UI is stable. The walkthrough now targets the production UI. Useful CPO insight: when Phase 4 guided onboarding begins, define specific confusion metrics (time-to-first-message, support questions, drop-off) that would inform future iteration.

### Marketing (CMO)

**Summary:** Tooltip copy must match brand guide tone -- declarative, bold, no hedging. Never use "assistant," "copilot," "tool," or "plugin." The walkthrough should drive users to the first @-mention interaction as the "aha moment," not just explain UI elements. Track walkthrough completion rate as an activation metric from day one. A polished onboarding flow produces screenshots and GIFs reusable for landing page, social, and docs content. Recommended conversion-optimizer or ux-design-lead for layout review since this is a conversion surface.
