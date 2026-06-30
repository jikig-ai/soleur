// Agent MCP tool for the Workstream board — agent-user READ parity (so an agent
// can see the same issues the user sees). `workstream_issues_list` is read-only
// (auto-approve) and calls the SAME shared getWorkstreamIssues() accessor the
// dashboard route uses (no duplicated query). Mirrors server/routines-tools.ts.
//
// WRITE tools (create / set_status) are deferred + tracked — see the plan's
// Deferred Work. The output INCLUDES the `user` field (Addendum item 5 read
// parity).

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { getWorkstreamIssues } from "@/server/workstream/get-workstream-issues";

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

export function buildWorkstreamTools(opts: BuildWorkstreamToolsOpts) {
  // The read IS user-scoped: it resolves the operator's active-workspace
  // connected repo + installation token (ADR-044) — thread userId through.
  const { userId } = opts;

  return {
    toolNames: ["mcp__soleur_platform__workstream_issues_list"],
    tools: [
      tool(
        "workstream_issues_list",
        "List the Workstream board issues (the kanban the user sees) for the " +
          "active workspace's connected GitHub repo. Returns { issues: [...] }; " +
          "each entry carries: id (the repo issue number as a string, e.g. " +
          "'5652'), title, description, status (backlog|todo|in_progress|" +
          "in_review|blocked|done|cancelled), priority (urgent|high|medium|low|" +
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
    ],
  };
}
