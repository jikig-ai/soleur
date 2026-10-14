---
title: "CLO attestation — the in-transit TLS claim retracted and qualified (#10136 / #10138 / PR #10326)"
type: clo-attestation
date: 2026-10-15
issue: 10136
also_addresses: [10138]
pr: 10326
attestation-authority: clo
status: "SIGNED-OFF WITH REQUIRED-BEFORE-MERGE R1-R4 (CLO-agent-attested, Soleur-as-tenant-zero v1). Signed as to the text specified in §Rulings, which the discharge record below applies; the CLO agent has not re-read the applied text."
disposition: "BLOCKED against 4e50fb7452 as written (one wording defect, N1). Discharges, without a further CLO read, on a byte-match to the §Rulings text with R2-R4 done. Any deviation comes back here. One deviation is recorded in the discharge record (DPA template line ~180)."
signed_off_at: 2026-10-15
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
blocking_findings: [N1]
required_before_merge: [R1, R2, R3, R4]
tier_classification: "Tier 1 — retraction of an overstated published assurance (`All communication ... is protected by TLS`, `TLS for data in transit` marked FULFILLED) in the Privacy Policy and the Data Protection Disclosure, plus their Eleventy mirrors. Same class as the 6588, 7786 and 2026-09-23 corrections. Recorded per `knowledge-base/legal/tc-version-bump-policy.md` §Non-T&C legal docs step 4."
semver: "No `TC_VERSION` bump: `docs/legal/terms-and-conditions.md` is untouched. The SHA-refresh contract applies and must be redone after R1."
brand_survival_threshold: aggregate pattern
written_against: "HEAD 4e50fb7452, re-measured 2026-10-15, plus the replacement text in §Rulings, which did not yet exist in the tree at that HEAD."
supersedes_as_to_literal_scope: "knowledge-base/legal/audits/2026-07-counsel-review-6588.md — its reading of the s11 and DPD (c) sentences as `user<->platform transport claims, true and unaffected` is superseded as to literal scope only. The dated audit is unedited."
re_evaluation_triggers:
  - "2026-11-12, or TLS landing on the Inngest hop, whichever is first: re-review the Privacy Policy bullet, DPD 8.1(c) and register PA-13 (g)(14)."
  - "2026-10-24 CLO re-ruling: owns the three ledger exception rows, DPD 2.3(o)'s packet-filter sentence, and the three pre-existing items listed on #10136."
  - "First arms-length data subject, EEA-out processing, or a regulated industry: external counsel re-read."
---

> **DRAFT — AI-generated, requires professional legal review. Not legal advice.**

# CLO attestation — #10136 / PR #10326

Internal v1 sign-off by the `clo` agent. The operator keeps an optional veto. External counsel re-review is reserved for the triggers above.

## Verdicts

| Artifact | Verdict |
|---|---|
| Privacy Policy s11 bullet, DPD 8.1(c), both mirrors | **BLOCKED on N1**, then DISCHARGED on the §Rulings text |
| Last Updated entries (4) | Same, conformed to N1 |
| `article-30-register.md` (PA-13 (g)(14) and pointers) | **DISCHARGED** |
| DPA template | DISCHARGED, plus the N1 conformance clause (R3 of the CLO's list of edits) |
| Ledger value change (`not-publicly-claimed`) | DISCHARGED; exception rows left to 2026-10-24 |
| `legal-doc-shas.ts` | DISCHARGED at HEAD; re-pin after R1 |

## Rulings

- **N1.** "Some ... not yet" implies the other links are encrypted, and "not yet" implies a rollout we describe only as "evaluating". The register says other links are "not asserted either way". The replacement text was given in the CLO's Q2 ruling and is the text now in the four published files.
- **Marks.** Use `*(Corrected 2026-10-15, ref #10136: ...)*`, matching the 2026-08-20 batch.
- **No top-of-document paragraph.** The 7786 and 8617 notes substituted for a frozen date line. 6588 and the October entries did not use one.

## Facts

- **Measured 2026-10-15:** the five gates exit 0; the SHA pins match; mirror bullets are byte-identical; `INNGEST_BASE_URL=http://10.0.1.40:8288`; `list-runs.ts` sends the raw signing key as the bearer while the ledger says it never crosses the wire.
- **Measured 2026-10-12:** hop configuration (a configuration read, not a wire capture).
- **Measured 2026-10-14:** which payloads cross the hop (code read).
- **Policy:** "evaluating adding TLS", no commitment and no date.
- **Inherited, not re-measured:** browser-to-platform TLS, vendor legs, peer identity, nftables restrictions. The register does not assert them and neither do I.

## Required before merge

- **R1.** Apply the Q1 marks and Q2 text to canonical and mirror, with the Last Updated and DPA conformance edits.
- **R2.** Re-pin `legal-doc-shas.ts` and re-run all five gates.
- **R3.** Post the #10136 comment: the `list-runs.ts` raw-key versus ledger discrepancy, the remediation (hash the bearer or move the read to TLS), and the 2026-10-24 items.
- **R4.** The PR body states Tier 1 with its reason, that the July 6588 reading is superseded as to literal scope only, and the 2026-11-12 re-review.

## Not cleared

This attests wording accuracy, not transport security. The hop remains plaintext. It is an accepted-by-design ledger exception, and the 2026-10-24 re-ruling still owns it.

A green gate run measures agreement, not truth. The prose and the code were read separately.

## Discharge record (lead, 2026-10-15; not part of the CLO's text)

- **R1 applied** in the commit that adds this file: the Q1 marks and the Q2 replacement text are in the four published files (canonical and mirror), both Last Updated entries are conformed, and the DPD entry says "(not fulfilled)". A byte-level check against `origin/main` plus the intended spans passes for all eight edited files.
- **R2 applied:** both SHA pins re-set; the mirror-drift ratchet, the SHA guard, the encryption-posture sweep, the register lint, the corpus probe and the two legal vitest files were re-run after R1 (results in the PR body).
- **R3 and R4** are carried out on the PR and on #10136 before the PR is marked ready.
- **Recorded deviation:** the CLO's instruction to append "; whether other such links are TLS-encrypted is not stated in this draft." to the DPA template items at lines ~180 and ~373 was applied to the Encryption in transit item only (line ~373). The line-~180 bullet is about Customer-facing endpoints and has no private-network antecedent for "other such links", so appending the clause there would read as a non sequitur. The change narrows nothing the CLO ruled; if the CLO wants the clause at both lines it can say so at the 2026-10-24 re-ruling.
