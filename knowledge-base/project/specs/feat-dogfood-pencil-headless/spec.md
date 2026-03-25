---
title: Dogfood Pencil Headless CLI via Pricing Page
issue: 656
branch: dogfood-pencil-headless
status: draft
created: 2026-03-24
---

# Dogfood Pencil Headless CLI via Pricing Page

## Problem Statement

The pencil.dev headless CLI integration (PR #1087) merged without end-to-end validation against a real design task. Known sharp edges (REPL parsing, text node gotchas, auth requirements) and an unchecked acceptance test (get_screenshot with tracked node ID) remain unverified. Meanwhile, the pricing page (#656) is a P1 marketing gap with no transactional-intent content on soleur.ai.

## Goals

1. Validate the pencil headless CLI integration works end-to-end for a real design task
2. Produce a mid-fi wireframe of the pricing page in .pen format
3. Implement the pricing page as HTML/Eleventy from the wireframe
4. Generate visual assets (OG image, comparison graphic) via pencil export
5. Surface and document integration bugs with GitHub issues

## Non-Goals

- Production-ready visual polish (mid-fi is sufficient for wireframe pass)
- Testing all 4 tiers of the detection cascade (headless CLI only)
- Public marketing content referencing the headless CLI (pre-announcement)

## Functional Requirements

- **FR1:** Register pencil headless MCP via pencil-setup skill
- **FR2:** Create pricing page wireframe in .pen with brand colors and real section headers
- **FR3:** Wireframe includes: hero section, cost explanation, competitor comparison table, FAQ section
- **FR4:** Screenshot wireframe for visual review using get_screenshot
- **FR5:** Implement pricing page as /pages/pricing.html with Eleventy templates
- **FR6:** Generate OG image and comparison graphic via export_nodes
- **FR7:** Include FAQPage schema and OG/Twitter meta tags
- **FR8:** Batch-file all integration issues encountered with summary

## Technical Requirements

- **TR1:** Pencil headless MCP registered at user scope via `claude mcp add`
- **TR2:** Node.js >=22.9.0 available for MCP adapter
- **TR3:** Pencil CLI authenticated (`pencil login` or `PENCIL_CLI_KEY`)
- **TR4:** Brand guide colors mapped to pencil design variables via set_variables
- **TR5:** All inline fixes committed to feature branch
- **TR6:** Integration issues filed with reproduction steps and adapter log context

## Acceptance Criteria

- [ ] Pencil headless MCP is registered and responding to tool calls
- [ ] Pricing page wireframe exists as .pen file with brand styling
- [ ] Screenshot of wireframe reviewed and approved
- [ ] HTML pricing page exists at /pages/pricing.html
- [ ] Competitor comparison table renders correctly
- [ ] FAQPage schema validates
- [ ] OG image generated via pencil export
- [ ] All encountered integration issues filed on GitHub
