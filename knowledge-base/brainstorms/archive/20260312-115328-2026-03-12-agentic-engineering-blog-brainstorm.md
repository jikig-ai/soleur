# Brainstorm: Agentic Engineering Blog Post

**Date:** 2026-03-12
**Status:** Captured
**Approach:** C — "From Vibe Coding to Company-as-a-Service: The Three Eras of AI-Assisted Development"

## What We're Building

A thought leadership blog post that traces the evolution of AI-assisted development through three eras, positioning Soleur as the exemplar of the third era (Company-as-a-Service). The post serves dual purpose: define the competitive landscape honestly and demonstrate that Soleur is the most comprehensive compound agentic engineering system — both within engineering and across all business domains.

**Target audience:** Engineering leaders / CTOs evaluating AI strategy AND senior developers / tech leads who've hit the ceiling with current tools.

**Tone:** Manifesto + practitioner hybrid. Bold, forward-looking thought leadership with concrete examples from the Soleur knowledge base as proof points.

## Why This Approach

### The Three Eras Framework

1. **Era 1: Vibe Coding (2024-2025)** — Autocomplete, ad-hoc prompting. Karpathy coined the term Feb 2025. Works for prototypes, breaks at scale.

2. **Era 2: Agentic Engineering (2025-2026)** — Specs, compound knowledge, structured workflows. Karpathy coined this Feb 2026. Tools: Spec Kit (GitHub), OpenSpec (YC), Kiro (AWS), Every's Compound Engineering Plugin, Tessl. All engineering-focused.

3. **Era 3: Company-as-a-Service (2026+)** — Full lifecycle compounding across all business domains. Not just code — legal, marketing, sales, finance, operations, support, product. Self-improving agents, rules, and workflows.

### Why Not Just "Define Agentic Engineering"

- Term already coined and defined by Karpathy, IBM, Addy Osmani, MIT Sloan, ICSE 2026 workshop
- Crowded content space — IBM, Glide, Taskade, Medium, Addy Osmani all published definitions
- The "three eras" framing is differentiated and naturally positions Soleur as the next step

### Why Engineering Depth Matters Too

The post must demonstrate Soleur's superiority even within engineering (not just claim "we do more domains"):

1. **Self-improving rules:** AGENTS.md and constitution.md updated from learnings. The workflow itself evolves — not just documentation. Every's plugin captures learnings but doesn't feed them back into agent behavior.

2. **Branch safety / worktrees:** PreToolUse hooks enforce never committing to main, worktree isolation, conflict marker detection. No competitor has mechanical prevention at this level.

3. **Full lifecycle depth:** Brainstorm → plan → deepen → work → review (multi-agent) → compound → ship. Every has plan/work/assess/compound (4 stages). Soleur has 7+ stages with research agents at each.

### Competitive Landscape (Acknowledge then Transcend)

| Tool | Era | Strength | Gap Soleur Fills |
|------|-----|----------|-----------------|
| GitHub Copilot / Cursor / Windsurf | 1 → 2 | IDE integration, fast autocomplete | No compounding, no lifecycle, no domain awareness |
| Spec Kit (GitHub) | 2 | Spec-driven development, MIT-licensed | No compounding, just the spec layer |
| OpenSpec (YC) | 2 | Brownfield-first, specs live in code | No agent orchestration, no compounding |
| Kiro (AWS) | 2 | Enterprise backing, GovCloud, agent hooks | No compounding, no cross-domain awareness |
| Tessl | 2 | Spec registry (10K+ specs), VC funding | Closed beta, spec-as-source only |
| Every Compound Plugin | 2 | Coined "compound engineering," 29 agents, learning capture | Engineering-only, no domain leaders, no self-improving rules |
| **Soleur** | **3** | **62 agents, 57 skills, 8 domain leaders, self-improving compound loop** | **—** |

### Concrete Proof Points from the Knowledge Base

1. **Worktree-write-guard arc:** Agent edits wrong directory → work lost → learning documented → constitution rule added → PreToolUse hook makes it mechanically impossible. Four stages of permanent improvement. (Best single narrative for the post.)

2. **Plan review reducing scope 30-70%:** Three confirmed cases (#12, #46, #71) where parallel specialized reviewers converged on dramatically reducing complexity. 65 tasks became 4. 257-line plans became 55.

3. **"Hooks beat documentation":** Contrarian insight — prose rules fail because agents rationalize skipping them. Every existing hook was added after a prose rule failed.

4. **Cross-domain knowledge flow:** Brand guide informs marketing content → competitive positioning → pricing strategy. No competitor has this.

5. **By the numbers:** 421 commits, 210 documented learnings, 78 archived brainstorms, 111 archived plans, 197 archived specs.

## Key Decisions

1. **Positioning:** "Acknowledge then transcend" — name competitors directly (Spec Kit, OpenSpec, Kiro, Tessl, Every), credit their contributions, then show Soleur goes further in depth AND breadth
2. **Title direction:** "From Vibe Coding to Company-as-a-Service: The Three Eras of AI-Assisted Development" (or similar)
3. **No personal anecdote:** Don't reference the WhatsApp conversation directly. Open with the problem statement abstractly.
4. **Key differentiators (unified argument):** Full lifecycle + living knowledge base + self-improving system = compound advantage that widens over time
5. **SEO angle:** Target "compound knowledge" and "compound engineering" (low competition) rather than "agentic engineering" (crowded)
6. **Tone:** Manifesto + practitioner hybrid — bold framing with concrete repo examples as proof
7. **Brand compliance:** Never say "plugin" or "tool" — it's a platform. Never say "AI-powered." Lead with what becomes possible.

## Open Questions

1. Should we include actual code/config snippets from AGENTS.md or the compound skill to show the mechanics?
2. What's the right length? 2000-word manifesto or 4000-word deep dive?
3. Should this be gated (email capture) or fully public for SEO?
4. Do we need to fact-check Soleur's agent/skill counts against Every's before publishing? (29 agents vs 62 — need to verify Every's latest count)
5. Where does this live? soleur.ai/blog doesn't exist yet — content strategy notes zero blog infrastructure in Eleventy docs site.

## Content Strategy Alignment

This post maps to **P1.3 pillar article** in `knowledge-base/overview/content-strategy.md`:
- Topic: "Agentic Engineering: Beyond Vibe Coding"
- Target keywords: agentic engineering, compound engineering, AI coding workflow, knowledge compounding
- Planned comparison table: vibe coding vs. agentic engineering vs. compound engineering

## User Research Context

A WhatsApp conversation with an ex-colleague (2026-03-12) surfaced the exact problem this post addresses:
- Colleague's company starting AI-driven BSS project
- Boss already using AI, April workshop to evaluate in-house vs vendor
- Colleague recognizes that "vibe coding" doesn't work for enterprise-scale projects
- Key insight from the conversation: "one thing that's important for something as big as BSS is to ensure the specs and knowledge compounds"
- This validates the core thesis — enterprise teams are hitting the ceiling and looking for structured approaches

See `knowledge-base/community/user-conversations/2026-03-12-ex-colleague-bss-ai.md` for full capture.
