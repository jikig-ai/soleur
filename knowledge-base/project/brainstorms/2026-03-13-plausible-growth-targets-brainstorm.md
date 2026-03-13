# Brainstorm: Plausible Analytics Operationalization & Growth Targets

**Date:** 2026-03-13
**Status:** Captured
**Participants:** Founder, CMO (agent assessment)

## What We're Building

An analytics operationalization layer that turns Plausible from a passive tracking tool into an active growth feedback loop. Three deliverables:

1. **Updated marketing strategy** with WoW growth targets, upgraded analytics priority, UTM conventions, and Plausible goal configuration requirements
2. **Weekly analytics snapshot template** (markdown in `knowledge-base/marketing/analytics/`) capturing Tier 1 metrics with WoW delta calculations
3. **CI automation** (GitHub Actions workflow) that pulls Plausible data via API and commits weekly snapshot files

## Why This Approach

Plausible is live and properly deployed on every page of soleur.ai, but no one is looking at it. The marketing strategy prescribes weekly analytics checks (line 379) and defines phased KPIs, but zero measurements have been taken. Content distribution started March 12 — without capturing baselines and establishing a review cadence now, we lose the ability to measure whether the content strategy is working.

The CMO assessment identified the core problem: not missing infrastructure, but missing operationalization. The strategy has absolute milestone targets (500+ monthly visitors) but no rate-of-change targets. Milestones are lagging indicators — by the time you miss one, the correction window has closed. WoW growth rates are leading indicators that surface problems while fixable.

## Key Decisions

1. **Update marketing-strategy.md directly** rather than creating a separate analytics plan document. Single source of truth.
2. **Adopt CMO's 3-phase WoW growth target framework:**
   - Phase 1 (Weeks 1-4): +15% WoW unique visitors, target 100/week by week 4
   - Phase 2 (Weeks 5-8): +10% WoW, target 250/week, organic search compounds
   - Phase 3 (Weeks 9-16): +7% WoW, target 500/week, aligns with strategy milestone
3. **Upgrade analytics priority** from Low to Medium in marketing-strategy.md (High once 4+ content pieces are live).
4. **Weekly snapshots as markdown files** in `knowledge-base/marketing/analytics/` — git-tracked, reviewable in PRs.
5. **Plausible API setup required** — founder has account but no API key yet. CI workflow will be built but requires API key as a GitHub secret to activate.
6. **Plausible goals to configure** (dashboard tasks for the founder):
   - Newsletter Signup as a Plausible Goal (event already instrumented)
   - Getting Started pageview goal (`/pages/getting-started.html`)
   - Blog pageview goals (`/blog/*`)
   - Enable outbound link tracking (GitHub, Discord clicks)
7. **UTM conventions** to document in the strategy:
   - Discord: `utm_source=discord&utm_medium=social&utm_campaign=<slug>`
   - X/Twitter: `utm_source=x&utm_medium=social&utm_campaign=<slug>`
   - IndieHackers: `utm_source=indiehackers&utm_medium=social&utm_campaign=<slug>`

## Metrics to Track Week Over Week

### Tier 1: Available Now (No Configuration)

| Metric | Why Track WoW |
|--------|--------------|
| Unique visitors | Primary growth signal |
| Total pageviews | Engagement depth |
| Pages per visit | Content stickiness |
| Top pages | Which content gets traffic |
| Referral sources | Which channels work |
| Bounce rate | Content/CTA effectiveness |
| Visit duration | Engagement quality |

### Tier 2: Requires Plausible Goal Configuration

| Metric | Configuration Needed |
|--------|---------------------|
| Newsletter signups | Configure as Plausible Goal (already instrumented) |
| GitHub outbound clicks | Enable outbound link tracking extension |
| Discord outbound clicks | Same as above |
| Blog article pageview goals | Create pageview goals for `/blog/*` |
| Getting Started pageview goal | Create pageview goal for `/pages/getting-started.html` |

### Tier 3: Requires Code Changes (Future)

| Metric | Implementation |
|--------|---------------|
| CTA click events | Add `plausible()` calls to key CTAs |
| Scroll depth on articles | Custom scroll tracking |

## CMO Challenges (Accepted)

1. **Analytics rated "Low" priority is wrong** — upgrading to Medium immediately. Content is publishing; analytics is the feedback loop.
2. **No WoW targets in strategy** — adding the 3-phase framework with rate-of-change targets alongside existing absolute milestones.
3. **Weekly cadence has no enforcement** — building CI automation to force the review habit. Until Plausible API is configured, the template provides structure for manual capture.

## Open Questions

1. What is the current baseline traffic? (Requires logging into Plausible — founder action)
2. Should we add Google Search Console integration to Plausible for organic search keyword data?
3. Should newsletter signup conversion rate be a tracked metric once we have enough data?

## Scope Boundaries

- **In scope:** Strategy updates, snapshot template, CI workflow, Plausible goal documentation
- **Out of scope:** Code changes to soleur.ai (CTA tracking, outbound link script changes), Plausible dashboard configuration (founder action), A/B testing setup, heatmaps
