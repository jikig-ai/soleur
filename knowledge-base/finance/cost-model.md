---
last_updated: 2026-07-16
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

> **[2026-06-16 Review note]** Out-of-cycle update against `expenses.md@2026-06-16`: the 2026-06-15 outbound-email cold-sending go-live (#5325, PR #5365) added a dedicated `outbound.soleur.ai` Resend sending subdomain, forcing a **Resend free-tier → Pro ($20/mo) upgrade** (a second sending domain exceeds the 1-domain free tier). Resend moves from not-counted to product COGS. Product COGS rises **$121.08 → $141.08** (+16.4%), all-in burn **$531.08 → $551.08**. The all-in **gross-price** break-even shifts **11 → 12 users** (⌈551.08 ÷ 49⌉); the Stripe-net all-in break-even is unchanged at **12**, and the COGS-scope break-even is unchanged at **3**. All-in margin at 50-user scale shifts **78.32% → 77.51%** (gross revenue) / **77.87% → 77.04%** (Stripe-net). The Resend Pro amount is an estimate (operator-driven billing upgrade) — verify against the next Resend invoice per the `expenses.md` caveat.

> **[2026-07-16 Review note]** Out-of-cycle correction against `expenses.md@2026-07-16` (#6538). Two defects, both ledger-accuracy not new spend. **(1) The Hetzner fleet was under-counted:** Product COGS carried only the web-1 host + its volume, omitting web-2, the zot registry, the Inngest control plane, and their volumes/IPv4s — ~$35/mo of *already-active* rows. **(2) The same cx33 SKU was priced two ways** (web-1 at $15.37 vs the registry row at $9.17); the live Hetzner catalog gives cx33 = EUR 8.49/mo net / 80 GB → USD ~9.17 at ~1.08 FX, so the $15.37 / "160 GB SSD" figures were wrong on both amount and disk. Also corrected: the registry is **cx23** (~$5.93), not cx33, since #6497/#6463 right-sized it on 2026-07-16. `grok-dogfood` (verified live via the Hetzner API 2026-07-16, previously ledgered "not born") is classified **R&D**, not COGS, per this document's own classification rule — it is an engineering accelerator that does not scale per paying user. Product COGS **$141.08 → $176.11** (+24.8%), R&D **$410.00 → $419.71**, all-in burn **$551.08 → $595.82**. COGS-scope break-even shifts **3 → 4 users** (⌈176.11 ÷ 49⌉); all-in break-even **12 → 13** at both gross ($49) and Stripe-net ($48) prices. All-in margin at 50-user scale **77.51% → 75.68%** (gross) / **77.04% → 75.17%** (Stripe-net). No new vendor, no new sub-processor — this is a re-derivation of spend that was already being drawn. web-2's rows are retained here and marked *retirement decided* (#6538/#6463); they leave COGS when the destroy lands, which will return ~$10.59/mo. **All Hetzner amounts are catalog-derived — VERIFY actual draw on the next Hetzner invoice.**

> **[2026-07-16 Review note — second pass]** Same cycle, same issue (#6538). The fleet
> sweep above found the Hetzner under-count; a second sweep of `expenses.md` for
> **`active` rows absent from this document's tables** found **three**, none of them
> new spend — and the sweep's own first report said "two", missing the third
> because it was hunting dollars and the third is worth none (**Cloudflare R2
> (cla-evidence)**: `active`, pay-per-use, sub-cent/mo — now named in the
> not-counted list above, whose scope had to widen to admit it; caught at review,
> not by the sweep). The two with dollars: **Supabase Inngest project** (`soleur-inngest-prd`, Micro compute, $10/mo,
> active since 2026-06-17 — the durable Postgres backend behind the CPX22 Inngest host
> that was *already* tabled as COGS) → **COGS**; and **Proton Mail Workspace Standard**
> ($14/mo, active) → **COGS** (rationale in the note under the COGS table — it delivers
> the disclosed `ops@soleur.ai` intake channel and is a named sub-processor, so it is
> not overhead). Product COGS **$176.11 → $200.11** (+13.6%), R&D unchanged at $419.71,
> all-in burn **$595.82 → $619.82**. **COGS-scope break-even shifts 4 → 5 users** at both
> $49 and $48; all-in break-even is **unchanged at 13**. All-in margin at 50-user scale
> **75.68% → 74.70%** (gross) / **75.17% → 74.17%** (Stripe-net); the COGS-based margin
> **92.81% → 91.83%**, which retires the "~93%" framing (§5). Both amounts are estimates
> flagged for invoice verification in `expenses.md` — VERIFY on the next Supabase and
> Proton invoices. **Method note:** the recurring defect is not any single row but that
> `expenses.md` and this document drift silently — nothing gates an `active` ledger row
> against a table line here, so the drift is only ever caught by a human re-reading both.
> Across both passes this cycle, Product COGS moved **$141.08 → $200.11 (+42%)** and the
> COGS break-even **3 → 5 users**, entirely from rows that were already billing. Gate
> proposed in **#6584**, which also carries two pre-existing gaps left un-fixed here: the
> volume rows' FX basis disagrees with the host rows' ~1.08 EUR→USD basis by ~$0.35/mo,
> and **web-1 and the registry have no Primary IPv4 row** (~$1.08/mo) though web-2,
> inngest, and grok-dogfood each do. Both need invoice verification before booking.

> **[2026-07-16 Review note — third pass, at merge]** Merging `origin/main` mid-ship
> pulled in **#6554**, which flipped **xAI API (Grok 4.5 dogfood)** from
> `approved-not-billing` → `active`. That is a live instance of the drift this cycle is
> about: an `active` ledger row with no line here. Tabled → **R&D** (an operator-dogfood
> measure suite is an engineering accelerator; same basis as the `grok-dogfood` host).
> **Booked at the actual draw (~$0.14), NOT the ledger's `100.00` amount** — that figure
> is the row's own **soft-ceiling kill-switch**, and the same row records the first
> billable batch at ≈ $0.14. See the note under the R&D table: booking the ceiling would
> overstate burn ~$100/mo and move the all-in break-even **13 → 15** on unspent money.
> R&D **$419.71 → $419.85**, all-in **$619.82 → $619.96**. **Every break-even and margin
> is unchanged** (⌈619.96 ÷ 49⌉ = ⌈619.96 ÷ 48⌉ = 13; all-in margin 74.70% / 74.17%) —
> the tabling is for completeness, not because it moves the model. Product COGS unchanged
> at $200.11. Re-derive when the first real monthly xAI draw lands.

## Monthly Burn

Monthly burn is split into two scopes: **R&D / dev tooling** (investments that accelerate engineering, not per-user product delivery) and **product COGS** (infrastructure and services consumed in running the product for paying users). This split is load-bearing for break-even math and for the gross-margin-at-scale claim in §5. Reporting a single blended number either collapses under scrutiny (the small-number framing omits real recurring costs) or misrepresents product economics (the large-number framing taxes product margins with engineering-accelerator spend). The split is defensible and carries forward cleanly into pricing conversations.

**Classification rule:** Claude Code Max 20x seats ($200/seat [expenses.md@2026-04-19]) and GitHub Copilot ($10 [expenses.md@2026-04-19]) are engineering accelerators — they make the one-founder engineering team faster, but they do not scale per paying user. Moving these to R&D reduces product COGS materially. If a decision is ever made to use these seats as a per-user service delivery mechanism, reclassification is required.

### R&D / Dev Tooling

| Line | Amount (USD/mo) | Source |
|------|----------------:|--------|
| GitHub Copilot (Business) | 10.00 [expenses.md@2026-04-19] | `expenses.md` |
| Claude Code Max 20x — seat 1 | 200.00 [expenses.md@2026-04-19] | `expenses.md` |
| Claude Code Max 20x — seat 2 | 200.00 [expenses.md@2026-04-19] | `expenses.md` |
| Anthropic API (CI claude-code-action) | 0.00 (accruing) [expenses.md@2026-06-11] | `expenses.md` |
| Hetzner CX33 (grok-dogfood, operator dogfood host) | 9.17 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner Primary IPv4 (grok-dogfood) | 0.54 [expenses.md@2026-07-16] | `expenses.md` |
| xAI API (Grok 4.5 dogfood) | 0.14 (accruing) [expenses.md@2026-07-16] | `expenses.md` (metered — see note) |
| **Subtotal R&D / Dev Tooling** | **419.85 [expenses.md@2026-07-16]** | |

> **xAI API line (#6545, tabled 2026-07-16 on merge of #6554):** `expenses.md` books this
> row's amount as **100.00**, which is its **soft-ceiling kill-switch**, not a draw — the
> same row records the first billable batch at **≈ $0.14** (2026-07-16). Tabled here at the
> **actual draw**, mirroring the `Anthropic API (CI claude-code-action)` line below
> (`0.00 (accruing)`), because this document models **burn**, not authorization. Booking the
> ceiling would overstate all-in burn by ~$100/mo (+16%) and move the all-in break-even
> **13 → 15 users** on money that has not been spent. Re-derive when the first real monthly
> draw lands — VERIFY on the xAI console. *(The ledger booking a ceiling in the amount
> column while a sibling metered row books the draw is the same two-ways-priced defect this
> cycle fixed for cx33; tracked in #6584.)*

> **CI claude-code-action line (#5086, ADR-056):** metered `ANTHROPIC_API_KEY`
> spend from the two CI review jobs — R&D, not COGS (engineering accelerator, same
> basis as the Max seats). Seeded `0.00`/`accruing`; subtotal unchanged until the
> first monthly reconciliation (`knowledge-base/finance/api-spend-ledger.jsonl` →
> the `expenses.md` line). Local Max-subscription loops carry **$0 marginal** and
> are deliberately not ledgered — per-loop dollars would manufacture a false
> billing surprise.

### Product COGS

| Line | Amount (USD/mo) | Source |
|------|----------------:|--------|
| Hetzner CX33 (web-1, web platform) | 9.17 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner Volume (web-1, 20 GB) | 0.88 [expenses.md@2026-04-19] | `expenses.md` |
| Hetzner CX33 (web-2, warm standby, fsn1) | 9.17 [expenses.md@2026-07-16] | `expenses.md` (retirement decided — #6538) |
| Hetzner Volume (web-2, 20 GB) | 0.88 [expenses.md@2026-07-16] | `expenses.md` (retirement decided — #6538) |
| Hetzner Primary IPv4 (web-2) | 0.54 [expenses.md@2026-07-16] | `expenses.md` (retirement decided — #6538) |
| Hetzner CX23 (zot registry, hel1) | 5.93 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner Volume (registry, 60 GB) | 2.64 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner CPX22 (inngest control plane, hel1) | 21.05 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner Volume (inngest, 10 GB) | 0.48 [expenses.md@2026-07-16] | `expenses.md` |
| Hetzner Primary IPv4 (inngest) | 0.54 [expenses.md@2026-07-16] | `expenses.md` |
| Supabase Pro + Custom Domain | 35.00 [expenses.md@2026-04-19] | `expenses.md` |
| Supabase Inngest project (`soleur-inngest-prd`, Micro compute) | 10.00 [expenses.md@2026-07-16] | `expenses.md` |
| Plausible Analytics (Growth) | 9.00 [expenses.md@2026-04-19] | `expenses.md` (EUR 9) |
| Anthropic API (ux-audit cron) | 15.00 [expenses.md@2026-04-19] | `expenses.md` |
| Cloudflare `soleur.ai` domain (amortized $70/yr ÷ 12) | 5.83 [expenses.md@2026-04-19] | `expenses.md` |
| Sentry Team (error tracking + cron monitors, $29 base + ~$11 PAYG draw) | 40.00 [expenses.md@2026-06-11] | `expenses.md` |
| Resend Pro (outbound + transactional email, 50K emails/mo) | 20.00 [expenses.md@2026-06-16] | `expenses.md` (estimate — verify on next invoice) |
| Proton Mail Workspace Standard (2 users — `ops@soleur.ai` intake) | 14.00 [expenses.md@2026-07-16] | `expenses.md` (estimate — confirm exact monthly rate from Proton billing) |
| **Subtotal Product COGS** | **200.11 [expenses.md@2026-07-16]** | |

> **Proton Mail is COGS, not overhead (#6538, 2026-07-16).** The row is easy to read as
> G&A — it is not. Proton delivers `ops@soleur.ai`, the company operational address that
> `gdpr-policy.md` §4.13 and `privacy-policy.md` **disclose to data subjects** as the
> intake channel, and Proton is a **named sub-processor** in the Article 30 register and
> all three policies. Inbound mail forwards to Resend Inbound for AI-assisted triage, so
> Proton is the first hop of a disclosed processing chain — a service consumed in running
> the product, and a prerequisite for delivering the statutory Article 15/17 response
> path. It fails the R&D test (the bucket is engineering accelerators; Proton does not
> make engineering faster). Flat-rate, like Supabase Pro and Sentry — COGS does not
> require per-user linearity.

**Totals:**

- **Product COGS:** ~$200/month [expenses.md@2026-07-16]
- **R&D / Dev Tooling:** ~$420/month [expenses.md@2026-07-16]
- **All-in recurring burn:** ~$620/month [expenses.md@2026-07-16]

Not counted (free-tier, test-mode, or metered-at-sub-cent; trigger-based upgrades listed in §4): Stripe, Better Stack (uptime free-tier; Responder tier still deferred), Buttondown, Doppler, LinkedIn, Bluesky, X API free tier, **Cloudflare R2 (cla-evidence)** — `active` and pay-per-use ($0.015/GB-mo + $0.36/M writes) but sub-cent/mo at realistic scale, so it is ledgered at 0.00 and not tabled. *(Scope of this list widened 2026-07-16 (#6538) from "free-tier or test-mode" to admit the metered-sub-cent case: R2 is `active` and fits neither prior label, so it fell through both the tables and this list. #6584's parity gate must treat this line as the authoritative not-counted set.)*

## Per-User Infrastructure Cost

The question this section answers: **what does the marginal paying user cost us in infrastructure?** At current architecture the answer is near-zero, because the hot variable cost (LLM inference) is externalized to the user's own API key.

### BYOK — Architectural Commitment

Per-user LLM inference cost is **$0** because inference runs on user-owned Anthropic API keys (Bring-Your-Own-Key). This is not a pricing choice — it is a **load-bearing architectural commitment** of the cost model. The $49/mo break-even math, the gross-margin-at-scale claim, and the scaling-triggers table all assume BYOK.

**If a managed-LLM fallback tier (e.g., Soleur-provisioned inference credits) is ever introduced, every number in this document must be re-derived.** Managed inference re-loads per-user variable cost and collapses COGS-based margins. See `engineering/architecture/decisions/ADR-004-byok-encryption-model.md` for the encryption dimension; the cost-model dimension is documented here.

### CX33 Session Capacity

The current Hetzner CX33 host (web-1: 4 shared vCPU, 8 GB RAM, 80 GB SSD, $9.17/mo [expenses.md@2026-07-16]) sustains approximately **10–12 concurrent agent sessions without Playwright**. Sessions with Playwright browser automation reduce this ceiling meaningfully; exact headroom depends on browser count. See `knowledge-base/operations/expenses.md` Hetzner CX33 notes for the operating-model assumption.

Per-user server cost at capacity (11 concurrent, amortized): **$9.17 / 11 ≈ $0.83 per concurrent user slot [expenses.md@2026-07-16]**. This is a capacity-bound number, not a per-MAU cost — a single slot serves many MAUs across time.

### Volume Amortization

Hetzner Volume (20 GB persistent storage for `/workspaces`) at $0.88/mo [expenses.md@2026-04-19] amortizes to $0.08/user/mo at 11 concurrent users. Negligible until the 20 GB cap is approached.

### Supabase Pro Headroom

Supabase Pro ($35/mo [expenses.md@2026-04-19], bundled with custom-domain add-on) offers 500 MB database, 50K MAU, 1 GB file storage, 2 GB bandwidth on-plan. Until those limits are approached, marginal user cost on Supabase is **$0**; when approached, the upgrade is to higher Pro-tier limits (not a plan change). See §4 for the scaling-trigger row.

### Per-User Summary

At current architecture and headroom:

| Component | Marginal cost/user (USD/mo) |
|-----------|-----------------------------|
| LLM inference | $0 (BYOK) |
| Server capacity (1 slot of 11 on CX33) | ~$0.83 [expenses.md@2026-07-16] |
| Persistent storage (volume amortized) | ~$0.08 |
| Database / auth / bandwidth (Supabase Pro headroom) | ~$0 until trigger |
| **Marginal user cost** | **~$0.91 [expenses.md@2026-07-16]** |

This is a steady-state approximation, valid while users remain within Supabase Pro limits and CX33 session capacity.

## Break-Even Analysis

Price anchor: **$49/month** per Pro tier (`product/pricing-strategy.md`). Math is burn ÷ price, rounded up.

### Gross-price arithmetic (before Stripe fees)

| Scope | Burn (USD/mo) | Price ($49) | Users to break even |
|-------|--------------:|------------:|--------------------:|
| Product COGS | 200.11 [expenses.md@2026-07-16] | 49 | ⌈200.11 ÷ 49⌉ = **5 users** |
| All-in (COGS + R&D / Dev Tooling) | 619.96 [expenses.md@2026-07-16] | 49 | ⌈619.96 ÷ 49⌉ = **13 users** |

### Stripe fee drag

Stripe live-mode fees: **2.9% + $0.30 per US charge**, **1.5% + EUR 0.25 per EU card charge**, no monthly minimum [expenses.md@2026-04-19]. For a $49 EU-card charge: $49 × 1.5% = $0.735, + ~$0.27 (EUR 0.25 ≈ USD 0.27) = **≈ $1.00 fee per user/mo**. US mix is higher (~$1.72 per $49 charge); using the EU-card number as the charitable floor.

Effective **net revenue per user after Stripe fees: ~$48/month** (EU floor) to ~$47.28/month (US).

### Net-price arithmetic (after Stripe fees, EU floor)

| Scope | Burn | Net price ($48) | Users to break even |
|-------|-----:|----------------:|--------------------:|
| Product COGS | 200.11 [expenses.md@2026-07-16] | 48 | ⌈200.11 ÷ 48⌉ = **5 users** |
| All-in | 619.96 [expenses.md@2026-07-16] | 48 | ⌈619.96 ÷ 48⌉ = **13 users** |

Stripe fee drag no longer moves the all-in break-even count — gross-price and net-price both round up to **13 users** at the current $619.96 burn (the 2026-06-16 Resend Pro add pushed the gross-price count from 11 to 12, closing the one-user gap). The COGS-scope count shifts 4 → 5 (⌈200.11 ÷ 49⌉ = ⌈200.11 ÷ 48⌉ = 5). Stripe fees still bite into gross margin at scale (see §5).

## Scaling Triggers

Each row is a trigger that forces a spend upgrade. "Upgrade delta" is the monthly increase to the next tier, not the new absolute total.

| Service | Current | Trigger | Upgrade delta (USD/mo) | Source |
|---------|---------|---------|-----------------------:|--------|
| Supabase Pro | $35.00 [expenses.md@2026-04-19] (Pro + custom domain) | Any of: 500 MB DB, 50K MAU, 1 GB file storage, 2 GB bandwidth | Pro-tier limit overages billed per-usage (DB storage ~$0.125/GB, bandwidth ~$0.09/GB, MAU ~$0.00325/MAU); no plan change until Team ($599/mo) | `expenses.md` + Supabase Pro pricing |
| Hetzner CX33 session capacity | $9.17 [expenses.md@2026-07-16] (~11 concurrent) | Sustained >10–12 concurrent agent sessions or Playwright-heavy workload | Upgrade to CX43 (~$29/mo delta TBD — verify at Hetzner pricing at trigger time) | `expenses.md` CX33 notes |
| X API | $0 [expenses.md@2026-04-19] (free tier) | First paying customer or $500 MRR (per #497) | +$100.00/mo (X API Basic) | `expenses.md` deferred row + #497 |
| Resend Pro | $20.00 [expenses.md@2026-06-16] (active; outbound + transactional, 50K emails/mo) | >50K emails/mo | Resend Scale-tier overage (delta TBD at trigger) | `expenses.md` (estimate — verify on next invoice) |
| Buttondown | $0 [expenses.md@2026-04-19] (free tier) | >100 newsletter subscribers | +$9.00/mo (Basic) | `expenses.md` |
| Plausible Analytics | $9.00 [expenses.md@2026-04-19] (Growth, EUR 9) | >10K pageviews/mo | Tier upgrade on Plausible Growth ladder — delta TBD at trigger | `expenses.md` |
| Sentry Team | $40.00 [expenses.md@2026-06-11] (active; $29 base + ~$11 PAYG drawn for 40 cron monitors, PR #5161) | Further cron-monitor growth beyond the 40 active | +$0–39/mo residual PAYG headroom (`onDemandMaxSpend` $50 cap, see #3958) | `expenses.md` |
| Better Stack | $0 [expenses.md@2026-05-21] (uptime free tier; Responder $29 deferred) | First paying customer or first email-only-routing incident (per #3960) | +$29/mo (Responder tier) | `expenses.md` |
| Claude Code Max 20x token ceiling | $400.00 [expenses.md@2026-04-19] (2 seats, flat) | Cumulative loop usage hits the Max-20x rolling token/usage ceiling → forces a 3rd seat or API spillover | +$200/mo (seat 3) or metered API overage | #5086 exposure note — no automated quota signal exists today; re-evaluate on sustained rate-limit/slowdown symptoms |

Pre-planned cumulative upgrade exposure at "first paying customer" trigger: **+$100/mo (X API Basic) + $29/mo (Better Stack Responder)** [expenses.md@2026-05-21] at minimum. Buttondown's trigger fires on volume rather than on the first-paying-customer gate. Resend's free-tier→Pro trigger has already fired (2026-06-15 second sending domain for cold outbound, #5325) and is now an active baseline cost counted in COGS above, not a pending trigger. Sentry Team is likewise an active baseline cost (counted in COGS above), not a trigger.

## Gross Margin at Scale

Worked example: **50 paying users × $49/month = $2,450 MRR**. Two margin framings, both computed.

### Against Product COGS (the COGS-only framing)

```
Revenue:           $2,450
Product COGS:      $200.11 [expenses.md@2026-07-16]
Gross profit:      $2,249.89
Gross margin:      2,249.89 / 2,450 = 91.83%
```

### Against All-in Burn (the honest founder-economics framing)

```
Revenue:           $2,450
All-in burn:       $619.96 [expenses.md@2026-07-16]
Contribution:      $1,830.04
Margin (all-in):   1,830.04 / 2,450 = 74.70%
```

### Stripe Fee Drag

At 50 users × ~$1/user/mo Stripe fee (EU floor) = **$50/mo in fees**. Effective net revenue: $2,450 − $50 = **$2,400**.

- Adjusted COGS-based margin: ($2,400 − $200.11) / $2,400 = **91.66%**
- Adjusted all-in margin: ($2,400 − $619.96) / $2,400 = **74.17%**

The original "93% gross margin" claim is closest to the COGS-based number, but that number is now **~92%, not ~93%** — the 2026-07-16 re-derivation (#6538) has walked it down from 92.81% as previously-untabled COGS rows landed, and it elides R&D / dev-tooling burn besides. The more honest founder-economics number is the all-in margin (**~75%**). Both should be cited side-by-side whenever the gross-margin claim is made; COGS-only margin without the R&D context misrepresents the operating picture. **The "93%" framing is now stale on its own terms and should be retired from external use rather than re-rounded.**

## Pricing Gate #4 Status

This document addresses the **affordability** dimension of Pricing Gate #4 (`knowledge-base/product/pricing-strategy.md:152` — "Infrastructure ready | Cloud sync, hosted execution, and analytics dashboard are buildable (not necessarily built) | Not assessed"). The affordability side is now assessed: product COGS is ~$200/mo at current ledger [expenses.md@2026-07-16], break-even is **5 paying users** (COGS scope) / 13 (all-in, gross-price and Stripe-net), gross margins are **~75% all-in (~92% COGS-scope)** at 50-user scale, and the BYOK architectural commitment keeps per-user variable cost near zero. **Cite the all-in figure, not the COGS-scope one** — §5 retires the "~93%" framing, and this section is the one most likely to be quoted outward.

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
