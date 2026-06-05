// In-process MCP tool that lets the Soleur Concierge edit a canonical LikeC4
// diagram source. This is the Concierge's ONLY sanctioned repo-write capability
// — generic Edit/Write stay hard-blocked (cc-dispatcher CC_PATH_DISALLOWED_TOOLS).
//
// SECURITY: owner/repo/installationId/workspacePath/userId are closed over at
// registration (resolved per-user from the active workspace, ADR-044) — they are
// NEVER tool inputs, so the agent cannot redirect the commit to another repo.
// The model controls only `relativePath` + `content`; `writeC4Diagram` enforces
// the diagrams-dir scope guard (`isC4DiagramPath`) as the hard boundary.
import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
// NOTE: `@/server/c4-writer` is imported dynamically inside the handler (not at
// module top) so its `import "server-only"` guard stays out of the static graph
// of cc-dispatcher — otherwise every test that loads the real dispatcher would
// fail to resolve `server-only` under vitest. The handler runs only at real
// tool invocation, where server-only is inert.

export const EDIT_C4_DIAGRAM_TOOL = "edit_c4_diagram";

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

export interface BuildC4ConciergeToolsOpts {
  userId: string;
  installationId: number;
  owner: string;
  repo: string;
  workspacePath: string;
}

/**
 * Build the `edit_c4_diagram` tool bound to a fixed (userId, repo, workspace).
 * Returns an array so the caller can spread it into `createSdkMcpServer`.
 */
export function buildC4ConciergeTools(opts: BuildC4ConciergeToolsOpts) {
  const { userId, installationId, owner, repo, workspacePath } = opts;
  return [
    tool(
      EDIT_C4_DIAGRAM_TOOL,
      "Edit a canonical LikeC4 architecture diagram source and commit it. " +
        "`relativePath` must be a `.c4` (or the `.md` view-embed page) directly " +
        "under `engineering/architecture/diagrams/`. `content` is the FULL new " +
        "file contents (not a patch). Commits the source directly to the repo; " +
        "the rendered diagram is precomputed and does NOT re-render at runtime — " +
        "it refreshes only after the model is re-rendered out-of-band (via " +
        "`/soleur:architecture render`), which you cannot trigger. Do not paste " +
        "DSL into chat for the user to apply, and do not claim the diagram has " +
        "already updated — tell the user the source was saved and the diagram " +
        "refreshes after the next re-render.",
      {
        relativePath: z
          .string()
          .describe(
            "KB-relative path under engineering/architecture/diagrams/, e.g. 'engineering/architecture/diagrams/model.c4'",
          ),
        content: z.string().describe("Full new file contents (UTF-8)."),
      },
      async (args: { relativePath: string; content: string }) => {
        const { writeC4Diagram } = await import("@/server/c4-writer");
        const result = await writeC4Diagram({
          userId,
          installationId,
          owner,
          repo,
          workspacePath,
          relativePath: args.relativePath,
          content: args.content,
        });
        if (!result.ok) {
          return textResponse(
            { error: result.error, code: result.code, status: result.status },
            true,
          );
        }
        return textResponse({
          ok: true,
          relativePath: args.relativePath,
          commitSha: result.commitSha,
        });
      },
    ),
  ];
}
