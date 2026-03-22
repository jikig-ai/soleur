---
feature: product-roadmap
issue: 675
status: draft
created: 2026-03-22
---

# Product Roadmap Skill Specification

## Problem Statement

After validating a business idea (via business-validator), founders have no structured way to define what to build and in what order. The CPO agent provides advisory assessments but lacks a workflow for creating and operationalizing a product roadmap. This is the most critical capability gap in the product domain — every Soleur user who has validated their idea needs it next.

## Goals

- G1: Provide a CPO-grade interactive workshop for defining product roadmaps
- G2: Synthesize full knowledge-base context (validation, competitive intel, brand, specs, issues) before engaging the founder
- G3: Output a strategic roadmap document (`knowledge-base/product/roadmap.md`) with phases, objectives, and rationale
- G4: Operationalize the roadmap by creating GitHub milestones and assigning issues
- G5: Work for any Soleur user, not just Soleur itself — discover from KB, fill gaps with questions

## Non-Goals

- NG1: Automated weekly status reports from milestones (future enhancement)
- NG2: GitHub Projects V2 GraphQL integration
- NG3: Cross-repo roadmap tracking
- NG4: Scheduled workflow for periodic review reminders
- NG5: New specialist agent — the CPO handles this with the skill providing the workflow

## Functional Requirements

- FR1: Skill reads knowledge-base artifacts (brand guide, business validation, competitive intelligence, specs, existing issues/milestones) on startup
- FR2: Skill identifies missing context and asks targeted questions to fill gaps (company stage, users, goals, constraints)
- FR3: Skill optionally spawns research agents (competitive-intelligence, business-validator) for additional context
- FR4: Skill runs a multi-turn dialogue workshop with the founder covering strategic themes, phase definitions, feature prioritization, and success criteria
- FR5: Skill generates `knowledge-base/product/roadmap.md` with phases, objectives, rationale, and success metrics
- FR6: Skill creates GitHub milestones for each roadmap phase (idempotent — skips existing milestones)
- FR7: Skill assigns existing GitHub issues to milestones based on workshop decisions
- FR8: Skill supports `$ARGUMENTS` bypass for headless/pipeline callers

## Technical Requirements

- TR1: Skill file at `plugins/soleur/skills/product-roadmap/SKILL.md` with standard YAML frontmatter
- TR2: No new agent — CPO and specialist agents spawned via Task tool as needed
- TR3: GitHub Milestones via REST API (`gh api repos/{owner}/{repo}/milestones`)
- TR4: Registration in `docs/_data/skills.js` under "Review & Planning" category
- TR5: Skill descriptions in third person per compliance checklist
- TR6: All reference files linked as proper markdown links, not backtick references
- TR7: New `knowledge-base/product/` directory created as output location
