---
title: "Counsel review audit — PR #7100 (Art. 30(1) closure: PA-31 / PA-32 / PA-33, the Art. 6(1)(f) LIA, the DPIA screening, and the correction of three published legal documents)"
type: counsel-review
date: 2026-08-01
pr: 7100
issue: 7100
changed_artifact:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md
  - knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md
  - knowledge-base/legal/data-processing-agreements/anthropic.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/statutory-response-catalog.md
  - docs/legal/privacy-policy.md
  - docs/legal/gdpr-policy.md
  - docs/legal/data-protection-disclosure.md
  - plugins/soleur/docs/pages/legal/privacy-policy.md
  - plugins/soleur/docs/pages/legal/gdpr-policy.md
  - plugins/soleur/docs/pages/legal/data-protection-disclosure.md
  - apps/web-platform/lib/legal/legal-doc-shas.ts
status: "BLOCKED — one blocking in-PR condition (C1); discharges automatically on C1 landing"
signed_off_at: null
reviewed_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the re-evaluation triggers below"
brand_survival_threshold: single-user incident
re_evaluation_triggers: "The first arms-length (non-founder) user of the Soleur Web Platform; any EEA-out transfer not covered by the disclosed DPF/SCCs; the CJEU ruling in C-703/25 P (Latombe appeal) on the adequacy of the EU-US DPF; publication of the final (non-consultation) version of EDPB Guidelines 1/2024 on Art. 6(1)(f), on which the D9 necessity-first conclusion partly rests; publication of the final version of EDPB Guidelines 03/2026 on web scraping, on which the Art. 14(5)(b) narrow reading partly rests; the Anthropic Zero-Retention amendment remaining unsigned 90 days from 2026-07-30 while the fleet continues to egress third-party content; PA-32's republication limb continuing unremediated past the #7119 remediation window; the full DPIA for PA-32 (#7121) remaining outstanding; any fleet member gaining authority to block, ban, restrict or rank a natural person (re-opens the Art. 22 negative determination); any fleet member being pointed at a repository, Discord guild or social account other than jikig-ai/soleur and Jikigai's own properties; the arrival of a first non-founder contributor whose source is transmitted to Anthropic under PA-33 (re-opens the CLA-scope question at LIA outstanding item 3)."
---

# Counsel review audit — PR #7100 (Art. 30(1) closure for the Anthropic-egressing fleet, the CI surface, and community republication)

> **STATUS: BLOCKED — on one condition (C1), which is a single paragraph in one
> file the PR is already editing and already SHA-repinning.** Seven non-blocking
> conditions (C2–C8) are recorded.
> Reviewed by the `clo` agent on 2026-08-01. The `clo` agent is the reviewing
> authority for the v1 Soleur-as-tenant-zero posture — this is an agent-native
> company; legal review is a CLO-agent function, not a task for the non-lawyer
> operator. The operator retains an optional veto; **external** counsel re-review
> is reserved for the frontmatter re-evaluation triggers.
> Every implementation-detail claim relied on below was cross-checked against the
> implementing source, the workflow YAML, the live GitHub API, and the published
> documents themselves — not against the PR's own summary of them.

## Why this is BLOCKED and not "DISCHARGED subject to C1"

The #7086 audit used the status "DISCHARGED WITH ONE BLOCKING IN-PR CONDITION".
That form is unavailable here because this gate returns a binary that decides
whether the PR may merge. A statement that must be corrected *before* merge and a
disposition that *permits* merge cannot both be returned. The accurate binary is
**BLOCKED**, and it inverts to DISCHARGED the moment C1 lands. Nothing else in
this change is held back by it.

This is not a judgement on the change's quality. On the substance the work is the
strongest legal record in this repository: it closes a real Art. 30(1) gap, and it
does so by recording three findings against the controller's own interest —
**no available lawful basis** for a live limb, an **overdue** Art. 14 obligation,
and an **overdue** DPIA — where the easier path was an assertion. Sections 1–5
below discharge every question put to this review in the controller's favour on
the merits. C1 is a completeness failure in the published-document sweep, and it
is the third instance of the same failure class already caught twice in this PR.

## Scope of the gate

The gate fired because the diff touches `knowledge-base/legal/` and `docs/legal/`
and the plan declares `brand_survival_threshold: single-user incident`. Unlike
#7086 — where the legal diff was two disclaimers of non-exhaustiveness — this
change **asserts new legal positions**: three Art. 30 activity entries, a
four-arm Art. 6(1)(f) assessment, an Art. 35 screening determination, an Art. 14
determination, and corrections to three published legal documents whose SHAs are
repinned in `apps/web-platform/lib/legal/legal-doc-shas.ts`. The review bar is
correspondingly higher.

Out of scope by instruction and confirmed appropriate: R1–R5 deferral to OPEN
#7119; the AC17 scope expansion; and the `operator-digest.workflow.yml`
asset-vs-deployed drift residual at PA-33 member (7).

---

## 1 — Lawful basis: sound for all four arms, and the Art. 6(1)(b) operator treatment is correct

**Arm A (repository / engineering) — CONCUR.** The interest (operating the
company's own engineering function over its own public repository) is legitimate;
necessity is satisfied because the artefact under assessment *is* the
contributor's content, so there is no less intrusive means that still performs the
task; and a contributor to a public repository has a Recital 47 expectation that
comfortably covers automated processing of what they published there. Nothing to
correct.

**Arm B1 (community collection + Anthropic egress) — CONCUR, and the
"narrowly and conditionally" qualifier is the right register.** Two things make
this arm defensible rather than comfortable, and the record states both rather
than eliding them: the Discord source is bot-token-gated and therefore **not** a
publicly accessible source, and the LIA records at PA-31 §(c) that
**output minimisation is not input minimisation** — the prompt's aggregate-only
directives constrain the digest, not the model input, so raw guild messages and
untruncated Hacker News comment text reach a US processor regardless. A record
that had cited the minimisation directives as an Art. 32 measure on the egress
path would have been materially false; this one says so expressly at PA-31 §(g)(8)
("NO PII SCRUB EXISTS on Anthropic-bound content on this path"), and declines to
inherit PA-22's `sanitizePromptString` TOM on the correct ground that the CLI path
has no prompt-assembly chokepoint to scrub at. Conditioning the conclusion on the
Art. 14 obligation being discharged is the right structure: Art. 6(1)(f) balancing
under Recital 47 turns on reasonable expectations, and expectations cannot be
asserted for a population that has never been told anything.

**Arm B2 (republication) — see Section 2. CONCUR, without qualification.**

**Arm C (CI contributors) — CONCUR.** Necessity is satisfied on the same
artefact-under-assessment logic as Arm A. The Recital 49 network-and-information-
security interest is correctly invoked for the `fix-constraints-stage-a` and
`ci.yml` gate limbs and correctly *not* stretched to cover the whole surface. The
fork-exclusion reasoning is verified against source: forks receive no secrets, so
`.github/actions/anthropic-preflight/action.yml` fails and the agent step is
skipped — this is a structural bound, not a policy one, and the record describes it
as such. The **CLA-scope question is correctly left open rather than resolved**:
whether the Individual/Corporate CLA's IP grant extends to transmitting
contributor source to a third-party AI processor is a contract-construction
question, and the record's statement that "an IP licence is not a lawful basis, and
a lawful basis is not an IP licence" is exactly right. Resolving it in the
controller's favour here would have been the error.

**Art. 6(1)(b) for the operator — CORRECT, and correctly bounded.** The operator
is party to the contract under which the Web Platform is provided, and the
processing of his own commits, prompts and run telemetry is necessary for its
performance. Two features of the treatment are what make it correct rather than
convenient: it is scoped to the operator alone and never reaches across to the
third-party populations (which would have been the classic Art. 6(1)(b)
over-extension the EDPB warned against in Guidelines 2/2019), and the *derived*
cost- and run-telemetry writes are put on Art. 6(1)(f) rather than swept into
6(1)(b) — telemetry generated by the controller about its own operations is not
"necessary for the performance" of the subject's contract, and splitting it out is
the more defensible reading. It mirrors PA-22's existing treatment, so the register
holds one position and not two.

**One structural point that carries the whole record: "Art. 28 is not Art. 6."**
This is stated at PA-31 §Lawful basis, repeated at PA-33, and now written into the
Anthropic row of the Vendor / Sub-Processor Mapping. It is the precise correction
of the confusion that produced the #7086 gap in the first place — an Art. 28
processor record was doing duty as though it supplied a controller-side basis. It
does not, and the register now says so in the row a reader would misuse.

**Verdict on question 1: SOUND for all four arms; the Art. 6(1)(b) operator
treatment is correct.**

---

## 2 — D9: the necessity-first conclusion is CORRECT AS A MATTER OF LAW. I concur. It should not be softened, and I have not softened it.

The proposition under review: **Art. 6(1)(f) is not available for the republication
limb as implemented; the assessment fails at the necessity limb and does not reach
balancing; no other Art. 6 basis is available.**

**The three-condition structure is settled law and the ordering is not optional.**
Art. 6(1)(f) imposes three **cumulative** conditions — a legitimate interest, the
necessity of the processing for that interest, and the non-overriding of the data
subject's interests and fundamental rights. The CJEU has restated that cumulation
consistently: *Rīgas satiksme* (C-13/16) at [28], *TK v Asociaţia de Proprietari*
(C-708/18) at [40], *Meta Platforms v Bundeskartellamt* (C-252/21) at [106], and
*KNLTB* (C-621/22) at [45]. Because the conditions are cumulative, failure of any
one is dispositive and the controller does not reach the next. Necessity precedes
balancing in the text of the provision and in every one of those judgments'
sequencing. **The necessity-first structure is therefore correct, and it is not a
stylistic choice — a balancing exercise conducted on processing that failed
necessity would be an answer to a question that never arose.**

**The citations support the proposition, with one precision point.** *Rīgas
satiksme* at [30] holds that derogations and limitations on the protection of
personal data must apply only in so far as is **strictly necessary**, and reads the
necessity condition together with the data-minimisation principle. That squarely
supports "necessity is an autonomous, strictly-construed, cumulative condition",
which is what Arm B2 and PA-32 use it for. It is fair authority and it is not
mis-cited.

The narrower formulation the record actually deploys — *"the interest cannot
reasonably be achieved by less intrusive means"* — has a **tighter** home than
*Rīgas satiksme*. Its canonical statement is C-708/18 *TK* at [47]: the controller
must examine whether the objective "may reasonably be achieved just as effectively
by other means less restrictive of the fundamental freedoms of the data subjects",
reiterated in C-252/21 *Meta Platforms* and in C-621/22 *KNLTB*. This is a
strengthening point, not a defect: the record's conclusion is *better* supported
than its citation string shows. Adding *TK* is **C2** (non-blocking).

EDPB Guidelines 1/2024 are correctly used and correctly disclosed. They treat
necessity as a cumulative requirement assessed before and independently of
balancing, which is exactly the proposition cited. The record states on its face
that the version relied on is the consultation version 1.0 and that no final
version is asserted — the right discipline, and the compliance-posture note goes
further and disentangles 1/2024 from Guidelines **03/2026** on web scraping after
the two were conflated in an earlier draft. Guidance in consultation is persuasive
and not binding; the conclusion does not depend on it, because the CJEU authorities
above carry it alone.

**The substantive conclusion is right, and it is right by a margin.** The stated
purpose of the digest is *operator awareness of community activity*. An aggregate
count plus a link to the source thread serves that purpose identically. That is a
textbook less-intrusive alternative, and the necessity limb fails on it. The
conclusion is in fact available **a fortiori**: the operator-awareness purpose does
not require *publication at all* — an internal file or a direct message serves it —
so it is not merely the identifiers that are unnecessary but the publication
operation itself. The record reaches the correct answer by the narrower route,
which is the conservative choice and I do not disturb it.

**I tested the conclusion against the arguments that would defeat it, and none
does.**

- *Could a different purpose rescue necessity?* Only by asserting one — a public,
  positioning-oriented community record — that the digest was not built for. PA-32
  §(a) identifies exactly this and routes it to the Art. 5(1)(b) / Art. 6(4)
  compatibility analysis, where it fails: weak link between purposes, semi-private
  context of collection, communications content, permanent public consequence, no
  pseudonymisation. A controller may not retrofit a purpose to manufacture
  necessity, and the record closes that door properly rather than leaving it ajar.
- *Does "manifestly made public" help?* No. That is Art. 9(2)(e), a special-category
  gateway, not an Art. 6 basis. The record does not misuse it. Public availability
  goes to **balancing**, which necessity failure means we never reach — and it does
  not touch the Discord limb, which is not public at all.
- *Is the Discord balancing observation doing improper work?* No. It is expressly
  labelled as recorded "for completeness rather than as the basis of the
  conclusion", in both the internal record and the published GDPR Policy. That is
  the correct handling of an alternative holding.

**The internal-precedent argument is the strongest paragraph in the record and it
is properly deployed.** PA-30's own LIA justifies the beta-CRM's database boundary
expressly on the ground that git-committed third-party PII would be "an Art. 17
erasure impossibility… The DB boundary is load-bearing, not incidental." PA-32 does
the very thing Jikigai rejected in writing, on a *public* repository. A supervisory
authority reading the two entries side by side would find the inconsistency in
minutes. Asserting a clean basis at PA-32 would have left the register holding two
irreconcilable positions — which is a worse posture than the negative finding, and
the record says so.

**Verdict on question 2: the citations support the proposition; the necessity-first
structure is correct as a matter of law; the conclusion is correct. NOT softened,
NOT hedged, and no BLOCKED finding arises from D9.** The single amendment is C2, a
citation addition that strengthens it.

---

## 3 — Art. 14: the "engaged, undischarged, overdue" assessment is correct, and the per-sub-population 14(5)(b) reasoning is sound

**Art. 14 rather than Art. 13 is the right article.** The data is obtained from
third-party platforms, not collected from the data subject; WP260 rev.01 assigns
that case to Art. 14. Correct.

**"Overdue since ~2026-03-19" is correct, and if anything understated.** Art.
14(3)(a) sets one month from obtaining; the earliest committed digest is
`2026-02-19-digest.md`; the deadline was ~2026-03-19. Verified.

**A point the record misses, and it runs against the controller.** The record grounds
the deadline solely on Art. 14(3)(a). For the `cron-daily-triage` limb, Art.
**14(3)(b)** also engages — where the data are to be used for **communication with
the data subject**, the information must be provided *at the latest at the time of
the first communication*. Posting a bot-authored comment onto a third party's issue
is a communication with that data subject. That is a **stricter** deadline than
14(3)(a), it has been missed at every such comment, and it continues to be missed on
the live limb. This is recorded as **C3** (non-blocking, because it makes an
already-recorded breach worse rather than disturbing any conclusion) and it should
be carried into #7120's scope.

**No Art. 14(5) exemption claimed — correct.** 14(5)(a) is unavailable: the record
establishes affirmatively that the subjects did not have the information, because
the published policy said the opposite until this PR.

**The per-sub-population 14(5)(b) table is sound, and the per-sub-population method
is itself the correct one.** A wholesale assertion of disproportionate effort would
have been the standard error; WP260 rev.01 requires the controller to weigh the
effort against the impact and to document it, and the effort plainly differs across
these three populations. On the merits:

- *Discord members* — **fails**, and obviously so. Jikigai operates the guild; a
  pinned message costs nothing. Correct.
- *GitHub commenters* — **fails**. Reachable through the repository's own README /
  CONTRIBUTING / issue templates and by `@`-mention. Correct.
- *Hacker News posters and drive-by stargazers* — **arguable**, and the record's
  refusal to bank it is right for a reason it states precisely: 14(5)(b) is not
  self-executing. Where it applies, the controller must take appropriate measures to
  protect the data subject's rights, **including making the information publicly
  available**. No such notice exists, so the exemption cannot presently be invoked
  even where it is arguable. That is the correct reading, and it is the reading the
  EDPB's draft web-scraping guidance also takes — cited, correctly, as a consultation
  draft and never as settled law.

**One precision defect, non-blocking.** For Arm A and Arm C the table records Art. 14
as "substantially discharged by context" / "materially satisfied by context". That
is not a GDPR category. Under Art. 14 the information is either already held by the
subject (14(5)(a), an exemption that must be claimed and evidenced) or it is due and
undischarged. "Context" is a good reason to expect the remediation to be cheap; it is
not a discharge. The safer and equally cheap record is: notice due, undischarged,
low-cost remediation tracked at #7120 — with no exemption claimed. **C4.**

**Verdict on question 3: the assessment is correct; the per-sub-population 14(5)(b)
reasoning is sound. Two precision conditions (C3, C4), neither blocking.**

---

## 4 — DPIA: the PA-32 / PA-31–33 split is defensible, and the two-criteria justification is properly documented

**PA-32 — full DPIA REQUIRED: correct.** Six WP248 rev.01 criteria against a stated
threshold of two. I checked each engaged criterion rather than the tally:

- **3 systematic monitoring** — correctly grounded on WP248 criterion 3, which
  carries no large-scale qualifier, rather than on Art. 35(3)(c), which does. The
  memo says exactly this and declines to claim 35(3)(c). That distinction is the
  difference between a defensible screening and an overreach, and the memo gets it
  right.
- **4 data of a highly personal nature** — verbatim content of messages in a
  bot-token-gated guild is electronic communications content. Supported.
- **6 matching / combining** — six platforms merged into a per-person cross-platform
  view with inferred affiliation. Squarely WP248's example. Supported.
- **7 vulnerable data subjects** — WP248 frames this as an imbalance preventing the
  subject from opposing the processing. No relationship, no notice, no objection
  route, no erasure route. Supported.
- **8 innovative technology** — autonomous LLM agents with tool grants and a
  publication path, unattended. Supported, and correctly rated *more* strongly than
  PA-27's read-only no-tools summarizer rather than copied across at PA-27's level.
- **9 processing that prevents exercise of a right** — **arguable**. WP248's worked
  example is a bank credit-screening that blocks access to a service, not the
  foreclosure of GDPR rights themselves. The criterion's text is literally "prevents
  data subjects from exercising a right", so the reading is textually available and
  the memo argues it as a property of the chosen mechanism rather than as a generic
  "rights are hard" observation — which is the right way to argue it. Recorded as an
  arguable rather than settled engagement (**C5**, non-blocking). It changes nothing:
  five criteria remain, against a threshold of two.

**Criterion 5 (large scale) recorded as NOT ENGAGED** — reasoned on the WP243/WP248
factors and expressly rejecting the "15+ data sources daily" framing on the correct
ground that source count is not a WP243 factor. The memo flags this as "the one
criterion where the honest answer favours the controller, and it is recorded as
such". That sentence is the mark of a screening done properly.

**"Overdue by ~5 months" — correct.** Art. 35(1) requires the assessment prior to the
processing; the processing began 2026-02-19.

**PA-31 and PA-33 — full DPIA not required: defensible, and — the point that decides
it — properly justified.** PA-33 engages one criterion; unremarkable. PA-31 engages
**two**, which is exactly WP248's "in most cases" indication. Concluding "not
required" at that count is permissible **only** where the controller documents the
reasons for departing from the presumption. §2.1 does precisely that, treats the
two-criteria rule as "a presumption, not a rule", and gives three activity-specific
reasons: no public-output limb (that limb is PA-32), a contracted Art. 28 recipient
under DPF + SCCs M2+3 + UK IDTA + Swiss Addendum, and solo-company scale. That is the
documented justification WP248 requires, and it is why the split holds. Had §2.1
simply asserted "not required" at two criteria, this would be a finding.

**§2.3 is the memo's best judgement and it is correct**: conducting a full DPIA on a
limb the controller's own LIA concludes has no lawful basis is the less useful path,
because the assessment would be assessing something that should not be happening —
coupled with the express caveat that remediation does **not** cure the overdue period
or the already-published corpus, and that the processing should not continue
unremediated while either path is pending. That caveat is what keeps §2.3 from
reading as an excuse to defer.

**Verdict on question 4: the split is defensible and properly justified. One
non-blocking precision condition (C5).**

---

## 5 — Retention / Art. 5(1)(e): recording "Art. 17 path: NONE" as a finding is the correct treatment, and the Anthropic posture is correctly disclosed

**Recording it as a finding is right, and the alternatives are all worse.** The three
available treatments were: leave the cell blank (an Art. 30(1)(f) omission); state a
retention period that does not exist (false); or record that the chosen mechanism has
no erasure path and that this is a compliance finding. Only the third is accurate.
Art. 30(1)(f) requires the envisaged time limits "where possible" — the honest
completion of that limb, where erasure is not implementable, is to say so.

More importantly, the record does not stop at *unimplemented*. It establishes **not
implementable**, and it does so mechanically: git history is append-only, so a
deletion commit erases nothing; the data persists in every prior commit object, in
GitHub's commit UI, in every clone and in **both forks**; `git filter-repo` plus a
force-push breaks downstream clones, does not reach forks, and does not reach public
issue bodies whose edit history GitHub retains. A supervisory authority will accept a
"no erasure path" finding backed by that reasoning far more readily than a remediation
promise that cannot be kept. The measurements are all cited to the commands that
produced them — 80 digests spanning 2026-02-19 → 2026-06-08, 45 with the commenter
table, 65 naming stargazers, **zero** deletions across the repository's entire history,
public repo with 2 forks.

The correction at PA-32 §(f) replacing *"appears to have produced nothing… should be
re-verified at merge"* with a flat statement of the scheduled live state deserves note:
it removed an unperformed operator step from inside an Art. 30 record, and its stated
reason — "a controller hedging whether its own scheduled function runs reads, to a
supervisory authority, as not knowing" — is correct.

**The Anthropic 30-day / unsigned-amendment posture is correctly disclosed, and
correctly de-scoped from PA-27.** PA-31 §(f) states that the Zero-Retention amendment
is unsigned, that Anthropic's default 30-day request/response retention therefore
applies to **all** fleet egress including raw Discord content and GitHub comment bodies
— not only to the PA-27 surface it was previously reasoned about — that Jikigai cannot
shorten the window, and that a 90-day re-evaluation trigger attaches. This discharges
#7086's C3 in substance. The Vendor / Sub-Processor Mapping row carries the same
statement, so the machine-readable index and the activity entry agree.

The **third** retention surface is the one most records would have dropped: the
self-hosted Inngest event/run store has **no automatic deletion**, so recording only
Anthropic's 30 days "would imply a retention story this activity does not have". That
sentence is correct and the surface is correctly enumerated.

**Verdict on question 5: the finding treatment is correct; the Anthropic posture is
correctly and completely disclosed.**

---

## 6 — BLOCKING (C1): Privacy Policy §6 still tells data subjects they can withdraw by deleting their contributions, and that the processing is necessary. Both are false, both favour the controller, and this PR republishes them.

This is the only blocking finding.

`docs/legal/privacy-policy.md` § 6 ("Legal Basis for Processing") — and its Eleventy
mirror at `plugins/soleur/docs/pages/legal/privacy-policy.md` — carries, unamended:

> If you interact with the GitHub repository (e.g., filing issues), the legal basis
> for processing your GitHub profile information in that context is **legitimate
> interest** (Article 6(1)(f) GDPR) -- facilitating community participation in the
> project. The balancing test for this interest considers: (a) the processing is
> limited to publicly available GitHub profile data voluntarily shared by the user,
> (b) the user initiated the interaction, **(c) the processing is necessary for the
> stated purpose (community participation)**, and **(d) the user can withdraw by
> deleting their GitHub contributions.**

Three defects, in the section a data subject and a supervisory authority open to find
the Art. 13/14(1)(c) legal basis:

1. **Limb (d) is affirmatively false, and it is false in the controller's favour.**
   It tells the data subject they hold a self-help remedy. § 7 of the *same file*, as
   amended by *this PR*, says the opposite: "Git history is append-only, so these
   copies have no retention period and **cannot be reliably erased by deleting the
   original contribution**." § 4.4 and the § 8.1 carve-out say the same. This is the
   #7086 Finding 4 class exactly — a published record telling a reader something the
   controller knows to be untrue, in the direction that reduces the controller's
   exposure.
2. **Limb (c) asserts necessity** for the family of processing whose republication
   limb this PR's own D9 concludes is **not necessary**. The policy therefore asserts
   necessity in § 6 and denies it in § 4.4.
3. **Limb (a)** ("limited to publicly available GitHub profile data") does not survive
   the Discord limb, though that is the weakest of the three since § 6's sentence is
   scoped to GitHub.

**Why this blocks where the pre-existing Art. 30 gap did not, and where C2–C8 do not.**

- **The GDPR Policy proves the sweep knew about this and missed one.**
  `docs/legal/gdpr-policy.md` § 3.3 carries the *identical* (a)–(d) balancing limbs at
  line 67 — and this PR placed a correction block immediately after it ("The preceding
  paragraph does not describe all of our processing, and **two of its assumptions do
  not hold**"), with ¶73 expressly rebutting limb (d). The corrective paragraph was
  written for this exact sentence, applied in one document, and not applied to its twin
  in the other. This is the third instance of the failure class the 10-agent review
  already caught twice (one of two named false statements corrected; a third document
  missed entirely).
- **This PR republishes the statement under an attestation that it was corrected.**
  `apps/web-platform/lib/legal/legal-doc-shas.ts` is repinned for `privacy-policy` to
  `8b9d66da…` (verified against the file). The "Last Updated" note dates the document
  2026-07-31 as a material correction of controllership. Shipping a corrected-and-
  re-attested policy that still contains a false controller-favourable remedy statement
  is worse than shipping the uncorrected one, for the same reason #7086's C1 blocked:
  it invites the reader to rely on it.
- **It is not pre-existing in any way that helps.** Before this PR, § 6 could be read
  as describing GitHub-platform processing. § 4.4 as amended makes Jikigai's own
  controllership over that same activity explicit, which converts § 6 from ambiguous
  into wrong.
- **The remedy is one paragraph in a file already open in the diff.** There is no
  scope-discipline argument for deferring it, and no argument that blocking leaves the
  record worse.

**C1 — required before merge.** Append to `docs/legal/privacy-policy.md` § 6, after the
GitHub-repository paragraph, and mirror to
`plugins/soleur/docs/pages/legal/privacy-policy.md`, a correction block in the form
already used at `gdpr-policy.md` § 3.3 that: (i) withdraws limb **(d)** and states that
deleting a GitHub contribution does **not** remove a copy already republished in a
digest committed to Git history or in a fork; (ii) qualifies limb **(c)** by recording
that the necessity limb **fails** for the republication step, cross-referencing § 4.4;
and (iii) states the lawful basis for the collection-and-Anthropic-egress limb —
Art. 6(1)(f) — which § 6 currently omits altogether even though Art. 13/14(1)(c)
requires the basis to be given (the GDPR Policy states it at § 3.3 ¶75; the Privacy
Policy states it nowhere). Then re-run the SHA repin for `privacy-policy` in
`apps/web-platform/lib/legal/legal-doc-shas.ts`.

On C1 landing, and on my verification of the mirror and the SHA, this audit's
disposition inverts to **DISCHARGED** and its `status` becomes
`SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`. No other condition need
land first.

---

## 7 — Published-policy adequacy: everything else checked is accurate, and several passages are better than adequate

Checked against the internal record rather than against the PR's summary.

**`privacy-policy.md` § 4.4 republished-category list — ACCURATE AND COMPLETE.** All
six populations from PA-32 §(b) appear: GitHub contributor usernames with quoted
excerpts (45 of 80), stargazer usernames (65 of 80), Discord member handles with first
names, join dates and inferred affiliation *including the verbatim private-guild
message disclosing employer context*, Hacker News handles, and **X and Bluesky**. The
last two matter: PA-32 §(b) records that they were omitted from the register's own
first pass and added at review. The published list is the complete one. The counts
match the LIA provenance measurements. The paragraph states plainly that the copies
cannot be reliably erased, that there are 2 forks, and — in the sentence that most
records would have avoided — "**As of 2026-07-31 this publication has not yet stopped**
… We are stating this rather than describing the work as already under way, because it
is not." That is the correct disclosure of a live unremediated breach.

**§ 4.4's Art. 15 promise — correctly limited, and honest about it.** "the search is
manual and **we cannot guarantee it is complete**", and "for data already committed to
Git history **we have no way to remove it**… We would rather tell you that than imply a
removal we cannot perform." This matches PA-32 §(h) exactly. No over-promise.

**§ 8.1 community-digest carve-out (Arts. 15 / 17 / 21) — ACCURATE, and it closes a
real gap.** It names all six populations, directs them to Jikigai rather than GitHub,
states that no account is needed, describes what will and will not be done, and states
that the **Art. 21(1) objection right is available immediately and does not depend on
the erasure limitation** — which is the legally important sentence, because Art. 21(1)
is mandatory for all Art. 6(1)(f) processing and its availability is independent of
whether erasure is possible. The § 8.1 lead-in and the closing GitHub sentence were both
amended to route this population correctly, so the carve-out is reachable from the
section's own navigation rather than stranded at the end.

**`gdpr-policy.md` § 3.3 necessity-first framing — ACCURATE, and the plain-language
rendering is faithful.** "necessity is assessed *before and independently of* any
balancing: where a less intrusive means would achieve the same purpose, legitimate
interest is unavailable regardless of how a balancing exercise would come out… The
assessment therefore **fails at the necessity limb and stops there**." That is a correct
lay statement of the cumulative-conditions doctrine, it does not overstate the
authorities, and it correctly marks the Discord balancing observation as recorded "for
completeness rather than as the basis of the conclusion". § 3.3 also states the live
status and the collection limb's continuing basis. Nothing here is more favourable to
the controller than the internal record supports.

**`gdpr-policy.md` § 9 DPIA correction — ACCURATE.** It withdraws the prior unqualified
"not required", states that a full DPIA **IS** required for the community activity on
six WP248 criteria against a threshold of two, states that it is **overdue by
approximately five months** because Art. 35(1) requires it before the processing, and —
the part most corrections get wrong — surgically repairs limb (b) of the retained
analysis ("no systematic monitoring of individuals occurs **on those two surfaces**")
rather than leaving a now-false limb standing inside a paragraph marked as corrected.

**`gdpr-policy.md` § 2.2 and `data-protection-disclosure.md` § 2.2(b) / § 2.3 table /
Anthropic sub-processor row — ACCURATE on controllership.** The Anthropic bullet is
split into the plugin path (user's own key, independent controller/processor) and the
Jikigai-operated path (Jikigai controller, Anthropic processor), with the prior
statement labelled **"affirmatively false"** for the second path and dated to when it
became so. `privacy-policy.md` § 5.1 receives the matching scoping paragraph so that
"Soleur does not intermediate, intercept, or store any data" can no longer be read as
covering Jikigai-keyed egress. The DPD § 2.3 table gains a distinct row for the
Jikigai-keyed surface. All three canonical documents and all three Eleventy mirrors
carry the corrections; all three SHA pins verified against the files.

**No further false or misleading published statement was found**, other than
`privacy-policy.md` § 6 (C1) and the DPD sub-processor-row column gap (C6 below).

---

## Conditions

| # | Condition | Blocking? |
|---|---|---|
| **C1** | **Correct `docs/legal/privacy-policy.md` § 6** (and its Eleventy mirror, then repin the SHA): withdraw limb (d)'s false withdrawal remedy; qualify limb (c)'s necessity assertion against § 4.4; and state the Art. 6(1)(f) basis for the collection-and-egress limb, which § 6 currently omits. Use the correction-block form already applied at `gdpr-policy.md` § 3.3. | **YES — must land before merge** |
| **C2** | Add **C-708/18 *TK v Asociaţia de Proprietari*** [47] (and optionally C-252/21 *Meta Platforms* / C-621/22 *KNLTB*) alongside *Rīgas satiksme* in LIA Arm B2, PA-32 §Lawful basis and the LIA External-authorities table, as the direct authority for the "no less intrusive means that achieves the objective just as effectively" formulation. *Rīgas satiksme* supports strict necessity; *TK* is where the less-intrusive-means test is stated in terms. Strengthens D9; does not change it. | No |
| **C3** | Record that **Art. 14(3)(b)** also engages for the `cron-daily-triage` public-comment limb — information due *at the latest at the time of the first communication with the data subject*, a stricter deadline than 14(3)(a), breached at every such comment and continuing on the live limb. Add to LIA §Art. 14, PA-32 §(b), and #7120's scope. | No |
| **C4** | Replace "substantially discharged by context" / "materially satisfied by context" for Arms A and C (LIA §Art. 14 table, PA-31 §(b)(i), PA-33 §(b)) with the GDPR-recognised disposition: notice **due and undischarged**, no Art. 14(5) exemption claimed, low-cost remediation at #7120. "Context" is a reason the fix is cheap, not a discharge. | No |
| **C5** | Mark WP248 criterion **9** for PA-32 as *arguable rather than settled* — WP248's worked example is denial of a service, not foreclosure of GDPR rights — and note that the PA-32 conclusion stands on the remaining five criteria regardless. | No |
| **C6** | **`data-protection-disclosure.md` § 2.3 Anthropic sub-processor row:** the *Purpose* column was extended to name PA-31/32/33, but the **Data categories** and **Lawful basis** columns were not. The row therefore now represents that all listed purposes rest on the email-triage LIA's legitimate interest — which is false for PA-32's republication limb (no basis) and unsupported for PA-31/PA-33 (governed by the new LIA). Extend both columns, cite `2026-07-31-claude-eval-fleet-and-ci-lia.md`, and state PA-32's no-basis finding in the row. This is the only remaining published statement more favourable to the controller than the internal record supports; it is non-blocking only because the DPD is the internal-facing disclosure and the Privacy Policy and GDPR Policy both state the position correctly. | No |
| **C7** | **Stale figures that the review sweep corrected at source but not downstream.** (i) `article-30-register.md` Vendor/Sub-Processor Mapping, Anthropic row: "PA-31 (… 21 Inngest modules, of which **15** reach Anthropic through the Claude Code CLI and **3** by direct HTTPS)" — 15 + 3 = 18, not 21. PA-31 §(a) was corrected at review to **18 CLI (16 `spawnClaudeEval` + 2 inline) + 3 HTTPS = 21**, and its correction block names "correcting a scope-mismatched figure with another scope-mismatched figure" as the failure it exists to end. The same row also reads "PA-33 (… **5 `.github/` members**)", superseded by PA-33 §(d)'s **6 files / 7 job-level surfaces** plus member (7) outside `.github/`. (ii) `2026-07-31-dpia-screening…md` line 41: "PA-33 — Jikigai-keyed CI surface (**5 `.github/` members**)" — same stale figure. | No |
| **C8** | **Five sites now assert an Art. 21(1) gap this PR itself closed.** LIA §Art. 15/20/21/22, PA-31 §(h), PA-32 §(h), PA-33 §(h), `compliance-posture.md` #7126 row, and DPIA memo criterion-7 rationale all state that **no** legal document provides an objection route for this population — while `privacy-policy.md` § 8.1 now provides exactly that route and `statutory-response-catalog.md` (amended in this same PR) points to it by name. Narrow the claim to what remains true: a route now exists at Privacy Policy § 8.1; what #7126 tracks is a **mechanism** and an Art. 15 completeness guarantee, not the absence of a route. Separately, the LIA §Art. 14 paragraph beginning "A separate and more urgent defect in the outward-facing record" still reads in the present tense ("currently tells the public"), still says correction is "outside this record's scope", still carries the self-cancelling "DEF-1a (resolved in this PR)" / "Until it lands", and names only **two** of the three corrected documents. PA-32 §(b) fixed this exact three-tenses defect in the register; the LIA copy was not swept. Rewrite it in the past tense naming all three documents. | No |

C6–C8 are all instances of one pattern: the review pass corrected the authoritative
cell and did not propagate to the cells that quote it. That pattern is precisely what
deferred item **DEF-2 (#7125)** exists to guard against, and it is worth noting that the
drift guard is being built while the same drift is being introduced. None of them is
controller-favourable except C6, and none misleads a data subject.

## Attestation

The `clo` agent has reviewed:

- `knowledge-base/legal/article-30-register.md` — PA-31, PA-32, PA-33 in full, the
  PA-17 amendment, and the Vendor / Sub-Processor Mapping rows for Anthropic PBC,
  GitHub Inc, Sentry, Better Stack and the new Discord Inc row;
- `knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md`
  — Arms A, B1, B2 and C, the Art. 14 analysis, the Art. 15/20/21/22 section, the
  PA-17 / #4558 trigger discharge, and the External-authorities table;
- `knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md`
  — the Art. 35(3) indicators, the WP248 rev.01 nine-criteria table, the CNIL national-
  list check, and conclusions §2.1–§2.3;
- `knowledge-base/legal/data-processing-agreements/anthropic.md`,
  `knowledge-base/legal/compliance-posture.md`,
  `knowledge-base/legal/statutory-response-catalog.md`;
- all three canonical published documents and all three Eleventy mirrors, read as a
  data subject would read them rather than as a diff;
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — all three pins recomputed and
  verified against the files;

and independently verified against the primary sources: the CJEU authorities cited
(C-13/16, C-101/01, and C-708/18 / C-252/21 / C-621/22 as the tighter necessity
authority), WP248 rev.01's criteria and its two-criteria presumption, Art. 14(3)(a) and
14(3)(b) timing, Art. 14(5)(a)/(b) and its public-availability condition, Art. 35(1) and
35(3), and the OPEN state of issues **#7119–#7126** via `gh issue list` (all eight
confirmed OPEN).

The `clo` agent **BLOCKS** the Counsel-Review CLO-Attestation gate for PR #7100 on
condition **C1**, and records C2–C8 as non-blocking. On C1 landing and verification,
this attestation converts to **DISCHARGED** with `status: SIGNED-OFF
(CLO-agent-attested, Soleur-as-tenant-zero v1)`.

Per-artifact verdict:

| Artifact | Verdict |
|---|---|
| `knowledge-base/legal/article-30-register.md` (PA-31) | **APPROVED** — C7 non-blocking (Vendor-mapping figures) |
| `knowledge-base/legal/article-30-register.md` (PA-32) | **APPROVED** — the D9 no-lawful-basis finding is affirmed without qualification; C5, C8 non-blocking |
| `knowledge-base/legal/article-30-register.md` (PA-33) | **APPROVED** — C7, C8 non-blocking |
| `knowledge-base/legal/article-30-register.md` (PA-17 amendment) | **APPROVED** — the #4558 trigger is properly discharged; withdrawing the "display-only" and "load-bearing Art. 14 gate" over-claims is correct |
| `…/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md` | **APPROVED** — C2, C3, C4, C8 non-blocking |
| `…/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md` | **APPROVED** — C5, C7 non-blocking |
| `knowledge-base/legal/data-processing-agreements/anthropic.md` | **APPROVED** — discharges #7086 C1–C4 in substance |
| `knowledge-base/legal/compliance-posture.md` | **APPROVED** — C8 non-blocking |
| `knowledge-base/legal/statutory-response-catalog.md` | **APPROVED** — the fourth requester class is correctly added; no condition |
| `docs/legal/gdpr-policy.md` + mirror | **APPROVED** — §§ 2.2, 3.3, 9 accurate and complete |
| `docs/legal/data-protection-disclosure.md` + mirror | **APPROVED subject to C6** (sub-processor-row columns) — non-blocking |
| `docs/legal/privacy-policy.md` + mirror | **REJECTED pending C1** — § 6 limbs (c) and (d) are false and controller-favourable, contradicted by §§ 4.4, 7 and 8.1 of the same file as amended by this PR |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | **APPROVED as computed** — all three pins verified; the `privacy-policy` pin must be recomputed after C1 |

This attestation is the v1 **internal** sign-off. All output remains draft material;
**external** counsel re-review is reserved for the frontmatter re-evaluation triggers —
most immediately the first arms-length user, the C-703/25 P ruling on the DPF, and the
finalisation of EDPB Guidelines 1/2024, on which the D9 necessity-first conclusion
partly (though not decisively) rests.
