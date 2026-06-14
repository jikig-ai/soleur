---
title: KB Recall-Quality Prereq — deterministic gate for deferred consolidation (#5292)
status: draft
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: "#5298"
defers: "#5292"
brainstorm: knowledge-base/project/brainstorms/2026-06-14-kb-consolidation-recall-prereq-brainstorm.md
spec: knowledge-base/project/specs/feat-compound-consolidate/spec.md
created: 2026-06-14
---

# ✨ KB Recall-Quality Prereq — Deterministic Gate for Deferred Consolidation (#5292)

## Overview

Cross-domain brainstorm (CPO+CLO+CTO, unanimous) **deferred** the scheduled KB-consolidation pass
(#5292) and reframed immediate work to a falsifiable prereq: prove whether the 1,554-file learnings
corpus actually needs consolidation **before** building automation to consolidate it (#2723 write-mostly
lesson). This plan builds the **decision apparatus**, not the automation.

spec-flow-analyzer tore down the first design: a gate pinned to a recurring run of the **LLM recall
bench** cannot fire — the bench's two existing runs swung **+56–104% in 24h** (it measures the live LLM
retriever, not the corpus), so a 10% threshold is below the noise floor; and the gate had no owner/trigger
(reproducing the `promotion-log.md` dangle it diagnoses). **The redesign pins the gate to a deterministic
pure-local redundancy metric** (zero LLM noise → recurrence is free and meaningful) plus a **real dated
GHA checkpoint** with an owner. The ~$3 LLM recall bench is demoted to an optional informational input.

## Research Reconciliation — Spec vs. Codebase

| Claim (spec/brainstorm/my-own-prior) | Reality (verified this session) | Plan response |
|---|---|---|
| FR1: "re-establish a **recurring recall bench** run" | Bench is `--confirm`-gated, ~50min/~$3 Anthropic Haiku, **non-deterministic** (live paraphrase calls); two runs swung +56–104%/24h | Demote recall bench to informational; gate on the **deterministic pure-local** `kb-staleness-metric.sh` (FR1 rewritten in spec) |
| TR1: "**any cron** must be Inngest, not GHA (ADR-027/033)" | ADR-027/033 governs **app-runtime** crons; repo governance crons ARE GHA (`scheduled-followthrough-sweeper.yml`, `rule-metrics-aggregate.yml`) | Narrowed TR1: FR6 checkpoint is a **GHA governance workflow**; Inngest rule applies only to the deferred #5292 consolidation cron |
| Redundancy "per-subdir density" | **1062/1549 (69%)** of learnings are loose top-level files in NO subdir | Gate uses **corpus-wide** density + min-pair floor; per-subdir kept for color only |
| `cron-compound-promote` is a "dead/abandoned scaffold" | It is **registered** in `cron-manifest.ts:29` but `promotion-config.yml` is `enabled: false` (opt-in OFF) | Reframe: opt-in-OFF, not abandoned; do NOT touch it (the staleness emit is separate + pure-local) |
| FR5: "update #5292 with criteria" | Already done this session via the reopen comment | Extend: add a required dated `named_outcome:` field + the FR6 trigger; AC verifies |
| Gate population: recall 1163 vs redundancy 1549 | Bench excludes `archive/`; on-disk non-archive = 1549 | Authoritative snapshot = **archive-excluded learnings**, used by the deterministic metric (the hard gate); recall is informational |
| My own FR6: "new GHA workflow with App auth" | Both cited precedents (`scheduled-followthrough-sweeper.yml`, `rule-metrics-aggregate.yml`) use `GITHUB_TOKEN` + scoped `permissions:`, NOT App token; ~15% of learnings lack `title:`; a new no-op-until-Aug workflow risks 60-day scheduled-disablement | **Fold the checkpoint into the existing daily sweeper** (`GITHUB_TOKEN`, stays active); title-less slug fallback; corrected auth (Kieran/Simplicity/DHH plan-review) |
| My own FR1: staleness + per-subdir + blocking key + schema | Gate reads only corpus-wide density; blocking key only adds false-negatives at n=1549; schema versioning is YAGNI for a 2-run metric | **Cut** staleness/per-subdir/blocking-key/schema (DHH+Simplicity HIGH); all-pairs Jaccard |

## User-Brand Impact

**If this lands broken, the user experiences:** a wrong build/kill verdict on #5292 — either premature
consolidation automation (the moat-eroding risk) or indefinite dangle of a deferred tracker. The
checkpoint's verdict is advisory + founder-reviewed, so a wrong number cannot auto-mutate the corpus.

**If this leaks, the user's data is exposed via:** n/a — the metric is **pure-local** (reads frontmatter +
file paths; sends nothing to any external API). No new data-movement surface. After the plan-review cut of
FR4's live demo, this PR mutates **zero existing learning files** — it adds net-new files (script, JSON,
kb-health.md) + an existing-workflow edit + issue/brainstorm doc edits.

**Brand-survival threshold:** single-user incident *(carried from spec/brainstorm for consistency)*. In
truth THIS diff is read-only measurement + advisory verdict (founder-reviewed; cannot auto-mutate the
corpus) — its real blast radius is low. The heavy merge/archive risk that earned the single-user-incident
tag **inherits to #5292**, which carries the threshold + CLO G1–G5 guardrails. CPO sign-off carried from
brainstorm Phase 0.1. *(If preflight prefers a tighter classification for this read-only diff, downgrade
to `none` with reason "read-only measurement + advisory verdict; no corpus mutation, no external egress".)*

## Implementation Phases
*(Collapsed 4→2 phases after plan-review: FR4 live demo cut, checkpoint folded into the existing sweeper.)*

### Phase 1 — Deterministic redundancy metric + SSH-free surface (FR1, FR2)
- Create `scripts/kb-staleness-metric.sh` (pure-local, NO external API):
  - Corpus = `knowledge-base/project/learnings/**/*.md` **excluding** `**/archive/**`.
  - **One gated signal — corpus-wide redundancy density:** all-pairs near-duplicate density via
    `Jaccard(title-tokens ∪ tags) ≥ 0.6`. **No blocking key** (n≈1549 → ~seconds; the blocking key only
    produced false negatives). **Title-less fallback** (~15% of corpus lacks `title:`): tokens from the
    date-stripped filename slug. Emit `corpus_count`, `redundant_pairs`, `density`, `top_pairs[]`.
    **Exempt classes** (`compliance/`, `security-issues/`, incident/PIR, frontmatter
    `category: compliance|security-issues` / `regulation:`) counted in denominator, never in `top_pairs` (CLO G1).
  - Output `knowledge-base/project/kb-redundancy-metrics-<date>.json` (**no `schema` field**).
  - `--self-test` with **synthesized fixtures** (`cq-test-fixtures-synthesized-only`, env hooks
    `LEARNINGS_ROOT`/`OUTPUT_DIR` mirroring `learning-retrieval-bench.sh`): assert (a) a positive near-dup
    pair, (b) a **false-negative** pair whose titles diverge in the first tokens (proves no-blocking-key),
    (c) a **title-less** file uses the slug fallback, (d) an exempt-class file is excluded from `top_pairs`.
  - *(Staleness/age + per-subdir reporting CUT — gate reads only density; uses `git log -1 --format=%ct`
    ONLY if any age signal is kept, NOT filesystem mtime. Current scope keeps no age signal.)*
- Run once → commit the **2026-06-14 baseline** JSON.
- Create `knowledge-base/project/kb-health.md`: stable snapshot (corpus_count, **baseline density**,
  top-3 redundant pairs) + pointer to the date-stamped JSON + the FR4 closure-lifecycle one-liner.
  Committed → readable via app.soleur.ai KB viewer + GitHub (no SSH).

### Phase 2 — Dated checkpoint folded into the existing sweeper + #5292 wiring (FR5, FR6)
- Edit `.github/workflows/scheduled-followthrough-sweeper.yml` (runs daily; reuses its `GITHUB_TOKEN` +
  `permissions:` — **not App token, not PAT**): add a guarded step — on/after **2026-08-13**, if #5292 is
  open and not yet adjudicated (no prior `kb-checkpoint` marker comment), run `kb-staleness-metric.sh`,
  evaluate the spec's authoritative decision rule, and **comment the verdict on #5292** (build-recommended
  or close-recommended, with the density number + which clause passed/failed). Pure bash + `gh`, no agent,
  no Anthropic. CR/LF-strip any value echoed into `::notice::`. If the sweeper's scope makes folding
  unclean at /work time, fall back to a standalone date-guarded `scheduled-*.yml` (same auth shape).
- Update #5292 body: add a dated `named_outcome:` field (empty) the checkpoint reads + the FR4 convention
  one-liner. (Extends the reopen comment from this session — FR5.) Automatable via `gh issue edit`.
- Reconcile the brainstorm: annotate `2026-06-14-kb-consolidation-recall-prereq-brainstorm.md` line ~59
  (the stale 3-clause gate) as `[Superseded by spec §Re-Evaluation Criteria]` so no contradicting gate
  definition remains (plan-review P1).

## Files to Create
- `scripts/kb-staleness-metric.sh` — deterministic pure-local redundancy metric + `--self-test`.
- `knowledge-base/project/kb-redundancy-metrics-2026-06-14.json` — baseline output (generated, committed).
- `knowledge-base/project/kb-health.md` — SSH-free snapshot + closure-lifecycle one-liner.

## Files to Edit
- `knowledge-base/project/specs/feat-compound-consolidate/spec.md` — gate rewritten + trimmed this session.
- `.github/workflows/scheduled-followthrough-sweeper.yml` — add the dated checkpoint step.
- `knowledge-base/project/brainstorms/2026-06-14-kb-consolidation-recall-prereq-brainstorm.md` — annotate
  the stale 3-clause gate as superseded.
- (GitHub, not a file) issue **#5292** — add dated `named_outcome:` field + FR4 convention one-liner.

**No corpus mutation:** FR4's live demo was cut — this PR touches **zero existing learning files**.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `bash scripts/kb-staleness-metric.sh --self-test` exits 0; fixtures assert (a) positive near-dup,
      (b) false-negative pair (titles diverge in first tokens — proves no blocking key), (c) title-less
      slug fallback, (d) exempt-class file absent from `top_pairs`.
- [ ] `kb-redundancy-metrics-2026-06-14.json` exists, committed, **no `schema` field**, non-empty
      `corpus_count`, `density` present, `top_pairs` lists no exempt-class file.
- [ ] No external API call in the script: `! grep -qiE 'curl|anthropic|api\.anthropic|https?://' scripts/kb-staleness-metric.sh`.
- [ ] `kb-health.md` exists with current snapshot (baseline density + top pairs) + closure-lifecycle
      one-liner + JSON pointer.
- [ ] **Zero existing learning files mutated:** `git diff --name-only origin/main | grep -c '^knowledge-base/project/learnings/' = 0`.
- [ ] `scheduled-followthrough-sweeper.yml` checkpoint step: `actionlint` clean; embedded `run:` shell
      passes `bash -n`; contains the `2026-08-13` date guard + #5292 open-and-unadjudicated guard; no
      Anthropic/agent; uses `GITHUB_TOKEN` + scoped `permissions: { contents: read, issues: write }`
      (NOT a GitHub App token, NOT a PAT).
- [ ] spec.md §Re-Evaluation Criteria is the single authoritative gate; the brainstorm's stale 3-clause
      gate (line ~59) is annotated `[Superseded by spec §Re-Evaluation Criteria]` — no contradicting
      definition remains. (`grep -c 'ALL must hold' brainstorm` reflects only the annotated reference.)
- [ ] Baseline density is recorded in `kb-health.md`; if baseline ≥ 15%, spec gate clause 1's absolute
      shortcut is noted inert (only +5pp delta governs) so the gate is not pre-decided.
- [ ] PR body uses `Closes #5298` (the prereq) and `Ref #5292` (do NOT auto-close the deferred tracker).

### Post-merge (operator/automation)
- [ ] #5292 body carries a dated `named_outcome:` field (empty) + FR4 convention one-liner. *(Automatable:
      `gh issue edit` — bake into /work, not operator.)*
- [ ] The sweeper's checkpoint step is present on main; first daily run after merge no-ops (before 2026-08-13).

## Domain Review

**Domains relevant:** Product, Legal, Engineering *(carried forward from brainstorm `## Domain
Assessments` — no scope change warranting re-spawn; per plan Phase 2.5 carry-forward)*

### Product (CPO)
**Status:** reviewed (carry-forward). **Assessment:** Defer the pass; consumer is agents not founder;
gate on evidence. This plan implements exactly that. CPO sign-off carried (brainstorm Phase 0.1).

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** Founder-grade. Guardrails G1–G5 apply to #5292;
THIS PR honors them by being additive-only + exempt-class-aware in FR1/FR4. No specialist threshold.

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** ~80% of #5292 exists in `cron-compound-promote.ts`;
this is an enhancement, not a feature. v1 = decision apparatus, no scheduler for the pass. Honored.

### Product/UX Gate
**Tier:** none. No UI surface (Files-to-Create are a bash script, JSON, markdown, a workflow). Phase 3.55
visual-design legitimately skipped.

## Observability
```yaml
liveness_signal:    { what: "daily sweeper run (checkpoint step no-ops until 2026-08-13)", cadence: "daily", alert_target: "GitHub Actions run status + #5292 verdict comment", configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml" }
error_reporting:    { destination: "GitHub Actions run log + non-zero exit", fail_loud: true }
failure_modes:      [ { mode: "metric script errors", detection: "non-zero exit fails the sweeper step", alert_route: "Actions run failure (repo Actions tab)" }, { mode: "gh comment on #5292 fails", detection: "step exit code", alert_route: "Actions run failure" } ]
logs:               { where: "GitHub Actions run logs", retention: "GitHub default (90d)" }
discoverability_test: { command: "bash scripts/kb-staleness-metric.sh && cat knowledge-base/project/kb-redundancy-metrics-*.json | jq .density", expected_output: "numeric density; NO ssh" }
```

## GDPR / Compliance
CLO assessment carried from brainstorm (exempt-class allowlist, source immutability, Art. 5(2) evidence
preservation). This PR adds **no external data-movement** surface (metric is pure-local; no Anthropic
egress, unlike the deferred consolidation pass). `gdpr-gate` fold-in obligations attach to #5292 when the
LLM consolidation pass is built — not to this read-only/additive prereq.

## Open Code-Review Overlap
None. Checked all 4 created + 2 edited paths against 63 open `code-review` issues (2026-06-14) — zero
bodies reference any planned path. Net-new surfaces (script, JSON, kb-health.md, checkpoint workflow).

## Test Scenarios
1. Fixture corpus with 2 near-identical titles → `--self-test` reports a redundant pair + correct density.
2. Fixture with a `compliance/` file in a near-dup pair → file flagged `exempt`, excluded from `top_pairs`.
3. Fixture with files of varied git-commit ages → p50/p90/older-counts correct.
4. Checkpoint workflow dry-run before 2026-08-13 → no-ops (date guard), opens no issue.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this
  one is filled.
- **Worktree mtime trap:** filesystem mtime in a fresh worktree is checkout time; the metric MUST use
  `git log -1 --format=%ct`. (Encoded as an AC grep.)
- **Recall bench is non-deterministic** — never make its R@5 a hard gate clause; informational only,
  run ≥3× if cited. (spec-flow finding; encoded in spec.)
- Do not touch `cron-compound-promote.ts` / `promotion-config.yml` — opt-in-OFF, separate concern.

## Alternatives Considered
| Approach | Why not |
|---|---|
| Recurring LLM recall-bench cron as the hard gate | Below noise floor (+56–104%/24h); ~$3/run recurring; non-deterministic. **Demoted to informational.** |
| New Inngest cron for the checkpoint | Six-registry lockstep + IaC overhead for a p3 governance check; GHA is the conventional governance substrate. **Deferred-as-unnecessary.** |
| Build the consolidation pass now | Unanimous leader defer; dead `promotion-log.md` precedent. **→ #5292 (gated).** |
| Recurrence automation for the metric beyond the checkpoint | Premature until baseline shows signal. **The FR6 checkpoint IS the minimum recurrence; broader automation gated on the verdict.** |
