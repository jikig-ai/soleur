# Tasks - Route technical forks in review/work final reports and seat dissents to the CTO (#10499)

Plan: knowledge-base/project/plans/2026-10-18-feat-route-technical-forks-in-review-work-final-reports-plan.md

## Phase 1: Failing test first

- 1.1 Add the "Technical-ruling final-report wiring (#10499)" describe block to plugins/soleur/test/components.test.ts: five or more file/anchor pairs through one hasAnchor() helper, whitespace-collapsed matching, a floor assertion on the pair count, a must-FAIL fixture and a reflow must-PASS fixture.
- 1.2 Run it and confirm RED on every anchor.

## Phase 2: Reference

- 2.1 Append section 8 (8.1 final-report check, 8.2 seat dissent from a ruling with its six numbered steps, Why) to plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md. Prose only: no Item/Class/Ruling table header, no "Authorized by delegation" text, no pipe inside an example ruling.

## Phase 3: review/SKILL.md (net <= 0 bytes; record ceiling minus wc -c)

- 3.1 Rewrite disposition item 4 as a gate before Step 3; keep "implement exactly what it returns" and the #7347 pointer; add the no-Agent-tool pending clause.
- 3.2 Insert the "Seat dissent from a ruling" paragraph just before the "Parallel Agents to review the PR" heading (the spawn site).
- 3.3 Insert the one-sentence "Final-report decision check" at the top of Step 3, after the pipeline-detection paragraph.
- 3.4 Compress (session-model Why paragraph, Self-audit merge, 100/4 Why pointer) honouring the preserve-list in the plan; measure after each edit; stop at net <= 0.

## Phase 4: work/SKILL.md (net <= 0 bytes)

- 4.1 Compress the "Technical rulings route to the CTO agent" hard gate, keeping its verbatim anchors including the quoted "do NOT use AskUserQuestion".
- 4.2 Insert the one-sentence "Final-report decision check" at the top of Phase 4: Handoff (do not repeat the hard-gate lead phrase).
- 4.3 Replace the step 3.5 closing-message sentence with a pointer to the new check.

## Phase 5: Verify

- 5.1 Phase 1 test GREEN; run components.test.ts, cto-interface-selector.test.sh, technical-ruling-gate.test.sh, workflow-fidelity.test.ts.
- 5.2 python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"; no description: line changed; eval-gate --check gated:false for both skills.
- 5.3 Run Guard 1 mutation rows 1-3 and the reflow must-PASS row on a scratch copy; record results.
- 5.4 technical-ruling-gate.sh --branch exits 0; markdownlint-cli2 clean on plan, tasks and the reference.
- 5.5 After the last rebase onto origin/main, re-run the budget lint, cto-interface-selector.test.sh and the markdown lint.
