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

// #5388: the soleur_platform FQN of the flag+repo-gated edit_c4_diagram tool.
// Colocated with the bare tool name (mirroring narrate-tool.ts's
// NARRATE_TOOL/NARRATE_TOOL_FQN pairing). SINGLE source of truth for the FQN —
// consumed by realSdkQueryFactory (sets c4ToolName when it builds the tool),
// the per-dispatch registeredPlatformToolNames resolve (advertises it to the
// unregistered-tool mirror predicate), and pinned by
// test/cc-mcp-tier-allowlist.test.ts against drift.
export const C4_TOOL_FQN = `mcp__soleur_platform__${EDIT_C4_DIAGRAM_TOOL}`;

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
        "file contents (not a patch). Commits the source directly to the repo " +
        "and then re-renders the diagram. The response includes `rerendered`: " +
        "when true, the rendered diagram has been regenerated and updated — tell " +
        "the user it updated; when false, the source was saved but the re-render " +
        "failed, so the diagram is unchanged. On failure the response may include " +
        "`rerenderDiagnostic` explaining WHY (e.g. an unresolved reference because " +
        "`spec.c4` is missing) — relay that reason to the user so they can fix the " +
        "source. Do not paste DSL into chat for the user to apply.",
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
          rerendered: result.rerendered,
          ...(result.rerenderDiagnostic
            ? { rerenderDiagnostic: result.rerenderDiagnostic }
            : {}),
        });
      },
    ),
  ];
}
