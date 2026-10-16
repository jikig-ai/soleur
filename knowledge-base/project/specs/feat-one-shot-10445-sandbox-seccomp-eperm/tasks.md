# Tasks: P1 hosted agent Bash down - apply-seccomp unshare(CLONE_NEWUSER) EPERM (#10445)

Plan: `knowledge-base/project/plans/2026-10-16-fix-hosted-agent-bash-apply-seccomp-userns-eperm-plan.md`
Order: Stage A (1 -> 2 -> 4 -> 5) restores service and ships first; Stage B (3) is separable and time-boxed.

## Phase 1: Evidence lock (no production mutation)

- [ ] 1.1 Pull onset evidence: first prod deploy of `v0.324.3` from Better Stack `ci-deploy` rows (archive arm included), the DIAG `kernel_ns` row, `/hooks/deploy-status` (counts and timestamps only)
- [ ] 1.2 Find where Bash tool_result text persists, if anywhere; decide census vs session-count proxy
  - [ ] 1.2.1 If a persisted source exists: counts-only aggregate, CLO-gated, results to the PIR only

## Phase 2: Fix and proofs (Stage A)

- [ ] 2.1 Write failing tests first: config test pins `network.allowAllUnixSockets === true`
- [ ] 2.2 `agent-runner-sandbox-config.ts`: add `allowAllUnixSockets: true` + type + header comment
- [ ] 2.3 G1: stub-model harness spike (time-boxed); with the knob on, wrapped command has no `apply-seccomp` and a real Bash succeeds through the shim; control arm reproduces the EPERM; programmatic `sandbox` option honours the key
- [ ] 2.4 Extend `test/helpers/vendored-bwrap-tail.ts` and `sandbox-vendored-argv-tail.test.ts` (helper-selection condition from the pinned binary)
- [ ] 2.5 `sandbox-masked-proc-docker.test.sh`: wrapped-command arm + control arm (committed RCA reproduction)
- [ ] 2.6 G2: runtime two-session test (tokenless and wrong-token 407, negative control, allowlisted pathname-socket census) as a suite assertion
  - [ ] 2.6.1 If G2 fails: implement option (b) (`socket(AF_UNIX)` deny in the one bwrap filter, `socketpair` allowed) in this PR; regenerate the `.bpf`; update the canary hardening probes

- [ ] 2.7 Create `scripts/followthroughs/sandbox-readback-10445.sh` (Stage A: prints `sandbox_canary=pass|fail` from deploy-status; it is the Observability discoverability test)

## Phase 3: Deploy-time smoke and second alert (Stage B, time-boxed half a day)

- [ ] 3.1 `scripts/sdk-bash-smoke.mjs` + `test/sdk-bash-smoke.test.ts` (Guard 1 mutation rows, harness rows)
- [ ] 3.2 Bake into the image (Dockerfile); wire `ci-deploy.sh` non-blocking next to `run_faithful_sandbox_canary`; `sdk_bash_smoke` field in deploy-status; test both old/new script-image orders
- [ ] 3.3 Extend `scripts/followthroughs/sandbox-readback-10445.sh` with the `sdk_bash_smoke` line and promotion exit; tracker directive and `follow-through` label
- [ ] 3.4 `faithful_canary_sandbox_broken` alert (positive `(op=sandbox-canary;` match)
- [ ] 3.5 If the spike overruns: file the Stage B tracking issue and ship Stage A alone

## Phase 4: Runtime detection and paging (Stage A)

- [ ] 4.1 Failing tests first: classifier fixtures (real helper line, benign-first/second-line, bare `unshare` negative, empty output)
- [ ] 4.2 `classifyBashSandboxFailure`: `apply-seccomp:` arm, `helper_userns_eperm`
- [ ] 4.3 Write the `agent_sandbox_bash_denial` SQL against the verified row shape (`CONTAINER_NAME`, `message.feature`, `message.op`, `message.sandboxErrorCode`); re-sample once to confirm before apply
- [ ] 4.4 `betterstack-logs-alerts.tf` + four `-target=` lines in `apply-web-platform-infra.yml`; `git grep -ln 'logtail_exploration' tests scripts apps/web-platform/test` and update every consumer
- [ ] 4.5 `test/infra/sandbox-alerts.test.sh` (Guard 3 rows + production-shaped fixture row)
- [ ] 4.6 `terraform validate`; `plugins/soleur/test/c4-count-parity.test.sh`

## Phase 5: Record

- [ ] 5.1 PIR via the `soleur:incident` headless flow, `status: ongoing`, redaction sentinel first
- [ ] 5.2 ADR-079 addendum, ADR-075 addendum (conditional on G2; cross-reference ADR-051/ADR-278)
- [ ] 5.3 Runbook updates: `betterstack-log-query.md`, `canary-probe-set.md` (including the accepted forgery limitation)
- [ ] 5.4 Comment on #10052 (paging path); file tracking issues: own AF_UNIX filter, runtime synthetic + dead-man arm, outer-wrap canary decision with deadline, plain-language Bash-failure message, the adjacent `spawnEgressForwarder` mkdir EACCES on `/var/lib/soleur/egress-tokens`, Stage B fallback if slipped
- [ ] 5.5 Hand the CPO outreach condition to the operator as a brand decision (sending is not assumed)

## Phase 6: Post-merge verification (agent-executed)

- [ ] 6.1 Deploy-status shows `sandbox_canary.verdict=pass` and (Stage B) a non-null `sdk_bash_smoke.verdict=pass`
- [ ] 6.2 Read both alerts back from the Better Stack API (present, unpaused)
- [ ] 6.3 Real hosted Bash call succeeds; egress-audit canary #9545 gets its first gateway row
- [ ] 6.4 Docs-only PR flipping the PIR to `resolved`; close #10445
