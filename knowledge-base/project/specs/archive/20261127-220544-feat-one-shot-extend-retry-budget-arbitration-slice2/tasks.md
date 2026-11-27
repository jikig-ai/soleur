# Tasks: Extend retry-budget arbitration (slice 2 of #12526)

- [x] Phase A: Wire `plugins/soleur/skills/test-fix-loop/SKILL.md` Phase 1 `fix_rounds` `STOP` to canonical `retry-budget-ruling.md` (`--phase test-fix-loop`)
- [x] Phase B: Wire `plugins/soleur/skills/review/SKILL.md` and `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` `seats` classified-stop to canonical `retry-budget-ruling.md` (`--phase review`)
- [x] Phase C: Wire `plugins/soleur/skills/qa/SKILL.md` capped-parent halt to canonical `retry-budget-ruling.md` (`--phase qa`) within the 37,000-byte lifecycle ceiling
- [x] Phase D: Update `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md` trigger header and verify `lint-skill-body-budget.py`, `components.test.ts`, and `retry-budget-ruling.test.sh`
