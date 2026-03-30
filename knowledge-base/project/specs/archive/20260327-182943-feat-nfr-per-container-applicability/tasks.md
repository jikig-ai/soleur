# Tasks: NFR Per-Container Applicability

## Phase 1: Setup

- [ ] 1.1 Read and inventory all 30 NFRs from `knowledge-base/engineering/architecture/nfr-register.md`
- [ ] 1.2 Read and extract all containers, external systems, and relationships from `knowledge-base/engineering/architecture/diagrams/container.md` (source of truth: 13 containers, 7 external systems, 22 relationships)
- [ ] 1.3 Classify containers into runtime (Dashboard, API Routes, Auth Module, Agent Runtime, Skill Loader, Hook Engine, Telegram Bot), passive (Skills, Agents, Knowledge Base), and infrastructure (Supabase, Cloudflare Tunnel, Compute)
- [ ] 1.4 Classify links into network (HTTPS, WebSocket, SDK), internal (File I/O, Directory scan, Event hook), and infrastructure (Docker hosting)
- [ ] 1.5 Classify each of the 30 NFRs by scope: container-scoped, link-scoped, or both

## Phase 2: Core Implementation -- NFR Register Restructure

- [ ] 2.1 Design the new per-NFR section format with container/link applicability matrix
  - [ ] 2.1.1 Define table columns: Container/Link, Applicable, Status, Enforced By, Evidence
  - [ ] 2.1.2 Define system-level status rollup rule: Not Implemented > Partial > Implemented; N/A excluded
  - [ ] 2.1.3 Define section template: `### NFR-NNN: Name` + Category + System-Level Status + table
- [ ] 2.2 Restructure Observability category NFRs (NFR-001 through NFR-006b) -- container-scoped
  - [ ] 2.2.1 NFR-001: Logging -- map to runtime containers only (skip passive containers)
  - [ ] 2.2.2 NFR-002: System-level monitoring -- map to infrastructure containers (Compute, Supabase)
  - [ ] 2.2.3 NFR-003: Service-level monitoring -- map to runtime containers
  - [ ] 2.2.4 NFR-004: Process-level monitoring -- map to runtime containers
  - [ ] 2.2.5 NFR-005: Telemetry dashboards -- map to Dashboard, Plausible link
  - [ ] 2.2.6 NFR-006: Distributed tracing -- map to inter-container network links
  - [ ] 2.2.7 NFR-006b: Overlay change events -- map to deployable containers (Dashboard, API Routes, Agent Runtime, Telegram Bot)
- [ ] 2.3 Restructure Resilience category NFRs (NFR-007 through NFR-010)
  - [ ] 2.3.1 NFR-007: Circuit breaker -- link-scoped, map to external API network links only (Anthropic, Stripe, Supabase, GitHub, Telegram API)
  - [ ] 2.3.2 NFR-008: Low latency -- link-scoped, map to user-facing network links (Founder -> Dashboard, Dashboard -> API, API -> Agent Runtime)
  - [ ] 2.3.3 NFR-009: High throughput -- container-scoped, map to Compute, API Routes, Agent Runtime
  - [ ] 2.3.4 NFR-010: Linear horizontal scalability -- container-scoped, map to stateless runtime containers
- [ ] 2.4 Restructure Testing category NFRs (NFR-011 through NFR-013) -- container-scoped
  - [ ] 2.4.1 NFR-011: Automated functional testability -- map to all codebases with tests (plugin, web app, telegram bridge)
  - [ ] 2.4.2 NFR-012: Automated performance testability -- map to user-facing runtime containers
  - [ ] 2.4.3 NFR-013: Synthetic monitoring -- map to external-facing endpoints (Dashboard, API Routes)
- [ ] 2.5 Restructure Configuration & Delivery category NFRs (NFR-014 through NFR-018) -- container-scoped
  - [ ] 2.5.1 NFR-014: Externalized environment configuration -- map to deployable containers that consume secrets
  - [ ] 2.5.2 NFR-015: Documentation of internal services -- map to all containers (including passive -- KB is the documentation itself)
  - [ ] 2.5.3 NFR-016: Continuous automated delivery -- map to deployable containers
  - [ ] 2.5.4 NFR-017: Graceful shutdown -- map to long-running process containers (API Routes, Agent Runtime, Telegram Bot)
  - [ ] 2.5.5 NFR-018: Canary upgrade -- map to deployable containers
- [ ] 2.6 Restructure Scaling & Recovery category NFRs (NFR-019 through NFR-022) -- container-scoped
  - [ ] 2.6.1 NFR-019: Auto-scaling -- map to Compute and runtime containers
  - [ ] 2.6.2 NFR-020: Auto-healing -- map to runtime containers with Docker restart policies
  - [ ] 2.6.3 NFR-021: Readiness endpoint -- map to HTTP-serving containers (Dashboard, API Routes)
  - [ ] 2.6.4 NFR-022: Liveness endpoint -- map to HTTP-serving containers (Dashboard, API Routes)
- [ ] 2.7 Restructure Security category NFRs (NFR-023 through NFR-028) -- mixed scope
  - [ ] 2.7.1 NFR-023: Attack detection and blocking -- both scopes, map to external-facing containers and network links
  - [ ] 2.7.2 NFR-024: Attack prevention -- both scopes, map to all containers handling user data and their links
  - [ ] 2.7.3 NFR-025: Rate limiting -- link-scoped, map to external-facing network links
  - [ ] 2.7.4 NFR-026: Encryption in-transit -- link-scoped, map to network links only (exclude File I/O, Directory scan, Event hook)
  - [ ] 2.7.5 NFR-027: Encryption at-rest -- container-scoped, map to data-storing containers (Supabase, Knowledge Base if sensitive)
  - [ ] 2.7.6 NFR-028: Geo distribution -- container-scoped, map to all deployable containers
- [ ] 2.8 Restructure Data Quality category NFRs (NFR-029 through NFR-030) -- container-scoped
  - [ ] 2.8.1 NFR-029: Data freshness -- map to data-consuming containers (Dashboard, Agent Runtime) and their data links
  - [ ] 2.8.2 NFR-030: Data accuracy -- map to data-writing containers (API Routes, Agent Runtime, Auth Module)
- [ ] 2.9 Update the summary table with system-level rollup derived from per-container data using explicit precedence rule

## Phase 3: Architecture Skill Updates

- [ ] 3.1 Update `assess` sub-command in `plugins/soleur/skills/architecture/SKILL.md`
  - [ ] 3.1.1 Update step 4 to reference per-container structure when assessing NFR categories
  - [ ] 3.1.2 Update step 5 output format to include container/link column and evidence gaps
  - [ ] 3.1.3 Update step 6 recommendations to reference specific containers/links with gaps
- [ ] 3.2 Update `plugins/soleur/skills/architecture/references/nfr-reference.md`
  - [ ] 3.2.1 Add section documenting per-container structure and NFR scope classification
  - [ ] 3.2.2 Add guidance on referencing specific container/link rows in ADR NFR Impacts (with example)
  - [ ] 3.2.3 Update assessment checklist to include container-scoping guidance
  - [ ] 3.2.4 Add maintenance procedure for updating NFR sections when new containers are added to the C4 diagram

## Phase 4: Validation

- [ ] 4.1 Verify all 30 NFRs are present with per-container tables
- [ ] 4.2 Verify container/link names match C4 diagram exactly (re-read `container.md`, do not rely on cached data)
- [ ] 4.3 Verify summary table rollup matches per-container worst-case using explicit precedence
- [ ] 4.4 Verify passive containers are absent from NFR sections where they are irrelevant
- [ ] 4.5 Verify internal links (File I/O) are absent from network-oriented NFRs
- [ ] 4.6 Run markdownlint on `nfr-register.md`
- [ ] 4.7 Run markdownlint on `nfr-reference.md`
- [ ] 4.8 Verify no NFR IDs were renumbered
