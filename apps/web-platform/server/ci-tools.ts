/**
 * CI/CD tool handler functions for platform MCP tools (#1927).
 *
 * Extracted from agent-runner.ts for unit testability. Each function
 * corresponds to an MCP tool registered in the soleur_platform server.
 *
 * These functions use github-api.ts for authenticated requests —
 * the agent subprocess never sees GitHub tokens.
 */

import { githubApiGet, githubApiGetText } from "./github-api";
import { createChildLogger } from "./logger";

const log = createChildLogger("ci-tools");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface CiRunSummary {
  id: number;
  name: string;
  branch: string;
  sha: string;
  status: string;
  conclusion: string | null;
  url: string;
  workflowId: number;
}

export interface Annotation {
  path: string;
  line: number;
  level: string;
  message: string;
}

export interface FallbackLog {
  jobName: string;
  stepName: string;
  lines: string;
}

export interface WorkflowLogResult {
  conclusion: string | null;
  annotations: Annotation[];
  fallbackLog?: FallbackLog;
  url?: string;
}

// ---------------------------------------------------------------------------
// GitHub API response types
// ---------------------------------------------------------------------------

interface WorkflowRunsResponse {
  total_count: number;
  workflow_runs: Array<{
    id: number;
    name: string;
    head_branch: string;
    head_sha: string;
    status: string;
    conclusion: string | null;
    html_url: string;
    workflow_id: number;
    created_at: string;
  }>;
}

interface CheckRunsResponse {
  total_count: number;
  check_runs: Array<{
    id: number;
    name: string;
    conclusion: string | null;
    output: {
      annotations_count: number;
    };
  }>;
}

interface GitHubAnnotation {
  path: string;
  start_line: number;
  end_line: number;
  annotation_level: string;
  message: string;
}

interface JobsResponse {
  total_count: number;
  jobs: Array<{
    id: number;
    name: string;
    conclusion: string | null;
    steps: Array<{
      name: string;
      conclusion: string | null;
      number: number;
    }>;
  }>;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Read recent CI workflow runs for a repo.
 * Returns a summary of each run with status, SHA, branch, and URL.
 */
export async function readCiStatus(
  installationId: number,
  owner: string,
  repo: string,
  options?: { branch?: string; per_page?: number },
): Promise<CiRunSummary[]> {
  const params = new URLSearchParams();
  if (options?.branch) params.set("branch", options.branch);
  params.set("per_page", String(options?.per_page ?? 10));

  const queryString = params.toString();
  const path = `/repos/${owner}/${repo}/actions/runs${queryString ? `?${queryString}` : ""}`;

  const data = await githubApiGet<WorkflowRunsResponse>(installationId, path);

  return data.workflow_runs.map((run) => ({
    id: run.id,
    name: run.name,
    branch: run.head_branch,
    sha: run.head_sha,
    status: run.status,
    conclusion: run.conclusion,
    url: run.html_url,
    workflowId: run.workflow_id,
  }));
}

/**
 * Read workflow logs for a specific run.
 *
 * Strategy (per spec):
 * 1. Fetch check run annotations (structured failure data, small payload)
 * 2. If no annotations, fall back to last 100 lines of the first failed step
 *
 * This avoids downloading multi-MB log zips while giving agents
 * actionable failure context.
 */
export async function readWorkflowLogs(
  installationId: number,
  owner: string,
  repo: string,
  runId: number,
): Promise<WorkflowLogResult> {
  // 1. Resolve the run's head_sha (the commits/check-runs endpoint needs
  //    a commit ref, not a workflow run ID)
  const run = await githubApiGet<{ head_sha: string; conclusion: string | null }>(
    installationId,
    `/repos/${owner}/${repo}/actions/runs/${runId}`,
  );

  const checkData = await githubApiGet<CheckRunsResponse>(
    installationId,
    `/repos/${owner}/${repo}/commits/${run.head_sha}/check-runs`,
  );

  if (checkData.check_runs.length === 0) {
    return { conclusion: null, annotations: [] };
  }

  // Use the first check run's conclusion as the overall conclusion
  const primaryCheck = checkData.check_runs[0];
  const overallConclusion = primaryCheck.conclusion;

  // 2. Try annotations first
  const totalAnnotations = checkData.check_runs.reduce(
    (sum, cr) => sum + cr.output.annotations_count,
    0,
  );

  if (totalAnnotations > 0) {
    const annotations = await fetchAnnotations(
      installationId,
      owner,
      repo,
      checkData.check_runs,
    );
    return {
      conclusion: overallConclusion,
      annotations,
    };
  }

  // 3. Fallback: last 100 lines of the first failed step
  const fallbackLog = await fetchFallbackLog(
    installationId,
    owner,
    repo,
    runId,
  );

  return {
    conclusion: overallConclusion,
    annotations: [],
    fallbackLog: fallbackLog ?? undefined,
  };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

async function fetchAnnotations(
  installationId: number,
  owner: string,
  repo: string,
  checkRuns: CheckRunsResponse["check_runs"],
): Promise<Annotation[]> {
  const annotations: Annotation[] = [];

  for (const cr of checkRuns) {
    if (cr.output.annotations_count === 0) continue;

    try {
      const rawAnnotations = await githubApiGet<GitHubAnnotation[]>(
        installationId,
        `/repos/${owner}/${repo}/check-runs/${cr.id}/annotations`,
      );

      for (const a of rawAnnotations) {
        annotations.push({
          path: a.path,
          line: a.start_line,
          level: a.annotation_level,
          message: a.message,
        });
      }
    } catch (err) {
      log.warn({ err, checkRunId: cr.id }, "Failed to fetch annotations");
    }
  }

  return annotations;
}

async function fetchFallbackLog(
  installationId: number,
  owner: string,
  repo: string,
  runId: number,
): Promise<FallbackLog | null> {
  try {
    const jobsData = await githubApiGet<JobsResponse>(
      installationId,
      `/repos/${owner}/${repo}/actions/runs/${runId}/jobs`,
    );

    // Find the first failed job
    const failedJob = jobsData.jobs.find((j) => j.conclusion === "failure");
    if (!failedJob) return null;

    // Find the first failed step
    const failedStep = failedJob.steps.find((s) => s.conclusion === "failure");
    if (!failedStep) return null;

    // Fetch job log (plain text) via the centralized wrapper
    const fullLog = await githubApiGetText(
      installationId,
      `/repos/${owner}/${repo}/actions/jobs/${failedJob.id}/logs`,
    );
    // Return last 100 lines
    const lines = fullLog.split("\n").slice(-100).join("\n");

    return {
      jobName: failedJob.name,
      stepName: failedStep.name,
      lines,
    };
  } catch (err) {
    log.warn({ err, runId }, "Failed to fetch fallback logs");
    return null;
  }
}
