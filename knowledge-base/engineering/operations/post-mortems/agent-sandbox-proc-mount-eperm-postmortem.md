---
title: "agent sandbox spawns failed closed under docker's masked /proc, and nothing alerted: the canary was report-only and a Bash denial reached Sentry as nothing"
date: 2026-10-11
incident_pr: 10043
incident_window: "From the shim splice (#9723), first shipped in the image of about 2026-10-09T04:52Z, to #10039 merging 2026-10-11T18:29Z. Whether any tenant Bash call failed in that window was not measurable: that gap is part of the incident."
recovery_at: "Fix merged 2026-10-11T18:29Z (#10039). Recovery in production is NOT yet verified: the close condition on #9860 is the first post-deploy faithful canary reporting pass."
suspected_change: "#9723 spliced a fresh `--proc /proc` into the bwrap argv. Under docker's default masked /proc a fresh procfs mount from a nested user namespace is refused (`bwrap: Can't mount proc on /newroot/proc: Operation not permitted`), so every sandboxed spawn failed closed."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - availability (agent Bash sandbox could not spawn in the production image; the faithful canary reported sandbox_broken / bwrap_operation_not_permitted)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: an availability event on the agent sandbox with no personal-data dimension.
# The sandbox failed CLOSED (no isolation was weakened; the cross-tenant /proc mask held). Brand survival
# is single-user because one tenant whose agent cannot run commands cannot work. No personal data was
# exposed, accessed, altered or lost, so Art. 33/34 do not apply.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The agent's Bash sandbox (bubblewrap inside the shared web container) could not start in the production image after #9723 changed how the shim handled `/proc`. The deploy canary that would have caught it is report-only by design, so deploys continued. A sandbox denial that the SDK returns to the model as a Bash `tool_result` is not a thrown error, so the session-level classifier never saw it and Sentry received nothing.

## Status

ongoing — the fix is merged (#10039) but the post-deploy faithful canary has not yet been read as `pass`.

## Symptom

Faithful canary verdict `sandbox_broken` with reason `bwrap_operation_not_permitted`; the weaker `SANDBOX_PROBE_OK` probe passed alongside it, which made the surface look healthy.

## Incident Timeline

- **Start time (detected):** before 2026-10-11; first read in the canary self-diagnosis bundle (#9860).
- **End time (recovered):** not yet verified in production (see Status).
- **Duration (MTTR):** TBD, pending the post-deploy canary read.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-10-09T04:52Z (approx.) | Image carrying the #9723 splice begins to ship. |
| human | 2026-10-11 | Operator resumes the canary self-diagnosis (#9860, #10032). |
| agent | 2026-10-11 | Lab measurement on bubblewrap 0.8.0 reproduces the refusal under docker's default masks. |
| agent | 2026-10-11T18:29Z | #10039 merges: the shim drops procfs mounts so the vendored `--tmpfs /proc` is the mask. |
| agent | 2026-10-11 | #10043 adds the production-posture CI gate and the Bash-denial Sentry mirror. |

## Participants and Systems Involved

Agent Bash sandbox (bubblewrap 0.8.0, `apps/web-platform/infra/bwrap-shim/bwrap`), the deploy canary (`apps/web-platform/scripts/sandbox-canary.mjs`), `cc-dispatcher.ts` `onToolResult`, Sentry, Better Stack.

## Detection (+ MTTD)

- **How detected:** the faithful canary's own diagnostic bundle, read by the operator. No monitoring system paged.
- **MTTD (mean time to detect):** unmeasurable; there was no signal that could have timestamped the first failure.

## Triggered by

system (a code change in the shim).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| H6: fresh procfs mount refused under docker's default masks | Reproduced in the lab with the production base image; the spliced shape fails and the shipped shim passes | none | confirmed |
| H7: AppArmor profile denial | Not excluded locally (the dev host has no AppArmor) | none | open; the CI suite runs with the real profile loaded |

## Resolution

#10039 changed the shim; #10043 adds the guard and the signal. `systempaths=unconfined` was measured and rejected (it widens `/proc` and `/sys` for the whole shared container).

## Recovery verification

Pending: `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 3h --grep SOLEUR_CANARY_SANDBOX_DIAG` after the next deploy; expected verdict `pass`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did sandboxed spawns fail? A fresh procfs mount was refused in a nested user namespace under docker's default masked `/proc`.
2. Why was a fresh mount attempted? The shim spliced `--proc /proc` before the command boundary (#9723).
3. Why did the change ship? Every shim test ran on an unmasked host; nothing ran real bwrap under docker's default masks.
4. Why did the deploy not stop? The faithful canary is report-only by design, and the weaker probe passed.
5. Why was tenant impact invisible? A Bash `tool_result` carrying the denial is not a thrown error, so it reached Sentry as nothing.

## Versions of Components

- **Version(s) that triggered the outage:** the release carrying #9723.
- **Version(s) that restored the service:** the release carrying #10039 (production verification pending).

## Impact details

### Services Impacted

Agent Bash tool calls inside the sandbox.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: agent commands could not run in the window; extent unmeasured
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None measured.

### Team Impact

Operator time on the canary self-diagnosis across several sessions.

## Lessons Learned

### Where we got lucky

The failure was closed: the mask held and no isolation was weakened.

### What went well

The lab reproduction was exact and cheap; the faithful canary named the reason.

### What went wrong

A report-only canary and a green weaker probe read as health; the denial path had no signal; the first implementation of #10032 was built on a premise #10039 had already replaced.

## Action Items & Follow-ups

| Issue | Action | Owner |
|---|---|---|
| #9860 | Read the first post-deploy faithful canary and close only when it reports pass | operator |
| #10052 | Paging alert for the new `op:bash-tool-result` Sentry event (blocked on #7985) | engineering |
| #10045 | Kernel-stream read for the deploy user, so a kernel denial is observable without SSH | engineering |
| #10065 | Assert parity of the CI suite with the real docker run tuples and the vendored argv tail | engineering |
