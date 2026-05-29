// byok-side-letter.ts
// BYOK Delegations consent-enforcement (#4625; parent #4232).
//
// Single TS source of truth for the canonical Delegation Consent Side
// Letter version. The accept route (app/api/workspace/delegations/accept)
// stamps THIS constant server-side — it never trusts a client-supplied
// version (the old client-supplied path let a grantee record a stale
// version and fail OPEN at the SQL lease gate).
//
// PARITY INVARIANT (AC4, CI-gated): this value MUST equal the literal
// returned by the SQL function public.current_byok_side_letter_version()
// (migration 083). The SECURITY DEFINER lease gate resolve_byok_key_owner
// compares the stored side_letter_version against the SQL function, so a
// one-sided bump (TS without SQL, or SQL without TS) would silently
// diverge dev from prd. test/byok-side-letter-version-parity.test.ts is
// wired as a CI gate (fails the build, not just the suite).
//
// Bumping the version is a DELIBERATE legal act: it fail-closes every
// stale-version acceptance at the gate (re-consent required). Bump BOTH
// this constant and the SQL function literal in the same migration, and
// update knowledge-base/legal/delegation-consent-side-letter-template.md.

export const BYOK_SIDE_LETTER_VERSION = "1.0.0" as const;
