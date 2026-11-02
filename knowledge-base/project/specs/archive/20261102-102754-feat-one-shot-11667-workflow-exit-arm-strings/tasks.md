# Tasks: feat-one-shot-11667-workflow-exit-arm-strings

Plan: `knowledge-base/project/plans/2026-11-02-chore-workflow-exit-arm-strings-11667-plan.md`. Issue: Ref #11667, Ref #9757. Draft PR: #11841. One PR. Never dispatch a recut or restore.

## Phase 0: Setup

- 0.1 `git fetch origin main`; record `wc -c` of the workflow on the branch and on `origin/main` (plan time: both 489,680).
- 0.2 Re-count each anchor in the plan's edit table with `grep -c` (each must be exactly 1); if main moved, recompute the byte table before editing.

## Phase 1: RED pin (tests/scripts/test-registry-d10-workflow-wiring.sh)

- 1.1 In `w9_check`'s per-code `case "$code" in` block add `6)` on `$line`: `grep -qiF 'unverified'` and `grep -qF 'do not deploy'`; `w9_add` messages carry the literal lowercase needle.
- 1.2 Add `unv6|unverified` and `nodeploy|do not deploy` controls to the `for w9_c` list and matching `elif` branches in `W9_PY` (locate the arm with `re.search(r'\n( *6\) echo [^\n]*)', seg)`, `once(...)`-guarded `re.sub` removing the phrase; template: the `manifest` branch).
- 1.3 Raise `EXPECTED_ASSERTIONS` from 91 to 93.
- 1.4 Run the suite against the UNCHANGED workflow; record the RED output (the `6)` check and both controls fail).

## Phase 2: GREEN workflow edit (.github/workflows/apply-web-platform-infra.yml)

- 2.1 Apply the eight edits from the plan's table (R1 `may be EMPTY`, R2, R3, R4 `Nothing was written; ...`, CMT, E5, R8, R5), one Edit per anchor. Do not apply R6 or R7.
- 2.2 `wc -c` must be at most 489,650 and strictly below the Phase 0 figure (expected 489,617, -63). If over, drop E5.
- 2.3 Leave the Restore-summary echo lines, exit-1/2/3/4 arms, `*)` arm and `# Rationale:` pointers byte-identical.

## Phase 3: Verification

- 3.1 `bash tests/scripts/test-registry-d10-workflow-wiring.sh` (93 passed, 0 failed).
- 3.2 One-off scratch mutations (not permanent controls): `6)` label neutered in the suite makes both controls report `expected a refusal ... got: <nothing>`; arm 6 reworded (order and case) is accepted.
- 3.3 `bun test plugins/soleur/test/workflow-file-size.test.ts` (test `no workflow file exceeds the gate`).
- 3.4 YAML parse of the workflow.
- 3.5 `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/stock-preflight-coverage.test.ts`; `bash tests/scripts/test-argv-bearer-sweep.sh`; `bash tests/scripts/test-registry-luks-recut-gate.sh`.
- 3.6 `git diff origin/main --stat` shows only the two planned files plus planning artifacts.

## Phase 4: Ship and post-merge

- 4.1 Before merge: `gh run list --workflow apply-web-platform-infra.yml --status in_progress` and `--status queued` are empty (never cancel an apply); no `[skip-web-platform-apply]` line anywhere.
- 4.2 PR body first line: merging fires the push apply run (no `.tf` change; recut/restore skipped on push). Body uses `Ref #11667` and `Ref #9757` only.
- 4.3 Post-merge: push run `preflight` and `apply` success; `registry_luks_recut`, `registry_pull_path_gate`, `registry_store_restore` skipped; failure-notification job skipped or success; file on main is 489,617; CI on main green; `/health` ok; no new `ci/` issue; comment the evidence on #11667 (stays open).
