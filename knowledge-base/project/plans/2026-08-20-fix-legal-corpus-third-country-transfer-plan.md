---
title: "Reconcile the published legal corpus to Art. 30 PA-7: third-country transfer, FreeTSA, and the retention floor"
type: fix
domain: legal
issue: 7624
closes: 7624
branch: feat-one-shot-7624-legal-corpus-third-country-transfer
lane: cross-domain
date: 2026-08-20
priority: p1
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tc_version_bump: false
tier_classification: "Tier 1 (material) — a third-country transfer newly disclosed in running text, and a retention characterisation corrected from a ceiling to a floor"
governing_record: knowledge-base/legal/article-30-register.md — Processing Activity 7, cells (d), (e), (f)
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/legal/data-processing-agreement-template.md
  - knowledge-base/legal/tc-version-bump-policy.md
  - knowledge-base/project/learnings/2026-08-01-the-correction-pr-reproduced-its-own-defect-and-my-tracker-said-done.md
  - knowledge-base/project/learnings/2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md
  - knowledge-base/project/learnings/2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md
---

# Reconcile the published legal corpus to Art. 30 PA-7

## Overview

PR #7622 (merged 2026-08-20) amended Processing Activity 7 of the Article 30 register. Cell
§(e) now records the CLA evidence archive as a **third-country transfer to Cloudflare Inc
(United States)** safeguarded by **EU-US DPF + SCCs + CBPR**, on the ground that the transfer
arises from the *identity of the importer*, not the location of the bytes, and that
`location = "WEUR"` on `cloudflare_r2_bucket.cla_evidence` is a **placement hint, not a
jurisdiction** — the bucket sits on Cloudflare's `default` (non-EU-tier) jurisdiction. Cell
§(f) records retention as **indefinite**; the ten-year R2 Lock Rule is a WORM *floor*. Cell
§(d) records **FreeTSA as NOT a recipient**.

The published corpus says the opposite in every one of those three respects, across three
documents and their published Eleventy mirrors. That is an Art. 13(1)(f) transparency defect:
the register is a record-keeping artefact, the corpus is the half that reaches data subjects.
It also leaves `gdpr-policy.md` §3.4 resting a proportionality limb of a live Art. 6(1)(f)
balancing test on a residency guarantee that does not exist.

This plan reconciles the corpus to the register. The register governs; where the two disagree,
the corpus is wrong. No transfer basis is invented — the register names DPF + SCCs + CBPR and
that is the only mechanism this plan may publish.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| PR #7622 merged, register amended | `gh pr view 7622` → `MERGED`, `mergedAt 2026-08-20T13:17:08Z`, merge commit `28612e8cd` | **Holds.** Worktree `article-30-register.md` is at `28612e8cd` — the amended text is present. |
| Issue #7624 open, P1, domain/legal | `gh issue view 7624` → `OPEN`, labels `priority/p1-high`, `type/chore`, `domain/legal` | **Holds.** |
| #7625 is a separate work item | `gh issue view 7625` → `OPEN`, "Art. 30 PA-7 §(c) omits comment_body…" | **Holds.** Out of scope; §(c) is untouched by this plan. |
| "the register does not name a transfer mechanism" | Read `article-30-register.md` §(e) | **FALSIFIED — and this is the single most important finding.** §(e) explicitly names *"EU-US DPF + SCCs + CBPR, the same instrument as the edge-proxy activities."* No mechanism needs to be invented, and none may be. |
| "`scripts/check-tc-document-sha.sh`" (path given in the task brief) | `find . -name '*tc-document-sha*'` | **FALSIFIED.** The script lives at `apps/web-platform/scripts/check-tc-document-sha.sh`. The repo-root path does not exist. |
| "roughly ten published statements" | Enumeration (see `## Enumerated Inventory`) | **UNDER-COUNT.** 10 canonical *third-country/EU-region* sites, but the full defect set spans **64 enumerated rows over 55 distinct anchors** across 10 classes and 16 files once the retention class, the FreeTSA class, the two Art. 13(1)(f) omissions, and the DPA-template contractual representation are included. |
| "four mirrors under `plugins/soleur/docs/pages/legal/`" | `ls` both directories | **Partially holds.** All 9 canonical docs have a 1:1 mirror. Three carry the transfer/FreeTSA defects; two more (`individual-cla`, `corporate-cla`) carry the retention defect. |
| `soleur-cla-evidence` jurisdiction is `default` | `apps/cla-evidence/infra/iam.tf:14` comment + `iam.tf:41` resource string `…${var.cf_account_id}_default_${bucket}` | **Holds.** `bucket.tf:6` sets `location = "WEUR"`. |
| Tenant DPAs executed under the template | `knowledge-base/legal/tenant-dpa-register.md` Rows table | **EMPTY.** No executed instrument carries the template's false §11.1 representation — correcting the template has zero counterparty blast radius. |

### Property List (Phase 0.6b)

1. A data subject reading any published Soleur legal document learns that the CLA evidence
   archive is transferred to a US-established processor, and learns the safeguard the
   register actually records.
2. No published Soleur legal document asserts that the archive is EU-region, intra-EU, or
   free of a third-country transfer.
3. No published Soleur legal document represents FreeTSA as a recipient, processor, or
   sub-processor of personal data.
4. No published Soleur legal document states ten years as the *ceiling* of CLA-signature
   retention.
5. The correction reaches the **published** surface (the Eleventy mirror), not only the
   canonical record.
6. A future edit that re-asserts any of (2)–(4) reddens CI rather than shipping.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Already covered by | Disposition |
|---|---|---|---|
| A new bespoke `lint-legal-transfer-claims.sh` gate | Property 6 | `apps/web-platform/test/legal-doc-consistency.test.ts:121-147` already owns a sentinel table of load-bearing legal prose fragments asserted against **both** surfaces. Extending it reuses the loop, the both-surface quantification, the doc loader and the CI wiring. | **CUT — but the original justification was wrong and is corrected here.** The claim "with zero new machinery" was **false**, and the correctness review caught it: the tuple is `Array<[string, RegExp]>` and the loop at `:142-147` hard-codes `expect(source).toMatch(pattern)` / `expect(mirror).toMatch(pattern)`. It carries **no polarity**, so a negative sentinel cannot be expressed in it at all. The real cost is a **third tuple element** (`"present" \| "absent"`) plus a two-arm branch in the loop — roughly six lines. That is still far cheaper than a new gate, and the cut stands; but it stands on a measured cost, not on a claim that turned out to be untrue. |
| A committed mirror-drift baseline file to regenerate | Lockstep detection | `scripts/lint-legal-mirror-drift-baseline.sh` derives its baseline at runtime from `git show <merge-base>:<path>`. There is **no baseline file**; nothing to regenerate. | **CUT.** Verified against the script header. |
| A `TC_VERSION` bump | Forcing re-acceptance | `TC_VERSION` gates `docs/legal/terms-and-conditions.md` only (`apps/web-platform/lib/legal/tc-version.ts`). This PR does not touch T&C. | **CUT.** |
| A `sed` sweep on `weur` | Properties 2-4 | Nothing — and it is actively wrong. Three of the four defect classes contain **no** `weur` token (the retention class, the FreeTSA class, and the two omissions). A `weur` sweep would have shipped a corpus still false in three ways. | **CUT.** Replaced by the per-row inventory below. |

### Consolidated findings

**The five legal CI gates (verified by inspection, not assumed).** None is path-filtered; all
five fire on this PR.

| # | Gate | Job | What it asserts | What this PR must do |
|---|---|---|---|---|
| 1 | `apps/web-platform/scripts/check-tc-document-sha.sh` | `ci.yml :: tc-document-sha-guard` (Terraform-pinned required check) | Raw-byte `sha256sum` of each `docs/legal/<doc>.md` equals its pin. `BODY_EQUIVALENCE_DOCS=("terms-and-conditions" "acceptable-use-policy" "disclaimer")` — the three docs edited here are **not** enrolled, confirming the issue body. `EXPECTED_COUNT=9` is a warning-only tripwire on the doc-count glob. **No `--write` mode.** | Re-pin 5 keys in `apps/web-platform/lib/legal/legal-doc-shas.ts` by hand, in the same commit. |
| 2 | `apps/web-platform/test/legal-doc-consistency.test.ts` | `ci.yml :: test-webplat` (feeds required `test`) | (a) `##`/`###` heading **sequence** identical canonical↔mirror; (b) a hard-coded **sentinel regex table** asserted against both surfaces; (c) `**Last Updated:**` body date parity canonical↔mirror **and** mirror hero `<p>`; (d) RCS-jurisdiction singleton. | Preserve every sentinel (see Sharp Edges). Add no headings. Extend the sentinel table with the anti-regression rows. |
| 3 | `apps/web-platform/test/legal-doc-shas-guard.test.ts` | `ci.yml :: test-webplat` | Mutation harness for gate 1; asserts `EXPECTED_COUNT == len(LEGAL_DOC_SHAS)+1` **and that the unmodified tree exits 0** — so a forgotten SHA re-pin fails vitest too, not just the bash job. | Nothing beyond gate 1. |
| 4 | `scripts/lint-legal-scope-block-placement.sh` | `ci.yml :: test-scripts` | Added-lines-only ratchet: a locality assertion (`applies/describes/covers/…` within 60 chars of `plugin-local/locally/on-device/…`) must not use a section-wide referent inside a cloud-marker section, must be flush-left, and must discharge on the same line. | Do not phrase new transfer prose as "This section applies only to…". Use "The paragraph above …; for the Web Platform see Section X". |
| 5 | `scripts/lint-legal-mirror-drift-baseline.sh` | `ci.yml :: test-scripts` | Canonical↔mirror drift at HEAD must be a **subsequence** of drift at the merge base. Verdicts `GREW` / `REORDERED` / `CONTENT CHANGED`. Also fails any `](….md)` link on a mirror page. Baseline computed from git history — no file to regenerate. | Edit both surfaces **identically and in the same position**; use `/legal/<slug>/` link form on mirrors. Measured baseline: `9 pair(s) checked, drift is within the baseline` (exit 0, merge-base `6473899`). |

`.github/workflows/legal-doc-cross-document-gate.yml` also runs (no path filter, required
check) but **trivially passes** — it fires only when a DSAR-surface file is in the diff, which
this PR has none of. `validate-vector-config.yml` is path-filtered to
`apps/web-platform/infra/vector.{toml,tf}` and does **not** fire; its Better Stack
source-ID/cluster parity step nonetheless greps `docs/legal/privacy-policy.md` and
`data-protection-disclosure.md` plus both mirrors, so those tokens must not be removed.

**Normalisation contract (`scripts/lib/legal-normalise.sh`).** Canonical↔mirror prose must be
**normalised-identical**, not byte-identical. Permitted divergence: frontmatter, the H1/hero
scaffolding (`<section>`, `<div>`, `<h1>`, `<p>Effective…</p>`), link form
(`privacy-policy.md` vs `/legal/privacy-policy/`), the `{{ stats.* }}` template vars, and
blank-line runs. Everything else — every word of prose — must match after normalisation.

**Precision note on gate 1.** "Gate 1 hashes canonical only — the mirror is never hashed" is true
for the three primary docs but **false as a general statement**: `check-tc-document-sha.sh:157`
does `normalize_plugin "$mirror_path" | collapse | sha256sum` for the `BODY_EQUIVALENCE_DOCS`
trio, and `:149-152` hard-fails on a missing mirror for every doc. None of the five docs this PR
edits is enrolled, so the mirror's *prose* is unhashed here — which is why gate 5 and the sentinel
table, not gate 1, are what protect the published surface.

**Measured current drift on the target lines.** Diffing `normalize_canonical | collapse`
against `normalize_plugin | collapse` for all three docs and filtering for
`weur|FreeTSA|third-country|ten \(10\)|Intra-EU|evidence archive`: **none of the target prose
lines currently drift.** The only drifting hits are the `**Last Updated:**` line on all three
docs (the mirror appends a "correction history on this published page is condensed" note) and
a canonical-only Microsoft intra-EU bullet in `privacy-policy.md`. This is load-bearing: it
means every target line can be edited in lockstep with zero drift growth, and it means the
`**Last Updated:**` line **cannot** be edited in place (see Sharp Edges).

**Applicable institutional learnings.**

- `knowledge-base/project/learnings/2026-08-01-the-correction-pr-reproduced-its-own-defect-and-my-tracker-said-done.md`
  — a correction PR is the highest-risk place to commit the error it corrects; the author is
  in "the old claim was wrong" mode and writes a new one without re-deriving its scope. That
  PR (#7110) found three documents and missed a fourth. **Rule imposed:** every replacement
  claim in this PR must trace to a named cell of PA-7, and the enumeration must be by *subject*
  across all of `docs/legal/`, `plugins/soleur/docs/pages/legal/` and `knowledge-base/legal/`.
- `knowledge-base/project/learnings/2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md`
  — sweep for the **subject** of a claim, not its phrasing; a residual-zero count is evidence
  about a string, never about a claim. **Rule imposed:** the subject sweep is
  `soleur-cla-evidence|CLA evidence|evidence archive|FreeTSA`, not `weur`.
- `knowledge-base/project/learnings/2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`
  — deleting an entity from an enumeration can *strengthen* the dependent clause that leaned
  on it. **Rule imposed:** the FreeTSA sites are a claim family; each removal must be checked
  for what the surviving sentence now asserts (see AC12).
- `knowledge-base/project/learnings/2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md`
  — legal prose making technical claims must be derived from the implementing artefact.
  **Rule imposed:** the jurisdiction claim is derived from `apps/cla-evidence/infra/iam.tf`,
  which the register already cites, and from nothing else.
- `knowledge-base/legal/audits/2026-08-counsel-review-7349.md` — the precedent audit for this
  exact class; sign-off was withheld twice over published prose that was false on the day of
  merge, and `LEGAL_DOC_SHAS` had to be re-pinned twice. **Rule imposed:** re-pin the SHAs
  **last**, after the final prose byte is settled, and again after any review-fix commit.

**Related issues.** #7601 (closed by #7622, the register amendment). #7625 (PA-7 §(c) field
omissions — explicitly out of scope). #7465 (the mirror-drift remediation ratchet, target
2026-09-30). #5858 (a structurally identical defect for Flagsmith: transfer safeguard missing
from the transfer sections) — not fixed here, but it confirms the omission class in `## Class D`
is real and recurrent.

**CLAUDE.md / AGENTS.md conventions engaged.** `hr-gdpr-gate-on-regulated-data-surfaces`,
`hr-third-party-content-grep-on-undertaking`, `cq-cite-content-anchor-not-line-number` (the
inventory below carries line numbers for locating, but /work must anchor edits on the verbatim
sentence — the mirror offsets are **not** uniform: `+9` for privacy-policy and DPD, but `+9`,
`+8` and `−7` at different points in gdpr-policy), `cq-assert-anchor-not-bare-token`,
`wg-use-closes-n-in-pr-body-not-title-to`.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / task brief | Codebase reality | Plan response |
|---|---|---|
| "the register does not state a transfer mechanism — flag to CLO rather than fabricating one" | §(e) **does** state one: EU-US DPF + SCCs + CBPR | Publish exactly that. No fabrication needed; the "do not invent" constraint is satisfied by quoting the register. |
| `scripts/check-tc-document-sha.sh` | `apps/web-platform/scripts/check-tc-document-sha.sh` | Corrected throughout this plan. |
| "roughly ten published statements" | 10 canonical third-country/EU-region sites; 64 enumerated rows over 55 distinct anchors, across 10 classes and 16 files | Full inventory below; classes B/C/D were not in the issue's table. |
| "FreeTSA listed as sub-processor at DPD §2.3(n)" | Three DPD sites, not one: §2.3(n) closing line, the §4.2 processor-table row, and the §6.4 transfers bullet. A fourth site in `gdpr-policy.md` §2.2 already disclaims Art. 28 scope. | Class B, 4 canonical rows + 4 mirror rows. |
| "retention understated at privacy-policy.md:122" | Seven canonical sites, including `individual-cla.md:26` and `corporate-cla.md:26` — the instruments contributors actually sign — and the *premise* of the gdpr-policy §3.4 balancing test | Class C. CLO ruling sought on the CLA-instrument sites (Fork 4a). |
| "the mirror-sync gates compare hashes, not truth" | Confirmed and sharper: gate 5's own header says *"NOT CHECKED: a lockstep DELETION"*, and gate 1 hashes **canonical only** — the mirror is never hashed | Class-by-class inventory + the sentinel extension in Phase 4 are the only truth-anchored mechanisms in the PR. |
| "do not edit `apps/web-platform/infra/vector.toml`" | Not in any Files-to-Edit list | Honoured. Its parity step greps PP/DPD for Better Stack tokens — those tokens are untouched. |

## The Governing Record

Every replacement claim in this PR traces to one of these three cells. `/work` must not publish
a proposition that cannot be pointed back to this section.

**PA-7 §(d) Recipients** — *"**NOT a recipient: FreeTSA.** The monthly RFC 3161 exchange
transmits a SHA-256 digest of the bucket-state manifest and receives a signed token. The digest
is taken over an aggregate manifest rather than over any individual's identifier, so it cannot
be used to single out a data subject… No signature record, identity or timestamp payload
egresses to the TSA."*

**PA-7 §(e) Third-country transfers** — *"**Cloudflare Inc (R2 object custody) — third
country: the United States.** Safeguards: EU-US DPF + SCCs + CBPR, the same instrument as the
edge-proxy activities. **The transfer arises from the identity of the importer, not from the
location of the bytes:** … a Chapter V transfer irrespective of where the objects rest (EDPB
Guidelines 05/2021, criterion 3). **The bucket is additionally NOT jurisdiction-restricted, and
this cell must not record data localisation as a safeguard.** `cloudflare_r2_bucket.cla_evidence`
sets `location = "WEUR"`, which is a **placement hint, not a jurisdiction**… The safeguard for
this transfer is therefore the DPF/SCC mechanism alone."*

**PA-7 §(f) Retention** — *"**Indefinite**. License grants under the CLA are irrevocable and
survive any withdrawal of the signature record. Art. 17 erasure of the record will be honoured
on request…"* — with §(g) recording the ten-year figure as *"a 10-year retention **floor**"*
(`maxAgeSeconds = 315360000`).

## Enumerated Inventory

**This table is the contract.** `/work` verifies each row individually against the verbatim
current text. A `sed` sweep is forbidden: three of the four classes contain no `weur` token.
Line numbers locate; the **verbatim sentence** is the anchor.

### Class A — third-country transfer / EU-region (10 canonical + 10 mirror)

| # | File | Line | Verbatim current text (the false clause) |
|---|---|---|---|
| A1 | `docs/legal/privacy-policy.md` | 120 | "an off-site **CLA evidence archive** is maintained at a Cloudflare R2 bucket (`soleur-cla-evidence`, region `weur` -- Western Europe)" |
| A2 | `docs/legal/privacy-policy.md` | 122 | "retained for ten (10) years on the off-site archive (R2 Lock Rules age-based retention, EU region)" *(also Class C — row C1)* |
| A3 | `docs/legal/privacy-policy.md` | 385 | "- **Storage location:** Cloudflare R2 bucket `soleur-cla-evidence`, region `weur` (Western Europe). Intra-EU processing -- no third-country transfer for archive contents at rest." |
| A4 | `docs/legal/data-protection-disclosure.md` | 172 | "at a Cloudflare R2 bucket (`soleur-cla-evidence`, region `weur` -- Western Europe)" **and** "**Sub-processors:** Cloudflare R2 (storage, EU region) and FreeTSA TSA (timestamping authority, DE -- EU)." *(second clause also Class B — row B1)* |
| A5 | `docs/legal/data-protection-disclosure.md` | 264 | §4.2 table row: "CLA evidence archive (`soleur-cla-evidence` bucket, region `weur`; R2 Lock Rules age-based retention, 10yr floor)" |
| A6 | `docs/legal/data-protection-disclosure.md` | 359 | "- **Cloudflare R2 (CLA evidence archive):** EU region (`weur` -- Western Europe). R2 Lock Rules age-based retention, 10yr floor. Intra-EU processing for archive contents at rest." |
| A7 | `docs/legal/gdpr-policy.md` | 62 | "Cloudflare R2 hosts the off-site CLA evidence archive `soleur-cla-evidence` in region `weur` (Western Europe)." |
| A8 | `docs/legal/gdpr-policy.md` | 96 | "(b) the off-site Cloudflare R2 evidence archive `soleur-cla-evidence`, region `weur` (Western Europe), under R2 Lock Rules with an age-based ten (10) year retention floor" |
| A9 | `docs/legal/gdpr-policy.md` | 103 | "(b) the bucket region is EU (`weur`) and R2 Lock Rules use age-based retention so an administrator override remains possible for Article 17 erasure cases" — **a load-bearing limb of the Art. 6(1)(f) proportionality test** |
| A10 | `docs/legal/gdpr-policy.md` | 106 | "The off-site archive does not introduce a third-country transfer for archive contents at rest (Cloudflare R2 `weur` is in Western Europe) and FreeTSA is operated from DE -- intra-EU." |
| A1′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 129 | mirror of A1 — currently byte-identical |
| A2′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 131 | mirror of A2 |
| A3′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 394 | mirror of A3 |
| A4′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 181 | mirror of A4 |
| A5′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 273 | mirror of A5 |
| A6′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 368 | mirror of A6 |
| A7′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 71 | mirror of A7 |
| A8′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 104 | mirror of A8 |
| A9′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 111 | mirror of A9 |
| A10′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 114 | mirror of A10 |

### Class B — FreeTSA represented as a recipient / sub-processor (4 canonical + 4 mirror)

| # | File | Line | Verbatim current text |
|---|---|---|---|
| B1 | `docs/legal/data-protection-disclosure.md` | 172 | "**Sub-processors:** Cloudflare R2 (storage, EU region) and FreeTSA TSA (timestamping authority, DE -- EU)." |
| B2 | `docs/legal/data-protection-disclosure.md` | 265 | §4.2 **Service Processors** table row: "\| FreeTSA ([freetsa.org](https://freetsa.org)) -- RFC 3161 Time Stamp Authority \| Monthly RFC 3161 timestamping … \| SHA-256 hash of bucket-state manifest (no personal data) \| Legitimate interest (Article 6(1)(f)) -- Section 2.3(n) \| Public free-of-charge service; no DPA available… \|" |
| B3 | `docs/legal/data-protection-disclosure.md` | 360 | §6.4 transfers bullet: "- **FreeTSA (RFC 3161 Time Stamp Authority):** DE-based public service… Intra-EU processing. No DPA -- the input is not personal data within the meaning of Article 4(1) GDPR" |
| B4 | `docs/legal/gdpr-policy.md` | 63 | §2.2 bullet — **verify-only**: already states "Because the input is not personal data within Article 4(1), FreeTSA processing falls outside Article 28 sub-processor scope; we disclose the dependency here for completeness." Classify against §(d); change only if the CLO rules it insufficient. |
| B1′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 181 | mirror of B1 |
| B2′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 274 | mirror of B2 |
| B3′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 369 | mirror of B3 |
| B4′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 72 | mirror of B4 |

### Class C — retention stated as a ceiling rather than a floor (7 canonical + 7 mirror)

| # | File | Line | Verbatim current text |
|---|---|---|---|
| C1 | `docs/legal/privacy-policy.md` | 122 | "**Retention:** CLA signature data is retained for ten (10) years on the off-site archive (R2 Lock Rules age-based retention, EU region)" |
| C2 | `docs/legal/privacy-policy.md` | 389 | "- **Retention:** Ten (10) years on the bucket; monthly RFC 3161 timestamps retained indefinitely as part of the chain." |
| C3 | `docs/legal/data-protection-disclosure.md` | 172 | "**Retention:** ten (10) years on the bucket; monthly RFC 3161 timestamps retained indefinitely as part of the evidentiary chain." |
| C4 | `docs/legal/gdpr-policy.md` | 100 | "A separate balancing test is required because (i) the data set is materially broader and (ii) **retention is hard-set at 10 years rather than indefinite**." — directly contradicts §(f) |
| C5 | `docs/legal/gdpr-policy.md` | 103 | "**(2) Necessity and proportionality.** The retention period of 10 years is calibrated to the longest statutory limitation period likely to apply…" — the proportionality limb |
| C6 | `docs/legal/individual-cla.md` | 26 | "The signature record is retained for ten (10) years from the date of signature, balancing GDPR proportionality against the German and UK statutory limitation periods applicable to copyright disputes." — **CLO ruling sought (Fork 4a)** |
| C7 | `docs/legal/corporate-cla.md` | 26 | same sentence, "the signature record" phrasing — **CLO ruling sought (Fork 4a)** |
| C8 | `docs/legal/data-protection-disclosure.md` | 155 | §2.3(d): "an off-site evidence archive of the same record is **retained for ten (10) years** per Section 2.3(n)" — **found by the correctness review; the first enumeration missed it.** It is a *second* retention claim in the same document, in the CLA-signatures item rather than the archive item. |
| C1′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 131 | mirror of C1 |
| C2′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 398 | mirror of C2 |
| C3′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 181 | mirror of C3 |
| C4′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 108 | mirror of C4 |
| C5′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 111 | mirror of C5 |
| C6′ | `plugins/soleur/docs/pages/legal/individual-cla.md` | 27 | mirror of C6 |
| C7′ | `plugins/soleur/docs/pages/legal/corporate-cla.md` | 27 | mirror of C7 |
| C8′ | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 164 | mirror of C8 |

### Class D — the transfer is absent where Art. 13(1)(f) requires it (2 canonical + 2 mirror)

Not false sentences; **missing** ones. `DPD §6.4` has a (false) entry — row A6. The other two
transfer sections have none at all: their only Cloudflare entry is scoped to the CDN role.

| # | File | Anchor | Gap |
|---|---|---|---|
| D1 | `docs/legal/privacy-policy.md` | §10 "International Data Transfers" (heading at :557); insert after "- **Cloudflare:** Global CDN…" (:570) | No CLA-evidence-archive transfer entry |
| D2 | `docs/legal/gdpr-policy.md` | §6 "International Data Transfers" (heading at :427); insert after "- **Cloudflare:** Global CDN…" (:436) | No CLA-evidence-archive transfer entry |
| D1′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | heading at :563; anchor bullet at :576 | mirror of D1 |
| D2′ | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | heading at :420; anchor bullet at :429 | mirror of D2. **Note the mirror sits ABOVE the canonical line number here** — anchor on text, never on offset. |

### Class E — contractual representation outside the published corpus (4 rows)

| # | File | Line | Verbatim current text |
|---|---|---|---|
| E1 | `knowledge-base/legal/data-processing-agreement-template.md` | 210 | §11.1: "Where an Authorized Sub-processor processes Customer Data exclusively within the European Economic Area ("EEA"), **no transfer mechanism under Chapter V GDPR is required**. Per Schedule 2, the following sub-processors are EEA-only: … **Cloudflare R2 (region `weur` — Western Europe)** …" |
| E2 | `knowledge-base/legal/data-processing-agreement-template.md` | 317 | Schedule 2 row, Location column: "EU (region `weur` — Western Europe)" |
| E3 | `knowledge-base/legal/data-processing-agreement-template.md` | 317 | **RULED IN by the CLO (Fork 4b) — upgraded from flag-only:** the same row attributes `chat-attachments/*` to Cloudflare R2. It is a **Supabase Storage** bucket — verified at `apps/web-platform/scripts/dsar-export-oversize.sh:104`, which lists it via `${SUPABASE_URL}/storage/v1/object/list/chat-attachments`. Independent defect class; file a tracking issue. |

| E4 | `knowledge-base/legal/data-processing-agreement-template.md` | 378 | **FOUND BY THE CLO.** §8 Availability + DR: "Hetzner Helsinki primary; **Cloudflare R2 multi-region for object storage (`weur`)**; Supabase platform availability commitments." Two defects: the residency implication, and an implied R2 multi-region availability property for customer attachments that the corrected attribution shows this estate does not have. |

Blast radius for E1/E2/E3/E4 is zero: `knowledge-base/legal/tenant-dpa-register.md` Rows is empty,
so no executed instrument carries any of these representations. **None of the five CI gates fires
on this file** (it lives under `knowledge-base/legal/`, not `docs/legal/**`) and it has no mirror.

### Class G — same defect class, found by the CLO during the ruling (1 canonical + 1 mirror)

| # | File | Line | Verbatim current text |
|---|---|---|---|
| G1 | `docs/legal/privacy-policy.md` | 386 | §5.11 Object Lock bullet: "- **Object Lock:** **Governance mode** with a ten (10) year retention floor." — "Governance mode" is **S3 Object Lock** terminology. §(g) records a Cloudflare **R2 Lock Rule** (`cla-evidence-10yr-retention`, Age condition). The corpus names a mechanism the infrastructure does not use. |
| G1′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | 395 | mirror of G1 — currently byte-identical |

### Class H — the same false claims outside the legal corpus (3 rows, found by the advisor consult)

None of these is gated by any of the five legal CI gates, and none has a mirror. H1 is the most
serious of the three: it is the document a person **follows** when executing an Art. 17 erasure.

| # | File | Line | Verbatim current text | Disposition |
|---|---|---|---|---|
| H1 | `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` | 9 | "Operations runbook for the off-site CLA evidence archive (`soleur-cla-evidence` R2 bucket, **region `weur`**, R2 Lock Rules age-based retention with a 10-year floor providing write-once-read-many (WORM) semantics)." | **IN.** Only the residency implication is wrong — "10-year floor" is already correct here. Verified: this is the file's **only** hit for `weur\|EU\|Europe\|third-country\|ten (10)\|10.year\|indefinit`. |
| H2 | `apps/cla-evidence/infra/README.md` | 14 | "**Region:** `weur` (Western Europe, best-effort per Cloudflare R2 placement)." | **IN.** Nearly right — "best-effort placement" is accurate — but it never says the hint is not a jurisdiction, which is the inference the whole defect family rests on. One clause. |
| H3 | `knowledge-base/operations/expenses.md` | 56 | Cloudflare R2 (cla-evidence) ledger row, Notes cell: "Off-site CLA signature archive, **Governance object-lock, 10yr retention, region weur**." | **IN.** Carries all three defects in one cell (S3 terminology, retention-as-ceiling, residency). Trivial edit; leaving it would leave the ledger contradicting the register. |

**Not a row — recorded so it is not re-litigated.** `apps/web-platform/infra/workspaces-luks-header.tf:46`
sets `location = "WEUR"` on a **different** bucket. Verified: that bucket is named in **no** legal
document (`grep -rn "workspaces-luks-header\|luks-header" docs/legal/ plugins/soleur/docs/pages/legal/
knowledge-base/legal/` → zero hits), so there is no false disclosure to correct. It is noted here
only so that a future disclosure about that bucket does not reproduce the same misreading. **Do not
generalise this plan's conclusion to it** — the register's finding was derived for
`soleur-cla-evidence` specifically, from `apps/cla-evidence/infra/iam.tf`.

**Not a row — the technical fork, decided here rather than asked.** Per
`hr-technical-fork-is-not-an-operator-question`: is migrating the bucket to Cloudflare's EU
jurisdiction tier the real fix, rather than correcting prose? **No.** The register's §(e)
re-evaluation trigger already answers it: such a migration "would **not**, on its own, convert this
cell to a no-transfer posture — that would additionally require the contracting entity and the
access path to cease being US-established." The transfer arises from importer identity. Prose
correction is the whole fix. The knowledge that `WEUR` is a placement hint is already recorded in
the Terraform root at `apps/cla-evidence/infra/iam.tf:14`; no `.tf` file is edited by this PR.

### Class F — the register's own forward reference (1 row)

| # | File | Line | Verbatim current text |
|---|---|---|---|
| F1 | `knowledge-base/legal/article-30-register.md` | 162, inside §(e) | "**[2026-08-19 CORPUS DIVERGENCE (#7601): … currently represent this archive as EU-region and state that it introduces no third-country transfer. Those statements are superseded by this cell and are tracked for correction at #7624. Until that lands, this cell governs.]**" — becomes false the moment this PR merges. §(e)-scoped only; does **not** touch §(c) and so does not collide with #7625. |

### Class I — cross-references in other files that a Class-B change could falsify (2 rows, VERIFY-ONLY)

The `2026-07-16` learning in reverse: not a dangling clause inside the edited sentence, but a
**cross-reference in a different file** that a removal would silently falsify. AC12 as originally
written covered only the surviving sentence, which is why the correctness review found these.
Under the CLO's Fork 3 ruling both stay true — the FreeTSA row is **re-characterised, not
removed** — so both are verify-only. They are listed because that outcome must be *confirmed*, not
assumed: if any later revision reverts to removal, these two become false in the same commit.

| # | File | Line | Verbatim current text | Why it is at risk |
|---|---|---|---|---|
| I1 | `knowledge-base/legal/terms-and-conditions-contradiction-register.md` | 133 | "\| DPD §4.2 Web Platform table \| those four **plus** Sentry, Resend, **Anthropic PBC**, Cloudflare R2, **FreeTSA**, LinkedIn Ireland, Microsoft Ireland, Bullet Train (Flagsmith) \|" | Enumerates the DPD §4.2 table membership. A removal of row B2 falsifies it. **13th file.** |
| I2 | `knowledge-base/legal/data-processing-agreement-template.md` | 334 | "FreeTSA \| RFC 3161 TSA (DPD §2.3(n)) … \| **DPD §4.2 FreeTSA row**" | A direct cross-reference to the row. A removal leaves it dangling. |

### Class J — journey gaps the corrections would leave open (2 canonical + 2 mirror)

Found by the flow review. These are not false sentences; they are hops in the data subject's
journey where, **after** every Class-A/B/C correction lands, the subject still gets no transfer or
no accurate retention answer at the surface they are actually reading.

| # | File | Anchor | Gap |
|---|---|---|---|
| J1 | `docs/legal/privacy-policy.md` | §4.5, after the Retention paragraph (:122) | §4.5 **is** the Art. 13 collection notice for CLA data, and `gdpr-policy.md:104` names it as a notice surface. A1/A2 remove the false residency but add no transfer, no safeguard and no pointer. A subject who stops at §4.5 still receives no Art. 13(1)(f) disclosure. **Add a one-sentence pointer to §5.11 and §10.** |
| J2 | `docs/legal/privacy-policy.md` | §7 Data Retention (heading :472) | §7 carries bullets for plugin, Web Platform, statutory markers, docs site, repository interactions, newsletter and LinkedIn — and **no CLA bullet**. The §(f) "indefinite" correction never reaches the section a subject reads for retention. **Add a CLA-evidence-archive bullet.** |
| J1′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | mirror of J1 | as above |
| J2′ | `plugins/soleur/docs/pages/legal/privacy-policy.md` | mirror of J2 | as above |

**A third journey gap is already discharged by the CLO ruling, recorded so it is not re-opened:**
`gdpr-policy.md:104` limb (3) is the corpus's own map of notice surfaces and it names the CLA
preambles, which carry no transfer disclosure. CLO 2C appends a sentence to exactly that bullet,
and CLO 4(a)'s cross-reference recommendation makes the preambles a valid **layered** notice under
WP29 transparency guidance. This plan therefore **elevates CLO 4(a)'s "recommended, not required"
cross-reference to REQUIRED** — a layered notice is only valid if the pointer is specific and the
linked layer is accurate, and the flow review showed the pointer is what closes the hop.

### Row arithmetic

Stated explicitly so the aggregate can be audited against its parts. **This table has been wrong
twice** — first at 34 (a fabricated aggregate), then at 50/45 (a correct class sum with an
under-counted dedup). The per-file anchor enumeration below is the check that catches both.

| Class | Rows | Notes |
|---|---|---|
| A | 20 | third-country / EU-region; 10 canonical + 10 mirror |
| B | 8 | FreeTSA; B4/B4′ **verify-only** (CLO Fork 3(d): no change) |
| C | 16 | retention-as-ceiling; 8 canonical + 8 mirror (C8/C8′ added by the correctness review) |
| D | 4 | Art. 13(1)(f) omissions; additions, not corrections |
| E | 4 | DPA template: §11.1, Schedule 2 location, `chat-attachments` attribution, §8 |
| F | 1 | register §(e) back-reference |
| G | 2 | "Governance mode" S3-terminology defect |
| H | 3 | same claims outside the legal corpus |
| I | 2 | cross-references in other files; **verify-only** under the CLO's Fork 3 ruling |
| J | 4 | journey gaps; additions, not corrections |
| **Total rows** | **64** | |

**Distinct anchors, enumerated per file** (the dedup check):

| File | Anchors |
|---|---|
| `docs/legal/privacy-policy.md` | 8 — A1(120), A2≡C1(122), A3(385), G1(386), C2(389), D1(§10 ins.), J1(§4.5 ins.), J2(§7 ins.) |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 8 — mirrors of the above |
| `docs/legal/data-protection-disclosure.md` | 6 — C8(155), A4≡B1≡C3(172), A5(264), B2(265), A6(359), B3(360) |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 6 — mirrors |
| `docs/legal/gdpr-policy.md` | 7 — A7(62), B4(63), A8(96), C4(100), A9≡C5(103), A10(106), D2(§6 ins.) |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 7 — mirrors |
| `docs/legal/individual-cla.md` + mirror | 2 — C6(26), C6′(27) |
| `docs/legal/corporate-cla.md` + mirror | 2 — C7(26), C7′(27) |
| `knowledge-base/legal/data-processing-agreement-template.md` | 4 — E1(210), E2≡E3(317), I2(334), E4(378) |
| `knowledge-base/legal/article-30-register.md` | 1 — F1(162) |
| `knowledge-base/legal/terms-and-conditions-contradiction-register.md` | 1 — I1(133) |
| `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` | 1 — H1(9) |
| `apps/cla-evidence/infra/README.md` | 1 — H2(14) |
| `knowledge-base/operations/expenses.md` | 1 — H3(56) |
| **Total anchors** | **55** across **16 files** |

**Nine rows share an anchor with another row.** `docs/legal/data-protection-disclosure.md:172` is
the worst offender — that single line carries **three** distinct false claims (`region weur` = A4,
the `**Sub-processors:**` list = B1, and `**Retention:** ten (10) years` = C3), and the same holds
on its mirror. The full shared-anchor set is:
`A4 ≡ B1 ≡ C3`, `A4′ ≡ B1′ ≡ C3′`, `A2 ≡ C1`, `A2′ ≡ C1′`, `A9 ≡ C5`, `A9′ ≡ C5′`, `E2 ≡ E3`.
64 rows − 9 dedups = **55 anchors**, which reconciles.

Of the 64 rows: **60 require an edit**, **4 are verify-only** (B4, B4′, I1, I2).

**Row count is not the closure criterion.** A row count certifies that a list was worked, never
that the list was the right list — and this inventory has grown three times: Class G from the CLO
ruling, Class H from the advisor consult, and C8/C8′ + Classes I and J from the review panel,
totalling 14 rows the first enumeration missed. The closure criterion is therefore **AC10's
residual-token sweep over the tracked tree**; the inventory is the work-list that makes each
individual correction verifiable. A residual sweep survives a missed row; a row count does not.

## Files to Edit

- `docs/legal/privacy-policy.md` — rows A1, A2/C1, A3, C2, D1
- `docs/legal/data-protection-disclosure.md` — rows A4/B1, A5, A6, B2, B3, C3
- `docs/legal/gdpr-policy.md` — rows A7, A8, A9, A10, B4 (verify-only), C4, C5, D2
- `docs/legal/individual-cla.md` — row C6 **(CLO Fork 4a: RULED IN — the strongest Art. 13 case in the set; §0 is the moment the data is obtained)**
- `docs/legal/corporate-cla.md` — row C7 **(CLO Fork 4a: RULED IN)**
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — A1′, A2′/C1′, A3′, C2′, D1′
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — A4′/B1′, A5′, A6′, B2′, B3′, C3′
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` — A7′–A10′, B4′, C4′, C5′, D2′
- `plugins/soleur/docs/pages/legal/individual-cla.md` — C6′
- `plugins/soleur/docs/pages/legal/corporate-cla.md` — C7′
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — re-pin `privacy-policy`,
  `data-protection-disclosure`, `gdpr-policy`, and (if Fork 4a lands IN) `individual-cla`,
  `corporate-cla`
- `apps/web-platform/test/legal-doc-consistency.test.ts` — extend the sentinel table (Phase 4)
- `knowledge-base/legal/data-processing-agreement-template.md` — rows E1, E2, E3, E4 **(CLO
  Fork 4b: RULED IN, highest severity — a contractual warranty, not a disclosure)**. No CI gate
  fires on this file and it has no mirror.
- `knowledge-base/legal/article-30-register.md` — row F1, **§(e) only**. CLO ruling: **append** a
  discharge block; do **not** edit or delete the existing CORPUS DIVERGENCE block, which is the
  audit trail of the divergence period.
- `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` — row H1
- `apps/cla-evidence/infra/README.md` — row H2
- `knowledge-base/operations/expenses.md` — row H3
- **Verify-only, not edited:** `knowledge-base/legal/terms-and-conditions-contradiction-register.md`
  (row I1) and `knowledge-base/legal/data-processing-agreement-template.md:334` (row I2) — both
  remain true under the CLO's re-characterise-in-place ruling, and Phase 5.2 confirms it.

**Not edited, deliberately:** no `.tf` file (the placement-hint fact is already recorded at
`apps/cla-evidence/infra/iam.tf:14`), `apps/web-platform/infra/vector.toml`, any version file, and
`apps/web-platform/test/legal-doc-consistency.test.ts`'s **existing** sentinel rows — the CLO's
rulings were constructed so that no existing sentinel needs editing, which AC6a verifies
empirically rather than assuming.

## Files to Create

- `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md` —
  the CLO advisory reproduced in `## CLO Advisory — Binding Rulings` below, written out verbatim
  as the sign-off record (mirrors the `2026-08-counsel-review-7349.md` precedent). **This is a
  /work Phase 0 deliverable, not a plan artefact** — planning is confined to
  `knowledge-base/project/{plans,specs}/`, so the plan carries the advisory text and /work writes
  the file.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
piped through `jq --arg path … | contains($path)` for all 8 primary Files-to-Edit paths returned
zero matches. The check ran; the corpus is empty for these paths.

## User-Brand Impact

**If this lands broken, the user experiences:** a contributor who signs the CLA and then reads
`soleur.ai/legal/privacy-policy/` §5.11 is told, in the published document, that their signature
evidence never leaves the EU — while the controller's own Art. 30 register records a US transfer.
If this PR lands *partially* (canonical corrected, mirror not), the published page keeps saying
the false thing while the record says the PR fixed it, which is strictly worse than the status
quo because the tracker will read Done.

**If this leaks, the user's data is exposed via:** no new exposure surface — this PR moves no
data. The exposure it addresses is a **transparency** exposure: a data subject cannot exercise
the Art. 15(2) right to be informed of the safeguards for a transfer whose existence the
controller denies in writing.

**Brand-survival threshold:** `single-user incident`. One contributor reading one false
transfer statement is the whole harm; there is no aggregation threshold below which it is
acceptable. `requires_cpo_signoff: true` is set accordingly, and `user-impact-reviewer` runs at
review time.

## Implementation Phases

**Ordering note (from the advisor consult).** Phase 3 — the balancing-test re-derivation — runs
**first**, ahead of the Class-A/B/E edits, and this ordering is load-bearing. The re-derivation is
the only change in the PR with the potential to alter *heading structure* in `gdpr-policy.md`
§3.4, and heading structure is what the mirror heading-sequence assertion, the sentinel
`/Three-part balancing test \(off-site evidence archive\)/`, and every SHA pin key on. Doing the
factual edits first and holding the re-derivation is the sequencing most likely to force a full
re-pin and a sentinel rewrite. The CLO's Fork 2 wording resolves the structural question — §3.4
keeps two balancing tests and the pinned heading survives verbatim — so the risk is already
retired, but the ordering costs nothing and removes the last way it could return.

### Phase 0 — Preconditions and the sign-off record (no corpus edits)

0.1 Write the `## CLO Advisory — Binding Rulings` section out verbatim to
    `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`,
    with frontmatter matching the `2026-08-counsel-review-7349.md` precedent.
0.2 Re-read PA-7 cells (d), (e), (f), (g) at HEAD. If `article-30-register.md` has moved since
    `28612e8cd`, re-derive the governing text before any prose is written.
0.3 Confirm a clean start: `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`
    (expect exit 0, "drift is within the baseline") and
    `bash apps/web-platform/scripts/check-tc-document-sha.sh` (expect exit 0).
0.4 Re-derive the inventory at HEAD. For each of the 56 rows, confirm the verbatim sentence is
    still present. Any row that has moved is **re-anchored on its text**, not skipped — and note
    that Phase 1's own edits shift every later line number in the same file, which is why the
    anchors are sentences and the line numbers are only a locator.
0.5 **Verify the CLA doc-hash mechanism before editing a CLA instrument.** `.github/workflows/cla-evidence.yml`'s *"Compute CLA doc hash at PR base SHA"* step (`id: doc_hash`) hashes the CLA text at `github.event.pull_request.base.sha`. Confirm by reading it that the hash is computed **per PR base**, so existing signatures keep their own hash and only future signatures bind to the corrected text. Both `privacy-policy.md` §4.5 and `gdpr-policy.md` §3.4(2)(a) rest on that hash proving *"the signer agreed to this specific text of the CLA at this point in time"*; the CLO ruled this "the design working", and Phase 0 records that it was checked rather than assumed.
0.6 **File the retention-ceiling issue now** (CLO Fork 2D) and record its number. Everything
    downstream that writes `[#NNNN]` needs it. Title: *"legal: proportionality re-assessment of
    indefinite retention on the CLA evidence archive (Art. 30 PA-7 §(f))"*; labels `domain/legal`
    + `type/chore` + `priority/p2-medium` (all verified present).

### Phase 1 — the balancing-test re-derivation (`gdpr-policy.md` §3.4)

Apply CLO 2A (preamble, row C4), 2B (limb (2) full replacement, rows A9 + C5) and 2C (limb (3)
addition), canonical and mirror in lockstep. Substitute the Phase-0.5 issue number for `[#NNNN]`.
**Limb (1) is not touched** — it already says "age-based retention floor, 10 years", which is
correct. Confirm after the edit that `/Three-part balancing test \(off-site evidence archive\)/`
still matches both surfaces.

The old limb (2) contained the clause *"we accept the 10y floor as proportionate; longer retention
is judged disproportionate at v1"*. Indefinite retention is exactly what that clause declares
disproportionate — which is why a word-swap was never available and the CLO ruled re-derivation.
The replacement drops the clause rather than inverting it, and routes the live question to the
Phase-0.5 issue.

### Phase 2 — Class A (third-country transfer) and Class G

Apply CLO 1A (the two-bullet split at `privacy-policy.md` §5.11), 1B is already done in Phase 1,
and the 1C template table for rows A1, A2/C1, A4, A5, A6, A7, A8, plus C2 and **G1** (the
"Governance mode" → "Cloudflare R2 Lock Rule" correction). Each edit lands byte-identically on the
mirror in the same commit. **Data localisation must not be published as a safeguard anywhere.**

### Phase 3 — Class B (FreeTSA) and Class D (the Art. 13(1)(f) omissions)

3.1 Apply CLO 3(a) (DPD §2.3(n) closing line), 3(b) (the §4.2 table row re-frame **in place** —
    do not move it, the drift gate penalises reordering — plus the clarifying line beneath the
    table), and 3(c) (the §6.4 bullet).
3.2 Rows B4/B4′: **verify only, change nothing** (CLO 3(d)).
3.3 Apply CLO 5(b): the new `privacy-policy.md` §10 paragraph and the new `gdpr-policy.md` §6
    bullet. **Placement ruling: adjacent to the GitHub/repository material, NOT under "For the
    Web Platform:"** — the archive is a repository-interaction surface. On the mirrors use
    `/legal/<slug>/` link form, and match the surrounding bullets' existing autolink convention
    for `<legal@jikigai.com>` — check each surface before writing.

### Phase 4 — Class C remainder (retention) and Class H

4.1 Correct C1, C2 (done in Phase 2), C3 to state ten years as the WORM **floor** and retention as
    **indefinite** per §(f), preserving §(f)'s Art. 17 carve-out framing.
4.2 Apply CLO 4(a): rows C6/C7 in `individual-cla.md` and `corporate-cla.md` §0, plus their
    mirrors. Both are in `NO_BODY_LAST_UPDATED`, so no Last-Updated handling applies. Optionally
    make the following cross-reference specific, as the CLO recommends.
4.3 **Row C8** — `data-protection-disclosure.md:155` §2.3(d), the *second* retention claim in that
    document, and its mirror at `:164`. Missed by the first enumeration; found by the review panel.
4.4 **Class J (journey gaps).** J1: a one-sentence pointer at the end of `privacy-policy.md` §4.5
    to §5.11 and §10 — §4.5 is the Art. 13 collection notice and `gdpr-policy.md:104` names it as
    a notice surface, so a subject who stops there must still reach the transfer. J2: a
    CLA-evidence-archive bullet in `privacy-policy.md` §7 Data Retention, which today carries
    bullets for seven other data classes and none for CLA signatures, so the "indefinite"
    correction never reaches the section a subject reads for retention. Both plus mirrors. **These
    are bullets and sentences, not headings** — AC9's heading-parity invariant is preserved.
4.5 Rows H1 (the Art. 17 erasure runbook), H2 (`apps/cla-evidence/infra/README.md`) and H3 (the
    expense ledger). No CI gate covers these and none has a mirror; they are corrected because
    H1 in particular is the document a person **follows** during a rights request.

### Phase 5 — Class E (the DPA template) and Class F (the register)

5.1 Apply CLO 4(b): §11.1 replacement (E1), the §11.2 covered-list addition, the Schedule 2 row
    split (E2 + E3, with `chat-attachments/*` folded into the **Supabase Inc** row and the
    correction note beneath the table), and E4 at §8.
5.2 **Rows I1/I2 — verify, do not edit.** Confirm that
    `knowledge-base/legal/terms-and-conditions-contradiction-register.md:133` (which enumerates the
    DPD §4.2 table membership, FreeTSA included) and
    `knowledge-base/legal/data-processing-agreement-template.md:334` (which cross-references the
    "DPD §4.2 FreeTSA row") are **still true** after Phase 3. They are, because the CLO ruled the
    row re-characterised rather than removed. If any later revision reverts to removal, both become
    false in the same commit and must move from verify-only to corrected.
5.3 Apply the CLO's register discharge block (F1). **Append** it; leave the existing CORPUS
    DIVERGENCE block unaltered. Substitute the Phase-0.5 issue number for `#NNNN`. Confirm by
    `git diff` that no line of §(c) is in the diff.

### Phase 6 — Anti-regression sentinels

Widen the `checks` tuple at `apps/web-platform/test/legal-doc-consistency.test.ts:121` to
`Array<[string, RegExp, "present" | "absent"]>`, branch the loop at `:142-147` on polarity, add
`stripCorrectionMarkers` to the `absent` arm, and add the fourteen rows plus the dispatch floor
**enumerated concretely in `## Guard Contract`** — that section names every regex literal, so this
phase is actionable without further derivation. Every **existing** row gains `"present"` and is
otherwise untouched (AC6a). Then execute mutation rows 1-6 and harness rows H1-H4 and record each
verdict (AC13).

### Phase 7 — Re-pin and verify

7.1 `sha256sum` each of the **five** edited canonical docs (privacy-policy,
    data-protection-disclosure, gdpr-policy, individual-cla, corporate-cla) and paste each value
    into the matching key of `apps/web-platform/lib/legal/legal-doc-shas.ts`. **This is the last
    content change**, and it is redone after any review-fix commit (the #7349 double-re-pin).
7.2 Run the full local battery in order:
    ```
    bash apps/web-platform/scripts/check-tc-document-sha.sh
    bash scripts/lint-legal-scope-block-placement.sh --base origin/main
    bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main
    cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts
    ```
    If the drift gate fails, the two surfaces have diverged — a real finding to fix, **not a gate
    to suppress**. Do not set `SOLEUR_LEGAL_DRIFT_ACCEPT` (CLO ship checklist item 4).
7.3 Run AC10 / AC10a / AC11 / AC11a / AC11b and paste the classified output into the PR body.
7.4 `git diff origin/main | grep -n '#NNNN'` returns nothing.

## Guard Contract


### Guard 1 — corpus anti-regression sentinels (`legal-doc-consistency.test.ts`)

**Property.** No surface of the published legal corpus — canonical or mirror — asserts that the
CLA evidence archive is EU-region, intra-EU, or free of a third-country transfer, or that its
retention is capped at ten years; and every document that describes the archive's transfer names
the safeguard PA-7 §(e) records.

**Assembly.** The chokepoint is the `checks` table at
`apps/web-platform/test/legal-doc-consistency.test.ts:121`, whose `for` loop at `:142-147` applies
each pattern to **both** `loadSource(doc)` and `loadMirror(doc)`. That loop is the only place in
the repo where a legal-prose proposition is quantified over both surfaces at once; the other four
gates compare hashes, heading sequences, or drift, and are structurally blind to content truth.

**Required mechanism change (measured, not assumed).** The tuple is `Array<[string, RegExp]>` and
the loop hard-codes `toMatch`. Negative sentinels therefore require:

```ts
const checks: Array<[string, RegExp, "present" | "absent"]> = [ … ];
for (const [doc, pattern, polarity] of checks) {
  const source = loadSource(doc); const mirror = loadMirror(doc);
  if (polarity === "present") {
    expect(source, `source ${doc} missing ${pattern}`).toMatch(pattern);
    expect(mirror, `mirror ${doc} missing ${pattern}`).toMatch(pattern);
  } else {
    expect(source, `source ${doc} still carries ${pattern}`).not.toMatch(pattern);
    expect(mirror, `mirror ${doc} still carries ${pattern}`).not.toMatch(pattern);
  }
}
```

Every **existing** row gains a third element `"present"` and is otherwise untouched — AC6a asserts
that from the diff. Note the loop applies each pattern to whole-file text, and JS `.` does not
cross newlines, so every pattern must be satisfiable on a single line.

**The rows to add.** Negative rows are drawn from the *same* token list as AC10's residual sweep,
so the guard and the closure criterion cannot drift apart. Positive rows discharge Property 1 at
each document, which nothing in the first draft asserted.

| Doc | Pattern | Polarity | Discharges |
|---|---|---|---|
| privacy-policy | `/no third-country transfer for archive contents at rest/` | absent | A3, A3′ |
| privacy-policy | `/Governance mode/` | absent | G1, G1′ |
| privacy-policy | `/retained for ten \(10\) years on the off-site archive/` | absent | C1, C1′ |
| gdpr-policy | `/does not introduce a third-country transfer/` | absent | A10, A10′ |
| gdpr-policy | `/bucket region is EU/i` | absent | A9, A9′ |
| gdpr-policy | `/hard-set at 10 years/` | absent | C4, C4′ |
| data-protection-disclosure | `/Intra-EU processing for archive contents at rest/` | absent | A6, A6′ |
| data-protection-disclosure | `/Cloudflare R2 \(storage, EU region\)/` | absent | A4/B1, A4′/B1′ |
| data-protection-disclosure | `/retained for ten \(10\) years per Section 2\.3\(n\)/` | absent | C8, C8′ |
| individual-cla | `/retained for ten \(10\) years from the date of signature/` | absent | C6, C6′ |
| corporate-cla | `/retained for ten \(10\) years from the date of signature/` | absent | C7, C7′ |
| privacy-policy | `/EU-US Data Privacy Framework/` | present | Property 1 at PP |
| gdpr-policy | `/EU-US Data Privacy Framework/` | present | Property 1 at gdpr |
| data-protection-disclosure | `/EU-US Data Privacy Framework/` | present | Property 1 at DPD |

**Dispatch floor** (anti-vacuity): `expect(checks.filter(c => c[2] === "absent").length).toBeGreaterThanOrEqual(11);`
plus the existing implicit floor on the positive set. A table that iterates zero times, or whose
negative half is deleted, must red rather than pass silently.

**Mutation matrix** (each row must drive the suite RED):

| # | Mutation | Must redden because |
|---|---|---|
| 1 | Restore `no third-country transfer for archive contents at rest` to `docs/legal/privacy-policy.md` | the PP negative sentinel forbids it on the canonical surface |
| 2 | Restore the same literal to `plugins/soleur/docs/pages/legal/privacy-policy.md` **only**, canonical clean | the loop asserts every pattern against `loadMirror` too — the byte-identical-copy-of-a-false-sentence case this PR exists to close |
| 3 | Delete `EU-US Data Privacy Framework` from `docs/legal/gdpr-policy.md` while leaving the mirror's copy | the positive sentinel is absent from one surface |
| 4 | Delete the entire `checks` array (the guard's own dispatch) | the `for` loop iterates zero times; the dispatch floor is what makes this red instead of a vacuous pass |
| 5 | Add a **second** false-claim surface after a compliant first — reintroduce `Intra-EU processing for archive contents at rest` into DPD §6.4 while PP stays corrected | a check that stops at the first document is itself an instance of the class; the loop must quantify over every row |
| 6 | Restore `retained for ten (10) years from the date of signature` to `docs/legal/individual-cla.md` | the CLA-instrument rows were invisible to the first draft's subject sweep (see AC10a); this row is what makes them mechanically covered |

**Harness rows** (mutations to the SUITE, not the corpus):

| # | Mutation / input | Expected |
|---|---|---|
| H1 | Replace one negative sentinel's regex with a literal absent from every surface (e.g. `/zzz-never-present/`, polarity `absent`) | must **RED** under a deliberate re-introduction of the real literal it replaced — otherwise the negative assertion passes for the wrong reason and is vacuous |
| H2 | A must-PASS input that is **not** the corrected corpus: a fixture doc pair describing the transfer in the register's terms, with different surrounding prose and a different section number | must **PASS** — proves the sentinels key on the proposition, not on a whole-file snapshot |
| H3 | Flip one existing `"present"` row to `"absent"` without changing its regex | must **RED** — proves the polarity field is actually read by the loop and not silently ignored |
| H4 | Broaden `stripCorrectionMarkers` to `t.replace(/.*!/gs, "")` (strip everything) | must **RED** — a strip that removes too much makes every negative sentinel vacuously true, and nothing else in the matrix can see it. Conversely, **delete** `stripCorrectionMarkers` entirely and the suite must also **RED** on the CLO 1A marker, proving the strip is load-bearing rather than decorative |

**The correction markers collide with the negative sentinels — resolved by construction, not by
luck.** The CLO's replacement wording deliberately *quotes* what the text used to say, which is
better transparency than a paraphrase. But that means the forbidden literal is republished inside
the marker. Checked row by row against the CLO wording, exactly one hard collision exists today:
CLO 1A's marker contains `"Intra-EU processing -- no third-country transfer for archive contents at
rest"`, which the PP negative sentinel forbids. Three more are near-misses that survive only on a
word-versus-digit or a tense difference (`hard-set at ten years` vs the sentinel's `hard-set at 10
years`; `introduced no third-country transfer` vs `does not introduce a third-country transfer`).
Shipping on those near-misses would be exactly the fragility this plan's own learnings warn about.

**The negative arm therefore runs against marker-stripped text**, not raw text:

```ts
// Correction markers deliberately quote the superseded sentence. They are transparency,
// not a live claim, so the negative arm must not see them.
const stripCorrectionMarkers = (t: string) =>
  t.replace(/\*\((?:Corrected|Re-derived|Added)[^*]*ref #7624[^*]*\)\*/g, "");
```

Applied only in the `"absent"` branch; the `"present"` branch reads the raw text. **Harness row H4
below is what proves the strip is scoped correctly** — a strip that removed too much would make
every negative sentinel vacuous, which is the failure mode that matters here.

**Reject condition for /work:** a negative sentinel whose forbidden literal appears in corrective
prose *outside* a correction marker. AC11a verifies this empirically for every negative row rather
than trusting the marker regex to have caught everything.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — Every one of the **64** inventory rows carries exactly one disposition — `corrected` / `verified-consistent` / `deferred-with-issue-#N` — reconciled against **rows, not anchors** (nine rows share an anchor; `data-protection-disclosure.md:172` alone carries three). Expected under the CLO's rulings: **60 corrected, 4 verified-consistent, 0 deferred**. The PR body carries
  the inventory table with that per-row disposition. No row is unaccounted for.
- **AC2** — Every published claim about the archive's transfer traces to PA-7 §(e). The PR body
  quotes the register cell beside each new sentence. No safeguard appears in the corpus that
  §(e) does not name; specifically, `grep -rn "adequacy decision" docs/legal/privacy-policy.md
  docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md` returns no *new* hit
  attached to the CLA evidence archive.
- **AC3** — `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0.
- **AC4** — `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` exits 0 with
  "drift is within the baseline".
- **AC5** — `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` exits 0.
- **AC6** — `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` passes.
- **AC7** — Canonical and mirror move in the **same commit** for every edited document pair.
  Verified by walking `git rev-list origin/main..HEAD` and, for each commit touching any
  `docs/legal/*.md`, asserting the same commit touches the corresponding
  `plugins/soleur/docs/pages/legal/*.md`. Use a tempfile (`patch=$(mktemp); git show "$sha" >
  "$patch"; grep -c … "$patch"`), never `printf '%s' "$diff" | grep -q`.
- **AC8** — `LEGAL_DOC_SHAS` re-pinned for every edited canonical doc, in the same commit as the
  final prose byte. Lowercase 64-hex.
- **AC9** — No `##`/`###` heading is added, removed, or reworded on any of the ten documents;
  heading-sequence parity is preserved by construction.
- **AC6a** — **No existing sentinel needed editing.** `git diff origin/main --
  apps/web-platform/test/legal-doc-consistency.test.ts` shows only **additions** to the `checks`
  array; no pre-existing `[doc, pattern]` row is modified or removed. This is asserted, not
  assumed — the CLO's rulings were built to keep all five pinned sentinels green, and that claim
  must be verified by the diff rather than trusted.
- **AC10** — **Residual-token sweep over the tracked tree — this is the closure criterion, not
  the row count.** Run, from the repo root, over `git ls-files` excluding
  `knowledge-base/project/**` and `**/archive/**` (point-in-time records that must retain the old
  text) and excluding `knowledge-base/legal/audits/**` and `knowledge-base/legal/gdpr-gate-report-*.md`
  (dated historical audits):

  ```
  git grep -n -i -E 'weur|Western Europe|no third-country transfer|does not introduce a third-country transfer|Intra-EU processing for archive|hard-set at 10 years|EEA-only|Governance mode|Governance object-lock|signature record is retained|ten \(10\) years' \
    -- . ':!knowledge-base/project' ':!*/archive/*' ':!knowledge-base/legal/audits' ':!knowledge-base/legal/gdpr-gate-report-*.md'
  ```

  **Every** surviving hit is classified in the PR body as `corrected` /
  `true-as-written-and-why` / `historical-and-marked`. The known legitimate survivors at plan time
  are: `apps/cla-evidence/infra/bucket.tf:5-6` and `iam.tf:14` (the Terraform itself — `WEUR` is
  the real value and `iam.tf` already states it is not a jurisdiction),
  `apps/web-platform/infra/workspaces-luks-header.tf:44-46` (a different, undisclosed bucket), the
  register's own §(e) and Vendor-Mapping cells (which state the correct position), and
  `compliance-posture.md:88`. A count is not a classification; each hit needs a reason.
- **AC10a** — **Subject sweep, with its measured blind spot named.** Run `git grep -n
  "soleur-cla-evidence\|CLA evidence\|evidence archive\|FreeTSA\|signature record" -- .
  ':!knowledge-base/project' ':!*/archive/*'` and classify every hit the same way. **The
  `signature record` alternative is load-bearing and was added after measurement:** the four
  CLA-instrument files return **0** for the original four-term pattern — they say only "the
  signature record" — so the sweep the Risks table billed as the completeness mechanism could not
  discover rows C6/C7/C6′/C7′, which the CLO called the strongest Art. 13 case in the set. The
  token sweep (AC10) catches phrasings; the subject sweep catches a site that describes the
  archive without using any of them. Neither subsumes the other, and neither is trusted without
  its blind spot stated.
- **AC11** — **Residual-falsehood check, with one literal per row rather than one per document.**
  The first draft of this AC used three literals and claimed a result "on both surfaces of all
  three primary docs". The correctness review **measured** that claim and it was false:
  `no third-country transfer for archive contents at rest` returns 1 on privacy-policy and **0 on
  gdpr-policy and DPD**, because gdpr-policy phrases it *"does not introduce a third-country
  transfer…"* — a different literal. Three literals were structurally blind to four of the six
  files while asserting a corpus-wide result. The corrected set, each verified against the exact
  row it discharges, run over both surfaces:

  ```
  grep -c "no third-country transfer for archive contents at rest"   # A3, A3'   (PP)
  grep -c "does not introduce a third-country transfer"              # A10, A10' (gdpr)
  grep -c "Intra-EU processing for archive contents at rest"         # A6, A6'   (DPD)
  grep -ci "bucket region is EU"                                     # A9, A9'   (gdpr)
  grep -c "Cloudflare R2 (storage, EU region)"                       # A4/B1, A4'/B1' (DPD)
  grep -c "EU region (\`weur\` -- Western Europe)"                    # A6, A6'   (DPD)
  grep -c "hard-set at 10 years"                                     # C4, C4'   (gdpr)
  grep -c "retained for ten (10) years on the off-site archive"      # C1, C1'   (PP)
  grep -c "retained for ten (10) years per Section 2.3(n)"           # C8, C8'   (DPD)
  grep -c "retained for ten (10) years from the date of signature"   # C6/C7 + mirrors (CLAs)
  grep -c "Governance mode"                                          # G1, G1'   (PP)
  ```

  Each returns **0** on the file it targets. Any literal that returns 0 *before* the fix is a
  defective assertion, not a passing one — /work must confirm each returns ≥1 on `origin/main`
  first, per the "verify the gate on main, then on the fix" discipline.
- **AC11a** — **The negative sentinels are not self-referential.** For every `absent`-polarity row
  in `## Guard Contract`, confirm the forbidden literal appears in the corrected corpus **only**
  inside a `*(Corrected … ref #7624 …)*` marker, and nowhere in live prose. Run the same grep with
  the markers stripped and assert 0. This is what makes `stripCorrectionMarkers` safe rather than
  a blanket suppressor.
- **AC11b** — **The three sites that a partial fix would leave false.** The correctness review
  constructed a concrete implementation that passes every other AC and all five gates while
  leaving three published falsehoods standing. Each is asserted individually:
  `grep -c "Cloudflare R2 (storage, EU region)" docs/legal/data-protection-disclosure.md` → 0;
  `grep -c "does not introduce a third-country transfer" docs/legal/gdpr-policy.md` → 0;
  `grep -c "retained for ten (10) years per Section 2.3(n)" docs/legal/data-protection-disclosure.md` → 0;
  and the same three on the mirrors.
- **AC12** — **Claim-family check (the #7416 trap).** For every sentence from which an entity or
  qualifier is removed, the PR body records what the surviving sentence now asserts and confirms
  it is true. Specifically: after FreeTSA is removed from the DPD §2.3(n) `**Sub-processors:**`
  line, the surviving list is confirmed to be a complete and accurate enumeration; and after
  "EU region" is removed from the retention parenthetical at `privacy-policy.md:122`, the
  surviving clause is confirmed not to imply a residency guarantee by omission.
- **AC13** — Guard 1's mutation matrix rows 1-5 and harness rows H1-H2 are each executed and
  each produces the stated verdict. Output pasted into the PR body. A row that cannot be driven
  RED is a defect in the guard, not a passing result.
- **AC14** — **#7625 stays unbundled, verified executably.** The first draft prescribed
  "`grep`-confirm that no line inside the `**(c) Categories of…**` rows is in the diff" — not
  runnable: the literal contains an ellipsis, and `**(c) Categories of personal data**` occurs
  **35 times** in the register, once per Processing Activity, with no PA-7 anchoring. Executable
  form:
  `git diff origin/main -- knowledge-base/legal/article-30-register.md | grep -c '(c) Categories of personal data'`
  → **0**; plus confirm every diff hunk header's line range falls inside PA-7's §(e) row (line
  162) and excludes §(c) (line 158); plus
  `git diff origin/main -- knowledge-base/legal/article-30-register.md | grep -c '^-'` → **0**,
  which enforces the CLO's append-only ruling (the existing CORPUS DIVERGENCE block must survive
  byte-for-byte).
- **AC15** — **Better Stack disclosure tokens survive in all SIX files, not four.**
  `apps/web-platform/infra/vector.toml` is not in the diff. `validate-vector-config.yml`'s
  `DISCLOSURE_FILES` array (lines 160-167) is **six** entries, and the first draft of this AC named
  only four — it omitted `knowledge-base/legal/article-30-register.md` and
  `knowledge-base/legal/compliance-posture.md`, **the first of which this PR edits** (row F1).
  Assert `grep -q '2457081'` and `grep -q 'eu-fsn-3'` in each of:
  `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`,
  `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`, and
  both `plugins/soleur/docs/pages/legal/` mirrors. The workflow is path-filtered and does not fire
  on this PR — which is precisely the hazard: a removal would go undetected here and red the next
  infra PR, and `main`, instead.
- **AC16** — No version file is bumped: `TC_VERSION`, `TC_DOCUMENT_SHA`, `TC_BUMP_METADATA`, the
  three seed scripts and the `compliance-posture.md` T&C row are all unchanged.
- **AC17** — The CLO advisory is committed at
  `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md` and
  every fork's ruling is reflected in the diff. Any post-advisory rebase or review-fix commit
  invalidates the sign-off and requires a re-read (per
  `2026-08-02-the-retraction-pr-was-itself-over-claiming…`).
- **AC18** — The Tier classification (`Tier 1 — material`) is stated in the PR body per
  `knowledge-base/legal/tc-version-bump-policy.md` § Non-T&C legal docs.
- **AC19** — Tracking issue filed for E3 (`chat-attachments` mis-attributed to Cloudflare R2 in
  the DPA template Schedule 2), citing
  `apps/web-platform/scripts/dsar-export-oversize.sh:104` as the evidence. Labels
  `domain/legal` + `type/chore` + `priority/p3-low` — all three verified present at plan time
  via `gh label list --limit 200`.
- **AC20** — If the CLO's Fork 2 ruling defers the balancing-test re-derivation, the deferral
  carries a filed issue **and** an entry in `article-30-register.md` § *Outstanding
  counsel-review items*. A deferral with neither is invisible.

### Post-merge

- **PM1** — **Fetch all three published mirrors, not one page.** The first draft fetched only
  `soleur.ai/legal/privacy-policy/` §5.11 — which would not detect a mirror miss on two of the
  three documents, in a plan whose own `## User-Brand Impact` calls a mirror miss "strictly worse
  than the status quo". Fetch `https://soleur.ai/legal/privacy-policy/`,
  `https://soleur.ai/legal/gdpr-policy/` and `https://soleur.ai/legal/data-protection-disclosure/`
  and assert, on the rendered HTML of each: the AC11 negative literals return 0, and
  `EU-US Data Privacy Framework` returns ≥1. Also confirm the PP §4.5, §7 and §10 additions and the
  gdpr §6 addition render. Automatable via `curl` + `grep` — not an operator step.
- **PM2** — **Verify the deferred items actually exist**, rather than trusting the pre-merge
  self-assertions in AC19/AC20. Re-read `knowledge-base/legal/article-30-register.md`
  § *Outstanding counsel-review items* on `main` and confirm the retention-ceiling entry is
  present; `gh issue view <retention-ceiling-issue>` and `gh issue view <E3-tracking-issue>` both
  return `OPEN`. A filed-then-lost deferral is invisible, which is the whole reason
  `wg-when-deferring-a-capability-create-a` exists.
- **PM3** — `gh issue close 7624` only after PM1 and PM2 both pass.

## Domain Review

**Domains relevant:** legal (primary), product (advisory — published-surface copy).

### Legal (CLO)

**Status:** reviewed — advisory requested at plan time on five binding forks; the ruling is a
plan input, not a review comment. See `## Questions for the CLO` and the committed advisory.

### Product/UX Gate

**Tier:** none. No file in `## Files to Edit` or `## Files to Create` matches the UI-surface
glob set (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The Eleventy mirror is
published Markdown, not a UI component. The mechanical override does not fire.

### GDPR / Compliance Gate (Phase 2.7)

The canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex (schemas, migrations, auth flows,
API routes, `.sql`) matches nothing in this diff — this PR moves no data and adds no processing.
The substantive compliance review is the CLO advisory above, which is the correct specialist for
an Art. 13(1)(f) disclosure defect. `/soleur:gdpr-gate` is deferred to `/work`, where a real diff
exists for it to scan.

## Architecture Decision (ADR/C4)

**None.** This PR makes no architectural decision: no ownership or tenancy boundary moves, no
substrate or integration pattern is introduced, no resolver or trust boundary changes, and no
existing ADR is reversed or extended. The system is unchanged; only the description of it is
corrected, and the corrected description already landed in the register at #7622. A competent
engineer reading the existing ADRs and C4 model would not be misled about the system after this
plan ships, because the plan changes nothing the model describes.

## Observability

**Skipped, with reason.** No file in `## Files to Edit` falls under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface is
introduced. `apps/web-platform/lib/legal/legal-doc-shas.ts` is a constant table re-pin with no
runtime error path, and `apps/web-platform/test/legal-doc-consistency.test.ts` is a test. The
five CI gates enumerated above **are** the observability for this change class: a regression
reddens `tc-document-sha-guard`, `test-webplat`, or `test-scripts` on the next PR.

## Encryption Posture

**Skipped.** No persistent store and no cross-component connection is introduced. The R2 bucket
already exists and its posture is unchanged — this PR corrects how that posture is *described*.

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

> `- **(2) Necessity and proportionality.** **Retention on the archive is indefinite, not ten years.** The ten-year figure that appeared here before 2026-08-20 described the R2 Lock Rule (`maxAgeSeconds = 315360000`), which is a **minimum** period during which an object cannot be deleted -- a floor that guarantees the record survives, not a ceiling that removes it. Nothing deletes an object at ten years. Necessity for indefinite retention rests on the irrevocability of the grant: the licence granted by the CLA has no end date, so the evidence that it was granted must remain available for as long as the grant can be relied on or disputed. The statutory limitation periods that the earlier text cited (10 years under German civil law, BGB §195 + §199; 6 years under the UK Limitation Act 1980 §5/§9; 30 years under French Code civil art. 2227) explain why the ten-year **floor** is not set shorter; they do not establish that indefinite retention is proportionate, and they are no longer offered as if they did. **Whether a retention ceiling should be adopted is under active re-assessment** at issue [#NNNN]; this Policy will be updated if one is adopted. The data minimisation tests: (a) only data essential to prove that the signer agreed to *this specific text of the CLA at this point in time* is captured (comment body + doc-hash); (b) the R2 Lock Rule is age-based rather than an absolute immutability lock, so the administrator override described in sub-bullet (3) remains available for Article 17 erasure cases -- the floor is enforced but is not absolute; (c) the monthly RFC 3161 timestamp protects only the bucket-state manifest hash -- FreeTSA never sees any contributor data; (d) the bypass-record path for allowlisted bot accounts uses a sanitised key (`dependabot-bot`) so no `[bot]` substring appears in object keys, and `github-actions[bot]` (DB-id 41898282) is filtered out entirely before any write. **The location of the bucket is not offered as a mitigation.** The `WEUR` location hint expresses a placement preference and is not a jurisdictional restriction; the transfer safeguard is the DPF / SCC / CBPR mechanism described at the end of this section, and no limb of this test rests on the data being held in the EEA.`

Note what happened to old sub-bullet (b): it welded the false "bucket region is EU" claim onto a
true one about age-based rules permitting override. The replacement **keeps the true half and
discards the false half** rather than deleting the sub-bullet — the override availability is a
genuine mitigation and the test needs it.

**2C — limb (3) addition.** Append after the constructive-notice sentence:

> `Those notices now disclose both the indefinite retention and the transfer to a processor established in the United States; before 2026-08-20 they did not, and a contributor who read them would have been told the opposite on both points.`

**Limb (1) needs NO change** — it already says "age-based retention floor, 10 years", which is
correct. Do not touch it.

**2D — the tracking issue is BLOCKING ON PUBLISH.** File it before pushing and substitute the
real number for `[#NNNN]` in 2B. Title: *"legal: proportionality re-assessment of indefinite
retention on the CLA evidence archive (Art. 30 PA-7 §(f))"*. Body states it as a controller
decision: given irrevocable grants, is indefinite retention proportionate, or should a ceiling be
adopted with a corresponding expiry path through `gdpr-override.sh`? Route to CLO with CTO input
on whether an expiry path is buildable against the Lock Rule floor. **The PR must not merge
carrying the `#NNNN` placeholder.**

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

**Schedule 2 — SPLIT the mis-attributed row (row E2 + row E3, now RULED IN rather than
now RULED IN).** Replace the single Cloudflare R2 row at line 317 with:

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

> `**[2026-08-20 DIVERGENCE DISCHARGED (#7624): the corpus correction landed.** The published surfaces named in the block above now record the transfer to Cloudflare Inc (US) under DPF + SCCs + CBPR and no longer offer the `weur` location hint as a safeguard. `docs/legal/privacy-policy.md` §10 and `docs/legal/gdpr-policy.md` §6 gained the Art. 13(1)(f) transfer entry that neither had ever carried — an omission the divergence note above did not identify. **One citation in that note was imprecise and is corrected here:** the gdpr-policy processor bullet is at §2.2, not §3.3. **Two further divergences were found by enumeration during the correction and are also discharged:** `docs/legal/individual-cla.md` and `docs/legal/corporate-cla.md` §0 each stated a ten-year retention period against this register's §(f) **Indefinite**, in the instrument the data subject actually assents to at collection time; and `knowledge-base/legal/data-processing-agreement-template.md` §11.1 represented Cloudflare R2 to counterparties as EEA-only requiring no Chapter V mechanism — a contractual representation rather than a disclosure. No tenant DPA had been executed under that template at the date of correction (`tenant-dpa-register.md` Rows table empty), so the correction carries no amendment tail; the same Schedule 2 row also mis-attributed the Supabase Storage bucket `chat-attachments/*` to Cloudflare R2, and that attribution is corrected to Supabase. **The preceding CORPUS DIVERGENCE block is preserved unaltered as the audit trail of the divergence period and must not be read as a description of the corpus as it now stands.** **Not discharged, and deliberately carried forward:** the Art. 6(1)(f) balancing test at `gdpr-policy.md` §3.4 was **re-derived** on the corrected facts rather than patched, because two of its load-bearing premises (an EU bucket jurisdiction, and a ten-year retention ceiling) were false and its proportionality conclusion did not survive their correction. Its proportionality limb now records retention as indefinite and withdraws the limitation-period calibration as a proof of proportionality. **Whether a retention ceiling should be adopted is a controller decision about the processing itself, not a documentation question, and is tracked at #NNNN.** §(c) field omissions remain tracked at #7625 and are untouched by this correction.]**`

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
   `#NNNN` before marking ready.**
7. Not in this PR: #7625, any Last-Updated bump, the retention-ceiling decision itself.

### Standing caveat carried into the PR body

This is the v1 internal counsel-review attestation under the tenant-zero posture; it is not a
substitute for external counsel, which is reserved for the audit frontmatter's re-evaluation
triggers (first arms-length user, EEA-out, regulated industry). Per #7349: **every replacement
above must be read as prose against the register before it ships — two byte-identical copies of a
wrong sentence pass all five gates.**

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A byte-identical false sentence ships to both surfaces and every gate stays green (#7349 class) | The inventory is per-row and per-surface; the guard's negative sentinels run against BOTH surfaces; AC1 requires a disposition for each of the 64 rows; Guard 1 mutation row 2 specifically exercises the mirror-only case. |
| The correction PR commits the error it corrects (`2026-08-01` learning) | AC2 forces every new claim to trace to a quoted register cell. AC10 sweeps by subject, not phrase. AC12 audits the surviving sentence after each removal. |
| A `sed` sweep on `weur` is used and three defect classes survive | Explicitly cut in the Cut List, with the reason: Classes B, C and D contain no `weur` token. |
| Removing FreeTSA strengthens a dangling clause (`2026-07-16` learning) | AC12; and Fork 3 asks the CLO to prefer re-characterisation over deletion where §(d) wants the exclusion visible. |
| A negative sentinel false-fails because the corrective prose quotes the old sentence | Guard 1 reject condition; AC11 verifies the forbidden literals are absent from the corrective prose too. |
| The register edit collides with #7625 | AC14 confines the diff to §(e) and asserts §(c) is untouched. |
| Counsel sign-off goes stale after a review-fix rebase (`2026-08-02` learning) | AC17 treats any post-advisory history rewrite as withdrawing the sign-off. |
| A negative sentinel false-fails on the CLO's own correction marker, which quotes the superseded sentence | Measured: exactly one hard collision (CLO 1A) and three near-misses surviving only on word-vs-digit or tense. Resolved by construction — the `absent` arm runs against marker-stripped text, and harness rows H4 prove the strip is neither too broad nor decorative. |
| The plan's own aggregate counts are wrong (it happened twice: 34, then 50/45) | The arithmetic is now shown as a per-file anchor enumeration that must reconcile with the class sum, and **row count is explicitly demoted from closure criterion to work-list** — AC10's residual sweep is what closes the PR. |
| A verification command is vacuous — returns 0 before the fix and is read as a pass | AC11 requires each literal to return ≥1 on `origin/main` first. The first draft failed exactly this: three literals were blind to four of six files. |
| The CLO ruling is superseded by a fork it did not reach — e.g. that Art. 6(1)(f) is unavailable for indefinite retention plus a US importer | The CLO reached the necessity ground (irrevocable grant, no end date) and did **not** reach unavailability, but it has reached that conclusion elsewhere in this same corpus (`gdpr-policy.md` §3.3, for the PA-32 republication limb). If the re-assessment at the Phase-0.6 issue lands the other way, the lawful basis at PP §4.5, PP §5.11, DPD §2.3(n), gdpr §3.4 and PA-7 §(b) all change. Recorded so the tracking issue is scoped to that possibility rather than to a retention number alone. |
| SHA re-pinned before the final prose byte, then a review fix invalidates it (the #7349 double re-pin) | Phase 7.1 makes the re-pin the last content change; AC8 re-asserts it after review fixes. |

## Sharp Edges

- **The `**Last Updated:**` line cannot be edited in place.** It already drifts canonical↔mirror
  on all three docs (the mirror appends a "correction history on this published page is
  condensed" note). `lint-legal-mirror-drift-baseline.sh` requires HEAD's drift-line sequence to
  be a **subsequence** of the merge base's; an in-place edit of an already-drifting line
  produces a novel drift line and fails with `CONTENT CHANGED` (script lines 393-405). The only
  passing edits are (a) leave it alone — the #7416 precedent — or (b) make canonical and mirror
  byte-identical on that line, which *reduces* drift and passes but drops the mirror's
  condensation note. Fork 5(a) is the decision. `/work` must not improvise here, and must not
  reach for `SOLEUR_LEGAL_DRIFT_ACCEPT` to force it.
- **FIFTEEN sentinel rows are load-bearing, not five — and TWO of them sit on lines this PR
  rewrites.** The first draft of this plan listed five and would have redded CI on its **first**
  Class-A edit. The full table is `apps/web-platform/test/legal-doc-consistency.test.ts:121-141`,
  every row asserted against **both** surfaces. The two that sit on edited lines:
  - `/off-site\s+\*\*CLA evidence archive\*\*/` → `docs/legal/privacy-policy.md:120` = **row A1**
  - `/\*\*\(n\)\*\* \*\*CLA evidence archive \(off-site\):\*\*/` → `docs/legal/data-protection-disclosure.md:172` = **rows A4/B1/C3**

  Two more sit adjacent to edited lines: `/tombstones\/<sha>\.deleted\.json/` (PP §5.11, beside
  A3/C2/G1) and `/Article 17\(3\)\(e\)/` (gdpr-policy, lines 101 and 104, beside C5 and CLO 2C's
  addition). The remaining eleven: the four CLA-preamble rows, `/### 5\.11 Cloudflare R2 \(CLA
  Evidence Archive\)/`, `/Cloudflare Inc.*R2 Storage/`, `/FreeTSA.*RFC 3161 Time Stamp Authority/`,
  `/Cloudflare R2 \(CLA evidence archive\):/` (in **both** DPD and gdpr),
  `/Three-part balancing test \(off-site evidence archive\)/`, and
  `/FreeTSA \(RFC 3161 Time Stamp Authority\):/`. **Corollary: reconcile the bodies, keep the
  headers and the quoted fragments.** The CLO's rulings were constructed to satisfy all fifteen —
  AC6a verifies that from the diff rather than trusting it.
- **The FreeTSA §4.2 placement objection is answered, not outstanding.** An earlier draft of this
  plan said "the defect is the placement, not only the text — a fix that only edits the cell body
  leaves the table's own caption making the claim", while the Risks table simultaneously disfavoured
  removal. That left Fork 3 with two arms both of which the plan itself rejected. The CLO's ruling
  supplies the third: re-characterise **in the Processor cell itself** ("NOT an Article 28
  processor; listed for completeness") **and** add a clarifying line immediately beneath the table.
  The caption stops making the claim because the row now contradicts it explicitly. Do not relocate
  the row — moving it risks the drift gate's reordering verdict for no legal gain, and a new
  subheading would break heading-sequence parity (AC9).
- **Mirror line offsets are not uniform, and an earlier draft of this plan got one wrong.** DPD is
  uniformly `+9`. privacy-policy is `+9` in §§4.5/5.11 but **`+6`** in §10 (heading `557 → 563`,
  anchor bullet `570 → 576`) — the earlier draft said "privacy-policy and DPD are canonical `+9`",
  which is exactly the row an offset-based edit would misplace, and it contradicted this plan's own
  D1′ entry. gdpr-policy is `+9` at §2.2, `+8` at §3.4, and **`−7`** at §6 (canonical `:427` →
  mirror `:420`). **Every edit anchors on the verbatim sentence; the line numbers are a locator
  only** (`cq-cite-content-anchor-not-line-number`). Phase 2's own edits shift every later line in
  the same file, so the numbers in this plan are stale by construction after the first commit.
- **Mirror pages must not carry `](….md)` links.** The drift gate fails any relative-`.md` link
  target on `plugins/soleur/docs/pages/legal/*.md`; the published form is `/legal/<slug>/`. Any
  new cross-reference added in Phase 3.3 must use the published form on the mirror and the
  `.md` form on the canonical — the normaliser collapses both to the same token, so this is a
  *required* divergence, not drift.
- **Gate 5 itself says `NOT CHECKED: a lockstep DELETION`** — at `scripts/lint-legal-mirror-drift-baseline.sh:536`, in the clean-run stdout advisory rather than the header comment block. Removing the same disclosure
  from both surfaces leaves drift unchanged and passes. Only the SHA pin and human review catch
  it. That is precisely the shape of the FreeTSA removal in Phase 2 — hence AC12.
- **The 10-year figure is not uniformly wrong.** It is correct as a description of the R2 Lock
  Rule *floor* (`maxAgeSeconds = 315360000`, §(g)) and wrong as a description of *retention*
  (§(f): indefinite). A blanket removal of "ten (10) years" would delete a true statement about
  the WORM property. Each Class-C row must be read for which of the two it asserts.
- **The DPD §4.2 FreeTSA row already disclaims Art. 28 scope in its own last column** while
  sitting inside a table titled *Service Processors* under a heading titled *Third-Party
  Services and Sub-processors*. The defect is the placement, not only the text — a fix that only
  edits the cell body leaves the table's own caption making the claim.
- **`EXPECTED_COUNT=9` in the SHA guard must not be touched.** It is a warning-only tripwire on
  the `docs/legal/*.md` glob and is separately asserted by
  `legal-doc-shas-guard.test.ts` as `len(LEGAL_DOC_SHAS)+1`. No document is added or removed here.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Corrected corpus, all five gates | all exit 0 / pass |
| T2 | Canonical corrected, mirror left false | gate 2's sentinel loop reds on `loadMirror` (Guard 1 mutation 2) |
| T3 | Both surfaces corrected, `legal-doc-shas.ts` not re-pinned | gate 1 exits non-zero **and** `legal-doc-shas-guard.test.ts` baseline assertion fails |
| T4 | `**Last Updated:**` edited in place on both surfaces | gate 5 fails `CONTENT CHANGED` — confirms the Sharp Edge empirically rather than by reasoning |
| T5 | `gdpr-policy.md` §2.2 FreeTSA bullet header deleted | gate 2 sentinel `/FreeTSA \(RFC 3161 Time Stamp Authority\):/` reds |
| T6 | DPD §4.2 FreeTSA table row removed, §2.3(n) retained | gate 2 sentinel `/FreeTSA.*RFC 3161 Time Stamp Authority/` still passes — verifies the removal is safe before it is made |
| T7 | A new mirror bullet added with a `](privacy-policy.md)` link | gate 5's published-link check fails |
| T8 | `checks` array emptied | Guard 1's dispatch floor reds (mutation 4) |
| T9 | A fixture document stating the transfer in the register's terms but different surrounding prose | Guard 1 harness H2 passes — the sentinel keys on the proposition, not a snapshot |

## Non-Goals

- **#7625** (PA-7 §(c) field omissions) — the CLO ruled it must not be bundled. §(c) is not
  edited; AC14 asserts it.
- **`apps/web-platform/infra/vector.toml`** — not edited; AC15 asserts it.
- **Version files** — no bump; AC16 asserts it.
- **#7465 mirror-drift remediation** (target 2026-09-30) — this PR neither grows nor reduces the
  frozen drift beyond the lines it edits.
- **E3, the `chat-attachments` mis-attribution** — a distinct defect class; tracked by the issue
  filed under AC19 rather than fixed here.
- **Enrolling these three docs into `BODY_EQUIVALENCE_DOCS`** — tracked separately at #6585.
