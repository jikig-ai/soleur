# Soleur Platform — System Context (C4 Level 1)

Generated: 2026-03-27 · Migrated to LikeC4: 2026-06-03

Rendered interactively from the canonical LikeC4 model in this directory
(`spec.c4`, `model.c4`, `views.c4`). Click the **Soleur Platform** box to drill
down into the container view.

```likec4-view
context
```

## Notes

- Web App is a thin view/control layer over the CLI engine (ADR-003)
- CLI engine preserves 100% of orchestration capability — agents execute on cloud-hosted Claude Code instances
- BYOK encryption isolates per-user API keys via AES-256-GCM with HKDF derivation (ADR-004)
- All infrastructure provisioned via Terraform with R2 remote backend (ADR-006, ADR-019)
- Secrets managed via Doppler with runtime injection — no plaintext .env on disk (ADR-007)
- Zero-trust access via Cloudflare Tunnel — server invisible to port scanners (ADR-008)
- Stripe in test mode — subscription billing via checkout sessions and webhooks
- Plausible Analytics for privacy-focused tracking (no cookies, GDPR-compliant)
