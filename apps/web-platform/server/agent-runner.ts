import { query, type tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { readFile, writeFile, mkdir } from "fs/promises";
import path from "path";

import { createServiceClient } from "@/lib/supabase/service";
import { ROUTABLE_DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { routeMessage } from "./domain-router";
import { KeyInvalidError, type AttachmentRef } from "@/lib/types";
import { ALLOWED_ATTACHMENT_TYPES } from "@/lib/attachment-constants";
import { decryptKey, decryptKeyLegacy, encryptKey } from "./byok";
import { sendToClient } from "./ws-handler";
import { notifyOfflineUser, type NotificationPayload } from "./notifications";
import * as Sentry from "@sentry/nextjs";
import { sanitizeErrorForClient } from "./error-sanitizer";
import {
  ERR_WORKSPACE_NOT_PROVISIONED,
  ERR_CONVERSATION_NOT_FOUND,
  ERR_NO_ACTIVE_SESSION,
  ERR_REVIEW_GATE_NOT_FOUND,
  ERR_ATTACHMENT_NOT_FOUND,
  ERR_UNSUPPORTED_FILE_TYPE,
  ERR_UPLOAD_FAILED,
} from "./error-messages";
import { isPathInWorkspace } from "./sandbox";
import { buildAgentEnv } from "./agent-env";
import { PROVIDER_CONFIG, EXCLUDED_FROM_SERVICES_UI } from "./providers";
import type { Provider } from "@/lib/types";
import { createSandboxHook } from "./sandbox-hook";
import { abortableReviewGate, validateSelection, type AgentSession } from "./review-gate";
import { createChildLogger } from "./logger";
import { syncPull, syncPush } from "./session-sync";
import { tryCreateVision, buildVisionEnhancementPrompt } from "./vision-helpers";
import { createRateLimiter } from "./trigger-workflow";
import { githubApiGet } from "./github-api";
import { MAX_BINARY_SIZE } from "./kb-limits";
import { buildKbShareTools } from "./kb-share-tools";
import { buildConversationsTools } from "./conversations-tools";
import { buildGithubTools } from "./github-tools";
import { buildPlausibleTools } from "./plausible-tools";
import { createCanUseTool } from "./permission-callback";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("agent");

let _supabase: ReturnType<typeof createServiceClient>;
function supabase() { return _supabase ??= createServiceClient(); }

const PLUGIN_PATH =
  process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";

import { buildToolLabel } from "./tool-labels";

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
  /** When true, do NOT send session_ended after the result message.
   *  Used by dispatchToLeaders so the orchestrator sends a single
   *  session_ended after all leaders finish (see #2428). */
  skipSessionEnded?: boolean,
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
      throw new Error(ERR_WORKSPACE_NOT_PROVISIONED);
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
    } catch (err) {
      // plugin.json may not exist in all workspaces; proceed without plugin MCP tools.
      // ENOENT is an expected state (no plugin installed). Parse errors or other
      // read failures on a committed file are degraded conditions — mirror to
      // Sentry so we hear about corrupted workspaces.
      if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
        reportSilentFallback(err, {
          feature: "agent-runner",
          op: "plugin-mcp-discovery",
          extra: { userId },
        });
      }
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

Use the tools available to you to read and write to the knowledge-base directory. Files are relative to the current working directory.

Never mention file system paths, workspace paths, or internal directory structures in your responses — refer to files by their knowledge-base-relative path (e.g. "overview/vision.md" not "/workspaces/.../knowledge-base/overview/vision.md").

When you need user input for important decisions, use the AskUserQuestion tool.`;

    // Inject artifact context when conversation started from a specific page.
    // Three tiers: (1) client-provided content, (2) server-read content,
    // (3) assertive Read instruction when content can't be inlined.
    // All branches include "do not ask which document" to prevent the agent
    // from ignoring the open document and asking clarifying questions (#2428).
    const CONTEXT_NO_ASK = "Do not ask which document the user is referring to — it is the document described above.";
    const MAX_INLINE_BYTES = 50_000; // ~12-15K tokens — keeps cost bounded

    if (context?.content) {
      systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nArtifact content:\n${context.content}\n\nAnswer in the context of this artifact. ${CONTEXT_NO_ASK}`;
    } else if (context?.path) {
      const fullPath = path.join(workspacePath, context.path);
      const isPdf = context.path.toLowerCase().endsWith(".pdf");
      const pathSafe = isPathInWorkspace(fullPath, workspacePath);

      if (!pathSafe) {
        // Path traversal attempt — inject nothing, log warning
        log.warn({ path: context.path, userId }, "Context path failed workspace validation");
      } else if (isPdf) {
        // PDFs can't be read as text — instruct agent assertively
        systemPrompt += `\n\nThe user is currently viewing the PDF document: ${context.path}\n\nThis is a PDF file. Use the Read tool to read "${context.path}" — it supports PDF files. Answer all questions in the context of this document. ${CONTEXT_NO_ASK}`;
      } else {
        // Attempt to read the file server-side and inject content
        try {
          const content = await readFile(fullPath, "utf-8");
          if (content.length <= MAX_INLINE_BYTES) {
            systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nDocument content:\n${content}\n\nAnswer in the context of this document. ${CONTEXT_NO_ASK}`;
          } else {
            // File too large to inline — instruct agent to Read it
            systemPrompt += `\n\nThe user is currently viewing: ${context.path} (${Math.round(content.length / 1024)}KB)\n\nThis file is too large to include inline. Use the Read tool to read "${context.path}" and answer questions in its context. ${CONTEXT_NO_ASK}`;
          }
        } catch {
          // Read failed — fall back to assertive Read instruction
          systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nRead this file first using the Read tool, then answer questions in the context of this document. Focus on the document content — do not search the knowledge-base directory for other files unless the user specifically asks. ${CONTEXT_NO_ASK}`;
        }
      }
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

    // Announce KB share capability (closes #2315). Without this block the
    // agent cannot discover kb_share_* from natural-language requests like
    // "share the Q1 report."
    const kbShareSizeMb = Math.round(MAX_BINARY_SIZE / 1024 / 1024);
    systemPrompt += `

## Knowledge-base sharing

You can generate public read-only share links for any file in the knowledge-base
using kb_share_create. Any file type is allowed (markdown, PDF, image, docx).
Links are revocable via kb_share_revoke, listable via kb_share_list, and
previewable via kb_share_preview. Use kb_share_list to check what is currently
shared before generating a new link — this surfaces duplicates and revoked
links.

kb_share_create is idempotent on unchanged content — calling it for a file
that already has an active link with a matching content hash returns the
existing token rather than issuing a new URL. Content drift revokes the
stale link and issues a fresh one.

Share links expose the file contents to anyone who has the URL. Before creating
a link for a file that looks sensitive (credentials, personal data, unreleased
strategy, or paths under finances/, legal/, customers/), confirm with
AskUserQuestion first. Files over ${kbShareSizeMb} MB cannot be shared.

Use kb_share_preview({ token }) to verify a link renders correctly before
sending it to someone. It returns the same metadata a recipient's browser
would see (contentType, size, filename, kind, and for PDFs/images a
firstPagePreview with dimensions and page count). Revoked or content-drifted
links surface the same terminal state the public endpoint would return. This
is the right tool when the user asks "double-check the link still works" or
"tell me how many pages that PDF is."

On code "revoked" or "content-changed", offer to run kb_share_create on the
same documentPath to issue a fresh link. On code "legacy-null-hash" (pre-
migration share row, rare) recommend re-creating the share as well.

## KB-chat thread discovery

You can look up whether a KB-chat thread already exists for a knowledge-base
document using conversations_lookup. Input: contextPath (the KB file path).
Returns thread metadata ({ conversationId, lastActive, messageCount }) if a
thread exists, or null otherwise. Use this before creating a new thread —
resuming an existing thread preserves context for the user.`;

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

    // GitHub tool family: requires GitHub App installation with a connected repo.
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

        const github = buildGithubTools({
          installationId,
          owner,
          repo,
          defaultBranch,
          workspacePath,
          workflowRateLimiter,
        });
        platformTools.push(...github.tools);
        platformToolNames.push(...github.toolNames);
      }
    }

    // Service tools: registered independently of GitHub installation.
    // Users with stored API keys get tools even without a connected repo.
    // Guard stays at the top level — nesting inside the GitHub block would
    // hide Plausible tools from users without a connected repo (see learning
    // `service-tool-registration-scope-guard-20260410.md`).
    const plausibleKey = serviceTokens.PLAUSIBLE_API_KEY;
    if (plausibleKey) {
      const plausible = buildPlausibleTools({ plausibleKey });
      platformTools.push(...plausible.tools);
      platformToolNames.push(...plausible.toolNames);
    }

    // KB share tools (#2309): registered independently of GitHub installation
    // or service tokens — only prerequisite is a ready workspace (guaranteed
    // above by the ERR_WORKSPACE_NOT_PROVISIONED guard). Mirrors the
    // SharePopover UI in the KB viewer so the agent and the user have
    // identical capability.
    //
    // CSRF elision: the in-process MCP tools do NOT call validateOrigin the
    // way the HTTP routes do — the agent runs in-process, there is no request
    // origin, and the review-gate confirmation (see tool-tiers.ts tier
    // mapping: create + revoke are `gated`) is the user-consent substitute.
    const appUrl = process.env.NEXT_PUBLIC_APP_URL;
    if (!appUrl) {
      reportSilentFallback(null, {
        feature: "kb-share",
        op: "baseUrl",
        message: "NEXT_PUBLIC_APP_URL unset; agent share URLs will point at https://app.soleur.ai",
        extra: { userId },
      });
    }
    const kbShareTools = buildKbShareTools({
      serviceClient: supabase(),
      userId,
      kbRoot: path.join(workspacePath, "knowledge-base"),
      baseUrl: appUrl ?? "https://app.soleur.ai",
    });
    platformTools.push(...kbShareTools);
    platformToolNames.push(
      "mcp__soleur_platform__kb_share_create",
      "mcp__soleur_platform__kb_share_list",
      "mcp__soleur_platform__kb_share_revoke",
      "mcp__soleur_platform__kb_share_preview",
    );

    // KB-chat thread discovery (closes #2512 P2 slice). P3 siblings
    // (conversations_list, conversation_archive) deferred to follow-up
    // issue because they require new HTTP endpoints.
    const conversationsTools = buildConversationsTools({ userId });
    platformTools.push(...conversationsTools);
    platformToolNames.push("mcp__soleur_platform__conversations_lookup");

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
          // Refuse to start if sandbox deps (bubblewrap, socat) are missing.
          // Without this flag, the SDK silently runs unsandboxed on dependency
          // drift (per `Options.sandbox.failIfUnavailable` in
          // @anthropic-ai/claude-agent-sdk) — Tier 4 defense-in-depth
          // disappears with no Sentry signal. See #2634.
          failIfUnavailable: true,
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
        // Permission callback (SDK chain step 5). File-tool checks are
        // defense-in-depth — PreToolUse hooks (step 1) are the primary
        // enforcement. See #891. The callback body lives in
        // `permission-callback.ts` so the 7 allow branches + deny-by-default
        // can be unit-tested without booting an SDK session (#2335).
        canUseTool: createCanUseTool({
          userId,
          conversationId,
          leaderId,
          workspacePath,
          platformToolNames,
          pluginMcpServerNames,
          repoOwner,
          repoName,
          session,
          controllerSignal: controller.signal,
          deps: {
            abortableReviewGate,
            sendToClient,
            notifyOfflineUser,
            updateConversationStatus,
          },
        }),
      },
    });

    // Stream messages to client with leader attribution
    let fullText = "";
    let hasStreamedPartials = false;
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
              // Skip final text emission if partials already streamed this content
              // (client already has the full text via cumulative partial:true messages)
              if (!hasStreamedPartials) {
                sendToClient(userId, {
                  type: "stream",
                  content: block.text,
                  partial: false,
                  leaderId: streamLeaderId,
                });
              }
            } else if (block.type === "tool_use") {
              // Emit tool_use event so client can show status chip. Only the
              // human-readable label crosses the wire — the raw SDK tool name
              // (Read/Bash/Grep/...) is an internal implementation detail and
              // must not leak to devtools or any WS inspector. See #2138.
              const toolBlock = block as { name?: string; input?: Record<string, unknown> };
              const toolName = toolBlock.name ?? "unknown";
              sendToClient(userId, {
                type: "tool_use",
                leaderId: streamLeaderId,
                label: buildToolLabel(toolName, toolBlock.input, workspacePath),
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

        // In multi-leader mode, dispatchToLeaders sends a single session_ended
        // after all leaders finish — individual leaders must not send it or the
        // client clears all active streams prematurely (see #2428).
        if (!skipSessionEnded) {
          sendToClient(userId, {
            type: "session_ended",
            reason: "turn_complete",
          });
        }
      } else if (
        // Partial messages (streaming text deltas — cumulative snapshots)
        "message" in message &&
        message.message?.content
      ) {
        const content = message.message.content;
        if (Array.isArray(content)) {
          const lastBlock = content[content.length - 1];
          if (lastBlock?.type === "text") {
            hasStreamedPartials = true;
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
    } else if (
      resumeSessionId &&
      err instanceof Error &&
      err.message.includes("No conversation found with session ID")
    ) {
      // Resume-specific error: clean up the typing indicator and re-throw
      // so the caller's .catch() fallback can fire (clear stale session_id,
      // load history, replay). Do NOT capture to Sentry (expected operational
      // behavior) or mark conversation as failed (it will be retried).
      sendToClient(userId, { type: "stream_end", leaderId: leaderId ?? "cpo" });
      throw err;
    } else {
      // Sandbox-required-but-unavailable surfaces as a SDK subprocess
      // process.exit(1) after writing this substring to stderr (see
      // `Options.sandbox.failIfUnavailable` in @anthropic-ai/claude-agent-sdk
      // and #2634). The bare captureException below would land an untagged
      // generic "command failed" event in Sentry — useless for triage. Tag
      // it so on-call can filter by `feature: "agent-sandbox"`.
      const errMsg = err instanceof Error ? err.message : String(err);
      if (errMsg.includes("sandbox required but unavailable")) {
        reportSilentFallback(err, {
          feature: "agent-sandbox",
          op: "sdk-startup",
          extra: { userId, conversationId, leaderId },
        });
      } else {
        Sentry.captureException(err);
      }
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

  // Multiple leaders — dispatch in parallel with skipSessionEnded.
  // Each leader sends its own stream_start/stream/stream_end events (tagged
  // with leaderId), but does NOT send session_ended. A single session_ended
  // is sent here after all leaders finish so the client doesn't clear active
  // streams prematurely when the first leader completes (see #2428).
  const results = await Promise.allSettled(
    leaders.map((leaderId) =>
      startAgentSession(userId, conversationId, leaderId, undefined, message, context, routeSource, true),
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

  // All leaders done (success or failure) — send single session_ended
  sendToClient(userId, { type: "session_ended", reason: "turn_complete" });
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

  if (convErr || !conv) throw new Error(ERR_CONVERSATION_NOT_FOUND);

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
    const pathPrefix = `${userId}/${conversationId}/`;

    for (const att of attachments) {
      // P1 fix: reject storagePath that doesn't belong to this user/conversation or contains traversal
      if (!att.storagePath.startsWith(pathPrefix) || att.storagePath.includes("..")) {
        throw new Error(ERR_ATTACHMENT_NOT_FOUND);
      }
      if (!ALLOWED_ATTACHMENT_TYPES.has(att.contentType)) {
        throw new Error(ERR_UNSUPPORTED_FILE_TYPE);
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
      throw new Error(ERR_UPLOAD_FAILED);
    }

    // Download files to workspace for agent access
    const { data: user } = await supabase()
      .from("users")
      .select("workspace_path")
      .eq("id", userId)
      .single();

    if (user?.workspace_path) {
      const attachDir = path.join(user.workspace_path, "attachments", conversationId);
      await mkdir(attachDir, { recursive: true });

      const extMap: Record<string, string> = {
        "image/png": "png", "image/jpeg": "jpeg", "image/gif": "gif",
        "image/webp": "webp", "application/pdf": "pdf",
      };

      const results = await Promise.allSettled(
        attachments.map(async (att) => {
          const { data: fileData, error: dlErr } = await supabase()
            .storage
            .from("chat-attachments")
            .download(att.storagePath);

          if (dlErr || !fileData) {
            log.error({ err: dlErr, storagePath: att.storagePath }, "Failed to download attachment");
            return null;
          }

          const ext = extMap[att.contentType] || "bin";
          const localPath = path.join(attachDir, `${randomUUID()}.${ext}`);
          await writeFile(localPath, Buffer.from(await fileData.arrayBuffer()));
          return `- ${att.filename} (${att.contentType}, ${att.sizeBytes} bytes): ${localPath}`;
        }),
      );

      const filePaths = results
        .filter((r): r is PromiseFulfilledResult<string | null> => r.status === "fulfilled")
        .map((r) => r.value)
        .filter((v): v is string => v !== null);

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

      // Fetch user's custom team names for @-mention resolution
      const { data: nameRows, error: namesError } = await supabase()
        .from("team_names")
        .select("leader_id, custom_name")
        .eq("user_id", userId);
      if (namesError) log.warn({ err: namesError }, "Failed to fetch custom team names");
      const customNames: Record<string, string> = {};
      for (const row of nameRows ?? []) {
        customNames[row.leader_id] = row.custom_name;
      }

      const route = await routeMessage(content, apiKey, conversationContext, customNames);
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
      conversationContext, // Pass context so system prompt includes document (#2430)
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
        conversationContext, // Pass context so system prompt includes document (#2430)
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
      conversationContext, // Pass context so system prompt includes document (#2430)
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
    throw new Error(ERR_NO_ACTIVE_SESSION);
  }

  if (!foundSession || !foundEntry) {
    throw new Error(ERR_REVIEW_GATE_NOT_FOUND);
  }

  validateSelection(foundEntry.options, selection);

  foundEntry.resolve(selection);
  foundSession.reviewGateResolvers.delete(gateId);
}
