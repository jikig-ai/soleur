# Non-Functional Requirements — Reference Guide

Non-Functional Requirements (NFRs) define how the system should behave rather than what it should do. Every architecture decision should consider its impact on NFRs.

## NFR Categories

| Category | Scope | Example NFRs |
|----------|-------|-------------|
| Observability | Can we see what the system is doing? | Logging, monitoring, tracing, dashboards |
| Resilience | Does the system recover from failures? | Circuit breakers, graceful shutdown, auto-healing |
| Testing | Can we verify the system works? | Functional tests, performance tests, synthetic monitoring |
| Configuration & Delivery | Can we deploy and configure safely? | Externalized config, CI/CD, canary upgrades |
| Scaling & Recovery | Can the system grow and recover? | Auto-scaling, readiness/liveness probes, backup |
| Security | Is the system protected? | Encryption, rate limiting, attack detection, image security |
| Data Quality | Is the data trustworthy? | Freshness, accuracy, LLM-readiness |

## NFR Register Structure

The canonical NFR register lives at `knowledge-base/engineering/architecture/nfr-register.md`. It contains all NFRs organized per-container and per-link with applicability matrices.

### Per-Container/Link Format

Each NFR has its own section with a table mapping to C4 containers and links:

```markdown
### NFR-NNN: Title

**Category:** X | **Scope:** Y | **System-Level Status:** Z

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Cloudflare | WAF managed rulesets |
| Agent Runtime -> Anthropic | Not Implemented | — | No circuit breaker |
```

### NFR Scope Classification

Each NFR has a scope that determines which rows appear in its table:

| Scope | Description | Rows to Include |
|-------|-------------|-----------------|
| Container-scoped | Applies to individual containers | Container rows only |
| Link-scoped | Applies to relationships between containers | Link rows only |
| Both | Applies to containers and links | Both container and link rows |

### System-Level Rollup

System-level status is derived from per-container/link statuses using explicit precedence:

1. If any applicable container/link is **Not Implemented** -> system-level is **Not Implemented**
2. Else if any is **Partial** -> system-level is **Partial**
3. Else if all are **Implemented** -> system-level is **Implemented**
4. **N/A** rows are excluded from rollup. An NFR where all rows are N/A has system-level **N/A**

## How to Reference NFRs in ADRs

When writing the `## NFR Impacts` section of an ADR, reference NFRs by their ID **and the specific container or link affected**:

```markdown
## NFR Impacts

- **NFR-014 (Externalized Configuration) on New Service container:** Maintained — uses Doppler for secrets (no change)
- **NFR-026 (Encryption In-Transit) on Agent Runtime -> New Service link:** Implemented — SDK enforces HTTPS
- **NFR-007 (Circuit Breaker) on Agent Runtime -> New Service link:** Risk introduced — no fallback; filed as follow-up
- **NFR-001 (Logging) on New Service container:** Needs attention — structured logging required
```

Per-container references are more precise than system-level references. Use the format: `NFR-NNN (Name) on <Container/Link>`.

### Assessment Checklist

When evaluating NFR impacts for a decision, first identify which C4 containers and links the decision affects, then check each category for the affected containers/links:

1. **Observability:** Does this change add containers or links that need monitoring? Will existing logging capture the new behavior per container?
2. **Resilience:** Does this introduce new failure modes on specific links? Are there fallbacks for new external dependencies?
3. **Testing:** Can the change be tested per container? Does it need new test types (load, integration, E2E)?
4. **Configuration & Delivery:** Does this add new secrets or deployment steps for specific containers?
5. **Scaling & Recovery:** Does this change scaling for specific containers? Are there new stateful components or backup requirements?
6. **Security:** Does this expose new attack surfaces on specific links, handle sensitive data in new containers, or change access control?
7. **Data Quality:** Does this change how data is created, stored, or accessed per container? Are there new consistency requirements?

### When to Update the NFR Register

Update `knowledge-base/engineering/architecture/nfr-register.md` when:

- An ADR changes the status of an NFR on a specific container/link (e.g., Agent Runtime -> New Service: Not Implemented -> Implemented)
- A new NFR is identified that is not in the register
- The enforcement tool changes for a specific container/link
- An NFR becomes N/A or newly relevant for a container/link due to architecture changes
- A new container or link is added to the C4 diagram (see Maintenance Procedure below)

## NFR Status Definitions

| Status | Criteria |
|--------|----------|
| **Implemented** | Actively enforced by a tool or mechanism. Verified working. |
| **Partial** | Some coverage but known gaps. Document what is and is not covered. |
| **Not Implemented** | Acknowledged but no mechanism in place. May have a roadmap item. |
| **N/A** | Not applicable at current scale or architecture. Revisit when conditions change. |

## Common NFR Patterns by Decision Type

| Decision Type | Typically Affects |
|---------------|------------------|
| New external service integration | NFR-001 (Logging), NFR-007 (Circuit Breaker), NFR-026 (Encryption In-Transit), NFR-041 (Link Access Control) |
| Infrastructure change | NFR-002-004 (Monitoring), NFR-010 (Scalability), NFR-016 (CD), NFR-019 (Auto-scaling), NFR-038 (Least Privilege) |
| New user-facing feature | NFR-008 (Latency), NFR-011 (Functional Testing), NFR-025 (Rate Limiting), NFR-042 (LLM-Ready Docs) |
| Data model change | NFR-027 (Encryption At-Rest), NFR-029 (Data Freshness), NFR-030 (Data Accuracy), NFR-040 (Retention Policy) |
| Security change | NFR-023-028 (security category), NFR-038-041, NFR-047 |
| Deployment change | NFR-016-018 (CD, Graceful Shutdown, Canary), NFR-021-022 (Readiness/Liveness), NFR-032 (Auto Rollback), NFR-036 (Immutable Releases) |
| New container addition | See Maintenance Procedure below |

## Maintenance Procedure: Adding New Containers

When a new container is added to the C4 container diagram (`knowledge-base/engineering/architecture/diagrams/container.md`):

1. **Classify the container** as runtime, passive, or infrastructure (see Container Classification in the register)
2. **Add the container** to the Container & Link Inventory table in the NFR register
3. **Add new links** involving this container to the Link Classification table
4. **Review each NFR section** and add rows for the new container/links where applicable:
   - Runtime containers: check all container-scoped NFRs (Logging, Monitoring, Testing, Config, etc.)
   - Passive containers: check only Documentation (NFR-015), LLM-Ready Documentation (NFR-042), and Encryption At-Rest (NFR-027) if containing sensitive data
   - Infrastructure containers: check monitoring, security, and scaling categories
5. **For new links:** check all link-scoped NFRs (Circuit Breaker, Latency, Rate Limiting, Encryption In-Transit, Distributed Tracing, Access Control, Certificate Scope)
6. **Update the summary table** to reflect new rollup counts
7. **Verify** container/link names match the C4 diagram exactly
