# Tasks: sandbox post-incident follow-ups (#10453, #10454, #10455)

Plan: `knowledge-base/project/plans/2026-10-19-fix-sandbox-incident-followups-plan.md`. PR body: `Closes #10453`, `Closes #10454`, `Ref #10455`.
Write each phase's RED tests before its code. Commit order: Phase 1 first, Phase 5 last, readback retirement the very last commit.

## Phase 0: Go/no-go measurements (before editing)

- [ ] 0.1 Re-read the CTO rulings in `decision-challenges.md`
- [x] 0.2 `io_uring_setup` blocked by the container profile? If not, can ENOSYS be added to the variant cheaply? (Phase 4 go/no-go) - GO: the committed run-tuple profile (default-deny allowlist, no io_uring_* name) returns EPERM; live docker measurement with an unconfined positive control; no ENOSYS rule needed; recorded in the plan's Work-phase measurements
- [x] 0.3 Logs-alert count and free-tier cap; is there a Sentry rule on `op=sandbox-canary`? (Phase 3 fallback decision) - live read 2026-10-19: 17 alerts apply (16 managed + 1 hand-made), cap undocumented and at least 17, so no fallback trigger; no Sentry rule on `op=sandbox-canary` in IaC (live rules unreadable with the read-only tokens); recorded in the plan's Work-phase measurements and ADR-218
- [ ] 0.4 Heartbeat period floor (`/fail` support is CONFIRMED by the vendor docs, 2026-10-19; append `/fail` to the host's own heartbeat URL); prod container memory headroom for one SDK CLI spawn; `cloud-init.yml` user_data size headroom (Phase 5 go/no-go)
- [x] 0.5 Does the tool_result observer's `block` carry an error flag? Helper step order: which of the 14 steps run before the worker fork (Phase 2)
- [x] 0.6 `bash plugins/soleur/test/c4-count-parity.test.sh` green baseline; list the five callers of `buildAgentSandboxConfig`/`buildAgentEnv`

## Phase 1: Demote the outer-wrap canary (#10454)

- [x] 1.1 RED: absence rows in `ci-deploy.test.sh` and `cat-deploy-state.test.sh`; repo-wide `git grep` absence row
- [x] 1.2 `ci-deploy.sh`: delete `run_outer_wrap_canary`, its call, state-file and alias blocks; leave the retirement comment
- [x] 1.3 `cat-deploy-state.sh`: delete `outer_wrap_canary_json` and the merge key; update `sandbox-canary-soak.test.sh`
- [x] 1.4 Delete `tenant-outer-wrap-soak-5863.sh` and `.test.sh` with their `test-all.sh`, bearer-sweep and both shard-TSV-pair entries in the same commit
- [x] 1.5 Keep `--replay-outer`, fixture, classifier, docker-suite arm, `--smoke-outer`; name each kept piece's consumer
- [x] 1.6 `canary-probe-set.md` retirement note (dated re-evaluate trigger 2026-12-19 or #9773 Stage 1); `workspace-isolation-canary-probe.md`; ADR-079 addendum (`Ruled by CTO agent, 2026-10-19: DEMOTE`)
- [ ] 1.7 Agent-executed at ship: close #9797 (won't-fix), resolve Sentry issue 152662657, comment on #9773

## Phase 2: Classifier, notice, directive (#10455 c, e)

- [x] 2.1 RED tests: classifier (15 steps + userns [16 measured, not 14], EACCES/EINVAL unclassified, tail unclassified, mixed/multi-line/non-error/`waitpid` no notice, allowlist subset of vendored binary with non-skipped floor)
- [x] 2.2 `sandbox-startup-classifier.ts`: `HELPER_STEPS`, `helper_step_eperm`, `isPreExecSandboxDenialOutput`
- [x] 2.3 `cc-dispatcher.ts`: mirror first, then notice rewrite behind the autonomous gate; `BASH_UNAVAILABLE_PROMPT_DIRECTIVE` (raw-line keyed, idempotent-only retry once, 403 carve-out)
- [x] 2.4 `betterstack-logs-alerts.tf` IN list; `sandbox-alerts.test.sh` both code needles; `betterstack-log-query.md` row

## Phase 3: Deploy-time SDK Bash smoke (#10453)

- [x] 3.1 RED: probe verdict table (pass / failed / dispatched-hung / infra / replay_only), parity test `sdk-bash-probe-parity.test.ts`, `ci-deploy.test.sh` rows (both orderings, canary-only, atomic ledger, stale warning at 3, no rollback)
- [x] 3.2 `sdk-bash-probe.mjs` smoke mode; Dockerfile COPY + `.dockerignore` bang
- [x] 3.3 `ci-deploy.sh` `run_sdk_bash_smoke`, ledger via `write_sandbox_canary_state` extra-JSON arg, call after `run_faithful_sandbox_canary || true`
- [x] 3.4 `cat-deploy-state.sh` `sdk_bash_smoke_json` and tests
- [x] 3.5 Alert `faithful_canary_sandbox_broken` (+ `-target` lines, `faithful-canary-sandbox-alert.test.sh`, infra-validation step, mutation-count bump, runbook, ADR-218 amendment incl. stale step-count fix)
- [x] 3.6 `sdk-bash-smoke-verdict-10548.sh` + test + registrations + `BASELINE_DECLARED_PROBES` 70 to 71
- [x] 3.7 `canary-probe-set.md` SDK-smoke section implemented; post-merge positive-control query documented

## Phase 4: AF_UNIX variant behind a runtime flag (#10455 a)

- [ ] 4.1 RED: interpreter-level cases, golden-bytes base artifact, dispatcher agreement test (both egress values, both flag states), call-site census, flag-default-OFF test, shim exit 65 on unreadable alternate
- [ ] 4.2 Restructure `gen-bwrap-userns-seccomp.mjs` into builders (`emit()` exported); `--variant unixdeny`; commit `bwrap-userns-clone3-unixdeny.bpf`; `--check` both
- [ ] 4.3 `seccompArtifactFor`; `buildAgentSandboxConfig`; conditional selector in `buildAgentEnv`; sweep the five callers; spawn-time assertion; `probeAgentSandboxHardening` both artifacts
- [ ] 4.4 Create flag `agent-sandbox-unix-deny` with `soleur:flag-create` (default OFF)
- [ ] 4.5 Dockerfile/.dockerignore bake; canary hardening probe checks it
- [ ] 4.6 Real-SDK and run-tuple tests (no-egress ON, egress, flag OFF; non-skipped-row floor); vendored-argv-tail pins
- [ ] 4.7 ADR-075 addendum superseding the 2026-10-16 statements; release-notes and support-runbook line
- [ ] 4.8 Post-merge, operator-authorized: enable the flag after a green deploy smoke (tracked in #10548)

## Phase 5: Runtime synthetic (#10455 b), objective cut line

- [ ] 5.1 Apply the cut trigger (over 100 files or more than three parity suites red after one CI cycle moves this phase to a stacked PR)
- [ ] 5.2 RED: `web-bash-synthetic.test.sh` (lock held, container not Running, race with `docker stop`, failed run never pings success URL, nonce mismatch)
- [ ] 5.3 `web-bash-synthetic.{sh,service,timer}`; `OnBootSec=90s`; Source 4 retag in `vector.toml`
- [ ] 5.4 `web-probe.tf` heartbeat (period 900, grace 900) and Doppler secret; `server.tf` provisioner pair; `cloud-init.yml`; `soleur-host-bootstrap.sh`; `web-probe-envwrite.sh`; `web-probe-read-token.tf`
- [ ] 5.5 Registrations: `heartbeat-manifest.ts`, `arm-heartbeats.sh` (+ test, explicit `arm_one`), `terraform-target-parity`, `heartbeat-live-reconcile`, `heartbeat-reprovision-parity`, `fresh-boot-parity`, `web-host-provisioner-parity` (exact-bump rows), `cloud-init-user-data-size`, `validate-infra-templates.sh`, `web-host-birth-gate`, `guard-vacuity-floor`, shard TSVs
- [ ] 5.6 `-target` lines (main plan unkeyed, per-host keyed dispatch lines)
- [ ] 5.7 `canary-probe-set.md` runtime-synthetic section

## Phase 6: Slack wake check (#10455 d)

- [ ] 6.1 One read-only `slack-integrations` call plus the Logs alerts' escalation targets; record the dated result and exact commands in the runbooks and on #10455
- [ ] 6.2 Name the operator-only residue (OAuth consent, paid tier); attempt Playwright up to the consent gate before naming it operator-only

## Phase 7: Records and hygiene

- [ ] 7.1 ADR-079, ADR-075, ADR-218 text; `model.c4` edge prose; run C4 tests
- [ ] 7.2 Comment on #10455 listing remaining open items and the new residuals
- [ ] 7.3 Open Code-Review Overlap re-check against the final file list
- [ ] 7.4 LAST commit: retire `sandbox-readback-10445.sh`, its test and its `test-all.sh` line
