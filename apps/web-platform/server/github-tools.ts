// In-process MCP tool definitions for the GitHub App family (PR creation,
// CI status reads, workflow log reads, workflow triggers, branch pushes).
// Factored out of agent-runner.ts following the kb-share-tools.ts /
// conversations-tools.ts precedent so each tool's wiring has a single call
// site and unit tests can exercise the handlers in isolation.
//
// The handlers delegate the full implementation to
// github-app/ci-tools/trigger-workflow/push-branch — this module only
// glues SDK `tool()` calls to those delegates and stringifies results.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { createPullRequest } from "./github-app";
import { readCiStatus, readWorkflowLogs } from "./ci-tools";
import {
  readIssue,
  readIssueComments,
  readPullRequest,
  listPullRequestComments,
} from "./github-read-tools";
import { triggerWorkflow, type createRateLimiter } from "./trigger-workflow";
import { pushBranch } from "./push-branch";
import { validateBranchFormat } from "./branch-validation";

interface BuildGithubToolsOpts {
  installationId: number;
  owner: string;
  repo: string;
  defaultBranch: string;
  workspacePath: string;
  workflowRateLimiter: ReturnType<typeof createRateLimiter>;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- SDK uses any for heterogeneous tool arrays
type GithubTool = ReturnType<typeof tool<any>>;

export interface BuildGithubToolsResult {
  tools: GithubTool[];
  toolNames: string[];
}

export function buildGithubTools(opts: BuildGithubToolsOpts): BuildGithubToolsResult {
  const { installationId, owner, repo, defaultBranch, workspacePath, workflowRateLimiter } = opts;

  const createPr = tool(
    "create_pull_request",
    "Create a pull request on the user's connected GitHub repository. " +
      "The repository is determined server-side from the user's connected repo. " +
      "The head branch must already exist on the remote (push first via git).",
    {
      head: z.string().describe("Branch name containing changes (just the name, not owner:branch)"),
      base: z.string().default("main").describe("Target branch to merge into"),
      title: z.string().describe("PR title"),
      body: z.string().optional().describe("PR description body (markdown)"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        validateBranchFormat(args.head);
        validateBranchFormat(args.base);
        if (args.head === args.base) {
          return {
            content: [{ type: "text", text: "Error creating PR: Head branch and base branch cannot be the same" }],
            isError: true,
          };
        }
        const result = await createPullRequest(
          installationId, owner, repo,
          args.head, args.base, args.title, args.body,
        );
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error creating PR: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const readCi = tool(
    "github_read_ci_status",
    "Read recent CI workflow run statuses for the connected repository. " +
      "Returns status (pass/fail/in-progress), commit SHA, branch, run URL, " +
      "and workflow name/ID. Optionally filter by branch.",
    {
      branch: z.string().optional().describe("Filter runs by branch name"),
      per_page: z.number().default(10).describe("Number of runs to return (max 30)"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const runs = await readCiStatus(
          installationId, owner, repo,
          { branch: args.branch, per_page: Math.min(args.per_page, 30) },
        );
        return { content: [{ type: "text", text: JSON.stringify(runs, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading CI status: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const readLogs = tool(
    "github_read_workflow_logs",
    "Read failure details for a specific workflow run. Returns check annotations " +
      "(structured failure data) when available, otherwise falls back to the last " +
      "100 lines of the first failed step. Use github_read_ci_status first to find run IDs.",
    {
      run_id: z.number().describe("The workflow run ID to inspect"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await readWorkflowLogs(
          installationId, owner, repo, args.run_id,
        );
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading workflow logs: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const triggerWf = tool(
    "github_trigger_workflow",
    "Trigger a workflow_dispatch event on the connected repository. " +
      "Requires founder approval via review gate. Rate limited to 10 triggers per session. " +
      "Use github_read_ci_status first to find workflow IDs.",
    {
      workflow_id: z.number().describe("The workflow ID to trigger (from github_read_ci_status)"),
      ref: z.string().describe("Git ref to run the workflow on (branch name or tag)"),
      inputs: z.record(z.string(), z.string()).optional().describe("Optional workflow_dispatch inputs"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await triggerWorkflow(
          installationId, owner, repo,
          args.workflow_id, args.ref, workflowRateLimiter, args.inputs,
        );
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error triggering workflow: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const pushBr = tool(
    "github_push_branch",
    "Push the current workspace HEAD to a feature branch on the remote. " +
      "Requires founder approval via review gate. Force-push and push to " +
      "main/master are blocked unconditionally.",
    {
      branch: z.string().describe("Target branch name (must not be main, master, or default branch)"),
      force: z.boolean().default(false).describe("Force-push (always rejected — included for explicit error messaging)"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await pushBranch({
          installationId,
          owner,
          repo,
          workspacePath,
          branch: args.branch,
          force: args.force,
          defaultBranch,
        });
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error pushing branch: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Read-only issue/PR tools (#2843). Matching pattern: readCi/readLogs —
  // auto-approve, JSON-stringified narrowed output, isError on exception.
  // Response narrowing + body truncation lives in github-read-tools.ts.
  // ---------------------------------------------------------------------------

  const readIssueTool = tool(
    "github_read_issue",
    "Read a single issue from the connected repository by number. " +
      "Returns number, title, state, body (truncated at 10 KB), labels, " +
      "assignees, milestone title, timestamps, author login, and html_url.",
    {
      issue_number: z.number().describe("The issue number to read"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await readIssue(installationId, owner, repo, args.issue_number);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading issue: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const readIssueCommentsTool = tool(
    "github_read_issue_comments",
    "Read conversation comments on an issue. Returns id, author login, " +
      "body (truncated at 4 KB), created_at, and html_url. Results are " +
      "tagged kind=\"conversation\" for symmetry with github_list_pr_comments.",
    {
      issue_number: z.number().describe("The issue number to read comments from"),
      per_page: z.number().default(10).describe("Number of comments to return (max 50)"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await readIssueComments(
          installationId, owner, repo, args.issue_number, { per_page: args.per_page },
        );
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading issue comments: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const readPrTool = tool(
    "github_read_pr",
    "Read a pull request from the connected repository by number. Returns " +
      "the issue fields plus PR-specific review state: draft, merged, " +
      "mergeable, mergeable_state, head_ref, base_ref, merged_at. Use this " +
      "to decide whether a PR needs another push or is already merged.",
    {
      pull_number: z.number().describe("The pull request number to read"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await readPullRequest(installationId, owner, repo, args.pull_number);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading PR: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  const listPrCommentsTool = tool(
    "github_list_pr_comments",
    "List both review comments (line-specific) and conversation comments on " +
      "a pull request. Each entry is tagged kind=\"review\" or " +
      "kind=\"conversation\" so you can filter. Review comments come from " +
      "/pulls/:n/comments; conversation comments from /issues/:n/comments.",
    {
      pull_number: z.number().describe("The pull request number to list comments for"),
      per_page: z.number().default(10).describe("Number of comments per kind to return (max 50)"),
    },
    async (args): Promise<ToolTextResponse> => {
      try {
        const result = await listPullRequestComments(
          installationId, owner, repo, args.pull_number, { per_page: args.per_page },
        );
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error listing PR comments: ${(err as Error).message}` }],
          isError: true,
        };
      }
    },
  );

  return {
    tools: [
      createPr, readCi, readLogs, triggerWf, pushBr,
      readIssueTool, readIssueCommentsTool, readPrTool, listPrCommentsTool,
    ],
    toolNames: [
      "mcp__soleur_platform__create_pull_request",
      "mcp__soleur_platform__github_read_ci_status",
      "mcp__soleur_platform__github_read_workflow_logs",
      "mcp__soleur_platform__github_trigger_workflow",
      "mcp__soleur_platform__github_push_branch",
      "mcp__soleur_platform__github_read_issue",
      "mcp__soleur_platform__github_read_issue_comments",
      "mcp__soleur_platform__github_read_pr",
      "mcp__soleur_platform__github_list_pr_comments",
    ],
  };
}
