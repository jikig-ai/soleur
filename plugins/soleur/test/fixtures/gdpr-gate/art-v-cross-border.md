**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `GDPR-Chapter-V` — new non-EEA vendor without compliance-posture.md Vendor DPA row

**Severity:** Important
**Article:** GDPR Chapter V (Art. 44–49 cross-border transfers)
**Location:** apps/web-platform/server/billing.ts:3
**Pattern matched:** `process.env.STRIPE_API_KEY` (Stripe US) introduced; no row matching `Stripe` in `knowledge-base/legal/compliance-posture.md` Vendor DPAs table
**Why this matters:** Each new non-EEA processor is a Chapter V transfer. Without a Standard Contractual Clauses (SCC) basis or Data Privacy Framework participation recorded in `compliance-posture.md`, the transfer lacks a lawful basis at the moment of first processing.
**What to do:** File a Vendor DPA row in `compliance-posture.md` referencing the SCCs / DPF status of the vendor. See `references/layers/data-in-transit.md` DT-EU-CB.
