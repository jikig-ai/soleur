---
plan: knowledge-base/project/plans/2026-10-11-fix-agent-sandbox-proc-mask-systempaths-plan.md
spec: knowledge-base/project/specs/feat-sandbox-proc-shim-h6/spec.md
issue: 9860
branch: feat-sandbox-proc-shim-h6
lane: cross-domain
---

# Tasks (re-scoped 2026-10-11, option A)

Ref #9860, never Closes. Production writes (merge, deploy dispatch) need the operator's go-ahead.

- [x] 1.1 RED: `classifyBashSandboxFailure` tests on bwrap's real stderr (denial, scrub, cap, null cases)
- [x] 1.2 GREEN: `classifyBashSandboxFailure` in `sandbox-startup-classifier.ts`
- [x] 1.3 `mirrorBashSandboxFailure` in `cc-dispatcher.ts` + `onToolResult` call + its unit test (data minimisation)
- [x] 2.1 `sandbox-masked-proc-docker.test.sh` (control / treatment / isolation, literal tokens, never skips)
- [x] 2.2 Mutation battery: splice-shim, shim-bypass, control-unmasked, sleeper-after RED; stub-replay closed by a stronger non-vacuity assertion
- [x] 2.3 Re-run baseline + stub-replay mutation after the assertion change (baseline rc=0, stub-replay RED)
- [x] 3.1 `infra-validation.yml` sudo step; `PRIVILEGED_WHY` entry; orphan lint green
- [x] 4.1 Comment fix in `agent-runner-sandbox-config.ts`
- [ ] 5.1 Typecheck, affected-test gate, review panel, `user-impact-reviewer`
- [ ] 5.2 Push; confirm the suite passes in CI with the real AppArmor profile; operator go-ahead to merge
