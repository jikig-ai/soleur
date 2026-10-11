---
plan: knowledge-base/project/plans/2026-10-11-fix-agent-sandbox-proc-mask-systempaths-plan.md
spec: knowledge-base/project/specs/feat-sandbox-proc-shim-h6/spec.md
issue: 10032
branch: feat-sandbox-proc-shim-h6
lane: cross-domain
---

# Tasks: agent sandbox H6 fix (#10032)

Ref #10032, Ref #9860 (never Closes). Every production write (merge, apply-workflow dispatch, release re-run, Doppler write) needs the operator's explicit go-ahead. Run tests in an allocated sandbox (`scripts/soleur-sandbox.sh new/run-isolated/rm`).

## Phase 1 — RED first

- [ ] 1.1 `apps/web-platform/infra/ci-deploy.test.sh`: add the Guard 1 parity assertion (derive docker-run sites scoped to `--security-opt seccomp=` lines, join continuations, strip comments) and correct the mock `docker inspect` (flag absent from SecurityOpt, `MaskedPaths` empty); red today
- [ ] 1.2 `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`: control arm (EPERM reproduces) and treatment arm (canary replay passes, sibling sleeper via `docker exec` absent); literal failure tokens, never skip; measure duration in the sandbox
- [ ] 1.3 `apps/web-platform/test/sandbox-startup-classifier.test.ts`: Bash tool_result cases on bwrap's real stderr; a non-sandbox permission error classifies `other`; a secret-looking neighbour line never reaches the event
- [ ] 1.4 Existing sandbox-config test (`git grep -ln enableWeakerNestedSandbox apps/web-platform/test`): assert `enableWeakerNestedSandbox` stays `true`

## Phase 2 — the flag

- [ ] 2.1 `ci-deploy.sh`: `--security-opt systempaths=unconfined` on the canary and prod `docker run`; read the canary-start failure path (rejected option must fail before the prod stop); verify the provisioner writes the script atomically
- [ ] 2.2 `cloud-init.yml`: same flag; stay within the user-data size budget; run `cloud-init-user-data-size.test.ts`
- [ ] 2.3 `ci-deploy.sh` `host` diag row: add `masked=<n>` (`{{len .HostConfig.MaskedPaths}}`); update the mock field whitelist and row regex in `ci-deploy.test.sh`
- [ ] 2.4 `audit-bwrap-uid.sh` + `.test.sh`: read `HostConfig.MaskedPaths` (expect `[]`); red and green fixtures

## Phase 3 — CI wiring

- [ ] 3.1 `.github/workflows/infra-validation.yml`: explicit `sudo bash` step for the docker suite in `deploy-script-tests-fixed`, `timeout-minutes` from the 1.2 measurement
- [ ] 3.2 `PRIVILEGED_WHY` in `run-registered-suites.sh`, `DOUBLE_COVERED_ACK` row in `scripts/lint-orphan-test-suites.sh`, row in `scripts/suite-shard-legs.tsv`

## Phase 4 — observability (last commit)

- [ ] 4.1 `sandbox-startup-classifier.ts`: `classifyBashSandboxFailure` (reuse the namespace-token regex; add `proc_mount_eperm`; return only the matched line(s), capped ~300 chars)
- [ ] 4.2 `cc-dispatcher.ts` `onToolResult`: sibling try/catch before the posture gate; `mirrorWithDebounce`, `feature: agent-sandbox`, `op: bash-tool-result`
- [ ] 4.3 Comment the legacy `agent-runner.ts` limit; 4.4 comment in `server/agent-env.ts` that `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is deliberately never set

## Phase 5 — docs and records

- [ ] 5.1 Correct the stale comments in `agent-runner-sandbox-config.ts` (lines 36 and 571)
- [ ] 5.2 ADR-075 addendum (status `adopting`; supersedes the "widening, not a fix" line; rw readonlyPaths; DAC+caps compensation; `timer_list`/`sched_debug`/`interrupts` in-sandbox exposure; mask-absent interval) and the `canary-probe-set.md` H6 row
- [ ] 5.3 Read all three `.c4` files, record the actor/system/relationship check, run `c4-count-parity.test.sh`

## Phase 6 — legal records

- [ ] 6.1 `knowledge-base/legal/audits/2026-10-11-clo-attestation-sandbox-systempaths.md` and the Art. 32 TOM cell in `article-30-register.md`

## Phase 7 — ship and verify

- [ ] 7.1 Full battery in the sandbox, CI green, review panel, `user-impact-reviewer`; update `BASELINE_DECLARED_PROBES` on top of main's value (count plans recursively)
- [ ] 7.2 Merge (operator go-ahead); read the apply workflow result for both hosts; expect the first release deploy to run the old script; ask for the go-ahead to re-run the release deploy
- [ ] 7.3 After the second deploy, read the diag bundle for both hosts and the new image tag (Monitor, never sleep): `masked=0`, `sdk_probe rc=0`, `proc_mask` passes, `DEPLOY_SCRIPT_SHA` parity
- [ ] 7.4 If `sdk_probe` still fails with `masked=0`: stop, H7 live, comment on #10032; the revert PR is the operator's call
- [ ] 7.5 On a faithful pass: docs-only PR flipping the ADR addendum to `accepted` (CLO acknowledging); comment and close #10032 and #9860 per the operator
