---
title: "rundevoo.run — domain purchase + safe-DNS onboarding (future product, phase 1)"
date: 2026-11-19
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [infra, dns, cloudflare, domain, dogfood, product-incubation]
related_issues: []
related_adrs: [ADR-030, ADR-065, ADR-130]
---

# rundevoo.run — test-app domain (future product)

## The question

Purchase `rundevoo.run` as the domain for a future product that phase 1 treats as
"a test app on which we run Soleur." Operator decisions this session: **future
product** (incubated; the test-app framing is its first phase), **product shape
still undecided** (a later brainstorm owns it), **phase-1 scope = domain + safe
DNS only** (no site, no app scaffold), **purchase via Cloudflare Registrar**,
**full IaC onboarding** approach.

## Measured floor (verified this session)

- **Domain availability:** `rundevoo.run` returns RDAP 404 (object not found) —
  unregistered as of 2026-11-19.
- **Price:** ~$21.20/yr `.run` at Cloudflare Registrar (at-cost; COO-measured,
  nextname.app Nov 2026). 1-year term; `.run` has no multi-year minimum.
- **No `rundevoo` anywhere in the repo** — greenfield.
- **IaC floor:** soleur.ai is the only managed zone, and it is *referenced*, not
  created — `var cf_zone_id` (no default) in `apps/web-platform/infra`; **zero
  `resource "cloudflare_zone"` exists on main**. `dns.tf` is soleur.ai-scoped
  (32 records). Six scoped CF provider aliases; none can create a zone.
- **jikigai.com is absent from IaC** (Squarespace registrar, Google DNS; CF zone
  died unobserved on the 28-day pending clock — #7995 still open). The deferred
  plan `knowledge-base/project/plans/archive/20261013-051752-2026-09-09-feat-jikigai-cloudflare-zone-terraform-plan.md`
  is the authoritative zone-onboarding checklist; rundevoo.run skips its three
  hard parts (Cloudflare Registrar auto-creates the zone in-account — no NS
  cutover, no 28-day pending clock, no mail-continuity constraint).
- **Dogfood precedent:** `apps/web-platform/infra/grok-dogfood.tf` — flag-gated
  host, SSH-only, explicitly off `10.0.1.0/24`, "dogfood is not a product
  surface." rundevoo.run inverts that posture deliberately (public product
  domain), so agent-guards must be designed in, not inherited.
- **Purchase is a payment step** — operator-only per the canonical list
  (payment-method/billing entry). Everything after is agent-doable.
- **Ledgers:** `knowledge-base/operations/domains.md` (domain register) +
  `knowledge-base/operations/expenses.md` (Recurring + One-Time dual-entry
  precedent from soleur.ai); `wg-record-recurring-vendor-expense-before-ready`
  (ship Phase 5.5) binds the renewal row.

## Decision

**Full IaC onboarding** — operator-selected 2026-11-19. Purchase at Cloudflare
Registrar → zone auto-created in-account → new Terraform root
`infra/rundevoo-run/` (R2 backend) → zone import + zone-scoped `Zone:DNS:Edit`
token via the bootstrap-ephemeral-admin pattern → mail-spoof hardening → apply
workflow + drift matrix + destroy-guard wiring → ledger rows.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | rundevoo.run is a **future product**; phase 1 = domain + safe DNS only | Operator decision. Product shape (dev tool / content / API) is a later brainstorm; buying now secures the name. |
| 2 | Purchase at **Cloudflare Registrar** as **Jikigai SARL**, 1-yr, auto-renew ON, org registrant email, WHOIS privacy on | soleur.ai precedent; at-cost (~$21.20/yr); zone auto-created in the same account (no NS cutover, no 28-day clock); org registrant = company asset + avoids ICANN suspension. Auto-renew makes "kept" the default; squatter-pickup is the real failure mode, not a $21 renewal. |
| 3 | **Separate TF root `infra/rundevoo-run/`**, same Cloudflare account | jikigai-dns plan D1 conclusion: the prod merge-apply resolves every root variable before `-target` pruning — a new no-default var in `apps/web-platform/infra` can wedge the whole prod apply. Separate state makes prod-reach structurally impossible. Same account keeps registrar+DNS consolidated; a separate CF account buys isolation against a threat the bootstrap pattern already closes. |
| 4 | Zone **import**, not create | Cloudflare Registrar purchase auto-creates the zone in-account; TF `import`s it. Provider pinned `~> 4.0` → dump schema locally, never trust docs (jikigai plan line 158 lesson). |
| 5 | Zone-scoped `Zone:DNS:Edit` credential via **bootstrap ephemeral-admin** pattern | `hr-tf-variable-no-operator-mint-default`; account-admin token exists for minutes, mints `cloudflare_api_token` resources, self-revokes (`apps/claevidence/infra/bootstrap.sh` precedent). |
| 6 | Mail-spoof hardening on day one: **null MX (RFC 7505), `v=spf1 -all`, DMARC `p=reject`, DNSSEC on** | CLO: a domain that can neither send nor be spoofed is the safe-by-default posture for a domain with no mail product. Matches soleur.ai email-auth discipline in the negative. |
| 7 | Apply workflow + drift matrix + destroy-guard triple ship **with** the root | Per CTO inventory: `apply-*.yml` mirroring `apply-sentry-infra.yml`, `scheduled-terraform-drift.yml` matrix entry (hardcoded list), `destroy-guard-filter-*.jq` + counter test + CODEOWNERS rows, `encryption-posture-ledger.json` `non_store_types` needs `cloudflare_zone` added (lint is fail-closed). |
| 8 | Dual ledger entries + `domains.md` row | Recurring `$21.20/yr` + One-Time registration rows (soleur.ai precedent at `expenses.md`); unrecorded domains die unobserved (jikigai.com lesson). |
| 9 | Article 30 register: dated amendment or new PA naming the rundevoo.run surface | CLO: register predicate already reaches it (Jikigai controller); minimal processing (edge/DNS logs) until a product exists. |
| 10 | Standing agent-side constraints carried to the product brainstorm | No outbound email from the domain; no real personal data on the surface (`cq-test-fixtures-synthesized-only` extends to seed data); deploy-to-public-domain only via PR-merge → CI (never direct agent push) when an app exists. |

## Rejected / deferred options

- **Staged onboarding** (TF root but defer apply-workflow/drift/destroy-guard):
  rejected — leaves no drift detection and widens the gap the jikigai plan
  already enumerates; full wiring is mechanical.
- **Purchase + ledger only**: rejected — leaves the domain unhardened and
  spoofable; violates the Terraform-only DNS posture as soon as any record is
  needed.
- **Separate Cloudflare account** for the zone: rejected — doubles registrar,
  Doppler, Better Stack, Sentry, token plumbing; Registrar anchors the zone in
  the account that buys it.
- **Subdomain of soleur.ai** (`sandbox.soleur.ai`): rejected — shares the
  `*.soleur.ai` cookie/security boundary and brand domain; worst of both
  worlds for a future public product.

## Open Questions

- Product shape for rundevoo.run — dev tool/SaaS, content site, API, or other
  **(out of scope — deferred to a follow-up brainstorm when the operator
  decides)**. That brainstorm owns: app repo placement (monorepo `apps/` vs
  separate `jikig-ai/` repo — separate repo is the more faithful dogfood per
  CTO), hosting substrate (Hetzner host vs CF Pages), access posture
  (public vs CF Access-gated), and legal pages (standalone notice vs Privacy
  Policy scope amendment — the amendment path triggers the canonical↔mirror +
  SHA re-pin + DSAR-lockstep machinery).
- Whether rundevoo.run is the ADR-030 **founder-as-first-tenant** validation
  vehicle (its open questions — cold-start provisioning automation,
  per-provider ToS for "agent creates accounts," meta-audit log, offboarding —
  become blocking scope if yes).
- Trademark knock-out search on "rundevoo" (coined term, low conflict; cheap
  diligence, operator homework).
- Housekeeping: confirm soleur.ai's registrant entity is Jikigai SARL (repo
  records registrar/cost but not registrant).
- Cloudflare Registrar premium-tier check on `rundevoo.run` at checkout —
  Cloudflare's API refuses premium-tier registrations (verified available via
  RDAP, but premium flag is only visible in the registrar flow).

## User-Brand Impact

- **Artifact:** the rundevoo.run domain + its DNS/zone posture — the public
  surface a future Jikigai product will be published under.
- **Vector:** worst case, an unhardened or agent-published surface under a
  company-owned domain is spoofed (phishing email) or serves arbitrary
  agent-authored content to a third party, attributable to Jikigai SARL.
- **Threshold:** `single-user incident`.

## Lane

`cross-domain` (auto per #5175 — `USER_BRAND_CRITICAL=true` set unconditionally).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Internal incubation, not a customer-facing roadmap row; public
exposure is acceptable only as a deliberate choice — baseline controls
(noindex/disclaimer when a site exists, no real user data, an uptime monitor so
it can't silently rot). A separate domain is the cleanest possible
proof-of-work showcase if the product goes public; the phase-1 domain+DNS-only
scope is correct.

### Legal (CLO)

**Summary:** No threshold-catalog trigger; registrar ToS acceptance is the only
legal event. Registrant = Jikigai SARL, org email, WHOIS privacy; null-MX +
SPF `-all` + DMARC reject before the domain is reachable; Art. 30 register
entry/amendment; legal pages only when the product accepts third-party input
(standalone notice preferred over amending the published corpus); agent-side
constraints (no email, no third-party PII publication). GDPR-gate fires only if
the later app adds PII-touching surfaces — note the canonical path regex covers
`apps/web-platform/` only, so a different-path app needs a manual invocation.

### Engineering (CTO)

**Summary:** Separate TF root, same account — the deferred jikigai plan is the
checklist minus its hard parts. Enumerated onboarding inventory: R2-backed root,
zone import, bootstrap-minted zone-scoped token, apply workflow + drift leg +
destroy-guard triple, `encryption-posture-ledger.json` `non_store_types` entry,
`domains.md` ledger row, Doppler `TF_VAR_*` before merge (ADR-065). Deploy
guards precede first app deploy: PR-merge → CI only, test-surface-scoped
credentials, off-private-net host. Complexity: medium (~2-4 PRs). Recommends
capturing an ADR for the blast-radius boundary.

### Operations (COO)

**Summary:** Reuse Cloudflare Registrar — measured `.run` pricing makes promo
registrars a ~$18 first-year saving against a third vendor account (the
jikigai.com sprawl failure mode). Dual ledger entries + `domains.md` row;
auto-renew ON; ~$21/yr doesn't trip the cost-model threshold. Registrar
constraint: Cloudflare requires Cloudflare nameservers — fine given the
Terraform-DNS posture.

## Capability Gaps

None blocking. Noted (evidence-backed):
- No standing zone-create/token-mint automation for *our own* account —
  `soleur:provision-cloudflare` mints tenant-scoped tokens only and requires a
  zone ID input (`plugins/soleur/skills/provision-cloudflare/SKILL.md`); the
  bootstrap-ephemeral pattern in `apps/cla-evidence/infra/bootstrap.sh` covers
  the gap procedurally.
- `cloudflare_zone` is absent from
  `scripts/encryption-posture-ledger.json` `non_store_types` (verified by grep —
  only `cloudflare_zone_dnssec`/`zone_settings_override` present);
  `lint-encryption-posture.py` is fail-closed → must be added in the same PR.
