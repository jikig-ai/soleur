---
title: An empty market quadrant is not an opportunity by default; dogfood-then-validate before spinning out a product
date: 2026-07-07
category: product
tags: [business-validation, sourcing-decision, brainstorm, product-strategy, focus-discipline]
related: [2026-07-07-beta-conversation-capture-brainstorm, sourcing-options-canvas]
---

# Learning: empty quadrant ≠ opportunity; dogfood-then-validate before product spin-out

## Context

A `/soleur:go` brainstorm to capture beta-tester conversations (internal tooling) surfaced, via a four-way Sourcing Options Canvas (build / buy / OSS-self-host / connect-existing), that the market quadrant [turnkey CRM + native MCP + multi-tenant + resale-safe license] is **empty in 2026**. The operator reasonably read the empty quadrant as a product opportunity ("build an agent-operated open-source CRM as a second Jikigai product"). A three-lens validation panel (business-validator, competitive-intelligence, pricing-strategist) returned a unanimous **NOT-NOW**.

## Two transferable lessons

### 1. An empty market quadrant is not automatically an opportunity — it is equally evidence of unproven demand.

The quadrant was empty not because no one noticed, but because **the market is not yet ready to let an agent *operate* (vs. assist) a CRM** — 88% of agent pilots never reach production. The nearest OSS peers (Twenty, Relaticle) are AGPL + single-tenant *by choice*, and incumbents (HubSpot Breeze, Salesforce Agentforce, Attio) shipped production MCP read/write in H1 2026. "No one is in this exact corner" and "there is demand for this exact corner" are independent claims; verify the second before treating the first as a gap. Ask: *is the corner empty because it's hard-and-valuable, or because it's not-yet-wanted?*

### 2. When an internal-tool build surfaces a product idea, build the internal module and gate the spin-out on usage triggers — don't pivot the build.

The idea *emerged from* building the internal capture tool — a classic tell of a shiny tangent, not validated market pull. The disciplined resolution: **build the capability as a module of the existing product (dogfood), and gate any standalone/OSS spin-out on explicit, pre-registered triggers** rather than pre-committing a roadmap. Triggers used here: ≥3 of the first ~5 beta users *unprompted* ask to buy it standalone; parent product reaches early PMF; a structural moat emerges the incumbents can't copy. The licensing/pricing work becomes a shelf-ready playbook, not present-tense investment. Focus is the pre-PMF asset; protect it by making the product prove itself as a module first.

## Application

- Brainstorm/plan sourcing decisions: when the canvas finds an empty external quadrant, add a "why is it empty?" demand check before framing it as an opportunity.
- Product ideas born mid-build: default to internal-module + trigger-gated spin-out; route to a full validation panel before any standalone commitment. See the Sourcing Options Canvas workflow (tracked in the workflow-improvement issue) for the enumeration side of this.
