# Brainstorm: alirezarezvani/claude-skills Comparative Audit

**Date:** 2026-04-21
**Participants:** Founder, CPO, CMO, CTO, Explore (external deep-scan), repo-research-analyst (implicit from Soleur inventory knowledge)
**Status:** Complete; action items filed as GitHub issues; work scoped for future planning cycles.

## What We're Building

A **comparative audit** of `https://github.com/alirezarezvani/claude-skills` (MIT, v2.0.0, 12.2k stars, 235+ skills, 305 stdlib Python CLI tools, 29 commands, 3 personas) against the Soleur plugin, producing:

1. **Three architectural meta-pattern extractions** applied to existing Soleur skills (security scan, promotion loop, orchestration lanes).
2. **One new sub-mode** in an existing skill (`peer-plugin-audit` inside `competitive-analysis`) to productize this audit workflow for future peer repos surfaced by weekly CI.
3. **Five new skill/agent candidates** (tech-debt-tracker, mcp-server-builder, incident-commander, code-to-prd, karpathy-check) — each filtered through CPO's founder-outcome gate before building.
4. **CMO updates** to the competitive-intelligence report (new "Skill Library" tier) and one category-creation content piece.
5. **One explicit deferral**: RA/QM regulatory skills (FDA 510k, MDR 745, ISO 27001, GDPR specialist, CAPA) parked to "Soleur for regulated founders" ICP expansion, Post-MVP milestone.

**NOT building**: a 235-skill wholesale port, a multi-tool (Cursor/Aider/Windsurf) converter, or marketing content that compares head-to-head skill counts.

## Why This Approach

**Closeness premise challenged.** The weekly CI report surfaced `alirezarezvani/claude-skills` as "closest to Soleur." That framing is wrong: their repo is a portable skill library (converts to 12 AI tools, standalone skills, no workflow); Soleur is an opinionated workflow plugin (brainstorm → plan → implement → review → compound → ship with compounding KB and 8 domain leaders). They are complementary, not competitive. Our true closest competitors per our own CI report remain Anthropic Cowork/KAIROS, Polsia, and Cursor.

However, their repo is MIT-licensed, highly-starred, and has genuinely surveyed a breadth Soleur has not — so it's worth mining for gaps and patterns **without** treating their skill count as a parity target.

**Three domain-leader assessments converged on the same answer**: extract patterns, don't port in bulk.

- **CPO**: Priority ranking is (c) improve existing > (d) selective architectural meta > (a) selective engineering ports > (b) regulatory skills are off-strategy. No skill ships without naming the founder outcome it unblocks. Skill-count inflation damages `/soleur:help` discoverability faster than any single port helps.
- **CMO**: Add a "Skill Library" tier to the CI report (the category is structurally different from Tier 3 SaaS competitors). Publish only category-creation content ("workflow plugin vs. skill library"), never head-to-head count posts. Bundle any ports into ICP-expansion launches, not individual skill-add announcements. MIT attribution belongs in skill file headers, not launch copy.
- **CTO**: Three meta-pattern extractions + targeted 5-10 skill shortlist only. Reject the multi-tool converter outright (loses agent orchestration and KB — ships ~20% of the skill's value). Token budget math: 68 skills live under the 1800-word cap; 30 new descriptions would require existing-skill compression.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Do not do a wholesale 235-skill port | Off-strategy (CPO), dilutes positioning (CMO), blows token budgets (CTO). |
| 2 | Extract `skill-security-auditor` pattern into `skill-creator` + `agent-finder` rather than importing as a new skill | Closes a real supply-chain gap (`agent-finder` surfaces community skills with zero vetting today); single Soleur-native implementation instead of orphan skill. |
| 3 | Extract `self-improving-agent` promotion loop into `compound` + `compound-capture` | Operationalizes `wg-every-session-error-must-produce-either` which is today enforced by human vigilance. Learnings repeated N times should auto-propose AGENTS.md rule / skill edit. |
| 4 | Name orchestration lanes (Solo Sprint, Domain Deep-Dive, Multi-Agent Handoff, Skill Chain) in `brainstorm` + `work` | We do these implicitly; naming them makes domain-leader routing deterministic. |
| 5 | Productize this audit via a new `peer-plugin-audit` sub-mode inside the existing `competitive-analysis` skill | Keeps this workflow reusable without adding a net-new skill. Feeds the new CI "Skill Library" tier directly. Rejected alternatives: (a) new dedicated skill (surface-area inflation), (b) extend `functional-discovery`/`agent-finder` (blurs their /plan-scoped contracts). |
| 6 | Build 5 targeted new components: `tech-debt-tracker` (agent, trending ledger), `mcp-server-builder` (skill), `incident-commander` (skill/agent TBD), `code-to-prd` (skill), `karpathy-check` (integrates into `code-simplicity-reviewer` — TBD whether skill or command) | Each fills a confirmed Soleur gap that serves the current solo-founder/SaaS ICP. Each gets its own brainstorm with domain-leader assessment before implementation. |
| 7 | RA/QM skills (FDA 510k, MDR 745, ISO 27001 auditor, GDPR specialist, CAPA coordinator) deferred as a single "Post-MVP / Later" issue | Off-strategy for current ICP. Revisit when Soleur serves regulated-industry customers. |
| 8 | Reject multi-tool converter (Claude Code → Cursor/Aider/Windsurf) | Loses agent orchestration + KB integration; ships ~20% of skill value; not our distribution strategy. |
| 9 | Add new "Skill Library" tier to `knowledge-base/product/competitive-intelligence.md` with `alirezarezvani/claude-skills` as the first entry | Currently invisible in the CI report despite 12.2k stars. Category-correct tier, not forced into Tier 3. |
| 10 | Commission one category-creation content piece ("Skill libraries vs. workflow plugins") via copywriter + content-writer | Reframes the comparison axis on our terms without head-to-head count cites. |

## Open Questions

- For each of the 5 new-skill candidates, what is the specific founder outcome it unblocks this quarter? (CPO's gate — answered during each candidate's own brainstorm.)
- For `karpathy-check`: does this extend `code-simplicity-reviewer` agent or become a standalone skill invoked at `/review` time? (Decide during plan phase.)
- For `incident-commander`: should it be an agent (orchestrates post-mortem via domain leaders) or a skill (templated SEV classification + PIR generation)? (Decide during brainstorm.)
- For the promotion loop in `compound`: what's the threshold N for auto-promotion (3 repeats? 5?)? Manual confirmation gate before applying a rule edit, or opt-in auto-apply? (Plan decision.)
- Does the `peer-plugin-audit` sub-mode also run on any GitHub URL the user provides ad-hoc, or only on URLs already tracked in the CI report? (Sub-mode spec decision.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Off-strategy to port at scale from a portable-skill-library competitor; our moat is workflow orchestration and compounding knowledge, not skill count. Selective absorption of patterns is net-positive if framed as "inspired by," not "ported from." Priority: (c) improve existing > (d) architectural meta > (a) targeted engineering > (b) regulatory (deferred).

### Engineering (CTO)

**Summary:** Three meta-patterns worth extracting into existing Soleur skills (security auditor, promotion loop, orchestration lanes). Skill ports require full rewrite (their stdlib-Python-CLI architecture is incompatible with our bash + Skill-tool + agent orchestration). Reject multi-tool converter. Token budget permits 10-15 new skills max before compression is required. Per-skill integration cost is ~0.5-1 day in Soleur vs. minutes in their model.

### Marketing (CMO)

**Summary:** Add new "Skill Library" tier to CI report — the category is structurally different and warrants its own frame. Publish category-creation content only ("workflow plugin vs. skill library"), never head-to-head count posts. Bundle ports into ICP-expansion launches, never skill-by-skill announcements. MIT attribution in skill headers, not launch copy.

## Capability Gaps

No Soleur capability gaps blocking this work itself. CPO, CMO, CTO, `competitive-analysis`, `skill-creator`, `compound`, and `architecture-strategist` cover the execution surface.

## Attribution

External repo: `https://github.com/alirezarezvani/claude-skills` — MIT License, Copyright (c) 2025 Alireza Rezvani. All patterns and ideas referenced here are inspirations for Soleur-native implementations; no verbatim file copies are intended. When specific code or prose is adapted, attribution header required in the target Soleur skill file per CMO guidance.
