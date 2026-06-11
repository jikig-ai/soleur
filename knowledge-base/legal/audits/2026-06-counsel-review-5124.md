---
title: "Counsel review audit — #5124 (LinkedIn publication surface re-point: Jikigai Page → Soleur Page)"
type: counsel-review
date: 2026-06-10
issue: 4046
pr: 5124
status: SIGNED-OFF (operator-attested)
signed_off_at: 2026-06-10
signed_off_by: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "First Page Insights API call OR first non-Soleur tenant onboarding (carried forward from 2026-05-counsel-review-4051.md)"
---

# Counsel review audit — #5124 (LinkedIn publication surface re-point)

This audit file is the load-bearing evidence for the counsel-review gate on PR #5124, which re-points the LinkedIn Company Page publication surface from the Jikigai Company Page (`linkedin.com/company/jikigai/`, org 112298380) to the new dedicated **Soleur** Company Page (`linkedin.com/company/soleur/`, org 129094054) following the operator's 2026-06-10 brand-separation decision. Each row below is operator-attested in lieu of external counsel review for v1 (Soleur-as-tenant-zero posture), per the precedent established by PR #4081 / #4051 (`2026-05-counsel-review-4051.md`).

**Scope boundary of this review:** the change is a Page-identity substitution only. Controller (Jikigai SARL), developer app (229658411), OAuth token (`LINKEDIN_ORG_ACCESS_TOKEN`), publisher pipeline (`scripts/content-publisher.sh`), scopes (`w_organization_social`), recipients (LinkedIn Ireland, Microsoft Ireland), lawful bases, retention envelopes, and the Art. 17 carve-out mechanics are all unchanged. Zero posts had been published to the prior Page surface (verified 2026-06-10 against the Jikigai Page admin view), so no data subjects migrate between surfaces.

---

## Artifact 1 — Legitimate Interest Assessment (amendment)

**File:** `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`

**Scope of review:** the 2026-06-10 amendment banner and the Page URL/slug substitutions. The Art. 6(1)(f) three-part test (purpose / necessity / balancing) is asserted to apply identically to the new Page identity — the data-subject population definition ("members who follow or engage with the Page") is Page-relative and carries over without re-derivation.

**Particular attention requested on:**
1. Whether a Page-identity change requires a fresh balancing analysis (assessed: no — the processing, audience, and data categories are identical; the new Page starts at zero followers so the initial population is empty).
2. Whether the Jikigai Page's continued existence as a separate, non-publication surface creates a second processing activity (assessed: no — no Soleur-pipeline processing occurs against it; any future Jikigai-page activity would be a new PA).

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture; external counsel re-review trigger: first Page Insights API call OR first non-Soleur tenant onboarding) | 2026-06-10 | Operator attestation via PR #5124 review | ☑ | Approved. Page-identity substitution only; three-part test carries over; re-evaluation triggers unchanged. |

---

## Artifact 2 — Privacy Policy (root + docs-site mirror)

**Files:** `docs/legal/privacy-policy.md`, `plugins/soleur/docs/pages/legal/privacy-policy.md`

**Scope of review:** §4.10 (publication-surface URL), §5.12 (LinkedIn Ireland recipient context), §7 retention (Page reference), §8.1 Art. 17 carve-out (erasure-request target URL), and the Last-Updated chain entry. The Art. 13(1)(e) recipient disclosure is unchanged in substance — same recipients, same roles.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture) | 2026-06-10 | Operator attestation via PR #5124 review | ☑ | Approved. URL re-point only; recipient set and carve-out mechanics unchanged. |

---

## Artifact 3 — Data Protection Disclosure + Article 30 PA15

**Files:** `docs/legal/data-protection-disclosure.md` (§2.3(p), §10.3, Last-Updated chain), `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Last-Updated chain only — the mirror's LinkedIn §4.2 rows carry the pre-existing documented drift, out of scope per PR #4455 note), `knowledge-base/legal/article-30-register.md` (PA15 amendment note + reference re-points).

**Scope of review:** PA15's K-bis business-verification limbs are retained verbatim as historical record — the one-time Microsoft Ireland transfer genuinely occurred via the Jikigai Page admin flow and its documentation must not be rewritten.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| Jean Deruelle (Jikigai SARL gérant, operator-attested in lieu of external counsel review for v1 — Soleur-as-tenant-zero posture) | 2026-06-10 | Operator attestation via PR #5124 review | ☑ | Approved. PA15 amendment preserves the K-bis historical record; lockstep complete. |
