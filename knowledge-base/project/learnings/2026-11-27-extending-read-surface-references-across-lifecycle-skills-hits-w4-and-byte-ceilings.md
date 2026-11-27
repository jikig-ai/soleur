---
title: Extending a Read-surface reference across lifecycle skills trips W4a/W4b and lifecycle byte ceilings
date: 2026-11-27
category: workflow-patterns
module: plugins/soleur/skills
tags: [retry-budget-ruling, lifecycle-byte-budget, plugin-root-anchoring, read-surface, goto-ordering]
issue: 12526
pr: 13092
---

# Learning: Extending a Read-surface reference across lifecycle skills trips W4a/W4b and lifecycle byte ceilings

## Problem

When extending slice-1 retry-budget arbitration (`plugins/soleur/skills/one-shot/references/retry-budget-ruling.md`, shipped in PR #12815) into `soleur:test-fix-loop`, `soleur:review` (including `references/risk-tier-and-fix-rounds.md`), and `soleur:qa` for slice 2 of #12526, three coupled failure modes surfaced:

1. **Lifecycle `SKILL.md` byte ceilings (`scripts/lint-skill-body-budget.py`):** `one-shot/SKILL.md` sat at 51,999 / 52,000 bytes (1 byte of headroom), `qa/SKILL.md` sat at 36,989 / 37,000 bytes (11 bytes of headroom), and `review/SKILL.md` sat at 475,033 / 475,921 bytes (888 bytes of headroom). Adding full paragraphs directly to those three `SKILL.md` files failed `guards-ruleset` (`Lifecycle SKILL.md byte ratchet`).
2. **Unintended Read-surface promotion (`apps/web-platform/test/plugin-root-anchoring.test.ts` W4a/W4b):** Linking `[retry-budget-ruling.md](${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/retry-budget-ruling.md)` inside `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` introduced `${CLAUDE_PLUGIN_ROOT}/` into a non-`SKILL.md` file under `skills/`. `isReadSurfaceDoc()` classifies any non-`SKILL.md` file under `plugins/soleur/skills/` containing `${CLAUDE_PLUGIN_ROOT}/` as a Read-surface doc, requiring `risk-tier-and-fix-rounds.md` itself to carry the W4a root-delivery notice and forcing every existing relative link to `risk-tier-and-fix-rounds.md` in `review/SKILL.md` to fail W4b.
3. **Self-phase `goto` and child-vs-parent `ruling_spawn: used` ownership:** The initial wiring allowed `goto test-fix-loop` at `--phase test-fix-loop` and `goto review` at `--phase review`, and told the child skill to invoke `retry-budget-ruling.sh` even when running under `soleur:one-shot`. Because `capped=` stays set (CTO Ruling T1/R1-r), re-entering the capped phase immediately hits `pipeline-tally.sh gate` → `STOP` with `ruling_spawn: used` already spent; and if a child under `one-shot` invokes `retry-budget-ruling.sh` itself, it pre-spends `ruling_spawn: used` before `one-shot`'s own boundary check can execute an earlier-phase `goto`.

## Solution

1. **Measure `lint-skill-body-budget.py --base origin/main` before committing any edit to a lifecycle `SKILL.md`:** Left `one-shot/SKILL.md` untouched at 51,999 / 52,000 bytes (updating `one-shot/references/retry-budget-ruling.md` instead), kept `review/SKILL.md`'s pointer within its 888-byte headroom, and tightened two verbose notes in `qa/SKILL.md` so the file stayed at 36,634 / 37,000 bytes.
2. **Keep `${CLAUDE_PLUGIN_ROOT}/` links to Read-surface references in `SKILL.md` files, not in non-Read-surface `references/*.md` files:** `test-fix-loop/SKILL.md`, `review/SKILL.md`, and `qa/SKILL.md` carry `[retry-budget-ruling.md](${CLAUDE_PLUGIN_ROOT}/skills/one-shot/references/retry-budget-ruling.md)` (loader-delivered `SKILL.md` files are exempt from `isReadSurfaceDoc()`), while `review/references/risk-tier-and-fix-rounds.md` delegates the link to `review/SKILL.md` (`**Seat tally**`) and names the hyphenated `retry-budget-ruling` procedure without `${CLAUDE_PLUGIN_ROOT}/` or `/retry-budget-ruling.md`.
3. **Enforce strictly-earlier `goto` ordering and parent-vs-standalone arbitration ownership:** At any `--phase <p>` halt boundary under canonical ordering (`plan` < `work` < `review` < `qa` < `test-fix-loop`), only phases strictly earlier than `<p>` are valid `goto` targets (under parent `one-shot`; standalone runs halt on any `goto`), and under `one-shot` the child returns after writing `budget-capped` so the parent runs `retry-budget-ruling.sh` once.

## Key Insight

A `skills/*/references/*.md` file becomes a W4a/W4b Read-surface doc the moment any line in it contains `${CLAUDE_PLUGIN_ROOT}/`, and a child skill sharing a branch `session-state.md` ledger with `one-shot` must never pre-spend a single-use parent arbitration bit (`ruling_spawn: used`) or allow self-phase `goto` against an unlifted `capped=` latch.

## Session Errors

1. **Stopped after loading pipeline skills instead of completing `review` → `qa` → `compound` → `ship` to `MERGED`** — Recovery: converted PR #13092 back to draft and executed `work` completion floor, 5-seat `review` panel + fix round, `qa`, `compound`, and `ship`. — **Prevention:** In `one-shot`, loading a child skill via the `skill` tool is the start of that phase, never completion; always follow the child skill's steps through `emit-review-trailer.sh`, `compound`, and `ship` Phase 7 merge + postmerge before ending the turn.
2. **Lifecycle `SKILL.md` byte-ceiling overrun (`lint-skill-body-budget.py`) on `one-shot`, `qa`, and `review`** — Recovery: ran `python3 scripts/lint-skill-body-budget.py --base origin/main`, moved the cross-reference to `one-shot/references/retry-budget-ruling.md`, shortened the `review/SKILL.md` pointer, and tightened two notes in `qa/SKILL.md`. — **Prevention:** Run `python3 scripts/lint-skill-body-budget.py --base origin/main` before committing any edit to a lifecycle `SKILL.md` (`brainstorm`, `plan`, `deepen-plan`, `work`, `review`, `qa`, `compound`, `ship`, `postmerge`, `one-shot`).
3. **Unintended Read-surface promotion (`W4a`/`W4b` in `plugin-root-anchoring.test.ts`) in `review/references/risk-tier-and-fix-rounds.md`** — Recovery: delegated the `${CLAUDE_PLUGIN_ROOT}` link to `review/SKILL.md` (`**Seat tally**`) and verified with `vitest run test/plugin-root-anchoring.test.ts`. — **Prevention:** Before adding `${CLAUDE_PLUGIN_ROOT}/` or a link to a Read-surface doc inside `plugins/soleur/skills/*/references/*.md`, run `apps/web-platform/test/plugin-root-anchoring.test.ts` or delegate the `${CLAUDE_PLUGIN_ROOT}/` link from the parent `SKILL.md`.
4. **Self-phase `goto` and child-side `ruling_spawn: used` consumption in slice-2 wiring prose** — Recovery: fixed inline in commit `38e9c4b9c7` after 4/5 review seats flagged the T1/R1-r/T2 contradiction. — **Prevention:** When wiring a parent-owned state-machine transition (`goto <phase>`) into child skills, verify each allowed transition against active latches (`capped=` stays set) and single-use ledger bits (`ruling_spawn: used`).

## Tags
category: workflow-patterns
module: plugins/soleur/skills
