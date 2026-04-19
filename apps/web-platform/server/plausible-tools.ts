// In-process MCP tool definitions for Plausible Analytics (create site,
// add goal, get stats). Factored out of agent-runner.ts following the
// github-tools.ts / kb-share-tools.ts precedent.
//
// Registration guard (plausibleKey != null) stays at the call site —
// do NOT nest this inside the GitHub installation block. Per learning
// `service-tool-registration-scope-guard-20260410.md`, conflating
// Plausible's "stored PLAUSIBLE_API_KEY" prerequisite with GitHub's
// "App installation + connected repo" prerequisite silently hides
// Plausible tools from users without a GitHub installation.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import {
  plausibleCreateSite,
  plausibleAddGoal,
  plausibleGetStats,
} from "./service-tools";

interface BuildPlausibleToolsOpts {
  plausibleKey: string;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- SDK uses any for heterogeneous tool arrays
type PlausibleTool = ReturnType<typeof tool<any>>;

export interface BuildPlausibleToolsResult {
  tools: PlausibleTool[];
  toolNames: string[];
}

function wrapResult(result: {
  success: boolean;
  data?: unknown;
  error?: string;
}): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(result) }],
  };
  if (!result.success) body.isError = true;
  return body;
}

export function buildPlausibleTools(opts: BuildPlausibleToolsOpts): BuildPlausibleToolsResult {
  const { plausibleKey } = opts;

  const createSite = tool(
    "plausible_create_site",
    "Create a new site in Plausible Analytics. Returns the created site metadata.",
    {
      domain: z.string().describe("Domain name for the site (e.g., example.com)"),
      timezone: z.string().default("UTC").describe("Timezone for the site"),
    },
    async (args) => wrapResult(await plausibleCreateSite(plausibleKey, args.domain, args.timezone)),
  );

  const addGoal = tool(
    "plausible_add_goal",
    "Add a conversion goal to a Plausible Analytics site. Uses PUT with upsert semantics (safely idempotent).",
    {
      site_id: z.string().describe("Domain of the site (e.g., example.com)"),
      goal_type: z.enum(["event", "page"]).describe("Type of goal"),
      value: z.string().describe("Event name (for event goals) or page path (for page goals)"),
    },
    async (args) => wrapResult(await plausibleAddGoal(plausibleKey, args.site_id, args.goal_type, args.value)),
  );

  const getStats = tool(
    "plausible_get_stats",
    "Get aggregate stats for a Plausible Analytics site. Returns visitors, pageviews, bounce rate, and visit duration.",
    {
      site_id: z.string().describe("Domain of the site (e.g., example.com)"),
      period: z.enum(["day", "7d", "30d"]).default("30d").describe("Time period for stats"),
    },
    async (args) => wrapResult(await plausibleGetStats(plausibleKey, args.site_id, args.period)),
  );

  return {
    tools: [createSite, addGoal, getStats],
    toolNames: [
      "mcp__soleur_platform__plausible_create_site",
      "mcp__soleur_platform__plausible_add_goal",
      "mcp__soleur_platform__plausible_get_stats",
    ],
  };
}
