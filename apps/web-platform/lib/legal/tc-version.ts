/**
 * Current version of the Terms & Conditions.
 *
 * Bump this when T&C content changes substantively (new processing purposes,
 * altered user rights). Do NOT bump for typo fixes or formatting changes —
 * forced re-acceptance on trivial edits creates consent fatigue.
 *
 * The middleware compares this against each user's tc_accepted_version and
 * redirects to /accept-terms on mismatch.
 */
export const TC_VERSION = "1.0.0";
