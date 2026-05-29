// TR9 PR-3 (#4211, AC4) — synthetic-probe Octokit factory.
//
// WARNING — do NOT import this in founder-activity flows. Use the sibling
// `createGitHubAppClient(installationId, founderId)` instead.
//
// This helper mints an installation-scoped Octokit for the OPERATOR-owned
// `jikig-ai/soleur` repo. It exists to let the OAuth-probe Inngest function
// (`cron-oauth-probe.ts`) file / comment on / close the `[ci/auth-broken]`
// tracking issue without dragging in `app-client.ts`'s audit-writer hooks.
//
// Distinctions from `createGitHubAppClient`:
//   - NO `founderId` parameter. The probe is platform-owned synthetic
//     traffic; there is no founder to attribute the API calls to.
//   - NO audit-writer attachment. Writing `audit_github_token_use` rows
//     for synthetic-probe traffic would pollute the Article 30 PA-16
//     ledger (operator-action audit log scoped to founder activity).
//   - NO `installationId` parameter. The installation is discovered at
//     call time by querying `GET /repos/{owner}/{repo}/installation` with
//     the app-level JWT — survives App reinstall without an env-var bump.
//
// The factory is per-call (no module-scope cache) for the same threat-model
// reasons documented in `app-client.ts`.

import { createPrivateKey } from "crypto";
import { App } from "@octokit/app";
import { createChildLogger } from "../logger";
import { warnSilentFallback } from "@/server/observability";

const log = createChildLogger("probe-octokit");

const APP_ID_ENV = "GITHUB_APP_ID";
const PRIVATE_KEY_ENV = "GITHUB_APP_PRIVATE_KEY";

// Mirrors the canonical backoff idiom in server/github-api.ts (MAX_RETRIES=2,
// BASE_DELAY_MS=1_000 → 1s, 2s) and the parity fix in
// server/github-app.ts:467-468,506-520 (PR 4565, #122537945). 401-only: a 401
// on App-JWT installation discovery is the transient JWT-replication class; any
// non-401 breaks immediately, preserving 404/403/5xx semantics. The sibling
// hand-rolled path was hardened to this budget; this brings the @octokit/app
// path to parity (PR #4498's single 1s retry was insufficient).
const PROBE_JWT_MAX_RETRIES = 2; // 3 total attempts
const PROBE_JWT_BASE_DELAY_MS = 1_000; // 1s, 2s

// GitHub-origin diagnostics extracted from a thrown @octokit/request-error
// `RequestError` WITHOUT materializing the App JWT or PEM. Reads only
// `err.status` + `err.response.{headers,data}` (GitHub's public error JSON +
// lower-cased response headers — verified in @octokit/types ResponseHeaders).
// `clockSkewMs` is positive when the local clock is AHEAD of GitHub — the exact
// direction that produces JWT `iat`-in-future rejections behind the opaque
// "A JSON web token could not be decoded" error. AC5: no secret enters here.
interface GitHubErrorDiag {
  ghStatus?: number;
  ghRequestId?: string;
  ghBody?: string;
  clockSkewMs: number | null;
}

function extractGitHubErrorDiag(err: unknown): GitHubErrorDiag {
  if (!err || typeof err !== "object") return { clockSkewMs: null };
  const status = (err as { status?: number }).status;
  const resp = (err as {
    response?: {
      headers?: { date?: string; "x-github-request-id"?: string };
      data?: unknown;
    };
  }).response;
  const headers = resp?.headers ?? {};
  const ghDate = headers.date;
  const parsed = ghDate ? Date.parse(ghDate) : NaN;
  const clockSkewMs = Number.isNaN(parsed) ? null : Date.now() - parsed;
  const rawBody = resp?.data;
  const ghBody =
    rawBody === undefined || rawBody === null
      ? undefined
      : (typeof rawBody === "string" ? rawBody : JSON.stringify(rawBody))
          // Codebase-canonical log-injection strip (control chars + DEL +
          // Unicode line/paragraph separators), NOT bare /[\r\n]/ — GitHub
          // error bodies can echo client-influenced content (422/OAuth
          // error_description) that pino/Sentry viewers render as line breaks.
          // \uXXXX escapes required (cq-regex-unicode-separators-escape-only).
          .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ")
          .slice(0, 500);
  return {
    ghStatus: status,
    ghRequestId: headers["x-github-request-id"],
    ghBody,
    clockSkewMs,
  };
}

// Operator repo the probe files issues against. The probe is repo-scoped
// by design — its tracking issues live where the operator looks. If the
// repo is ever forked or renamed, update both constants in one edit.
export const PROBE_ISSUE_OWNER = "jikig-ai";
export const PROBE_ISSUE_REPO = "soleur";

function readEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(
      `${name} is unset — GitHub App secrets must be present in Doppler 'prd' (TR9 PR-3).`,
    );
  }
  return v;
}

// Canonicalize the GitHub App private key to a clean LF-only PKCS#8 PEM BEFORE
// handing it to @octokit/app. universal-github-app-jwt@2.2.2's getDERfromPEM()
// does `pem.trim().split("\n").slice(1,-1).join("")` and imports via Web-Crypto
// importKey("pkcs8", …) — it rejects PKCS#1 and produces corrupted DER from
// CRLF-laden PEMs, surfacing as GitHub's "A JSON web token could not be decoded"
// (Sentry 4e6a3003…). Node's createPrivateKey().export() is whitespace/format-
// tolerant (the same primitive server/github-app.ts trusts via createSign) and
// emits exactly the one-header / body / one-footer LF PEM that slice(1,-1)
// expects, regardless of input format (PKCS#1 or #8) or line endings (CRLF/LF).
export function normalizeAppPrivateKey(raw: string): string {
  const pem = raw.replace(/\\n/g, "\n"); // expand escaped \n (env/Doppler)
  return createPrivateKey(pem)
    .export({ type: "pkcs8", format: "pem" })
    .toString();
}

/**
 * Returns an installation-scoped Octokit for the operator's
 * `jikig-ai/soleur` repo. Mints a fresh App JWT on every call, discovers
 * the installation via the App API, and returns an Octokit whose
 * underlying token is auto-refreshed by `@octokit/auth-app` internally.
 *
 * Intentionally omits the audit-writer hooks attached by
 * `createGitHubAppClient`. See file header for rationale.
 */
export async function createProbeOctokit() {
  async function attempt() {
    const app = new App({
      appId: readEnv(APP_ID_ENV),
      privateKey: normalizeAppPrivateKey(readEnv(PRIVATE_KEY_ENV)),
    });
    const { data: installation } = await app.octokit.request(
      "GET /repos/{owner}/{repo}/installation",
      { owner: PROBE_ISSUE_OWNER, repo: PROBE_ISSUE_REPO },
    );
    return app.getInstallationOctokit(installation.id);
  }

  // Diagnostic-capture-then-rethrow. `warnSilentFallback` (warning level, not
  // error) is deliberate: the cron handler's `step.run("issue-handling")` catch
  // (cron-oauth-probe.ts) already owns the terminal error-level
  // `reportSilentFallback`, so this avoids double-counting the same failure as
  // two error events while still surfacing the GitHub status/request-id/body/
  // clock-skew that makes the next recurrence self-diagnosing.
  // (cq-silent-fallback-must-mirror-to-sentry: warnSilentFallback reaches Sentry.)
  function captureAndRethrow(err: unknown, attempts: number): never {
    warnSilentFallback(err, {
      feature: "cron-oauth-probe",
      op: "create-probe-octokit:app-jwt",
      message: "App-JWT installation discovery failed",
      extra: { ...extractGitHubErrorDiag(err), attempts },
    });
    throw err;
  }

  for (let i = 0; i <= PROBE_JWT_MAX_RETRIES; i++) {
    try {
      return await attempt();
    } catch (err) {
      const status = (err as { status?: number }).status;
      // Non-401: not the transient JWT-replication class — capture + rethrow now.
      if (status !== 401) captureAndRethrow(err, i + 1);
      // Exhausted the 401 retry budget — capture + rethrow.
      if (i >= PROBE_JWT_MAX_RETRIES) captureAndRethrow(err, i + 1);
      // Otherwise back off (1s, 2s) and re-attempt with a fresh App/JWT.
      log.warn(
        { attempt: i + 1, status },
        "401 on App JWT installation discovery — retrying with backoff",
      );
      await new Promise((r) =>
        setTimeout(r, PROBE_JWT_BASE_DELAY_MS * 2 ** i),
      );
    }
  }
  // Unreachable: the loop either returns or captureAndRethrow throws.
  throw new Error("createProbeOctokit: retry loop fell through");
}

/**
 * TR9 PR-4 (#4235, AC4) — App-level JWT Octokit for `/app` + `/app/installations`.
 *
 * Mints an app-level JWT Octokit for surfaces requiring app-level
 * authentication (the drift-guard's `GET /app` and `GET /app/installations`
 * calls). Returns `{ octokit }`: an `app.octokit` (app-level, NOT installation-
 * scoped) so callers can hit `/app` directly.
 *
 * CRITICAL: Deliberately omits the audit-writer hook (`audit_github_token_use`).
 * The drift-guard is platform-owned synthetic traffic; writing audit rows
 * would pollute the Article 30 PA-16 founder-activity ledger. Mirror of
 * `createProbeOctokit()`'s same rationale.
 *
 * NOTE: Previously returned `{ octokit, appJwt }` so the JWT string could be
 * passed through the leak tripwire. The handler never actually consumed
 * `appJwt`, so the shape was simplified to just `{ octokit }` to remove a
 * dead-store + reduce the leak surface (the JWT is never materialized into a
 * caller-visible string).
 *
 * @throws if GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY is missing.
 */
export async function createAppJwtOctokit(): Promise<{
  octokit: InstanceType<typeof App>["octokit"];
}> {
  const app = new App({
    appId: readEnv(APP_ID_ENV),
    privateKey: normalizeAppPrivateKey(readEnv(PRIVATE_KEY_ENV)),
  });
  return { octokit: app.octokit };
}
