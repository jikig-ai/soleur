---
title: "A6 \"no known access\" record — Hetzner project holding the Inngest sole-copy volume"
status: signed-relayed-and-attested
date: 2026-11-07
refreshed: 2026-11-07
related: [9927, 10382, 10136, 11218]
related_adrs: [ADR-282]
brand_survival_threshold: single-user incident
---

# A6 "no known access" record — Hetzner project holding the Inngest sole-copy volume

owner sentence relayed 2026-11-07T17:31Z on #10136 (S6-A6-RELAYED, own words, Agent-drafted text: no); attested by soleur:legal:clo 2026-11-07 (#10382 comment 6711794462)

> **SIGNED BY RELAY AND ATTESTED.** The owner's sentence was relayed on #10136 at
> 2026-11-07T17:31:48Z under the 2026-11-02 signing route (`S6-A6-RELAYED`, `Agent-drafted text: no`,
> not typed by the owner into the thread; this second relay supersedes a 13:31Z relay whose disclosed
> drafted flag the CLO refused — see "Owner's own sentence"), and `soleur:legal:clo` attested it on
> #10382 at 2026-11-07 (comment 6711794462; v1 internal attestation, not external counsel advice).
> The file name carries the UTC date of signing. Counts and roles only: no names, no email addresses,
> no token values.

> **Superseded 2026-11-02 (CLO and CTO rulings; ruled in session, recorded in
> `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`, section 9, and in the A5/A6/A7 rows of
> `knowledge-base/engineering/operations/runbooks/inngest-server.md`), as to how this record is signed. The history below is left as written.**
> "Owner-signed" (line "What this record is"), "Signed by the owner (human, not an agent)" (Signature block), "An in-session instruction transcribed
> by an agent is not the owner's signature" (CLO review of 2026-10-31) and "Post `S6-A6-DONE`" (After signing) no longer describe the only route.
> The owner's knowledge sentence is still ONLY the owner's own words: an agent never drafts it, so the "Statement
> (to be adopted by the owner)" below is evidence-framing text, not a sentence the owner adopts by agreeing. The owner gives that sentence once in
> session; an agent posts the record under a provenance block that quotes it verbatim ("Posted by ... on the owner's instruction given in session at ...
> Owner's words, verbatim: ... Agent-drafted text: yes/no. Not typed by the owner into this thread"), then posts `S6-A6-RELAYED:` (never `S6-A6-DONE:`)
> on #10136; the owner may still type `S6-A6-DONE:` themselves. The CLO still attests separately, and an agent-posted record that claims human
> typing is void.

> Superseded 2026-11-06: the "Statement (to be adopted by the owner)" block mentioned above was removed (see "Owner's own sentence" below). The owner's sentence field is empty and no agent drafts it.

## What this record is

The A6 row of the post-merge production-envelope table in `knowledge-base/engineering/operations/runbooks/inngest-server.md`
asks for the owner's own knowledge sentence about access to the Hetzner project that holds `hcloud_volume.inngest_redis_luks`
(volume `106903269`), the only copy of the Inngest queue and run state. It is linked from #10382 and #10136.
The member list below is an evidence section of this file, not a second record.

## API read, 2026-11-06T08:26:19Z (not the console figures)

Source: the Hetzner Cloud API, read with the project's read-only token (token class: read-only; no value recorded). One read of the volume and one of the server list; no write verb. Read at the UTC time in the heading.

| Item | Value |
|---|---|
| Volume id | 106903269 |
| Delete-protection flag | on |
| Volume status | available |
| Servers in the project | 5 (count only; the servers carry no role labels, so no roles are listed) |

This read says nothing about members, two-factor status or API tokens, and it is not a substitute for the console re-read below. Queue and run state is held on a single volume with no off-project copy; recoverability after a project or account loss is not established. The same read with an invalid token was refused with status 401 and rendered as "refused" (the failure mapping works).

## Evidence: Hetzner console, last console read 2026-10-29

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
| Console re-read of members, two-factor and API tokens | PENDING, filled from the owner's own browser session. No agent fills this cell. |

## Related measured items (the A6 row's prerequisites)

| Prerequisite | State (cells updated 2026-11-06) | Owner fills in |
|---|---|---|
| A5 complete | recorded complete on #10136 (updated 2026-11-06): `S5-A5-DONE` 2026-11-02T14:28:00Z (agent-posted at owner delegation) and `S5-A5-RELAYED` 2026-11-02T21:51:04Z (owner's words). It covers the dedicated Inngest key pair only; the other exposed keys are still rotating, see `knowledge-base/legal/audits/2026-11-02-a6-no-known-access-record-inngest-keys.md` and the CLO re-assessment due 2026-11-08 | owner re-checks A5 at signing |
| Measured re-read from the deployed #10405 emit | PR #10405 merged 2026-10-19; the 2026-11-02 keys record holds a tls-health re-read (`nft_rules=7`, `legacy_8288_packets=0`) that is available as evidence (updated 2026-11-06) | n/a (owner, in session 2026-11-07) |
| Hetzner support answer on delete protection versus project delete and account closure | received 2026-11-02: a paraphrase of the support reply is in #9927 comment 6577564178 (updated 2026-11-06); a support reply, not a contract term | owner links the answer |

Superseded 2026-11-06: the three cells above read as follows on 2026-10-31, kept as history. A5: "no, as of 2026-10-31: `S5-A5-DONE` is not on #10136, and the #11218 sweeper reports NOT YET because #11215 is open; the earliest 48-hour point of the new-link soak (#11215, window opened 2026-10-30T15:15:48Z) is 2026-11-01T15:15:48Z". Measured re-read: "PR #10405 merged 2026-10-19; no comment on #9927 or #10136 records a read of the deployed ruleset". Hetzner answer: "question reported sent on #9927 at 2026-10-29 17:28 UTC; no answer on #9927 as of 2026-10-31: pending".

## Owner's own sentence

Posted by Devin (agent) at 2026-11-07T17:31:48Z on the owner's instruction given in session at 2026-11-07T17:31:00Z. Owner's words, verbatim:

> I'm not aware of any external access to the Inngest host's LUKS key material

Agent-drafted text: no (the sentence is the owner's own composition in session; no agent proposed or supplied it). Not typed by the owner into this thread. Relayed on #10136 as `S6-A6-RELAYED`: <https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6710705414>.

Superseded 2026-11-07: an earlier relay (comment 6707582642, 13:31:17Z) carried a sentence the agent had proposed as an example (`Agent-drafted text: yes`), which failed resubmission condition 1 (`Agent-drafted text: no`); the CLO refused attestation on #10382 (comment 6709536378). The owner then composed the sentence above in their own words. The earlier block is kept as history.

An agent-written evidence-framing block stood here from 2026-10-30 until 2026-11-06. It was removed because an agent never drafts the owner's knowledge sentence. It is recoverable from git history (commit b959fe4b84).

## Signature block

- Signed by the owner (human, not an agent) through the 2026-11-02 agent-relay route, by the `S6-A6-RELAYED` comment on #10136 that posts the owner's own sentence (see "Owner's own sentence"), in the owner's words: <https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6710705414>   UTC date and time: 2026-11-07T17:31:48Z
- Attested by `soleur:legal:clo` (v1 internal attestation, separate from the owner's signature; not external counsel advice), scope limited to the owner's own sentence and the claim limits above; it does not discharge the 2026-11-12 re-review, A5 or the TLS rows: attested via <https://github.com/jikig-ai/soleur/issues/10382#issuecomment-6711794462>, conditions in #10382 comment 6680610653 verified; anchored to the 2026-10-29 console figures (owner console re-read pending)   date: 2026-11-07

Superseded 2026-11-06: the two lines above used to refer to a "statement above"; that block was removed. They now point at the owner's own sentence field, which stays empty until the owner gives it in their own words.

## CLO review, 2026-10-31

This heading records a refusal to attest. It is not an attestation and does not fill the attestation line above.

DO NOT ATTEST YET. An in-session instruction transcribed by an agent is not the owner's
signature (this record and the A6 row of the runbook both exclude it), and A5 is not complete. The CLO attests on
resubmission once the owner's own comment exists and A5 is done.

Superseded in part 2026-11-06: the A5 reason is resolved for the dedicated Inngest key pair only (see the A5 cell; the other exposed keys are still rotating); the signing-route reason was superseded by the 2026-11-02 rulings. This refusal was not an attestation, and no attestation exists. The conditions for resubmission are posted on #10382 (<https://github.com/jikig-ai/soleur/issues/10382#issuecomment-6680610653>).

## CLO attestation, 2026-11-07

`soleur:legal:clo` attests the owner's own sentence and the claim limits below (v1 internal
attestation, separate from the owner's signature; not external counsel advice). This attestation
takes effect on the merge of the PR that carries it; until that merge it is a record in an
unmerged branch.

Checked against the seven resubmission conditions posted on #10382
(<https://github.com/jikig-ai/soleur/issues/10382#issuecomment-6680610653>) and the 2026-11-07
refusal (<https://github.com/jikig-ai/soleur/issues/10382#issuecomment-6709536378>):

- Condition 1 — holds. The owner's sentence was composed by the owner in session and relayed on
  #10136 at 2026-11-07T17:31:48Z under the 2026-11-02 provenance route with `Agent-drafted
  text: no` (<https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6710705414>), quoted
  verbatim in "Owner's own sentence". The superseded 13:31Z relay (`Agent-drafted text: yes`)
  is kept as history.
- Condition 2 — holds. "I'm not aware of any external access to the Inngest host's LUKS key
  material" is a bounded knowledge claim; the claim limits keep Hetzner staff access, retention
  and post-closure outcomes outside what this record establishes.
- Condition 3 — holds at its fallback. The console re-read cell remains PENDING, so this
  attestation is anchored only to the dated 2026-10-29 console figures.
- Condition 4 — holds. The measured-re-read cell reads `n/a (owner, in session 2026-11-07)`.
- Conditions 5–7 — hold. The claim-limit paragraphs are present; no "signed" or "attested"
  wording predates this attestation; the 2026-11-12 re-review, A5 and the TLS rows are not
  discharged by this record.

This attestation does not perform the owner-side steps in "After signing (owner)": linking the
record from #10382 and #10136 and posting `S6-A6-DONE:` remain the owner's option under the
2026-11-02 route (an agent never posts `S6-A6-DONE:`). The console re-read cell also remains
owner-fillable: a post-2026-11-02 read would move the anchor off the 2026-10-29 figures in a new
record.

## After signing (owner)

1. Rename the file to the UTC signing date if it differs from the date in the name.
2. Link it from #10382 and #10136.
3. Post `S6-A6-DONE: <UTC time ending in Z>` on #10136.

## Claim limits

Hetzner staff access and retention after a project or account closure are not established. The console figures are dated 2026-10-29. The owner's sentence, when it exists, covers the owner's own knowledge at the time it is given.

Hetzner's support reply of 2026-11-02 (paraphrase, #9927 comment 6577564178) says that delete protection does not guarantee data retention after account termination, that Admins and Members can lift protection and delete volumes, and that project deletion checks for protected resources. This record therefore does not establish that the volume survives a project deletion, an account suspension or closure, or deletion by any person holding Admin or Member rights.

Delete protection is a guard against accidental deletion by the project's own users. It is not a retention guarantee and not an access control against project members. The volume is the only copy; no off-project copy exists. An off-project ciphertext copy is deferred, not declined, and is not built.

The 2026-11-06 API read shows only the volume, its delete-protection flag and the server list as of its UTC time. It does not show members, two-factor status or tokens, and it is not a substitute for the console re-read.

This record does not establish A5, the TLS posture or the Hetzner support answer. No console re-read is recorded
between the 2026-10-29 read and the drafting of this record (a re-read before signing needs its own dated
evidence section), and two-factor on the account says nothing about account recovery.

Counts and roles as the console labels them on the read date. Not evidence of past access, of Hetzner-side
access, or of what the two tokens can do beyond the per-token level the owner adds. A later change of
members or tokens needs a new record.
