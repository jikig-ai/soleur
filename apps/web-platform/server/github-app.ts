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

import { createHash, createSign, randomUUID } from "crypto";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import { readAppId } from "./github/app-private-key";
import { isRetryable, delay } from "./github-retry";

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

export interface IssueResult {
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
  // The access-tokens POST returns these in the SAME body (no extra round-trip).
  // They make a wrong-installation token self-diagnosing at mint time:
  // `repository_selection: "selected"` with the connected repo absent from the
  // token's repo set is the wrong-installation signature. Both optional —
  // older/edge responses may omit them. Type widening is additive AND
  // single-consumer (only github-app.ts), so blast-radius is zero
  // (hr-type-widening-cross-consumer-grep).
  repository_selection?: "all" | "selected";
  permissions?: Record<string, string>;
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
  // Trim + numeric-validate before it becomes the JWT `iss`. The hand-rolled
  // signer reads the same GITHUB_APP_ID as the @octokit/app paths, so the same
  // whitespace/client-id-confusion class applies here (Sentry 00bdfdf1…: a
  // trailing-newline App ID). Shared guard keeps every App-JWT path consistent.
  return readAppId(appId);
}

let pemShapeWarned = false;

function getPrivateKey(): string {
  const raw = process.env.GITHUB_APP_PRIVATE_KEY;
  if (!raw) throw new Error("GITHUB_APP_PRIVATE_KEY is not set");
  // Handle escaped newlines from env vars (common in Docker/Doppler)
  const pem = raw.replace(/\\n/g, "\n");
  if (!pemShapeWarned && !/^-----BEGIN (RSA )?PRIVATE KEY-----/.test(pem)) {
    pemShapeWarned = true;
    log.warn(
      { rawLength: pem.length, hasBeginMarker: pem.includes("-----BEGIN") },
      "PEM does not start with expected header — key may be corrupted",
    );
  }
  return pem;
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
    // 540s — 60s below GitHub's 600s max JWT lifetime to absorb positive
    // server-clock skew (GitHub rejects exp > now+600 as 401). octokit's
    // universal-github-app-jwt uses now+570 for the same reason. #122537945.
    exp: now + 9 * 60,
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

// ---------------------------------------------------------------------------
// Org-membership probe (transient-robust, fail-closed)
//
// feat-one-shot-concierge-gh-403-self-heal (Bug A). A bare `status === 204`
// check collapses a genuine 404/302 ("not a member" → correctly deny) and a
// TRANSIENT 5xx / AbortSignal.timeout throw into the SAME "deny" outcome — so
// an ENTITLED org member is wrongly denied promotion (kept on the wrong
// installation → 403) purely because GitHub's /orgs/{org}/members/{login}
// endpoint 5xx'd or timed out for ~3s. Classify into three outcomes and retry
// ONLY the transient class, reusing the canonical backoff idiom from
// server/github-api.ts (isRetryable already classifies the AbortSignal.timeout
// DOMException + undici network codes as retryable).
//
// SECURITY (fail-closed): the retry gates an AUTHORIZATION decision, so a
// post-retry `indeterminate` DENIES promotion (only a confirmed 204 grants).
// Narrowing the false-negative must NOT widen the entitlement gate. No token
// value is ever logged (hr-github-app-auth-not-pat).
// ---------------------------------------------------------------------------

// Match the sibling install-token retry constants (INSTALL_TOKEN_MAX_RETRIES=2,
// INSTALL_TOKEN_BASE_DELAY_MS=1_000, defined later in this file) so the three
// retry sites stay consistent. Literals (not the named constants) to avoid a
// temporal-dead-zone reference — those consts are declared further down.
const MEMBER_PROBE_MAX_RETRIES = 2; // 3 total attempts
const MEMBER_PROBE_BASE_DELAY_MS = 1_000; // 1s, 2s

type MembershipProbeOutcome = "member" | "not-member" | "indeterminate";

/**
 * Probe whether `githubLogin` is a member of org `owner`, using the org
 * installation's token (carries members:read). Returns a 3-value outcome:
 *   - `member`        — 204 (the ONLY path that grants promotion)
 *   - `not-member`    — 404 / 302 (authoritative; NOT retried — a definitive
 *                       answer; retrying it is a pure latency tax)
 *   - `indeterminate` — transient 5xx / thrown timeout/network (retried up to
 *                       MEMBER_PROBE_MAX_RETRIES), or any other non-authoritative
 *                       status (e.g. 403) after retries. Fail-closed: the caller
 *                       must DENY promotion on `indeterminate`.
 */
async function probeOrgMembership(
  owner: string,
  githubLogin: string,
  installationToken: string,
): Promise<MembershipProbeOutcome> {
  const url = `${GITHUB_API}/orgs/${encodeURIComponent(owner)}/members/${encodeURIComponent(githubLogin)}`;
  for (let attempt = 0; attempt <= MEMBER_PROBE_MAX_RETRIES; attempt++) {
    let response: Response;
    try {
      response = await githubFetch(url, {
        headers: { Authorization: `token ${installationToken}` },
        // Do NOT follow the 302 GitHub returns for "requester not visible as an
        // org member" — following it lands on /public_members and turns one
        // authoritative deny into a second probe. Surface 302 as not-member,
        // matching verifyInstallationOwnership's redirect:"manual" precedent.
        redirect: "manual",
      });
    } catch (err) {
      // AbortSignal.timeout fires a DOMException; undici network errors throw.
      // Retry the transient class, else fail-closed → indeterminate.
      if (attempt < MEMBER_PROBE_MAX_RETRIES && isRetryable(err)) {
        await delay(MEMBER_PROBE_BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      return "indeterminate";
    }

    if (response.status === 204) return "member";
    // 404 = not a member; 302 = requester not visible as org member. Both are
    // authoritative — drain and return WITHOUT retrying.
    if (response.status === 404 || response.status === 302) {
      await response.text().catch(() => {});
      return "not-member";
    }
    // Drain before any sleep/return to avoid socket keep-alive leaks.
    await response.text().catch(() => {});
    // 5xx = transient → retry. Anything else (403, …) → indeterminate (no retry).
    if (response.status >= 500 && attempt < MEMBER_PROBE_MAX_RETRIES) {
      await delay(MEMBER_PROBE_BASE_DELAY_MS * 2 ** attempt);
      continue;
    }
    return "indeterminate";
  }
  return "indeterminate";
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

    // Transient-robust, fail-closed membership probe (Bug A). A transient 5xx /
    // timeout on one org no longer silently skips an entitled org — it retries
    // first; only a confirmed `member` returns the install.
    const outcome = await probeOrgMembership(
      inst.account.login,
      githubLogin,
      installationToken,
    );
    if (outcome === "member") {
      log.info(
        { githubLogin, orgLogin: inst.account.login, installationId: inst.id },
        "Found org installation for user",
      );
      return inst.id;
    }
  }

  return null;
}

/**
 * Find the GitHub App installation whose ACCOUNT LOGIN equals `login`
 * (case-insensitive) — i.e. the installation that OWNS that account's repos.
 *
 * This disambiguates the wrong-installation 403 root cause
 * (feat-one-shot-concierge-gh-403): a repo owned by an org can be reachable by
 * BOTH the org's installation (full grant, `issues: write`) and a cross-account
 * personal/collaborator installation (reduced grant, `issues: read`). A read
 * probe (`checkRepoAccess`) passes for BOTH, so it cannot tell them apart —
 * only the account-login match deterministically selects the owning install
 * that carries the full grant. Passing the repo OWNER here yields the
 * installation that can actually create issues, push, etc.
 *
 * Single `GET /app/installations` call (App JWT). Returns null when no account
 * matches or the listing degrades — the caller keeps its existing installation
 * (graceful: never block a dispatch on this probe). This is installation
 * SELECTION, never a permission change — the owning grant already exists.
 */
export async function findInstallationByAccountLogin(
  login: string,
): Promise<number | null> {
  const jwt = createAppJwt();
  // Single page of 100 — same cap as findOrgInstallationForUser. If the App
  // ever exceeds 100 installations, an owner install on a later page is missed
  // (returns null → caller keeps its installation, fail-safe). Revisit with
  // Link-header pagination if the App scales past that.
  const response = await githubFetch(
    `${GITHUB_API}/app/installations?per_page=100`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    log.warn(
      { status: response.status, login },
      "Failed to list app installations for account-login match",
    );
    return null;
  }

  interface AppInstallation {
    id: number;
    account: { login?: string } | null;
  }

  const installations = (await response.json()) as AppInstallation[];
  const target = login.toLowerCase();
  const match = installations.find(
    (i) => i.account?.login?.toLowerCase() === target,
  );
  return match?.id ?? null;
}

/**
 * Resolve the repo-OWNER's installation for `owner/...`, but ONLY when the
 * dispatching user (`githubLogin`) is ENTITLED to act through it. Returns the
 * installation id on entitlement, else null.
 *
 * Why the entitlement gate (security — feat-one-shot-concierge-gh-403, P1):
 * `findInstallationByAccountLogin` alone would let an OUTSIDE read-only
 * collaborator on an org repo (who can connect it — the read probe passes) be
 * promoted to the org's WRITE-capable installation, a cross-tenant privilege
 * escalation (the installation token acts as the APP with the org's full grant,
 * independent of the user's personal repo permission). Entitlement holds when:
 *   - the owner account IS the user's own account (personal repo — no escalation), OR
 *   - the user is a verified MEMBER of the owner org
 *     (`GET /orgs/{owner}/members/{login}` → 204, the same check
 *     `findOrgInstallationForUser` uses; the owner install carries members:read).
 * A non-member gets null → the caller keeps its current installation and the
 * honest 403 surfaces, rather than silently gaining write it was never granted.
 */
/**
 * Why the promotion was (or was not) granted. Surfaced to the orchestration
 * (cc-dispatcher) so a DENY/SKIP becomes a queryable Sentry event rather than
 * an observability-dark silent keep (feat-one-shot-concierge-gh-403-self-heal,
 * Bug B). `installationId !== null` only on `personal-repo` / `member`.
 */
export type RepoOwnerPromotionOutcome =
  | "no-github-login"
  | "no-owner-install"
  | "personal-repo"
  | "member"
  | "not-member"
  | "indeterminate"
  | "token-mint-failed";

export interface RepoOwnerInstallationResolution {
  /** The entitled owner installation id, or null when promotion is denied. */
  installationId: number | null;
  outcome: RepoOwnerPromotionOutcome;
}

export async function findRepoOwnerInstallationForUser(
  owner: string,
  githubLogin: string | null,
): Promise<RepoOwnerInstallationResolution> {
  if (!githubLogin)
    return { installationId: null, outcome: "no-github-login" };

  const ownerInstall = await findInstallationByAccountLogin(owner);
  if (ownerInstall === null)
    return { installationId: null, outcome: "no-owner-install" };

  // Personal repo (owner is the user's own account) — no escalation possible.
  if (owner.toLowerCase() === githubLogin.toLowerCase())
    return { installationId: ownerInstall, outcome: "personal-repo" };

  // Org repo — require verified org membership before promoting. Mint the
  // owner install's token (members:read) and probe membership.
  let installationToken: string;
  try {
    installationToken = await generateInstallationToken(ownerInstall);
  } catch (err) {
    log.warn(
      { err, ownerInstall, owner },
      "findRepoOwnerInstallationForUser: token mint failed — denying promotion",
    );
    return { installationId: null, outcome: "token-mint-failed" };
  }

  // Transient-robust, fail-closed (Bug A): the owner install is returned ONLY
  // on a confirmed `member` (204). A post-retry `indeterminate` (transient
  // 5xx/timeout) or an authoritative `not-member` both DENY — keeping the
  // stored install and the honest 403 rather than silently granting write.
  const outcome = await probeOrgMembership(owner, githubLogin, installationToken);
  return outcome === "member"
    ? { installationId: ownerInstall, outcome: "member" }
    : { installationId: null, outcome };
}

// ---------------------------------------------------------------------------
// Token cache (installation tokens are valid for 1 hour)
// ---------------------------------------------------------------------------

// Keyed on installationId AND the requested scope (permissions + repositories),
// NOT installationId alone. A narrowed cron token (#5046) and the broad token
// the ~10 interactive/agent callers mint share the SAME installation id; keying
// on the id alone would return whichever was minted first to BOTH — a silent
// over-privilege (broad caller served a narrow token → 403) OR under-containment
// (narrow caller served the broad token → the narrowing is defeated). The scope
// is folded into the key so differently-scoped requests never collide.
const tokenCache = new Map<string, { token: string; expiresAt: number }>();

const TOKEN_SAFETY_MARGIN_MS = 5 * 60 * 1000; // Refresh 5 minutes early

// Deterministic cache key. An UNSCOPED request (no permissions, no repositories)
// keys under the bare installation id so every existing broad-scope caller keeps
// its current keyspace (zero behavior change). A scoped request appends a stable,
// sorted serialization of the requested permissions + repositories.
function installationTokenCacheKey(
  installationId: number,
  permissions?: Record<string, string>,
  repositories?: string[],
): string {
  if (!permissions && !repositories) return String(installationId);
  // JSON-serialize a normalized, sorted structure (NOT a hand-joined
  // `k=v,…`/`r:…` string) so a permission value or repo name that contains a
  // delimiter can never alias another scope's key — future-proofing for PR-2,
  // which adds more scoped callers (possibly repository_ids / non-soleur repos).
  // The unscoped path stays the bare numeric id, disjoint from every scoped key
  // (those always carry the `|` separator, which a `String(number)` never does).
  const permEntries = permissions
    ? Object.keys(permissions)
        .sort()
        .map((k) => [k, permissions[k]] as const)
    : [];
  const repoList = repositories ? [...repositories].sort() : [];
  return `${installationId}|${JSON.stringify({ p: permEntries, r: repoList })}`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Exchange a GitHub App JWT for an installation access token.
 * Tokens are cached in memory and refreshed 5 minutes before expiry.
 *
 * @param installationId GitHub App installation id.
 * @param opts.minRemainingMs Minimum remaining lifetime (ms) the returned
 *   token MUST have. Callers that spawn long-running children (e.g. the
 *   cron-bug-fixer's 50-min claude-eval) pass a floor that exceeds their
 *   wall-clock budget to avoid mid-spawn auth failures when the cache is
 *   warm with a token whose lifetime is less than the budget remaining
 *   (TR9 PR-5 security HIGH-1).
 * @param opts.permissions Optional least-privilege permission subset for the
 *   minted token (e.g. `{ contents: "write", issues: "write" }`). Posted as the
 *   access_tokens body. The GitHub App install-time manifest is the hard ceiling
 *   — this can only narrow WITHIN the granted permissions, never widen. Omit for
 *   the full installation grant. Folded into the cache key (#5046).
 * @param opts.repositories Optional repo-name allowlist (e.g. `["soleur"]`) that
 *   bounds the token to those repositories — a leaked token cannot be replayed
 *   cross-repo. Posted as the access_tokens body. Omit for all installed repos.
 *   Folded into the cache key (#5046).
 */
// Installation-token mint retry budget. Mirrors the canonical backoff idiom in
// server/github-api.ts (MAX_RETRIES=2, BASE_DELAY_MS=1_000 → 1s, 2s) but retries
// on 401 only (the mint's transient class is JWT-replication/clock-skew, not
// 5xx). 3 total attempts. #122537945.
const INSTALL_TOKEN_MAX_RETRIES = 2;
const INSTALL_TOKEN_BASE_DELAY_MS = 1_000;

export async function generateInstallationToken(
  installationId: number,
  opts: {
    minRemainingMs?: number;
    permissions?: Record<string, string>;
    repositories?: string[];
  } = {},
): Promise<string> {
  const minRemainingMs = opts.minRemainingMs ?? TOKEN_SAFETY_MARGIN_MS;
  const { permissions, repositories } = opts;
  const cacheKey = installationTokenCacheKey(
    installationId,
    permissions,
    repositories,
  );
  const cached = tokenCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now() + minRemainingMs) {
    return cached.token;
  }
  // Drop a cached-but-too-short-lived token so we always re-mint when the
  // floor is not met (otherwise the same stale entry would be reconsidered
  // by re-entrant callers).
  if (cached) {
    tokenCache.delete(cacheKey);
  }

  const pem = getPrivateKey();
  const pemFingerprint = createHash("sha256").update(pem).digest("hex").slice(0, 8);

  function mintAndExchange() {
    const jwt = createAppJwt();
    // Post a scoped body ONLY when narrowing is requested; an unscoped mint
    // stays bodyless (full installation grant) — byte-for-byte the prior
    // behavior for the ~10 broad-scope callers.
    const scopeBody: Record<string, unknown> = {};
    if (permissions) scopeBody.permissions = permissions;
    if (repositories) scopeBody.repositories = repositories;
    const hasScope = Object.keys(scopeBody).length > 0;
    return githubFetch(
      `${GITHUB_API}/app/installations/${installationId}/access_tokens`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
          ...(hasScope ? { "Content-Type": "application/json" } : {}),
        },
        ...(hasScope ? { body: JSON.stringify(scopeBody) } : {}),
      },
    );
  }

  let response = await mintAndExchange();

  // Retry on 401 with exponential backoff — defensive against transient GitHub
  // JWT-replication / clock-skew rejections of the token exchange. 401-only
  // (any non-401 breaks immediately, preserving 403/5xx semantics); a fresh JWT
  // is minted per attempt; the body is drained before each sleep to avoid
  // socket leaks. Mirrors the canonical backoff idiom in server/github-api.ts.
  // #122537945 — the single 1s retry from PR #4498 was insufficient (90 events
  // over 14 days); 2 retries (1s, 2s) covers the observed transient window.
  for (
    let attempt = 0;
    response.status === 401 && attempt < INSTALL_TOKEN_MAX_RETRIES;
    attempt++
  ) {
    log.warn(
      { installationId, attempt: attempt + 1, status: response.status },
      "401 on installation token — retrying with backoff",
    );
    await response.text().catch(() => {});
    await new Promise((r) =>
      setTimeout(r, INSTALL_TOKEN_BASE_DELAY_MS * 2 ** attempt),
    );
    response = await mintAndExchange();
  }

  if (!response.ok) {
    const body = await response.text();
    log.error(
      {
        status: response.status,
        body: body.slice(0, 500),
        installationId,
        appId: getAppId(),
        pemFingerprint,
      },
      "Failed to generate installation token",
    );
    const err = new Error(
      `GitHub installation token request failed: ${response.status}`,
    );
    reportSilentFallback(err, {
      feature: "github-app",
      op: "generate-installation-token",
      extra: { installationId, status: response.status },
    });
    throw err;
  }

  const data = (await response.json()) as GitHubInstallationTokenResponse;

  // Mint-time observability (feat-one-shot-concierge-gh-403). Log the
  // installation id, the token's repository_selection, and the SORTED granted
  // permission KEYS so a future 403 is self-diagnosing without guessing which
  // installation/scope was used — a "selected" token missing the connected
  // repo, or a permission-key gap, is visible in the log line. NEVER log
  // `data.token` (hr-github-app-auth-not-pat) — keys/selection are non-secret
  // metadata; the token value is the secret.
  log.info(
    {
      installationId,
      repositorySelection: data.repository_selection,
      permissionKeys: Object.keys(data.permissions ?? {}).sort(),
      appId: getAppId(),
    },
    "Minted installation token",
  );

  tokenCache.set(cacheKey, {
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
 * Latest commit timestamp (epoch ms) on a repo's DEFAULT branch, via the
 * installation token. Used by the KB-sync went-quiet detector (#4717) to
 * correlate real default-branch activity against the last successful sync —
 * the out-of-band signal that `kb_sync_history` cannot provide once a workspace
 * goes quiet (it stops writing rows).
 *
 * `GET /commits?per_page=1` with no `sha` lists the repo's default branch.
 * Returns the HEAD commit's `committer.date` as epoch ms; `null` when the repo
 * has no commits (brand-new repo → GitHub 409 Conflict, or an empty array).
 * Throws on token / network / other non-200 so the caller can classify it as a
 * probe error (reportSilentFallback). Mirrors `checkRepoAccess` above.
 */
export async function getDefaultBranchHeadCommitAt(
  installationId: number,
  owner: string,
  repo: string,
): Promise<number | null> {
  const token = await generateInstallationToken(installationId);
  // Encode the path segments (defense-in-depth, matching this file's upstream-
  // distrust posture): repo_url is DB-sourced and canonical today, but encoding
  // forecloses any `?`/`#`/`..`-in-segment from reshaping the GitHub API path.
  const response = await githubFetch(
    `${GITHUB_API}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits?per_page=1`,
    { headers: { Authorization: `token ${token}` } },
  );
  // Empty repository → GitHub returns 409 ("Git Repository is empty"); not an
  // error for our purposes — there is simply nothing to have gone quiet.
  if (response.status === 409) return null;
  if (response.status !== 200) {
    throw new Error(
      `GitHub GET /commits returned ${response.status} for ${owner}/${repo}`,
    );
  }
  const body = (await response.json()) as Array<{
    commit?: { committer?: { date?: string } };
  }>;
  if (!Array.isArray(body) || body.length === 0) return null;
  const dateStr = body[0]?.commit?.committer?.date;
  if (!dateStr) return null;
  const ms = Date.parse(dateStr);
  return Number.isNaN(ms) ? null : ms;
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

/**
 * Find the first OPEN pull request matching `head` → `base` on a repository,
 * via the GitHub App installation token. Returns `null` when none is open.
 *
 * For same-repo PRs the `head` filter qualifier is `{owner}:{branch}` (GitHub's
 * `GET /pulls?head=` expects the user/org-qualified ref). Mirrors
 * `createPullRequest`'s auth + error surface so the kb-sync protected-fallback
 * (#5426) can create-or-update a single durable `soleur/kb-sync` PR without
 * recreating it every session. Throws on a non-OK response (so the caller's
 * try/catch preserves writes-on-default for retry rather than silently
 * recreating).
 */
export async function findOpenPullRequest(
  installationId: number,
  owner: string,
  repo: string,
  head: string,
  base: string,
): Promise<PullRequestResult | null> {
  const token = await generateInstallationToken(installationId);

  const headParam = encodeURIComponent(`${owner}:${head}`);
  const baseParam = encodeURIComponent(base);
  const response = await githubFetch(
    `${GITHUB_API}/repos/${owner}/${repo}/pulls?head=${headParam}&base=${baseParam}&state=open`,
    {
      method: "GET",
      headers: { Authorization: `token ${token}` },
    },
  );

  if (!response.ok) {
    const { message: errorMessage, body: errorBody } = await parseGitHubError(
      response,
      "GitHub list PRs failed",
    );
    log.error(
      { status: response.status, body: errorBody.slice(0, 500), installationId, owner, repo },
      "Failed to list pull requests",
    );
    throw new Error(errorMessage);
  }

  const data = (await response.json()) as Array<{
    number: number;
    html_url: string;
    url: string;
  }>;
  if (!Array.isArray(data) || data.length === 0) return null;
  const pr = data[0];
  return { number: pr.number, htmlUrl: pr.html_url, url: pr.url };
}

/**
 * Create an issue on a repository using the GitHub App installation token.
 *
 * Mirrors `createPullRequest`: same auth surface (`issues: write` already
 * granted), same `parseGitHubError` error path. Throws on error with a
 * descriptive message extracted from GitHub's response.
 */
export async function createIssue(
  installationId: number,
  owner: string,
  repo: string,
  title: string,
  body?: string,
  labels?: string[],
): Promise<IssueResult> {
  const token = await generateInstallationToken(installationId);

  const response = await githubFetch(
    `${GITHUB_API}/repos/${owner}/${repo}/issues`,
    {
      method: "POST",
      headers: {
        Authorization: `token ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ title, body, labels }),
    },
  );

  if (!response.ok) {
    const { message: errorMessage, body: errorBody } = await parseGitHubError(
      response,
      "GitHub create issue failed",
    );
    log.error(
      { status: response.status, body: errorBody.slice(0, 500), installationId, owner, repo },
      "Failed to create issue",
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
