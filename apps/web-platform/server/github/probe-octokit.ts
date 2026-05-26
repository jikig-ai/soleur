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

import { App } from "@octokit/app";
import { createChildLogger } from "../logger";

const log = createChildLogger("probe-octokit");

const APP_ID_ENV = "GITHUB_APP_ID";
const PRIVATE_KEY_ENV = "GITHUB_APP_PRIVATE_KEY";

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
      privateKey: readEnv(PRIVATE_KEY_ENV),
    });
    const { data: installation } = await app.octokit.request(
      "GET /repos/{owner}/{repo}/installation",
      { owner: PROBE_ISSUE_OWNER, repo: PROBE_ISSUE_REPO },
    );
    return app.getInstallationOctokit(installation.id);
  }

  try {
    return await attempt();
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status !== 401) throw err;
    log.warn("401 on App JWT installation discovery — retrying once after 1s");
    await new Promise((r) => setTimeout(r, 1_000));
    return await attempt();
  }
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
    privateKey: readEnv(PRIVATE_KEY_ENV),
  });
  return { octokit: app.octokit };
}
