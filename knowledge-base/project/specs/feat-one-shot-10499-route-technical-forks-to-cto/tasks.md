# Tasks - Route technical forks in review/work final reports and seat dissents to the CTO (#10499)

Plan: knowledge-base/project/plans/2026-10-18-feat-route-technical-forks-in-review-work-final-reports-plan.md

## Phase 1: Failing test first

- 1.1 Add the "Technical-ruling final-report wiring (#10499)" describe block to plugins/soleur/test/components.test.ts (five or more file/anchor pairs; strips fences and HTML comments; whitespace-normalised; floor assertion on the pair count).
- 1.2 Run it and confirm RED on every anchor.

## Phase 2: Reference

- 2.1 Append section 8 (8.1 final-report check, 8.2 seat dissent from a ruling, Why) to plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md, prose only, after the section 7 block.

## Phase 3: review/SKILL.md (net <= 0 bytes)

- 3.1 Rewrite disposition item 4 as a gate before Step 3.
- 3.2 Insert the "Seat dissent from a ruling" paragraph and the one-clause seat-brief instruction.
- 3.3 Insert the "Final-report decision check" paragraph at the top of Step 3.
- 3.4 Compress restating text (session-model Why paragraph, Self-audit, 100/4 Why) until `wc -c` <= 475913; fall back to moving one defect-class bullet to references/ only if needed.

## Phase 4: work/SKILL.md (net <= 0 bytes)

- 4.1 Compress the "Technical rulings route to the CTO agent" hard gate, keeping its pinned anchors and link.
- 4.2 Insert the "Final-report decision check" paragraph at the top of Phase 4: Handoff; `wc -c` <= 359179.

## Phase 5: Verify

- 5.1 Phase 1 test GREEN; run components.test.ts, cto-interface-selector.test.sh, technical-ruling-gate.test.sh.
- 5.2 python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"; no description: line changed; eval-gate --check gated:false for both skills.
- 5.3 Run Guard 1 mutation rows 1-6 and the reflow must-PASS row on a scratch copy; record results.
- 5.4 technical-ruling-gate.sh --branch exits 0.
