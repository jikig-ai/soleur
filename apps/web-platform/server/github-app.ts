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

async function githubFetch(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(15_000),
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
 * Generate a unique, unpredictable credential helper filename.
 * Prevents symlink attacks and token theft from predictable paths.
 */
export function randomCredentialPath(): string {
  return `/tmp/git-cred-${randomUUID()}`;
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

/**
 * Create a repository using the GitHub App installation token.
 *
 * Determines whether the installation is on a user account or an
 * organization, then calls the appropriate GitHub API endpoint:
 * - Organization: POST /orgs/{org}/repos (requires administration:write)
 * - User: POST /user/repos
 */
export async function createRepo(
  installationId: number,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const account = await getInstallationAccount(installationId);
  const token = await generateInstallationToken(installationId);

  const endpoint = account.type === "Organization"
    ? `${GITHUB_API}/orgs/${account.login}/repos`
    : `${GITHUB_API}/user/repos`;

  const response = await githubFetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `token ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name,
      private: isPrivate,
      auto_init: true,
      description: "Knowledge base managed by Soleur",
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    let errorMessage = `GitHub create repo failed: ${response.status}`;
    try {
      const parsed = JSON.parse(body);
      if (parsed.errors?.[0]?.message) {
        errorMessage = parsed.errors[0].message;
      } else if (parsed.message) {
        errorMessage = `GitHub create repo failed: ${response.status} - ${parsed.message}`;
      }
    } catch {
      // Non-JSON response
    }
    log.error(
      { status: response.status, body: body.slice(0, 500), installationId, name },
      "Failed to create repo",
    );
    throw new GitHubApiError(errorMessage, response.status);
  }

  const data = (await response.json()) as GitHubRepoResponse;
  return {
    repoUrl: data.html_url,
    fullName: data.full_name,
  };
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
    const errorBody = await response.text();
    // Extract the most useful error message from GitHub's response
    let errorMessage = `GitHub create PR failed: ${response.status}`;
    try {
      const parsed = JSON.parse(errorBody);
      const firstError = parsed.errors?.[0]?.message;
      if (firstError) {
        errorMessage = firstError;
      } else if (parsed.message) {
        errorMessage = `GitHub create PR failed: ${response.status} - ${parsed.message}`;
      }
    } catch {
      // Non-JSON response body -- use generic message
    }
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
