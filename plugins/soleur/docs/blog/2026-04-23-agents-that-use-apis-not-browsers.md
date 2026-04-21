---
title: "Agents That Use APIs, Not Browsers (2026)"
seoTitle: "Agents That Use APIs, Not Browsers — Service Automation for Solo Founders | Soleur"
date: 2026-04-23
description: "Service automation for solo founders, built on direct APIs instead of server-side browsers. Open source. Encrypted tokens. 3 live integrations shipped."
ogImage: "blog/og-agents-that-use-apis-not-browsers.png"
tags:
  - announcement
  - service-automation
  - agent-native
  - company-as-a-service
---

Running a company alone means running a lot of vendor dashboards. Cloudflare, Stripe, Plausible, Resend, Hetzner — every one of them is a tab you keep open, a form you fill out, a setting you remember to flip. "Service automation" is the layer that lets an agent do that vendor work on your behalf, through the same APIs you would call by hand. Soleur's service automation shipped this week, and it is open source.

The bet underneath it: **agents should talk to APIs, not browsers.** We spent a month proving that out. Here is what we built, what we rejected, and what you can use today.

## What service automation is, in one sentence

Service automation is the capability that lets an AI agent provision, configure, and operate third-party services — create a DNS record, issue a Stripe refund, spin up a Plausible site — by calling vendor APIs directly, using tokens you own, on your behalf.

That sentence matters because the phrase "service automation" is doing real work in the industry right now. Some tools mean "an agent that drives a browser through a dashboard." Others mean "a workflow engine that chains Zapier-style connectors." We mean neither. We mean an agent that reads a vendor's API contract, holds your token, makes the HTTP call, handles the error, and writes the result back into your knowledge base.

If you want the short version: **your AI team gets credentials the same way a new hire does, and uses them the same way a senior engineer would — through the API, not the UI.**

## The fork in the road: browsers or APIs

Back in March we had a real decision to make. Service automation had been validated by founder interviews as one of the top-three requests. The open question was *how* an agent should actually carry out vendor work.

The popular answer in the agent industry is browser automation: run Playwright on a server, let the agent log into each dashboard, click through the forms, scrape the confirmation page. It looks great in demos. It is also how most "agent platforms" you see on launch day are actually built.

We rejected it. Four reasons, in the order they hurt:

1. **Attack surface.** Running a headless browser on your server that logs into external dashboards on behalf of your users removes nothing from the threat model — it adds to it. A server-side browser that follows redirects, loads arbitrary pages, and accepts scripted input is the canonical shape of a server-side-request-forgery primitive. Going API-first removes the server-side browser attack surface.
2. **Cost.** Our CFO flagged 2–4× infra-cost risk if we relied on browser automation. Headless browsers are RAM-hungry, they need long-lived sessions, and they fail in ways that require retries. A single REST call costs fractions of a cent. A browser session costs meaningful money.
3. **Drift.** Vendor dashboards change layout every few months. Vendor APIs change on deprecation schedules. If your automation tier is built on CSS selectors, every marketing redesign breaks your agent. If it is built on documented endpoints, you get years of stability.
4. **Trust.** When a founder hands an agent a credential, they want to know where it lives and what it does. "Our server never opens a browser to your dashboard" is a promise we can keep. "Our scraper won't do anything weird" is not.

So we went API-first and wrote the whole thing up in an architecture decision record. Three tiers, ordered by how much of the vendor universe they cover:

- **Tier 1 — Direct API + MCP.** Target allocation: roughly 80% of services. Design, not measurement.
- **Tier 2 — Local browser automation.** Target allocation: roughly 15%. This runs on the founder's own machine via our desktop app, not on our servers — different threat model entirely.
- **Tier 3 — Guided playbooks.** Target allocation: roughly 5%. Deep-linked dashboard instructions with human review gates, for the last mile where no API exists.

Those percentages are **design allocation, not measured**. We are shipping the scaffolding this week; the real distribution will land over the next quarter as we grow coverage.

## What shipped this week

The launch cut is honest about where we are. Three live API automations, two guided playbooks, fourteen BYOK providers wired into the credential layer.

**Live automations (Tier 1):**

- **Cloudflare MCP** — DNS records, zone settings, page rules. Agents can configure a domain end-to-end.
- **Stripe MCP** — customers, subscriptions, refunds, webhook endpoints. Your finance agent moves money with your token, not a stolen session.
- **Plausible API** — create sites, read traffic, pull goal conversions. *(Note: `/api/v1/sites` requires an Enterprise plan with a Sites API key — check your plan before wiring it up.)*

**Guided playbooks (Tier 3):**

- **Hetzner** — server provisioning, volume attach, firewall rules. Deep-linked into the Hetzner cloud console with a pre-filled config.
- **Resend** — domain verification, API key issuance, send-test flow.

**Credential layer (all tiers):**

- **14 BYOK providers** hooked into the credential store.
- **AES-256-GCM** for data-at-rest, **per-user HKDF-SHA256** key derivation. Your tokens, encrypted at rest, used by your agents. Each user's ciphertext is keyed to their own derived secret — a database leak does not yield usable credentials without the per-user material.

The PR was 1,685 lines across 15 files, added 20+ new tests, and shipped green against the existing suite. It is public, it is open source, and you can read every line.

<div class="cta-block">

**Ready to try it?**

<a href="https://app.soleur.ai/?utm_source=blog&utm_medium=cta&utm_campaign=agents-that-use-apis-not-browsers">Connect your repo</a> at app.soleur.ai and let an agent provision your first service.

</div>

## Why this matters if you are building alone

The hardest thing about being a solo founder is not the engineering. It is the other seventy percent — the vendor dashboards, the DNS flips at 11pm, the Stripe webhook you forgot to subscribe, the Plausible site you keep meaning to create for the new landing page.

Every one of those tasks is an API call. Every one of those API calls is something a well-briefed agent can handle, if — and only if — the agent has the credentials, the contract, and the authority.

Soleur's service automation gives the AI team all three. Credentials live in the encrypted BYOK layer. Contracts live in the MCP servers and playbook definitions. Authority lives in your repo — in the brand guide, the spec, the plan — where every agent reads from the same compounding knowledge base.

That last part is the lock-in break. An agent that can call Cloudflare for you is useful. An agent that can call Cloudflare for you *and* knows, from your brand guide, which domain owns which brand, *and* knows, from last week's learning file, that you always want `Always Use HTTPS` on — that is a teammate.

## Why APIs compound and browsers do not

This is the same argument we made in [why most agentic tools plateau](/blog/why-most-agentic-tools-plateau/), applied to a new surface.

A browser-based automation is a snowflake. Every site has its own DOM, its own auth flow, its own anti-bot heuristics. Every fix is a one-off. Nothing transfers.

An API-based automation is a contract. Once you have wrapped Stripe's API with agent-legible tools, the next agent that wants to issue a refund does not need to learn Stripe's dashboard — it needs to learn the contract, which is already documented, typed, and tested. The investment accrues.

That is what makes this release structurally different from the service-automation stories you see from browser-agent startups. We are not shipping a pile of scrapers. We are shipping a typed, tested, credentialed automation substrate that every agent in the organization can call the same way — from the marketing agent that wants to create a Plausible goal to the ops agent that wants to check a Hetzner firewall.

## What it looks like from the founder's seat

The mental model we optimized for: the founder never touches a token file, never inspects a response header, never writes a retry loop. They say what they want in plain language. The AI team handles the rest.

A concrete example. You are launching a new landing page on a fresh subdomain. In a pre-automation world, that is a thirty-minute errand: open Cloudflare, add the CNAME, wait for propagation, open Plausible, create the site, copy the script tag, go back to the code, paste it, deploy, check analytics, realize the goal is not firing, go back to Plausible, create the goal. Eleven context switches.

In the post-automation world it is one sentence to your ops agent: "Spin up `launch.soleur.ai`, point it at the production app, and track signups as a conversion." The agent resolves the domain against your Cloudflare zone, creates the DNS record, waits for propagation, creates the Plausible site, records the site ID in your knowledge base, writes the goal configuration, and comes back with a verification checklist. You approve. It is done.

The time savings are real but secondary. The primary value is that the steps are now **auditable and repeatable**. Every decision the agent made is committed to your repo. The next time you launch a subdomain, the agent reads the prior run, applies the same configuration, and only stops to ask about the deltas. This is the compounding effect applied to vendor work — the same substrate that makes engineering work compound now applies to the rest of the company.

## How this was built

For anyone interested in the architectural argument underneath the release: the full decision is written up as ADR-002 ("Three-Tier Service Automation") in the Soleur knowledge base. The short version is above. The long version walks through the CTO, CLO, and CFO objections to a server-side-browser design, the threat model we rejected, and the BYOK encryption scheme we adopted in its place. If you are building anything adjacent, it is worth reading as a template for "how to decide where agents get their hands dirty."

One rule we learned writing it: the moment you catch yourself saying "the agent will log in to the dashboard and…" — stop, and go find the API. In the rare case the vendor has no API, write a guided playbook and let the human keep the keys. Do not put a browser on your server.

## What is next

Three live automations is a beachhead, not a platform. The roadmap from here:

- Expand Tier 1 coverage: the shortlist is GitHub, Vercel, Supabase, and Mailchimp — all API-first, all natural fits for the MCP layer.
- Ship the first Tier 2 integrations through the desktop app, for vendors whose highest-value workflows genuinely require a browser session (think "download this monthly CSV report" or "confirm a TOTP prompt").
- Measure the actual tier distribution in production and report it. The 80/15/5 target needs real data behind it before we trust it.

If there is a vendor you want your AI team to handle, file it as an issue on the repo. We prioritize by founder pain, not vendor size.

<div class="cta-block">

**Start here.**

<a href="https://app.soleur.ai/?utm_source=blog&utm_medium=cta&utm_campaign=agents-that-use-apis-not-browsers">Connect your repo</a> at app.soleur.ai and let an agent provision your first service.

</div>
