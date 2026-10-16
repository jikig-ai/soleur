# Tasks: P1 hosted agent Bash down - apply-seccomp unshare(CLONE_NEWUSER) EPERM (#10445)

Plan: `knowledge-base/project/plans/2026-10-16-fix-hosted-agent-bash-apply-seccomp-userns-eperm-plan.md`
Order: Stage A (1 -> 2 -> 4 -> 5) restores service and ships first; Stage B (3) is separable and time-boxed.

## Phase 1: Evidence lock (no production mutation)

- [x] 1.1 Pull onset evidence: first prod deploy of `v0.324.3` from Better Stack `ci-deploy` rows (archive arm included), the DIAG `kernel_ns` row, `/hooks/deploy-status` (counts and timestamps only)
- [x] 1.2 Find where Bash tool_result text persists, if anywhere; decide census vs session-count proxy
  - [ ] 1.2.1 If a persisted source exists: counts-only aggregate, CLO-gated, results to the PIR only

## Phase 2: Fix and proofs (Stage A)

- [x] 2.1 Write failing tests first: config test pins `network.allowAllUnixSockets === true`
- [x] 2.2 `agent-runner-sandbox-config.ts`: add `allowAllUnixSockets: true` + type + header comment
- [x] 2.3 G1: stub-model harness spike (time-boxed); with the knob on, wrapped command has no `apply-seccomp` and a real Bash succeeds through the shim; control arm reproduces the EPERM; programmatic `sandbox` option honours the key
- [x] 2.4 Extend `test/helpers/vendored-bwrap-tail.ts` and `sandbox-vendored-argv-tail.test.ts` (helper-selection condition from the pinned binary)
- [x] 2.5 `sandbox-masked-proc-docker.test.sh`: wrapped-command arm + control arm (committed RCA reproduction)
- [x] 2.6 G2: runtime two-session test (tokenless and wrong-token 407, negative control, allowlisted pathname-socket census) as a suite assertion
  - [ ] 2.6.1 If G2 fails: implement option (b) (`socket(AF_UNIX)` deny in the one bwrap filter, `socketpair` allowed) in this PR; regenerate the `.bpf`; update the canary hardening probes

- [x] 2.7 Create `scripts/followthroughs/sandbox-readback-10445.sh` (Stage A: prints `sandbox_canary=pass|fail` from deploy-status; it is the Observability discoverability test)

## Phase 3: Deploy-time smoke and second alert (Stage B, time-boxed half a day)

- [ ] 3.1 `scripts/sdk-bash-smoke.mjs` + `test/sdk-bash-smoke.test.ts` (Guard 1 mutation rows, harness rows) (DEFERRED to #10453: Stage B time-box fallback)
- [ ] 3.2 Bake into the image (Dockerfile); wire `ci-deploy.sh` non-blocking next to `run_faithful_sandbox_canary`; `sdk_bash_smoke` field in deploy-status; test both old/new script-image orders (DEFERRED to #10453: Stage B time-box fallback)
- [ ] 3.3 Extend `scripts/followthroughs/sandbox-readback-10445.sh` with the `sdk_bash_smoke` line and promotion exit; tracker directive and `follow-through` label (DEFERRED to #10453: Stage B time-box fallback)
- [ ] 3.4 `faithful_canary_sandbox_broken` alert (positive `(op=sandbox-canary;` match) (DEFERRED to #10453: Stage B time-box fallback)
- [x] 3.5 If the spike overruns: file the Stage B tracking issue and ship Stage A alone

## Phase 4: Runtime detection and paging (Stage A)

- [x] 4.1 Failing tests first: classifier fixtures (real helper line, benign-first/second-line, bare `unshare` negative, empty output)
- [x] 4.2 `classifyBashSandboxFailure`: `apply-seccomp:` arm, `helper_userns_eperm`
- [x] 4.3 Write the `agent_sandbox_bash_denial` SQL against the verified row shape (`CONTAINER_NAME`, `message.feature`, `message.op`, `message.sandboxErrorCode`); re-sample once to confirm before apply
- [x] 4.4 `betterstack-logs-alerts.tf` + four `-target=` lines in `apply-web-platform-infra.yml`; `git grep -ln 'logtail_exploration' tests scripts apps/web-platform/test` and update every consumer
- [x] 4.5 `test/infra/sandbox-alerts.test.sh` (Guard 3 rows + production-shaped fixture row)
- [x] 4.6 `terraform validate`; `plugins/soleur/test/c4-count-parity.test.sh`

## Phase 5: Record

- [x] 5.1 PIR via the `soleur:incident` headless flow, `status: ongoing`, redaction sentinel first
- [x] 5.2 ADR-079 addendum, ADR-075 addendum (conditional on G2; cross-reference ADR-051/ADR-278)
- [x] 5.3 Runbook updates: `betterstack-log-query.md`, `canary-probe-set.md` (including the accepted forgery limitation)
- [x] 5.4 Comment on #10052 (paging path); file tracking issues: own AF_UNIX filter, runtime synthetic + dead-man arm, outer-wrap canary decision with deadline, plain-language Bash-failure message, the adjacent `spawnEgressForwarder` mkdir EACCES on `/var/lib/soleur/egress-tokens`, Stage B fallback if slipped
- [ ] 5.5 Hand the CPO outreach condition to the operator as a brand decision (sending is not assumed)

## Phase 6: Post-merge verification (agent-executed)

- [ ] 6.1 Deploy-status shows `sandbox_canary.verdict=pass` and (Stage B) a non-null `sdk_bash_smoke.verdict=pass`
- [ ] 6.2 Read both alerts back from the Better Stack API (present, unpaused)
- [ ] 6.3 Real hosted Bash call succeeds; egress-audit canary #9545 gets its first gateway row
- [ ] 6.4 Docs-only PR flipping the PIR to `resolved`; close #10445

## Post-ruling amendments (2026-10-16, CTO batch; see decision-challenges.md)

- Stage B fallback if the stub-model smoke is not done in the half-day time box: ship Stage A alone plus the Phase 1 docker-suite wrapper arm as the pre-merge guard, and file the tracking issue for the unfinished smoke BEFORE merge.
- Stage B probe ships non-blocking (reports + pages); promotion follow-through is `scripts/followthroughs/sandbox-readback-10445.sh`; `smoke_infra_error` never rolls back.
- Runbook entry for the new alerts states the wake path is email-only until the ADR-260 Slack integration is verified; file a tracking issue to verify the Slack wake across all Better Stack alerts.
- Optional public PIR summary only after Stage A readback is green on a real deploy; names no filter, socket-bridge or tenant-isolation mechanism.
