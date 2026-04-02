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
// GitHub API helpers
// ---------------------------------------------------------------------------

const GITHUB_API = "https://api.github.com";

async function githubFetch(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...options.headers,
    },
  });
  return response;
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
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    if (response.status === 404) {
      return { verified: false, error: "Installation not found", status: 404 };
    }
    log.error(
      { status: response.status, installationId },
      "GitHub API error during installation verification",
    );
    return { verified: false, error: "Failed to verify installation", status: 502 };
  }

  const data = (await response.json()) as { account?: InstallationAccount };
  const account = data.account;
  if (!account?.login) {
    return { verified: false, error: "Installation has no account", status: 502 };
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
 * Uses the authenticated user endpoint via installation token. The repo
 * is created under the account that installed the GitHub App.
 */
export async function createRepo(
  installationId: number,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const token = await generateInstallationToken(installationId);

  // For GitHub App installations on user accounts, use /user/repos.
  // The installation token scopes the request to the installing user.
  const response = await githubFetch(`${GITHUB_API}/user/repos`, {
    method: "POST",
    headers: {
      Authorization: `token ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name,
      private: isPrivate,
      auto_init: true, // Initialize with README
      description: "Knowledge base managed by Soleur",
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    log.error(
      { status: response.status, body: body.slice(0, 500), installationId, name },
      "Failed to create repo",
    );
    throw new Error(`GitHub create repo failed: ${response.status}`);
  }

  const data = (await response.json()) as GitHubRepoResponse;
  return {
    repoUrl: data.html_url,
    fullName: data.full_name,
  };
}
