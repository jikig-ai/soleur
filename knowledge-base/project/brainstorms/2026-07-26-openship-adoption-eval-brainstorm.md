---
date: 2026-07-26
topic: Openship adoption evaluation (openship.io / oblien/openship)
status: decided
decision: do-not-adopt
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [Product, Legal, Engineering, Marketing, Operations]
related_adrs: [ADR-030-multi-tenant-deploy-substrate, ADR-007, ADR-068, ADR-087, ADR-096, ADR-114, ADR-115, ADR-118, ADR-119, ADR-123, ADR-135, ADR-140, ADR-141, ADR-142, ADR-143]
---

# Brainstorm: Should Soleur adopt Openship?

## The question

The operator surfaced <https://openship.io> / <https://github.com/oblien/openship> and asked whether it makes
sense to adopt "for Soleur and Soleur users." That is two questions with different answers, and they were kept
separate throughout:

- **Q1 — internal:** replace or augment Soleur's own deploy pipeline with Openship?
- **Q2 — user-facing:** make Openship the substrate that deploys the apps Soleur's non-technical founders build?

## What Openship actually is (verified 2026-07-26)

Apache-2.0, self-hostable deployment platform / PaaS with built-in CI/CD. *"Point it at a repo — it builds,
ships, routes, and TLS-terminates your app."* Stack: Bun, pnpm, TypeScript, Postgres, Redis, OpenResty edge
router, Docker. Surfaces: CLI, web dashboard, desktop app, REST API, **and an MCP server** ("Drive deploys from
AI agents — Claude, Cursor, any MCP client").

Verified via `gh api repos/oblien/openship`, the repo contents, and the product site (`openship.io`, incl.
`/terms`, `/privacy`, `/trust`).

> **[2026-07-26 correction — read this before citing the table below.]** The first version of this table was
> gathered from `gh api` + the README only, and declared that exclusion of "the marketing surface" as rigor.
> Three rows were wrong *because of* that exclusion — legal entity, RBAC, and the disclosure process are all
> published on the product site. Multi-agent review refuted each in one command. The verdict did not change, but
> the reasoning did; see `## Session Errors` #6. The original claims are struck through below rather than
> deleted, because issue #6961's re-open triggers were calibrated against them.

| Signal | Value | Why it matters |
|---|---|---|
| Repo created | **2026-03-05** | 4.7 months old |
| Latest release | **v0.3.0** (2026-07-22) | Pre-1.0 |
| Commit on evaluation day | *"finalizing the initial stable release"* | **First stable release had not shipped as of the day it was evaluated** |
| Stars / forks | 8,596 / 686 | High hype velocity — a popularity signal, not a quality one |
| Commit concentration | Top author holds **226 of 386** commits on the default branch (**~59%**); 33 named contributors sum to 338, 37 incl. anonymous sum to 386 | Concentrated, but ~~78%~~ **overstated** in the first draft against an unmeasured `~290` denominator |
| Security policy | Root **`SECURITY.md` (4,458 B)** + a responsible-disclosure section on `/trust`. `community/profile` returns `security_policy: null`, which is an API-detection artifact, **not** absence | ~~"No published CVE / disclosure process"~~ — **refuted.** A null API field says a file was not detected, not that a process does not exist |
| Published advisories | 0 | No track record either way |
| Multi-tenancy / RBAC | **Present, in-instance.** `apps/api/src/modules/permissions/{routes,controller}.ts`; `/trust` documents *"role + resource grants"*, org-id isolation on proxied requests, and *"Credential custody"* | ~~"Not supported"~~ — **refuted.** The README's *"the first admin"* is **ordinal, not singular**; the first draft's `(singular)` gloss inverted the source. In-instance team RBAC is still **not** per-tenant credential isolation — see Q2 |
| Legal entity | **Oblien LLC** (`"legalName"` in the site's JSON-LD; footer on every page). `/terms` §12: governed by the laws of **Ireland**, courts of Dublin. `/privacy` publishes a sub-processor chain (Stripe, AWS, Hetzner, Cloudflare, Postmark, Sentry), EU-West storage, and a data-subject-rights process | ~~"None identified"~~ — **refuted.** A counterparty exists. The managed-cloud verdict now rests on a different, verifiable fact — see below |
| Managed cloud availability | `/terms` §02: **"Openship Cloud is not yet generally available."** | This — not the absence of an entity — is why the managed path is unavailable today |

Deployment modes: **bare** (single process, embedded DB, deploys out via SSH/cloud, any OS) and **compose**
(full Postgres + Redis + OpenResty + Docker stack, Linux-only, hosts apps on the same box).

## The decision

**Do not adopt, for either question.** Track it; re-open only against explicit triggers.

| Question | Verdict | Single strongest reason |
|---|---|---|
| **Q1 — Soleur's own pipeline** | **REJECT** | Openship satisfies none of the invariants Soleur's pipeline encodes, and would replace working, ADR-documented automation with a pre-1.0 control plane that sits *on the deploy path* — so when it breaks you cannot deploy the fix through it. |
| **Q2 — substrate for user apps** | **MONITOR (conditional)** | Soleur has no "deploy the user's app" capability today, and ADR-030 already decided the architecture for when it does. ADR-030's hard constraint binds **Soleur-owned infrastructure** holding N tenants' credentials — it forbids the Soleur-hosted-control-plane shape regardless of Openship's own tenancy model. |
| **Q2 via Openship's managed cloud** | **UNAVAILABLE today; PROHIBITED until a DPA is executed** | `/terms` §02: *"Openship Cloud is not yet generally available"* — there is nothing to adopt. If it ships, Oblien LLC is a real counterparty, so the Art. 28(3) question becomes *"will they sign a DPA, and do the SCC/transfer terms work?"* — an open question, **not** the settled impossibility the first draft asserted. |

## Why — the load-bearing findings

### 1. Q2 is a capability that does not exist yet

Repo research found no user-app deployment surface anywhere in the codebase. Workspaces are **data containers**
(per-user worktree leases over shared git-data, routed by a Postgres write-lease — ADR-068), not deployable
applications. The `provision-*` skills provision *Soleur's own* infrastructure. There is no "the founder's app
goes live at a URL" moment to put a substrate underneath.

No roadmap row owns this capability either — it is absent from P1–P5. Phase 4 (Validate + Scale, 67 open / 183
closed) is bottlenecked on **recruiting and interviewing five founders**, which is human outreach, not a deploy
substrate.

### 2. ADR-030 already eliminated this exact shape

This is not a greenfield question. `ADR-030 — Multi-tenant deploy substrate` (accepted 2026-05-14, issue #3723)
records a **hard constraint**:

> at no point may Soleur-owned infrastructure hold credentials for more than one tenant's cloud account at the
> same time … The substrate's correctness criterion is the **absence** of such a point.

It is hard precisely because the brand-survival threshold is `single-user incident`. Its brainstorm considered
and **eliminated** a Soleur-side persistent VM holding tenant deploy credentials, choosing per-tenant GitHub
Actions OIDC running inside *the tenant's own* repo and org.

A Soleur-hosted Openship control plane holding N founders' deploy credentials **is** the aggregation point that
ADR-030 exists to forbid. This holds on ADR-030 alone: the constraint is about **where the credentials sit**, not
about the substrate's feature set, so Openship's in-instance RBAC does not relieve it. (The first draft argued
this "by construction, from Openship's lack of multi-tenancy" — that premise was false and the argument is
withdrawn; the ADR-030 half was always the load-bearing one and stands unchanged.)

The only non-forbidden shape is Openship running **inside the tenant's own account** — which lands in ADR-030's
already-documented Approach C (BYOInfra) escape hatch, not in new architectural territory.

### 3. For Q1, Openship conflicts with the invariants rather than subsuming them

Soleur's own deploy path is not the generic SSH template in `plugins/soleur/skills/deploy`. It is: GitHub Actions
→ HMAC-signed POST behind **Cloudflare Tunnel + CF Access service tokens** → `adnanh/webhook` →
`apps/web-platform/infra/ci-deploy.sh` (**~2,950 lines**) doing cosign verify-by-digest, zot/GHCR fallback pull,
canary probe, drain, and a state-file protocol. No SSH on the deploy path.

| Invariant | ADR | Openship |
|---|---|---|
| Ingress / TLS | ADR-114 (one tunnel, origin-relative), ADR-118 (cert SANs track roster) | **Conflicts** — OpenResty is a second, competing ingress owner; ADR-114 explicitly rejects per-backend tunnels |
| Host lifecycle | ADR-143 (drain-gated active-active); ADR-115 (dedicated hosts **self-converge** their private NIC at boot) and ADR-123 (web hosts self-report but **do NOT self-converge** — detect + emit + alarm, no reboot) | **Conflicts** — Openship owns placement; these are Terraform- and NIC-aware, and ADR-115/123 are deliberately *opposite* policies per host class, not one convergence rule |
| Secrets | ADR-007 (Doppler) | **Conflicts** — Openship's own secret store is a second source of truth |
| At-rest encryption | ADR-119/140/141/142 + posture ledger | **Conflicts** — adds Postgres + Redis with no LUKS story; Layer-A lint fails on day one |
| Config refresh | ADR-135 (pull-based signed bundle), `hr-prod-host-config-change-immutable-redeploy` | **Conflicts** — Openship's CLI *pushes* config; the rule is image-replace-only |
| Supply chain | ADR-087 (cosign verify-by-digest), ADR-096 (self-hosted zot, deny-all-public) | **Conflicts** — builds on-host, no cosign-verified-digest run path |

Apache-2.0 self-hosting is **not** a sufficient hedge. Forking means a solo founder owns a
Bun/OpenResty/Postgres/Redis PaaS — strictly more surface than the `ci-deploy.sh` it would replace, plus new LUKS
and encryption-ledger obligations.

### 4. The MCP surface is the one genuinely aligned thread — and it is not yet a reason to adopt

Soleur is agent-native, and Openship's MCP server is real and on-thesis. But deploy-by-agent is already delivered
through Soleur's skill layer, and `provision-hetzner` is **deliberately** human-gated ("MUST run on the
operator's local machine", Art. 32, `read -s`). Openship's MCP would re-expose precisely what Soleur
intentionally keeps *out* of an agent-callable API. Worth watching; not worth adopting for.

### 5. Operationally it is a negative trade, at a bad moment

Self-hosting adds three stateful failure surfaces (Postgres, Redis, OpenResty) each needing its own host, volume,
IPv4, backup, LUKS posture, and monitors — and credible monitoring needs ~5–10 new monitors against **~$7.78 of
remaining headroom** under the $50 Sentry PAYG cap, where hitting the cap deactivates *all* monitors (#3958).
Managed cloud is unpriced ("pay only for compute and bandwidth"), duplicates Hetzner spend during any migration,
and needs an expense-ledger row before shipping.

## User-Brand Impact

- **Artifact:** the deploy substrate for Soleur's production app and (prospectively) for founders' applications.
- **Vector:** a pre-1.0 third-party control plane on the deploy path fails or is abandoned, and a founder's live
  application goes down with no self-rescue path — Apache-2.0 fork rights are a developer's escape hatch and are
  worthless to a non-technical founder.
- **Threshold:** `single-user incident`.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Do not adopt Openship for Soleur's own deploy pipeline. | Conflicts with ADR-087/096/114/118/135/143 and the encryption posture; replaces working automation with pre-1.0 dependency on the deploy path. |
| 2 | Do not adopt Openship as the user-app substrate. | The capability does not exist yet; ADR-030's hard constraint forbids the only shape Openship supports (single-admin control plane). |
| 3 | Managed-cloud path is unavailable today; permissible only after GA **and** an executed DPA. | `/terms` §02 — "Openship Cloud is not yet generally available", so there is nothing to adopt. *(Revised: the first draft said "prohibited outright, Art. 28(3) unsatisfiable, no legal entity" — Oblien LLC exists, so that basis was false.)* |
| 4 | Add Openship to `competitive-intelligence.md` as a **Tier 5 (DIY Stack)** watch entry + New Entrants line. | CMO: neither competitor nor complement today; seating it in Tier 0–3 would misrepresent threat level. |
| 5 | File one deferred issue carrying explicit re-open triggers. | Operator decision. Note ADR-030 precedent argues architectural-option deferrals belong in an ADR rather than the backlog; the operator chose an issue. |
| 6 | Do **not** author a spec.md for this brainstorm. | The outcome is a decision not to build. A feature spec would be an empty artifact; this document is the decision record. |

## Re-open triggers (all must hold)

**Recalibrated 2026-07-26 after review.** The first draft's triggers 2 and 3 were **already satisfied on the day
they were written** (Oblien LLC exists; `/trust` documents RBAC + credential custody), and trigger 2 conflated
governance with legal-entity existence. A gate whose conditions are already met is worse than no gate — a future
reader either believes two conditions newly cleared, or dismisses the issue as unreachable. Corrected:

1. Openship ships **v1.0 stable** and sustains releases for **12 months**.
2. **Bus factor improves measurably** — the top author's share of default-branch commits falls below ~40%
   (baseline 2026-07-26: **226 / 386 ≈ 59%**), or a second maintainer with release authority appears.
   *(This is a governance test only. Oblien LLC already exists — that is not a trigger.)*
3. It can run **inside the tenant's own cloud account** (ADR-030 Approach C shape), never as a Soleur-hosted
   control plane holding N tenants' credentials. **This is the load-bearing one** — it is the only trigger
   ADR-030's hard constraint actually turns on, and no amount of in-instance RBAC satisfies it.
4. Soleur reaches **N=2 tenants**, or a founder interview names deployment as their actual blocker.
5. For the managed path only: **Openship Cloud reaches GA** (`/terms` §02 currently says it is not), *and*
   Oblien LLC executes an Art. 28(3) DPA with workable transfer terms.

Already true as of 2026-07-26 and therefore **not** triggers: a named legal entity (Oblien LLC, Irish governing
law), in-instance RBAC, a published `SECURITY.md` + responsible-disclosure process, and a published
sub-processor chain.

## Non-Goals

- Any change to `ci-deploy.sh`, the tunnel topology, or the encryption posture.
- Any spike, pilot, or non-production install at this time (explicitly declined — negative toil trade against
  exhausted monitor headroom).
- Reversing or amending ADR-030.

## Open Questions

1. Does the **agent-native deploy** thread deserve its own brainstorm independent of Openship? Soleur's own app
   deploy is not agent-triggerable today, and `provision-*` is deliberately human-gated. Whether that gap should
   close — and how far — is a real question that Openship merely surfaced.
2. If Soleur ever builds the "founder's app goes live" capability, is ADR-030 Approach A still right at N=2, or
   does a tenant-side PaaS (Openship or otherwise) belong inside the per-tenant scaffold?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal *(Sales, Finance, Support — not relevant)*

### Product (CPO)

Q1 REJECT, Q2 MONITOR. "Deploy the user's app" has no roadmap row and is not what Phase 4 is blocked on — P4 is
bottlenecked on founder recruitment. Adopting a pre-1.0 PaaS mid-validation risks a breaking 1.0 landing during
recruitment. A non-technical founder sees a URL and TLS; the substrate underneath is invisible to them, so
swapping it earns no validation signal.

### Legal (CLO)

Apache-2.0 inbound is clean (obligations bite only on distribution — carry NOTICE if shipped into tenant infra;
§3 patent grant intact despite no CLA). Self-hosted: no new sub-processor, but Openship's Postgres + Redis must
land as LUKS entries or justified plaintext-exceptions in `encryption-posture-ledger.json` **before** merge per
ADR-140 — silence would falsify the ledger's coverage claim. Managed cloud: **unavailable** (`/terms` §02, not
GA), and gated on an executed Art. 28(3) DPA if it ships. At `single-user incident` threshold, a pre-1.0
dependency on the customer-hosting path is still hard to defend under Art. 28(1) "sufficient guarantees" —
though on *maturity* grounds, not on the absence of a disclosure process (one exists).

> **Correction (2026-07-26):** the CLO's assessment was delivered against the false premise that no legal entity
> existed, and it correctly reported `PROHIBITED` *given that premise*. Oblien LLC exists, with Irish governing
> law and a published sub-processor chain, so the Art. 28(3) analysis does not terminate — it proceeds to
> "will they sign, and do the transfer terms work?", which is unanswered. The Apache-2.0 and ADR-140
> ledger findings are unaffected.

### Engineering (CTO)

Q1 REJECT, Q2 MONITOR. Mapped every invariant a PaaS would own against Openship: conflicts on ingress, host
lifecycle, secrets, at-rest encryption, config refresh, and supply chain; subsumes multi-host routing only on
paper (loses drain-gating). ADR-030's credential ceiling makes the central-control-plane shape fatal for Q2.
Soleur has **no product MCP server** (34 API route groups, zero MCP), so Openship's MCP is not redundant — but
what it would expose is what Soleur deliberately human-gates.

### Marketing (CMO)

Neither competitor nor complement. Openship's ICP is developers who already know they need TLS termination;
Soleur's cannot read a Dockerfile. No shared buyer, budget line, or search query. Add as a **Tier 5** watch entry
plus a New Entrants line — not a Tier 0–3 competitor row. Narrative risk is asymmetric: a pre-1.0 single-maintainer
dependency under a customer's live app converts upstream abandonment into *Soleur's* outage. The "built on open
source, no lock-in" upside does not offset it — Soleur already owns no-lock-in more strongly via `provision-github`
(repos in the founder's own org from day one).

### Operations (COO)

REJECT. Self-hosting adds three stateful failure surfaces on the deploy-critical path with the solo operator as
sole pager. Monitoring needs ~5–10 new monitors against ~$7.78 remaining PAYG headroom. Managed cloud is unpriced
and duplicates Hetzner spend. Apache-2.0 does not mitigate continuity risk — the fallback is "solo founder
maintains a forked PaaS," strictly worse than today. **Net toil increases.**

## Session Errors

1. **Stale cost figure propagated into all five leader prompts — and the correction was itself wrong twice.**
   I sourced `~$81/mo COGS, break-even 2 users` from `roadmap.md` (lines 63, 74, 454 — anchored 2026-04-23).
   The COO corrected it to `$234.34`; I repeated that, and a review agent "verified" it by citing `$231.33`.
   All three are superseded intermediates from the review-note chain
   (`$200.11 → $231.33 → $234.34 → $223.39`). The authoritative figure is the **subtotal**, not a narrative
   note: `cost-model.md:204` reads **`223.39`**, and all three break-even tables (`:284`, `:297`, `:328`) agree
   at **5 users** — a ~2.75× understatement, not 2.9×.
   Three independent readers made the same error in one session because `cost-model.md` **contradicts itself**:
   line 204's subtotal says `223.39` while line 232's summary says `~$234/month`, both under the same
   `[expenses.md@2026-07-17]` anchor. → Filed as #6959; the self-inconsistency was added to it.
   **Prevention:** read the subtotal row or a break-even table, never a review note — and never a downstream
   summary. `roadmap-reconcile.sh validate` syncs milestone counts but **not** CFO figures, so this drift is
   undetected by design. The 2-line `roadmap.md` correction is folded into this PR.
2. **Prior-art sweep keyword set was too narrow.** The Phase 1.1 `find` used
   `openship|paas|deploy-platform|coolify|dokku|self-host` and returned one unrelated hit, so the brainstorm
   opened on a "greenfield evaluation" premise. The real prior art —
   `ADR-030-multi-tenant-deploy-substrate.md` plus its archived brainstorm, plan, spec, and a legitimate-interest
   assessment — was keyed on **"deploy substrate"**, a term absent from the sweep. It surfaced only when the CTO
   cited ADR-030. **Rule:** for an external-product evaluation, sweep the ADR corpus for the product's *function*
   ("deploy substrate", "multi-tenant deploy") in addition to competitor names, and search
   `knowledge-base/**/archive/` — archived artifacts stay canonical for decisions.
3. **`learnings-researcher` reported "zero prior evaluations of PaaS/deploy platforms" — correct for its scope,
   misleading as a global claim.** It searched `knowledge-base/project/learnings/` only, where the statement is
   true. The decisive prior art lived in the ADR corpus. A negative result from a scoped agent is not a
   repo-wide negative.
4. **Duplicate ADR numbers found.** `ADR-030` names both `inngest-as-durable-trigger-layer` and
   `multi-tenant-deploy-substrate`; `ADR-027`, `ADR-031`, `ADR-033`, `ADR-038` also collide. Citing "ADR-030"
   is ambiguous — this cost a wrong-file read mid-session. → Issue filed.
6. **Three of the five "verified facts" about the vendor were false — and the evidence method that produced
   them was declared as rigor.** The original table carried the banner *"Verified via `gh api` and the repo's own
   README — **not** from the marketing surface."* Legal entity, RBAC, and the disclosure process are all
   published on the product site. The method was **structurally incapable** of seeing those three classes, and
   excluding the only source that carried them was presented as methodological discipline. Specifically:
   - "Legal entity: None identified" → **Oblien LLC**, in the site's JSON-LD and every page footer.
   - "Multi-tenancy: Not supported" → `apps/api/src/modules/permissions/*` exists; `/trust` documents
     "role + resource grants" and "Credential custody". The README's *"the first admin"* is **ordinal**; the
     `(singular)` gloss inverted the source's meaning.
   - "No published CVE / disclosure process" → root `SECURITY.md` (4,458 B) + `/trust` responsible disclosure.
     `community/profile → security_policy: null` is an API-detection artifact; a null field says a file was not
     detected, not that a process does not exist.

   Each was refutable in one command. Two review agents converged independently.
   **This is the same defect as Session Error #2, in the opposite direction and in the same commit:** #2 was a
   *repo* sweep whose keyword set could not reach the prior art; this was a *vendor* sweep whose source set could
   not reach the entity, the RBAC docs, or the disclosure policy — and in both cases the negative was reported
   with the confidence of a measurement. The learning file's thesis ("a negative carries only the scope that
   produced it") was violated by the very document that states it.
   **Prevention:** for an external-product evaluation, the source set must include the product site (`/terms`,
   `/privacy`, `/trust`, `/security`, footer) and a `contents/` probe for `SECURITY.md`/`LICENSE`/governance
   files — an API-only sweep cannot answer legal, commercial, or policy questions. Never let an API null stand
   in for a fact about the world. And state each row as what was **observed**, not what was **inferred**:
   "`community/profile` returns null" is a measurement; "no disclosure process" is a claim.
   Also corrected here: commit concentration was **226/386 ≈ 59%**, not "225 of ~290 (~78%)" — the `~290`
   denominator matched no measurement; both the `Link: rel="last"` page count and the anonymous-contributor
   sum give 386.

7. **Roadmap phase-4 milestone drift** detected by `roadmap-reconcile.sh validate`
   (`roadmap=56o/179c` vs `milestone=67o/183c`). Not corrected in this worktree — the sanctioned fix is the
   roadmap-review cron, which opens a reviewed PR. Surfaced to the operator. The CPO pulled live milestone
   numbers directly, so no assessment was affected.

## References

- <https://openship.io> · <https://github.com/oblien/openship> (Apache-2.0)
- `knowledge-base/engineering/architecture/decisions/ADR-030-multi-tenant-deploy-substrate.md`
- `knowledge-base/project/brainstorms/archive/20260515-104421-2026-05-14-soleur-managed-deploy-substrate-multi-tenant-brainstorm.md`
- `knowledge-base/legal/legitimate-interest-assessments/2026-05-14-tenant-deploy-substrate-lia.md`
- `knowledge-base/finance/cost-model.md` (authoritative COGS; roadmap figures are stale)
- `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md`
- `knowledge-base/project/learnings/2026-03-25-verify-platform-limits-during-brainstorm.md`
- `knowledge-base/project/learnings/2026-02-25-platform-risk-cowork-plugins.md`
- `apps/web-platform/infra/ci-deploy.sh`, `tunnel.tf`, `proxy-tls.tf`
