---
title: "feat: NFR register per-container and per-link applicability with evidence"
type: feat
date: 2026-03-27
issue: "#1206"
semver: patch
---

# feat: NFR register per-container and per-link applicability with evidence

## Overview

Restructure the NFR register (`knowledge-base/engineering/architecture/nfr-register.md`) from flat system-wide tables to per-NFR sections with container/link applicability matrices. Each NFR will map to specific C4 containers and container-to-container links, with evidence of how enforcement works at each point.

The `architecture assess` sub-command will also be updated to produce per-container assessments rather than system-wide summaries.

## Problem Statement / Motivation

The current NFR register treats every requirement as a single system-wide boolean (Implemented / Partial / Not Implemented). This masks important nuances:

- **NFR-026 (Encryption In-Transit):** Implemented differently per link -- Cloudflare Tunnel for webapp-to-API, HTTPS SDK for engine-to-Anthropic, TLS for engine-to-Supabase. The flat "Implemented" status hides these distinct enforcement mechanisms.
- **NFR-007 (Circuit Breaker):** Relevant for engine-to-Anthropic but irrelevant for webapp-to-Supabase. The flat "Not Implemented" implies a gap across all links, when only some need it.
- **NFR-001 (Logging):** Different maturity per container -- Docker logs for the engine, Next.js console for the webapp, grammy logging for the Telegram bridge. The flat "Partial" gives no visibility into which containers need work.

Without per-container granularity, the `assess` sub-command cannot tell implementers which containers a new feature actually impacts, and ADR NFR Impacts sections cannot reference specific enforcement points.

## Proposed Solution

### 1. Restructure `nfr-register.md`

Replace the current flat tables (one row per NFR within category tables) with per-NFR sections, each containing a container/link applicability matrix:

```markdown
### NFR-026: Encryption In-Transit

**Category:** Security
**System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|---------------|-----------|--------|-------------|----------|
| Web App -> API | Yes | Implemented | Cloudflare Tunnel | TLS terminated at Cloudflare edge |
| API -> CLI Engine | Yes | Implemented | WebSocket WSS | Internal network, WSS protocol |
| CLI Engine -> Anthropic | Yes | Implemented | HTTPS | SDK enforces HTTPS |
| CLI Engine -> Supabase | Yes | Implemented | TLS | Supabase requires TLS connections |
| Telegram Bot -> Telegram API | Yes | Implemented | HTTPS | grammy SDK enforces HTTPS |
```

The system-level status becomes a derived rollup: if all applicable containers/links are Implemented, system-level is Implemented; if any are Partial or Not Implemented, system-level reflects the worst case.

### 2. Source containers and links from the C4 container diagram

The container/link inventory comes from `knowledge-base/engineering/architecture/diagrams/container.md`. The containers are:

**Containers:**

- Dashboard (React, Next.js)
- API Routes (Next.js API)
- Auth Module (Supabase Auth)
- Agent Runtime (Claude Code)
- Skill Loader (Plugin Discovery)
- Hook Engine (PreToolUse Guards)
- Skills (Markdown SKILL.md)
- Agents (Markdown Agent Defs)
- Knowledge Base (Markdown + YAML)
- Telegram Bot (grammy, TypeScript)
- Supabase PostgreSQL
- Cloudflare Tunnel (cloudflared)
- Compute (Hetzner Cloud)

**External Systems:**

- Anthropic API
- GitHub
- Cloudflare
- Doppler
- Stripe
- Plausible
- Telegram Bot API

**Key Links (from `Rel()` declarations):**

- Dashboard -> API Routes (HTTPS)
- API Routes -> Agent Runtime (WebSocket)
- Agent Runtime -> Skill Loader (File I/O)
- Agent Runtime -> Supabase (HTTPS)
- Agent Runtime -> Anthropic (HTTPS)
- Agent Runtime -> GitHub (HTTPS/SSH)
- API Routes -> Supabase (HTTPS)
- API Routes -> Stripe (HTTPS)
- Dashboard -> Plausible (JS snippet)
- Auth Module -> Supabase (HTTPS)
- Telegram Bot -> Telegram API (grammy SDK)
- Telegram Bot -> Agent Runtime (Subprocess)
- Cloudflare Tunnel -> API Routes (HTTPS)
- Doppler -> Agent Runtime (CLI)

Not every NFR applies to every container or link. The applicability column captures this -- "No" or omission means the NFR is irrelevant for that container/link, avoiding noise.

### 3. Update `architecture assess` sub-command

Currently, the assess sub-command outputs a flat table. After this change, it will:

1. Accept an optional `--container <name>` argument to scope the assessment to a single container and its links
2. When assessing a feature, map the feature to affected containers/links (using the C4 diagram)
3. Output per-container NFR status for only the affected containers
4. Include evidence gaps (containers/links with "Applicable: Yes" but no evidence documented)

### 4. Update `nfr-reference.md`

Update the reference guide to document the new per-container structure and how to reference specific container/link rows in ADR NFR Impacts sections.

## Technical Considerations

- **File size:** The register will grow from ~94 lines to approximately 300-400 lines. Each of the 30 NFRs gets its own section with a table. NFRs where only 1-2 containers apply will have small tables; NFRs like Logging that span all containers will have larger tables.
- **Maintenance burden:** Adding a new container (e.g., a new microservice) requires updating applicable NFR sections. This is acceptable because new containers should trigger an NFR review anyway.
- **Category grouping:** Preserve the existing 7-category structure as top-level headings, with NFR subsections nested within their category.
- **Summary table:** Keep a summary table at the bottom but derive system-level status from per-container rollup.
- **Backward compatibility:** ADRs and plans that reference NFR IDs (e.g., "NFR-026") remain valid. The per-container detail is additive.

### Files Changed

| File | Change |
|------|--------|
| `knowledge-base/engineering/architecture/nfr-register.md` | Restructure from flat tables to per-NFR sections with container/link applicability matrices |
| `plugins/soleur/skills/architecture/SKILL.md` | Update `assess` sub-command to support per-container scoping |
| `plugins/soleur/skills/architecture/references/nfr-reference.md` | Document new per-container structure and referencing conventions |

## Non-Goals

- Adding new NFRs beyond the existing 30 -- this is a structural change, not a content expansion
- Automating evidence collection (e.g., scanning code for TLS config) -- evidence is manually documented
- Changing the ADR template -- the existing NFR Impacts section already supports referencing specific containers
- Creating a machine-readable format (YAML/JSON) for the NFR register -- markdown remains the format
- Per-component (C4 Level 3) granularity -- container-level (C4 Level 2) is sufficient

## Acceptance Criteria

- [ ] Each of the 30 NFRs has its own subsection with a container/link applicability table
- [ ] Container and link names match the C4 container diagram exactly
- [ ] System-level status is derived from per-container rollup (worst-case aggregation)
- [ ] Every "Applicable: Yes" row has a non-empty "Enforced By" and "Evidence" column (or explicit "TBD" for gaps)
- [ ] The summary table at the bottom reflects rollup from per-container data
- [ ] The `assess` sub-command references the per-container structure in its output description
- [ ] `nfr-reference.md` documents how to reference specific container/link rows in ADR NFR Impacts
- [ ] All existing NFR IDs are preserved (no renumbering)
- [ ] Markdown passes markdownlint

## Test Scenarios

- Given the restructured NFR register, when reading NFR-026, then there is a table showing encryption enforcement per container link with specific evidence
- Given the restructured NFR register, when reading the summary table, then system-level statuses match the worst-case rollup of per-container statuses
- Given an NFR that applies to only some containers (e.g., NFR-007 Circuit Breaker), when viewing its section, then only applicable containers/links appear (no noise from irrelevant containers)
- Given the updated assess sub-command description, when a user runs `architecture assess`, then the output references per-container NFR tables
- Given the updated nfr-reference.md, when writing an ADR NFR Impacts section, then there is guidance on referencing specific container/link evidence

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a pure engineering/architecture documentation restructuring. The CTO domain is relevant because it changes the NFR register structure that the architecture skill consumes and produces. No infrastructure provisioning, no external services, no user-facing changes. The restructuring improves architectural traceability without introducing new tooling or dependencies. Risk is low -- the changes are additive (per-container detail enriches existing flat data) and backward-compatible (NFR IDs are preserved).

## References & Research

### Internal References

- Current NFR register: `knowledge-base/engineering/architecture/nfr-register.md` (30 NFRs, 7 categories, 94 lines)
- C4 container diagram: `knowledge-base/engineering/architecture/diagrams/container.md` (13 containers, 7 external systems, 14 relationships)
- Architecture skill: `plugins/soleur/skills/architecture/SKILL.md` (assess sub-command at line 207)
- NFR reference guide: `plugins/soleur/skills/architecture/references/nfr-reference.md`
- ADR template: `plugins/soleur/skills/architecture/references/adr-template.md` (NFR Impacts section)
- Related PRs: #1203 (NFR register + ADR template), #1204 (NFR reference guide), #1205 (assess sub-command)
- Issue: #1206
