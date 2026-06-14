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

1. Make learnings-corpus recall quality **observable and recurring** (re-establish a cadence for the
   existing bench, surface its output where an agent/founder can read it without SSH).
2. Define a **staleness/redundancy metric** and a **degradation threshold** that would justify
   consolidation work.
3. Define a minimal **closure-lifecycle** signal (additive frontmatter) so any future review PR can
   actually "close" something — the missing prereq that killed the promote loop.
4. Encode the **re-evaluation criteria** that gate the deferred consolidation pass (#5292).

## Non-Goals

- Building the scheduled consolidation cron, the per-subdir batching, or the LLM merge engine (deferred → #5292).
- Any mutation (merge/archive/rewrite) of existing learning files in this work.
- Human-navigability UI for the corpus (no UI surface).
- Promoting learnings into constitution rules (already covered by `cron-compound-promote.ts`).

## Functional Requirements

- **FR1** — Re-establish a recurring recall benchmark run from `scripts/learning-retrieval-bench.sh`,
  emitting `learning-retrieval-metrics-<date>.json`, on a cadence (cron or documented manual trigger),
  with cost disclosed per `hr-autonomous-loop-skill-api-budget-disclosure`.
- **FR2** — Surface the latest recall metric where it is readable without SSH (per
  `hr-no-dashboard-eyeball-pull-data-yourself` / `hr-no-ssh-fallback-in-runbooks`): a committed summary
  file and/or Better Stack/Sentry signal.
- **FR3** — Define a composite **staleness/redundancy metric** (recall-miss rate from the bench +
  cheap near-duplicate density) and a **degradation threshold** value, documented in the spec/plan.
- **FR4** — Define the minimal **closure-lifecycle** frontmatter (e.g. `superseded_by:` / `status:`),
  additive-only, with a documented way to set it. No bulk rewrite of existing files.
- **FR5** — Update #5292 to a deferred tracker carrying the ALL-must-hold re-evaluation criteria.

## Technical Requirements

- **TR1** — Reuse `scripts/learning-retrieval-bench.sh` (do not rebuild recall measurement). If a cron is
  added, it MUST be an Inngest sibling of `cron-compound-promote.ts`, not a new GHA workflow (ADR-027/033
  regression).
- **TR2** — Zero mutation of existing learning bodies in this work; frontmatter additions only, applied
  by an explicit/opt-in path, never a blanket sweep.
- **TR3** — Any new `cron-*.ts` honors the six-registry lockstep (route.ts, cron-manifest.ts,
  function-registry-count.test.ts, cron-monitors.tf, apply-sentry-infra.yml, cron-containment-classify.test.ts).
- **TR4** — GitHub App auth, not PAT (`hr-github-app-auth-not-pat`); silent fallbacks mirror to Sentry
  (`cq-silent-fallback-must-mirror-to-sentry`).

## CLO Guardrails (mandatory whenever #5292 is built)

- **G1** — Exempt-class allowlist: `compliance/`, `security-issues/`, incident/PIR records, and any
  frontmatter-flagged evidence are NON-mergeable and NON-archivable — hard skip, logged.
- **G2** — Source immutability: consolidation/distillation is additive-only (new files + non-destructive
  `superseded_by:` frontmatter); never edits or deletes existing learning bodies.
- **G3** — In-place discoverability: exempt evidence stays at its original path; never `git mv` to `archive/`.
- **G4** — History-preserving moves (`git mv`) for archivable ordinary learnings; never plain delete.
- **G5** — Human-in-the-loop PR gate affirming no source learning was rewritten or lost.

## Re-Evaluation Criteria for #5292 (ALL must hold to unblock the build)

1. The recall metric (FR1–FR3) shows **measured degradation** past the defined threshold over the window.
2. A **named founder/agent outcome** the consolidation unblocks this quarter is articulated.
3. A **closure-lifecycle** (FR4) exists and has demonstrated ≥1 real closure, so review PRs can land
   rather than accrete (the #2723 condition the dead promote loop failed).

If, after a 60-day window, recall is not degrading and no outcome is named → **kill #5292** (correct outcome).

## Out of Scope (Future Work → #5292)

- Scheduled `cron-compound-consolidate.ts`, per-subdir batching, LLM merge/distill proposals,
  propose-only review PRs with the G1–G5 guardrails enforced.

## Success Criteria

- Recall metric is recurring + readable without SSH; a baseline + degradation threshold are documented.
- Closure-lifecycle frontmatter is defined with ≥1 demonstrated closure path.
- #5292 carries the ALL-must-hold re-eval criteria and is correctly framed as deferred-and-gated.
