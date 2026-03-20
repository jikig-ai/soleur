# Domain Purchase Brainstorm

**Date:** 2026-02-16
**Status:** Purchased

## What We're Building

Selecting and purchasing the primary domain name for the Soleur brand ("The Company-as-a-Service Platform"). Currently no domains are owned -- `domains.md` and `expenses.md` have incorrect entries listing `soleur.dev` as owned, which needs correcting.

## Why This Matters

The brand needs a web presence. The domain choice signals positioning: `.ai` says "AI company," `.dev` says "developer tool," `.io` says "tech startup." For a Company-as-a-Service AI platform targeting solo founders, the domain should reinforce the AI identity.

## Key Decisions

- **Approach:** Single best domain (no defensive bundle, no TLD split)
- **Budget:** Up to $1,000 total
- **Use case:** Main website
- **Registrar:** Cloudflare (at-cost pricing, no renewal markup, free WHOIS privacy)

## Research Findings

### Availability (as of 2026-02-16)

| Domain | Status | Price (Cloudflare, /yr) |
|--------|--------|------------------------|
| soleur.ai | Available | ~$69 (2-year min: $138) |
| soleur.io | Available | ~$40 |
| soleur.dev | Available | ~$13 |
| soleur.co | Available | ~$10 |
| soleur.app | Available | ~$17 |
| soleur.tech | Available | ~$40 |
| soleur.sh | Likely available | ~$28 |
| soleur.so | Likely available | ~$58 |
| soleur.com | Taken | Broker-only, est. $2K-$10K+ |

### Recommendation Ranking

1. **soleur.ai** -- Strongest AI brand signal. Used by character.ai, perplexity.ai, stability.ai. ~$69/yr. Best fit for "Company-as-a-Service AI platform."
2. **soleur.io** -- Strong tech credibility, half the cost. But no AI signal.
3. **soleur.app** -- Cheap ($17/yr), signals "product." Generic.
4. **soleur.dev** -- Developer-focused. Good for docs but undersells the platform vision.
5. **soleur.co** -- Cheapest ($10/yr). Often confused with .com typos. No tech/AI signal.

### Registrar Comparison

Cloudflare is the clear winner: at-cost pricing, no renewal surprises, free WHOIS privacy, DNS included.

### soleur.com Status

Held by eWeb Development Inc. (Richmond, BC, Canada) since 2011. Parked "Ready for Development" page. Expires 2027. Would require broker negotiation, estimated well above $1,000 budget.

## Purchase Outcome

- **Domain:** soleur.ai
- **Registrar:** Cloudflare
- **Cost:** $140.00 (2-year registration, mandatory for .ai TLD)
- **Renewal:** $70.00/yr (2-year cycles)
- **Expires:** 2028-02-16
- **Purchased:** 2026-02-16
- **Note:** Locked in pre-March-5 pricing ($70/yr vs $80/yr after registry increase)

## Open Questions

- [x] Final domain selection -- **soleur.ai**
- [ ] Whether to also grab soleur.dev as a secondary for docs later
- [x] Fix domains.md and expenses.md -- corrected 2026-02-16
- [ ] Configure DNS and point to GitHub Pages hosting
- [ ] Domain security hardening (SSL/TLS, DNSSEC, HSTS, WAF) -- see #100

## Discovered Opportunity

Manual Cloudflare dashboard navigation for security/DNS configuration revealed a gap in agent coverage. Created issue #100 for an infra-security agent to handle domain security auditing, DNS wiring, and Cloudflare configuration.

## Next Steps

1. ~~Decide on domain~~ -- soleur.ai purchased
2. ~~Purchase via Cloudflare~~ -- done
3. ~~Update ops tracking files~~ -- done
4. Wire soleur.ai to GitHub Pages (requires infra-security agent or manual setup)
5. Harden domain security settings (requires infra-security agent or manual setup)
