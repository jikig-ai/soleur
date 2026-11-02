# Tasks — feat-one-shot-11848-ratchet-accept-row

Plan: `knowledge-base/project/plans/2026-11-02-fix-affected-index-ratchet-new-pair-plan.md`

## Phase 1 — Edge declaration (Fix-Size: XS)

- [x] 1.1 In `scripts/lib/test-affected-paths.sh`, inside `AFFECTED_PLUGINS_SOLEUR_PATHS`
      (~line 935), insert between `"apps/web-platform/infra/inngest-server-flip-guard.sh"` and
      `"apps/web-platform/infra/inngest-wiped-volume-verify.sh"` (sorted position):
      - comment line: `# #11848: cloud-init-user-data-size.test.ts reads and executes the real script via BUDGET_SH (join(INFRA, ...)); terraform-target-parity.test.ts only names it in a yaml-pin.`
      - edge line: `"apps/web-platform/infra/inngest-userdata-budget.sh"`
- [x] 1.2 Verify AC-2: `bash scripts/test-all.sh --print-selection --paths=apps/web-platform/infra/inngest-userdata-budget.sh`
      prints `AFFECTED_SELECTED\tplugins/soleur\t1\t`. (verified — `edge:declared` row printed)

## Phase 2 — Ratchet verification

- [x] 2.1 Run `PR_AFFECTED_REPLAY_SELECT_TIMEOUT=290 python3 -I scripts/ci-pr-affected-replay.py ratchet --report /tmp/ratchet-11848.full --base origin/main`
      and confirm `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass` with live=baseline
      (plan-time expectation `live=1510 baseline=1510`). (Runtime ~4 min locally.)
      (verified — 290s override selector-timed-out under host load; re-ran with the 900s
      default: `exit=0 reason=pass live=1510 baseline=1510`)
- [x] 2.2 Read `/tmp/ratchet-11848.full`: assert no `new-pair` lines other than the repaired one.
      If the declare revealed new pairs (expected zero — the script names no tracked path outside
      comments), follow the runbook fixpoint (declare real reads / accept mentions) in the same PR
      and log the deviation. (verified — zero revealed pairs)
- [x] 2.3 Confirm the diff touches only `scripts/lib/test-affected-paths.sh` among source files
      (plus knowledge-base artifacts): `git status --short` + `git diff --name-only origin/main...HEAD`.
- [ ] 2.4 Expect `AFFECTED_FALLBACK reason=runner-changed` on the local `--affected` gate (the edge
      file is a runner trigger — full battery runs once on this PR; that is normal, note it in the
      PR body). (in flight — backgrounded)

## Phase 3 — PR body linkage

- [ ] 3.1 PR body carries `Closes #11848` on its own line; `Ref #10865`, `Ref #11556`, `Ref #11771`
      elsewhere — never `Closes`/`Fixes` for the Ref'd issues.
- [ ] 3.2 Note in the PR body that the disposition diverges from the issue's prescribed accept row
      (declared edge instead — suite really reads/executes the script via `BUDGET_SH`); cite
      `decision-challenges.md` row R1.

## Phase 4 — Post-merge check

- [ ] 4.1 After merge, confirm the next main `merge_group` run of `affected-index-ratchet` is green
      (this un-pauses the #10865 observation-window probe).
