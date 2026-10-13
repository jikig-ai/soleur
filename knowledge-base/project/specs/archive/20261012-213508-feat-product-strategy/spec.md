# Spec: Product Strategy -- Validation-First Plan

**Status:** Draft
**Created:** 2026-03-03
**Branch:** feat-product-strategy
**Brainstorm:** [2026-03-03-product-strategy-brainstorm.md](../../brainstorms/2026-03-03-product-strategy-brainstorm.md)

---

## Problem Statement

Soleur is engineering-mature (v3.10.1, 61 agents, 55 skills) but commercially pre-seed with zero confirmed external users. The business validation document (2026-02-25) issued a PIVOT verdict: stop building features, start validating with real users. A traditional feature roadmap is premature without demand evidence. The competitive landscape is intensifying (Anthropic Cowork, Notion Custom Agents, Devin) and the window to validate the CaaS thesis is narrowing.

## Goals

- G1: Validate whether solo founders independently describe multi-domain pain (not just engineering)
- G2: Identify which non-engineering domains deliver real value to external users first
- G3: Test whether users retain and express willingness to pay for non-engineering value
- G4: Determine if Claude Code is the viable long-term distribution surface
- G5: Close 3 capability gaps (telemetry, interview framework, onboarding) needed to execute validation

## Non-Goals

- NG1: Building new features or agents (validation-first, not build-first)
- NG2: Committing to pricing (deferred until validation data exists)
- NG3: Multi-platform support (evaluate, don't build, during validation)
- NG4: Team features or enterprise positioning (solo founder focus during validation)
- NG5: Hosted web platform (on hold per issue #297 pending strategic reassessment)

## Functional Requirements

- FR1: Produce 5-7 Dogfood-Out case studies documenting Soleur's own non-engineering domain usage
- FR2: Conduct 10+ problem interviews with solo technical founders using the structured interview framework
- FR3: Run product usage test with 10 founders in split cohorts (interview-first vs. product-first)
- FR4: Measure retention and WTP after 2-week unassisted usage period
- FR5: Reach decision point at week 12 with pass/fail assessment across 5 gates

## Technical Requirements

- TR1: Implement opt-in telemetry instrumentation (install count, domain activation, session depth)
- TR2: Create customer interview analysis template (markdown or spreadsheet)
- TR3: Audit and improve onboarding flow for first-time external users
- TR4: Ensure Getting Started page is discoverable and the first action is clear
- TR5: Create "first 5 minutes" onboarding flow: install -> sync -> one domain task -> result

## Validation Gates

| Gate | Threshold | Phase |
|------|-----------|-------|
| Inbound interest | 5+ expressions of interest from content | Phase 0 (Weeks 1-4) |
| Multi-domain pain | 5/10 founders, intensity >= 3, 2+ domains in 6/10 | Phase 1 (Weeks 2-6) |
| Unprompted domain usage | 3/10 use non-engineering domain unprompted | Phase 2 (Weeks 5-10) |
| WTP | 3/10 at >= $25/month, NPS >= 7 | Phase 3 (Weeks 8-12) |
| Overall | 4/5 gates pass -> real roadmap | Phase 4 (Week 12) |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Zero inbound from Dogfood-Out content | Medium | High | Fallback to cold outreach at week 4-6 |
| Anthropic ships native CaaS features | Medium | Critical | Multi-platform architecture evaluation in parallel |
| Founders only value engineering domains | Medium | High | Pivot to engineering-depth strategy |
| Interview recruitment difficulty | Medium | Medium | Multiple channels: Discord, IndieHackers, Twitter/X |
| Telemetry implementation privacy concerns | Low | Medium | Opt-in only, aggregated data, transparent disclosure |
