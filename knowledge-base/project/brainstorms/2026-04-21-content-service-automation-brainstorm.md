---
title: Service Automation Launch Content
date: 2026-04-21
status: brainstorm-complete
issue: "#1944"
related: ["#1050", "#1921", "ADR-002"]
---

# Brainstorm: Service Automation Launch Content

## What We're Building

A multi-channel launch package announcing the service-automation feature (PR #1921, feature #1050) that shipped as part of Phase 3. Deliverables:

1. **Blog post** — agent-native framing, hero title candidate *"Agents That Use APIs, Not Browsers (2026)"*. Hook: *"Your agents just stopped pretending to be humans."* Architecture decisions become supporting substance, not the lead.
2. **Distribution-content file** — single markdown in `knowledge-base/marketing/distribution-content/2026-04-21-service-automation-launch.md` with the 7 channel sections (X thread, Discord, Bluesky, LinkedIn Personal, LinkedIn Company, IndieHackers, blog link), consumed by `scripts/content-publisher.sh`.
3. **OG / hero image** via `soleur:gemini-imagegen` (agent-native visual metaphor: agent icon + API endpoints, not a browser).
4. **Fact-check pass** before publish to verify every stat/quote/URL.
5. **Day-2 Hacker News Show submission** reusing the architecture-decision angle demoted from the blog hero.

## Why This Approach

The original brief (#1944) prescribed an "architecture decision story" as the hero. CMO challenged it: the engineer-inward framing rewards the build team, not the solo-founder ICP who cares that their stack provisions itself. Founder-outcome wins the blog hero; the architecture cut survives in the HN Show post and supporting social copy where technical depth lands.

Full fan-out (7 channels + day-2 HN) is justified by low baseline traffic (10-28 weekly visitors per `marketing/analytics/trend-summary.md`) — each dark channel is a real opportunity cost. The automation already exists (`scripts/content-publisher.sh` + `copywriter` + `social-distribute` + `gemini-imagegen`), so the marginal cost per channel is small.

Phase 3 milestone was due 2026-04-19; today is 2026-04-21. Waiting further is inertia, not strategy.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Hero angle | Agent-native (founder-outcome) | CMO rec; aligns with "Why Most Agentic Tools Plateau" pillar voice; ICP = solo founder, not engineer |
| Channels | Full fan-out (7) via `content-publisher.sh` + day-2 HN Show | Low baseline traffic; existing automation makes marginal cost small |
| Primary CTA | `app.soleur.ai` — "Connect your repo and let an agent provision your first service." | Brand-guide guidance (CTA away from plugin install); drives to hosted product |
| Blog title | "Agents That Use APIs, Not Browsers (2026)" | Terse, declarative, AEO-optimized, carries year per learnings |
| OG image | Yes, `soleur:gemini-imagegen` | Automatable; founder-operator expectation that announcement posts have visuals |
| Timing | Ship this week (publish by 2026-04-24) | Phase 3 due date passed; news decay risk |
| Fact-check | Yes, fact-checker agent pre-publish | Prior blog had 6 confabulations; defensive gate is cheap |
| HN Show submission | Day-2, separate | Architecture-decision angle; engineer audience; keeps blog hero clean |
| LinkedIn Personal architecture cut | Not in scope (this round) | User scoped out; day-2 HN carries the architecture angle |

### Hard Data Points (Verified)

| Claim | Value | Source |
|---|---|---|
| Automations live today | 3 (Cloudflare MCP, Stripe MCP, Plausible API) | `plugin.json` + `service-tools.ts` |
| Guided playbooks live today | 2 (Hetzner, Resend) | `service-deep-links.md` |
| BYOK providers supported | 14 | `byok.ts` + feat-service-automation plan |
| Encryption | AES-256-GCM, 12-byte IV, per-user HKDF-SHA256 key derivation | `byok.ts`, migration `009_byok_hkdf_per_user_keys.sql` |
| PR #1921 size | 1,685 additions / 42 deletions, 15 files, 17 commits | `gh pr view 1921` |
| New tests | 30 (17 agent-runner-tools + 13 service-tools) | `gh pr view 1921` |
| Total tests passing | 674 | feat-service-automation session-state |
| Brainstorm → ship | ~18 days (#1050 opened 2026-03-23, closed 2026-04-10) | `gh issue view 1050` |

### Claims to Soften (from `repo-research-analyst`)

- **"80% / 15% / 5% tier split"** → reframe as *"design allocation"* or *"target mix"*, not measured today.
- **"Eliminates SSRF risk"** → *"removes the server-side browser attack surface"*. SSRF is a category; API-first does not eliminate SSRF globally.
- **"2-4× infra cost"** → *"our CFO flagged 2-4× infra-cost risk"* — domain-review verdict, not measured.
- **"BYOK without a server touching your tokens"** → **must not claim**. Server decrypts tokens to call APIs. Use *"your tokens, encrypted at rest, used by your agents."*
- **ADR-002** is not yet on main — ships in this worktree's PR. Do not link to a main-branch ADR URL until the PR lands.

### Pre-Publish Checklist (from `learnings-researcher`)

- Grep banned terms: `grep -niE 'plugin|ai-powered|synthetic labor|soloentrepreneur|\bjust\b|\bsimply\b'` on every draft file.
- Blog post frontmatter inherits from `blog.json` — only `title`, `description`, `date`, `tags`. No `layout` or `ogType`.
- Distribution-content frontmatter schema matches `2026-03-29-pwa-installability-milestone.md` (title, type, publish_date, channels, status, pr_reference, issue_reference, roadmap_item). Each channel heading (`## Discord`, `## X/Twitter Thread`, etc.) is parsed by `scripts/content-publisher.sh` — do not invent new schema.
- UTM params on every blog link per channel.
- "Open source" prominent in H1 or first paragraph; include a one-sentence, AI-extractable definition of *service automation* near first use.
- Cross-link to the CaaS pillar and a relevant comparison post (lateral linking is a repeat audit gap).

## Open Questions

- Which 3rd comparison / pillar post should the new blog lateral-link to? Candidates: `06-why-most-agentic-tools-plateau.md`, `2026-04-17-repo-connection-launch.md`, `2026-03-24-vibe-coding-vs-agentic-engineering.md`. **Decision:** defer to copywriter during drafting; pick whichever reinforces the agent-native thesis.
- Exact publish day (Wed 2026-04-22, Thu 2026-04-23, or Fri 2026-04-24)? **Decision:** target Thu 2026-04-23 for blog + fan-out; HN Show Fri 2026-04-24.
- Who verifies the Plausible Sites API tier-gating caveat is not a misleading omission (customers on non-Enterprise plans hit 402)? **Decision:** flag in FAQ section of the blog; fact-checker confirms wording.

## Domain Assessments

**Assessed:** Marketing (CMO). Engineering research via `repo-research-analyst` and `learnings-researcher` supplied ground-truth facts and content patterns. Other domains (Engineering leadership, Operations, Product, Legal, Sales, Finance, Support) were not invoked because this is a content-only task with no architectural, ops, product-surface, legal claim, sales-deal, or financial-modelling implication beyond what is already covered by Marketing's risk flags.

### Marketing (CMO)

**Summary:** Challenge the brief's architecture-decision hero for a founder-outcome hero ("Your agents just stopped pretending to be humans"). Expand from 2 to 7 channels via existing `content-publisher.sh`, plus day-2 HN Show. Soften 5 specific claims before publish; drive CTA to `app.soleur.ai`; ship this week. Primary angle: agent-native / founder-outcome. Supporting cut for HN: architecture decision story.

## Capability Gaps

None. `soleur:copywriter`, `soleur:marketing:fact-checker`, `soleur:gemini-imagegen`, `soleur:social-distribute`, `soleur:marketing:cmo`, and `scripts/content-publisher.sh` are all available and sufficient for the pipeline.
