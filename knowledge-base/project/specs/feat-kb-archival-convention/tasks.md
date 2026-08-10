---
title: "Tasks — stop indexing per-feature ephemeral state (Tier 1)"
feature: feat-kb-archival-convention
issue: "#7399"
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-10-fix-stop-indexing-per-feature-ephemeral-state-plan.md
date: 2026-08-10
---

# Tasks — Tier 1

Derived from the plan. Every count below is re-derived in 1.1, not inherited.

## Phase 1 — Preconditions (no writes)

- [ ] 1.1 Baseline: `find knowledge-base -type f -not -type l -name '*.md' -not -path '*/archive/*' -not -name 'INDEX.md' | wc -l` → expect **7475**. If it differs, re-derive every count in the plan before continuing.
- [ ] 1.2 `grep -n 'find "\$LEARNINGS_DIR"' scripts/generate-kb-index.sh` returns exactly one line (confirms the faceting walk cannot see `project/specs/`, so only one `find` needs the change).
- [ ] 1.3 `grep -c 'generate-kb-index' scripts/test-all.sh` returns **0** (confirms the orphan suite).
- [ ] 1.4 Read `scripts/generate-kb-index.sh:30-45` before editing (`hr-always-read-a-file-before-editing-it`).

## Phase 2 — Register the orphan suite

- [ ] 2.1 Add `run_suite "plugins/generate-kb-index" bash plugins/soleur/test/generate-kb-index.test.sh` to `scripts/test-all.sh`, adjacent to the other `plugins/soleur/test` registrations.
- [ ] 2.2 `bash scripts/test-all.sh` — confirm the suite now appears in output and passes against current (unchanged) behaviour.
- [ ] 2.3 Commit this alone. It is an independent bug fix and it is what makes Phase 3's tests gate anything.

## Phase 3 — Failing tests first (RED)

Extend `plugins/soleur/test/generate-kb-index.test.sh`. Add a `setup_kb_specs` sibling to the existing `setup_kb` (which builds only `project/learnings/`). Reuse `run_generator` and the `KB_DIR` override.

- [ ] 3.1 F1 `specs/feat-x/spec.md` → indexed
- [ ] 3.2 F2 `specs/feat-x/tasks.md` + `session-state.md` → dropped
- [ ] 3.3 F3 `specs/feat-x/phase0-evidence.md` + `ac-walk.md` → dropped *(the case a denylist misses)*
- [ ] 3.4 F4 `specs/fix-y/spec.md` indexed + `specs/fix-y/tasks.md` dropped *(prefix-independence, FR2)*
- [ ] 3.5 F5 `specs/review-workflow-hardening/spec.md` → indexed *(bare-named dir, real shape on main)*
- [ ] 3.6 F6 `specs/feat-z/case-studies/01-a.md` → indexed *(depth ≥3)*
- [ ] 3.7 F7 `plans/feat-q/plan.md` → indexed *(the nested-plan shape that broke the reverted gate's `-maxdepth 1`)*
- [ ] 3.8 F8 `plans/2026-01-01-feat-r-plan.md` → indexed (FR3)
- [ ] 3.9 F9 `specs/archive/…/spec.md` → dropped *(pre-existing behaviour must not regress)*
- [ ] 3.10 F10 `specs/feat-x/decision-challenges.md` → dropped from index **AND** asserted still present on disk *(mechanical proof ADR-084 §5's read path is untouched)*
- [ ] 3.11 Confirm F1–F10 are RED against the unmodified script before writing Phase 4.

## Phase 4 — The predicate (GREEN)

- [ ] 4.1 Edit the `find` at `scripts/generate-kb-index.sh:36-41`, adding exactly one group:
      `\( -not -path "$KB_DIR/project/specs/*" -o -name 'spec.md' -o -path "$KB_DIR/project/specs/*/*/*" \)`
- [ ] 4.2 Do **not** write `specs/*/spec.md` — `find -path`'s `*` matches `/`, so it would match at any depth. Use `-name 'spec.md'`.
- [ ] 4.3 Do **not** simplify the third arm to `specs/*/*` — F2/F3 must catch it if attempted (see M5).
- [ ] 4.4 F1–F10 all GREEN.
- [ ] 4.5 `bash -n scripts/generate-kb-index.sh` clean.

## Phase 5 — Mutation battery

Each mutation applied to a scratch copy MUST turn the suite RED. Record the actual failure per row — a mutation list with no recorded RED is a hope, not a battery.

- [ ] 5.1 M1 delete the whole `\( … \)` group → RED via F2, F3
- [ ] 5.2 M2 delete `-o -name 'spec.md'` → RED via F1, F4, F5
- [ ] 5.3 M3 delete `-o -path ".../specs/*/*/*"` → RED via F6
- [ ] 5.4 M4 flip `-not -path ".../specs/*"` → `-path` → RED broadly
- [ ] 5.5 M5 widen third arm to `specs/*/*` → RED via F2, F3
- [ ] 5.6 M6 drop `-not -path '*/archive/*'` → RED via F9
- [ ] 5.7 M7 narrow first arm to `specs/feat-*` → RED via F4, F5 *(the `archive-kb.sh` defect, reintroduced — the important one)*

## Phase 6 — Real-corpus assertion

- [ ] 6.1 Run the **script** (not a re-typed predicate) against a `cp -r` copy under `mktemp -d`, so the committed `INDEX.md` is never written.
- [ ] 6.2 Spec-dir basenames in the produced INDEX.md = `spec.md` ×321 + exactly the 7 nested files, nothing else.
- [ ] 6.3 `grep -c 'project/plans'` unchanged vs baseline (FR3).
- [ ] 6.4 New-predicate file count = **4960** (delta −2515 from 1.1).
- [ ] 6.5 `rm -rf` the temp copy; `git status --short` shows no `INDEX.md`, `kb-tags.txt`, or `kb-categories.txt` (FR4, NG4).

## Phase 7 — ADR

- [ ] 7.1 Re-derive the next free ADR ordinal against freshly-fetched `origin/main`. ADR-171 was highest on 2026-08-10; **the number is provisional**.
- [ ] 7.2 Author `ADR-172-kb-index-exclusion-supersedes-per-feature-archival.md`, `status: adopting`.
- [ ] 7.3 Cite ADR-084 §5 and `ship/SKILL.md:2361` (the repo's own record that archival sanctionedly does not run).
- [ ] 7.4 `## Alternatives Considered` names all three losing options with the reason each lost: keep-archival-and-fix-its-holes; delete-the-convention-outright; denylist-by-basename.
- [ ] 7.5 If the ordinal moved, sweep the plan, this file, and AC12 in the **same** edit.

## Phase 8 — Exit gate

- [ ] 8.1 `git diff --stat plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` empty (NG2).
- [ ] 8.2 `git diff --name-status origin/main -- knowledge-base/project/specs knowledge-base/project/plans` shows only this feature's own new artifacts and zero `R`/`D` lines (NG3).
- [ ] 8.3 Full `bash scripts/test-all.sh` green.
- [ ] 8.4 All 13 plan ACs verified and recorded.

## Out of scope — do not do

- No archival gate, reworked or otherwise. Any gate on the `git mv` inherits the ADR-084 §5 collision.
- No change to `archive-kb.sh`. Its retirement is #7400's exit criterion.
- No migration of the 3,054-artifact backlog. Under index-exclusion there is nothing to migrate.
- No regeneration of the committed `INDEX.md` — that is #7401, a ~3,700-line diff that would swamp this ~10-line change.
- No exclusion of merged features' `spec.md` or plans — #7400, deferred pending a reliable merged signal.
- No change to brainstorm indexing or archival.
