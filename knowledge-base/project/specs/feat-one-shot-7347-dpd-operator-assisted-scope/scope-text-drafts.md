# Scope-text drafts — the canonical strings

Every string below is drafted ONCE here and applied VERBATIM at its sites. Plan §3.2 collapse, as
amended by §0 A2/A3/A4/A5/A9. Amendments supersede plan §4, which was written before the review —
notably §4's N1 draft proposed publishing *"own machine and key **at no charge**"*, a **price term**
carried only by the unexecuted annex. A2 forbids it and it is absent below.

## The rule every string obeys (A2)

A published sentence may state that **an instrument addresses X**. It may never state **what the
instrument promises**. No numeric SLA, no price term, no retention figure, no named transfer
mechanism. Rationale and record trace: `decision-challenges.md` M2.

Records consulted: `article-30-register.md` PA-34/PA-35, `article-30-2-register.md` P-1,
`2026-08-06-alpha-tester-processing-annex.md` §5.1-§5.6, and the determination §4/§11.

**C6 is open** (`data-processing-agreements/anthropic.md` item 4): the Anthropic account's
Commercial-vs-Consumer Terms status is unconfirmed. PA-35's third-country-transfer safeguards entry
*depends on* Commercial Terms §C. Therefore **no string below names the transfer mechanism, the
DPF/SCC/IDTA status, or the retention window** — even though annex §5.2 states them flatly. This is
open question Q4, resolved conservatively.

---

## S1 — POINTER-FORMAL (third-person: `data-protection-disclosure.md`, `gdpr-policy.md`)

Leads with the default case per A5. Names the target document in words per A3 — no `#` fragment,
because `eleventy.config.js` registers no anchor plugin and published headings carry no `id`.

> **Scope.** This section describes **plugin-local processing** — the Plugin running on the User's
> own machine, under the User's own credentials, for the User's own purposes. That is the default,
> and it is what applies unless the User has asked Jikigai for an operator-assisted session. It does
> not describe **operator-assisted processing**, in which a Jikigai machine or a Jikigai-held
> credential is used, and must not be read as covering it. Operator-assisted processing is described
> in the Data Protection Disclosure, Section 2.1c.

## S2 — POINTER-PLAIN (second-person: `privacy-policy.md`, `acceptable-use-policy.md`, `disclaimer.md`)

Same claim, second person, per A4. The two registers are NOT interchangeable: a third-person string
at a second-person site is wrong-voiced at ~8 sites while an exact-count grep still passes.

> **What this covers.** This section describes the Plugin running on **your** own machine, under
> **your** own API key, for **your** own purposes — which is how it works unless you have asked us
> for an operator-assisted session. It does not describe operator-assisted sessions, where a Jikigai
> machine or a Jikigai-held credential is used. Those are described in the Data Protection
> Disclosure, Section 2.1c.

---

## Limb clauses — appended at P+ sites only

Justified only where the text denies a legal **duty** or denies a **transfer** (A9). The retention
clause from plan §3.2 is **dropped** — the pointer already cures it.

### S3 — DSAR limb (DPD §5.1, GDPR §5.2)

> Where an operator-assisted session has taken place, the written instrument agreed before that
> session addresses how Jikigai assists the User in responding to requests from data subjects in
> respect of that processing.

### S4 — Transfer limb (DPD §6.1, PP §10, GDPR §6)

> Where an operator-assisted session has taken place, the written instrument agreed before that
> session addresses any transfer of personal data outside the European Economic Area arising from
> it, and the safeguards relied on for that transfer.

### S5 — Breach / audit limb (DPD §7.1, DPD §9.1)

> Where an operator-assisted session has taken place, the written instrument agreed before that
> session addresses notification of personal-data breaches affecting that processing, and the
> User's audit rights in respect of it.

---

## S6 — N1: new `### 2.1c Operator-Assisted Processing` (DPD only)

The only new heading in the change. Slots between §2.1b and §2.2 so nothing renumbers. Deliberately
does **not** restate §2.1b's Web Platform posture — §2.1b carries a team-workspace carve-out that a
summary row would flatten, inventing a new wrong claim inside the correction.

> ### 2.1c Operator-Assisted Processing
>
> Sections 2.1 and 2.2 describe the Plugin as the User runs it: on the User's own machine, under the
> User's own credentials, for the User's own purposes. In that configuration Jikigai is neither a
> Controller nor a Processor of the User's content, and those sections remain accurate.
>
> An **operator-assisted session** is different. It is a session in which Jikigai, at the User's
> request, participates directly in running Soleur against the User's own material — using a Jikigai
> machine, a Jikigai-held credential, or both. The determining question is not whose machine executes
> the session but **whose credential funds it**.
>
> | Configuration | Jikigai's role |
> |---|---|
> | Plugin-local — User's machine, User's credentials, User's purposes | Neither Controller nor Processor |
> | Operator-assisted, acting on the User's instructions | **Processor** |
> | Operator-assisted, for Jikigai's own product-learning purpose | **Controller** |
>
> - **(a) The Processor role.** To the extent Jikigai processes the User's content on the User's
>   instructions during an operator-assisted session, Jikigai acts as a Processor and the User acts
>   as the Controller.
> - **(b) The Controller role.** Jikigai also observes how Soleur performs during such sessions in
>   order to improve the product. For that purpose, and that purpose only, Jikigai acts as a
>   Controller in its own right and relies on its legitimate interests under Article 6(1)(f).
> - **(c) Instrument first.** Jikigai carries out operator-assisted processing **only** under a
>   written Article 28(3) instrument agreed with the User **before** the session begins. That
>   instrument — not this Disclosure — governs sub-processor authorisation, international transfers,
>   breach notification, audit rights, retention, and assistance with data-subject requests.
> - **(d) Not the default.** Operator-assisted processing never happens unless the User asks for it.
>   A User may instead require that any such session run on the User's own machine under the User's
>   own credentials, which removes Jikigai from the processing chain entirely.

## S7 — D5: DPD §4.1 sub-processor paragraph (appended; existing sentence kept verbatim)

The sharpest contradiction in the corpus: §4.1 denies any plugin-level sub-processor while the annex
asks the User to authorise Anthropic PBC for exactly these runs, and P-1(a) records that Art. 28(2)
is **not** satisfied. Fixed by binding the existing sentence to its true scope and adding the
operator-assisted case — not by retracting it.

> The paragraph above describes plugin-local processing, where the User contracts directly with any
> AI provider under the User's own credentials, and it remains accurate for that configuration.
>
> **Operator-assisted sessions are the exception.** Where a session runs under a **Jikigai-held**
> credential rather than the User's own, the AI provider processing that content — **Anthropic PBC**,
> 548 Market Street, San Francisco, CA 94104, United States — is engaged as **Jikigai's**
> Sub-processor for that session rather than as the User's own provider. Authorisation under Article
> 28(2), the basis for any international transfer, and the applicable retention period are settled in
> the written instrument agreed with the User before the session begins. A User who prefers to avoid
> this entirely may require that the session run under the User's own credentials, in which case the
> AI provider remains the User's own processor and Jikigai is not part of the chain.

## S8 — P3: PP §4.2 plain-English block (appended)

`§4.2` is the sentence that actually breaks: it names the `knowledge-base/` tree and git artifacts —
exactly what PA-35 records being read — and carries **no scope line at all**, unlike §4.1.

> **Operator-assisted sessions are the exception to the sentence above.** If you ask us to help you
> run Soleur against your own material, and we do that using our machine or our API key, then during
> that session we do read the files described above — including your `knowledge-base/` directory and
> your git history — and their content is sent to our AI provider under **our** credentials rather
> than yours.
>
> When we do that on your instructions we are acting as your processor. We also look at how Soleur
> performed in order to improve the product, and for that narrow purpose we are acting as a
> controller in our own right. We only do this under a written agreement made with you **before** the
> session starts, and that agreement — not this policy — sets out what happens to the data.
>
> We do not do this by default. Unless you ask us for an operator-assisted session and agree that
> written agreement first, everything above stands exactly as written.

## S9 — G2: GDPR §2.2 third bullet (file's own pattern)

§2.2 already splits BYOK-plugin from Jikigai-keyed-**as-controller**. Neither existing bullet reaches
Jikigai-keyed-**as-processor**, which is the gap. Added as a third bullet, additive only.

> - **Operator-assisted sessions.** Where Jikigai, at a User's request, runs Soleur against that
>   User's own material using a Jikigai machine or a Jikigai-held API key, Jikigai acts as a
>   **processor** on the User's instructions, and additionally as a **controller** for its own
>   product-learning purpose. Such sessions are carried out only under a written Article 28(3)
>   instrument agreed with the User beforehand. This is distinct from the automated jobs described
>   above: an operator-assisted session is interactive and is initiated at the User's request.

---

## The "automated jobs" gap — why S9's last sentence exists

Both in-repo precedents (`privacy-policy.md` §5.1, `gdpr-policy.md` §2.2 bullet 2) scope the
Jikigai-keyed path to Jikigai's *"own **automated jobs**"* and enumerate Inngest, CI and community
monitoring. **An operator-driven interactive run on a workstation is not an automated job.** Copying
either precedent verbatim would leave operator-assisted runs outside the carve-out — which is exactly
the failure the register's re-key note records escaping twice. Every string above names the
operator-assisted limb explicitly rather than relying on the automated-jobs framing.

## Annotation banner (A7)

Plain English, no PR or branch reference, per
`knowledge-base/project/learnings/2026-05-12-public-legal-doc-annotations-no-pr-numbers.md`. Cite
sections, never issues:

> *(Scope clarification added 9 August 2026: the distinction between plugin-local and
> operator-assisted processing was previously implicit, which left these sections reading as
> statements about every configuration.)*

Framed as a **scoping clarification**, never as a correction-of-falsity — the determination §4 is
explicit that the existing text is true within its scope and inapplicable outside it.
