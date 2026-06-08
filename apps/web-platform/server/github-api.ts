/**
 * Thin GitHub API fetch wrapper for platform MCP tools (#1927).
 *
 * All GitHub API calls from agent sessions route through this module.
 * Authentication uses generateInstallationToken() — the agent subprocess
 * never sees the token.
 *
 * Safety: DELETE method calls are rejected at this layer to prevent
 * accidental branch/ref deletion from cloud agents.
 */

import { generateInstallationToken, GitHubApiError } from "./github-app";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

export { GitHubApiError };

const log = createChildLogger("github-api");

const GITHUB_API = "https://api.github.com";
const GITHUB_FETCH_TIMEOUT_MS = 15_000;
const MAX_RETRIES = 2; // 3 total attempts
const BASE_DELAY_MS = 1_000;

// ---------------------------------------------------------------------------
// Retry wrapper for transient failures
// ---------------------------------------------------------------------------

// Exported so the GitHub-App membership probe (server/github-app.ts) reuses the
// SAME transient classification rather than inventing a third retry shape
// (feat-one-shot-concierge-gh-403-self-heal, Bug A). Classifies the
// AbortSignal.timeout DOMException + undici network codes as retryable.
export function isRetryable(err: unknown): boolean {
  // AbortSignal.timeout() fires a DOMException with name "TimeoutError"
  if (err instanceof DOMException && err.name === "TimeoutError") return true;
  // Network-level fetch failure (undici throws TypeError with "fetch failed")
  if (err instanceof TypeError && err.message === "fetch failed") return true;
  // Undici-specific error codes
  if (
    err instanceof Error &&
    "code" in err &&
    typeof (err as { code: unknown }).code === "string"
  ) {
    const code = (err as { code: string }).code;
    return [
      "UND_ERR_CONNECT_TIMEOUT",
      "UND_ERR_SOCKET",
      "ECONNRESET",
      "ECONNREFUSED",
      "ENOTFOUND",
      "ENETDOWN",
    ].includes(code);
  }
  return false;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry(
  url: string,
  init: RequestInit,
): Promise<Response> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      // Each attempt gets a fresh AbortSignal — a timed-out signal cannot be reused
      const response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(GITHUB_FETCH_TIMEOUT_MS),
      });
      // Retry on 5xx (GitHub transient errors)
      if (response.status >= 500 && attempt < MAX_RETRIES) {
        lastError = new Error(`GitHub API ${response.status}`);
        // Drain response body to prevent socket keep-alive issues
        await response.text().catch(() => {});
        log.warn(
          { attempt: attempt + 1, status: response.status, url },
          "GitHub API fetch failed — retrying",
        );
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      return response;
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      if (attempt < MAX_RETRIES && isRetryable(err)) {
        log.warn(
          { attempt: attempt + 1, err: lastError.message, url },
          "GitHub API fetch failed — retrying",
        );
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      throw lastError;
    }
  }
  // TypeScript exhaustiveness guard — loop always exits via return or throw above
  throw lastError;
}

/**
 * Make an authenticated GET request to the GitHub API.
 * Handles 403 (permission upgrade needed) with a descriptive message.
 */
export async function githubApiGet<T = unknown>(
  installationId: number,
  path: string,
): Promise<T> {
  const token = await generateInstallationToken(installationId);

  const response = await fetchWithRetry(`${GITHUB_API}${path}`, {
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });

  if (!response.ok) {
    await handleErrorResponse(response, path);
  }

  return response.json() as Promise<T>;
}

/**
 * Make an authenticated GET request that returns plain text (e.g., job logs).
 * Same auth and error handling as githubApiGet, but returns text instead of JSON.
 */
export async function githubApiGetText(
  installationId: number,
  path: string,
): Promise<string> {
  const token = await generateInstallationToken(installationId);

  const response = await fetchWithRetry(`${GITHUB_API}${path}`, {
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });

  if (!response.ok) {
    await handleErrorResponse(response, path);
  }

  return response.text();
}

/**
 * Make an authenticated POST (or other method) request to the GitHub API.
 * DELETE method is rejected unconditionally as a safety guard.
 */
export async function githubApiPost<T = unknown>(
  installationId: number,
  path: string,
  body: Record<string, unknown>,
  method: string = "POST",
): Promise<T | null> {
  if (method.toUpperCase() === "DELETE") {
    throw new Error("DELETE method is not allowed from cloud agents");
  }

  const token = await generateInstallationToken(installationId);

  const response = await fetchWithRetry(`${GITHUB_API}${path}`, {
    method: method.toUpperCase(),
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    await handleErrorResponse(response, path);
  }

  // 204 No Content (e.g., workflow_dispatch) returns no body
  if (response.status === 204) {
    return null;
  }

  return response.json() as Promise<T>;
}

/**
 * Make an authenticated DELETE request to the GitHub API.
 * Restricted to first-party API routes — NOT exposed to cloud agent sessions.
 * The githubApiPost DELETE guard remains in place for agent safety.
 */
export async function githubApiDelete<T = unknown>(
  installationId: number,
  path: string,
  body: Record<string, unknown>,
): Promise<T | null> {
  const token = await generateInstallationToken(installationId);

  const response = await fetch(`${GITHUB_API}${path}`, {
    method: "DELETE",
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    await handleErrorResponse(response, path);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json() as Promise<T>;
}

async function handleErrorResponse(
  response: Response,
  path: string,
): Promise<never> {
  const bodyText = await response.text();

  if (response.status === 403) {
    // Surface the ACTUAL GitHub `message` instead of inventing a cause
    // (feat-one-shot-concierge-gh-403). A 403 on an org repo is usually a
    // WRONG-INSTALLATION token (a cross-account install that can read the repo
    // but lacks write), NOT a missing permission scope the user can re-consent
    // away — the org grant already exists. The old text ("approve new
    // permissions in installation settings") sent users on a fruitless
    // re-consent loop. Parse the real message; degrade honestly.
    let githubMessage = "";
    try {
      githubMessage = (JSON.parse(bodyText) as { message?: string }).message ?? "";
    } catch {
      githubMessage = bodyText.slice(0, 200);
    }
    log.warn(
      { status: 403, path, githubMessage, body: bodyText.slice(0, 500) },
      "GitHub API 403",
    );
    // cq-silent-fallback-must-mirror-to-sentry: make 403s queryable rather
    // than swallowing the real cause behind a hard-coded message.
    reportSilentFallback(new Error(`GitHub API 403: ${path}`), {
      feature: "github-api",
      op: "handle-403",
      extra: { path, githubMessage, status: 403 },
      message: "GitHub API returned 403",
    });
    throw new GitHubApiError(
      `GitHub API 403 for ${path}` +
        (githubMessage ? `: "${githubMessage}"` : "") +
        ". This usually means the installation cannot access this resource " +
        "(e.g. a wrong-installation token) — not a missing permission scope.",
      403,
    );
  }

  log.error(
    { status: response.status, path, body: bodyText.slice(0, 500) },
    "GitHub API request failed",
  );
  throw new GitHubApiError(
    `GitHub API request failed: ${response.status} ${path}`,
    response.status,
  );
}
