# Tasks: fix memory-backstop re-entry SetUnitProperties OOMPolicy (#9246)

Plan: knowledge-base/project/plans/2026-09-30-fix-backstop-reentry-oompolicy-plan.md
Issue: #9246. Branch: feat-one-shot-9246-oompolicy-reentry.

## Phase 1: Failing tests first

- [x] 1.1 `.claude/hooks/memory-backstop.test.sh` fixture half (~T2 wiring block, :285): extract the `"$scope"`-targeted `SetUnitProperties` block; assert `true 4`, the four caps, no `OOMPolicy`, non-empty extraction (fail-closed); assert `grep -c '"OOMPolicy" "s" "continue"' "$HOOK"` == 3. RED on the pre-fix hook.
- [x] 1.2 `.claude/hooks/memory-backstop.test.sh` live arm: before the existing re-entry `run_real_hook` (~:1464), degrade the adopted scope's `TasksMax` to `37984` via runtime `SetUnitProperties`; after the run assert `TasksMax=4096` and the new ledger line `outcome:"applied"`; add `T21-reentry-converge` to `LIVE_LABELS` with mark/skip per #8008. RED on systemd ≥261 pre-fix.
- [x] 1.3 `.claude/hooks/memory-backstop-mutation-battery.sh`: add M11 row after M10 — empirical OOMPolicy-rejection probe (skip-note on pre-261), baseline reconvergence positive control, mutant re-adding `OOMPolicy` + arity `4`→`5` anchored on the `"$scope"`-targeted call → degraded cap stays → KILLED.

## Phase 2: Core Implementation

- [x] 2.1 `.claude/hooks/memory-backstop.sh` (~:855–863): drop `"OOMPolicy" "s" "continue"` and arity `5`→`4`; add the creation-only/systemd-261/all-or-nothing comment mirroring `repair_eval_scope` (:413–417); bump `BACKSTOP_REVISION` `2`→`3`. `bash -n` clean.
- [x] 2.2 Re-vendor: `cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/ && chmod 0755` (byte-identical pin, `backstop-parity.test.ts`).
- [x] 2.3 `.claude/hooks/README.md` (:946): update the stale #9246 parenthetical — the re-entry refresh now applies the same exclusion.

## Phase 3: Testing

- [x] 3.1 `bash .claude/hooks/memory-backstop.test.sh` standalone (not via lefthook) — fixture + live arms green on this systemd-261 host.
- [x] 3.2 `bash .claude/hooks/memory-backstop-mutation-battery.sh "$PWD"` — all rows incl. M11 green.
- [x] 3.3 `bun test plugins/soleur/test/backstop-parity.test.ts` and `bash plugins/soleur/test/fixture-relative-assert.test.sh` — green, no baseline drift.
- [x] 3.4 `bash scripts/check-backstop-revision.sh` (needs `origin/main` reachable) + `bash scripts/test-all.sh` (or the hook-suite shard) green.
