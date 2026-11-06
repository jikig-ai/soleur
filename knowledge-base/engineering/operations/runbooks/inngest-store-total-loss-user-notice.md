---
title: "Pre-drafted user notice — total loss of the Inngest store"
date: 2026-11-06
owners: engineering/ops
category: incident-communications
tags: [inngest, luks, incident, user-notice, total-loss]
applies_to:
  - knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md
related_issues: [10664, 9927]
---

# Runbook: pre-drafted user notice for a total loss of the Inngest store

**TL;DR:** the standing draft of the user notice the repository owner sends after a total loss of the Inngest store — queued events, in-flight run state, armed reminders, approved-but-unexecuted actions, and run history. Fill the `[...]` fields, send nothing else. Whether and when a notice goes out is the CLO's call, not this file's.

## What this file is

The ready notice text for the "After a total loss" path of [`inngest-luks-cutover-6894.md`](./inngest-luks-cutover-6894.md). The loss-mode rows that land here are `volume-gone`, `Both copies lost`, `LUKS header corrupted`, `Volume deleted despite protection, or project loss`, and the `fail_header` key-probe row. It exists so wording is never improvised mid-incident, while every claim the text makes is pre-checked against the measured evidence in that runbook.

## Send conditions are the CLO's call

This draft supplies text only. Whether notification is owed at all, to whom, on which channel, and when — the Art. 4(12)/33/34 assessment the cutover runbook already names — are the incident owner's decisions with counsel. The determination record lands in `knowledge-base/legal/audits/` and `knowledge-base/legal/breach-register.md`. Nothing below decides, implies, or pre-commits to any disclosure duty: the file exists so a notice that is owed does not start from a blank page.

## Constraints the notice text must keep

Each constraint is traceable to the C1 finding in `inngest-luks-cutover-6894.md` (the Superseded 2026-10-22 block and the event-class table). Do not weaken them at send time.

- The affected set is "all active users" as a floor — do not state a narrower set. Two groups sit outside even that floor: inactive founders, and external inbound-email senders.
- Never claim "no record survives" or "nothing identifies anyone". The evidence class is **partial**: a user-reference-capable column exists (`events.event_user`), and neither its non-null count nor the oldest row was measured.
- Never promise armed reminders will be restored. The re-arm path (`apps/web-platform/infra/inngest-rearm-reminders.sh`) covers `reminder.scheduled` only, and whether it ran is an incident-time fact, not a constant.
- The notice does not cover the external-sender group (`email/inbound.received`): an inbound email in flight at loss harms its sender, and a statutory request among them keeps its clock running. The runbook names the separate owner step for that group — this notice is not that step.
- Aggregate only: no per-user identifiers, per-user counts, or "N users affected" figures. A count the partial evidence cannot support is worse than none.

## The drafted notice

Copy the block, fill every `[...]` field, remove any line the fill table marks conditional, then send through the channel the incident owner and counsel choose.

> **Subject: An incident affected some automated work in your Soleur workspace**
>
> On [DATE UTC] we lost the store Soleur uses to queue and run automated work — drafts, reminders and approved actions waiting to execute — and the history of those runs.
>
> What this means for you:
>
> - Automated work queued or in progress at [LOSS TIME UTC] on [DATE] did not complete and was not automatically retried.
> - Drafts, reminders or follow-up actions you expected around that time may never have appeared.
> - Run history for affected work is not available.
> - Your repositories, knowledge base content and account records were not stored there.
>
> What we did: the store was rebuilt and your automations re-registered; work scheduled since [RESTORE TIME UTC] runs normally.
>
> What to do:
>
> - Check your dashboard for drafts or reminders you expected but never received, and re-trigger the underlying action where you can.
> - If you approved an action around [DATE] that never executed, approve it again — an approval click is safe to repeat within 23 hours of the original.
> - If a reminder that mattered did not fire, re-create it.
> - If something you lost is not covered above, write to [SUPPORT ROUTE].
>
> [ONE-SENTENCE follow-up line — owner fills at send time, e.g. the rebuild is verified and the watch is in place.]

## Fill fields

| Placeholder | Supplied by | Source |
|---|---|---|
| `[DATE UTC]`, `[DATE]` | incident owner | the loss-mode finding's timestamps (the row that landed on "After a total loss") |
| `[LOSS TIME UTC]` | incident owner | the loss-mode finding — the point the store became unreadable |
| `[RESTORE TIME UTC]` | incident owner | the rebuild/restore record; include the "work scheduled since" sentence only if the store is verifiably serving again |
| `[SUPPORT ROUTE]` | incident owner | the support channel in force at send time (in-app, email alias, or status page per the incident's channel decision) |
| `[ONE-SENTENCE follow-up line]` | incident owner | the incident's verified end state — never a promise (see Constraints: no armed-reminder restoration promise) |
| re-arm verdict | incident owner | whether `inngest-rearm-reminders.sh` ran; if it did not run or covered only part of the store, delete nothing from "What to do" — the re-create-it line already carries the correct advice, and no sentence may claim reminders were restored |
| external-sender step | incident owner | `inngest-luks-cutover-6894.md` — the mail-provider-side counts + manual triage step for `email/inbound.received`; runs outside this notice |
