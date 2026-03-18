import { query } from "@anthropic-ai/claude-agent-sdk";
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "crypto";
import path from "path";

import { DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { decryptKey } from "./byok";
import { sendToClient } from "./ws-handler";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

const PLUGIN_PATH =
  process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";

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
    .limit(1)
    .single();

  if (error || !data) {
    throw new Error("No valid API key found. Please set up your key first.");
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
  await supabase.from("messages").insert({
    id: randomUUID(),
    conversation_id: conversationId,
    role,
    content,
    tool_calls: toolCalls || null,
  });
}

async function updateConversationStatus(
  conversationId: string,
  status: string,
) {
  await supabase
    .from("conversations")
    .update({ status, last_active: new Date().toISOString() })
    .eq("id", conversationId);
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
        includePartialMessages: true,
        persistSession: false,
        maxTurns: 50,
        maxBudgetUsd: 5.0,
        systemPrompt,
        env: { ...process.env, ANTHROPIC_API_KEY: apiKey },
        plugins: [{ type: "local" as const, path: pluginPath }],
        canUseTool: async (
          toolName: string,
          toolInput: Record<string, unknown>,
        ) => {
          // Workspace sandbox: block file access outside workspace
          if (
            ["Read", "Write", "Edit", "Glob", "Grep"].includes(toolName)
          ) {
            const filePath =
              (toolInput.file_path as string) ||
              (toolInput.path as string) ||
              "";
            if (filePath && !filePath.startsWith(workspacePath)) {
              return {
                behavior: "deny" as const,
                message: "Access denied: outside workspace",
              };
            }
          }

          // Review gates: intercept AskUserQuestion
          if (toolName === "AskUserQuestion") {
            const gateId = randomUUID();
            const question =
              (toolInput.question as string) || "Agent needs your input";
            const options = Array.isArray(toolInput.options)
              ? (toolInput.options as string[])
              : ["Approve", "Reject"];

            // Send review gate to client
            sendToClient(userId, {
              type: "review_gate",
              gateId,
              question,
              options,
            });

            // Update conversation status
            await updateConversationStatus(conversationId, "waiting_for_user");

            // Wait for user response
            const selection = await new Promise<string>((resolve) => {
              session.reviewGateResolvers.set(gateId, resolve);
            });

            await updateConversationStatus(conversationId, "active");

            return {
              behavior: "allow" as const,
              updatedInput: { ...toolInput, answer: selection },
            };
          }

          return { behavior: "allow" as const };
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
      const message =
        err instanceof Error ? err.message : "Agent session failed";
      const isKeyError = err instanceof Error &&
        err.message.includes("No valid API key");
      sendToClient(userId, {
        type: "error",
        message,
        ...(isKeyError && { errorCode: "key_invalid" as const }),
      });
      await updateConversationStatus(conversationId, "failed");
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
  );
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
