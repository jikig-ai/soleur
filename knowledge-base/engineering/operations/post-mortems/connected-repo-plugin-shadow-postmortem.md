---
title: "Connected-repo plugin shadows the deployed platform plugin — untrusted-code-exec + the #4826 worktree-creation wedge"
date: 2026-07-06
incident_pr: 6123
incident_window: "2026-07-04 → 2026-07-06 (the multi-round #4826 wedge + the #6115/#6117 misattribution)"
recovery_at: "2026-07-06 (Slice A / PR #6123 — security core)"
suspected_change: "none — a latent path-resolution defect exposed by the operator dogfooding Concierge on a connected repo that ships its own plugins/soleur/"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

A Concierge (web) session loads its Soleur plugin — commands, skills, agents, and **executable `hooks/hooks.json` command-hooks** — from a **workspace-relative** path. For the operator's workspace, whose connected repo (`jikig-ai/soleur`) ships its own committed `plugins/soleur/`, the platform loaded the **connected repo's frozen committed copy** instead of the platform-deployed plugin. One defect, two faces: (1) **untrusted-code execution** — the connected repo's SessionStart/Stop `type:"command"` hooks ran as subprocesses of the Node dispatch process, outside the bwrap sandbox, with the server process's env + privileges; (2) **delivery shadow (#4826)** — every platform plugin fix was silently shadowed for that workspace, so the deployed `worktree-manager.sh` guard fixes (#6108, #6068, …) never ran.

## Status

resolved — Slice A (PR #6123) closes the security core (both SDK factories + the residual in-process SKILL.md reader load the deployed root). The delivery half is sequenced as Slice B (#6121).

## Symptom

The operator's `/soleur:go` Concierge sessions repeatedly wedged on worktree creation (a 5-round saga). Deployed guard fixes appeared to have no effect on the dogfooding workspace; the operator's interim unblock was a manual `git -C /workspaces/<id> pull origin main`.

## Incident Timeline

- **Start time (detected):** 2026-07-04 (first #4826 wedge round)
- **End time (recovered):** 2026-07-06 (Slice A merged)
- **Duration (MTTR):** ~2 days across multiple diagnosis rounds

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-07-04 | Operator's `/soleur:go` wedges on worktree creation; deployed guard fixes appear ineffective. |
| agent | 2026-07-05 | #6115 attempts the fix (cc-dispatcher factory only) but is reverted via #6117 on a false canary theory ("`/app/shared` not sandbox-accessible"). |
| agent | 2026-07-06 | Root cause confirmed: workspace-relative plugin load; the reverted-canary premise falsified against the actual gate code. |
| agent | 2026-07-06 | Slice A (PR #6123): both SDK factories + the F3 reader load `getPluginPath()`; loaded-gun guard added. |

## Participants and Systems Involved

Web dispatch (`cc-dispatcher.ts`, `agent-runner.ts`), the SDK plugin loader, the `context-queries-hook` in-process SKILL.md reader, `getPluginPath()` / `verifyPluginMountOnce()`, and the deploy canary (`ci-deploy.sh`).

## Detection (+ MTTD)

- **How detected:** operator-reported repeated Concierge session wedge (external/manual report), not a monitor — the dispatch surface had no load-source telemetry (the blind-surface gap this fix's `connectedRepoShipsPlugin` breadcrumb + `verifyPluginMountOnce` now close).
- **MTTD:** ~immediate on first wedge; the cost was time-to-DIAGNOSE, not time-to-detect.

## Triggered by

system — a latent path-resolution defect, surfaced by the operator dogfooding Concierge on a repo that commits `plugins/soleur/`.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Deployed `worktree-manager.sh` guard is buggy | wedge persisted after guard fixes | fixes were correct in isolation; never executed on the surface | rejected |
| `/app/shared` plugin path fails in the bwrap sandbox (#6117 premise) | #6115's deploy canary went red | sandbox binds `--ro-bind / /`; `getPluginPath()` is already boot-validated | rejected (falsified) |
| SDK + readers load the connected-repo workspace copy, not the deployed plugin | both factories + context-queries-hook build workspace-relative paths | — | confirmed |

## Resolution

Both real-SDK factories and the residual in-process SKILL.md reader now load from the platform-deployed root (`getPluginPath()`), workspace-independent. A loaded-gun guard (`assertTrustedPluginPath`) fails loudly on any regression. Canary-neutral (`buildAgentSandboxConfig` untouched). See ADR-093.

## Recovery verification

Full web-platform vitest suite green (11997/0), `tsc --noEmit` clean, multi-agent review (security-sentinel + user-impact-reviewer + architecture-strategist + code-quality-analyst + semgrep) with no P1/P2. Post-deploy: `/hooks/deploy-status` reason + `verifyPluginMountOnce`→Sentry confirm the deployed root loads on the operator's surface.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the operator's session wedge?** The deployed worktree-manager guard fixes did not run. **Why?** The SDK loaded the connected repo's frozen committed `plugins/soleur/`, not the deployed plugin. **Why?** Both real-SDK factories set `plugins:[{ path: join(workspacePath, "plugins", "soleur") }]` (workspace-relative). **Why was this not caught earlier?** The dispatch surface had no load-source telemetry — the load source was invisible. **Why did the first fix get reverted?** #6117 attributed a HOST bwrap/userns `canary_sandbox_failed` (the #4932/#5849 false-rollback class) to the plugin-path change without reading the actual gate — a wrong-layer misattribution, nearly repeated a 6th time.

## Versions of Components

- **Version(s) that triggered:** every deployed build prior to this fix (workspace-relative plugin load has always been present).
- **Version(s) that restored:** the build carrying PR #6123 (Slice A).

## Impact details

### Services Impacted

Concierge (web) agent dispatch for any workspace whose connected repo ships `plugins/soleur/`.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user (dogfooding operator): repeated `/soleur:go` worktree-creation wedge; every platform plugin fix silently shadowed; latent untrusted-code-execution exposure of the dispatch-process env on every session start/stop.
- Authenticated app user (non-dogfooding): none — their workspace `plugins/soleur` is a symlink to the deployed root, so behavior was already correct.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None (single-user dogfooding; pre-revenue surface).

### Team Impact

~2 days of solo-operator diagnosis time across 5 wedge rounds + a reverted fix attempt.

## Lessons Learned

### Where we got lucky

The untrusted-code-execution path required a connected repo to *ship* a malicious `hooks/hooks.json` — the only workspace that shipped `plugins/soleur/` was the operator's own trusted repo, so the exposure stayed latent rather than exploited.

### What went well

Root cause was ultimately confirmed by reading the actual gate code (not reasoning from the sandbox model on a dev machine), and the fix is canary-neutral — decoupled from every blocking canary reason.

### What went wrong

The blind dispatch surface (no load-source telemetry) turned a one-line path bug into a 5-round diagnosis saga, and a HOST bwrap/userns canary failure was misattributed to the plugin change — nearly a 6th round.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #6121 | Slice B — `CLAUDE_PLUGIN_ROOT` env injection + `safe-bash.ts` exact-literal carve-out + wedge-flow skill migration (closes the residual CWD-relative shell-out that keeps the delivery wedge until it lands). | open |
