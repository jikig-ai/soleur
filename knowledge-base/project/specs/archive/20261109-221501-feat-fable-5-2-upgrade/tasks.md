# Tasks: Fable 5.2 model launch

Plan: knowledge-base/project/plans/2026-11-09-chore-fable-5-2-model-launch-plan.md

## 1. Tests first
- 1.1 Read the pair-count floor line in plugins/soleur/test/model-launch-review.test.ts; raise it 10 -> 11; fix the false "not itself a source id" comment
- 1.2 CURRENT_IDS and its comment -> claude-fable-5-2
- 1.3 SUPERSEDED map: claude-fable-5 and claude-fable-5-1 -> claude-fable-5-2
- 1.4 Synthetic-prefix test: .replace() source string and replacement -> claude-fable-5-2; fix the floor-failure message
- 1.5 Sed-anchor fixture: CURRENT -> claude-fable-5-2; add STALE_FABLE claude-fable-5-1 -> exactly claude-fable-5-2
- 1.6 New test: fable 5 / 5.1 / 5.2 converge in one --fix run; dated claude-fable-5-1-20261101 untouched
- 1.7 Run the file; confirm RED on the SUPERSEDED pair test, the synthetic-prefix test and the convergence test

## 2. Retarget the pair table
- 2.1 audit-models.sh AUTOFIX_PAIRS: claude-fable-5=claude-fable-5-2, add claude-fable-5-1=claude-fable-5-2
- 2.2 Fix comments naming claude-fable-5-1 as current or as "not a source id" (no closing paren inside the array comments)
- 2.3 Run the test file (GREEN), audit-models.sh and --detect (exit 0)

## 3. Skill doc
- 3.1 SKILL.md line 17: add Fable 5.2 to the release list
- 3.2 SKILL.md step 2: one sentence naming the test surfaces a new pair must touch
- 3.3 SKILL.md line 190: append the 5.2 retarget clause

## 4. ADR-053 addendum
- 4.1 Add "Addendum - 2026-11-09 (Fable 5.2 launch)": price rows, multiples, cache-read delta, list-price and alias-unverified wording, MODEL_PRICING reason, vendor-claim label, cross-link

## 5. ADR-083 addendum
- 5.1 Add "Addendum - 2026-11-09 (Fable 5.2)": six rejections/non-changes, Ruled by CTO agent
- 5.2 Add Superseded pointer next to the Context line quoting Fable 5 at $10/$50; cross-link ADR-053

## 6. Policy basis
- 6.1 plugins/soleur/AGENTS.md pricing basis: 5.2 multiples, point to ADR-053, replace the cold-spawn "~0 cache reads" sentence with ADR-053's measured statement, list-price and alias-unverified wording

## 7. Verify
- 7.1 model-launch-review, harness-model-map, fable-consult-gates tests pass
- 7.2 audit-models.sh all items; git grep dispositions for claude-fable-5-1 and "Fable 5.1"
- 7.3 git grep -inwE 'fable|claude-fable[-0-9a-z]*' -- 'apps/web-platform/server/**/*.ts' returns nothing
