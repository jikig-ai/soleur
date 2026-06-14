---
title: KB Recall-Quality Prereq (gate for the deferred consolidation pass)
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-14-kb-consolidation-recall-prereq-brainstorm.md
created: 2026-06-14
defers: "#5292"
---

## Problem Statement

Issue #5292 proposes a scheduled `compound --consolidate` pass that merges/archives the 1,554-file
`knowledge-base/project/learnings/` corpus and opens a review PR ("sleep-time compute" analog,
competitor-mimicry of cofounder.co). Cross-domain assessment (CPO + CLO + CTO, unanimous) rejected
building it now:

- The prior attempt is **dead**: `promotion-log.md` has 0 data rows; `scheduled-compound-promote.yml`
  was never wired live. Empirical proof of the write-mostly failure mode (#2723 lens).
- The KB consumer is **agents at recall time**, not the founder. The honest goal is recall quality, not
  human navigability. We cannot claim recall is degrading — recall measurement
  (`scripts/learning-retrieval-bench.sh`, #4043) ran twice (2026-05-19/20) then went quiet.
- Auto-consolidation is **lossy by construction**, threatening the verbatim/auditable moat.

We are building the **falsifiable prerequisite**, not the consolidation pass.

## Goals

1. Make corpus **staleness/redundancy observable** via a deterministic, pure-local, recurring-affordable
   metric (zero LLM noise), surfaced where an agent/founder can read it without SSH.
2. Define the **authoritative decision rule** with concrete, deterministic thresholds that justify (or
   kill) consolidation work.
3. Define a minimal **closure-lifecycle** signal (additive frontmatter) so any future review PR can
   actually "close" something — the missing prereq that killed the promote loop.
4. Encode the re-eval criteria **and a real dated checkpoint trigger+owner** so the gate cannot dangle
   (the failure mode of the `promotion-log.md` scaffold it replaces).

## Non-Goals

- Building the scheduled consolidation cron, the per-subdir batching, or the LLM merge engine (deferred → #5292).
- Any mutation (merge/archive/rewrite) of existing learning files in this work.
- Human-navigability UI for the corpus (no UI surface).
- Promoting learnings into constitution rules (already covered by `cron-compound-promote.ts`).

## Functional Requirements

> **[Revised 2026-06-14 after spec-flow-analyzer teardown.]** The original FRs pinned the gate to a
> recurring run of the **LLM recall bench**. spec-flow proved that gate cannot fire: the bench's two
> existing runs swung +56–104% in 24h (it measures the live LLM retriever, not the corpus), so a 10%
> degradation threshold is below the noise floor; and deferring the recurrence made the trend it needs
> uncollectable. The redesign pins the gate to the **deterministic pure-local redundancy metric**
> (zero LLM noise, free to recompute → recurrence is genuinely affordable) and demotes the recall bench
> to an **optional informational input**.

> **[Trimmed 2026-06-14 after 3-reviewer plan-review.]** Cut staleness/age + per-subdir reporting (gate
> reads only corpus-wide density); cut FR4's live demo + corpus touch (zero corpus mutation now); folded
> the checkpoint into the existing daily sweeper (no new workflow, dodges 60-day scheduled-disablement);
> corrected auth to `GITHUB_TOKEN` + scoped `permissions:` (matching the cited precedents, not App token).

- **FR1** — Build `scripts/kb-staleness-metric.sh`: a **deterministic, pure-local** (NO external API)
  scanner of `knowledge-base/project/learnings/` (excluding `**/archive/**`) emitting
  `kb-redundancy-metrics-<date>.json`. **One gated signal — corpus-wide redundancy density:** all-pairs
  near-duplicate density via `Jaccard(title-tokens ∪ tags) ≥ 0.6` (n≈1549 → ~seconds, **no blocking key**
  — it only introduced false negatives). **Title-less fallback** (~15% of corpus lacks `title:`): derive
  tokens from the date-stripped filename slug. CLO **exempt classes** (`compliance/`, `security-issues/`,
  incident/PIR, frontmatter `category: compliance|security-issues` / `regulation:`) are counted in the
  denominator but never listed in `top_pairs`. Self-tested (`cq-test-fixtures-synthesized-only`) with
  positive, **false-negative**, and **title-less** fixtures. **No `schema` versioning.** Run once →
  commit the **2026-06-14 baseline density**. Cost: $0, seconds. *(Staleness/per-subdir CUT: a
  stale-but-unique learning should not be consolidated, so staleness is not a gate signal.)*
- **FR2** — Surface without SSH (`hr-no-dashboard-eyeball-pull-data-yourself` /
  `hr-no-ssh-fallback-in-runbooks`): the date-stamped JSON is committed (readable via app.soleur.ai KB
  viewer + GitHub), and a stable `knowledge-base/project/kb-health.md` carries the latest human-readable
  snapshot (committed baseline density + top pairs) so it is discoverable without the date-stamped filename.
- **FR3** — Define the **authoritative decision rule** (single source of truth; see Re-Evaluation
  Criteria below). Hard clauses are deterministic (redundancy density + a recorded outcome field); the
  LLM recall bench (R@5/MRR) is **informational only**, never a hard clause.
- **FR4** — **(Trimmed to a one-line convention, reserved for #5292.)** Record the closure-lifecycle
  convention — additive `superseded_by: <path>` frontmatter, never edit/delete a body, never archive an
  exempt class (CLO G2/G3) — in #5292's body and the spec. **No live demo, no corpus file touched in this
  PR** (a single hand-made closure proves only writability — plan-review). The convention's first real use
  lands with the #5292 consolidation pass, its only consumer.
- **FR5** — Update #5292: revised criteria + a required dated `named_outcome:` field the checkpoint reads.
- **FR6** — **Fold a dated checkpoint step into the existing `scheduled-followthrough-sweeper.yml`** (runs
  daily, stays active → no 60-day-disablement dangle): on/after **2026-08-13**, if #5292 is open and not
  yet adjudicated, run `kb-staleness-metric.sh`, evaluate the decision rule, and comment the verdict on
  #5292 (build-recommended or close-recommended). **Pure bash + `gh`**, `GITHUB_TOKEN` + `permissions:
  { contents: read, issues: write }` (NOT App token, NOT PAT — matching the precedent), no agent, no
  Anthropic. Fallback if folding is unclean: a dated issue assigned to `engineering`.

## Technical Requirements

- **TR1** — Reuse `scripts/learning-retrieval-bench.sh` for any (optional, on-demand) recall measurement;
  do not rebuild it. **[Narrowed 2026-06-14]** The original "any cron must be Inngest, not GHA" applies
  to the deferred *consolidation runtime cron* (#5292, web-platform-adjacent) — NOT to a **repo-governance
  checkpoint** (FR6), which conventionally uses GHA (precedent: `scheduled-followthrough-sweeper.yml`,
  `rule-metrics-aggregate.yml`). ADR-027/033's "Inngest > GHA" governs app-runtime crons, not governance
  automations.
- **TR2** — Zero mutation of existing learning bodies in this work; frontmatter additions only, applied
  by an explicit/opt-in path, never a blanket sweep.
- **TR3** — FR6's checkpoint is a **GHA governance workflow**, not an Inngest `cron-*.ts`; the
  six-registry lockstep does NOT apply. (It applies only if/when the #5292 consolidation cron is built.)
- **TR4** — CI GitHub writes use `GITHUB_TOKEN` + scoped `permissions:` (matching
  `scheduled-followthrough-sweeper.yml` / `rule-metrics-aggregate.yml`), **never a PAT**
  (`hr-github-app-auth-not-pat` forbids PATs; the auto-scoped Actions `GITHUB_TOKEN` is not a PAT and is
  the convention for same-repo issue writes — a GitHub App token is unnecessary here). Silent fallbacks
  mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).

## CLO Guardrails (mandatory whenever #5292 is built)

- **G1** — Exempt-class allowlist: `compliance/`, `security-issues/`, incident/PIR records, and any
  frontmatter-flagged evidence are NON-mergeable and NON-archivable — hard skip, logged.
- **G2** — Source immutability: consolidation/distillation is additive-only (new files + non-destructive
  `superseded_by:` frontmatter); never edits or deletes existing learning bodies.
- **G3** — In-place discoverability: exempt evidence stays at its original path; never `git mv` to `archive/`.
- **G4** — History-preserving moves (`git mv`) for archivable ordinary learnings; never plain delete.
- **G5** — Human-in-the-loop PR gate affirming no source learning was rewritten or lost.

## Re-Evaluation Criteria for #5292 — AUTHORITATIVE DECISION RULE (single source of truth)

> This block is the **only** place the gate is defined (spec-flow flagged a 3-vs-4-clause spec/brainstorm
> contradiction). The brainstorm and plan reference this; they do not redefine it.

**Trigger & owner:** the FR6 step folded into the daily `scheduled-followthrough-sweeper.yml` fires
on/after **2026-08-13**, recomputes `kb-staleness-metric.sh` against the same authoritative corpus
snapshot (archive-excluded learnings), and comments a verdict on #5292 (assigned to `engineering`). The
checkpoint **always produces a verdict** (build-recommended or close-recommended) — there is no
"unmeasured/dangle" state, because the deterministic local metric is always computable, and the host
sweeper runs daily (no 60-day scheduled-workflow-disablement risk).

**Build #5292 only if BOTH hard clauses hold at the checkpoint:**

1. **Redundancy is material** — **primary (trustworthy) clause:** corpus-wide near-duplicate density grew
   ≥ **5 percentage points** vs the 2026-06-14 baseline; **secondary shortcut:** absolute density ≥
   **15%**. The delta clause is robust to the Jaccard threshold and the (now-removed) blocking key; the
   absolute floor is softer (density is a **lower bound** — Jaccard misses paraphrase-without-token-overlap).
   The **2026-06-14 baseline is computed and committed in this PR before the threshold is final** — if the
   baseline already ≥ 15%, the absolute shortcut is inert and only the +5pp delta arm governs (so the gate
   is never pre-decided). Measured by the deterministic `kb-staleness-metric.sh` (zero LLM noise; baseline
   and checkpoint use the byte-identical committed
   script, so the delta is meaningful). Corpus-wide (not per-subdir) to cover the ~69% loose top-level
   files; exempt classes counted in the denominator but never proposed as merge candidates.
2. **A named outcome exists** — #5292's `named_outcome:` field is non-empty and dated within the window:
   the concrete founder/agent outcome consolidation unblocks this quarter.

**Informational inputs** (recorded in the decision issue, NOT hard clauses): optional on-demand recall
bench R@5/MRR (noisy — if cited, run ≥3× and report the spread); closure-lifecycle adoption (organic
`superseded_by:` count over the window).

**Otherwise → close #5292 as wontfix** (the correct outcome — the corpus's problem was never bloat).
The checkpoint issue records which clause failed.

## Out of Scope (Future Work → #5292)

- Scheduled `cron-compound-consolidate.ts`, per-subdir batching, LLM merge/distill proposals,
  propose-only review PRs with the G1–G5 guardrails enforced.

## Success Criteria

- Recall metric is recurring + readable without SSH; a baseline + degradation threshold are documented.
- Closure-lifecycle frontmatter is defined with ≥1 demonstrated closure path.
- #5292 carries the ALL-must-hold re-eval criteria and is correctly framed as deferred-and-gated.
