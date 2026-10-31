---
title: Hosted Bash outage follow-ups, re-scoped
lane: cross-domain
brand_survival_threshold: single-user incident
issues: [10455, 10477, 5941, 10548]
brainstorm: knowledge-base/project/brainstorms/2026-10-31-hosted-bash-outage-followups-brainstorm.md
---

# Spec: Hosted Bash outage follow-ups

## Problem Statement

Tracker #10455 lists follow-ups from the hosted Bash outage (#10445). Most headline items have shipped (synthetic #10697, smoke and AF_UNIX variant #10546, routed alerts #10892). The remainder is smaller, differently ordered, and includes one cross-tenant read-channel measurement that outranks the rest.

## Goals

- Land four sequenced PRs (`Ref` on #10455 and #10548, never `Closes`).
- Close #5941 as superseded by #10453/#10546.
- Record the #10477 decision: no note, no count.

## Non-Goals

- Any user outreach (decided 2026-10-31). Revisit only on public hosted launch.
- Parked items (#10549, #10604, legacy-runner observer, 2+ user paging, SOCKS probe, peer-messaging auth, `--pids-limit`, #11085): see brainstorm for triggers.

## Functional Requirements

- FR1 (PR 1): measure what a sibling tenant can reach of persisted CLI output (`history.jsonl`, `debug`, `todos`, `shell-snapshots`, daemon sockets). A reachable leak is a P1 Art. 32 finding routed to the CLO.
- FR2 (PR 1): fix the `op=tenant-deny` emit (null first argument, constant message, `extra.code`, Sentry rule, `alert-reference.json` entry).
- FR3 (PR 1): derive the deny set from `agentEnv`, with a test that fails when `buildAgentEnv` emits a derivation key the guard does not read.
- FR4 (PR 2): promote `sdk_bash_smoke` to the blocking rollback lane; delete the `faithful_canary_sandbox_broken` alert. Attach the alert-flap review and the canary `memory.peak`/`oom_kill` record.
- FR5 (PR 3): plain-language Bash-failure message built on `classifyBashSandboxFailure`; sandbox-setup failures only; raw text behind a details disclosure; classify other helper steps (prctl/seccomp EPERM).
- FR6 (PR 4, optional): verify the ADR-260 Slack wake path for Better Stack and Sentry alerts; confirm `betterstack_paid_tier` first.
- FR7: add a negative-determination row for #10445 to `knowledge-base/legal/breach-register.md`; do not write "no data affected".

## Technical Requirements

- TR1: PR 2 changes the deploy rollback lane and needs operator authorization to merge and ship.
- TR2: enabling `agent-sandbox-unix-deny` in production is an operator-typed write (#10548); not bundled.
- TR3: copy-only change to an existing UI row needs no wireframe; adding a Retry button re-triggers `wg-ui-feature-requires-pen-wireframe`.
