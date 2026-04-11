# Brainstorm: Named Domain Leaders

**Date:** 2026-04-10
**Issue:** #1871
**Branch:** `name-domain-leaders`
**Status:** Complete

## What We're Building

Allow users to assign custom names to their 8 domain leaders (CTO, CMO, CPO, etc.) so the AI organization feels like a real team with named members rather than anonymous role acronyms. Names display as "Alex (CTO)" format everywhere -- conversations, @-mentions, KB artifacts.

### Scope

- Custom naming for all 8 domain leaders across web platform and CLI
- Three naming surfaces: settings page, onboarding prompt, contextual nudge
- Dual @-mention syntax: both @Alex and @CTO work
- "Name (Role)" display format everywhere
- Supabase-first storage with KB sync for CLI

### Out of Scope

- Personalities (deferred to Post-MVP, tracked in #1879)
- Avatar customization
- Custom specialist agent naming (only leaders)

## Why This Approach

### Approach A: Supabase-first, KB sync (Selected)

Names stored as a Supabase user setting. Web platform reads from DB directly. Knowledge-base syncs a `team-config.md` file for the CLI plugin and for artifact readability.

**Why selected over alternatives:**

- **vs. KB-driven (B):** The web platform is the primary product post-pivot. File-based config is clunky for a web UI (user would edit a markdown file). Multi-user scenarios are awkward with file-based config.
- **vs. Dual source (C):** Brand says "your AI organization" -- implies one team identity. Divergent names across surfaces undermine that.

### Rejected Approaches

| Approach | Why Rejected |
|----------|-------------|
| B: Knowledge-base driven | CLI-first thinking; web is now the primary product. File editing for names is poor UX. |
| C: Dual source, no sync | Names diverge between surfaces. Undermines single team identity. |

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Phase 3 timing | Correctly milestoned to "Make it Sticky." CPO concern about Phase 1 blockers was based on stale data (#1878) -- Phase 1 and 2 are closed. |
| 2 | Both surfaces (web + CLI) | Cloud-first strategy but CLI remains a power-user surface. One team identity across both. |
| 3 | "Name (Role)" format always | Protects the "organization, not assistant" brand positioning (CMO). Role title always visible for clarity. |
| 4 | Three naming moments | Settings page (always available) + onboarding prompt (high adoption, skippable) + contextual nudge (earned moment after first leader interaction). |
| 5 | Both @Alex and @CTO | Natural UX. Extends `at-mention-dropdown.tsx` autocomplete to include custom names alongside role acronyms. |
| 6 | Supabase-first storage | Web is primary product. DB is natural store for user preferences. KB sync gives CLI what it needs. |
| 7 | Agent `name:` untouched | YAML frontmatter `name:` is the machine routing identifier. Custom names are a presentation layer only. No routing changes. |
| 8 | Personalities deferred | Both CTO and CMO recommend deferring. Risk of degrading output quality (CTO: personality traits conflict with Assess/Recommend/Sharp Edges contract). Revisit after Phase 4 user validation. Tracked in #1879. |

## Open Questions

| # | Question | Context |
|---|----------|---------|
| 1 | Should custom names appear in generated KB artifacts? | Brainstorm docs, specs, plans currently reference "CTO," "CMO." If they say "Alex recommended..." it's opaque to new team members. |
| 2 | What defaults for users who skip naming? | Options: keep "CTO" / system-generated names / "Your CTO." Zero-config must feel complete. |
| 3 | Supabase schema: user-level or workspace-level? | Per-user means each team member has their own names. Per-workspace means the org shares one set. Phase 3 is single-user, but schema should anticipate multi-user. |
| 4 | KB sync mechanism: manual command or automatic? | Does `/soleur:sync` pull names from Supabase to team-config.md? Or does the web platform write it on save? |
| 5 | Prompt injection: how to sanitize names? | A name like "Ignore previous instructions" would be injected into system prompts. Need input validation (length, character set). |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** Strong retention mechanism -- naming triggers the endowment effect and creates emotional switching costs aligned with Phase 3 "Make it Sticky." Always display role title alongside name to protect "organization, not assistant" brand. Social sharing surface: "My CTO Alex just audited the codebase" is organic distribution. No competitor offers personalizable AI teams.

### Engineering (CTO)

**Summary:** Recommended display-name layer via `knowledge-base/project/team-config.md` with agent `name:` fields untouched. 11 touchpoints where leader names are referenced. Prompt injection is a concern -- names in system prompts need sanitization. Token budget impact is minimal (~20 tokens per agent). `domain-leaders.ts` is the web platform's central registry.

### Product (CPO)

**Summary:** Assessment was based on stale milestone data (#1878 created to fix). With corrected data (Phase 1-2 closed), the feature is correctly milestoned to Phase 3. Tag-and-route spec already envisions per-message leader attribution. Custom names extend that naturally. Recommended deferring personalities to post-MVP validation.

## Side Discovery: CPO Stale Data Bug

During this brainstorm, the CPO assessment claimed Phase 1 had 7 unfinished P1 items. Phase 1 and 2 are both closed. Root cause: roadmap.md "Current State" section frozen since 2026-03-23, and CPO agent treats it as ground truth despite having an instruction to cross-reference with `gh api milestones`. Tracking issue: #1878.
