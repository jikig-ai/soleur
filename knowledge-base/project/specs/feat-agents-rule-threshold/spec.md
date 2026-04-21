---
title: Raise AGENTS.md rule threshold + activate prune pipeline
issue: 2686
branch: feat-agents-rule-threshold
status: draft
created: 2026-04-21
---

# Spec: AGENTS.md rule threshold (#2686)

## Problem Statement

`AGENTS.md` is at 106 rules — 6 over the 100-rule warn threshold in `cq-agents-md-why-single-line` (compound step 8). The warn fires every compound run. The threshold pre-dated the empirical growth curve; the rule count has climbed monotonically because each rule cites a real incident (PR # or learning file). Blanket pruning without runtime evidence risks re-creating rules the next time the incident recurs. The existing rule-metrics aggregator (PR #2213) + prune surface (`scripts/rule-prune.sh`) already exist but have not visibly driven the count down.

## Goals

1. Stop compound step 8 from firing the rule-count warn on main.
2. Keep the threshold load-bearing (not a blank check) by raising it modestly to 115 rather than 120.
3. Migrate 3–5 already-skill-enforced `cq` rules to their owning skill/hook, proving the migration pattern.
4. Verify the weekly rule-metrics aggregator workflow has actually fired against main and commits `rule-metrics.json`; file a follow-up if not.
5. Preserve `cq-rule-ids-are-immutable` — migrated rule IDs remain traceable via deprecation pointers.

## Non-Goals

- Migrating `knowledge-base/project/constitution.md` rules or adjusting its 300-rule threshold.
- Running a full audit of all 43 `cq` rules for migrateability.
- Auto-pruning rules without human review. The prune pipeline files issues; humans decide.
- Changing the 40,000-byte file cap or 600-byte per-rule cap.
- Re-compressing existing `**Why:**` annotations (PR #2544 already did this pass).

## Functional Requirements

- **FR1:** `cq-agents-md-why-single-line` threshold text updated from "rule count (A/100)" to "rule count (A/115)" in both AGENTS.md rule prose AND compound step 8 `SKILL.md`. Both must be in sync — they encode the same contract.
- **FR2:** Rule's `**Why:**` annotation cites #2683 + #2686 and references the empirical rule-count trajectory (one sentence, per `cq-agents-md-why-single-line` itself).
- **FR3:** 3–5 `cq` rules tagged `[skill-enforced: ...]` or `[hook-enforced: ...]` are migrated. For each migrated rule: (a) the full rule body moves to the owning skill's SKILL.md or the hook's script comment, (b) AGENTS.md retains a one-line pointer with the original ID preserved (per `cq-rule-ids-are-immutable`), or the rule is fully removed with a deprecation entry appended to a learning file listing the retired IDs.
- **FR4 (original, ~~strikethrough~~):** ~~Post-migration, `grep -c '^- ' AGENTS.md` returns ≤ 103 (down from 106) AND ≤ 115 (under the new threshold).~~
- **FR4 (replacement, 2026-04-21):** Post-migration, `grep -c '^- ' AGENTS.md` is **flat** (pointer-preservation is required by `lint-rule-ids.py` — no ID may be silently removed). File bytes are **neutral-to-slightly-higher** vs baseline (the longest original rule among the 3 migration candidates was only 141 bytes; pointer text referencing a destination path unavoidably exceeds that). The real win is architectural: rule bodies live with the hook/skill that enforces them, plus the threshold warn is silenced (106 ≤ 115). Full-body removal is blocked until `lint-rule-ids.py` gains a retired-ids allowlist (filed as Issue A, see plan §4.6).
- **FR5 (satisfied by research):** `gh run list --workflow rule-metrics-aggregate.yml --limit 5 --branch main` confirmed the aggregator is firing (last scheduled run 2026-04-19 01:16 UTC succeeded; run 24617976419). No follow-up issue filed.

## Technical Requirements

- **TR1:** AGENTS.md byte size stays under 40,000 (currently 36,566 — migration reduces it).
- **TR2:** Longest single rule stays under 600 bytes (currently 582).
- **TR3:** Every migrated rule's new home includes the original `[id: ...]` tag text in a grep-stable way so references to the rule ID in existing docs/code do not break.
- **TR4:** `lefthook` pre-commit hook `lint-rule-ids.py` passes — immutable rule IDs are not silently removed or renumbered.
- **TR5:** Markdown lint passes on AGENTS.md and every touched skill SKILL.md (`npx markdownlint-cli2 --fix` on the specific changed files, per `cq-markdownlint-fix-target-specific-paths`).
- **TR6:** No change to the runtime behavior of any migrated rule — the hook or skill enforcement that was load-bearing before must still fire the same way after migration.

## Acceptance Criteria

- [ ] `grep -c '^- ' AGENTS.md` is flat vs baseline (pointer-preservation per updated FR4) and < 115
- [ ] `wc -c < AGENTS.md` < 40,000
- [ ] `grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1` < 600
- [ ] `cq-agents-md-why-single-line` rule text mentions 115 (not 100)
- [ ] `plugins/soleur/skills/compound/SKILL.md` step 8 mentions 115 (not 100)
- [ ] For each migrated rule: original ID is grep-able in repo (either as AGENTS.md pointer or in deprecation breadcrumb)
- [ ] `lefthook run pre-commit` passes on the changed files
- [ ] `gh run list --workflow rule-metrics-aggregate.yml` inspected; follow-up issue filed if aggregator is not firing
- [ ] PR body includes a table of migrated rule IDs and their new locations

## Out-of-Scope Follow-ups (track only if discovered)

- Full audit of remaining `cq` rules for migrateability (filed as a separate issue if volume warrants).
- Aggregator workflow broken (filed per FR5).

## References

- Issue: #2686
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-21-agents-md-rule-threshold-brainstorm.md`
- AGENTS.md rules: `cq-agents-md-why-single-line`, `cq-rule-ids-are-immutable`
- Compound skill: `plugins/soleur/skills/compound/SKILL.md` step 8
- Aggregator: `scripts/rule-metrics-aggregate.sh` (PR #2213, #2573)
- Prune surface: `scripts/rule-prune.sh`
