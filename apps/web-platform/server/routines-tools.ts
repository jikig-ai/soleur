// Agent MCP tools for routines (#5345 PR-1) — agent-user parity for the
// Routines surface. routines_list + routine_runs_list are read-only
// (auto-approve); routine_run is a write (gated — the host review-gate is the
// single confirmation, so the tool dispatches with confirmed=true and never
// double-gates via the in-band 409). All three call the SAME shared server fns
// the dashboard routes use (no duplicated query).

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { getServiceClient } from "@/lib/supabase/service";
import {
  listRecentRuns,
  listRoutinesWithLastRun,
} from "@/server/routines/list-routines";
import { runRoutine } from "@/server/routines/run-routine";

interface BuildRoutineToolsOpts {
  /** The operator the agent acts for — recorded as delegating_principal. */
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

export function buildRoutineTools(opts: BuildRoutineToolsOpts) {
  const { userId } = opts;

  return {
    toolNames: [
      "mcp__soleur_platform__routines_list",
      "mcp__soleur_platform__routine_runs_list",
      "mcp__soleur_platform__routine_run",
    ],
    tools: [
      tool(
        "routines_list",
        "List all Inngest routines (scheduled crons). Returns a flat array; " +
          "each entry carries domain (for grouping), ownerRole, a human-" +
          "readable schedule, the manualTrigger policy (allowed|confirm), and " +
          "the latest run summary (status, timestamps, duration). Read-only.",
        {},
        async () => {
          try {
            const routines = await listRoutinesWithLastRun(
              getServiceClient() as never,
            );
            return textResponse({ routines });
          } catch (err) {
            return textResponse(
              { error: "routines_query_error", message: err instanceof Error ? err.message : "unknown" },
              true,
            );
          }
        },
      ),
      tool(
        "routine_runs_list",
        "List recent routine executions (reverse-chronological) across all " +
          "routines: routine id, run id, status, trigger source + actor class " +
          "(system/human/agent), timestamps, duration. Keyset-paginated via " +
          "`cursor`. Read-only.",
        {
          cursor: z
            .string()
            .optional()
            .describe("Opaque pagination cursor from a prior page's nextCursor"),
          limit: z
            .number()
            .optional()
            .describe("Page size (1-200, default 50)"),
        },
        async (input) => {
          try {
            const page = await listRecentRuns(getServiceClient() as never, {
              cursor: input.cursor ?? null,
              limit: input.limit,
            });
            return textResponse(page);
          } catch (err) {
            return textResponse(
              { error: "runs_query_error", message: err instanceof Error ? err.message : "unknown" },
              true,
            );
          }
        },
      ),
      tool(
        "routine_run",
        "Trigger a routine to run now, off-schedule (debug mode). `fnId` must be " +
          "an EXPECTED_CRON_FUNCTIONS id (event-driven functions are rejected). " +
          "Gated: requires operator approval via the review gate — that approval " +
          "IS the confirmation for protected (financial/egress/deletion) " +
          "routines. Returns the dispatched event name. Error codes: " +
          "400 unknown_routine.",
        {
          fnId: z.string().describe("Routine id, e.g. 'cron-daily-triage'"),
        },
        async (input) => {
          try {
            const result = await runRoutine({
              fnId: input.fnId,
              actorClass: "agent",
              actorId: null,
              delegatingPrincipal: userId,
              // The gated review-gate is the single confirmation — no double-gate.
              confirmed: true,
              feature: "routine-run-agent",
            });
            if (!result.ok) {
              return textResponse({ error: result.code }, true);
            }
            return textResponse({ dispatched: result.event });
          } catch (err) {
            return textResponse(
              { error: "dispatch_failed", message: err instanceof Error ? err.message : "unknown" },
              true,
            );
          }
        },
      ),
    ],
  };
}
