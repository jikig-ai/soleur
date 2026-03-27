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

Source of truth: `knowledge-base/engineering/architecture/diagrams/container.md` (13 containers, 7 external systems, 22 relationships).

### Container Classification

| Container | Type | C4 ID | Description |
|-----------|------|-------|-------------|
| Dashboard | Runtime | `dashboard` | React, Next.js conversation UI |
| API Routes | Runtime | `api` | Next.js API REST endpoints |
| Auth Module | Runtime | `auth` | Supabase Auth JWT and OAuth |
| Agent Runtime | Runtime | `claude` | Claude Code agent orchestration |
| Skill Loader | Runtime | `skillloader` | Plugin discovery for skills and agents |
| Hook Engine | Runtime | `hooks` | PreToolUse syntactic guards |
| Telegram Bot | Runtime | `tgbot` | grammy bridge to Claude Code CLI |
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
| Telegram Bot -> Telegram API | Network | grammy SDK |
| Telegram Bot -> Agent Runtime | Network | Subprocess |
| Agent Runtime -> Skill Loader | Internal | File I/O |
| Skill Loader -> Skills | Internal | Directory scan |
| Skill Loader -> Agents | Internal | Recursive scan |
| Hook Engine -> Agent Runtime | Internal | Event hook |
| Skills -> Knowledge Base | Internal | File I/O |
| Agents -> Knowledge Base | Internal | File I/O |
| Compute -> Agent Runtime | Infrastructure | Docker |
| Compute -> Telegram Bot | Infrastructure | Docker |

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

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | console.log | Next.js client/server console logging; no structured format |
| API Routes | Yes | Partial | console.log | Next.js API route logging; no structured format |
| Agent Runtime | Yes | Partial | Docker logs | Container stdout/stderr captured via `docker logs` |
| Hook Engine | Yes | Partial | stderr | Guard scripts write to stderr on block |
| Telegram Bot | Yes | Partial | grammy logger | grammy framework logging; Docker container logs |
| Supabase PostgreSQL | Yes | Implemented | Supabase Dashboard | Built-in query and auth logs |
| Compute | Yes | Partial | Docker logs | `docker logs` available on host; no centralized aggregation |

### NFR-002: System-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No system metrics collection |
| API Routes | Yes | Not Implemented | — | No system metrics collection |
| Agent Runtime | Yes | Not Implemented | — | No system metrics collection |
| Telegram Bot | Yes | Not Implemented | — | No system metrics collection |
| Supabase PostgreSQL | Yes | Partial | Supabase Dashboard | Built-in database usage metrics |
| Compute | Yes | Partial | Hetzner Console | Basic server metrics (CPU, RAM, disk) |

### NFR-003: Service-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No health dashboards or uptime monitoring |
| API Routes | Yes | Not Implemented | — | No uptime monitoring |
| Agent Runtime | Yes | Not Implemented | — | No service health tracking |
| Telegram Bot | Yes | Not Implemented | — | No bot availability monitoring |
| Supabase PostgreSQL | Yes | Implemented | Supabase Dashboard | Built-in service health monitoring |

### NFR-004: Process-Level Monitoring

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No process metrics |
| API Routes | Yes | Not Implemented | — | No process metrics |
| Agent Runtime | Yes | Not Implemented | — | No process metrics; Docker restart provides basic recovery |
| Telegram Bot | Yes | Not Implemented | — | No process metrics |
| Compute | Yes | Partial | Docker | `restart: unless-stopped` provides basic process recovery |

### NFR-005: Telemetry Dashboards

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Plausible Analytics | Page views, referrers, device data via JS snippet |
| API Routes | Yes | Not Implemented | — | No API telemetry dashboards |
| Agent Runtime | Yes | Not Implemented | — | No agent session telemetry |
| Telegram Bot | Yes | Not Implemented | — | No bot usage telemetry |

### NFR-006: Distributed Tracing

**Category:** Observability | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard -> API Routes | Yes | Not Implemented | — | No trace context propagation |
| API Routes -> Agent Runtime | Yes | Not Implemented | — | No WebSocket trace context |
| Agent Runtime -> Anthropic | Yes | Not Implemented | — | No trace headers to external API |
| Agent Runtime -> Supabase | Yes | Not Implemented | — | No trace headers to database |
| Agent Runtime -> GitHub | Yes | Not Implemented | — | No trace headers to GitHub |

### NFR-006b: Overlay Change Events

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No deployment event correlation with metrics |
| API Routes | Yes | Not Implemented | — | No deployment event correlation |
| Agent Runtime | Yes | Not Implemented | — | GitHub Releases track versions but no performance correlation |
| Telegram Bot | Yes | Not Implemented | — | No deployment event tracking |

### NFR-033: Unified Logging Format

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | Next.js default console output format |
| API Routes | Yes | Not Implemented | — | Next.js default console output format |
| Agent Runtime | Yes | Not Implemented | — | Unstructured stdout/stderr |
| Hook Engine | Yes | Not Implemented | — | Ad-hoc stderr messages |
| Telegram Bot | Yes | Not Implemented | — | grammy default format; differs from other containers |

### NFR-044: Dynamic Logging Configuration

**Category:** Observability | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No runtime log level control |
| API Routes | Yes | Not Implemented | — | No runtime log level control |
| Agent Runtime | Yes | Not Implemented | — | No runtime log level control |
| Telegram Bot | Yes | Not Implemented | — | No runtime log level control |

---

## Resilience

### NFR-007: Circuit Breaker

**Category:** Resilience | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Agent Runtime -> Anthropic | Yes | Not Implemented | — | Failures propagate directly to agent session |
| Agent Runtime -> Supabase | Yes | Not Implemented | — | No fallback for database errors |
| API Routes -> Supabase | Yes | Not Implemented | — | No fallback for database errors |
| API Routes -> Stripe | Yes | Not Implemented | — | No fallback for payment failures |
| Agent Runtime -> GitHub | Yes | Not Implemented | — | No fallback for git operations |
| Telegram Bot -> Telegram API | Yes | Not Implemented | — | grammy retry plugin available but not configured |

### NFR-008: Low Latency

**Category:** Resilience | **Scope:** Link | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Founder -> Dashboard | Yes | Implemented | Cloudflare CDN | Static assets cached at edge |
| Dashboard -> API Routes | Yes | Implemented | Cloudflare Tunnel | Low-latency internal routing |
| API Routes -> Agent Runtime | Yes | Partial | WebSocket | Real-time streaming; latency depends on Anthropic response time |
| Cloudflare Tunnel -> API Routes | Yes | Implemented | cloudflared | Local tunnel, minimal added latency |

### NFR-009: High Throughput

**Category:** Resilience | **Scope:** Container | **System-Level Status:** N/A

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| API Routes | Yes | N/A | — | Single-founder usage; not a current constraint |
| Agent Runtime | Yes | N/A | — | Per-user sessions provide natural sharding |
| Compute | Yes | N/A | — | Single VPS sufficient for current scale |

### NFR-010: Linear Horizontal Scalability

**Category:** Resilience | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Next.js, Docker | Stateless; supports multiple instances |
| API Routes | Yes | Partial | Next.js, Docker | Stateless but WebSocket sessions are per-instance |
| Agent Runtime | Yes | Partial | Docker | Containerized; natural per-user sharding; no load balancer |
| Telegram Bot | Yes | Partial | Docker | Containerized; single-instance by design (one bot token) |
| Compute | Yes | Partial | Hetzner Cloud | Can add VPS instances; no orchestrator configured |

### NFR-045: API Backwards Compatibility

**Category:** Resilience | **Scope:** Link | **System-Level Status:** N/A

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard -> API Routes | Yes | N/A | — | Internal API with single consumer |
| API Routes -> Agent Runtime | Yes | N/A | — | Internal WebSocket protocol |
| Telegram Bot -> Agent Runtime | Yes | N/A | — | Internal subprocess interface |

---

## Testing

### NFR-011: Automated Functional Testability

**Category:** Testing | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Bun test | Web platform test suite |
| API Routes | Yes | Implemented | Bun test | API endpoint tests |
| Agent Runtime | Yes | Implemented | Bun test, Lefthook | 964+ plugin tests; pre-commit hooks enforce |
| Hook Engine | Yes | Implemented | Bun test | Hook behavior tests |
| Telegram Bot | Yes | Implemented | Bun test | Bridge test suite |
| Skills | Yes | Implemented | Bun test | Component count validation tests |

### NFR-012: Automated Performance Testability

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No load testing |
| API Routes | Yes | Not Implemented | — | No API performance benchmarks |
| Agent Runtime | Yes | Not Implemented | — | Performance-oracle agent provides advisory; no automated benchmarks |

### NFR-013: Synthetic Monitoring

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | Plausible tracks real users; no synthetic probes |
| API Routes | Yes | Not Implemented | — | No synthetic endpoint monitoring |

### NFR-037: FOSS Compatibility Scanning

**Category:** Testing | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | npm dependencies not license-scanned |
| Agent Runtime | Yes | Not Implemented | — | Plugin dependencies not license-scanned |
| Telegram Bot | Yes | Not Implemented | — | npm dependencies not license-scanned |

### NFR-046: Automated Failure Injection Testing

**Category:** Testing | **Scope:** Both | **System-Level Status:** N/A

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| All runtime containers | Yes | N/A | — | Chaos engineering not applicable at current single-instance scale |
| All network links | Yes | N/A | — | No fault injection infrastructure |

---

## Configuration & Delivery

### NFR-014: Externalized Environment Configuration

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Doppler | Secrets injected via `doppler run` |
| API Routes | Yes | Implemented | Doppler | Shared environment with Dashboard |
| Agent Runtime | Yes | Implemented | Doppler | `doppler run` for all secrets (ADR-007) |
| Telegram Bot | Yes | Implemented | Doppler | Bot token via Doppler |
| Supabase PostgreSQL | Yes | Implemented | Supabase Dashboard | Configuration via dashboard; no local .env |

### NFR-015: Documentation of Internal Services

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Knowledge Base, Git | Component docs, ADRs, specs |
| API Routes | Yes | Implemented | Knowledge Base, Git | API documented in specs |
| Agent Runtime | Yes | Implemented | Knowledge Base | 20 ADRs, 120+ learnings, constitution.md |
| Skills | Yes | Implemented | SKILL.md | Each skill self-documents via SKILL.md |
| Agents | Yes | Implemented | Agent .md | Each agent self-documents via markdown definition |
| Knowledge Base | Yes | Implemented | Git | Architecture decisions, conventions, specs, plans |

### NFR-016: Continuous Automated Delivery

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | GitHub Actions | Push-to-deploy via Cloudflare Tunnel webhook |
| API Routes | Yes | Implemented | GitHub Actions | Shared deployment with Dashboard |
| Agent Runtime | Yes | Implemented | GitHub Actions | ci-deploy.sh handles Docker build and health checks |
| Telegram Bot | Yes | Implemented | GitHub Actions | Separate deployment workflow |
| Skills | Yes | Implemented | Git, semver labels | Version bumped by CI on merge (ADR-017) |

### NFR-017: Graceful Shutdown

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | Docker | SIGTERM with 10s grace; no in-flight request draining |
| API Routes | Yes | Partial | Docker | SIGTERM with 10s grace; WebSocket connections dropped |
| Agent Runtime | Yes | Partial | Docker | SIGTERM with 10s grace; active agent sessions terminated |
| Telegram Bot | Yes | Partial | Docker | SIGTERM with 10s grace; no graceful webhook deregistration |

### NFR-018: Canary Upgrade

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | Single-instance deployment; rollback via previous Docker tag |
| API Routes | Yes | Not Implemented | — | Shared deployment with Dashboard |
| Agent Runtime | Yes | Not Implemented | — | Single-instance; no canary strategy |
| Telegram Bot | Yes | Not Implemented | — | Single-instance; no canary strategy |

### NFR-032: Automatic Rollback on KPI Alert

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No KPI-based rollback triggers |
| API Routes | Yes | Not Implemented | — | No error rate monitoring for rollback |
| Agent Runtime | Yes | Not Implemented | — | No deployment health scoring |
| Telegram Bot | Yes | Not Implemented | — | No automated rollback mechanism |

### NFR-034: Stable Dependency Versioning

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | bun.lockb | Lockfile committed; pinned dependency versions |
| API Routes | Yes | Implemented | bun.lockb | Shared lockfile with Dashboard |
| Agent Runtime | Yes | Implemented | bun.lockb | Plugin lockfile committed |
| Telegram Bot | Yes | Implemented | bun.lockb | Separate lockfile committed |

### NFR-035: Semantic Versioning

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Agent Runtime | Yes | Implemented | GitHub Actions | semver labels -> git tags -> GitHub Releases (ADR-017) |
| Skills | Yes | Implemented | GitHub Actions | Version derived from plugin release tags |

### NFR-036: Immutable Releases

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | GHCR | Docker image tagged with SHA and version |
| Agent Runtime | Yes | Implemented | GHCR | Docker image tagged with SHA and version |
| Telegram Bot | Yes | Implemented | GHCR | Docker image tagged with SHA and version |
| Skills | Yes | Implemented | GitHub Releases | Release artifacts immutable once published |

### NFR-043: Rolling Update Deployment

**Category:** Configuration & Delivery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | Single instance; replaced atomically |
| API Routes | Yes | Not Implemented | — | Shared deployment with Dashboard |
| Agent Runtime | Yes | Not Implemented | — | Single instance; no rolling strategy |
| Telegram Bot | Yes | Not Implemented | — | Single instance; no rolling strategy |

---

## Scaling & Recovery

### NFR-019: Auto-Scaling

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** N/A

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | N/A | — | Single Hetzner VPS; not applicable at current scale |
| API Routes | Yes | N/A | — | Single Hetzner VPS |
| Agent Runtime | Yes | N/A | — | Single Hetzner VPS |
| Telegram Bot | Yes | N/A | — | Single Hetzner VPS |
| Compute | Yes | N/A | — | No orchestrator for auto-scaling |

### NFR-020: Auto-Healing

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | Docker | `restart: unless-stopped`; no health check recovery |
| API Routes | Yes | Partial | Docker | `restart: unless-stopped` |
| Agent Runtime | Yes | Partial | Docker | `restart: unless-stopped` |
| Telegram Bot | Yes | Partial | Docker | `restart: unless-stopped` |
| Supabase PostgreSQL | Yes | Implemented | Supabase | Managed service with automatic recovery |

### NFR-021: Readiness Endpoint

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No `/ready` endpoint |
| API Routes | Yes | Not Implemented | — | No `/ready` endpoint |
| Agent Runtime | Yes | Not Implemented | — | ci-deploy.sh health check not exposed as HTTP endpoint |
| Telegram Bot | Yes | Not Implemented | — | No readiness probe |

### NFR-022: Liveness Endpoint

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No `/health` or `/live` endpoint |
| API Routes | Yes | Not Implemented | — | No liveness endpoint |
| Agent Runtime | Yes | Not Implemented | — | Docker health check relies on process existence |
| Telegram Bot | Yes | Not Implemented | — | No liveness endpoint |

### NFR-031: Periodic Backup & Recovery

**Category:** Scaling & Recovery | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Supabase PostgreSQL | Yes | Partial | Supabase | Daily automatic backups (Pro plan); no tested restore procedure |
| Knowledge Base | Yes | Implemented | Git | Full history in Git; recoverable via `git checkout` |
| Compute | Yes | Not Implemented | — | No server volume backups on Hetzner |

---

## Security

### NFR-023: Attack Detection and Blocking

**Category:** Security | **Scope:** Both | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Cloudflare WAF | Managed rulesets for web traffic |
| API Routes | Yes | Implemented | Cloudflare WAF | WAF rules on API endpoints |
| Agent Runtime | Yes | Implemented | Cloudflare Tunnel | No exposed ports (ADR-008) |
| Founder -> Dashboard | Yes | Implemented | Cloudflare WAF | WAF inspects all inbound traffic |
| Cloudflare Tunnel -> API Routes | Yes | Implemented | Zero Trust | Tunnel-only access; no exposed ports |

### NFR-024: Attack Prevention

**Category:** Security | **Scope:** Both | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Implemented | Cloudflare | DDoS protection at edge |
| API Routes | Yes | Implemented | Cloudflare | DDoS protection |
| Supabase PostgreSQL | Yes | Implemented | Supabase RLS | Row-Level Security for data isolation |
| Agent Runtime | Yes | Implemented | BYOK | AES-256-GCM with HKDF per-user derivation (ADR-004) |
| Founder -> Dashboard | Yes | Implemented | Cloudflare | DDoS + WAF |
| API Routes -> Supabase | Yes | Implemented | Supabase RLS | Row-level data isolation |

### NFR-025: Rate Limiting

**Category:** Security | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Founder -> Dashboard | Yes | Implemented | Cloudflare | Rate limiting on external traffic |
| Dashboard -> API Routes | Yes | Partial | Cloudflare | HTTP rate limiting; no WebSocket rate limiting |
| API Routes -> Agent Runtime | Yes | Not Implemented | — | No rate limiting on WebSocket connections |
| Telegram Bot -> Telegram API | Yes | Implemented | Telegram API | Telegram enforces rate limits server-side |

### NFR-026: Encryption In-Transit

**Category:** Security | **Scope:** Link | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Founder -> Dashboard | Yes | Implemented | Cloudflare | TLS terminated at Cloudflare edge |
| Dashboard -> API Routes | Yes | Implemented | HTTPS | Internal HTTPS via Next.js |
| API Routes -> Agent Runtime | Yes | Implemented | WebSocket WSS | Encrypted WebSocket protocol |
| API Routes -> Supabase | Yes | Implemented | TLS | Supabase requires TLS connections |
| API Routes -> Stripe | Yes | Implemented | HTTPS | Stripe SDK enforces HTTPS |
| Agent Runtime -> Supabase | Yes | Implemented | TLS | Supabase requires TLS |
| Agent Runtime -> Anthropic | Yes | Implemented | HTTPS | Anthropic SDK enforces HTTPS |
| Agent Runtime -> GitHub | Yes | Implemented | HTTPS/SSH | Both protocols encrypted |
| Auth Module -> Supabase | Yes | Implemented | HTTPS | Supabase Auth client uses HTTPS |
| Cloudflare Tunnel -> API Routes | Yes | Implemented | HTTPS | Tunnel uses encrypted connection |
| Doppler -> Agent Runtime | Yes | Implemented | HTTPS | Doppler CLI uses HTTPS for secret fetch |
| Dashboard -> Plausible | Yes | Implemented | HTTPS | JS snippet loaded via HTTPS |
| Telegram Bot -> Telegram API | Yes | Implemented | HTTPS | grammy SDK enforces HTTPS |

### NFR-027: Encryption At-Rest

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Supabase PostgreSQL | Yes | Implemented | Supabase | Database encrypted at rest by default |
| Agent Runtime | Yes | Implemented | BYOK | User API keys: AES-256-GCM + HKDF per-user (ADR-004) |
| Compute | Yes | Not Implemented | — | Hetzner server volumes not encrypted at disk level |

### NFR-028: Geo Distribution

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | Cloudflare CDN | Static assets cached at edge; SSR single-region |
| API Routes | Yes | Not Implemented | — | Single Hetzner EU region |
| Agent Runtime | Yes | Not Implemented | — | Single Hetzner EU region |
| Telegram Bot | Yes | Not Implemented | — | Single Hetzner EU region |
| Supabase PostgreSQL | Yes | Not Implemented | — | Single Supabase region |

### NFR-038: Least Privilege Container Images

**Category:** Security | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | Dockerfile | Node.js base image; not fully hardened |
| Agent Runtime | Yes | Partial | Dockerfile | Runs as non-root in some configurations |
| Telegram Bot | Yes | Partial | Dockerfile | Node.js base image; room for hardening |

### NFR-039: Container Image Security Scanning

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Not Implemented | — | No Trivy/Snyk/Grype scanning in CI |
| Agent Runtime | Yes | Not Implemented | — | No image vulnerability scanning |
| Telegram Bot | Yes | Not Implemented | — | No image vulnerability scanning |

### NFR-040: Data Retention Policy

**Category:** Security | **Scope:** Container | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Supabase PostgreSQL | Yes | Not Implemented | — | No automated data lifecycle management |
| Agent Runtime | Yes | Not Implemented | — | Session data retained indefinitely |

### NFR-041: Link-Level Access Control

**Category:** Security | **Scope:** Link | **System-Level Status:** Not Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Founder -> Dashboard | Yes | Implemented | Cloudflare Zero Trust | Access policies on tunnel |
| Cloudflare Tunnel -> API Routes | Yes | Implemented | cloudflared | No exposed ports; tunnel-only access |
| API Routes -> Supabase | Yes | Implemented | Supabase RLS | Row-level security policies |
| Agent Runtime -> Supabase | Yes | Implemented | Supabase RLS | Service role key scoped by RLS |
| Dashboard -> API Routes | Yes | Partial | Session auth | Session-based auth; no network-level ACL |
| API Routes -> Agent Runtime | Yes | Partial | WebSocket auth | WebSocket auth; no network-level ACL |
| Telegram Bot -> Agent Runtime | Yes | Not Implemented | — | Subprocess; no access control beyond process isolation |

### NFR-047: Certificate Scope Control

**Category:** Security | **Scope:** Link | **System-Level Status:** Implemented

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Founder -> Dashboard | Yes | Implemented | Cloudflare | Per-domain certificates; no wildcards |
| Cloudflare Tunnel -> API Routes | Yes | Implemented | Cloudflare | Origin certificates per tunnel |
| Telegram Bot -> Telegram API | Yes | Implemented | Telegram | Platform-managed certificates |

---

## Data Quality

### NFR-029: Data Freshness

**Category:** Data Quality | **Scope:** Both | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Dashboard | Yes | Partial | Supabase real-time | Real-time subscriptions for conversations; no SLA on staleness |
| Agent Runtime | Yes | Partial | Supabase | Direct database access; freshness depends on query timing |
| Knowledge Base | Yes | Implemented | Git | File-based; always fresh via git pull in worktrees |
| API Routes -> Supabase | Yes | Partial | Supabase | No caching layer; queries always hit database |
| Agent Runtime -> Supabase | Yes | Partial | Supabase | No caching layer |

### NFR-030: Data Accuracy

**Category:** Data Quality | **Scope:** Both | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| API Routes | Yes | Partial | TypeScript | Type-safe data access; no data quality monitoring |
| Agent Runtime | Yes | Partial | TypeScript | Type-safe; no anomaly detection |
| Supabase PostgreSQL | Yes | Implemented | Supabase RLS | Row-Level Security prevents cross-user data leakage |
| API Routes -> Supabase | Yes | Implemented | Supabase RLS | RLS enforces data isolation per query |
| Agent Runtime -> Supabase | Yes | Implemented | Supabase RLS | Service role respects RLS policies |

### NFR-042: LLM-Ready Documentation

**Category:** Data Quality | **Scope:** Container | **System-Level Status:** Partial

| Container/Link | Applicable | Status | Enforced By | Evidence |
|----------------|------------|--------|-------------|----------|
| Skills | Yes | Implemented | SKILL.md | Each skill has structured markdown consumable by Claude |
| Agents | Yes | Implemented | Agent .md | Each agent has structured markdown with routing description |
| Knowledge Base | Yes | Implemented | Markdown | AGENTS.md, constitution.md loaded every session |
| Dashboard | Yes | Partial | — | No llms.txt or structured API documentation for LLM consumption |

---

## Summary

System-level statuses derived from per-container rollup using precedence: Not Implemented > Partial > Implemented (N/A excluded).

| Category | Implemented | Partial | Not Implemented | N/A | Total |
|----------|-------------|---------|-----------------|-----|-------|
| Observability | 0 | 1 | 8 | 0 | 9 |
| Resilience | 0 | 2 | 1 | 2 | 5 |
| Testing | 1 | 0 | 3 | 1 | 5 |
| Config & Delivery | 6 | 1 | 3 | 0 | 10 |
| Scaling & Recovery | 0 | 1 | 3 | 1 | 5 |
| Security | 4 | 1 | 6 | 0 | 11 |
| Data Quality | 0 | 3 | 0 | 0 | 3 |
| **Total** | **11** | **9** | **24** | **4** | **48** |
