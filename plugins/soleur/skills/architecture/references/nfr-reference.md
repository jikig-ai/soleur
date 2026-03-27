# Non-Functional Requirements — Reference Guide

Non-Functional Requirements (NFRs) define how the system should behave rather than what it should do. Every architecture decision should consider its impact on NFRs.

## NFR Categories

| Category | Scope | Example NFRs |
|----------|-------|-------------|
| Observability | Can we see what the system is doing? | Logging, monitoring, tracing, dashboards |
| Resilience | Does the system recover from failures? | Circuit breakers, graceful shutdown, auto-healing |
| Testing | Can we verify the system works? | Functional tests, performance tests, synthetic monitoring |
| Configuration & Delivery | Can we deploy and configure safely? | Externalized config, CI/CD, canary upgrades |
| Scaling & Recovery | Can the system grow and recover? | Auto-scaling, readiness/liveness probes |
| Security | Is the system protected? | Encryption, rate limiting, attack detection |
| Data Quality | Is the data trustworthy? | Freshness, accuracy, consistency |

## NFR Register Location

The canonical NFR register lives at `knowledge-base/engineering/architecture/nfr-register.md`. It contains all 30 NFRs with current status (Implemented, Partial, Not Implemented, N/A) and the tool that enforces each.

## How to Reference NFRs in ADRs

When writing the `## NFR Impacts` section of an ADR, reference NFRs by their ID and describe the status change:

```markdown
## NFR Impacts

- **NFR-014 (Externalized Configuration):** Maintained — new service uses Doppler for secrets (no change)
- **NFR-026 (Encryption In-Transit):** Improved from Partial to Implemented — all new endpoints use HTTPS via Cloudflare Tunnel
- **NFR-007 (Circuit Breaker):** Risk introduced — new external API dependency has no circuit breaker; filed as follow-up
```

### Assessment Checklist

When evaluating NFR impacts for a decision, check each category:

1. **Observability:** Does this change add services, APIs, or components that need monitoring? Will existing logging capture the new behavior?
2. **Resilience:** Does this introduce new failure modes? Are there fallbacks for external dependencies?
3. **Testing:** Can the change be tested automatically? Does it need new test types (load, integration, E2E)?
4. **Configuration & Delivery:** Does this add new environment variables, secrets, or deployment steps?
5. **Scaling & Recovery:** Does this change the system's scaling characteristics? Are there new stateful components?
6. **Security:** Does this expose new attack surfaces, handle sensitive data, or change authentication/authorization?
7. **Data Quality:** Does this change how data is created, stored, or accessed? Are there new consistency requirements?

### When to Update the NFR Register

Update `knowledge-base/engineering/architecture/nfr-register.md` when:

- An ADR changes the status of an NFR (e.g., Partial → Implemented)
- A new NFR is identified that is not in the register
- The enforcement tool changes (e.g., migrating from one monitoring service to another)
- An NFR becomes N/A or newly relevant due to architecture changes

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
| New external service integration | NFR-001 (Logging), NFR-007 (Circuit Breaker), NFR-026 (Encryption In-Transit) |
| Infrastructure change | NFR-002-004 (Monitoring), NFR-010 (Scalability), NFR-016 (CD), NFR-019 (Auto-scaling) |
| New user-facing feature | NFR-008 (Latency), NFR-011 (Functional Testing), NFR-025 (Rate Limiting) |
| Data model change | NFR-027 (Encryption At-Rest), NFR-029 (Data Freshness), NFR-030 (Data Accuracy) |
| Security change | NFR-023-027 (full security category) |
| Deployment change | NFR-016-018 (CD, Graceful Shutdown, Canary), NFR-021-022 (Readiness/Liveness) |
