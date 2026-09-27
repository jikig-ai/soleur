---
title: "Dedicated Inngest host ran without its deny-all cloud firewall for ~65 of 78 days"
date: 2026-09-25
incident_pr: 8831
incident_window: "2026-07-09T22:28Z → 2026-07-31T10:34Z; 2026-08-12T22:21Z → 2026-09-09T08:40Z; 2026-09-09T15:14Z → 2026-09-27T14:56Z (closed by inngest-host-replace run 36327637204)"
recovery_at: "2026-09-27T14:56:48Z"
suspected_change: "hcloud_firewall_attachment.inngest bound by server id; inngest-host-replace (#6197, 2026-07-09) never targeted it"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - security-control-absent
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — not a personal-data breach on present facts (CLO determination 2026-09-25, provisional on limb L3; see knowledge-base/legal/audits/2026-09-25-8754-inngest-cloud-firewall-determination.md)"
---

## Actor key

- `agent`: Claude Code did this autonomously (no operator ack required).
- `agent-with-ack`: Claude Code did this AFTER the operator confirmed via a menu option, per `hr-menu-option-ack-not-prod-write-auth`.
- `human`: the operator did this directly.

# Incident Overview

The dedicated Inngest host carries the only Inngest scheduler and Redis store. Its declared zero-rule deny-all Hetzner cloud firewall (`hcloud_firewall.inngest`, id 11269127) was attached to no server for three intervals: 2026-07-09 to 07-31, 2026-08-12 to 09-09, and 2026-09-09 to 2026-09-27, when the replacement host was born with the firewall applied. During those intervals sshd (key-only authentication) answered on the host's public IP.

The data ports stayed off the internet because of independent host-local controls:

- `:8288` and `:8289` are filtered by the nftables chain.
- Redis binds to loopback only.

## Status

resolved (2026-09-27). The fix (PR #8831) binds the firewall at server creation. The `inngest-host-replace` of 2026-09-27 created the host in service with the firewall applied, and the Hetzner API check passed (see Recovery verification). The follow-ups that stay open are tracked in Action Items & Follow-ups.

## Symptom

The web-platform drift plan (#8754) showed `hcloud_firewall_attachment.inngest` updating `server_ids` from a destroyed server id (165279348). A live Hetzner read confirmed the rest:

- firewall 11269127 has `applied_to=[]`;
- server 167310350 has `firewalls=[]`;
- TCP 22 is open on 95.217.161.110.

## Incident Timeline

- **Start time (first unfirewalled interval):** 2026-07-09T22:28Z
- **Detected:** 2026-09-25 (drift triage)
- **End time (recovered):** 2026-09-27T14:56:48Z (the replacement host was created with the firewall applied)
- **Duration:** three intervals: about 21.5 days, about 27.4 days, and 2026-09-09T15:14Z → 2026-09-27T14:56Z. Closed.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-08 | Infra comment records the stale attachment as an accepted residual, "reconciled by the next full/drift apply". No such apply existed. |
| agent | 2026-07-09 22:28 | First scoped `inngest-host-replace`. The new host boots with no cloud firewall. |
| agent | 2026-07-20 | Plan review finds that "no such automated path exists". The response corrects a comment; the mechanism is not changed. |
| human | 2026-07-31 10:34 | A full apply (run 30623984560) re-binds the firewall during the laptop-compromise response. |
| agent | 2026-08-12 22:21 | A replace leaves the next host unfirewalled. |
| human | 2026-09-09 08:40 | Run 34330222965 re-binds. |
| agent | 2026-09-09 15:14 | A replace leaves the next host unfirewalled (the current interval). |
| agent | 2026-09-25 | Drift triage (#8754) measures the gap live. PR #8831 binds the firewall through `hcloud_server.firewall_ids`. |
| agent-with-ack | 2026-09-27 14:56 | `inngest-host-replace` run 36327637204 (from `main` at 517bf59d85, after PR #8831 and PR #8873) creates server 167651172 with firewall 11269127 applied at creation and deletes server 167310350. Interval 3 ends. |
| agent | 2026-09-27 15:02 | The Hetzner API check passes (see Recovery verification). |
| agent-with-ack | 2026-09-27 15:29 | The cutover resume (`cutover-inngest.yml`, `op=resume`, run 36327875467) succeeds. The operator approved the `inngest-cutover` environment. |

## Participants and Systems Involved

Hetzner Cloud firewall 11269127, the dedicated Inngest host, `apply-web-platform-infra.yml` (the `inngest_host_replace` job), and Terraform provider hcloud 1.63.0.

## Detection (+ MTTD)

- **How detected:** manually, while triaging a drift report. No monitor covers "firewall attached to nothing" (#8870).
- **MTTD:** about 78 days from the first interval.

## Triggered by

system: a designed-in gap in the host-replace workflow.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The attachment binds by server id, and no workflow re-applies it after a replace | The drift plan's `server_ids` lists a destroyed id; the jobs API shows 36 replaces and only 2 re-binds | none | confirmed |

## Resolution

PR #8831:

- `hcloud_server.inngest.firewall_ids = [hcloud_firewall.inngest.id]`, sent inside ServerCreate so the host boots firewalled;
- the attachment is forgotten with `removed { destroy = false }`;
- a static guard (Guard 1) and a plan-level replace-gate counter (`firewall_not_bound`) pin the binding.

## Recovery verification

Pending, and to be recorded after the next `inngest-host-replace` (Hetzner API, no SSH):

- the new server's `public_net.firewalls` lists 11269127 with status `applied`;
- firewall 11269127's `applied_to` lists that server's id.

**Measured 2026-09-27: passed.**

- **The check (Hetzner API, GET only, about 15:02Z).** Server 167651172 (`soleur-inngest`, created 2026-09-27T14:56:48Z, public IPv4 95.217.161.110) has `public_net.firewalls` = [11269127: `applied`]. Firewall 11269127 (0 rules) has `applied_to` = [167651172]. The old server 167310350 returns 404.
- **External reachability.** From the operator workstation, TCP connects to 95.217.161.110 on 22, 8288 and 6379 all time out after 8 s. They are dropped, not refused.
- **The log side.** Shipped sshd rows from host `soleur-inngest` were 141 for 14:00–14:56Z and 0 for 15:00–16:30Z (queried at 16:01Z).
- **SSH logins in the interval-3 tail.** Better Stack, 2026-09-25T00:00Z to 2026-09-27T15:10Z. It found 0 sshd `Accepted publickey` and 0 `session opened for user` from `soleur-inngest`. Five rows from that host contain the phrase, and all five are Inngest event-log rows (`SYSLOG_IDENTIFIER=doppler`), the #8846 self-poisoning class.
- **Serving.** The first hourly `SOLEUR_INNGEST_SERVER_PROBE` row after the resume reads `instance=hetzner-167651172`, http 200, `server_active=active`, image v1.1.40, `cutover_flag=done`, `redis_keys=1215`, `registry_fns=72`, `data_mount_src=/dev/mapper/inngest-redis`. The pre-replace baseline was `redis_keys=1232` and `registry_fns=72`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the host unfirewalled?** The attachment's `server_ids` still named the destroyed predecessor.
2. **Why was it never updated?** `inngest-host-replace` deliberately excluded the attachment from its `-target` set.
3. **Why was that exclusion accepted?** A comment claimed "the next full/drift apply" would reconcile it.
4. **Why did no one notice that apply never ran?** The drift check only plans, the per-merge apply never listed the address, and nothing alarms on an empty `applied_to` (#8870).
5. **Why did the 2026-07-20 finding not fix it?** The response corrected the comment's wording instead of changing the mechanism.

## Versions of Components

- **Version(s) that triggered the outage:** the `inngest-host-replace` job as introduced by #6197 (2026-07-09) onward.
- **Version(s) that restored the service:** PR #8831, plus the host replace of 2026-09-27 (run 36327637204).

## Impact details

### Services Impacted

The dedicated Inngest host's network perimeter: public SSH exposure only.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: no known impact. Their data on the host (Inngest queue state in Redis) stayed off the internet because Redis binds to loopback. For the 2026-08-12 to 2026-09-25 intervals, the shipped sshd log shows zero successful logins. The 2026-07-09 to 07-31 interval has no surviving log and overlaps the July key exposure (#8867). The 2026-09-27 re-read carries the zero count to the end of interval 3 (see Recovery verification).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Legal records asserted a control that was absent. They are corrected append-only in PR #8831.

## Lessons Learned

### Where we got lucky

The host-local controls (the nftables filter on the ingest ports, and Redis bound to loopback) held the data plane closed. The host key was rotated on 2026-07-28, and hosts born afterwards use the new key.

### What went well

A live Hetzner read and a Better Stack sshd sweep settled the facts in minutes. The CLO ruling and the corrections landed in the same PR as the fix.

### What went wrong

An accepted-residual comment named an actor that never existed. A review found the gap and corrected the prose, not the mechanism. No alarm existed for "firewall attached to nothing".

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8754 | Run `inngest-host-replace` so the live host is born bound to firewall 11269127, verify `applied_to` through the Hetzner API, and append a dated "restored" marker to this PIR and the legal records | done 2026-09-27 (run 36327637204; check passed; markers appended) |
| #8870 | Add a standing no-SSH probe that alarms when any declared host firewall has an empty `applied_to` | open |
| #6442 | Move web, git-data, registry and grok_dogfood from `hcloud_firewall_attachment` to `firewall_ids` (zero-window recipe posted on the issue) | open |
| #8867 | Make the Art. 4(12) determination for the 2026-07-27/28 laptop compromise, which closes limb L3 of this incident's determination | open |
| #9061 | Stop `apply-deploy-pipeline-fix.yml` closing web-platform drift issues it did not resolve: it auto-closed #8754 on 2026-09-25 while this gap was still open, and the next drift run filed duplicate #8908 (added 2026-09-27 by #8754 PR-B, #9062) | open |
