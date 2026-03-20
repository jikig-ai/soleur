---
title: "feat: Pillar blog post — Why Most Agentic Tools Plateau"
type: feat
date: 2026-03-12
updated: 2026-03-12
---

# Post 1: Why Most Agentic Tools Plateau (and What Compound Knowledge Changes)

[Updated 2026-03-12] Revised after plan review. Split from a single overloaded post into a two-post strategy. This plan covers Post 1 (engineering depth). Post 2 (CaaS) already exists and will be reviewed for updates.

## Overview

Write a focused blog post that demonstrates Soleur's engineering depth against direct competitors in the compound/agentic engineering space. The post argues that most agentic engineering tools plateau because they lack compound knowledge — and shows, with concrete proof, how Soleur's self-improving system breaks through that ceiling.

**Target audience:** Engineering leaders / CTOs evaluating AI strategy + senior devs who've outgrown Copilot/Cursor.

**Target length:** ~2,500 words.

**Content strategy alignment:** P1.3 pillar article. Primary keywords: "compound engineering," "agentic engineering." Secondary: "knowledge compounding," "AI coding workflow."

## Two-Post Strategy

| Post | Focus | Audience | Status |
|------|-------|----------|--------|
| **Post 1** (this plan) | Engineering depth + compound engineering comparison | Senior devs, CTOs | NEW |
| **Post 2** (existing) | Company-as-a-Service — the full-company vision | Solo founders, broader audience | REVIEW for updates |

Post 1 links to Post 2 as: "and this extends beyond engineering — read how." Post 2 gets updated to reference the Three Eras framework and link back to Post 1.

## Problem Statement

The "agentic engineering" content space is crowded with definitions but thin on evidence. No one has demonstrated, with concrete compounding examples, why some systems get better with use while others plateau. Soleur needs a post that:

1. Earns SEO on "compound engineering" and "agentic engineering"
2. Positions honestly against named competitors (Spec Kit, OpenSpec, Kiro, Tessl, Every)
3. Provides concrete proof from the knowledge base — stories, not just claims

## Proposed Solution

### Article Structure (5 sections)

**Meta title (under 60 chars):** "Why Most Agentic Engineering Tools Plateau"

**On-page H1:** "Why Most Agentic Tools Plateau — and What Compound Knowledge Changes"

#### Section 1: The Hook (~250 words)

The plateau problem: engineering teams adopt AI tools that stop getting better after week two. Session 100 starts from the same blank slate as session 1. The tools solved autocomplete. They did not solve institutional memory.

Frame the eras by **what compounds** (SpecFlow insight):
- Era 1 (vibe coding): Nothing compounds. Every session starts from zero.
- Era 2 (agentic engineering): Specs and engineering knowledge compound.
- Era 3 (compound engineering done right): Everything compounds — rules, agents, workflows, and cross-domain knowledge.

Do NOT reference the WhatsApp conversation. Keep it abstract.

#### Section 2: The Landscape — Where Most Tools Stop (~600 words)

Combine Eras 1 and 2 into a single landscape section. Brief, not a history lesson.

**Vibe coding (2024-2025):** Karpathy coined the term Feb 2025. Ad-hoc prompting, autocomplete, conversation-as-IDE. Works for prototypes. Breaks at scale — no memory, no specs, no quality gates.

**Agentic engineering (2025-2026):** Specs, structured workflows, agent orchestration. The market split into two approaches:
- **Spec-driven:** Spec Kit (GitHub), OpenSpec, Kiro (AWS), Tessl — capture intent before coding
- **Compound engineering:** Every's Compound Engineering — plan/work/assess/compound, captures learnings

**The ceiling:** These are real advances. But none solve the deeper problem: does your system actually get better with use? Can you prove it?

Use magnitude comparisons for competitor numbers ("roughly 2x the agent count") rather than exact counts that go stale (Kieran's recommendation).

"Acknowledge then transcend" tone — but framed around the user's problem, not Soleur's perspective.

#### Section 3: What Compound Knowledge Actually Looks Like (~900 words)

**The heart of the article.** This is where the post earns credibility.

Four proof points, each told as a brief story translated into universal engineering concepts (SpecFlow: avoid Soleur-internal jargon):

1. **The safety net arc** (~250 words): An AI agent edited files outside its sandbox. Two hours of work lost. The team documented the failure. A rule was added to the governance file. Then a code guardrail made the mistake mechanically impossible. Four stages: failure → documentation → rule → enforcement. The system can never make that mistake again. (Translation of the worktree-write-guard arc.)

2. **Hooks beat documentation** (~150 words): Prose rules fail because agents rationalize skipping them. Every enforcement hook in the system exists because a written rule was insufficient. This is a contrarian insight: AI doesn't follow instructions the way humans do.

3. **Plan review scope reduction** (~250 words): Use the 8-feature data table (Case Study 3 from learnings research). Across 8 features, parallel specialized reviewers reduced complexity by 30-96%. 65 tasks became 4. The system generated its own evidence that plan review should be mandatory. Frame as: "the compound system validated its own workflow gate."

4. **Self-improving instructions** (~250 words): The compound step doesn't just capture learnings — it routes insights back to the specific agent or skill that was active. Instructions literally get better with use. The governance document grew from 26 lines to 208 rules, each triggered by a real failure. Include one short config snippet (5-10 lines) as proof.

**Comparison table** (reframed around user needs, not Soleur's perspective):

| What you need | Spec-driven tools | Compound engineering | Soleur |
|---------------|------------------|---------------------|--------|
| Capture intent before coding | Yes | Partial | Yes |
| Remember learnings across sessions | No | Yes | Yes |
| Self-improving rules and guardrails | No | No | Yes |
| Mechanical prevention of known failures | No | No | Yes |
| Full lifecycle (brainstorm → ship) | No | Partial (4 stages) | Yes (7+ stages) |

#### Section 4: Beyond Engineering (~300 words)

Brief bridge to the CaaS vision. Do NOT re-explain CaaS — link to the existing article.

"If compound knowledge transforms engineering, what happens when you apply the same principle to every department?" Brief mention of 8 domain leaders, cross-domain knowledge flow. Then: "Read the full case for Company-as-a-Service →"

This section exists to connect the two posts and give the engineering-focused reader a glimpse of the bigger picture.

#### Section 5: CTA (~100 words)

Direct, brand-voice CTA. One clear action. Link to the Soleur landing page.

### FAQ Section (3 questions, for AEO/Schema markup)

1. "What is compound engineering?" — Brief definition + how it differs from agentic engineering
2. "How does knowledge compounding work in AI-assisted development?" — The compound loop: work → capture → route → enforce
3. "What is the difference between vibe coding and agentic engineering?" — Quick comparison

## P0: Fact-Check Gate (Must Complete Before Writing)

Verify with primary sources. Any claim that cannot be sourced gets softened or removed.

- [ ] Karpathy "agentic engineering" attribution — find the specific tweet/post URL (Feb 2026). If unverifiable, restructure to "the term gained traction in early 2026" without attributing to one person.
- [ ] Karpathy "vibe coding" — verify Feb 2025 tweet
- [ ] Spec Kit: verify it is a GitHub org project (not just hosted on GitHub)
- [ ] OpenSpec: verify YC batch and current status
- [ ] Kiro: verify relationship to AWS (product vs funded startup vs built on AWS)
- [ ] Tessl: verify funding status and current availability (closed beta?)
- [ ] Every Compound Plugin: verify current component counts from their README
- [ ] Soleur's own counts: run `find` on agents/skills at time of writing, cite as "as of [date]"
- [ ] All competitor descriptions fair and verifiable against their public docs

**Rule:** No naked numbers. Every quantitative claim gets a linked source or a date qualifier.

## Post 2: CaaS Article Review

Review the existing article at `plugins/soleur/docs/blog/what-is-company-as-a-service.md` for:

- [ ] Add reference to the Three Eras framework ("this is Era 3")
- [ ] Add internal link to Post 1 ("for how compound knowledge works in engineering, read...")
- [ ] Check if any content duplicated in Post 1 should be removed or refactored
- [ ] Verify all statistics are current

## Acceptance Criteria

- [ ] 5-section structure, ~2,500 words
- [ ] All competitor claims fact-checked with primary sources (P0 gate passed)
- [ ] 3+ concrete proof points from the knowledge base, told as stories
- [ ] Comparison table framed around user needs
- [ ] FAQ section with 3 questions (for AEO)
- [ ] SEO frontmatter: meta title under 60 chars, description, tags
- [ ] Internal links to CaaS article and at least 1 case study
- [ ] Builds in Eleventy
- [ ] Brand guide compliance (reference `knowledge-base/overview/brand-guide.md`)

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-12-agentic-engineering-blog-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-agentic-engineering-blog/spec.md`
- Brand guide: `knowledge-base/overview/brand-guide.md`
- Existing CaaS article: `plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- Blog data: `plugins/soleur/docs/blog/blog.json`
- Issue: #548 | Draft PR: #547

### External Sources (for fact-checking)
- Spec Kit: `github.com/github/spec-kit`
- OpenSpec: `github.com/Fission-AI/OpenSpec`
- Kiro: `kiro.dev`
- Tessl: `tessl.io`
- Every Compound Plugin: `github.com/EveryInc/compound-engineering-plugin`
- Martin Fowler SDD comparison: `martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html`
