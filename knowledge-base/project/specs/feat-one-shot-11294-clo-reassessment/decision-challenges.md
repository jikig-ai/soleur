---
title: Decision challenges for feat-one-shot-11294-clo-reassessment
branch: feat-one-shot-11294-clo-reassessment
created: 2026-11-08
---

# Decision Challenges

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| The CLO-prescribed canonical-source cell append creates the register's first multi-source canonical cell, which `lint-legal-registers.sh`'s single-path `trim($(NF-1))` extraction cannot parse — assertion (b) fails on the composite string and (c) then sees neither cited file as indexed. Resolve the conflict between the prescribed cell text and the blocking lint. | technical | pending - assumed: extend the cited-paths awk producer to emit one line per backtick-enclosed span in `$(NF-1)` (every candidate runs the existing resolve/tracked/contained gauntlet; a row emitting zero candidates fails; row-count reconciliation moves from `resolved+broken == row_count` to `rows_emitting == row_count`), proven GREEN on the unmodified register before the composite cell lands. `NOT_TRANSCRIBED` waiver rejected — citing the record as canonical while waiving it is the indexed/waived contradiction assertion (c) exists to forbid. New index row rejected — a "determination STANDS" re-assessment is not a new determination; the in-cell corrections convention is the designed vehicle - `scripts/lint-legal-registers.sh:263-303,386-443`, `breach-register.md:143`, §Corrections — 2026-09-14 precedent |
| `related:` frontmatter append for the new record (not in the CLO's four prescribed edits) | taste | Planner decision, 2026-11-08: append `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` — convention measured at commit 45df1eef3f (the 2026-10-29 determination landing added its record to `related:`); omitting it leaves the frontmatter list stale relative to the index row it indexes - `breach-register.md:8-24` |
| Brand-survival threshold for this landing | taste | Planner decision, 2026-11-08: `none` — Tier-1 internal record landing (docs + a lint parser fix); no user-facing artifact, no personal-data processing introduced, no sensitive-path regex hit (`knowledge-base/legal/**`, `scripts/` not in `SENSITIVE_PATH_RE`) - preflight Check 6.1 regex, record's own `tier_classification: Tier 1` |
| Where the post-merge #11294 comment lives (runbook file vs PR-body checklist vs tasks.md) | taste | Planner decision, 2026-11-08: tasks.md §5 (verbatim) + plan Phase 4, executed via `gh issue comment 11294` after merge — a committed runbook file would add a fourth artifact for a single verbatim step, and tasks.md is where the sibling #11294 pipeline recorded its comment steps (archive 20261104-211526 tasks §3) |
