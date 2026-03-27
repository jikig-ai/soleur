# Tasks: NFR Per-Container Applicability

## Phase 1: Setup

- [ ] 1.1 Read and inventory all 30 NFRs from `knowledge-base/engineering/architecture/nfr-register.md`
- [ ] 1.2 Read and extract all containers, external systems, and relationships from `knowledge-base/engineering/architecture/diagrams/container.md`
- [ ] 1.3 Build a container/link reference list (13 containers + 7 external systems + 14 relationships)

## Phase 2: Core Implementation -- NFR Register Restructure

- [ ] 2.1 Design the new per-NFR section format with container/link applicability matrix
  - [ ] 2.1.1 Define table columns: Container/Link, Applicable, Status, Enforced By, Evidence
  - [ ] 2.1.2 Define system-level status rollup rule (worst-case aggregation)
- [ ] 2.2 Restructure Observability category NFRs (NFR-001 through NFR-006b)
  - [ ] 2.2.1 NFR-001: Logging -- map to all containers with per-container maturity
  - [ ] 2.2.2 NFR-002: System-level monitoring -- map to infrastructure containers
  - [ ] 2.2.3 NFR-003: Service-level monitoring -- map to application containers
  - [ ] 2.2.4 NFR-004: Process-level monitoring -- map to running containers
  - [ ] 2.2.5 NFR-005: Telemetry dashboards -- map to web-facing containers
  - [ ] 2.2.6 NFR-006: Distributed tracing -- map to inter-container links
  - [ ] 2.2.7 NFR-006b: Overlay change events -- map to deployment containers
- [ ] 2.3 Restructure Resilience category NFRs (NFR-007 through NFR-010)
  - [ ] 2.3.1 NFR-007: Circuit breaker -- map to external API links only
  - [ ] 2.3.2 NFR-008: Low latency -- map to user-facing links
  - [ ] 2.3.3 NFR-009: High throughput -- map to compute containers
  - [ ] 2.3.4 NFR-010: Linear horizontal scalability -- map to stateless containers
- [ ] 2.4 Restructure Testing category NFRs (NFR-011 through NFR-013)
  - [ ] 2.4.1 NFR-011: Automated functional testability -- map to all codebases
  - [ ] 2.4.2 NFR-012: Automated performance testability -- map to user-facing containers
  - [ ] 2.4.3 NFR-013: Synthetic monitoring -- map to external-facing endpoints
- [ ] 2.5 Restructure Configuration & Delivery category NFRs (NFR-014 through NFR-018)
  - [ ] 2.5.1 NFR-014: Externalized environment configuration -- map to all deployable containers
  - [ ] 2.5.2 NFR-015: Documentation of internal services -- map to all containers
  - [ ] 2.5.3 NFR-016: Continuous automated delivery -- map to all deployable containers
  - [ ] 2.5.4 NFR-017: Graceful shutdown -- map to long-running process containers
  - [ ] 2.5.5 NFR-018: Canary upgrade -- map to all deployable containers
- [ ] 2.6 Restructure Scaling & Recovery category NFRs (NFR-019 through NFR-022)
  - [ ] 2.6.1 NFR-019: Auto-scaling -- map to compute containers
  - [ ] 2.6.2 NFR-020: Auto-healing -- map to running containers
  - [ ] 2.6.3 NFR-021: Readiness endpoint -- map to HTTP-serving containers
  - [ ] 2.6.4 NFR-022: Liveness endpoint -- map to HTTP-serving containers
- [ ] 2.7 Restructure Security category NFRs (NFR-023 through NFR-028)
  - [ ] 2.7.1 NFR-023: Attack detection and blocking -- map to external-facing containers and links
  - [ ] 2.7.2 NFR-024: Attack prevention -- map to all containers handling user data
  - [ ] 2.7.3 NFR-025: Rate limiting -- map to external-facing links
  - [ ] 2.7.4 NFR-026: Encryption in-transit -- map to all inter-container and external links
  - [ ] 2.7.5 NFR-027: Encryption at-rest -- map to data-storing containers
  - [ ] 2.7.6 NFR-028: Geo distribution -- map to all deployable containers
- [ ] 2.8 Restructure Data Quality category NFRs (NFR-029 through NFR-030)
  - [ ] 2.8.1 NFR-029: Data freshness -- map to data-consuming containers and links
  - [ ] 2.8.2 NFR-030: Data accuracy -- map to data-writing containers
- [ ] 2.9 Update the summary table with system-level rollup derived from per-container data

## Phase 3: Architecture Skill Updates

- [ ] 3.1 Update `assess` sub-command in `plugins/soleur/skills/architecture/SKILL.md`
  - [ ] 3.1.1 Update step 4 to reference per-container structure when assessing NFR categories
  - [ ] 3.1.2 Update step 5 output format to include container/link column
  - [ ] 3.1.3 Update step 6 recommendations to reference specific containers/links
- [ ] 3.2 Update `plugins/soleur/skills/architecture/references/nfr-reference.md`
  - [ ] 3.2.1 Add section documenting per-container structure
  - [ ] 3.2.2 Add guidance on referencing specific container/link rows in ADR NFR Impacts
  - [ ] 3.2.3 Update assessment checklist to include container-scoping guidance

## Phase 4: Validation

- [ ] 4.1 Verify all 30 NFRs are present with per-container tables
- [ ] 4.2 Verify container/link names match C4 diagram exactly
- [ ] 4.3 Verify summary table rollup matches per-container worst-case
- [ ] 4.4 Run markdownlint on `nfr-register.md`
- [ ] 4.5 Run markdownlint on `nfr-reference.md`
- [ ] 4.6 Verify no NFR IDs were renumbered
