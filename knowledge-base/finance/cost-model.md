---
last_updated: 2026-06-11
last_reviewed: 2026-06-02
review_cadence: monthly
owner: cfo
depends_on:
  - knowledge-base/operations/expenses.md
  - knowledge-base/product/pricing-strategy.md
---

# Cost Model

Derived view over the authoritative expense ledger at `knowledge-base/operations/expenses.md`. Every dollar figure in this document traces to a specific ledger row at the cited date. This is not a second ledger — categories and derived totals are maintained here; row-by-row expense detail stays in the ledger.

> **[2026-06-02 Review note]** Monthly review against `expenses.md@2026-05-21`. One material change since the 2026-04-19 basis: **Sentry Team ($29/mo) moved from free-tier to active** (org `jikigai-eu`, renewal 2026-06-17), so it now counts as product COGS. Product COGS rises **$81.08 → $110.08**, all-in burn **$491.08 → $520.08**, and COGS-scope break-even shifts **2 → 3 users**. All-in break-even (11 users) and per-user marginal cost (~$1.50) are unchanged. Unchanged component lines retain their `@2026-04-19` anchors; re-derived totals and the Sentry line are anchored `@2026-05-21`.

> **[2026-06-11 Review note]** Out-of-cycle update against `expenses.md@2026-06-11`: PR #5161 backfilled 14 Sentry cron monitors (40 total active), realizing **~$11/mo of the $50 PAYG cap** (#3958) that was previously listed as un-drawn step-up exposure. Sentry line rises **$29.00 → $40.00**, product COGS **$110.08 → $121.08**, all-in burn **$520.08 → $531.08**. Gross-price break-evens are unchanged (⌈121.08 ÷ 49⌉ = 3; ⌈531.08 ÷ 49⌉ = 11), but the Stripe-net all-in break-even shifts **11 → 12 users** (⌈531.08 ÷ 48⌉). Margins at 50-user scale shift <0.5 pt (all-in 78.77% → 78.32%). PAYG estimate (~14 × $0.78) to be verified against the actual 2026-06-17 invoice.

## Monthly Burn

Monthly burn is split into two scopes: **R&D / dev tooling** (investments that accelerate engineering, not per-user product delivery) and **product COGS** (infrastructure and services consumed in running the product for paying users). This split is load-bearing for break-even math and for the gross-margin-at-scale claim in §5. Reporting a single blended number either collapses under scrutiny (the small-number framing omits real recurring costs) or misrepresents product economics (the large-number framing taxes product margins with engineering-accelerator spend). The split is defensible and carries forward cleanly into pricing conversations.

**Classification rule:** Claude Code Max 20x seats ($200/seat [expenses.md@2026-04-19]) and GitHub Copilot ($10 [expenses.md@2026-04-19]) are engineering accelerators — they make the one-founder engineering team faster, but they do not scale per paying user. Moving these to R&D reduces product COGS materially. If a decision is ever made to use these seats as a per-user service delivery mechanism, reclassification is required.

### R&D / Dev Tooling

| Line | Amount (USD/mo) | Source |
|------|----------------:|--------|
| GitHub Copilot (Business) | 10.00 [expenses.md@2026-04-19] | `expenses.md` |
| Claude Code Max 20x — seat 1 | 200.00 [expenses.md@2026-04-19] | `expenses.md` |
| Claude Code Max 20x — seat 2 | 200.00 [expenses.md@2026-04-19] | `expenses.md` |
| **Subtotal R&D / Dev Tooling** | **410.00 [expenses.md@2026-04-19]** | |

### Product COGS

| Line | Amount (USD/mo) | Source |
|------|----------------:|--------|
| Hetzner CX33 (web platform) | 15.37 [expenses.md@2026-04-19] | `expenses.md` |
| Hetzner Volume (20 GB) | 0.88 [expenses.md@2026-04-19] | `expenses.md` |
| Supabase Pro + Custom Domain | 35.00 [expenses.md@2026-04-19] | `expenses.md` |
| Plausible Analytics (Growth) | 9.00 [expenses.md@2026-04-19] | `expenses.md` (EUR 9) |
| Anthropic API (ux-audit cron) | 15.00 [expenses.md@2026-04-19] | `expenses.md` |
| Cloudflare `soleur.ai` domain (amortized $70/yr ÷ 12) | 5.83 [expenses.md@2026-04-19] | `expenses.md` |
| Sentry Team (error tracking + cron monitors, $29 base + ~$11 PAYG draw) | 40.00 [expenses.md@2026-06-11] | `expenses.md` |
| **Subtotal Product COGS** | **121.08 [expenses.md@2026-06-11]** | |

**Totals:**

- **Product COGS:** ~$121/month [expenses.md@2026-06-11]
- **R&D / Dev Tooling:** ~$410/month [expenses.md@2026-04-19]
- **All-in recurring burn:** ~$531/month [expenses.md@2026-06-11]

Not counted (free-tier or test-mode; trigger-based upgrades listed in §4): Stripe, Better Stack (uptime free-tier; Responder tier still deferred), Buttondown, Doppler, LinkedIn, Bluesky, Resend, X API free tier.

## Per-User Infrastructure Cost

The question this section answers: **what does the marginal paying user cost us in infrastructure?** At current architecture the answer is near-zero, because the hot variable cost (LLM inference) is externalized to the user's own API key.

### BYOK — Architectural Commitment

Per-user LLM inference cost is **$0** because inference runs on user-owned Anthropic API keys (Bring-Your-Own-Key). This is not a pricing choice — it is a **load-bearing architectural commitment** of the cost model. The $49/mo break-even math, the gross-margin-at-scale claim, and the scaling-triggers table all assume BYOK.

**If a managed-LLM fallback tier (e.g., Soleur-provisioned inference credits) is ever introduced, every number in this document must be re-derived.** Managed inference re-loads per-user variable cost and collapses COGS-based margins. See `engineering/architecture/decisions/ADR-004-byok-encryption-model.md` for the encryption dimension; the cost-model dimension is documented here.

### CX33 Session Capacity

The current Hetzner CX33 host (4 vCPU, 8 GB RAM, 160 GB SSD, $15.37/mo [expenses.md@2026-04-19]) sustains approximately **10–12 concurrent agent sessions without Playwright**. Sessions with Playwright browser automation reduce this ceiling meaningfully; exact headroom depends on browser count. See `knowledge-base/operations/expenses.md` Hetzner CX33 notes for the operating-model assumption.

Per-user server cost at capacity (11 concurrent, amortized): **$15.37 / 11 ≈ $1.40 per concurrent user slot [expenses.md@2026-04-19]**. This is a capacity-bound number, not a per-MAU cost — a single slot serves many MAUs across time.

### Volume Amortization

Hetzner Volume (20 GB persistent storage for `/workspaces`) at $0.88/mo [expenses.md@2026-04-19] amortizes to $0.08/user/mo at 11 concurrent users. Negligible until the 20 GB cap is approached.

### Supabase Pro Headroom

Supabase Pro ($35/mo [expenses.md@2026-04-19], bundled with custom-domain add-on) offers 500 MB database, 50K MAU, 1 GB file storage, 2 GB bandwidth on-plan. Until those limits are approached, marginal user cost on Supabase is **$0**; when approached, the upgrade is to higher Pro-tier limits (not a plan change). See §4 for the scaling-trigger row.

### Per-User Summary

At current architecture and headroom:

| Component | Marginal cost/user (USD/mo) |
|-----------|-----------------------------|
| LLM inference | $0 (BYOK) |
| Server capacity (1 slot of 11 on CX33) | ~$1.40 |
| Persistent storage (volume amortized) | ~$0.08 |
| Database / auth / bandwidth (Supabase Pro headroom) | ~$0 until trigger |
| **Marginal user cost** | **~$1.50 [expenses.md@2026-04-19]** |

This is a steady-state approximation, valid while users remain within Supabase Pro limits and CX33 session capacity.

## Break-Even Analysis

Price anchor: **$49/month** per Pro tier (`product/pricing-strategy.md`). Math is burn ÷ price, rounded up.

### Gross-price arithmetic (before Stripe fees)

| Scope | Burn (USD/mo) | Price ($49) | Users to break even |
|-------|--------------:|------------:|--------------------:|
| Product COGS | 121.08 [expenses.md@2026-06-11] | 49 | ⌈121.08 ÷ 49⌉ = **3 users** |
| All-in (COGS + R&D / Dev Tooling) | 531.08 [expenses.md@2026-06-11] | 49 | ⌈531.08 ÷ 49⌉ = **11 users** |

### Stripe fee drag

Stripe live-mode fees: **2.9% + $0.30 per US charge**, **1.5% + EUR 0.25 per EU card charge**, no monthly minimum [expenses.md@2026-04-19]. For a $49 EU-card charge: $49 × 1.5% = $0.735, + ~$0.27 (EUR 0.25 ≈ USD 0.27) = **≈ $1.00 fee per user/mo**. US mix is higher (~$1.72 per $49 charge); using the EU-card number as the charitable floor.

Effective **net revenue per user after Stripe fees: ~$48/month** (EU floor) to ~$47.28/month (US).

### Net-price arithmetic (after Stripe fees, EU floor)

| Scope | Burn | Net price ($48) | Users to break even |
|-------|-----:|----------------:|--------------------:|
| Product COGS | 121.08 [expenses.md@2026-06-11] | 48 | ⌈121.08 ÷ 48⌉ = **3 users** |
| All-in | 531.08 [expenses.md@2026-06-11] | 48 | ⌈531.08 ÷ 48⌉ = **12 users** |

Stripe fee drag now moves the all-in break-even by one user (gross-price 11 → net-price 12); the COGS-scope count is unchanged at 3. It also bites into gross margin at scale (see §5).

## Scaling Triggers

Each row is a trigger that forces a spend upgrade. "Upgrade delta" is the monthly increase to the next tier, not the new absolute total.

| Service | Current | Trigger | Upgrade delta (USD/mo) | Source |
|---------|---------|---------|-----------------------:|--------|
| Supabase Pro | $35.00 [expenses.md@2026-04-19] (Pro + custom domain) | Any of: 500 MB DB, 50K MAU, 1 GB file storage, 2 GB bandwidth | Pro-tier limit overages billed per-usage (DB storage ~$0.125/GB, bandwidth ~$0.09/GB, MAU ~$0.00325/MAU); no plan change until Team ($599/mo) | `expenses.md` + Supabase Pro pricing |
| Hetzner CX33 session capacity | $15.37 [expenses.md@2026-04-19] (~11 concurrent) | Sustained >10–12 concurrent agent sessions or Playwright-heavy workload | Upgrade to CX43 (~$29/mo delta TBD — verify at Hetzner pricing at trigger time) | `expenses.md` CX33 notes |
| X API | $0 [expenses.md@2026-04-19] (free tier) | First paying customer or $500 MRR (per #497) | +$100.00/mo (X API Basic) | `expenses.md` deferred row + #497 |
| Resend | $0 [expenses.md@2026-04-19] (free tier) | >100 emails/day or >3K emails/mo | +$20.00/mo (paid tier, 50K emails) | `expenses.md` |
| Buttondown | $0 [expenses.md@2026-04-19] (free tier) | >100 newsletter subscribers | +$9.00/mo (Basic) | `expenses.md` |
| Plausible Analytics | $9.00 [expenses.md@2026-04-19] (Growth, EUR 9) | >10K pageviews/mo | Tier upgrade on Plausible Growth ladder — delta TBD at trigger | `expenses.md` |
| Sentry Team | $40.00 [expenses.md@2026-06-11] (active; $29 base + ~$11 PAYG drawn for 40 cron monitors, PR #5161) | Further cron-monitor growth beyond the 40 active | +$0–39/mo residual PAYG headroom (`onDemandMaxSpend` $50 cap, see #3958) | `expenses.md` |
| Better Stack | $0 [expenses.md@2026-05-21] (uptime free tier; Responder $29 deferred) | First paying customer or first email-only-routing incident (per #3960) | +$29/mo (Responder tier) | `expenses.md` |

Pre-planned cumulative upgrade exposure at "first paying customer" trigger: **+$100/mo (X API Basic) + $29/mo (Better Stack Responder)** [expenses.md@2026-05-21] at minimum. Resend and Buttondown triggers fire on volume rather than on the first-paying-customer gate. Sentry Team is now an active baseline cost (counted in COGS above), not a trigger.

## Gross Margin at Scale

Worked example: **50 paying users × $49/month = $2,450 MRR**. Two margin framings, both computed.

### Against Product COGS (the 93%-adjacent framing)

```
Revenue:           $2,450
Product COGS:      $121.08 [expenses.md@2026-06-11]
Gross profit:      $2,328.92
Gross margin:      2,328.92 / 2,450 = 95.06%
```

### Against All-in Burn (the honest founder-economics framing)

```
Revenue:           $2,450
All-in burn:       $531.08 [expenses.md@2026-06-11]
Contribution:      $1,918.92
Margin (all-in):   1,918.92 / 2,450 = 78.32%
```

### Stripe Fee Drag

At 50 users × ~$1/user/mo Stripe fee (EU floor) = **$50/mo in fees**. Effective net revenue: $2,450 − $50 = **$2,400**.

- Adjusted COGS-based margin: ($2,400 − $121.08) / $2,400 = **94.96%**
- Adjusted all-in margin: ($2,400 − $531.08) / $2,400 = **77.87%**

The original "93% gross margin" claim is closer to the COGS-based number (actually ~96%) and elides R&D / dev-tooling burn. The more honest founder-economics number is the all-in margin (~78%). Both should be cited side-by-side whenever the gross-margin claim is made; COGS-only margin without the R&D context misrepresents the operating picture.

## Pricing Gate #4 Status

This document addresses the **affordability** dimension of Pricing Gate #4 (`knowledge-base/product/pricing-strategy.md:152` — "Infrastructure ready | Cloud sync, hosted execution, and analytics dashboard are buildable (not necessarily built) | Not assessed"). The affordability side is now assessed: product COGS is ~$121/mo at current ledger, break-even is 3 paying users (COGS scope) / 11 (all-in, gross-price; 12 Stripe-net), gross margins remain ~78% all-in (~95% COGS-scope) at 50-user scale, and the BYOK architectural commitment keeps per-user variable cost near zero.

The **buildability** dimension — whether cloud sync, hosted agent execution, and the analytics dashboard are actually buildable within a reasonable horizon — remains with **CPO / CTO**. That assessment is not closed by this document.

Pricing Gate #4 is therefore **partially addressed**, not closed. Do not cite cost-model.md as evidence that Gate #4 is green.

## Open Questions

- **Claude Code Max seat classification for external-facing framing.** The internal R&D/COGS split is defensible. Investor-facing or public cost-disclosure scrutiny may interpret $400/mo of "dev tooling" that is the literal mechanism of product delivery differently. Proposed resolution: cost-model.md is internal-first; produce an external-facing summary only when needed (e.g., investor update, pricing page justification), and keep the external framing consistent with the audit trail in `expenses.md`.
- **CX22 `telegram-bridge` R&D/COGS split.** The telegram-bridge host is not in the active recurring ledger [expenses.md@2026-04-19] and is classed historically as R&D. If/when the telegram bridge becomes a paying-customer channel, it reclassifies to COGS and this document needs a new row. Trigger: first paying customer using the telegram surface.
- **Managed-LLM-tier impact on the BYOK claim.** See §2 — any decision to offer a Soleur-provisioned inference tier forces a full re-derivation of the cost model. Who owns the trigger-decision: CPO for the product call, CFO for the cost re-derivation, CTO for the BYOK-encryption-model ADR update.
- **Cost-model review cadence ownership.** Current chain: CFO agent → budget-analyst → founder. Frontmatter `review_cadence: monthly` sets the expectation; the `/ship` Phase 5.5 COO gate catches ledger drift; strategy-review-cadence cron is the safety net. If monthly reviews do not materialize (30–60 day observation window post-merge), a follow-up PR either adds an AGENTS.md workflow gate or extends the cron target list.

## References

- `../operations/expenses.md` — source ledger; all dollar figures in this document trace here at their bracketed anchor dates.
- `../product/pricing-strategy.md` — Pricing Gate #4 definition at L152; pivot context at L25 (cost escalation under platform-first delivery).
- `../product/roadmap.md` — Phase 4.10 (Stripe live activation) and Pricing section; this document's partial Gate #4 status is reflected in the roadmap narrative sync in the same PR.
- `../engineering/architecture/decisions/ADR-004-byok-encryption-model.md` — BYOK architectural record; encryption dimension. Cost dimension is §2 of this document.
- `./memos/2026-04-19-conversation-slot-economics-cfo-reconsult.md` — tiered pricing decision record ($0 / $49 / $149 / $499); referenced, not absorbed (memo is a dated decision record with point-in-time framing).
