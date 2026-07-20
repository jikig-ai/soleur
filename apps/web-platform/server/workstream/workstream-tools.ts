// Agent MCP tools for the Workstream board — agent-user READ + WRITE parity
// (#5677, ADR-109). Read tools `workstream_issues_list` + `workstream_issue_options`
// are auto-approve; the WRITE tools (create / set_status / update_title / close /
// update_fields) are `gated` (tool-tiers.ts) — the host review gate is the
// founder-confirmation surface. ALL of them call the SAME shared accessors the
// HTTP routes use (getWorkstreamIssues / getWorkstreamIssueOptions /
// mutateWorkstreamIssue helpers) — no duplicated query, no `gh` shell-out.
// owner/repo/installation + initiatorLogin resolve server-side from the
// operator's active workspace (never tool input).

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { getWorkstreamIssues } from "@/server/workstream/get-workstream-issues";
import { getWorkstreamIssueOptions } from "@/server/workstream/get-workstream-issue-options";
import {
  createWorkstreamIssue,
  reopenWorkstreamIssue,
  setWorkstreamIssueStatus,
  updateWorkstreamIssueFields,
  updateWorkstreamIssueTitle,
} from "@/server/workstream/mutate-workstream-issue";

interface BuildWorkstreamToolsOpts {
  /** The operator the agent acts for (parity with the routines builder). */
  userId: string;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown, isError = false): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
  if (isError) body.isError = true;
  return body;
}

/** Shared fail-loud wrapper: a write that throws returns isError with a stable
 *  code (never a silent success), mirroring the route's 502 posture. */
async function writeResult(
  fn: () => Promise<unknown>,
): Promise<ToolTextResponse> {
  try {
    const issue = await fn();
    return textResponse({ issue });
  } catch (err) {
    return textResponse(
      {
        error: "workstream_write_error",
        message: err instanceof Error ? err.message : "unknown",
      },
      true,
    );
  }
}

// The 7 board columns as an agent-facing status enum (mirrors WorkstreamStatus).
const STATUS_ENUM = z.enum([
  "backlog",
  "ready",
  "in_progress",
  "in_review",
  "blocked",
  "pending",
  "done",
]);

const CLOSE_REASON_ENUM = z.enum(["completed", "not_planned"]);

export function buildWorkstreamTools(opts: BuildWorkstreamToolsOpts) {
  // The reads AND writes are user-scoped: they resolve the operator's active-
  // workspace connected repo + installation token (ADR-044) — thread userId.
  const { userId } = opts;

  return {
    toolNames: [
      "mcp__soleur_platform__workstream_issues_list",
      "mcp__soleur_platform__workstream_issue_options",
      "mcp__soleur_platform__workstream_issue_create",
      "mcp__soleur_platform__workstream_issue_set_status",
      "mcp__soleur_platform__workstream_issue_update_title",
      "mcp__soleur_platform__workstream_issue_update_fields",
      "mcp__soleur_platform__workstream_issue_close",
    ],
    tools: [
      tool(
        "workstream_issues_list",
        "List the Workstream board issues (the kanban the user sees) for the " +
          "active workspace's connected GitHub repo. Returns { issues: [...] }; " +
          "each entry carries: id (the repo issue number as a string, e.g. " +
          "'5652'), title, description, status (backlog|ready|in_progress|" +
          "in_review|blocked|pending|done), priority (urgent|high|medium|low|" +
          "none), assigneeRole (a leader role id like 'cto'/'coo', or null), an " +
          "optional `user` (the first assignee: { name, initials }), an optional " +
          "`live` flag, and createdAt/updatedAt. Empty when no repo is " +
          "connected. Read-only.",
        {},
        async () => {
          try {
            const issues = await getWorkstreamIssues(userId);
            return textResponse({ issues });
          } catch (err) {
            return textResponse(
              {
                error: "workstream_query_error",
                message: err instanceof Error ? err.message : "unknown",
              },
              true,
            );
          }
        },
      ),
      tool(
        "workstream_issue_options",
        "List the valid EDIT options for the active workspace's connected repo so " +
          "you can pick real values before an update: returns { labels: [{name," +
          "color}] (NON-status labels only — status is owned by set_status), " +
          "assignees: [{login}], milestones: [{number,title}] }. Degrade-safe " +
          "(empty arrays when no repo/grant). Read-only.",
        {},
        async () => {
          try {
            const options = await getWorkstreamIssueOptions(userId);
            return textResponse(options);
          } catch (err) {
            return textResponse(
              {
                error: "workstream_options_error",
                message: err instanceof Error ? err.message : "unknown",
              },
              true,
            );
          }
        },
      ),
      tool(
        "workstream_issue_create",
        "Create a REAL GitHub issue on the active workspace's connected repo. " +
          "`title` is required; `body` optional; `status` optionally seeds the " +
          "column (defaults Backlog). owner/repo + the creator attribution are " +
          "resolved server-side (never accepted as input). Returns { issue } — " +
          "the created issue with its real number. Gated (founder approval).",
        {
          title: z.string().describe("Issue title (required, non-empty)."),
          body: z.string().optional().describe("Optional issue body/description."),
          status: STATUS_ENUM.optional().describe(
            "Optional seed column (defaults backlog).",
          ),
        },
        async (input) =>
          writeResult(() =>
            createWorkstreamIssue(userId, {
              title: input.title,
              ...(input.body !== undefined ? { body: input.body } : {}),
              ...(input.status !== undefined ? { status: input.status } : {}),
            }),
          ),
      ),
      tool(
        "workstream_issue_set_status",
        "Move an issue to a board column by number. Persists via the issue's " +
          "labels (atomic); `done` closes the issue (optional `state_reason` " +
          "completed|not_planned). A non-terminal column on a closed issue " +
          "reopens it. Returns the canonical resulting { issue }. Gated.",
        {
          number: z.number().int().positive().describe("The issue number."),
          status: STATUS_ENUM.describe("Target board column."),
          state_reason: CLOSE_REASON_ENUM.optional().describe(
            "When status=done: completed (default) or not_planned.",
          ),
        },
        async (input) =>
          writeResult(() =>
            setWorkstreamIssueStatus(
              userId,
              input.number,
              input.status,
              input.state_reason,
            ),
          ),
      ),
      tool(
        "workstream_issue_update_title",
        "Edit an issue's title by number. Returns the canonical { issue }. Gated.",
        {
          number: z.number().int().positive().describe("The issue number."),
          title: z.string().describe("New title (required, non-empty)."),
        },
        async (input) =>
          writeResult(() =>
            updateWorkstreamIssueTitle(userId, input.number, input.title),
          ),
      ),
      tool(
        "workstream_issue_update_fields",
        "Edit an issue's body, assignees, milestone, and/or NON-status labels by " +
          "number (any combination in one call — only provided fields change). " +
          "`labels` sets the non-status label set (status stays owned by " +
          "set_status; call workstream_issue_options for valid names). `milestone` " +
          "is a milestone NUMBER or null to clear. A body edit preserves the " +
          "original initiator attribution. Returns the canonical { issue }. Gated.",
        {
          number: z.number().int().positive().describe("The issue number."),
          body: z
            .string()
            .optional()
            .describe("New issue body/description (empty string allowed)."),
          labels: z
            .array(z.string())
            .optional()
            .describe("Desired NON-status labels (replaces the non-status set)."),
          assignees: z
            .array(z.string())
            .optional()
            .describe("Assignee logins (replaces the assignee set)."),
          milestone: z
            .number()
            .int()
            .positive()
            .nullable()
            .optional()
            .describe("Milestone number, or null to clear."),
        },
        async (input) => {
          const fields: Parameters<typeof updateWorkstreamIssueFields>[2] = {};
          if (input.body !== undefined) fields.body = input.body;
          if (input.labels !== undefined) fields.labels = input.labels;
          if (input.assignees !== undefined) fields.assignees = input.assignees;
          if (input.milestone !== undefined) fields.milestone = input.milestone;
          return writeResult(() =>
            updateWorkstreamIssueFields(userId, input.number, fields),
          );
        },
      ),
      tool(
        "workstream_issue_close",
        "Close an issue (`reason` completed|not_planned — both land it in Done; " +
          "there is no Cancelled column) OR reopen it (`reopen: true` → the card " +
          "leaves Done and lands where its surviving labels derive). Returns the " +
          "canonical { issue }. Gated.",
        {
          number: z.number().int().positive().describe("The issue number."),
          reason: CLOSE_REASON_ENUM.optional().describe(
            "Close reason (default completed). Ignored when reopen=true.",
          ),
          reopen: z
            .boolean()
            .optional()
            .describe("Reopen the issue instead of closing it."),
        },
        async (input) =>
          writeResult(() =>
            input.reopen
              ? reopenWorkstreamIssue(userId, input.number)
              : setWorkstreamIssueStatus(
                  userId,
                  input.number,
                  "done",
                  input.reason,
                ),
          ),
      ),
    ],
  };
}
