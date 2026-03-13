---
title: "GitHub Pages + Cloudflare Custom Domain: End-to-End Wiring Workflow"
category: integration-issues
tags: [github-pages, cloudflare, dns, ssl, cert-provisioning, infra-security, agent-autonomy, base-href]
module: infra-security-agent
symptoms:
  - "526 Invalid SSL Certificate error from Cloudflare"
  - "GitHub Pages DNS checks fail for apex domain on project repos"
  - "Enforce HTTPS unavailable in GitHub Pages settings"
  - "CSS/fonts/images not loading after custom domain switch"
  - "Docs site showing stale agent/skill counts"
severity: high
date: 2026-02-16
---

# GitHub Pages + Cloudflare Custom Domain Wiring

## Problem

Wiring `soleur.ai` to GitHub Pages through Cloudflare required 10+ manual round-trips between the agent and user. Each step surfaced a new blocker that the agent should have anticipated and handled autonomously.

## Root Causes (Sequential Blockers)

### 1. SSL Full (Strict) enabled before cert provisioning

The agent upgraded Cloudflare SSL to Full (Strict) immediately after creating DNS records. GitHub Pages had not yet provisioned a Let's Encrypt cert for the custom domain -- it was still presenting the default `*.github.io` wildcard cert. Full (Strict) validates hostname match on the origin cert, so Cloudflare correctly rejected it with a 526 error.

**Fix:** Start with SSL mode "Full" (not Strict). Only upgrade to Strict after verifying the origin cert covers the custom domain.

### 2. Cloudflare proxied DNS blocks Let's Encrypt ACME validation

All DNS records were created with `proxied: true` (orange cloud). GitHub Pages uses HTTP-01 ACME challenges to provision Let's Encrypt certs, which requires reaching the actual GitHub Pages server directly. Cloudflare's proxy intercepts this, so GitHub sees Cloudflare IPs and cannot validate domain ownership.

**Fix:** Create DNS records as DNS-only (grey cloud) initially. Re-enable proxying only after GitHub confirms cert provisioning is complete.

### 3. GitHub Pages project repos require `www` custom domain

For project repos (e.g., `jikig-ai/soleur` vs the org repo `jikig-ai.github.io`), setting the custom domain to the apex `soleur.ai` fails DNS checks. Setting it to `www.soleur.ai` passes because the CNAME resolves correctly to `jikig-ai.github.io`.

**Fix:** Always configure `www.soleur.ai` as the custom domain for project repos. GitHub handles apex-to-www redirect automatically.

### 4. `<base href="/soleur/">` breaks asset paths on custom domain

The docs site was built for `jikig-ai.github.io/soleur/` where the `/soleur/` prefix is needed. On a custom domain, the site is served from `/`, so the base href causes all asset URLs to resolve to `soleur.ai/soleur/css/style.css` (404).

**Fix:** Change `<base href="/soleur/">` to `<base href="/">` and update all absolute `og:url`/`og:image` meta tags, `sitemap.xml`, and `robots.txt` URLs. Add a `CNAME` file to the docs directory for GitHub Pages persistence.

### 5. Docs site not updated with latest components

Three agents added in recent PRs (infra-security, ops-advisor, ops-research) were missing from the docs site. The docs HTML pages are manually maintained and `release-docs` was not run after those agents were added.

**Fix:** Run `release-docs` as part of the ship workflow whenever agents/skills/commands are added.

## Correct Ordering for GitHub Pages + Cloudflare

The entire workflow should execute in this sequence without user intervention:

```
1. Create DNS records as DNS-ONLY (grey cloud):
   - 4x A records -> GitHub Pages IPs (185.199.108-111.153)
   - CNAME www -> <org>.github.io

2. Set SSL mode to "Full" (not Strict)

3. Enable Always Use HTTPS + Min TLS 1.2

4. Use `gh api` to set custom domain on the repo:
   gh api repos/<org>/<repo>/pages -X PUT -f cname="www.<domain>"

5. Create TXT challenge record if GitHub requests one

6. VERIFY cert provisioning (poll until done):
   openssl s_client -connect <github-pages-ip>:443 -servername <domain>
   # Wait until cert SAN includes the custom domain

7. ONLY THEN: Re-enable Cloudflare proxying on all records

8. ONLY THEN: Upgrade SSL to Full (Strict)

9. Enable HSTS (max-age=31536000, includeSubDomains, preload)

10. VERIFY end-to-end using playwright/agent-browser:
    - Navigate to https://<domain>
    - Check HTTP status 200
    - Verify CSS loaded (check computed styles or screenshot)
    - Verify no console errors
```

## Key Insight: Agent Autonomy Gap

The infra-security agent treated each step as a stopping point requiring user confirmation. The agent should own the full workflow end-to-end:

1. **Use `gh` CLI** to configure GitHub Pages settings programmatically instead of asking the user to do it manually in the browser
2. **Poll for cert provisioning** using `openssl s_client` in a loop instead of asking the user to "check and let me know"
3. **Verify with playwright/agent-browser** that the site loads with full styling instead of asking the user to open a browser
4. **Anticipate the correct ordering** (DNS-only first, cert, then proxy, then strict SSL) instead of learning it through failures

The agent should only stop for user input when there's a genuine decision to make (e.g., "which repo hosts your Pages site?"), not for mechanical verification steps it can automate.

## Prevention

- Update the infra-security agent's GitHub Pages wiring recipe to follow the correct ordering above
- Add automated verification steps using `curl`, `openssl`, and `agent-browser`
- Add `release-docs` to the ship workflow checklist when agents/skills are modified
- Consider adding a `CNAME` file to the docs directory as part of initial GitHub Pages setup

## Related

- `knowledge-base/learnings/2026-02-13-base-href-breaks-local-dev-server.md` -- base href local testing workaround
- `knowledge-base/learnings/2026-02-16-inline-only-output-for-security-agents.md` -- security agent output constraints
- `knowledge-base/learnings/2026-02-13-static-docs-site-from-brand-guide.md` -- docs site build workflow
