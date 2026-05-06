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
