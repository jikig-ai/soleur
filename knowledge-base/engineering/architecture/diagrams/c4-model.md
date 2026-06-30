# Soleur Platform — C4 Model

Generated: 2026-03-27 · Migrated to LikeC4: 2026-06-03

The interactive C4 model, rendered from the canonical LikeC4 sources in this
directory (`spec.c4`, `model.c4`, `views.c4`). The diagram opens at **System
Context (L1)**. Click the **Soleur Platform** box to drill down into
**Containers (L2)**, then the **Soleur Plugin** box to drill down into
**Components (L3)** — all in place, without leaving this page.

```likec4-view
context
```

## System Context (C4 L1)

- Web App is a thin view/control layer over the CLI engine (ADR-003)
- CLI engine preserves 100% of orchestration capability — agents execute on cloud-hosted Claude Code instances
- BYOK encryption isolates per-user API keys via AES-256-GCM with HKDF derivation (ADR-004)
- All infrastructure provisioned via Terraform with R2 remote backend (ADR-006, ADR-019)
- Secrets managed via Doppler with runtime injection — no plaintext .env on disk (ADR-007)
- Zero-trust access via Cloudflare Tunnel — server invisible to port scanners (ADR-008)
- Stripe in test mode — subscription billing via checkout sessions and webhooks
- Plausible Analytics for privacy-focused tracking (no cookies, GDPR-compliant)
- Operator email-triage inbox ingests inbound mail via a Resend webhook (svix-verified); statutory/operational triage notifications go back out via Resend (ADR-066)
- Durable server-side triggers (cron, one-shot, HTTP-armed reminders) run on self-hosted Inngest (ADR-030)

## Containers (C4 L2)

Click the **Soleur Platform** box in the diagram above to drill into this view.

- Plugin has flat skill structure (skills don't nest) and recursive agent discovery (ADR-016)
- Three enforcement tiers: hooks (syntactic), skills (semantic), prose (advisory) — ADR-011
- Knowledge base compounds ADRs, learnings, and conventions across sessions
- Worktree isolation enforced via PreToolUse hooks (ADR-009)
- Version derived from git tags at merge time, not committed files (ADR-017)
- Stripe handles subscription checkout sessions and payment webhooks (test mode)
- Plausible analytics embedded as JS snippet in the web dashboard (no cookies, GDPR-compliant)
- Inngest durable trigger layer is self-hosted on Hetzner with a dedicated EU Supabase Postgres (config + run history) and Redis with AOF persistence that survives a host re-provision (ADR-030, #5450)

## Components (C4 L3)

The deepest level — drill into the **Soleur Plugin** box (inside the Containers
view) to reach it.

- Three commands (go, sync, help) are the only user-facing entry points (ADR-016)
- One-shot orchestrates the full pipeline: plan → work → review → compound → ship (ADR-015)
- Domain leaders (CTO, CMO, CPO) participate in brainstorm Phase 0.5 and plan Phase 2.5 (ADR-013)
- CTO agent detects architectural decisions and recommends `/soleur:architecture create`
- Architecture-strategist checks ADR coverage during review as advisory finding
- 8 review agents run in parallel during `/soleur:review` — only architecture-strategist shown here
