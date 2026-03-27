---
title: "feat: NFR register per-container and per-link applicability with evidence"
type: feat
date: 2026-03-27
issue: "#1206"
semver: patch
deepened: 2026-03-27
---

# feat: NFR register per-container and per-link applicability with evidence

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, References)
**Research sources:** Web research on NFR traceability matrices, ADR-NFR mapping best practices, C4 diagram verification, codebase analysis

### Key Improvements

1. Fixed link inventory: C4 diagram has 22 relationships (not 14) -- 8 internal links were missing from the original plan
2. Added container classification (runtime vs. passive vs. infrastructure) to reduce NFR table noise
3. Clarified rollup rule with explicit precedence and handling of N/A status
4. Added NFR scope classification (container-scoped vs. link-scoped vs. both) to guide implementers
5. Added implementation sequencing guidance and edge case handling

### New Considerations Discovered

- Passive containers (Skills, Agents, Knowledge Base) are data artifacts with no runtime behavior -- most NFR categories do not apply to them, which significantly reduces table sizes
- Internal links (File I/O, Directory scan, Event hook) need different NFR treatment than network links -- encryption in-transit is irrelevant for File I/O links
- Industry best practice confirms per-component NFR traceability as the recommended approach, with emphasis on maintaining traceability between analysis models and architectural patterns

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

The system-level status becomes a derived rollup using explicit precedence:

1. If any applicable container/link is **Not Implemented**, system-level is **Not Implemented**
2. Else if any is **Partial**, system-level is **Partial**
3. Else if all are **Implemented**, system-level is **Implemented**
4. **N/A** rows are excluded from the rollup -- an NFR where all containers are N/A has system-level **N/A**

### 2. Source containers and links from the C4 container diagram

The container/link inventory comes from `knowledge-base/engineering/architecture/diagrams/container.md`. Containers are classified into three types to guide NFR applicability:

**Runtime Containers** (have running processes, most NFRs apply):

- Dashboard (React, Next.js) -- `dashboard`
- API Routes (Next.js API) -- `api`
- Auth Module (Supabase Auth) -- `auth`
- Agent Runtime (Claude Code) -- `claude`
- Skill Loader (Plugin Discovery) -- `skillloader`
- Hook Engine (PreToolUse Guards) -- `hooks`
- Telegram Bot (grammy, TypeScript) -- `tgbot`

**Passive Containers** (data artifacts, limited NFR applicability):

- Skills (Markdown SKILL.md) -- `skills`
- Agents (Markdown Agent Defs) -- `agents`
- Knowledge Base (Markdown + YAML) -- `kb`

**Infrastructure Containers** (hosting/networking, infrastructure-specific NFRs apply):

- Supabase PostgreSQL -- `supabase`
- Cloudflare Tunnel (cloudflared) -- `tunnel`
- Compute (Hetzner Cloud) -- `hetzner`

**External Systems:**

- Anthropic API -- `anthropic`
- GitHub -- `github`
- Cloudflare -- `cloudflare`
- Doppler -- `doppler`
- Stripe -- `stripe`
- Plausible -- `plausible`
- Telegram Bot API -- `telegram_api`

**All Links (22 `Rel()` declarations from the C4 diagram):**

Network links (NFRs like encryption in-transit, circuit breaker apply):

- Founder -> Dashboard (HTTPS)
- Dashboard -> API Routes (HTTPS)
- API Routes -> Agent Runtime (WebSocket)
- API Routes -> Supabase (HTTPS)
- API Routes -> Stripe (HTTPS)
- Agent Runtime -> Supabase (HTTPS)
- Agent Runtime -> Anthropic (HTTPS)
- Agent Runtime -> GitHub (HTTPS/SSH)
- Auth Module -> Supabase (HTTPS)
- Cloudflare Tunnel -> API Routes (HTTPS)
- Doppler -> Agent Runtime (CLI)
- Dashboard -> Plausible (JS snippet)
- Telegram Bot -> Telegram API (grammy SDK)
- Telegram Bot -> Agent Runtime (Subprocess)

Internal links (process-local, most network-oriented NFRs do not apply):

- Agent Runtime -> Skill Loader (File I/O)
- Skill Loader -> Skills (Directory scan)
- Skill Loader -> Agents (Recursive scan)
- Hook Engine -> Agent Runtime (Event hook)
- Skills -> Knowledge Base (File I/O)
- Agents -> Knowledge Base (File I/O)

Infrastructure links (hosting relationships):

- Compute -> Agent Runtime (Docker)
- Compute -> Telegram Bot (Docker)

Not every NFR applies to every container or link. The applicability column captures this -- omit rows where the NFR is clearly irrelevant (e.g., do not add encryption in-transit rows for File I/O links). This keeps tables focused and scannable.

### Research Insight: NFR Scope Classification

Each NFR naturally falls into one of three scopes. Classify each during implementation to determine which rows to include:

| Scope | Description | Example NFRs |
|-------|-------------|-------------|
| **Container-scoped** | Applies to individual containers | NFR-001 (Logging), NFR-017 (Graceful Shutdown), NFR-020 (Auto-healing) |
| **Link-scoped** | Applies to relationships between containers | NFR-026 (Encryption In-Transit), NFR-007 (Circuit Breaker), NFR-025 (Rate Limiting) |
| **Both** | Applies to containers and links | NFR-023 (Attack Detection), NFR-024 (Attack Prevention) |

Container-scoped NFRs need only container rows. Link-scoped NFRs need only link rows. This prevents table bloat from irrelevant combinations.

### 3. Update `architecture assess` sub-command

Currently, the assess sub-command outputs a flat table. After this change, it will:

1. When assessing a feature, map the feature to affected containers/links (using the C4 diagram)
2. Output per-container NFR status for only the affected containers
3. Include evidence gaps (containers/links with "Applicable: Yes" but no evidence documented)
4. Recommend specific containers/links where NFR gaps exist, not just system-level gaps

Note: The `--container <name>` scoping argument from the original issue is deferred as a non-goal for this iteration. The assess sub-command already identifies affected containers from the feature description -- explicit container scoping adds CLI argument parsing complexity without clear benefit for the primary use case (assessing a feature). It can be added later if users request it.

### 4. Update `nfr-reference.md`

Update the reference guide to document the new per-container structure and how to reference specific container/link rows in ADR NFR Impacts sections.

## Technical Considerations

- **File size:** The register will grow from ~94 lines to approximately 300-400 lines. Each of the 30 NFRs gets its own section with a table. NFRs where only 1-2 containers apply will have small tables; NFRs like Logging that span all containers will have larger tables. Using the scope classification (container-scoped vs. link-scoped) and omitting passive containers where irrelevant keeps individual tables to 3-8 rows rather than 13+.
- **Maintenance burden:** Adding a new container (e.g., a new microservice) requires updating applicable NFR sections. This is acceptable because new containers should trigger an NFR review anyway. Document this maintenance contract in `nfr-reference.md` so future contributors know the update procedure.
- **Category grouping:** Preserve the existing 7-category structure as top-level headings (`##`), with NFR subsections (`###`) nested within their category. This gives 3 heading levels: category (`##`), NFR (`###`), and metadata/table content.
- **Summary table:** Keep a summary table at the bottom but derive system-level status from per-container rollup using the explicit precedence rule (Not Implemented > Partial > Implemented; N/A excluded).
- **Backward compatibility:** ADRs and plans that reference NFR IDs (e.g., "NFR-026") remain valid. The per-container detail is additive.
- **Passive container handling:** Skills, Agents, and Knowledge Base are markdown files on disk. Most NFR categories (Resilience, Scaling, Security network controls) do not apply. Include them only for categories where they are genuinely relevant (e.g., NFR-015 Documentation, NFR-027 Encryption At-Rest for the KB if it contains sensitive data). Omitting irrelevant passive container rows avoids table bloat.
- **Implementation sequencing:** Complete the register restructure (Phase 2) before updating the architecture skill (Phase 3). The skill references the register structure -- updating the skill first would create a mismatch between the skill instructions and the actual register format.

### Research Insights

**Industry alignment:** NFR traceability per-component is the [recommended approach](https://link.springer.com/chapter/10.1007/978-1-4471-2239-5_14) in software architecture literature. The key insight is that NFRs exhibit complex interdependencies across components -- flat system-level tracking loses the mapping between quality attributes and the architectural elements that implement them.

**ADR integration:** [AWS best practices](https://aws.amazon.com/blogs/architecture/master-architecture-decision-records-adrs-best-practices-for-effective-decision-making/) recommend linking ADRs to specific containers/components affected by the decision. The existing NFR Impacts section in ADRs will naturally benefit from per-container references (e.g., "Improves NFR-026 on the API -> Anthropic link" instead of "Improves NFR-026").

**Verification discipline:** Per the project learning on [stale domain assessments](knowledge-base/project/learnings/2026-03-25-domain-assessments-contain-stale-codebase-claims.md), verify all container and link names against the actual C4 diagram before writing each NFR section. Do not copy container names from this plan without re-reading the diagram -- the C4 diagram is the source of truth, not this plan's inventory.

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
- `--container <name>` CLI argument for the assess sub-command -- deferred until user demand exists; the assess command already infers affected containers from the feature description

## Acceptance Criteria

- [ ] Each of the 30 NFRs has its own subsection (`###`) with a container/link applicability table
- [ ] Container and link names match the C4 container diagram (`container.md`) exactly -- verified by re-reading the diagram, not copied from this plan
- [ ] Each NFR section includes **Category** and **System-Level Status** metadata above the table
- [ ] System-level status is derived from per-container rollup using explicit precedence: Not Implemented > Partial > Implemented; N/A excluded
- [ ] Every row with "Applicable: Yes" has a non-empty "Enforced By" and "Evidence" column (or explicit "TBD" for gaps)
- [ ] Passive containers (Skills, Agents, Knowledge Base) are included only where genuinely applicable -- not in every NFR section
- [ ] Internal links (File I/O, Directory scan, Event hook) are excluded from network-oriented NFRs (encryption, circuit breaker, rate limiting)
- [ ] The summary table at the bottom reflects rollup from per-container data, with counts matching the per-NFR tables
- [ ] The `assess` sub-command in SKILL.md references the per-container structure in its assessment output format
- [ ] `nfr-reference.md` documents: (a) the per-container structure, (b) how to reference specific container/link rows in ADR NFR Impacts, (c) the maintenance procedure when adding new containers
- [ ] All existing NFR IDs are preserved (no renumbering)
- [ ] Markdown passes markdownlint on all modified files

## Test Scenarios

- Given the restructured NFR register, when reading NFR-026 (Encryption In-Transit), then there is a table showing encryption enforcement per network link with specific evidence, and internal File I/O links are absent
- Given the restructured NFR register, when reading the summary table, then system-level statuses match the worst-case rollup of per-container statuses using the precedence rule
- Given an NFR that applies to only some containers (e.g., NFR-007 Circuit Breaker), when viewing its section, then only applicable containers/links appear (no noise from irrelevant containers or internal links)
- Given the restructured NFR register, when reading NFR-001 (Logging), then passive containers (Skills, Agents, Knowledge Base) are either absent or explicitly marked N/A
- Given the updated assess sub-command description, when a user runs `architecture assess`, then the output references per-container NFR tables and identifies specific evidence gaps
- Given the updated nfr-reference.md, when writing an ADR NFR Impacts section, then there is guidance on referencing specific container/link evidence (e.g., "NFR-026 on Agent Runtime -> Anthropic link")
- Given the updated nfr-reference.md, when adding a new container to the C4 diagram, then there is a documented procedure for updating applicable NFR sections

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a pure engineering/architecture documentation restructuring. The CTO domain is relevant because it changes the NFR register structure that the architecture skill consumes and produces. No infrastructure provisioning, no external services, no user-facing changes. The restructuring improves architectural traceability without introducing new tooling or dependencies. Risk is low -- the changes are additive (per-container detail enriches existing flat data) and backward-compatible (NFR IDs are preserved).

## References & Research

### Internal References

- Current NFR register: `knowledge-base/engineering/architecture/nfr-register.md` (30 NFRs, 7 categories, 94 lines)
- C4 container diagram: `knowledge-base/engineering/architecture/diagrams/container.md` (13 containers, 7 external systems, 22 relationships)
- Architecture skill: `plugins/soleur/skills/architecture/SKILL.md` (assess sub-command at line 207)
- NFR reference guide: `plugins/soleur/skills/architecture/references/nfr-reference.md`
- ADR template: `plugins/soleur/skills/architecture/references/adr-template.md` (NFR Impacts section)
- Related PRs: #1203 (NFR register + ADR template), #1204 (NFR reference guide), #1205 (assess sub-command)
- Issue: #1206
- Learning: `knowledge-base/project/learnings/2026-03-25-domain-assessments-contain-stale-codebase-claims.md` -- verify container names against live C4 diagram, not cached plan data

### External References

- [Tracing Non-Functional Requirements](https://link.springer.com/chapter/10.1007/978-1-4471-2239-5_14) -- academic reference on NFR traceability across architectural components
- [AWS: Master ADR Best Practices](https://aws.amazon.com/blogs/architecture/master-architecture-decision-records-adrs-best-practices-for-effective-decision-making/) -- links ADRs to specific containers/components affected
- [NFR Traceability Management Based on Architectural Patterns](https://link.springer.com/chapter/10.1007/978-3-642-21375-5_3) -- traceability between analysis and design models for NFRs
- [GitHub ADR Repository](https://github.com/joelparkerhenderson/architecture-decision-record) -- community ADR templates and examples
- [Google Cloud ADR Overview](https://docs.cloud.google.com/architecture/architecture-decision-records) -- practical guidance on ADR structure and maintenance
