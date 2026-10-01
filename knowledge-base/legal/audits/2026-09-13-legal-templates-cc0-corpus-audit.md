# Corpus Audit — General-Legal CC0 Templates (vendored under #8122)

**Date:** 2026-09-13
**Auditor:** legal-compliance-auditor (benchmark mode), run against the vendored corpus at pinned commit `0f7c7bf`
**Scope:** spec-named gate items `privacy-policy-gdpr` and `dpa-global` (the two EU-law-bearing templates a US firm could plausibly under-draft), plus the contamination inventory across all 12.

## Method

- GDPR Art. 13/14 13-item disclosure checklist (per `legal-compliance-auditor` benchmark mode) against `privacy-policy-gdpr`.
- GDPR Art. 28(3) contract-element checklist against `dpa-global` (a DPA is a contract — the checklist is the mandated clause set, not the Art. 13 notice list).
- Vendor-surface inventory: `grep` for `general[-.[:space:]]?legal`, `@`, URLs, and related-party vendor plugs across all 12 files.

## Findings

### privacy-policy-gdpr — 12/13 Art. 13/14 items present

Present: controller identity/contact, DPO contact (conditional clause), purposes + legal bases, legitimate interests, recipients/categories, third-country transfers + safeguards, retention (bracketed-optional section), data-subject rights, consent withdrawal, supervisory-authority complaint right, automated decision-making/profiling, Art. 14 source disclosure (third-party sources section).

- `[MEDIUM] [REGULATORY] Information Provision > Missing Art. 13(2)(e) statutory/contractual-requirement disclosure > The template does not state whether provision of personal data is a statutory/contractual requirement or the consequences of non-provision. Add a clause at fill time or accept the gap for low-risk processing.`

**Verdict: vendor verbatim.** One MEDIUM gap, disclosed to the generator arm — not a drop criterion.

### dpa-global — Art. 28(3) elements structurally complete

Present: documented-instructions clause, confidentiality, sub-processor consent + Annex 5 listing + flow-down, technical/organizational measures (Annex 4), data-subject-request assistance, deletion/return on termination, audit rights, SCC definition (Decision (EU) 2021/914), Annex 2 European Annex + Annex 3 State Privacy Laws Annex routing.

- `[LOW] [REGULATORY] Form > No literal "Article 28" citation > The substance of every mandated element is present; the missing citation is cosmetic — DPAs bind by content, not by citing the article they satisfy.`

**Verdict: vendor verbatim.**

### Contamination inventory (all 12)

- Trailing "prepared by General Legal, PC" credit block in all 12 — retained in corpus, stripped on emit (`strip-vendor-credit.sh`).
- **DecisionLayer arbitration plug** (`decisionlayer.ai`, a General-Legal-affiliated AI-arbitration vendor) present as "OPTION B" inside `employee-offer-letter` and `terms-of-use`. It is a substantive clause, not a credit — the strip does NOT remove it. Generator protocol surfaces it as an explicit user choice and defaults to the JAMS Option A path.
- `@` / URL surfaces beyond the credit: Stripe privacy-policy URL inside an optional `<mark>` example (fill-time content, not vendor promotion).

## Decision

Both spec-gated templates pass benchmark review and remain vendored verbatim. The corpus ships with the DecisionLayer clause documented as an explicit-choice requirement in the generator contract. No drop.
