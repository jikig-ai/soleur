---
last_updated: 2026-04-10
---

# Domains

| Domain | Registrar | Renewal Date | Nameservers | Notes |
|--------|-----------|--------------|-------------|-------|
| soleur.ai | Cloudflare | 2028-02-16 | ns1.cloudflare.com, ns2.cloudflare.com | Primary brand domain |

## DNS Records

| Type | Name | Content | Proxied | Notes |
|------|------|---------|---------|-------|
| A | soleur.ai | 185.199.108.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.109.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.110.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.111.153 | Yes | GitHub Pages |
| CNAME | <www.soleur.ai> | jikig-ai.github.io | Yes | GitHub Pages |
| TXT | _github-pages-challenge-jikig-ai.soleur.ai | 8fcc2ac37a5abcac6cd2c71556053f | No | Domain verification |

## Security Configuration

| Setting | Value |
|---------|-------|
| SSL Mode | Full (Strict) |
| Always Use HTTPS | On |
| Minimum TLS Version | 1.2 |
| HSTS | max-age=31536000; includeSubDomains; preload |
| HSTS Preload | Submitted 2026-03-20 — pending inclusion in Chromium preload list |
| DNSSEC | Enabled (pending DS propagation to .ai registry — expected active by 2026-04-12) |
| X-Content-Type-Options | nosniff |

## HSTS Preload Commitment

The domain `soleur.ai` was submitted to the [HSTS preload list](https://hstspreload.org) on 2026-03-20. This means:

- All subdomains must serve HTTPS. Creating an HTTP-only subdomain will be unreachable for browsers using the preload list.
- Removal from the list takes months (requires removing the `preload` directive from headers, submitting a removal request at hstspreload.org, and waiting for a Chromium release cycle).
- New subdomains created via Terraform must have Cloudflare proxy enabled (`proxied = true`) with `Always Use HTTPS` active.
