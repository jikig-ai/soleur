---
feature: seo-refresh-queue producer/consumer contract + competitor-claim substantiation
issue: 6827
branch: feat-6827-seo-queue-consumer-tier3-positioning
pr: 6830
brainstorm: knowledge-base/project/brainstorms/2026-07-22-seo-queue-contract-and-tier3-positioning-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
date: 2026-07-22
---

# Spec — SEO Queue Contract + Competitor-Claim Substantiation

## Problem Statement

`knowledge-base/marketing/seo-refresh-queue.md` accumulates flagged-stale comparison-page rows
that are never drained. Issue #6827 attributes this to the queue having no consumer. It has two.

The real defect is a producer/consumer contract mismatch:

- **Bug A:** the producer (`cron-competitive-analysis.ts:166`) appends dated
  `## Stale Comparison Pages Flagged for Regeneration` blocks at `seo-refresh-queue.md:201,219`,
  below `## Refresh Schedule` (`:191`). The consumer (`cron-content-generator.ts:103`) reads only
  §1.x / §2.2 / §2.1. Flagged rows are structurally unreachable.
- **Bug B:** the consumer selects on *absence* of `generated_date`. §1.1–§1.7 (`:25`–`:90`) are
  prose subsections with no such field and are ordered first, so §1.1 Homepage is eligible on
  every fire, forever. The pipeline is mis-targeted, not stalled.
- **Bug C:** the producer is dark ~90d (tracked by open issue **#4375** — out of scope here). The
  consumer is live at 2x/week (#6818).

The same class of gap produced a second, undetected defect: the 2026-07-20 comparison-page
correction fixed `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` but not its social
twin `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`, which
still states "14.6k GitHub stars" in six places against a true 74,282 (~5x off) and carries
`status: published`.

## Goals

- G1 — Correct the paperclip distribution twin and eliminate figure drift between every
  `distribution-content/` file and its `docs/blog/` twin.
- G2 — Make flagged-stale rows reachable by the consumer (fix Bug A + Bug B).
- G3 — Make a silently non-draining queue self-report from the observability layer.
- G4 — Bind the existing competitor-claim substantiation rule to the diffs that bypass it.
- G5 — Separate verified from unsubstantiated Cofounder convergence claims in the source of
  truth, so no downstream rewrite inherits unverified premises.

## Non-Goals

- **NG1** — The `soleur-vs-cofounder` comparison page. Operator decision: do not publish.
  Positioning is captured internally instead. Blocked in any case on NG5.
- **NG2** — The Tier-3 positioning rewrite on published pages. Deferred to its own cycle;
  premises are only partly substantiated.
- **NG3** — Draining the 7 content rows (Notion, Cursor, NanoCorp, Codex, Tanka, CrewAI,
  Best-Plugins pillar). Deferred; the repaired pipeline is what should drain them.
- **NG4** — Dark-cron liveness remediation. Tracked by #4375; do not re-file or re-solve.
- **NG5** — The site-wide non-affiliation disclaimer. A real gap (CLO), but a prerequisite for
  the deferred competitor page, not for this cycle's work. File as follow-up.
- **NG6** — `product-roadmap validate` changes. Rejected as scope creep into an unrelated skill.
- **NG7** — "One GitHub issue per flagged page". Rejected; relocates a write-mostly backlog.

## Functional Requirements

- **FR1** — Correct all six stale star-count occurrences in
  `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md` (`:13`,
  `:25`, `:45`, `:76`, `:98`, `:136`) to agree with the blog twin's corrected figure, using the
  soft-floor form ("74,000+") the blog twin already uses rather than a precise count that drifts.
- **FR2** — Sweep every file under `knowledge-base/marketing/distribution-content/` for numeric
  competitor claims that disagree with its `plugins/soleur/docs/blog/` twin; correct all
  divergences found. Report the full sweep result in the PR body, including files checked with
  no divergence.
- **FR3** — Amend the producer prompt in `cron-competitive-analysis.ts` so flagged-stale rows are
  written into the canonical section the consumer reads (§2.1 comparison / §2.2 pillar tables),
  not into a new dated block below `## Refresh Schedule`.
- **FR4** — Amend the consumer predicate in `cron-content-generator.ts:103` from
  "highest-priority item without a `generated_date` annotation" to a **positive** predicate:
  Status contains `Stale` or `Create` **and** the row has no `generated_date`.
- **FR5** — Backfill the 7 undrained rows from the 2026-06-08 block (and any still-actionable
  2026-03-12 rows) into the canonical section, so the fix is not forward-only. Rows judged
  won't-do may be marked as such rather than migrated, with rationale in the queue file.
- **FR6** — Emit an artifact-delta observability signal keyed on the queue's `generated_date`
  count changing across a run — not on audit-issue existence. Must be reachable from the
  observability layer without SSH.
- **FR7** — Annotate `knowledge-base/product/competitive-intelligence.md` Tier-3 takeaway #7 to
  mark each Cofounder convergence claim as verified or unsubstantiated. Verified against
  cofounder.co on 2026-07-22: human-in-the-loop approval gates ("nothing ships without your
  approval") and multi-department breadth (11 domains listed). Not stated on the vendor site:
  pricing, revenue-share terms, memory/knowledge-base architecture, data ownership.
- **FR8** — Extend the review gate so any diff touching `plugins/soleur/docs/blog/*vs-*` or
  `knowledge-base/marketing/distribution-content/*vs-*` requires the existing acceptance
  criterion that every third-party claim traces to a named line in a cited source of truth,
  with a retrieval date.

## Technical Requirements

- **TR1** — FR3 and FR4 must be applied in lockstep with their verbatim mirrors in
  `.github/workflows/*.yml`. Both prompts are anchor-tested
  (`cron-content-generator.test.ts:79`, `cron-competitive-analysis.test.ts:148`); editing one
  side alone breaks the parity test.
- **TR2** — Preserve the anchor strings the parity tests assert on, or update the tests in the
  same commit. Do not silently weaken an anchor.
- **TR3** — FR6 must not reuse the existing issue-gated heartbeat at
  `cron-content-generator.ts:200,232,277`, which returns GREEN at zero rows drained. Cite the
  observability layer explicitly per `hr-observability-layer-citation`.
- **TR4** — No competitor financial or scale figure may be written into JSON-LD unless its hedge
  or attribution travels inside the same string (CLO, EU 2006/114/EC Art. 4(c)).
- **TR5** — Changes to `seo-refresh-queue.md` must keep the file parseable by both consumers;
  `cron-growth-execution.ts:126` reads a third predicate ("Priority 1 stale pages") and must not
  regress even though it is currently dark.
- **TR6** — Per `hr-write-boundary-sentinel-sweep-all-write-sites`, FR2's sweep is a required
  gate, not a spot check: enumerate every write-site for a corrected claim before closing.

## Acceptance Criteria

- AC1 — `grep -rn "14\.6k" knowledge-base/marketing/` returns zero hits.
- AC2 — No numeric competitor claim disagrees between any `distribution-content/` file and its
  `docs/blog/` twin; the sweep is documented in the PR body.
- AC3 — A test asserts the consumer predicate does not select a §1.x prose subsection.
- AC4 — A test asserts producer output lands in a section the consumer's predicate reaches.
- AC5 — The parity tests pass with both prompt sides edited.
- AC6 — The artifact-delta signal is demonstrated (name the marker and the layer it surfaces in).
- AC7 — Takeaway #7 distinguishes verified from unsubstantiated claims with a retrieval date.
- AC8 — Issue #6827's checklist is updated to reflect what shipped and what was deferred, with
  the deferred items' own issues linked.

## Follow-Up Issues

- Site-wide non-affiliation disclaimer on comparison pages and shared layouts (NG5, CLO).
- Tier-3 positioning rewrite, gated on FR7's substantiation pass (NG2).
- `soleur-vs-cofounder` page decision — records the CPO/CMO split for re-decision (NG1).
- Content drain of the remaining queue rows once the pipeline is repaired (NG3).
- Productize candidate: `distribution-twin-drift` check as a reusable gate.
