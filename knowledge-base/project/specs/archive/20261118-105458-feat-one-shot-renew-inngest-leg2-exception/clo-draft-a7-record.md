---
title: "A7 ledger: owner renewal before expiry of the leg-2 accepted-risk record for the Inngest sdk_url poll, to 2026-12-10 (#12742)"
status: record
date: 2026-11-17
related: [10136, 10538, 12742, 10479, 10205]
renews: "2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md"
outer_limit: 2026-12-10
---

> Draft as ruled by the CLO agent 2026-11-17; superseded by `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`. Placeholders here are intentional.

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

Option chosen: "Renew until 10 Dec". The owner's own typed words, at about 16:55Z on 2026-11-17 (session time; not
recorded more precisely):

> 1 but let's make sure we prioritize the work to avoid extending another time

What the question did and did not show: it named the link in plain words and referred to the 13 Nov acceptance. It
did not name the addresses, the voids or the compensating controls. Those terms come from the 13 Nov acceptance
and carry over unchanged. The question said the check fails "from the 20th"; it actually fails from
2026-11-21T00:00Z. That does not change the act.

[If the transcript shows the question or an option description naming 10.0.1.40 / 10.0.1.10:3000/api/inngest,
quote that text verbatim here and delete "It did not name the addresses".]

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

## Compensating controls (re-measured 2026-11-17, read-only, before merge)

- Hetzner `GET /v1/servers` and networks with `HCLOUD_TOKEN_READONLY`, 2026-11-17T17:04-17:07Z: 5 servers, all Jikigai's (soleur-web-platform 10.0.1.10, soleur-web-2 .11, soleur-git-data .20, soleur-registry .30, soleur-inngest .40); one network, soleur-private (12414183), only subnet 10.0.1.0/24, 5 servers attached and their ids equal to the project's own server ids, 0 load balancers, `expose_routes_to_vswitch` false. No void.
- tls-health (Better Stack), 2026-11-13T00:43Z to 2026-11-17T17:07Z, read by the CTO agent at 17:06Z: 1,329 rows (the planner's 17:11Z re-run: 1,330 rows, same values), max gap 320 s, one host (soleur-inngest), one boot_id (5319e63a); unit active, listener 1, `nft_rules=7`, `nft8443_sha256` unchanged from 2026-11-13 (1d224d03…58e4cf), `served_sha256==cert_sha256`, `tls_8443` rising.
- `legacy_8288` is **not 0**. It rose from 0 to 12 between the readings at 2026-11-16T12:04:32Z and 12:09:34Z on the same boot, and has stayed at 12 since. The counter counts plaintext packets to the Inngest host's legacy :8288 listener from the two web hosts' private IPs only. That is leg 1 (ledger row 5), not this leg, and not a foreign peer. Cause not verified: it coincides with the web-2 host replace (`apply-web-platform-infra.yml` run 43862798565, 12:01:10Z-12:08:55Z), the residual that row 5 discloses for a newly born web host. Packet contents were not measured. The counter is not reset, because a reboot would stop the TLS listener (#11081). Tracked as #<CLASS_R>; breach-register row of 2026-11-17 (not a personal data breach on the measured facts).
- CLO ruling 2026-11-17: this is a disclosed leg-1 residual, stated here as measured fact. It does not void or halt this leg-2 renewal.
- Source: #12742 comment <ACCEPT_ID>, which carries every value above with its reader and time and the work phase's Phase 1 read line ("re-read <UTC>: unchanged", or "re-read <UTC>: <source> not read (<reason>)"); the merge-day re-read is recorded in the body of PR #12884. The values above are the plan-time reads (CTO agent 17:04-17:07Z; planner 17:11Z), labelled with their times.

[If a measurement could not be done, write: "Not re-measured on 2026-11-17 by the work phase: <exact reason>. Last
measurement: 2026-11-17T17:04-17:11Z (CTO and planner reads, values above)." Never carry 2026-11-13 values forward as current.]

## Leg-1 plaintext event: breach assessment

[Write the CLO determination D below as this section, so the breach-register row's canonical source holds it, and link
the #<CLASS_R> comment <CLASS_R_COMMENT_ID> that carries the same text.]

## No further renewal

After 2026-12-10 the row lapses and is not accepted again: no renewal and no new acceptance, by any route,
in session or typed, by the owner or by an agent. If #12742 has not converted ledger row 6 by then, the required
`encryption-posture` check fails on every PR from 2026-12-11T00:00Z. The only cure is ending the plain-HTTP poll
and measuring that it stopped (#12742). Weakening the lint, the workflow or the ruleset is not a cure.

## Gap

None. The owner renewed on 2026-11-17, before the 2026-11-20 acceptance ran out.

[If this PR merges after 2026-11-21T00:00Z, replace with: "None in coverage: the owner renewed on 2026-11-17,
before the 2026-11-20 acceptance ran out. The ledger recorded the renewal only at the merge of PR #12884 (the merge
commit's timestamp is the record), so the required `encryption-posture` check failed from 2026-11-21T00:00Z until then.
Recorded, not backdated."]

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
  run or an owner-typed record exists." (the frontmatter `re_evaluation_triggers` corrected in the field).
- `inngest-server.md` (append-only notes, CTO ruling 2026-11-17): "the owner acceptance recorded by PR #12733 runs to
  2026-11-20 only" (the 2026-11-13 CLO note under the legal bridge-date item); "the owner acceptance runs to 2026-11-20"
  (the #10538 row of "Tracked follow-ups"); precondition 4, "If the replace lands after 2026-11-20, the owner-typed record
  the CLO ruling requires exists first": met by this renewal for a replace before 2026-12-10.; the precondition-1 note's "and so is the 2026-11-20 limit in item 4" (its own one-line marker).
- `2026-11-counsel-review-10479.md` `open_follow_ups` Q-2: "The replace must run by 2026-11-20, or else an owner-typed
  record ... is required" (inline bracket, same form as Q-1's).
- `ADR-294-inngest-link-tls-terminator-and-flagged-flip.md`: "the acceptance runs to 2026-11-20" (the 2026-11-13
  blockquote; a dated note under it says this is a renewal, not the dead 2026-11-02 extension).
- #12742 item 8: marker added to the issue body.

## What this does not do

- It is not a signature, and the ledger edit is not one: it moves a date the owner named.
- It does not run, authorize or schedule the `inngest-host-replace`, and it does not touch PR #12876.
- It does not change the lint, `ci.yml`, any ruleset, row 7 or any published legal wording (#12742 item 7).
- It does not close #10538 (closes only as "not planned, superseded by #12742") or #12742.
- It does not discharge Q-3.
- It authorizes nothing past 2026-12-10.
