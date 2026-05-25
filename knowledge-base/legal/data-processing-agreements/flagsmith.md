---
vendor: Bullet Train Limited (trading as Flagsmith)
role: processor (Web Platform feature-flag identity-trait evaluation)
status_snapshot_date: 2026-05-25
register_activity_refs: [PA-1, PA-2]
dpa_mechanism: auto-incorporated-via-tos
notification_clock_state: not-triggered-zero-customer-dpas
---

# Bullet Train Limited (Flagsmith) — DPA snapshot

Cross-reference to the Article 30 Vendor Mapping row in
`knowledge-base/legal/article-30-register.md` (Vendor / Sub-Processor
Mapping section) and to Processing Activities PA-1 (Account &
Authentication) and PA-2 (Conversation Data) Recipients columns. PR-2
of umbrella #4456 is the first PR that egresses workspace `orgId`
identity traits to Flagsmith; this row MUST land before PR-2 per
the umbrella plan §"Implementation Phases" PR sequencing constraint.

## Vendor identity

| Field | Value |
|---|---|
| **Legal entity** | Bullet Train Limited (trading as Flagsmith) |
| **Companies House registration** | 12353266 (England and Wales) — register lookup: `https://find-and-update.company-information.service.gov.uk/company/12353266` |
| **Registered office (per Companies House — authoritative)** | 66 Paul Street, London, England, EC2A 4NA |
| **Operating / customer-facing address** | 86-90 Paul Street, London, EC2A 4NE (4th Floor per Flagsmith Privacy Policy; 3rd Floor per Flagsmith ToS — floor disagreement acknowledged by vendor). Operating address differs from the Companies House registered office. |
| **Governing law** | English law; exclusive jurisdiction of the courts of England and Wales (Flagsmith ToS) |

## DPA + transfer mechanisms

| Field | Value |
|---|---|
| **DPA mechanism** | AUTO via the **Data Processor Appendix to the Flagsmith Terms of Service** (no separate signature instrument; embedded clause in the customer-side ToS at https://www.flagsmith.com/terms-of-service). Same shape as Anthropic Commercial Terms §C, Stripe Services Agreement, Resend ToS §7. |
| **DPA effective date** | Effective on the operator-side acceptance of the Flagsmith Terms of Service (free-tier sign-up); pinned 2026-05-25 (operator-attested at PR-1 of umbrella #4456). |
| **Transfer mechanisms** | UK IDTA (UK Addendum to EU SCCs) + EU SCCs Modules 2 + 3, as belt-and-suspenders to the EC adequacy decision for the UK (Commission Implementing Decision (EU) 2021/1772 of 28 June 2021, currently in force; review-pending). Flagsmith's onward US sub-processors (AWS, Sentry, Slack, Amplitude, Stripe, Chargebee, Reo Dev, Google Analytics, Google Docs) covered by SCCs Module 3 flow-down + DPF where available. |
| **Region (data processed)** | **Not pinned on the free / managed-SaaS tier.** Flagsmith managed SaaS uses the global edge network at `edge.api.flagsmith.com` (AWS-hosted; data centers include California, London, Sydney, São Paulo, Seoul per Flagsmith hosting docs). Region pinning is only available on the Private Cloud tier ("isolated single-tenant deployment hosted with your chosen cloud provider in your chosen region"). The operator does NOT use the Private Cloud tier today. |
| **Flagsmith ToS URL** | https://www.flagsmith.com/terms-of-service (Data Processor Appendix is the in-document DPA) |
| **Flagsmith Privacy Policy URL** | https://www.flagsmith.com/privacy-policy |
| **Flagsmith Sub-Processors URL** | https://www.flagsmith.com/gdpr-sub-processor-list |

## Flagsmith's own sub-processors (Schedule 2 flow-down)

As published at https://www.flagsmith.com/gdpr-sub-processor-list, last updated 13 October 2025:

| Sub-processor | Purpose | Region |
|---|---|---|
| Amazon Web Services (AWS) | Data hosting | USA |
| Sentry | Reporting and monitoring | USA |
| HubSpot | Business sales | Ireland |
| Slack | Chat communications | USA |
| Amplitude Analytics | Analytics | USA |
| Reo Dev | Intent data | USA |
| Xero | Business accounting | New Zealand |
| Chargebee | Subscription and billing | USA |
| Stripe | Payment processing | USA |
| Google Analytics | Web and application analytics | USA |
| Google Docs | Online documents and spreadsheets | USA |

## Scope: what Jikigai sends to Flagsmith

PR-2 of umbrella #4456 introduces the first server-side tenant-boundary
Flagsmith call. The call shape is
`getIdentityFlags(identifier, { role, orgId }, /*transient*/ true)` against
`edge.api.flagsmith.com`:

- **`identifier`** — operator-supplied identity key (pseudonymised; not the
  raw `userId`; canonical shape determined at PR-2 plan-cycle time).
- **`role`** — string in `{anon, user, admin, dev, prd}` (no personal data).
- **`orgId`** — workspace UUID (workspace metadata; not itself a direct
  identifier of a natural person; cross-referenced via Supabase
  `workspace_members` for membership).
- **`transient: true`** — MANDATORY data-minimisation lever (effective on
  PR-2 of umbrella #4456 merge). Opts out of Flagsmith server-side
  **identity persistence**. The flag-evaluation request still transits
  Flagsmith; only the persisted-identity record on Flagsmith's side is
  suppressed. Verified against the Flagsmith Node SDK signature at
  `apps/web-platform/node_modules/flagsmith-nodejs/build/cjs/sdk/index.d.ts:89`
  (third arg `transient?: boolean`). All `getIdentityFlags(...)` call sites
  in the codebase MUST pass `transient: true` after PR-2 lands the CI grep
  sentinel that enforces it (mirror of the
  `apps/web-platform/test/dsar-message-redact-fields-sweep.test.ts` shape).
- **Single-member workspace linkability note** — `orgId` is workspace
  metadata and not itself a direct identifier of a natural person; however,
  for single-member workspaces (one user, one organisation) `orgId` and
  the underlying `user_id` are 1:1 and `orgId` becomes effectively a
  pseudonymous identifier of that single natural person under Article 4(5)
  GDPR. Re-identification from `orgId` alone requires the Soleur-side
  `organizations` table join (Flagsmith holds neither side of that join),
  preserving the Article 4(5) pseudonymisation property at the Flagsmith
  boundary.

**Current code-side state at PR-1 merge (before PR-2):** the single
existing call site at `apps/web-platform/lib/feature-flags/server.ts`
calls `getIdentityFlags(\`role:${role}\`, { role })` — third positional
`transient` argument is omitted (defaults to `undefined`/`false` on the
Flagsmith SDK side), and the trait map carries only `role` (no `orgId`).
The role-bucket key has cardinality ≤ 5 (`{anon, user, admin, dev, prd}`)
and is not per-user identity. PR-1 lands the Article 13(3) prior-disclosure
of the post-PR-2 data envelope so the customer-facing Privacy Policy /
DPD / GDPR Policy / Article 30 register surfaces are stable before any
per-user-identity trait egresses to Flagsmith.

## §6.1 30-day notification clock state

`knowledge-base/legal/tenant-dpa-register.md` has **zero** rows in
`status: dpa-signed` at this snapshot date (2026-05-25 — verified via the
PR-2 pre-merge tenant-DPA guard). The §6.1 30-day Customer notification
clock for adding Flagsmith as an Authorized Sub-processor is therefore
**not triggered**: there is no Customer to notify. The clock will fire on
the first executed Customer DPA per the data-processing-agreement-template
§6.1 standing authorization mechanism; Flagsmith will appear in that
DPA's Schedule 2 at signing time per the §6.5 single-source-of-truth
resolution.

## TOMs relied on (Art. 32)

Soleur's TOMs that bound Flagsmith-side risk under PA-1 + PA-2:

- `transient: true` on every `getIdentityFlags(...)` call (data-min
  lever — opts out of Flagsmith server-side identity persistence).
- Dual-control gating: every flag flip is the AND of the Flagsmith
  boolean AND a server-side env-allowlist (`*_ALLOWLIST_ORG_IDS`) — a
  Flagsmith segment misconfiguration alone cannot expose data
  cross-tenant.
- LRU-bounded `_roleCache` keyed on `(role, orgId)` (N=1000 env-tunable)
  prevents DDoS-amplified unbounded growth of in-process cache state.
- Fail-closed-to-OFF behaviour on Flagsmith SDK timeout / network
  error; `reportSilentFallback(op='flagsmith.getIdentityFlags')` mirrors
  the failure to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
- WORM `flag_flip_audit` (migration 071, PR-2) appends an immutable
  evidence row before every Flagsmith mutation; skill abort exit-code 4
  on audit-row append failure (no silent skip).

## Activities in scope

- **PA-1 (Account & Authentication)** — Flagsmith returns the runtime
  enablement of `team-workspace-invite` for the resolving identity;
  affects the workspace-invite UI/API gate.
- **PA-2 (Conversation Data, including BYOK delegations)** —
  Flagsmith returns the runtime enablement of `byok-delegations` for
  the resolving identity; affects the BYOK key-routing decision inside
  the conversation runtime.

## Re-evaluate when

- Flagsmith publishes a revised ToS / Data Processor Appendix or revises
  the sub-processor list (snapshot date above goes stale).
- Operator promotes to the Flagsmith Private Cloud tier (region pinning
  becomes available; transfer mechanism narrows).
- The UK loses its EC adequacy decision (the original Commission
  Implementing Decision (EU) 2021/1772 of 28 June 2021 carried a
  4-year sunset to June 2025; the Commission extended adequacy
  via a renewed decision in late 2025 covering 2025-2031 —
  re-verify the renewed decision text at PR-2 plan-cycle time
  per the plan's "premise probes" workflow) — at that point UK
  IDTA becomes the load-bearing transfer instrument and §11.2
  reclassifies accordingly.
- The Web Platform begins sending any identity trait beyond `role` +
  `orgId` (e.g., raw `userId`, email, IP) — data-min posture must be
  re-assessed.
- First Customer DPA executes — Flagsmith promotes into that customer's
  Schedule 2 with §6.1 30-day notification.

## Refs

- `knowledge-base/legal/article-30-register.md` — PA-1 + PA-2 Recipients;
  Vendor / Sub-Processor Mapping row.
- `knowledge-base/legal/compliance-posture.md` Vendor DPA Status table.
- `knowledge-base/legal/data-processing-agreement-template.md` Schedule 2
  + §11.2 SCCs classification.
- `knowledge-base/legal/tenant-dpa-register.md` — §6.1 clock state
  baseline.
- `docs/legal/privacy-policy.md` §5.15 (PR-1).
- `docs/legal/data-protection-disclosure.md` §4.2 + Eleventy mirror at
  `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (PR-1).
- `docs/legal/gdpr-policy.md` §2.2 (PR-1).
- Umbrella issue #4456; draft PR #4455; plan
  `knowledge-base/project/plans/2026-05-25-feat-audit-env-flags-flagsmith-policy-plan.md`.
