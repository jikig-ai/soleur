---
title: Reopen 2026-04-07 KB retrieval decision — fix kb-search structural displacement
status: draft
owner: engineering
issue: 4119
blocks: 4042
supersedes_decision_in: 2026-04-07-kb-retrieval-improvement-brainstorm.md
brainstorm: knowledge-base/project/brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md
created: 2026-05-20
lane: single-domain
brand_survival_threshold: none
---

# Spec: Reopen 2026-04-07 KB Retrieval Decision

**Issue:** #4119
**Branch:** feat-kb-retrieval-reopen-4119
**Brainstorm:** [2026-05-20-kb-retrieval-reopen-brainstorm.md](../../brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md)
**Blocks:** #4042 (learnings archive — premised on a working retriever)

## Problem Statement

The 2026-04-07 brainstorm chose file-based retrieval (manifest + `kb-search` + standardized frontmatter) over RAG/embeddings, and named the reopen trigger as *"evidence that agents consistently fail to find relevant content despite manifest and standardized frontmatter."* The 2026-05-19 retrieval bench (PR #4045) provided that evidence:

- R@5(heavy, kb-search) = **0.1331** (threshold for `reopen-rag` bucket was <0.4).
- `gap_skill_roi = −0.173` — kb-search performs **worse** than bare grep across every paraphrase level.
- R@5(identity, kb-search) = **0.497** vs grep = **0.952** — kb-search loses to grep *before paraphrase enters the picture*.

Repo research locates the structural cause: `knowledge-base/INDEX.md` has 3461 entries (entire KB), but the bench evaluates against 1127 learnings. Tier-1 grep on INDEX.md floods the cap-20 with non-learning titles before tier-2 corpus content matches are considered. Dominant prefix-noise: `session state` ×497, `digest` ×65, `tasks: fix` ×110. ~63% of learnings (533/841) have no frontmatter — invisible to `--tag`/`--category` facets. `kb-search` is a Markdown prompt strategy with zero programmatic consumers; schema changes are zero-churn.

This evidence does **not** point at a fundamental semantic-search deficit. It points at a structural bug in the current implementation. The reopen is not "abandon file-based retrieval"; it is "fix the bug before reaching for new infra." Staged, bench-gated escalation is the YAGNI path.

## Goals

- **G1.** Recover R@5(heavy, kb-search) to ≥ 0.4 using the cheapest mechanism that the bench evidence supports.
- **G2.** Keep the bench as the sole acceptance signal — no "feels better" claims accepted.
- **G3.** Co-evolve `kb-search/SKILL.md` and `learning-retrieval-bench.sh` `kbsearch_rank` in lockstep so the bench measures the strategy as written.
- **G4.** Pre-commit the escalation ladder (Stage 1 → 1.5 → 2 → 3) before running Stage 1, so the operator does not negotiate ad-hoc when results arrive.
- **G5.** Unblock #4042 if Stage 1 passes the gate; document the cascade if not.

## Non-Goals

- Embeddings/RAG infrastructure in this PR (Stage 3, gated by Stages 1+1.5+2 failure; ADR-trigger).
- LLM paraphrase pre-pass in this PR (Stage 2, gated by Stages 1+1.5 failure).
- IDF/stopword scoring tuning in this PR (Stage 1.5, gated by Stage 1 failure).
- Adding programmatic consumers of `kb-search` (it stays prompt-only).
- Changes to `kb-tags.txt` / `kb-categories.txt` semantics beyond what the frontmatter backfill produces.
- Replacing or rewriting `learning-retrieval-bench.sh`'s paraphrase pipeline.

## Functional Requirements

### FR1: Split cap-20 into 8 tier-1 + 12 tier-2

`kb-search` SKILL.md Phase 3 currently caps total at 20 with tier-1 (INDEX.md title matches) listed first, then tier-2 (corpus content matches). Change to: cap tier-1 at 8, cap tier-2 at 12. Tier-2 gets a guaranteed floor so noise-prefix tier-1 hits cannot starve it. Order in output remains tier-1 then tier-2.

### FR2: Scope tier-1 to a learnings sub-index

Generate a learnings-scoped sub-index (a new section anchor inside `INDEX.md`, or a separate `INDEX-learnings.md` — plan decides). `kb-search` Phase 3 tier-1 greps the learnings sub-index only, not the full INDEX.md. The other 2300+ titles remain reachable via tier-2 corpus grep but no longer compete for tier-1 cap slots.

### FR3: Backfill frontmatter for missing-frontmatter learnings

Run a one-shot backfill over `knowledge-base/project/learnings/**/*.md` to add YAML frontmatter where absent. Reuse the pattern from `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` (idempotent, PyYAML, category inference from slug). Target: 0 missing-frontmatter learnings after the run. Commit as a separate commit so the bench can isolate its contribution.

### FR4: Lockstep bench update

`scripts/learning-retrieval-bench.sh` `kbsearch_rank` (currently lines 413-507) must update in the same PR as the SKILL.md change to emulate the new strategy (cap 8+12, learnings-scoped tier-1). Bench output JSON gains a per-tier rank breakdown so future regressions distinguish "tier-1 flooded" from "tier-2 missed".

### FR5: Synthesized flooding-pathology fixture

Add a synthesized fixture to `learning-retrieval-bench.sh --self-test`: ≥30 noise-titled INDEX entries (e.g., `session state X`, `digest Y`) + 3 target learnings whose correct retrieval requires tier-2 cap reservation. Per `cq-test-fixtures-synthesized-only`, no real-learning copies. The fixture must currently FAIL on the pre-fix `kbsearch_rank` and PASS on the post-fix version.

### FR6: Bench rerun + result commit

Operator runs `bash scripts/learning-retrieval-bench.sh --confirm` once Stage 1 changes are in place. Results commit to `knowledge-base/project/learning-retrieval-metrics-<date>.json` and a new diagnostic-findings learning under `knowledge-base/project/learnings/`. Uses `--cache-paraphrases` to avoid re-spending the ~$3 / 70min on Haiku reruns.

### FR7: Pre-committed escalation ladder

The PR's spec (this file) pre-commits the decision tree:

- **R@5(heavy, kb-search) ≥ 0.4** → close #4119, comment on #4042 to unblock.
- **0.3 ≤ R@5(heavy, kb-search) < 0.4** → keep #4119 open; file Stage 1.5 deferred issue (IDF/stopword scoring tuning) with bench-rerun gate.
- **R@5(heavy, kb-search) < 0.3** → keep #4119 open; file Stage 2 deferred issue (LLM paraphrase pre-pass) with budget disclosure (`hr-autonomous-loop-skill-api-budget-disclosure`) and bench-rerun gate.
- **No improvement vs. 0.1331 baseline (within ±0.02)** → keep #4119 open; file Stage 3 deferred issue (embeddings/RAG, ADR-trigger).

### FR8: Deferred-tracking issues for unship Stages

Per `wg-when-deferring-a-capability-create-a`, file GitHub issues for Stages 1.5, 2, 3 with their pre-committed trigger conditions and milestone "Post-MVP / Later." Do not create them speculatively if Stage 1 passes the gate.

## Technical Requirements

### TR1: Zero programmatic consumers — schema changes are SKILL.md edits

`kb-search` has no agents, hooks, or scripts that invoke it programmatically (verified via repo-wide search). All consumers are prompt-level (agents read SKILL.md and emulate). FR1/FR2 are documentation edits in `plugins/soleur/skills/kb-search/SKILL.md` Phase 3, with `scripts/generate-kb-index.sh` updated to emit the new sub-index anchor or file.

### TR2: Lockstep PR boundary (SKILL.md + bench in same commit)

The single most likely silent regression is: SKILL.md updated but `learning-retrieval-bench.sh` `kbsearch_rank` left on the old strategy. The bench then measures the wrong thing. Both files must change in the same commit; CI does not enforce this — review must.

### TR3: Bench self-test gates merge

PR cannot merge unless `bash scripts/learning-retrieval-bench.sh --self-test` passes with the new flooding-pathology fixture exercising the cap-split logic. The expensive `--confirm` rerun is operator-gated (post-merge or pre-merge by operator choice), but `--self-test` is CI-gated.

### TR4: Frontmatter backfill is idempotent + reversible

The backfill script must be re-runnable without producing duplicate frontmatter blocks (idempotency). Each backfilled file commits independently or in a single commit clearly labelled "frontmatter-only" so git revert is clean if the inferred categories are wrong.

### TR5: Observability is the bench (no new dashboards)

Per `hr-observability-as-plan-quality-gate`, Stage 1 does not introduce dashboards, log sinks, or telemetry. The bench rerun on demand IS the observability surface. Stage 2 or 3, if reached, will introduce their own observability (query logging, recall sentinel) per `hr-no-dashboard-eyeball-pull-data-yourself`.

### TR6: ADR-trigger for Stage 3

If escalation reaches Stage 3 (embeddings), the deferred-tracking issue must require `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` before implementation. Greenfield infra + irreversible operator coupling cross the architectural threshold.

## Acceptance Criteria

- **AC1.** `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 reflects cap-split (8 tier-1 + 12 tier-2) and learnings-scoped tier-1.
- **AC2.** `scripts/learning-retrieval-bench.sh` `kbsearch_rank` updated to emulate the new strategy; bench JSON output gains per-tier rank breakdown.
- **AC3.** `scripts/generate-kb-index.sh` emits the learnings sub-index (anchor or separate file).
- **AC4.** Frontmatter backfill applied; `grep -L '^---' knowledge-base/project/learnings/*.md` returns 0 files (modulo intentional exclusions documented inline).
- **AC5.** `bash scripts/learning-retrieval-bench.sh --self-test` passes with the new synthesized flooding-pathology fixture (FR5).
- **AC6.** Operator-run `bash scripts/learning-retrieval-bench.sh --confirm` results committed to `knowledge-base/project/learning-retrieval-metrics-<date>.json` and a new diagnostic-findings learning.
- **AC7.** Escalation outcome documented per FR7 ladder. Close #4119 + comment #4042 if gate passes; file deferred issue(s) if not.
- **AC8.** PR `## Changelog` section + `semver:patch` label (docs-only + script change, no runtime code surface). Branch synced from main on merge.

## Dependencies

- `scripts/learning-retrieval-bench.sh` (PR #4045, merged)
- `scripts/generate-kb-index.sh` (existing)
- `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` (frontmatter backfill precedent)
- `knowledge-base/project/learnings/2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` (--cache-paraphrases pattern)

## Out-of-Scope (Explicit Stage 2/3 Deferral Conditions)

- **Stage 1.5 (IDF/stopword scoring):** Only if Stage 1 lands at 0.3 ≤ R@5(heavy) < 0.4. Deferred-tracking issue at FR7/FR8.
- **Stage 2 (LLM paraphrase pre-pass):** Only if Stage 1+1.5 land R@5(heavy) < 0.3. Deferred-tracking issue with budget disclosure.
- **Stage 3 (embeddings/RAG):** Only if Stages 1+1.5+2 land no improvement vs baseline. Deferred-tracking issue with ADR-trigger.
