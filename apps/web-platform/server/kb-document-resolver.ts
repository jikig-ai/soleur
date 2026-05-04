// KB Concierge document-context resolver. Mirrors the legacy
// `agent-runner.ts § "Inject artifact context"` injection (~lines 590-635
// in that file): caller-provided content wins; PDFs get a Read directive
// (no body read); text files are read server-side under the
// workspace-validation guard.
//
// Extracted from `cc-dispatcher.ts` so the orchestration layer doesn't
// own filesystem responsibilities on top of SDK Query construction, MCP
// wiring, BYOK token resolution, bash-approval, and rate-limiting. The
// per-process `_workspacePathCache` lives here too because it's the
// resolver's hot path; the cc-dispatcher's `realSdkQueryFactory`
// re-imports `fetchUserWorkspacePath` from this module so both paths
// share one cache and one source of truth.

import { readFile } from "fs/promises";
import path from "path";

import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "./observability";
import { isPathInWorkspace } from "./sandbox";

/** Per-conversation cap on inlined document body. Mirrors the legacy
 *  `agent-runner.ts MAX_INLINE_BYTES` (~12-15K tokens). Source of truth
 *  for the cc path. */
export const CONCIERGE_INLINE_CAP_BYTES = 50_000;

let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  if (!_supabase) _supabase = createServiceClient();
  return _supabase;
}

// Per-process memo for `users.workspace_path`. The workspace path is
// immutable per user lifetime — without this, every Concierge turn re-hits
// Supabase from `resolveConciergeDocumentContext` even though the answer
// never changes. Key: userId.
const _workspacePathCache = new Map<string, string>();

export async function fetchUserWorkspacePath(userId: string): Promise<string> {
  const cached = _workspacePathCache.get(userId);
  if (cached) return cached;
  const { data, error } = await supabase()
    .from("users")
    .select("workspace_path")
    .eq("id", userId)
    .single();
  if (error || !data?.workspace_path) {
    throw new Error("Workspace not provisioned");
  }
  const workspacePath = data.workspace_path as string;
  _workspacePathCache.set(userId, workspacePath);
  return workspacePath;
}

/** Test seam — tests that swap workspace_path between cases drain the
 *  cache to make the swap observable. Production callers never need this. */
export function _resetWorkspacePathCacheForTests(): void {
  _workspacePathCache.clear();
}

/**
 * Resolve a KB document's context for the Concierge system prompt.
 *
 * Returns an empty object on path-traversal rejection or on a path that
 * escapes the `knowledge-base/` subtree. Read errors degrade gracefully
 * to a kind-only result so the runner injects an instruction-shaped
 * Read directive without the body.
 */
export async function resolveConciergeDocumentContext(args: {
  userId: string;
  contextPath: string | null | undefined;
  providedContent?: string | null;
}): Promise<{
  artifactPath?: string;
  documentKind?: "pdf" | "text";
  documentContent?: string;
}> {
  const { userId, contextPath, providedContent } = args;
  if (!contextPath || contextPath.length === 0) return {};

  // Defense-in-depth: scope every Concierge document read to the
  // `knowledge-base/` subtree even though `isPathInWorkspace` already
  // blocks parent-traversal. Without this guard, a UI bug (or malicious
  // client) could request `attachments/<otherConvId>/secret.txt`,
  // `.git/**`, or any other workspace-relative file via a Concierge
  // start_session — `validateConversationContext` only blocks `..` /
  // null-bytes, while `validateContextPath` (used for `resumeByContextPath`)
  // already enforces the same prefix. This brings the two paths to parity.
  if (!contextPath.startsWith("knowledge-base/")) {
    return {};
  }

  const isPdf = contextPath.toLowerCase().endsWith(".pdf");
  // Caller-provided content wins (legacy parity). Skip the read entirely.
  if (providedContent && providedContent.length > 0) {
    if (isPdf) {
      // PDFs aren't usefully inlined as text; let the agent Read it.
      return { artifactPath: contextPath, documentKind: "pdf" };
    }
    return {
      artifactPath: contextPath,
      documentKind: "text",
      documentContent: providedContent.slice(0, CONCIERGE_INLINE_CAP_BYTES),
    };
  }

  if (isPdf) {
    return { artifactPath: contextPath, documentKind: "pdf" };
  }

  let workspacePath: string;
  try {
    workspacePath = await fetchUserWorkspacePath(userId);
  } catch (err) {
    // Per `cq-silent-fallback-must-mirror-to-sentry`: a missing workspace
    // path here means a degraded Concierge experience (no document body
    // injected) and we MUST be able to see this in Sentry.
    reportSilentFallback(err, {
      feature: "kb-concierge-context",
      op: "fetchUserWorkspacePath",
      extra: { userId, pathBasename: path.basename(contextPath) },
    });
    // Still surface the path so the router knows the scope.
    return { artifactPath: contextPath };
  }

  const fullPath = path.join(workspacePath, contextPath);
  if (!isPathInWorkspace(fullPath, workspacePath)) {
    // Path-traversal attempt — drop the path entirely (do not leak it
    // back into the prompt) and fall through to the bare router prompt.
    return {};
  }

  try {
    const content = await readFile(fullPath, "utf-8");
    if (content.length <= CONCIERGE_INLINE_CAP_BYTES) {
      return {
        artifactPath: contextPath,
        documentKind: "text",
        documentContent: content,
      };
    }
    // Too large to inline — let the agent Read it directly.
    return { artifactPath: contextPath, documentKind: "text" };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "kb-concierge-context",
      op: "readFile",
      // PII redaction: KB paths can carry user-identifying data
      // (`knowledge-base/customers/jane-doe.md`). Default Sentry
      // scrubbing matches on field NAMES (password / email / ssn) — it
      // does NOT scrub a `path` value. Log only the basename so the
      // failure is traceable without leaking the directory hierarchy.
      extra: { userId, pathBasename: path.basename(contextPath) },
    });
    return { artifactPath: contextPath, documentKind: "text" };
  }
}
