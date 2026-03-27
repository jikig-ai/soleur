# Non-Functional Requirements Register

Tracks NFRs across the Soleur platform. Each requirement has a status reflecting current implementation state and the tool/mechanism that enforces it.

**Last updated:** 2026-03-27

## Status Legend

| Status | Meaning |
|--------|---------|
| Implemented | Fully in place and enforced |
| Partial | Some coverage but gaps remain |
| Not Implemented | Not yet addressed |
| N/A | Not applicable at current scale |

## Observability

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-001 | Logging | Partial | Docker logs, `console.log` | Structured logging not implemented. Docker container logs available via `docker logs`. No centralized log aggregation. |
| NFR-002 | System-level monitoring | Not Implemented | — | No system metrics collection. Hetzner Console provides basic server metrics. |
| NFR-003 | Service-level monitoring | Not Implemented | — | No service health dashboards. Uptime monitoring not configured. |
| NFR-004 | Process-level monitoring | Not Implemented | — | No process-level metrics. Docker restart policies provide basic recovery. |
| NFR-005 | Telemetry dashboards | Partial | Plausible Analytics | Web analytics only (page views, referrers). No application telemetry dashboards. |
| NFR-006 | Distributed tracing | Not Implemented | — | Single-service architecture currently. Tracing becomes relevant with multi-service expansion. |
| NFR-006b | Overlay change events | Not Implemented | — | No deployment event correlation with metrics. GitHub Releases track versions but not correlated with performance data. |

## Resilience

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-007 | Circuit breaker | Not Implemented | — | External API calls (Anthropic, Supabase) have no circuit breaker. Failures propagate directly. |
| NFR-008 | Low latency | Partial | Cloudflare CDN | Static assets cached at edge via Cloudflare. API latency depends on Anthropic response time (not controllable). WebSocket connections for real-time agent output. |
| NFR-009 | High throughput | N/A | — | Single-founder usage. Not a current concern. Architecture supports horizontal scaling via ADR-001 (PWA) and containerization. |
| NFR-010 | Linear horizontal scalability | Partial | Docker, Hetzner | Containerized deployment allows horizontal scaling. Stateless web app supports multiple instances. Agent sessions are per-user (natural sharding). No load balancer configured yet. |

## Testing

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-011 | Automated functional testability | Implemented | Bun test, Lefthook pre-commit | 964+ tests across plugin, web platform, and infrastructure. Pre-commit hooks enforce test execution. ATDD workflow in `/soleur:work`. |
| NFR-012 | Automated performance testability | Not Implemented | — | No load testing or performance benchmarks. Performance-oracle agent provides advisory review but no automated benchmarks. |
| NFR-013 | Synthetic monitoring | Not Implemented | — | No synthetic transaction monitoring. Plausible tracks real user visits but not synthetic probes. |

## Configuration & Delivery

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-014 | Externalized environment configuration | Implemented | Doppler | All secrets centralized in Doppler with runtime injection via `doppler run`. No plaintext .env on production servers (ADR-007). |
| NFR-015 | Documentation of internal services | Implemented | Knowledge Base, Git | Architecture decisions in ADRs, component docs in knowledge-base, conventions in constitution.md. 20 ADRs, 3 C4 diagrams, 120+ learnings. |
| NFR-016 | Continuous automated delivery | Implemented | GitHub Actions | Push-to-deploy via Cloudflare Tunnel webhook. ci-deploy.sh handles Docker build, health checks, and rollback. Version bumps automated via semver labels (ADR-017). |
| NFR-017 | Graceful shutdown | Partial | Docker | Docker stop sends SIGTERM with 10s grace period. No application-level graceful shutdown handler (in-flight requests may be dropped). |
| NFR-018 | Canary upgrade | Not Implemented | — | Single-instance deployment. No canary or blue-green strategy. Rollback via `docker pull` of previous image tag. |

## Scaling & Recovery

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-019 | Auto-scaling | N/A | — | Single Hetzner VPS. Not applicable at current scale. Containerization enables future horizontal scaling. |
| NFR-020 | Auto-healing | Partial | Docker restart policy | `restart: unless-stopped` in docker-compose. No orchestrator-level health check recovery (no Kubernetes). |
| NFR-021 | Readiness endpoint | Not Implemented | — | No `/ready` endpoint. Health check exists in ci-deploy.sh but not exposed as an HTTP endpoint for load balancers. |
| NFR-022 | Liveness endpoint | Not Implemented | — | No `/health` or `/live` endpoint. Docker health check relies on process existence, not application health. |

## Security

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-023 | Attack detection and blocking | Implemented | Cloudflare WAF | Cloudflare WAF with managed rulesets. Zero-trust tunnel means no exposed ports (ADR-008). |
| NFR-024 | Attack prevention | Implemented | Cloudflare, Supabase RLS | Cloudflare WAF + DDoS protection. Supabase Row-Level Security for data isolation. BYOK encryption for API keys (ADR-004). |
| NFR-025 | Rate limiting | Partial | Cloudflare | Cloudflare rate limiting on external traffic. No application-level rate limiting on WebSocket connections (roadmap P2 item). |
| NFR-026 | Encryption in-transit | Implemented | Cloudflare, HTTPS | All traffic via HTTPS through Cloudflare Tunnel. WebSocket connections encrypted via WSS. Supabase connections over TLS. |
| NFR-027 | Encryption at-rest | Partial | Supabase, BYOK | User API keys encrypted via AES-256-GCM with HKDF per-user derivation (ADR-004). Supabase database encrypted at rest. Server volumes not encrypted at Hetzner level. |
| NFR-028 | Geo distribution | Not Implemented | — | Single-region deployment (Hetzner EU). Cloudflare CDN provides edge caching for static assets. No multi-region application deployment. |

## Data Quality

| ID | Requirement | Status | Enforced By | Notes |
|----|-------------|--------|-------------|-------|
| NFR-029 | Data freshness | Partial | Supabase real-time | Supabase real-time subscriptions for conversation updates. Knowledge base is file-based (always fresh via git). No SLA on data staleness. |
| NFR-030 | Data accuracy | Partial | Supabase RLS, TypeScript | Type-safe data access via TypeScript. Row-Level Security prevents cross-user data leakage. No data quality monitoring or anomaly detection. |

## Summary

| Category | Implemented | Partial | Not Implemented | N/A |
|----------|-------------|---------|-----------------|-----|
| Observability | 0 | 2 | 5 | 0 |
| Resilience | 0 | 2 | 1 | 1 |
| Testing | 1 | 0 | 2 | 0 |
| Config & Delivery | 3 | 1 | 1 | 0 |
| Scaling & Recovery | 0 | 1 | 3 | 1 |
| Security | 3 | 2 | 1 | 0 |
| Data Quality | 0 | 2 | 0 | 0 |
| **Total** | **7** | **10** | **13** | **2** |
