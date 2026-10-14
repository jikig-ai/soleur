---
title: "infra-config delivery completed while activation silently never happened"
date: 2026-08-04
incident_pr: 7221
incident_window: "2026-05 (reload first ungranted) → ongoing; loud since 2026-08-03T11:58:31Z"
recovery_at: "not yet recovered — PR-A instruments, PR-B repairs"
suspected_change: "701e76e6 (#7146) moved the ungranted daemon-reload above the state write, converting a ~2-month silent failure into a loud one"
brand_survival_threshold: single-user incident
status: mitigating
triggers:
  - "CI: Apply deploy-pipeline-fix verify step failed on the #7146 merge"
  - "Frame reported exit_code=1 reason=unhandled files_total=0"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`infra-config-apply.sh` is the webhook handler that delivers 19 managed config files to
`soleur-web-platform` and then activates them (`daemon-reload` + unit reconciliation). It is the
**only no-SSH remediation channel** on a `cx33` host with 0/6 datacentre stock.

Delivery has been healthy throughout. **Activation has not.** The handler's
`systemctl daemon-reload` runs as `User=deploy` with no sudoers grant, returns
`Interactive authentication required`, and `set -e` aborts the handler — **after all 19 files
are written**, but before unit reconciliation and the webhook self-restart. Every managed unit
has therefore been running the environment it was started with, while the channel reported the
files as delivered.

Two properties made this hard to see, and both are the actual subject of this PIR:

1. **The reload has been ungranted since it was introduced (~2026-05).** `#7146` did not break
   it; it MOVED the call above the state write, which converted a two-month *silent* failure
   into a *loud* one. Verified from git history: the oldest `deploy-inngest-bootstrap.sudoers`
   contains zero `daemon-reload` references, and the current file grants only
   `DROPIN_TRY_RESTART`.
2. **The channel could fail but not say how.** The EXIT trap published a frame of hardcoded
   zeros, so the CI gate reported `files_total=0` — *the exact opposite of what happened* — with
   no line, no command and no rc. The operator-facing annotation was then two-thirds false, and
   the issue written from it pointed at `terraform apply -replace` on the one host that cannot
   be re-provisioned.

## Status

**Mitigating.** PR #7221 (PR-A) ships the instrument, not the repair. Activation remains broken
until PR-B lands the sudoers grant. This PIR is filed now rather than at resolution because the
detection and diagnosis lessons are complete and are what recur.

## Impact

- **User-facing: none.** `app.soleur.ai/health` returned 200 throughout; the web platform is a
  separate delivery path. No customer data was affected. Art. 33/34 do not apply — no personal
  data was exposed, only an internal control plane failed to activate.
- **Operationally significant.** Config changes to the 19 `FILE_MAP` destinations (including
  `ci-deploy.sh`, `hooks.json`, `webhook.service` and the Doppler credential drop-ins) reached
  the host but were never adopted by the running units. The channel is also the no-SSH
  remediation path, so it needed repair *before* it was needed.

## Timeline

| When (UTC) | Actor | What |
|---|---|---|
| ~2026-05 | — | `systemctl daemon-reload` introduced in the handler with no sudoers grant. Silent: it ran after the state write, so the frame was already published. |
| 2026-08-03 13:54 | `agent` | #7146 (`701e76e6`) reorders the reload ABOVE the state write so activation can be reported. The ungranted call now aborts before the frame is written. |
| 2026-08-03 11:58:30 | — | Apply fires. 19/19 files written in 1.05s. |
| 2026-08-03 11:58:31 | — | `command output: Reload daemon failed: Interactive authentication required.` → `error occurred: exit status 1`. No `SOLEUR_INFRA_CONFIG_RESTART`, no self-restart. |
| 2026-08-03 ~14:00 | `human` | Operator files #7220 from the CI failure. |
| 2026-08-03 | `agent` | Root cause confirmed from Better Stack on request id `86ea60`; three premises in the issue body falsified (19/19 landed, 16 journald rows shipped, all 19 `*_B64` vars present). |
| 2026-08-04 | `agent` | PR-A (#7221) ships the fatal channel. Activation still broken pending PR-B. |

## Root Cause

An ungranted privileged verb on a fail-fast path, with no error channel to report it.

The sudoers policy grants `DROPIN_TRY_RESTART` (`systemctl try-restart vector.service`) and
nothing else. `daemon-reload` was never added. Under `set -euo pipefail` the denial aborts the
handler mid-activation.

## Detection

**Poor, and that is the finding.** The failure surfaced only as a red CI step whose message said
`files_total=0` — which is false. Nothing on the journald channel named the failing command,
because the handler emitted no fatal marker at all. Diagnosis required a manual Better Stack
query correlating a webhook request id, and the query that found it (`--grep 86ea60`) is one no
runbook would have suggested: the decisive line does not contain the string `infra-config`.

## What Went Well

- The dual-channel design meant the evidence existed at all — the webhook's own stderr capture
  carried the denial text verbatim, on the same request id as the handler's exec line.
- The R3 canary (`SOLEUR_PROBE_CANARY … source4_live=1`) provided a positive control proving the
  telemetry channel was live, so "zero rows" could be read as a real absence rather than a dead
  instrument.
- The operator declined the `terraform apply -replace` remediation the annotation implied, on a
  host that cannot be re-provisioned.

## What Went Wrong

- A privileged verb shipped with no corresponding grant and no test asserting the grant exists.
- The handler's failure path published **hardcoded zeros**, so the one artifact the CI gate reads
  actively misdescribed what happened.
- The annotation derived from that frame sent the reader toward destroying the host.
- The first attempt at a soak probe for this very channel **returned PASS against the dying
  host**, because its liveness control counted rows the pre-fix handler also emits. The sweeper
  auto-closes on PASS; it would have closed this incident while it was happening.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Action | Status |
|---|---|---|
| #7220 | PR-B: grant `daemon-reload` via the existing WRITE seam, gated behind the `*.service` content shape-gate, and re-verify activation end-to-end. This is the repair; PR-A only instruments. | open |
| #7220 | Post-merge soak `scripts/followthroughs/infra-config-fatal-channel-7220.sh` — asserts the channel is live and reporting, and FAILs (never PASSes) when it cannot tell a healthy new handler from an undelivered one. | open |
| #7103 | `soleur-web-2` `IMAGE_PULL_FAIL … auth_denied` on `v0.248.2` — pre-existing B4, re-confirmed live and out of scope for this channel. | open |

## Related

- [[2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect]] — the session learning;
  every defect here was a check certifying the wrong property.
- ADR-159 (delivery is not activation) — this incident is proposition 1's defect, live.
- ADR-154 (repair the credential channel, not the host).
