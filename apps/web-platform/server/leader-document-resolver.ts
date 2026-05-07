// Leader-path document-context resolver (#3437). Sibling to
// `kb-document-resolver.ts`'s `resolveConciergeDocumentContext`.
//
// Differs from the Concierge resolver in two ways:
//   1. NO `knowledge-base/` prefix gate — leaders read across the whole
//      workspace (vision.md, attachments, project files), not just the KB
//      subtree. Containment is enforced by `isPathInWorkspace` alone.
//   2. Sentry feature tag is `"leader-context"` so operators can filter
//      leader-side fires from Concierge fires when both share
//      `category: "cc-pdf-extractor"`.
//
// Bridge fix for #3437: brings the leader path under the same partition +
// page-count gate as #3429 / PR #3430 added to the Concierge path.

import { readFile } from "fs/promises";
import path from "path";

import * as Sentry from "@sentry/nextjs";
import { reportSilentFallback } from "./observability";
import { isPathInWorkspace } from "./sandbox";
import {
  fetchUserWorkspacePath,
  CONCIERGE_INLINE_CAP_BYTES,
  type DocumentExtractMeta,
} from "./kb-document-resolver";
import {
  extractPdfText,
  extractPdfMetadata,
  LARGE_PDF_PAGE_THRESHOLD,
  PDF_FEATURE_TAGS,
  type PdfExtractErrorClass,
} from "./pdf-text-extract";

const LEADER_FEATURE_TAG = PDF_FEATURE_TAGS.LEADER;

export interface ResolvedLeaderDocumentContext {
  artifactPath?: string;
  documentKind?: "pdf" | "text";
  documentContent?: string;
  documentExtractError?: PdfExtractErrorClass;
  documentExtractMeta?: DocumentExtractMeta;
}

/**
 * Resolve a workspace document's context for the leader system prompt.
 *
 * Returns an empty object on a missing/empty path or on a path that escapes
 * the workspace via traversal. Read errors degrade gracefully to a kind-only
 * result so the runner injects the appropriate directive (gated / unreadable
 * / too-long) without the body.
 */
export async function resolveLeaderDocumentContext(args: {
  userId: string;
  contextPath: string | null | undefined;
  providedContent?: string | null;
  /**
   * Optional pre-resolved workspace path. The leader's `startAgentSession`
   * already SELECTs `workspace_path` (alongside repo_status/installation_id)
   * for the session — passing it through here avoids a second Supabase
   * round-trip via `fetchUserWorkspacePath` on every leader turn. When
   * omitted, the resolver falls back to the cached fetcher (Concierge
   * shape).
   */
  workspacePath?: string;
}): Promise<ResolvedLeaderDocumentContext> {
  const { userId, contextPath, providedContent, workspacePath: preResolvedPath } = args;
  if (!contextPath || contextPath.length === 0) return {};

  const isPdf = contextPath.toLowerCase().endsWith(".pdf");

  // Caller-provided content wins (legacy parity with Concierge resolver).
  if (providedContent && providedContent.length > 0) {
    if (isPdf) {
      return { artifactPath: contextPath, documentKind: "pdf" };
    }
    return {
      artifactPath: contextPath,
      documentKind: "text",
      documentContent: providedContent.slice(0, CONCIERGE_INLINE_CAP_BYTES),
    };
  }

  let workspacePath: string;
  if (preResolvedPath && preResolvedPath.length > 0) {
    workspacePath = preResolvedPath;
  } else {
    try {
      workspacePath = await fetchUserWorkspacePath(userId);
    } catch (err) {
      reportSilentFallback(err, {
        feature: LEADER_FEATURE_TAG,
        op: "fetchUserWorkspacePath",
        extra: { userId, pathBasename: path.basename(contextPath) },
      });
      return {
        artifactPath: contextPath,
        documentKind: isPdf ? "pdf" : "text",
      };
    }
  }

  const fullPath = path.join(workspacePath, contextPath);
  if (!isPathInWorkspace(fullPath, workspacePath)) {
    return {};
  }

  if (isPdf) {
    let buffer: Buffer;
    try {
      buffer = await readFile(fullPath);
    } catch (err) {
      const errno = (err as NodeJS.ErrnoException)?.code ?? null;
      const basename = path.basename(contextPath);
      Sentry.addBreadcrumb({
        category: "cc-pdf-extractor",
        message: "readFile failed before extractPdfText",
        level: "warning",
        data: {
          ok: false,
          errorClass: "read_failed",
          errno,
          pathBasename: basename,
        },
      });
      // ENOENT is the expected "user deleted/renamed the file" case;
      // suppress the Sentry mirror but keep the breadcrumb.
      if (errno !== "ENOENT") {
        reportSilentFallback(err, {
          feature: LEADER_FEATURE_TAG,
          op: "extractPdfText.readFile",
          extra: {
            userId,
            pathBasename: basename,
            errorClass: "read_failed",
            errno,
          },
        });
      }
      return {
        artifactPath: contextPath,
        documentKind: "pdf",
        documentExtractError: "read_failed",
      };
    }

    const result = await extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES, {
      featureTag: LEADER_FEATURE_TAG,
    });

    if ("error" in result) {
      Sentry.addBreadcrumb({
        category: "cc-pdf-extractor",
        message: "extractPdfText completed",
        level: "info",
        data: {
          ok: false,
          errorClass: result.error,
          pageCount: result.pageCount ?? null,
          truncated: null,
          textBytes: 0,
          pathBasename: path.basename(contextPath),
        },
      });
      const op =
        result.error === "empty_text"
          ? "extractPdfText.empty_text"
          : "extractPdfText";
      reportSilentFallback(new Error(`extractPdfText ${result.error}`), {
        feature: LEADER_FEATURE_TAG,
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

      // Page-count gate (#3437 leader symmetry of #3429): when
      // oversized_buffer fires, do a metadata-only pdfjs read to obtain
      // numPages cheaply. If the PDF exceeds the threshold, surface
      // too_many_pages so the runner picks `buildPdfTooLongDirective`
      // instead of fanning the SDK Read tool.
      if (result.error === "oversized_buffer") {
        const meta = await extractPdfMetadata(buffer);
        Sentry.addBreadcrumb({
          category: "cc-pdf-extractor",
          message: "extractPdfMetadata completed",
          level: "info",
          data: {
            ok: meta.ok,
            op: "metadataRead",
            numPages: meta.ok ? meta.numPages : null,
            reason: meta.ok ? null : meta.reason,
            pathBasename: path.basename(contextPath),
          },
        });
        if (meta.ok && meta.numPages > LARGE_PDF_PAGE_THRESHOLD) {
          return {
            artifactPath: contextPath,
            documentKind: "pdf",
            documentExtractError: "too_many_pages",
            documentExtractMeta: { numPages: meta.numPages },
          };
        }
      }

      return {
        artifactPath: contextPath,
        documentKind: "pdf",
        documentExtractError: result.error,
      };
    }

    Sentry.addBreadcrumb({
      category: "cc-pdf-extractor",
      message: "extractPdfText completed",
      level: "info",
      data: {
        ok: true,
        errorClass: null,
        pageCount: result.pageCount,
        truncated: result.truncated,
        textBytes: result.text.length,
        pathBasename: path.basename(contextPath),
      },
    });
    if (result.text.length > 0) {
      return {
        artifactPath: contextPath,
        documentKind: "pdf",
        documentContent: result.text,
      };
    }
    return { artifactPath: contextPath, documentKind: "pdf" };
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
    // Too large to inline — runner emits a Read directive against the
    // resolved absolute path.
    return { artifactPath: contextPath, documentKind: "text" };
  } catch (err) {
    // Leader divergence from Concierge: rather than silently dropping the
    // context (Concierge's #3353 fix returns `{}`), preserve the legacy
    // leader behavior of falling through to an assertive Read directive
    // by returning kind=text without content. ENOENT is suppressed from
    // Sentry per cq-silent-fallback-must-mirror-to-sentry's "first-time
    // 404" exemption (file deletion is expected drift).
    const errno = (err as NodeJS.ErrnoException)?.code ?? null;
    if (errno !== "ENOENT") {
      reportSilentFallback(err, {
        feature: LEADER_FEATURE_TAG,
        op: "readFile",
        extra: {
          userId,
          pathBasename: path.basename(contextPath),
          errno,
        },
      });
    }
    return { artifactPath: contextPath, documentKind: "text" };
  }
}
