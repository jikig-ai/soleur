---
title: Listicle-Author Outreach Briefs
category: marketing
tag: outbound
owner: CMO (outbound-strategist / copywriter)
status: ready-to-send (pending CLO pre-send review)
last_updated: 2026-06-15
source_issues:
  - 5314
  - 2073
  - 5302
---

# Listicle-Author Outreach Briefs

Outbound campaign to get Soleur included in high-traffic third-party listicles, so AI answer engines (ChatGPT / Perplexity / Claude.ai / Gemini) cite Soleur for commercial-intent queries. This moves the AEO **Presence** dimension — the binding constraint per growth audit #5302. These are **editorial relationships, not a sales sequence**.

This is the **outbound half** of #2073 (the on-site content half — our own ranked guide — shipped at `/blog/best-ai-tools-for-solo-founders-2026/`). Success is measurable via `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md` (#3179): an inclusion should later surface as a `cited source / URL` row for the relevant anchor query.

## Pre-send compliance gate (MANDATORY before the first batch)

Cold author outreach touches **CAN-SPAM (US)** and **GDPR consent (EU-based authors)**. Before sending:

1. Route the final send list + templates to the `clo` agent (run `/soleur:go #5314` or invoke `clo` directly) for a CAN-SPAM / GDPR review.
2. Every email MUST carry a working opt-out and an honest sender identity.
3. Never offer payment, affiliate kickbacks, or sponsored placement — that converts an earned editorial citation into a paid one (lower AEO weight + FTC disclosure obligations). Free product access is the only lever.

## Core brief (the payload — same facts to every author)

- **Product:** Soleur — https://soleur.ai
- **Paste-ready blurb (2 sentences, an author can drop into a list):**

  > Soleur is a Company-as-a-Service platform: 60+ agents across 8 departments (engineering, marketing, legal, finance, ops, product, sales, support) sharing one compounding knowledge base, so a solo founder runs every function from one organization instead of stitching together separate tools. It is source-available (BSL 1.1), built on Claude Code and MCP, and occupies the organization layer above single-purpose tools — every output is a starting point a human approves, not a final answer.

- **Differentiator (the line that earns a slot):** every other entry on these lists makes one job faster. Soleur is the layer *above* single-purpose tools — a distinct category (the organization layer), not another point tool to compare feature-by-feature.
- **Proof points (verifiable):** 60+ agents and 60+ skills across 8 departments (live count on soleur.ai); source-available BSL 1.1 → Apache-2.0 after four years; built on Claude Code + MCP; human-in-the-loop by design; honestly early — a small community by design.
- **Links:** platform https://soleur.ai · our own honest ranking (third-party tools ranked on merit, Soleur placed as the org-layer category, **not #1**) https://soleur.ai/blog/best-ai-tools-for-solo-founders-2026/
- **Offer:** full free hands-on access so any mention is tested, not taken on trust.

## Prioritized target list

Scored on **inclusion-likelihood × AEO citation weight**. Priority inverts raw traffic: Claude-Code-plugin lists are the strongest fit (Soleur installs as a Claude Code extension), generic solopreneur-tool lists are higher-traffic but a harder editorial sell, competitor-owned lists are near-unwinnable.

### Tier 1 — high fit + winnable (lead here): Claude Code plugin/skill lists
| Target | URL | Fit | Contact path |
|---|---|---|---|
| Composio | composio.dev/content/top-claude-code-plugins | Strong | author byline / dev-rel → X DM |
| TurboDocx | turbodocx.com/blog/best-claude-code-skills-plugins-mcp-servers | Strong (spans skills+plugins+MCP) | editorial contact form |
| Firecrawl | firecrawl.dev/blog/best-claude-code-plugins | Strong | dev-rel / author → X DM |
| Bito | bito.ai/ai-tools/claude-code-plugins | Strong | editorial contact form |

### Tier 2 — independent testers ("tested & ranked"): free access is the lever
| Target | URL | Fit | Contact path |
|---|---|---|---|
| Workborn | workborn.com/best-ai-tools-solopreneurs | Medium | site contact form |
| alfred_ | get-alfred.ai/blog/best-ai-tools-for-solopreneurs | Medium (small curated list → high per-slot value) | author byline / site contact |
| EntrepreneurLoop | entrepreneurloop.com/ai-tools-to-scale-solo-business | Medium | editorial contact |
| Carly | usecarly.com/blog/best-ai-tools-solopreneurs | Medium-low (long list → easier inclusion, lower per-slot weight) | site contact form |

### Tier 3 — generic "AI agent platform" lists: high weight, framing stretch
Frame Soleur as an agent *organization*, not a single-agent builder, or risk a mismatch rejection.
| Target | URL | Fit | Contact path |
|---|---|---|---|
| Marketer Milk | marketermilk.com/blog/best-ai-agent-platforms | Medium (stretch on framing) | author byline → site / X DM |
| StartupHub.ai | startuphub.ai/.../best-ai-agent-platforms-2026 | Medium | editorial tips/contact form |
| DataCamp | datacamp.com/blog/best-ai-agents | Medium-low (data-science lens) | author byline → editorial contact |

### Tier 4 — skip (competitor-owned SEO, rank own product)
Storyflow, Blink, Rocket.new, siift, smartaiforbiz, like2byte. Near-zero inclusion likelihood — they will not add a category-defining rival. Monitor only; spend no touches.

## Cadence & sequencing

- **Max 2 touches per target.** Touch 1 = personalized pitch (proves you read their list, names the specific gap, offers the org-layer entry + free access). Touch 2 = one polite follow-up only if no reply.
- **Follow-up after 7 business days.** No third touch — silence is a no. Re-approach only when they publish a new/updated list (the natural re-entry point).
- **One channel per target** (author email where listed, else the platform DM they're active on). Do not multi-channel the same person.
- **Batch Tier 1 first as a ~5–7-send pilot.** Measure reply + inclusion rate, harvest objections, refine the pitch, then release Tier 2, then Tier 3. Tier 1 wins teach how to frame the harder Tier 3 sell.
- **Stop** a target after Touch 2 unanswered. Stop the campaign when ~60% of Tier 1+2 have responded (→ maintenance/monitoring), or when two full tiers yield <10% reply after refinement (escalate to CMO — the pitch or category-fit is off).

## Message templates

### Email A — editorial / neutral lists

**Subject:** A category your {{list_title}} is missing

Hi {{first_name}},

I read {{list_title}} — the way you separate the genuinely useful from the noise is why it ranks.

One gap worth a look: every entry on that list is a single-purpose tool. Soleur is the organization layer above them. It is a Company-as-a-Service platform — 60+ agents across 8 departments (engineering, marketing, legal, finance, ops, product, sales, support) sharing one compounding knowledge base, so the marketing work knows what the legal work decided.

We are early and our community is small. I am not asking for a ranking or a slot. If the category fits how you frame the list, here is the honest version, including our own ranking of where we stand: https://soleur.ai/blog/best-ai-tools-for-solo-founders-2026/

Source-available (BSL 1.1), built on Claude Code and MCP, human-in-the-loop by design: https://soleur.ai

Happy to answer anything.

Jean

### Email B — independent tester blogs (lead with free access)

**Subject:** Free access to test Soleur for {{list_title}}

Hi {{first_name}},

You actually run the products you write about, so I want to put Soleur in your hands before you decide anything.

Full free access, no conditions. Test it, break it, and write what you find — including what falls short. We are early-stage with a small community, and honest hands-on coverage is worth more to us than a flattering mention.

Soleur is a Company-as-a-Service platform: 60+ agents across 8 departments sharing one compounding knowledge base — the organization layer above the single-purpose tools you usually review. Source-available (BSL 1.1), built on Claude Code and MCP. Every output is a starting point you approve, not a final answer.

Start here: https://soleur.ai
Our own honest ranking for context: https://soleur.ai/blog/best-ai-tools-for-solo-founders-2026/

Reply and I will set you up today.

Jean

### X / LinkedIn DM (under 60 words)

Hi {{first_name}} — your {{list_title}} covers the single-purpose tools well. Soleur is the layer above them: a Company-as-a-Service platform, 60+ agents across 8 departments on one shared knowledge base. We are early and not asking for a ranking — only a look. Honest take here: https://soleur.ai

## Guardrails

1. **Honest traction, always.** Early-stage, small community — state it plainly. The pitch is category novelty and source-available transparency, never inflated numbers. "We don't even rank ourselves #1 in our own guide" (link the live post) is the credibility hook that disarms the vendor-bias objection.
2. **Never demand a slot or rank.** Offer the entry and the differentiator; let the editor decide placement. Asking for "#3" or "above competitor X" gets you blacklisted and is editorially dishonest.
3. **Free access is the lever, not payment.** Offer full free access for hands-on testing (especially Tier 2). Never payment, affiliate, or sponsored placement (see the pre-send compliance gate).
4. **"What's your traction?" → pivot to category, not metrics.** Answer: small but real community, source-available so claims are verifiable, value is the new category (org layer above point tools); re-offer free access so they evaluate the product directly. Never fabricate or imply scale.

## Success metric

Inclusions are tracked downstream in `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md` (#3179): a successful pickup surfaces as a `cited source / URL` row (mention type `cited-with-link` or `named-no-link`) for the relevant anchor query in a future weekly run.
