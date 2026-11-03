---
title: "A7 ledger: leg-2 accepted-risk record for the Inngest sdk_url poll (#10136)"
status: record
date: 2026-11-02
related: [10136, 10538, 10479, 10205, 11294]
---

# A7 ledger: leg-2 accepted-risk record (Inngest `sdk_url` poll, #10136)

## Provenance

Filed on 2026-11-02 by a Claude Code agent. It is not a human-typed record. The accepted-risk text was
posted by an agent on #10136 at the owner's in-session instruction; this file points at it and quotes the
owner's confirmation. The literal line "SIGNED BY OWNER (human, not an agent)" is not used and is not claimed.

## The record

- Accepted-risk record: <https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6580646693> (agent-posted,
  2026-11-02T15:11:51Z). Scope: the leg-2 poll only (the Inngest server on 10.0.1.40 polls the app at
  `http://10.0.1.10:3000/api/inngest` every 60 s over plain HTTP on the private network, tracked as #10538).
- Accepted until 2026-11-12 (CLO bridge date). Extension to 2026-12-10 only if the replacement is merged by
  2026-11-12 and the replace-window go is dated. After 2026-12-10 the row lapses and is not accepted again.
- Voids on a server beyond the five attached to 10.0.1.0/24, or any public or cross-network exposure of the poll.
- Compensating controls were measured on 2026-11-02 (rotation of the dedicated Inngest pair, nftables re-read
  through `tls-health`, read-only Hetzner enumeration: 5 servers, all Jikigai's). Details are in the record.

## Owner instruction (comment 6581495825)

<https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6581495825>, quoting the owner's words in session:

> I give you my delegation to do it
> go ahead on A7 too

## Owner confirmation (comment 6582099901)

<https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6582099901>, agent-posted 2026-11-02T16:15:26Z on the
owner's in-session reply. Owner's words, verbatim:

> I confirm A7 as read

The agent-drafted sentence the owner confirmed (drafted by the CLO agent and shown to the owner together with
the full text of the record before they replied; not typed by the owner into the thread):

> On 2026-11-02, in session, I instructed the agent to post the A7 accepted-risk record on #10136 (posted as
> comment 6580646693; my instruction recorded in comment 6581495825). I read the risk text before instructing.
> That instruction is my act and my acceptance of the risk as stated. I understand the record was posted by an
> agent and not typed by me, and I ask that it satisfy row A7.

## CLO ruling, 2026-11-02

> an owner's in-session instruction and confirmation suffice for A7; the literal "SIGNED BY OWNER (human, not an
> agent)" line is not used for an agent-posted record.

## What this does not do

- It does not extend the accepted-until date, and it does not cover leg 1 (the zot records) or any other
  link. Signing the zot records and any extension past 2026-11-12 remain owner-only acts.
- It does not close #10136; the Inngest TLS implementation has not started.
