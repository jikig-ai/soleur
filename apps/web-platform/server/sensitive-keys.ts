// Single source of truth for credential-bearing key names that must be
// stripped from logs (pino) and Sentry events. Any new auth/secret field
// added to the codebase belongs here — splitting the list across modules
// has caused silent drift in past PRs.
//
// Coverage rationale:
//   - BYOK envelope (`apps/web-platform/server/byok.ts:encryptKey`):
//     `encrypted`, `iv`, `tag` are the real return-shape field names.
//     `encryptedKey`/`auth_tag` are also listed because earlier plan
//     drafts and call sites use those spellings; defensive depth.
//   - HTTP/auth headers: `cookie`, `x-nonce` (CSP), `Authorization` /
//     `authorization` (case variants), `x-api-key` (vendor variant).
//   - API/secret/token names from `apps/web-platform/server/providers.ts`
//     (`*_API_KEY`, `*_API_TOKEN`, `*_BEARER_TOKEN`, `*_APP_PASSWORD`)
//     and OAuth surfaces: `apiKey`, `api_key`, `password`, `token`,
//     `access_token`, `refresh_token`, `bearer`, `client_secret`,
//     `private_key`, `secret`.
//
// Key matching is case-insensitive (callers lowercase before comparing).
// Pino's `fast-redact` does NOT support recursive wildcards — `REDACT_PATHS`
// derives top-level + 1-deep wildcard paths from `SENSITIVE_KEY_NAMES`,
// plus the existing `req.headers.*` literal paths. Deeper-nested credential
// objects must be filtered at the call site or routed through the BYOK
// lease (PR-B §1.4) which is the canonical handling path.

export const SENSITIVE_KEY_NAMES = [
  // BYOK envelope (real shape)
  "encrypted",
  "iv",
  "tag",
  // BYOK envelope (alt spellings — defensive)
  "encryptedKey",
  "auth_tag",
  // API keys
  "apiKey",
  "api_key",
  "x-api-key",
  // Auth headers
  "Authorization",
  "authorization",
  "bearer",
  // Tokens
  "token",
  "access_token",
  "refresh_token",
  // Passwords / secrets
  "password",
  "client_secret",
  "private_key",
  "secret",
  // Note (#3363 Resolution C): The PR-B-era allowlist entries
  // `jwt_secret` + `supabase_jwt_secret` were removed when the HS256
  // substrate was retired — Node no longer holds a signing key. The
  // exact-name `secret` match above still covers any residual leak
  // shape (e.g., `service_role_secret`). Supabase's asymmetric private
  // keys never leave Supabase, so no replacement allowlist entry is
  // needed for the signing material itself.
  // Dev-only sign-in passwords (R3 / feat-dev-signin-bypass). Exact-name
  // match on `password` does NOT cover the per-slot env-var key names
  // that may appear in error reports or config-snapshot dumps. These
  // keys must never reach Sentry even though they are dev-only — a
  // leak of the dev passwords is a vector to authenticate as the
  // seeded test users in the dev Supabase project.
  "DEV_USER_1_PASSWORD",
  "DEV_USER_2_PASSWORD",
  "DEV_USER_3_PASSWORD",
  // Sentry userId pseudonymization pepper (#3638). Held in Doppler, read
  // once at module init in `server/observability.ts`. Listed here so a
  // future env-block dump or config-snapshot log cannot leak the pepper —
  // the value is what the helper's confidentiality leans on (Recital 26).
  "SENTRY_USERID_PEPPER",
  "pepper",
  // HTTP transport
  "cookie",
  "x-nonce",
] as const;

/**
 * Lowercased Set used by the Sentry recursive scrubber. Lookups are
 * case-insensitive — `SENSITIVE_LOWER.has(key.toLowerCase())`.
 */
export const SENSITIVE_LOWER: ReadonlySet<string> = new Set(
  SENSITIVE_KEY_NAMES.map((k) => k.toLowerCase()),
);

/**
 * Pino redact paths covering top-level + 1-deep wildcard for every
 * sensitive key name, plus the canonical `req.headers.*` literals
 * the Next.js logger sees on inbound requests.
 */
export const REDACT_PATHS: readonly string[] = [
  "req.headers['x-nonce']",
  "req.headers.cookie",
  "req.headers.authorization",
  "req.headers['x-api-key']",
  ...SENSITIVE_KEY_NAMES.flatMap((k) => [k, `*.${k}`]),
];
