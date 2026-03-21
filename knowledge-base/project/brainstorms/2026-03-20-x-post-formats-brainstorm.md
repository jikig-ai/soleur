# Brainstorm: X Post Formats

**Date:** 2026-03-20
**Issue:** #683
**Status:** Decided
**Participants:** Founder, CMO assessment

## What We're Building

Nothing new. This brainstorm evaluated whether to add X Articles alongside the existing thread format for @soleur_ai's X/Twitter presence.

## Why This Approach

**Decision: Threads-only. Revisit X Articles at 5k followers.**

The evaluation considered format mechanics, audience size, brand voice fit, existing tooling, and content strategy alignment:

- **Reach mechanics:** Each tweet in a thread is a separate discovery surface in the timeline. X Articles are a single engagement unit with lower algorithmic distribution — especially for accounts under 5k followers.
- **Audience size:** @soleur_ai is under 500 followers. Articles require existing distribution to surface organically. At this stage, threads structurally outperform.
- **Brand voice:** The brand guide specifies short, punchy, declarative copy. Threads are a natural fit. Long-form articles dilute the voice.
- **Tooling:** The entire pipeline (`social-distribute`, `x-community.sh`, `content-publisher.sh`, brand guide channel notes) is built around threads. Adding articles requires new tooling with no API support — only manual publishing or Playwright automation.
- **Blog traffic:** Threads tease content and drive clicks to soleur.ai. Articles absorb the reader on-platform, competing with the blog for attention. This conflicts with the SEO/AEO strategy that needs blog pageviews.
- **Active campaign:** Case study campaign runs through 2026-03-30 using threads. No format changes mid-campaign.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Threads remain the sole X format** | Higher reach per-tweet, better brand voice fit, proven blog traffic driver, full tooling support |
| 2 | **No X Articles investment now** | Low organic distribution under 5k followers, no API exists, competes with blog, requires new tooling |
| 3 | **Revisit at 5k followers** | At that scale, algorithmic distribution makes articles viable. Re-evaluate format mix then |
| 4 | **Optimize thread quality** | Focus effort on better hooks, engagement patterns, and A/B testing rather than adding a new format |

## Open Questions

None. The decision is clear given current audience size and tooling state.

## CMO Assessment Summary

The CMO conducted a detailed format comparison across 10 dimensions (reach, engagement, depth, traffic driving, repurposing, brand voice, automation, audience behavior, discoverability, content depth). Threads won on 8 of 10 dimensions. Articles only edge ahead on content depth — but that's what the blog is for.

Recommended hybrid model deferred: 1-2 flagship articles per quarter could work post-5k followers for content that genuinely cannot compress to thread format. Not actionable now.
