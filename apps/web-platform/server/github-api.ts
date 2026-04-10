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

import { generateInstallationToken } from "./github-app";
import { createChildLogger } from "./logger";

const log = createChildLogger("github-api");

const GITHUB_API = "https://api.github.com";

/**
 * Make an authenticated GET request to the GitHub API.
 * Handles 403 (permission upgrade needed) with a descriptive message.
 */
export async function githubApiGet<T = unknown>(
  installationId: number,
  path: string,
): Promise<T> {
  const token = await generateInstallationToken(installationId);

  const response = await fetch(`${GITHUB_API}${path}`, {
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

  const response = await fetch(`${GITHUB_API}${path}`, {
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

async function handleErrorResponse(
  response: Response,
  path: string,
): Promise<never> {
  const bodyText = await response.text();

  if (response.status === 403) {
    log.warn(
      { status: 403, path, body: bodyText.slice(0, 500) },
      "GitHub API 403 — possible permission gap",
    );
    throw new Error(
      `GitHub API permission denied (403) for ${path}. ` +
      "Your Soleur GitHub App installation may need updated permissions. " +
      "Visit your GitHub App installation settings to approve new permissions.",
    );
  }

  log.error(
    { status: response.status, path, body: bodyText.slice(0, 500) },
    "GitHub API request failed",
  );
  throw new Error(`GitHub API request failed: ${response.status} ${path}`);
}
