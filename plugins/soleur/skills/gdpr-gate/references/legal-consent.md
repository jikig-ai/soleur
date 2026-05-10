<!-- Soleur-authored — see NOTICE -->

# Layer: Legal Consent (ePrivacy + GDPR Art. 7 / 13 / 14 / 35)

## When This Layer Loads

Auto-trigger inline when the gate is about to evaluate:

- Cookie banner code, consent UI, or any `consent` / `optIn` / `optOut` columns or fields
- A privacy notice, cookie policy, or terms-of-service text change
- A new third-party SDK / pixel / analytics integration
- A schema column whose name matches the Art. 9 special-category list (`fields.md`)
- A new automated-decision or profiling code path (Art. 22)
- A diff that touches `apps/web-platform/lib/auth/consent`, `apps/web-platform/app/api/consent`, or any path containing `consent`, `cookie-banner`, `privacy-notice`, or `dpia`

Also loads during full repo scan.

---

## LC-01: ePrivacy cookie consent — strict opt-in, not opt-out

What to grep:
- `localStorage.setItem`, `sessionStorage.setItem`, `document.cookie =`, `Set-Cookie:`
- `consent.*=.*true` literals (presumed opt-in)
- Cookie-banner code that loads SDKs (`<script src=`, `gtag(`, `fbq(`, `posthog.init(`, `mixpanel.init(`) BEFORE a consent decision is captured
- HTML attributes `checked` on consent inputs
- Strings: "by using this site you agree", "implied consent", "we use cookies"

Flag when:
- A non-essential cookie or storage write happens before a consent decision is recorded
- A consent UI defaults to opt-in (pre-checked box, "Accept" pre-selected, no "Reject" parity button)
- Third-party scripts load on first paint without a consent-gate guard
- The "Reject all" path is harder to reach than "Accept all" (cookie-wall pattern)

Why it matters: ePrivacy Directive 2002/58/EC Art. 5(3) and German TTDSG §25 require **prior, freely-given, specific, informed, unambiguous** consent before any non-essential storage or transmission to the user terminal. Implied consent does not satisfy ePrivacy. Pre-checked boxes are explicitly invalid (CJEU C-673/17 *Planet49*).

Fix pattern:
- Gate every non-essential storage write and SDK load on a recorded consent decision.
- Default to "Reject all" — the consent banner must surface "Accept" and "Reject" with equal prominence on the same screen layer.
- Persist consent records (`consent_decisions` table) with timestamp, jurisdiction, banner version, and lawful-basis snapshot.

Regulation: ePrivacy Directive 2002/58/EC Art. 5(3); TTDSG §25; CJEU C-673/17 *Planet49*; EDPB Guidelines 05/2020 on consent.

---

## LC-02: Art. 7 freely-given consent — no bundling, no pre-checks

What to grep:
- A single consent checkbox covering multiple processing purposes (marketing + analytics + product)
- `required.*consent`, `consent.*required` patterns where consent is a precondition for service access
- Pre-checked boxes (`<input type="checkbox" checked`)
- Consent text that lists multiple recipients or purposes in one bullet

Flag when:
- One consent action covers more than one processing purpose
- Consent is required to use the core service (consent is not freely given when refusal blocks access to a service the user paid for)
- Boxes default to checked
- Consent for marketing is bundled with consent for terms-of-service acceptance

Why it matters: Art. 7(2) requires consent to be **clearly distinguishable** from other matters; Art. 7(4) requires the freely-given nature to be assessed against bundling. EDPB Guidelines 05/2020 §3.1.2 explicitly bans pre-ticked boxes.

Fix pattern:
- Split consent into per-purpose toggles, each defaulting to OFF.
- Decouple service access from consent — the service must remain usable on refusal of non-essential consent.
- Render terms-of-service acceptance as a separate, non-bundled control.

Regulation: GDPR Art. 7; Recital 32; Recital 43; EDPB Guidelines 05/2020 on consent.

---

## LC-03: Art. 13/14 disclosure — purposes, lawful basis, retention, recipients

What to grep:
- Privacy-notice copy, cookie-policy copy, account-creation flows
- Strings: "we may use", "we collect", "we share with"
- Schema migrations that add a new PII column without a corresponding privacy-notice update in the same diff
- API endpoints that send user data to a third party without a disclosure entry

Flag when:
- A new PII column is added but the privacy notice is unchanged in the same diff
- Disclosure copy lacks any of: processing purposes, lawful basis (Art. 6 / Art. 9), retention period, recipient categories, transfer mechanisms (Chapter V)
- A new third-party SDK is added without listing the recipient in the privacy notice

Why it matters: Art. 13 (data collected from the data subject) and Art. 14 (data collected from third parties) require disclosure at the moment data is obtained. Missing disclosure is a documentable Art. 13/14 violation regardless of any operational harm.

Fix pattern:
- Pair every PII-collecting code change with a privacy-notice diff in the same PR.
- Maintain a recipient register (`compliance-posture.md` Vendor DPAs) and link each disclosure entry to a register row.
- Render retention periods per data category, not as a single site-wide blanket.

Regulation: GDPR Art. 13; Art. 14; Recitals 60–62; EDPB Guidelines 04/2019 on transparency.

---

## LC-04: Art. 35 DPIA trigger — profiling, Art. 9 at scale, public-space monitoring

What to grep:
- New automated-decision code paths (`if (score > X) reject`)
- ML-model inference for credit, hiring, insurance, or eligibility decisions
- Schema columns named `risk_score`, `eligibility`, `profile_*`, `predicted_*`
- Art. 9 special-category columns from `fields.md` combined with high-volume / public-facing endpoints
- Camera, microphone, location-tracking, or biometric capture in public spaces

Flag when:
- An automated decision produces a legal effect or similarly significant effect on a data subject without a human-review override (Art. 22)
- Art. 9 data is processed at scale (recital 91: "large scale" assessed by data subjects, volume, duration, geographic coverage)
- Public-space monitoring is added (CCTV, biometric kiosk, geolocation aggregation)

Why it matters: Art. 35 requires a Data Protection Impact Assessment **before** processing where a high risk is likely. Failing to run a DPIA is itself an Art. 35 violation (and indirectly an Art. 5(2) accountability violation) regardless of whether harm materialises. The CNIL, ICO, and BfDI have all issued fines for missing DPIAs.

Fix pattern:
- Run the DPIA template in `legal-audit` skill BEFORE the feature ships.
- Document the Art. 35(7) elements: description, necessity assessment, risk assessment, mitigations.
- Consult `clo` and (for high-risk residual) the supervisory authority under Art. 36.

Regulation: GDPR Art. 35; Art. 36; Recitals 84, 89–96; EDPB Guidelines on DPIA (WP 248 rev.01).

---

## LC-05: Art. 7(3) withdrawal — as easy as giving

What to grep:
- Account-settings UI, preference center, unsubscribe links
- API endpoints `POST /consent`, `DELETE /consent`, `PATCH /preferences`
- Email-template footers
- Strings: "to unsubscribe, contact support", "to revoke consent, email us"

Flag when:
- Withdrawal of consent requires more steps, more authentication, or more friction than giving consent did
- Withdrawal is gated behind a support ticket, email, or phone call when consent was a one-click action
- The withdrawal control is not present on the same surface where consent was originally given
- Withdrawal triggers downstream service degradation that wasn't disclosed at consent time

Why it matters: Art. 7(3) requires withdrawal to be **as easy as giving** consent. EDPB Guidelines 05/2020 §5.4 expand this to mean same channel, same number of steps, same UX surface. Asymmetric withdrawal is a documented violation regardless of intent.

Fix pattern:
- Mirror every consent control with a withdrawal control on the same surface.
- One-click consent → one-click withdrawal.
- Persist withdrawal events in `consent_decisions` with the same fidelity as the original consent grant; downstream processing must terminate within a documented SLA.

Regulation: GDPR Art. 7(3); Recital 42; EDPB Guidelines 05/2020 on consent §5.4.
