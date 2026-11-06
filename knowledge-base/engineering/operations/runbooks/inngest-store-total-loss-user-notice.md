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

Copy the block, fill every `[...]` field, remove any line the fill table marks conditional, then send through the channel the incident owner and counsel choose. Before sending, search the copied block for `[` — any match means a missed field; do not send.

> **Subject: We lost automated work in your Soleur workspace**
>
> On [DATE UTC] we lost the store Soleur uses to queue and run automated work — drafts, reminders and approved actions waiting to execute[IF-PROJECT-LOSS: , and the history of those runs].
>
> We're sorry — we know some of this work mattered on a deadline.
>
> What this means for you:
>
> - One-off work queued or in progress at [LOSS TIME UTC] — drafts, reminders, approved actions — did not complete and was not automatically retried.
> - Reminders you had set — for any future date — may never fire.
> - Drafts or follow-up actions you expected around that time may never have appeared.[IF-PROJECT-LOSS:
> - Run history for affected work cannot be recovered.]
> - Your repositories and knowledge base content live in other systems and were not part of this store.
>
> What we did: [IF-RESTORED: we rebuilt the store and re-registered your automations; work scheduled since [RESTORE TIME UTC] runs normally.]
>
> What to do:
>
> - Think back over what you expected around [DATE] — a draft, a reminder, a follow-up — and re-run the action that would have created it where you can.
> - If you approved an action around [DATE] that never ran, approve it again[IF-WITHIN-23H: — a re-click within 23 hours of the original approval re-sends it][IF-PAST-23H: — that replays the request for us].
> - If a reminder that mattered did not fire, re-create it.
> - If something you lost is not covered above, reach us at [SUPPORT ROUTE].
>
> [ONE-SENTENCE follow-up line — owner fills at send time, e.g. "We've verified the rebuilt system and are watching it closely."]
>
> — The Soleur team

## Fill fields

| Placeholder / conditional | Supplied by | Source |
|---|---|---|
| `[DATE UTC]`, `[DATE]` | incident owner | the loss-mode finding's timestamps (the row that landed on "After a total loss") |
| `[LOSS TIME UTC]` | incident owner | the loss-mode finding — the point the store became unreadable |
| `[IF-PROJECT-LOSS: …]` (two spots) | incident owner | include only when the loss-mode finding lost the Postgres history project too (the `Volume deleted …, or project loss` row); for a volume-only loss the history survives, so delete both bracketed clauses and the bullet they mark — claiming lost history then is false |
| `[IF-RESTORED: …]` + `[RESTORE TIME UTC]` | incident owner | include the whole "What we did" line only when the rebuild/restore record verifies the store is serving again; delete it otherwise |
| `[IF-WITHIN-23H: …]` / `[IF-PAST-23H: …]` | incident owner | keep exactly one: the 23-hour clause only if the notice goes out within 23 hours of the oldest affected approvals (#10543); the alternative clause otherwise |
| `[SUPPORT ROUTE]` | incident owner | the support channel in force at send time (in-app, email alias, or status page per the incident's channel decision) |
| `[ONE-SENTENCE follow-up line]` | incident owner | the incident's verified end state — never a promise (see Constraints: no armed-reminder restoration promise) |
| re-arm verdict | incident owner | whether `inngest-rearm-reminders.sh` ran; if it did not run or covered only part of the store, delete nothing from "What to do" — the re-create-it line already carries the correct advice, and no sentence may claim reminders were restored |
| external-sender step | incident owner | `inngest-luks-cutover-6894.md` — the mail-provider-side counts + manual triage step for `email/inbound.received`; runs outside this notice |
