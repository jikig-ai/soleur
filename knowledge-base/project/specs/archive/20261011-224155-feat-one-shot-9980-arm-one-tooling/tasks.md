# Tasks: arm-heartbeats --status / --arm-one (#9980)

Plan: `knowledge-base/project/plans/2026-10-11-feat-arm-heartbeats-status-and-arm-one-plan.md`
Refs #9438 (never Closes). PR may `Closes #9980`. No production call, no workflow edit.

## Phase 0 - Setup and failing tests first

- 0.1 Extend the fake curl in `apps/web-platform/infra/arm-heartbeats.test.sh`: list endpoint served from `$FAKE_LIST_DIR/page-<n>.json`, `per_page=250` required, off-origin host refused (exit 67, logged first), missing page `exit 64`, `FAKE_LIST_FAIL` knob for 500/empty/garbage. Keep every existing refusal intact.
- 0.2 Plain stub self-test (H1): list without `per_page` refused; page 2 reachable; off-origin refused. Export FAKE_LIST_DIR/FAKE_LIST_FAIL in case_setup and the self-test block; run helpers set TMPDIR=$CASE.
- 0.3 Write ST1-ST5, AX (argument refusals), AO1-AO6 and AO8 cases; run against the unmodified script and record the failing count.
- 0.4 Write mutation rows M22-M33 (each asserts the edit landed on exactly N lines; adjust existing M7 landing count 2 -> 3) plus a new-mode unmutated control.

## Phase 1 - Script plumbing (`apps/web-platform/infra/arm-heartbeats.sh`)

- 1.1 Header CONTRACT block and `usage()`: new modes, `--id`, exit codes, private books; keep the `sed` range ending at `#   mint-unreadable`.
- 1.2 Argument parser (`--status <name>`, `--arm-one <name> [--id <id>]`), name charset `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`, id `^[0-9]+$`, refuse extras; optional 4th positional parameter on `arm_one` (no global/env).
- 1.3 `hb_resolve_name` (paginated, quoted-prefix pin on `next`, exactly-20-request bound, `.data` must be an array on every page, delimiter `\x1f` with per-field null sentinel, count matches without dedupe, direct call not a subshell, fail closed on any bad page).
- 1.4 Gate the tfstate/required-env/resource-count block on `MODE == arm`; add the optional 4th-parameter override inside `arm_one`. Do not touch the six `arm_one '` call lines or the inngest block.

## Phase 2 - `--status`

- 2.1 `status_main`: require token shape, resolve, print `name= id= paused= status= period= grace=`, rc 0 only for exactly one match, zero PATCH reachable.

## Phase 3 - `--arm-one`

- 3.1 `armone_main`: resolve; `--id` equality; deadline guard (`ARM_ONE_DEADLINE=150`, max derived from `ARM_POLL_INTERVAL_S + 2 * ARM_CURL_MAX_TIME_S`, fail closed on non-numeric period/grace).
- 3.2 Private `mktemp` books when `ARMED_UNCONFIRMED` unset; print path and `--sweep` recovery command before the first PATCH; remove only when empty and private.
- 3.3 Call `arm_one` via the override; pass rc 0/1/2 through; extra line on rc 2 about the git-data-liveness events.

## Phase 4 - Suite completion

- 4.1 Make all new cases and mutation rows green; run the suite; set `ASSERT_FLOOR` to the exact new total and extend its ratchet comment.

## Phase 5 - Targeted verification (no full-suite run)

- 5.1 `bash apps/web-platform/infra/arm-heartbeats.test.sh` (note runtime vs 21000 ms manifest value).
- 5.2 `plugins/soleur/test/terraform-target-parity.test.ts`: change ONLY the the `$(bs_api` call-site token (with its trailing space) pin 2 -> 3 with rationale; run it with bun.
- 5.3 `bash scripts/guard-vacuity-floor.test.sh`; `bash plugins/soleur/test/fixture-relative-assert.test.sh` (regenerate baseline only if it reds); `scripts/lint-shell-trace-credential-refusal.py` on both shell files; `shellcheck`; `plugins/soleur/test/c4-count-parity.test.sh`.
- 5.4 Confirm `git diff origin/main -- apps/web-platform/infra/arm-heartbeats.sh` has no hunk on the six `arm_one '` call lines or the inngest block.

## Review round (PR #10029)

- R.1 Fix findings from the ten-seat panel: verdict line, `up`-only rc 0, `--id ''`, `ARM_POLL_INTERVAL_S` validation, resolver hardening (pagination type, validate-before-strip, empty id), ambiguous-unpause read-back, books preflight and own-id residue check, runbook wrapper and recovery, ADR wording. Cases ST1b-ST5n, AX2, AO6f-g, AO7b-d, AO10-AO12; mutation rows M35-M42.

## Phase 6 - Docs

- 6.1 Runbook step 7 in `git-data-luks-cutover-5274.md`: replace "do not arm by hand" with the `--status` (READONLY secret name) and `--arm-one` (write secret name, `--id 506836`) invocations via `doppler run ... -- bash -c '...'`, no-exposure explanation, interrupt recovery; point at `--help` for the exit-code table (steps 4 and 9 untouched).
- 6.2 ADR-117 short dated amendment (second entry; no alternatives table); ADR-283 pointer update.
- 6.3 PR body: `Closes #9980`, `Refs #9438`, `## Changelog`, note the issue's wrong script path; note period/grace are first read live by the owner's `--status` (fails closed if absent).
