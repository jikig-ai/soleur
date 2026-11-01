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
Read on 2026-10-29 through the owner's own signed-in browser session; the figures were posted on #9927 at 17:28 UTC (the CTO agent copied them into the #9927 hold ledger). No console re-read is recorded since.

| Item | Count / state |
|---|---|
| Members of the project | 1 |
| Role of that member | Owner |
| Admins | 0 |
| Other roles (Member, Restricted) | 0 |
| Sign-in protection (two-factor) on the account | Active |
| API tokens listed for the project | 2 (count only: 1 Read, 1 Read & Write, as posted by the owner on #9927 on 2026-10-29) |

## Related measured items (the A6 row's prerequisites)

| Prerequisite | State as of 2026-10-31 | Owner fills in |
|---|---|---|
| A5 complete | no, as of 2026-10-31: `S5-A5-DONE` is not on #10136, and the #11218 sweeper reports NOT YET because #11215 is open; the earliest 48-hour point of the new-link soak (#11215, window opened 2026-10-30T15:15:48Z) is 2026-11-01T15:15:48Z | owner confirms yes / no, date |
| Measured re-read from the deployed #10405 emit | PR #10405 merged 2026-10-19; no comment on #9927 or #10136 records a read of the deployed ruleset | owner links one or marks "n/a" |
| Hetzner support answer on delete protection versus project delete and account closure | question reported sent on #9927 at 2026-10-29 17:28 UTC; no answer on #9927 as of 2026-10-31: pending | answer or "pending" |

## Statement (to be adopted by the owner)

> As of the console read of 2026-10-29 17:28 UTC, to my knowledge the only human member of the Hetzner
> project that holds the Inngest sole-copy volume was a single Owner (1 member, 0 Admins, 0 other roles);
> two-factor sign-in was active on the account; and the project's two API tokens (machine access paths: one
> Read and one Read & Write) are the ones I know and expect.
> I know of no other access. This statement is limited to what the console showed on the date of the
> check and does not cover Hetzner's own staff access or what Hetzner retains after a project or account
> closure (not established; see ADR-282, addenda of 2026-10-23 and 2026-10-28).

## Signature block

- Signed by the owner (human, not an agent), by their own GitHub comment on #10136 that posts the statement above verbatim: ____________________ (comment URL)   UTC date and time: ____________Z
- Attested by `soleur:legal:clo` (v1 internal attestation, separate from the owner's signature; not external counsel advice), scope limited to the statement and claim limits above; it does not discharge the 2026-11-12 re-review, A5 or the TLS rows: ____________________   date: ____________

## CLO review, 2026-10-31

DO NOT ATTEST YET. An in-session instruction transcribed by an agent is not the owner's
signature (this record and the A6 row of the runbook both exclude it), and A5 is not complete. The CLO attests on
resubmission once the owner's own comment exists and A5 is done.

## After signing (owner)

1. Rename the file to the UTC signing date if it differs from the date in the name.
2. Link it from #10382 and #10136.
3. Post `S6-A6-DONE: <UTC time ending in Z>` on #10136.

## Claim limits

This statement does not establish A5, the TLS posture or the Hetzner support answer. No console re-read is recorded
between the 2026-10-29 read and the drafting of this record (a re-read before signing needs its own dated
evidence section), and two-factor on the account says nothing about account recovery.

Counts and roles as the console labels them on the read date. Not evidence of past access, of Hetzner-side
access, or of what the two tokens can do beyond the per-token level the owner adds. A later change of
members or tokens needs a new record.
