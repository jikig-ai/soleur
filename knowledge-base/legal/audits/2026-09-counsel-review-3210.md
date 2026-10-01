---
title: "Counsel review audit — #3210 / PR #7828 (the Corporate CLA coverage map, re-reviewed after the origin/main merge moved PA-7 under it)"
type: counsel-review
date: 2026-09-07
issue: 3210
pr: 7828
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
date_reviewed: 2026-09-07
signed_off_at: 2026-09-07
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
rounds:
  - "Round 1 (2026-09-07, pre-b91e5a83d) — three blockers raised: B1 privacy expectation, B2 temporal gap, B3 unimplemented state. Three defects corrected in review (F-a, F-b, F-c)."
  - "Round 2 (2026-09-07, b91e5a83d) — B1 DISCHARGED, B3 DISCHARGED. B2's design DISCHARGED; its epoch instrument REFUSED, re-raised as B2-a."
  - "Round 3 (2026-09-07, 017ccf5a7) — B2-a DISCHARGED by derivation rather than the fallback minimum. O-8 applied; the AC19 ruling applied as given. B2-b raised: the derivation held under squash only."
  - "Round 4 (2026-09-07, aa30e23b0) — B2-b DISCHARGED. `--first-parent` + `%cI`, correct under all three permitted merge methods, with all three instantiated as suite arms and each flag carrying its own killing mutant. O-9 applied although twice ruled non-blocking. ALL FINDINGS CLOSED."
disposition: "DISCHARGED — fourteen artifacts reviewed across four rounds, all approved. Three blockers raised and closed (B1 privacy expectation set against the outcome; B2 contribution-triggered entry gating on membership rather than on when the signature was made; B3 an asserted contributor-facing state nothing produced), plus two successor findings on the temporal remedy's instrument (B2-a the hardcoded epoch, B2-b its merge-method dependence). Three defects were found and corrected by me during round 1 (PA-7 §(e)(ii) stated something false about §(d); PA-7 §(c) enumerated the roster narrower than the published notice; compliance-posture cited a section naming no processor). Nine observations recorded, none blocking. Every claim that carried a blocker was verified by execution rather than by reading — the derived epoch, the write path at rc=4, the merge-method matrix in throwaway repositories, and both killing mutants re-run independently here. The `removed_at` surface is clean at eleven sites and no live document asserts the superseded no-personal-data framing."
blocking_findings: []
required_before_merge: []
attests:
  - knowledge-base/legal/article-30-register.md (PA-7, all nine rows, as re-grafted onto main)
  - knowledge-base/legal/ccla-register.md
  - knowledge-base/legal/compliance-posture.md (Proton AG row)
  - docs/legal/corporate-cla.md
  - docs/legal/individual-cla.md
  - docs/legal/gdpr-policy.md (§3.4 third balancing test, §5.3b)
  - docs/legal/privacy-policy.md (§4.5, §10)
  - docs/legal/data-protection-disclosure.md (§2.3(d), §2.3(n), §6.4)
  - apps/web-platform/scripts/cla-evidence/schema.ts
  - apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts
  - apps/cla-evidence/scripts/ccla-add.sh
  - .github/workflows/cla.yml
  - CONTRIBUTING.md
carve_outs:
  - "NOT REOPENED — the 2026-09-04 ruling (B1-c, the permanent identity-field prohibition, encrypted-drive custody, amendment B1-c-2). Re-read in full at the start of this review and applied, not re-litigated."
  - "NOT ATTESTED — whether indefinite retention of the employer↔account association is proportionate under Art. 5(1)(e) on a non-erasable surface. Open at #7668 and correctly recorded as open at nine sites."
  - "NOT ATTESTED — the outbound correspondence leg to Pakistan. PA-7 §(e) records it as an OPEN ITEM tracked at #7846, no such transfer has occurred, and the reply is unsent."
  - "NOT ATTESTED — the Art. 28(3) instrument covering Proton AG. It does not exist; the corpus says so in three places and asserts nothing else. #7845."
  - "NOT ATTESTED — the merits of the Supabase importer-identity divergence (#7670), untouched here."
  - "NOT ATTESTED — a clean full-gate CI run on this tree. The author raised this themselves and did not treat this sign-off as substituting for it, which is the correct reading: this is a counsel review, not a green build. Targeted suites and every docs/legal gate were re-run here and pass; the full run is still owed before merge."
related:
  - knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md
  - knowledge-base/legal/audits/2026-09-counsel-review-7625.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/engineering/architecture/decisions/ADR-201-corporate-cla-is-a-repo-tracked-roster-not-an-allowlist-entry.md
re_evaluation_triggers:
  - "First arms-length (non-Jikigai-affiliate) corporate representative written to the roster — the Soleur-as-tenant-zero posture grounding a v1 internal attestation ends there."
  - "First counterparty that is a sole trader or trades under a natural person's name — amendment B1-c-2 has still never been exercised, and `docs/legal/corporate-cla.md` §0 states the rule for the register index and for the closing 'What is published' paragraph but not inside the coverage-map bullet (Finding O-3)."
  - "More than ten organisations on the register, or the first instrument that must be jointly auditable — the B1-b refusal at n=1 does not generalise."
  - "Any proposal to reinstate an identity field in a tracked file — that re-opens the 2026-09-04 ruling rather than changing a schema."
  - "Adoption of an Art. 5(1)(e) retention ceiling at #7668, or lapse/suspension/annulment of the EC adequacy decision for Switzerland."
  - "Any change to the ICLA §0 coverage-map paragraph — B2's residual population is defined by reference to the version of that paragraph, so a further amendment creates a further cohort."
  - "THE FIRST ENTRY ADDED TO `DIRECT_NOTICE_GIVEN`. The set is the named-residual remedy and nothing validates its `register_ref` — an empty string unblocks a write exactly as a real citation does (O-9). Harden it before the first use, not after."
---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**

# Counsel review audit — #3210 / PR #7828

## Scope and method

The 2026-09-04 CLO ruling (`2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`,
APPROVED, disposition DISCHARGED) settled siting (B1-c: the register is an INDEX, the executed
instrument is the EVIDENCE), the permanent prohibition on identity fields, custody on the encrypted
operator drive, and amendment B1-c-2. **That ruling is applied here and is not re-litigated.**

What is reviewed here is what changed *after* it: `origin/main` moved — #7625 and #7803 rewrote five
PA-7 rows, including replacing `Special categories | None.` with a full Art. 9 analysis and splitting
the Art. 6(1)(f) balancing to record a non-signer commenter capture failing on necessity — and the
#3210 annotations were re-grafted **on top of** that newer text. A re-graft is exactly the operation
that produces prose which agrees with itself and disagrees with the record, so the method was:

1. Read PA-7 in the working tree as it now stands, all nine rows, not the diff. The diff does not
   show the row a reader will read.
2. Read every cross-referenced surface end to end: both CLA instruments, GDPR Policy §3.4 and §5.3b,
   Privacy Policy §4.5 and §10, DPD §2.3(d)/(n) and §6.4, `ccla-register.md`, `compliance-posture.md`.
3. Check every implementation-detail claim against the implementation — `schema.ts`,
   `roster-entry-gate.ts`, `validate-roster.ts`, `ccla-add.sh`, `roster-entry-gate.test.ts`,
   `roster-schema.test.ts`, `cla.yml`, `cla-evidence.yml`, `CONTRIBUTING.md` — because prose
   hallucinated against the code is the known drift class of PR #4353 / #4558.
4. Run all five `docs/legal/**` gates plus `lint-legal-registers.sh`, and then **read the prose
   anyway**, because per #7349 all five gates compare the two surfaces against each other and none
   asks whether the agreed text is true.

## Per-artifact verdicts

| Artifact | Verdict |
|---|---|
| `knowledge-base/legal/article-30-register.md` PA-7 (nine rows, re-grafted) | **APPROVED as corrected.** One false sentence found in §(e) and one under-inclusive enumeration in §(c); both corrected in this review (§Corrections applied). The restated Lawful-basis opening is accurate — see Q1. |
| `docs/legal/gdpr-policy.md` §3.4 third balancing test | **APPROVED.** The governing record. Substantively the strongest document in the set: it carries the sole-trader rule for the map, states erasure-impossibility as a premise rather than a mitigation, and refuses to rest any limb on retractability. |
| `docs/legal/gdpr-policy.md` §5.3b | **APPROVED.** Article-by-article, and the Art. 17 subsection states the negative (17(3)(b) unavailable) rather than leaving an impression that the ground is held. |
| `docs/legal/privacy-policy.md` §4.5 / §10 | **APPROVED SUBJECT TO B2.** The field enumeration is the most complete in the corpus. "You are told before any record about you exists" is the sentence B2 bites on. |
| `docs/legal/data-protection-disclosure.md` §2.3(d)/(n), §6.4 | **APPROVED.** §2.3(n)'s scoping note ("this clause read 'For each signature…' while §2.3(d) described a single record type. It now describes two, and only the first reaches this archive") is precisely the kind of correction the #7349 lesson exists to produce. |
| `docs/legal/corporate-cla.md` | **APPROVED.** §0's two-answer erasure passage is correct and is the one place the corpus refuses to offer a single procedure that covers neither surface. One symmetry observation at O-3. |
| `docs/legal/individual-cla.md` §0 | **APPROVED SUBJECT TO B2.** The new paragraph is the Art. 13 notice the whole design rests on. Its "We tell You this here, at the moment You sign" is the second sentence B2 bites on. |
| `knowledge-base/legal/ccla-register.md` | **APPROVED.** Schema carries no identity field, states the prohibition as permanent rather than gated, and carries the sole-trader rule. |
| `knowledge-base/legal/compliance-posture.md` Proton AG row | **APPROVED as corrected.** Characterisation right (Q2); one citation corrected. |
| `apps/web-platform/scripts/cla-evidence/schema.ts` | **APPROVED.** `.strict()` at all four levels, `legal_name` nullable, `login` bounded at 39, no free-text field, and the reason each of those holds is in the file. |
| `apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts` + tests | **BLOCKED — B2.** The gate is well built (refuses an unusable reference set rather than degrading to an empty one, collects every offender, and the suite cross-checks the *tracked* roster against the *real* ledger with a working anti-vacuity arm). What it does not test is *when* the signature was made. |
| `apps/cla-evidence/scripts/ccla-add.sh` | **BLOCKED — B2** (same gap, write side). Otherwise the strongest script in this PR: test seams refused off the dry-run path, absolute-path resolution, withdrawal dates never rewritten, ids resolved numerically rather than by login. |
| `.github/workflows/cla.yml` `custom-notsigned-prcomment` | **BLOCKED — B1 and B3.** |
| `CONTRIBUTING.md` | **BLOCKED — B1 and B3.** The CCLA §5 coverage statement itself is accurate (Q-extra below). |

## The five questions asked, answered

### Q1 — Do the re-grafted PA-7 rows state anything false after the merge?

**One sentence, in §(e), now corrected. §(d)'s "unchanged by THIS LIMB" is true. The restated
Lawful-basis opening is accurate.**

**§(d) — true.** Limb (i) now reads "…**no new processor and no new third-country transfer arises**,
and §(e) is unchanged by THIS LIMB (limb (iii) below adds a Swiss processor — see §(e))." Checked
against the cell it sits in: limb (i) is the coverage map, which engages no processor beyond GitHub
Inc and adds no third country; limb (iii) is Proton AG, which does. The scoping is correct and the
cross-reference resolves.

**§(e) — the correction made §(e) false, and that is the one falsehood in the row.** §(e)'s
2026-09-04 amendment, limb (ii), opened: *"§(d) added Proton AG as a processor … and stated that §(e)
was unchanged by that amendment. That statement is correct as to the coverage map and incomplete as
to Proton AG, and is corrected here rather than left standing."* §(d) as it now stands says no such
thing — it says the opposite, scoping the statement to its own limb (i) and pointing here. A cell
was describing a sibling cell inaccurately, and "corrected here rather than left standing" described
correcting text that no longer stands. **Restated during this review** (§Corrections applied, F-a).

**The Lawful-basis restatement — accurate, verified clause by clause.** It reads: *"limbs (i)-(iv)
above are true of the SIGNER. The #7625 correction above already records that they do not reach the
non-signer commenter capture; they equally do not reach a CORPORATE REPRESENTATIVE…"*

- *"limbs (i)-(iv) above are true of the SIGNER"* — matches the cell's own opening, which scopes the
  balancing to "shapes (1) and (2) **where the actor is a signer**".
- *"The #7625 correction above already records that they do not reach the non-signer commenter
  capture"* — the #7625 block does record exactly that: "the balancing is split: it holds for signers
  and is unavailable for the non-signer capture recorded at §(c), where it fails on necessity", and
  the body carries the same finding under the heading "**The balancing test does not reach the
  non-signer capture.**" The restatement uses #7625's own verb. **It does not misdescribe #7625's
  finding.**
- *"they equally do not reach a CORPORATE REPRESENTATIVE"* — true, and the sentence then names which
  limbs fail and why (i: the representative discloses nothing by the signatory's act; iii: the
  representative is not present at the signing event). Recorded as observation **O-1** only because
  "equally" glosses two different failure modes — necessity for the commenter, limbs (i)/(iii) for
  the representative — which the sentence then distinguishes, so it misleads no reader who finishes it.

**One further defect found in the same row and corrected:** §(c) `Categories of personal data`
enumerated the roster narrower than the notice published to the data subject (F-c below).

### Q2 — Is the Proton AG characterisation right?

**Yes, on all three limbs.**

- **Processor, not "no recipient".** PA-7 §(d)(iii) records it as a recipient/processor with the
  measurement behind it (MX, SPF, the verification TXT), measured rather than assumed by analogy with
  `ops@soleur.ai` — which is the failure class #7624 exists to correct and which this discharges.
- **Swiss adequacy as a *mechanism*, not as a finding that no transfer occurs.** §(e)(ii) gets the
  doctrine right and says so explicitly: "An adequacy decision is the *mechanism* by which a transfer
  to it is lawful, not a finding that no transfer occurs, and Art. 30(1)(e) requires the third country
  to be identified wherever transfers take place." It then applies the cell's own importer-identity
  test to Proton AG rather than exempting it — the consistency this register exists to enforce. It
  also records adequacy revocation as a re-evaluation trigger.
- **Art. 28(3) recorded as NOT EXECUTED, open, and never asserted as covered.** Three sites agree:
  the `compliance-posture.md` vendor row ("NOT EXECUTED — no Art. 28(3) instrument recorded … Tracked
  at #7845"), PA-7 §(d)(iii) and PA-7 §(e)(ii), the last of which says in terms that adequacy does
  not discharge Art. 28. The row's claim that Proton "carried no row in this table at all — not
  PENDING, absent" was **verified against `origin/main`**: one mention, in a 2026-06-11 HTML comment,
  and no vendor row.
- **One citation defect, corrected here (F-b):** the row cited `gdpr-policy.md` §3.5 as where Proton
  is named for `legal@jikigai.com`. §3.5 states the lawful basis for legal-inquiry handling and names
  no processor. Proton is named at §4 (third-party disclosure table) and §11 (breach scenarios).
  Corrected in the shape of the §3.3→§2.2 correction already in PA-7 §(e).

### Q3 — Is `removed_at` consistently a withdrawal-of-designation marker and NOT erasure?

**Yes. This is the cleanest thing in the PR, and it is clean at eleven sites.** No false erasure claim
exists anywhere in the corpus. Enumerated, because "I checked" is not a finding:

| Site | What it says |
|---|---|
| `schema.ts` `RosterRepresentativeSchema.removed_at` doc comment | "Withdrawal-of-designation marker. NOT erasure, and it must never be described as one" |
| `ccla-register.md` schema table, `Withdrawn at` row | "A **withdrawal-of-designation marker**, not erasure" |
| `ccla-register.md` Notes | "They are not erasure and must never be described as erasure, in this file, in a data-subject response, or in any published document" |
| `corporate-cla.md` §0 | "That is a withdrawal-of-designation marker. It is not erasure, We will not describe it as erasure" |
| `corporate-cla.md` §5 | "Recording a withdrawal is **not erasure** and We will not present it as erasure" |
| `individual-cla.md` §0 | "A withdrawal of designation is recorded as a date against the entry and is not erasure" |
| `gdpr-policy.md` §3.4 limb (3) | "It is a withdrawal-of-designation marker. It is not erasure … and it must not be described or relied on as erasure" |
| `gdpr-policy.md` §5.3b | "The `removed_at` field is not erasure … it must not be relied on as though it did" |
| `privacy-policy.md` §4.5 | "it is a withdrawal-of-designation marker, it is not erasure, and we will not describe it as one" |
| `data-protection-disclosure.md` §2.3(d) | "`removed_at` is a **withdrawal-of-designation marker and not erasure**, which no document may describe as one" |
| `article-30-register.md` PA-7 Lawful basis, §(d)(i), §(f) | all three, in terms |

Two further checks passed. **The word "tombstone" is kept off this surface** — the ruling's naming
instruction — and appears in the roster path nowhere; it is reserved for `tombstones/<sha>.deleted.json`
on the R2 evidence path, where it does mean something erasure-shaped. And the **ICLA's own erasure
paragraph was re-scoped** rather than left to be read across: "**That procedure reaches Your signature
record only.** It does not reach the corporate coverage map described above." PA-7 §(f) does the same
in the internal record, and explicitly withdraws the citation it used to rest on: "The citation above
must not be read across either: `corporate-cla.md` Section 0 … no longer supports the sentence that
cites it, for this population."

### Q4 — Does anything still assert that the coverage map contains no personal data?

**No. Nothing live.** A repository-wide search for the superseded framing returns three classes of
hit, all correct:

- the **archived** plan and spec, where spec AC3 is explicitly marked *(SUPERSEDED 2026-09-04 — see
  FR1.)* and the plan carries the finding `GDPR-Art-6 — B2: "the coverage map contains no personal
  data" is false`;
- **ADR-201**, which records the framing as "a category error";
- every live document stating the corrected characterisation affirmatively — PA-7 §(c) ("NOT 'no
  personal data', which is how it was framed at KD13 of the plan and is false"), gdpr-policy §3.4
  ("it is not correct to say that it contains no personal data, and we do not say so"),
  privacy-policy §4.5 ("**This record is personal data, and we do not say otherwise.**"), DPD
  §2.3(d), corporate-cla §0 ("**is personal data** about the representative, notwithstanding that a
  GitHub login is public on its own").

Section 3 of the ruling is fully implemented.

### Q5 — Is the Art. 13 (not Art. 14) posture stated consistently, and does contribution-triggered entry support it as implemented?

**Stated consistently: yes, at five sites, in identical terms.** ICLA §0, gdpr-policy §3.4 limb (3),
privacy-policy §4.5, DPD §2.3(d) and PA-7 §(c) all say the duty is discharged directly, at or before
record creation, under Art. 13 rather than under the Art. 14 indirect-collection regime.

**Supported as implemented: for every future signer, yes. For two enumerable existing accounts, no —
this is B2.** And the notice chain the posture rests on is weakened by this PR's own copy — B1.

The mechanism itself is genuinely built, and built better than the prose claims:

- **Two enforcement sites, both real.** `ccla-add.sh` refuses at the write path before a branch
  exists (exit 4), and `validate-roster.ts` re-runs the same module over the whole roster before
  anything is written or pushed. CI runs the same implementation, not a shell reimplementation.
- **The CI arm is not vacuous** — the specific trap the session's own learning
  (`2026-09-04-every-verification-i-wrote-passed-and-three-of-them-proved-nothing.md`) warns about.
  `roster-entry-gate.test.ts` reads the **tracked** roster and the **real** `origin/cla-signatures`
  ledger, fetches the ref shallowly rather than skipping when it is absent, refuses an empty or
  malformed reference set rather than passing everything, and carries a second arm that feeds the
  real ledger a known-unsigned id (2 147 483 646, verified absent) so the cross-check is proven to
  bite **today**, while the tracked roster is still empty. That is the arm most such suites omit.
- **The reference set is keyed on numeric id, not login**, so a renamed account cannot inherit a
  stranger's signature — correct, and the reason is in the code.
- **Self-authorisation is closed structurally**: `cla-evidence.yml` checks out
  `github.event.pull_request.base.sha` and never the PR head, so a contributor cannot authorise
  themselves by editing the roster in the pull request the roster governs. PA-7 §(g)(4) correctly
  records CODEOWNERS as **designed and not in force** and says in terms that it "must not be counted
  as the self-authorization control; the base-ref read is." Verified: no ruleset enforces CODEOWNERS.

**Doctrinal observation, non-blocking (O-2).** "Art. 13, not Art. 14" is a characterisation a
supervisory authority could contest, because the employer association is in fact obtained from the
employer, and Art. 14 applies where data have not been obtained from the data subject. The *outcome*
is unimpeachable either way — notice is delivered directly, to the subject, before the record exists,
which exceeds Art. 14(3)(a)'s one-month outer limit and independently engages Art. 14(5)(a) — so
nothing turns on it in practice. The safer formulation, which costs one clause, is that the design
satisfies Art. 13 timing directly and that Art. 14 is in any event discharged before collection.
This is the item I would most want external counsel to confirm.

### Q-extra — the two copy accuracy checks that were asked for

**ICLA §4(a) vs the bot comment: accurate.** §4(a) as drafted reads: "*If Your employer(s) has rights
to intellectual property that You create that includes Your Contributions, You represent that You
have received permission …, that Your employer has waived such rights …, or that Your employer has
signed a Corporate Contributor License Agreement with Us and has designated You as an Authorized
Representative under it.*" The bot's three-limb disjunction reproduces all three limbs correctly and
in the right disjunctive relation.

The one risk in that copy is over-blocking rather than misstatement: §4(a)'s employer representation
is **conditional** on the employer having rights in the work, and the bot's "*If none of the three is
true for you, or you are not sure, tell us at <legal@jikigai.com> instead of signing*" would, read
alone, tell a contributor whose employer has no rights at all not to sign. It does not stand alone —
the paragraph closes "*None of the above applies if you are contributing your own work on your own
time. In that case the one line at the top is genuinely the whole ask*", which is the antecedent-fails
case. **No fix required.** (The mid-paragraph gloss "*Most contributors are already covered by the
first — an open-source contribution policy, or work that simply is not your employer's*" is loose:
work that is not the employer's is the antecedent failing, not "permission received". Cosmetic.)

**CONTRIBUTING.md's "coverage runs through the Authorized Representative list (CCLA §5)": accurate.**
CCLA §2 and §3 grant licences over "Contributions submitted by Your Authorized Representatives"; §1
defines the term; §5 is the management clause and does say the additions come by email to
`legal@jikigai.com` from the signatory. Coverage does run through the list, not through the company
at large, and a colleague is added by that route. Verified against §§1, 2, 3, 5.

## Blocking findings

> **Round 1, preserved unaltered as the audit trail.** EVERY finding in this section, and the two
> successors B2-a and B2-b, are DISCHARGED as of commit aa30e23b0. §Round 4 is the current record;
> this section and §§Re-review / Round 3 must not be read as descriptions of the tree as it now stands.

### B1 — the pre-signature comment sets the privacy expectation in the wrong direction

**Artifact:** `.github/workflows/cla.yml`, `custom-notsigned-prcomment`; and the mirrored paragraph in
`CONTRIBUTING.md`.

**The sentences:**

> **Email that to <legal@jikigai.com> rather than posting it here**, unless you would rather it were
> public. This thread is world-readable and permanent, and who you work for is yours to disclose or not.

and its CONTRIBUTING.md counterpart:

> Email rather than the pull request thread, unless you would rather it were public -- the thread is
> world-readable and permanent, and who you work for is yours to disclose or not.

**Why this blocks.** The comment recommends the Corporate CLA route, and it protects the employer's
identity from the pull-request thread on the express ground that it is the contributor's to disclose
or not. The successful outcome of that very route — employer signs, designates the contributor, the
contributor signs the ICLA — **publishes exactly that association, permanently, in a file on the
default branch of a public repository, from which the same corpus says four times over that erasure
is not available.** Nowhere in the comment, and nowhere in `CONTRIBUTING.md`, is that said. The
contributor learns it only from ICLA §0 — the document the same comment invites them not to read
("*Read the Individual Contributor License Agreement first if you would like to*").

This is not a drafting nit. It is the one place in the corpus where a data subject's expectation is
actively set in the opposite direction from the outcome, at the moment before they act, and it
undercuts the notice limb (limb (iii)) on which PA-7's Lawful-basis cell and gdpr-policy §3.4 both
rest. The register's own limb (iii) reasons that the sign phrase "*is an attestation of having read
that document*" — an attestation this copy tells the contributor is optional.

**The fix (one sentence, both surfaces).** In the Corporate-CLA paragraph, before the email
instruction, add substantially:

> One consequence to know before you sign: if your employer does sign a Corporate CLA and names you
> under it, we publish the fact that your GitHub account is covered by that employer's agreement in a
> public file in this repository, and we cannot erase it afterwards. Section 0 of the Individual CLA
> sets out exactly what that entry contains and what it does not.

Either drop "*first if you would like to*", or leave it and amend PA-7 Lawful-basis limb (iii) to stop
describing the sign phrase as an attestation of having read the document. **Do not do neither.**

### B2 — contribution-triggered entry gates on membership, not on when the signature was made

**Artifacts:** `apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts`
(`assertContributionTriggeredEntry`) and `apps/cla-evidence/scripts/ccla-add.sh` (Guard 3, write side).

**The gap.** Both check `id ∈ ledger.signedContributors`. Neither looks at `created_at`, and neither
looks at which version of `docs/legal/individual-cla.md` the signature was made against — although
the evidence record pins exactly that in `cla_doc.content_sha256`, so the fact is available.

**The measured consequence.** `origin/cla-signatures:signatures/cla.json` today contains exactly two
accounts:

| login | id | `created_at` |
|---|---|---|
| `deruelle` | 54279 | 2026-02-27T09:53:45Z |
| `Elvalio` | 92384917 | 2026-05-04T13:13:53Z |

The ICLA §0 paragraph "**If Your employer has signed a Corporate Contributor License Agreement**" —
the Art. 13 notice this entire design rests on — was **added 2026-09-04 by this PR**. Both accounts
signed against an ICLA that did not contain it. Both pass the gate today. Either can be written to
the roster by `ccla-add.sh` right now.

**The sentences that would then be false.** Four, all unconditional:

- `gdpr-policy.md` §3.4 limb (3): "*contribution-triggered entry means no designation ever produces a
  published record before the representative has themselves acted here **and been informed here***".
- `privacy-policy.md` §4.5: "**You are told before any record about you exists.**"
- `individual-cla.md` §0: "*We tell You this here, at the moment You sign*".
- PA-7 Lawful basis, population (B): "*limbs (i) and (iii) become true of that person, at the moment
  the record is created, rather than being assumed of them*".

For a pre-notice signer, limb (iii) does **not** become true at the moment the record is created. They
acted here; they were not informed here. The ruling's own consequence 3 — "*every person in the map
has been informed directly, here, at or before the moment their record was created*" — is what the
implementation does not yet guarantee.

**The fix — either is acceptable, both are cheap.**

1. *Gate it.* Add a date/version condition to `assertContributionTriggeredEntry` **and** to
   `ccla-add.sh`'s write-side loop (both, for the reason `roster-entry-gate.ts` already gives in its
   own header): refuse an account whose ledger `created_at` precedes the commit that introduced the
   ICLA §0 coverage-map paragraph, unless an explicit `--notice-given-at` is supplied. Cover it with a
   mutation arm in `roster-entry-gate.test.ts` in the shape of the existing G3-M arms.
2. *Record it.* Add a **named, enumerated residual** — the population is two accounts, both listed
   above, one of them the controller's own operator — plus an operator step giving direct notice
   before such a row is written, and qualify the four sentences above ("*for a representative who
   signed before this notice was published, we give the notice directly before the entry is made*").

The corpus already has the convention for option 2: PA-7 §Special categories carries a "**Named
residual (accepted at present scale, not as a steady state)**" block of exactly this shape. What is
not acceptable is leaving four unconditional sentences standing over an implementation that does not
enforce them.

### B3 — an asserted contributor-facing state that nothing produces

**Artifacts:** `.github/workflows/cla.yml` `custom-notsigned-prcomment`; `CONTRIBUTING.md`.

**The sentence:**

> **While a Corporate CLA of yours is in flight** — and only then — this PR carries the state
> **"CCLA in progress — maintainer action, not yours"**.

**Why this blocks.** Nothing produces that state. Verified: no such label exists in the repository
(`gh label list` — the command works and returns the label set; no CCLA label is in it); no workflow
step adds a label, sets a commit status or posts a conditional comment (`cla.yml` and
`cla-evidence.yml` contain no `addLabels`, no `gh pr edit`, no `statuses/` call); and a
repository-wide search for the string finds it only in the two copy surfaces, the brainstorm, the
archived plan (AC19) and the archived tasks file. Task 1.3 is ticked `[x]`; plan AC19 — "*Where a CCLA
is in flight, the PR carries a visible "CCLA in progress — maintainer action, not yours" state*" —
has no verification evidence anywhere in the spec directory. The sentence is also conditional
("*while … and only then*"), so the comment that carries it cannot itself be the carrier: it is posted
to every unsigned contributor regardless.

This is the defect class the corpus already handles by retraction — #6588 retracted four published
Art. 32 measures "**as statements about the platform as it runs today**", and PA-7 §(g)(4) applies the
same convention to CODEOWNERS in this very PR. The same convention has to reach contributor-facing
copy.

**The fix.** Either implement the state (a label applied by the maintainer, or by a step keyed on a
label the maintainer sets), or reword both surfaces to what actually happens — e.g. "*we will say so
on the pull request, and it is reviewed and merged on its merits in the meantime*". If AC19 is
deferred rather than met, deferral needs an issue, and task 1.3 should not stay ticked.

## Corrections applied during this review

Three defects were unambiguous, internal to the knowledge-base records, and carried no fork for the
owner to decide, so they were repaired here rather than handed back. All three are in files outside
`docs/legal/**`, so no mirror-pair, SHA-pin or heading-parity gate is engaged by them.

**F-a — `knowledge-base/legal/article-30-register.md`, PA-7 §(e), 2026-09-04 amendment, limb (ii).**
The opening described §(d) as stating that §(e) was unchanged by that amendment. §(d) as it now stands
says the opposite. Restated to describe §(d) as it reads, with the earlier draft's wording preserved as
the audit trail and a dated `[2026-09-07 RESTATEMENT]` marker, per the register's amendment-history
convention. **This is the answer to Q1's "anything false".**

**F-b — `knowledge-base/legal/compliance-posture.md`, Proton AG row.** Cited `gdpr-policy.md` §3.5 as
where Proton is named for `legal@jikigai.com`. §3.5 ("Legal and GDPR Inquiry Handling") states a
lawful basis and names no processor; the disclosure is at §4's third-party table and at §11. Citation
corrected and the correction dated inline, in the shape of the §3.3→§2.2 correction already recorded
in PA-7 §(e).

**F-c — `knowledge-base/legal/article-30-register.md`, PA-7 §(c) Categories of personal data.** The
`ADDED CATEGORY` enumeration of the roster listed "GitHub account identifier, the employing
organisation, `authorized_from`, `removed_at`, the SHA-256 of the Corporate CLA text executed, and the
SHA-256 of the executed instrument" — silent on `record_ref`, on the organisation's `signed_at`, on
`cla_doc.path` / `cla_doc.git_sha`, and on the `login`/`id` distinction. **All four are enumerated in
the notice published to the data subject** (Privacy Policy §4.5 and DPD §2.3(d)), so the internal
governing record was narrower than the published notice — which is the precise defect #7625 recorded
against this same cell four days earlier ("*the wrong direction for the two to differ*"). Completed at
field level against `RosterSchema`, with the prior text preserved and a dated `[2026-09-07 COMPLETION]`
marker.

## Findings recorded, not blocking

**O-1 — "equally do not reach" glosses two different failure modes.** PA-7 Lawful basis, #3210
correction. For the non-signer commenter the balancing fails at limb (ii) on necessity; for the
corporate representative it fails at limbs (i) and (iii) while necessity is *satisfied* (via
contribution-triggered entry, per the third balancing test). The sentence names both failures
explicitly a clause later, so no reader who finishes it is misled. Left as drafted.

**O-2 — the Art. 13 / Art. 14 characterisation.** See Q5. Outcome unimpeachable, label contestable,
one clause would settle it. The item for external counsel.

**O-3 — the sole-trader rule is stated for the register index but not inside the coverage-map bullet.**
`corporate-cla.md` §0's coverage-map bullet says the map records "the employing organization" and "**no
name, no title, no email address and no postal address**", and the closing "What is published and what
is not" paragraph applies the B1-c-2 carve-out only to the register index. The carve-out **is** carried
for the map by `gdpr-policy.md` §3.4 limb (2), by `privacy-policy.md` §4.5, by `ccla-register.md` and by
the nullable `legal_name` in `RosterSchema`, and the coverage-map bullet does enumerate `record_ref`,
so a reader of the whole §0 can reach the rule. Not a falsehood; an asymmetry. One clause in the
coverage-map bullet would remove it, and B1-c-2's first exercise is already a frontmatter re-evaluation
trigger.

**O-4 — `ccla-add.sh remove` inherits the whole-roster gate.** The write-side Guard 3 loop is
deliberately scoped to `add`, with a good reason recorded in the file ("*the more broken the ICLA
record is, the harder it becomes to revoke an ex-employee's authorization*"). But `validate-roster.ts`
still runs `assertContributionTriggeredEntry` over the entire new roster before a withdrawal is
written, so a degraded ledger blocks a `remove` anyway — the scoping does not achieve what its comment
says it achieves. Engineering, not legal, and it fails closed rather than open.

**O-5 — §4(c) vs §5 citation.** PA-7, `ccla-register.md` and gdpr-policy §3.4 cite the designation list
to CCLA **§4(c)** (the representation that the list has been provided); `CONTRIBUTING.md` and
`corporate-cla.md` §0 cite **§5** (the management clause) and `§1` for the no-cut-off coverage, which
in the instrument sits in the preamble rather than in §1. All defensible, none contradictory. Recorded
so a later reader does not re-derive it.

## What was verified and found sound

- **Every one of the five `docs/legal/**` gates, plus the register lint, run in this worktree:**
  scope-block placement `0 violations`; mirror drift `9 pairs checked, drift is within the baseline`;
  `check-tc-document-sha.sh` exit 0; `lint-legal-registers.sh` `7 assertions, 0 failed`. Per #7349 that
  is agreement, not truth, which is why the prose was read anyway — and why F-a, F-c, B1, B2 and B3 all
  sit past a fully green run.
- **Mirror parity of the #3210 prose**, checked directly rather than trusted to the ratchet: the added
  text in `privacy-policy.md` and `data-protection-disclosure.md` is byte-identical between canonical
  and mirror; `individual-cla.md`, `gdpr-policy.md` and `corporate-cla.md` are identical after
  normalising the mirror's `/legal/<doc>/` link rewriting, which is the mirror's own convention. **The
  mirror is the published surface**, so a canonical-only edit here would have changed nothing a user
  sees; none occurred.
- **The Art. 13 notice URL resolves.** `cla.yml` posts
  `https://soleur.ai/pages/legal/individual-cla.html`. That is a legacy path, but it is redirected in
  two independent places — `plugins/soleur/docs/_data/pageRedirects.js` and the Cloudflare bulk
  redirect at `apps/web-platform/infra/seo-bulk-redirects.tf` — to `/legal/individual-cla/`, and
  `_site/pages/legal/individual-cla.html` is also built. The notice chain is not broken by the URL.
- **The schema prohibition is structural, not a denylist.** `.strict()` at all four levels, asserted
  by `roster-schema.test.ts` at each of them including "an undeclared key nobody would denylist"; the
  drafted operator `notes` field was removed and its absence is asserted; `login` is bounded at 39
  characters because "an unbounded string is a place to put something that is not a login, on a surface
  from which nothing can be erased". `legal_name` is nullable, and B1-c-2 has its own test.
- **The tracked roster is empty** (`{"schema_version":"1.0","organizations":[]}`), so no live
  disclosure of any real person exists on this surface today. B2's exposure is prospective; B1's is
  live from the moment the workflow copy lands.
- **The withdrawal path refuses to rewrite a recorded date** ("*a recorded withdrawal date is the
  operative one and is not rewritten*"), refuses a second live designation of the same id, and refuses
  more than one `--login` per `remove` so a partial write cannot be reported as complete. All three are
  the right defaults for a legal record.
- **PA-7 §(e)'s open items are open, not asserted:** the Pakistan outbound leg (#7846, reply unsent,
  `status: awaiting-operator-send`), the Supabase importer-identity divergence (#7670, expressly not
  decided), #7668 retention. None is dressed up as discharged.

## What this review could not resolve

- **Whether external counsel accepts the Art. 13 characterisation (O-2).** Nothing in the repository
  can settle it; the compliant outcome does not depend on it.
- **Whether the Art. 28(3) instrument with Proton AG can be obtained on Proton's standard terms.**
  Recorded as absent at three sites and tracked at #7845. Correctly not asserted; simply unknown.
- **Whether `Elvalio` (92384917) is or could be a corporate representative.** Unknowable from here, and
  irrelevant to B2: the gate permits the write regardless, which is the finding.
- **Whether B3's fix is "implement" or "reword".** That is a product decision about a promise made to
  contributors, and it is the owner's, not counsel's. Both discharge the accuracy defect.

## Verification

```
gh issue view 3210 --json state          -> OPEN
gh pr view 7828 --json state,headRefName -> OPEN, feat-ccla-signing-mechanism
bash scripts/lint-legal-scope-block-placement.sh --base origin/main
                                         -> 0 scope block(s) classified, 0 violations
bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main
                                         -> 9 pair(s) checked, drift within baseline
bash apps/web-platform/scripts/check-tc-document-sha.sh          -> exit 0
bash scripts/lint-legal-registers.sh     -> 7 assertion(s), 0 failed
git show origin/cla-signatures:signatures/cla.json
                                         -> 2 signers: deruelle/54279/2026-02-27,
                                            Elvalio/92384917/2026-05-04
gh label list                            -> no CCLA label (command functional; label absent)
git show origin/main:knowledge-base/legal/compliance-posture.md | grep -ci proton
                                         -> 1 (an HTML comment; no vendor row) — confirms
                                            "not PENDING, absent"
cat apps/cla-evidence/roster/ccla-roster.json
                                         -> {"schema_version":"1.0","organizations":[]}
```

## Re-review — commit b91e5a83d (2026-09-07)

Everything below was checked against the shipped code and the shipped copy, not against the commit
message. The commit message is accurate in every claim I tested; three of its claims I tested by
running them rather than reading them, and one of those produced the finding that keeps this BLOCKED.

### B1 — DISCHARGED

The new paragraph does what I asked and slightly more. The consequence is now stated **in the comment
body**, before the sign line, rather than left behind a link:

> **What happens if that Corporate CLA is signed.** Once your employer executes one and names you
> under it, we publish an entry linking your GitHub account to that organisation in a public file in
> this repository … the account-to-employer association is itself personal data about you, it is
> created only at or after you sign the line above, and once written it is copied into every clone and
> fork and **cannot be erased**. Section 0 of the Individual CLA is the full notice, and it is worth
> reading before you sign rather than after.

Checked clause by clause against the artifact and the corpus, because "does not overstate what the
roster holds" was the question asked:

- *"an entry linking your GitHub account to that organisation"* — matches `RosterRepresentativeSchema`
  plus `RosterOrganizationSchema.legal_name`. Not overstated.
- *"carries no name, no email and no postal address"* — matches the corpus formula used at ICLA §0,
  corporate-cla §0, privacy-policy §4.5 and DPD §2.3(d), all of which read the "no name" as being about
  the representative's identity fields. It drops "no title" from the standard four; a simplification,
  not an overstatement. The sole-trader asymmetry at **O-3** is unchanged and is unaffected by this.
- *"is itself personal data about you"* — matches the corrected Art. 4(1) framing exactly, and does not
  slip back toward the KD13 category error.
- *"created only at or after you sign the line above"* — true, and as of this commit actually enforced
  in both directions rather than only on membership.
- *"copied into every clone and fork and cannot be erased"* — matches gdpr-policy §5.3b and
  privacy-policy §4.5. Correctly does **not** offer `removed_at` as a remedy.

**Nothing is overstated and nothing is understated.** This is a stronger discharge than the one I
specified: I asked for the consequence to be named; putting it in the comment body rather than behind
the ICLA link means the corporate-representative population is informed by the comment itself, which
is what limb (iii) of PA-7's Lawful-basis cell needs and what the link alone could not guarantee.

The sub-item I attached to B1 — the surviving *"Read the Individual Contributor License Agreement
first if you would like to"* against a sign phrase that reads "I have read the CLA Document" — is
**downgraded to observation O-6, not carried as a blocker**, and I want to be explicit that this is a
reassessment rather than a softening. It no longer carries blocking weight for two reasons that did
not hold before this commit: the disclosure that mattered moved *into* the comment, so the notice no
longer depends on the link being followed; and Art. 13 requires information to be **provided**, not
proof that it was read, so limb (iii) — whose claim is that the signer "is informed before signing"
via the comment and §0 — is not falsified. The sign phrase remains an attestation; the copy merely
declines to insist on the reading behind it. See O-6 for the one-clause close.

### B3 — DISCHARGED

Both surfaces now read *"While a Corporate CLA of yours is in flight, your pull request is reviewed and
merged on its merits exactly as any other … the corporate side never gates your merge."* Verified true:
the only merge-gating check on the CLA path is `license/cla`, which tests the **Individual** signature;
no workflow, ruleset or check keys on the Corporate CLA or on the roster's contents for a contributor's
own pull request. **Removing the claim rather than building a label to justify it is the right call** —
it is the #6588 convention applied to contributor-facing copy, and the same convention this PR already
applies to CODEOWNERS at PA-7 §(g)(4).

### B2 — design DISCHARGED, instrument REFUSED (re-raised as B2-a)

Everything I asked for is present, and the parts I asked to check rather than take on trust all hold.

| Property asked for | Verified how | Result |
|---|---|---|
| Fails CLOSED on absent or unparseable `created_at` | read the code (`Number.isFinite` on a `Date.parse`, `Number.NaN` for a non-string) and ran both arms | **holds** |
| Refusal names the temporal ground, never reads as "no signature" | the message, plus the suite's `expect(msg).not.toContain("have no Individual CLA signature")` — an assertion on the *negative*, which is the one that actually separates two throws of the same error type | **holds** |
| Membership checked before temporality | code order plus its comment; an unsigned account is still reported as unsigned | **holds** |
| Both sites, without a second implementation | `ccla-add.sh` runs `validate-roster.ts`, which calls this module, **before** it creates a branch, commits or pushes; the shell suite's new arm asserts rc=4 and greps the temporal message | **holds — and refusing to hand-write a shell copy was correct.** A second copy is the drift the shared implementation exists to prevent, and the write path still refuses *before anything is written*, which is the property B2 actually required. This is not "insufficient for both sites"; it is the better construction of both sites. |
| `DIRECT_NOTICE_GIVEN` is a residual, not a bypass | empty, typed `{id, register_ref}`, documented | **holds as far as types go** — see O-9 for what is not enforced |
| The epoch parses | the suite's own arm | **holds** |
| The epoch is a FLOOR | — | **does not hold. This is B2-a.** |

The suite asserts the epoch *parses*. Nothing asserts it is **not earlier than the moment the notice
actually landed**, which is the only property that makes it a floor. Reproduced against the shipped
module, in this worktree:

```
A  created_at 2026-09-09T10:00:00Z  ->  ACCEPTED  (1 account checked)
B  created_at 2026-09-07T18:00:00Z  ->  REFUSED   ("signed … before the notice existed")
C  ledger [null, {...}]             ->  TypeError: Cannot read properties of null (reading 'id')
   epoch = 2026-09-08T00:00:00Z ; wall clock at review = 2026-09-07T10:01Z
```

**Row A is the finding.** If this pull request merges after 2026-09-08T00:00Z — and it is 2026-09-07,
after two review rounds, with the merge not yet done — then anyone signing between the constant and the
merge signed *without* the notice and is **admitted**. The gate silently reverts to membership-only for
that window, which is the exact property B2 exists to prevent, in the exact direction the code's own
comment calls unrecoverable ("*too early admits someone who was never told, on a surface with no
erasure*"). It is also the same failure shape as the fourth mutant that was killed — an epoch value that
makes the comparison vacuous — reached by the calendar instead of by an edit, and with no test to catch
it because the suite checks the *format* of the constant and not its *relation to the notice*.

**Row B is the cost of the constant in the other direction, and it lands on the first real user.**
A contributor who signs the same day this merges is refused although they were properly noticed. That
is Convergence's contributor (plan task 1.5, still open, blocked on a third party). Their only escape
is a `DIRECT_NOTICE_GIVEN` entry — a set reserved for people who signed *before* the notice and were
given it directly — so using it for someone who signed *after* the notice would put a false statement
in the register citation the set demands. The comment anticipates this and answers it with "*may be
lowered later against the merge commit's own date*": an unowned manual post-merge edit, with no issue,
no gate and no forcing function, which is what `wg-block-pr-ready-on-undeferred-operator-steps` exists
to stop.

**Answering the two questions as asked.**

- **Is 2026-09-08 defensible?** No. It is defensible only for the fourteen hours in which the merge
  beats it, and nothing in the artifact makes that condition visible if it fails.
- **Is a hardcoded floor the right instrument at all?** No. A constant cannot express "the moment the
  notice landed" because that moment is created by the act of merging the constant.
- **Should it be pinned to the ICLA's content hash instead?** That is the semantically correct pin and
  it is **not reachable**. The reference set this gate reads is
  `origin/cla-signatures:signatures/cla.json`, whose records carry `{name, id, comment_id, created_at,
  repoId, pullRequestNo}` and no document hash. `cla_doc.content_sha256` exists only in the R2 evidence
  record, which needs Doppler `prd_cla` credentials and is unreadable from a fork pull request's CI job.
  Recorded so this is not re-derived later.
- **Should it be lowered against the merge commit after the fact?** Only as half of a two-part remedy,
  and only if it is owned. On its own it closes row B and leaves row A open until someone remembers.

**The fix I would take (one function, no new reference set).** Derive the epoch from the repository at
check time: `git log -S` over the ICLA §0 coverage-map paragraph, oldest match, that commit's date.
On this branch it resolves to `696f24ebb 2026-09-04T13:06:16+02:00` — verified — and a squash-merge
rewrites that date to the merge date, which is precisely the instant the notice became true of `main`.
Both directions then close automatically and permanently: no false refusal of a same-day signer, and no
silent hole if the merge slips. Fail **closed** if the commit cannot be resolved (a shallow clone), in
the shape the ledger fetch already uses in `roster-entry-gate.test.ts`.

**The minimum I would accept instead**, if the constant is kept: a suite arm asserting
`Date.parse(COVERAGE_MAP_NOTICE_EPOCH) >= <introducing commit date>` — which closes row A by turning a
silent hole into a red build — **plus** an issue owning the post-merge lowering, which closes row B.
Both, not either. The constant alone closes neither.

## Ruling on the archived plan and tasks (AC19 / task 1.3)

**In scope for this audit, and the answer is: record it and annotate the archive; do not rewrite the
tick.**

Taking the archive out of scope because the claim is off the live surfaces would be right if archives
here were inert. They are not — they are consulted as evidence of what was done and when, which is the
very function this feature exists to serve for licence grants. An archived tasks file that says `[x]`
against "*Add the in-flight state*", and an AC19 that asserts "*the PR carries a visible 'CCLA in
progress — maintainer action, not yours' state*", will be read by the next auditor as evidence that a
mechanism was built. None was. That is a false record of the same shape as the ones this corpus spends
its amendment blocks correcting.

But the corpus convention is equally clear that a historical record is **appended to, never rewritten**
— #6588's retractions, PA-7's `[CORRECTION]` / `[WIDENING]` blocks, and §(g)(4)'s "designed, not in
force" all preserve the superseded text as the audit trail. So:

1. **Do not un-tick task 1.3 and do not delete AC19.** Append one dated line to each:
   *"[2026-09-07] NOT MET. No label, check or workflow step ever produced this state; the assertion was
   removed from `cla.yml` and `CONTRIBUTING.md` by b91e5a83d rather than the mechanism built. See
   `knowledge-base/legal/audits/2026-09-counsel-review-3210.md` §B3."*
2. **The generalisable defect belongs in the learnings**, and it is a sharper instance of the one this
   session already captured at
   `knowledge-base/project/learnings/2026-09-04-every-verification-i-wrote-passed-and-three-of-them-proved-nothing.md`:
   AC18, next door, verifies its copy claims by grepping for the sentences *and* asserting a byte
   offset; AC19 asserts a **user-visible state** and was closed with no evidence at all. The rule worth
   writing down is that **an AC asserting a state a user can see must be verified against the mechanism
   that produces it, never against the prose that describes it** — greppable prose is what makes such an
   AC feel verified while nothing checks it.
3. This is **not** a merge blocker. It is a record correction, and it is listed under
   `required_before_merge` nowhere.

## Findings added in round 2

**O-6 — the surviving "first if you would like to".** `.github/workflows/cla.yml` still invites the
contributor not to read the document whose §0 the sign phrase attests they have read. Downgraded from
part of B1 for the reasons at §B1 above. One-clause close: make it read "*worth reading before you
sign*", matching the sentence the same comment now uses two paragraphs later, so the comment does not
say both things.

**O-7 — the `covered: false` annotation, B3's weaker sibling.** `corporate-cla.md` §5 ("*a first
Contribution may be annotated as not yet covered*") and `ccla-register.md` Notes ("*A first pull request
may therefore be annotated `covered: false`*") describe an annotation that no mechanism produces —
the same family as B3. **Not raised as a blocker**, and the distinction is real rather than convenient:
both are hedged ("may be annotated"), neither asserts that a pull request *carries* a state, and the
consequence each draws — that it is "a delay in an annotation, not a condition on the Contribution" —
is true whether or not anything ever annotates anything. A maintainer saying so on the thread satisfies
both sentences. Recorded so the next reader does not have to re-derive why one was blocked and two were
not.

**O-8 — `assertContributionTriggeredEntry` crashes untyped on a null ledger entry.** The membership
half uses `c?.id`; the temporal half's `signedAt` map uses `c.id`, so a `null` in `signedContributors`
throws a `TypeError` instead of `ContributionTriggeredEntryError` — reproduced (row C above). It fails
**closed**, and through `validate-roster.ts` it surfaces as exit 1 rather than the documented exit 4, so
the consequence is a confusing exit code, not a bypass. One character (`c?.id`) closes it.

**O-9 — `DIRECT_NOTICE_GIVEN.register_ref` is typed but never validated.** An entry with
`register_ref: ""` unblocks a write exactly as a real citation does. The doc comment says a citation is
required and says that adding one without it "*is the defect this set exists to make visible rather than
to permit*" — but nothing makes it visible. Non-blocking **because the set is empty and any addition is
a reviewed code change**, and because hardening an unused set is not worth holding a merge for. It is
carried instead as a frontmatter re-evaluation trigger, to fire before the first entry: assert the ref
matches `^CCLA-[0-9]{4,}$` and that the cited row exists in `ccla-register.md`, in the shape of the
anti-vacuity arm this suite already has.

## Round 3 — commit 017ccf5a7 (2026-09-07)

### B2-a — DISCHARGED

The derivation is the right instrument and it closes B2-a completely. Verified by running it, not by
reading it:

```
resolveCoverageMapNoticeEpoch()            -> 2026-09-04T13:06:16+02:00   (live, this worktree)
ccla-add.sh add --login deruelle (dry run) -> rc=4, and the refusal names the derived epoch:
  "signed 2026-02-27T09:53:45Z, before the notice existed"
cla-evidence vitest                        -> 9 files, 93 tests, all passing
```

There is no constant left to lower and no issue left to remember, which is what B2-a was actually
about. Both of the failure directions I demonstrated in round 2 are closed by construction: a
same-day post-merge signer is admitted, and there is no window in which the gate silently degrades
to membership-only because someone did not get round to editing a number.

**Taking the derivation rather than the fallback was the right call.** The "constant + suite arm +
owned issue" minimum I offered was a concession to effort, and it would have left the post-merge
lowering as an unowned step — the thing `wg-block-pr-ready-on-undeferred-operator-steps` exists to
stop. This has no operator step at all.

**Fail-closed now covers both shapes, and the gap that was found was real.** The first fail-closed
arm passed a nonexistent path, which throws inside `execFileSync` and returns through the catch —
so the anchor-not-found branch, the one that fires if § 0 is ever reworded, was never exercised and
a mutant returning epoch 0 from it survived. The second arm now builds a repository whose ICLA has
history but never carried the anchor, and reaches that branch. **The disclosure of that gap, and of
the two test defects below, is worth as much as the fix**: an author who reports a surviving mutant
against their own suite is giving evidence that the rest of the suite was measured rather than
assumed, and it is why the mutant list is treated here as evidence rather than as assertion.

**The two self-reported test defects are both exactly the class this PR exists to remove**, and the
second is the sharper one:

1. *The 1-of-1 quantification.* An "oldest commit" assertion over an anchor with exactly one commit
   passes for a resolver that takes `lines[0]`. The fixture now touches the anchor twice and guards
   itself with `expect(all.length).toBe(2)` — the guard being the part that matters, since without it
   the fixture reverts to the vacuous case the first time the document changes. Verified present.
2. *`require` under vitest but not under `tsx`.* The vitest suite was **structurally incapable** of
   seeing this: it exercised the module under a runtime the write path never uses. The shell suite
   caught it immediately. It failed CLOSED (rc=4), so the direction was safe and no unnoticed person
   could have been admitted — but every legitimate write would have been refused. This is the
   strongest argument in the whole PR for keeping the shell harness alongside the unit suite, and it
   should be said in the record: **two suites over one implementation are not redundancy here, they
   are two different runtimes, and only one of them is the one that writes to the legal record.**

**Why the ICLA content hash could not be used — recorded, and I agree with the substitute.** The
ledger carries no document hash, and `cla_doc.content_sha256` lives only in the R2 evidence record
behind `prd_cla` credentials a fork pull request's CI cannot hold. The git derivation is the nearest
reachable pin to the semantics, and it pins the same fact (which text existed when) by a different
route. No disagreement.

### B2-b — the derivation is correct under ONE of the three merge methods this repository permits

This is what I cannot sign off, and it is narrower than either B2 or B2-a.

`resolveCoverageMapNoticeEpoch()` runs `git log -S NOTICE_ANCHOR --format=%aI -- docs/legal/individual-cla.md`
and takes the oldest match. The code comment states the assumption honestly — *"a squash merge
rewrites that commit to the merge itself"* — so this is disclosed rather than hidden, which is a real
difference from B2-a. But the assumption is not enforced anywhere, and the repository does not hold it:

```
gh api repos/jikig-ai/soleur -> allow_merge_commit: true, allow_rebase_merge: true, allow_squash_merge: true
live rulesets                -> CI Required, CLA Required, Copilot review, Force Push Prevention
                                (NO merge_queue rule — infra/github/README.md records it as REVERTED,
                                 and it is the merge queue that would have pinned merge_method = SQUASH)
git log --merges -300 main   -> 35 merge commits (e.g. "Merge pull request #6326", "#5799")
```

So the merge method is convention, not enforcement — and this repository has merged with merge commits
before. Measured across the full matrix, in throwaway repositories, with a notice commit at 2026-09-04
and a merge at 2026-09-12 (correct answer is always 09-12 post-merge, and 09-04 pre-merge):

| Merge method | shipped: plain + `%aI` | `--first-parent` + `%aI` | `--first-parent` + `%cI` |
|---|---|---|---|
| **Squash** (project practice) | 09-12 ✓ | 09-12 ✓ | **09-12 ✓** |
| **Merge commit** (permitted, used before) | **09-04 ✗** | 09-12 ✓ | **09-12 ✓** |
| **Rebase merge** (permitted) | **09-04 ✗** | **09-04 ✗** | **09-12 ✓** |
| Pre-merge, on the feature branch (this PR's CI context) | 09-04 ✓ | 09-04 ✓ | **09-04 ✓** |

`--first-parent` alone is not enough: a rebase merge replays the commit onto main's first-parent line
with its **author** date preserved, so only `%cI` moves. `%cI` alone is not enough either: a merge
commit preserves both dates on the branch commit, so only `--first-parent` moves. **Both, and then all
three methods and the pre-merge context are correct.**

**The consequence if this merges by either other method.** The epoch resolves to 2026-09-04T11:06Z
instead of the merge instant, and every ICLA signature made between then and the merge — against a
`main` that does not carry the notice — is admitted. That is the same silent degradation to
membership-only that B2-a was, in the same unrecoverable direction, reached by a merge-button choice
instead of by the calendar. The window is empty today (the ledger still holds two accounts, both from
long before), so nothing is presently exposed; but the hole would be permanent for anyone who signed in
it, not limited to the window itself.

**The fix, verified so it does not have to be re-derived:**

```ts
["log", "--first-parent", "-S", NOTICE_ANCHOR, "--format=%cI", "--", NOTICE_DOC]
```

plus a suite arm building throwaway repositories for the merge-commit and rebase cases and asserting
the resolver returns the merge date in both — the same shape as the two-commit fixture already written
for the oldest-vs-newest arm, and the arm that makes this a property of the artifact rather than of the
merge button.

### O-9 — my answer: still not required for this merge

Leaving it as the re-evaluation trigger was the right reading of my ruling, and I am not moving the
line now merely because another round is open — a finding I called non-blocking on its merits does not
become blocking because an unrelated one is. The set is empty, it has no callers, and any addition is a
reviewed code change that a human reads. It stays a trigger, to fire **before the first entry exists**.

Since the file is being touched anyway, the check I would write is four lines, and it is offered rather
than required:

```ts
for (const d of DIRECT_NOTICE_GIVEN) {
  if (!/^CCLA-[0-9]{4,}$/.test(d.register_ref)) {
    throw new ContributionTriggeredEntryError(
      `DIRECT_NOTICE_GIVEN entry for id ${d.id} carries no register citation — ` +
        "the set records a notice that was given, and an entry without a citation records nothing.",
    );
  }
}
```

Take it or leave it in this commit; it must exist before the set is first used.

### Everything else in 017ccf5a7, verified

- **O-8 applied** — `[c?.id, c?.created_at]`, matching the membership half, with the reason in the code.
- **The AC19 ruling applied exactly as given** — plan AC19 and archived task 1.3 both keep their `[x]`
  and carry the appended dated `NOT MET` line naming b91e5a83d. Nothing rewritten, which is the half of
  the ruling that mattered.
- **Anchor integrity has its own arm** — a test asserts `NOTICE_ANCHOR` still occurs in `NOTICE_DOC`, so
  rewording § 0 reds the suite instead of silently sending the resolver down the fail-closed path
  forever. That arm was not asked for and is the right instinct.
- **Suites**: `cla-evidence` vitest 9 files / 93 tests passing, re-run here.
- **Corpus gates** unchanged and green: SHA pin rc=0, mirror drift within baseline, register lint 7/7.

## Round 4 — commit aa30e23b0 (2026-09-07)

### B2-b — DISCHARGED

The resolver now runs `["log", "--first-parent", "-S", NOTICE_ANCHOR, "--format=%cI", "--", NOTICE_DOC]`,
which is the form measured correct across the full matrix. Three things were verified here rather than
accepted:

**1. All three merge methods are instantiated, and the arms are real.** `it.each(["squash",
"merge-commit", "rebase"])` builds a genuine repository per method: a branch commit carrying the anchor
at 2026-09-04, `main` moving on afterwards so the branch is authentically behind, and a merge at
2026-09-12 performed by the actual git operation for each method. Each arm asserts both
`toBe(MERGE_AT)` **and** `not.toBe(BRANCH_AT)` — the second pinning the specific failure, which is
landing on the branch date and admitting everyone who signed in the gap.

**2. Both killing mutants re-run independently in this worktree, and each kills a DIFFERENT single arm:**

```
baseline                              -> 23/23 pass
drop --first-parent (keep %cI)        -> 1 failed: "…under a merge-commit merge…"   (22 pass)
%cI -> %aI      (keep --first-parent) -> 1 failed: "…under a rebase merge…"          (22 pass)
restored                              -> 23/23 pass
```

**That one-arm-each discrimination is the finding, not the fact that mutants died.** A single arm that
only reds when both flags are wrong would prove the pair is load-bearing while leaving either flag free
to be decorative. This proves each flag independently, and the author says it was designed that way for
exactly that reason. It is the right instinct and it is now on the record.

**3. The fixture-invalidation catch is the most valuable thing in this commit.** The two-commit fixture
written in round 3 pinned its dates with `git commit --date`, which sets **only the author date**. The
moment the resolver was changed to read `%cI`, both fixture commits would have carried a committer date
of "now" — collapsing the fixture back into the exact 1-of-1 case it was written to escape, **while
continuing to pass**. It now sets `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` together.

The generalisation is worth carrying beyond this file, and it is sharper than the session learning it
extends: **changing which field a subject reads can silently invalidate a fixture that pins the other
field, and the fixture goes on passing.** A green suite after a resolver change is not evidence the
fixtures still discriminate — the fixtures must be re-read against the new field. Nothing in the
toolchain warns about this, which is precisely why it belongs in the learnings rather than in a comment.

### O-9 — applied, and the reasoning for applying it is better than my reasoning for deferring it

I declined twice to make O-9 blocking and I stand by that on the merits. The author took it anyway, on
a ground I had not stated and now accept: **the set being empty is exactly what makes the first entry
the one nobody is watching.** A validation written while the set is empty costs four lines; the same
validation written when someone is blocked on a real contributor competes with time pressure.

Implementation checked. The runtime half refuses a blank or non-string `register_ref` inside
`assertContributionTriggeredEntry`, with a message that names why the citation is load-bearing ("*an
entry without a citation is an unrecorded claim*"). The suite half is a property over the exported
array plus `expect(DIRECT_NOTICE_GIVEN.length).toBe(0)`. **Micro-note, non-blocking and recorded only
so it is not rediscovered:** the runtime loop is not directly exercised, because a module-level `const`
cannot be injected — the protection today is the suite arm, and the `length === 0` assertion means the
first legitimate addition reds the suite and forces a human to open this arm. That is a forcing
function rather than a gap, and it is the behaviour I would have chosen.

### Independent reproduction of the matrix

The author rebuilt the three repositories and reproduced my numbers before acting on them, rather than
editing to a table handed over by a reviewer. That is the correct handling of a reviewer's measurement,
it is what the flag comment at the call site now records for the next reader, and it is why the matrix
is preserved in the code rather than only in this audit.

### Final verification of the tree

```
cla-evidence vitest                -> 9 files, 97 tests, all passing
ccla-add.test.sh                   -> 40 passed, 0 failed
resolveCoverageMapNoticeEpoch()    -> 2026-09-04T13:06:16+02:00 (live)
scope-block placement              -> 0 violations
legal mirror drift                 -> 9 pairs, within baseline
check-tc-document-sha.sh           -> rc=0
lint-legal-registers.sh            -> 7 assertions, 0 failed
apps/cla-evidence/roster/ccla-roster.json -> {"schema_version":"1.0","organizations":[]}
git status                         -> clean (my mutation edits restored)
```

## Disposition

**DISCHARGED. Sign-off given.**

All three original blockers and both successor findings are closed, and each was closed by taking the
stronger of the options offered rather than the cheaper one: the publication consequence moved into the
comment body instead of behind a link; the false "CCLA in progress" state was deleted instead of a
label being built to justify a sentence; the epoch was derived from git instead of hardcoded with a
promise to lower it; and the derivation was made correct under every merge method the repository
permits instead of under the one it happens to use. O-9 was applied although I twice ruled it
non-blocking, on a better reason than the one I gave for deferring it.

**What this sign-off attests.** That the fourteen artifacts listed in the frontmatter represent what
they claim to represent; that the employer↔account association is characterised as personal data
everywhere and as "no personal data" nowhere; that `removed_at` is described as a withdrawal-of-
designation marker and never as erasure, at eleven sites; that the Art. 13 posture is stated
consistently and is now enforced by an artifact rather than asserted by prose, in both directions and
under every merge method; and that the Proton AG leg is recorded as a Swiss transfer under an adequacy
*mechanism* with its Art. 28(3) instrument recorded as absent rather than assumed.

**What it does not attest** is in the frontmatter carve-outs, and two are worth restating: the Art. 13
versus Art. 14 characterisation (**O-2**) is the item for external counsel when one is engaged, and a
clean full-gate CI run on this tree is still owed before merge — the author raised that themselves and
correctly did not treat this review as substituting for it.

The 2026-09-04 ruling stands undisturbed. Reviewed and attested by the CLO agent as attestation
authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto. This is the
internal v1 sign-off, and external counsel re-review is reserved for the triggers in the frontmatter —
of which the first arms-length corporate representative written to the roster is the one that will
arrive first.
