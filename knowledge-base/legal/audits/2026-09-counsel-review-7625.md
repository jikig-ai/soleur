---
title: "CLO counsel review — Art. 30 PA-7 §(c) categories, the Art. 9 determination, and the lawful-basis limb (#7625)"
type: clo-attestation
date: 2026-09-03
issue: 7625
pr: 7803
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: PROCEED-WITH-CHANGES
tier_classification: "Tier 1 (material) — an Art. 9 special-categories determination reversed from `None.`, a categories-of-personal-data cell widened from one record shape to four, a categories-of-data-subjects cell widened to three unintended populations, and an Art. 6(1)(f) balancing limb corrected on both its mechanism and its reach"
semver: "TC_VERSION unchanged — no T&C body edit in scope (tc_version_bump: false)"
brand_survival_threshold: single-user incident
governing_record: "knowledge-base/legal/article-30-register.md — Processing Activity 7, cells (c) Categories of data subjects, (c) Categories of personal data, Special categories (Art. 9 / 10), Lawful basis, and the new (h) DSAR (Art. 15 / 20)"
written_against: >-
  The Art. 30 register and the capture path as of 2026-09-03. The rulings below rest on code facts
  read from `.github/workflows/cla-evidence.yml`, `.github/workflows/cla.yml`,
  `apps/web-platform/scripts/cla-evidence/{schema.ts,build-record.ts,backfill.ts,allowlist-bypass.ts}`
  and `apps/cla-evidence/scripts/gdpr-override.sh`.
  THE REALISED CONTENTS OF THE `soleur-cla-evidence` R2 ARCHIVE ARE **UNMEASURED** — not
  read-refused and not measured-empty, but deliberately not attempted. The register records the
  categories of data the controller *processes*, and the capture predicate is a property of the code;
  the bucket's contents decide the *severity* question (whether an incident occurred, and whether
  Art. 14 notice is owed to an over-captured commenter), which this review expressly does not reach.
  The measurement recipe and its three-arm reading (measured / read-refused / credentials-absent) are
  carried to the PR B tracking issue as a prerequisite of drafting the published-corpus correction,
  not of this amendment.
  Measured dormancy, recorded because it is the strongest mitigating datum available and belongs in
  the record alongside the present-tense finding: on the most recent `issue_comment`-triggered
  `cla-evidence` run to reach completion (run `33796733777`, 2026-09-03T19:29:34Z) the
  `Build and write evidence record` step concluded `skipped`, and the seven subsequent
  `issue_comment` runs concluded `skipped` at the job level. The capture predicate is a property of
  the path, not an observation of current firing — both halves of that sentence belong here, since
  recording only the first overstates and only the second understates.
scope_boundary: >-
  Decides the PA-7 §(c), Special-categories and Lawful-basis cells and mints the PA-7 §(h) cell.
  Does NOT decide: the proportionality of indefinite retention (#7668, on which Ruling 1 supplies a
  new argument without answering it); importer-identity vs byte-location, whose §(e) OPEN QUESTION
  block stands untouched (#7670); the register-to-corpus CI sentinel, to which this review only adds
  anchors (#7669); the LUKS-header bucket (#7671); whether a sign-phrase filter or a closed
  `override_reason` vocabulary is adopted, both engineering decisions for the CTO; whether the
  archive's realised contents include over-captured records; whether Art. 14 notice is owed; and
  whether a DPIA is required, which Art. 35 screening this review expressly declines to open.
re_evaluation_triggers:
  - "A sign-phrase equality check is added to the evidence-write path — would retire the non-signer arm of the Lawful basis cell, narrow the Categories of data subjects cell, and close the published-corpus gap prospectively. The historic window would still require disclosure. NOTE, per the addendum: this is narrower than the advisory first stated — the `allowlist/` bypass arm at `cla-evidence.yml` is untouched by such a gate and keeps processing non-signers, `deruelle` among them."
  - "The realised contents of `soleur-cla-evidence` are measured (`apps/cla-evidence/scripts/inspect-evidence.sh`, Doppler `prd_cla`). This review rules on the capture predicate, which is a code fact; the archive's realised contents were NOT read and are recorded as UNMEASURED. Measurement decides the severity question — whether an incident occurred, and whether Art. 14 notice is owed to an over-captured commenter — not the register text. A non-zero `tombstones/` count is separately material: it would mean an erasure has already run and Ruling 1's second Art. 9 surface is realised rather than hypothetical."
  - "The `cla-evidence` workflow is wired to any repository that is not public, or `jikig-ai/soleur` ceases to be public. Art. 9(2)(e) is conditional on the comment being manifestly made public; `pr_of_record.repo` is unconstrained in the schema, so publicness is a present fact and not a structural invariant."
  - "A closed vocabulary is adopted for `override_reason` in `gdpr-override.sh` — would retire the second Art. 9 surface and the Art. 9(2)(f) reliance in the Special categories cell."
  - "A natural person other than `deruelle` is added to the CLA-action allowlist in `.github/workflows/cla.yml`, or `deruelle` is removed — moves the Categories of data subjects cell limb (ii)."
  - "First arms-length (non-Jikigai) contributor signs the CLA — carried forward from #7624. The first data subject of PA-7 who is not the operator, and the first reader of these cells with an adverse interest. This trigger also converts the 'accepted at present scale' residual in Special categories from a two-person posture into one requiring re-argument."
  - "Adoption of a retention ceiling at #7668 — this review does not decide it, but Ruling 1 supplies a new argument for it (an Art. 9 disclosure that only `gdpr-override.sh` can reach). Re-read Special categories when #7668 closes."
  - "AUP § 4.7 is re-scoped beyond the hosted chat surface — would supply the organisational control this path currently lacks, and would also bear on the two cells that cite § 4.7 for repository submissions (PA-17 and PA-33; flagged, not fixed, in this review)."
  - "External counsel re-review reserved for: first arms-length contributor, EEA-out, regulated industry, or any move from 'may arrive unsolicited' to a positive Art. 9 processing declaration."
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md
  - knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md
  - knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md
  - knowledge-base/legal/audits/2026-08-counsel-review-7100.md
  - knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md
---

# CLO counsel review — Art. 30 PA-7 §(c), Art. 9, and the lawful-basis limb (#7625)

## What this record is

The binding CLO advisory obtained at plan time for #7625, transcribed verbatim, together with the
addendum issued after a five-agent plan review sent four gaps back to the reviewing authority.

It is reproduced here rather than summarised because it is the **governing text** for every cell this
PR amends: `/work` applied the replacement cells and amendment blocks below as written, and did not
author governing legal text mid-implementation. Where the advisory and the addendum disagree, **the
addendum governs**; where either and any other section of the plan disagree, **the advisory governs**.

## Standing caveat

This is the v1 internal counsel-review attestation under the Soleur-as-tenant-zero posture, issued as
the attestation authority for a `single-user incident` threshold. It is draft material and is **not a
substitute for external counsel**, which is reserved for the frontmatter triggers above. The operator
retains a veto.

## CLO Advisory — Binding Rulings

Obtained at plan time from the `soleur:legal:clo` agent against PA-7's `(c) Categories of data
subjects`, `(c) Categories of personal data`, `Special categories` and `Lawful basis` cells. These
rulings are **inputs to `/work`, not review comments.** Where this section and any earlier section of
this plan disagree, **this section governs**. `/work` Phase 0 writes it verbatim to
`knowledge-base/legal/audits/2026-09-counsel-review-7625.md` — planning is confined to
`knowledge-base/project/{plans,specs}/`, so the audit file is a `/work` deliverable.

**Overall disposition: PROCEED-WITH-CHANGES.** `None.` is not sustainable, §(c) is not sustainable,
and limb (iii) is not sustainable as written. None is a blocking defect — there is no notification
duty and no unlawful processing requiring a stop today — but all three move in this PR, and one
changes the PR's class.

### Seven corrections to the brief, made before ruling

Recorded because ruling on the brief's framing would have produced two wrong answers.

1. **`SignerRow` does not declare `repoId`.** `backfill.ts` declares `name`, `id`, `pullRequestNo`,
   `comment_id`, `created_at`, `signedOnPR?`. The live branch content carries `repoId`; the interface
   does not. It is the backfill reader's view, not the record's shape. Do not cite it as a mirror.
2. **The receipt comment is not the informing mechanism, and never was the load-bearing one.**
   `cla.yml`'s `custom-notsigned-prcomment` posts, in-thread and before signing, a link to
   `docs/legal/individual-cla.md`, whose §0 discloses both copies, Cloudflare as a US-established
   processor, indefinite retention and the erasure route — and the required sign phrase is an
   attestation of having read it. A pre-signature Art. 13-shaped notice, materially stronger than a
   post-hoc receipt. This reverses the outcome of Ruling 3 for signers.
3. **The over-capture moves "Categories of data subjects", not only "Categories of personal data".**
   `wait_cla` polls the *persisting* `license/cla` status on the PR head SHA; once green it stays
   green. Every subsequent `issue_comment` on that PR — from any author — writes a record carrying
   that author's `login`, `id`, `type` and verbatim `comment_body`. A reviewer who signs nothing
   becomes a data subject of PA-7.
4. **The `deleted` path is not merely "no receipt".** `build-record.ts` sets
   `capture_method = "live-degraded"`, nulls `comment_body`, sets `fetch_error: "deleted"` — it
   writes a *further* record. The earlier `created` record, holding the body, is not withdrawn and
   cannot be under the §(g) floor.
5. **AUP §4.7 does not reach this surface.** Its heading is "Special-Category and Sensitive Personal
   Data — **Hosted Chat Surface**" and its opening sentence scopes it to `app.soleur.ai` prompt input
   and `chat-attachments`. A GitHub pull-request comment is neither. So there is no filter **and** no
   organisational control on the CLA capture path — weaker than PA-27, PA-32 and PA-35, each of which
   names at least one. (This also means the cells that cite §4.7 as prohibiting Art. 9/10 content
   "in repository submissions" overstate it. **Two such cells, and neither is PA-35**: `:313` (PA-17)
   and `:658` (PA-33) — corrected at plan review. Separate defect — see Ruling 5.)
6. **`compliance-posture.md:20` and `:44` are not PA-7 Art. 9 statements.** Line 20 is the #5363
   entry, scoped to PA-2 `turn_summary`. Line 44 is the #3988 entry recording that AUP §§4.7/4.8 were
   added. Neither says anything about PA-7.
7. **PA-7 §(e) carries no `CORRECTION` block, and line 242 is PA-12, not PA-7.** PA-7 §(e) uses
   `CORPUS DIVERGENCE` → `DIVERGENCE DISCHARGED` → `OPEN QUESTION`. **The register does not have a
   single-label convention. It has a vocabulary** — nine labels in use. `WIDENING` already exists,
   minted at #7100.

### Ruling 1 — Special categories: `None.` is NOT sustainable

`comment_body` is unbounded free text authored by the data subject; no component on the path compares
it to the sign phrase (`grep` for `hereby sign` across `apps/web-platform/scripts/cla-evidence/`,
`apps/cla-evidence/` and `cla-evidence.yml` returns nothing); §(f) is indefinite behind a write-once
floor. The register's own shape for exactly this is "none sought; may arrive unsolicited" plus named
controls and a named residual (PA-27:540, PA-32:639, PA-33:658). PA-7 is out of step with three of
its own siblings, and it is the sibling with the *fewest* controls.

**On Art. 9(2)(e), squarely.** It is genuinely available — a comment on a PR in a public repository
is about as clean a case of "manifestly made public by the data subject" as the Article contemplates.
It does not do the work being asked of it, for three reasons. It is a **gateway, not a denial**:
reaching for it concedes that Art. 9 data may be in the record, and a cell saying `None.` and a cell
relying on (2)(e) cannot both be right. It is **assessed at the moment of processing** while retention
is indefinite: an author who deletes their comment from the public surface removes the very publicity
that opened the gateway, while the archived copy persists behind a floor only `gdpr-override.sh` can
lift — which §(g) itself calls "not absolute". And it is **conditional on the repository being
public**, which nothing in the schema constrains: `pr_of_record.repo` is a free string, so publicness
is a present fact, not a structural invariant. Per `audits/2026-08-counsel-review-7100.md`, (2)(e) is
a special-category gateway, **not** an Art. 6 basis, and must not appear in the Art. 6(1)(f)
balancing. Ruling 3's text keeps it out.

**On `override_reason` — the sharper finding.** `gdpr-override.sh` writes `admin_actor`,
`gdpr_request_ref` and `override_reason`: operator-authored free text stating *why* an erasure was
granted. "Subject asked us to remove a health disclosure" is itself Art. 9 content, is written
*about* a subject rather than *by* them (so (2)(e) is structurally unavailable), and is the one object
in the bucket that an Art. 17 erasure **creates** rather than removes. The available gateway there is
Art. 9(2)(f), pairing with the Art. 17(3)(e) carve-out already relied on at §(f).

**Both arms of the unmeasured question.** This cell is correct whether or not the bucket holds a
realised Art. 9 disclosure, because §(c) records the categories of data the controller *processes*,
and the capture predicate is a property of the code that was read — not of the bucket that was not.
Measurement changes the *severity* question (whether an incident occurred; whether Art. 14 notice is
owed to an over-captured commenter), not the register text. **Do not gate the register edit on the
measurement.**

Also harmonise the row label from `**Special categories**` to `**Special categories (Art. 9 / 10)**`,
matching PA-15/27/32/35. The register is internal-only and in no Eleventy tree, so this touches no
gate today; note it as an input to #7669.

#### Exact replacement cell — Special categories

```text
| **Special categories (Art. 9 / 10)** | **None sought; may arrive unsolicited — and here nothing filters it.** The off-site evidence record persists `comment_body`, the verbatim text of a GitHub pull-request comment authored by the data subject (`EvidenceRecordSchema.comment_body`, `string \| null`, in `apps/web-platform/scripts/cla-evidence/schema.ts`). **No component on the capture path compares that text against the required sign phrase** (`custom-pr-sign-comment` in `.github/workflows/cla.yml`): the write step's only gate is `steps.wait_cla.outputs.cla_state == 'success'`. A signer — or any other commenter, see the capture predicate at §(c) — can therefore place Art. 9 content into an indefinitely-retained, write-once archive. **Art. 9(2)(e) is available but does not carry this cell.** A comment posted on a pull request in a public repository is manifestly made public by its author, so the gateway is open at the moment of processing. Per `knowledge-base/legal/audits/2026-08-counsel-review-7100.md`, Art. 9(2)(e) is a special-category **gateway and not an Art. 6 basis**; it is not relied on in the balancing recorded at "Lawful basis". Two conditions bound it. (i) It holds only while the pull request sits in a **public** repository — `pr_of_record.repo` is unconstrained in the schema, so publicness is a present fact and not a structural invariant. (ii) It is assessed at the moment of processing, whereas §(f) is indefinite behind the §(g) write-once floor — an author who deletes the comment from the public surface removes the publicity that opened the gateway while the archived copy persists, and the `deleted` path writes a further `live-degraded` record without withdrawing the earlier one. **No filter, and no organisational control on this surface:** AUP § 4.7 is scoped by its own heading and opening sentence to the hosted Web Platform at `app.soleur.ai` (prompt field and `chat-attachments`) and does not reach a GitHub pull-request comment. This is a weaker control posture than PA-27, PA-32 or PA-35, each of which names at least one. **The erasure tombstone is a second and distinct Art. 9 surface.** `apps/cla-evidence/scripts/gdpr-override.sh` writes `override_reason` — operator-authored free text stating why an erasure was granted — alongside `gdpr_request_ref`. A reason of the form "subject asked us to remove a health disclosure" is itself Art. 9 content, is written **about** a data subject rather than by them (so Art. 9(2)(e) is structurally unavailable), and is the one object in this bucket that an Art. 17 erasure **creates** rather than removes. Gateway relied on there is Art. 9(2)(f) — establishment, exercise or defence of legal claims — the same ground as the Art. 17(3)(e) carve-out at §(f). **Named residual (accepted at present scale, not as a steady state):** erasure of an Art. 9 disclosure runs only through `gdpr-override.sh`, which §(g) itself records as "not absolute". The signer population is two. Two remediations are recorded as options and are **not** adopted here, being engineering decisions: a sign-phrase equality check before the evidence write, and a closed vocabulary for `override_reason`. A GitHub login, numeric account id and contributor identity are **not** Art. 9 special categories. **No Art. 10 data** is sought or expected on this path. |
```

### Ruling 2 — §(c) Categories of personal data, and Categories of data subjects

**Bypass shape: in scope of §(c), with a carve.** The "mostly bots" argument fails on its own terms —
`deruelle` is on the `cla.yml` allowlist and is a natural person. His `principal`, `db_id`,
`first_seen_at` and `first_pr` are personal data of an identified individual, held in the same bucket
under the same floor. "Mostly not personal data" is not "not personal data."

**Tombstone shape: in scope of §(c).** The "Art. 17 artefact, not a category" argument fails.
Art. 30(1)(c) asks what personal data the controller processes for the activity. `admin_actor`
identifies a natural person; `gdpr_request_ref` may identify the requesting subject; `override_reason`
is free text about them. It is stored in the same bucket, for the same purpose, sealed by the same
rule. Art. 17 machinery is itself processing, and a category of data that exists *only* because of an
erasure is precisely the kind a register must not lose track of.

#### Exact replacement cell — (c) Categories of personal data

```text
| **(c) Categories of personal data** | **Four record shapes.** **(1) Public canonical record** — `origin/cla-signatures:signatures/cla.json`, one entry per signer: `name` (GitHub login), `id` (GitHub numeric account id), `comment_id`, `created_at` (signature timestamp), `repoId`, `pullRequestNo`. (The `SignerRow` interface at `apps/web-platform/scripts/cla-evidence/backfill.ts` is the backfill reader's view and declares `name`, `id`, `pullRequestNo`, `comment_id`, `created_at`, optional `signedOnPR` — it does **not** declare `repoId`, which the live branch content carries. Do not read it as the record's full shape.) **(2) Off-site evidence record** — `signatures/<sha256-of-payload>.json`, `EvidenceRecordSchema` at `apps/web-platform/scripts/cla-evidence/schema.ts`: `schema_version`; `comment_id`; **`comment_body` — the verbatim text of the comment, unbounded free text authored by the data subject** (`string \| null`); `comment_body_sha256`; `actor.{login, id, type}`; `pr_of_record.{number, repo}`; `cla_doc.{path, git_sha, content_sha256}` (a hash of Jikigai's text, not the subject's); `signed_at`; `capture_method` (`live \| live-degraded \| backfilled \| backfilled-pre-existed`); `workflow_run_id`; and, on a fetch failure or a deletion, `comment_body_fetch_failed`, `fetch_error`, `first_pr_signed_against`. On an **edit**, a second record is written carrying the edited body; on a **delete**, a `live-degraded` record is written with `comment_body` null. Neither withdraws the earlier record, which the §(g) floor forbids. **(3) Allowlist-bypass record** — `allowlist/<principal>/<quarter>.json`, `BypassRecord` at `apps/web-platform/scripts/cla-evidence/allowlist-bypass.ts`: `principal`, `principal_safe`, `db_id`, `quarter`, `first_seen_at`, `first_pr`, `allowlist_source`. Most allowlist principals are bot accounts and are not natural persons, so those records carry no personal data; the allowlist at `.github/workflows/cla.yml` also names `deruelle`, a natural person, and that principal's records **are** personal data of an identified individual. **(4) Erasure tombstone** — `tombstones/<prior_sha>.deleted.json`, written by `apps/cla-evidence/scripts/gdpr-override.sh`: `schema_version`, `deleted_at`, `admin_actor` (the operator, an identified natural person), `gdpr_request_ref` (may identify the requesting data subject), `prior_object_sha`, `override_reason` (operator-authored free text). Recorded here rather than treated as an out-of-scope Art. 17 artefact: it is personal data held in the same bucket, for the same purpose, under the same §(g) floor, and Art. 17 machinery is itself processing. **Capture predicate — wider than "signature data".** The evidence-record write step in `.github/workflows/cla-evidence.yml` fires on any `issue_comment` (`created`, `edited`, `deleted`) on a pull request whose `license/cla` commit status is `success`, and `wait_cla` reads that status as it persists on the head SHA rather than as a property of the triggering comment. Nothing on the path tests whether the comment is the sign comment. Consequently `actor` and `comment_body` can carry a commenter who signed nothing and text that is not a signature. Recorded as a finding against the implementation; the lawful-basis consequence is at "Lawful basis" and the Art. 9 consequence at "Special categories". **Corporate CLA:** signatory name, corporate email and corporate identity, supplied out-of-band to legal@jikigai.com per the `custom-notsigned-prcomment` instruction in `.github/workflows/cla.yml`; no automated record is written for this route. |
```

#### Exact replacement cell — (c) Categories of data subjects

```text
| **(c) Categories of data subjects** | Individual contributors signing the ICLA; authorised signatories of corporations signing the CCLA. **Additionally, and not by design — see the capture predicate below:** (i) **any GitHub account that comments on a pull request in this repository while that pull request's `license/cla` commit status is `success`**, whether or not it ever signs anything — the evidence-record write gates on that status alone, so a reviewer, a maintainer or a passer-by becomes the `actor` of an evidence record; (ii) **natural persons named on the CLA-action allowlist** at `.github/workflows/cla.yml` (today: `deruelle`), who are the subjects of `allowlist/` bypass records without signing a CLA — the remaining allowlist principals are bot accounts and are not data subjects; (iii) **the operator recorded as `admin_actor`** in an erasure tombstone, and any data subject identified by that tombstone's `gdpr_request_ref`. |
```

### Ruling 3 — Lawful basis: limb (iii) does NOT hold, and more than limb (iii) moves

**For signers, the limb is correct in substance and wrong in mechanism.** The signer is informed —
better than the limb claims — but not "at signing time" and not by the receipt. The notice is
`custom-notsigned-prcomment` → `individual-cla.md` §0, delivered *before* signing, with the sign
phrase as an attestation of having read it. The three receipt defects are all real and all verified,
and they matter exactly because they show why the receipt cannot be the mechanism:
`continue-on-error: true`; an `if:` requiring `action == 'created'` while the write fires on
`created`/`edited`/`deleted`; and no receipt at all on the `pull_request_target` bypass path.

**For non-signers, Art. 6(1)(f) fails — and it fails at necessity, before balancing.** A record whose
actor signed nothing evidences no grant. Limb (ii) ("minimum necessary to evidence the grant") is not
merely strained; it has no subject matter. That ends the analysis in the manner of PA-32's
publication limb, and no other Art. 6 basis is available: no contract, no consent sought, no
legal-obligation, vital-interests or public-task ground. This is a finding against the
implementation, not a defect in the interest.

**Art. 9(2) gateway now additionally required?** Yes, where Art. 9 content actually arrives — and it
is available: (2)(e) for a public-PR comment, subject to Ruling 1's two bounds; (2)(f) for the
tombstone `override_reason`. Neither is an Art. 6 basis and neither is offered as one.

#### Exact replacement cell — Lawful basis

```text
| **Lawful basis** | Art. 6(1)(f) — legitimate interest in maintaining an enforceable record of IP-license grants. **Balancing test — signature records (shapes (1) and (2) where the actor is a signer):** (i) the data is publicly disclosed by the signer through the act of contributing on a public pull request; (ii) processing is the minimum necessary to evidence the grant; (iii) **the signer is informed before signing, and not by the receipt** — the upstream CLA action posts `custom-notsigned-prcomment` (`.github/workflows/cla.yml`) linking to `docs/legal/individual-cla.md`, whose § 0 discloses both copies of the record, the US-established processor, the indefinite retention and the erasure route, and the required sign phrase ("I have read the CLA Document and I hereby sign the CLA") is an attestation of having read that document; the field-level detail, including that the verbatim comment body is retained, sits in GDPR Policy § 3.4, Privacy Policy § 4.5 and DPD § 2.3(n), which § 0 cross-references; (iv) no automated decision-making. **The receipt comment is not the informing mechanism and must not be treated as one.** The "Post receipt comment" step in `.github/workflows/cla-evidence.yml` carries `continue-on-error: true`, and its `if:` requires `github.event.action == 'created'` while the record-writing step also fires on `edited` and `deleted` — so on an edit or a delete a record is written and no receipt is posted at all, a structural absence rather than a soft failure. The `pull_request_target` bypass path posts no receipt ever. The receipt's text names the CLA document's git SHA and a retrieval command; it does not describe the record's fields. **The balancing test does not reach the non-signer capture.** Where the `actor` of an evidence record is a commenter who signed nothing (see the capture predicate at §(c)), the record evidences no grant, so limb (ii) fails on **necessity** and the analysis stops there, before balancing, in the manner of PA-32. No other Art. 6 basis is available for that fraction of the processing: there is no contract with such a commenter, no consent is sought, and no legal-obligation, vital-interests or public-task ground applies. Recorded as a finding against the implementation, not as a defect in the interest; the remediation is an engineering change and is not decided in this register. **Art. 9(2) gateways, where Art. 9 content arrives** (see Special categories): Art. 9(2)(e) for a comment manifestly made public by its author on a public pull request, subject to the two bounds recorded there; Art. 9(2)(f) — establishment, exercise or defence of legal claims — for the tombstone `override_reason`, which the data subject did not write and to which (2)(e) is therefore unavailable. Neither is an Art. 6 basis and neither is offered as one. |
```

### Ruling 4 — amendment mechanics: three labels, matched to three kinds of change

The premise that the register has one convention (`CORRECTION`) is not what the file shows.
`grep -o "\[2026-[0-9-]* [A-Z][A-Z ]*(" knowledge-base/legal/article-30-register.md` returns
**nine distinct kind-labels** in use: `CORRECTION`, `WIDENING`, `NARROWING`, `ADDITION`,
`AMENDMENT`, `UPDATE`, `OPEN QUESTION`, `CORPUS DIVERGENCE`, `DIVERGENCE DISCHARGED`. The convention
is not one label — **the label names the kind of change**, and the block body carries the nuance.

> **Verified independently, with one refinement to the advisory's count.** Running that grep returns
> **ten** distinct strings, not nine: the tenth is `TWO ITEMS RECORDED`, a one-off descriptor rather
> than a kind-label, which is presumably why the advisory did not list it. Occurrence counts:
> `UPDATE` 9, `CORRECTION` 8, `NARROWING` 2, `AMENDMENT` 2, `ADDITION` 2, and one each of `WIDENING`,
> `TWO ITEMS RECORDED`, `OPEN QUESTION`, `DIVERGENCE DISCHARGED`, `CORPUS DIVERGENCE`. The single
> `WIDENING` use confirms the #7100 precedent the advisory relies on, and the substantive ruling —
> a vocabulary exists, `WIDENING` is already minted, do not invent another — is unaffected.

| Cell | Label | Why |
|---|---|---|
| `(c) Categories of personal data` | **`WIDENING`** | Directly on the #7100 precedent: a statement that was **under-inclusive** while asserting completeness |
| `(c) Categories of data subjects` | **`WIDENING`** | Same kind |
| `Special categories` | **`CORRECTION`** | Not under-inclusive — **false**. `None.` asserts a negative the record does not support; a widening label would understate it |
| `Lawful basis` | **`CORRECTION`** | Limb (iii) misnames the mechanism and is false for the non-signer arm |

**Do not mint a new label.** The vocabulary already covers every case here, and #7669 would have to
learn any tenth label added. **Placement and closing formula** follow PA-7's own local style at line
161: block appended at the end of the cell, closing `…convention.]**`.

#### Exact block — §(c) Categories of personal data

```text
**[2026-09-03 WIDENING (#7625): this cell previously read "GitHub username; signature timestamp; pull-request reference associated with the signing event. For Corporate CLA: signatory name + corporate email + corporate identity." That was a closed enumeration, incomplete about the one record shape it named and silent about three others. It omitted `id`, `comment_id` and `repoId` from the public branch record; the entire off-site evidence record introduced by #3201, including the verbatim `comment_body`; the `allowlist/` bypass record; and the erasure tombstone — the last two already named at §(g), so the register described object prefixes whose contents it did not record. The under-inclusion mattered beyond bookkeeping: a §(c) cell is what a DSAR scope and a breach-scope assessment are read against, and a reader relying on the prior text would have under-reported on both. It also left the internal governing record **narrower than the notice published to the data subject** — GDPR Policy § 3.4, Privacy Policy § 4.5 and DPD § 2.3(n) have disclosed the verbatim comment body since #7624 (2026-08-20) — which is the wrong direction for the two to differ. Separately, and not a prior mis-statement: the capture predicate recorded above was established for the first time in this review and is a finding against the implementation, not a repair of the record. An Art. 30(1) record-keeping incompleteness is not an Art. 4(12) personal-data breach and triggers no Art. 33/34 notification; this widening is the record-keeping discharge. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

#### Exact block — Special categories

```text
**[2026-09-03 CORRECTION (#7625): this cell previously read "None." That was not sustainable. The evidence record persists an unbounded free-text field authored by the data subject, no filter compares it to the sign phrase, and retention is indefinite behind a write-once floor — the conditions under which this register's own PA-27, PA-32 and PA-35 cells reason rather than deny. The strongest argument for the prior text, that the comment is manifestly made public, is Art. 9(2)(e): a gateway that concedes the point rather than a denial that avoids it, and one whose two conditions are recorded above. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

#### Exact block — Lawful basis

```text
**[2026-09-03 CORRECTION (#7625): limb (iii) previously read "signer is informed of the record at signing time", which named no mechanism. The mechanism is the pre-signature notice comment and § 0 of the CLA document, not the post-hoc receipt — the receipt is soft-failing and structurally absent on `edited`, `deleted` and the bypass path, and could not have carried the limb had it been the mechanism. The limb is restated on the mechanism that actually exists, and the balancing is split: it holds for signers and is unavailable for the non-signer capture recorded at §(c), where it fails on necessity. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

A `WIDENING` block is required on `(c) Categories of data subjects` as well; draft it on the same
pattern, naming the three added limbs and citing the capture predicate as the reason.

### Ruling 5 — scope boundary, and the PR split

#### This PR must NOT decide

- **#7668** — proportionality of indefinite retention, and whether a ceiling is adopted. Ruling 1
  *pressures* it (an unerasable Art. 9 disclosure is the strongest argument yet for a ceiling); it
  must not answer it. Record the link in the audit; do not touch §(f).
- **#7670** — importer-identity vs byte-location. §(e) is not amended and its `OPEN QUESTION` block
  stands untouched.
- **#7669** — the corpus-anchor CI sentinel. This PR *adds* anchors (`schema.ts`,
  `allowlist-bypass.ts`, `gdpr-override.sh`, `cla-evidence.yml`, `cla.yml`) and a row-label
  harmonisation; note them as inputs, build nothing.
- **#7671** — the LUKS-header bucket. Unrelated.
- **Whether to add a sign-phrase filter, or a closed vocabulary for `override_reason`.** Engineering
  decisions; defer to the CTO. The register records the position as it is; it does not prescribe the
  fix.
- **Whether the archive's realised contents include over-captured records.** Do not assert either
  arm.
- **Whether Art. 14 notice is owed** to an over-captured non-signer. Contingent on that measurement.
- **A DPIA.** Art. 35 is a separate test, the population is two, and the screening convention in
  `knowledge-base/legal/audits/` exists. Do not open one.
- **The over-broad AUP §4.7 citations.** Real defect, surfaced here. Two cells — PA-17 (`:313`) and
  PA-33 (`:658`), not PA-35, which was a misattribution corrected at plan review. Belongs to those
  activities' own amendments. File it.

#### Does anything here require a `docs/legal/**` edit? Yes. Split the PR.

Two separable questions, with different answers.

**(A) The field-level widening of §(c) — no docs edit.** The published corpus already discloses the
verbatim body, doc-hash, PR-of-record, `signed_at` and `capture_method` (privacy-policy §4.5
enumerates exactly those). Art. 13/14 does not require a field-by-field enumeration, and `actor.id` /
`comment_id` add no category the reader is not already told about. The corpus is *wider* than the
register here, which is why this half is internal-only.

**(B) The capture predicate and the non-signer data subjects — yes, and plainly.** DPD §2.3(n) reads
"For each signature recorded under Section 2.3(d), a content-addressed evidence record is written."
Privacy Policy §4.5 and GDPR Policy §3.4 both frame the archive as processing "CLA signature data
when contributors sign." All three are now known to be narrower than the code. A person whose comment
is archived without signing is told nothing by any published document. That is an Art. 13/14
transparency gap on the published surface, and — not to be softened — **it does not depend on
measuring the bucket.** It depends on the workflow `if:` conditions, which were read. The corpus is
wrong on the code fact alone.

So the PR class changes. **Split:**

- **PR A (this plan — internal only).** `knowledge-base/legal/article-30-register.md` PA-7 (four
  cells) + the audit records under `knowledge-base/legal/audits/` + the `compliance-posture.md`
  Active Items addition. Touches no `docs/legal/**`, so none of the five gates fire. Closes #7625.
- **PR B (separate — five-gate class).** `docs/legal/gdpr-policy.md` §3.4,
  `docs/legal/privacy-policy.md` §4.5, `docs/legal/data-protection-disclosure.md` §2.3(n), each with
  its `plugins/soleur/docs/pages/legal/` mirror (all three mirrors exist — verified), plus a
  `legal-doc-shas.ts` re-pin and the `EXPECTED_COUNT` sentinel. None of the three is in
  `BODY_EQUIVALENCE_DOCS` (verified: `check-tc-document-sha.sh:130` enrolls only
  `terms-and-conditions`, `acceptable-use-policy`, `disclaimer`), so no body-equivalence check
  arrives — but the mirror-drift ratchet, the SHA pin and heading-parity all apply.
  **TC_VERSION: not required** — no T&C body edit.

**Sequencing.** It is cheaper to close the gap than to publish it. If the engineering fix (a
sign-phrase equality check before the write) lands before PR B, PR B discloses a *historic window*
rather than an ongoing practice, and its text is materially easier to write and to defend. **PR A
should not wait for either — the register records today's position today.**

### Ruling 6 — downstream consumers: none move

- **`article-30-register.md:28` (§0 DPO cell) — does NOT move.** Three independent reasons, any one
  sufficient. (a) Ruling 1 is "none sought; may arrive unsolicited", not a positive declaration of
  Art. 9 processing. (b) The cell's predicate is "**large-scale** processing of Art. 9/10 data"
  (Art. 37(1)(c)); the PA-7 signer population is two, and unsolicited arrival in a free-text field is
  not large-scale processing on any reading of WP243. (c) Dispositively: the register already carries
  "may arrive unsolicited" Art. 9 cells — PA-27, PA-31, PA-32 and PA-33 (**not** PA-35, whose cell
  reads a bare `None identified.`) — and the DPO cell has never moved for them. PA-7 joining that set
  changes nothing it did not already have to survive. [Count corrected at plan review; the argument is
  unaffected and if anything stronger at four cells than three.] The
  cell's own "re-assessed quarterly" is the mechanism that catches a scale change.
- **`compliance-posture.md:20` — does NOT move.** The #5363 entry, scoped to PA-2 `turn_summary`.
- **`compliance-posture.md:44` — does NOT move.** The #3988 entry recording that AUP §§4.7/4.8 were
  added; an accurate historical record of that PR. What Ruling 1 surfaces is that §4.7's *scope* does
  not reach the CLA path — a gap, not an error in line 44. That belongs as a **new Active Items
  row**, not an edit to line 44.
- **`audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md:88-92` — checked, does NOT
  move.** It cites §(c)'s enumeration to establish that this surface *does* process personal data.
  The widening strengthens that conclusion; it does not falsify it, and the ruling's holding does not
  turn on the enumeration being complete.
- **`legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md:261` — checked, does
  NOT move.** It quotes PA-7 limb (i), which Ruling 3 preserves verbatim for the signer arm. Line
  510's "CLA coverage — an open question" is untouched.

**Net: one addition** (a new Active Items row for the AUP §4.7 scope gap), **zero edits** to any
existing downstream statement.

### Re-evaluation triggers for the audit frontmatter

```yaml
re_evaluation_triggers:
  - "A sign-phrase equality check is added to the evidence-write path — would retire the non-signer arm of the Lawful basis cell, narrow the Categories of data subjects cell, and close the published-corpus gap prospectively. The historic window would still require disclosure."
  - "The realised contents of `soleur-cla-evidence` are measured (`apps/cla-evidence/scripts/inspect-evidence.sh`, Doppler `prd_cla`). This review rules on the capture predicate, which is a code fact; the archive's realised contents were NOT read and are recorded as UNKNOWN. Measurement decides the severity question — whether an incident occurred, and whether Art. 14 notice is owed to an over-captured commenter — not the register text."
  - "The `cla-evidence` workflow is wired to any repository that is not public, or `jikig-ai/soleur` ceases to be public. Art. 9(2)(e) is conditional on the comment being manifestly made public; `pr_of_record.repo` is unconstrained in the schema, so publicness is a present fact and not a structural invariant."
  - "A closed vocabulary is adopted for `override_reason` in `gdpr-override.sh` — would retire the second Art. 9 surface and the Art. 9(2)(f) reliance in the Special categories cell."
  - "A natural person other than `deruelle` is added to the CLA-action allowlist in `.github/workflows/cla.yml`, or `deruelle` is removed — moves the Categories of data subjects cell limb (ii)."
  - "First arms-length (non-Jikigai) contributor signs the CLA — carried forward from #7624. The first data subject of PA-7 who is not the operator, and the first reader of these cells with an adverse interest. This trigger also converts the 'accepted at present scale' residual in Special categories from a two-person posture into one requiring re-argument."
  - "Adoption of a retention ceiling at #7668 — this review does not decide it, but Ruling 1 supplies a new argument for it (an Art. 9 disclosure that only `gdpr-override.sh` can reach). Re-read Special categories when #7668 closes."
  - "AUP § 4.7 is re-scoped beyond the hosted chat surface — would supply the organisational control this path currently lacks, and would also bear on PA-35's citation of § 4.7 for repository submissions (flagged, not fixed, in this review)."
  - "External counsel re-review reserved for: first arms-length contributor, EEA-out, regulated industry, or any move from 'may arrive unsolicited' to a positive Art. 9 processing declaration."
```

### Standing caveat, to be carried into both audit records and the PR body

This is the v1 internal counsel-review attestation under the Soleur-as-tenant-zero posture, issued as
the attestation authority for a `single-user incident` threshold. It is draft material and is not a
substitute for external counsel, which is reserved for the frontmatter triggers above. The operator
retains a veto.

**Files the reviewing authority read for this advisory:**
`knowledge-base/legal/article-30-register.md` (PA-7 lines 152-164; precedent cells 28, 74, 242, 291,
540, 639, 658) · `knowledge-base/legal/compliance-posture.md` ·
`knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md` ·
`knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` ·
`knowledge-base/legal/audits/2026-08-counsel-review-7100.md` · `.github/workflows/cla-evidence.yml` ·
`.github/workflows/cla.yml` ·
`apps/web-platform/scripts/cla-evidence/{schema.ts,build-record.ts,backfill.ts,allowlist-bypass.ts}` ·
`apps/cla-evidence/scripts/gdpr-override.sh` · `apps/web-platform/scripts/check-tc-document-sha.sh` ·
`docs/legal/{gdpr-policy.md,privacy-policy.md,data-protection-disclosure.md,acceptable-use-policy.md,individual-cla.md}` ·
`origin/cla-signatures:signatures/cla.json`.

---

## CLO Advisory — Addendum after plan review (2026-09-03)

A five-agent plan review found four gaps in the advisory above and they were sent back to the
reviewing authority rather than papered over here. **All four were confirmed against source; one was
a false statement the authority had itself introduced.** This addendum governs where it and the
advisory above disagree, and it is transcribed into `2026-09-counsel-review-7625.md` alongside it.

### A1 — Ruling 3's cell text carried a false cross-reference. Corrected clause.

Ruling 3's limb (iii) asserted that the field-level detail "sits in GDPR Policy § 3.4, Privacy Policy
§ 4.5 and DPD § 2.3(n), **which § 0 cross-references**". `docs/legal/individual-cla.md` §0 closes by
naming Privacy Policy §§4.5, 5.11 and 10 and GDPR Policy §§3.4 and 6 — **it does not reference the DPD
at all.** A false statement, landing in the very cell whose original defect was that it named no
mechanism, and the exact class of
`knowledge-base/project/learnings/2026-08-20-my-correction-pr-published-three-new-false-statements.md`.

Replace the limb-(iii) tail, from "the field-level detail" to the end of the limb, with:

```text
the field-level detail, including that the verbatim sign-comment body is retained, sits in Privacy Policy § 4.5 ("the bucket contains a content-addressed record per signature (doc-hash, verbatim sign-comment body, PR-of-record, signed_at, capture_method)") and GDPR Policy § 3.4, both of which § 0 cross-references — § 0 names Privacy Policy §§ 4.5, 5.11 and 10 and GDPR Policy §§ 3.4 and 6, and does **not** cross-reference the DPD, so DPD § 2.3(n) carries the same disclosure but is not part of the notice chain relied on in this limb;
```

**And the sharper consequence:** §5.11 *is* inside that notice chain, and §5.11 is where the false
"bypass records for allowlisted **bot accounts**" sentence lives (`privacy-policy.md:383`). A signer
following §0's own pointer is handed an incorrect statement about who the bypass path records. Fixing
§5.11 in PR B is **load-bearing for limb (iii)**, not cosmetic — say so in the PR B rationale.

**Standing instruction carried into `/work`:** re-read *every* cross-reference in the four cells
against the target document before the PR goes ready, not only this one.

### A2 — `(c) Categories of data subjects` WIDENING block, supplied verbatim

Appended at the end of the cell, before the terminating `|`, PA-7 local style:

```text
**[2026-09-03 WIDENING (#7625): this cell previously read "Individual contributors signing the ICLA; authorised signatories of corporations signing the CCLA." That named the population the activity was designed for and omitted three it actually processes. The evidence-record write step in `.github/workflows/cla-evidence.yml` gates on the persisting `license/cla` commit status and not on the content of the triggering comment, so any commenter on a green pull request becomes the `actor` of a record; the `allowlist/` path in the same workflow records natural persons named on the `.github/workflows/cla.yml` allowlist who sign nothing; and `apps/cla-evidence/scripts/gdpr-override.sh` records the operator and, via `gdpr_request_ref`, the subject of an erasure request. The under-inclusion is consequential rather than cosmetic: a categories-of-data-subjects cell determines who is owed Art. 13/14 transparency, who may bring an Art. 15 request, and who must be offered the Art. 21(1) objection route that Art. 6(1)(f) processing requires — and the two populations added at (i) and (ii) hold no account with Jikigai and appear in no published document. The additions were established by reading the workflow conditions in this review: they are a finding against the implementation, not the repair of a prior mis-statement, which is why this is a widening and not a correction. An Art. 30(1) record-keeping incompleteness is not an Art. 4(12) personal-data breach and triggers no Art. 33/34 notification. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

### A3 — PR A must carry a CORPUS DIVERGENCE block. Ruling 5 had a hole.

The block minted at #7601 exists for exactly this state, and with **#7669 deliberately unbuilt the
divergence would be undetectable rather than merely unrecorded.** **One block, on
`(c) Categories of data subjects`**, immediately after the WIDENING block — not two: the Lawful-basis
divergence follows from the same fact, and a divergence note in two cells is the marked/unmarked
hazard the #7100 `NARROWING` block calls out. Have the Lawful-basis CORRECTION block end with *"the
corpus divergence this creates is recorded at the `(c) Categories of data subjects` cell"* rather than
restating it.

```text
**[2026-09-03 CORPUS DIVERGENCE (#7625): `docs/legal/gdpr-policy.md` §3.4, `docs/legal/privacy-policy.md` §§4.5, 5.11 and 8.1, and `docs/legal/data-protection-disclosure.md` §2.3(n) all frame this archive as processing the data of contributors who sign, and disclose no population beyond them. Three of their statements are superseded by this cell and by "Lawful basis": (i) that an evidence record is written "for each signature" (DPD §2.3(n)) — it is written for any comment on a pull request whose `license/cla` status is green; (ii) that bypass records are for "allowlisted bot accounts (`dependabot[bot]`, `renovate[bot]`, `claude[bot]`)" (privacy-policy §5.11, DPD §2.3(n)) — the allowlist at `.github/workflows/cla.yml` also carries `deruelle`, a natural person, and `soleur-ai[bot]`, neither of which those enumerations name; and (iii) that Art. 6(1)(f) supports this archive without qualification (gdpr-policy §3.4) — it is unavailable for the non-signer fraction, which fails at necessity before balancing. Privacy Policy §8.1 additionally provides no Art. 21(1) route for the involuntary population identified above, while providing one for three comparable populations. The corpus correction is tracked at #<PR-B-issue>. Until that lands, this cell governs. Recorded here rather than left to the register-to-corpus sentinel, which is not built — that work is #7669.]**
```

**Do not land this with `#<PR-B-issue>` unsubstituted.** Mint the PR B issue in Phase 2 first and
write the real number — a divergence block whose tracking reference is unresolvable is worse than none, because it
reads as discharged-somewhere. This is a second, independent reason the filings phase runs before both the amendment and the sweep.

### A4 — PA-7 needs an `(h) DSAR` cell, and it belongs in PR A

PA-32 (`:626`) and PA-33 (`:645`) mint `(h)` cells precisely because they carry involuntary
populations; Ruling 2 mints one for PA-7. Leaving PA-7 without the cell invites a reader to assume it
shares PA-32's "not reachable, no completeness guarantee" posture — and **PA-7's answer is materially
better**, which is exactly why it must be written down rather than inferred:
`inspect-evidence.sh by-contributor` filtering on `.actor.login` is a real enumeration path over
`signatures/` that no PA-32/PA-33 surface has. The register cell goes in PR A; the §8.1 carve-out that
actually confers the route goes in PR B. The `(h)` count moves 8 → 9. No test asserts it —
`legal-doc-consistency.test.ts:195` reads the register only at a PA-15(c) anchor — so PR A trips
nothing. **The `(h)` cell is an addition and takes no amendment block: it states no prior position.**

```text
| **(h) DSAR (Art. 15 / 20)** | **Reachable, unlike PA-32 and PA-33 — and the difference is recorded rather than left to be assumed.** `DSAR_TABLE_ALLOWLIST` (`apps/web-platform/server/dsar-export-allowlist.ts`) enumerates **database tables** and reaches none of this activity's four record shapes, none of which is a table. But an **enumeration path exists** here where none exists over a git history or an issue body: `apps/cla-evidence/scripts/inspect-evidence.sh by-contributor <login>` filters `signatures/` records on `.actor.login`, so it reaches a non-signer commenter as readily as a signer; `by-pr` and `by-quarter` cover the other axes; shape (1) is a single public JSON file and is trivially enumerable; and shape (3) is keyed by principal (`allowlist/<principal>/<quarter>.json`), so it is enumerable by construction. **The honest Art. 15 route today** is a manual request to `legal@jikigai.com`, answered by running `inspect-evidence.sh by-contributor` against the archive and reading the public branch — an operator-only path requiring Doppler `prd_cla` credentials, with **no self-serve surface at `/dashboard/settings/privacy`**, because the subjects of this activity generally hold no Web Platform account. **One shape is not enumerable by its own subject:** the erasure tombstone (shape (4)) is keyed by `prior_object_sha` and by no subject identifier, so a person named in a tombstone's `gdpr_request_ref` cannot be found by searching for themselves — `inspect-evidence.sh tombstone <object-sha>` presupposes knowing the sha. **Art. 20 portability does not apply** to any shape: the lawful basis is Art. 6(1)(f), and Art. 20 is available only for processing grounded on Art. 6(1)(a) consent or Art. 6(1)(b) contract; that a signer authored the comment text does not change that. **Art. 21(1) right to object — mandatory for Art. 6(1)(f) processing, and currently absent for the involuntary population.** `docs/legal/privacy-policy.md` § 8.1 carries named carve-outs for community-digest subjects, departed workspace members, LinkedIn-published content and operator-assisted sessions, and carries **no CLA carve-out** — so a non-signer commenter or an allowlist-bypass principal, neither of whom holds an account with Jikigai, is offered no route anywhere in the published corpus. Same shape as the gap PA-32 and PA-33 record at **DEF-9** (#7126); tracked for the corpus at #<PR-B-issue>. **Art. 17 interaction:** the erasure route is `apps/cla-evidence/scripts/gdpr-override.sh` per §(f) and §(g). Note that honouring an erasure **creates** shape (4), which the §(g) floor then seals — an Art. 17 request against this activity cannot be fully unwound. |
```

### A5 — Four Active Items rows, not one and not three. No DPIA row.

Ruling 6 said one. Review argued three, on the PA-32 precedent. **The answer is four**, and the
acceptance criterion asserts that number.

| Row | Item | Finding | Remediation |
|---|---|---|---|
| 1 | PA-7 non-signer capture has **no available Art. 6 basis** — filter or cease | Ruling 3: Art. 6(1)(f) fails at necessity for any record whose `actor` signed nothing; no other basis available | The sign-phrase check (Phase 2 item 2). Direct analogue of **#7119** |
| 2 | PA-7 `comment_body` **Art. 9 ingress**: no filter, **and no organisational control** | Ruling 1 | Survives Row 1's fix — a strict-equality gate would bound it, a containment-style gate would not, and a signer's own comment can carry Art. 9 content alongside the required sentence. Record that AUP §4.7 does not reach this path, so unlike PA-27/32/33 there is **neither** a technical nor an organisational measure |
| 3 | PA-7 **published corpus does not disclose the non-signer population**; no Art. 21(1) route exists for it | Ruling 5(B) + A3 + A4 | PR B. This is the CORPUS DIVERGENCE block's referent. **Not contingent on measurement — a code fact** |
| 4 | PA-7 tombstone **`override_reason` free-text Art. 9 surface**, un-erasable by construction | Ruling 1's second surface | Distinct population (operator + requesting subject), distinct gateway (Art. 9(2)(f), not (2)(e) — the subject did not write it), distinct remediation (closed vocabulary). PA-32 got separate rows for separate remediations |

Each row carries its own `compliance/critical` issue from Phase 2, `Status: OPEN`, and a `check_id`.

**No DPIA row, and the reason is recorded so the count is not re-litigated.** PA-32 earned #7121
because its screening memo *concluded* a full DPIA was required. No such conclusion exists for PA-7
and this review expressly declines to reach Art. 35: the signer population is two, nothing is
systematic, and Art. 9 arrival is unsolicited rather than a purpose. **The hook instead:** if the
bucket measurement returns realised over-capture at any volume, the Art. 35 screening question
reopens.

**The bucket measurement is the severity determinant for Row 1, not a fifth row.** It decides whether
records exist, not whether the basis is available.

### A6 — accepted corrections to the advisory's own record

- **PR B scope additions endorsed, not merely unopposed:** `privacy-policy.md` §5.11 and §8.1. Ruling
  5(B)'s scope was incomplete. §5.11 is the higher priority of the two, per A1. No change is needed to
  `individual-cla.md` / `corporate-cla.md` §0 — neither enumerates fields or populations, and fixing
  §5.11 repairs what §0 points at.
- **Ten labels, not nine.** `TWO ITEMS RECORDED` at PA-1 §(e). The assignment is unaffected, but the
  count correction is itself recorded in the audit, because the vocabulary was cited as evidence for
  Ruling 4.
- **Ruling 4 now covers five blocks:** `WIDENING` on both §(c) cells, `CORRECTION` on Special
  categories and on Lawful basis, `CORPUS DIVERGENCE` on Categories of data subjects.
