---
last_updated: 2026-03-28
---

# Expenses

## Recurring

| Service | Provider | Category | Amount | Status | Renewal Date | Notes |
|---------|----------|----------|--------|--------|--------------|-------|
| GitHub Copilot | GitHub | dev-tools | 10.00 | active | 2026-03-14 | Business plan |
| Hetzner CX22 | Hetzner | hosting | 5.83 | active | 2026-03-01 | 2 vCPU, 4 GB RAM, 40 GB SSD, eu-central (telegram-bridge) |
| Hetzner CX33 | Hetzner | hosting | 15.37 | active | 2026-04-01 | 4 vCPU, 8 GB RAM, 160 GB SSD, hel1 (web platform). DPA: must be signed via Hetzner Console |
| Hetzner Volume (20 GB) | Hetzner | hosting | 0.88 | active | 2026-04-01 | Persistent storage for /workspaces, hel1 (web platform) |
| Supabase | Supabase | saas | 0.00 | free-tier | - | Auth + PostgreSQL for web platform. Upgrade triggers: 500 MB DB, 50K MAU, 1 GB file storage, 2 GB bandwidth. Pro tier: $25/mo |
| Stripe | Stripe | payments | 0.00 | test-mode | - | Payment processing for web platform. Live costs: 2.9% + $0.30/charge (US), 1.5% + EUR 0.25/charge (EU cards). No monthly minimum |
| soleur.ai | Cloudflare | domain | 70.00 | active | 2028-02-16 | 2-year registration required for .ai TLD. Also proxies app.soleur.ai (A record to Hetzner CX33, free tier) |
| Plausible Analytics | Plausible | saas | 9.00 | active | 2027-03-28 | Growth plan, 10K pageviews, EUR 9/mo. Annual renewal |
| X API | X Corp | api | 0.00 | active | - | Free tier, pay-per-use; @soleur_ai account |
| X API Basic (DEFERRED) | X Corp | api | 100.00 | deferred | - | DEFERRED: $100/mo Basic tier for fetch-mentions/timeline. Trigger: first paying customer or $500 MRR. See #497 |
| Sentry | Sentry | observability | 0.00 | free-tier | - | Error tracking + CSP report-uri for web platform. Org: jikigai, project: soleur-web-platform. Free tier: 5K errors/mo. Upgrade triggers: error volume |
| Better Stack | Better Stack | observability | 0.00 | free-tier | - | Uptime monitoring for app.soleur.ai/health (3-min interval). Free tier: 10 monitors, email alerts. Upgrade triggers: Telegram/SMS alerts, phone calls |

## One-Time

| Service | Provider | Category | Amount | Status | Date | Notes |
|---------|----------|----------|--------|--------|------|-------|
| soleur.ai registration | Cloudflare | domain | 140.00 | active | 2026-02-16 | 2-year initial registration |
