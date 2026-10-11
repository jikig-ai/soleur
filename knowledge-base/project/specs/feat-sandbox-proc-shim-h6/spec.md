---
title: Sandbox /proc mask — production-posture CI gate and Bash sandbox-failure observability
status: draft
owner: engineering
issue: 9860
brainstorm: knowledge-base/project/brainstorms/2026-10-11-sandbox-proc-shim-h6-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
created: 2026-10-11
rescoped: 2026-10-11
---

# Spec: close the gaps #10039 left around the sandbox /proc mask

> **Re-scoped 2026-10-11.** The original scope (add `--security-opt systempaths=unconfined`, an ADR addendum and
> legal records for the widening) was made obsolete the same day by PR #10039, which fixed #10032 by changing the
> shim to DROP procfs mounts, and which measured and rejected `systempaths=unconfined`. Measured in this work's
> lab: with the shipped shim the canary replay passes under docker's default masks WITHOUT the flag. The flag is
> not shipped. The operator chose option A: build only what #10039 left open.

Ref #9860 (never Closes: it closes when the first post-deploy faithful canary reports `pass`, #10039 AC4).

## Problem Statement

#10039 fixed the outage, but two gaps that let it ship and stay invisible remain:

1. **No CI job runs real bwrap under docker's default masked `/proc`.** Every shim test ran on an unmasked host, and
   the canary that would have caught the #9723 splice is report-only. #10039's in-image measurement was by hand.
2. **A sandbox denial the SDK returns to the model as a Bash `tool_result` reaches Sentry as nothing.** Only errors
   thrown out of the SDK iterator are classified, so tenant impact of a sandbox outage is unobservable.

## Goals

- **G1.** A privileged CI suite proves, in a container with the production posture, that (control) the historical
  splice shape is refused under docker's default masks, (treatment) the canary replay passes through the shipped shim,
  and (isolation) a sibling process is absent from the sandbox's `/proc` through the shim and visible through the
  real bwrap. It never self-skips.
- **G2.** A Bash `tool_result` carrying a sandbox denial is mirrored to Sentry (`feature:agent-sandbox`,
  `op:bash-tool-result`), carrying ONLY the scrubbed, capped matched line.
- **G3.** The stale comment in `agent-runner-sandbox-config.ts` describes the real mechanism.

## Non-Goals

- `systempaths=unconfined`, any docker-run change, any ADR-075 widening addendum, any legal record for a widening.
- Kernel-stream read for the deploy user (#10045) and the paging alert for the new Sentry event (#10052).
- The legacy `agent-runner.ts` loop (no tool-result observer there; its session-level catch is unchanged).

## Functional Requirements

- **FR1.** `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`: control / treatment / isolation arms; literal
  failure tokens (`DOCKER_UNAVAILABLE`, `APPARMOR_UNAVAILABLE`, `SYSCTL_UNAVAILABLE`, `IMAGE_BUILD_FAILED`,
  `IMAGE_DRIFT`); a local-only `SOLEUR_SANDBOX_DOCKER_APPARMOR=unconfined` override refused when `CI` is set.
- **FR2.** CI wiring: a `sudo bash` step in `deploy-script-tests-fixed`, an entry in `PRIVILEGED_WHY`
  (`run-registered-suites.sh`) so the glob-derived unprivileged legs skip it, and the orphan lint stays green.
- **FR3.** `classifyBashSandboxFailure` (sandbox-startup-classifier.ts) and `mirrorBashSandboxFailure`
  (cc-dispatcher.ts), called from `onToolResult` before the autonomous-posture gate, debounced per user.
- **FR4.** Correct the stale comment in `agent-runner-sandbox-config.ts`.

## Technical Requirements

- **TR1.** Mutation battery on the docker suite, each row RED: swap in a splicing shim (pre-#10039 behaviour), bypass
  the shim, remove the masks from the control, start the sibling after the sandbox, replace the replay with a stub.
- **TR2.** The data-minimisation test: a secret-looking neighbour line and a workspace path never reach the event.
- **TR3.** Tests and batteries run in an allocated sandbox; any production write needs the operator's go-ahead.
