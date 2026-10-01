---
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-28-fix-luks-deadman-host-canary-disarm-and-snapshot-411798619-release-plan.md
issue: 9045
---

# Tasks — LUKS residuals (#9045, #8734, fstab, #8706)

## 1. Setup

- 1.1 Re-read the plan's `## Plan Review Revisions` and `decision-challenges.md`.
- 1.2 Re-verify `workspaces-luks-deadman` consumers (`git grep -n workspaces-luks-deadman`) and the suites that load the cutover script (`git grep -l workspaces-cutover.sh`).

## 2. #8734 — release snapshot 411798619 (Phase 1; production write, per-command go-ahead)

- 2.1 Read-only evidence re-pull: image GET, every page of server actions, image actions, and `GET /v1/servers`. Assert (a)–(e) as `jq` expressions.
- 2.2 Write the scratch delete script: identity re-read → DELETE (204) → GET (404) → post-DELETE re-pull re-assert. Name the failure branches. Refuse under xtrace, pass the token on stdin (`--config -`), never use `-v`, post only `jq` fields, and have the script delete itself.
- 2.3 Show the exact command and wait for the per-command go-ahead. Then run it.
- 2.4 Post the #8734 evidence comment, opened with `<!-- soleur:snapshot-411798619-deleted -->`. Post linking comments on PR #8626 (rebase order, ledger flip, `SNAPSHOTS` drop, PA-8 (f)), #6178 and #8632 (correction).
- 2.5 After the DELETE only: edit the prior-exposure assessment (L3 in-cell, Superseded marker, addendum), the breach-register row plus Corrections section, the compliance-posture row, and the ADR-100 2026-09-28 addendum.
- 2.6 Record the credential dispositions, scoped to the image route, with a blanket line for the other root-disk secret classes. Record whether `HCLOUD_TOKEN` was readable. File the go-ahead-gated token-route issue covering Stripe, the service-role key, BYOK, and the other prd values.
- 2.7 No go-ahead: comment the prepared command, label #8734 `action-required`, and leave the records unedited. Add `scripts/followthroughs/snapshot-411798619-expiry-8734.sh` plus its test (marker-keyed, no new secret) and enroll it with `earliest=2026-10-06T00:00Z`.
- 2.8 Run `soleur:legal:legal-compliance-auditor` across the three records and the #8632 comment.

## 3. #9045 — dead-man disarm at the host canary (Phase 2, TDD)

- 3.1 RED — harness (`workspaces-luks-harness.sh`), then the instrument control (existing pass counts unchanged). Add:
  - per-unit, per-property `systemctl show` through `_seq_next`;
  - a GC model where the last event per exact unit wins and `systemd-run` revives;
  - the `DEADMAN_STOP_INEFFECTIVE` knob;
  - `SYSTEMD_RUN_RC`/`SYSTEMD_RUN_OUT`;
  - `logger` and `EMIT_DRIFT` recorded in `$CALLS`, with existing patterns re-anchored;
  - `LastTriggerUSec` defaulting to empty;
  - the stub self-test.
- 3.2 RED — `workspaces-luks-freeze.test.sh`: T30–T33 (with T30b and T32b), T35–T38 (with T35b/c/d, T36a–d, T37b/c), T40, and T25'/T25c/T25d/T39. Every invocation sets `DRY_RUN=0`, and cleanup cases inject `(exit 9)`. Invert T25/T25b. Record the failing IDs.
- 3.3 RED — `luks-monitor.test.sh` (x): the marker set.
- 3.4 GREEN — `workspaces-cutover.sh`, covering:
  - the `DEADMAN_ARMED` global;
  - `arm_dead_man` (refuse, pre-clear, un-swallowed `systemd-run --description`, early flag, bounded waiting check);
  - the arm before `FREEZE_HELD`;
  - a status-returning `disarm_dead_man` in (a) → stop → (b) → reset-failed → (c) order;
  - `rollback` (dead-man first: attempt-bounded fire wait, then a disarm gated on `DEADMAN_ARMED`, then unmount/remount);
  - the host-canary population assert (`WORKSPACES_COUNT` on `$MOUNT`), then the disarm, then the `findmnt` re-assert;
  - the post-`app_canary` disarm deleted;
  - `cleanup` outcome markers, and the roll-forward after a mapper re-assert, with a checked `docker start`;
  - the post-canary drift;
  - markers echoed and logged;
  - `detail=` scrubbed with `LC_ALL=C`, cut to 200 characters, `=` mapped to `_`, placed last, and never sent to Sentry;
  - the green log-line reboot pointer.
- 3.5 Update `tests/scripts/test-workspaces-luks-cutover-gate.sh` Q3/Q4 stubs (`systemctl`, `emit_drift`).
- 3.6 Add the real-systemd case to `workspaces-luks-loopback.test.sh`:
  - H1 reproduction, with stderr naming the collision;
  - success after the exact clear-out;
  - measured post-finish unit states recorded;
  - a throwaway unit, with an EXIT trap and a leftover check.
- 3.7 Terraform:
  - `local.luks_monitor_forensic_print` as a guarded read-only step BEFORE the exit-17 step, folded into `triggers_replace`: exact-field fstab select, a one-key `apt-config shell`, an argv-only `ExecStart` hash, no journalctl, and no env-file reads;
  - plus `logtail_exploration_alert.workspaces_luks_deadman_fired` in `betterstack-logs-alerts.tf`, with its `*-alert.test.sh`.
- 3.8 `luks-monitor-install.test.sh`: `inline_raw()` resolves locals. Add the G-rows, the mutation rows, and the wider DIAG_OK deny list.
- 3.9 Bump `BASELINE_DECLARED_PROBES` 32 → 33, with its comment.

## 4. Docs and ADRs

- 4.1 ADR-119: the 2026-09-28 addendum, with Superseded/Qualified markers in place.
- 4.2 ADR-154: `Re-examined 2026-09-28` note (re-measure `cx33` via `GET /v1/datacenters`).
- 4.3 Runbook `workspaces-luks-cutover-6604.md`: the §3 blockquote, step 4's reboot pointer, and the four triage rows (fix-forward only for the post-canary one).

## 5. fstab (Phase 3)

- 5.1 File the P1 reboot-path issue in plain words, with its measured facts, before ship. Verify the labels exist first.

## 6. Verification

- 6.1 Pre-merge: AC1–AC10, AC15 and AC16. Run markdownlint, `lint-infra-no-human-steps.py --changed`, `lint-guard-contract.py`, `c4-count-parity.test.sh` and `terraform validate`.
- 6.2 Post-merge (Phase 5): watch the apply run, read the forensic print, and post the H1/H2 verdict on #9045 and the fstab facts on the new issue (AC11, AC12).
- 6.3 Close #8734 explicitly only when AC13 holds.
- 6.4 From 2026-10-01: #8706 sweeper check (AC14).
