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

## User-Brand Impact

**If this lands broken, the user experiences:** a wrong build/kill verdict on #5292 — either premature
consolidation automation (the moat-eroding risk) or indefinite dangle of a deferred tracker. The
checkpoint's verdict is advisory + founder-reviewed, so a wrong number cannot auto-mutate the corpus.

**If this leaks, the user's data is exposed via:** n/a — the metric is **pure-local** (reads git
last-commit times + frontmatter; sends nothing to any external API). No new data-movement surface in this
PR. The one corpus touch is FR4's additive `superseded_by:` frontmatter on a **single non-exempt** learning.

**Brand-survival threshold:** single-user incident *(carried from brainstorm for consistency)*. The
load-bearing risk in THIS diff is narrow — FR4's frontmatter demo accidentally touching a CLO-exempt
class (`compliance/`, `security-issues/`, incident records), mitigated by FR4 hard-skipping the exempt
allowlist. The heavier merge/archive blast radius properly **inherits to #5292**, which carries the
single-user-incident threshold + CLO G1–G5 guardrails. CPO sign-off carried from brainstorm Phase 0.1.

## Implementation Phases

### Phase 1 — Deterministic staleness/redundancy metric (FR1)
- Create `scripts/kb-staleness-metric.sh` (pure-local, NO external API):
  - Corpus = `knowledge-base/project/learnings/**/*.md` **excluding** `**/archive/**`.
  - **Staleness** per-corpus + per-subdir: age via `git log -1 --format=%ct -- <file>` (NOT filesystem
    mtime — checkout time in a worktree is meaningless); emit p50/p90 age-days, count older-than-180d/365d.
  - **Redundancy** corpus-wide: near-duplicate pairs via Jaccard(title-tokens ∪ tags) ≥ 0.6; to bound
    the O(n²) pairing use a blocking key (first 3 normalized title tokens). Emit `redundant_pairs`,
    `density = redundant_pairs / corpus_count`, `top_pairs[]`. **Exempt classes** (`compliance/`,
    `security-issues/`, paths whose frontmatter has `category: compliance|security-issues` or
    `regulation:`/`articles:`) are counted in the denominator but flagged `exempt: true` and never listed
    as merge candidates (CLO G1).
  - Output `knowledge-base/project/kb-staleness-metrics-<date>.json` (schema 1).
  - Self-test (`--self-test`) with **synthesized fixtures** (`cq-test-fixtures-synthesized-only`): env
    hooks `LEARNINGS_ROOT`/`OUTPUT_DIR` mirroring `learning-retrieval-bench.sh`; assert staleness +
    redundancy math on a known fixture set; assert exempt-class exclusion.
- Run once → commit the **2026-06-14 baseline** JSON.

### Phase 2 — Surface without SSH (FR2)
- Append/update `knowledge-base/project/kb-health.md`: a stable file with the latest snapshot
  (corpus_count, redundancy density, p90 age, top-3 redundant pairs) + a pointer to the date-stamped
  JSON. Committed → readable via app.soleur.ai KB viewer + GitHub (no SSH, no dashboard-pull).

### Phase 3 — Closure-lifecycle frontmatter (FR4, enabling infra)
- Document the convention in `kb-health.md` (or a short section in the spec): additive
  `superseded_by: <path>` and optional `status: superseded`. **Additive only** — never edit/delete a
  learning body; never archive an exempt class (CLO G2/G3).
- Demonstrate once: pick a real ordinary (non-exempt) learning that a newer one supersedes, add
  `superseded_by:` to the older. One file, frontmatter-only, history-preserving.

### Phase 4 — Dated governance checkpoint (FR5 + FR6, the anti-dangle trigger)
- Add `.github/workflows/scheduled-kb-consolidation-checkpoint.yml` (precedent:
  `scheduled-followthrough-sweeper.yml`, `rule-metrics-aggregate.yml`):
  - `schedule:` weekly cron with a guard that no-ops before **2026-08-13**, then on/after that date runs
    `kb-staleness-metric.sh`, evaluates the authoritative decision rule (spec §Re-Evaluation Criteria),
    and opens/updates a decision issue (`gh issue create/edit`) assigned to engineering, referencing
    #5292, recording which clause passed/failed. **Pure bash + `gh`** — no agent, no Anthropic.
  - GitHub App auth via the repo's existing App pattern (`hr-github-app-auth-not-pat`), not PAT.
  - Pin all network/`gh` calls; CR/LF-strip any JSON-decoded value echoed into `::notice::`.
- Update #5292 body: add a required dated `named_outcome:` field (empty initially) the checkpoint reads;
  link the checkpoint workflow. (Extends the reopen comment already added this session — FR5.)

## Files to Create
- `scripts/kb-staleness-metric.sh` — deterministic pure-local metric + `--self-test`.
- `knowledge-base/project/kb-staleness-metrics-2026-06-14.json` — baseline output (generated, committed).
- `knowledge-base/project/kb-health.md` — SSH-free snapshot + closure-lifecycle convention.
- `.github/workflows/scheduled-kb-consolidation-checkpoint.yml` — dated governance checkpoint.

## Files to Edit
- `knowledge-base/project/specs/feat-compound-consolidate/spec.md` — gate already rewritten this session.
- One existing **non-exempt** learning under `knowledge-base/project/learnings/` — add `superseded_by:`
  frontmatter (Phase 3 demo; exact file chosen at /work time, never an exempt class).
- (GitHub, not a file) issue **#5292** — add dated `named_outcome:` field + checkpoint link.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `bash scripts/kb-staleness-metric.sh --self-test` exits 0; synthesized fixtures assert staleness +
      redundancy math + exempt-class exclusion.
- [ ] `kb-staleness-metrics-2026-06-14.json` exists, committed, `schema=1`, non-empty `corpus_count`,
      `redundancy.density` present, `top_pairs` lists no exempt-class file.
- [ ] Script reads age via `git log -1 --format=%ct` (grep the script) — NOT filesystem mtime.
- [ ] No external API call in the script: `! grep -qE 'curl|anthropic|api\.' scripts/kb-staleness-metric.sh`.
- [ ] `kb-health.md` exists with current snapshot + closure-lifecycle convention + JSON pointer.
- [ ] Exactly one non-exempt learning gained `superseded_by:` frontmatter; `git diff` shows
      **frontmatter-only** change (no body lines removed); the file is not under `compliance/`,
      `security-issues/`, or incident/PIR.
- [ ] `scheduled-kb-consolidation-checkpoint.yml`: `actionlint` clean; embedded `run:` shell passes
      `bash -n`; contains the `2026-08-13` date guard; no Anthropic/agent invocation; uses App auth not PAT.
- [ ] spec.md §Re-Evaluation Criteria is the single authoritative gate (2 deterministic hard clauses);
      no contradicting 3-vs-4-clause definition remains in brainstorm/plan.
- [ ] PR body uses `Closes #5298` (the prereq) and `Ref #5292` (do NOT auto-close the deferred tracker).

### Post-merge (operator/automation)
- [ ] #5292 body carries a dated `named_outcome:` field (empty) + checkpoint link. *(Automatable:
      `gh issue edit` — bake into /work, not operator.)*
- [ ] The checkpoint workflow appears in `gh workflow list` after merge to main.

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
liveness_signal:    { what: "weekly checkpoint workflow run", cadence: "weekly (no-op until 2026-08-13)", alert_target: "GitHub Actions run status + decision issue", configured_in: ".github/workflows/scheduled-kb-consolidation-checkpoint.yml" }
error_reporting:    { destination: "GitHub Actions run log + non-zero exit", fail_loud: true }
failure_modes:      [ { mode: "metric script errors", detection: "non-zero exit fails the workflow run", alert_route: "Actions run failure (visible in repo Actions tab)" }, { mode: "gh issue create fails", detection: "workflow step exit code", alert_route: "Actions run failure" } ]
logs:               { where: "GitHub Actions run logs", retention: "GitHub default (90d)" }
discoverability_test: { command: "bash scripts/kb-staleness-metric.sh && cat knowledge-base/project/kb-staleness-metrics-*.json | jq .redundancy", expected_output: "redundancy object with density field; NO ssh" }
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
