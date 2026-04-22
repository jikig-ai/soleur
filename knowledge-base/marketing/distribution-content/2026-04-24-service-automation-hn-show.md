---
title: "Show HN: Soleur — open-source agents that call APIs, not browsers"
type: hn-show
publish_date: "2026-04-24"
channels:
status: draft
pr_reference: "#1921"
issue_reference: "#1944"
blog_url: "/blog/agents-that-use-apis-not-browsers/"
---

## Hacker News Show

**Show HN: Soleur — open-source agents that call APIs, not browsers**

Soleur is an open-source agent orchestrator aimed at solo founders — one builder, a lot of vendor accounts, no time to babysit dashboards. This week we shipped the "service automation" layer, and the architectural decision underneath it is probably the more interesting HN read.

The core choice was: when an agent needs to create a DNS record on Cloudflare, issue a Stripe refund, or spin up a Plausible site, does it drive a server-side browser, or does it call the vendor API directly? We rejected the server-side browser path. Reasons, written up as an architecture decision record (ADR-002, "Three-Tier Service Automation" — [knowledge-base/engineering/architecture/decisions/ADR-002-three-tier-service-automation.md](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/decisions/ADR-002-three-tier-service-automation.md)): CTO flagged that a persistent headless browser with vendor cookies is a server-side request-forgery-adjacent attack surface; CLO flagged that automating dashboards the vendor's TOS wasn't written for creates agency-liability exposure; CFO flagged 2–4× infra-cost risk if we relied on browser automation at scale. An API-based tier is typed, testable, auditable, and the contract survives UI redesigns.

So the design is three tiers: Tier 1 direct APIs via MCP servers (Cloudflare, Stripe, Plausible shipped); Tier 2 local-browser automation in the desktop app when the vendor genuinely has no API and the workflow needs session state (think "download this month's CSV report"); Tier 3 guided playbooks with deep links when neither fits (Hetzner provisioning, Resend domain verification). Credentials are BYOK: AES-256-GCM at rest with per-user HKDF-SHA256 key derivation — a database leak does not yield usable tokens without the per-user material.

### What this is NOT

The 80/15/5 target split (API / local-browser / guided) is a design allocation we intend to measure, not a measurement we are reporting. We do not yet have production telemetry to confirm the distribution; the number reflects where we think services will fall based on the Tier 1 shortlist we have audited. Call it aspirational. The release shipped three live Tier 1 integrations, two guided playbooks, and 14 BYOK providers wired into the credential store — that part is counted, not claimed.

Blog post with the founder-outcome framing (API vs. browser, why it compounds, what a founder's workflow actually looks like): <https://soleur.ai/blog/agents-that-use-apis-not-browsers/?utm_source=hn&utm_medium=community&utm_campaign=agents-that-use-apis-not-browsers>

Source: <https://github.com/jikig-ai/soleur> (Apache 2.0). Feedback on the three-tier model, the BYOK scheme, or the rejection of server-side browsers is very welcome — it is the kind of review that is hard to find outside HN.
