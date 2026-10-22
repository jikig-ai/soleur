---
title: Sandbox follow-ups, runtime synthetic and detection gaps
status: specified
issue: 10455
brainstorm: knowledge-base/project/brainstorms/2026-10-20-sandbox-followups-triage-brainstorm.md
branch: feat-sandbox-followups-triage-10455
pr: 10697
date: 2026-10-20
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
---

# Spec: sandbox follow-ups, runtime synthetic and detection gaps

The implementation pull request tracks #10455 and leaves it open. Do not put a GitHub closing keyword for #10455, #10548, #10549 or #10604 in the pull-request body or commit messages.

## Problem Statement

The deploy-time SDK Bash smoke only runs at deploy. Between deploys nothing exercises the wrapped Bash command, which is how the 2026-10-06..16 outage (#10445) went unnoticed for 10 days. The `op=masked-dir-precreate` failure reaches Sentry only, with no alert. Whether sibling tenants can read persisted CLI output (`history.jsonl`, `debug`, `todos`, `shell-snapshots`) through a shared `HOME` is unmeasured.

## Goals

- G1: A runtime synthetic on every web host that runs a real wrapped Bash call against the running container and pages through a per-host dead-man heartbeat.
- G2: A routed alert for `op=masked-dir-precreate`.
- G3: A read-only measurement of sibling-reachable persisted CLI output, with a recorded verdict.
- G4 (if the diff stays small): derive the sandbox deny set from the env the CLI is spawned with (`agentEnv`), with a test that fails when `buildAgentEnv` emits a derivation key the guard does not read.

## Non-Goals

#10548 soak and flag enable (operator-typed, not before 2026-10-26), #10549, #10604, the legacy-runner observer, distinct-user paging, SOCKS/`allowWebEgress`/read-only test arms, peer-messaging auth, `--pids-limit`, EACCES/EINVAL classification, and the PIR affected-user count. Each stays open or parked behind its recorded trigger.

## Functional Requirements

- FR1: Host systemd timer `web-bash-synthetic` per web host, every 15 minutes, under `flock` and `timeout 60`, running via `docker exec` in the running `soleur-web-platform` container with `env -i` and the decoy key.
- FR2: The Bash call echoes a fresh per-run random nonce; the probe passes only if the nonce is found in the real tool_result.
- FR3: Per-host Better Stack heartbeat (`for_each = var.web_hosts`), pinged only on a verified pass, `/fail` on `sdk_bash_smoke_failed`; period 900 s, grace 900 s (1800 s if the tier floor forbids).
- FR4: The synthetic pages on its first failure.
- FR5: Better Stack Logs alert on `op=masked-dir-precreate`.
- FR6: Written measurement of which persisted CLI paths a sibling session can read under the production sandbox config, recorded in the runbook. If reachable: file a P1 Art. 32 issue and run an Art. 4(12) screening only if actual access is found.

## Technical Requirements

- TR1: Deploy-swap guards on the timer (deploy lock, container state, first run at timer start), per the 2026-10-19 plan.
- TR2: Heartbeat follows the `web_nic_guard` / `web_zot_consumer` precedent in `arm-heartbeats.sh`; fresh-host provisioning reachable from `terraform apply` (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
- TR3: No tenant data in the synthetic; no new Article 30 category (CLO).
- TR4: Prior design: `knowledge-base/project/plans/archive/20261019-203025-2026-10-19-fix-sandbox-incident-followups-plan.md` Phase 5 and `decision-challenges.md` in the matching archived specs directory.
