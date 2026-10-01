---
feature: fix-cutover-execute-dark-host-registry-gate
branch: feat-one-shot-8054-execute-dark-host-registry-gate
plan: knowledge-base/project/plans/2026-09-10-fix-cutover-execute-dark-host-registry-gate-plan.md
issue: 8054
closes: [8054]
status: planned
---

# Tasks — op=execute 2.0 accepts a provably-dark dedicated host

Derived from the DEEPENED plan (post plan-review + deepen-plan, 2026-09-11). Phase numbers match
`## Implementation Phases`; AC numbers `## Acceptance Criteria`; E/row numbers `## Guard Contract`.
Every Phase 0 measurement was taken at plan time and is RE-RUN here as a freshness check — a
disagreement is a finding to stop on.

## Phase 0 — Re-measure

- [x] 0.1 Two separate reads (probe `--since 24h --limit 500`, heartbeat `--since 15m --limit 200`), host-isolated post-decode. Newest dedicated probe row: `probe_schema=8 http_code=000 server_active!=active cutover_flag∈{aborted,rolled-back} host_role=dedicated registry_fns=__UNREADABLE__`; ≥1 heartbeat row with `_BOOT_ID == ${boot_id//-/}` ≤15 min old, `(.message|type)=="object"`, `.message.flag∈{aborted,rolled-back}`. Record both `dt` in the PR body.
- [x] 0.2 Confirm the OR-combined read still starves (500 rows, 0 probe rows).
- [x] 0.3 Baselines: dark-gate suite `124 passed, 0 failed`, `_PRED_FLOOR=22`, `_FLOOR=124`; wiring suite `497 passed, 0 failed`.
- [x] 0.4 Confirm on the current tree: `_ihdg_row_count` carries an inline selector copy; sibling G8 is `== "inactive"`; `gate()` and `mutate()` in the suite call `inngest_host_dark_gate` by name; `betterstack-query.sh` line 271 is `curl … --fail-with-body` (rc 22 on HTTP error), exit 3 = creds absent, exit 2 = destination-pin refusal, 64 usage, 78 trace; `_flip_query_rows` has exactly two call sites.

## Phase 1 — Failing battery first (`cq-write-failing-tests-before`)

- [x] 1.1 `tests/scripts/test-inngest-host-dark-gate.sh`: `bs_line` gains `SYSLOG_IDENTIFIER` (default `inngest-server-probe`) and envelope `_BOOT_ID` args, every existing call unchanged; add `hb_line` producing a heartbeat row whose `.message` is a parsed object `{flag, reason, guard, exit_code, start_ts}` with an explicit `_BOOT_ID` arg — its defaults must NOT be derived from the probe row it is paired with (fixture-default tautology).
- [x] 1.2 **Rebind the harness:** `gate()` and `mutate()`'s mutated-run invocation dispatch on `${GATE_FN:-inngest_host_dark_gate}` with per-entry-point default args. `mutate()` derives `want_rc` from the expected token and passes on `got != tok || rc != want_rc`. Add ERG must-FAIL self-tests (`expect … dark` on a refusing ERG fixture MUST fail; duplicate `predicate` id MUST fail) and the H7 known-negative (scoped `sed` on an unused `local` → `mutate()` MUST report `did NOT change the verdict`).
- [x] 1.3 Predicate (escape-row) cases `[ERG-E1]`…`[ERG-E13]` + `[ERG-E4b]` (disagreeing tie as INPUT) + `[ERG-H5]`, `[ERG-H5b]`, `[ERG-H5c]` using `expect`/`predicate` (pass token `dark`). Must-REFUSE inputs include: zero rows; previous-boot heartbeat (`906c015b…`); heartbeat rows with NO `_BOOT_ID` → `fsm_silent`; `cutover_flag=unknown` / `rollback` / empty → `flag_unreadable`; `server_active=unknown` → `unreadable`; numeric `registry_fns` on non-200 → `unreadable`; heartbeat newest `flag=armed` (60 s) beside older `aborted` (600 s) → `flag_armed`; heartbeat 2 h old → `fsm_silent`; `--hb-max-age 15m` (string) → `fsm_unreadable`; `--query-rc` 3, 1, 22, 2, 99 (one `[ERG-E1]` case per remediation branch); `--hb-rc 22` → `fsm_unreadable`; raw-lines≥1-decoded==0 on each file → `unreadable`/`fsm_unreadable`; newest tag row a STRING message (`SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED …`) beside a fresh object row → `dark`. Must-PASS: H5 (five axes in the label), H5b (older same-boot `armed` + foreign-boot `armed` + newest `aborted`; probe `aborted` vs heartbeat `rolled-back`; `server_active=inactive`), H5c (`row_age == max_row_age`, `hb_age == hb_max_age`).
- [x] 1.4 Matrix rows 1–16, 20–22 through `mutate()`: E8–E13 rows scoped `/^inngest_execute_registry_gate() {$/,/^}$/`; E1–E7 and helper rows (6–12) UNSCOPED, each asserted to redden BOTH gates. Every row is ONE substituted pristine line: row 12 = `s|^  if [[ "$(_ihdg_tied_newest .*|  if false; then|` on `rows-m6a.json` → `unreadable`; row 13 = the gate's first `local` line → `_ihdg_verdict dark; return $?`; row 15 mutates the `-le "$hb_max_age"` comparison, not the default; row 21 = `(._BOOT_ID // "") == $bid`; row 22 = move the flag test into the jq selector. Verify no pre-existing `[G<n>]` `mutate()` row now reports "changed 2 lines".
- [x] 1.5 Direct-call errexit case: `bash -c 'set -euo pipefail; source …; inngest_execute_registry_gate --rows-file /dev/null --query-rc 0 …'` → `tail -1` is the token, rc 1 (TS7).
- [x] 1.6 Add `cutover_flag`, `uptime_s`, `registry_fns` to BOTH B12 loops; per-gate PD override `registry_fns=__UNREADABLE__`.
- [x] 1.7 Helper-level tests: `_ihdg_field` absent/dup/newline → rc 1; `_ihdg_tied_newest` 1/0; `_ihdg_epoch_from_dt` refuses `yesterday`, `now`, `2026-09-11 10:00:00; touch x`; no `_ihdg_*` body calls `_ihdg_verdict`; `_ihdg_graded_row` and `_ihdg_epoch_from_dt` appear only inside `$(…)`.
- [x] 1.8 Token-coverage floor: `expect()` appends `$want` to `_seen_tokens`; a third floor computes `T` from the lib, asserts `T ⊆ _seen_tokens`, `dark` asserted ≥2, prints `ok   token coverage: <n>/<n> tokens asserted`.
- [x] 1.9 Run: RED on every new case; all 124 pre-existing assertions green.

## Phase 2 — The gate library

- [x] 2.1 Extract `_ihdg_graded_row` (G1–G7 / E1–E7) and `_ihdg_epoch_from_dt` (G3's regex + `date -u -d "… UTC"`); `inngest_host_dark_gate` calls both; its battery stays 124 green with G-row mutations still reddening. Fold `_ihdg_row_count`'s inline selector onto `"$_IHDG_SELECT"` (literal `test("^SOLEUR_INNGEST_SERVER_PROBE ")` then appears exactly twice).
- [x] 2.2 `inngest_execute_registry_gate` (`--rows-file --query-rc --hb-file --hb-rc --now-epoch --max-row-age --hb-max-age --emit-file --host --host-name --expected-schema`): `--hb-max-age` NUMERIC (`^[0-9]{1,9}$`, default `900`); E7 `boot_id` matches the UUID regex and `bid="${boot_id//-/}"` matches `^[0-9a-f]{32}$` in bash BEFORE jq; E8 `wrong_host`; E9/E10 numeric + present + `!=unknown` + `!=200`/`!=active`; E11 POSITIVE allowlist `{aborted, rolled-back}` → `flag_armed` / `flag_unreadable`; E12 `registry_fns==__UNREADABLE__` → `unreadable`; E13 selector on TYPE only (`SYSLOG_IDENTIFIER`, host pair, `(._BOOT_ID|type)=="string"`, `test("^[0-9a-f]{32}$")`, `== $bid`, `(.message|type)=="object"`), `sort_by(.dt)|last`, `dt` via `_ihdg_epoch_from_dt`, age ≤ bound and ≥ 0 else `fsm_silent`, `(.message.flag // "__ABSENT__")` exact-matched in a bash `case`. Echo one token via `_ihdg_verdict`. Write `--emit-file` lines `flag=` / `boot_id=` / `row_age=` / `hb_age=` ONLY after each value passed its predicate; `flag=__UNREADABLE__` on `flag_unreadable`.
- [x] 2.3 Header: both consumers (`scripts/cutover-inngest.sh op=execute (P0 cutover step)`), E-table copied, G8/E10 divergence recorded → #8078.
- [x] 2.4 `shellcheck -S warning` the lib.

## Phase 3 — Green, then floors

- [x] 3.1 `_FLOOR` → `-ne` with `STALE FLOOR — set _FLOOR=<ran>`; set to the measured ran-count; `_PRED_FLOOR` = covered−1. Record both in the PR body.

## Phase 4 — Wire 2.0 (`scripts/cutover-inngest.sh`)

- [x] 4.1 `_flip_query_rows` → `_bs_query_rows <since> <grep> <limit>`; two existing call sites pass `inngest-cutover-flip`. It captures stderr to a `mktemp` file (the inherited `2>/dev/null` is gone) and returns rc. Row/err tempfiles via `mktemp` under `${RUNNER_TEMP:-/tmp}`, `umask 077`, `trap 'rm -f …' EXIT`.
- [x] 4.2 In `execute)`, replace ONLY the `if [[ "$CODE" != "200" ]]; then … exit 1; fi` branch: `::notice::expected pre-arm (P1-5): webhook probe HTTP $CODE — grading darkness from the host's own rows`; plain (non-annotation) line `2.0 webhook body (HTTP $CODE, informational — grading from host rows): ${CAUSE:-<empty body>}` CR/LF-stripped; guarded `source … || { echo "::error::2.0: gate library not found on this ref — dispatch with --ref main"; exit 1; }`; two `_bs_query_rows` calls (one `--grep` each); `ERG_RC=0; ERG_VERDICT="$(inngest_execute_registry_gate … --emit-file "$erg_emit")" || ERG_RC=$?`; read `--emit-file` behind `[[ "$line" =~ ^(flag|boot_id|row_age|hb_age)=([A-Za-z0-9_-]{1,64})$ ]] || continue`; `case "$ERG_VERDICT"` with 11 arms + `*)`.
- [x] 4.3 `dark` arm: `::notice::` with `boot_id=… flag=… row_age=… hb_age=…` and the plain-words sentence (value-agnostic about the flag literal); fall through to 2.1. Refusal arms: the E-table's `::error::` text — E1 branches on `PROBE_RC` 3/1/22/`2|64|78`/`*` and prints the captured stderr first line; E13 same on `HB_RC`; E9/E10 check the webhook path first; E11/E13 flag tokens branch on the emitted `flag=`. `*)`: `ERG_VERDICT="${ERG_VERDICT:0:32}"`, `//[^a-z_]/?`, both rcs, "defect in the gate — file an issue with this run URL", `exit 1`.
- [x] 4.4 D4: rewrite steps (2)–(3) of the P1-6 `::error::` on the HTTP-200 arm to the OPERATOR read (`gh run list --workflow scheduled-inngest-health.yml --limit 1` → `gh run view <id> --log | grep -o 'cutover_flag=[a-z-]*'`; done → `op=verify`; armed/flipping → read the arm run; flushed → `op=resume`; pre-arm + non-empty → `doublefire-probe` then `rollback`). NO `ERG_*` on that path. Remove `stop the dark inngest-server`.
- [x] 4.5 Append the designed-stop sentence to the 2.2 STILL RUNNING message (quiesce-web opens the maintenance window; back-to-back inside 15 min; #8077).
- [x] 4.6 `::warning::` after `pre-flight clear` on the reachable arm, naming #8072.
- [x] 4.7 `shellcheck`; AC7 (scoped, D4 echo excluded) → identical; AC9 (diff-scoped denylist incl. `CAUSE`, `newest_msg`, `chosen_msg`, `rows_tsv`, `hb_msg`) → 0.

## Phase 5 — Wiring suite

- [x] 5.1 Add `mutate_script <sed> <assert-fn>` (pristine copy of `scripts/cutover-inngest.sh`, `cmp` + exactly-one-line guards, re-run the extracted assertion, assert FAIL); floor comparison → `-ne`.
- [x] 5.2 Assertions: one guarded gate call (`|| ERG_RC=$?`); every lib token has a `case` arm; `*)` exits 1; two `_bs_query_rows` sites, one distinct `--grep` each; guarded `source`; no added `echo "::…"` interpolates the AC9 denylist; every `$ERG_*` interpolation is on the dark arm after the gate call and assigned only from the `--emit-file` regex read; E11/E13 allowlist set-equal to the P1-5 `case` derived from `inngest-server-flip-guard.sh`; the `dark` notice against the H5 fixture matches `boot_id=[0-9a-f-]{36}.*flag=(aborted|rolled-back)`; H6 reachable arm not routed through the gate.
- [x] 5.3 `mutate_script` rows 17 (`|| rc=$?` removed), 18 (`*)` fall-through), 19 (bare `$(…)`) each redden.
- [x] 5.4 Suite green; floor raised to the measured count.

## Phase 6 — ADR, C4, full battery

- [x] 6.1 ADR-100 addendum `## Addendum — 2026-09-11 (#8054) — …` with the eight decision points (incl. the rejected `BLOCK:` design + measurement, G8/E10 → #8078, reachable-arm asymmetry → #8072).
- [x] 6.2 `model.c4`: `github -> betterstack` (+`op=execute` 2.0) and `inngest -> betterstack` (+heartbeat as safety-critical input). `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [x] 6.3 `python3 scripts/lint-guard-contract.py <plan>`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.4 (REFUSED rc 4 at /work — 6 sibling full-gate runs in flight; targeted suites run instead: dark-gate 256/0, wiring 545/0, ci-deploy 216/0, infra-config-verify 41/0, inngest-host 43/0, guard-vacuity-floor 23/0, terraform-target-parity 194/0, C4 syntax+render 23/0, lint-workflows, lint-orphan, lint-guard-contract, lint-infra-no-human-steps, trace-credential (repo + --changed). Full battery re-attempted at ship.) `bash scripts/test-all.sh` — marker + rc file `0` (AC17; a no-marker rc-4 is a sibling run, not a verdict).

## Phase 7 — Acceptance and the live dispatch

- [ ] 7.1 Walk AC1–AC18 (incl. AC16b) with the exact plan commands; paste results in the PR body.
- [ ] 7.2 TS3–TS7 (live read-only + local); record tokens.
- [ ] 7.3 After merge (AC19): re-measure the precondition; `gh workflow run cutover-inngest.yml --ref main -f op=execute`; Monitor; confirm the AC19 anchors in order and the stop at 2.2 with the designed-stop sentence; `INNGEST_BASE_URL` unchanged; nothing quiesced, armed or flushed.

## /work notes (2026-09-11)

- Matrix rows 21 and 22 landed as INPUT cases (equivalent mutant / design-shape change — see the plan's amended rows); H7 uses a comment line, not a planted `local`.
- `_flip_query_rows` → `_bs_query_rows` has FOUR call sites (confirm, liveness, 2.0 probe, 2.0 heartbeat); the wiring suite asserts 4 total and 2 flip-tag sites.
- The HTTP-200 block moved into an `else` (re-indented); AC7 compares with comments and leading whitespace stripped, as the AC section's preamble already prescribes.
- Unplanned but forced by CI: `lint-shell-trace-credential-refusal.py --changed` unbaselines any touched file, and `scripts/cutover-inngest.sh` carried 25 violations. Paid down (xtrace refusal + 24 `curl --disable --noproxy '*'`), removed from both baselines, pinned in the wiring suite.
- Suite counts: dark-gate `_PRED_FLOOR=35` (36 covered), `_FLOOR=256` exact, token coverage 18/18; wiring `_EXACT_FLOOR=545`.
