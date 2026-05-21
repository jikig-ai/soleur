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
  const app = new App({
    appId: readEnv(APP_ID_ENV),
    privateKey: readEnv(PRIVATE_KEY_ENV),
  });

  // App-level JWT can hit /repos/{owner}/{repo}/installation to discover
  // which installation backs a repo. Returned object has `.id` — the
  // installation id we need for installation-scoped Octokit minting.
  const { data: installation } = await app.octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: PROBE_ISSUE_OWNER, repo: PROBE_ISSUE_REPO },
  );

  return app.getInstallationOctokit(installation.id);
}
