# Tasks — feat-one-shot-6588-luks-freeze-quiesce

Derived from
[`knowledge-base/project/plans/2026-07-19-fix-workspaces-luks-freeze-quiesce-redis-g4-canary-plan.md`](../../plans/2026-07-19-fix-workspaces-luks-freeze-quiesce-redis-g4-canary-plan.md)
(post-deepen). `Ref #6588` — not `Closes`.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> All service state-changes below are **program logic inside
> `apps/web-platform/infra/workspaces-cutover.sh`**, executed by the
> `workspaces-luks-cutover.yml` workflow dispatch. No task asks an operator to shell into a host.

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 Re-read `workspaces-cutover.sh` anchors: `:458-472` (freeze), `:254-267` (rollback),
      `:294-310` (dead-man), `:549-591` (success/canary). Confirm before editing.
- [x] 0.2 Confirm the sourced-detection guard is at `:288`; `rollback()` (`:254`) is above it,
      the freeze block (`:458`) is below it (hence the extraction in Phase 2).
- [x] 0.3 Re-run the pipefail/SIGPIPE reproduction; confirm G4-b holds on the build agent.
- [x] 0.4 Confirm `middleware.ts:113` `/health` early-return is still the sole exemption.
- [x] 0.5 Confirm no CI drift guard extracts service verbs from `apps/web-platform/infra/*.sh`.

## Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

- [x] 1.1 Create `apps/web-platform/infra/workspaces-luks-freeze.test.sh` using the
      `workspaces-luks-verify.test.sh` harness idioms (`SCRIPT_DIR`/`CUTOVER` prelude,
      `ok()`/`no()` counters, `[ "$fail" -eq 0 ]` exit).
- [x] 1.2 Implement `run_case`-style `bash -c 'source "$CUTOVER"; <stubs>; <call>'` subshells with
      `systemctl`/`docker`/`lsof`/`mount`/`curl` overridden as shell functions **after** `source`,
      each recording argv to a calls file.
- [x] 1.3 Implement the `mutate()` sed-copy helper including the M4-style did-the-sed-land guard.
- [x] 1.4 Write T1-T14 (see plan `## Test Scenarios`). Confirm T1-T13 are RED against `main`.

## Phase 2 — Extract the freeze/resume seams

- [x] 2.1 Add `QUIESCE_UNITS="webhook.service inngest-redis.service"` as the single declaration
      point. **Do not** include `inngest-server.service` (deepen reversal — it cannot write
      `/mnt/data` and costs up to 180 s).
- [x] 2.2 Extract `freeze_writers()` **above** the `:288` guard: stop `webhook`, then the
      container (`-t 120`), then `inngest-redis`; `persist_state QUIESCED_UNITS`.
- [x] 2.3 Widen the generic straggler/lock sweep to the whole mount (`"$MOUNT"/*/`), retaining the
      `.git`-specific asserts under `workspaces/*/`.
- [x] 2.4 Add `ensure_lsof()` mirroring `ensure_aws()` (`:92-107`) — idempotent install; **abort**,
      never skip, if `lsof` is still absent afterwards.
- [x] 2.5 Replace G4 with the capture-to-variable form (no pipe — pipefail/SIGPIPE) plus
      `emit_freeze_holders` before `die`.
- [x] 2.6 Add `emit_freeze_holders()` mirroring `emit_verify_diff`: `_vscrub`, cap, emit
      `SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER` to run log + `logger -t "$LUKS_LOG_TAG"`, then
      `emit_drift freeze_straggler_holds_mount`.
- [x] 2.7 Extract `resume_writers()` above the guard: start quiesced units in reverse order after
      the mount; clear failed state before each start; assert active + `emit_drift` on failure.
- [x] 2.8 Add the post-freeze `inngest-server` reconcile inside `resume_writers()` (clear failed
      state; start only if not active; `emit_drift inngest_server_not_active` on failure).

## Phase 3 — Wire restore into all three exit paths

- [x] 3.1 Success path (`:549-591`) — call `resume_writers()` after the mapper mount + container start.
- [x] 3.2 `rollback()` (`:254-267`) — call `resume_writers()` after the plaintext remount,
      replacing the bare container + webhook restarts. Covers the EXIT trap and `ROLLBACK=1`.
- [x] 3.3 Dead-man `systemd-run` command (`:294-306`) — also start `inngest-redis.service` (and
      idempotently `inngest-server.service`). Keep the command self-contained (`:296-298`).

## Phase 4 — Canary URL

- [x] 4.1 Extract `app_canary()` above the `:288` guard.
- [x] 4.2 Point it at `https://app.soleur.ai/health`; update the `die` message string to match.

## Phase 5 — dry_run description + dry-run holder probe

- [x] 5.1 Rewrite `.github/workflows/workspaces-luks-cutover.yml:37` `description:` — state what the
      rehearsal covers (L3 gates, `prepare_luks_target`, escrow proof + R2 probe, G2 manifest) and
      what it does not (no bulk rsync, no freeze, no delta rsync, **no C1 verify**, no repoint,
      no wipe). Must contain the literal `no C1 verify` (AC9).
- [x] 5.2 Add the dry-run-arm advisory holder probe (`ensure_lsof` + holder capture, log-only,
      never fatal in the `DRY_RUN=1` arm).

## Phase 6 — ADR addendum, CI registration, cloud-init

- [x] 6.1 Write the ADR-119 **Addendum 2026-07-19 (#6588 freeze-quiesce)** — restated quiesce set
      naming `inngest-redis.service`, the fail-closed self-delivering straggler assert, and the
      three-exit-path restore invariant.
- [x] 6.2 Register `workspaces-luks-freeze.test.sh` as its own step in
      `.github/workflows/infra-validation.yml` (near `:381`). **Load-bearing** — the job lists
      tests explicitly; an unregistered file is zero coverage.
- [x] 6.3 Add `lsof` to `apps/web-platform/infra/cloud-init.yml` packages (future hosts).

## Phase 7 — GREEN + full suite

- [x] 7.1 `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh` — all green.
- [x] 7.2 `bash apps/web-platform/infra/workspaces-luks-verify.test.sh` — still green (AC10).
- [x] 7.3 Run sibling static guards: `luks-monitor.test.sh`, `workspaces-luks.test.sh`,
      `workspaces-luks-header.test.sh` (they grep this script; the refactor moves lines).
- [x] 7.4 Verify AC1-AC13 mechanically (see plan `## Acceptance Criteria`).
- [x] 7.5 Confirm AC11: `git diff main -- apps/web-platform/infra/workspaces-cutover.sh` shows no
      change inside `verify_byte_identity()` / `emit_verify_diff()`.

## Deviations from the plan (recorded at /work)

- **`luks-monitor.timer` is quiesced** (plan Sharp Edges said "consider"). It is
  `RequiresMountsFor=/mnt/data` and armed by a prior successful cutover, so on a re-dispatch it can
  hold the mount and trip the newly fail-closed G4 — an abort on our own monitor. Stopped
  best-effort in `freeze_writers()`, restarted in `resume_writers()`.
- **Added T15 + mutation twin M5 (stop/restore symmetry)** — not in the plan's T1-T14. The first
  implementation stopped `webhook.service` unconditionally but restored only `$QUIESCE_UNITS`, so an
  override omitting webhook would leave it down. Both sides now drive off `_quiesce_list()`.
- **Harness scratch moved to one per-run directory.** The plan's harness shape (loose `mktemp` per
  case, mirroring `workspaces-luks-verify.test.sh`) proved flaky under concurrent load: files were
  removed mid-run, so `cat` returned empty and assertions reported phantom SUT regressions
  (T4/T4b/T5/T9 failing in 3 different combinations across 5 runs). A missing scratch file now
  reports as a HARNESS error rather than as evidence.
- **Harness asserts each function under test is DECLARED before running it.** Without this, the
  "must exit non-zero" cases (T7/T8) passed vacuously against `main`, where the functions do not
  exist at all — the subshell failed for the wrong reason and the gate read green while testing
  nothing. Two further vacuity bugs were caught the same way: a multi-MB `LSOF_OUT` exceeded the
  `env` argv limit (E2BIG) so T8 never ran, and the `lsof` stub's hardcoded `return 0` swallowed the
  producer SIGPIPE that mutation M3 exists to reproduce.
- **AC5's grep excludes comment lines.** The `freeze_writers()` body documents the
  `lsof | grep -q .` trap in prose, so a bare body-grep matched its own explanation and false-FAILed
  a correct implementation (`cq-assert-anchor-not-bare-token`).
