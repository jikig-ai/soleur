# Brainstorm: Validate Soleur with 10 Power Users

**Date:** 2026-02-22
**Status:** Complete
**Participants:** Human, CPO, CMO

## What We're Building

A two-phase effort to validate whether Soleur's Company-as-a-Service thesis transfers beyond its creator:

1. **Vision alignment** -- Fix the disconnect between the ambitious website ("Build a Billion-Dollar Company. Alone.") and the developer-tool onboarding (README, registry listing, Getting Started all describe a dev workflow plugin). Users who install today hit a cliff between the marketing promise and the product surface.

2. **User validation** -- Test the core hypothesis with 10 solo founders: Can a single person use Soleur's multi-domain agents (engineering + marketing + legal + ops + product) to actually run a company, not just write code?

## Why This Approach

### The Discovery

During brainstorming, we found that `knowledge-base/overview/business-validation.md` fundamentally misidentifies what Soleur is. The document evaluated Soleur as a "Claude Code development workflow plugin" and recommended shrinking to 4 engineering commands -- directly contradicting the product's stated vision as a Company-as-a-Service platform with 5 business domains.

This misaligned document then propagated: the CPO agent read it as ground truth, the CMO inherited its framing, and the brainstorm's initial research was shaped by wrong premises. If left uncorrected, the same error would have poisoned the validation effort itself.

### Root Cause Analysis: Business-Validator Agent

Three structural flaws in the `business-validator` agent produced the misaligned document:

| Flaw | Description | Fix |
|------|-------------|-----|
| **No project context step** | The workflow goes from "detect existing report" directly to Gate 1 questions. It never reads the brand guide, vision page, or product positioning documents. | Add Step 0.5: Read `knowledge-base/overview/brand-guide.md` and any vision/positioning artifacts before Gate 1. |
| **No vision alignment check** | After producing the assessment, the agent never cross-references conclusions against stated product positioning. It wrote "49 agents is scope creep" without checking that the brand says "Every department." | Add a post-assessment check: compare conclusions against brand guide, flag contradictions. |
| **Gate 6 biased toward reduction** | "What is the ONE core thing?" structurally penalizes platform plays where breadth IS the thesis. | Make Gate 6 vision-aware: if the brand/vision defines breadth as the value prop, assess whether the breadth is coherent, not whether it can be reduced. |

**Propagation chain:** business-validator (wrong doc) -> CPO reads it as truth -> CMO inherits framing -> brainstorm inherits all of it.

**Additional fix needed:** CPO agent should cross-reference business-validation.md against brand-guide.md before trusting it. Currently it consumes the validation doc uncritically.

### Vision Alignment Audit

Full audit of all user-facing artifacts against the Company-as-a-Service vision:

| Artifact | Alignment | Key Issue |
|----------|-----------|-----------|
| Vision page | Aligned | True north reference |
| Brand guide | Aligned | True north reference |
| Landing page (index.njk) | Aligned | "Build a Billion-Dollar Company. Alone." |
| Root README | Mixed | "Currently: an orchestration engine for Claude Code" hedges the vision. Workflow section shows only engineering commands. |
| Plugin README | Mixed | Opens with "full AI organization" but all workflows/examples are engineering-only |
| plugin.json | Misaligned | "compound your **engineering** knowledge" -- this is the registry listing |
| Getting Started | Misaligned | All examples engineering: "Building a Feature," "Fixing a Bug," "Reviewing a PR." Zero non-engineering use cases. |
| llms.txt | Mixed | "Company-as-a-Service" but then "for software development workflows" |
| business-validation.md | Severely misaligned | Treats domains as scope creep, recommends shrinking to 4 dev commands |

**The pattern:** Website tells the platform story. Everything after install (README, registry, getting started) tells the "dev plugin" story. Non-engineering domains (marketing, legal, ops, product) have agents and skills but zero onboarding surface.

## Key Decisions

1. **Fix alignment before outreach** (sequential, not parallel). First impressions with the initial 10 users cannot be wasted on a disjointed experience. The alignment work is a prerequisite.

2. **Bring onboarding UP to vision** (not vision down to reality). The 5 domains ARE the product -- they're what makes Soleur a Company-as-a-Service platform, not just another coding assistant. Onboarding must showcase all departments.

3. **Core hypothesis: Full org value.** Can a solo founder use multi-domain agents to run a company? This is harder to test than "does the dev workflow transfer?" but it's the right question given the product thesis.

4. **Problem confirmation is the validation goal.** Success = at least 5/10 users independently describe the pain of managing everything (code, marketing, legal, ops) alone and express interest in AI departments for all of it.

5. **Mixed sourcing for the 10 users.** Claude Code Discord (~4), GitHub signal mining (~3), direct network (~3) to avoid segment bias.

6. **Fix the business-validator agent** to prevent recurrence. This is not just a one-time artifact correction -- the systemic flaws will produce wrong output again for any future validation.

## Artifacts to Fix (Alignment Phase)

### Must Fix (blocks validation)

| Artifact | Change Required |
|----------|----------------|
| `plugin.json` description | "engineering knowledge" -> "company knowledge" |
| Root `README.md` | Remove "Currently: an orchestration engine" hedging. Add domain showcase. |
| Getting Started page | Add non-engineering use cases: brand workshop, legal docs, competitive analysis, ops tracking |
| `llms.txt` | Remove "for software development workflows" -- describe the full platform |
| `business-validation.md` | Complete rewrite with correct framing |

### Must Fix (prevents recurrence)

| Artifact | Change Required |
|----------|----------------|
| `business-validator` agent | Add context step (read brand guide), add vision alignment check, make Gate 6 vision-aware |
| `cpo` agent | Cross-reference validation against brand guide before trusting it |

### Should Fix

| Artifact | Change Required |
|----------|----------------|
| Plugin `README.md` | Add non-engineering workflow examples alongside engineering ones |
| Docs landing page | Already aligned, but verify departments section matches current agent counts |

## Validation Plan (Post-Alignment)

### Phase 1: Problem Interviews (Week 1-2)

Interview 10 solo founders about their workflow pain WITHOUT showing Soleur. Key questions:

- "You're building [X] alone. How do you handle the non-code parts -- marketing, legal, operations?"
- "What's the most frustrating part of running everything yourself?"
- "Have you tried using AI for anything beyond coding? What worked? What didn't?"
- "If you could have an AI department for any part of your business, which would it be?"

**Success signal:** At least 5/10 independently describe multi-domain pain and express interest in AI handling non-engineering work.

**Kill criterion:** If fewer than 3/10 express multi-domain pain, the Company-as-a-Service thesis doesn't resonate. Reframe or pivot.

### Phase 2: Guided Onboarding (Week 3)

With the 5 users who showed strongest resonance:

- Walk them through installing Soleur on THEIR project
- Show all 5 departments, not just engineering
- Observe: which departments do they try first? Which do they ignore?
- Record friction points in onboarding

### Phase 3: Unassisted Usage (Week 4-5)

2-week period where validated users work independently:

- Track: which commands/agents do they use? Do they return for week 2?
- Track: does their knowledge-base grow?
- Track: do they use non-engineering agents?

### Success Metrics

| Metric | Threshold | Signal |
|--------|-----------|--------|
| Problem resonance | 5/10 describe multi-domain pain | Problem is real |
| Return usage | 3/5 guided users return for week 2 | Workflow transfers |
| Multi-domain adoption | 2/5 use non-engineering agents | Platform thesis holds |
| Organic referral | 1/5 recommends unprompted | Product-market fit signal |

## Open Questions

1. Should the Getting Started page be restructured as a journey (engineering first, then other departments)? Or should it present all 5 domains equally from the start?
2. What's the minimum install-to-first-value time for a non-engineering use case? (e.g., running the brand workshop on a new project)
3. Should we create a demo/sample project for users who don't have a project ready?
4. How to measure knowledge-base growth without telemetry? Self-report only?
