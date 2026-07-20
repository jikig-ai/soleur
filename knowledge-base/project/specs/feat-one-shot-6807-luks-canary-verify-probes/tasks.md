# Tasks — fix(infra): LUKS canary retry + verify readiness & inventory (#6807)

Plan: `knowledge-base/project/plans/2026-07-21-fix-luks-canary-retry-and-verify-readyz-plan.md`
Branch: `feat-one-shot-6807-luks-canary-verify-probes`

> **Phase 2 is a hard gate.** It answers the ground-truth question before any hardening is built.
> **Tests are written RED first** within each phase (`cq-write-failing-tests-before`), not deferred wholesale to Phase 6.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Baseline green: `bash apps/web-platform/infra/{workspaces-luks-freeze,luks-monitor,workspaces-luks-verify}.test.sh`.
- [ ] 0.2 Confirm `git grep -n 'sleep' apps/web-platform/infra/workspaces-luks-harness.sh` is empty and `workspaces-cutover.sh` has no `sleep` today (both verified at plan time — re-confirm on the rebased branch).
- [ ] 0.3 Record baselines: `deploy-script-tests` duration (`.github/workflows/infra-validation.yml:298`, `timeout-minutes: 12`) and the verify job budget (`workspaces-luks-verify.yml:38`, `timeout-minutes: 15`).
- [ ] 0.4 **Measure remaining dead-man budget at the canary** from run `29782780158`: elapsed from `arm_dead_man` (`workspaces-cutover.sh:2128`) to the canary (`:2260`), against `DEAD_MAN_MIN=30` (`:57`). Bounds task 5.3 and AC8.
- [ ] 0.5 Read the `CANARY_OK` reload path (`:2246`, `cleanup()` `:721`); confirm a re-dispatch cannot suppress `rollback()` via stale state.

## Phase 1 — Shared probe helper (`workspaces-luks-emit.sh`)

- [ ] 1.1 Bounded, classifying HTTP probe. **Structural set** (fail fast): `307, 401, 403, 404, 405, 525, 526`. **Everything else retryable** — notably `000, 500, 502, 503, 504, 521, 522, 523, 524, 530`.
- [ ] 1.2 Attempts-bounded knobs with the floor:
      `CANARY_ATTEMPTS="${WORKSPACES_CANARY_ATTEMPTS:-30}"`, `CANARY_INTERVAL_S="${WORKSPACES_CANARY_INTERVAL_S:-3}"`,
      `[ "$CANARY_ATTEMPTS" -ge 1 ] 2>/dev/null || CANARY_ATTEMPTS=1` (catches `=0` and non-numeric; `:-` catches neither).
- [ ] 1.3 Log `(attempt N/M)` per attempt — matches the dominant repo convention (`ci-deploy.sh:1846,1911,1956`).
- [ ] 1.4 readyz classifier — **HTTP status BEFORE body shape**, five arms:
      `200`+`ready:true` ⇒ success · `200`+`ready:false` ⇒ `readyz_not_ready` · `200`+unparseable ⇒ `readyz_unparseable` · `403/404/405` ⇒ `readyz_gate_regression` · no response ⇒ `readyz_unreachable`.
- [ ] 1.5 Extend the envelope (`:62-73`) with `WL_READYZ_WRITABLE`, `WL_READYZ_POPULATED`, `WL_READYZ_CAPACITY`, `WL_WORKSPACE_COUNT`, `WL_WORKSPACE_COUNT_EXPECTED`, `WL_PROBE_LAST_CODE`, `WL_PROBE_ATTEMPTS`, `WL_PROBE_ELAPSED_S`, `WL_PROBE_CLASS` — additive, existing callers emit `unknown`, every value through `_wl_scrub` (`:33`).
- [ ] 1.6 **Do NOT parameterize `op`** — it stays `workspaces-luks-drift` (the sole paging op; see plan §3).
- [ ] 1.7 Header note: this file is the shared leaf helper for the feature, not solely the emitter.

## Phase 2 — Ground-truth gate (probe first) 🚦

- [ ] 2.1 `.github/workflows/workspaces-luks-verify.yml:103`: `/api/health` → `https://app.soleur.ai/health`, wrapped in the Phase 1 retry.
- [ ] 2.2 Set `LUKS_MONITOR_ASSERT_READYZ=1` **via the `.env` already `set -a`-sourced** at `:99` — never through the triple-nested quoting.
- [ ] 2.3 `luks-monitor.sh`: flag-gated readyz assert using the Phase 1 helper.
- [ ] 2.4 `luks-monitor.sh`: **host-side inventory count**, exclusions mirrored from `apps/web-platform/server/session-metrics.ts:19-41` — exclude `.orphaned-*`, `.cron`, `lost+found`, and non-directories. Cross-reference comment on both sides.
- [ ] 2.5 Comparison **fails closed**: `WORKSPACES_COUNT` absent ⇒ non-zero exit + `workspace_count_baseline_missing`. Never a skipped comparison.
- [ ] 2.6 Count command's **stderr redirected host-side** (`2>/dev/null` + separate rc check) so a permission/symlink error never carries a user path across the SSH boundary.
- [ ] 2.7 Emit the mandatory verdict line, e.g. `SOLEUR_WORKSPACES_READYZ ready=… writable=… populated=… workspace_count=… expected=…`.
- [ ] 2.8 **Seed the baseline:** write `WORKSPACES_COUNT=8` to the host state file — the 2026-07-20 cutover predates `persist_state`, so no baseline exists (`grep -rn WORKSPACES_COUNT apps/web-platform/infra/` → zero).
- [ ] 2.9 **Dispatch pre-merge:** `gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes` (workflow already on the default branch, ID `315308438`).
- [ ] 2.10 **Record the verdict in the plan.** Expected `ready=true`, `workspace_count=8`, `expected=8`.
- [ ] 2.11 **STOP CONDITION.** `ready=false` + `WL_READYZ_WRITABLE=false` + `WL_READYZ_CAPACITY` showing full/read-only ⇒ **capacity incident**, not data loss. Count `< 8`, or `ready=false` on a healthy mount ⇒ **data-recovery incident on sole-copy data**: halt and escalate.

## Phase 3 — Freeze harness (`workspaces-luks-harness.sh`)

- [ ] 3.1 **Recording** no-op `sleep` stub that does `rec "sleep $*"` — records the *argument* (model: `nic-wait-gate.test.sh:71-82`). This gives per-arm attribution AND covers `WORKSPACES_CANARY_INTERVAL_S` for free.
- [ ] 3.2 `CURL_CODES` + `READYZ_BODIES` sequenced knobs mirroring `MOUNTPOINT_RCS` (`:173-181`), using the **`${X-default}` unset form** per the discipline at `:283`.
- [ ] 3.3 **Separate index per endpoint arm** — the stub's single `case "$*"` serves both `/health` and `*readyz*`; one shared counter desynchronises the `/health` sequence silently. Inline comment explaining why. Same reasoning applies to the sleep recorder.
- [ ] 3.4 Document saturation semantics inline (`CURL_CODES="521"` ⇒ *always* 521).
- [ ] 3.5 Reconcile with the existing `MOCK_SLEEP_NOOP` idiom (`ci-deploy.test.sh:699`; broadening tracked in #6665) rather than inventing a parallel mechanism.

## Phase 4 — Execution seam for `luks-monitor.sh`

- [ ] 4.1 **Add a sourced-detection guard** to `luks-monitor.sh`, mirroring `workspaces-cutover.sh:1896` (`BASH_SOURCE[0]` vs `$0`). Without it, `source` runs the whole probe from `:64` and the harness's function stubs cannot take effect — the seam is impossible as first written.
- [ ] 4.2 Extend the harness to source and run `luks-monitor.sh` under stubbed `curl`/`doppler`/`findmnt`/`cryptsetup`/`blkid`/`mountpoint`.
- [ ] 4.3 Pin ordering: readyz + inventory asserts run **before** the heartbeat push (`:109-117`), so a failing host does not push a healthy beat. Comment the reason.
- [ ] 4.4 Exit codes: `1` = LUKS drift, `2` = readiness/inventory.

## Phase 5 — `app_canary` retry (`workspaces-cutover.sh`)

- [ ] 5.1 Route both probes (`:663`, `:665`) through the Phase 1 helper. **Pin the loop shape** (whether it sleeps after the final attempt) — ACs derive from it.
- [ ] 5.2 Add `emit_drift health_probe_deadline` / `health_probe_structural` to the `/health` arms, which today call bare `die` and emit nothing to Sentry.
- [ ] 5.3 Cap **combined** canary spend against the task 0.4 measurement, with a hard assertion that worst-case spend + measured pre-canary elapsed `< DEAD_MAN_MIN`. (Worst case is ~480 s for both probes, not 90 s.)
- [ ] 5.4 **Do not move `app_canary` relative to `disarm_dead_man`** (`:2256-2269`, defended by comment).
- [ ] 5.5 `persist_state WORKSPACES_COUNT "$total"` at the C1 gate so future verifies have a baseline.

## Phase 6 — Tests (existing suites only)

`apps/web-platform/infra/workspaces-luks-freeze.test.sh` — every case pins a reason code via `outF 'EMIT_DRIFT: <reason>'` (the stub already echoes, `harness:289`); `died()` alone cannot distinguish structural from deadline. Sleep assertions are **per-arm**, never a global total.

- [ ] 6.1 Add `VERIFY_WF=` beside the existing `WORKFLOW=` (`:25`).
- [ ] 6.2 T23a — `CURL_CODES="521 521 200"` ⇒ `ran` ∧ exactly 2 `/health`-arm sleeps.
- [ ] 6.3 T23b — `CURL_CODES="307"` ⇒ `died` ∧ **zero** sleeps ∧ `health_probe_structural`.
- [ ] 6.4 T23c — `CURL_CODES="530"` ⇒ `died` ∧ sleeps == full bound ∧ `health_probe_deadline` (distinguishes it from T23b, which outcome alone does not).
- [ ] 6.5 T23d — seam-unset: knobs unset, `run_case` **sealed against inherited env** (it uses `env "$@"` without `-i` at `:143`) ⇒ sleeps exactly the **literal** `30`; deriving the number from source is circular.
- [ ] 6.6 T23e — interval seam: every recorded sleep arg is exactly `3` under unset knobs.
- [ ] 6.7 T23f — floor: `WORKSPACES_CANARY_ATTEMPTS=0` **and** `=abc` each still probe ≥ 1 time.
- [ ] 6.8 T24 — readyz arms via `READYZ_BODIES`: recovering ⇒ `ran`; saturating `ready:false` ⇒ `readyz_not_ready`; unparseable ⇒ `readyz_unparseable`; `403` ⇒ `readyz_gate_regression`.
- [ ] 6.9 T25 — `app_canary` precedes `disarm_dead_man` (comment-stripped index comparison).
- [ ] 6.10 Widen the suite's existing `/api/health` gate: **bare** `/api/health` pattern (only `:103` of the seven sites carries `app.soleur.ai`), scope `$CUTOVER $VERIFY_WF`, **not** comment-stripped for the workflow, `/api/health/team-membership` allowlisted.

`apps/web-platform/infra/luks-monitor.test.sh` (on the Phase 4 seam):

- [ ] 6.11 Flag unset ⇒ readyz never probed **and** `ran` (a bare negative passes if the seam aborted early at `not_mounted`).
- [ ] 6.12 Flag set ⇒ readyz **is** probed (paired positive control).
- [ ] 6.13 Count parity fixture containing `lost+found`, `.cron`, `.orphaned-x`, and a stray regular file ⇒ host count equals `countWorkspaceDirsAt`'s result.
- [ ] 6.14 Missing `WORKSPACES_COUNT` ⇒ non-zero exit + `workspace_count_baseline_missing`.
- [ ] 6.15 Count `< expected` ⇒ exit `2` + `workspace_count_shortfall`.
- [ ] 6.16 Verdict line present on the success path.
- [ ] 6.17 Flag-leak guard: the cutover channel writes no `LUKS_MONITOR_ASSERT_READYZ` into `/etc/default/luks-monitor` (`luks-monitor.service:17` reads it with `EnvironmentFile=-`).
- [ ] 6.18 Positive control (dispatch-verified, not shell-suite): with the flag deliberately unset, a second `--ref` dispatch **fails** on the absence of the verdict line.

Hygiene for every new assertion:

- [ ] 6.19 No `cmd | grep -q` under `pipefail` (141 on early match fails **OPEN** on negatives); strip `^[[:space:]]*#` before body-greps; never `[[ cond ]] && cmd` standalone under `set -e`.

## Phase 7 — Docs, model, tracking

- [ ] 7.1 Runbook §5: `/health` 200 + `readyz ready=true` + `workspace_count`; record the **2026-07-20** landing (run `29782780158`) and that §5 was non-functional until this fix.
- [ ] 7.2 Runbook: **verdict → operator action triage table** — LUKS drift / readiness / **capacity (ENOSPC/EROFS)** / count shortfall / baseline missing / structural / gate regression / transport rc 255 / AC-fails-during-ship. Capacity routes to "capacity incident", **never** "data-recovery".
- [ ] 7.3 Runbook: strike the two false heartbeat claims — §5's *"pushes a Better Stack heartbeat; a missed push pages"* and the Failure-signals `betteruptime_heartbeat.workspaces_luks` bullet — marking both `UNFED pending #6808` (`luks-monitor.sh:116`).
- [ ] 7.4 ADR-119 §(a) (`:155-162`): verify-surface extension **and** floor-vs-inventory.
- [ ] 7.5 ADR-119 `:237`: `/api/health` → `/health`.
- [ ] 7.6 `model.c4:186` and `:410`: correct the plaintext-at-rest staleness. Re-run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 7.7 `workspaces-luks-verify.yml` header (`:3`, `:7`, `:84`): reword "MUTATES NOTHING" — `isWorkspacesWritable` write+unlinks a probe file at the workspaces root.
- [ ] 7.8 Workflow prose sweep: `:6`, `:102`, `:104`, `:110`, `:113`, `:160`.
- [ ] 7.9 Add the rc `255` transport arm so the error stops pointing at a Sentry event that was never emitted.
- [ ] 7.10 File the deferred daily-readyz issue with the **corrected** framing (steady-state only; the reboot hazard is structurally covered by `chattr +i` + the `RequiresMountsFor` drop-in). Note that flipping it ON would also require revisiting the soak query.
- [ ] 7.11 Consider renaming `workspaces-luks-verify.test.sh` (it covers `verify_byte_identity`, not the workflow).

## Exit

- [ ] E.1 All ACs (AC1–AC19) in the plan verified.
- [ ] E.2 `WORKSPACES_LUKS_HEARTBEAT_URL` absent from the diff — #6808 stays out.
- [ ] E.3 PR body uses `Closes #6807` (`wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] E.4 `ship` renders `decision-challenges.md` into the PR body and files the `action-required` issue.
