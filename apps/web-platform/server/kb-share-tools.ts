// In-process MCP tool definitions for the three KB-share operations
// (create / list / revoke). Factored out of agent-runner.ts following the
// ci-tools.ts / push-branch.ts precedent so each tool's wiring has a
// single call site and unit tests can exercise the handlers in isolation.
//
// The handlers delegate the whole validation + DB lifecycle to
// server/kb-share.ts — this module only translates tagged-union DTOs into
// the platform-tool response shape and turns relative URLs into absolute
// URLs (so the agent can paste the link verbatim into its reply).

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import {
  createShare,
  listShares,
  previewShare,
  revokeShare,
  type CreateShareResult,
  type ListSharesResult,
  type PreviewShareErrorCode,
  type PreviewShareResult,
  type RevokeShareResult,
  type ShareServiceClient,
} from "@/server/kb-share";

interface BuildKbShareToolsOpts {
  serviceClient: ShareServiceClient;
  userId: string;
  kbRoot: string;
  /** Absolute origin like "https://app.soleur.ai" — prepended to relative share URLs. */
  baseUrl: string;
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

function wrapError(result: {
  error: string;
  code: string;
  status: number;
}): ToolTextResponse {
  return textResponse(
    { error: result.error, code: result.code, status: result.status },
    true,
  );
}

function wrapCreate(result: CreateShareResult, baseUrl: string): ToolTextResponse {
  if (!result.ok) return wrapError(result);
  return textResponse({
    token: result.token,
    url: `${baseUrl}${result.url}`,
    documentPath: result.documentPath,
    size: result.size,
  });
}

function wrapList(result: ListSharesResult): ToolTextResponse {
  if (!result.ok) return wrapError(result);
  return textResponse({ shares: result.shares });
}

function wrapRevoke(result: RevokeShareResult): ToolTextResponse {
  if (!result.ok) return wrapError(result);
  // Echo documentPath so a batching agent can reconstruct which file
  // lost access from the tool output alone.
  return textResponse({
    revoked: true,
    token: result.token,
    documentPath: result.documentPath,
  });
}

function wrapPreview(result: PreviewShareResult): ToolTextResponse {
  if (!result.ok) {
    // Compile-time exhaustiveness on PreviewShareErrorCode — adding a new
    // code without reviewing this wrapper fails tsc --noEmit (per
    // 2026-04-10-discriminated-union-exhaustive-switch-miss).
    const _exhaustive: PreviewShareErrorCode = result.code;
    void _exhaustive;
    return wrapError(result);
  }
  // firstPagePreview is an optional field on the success variant — JSON
  // serialization drops undefined keys, so conditional assignment buys
  // nothing. Spread result directly.
  return textResponse({
    status: result.status,
    token: result.token,
    documentPath: result.documentPath,
    kind: result.kind,
    contentType: result.contentType,
    size: result.size,
    filename: result.filename,
    firstPagePreview: result.firstPagePreview,
  });
}

export function buildKbShareTools(opts: BuildKbShareToolsOpts) {
  const { serviceClient, userId, kbRoot, baseUrl } = opts;
  return [
    tool(
      "kb_share_create",
      "Generate a public read-only share link for a KB document. " +
        "Works on any file type (markdown, PDF, image, docx). " +
        "Returns { token, url, documentPath, size }. Links are revocable. " +
        "Use kb_share_list first to check whether an active link already exists — " +
        "the tool is idempotent on unchanged content, but listing surfaces stale or " +
        "revoked links the user may want to know about.",
      { documentPath: z.string() },
      async (args) =>
        wrapCreate(
          await createShare(serviceClient, userId, kbRoot, args.documentPath),
          baseUrl,
        ),
    ),
    tool(
      "kb_share_list",
      "List share links for the current user. Optionally filter by documentPath. " +
        "Returns active and revoked links with created timestamps.",
      { documentPath: z.string().optional() },
      async (args) =>
        wrapList(
          await listShares(
            serviceClient,
            userId,
            args.documentPath ? { documentPath: args.documentPath } : undefined,
          ),
        ),
    ),
    tool(
      "kb_share_revoke",
      "Revoke a share link by its token. Permanent and cannot be undone. " +
        "Use kb_share_list to find the token first.",
      { token: z.string() },
      async (args) =>
        wrapRevoke(await revokeShare(serviceClient, userId, args.token)),
    ),
    tool(
      "kb_share_preview",
      "Preview what a recipient sees at /shared/<token>. Returns " +
        "{ status, contentType, size, filename, kind, firstPagePreview? }. " +
        "Use this to verify a share link renders correctly before sending it. " +
        "Works for all share terminal states — revoked links return " +
        "{ code: 'revoked' }, content-drift returns { code: 'content-changed' }. " +
        "Does NOT return the document bytes (use kb_read_content for that).",
      { token: z.string() },
      async (args) =>
        wrapPreview(await previewShare(serviceClient, args.token)),
    ),
  ];
}
