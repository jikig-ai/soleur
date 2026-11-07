---
title: "fix: printf SIGPIPE under pipefail in luks-monitor and cutover-inngest-workflow suites (#9325)"
type: fix
date: 2026-10-24
slug: fix-9325-sigpipe-flake
branch: feat-one-shot-9325-sigpipe-flake
issue: 9325
closes: 9325
lane: engineering
---

# fix: printf SIGPIPE under pipefail in luks-monitor and cutover-inngest-workflow suites (#9325)

## Overview

Issue #9325 records two `printf: write error: Broken pipe` flakes in CI under `-P4`
leg contention:

- `apps/web-platform/infra/luks-monitor.test.sh` — the SUT feed `printf '%s' "$key" | cryptsetup luksOpen --test-passphrase --key-file - "$real_dev"` (luks-monitor.sh:224; the issue cites :176 against an older revision). Observed red row: "wrong-source fstab did not fail fstab_mapper_line_missing" — pipefail folded a producer SIGPIPE (141) into a fake `escrow_passphrase_mismatch` before the fstab asserts ran.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — five `printf '%s\n' "$FIX_*" | _generation_scoped_count … 2>"$FLV_ERR" )"` sites (current lines ~1475, ~1480, ~1486, ~1493, ~1496; the issue cites :1341). Each is the LAST command of a `FILTER_OUT="$( … )"` assignment under `set -euo pipefail`, so a producer 141 propagates through the assignment and kills the whole suite.

## Research Reconciliation — Issue vs. Tree

| Issue claim | Reality in this tree | Response |
|---|---|---|
| "make the `cryptsetup` stub drain stdin (`cat >/dev/null`)" | **Already done.** c99a4451df (#9245, merged 2026-09-30 21:21 UTC — AFTER both cited runs, 16:12/18:49 UTC) added flag-gated drains to BOTH harness cryptsetup stubs: `mon_prepare`'s `bin/cryptsetup` drains into `$CALLS.escrow-stdin`, `run_case`'s `cryptsetup()` drains `cat >/dev/null`, and luks-monitor.test.sh pins the drain with the (t1b) wire assert. | Verify only; no stub change needed for the drain itself. The stub gains a `MON_ESCROW_ERR` knob to drive the new failure-split rows. |
| "feed `_generation_scoped_count` from a here-string or a file instead of a pipe" | Correct and still needed. Three of the five sites race a refusal the consumer never reads stdin for (the two `_current_instance_row_counts` overrides that never read, and the `""`-tag refusal at ~1486); the other two are the same shape with a draining consumer. | Convert all five to here-strings (uniform shape; no producer process ⇒ no SIGPIPE class at all). |
| "an early `cryptsetup` error at luks-monitor.sh:176 would report `escrow_passphrase_mismatch` instead of its real cause" | **The misattribution is real.** Every non-zero of that pipeline — keyslot rejection, early device/tooling error, rc 127, or the producer's own SIGPIPE (141) — lands in `emit_and_die escrow_passphrase_mismatch`, which `is_at_rest_drift` files as the p0 type/security verdict asserting the published Article 32 claim is false. A tooling fault filing that verdict is the confidently-wrong-verdict class this codebase repeatedly fixes (the `cryptsetup_status_missing`/`mapper_device_link_missing` TOOLING_FAULTS carve-out exists for exactly this reason). | Fix it: capture cryptsetup's stderr, split "keyslot tested and rejected" (`escrow_passphrase_mismatch`, at-rest) from "the test never produced a keyslot verdict" (new `escrow_check_failed`, probe-integrity → `unavailable`). The match fails TOWARD `unavailable`: a drifted rejection message under-reports, never over-claims. |

## Mechanism (why only the refusing consumer flakes)

A consumer that exits **before reading any stdin** lets the producer's `write()` land on a
closed read end → SIGPIPE 141 → pipefail makes it the pipeline rc. Two reachability shapes:

- `_generation_scoped_count` returns before its first read: non-numeric `$floor`, empty
  `$tag` (~line 1486 test), or the overridden `_current_instance_row_counts` stubs
  (~1475/1480) that print a canned line and never read. The function finishes in
  microseconds; a 1-line producer still EPIPEs if it loses the startup race.
- `X | head -1` (and equivalent early-exit consumers): `head` exits after its first line;
  a producer with a second pending `write()` EPIPEs under CPU contention. Small-output
  producers land their buffer first, so the window is microscopic but nonzero — the
  suite's own comments pin this class ("Herestring, not `grep -v | grep -q` … measured
  flaking 1 in 8 under load", lines 2845/3193).

Consumers that read all of stdin (`grep -c`, `sed -n '1p'`, `tail`, `awk` without `exit`,
`jq -s`, `cut`, `tr`, `wc`) can never trigger it — the suite's established drain-safe
idiom for "first line" is `sed -n '1p'`, and this plan converts the leftover `| head -1`
sites to it.

## Implementation Phases

### Phase 1 — cutover-inngest-workflow.test.sh: kill the refusing-consumer pipes

1. Convert the five `printf … | _generation_scoped_count` sites to here-strings
   (`<<<"$FIX_CUR_1_FLIP"`, `<<<"$FIX_CUR_1_LUKS"$'\n'"$FIX_CUR_2_LUKS"`,
   `<<<"$(fix_row …)"`), with a comment naming the mechanism (the function can return
   `__UNREADABLE__` before reading stdin; a producer then EPIPEs and `set -e` propagates
   the 141 out of `FILTER_OUT=$(…)`).
2. Convert the `X | head -1` sites to `X | sed -n '1p'` (same output, drains all input):
   lines ~341–342, ~373–379, ~606–607, ~1835–1836, ~2436, ~2671, ~4257, ~4341–4342,
   ~4461–4462, ~4476. For the `grep -B1 … | head -1 | sed 's/…//'` chains the trailing
   strip sed is preserved (or merged into `sed -n '1{s/…/;p}'`).

### Phase 2 — luks-monitor.sh:224: split the keyslot verdict from a test fault

```bash
_luks_open_err="$(printf '%s' "$key" | cryptsetup luksOpen --test-passphrase --key-file - "$real_dev" 2>&1 >/dev/null)" \
  && _luks_open_rc=0 || _luks_open_rc=$?
if [ "$_luks_open_rc" -eq 0 ]; then
  WL_LUKS_OPEN_RESULT=ok
elif [[ "$_luks_open_err" == *"No key available"* || "$_luks_open_err" == *"No usable keyslot"* ]]; then
  WL_LUKS_OPEN_RESULT=fail; emit_and_die escrow_passphrase_mismatch
else
  log "escrow check failed (cryptsetup rc=$_luks_open_rc): ${_luks_open_err:0:160}"
  WL_LUKS_OPEN_RESULT=fail; emit_and_die escrow_check_failed
fi
```

- The `printf |` producer STAYS: a `<<<"$key"` here-string is implemented via a tempfile
  under TMPDIR by bash, which writes the live passphrase to a (briefly) filesystem-backed
  object — a posture regression this credential-handling file (which refuses xtrace) does
  not take. With stderr captured, a producer SIGPIPE arrives with empty stderr →
  `escrow_check_failed`, so the pipe is no longer a fake-mismatch vector.
- `escrow_check_failed` joins `is_probe_integrity` in
  `.github/workflows/workspaces-luks-verify.yml` (the "could not read its own inputs"
  class → `unavailable`, still alarms, never the legal claim) and gets a triage-table row
  in `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
  beside `cryptsetup_status_missing`.

### Phase 3 — luks-monitor suite: stub knob + failure-split rows + latent sweeps

1. `workspaces-luks-harness.sh`: `mon_prepare`'s `bin/cryptsetup` `luksOpen` arm emits
   `${MON_ESCROW_ERR}` on stderr when set (documented knob beside `MON_ESCROW_RC`); the
   existing stdin drain is untouched. `idx()` becomes `grep -m1 -nE … | cut -d: -f1`
   (removes its `| head -1` early-exit consumer for every suite sharing the harness).
2. `luks-monitor.test.sh`: three new behavioural rows after (t1b) —
   `MON_ESCROW_RC=1 MON_ESCROW_ERR='No key available with this passphrase.'` →
   `escrow_passphrase_mismatch`; `MON_ESCROW_RC=1 MON_ESCROW_ERR='Device … failed'` →
   `escrow_check_failed`; `MON_ESCROW_RC=141` with no stderr (the producer-SIGPIPE shape) →
   `escrow_check_failed`. `EXPECTED_PASSES` 155→158, `LUKS_MONITOR_MIN_PASS` 89→92.
   `kc_key_cfg`/`kc_hb_cfg` become `grep -m1 -E … | sed -n 's/.*--config //p'`.

## Sweep dispositions (same suites + shared harness/SUT, all checked)

| Site | Verdict |
|---|---|
| `luks-monitor.sh:180` `cryptsetup status | sed -n 's/…//p' | head -1` | Left as-is: real and stub `cryptsetup status` emit exactly one `device:` line, so `sed` never has a second write pending — `head -1` cannot EPIPE it. Value and rc are also discarded-safely (assignment, no `set -e`). |
| `luks-monitor.sh:43` `tr | tr | head -c 36` | Left as-is: byte-count consumer inside `$( … || true)`; `|| true` swallows the 141 and the first 36 bytes are deterministic. |
| `luks-monitor.sh:456` `curl --config - < <(printf 'url = "…"')` | Safe: process-substitution, not a checked pipeline; the reader's `break` follows a successful read, so the write already landed. |
| `luks-monitor.test.sh` `printf | grep -cE` (:136–140, :553) | `grep -c` reads all input — drains. |
| `workspaces-luks-emit.sh` `printf | tr`, `printf | sed -E`, `df | awk` | All drain. |
| `scripts/cutover-inngest.sh:794,820` `printf '%s\n' "$rows" | _generation_scoped_count` | Left as-is: `$floor` is validated numeric one statement earlier and `$tag` is a literal, so the early-refuse arms are unreachable and `_current_instance_row_counts`/`jq -s` always drains. (Changing them would also re-anchor the `GSC_CALLS` parity grep for no behavioural gain.) |
| cutover suite `| grep -q` / `| grep -qE` | None piped — the suite already here-strings or file-greps them (lines 2845, 3193 comments). |
| `idx()` in the harness | Fixed (`grep -m1`) — shared by other suites, same class. |

## Observability

- The fix is self-observing at the failure site: `escrow_check_failed` carries cryptsetup's
  rc and the first 160 bytes of its stderr into the `FAIL (reason)` journald line the
  verify workflow parses (layer: journald → Vector → Better Stack + the workflow's
  reason-first classifier). A SIGPIPE'd producer still prints `printf: write error` into
  `MON_OUT`/journald beside the new reason.
- `is_probe_integrity` membership is enforced by the (M) parity gate in
  `workspaces-luks-verify-workflow.test.sh`; the runbook row is enforced by the (N)
  triage-table gate. Both red loudly if the new reason is unregistered.

## Guard Contract

### Guard 1 — the escrow failure split never files the wrong verdict class

**Property:** a non-zero escrow test reports `escrow_passphrase_mismatch` only when
cryptsetup's stderr proves a keyslot verdict ran; every other failure reports
`escrow_check_failed`.

**Assembly:** the three `elif` arms at luks-monitor.sh:~224, the harness stub's
`MON_ESCROW_ERR`/`MON_ESCROW_RC` knobs, and the workflow classifier membership.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expected |
|---|--------------------------------------|----------|
| 1 | `MON_ESCROW_RC=1` + `MON_ESCROW_ERR='No key available with this passphrase.'` | `escrow_passphrase_mismatch` (mismatch arm still reachable) |
| 2 | `MON_ESCROW_RC=1` + non-keyslot stderr | `escrow_check_failed` (real-cause arm) |
| 3 | `MON_ESCROW_RC=141` + empty stderr | `escrow_check_failed` (the SIGPIPE shape, deterministically) |

### Guard 2 — no refusing consumer is fed by a pipe in the cutover suite

**Property:** every `_generation_scoped_count` feed in the test takes stdin from a
here-string/file, never a `printf |` producer.

**Assembly:** the five feed sites in the generation-scope block.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expected |
|---|--------------------------------------|----------|
| 1 | revert ~1486 (empty-tag) to `printf … \|` | producer can EPIPE into a consumer that returns before reading — shape eliminated by construction |
| 2 | revert ~1475 (never-reading `_current_instance_row_counts` override) to `printf … \|` | same refusal class |
| 3 | sweep grep `'\| _generation_scoped_count'` over the suite | zero hits after the change |

## Acceptance Criteria

- [ ] `bash apps/web-platform/infra/luks-monitor.test.sh` green with `EXPECTED_PASSES=158` and the three new rows.
- [ ] `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` green; zero `| _generation_scoped_count` and zero `| head -1` sites remain in the suite.
- [ ] `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` green (the (M)/(N) parity + runbook gates cover the new reason).
- [ ] `bash scripts/test-all.sh --print-selection` — no registration changes needed (no new suites).
- [ ] `python3 scripts/lint-guard-contract.py` green for this plan.

## Out of Scope

- The two production `printf | _generation_scoped_count` sites in `scripts/cutover-inngest.sh`
  (dispositioned above — no reachable refusal).
- `workspaces-cutover.sh:2666`'s identical escrow shape (different suite, different emit
  channel; the same split may deserve a follow-up if reviewers judge it in scope).
- Other suites' `| head -1` sites outside the two named suites + shared harness.
