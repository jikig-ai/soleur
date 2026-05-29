// PR-H (#3244) Phase 3 — GitHub App per-request Octokit factory.
// PR-H+1 (#4098) — attaches per-call audit writer to every installation
//   client. The audit hook fires after every Octokit response (success
//   or error) so audit_github_token_use populates as Soleur uses the
//   installation token. Per Art. 30 PA-16 disclosure (Art. 5(2)).
//
// THREAT MODEL: cross-tenant token leak across Next.js App Router
// worker boundaries. Module-scope singletons of `App` or a cached
// installation token leak across the boundary (vercel/next.js#65350)
// and across simultaneous request/founder pairs in the same worker.
// The plan's load-bearing primitive is "no module-scope state":
//   - `createGitHubAppClient(installationId, founderId)` instantiates a
//     fresh `App` on every call from per-request env reads.
//   - It then returns `app.getInstallationOctokit(installationId)`
//     which auto-refreshes the installation token at
//     `expires_at - 60s` internally (@octokit/auth-app v8+). Layering
//     a manual cache on top double-caches and risks mid-request
//     expiry.
//   - PR-H+1 audit hook: each returned Octokit is wrapped with
//     `octokit.hook.after("request", ...)` and `octokit.hook.error("request", ...)`
//     to write one audit_github_token_use row per response (or error)
//     via recordGithubApiCall. founderId enters via closure, so audit
//     rows attribute correctly even when the same installation backs
//     multiple founders (multi-org GitHub App install class).
//
// Why a factory (not a class with private state): functions cannot
// accidentally retain memoized state across calls. Adding a memoize
// helper to the module would re-introduce the very hazard the plan
// names; the test asserts this absence (`fresh-import-per-test`).

import { App } from "@octokit/app";

import {
  recordGithubApiCall,
  extractEndpoint,
  extractRepoFullName,
} from "./audit-writer";
import { normalizeAppPrivateKey } from "./app-private-key";

const APP_ID_ENV = "GITHUB_APP_ID";
const PRIVATE_KEY_ENV = "GITHUB_APP_PRIVATE_KEY";

function readEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(
      `${name} is unset — GitHub App secrets must be present in Doppler 'prd' (PR-H Phase 2 IaC).`,
    );
  }
  return v;
}

/**
 * Returns an Octokit client scoped to a single GitHub App installation
 * AND a single founder (audit attribution).
 *
 * INVARIANTS:
 *   - Per-request only. NO module-scope cache, NO singleton.
 *   - Reads `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from process.env
 *     on every call (Next.js worker boots may surface different envs
 *     across deploys).
 *   - Auto-refreshing installation token is the responsibility of
 *     `@octokit/auth-app` internally; do NOT layer a manual cache.
 *   - PR-H+1: every response (success or error) writes one audit row
 *     via recordGithubApiCall. The hook is non-blocking — a Supabase
 *     outage cannot wedge an Octokit request.
 *
 * CALLER CONTRACT:
 *   `founderId` MUST be derived from a validated session (cookie-scoped
 *   `supabase.auth.getUser()` or equivalent webhook predicate) — NEVER
 *   from a request body, query string, or other client-supplied source.
 *   The audit-writer trusts the value and writes it straight to the
 *   `audit_github_token_use.founder_id` column; a client-controlled
 *   value would let an attacker forge cross-tenant audit attribution.
 *
 * @param installationId — GitHub App installation id (per repo or per org)
 * @param founderId      — Soleur founder UUID derived from a session-validated
 *                          source. Audit rows attribute here.
 */
export async function createGitHubAppClient(
  installationId: number,
  founderId: string,
) {
  const app = new App({
    appId: readEnv(APP_ID_ENV),
    privateKey: normalizeAppPrivateKey(readEnv(PRIVATE_KEY_ENV)),
  });
  const octokit = await app.getInstallationOctokit(installationId);

  // Octokit hook signatures:
  //   hook.after("request", (response, options)) — runs after a successful
  //     response. response.status is the HTTP status; options.url is the
  //     normalized request URL.
  //   hook.error("request", (error, options)) — runs when a request errors;
  //     error.status carries the HTTP status when applicable (404, 422, etc.).
  //
  // Both writers MUST be non-blocking — Octokit propagates exceptions thrown
  // inside the hook to the caller. recordGithubApiCall internally catches
  // everything and mirrors to Sentry (AC8). The `void` form drops the
  // returned promise without forcing the hook to await — Octokit's hook
  // contract awaits returned promises before completing the request, which
  // would couple Octokit latency to Supabase round-trip. Fire-and-forget is
  // intentional.

  octokit.hook.after("request", async (response, options) => {
    const url = String(options.url ?? "");
    void recordGithubApiCall({
      founderId,
      installationId,
      endpoint: extractEndpoint(url),
      repoFullName: extractRepoFullName(url),
      responseStatus: response.status,
    });
  });

  octokit.hook.error("request", async (error, options) => {
    const url = String(options.url ?? "");
    // status normalized to null for non-HTTP failures (network reset,
    // abort, DNS, no .status field). The audit row's response_status
    // CHECK constraint allows NULL OR 100-599 — a synthetic 0 would
    // violate CHECK and cause silent row drop.
    const rawStatus =
      error && typeof error === "object" && "status" in error
        ? Number((error as { status?: unknown }).status)
        : Number.NaN;
    const status =
      Number.isFinite(rawStatus) && rawStatus >= 100 && rawStatus <= 599
        ? rawStatus
        : null;
    void recordGithubApiCall({
      founderId,
      installationId,
      endpoint: extractEndpoint(url),
      repoFullName: extractRepoFullName(url),
      responseStatus: status,
    });
    // Re-throw to preserve Octokit's error propagation contract — the
    // hook is observation-only, not interception. Async fn turns the
    // throw into a rejected promise (matches Octokit's hook contract).
    throw error;
  });

  return octokit;
}
