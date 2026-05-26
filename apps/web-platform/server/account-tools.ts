import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { deleteAccount } from "./account-delete";
import { enqueueExport } from "./dsar-export";

interface BuildAccountToolsOpts {
  userId: string;
  userEmail: string;
  sessionId: string;
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

export function buildAccountTools(opts: BuildAccountToolsOpts) {
  const { userId, userEmail, sessionId } = opts;

  return {
    tools: [
      tool(
        "account_export_enqueue",
        "Enqueue a DSAR (Article 15 + 20) data export for the current user. " +
          "Returns a 202 payload with the job ID and expected completion time. " +
          "The export bundles account profile, conversations, messages, " +
          "attachments, KB share links, BYOK credentials, and workspace files " +
          "into a signed ZIP URL valid for 7 days. " +
          "Idempotent: returns the existing in-flight job if one is already queued. " +
          "Error codes: 429 rate_limited (one active export at a time).",
        { requesterIp: z.string().describe("Client IP for audit trail"), userAgent: z.string().describe("User-Agent for audit trail"), reauthEventId: z.string().describe("Re-authentication event ID from the step-up auth flow") },
        async (input) => {
          try {
            const result = await enqueueExport({
              userId,
              sessionId,
              reauthEventId: input.reauthEventId,
              requesterIp: input.requesterIp,
              userAgent: input.userAgent,
            });
            return textResponse(result);
          } catch (err) {
            return textResponse(
              { error: "export_failed", message: err instanceof Error ? err.message : "unknown" },
              true,
            );
          }
        },
      ),
      tool(
        "account_delete_initiate",
        "Initiate permanent account deletion for the current user. " +
          "DESTRUCTIVE: deletes all account data, conversations, messages, " +
          "attachments, workspace files, and cancels any active subscription. " +
          "Requires explicit acknowledgment via the 'ack' parameter " +
          "(must be the literal string 'DELETE MY ACCOUNT') per " +
          "hr-menu-option-ack-not-prod-write-auth. " +
          "Also requires 'confirmEmail' matching the user's email on file. " +
          "Error codes: 403 not_a_workspace_member, 400 ack_mismatch, " +
          "400 email_mismatch.",
        { ack: z.string().describe("Must be the literal 'DELETE MY ACCOUNT'"), confirmEmail: z.string().describe("Must match the user's email address on file") },
        async (input) => {
          if (input.ack !== "DELETE MY ACCOUNT") {
            return textResponse(
              { error: "ack_mismatch", code: "400", message: "ack must be the literal 'DELETE MY ACCOUNT'" },
              true,
            );
          }
          if (input.confirmEmail !== userEmail) {
            return textResponse(
              { error: "email_mismatch", code: "400", message: "confirmEmail does not match user email on file" },
              true,
            );
          }
          try {
            const result = await deleteAccount(userId, input.confirmEmail);
            if (!result.success) {
              return textResponse({ error: "delete_failed", message: result.error }, true);
            }
            return textResponse({ success: true, message: "Account deletion cascade complete." });
          } catch (err) {
            return textResponse(
              { error: "delete_failed", message: err instanceof Error ? err.message : "unknown" },
              true,
            );
          }
        },
      ),
    ],
    toolNames: [
      "mcp__soleur_platform__account_export_enqueue",
      "mcp__soleur_platform__account_delete_initiate",
    ] as const,
  };
}
