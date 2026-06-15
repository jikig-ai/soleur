---
title: "CLO pre-send compliance review — listicle-author cold outreach (#5314)"
type: counsel-review
date: 2026-06-15
issue: 5314
related_issues: [2073, 5302]
artifact: knowledge-base/marketing/listicle-outreach-briefs.md
status: DISCHARGED (mandatory conditions C1–C5 applied to the campaign artifact 2026-06-15)
reviewed_by: "CLO agent (v1 internal counsel-review attestation authority, Soleur-as-tenant-zero posture)"
operator: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "First arms-length (non-Soleur) tenant runs an outbound campaign through this template; ANY shift from 1:1 personalized editorial pitch to bulk/templated send >50 recipients; addition of any payment/affiliate/sponsored term; EEA-out (campaign run from outside the EEA under a different controller)"
draft_notice: "Draft legal guidance for a non-lawyer founder. Not a substitute for licensed counsel where the re-evaluation triggers above apply."
---

# CLO pre-send compliance review — listicle-author cold outreach (#5314)

This is the "Pre-send compliance gate (MANDATORY)" the campaign artifact at
`knowledge-base/marketing/listicle-outreach-briefs.md` requires before the first batch. The
outbound-strategist flagged it and deferred to the CLO. Per the Soleur-as-tenant-zero v1 posture,
the CLO performs this review and returns a disposition; the operator retains an optional veto.

**Controller / sender identity of record:** Jikigai (Jikigai SARL), a company incorporated in
France, registered office **25 rue de Ponthieu, 75008 Paris, France** (RCS Paris 927 585 729),
gérant Jean Deruelle. Rights/contact: `legal@jikigai.com`. These are the load-bearing facts for the
CAN-SPAM postal-address element and the GDPR Art. 13/14 identity element.

**Campaign nature (controls the entire analysis):** cold, personalized 1:1 outreach to authors/
editors of third-party listicles, asking for editorial consideration. Goal = earned editorial
citation (AEO), NOT a sale. ~11 named targets, max 2 touches each. Only incentive = free product
access (explicitly NOT payment/affiliate/sponsored).

---

## Disposition: BLOCKED pending edits → DISCHARGED on completion of C1–C5

The campaign is **low-risk and fundamentally lawful** (1:1 B2B editorial pitch, low volume, honest
identity, no payment). It is **BLOCKED only on five mechanical additions** that are currently
MISSING from the templates. Once C1–C5 are pasted in, this review is **DISCHARGED**.

| # | Mandatory condition | Blocks send to |
|---|---------------------|----------------|
| C1 | Add a valid physical postal address to Email A and Email B footers | All email targets |
| C2 | Add a working opt-out line ("reply 'no thanks' and I won't contact you again") to Email A and Email B | All email targets |
| C3 | Tag each target US vs EU/UK on the send list BEFORE sending; add a one-line data-source disclosure to the EU/UK variant | EU/UK email targets |
| C4 | Add the FTC material-connection instruction to Email B (free-access pitch) | Tier-2 free-access targets |
| C5 | Honor any opt-out within 10 business days and suppress permanently; keep a suppression note | All targets (operational) |

No condition requires payment, schema, or product change. All five are copy/process edits the
operator can complete in one editing pass.

---

## 1. CAN-SPAM (US)

### Is a 1:1 B2B editorial pitch a "commercial electronic message"?

**Likely yes — treat it as one.** CAN-SPAM (15 U.S.C. §7701 et seq.) defines a commercial message as
one whose **primary purpose is the commercial advertisement or promotion of a commercial product or
service**. Even though the *ask* is editorial coverage (not a sale), both emails promote Soleur (a
commercial product), link to soleur.ai, and offer free access to it. The FTC reads "primary purpose"
broadly; a "transactional or relationship" exemption does NOT apply here because there is no prior
relationship or transaction with these authors. **Conservative, correct posture: comply with CAN-SPAM
in full.** The good news: CAN-SPAM applies per-message, has no volume floor, and a compliant 1:1
email is trivially achievable. It does NOT require prior consent (unlike GDPR/PECR) — opt-out, not
opt-in, is the US standard.

### Element-by-element — Email A and Email B (identical analysis for both)

| CAN-SPAM required element | Status in current templates | Fix |
|---|---|---|
| **No false/misleading header info** (From/To/Reply-To/routing accurate) | **PRESENT** — sent from Jean's real address, real name "Jean" | None. Ensure the From name resolves to Jean Deruelle / Soleur, not a spoofed alias. |
| **No deceptive subject line** (must reflect message content) | **PRESENT** — "A category your {{list_title}} is missing" and "Free access to test Soleur for {{list_title}}" both accurately describe the body | None. Both are honest. |
| **Identify the message as an ad** | **PRESENT (constructively)** — CAN-SPAM allows this by "clear and conspicuous" means; the body openly states it's a pitch from the product's founder. A 1:1 named pitch that openly identifies the sender and product satisfies this. | None required; the opt-out + identity below reinforce it. |
| **Valid physical postal address** of the sender | **MISSING** — no postal address anywhere in either template | **C1 — paste the footer below.** This is the single hardest-failing element today. |
| **Clear opt-out mechanism** | **MISSING** — neither email tells the recipient how to decline further contact | **C2 — paste the opt-out line below.** A reply-based opt-out ("just reply and say no") is acceptable for 1:1 mail; it need not be a hosted unsubscribe link at this volume. |
| **Honor opt-out within 10 business days; no fee/info required to opt out; keep suppressed** | **MISSING (process)** — no suppression process documented | **C5 — operational.** If anyone declines, suppress them permanently and do not send Touch 2. Note it on the send list. |

**Net CAN-SPAM verdict:** Email A and Email B are **NON-COMPLIANT as written** (missing postal
address + opt-out), but become **COMPLIANT** once C1, C2, and the C5 process are in place. The DM
template is out of CAN-SPAM scope (CAN-SPAM governs email; see §4 for DM/ToS).

---

## 2. GDPR / UK-GDPR + PECR (EU/UK authors)

### Lawful basis: legitimate interest, not consent

For cold **B2B** outreach to a named professional about a matter within their professional remit
(an author of a tools listicle being pitched a tool to consider), **Art. 6(1)(f) legitimate interest
is the appropriate lawful basis** — consent (Art. 6(1)(a)) is not required for the GDPR layer.
Direct marketing is expressly recognized as a potential legitimate interest (GDPR Recital 47).

But two layers stack and you must satisfy both:

1. **GDPR Art. 6(1)(f)** — needs a documented legitimate-interest balancing test (below).
2. **PECR (UK) / ePrivacy (EU)** — the e-marketing rules that sit *on top of* GDPR for electronic
   marketing. **This is the layer that bites.**

### The PECR / ePrivacy "soft opt-in" and its limits

- The **"soft opt-in"** (PECR Reg. 22) lets you email marketing without prior consent ONLY where you
  obtained the contact **during a sale/negotiation of a similar product to that person**. **It does
  NOT apply here** — these authors are cold, no prior dealing. So soft-opt-in is unavailable.
- **However, PECR's consent requirement for unsolicited marketing email applies to "individual
  subscribers"** (consumers, sole traders, some partnerships). For **"corporate subscribers"**
  (registered companies, LLPs, corporate role addresses like `editor@publication.com`), UK PECR
  does **not** require prior consent for marketing email — only (a) sender identification and (b) a
  working opt-out. EU member-state ePrivacy transpositions vary; some (e.g. Germany) are stricter
  and effectively require consent or a pre-existing relationship even B2B.

**Practical consequence for this campaign:**
- Emailing a **corporate/role editorial address** of an EU/UK publication (e.g. an "editorial contact
  form" or `tips@`/`editor@`) is **lower-risk** and broadly defensible under legitimate interest +
  identification + opt-out.
- Emailing an **individual author's personal-style address** (e.g. a named freelancer's own email) in
  a stricter EU member state is **higher-risk** without consent. For these, **prefer the platform DM
  channel** (the artifact already lists "author byline → X DM" for several) or the publication's
  corporate contact form, rather than a cold personal email.

### Art. 6(1)(f) legitimate-interest balancing — what it requires (and the assessment)

A defensible LIA has three parts; here is the short-form assessment for this campaign:

1. **Purpose test (is there a legitimate interest?)** — Yes. Promoting a relevant product to a
   professional who curates exactly that product category is a genuine, lawful, B2B-marketing
   interest. The contact is being approached *in their professional capacity about their published
   professional work*.
2. **Necessity test (is the processing necessary?)** — Yes, and it is **minimal**: a single
   personalized message (max 2 touches), publicly-available professional contact data, no profiling,
   no list-building, no enrichment, no storage beyond a send log.
3. **Balancing test (do the individual's rights override?)** — Tilts in favor of the sender given:
   low volume, the contact's reasonable expectation that authors of "best tools" lists receive vendor
   pitches, easy opt-out, honest identity, and no sensitive data. **The balance holds ONLY IF** the
   recipient is told (a) who is contacting them, (b) where the data came from, and (c) how to opt out
   — i.e. the Art. 14 transparency obligations are met (see below).

This assessment is light enough that a standalone LIA file is **not** required at this volume; this
section IS the recorded balancing test. (If volume or templating scales past ~50 recipients, promote
this to a dedicated LIA under `knowledge-base/legal/legitimate-interest-assessments/` — that is a
re-evaluation trigger in the frontmatter.)

### Art. 14 — you must disclose where you got their contact data

Because the personal data (the author's name/email) was **not collected from the data subject** but
from their public byline/listicle, **GDPR Art. 14** applies: at first contact you must tell them
your identity, the purpose, the lawful basis (legitimate interest), the **source of the data**, and
their rights (object, access, erasure). At this scale this is satisfied by **one disclosure line in
the email body** (provided in C3 below) pointing to the privacy policy — you do not need a separate
notice.

### Is a jurisdiction split of the send list required?

**YES — C3 is mandatory.** Before the first send, tag each of the ~11 targets as **US** or **EU/UK**
(and ideally flag the stricter EU states). This is required because:
- EU/UK recipients need the Art. 14 data-source line + opt-out + identity (the EU/UK email variant).
- It lets you route higher-risk EU/UK *individual* addresses to DM/corporate-form instead of cold
  personal email.
- US recipients only need the CAN-SPAM elements (C1/C2), not the Art. 14 source line.

A practical, defensible default if jurisdiction is genuinely unknown for a target: **send the EU/UK
variant** (it is a strict superset — it satisfies CAN-SPAM too). So the cheapest compliant path is:
add C1+C2+C3 to a single unified footer and use it for everyone.

---

## 3. FTC endorsement / material-connection disclosure

### Does free product access trigger disclosure?

**Yes — for the AUTHOR, and you must prompt it.** Under the FTC's revised Endorsement Guides
(16 CFR Part 255, 2023 update), **free or complimentary products given to a reviewer are a "material
connection"** that must be **clearly and conspicuously disclosed** in the resulting review/listicle.
The obligation to disclose legally sits on the **endorser (the author/publisher)**, but the FTC's
guidance and its warning letters make clear that the **advertiser (Soleur/Jikigai) is responsible for
advising endorsers of their disclosure obligations** and should not incentivize non-disclosure.

So Soleur's exposure is: if you give free access and the author writes Soleur into a list without
disclosing the free access, **both** parties have FTC exposure, and Soleur's failure to instruct is
itself a cited deficiency in FTC enforcement.

### What Soleur must say / require

- **In Email B (the free-access pitch):** add the C4 instruction telling the author that if free
  access materially informs their coverage, they should disclose it per their normal editorial
  policy / FTC guidance. This is paste-ready in §5.
- **Free access ≠ paid placement:** the artifact's guardrail #3 (no payment/affiliate/sponsored) is
  exactly right and materially lowers risk — a complimentary product for honest testing is the
  lightest-touch material connection and is routinely handled by a one-line "[Vendor] provided free
  access for testing" disclosure. Do not cross into payment/affiliate; that escalates both FTC
  weight and AEO de-valuation.

### Tier-2 "tested & ranked" vs Tier-1 editorial lists — does it differ?

**Yes, materially:**
- **Tier-2 independent testers** (Email B): these authors **hands-on test** the product *because of*
  the free access — the free access is the direct enabler of the review. **Material connection is
  squarely engaged; C4 disclosure instruction is required.** This is the higher-disclosure tier.
- **Tier-1 / Tier-3 editorial lists** (Email A): these are editorially-curated lists where the author
  is **not** necessarily testing via your free access — they may include Soleur on merit/research
  without redeeming the offer. If they do **not** accept free access, no material connection arises
  and no disclosure is triggered. If an Email A recipient *does* take the free access, the same C4
  instruction applies. **Safest: include the C4 line wherever free access is actually offered/taken.**
  Email A as written only *links* to the honest ranking and offers "free hands-on access" loosely —
  if you keep that offer in Email A, add C4 there too.

---

## 4. Platform ToS (X / LinkedIn DMs) — advisory only

- **Not a CAN-SPAM/PECR email matter** (those govern email; PECR also covers SMS/automated calls,
  not 1:1 social DMs). The exposure here is **contractual** under each platform's ToS, not statutory.
- **X (Twitter):** the X Rules prohibit "platform manipulation and spam," including bulk/unsolicited/
  duplicative DMs and aggressive solicitation. A **genuinely personalized 1:1 DM that references the
  recipient's specific work, low volume, one channel per person, max 2 touches** (exactly the
  artifact's cadence) is **low-risk** but not zero — repeated identical DMs or contacting people who
  don't follow you can trip automated spam heuristics and risk account limiting. Keep each DM
  individually written (the template's `{{list_title}}` personalization helps) and stop after Touch 2.
- **LinkedIn:** the User Agreement / Professional Community Policies prohibit spam and unsolicited
  bulk messaging; connection-request and InMail limits apply. Same mitigation: personalized, low
  volume, no automation tools (no scrapers/auto-senders — those separately violate LinkedIn ToS and
  raise CFAA-adjacent issues). **Advisory:** prefer engaging publicly / a connection request with a
  note over cold InMail where possible; never use automation to send the DMs.
- **No statutory blocker.** The DM template content is fine; this is a "follow each platform's rules,
  send manually, stay personalized" advisory.

---

## 5. Required edits — paste-ready text

### C1 + C2 + C5 — Email A and Email B footer (US baseline)

Append to the bottom of **both** Email A and Email B, after "Jean":

```
—
Jean Deruelle · Soleur (Jikigai SARL)
25 rue de Ponthieu, 75008 Paris, France
This is a one-time personal note about your list. If you'd rather not hear from me,
just reply "no thanks" and I won't contact you again.
```

(The reply-based opt-out satisfies CAN-SPAM at this volume. C5: if anyone replies to opt out,
suppress them permanently — do not send Touch 2 — and note it on the send list.)

### C3 — EU/UK variant: add the Art. 14 data-source + rights line

For any target tagged **EU/UK** (or unknown-jurisdiction, where you default to this variant), use the
expanded footer instead:

```
—
Jean Deruelle · Soleur (Jikigai SARL), data controller
25 rue de Ponthieu, 75008 Paris, France · legal@jikigai.com
I'm contacting you because of your published article {{list_title}}; I found your contact
via its public byline. I'll only send one polite follow-up at most. You can object at any time
(just reply), and you have the right to access or have me erase your contact details — email
legal@jikigai.com. Our privacy policy: https://soleur.ai/legal/privacy-policy
```

(This single block satisfies GDPR Art. 14 identity + source + purpose + lawful basis + rights, and
also satisfies CAN-SPAM — so it is safe to use it universally if you don't want to maintain two
footers.)

### C4 — FTC material-connection instruction (add to Email B; and to Email A wherever free access is offered)

Insert as a short line in the free-access paragraph of Email B:

```
One ask if you do cover us: if the free access shapes what you write, please disclose it
however your editorial policy / the FTC endorsement guidelines call for ("Soleur provided free
access for testing" is plenty). Honest, disclosed coverage is exactly what we want.
```

### Artifact edit — update the campaign file

In `knowledge-base/marketing/listicle-outreach-briefs.md`:
- Change frontmatter `status: ready-to-send (pending CLO pre-send review)` →
  `status: ready-to-send (CLO pre-send review DISCHARGED 2026-06-15 #5314 — conditions C1–C5 applied)`.
- Add the C1/C3 footer and C4 line into the Email A / Email B templates (so the source-of-truth
  template is itself compliant, not just the operator's sent copy).
- Add a "Send list jurisdiction tag (US / EU-UK)" column to the Prioritized target list, or a
  companion note, before the first send (C3).
- Cross-link this audit: `knowledge-base/legal/audits/2026-06-15-clo-presend-review-listicle-outreach-5314.md`.

---

## 6. Overall disposition

**BLOCKED pending edits → DISCHARGED upon application of C1–C5.**

- The campaign is lawful in design: 1:1 personalized B2B editorial outreach, ~11 targets, max 2
  touches, honest identity, free access only (no payment/affiliate/sponsored — guardrail #3 is
  correct and load-bearing).
- It **cannot be sent as currently written** because the email templates are missing the CAN-SPAM
  postal address (C1), the opt-out (C2), the EU/UK Art. 14 data-source line (C3), and the FTC
  material-connection instruction (C4); and the suppression process (C5) is undocumented.
- On applying C1–C5 (all copy/process edits, no product change), the gate is **DISCHARGED** and the
  first Tier-1 pilot batch may send.

**v1 attestation:** This is the CLO's internal v1 sign-off under the Soleur-as-tenant-zero posture;
the operator (Jikigai SARL gérant) retains an optional veto. **External licensed counsel re-review
is reserved for the frontmatter re-evaluation triggers** — notably the first arms-length tenant
running outbound through this template, any shift to bulk/templated sending >50 recipients, or any
addition of a payment/affiliate/sponsored term. This is draft legal guidance for a non-lawyer
founder, not a substitute for licensed counsel where those triggers apply.
