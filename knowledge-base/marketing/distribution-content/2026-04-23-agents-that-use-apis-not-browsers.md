---
title: "Agents That Use APIs, Not Browsers"
type: milestone-announcement
publish_date: "2026-04-23"
channels: discord, x, bluesky, linkedin-personal, linkedin-company
status: draft
pr_reference: "#1921"
issue_reference: "#1944"
roadmap_item: "Phase 3: Make it Sticky"
blog_url: /blog/agents-that-use-apis-not-browsers/
---

## Discord

Service automation shipped.

Your AI team now provisions vendor services through APIs, not server-side browsers. Live today: Cloudflare MCP, Stripe MCP, Plausible API. Plus 14 BYOK providers with AES-256-GCM encryption at rest.

Tokens stay encrypted. No scrapers on our servers. Open source, on main, today.

Full writeup: <https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=discord&utm_medium=community&utm_campaign=agents-that-use-apis-not-browsers>

---

## X/Twitter Thread

**Tweet 1**
Agents should talk to APIs, not browsers.

We shipped service automation this week. 3 live integrations. 2 guided playbooks. 14 BYOK providers. Tokens encrypted at rest. Zero server-side scrapers.

Open source. On main. Today.

**Tweet 2**
The popular answer in the agent industry is browser automation — run Playwright on a server, let the agent click through dashboards.

Cool demo. Terrible architecture.

API-first removes the server-side browser attack surface. No redirects, no DOM drift, no scraped sessions.

**Tweet 3**
Our CFO flagged 2-4x infra-cost risk if we relied on browser automation.

Headless browsers are RAM-hungry. Sessions are long-lived. Failures need retries.

A REST call costs fractions of a cent. A browser session costs real money.

We picked the one that compounds.

**Tweet 4**
Live Tier 1 today:

- Cloudflare MCP (DNS, zones)
- Stripe MCP (customers, refunds)
- Plausible API (sites, goals)

Guided playbooks for Hetzner + Resend.

14 BYOK providers. AES-256-GCM at rest. Per-user HKDF-SHA256 derivation.

Your tokens. Encrypted. Used by your agents.

**Tweet 5**
Target allocation, not measured: Tier 1 APIs cover ~80%, local browser ~15%, guided playbooks ~5%.

The scaffolding ships this week. The real distribution lands as coverage grows next quarter.

Shipping the measurement before the marketing.

**Tweet 6**
One sentence to your ops agent:

"Spin up launch.soleur.ai, point it at prod, track signups as a conversion."

DNS record, Plausible site, goal config, verification checklist — all auditable, all committed to your repo.

**Tweet 7**
PR #1921: 1,685 LOC. 15 files. 30 new tests. 674 passing.

Open source. Your credentials. Your repo.

<https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=x&utm_medium=social&utm_campaign=agents-that-use-apis-not-browsers>

# solofounder

---

## Bluesky

Agents should talk to APIs, not browsers. Service automation shipped — Cloudflare, Stripe, Plausible. Tokens encrypted at rest. Open source.

<https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=bluesky&utm_medium=social&utm_campaign=agents-that-use-apis-not-browsers>

---

## LinkedIn Personal

Running a company alone means running a lot of vendor dashboards. Cloudflare, Stripe, Plausible, Resend, Hetzner — every one is a tab you keep open, a form you fill, a setting you remember to flip.

This week I shipped the layer that lets an AI agent do that work for you. Service automation is live on Soleur today, and it is open source.

The architectural bet: agents should talk to APIs, not browsers. The popular answer in the agent industry is server-side browser automation — let Playwright log into each dashboard and click through forms. It demos well. It also adds attack surface, costs 2-4x more in infrastructure, and breaks every time a vendor ships a redesign.

I went the other way. Three live Tier 1 integrations on day one: Cloudflare MCP, Stripe MCP, Plausible API. Two guided playbooks for vendors where an API alone is not enough — Hetzner and Resend. Fourteen BYOK providers wired into a credential layer using AES-256-GCM encryption with per-user HKDF-SHA256 key derivation. A database leak does not yield usable credentials without the per-user material.

The founder's experience is a single sentence to an agent: "Spin up launch.soleur.ai, track signups as a conversion." DNS, Plausible site, goal config, verification — all done, all logged, all committed to your repo. The next launch reuses the pattern. The compounding effect applied to vendor work.

Full writeup on the architecture decision: <https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=agents-that-use-apis-not-browsers>

# solofounder #buildinpublic

---

## LinkedIn Company Page

Soleur now ships service automation — the layer that lets AI agents provision and configure vendor services on a founder's behalf.

The approach is API-first by design. Agents call Cloudflare, Stripe, and Plausible through direct REST APIs and MCP servers, not server-side browsers. Tokens are encrypted at rest with AES-256-GCM and per-user HKDF-SHA256 key derivation.

Live today:

- Three Tier 1 automations: Cloudflare MCP, Stripe MCP, Plausible API
- Two guided playbooks: Hetzner and Resend
- Fourteen BYOK providers wired into the credential layer

Target allocation across tiers — roughly 80% direct API, 15% local browser on the founder's own machine, 5% guided — is a design allocation that will be measured and reported as coverage grows.

This is the third major capability in Phase 3 of the Soleur roadmap. Open source, on main, today.

Full details: <https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=linkedin-company&utm_medium=social&utm_campaign=agents-that-use-apis-not-browsers>
