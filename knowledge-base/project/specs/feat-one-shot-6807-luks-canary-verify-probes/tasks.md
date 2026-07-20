# Tasks — fix(infra): LUKS canary retry + verify readiness & inventory (#6807)

Plan: `knowledge-base/project/plans/2026-07-21-fix-luks-canary-retry-and-verify-readyz-plan.md`
Branch: `feat-one-shot-6807-luks-canary-verify-probes`

> **Phase 2 is a hard gate.** It answers the ground-truth question before any hardening is built. If it reports `ready=false` or a workspace count below the expected value, STOP — that is a data-recovery incident on sole-copy data, not a monitoring project.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Baseline green: `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh`, `luks-monitor.test.sh`, `workspaces-luks-verify.test.sh`.
- [ ] 0.2 Confirm `git grep -n 'sleep' apps/web-platform/infra/workspaces-luks-harness.sh` is empty, and `workspaces-cutover.sh` has no `sleep` today.
- [ ] 0.3 Record baselines: `deploy-script-tests` duration (`.github/workflows/infra-validation.yml:298`, `timeout-minutes: 12`) and the verify job budget (`workspaces-luks-verify.yml:38`, `timeout-minutes: 15`).
- [ ] 0.4 **Measure remaining dead-man budget at the canary** from run `29782780158`: elapsed from `arm_dead_man` (`workspaces-cutover.sh:2128`) to the canary step (`:2260`). `DEAD_MAN_MIN=30` (`:57`). This bounds task 5.3.
- [ ] 0.5 Read the `CANARY_OK` state-reload path (`:2246`, `cleanup()` `:721`); confirm a re-dispatch cannot suppress `rollback()` via stale state.

## Phase 1 — Shared probe helper (`workspaces-luks-emit.sh`)

- [ ] 1.1 Add the bounded, classifying HTTP probe. **Structural set** (fail fast, no retry): `307, 401, 403, 404, 405, 525, 526`. **Everything else retryable** — notably `000, 500, 502, 503, 504, 521, 522, 523, 524, 530`.
- [ ] 1.2 Bound by **attempts**, not wall clock: `CANARY_ATTEMPTS="${WORKSPACES_CANARY_ATTEMPTS:-30}"`, `CANARY_INTERVAL_S="${WORKSPACES_CANARY_INTERVAL_S:-3}"`, plus the floor `[ "$CANARY_ATTEMPTS" -ge 1 ] || CANARY_ATTEMPTS=1` (the real silent-disable hazard is `=0`, which `:-` does not catch).
- [ ] 1.3 Add the readyz **three-way** classifier: `ready:true` / retryable-not-ready / **structural-unparseable** (distinct reason `readyz_unparseable`, so a proxy error page is never reported as data loss).
- [ ] 1.4 Extend the Sentry envelope (`:62-73`) with `WL_READYZ_WRITABLE`, `WL_READYZ_POPULATED`, `WL_WORKSPACE_COUNT` — additive; existing callers emit `unknown`. Route every value through `_wl_scrub` (`:33`).
- [ ] 1.5 Add a distinct Sentry `op` for readiness (`workspaces-readiness-drift`) so the DP-8 alert does not page "at-rest encryption drift" for a readiness blip.
- [ ] 1.6 Header note: this file is the shared leaf helper for the feature, not solely the emitter.

## Phase 2 — Ground-truth gate (probe first) 🚦

- [ ] 2.1 `.github/workflows/workspaces-luks-verify.yml`: `/api/health` → `https://app.soleur.ai/health` (`:103`), wrapped in the Phase 1 retry.
- [ ] 2.2 Set `LUKS_MONITOR_ASSERT_READYZ=1` **via the `.env` that is already `set -a`-sourced** at `:99` — not through the triple-nested quoting.
- [ ] 2.3 Add the host-side workspace **count** (integer only — no listing, no directory names).
- [ ] 2.4 `luks-monitor.sh`: flag-gated readyz assert using the Phase 1 helper, emitting the mandatory verdict line (e.g. `SOLEUR_WORKSPACES_READYZ ready=… writable=… populated=… workspace_count=…`).
- [ ] 2.5 **Dispatch pre-merge:** `gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes` (feasible — the workflow already exists on the default branch, ID `315308438`).
- [ ] 2.6 **Record the verdict in the plan.** Expected `ready=true`, `workspace_count=8`.
- [ ] 2.7 **STOP if `ready=false` or count `< 8`.** Escalate; do not build the remaining phases.

## Phase 3 — Freeze harness (`workspaces-luks-harness.sh`)

- [ ] 3.1 Recording no-op `sleep` stub (model: `nic-wait-gate.test.sh:71-82`), reconciled with the repo's `MOCK_SLEEP_NOOP` idiom (`ci-deploy.test.sh:699`; broadening tracked in #6665) rather than a parallel mechanism.
- [ ] 3.2 `CURL_CODES` sequenced knob mirroring `MOUNTPOINT_RCS` (`:173-181`), **with a separate index per endpoint arm** — the stub's single `case "$*"` serves both `/health` and `*readyz*`, so one shared counter desynchronises the `/health` sequence silently. Inline comment explaining why.
- [ ] 3.3 Document saturation semantics inline (`CURL_CODES="521"` ⇒ *always* 521) — the timeout-arm tests depend on it.
- [ ] 3.4 Do **not** add `READYZ_BODIES`; readyz routes through the same helper. Do not "normalise" the existing `${READYZ_BODY-…}` unset form at `:283` — it is deliberate.

## Phase 4 — Execution seam for `luks-monitor.sh`

- [ ] 4.1 Extend the harness to source and run `luks-monitor.sh` under stubbed `curl`/`doppler`/`findmnt`/`cryptsetup`/`blkid`/`mountpoint`. (`luks-monitor.test.sh` is static-only today — without this, "flag unset ⇒ never probes" degrades to a grep that passes on dead code.)
- [ ] 4.2 Pin ordering: the readyz assert runs **before** the heartbeat push (`luks-monitor.sh:109-117`), so a `ready=false` host does not push a healthy beat. Comment the reason.
- [ ] 4.3 Distinct exit codes: `1` = LUKS drift, `2` = readiness.

## Phase 5 — `app_canary` retry (`workspaces-cutover.sh`)

- [ ] 5.1 Route both probes (`:663`, `:665`) through the Phase 1 helper. **Pin the loop shape** (does it sleep after the final attempt?) — the ACs derive from it.
- [ ] 5.2 Add `emit_drift health_probe_deadline` / `health_probe_structural` to the `/health` arms, which today call bare `die` and emit nothing to Sentry.
- [ ] 5.3 Cap **combined** canary spend against the task 0.4 measurement (worst case is ~480 s for both probes, not 90 s).
- [ ] 5.4 **Do not move `app_canary` relative to `disarm_dead_man`** (`:2256-2269` — defended by an explicit comment).
- [ ] 5.5 `persist_state WORKSPACES_COUNT "$total"` at the C1 gate so future verifies have a machine-checkable expected inventory.

## Phase 6 — Tests (existing suites only)

`apps/web-platform/infra/workspaces-luks-freeze.test.sh`:

- [ ] 6.1 Add `VERIFY_WF=` beside the existing `WORKFLOW=` (`:25`).
- [ ] 6.2 T23a — recovers through the loop: `CURL_CODES="521 521 200"` ⇒ `ran` ∧ `1 ≤ sleeps < bound`.
- [ ] 6.3 T23b — structural fail-fast: `CURL_CODES="307"` ⇒ `died`, **zero** sleeps (Bug A regression guard).
- [ ] 6.4 T23c — retryable-unknown fails safe: `CURL_CODES="530"` ⇒ retried, not fast-failed.
- [ ] 6.5 T23d — timeout arm runs the full bound (count per the task 5.1 loop shape).
- [ ] 6.6 T23e — seam-unset: knobs **unset** ⇒ never-recovering probe uses exactly the production attempt count.
- [ ] 6.7 T23f — attempts floor: `WORKSPACES_CANARY_ATTEMPTS=0` still probes ≥ 1 time.
- [ ] 6.8 T24 — readyz unparseable body ⇒ `readyz_unparseable`, not `readyz_not_ready`.
- [ ] 6.9 T25 — `app_canary` precedes `disarm_dead_man` (comment-stripped index comparison).
- [ ] 6.10 Widen AC7's gate: bare `/api/health` pattern (only one of the six sites carries `app.soleur.ai`), scope `$CUTOVER $VERIFY_WF`, **not** comment-stripped for the workflow, `/api/health/team-membership` allowlisted.

`apps/web-platform/infra/luks-monitor.test.sh` (on the Phase 4 seam):

- [ ] 6.11 Flag unset ⇒ readyz never probed.
- [ ] 6.12 Flag set + `ready:false` ⇒ exit `2` + `readyz_not_ready`.
- [ ] 6.13 Verdict line present on the success path.
- [ ] 6.14 Flag-leak guard: the cutover channel writes no `LUKS_MONITOR_ASSERT_READYZ` into `/etc/default/luks-monitor` (`luks-monitor.service:17` reads it with `EnvironmentFile=-`).
- [ ] 6.15 Positive control: with the flag deliberately unset, the **workflow** fails on the absence of the verdict line.

Hygiene for every new assertion:

- [ ] 6.16 No `cmd | grep -q` under `pipefail` (141 on early match fails **OPEN** on negatives); strip `^[[:space:]]*#` before body-greps; never `[[ cond ]] && cmd` standalone under `set -e`.

## Phase 7 — Docs, model, tracking

- [ ] 7.1 Runbook `workspaces-luks-cutover-6604.md` §5: `/health` 200 + `readyz ready=true` + `workspace_count`; record the **2026-07-20** landing (run `29782780158`) and that §5 was non-functional until this fix.
- [ ] 7.2 Runbook: add a **verdict → operator action triage table** covering LUKS drift / readiness / count shortfall / structural / transport rc 255 / AC-fails-during-ship (`hr-no-ssh-fallback-in-runbooks` forbids the usual escape hatch).
- [ ] 7.3 ADR-119 §(a) (`:155-162`): the verify-surface extension **and** floor-vs-inventory.
- [ ] 7.4 ADR-119 `:237`: `/api/health` → `/health`.
- [ ] 7.5 `model.c4:186` and `:410`: correct the plaintext-at-rest staleness (cutover landed 2026-07-20). Re-run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 7.6 `workspaces-luks-verify.yml` header (`:3`, `:7`, `:84`): reword "MUTATES NOTHING" — `isWorkspacesWritable` write+unlinks a probe file at the workspaces root.
- [ ] 7.7 Workflow prose sweep: `:6`, `:102`, `:104`, `:110`, `:113`, `:160`.
- [ ] 7.8 Add the rc `255` transport arm to the workflow's error branch so it stops pointing at a Sentry event that was never emitted.
- [ ] 7.9 File the deferred daily-readyz issue with the **corrected** framing (steady-state only; the reboot hazard is structurally covered by `chattr +i` + the `RequiresMountsFor` drop-in).
- [ ] 7.10 Consider renaming `workspaces-luks-verify.test.sh` (it covers `verify_byte_identity`, not the workflow).

## Exit

- [ ] E.1 All ACs in the plan's Acceptance Criteria verified.
- [ ] E.2 `WORKSPACES_LUKS_HEARTBEAT_URL` absent from the diff — #6808 stays out.
- [ ] E.3 PR body uses `Closes #6807` (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] E.4 `ship` renders `decision-challenges.md` into the PR body and files the `action-required` issue.
