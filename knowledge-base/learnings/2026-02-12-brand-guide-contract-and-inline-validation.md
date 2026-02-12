---
module: soleur
date: 2026-02-12
problem_type: architecture
component: marketing
tags: [brand-guide, contract, inline-validation, agent-design]
severity: medium
---

# Brand Guide Contract and Inline Validation Pattern

## Problem

Building downstream tools (discord-content skill) that depend on a structured document (brand-guide.md) produced by an upstream tool (brand-architect agent). How do you ensure the document structure is stable enough for parsing without over-engineering a schema system?

## Solution

### 1. Brand Guide Contract

Define exact `##` heading names in a contract table within the producing agent:

| Heading | Required | Purpose |
|---------|----------|---------|
| `## Identity` | Yes | Mission, values, positioning |
| `## Voice` | Yes | Tone, do's/don'ts |
| `## Visual Direction` | No | Colors, typography, imagery |
| `## Channel Notes` | Yes | Platform-specific guidance |

Downstream tools grep for these exact headings. The contract is documented in the agent that produces the document, so changes propagate through plan review.

### 2. Inline Validation Over Separate Agent

Three reviewers independently recommended against building a separate `brand-voice-reviewer` agent. The alternative: inline brand voice validation as a step within each content skill.

The discord-content skill reads `## Voice` and `## Channel Notes > ### Discord`, then validates its own draft against the do's/don'ts before presenting to the user. No cross-component invocation needed.

**Why this is better:**
- No skill-to-agent invocation complexity (skills can't directly call agents)
- Faster feedback loop (validation happens in the same context)
- Simpler dependency graph (skill only needs to read a file, not coordinate with another component)

## Key Insight

**Contracts beat schemas for human-produced documents.** A contract (table of exact headings with required/optional) is lightweight enough that an agent can follow it during generation, and downstream tools can parse it with simple grep. No YAML parsing, no JSON schema, no validation library.

**Inline validation beats separate reviewers for single-document checks.** If the validation context fits in one file (brand guide), inline it. Separate agents are for cross-cutting concerns that span multiple files or require specialized knowledge.

## Related

- [parallel-plan-review-catches-overengineering.md](./2026-02-06-parallel-plan-review-catches-overengineering.md) - Third case: brand marketing scope reduction
