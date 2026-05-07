// ---------------------------------------------------------------------------
// GitHub App authentication and operations
//
// Handles JWT creation (RS256), installation token exchange, and
// repository listing/creation via the GitHub App API.
//
// Environment variables (server-only, NOT in agent allowlist):
//   GITHUB_APP_ID         — numeric App ID
//   GITHUB_APP_PRIVATE_KEY — PEM-encoded RSA private key (may have \n escaped)
// ---------------------------------------------------------------------------

import { createSign, randomUUID } from "crypto";
import { createChildLogger } from "./logger";

const log = createChildLogger("github-app");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Repo {
  name: string;
  fullName: string;
  private: boolean;
  description: string | null;
  language: string | null;
  updatedAt: string;
}

export interface PullRequestResult {
  number: number;
  htmlUrl: string;
  url: string;
}

interface InstallationAccount {
  login: string;
  id: number;
  type: string; // "User" or "Organization"
}

interface VerifyResult {
  verified: boolean;
  error?: string;
  status?: number; // HTTP status to return to client
}

class InstallationError extends Error {
  constructor(
    message: string,
    public readonly code: "NOT_FOUND" | "NO_ACCOUNT" | "FETCH_FAILED",
  ) {
    super(message);
  }
}

/**
 * Thrown when the GitHub API returns an error response.
 * Carries the HTTP status code so callers can distinguish user-correctable
 * 4xx errors from internal 5xx failures.
 */
export class GitHubApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
  ) {
    super(message);
    this.name = "GitHubApiError";
  }
}

interface GitHubInstallationTokenResponse {
  token: string;
  expires_at: string;
}

interface GitHubRepoResponse {
  name: string;
  full_name: string;
  private: boolean;
  description: string | null;
  language: string | null;
  updated_at: string;
  html_url: string;
}

// ---------------------------------------------------------------------------
// JWT signing (RS256)
// ---------------------------------------------------------------------------

function getAppId(): string {
  const appId = process.env.GITHUB_APP_ID;
  if (!appId) throw new Error("GITHUB_APP_ID is not set");
  return appId;
}

function getPrivateKey(): string {
  const raw = process.env.GITHUB_APP_PRIVATE_KEY;
  if (!raw) throw new Error("GITHUB_APP_PRIVATE_KEY is not set");
  // Handle escaped newlines from env vars (common in Docker/Doppler)
  return raw.replace(/\\n/g, "\n");
}

function base64url(input: Buffer): string {
  return input.toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function createAppJwt(): string {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: getAppId(),
    iat: now - 60,
    exp: now + 10 * 60,
  };

  const headerB64 = base64url(Buffer.from(JSON.stringify(header)));
  const payloadB64 = base64url(Buffer.from(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const signer = createSign("RSA-SHA256");
  signer.update(signingInput);
  signer.end();
  const signature = base64url(signer.sign(getPrivateKey()));

  return `${signingInput}.${signature}`;
}

// ---------------------------------------------------------------------------
// App slug resolution (defense-in-depth)
// ---------------------------------------------------------------------------

let cachedSlug: string | null = null;

/**
 * Fetch the GitHub App slug from the API (GET /app), caching the result.
 * Falls back to NEXT_PUBLIC_GITHUB_APP_SLUG if credentials are not set.
 */
export async function getAppSlug(): Promise<string> {
  if (cachedSlug) return cachedSlug;

  const appId = process.env.GITHUB_APP_ID;
  const privateKey = process.env.GITHUB_APP_PRIVATE_KEY;
  if (!appId || !privateKey) {
    const fallback = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai";
    log.warn("GITHUB_APP_ID not set — using env var fallback for app slug");
    cachedSlug = fallback;
    return fallback;
  }

  const jwt = createAppJwt();
  const response = await fetch(`https://api.github.com/app`, {
    headers: {
      Authorization: `Bearer ${jwt}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });

  if (!response.ok) {
    const fallback = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai";
    log.error({ status: response.status }, "Failed to fetch app slug from GitHub API — using fallback");
    cachedSlug = fallback;
    return fallback;
  }

  const data = (await response.json()) as { slug: string };
  // Validate slug format to prevent open redirect via path traversal
  if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(data.slug)) {
    const fallback = process.env.NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai";
    log.error({ slug: data.slug }, "Invalid slug format from GitHub API — using fallback");
    cachedSlug = fallback;
    return fallback;
  }
  cachedSlug = data.slug;
  return data.slug;
}

/** @internal Test-only: reset the cached slug so fallback paths can be tested. */
export function _resetSlugCacheForTesting(): void {
  cachedSlug = null;
}

// ---------------------------------------------------------------------------
// GitHub API helpers
// ---------------------------------------------------------------------------

const GITHUB_API = "https://api.github.com";
const GITHUB_FETCH_TIMEOUT_MS = 15_000;
// Template-generate clones a repo server-side; tail latency exceeds /repos
// create. Bumped to 30s to avoid clipping legitimate generates that succeed
// server-side but time out client-side (and would 422 on user retry).
const GITHUB_GENERATE_TIMEOUT_MS = 30_000;

// GitHub username/org slug rules: 1-39 chars, alphanumerics and hyphens, no
// leading/trailing hyphens. Defense-in-depth — values from getInstallationAccount
// are GitHub-controlled but we don't trust upstream regressions.
const GITHUB_LOGIN_RE = /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,38})$/;

async function githubFetch(
  url: string,
  options: RequestInit & { timeoutMs?: number } = {},
): Promise<Response> {
  const { timeoutMs, ...rest } = options;
  const response = await fetch(url, {
    ...rest,
    signal: AbortSignal.timeout(timeoutMs ?? GITHUB_FETCH_TIMEOUT_MS),
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...options.headers,
    },
  });
  return response;
}

// ---------------------------------------------------------------------------
// Installation account lookup
// ---------------------------------------------------------------------------

/**
 * Fetch the account (user or org) that owns a GitHub App installation.
 * Used by verifyInstallationOwnership and createRepo to determine
 * whether the installation is on a user account or an organization.
 */
export async function getInstallationAccount(
  installationId: number,
): Promise<InstallationAccount> {
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    if (response.status === 404) {
      throw new InstallationError("Installation not found", "NOT_FOUND");
    }
    throw new InstallationError(
      `Failed to fetch installation: ${response.status}`,
      "FETCH_FAILED",
    );
  }

  const data = (await response.json()) as {
    account?: InstallationAccount;
  };
  if (!data.account?.login) {
    throw new InstallationError("Installation has no account", "NO_ACCOUNT");
  }
  if (!GITHUB_LOGIN_RE.test(data.account.login)) {
    throw new InstallationError(
      `Installation account login does not match GitHub login format: ${data.account.login.slice(0, 50)}`,
      "NO_ACCOUNT",
    );
  }
  return data.account;
}

// ---------------------------------------------------------------------------
// Installation ownership verification
// ---------------------------------------------------------------------------

/**
 * Verify that a GitHub App installation belongs to the expected user.
 * Calls GET /app/installations/{id} with the App JWT and compares
 * account.login against the expected GitHub username.
 */
export async function verifyInstallationOwnership(
  installationId: number,
  expectedLogin: string,
): Promise<VerifyResult> {
  let account: InstallationAccount;
  try {
    account = await getInstallationAccount(installationId);
  } catch (err) {
    if (err instanceof InstallationError) {
      if (err.code === "NOT_FOUND") {
        return { verified: false, error: "Installation not found", status: 404 };
      }
      if (err.code === "NO_ACCOUNT") {
        return { verified: false, error: "Installation has no account", status: 502 };
      }
    }
    log.error(
      { installationId, err },
      "GitHub API error during installation verification",
    );
    return { verified: false, error: "Failed to verify installation", status: 502 };
  }

  // Organization installations: verify the user is a member of the org.
  if (account.type === "Organization") {
    const token = await generateInstallationToken(installationId);
    const memberResponse = await githubFetch(
      `${GITHUB_API}/orgs/${account.login}/members/${expectedLogin}`,
      { headers: { Authorization: `token ${token}` }, redirect: "manual" },
    );
    if (memberResponse.status === 204) {
      return { verified: true };
    }
    if (memberResponse.status === 404 || memberResponse.status === 302) {
      return {
        verified: false,
        error: "User is not a member of the organization",
        status: 403,
      };
    }
    log.error(
      { status: memberResponse.status, installationId, org: account.login, expectedLogin },
      "Failed to verify organization membership",
    );
    return { verified: false, error: "Failed to verify organization membership", status: 502 };
  }

  // SECURITY: Case-insensitive comparison — GitHub usernames are case-insensitive
  const matches = account.login.toLowerCase() === expectedLogin.toLowerCase();
  return {
    verified: matches,
    error: matches ? undefined : "Installation does not belong to this user",
    status: matches ? undefined : 403,
  };
}

// ---------------------------------------------------------------------------
// Installation discovery (auto-detect existing installs)
// ---------------------------------------------------------------------------

/**
 * Find a GitHub App installation for a given user login.
 *
 * First checks GET /users/{login}/installation for a personal installation.
 * If not found, iterates all app installations to find org installations
 * where the user is a member. Returns the installation ID if found, null
 * otherwise.
 */
export async function findInstallationForLogin(
  githubLogin: string,
): Promise<number | null> {
  const jwt = createAppJwt();

  // 1. Check personal account installation
  const response = await githubFetch(
    `${GITHUB_API}/users/${encodeURIComponent(githubLogin)}/installation`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (response.ok) {
    const data = (await response.json()) as { id?: number };
    if (typeof data.id === "number") return data.id;
  } else if (response.status !== 404) {
    log.warn(
      { status: response.status, githubLogin },
      "Unexpected status from /users/{login}/installation",
    );
  }

  // 2. Check org installations — iterate all app installations and look for
  //    orgs where the user is a member
  return findOrgInstallationForUser(jwt, githubLogin);
}

/**
 * Iterate all app installations looking for org installations where the
 * given user is a member. Returns the first matching installation ID.
 */
async function findOrgInstallationForUser(
  jwt: string,
  githubLogin: string,
): Promise<number | null> {
  const response = await githubFetch(
    `${GITHUB_API}/app/installations?per_page=100`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    log.warn(
      { status: response.status },
      "Failed to list app installations for org detection",
    );
    return null;
  }

  interface AppInstallation {
    id: number;
    account: { login: string; type: string };
  }

  const installations = (await response.json()) as AppInstallation[];
  const orgInstallations = installations.filter(
    (i) => i.account?.type === "Organization",
  );

  for (const inst of orgInstallations) {
    // Use installation token (not App JWT) for org membership check —
    // GET /orgs/{org}/members/{user} requires members:read permission
    let installationToken: string;
    try {
      installationToken = await generateInstallationToken(inst.id);
    } catch (err) {
      log.warn(
        { err, installationId: inst.id },
        "Failed to generate installation token for membership check",
      );
      continue;
    }

    const memberCheck = await githubFetch(
      `${GITHUB_API}/orgs/${encodeURIComponent(inst.account.login)}/members/${encodeURIComponent(githubLogin)}`,
      { headers: { Authorization: `token ${installationToken}` } },
    );
    // 204 = is a member, 302 = requester is not org member, 404 = not a member
    if (memberCheck.status === 204) {
      log.info(
        { githubLogin, orgLogin: inst.account.login, installationId: inst.id },
        "Found org installation for user",
      );
      return inst.id;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Token cache (installation tokens are valid for 1 hour)
// ---------------------------------------------------------------------------

const tokenCache = new Map<number, { token: string; expiresAt: number }>();

const TOKEN_SAFETY_MARGIN_MS = 5 * 60 * 1000; // Refresh 5 minutes early

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Exchange a GitHub App JWT for an installation access token.
 * Tokens are cached in memory and refreshed 5 minutes before expiry.
 */
export async function generateInstallationToken(
  installationId: number,
): Promise<string> {
  const cached = tokenCache.get(installationId);
  if (cached && cached.expiresAt > Date.now() + TOKEN_SAFETY_MARGIN_MS) {
    return cached.token;
  }

  const jwt = createAppJwt();

  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    },
  );

  if (!response.ok) {
    const body = await response.text();
    log.error(
      { status: response.status, body: body.slice(0, 500), installationId },
      "Failed to generate installation token",
    );
    throw new Error(
      `GitHub installation token request failed: ${response.status}`,
    );
  }

  const data = (await response.json()) as GitHubInstallationTokenResponse;

  tokenCache.set(installationId, {
    token: data.token,
    expiresAt: new Date(data.expires_at).getTime(),
  });

  return data.token;
}

/**
 * @deprecated No prod call sites after the GIT_ASKPASS migration — the
 * replacement is `gitWithInstallationAuth` in `./git-auth`. Kept as an
 * export only because several vitest files still construct helper paths
 * in their mocks of this module; those mocks are harmless no-ops under
 * the new code. Safe to remove once all test files are migrated.
 */
export function randomCredentialPath(): string {
  return `/tmp/git-cred-${randomUUID()}`;
}

// ---------------------------------------------------------------------------
// Repo-access preflight
// ---------------------------------------------------------------------------

/**
 * Classification returned by `checkRepoAccess`. Maps GitHub REST status
 * codes into a small closed set the calling workspace code can branch on.
 */
export type RepoAccessStatus =
  | "ok"
  | "not_found"
  | "access_revoked"
  | "degraded";

/**
 * Probe repository access before attempting a clone. Distinguishes
 * "repo is gone / app has no access" (user-correctable — reinstall CTA)
 * from "api.github.com hiccup" (likely still OK to clone).
 *
 * 200            → `ok`              — proceed to clone
 * 404            → `not_found`       — surface REPO_NOT_FOUND to user
 * 403            → `access_revoked`  — surface reinstall CTA
 * 5xx / network  → `degraded`        — proceed to clone; let git surface
 *                                     the real failure if any
 */
export async function checkRepoAccess(
  installationId: number,
  owner: string,
  repo: string,
): Promise<RepoAccessStatus> {
  let token: string;
  try {
    token = await generateInstallationToken(installationId);
  } catch (err) {
    // Token-gen failure is its own error class and is wrapped upstream;
    // report as degraded so the clone path still runs — the underlying
    // clone will fail loudly if auth is actually broken.
    log.warn(
      { installationId, err: (err as Error).message },
      "checkRepoAccess: token generation failed — treating as degraded",
    );
    return "degraded";
  }

  let response: Response;
  try {
    response = await githubFetch(`${GITHUB_API}/repos/${owner}/${repo}`, {
      headers: { Authorization: `token ${token}` },
    });
  } catch (err) {
    log.warn(
      { installationId, owner, repo, err: (err as Error).message },
      "checkRepoAccess: network error — treating as degraded",
    );
    return "degraded";
  }

  if (response.status === 200) return "ok";
  if (response.status === 404) return "not_found";
  if (response.status === 403) return "access_revoked";
  if (response.status >= 500) return "degraded";
  // 401 would mean the token itself is broken — treat as access-revoked so
  // the user sees a reinstall CTA rather than a generic clone-failure.
  if (response.status === 401) return "access_revoked";
  // Other 4xx: unknown classification; default to degraded to let git
  // attempt the clone and surface the real error.
  return "degraded";
}

/**
 * List repositories accessible to a GitHub App installation.
 */
export async function listInstallationRepos(
  installationId: number,
): Promise<Repo[]> {
  const token = await generateInstallationToken(installationId);

  const repos: Repo[] = [];
  let page = 1;
  const perPage = 100;

  // Paginate through all repos (most installations have < 100)
  while (true) {
    const response = await githubFetch(
      `${GITHUB_API}/installation/repositories?per_page=${perPage}&page=${page}`,
      {
        headers: {
          Authorization: `token ${token}`,
        },
      },
    );

    if (!response.ok) {
      const body = await response.text();
      log.error(
        { status: response.status, body: body.slice(0, 500), installationId },
        "Failed to list installation repos",
      );
      throw new Error(`GitHub list repos failed: ${response.status}`);
    }

    const data = (await response.json()) as {
      repositories: GitHubRepoResponse[];
      total_count: number;
    };

    for (const r of data.repositories) {
      repos.push({
        name: r.name,
        fullName: r.full_name,
        private: r.private,
        description: r.description,
        language: r.language,
        updatedAt: r.updated_at,
      });
    }

    if (repos.length >= data.total_count || data.repositories.length < perPage) {
      break;
    }
    page++;
  }

  return repos;
}

// Public template under the Soleur org used to seed user-account repos.
// User installations cannot call POST /user/repos with installation tokens
// (returns 403 "Resource not accessible by integration" — UAT-only endpoint),
// so we route through the template-generate endpoint, which DOES accept
// installation tokens. Live-verified against the production App on 2026-05-07.
//
// Template MUST be public + is_template — cross-account /generate calls
// from a user-installation token return 404 against private templates.
//
// Owner/name are env-overridable so staging/preview environments can pin a
// per-environment template without a code deploy.
export const KB_TEMPLATE_OWNER =
  process.env.KB_TEMPLATE_OWNER ?? "jikig-ai";
export const KB_TEMPLATE_NAME =
  process.env.KB_TEMPLATE_NAME ?? "kb-template";

async function parseGitHubError(
  response: Response,
  fallbackPrefix: string,
): Promise<{ message: string; body: string }> {
  const body = await response.text();
  let message = `${fallbackPrefix}: ${response.status}`;
  try {
    const parsed = JSON.parse(body);
    if (parsed.errors?.[0]?.message) {
      message = parsed.errors[0].message;
    } else if (parsed.message) {
      message = `${fallbackPrefix}: ${response.status} - ${parsed.message}`;
    }
  } catch {
    // Non-JSON response
  }
  return { message, body };
}

/**
 * Shared body for the two repo-create helpers. POSTs to {url} with the
 * installation token, parses errors via parseGitHubError, validates the
 * response shape (defends against 202-async or stripped payloads), and
 * returns the canonical {repoUrl, fullName} pair.
 */
async function postRepoCreate(
  installationId: number,
  url: string,
  payload: Record<string, unknown>,
  logCtx: { op: string; name: string; ownerLogin?: string },
  options: { timeoutMs?: number } = {},
): Promise<{ repoUrl: string; fullName: string }> {
  const token = await generateInstallationToken(installationId);

  const response = await githubFetch(url, {
    method: "POST",
    headers: {
      Authorization: `token ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
    timeoutMs: options.timeoutMs,
  });

  if (!response.ok) {
    const { message, body } = await parseGitHubError(
      response,
      "GitHub create repo failed",
    );
    log.error(
      {
        status: response.status,
        body: body.slice(0, 500),
        installationId,
        ...logCtx,
      },
      "Failed to create repo",
    );
    throw new GitHubApiError(message, response.status);
  }

  const data = (await response.json()) as Partial<GitHubRepoResponse>;
  if (typeof data.html_url !== "string" || typeof data.full_name !== "string") {
    log.error(
      {
        installationId,
        responseKeys: Object.keys(data),
        ...logCtx,
      },
      "GitHub repo create returned malformed response (missing html_url/full_name)",
    );
    throw new GitHubApiError(
      "GitHub returned a malformed repo creation response",
      502,
    );
  }
  log.info(
    { installationId, fullName: data.full_name, ...logCtx },
    "Created repo",
  );
  return { repoUrl: data.html_url, fullName: data.full_name };
}

async function createRepoForOrg(
  installationId: number,
  orgLogin: string,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  return postRepoCreate(
    installationId,
    `${GITHUB_API}/orgs/${orgLogin}/repos`,
    {
      name,
      private: isPrivate,
      auto_init: true,
      description: "Knowledge base managed by Soleur",
    },
    { op: "createRepoForOrg", name },
  );
}

/**
 * Create a repository for a user installation by generating from the
 * Soleur KB template. Used because POST /user/repos does not accept
 * installation tokens (UAT-only endpoint, returns 403). The template-generate
 * endpoint DOES accept installation tokens, provided the template is public
 * and marked is_template (private templates return 404 to cross-account
 * installation tokens — live-verified GitHub API limitation).
 */
async function createRepoFromTemplate(
  installationId: number,
  ownerLogin: string,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  return postRepoCreate(
    installationId,
    `${GITHUB_API}/repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME}/generate`,
    {
      owner: ownerLogin,
      name,
      private: isPrivate,
      include_all_branches: false,
      description: "Knowledge base managed by Soleur",
    },
    { op: "createRepoFromTemplate", name, ownerLogin },
    { timeoutMs: GITHUB_GENERATE_TIMEOUT_MS },
  );
}

/**
 * Create a repository using the GitHub App installation token.
 *
 * Determines whether the installation is on a user account or an
 * organization, then calls the appropriate GitHub API endpoint:
 * - Organization: POST /orgs/{org}/repos (requires administration:write)
 * - User: POST /repos/{template_owner}/{template_repo}/generate
 *   (POST /user/repos does not accept installation tokens — see
 *    createRepoFromTemplate for details)
 */
export async function createRepo(
  installationId: number,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const account = await getInstallationAccount(installationId);

  if (account.type === "Organization") {
    return createRepoForOrg(installationId, account.login, name, isPrivate);
  }

  // User installation: template-generate is the only working option.
  // POST /user/repos returns 403 "Resource not accessible by integration"
  // when called with an installation token (live-verified).
  return createRepoFromTemplate(installationId, account.login, name, isPrivate);
}

/**
 * Create a pull request on a repository using the GitHub App installation token.
 *
 * For same-repo PRs, `head` is just the branch name (not `owner:branch`).
 * Throws on error with a descriptive message extracted from GitHub's response.
 */
export async function createPullRequest(
  installationId: number,
  owner: string,
  repo: string,
  head: string,
  base: string,
  title: string,
  body?: string,
): Promise<PullRequestResult> {
  const token = await generateInstallationToken(installationId);

  const response = await githubFetch(
    `${GITHUB_API}/repos/${owner}/${repo}/pulls`,
    {
      method: "POST",
      headers: {
        Authorization: `token ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ head, base, title, body }),
    },
  );

  if (!response.ok) {
    const { message: errorMessage, body: errorBody } = await parseGitHubError(
      response,
      "GitHub create PR failed",
    );
    log.error(
      { status: response.status, body: errorBody.slice(0, 500), installationId, owner, repo },
      "Failed to create pull request",
    );
    throw new Error(errorMessage);
  }

  const data = (await response.json()) as {
    number: number;
    html_url: string;
    url: string;
  };

  return {
    number: data.number,
    htmlUrl: data.html_url,
    url: data.url,
  };
}
