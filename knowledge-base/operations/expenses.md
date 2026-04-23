---
last_updated: 2026-04-19
---

# Expenses

## Recurring

| Service | Provider | Category | Amount | Status | Renewal Date | Notes |
|---------|----------|----------|--------|--------|--------------|-------|
| GitHub Copilot | GitHub | dev-tools | 10.00 | active | 2026-03-14 | Business plan |
| Hetzner CX33 | Hetzner | hosting | 15.37 | active | 2026-04-01 | 4 vCPU, 8 GB RAM, 160 GB SSD, hel1 (web platform). DPA: must be signed via Hetzner Console |
| Hetzner Volume (20 GB) | Hetzner | hosting | 0.88 | active | 2026-04-01 | Persistent storage for /workspaces, hel1 (web platform) |
| Supabase Pro + Custom Domain | Supabase | saas | 35.00 | active | 2026-04-03 | Pro plan ($25/mo) + custom domain add-on ($10/mo). Custom domain: api.soleur.ai for branded OAuth callbacks |
| Stripe | Stripe | payments | 0.00 | test-mode | - | Payment processing for web platform. Live costs: 2.9% + $0.30/charge (US), 1.5% + EUR 0.25/charge (EU cards). No monthly minimum |
| soleur.ai | Cloudflare | domain | 70.00 | active | 2028-02-16 | 2-year registration required for .ai TLD. Also proxies app.soleur.ai (A record to Hetzner CX33, free tier) |
| Plausible Analytics | Plausible | saas | 9.00 | active | 2027-03-28 | Growth plan, 10K pageviews, EUR 9/mo. Annual renewal |
| X API | X Corp | api | 0.00 | active | - | Free tier, pay-per-use; @soleur_ai account |
| X API Basic (DEFERRED) | X Corp | api | 100.00 | deferred | - | DEFERRED: $100/mo Basic tier for fetch-mentions/timeline. Trigger: first paying customer or $500 MRR. See #497 |
| Sentry | Sentry | observability | 0.00 | free-tier | - | Error tracking + CSP report-uri for web platform. Org: jikigai, project: soleur-web-platform. Free tier: 5K errors/mo. Upgrade triggers: error volume |
| Better Stack | Better Stack | observability | 0.00 | free-tier | - | Uptime monitoring for app.soleur.ai/health (3-min interval) + status page at soleur-ai.betteruptime.com. Free tier: 10 monitors, 1 status page, email alerts. Upgrade trigger: first paying customer (custom domain, white-label, custom CSS) |
| Buttondown | Buttondown | saas | 0.00 | free-tier | - | Newsletter platform. Free tier: 100 subscribers, custom sending domain, API access. Upgrade trigger: >100 subscribers ($9/mo Basic) |
| Doppler | Doppler | secrets-mgmt | 0.00 | free-tier | - | Secrets management. Developer plan (free). Account: <ops@jikigai.com>. 6 configs: dev, dev_personal, ci, prd, prd_scheduled, prd_terraform. Upgrade triggers: team growth, audit logs |
| LinkedIn | LinkedIn | social | 0.00 | active | - | Company page + personal profile for content distribution. Free tier API access via LinkedIn Marketing Developer Platform |
| Bluesky | Bluesky | social | 0.00 | active | - | @soleur.ai account for content distribution. AT Protocol API (free, no tier limits) |
| Resend | Resend | email | 0.00 | free-tier | - | Transactional email API. Free tier: 100 emails/day, 3K emails/mo. Upgrade trigger: volume exceeds free tier ($20/mo for 50K emails) |
| Anthropic API (ux-audit) | Anthropic | api | 15.00 | active | - | Event-driven + monthly cron via `.github/workflows/scheduled-ux-audit.yml`. ~$3-$12/run × ≤3 runs/month. Threshold warning at $15/run in workflow output. Budget: $15/mo estimate; COO target ≤$12/run. |
| Claude Code Max 20x (seat 1) | Anthropic | dev-tools | 200.00 | active | 2026-05-01 | Max 20x tier ($200/mo/seat). Engineering tooling for Soleur development. Started 2026-02-01; seat 1 of 2 |
| Claude Code Max 20x (seat 2) | Anthropic | dev-tools | 200.00 | active | 2026-05-01 | Max 20x tier ($200/mo/seat). Engineering tooling for Soleur development. Started 2026-02-01; seat 2 of 2 |

## One-Time

| Service | Provider | Category | Amount | Status | Date | Notes |
|---------|----------|----------|--------|--------|------|-------|
| soleur.ai registration | Cloudflare | domain | 140.00 | active | 2026-02-16 | 2-year initial registration |

## Downstream Consumers

- **Finance:** [finance/cost-model.md](../finance/cost-model.md) — derived monthly burn and break-even model (R&D / product-COGS split). Refresh on every category subtotal shift >10 % per cost-model.md `review_cadence`.
