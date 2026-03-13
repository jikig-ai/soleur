# Ops Directory Spec

**Issue:** #81
**Branch:** feat-ops-directory
**Date:** 2026-02-13

## Problem Statement

The Soleur plugin has zero operational components despite "operations" being planned as one of five startup domains. There's no way to track costs, manage domains, or inventory hosting -- even manually. As the project grows (website, more deployments, API subscriptions), this gap will compound.

## Goals

- Establish the `agents/operations/` directory with foundational advisory agents
- Create `knowledge-base/ops/` with structured markdown files for expense, domain, and hosting tracking
- Provide agents that can read, update, and summarize operational data
- Set conventions that future automation (purchase flows, budget controls) can build on

## Non-Goals

- Browser-automated purchasing (Phase 2)
- Semi-autonomous execution with budget controls (Phase 3)
- Integration with specific registrars or hosting providers
- Billing provider integration (Stripe, etc.)
- Legal document generation

## Functional Requirements

- **FR1:** Cost-tracker agent can read expenses.md, add entries, and summarize total monthly/annual spend
- **FR2:** Domain-manager agent can maintain domains.md with registrar, renewal date, and DNS info
- **FR3:** Hosting-advisor agent can maintain hosting.md with provider, specs, and cost info
- **FR4:** All agents produce markdown table output consistent with existing knowledge-base conventions

## Technical Requirements

- **TR1:** Agents live under `plugins/soleur/agents/operations/` (recursive discovery: `soleur:operations:<name>`)
- **TR2:** Data files live under `knowledge-base/ops/` as markdown with structured tables
- **TR3:** No new data formats (no YAML, JSON) -- markdown only
- **TR4:** Plugin version bump required (MINOR -- new agents = new capability)
