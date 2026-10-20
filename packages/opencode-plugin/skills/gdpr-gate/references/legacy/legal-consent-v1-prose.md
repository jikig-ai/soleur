<!-- Archived v1 prose-shape — preserved for one release cycle for regulatory-citation provenance. Will be removed at v3. -->

# Legal consent — ePrivacy + GDPR Art. 7 / 13 / 14 / 35

Written from scratch for Soleur. Consent and disclosure flows that the gate checks at design time. Output is advisory; the load-bearing enforcement is in the privacy policy + cookie banner + DPIA docs (`legal-audit` and `legal-generate` skills handle the document side).

## ePrivacy Directive (2002/58/EC) — cookie consent

The ePrivacy Directive predates GDPR but governs storage and access to information on terminal equipment (cookies, localStorage, IndexedDB, fingerprinting).

What the gate checks at plan time:
- Plan prose introducing analytics, A/B-testing, advertising, or cross-site tracking → check for a cookie-consent precondition (`Suggestion` if missing).
- Plan prose introducing a cookie banner → check it implements opt-IN (consent before set), not opt-OUT (set first, ask later) — opt-out cookie banners are non-compliant in EEA.

## Art. 7 — Conditions for consent
- Consent must be **freely given, specific, informed, unambiguous**.
- Withdrawal must be **as easy as giving** consent.
- Consent for special-category processing under Art. 9(2)(a) must be **explicit**.

What the gate checks: schema additions for `consent_given`, `terms_accepted_at`, `privacy_accepted_at` columns flag a `Suggestion` reminder to verify the UX matches Art. 7 ("freely given" rules out pre-checked boxes; "specific" rules out catch-all consent).

## Art. 13 + 14 — Information to be provided

Art. 13 (data collected from the subject) and Art. 14 (data collected from third parties) require disclosure of:
- Identity + contact of the controller
- DPO contact (if applicable)
- Purposes + lawful basis
- Recipients / categories of recipients
- Cross-border transfer destinations + safeguards
- Retention periods
- Data subject rights (access, rectification, erasure, restriction, portability, objection, withdrawal of consent, complaint to supervisory authority)
- Source (Art. 14 only)

What the gate checks: new schema columns / new vendor SDKs route to a one-liner reminder to update the privacy policy. The actual policy content lives in `legal-audit`.

## Art. 35 — Data Protection Impact Assessment (DPIA)

Required when processing is **likely to result in high risk** to data subjects. Indicators:
- Systematic + extensive automated evaluation (Art. 22 profiling).
- Large-scale special-category processing (Art. 9 columns + production scale).
- Systematic monitoring of public space.

What the gate checks: plan-time prose introducing one of the indicators surfaces a DPIA-required note. The DPIA template lives outside this skill.

## Boundary with other skills
- **legal-audit**: scans existing policy / terms / cookie / DPA documents for compliance gaps.
- **legal-generate**: drafts new legal documents.
- **gdpr-gate**: scans diffs and plans for design-time signals that demand a legal-audit / legal-generate follow-up.
