// Named-secret reader for /api/internal/* routes that do NOT use the Inngest secret (#12011 PR-D).
// Server-side only (reads process.env).
//
// Why this is a separate module: lib/internal-auth.ts is one of the CENSUS_PATHS bound by the CLO ruling on #10455
// (apps/web-platform/scripts/home-census-trigger.sh): `git diff --quiet <discharged sha> <served sha> -- CENSUS_PATHS`
// refuses the census run on any change to a bound path, and the discharged sha is 8c77db1. Keeping internal-auth.ts
// byte-identical to that sha means a new caller cannot cost the operator a re-discharge. The comparison itself
// (`bearerMatches`) is still the shared one from "@/lib/internal-auth"; only the secret lookup lives here.
//
// What the header of internal-auth.ts therefore no longer says: it names three callers (trigger-cron, schedule-reminder,
// cohort). There is a fourth, GET /api/internal/legal-acceptance/[key], which reads LEGAL_ACCEPTANCE_VERIFY_TOKEN through
// this module and compares with bearerMatches. That token is separate on purpose: a holder of the Inngest secret cannot
// use the status endpoint, and a holder of the status token cannot trigger anything.
//
// The name is a CLOSED union (never a free string): adding a secret is a reviewed edit to this type.
//
// SOLEUR-DEBT: a second module only to keep internal-auth.ts byte-identical to the discharged census sha; fold the named-secret parameter into internal-auth.ts and delete this module when the home-census route is retired (#11714; census SUNSET_UTC 2026-11-30)

export type NamedBearerSecretName = "LEGAL_ACCEPTANCE_VERIFY_TOKEN";

export function readNamedBearerSecret(name: NamedBearerSecretName): string | null {
  const v = process.env[name];
  return v && v.length > 0 ? v : null;
}
