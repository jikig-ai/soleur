---
title: "Tasks — fix(inngest): op=inventory eventsV2 ARG_MAX overflow"
feature: feat-one-shot-5523-inngest-inventory-argmax
plan: knowledge-base/project/plans/2026-06-18-fix-inngest-inventory-argmax-overflow-plan.md
issue: 5523
lane: procedural
---

# Tasks — fix #5523 inngest inventory/enumerate ARG_MAX overflow

## Phase 0 — Preconditions

- [ ] 0.1 `git grep -n 'argjson a "$all_edges"' apps/web-platform/infra/` → exactly 2 hits
      (`inngest-inventory.sh:154`, `inngest-enumerate-reminders.sh:126`). If a 3rd, extend scope.
- [ ] 0.2 Confirm both scripts carry `set -euo pipefail`.
- [ ] 0.3 Re-confirm tempfile fix locally: `tmp=$(mktemp); echo '[{"a":1}]'>>"$tmp"; echo '[{"a":2}]'>>"$tmp"; jq -s 'add' "$tmp"`.
- [ ] 0.4 Confirm enumerate is in `apply-deploy-pipeline-fix.yml` FILE_MAP (line 85 — verified at plan time).

## Phase 1 — RED test (inventory)

- [ ] 1.1 Add large-edge overflow test to `inngest-inventory.test.sh` (N pages × M edges
      so the running accumulator > ~128 KB). Synthesized fixture only (cq-test-fixtures-synthesized-only).
- [ ] 1.2 Calibrate: run the new test against the **unpatched** script; confirm it FAILs
      with `Argument list too long`. (RED-first is load-bearing.)
- [ ] 1.3 Add structural guard: test FAILs if `grep -qE 'argjson a "\$all_edges"' "$TARGET"`
      matches; positively assert accumulation reads from a file. Anchor on the exact
      `argjson a "$all_edges"` string (not bare `--argjson`).
- [ ] 1.4 Register both in the harness call list (lines ~200–210); confirm exit-gate `[[ FAIL -eq 0 ]]`.

## Phase 2 — GREEN fix (both scripts)

- [ ] 2.1 `inngest-inventory.sh`: replace `all_edges=$(jq -nc --argjson a ... )` loop with
      `mktemp` spool + per-page `echo "$resp" | jq -c '.data.eventsV2.edges // []' >> "$edges_file"`
      + post-loop `all_edges=$(jq -s 'add // []' "$edges_file")`; add `trap "rm -f '$edges_file'" RETURN`
      (`# shellcheck disable=SC2064`). Keep projections reading `echo "$all_edges" | jq` (stdin) unchanged.
- [ ] 2.2 `inngest-enumerate-reminders.sh`: apply the identical transformation to its loop
      (line 104 + 126). Keep the two scripts in lockstep.

## Phase 3 — enumerate test parity

- [ ] 3.1 Add the same large-edge overflow test + structural guard to
      `inngest-enumerate-reminders.test.sh` (adapt to its `make_edge` signature).
- [ ] 3.2 Calibrate RED-first against unpatched enumerate; register in its call list.

## Phase 4 — Local verification

- [ ] 4.1 `bash apps/web-platform/infra/inngest-inventory.test.sh` → 0 failed.
- [ ] 4.2 `bash apps/web-platform/infra/inngest-enumerate-reminders.test.sh` → 0 failed.
- [ ] 4.3 `bash apps/web-platform/infra/inngest-rearm-reminders.test.sh` + `cutover-inngest-workflow.test.sh` → still pass.
- [ ] 4.4 `shellcheck` clean on both edited scripts.

## Phase 5 — Ship + post-merge live verify

- [ ] 5.1 PR body: `Closes #5523`.
- [ ] 5.2 (ship-automated) `gh workflow run cutover-inngest.yml -f op=inventory`; assert
      run log shows `::notice::inventory: functions=N event_names=M armed_reminders=K`, zero
      `Argument list too long`.
- [ ] 5.3 (ship-automated) re-run `op=enumerate`; assert HTTP 200 JSON array, no overflow.
