---
title: "feat: Pillar blog post — From Vibe Coding to Company-as-a-Service"
type: feat
date: 2026-03-12
---

# Pillar Blog Post: The Three Eras of AI-Assisted Development

## Overview

Write and publish a thought leadership blog post tracing the evolution of AI-assisted development through three eras, positioning Soleur as the exemplar of Era 3 (Company-as-a-Service). The post demonstrates Soleur's engineering depth against direct competitors AND its unique cross-domain breadth.

**Target audience:** Engineering leaders / CTOs evaluating AI strategy + senior devs who've hit the ceiling with current tools.

**Content strategy alignment:** P1.3 pillar article. Target keywords: compound engineering, knowledge compounding, agentic engineering workflow.

## Problem Statement

The "agentic engineering" content space is crowded with definitions (IBM, Addy Osmani, Glide, Taskade), but no one has articulated the full evolution from spec-driven development to compound engineering to Company-as-a-Service. Soleur needs a pillar article that:

1. Earns SEO on underserved keywords ("compound engineering", "knowledge compounding")
2. Positions honestly against named competitors (Spec Kit, OpenSpec, Kiro, Tessl, Every)
3. Provides concrete proof from the knowledge base — not just claims

## Proposed Solution

### Article Structure (Approach C: Three Eras)

**Title:** "From Vibe Coding to Company-as-a-Service: The Three Eras of AI-Assisted Development"

**Estimated length:** 3,000-3,500 words (manifesto + practitioner hybrid)

#### Section 1: The Hook (~300 words)

Open with the plateau problem: engineering teams adopt AI tools that stop getting better after week two. The autocompletion era solved the easy part. The hard part — institutional memory, cross-domain coordination, self-improvement — remains unsolved.

Do NOT reference the WhatsApp conversation. Keep it abstract.

#### Section 2: Era 1 — Vibe Coding (2024-2025) (~400 words)

- Karpathy coined the term Feb 2025
- Characteristics: ad-hoc prompting, autocomplete, conversation-as-IDE
- What it solved: prototyping speed, boilerplate elimination
- Where it breaks: no memory between sessions, no specs, no quality gates, no compounding
- Tools: GitHub Copilot, Cursor, Windsurf (category references, not a hit piece)

#### Section 3: Era 2 — Agentic Engineering (2025-2026) (~800 words)

- Karpathy coined this Feb 2026 (one year after vibe coding)
- Characteristics: specs, structured workflows, compound knowledge, agent orchestration
- Sub-categories within Era 2:
  - **Spec-driven:** Spec Kit (GitHub, MIT-licensed), OpenSpec (YC, brownfield-first), Kiro (AWS, enterprise/GovCloud), Tessl (spec registry, VC-funded)
  - **Compound engineering:** Every's Compound Engineering (plan/work/assess/compound, 29 agents, learning capture)
- "Acknowledge then transcend" tone for each competitor
- **The ceiling of Era 2:** All tools focus exclusively on engineering. None cross into legal, marketing, sales, finance, operations, support, or product strategy

#### Section 4: Even Within Engineering, Depth Matters (~600 words)

Before introducing Era 3, demonstrate Soleur's engineering superiority:

1. **Self-improving rules:** AGENTS.md and constitution.md updated from learnings. Concrete example: worktree-write-guard arc (mistake → learning → constitution rule → PreToolUse hook). Four stages of permanent improvement.

2. **Branch safety / mechanical prevention:** PreToolUse hooks enforce never committing to main, worktree isolation, conflict marker detection. "Hooks beat documentation" — every hook exists because a prose rule failed first.

3. **Full lifecycle depth:** Brainstorm → plan → deepen → work → review (multi-agent) → compound → ship. 7+ stages with research agents at each. Every has 4 stages.

4. **Plan review scope reduction:** Three confirmed cases where parallel specialized reviewers (DHH-style, technical accuracy, simplicity) reduced complexity 30-70%. 65 tasks became 4.

Include the comparison table from the brainstorm (Tool / Era / Strength / Gap Soleur Fills).

#### Section 5: Era 3 — Company-as-a-Service (2026+) (~600 words)

- The other 70% of running a company is still manual
- Link to and build on the existing CaaS article (`/blog/what-is-company-as-a-service/`)
- 8 domain leaders (CTO, CMO, CLO, COO, CPO, CFO, CRO, CCO) — not just engineering
- Cross-domain knowledge flow: brand guide → marketing content → competitive positioning → pricing strategy
- The compound effect: 421 commits, 210 learnings, 78 brainstorms, 111 plans, 197 specs
- "You decide. Agents execute. Knowledge compounds." (brand guide phrase)

#### Section 6: The Compound Advantage (~300 words)

The key insight: compound knowledge isn't a feature — it's a flywheel. Each of the three layers (full lifecycle, living KB, self-improving system) reinforces the others. The longer you use the system, the wider the gap between Soleur and tools without compounding.

Tie back to brand thesis: "The first billion-dollar company run by one person isn't science fiction. It's an engineering problem."

#### Section 7: CTA (~100 words)

Direct, brand-voice CTA. No hedging. Point to the Soleur landing page and Claude Code marketplace.

### Brand Compliance Checklist

- [ ] Never say "plugin," "tool," or "AI-powered"
- [ ] Never hedge with "might," "could," "potentially"
- [ ] Lead with what becomes possible, not what the tool does
- [ ] Use declarative statements
- [ ] Keep sentences short and punchy in marketing-adjacent sections
- [ ] Frame the founder as decision-maker, system as executor

## Technical Considerations

### Blog Infrastructure (Already Exists)

- `plugins/soleur/docs/blog/blog.json` — Eleventy data file (tags, layout, permalink, ogType)
- `plugins/soleur/docs/blog/` — Contains 6 existing articles (CaaS pillar + 5 case studies)
- Layout: `blog-post.njk`
- Permalink pattern: `blog/{{ page.fileSlug }}/index.html`
- No new infrastructure needed — just add a new `.md` file

### SEO Requirements

- Frontmatter: title, date, description, tags
- Target keywords in title, description, H2s, and first paragraph
- Internal links to CaaS article and case studies
- Open Graph tags (handled by `blog.json` ogType: article)

### Fact-Checking Requirements

Before publishing, verify:
- [ ] Every Compound Plugin agent/skill counts (claimed 29 agents — verify against their latest README)
- [ ] Karpathy dates for "vibe coding" (Feb 2025) and "agentic engineering" (Feb 2026)
- [ ] Spec Kit, OpenSpec, Kiro, Tessl feature claims match their current public documentation
- [ ] Soleur's own numbers are current (62 agents, 57 skills, 8 domains, 210 learnings, etc.)
- [ ] All competitor descriptions are fair and accurate

## Acceptance Criteria

- [ ] Article follows Three Eras framework (Vibe Coding → Agentic Engineering → CaaS)
- [ ] Names competitors directly with honest, verifiable assessment
- [ ] Includes 3+ concrete proof points from the knowledge base
- [ ] Passes brand compliance checklist (no "plugin," "tool," "AI-powered," hedging)
- [ ] SEO frontmatter complete (title, date, description, tags)
- [ ] Internal links to CaaS article and relevant case studies
- [ ] 3,000-3,500 words
- [ ] Fact-checked competitor claims
- [ ] Builds successfully in Eleventy (`npx @11ty/eleventy --serve`)

## Test Scenarios

- Given the blog post markdown, when built with Eleventy, then it renders at `/blog/three-eras-agentic-engineering/`
- Given a reader unfamiliar with Soleur, when reading Section 4, then they understand Soleur's engineering advantages with concrete examples
- Given a CTO evaluating AI strategy, when reading the comparison table, then they can assess each tool's coverage without feeling it's a biased hit piece
- Given the SEO targets, when searching "compound engineering" or "knowledge compounding," then this article appears in results within 30 days

## Success Metrics

- Ranks page 1 for "compound engineering" within 60 days
- Drives 500+ unique visitors in first month
- At least 10 social shares (X/Twitter, LinkedIn, HN)
- Internal link click-through to CaaS article > 15%

## Dependencies & Risks

**Dependencies:**
- Eleventy docs site must build and deploy (existing CI/CD handles this)
- Social distribution requires X/Twitter and Discord access (both configured)

**Risks:**
- Competitor response — naming tools directly may draw pushback. Mitigation: ensure every claim is factually verifiable and fair
- Outdated competitor data — tool features change fast. Mitigation: fact-check all claims within 48 hours of publishing
- "Three Eras" framing may feel presumptuous. Mitigation: ground each era in named, dated events (Karpathy's coinages) not our own declarations

## References & Research

### Internal References
- Brainstorm: `knowledge-base/brainstorms/2026-03-12-agentic-engineering-blog-brainstorm.md`
- Spec: `knowledge-base/specs/feat-agentic-engineering-blog/spec.md`
- User research: `knowledge-base/community/user-conversations/2026-03-12-ex-colleague-bss-ai.md`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- Content strategy: `knowledge-base/overview/content-strategy.md`
- Existing CaaS article: `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- Blog data: `plugins/soleur/docs/blog/blog.json`

### External References
- Karpathy on agentic engineering: search "Andrej Karpathy agentic engineering February 2026"
- Addy Osmani's 5 principles: `addyosmani.com/blog/agentic-engineering/`
- GitHub Spec Kit: `github.com/github/spec-kit`
- OpenSpec: `github.com/Fission-AI/OpenSpec`
- Kiro: `kiro.dev`
- Tessl: `tessl.io`
- Every Compound Plugin: `github.com/EveryInc/compound-engineering-plugin`
- Martin Fowler SDD comparison: `martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html`

### Related Work
- Issue: #548
- Draft PR: #547
