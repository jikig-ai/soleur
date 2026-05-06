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

import * as Sentry from "@sentry/nextjs";
import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "./observability";
import { isPathInWorkspace } from "./sandbox";
import {
  extractPdfText,
  type PdfExtractErrorClass,
} from "./pdf-text-extract";

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
  /**
   * Set when the in-process PDF extractor returned a typed failure
   * (`oversized_buffer | lazy_import_failed | encrypted | corrupted |
   * parse_error | empty_text`). Threaded into the runner so the system
   * prompt picks `buildPdfUnreadableDirective` (content-grounded reply)
   * instead of `buildPdfGatedDirective` (apt-get-cascade-prone Read path).
   */
  documentExtractError?: PdfExtractErrorClass;
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
    // Surface the path AND the kind so the runner emits the correct
    // assertive directive (gated PDF Read vs text Read). Without the kind,
    // emitConciergeDocumentResolutionBreadcrumb fires its suspicious-skip
    // warning on a path that's actually well-formed — just unfetchable.
    return {
      artifactPath: contextPath,
      documentKind: isPdf ? "pdf" : "text",
    };
  }

  const fullPath = path.join(workspacePath, contextPath);
  if (!isPathInWorkspace(fullPath, workspacePath)) {
    // Path-traversal attempt — drop the path entirely (do not leak it
    // back into the prompt) and fall through to the bare router prompt.
    return {};
  }

  if (isPdf) {
    // #3338 — server-side PDF text extraction. Read raw bytes (NOT utf-8)
    // and hand to the in-process pdfjs-dist parser. On success, inline the
    // body via documentContent so the agent never has to call Read (which
    // is the proximate cause of the apt-get/find Bash modal cascade). On
    // failure, fall through to the existing Read-directive branch and
    // mirror to Sentry so operators see the failure class.
    try {
      const buffer = await readFile(fullPath);
      const result = await extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES);
      const ok = !("error" in result);
      const errorClass: PdfExtractErrorClass | null = ok ? null : result.error;
      // #3338 Phase 5.1 — observability breadcrumb. Captures the extractor's
      // outcome on every cold-Query construction so operators can correlate
      // PDF-summary-quality with extraction shape (page count, truncation,
      // body size). PII redaction: log basename only — KB paths can carry
      // user-identifying directory hierarchy. The 2026-05-06 follow-up adds
      // `errorClass` so a future Sentry event names the failure class
      // directly without breadcrumb hunting.
      Sentry.addBreadcrumb({
        category: "cc-pdf-extractor",
        message: "extractPdfText completed",
        level: "info",
        data: {
          ok,
          errorClass,
          pageCount: ok ? result.pageCount : (result.pageCount ?? null),
          truncated: ok ? result.truncated : null,
          textBytes: ok ? result.text.length : 0,
          pathBasename: path.basename(contextPath),
        },
      });
      if (ok && result.text.length > 0) {
        return {
          artifactPath: contextPath,
          documentKind: "pdf",
          documentContent: result.text,
        };
      }
      if (!ok) {
        // Extraction failed (oversized, corrupted, encrypted, lazy-import
        // failure, parse error, OR empty_text). Mirror to Sentry tagged with
        // the failure class so operators see WHICH shape fired without
        // parsing breadcrumbs. `empty_text` gets a distinct `op` so
        // Hypothesis B (scanned PDFs) is filterable from Hypothesis A
        // (oversized) in the Sentry UI.
        const op =
          result.error === "empty_text"
            ? "extractPdfText.empty_text"
            : "extractPdfText";
        reportSilentFallback(new Error(`extractPdfText ${result.error}`), {
          feature: "kb-concierge-context",
          op,
          extra: {
            userId,
            pathBasename: path.basename(contextPath),
            errorClass: result.error,
            ...(result.pageCount !== undefined
              ? { pageCount: result.pageCount }
              : {}),
          },
        });
        return {
          artifactPath: contextPath,
          documentKind: "pdf",
          documentExtractError: result.error,
        };
      }
      // ok === true but text was empty. The extractor now classifies that as
      // `empty_text`, so this branch is unreachable — keep the safety return
      // for type narrowing and future-proofing.
      return { artifactPath: contextPath, documentKind: "pdf" };
    } catch {
      // readFile failed (missing file, permission denied) — let the agent
      // try Read. No Sentry mirror: this is not a degraded extractor, just
      // an absent file the UI may have stale-referenced.
      return { artifactPath: contextPath, documentKind: "pdf" };
    }
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
