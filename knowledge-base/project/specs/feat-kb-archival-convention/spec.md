---
title: "Stop indexing per-feature working state (Tier 1)"
feature: feat-kb-archival-convention
issue: "#7399"
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-08-10
branch: feat-kb-archival-convention
pr: 7398
brainstorm: knowledge-base/project/brainstorms/2026-08-10-kb-archival-convention-brainstorm.md
plan: knowledge-base/project/plans/2026-08-10-fix-stop-indexing-per-feature-ephemeral-state-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-173-kb-index-exclusion-supersedes-per-feature-archival.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md
  - knowledge-base/project/learnings/2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md
---

# Stop indexing per-feature working state (Tier 1)

> **v2.** The original spec specified a denylist of three named file classes and a
> shared constant across two `find` invocations. Both were superseded during planning
> and implementation; the reasons are recorded in the plan's `## Research
> Reconciliation` and `## Plan Review Revisions`. This document has been amended so it
> stands alone rather than contradicting the plan that implements it.

## Problem Statement

`knowledge-base/INDEX.md` is the discovery surface agents grep for prior art —
`learnings-researcher.md:15` Step 0 greps it across all domains, and any agent may grep
it raw. (`kb-search` Tier 1 and `learning-retrieval-bench.sh` also read it but restrict
to `knowledge-base/project/learnings/`, so they never saw the rows at issue.)

A large majority of its `project/specs/**` rows are per-feature working state rather
than knowledge: `session-state.md` is session scratch, and roughly ninety other one-off
working filenames appear, about seventy-six of them exactly once.

The pre-existing mechanism for removing a row was per-feature archival
(`archive-kb.sh`), which has been decided against — see ADR-173. In short: it has no
recorded purpose, it is structurally unable to reach `fix-*` spec dirs or topic-named
plans (and reports success anyway), and its `git mv` collides with ADR-084 §5, which
requires a spec directory to stay readable until `ship` Phase 6.

## Goals

- **G1** — Remove per-feature working state from INDEX.md at generation time, using a
  single mechanical predicate with no per-file judgment.
- **G2** — Keep every feature discoverable: a spec directory must still contribute at
  least one row naming it.
- **G3** — Change nothing on disk. No `git mv`, no backlog migration, no file relocated.
- **G4** — Leave ADR-084 §5's `specs/<branch>/decision-challenges.md` read path
  untouched.

## Non-Goals

- **NG1** — Excluding merged features' `spec.md`, `tasks.md`, or plans. Deferred to
  #7400; it needs a reliable merged signal that does not exist yet.
- **NG2** — Modifying `archive-kb.sh`. Its retirement is #7400's exit criterion.
  `archive-kb/SKILL.md` gains a superseded-in-part pointer; the script is unchanged.
- **NG3** — Migrating the artifact backlog. Under index-exclusion there is nothing to
  migrate.
- **NG4** — Building any archival gate, reworked or otherwise.
- **NG5** — Changing brainstorm indexing.
- **NG6** — A CI freshness gate for INDEX.md. Tracked by #7401.
- **NG7** — Widening `lint-orphan-test-suites.sh`. Tracked by #7402.

## Functional Requirements

- **FR1** — Inside `knowledge-base/project/specs/<feature>/`, `generate-kb-index.sh`
  MUST index `spec.md` and `tasks.md` and MUST NOT index any other file.
  **An allowlist, not a denylist:** filename invention is the norm in these
  directories, so an enumerated deny set is stale the next time a new working filename
  is written.
- **FR2** — The rule MUST be independent of directory prefix. `feat-*`, `fix-*`, and
  bare-named spec dirs behave identically — the structural property `archive-kb.sh`
  lacks.
- **FR3** — Rows under `knowledge-base/project/plans/**` MUST be unchanged, including
  the nested `plans/<feature>/plan.md` shape.
- **FR4** — The rule MUST apply only to `project/specs/`. A `specs/` directory
  elsewhere in the knowledge base is unaffected.
- **FR5** — Pre-existing exclusions (`archive/`, `INDEX.md`, non-markdown) MUST be
  unchanged.
- **FR6** — `kb-tags.txt` and `kb-categories.txt` MUST stay consistent. The faceting
  walk is rooted at `project/learnings/` and cannot reach `project/specs/`, so it is out
  of scope — asserted, not assumed.
- **FR7** — No file is created, deleted, moved, or renamed on disk.

## Technical Requirements

- **TR1** — Implement in the existing `find` predicate that already carries
  `-not -path '*/archive/*'`, keeping one exclusion mechanism.
- **TR2** — Patterns MUST NOT interpolate `$KB_DIR`. Interpolation makes the predicate
  depend on the variable's textual form: a trailing slash produces a `//` no
  `find`-emitted path contains, so the exclusion evaluates true for everything and the
  feature silently no-ops with exit 0. `KB_DIR` MUST also be normalized once
  (`${KB_DIR%/}`), which additionally fixes the pre-existing `rel=` strip that emits
  absolute paths on the same input.
- **TR3** — Tests MUST assert on the INDEX.md **link target** (`](path)`), never a bare
  path: each fixture's title contains its own path, so a bare grep matches the title and
  passes vacuously. A non-vacuity guard MUST fail if the fixture corpus produces zero
  rows.
- **TR4** — Fixtures MUST be derived from the repository's real shapes, not from the
  implementation. At minimum: a `fix-*` spec dir, a bare-named spec dir, the nested
  `plans/<feature>/plan.md` shape, an archived spec, a non-markdown file, a
  self-referential `INDEX.md`, and a `specs/` directory outside `project/`.
- **TR5** — A mutation battery MUST cover every arm of the predicate and every
  pre-existing arm adjacent to the edit. Each mutation must turn the suite RED, run
  against a scratch copy via a `GEN_SCRIPT` override so the working tree is never
  mutated. Where a mutation aborts an earlier test before the new fixtures run, its
  fixtures MUST be verified separately rather than credited on the abort.
- **TR6** — Verification MUST use same-session differentials, never absolute corpus
  counts. Counts decay on every knowledge-base merge and on this feature's own
  artifacts.

## User-Brand Impact

- **Artifact:** `knowledge-base/INDEX.md` and the prior-art sweep path
  (`learnings-researcher` Step 0).
- **Vector:** A discovery surface dense with per-feature scratch degrades the sweeps
  that prevent an agent from re-deriving or contradicting a decision already made. The
  failure is silent — it surfaces as an agent acting confidently on a false greenfield
  premise in a customer's repository. The sharpest form is documentation that
  *overstates* what the index contains: an agent trusting "INDEX.md lists every
  non-archived file" reads an empty grep as proof of absence.
- **Threshold:** single-user incident.

## Acceptance Criteria

- [ ] FR1–FR7 and TR1–TR6 satisfied.
- [ ] Generating twice from one corpus copy: plan row count identical, and the set of
      surviving basenames under `project/specs/` is exactly `{spec.md, tasks.md}`.
- [ ] Every mutation in the battery turns the suite RED, with the actual failure
      recorded per mutation.
- [ ] `archive-kb.sh` byte-identical.
- [ ] No knowledge-base file added, deleted, or renamed beyond this feature's own
      artifacts.
- [ ] Every document asserting that INDEX.md lists *every* non-archived file is
      amended.
- [ ] `bash -n` clean; full test suite green with the suite appearing exactly once in
      the runner output.
