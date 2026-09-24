---
title: "Inngest host replace booted before its private NIC was usable; scheduler dark ~59 min"
date: 2026-09-23
incident_pr: 8560
incident_window: "2026-09-22T06:59:45Z – 2026-09-22T07:58:00Z"
recovery_at: "2026-09-22T07:58:00Z"
suspected_change: "apply_target=inngest-host-replace (run 35697187645) — no code change; the race is structural in Hetzner's post-create network attach"
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - provider
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A routine `apply_target=inngest-host-replace` recreated `hcloud_server.inngest`. Hetzner attaches a
private network **after** the server is created and started, so cloud-init reached its zot registry
login ~34 s after the attach was issued and the private NIC still held no address. The pull timed
out, the GHCR fallback returned 401 because that PAT is revoked (AP-016), and the boot aborted
`FATAL: OCI pull failed`. The Inngest scheduler — of which there is exactly one — did not come up.

## Status

resolved

## Symptom

`dial tcp 10.0.1.30:5000: i/o timeout` in cloud-init output, followed by a GHCR 401 and
`FATAL: OCI pull failed`. Externally: no Inngest scheduler bound on :8288, so inbound-email and
PR-review dispatch were dark.

## Incident Timeline

- **Start time (detected):** 2026-09-22T06:59:45Z (server created; dark from this point)
- **End time (recovered):** 2026-09-22T07:58:00Z
- **Duration (MTTR):** ~59 minutes

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent-with-ack | 2026-09-22T06:59:45 | `hcloud_server.inngest` created by apply run 35697187645. |
| agent | 2026-09-22T07:00:12 | `hcloud_server_network.inngest` attach issued — 27 s after create, by design. |
| agent | 2026-09-22T07:00:46 | cloud-init `docker login`/`pull` against `10.0.1.30:5000` → `i/o timeout`. NIC still unusable ~34 s after the attach. |
| agent | 2026-09-22T07:00:46 | GHCR fallback leg returned 401 — that PAT is revoked (AP-016), so the documented break-glass path was already dead. |
| agent | 2026-09-22T07:00:47 | Boot aborted `FATAL: OCI pull failed`. Scheduler never bound :8288. |
| human | 2026-09-22T07:4x | Outage noticed; second `inngest-host-replace` dispatched (run 35697872056). |
| agent | 2026-09-22T07:5x | Second replace won the race — the NIC was usable by the time cloud-init reached the pull. |
| human | 2026-09-22T07:58 | `cutover-inngest.yml -f op=resume` approved; scheduler serving. |

## Participants and Systems Involved

Hetzner Cloud (server create + private-network attach ordering), cloud-init on the dedicated
inngest host, the zot registry at `10.0.1.30:5000`, GHCR (fallback leg), and the
`cutover-inngest.yml` resume path gated on a human reviewer.

## Detection (+ MTTD)

- **How detected:** external/manual — the operator noticed the scheduler was not serving. No
  automated signal fired, because the host emits its boot trace only if it gets far enough to run
  the emitter, and nothing alerts on the absence of a boot event.
- **MTTD (mean time to detect):** ~45 minutes.

## Triggered by

provider — Hetzner attaches the private network after the server is created and started. No code
change was involved; any replace could have lost this race, and an earlier one did (#6400, on the
registry host, which ran ~14 days with an unconfigured private NIC).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The private NIC was attached but not yet configured when cloud-init reached the pull | Attach at 07:00:12, pull at 07:00:46, `i/o timeout` not `connection refused`; zot itself healthy and serving other hosts throughout | — | Confirmed |
| zot was down | zot's own log shows it serving 10.0.1.10/.11/.30 during the window; no request from the inngest host ever arrived | Rules this out | Rejected |
| A transient IMDS blip | The second replace succeeded with no configuration change, consistent with a timing race rather than a metadata fault | Cannot be fully separated from the race on this evidence alone | Held as a weaker competing explanation |

## Resolution

A second `inngest-host-replace` (run 35697872056) happened to win the race, followed by a
human-approved `op=resume`. The Redis AOF volume was preserved throughout — no scheduler state was
lost. This was luck, not a fix; nothing about the second attempt made it more likely to succeed.

## Recovery verification

`cutover-inngest.yml -f op=resume` completed with the on-host 30 s timer starting, verifying and
recording the scheduler, and returning `INNGEST_CUTOVER_FLIP` to `done`. The scheduler bound :8288
and resumed dispatch.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the scheduler dark?** cloud-init aborted with `FATAL: OCI pull failed`.
2. **Why did the pull fail?** The zot leg timed out and the GHCR leg 401'd, so both legs were dead.
3. **Why did the zot leg time out?** The host's private NIC held no address yet; no packet from this
   host ever reached zot.
4. **Why did it hold no address?** Hetzner attaches the private network after the server is created
   and started, and nothing on the host configured the late-arriving link. cloud-init's own hotplug
   handler runs `After=cloud-init.target`, i.e. after `runcmd` — so it could not help a `runcmd` step.
5. **Why was there nothing to converge it?** The web host had `soleur-wait-nic` (#6441/ADR-114 §I1)
   and the registry host had `soleur-private-nic-guard` (#6415/ADR-115, reboot-based). The dedicated
   inngest host had neither — it was the one privately-attached host with no converge primitive, and
   that gap was not tracked.

## Versions of Components

- **Version(s) that triggered the outage:** cloud-init-inngest.yml at `origin/main` as of 2026-09-22; hcloud provider 1.63.0.
- **Version(s) that restored the service:** identical — recovery was a second attempt, not a change.

## Impact details

### Services Impacted

The Inngest scheduler (sole instance): inbound-email processing and PR-review dispatch were not
running for the duration. No data was lost; the Redis AOF volume survived the replace.

### Customer Impact (by role)

- Prospect: none — the marketing site and signup are not served by this host.
- Authenticated app user: degraded — any action whose completion depends on an Inngest-dispatched
  job (inbound email processing) was queued rather than lost, and drained after recovery.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none — no billing path runs through this host.
- OAuth installation owner: degraded — PR-review dispatch did not run during the window.

### Revenue Impact

None identified. No billing path traverses this host and no charge was attempted or missed.

### Team Impact

~59 minutes of scheduler downtime plus the operator time to notice, diagnose and dispatch a second
replace. Diagnosis was possible only because zot's shipped logs and Hetzner's attach timestamps
could be read off-box; the host itself emitted nothing.

## Lessons Learned

### Where we got lucky

The second replace won the same race with no change made. Nothing about it was more likely to
succeed than the first, so the recovery was chance. Had it lost too, the next step would have been a
third replace with the same odds. The Redis AOF volume also survived — a replace that had lost it
would have turned an availability incident into a data one.

### What went well

The failure was loud on the host (`FATAL: OCI pull failed`) rather than a silent half-boot, and the
Hetzner attach timestamps plus zot's own request log were enough to establish the cause without SSH.
zot's log showing requests from 10.0.1.10/.11/.30 and none from the inngest host is what ruled out a
zot fault in one read.

### What went wrong

- **Nothing paged.** The host went dark and the only detector was a human noticing. A boot that
  aborts before its emitter runs emits nothing, and no alert keys on the absence of a boot event.
- **The documented break-glass path was already dead.** The GHCR fallback leg 401s because that PAT
  is revoked (AP-016), so the pull had one live leg, not two — and that was not surfaced anywhere
  before the incident consumed it.
- **The gap was known in the abstract and untracked in the specific.** Both sibling hosts had a
  converge primitive; the one with no primitive was the sole scheduler, and nothing recorded that
  asymmetry as a risk.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

| Issue | Action | Status |
|---|---|---|
| #8562 | Move the bootstrap pull into a retrying systemd unit so a missed first-boot pull is recoverable without a host replace, and add a forced-race rehearsal that proves the converge primitive under a deliberately late attach. | open |
| #8495 | The external watchdog `scheduled-inngest-health` never ran inside this window: GitHub's `schedule:` left a gap from 06:01 to 11:36 UTC on 09-22, so the probe that files `ci/inngest-down` could not see the dark scheduler. The trigger now comes from an in-process dispatch clock on both web hosts, on a 15-minute slot, with the Sentry margin sized to the measured runner queue (ADR-248, PR #8691). | fixed in PR #8691 |
