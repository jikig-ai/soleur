---
date: 2026-07-07
status: paused-pending-product-validation
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [product, legal, engineering, sales, operations, finance]
---

# Beta-Tester Conversation Capture — Brainstorm

## ⏸ Session Pivot (2026-07-07)

Mid-brainstorm, the Sourcing Options Canvas surfaced that the quadrant [turnkey CRM + agent-native MCP + multi-tenant + resale-safe license] is **empty in the 2026 market** — a potential product opportunity. The operator opted to **validate an "agent-operated open-source CRM" as a separate Jikigai product** before investing further here (validation report: `knowledge-base/product/validation/2026-07-07-agent-operated-crm-validation.md`).

**Consequences:**
- The DB-backed capture build below is **paused** pending the product go/no-go. The design remains valid as the product's **v0 seed / first dogfood datapoint**.
- **This-week stopgap (no build):** capture beta conversations in the existing anonymized markdown format (`knowledge-base/support/community/user-conversations/`), initials/role/company-type only, **no raw PII** — leak-safe and compliance-clean.
- If the product verdict is GO, this capability spins into its own repo/roadmap; if NOT-NOW, resume this spec as an internal-only feature.

## What We're Building

A **private, per-tenant capture store for beta-tester / prospect conversations** that serves two lenses from one record: **Sales** (relationship, pipeline, deal value) and **Product** (feedback, pain points, feature signal). Primary interaction is **agent-mediated** — the operator feeds a conversation in (paste / note / forward) and `cro` / `cpo` agents structure, tag, and analyze it. Any visual surface, when needed, lives **inside the Soleur UI** (reusing the store's API), never a separate CRM app.

Built for **Soleur's own beta onboarding this week/next** AND as a **reusable capability every future tenant inherits** — so the compliance and multi-tenancy scaffolding is part of the feature, not an afterthought.

## Why This Approach — Sourcing Options Canvas

The storage/engine decision was evaluated across the full four-way sourcing space (this case motivated workflow issue #6163):

| Option | Privacy / residency | Productizes (multi-tenant) | Agent-native | Cost + ops | Licensing | Verdict |
|---|---|---|---|---|---|---|
| **Build — extend Supabase DB** | Best (EU-resident, no sub-processor, inherits DSAR/WORM) | Yes — rows, not servers | Native (shared auth/RLS) | Low (migration only) | None | **CHOSEN** |
| Buy — external SaaS (Attio / HubSpot Free) | New sub-processor; US-residency (Attio) / CLOUD Act (HubSpot EU) | No — company account ≠ tenant capability | Via API token | Recurring + DPA/Art.30 | — | Rejected |
| OSS self-host (Twenty / Corteza) | Good (self-run) | Twenty single-tenant → sprawl; Corteza multi-tenant but low-code toolkit | Twenty native MCP; Corteza build-it-yourself | Second app to operate (DB/auth/patch/backup) + new erasure path | **AGPL trap** (Twenty/Espo); Corteza Apache-safe | Rejected (turnkey+multi-tenant+safe quadrant is empty) |
| Connect existing (BYO-CRM) | Light (native MCP = no sub-processor) | Yes, for tenants who already have a CRM | Native | Deferrable per-CRM | — | **Deferred** (later phase) |

**Decisive reasoning:** extending the DB is *not* "building a CRM from scratch" — it's ~2 tables inheriting RLS + DSAR/WORM Soleur already operates; self-hosting an OSS CRM is the heavier build (a whole second product). The one thing OSS/external buys — a polished CRM UI — is explicitly *not* wanted (agent-mediated; embed in Soleur UI if ever). Unified-API vendors (Merge/Apideck, ~$500–650/mo) are premature at 0 users. BYO-CRM, when it comes, is cheap via CRMs' **native MCP servers** (HubSpot/Pipedrive/Attio/Salesforce all ship one), not a middleman.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Storage = per-tenant Supabase tables**, never git-committed markdown | Third-party PII in git = irreversible (Art. 17 erasure impossible); commit secret-scan is PII-blind. DB inherits RLS + DSAR/WORM. |
| 2 | **One dual-lens record**, not two logs | A single conversation carries both sales + product signal; per-note `lens` tags. Two logs = double-entry + drift (fatal for a solo founder). |
| 3 | **Operator-private** (owner-only RLS) | Matches a founder's private discovery notebook. Tester-visible records deferred. |
| 4 | **Agent-mediated capture**; UI (if any) embedded in Soleur UI | Operator's explicit steer. No separate CRM app. |
| 5 | **Pipeline fields feed Finance** | `amount`, `currency`, `stage`, `expected_close_date`, `stage_entered_at`, canonical stage→probability map → `pipeline-analyst` → `revenue-analyst`/`cfo`. |
| 6 | **Compliance scaffolding ships with the feature** | New Article 30 processing record + retention policy + DSAR/erasure wiring; `/soleur:gdpr-gate` mandatory at plan time. |
| 7 | **De-identified insight layer in git KB** (`knowledge-base/sales/`, `product/`) | Aggregate/pseudonymised signal (no identifiable person) is safe to commit and is where `cro`/`cpo` already synthesize. Raw PII stays in the DB. |
| 8 | **Deferred:** BYO-CRM connect (native MCP), tester-visible records, in-Soleur-UI surface, unified-API / Corteza multi-tenant re-eval | Not needed for the beta; each is its own follow-up. |

## User-Brand Impact

- **Artifact:** the private beta-tester capture store (Supabase tables + agent read/write route).
- **Vector:** an RLS gap or mis-scoped query exposes every beta tester/prospect in a workspace — third-party PII shared under implied confidence — a trust/relationship rupture and a GDPR breach (Art. 33, 72h clock). Git storage would make exposure permanent + secret-scan-invisible.
- **Threshold:** `single-user incident`.

## Open Questions (for plan/spec)

1. **Currency:** single reporting currency (USD, matching expense ledger) or multi-currency + FX normalization from day one? (CFO)
2. **Deal `amount` at beta stage:** hypothetical target ACV (design-partner list price) or $0 until paid conversion? Determines if early pipeline is directional or noise. (CFO)
3. **Consent mechanism:** legitimate-interest + notice at onboarding vs. explicit consent — and the privacy-notice line for beta testers. (CLO)
4. **Retention horizon:** e.g. delete on beta-exit + N months. (CLO)
5. **Record grain:** one row per contact vs. per company with nested contacts — affects `pipeline-analyst` aggregation. (CRO)
6. **Multi-member workspaces:** owner-private (like `conversations`) vs workspace-shared (like `email_triage_items`) — MVP is owner-private. (CTO)

## Domain Assessments

**Assessed:** Product, Legal, Engineering, Sales, Operations, Finance. (Not consulted: Marketing, Support.)

### Product (CPO)
Roadmap-aligned (Phase 4; #1440 problem-interviews / #1443 exit-interviews need this capture home); business-validation PASSes. One faceted record, not two logs. In-repo-vs-DB PII boundary deferred to CLO/CTO. Capability gap: no skill turns a raw conversation into a faceted record, and no routing makes cpo/cro read a shared capture location.

### Legal (CLO)
Third-party PII (names, employer, email, conversation content). Cleanest basis: Art. 6(1)(f) legitimate interest + LIA + notice, or explicit consent at onboarding. **Git-committed PII is a compliance anti-pattern** (Art. 17 erasure impossible). Correct boundary = Supabase + RLS + WORM + pseudonymisation (PA-27/PA-18 pattern). **New Article 30 processing record + retention + DSAR wiring required, and future tenants inherit the obligation** — scaffolding is the feature's compliance floor. `/soleur:gdpr-gate` mandatory at plan time.

### Engineering (CTO)
Mature per-tenant Supabase exists (161 RLS lines, `conversations` `visibility='private'` owner-only, `dsar_export_jobs`, WORM, `email_triage_items` workspace-scoped PII). Git route WRONG (permanent + secret-scan PII-blind). DB route CORRECT (reuse mig-075 template). Net-new: a CRM-shaped table (`beta_contacts` + `interview_notes`) + an **agent read/write path (MCP tool or app/api route)** — the make-or-break for agent-native, doesn't exist today. Complexity: medium (days). Recommends an ADR for the storage-boundary + data-model decision.

### Sales (CRO)
`knowledge-base/sales/` holds only battlecards — this bootstraps the first pipeline data layer. Smallest schema: `name, company, role, source, stage, next_action, next_action_date, last_contact` + dated conversation log. Record **stage-transition timestamps** (not just current stage) so `pipeline-analyst` can compute velocity; `deal-architect` needs per-contact legibility. One dual-lens capture, `lens: [sales|product]` per note. Tenant-generic (no Soleur-specific stages hardcoded).

### Operations (COO)
BUILD-light both horizons: reuse existing agent-native substrate; zero new vendor / sub-processor / recurring cost; private inside an already-DPA'd boundary (Hetzner/Supabase). An external tool = new sub-processor (DPA file + Art. 30 entry + expense-ledger row). A company-owned SaaS account doesn't productize. If tenants want their own CRM, the productized answer is a **BYO native-MCP integration pattern**, not a Soleur-owned seat.

### Finance (CFO)
No revenue/forecast artifact exists yet (only `cost-model.md`); pre-revenue, 0 users. At 0 deals, forecasting is theater — **value = capturing the fields now** so the forecast becomes possible once deals exist. Min fields: `amount`, `currency`, `stage`, `expected_close_date`, `created_at`, `owner`, + `stage_entered_at` day-one. Contract: single canonical **stage→probability** map (versioned, one place), currency stored raw + normalized at a dated FX rate, stage-transition timestamps. Schema ownership = CRO/pipeline-analyst; CFO chain consumes.

## Capability Gaps

1. **Agent read/write path to the tenant DB (Engineering/infra).** `cro`/`cpo` operate on git KB files only today; DB-resident records need an MCP tool or `app/api` route to reach `beta_contacts`. Evidence: CTO grep found no CRM-facing route; `conversations`/`messages` are UI-server-served, not agent-served. **Make-or-break for the agent-native requirement.**
2. **A capture skill.** No skill turns a raw pasted/dictated conversation into a faceted record (CPO). Candidate: `/soleur:capture-conversation`. — Productize Candidate.
3. **Canonical stage→probability table.** Needed by the Finance contract; does not exist (CFO).

## Productize Candidates

- `/soleur:capture-conversation` — parse a raw conversation into a faceted `beta_contacts` + `interview_notes` record (agent-mediated capture). File as follow-up.

## Deferred Items (→ follow-up issues)

1. **BYO-CRM connect** via native MCP (HubSpot first) — for tenants who already run a CRM. Re-eval unified-API (Nango self-host / unified.to) at ~8–10 tenants across 4+ CRMs.
2. **Tester-visible records** (agent-user parity; external-person auth surface).
3. **In-Soleur-UI surface** for contacts/pipeline (built on the store's API; wireframes required when scoped).
4. **Corteza multi-tenant CRM-engine spike** — only if a rich human-facing CRM UI becomes a product bet.
