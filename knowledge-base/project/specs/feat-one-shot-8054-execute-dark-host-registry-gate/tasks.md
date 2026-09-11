---
feature: fix-cutover-execute-dark-host-registry-gate
branch: feat-one-shot-8054-execute-dark-host-registry-gate
plan: knowledge-base/project/plans/2026-09-10-fix-cutover-execute-dark-host-registry-gate-plan.md
issue: 8054
closes: [8054]
status: planned
---

# Tasks — op=execute 2.0 accepts a provably-dark dedicated host

Derived from the post-review plan (commit `d238385ee`). Phase numbers match the plan's
`## Implementation Phases`; AC numbers match `## Acceptance Criteria`; E/mutation numbers match
`## Guard Contract`. Every measurement in Phase 0 was taken at plan time and is RE-RUN here as a
freshness check — a disagreement is a finding to stop on.

## Phase 0 — Re-measure (freshness check of plan-time measurements)

- [ ] 0.1 Two separate Better Stack reads (probe stream `--since 24h`, heartbeat stream `--since 15m`), host-isolated post-decode. Confirm the newest dedicated probe row still reads `probe_schema=8 http_code=000 server_active!=active cutover_flag∈{aborted,rolled-back} host_role=dedicated registry_fns=__UNREADABLE__`, and that ≥1 heartbeat row with `_BOOT_ID == strip_hyphens(boot_id)` is ≤15 min old with `.message.flag∈{aborted,rolled-back}`. Record both rows' `dt` in the PR body.
- [ ] 0.2 Confirm the OR-combined read still starves (500 rows, 0 probe rows) — the premise for one-`--grep`-per-read. One command; record the stream histogram.
- [ ] 0.3 Baselines: `bash tests/scripts/test-inngest-host-dark-gate.sh` → `124 passed, 0 failed`, `_PRED_FLOOR=22`, `_FLOOR=124`; `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` → `497 passed, 0 failed`. Record.
- [ ] 0.4 Confirm on the current tree: `_ihdg_row_count` carries an inline selector copy (does NOT reference `"$_IHDG_SELECT"`); the sibling's G8 is `== "inactive"`; `betterstack-query.sh` exit 3 = credentials absent, 2 = query failure. These are the premises Phases 2 and 4 act on.

## Phase 1 — Failing battery first (`cq-write-failing-tests-before`)

- [ ] 1.1 `tests/scripts/test-inngest-host-dark-gate.sh`: extend `bs_line` with a `SYSLOG_IDENTIFIER` arg (default `inngest-server-probe`) and an envelope `_BOOT_ID` arg; every existing call site unchanged. Add `hb_line` producing a heartbeat row whose `.message` is a parsed object `{flag, reason, guard, exit_code, start_ts}`.
- [ ] 1.2 Add cases `[ERG E1]`…`[ERG E13]` and `[ERG H5]` using the existing `expect` / `predicate` helpers (pass token is `dark`). Include the must-REFUSE inputs: zero rows; previous-boot heartbeat (`906c015b…`); `cutover_flag=unknown`; `cutover_flag=rollback`; `server_active=unknown`; numeric `registry_fns` on a non-200 row; heartbeat `flag=armed`; heartbeat 2 h old; `--query-rc 3`; `--hb-rc 2`; raw-lines≥1-decoded==0 on each file.
- [ ] 1.3 Route mutation rows 1–16 and 20 through `mutate()`: per-gate rows address-range scoped to `/^inngest_execute_registry_gate() {$/,/^}$/`; shared-helper rows 7–12 UNSCOPED and each asserted to redden BOTH `inngest_host_dark_gate` and `inngest_execute_registry_gate`. Verify no existing `[G<n>]` `mutate()` row changed from "changed 1 line" to "changed 2 lines" (the same-file collision the plan names).
- [ ] 1.4 Add the `set -euo pipefail` case: `bash -c 'set -euo pipefail; source …; ERG_RC=0; V="$(inngest_execute_registry_gate …refusing input…)" || ERG_RC=$?; printf "%s %s" "$V" "$ERG_RC"'` → token + `1`, shell survives.
- [ ] 1.5 Add `cutover_flag`, `uptime_s`, `registry_fns` to BOTH B12 consumed-field loops; state the per-gate PD override for `registry_fns` (`__UNREADABLE__` on the ERG dark fixture).
- [ ] 1.6 Add helper-level tests: `_ihdg_field` absent/dup/newline → rc 1; `_ihdg_tied_newest` 1 on identical dup, 0 on disagreement; no `_ihdg_*` helper body calls `_ihdg_verdict`.
- [ ] 1.7 Run the suite: RED on every new case; all 124 pre-existing assertions still green.

## Phase 2 — The gate library (`tests/scripts/lib/inngest-host-dark-gate.sh`)

- [ ] 2.1 Extract `_ihdg_graded_row` from `inngest_host_dark_gate`'s inlined G1–G7 (query-rc, rows-file + decode coherence, population-then-silence, newest/tie-free, wall-clock age, exact schema, `boot_id` presence). Returns graded message + row age on stdout, or a refusal token. `inngest_host_dark_gate` calls it; its battery stays at 124 green and its G-row mutations still redden.
- [ ] 2.2 Fold `_ihdg_row_count`'s inline `test("^SOLEUR_INNGEST_SERVER_PROBE ")` copy onto `"$_IHDG_SELECT"` (the literal then appears exactly twice in the file: the selector and the deliberate `wrong_host_rows` inverse).
- [ ] 2.3 Add `inngest_execute_registry_gate` (`--rows-file --query-rc --hb-file --hb-rc --now-epoch --max-row-age --hb-max-age --host --host-name --expected-schema`): calls `_ihdg_graded_row`, then E8 `host_role==dedicated` (`wrong_host`), E9 `http_code` numeric ∧ `!=200`, E10 `server_active` present ∧ `!=unknown` ∧ `!=active` (`unreadable`/`host_serving`), E11 POSITIVE allowlist `cutover_flag∈{aborted,rolled-back}` (`flag_armed` for the arm set, `flag_unreadable` otherwise), E12 `registry_fns==__UNREADABLE__` (`unreadable`), E13 heartbeat (rc→`fsm_unreadable`; decode coherence; select tag+host pair+`_BOOT_ID` equality with hyphens stripped; newest; age→`fsm_silent`; `.message.flag` by the E11 partition). Echo via `_ihdg_verdict` — rc 0 only on `dark`. No `_ierg_verdict`.
- [ ] 2.4 Header: list both consumers incl. `scripts/cutover-inngest.sh op=execute (P0 cutover step)`; copy the E-table beside the G-table; record the G8 (`== inactive`) vs E10 (`!= active`) divergence and cite #8078.
- [ ] 2.5 `shellcheck -S warning` the lib.

## Phase 3 — Green, then floors

- [ ] 3.1 Suite green. Change `_FLOOR`'s comparison to `-ne` with a `STALE FLOOR — set _FLOOR=<ran>` message; set `_FLOOR` to the measured ran-count (exact); set `_PRED_FLOOR` to covered−1 (the file's convention). Record both numbers in the PR body.

## Phase 4 — Wire 2.0 (`scripts/cutover-inngest.sh`)

- [ ] 4.1 Generalise `_flip_query_rows` → `_bs_query_rows <since> <grep> <limit>`; update its three call sites to pass `inngest-cutover-flip` (behaviour unchanged). No `_probe_query_rows` / `_guard_block_query_rows`.
- [ ] 4.2 In the `execute)` arm, replace ONLY the `if [[ "$CODE" != "200" ]]; then … exit 1; fi` branch: `::notice::` prefixed `expected pre-arm (P1-5): webhook probe HTTP $CODE — grading darkness from the host's own rows`; guarded `source tests/scripts/lib/inngest-host-dark-gate.sh || { echo "::error::2.0: gate library not found on this ref — dispatch with --ref main"; exit 1; }`; two `_bs_query_rows` calls (probe `--since 24h --limit 500`, heartbeat `--since 15m --limit 200`) to tempfiles, each `|| rc=$?`; the guarded call `ERG_RC=0; ERG_VERDICT="$(inngest_execute_registry_gate …)" || ERG_RC=$?`; `case "$ERG_VERDICT"` with one arm per token (11) + `*)`.
- [ ] 4.3 `dark` arm: `::notice::` naming `boot_id`, the graded flag, probe-row age, heartbeat age, and the plain-words sentence (“the dedicated host is intentionally refusing to start until `op=arm`; a non-200 loopback with the server not active is the correct pre-flip posture, not a fault”); falls through to 2.1. Each refusal arm: the E-table's `::error::` text (E1 branches on `PROBE_RC` 3/2/1/0; E11 branches on `ERG_FLAG` done/armed|flipping/flushed; E9/E10 says check the webhook path first), `exit 1`. `*)`: token + both rcs + “this is a defect in the gate, not a host state — file an issue with this run URL; do not proceed”, `exit 1`.
- [ ] 4.4 D4: rewrite steps (2)–(3) of the existing P1-6 `::error::` per the plan (read `ERG_FLAG` → verify / read the arm run / resume; pre-arm + non-empty → `doublefire-probe` then `rollback`). Remove `stop the dark inngest-server`.
- [ ] 4.5 Append the designed-stop sentence to the 2.2 STILL RUNNING message (quiesce-web opens the maintenance window; dispatch quiesce-web → execute → arm back-to-back; the watchdog restarts the web scheduler within 15 min — #8077).
- [ ] 4.6 Add the one `::warning::` after the `pre-flight clear` notice on the reachable-empty arm, naming #8072.
- [ ] 4.7 `shellcheck -S warning scripts/cutover-inngest.sh`. Run AC7 (scoped diff, D4 echo excluded) → identical. Run AC9 (diff-scoped denylist) → 0.

## Phase 5 — Wiring suite (`apps/web-platform/infra/cutover-inngest-workflow.test.sh`)

- [ ] 5.1 Assert exactly one guarded gate call in the execute arm (`|| ERG_RC=$?` present; a bare `$(…)` fails).
- [ ] 5.2 Assert every token the lib can emit (extracted from the lib) has a `case` arm, and `*)` exits 1.
- [ ] 5.3 Assert two `_bs_query_rows` call sites in the execute arm, one `--grep` term each, distinct terms.
- [ ] 5.4 Assert the `source` line is `||`-guarded.
- [ ] 5.5 Assert no added `echo "::…"` line interpolates `PROBE_ROWS*`, `HB_ROWS*`, `BODY`.
- [ ] 5.6 Assert set-equality between the P1-5 allowlist derived from `apps/web-platform/infra/inngest-server-flip-guard.sh`'s `case` arm and the E11/E13 set in the lib (mutation #20 reddens it).
- [ ] 5.7 H6: the reachable-empty arm remains reachable and does not route through the gate; mutation rows 17–19 (rc swallowed, `*)` fall-through, un-guarded call) each redden.
- [ ] 5.8 Suite green; raise its anti-deletion floor to the new measured count.

## Phase 6 — ADR, C4, full battery

- [ ] 6.1 ADR-100: add `## Addendum — 2026-09-11 (#8054) — "host dark" is a positive reading, and 2.0 accepts it` with the eight decision points in the plan's `### ADR` (including the rejected `BLOCK:` design and its measurement, the G8/E10 divergence → #8078, the reachable-arm asymmetry → #8072).
- [ ] 6.2 `model.c4`: amend `github -> betterstack` (`op=execute` 2.0 beside `op=verify` as a safety-critical Logs read) and `inngest -> betterstack` (the `inngest-cutover-flip` heartbeat is a safety-critical input to 2.0). `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] 6.3 `python3 scripts/lint-guard-contract.py <plan>`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.4 `bash scripts/test-all.sh` — marker `^=== N/M suites passed ===$` + rc file `0` (AC17; a no-marker rc-4 refusal is a sibling run, not a verdict).

## Phase 7 — Acceptance and the live dispatch

- [ ] 7.1 Walk AC1–AC18 with the exact commands in the plan; paste each result in the PR body.
- [ ] 7.2 TS3/TS4/TS5/TS6/TS7 (live read-only + local) — record tokens.
- [ ] 7.3 After merge (AC19): re-measure the precondition (`INNGEST_CUTOVER_FLIP`=`aborted`, newest probe `http_code=000`); `gh workflow run cutover-inngest.yml --ref main -f op=execute`; watch with the Monitor tool; confirm the AC19 log anchors in order and the stop at 2.2 with the designed-stop sentence; confirm `INNGEST_BASE_URL` unchanged; nothing quiesced, armed or flushed.
