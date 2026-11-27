---
lane: single-domain
brand_survival_threshold: none
---

# Feature: Extend retry-budget arbitration (slice 2 of #12526)

## Problem Statement

Slice 1 (PR #12815) shipped `plugins/soleur/scripts/retry-budget-ruling.sh`, `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md`, and the `one-shot/SKILL.md` parent-halt wiring. Issue #12526 remained open for slice 2: extending the retry-budget ruling wiring into `soleur:test-fix-loop`, `soleur:review` (classified-stop / fix-rounds), and `soleur:qa`.

## Goals

- Wire `plugins/soleur/skills/test-fix-loop/SKILL.md` Phase 1 `fix_rounds` `STOP` to `retry-budget-ruling.md` with `--phase test-fix-loop`.
- Wire `plugins/soleur/skills/review/SKILL.md` and `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` `seats` `STOP` to `retry-budget-ruling.md` with `--phase review`.
- Wire `plugins/soleur/skills/qa/SKILL.md` parent-capped halt at the qa step to `retry-budget-ruling.md` with `--phase qa`.
- Keep all lifecycle `SKILL.md` files within their `skill-body-budget.json` byte ceilings (`scripts/lint-skill-body-budget.py --base origin/main`).
- Preserve each skill's existing termination and reset rules when the ruling resolves to `fail` or `continue`.
