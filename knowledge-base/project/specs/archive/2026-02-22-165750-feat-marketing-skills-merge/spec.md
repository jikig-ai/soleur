---
title: Merge marketingskills into Soleur
feature: feat-marketing-skills-merge
date: 2026-02-20
issue: "#174"
---

# Spec: Merge marketingskills into Soleur

## Problem Statement

Soleur has 4 marketing agents and 3 growth skills covering content strategy, SEO/AEO, brand identity, and community engagement. This covers ~25% of what a full marketing team does. The remaining 75% (CRO, paid ads, pricing, retention, referrals, launch strategy, measurement) has no coverage. The coreyhaines31/marketingskills plugin (MIT, 29 skills) covers these gaps but without lifecycle integration.

## Goals

- G1: Build a CMO agent that orchestrates the full marketing function
- G2: Adopt and integrate ~22 new marketing capabilities as agents
- G3: Expand 3 existing agents to absorb overlapping capabilities
- G4: Achieve full lifecycle integration (brand guide, knowledge-base output) across all agents
- G5: Ship as a single release

## Non-Goals

- NG1: Building a marketing automation platform (no scheduling, no campaign execution)
- NG2: Creating user-facing skills for every agent (CMO is the entry point)
- NG3: Competing with marketingskills on general-purpose appeal (we're opinionated)
- NG4: Automated social posting or ad buying (analysis and strategy only)

## Functional Requirements

- FR1: CMO agent assesses marketing posture across all channels
- FR2: CMO agent creates unified marketing strategy and delegates to specialized agents
- FR3: Each marketing agent reads brand guide when available
- FR4: Each marketing agent produces structured output (tables, matrices, prioritized lists)
- FR5: Subdomain folders organize agents by marketing function
- FR6: High-overlap capabilities merge into existing agents, not duplicate

## Technical Requirements

- TR1: Sharp-edges-only prompt design (only instructions Claude gets wrong)
- TR2: Agent frontmatter includes model, name, description with examples
- TR3: Subdomain folder structure under agents/marketing/
- TR4: MIT license attribution for adopted material
- TR5: Version bump (MINOR), CHANGELOG, README updates
