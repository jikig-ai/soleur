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
    "15ceaabbded53d68f2061ffd531ebfa1aada797e084571e02507404364b53f6a",
  "cookie-policy":
    "3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8",
  "corporate-cla":
    "d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826",
  "data-protection-disclosure":
    "58efac21e7d59c778527bd1f515eef03a82f46e0419ab3d9c8a997b0644e6651",
  "disclaimer":
    "9a31290a5d691c5ddaecaf073b5db00a6d5b77f560c8c6589e84ce887e3c5384",
  "gdpr-policy":
    "33c430f7b2fa7a9bfc56824af3fbc06273ce980c029906db27dde2774ce9624f",
  "individual-cla":
    "8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538",
  "privacy-policy":
    "f901bf93aadf6f53a721e9bcdac1fb16410a3ab80d5a2249cc0eb4fd613112e7",
};
