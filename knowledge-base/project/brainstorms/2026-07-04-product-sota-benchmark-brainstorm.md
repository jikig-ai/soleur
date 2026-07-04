# Brainstorm: Product SOTA-Benchmark capability for tenant founders

- **Date:** 2026-07-04
- **Status:** Decided — shape locked, build deferred
- **Lane:** cross-domain
- **Brand-survival threshold:** single-user incident
- **Inciting event:** peer-plugin audit of [MerlijnW70/sota-scan](https://github.com/MerlijnW70/sota-scan) (2026-07-04) — see `knowledge-base/product/competitive-intelligence.md` Tier 1 + PR #5996
- **Related:** mechanic-extraction issues `#5993` (gap/impl confidence), `#5994` (persisted rubric+diff), `#5995` (clustering-for-fairness); ADR-084

## What we're building (decided shape)

A **tenant-facing product-benchmark sub-mode of `competitive-analysis`** — NOT a standalone skill, NOT a code benchmark.

It benchmarks *the founder's own product* (features / pricing / positioning) against the best players in *its* category, emits a **cited gap to-do list**, and treats **open-source alternatives as a first-class competitor class** (the real founder-grade slice CPO surfaced). It reuses the **sota-scan method** — cited grounding ("no source, no claim"), clustering-for-fairness, persisted rubric + since-last-scan diff — applied at the **product/market altitude**, not the code altitude.

**Build is deferred** behind a hard dependency (see Key Decisions). This brainstorm locks the *shape* so it is not re-litigated; it does not authorize implementation yet.

## Why this approach

The inciting audit surfaced that Soleur has no capability answering *"is the product I'm building competitive with the best in its category?"* for a tenant founder. Three altitudes were distinguished:

| Altitude | Question | Serves | Verdict |
|---|---|---|---|
| **Code** | Does my codebase match the best open-source repos in my domain? | Developers | **Rejected** — sota-scan's exact scope; developer-grade gaps ("lacks SARIF vs lefthook") are unactionable for non-technical founders (`business-validation.md` L34/L141-147: users rejected even a CLI, want a visual UI) |
| **Product/market** | Is *my* product's features/pricing/positioning competitive with the best in *my* category? | Founders (our users) | **Selected** — real founder-grade gap; `competitive-analysis` today is Soleur-centric (tracks Soleur's competitors), not tenant-product-vs-its-category |
| **Neither (defer)** | Value already captured by #5993/#5994/#5995 | — | Partially true, but the tenant-facing entry point + open-source-alternatives class is a genuine additional slice |

The operator selected the **product/market** altitude. Both domain leaders independently converged on **"sub-mode of `competitive-analysis`, not a standalone skill."**

Premise-challenge applied per `knowledge-base/project/learnings/2026-04-21-peer-plugin-audit-brainstorm-patterns.md`: we did **not** default to porting sota-scan wholesale (the 235-skill category-mismatch failure analog). The code-altitude port was explicitly rejected as serving developers, not our users.

## Key Decisions

1. **Sub-mode, not a standalone skill.** `competitive-analysis` already owns mode-dispatch (`SKILL.md:10-26`) + single-destination output routing (`competitive-intelligence.md`), and the `peer-plugin-audit` 4-section audit template (`references/peer-plugin-audit.md`) is the working shape. A standalone skill would duplicate this for no gain. (CTO; ADR-084)
2. **Product altitude, not code altitude.** Reject the sota-scan code benchmark for Soleur's users; build the product/market/positioning version. (CPO + operator)
3. **Open-source alternatives as a competitor class.** The real founder-grade slice is *"what alternatives (incl. open-source) would my buyers compare me to, and what do they have that I don't?"* — a positioning question, folded in as a competitor class. (CPO)
4. **DEFERRED — hard dependency on #5994 + #5995.** The sub-mode *consumes* persisted-rubric+diff (#5994) and clustering-for-fairness (#5995). Building before those land means reimplementing and throwing away that work. **Re-evaluation trigger: #5994 AND #5995 merged, AND a user requests the capability** (no user-demand signal exists today — CPO). (CTO)
5. **Architecture decision recorded** in ADR-084 so the shape + sequencing survive even if the deferred issue goes stale.
6. **Productize candidate:** this benchmark is itself a recurring-cadence artifact (like the monthly competitive scan) — the sub-mode should support scheduled re-runs with the since-last-scan diff once built.

## Open Questions (resolve at build time, post-dependency)

- Output routing for a *tenant's* product benchmark: `competitive-intelligence.md` is Soleur's own file — a tenant-run benchmark writes to the tenant's KB. Confirm the destination convention when the sub-mode is built.
- Token budget: sota-scan reports ~80–400k/run. CTO recommends capping peer-set size and reusing the `deep-research` adversarial-verify harness rather than building fresh.
- Whether the product-altitude rubric axis is per-category (reusable across tenants in the same space) or per-tenant.

## User-Brand Impact

- **Artifact:** the `competitive-analysis product-benchmark` sub-mode (a tenant-facing benchmark report).
- **Vector:** a benchmark that silently cites a wrong/fabricated competitor capability, or leaks one tenant's product data into another's report, would breach founder trust in the report's cited-grounding guarantee.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Product, Engineering

### Product (CPO)

**Summary:** The code benchmark is a developer-tool gap, not a Soleur-user gap — rightly rejected. The founder-grade slice is a *positioning* question ("what alternatives, incl. open-source, would my buyers compare me to") best folded into the tenant's competitive scan as a competitor class, not a new skill. No user-demand signal yet → default defer until a user asks.

### Engineering (CTO)

**Summary:** Sub-mode of `competitive-analysis`, not standalone — the scaffolding (mode-dispatch, output routing, the peer-plugin-audit 4-section template, the agent-native-audit fan-out pattern) already exists. Hard dependency: the sub-mode consumes #5994 (rubric+diff) and #5995 (clustering); defer until both merge or reimplement-and-throw-away. Maintenance risk is unbounded per-run token cost (~80–400k) — cap peer-set size, reuse `deep-research`'s verify harness. Capture the standalone-vs-sub-mode + sequencing decision as an ADR.
