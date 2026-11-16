---
title: "A7 ledger: new acceptance after a lapse of the leg-2 accepted-risk record for the Inngest sdk_url poll (#10538)"
status: record (owner-pending)
date: 2026-11-13
related: [10136, 10538, 10479, 10205]
addenda: ["2026-11-13 CLO-cures addendum (PR #12737; its ledger-row and sdk_url limbs fire on that PR's merge), amended 2026-11-15 by CLO fix-round rulings (a) and (c): see 'Addendum — 2026-11-13 (CLO cures, PR #12737)' and 'Unsigned owner-record draft'"]
---

# A7 ledger: owner extension, leg-2 Inngest `sdk_url` poll

> **Superseded 2026-11-15 (#12737): this is a new acceptance after a lapse, not an extension (see the 2026-11-13 addendum), and its owner items are still owner-pending.**

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

## Addendum — 2026-11-13 (CLO cures, PR #12737)

Appended by a Claude Code agent under the CLO agent's ruling of 2026-11-13 (agent ruling, not counsel advice). The body above is left as filed.

- **Label.** This record is a **new acceptance after a lapse**, not an extension. The 2026-11-02 record's conditional extension to 2026-12-10 is dead for good, because #10538 did not merge by 2026-11-12. 2026-12-10 remains the outer limit: no acceptance of leg 2 may run past it.
- **Gap.** From 2026-11-13T00:00Z until the owner's in-session acceptance, leg 2 was **not covered** by any acceptance. That is recorded as a fact and is not backdated. The acceptance was posted to #10538 in comment 6846245981 at 06:46:47Z; the moment the owner gave it in session is not recorded more precisely.
- **Controls.** The body says the controls "were not re-measured". They were re-measured on 2026-11-13, read-only, and recorded in #10538 comment 6840514776 (00:55:51Z):
  - Hetzner enumeration: 5 servers, all Jikigai (10.0.1.10, .11, .20, .30, .40).
  - tls-health at 00:53Z: `nft_rules=7`, `nft8443_sha256` present, `legacy_8288=0`, `served_sha256==cert_sha256`.
- **Owner's words.** The quoted sentence was drafted by the agent and chosen by the owner. The CLO ruled that the record should carry the owner's own words, with a timestamp, as the 2026-11-02 record did ("I confirm A7 as read"). **That is owner-pending**: the owner confirms in their own words on #12742 (#10538 closes on the merge of PR #12737). An agent cannot supply it.
- **Companion change superseded.** On the merge of PR #12737, ledger row 7 converts (Cloudflare to origin) to verified TLS and removes its exception. The 2026-11-19 date that this record's companion change set no longer applies once PR #12737 merges.
- **After PR #12737.** That PR changes the declared `--sdk-url` to `https://app.soleur.ai/api/inngest`. The live host keeps the plain-HTTP poll until the owner's `inngest-host-replace` (#12742). *(Corrected 2026-11-15, CLO fix-round ruling (c): this sentence used to say "nothing live changes at merge".)* On the merge of PR #12737, the push apply rewrites the live Cloudflare config ruleset (`cloudflare_ruleset.seo_config_settings`: the adopted rule becomes `ssl = "strict"` for `app.soleur.ai` alone and the two ORIGIN-TLS rules are deleted). The effective SSL mode for `app.soleur.ai` (`strict`) and the live `--sdk-url` (private plain HTTP until #12742) stay the same. The void "pointing `--sdk-url` at the public host while Cloudflare to origin is flexible" is avoided only because #12742 lands after that apply; before #12742 runs, a read-only read-back (`cloudflare-readonly.sh config-entrypoint`) must show that no `flexible` rule matches `app.soleur.ai`. If the owner's act lands after 2026-11-20, a record that the owner types, beginning "SIGNED BY OWNER (human, not an agent)", is required. The draft is in the section 'Unsigned owner-record draft' below.

## Unsigned owner-record draft (agent-authored; NOT a signature; no effect until the owner types it)

Required only if the owner's `inngest-host-replace` (#12742) lands after 2026-11-20. The owner types the signed record
as a comment on #12742, in their own words; an agent then mirrors it to a new audit file. Nothing below is filled in by
an agent, and until the owner types it this draft records nothing.

*(Changed 2026-11-15, CLO fix-round ruling (a): this draft used to pre-write the owner's sentences. It is now a list of
the elements the record must contain. Each element is a prompt the owner answers in their own words. The only fixed
values are the limits the controller has already set: no later than 2026-12-10, the gap start 2026-11-13T00:00Z, and
the void conditions.)*

```text
Required elements of the owner's record (agent-authored prompts; NOT a signature):
1. Opening line, typed by the owner: SIGNED BY OWNER (human, not an agent)
2. Scope: which link you accept, in your words (the leg-2 poll from the Inngest host to the web host's /api/inngest).
3. Data: what crosses that link, in your words.
4. Why: why the poll is still plain HTTP on the private network, and what act ends it (#12742).
5. Your 2026-11-13 statement "I will not extend past [2026-11-20]": say what happens to it, in your words.
6. Until when: a date or an event you choose. Fixed limit: no later than 2026-12-10.
7. The gap: the uncovered window from 2026-11-13T00:00Z (fixed) to your acceptance, acknowledged in your words.
8. Voids (fixed): a server beyond the five on 10.0.1.0/24; any public or cross-network exposure of the plaintext
   poll; any non-Jikigai peer on that network; --sdk-url at the public host while any flexible rule applies to
   app.soleur.ai.
9. Not accepted: anything you exclude, in your words.
10. Controls measured: the date, the run or comment, and the result you rely on (Hetzner read-only enumeration;
    tls-health nft_rules, legacy_8288).
11. No known access: confirm, in your words, that you know of no access to this link by anyone else.
12. Signature: your typed name and the date.
```
