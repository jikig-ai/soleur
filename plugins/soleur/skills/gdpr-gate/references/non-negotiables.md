# Non-negotiables — GDPR-first, CCPA + HIPAA secondary

Written from scratch for Soleur. The gate's findings sit on these load-bearing articles. Treat each item as a falsifiable claim — if it cannot be answered "yes" against the change under audit, the gate emits a finding.

## GDPR (first-class)

### Art. 5 — Principles relating to processing
- **5(1)(a) lawfulness, fairness, transparency** — every processing activity has a lawful basis (Art. 6 / Art. 9) declared and reachable.
- **5(1)(b) purpose limitation** — purposes are specified explicitly; new uses cannot silently piggyback on old consent.
- **5(1)(c) data minimisation** — collect only what's needed for the declared purpose.
- **5(1)(d) accuracy** — corrections are propagated; no stale duplicates linger in audit logs.
- **5(1)(e) storage limitation** — retention is bounded; "forever" is not a retention policy.
- **5(1)(f) integrity and confidentiality** — encryption at rest + in transit (see data-in-transit layer).

### Art. 6 — Lawful basis (REQUIRED)
Every column or processing path needs ONE of: consent, contract, legal obligation, vital interests, public task, or legitimate interests. The gate looks for an annotated lawful basis (e.g., comment `-- LAWFUL_BASIS: contract`) on new schema columns. Missing annotation → `Important` finding (`check_id: GDPR-Art-6`).

### Art. 9 — Special categories (LOAD-BEARING)
Health, genetic, biometric, sex life, sexual orientation, trade-union, religious / philosophical, political, racial / ethnic — see `references/fields.md` Art. 9 list. Column-name match → `Critical` finding (`check_id: GDPR-Art-9`). Critical is reserved for Art. 9 in v1; demoting other findings to Important keeps the Critical signal load-bearing.

### Art. 17 — Right to erasure
Schema additions linking to a `users` table need a deletion path. `ON DELETE CASCADE` or an explicit anonymisation migration counts; bare FKs without either → `Important` finding (`check_id: GDPR-Art-17`).

### Art. 20 — Portability
See `layers/data-lifecycle.md` DL-04. Structured machine-readable export reachable for every PII table.

### Art. 25 — Data protection by design
The gate itself is a Soleur-side embodiment. New features touching regulated data must show evidence of the design-time decisions (DPIA when applicable, see Art. 35).

### Art. 30 — Records of processing activities (RoPA)
Every controller/processor with regular processing of regulated data maintains a RoPA. Schema additions that introduce a new processing purpose surface a RoPA-update reminder (advisory note, not a gated finding in v1).

### Art. 32 — Security of processing
Encryption, pseudonymisation, integrity, restoration. See `data-in-transit.md` and `api-layer.md`. Boundary with `security-sentinel`: OWASP/CWE patterns route to security-sentinel; column-level encryption-at-rest gaps route here.

### Art. 33 — Breach notification (72 hours)
Plan-time advisory only — the gate cannot enforce an incident-response runbook. Surfaces as a one-line note when `incident`, `breach`, or `notification` keywords appear in plan prose without a corresponding 72h handler.

### Art. 35 — DPIA threshold
High-risk processing (large-scale special-category, systematic monitoring, automated decision-making with significant effects) triggers a DPIA. The gate flags new schemas matching these patterns with a DPIA-required note.

### Chapter V — Cross-border transfers
See `layers/data-in-transit.md` DT-EU-CB. Each new non-EEA vendor demands a Vendor DPA row in `compliance-posture.md`.

## CCPA / CPRA (secondary)

- **§1798.100–.130** access + deletion + portability (mostly covered by GDPR Art. 15/17/20 audits).
- **§1798.135** opt-out signal — if the codebase processes browser hits, the gate notes Global Privacy Control handling absence as a `Suggestion`.
- **§1798.150** private right of action for data breaches — overlaps with Art. 32; no separate finding in v1.

## HIPAA (secondary)

- **45 CFR §164.502 minimum necessary** — overlaps with GDPR data minimisation.
- **45 CFR §164.312 technical safeguards** — encryption, audit controls, integrity. See data-in-transit, api-layer.
- **45 CFR §164.520 notice of privacy practices** — enforced at content layer (see `legal-audit` skill), not at this gate.

## What this gate is NOT
- Not a legal review. The disclaimer at top of every gate output says so.
- Not a runtime enforcement layer. v1 fires advisory output; v2 may add preflight gates.
- Not a substitute for a DPO. Critical findings prompt operator acknowledgment + GitHub issue creation; the issue is the human-routing channel.
