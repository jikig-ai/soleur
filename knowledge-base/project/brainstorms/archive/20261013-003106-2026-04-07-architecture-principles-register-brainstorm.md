# Architecture Principles Register

Date: 2026-04-07

## What We're Building

An Architecture Principles Register -- a flat markdown index that assigns IDs (AP-001, AP-002, ...) to the ~10-15 architectural principles currently scattered across AGENTS.md and constitution.md. Each entry links to its canonical source rather than duplicating text.

The register integrates into the existing `/soleur:architecture` skill (new `principle list` sub-command), the `architecture assess` sub-command (principle alignment check alongside NFRs), the ADR template (new `## Principle Alignment` section), and the architecture-strategist review agent (principle compliance during PR review).

Inspired by 1nce's AAC Evolution v2 article but adapted from their enterprise TOGAF approach to Soleur's solo-operator, markdown-first, agent-native context.

## Why This Approach

- **Index-only, not a standalone register.** The CTO assessment identified that a full register creates a 4th source of truth alongside AGENTS.md, constitution.md, and ADRs. An index with links to canonical sources has zero drift risk.
- **Minimal metadata.** Each entry carries: ID, title, canonical source link, enforcement tier (hook/skill/advisory), related NFR IDs. Rationale lives at the source. ~1 line per principle.
- **Architecture-only scope.** Only system design, infrastructure, and data architecture principles (~10-15 entries). Workflow rules, operational procedures, and engineering practices stay in their current homes.
- **Flat table format.** A single markdown table -- grep-friendly, agents parse it in one pass, trivial to maintain at this scale. Can upgrade to heading-per-principle format if the register grows beyond ~20 entries.
- **Full integration.** New `architecture principle list` sub-command, principle alignment in `architecture assess`, `## Principle Alignment` section in ADR template, and architecture-strategist reads the register during PR review.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Register ownership model | Index-only (links to canonical sources) | Avoids 4th source of truth, zero drift risk |
| Metadata per entry | Minimal (ID, title, source, enforcement tier, NFRs) | Rationale lives at source; agents don't need it duplicated |
| Initial scope | Architecture-only (~10-15 principles) | Workflow rules and procedures stay in AGENTS.md/constitution.md |
| File format | Flat markdown table | Sufficient for ~15 entries, grep-friendly, simple to maintain |
| Integration depth | Full (skill, assess, ADR template, review agent) | Maximizes value; all touchpoints are incremental changes |
| Principle ID scheme | AP-NNN (e.g., AP-001) | Mirrors NFR-NNN pattern for consistency |

## Open Questions

- None -- all design decisions resolved during brainstorm.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO identified the core risk of creating a 4th source of truth and recommended the index-only approach (Option A). Flagged extraction ambiguity (distinguishing principles from rules/procedures) and maintenance burden as secondary risks. Both addressed by architecture-only scope and minimal metadata decisions. No capability gaps identified.

## Candidate Principles (Initial Extraction)

Preliminary list of architectural principles to index (final list determined during implementation):

1. Terraform-only infrastructure provisioning (AGENTS.md)
2. No SSH state mutation (AGENTS.md)
3. R2 remote backend for all Terraform roots (AGENTS.md)
4. Agent-native parity (AGENTS.md / architecture-strategist)
5. Email for ops notifications, Discord for community only (AGENTS.md)
6. All knowledge in committed repo files (AGENTS.md)
7. Exhaust automation before manual steps (AGENTS.md priority chain)
8. Doppler for all secrets management (AGENTS.md)
9. Never delete user data (constitution.md)
10. Design for v2, implement for v1 (constitution.md)
11. Convention over configuration for paths (constitution.md)
12. New vendor checklist (constitution.md)
