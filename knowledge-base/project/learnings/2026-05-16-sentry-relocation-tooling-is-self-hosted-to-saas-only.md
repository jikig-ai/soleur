---
date: 2026-05-16
category: integration-issues
module: sentry, vendor-evaluation, observability
tags:
  - sentry
  - vendor-evaluation
  - cross-region-migration
  - residency
  - probe-discipline
  - gdpr
related_issues:
  - "#3861"
  - "#3904"
related_learnings:
  - 2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline
  - 2026-05-15-sentry-dsn-cluster-substring-authoritative-residency
  - 2026-05-15-sentry-iac-billing-and-quirks
---

# Learning: Sentry "Relocation" tooling does NOT cover cross-region SaaS migration

When evaluating a vendor-managed migration path as an alternative to a manual atomic-swap of credentials across N secret stores, the assumption "the vendor has a cross-region migration product" must be probe-verified, not inferred from marketing surface. Sentry's "Relocation" product is real but covers self-hosted→SaaS only; it does NOT migrate between SaaS regions (US ↔ EU/DE) and regenerates DSNs at the destination regardless. The US cancellation-page prompt "If migrating to another existing account, can you provide the org slug?" is sales-assisted billing/subscription-transfer (move a paid plan between existing orgs on the same cluster), not cross-cluster destination migration.

## Problem

A2 Branch C brainstorm needed to decide whether to commit to a 7+ secret-surface manual atomic swap (Doppler + GH + Vercel + 11 scheduled workflows + sentry-cli + CSP report-uri + Cloudflare cache purge) OR investigate a vendor-managed shortcut suggested by an observed UI prompt on Sentry's cancellation page. CTO triad assessment assigned ~85% probability the vendor path was billing-theater, but the 15% case would have collapsed C2's blast radius 10x. Probe was timeboxed to 30 minutes.

## Solution

Five lightweight probes resolved the question in ~5 minutes:

1. **WebSearch on the vendor domain.** `WebSearch query="Sentry relocation cross-region migration"` allowed_domains=[sentry.io, docs.sentry.io, develop.sentry.dev]. Returned authoritative pages: docs.sentry.io/product/sentry-basics/migration/, blog.sentry.io/sentrys-eu-data-region-now-in-early-access/, docs.sentry.io/organization/data-storage-location/. Search confirmed Relocation IS a documented product but characterized it as "moving from self-hosted to SaaS."

2. **HEAD-probe 5 candidate API endpoints on both regional edges.** Use the canonical pattern:

   ```bash
   for ep in /api/0/relocations/ /api/0/organizations/<slug>/relocations/ \
             /api/0/customers/<slug>/relocations/ \
             /api/0/organization-transfers/ /api/0/account-migrations/; do
     code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 -L "https://eu.sentry.io${ep}")
     echo "eu.sentry.io${ep} -> ${code}"
   done
   ```

   All 5 returned 404 on both `eu.sentry.io` and `sentry.io` edges. No relocation API endpoint exists on either edge — Relocation is operator-portal-only, not API-exposed.

3. **CLI subcommand check.** `which sentry-cli && sentry-cli --help | grep -iE "(relocation|migrate|transfer)"` → no relocation/migrate/transfer subcommand exists in user-facing sentry-cli.

4. **WebFetch the canonical docs page.** docs.sentry.io/product/sentry-basics/migration/ confirmed: (a) self-hosted→SaaS only; (b) DSNs are regenerated at destination — must update DSN in each SDK; (c) self-service via in-app instructions; (d) requires owner access to source install.

5. **Cross-check against developer architecture docs.** develop.sentry.dev/self-hosted/relocation/ returned 404 (the relocation product is not documented in developer architecture docs, only consumer docs — confirming it's a customer-facing migration flow, not a public API or service primitive).

**Verdict for Branch C:** Cannot use Sentry Relocation because (a) it doesn't cover cross-region SaaS, (b) the source org `4511123328466944` is unowned (we lack owner access), (c) DSNs would regenerate anyway. Manual atomic swap is the only path.

## Key Insight

**Vendor cross-region migration tooling is the exception, not the rule.** Vendors that operate multi-region data planes typically isolate them as separate accounts with no cross-region data movement, because cross-region migration is in tension with the residency commitments that justified the regions in the first place. When a vendor markets a "migration" product, default-assume it's self-hosted→SaaS (the only direction with clear demand and no residency conflict) — and probe-verify before designing an architecture around the cross-region capability.

**The 5-probe pattern (WebSearch + 5 API HEAD probes + CLI subcommand check + canonical doc fetch + dev-docs cross-check) is reusable for any "does vendor X offer feature Y?" question** that would otherwise spawn a multi-hour design exploration. Total cost: ~5 minutes. Total avoided cost when the answer is no: hours of design on a false premise.

**A UI prompt observed during operator navigation is not a feature — it's a discovery surface for a feature whose semantics must be verified.** The "migrate to another existing account" prompt on Sentry's cancellation page is sales-assisted plan/seat transfer between same-cluster orgs, NOT cross-cluster destination migration. UI prompts compress complex sales flows into ambiguous strings.

## Session Errors

1. **WebFetch 404 on three guessed Sentry doc URLs** (`docs.sentry.io/product/relocation/`, `develop.sentry.dev/self-hosted/relocation/`, `help.sentry.io/product-features/data-residency/multi-region-support/`). Recovery: WebSearch returned the canonical `docs.sentry.io/product/sentry-basics/migration/` on the first try. **Prevention:** WebSearch on the vendor domain before WebFetch when probing vendor product docs — URL paths drift across product reorganizations; doc-search indexes track them correctly.

## Tags

category: integration-issues
module: sentry, vendor-evaluation, observability
