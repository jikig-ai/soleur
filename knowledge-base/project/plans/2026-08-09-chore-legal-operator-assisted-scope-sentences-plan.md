---
title: "Scope sentences distinguishing plugin-local from operator-assisted processing across the published legal corpus"
type: chore
domain: legal
issue: 7347
branch: feat-one-shot-7347-dpd-operator-assisted-scope
lane: cross-domain
date: 2026-08-09
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tc_version_bump: false
publication_chain_fires: false
tier_classification: "Tier 1 (material) — new sub-processor disclosed in running text"
spec_source: "knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md §11 condition C5"
related:
  - knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md
  - knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/article-30-2-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/tc-version-bump-policy.md
  - knowledge-base/project/learnings/2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md
  - knowledge-base/project/learnings/2026-08-06-my-compliance-pr-breached-its-own-undertaking-and-every-gate-was-green.md
  - knowledge-base/project/learnings/2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md
  - knowledge-base/project/learnings/2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync.md
  - knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md
  - knowledge-base/project/learnings/2026-05-12-public-legal-doc-annotations-no-pr-numbers.md
---

# Scope sentences: plugin-local vs operator-assisted processing

> **DRAFT PLAN.** The legal text drafted here requires CLO attestation before merge. Not legal advice.

---

## 0. Plan-review amendments — BINDING, and they SUPERSEDE any conflicting text below

Six-reviewer panel, 2026-08-09. Full findings and evidence:
`knowledge-base/project/specs/feat-one-shot-7347-dpd-operator-assisted-scope/decision-challenges.md`.
Recorded here as deltas only — the rationale lives in that artifact and is **not** restated (two
copies of one rationale drift; this plan already carries an instance of that in §3.4 vs §7.3).

**A1 — §3.4 and AC-8b: strike the claim that DPD §3.1(b)/(d) are "literally true."** They are
falsified by `plugins/soleur/skills/trigger-cron/scripts/trigger.sh`, which ships inside the Plugin
and POSTs to `https://app.soleur.ai/api/internal/trigger-cron` (`ROUTE_URL` line 15, `curl -X POST`
lines 144-145) — independently verified, not taken on report. The **(a)-only cut stands**: those limbs
key on the infrastructure limb, which operator-assisted runs do not engage. What must not happen is a
Tier-1 CLO attestation certifying a sentence this plan elsewhere calls false. Reword to *"not the limb
this configuration breaks; falsified separately and tracked."* File a distinct issue for the
`trigger.sh` falsification — do NOT fix it here (different claim class, different cause).

**A2 — every limb clause states the INSTRUMENT, never a unilateral promise.** Breach (24h), audit
(annual / 30 days' notice), DSAR service levels (2/10 business days) and *"own machine and key at no
charge"* are carried **only** by the unexecuted, counsel-pending, single-counterparty annex. P-1 has
no DSAR/breach/audit limb by construction; PA-34(h) is controller-limb only and marked *"No
completeness guarantee."* Required form: *"the written instrument agreed before such a session
addresses X."* **No numeric SLA, no price term, no retention figure in published text.** AC-10 asserts
the FORM, not merely the trace. This is the highest-severity finding in the review.

**A3 — the pointer names its target document.** A bare "Section 2.1c" resolves locally-and-wrongly in
`gdpr-policy.md` (own `## 2`/`### 2.1`/`### 2.2`) and to nothing in `privacy-policy.md`. Use
"…described in the Data Protection Disclosure, Section 2.1c." No `#` fragment: `eleventy.config.js`
registers no markdown-it-anchor plugin, so published headings carry no `id`. Add an AC for
cross-document resolution.

**A4 — two pointer registers, not one string.** DPD/GDPR are third-person legal; `privacy-policy.md`
is second-person. One verbatim string is wrong-voiced at ~8 P sites while AC-2's count-grep still
passes. **12 strings, not 11.**

**A5 — pointer leads with the default case**, then the qualification. 20+ caveats each opening on the
exception read as hedging and make the common case harder to determine.

**A6 — G10: do NOT change "eleven" to "35".** `gdpr-policy.md:412` is followed by an enumerated list
of exactly 11. De-numeralise, or defer. Publishing the other 24 would narrate the incident (§7.2).

**A7 — Q3 settled: no PR refs in published legal text.** Plain-English + `§N.M`. The learning forbids
perpetuating the style; its symmetry claim is entry-level, not chain-level. Note §3.3's quote of the
precedent **elides `ref #7100`** — property (iv) restates as "dated parenthetical, date only, no ref."

**A8 — four missed sites, two of them critical.** DPD preamble (*"Because Soleur is not a data
processor (see Section 2), this is not a Data Processing Agreement under Article 28"* — first
substantive sentence, document-wide, cites the section §2.1c contradicts); `privacy-policy.md` §2 "Who
We Are" (*"Jikigai is the data controller…"* two headings above P3 saying processor); `gdpr-policy.md`
§2.1 ¶3 closed three-item controller list; DPD §4.2 preamble closed section list.

**A9 — cuts/narrowings.** Cut D4, P1, P8, G9. Narrow G7 to bullets 1 and 4 with a D3-style attachment
guard. Fold D6 into D5. **Drop the retention limb clause** — the pointer cures it. Limb clauses only
where the text denies a legal DUTY (D7, D9, D10, G5) or a TRANSFER (D8, P7, G6).

**A10 — AC-8 is unsatisfiable as written** (P2/P4 are widenings, G10 a correction, so `grep '^-'`
cannot yield only banner lines). Specify widenings as pure appends or scope the grep. Do not silently
relax it at implementation — that would take the non-retraction guard with it.

**A11 — AC-12 adds sector/nationality descriptors.** P-1(a)'s *"a French venture-exploration database
business"* is quasi-identifying with one alpha tester (`hr-third-party-content-grep-on-undertaking`).

**A12 — fix two stated mechanisms, keep their conclusions.** The hero regex misses the body line
because of the `:` in `**Last Updated:**`, not "first occurrence"; the mirror sentinel trips via
`test.each(DOCS)` → `loadMirror` ENOENT, not `expect(DOCS)` (which uses `arrayContaining`). Wrong
reasons mislead the next reader even when the action is right.

**A13 — §13, §14, §15, §16, §17, §18, §19 collapse to one-line "N/A — prose-only."**

**A14 — the `compliance-posture.md` C5-discharge row must state: C5 discharged; C2/C3 open; C5 is a
notice fix, not a remedy for the live tester.** Otherwise the condition set reads majority-complete
while the conditions that actually protect the tester stay open.

### Operator decisions, 2026-08-09 — these override §3.5 and §21

**A15 — AUP and Disclaimer are IN SCOPE. Only `terms-and-conditions.md` stays deferred.** The T&C
deferral keeps its mechanism (editing it engages `TC_VERSION` → forced re-acceptance for every
existing user, closing live sessions). AUP/Disclaimer had no mechanism — they were deferred by
adjacency, and AUP §5.3 *"You are the data controller"* is the same wrong-for-this-tester claim as PP
§4.2. Adds ~5 pointers, 2 mirrors, 2 `LEGAL_DOC_SHAS` entries. Sites: AUP §2, §5.1, §5.3, §6.1;
Disclaimer §4.1.

**A16 — deferral re-evaluation trigger tightened** to *the next operator-assisted run, or C9
(before tester #2), whichever is earlier.* Those are different events and the first arrives sooner.

**A17 — body-equivalence guard: measured, and activation is DEFERRED to a filed follow-up.** Measured
drift after the script's own normalisation — gdpr-policy 63 lines, privacy-policy 58, DPD 56, AUP 18,
disclaimer 2 (cosmetic), T&C 0. Substantive, not cosmetic, so the rule resolves to: **this PR syncs
its OWN edits to both surfaces correctly and does not resync pre-existing drift.** Do not add any doc
to `BODY_EQUIVALENCE_DOCS` here — it would fail on drift this PR did not cause.

**A18 — the pre-existing drift belongs to #7349 and its premise has been corrected there**
(comment on #7349, 2026-08-09). The published DPD mirror is missing **six** §2.3 processing-activity
disclosures — (p), (w), (x), (y), (z), (ad) — not the single (ad) that issue recorded; since the
mirror is the only published surface, those activities are undisclosed to data subjects. The AUP
mirror's divergences are substantive (prohibition reframed from acts to document properties; the
"another lawful basis" alternative dropped, making the published text stricter than the record; a
§4.2 cross-reference replaced with freestanding text; a share-link revocation consequence with no
canonical counterpart; a workspace-logo paragraph missing). **Out of scope here by operator decision**
— this PR must not silently fix or silently inherit it. Expect light file overlap in AUP/Disclaimer.

---

## 1. Overview

The published corpus describes **two** processing configurations: the Plugin running locally on the
User's machine (Soleur is neither controller nor processor), and the Web Platform on Jikigai
infrastructure. There is a **third**, described nowhere: **operator-assisted processing** — where, at
a User's request, Jikigai personnel run Soleur against that User's own content on a **Jikigai
machine**, under a **Jikigai-held credential**, or in a **Jikigai account**. There, Jikigai **is** an
Article 4(8) processor for the instructed work and an Article 4(7) controller for any
product-learning purpose of its own (Article 28(10) confirms the direction of travel).

This is live. An alpha tester's 2026-08-06 session ran in exactly that configuration. A reader of the
current published text draws a conclusion that is correct in general and wrong for them.

### 1.1 This is NOT a retraction — and the internal record already says so

> **(c) Therefore the published position is NOT falsified — it is INAPPLICABLE to the 2026-08-06
> configuration.** … It is **not** a finding that the disclosure is wrong, and **not** a finding that
> the disclosure should be retracted. It is equally **not** a finding that everything is published
> and fine.
> — determination §4(c)

Two further internal artifacts pre-authorise this exact framing, and the plan adopts their words:

> **Still out of scope — and note this is now a conclusion of the test, not an exception to it:** the
> locally-installed Soleur Claude Code plugin running **on the user's own machine, under the user's
> own API key, for the user's own purposes**… That is why `docs/legal/data-protection-disclosure.md`
> §"The Soleur Plugin Is Not a Data Processor" and `docs/legal/privacy-policy.md` §4.1 remain
> **accurate for the configuration they describe** — they are narrower than, not contradicted by, the
> operator-assisted case.
> — `article-30-register.md` §0 Controller Identification

> **The published "Plugin is not a data processor" position is not falsified — it is true within its
> scope and inapplicable to the operator-assisted configuration; a scope sentence … is filed
> separately.**
> — `compliance-posture.md`, the #7331 Active Item row

| Failure mode | What it looks like here | Guard |
|---|---|---|
| **Overshoot** | Deleting or weakening a plugin-local statement; adopting the `[Correction … **affirmatively false**]` bracket used for #7100 (that framing asserts falsity, which the internal record **expressly declines** here); over-retracting a claim that is still literally true (§3.4); publishing an incident narrative; asserting unverified transfer/retention facts | Every edit **additive** (AC-8). §7.3 must-not-assert table. §3.4 over-retraction guard. §7.2 no-incident-narration decision. |
| **Undershoot** | Editing only DPD §2.1; or only the four sites C5 names; or only `docs/legal/` while the **published** mirror stays stale; or reusing the existing carve-out wording *"automated jobs"*, which does not reach an operator-driven interactive run | §3 sweeps by claim → **29 sites**, not 4. §5.2: `docs/legal/` is published **nowhere**. §3.3 "automated jobs" gap. |

A third failure mode, specific to this repository and counterparty, is §7.1.

---

## 2. Research Reconciliation — issue body / C5 vs. verified reality

| Claim | Verified reality | Response |
|---|---|---|
| "mirror the separation already applied in `gdpr-policy.md`" | **The trap is real and it is worse than stated.** GDPR §2.2 bullets 1–2 *are* a correct BYOK-vs-Jikigai-keyed split; GDPR §2.1, ten lines above, is a **defect**. And the corpus's **best** fix shape is not in that file at all — it is `privacy-policy.md` §5.1, which adds a move GDPR §2.2 lacks: it **quotes back the specific sentence** that must not be over-read. | Adopt PP §5.1 as the canonical shape (§3.3). Treat GDPR §2.1 as a defect. |
| Both precedents are safe to copy | **No — both carve out only Jikigai's *"automated jobs"*.** An operator-driven interactive run on a workstation is **not** an automated job, so verbatim reuse would miss again — the exact failure the register's re-key note says escaped twice. | Every new block adds an explicit *operator-assisted / guided-onboarding* limb (§3.3). |
| C5 names four sites | **29 sites** in the three C5 files carry the claim class. A further ~10 sit in T&C, AUP and Disclaimer (§3.5). | §3.1–3.2. |
| DPD §3.1 "No data is transmitted to Soleur-operated servers" is falsified | **No — still literally true.** The Jikigai-keyed leg goes to **Anthropic**, not to a Jikigai server. The correct key is the register's **credential limb**, not the infrastructure limb. | §3.4 — an over-retraction guard, not an edit target for that specific clause. |
| "SOC 2 engagement within 90 days" fires on a new `docs/legal/` file | Substantially right, mechanism more specific: the `#4330` row fires on publishing the **customer DPA template**, and step (vi) keys on *"first **executed** DPA"* (that template's §10.3). | §5.1 — not fired, three grounds. |
| `legal-doc-consistency.test.ts` is the gate | It is **one of two**. The other, `tc-document-sha-guard`, is a required check with **no path filter**. | §5.2–5.3. |
| `tc-version-bump-policy.md` is T&C-scoped | True — **and its §"Non-T&C legal docs" imposes an unconditional SHA-refresh contract** on all three targets. | §5.3. |
| #7347 state | `OPEN`. Parent #7331 `CLOSED` (determination + annex + registers shipped in PR #7342). | Proceed. |

**Premise validation.** Every cited path resolves: determination (C5 at anchor `**C5 — REQUIRED,
separate change. Filed as #7347.**`), annex §5.1–§5.6, `article-30-register.md` PA-34/PA-35,
`article-30-2-register.md` P-1, `tc-version-bump-policy.md`, `legal-doc-consistency.test.ts`,
`check-tc-document-sha.sh`, `eleventy.config.js`, `compliance-posture.md` #4330 row. Nothing stale.

**One internal inconsistency to carry, not resolve here:** `article-30-register.md` §0 names privacy
policy **§4.1** as the safe one. C5 correctly identifies **§4.2** as the one that actually breaks
(§4.1 has a scope line; §4.2 has none). The register's citation is imprecise; this PR does not
rewrite it, but AC-11's traceability pass records the discrepancy for CLO.

---

## 3. The verified site list — swept by CLAIM, not by file

Per `2026-08-06-my-compliance-pr-breached-its-own-undertaking-and-every-gate-was-green.md` §3 —
*"index a retraction by **claim**, not by the files you happened to edit"* — recorded there as the
**third** instance of that defect, shipped by the commit fixing its first. This is the fourth
opportunity to make the mistake.

**The claim:** *"the Plugin runs on your machine, under your key, for your purposes; therefore
Jikigai has no access, transmits nothing, transfers nothing abroad, retains nothing, engages no
sub-processor, cannot answer a data-subject request, cannot detect a breach, owes no audit right,
and needs no lawful basis."*

Each limb of that claim recurs independently. C5 names four instances of two limbs. The sweep finds
**29** across the three C5 files.

### 3.1 In-scope sites — `docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md`

Legend: **S** = one of the three substantive blocks · **P** = the standard pointer sentence (§3.3) ·
**P+** = pointer plus one of four fixed limb clauses.

#### `data-protection-disclosure.md` — 12 sites

| # | Section | Limb that does not travel | Shape |
|---|---|---|---|
| **N1** | **new `### 2.1c Operator-Assisted Processing`** | — (the canonical definition all others point at) | **S** + only new heading |
| D1 | §2.1 *(C5-named)* | (d) *"Users authenticate directly with third-party services using their own API keys"*; (a) Art. 28 disapplication; closing *"neither a Controller nor a Processor"* | **S** (quote-back block) |
| D2 | §2.2 *User's Responsibilities as Controller* | sole-controllership assignment — contradicts PA-34 (Jikigai controller) | **P** |
| D3 | §3.1 *Plugin Architecture (Local-Only)* | (a) *"executes entirely within the User's local CLI environment"* — **see §3.4: limbs (b)/(d) are NOT edited** | **P** |
| D4 | §3.2 preamble | *"While Soleur does not process User data…"* | **P** |
| D5 | §4.1 *Plugin Sub-processors* *(C5-named)* | *"there are no Plugin-level Sub-processors to disclose under Article 28(2)"* — annex §5.1 asks the User to authorise Anthropic PBC for exactly these runs; P-1(a): *"Art. 28(2) is **not** satisfied"* | **S** (sub-processor block) |
| D6 | §4.3 preamble + Anthropic row | *"initiated and controlled by the User, not by Soleur"*; *"Direct customer of Anthropic"* | **P** |
| D7 | §5.1 *Local Data* | *"Soleur cannot fulfill such requests as it has no access to the data"* — annex §6 imposes Art. 28(3)(e) assistance duties | **P+** (DSAR clause) |
| D8 | §6.1 *Local Data* | *"No international data transfers are performed by Soleur"* — P-1(c) and PA-34(e) both record a **US transfer to Anthropic PBC** | **P+** (transfer clause) |
| D9 | §7.1 *Local Breaches* | *"cannot detect or report data breaches"*; *"Users are solely responsible"* — annex §8 puts Art. 33/34 processor duties on Jikigai | **P+** (breach clause) |
| D10 | §9.1 *Current Architecture* | *"audit rights under Article 28(3)(h) … are not applicable"* — annex §9 grants them | **P+** (audit clause) |
| D11 | §10.1 *Plugin Removal* (b) | *"no such data was ever transmitted to Soleur"* — falsified by the operator's local working tree and the 30-day Anthropic window | **P** |

> **Internal contradiction this closes:** §4.2's processor table **already names Anthropic PBC
> receiving content under a Jikigai-held key**, forty lines below §4.1's flat denial that any
> Plugin-level sub-processor exists. That is the sharpest inconsistency in the corpus.

#### `privacy-policy.md` — 8 sites

| # | Section | Limb | Shape |
|---|---|---|---|
| P1 | §3 *What the Plugin Does* | *"runs entirely on your local machine"* | **P** |
| P2 | §4.1 closing line | *"This section applies to the Plugin only. For … the Web Platform … see 4.7"* — enumerates **one** exception; becomes an incomplete list the moment P3 lands | widen |
| P3 | §4.2 *Data Processed Locally* *(C5-named)* | *"All of this data remains on your machine. We have no access to it."* — names the `knowledge-base/` tree and git artifacts, **exactly** what PA-35 records reading. **No scope line at all.** | **S** (plain-English block) |
| P4 | §5.1 *Anthropic Claude API* | already carries the corpus's best scope block — but scoped to *"automated jobs"* and to Jikigai-**as-controller**. Operator-assisted is the **inverse** (User controller, Jikigai processor) and is not reached | widen |
| P5 | §6 *Legal Basis* | *"no legal basis for processing is required for Plugin usage"* — PA-34/PA-35 both rely on Art. 6(1)(f) | **P** |
| P6 | §7 *Data Retention*, Plugin bullet | *"You control its retention and deletion entirely"* — annex §5.3: 30-day Anthropic window Jikigai **cannot compel earlier deletion** of | **P+** (retention clause) |
| P7 | §10 *International Data Transfers* | *"The Plugin operates locally and does not transfer data internationally"* | **P+** (transfer clause) |
| P8 | §11 *Security* | *"does not transmit data to our servers"*; note P-1(d)(5): the operator workstation is **not** encrypted at rest | **P** |

#### `gdpr-policy.md` — 9 sites

| # | Section | Limb | Shape |
|---|---|---|---|
| G1 | §2.1 *Soleur's Role* *(C5-named)* | *"does not collect, transmit, receive, or store any personal data on external servers"*; *"the Plugin does not act as a data processor within the meaning of Article 4(8)"* — sits **ten lines above** the file's own correct model in §2.2 | **S** (quote-back block) |
| G2 | §2.2 Anthropic bullets | two bullets: BYOK-plugin, and Jikigai-keyed-**as-controller**. Neither reaches Jikigai-keyed-**as-processor** | **S** (third bullet, file's own pattern) |
| G3 | §3.1 *Plugin Operation* | *"there is no personal data processing by Soleur that requires a lawful basis under Article 6"* | **P** |
| G4 | §4.1 *Data NOT Collected* | bullet *"Content generated through the plugin (knowledge-base files, brainstorms, plans, code)"* — PA-35 reads exactly this | **P** |
| G5 | §5.2 *Rights Exercisable Locally* | *"you have full and immediate control over its deletion"* | **P+** (DSAR clause) |
| G6 | §6 *International Data Transfers* | *"The Soleur Plugin itself does not transfer personal data internationally"* | **P+** (transfer clause) |
| G7 | §7.1 *Local Security* | *"All data remains within the user's filesystem security perimeter"*; *"API keys … never collected or stored by Soleur"* | **P** |
| G8 | §8.1 *Local Data* (retention) | *"Users have full control over the lifecycle of all locally stored artifacts"* | **P+** (retention clause) |
| G9 | §9 DPIA closing | *"This is your responsibility as the data controller for locally processed data"* | **P** |

> **G10 — adjacent accuracy fix, flagged for CLO (Q6).** §10 states *"The register documents eleven
> processing activities"*. The internal register now holds **35** plus a separate Art. 30(2)
> register. Not a scope claim, but a knowably-false published statement in a file being edited for
> accuracy. Recommend fixing; CLO to confirm inclusion.

### 3.2 Design: 5 substantive blocks + 1 reusable sentence + 4 fixed clauses

29 sites × bespoke prose = 29 novel claims, each needing independent traceability — and 29 chances to
write a new wrong sentence in a correction. Instead:

- **5 substantive blocks** carry all the substance: **N1** (DPD §2.1c, canonical), **D1** (DPD §2.1
  quote-back), **D5** (DPD §4.1 sub-processor), **P3** (PP §4.2 plain-English), **G1** (GDPR §2.1) +
  **G2** (GDPR §2.2 third bullet). Two widenings: **P2**, **P4**.
- **1 standard pointer sentence**, verbatim-identical at all remaining sites.
- **4 fixed limb clauses** — DSAR · transfer · breach/audit · retention — appended where the site's
  limb needs naming. Each drafted **once** and reused verbatim.

Result: **11 strings to verify**, not 29. And because the pointer is verbatim-identical, the
acceptance criteria become exact counts (`grep -c` the standard sentence per file), not 29 bespoke
greps — which also satisfies `cq-assert-anchor-not-bare-token`, since the pointer is a full sentence
no comment could accidentally produce.

### 3.3 The fix shape — canonical precedent, plus the gap it leaves

`docs/legal/privacy-policy.md` §5.1, verbatim:

> **This section describes the locally-installed Plugin only.** Jikigai separately operates its own
> automated jobs that send content to Anthropic PBC under a **Jikigai-held API key**, for which
> Jikigai is the controller and Anthropic is its processor. The three bullets above — in particular
> "Soleur does not intermediate, intercept, or store any data exchanged between you and Anthropic" —
> do **not** describe that processing and must not be read as covering it. See Section 4.4 …
> *(Clarification added 2026-07-31 …: the scoping was previously implicit, which left this section
> reading as a statement about all Anthropic egress, contradicting Section 4.4.)*

Four properties reused: **(i)** affirmative scope first, not a hedge; **(ii)** the specific sentence
that does not travel, **quoted inline**; **(iii)** a cross-reference to where the other configuration
*is* described; **(iv)** a dated parenthetical framed as a **scoping clarification**, never as a
correction-of-falsity.

**The gap both existing precedents leave — and the single most important thing to get right.** GDPR
§2.2 bullet 2 and PP §5.1 both scope the Jikigai-keyed path to Jikigai's *"own **automated jobs**"*,
enumerating Inngest, CI and community monitoring. An **operator-driven interactive run on a
workstation is not an automated job.** Copying either verbatim leaves operator-assisted runs outside
the carve-out — which is precisely the failure the register's re-key note records escaping **twice**.
Every block and the standard pointer must name an **operator-assisted / guided-onboarding** limb
explicitly, and P4 exists solely to widen §5.1 for this reason.

### 3.4 Over-retraction guard — the claim that must NOT be corrected

DPD §3.1(b) *"No data is transmitted to Soleur-operated servers"* and (d) *"The Plugin does not
establish network connections to Soleur-controlled endpoints"* remain **literally true** for
operator-assisted runs: the egress goes to **Anthropic**, not to a Jikigai server. Correcting them
would introduce a new false claim inside a correction — the documented failure mode, exactly.

The right key is the register's **credential limb**, not its infrastructure limb:

> **Credential limb** — the processing is effected under a **Jikigai-held credential or account** …
> **whoever's machine executes it**.

So D3's pointer attaches to §3.1**(a)** (*"executes entirely within the User's local CLI
environment"*), which is the limb that actually breaks, and says nothing about (b) or (d). **AC-8b**
asserts §3.1(b) and (d) survive verbatim and unqualified.

Two further true-claims not to disturb: the Plugin's no-telemetry statement (the defensible form is
*"no automatic or background telemetry; all egress is explicitly operator-invoked"* — this PR touches
none of it, per §7.3) and the cookie-policy statement (unaffected either way).

### 3.5 Out of scope — tracked, not silent

Agent-verified hits outside the three C5 files:

| File | Sites | Why deferred |
|---|---|---|
| `terms-and-conditions.md` | §4.1 *Local-First Architecture*, §4.2 *"through your own API keys and accounts"*, §8.1 *Local Data Storage* | **Editing it engages `TC_VERSION`** (§5.3) — a bump forces **every existing user to re-accept** on next page load and closes live WebSocket sessions. That is an operator-visible, user-visible event that must be taken deliberately, not ridden in on a chore PR. |
| `acceptable-use-policy.md` | §2 *"You retain full control over Plugin agent actions"*, §5.1, §5.3 *"You are the data controller"*, §6.1 | Grouped with the T&C decision they sit alongside; same responsibility-allocation claim family. |
| `disclaimer.md` | §4.1 *"The Platform operates locally on your system"* | Same. |

**One tracking issue filed in this PR** covering all three files. This is not a silent deferral:
`compliance-posture.md` records the adjacent T&C row as **STALE** with the note *"they are
UNTRACKED. Filed fresh rather than assumed covered."* — so filing closes a gap the corpus already
knows about. Re-evaluation criterion: **the next `TC_VERSION` bump for any reason**, or determination
condition **C9** (before onboarding tester #2), whichever is first.

### 3.6 Considered and deliberately NOT edited

| Site | Why |
|---|---|
| DPD §3.1(b), (d) | §3.4 — still true. Editing would be the overshoot. |
| DPD §4.2 Anthropic row | Preamble scopes it to *"where Jikigai acts as **Controller**"*. Operator-assisted-as-processor belongs in §4.1 (D5). |
| GDPR §11.2 breach scenarios | An omission in an illustrative list, not an assertion. Recording it would require narrating the workstation exposure — §7.2. |
| `cookie-policy.md` §3.1 | Factually unaffected: no cookies either way. |
| `corporate-cla.md`, `individual-cla.md` | Zero hits. |
| `article-30-register.md`, `compliance-posture.md` | Internal registers, already remediated in PR #7342. **Verified** (AC-11), not rewritten. |

---

## 4. Drafted text

Full drafts for all 29 sites live in `knowledge-base/project/specs/<branch>/scope-text-drafts.md`,
written in Phase 1 so every sentence is diffed against its supporting record **before** it reaches a
published file. Shapes of the load-bearing blocks:

**N1 — DPD `### 2.1c Operator-Assisted Processing`.** The machine/credential/purpose test as a
**three-row** table (plugin-local → neither; operator-assisted instructed limb → **processor**;
operator-assisted product-learning limb → **controller**), plus limbs (a)–(d): the processor role,
the controller role, the commitment that operator-assisted processing is carried out **only** under a
written Article 28(3) instrument agreed **before** it begins, and that it is **not the default** — a
User may require their own machine and key at no charge (annex §5.4), which removes Jikigai from the
chain entirely. Closes by stating §2.1 remains accurate as to plugin-local processing.

> The table deliberately does **not** restate §2.1b's Web Platform posture. §2.1b carries a
> team-workspace carve-out (Workspace Owner as controller, Jikigai as processor) that a summary row
> would flatten — inventing a new wrong claim inside the correction. Cross-referenced in prose only.

**D5 — DPD §4.1.** The existing sentence **kept verbatim and bound to plugin-local**, then a new
paragraph naming **Anthropic PBC, 548 Market Street, San Francisco, CA 94104, United States** as the
Sub-processor for operator-assisted runs — because the run is funded by a Jikigai-held key rather
than the User's own — and stating that Article 28(2) authorisation, the transfer mechanism and the
retention period are **obtained through** the written instrument agreed before the run. Closes with
annex §5.4's alternative: require your own key, and Anthropic is your own processor with no Jikigai
chain.

**P3 — PP §4.2.** Plain English, second person. Names the exception explicitly (*"Operator-assisted
sessions are different, and this is the exception to the sentence above"*), states that during such a
session we do read the `knowledge-base/` tree and git history and that content goes to our AI
provider under our credentials, states both roles, states the instrument-first commitment, and closes
*"we do not do this by default: unless you ask for it and agree the instrument, everything above
stands as written."*

**The standard pointer sentence** (verbatim at every **P** site; the four limb clauses append to it
at **P+** sites) is drafted once in Phase 1 and is the string AC-2 counts.

---

## 5. The three gates, answered

### 5.1 Gate 1 — PUBLICATION CHAIN: **does not fire.** Three independent grounds.

The chain is the `#4330` `DEFERRED-ARTIFACT-ONLY` row in `compliance-posture.md`, beginning *"On
trigger fire: (i) publish DPA template by copying to `docs/legal/data-processing-agreement.md` +
Eleventy mirror …"* and ending *"(vi) initiate SOC 2 engagement within 90 days per DPA §10.3
commitment."*

1. **No trigger condition has fired.** Verbatim: *(a) first B2B prospect asks "Do you have a DPA?";
   (b) first paying customer organization invites employees as Workspace Co-Members under
   `FLAG_TEAM_WORKSPACE_INVITE`; (c) first EU customer requests SCCs for non-EU sub-processors.* The
   alpha tester is a **free** tester who did not request a DPA — the Article 28(3) annex is
   **Jikigai-initiated remediation** under determination condition C2.
2. **The chain's subject is an artifact this PR does not touch:** the **customer DPA template**
   (`knowledge-base/legal/data-processing-agreement-template.md`). The SOC 2 step exists because
   **that template's §10.3** carries the commitment. This PR publishes no template.
3. **Step (vi) keys on "first *executed* DPA"**, not on a file existing. The alpha-tester annex is
   **unexecuted**, counsel-review pending (§14.3), and lives in `knowledge-base/legal/` deliberately.

**Therefore: no new file under `docs/legal/`.** Two mechanical consequences reinforce this
independently: `legal-doc-consistency.test.ts` derives its list from `readdirSync(docs/legal)` (a new
file instantly demands a mirror), and `check-tc-document-sha.sh` would demand a `LEGAL_DOC_SHAS`
entry and warn on the `EXPECTED_COUNT=9` mismatch. **AC-1** asserts the added-file set is empty.

> **Flagged, not actioned (CLO Q5):** whether *executing* the alpha-tester annex would itself
> constitute a "first executed DPA" for step (vi). That belongs to condition C2, not to this
> notice-scoping change.

### 5.2 Gate 2 — MIRROR PARITY: the mirror MUST carry the substantive prose, heading or not.

**The decisive fact.** `eleventy.config.js` sets `INPUT = "plugins/soleur/docs"`. `docs/legal/**` is
**not in the Eleventy input tree**, **not** in `deploy-docs.yml`'s path filter, and **no Next.js
route reads it** — the web platform links *out* to `https://soleur.ai/…`. **`docs/legal/*.md` is the
canonical source of record and is published nowhere.** The Eleventy mirror at
`plugins/soleur/docs/pages/legal/<doc>.md` (`permalink: legal/<doc>/`) **is** the separately-published,
publicly-readable document.

**Answer to the gate's explicit question: yes — the substantive scope text must appear in the mirror
regardless of the heading question.** Editing only `docs/legal/` would leave the flat denials
standing on the pages a reader actually reads. Heading parity would stay green while the issue stayed
unfixed. This is the undershoot mode in a form **no CI gate detects** — hence AC-4 and AC-16.

**What `legal-doc-consistency.test.ts` actually compares:**

| Test | Compares | Consequence |
|---|---|---|
| heading sequence, per doc | `extractHeadings` over `/^(##{1,2})\s+(.+?)\s*$/` → `expect(mirrorHeads).toEqual(sourceHeads)`. `##`/`###` only. **Prose bodies not compared.** | Only **N1** needs a mirror heading. The other 28 edits are invisible to this test — which is why AC-4 exists. |
| "Phase 6 additions land identically" | **Fixed historical allowlist** of 15 regexes asserted in both source and mirror | **No new sentinel entry needed.** Constraint: do not reword those 15 (DPD §2.3(n), R2/FreeTSA rows, GDPR §3.4 balancing test, PP §5.11). |
| Last-Updated parity | source body `==` mirror **body** `==` mirror **hero `<p>`** | **Nine date locations.** The hero regex `/Last Updated\s+(Date)/` is unanchored → matches the **first** occurrence (hero, line 11). Updating only the mirror body turns the suite red. |
| RCS jurisdiction | exactly one distinct `RCS <City>` across six files | Introduce no new `RCS` token. |

**Per-edit shape decision:**

| Edit | Shape | Mirror action |
|---|---|---|
| **N1** (DPD §2.1c) | **NEW `###` heading** — the only one | heading **and** body synced |
| D1–D11, P1–P8, G1–G9 (+G10) | **prose inside an existing section** | body synced verbatim; **no heading change** |

Exactly one heading, in one file. **All three mirrors receive prose.**

**Why N1 gets a heading** (challenge this at plan-review): DPD §2 is titled *Data Processing
Relationship Classification* and enumerates its relationships as headings (§2.1, §2.1b). There are
now three; omitting the third from the classification's own heading list hides it from the reader
scanning "which relationship am I in?". Twenty-eight prose sites need a stable cross-reference
anchor. It slots between §2.1b and §2.2, so **nothing renumbers**. The mirror is being edited anyway,
so the incremental cost is one line. Alternative in §9.

### 5.3 Gate 3 — T&C VERSION POLICY: **`TC_VERSION` bump NOT engaged.** SHA refresh IS mandatory.

**Not engaged:**

- `TC_VERSION` (`apps/web-platform/lib/legal/tc-version.ts`) governs `docs/legal/terms-and-conditions.md`
  **only**, which this PR does not touch (AC-9, §3.5).
- `tc-version-bump-policy.md` §"Non-T&C legal docs" covers all three targets explicitly: *"Unlike
  T&C, these documents are **notice / disclosure documents**, not contracts of adhesion. **No
  middleware reads a version constant for them** and there is **no WORM ledger** that persists
  user-acceptance of a specific revision."*
- The re-acceptance mechanic — middleware redirect on version mismatch, `recheckTcMidSession`
  closing live WebSocket sessions — therefore **cannot** be triggered. **No existing user is forced
  to re-accept anything.**
- Empirically confirmed: the three most recent legal-prose commits (`ad81dc81b` #6938, `c1056ec7a`
  #7110, `cb93c2948` #6568) each touched the same three canonicals + three mirrors +
  `legal-doc-shas.ts`, and **none** touched `tc-version.ts`.

**Mandatory instead — the unconditional SHA-refresh contract** (same policy file): *"Every edit to a
canonical at `docs/legal/<doc>.md` … MUST be paired with a refresh of the corresponding
`LEGAL_DOC_SHAS["<doc>"]` entry in the same PR. There is **NO** equivalent of the T&C
`TC_VERSION`-bump bypass; the SHA refresh is unconditional."* Enforced by `tc-document-sha-guard`, a
**required check with no path filter** — it runs on every PR regardless of what changed. Body
equivalence is **not** enforced for non-T&C docs (`BODY_EQUIVALENCE_DOCS=("terms-and-conditions")`),
which is a second reason AC-4 must carry the mirror-prose burden.

**Tier: 1 (material).** Required for Article 30 / counsel-ledger purposes even with no constant
moving. The dispositive example, verbatim: *"New sub-processor disclosed in the running text (in
addition to the Article 30 register update, which is required regardless)."* **D5** discloses
Anthropic PBC in the DPD's running text. **Tier 1 ⇒ CLO sign-off is the gating signal for merge.**

**Article 30 register:** no amendment expected — PA-34, PA-35 and P-1 shipped with the determination
and already record this processing. **AC-11 verifies rather than assumes**: every published sentence
must trace to a record limb. If a limb is uncarried, the register edit folds into this PR (policy
§Non-T&C step 5).

---

## 6. Files to Edit

**Mandatory — CI fails without these:**

| # | Path (relative to worktree root) | Change |
|---|---|---|
| 1 | `docs/legal/data-protection-disclosure.md` | N1 heading + D1–D11 prose; `**Last Updated:**` (line 12) |
| 2 | `docs/legal/privacy-policy.md` | P1–P8 prose; `**Last Updated:**` (line 11) |
| 3 | `docs/legal/gdpr-policy.md` | G1–G9 (+G10) prose; `**Last Updated:**` (line 13) |
| 4 | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | same prose + `### 2.1c`; body (line 21) **and** hero `<p>` (line 11) |
| 5 | `plugins/soleur/docs/pages/legal/privacy-policy.md` | same prose; body (line 20) **and** hero (line 11) |
| 6 | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | same prose; body (line 22) **and** hero (line 11) |
| 7 | `apps/web-platform/lib/legal/legal-doc-shas.ts` | refresh 3 entries — **last**, after prose is frozen (SHA is over raw bytes incl. frontmatter + trailing newline) |

**Convention-required (all three precedent commits did both):**

| # | Path | Change |
|---|---|---|
| 8 | `knowledge-base/legal/compliance-posture.md` | record the C5 discharge against the determination's condition set |
| 9 | `knowledge-base/legal/article-30-register.md` | **verify-only** by default; edit only if AC-11 finds an uncarried limb |
| 10 | `knowledge-base/legal/audits/2026-08-counsel-review-7347.md` | CLO attestation (Tier 1) — **new file under `knowledge-base/legal/audits/`, NOT `docs/legal/`** |

**Planning artifacts:** `knowledge-base/project/specs/feat-one-shot-7347-dpd-operator-assisted-scope/{tasks.md,scope-text-drafts.md}`.

**Deliberately NOT edited:** `apps/web-platform/lib/legal/tc-version.ts`;
`docs/legal/terms-and-conditions.md`; `docs/legal/acceptable-use-policy.md`;
`docs/legal/disclaimer.md` (all §3.5, tracked); `legal-doc-consistency.test.ts` (no new sentinel);
seed scripts.

## Files to Create

**No file under `docs/legal/`** (§5.1). Items 10 and the two spec artifacts are the only creations,
all outside `docs/legal/`.

---

## 7. Risks & Sharp Edges

### 7.1 This PR could breach the very undertaking it describes

`gh repo view` confirms `jikig-ai/soleur` is **PUBLIC** with **2 forks**. Annex **§7.5**: *"Customer
content shall not be published, quoted or reproduced in **any Jikigai commit**, issue, digest, case
study or marketing material."*

Three days ago PR #7342 — the PR that *landed that clause* — committed the counterparty's private
repository filenames into this public repo. Every gate was green and correctly so: the AC was scoped
to *"no individual may be named"*, and filenames are not personal data.
(`hr-third-party-content-grep-on-undertaking`.)

**Note the specific hazard here:** record **P-1(a)** in the internal Art. 30(2) register names the
counterparty's repository slug. That is correct for an internal register. It must not travel into any
artifact this PR writes.

**Hard constraint on every artifact — published text, mirrors, plan, spec, tasks, commit messages,
PR body:** describe the **configuration** generically ("a User", "your repository"). Name **no**
counterparty, **no** repository slug, **no** filename, **no** repository content, **no** date of any
specific session. Narrate **no** incident (§7.2). **AC-12** greps the whole diff before PR-ready.

This plan file is written to that constraint.

### 7.2 Why the published text states the standing position and narrates no incident

1. C5 asks for *"a **scope sentence** … distinguishing plugin-local processing from operator-assisted
   processing"* and says *"**Not a retraction** (§4)"*.
2. Determination §4: *"the remedy is an instrument for the uncovered configuration, **not** an edit
   to a statement that is accurate about the thing it describes."*
3. §7.1 — narrating the event in a public notice is the republication risk.
4. Accountability lives where Article 5(2) puts it: PA-34, PA-35, P-1 and the determination, all
   committed. The **counterparty-facing** disclosure is condition **C3**, a bilateral communication.

**Consequence for tense:** commitments are written **forward** (*"operator-assisted processing is
carried out only under a written instrument agreed beforehand"*), never as a claim about history.
Determination C1 — a behavioural control *"effective immediately"* — is what makes the present-tense
form accurate. **CLO Q2.**

### 7.3 Claims this PR must NOT assert

| Tempting sentence | Why it must not be published |
|---|---|
| "Transfers to Anthropic PBC are covered by the EU-US DPF, SCCs Modules 2+3 and the UK IDTA." | Determination **C6 is OPEN**: *"Confirm this account is on **Commercial** Terms, not Consumer Terms. The entire §C auto-incorporation analysis rests on it, and it has not been verified"* — recorded as *"a premise not a formality"*. **P-1(c) and PA-34(e) both carry it as an open condition.** Publish the mechanism as *agreed per-engagement in the instrument*, never as settled fact. Note the annex §5.2 states it flatly — that is the annex's exposure (unexecuted, counsel-review pending), not a licence to repeat it publicly. |
| "Anthropic retains content for 30 days." | True of Anthropic's *default* Commercial Terms while `zero_retention_amendment: unsigned`, but inherits C6's premise and is a moving state. Refer to the instrument. |
| "Jikigai has an Article 28(3) instrument in place with its alpha testers." | The annex is **unexecuted**. Forward commitment only. |
| "The Plugin has no phone-home path." | Falsified by the determination's own egress scan (`trigger-cron/scripts/trigger.sh` POSTs to a Jikigai host; `plugin.json` declares four remote MCP servers). Defensible form: *"no automatic or background telemetry; all egress is explicitly operator-invoked."* **This PR touches no telemetry claim** and must not strengthen one. |
| Any `[Correction … **affirmatively false**]` bracket | That is the #7100 framing for a claim that **was** false. Here the internal record **expressly declines** to assert falsity (§1.1). Use the PP §5.1 *scoping-clarification* framing. |

**AC-10** requires every new sentence to cite its supporting record and rejects any whose only
support is plan-authored inference.

### 7.4 Mechanical traps (verified against the working tree)

- **`lint-encryption-posture.py` R5 anchors.** `scripts/encryption-posture-ledger.json` pins
  `docs/legal/privacy-policy.md:Encrypted workspace storage` and
  `docs/legal/data-protection-disclosure.md:TLS for data in transit`. The rule fails if an anchor
  stops resolving, **and** if `/LUKS|encrypt/i` appears within **±300 characters** of an anchor whose
  mechanism is `plaintext-exception`. → Do not reword those phrases; keep "encrypt" away from them.
  **Live risk:** P8 (PP §11 *Security*) is near the privacy-policy anchor and the temptation is to
  mention encryption at rest. Do not. (CI job `encryption-posture` is advisory but must not break.)
- **Nine date locations, not three** (§5.2).
- **The SHA is over raw bytes** — regenerate `legal-doc-shas.ts` **after** the last prose byte
  changes, **including in review-fix commits**. A review-fix that edits prose and forgets the SHA
  turns a required check red.
- **`tc-document-sha-guard` has no path filter** and is a required check.
- **Full suite, not touched-file tests.** `legal-doc-consistency.test.ts` is only caught by the full
  run, and a background runner has reported exit 0 with a real failure. Grep the log for `FAIL`/`× `.
- **Runner:** `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts`.
  Not `bun test`; not `npm run -w` (the repo root declares no `workspaces` field).
- **`legal-doc-cross-document-gate.yml`** is the reverse direction (DSAR surface → legal docs); this
  PR touches no surface file, so it passes trivially.

### 7.5 Convention tension to settle at review, not silently

`2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` says public Last-Updated annotations must
**not** embed issue/PR numbers. All three target banners currently do (`(Ref #6588 (branch) — …)`,
`(Ref #7100 (branch) — …)`), symmetrically across canonical and mirror, established by three
consecutive precedent commits. **Recommendation:** match the established symmetric convention —
deviating in one entry of a chain recreates exactly the canonical/mirror asymmetry the learning was
written to prevent. **CLO Q3**; if overturned, it is a one-line change.

---

## 8. Implementation Phases

### Phase 0 — Preconditions (no writes)

0.1 `git rebase origin/main` (the legal file-set moves on `main` often).
0.2 Re-read C5 at its content anchor, not a line number (`cq-cite-content-anchor-not-line-number`).
0.3 Extract verbatim: PA-34 and PA-35 limbs (a)–(h); P-1 limbs (a)–(d) + Status; annex §5.1–§5.6, §6,
    §8, §9. **These are the only admissible support for a new published sentence.**
0.4 Baseline green: `legal-doc-consistency.test.ts`; `check-tc-document-sha.sh`.

### Phase 1 — Draft against records (writes only to `specs/`)

1.1 Write `specs/<branch>/scope-text-drafts.md`. Structure: **the 11 strings first** (5 substantive
    blocks, 2 widenings, the standard pointer, the 4 limb clauses), then a 29-row table mapping each
    site → which string it receives → the record limb supporting it → the existing sentence it
    scopes, quoted.
1.2 Self-review every string against §7.3's must-not-assert table, §3.4's over-retraction guard, and
    §3.3's "automated jobs" gap.
1.3 Confirm no string names a counterparty, slug, filename, or session date (§7.1).

### Phase 2 — Canonical edits (`docs/legal/`)

2.1 **DPD:** insert `### 2.1c` after §2.1b; D1 into §2.1; D5 rewrite of §4.1 (**append and bind — do
    not delete** the existing sentence); pointer/limb strings into D2, D3 *(attaching to §3.1(a)
    only — §3.4)*, D4, D6–D11.
2.2 **PP:** P3 block into §4.2; widen P2 and P4; pointer/limb strings into P1, P5–P8.
2.3 **GDPR:** G1 into §2.1; G2 third bullet into §2.2; pointer/limb strings into G3–G9; G10 if CLO
    confirms.
2.4 Update the three `**Last Updated:**` banners to **August 9, 2026** with a Tier-1 classification
    phrase — *"**scoping clarification; no change to the substance of processing, and no retraction
    of any prior statement.**"* — and prepend the existing entry to the `Previous:` chain.

### Phase 3 — Mirror sync (`plugins/soleur/docs/pages/legal/`) — the substantive publication step

3.1 Port **every** Phase-2 prose block verbatim to the corresponding mirror. This is what a reader
    sees (§5.2); no CI gate checks it.
3.2 Port the `### 2.1c` heading to the DPD mirror.
3.3 Update **six** mirror dates: body + hero, per file.
3.4 Region-by-region canonical↔mirror diff for each of the 30 edits.

### Phase 4 — Pins, registers, verification

4.1 `sha256sum docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md` → paste into
    `legal-doc-shas.ts`. **Last.**
4.2 AC-11 register traceability; fold a register edit in only if a limb is uncarried.
4.3 `compliance-posture.md` — record the C5 discharge.
4.4 Full suite (§7.4 runner); grep the log for `FAIL`.
4.5 `bash apps/web-platform/scripts/check-tc-document-sha.sh`.
4.6 Run the §11 acceptance block end to end.

### Phase 5 — Gates

5.1 `/soleur:gdpr-gate` against the diff (§12 — mandatory).
5.2 `/soleur:review` including `user-impact-reviewer` (threshold = single-user incident) + CLO.
5.3 File the §3.5 tracking issue (T&C + AUP + Disclaimer) and the §13 C4 issue.
5.4 CLO attestation → `knowledge-base/legal/audits/2026-08-counsel-review-7347.md`, written **against
    the final branch head** and re-verified after any rebase or force-push (an attestation older than
    the branch's last history rewrite is withdrawn until re-verified).
5.5 §7.1 third-party-content grep before `gh pr ready`.

---

## 9. Alternatives Considered

| Alternative | Rejected because |
|---|---|
| **Edit only DPD §2.1** (the issue's literal ask) | Undershoot. Leaves §4.1's flat denial standing against the annex's own sub-processor authorisation, and leaves PP §4.2 — the sentence the determination says *"actually breaks"* — untouched. |
| **Edit only the four C5 sites** | Reproduces the *"a retraction reaches the twins you remember, not the twins that exist"* defect, whose **third** instance shipped three days ago in the commit fixing its first. Also leaves DPD §6.1 ("no international transfers"), §7.1 (breach), §9.1 (audit) and §5.1 (DSAR) asserting things the annex directly contradicts. |
| **Bespoke prose at all 29 sites** | 29 novel claims = 29 chances to write a new wrong sentence inside a correction, and 29 bespoke ACs. §3.2's 11-string design collapses it to 11 verifiable strings and exact-count ACs. |
| **Also fix T&C / AUP / Disclaimer in this PR** | T&C engages `TC_VERSION` → forces **every existing user to re-accept** and closes live sessions. That is a deliberate operator decision, not a chore-PR side effect. Tracked, not silent (§3.5). |
| **Publish a new `docs/legal/operator-assisted-processing.md`** | Fires the §5.1 chain analysis and its SOC 2 step — the highest-cost error available. Also demands a mirror, a SHA entry and an `EXPECTED_COUNT` bump. |
| **No new heading; inline §2.1c into §2.1** | Saves exactly one mirror heading line, and the mirror is being edited anyway. Costs: the third processing relationship is invisible in a document whose §2 *is* the relationship classification, and 28 prose sites lose a stable anchor. **Recommended for plan-review to challenge**; reversal is mechanical. |
| **Retract the plugin-local statements** | Overshoot. Determination §4(a): they *"remain TRUE within [their] scope"*. The register and compliance-posture both say the same (§1.1). |
| **Also "correct" DPD §3.1(b)/(d)** | §3.4 — they are still literally true. This would be an over-retraction: a new false claim introduced by the correction. |
| **Narrate the 2026-08-06 session publicly** | §7.1 + §7.2. Counterparty disclosure is condition **C3**, tracked separately. |
| **Fold the whole C4 model gap in** | §13. Different artifact class with its own test surface; deferred with a tracking issue. |

---

## 10. Open questions for CLO (answered before merge, not after)

- **Q1.** Do PA-34/PA-35/P-1 already carry every limb asserted publicly, or is an
  `article-30-register.md` amendment required? AC-11 produces the evidence.
- **Q2.** Confirm the published text states the **standing position** and narrates no incident
  (§7.2), and that forward-tense commitments are the correct register.
- **Q3.** Settle §7.5 — `Ref #7347` (established symmetric convention) vs. plain-English (the
  2026-05-12 learning).
- **Q4.** Confirm §7.3: do not assert the Anthropic transfer mechanism or retention window as settled
  fact while determination **C6** is open — including where the annex §5.2 states it flatly.
- **Q5.** For the condition set, **not this PR**: would executing the alpha-tester annex constitute a
  "first executed DPA" for the `#4330` step (vi) SOC 2 trigger?
- **Q6.** Include G10 (GDPR §10's stale *"eleven processing activities"* against 35 + the Art. 30(2)
  register) as an adjacent accuracy fix, or defer?
- **Q7.** `article-30-register.md` §0 cites privacy policy **§4.1** as the safe one; C5 identifies
  **§4.2** as the one that breaks. Correct the register's citation, or leave it?

---

## 11. Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-1 — No new file under `docs/legal/`.** `git diff --name-status --diff-filter=A origin/main...HEAD -- docs/legal/` returns zero lines. The publication chain does not fire.
- [ ] **AC-2 — All 29 sites carry scope text.** The standard pointer sentence appears exactly N times per canonical (counts fixed in Phase 1 from the §3.1 tables); each of the 5 substantive blocks and 2 widenings is present in its named section, asserted by a region-scoped grep anchored on a phrase spanning no punctuation boundary — never a bare token (`cq-assert-anchor-not-bare-token`). Mutation-tested: deleting any one block must fail this AC.
- [ ] **AC-3 — Every site distinguishes the two configurations,** and no block reuses *"automated jobs"* as the sole descriptor of the Jikigai-keyed path (§3.3). Each names an operator-assisted / guided-onboarding limb and states Jikigai's role (processor; controller for the product-learning limb).
- [ ] **AC-4 — Mirror carries the substantive prose.** For each of the 30 edits, the same block is present in the corresponding `plugins/soleur/docs/pages/legal/` file. **No CI gate checks this** (§5.2, §5.3) — verified by per-edit region diff, not by the heading test passing.
- [ ] **AC-5 — DPD §4.1 no longer stands unqualified.** `Anthropic PBC` present within §4.1's region **and** the original sentence preserved verbatim but bound to plugin-local. Both halves asserted.
- [ ] **AC-6 — `legal-doc-consistency.test.ts` green**, then the **full** suite, with the log grepped for `FAIL`/`× ` (never the exit code alone).
- [ ] **AC-7 — `check-tc-document-sha.sh` green**; all three `LEGAL_DOC_SHAS` entries equal `sha256sum` of their canonical.
- [ ] **AC-8 — No retraction (non-deletion).** Every sentence in the protected set is present **verbatim** at HEAD: DPD §2.1(a)–(d) + its "Therefore" line, DPD §4.1 sentence 1, DPD §5.1/§6.1/§7.1/§9.1/§10.1(b), PP §4.1 bullets + §4.2 "All of this data remains on your machine…", GDPR §2.1 ¶1–2, §4.1 bullets, §7.1 bullets. The diff is **additive** at every site: `git diff -U0 origin/main...HEAD -- docs/legal/ | grep '^-' | grep -v '^---'` yields only `**Last Updated:**` banner lines.
- [ ] **AC-8b — Over-retraction guard.** DPD §3.1**(b)** and **(d)** are present verbatim **and carry no new qualifier** — they remain true (§3.4). The pointer at D3 attaches to §3.1(a) only. No new sentence anywhere asserts that Jikigai operates a server receiving Plugin data.
- [ ] **AC-9 — `TC_VERSION` untouched.** `git diff origin/main...HEAD -- apps/web-platform/lib/legal/tc-version.ts docs/legal/terms-and-conditions.md` is empty. PR body states **Tier 1**, that no bump is engaged, and why.
- [ ] **AC-10 — Every new sentence traces to a record.** `scope-text-drafts.md` maps all 11 strings to PA-34 / PA-35 / P-1(a)–(d) / annex §5.x, §6, §8, §9 / determination §2–§5. Any sentence supported only by plan-authored inference is cut. **No sentence from §7.3's table appears in the diff**, including any `affirmatively false` bracket.
- [ ] **AC-11 — Article 30 traceability.** No new Processing Activity introduced; every publicly asserted limb is carried by an existing record, or the register is amended here. Evidence recorded for CLO Q1 and Q7.
- [ ] **AC-12 — Third-party-content grep** (`hr-third-party-content-grep-on-undertaking`). Over the **whole** diff plus PR body and commit messages: zero occurrences of the counterparty repository slug (it appears in P-1(a) — do not carry it forward), any fixture filename from the determination's §7 residual, or any specific session date. Repo confirmed public with forks.
- [ ] **AC-13 — Mechanical traps clear.** Both `disclosed_as` anchor phrases resolve unchanged with no `LUKS|encrypt` within ±300 chars (P8 is the live risk); no new `RCS <City>` token; the 15 Phase-6 sentinel fragments unreworded; nine date locations consistent.
- [ ] **AC-14 — CLO attestation** at `knowledge-base/legal/audits/2026-08-counsel-review-7347.md`, written against the **final** branch head, Q1–Q7 answered. Re-verified after any rebase or force-push.
- [ ] **AC-15 — `/soleur:gdpr-gate` run**, findings folded in or explicitly scoped out.
- [ ] **AC-16 — Deferrals tracked.** The §3.5 issue (T&C + AUP + Disclaimer) and the §13 C4 issue exist and are referenced from the PR body with `Refs #NNNN`.

### Post-merge (automated — no operator step)

- [ ] **AC-17 — The published pages actually changed.** After `deploy-docs.yml` completes on `main`, `curl -s https://soleur.ai/legal/data-protection-disclosure/ | grep -c 'Operator-Assisted'` ≥ 1, and the same for the privacy-policy and gdpr-policy pages against their own scope phrase. **This is the only check that proves the reader-visible defect is fixed.** Run in-session via `gh run watch` + `curl`; no SSH, no dashboard.

---

## 12. GDPR / Compliance Gate (Phase 2.7)

**Invoked — mandatory.** Two independent triggers: the change is *about* regulated-data disclosures
under Articles 4, 6, 28, 30, 33 and 34; and the plan declares `brand-survival threshold: single-user
incident` (expansion trigger (b)). Runs at Phase 5.1 against the diff plus §4's drafts. Critical
findings escalate to `compliance-posture.md` Active Items plus a `compliance/critical` issue.
Precedent says to expect fold-ins the research agents structurally cannot produce
(`2026-05-16-plan-time-ac-discipline-prod-synthetic-users-gdpr-gate-value.md`, class (C)).

---

## 13. Architecture Decision (ADR/C4)

**No ADR.** No ownership or tenancy boundary moves, no new substrate, integration pattern, resolver
or trust boundary; no existing ADR is reversed or extended. The configuration already exists and was
decided by the determination.

### C4 — enumerated against all three model files, not grepped for the feature's own noun

Read in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

| Category | Enumerated | Modeled? |
|---|---|---|
| **External human actors** | The **User/customer as controller**, for whom Jikigai is an Article 28 processor during an operator-assisted run | **NO.** `founder` is the Owner (not `#external`). `betaContact` is `#external` but is the **inverse** relationship — *"the operator captures notes **about** this third party"*, Jikigai-as-controller over the beta-CRM, *"no direct access to the store"*. `emailSender`/`contributor` unrelated. **Genuine gap.** |
| **External systems / vendors** | Anthropic PBC | **YES** — `anthropic = system "Anthropic API" { #external }`. No addition. |
| **Containers / data stores** | Operator's local working tree + the Anthropic API leg. P-1(d)(2): *"no Jikigai server-side persistence of controller content"* | No change. |
| **Access relationships that change** | The **credential** is the entire legal discriminator. `engine -> anthropic` is qualified *"LLM calls with **BYOK keys**"*; **`claude -> anthropic "LLM calls"` carries no credential qualifier at all** | **Description defect** on the exact axis that decides controller-vs-processor. |
| `spec.c4` | `actor`/`system`/`container`/`database`/`component`; tags `external`/`selfhosted` | Sufficient either way. No change. |
| `views.c4` | `context` and `containers` each `include` an explicit actor list (`founder, emailSender, betaContact, contributor`) | A new actor must be added to **both** include lists or it does not render. |

**Disposition — split:**

- **Fold in (recommended):** qualify the `claude -> anthropic` edge description with the credential
  discriminator. One line; no new element; no `views.c4` change; no `c4-count-parity` impact; directly
  on this issue's thesis.
- **Defer with a tracking issue:** the missing `#external` customer-as-controller actor, its edges,
  and the two `views.c4` include-list additions. Different artifact class with its own test surface
  (`c4-code-syntax`, `c4-render`, `c4-count-parity`); natural owner is the determination's follow-up
  set. Re-evaluation criterion: determination **C9** — before onboarding tester #2.

**Recommended for plan-review to challenge** in either direction.

---

## 14. Observability

Pure-docs change: no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or
`plugins/*/scripts/`; no new infrastructure. Phase 2.9's full schema does not apply. One real surface
remains — the Eleventy build and Pages deploy, the **only** path by which this change reaches a
reader (§5.2):

```yaml
liveness_signal:
  what: "deploy-docs.yml completes on main and the three /legal/ pages serve the new scope text"
  cadence: "once, on merge (push to main, path plugins/soleur/docs/**)"
  alert_target: "the workflow's own failure status; verified in-session via gh run watch"
  configured_in: ".github/workflows/deploy-docs.yml"
error_reporting:
  destination: "GitHub Actions run status (deploy-docs.yml)"
  fail_loud: true
failure_modes:
  - mode: "Eleventy build fails on the edited mirror markdown"
    detection: "deploy-docs.yml build step non-zero"
    alert_route: "gh run view --log-failed"
  - mode: "Build and deploy succeed but mirror prose was never synced — the published page still carries the unqualified denial while every CI gate is green (the undershoot mode, section 5.2)"
    detection: "AC-17 curl of the three live pages for their scope phrase"
    alert_route: "in-session; a zero count is a merge-day defect, remediated by a follow-up prose commit"
logs:
  where: "GitHub Actions run logs for deploy-docs.yml"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "curl -s https://soleur.ai/legal/data-protection-disclosure/ | grep -c 'Operator-Assisted'"
  expected_output: ">= 1"
```

No SSH. No dashboard step (`hr-no-dashboard-eyeball-pull-data-yourself`). **Soak follow-through:**
none — no acceptance criterion is time-gated.

---

## 15. Encryption Posture

**Skipped — detection does not fire.** No `.tf`, no `supabase/migrations/*.sql`, no `cloud-init*.yml`,
no `docker-compose*.yml`; no persistent store and no new cross-component connection. The only
encryption-adjacent coupling is the `lint-encryption-posture.py` **anchor-preservation** constraint in
§7.4 — a "do not disturb", not a new posture.

## 16. Infrastructure (IaC)

**Skipped — no infrastructure introduced.** No server, service, cron, vendor account, DNS record, TLS
cert, secret or firewall rule. No SSH step, no secret-manager write step, and no vendor-dashboard step
appears anywhere in this plan. <!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## 17. Hypotheses

**Not applicable.** No network/SSH trigger patterns; nothing is being diagnosed. The defect is a
documented, confirmed scope gap.

---

## 18. User-Brand Impact

**If this lands broken, the user experiences:** a live alpha tester opens
`https://soleur.ai/legal/privacy-policy/` §4.2, reads *"All of this data remains on your machine. We
have no access to it."*, and concludes that the hands-on session in which the operator ran Soleur
against their repository under a Jikigai API key needed no data-processing instrument, exposed their
content to no sub-processor, gave them no audit right, and left them solely responsible for breach
notification. All of that is wrong for them, and the page that produced it is the page Jikigai
publishes as its privacy notice. The specific broken-landing modes: **(i)** mirror prose not synced —
green CI, unchanged public page; **(ii)** DPD §4.1's flat denial left standing against the very
sub-processor authorisation the annex asks that tester to sign; **(iii)** a new block that reuses
*"automated jobs"* and therefore still does not reach them.

**If this leaks, the user's data is exposed via:** the inverse of the usual direction — **the diff
itself**. This PR commits text *about* a counterparty's content into a **public** repo with 2 forks
while annex §7.5 forbids publishing, quoting or reproducing that content in any Jikigai commit; and
the internal record it draws on (P-1(a)) names the counterparty's repository slug. Vectors: published
prose, plan/spec artifacts, commit messages, PR body. This exact breach shipped three days ago in PR
#7342 with every gate green (§7.1). Mitigated by AC-12 and the §7.1/§7.2 drafting constraints.

**Brand-survival threshold: `single-user incident`.** One tester, one wrong conclusion drawn from a
published notice, inside a live regulated relationship with a materialised Article 28 gap.

Consequences: `requires_cpo_signoff: true`; CPO sign-off required before `/work`;
`user-impact-reviewer` at review time; CLO attestation separately required by Tier 1 (§5.3).

---

## 19. Domain Review

**Domains relevant:** Legal (primary), Product, Engineering.

### Legal (CLO) — BLOCKING
Invoked at Phase 5.2. Tier 1 makes CLO sign-off the gating signal for merge. Must answer Q1–Q7 (§10).

### Product (CPO) — ADVISORY
The mechanical UI-surface override does **not** fire: changed paths are `docs/legal/*.md`,
`plugins/soleur/docs/pages/legal/*.md` and one `.ts` constants file. None matches the glob superset in
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` (`components/**`,
`app/**/page.tsx`, `pages/**`, `routes/**`, `**/*.{njk,html,vue,svelte,astro}`) — the mirrors are
`.md` consumed by a `.njk` **layout** that is not edited. The term list excludes *"Pure copy or style
tweaks with no structural/layout change"* and *"Docs / knowledge-base … changes"*. **No `.pen`
wireframe required**; `wg-ui-feature-requires-pen-wireframe` does not engage.

CPO input is still required for the `single-user incident` sign-off (§18), on substance not design.

**Skipped specialists:** `ux-design-lead` — **not applicable** (no UI surface; the gate does not
engage). `copywriter` — recommended for one pass over the **P3** block only, which is the sole
reader-facing plain-English prose in the change.

**Pencil available:** N/A (no UI surface).

### Engineering (CTO)
Two mechanical gates and one publication path (§5.2–§5.3, §7.4). No architectural decision (§13).

---

## 20. Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` searched for each planned path
(`docs/legal/data-protection-disclosure.md`, `docs/legal/privacy-policy.md`,
`docs/legal/gdpr-policy.md`, `plugins/soleur/docs/pages/legal`, `legal-doc-shas.ts`,
`legal-doc-consistency.test.ts`) — zero matches.

---

## 21. Deferral Tracking

| Deferred | Why | Re-evaluation criterion | Tracking |
|---|---|---|---|
| Scope sentences in `terms-and-conditions.md` (§4.1, §4.2, §8.1), `acceptable-use-policy.md` (§2, §5.1, §5.3, §6.1), `disclaimer.md` (§4.1) | T&C engages `TC_VERSION` → forced re-acceptance for every existing user; a deliberate operator decision. AUP/Disclaimer grouped with it (§3.5) | The next `TC_VERSION` bump for any reason, or determination **C9** (before tester #2) | Issue filed in Phase 5.3 (`domain/legal`, `type/chore`, `priority/p2-medium`). Note `compliance-posture.md` records the adjacent T&C row as STALE and these as **UNTRACKED** — filing closes a known gap |
| C4 `#external` customer-as-controller actor + edges + `views.c4` include-list additions (§13) | Different artifact class with its own test surface; natural owner is the determination's follow-up set | Determination **C9** | Issue filed in Phase 5.3 (`domain/engineering`, `type/chore`) |
| Counterparty-facing sub-processor authorisation + retention disclosure | Determination condition **C3**; bilateral, not a public notice (§7.2) | On execution of the Article 28(3) instrument (C2) | Already in the determination's condition set |
| Anthropic Commercial-vs-Consumer Terms confirmation | Determination condition **C6**; a premise this PR must therefore not assert (§7.3) | Operator action | Already tracked (`anthropic.md` item 4) |
