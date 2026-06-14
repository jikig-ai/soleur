---
date: 2026-06-14
topic: KB consolidation pass — reframed to recall-quality prereq
status: brainstorm-complete
issue: "#5292 (deferred consolidation tracker) + new prereq issue"
lane: cross-domain
brand_survival_threshold: single-user incident
leaders: [CPO, CLO, CTO]
---

# Brainstorm: Background KB Consolidation Pass → Recall-Quality Prereq

## What We're Building

**Not** the thing issue #5292 literally asks for. After cross-domain assessment (CPO + CLO + CTO,
all unanimous), the scheduled `compound --consolidate` pass is **deferred**, and this brainstorm
captures the **falsifiable prerequisite** that must ship and prove out first:

> Make learnings-corpus **recall quality observable and recurring**, define a **staleness/redundancy
> metric**, and gate any future consolidation automation on **measured recall degradation** — not on
> competitor-mimicry or a hypothetical "the KB is too big" intuition.

The consolidation pass (merge/archive/distill across the 1,554-file `learnings/` corpus, propose-only
review PR) becomes a **deferred downstream** with concrete re-evaluation criteria, tracked on #5292.

## Why This Approach

Issue #5292 proposes a "sleep-time compute" analog (inspired by competitor cofounder.co) — a background
pass that consolidates redundant/stale learnings and opens a review PR. Research and the leader triad
surfaced three facts that invert the framing:

1. **~80% of the machinery already exists.** `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
   (ADR-027/ADR-033) already reads `learnings/`, filters PII + retired entries, calls Anthropic to
   cluster, and opens a review PR via `safeCommitAndPr` (GitHub App auth, Sentry-monitored). It
   *promotes* learnings into constitution rules.
2. **The prior attempt at exactly this pattern is dead.** `knowledge-base/project/learnings/promotion-log.md`
   scaffolds the full consolidation-PR lifecycle but has **0 real data rows**; its driver
   `scheduled-compound-promote.yml` is **missing** (never wired live). Empirical proof of the
   write-mostly failure mode — not a hypothetical.
3. **Recall measurement already exists but went quiet.** `scripts/learning-retrieval-bench.sh` (#4043,
   schema v2 #4176) produced `learning-retrieval-metrics-*.json` on **2026-05-19 and 2026-05-20**, then
   stopped. We cannot claim recall is degrading because we stopped measuring it.

The honest goal is **agent recall quality**, not human navigability — no human (least of all the
non-technical founder) reads 1,554 raw learnings. The consumer is Soleur's own agents at recall time
(`learnings-researcher`, `kb-search`). And auto-consolidation is **lossy by construction** — it trades
away the verbatim/auditable moat we differentiate on against Cofounder.

This mirrors the #2723 tech-debt-tracker reframe verbatim: an artifact that accretes with ~zero closures
means automation producing *more entries* (consolidation PRs nobody merges) compounds the backlog, not
the knowledge. Prereq first, 60-day evidence window, kill-if-no-signal.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Do not build the scheduled consolidation pass now.** | Unanimous CPO/CLO/CTO defer; dead prior attempt (promotion-log.md) is empirical evidence of the write-mostly failure mode. |
| 2 | **Ship the recall-quality prereq instead.** | Make `learning-retrieval-bench.sh` recurring + observable; define a staleness/redundancy metric; gate consolidation on measured degradation. |
| 3 | **Gate, don't schedule, the consolidation build.** | Re-eval criteria (ALL must hold): recall metric shows measured degradation over the window AND a named founder/agent outcome AND a closure-lifecycle exists so review PRs actually land. |
| 4 | **If ever built: enhance the existing Inngest cron, not a new GHA cron.** | A fresh GHA path is an architectural regression (team migrated off GHA per ADR-027). Sibling `cron-compound-consolidate.ts` inherits auth/Sentry/ADR-033 coverage. *(Deferred — captured for #5292.)* |
| 5 | **If ever built: propose-only, never auto-mutate; batch per subdir.** | VERBATIM/auditable moat → LLM proposes grouping, deterministic script does `git mv`; one PR = one subdir = founder-readable changeset. *(Deferred.)* |
| 6 | **CLO exempt-class is mandatory whenever this is built.** | `compliance/`, `security-issues/`, incident/PIR records are GDPR Art. 5(2) accountability evidence — NON-mergeable, NON-archivable, in-place + discoverable. Found a live one: `compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`. |
| 7 | **Distillation is additive-only.** | New abstraction files may read all sources; may never edit/delete a source learning body. Source immutability is the line between safe distillation and lossy rewrite. *(Carried into #5292 + spec guardrails.)* |
| 8 | Visual design: N/A | Pure tooling/infra; no UI surface (Phase 3.55 skipped legitimately). |

## Open Questions

- **What is the staleness/redundancy metric?** mtime-age is the cheap proxy CTO floated, but age ≠ stale
  (a 2-year-old learning can be load-bearing). Likely a composite: recall-miss rate from the bench +
  near-duplicate density from cheap embeddings. To be decided in `plan`.
- **What recall-degradation threshold unblocks consolidation?** Needs a baseline from re-running the bench;
  no current cadence to derive it from.
- **Closure-lifecycle shape** (the #2723 prereq-to-the-prereq): do learnings even need a `status`/`superseded_by`
  frontmatter field, or is archival the only "closure"? Spec proposes the minimal additive frontmatter.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** DEFER. Competitor-mimicry, not moat. Consumer is agents at recall time, not the founder;
the dead `promotion-log.md` scaffold proves the write-mostly risk is real here. Cheaper dominating
move: frontmatter hygiene + recall-quality measurement before paying to compress. Name the founder
outcome consolidation unblocks this quarter — currently unnamed.

### Engineering (CTO)

**Summary:** SCOPE DOWN. ~80% exists in `cron-compound-promote.ts`; this is an enhancement, not a new
feature. v1 should be a manual, single-subdir, zero-mutation dry-run report to prove the merge signal.
Inngest sibling cron if ever built (GHA would regress ADR-027). Whole-corpus LLM scan on a schedule is
the real recurring cost; needs cheap retrieval candidate-pairing before any LLM merge judgment.

### Legal (CLO)

**Summary:** Founder-grade (no specialist). Hard guardrails required whenever built: exempt
`compliance/`/`security-issues/`/incident records from merge+archive (Art. 5(2) evidence); source
immutability (additive distillation only); in-place discoverability for evidence (never `git mv` to
`archive/`); human-in-the-loop PR gate affirming no source was rewritten or lost.

## User-Brand Impact

- **Artifact:** the scheduled `compound --consolidate` consolidation pass (the agent that would
  merge/archive `knowledge-base/project/learnings/` entries and open a review PR).
- **Vector:** a background pass that auto-rewrites or archives founder-readable learnings could silently
  destroy or corrupt verbatim institutional knowledge the founder trusts as auditable — the exact moat
  property the feature claims to protect. The CLO additionally found a live GDPR Art. 5(2) accountability
  record in `compliance/` that lossy consolidation would damage.
- **Threshold:** single-user incident.

This brainstorm's chosen direction (measure-before-build, propose-only, exempt-class) is the mitigation:
nothing mutates the corpus until a metric proves it should, and even then only via founder-reviewed
propose-only PRs with the exempt-class allowlist enforced.
