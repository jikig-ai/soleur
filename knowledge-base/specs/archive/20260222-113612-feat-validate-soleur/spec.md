# Spec: Validate Soleur with 10 Power Users

## Problem Statement

Soleur has zero confirmed external users. The product has been built in isolation with 50 agents across 5 business domains, but the onboarding surface (README, registry listing, Getting Started) presents it as a development workflow plugin, contradicting the Company-as-a-Service vision. The business-validator agent produced a misaligned assessment that treated the multi-domain breadth as scope creep rather than as the core value proposition, and this error propagated through the CPO and CMO assessments.

Before inviting external users, the product artifacts must tell a coherent story, the agent that evaluates product-market fit must be fixed, and a structured validation plan must be executed.

## Goals

- G1: Align all user-facing artifacts with the Company-as-a-Service vision
- G2: Fix the business-validator agent to prevent context-blind assessments
- G3: Fix the CPO agent to cross-reference validation against brand positioning
- G4: Rewrite business-validation.md with the correct framing
- G5: Execute a structured validation with 10 solo founders testing the full-org hypothesis

## Non-Goals

- Building new features or agents (the product is feature-complete for validation)
- Launching publicly on HackerNews or Product Hunt (validation first, launch after)
- Adding usage telemetry or analytics to the plugin
- Monetization planning (deferred until adoption signal)
- Redesigning the website (the landing page is already aligned)

## Functional Requirements

### FR1: Vision Alignment

- FR1.1: Update `plugin.json` description to reference company knowledge, not engineering knowledge
- FR1.2: Rewrite root `README.md` to remove "orchestration engine for Claude Code" hedging and showcase all 5 domains
- FR1.3: Update Getting Started page with non-engineering use cases (brand workshop, legal generation, competitive analysis, ops tracking)
- FR1.4: Update `llms.txt` to describe the full platform, not just software development workflows
- FR1.5: Update plugin `README.md` with non-engineering workflow examples

### FR2: Agent Fixes

- FR2.1: Add "Step 0.5: Read Project Identity" to business-validator agent (read brand guide and vision before Gate 1)
- FR2.2: Add post-assessment vision alignment check to business-validator (compare conclusions against brand positioning, flag contradictions)
- FR2.3: Make Gate 6 (Minimum Viable Scope) vision-aware (if breadth IS the thesis, assess coherence not reduction)
- FR2.4: Update CPO agent to cross-reference business-validation.md against brand-guide.md before consuming it

### FR3: Business Validation Rewrite

- FR3.1: Rewrite `knowledge-base/overview/business-validation.md` evaluating Soleur as the Company-as-a-Service platform
- FR3.2: Competitive landscape must compare against AI agent workforce platforms, not just Claude Code workflow plugins
- FR3.3: Minimum Viable Scope must recognize that 5 domains IS the MVP for a Company-as-a-Service platform

### FR4: User Validation Execution

- FR4.1: Source 10 solo founders from mixed channels (Discord ~4, GitHub ~3, network ~3)
- FR4.2: Conduct problem interviews (no demo) testing multi-domain pain
- FR4.3: Filter to 5 users showing strongest resonance for guided onboarding
- FR4.4: Observe 2-week unassisted usage period
- FR4.5: Define and apply kill criteria before starting outreach

## Technical Requirements

- TR1: All artifact changes must pass existing CI checks (markdownlint, SEO validation, component tests)
- TR2: Agent changes must maintain cumulative description word count under 2500
- TR3: Business-validator changes must not break the 6-gate contract or heading structure
- TR4: Version bump required for any changes under `plugins/soleur/`

## Test Scenarios

### Given a new user visits the root README
**When** they read the "What is Soleur?" section
**Then** they should understand it covers 5 business domains, not just engineering

### Given a new user installs via the registry
**When** they read the plugin description
**Then** it should reference company knowledge, not engineering knowledge

### Given the business-validator runs on a project with a brand guide
**When** it reaches Gate 1 (Problem)
**Then** it should have already read the brand guide and vision artifacts

### Given the business-validator produces an assessment
**When** its conclusions contradict the brand guide
**Then** it should flag the contradiction explicitly in the document

### Given the CPO reads a business-validation.md
**When** the validation's framing contradicts brand-guide.md
**Then** the CPO should flag the misalignment rather than consuming it uncritically

### Given the Getting Started page is loaded
**When** a new user reads Common Workflows
**Then** they should see non-engineering use cases alongside engineering ones
