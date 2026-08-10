---
title: "Stop indexing per-feature ephemeral state (Tier 1)"
feature: feat-kb-archival-convention
issue: "#7399"
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-08-10
branch: feat-kb-archival-convention
pr: 7398
brainstorm: knowledge-base/project/brainstorms/2026-08-10-kb-archival-convention-brainstorm.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md
  - knowledge-base/project/learnings/2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md
---

# Stop indexing per-feature ephemeral state (Tier 1)

## Problem Statement

`knowledge-base/INDEX.md` is the discovery surface `kb-search` (Tier 1),
`learnings-researcher` (Step 0), and `learning-retrieval-bench.sh` read to find prior
art. Regenerated, it is **7,507 rows, of which 4,372 (58%) are specs and plans**.

Of the 2,842 spec-dir rows, **2,408 (85%) are `tasks.md`, `session-state.md`, and
`decision-challenges.md`** — branch-lifetime working state, not knowledge.
`session-state.md` is session scratch. Only 320 rows are actual `spec.md`.

The existing remedy is per-feature archival (`archive-kb.sh` `git mv`s artifacts into
`archive/`, which `generate-kb-index.sh` excludes). That mechanism has been decided
against — see the brainstorm. In short: it cannot reach `fix-*` spec dirs
(`derive_slug()` strips `fix-`, then the probe is `specs/feat-${slug}`; 27 live, 0
archived), it misses topic-named plans and misreports the result as complete
(`2026-08-09-my-suites-were-hermetic…`), and moving a spec dir collides with ADR-084
§5, which requires `specs/<branch>/decision-challenges.md` to stay readable until
`ship` Phase 6 renders it. A gate on the move inherits that collision, which is why
the last one was reverted.

The benefit is attached to **INDEX.md membership**, not to the move. Take it directly.

## Goals

- **G1** — Remove per-feature ephemeral working state from INDEX.md at generation
  time, with no predicate and no judgment call.
- **G2** — Leave `spec.md` and plan rows fully intact so prior-art sweeps keep
  working.
- **G3** — Change nothing on disk. No `git mv`, no backlog migration, no artifact
  relocated.
- **G4** — Leave ADR-084's `specs/<branch>/decision-challenges.md` path untouched and
  readable by `ship` Phase 6.

## Non-Goals

- **NG1** — Excluding merged features' `spec.md` and plans (1,850 rows). Deferred to
  #7400; it needs a reliable merged signal that does not exist yet.
- **NG2** — Retiring or modifying `archive-kb.sh`. That is #7400's exit criterion. It
  stays as-is: neither enforced nor removed.
- **NG3** — Migrating the 3,054-artifact backlog. Under index-exclusion there is
  nothing to migrate — that is the point of the approach.
- **NG4** — Regenerating the committed INDEX.md to fix its 3,711-row staleness. That
  is #7401, and folding it in here would produce a ~3,700-line diff that swamps
  review of a ~10-line change.
- **NG5** — Building any archival gate, reworked or otherwise.
- **NG6** — Changing brainstorm indexing or archival. A brainstorm is knowledge and
  arguably belongs in INDEX.md permanently.

## Functional Requirements

- **FR1** — `scripts/generate-kb-index.sh` MUST omit files named `session-state.md`,
  `tasks.md`, and `decision-challenges.md` from INDEX.md, anywhere under
  `knowledge-base/`.
- **FR2** — The exclusion MUST be independent of directory prefix. A `fix-*`,
  `feat-*`, or bare-named spec dir is treated identically — this is the structural
  property `archive-kb.sh` lacks.
- **FR3** — `spec.md` rows (320) and `project/plans/**` rows (1,530) MUST be
  unchanged in count and content.
- **FR4** — The tag/category sidecars (`kb-tags.txt`, `kb-categories.txt`) MUST stay
  consistent with the new exclusion — the faceting pass walks
  `project/learnings/` only, so verify it is unaffected rather than assuming it.
- **FR5** — No file on disk is created, deleted, moved, or renamed.

## Technical Requirements

- **TR1** — Implement in the `find` predicate that already carries
  `-not -path '*/archive/*'` (`generate-kb-index.sh:36-41`), keeping one exclusion
  mechanism rather than adding a second downstream filter.
- **TR2** — The exclusion list MUST be a named, single-source constant, not repeated
  literals across the two `find` invocations (lines ~39 and ~136).
- **TR3** — Tests MUST assert against the **call form and extracted block**, not a
  comment naming the behaviour. Per
  `2026-08-09-my-suites-were-hermetic…`, the reverted gate's suite passed while an
  arm pointed at a different script because a comment named the audited one. A
  mutation that deletes an exclusion entry MUST fail the suite.
- **TR4** — Fixtures MUST be derived from the **repository's real shapes**, not from
  the implementation. The reverted gate's fixtures instantiated `specs/$BRANCH`
  because the code said so; its coverage holes then clustered exactly where the
  implementation was wrong. Cover at minimum: a `fix-*` spec dir, a nested plan
  (`plans/feat-*/plan.md` — live today), and a spec dir whose plan is topic-named.
- **TR5** — Run against the real corpus and assert the delta: total rows drop by
  ~2,408; `grep -c 'project/plans' ` is unchanged; `spec.md` row count is unchanged.
- **TR6** — `bash -n` clean; `scripts/test-all.sh` registration is explicit
  (`scripts/*.test.sh` is NOT auto-discovered — an unregistered suite never gates).

## User-Brand Impact

- **Artifact:** `knowledge-base/INDEX.md` and the KB discovery path (`kb-search`,
  `learnings-researcher`).
- **Vector:** A discovery surface that is 58% per-feature scratch degrades the
  prior-art sweeps that prevent agents from re-deriving or contradicting decisions
  already made. The failure is silent — it surfaces as an agent confidently acting on
  a false greenfield premise in a customer's repo.
- **Threshold:** single-user incident.

## Acceptance Criteria

- [ ] FR1–FR5 satisfied
- [ ] Regenerated INDEX.md drops ~2,408 rows; plan and `spec.md` rows unchanged
- [ ] A deleted exclusion entry fails the suite (TR3 mutation check)
- [ ] `archive-kb.sh` byte-identical
- [ ] `git status` shows no moved, added, or deleted knowledge-base artifacts
- [ ] `ship` Phase 6 can still read `specs/<branch>/decision-challenges.md`

## Note

This spec directory will itself emit `tasks.md` and `session-state.md`. Under FR1
neither is indexed — the change removes its own artifacts from the surface it fixes,
which is the correct behaviour and a live end-to-end check.
