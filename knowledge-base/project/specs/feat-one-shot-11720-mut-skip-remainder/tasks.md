# Tasks — feat-one-shot-11720-mut-skip-remainder (#11720 batch-2)

Plan: knowledge-base/project/plans/2026-11-02-chore-mut-skip-guard-remainder-plan.md (authoritative — incl. "Port Contract — per-file obligations" addendum).

## Phase 1 — registry-store-not-luks + registry-zot-credential-shape
- [ ] 1.1 Port registry-store-not-luks: canon compare, res_block/param, constructible floor (PRESENCE_ROWS/MUT_ROWS replacing _floor=35/24), _red_verdict/mutate_green/mutate_floor_red, decoy rows, pristine control, want=wrong, IV axis + seam check (REGSTORE_* literals + MUT_SKIP), CI axis (cloud-init-registry.yml emitters), floor trips exit 1 / instruments exit 2
- [ ] 1.2 Same port for registry-zot-credential-shape (_floor=27/20; REGCREDSHAPE_*)
- [ ] 1.3 Run both suites green; MUT_SKIP=1 inner runs green; mutate_floor_red grades RED

## Phase 2 — workspaces-luks-deadman-fired
- [ ] 2.1 Replace first-hit grep -oE window extraction (:178-179) with exact param() pins (QP/CK exact values + uniqueness)
- [ ] 2.2 Conjunct-set canon (order-insensitive reorder stays mutate PASS); named constants adjacent to floor; floor trip exit 2→1; FIRE_LINE uncommented-early-copy row; DEADMAN_GUARD_* + IV seam check
- [ ] 2.3 Run green + mutation rows verified RED

## Phase 3 — egress-gw + meta-guard promotion
- [ ] 3.1 Full port; remove pass -lt 30 floor → derived _floor; IV) arms in both mutate case tables; DENY_SQL/SILENT_SQL/FAIL_SQL region anchors
- [ ] 3.2 scripts/guard-vacuity-floor.test.sh: PROMOTED_FILES entry at :1089 site (escaped dots) + grounds comment + MIN_FIRING_SUITES 61→62
- [ ] 3.3 Run meta-guard: exit 0; counters diff n_deferred 47→46, n_fires +1, n_def_construct −3, n_def_fires +3, n_covered +1

## Phase 4 — rebaseline + measure
- [ ] 4.1 All four suites + MUT_SKIP inner runs green; registry-clientip byte-identical (AC5)
- [ ] 4.2 Measure deploy-script-tests-fixed leg on-branch; conditional timeout-minutes bump at infra-validation.yml:851 only if near ceiling
- [ ] 4.3 affected-suites + guard-vacuity-floor green; lint-shell-capture-exit baseline check
