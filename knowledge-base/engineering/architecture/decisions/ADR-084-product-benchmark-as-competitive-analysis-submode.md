# ADR-084: Product SOTA-benchmark as a `competitive-analysis` sub-mode, deferred behind its mechanic dependencies

- **Status:** Accepted
- **Date:** 2026-07-04
- **Issue:** brainstorm 2026-07-04 (`knowledge-base/project/brainstorms/2026-07-04-product-sota-benchmark-brainstorm.md`); deferred tracking issue filed at brainstorm-end. Inciting event: peer-plugin audit of [MerlijnW70/sota-scan](https://github.com/MerlijnW70/sota-scan) (PR #5996, `competitive-intelligence.md` Tier 1).
- **Depends on:** `#5994` (persisted rubric + since-last-scan diff), `#5995` (clustering-for-fairness in `peer-plugin-audit`).

## Context

The sota-scan peer-plugin audit surfaced that Soleur has no capability answering, for a **tenant founder**, *"is the product I'm building competitive with the best in its category?"* Existing coverage: `competitive-analysis` tier scan (Soleur's **own** business competitors), `peer-plugin-audit` sub-mode (skill-library peers), `agent-native-audit` (codebase vs fixed agent-native principles). None benchmark a tenant's product against its category with a cited gap to-do list.

Two shape questions had to be settled before any build:

1. **Standalone skill vs. sub-mode of `competitive-analysis`?**
2. **Code altitude (sota-scan's exact scope) vs. product/market altitude?**

And one sequencing question: three sota-scan mechanics are already being extracted into existing skills (`#5993` gap/impl confidence → review/one-shot; `#5994` persisted rubric+diff → agent-native-audit; `#5995` clustering-for-fairness → peer-plugin-audit). A product-benchmark **consumes** #5994 and #5995.

Domain-leader input (brainstorm Phase 0.5): CPO rejected the code altitude as a developer-tool gap (Soleur's users are non-technical founders who want a visual UI, not developer-grade gaps like "lacks SARIF vs lefthook"); CTO independently recommended a sub-mode over a standalone skill and flagged the hard dependency on #5994/#5995.

## Decision

1. **Build it as a sub-mode of `competitive-analysis`, not a standalone skill.** `competitive-analysis` already owns multi-mode dispatch (`plugins/soleur/skills/competitive-analysis/SKILL.md:10-26`), single-destination output routing, and a working 4-section audit template (`references/peer-plugin-audit.md`). A product-benchmark is that same shape pointed at product/market comparators. A standalone skill would duplicate dispatch + routing for no gain.
2. **Target the product/market altitude, not the code altitude.** Benchmark the founder's product (features / pricing / positioning) against the best in its category — including **open-source alternatives as a first-class competitor class**. Reject the sota-scan code-vs-open-source-repo benchmark for Soleur's users.
3. **Reuse the sota-scan *method*, not the *product*.** Cited grounding ("no source, no claim"), clustering-for-fairness, and persisted rubric + since-last-scan diff, applied at product altitude. MIT source → prose adaptable with attribution.
4. **Defer the build until `#5994` and `#5995` merge.** The sub-mode consumes both; building first means reimplementing rubric-persistence and peer-clustering, then discarding them. Re-evaluation trigger: **both merged AND a user requests the capability** (no user-demand signal today).

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Standalone `product-benchmark` skill** | Duplicates `competitive-analysis` mode-dispatch + output routing; larger surface, higher maintenance, no gain over a sub-mode. |
| **Port sota-scan wholesale (code altitude)** | Serves developers, not Soleur's non-technical founders — the 235-skill category-mismatch failure analog (`2026-04-21-peer-plugin-audit-brainstorm-patterns.md`). |
| **Build the sub-mode now** | Hard dependency on #5994/#5995 (not yet merged); building first is reimplement-and-throw-away work. |
| **Don't build at all** | The mechanic-extraction issues capture *mechanics* but not the tenant-facing entry point + open-source-alternatives competitor class — a genuine additional slice worth keeping on the roadmap. |

## Consequences

- **Positive:** the shape is locked and won't be re-litigated; the build is correctly sequenced behind its dependencies; no premature token/maintenance cost incurred.
- **Negative / watch:** the deferred issue must not go stale — this ADR is the durable record if it does. When built, resolve the open questions from the brainstorm: tenant-KB output routing (vs Soleur's own `competitive-intelligence.md`), per-run token cap, and per-category vs per-tenant rubric axis.
- **Maintenance guardrail (CTO):** cap peer-set size and reuse the `deep-research` adversarial-verify harness rather than building a fresh web-scan/verify loop (~80–400k tokens/run otherwise).
