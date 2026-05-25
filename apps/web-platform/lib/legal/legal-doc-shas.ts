/**
 * Per-doc SHA-256 literals for the 8 non-T&C legal documents under
 * `docs/legal/`. These are drift-detection constants ONLY — they are NOT
 * persisted to any audit ledger and have no runtime consumer.
 *
 * T&C exception: `terms-and-conditions.md` keeps its SHA in
 * `apps/web-platform/lib/legal/tc-version.ts` as `TC_DOCUMENT_SHA` because
 * that literal is load-bearing — it is consumed at
 * `app/api/accept-terms/route.ts` (`p_doc_sha` argument to the
 * `accept_terms` RPC) and written into the `public.tc_acceptances` WORM
 * ledger. Mixing the audit-evidence literal with drift-only literals
 * obscures the reader's mental model of which constants gate consent.
 *
 * Drift-only role: each SHA must equal `sha256sum docs/legal/<key>.md` of
 * the canonical doc at the time of the most recent edit. The CI guard
 * (`.github/workflows/ci.yml :: tc-document-sha-guard`, script at
 * `apps/web-platform/scripts/check-tc-document-sha.sh`) asserts equality
 * and fails the build on mismatch. Unlike T&C, there is NO `TC_VERSION`-
 * style bump bypass for these docs — every canonical edit MUST be paired
 * with a refresh of the corresponding SHA literal here. The 8 docs are
 * notice/disclosure documents and not contracts of adhesion; no
 * middleware reads a version constant for them.
 *
 * Bump-policy rubric (Tier 1 / Tier 2 / Tier 3 classification still
 * applies for Article 30 register + counsel-review-ledger purposes):
 * `knowledge-base/legal/tc-version-bump-policy.md` (§ Non-T&C legal docs).
 */
export const LEGAL_DOC_SHAS: Readonly<Record<string, string>> = {
  "acceptable-use-policy":
    "76412258e127e7e5aca8c788ac6905f7bc00fddab9a9eba0b6a8f9985da3e03c",
  "cookie-policy":
    "3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "4730b7e35d65ce612cd7ff9ecb0e0e8c97e86417ff5489a9a24c14e3f6805adc",
  "disclaimer":
    "9a31290a5d691c5ddaecaf073b5db00a6d5b77f560c8c6589e84ce887e3c5384",
  "gdpr-policy":
    "5c96f805bec702149114809c888d74f63597d804b680e980cbedece261f2552a",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "0a919f70eaa23e874c2b7075a8a85cded55aca71bd31df746c349d3666be2535",
};
