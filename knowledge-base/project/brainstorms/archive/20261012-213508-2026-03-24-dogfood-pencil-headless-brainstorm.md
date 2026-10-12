---
date: 2026-03-24
topic: Dogfood pencil.dev headless CLI integration via pricing page design
status: accepted
issue: "#656"
---

# Dogfood Pencil Headless CLI Integration

## What We're Building

A full dogfooding session of the pencil.dev headless CLI integration (merged in PR #1087) by designing the soleur.ai pricing page (#656). The session serves dual purpose: validating the integration works end-to-end AND producing a real deliverable (pricing page wireframe + HTML implementation + visual assets).

## Why This Approach

The headless CLI integration added 16 MCP tools via a Node.js adapter bridging `pencil interactive` REPL to Claude Code. It has known sharp edges (REPL parsing, text node gotchas, auth requirements) and an unchecked acceptance test (get_screenshot with tracked node ID). Dogfooding against a real deliverable surfaces integration issues that synthetic tests miss while producing useful output.

## Key Decisions

1. **Deliverable:** Pricing page for soleur.ai (#656) — exercises layout, text, comparison tables, asset export
2. **Two-pass design:** Mid-fi wireframe in .pen first (brand colors, real section headers), then HTML/Eleventy implementation, then pencil for asset generation (OG image, comparison graphic)
3. **Sequential pipeline:** Register MCP → load guidelines → wireframe → screenshot review → HTML → assets → batch-file issues
4. **Bug handling:** Fix inline if <5 min, otherwise note and continue. Batch-create GitHub issues at session end with summary
5. **Visual fidelity:** Mid-fi with brand colors — real headers, brand palette, rough component shapes

## Pricing Page Requirements (from #656)

- Highlight free/open-source model as primary message
- Explain cost structure (Soleur free; users pay Claude API/subscription)
- Competitor comparison table: Cursor $20/mo, Devin $20/mo, GitHub Copilot $10-39/mo
- FAQPage schema for pricing questions
- Navigation links from homepage
- OG/Twitter meta tags

## Dogfooding Test Matrix

### Happy Path (must work)

- [x] `pencil-setup` skill registers headless MCP successfully
- [x] `get_guidelines("landing-page")` returns useful design guidance
- [x] `batch_design` creates page sections (hero, comparison table, FAQ)
- [x] `get_screenshot` captures the design for visual review
- [x] `export_nodes` generates PNG/WebP assets

### Edge Cases (stress test)

- [x] Text nodes with `fill` (not `textColor`) render correctly
- [ ] Auto-sized text width workaround (two-pass measure-then-position) — used `alignItems:"center"` on parent frame instead
- [ ] Concurrent tool calls serialize properly via command queue — not tested
- [ ] Crash recovery: adapter restarts after simulated failure — not tested
- [ ] `open_document` switches between .pen files cleanly — not tested
- [x] `get_screenshot` with tracked node ID from prior `batch_design`

### Agent Workflow (UX validation)

- [ ] ux-design-lead agent can use headless mode for design session — not tested this session
- [x] Brand guide colors translate to pencil design variables
- [x] Iterative design loop (design → screenshot → feedback → redesign) is productive

## Open Questions

- How stable is the `pencil interactive` REPL format across CLI versions?
- What's the failure mode when auth token expires mid-session?
- Can the adapter handle large designs (50+ nodes) without timeouts?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The MCP adapter's REPL parsing is the primary fragility point. Dogfooding should specifically test: command serialization under concurrent tool calls, crash recovery behavior, and the 30-second timeout adequacy for complex batch_design operations. The text node two-pass workflow is an ergonomics concern that may need SDK-level abstraction.

### Product (CPO)

**Summary:** The pricing page is an ideal dogfooding target because it exercises layout primitives (sections, tables, typography) that are common across all design tasks. Success here validates the headless CLI as a viable design workflow. Key validation: can the ux-design-lead agent produce artifacts that are useful for HTML implementation, not just pretty pictures?

### Marketing (CMO)

**Summary:** The headless CLI npm package has NOT been publicly announced by the pencil.dev founder. No public marketing content should reference the headless CLI or package name. The pricing page itself (#656) is a P1 marketing priority — if the dogfooding session produces it, that's a direct marketing win. Ensure the pricing page follows the brand guide for voice, palette, and competitive positioning.
