---
title: "CLO review — published-corpus reconciliation to Art. 30 PA-7 (#7624)"
type: clo-attestation
date: 2026-08-20
issue: 7624
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: RULINGS-ISSUED
tier_classification: "Tier 1 (material) — a third-country transfer newly disclosed in running text, a retention characterisation corrected from ceiling to floor, and an Art. 6(1)(f) balancing test re-derived rather than patched"
semver: "TC_VERSION unchanged — no T&C body edit in scope (tc_version_bump: false)"
brand_survival_threshold: single-user incident
governing_record: "knowledge-base/legal/article-30-register.md — Processing Activity 7, cells (d), (e), (f), (g)"
written_against: "the Art. 30 register at 28612e8cd (PA-7 amendment, #7622) and the published corpus at that commit"
scope_boundary: "Corrects what the corpus SAYS. Does NOT decide what the processing SHOULD BE — the proportionality of indefinite retention is carved out to #7668. Art. 30 PA-7 §(c) field omissions remain at #7625 and are untouched."
re_evaluation_triggers:
  - "First arms-length (non-Jikigai) contributor signs the CLA — the first data subject of PA-7 who is not the operator, and the first reader of these disclosures with an adverse interest."
  - "Any migration of `soleur-cla-evidence` to Cloudflare's EU jurisdiction tier. Per PA-7 §(e) this would change the residency position and the `iam.tf` token resource-strings, but would NOT on its own convert the cell to a no-transfer posture — that additionally requires the contracting entity and access path to cease being US-established. Any corpus edit made on the strength of such a migration must be re-reviewed against that distinction."
  - "Any change to `comment_body` capture on the evidence record — the only unbounded free-text field, and the one whose Art. 9 special-category determination is under separate review at #7625."
  - "Adoption of a retention ceiling at #7668 — would move gdpr-policy §3.4 limb (2), privacy-policy §§4.5/5.11/7, both CLA instruments §0, and PA-7 §(f)+(g) together."
  - "Execution of the first tenant DPA under `data-processing-agreement-template.md`. The §11.1 correction below carries no amendment tail today because `tenant-dpa-register.md` Rows is empty; that cost rises discontinuously at first execution."
  - "Any revision that reverts the FreeTSA rows to REMOVAL rather than re-characterisation — two cross-references (contradiction-register:133, DPA template:334) become false in the same commit."
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/legal/tc-version-bump-policy.md
  - knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md
  - knowledge-base/legal/audits/2026-08-counsel-review-7349.md
---

# CLO review — published-corpus reconciliation to Art. 30 PA-7 (#7624)

**Standing caveat.** This is the v1 internal counsel-review attestation under the tenant-zero
posture. It is **not** a substitute for external counsel, which is reserved for the
re-evaluation triggers in the frontmatter above (first arms-length contributor, EEA-out,
regulated industry, Art. 9 processing).

**Read the prose, not the hashes.** Per #7349: two byte-identical copies of a wrong sentence
pass all five legal CI gates. Every replacement below was read as prose against the governing
register cell before it shipped.

## CLO Advisory — Binding Rulings

Obtained at plan time from the `soleur:legal:clo` agent against PA-7 §§(d)(e)(f)(g). **Overall
disposition: PROCEED — no fork requires external counsel before this PR lands.** These rulings
are inputs to `/work`, not review comments. Where this section and any earlier section of the
plan disagree, **this section governs**.

`/work` Phase 0 must first write this advisory verbatim to
`knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`
(planning is confined to `knowledge-base/project/{plans,specs}/`, so the audit file is a /work
deliverable, not a plan artefact).

### Rulings the CLO independently verified before deciding

| Claim | Status |
|---|---|
| `chat-attachments` is Supabase Storage, not R2 | **Confirmed independently** — `apps/web-platform/scripts/dsar-export-oversize.sh:104`; and `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts:8` cites *"migration 045 — storage.objects FOR ALL policy on chat-attachments"* |
| Last-Updated drift magnitude | **Measured, and larger than this plan first characterised.** privacy-policy canonical 32,612 chars vs mirror 23,587, first divergence at char 3,258; gdpr-policy 28,939 vs 21,917 at 10,963; DPD 32,510 vs 26,300 at 10,480. The mirror is **not** a condensation — it stops at an earlier PR and carries a materially different correction history. |
| The register's own §(e) note mis-cites a section | **The register is imprecise:** it says "gdpr-policy §3.3 processor bullet"; the bullet is at `gdpr-policy.md:62`, which is **§2.2**. Corrected in the discharge block below. |

### Fork 1 — transfer disclosure wording: REPLACE BOTH; SPLIT the privacy-policy bullet in two

A single bullet labelled "Storage location" cannot carry an Art. 13(1)(f) disclosure, because
the reader's question ("where are my bytes?") and the legal question ("who can reach them, under
whose law?") have different answers here. The correction must also **disclaim** localisation
rather than merely omit it — `weur` still appears in the bucket name, and silence would let a
reader reconstruct the same wrong inference.

**1A — `docs/legal/privacy-policy.md` §5.11.** Replace the single `- **Storage location:**`
bullet with these two (§5.11 uses ASCII `--`; matched):

> `- **Storage location:** Cloudflare R2 bucket `soleur-cla-evidence`. The bucket is created with the location hint `WEUR` (Western Europe), which expresses a preference for where Cloudflare places the objects. It is **not** a jurisdictional restriction -- the bucket sits on Cloudflare's default, non-EU-tier jurisdiction. We do not rely on data localisation as a safeguard for this archive, and you should not read `weur` as one.`
>
> `- **International data transfer:** This archive **does involve a transfer to a third country**. Cloudflare, Inc. is established in the United States and subject to United States jurisdiction, so making the evidence records available to it is a transfer under Chapter V GDPR irrespective of where the objects physically rest. The safeguards relied on are Cloudflare's certification under the **EU-US Data Privacy Framework**, the **Standard Contractual Clauses**, and **Global CBPR** certification -- the same instrument as the Section 5.8 CDN role. To obtain a copy of the safeguards relied on, write to <legal@jikigai.com>. *(Corrected 2026-08-20, ref #7624: this section previously stated "Intra-EU processing -- no third-country transfer for archive contents at rest". That was wrong on both limbs -- the `weur` hint is not a jurisdiction, and the transfer arises from the identity of the processor, not the location of the bytes.)*`

**1B — `docs/legal/gdpr-policy.md` §3.4 closing sentence** (row A10). Replace the whole sentence:

> `The off-site archive **does** involve a third-country transfer. Cloudflare, Inc. is established in the United States, and making the evidence records available to a US-established processor is a transfer under Chapter V GDPR irrespective of where the objects rest. The bucket's `WEUR` location hint is a placement preference, not a jurisdictional restriction, and is not relied on as a safeguard. The transfer is made under Cloudflare's **EU-US Data Privacy Framework** certification, the **Standard Contractual Clauses**, and **Global CBPR** certification -- the same instrument as the Cloudflare row in Section 2.2. FreeTSA is operated from DE and receives no personal data, so it is not a recipient and no transfer arises on that path. See DPD §6.4 and Privacy Policy §5.11 for sub-processor details. *(Corrected 2026-08-20, ref #7624: this paragraph previously stated that the archive introduced no third-country transfer, on the strength of the `weur` location hint.)*`

**1C — reconciliation template for the remaining Class-A sites.** Three moves at every site:
(i) never let `weur`/`EU region` stand unqualified; (ii) name US + DPF/SCCs/CBPR wherever the
site discusses transfer; (iii) correct retention to indefinite wherever the site states ten years.

| Row | Site | Move |
|---|---|---|
| A1 | `privacy-policy.md:120` | `(soleur-cla-evidence, region weur -- Western Europe)` → `(soleur-cla-evidence; the WEUR location hint is a placement preference, not a jurisdictional restriction -- see Section 5.11)` |
| A2/C1 | `privacy-policy.md:122` | apply the Fork-2 retention wording; drop `, EU region` |
| C2 | `privacy-policy.md:389` §5.11 Retention bullet | `Ten (10) years on the bucket` → `**Indefinite.** The bucket carries a ten (10) year write-once retention **floor** -- a minimum period during which an object cannot be deleted. Nothing removes it when that period expires.` |
| **G1 (NEW)** | `privacy-policy.md:386` §5.11 Object Lock bullet | **A defect the inventory missed.** "Governance mode" is **S3 Object Lock** terminology; §(g) records a Cloudflare **R2 Lock Rule** (`cla-evidence-10yr-retention`, Age condition). Replace `Governance mode with a ten (10) year retention floor` → `Cloudflare R2 Lock Rule (age-based, ten (10) year retention floor)`. Same defect class; **fix in this PR.** |
| A7 | `gdpr-policy.md:62` §2.2 | `in region weur (Western Europe)` → `. Cloudflare, Inc. is established in the **United States**; the bucket's `WEUR` location hint is a placement preference, not a jurisdictional restriction. Transfers under DPF + SCCs + CBPR -- the same instrument as the CDN row above` |
| A8 | `gdpr-policy.md:96` | `region weur (Western Europe), under R2 Lock Rules` → `held by Cloudflare, Inc. (United States) under R2 Lock Rules` |
| A4/B1/C3 | `data-protection-disclosure.md:172` | same two moves on the opening and Retention; closing line per Fork 3 |
| A5 | `data-protection-disclosure.md:264` §4.2 R2 row | Activity cell: strip `region weur`; add `held by Cloudflare, Inc. (US) -- DPF + SCCs + CBPR, see §6.4` |
| A6 | `data-protection-disclosure.md:359` §6.4 | replace `EU region (weur -- Western Europe). … Intra-EU processing for archive contents at rest.` with the US/DPF framing per 1B |

Every mirror moves byte-identically in the same commit.

### Fork 2 — the Art. 6(1)(f) balancing test: RE-DERIVATION REQUIRED, IN SCOPE

**A factual edit is not available.** Both load-bearing facts of limb (2) are false in the
direction that made the test *easier to pass*. "The bucket region is EU (`weur`)" was offered as
a data-minimisation mitigation; the truth is not that the mitigation is absent but that its
opposite obtains. "Retention is hard-set at 10 years rather than indefinite" is the premise the
whole proportionality argument is built on: the published limb proves ten years is calibrated to
the longest applicable limitation period, which is a valid argument about a *bounded* period and
says nothing about an unbounded one. Swapping the words would leave the conclusion standing on
premises that no longer support it **while looking re-assessed** — the #7349 failure mode moved
from the gate layer into the reasoning layer, and worse than the defect being fixed, because a
reader (or a supervisory authority) would take the dated marker as evidence the assessment had
been re-run.

**It is in scope because the register supplies every fact the re-derivation needs:** §(f) gives
the necessity rationale (the grant is irrevocable and has no end date), §(g) gives the operable
Art. 17 override that keeps erasure real under a WORM floor, §(e) gives the transfer safeguard.
What the register does **not** contain — and what the CLO declined to manufacture — is a
judgement that indefinite retention is proportionate versus a bounded alternative. That is a
decision about the processing itself, and it is **carved out and tracked, not deferred silently**.

**2A — preamble replacement** (row C4; keeps the pinned sentinel string verbatim):

> `**Three-part balancing test (off-site evidence archive):** The off-site archive captures the verbatim sign-comment body and the document-hash at sign-time in addition to the public-branch fields. A separate balancing test is required because (i) the data set is materially broader, (ii) retention on the archive is **indefinite**, and (iii) the archive is held by a processor established in the United States, so it involves a transfer to a third country. *(Re-derived 2026-08-20, ref #7624. The version published before that date rested this test on two facts that were not true of the processing: that retention was hard-set at ten years, and that the bucket was jurisdictionally EU. Both are corrected below, and the test has been re-run on the corrected facts rather than patched around them.)*`

**2B — limb (2) full replacement** (rows A9 + C5):

> `- **(2) Necessity and proportionality.** **Retention on the archive is indefinite, not ten years.** The ten-year figure that appeared here before 2026-08-20 described the R2 Lock Rule (`maxAgeSeconds = 315360000`), which is a **minimum** period during which an object cannot be deleted -- a floor that guarantees the record survives, not a ceiling that removes it. Nothing deletes an object at ten years. Necessity for indefinite retention rests on the irrevocability of the grant: the licence granted by the CLA has no end date, so the evidence that it was granted must remain available for as long as the grant can be relied on or disputed. The statutory limitation periods that the earlier text cited (10 years under German civil law, BGB §195 + §199; 6 years under the UK Limitation Act 1980 §5/§9; 30 years under French Code civil art. 2227) explain why the ten-year **floor** is not set shorter; they do not establish that indefinite retention is proportionate, and they are no longer offered as if they did. **Whether a retention ceiling should be adopted is under active re-assessment** at issue [#7668]; this Policy will be updated if one is adopted. The data minimisation tests: (a) only data essential to prove that the signer agreed to *this specific text of the CLA at this point in time* is captured (comment body + doc-hash); (b) the R2 Lock Rule is age-based rather than an absolute immutability lock, so the administrator override described in sub-bullet (3) remains available for Article 17 erasure cases -- the floor is enforced but is not absolute; (c) the monthly RFC 3161 timestamp protects only the bucket-state manifest hash -- FreeTSA never sees any contributor data; (d) the bypass-record path for allowlisted bot accounts uses a sanitised key (`dependabot-bot`) so no `[bot]` substring appears in object keys, and `github-actions[bot]` (DB-id 41898282) is filtered out entirely before any write. **The location of the bucket is not offered as a mitigation.** The `WEUR` location hint expresses a placement preference and is not a jurisdictional restriction; the transfer safeguard is the DPF / SCC / CBPR mechanism described at the end of this section, and no limb of this test rests on the data being held in the EEA.`

Note what happened to old sub-bullet (b): it welded the false "bucket region is EU" claim onto a
true one about age-based rules permitting override. The replacement **keeps the true half and
discards the false half** rather than deleting the sub-bullet — the override availability is a
genuine mitigation and the test needs it.

**2C — limb (3) addition.** Append after the constructive-notice sentence:

> `Those notices now disclose both the indefinite retention and the transfer to a processor established in the United States; before 2026-08-20 they did not, and a contributor who read them would have been told the opposite on both points.`

**Limb (1) needs NO change** — it already says "age-based retention floor, 10 years", which is
correct. Do not touch it.

**2D — the tracking issue is BLOCKING ON PUBLISH.** File it before pushing and substitute the
real number for `[#7668]` in 2B. Title: *"legal: proportionality re-assessment of indefinite
retention on the CLA evidence archive (Art. 30 PA-7 §(f))"*. Body states it as a controller
decision: given irrevocable grants, is indefinite retention proportionate, or should a ceiling be
adopted with a corresponding expiry path through `gdpr-override.sh`? Route to CLO with CTO input
on whether an expiry path is buildable against the Lock Rule floor. **The PR must not merge
carrying the `#7668` placeholder.**

### Fork 3 — FreeTSA: RE-CHARACTERISE ALL THREE IN PLACE, REMOVE NONE; §2.2 unchanged

The register recorded the exclusion "explicitly so a future reader does not have to re-derive"
it. Deleting the corpus entries defeats that twice: once by discarding the disclosure, once by
leaving a reader who finds `.github/workflows/cla-evidence-timestamp.yml` to conclude there is an
*undisclosed* recipient. Over-disclosure of a non-processor is not a transparency violation;
naming FreeTSA a **sub-processor** is, because it asserts an Art. 28 relationship that does not
exist. Keeping both pinned sentinels green is a convenience, not the reason.

**3(a) — DPD §2.3(n) closing line (row B1), the genuinely wrong one.** Replace:

> `**Sub-processors:** Cloudflare Inc (R2 object custody) -- a processor established in the **United States**; see Section 6.4 for the transfer mechanism. **FreeTSA is not a sub-processor and not a recipient:** the monthly exchange transmits a SHA-256 digest of an aggregate bucket-state manifest and receives a signed token in return. The digest is taken over a whole manifest file rather than over any individual's identifier, so it cannot be used to single out a data subject, and no signature record, identity or timestamp payload leaves the bucket. The dependency is disclosed here for completeness, not because Article 28 applies to it. *(Corrected 2026-08-20, ref #7624: this line previously named FreeTSA as a sub-processor and described the R2 bucket as being in an EU region. Neither was accurate.)*`

**3(b) — DPD §4.2 table row (row B2).** A row inside a processor table whose own last cell says
"processing falls outside Article 28 scope" is self-contradicting. **Keep it in place** — moving
it risks the drift gate's reordering rule for no legal gain — and re-frame the cells:

| Cell | Replacement |
|---|---|
| Processor | `FreeTSA ([freetsa.org](https://freetsa.org)) -- RFC 3161 Time Stamp Authority -- **NOT an Article 28 processor; listed for completeness**` |
| Processing Activity | unchanged |
| Data Processed | `SHA-256 hash of the aggregate bucket-state manifest. Not personal data within Article 4(1): the pre-image is a whole manifest file, not an individual identifier, so no data subject can be singled out from it.` |
| Legal Basis | `Not applicable -- FreeTSA processes no personal data. The Article 6(1)(f) basis at Section 2.3(n) covers our own act of generating and storing the timestamp, not any processing by FreeTSA.` |
| Sub-processor List | `None. No DPA exists or is required: FreeTSA receives no personal data, so Article 28 does not apply.` |

The Processor cell retains `FreeTSA` … `RFC 3161 Time Stamp Authority`, so
`/FreeTSA.*RFC 3161 Time Stamp Authority/` stays green. Add immediately below the table, before
the existing "This disclosure is consistent with…" line:

> `The FreeTSA row above is included so that the dependency is visible. FreeTSA is **not** an Article 28 processor and is not counted as a sub-processor anywhere in this disclosure.`

**3(c) — DPD §6.4 bullet (row B3).** The single defect is that "Intra-EU processing" frames this
as a transfer that happens to land in the EU, when no transfer arises at all. Leaving DE-location
load-bearing is a trap: if FreeTSA relocated, a future reader would think the analysis changed.

> `- **FreeTSA (RFC 3161 Time Stamp Authority):** **No transfer arises on this path and FreeTSA is not a recipient.** The service receives only a SHA-256 hash of the monthly bucket-state manifest, taken over a whole manifest file rather than over any individual's identifier, so no data subject can be singled out from it. That input is not personal data within the meaning of Article 4(1) GDPR, so Chapter V is not engaged and no DPA is required or available. The service is operated from Germany; that is recorded as a fact about the operator and is **not** relied on as a transfer safeguard.`

**3(d) — `gdpr-policy.md` §2.2 FreeTSA bullet (rows B4/B4′): NO CHANGE.** It already states the
exclusion, the ground, and why the dependency is disclosed — the register's posture, expressed
better than the DPD manages. Editing a correct line in a legal corpus is a net-negative trade:
every edited line becomes a new drift-ratchet surface and a new chance to introduce error.

### Fork 4 — scope

**4(a) — `individual-cla.md:26` / `corporate-cla.md:26` (rows C6/C7): RULED IN.** This is the
strongest Art. 13 case in the whole set. Art. 13 requires the information to be given "at the
time when personal data are obtained"; §0 of the CLA **is** that moment, and it is the only text
in the corpus the data subject demonstrably reads, because assent to it is the act that creates
the record. Understating retention at the point of assent is materially worse than understating
it in a policy the signer may never open. Excluding it would also leave the corrected corpus
self-inconsistent (PP §4.5 indefinite, CLA §0 ten years).

**The doc-hash objection is not a reason to exclude; it is the design working.** The scheme
hashes the CLA text *at the PR base SHA* precisely so each signature binds to the text as it
stood for that signer. Existing signatures keep their own hash and remain provable; future
signatures bind to the corrected text. The alternative — continuing to obtain assent under a
false retention statement to keep a hash constant — is not available at any price.

`individual-cla.md` §0, replacing the sentence beginning `The signature record is retained for ten (10) years…`:

> `Your signature record is retained **indefinitely**. The off-site evidence archive carries a ten (10) year write-once retention **floor** -- a minimum period during which the record cannot be deleted -- and nothing removes it when that period expires. Retention is indefinite because the licence You grant is irrevocable and has no end date, so the evidence that You granted it must remain available for as long as the grant can be relied on or disputed. You may request deletion of Your signature record; the grant survives the deletion. *(Corrected 2026-08-20, ref #7624: this sentence previously stated a ten (10) year retention period, which understated it -- ten years is a floor, not a ceiling.)*`

`corporate-cla.md` §0, same position:

> `The signature record is retained **indefinitely**. The off-site evidence archive carries a ten (10) year write-once retention **floor** -- a minimum period during which the record cannot be deleted -- and nothing removes it when that period expires. Retention is indefinite because the licence You grant is irrevocable and has no end date, so the evidence that You granted it must remain available for as long as the grant can be relied on or disputed. Deletion of the signature record may be requested; the grant survives the deletion. *(Corrected 2026-08-20, ref #7624: this sentence previously stated a ten (10) year retention period, which understated it -- ten years is a floor, not a ceiling.)*`

Both CLAs are in `NO_BODY_LAST_UPDATED`, so Fork 5(a) does not bite. Both pinned CLA sentinels
are untouched. **Re-pin `legal-doc-shas.ts` for both.** *Recommended, not required:* make the
following sentence's cross-reference specific — `see the Privacy Policy §§4.5 and 5.11 and the
GDPR Policy §3.4 for retention, international transfer, and your rights` — a valid layered notice
under WP29 transparency guidance, now that the linked layer is accurate.

**4(b) — `data-processing-agreement-template.md` §11.1 + Schedule 2: RULED IN, highest severity
in Fork 4.** §11.1 is categorically different from everything else here: it is not a disclosure
to a data subject, it is a **contractual representation to a counterparty** that "no transfer
mechanism under Chapter V GDPR is required" for Cloudflare R2. A wrong disclosure misinforms and
is cured by correction; **a wrong warranty is breachable, by the counterparty who relied on it.**

**The empty tenant register is the argument for fixing it NOW, not for deferring.** No executed
instrument carries the representation, so this is a pure template edit with zero amendment tail
and zero counterparty notification. That cost rises discontinuously the moment the first tenant
DPA is executed, when the same fix becomes an amendment to a live contract requiring consent.
The file also lives outside `docs/legal/**`, so **none of the five CI gates fire on it** and it
has no mirror — marginal CI cost nil.

`§11.1` replacement:

> `**§11.1 EU-only sub-processors.** Where an Authorized Sub-processor processes Customer Data exclusively within the European Economic Area ("EEA"), no transfer mechanism under Chapter V GDPR is required. Per Schedule 2, the following sub-processors are EEA-only: Supabase (EU project), Hetzner (EEA data centres — Helsinki, Finland and Falkenstein, Germany; same account and signed AVV), Sentry's primary region (DE), Better Stack (CZ controller → DE `eu-fsn-3` cluster), Buttondown (newsletter, EU), Plausible Analytics (EU-hosted). **Cloudflare R2 is not EEA-only and is not covered by this paragraph.** Cloudflare, Inc. is established in the United States, so making Customer Data available to it is a transfer under Chapter V irrespective of the bucket's location hint; it is covered by §11.2 on the same DPF + SCCs + CBPR instrument as the Cloudflare CDN role. *(Corrected 2026-08-20, ref #7624: Cloudflare R2 was previously listed here as EEA-only on the strength of the `weur` location hint, which is a placement preference and not a jurisdictional restriction. No Customer had executed a DPA under this template at the date of correction, so no executed instrument carries the superseded representation.)*`

**`§11.2` covered-list addition** — append to the "Sub-processors covered by §11.2:" sentence:

> `, **Cloudflare Inc (R2 object custody — CLA evidence archive)** (US — EU-US DPF + SCCs + CBPR; same instrument as the Cloudflare CDN role)`

**Schedule 2 — SPLIT the mis-attributed row (rows E2 + E3).** Replace the single Cloudflare R2 row at line 317 with:

> `| Cloudflare R2 (Cloudflare Inc) | Object storage — CLA evidence archive (`soleur-cla-evidence`) | CLA evidence records (GitHub username, signature timestamp, sign-comment body, PR-of-record, doc-hash, capture method) | **US (EU-US DPF + SCCs + CBPR).** The bucket carries a `WEUR` location hint, which is a placement preference and not a jurisdictional restriction; the bucket sits on Cloudflare's default jurisdiction | [cloudflare.com/cloudflare-customer-dpa](https://www.cloudflare.com/cloudflare-customer-dpa/) (same instrument as CDN row) |`

and fold `chat-attachments/*` into the **Supabase Inc** row where it belongs — Activity cell →
`Web Platform auth + database + object storage (`chat-attachments/*`, `dsar-exports/*` — Supabase
Storage)`; Data-processed cell → append `; user-uploaded chat attachments`; Location cell
unchanged (`EU (eu-west-1 Ireland)`). Add beneath Schedule 2's Web Platform table:

> `*(Corrected 2026-08-20, ref #7624: `chat-attachments/*` was previously attributed to Cloudflare R2. It is a **Supabase Storage** bucket -- `storage.objects`, migration 045, served from `${SUPABASE_URL}/storage/v1/object/...` -- and is therefore EEA-resident under the Supabase row. Cloudflare R2 holds the CLA evidence archive only. The mis-attribution had the effect of placing customer attachments in a row that this Schedule described as EU-resident on a false basis; both halves of that error are corrected here.)*`

**Row E4 (NEW) — a third site in the same file, RULED IN.** Line 378, §8 Availability + DR:
`Cloudflare R2 multi-region for object storage (`weur`)` → `Cloudflare R2 for the CLA evidence
archive (bucket location hint `WEUR` -- a placement preference, not a jurisdictional restriction;
see §11.1)`. That line also implies R2 multi-region availability for customer attachments, which
the corrected attribution shows is not a property this estate has.

### Fork 5 — publication hygiene

**5(a) — Last Updated: DO NOT BUMP.** Three independent grounds, any one sufficient.

1. **The drift is not cosmetic and it was measured** (see the verification table above). Making
   the two surfaces byte-identical is either publishing ~9 KB of previously-unpublished
   correction history to the live page, or deleting correction history from the canonical
   record. The first is a substantive publication decision; the second degrades the audit trail
   the register's amendment convention exists to protect. Neither belongs as a side effect of a
   factual-correction PR.
2. **The legal premise is wrong.** Art. 12(1) requires accuracy, concision, transparency and
   intelligibility. It does not prescribe a document-level revision stamp, and a bumped header
   date is a poor transparency instrument — it tells the reader *something* changed somewhere in
   a 600-line document. This corpus already has a better instrument, used at PP §4.4 and DPD
   §4.2, and **every replacement specified above carries one**: a dated marker at the corrected
   passage naming what the text used to say. That reaches the reader where they actually are.
3. **The cost is real and the benefit is zero.** A bump is three coordinated edits (canonical
   body, mirror body, mirror hero), two of them on the ratcheted line.

If a document-level stamp is later wanted it is **its own PR**: deliberately drift-reduce the
line, make the editorial call about correction history explicitly, and use
`SOLEUR_LEGAL_DRIFT_ACCEPT` only if the ratchet still objects. Do not smuggle that decision here.

**5(b) — PP §10 and GDPR §6 entries (rows D1/D2): REQUIRED by Art. 13(1)(f). Add both.**
Art. 13(1)(f) requires the transfer, the safeguards, **and the means to obtain a copy of them**.
Both sections are structured as enumerations, and an enumeration that omits a transfer represents
by the completeness of its own form that the list *is* the set of transfers. The existing
"Cloudflare: Global CDN" entry makes it worse: a reader who sees Cloudflare named and
characterised as CDN reasonably concludes the CDN role is the whole of Cloudflare's involvement.
Neither section currently offers the copy-request route required by the closing words of
Art. 13(1)(f) for *any* of its bullets; the new entries carry it.

**Placement ruling.** The CLA evidence archive is a **repository-interaction** surface, not a Web
Platform surface. Do **not** place it under "For the Web Platform:" / "Web Platform
(app.soleur.ai):" — place it adjacent to the GitHub/repository material in each document.

`docs/legal/privacy-policy.md` §10 — new paragraph immediately after the existing
`For the Docs Site and repository interactions, GitHub may transfer data internationally…`
paragraph, matching the loose-paragraph style of its neighbours:

> `For the off-site **CLA evidence archive** (see Sections 4.5 and 5.11), evidence records are held by **Cloudflare, Inc.**, which is established in the United States. This is a transfer to a third country irrespective of the bucket's `WEUR` location hint, which is a placement preference and not a jurisdictional restriction and is not relied on as a safeguard. The transfer is governed by the EU-US Data Privacy Framework (DPF), Standard Contractual Clauses (SCCs), and Global CBPR certification -- the same instrument as the Cloudflare CDN entry above. To obtain a copy of the safeguards relied on, write to <legal@jikigai.com>. See [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/). *(Added 2026-08-20, ref #7624: this transfer was not previously listed in this section.)*`

`docs/legal/gdpr-policy.md` §6 — new bullet under **Other services:**, immediately after the
GitHub Pages / GitHub bullet:

> `- **Cloudflare R2 (CLA evidence archive):** The off-site CLA evidence archive `soleur-cla-evidence` (Section 3.4) is held by **Cloudflare, Inc.**, established in the **United States**. This is a **Chapter V transfer** irrespective of the bucket's `WEUR` location hint, which is a placement preference and not a jurisdictional restriction and is not relied on as a safeguard. Transfer via the **EU-US Data Privacy Framework (DPF)**, **Standard Contractual Clauses (SCCs)**, and **Global CBPR** certification -- the same instrument as the Cloudflare CDN row above. DPA self-executing via the Cloudflare Self-Serve Subscription Agreement (verified 2026-03-19). A copy of the safeguards relied on is available on request to <legal@jikigai.com>. See [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/). *(Added 2026-08-20, ref #7624: this transfer was not previously listed in this section.)*`

**Caution for /work:** on the mirror surfaces these two additions must use `/legal/<slug>/` link
form, and the `<legal@jikigai.com>` autolink must match whatever autolink convention the
surrounding bullets already use on each surface — check before writing.

### Register §(e) note (row F1): UPDATE IT IN THIS PR — but APPEND, never edit

The bracketed note is a live conflict-of-authority rule ("Until that lands, this cell governs").
Once the corpus is corrected that rule is spent, and a note saying the published corpus is wrong
when it is right is itself a currency defect. The register's amendment convention is **additive**:
supersede in place, never silently repair. So **do not delete or edit the existing block** —
append a discharge. The edit is confined to §(e) and touches no part of §(c).

> `**[2026-08-20 DIVERGENCE DISCHARGED (#7624): the corpus correction landed.** The published surfaces named in the block above now record the transfer to Cloudflare Inc (US) under DPF + SCCs + CBPR and no longer offer the `weur` location hint as a safeguard. `docs/legal/privacy-policy.md` §10 and `docs/legal/gdpr-policy.md` §6 gained the Art. 13(1)(f) transfer entry that neither had ever carried — an omission the divergence note above did not identify. **One citation in that note was imprecise and is corrected here:** the gdpr-policy processor bullet is at §2.2, not §3.3. **Two further divergences were found by enumeration during the correction and are also discharged:** `docs/legal/individual-cla.md` and `docs/legal/corporate-cla.md` §0 each stated a ten-year retention period against this register's §(f) **Indefinite**, in the instrument the data subject actually assents to at collection time; and `knowledge-base/legal/data-processing-agreement-template.md` §11.1 represented Cloudflare R2 to counterparties as EEA-only requiring no Chapter V mechanism — a contractual representation rather than a disclosure. No tenant DPA had been executed under that template at the date of correction (`tenant-dpa-register.md` Rows table empty), so the correction carries no amendment tail; the same Schedule 2 row also mis-attributed the Supabase Storage bucket `chat-attachments/*` to Cloudflare R2, and that attribution is corrected to Supabase. **The preceding CORPUS DIVERGENCE block is preserved unaltered as the audit trail of the divergence period and must not be read as a description of the corpus as it now stands.** **Not discharged, and deliberately carried forward:** the Art. 6(1)(f) balancing test at `gdpr-policy.md` §3.4 was **re-derived** on the corrected facts rather than patched, because two of its load-bearing premises (an EU bucket jurisdiction, and a ten-year retention ceiling) were false and its proportionality conclusion did not survive their correction. Its proportionality limb now records retention as indefinite and withdraws the limitation-period calibration as a proof of proportionality. **Whether a retention ceiling should be adopted is a controller decision about the processing itself, not a documentation question, and is tracked at #7668.** §(c) field omissions remain tracked at #7625 and are untouched by this correction.]**`

### CLO ship checklist (folded into the ACs below)

1. Canonical + mirror land **atomically** in one commit.
2. Re-pin `legal-doc-shas.ts` for **five** documents: privacy-policy, gdpr-policy,
   data-protection-disclosure, individual-cla, corporate-cla.
3. `lint-legal-scope-block-placement.sh` — no scope blocks added; run anyway.
4. `lint-legal-mirror-drift-baseline.sh` — this PR should **drift-reduce**. Do **not** set
   `SOLEUR_LEGAL_DRIFT_ACCEPT`; if it fails, the two surfaces have diverged and that is a real
   finding, not a gate to suppress.
5. `check-tc-document-sha.sh` + `legal-doc-consistency.test.ts`. **No sentinel edits are required
   by any ruling above — verify that empirically rather than trusting it.**
6. `#7624` and the new retention-ceiling issue number both substituted; **grep the diff for
   `#7668` before marking ready.**
7. Not in this PR: #7625, any Last-Updated bump, the retention-ceiling decision itself.

### Standing caveat carried into the PR body

This is the v1 internal counsel-review attestation under the tenant-zero posture; it is not a
substitute for external counsel, which is reserved for the audit frontmatter's re-evaluation
triggers (first arms-length user, EEA-out, regulated industry). Per #7349: **every replacement
above must be read as prose against the register before it ships — two byte-identical copies of a
wrong sentence pass all five gates.**

