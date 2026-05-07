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
  extractPdfMetadata,
  LARGE_PDF_PAGE_THRESHOLD,
  type PdfExtractErrorClass,
} from "./pdf-text-extract";

/**
 * Structured metadata passed alongside `documentExtractError` for failure
 * classes that carry per-failure details. Currently only `too_many_pages`
 * uses `numPages`; the type is open for future extension.
 */
export interface DocumentExtractMeta {
  numPages?: number;
}

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
   * parse_error | empty_text | read_failed | too_many_pages`). Threaded
   * into the runner so the system prompt picks the correct directive
   * factory (gated / unreadable / too-long).
   */
  documentExtractError?: PdfExtractErrorClass;
  /**
   * Per-failure structured metadata. Currently only set with
   * `too_many_pages` (`numPages`), where the runner injects the count
   * into the directive copy.
   */
  documentExtractMeta?: DocumentExtractMeta;
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
      // #3338 Phase 5.1 — observability breadcrumb. Captures the extractor's
      // outcome on every cold-Query construction so operators can correlate
      // PDF-summary-quality with extraction shape (page count, truncation,
      // body size). PII redaction: log basename only — KB paths can carry
      // user-identifying directory hierarchy. The 2026-05-06 follow-up adds
      // `errorClass` so a future Sentry event names the failure class
      // directly without breadcrumb hunting.
      if ("error" in result) {
        // Extraction failed (oversized, corrupted, encrypted, lazy-import
        // failure, parse error, OR empty_text). Mirror to Sentry tagged with
        // the failure class so operators see WHICH shape fired without
        // parsing breadcrumbs. `empty_text` gets a distinct `op` so
        // Hypothesis B (scanned PDFs) is filterable from Hypothesis A
        // (oversized) in the Sentry UI.
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

        // 2026-05-07 follow-up to #3429: page-count gate on the
        // soft-route. When `oversized_buffer` fires (the >24MB extractor
        // refusal — see MAX_AGENT_READABLE_PDF_SIZE), do a metadata-only
        // pdfjs read to obtain numPages cheaply. PDFs with too many
        // pages would fanout the SDK Read tool's 20-page-per-request cap
        // (~21 sequential calls for a 400-page book), exceeding the 90s
        // idle-reaper window and surfacing "Agent stopped responding"
        // to the user. Surface a typed `too_many_pages` HARD class so
        // the runner routes to `buildPdfTooLongDirective` (specific
        // refusal naming the page count, offering chapter-share/TOC-paste
        // recovery) instead of the gated Read directive.
        //
        // Fail-closed on every metadata-read error path: the gate
        // augments the existing partition; if metadata can't be read
        // (oversized beyond the 60MB ceiling, parse failure, timeout)
        // we fall through to the existing soft-route. Worst case the
        // user gets today's behavior — never worse.
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
          // Below threshold OR metadata-read failed → fall through to
          // the existing soft-route (oversized_buffer → buildPdfGatedDirective).
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
      // Unreachable under the current extractor contract: an empty text
      // body is now classified as `{ error: "empty_text" }` upstream and
      // handled in the failure branch above. Keep this terminal return as
      // a tight type-narrowing guard so a future contract regression
      // (extractor reverts to returning `{ text: "" }` on success) cannot
      // produce a literal-undefined `documentContent`.
      return { artifactPath: contextPath, documentKind: "pdf" };
    } catch (err) {
      // 2026-05-06 follow-up to #3353 — Bug B in plan
      // 2026-05-06-fix-sidebar-pdf-summarize-out-of-boundary-plan.md.
      // Pre-fix this catch returned a bare `{ artifactPath, documentKind:
      // "pdf" }` (no `documentExtractError`), which routed the runner to
      // `buildPdfGatedDirective`. The agent then called
      // `Read({ file_path: contextPath })` with a workspace-relative
      // path; the sandbox-hook resolved it against the Next.js process
      // CWD, denied with "outside workspace boundary", and the model
      // paraphrased that to the end user (#3376 reproduction).
      //
      // Surface the typed `read_failed` class so the runner picks
      // `buildPdfUnreadableDirective` (content-grounded "I can't read
      // this PDF" reply) instead. Mirror to Sentry per
      // `cq-silent-fallback-must-mirror-to-sentry` — `read_failed` IS
      // alarming when it fires (real upload-vs-context_path drift).
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
      // Per `cq-silent-fallback-must-mirror-to-sentry`'s "first-time
      // 404" exemption (perf review #3384 P2-1): an ENOENT here is the
      // expected "user deleted/renamed the file while sidebar was open"
      // case — it produces a graceful `read_failed` reply, not a
      // production incident. Keep the breadcrumb (free, in-process) so
      // an event captured later in the same scope retains the context;
      // skip the Sentry event so a deletion sweep doesn't quota-storm.
      // EACCES / EIO / EBUSY etc. ARE alarming and still mirror.
      if (errno !== "ENOENT") {
        reportSilentFallback(err, {
          feature: "kb-concierge-context",
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
    // 2026-05-06 follow-up to #3353 — text-file twin of Bug B.
    // Pre-fix this catch returned `{ artifactPath, documentKind: "text" }`
    // which routed the runner to a text Read directive injecting the
    // workspace-relative path; the agent's Read attempt tripped the same
    // sandbox-deny path Bug A1+A2 covered for PDFs. Drop to no-context
    // (`{}`) instead — the runner emits the bare router prompt and the
    // model produces a generic "I can't find that document" reply
    // without leaking sandbox internals. Text files don't have an
    // apt-get-cascade analog, so a parallel `text_read_failed` directive
    // would be ROI-negative.
    reportSilentFallback(err, {
      feature: "kb-concierge-context",
      op: "readFile",
      // PII redaction: KB paths can carry user-identifying data
      // (`knowledge-base/customers/jane-doe.md`). Default Sentry
      // scrubbing matches on field NAMES (password / email / ssn) — it
      // does NOT scrub a `path` value. Log only the basename so the
      // failure is traceable without leaking the directory hierarchy.
      extra: {
        userId,
        pathBasename: path.basename(contextPath),
        errno: (err as NodeJS.ErrnoException)?.code ?? null,
      },
    });
    return {};
  }
}
