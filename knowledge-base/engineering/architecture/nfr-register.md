# Non-Functional Requirements Register

Tracks NFRs across the Soleur platform with per-container and per-link applicability. Each NFR maps to specific C4 containers and relationships, with evidence of enforcement at each point.

**Last updated:** 2026-03-27

## Status Legend

| Status | Meaning |
|--------|---------|
| Implemented | Fully in place and enforced |
| Partial | Some coverage but gaps remain |
| Not Implemented | Not yet addressed |
| N/A | Not applicable at current scale |

**System-level rollup rule:** Not Implemented > Partial > Implemented. N/A rows are excluded from rollup. An NFR where all containers are N/A has system-level N/A.

## Container & Link Inventory

Source of truth: `knowledge-base/engineering/architecture/diagrams/container.md` (12 containers, 6 external systems, 19 relationships).

### Container Classification

| Container | Type | C4 ID | Description |
|-----------|------|-------|-------------|
| Dashboard | Runtime | `dashboard` | React, Next.js conversation UI |
| API Routes | Runtime | `api` | Next.js API REST endpoints |
| Auth Module | Runtime (lifecycle shared with Dashboard/API Routes) | `auth` | Supabase Auth JWT and OAuth |
| Agent Runtime | Runtime | `claude` | Claude Code agent orchestration |
| Skill Loader | Runtime (lifecycle shared with Agent Runtime) | `skillloader` | Plugin discovery for skills and agents |
| Hook Engine | Runtime | `hooks` | PreToolUse syntactic guards |
| Skills | Passive | `skills` | 61 workflow skills (Markdown SKILL.md) |
| Agents | Passive | `agents` | 65 domain agents (Markdown definitions) |
| Knowledge Base | Passive | `kb` | Conventions, learnings, ADRs, specs (Markdown + YAML) |
| Supabase PostgreSQL | Infrastructure | `supabase` | Users, BYOK-encrypted API keys, sessions |
| Cloudflare Tunnel | Infrastructure | `tunnel` | Zero-trust inbound access (cloudflared) |
| Compute | Infrastructure | `hetzner` | Hetzner Cloud Docker host |

### Link Classification

| Link | Type | Protocol |
|------|------|----------|
| Founder -> Dashboard | Network | HTTPS |
| Dashboard -> API Routes | Network | HTTPS |
| API Routes -> Agent Runtime | Network | WebSocket |
| API Routes -> Supabase | Network | HTTPS |
| API Routes -> Stripe | Network | HTTPS |
| Agent Runtime -> Supabase | Network | HTTPS |
| Agent Runtime -> Anthropic | Network | HTTPS |
| Agent Runtime -> GitHub | Network | HTTPS/SSH |
| Auth Module -> Supabase | Network | HTTPS |
| Cloudflare Tunnel -> API Routes | Network | HTTPS |
| Doppler -> Agent Runtime | Network | CLI |
| Dashboard -> Plausible | Network | JS snippet |
| Agent Runtime -> Skill Loader | Internal | File I/O |
| Skill Loader -> Skills | Internal | Directory scan |
| Skill Loader -> Agents | Internal | Recursive scan |
| Hook Engine -> Agent Runtime | Internal | Event hook |
| Skills -> Knowledge Base | Internal | File I/O |
| Agents -> Knowledge Base | Internal | File I/O |
| Compute -> Agent Runtime | Infrastructure | Docker |

### NFR Scope Classification

| Scope | Description | Rows to Include |
|-------|-------------|-----------------|
| Container-scoped | Applies to individual containers | Container rows only |
| Link-scoped | Applies to relationships between containers | Link rows only |
| Both | Applies to containers and links | Both container and link rows |

---

## Observability

### NFR-001: Logging

**Category:** Observability | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | console.log | Next.js client/server console logging; no structured format |
| API Routes | Partial | console.log | Next.js API route logging; no structured format |
| Agent Runtime | Partial | Docker logs | Container stdout/stderr captured via `docker logs` |
| Hook Engine | Partial | stderr | Guard scripts write to stderr on block |
| Supabase PostgreSQL | Implemented | Supabase Dashboard | Built-in query and auth logs |
| Compute | Partial | Docker logs | `docker logs` available on host; no centralized aggregation |

### NFR-002: System-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No system metrics collection |
| API Routes | Not Implemented | — | No system metrics collection |
| Agent Runtime | Not Implemented | — | No system metrics collection |
| Supabase PostgreSQL | Partial | Supabase Dashboard | Built-in database usage metrics |
| Compute | Partial | Hetzner Console + disk-monitor.sh | Hetzner console metrics + disk usage alerts at 80%/95% via Discord (#1409) |

### NFR-003: Service-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No health dashboards or uptime monitoring |
| API Routes | Not Implemented | — | No uptime monitoring |
| Agent Runtime | Not Implemented | — | No service health tracking |
| Supabase PostgreSQL | Implemented | Supabase Dashboard | Built-in service health monitoring |

### NFR-004: Process-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No process metrics |
| API Routes | Not Implemented | — | No process metrics |
| Agent Runtime | Not Implemented | — | No process metrics; Docker restart provides basic recovery |
| Compute | Partial | Docker | `restart: unless-stopped` provides basic process recovery |

### NFR-005: Telemetry Dashboards

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Plausible Analytics | Page views, referrers, device data via JS snippet |
| API Routes | Not Implemented | — | No API telemetry dashboards |
| Agent Runtime | Not Implemented | — | No agent session telemetry |

### NFR-006: Distributed Tracing

**Category:** Observability | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard -> API Routes | Not Implemented | — | No trace context propagation |
| API Routes -> Agent Runtime | Not Implemented | — | No WebSocket trace context |
| Agent Runtime -> Anthropic | Not Implemented | — | No trace headers to external API |
| Agent Runtime -> Supabase | Not Implemented | — | No trace headers to database |
| Agent Runtime -> GitHub | Not Implemented | — | No trace headers to GitHub |

### NFR-006b: Overlay Change Events

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No deployment event correlation with metrics |
| API Routes | Not Implemented | — | No deployment event correlation |
| Agent Runtime | Not Implemented | — | GitHub Releases track versions but no performance correlation |

### NFR-033: Unified Logging Format

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | Next.js default console output format |
| API Routes | Not Implemented | — | Next.js default console output format |
| Agent Runtime | Not Implemented | — | Unstructured stdout/stderr |
| Hook Engine | Not Implemented | — | Ad-hoc stderr messages |

### NFR-044: Dynamic Logging Configuration

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No runtime log level control |
| API Routes | Not Implemented | — | No runtime log level control |
| Agent Runtime | Not Implemented | — | No runtime log level control |

---

## Resilience

### NFR-007: Circuit Breaker

**Category:** Resilience | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Agent Runtime -> Anthropic | Not Implemented | — | Failures propagate directly to agent session |
| Agent Runtime -> Supabase | Not Implemented | — | No fallback for database errors |
| API Routes -> Supabase | Not Implemented | — | No fallback for database errors |
| API Routes -> Stripe | Not Implemented | — | No fallback for payment failures |
| Agent Runtime -> GitHub | Not Implemented | — | No fallback for git operations |

### NFR-008: Low Latency

**Category:** Resilience | **Scope:** Link | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Founder -> Dashboard | Implemented | Cloudflare CDN | Static assets cached at edge |
| Dashboard -> API Routes | Implemented | Cloudflare Tunnel | Low-latency internal routing |
| API Routes -> Agent Runtime | Partial | WebSocket | Real-time streaming; latency depends on Anthropic response time |
| Cloudflare Tunnel -> API Routes | Implemented | cloudflared | Local tunnel, minimal added latency |

### NFR-009: High Throughput

**Category:** Resilience | **Scope:** Container | **System-Level Status:** N/A

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| API Routes | N/A | — | Single-founder usage; not a current constraint |
| Agent Runtime | N/A | — | Per-user sessions provide natural sharding |
| Compute | N/A | — | Single VPS sufficient for current scale |

### NFR-010: Linear Horizontal Scalability

**Category:** Resilience | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Next.js, Docker | Stateless; supports multiple instances |
| API Routes | Partial | Next.js, Docker | Stateless but WebSocket sessions are per-instance |
| Agent Runtime | Partial | Docker | Containerized; natural per-user sharding; no load balancer |
| Compute | Partial | Hetzner Cloud | Can add VPS instances; no orchestrator configured |

### NFR-045: API Backwards Compatibility

**Category:** Resilience | **Scope:** Link | **System-Level Status:** N/A

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard -> API Routes | N/A | — | Internal API with single consumer |
| API Routes -> Agent Runtime | N/A | — | Internal WebSocket protocol |

---

## Testing

### NFR-011: Automated Functional Testability

**Category:** Testing | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Bun test | Web platform test suite |
| API Routes | Implemented | Bun test | API endpoint tests |
| Agent Runtime | Implemented | Bun test, Lefthook | 964+ plugin tests; pre-commit hooks enforce |
| Hook Engine | Implemented | Bun test | Hook behavior tests |
| Skills | Implemented | Bun test | Component count validation tests |

### NFR-012: Automated Performance Testability

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No load testing |
| API Routes | Not Implemented | — | No API performance benchmarks |
| Agent Runtime | Not Implemented | — | Performance-oracle agent provides advisory; no automated benchmarks |

### NFR-013: Synthetic Monitoring

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | Plausible tracks real users; no synthetic probes |
| API Routes | Not Implemented | — | No synthetic endpoint monitoring |

### NFR-037: FOSS Compatibility Scanning

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | npm dependencies not license-scanned |
| Agent Runtime | Not Implemented | — | Plugin dependencies not license-scanned |

### NFR-046: Automated Failure Injection Testing

**Category:** Testing | **Scope:** Both | **System-Level Status:** N/A

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | N/A | — | Single-instance scale; chaos engineering not applicable |
| API Routes | N/A | — | Single-instance scale; chaos engineering not applicable |
| Agent Runtime | N/A | — | Single-instance scale; chaos engineering not applicable |
| Dashboard -> API Routes | N/A | — | No fault injection infrastructure |
| API Routes -> Agent Runtime | N/A | — | No fault injection infrastructure |
| Agent Runtime -> Anthropic | N/A | — | No fault injection infrastructure |

---

## Configuration & Delivery

### NFR-014: Externalized Environment Configuration

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Doppler | Secrets injected via `doppler run` |
| API Routes | Implemented | Doppler | Shared environment with Dashboard |
| Agent Runtime | Implemented | Doppler | `doppler run` for all secrets (ADR-007) |
| Supabase PostgreSQL | Implemented | Supabase Dashboard | Configuration via dashboard; no local .env |

### NFR-015: Documentation of Internal Services

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Knowledge Base, Git | Component docs, ADRs, specs |
| API Routes | Implemented | Knowledge Base, Git | API documented in specs |
| Agent Runtime | Implemented | Knowledge Base | 20 ADRs, 120+ learnings, constitution.md |
| Skills | Implemented | SKILL.md | Each skill self-documents via SKILL.md |
| Agents | Implemented | Agent .md | Each agent self-documents via markdown definition |
| Knowledge Base | Implemented | Git | Architecture decisions, conventions, specs, plans |

### NFR-016: Continuous Automated Delivery

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | GitHub Actions | Push-to-deploy via Cloudflare Tunnel webhook |
| API Routes | Implemented | GitHub Actions | Shared deployment with Dashboard |
| Agent Runtime | Implemented | GitHub Actions | ci-deploy.sh handles Docker build and health checks |
| Skills | Implemented | Git, semver labels | Version bumped by CI on merge (ADR-017) |

### NFR-017: Graceful Shutdown

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | Docker | SIGTERM with 10s grace; no in-flight request draining |
| API Routes | Partial | Docker | SIGTERM with 10s grace; WebSocket connections dropped |
| Agent Runtime | Partial | Docker | SIGTERM with 10s grace; active agent sessions terminated |

### NFR-018: Canary Upgrade

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | Single-instance deployment; rollback via previous Docker tag |
| API Routes | Not Implemented | — | Shared deployment with Dashboard |
| Agent Runtime | Not Implemented | — | Single-instance; no canary strategy |

### NFR-032: Automatic Rollback on KPI Alert

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No KPI-based rollback triggers |
| API Routes | Not Implemented | — | No error rate monitoring for rollback |
| Agent Runtime | Not Implemented | — | No deployment health scoring |

### NFR-034: Stable Dependency Versioning

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | bun.lockb | Lockfile committed; pinned dependency versions |
| API Routes | Implemented | bun.lockb | Shared lockfile with Dashboard |
| Agent Runtime | Implemented | bun.lockb | Plugin lockfile committed |

### NFR-035: Semantic Versioning

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Agent Runtime | Implemented | GitHub Actions | semver labels -> git tags -> GitHub Releases (ADR-017) |
| Skills | Implemented | GitHub Actions | Version derived from plugin release tags |

### NFR-036: Immutable Releases

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | GHCR | Docker image tagged with SHA and version |
| Agent Runtime | Implemented | GHCR | Docker image tagged with SHA and version |
| Skills | Implemented | GitHub Releases | Release artifacts immutable once published |

### NFR-043: Rolling Update Deployment

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | Single instance; replaced atomically |
| API Routes | Not Implemented | — | Shared deployment with Dashboard |
| Agent Runtime | Not Implemented | — | Single instance; no rolling strategy |

---

## Scaling & Recovery

### NFR-019: Auto-Scaling

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** N/A

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | N/A | — | Single Hetzner VPS; not applicable at current scale |
| API Routes | N/A | — | Single Hetzner VPS |
| Agent Runtime | N/A | — | Single Hetzner VPS |
| Compute | N/A | — | No orchestrator for auto-scaling |

### NFR-020: Auto-Healing

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | Docker | `restart: unless-stopped`; no health check recovery |
| API Routes | Partial | Docker | `restart: unless-stopped` |
| Agent Runtime | Partial | Docker | `restart: unless-stopped` |
| Supabase PostgreSQL | Implemented | Supabase | Managed service with automatic recovery |

### NFR-021: Readiness Endpoint

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No `/ready` endpoint |
| API Routes | Not Implemented | — | No `/ready` endpoint |
| Agent Runtime | Not Implemented | — | ci-deploy.sh health check not exposed as HTTP endpoint |

### NFR-022: Liveness Endpoint

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No `/health` or `/live` endpoint |
| API Routes | Not Implemented | — | No liveness endpoint |
| Agent Runtime | Not Implemented | — | Docker health check relies on process existence |

### NFR-031: Periodic Backup & Recovery

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Supabase PostgreSQL | Partial | Supabase | Daily automatic backups (Pro plan); no tested restore procedure |
| Knowledge Base | Implemented | Git | Full history in Git; recoverable via `git checkout` |
| Compute | Not Implemented | — | No server volume backups on Hetzner |

---

## Security

### NFR-023: Attack Detection and Blocking

**Category:** Security | **Scope:** Both | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Cloudflare WAF | Managed rulesets for web traffic |
| API Routes | Implemented | Cloudflare WAF | WAF rules on API endpoints |
| Agent Runtime | Implemented | Cloudflare Tunnel | No exposed ports (ADR-008) |
| Founder -> Dashboard | Implemented | Cloudflare WAF | WAF inspects all inbound traffic |
| Cloudflare Tunnel -> API Routes | Implemented | Zero Trust | Tunnel-only access; no exposed ports |

### NFR-024: Attack Prevention

**Category:** Security | **Scope:** Both | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Implemented | Cloudflare | DDoS protection at edge |
| API Routes | Implemented | Cloudflare | DDoS protection |
| Supabase PostgreSQL | Implemented | Supabase RLS | Row-Level Security for data isolation |
| Agent Runtime | Implemented | BYOK | AES-256-GCM with HKDF per-user derivation (ADR-004) |
| Founder -> Dashboard | Implemented | Cloudflare | DDoS + WAF |
| API Routes -> Supabase | Implemented | Supabase RLS | Row-level data isolation |

### NFR-025: Rate Limiting

**Category:** Security | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Founder -> Dashboard | Implemented | Cloudflare | Rate limiting on external traffic |
| Dashboard -> API Routes | Partial | Cloudflare | HTTP rate limiting; no WebSocket rate limiting |
| API Routes -> Agent Runtime | Not Implemented | — | No rate limiting on WebSocket connections |

### NFR-026: Encryption In-Transit

**Category:** Security | **Scope:** Link | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Founder -> Dashboard | Implemented | Cloudflare | TLS terminated at Cloudflare edge |
| Dashboard -> API Routes | Implemented | HTTPS | Internal HTTPS via Next.js |
| API Routes -> Agent Runtime | Implemented | WebSocket WSS | Encrypted WebSocket protocol |
| API Routes -> Supabase | Implemented | TLS | Supabase requires TLS connections |
| API Routes -> Stripe | Implemented | HTTPS | Stripe SDK enforces HTTPS |
| Agent Runtime -> Supabase | Implemented | TLS | Supabase requires TLS |
| Agent Runtime -> Anthropic | Implemented | HTTPS | Anthropic SDK enforces HTTPS |
| Agent Runtime -> GitHub | Implemented | HTTPS/SSH | Both protocols encrypted |
| Auth Module -> Supabase | Implemented | HTTPS | Supabase Auth client uses HTTPS |
| Cloudflare Tunnel -> API Routes | Implemented | HTTPS | Tunnel uses encrypted connection |
| Doppler -> Agent Runtime | Implemented | HTTPS | Doppler CLI uses HTTPS for secret fetch |
| Dashboard -> Plausible | Implemented | HTTPS | JS snippet loaded via HTTPS |

### NFR-027: Encryption At-Rest

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Supabase PostgreSQL | Implemented | Supabase | Database encrypted at rest by default |
| Agent Runtime | Implemented | BYOK | User API keys: AES-256-GCM + HKDF per-user (ADR-004) |
| Compute | Not Implemented | — | Hetzner server volumes not encrypted at disk level |

### NFR-028: Geo Distribution

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | Cloudflare CDN | Static assets cached at edge; SSR single-region |
| API Routes | Not Implemented | — | Single Hetzner EU region |
| Agent Runtime | Not Implemented | — | Single Hetzner EU region |
| Supabase PostgreSQL | Not Implemented | — | Single Supabase region |

### NFR-038: Least Privilege Container Images

**Category:** Security | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | Dockerfile | Node.js base image; not fully hardened |
| Agent Runtime | Partial | Dockerfile | Runs as non-root in some configurations |

### NFR-039: Container Image Security Scanning

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Not Implemented | — | No Trivy/Snyk/Grype scanning in CI |
| Agent Runtime | Not Implemented | — | No image vulnerability scanning |

### NFR-040: Data Retention Policy

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Supabase PostgreSQL | Not Implemented | — | No automated data lifecycle management |
| Agent Runtime | Not Implemented | — | Session data retained indefinitely |

### NFR-041: Link-Level Access Control

**Category:** Security | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Founder -> Dashboard | Implemented | Cloudflare Zero Trust | Access policies on tunnel |
| Cloudflare Tunnel -> API Routes | Implemented | cloudflared | No exposed ports; tunnel-only access |
| API Routes -> Supabase | Implemented | Supabase RLS | Row-level security policies |
| Agent Runtime -> Supabase | Implemented | Supabase RLS | Service role key scoped by RLS |
| Dashboard -> API Routes | Partial | Session auth | Session-based auth; no network-level ACL |
| API Routes -> Agent Runtime | Partial | WebSocket auth | WebSocket auth; no network-level ACL |

### NFR-047: Certificate Scope Control

**Category:** Security | **Scope:** Link | **System-Level Status:** Implemented

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Founder -> Dashboard | Implemented | Cloudflare | Per-domain certificates; no wildcards |
| Cloudflare Tunnel -> API Routes | Implemented | Cloudflare | Origin certificates per tunnel |

---

## Data Quality

### NFR-029: Data Freshness

**Category:** Data Quality | **Scope:** Both | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Dashboard | Partial | Supabase real-time | Real-time subscriptions for conversations; no SLA on staleness |
| Agent Runtime | Partial | Supabase | Direct database access; freshness depends on query timing |
| Knowledge Base | Implemented | Git | File-based; always fresh via git pull in worktrees |
| API Routes -> Supabase | Partial | Supabase | No caching layer; queries always hit database |
| Agent Runtime -> Supabase | Partial | Supabase | No caching layer |

### NFR-030: Data Accuracy

**Category:** Data Quality | **Scope:** Both | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| API Routes | Partial | TypeScript | Type-safe data access; no data quality monitoring |
| Agent Runtime | Partial | TypeScript | Type-safe; no anomaly detection |
| Supabase PostgreSQL | Implemented | Supabase RLS | Row-Level Security prevents cross-user data leakage |
| API Routes -> Supabase | Implemented | Supabase RLS | RLS enforces data isolation per query |
| Agent Runtime -> Supabase | Implemented | Supabase RLS | Service role respects RLS policies |

### NFR-042: LLM-Ready Documentation

**Category:** Data Quality | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Status | Enforced By | Evidence |
|----------------|--------|-------------|----------|
| Skills | Implemented | SKILL.md | Each skill has structured markdown consumable by Claude |
| Agents | Implemented | Agent .md | Each agent has structured markdown with routing description |
| Knowledge Base | Implemented | Markdown | AGENTS.md, constitution.md loaded every session |
| Dashboard | Partial | — | No llms.txt or structured API documentation for LLM consumption |

---

## Summary

System-level statuses derived from per-container rollup using precedence: Not Implemented > Partial > Implemented (N/A excluded).

| Category | Implemented | Partial | Not Implemented | N/A | Total |
|----------|-------------|---------|-----------------|-----|-------|
| Observability | 0 | 1 | 8 | 0 | 9 |
| Resilience | 0 | 2 | 1 | 2 | 5 |
| Testing | 1 | 0 | 3 | 1 | 5 |
| Configuration & Delivery | 6 | 1 | 3 | 0 | 10 |
| Scaling & Recovery | 0 | 1 | 3 | 1 | 5 |
| Security | 4 | 1 | 6 | 0 | 11 |
| Data Quality | 0 | 3 | 0 | 0 | 3 |
| **Total** | **11** | **9** | **24** | **4** | **48** |
