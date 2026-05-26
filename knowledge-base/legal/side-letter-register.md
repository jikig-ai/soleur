---
title: "Side Letter Register"
type: counterparty-ledger
custodian: clo
template: knowledge-base/legal/side-letter-template.md
schema_version: 1
last_reviewed: 2026-05-22
related:
  - docs/legal/terms-and-conditions.md (Section 3b)
  - docs/legal/acceptable-use-policy.md (Section 5.5)
  - knowledge-base/legal/side-letter-template.md
  - knowledge-base/legal/tenant-dpa-register.md
---

# Side Letter Register

This register records each executed Soleur Side Letter (per `knowledge-base/legal/side-letter-template.md`) between a Workspace Owner and a Co-Member of the same Soleur Web Platform workspace. The register is the operator-facing audit trail for AUP §5.5 owner attestation and Terms & Conditions §3b.4 ("Side Letter and customer-DPA roadmap").

## Schema

| Column | Description |
|---|---|
| Counterparty | Full legal name of the Co-Member (the non-Jikigai party to the Side Letter). |
| Workspace ID | The Soleur Web Platform `workspace_id` (UUID) into which the Co-Member is invited. |
| Signed at | ISO 8601 timestamp (UTC) at which both Parties signed the executed Side Letter. |

Additional columns (PDF SHA-256, template version, external-counsel re-review trigger fired) are derivable from the executed PDF + the corresponding counsel-review audit file (`knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md`) and are intentionally NOT in this register's schema until the register has more than one row (see code-simplicity P1 plan-review note — "Add columns the first time they matter").

## Register

| Counterparty | Workspace ID | Signed at (ISO 8601 UTC) |
|---|---|---|
| (none yet) | | |

## Notes

- This is a SINGLE LEDGER FILE — not a directory of per-counterparty files. Append rows; do not split.
- The executed PDF lives off-repo (encrypted operator drive). The repository carries only the template and this register.
- Counsel-review audit at `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` records the operator-attested counsel sign-off on the template + this register's schema; external counsel re-review triggers are listed in that audit file's §External Counsel Re-Review Triggers section.
- The Side Letter requirement may be superseded by a customer-facing Data Processing Agreement published by Jikigai per Terms & Conditions §3b.4; the supersession will be announced in writing to each Workspace Owner and recorded as an update to the audit file.
- **Delegation Consent Side Letter** (added PR-B #4508 / #4232): delegation-specific acceptances are stored in the `byok_delegation_acceptances` table (migration 074), NOT in this register. The template at `knowledge-base/legal/delegation-consent-side-letter-template.md` is distinct from the workspace co-member Side Letter template — it covers a different consent surface (BYOK delegation cost-telemetry + Art. 26 joint controllership). When a Grantee accepts a delegation in-app, the acceptance row in `byok_delegation_acceptances` serves as the Art. 7 consent evidence; the physical Side Letter signature is a belt-and-braces supplement for the Grantor's records.
