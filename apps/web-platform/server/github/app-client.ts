// PR-H (#3244) Phase 3 — GitHub App per-request Octokit factory.
//
// THREAT MODEL: cross-tenant token leak across Next.js App Router
// worker boundaries. Module-scope singletons of `App` or a cached
// installation token leak across the boundary (vercel/next.js#65350)
// and across simultaneous request/founder pairs in the same worker.
// The plan's load-bearing primitive is "no module-scope state":
//   - `createGitHubAppClient(installationId)` instantiates a fresh
//     `App` on every call from per-request env reads.
//   - It then returns `app.getInstallationOctokit(installationId)`
//     which auto-refreshes the installation token at
//     `expires_at - 60s` internally (@octokit/auth-app v8+). Layering
//     a manual cache on top double-caches and risks mid-request
//     expiry.
//
// Why a factory (not a class with private state): functions cannot
// accidentally retain memoized state across calls. Adding a memoize
// helper to the module would re-introduce the very hazard the plan
// names; the test asserts this absence (`fresh-import-per-test`).

import { App } from "@octokit/app";

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
 * Returns an Octokit client scoped to a single GitHub App installation.
 *
 * INVARIANTS:
 *   - Per-request only. NO module-scope cache, NO singleton.
 *   - Reads `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from process.env
 *     on every call (Next.js worker boots may surface different envs
 *     across deploys).
 *   - Auto-refreshing installation token is the responsibility of
 *     `@octokit/auth-app` internally; do NOT layer a manual cache.
 */
export async function createGitHubAppClient(installationId: number) {
  const app = new App({
    appId: readEnv(APP_ID_ENV),
    privateKey: readEnv(PRIVATE_KEY_ENV),
  });
  return app.getInstallationOctokit(installationId);
}
