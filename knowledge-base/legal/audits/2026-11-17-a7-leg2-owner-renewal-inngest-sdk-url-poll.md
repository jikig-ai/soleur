---
title: "A7 ledger: owner renewal before expiry of the leg-2 accepted-risk record for the Inngest sdk_url poll, to 2026-12-10 (#12742)"
status: record
date: 2026-11-17
related: [10136, 10538, 12742, 12887, 10479, 10205]
renews: "2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md"
outer_limit: 2026-12-10
---

# A7 ledger: owner renewal before expiry, leg-2 Inngest `sdk_url` poll

## Provenance

Filed on 2026-11-17 by a Claude Code agent. It is not a human-typed record and does not use the literal line
"SIGNED BY OWNER (human, not an agent)". The owner's renewal below was given in session, in answer to a question
shown to the owner. The CLO agent ruled on 2026-11-17 that this in-session renewal suffices (agent ruling, not
counsel advice). The same route carried the 2026-11-02 and 2026-11-13 records.

## Why a renewal is needed

The 2026-11-13 acceptance runs until 2026-11-20 (`2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`).
The work that ends the plain-HTTP poll (#12742: the owner's `inngest-host-replace` and its measurements) is still in
progress and cannot finish by then. With `expires_on: 2026-11-20` the required `encryption-posture` check fails on
every PR from 2026-11-21T00:00Z.

## The question shown and the owner's words (verbatim)

The question shown to the owner, in session on 2026-11-17:

> Background-jobs link: on 13 Nov you accepted, until 20 Nov, that the background-jobs server keeps calling the app
> over unencrypted HTTP on the private network. The fix (switching it to the public encrypted address and replacing
> that server) is still a draft and its safety checks are not green, so it cannot be done by the 20th. If nothing is
> accepted, the required encryption check fails on every PR from the 20th. Renew the acceptance until 10 Dec? Your
> earlier record says 10 Dec is the last date that can ever be accepted.

The two options shown, with their descriptions (verbatim):

- "Renew until 10 Dec": "I'll ask the legal agent to write the new acceptance record in your words and put it in
  place before the 20th. If the fix isn't in by 10 Dec, no further renewal is possible."
- "Let it lapse on 20 Nov": "From the 20th, every PR fails the encryption check until the server is replaced."

Option chosen: "Renew until 10 Dec". The owner's own typed words, at 2026-11-17T16:54:35Z (the session transcript's
timestamp of the answer; "about 16:55Z" in the ledger and the #12742 comment):

> 1 but let's make sure we prioritize the work to avoid extending another time

What the question did and did not show: it named the link in plain words and referred to the 13 Nov acceptance. It
did not name the addresses, the voids or the compensating controls (nor did either option description). Those terms
come from the 13 Nov acceptance and carry over unchanged. The question said the check fails "from the 20th"; it
actually fails from 2026-11-21T00:00Z. That does not change the act.

Only the quoted sentence is the owner's; the rest of this record is agent text. The answer (16:54:35Z) predates the
first measurement of the 2026-11-16 leg-1 event below (CTO agent read, about 17:06Z), so the question did not mention
it. Per the CLO ruling of 2026-11-17 the owner is told afterwards, in plain words, without being asked again, and may
withdraw this renewal.

## What the owner renewed

- **Label.** A renewal before expiry, on the same terms. It is not the 2026-11-02 conditional extension, which is
  dead, and not a new acceptance after a lapse.
- **Scope.** The leg-2 poll only: the Inngest host (10.0.1.40) polls `http://10.0.1.10:3000/api/inngest` over plain
  HTTP on 10.0.1.0/24 every 60 s. It does not cover leg 1, the zot records, Cloudflare to origin (#10479, row 7) or
  any other link.
- **Until.** 2026-12-10, the outer limit set on 2026-11-02.
- **The owner's 2026-11-13 statement** "I will not extend past that date" is superseded by the owner's own act of
  2026-11-17, quoted above. An agent did not supersede it.

## Voids (carried over verbatim from 2026-11-02 and 2026-11-13)

- A server beyond the five attached to 10.0.1.0/24, or any public or cross-network exposure of the poll.
- Also not accepted: any non-Jikigai peer on the network, and pointing --sdk-url at the public host while
  Cloudflare to origin is flexible (#10479).

The voids apply by their own terms. The renewal does not cover any state in which one holds.

## Compensating controls (re-measured read-only 2026-11-17; re-read 2026-11-17T17:31Z and 2026-11-18T09:24Z; before merge)

- Hetzner `GET /v1/servers` and networks with `HCLOUD_TOKEN_READONLY`, 2026-11-17T17:04-17:07Z: 5 servers, all Jikigai's (soleur-web-platform 10.0.1.10, soleur-web-2 .11, soleur-git-data .20, soleur-registry .30, soleur-inngest .40); one network, soleur-private (12414183), only subnet 10.0.1.0/24, 5 servers attached and their ids equal to the project's own server ids, 0 load balancers, `expose_routes_to_vswitch` false. No void.
- tls-health (Better Stack), query window 2026-11-13T00:43Z to 2026-11-17T17:07Z, run by the CTO agent (logged 17:06Z): 1,329 rows (the planner's 17:11Z re-run: 1,330 rows, same values), max gap 320 s, one host (soleur-inngest), one boot_id (5319e63a); unit active, listener 1, `nft_rules=7`, `nft8443_sha256` unchanged from 2026-11-13 (1d224d03…58e4cf), `served_sha256==cert_sha256`, `tls_8443` rising.
- `legacy_8288` is **not 0**. It rose from 0 to 12 between the readings at 2026-11-16T12:04:32Z and 12:09:34Z on the same boot, and has stayed at 12 since. The counter counts TCP packets of any flags (how many carried payload was not measured) to the Inngest host's legacy :8288 listener from the two web hosts' private IPs only. That is leg 1 (ledger row 5), not this leg, and not a foreign peer. Cause not verified: it coincides with the web-2 host replace (`apply-web-platform-infra.yml` run 43862798565, 12:01:10Z-12:08:55Z). Candidates on a newly born web host: its first container starting on the http literal, which row 5 names, or the web-host probes' default `http://10.0.1.40:8288` before the link env file exists, which row 5 covers only by its general sentence that the legacy :8288 listener stays open and counted. Packet contents were not measured. The counter is not reset, because a reboot would stop the TLS listener (#11081). Tracked as #12887; breach-register row of 2026-11-17 (not a personal data breach on the measured facts).
- CLO ruling 2026-11-17: this is a disclosed leg-1 residual, stated here as measured fact. It does not void or halt this leg-2 renewal.
- Source: #12742 comment 6974401670 (posted 2026-11-18), which carries every value above with its reader and time, and the work phase's re-reads (all unchanged). The merge-day re-read is to be written in the body of PR #12884 before it is enqueued; if that body carries no merge-day re-read line, none was made. The values above are the plan-time reads (CTO agent 17:04-17:07Z; planner 17:11Z), labelled with their times.

## Leg-1 plaintext event: breach assessment

CLO agent determination, 2026-11-17 (agent ruling, not counsel advice). The same determination is posted, dated, on #12887 as
comment 6955805845 (2026-11-17T17:32:55Z), with the Hetzner read time (17:31:11Z) and a likely-cause note added.

- **Event.** 12 TCP packets (any flags; payload not measured) to the Inngest host's plaintext legacy :8288 listener from the web hosts' private IPs, between
  the tls-health readings at 2026-11-16T12:04:32Z and 12:09:34Z (leg 1, ledger row 5). Cause not verified (it
  coincides with the web-2 host replace, run 43862798565). Packet contents not measured.
- **Awareness:** 2026-11-17T17:07Z (CTO agent read-only measurement, not a monitor). The 72 hours run to
  2026-11-20T17:07Z.
- **Determination:** not a personal data breach on the measured facts. **Art. 33: No. Art. 34: No.** Nothing shows
  unauthorised access or disclosure; the only members of the network are the controller's own servers; Hetzner runs
  the network as processor.
- **Evidentiary limbs inconclusive: Yes.** Not measured: what the packets contained (by code read they may carry
  `INNGEST_EVENT_KEY` and event payloads, which can include personal data) and the cause.
- **Key rotation** is not legally required on these facts; whether to rotate is the CTO's call (#10540; row 5 says a key
  sniffed before the flip stays valid until it is rotated; the same holds for any key carried in these packets).
- **Reopen trigger:** any later evidence of a foreign peer, or exposure of the network, during 2026-11-16T12:04-12:10Z.
- Row 5's ledger cell is not edited: its disclosure already covers the event.

## No further renewal

After 2026-12-10 the row lapses and is not accepted again: no renewal and no new acceptance, by any route,
in session or typed, by the owner or by an agent. If #12742 has not converted ledger row 6 by then, the required
`encryption-posture` check fails on every PR from 2026-12-11T00:00Z. The only cure is ending the plain-HTTP poll
and measuring that it stopped (#12742). Weakening the lint, the workflow or the ruleset is not a cure.

## Gap

None. The owner renewed on 2026-11-17, before the 2026-11-20 acceptance ran out.

## Owner's instruction on priority

The owner instructed, in the words quoted above, that the #12742 work be prioritized so that no further extension
is needed. It is recorded as an instruction to the work, not as a term of the acceptance. #12742 is raised to
`priority/p1-high`.

## Owner items

- The owner's own words for the 2026-11-13 acceptance (Q-3) stay owner-pending on #12742. The 2026-11-17 words
  concern this renewal and do not supply them after the fact.
- The owner-typed "SIGNED BY OWNER" record that #12742 item 8, runbook precondition 4 and the 2026-11-13 addendum
  required if the replace landed after 2026-11-20 is no longer required for a replace before 2026-12-10
  (CLO ruling 2026-11-17). It is superseded, not discharged: nobody typed it.

## Statements this renewal supersedes

In this PR (Superseded markers added; text as filed kept):

- `2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`: "After 2026-11-20 the row lapses again"; "I will
  not extend past that date"; "If the owner's act lands after 2026-11-20, a record that the owner types ... is
  required"; "Required only if the owner's `inngest-host-replace` (#12742) lands after 2026-11-20".
- `2026-11-counsel-review-10479.md`: "The acceptance lapses again after 2026-11-20 unless the owner's replace has
  run or an owner-typed record exists." (the frontmatter `re_evaluation_triggers` corrected in the field; an `addenda`
  entry records the correction and its old wording).
- `inngest-server.md` (append-only notes, CTO ruling 2026-11-17): "the owner acceptance recorded by PR #12733 runs to
  2026-11-20 only" (the 2026-11-13 CLO note under the legal bridge-date item); "the owner acceptance runs to 2026-11-20"
  (the #10538 row of "Tracked follow-ups"); precondition 4, "If the replace lands after 2026-11-20, the owner-typed record
  the CLO ruling requires exists first": superseded by this renewal for a replace before 2026-12-10, not discharged;
  the precondition-1 note's "and so is the 2026-11-20 limit in item 4" (its own one-line marker).
- `2026-11-counsel-review-10479.md` `open_follow_ups` Q-2: "The replace must run by 2026-11-20, or else an owner-typed
  record ... is required" (inline bracket, same form as Q-1's).
- `ADR-294-inngest-link-tls-terminator-and-flagged-flip.md`: "the acceptance runs to 2026-11-20" (the 2026-11-13
  blockquote; a dated note under it says this is a renewal, not the dead 2026-11-02 extension).

On GitHub: #12742 item 8, a marker added to the issue body (2026-11-18).

## What this does not do

- It is not a signature, and the ledger edit is not one: it moves a date the owner named.
- It does not run, authorize or schedule the `inngest-host-replace`, and it does not touch PR #12876.
- It does not change the lint, `ci.yml`, any ruleset, row 7 or any published legal wording (#12742 item 7).
- It does not close #10538 (closes only as "not planned, superseded by #12742") or #12742.
- It does not discharge Q-3.
- It authorizes nothing past 2026-12-10.
