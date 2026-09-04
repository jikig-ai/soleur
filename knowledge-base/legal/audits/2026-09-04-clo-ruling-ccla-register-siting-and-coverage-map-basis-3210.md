---
title: "CLO ruling — siting of the Corporate CLA register, and the Art. 6(1)(f) basis for the public coverage map"
type: clo-ruling
date: 2026-09-04
issue: 3210
pr: 7828
attestation-authority: clo
status: APPROVED (CLO-agent-ruled, Soleur-as-tenant-zero v1)
disposition: DISCHARGED
signed_off_at: 2026-09-04
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
tier_classification: "Tier 2 — docs/legal/gdpr-policy.md Section 3.4 gains a third balancing test, so the mirror-pair, drift-ratchet, SHA-pin and heading-parity gates over docs/legal/** are engaged. Art. 30 amendment: PA-7 (c) data subjects, (c) personal data, Lawful basis, (d) Recipients."
semver: "N/A — TC_VERSION unaffected; no Terms and Conditions change"
brand_survival_threshold: single-user incident
written_against: "measured repository visibility, measured DNS for legal@jikigai.com, and the corpus as it stands — not the plan's KD narrative"
re_evaluation_triggers:
  - "MORE THAN TEN ORGANISATIONS on the register. B1-b (a separate private repository) was refused at n=1 on the ground that it buys a repo, an access policy and a second drift surface to protect a field set that need not be in version control at all. That arithmetic changes with volume; the refusal does not generalise."
  - "THE FIRST COUNTERPARTY WHOSE EXECUTED INSTRUMENT MUST BE JOINTLY AUDITABLE. Custody on the encrypted operator drive is single-custodian by construction. A counterparty entitled to audit the instrument alongside us defeats that, and the B1-b refusal must be re-run."
  - "THE FIRST COUNTERPARTY THAT IS A SOLE TRADER OR TRADES UNDER A NATURAL PERSON'S NAME. Amendment B1-c-2 is a rule that has never been exercised. Its first application should be reviewed, not merely applied."
  - "ANY PROPOSAL TO WRITE AN IDENTITY FIELD (name, title, email, postal address, signature image) INTO A TRACKED FILE. Section 1 below removes those fields from the schema permanently. A proposal to reinstate one is a re-opening of this ruling, not a schema change."
  - "RESOLUTION OF #7668 AS APPLIED TO THIS POPULATION. Whether indefinite retention of the employer-to-account association is proportionate under Art. 5(1)(e), on a surface from which it cannot be erased, is not decided here."
related:
  - knowledge-base/project/plans/2026-09-04-feat-ccla-signing-mechanism-plan.md
  - knowledge-base/legal/ccla-register.md
  - knowledge-base/legal/article-30-register.md
  - docs/legal/gdpr-policy.md
  - docs/legal/corporate-cla.md
  - apps/cla-evidence/roster/ccla-roster.json
---

# CLO ruling — CCLA register siting and coverage-map basis (#3210)

## Disposition: APPROVED. B1-c adopted with two amendments; B1-a and B1-b refused.

## The question

The plan sited a Corporate CLA register carrying enumerated signatory identity fields at a
path in this repository, and described it as private. It is not private. `gh repo view`
returns `jikig-ai/soleur visibility=PUBLIC private=false`; `git ls-tree -r origin/main --
knowledge-base/legal/` returns 69 tracked files; `.gitignore:60` ignores
`knowledge-base/private/`, and that directory does not exist. Writing one signatory row
would publish a named individual's name, title and corporate email to the world,
permanently and irreversibly, in git history.

Two things were therefore in issue: **where the identity bytes live**, and **on what basis
the employer-to-account association is published at all**.

## Section 1 — Siting: B1-c adopted

**The register in this repository is an INDEX. The executed instrument is the EVIDENCE.**
The question the record must answer at a relicensing event is *"was account N covered by
organisation O's Corporate CLA on date D, under document version H?"* None of that requires
the signatory's name. Authority to sign is proven by the executed instrument, not by a
markdown row.

Adopted: the tracked register carries existence, an opaque record reference, the
organisation's legal name (subject to Section 1.2), the CCLA document hash, the SHA-256 of
the executed instrument as received, `signatory_on_file: yes|no`, and the effective date. It
carries **no name, title, email, postal address or signature image**, and this is a
permanent prohibition rather than a gate — nothing waits on it, because nothing may ever
write those fields to a tracked file.

### Section 1.1 — Amendment B1-c-1: custody is the encrypted operator drive, not the mailbox

A mailbox is a transport, not custody: it has no retention discipline, no access record,
and an Art. 15 or Art. 17 request made against it is unanswerable. The controlling
precedent is already in the corpus, at `side-letter-register.md` Notes: *"The executed PDF
lives off-repo (encrypted operator drive). The repository carries only the template and
this register."* That is the posture adopted here.

**Measured, not assumed** — this discharges plan task 0.4, which existed precisely because
the corpus recorded a provider for `ops@soleur.ai` and nothing for `legal@jikigai.com`, and
because reasoning by analogy from one to the other is the failure class #7624 exists to
correct. As at 2026-09-04, `legal@jikigai.com` is hosted on **Proton Mail (Proton AG,
Switzerland)**: MX `mail.protonmail.ch` and `mailsec.protonmail.ch`, SPF
`include:_spf.protonmail.ch`, and a `protonmail-verification` TXT record present.
Switzerland is covered by an EC adequacy decision, so the transport leg raises no Chapter V
question. Proton AG is recorded as a processor in PA-7 (d); its Art. 28(3) instrument is
**not** verified in `compliance-posture.md` and is recorded as an open item rather than
asserted.

### Section 1.2 — Amendment B1-c-2: a legal name is not unconditionally non-personal

True of a *société*; false of a sole trader, or of anyone trading under their own name,
where the organisation's legal name **is** a natural person's name. The schema therefore
carries a rule rather than an assumption: such a counterparty is published under the opaque
`Record ref` alone, with the legal name held off-repo with the instrument.

### Section 1.3 — B1-a refused

`knowledge-base/private/ccla-register.md`, gitignored. Refused. Privacy by `.gitignore`
discipline is not privacy by construction, and this exact approach has already failed twice
here — the Art. 30 register was planned private and is public today. It also destroys the
content-addressed integrity that KD8 exists to buy: an untracked file is unbacked, has no
history and is not tamper-evident.

### Section 1.4 — B1-b refused, at n=1

A separate private repository. Refused **at one organisation**, not in principle. It buys a
repository, an access policy and a second drift surface in order to protect a field set
that, under B1-c, need not be in version control at all. **Refusing to store the data beats
storing it privately.** See the re-evaluation triggers in the frontmatter: more than ten
organisations, or the first counterparty whose instrument must be jointly auditable.

### Section 1.5 — B1-d unavailable

The R2 evidence bucket is blocked by NG6/AC5 on #7813, #7814 and #7816. Not refused on the
merits; simply not available to rule on.

## Section 2 — Contribution-triggered entry (the spine of this ruling)

B1, Finding B2 and the Art. 17 problem are one problem seen from three articles: *the
roster as specified entered people into an irreversible public record on a third party's
say-so, before they had done anything and before they had been told anything.*

**The rule: a representative's account identifier and employer association are committed to
a tracked file only at or after that representative has themselves signed the Individual
CLA on a pull request in this repository.** The employer's designation list under Corporate
CLA Section 4(c) is held off-repo and does not by itself write a row.

Four consequences, each of which is why the rule is adopted rather than a stricter or
looser one:

1. The Art. 6(1)(f) balancing at `gdpr-policy.md` Section 3.4 becomes comfortable rather
   than strained, because the residual intrusion is assessed against a pull-request history
   the person published under their own account, by their own act.
2. The never-contributed population — the only one with no Art. 17(3)(e) ground — never
   enters git at all.
3. Art. 14 collapses into Art. 13 for the entire published population: every person in the
   map has been informed directly, here, at or before the moment their record was created.
4. Provenance survives via an `authorized_from` field carrying the legally operative date,
   rather than an inferred commit timestamp.

The cost is that a first pull request may be annotated `covered: false` until the roster
catches up. That is a latency on an annotation, not a gate on a merge, and Corporate CLA
Section 1 covers future contributions with no cut-off.

## Section 3 — Finding B2 accepted: the coverage map contains personal data

KD13 justified publishing the map on the ground that *"a corporate entity is not a data
subject and GitHub logins are already public."* The first clause holds. The second is a
category error. Public availability does not remove data from Art. 4(1), and the map does
not merely republish logins: it asserts an **employment relationship** between an
identifiable natural person and a named employer. That association is personal data that
neither component carried alone, and it is precisely the information the map exists to
convey. `docs/legal/corporate-cla.md` Section 4(e) already classes GitHub usernames as
personal information, so the corpus contradicted KD13 before this ruling did.

**The map contains no special-category data and no contact data. It does not contain "no
personal data", and no document in this corpus may say that it does.** The Art. 6(1)(f)
basis is recorded in the third balancing test at `gdpr-policy.md` Section 3.4 and in PA-7's
Lawful basis cell.

## Section 4 — Art. 17 ruled

- **A `removed_at` marker in a git-tracked file is not erasure and must never be described
  as one.** The surface is a public git repository: the record is copied into every clone,
  fork and mirror, and rewriting our own history does not reach them.
- **Art. 17(3)(b) is NOT available.** No statute or regulation obliges a contributor
  roster. The obligation being met is contractual and self-imposed, and a self-imposed
  obligation is not a legal one for the purposes of Art. 17(3)(b).
- **Art. 17(3)(e) IS available, per record.** Yes for a representative who contributed —
  the association evidences that a merged commit was covered. No for one who never did.
  Contribution-triggered entry removes that second population entirely, which is the
  strongest argument for the rule in Section 2.
- **Naming.** `removed_at` is a **withdrawal-of-designation marker**, never a "tombstone".
  "Tombstone" already means something erasure-shaped in this codebase
  (`tombstones/<sha>.deleted.json` on the R2 path), and reusing it is how a false
  disclosure appears two documents downstream.
- **#7668 extends to this population**, scoped to one new question: is indefinite retention
  of the association proportionate under Art. 5(1)(e) *on a surface from which it cannot be
  erased*? Not decided here.

## Section 5 — The gate, corrected

An earlier draft of this ruling had the gate in both directions and is corrected here.
Writing identity columns into a tracked file is not *gated* — Section 1 removes those fields
from the schema permanently, so nothing waits on it. But the roster row that draft called
unblocked **is** gated: committing the association before its Art. 6(1)(f) basis is on the
record publishes personal data with no documented basis, which is the #7813 defect class in
a fresh location.

**The gate is exactly two conditions, both cheap:**

1. The third balancing test is present at `gdpr-policy.md` Section 3.4 and in PA-7's Lawful
   basis cell (a documentation edit, landing in this PR).
2. That representative has signed the Individual CLA here.

Everything else in Tier 0 is unblocked: the FR7 copy fix; replying to request a named
signatory with title and an individually-attributable mailbox; a corporate contributor
signing the ICLA and their pull request merging on its merits; and countersigning. The
first corporate contributor can be served this week.

## What this ruling does not decide

- The Art. 28(3) instrument covering Proton AG. Recorded as open in PA-7 (d).
- Whether indefinite retention of the association is proportionate under Art. 5(1)(e)
  (#7668).
- The Supabase / importer-identity divergence at #7670, which PA-7 (e) governs and which
  is untouched here.

## Attestation

Reviewed and ruled by the CLO agent as attestation authority for the Soleur-as-tenant-zero
v1 posture. The operator retains an optional veto. This is the internal v1 sign-off;
external counsel re-review is reserved for the triggers listed in the frontmatter.
