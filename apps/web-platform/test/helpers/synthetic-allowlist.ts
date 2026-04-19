/**
 * Synthetic-identifier guard for destructive integration tests. Any
 * `beforeAll`/`afterAll` that DELETEs or UPSERTs against a shared database
 * must gate on `assertSyntheticEmail(user.email)` so the test cannot
 * accidentally destroy a real account. See cq-destructive-prod-tests-allowlist.
 */

export const SYNTHETIC_EMAIL_RE =
  /^concurrency-test\+[0-9a-f-]+@soleur\.dev$/;

/**
 * Throws if the given email is not a concurrency-test synthetic address.
 * Strict regex — any typo, missing suffix, or real domain aborts the
 * destructive path before it touches data.
 */
export function assertSyntheticEmail(email: string): void {
  if (!SYNTHETIC_EMAIL_RE.test(email)) {
    throw new Error(
      `Refusing destructive op on non-synthetic email: "${email}". ` +
        `Emails must match ${SYNTHETIC_EMAIL_RE}.`,
    );
  }
}

/**
 * Generate a synthetic email for a test fixture. Uses crypto.randomUUID so
 * each run is isolated even if a prior run leaked rows.
 */
export function syntheticEmail(): string {
  const uuid =
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? (crypto as { randomUUID: () => string }).randomUUID()
      : Math.random().toString(36).slice(2);
  return `concurrency-test+${uuid}@soleur.dev`;
}
