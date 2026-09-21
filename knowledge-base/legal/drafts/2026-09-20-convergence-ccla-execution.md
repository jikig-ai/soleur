---
title: "Execution reply — Convergence Corporate CLA (AWAITING OPERATOR SEND)"
date: 2026-09-20
type: correspondence
custodian: clo
status: awaiting-operator-send
counterparty: Convergence (Islamabad, Pakistan)
inbound: support@convergence.pk → legal@jikigai.com
related: [3210, 7846, 7922]
---

# Execution reply to Convergence — prepared 2026-09-20

**Status: AWAITING OPERATOR SEND.** Prepared in response to the counterparty's
reply to the 2026-09-09 request
(`knowledge-base/legal/drafts/2026-09-04-convergence-ccla-reply.md`).

**What their reply provided.** (1) The organisation's legal name, registered
address and registration identifiers — including the Islamabad Chamber of
Commerce registration and confirmation of the NTN and PSEB numbers already on
file. (2) A named authorised signatory with title and an individually
attributable mailbox — satisfying CLO D3. (3) For the Section 4(c)
representative list, a **mailbox** rather than a GitHub username, with the note
that the account will be operated by their AI.

**PII boundary.** The signatory's name, title, email address and the
organisation's street address are **not in this file and may never enter any
tracked file** — see the prohibited-fields rule in
`knowledge-base/legal/ccla-register.md`. The execution copy and the addressed
cover email carrying those fields live **off-repo** on the encrypted volume at:

- `/data/ccla/2026-09-20-convergence-ccla-execution-copy.md` — the instrument
  (agreement text verbatim + particulars + Schedule A + signature blocks)
- `/data/ccla/2026-09-20-convergence-reply-cover-email.md` — the cover email as
  addressed (To: the signatory mailbox; Cc: the role mailbox)

**The agreement text embedded in the execution copy** is
`docs/legal/corporate-cla.md` at commit `18887f8d5c697c94864a79eed7dfede25b8babe2`
(SHA-256 `03cbf51b1543cdb3699ec71fbfa2946ff28d264ef574ae7252eac17b89ab6bad`).
If `docs/legal/corporate-cla.md` changes before signature, regenerate the
execution copy — the register's CCLA version hash must describe the text that
was actually executed.

## Body of the reply (as prepared; greeting and headers filled off-repo)

**Subject:** Re: Corporate CLA — Convergence

Hello,

Thank you — that is everything we needed on the first two items, and the
enclosed execution copy is prepared accordingly.

One detail remains on the third. Section 4(c) of the agreement asks for the
GitHub **usernames** authorised to contribute — the account handle shown on the
profile page (for example `@octocat`), not an email address. We cannot resolve
a GitHub account from an email address. Rather than hold the instrument up for
it, Schedule A is left for you to complete at signature — the designation list
is yours, so it is right that you write it. If it is easier, reply with the
username and we will fill it in before countersigning.

One related note, since you mention the account will be operated by your AI:
when your pull request is opened, our CLA bot will ask the account holder to
sign the **Individual** CLA by posting a one-line comment. That signature is a
representation made by a natural person, so please make sure the signature
comment is posted by — or under the express authority of — an identified
individual at Convergence. The corporate agreement covers the company; the
individual one covers the person, and only a person can make it.

What happens next:

1. Review the enclosed execution copy and write the GitHub username(s) into
   Schedule A.
2. Have the document signed where indicated and return it to
   <legal@jikigai.com>.
3. We countersign and send back a fully executed copy for your records.

As before, nothing here blocks your pull request — please open it from
`feat-opencode-harness` whenever it is ready.

Best regards,
Jean Deruelle
Jikigai — <legal@jikigai.com>

---

## Operator notes (do not send)

- **Fill before sending:** the greeting in the off-repo copy addresses the
  signatory by name; the Jikigai signature block in the instrument carries a
  blank title field for the operator.
- **Schedule A is deliberately blank.** Their §4(c) answer gave a mailbox, not
  a GitHub username, and we cannot resolve one from the other. The counterparty
  completes the list at signature — it is their representation under §4(c), and
  §5 already makes it amendable by email afterwards. No extra round-trip, and
  the 5-business-day commitment made on 2026-09-09 is preserved.
- **The AI-operated account is a flagged open question, handled not buried.**
  The reply tells the counterparty the ICLA signature must be made by — or
  under the express authority of — an identified natural person, consistent
  with CLO D3's reasoning that §4(a)-type representations are personal acts.
  The deeper question — whether contributions authored by an AI-operated
  account give the organisation the §2 rights it grants — is program-level, not
  Convergence-specific, and is recorded on the send-tracking issue for CLO
  pickup. It does not block this send: the instrument's protections are
  unchanged either way.
- **On the signed instrument's return (runbook §10.1, event A):** move it to
  the encrypted drive, `sha256sum < <instrument>` (with the redirect), and add
  the row to `knowledge-base/legal/ccla-register.md` — `CCLA-0001`,
  organisation legal name `Convergence` (not a natural person's name, so the
  sole-trader rule does not blank it), `Signatory on file: yes`, `Authorized
  from` = the effective date stated in the instrument (the date of the last
  signature). The roster row waits for the representative's ICLA signature —
  #7922's watch reports that.
- **Do not commit the off-repo artifacts.** `ccla-add.sh` independently refuses
  an `--instrument-file` that resolves inside the repository.
- **Send automation:** `playwright-attempt: NOT ATTEMPTED` — the Playwright MCP
  server was configured but not reachable this session (`mcp_list_tools`
  failed on connect), so no browser surface to the Proton-hosted mailbox was
  possible. Same tooling condition recorded on #7846; the scripted reply-send
  remains deferred to the third organisation per #7911.
- **Chapter V:** sending the instrument — which carries the signatory's name
  and mailbox — to a controller in Pakistan is the outbound transfer already
  flagged in the 2026-09-04 file's notes; it is covered for one-off
  correspondence. The recurring §5 maintenance-exchange question stays open in
  the 2026-09-04 brainstorm's open questions.
