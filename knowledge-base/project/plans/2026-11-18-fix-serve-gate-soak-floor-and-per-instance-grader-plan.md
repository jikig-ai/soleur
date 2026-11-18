---
title: "fix(infra): serve gate soak floor of 3 days and the ADR-263 per-instance soak grader"
type: fix
date: 2026-11-18
slug: fix-serve-gate-soak-floor-and-per-instance-grader
branch: feat-one-shot-12849-serve-gate-soak-floor
issue: 12849
closes: 12849
refs: [12008, 9421]
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(infra): serve gate soak floor of 3 days and the ADR-263 per-instance soak grader

> Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-18 (after the 5-agent plan review and the CTO rulings G1-G13).
**Sections enhanced:** Proposed Solution Parts 1-4, Technical Considerations, Attack Surface, Observability,
Guard Contract, Implementation Phases 1 and 5, Files to Create/Edit, Acceptance Criteria, Test Scenarios,
Dependencies & Risks, Sharp Edges.
**Review agents used:** terraform-architect, infra-security, observability-coverage-reviewer, a
verify-the-negative / post-edit self-audit pass, plus the plan-review panel (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer), a sharp-edges pass, and the CTO for every technical fork.

### Key Improvements

1. **A pre-existing floor bypass is closed (G1).** An unbounded soak value wraps in bash arithmetic
   (`200000000000000 * 86400` is negative), so today's gate passes it at once. The knob is now capped at three
   digits.
2. **The step logic moves into a sourced, executed helper (G2-G4).** `scripts/lib/serve-soak-evidence.sh` holds
   the one copy of the grammar, the mirror, the anti-vacuity re-check of each pass line's numbers (G8), the
   grader rc mapping and the host check. Evidence emission moves into the gate's existing `fail()` (G3).
3. **The grader runs without the job's Hetzner and Doppler credentials (G10).** It runs under `env -i` with only
   its three Better Stack read credentials; a decoy row proves it.
4. **Fail-closed wiring that does not depend on the helper alone.** An inline `gate_rc` backstop, a guarded
   helper load with a named `::error::`, explicit `|| return 1` inside the helper, an EXIT/TERM trap in both
   steps, `EV_KIND` initialised before any refusal under `set -u`, and `SOLEUR_GATED_HOST` bound at step level.
5. **Discoverable without SSH.** A committed read-only probe (`scripts/serve-soak-evidence-last.sh`, G11) that
   handles `gh run view --log`'s line prefix and reports the run's branch and SHA; every failure mode names its
   layer; every refusal has a runbook action.

### New Considerations Discovered

- A web-2 instance older than 90 days can never pass the grader (90-day readiness lookback); kept fail-closed,
  remedy is a replace (G12, #12938).
- A replaced web-2 keeps the pool weight it found and can serve without the serve arm; recorded residual (G13,
  #12939). Ruled by CTO agent, 2026-11-18: the fix ships with #12869, not here.
- `g3_dbin_ok` in `workspaces-luks-verify-workflow.test.sh` pins the gate step's exact wrapper hand-off, so the
  stderr redirect must follow the wrapper path and no new code line may name the wrapper file or `DOPPLER_BIN`.
- The grader's `$GRADE` text is printed only when it matches a fixed shape (workflow-command injection).

## Overview

The web-2 serve gate (`apps/web-platform/infra/lb-weight-gate.sh`, reached only through
`lb-weight-gate-with-marker.sh` from the `ga-pool-update` serve arm of `.github/workflows/cf-lb-overlay.yml`)
takes its soak length from the environment, so a `prd` value of 1 shortened the 3-day LUKS soak on
2026-11-18 without review. The serve arm also never runs the per-instance soak grader that ADR-263's
2026-10-08 addendum requires. This plan implements the CTO ruling of 2026-11-18 on #12849 (the binding
design): a code floor of 3 days that values may only lengthen, the existing #6931 grader as a hard
precondition before plan, and structured evidence lines on stderr and in the step summary.

One PR. `Closes #12849`, `Ref #12008`, `Ref #9421` (never `Closes` for those two). It must merge before
#12869 (web-3 and per-host serve gate).

## Problem Statement / Motivation

Root cause, established 2026-11-18 from the run log and gate code (no secret read):

- `cf-lb-overlay.yml` run 44304068922, step `§(c) gate chain`, ran at 2026-11-18T12:43:37Z.
- The marker `WORKSPACES_LUKS_CUTOVER_AT=2026-11-17T12:18:54Z` was 87,883 s old at gate time.
- The workspaces soak check (`lb-weight-gate.sh`, `[[ "$ws_delta" -ge $(( WS_SOAK_DAYS * 86400 )) ]]`) passes
  only when the age is at least `WORKSPACES_LUKS_SOAK_DAYS` x 86,400. Since 86,400 <= 87,883 < 172,800, the
  only value that passes is 1: the effective value came from `prd`, not the default of 3.
- The gate printed only `requires_runtime_bind_probe=true` and the SHAPE-ONLY banner. It never printed the
  effective soak days, their source or the marker age, so the early pass was visible only by arithmetic.

Three gaps follow:

1. **The soak can be shortened without review.** B.2 and the workspaces days check accept any positive
   integer (`[[ "$SOAK_DAYS" -gt 0 ]]`, `[[ "$WS_SOAK_DAYS" -gt 0 ]]`).
2. **No per-instance soak in the serve arm.** ADR-263 (2026-10-08 addendum): "marker age must never stand in
   for the new instance's soak", and "The flip orchestrator (#9358) must require the grader's PASS". The serve
   arm has no grader call, so a marker inherited across a rebirth lets a reborn host serve with no new soak.
3. **No telemetry.** The gate never self-reports the soak it enforced.

A fourth defect surfaced in the CTO review (F10): `010` passes `^[0-9]+$` and `-gt 0`, and bash reads it as
octal 8, so a configured 10-day soak is enforced as 8 days.

## Proposed Solution

All decisions below are recorded in
`knowledge-base/project/specs/feat-one-shot-12849-serve-gate-soak-floor/decision-challenges.md`
(D1-D5 are the 2026-11-18 ruling; F1-F11 are the derived forks, also Ruled by CTO agent, 2026-11-18).

### Part 1 — `lb-weight-gate.sh`: the floor and the evidence line

- Add `SOAK_FLOOR_DAYS=3` near the top, assigned in plain `NAME=` form. **Never** `${SOAK_FLOOR_DAYS:=3}`:
  `gate_read_vars` in `lb-weight-gate-with-marker.test.sh` subtracts only `NAME=`/`NAME+=`/`readonly`/`local`
  assignments, so a `:=` form would make the name a gate *input*, move the derived allowlist from 11 to 12
  names, and redden `scn_allow_parity`.
- B.2 (git data) and B.6 (workspaces), in this order per knob (keeps today's sub_condition precedence, F1):
  1. `SOAK_DAYS="${GIT_DATA_LUKS_SOAK_DAYS:-$SOAK_FLOOR_DAYS}"` (same for `WS_SOAK_DAYS` /
     `WORKSPACES_LUKS_SOAK_DAYS`). Empty and unset both mean the default (`:-` semantics, unchanged).
  2. `[[ "$X" =~ ^[1-9][0-9]{0,2}$ ]] || fail "<kind>_soak_days_invalid"`. F10 removes leading zeros; G1 caps the
     value at three digits (at most 999 days). **G1 fixes a bypass that exists today:** an unbounded value wraps
     in bash arithmetic. `200000000000000` makes `$(( X * 86400 ))` negative, so the age check passes at once,
     and `18446744073709551619` is read as 3. `999 * 86400` cannot overflow. Running the regex first also keeps
     arithmetic injection out of the later `[[ $X -ge ... ]]` tests.
  3. The existing `[[ "$X" -gt 0 ]] || fail "<kind>_soak_days_invalid"` stays (D1 keeps the `*_invalid`
     checks). It is unreachable after step 2, carries the comment "unreachable after the regex; kept for D1",
     and no mutation targets it.
  4. New: `[[ "$X" -ge "$SOAK_FLOOR_DAYS" ]] || fail "<kind>_soak_days_below_floor"`, with ids
     `B_luks_soak_days_below_floor` (git data) and `B_workspaces_luks_soak_days_below_floor`. It runs AFTER
     the invalid checks, so `0` keeps refusing as `*_invalid` (tests at `assert_rejects_with
     "GIT_DATA_LUKS_SOAK_DAYS=0 (floor)"` and its workspaces twin pin that).
- Evidence line (D3, F1, F2; emission per G3). A small record (`EV_KIND EV_DAYS EV_SRC EV_MARKER EV_AGE EV_REQ`),
  every field assigned in `NAME=` form so `scn_allow_parity` stays unchanged. `EV_KIND=` (empty) is initialised
  above `fail()`, before any refusal, in plain `NAME=` form (never `${EV_KIND-}`): the gate runs under `set -u`,
  so a `fail()` that reads an unassigned `EV_KIND` on a TOP_/Condition A/B.1 refusal would abort before printing
  `gate_fail sub_condition=` (self-audit A1; a by-hand mutation deleting the init must redden the
  `TOP_gated_host_absent` row). `EV_KIND=git_data` and the other
  fields `none` at B.2 entry; after the B.5 pass emit, `EV_KIND=workspaces_luks` and the fields reset at B.6
  entry; after the B.10 pass emit, `EV_KIND=`. The fields fill as each value is computed:
  - `soak_days`: the value when it matched `^[1-9][0-9]{0,2}$`, else `invalid`. A raw non-matching value is
    never printed.
  - `source`: `env` when the knob is set and non-empty, else `default`.
  - `floor_days`: `${SOAK_FLOOR_DAYS}`.
  - `marker_at`: `none` until the marker is parsed (absent, or not yet reached, e.g. on
    `B_workspaces_luks_marker_other_host`); `unparseable` when the ISO shape or `date -d` fails; after the parse,
    the value rebuilt from the epoch, `date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ`, never the raw text.
  - `age_s`: the delta (may be negative on the `*_future` refusal), else `none`.
  - `required_s`: `days * 86400` once the days value has passed the invalid AND floor checks, else `none`.
  - `verdict`/`sub_condition`: `fail` + the refusing id, or `pass` + `none`.
  - `host`: `${HOST}` (already validated by `TOP_gated_host_malformed`). The gate must not name a host
    literal: the suite forbids `web-[0-9]` on any gate code line.
- **Emission lives in the existing `fail()` (G3, Ruled by CTO agent, 2026-11-18; amends F1's mechanism, not its
  outcome).** `fail()` prints the evidence line (verdict=fail) first, only when `EV_KIND` is non-empty, then
  `gate_fail sub_condition=<id>`. Every refusal inside B.2-B.10 is covered by construction; B.1
  (`B_git_data_store_disabled`), Condition A and the weight-0 standby branch run with `EV_KIND` empty and emit
  nothing. No `soak_fail` helper, no static no-bare-`fail` rule. The behaviour row "every refusal id in B.2-B.10
  yields exactly one line of its kind" carries the coverage.
- The gate header records `^gate_fail sub_condition=` as the only refusal contract; the evidence line is
  non-authoritative. A comment at the emit site names the helper's `SOAK_EV_RE` as the grammar (one copy, G4).
- The grammar, one line, space-separated, anchored (its one copy is `SOAK_EV_RE` in the new helper, G4):

  ```text
  ^SOLEUR_SOAK_EVIDENCE kind=(workspaces_luks|git_data) host=[a-z][a-z0-9-]{0,30} soak_days=([1-9][0-9]{0,2}|invalid) source=(default|env) floor_days=[1-9][0-9]{0,2} marker_at=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|none|unparseable) age_s=(-?[0-9]+|none) required_s=([1-9][0-9]*|none) verdict=(pass|fail) sub_condition=(B_[a-z_]+|none)$
  ```

- Update the header comment (Condition B paragraph and B.2/B.6 comments): the floor, the 999-day cap, "values
  may only lengthen", the evidence line, and why a `prd` value cannot shorten the soak.

### Part 2 — new helper `scripts/lib/serve-soak-evidence.sh` (G2)

Ruled by CTO agent, 2026-11-18 (G2): the step logic lives in one checked-in, sourced file, so the suite executes
the file instead of sed-extracting step bodies. Precedent: the relay step sources `scripts/lib/web2-relay-rows.sh`.
The helper contains no `lb-weight-gate.sh` literal in code (the wrapper census) and never mentions the soak
marker's Doppler name.

- `readonly SOAK_EV_RE='<the grammar above, without ^ and $>'` and
  `readonly INSTANCE_EV_RE='SOLEUR_INSTANCE_SOAK host=([a-z][a-z0-9-]{0,30}|invalid) grader=[a-z0-9-]+ rc=([0-9]+|none) verdict=(PASS|FAIL|NOT_YET|CANNOT_ESTABLISH)'`
  (architecture 6: the grader value is pinned by a wiring row, not the grammar; G7: `host=invalid`). A comment
  says the gate's `fail()` and pass emit are the producer of `SOAK_EV_RE`.
- `readonly SOAK_FLOOR_S=259200` (G8). The F8 parity row also pins it equal to the gate's
  `SOAK_FLOOR_DAYS * 86400` and the grader's `SOAK_DAYS * 86400`.
- **Error handling inside the helper.** Every guarded command carries an explicit `|| return 1`; the helper
  never relies on `set -e` inside its functions, because bash turns errexit off in a function called as
  `fn || ...` or `if fn` (observability 6).
- `sse_gate_chain_check <stderr-file> <gated-host> <rc>`: called by the gate chain step after the wrapper ran
  (F6, CTO plan-review findings 1-5):
  1. Write to `$GITHUB_STEP_SUMMARY` a `### §(c) gate chain soak evidence` heading, a ```` ```text ```` fence, the
     lines that fully match `^${SOAK_EV_RE}$`, and a closing fence (G9; the grammar has no backtick, so a line
     cannot break out of the fence). Zero matches is normal (Condition A, B.1, standby, wrapper pre-exec
     refusals): `grep -E ... "$f" >>"$GITHUB_STEP_SUMMARY" || [[ $? -eq 1 ]]` (rc 2 still fails).
  2. Non-zero rc: `::error::` naming the refusing id, read from the anchored `^gate_fail sub_condition=([A-Za-z0-9_]+)$`
     line (`none` when absent), repeated in the summary heading (AC17). For `*_soak_days_below_floor` it adds:
     "a configured soak value is below the 3-day floor; delete it from Doppler prd (#12933, Operator-authorizes) -
     the floor cannot be shortened, values may only lengthen it". It also appends `per-instance soak grader: NOT RUN
     (gate refused)` to the summary (spec-flow 5). Return 1.
  3. Pass (rc 0), after the step's existing `requires_runtime_bind_probe=true` check: for each kind, exactly one
     line matching the grammar with `kind=<k> host=<gated-host> ... verdict=pass sub_condition=none`
     (architecture 4), AND (G8) an ISO `marker_at`, integer `age_s` and `required_s`, `required_s >= SOAK_FLOOR_S`,
     `age_s >= required_s`. Counts use `n="$(grep -cE ... "$f" || true)"`; no pipeline inside `$( )`. Otherwise
     `::error::§(c) gate chain: gate passed but soak evidence for kind=<k> is missing or malformed - a code
     defect, not a soak wait; do not re-dispatch`, return 1.
- `sse_instance_soak <gated-host> <grader-path>`: called by the grader step (D2, F3, F5, G7):
  1. Refuse xtrace (`case "$-" in *x*) ... return 78`), as the relay step does. Then arm an EXIT/TERM trap that,
     unless a verdict line was already printed, prints and mirrors
     `SOLEUR_INSTANCE_SOAK host=<host> grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH`, so a cancel
     or timeout while `$GRADE` is buffering still leaves a verdict line (observability 3).
  2. Host check (`# until #12869`): a value other than `web-2` prints
     `SOLEUR_INSTANCE_SOAK host=<value|invalid> grader=web2-luks-live-6931 rc=none verdict=CANNOT_ESTABLISH`
     (`host=invalid` when the value does not match `^[a-z][a-z0-9-]{0,30}$`), mirrors it, `::error::` (the grader
     reads only web-2's rows; `W2L_HOST_NAME="soleur-web-2"` is hardwired in `scripts/lib/web2-luks-rows.sh`),
     returns 1 and never calls the grader.
  3. `rc=0; GRADE="$(env -i PATH="$PATH" HOME="$HOME" TMPDIR="${RUNNER_TEMP:-/tmp}" BETTERSTACK_QUERY_HOST="$BETTERSTACK_QUERY_HOST" BETTERSTACK_QUERY_USERNAME="$BETTERSTACK_QUERY_USERNAME" BETTERSTACK_QUERY_PASSWORD="$BETTERSTACK_QUERY_PASSWORD" SOLEUR_FT_EARLIEST= bash "$grader")" || rc=$?`.
     G10 (Ruled by CTO agent, 2026-11-18): the job's `Load infra credentials (tiered)` step writes `HCLOUD_TOKEN`
     and `TF_VAR_github_app_runtime_doppler_token` to `$GITHUB_ENV` before the gate chain, so the grader step
     inherits them; `env -i` hands the grader only the names it reads. The Better Stack password sits briefly in
     `env`'s argv (`/proc/<pid>/cmdline`) until `env` execs `bash`; accepted, as the existing gate step does the same
     with `env DOPPLER_TOKEN=...` and the value is masked in logs (infra-security 5). The empty `SOLEUR_FT_EARLIEST` means "no
     clock", so an unmet soak reads NOT YET, never a window FAIL.
  4. Map: 0 PASS, 1 FAIL, 2 NOT_YET, 3 CANNOT_ESTABLISH, anything else CANNOT_ESTABLISH with the real rc (F3).
  5. Print `SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=<n> verdict=<V>` on stderr, the grader's
     own text (`$GRADE`) to the log only when it matches `^(PASS|FAIL|NOT YET|CANNOT ESTABLISH): [^\r]*$` and does
     not start with `::` (else `grade_text=unprintable`): the grader is shared with the sweeper and may change, and
     GitHub reads workflow commands on stdout and stderr (infra-security 3), and `### per-instance soak grader (serve only)` plus a fenced copy of the line
     to the summary (G9). `rc=0` if and only if `verdict=PASS`.
  6. Non-zero rc: `::error::` naming the verdict, "NOTHING planned, NOTHING applied", and the next step for that
     verdict (spec-flow 4, G12): before the `::error::`, the helper prints the grader's first line (`$GRADE`
     head -1, filtered as in step 5) to the step log, not the summary. NOT_YET - "NOT_YET: read the grader line
     above; if it says no GREEN web-2 readiness row and web-2 was created more than 90 days ago, replace the host
     (web-host-replace.md) and wait for the 3-day soak; otherwise wait or check web-2 probe telemetry" (G12,
     Ruled by CTO agent, 2026-11-18: the grader's readiness lookback is 90 days, `W2L_READY_LOOKBACK_D=90` in
     `scripts/lib/web2-luks-rows.sh`, and the row is written once per instance, so an instance older than 90 days
     stays fail-closed and must be replaced to re-serve; no grader or lib change; follow-up #12938); FAIL - "the soak of this
     instance is spoiled; investigate, a replace is the repair"; CANNOT_ESTABLISH with rc 3 - "Better Stack
     credentials or the shared helper are missing"; any other rc or `none` - "a code or wiring defect; do not
     re-dispatch". Return 1.

### Part 3 — `cf-lb-overlay.yml`, `ga_pool_update` job

**3a. The `§(c) gate chain` step.**

- Keep the inner `env` names exactly as `p_guard` pins them (`DOPPLER_BIN, DOPPLER_TOKEN, SOLEUR_GATED_HOST,
  SOLEUR_SERVING_ROTATION, SOLEUR_WEB2_SERVING_WEIGHT`). No soak pin (D1); `p_guard` already reddens on one.
- Before the wrapper runs: `gate_rc=0`, `: >"${RUNNER_TEMP}/lb-gate.stderr"` (the file exists even when Doppler
  fails first), and `trap 'cat "${RUNNER_TEMP}/lb-gate.stderr" >&2' EXIT` so the captured lines reach the log on
  every exit path, including a refusal, a timeout or a cancel (spec-flow 1 and 7).
- The first line keeps starting `GATE_OUT="$(env DOPPLER_TOKEN=` (the C.4-P1m6 mutant still lands). The wrapper's
  stderr is redirected to the file inside the `$( )`, and the rc is captured with `|| gate_rc=$?` (not `|| true`).
  Doppler's own stderr lands in the file too; it is replayed, never mirrored.
- Add a step-level `env: SOLEUR_GATED_HOST: web-2` so the helper call can read the gated host (today the step's
  `env:` holds only `DOPPLER_TOKEN_PRD` and `DOPPLER_TOKEN_LUKS_MARKER`, and `$SOLEUR_GATED_HOST` would be unbound
  under `set -u`; self-audit A2). The inner `env` line keeps its literal `SOLEUR_GATED_HOST="web-2"` unchanged:
  `g3_dbin_ok` in `workspaces-luks-verify-workflow.test.sh` strips exactly that token before pinning the wrapper
  hand-off. The host-literal parity row reads both the step `env:` value and the inner literal.
- Source the helper with the grader's own load pattern (`# shellcheck source=scripts/lib/serve-soak-evidence.sh`;
  `source "$f" && declare -F sse_gate_chain_check >/dev/null || { echo "::error::serve-soak-evidence helper not
  loaded ($f) - wiring defect, do not re-dispatch"; exit 1; }`; a wiring row pins it; observability 5) and call
  `sse_gate_chain_check "${RUNNER_TEMP}/lb-gate.stderr" "$SOLEUR_GATED_HOST" "$gate_rc"` as a bare statement
  (never inside `if`, `||` or `&&`, which would switch errexit off for it; a wiring row pins that). Directly after
  it, an inline backstop `[[ "$gate_rc" -eq 0 ]] || exit 1`, so a refusal fails the step even if the helper
  returned 0 by mistake (an executed row: rc 1 returns 1; a wiring row: the backstop line follows the call).
  Order on a pass: the call's mirror half, then the existing `requires_runtime_bind_probe=true` check on
  `GATE_OUT`, then the helper's pass re-check (split into `sse_gate_chain_mirror` and `sse_gate_chain_verify`
  if one call cannot sit on both sides of the existing check). On a refusal the existing check is never reached
  (terraform-architect 2).

**3b. New step `per-instance soak grader (serve only)` (D2, F4, F5).**

- Placement: immediately after `§(c) gate chain`, before `web-2 health precondition` (it needs no Terraform
  state). Keys exactly `name`, `if`, `env`, `run`; `if: inputs.mode == 'serve'`; no `shell:`,
  `continue-on-error`, `|| true` or `set +e`.
- `env:` exactly: `SOLEUR_GATED_HOST: web-2` and the three `BETTERSTACK_QUERY_HOST|USERNAME|PASSWORD:
  ${{ secrets.BETTERSTACK_QUERY_* }}` lines (the same secrets the job's `relay bind probe` step binds). No
  `secrets.` expression in the run body.
- Run body: `set -euo pipefail`, source the helper with the same guarded load pattern (checking
  `declare -F sse_instance_soak`), call
  `sse_instance_soak "$SOLEUR_GATED_HOST" "${GITHUB_WORKSPACE}/scripts/followthroughs/web2-luks-live-6931.sh"`.
- Update the job's header comment (lines above `environment: web-platform-infra-apply`) to name the grader.

### Part 4 — supporting edits

- `scripts/followthroughs/web2-luks-live-6931.sh`: the comment above `SOAK_DAYS=3` says "the same soak the
  traffic-weight gate defaults to (lb-weight-gate.sh WS_SOAK_DAYS)"; repoint it at `SOAK_FLOOR_DAYS` and the
  parity test (F8). Do not touch the `SOAK_DAYS=3` line itself: `web2-luks-live-6931.test.sh` mutants anchor on
  it (`mutant "soak shortened to 0 days ..." probe 'SOAK_DAYS=3' 'SOAK_DAYS=0'` and the `sed 's/^SOAK_DAYS=3$/'`
  row).
- `.github/workflows/infra-validation.yml`: add `scripts/followthroughs/web2-luks-live-6931.sh`,
  `scripts/lib/serve-soak-evidence.sh` and `scripts/serve-soak-evidence-last.sh` to the `pull_request:` paths list only, next to the
  `scripts/lib/web2-relay-rows.sh` entry, with a `#12849` comment (F9, G2). Consumers: the parity row (the only
  suite row that reads the real grader file; the executed rows use a stub, sharp-edges 10) and the helper's
  executed rows.
- ADR-263: new addendum + one supersession blockquote (see `## Architecture Decision (ADR/C4)`); ADR-068 pointer.
- `model.c4` line ~979 (`github -> betterstack` description) + regenerate `model.likec4.json`.
- Runbooks: `cf-lb-a-record-gaplessness-verify.md` (`### Before dispatching mode=serve ...`) and
  `web-host-replace.md` (the paragraph ending "`mode=serve` then refuses with `B_workspaces_luks_so...`").

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality | Plan response |
|---|---|---|
| Issue "Needed" bullet 1: pin both soak days in the serve step's inner env | Superseded by the CTO ruling ("No pin in the workflow"); `p_guard` pins the inner env names exactly | No pin; a suite row proves a pin reddens `p_guard` |
| "lb-weight-gate-with-marker.sh only prints stdout on pass" | The wrapper `exec`s the gate, so the gate's stderr reaches the step's stderr directly; the step captures only stdout into `GATE_OUT` | The step captures stderr to a file and replays it (trap on EXIT), so the summary can be written |
| Existing `assert_stderr_contains` checks `*"sub_condition=$2"*` | The new evidence line also carries `sub_condition=<id>`, so a substring check can be satisfied by the evidence line alone | Anchor all 7 substring sites (2 in `lb-weight-gate.test.sh`: `assert_stderr_contains`, `a1_row_ok`; 5 in `lb-weight-gate-with-marker.test.sh`) on the whole `gate_fail sub_condition=<id>` line, plus a census row that reddens on any remaining `*"sub_condition=` substring check |
| Grader is "the same soak the gate defaults to" (grader comment) | After this PR the gate has a floor, not just a default | Comment repointed; parity test added |
| C4 `github -> betterstack` says the grader verdict is "advisory evidence" | After this PR the serve arm refuses unless the grader returns 0 | Edit the description (a veto, never an authorization) |
| `^[1-9][0-9]*$` (F10) bounds the soak below | It has no upper bound; a 15-digit value wraps negative in `$(( X * 86400 ))` and passes at once (reproduced 2026-11-18; the bypass exists in today's gate) | G1: cap at 3 digits, longer refuses `*_invalid` |
| Grader step "binds only the three Better Stack credentials" | Steps inherit every earlier `$GITHUB_ENV` write in the job | G10: the helper runs the grader under `env -i` with only its read credentials; decoy row |

## Technical Considerations

- **Allowlist derivation.** No new environment name is read by the gate. `SOAK_FLOOR_DAYS` and the `EV_*`
  record are assigned in `NAME=` form. `scn_allow_parity` must stay unchanged from the base (11 names today).
- **Collision with PR #12918** (open draft, `feat-one-shot-12910-host-roster-lease-id`): it edits Condition A of
  the same gate and `GATE_ENV_ALLOW` (adds `SOLEUR_WEB_HOSTS`) plus both gate suites. The hunks do not overlap
  (Condition A vs Condition B), so the second PR to merge rebases; the wrapper's allowlist count becomes 12
  there, not here. Fixture helpers that build the gate env (`reset_def`) may need the `SOLEUR_WEB_HOSTS` value
  after that rebase.
- **Live `prd` override.** `WORKSPACES_LUKS_SOAK_DAYS=1` is still in Doppler `prd` (owner decision recorded
  on #12849, 2026-11-18). After this merges, every serve refuses with
  `B_workspaces_luks_soak_days_below_floor` until #12933 removes it. That is the intended effect of D1 and is an
  Operator-authorizes hold, not part of this PR.
- **#12820 timing.** web-2's marker was written 2026-11-17T12:18:54Z, so its 3-day age is met from
  2026-11-20T12:18:54Z; the grader additionally needs green probe rows on 3 distinct days after the newest
  readiness row. A serve after this merge needs both, plus #12933.
- **Security.** The job holds Hetzner (`HCLOUD_TOKEN`) and Doppler-runtime
  (`TF_VAR_github_app_runtime_doppler_token`) credentials from its `Load infra credentials (tiered)` step, written
  to `$GITHUB_ENV` before the gate chain, and the grader step inherits them. The helper runs the grader under
  `env -i` with only `PATH`, `HOME`, `TMPDIR`, the three Better Stack read credentials (the same secrets the relay
  step binds) and an empty `SOLEUR_FT_EARLIEST` (G10); an executed row plants decoys and proves the grader sees
  none. The grader itself refuses xtrace with a live credential (exit 78) and the helper refuses xtrace first. Evidence lines carry a host key, integers and epoch-rebuilt timestamps only; no raw Doppler
  text reaches the log or the summary (F2). No new secret, no new network edge.
- **GDPR gate (plan Phase 2.7, trigger (b) single-user threshold), 2026-11-18:** no findings. No Files-to-Edit
  path matches the canonical regulated-data regex; no schema, PII table, `users` FK or new vendor; the evidence
  lines carry a host key, integers and epoch-rebuilt timestamps only. Advisory, not legal review.
- **NFR.** Availability of web-2 serving drops by design (the serve arm refuses more often); integrity of the
  pooling decision rises. No runtime cost on any host.
- **Out of scope:** sending the lines to Better Stack (#12936); per-host marker keying and grader (#12869);
  deleting the `prd` override (#12933); any emergency path that would let a host serve before its soak ends (a
  new reviewed change, never a config value — CPO concern 2).

### Attack Surface Enumeration

Every way the soak decision can be shortened or skipped on the serve path, and what covers it:

| Path | Covered by |
|---|---|
| A `prd` value of 1 or 2 for either knob | Floor check (Part 1) |
| A huge value that wraps in bash arithmetic (`200000000000000`, `18446744073709551619`) | G1 three-digit cap |
| A leading-zero value read as octal (`010`) | F10 regex |
| A value that forges a field (`1 verdict=pass`) | `invalid` refusal + `soak_days=invalid` in the line (F2) |
| A marker inherited across a rebirth (age already met) | Partially: grader step (Parts 2-3). Residual (AP-027, no run anchor): if a replacement's readiness row is lost, the predecessor's row still looks newest and the grader can PASS on the old instance. Recorded in the ADR-263 addendum; a generation anchor is a #12869 requirement |
| A grader that cannot read Better Stack | rc 2/3 refuse |
| A grader killed or missing (127/126/signal) | F3 |
| A gate that stops emitting a kind and still passes | Anti-vacuity check (Part 2), with the G8 re-check of each pass line's numbers |
| The step skipped (`if:` loosened, moved after plan, `continue-on-error`) | Wiring rows (Guard 3) |
| A workflow-side pin that hides a stray value | `p_guard` |
| A second host keyed onto web-2's grader | F5 host refusal |
| The grader (network calls) inheriting the job's Hetzner and Doppler-runtime credentials | G10 `env -i` allowlist + decoy row |
| A replaced instance serves at the weight the replace found (`web2_lb_weight` defaults to 1; the replace job's `-target` set omits the pool) | Not covered here (predates this PR). Runbook drain-first step at `web-host-replace.md:245`; follow-up #12939 (drain on replace, or a replace pre-gate); G13 |
| A web-2 instance older than 90 days | Fail-closed by design: grader NOT_YET, remedy is a replace (G12; #12938) |
| A planted marker value in shared `prd` | Not covered (recorded residual in ADR-263: provenance is not asserted) |

## User-Brand Impact

- **If this lands broken, the user experiences:** (permissive) a reborn web host whose `/workspaces` LUKS
  volume and soak are unproven is put into the load-balancer pool, and a user routed to it finds their
  workspace missing (the ADR-143 "workspace-gone" incident); (restrictive) web-2 never re-enters serving,
  web-1 serves alone with no failover, and users see nothing until web-1 fails.
- **If this leaks, the user's data is exposed via:** no user data crosses this change. The only credential
  surface the grader can reach is the three Better Stack read credentials (the job's Hetzner and Doppler-runtime
  credentials are stripped by `env -i`, G10); a traced or echoed step could print them, which the xtrace
  refusals and the no-`secrets.`-in-run-body pin close.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the permissive failure strands one user's workspace, which is
  single-user by definition; ADR-263's own threshold is the same.
- **CPO sign-off, 2026-11-18:** threshold single-user incident confirmed; a broken-permissive gate routes a
  user to a host without proof their workspace is LUKS-backed and soaked, so the 3-day floor and the
  per-instance grader must fail closed, and a config value may only lengthen the soak.
- `soleur:engineering:review:user-impact-reviewer` runs at review time (single-user threshold).

## Observability

Layers (hr-observability-layer-citation): GitHub Actions run log of `cf-lb-overlay.yml` (job `ga_pool_update`)
and its step summary. No Sentry or Better Stack layer is added (F7, #12936).

```yaml
liveness_signal:
  what: "SOLEUR_SOAK_EVIDENCE (one line per evaluated soak kind) and SOLEUR_INSTANCE_SOAK (one line per serve dispatch) on stderr and in the step summary"
  cadence: "per ga-pool-update serve dispatch"
  alert_target: "the dispatcher's GitHub failed-run notification plus the ::error:: annotation naming the refusal"
  configured_in: ".github/workflows/cf-lb-overlay.yml (steps '§(c) gate chain' and 'per-instance soak grader (serve only)'), apps/web-platform/infra/lb-weight-gate.sh (fail() / pass evidence emit), scripts/lib/serve-soak-evidence.sh (mirror, anti-vacuity, grader rc mapping)"

error_reporting:
  destination: "GitHub Actions run log, step summary and ::error:: annotations of cf-lb-overlay.yml (workflow-only surface, no app process, so no Sentry)"
  fail_loud: "::error::§(c) gate chain refused ... / ::error:: per-instance soak grader verdict=<V> ... NOTHING planned, NOTHING applied"

failure_modes:
  - mode: "a prd soak value below the floor"
    detection: "gate_fail sub_condition=B_*_soak_days_below_floor plus SOLEUR_SOAK_EVIDENCE source=env soak_days=<n> verdict=fail (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "per-instance soak not met or not readable (NOT_YET, FAIL, CANNOT_ESTABLISH, unknown rc)"
    detection: "SOLEUR_INSTANCE_SOAK rc=<n> verdict=<V> with rc != 0 (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "the gate stops emitting a kind's evidence but still passes"
    detection: "anti-vacuity refusal in the gate chain step (fewer than one well-formed verdict=pass line per kind) (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "producer grammar and consumer regex drift"
    detection: "none possible by construction: one SOAK_EV_RE in scripts/lib/serve-soak-evidence.sh, sourced by the suite (G4); its negative fixtures redden a loosening in deploy-script-tests; at runtime the anti-vacuity refusal (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "PR check failure; red serve run"
  - mode: "web-2 probe telemetry dark"
    detection: "grader rc 2 NOT_YET on every dispatch (its verdict text names the missing row) (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "a soak knob value that is not a plain integer from 1 to 999 (leading zero, more than 3 digits, text)"
    detection: "gate_fail sub_condition=B_*_soak_days_invalid plus SOLEUR_SOAK_EVIDENCE soak_days=invalid verdict=fail (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "the wrapper or Doppler fails before the gate runs"
    detection: "::error:: with refusing id none and zero evidence lines; the EXIT trap replays the wrapper's stderr (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "the helper is missing or fails to load in either step"
    detection: "::error::serve-soak-evidence helper not loaded (<path>) - wiring defect, do not re-dispatch (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "a step runs under xtrace with a live credential"
    detection: "helper refuses with rc 78 before any credential is used (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red serve run to the dispatcher"
  - mode: "the job is cancelled or times out while the grader runs"
    detection: "sse_instance_soak EXIT/TERM trap prints SOLEUR_INSTANCE_SOAK ... rc=none verdict=CANNOT_ESTABLISH; a hard kill leaves only GitHub's timeout notice (layer 6: workflow run log + ::error:: + step summary)"
    alert_route: "red or cancelled serve run to the dispatcher"

logs:
  where: "GitHub Actions run logs and step summaries for cf-lb-overlay.yml runs (gh run view <id> --log)"
  retention: "the repository's GitHub Actions log retention (90 days by default)"

discoverability_test:
  command: "bash scripts/serve-soak-evidence-last.sh"
  expected_output: "SOLEUR_SOAK_EVIDENCE"
  credentials_required: "GitHub repository read (gh auth) — workflow run logs are not public and no unauthenticated endpoint serves them"
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-263 (`knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`)
with `## Addendum — 2026-11-18 (#12849, the soak floor and the per-instance grader in the serve arm)`, in the
file's style (bold lead paragraphs):

- **Decision.** The serve gate enforces a floor of 3 days (`SOAK_FLOOR_DAYS`) for both soaks; an environment
  value may only lengthen it; 1 and 2 refuse as `*_below_floor`, and leading zeros refuse as `*_invalid`. The
  serve arm runs the #6931 grader before plan and refuses on any rc other than 0, scoped to web-2 until #12869.
  Both report through `SOLEUR_SOAK_EVIDENCE` / `SOLEUR_INSTANCE_SOAK`; the grammar lives once, in
  `scripts/lib/serve-soak-evidence.sh`. The knob is capped at three digits (at most 999 days): this fixes a
  bypass that existed before this change, where an unbounded value wrapped in bash arithmetic and made the
  required soak negative. The grader runs under `env -i` with only its three read credentials.
- **Why.** Run 44304068922 passed at 87,883 s on a `prd` value of 1; the 2026-10-08 addendum's "must require
  the grader's PASS" had no caller.
- **What is still not claimed.** Provenance of the marker; instance identity remains the weak anchor of the
  2026-10-08 addendum (AP-027: if a replacement's readiness row is lost, the predecessor's row still looks newest
  and the grader can PASS on the old instance; a generation anchor is a #12869 requirement); the grader is
  web-2-only; the grader stays at 3 days when the gate is lengthened; Better Stack shipping is #12936. A host
  replace keeps the pool weight it found, so a replaced instance can serve without the serve arm (residual,
  predates this change; drain-first runbook step; #12939). An instance older than 90 days has no readiness row
  in the grader's window and must be replaced to re-serve (#12938).
- **Same name, different meaning.** `scripts/followthroughs/workspaces-luks-soak-6604.sh` also reads
  `WORKSPACES_LUKS_SOAK_DAYS` (default 7, the ADR-119 soak) and is not bounded by this floor; noted here and in
  #12933's scope so deleting the `prd` value is checked against both readers.
- Add a blockquote in the 2026-10-08 addendum, after "Nothing calls the gate today.":
  `> **Superseded 2026-11-18 (#12849), in part:** the cf-lb-overlay serve arm calls the gate and now requires the #6931 grader's PASS before plan; see the addendum at the end.`

Ordinal: this amends an existing ADR, so no new ordinal is claimed.

### C4 views

All three model files were read in full (`model.c4`, `views.c4`, `spec.c4`). Enumeration:

- (a) External human actors: `founder` dispatches the serve; already modeled; no edge changes.
- (b) External systems: `github`, `betterstack`, `doppler`, `cloudflare`; the pair `github -> betterstack`
  exists (ClickHouse reads through `BETTERSTACK_QUERY_*`). No new vendor.
- (c) Containers/stores: none new (`hetzner`, the workspaces volume unchanged).
- (d) Relationships: no new edge; the serve arm becomes another reader on `github -> betterstack`.
- **Edit (in scope):** the `github -> betterstack` description near `model.c4:979` says the web2 grader
  verdict is "advisory evidence for the soak marker, not an authority". Append that the `cf-lb-overlay.yml`
  `ga-pool-update` serve arm runs `web2-luks-live-6931.sh` as a fail-closed veto (it can refuse the flip, never
  authorize it), with the credentials the job's relay bind probe already holds. (The stale clause near
  `model.c4:816`, "sourcing it there is #9358", predates this change and is left alone: plan review, DHH 8 /
  simplicity 8.)
- Regenerate `knowledge-base/engineering/architecture/diagrams/model.likec4.json` with
  `scripts/regenerate-c4-model.sh` (pinned likec4@1.60.0); run `plugins/soleur/test/c4-model-freshness.test.sh`,
  `plugins/soleur/test/c4-count-parity.test.sh` (13/13 green on 2026-11-18 before the change),
  `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`. `views.c4` needs no change.

### Sequencing

The decision is true when this PR merges; no `adopting` status is needed.

## Guard Contract

**How mutations are proven (G5, Ruled by CTO agent, 2026-11-18).** Rows marked **committed** are sandbox
mutation rows in `lb-weight-gate.test.sh` (`wmut`/`pmut` pattern): each must LAND (diff-line count asserted) and
drive its guard RED. They cover only textual YAML pins, the guard a commented-out line has satisfied before
(learnings 2026-11-05 and 2026-11-13). Rows marked **by hand** are behaviour mutations run once against the
final code; the PR body records each mutation and the row it turned RED. Rows marked **executed** are ordinary
behaviour rows on the helper. No "test the test helper" (H1) rows are committed; the H2 must-PASS rows are
behaviour rows and stay. New sections keep per-section executed-row counters, and `MIN_CASES` is raised.

### Guard 1 — soak floor

**Property.** No environment value lets either soak (`git_data`, `workspaces_luks`) be enforced as shorter
than `SOAK_FLOOR_DAYS` (3) days, and the effective value is never misread (no octal, no arithmetic wrap).

**Assembly.** The two knob reads in `lb-weight-gate.sh` (`GIT_DATA_LUKS_SOAK_DAYS` at B.2,
`WORKSPACES_LUKS_SOAK_DAYS` at B.6) and the one constant `SOAK_FLOOR_DAYS`. The values reach the gate only
through the wrapper's `GATE_ENV_ALLOW` (`env -i` exec). On the workflow side, anything that sets a knob before
the wrapper runs: the inner `-- env` (pinned by `p_guard`), the step's `env:`, the job's `env:`, and any earlier
step's `$GITHUB_ENV` write (`doppler run --preserve-env` lets an ambient value win). Chokepoint: each knob passes
the three-digit regex, the `-gt 0` check and the floor check before the age comparison uses it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the workspaces floor line (by hand) | RED (row "WORKSPACES_LUKS_SOAK_DAYS=1 refuses below_floor") |
| 2 | Delete only the git-data floor line, keeping the workspaces one (second member; by hand) | RED (row "GIT_DATA_LUKS_SOAK_DAYS=1 refuses") |
| 3 | `SOAK_FLOOR_DAYS=1` (by hand) | RED (rows for 2 and 1, and the F8/G8 parity row) |
| 4 | Floor compare `-gt` instead of `-ge` (by hand) | RED (row "3 accepted") |
| 5 | Floor check moved before the regex (by hand) | RED (row "0 refuses `*_invalid`" now reads `*_below_floor`) |
| 6 | Default `:-1` (by hand) | RED (row "unset with 2-day markers refuses not_elapsed, source=default soak_days=3") |
| 7 | Regex back to `^[0-9]+$` (by hand) | RED (row "010 refuses invalid") |
| 8 | Regex unbounded, `^[1-9][0-9]*$` (by hand) | RED (rows `1000`, `200000000000000`, `18446744073709551619` refuse invalid) |
| 9 | `SOAK_FLOOR_DAYS` assigned as `${SOAK_FLOOR_DAYS:=3}` (by hand) | RED (`scn_allow_parity`, allowlist grows by one) |
| 10 | `WORKSPACES_LUKS_SOAK_DAYS=3` added to the gate step's inner env (committed) | RED (`p_guard` C.4-P1) |
| 11 | A knob set in the step `env:`, the job `env:`, or an earlier `>> "$GITHUB_ENV"` export (committed, three mutants) | RED (census row: no `(GIT_DATA|WORKSPACES)_LUKS_SOAK_DAYS` on a non-comment line of `cf-lb-overlay.yml`) |
| 12 | Own dispatch: the floor section's rows never execute (by hand) | RED (the section's executed-row counter must equal its declared row count) |

**Harness rows.** (H2) Must-PASS non-canonical: `WORKSPACES_LUKS_SOAK_DAYS=5` with 6-day markers passes with
`required_s=432000 source=env`; the same 5 with 4-day markers refuses `B_workspaces_luks_soak_not_elapsed`; `999`
with 1000-day markers passes. Same pairs for `GIT_DATA_LUKS_SOAK_DAYS`.

**Anchor.** The floor is a code constant reviewed in the PR diff; no stored value guards it. `p_guard`'s exact
name set and the knob census are the anchors against a workflow-side setting.

### Guard 2 — soak evidence line (producer)

**Property.** For every soak kind whose evaluation starts, the gate prints exactly one well-formed
`SOLEUR_SOAK_EVIDENCE` line on stderr whose `verdict` equals the gate's decision for that kind and whose
`sub_condition` equals the `gate_fail` id when it refuses; no raw environment text appears in it.

**Assembly.** Every exit inside B.2-B.5 and B.6-B.10 of `lb-weight-gate.sh` goes through the existing `fail()`,
which emits whenever `EV_KIND` is non-empty (G3), so a refusal added to those blocks later is in the assembly by
construction; plus the two pass-emit sites (after B.5, after B.10) and the three `EV_KIND` assignments (B.2
entry, B.6 entry, after B.10). The grammar is the single `SOAK_EV_RE` in the helper (G4).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `fail()` emits only when `EV_KIND=git_data` (by hand) | RED (every workspaces refusal row: zero lines) |
| 2 | The workspaces pass emit deleted, the git-data one kept (second member; by hand) | RED (pass row: exactly 2 pass lines) |
| 3 | `EV_KIND` not cleared after B.10, or set before B.1 (by hand) | RED (B.1 / Condition A / standby rows: zero lines) |
| 4 | `verdict=pass` hardcoded on the fail path (by hand) | RED (every refusal row) |
| 5 | Workspaces line computes `age_s` from the git-data marker (by hand) | RED (fixture with markers 4 d and 6 d apart, age window per kind) |
| 6 | `source=env` always (by hand) | RED (unset row expects `source=default`) |
| 7 | Raw `$WS_MARKER` printed instead of the epoch rebuild (by hand) | RED (`+02:00` offset fixture expects the Z-form rebuild; space-separator fixture expects a grammar match) |
| 8 | Raw soak value printed (`1 verdict=pass`) (by hand) | RED (exactly one `verdict=` token; `soak_days=invalid`) |
| 9 | `SOAK_EV_RE` loosened (a field made optional) (by hand) | RED (G4 negative fixtures: extra field, missing field, out-of-order field, doubled `verdict=` must not match) |

**Harness rows.** (H2) Must-PASS non-canonical: gated host `web-3` (fixture adds web-3 to the relay roster and
its address to the allowlist, and sets `SOLEUR_WEB_HOSTS` once #12918 lands) yields a
`kind=git_data host=web-3 ... verdict=pass` line, then a workspaces line with
`sub_condition=B_workspaces_luks_marker_other_host marker_at=none` (the host is not hardcoded).

### Guard 3 — per-instance grader precondition (serve arm)

**Property.** In `ga_pool_update`, no serve-mode `terraform plan` runs unless `web2-luks-live-6931.sh` returned
rc 0 in an earlier step of the same job, invoked with an empty `SOLEUR_FT_EARLIEST` and only its allowlisted
environment, for the same gated host the gate chain checked.

**Assembly.** The step list of job `ga_pool_update` (the only job whose plan can carry `web2_lb_weight=1`:
`w_guard` pins the single `WEB2_LB_WEIGHT` assignment; `ga_overlay` passes an explicit 0), and
`sse_instance_soak` in the helper. Chokepoints: the step's position (GATE < GRADER < HEALTH, GRADER < PLAN), its
`if:`, its key set, the absence of tolerance (`continue-on-error`, `|| true`, `set +e`, `shell:`, job `defaults`),
the host literal shared with the gate step, the helper's rc mapping and its `env -i` call. The web-2 literal
sites are: the gate step, the grader step, the wrapper's `MARKER_HOST="web-2"` and the rows library's
`W2L_HOST_NAME="soleur-web-2"`; the parity row pins all four, labelled as the #12869 un-keying list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Step `if:` set to `false` or the serve condition removed (committed) | RED (wiring row) |
| 2 | Step moved after `Terraform plan` (committed) | RED (order row) |
| 3 | `continue-on-error: true`, or `|| true` after the helper call (committed) | RED (tolerance row) |
| 4 | A `shell:` key added to the step (committed) | RED (key-set row) |
| 4b | The gate step's inline backstop `[[ "$gate_rc" -eq 0 ]] || exit 1` deleted, or the helper call wrapped in `if`/`||` (committed) | RED (gate-step wiring rows) |
| 4c | `sse_gate_chain_check`'s refuse branch returns 0 (by hand) | RED (executed rc=1 row expects return 1; the backstop still fails the step) |
| 5 | Host literal in the grader step changed to `web-3` while the gate step keeps `web-2` (committed) | RED (parity row) |
| 6 | rc 2 mapped to 0 in the helper (by hand) | RED (executed row rc=2) |
| 7 | rc 1, 2, 3 refuse but 78 passes (second member past the named codes; by hand) | RED (executed rows rc=78, 126, 127) |
| 8 | `SOLEUR_FT_EARLIEST=` dropped from the `env -i` call (by hand) | RED (stub records a non-empty value under an ambient `SOLEUR_FT_EARLIEST`) |
| 9 | `env -i` dropped (by hand) | RED (decoy row: the stub sees `HCLOUD_TOKEN`, `TF_VAR_github_app_runtime_doppler_token`, `DOPPLER_TOKEN`, `AWS_SECRET_ACCESS_KEY`) |
| 10 | Own dispatch: the helper returns 0 before calling the grader (by hand) | RED (stub call count must be exactly 1 on the rc=0 row) |

**Harness rows.** (H2) Must-PASS: stub rc 0 with a `PASS:` line yields return 0, a fenced summary line
`SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=0 verdict=PASS`, and no `::error::`.

### Guard 4 — summary mirror and anti-vacuity (consumer)

**Property.** The gate chain step writes to the step summary every well-formed evidence line and nothing
else, on pass and on refuse, replays the full stderr to the log, and refuses a pass unless each kind has exactly
one well-formed pass line for the gated host whose numbers show a met soak of at least the floor.

**Assembly.** The gate chain step's capture, `gate_rc` capture and EXIT trap (YAML), and
`sse_gate_chain_check` in the helper (mirror, refusal message, pass re-check), with the single `SOAK_EV_RE` and
`SOAK_FLOOR_S`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Mirror runs only on the pass branch (executed) | RED (refuse row: the fenced summary block holds the fail line) |
| 2 | Mirror unanchored (`grep SOLEUR_SOAK_EVIDENCE`) (executed) | RED (forged line with an extra field must not reach the summary) |
| 3 | EXIT trap replay dropped (committed) | RED (step-wiring row: the trap line is present; executed row: stderr holds the evidence and `gate_fail` lines) |
| 4 | Anti-vacuity checks only `git_data` (second member; by hand) | RED (pass fixture lacking the workspaces line refuses) |
| 5 | Pass re-check accepts `none` fields or `required_s=86400` (by hand) | RED (G8 rows: both refuse) |
| 6 | Host not compared (by hand) | RED (wrong-host pass line refuses) |
| 7 | Mirror grep unguarded under `set -e` (by hand) | RED (Condition A refusal row: the `::error::` line still appears) |
| 8 | Own dispatch: summary write skipped when the file is empty (by hand) | RED (pass row asserts two lines between the fences) |

**Harness rows.** (H2) Must-PASS: interleaved non-evidence stderr (a Doppler notice line) passes and stays out of
the summary.

## Infrastructure note

No Terraform, server, secret, DNS or vendor change. The workflow edits add a step that reads with existing
credentials; no `terraform apply` path changes. Phase 2.8 IaC routing does not apply.

## Implementation Phases

### Phase 1 — tests first (RED)

1. `lb-weight-gate.test.sh` and `lb-weight-gate-with-marker.test.sh`: anchor all 7 `sub_condition=` substring
   checks on the whole `gate_fail sub_condition=<id>` line; add a census row that reddens on any remaining
   `*"sub_condition=` substring check.
2. Source `scripts/lib/serve-soak-evidence.sh` for `SOAK_EV_RE` / `INSTANCE_EV_RE` / `SOAK_FLOOR_S` (G4: one copy).
   Helpers `ev_lines <kind>`, `ev_field <line> <name>` (anchored on `(^| )name=([^ ]+)( |$)`), `assert_ev`.
   Fixed grammar fixtures: pass, fail, `none`, `unparseable`, negative `age_s` must match; extra field, missing
   field, out-of-order field, doubled `verdict=` must not.
3. Floor rows for both knobs: 1 and 2 refuse `*_below_floor`; 3 and 5 accept (5 with 6-day markers); 5 with
   4-day markers refuses `*_soak_not_elapsed` with `required_s=432000`; 999 with 1000-day markers passes; 0,
   `010`, `08`, `abc`, `1 verdict=pass`, `1000`, `200000000000000`, `18446744073709551619` refuse `*_invalid`
   with `soak_days=invalid`; unset and empty give `source=default soak_days=3`; `3` gives `source=env`.
4. Evidence rows: for every existing refusal id in B.2-B.10, exactly one line of that kind, `verdict=fail`,
   `sub_condition` equal to the `gate_fail` id; pass gives exactly two `verdict=pass sub_condition=none` lines;
   standby, Condition A and B.1 refusals give zero; a git-data refusal gives zero workspaces lines; `age_s` in
   `[expected, expected+120]`; `required_s` exact; `marker_at` rebuilt (offset fixture); `floor_days=3`;
   `host=web-3` row (roster and allowlist fixture additions as in Guard 2 H2).
5. Parity row: `^SOAK_DAYS=([0-9]+)$` in the grader equals `^SOAK_FLOOR_DAYS=([0-9]+)$` in the gate, both
   non-empty, and the helper's `SOAK_FLOOR_S` equals both times 86400 (F8, G8). Host-literal parity across the
   four web-2 sites (Guard 3 Assembly).
6. Workflow wiring rows: grader step (Guard 3 rows 1-5), the gate step's EXIT trap and `gate_rc=0`, both steps'
   `# shellcheck source=scripts/lib/serve-soak-evidence.sh` line and single helper call, the
   `grader=web2-luks-live-6931` value, no mention of the soak marker's Doppler name in `cf-lb-overlay.yml`
   (architecture 2), and the knob census (Guard 1 row 11). Committed mutation rows per G5.
7. Executed rows on `sse_instance_soak`: stub grader recording its call count, rc fixture, `SOLEUR_FT_EARLIEST`
   and its full `env` name set; loop rc over 0, 1, 2, 3, 78, 126, 127; ambient `SOLEUR_FT_EARLIEST` row; decoy
   row (G10: planted `HCLOUD_TOKEN`, `TF_VAR_github_app_runtime_doppler_token`, `DOPPLER_TOKEN`,
   `AWS_SECRET_ACCESS_KEY`; the recorded set is exactly the allowlist plus bash's own `PWD`/`SHLVL`/`_`, and no
   decoy value appears); one `web-3` row (`# until #12869`: rc 1, `rc=none`, stub never called) and one empty-host
   row (`host=invalid`). Reuse the relay rows' clean-env pattern (`env -i PATH=...`, `GITHUB_STEP_SUMMARY` file);
   write stub shebangs from `command -v bash`; never call helpers that set globals inside `$( )`.
8. Executed rows on `sse_gate_chain_check` per Guard 4 (refuse and pass fixtures, forged line, missing kind,
   `none` fields, `required_s=86400`, wrong host, zero-line Condition A refusal, `below_floor` message text,
   anti-vacuity message text, summary lines read between the ```` ```text ```` fences).
9. `scripts/serve-soak-evidence-last.sh`: one executed row with a stub `gh` (a run log holding evidence lines
   prints the run id and at most 3 + 1 matched lines; a window with none exits 2).
10. `lb-weight-gate-with-marker.test.sh`: one seam row that the happy path's stderr carries two `verdict=pass`
    evidence lines through the `env -i` exec (G6: keep).
11. Raise `MIN_CASES=330` (the minimum-cardinality guard at the end of `lb-weight-gate.test.sh`) to the new measured
    total; each new section counts its own executed rows against its declared row count.
12. `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 98 -> 99 with the
    PLACEMENT / TRUTH / NO SUBSTITUTE comment.

Run the suites: `bash apps/web-platform/infra/lb-weight-gate.test.sh`,
`bash apps/web-platform/infra/lb-weight-gate-with-marker.test.sh`,
`bash scripts/followthroughs/web2-luks-live-6931.test.sh` (must stay green, untouched). Confirm the new rows
are RED before Phase 2.

### Phase 2 — the gate (GREEN for Guards 1-2)

`apps/web-platform/infra/lb-weight-gate.sh` per Part 1.

### Phase 3 — the workflow (GREEN for Guards 3-4)

`scripts/lib/serve-soak-evidence.sh` per Part 2 (GREEN for its executed rows); `.github/workflows/cf-lb-overlay.yml`
per Part 3; `infra-validation.yml` path entries; grader comment.

### Phase 4 — records

ADR-263 addendum and blockquote; `model.c4` edits + regenerate `model.likec4.json`; runbooks:

- `cf-lb-a-record-gaplessness-verify.md`: a new `### Before dispatching mode=serve: the soak floor and the
  per-instance grader (#12849)` after the relay-evidence section. It names the two line prefixes and their
  fields and points to `SOAK_EV_RE` / `INSTANCE_EV_RE` in `scripts/lib/serve-soak-evidence.sh` and the ADR-263 addendum for the exact grammar (no
  third copy of the regex, plan review DHH 7 / simplicity 7); says how to read them from the run log
  (`gh run view <id> --log`) and the step summary; and states the two clocks (spec-flow 6): the gate's ETA is
  `marker_at + required_s`, the grader's soak starts at the newest readiness row, and both must pass. Then a
  refusal-to-action table (Ruled by CTO agent, 2026-11-18, plan review):

  | Refusal | What the operator does |
  |---|---|
  | `*_soak_days_below_floor` | Delete the Doppler `prd` value (#12933, Operator-authorizes). Until #12933, every serve refuses this way. |
  | `*_soak_not_elapsed` | Wait until `marker_at` + `required_s`. |
  | `*_soak_days_invalid` | The knob is not a plain integer from 1 to 999 (a leading zero, more than 3 digits, or text); the log prints `soak_days=invalid` on purpose. Read the value (`doppler secrets get <KNOB> -p soleur -c prd --plain`), then set a plain integer from 3 to 999 or delete it (Operator-authorizes). |
  | refusing id `none` | The wrapper or Doppler failed before the gate ran; read the replayed stderr in the step log. |
  | `NOT_YET` with "no GREEN web-2 readiness row" and web-2 older than 90 days | The grader's readiness lookback is 90 days and the row is written once per instance: replace the host (this runbook) and wait for the 3-day soak (G12; #12938). |
  | `NOT_YET` (other) | A read fault: retry now. A soak wait: retry after 3 distinct green probe days. Still `NOT_YET` 4 days after readiness: telemetry dark; run the readiness-row and daily probe-row (`SYSLOG_IDENTIFIER = luks-monitor`, `host_name = soleur-web-2`) Better Stack queries in `web-host-replace.md` (`scripts/betterstack-query.sh`). |
  | `FAIL` | The instance's soak is spoiled: read the non-green probe rows with the same `web-host-replace.md` queries, then replace the host (the repair). |
  | `CANNOT_ESTABLISH` with rc 3 | Better Stack credentials or the shared helper are missing. |
  | `CANNOT_ESTABLISH` with rc 126, 127, another code, or `none` | A code or wiring defect; do not re-dispatch. |
  | Anti-vacuity ("soak evidence ... missing or malformed") | A code defect; do not re-dispatch. |

- `web-host-replace.md`: in the sentence ending "`mode=serve` then refuses with `B_workspaces_luks_so...`",
  change "(3 by default in `lb-weight-gate.sh`)" to "(at least 3: `SOAK_FLOOR_DAYS` in `lb-weight-gate.sh`; a
  configured value may only lengthen it)", and add the grader (PASS needs green probe rows on 3 distinct days
  after the new readiness row).

### Phase 5 — full verification

Re-run the three suites plus `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (its G3
census and `g3_dbin_ok` read `cf-lb-overlay.yml`), `python3 scripts/lint-guard-contract.py` on this plan, the C4 tests, `actionlint` (if
installed) on `cf-lb-overlay.yml`, and `shellcheck` on the gate, the grader, the helper and the probe.

## Files to Edit

- `apps/web-platform/infra/lb-weight-gate.sh`
- `apps/web-platform/infra/lb-weight-gate.test.sh`
- `apps/web-platform/infra/lb-weight-gate-with-marker.test.sh` (anchor 5 substring checks; one seam row)
- `.github/workflows/cf-lb-overlay.yml`
- `.github/workflows/infra-validation.yml`
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 98 -> 99, with the
  PLACEMENT / TRUTH / NO SUBSTITUTE comment naming this plan; this plan declares `credentials_required`)
- `scripts/followthroughs/web2-luks-live-6931.sh` (comment above `SOAK_DAYS=3` only)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
  (one-line pointer at "`GIT_DATA_LUKS_SOAK_DAYS` (default 3, §3.D)": now a floor of 3, values only lengthen,
  see the ADR-263 2026-11-18 addendum; plan review, architecture 8)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`

## Files to Create

- `scripts/lib/serve-soak-evidence.sh`: the sourced step helper (Part 2; Ruled by CTO agent, 2026-11-18, G2).
- `scripts/serve-soak-evidence-last.sh`: the read-only discoverability probe (G11, Ruled by CTO agent,
  2026-11-18). It runs `gh run list --workflow cf-lb-overlay.yml` with a fixed `--limit` (default 50, at most
  50), reads runs newest first, and for the first run whose log holds either token prints the run id, at most 3
  `SOLEUR_SOAK_EVIDENCE` lines and 1 `SOLEUR_INSTANCE_SOAK` line, each matched by the helper's sourced
  `SOAK_EV_RE` / `INSTANCE_EV_RE` (never a raw log dump), with control characters stripped from the printed
  match. It lists `--branch main` runs by default and prints each reported run's `headBranch` and `headSha`, since a
  run dispatched from another branch can print forged lines from a modified gate (infra-security 4). `gh run view --log` prefixes every line with
  `<job>\t<step>\t<timestamp>` plus a space, so the probe strips that prefix (`sed -E 's/^[^\t]*\t[^\t]*\t[^ ]+ //'`) before
  the anchored match (equivalently: an unanchored `grep -oE "$SOAK_EV_RE"`, then re-validate
  `^${SOAK_EV_RE}$` on the extracted text). No match in the window: one line `no soak evidence in the last <N> runs` (it must not
  contain either token, or it would satisfy `expected_output` by itself), exit 2. Default `--limit` 50 (a
  20-run window can hold only non-serve modes; observability 7). Tested with shellcheck and executed rows using
  a stub `gh` that prints the real tab-prefixed format (observability 1). It is not folded into the step helper: that
  runs inside the production job with credentials, and an operator read tool does not belong there.

## Open Code-Review Overlap

2 open scope-outs touch these files:

- #8735 (infra-validation notify-main-failure misses cancelled jobs): **Acknowledge** — a different concern
  (failure notification on cancel) in the same workflow; this plan only adds one path-filter line.
- #7942 (two mutation batteries named `*.mutation.sh` run in no gate): **Acknowledge** — concerns
  `plugins/soleur/test/` batteries, not the infra suites this plan edits.

## Research Insights

**Premise Validation.** #12849 open (p1, the target). #12008, #9421, #12869, #12933, #12820 open; #6931 closed
(the grader it enrolled is the one reused). Draft PR #12934 is this branch. Collision pre-check: open PR #12918
(draft, `feat-one-shot-12910-host-roster-lease-id`) edits `lb-weight-gate.sh` Condition A, the wrapper's
allowlist and both suites: non-overlapping hunks, rebase on whichever lands second. Three foreign `test-all.sh`
processes in unrelated worktrees. Every cited path exists on `origin/main` (7e1d286ebe).

**Property List.**

1. P1: no `prd` (or any environment) value makes either soak shorter than 3 days.
2. P2: a reborn host cannot serve on a predecessor's marker age; its own instance must show the soak.
3. P3: every serve run's log shows the soak it enforced (days, source, marker time, age, verdict) and the
   per-instance grade, whether it passed or refused.
4. P4: the change cannot widen the credential surface of the job.

**Cut List.**

- Workflow pin of both soak values (issue "Needed" bullet 1) → P1 → covered by the code floor; a pin would hide
  a stray value (CTO ruling item 1).
- "Tie the marker to the instance's readiness time" (issue bullet 3, second option) → P2 → covered by the
  existing grader, which already derives the soak from the readiness row; re-keying the marker is #12869.
- Better Stack ingest of the lines → P3 → covered by the run log and summary; deferred to #12936 (F7).

**Relevant code** (content anchors): `lb-weight-gate.sh` `# B.2 — soak-window days`, `WS_SOAK_DAYS=`,
`fail() {`; `lb-weight-gate-with-marker.sh` `GATE_ENV_ALLOW=(`, `exec env -i`; `cf-lb-overlay.yml`
`- name: §(c) gate chain`, `- name: relay bind probe (serve only)`; `lb-weight-gate.test.sh` `reset_def()`,
`run_with_def()`, `assert_stderr_contains()`, `step_of()`, `p_guard()`, `r_exec()`, `e_refuse()`;
`lb-weight-gate-with-marker.test.sh` `gate_read_vars()`, `scn_allow_parity`; `web2-luks-live-6931.sh` exit
semantics header, `unmet()`; `web2-luks-live-6931.test.sh` curl stub and `FLOOR=` count;
`infra-validation.yml` `scripts/lib/web2-relay-rows.sh` path entry.

**Findings from repo research.** No existing fixture sets a soak value of 1 or 2 (defaults are explicit `'3'`
in `reset_def`), so no fixture breaks. No test pins stderr exactly; all are substring checks, which the new
evidence line could satisfy alone (hence the anchoring). New infra suites are glob-registered by
`run-registered-suites.sh` (no edit). The wrapper's census forbids literal `lb-weight-gate.sh` and assignments
of `WORKSPACES_LUKS_CUTOVER_AT` in non-test code, so the new step must contain neither.

**Institutional learnings applied.**

- `2026-11-05-a-gate-suite-that-pins-the-step-body-cannot-see-the-wiring-and-twelve-seats-found-it.md`: pin
  the step's wiring (key set, order, `if:`, no `shell:`/`defaults`) in the first version, not only its body;
  stub shebang from `command -v bash`; no state-setting helper inside `$( )`; scope mutations to the step's
  line range and assert the diff count.
- `2026-11-13-a-pin-on-gate-text-was-satisfied-by-a-commented-out-line-twice.md`: every text pin runs on the
  comment-stripped body (`c4_nocomment`).
- `2026-11-12-keyed-host-gate-must-refuse-unkeyed-evidence-web-hosts.md`: evidence must name the host it
  attests; hence the F5 host refusal in the grader step.
- `2026-11-16-web2-kernel-currency-replace-five-operational-traps.md` §5: the marker can be inherited across a
  rebirth; the grader is the per-instance check.
- `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`: when citing these lines as proof,
  attribute them to their step group.
- `2026-11-09-followthrough-probe-self-deriving-inputs.md`: `SOLEUR_FT_*` is the sweeper's reserved prefix;
  the step sets `SOLEUR_FT_EARLIEST` only to empty, deliberately.

**External research.** Not run: the repo has strong local patterns for every mechanism (gate, step harness,
grader), and the change adds no external API.

**Functional overlap.** Community registries queried; no overlapping skill or agent.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "In `lb-weight-gate.sh`, require at least 3 for both days values. Add `lb-weight-gate.test.sh` rows that refuse a value of `1`." [issue #12849] | Part 1; Phase 1 step 3 | mapped |
| 2 | "In the serve step of `cf-lb-overlay.yml`, pin `WORKSPACES_LUKS_SOAK_DAYS=3` and `GIT_DATA_LUKS_SOAK_DAYS=3` in the inner env" [issue #12849] | — | descoped — justification: superseded by the binding CTO ruling of 2026-11-18 ("No pin in the workflow ... a pin would silently hide a stray value"); Guard 1 row 10 keeps a pin out |
| 3 | "Before serving, require the #6931 rule (3 distinct green probe days after the newest readiness row), or tie the marker to the instance's readiness time." [issue #12849] | Parts 2-3 (`sse_instance_soak`, grader step) | mapped |
| 4 | "The fix must add a `SOLEUR_*` gate line carrying those fields, so a future shortened soak shows up in the run log and in Better Stack." [issue comment 2026-11-18] | Part 1 evidence line, Part 2 mirror | mapped (run log); Better Stack descoped — justification: Ruled by CTO agent, 2026-11-18 (F7), tracked #12936 |
| 5 | "constant SOAK_FLOOR_DAYS=3. WORKSPACES_LUKS_SOAK_DAYS and GIT_DATA_LUKS_SOAK_DAYS: unset → 3; >=3 accepted (only lengthens); positive <3 fails with B_workspaces_luks_soak_days_below_floor / B_luks_soak_days_below_floor. Keep the existing *_invalid checks. No workflow pin." [brief] | Part 1 | mapped |
| 6 | "serve job: before plan, run the existing grader scripts/followthroughs/web2-luks-live-6931.sh (Better Stack creds the job already has, empty SOLEUR_FT_EARLIEST); any non-zero rc refuses. Scope SOLEUR_GATED_HOST=web-2" [brief] | Parts 2-3 | mapped |
| 7 | "Self-report on stderr ... SOLEUR_SOAK_EVIDENCE ... and SOLEUR_INSTANCE_SOAK ... mirror both into the step summary." [brief] | Part 1, Part 2, Part 3 | mapped |
| 8 | "Tests: refuse 1 and 2 for both knobs, accept 3 and 5; assert evidence-line fields by anchored field; assert serve refuses on each non-zero grader rc." [brief] | Phase 1 | mapped |
| 9 | "ADR-263 addendum recording the floor and the per-instance grader requirement." [brief] | `## Architecture Decision (ADR/C4)` | mapped |
| 10 | "One PR, Closes #12849, Ref #12008, Ref #9421 (never Closes for #12008 or #9421)." [brief] | Overview; Acceptance Criteria | mapped |
| 11 | "Must merge before #12869." [brief] | Dependencies & Risks | mapped |
| 12 | "Removing the live prd override is a separate Operator-authorizes item (#12933), not part of this PR." [brief] | `## Operator Holds` | descoped — justification: the brief itself scopes it out; recorded as a hold |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `lb-weight-gate.sh` | asks 1, 5, 7 | asked |
| `lb-weight-gate.test.sh` | asks 1, 8 | asked |
| `lb-weight-gate-with-marker.test.sh` (one seam row) | — | inferred — justification: the evidence line must survive the wrapper's `env -i` exec to reach the log (ask 7); one row proves the seam forwards it |
| `cf-lb-overlay.yml` | asks 6, 7 | asked |
| `infra-validation.yml` path entries | — | inferred — justification: the parity row reads the real grader and the suite executes the helper; without the paths a grader-only or helper-only PR skips the guard (F9, G2) |
| `scripts/lib/serve-soak-evidence.sh` (new) | asks 6, 7 | asked — the steps' logic, moved to a checked-in file so the suite executes it (Ruled by CTO agent, 2026-11-18, G2) |
| `preflight-discoverability-test.test.ts` baseline bump | — | inferred — justification: this plan declares `credentials_required`; the corpus count moves (sharp-edges 4) |
| ADR-068 pointer | — | inferred — justification: ADR-068 states the git-data soak as "default 3"; it becomes a floor (architecture 8) |
| G1 three-digit cap | — | inferred — justification: Ruled by CTO agent, 2026-11-18; an unbounded value bypasses the floor ask 5 sets |
| grader comment | — | inferred — justification: the comment would be false after the floor lands; the parity test needs a named anchor (F8) |
| ADR-263 addendum + blockquote | ask 9 | asked |
| `model.c4` + `model.likec4.json` | — | inferred — justification: the `github -> betterstack` description becomes false (wg-architecture-decision-is-a-plan-deliverable, C4 completeness mandate) |
| runbooks | — | inferred — justification: both runbooks state the serve preconditions; leaving them out would send the next dispatcher to a refusal they cannot read |
| F10 regex tightening | — | inferred — justification: a leading-zero value weakens the floor ask 5 sets (Ruled by CTO agent, 2026-11-18) |
| Anti-vacuity check (Part 2, `sse_gate_chain_check`) | — | inferred — justification: Ruled by CTO agent, 2026-11-18 (F6); a pass with no evidence would defeat ask 7 |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `.github`, `scripts`, `knowledge-base`
- Planned files: 15 (13 edited, 2 created) | Estimated changed lines: ~650 (most in `lb-weight-gate.test.sh`;
  G5 cut most committed mutation rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the subsystem threshold trips, but the brief mandates one PR and the
  `knowledge-base` and `scripts` edits are the ADR, C4, runbook and comment records that must not lag the
  behavior they describe (wg-architecture-decision-is-a-plan-deliverable); splitting would ship a gate whose
  recorded architecture is false.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1: With either knob at `1` or `2`, the gate exits 1 with the whole line
      `gate_fail sub_condition=B_luks_soak_days_below_floor` (git data) or
      `gate_fail sub_condition=B_workspaces_luks_soak_days_below_floor` (workspaces).
- [ ] AC2: With either knob at `3` (4-day markers) or `5` (6-day markers), the gate exits 0; with `5` and
      4-day markers it refuses `*_soak_not_elapsed` and the line carries `required_s=432000`.
- [ ] AC3: `0`, `010`, `08`, `abc`, `1 verdict=pass`, `1000`, `200000000000000` and `18446744073709551619`
      refuse as `*_invalid` (`999` with 1000-day markers passes), and the evidence line carries
      `soak_days=invalid` and exactly one `verdict=` field.
- [ ] AC4: Unset and empty knobs give `source=default soak_days=3`; a set knob gives `source=env`.
- [ ] AC5: On a full pass the gate's stderr holds exactly two lines matching `SOAK_EV_RE`, one per kind, each
      `verdict=pass sub_condition=none`; on every refusal inside B.2-B.10 exactly one line of that kind with
      `verdict=fail` and `sub_condition` equal to the `gate_fail` id; on the standby branch, Condition A and B.1
      refusals, zero lines.
- [ ] AC6: No raw environment text appears in an evidence line: `marker_at` is `none`, `unparseable` or an
      epoch-rebuilt `YYYY-MM-DDTHH:MM:SSZ`.
- [ ] AC7: `scn_allow_parity` stays green with the allowlist unchanged from the base branch (11 names today, 12
      after #12918 lands); no new environment name is read by the gate.
- [ ] AC8: `ga_pool_update` contains exactly one step `per-instance soak grader (serve only)`, after the gate
      chain and before the health precondition and the plan, serve-gated, keys exactly `name/if/env/run`, env
      exactly `SOLEUR_GATED_HOST: web-2` plus the three `BETTERSTACK_QUERY_*` secrets; its run body sources
      `scripts/lib/serve-soak-evidence.sh` and makes one `sse_instance_soak` call.
- [ ] AC9: Executing `sse_instance_soak` with a stub grader returning 1, 2, 3, 78, 126 and 127 exits 1 each time,
      with a `::error::` line and `SOLEUR_INSTANCE_SOAK host=web-2 grader=web2-luks-live-6931 rc=<n> verdict=<V>`
      (FAIL, NOT_YET, CANNOT_ESTABLISH, CANNOT_ESTABLISH, CANNOT_ESTABLISH, CANNOT_ESTABLISH) on stderr and in the
      summary; rc 0 exits 0 with `verdict=PASS`; the stub is called exactly once and sees an empty
      `SOLEUR_FT_EARLIEST` under an ambient value; a non-web-2 host refuses with `rc=none
      verdict=CANNOT_ESTABLISH` and never calls the stub; an empty host prints `host=invalid`; the stub sees only the `env -i` allowlist and
      none of the planted decoy credentials (G10).
- [ ] AC10: Executing `sse_gate_chain_check`: on refuse and pass, the summary holds, between a ```` ```text ````
      fence pair under the heading, only the grammar-matching lines; the gate step's EXIT trap replays every
      wrapper stderr line; a pass missing either kind's line, with `none` fields, with `required_s` below
      259200, or for a different host exits 1 with the anti-vacuity message; a zero-line refusal still prints
      its `::error::`. `SOAK_EV_RE` exists once (the helper) and the G4 negative fixtures do not match.
- [ ] AC11: Grader `SOAK_DAYS` equals gate `SOAK_FLOOR_DAYS`, and the helper's `SOAK_FLOOR_S` equals both times
      86400 (parity row); the grader's comment names
      `SOAK_FLOOR_DAYS`; `web2-luks-live-6931.test.sh` passes unchanged.
- [ ] AC12: Every **committed** Guard 1-4 mutation row lands and drives its guard RED; the PR body lists every
      **by hand** mutation and the row it turned RED (G5).
- [ ] AC13: `infra-validation.yml`'s `pull_request` paths include `scripts/followthroughs/web2-luks-live-6931.sh`,
      `scripts/lib/serve-soak-evidence.sh` and `scripts/serve-soak-evidence-last.sh`.
- [ ] AC14: ADR-263 carries the 2026-11-18 addendum (including the G1 overflow fix and the AP-027 residual) and
      the supersession blockquote; ADR-068 carries the floor pointer; `model.c4` edits land and
      `c4-model-freshness`, `c4-count-parity`, `c4-code-syntax` and `c4-render` are green.
- [ ] AC15: Both runbooks name the floor and the grader as serve preconditions.
- [ ] AC16: The PR body says `Closes #12849`, `Ref #12008`, `Ref #9421`, and carries the Operator Holds below.
- [ ] AC17: A refusal is a red job whose `::error::` line names the reason, so the dispatcher is alerted, not
      only the log (CPO concern 1).
- [ ] AC18: `bash scripts/serve-soak-evidence-last.sh` passes shellcheck and its stub-`gh` row;
      `preflight-discoverability-test.test.ts` passes with `BASELINE_DECLARED_PROBES = 99`.
- [ ] AC19: `cf-lb-overlay.yml` names neither soak knob on a non-comment line nor the soak marker's Doppler name
      anywhere; every `sub_condition=` check in both suites is anchored (census row).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-18: architecture risk is low. The change adds fail-closed checks
before `terraform plan` in a manually dispatched serve path, and gate behaviour only gets stricter. The main
risks are coupling and false passes, not outages: forgeable or vacuous evidence lines (F2, F6), the octal
misread (F10), and the hardcoded web-2 grader that must stay in step with the gate host until #12869 (F5). No
new secrets enter the job, and the wrapper's `env -i` allowlist is unchanged. The grader can return NOT_YET
forever if web-2 telemetry goes dark; that is intended fail-closed behaviour, visible in the summary.

### Product/UX Gate

Not applicable: no UI surface in `## Files to Edit` or `## Files to Create`; Product tier NONE. CPO consulted
for the threshold sign-off only (recorded under `## User-Brand Impact`).

## Test Scenarios

All `unit` layer unless stated (bash suites, no network, no credentials).

- Given `WORKSPACES_LUKS_SOAK_DAYS=1` and valid 4-day markers, when the gate runs, then it exits 1 with
  `gate_fail sub_condition=B_workspaces_luks_soak_days_below_floor` and one evidence line
  `kind=workspaces_luks ... soak_days=1 source=env ... verdict=fail sub_condition=B_workspaces_luks_soak_days_below_floor`.
  (Regression for run 44304068922.)
- Given the same with `GIT_DATA_LUKS_SOAK_DAYS=2`, then `B_luks_soak_days_below_floor` and a `kind=git_data`
  line; no workspaces line.
- Given both knobs unset and 2-day markers, then `B_luks_soak_not_elapsed`, `source=default soak_days=3`.
- Given `010`, then `*_invalid` (not an 8-day soak).
- Given a marker with a `+02:00` offset, then `marker_at` is the Z-form rebuild.
- Given gated host `web-3`, then the git-data line says `host=web-3` and the workspaces block refuses
  `B_workspaces_luks_marker_other_host` with `marker_at=none`.
- Given `sse_instance_soak` and a stub grader exiting each of 1, 2, 3, 78, 126, 127 (`integration`: the
  real helper executed against a fake workspace tree), then return 1, `::error::`, the mapped verdict.
- Given decoy `HCLOUD_TOKEN` and Doppler/AWS values in the environment, then the stub grader sees none of them.
- Given a stub grader that prints `NOT YET: no GREEN web-2 readiness row opens the soak (...)` and exits 2, then
  the step exits 1, that line is in stderr, and the `::error::` carries the 90-day replace next-step (G12).
- Given `GIT_DATA_LUKS_SOAK_DAYS=200000000000000`, then `B_luks_soak_days_invalid` (the overflow bypass is
  closed).
- Given rc 0, then exit 0 and `verdict=PASS` in the summary.
- Given `sse_gate_chain_check` and a stub stderr file with rc 0 but only the `git_data` pass line, or a pass
  line with `none` fields, then return 1 (anti-vacuity).
- Given a forged evidence line with an extra field, then it is replayed to the log and kept out of the summary.
- Given the pristine workflow plus each committed Guard mutation, then the guard goes RED.

Property that must never break: for every soak value string `s`, the gate either refuses, or enforces
`required_s >= 3 * 86400`, and `required_s` equals `10#s * 86400` when it passes (true only with the G1
three-digit cap; an unbounded value wraps).

## Operator Holds

- Hold: Operator-authorizes: every production workflow_dispatch (cf-lb-overlay, host create/replace/destroy, workspaces-luks-verify dispatch) and its web-platform-infra-apply environment approval.
- Hold: Operator-authorizes: deleting WORKSPACES_LUKS_SOAK_DAYS from Doppler prd (#12933) — out of scope of this PR.

This PR itself needs no production act to merge: it changes a gate that only runs on an operator-dispatched
serve.

## Success Metrics

- The next serve dispatch's log and summary show the `SOLEUR_SOAK_EVIDENCE` lines. Until #12933 lands every serve
  refuses at the gate, so the grader step does not run; `SOLEUR_INSTANCE_SOAK` appears only on a serve after
  #12933.
- No serve passes with an effective soak below 3 days or without a grader PASS.

## Dependencies & Risks

- **Must merge before #12869** (web-3; that step keys the marker and grader per host and replaces the F5 host
  refusal with a real per-host check).
- **After merge, serve refuses until #12933** removes the `prd` override (intended).
- **PR #12918** rebase on the same files (Condition A, allowlist count).
- **Residual (G13, #12939):** a replaced web-2 keeps the pool weight the replace found and can take traffic
  without the serve gate chain or the grader; only the drain-first step in `web-host-replace.md` prevents it.
  Ruled by CTO agent, 2026-11-18: the fix ships with #12869, not in this PR (see `decision-challenges.md`).
- **Risk (G12, #12938):** a web-2 older than 90 days cannot re-serve without a replace; intended, and the
  `::error::` names the remedy.
- **Risk:** the anti-vacuity check refuses every serve if the producer grammar drifts; mitigated by the
  single `SOAK_EV_RE` in the helper, sourced by the suite, with positive and negative fixtures (G4, amends F11).
- **Risk:** web-2 telemetry gaps make the grader NOT_YET; intended, visible in the line.

## References & Research

- Issue #12849 (body and CTO ruling comment, 2026-11-18); #12820; #12869; #12933; #12936 (deferral).
- ADR-263 2026-10-08 addendum; ADR-143 D3; ADR-068 §(c).
- Run 44304068922 (gate at 2026-11-18T12:43:37Z), run 44081894988 (marker write).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold
  will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- `SOAK_FLOOR_DAYS` must be assigned as `SOAK_FLOOR_DAYS=3`, never through a `:=` expansion (allowlist parity).
- The gate must not contain a `web-[0-9]` literal on any code line (suite rule); use `$HOST`.
- Do not edit the grader's `SOAK_DAYS=3` line; its mutants anchor on it.
- Keep `p_guard`'s inner-env name set unchanged; adding the stderr redirect after the wrapper path keeps its
  extraction regex matching.
- The new step must not contain the literal `lb-weight-gate.sh` or an assignment of
  `WORKSPACES_LUKS_CUTOVER_AT` (the wrapper census).
- `cf-lb-overlay.yml` must not mention `WORKSPACES_LUKS_CUTOVER_AT` on any code line, in any case, including an
  `::error::` text (comment lines are exempt from the census, but say "the soak marker" there too): the G3 census in `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`
  (`READERS` set) flags any mention outside its reader list, and the workflow must not be added to that list.
  Say "the soak marker" instead. A wiring row asserts the absence (plan review, architecture 2).
- Every `sub_condition=` check in both suites must anchor on the whole `gate_fail sub_condition=<id>` line,
  not only `assert_stderr_contains`: `a1_row_ok` (`GATE_ERR == *"sub_condition=$4"*`), the bind-table check, and
  the five substring checks in `lb-weight-gate-with-marker.test.sh` (`scn_future`, marker-absent,
  soak-not-elapsed, rotation-absent rows). The evidence line carries the same token, so a substring check can
  pass on the evidence line alone (plan review, Kieran 6 / architecture 3). The gate header records
  `^gate_fail sub_condition=` as the only refusal contract; the evidence line is non-authoritative.
- Under `set -euo pipefail`, every `grep` whose no-match is normal must be guarded: the mirror uses
  `grep ... || [[ $? -eq 1 ]]`, counts use `n="$(grep -cE ... "$f" || true)"`, and no pipeline sits inside
  `$( )` in these steps (plan review, Kieran 2).
- Keep the gate step's first line starting `GATE_OUT="$(env DOPPLER_TOKEN=` so the existing C.4-P1m6 mutant
  still lands; the stderr redirect stays inside the `$( )` (outside it does not capture the substitution's
  stderr). Doppler's own stderr lands in the file too; it is replayed and never mirrored.
- Any fixture with gated host `web-3` must add web-3 to the relay roster and its address to the allowlist
  (Condition A `has($HOST)`), and set `SOLEUR_WEB_HOSTS` once #12918 lands, or the gate refuses at Condition A
  and prints zero evidence lines (plan review, Kieran 10 / architecture 7).
- After rebasing on #12918, re-measure `MIN_CASES` (it raises the same line to 357).
- `g3_dbin_ok` (`workspaces-luks-verify-workflow.test.sh`) pins the gate step's wrapper hand-off on comment-stripped,
  continuation-joined code: the exact `env DOPPLER_TOKEN=... DOPPLER_BIN=... bash ".../lb-weight-gate-with-marker.sh"`
  substring once, `lb-weight-gate-with-marker.sh` exactly once and `DOPPLER_BIN` exactly once on code lines. So the
  stderr redirect goes after the wrapper path (`... .sh" 2>"${RUNNER_TEMP}/lb-gate.stderr"`), and no new code line
  in the workflow (helper call, `::error::` text, trap) may name the wrapper file or `DOPPLER_BIN`. Run that suite
  in Phase 5.
- `doppler run --preserve-env` lets an ambient value win, so a soak knob set in the gate step's `env:`, the
  job's `env:`, or an earlier step's `>> "$GITHUB_ENV"` write would reach the wrapper's allowlist without
  touching the inner `-- env` names that `p_guard` reads. A census row asserts no
  `(GIT_DATA|WORKSPACES)_LUKS_SOAK_DAYS` on any non-comment line of `cf-lb-overlay.yml`, with three mutants
  (step env, job env, `$GITHUB_ENV` export), each RED (plan review, sharp-edges 7). Guard 1 Assembly's "a
  workflow pin is the only other way" is read as "any workflow-side setting", which this row covers.
- The full bun battery counts plans declaring `credentials_required`; bump `BASELINE_DECLARED_PROBES` in the
  same commit as this plan, or it goes red (sharp-edges 4).
