# Learning: CDN services require dual legal basis for authenticated vs unauthenticated traffic

## Problem

The DPD Section 4.2 processor table listed Cloudflare's legal basis as blanket "Contract performance (Article 6(1)(b))" for all Web Platform traffic. However, Cloudflare's CDN/proxy processes IP addresses and request headers for all visitors — including unauthenticated visitors who have no contractual relationship with Jikigai. Contract performance under Article 6(1)(b) requires a contract to exist between the controller and the data subject.

## Solution

Changed the Cloudflare legal basis in the DPD processor table to a dual basis:
- **Contract performance (Article 6(1)(b))** for authenticated users (who accepted the T&C)
- **Legitimate interest (Article 6(1)(f))** for unauthenticated traffic (website operator's interest in secure, performant delivery)

This mirrors the pattern already used for GitHub Pages in the Docs Site processors table, where legitimate interest covers documentation site visitors who have no contractual relationship.

External validation: Cloudflare's own GDPR Trust Hub and community discussions confirm that legitimate interest is the standard GDPR legal basis for CDN processing of unauthenticated visitor traffic.

## Key Insight

Any processor that sits in front of a web application (CDN, WAF, reverse proxy, load balancer) processes traffic from both authenticated and unauthenticated visitors. A single legal basis of "contract performance" is legally insufficient for the unauthenticated portion because Article 6(1)(b) requires a contract to be in place. The dual-basis pattern (contract for authenticated, legitimate interest for unauthenticated) is the standard approach. When adding a new infrastructure processor to legal documents, always ask: "Does this processor see traffic from visitors who haven't accepted our T&C?"

## Session Errors

1. Ralph Loop setup script path was wrong (`./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` does not exist) — resolved by falling back to `./plugins/soleur/scripts/setup-ralph-loop.sh`
2. GitHub API returned HTTP 502 during draft PR creation — transient error, PR was created successfully despite the warning

## Tags
category: legal-compliance
module: data-protection-disclosure
