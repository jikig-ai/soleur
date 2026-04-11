import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import path from "path";
import { z } from "zod/v4";

import { createServiceClient } from "@/lib/supabase/service";
import { ROUTABLE_DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { routeMessage } from "./domain-router";
import { KeyInvalidError, type AttachmentRef } from "@/lib/types";
import { decryptKey, decryptKeyLegacy, encryptKey } from "./byok";
import { sendToClient } from "./ws-handler";
import * as Sentry from "@sentry/nextjs";
import { sanitizeErrorForClient } from "./error-sanitizer";
import { isPathInWorkspace } from "./sandbox";
import { UNVERIFIED_PARAM_TOOLS, extractToolPath, isFileTool, isSafeTool } from "./tool-path-checker";
import { buildAgentEnv } from "./agent-env";
import { PROVIDER_CONFIG, EXCLUDED_FROM_SERVICES_UI } from "./providers";
import type { Provider } from "@/lib/types";
import { createSandboxHook } from "./sandbox-hook";
import { abortableReviewGate, validateSelection, extractReviewGateInput, buildReviewGateResponse, type AgentSession } from "./review-gate";
import { createChildLogger } from "./logger";
import { syncPull, syncPush } from "./session-sync";
import { createPullRequest } from "./github-app";
import { plausibleCreateSite, plausibleAddGoal, plausibleGetStats } from "./service-tools";
import { tryCreateVision, buildVisionEnhancementPrompt } from "./vision-helpers";
import { getToolTier, buildGateMessage } from "./tool-tiers";
import { readCiStatus, readWorkflowLogs } from "./ci-tools";
import { triggerWorkflow, createRateLimiter } from "./trigger-workflow";
import { pushBranch } from "./push-branch";
import { githubApiGet } from "./github-api";

const log = createChildLogger("agent");

let _supabase: ReturnType<typeof createServiceClient>;
function supabase() { return _supabase ??= createServiceClient(); }

const PLUGIN_PATH =
  process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";

// ---------------------------------------------------------------------------
// Workspace permissions migration (#725)
// Defense-in-depth layer 2: settingSources: [] (layer 1) prevents the SDK
// from loading settings files. This migration cleans stale pre-approvals
// from disk -- relevant if settingSources is ever changed to ["project"]
// for CLAUDE.md support.
// ---------------------------------------------------------------------------
const FILE_TOOLS_TO_REMOVE = new Set(["Read", "Glob", "Grep"]);

function patchWorkspacePermissions(workspacePath: string): void {
  const settingsPath = path.join(workspacePath, ".claude", "settings.json");
  try {
    const raw = readFileSync(settingsPath, "utf8");
    const settings = JSON.parse(raw);
    const allow: string[] = settings?.permissions?.allow;
    if (!Array.isArray(allow) || allow.length === 0) return;
    const filtered = allow.filter((t: string) => !FILE_TOOLS_TO_REMOVE.has(t));
    if (filtered.length === allow.length) return;
    settings.permissions.allow = filtered;
    writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  } catch {
    // Settings file missing or malformed — workspace.ts will recreate on next provision
  }
}

// ---------------------------------------------------------------------------
// Active session tracking
// ---------------------------------------------------------------------------
const activeSessions = new Map<string, AgentSession>();

function sessionKey(userId: string, conversationId: string, leaderId?: string) {
  return leaderId
    ? `${userId}:${conversationId}:${leaderId}`
    : `${userId}:${conversationId}`;
}

/** Abort a running agent session (called from ws-handler on disconnect or supersession).
 *  When leaderId is provided, only that leader's session is aborted.
 *  When omitted, ALL leader sessions for the conversation are aborted (prefix match). */
export function abortSession(
  userId: string,
  conversationId: string,
  reason?: "disconnected" | "superseded",
  leaderId?: string,
): void {
  if (leaderId) {
    const key = sessionKey(userId, conversationId, leaderId);
    const session = activeSessions.get(key);
    if (session) {
      session.abort.abort(new Error(`Session aborted: ${reason ?? "disconnected"}`));
    }
    return;
  }

  // Broadcast: abort ALL sessions for this conversation (any leader)
  const prefix = `${userId}:${conversationId}`;
  for (const [key, session] of activeSessions) {
    if (key === prefix || key.startsWith(`${prefix}:`)) {
      session.abort.abort(new Error(`Session aborted: ${reason ?? "disconnected"}`));
    }
  }
}

/** Abort ALL sessions for a user (called during account deletion). */
export function abortAllUserSessions(userId: string): void {
  const prefix = `${userId}:`;
  for (const [key, session] of activeSessions) {
    if (key.startsWith(prefix)) {
      session.abort.abort(new Error("Session aborted: account_deleted"));
    }
  }
}

/** Abort ALL active sessions (called during server shutdown).
 *  Triggers the catch block in startAgentSession which updates
 *  conversation status to "failed" in the database. */
export function abortAllSessions(): void {
  for (const [, session] of activeSessions) {
    session.abort.abort(new Error("Session aborted: server_shutdown"));
  }
}

// ---------------------------------------------------------------------------
// BYOK key retrieval
// ---------------------------------------------------------------------------
async function getUserApiKey(userId: string): Promise<string> {
  const { data, error } = await supabase()
    .from("api_keys")
    .select("id, encrypted_key, iv, auth_tag, key_version")
    .eq("user_id", userId)
    .eq("is_valid", true)
    .eq("provider", "anthropic")
    .limit(1)
    .single();

  if (error || !data) {
    throw new KeyInvalidError();
  }

  const encrypted = Buffer.from(data.encrypted_key, "base64");
  const iv = Buffer.from(data.iv, "base64");
  const authTag = Buffer.from(data.auth_tag, "base64");

  if (data.key_version === 1) {
    // Lazy migration: decrypt with raw key, re-encrypt with HKDF-derived key
    const plaintext = decryptKeyLegacy(encrypted, iv, authTag);
    const reEncrypted = encryptKey(plaintext, userId);
    await supabase()
      .from("api_keys")
      .update({
        encrypted_key: reEncrypted.encrypted.toString("base64"),
        iv: reEncrypted.iv.toString("base64"),
        auth_tag: reEncrypted.tag.toString("base64"),
        key_version: 2,
        updated_at: new Date().toISOString(),
      })
      .eq("id", data.id);
    return plaintext;
  }

  return decryptKey(encrypted, iv, authTag, userId);
}

// ---------------------------------------------------------------------------
// Third-party service token retrieval
// ---------------------------------------------------------------------------
async function getUserServiceTokens(
  userId: string,
): Promise<Record<string, string>> {
  const { data, error } = await supabase()
    .from("api_keys")
    .select("provider, encrypted_key, iv, auth_tag, key_version")
    .eq("user_id", userId)
    .eq("is_valid", true);

  if (error || !data) return {};

  const tokens: Record<string, string> = {};

  for (const row of data) {
    // Skip LLM providers (handled by getUserApiKey) and excluded providers
    if (row.provider === "anthropic") continue;
    if (EXCLUDED_FROM_SERVICES_UI.has(row.provider as Provider)) continue;

    const config = PROVIDER_CONFIG[row.provider as Provider];
    if (!config) continue;

    try {
      const encrypted = Buffer.from(row.encrypted_key, "base64");
      const iv = Buffer.from(row.iv, "base64");
      const authTag = Buffer.from(row.auth_tag, "base64");

      let plaintext: string;
      if (row.key_version === 1) {
        plaintext = decryptKeyLegacy(encrypted, iv, authTag);
        // Lazy migration to v2
        const reEncrypted = encryptKey(plaintext, userId);
        await supabase()
          .from("api_keys")
          .update({
            encrypted_key: reEncrypted.encrypted.toString("base64"),
            iv: reEncrypted.iv.toString("base64"),
            auth_tag: reEncrypted.tag.toString("base64"),
            key_version: 2,
            updated_at: new Date().toISOString(),
          })
          .eq("user_id", userId)
          .eq("provider", row.provider);
      } else {
        plaintext = decryptKey(encrypted, iv, authTag, userId);
      }

      tokens[config.envVar] = plaintext;
    } catch (err) {
      log.error({ err, provider: row.provider }, "Failed to decrypt service token");
    }
  }

  return tokens;
}

// ---------------------------------------------------------------------------
// Message persistence
// ---------------------------------------------------------------------------
async function saveMessage(
  conversationId: string,
  role: "user" | "assistant",
  content: string,
  toolCalls?: unknown,
  leaderId?: string,
) {
  const { error } = await supabase().from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role,
    content,
    tool_calls: toolCalls || null,
    leader_id: leaderId ?? null,
  });

  if (error) {
    throw new Error(`Failed to save message: ${error.message}`);
  }
}

async function updateConversationStatus(
  conversationId: string,
  status: string,
) {
  const { error } = await supabase()
    .from("conversations")
    .update({ status, last_active: new Date().toISOString() })
    .eq("id", conversationId);

  if (error) {
    throw new Error(
      `Failed to update conversation status: ${error.message}`,
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation history for replay fallback
// ---------------------------------------------------------------------------
const MAX_REPLAY_MESSAGES = 20;

async function loadConversationHistory(
  conversationId: string,
): Promise<Array<{ role: string; content: string }>> {
  const { data, error } = await supabase()
    .from("messages")
    .select("role, content, created_at, message_attachments(filename, content_type, size_bytes)")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });

  if (error) {
    log.error({ err: error }, "Failed to load conversation history");
    return [];
  }

  // Augment user messages with attachment context for replay
  return (data ?? []).map((m) => {
    const atts = (m as Record<string, unknown>).message_attachments as
      | Array<{ filename: string; content_type: string; size_bytes: number }>
      | undefined;
    if (atts && atts.length > 0 && m.role === "user") {
      const attList = atts
        .map((a) => `- ${a.filename} (${a.content_type}, ${a.size_bytes} bytes)`)
        .join("\n");
      return { role: m.role, content: `${m.content}\n\n[Attached files:\n${attList}]` };
    }
    return { role: m.role, content: m.content };
  });
}

function buildReplayPrompt(
  history: Array<{ role: string; content: string }>,
  newMessage: string,
): string {
  // Keep only the last N messages to stay within context budget
  const recent = history.slice(-MAX_REPLAY_MESSAGES);

  if (recent.length === 0) return newMessage;

  const formatted = recent
    .map((m) => `[${m.role === "user" ? "User" : "Assistant"}]: ${m.content}`)
    .join("\n\n");

  return `Previous conversation:\n${formatted}\n\nNew message from user: ${newMessage}`;
}

// ---------------------------------------------------------------------------
// Orphaned conversation cleanup (runs on server startup)
// ---------------------------------------------------------------------------
export async function cleanupOrphanedConversations(): Promise<void> {
  const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1_000).toISOString();
  const { error } = await supabase()
    .from("conversations")
    .update({ status: "failed" })
    .in("status", ["active", "waiting_for_user"])
    .lt("last_active", fiveMinutesAgo);

  if (error) {
    log.error({ err: error }, "Failed to clean up orphaned conversations");
  }
}

// ---------------------------------------------------------------------------
// Inactivity timeout (runs as periodic background check)
// ---------------------------------------------------------------------------
const INACTIVITY_TIMEOUT_MS = 2 * 60 * 60 * 1_000; // 2 hours
const INACTIVITY_CHECK_INTERVAL_MS = 60 * 60 * 1_000; // Check every hour

export function startInactivityTimer(): void {
  const timer = setInterval(async () => {
    const cutoff = new Date(Date.now() - INACTIVITY_TIMEOUT_MS).toISOString();
    const { data, error } = await supabase()
      .from("conversations")
      .update({ status: "completed" })
      .in("status", ["waiting_for_user"])
      .lt("last_active", cutoff)
      .select("id, user_id");

    if (error) {
      log.error({ err: error }, "Inactivity cleanup error");
      return;
    }

    if (data && data.length > 0) {
      // Abort in-memory sessions for timed-out conversations
      for (const conv of data) {
        abortSession(conv.user_id, conv.id);
      }
      log.info({ count: data.length }, "Cleaned up inactive conversations");
    }
  }, INACTIVITY_CHECK_INTERVAL_MS);
  timer.unref();
}

// ---------------------------------------------------------------------------
// Start agent session
// ---------------------------------------------------------------------------
export async function startAgentSession(
  userId: string,
  conversationId: string,
  leaderId?: DomainLeaderId,
  resumeSessionId?: string,
  userMessage?: string,
  context?: import("@/lib/types").ConversationContext,
  routeSource?: "auto" | "mention",
): Promise<void> {
  const key = sessionKey(userId, conversationId, leaderId);

  // Abort any existing session for this specific leader (or un-keyed session)
  const existing = activeSessions.get(key);
  if (existing) existing.abort.abort();

  const controller = new AbortController();
  const session: AgentSession = {
    abort: controller,
    reviewGateResolvers: new Map(),
    sessionId: null,
  };
  activeSessions.set(key, session);

  try {
    // Get user's decrypted API key and service tokens
    const [apiKey, serviceTokens] = await Promise.all([
      getUserApiKey(userId),
      getUserServiceTokens(userId),
    ]);

    // Get leader config (default to CPO as general advisor if no leader specified)
    const effectiveLeaderId = leaderId ?? "cpo";
    const leader = ROUTABLE_DOMAIN_LEADERS.find((l) => l.id === effectiveLeaderId);
    if (!leader) throw new Error(`Unknown leader: ${effectiveLeaderId}`);

    // Get user workspace path, repo status, and GitHub App connection
    const { data: user } = await supabase()
      .from("users")
      .select("workspace_path, repo_status, github_installation_id, repo_url")
      .eq("id", userId)
      .single();

    if (!user?.workspace_path) {
      throw new Error("Workspace not provisioned");
    }

    const workspacePath = user.workspace_path;
    const pluginPath = path.join(workspacePath, "plugins", "soleur");

    // Extract MCP server names from plugin.json for canUseTool allowlisting.
    // Uses explicit server-name matching (not blanket mcp__ prefix).
    // See learning: 2026-04-06-mcp-tool-canusertool-scope-allowlist.md
    let pluginMcpServerNames: string[] = [];
    try {
      const pluginJsonPath = path.join(pluginPath, ".claude-plugin", "plugin.json");
      const pluginJson = JSON.parse(readFileSync(pluginJsonPath, "utf-8"));
      if (pluginJson.mcpServers && typeof pluginJson.mcpServers === "object") {
        pluginMcpServerNames = Object.keys(pluginJson.mcpServers);
      }
    } catch {
      // plugin.json may not exist in all workspaces; proceed without plugin MCP tools
    }

    // Migrate existing workspaces: remove pre-approved permissions that
    // bypass canUseTool (see #725). Safe to run on every session start —
    // no-op for already-migrated workspaces.
    patchWorkspacePermissions(workspacePath);

    // Sync: pull latest from remote before session (connected repos only)
    if (user.repo_status === "ready") {
      await syncPull(userId, workspacePath);
    }

    // Create vision.md on first message if it doesn't exist (fire-and-forget).
    // Runs in startAgentSession (not sendUserMessage) to reuse the already-fetched
    // workspacePath and avoid an extra DB query on every message.
    if (userMessage) {
      tryCreateVision(workspacePath, userMessage).catch((err) => {
        log.error({ err, userId }, "Failed to create initial vision.md");
      });
    }

    // Build system prompt for the domain leader
    let systemPrompt = `You are the ${leader.title} (${leader.name}) for this user's business. ${leader.description}

Use the tools available to you to read and write to the knowledge-base directory. The user's workspace is at ${workspacePath}.

When you need user input for important decisions, use the AskUserQuestion tool.`;

    // Inject artifact context when conversation started from a specific page
    if (context?.content) {
      systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nArtifact content:\n${context.content}\n\nAnswer in the context of this artifact.`;
    }

    // CPO-scoped: enhance minimal vision.md with structured sections
    if (effectiveLeaderId === "cpo") {
      const enhancement = await buildVisionEnhancementPrompt(workspacePath);
      if (enhancement) systemPrompt += enhancement;
    }

    // Inject connected services context for service automation tier selection.
    // The agent uses this to decide MCP vs API vs guided instructions.
    // Map env var names to human-readable labels to avoid leaking internals.
    if (Object.keys(serviceTokens).length > 0) {
      const envVarToLabel = Object.fromEntries(
        Object.values(PROVIDER_CONFIG).map((c) => [c.envVar, c.label]),
      );
      const serviceList = Object.keys(serviceTokens)
        .map((envVar) => `- ${envVarToLabel[envVar] ?? envVar}: connected`)
        .join("\n");
      systemPrompt += `\n\n## Connected Services\n${serviceList}`;
    }

    // ---------------------------------------------------------------------------
    // In-process MCP server for platform tools (PR creation, etc.)
    // Only available when user has a GitHub App installation with a connected repo.
    // ---------------------------------------------------------------------------
    const installationId = user.github_installation_id as number | null;
    const repoUrl = user.repo_url as string | null;

    let mcpServersOption: Record<string, ReturnType<typeof createSdkMcpServer>> | undefined;
    let platformToolNames: string[] = [];
    // Hoisted for canUseTool audit logging — set inside the installationId guard
    let repoOwner = "";
    let repoName = "";

    // Session-scoped rate limiter for workflow triggers (#1928)
    const workflowRateLimiter = createRateLimiter();

    // eslint-disable-next-line @typescript-eslint/no-explicit-any -- SDK uses any for heterogeneous tool arrays
    const platformTools: Array<ReturnType<typeof tool<any>>> = [];

    // GitHub PR tool: requires GitHub App installation with a connected repo.
    if (installationId && repoUrl) {
      let owner: string;
      let repo: string;
      try {
        const parsed = new URL(repoUrl);
        const segments = parsed.pathname.split("/").filter(Boolean);
        owner = segments[0] ?? "";
        repo = segments[1] ?? "";
      } catch {
        owner = "";
        repo = "";
      }

      const GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;
      if (!GITHUB_NAME_RE.test(owner) || !GITHUB_NAME_RE.test(repo)) {
        owner = "";
        repo = "";
      }

      if (owner && repo) {
        repoOwner = owner;
        repoName = repo;

        // Fetch the repo's default branch for protected-branch validation (#1929).
        // Uses the existing token cache — no extra round-trip if token is warm.
        let defaultBranch = "main";
        try {
          const repoData = await githubApiGet<{ default_branch: string }>(
            installationId,
            `/repos/${owner}/${repo}`,
          );
          defaultBranch = repoData.default_branch;
        } catch {
          // Fall back to "main" — still protected by the hardcoded list
        }

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
          async (args) => {
            try {
              const result = await createPullRequest(
                installationId, owner, repo,
                args.head, args.base, args.title, args.body,
              );
              return {
                content: [{ type: "text" as const, text: JSON.stringify(result) }],
              };
            } catch (err) {
              return {
                content: [{ type: "text" as const, text: `Error creating PR: ${(err as Error).message}` }],
                isError: true,
              };
            }
          },
        );

        platformTools.push(createPr);
        platformToolNames.push("mcp__soleur_platform__create_pull_request");

        // Phase 2: Read CI status (#1927) — auto-approve tier
        platformTools.push(
          tool(
            "github_read_ci_status",
            "Read recent CI workflow run statuses for the connected repository. " +
            "Returns status (pass/fail/in-progress), commit SHA, branch, run URL, " +
            "and workflow name/ID. Optionally filter by branch.",
            {
              branch: z.string().optional().describe("Filter runs by branch name"),
              per_page: z.number().default(10).describe("Number of runs to return (max 30)"),
            },
            async (args) => {
              try {
                const runs = await readCiStatus(
                  installationId, owner, repo,
                  { branch: args.branch, per_page: Math.min(args.per_page, 30) },
                );
                return {
                  content: [{ type: "text" as const, text: JSON.stringify(runs, null, 2) }],
                };
              } catch (err) {
                return {
                  content: [{ type: "text" as const, text: `Error reading CI status: ${(err as Error).message}` }],
                  isError: true,
                };
              }
            },
          ),
          tool(
            "github_read_workflow_logs",
            "Read failure details for a specific workflow run. Returns check annotations " +
            "(structured failure data) when available, otherwise falls back to the last " +
            "100 lines of the first failed step. Use github_read_ci_status first to find run IDs.",
            {
              run_id: z.number().describe("The workflow run ID to inspect"),
            },
            async (args) => {
              try {
                const result = await readWorkflowLogs(
                  installationId, owner, repo, args.run_id,
                );
                return {
                  content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
                };
              } catch (err) {
                return {
                  content: [{ type: "text" as const, text: `Error reading workflow logs: ${(err as Error).message}` }],
                  isError: true,
                };
              }
            },
          ),
        );
        platformToolNames.push(
          "mcp__soleur_platform__github_read_ci_status",
          "mcp__soleur_platform__github_read_workflow_logs",
        );

        // Phase 3: Trigger workflows (#1928) — gated tier
        platformTools.push(
          tool(
            "github_trigger_workflow",
            "Trigger a workflow_dispatch event on the connected repository. " +
            "Requires founder approval via review gate. Rate limited to 10 triggers per session. " +
            "Use github_read_ci_status first to find workflow IDs.",
            {
              workflow_id: z.number().describe("The workflow ID to trigger (from github_read_ci_status)"),
              ref: z.string().describe("Git ref to run the workflow on (branch name or tag)"),
              inputs: z.record(z.string(), z.string()).optional().describe("Optional workflow_dispatch inputs"),
            },
            async (args) => {
              try {
                const result = await triggerWorkflow(
                  installationId, owner, repo,
                  args.workflow_id, args.ref, workflowRateLimiter, args.inputs,
                );
                return {
                  content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
                };
              } catch (err) {
                return {
                  content: [{ type: "text" as const, text: `Error triggering workflow: ${(err as Error).message}` }],
                  isError: true,
                };
              }
            },
          ),
        );
        platformToolNames.push("mcp__soleur_platform__github_trigger_workflow");

        // Phase 4: Push branches (#1929) — gated tier
        platformTools.push(
          tool(
            "github_push_branch",
            "Push the current workspace HEAD to a feature branch on the remote. " +
            "Requires founder approval via review gate. Force-push and push to " +
            "main/master are blocked unconditionally.",
            {
              branch: z.string().describe("Target branch name (must not be main, master, or default branch)"),
              force: z.boolean().default(false).describe("Force-push (always rejected — included for explicit error messaging)"),
            },
            async (args) => {
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
                return {
                  content: [{ type: "text" as const, text: JSON.stringify(result) }],
                };
              } catch (err) {
                return {
                  content: [{ type: "text" as const, text: `Error pushing branch: ${(err as Error).message}` }],
                  isError: true,
                };
              }
            },
          ),
        );
        platformToolNames.push("mcp__soleur_platform__github_push_branch");
      }
    }

    // Service tools: registered independently of GitHub installation.
    // Users with stored API keys get tools even without a connected repo.
    const plausibleKey = serviceTokens.PLAUSIBLE_API_KEY;
    if (plausibleKey) {
      const wrapResult = (result: { success: boolean; data?: unknown; error?: string }) => ({
        content: [{ type: "text" as const, text: JSON.stringify(result) }],
        ...(result.success ? {} : { isError: true }),
      });

      platformTools.push(
        tool(
          "plausible_create_site",
          "Create a new site in Plausible Analytics. Returns the created site metadata.",
          {
            domain: z.string().describe("Domain name for the site (e.g., example.com)"),
            timezone: z.string().default("UTC").describe("Timezone for the site"),
          },
          async (args) => wrapResult(await plausibleCreateSite(plausibleKey, args.domain, args.timezone)),
        ),
        tool(
          "plausible_add_goal",
          "Add a conversion goal to a Plausible Analytics site. Uses PUT with upsert semantics (safely idempotent).",
          {
            site_id: z.string().describe("Domain of the site (e.g., example.com)"),
            goal_type: z.enum(["event", "page"]).describe("Type of goal"),
            value: z.string().describe("Event name (for event goals) or page path (for page goals)"),
          },
          async (args) => wrapResult(await plausibleAddGoal(plausibleKey, args.site_id, args.goal_type, args.value)),
        ),
        tool(
          "plausible_get_stats",
          "Get aggregate stats for a Plausible Analytics site. Returns visitors, pageviews, bounce rate, and visit duration.",
          {
            site_id: z.string().describe("Domain of the site (e.g., example.com)"),
            period: z.enum(["day", "7d", "30d"]).default("30d").describe("Time period for stats"),
          },
          async (args) => wrapResult(await plausibleGetStats(plausibleKey, args.site_id, args.period)),
        ),
      );
      platformToolNames.push(
        "mcp__soleur_platform__plausible_create_site",
        "mcp__soleur_platform__plausible_add_goal",
        "mcp__soleur_platform__plausible_get_stats",
      );
    }

    // Build MCP server if any platform tools are registered
    if (platformTools.length > 0) {
      const toolServer = createSdkMcpServer({
        name: "soleur_platform",
        version: "1.0.0",
        tools: platformTools,
      });
      mcpServersOption = { soleur_platform: toolServer };
    }

    // Run the Agent SDK query
    const prompt = userMessage
      ?? `[Session started with ${leader.name}] How can I help you today?`;

    const q = query({
      prompt,
      options: {
        cwd: workspacePath,
        model: "claude-sonnet-4-6",
        permissionMode: "default",
        // Prevent SDK from loading .claude/settings.json -- permissions.allow
        // entries bypass canUseTool entirely (permission chain step 4 before
        // step 5). Default is [] since SDK v0.1.0; explicit for defense-in-depth.
        settingSources: [],
        includePartialMessages: true,
        // persistSession defaults to true -- session files stored at
        // ~/.claude/projects/ enable resume within the same container lifecycle.
        // Cross-restart continuity handled by message replay fallback.
        ...(resumeSessionId ? { resume: resumeSessionId } : {}),
        maxTurns: 50,
        maxBudgetUsd: 5.0,
        systemPrompt,
        env: buildAgentEnv(apiKey, serviceTokens),
        disallowedTools: ["WebSearch", "WebFetch"],
        ...(mcpServersOption ? { mcpServers: mcpServersOption } : {}),
        ...(platformToolNames.length > 0 || pluginMcpServerNames.length > 0
          ? {
              allowedTools: [
                ...platformToolNames,
                ...pluginMcpServerNames.map((s) => `mcp__plugin_soleur_${s}__*`),
              ],
            }
          : {}),
        sandbox: {
          enabled: true,
          autoAllowBashIfSandboxed: true,
          allowUnsandboxedCommands: false,
          // Docker containers cannot mount proc inside user namespaces (kernel
          // restriction). enableWeakerNestedSandbox skips --proc /proc in bwrap,
          // which is acceptable because /proc is already in denyRead (#1557).
          enableWeakerNestedSandbox: true,
          network: {
            allowedDomains: [],
            allowManagedDomainsOnly: true,
          },
          filesystem: {
            allowWrite: [workspacePath],
            denyRead: ["/workspaces", "/proc"],
          },
        },
        plugins: [{ type: "local" as const, path: pluginPath }],
        hooks: {
          PreToolUse: [{
            // LS and NotebookEdit added for #891 path validation.
            // NotebookRead included defensively (SDK may route via Read).
            matcher: "Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash",
            hooks: [createSandboxHook(workspacePath)],
          }],
          // Defense-in-depth: log subagent spawns for audit visibility.
          // If a future SDK version stops routing subagent tool calls
          // through canUseTool, these logs provide evidence. See #910.
          SubagentStart: [{
            hooks: [async (input) => {
              const subInput = input as Record<string, unknown>;
              const sanitize = (v: unknown) => String(v ?? '').replace(/[\r\n]/g, ' ').slice(0, 200);
              log.info(
                { sec: true, agentId: sanitize(subInput.agent_id), agentType: sanitize(subInput.agent_type) },
                "Subagent started",
              );
              return {};
            }],
          }],
        },
        // File tools and Bash are resolved by PreToolUse hooks (step 1)
        // and SDK sandbox auto-approval (step 3) before reaching this
        // callback. The canUseTool file-tool check is defense-in-depth
        // for tools that somehow bypass hooks. See #891.
        canUseTool: async (
          toolName: string,
          toolInput: Record<string, unknown>,
          options: { signal: AbortSignal; agentID?: string },
        ) => {
          const subagentCtx = options.agentID ? ` [subagent=${options.agentID}]` : '';
          // Defense-in-depth: catch any file tool that bypasses hooks.
          // PreToolUse hooks are the primary enforcement (layer 1).
          // This is layer 2 -- see #891 for the audit that added it.
          if (isFileTool(toolName)) {
            const filePath = extractToolPath(toolInput);
            if (filePath && !isPathInWorkspace(filePath, workspacePath)) {
              return {
                behavior: "deny" as const,
                message: `Access denied: outside workspace${subagentCtx}`,
              };
            }
            if (!filePath && (UNVERIFIED_PARAM_TOOLS as readonly string[]).includes(toolName) && Object.keys(toolInput).length > 0) {
              log.warn(
                { sec: true, toolName, inputKeys: Object.keys(toolInput) },
                "Tool invoked without recognized path parameter; SDK may have changed parameter names (see #891)",
              );
            }
            return { behavior: "allow" as const };
          }

          // Review gates: intercept AskUserQuestion
          if (toolName === "AskUserQuestion") {
            const gateId = randomUUID();
            const gate = extractReviewGateInput(toolInput as Record<string, unknown>);

            if (gate.isNewSchema) {
              const questions = (toolInput as Record<string, unknown>).questions as unknown[];
              if (questions.length > 1) {
                log.warn(
                  { questionCount: questions.length },
                  "AskUserQuestion received multiple questions; only the first is surfaced",
                );
              }
            }

            sendToClient(userId, {
              type: "review_gate",
              gateId,
              question: gate.question,
              header: gate.header,
              options: gate.options,
              descriptions: Object.keys(gate.descriptions).length > 0
                ? gate.descriptions
                : undefined,
            });

            await updateConversationStatus(conversationId, "waiting_for_user");

            const selection = await abortableReviewGate(
              session,
              gateId,
              controller.signal,
              undefined, // timeoutMs (use default)
              gate.options,
            );

            await updateConversationStatus(conversationId, "active");

            return {
              behavior: "allow" as const,
              updatedInput: buildReviewGateResponse(
                toolInput as Record<string, unknown>,
                selection,
              ),
            };
          }

          // Agent tool: spawns subagents that run within the same SDK
          // sandbox (bubblewrap, filesystem restrictions, network policy).
          // Both PreToolUse hooks and this canUseTool callback fire for
          // subagent tool calls (SDK CanUseTool type confirms via
          // options.agentID). Explicit allow replaces the prior SAFE_TOOLS
          // auto-allow for auditability. See #910.
          if (toolName === "Agent") {
            if (subagentCtx) {
              log.info({ sec: true, agentId: options.agentID }, "Agent tool invoked by subagent");
            }
            return { behavior: "allow" as const };
          }

          // Safe SDK tools: no filesystem path inputs, allowed without checks.
          // See tool-path-checker.ts for rationale on each tool.
          // LS removed (#891) -- it accepts path inputs and routes through
          // isPathInWorkspace. NotebookRead removed -- SDK reads via Read tool.
          if (isSafeTool(toolName)) {
            return { behavior: "allow" as const };
          }

          // Tiered gating for in-process MCP server tools (#1926).
          // Scoped to platformToolNames (not blanket mcp__ prefix) to prevent
          // future MCP servers from being auto-allowed without explicit review.
          if (platformToolNames.includes(toolName)) {
            const tier = getToolTier(toolName);

            if (tier === "blocked") {
              log.info(
                { sec: true, tool: toolName, tier, decision: "deny", repo: `${repoOwner}/${repoName}` },
                "Platform tool blocked",
              );
              return {
                behavior: "deny" as const,
                message: "This action is not allowed from cloud agents",
              };
            }

            if (tier === "gated") {
              const gateId = randomUUID();
              const question = buildGateMessage(toolName, toolInput);

              sendToClient(userId, {
                type: "review_gate",
                gateId,
                question,
                options: ["Approve", "Reject"],
              });

              await updateConversationStatus(conversationId, "waiting_for_user");

              const selection = await abortableReviewGate(
                session,
                gateId,
                options.signal,
                undefined,
                ["Approve", "Reject"],
              );

              await updateConversationStatus(conversationId, "active");

              const decision = selection === "Approve" ? "approved" : "rejected";
              log.info(
                { sec: true, tool: toolName, tier, decision, repo: `${repoOwner}/${repoName}` },
                "Platform tool gated",
              );

              if (selection !== "Approve") {
                return {
                  behavior: "deny" as const,
                  message: "User rejected the action",
                };
              }

              return { behavior: "allow" as const };
            }

            // auto-approve: read-only tools pass through
            log.info(
              { sec: true, tool: toolName, tier, decision: "auto-approved", repo: `${repoOwner}/${repoName}` },
              "Platform tool auto-approved",
            );
            return { behavior: "allow" as const };
          }

          // Allow plugin MCP tools from servers registered in plugin.json.
          // Uses explicit server-name matching (not blanket mcp__ prefix).
          // See learning: 2026-04-06-mcp-tool-canusertool-scope-allowlist.md
          if (
            toolName.startsWith("mcp__plugin_soleur_") &&
            pluginMcpServerNames.some((server) =>
              toolName.startsWith(`mcp__plugin_soleur_${server}__`),
            )
          ) {
            log.info({ sec: true, toolName, agentId: options.agentID }, "Plugin MCP tool invoked");
            return { behavior: "allow" as const };
          }

          // Deny-by-default: block unrecognized tools
          return {
            behavior: "deny" as const,
            message: "Tool not permitted in this environment",
          };
        },
      },
    });

    // Stream messages to client with leader attribution
    let fullText = "";
    const streamLeaderId = effectiveLeaderId;

    // Notify client that this leader is about to stream
    sendToClient(userId, { type: "stream_start", leaderId: streamLeaderId, source: routeSource });

    for await (const message of q) {
      if (controller.signal.aborted) break;

      // Capture session_id from the first message (available on every message)
      if (!session.sessionId && "session_id" in message && message.session_id) {
        session.sessionId = message.session_id;
        // Persist to DB for cross-turn resume
        const { error: updateErr } = await supabase()
          .from("conversations")
          .update({ session_id: message.session_id })
          .eq("id", conversationId);
        if (updateErr) {
          log.error({ err: updateErr, conversationId }, "Failed to store session_id");
        }
      }

      if (message.type === "assistant") {
        const content = message.message?.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === "text") {
              fullText += block.text;
              sendToClient(userId, {
                type: "stream",
                content: block.text,
                partial: false,
                leaderId: streamLeaderId,
              });
            }
          }
        }
      } else if (message.type === "result") {
        // Save the full assistant response with leader attribution
        if (fullText) {
          await saveMessage(conversationId, "assistant", fullText, undefined, streamLeaderId);
        }

        // Capture cost data from SDK result (per-turn delta)
        const costDelta = message.total_cost_usd ?? 0;
        const inputDelta = message.usage?.input_tokens ?? 0;
        const outputDelta = message.usage?.output_tokens ?? 0;

        // Fire-and-forget: cost tracking is non-blocking telemetry
        supabase().rpc(
          "increment_conversation_cost",
          {
            conv_id: conversationId,
            cost_delta: costDelta,
            input_delta: inputDelta,
            output_delta: outputDelta,
          },
        ).then(({ error: costError }) => {
          if (costError) {
            log.error({ err: costError, conversationId }, "Failed to save cost data");
          }
        });

        sendToClient(userId, {
          type: "usage_update",
          conversationId,
          totalCostUsd: costDelta,
          inputTokens: inputDelta,
          outputTokens: outputDelta,
        });

        // Sync: push changes to remote after session (connected repos only)
        if (user.repo_status === "ready") {
          await syncPush(userId, workspacePath);
        }

        // Notify client that this leader finished streaming
        sendToClient(userId, { type: "stream_end", leaderId: streamLeaderId });

        // Mark as waiting_for_user instead of completed -- conversation
        // continues until explicit close or inactivity timeout.
        await updateConversationStatus(conversationId, "waiting_for_user");

        sendToClient(userId, {
          type: "session_ended",
          reason: "turn_complete",
        });
      } else if (
        // Partial messages (streaming text deltas)
        "message" in message &&
        message.message?.content
      ) {
        const content = message.message.content;
        if (Array.isArray(content)) {
          const lastBlock = content[content.length - 1];
          if (lastBlock?.type === "text") {
            sendToClient(userId, {
              type: "stream",
              content: lastBlock.text,
              partial: true,
              leaderId: streamLeaderId,
            });
          }
        }
      }
    }
  } catch (err) {
    if (controller.signal.aborted) {
      // If superseded, the caller (abortActiveSession) already set status to
      // "completed" — skip the "failed" write to avoid overwriting it.
      const isSuperseded = err instanceof Error && err.message.includes("superseded");
      if (!isSuperseded) {
        // Disconnect or abort -- mark conversation as failed so it does not
        // stay stuck in "waiting_for_user" or "active" status forever.
        await updateConversationStatus(conversationId, "failed").catch(
          (statusErr) => {
            log.error(
              { err: statusErr, conversationId },
              "Failed to mark aborted conversation as failed",
            );
          },
        );
      }
    } else {
      Sentry.captureException(err);
      log.error({ err, userId, conversationId }, "Session error");
      const message = sanitizeErrorForClient(err);
      sendToClient(userId, {
        type: "error",
        message,
        errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
      });
      await updateConversationStatus(conversationId, "failed").catch(
        (statusErr) => {
          log.error(
            { err: statusErr, conversationId },
            "Failed to mark conversation as failed",
          );
        },
      );
    }
  } finally {
    activeSessions.delete(key);
  }
}

// ---------------------------------------------------------------------------
// Multi-leader dispatch
// ---------------------------------------------------------------------------

/**
 * Dispatch a user message to multiple leaders in parallel.
 * Each leader gets its own agent session with context injection.
 */
async function dispatchToLeaders(
  userId: string,
  conversationId: string,
  leaders: import("./domain-leaders").DomainLeaderId[],
  message: string,
  context?: import("@/lib/types").ConversationContext,
  resumeSessionId?: string,
  routeSource?: "auto" | "mention",
): Promise<void> {
  if (leaders.length === 1) {
    // Single leader — use standard session flow
    await startAgentSession(userId, conversationId, leaders[0], resumeSessionId, message, context, routeSource);
    return;
  }

  // Multiple leaders — dispatch in parallel
  // Each leader runs its own startAgentSession with its own system prompt.
  // stream_start/stream/stream_end messages are tagged with leaderId so the
  // client can multiplex them into separate bubbles.
  const results = await Promise.allSettled(
    leaders.map((leaderId) =>
      startAgentSession(userId, conversationId, leaderId, undefined, message, context, routeSource),
    ),
  );

  // Log failures but don't fail the whole dispatch
  for (let i = 0; i < results.length; i++) {
    if (results[i].status === "rejected") {
      log.error(
        { err: (results[i] as PromiseRejectedResult).reason, leaderId: leaders[i] },
        "Leader dispatch failed",
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Send user message into running session
// ---------------------------------------------------------------------------
export async function sendUserMessage(
  userId: string,
  conversationId: string,
  content: string,
  conversationContext?: import("@/lib/types").ConversationContext,
  attachments?: AttachmentRef[],
): Promise<void> {
  // Verify conversation ownership BEFORE saving the message to prevent
  // cross-user writes (the message insert has no user_id check itself).
  const { data: conv, error: convErr } = await supabase()
    .from("conversations")
    .select("domain_leader, session_id")
    .eq("id", conversationId)
    .eq("user_id", userId)
    .single();

  if (convErr || !conv) throw new Error("Conversation not found");

  // Save user message to DB (after ownership verified)
  const messageId = randomUUID();
  const { error: msgErr } = await supabase().from("messages").insert({
    id: messageId,
    conversation_id: conversationId,
    role: "user",
    content,
    tool_calls: null,
    leader_id: null,
  });
  if (msgErr) throw new Error(`Failed to save message: ${msgErr.message}`);

  // Persist attachment metadata and download files to workspace
  let attachmentContext: string | undefined;
  if (attachments && attachments.length > 0) {
    // Validate and sanitize each attachment (defense-in-depth — client is untrusted)
    const ALLOWED_TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp", "application/pdf"]);
    const pathPrefix = `${userId}/${conversationId}/`;

    for (const att of attachments) {
      // P1 fix: reject storagePath that doesn't belong to this user/conversation or contains traversal
      if (!att.storagePath.startsWith(pathPrefix) || att.storagePath.includes("..")) {
        throw new Error("Attachment not found");
      }
      if (!ALLOWED_TYPES.has(att.contentType)) {
        throw new Error("Unsupported file type");
      }
      // Sanitize filename: strip path separators
      att.filename = att.filename.replace(/[/\\]/g, "_");
    }

    // Insert attachment metadata rows
    const attachmentRows = attachments.map((att) => ({
      message_id: messageId,
      storage_path: att.storagePath,
      filename: att.filename,
      content_type: att.contentType,
      size_bytes: att.sizeBytes,
    }));

    const { error: attErr } = await supabase()
      .from("message_attachments")
      .insert(attachmentRows);

    if (attErr) {
      log.error({ err: attErr, messageId }, "Failed to save attachment metadata");
      throw new Error("Upload failed");
    }

    // Download files to workspace for agent access
    const { data: user } = await supabase()
      .from("users")
      .select("workspace_path")
      .eq("id", userId)
      .single();

    if (user?.workspace_path) {
      const attachDir = path.join(user.workspace_path, "attachments", conversationId);
      mkdirSync(attachDir, { recursive: true });

      const filePaths: string[] = [];
      for (const att of attachments) {
        const { data: fileData, error: dlErr } = await supabase()
          .storage
          .from("chat-attachments")
          .download(att.storagePath);

        if (dlErr || !fileData) {
          log.error({ err: dlErr, storagePath: att.storagePath }, "Failed to download attachment");
          continue;
        }

        const extMap: Record<string, string> = {
          "image/png": "png", "image/jpeg": "jpeg", "image/gif": "gif",
          "image/webp": "webp", "application/pdf": "pdf",
        };
        const ext = extMap[att.contentType] || "bin";
        const localPath = path.join(attachDir, `${randomUUID()}.${ext}`);
        writeFileSync(localPath, Buffer.from(await fileData.arrayBuffer()));
        filePaths.push(`- ${att.filename} (${att.contentType}, ${att.sizeBytes} bytes): ${localPath}`);
      }

      if (filePaths.length > 0) {
        attachmentContext = `The user attached the following files:\n${filePaths.join("\n")}`;
      }
    }
  }

  // Check for an in-memory session with a captured session_id
  const key = sessionKey(userId, conversationId);
  const activeSession = activeSessions.get(key);
  const resumeSessionId = activeSession?.sessionId ?? conv.session_id ?? undefined;

  const handleSessionError = (err: unknown) => {
    Sentry.captureException(err);
    log.error(
      { err, userId, conversationId },
      "sendUserMessage session error",
    );
    const message = sanitizeErrorForClient(err);
    sendToClient(userId, {
      type: "error",
      message,
      errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
    });
    updateConversationStatus(conversationId, "failed").catch((statusErr) => {
      log.error(
        { err: statusErr, conversationId },
        "Failed to mark conversation as failed",
      );
    });
  };

  // Augment content with attachment context for the agent
  const augmentedContent = attachmentContext
    ? `${content}\n\n${attachmentContext}`
    : content;

  // If no domain_leader is set (tag-and-route mode), use the router
  // to determine which leaders should respond
  if (!conv.domain_leader) {
    try {
      const apiKey = await getUserApiKey(userId);
      const route = await routeMessage(content, apiKey, conversationContext);
      log.info({ leaders: route.leaders, source: route.source }, "Routed message to leaders");
      dispatchToLeaders(userId, conversationId, route.leaders, augmentedContent, conversationContext, undefined, route.source)
        .catch(handleSessionError);
    } catch (err) {
      handleSessionError(err);
    }
    return;
  }

  // Legacy single-leader flow (conversation has explicit domain_leader)
  if (resumeSessionId) {
    // Try SDK resume first; fall back to message replay if it fails
    startAgentSession(
      userId,
      conversationId,
      (conv.domain_leader as DomainLeaderId) ?? undefined,
      resumeSessionId,
      augmentedContent,
    ).catch(async (err) => {
      log.warn({ err }, "SDK resume failed, falling back to message replay");
      // Clear stale session_id
      const { error: clearErr } = await supabase()
        .from("conversations")
        .update({ session_id: null })
        .eq("id", conversationId);
      if (clearErr) {
        log.error({ err: clearErr, conversationId }, "Failed to clear session_id");
      }

      // Load history and build replay prompt
      const history = await loadConversationHistory(conversationId);
      const replayPrompt = buildReplayPrompt(history, augmentedContent);

      startAgentSession(
        userId,
        conversationId,
        (conv.domain_leader as DomainLeaderId) ?? undefined,
        undefined,
        replayPrompt,
      ).catch(handleSessionError);
    });
  } else {
    // No session to resume — first turn or history-only replay
    const history = await loadConversationHistory(conversationId);
    const prompt = history.length > 0
      ? buildReplayPrompt(history, augmentedContent)
      : augmentedContent;

    startAgentSession(
      userId,
      conversationId,
      (conv.domain_leader as DomainLeaderId) ?? undefined,
      undefined,
      prompt,
    ).catch(handleSessionError);
  }
}

// ---------------------------------------------------------------------------
// Resolve a review gate
// ---------------------------------------------------------------------------
export async function resolveReviewGate(
  userId: string,
  conversationId: string,
  gateId: string,
  selection: string,
): Promise<void> {
  // Search all sessions for this conversation (any leader) to find the gate.
  // In multi-leader mode, each leader has its own session key.
  const prefix = `${userId}:${conversationId}`;
  let hasSession = false;
  let foundSession: import("./review-gate").AgentSession | undefined;
  let foundEntry: { resolve: (s: string) => void; options: string[] } | undefined;

  for (const [key, session] of activeSessions) {
    if (key === prefix || key.startsWith(`${prefix}:`)) {
      hasSession = true;
      const entry = session.reviewGateResolvers.get(gateId);
      if (entry) {
        foundSession = session;
        foundEntry = entry;
        break;
      }
    }
  }

  if (!hasSession) {
    throw new Error("No active session");
  }

  if (!foundSession || !foundEntry) {
    throw new Error("Review gate not found or already resolved");
  }

  validateSelection(foundEntry.options, selection);

  foundEntry.resolve(selection);
  foundSession.reviewGateResolvers.delete(gateId);
}
