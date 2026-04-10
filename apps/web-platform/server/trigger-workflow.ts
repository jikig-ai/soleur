/**
 * Workflow trigger handler for platform MCP tools (#1928).
 *
 * Dispatches workflow_dispatch events and returns the new run ID.
 * Rate limited to 10 triggers per session to prevent runaway loops.
 */

import { githubApiPost } from "./github-api";
import { readCiStatus } from "./ci-tools";
import { createChildLogger } from "./logger";

const log = createChildLogger("trigger-workflow");

const MAX_TRIGGERS_PER_SESSION = 10;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TriggerResult {
  runId: number | null;
  status: string;
  url: string | null;
}

export interface RateLimiter {
  check: () => boolean;
  increment: () => void;
  remaining: () => number;
}

// ---------------------------------------------------------------------------
// Rate limiter
// ---------------------------------------------------------------------------

/**
 * Create a session-scoped rate limiter for workflow triggers.
 * Max 10 triggers per session (prevents runaway agent loops).
 */
export function createRateLimiter(max: number = MAX_TRIGGERS_PER_SESSION): RateLimiter {
  let count = 0;
  return {
    check: () => count < max,
    increment: () => { count = count + 1; },
    remaining: () => max - count,
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Trigger a workflow_dispatch event and return the new run.
 *
 * After dispatching, polls recent runs once to find the new run ID.
 * The gating (review gate) is handled by canUseTool — this function
 * only executes after the founder has approved.
 */
export async function triggerWorkflow(
  installationId: number,
  owner: string,
  repo: string,
  workflowId: number,
  ref: string,
  rateLimiter: RateLimiter,
  inputs?: Record<string, string>,
): Promise<TriggerResult> {
  if (!rateLimiter.check()) {
    throw new Error(
      `Rate limit exceeded: max ${MAX_TRIGGERS_PER_SESSION} workflow triggers per session ` +
      `(${rateLimiter.remaining()} remaining)`,
    );
  }

  const body: Record<string, unknown> = { ref };
  if (inputs && Object.keys(inputs).length > 0) {
    body.inputs = inputs;
  }

  await githubApiPost(
    installationId,
    `/repos/${owner}/${repo}/actions/workflows/${workflowId}/dispatches`,
    body,
  );

  rateLimiter.increment();

  log.info(
    { workflowId, ref, owner, repo, remaining: rateLimiter.remaining() },
    "Workflow dispatched",
  );

  // Poll once for the new run (workflow_dispatch is async — run may not
  // appear instantly, but usually does within a few seconds)
  try {
    const runs = await readCiStatus(installationId, owner, repo, {
      branch: ref,
      per_page: 5,
    });

    if (runs.length > 0) {
      const latest = runs[0];
      return {
        runId: latest.id,
        status: latest.status,
        url: latest.url,
      };
    }
  } catch (err) {
    log.warn({ err }, "Failed to fetch run after dispatch — run may still be queuing");
  }

  return {
    runId: null,
    status: "dispatched",
    url: null,
  };
}
