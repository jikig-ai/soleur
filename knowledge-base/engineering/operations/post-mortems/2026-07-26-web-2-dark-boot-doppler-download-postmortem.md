---
title: "soleur-web-2 booted DARK at cloud-init stage doppler_download — the fatal could not name its own cause"
date: 2026-07-26
incident_pr: 6970
incident_window: "2026-07-26T16:49:35Z (host created) → ongoing (host is dark, still occupying a fleet slot; cause UNDETERMINED)"
recovery_at: "not recovered — runcmd is once-per-instance, so this host cannot be repaired by reboot; it must be destroyed and reborn (#6969 open decision)"
suspected_change: "none identified — the birth path (#6730, ADR-145) behaved correctly and detected the dark boot. The cause of the doppler_download failure itself is UNDETERMINED because the failing call discarded the Doppler CLI's stderr and exit code."
brand_survival_threshold: single-user incident
status: unresolved but ended
triggers:
  - automated detection (the #6730 birth-path gate failed its own run loudly on the fatal boot-stage event)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was involved. The host never entered service, holds no tenant data, and the only captured process output is the boot process's own stderr."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The **first real use** of the `web-host-create` birth path (#6730, ADR-145) created `soleur-web-2`
and then booted it **DARK**: the host exists and is `running` at the Hetzner level, but cloud-init
died at stage `doppler_download` and emitted a `fatal`. Because `runcmd` is once-per-instance, the
host cannot be repaired by a reboot — it must be replaced.

**The birth path behaved correctly.** `Terraform apply (web-host birth)` succeeded and the very next
step detected the dark boot and failed the run. This incident is about the boot failure, not the
gate — the gate is the reason we know at all.

The defect this PIR is really about is a *second-order* one, and it is the one that made the
incident unresolvable: **the fatal named only the stage, never the cause.** The failing call
discarded the Doppler CLI's stderr and exit code at the source, and Vector's shipping token comes
from the very fetch that failed — so the host had no error channel of its own. Every root-cause
hypothesis is still `UNKNOWN`, and no amount of further reasoning can close them, because the
discriminating datum was never captured.

## Status

`unresolved but ended` — the boot failure is not recurring (no further host births have been
attempted), but the root cause is UNDETERMINED and `soleur-web-2` is still dark.

## Symptom

`soleur-web-2` (`cpx22`, created `2026-07-26T16:49:35Z`, `host_id=155488316`) emitted a `fatal`
boot-stage event at stage `doppler_download` and never reached `cloud_init_complete`. The birth-path
run surfaced:

```
web-2 booted DARK: a fatal boot-stage event was surfaced
(last-reached stage: doppler_download). runcmd is once-per-instance, so this host
CANNOT be repaired by a reboot — it must be replaced. Do NOT put it into service.
```

Run: <https://github.com/jikig-ai/soleur/actions/runs/30211101264> (dispatch, approved 2026-07-26).

## Incident Timeline

- **Start time (detected):** 2026-07-26T16:51:58Z (the `fatal` event itself)
- **End time (recovered):** not recovered
- **Duration (MTTR):** n/a — the host is still dark

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent-with-ack | 2026-07-26T16:49:35Z | `web-host-create` birth path dispatched and approved; Hetzner creates `soleur-web-2` (`cpx22`). |
| agent | 2026-07-26T16:50:03Z | Boot-stage event `bootcmd_start` (info). |
| agent | 2026-07-26T16:51:42Z | Boot-stage event `bootstrap_complete` (info). |
| agent | 2026-07-26T16:51:52Z | Boot-stage event `webhook_bound` (info). |
| agent | 2026-07-26T16:51:58Z | Boot-stage event `doppler_download` at level **fatal**. Cloud-init aborts. |
| agent | 2026-07-26T16:52:xxZ | The birth path's own post-create gate reads the trail, detects the fatal, and fails the run loudly. |
| human | 2026-07-26 | Incident opened as #6969. |
| agent | 2026-07-26 | Diagnosis blocked: the fatal carries no stderr, no exit code, and no host name. Root cause UNDETERMINED. |
| agent | 2026-07-26 | Remediation re-scoped from "fix the download" to "ship the component's own error channel first" (this PR, #6970). |

## Participants and Systems Involved

Hetzner Cloud (host create), cloud-init `runcmd` (`apps/web-platform/infra/cloud-init.yml`), the
baked host-script `soleur-host-bootstrap.sh`, the Doppler CLI (`secrets download`), Sentry
(`jikigai-eu/web-platform`, the only channel a first-booting host has), and the `web-host-create`
birth path (`.github/workflows/apply-web-platform-infra.yml`).

## Detection (+ MTTD)

- **How detected:** monitoring/automation — the birth path's own post-create boot-trail gate, not an
  external report. This is the healthy direction: the gate was added by #6730 precisely so a dark
  birth cannot be mistaken for a quiet one.
- **MTTD:** under a minute from the fatal event to the run failing.

## Triggered by

`system` — an automated host-birth operation. No user action, no market movement. The immediate
provider interaction that failed (the Doppler fetch) is itself a candidate cause but is not
confirmed.

## Root-cause hypothesis (triage)

Every hypothesis below remains `UNKNOWN`. That is the finding, not a gap in the write-up: the
evidence needed to discriminate between them was discarded at the call site.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| H1 — the Doppler call hung and was killed / never returned | This was the **only unbounded Doppler invocation** in `cloud-init.yml` (measured: 11 bounded siblings, 1 unbounded — and the unbounded one is the one that failed) | none available — no exit code was captured, so a `124`-shaped timeout is indistinguishable from a fast non-zero | UNKNOWN |
| H2 — token/authz rejection (bad or unscoped `DOPPLER_TOKEN`) | The token is injected via `/etc/default/webhook-deploy` at cloud-init time and is not otherwise exercised on a fresh host | none available — the CLI's stderr, which would have said so verbatim, was discarded | UNKNOWN |
| H3 — transient network/DNS failure reaching Doppler | Fresh-boot networking is the least-settled part of the boot | none available | UNKNOWN |
| H4 — disk/tmpfile failure writing the downloaded env | `mktemp` + `chmod 600` precede the call | none available | UNKNOWN |

## Resolution

**Not resolved.** No cause was identified and `soleur-web-2` remains dark. What this PR resolves is
the *reason* it could not be identified:

- `soleur-boot-emit` gains a per-stage `detail` tag (`/run/soleur-stage-detail.d/<stage>`, with no
  legacy fallback) and a `host_name` tag; credential redaction lives **in the emitter**, the single
  choke point every producer flows through.
- A new baked helper `soleur-doppler-download` bounds the call (`timeout -k 5 20`, 3 attempts, 5s/10s
  backoff), captures stderr only, scrubs it, emits per-attempt `doppler_retry` breadcrumbs, and
  writes the summary the fatal trap reads.
- The call site is fail-closed twice over: `&& rc=0 || rc=$?` **plus** `[ "$rc" = 0 ] || exit "$rc"`.
- The birth-path gate's `::error::` now names the cause, is host-scoped, and warns on a green birth
  that nonetheless retried.

Consequence to state plainly: **this change reaches no running host.** `hcloud_server.web` pins
`user_data` under `lifecycle.ignore_changes`, and `runcmd` is once-per-instance, so the new tags
take effect only at a **fresh create**. It cannot repair `soleur-web-2`, and a `terraform plan`
showing no diff is expected rather than evidence of no effect.

## Recovery verification

Deferred by construction, and the deferral is the point. Recovery is verified at the **next fresh
host birth on a post-#6969 image**: the birth-path gate must either reach `cloud_init_complete`, or
fail with an `::error::` that names `stage=doppler_download` **together with the Doppler CLI's own
error line and exit code**. Until a host is born on such an image there is nothing live to probe —
which is precisely why the error channel shipped ahead of any attempted fix.

The channel's transport is independently probeable today without SSH:

```bash
curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
  https://o4511404939345920.ingest.de.sentry.io/api/4511404943671376/store/
# 401 (auth-gated but reachable) is the healthy signal
```

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was `soleur-web-2` unusable?** Cloud-init died at stage `doppler_download` and `runcmd` is
   once-per-instance, so the host cannot be repaired in place.
2. **Why did `doppler_download` fail?** **UNDETERMINED.**
3. **Why is it undetermined?** The fatal event named only the stage. The failing call was written as
   `if ! doppler secrets download … > "$TMPENV"; then … exit 1; fi`, which discards both the CLI's
   stderr and its exit code before anything can read them.
4. **Why was there no other channel?** Vector — the host's log shipper — draws its own token from the
   very Doppler fetch that failed, so on this failure path the host is structurally unable to ship
   logs. The Sentry boot-stage emitter was the only channel, and it was carrying a stage name and
   nothing else.
5. **Why was the emitter that thin?** Boot-stage events were designed as coarse progress beacons
   under a hard `user_data` byte budget. No stage had a producer for its own error text, so a fatal
   could report *where* it stopped but never *why*. **This is the actual root cause of the
   unresolvability**, and it is what ADR-147 changes: boot-stage diagnostics live in baked
   host-scripts, where they cost no `user_data` bytes.

## Versions of Components

- **Version(s) that triggered the outage:** the image and `cloud-init.yml` as of #6730 / ADR-145 (the
  first real `web-host-create` birth path).
- **Version(s) that restored the service:** none — service was never restored. The diagnosability fix
  lands in PR #6970 (ADR-147) and takes effect at the next fresh create.

## Impact details

### Services Impacted

None in production. `soleur-web-2` was never put into service:

- the `dns.tf` app record stays web-1-only;
- the #6575 `lb-weight-gate.sh` anti-pooling gate fail-closes;
- `web_tunnel_connector = each.key == "web-1"` means a fresh web-2 registers no cloudflared
  connector.

`soleur-web-1` was untouched throughout (the merge-path plan showed it as a strict `no-op`).

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerated by USER ROLE.

- Prospect: none — web-1 served all traffic at weight 200 throughout.
- Authenticated app user: none — no request was ever routed to web-2.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

The residual exposure is **not** user-facing: a dark host occupies a fleet slot and bills as a
running `cpx22` until it is destroyed.

### Revenue Impact

None from user impact. A small ongoing waste: one `cpx22` billing while dark.

### Team Impact

High relative to the (nil) user impact. A full diagnostic cycle produced no cause, and the
remediation had to be re-scoped mid-flight from "fix the download" to "ship the error channel
first" — the second time this class has cost a session (see the `2026-07-11` webhook-202/E2BIG
learning, same shape: a component reporting a state its own error channel could not corroborate).

## Lessons Learned

### Where we got lucky

The birth path had *already* been given a post-create boot-trail gate (#6730). Without it, a host
that is `running` at the provider level and dark at the OS level looks healthy to every other
signal — and the anti-pooling gate, not the boot gate, would eventually have been the thing standing
between a dark host and production traffic. We were also lucky that this was the fleet's *first*
real birth, so nothing depended on web-2 being available.

### What went well

- Detection was automated, immediate, and loud; the run failed rather than passing quietly.
- Attribution was solid: the `fatal` was on the `doppler_download` event itself and carried
  `host_id=155488316`, which resolved to `soleur-web-2` — so a shared-Sentry-project mismatch was
  ruled out explicitly rather than assumed.
- The remediation was correctly re-ordered to ship the error channel ahead of any speculative fix.

### What went wrong

- The single most useful bytes in the whole incident — the CLI's stderr and exit code — were thrown
  away one line before the failure was reported.
- The one Doppler call that was unbounded was the one that failed, leaving the channel structurally
  blind to the most likely shape of failure (a hang).
- The fatal was not host-scoped, so resolving *which* host emitted it required a separate Hetzner API
  lookup on a shared Sentry project.
- Diagnosis proceeded for a while by reasoning over hypotheses whose discriminator was known to be
  unavailable — the exact failure named in
  `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

| Issue | Item | Actor |
|---|---|---|
| #6969 | Decide the fate of the dark `soleur-web-2`: destroy-and-rebirth in one window (destroying re-arms the `host_creates` HALT because the host is declared in `var.web_hosts`), then read the named cause off the fresh birth. This PR scopes the decision out deliberately; the issue stays open to carry it. | agent-with-ack |
| #6971 | Extend the `host_name` tag to the `bootcmd` beacon and the inline `_emit`, add detail producers for the remaining boot stages, and migrate `/store/` → `/envelope/`. The inline `_emit` costs `user_data` bytes, so its tag must be measured against `WEB_GZIP_BUDGET`. | agent |
