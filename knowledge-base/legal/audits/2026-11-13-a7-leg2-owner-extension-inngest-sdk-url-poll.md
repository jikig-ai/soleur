---
title: "A7 ledger: owner extension of the leg-2 accepted-risk record for the Inngest sdk_url poll (#10538)"
status: record
date: 2026-11-13
related: [10136, 10538, 10479, 10205]
---

# A7 ledger: owner extension, leg-2 Inngest `sdk_url` poll

## Provenance

Filed on 2026-11-13 by a Claude Code agent. It is not a human-typed record and does not use the literal line
"SIGNED BY OWNER (human, not an agent)". The owner's acceptance below was given in session, in answer to a question
that showed the full text to be recorded. The same route carried the 2026-11-02 record
(`2026-11-02-a7-leg2-accepted-risk-ledger-inngest-sdk-url-poll.md`, CLO ruling 2026-11-02).

## Why an extension is needed

The 2026-11-02 record accepted the leg-2 poll "until 2026-11-12 (CLO bridge date)" with an extension to 2026-12-10 "only if
the replacement is merged by 2026-11-12 and the replace-window go is dated. After 2026-12-10 the row lapses and is
not accepted again." #10538 (the replacement) is still open, so the extension condition did not hold and the
acceptance lapsed at 2026-11-13T00:00Z. From that moment the required `encryption-posture` check failed on every
merge-queue run and the queue ejected every PR.

## The owner's acceptance (verbatim wording shown to, and chosen by, the owner)

> On 2026-11-13 I, the owner, accept the leg-2 Inngest sdk_url poll (10.0.1.40 to 10.0.1.10:3000/api/inngest, plain
> HTTP on 10.0.1.0/24) until 2026-11-20, because the replacement (#10538) is not merged. The 2026-11-02 voids and
> compensating controls still apply. I will not extend past that date.

The owner chose the date 2026-11-20 from the options 2026-11-20 and 2026-12-10, in session on 2026-11-13.

## Scope and limits

- Scope: the leg-2 poll only. It does not cover leg 1, the zot records, the Cloudflare-to-origin hop (#10479) or any
  other link.
- Voids carry over unchanged: a server beyond the five attached to 10.0.1.0/24, or any public or cross-network
  exposure of the poll; any non-Jikigai peer on the network; pointing `--sdk-url` at the public host while
  Cloudflare to origin is flexible.
- The compensating controls were measured on 2026-11-02 and were not re-measured for this extension: the agent had
  no read-only Hetzner credential available in this session. The voids are therefore stated, not re-verified.
- After 2026-11-20 the row lapses again. Any further extension is a new owner act and needs a record that begins
  "SIGNED BY OWNER (human, not an agent)" or a fresh in-session instruction the CLO rules sufficient.
- The ledger row records the new date and cites this file. The agent edit moves a date the owner named. It is not
  a signature.

## Companion change

The Cloudflare-to-origin row (#10479) is moved from 2026-11-12 to its stated hard stop 2026-11-19 in the same change,
as a bounded slip inside the CLO-ruled bound. It is not an acceptance and not an extension, and the 2026-10-27 CLO
ruling that the hop is to be fixed stands.
