import { query } from "@anthropic-ai/claude-agent-sdk";
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "crypto";
import { readFileSync, writeFileSync } from "fs";
import path from "path";

import { DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { KeyInvalidError } from "@/lib/types";
import { decryptKey } from "./byok";
import { sendToClient } from "./ws-handler";
import { sanitizeErrorForClient } from "./error-sanitizer";
import { isPathInWorkspace } from "./sandbox";
import { UNVERIFIED_PARAM_TOOLS, extractToolPath, isFileTool, isSafeTool } from "./tool-path-checker";
import { buildAgentEnv } from "./agent-env";
import { createSandboxHook } from "./sandbox-hook";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

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
interface AgentSession {
  abort: AbortController;
  reviewGateResolvers: Map<string, (selection: string) => void>;
}

const activeSessions = new Map<string, AgentSession>();

function sessionKey(userId: string, conversationId: string) {
  return `${userId}:${conversationId}`;
}

// ---------------------------------------------------------------------------
// BYOK key retrieval
// ---------------------------------------------------------------------------
async function getUserApiKey(userId: string): Promise<string> {
  const { data, error } = await supabase
    .from("api_keys")
    .select("encrypted_key, iv, auth_tag")
    .eq("user_id", userId)
    .eq("is_valid", true)
    .eq("provider", "anthropic")
    .limit(1)
    .single();

  if (error || !data) {
    throw new KeyInvalidError();
  }

  return decryptKey(
    Buffer.from(data.encrypted_key, "base64"),
    Buffer.from(data.iv, "base64"),
    Buffer.from(data.auth_tag, "base64"),
  );
}

// ---------------------------------------------------------------------------
// Message persistence
// ---------------------------------------------------------------------------
async function saveMessage(
  conversationId: string,
  role: "user" | "assistant",
  content: string,
  toolCalls?: unknown,
) {
  const { error } = await supabase.from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role,
    content,
    tool_calls: toolCalls || null,
  });

  if (error) {
    throw new Error(`Failed to save message: ${error.message}`);
  }
}

async function updateConversationStatus(
  conversationId: string,
  status: string,
) {
  const { error } = await supabase
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
// Start agent session
// ---------------------------------------------------------------------------
export async function startAgentSession(
  userId: string,
  conversationId: string,
  leaderId: DomainLeaderId,
): Promise<void> {
  const key = sessionKey(userId, conversationId);

  // Abort any existing session
  const existing = activeSessions.get(key);
  if (existing) existing.abort.abort();

  const controller = new AbortController();
  const session: AgentSession = {
    abort: controller,
    reviewGateResolvers: new Map(),
  };
  activeSessions.set(key, session);

  try {
    // Get user's decrypted API key
    const apiKey = await getUserApiKey(userId);

    // Get leader config
    const leader = DOMAIN_LEADERS.find((l) => l.id === leaderId);
    if (!leader) throw new Error(`Unknown leader: ${leaderId}`);

    // Get user workspace path
    const { data: user } = await supabase
      .from("users")
      .select("workspace_path")
      .eq("id", userId)
      .single();

    if (!user?.workspace_path) {
      throw new Error("Workspace not provisioned");
    }

    const workspacePath = user.workspace_path;
    const pluginPath = path.join(workspacePath, "plugins", "soleur");

    // Migrate existing workspaces: remove pre-approved permissions that
    // bypass canUseTool (see #725). Safe to run on every session start —
    // no-op for already-migrated workspaces.
    patchWorkspacePermissions(workspacePath);

    // Build system prompt for the domain leader
    const systemPrompt = `You are the ${leader.title} (${leader.name}) for this user's business. ${leader.description}

Use the tools available to you to read and write to the knowledge-base directory. The user's workspace is at ${workspacePath}.

When you need user input for important decisions, use the AskUserQuestion tool.`;

    // Run the Agent SDK query
    const q = query({
      prompt: `[Session started with ${leader.name}] How can I help you today?`,
      options: {
        cwd: workspacePath,
        model: "claude-sonnet-4-6",
        permissionMode: "default",
        // Prevent SDK from loading .claude/settings.json -- permissions.allow
        // entries bypass canUseTool entirely (permission chain step 4 before
        // step 5). Default is [] since SDK v0.1.0; explicit for defense-in-depth.
        settingSources: [],
        includePartialMessages: true,
        persistSession: false,
        maxTurns: 50,
        maxBudgetUsd: 5.0,
        systemPrompt,
        env: buildAgentEnv(apiKey),
        settingSources: [],
        disallowedTools: ["WebSearch", "WebFetch"],
        sandbox: {
          enabled: true,
          autoAllowBashIfSandboxed: true,
          allowUnsandboxedCommands: false,
          network: {
            allowedDomains: [],
            allowManagedDomainsOnly: true,
          },
          filesystem: {
            allowWrite: [workspacePath],
            denyRead: ["/workspaces"],
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
              console.log(
                `[sec] Subagent started: agent_id=${sanitize(subInput.agent_id)}, ` +
                `type=${sanitize(subInput.agent_type)}`,
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
              console.warn(
                `[sec] ${toolName} invoked without recognized path parameter. ` +
                `Keys: ${Object.keys(toolInput).join(", ")}. ` +
                `SDK version may have changed parameter names. See #891.`,
              );
            }
            return { behavior: "allow" as const };
          }

          // Review gates: intercept AskUserQuestion
          if (toolName === "AskUserQuestion") {
            const gateId = randomUUID();
            const question =
              (toolInput.question as string) || "Agent needs your input";
            const gateOptions = Array.isArray(toolInput.options)
              ? (toolInput.options as string[])
              : ["Approve", "Reject"];

            sendToClient(userId, {
              type: "review_gate",
              gateId,
              question,
              options: gateOptions,
            });

            await updateConversationStatus(conversationId, "waiting_for_user");

            const selection = await new Promise<string>((resolve) => {
              session.reviewGateResolvers.set(gateId, resolve);
            });

            await updateConversationStatus(conversationId, "active");

            return {
              behavior: "allow" as const,
              updatedInput: { ...toolInput, answer: selection },
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
              console.log(`[sec] Agent tool invoked${subagentCtx}`);
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

          // Deny-by-default: block unrecognized tools
          return {
            behavior: "deny" as const,
            message: "Tool not permitted in this environment",
          };
        },
      },
    });

    // Stream messages to client
    let fullText = "";

    for await (const message of q) {
      if (controller.signal.aborted) break;

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
              });
            }
          }
        }
      } else if (message.type === "result") {
        // Save the full assistant response
        if (fullText) {
          await saveMessage(conversationId, "assistant", fullText);
        }

        await updateConversationStatus(conversationId, "completed");

        sendToClient(userId, {
          type: "session_ended",
          reason: "completed",
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
            });
          }
        }
      }
    }
  } catch (err) {
    if (!controller.signal.aborted) {
      console.error(`[agent] Session error for ${userId}/${conversationId}:`, err);
      const message = sanitizeErrorForClient(err);
      sendToClient(userId, {
        type: "error",
        message,
        errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
      });
      await updateConversationStatus(conversationId, "failed").catch(
        (statusErr) => {
          console.error(
            `[agent] Failed to mark conversation ${conversationId} as failed:`,
            statusErr,
          );
        },
      );
    }
  } finally {
    activeSessions.delete(key);
  }
}

// ---------------------------------------------------------------------------
// Send user message into running session
// ---------------------------------------------------------------------------
export async function sendUserMessage(
  userId: string,
  conversationId: string,
  content: string,
): Promise<void> {
  // Save user message to DB
  await saveMessage(conversationId, "user", content);

  // For multi-turn, we'd need to start a new query with resume.
  // For now, start a fresh query with the user's message as the prompt.
  const { data: conv } = await supabase
    .from("conversations")
    .select("domain_leader")
    .eq("id", conversationId)
    .single();

  if (!conv) throw new Error("Conversation not found");

  // Start a new agent turn with the user's message
  startAgentSession(
    userId,
    conversationId,
    conv.domain_leader as DomainLeaderId,
  ).catch((err) => {
    console.error(
      `[agent] sendUserMessage session error for ${userId}/${conversationId}:`,
      err,
    );
    const message = sanitizeErrorForClient(err);
    sendToClient(userId, {
      type: "error",
      message,
      errorCode: err instanceof KeyInvalidError ? "key_invalid" : undefined,
    });
    updateConversationStatus(conversationId, "failed").catch((statusErr) => {
      console.error(
        `[agent] Failed to mark conversation ${conversationId} as failed:`,
        statusErr,
      );
    });
  });
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
  const key = sessionKey(userId, conversationId);
  const session = activeSessions.get(key);

  if (!session) {
    throw new Error("No active session");
  }

  const resolver = session.reviewGateResolvers.get(gateId);
  if (!resolver) {
    throw new Error("Review gate not found or already resolved");
  }

  resolver(selection);
  session.reviewGateResolvers.delete(gateId);
}
