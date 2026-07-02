/**
 * Current version of the Terms & Conditions.
 *
 * Bump this when T&C content changes substantively (new processing purposes,
 * altered user rights). Do NOT bump for typo fixes or formatting changes —
 * forced re-acceptance on trivial edits creates consent fatigue.
 *
 * The middleware compares this against each user's tc_accepted_version and
 * redirects to /accept-terms on mismatch.
 *
 * Bump-policy rubric (material / clarifying / cosmetic) lives at
 * knowledge-base/legal/tc-version-bump-policy.md (CLO-signed).
 */
export const TC_VERSION = "2.4.0";

/**
 * SHA-256 of `docs/legal/terms-and-conditions.md` at the time of the
 * current `TC_VERSION`. Hand-edited literal.
 *
 * Persisted per acceptance in `public.tc_acceptances.document_sha` so the
 * audit ledger captures exactly which document the user accepted.
 *
 * CI guardrail (`.github/workflows/ci.yml :: tc-document-sha-guard`) asserts
 * this literal matches the canonical doc's content; a mismatch fails the
 * build unless the same PR bumped `TC_VERSION`. Drift policy:
 *   1. Edit T&C in `docs/legal/terms-and-conditions.md`.
 *   2. `sha256sum docs/legal/terms-and-conditions.md` and paste the value below.
 *   3. Bump `TC_VERSION` per the bump-policy rubric if the change is
 *      material or clarifying (cosmetic edits do NOT require a bump but
 *      still require the SHA refresh).
 *   4. Commit all three in one PR — CI will accept the SHA change because
 *      `TC_VERSION` was also bumped.
 */
export const TC_DOCUMENT_SHA =
  "f3640a38ea9805667456336ea2be8cf9606ee61a097664ad2770e3888893a5cf";

/**
 * Bump-metadata for the current `TC_VERSION`. Consumed by the Art. 13(3)
 * re-acceptance banner on `/accept-terms` and the copy-regression test.
 *
 * When bumping `TC_VERSION`, update all four fields here in lockstep with
 * the canonical doc:
 *   - `lastUpdated`: human-readable date matching the canonical
 *     `**Last Updated:**` line.
 *   - `substantiveChange`: short label for the new top-level section
 *     introduced by the bump (e.g., `§Workspace Members`).
 *   - `fullTermsUrl`: canonical public URL for the full T&C.
 */
export const TC_BUMP_METADATA = {
  lastUpdated: "July 2, 2026",
  substantiveChange: "BYOK best-effort cost ceiling and operator overage allocation",
  fullTermsUrl: "https://soleur.ai/pages/legal/terms-and-conditions.html",
} as const;
