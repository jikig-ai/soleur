# Brainstorm: Expand Plan Phase 2.5 Domain Detection

**Date:** 2026-03-19
**Issue:** #753
**Status:** Complete
**Branch:** feat-plan-domain-gates-753

## What We're Building

Expanding the plan skill's Phase 2.5 from product/UX-only detection to a generalized domain signal sweep covering all 8 business domains (marketing, engineering, operations, product, legal, sales, finance, support). This fixes two failure modes:

1. **Bypass path** — users running `/plan` or `/one-shot` directly skip brainstorm Phase 0.5, so no domain assessment runs at all
2. **Handoff gap** — even when brainstorm runs domain assessments, findings aren't persisted in a structured way and evaporate before plan Phase 2.5

## Why This Approach

**Approach 2: Two-layer (general sweep + specialized gates)** was chosen over:

- **Approach 1 (unified sweep)** — would lose the product/UX BLOCKING tier that triggers spec-flow-analyzer and ux-design-lead for UI-heavy plans
- **Approach 3 (carry-forward only)** — fixes the handoff gap but not the bypass path; just warns instead of acting

The two-layer design preserves existing UX gate value while generalizing domain detection. It mirrors the existing enforcement tier pattern: general detection → specialized action.

## Key Decisions

1. **Both persistence AND detection (defense-in-depth).** Brainstorm documents get a structured `## Domain Assessments` section. Plan reads it first; only runs fresh detection if no brainstorm exists or findings are missing.

2. **All 8 domains via brainstorm-domain-config.md.** Single source of truth for domain detection. Adding future domains requires only a config table row — no plan skill edits.

3. **Two-layer architecture:**
   - **Layer 1 — Domain sweep:** Read brainstorm-domain-config.md, assess all 8 domains against plan content, spawn domain leader for each relevant domain
   - **Layer 2 — Specialized gates:** For domains with action-triggering tiers (currently product/UX with BLOCKING/ADVISORY/NONE and specific agent invocations), run detailed classification after the sweep

4. **All domain findings are blocking.** When any domain is detected as relevant, the plan pauses until the domain leader completes their review. This is the safest option — every cross-domain implication gets leader review before proceeding.

5. **`## UX Review` renamed to `## Domain Review`.** New heading contract with per-domain subsections. Downstream consumers need migration.

6. **Brainstorm-already-ran guard.** Plan checks for structured domain findings in the brainstorm document. If present, carries forward instead of re-running. Avoids double-routing waste.

## Open Questions

1. **Exact format of `## Domain Assessments` in brainstorm doc.** Needs to be machine-readable so plan can parse which domains were assessed and what was found. Markdown table vs. structured YAML frontmatter vs. heading-per-domain?

2. **Heading contract migration.** Need to audit all references to `## UX Review` across plan-review agents, work skill, compound skill before renaming. Breaking change if anything parses that heading.

3. **Token budget impact.** Spawning up to 8 domain leader agents in plan Phase 2.5 adds significant token consumption. In one-shot pipelines where plan runs inside a subagent, this compounds against the context ceiling. May need to batch or limit concurrent assessments.

4. **Specialized gates beyond product/UX.** Should legal get a specialized gate in v1 (e.g., auto-triggering CLO for DPA review when third-party services detected)? Or start with advisory-level domain leader assessments for all non-UX domains and graduate later?

## Capability Gaps

None identified. All 8 domain leaders and their specialist agents already exist. The brainstorm-domain-config.md already has rows for all domains with assessment questions and task prompts.

## Institutional Learnings

Key findings from the learnings archive that inform this design:

- **Supabase/Resend incident (learning #11):** Purely technical implementation shipped two new third-party processors without triggering legal or ops review. Learning #12 documents the cleanup: 4 critical and 6 high findings across legal documents. This is the exact scenario domain gates should prevent.
- **LLM semantic assessment is mandatory (learning #2):** Keyword-based detection was deliberately abandoned. Domain routing uses assessment questions interpreted by the LLM. Plan gates must follow the same pattern.
- **Token budget at capacity (learning #4):** Agent descriptions are at 2,498/2,500 words. If domain gates require new agents, existing descriptions must be trimmed first.
- **GDPR 3-doc x 2-location pattern (learning #14):** Adding a processor requires updating Privacy Policy, Data Protection Disclosure, and GDPR Policy — each in two locations (6 files). The GDPR Policy is easiest to forget.
- **Skill-enforced convention pattern (learning #7):** Three enforcement tiers: PreToolUse hooks (syntactic), skill instructions (semantic), prose rules (advisory). Domain detection is semantic — it belongs in skill instructions, not hooks.
- **Cross-domain disambiguation is bidirectional (learning #3):** Adding domain detection to plans must update disambiguation in BOTH directions.
- **Passive domain routing already exists (learning #1):** Domain leaders auto-fire via AGENTS.md behavioral rule. But this only fires on user messages during conversation — not on plan content during plan generation.

## CTO Assessment Summary

- **#1 risk:** Double-routing (brainstorm then plan) — mitigated by brainstorm-already-ran guard
- **Config drift risk:** Approach B (chosen) avoids this by reusing brainstorm-domain-config.md
- **Phase 2.5 scope change:** From "product/UX gate" to "multi-domain gate" — heading contract needs migration
- **Recommended:** Approach B with brainstorm-already-ran guard and renamed heading contract

## Repo Research Summary

- **Phase 2.5 is pure SKILL.md** — no scripts, no hooks, just instruction blocks at lines 194-244 of plan SKILL.md
- **Three-tier classification:** BLOCKING (new UI pages/flows → sequential pipeline: spec-flow-analyzer → CPO → ux-design-lead), ADVISORY (modifications to existing UI), NONE (backend/infra)
- **Output contract:** `## UX Review` section with Tier, Decision, Agents invoked, Pencil available, Findings subsections
- **One-shot inherits plan gates:** One-shot delegates to `soleur:plan` as a subagent, so Phase 2.5 fires automatically
- **Brainstorm-domain-config.md already has all 8 domains** with assessment questions and task prompts — no config additions needed
- **All domain leaders follow 3-phase contract:** Assess → Recommend and Delegate → Sharp Edges
