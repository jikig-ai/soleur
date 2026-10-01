---
title: "Two inngest-host-replace applies each stranded the scheduler on an inherited `done`, and the channel that would have shown it cannot reach that host"
date: 2026-09-17
incident_pr: 8252
incident_window: "2026-09-17, two apply_target=inngest-host-replace dispatches; ~76 minutes combined with no live scheduler"
recovery_at: "2026-09-17 — recovered by `gh workflow run cutover-inngest.yml -f op=resume`"
suspected_change: "No code change. A standing state split: INNGEST_CUTOVER_FLIP lives in Doppler and survives a host replace; the done-owner marker it must be paired with lives on the root disk the replace destroys."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Two `apply_target=inngest-host-replace` dispatches each produced a host on which
`inngest-server` refused to start. Combined, the production scheduler was not live for
roughly 76 minutes. The guard that refused was working exactly as designed; nothing warned
before the replace, and the diagnostic channel the runbook names is structurally unable to
reach the machine in question, so the cause stayed invisible until the host journal was read
directly.

## Status

resolved — the scheduler was recovered by a single `op=resume` dispatch, and the
condition is now warned about before the replace (PR #8252). The underlying state split is
NOT removed; see Action Items.

## Symptom

After each replace, the dedicated inngest host came up and `inngest-server` refused to start
with:

```
BLOCK: cutover flag='done' but this host carries no done-owner marker at
/var/lib/inngest-cutover/done-owner — refusing a prod start on an INHERITED done (#7228)
```

From the app side this is indistinguishable from any other "scheduler is not running" —
dispatches fail, and the host is otherwise healthy.

## Incident Timeline

- **Start time (detected):** 2026-09-17, at the first `inngest-host-replace` apply.
- The replace completed successfully. Terraform reported no error: the *apply* is not what
  failed.
- `inngest-server` refused to start on the new host. The scheduler was dark.
- `/hooks/deploy-status` was consulted and returned a payload describing a healthy
  `inngest_server`. That payload was **web-1's** — see Detection.
- A second replace was dispatched. It produced the identical outcome, deterministically.
- The host journal was read directly (journald → vector → Better Stack), which surfaced the
  `BLOCK:` line above and named the cause.
- **Recovery:** `gh workflow run cutover-inngest.yml -f op=resume` → flag written
  `flushed` → the on-host 30s timer started the server, verified it, re-recorded the
  done-owner marker and completed to `done`, with **no re-FLUSHALL**, so the queue survived.

## Participants and Systems Involved

`hcloud_server` (dedicated inngest host), `inngest-server.service`,
`apps/web-platform/infra/inngest-server-flip-guard.sh`, Doppler `soleur-inngest/prd`
(`INNGEST_CUTOVER_FLIP`), `/mnt/data` (flush latch), the root disk
(`/var/lib/inngest-cutover/done-owner`), `scripts/cutover-inngest.sh` (`op=resume`),
`.github/workflows/apply-web-platform-infra.yml` (`inngest_host_replace`).

## Detection (+ MTTD)

Detection was the failure, not the fix.

**The runbook's own no-SSH recipe cannot reach this host.** `/hooks/deploy-status` was read
12 consecutive times from a pinned reader; **all 12** were answered by
`hetzner-123931471` (web-1), never by the dedicated host `hetzner-166317708`. This is not a
retryable coin-flip: the `/hooks` channel terminates on web-1, and the dedicated host runs no
listener and has no inbound rule (deny-all public firewall; the tunnel ingress is web-1's).
So a `deploy-status` read "about the inngest host" is structurally a reading of a different
machine, and `.github/workflows/restart-inngest-server.yml` — same endpoint — cannot reach it
either, which is why its verify step fails against a host it never contacted.

Worse, the payload it *does* return is plausible. On an earlier occasion the same endpoint
showed `inngest_server: inactive` with a two-day-old journal — which was web-1's **deliberate**
quiesce — and that was nearly acted on as a statement about a freshly replaced host.

The channel that does reach it is journald → vector → Better Stack: continuous rather than
hourly, and carrying host identity **in the row**, so pinning is a filter rather than a
routing hope.

## Triggered by

`apply_target=inngest-host-replace`, dispatched deliberately. No defect in the dispatch.

## Root-cause hypothesis (triage)

Initially read as "the replace failed" or "the guard is malfunctioning". Both were wrong: the
apply succeeded, and the guard refused correctly.

## Resolution

One dispatch — `gh workflow run cutover-inngest.yml -f op=resume` — plus the required-reviewer
approval that `op=resume` carries (`cutover-inngest.yml:78`, `environment: inngest-cutover`).

## Recovery verification

The FSM row `reason="flushed-resume-no-reflush"` followed by a return to `noop-done`, read via
Better Stack; and the scheduler serving again. Critically, **no re-FLUSHALL** — the post-flush
resume arm starts, verifies, re-records the marker and completes, so the live prod queue was
not wiped.

## Root Cause(s) — 5-Whys

1. **Why was the scheduler dark?** `inngest-server` refused to start.
2. **Why did it refuse?** `inngest-server-flip-guard.sh` found `INNGEST_CUTOVER_FLIP=done`
   with no matching done-owner marker on the host.
3. **Why was there no marker?** The marker lives on the root disk, which the replace
   destroys; the flag lives in Doppler, which the replace does not touch. The replace
   separates a pair that is only meaningful together.
4. **Why does the guard refuse rather than proceed?** Because proceeding is worse. A `done`
   the host never earned is not evidence a FLUSHALL happened, and starting on it could run a
   **second** prod scheduler (#7228, task 3.7). The refusal is the correct behaviour and must
   not be softened.
5. **Why did it take two replaces and a journal read to find out?** Nothing warned before the
   dispatch, and the diagnostic channel the runbook names answers about a different machine.
   The condition is fully knowable *before* the replace — the flag is one Doppler read away —
   but nothing read it.

## Versions of Components

Dedicated host `hetzner-166317708`, `host_role=dedicated`, `probe_schema=8`,
`data_mount_devid=scsi-0HC_Volume_106261946`. Guard as of
`apps/web-platform/infra/inngest-server-flip-guard.sh` at the incident commit.

## Impact details

Production scheduler not live for ~76 minutes across two replaces. Cron and event-driven
Inngest work did not run in those windows. **No data loss** — the queue survived (the recovery
path is explicitly non-destructive), and `/mnt/data` with its flush latch is re-attached by the
replace rather than recut. No personal data was exposed or accessed, so neither Art. 33 nor
Art. 34 is engaged; the trigger is availability only.

## Lessons Learned

**A guard that refuses correctly still owes a warning at the point of dispatch.** Every
ingredient of this outage was knowable before the apply: the flag is a single Doppler read,
and the marker's fate under a replace is a property of the design, not of the run. The failure
was that nothing looked.

**A diagnostic channel has a reachability property, and "it returned a payload" does not
establish it.** The endpoint answered every time — with another host's state. A read that
cannot reach its subject is worse than one that fails, because it returns something that looks
like an answer. Pinning has to be a filter on identity carried *in the row*, not a hope about
routing.

**`done` is not the only stranding value, and the reassuring message is the dangerous one.**
`inngest-server-flip-guard.sh` allowlists `{armed, flipping, flushed, done}` for a prod start;
everything outside refuses outright. Of the four inside, only `flushed` self-heals after a
replace: the `/mnt/data` flush latch survives, so `armed` and `flipping` drive the FSM to
`aborted`, which is itself outside the allowlist — and `op=resume`'s G1 accepts `done` **only**
(verified at `scripts/cutover-inngest.sh:2685`). So those two states strand with *no*
one-dispatch recovery at all.

## Remediated in the source PR

Shipped in PR #8252, so these are deliberately NOT action items — they are done, and a
row here would rot open. They are recorded because the next reader of this PIR needs to
know which of the failures above are already closed.

- A pre-dispatch preflight on `inngest_host_replace` reads `INNGEST_CUTOVER_FLIP` and warns
  before the replace, naming the recovery. It is advisory by design — it degrades open,
  because failing a replace over an advisory read would be worse than the condition it advises
  about — and it now distinguishes `done`, the `armed`/`flipping` no-recovery case, the
  outside-allowlist case, and `flushed`.
- `scripts/inngest-host-state.sh` reads the dedicated host over the channel that actually
  reaches it, pinned on `host=soleur-inngest` **and** `host_role=dedicated` (web-1 emits the
  same marker with `host_name=soleur-inngest-prd`, so `host_name` alone selects the wrong
  machine).
- The runbook now records that `/hooks/deploy-status` cannot reach this host, and that the
  `op=resume` recovery holds for a required-reviewer approval rather than completing on its
  own.

## Action Items & Follow-ups

| Issue | Item | Owner | Status |
|---|---|---|---|
| #7695 | Nothing in-repo clears a standing `/mnt/data` flush latch, so a replace from `armed`/`flipping` reaches terminal `aborted` with no recovery verb that accepts it. The gated `inngest-volume-recut` apply_target is the designed route. | agent | open |
