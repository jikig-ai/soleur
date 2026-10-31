---
title: "A6 \"no known access\" record — Hetzner project holding the Inngest sole-copy volume"
status: draft-unsigned
date: 2026-10-30
related: [9927, 10382, 10136, 11218]
related_adrs: [ADR-282]
brand_survival_threshold: single-user incident
---

# A6 "no known access" record — Hetzner project holding the Inngest sole-copy volume

> **DRAFT, NOT SIGNED, NOT ATTESTED.** This file is prepared for the owner. It is not a record until the
> owner signs it and `soleur:legal:clo` attests it separately. No agent signs it or sends it. The file name
> carries the UTC date of signing; if signing happens on another day, rename the file to that date before
> filing. Counts and roles only: no names, no email addresses, no token values.

## What this record is

The A6 row of the post-merge production-envelope table in `knowledge-base/engineering/operations/runbooks/inngest-server.md`
asks for one owner-signed statement that, as far as the owner knows, nobody outside the intended
operator set has access to the Hetzner project that holds `hcloud_volume.inngest_redis_luks`
(volume `106903269`), the only copy of the Inngest queue and run state. It is linked from #10382 and #10136.
The member list below is an evidence section of this file, not a second record.

## Evidence: Hetzner console, read-only check

Source: Hetzner Console, the project's Members, Security and API tokens views. Read-only; nothing changed.
Read on 2026-10-29 at 17:28 UTC (the owner's own check; recorded by the CTO agent in the #9927 hold ledger).

| Item | Count / state |
|---|---|
| Members of the project | 1 |
| Role of that member | Owner |
| Admins | 0 |
| Other roles (Member, Restricted) | 0 |
| Sign-in protection (two-factor) on the account | Active |
| API tokens listed for the project | 2 (count only: 1 Read, 1 Read & Write, as posted by the owner on #9927 on 2026-10-29) |

## Related measured items (the A6 row's prerequisites)

| Prerequisite | State at drafting | Owner fills in |
|---|---|---|
| A5 complete | not read by the drafting agent | yes / no, date |
| Measured re-read from the deployed #10405 emit | not read by the drafting agent | link or "n/a" |
| Hetzner support answer on delete protection versus project delete and account closure | question sent 2026-10-29 17:28 UTC; no answer found on #9927 as of 2026-10-30 | answer or "pending" |

## Statement (to be adopted by the owner)

> As of the UTC date and time below, to my knowledge the only person with access to the Hetzner project
> that holds the Inngest sole-copy volume is the single Owner shown above; no Admin or other member exists;
> two-factor sign-in is active; and the two project API tokens listed are the ones I know and expect.
> I know of no other access. This statement is limited to what the console showed on the date of the
> check and does not cover Hetzner's own staff access or what Hetzner retains after a project or account
> closure (not established; see ADR-282, addenda of 2026-10-23 and 2026-10-28).

## Signature block

- Signed by the owner (human, not an agent): ____________________   UTC date and time: ____________Z
- Attested by `soleur:legal:clo` (separate attestation, not a delegation): ____________________   date: ____________

## After signing (owner)

1. Rename the file to the UTC signing date if it differs from the date in the name.
2. Link it from #10382 and #10136.
3. Post `S6-A6-DONE: <UTC time ending in Z>` on #10136.

## Claim limits

Counts and roles as the console labels them on the read date. Not evidence of past access, of Hetzner-side
access, or of what the two tokens can do beyond the per-token level the owner adds. A later change of
members or tokens needs a new record.
