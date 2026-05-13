# Soleur Platform — System Context (C4 Level 1)

Generated: 2026-05-13 (visual redesign per SOL-40, was 2026-03-27)

```mermaid
C4Context
title System Context diagram for Soleur Platform

UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")

Person(founder, "Founder", "Solo founder using Soleur as their AI organization")

Enterprise_Boundary(b0, "Soleur Platform") {
    System(webapp, "Web Application", "Next.js PWA providing dashboard and conversation UI")
    System(engine, "Cloud CLI Engine", "Claude Code instances executing agent workflows")
    SystemDb(supabase, "Supabase", "Auth, PostgreSQL database, and file storage")
}

System_Ext(cloudflare, "Cloudflare", "DNS, CDN, R2 storage, and zero-trust tunnel")
System_Ext(doppler, "Doppler", "Centralized secrets management with runtime injection")
System_Ext(anthropic, "Anthropic API", "Claude LLM for agent reasoning and tool use")
System_Ext(github, "GitHub", "Source control, CI/CD, issue tracking, and releases")
System_Ext(thirdparty, "Third-Party Services", "Discord + Stripe + Plausible — see Details")

Rel(founder, webapp, "Interacts via browser", "HTTPS")
Rel(webapp, engine, "Thin view/control layer", "WebSocket")
Rel(webapp, supabase, "Auth and data", "HTTPS")
Rel(engine, supabase, "Sessions and encrypted keys", "HTTPS")
Rel(cloudflare, webapp, "Tunnel, DNS, CDN", "HTTPS")
Rel(doppler, engine, "Runtime secrets", "CLI")
Rel(engine, anthropic, "LLM calls with BYOK keys", "HTTPS")
Rel(engine, github, "Git operations and CI", "HTTPS/SSH")
BiRel(webapp, thirdparty, "Checkout / webhooks / page events", "HTTPS")
Rel(engine, thirdparty, "Notifications", "Webhook")
```

## Details

**`thirdparty` group contains** (original Mermaid aliases preserved for grep-ability):

- `discord` — Discord — community notifications and release announcements
- `stripe` — Stripe — payment processing and subscription billing (test mode)
- `plausible` — Plausible Analytics — privacy-focused page-view tracking

All three are external SaaS systems with low individual visual signal at the system-context level. The `BiRel(webapp, thirdparty)` covers Stripe checkout + Stripe webhooks + Plausible JS events. The `Rel(engine, thirdparty)` covers Discord webhook notifications.

## Notes

- Web App is a thin view/control layer over the CLI engine (ADR-003)
- CLI engine preserves 100% of orchestration capability — agents execute on cloud-hosted Claude Code instances
- BYOK encryption isolates per-user API keys via AES-256-GCM with HKDF derivation (ADR-004)
- All infrastructure provisioned via Terraform with R2 remote backend (ADR-006, ADR-019)
- Secrets managed via Doppler with runtime injection — no plaintext .env on disk (ADR-007)
- Zero-trust access via Cloudflare Tunnel — server invisible to port scanners (ADR-008)
- Stripe in test mode — subscription billing via checkout sessions and webhooks
- Plausible Analytics for privacy-focused tracking (no cookies, GDPR-compliant)
