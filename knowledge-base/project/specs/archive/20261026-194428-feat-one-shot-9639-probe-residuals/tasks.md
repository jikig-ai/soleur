# Tasks — feat-one-shot-9639-probe-residuals

Derived from `knowledge-base/project/plans/2026-10-26-fix-9639-probe-residuals-plan.md`.
Plan lane: `single-domain` (spec.md absent; engineering-only per the sibling F6 plan).
Closes #9639. Precedents: PR #10637 (nic-guard/zot F6 arm), #10363 (inngest arm).

## Phase 1 — RED tests first

- [x] 1.1 Add F6 block to `apps/web-platform/infra/web-git-data-probe.test.sh` (mirror `inngest-consumer-probe.test.sh:525-666`): static `Exec*` dollar/export-free sweep; real-`ExecStart` launches under `SHELLOPTS=xtrace` and `BASH_ENV` (rc 78, refusal text, secret absent both streams); pre-fix `ExecStart` leak control; stub-`doppler` dispatch row; untraced positive delivery; identity-key + no-key/stray-var/unset-var cells; hostile-key + body-clause tables; four-way `_key_ok` parity; envdump/export/URL-preset/hoist mutants; lookup-after-refusal order row.
- [x] 1.2 Rewire `run_seam`/`run_real`/`run_transport` env injection to `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL` + `GIT_DATA_HEARTBEAT_URL=<synthetic>`; keep a bare-var row as the no-key WARN cell. Raise `MIN_ASSERTS` in the same edit.
- [x] 1.3 Add F7 ordering rows to `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` beside `:176-179`: awk-extract the probe block, assert `soleur-boot-emit` precedes `poweroff -f` and the `rc` detail write exists; fixture emit-after-poweroff and emit-absent rows RED.
- [x] 1.4 Author `apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` (Guard 4, modeled on `ghcr-blocked-alert.test.sh`): emitter-pinned needle, predicate identity, paging semantics, both `-target=` lines, runbook anchor, own-dispatch registration rows, mutation battery (A1-A7).
- [x] 1.5 Run the suites; confirm the new rows fail for the right reasons and `doppler-injection-bound.test.sh` is still green on the unfixed tree.

## Phase 2 — GREEN: F6 residual + F7 emit

- [x] 2.1 `apps/web-platform/infra/web-git-data-probe.sh`: unconditional xtrace refusal (`exit 78`) at top; `_key_ok` byte-identical to siblings; `unset URL; URL=""; KEY_BAD=false; if _key_ok "${GIT_DATA_HEARTBEAT_URL_KEY:-}"; then URL="${!GIT_DATA_HEARTBEAT_URL_KEY:-}"; else KEY_BAD=true; fi` after the refusal; invalid/empty key → value-free key line + existing WARN arm; update `CONFIG IS ENV` comment.
- [x] 2.2 `apps/web-platform/infra/web-git-data-probe.service`: `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-git-data-probe.sh'`; rewrite the EnvironmentFile comment (sibling shape, `web-private-nic-guard.service:23-29`).
- [x] 2.3 `apps/web-platform/infra/doppler-injection-bound.test.sh`: delete the git-data `WRAPPER_ACK_REASONS` entry; pin 1→0; re-scope/delete `drop-wrapper-ack`, `ack-extra-name`, G1.6, G1.10, G1.10b, G1.10c per decision-challenges row 4; update header items 4-5, WRAPPER/INNER_C comments, `:1353-1356` comment; refresh the git-data `ACK_REASONS` reason text (script-side resolution); keep `ACK_CARDINALITY=9` and all floors unchanged — CENSUS lines must match main.
- [x] 2.4 `apps/web-platform/infra/cloud-init.yml`: restructure `if ! probe; then` → `if probe; then :; else rc=$?; …fi`; write `rc=<n>` to `/run/soleur-stage-detail.d/egress_enforce_probe`; `soleur-boot-emit egress_enforce_probe fatal`; keep FATAL stderr line; `poweroff -f`.

## Phase 3 — GREEN: F8 alert

- [x] 3.1 Live-probe the predicate via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` (positive control; settles `dt` vs `time` column) before finalizing the SQL.
- [x] 3.2 `apps/web-platform/infra/betterstack-logs-alerts.tf`: `web_nic_guard_unpinned_url_sql` locals (`SYSLOG_IDENTIFIER='web-nic-guard'` + `position(message,'unpinned_url') > 0`, no host conjunct) + `logtail_exploration` + `logtail_exploration_alert.web_nic_guard_unpinned_url` copying `monitor_send_failed` paging semantics incl. `treat_as_zero`, channels, `critical_alert=false`, escalation ternary, runbook-linked `incident_cause`/`metadata`.
- [x] 3.3 `.github/workflows/apply-web-platform-infra.yml`: two `-target=` lines beside the sibling alerts.
- [x] 3.4 New runbook `knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md` + standing-alarms row in `betterstack-log-query.md`.
- [x] 3.5 `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: exploration `values`-literal count 17→18 + comment.
- [x] 3.6 `.github/workflows/infra-validation.yml`: `run: bash` step for the new suite + `paths:` entries (suite, runbook, .tf).

## Phase 4 — Sweep, ADR, verification

- [x] 4.1 Claim-sweep by noun (`git.data.*wrapper`, `still.*resolve.*wrapper`, `ExecStart.*GIT_DATA`, `not.*fixed.*9639`): update `web-probe-envwrite.sh:46-48`, `web-probe.tf:~128`, scanner headers; mark historical sites.
- [x] 4.2 Amend ADR-202 addendum status line (all four units fixed; wrapper-ack dict drained to 0).
- [x] 4.3 Ratchets: `run-registered-suites.sh` (or the plan's stated subset), `betterstack-send-failed-alert-mutation.test.sh`, `terraform fmt -check`/`validate`, `grep-q-pipe-guard`, `lint-trap-tempfile-ownership`, `guard-vacuity-floor`, C4 tests (`c4-code-syntax`, `c4-render`) — all green, no new deploy-script-tests reds.
- [ ] 4.4 Rebase on the post-#11159 merge-queue fixes when they land; verify AC1-AC9 against the final tree.
