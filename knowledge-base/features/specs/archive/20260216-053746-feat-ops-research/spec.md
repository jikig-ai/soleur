# Spec: ops-research Agent

**Date:** 2026-02-14
**Brainstorm:** `knowledge-base/brainstorms/2026-02-14-ops-research-agent-brainstorm.md`
**Branch:** `feat-ops-research`

## Problem Statement

The ops-advisor agent tracks expenses and domains but cannot research new options. Users must manually research domains, hosting, and tools before the ops-advisor can record them. There is no structured workflow for comparing providers, checking availability, or navigating to checkout.

## Goals

- G1: Enable structured research for domains, hosting, tools/SaaS, and cost optimization
- G2: Use browser automation to check live availability and pricing
- G3: Navigate to checkout but require human confirmation before purchase
- G4: Auto-invoke ops-advisor to record purchases after confirmation

## Non-Goals

- Autonomous purchasing (v2 with budget system)
- Cross-domain research (marketing tools, engineering tools outside ops scope)
- Real-time price monitoring or alerting

## Functional Requirements

- FR1: Read existing `knowledge-base/ops/` data before making recommendations
- FR2: Use WebSearch and WebFetch for initial research and comparison
- FR3: Present structured comparison tables with recommendations
- FR4: Use agent-browser to check live availability and navigate to checkout
- FR5: Stop before purchase and require explicit user confirmation
- FR6: After confirmed purchase, invoke ops-advisor to record the transaction

## Technical Requirements

- TR1: Agent file at `plugins/soleur/agents/operations/ops-research.md`
- TR2: Follow existing agent conventions (YAML frontmatter with examples)
- TR3: Embed only sharp edges in prompt (not general research knowledge)
- TR4: Use agent-browser CLI commands (not direct MCP tools)
