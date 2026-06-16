// DSAR Art. 15 + Art. 20 self-serve export worker — Phase 5
// (feat-dsar-art15-export-endpoint #3637, plan rev-2).
//
// Architecture (per plan rev-2 C1 + Q-credential):
//   - Worker is `service_role` (NOT per-user JWT-at-rest, NOT per-user
//     JWT-mint-at-runtime). Per-row `WHERE owner_id = $1` is the
//     planner-level isolation (file-parse lint enforces presence per
//     AC30). `assertReadScope(rows, expectedUserId, table)` is the
//     runtime invariant that fires `CrossTenantViolation` + P0 Sentry
//     mirror if any row's owner ≠ expected (AC12 + FR9).
//   - In-process `setInterval` poller mirroring agent-runner.ts:698.
//     Single-instance per rate-limiter.ts:255-262; all three migrate
//     together when infra scales.
//   - On-startup orphan reset per S3 (replaces TR12 pg_cron).
//   - Per-job hard timeout via `AbortController` + manual `setTimeout`
//     per `cq-abort-signal-timeout-vs-fake-timers`.
//   - Disk-then-upload archive per Phase 0 spike outcome + ADR-028 §D4:
//     archive built to local tmpfile, then streamed via raw `fetch`
//     with `duplex: 'half'` from `fs.createReadStream()`. supabase-js
//     `upload(WebReadableStream)` buffers the body (Δ RSS ≈ 1.09×).
//
// Data sources (all in v1):
//   - SQL tables in `DSAR_TABLE_ALLOWLIST` (incl. nested via `joinVia`).
//   - `chat-attachments/<userId>/...` binaries via Storage list +
//     path-prefix guard (fail-job-loud on path-traversal per AC26).
//   - `/workspaces/<userId>/*` files via `O_NOFOLLOW + fstat` ino
//     verify (skip-with-manifest on symlink/ino-mismatch per AC26).
//   - Manifest LAST with serialization conventions per AC23.

import {
  createReadStream,
  statSync,
  openSync,
  fstatSync,
  closeSync,
  constants as fsConstants,
} from "node:fs";
import { mkdir, rm, stat, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, posix as posixPath } from "node:path";
import { createHash, randomBytes } from "node:crypto";
import { Readable, PassThrough } from "node:stream";
import { pipeline } from "node:stream/promises";
// archiver@8 is ESM-only with NO default export (breaking change from v7);
// `import archiver from "archiver"` synthesizes an `undefined` default under
// Node's `require(esm)` interop, so `archiver("zip", ...)` throws
// `(0, default) is not a function` under vitest (and would throw in any
// caller path that actually reaches `buildArchiveToDisk`). @types/archiver
// is still pinned at v7 (factory `export =` shape), so we cast the v8
// runtime namespace to the v7-aware `Archiver` instance type. Pattern
// matches `scripts/spike/dsar-streaming-upload.ts:53-58`.
import type { Archiver } from "archiver";
import * as ArchiverRuntime from "archiver";
type ZipArchiveCtor = new (opts: { zlib?: { level?: number } }) => Archiver;
const ZipArchive = (
  ArchiverRuntime as unknown as { ZipArchive: ZipArchiveCtor }
).ZipArchive;
import { createWriteStream } from "node:fs";

import { createServiceClient, serverUrl } from "@/lib/supabase/service";
import { mirrorCrossTenantViolation, hashUserId } from "./observability";
import {
  sendDsarExportReadyEmail,
  sendDsarExportFailedEmail,
} from "./notifications";
import { createChildLogger } from "./logger";
import {
  DSAR_TABLE_ALLOWLIST,
  type DsarTableSpec,
} from "./dsar-export-allowlist";
import { enumerateCoUploaderAttachments } from "./dsar-export-co-uploader";
import { workspacePathForWorkspaceId } from "./workspace-resolver";

const log = createChildLogger("dsar-export");

/**
 * Resolve the on-disk workspace root used by the DSAR workspace-files
 * enumerator for `subjectUserId`.
 *
 * #5005: this is id-keyed (`<WORKSPACES_ROOT>/<subjectUserId>`) via
 * `workspacePathForWorkspaceId`, NOT read from the subject's legacy
 * `users.workspace_path` column — that column is stale/empty for accounts
 * provisioned after the ADR-044 `users → workspaces` relocation, which silently
 * truncated the workspace files from the export (an incomplete Art. 15/20
 * response).
 *
 * Resolver-selection (load-bearing): a DSAR is per-subject, so the SOLO/N2 path
 * (`workspace_id == user_id`) is correct — NOT the active-workspace resolver. A
 * member's personal data lives in their solo workspace; resolving their *active*
 * (possibly shared) workspace would over-export the owner's files into the
 * member's DSAR — a cross-tenant leak. The single-arg signature (no supabase
 * client, no active claim) makes that over-export structurally impossible.
 */
export function resolveDsarWorkspacePath(subjectUserId: string): string {
  return workspacePathForWorkspaceId(subjectUserId);
}

// ---------------------------------------------------------------------------
// Phase 2 primitives — re-exported as-is so Phase 2's tests + the
// per-row WHERE lint keep pointing at the same surface.
// ---------------------------------------------------------------------------

export class CrossTenantViolation extends Error {
  readonly name = "CrossTenantViolation";
  readonly tableName: string;
  readonly expectedUserId: string;
  readonly offendingUserId: string | null;

  constructor(
    tableName: string,
    expectedUserId: string,
    offendingUserId: string | null,
  ) {
    super(
      `Cross-tenant violation in table "${tableName}": ` +
        `row owned by ${offendingUserId ?? "(no owner_id field)"} ` +
        `appeared in a read scoped to ${expectedUserId}`,
    );
    this.tableName = tableName;
    this.expectedUserId = expectedUserId;
    this.offendingUserId = offendingUserId;
  }
}

export interface AssertReadScopeOptions {
  ownerField?: string;
}

/**
 * Raised when the bundle exceeds DSAR_EXPORT_SIZE_CAP_MB. Mapped by
 * runExport to failure_reason='bundle_too_large' so the user-facing
 * email points to the operator-fallback flow instead of telling them
 * to retry.
 */
export class BundleTooLargeError extends Error {
  readonly name = "BundleTooLargeError";
}

export function assertReadScope<T extends Record<string, unknown>>(
  rows: T[],
  expectedUserId: string,
  tableName: string,
  options: AssertReadScopeOptions = {},
): T[] {
  const ownerField = options.ownerField ?? "owner_id";
  for (const row of rows) {
    const owner = row[ownerField];
    if (typeof owner !== "string" || owner !== expectedUserId) {
      const offending = typeof owner === "string" ? owner : null;
      const err = new CrossTenantViolation(
        tableName,
        expectedUserId,
        offending,
      );
      mirrorCrossTenantViolation(offending, expectedUserId, tableName, err);
      throw err;
    }
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Art. 15(4) author-only redaction primitives (#4319).
//
// Per the plan's TR1: helpers live inside dsar-export.ts (NOT a separate
// module). Pure, side-effect-free, in-place mutation; returns `true` if
// redaction was applied so the call site can count.
//
// Field list is closed (`content`, `tool_calls`, `usage`, `draft_preview`,
// `action_class`). Any future migration that adds a free-text personal-
// data column to `messages` MUST sweep this file per
// `hr-write-boundary-sentinel-sweep-all-write-sites`.
// ---------------------------------------------------------------------------

export function redactRow<T extends Record<string, unknown>>(
  row: T,
  shouldRedact: boolean,
  fieldsToNull: readonly (keyof T)[],
  pseudonymCol?: keyof T,
  pseudonym?: string,
): boolean {
  if (!shouldRedact) return false;
  for (const f of fieldsToNull) {
    (row as Record<string, unknown>)[f as string] = null;
  }
  if (pseudonymCol && pseudonym !== undefined) {
    (row as Record<string, unknown>)[pseudonymCol as string] = pseudonym;
  }
  return true;
}

/**
 * Per-bundle pseudonymous identifier for a non-subject author.
 * `salt` is minted via crypto.randomBytes(32) at exportSqlTable entry
 * and held in closure — NEVER persisted to manifest / audit / log.
 * Returns `member_<hex12>` (48-bit collision space; birthday-safe past
 * ~10^6 distinct authors per bundle).
 */
export function pseudonymiseUserId(rawUserId: string, salt: Buffer): string {
  const h = createHash("sha256");
  h.update(salt);
  h.update(rawUserId);
  return `member_${h.digest("hex").slice(0, 12)}`;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const JOB_HARD_TIMEOUT_MS = 30 * 60 * 1000; // 30 min
const POLLER_INTERVAL_MS = 5 * 1000;
const SIGNED_URL_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const STORAGE_BUCKET = "dsar-exports";
// Bumped to 1.1.0 by #4319 — adds top-level `redactions[]` field
// disclosing Art. 15(4) author-only redactions to the subject (EDPB
// Guidelines 01/2022 §176). Paired bump in dsar-export-oversize.sh:130.
const MANIFEST_SCHEMA_VERSION = "1.2.0";
const SIZE_CAP_BYTES =
  (Number(process.env.DSAR_EXPORT_SIZE_CAP_MB) || 1024) * 1024 * 1024;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface EnqueueExportInput {
  userId: string;
  workspaceId: string;
  sessionId: string;
  reauthEventId: string;
  requesterIp: string;
  userAgent: string;
}

export interface EnqueueExportResult {
  jobId: string;
  acknowledgedAt: string;
}

interface ManifestFileEntry {
  path: string;
  included: boolean;
  article?: "15" | "15+20";
  source_table?: string;
  row_count?: number;
  sha256?: string;
  bytes?: number;
  reason?: string;
  redacted?: boolean;
  redaction_reason?: string;
  uploader_pseudonym?: string;
}

interface ManifestRoot {
  schema_version: string;
  generated_at: string; // ISO 8601 with UTC offset (Z)
  user_id: string;
  job_id: string;
  serialization: {
    timestamp_format: "ISO 8601 with UTC offset (Z)";
    bytea_encoding: "base64";
    null_encoding: "JSON null";
    object_keys: "sorted alphabetically";
  };
  files: ManifestFileEntry[];
  excluded_files: ManifestFileEntry[];
  /**
   * Art. 15(4) author-only redactions applied to this bundle.
   * Disclosed to the subject per EDPB Guidelines 01/2022 §176.
   * One entry per table that had at least one redacted row.
   */
  redactions: { path: string; reason: string; count: number }[];
}

// ---------------------------------------------------------------------------
// JSON serialization with AC23 conventions:
//   - ISO 8601 with UTC offset (Date.toISOString -> "Z")
//   - base64 for bytea (Buffer / Uint8Array)
//   - JSON null for SQL NULL (default JSON.stringify behavior)
//   - sorted object keys for deterministic SHA-256
// ---------------------------------------------------------------------------

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return (
    typeof v === "object" &&
    v !== null &&
    !Array.isArray(v) &&
    !(v instanceof Date) &&
    !(v instanceof Uint8Array)
  );
}

function dsarNormalize(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (value instanceof Uint8Array) {
    return Buffer.from(value).toString("base64");
  }
  if (Buffer.isBuffer(value)) {
    return value.toString("base64");
  }
  if (Array.isArray(value)) return value.map(dsarNormalize);
  if (isPlainObject(value)) {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = dsarNormalize(value[key]);
    }
    return out;
  }
  return value;
}

export function dsarStringify(value: unknown): string {
  return JSON.stringify(dsarNormalize(value), null, 2);
}

function sha256Hex(buf: Buffer | string): string {
  const h = createHash("sha256");
  h.update(buf);
  return h.digest("hex");
}

// ---------------------------------------------------------------------------
// SQL table enumeration — per-row WHERE + assertReadScope on every read.
//
// The repeated `service.from(<table>).select("*").eq(<owner>, expectedUserId)`
// pattern is REQUIRED by the file-parse lint
// `dsar-worker-per-row-where.test.ts` (AC30 + C1). Refactoring this loop
// into a single `service.from(table)` helper that takes a column name
// would defeat the lint — the lint matches literal `.eq("<owner>", ...)`
// at every `service.from("<allowlisted-table>").select(...)` chain.
//
// For `joinVia` tables (messages, message_attachments), there is no
// direct owner column. The worker:
//   1. Fetches the parent ID set with the per-row WHERE on the parent.
//   2. Fetches the child rows scoped to those parent IDs via `.in(...)`.
//   3. Re-checks owner by service-role re-fetching the parent's owner
//      column for every returned child row and asserting equality. This
//      is `assertReadScope` adapted for joins.
// ---------------------------------------------------------------------------

interface TableExportResult {
  table: string;
  spec: DsarTableSpec;
  rows: Record<string, unknown>[];
  // Error-mode: if the read failed for any reason, the worker fails
  // the entire job loud rather than silently skipping a table (Art. 15
  // completeness).
  error?: Error;
  // Art. 15(4) author-only redaction count for this table (#4319).
  // Surfaced into manifest.redactions[] by buildArchiveToDisk.
  redactionCount?: number;
}

// Post-mig 059 audit (#4319 Phase 0.3): the messages_workspace_member_insert
// RLS policy gates INSERT on is_workspace_member(workspace_id, auth.uid())
// — NOT on user_id matching conversation owner — and every server INSERT
// path (cc-dispatcher.ts, agent-runner.ts, kb-drift-ingest, cfo-on-payment-
// failed, github-on-event) omits `user_id` (defaults to NULL). A non-
// subject CAN write `user_id IS NULL` rows into a foreign-owned
// conversation. Fail-closed default: REDACT legacy NULL rows.
const LEGACY_NULL_IS_SUBJECT = false;

// Field list redacted on foreign-author messages. Closed set — any
// future migration adding a free-text or namespace-leaking column to
// `messages` MUST sweep this list per
// `hr-write-boundary-sentinel-sweep-all-write-sites`. The companion
// sentinel test at apps/web-platform/test/dsar-message-redact-fields-
// sweep.test.ts enforces this gate at CI time by parsing migration
// files for ALTER TABLE messages ADD COLUMN of text/jsonb shapes and
// asserting each new column appears here or in MESSAGE_NON_REDACT_
// ALLOWLIST below.
//
// Field rationale per column (Art. 15(4) review #4351 cross-reconcile):
//   content           — free-text body (M1 leak vector)
//   tool_calls        — jsonb — tool args + results (free-text PII)
//   usage             — jsonb (mig 040) — input_summary / result_summary
//                       embed conversation context
//   draft_preview     — text (mig 046) — pre-send free-text snippet
//   action_class      — text (mig 051) — open namespace, can encode
//                       Art. 9 special-category indicators
//   tier              — text (mig 046) — business tier signal about the
//                       third party (e.g., "external_brand_critical")
//   source            — text (mig 046) — pipeline source identifier
//   owning_domain     — text (mig 046) — third party's product surface
//                       (e.g., "cfo", "github", "legal")
//   urgency           — text (mig 046) — free-text urgency phrase
//                       ("client breach Tuesday")
//   trust_tier        — text (mig 046) — third party's trust band
//   source_ref        — text (mig 052) — namespace-id pattern such as
//                       `pr-<org>:<repo>:<number>` or `cve-<id>`; leaks
//                       third-party GitHub orgs / repos / CVE refs
//   leader_id         — text (mig 010) — domain leader identifier; may
//                       carry email-shaped or name-shaped values
//   template_id       — text (mig 053) — template identifier; usage
//                       pattern signal about the third party
const MESSAGE_REDACT_FIELDS = [
  "content",
  "tool_calls",
  "usage",
  "draft_preview",
  "action_class",
  "tier",
  "source",
  "owning_domain",
  "urgency",
  "trust_tier",
  "source_ref",
  "leader_id",
  "template_id",
] as const;

// Companion allowlist consumed by the migration-sweep sentinel test —
// every column on `public.messages` that is NEITHER in
// MESSAGE_REDACT_FIELDS NOR in this allowlist trips CI. Structural
// columns are safe to surface on a foreign-author row because they
// describe the bundle's own shape (thread position, the subject's
// workspace, timestamps, cache token counts) rather than the third
// party's content or namespace.
export const MESSAGE_NON_REDACT_ALLOWLIST = [
  "id",
  "conversation_id",
  "workspace_id",
  "user_id",
  "role",
  "status",
  "created_at",
  "cache_read_input_tokens",
  "cache_creation_input_tokens",
  // message_kind (mig 105) — structural discriminator ('turn_summary' vs
  // NULL='text'); describes the row's own shape, not third-party content,
  // so it is safe to surface on a foreign-author row. The summary BODY
  // lives in `content` (already redacted above), not here.
  "message_kind",
] as const;

export { MESSAGE_REDACT_FIELDS };

const ATTACHMENT_REDACT_FIELDS = ["storage_path", "filename"] as const;

export const REDACTION_REASON = "art-15-4-rights-of-others";

/**
 * Exported for the cross-tenant integration test (Phase 10).
 * Not part of the public worker API — callers should go through
 * `runExport` which orchestrates table reads + archive + upload.
 */
export async function exportSqlTable(
  // Per AC30, the per-row-WHERE lint expects `service.from("<table>")
  // .select(...).eq(<owner>, expectedUserId)` at every literal call
  // site. The worker enumerates each allowlisted table EXPLICITLY
  // below so the lint can pattern-match.
  expectedUserId: string,
  pseudonymSalt: Buffer,
  signal: AbortSignal,
): Promise<TableExportResult[]> {
  const service = createServiceClient();
  const results: TableExportResult[] = [];

  // -- users -------------------------------------------------------------
  {
    const { data, error } = await service
      .from("users")
      .select("*")
      .eq("id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`users read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "users", { ownerField: "id" });
    results.push({ table: "users", spec: DSAR_TABLE_ALLOWLIST.users, rows });
  }

  // -- api_keys ----------------------------------------------------------
  {
    const { data, error } = await service
      .from("api_keys")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`api_keys read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "api_keys", {
      ownerField: "user_id",
    });
    results.push({
      table: "api_keys",
      spec: DSAR_TABLE_ALLOWLIST.api_keys,
      rows,
    });
  }

  // -- workspace ID prefetch (for conversations UNION, #4358) -----------
  // Lightweight prefetch of workspace_ids the subject is a member of,
  // used to widen the conversations query below. The full
  // workspace_members export (`select("*")`) still runs in its own
  // section later; this prefetch only pulls the FK column needed for
  // the PostgREST `.or()` predicate.
  let prefetchWorkspaceIds: string[] = [];
  {
    const { data, error } = await service
      .from("workspace_members")
      .select("workspace_id")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(
        `workspace_members (conversations prefetch) read failed: ${error.message}`,
      );
    prefetchWorkspaceIds = ((data ?? []) as { workspace_id?: unknown }[])
      .map((r) => r.workspace_id)
      .filter((v): v is string => typeof v === "string");
  }

  // -- conversations -----------------------------------------------------
  // Art. 15 completeness (#4358): UNION of subject-owned conversations
  // (user_id = expectedUserId) AND conversations the subject participates
  // in via workspace membership (workspace_id IN prefetchWorkspaceIds).
  // This captures messages the subject authored in co-member-owned
  // conversations within shared workspaces. When prefetchWorkspaceIds is
  // empty (no workspace memberships), falls back to the direct-owner
  // predicate only.
  let conversationIds: string[] = [];
  {
    // visibility-sweep-audit: owner-scoped — DSAR exports are per-user per Art. 15
    // Per-row WHERE lint (AC30) requires the predicate (`.or()` or
    // `.eq()`) to appear in the same chain as the `.from()` call. The
    // ternary below keeps both paths in the single statement the lint
    // parses.
    const { data, error } =
      prefetchWorkspaceIds.length > 0
        ? await service
            .from("conversations")
            .select("*")
            .or(
              `user_id.eq.${expectedUserId},workspace_id.in.(${prefetchWorkspaceIds.join(",")})`,
            )
        : await service
            .from("conversations")
            .select("*")
            .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`conversations read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    // Two-arm cross-tenant assertion (#4358): every returned row MUST
    // satisfy (user_id = expectedUserId) OR (workspace_id is in the
    // subject's prefetched workspace set). Fail-closed via
    // CrossTenantViolation if neither arm holds.
    const wsSet = new Set(prefetchWorkspaceIds);
    for (const row of rows) {
      const isOwned =
        typeof row.user_id === "string" && row.user_id === expectedUserId;
      const isParticipated =
        typeof row.workspace_id === "string" && wsSet.has(row.workspace_id);
      if (!isOwned && !isParticipated) {
        const err = new CrossTenantViolation(
          "conversations",
          expectedUserId,
          typeof row.user_id === "string" ? row.user_id : null,
        );
        mirrorCrossTenantViolation(
          typeof row.user_id === "string" ? row.user_id : null,
          expectedUserId,
          "conversations",
          err,
        );
        throw err;
      }
    }
    conversationIds = rows
      .map((r) => r.id)
      .filter((v): v is string => typeof v === "string");
    results.push({
      table: "conversations",
      spec: DSAR_TABLE_ALLOWLIST.conversations,
      rows,
    });
  }

  // -- messages (joinVia conversations) ----------------------------------
  // Per-row Art. 15(4) redaction predicate (#4319): messages authored
  // by a non-subject within a subject-accessible conversation are returned
  // as structural shells (content + namespace columns nulled, raw
  // user_id replaced with a per-bundle salt-scoped pseudonym).
  // CrossTenantViolation runs BEFORE the redaction predicate (TR3
  // invariant) so the violation surface is unchanged.
  // #4358: conversationIds now includes both subject-owned AND
  // workspace-participated conversations (via the UNION above).
  let messageIds: string[] = [];
  // Allowlist (#4319): IDs of messages authored by the subject. The
  // attachments block redacts any attachment whose message_id is NOT
  // in this set (orphan / foreign-author parents → fail-closed).
  const subjectAuthoredMessageIds = new Set<string>();
  if (conversationIds.length > 0) {
    const { data, error } = await service
      .from("messages")
      .select("*")
      .in("conversation_id", conversationIds);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`messages read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    // No direct owner_id; verify every message's conversation_id is in
    // the set we already proved is scope-verified (owned OR workspace-
    // participated, #4358). If a service-role glitch returned a row
    // whose conversation_id is NOT in our scope-verified set, raise
    // CrossTenantViolation.
    const scopedConvSet = new Set(conversationIds);
    for (const row of rows) {
      if (typeof row.conversation_id !== "string" || !scopedConvSet.has(row.conversation_id)) {
        const err = new CrossTenantViolation(
          "messages",
          expectedUserId,
          null,
        );
        mirrorCrossTenantViolation(null, expectedUserId, "messages", err);
        throw err;
      }
    }
    messageIds = rows
      .map((r) => r.id)
      .filter((v): v is string => typeof v === "string");

    // Art. 15(4) per-row predicate. Runs AFTER cross-tenant assertion.
    let messagesRedactionCount = 0;
    for (const row of rows) {
      const rawUserId = row.user_id;
      const isSubjectAuthored =
        rawUserId === expectedUserId ||
        (rawUserId === null && LEGACY_NULL_IS_SUBJECT);
      if (isSubjectAuthored && typeof row.id === "string") {
        subjectAuthoredMessageIds.add(row.id);
      }
      const pseudonym = isSubjectAuthored
        ? undefined
        : typeof rawUserId === "string"
          ? pseudonymiseUserId(rawUserId, pseudonymSalt)
          : // Legacy NULL under fail-closed: redact content, leave user_id
            // as the actual NULL (no pseudonym needed for a NULL source).
            undefined;
      const applied = redactRow(
        row,
        !isSubjectAuthored,
        MESSAGE_REDACT_FIELDS,
        pseudonym !== undefined ? "user_id" : undefined,
        pseudonym,
      );
      if (applied) messagesRedactionCount += 1;
    }

    results.push({
      table: "messages",
      spec: DSAR_TABLE_ALLOWLIST.messages,
      rows,
      redactionCount: messagesRedactionCount,
    });
  } else {
    results.push({
      table: "messages",
      spec: DSAR_TABLE_ALLOWLIST.messages,
      rows: [],
      redactionCount: 0,
    });
  }

  // -- message_attachments (joinVia messages) ----------------------------
  // Art. 15(4) allowlist semantic (#4319): an attachment is preserved
  // ONLY when its parent message_id is in `subjectAuthoredMessageIds`.
  // Foreign-author parents and any parent we couldn't classify (orphan
  // shape) → redact storage_path + filename. Fail-closed.
  if (messageIds.length > 0) {
    const { data, error } = await service
      .from("message_attachments")
      .select("*")
      .in("message_id", messageIds);
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(`message_attachments read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    const ownedMsgSet = new Set(messageIds);
    for (const row of rows) {
      if (typeof row.message_id !== "string" || !ownedMsgSet.has(row.message_id)) {
        const err = new CrossTenantViolation(
          "message_attachments",
          expectedUserId,
          null,
        );
        mirrorCrossTenantViolation(
          null,
          expectedUserId,
          "message_attachments",
          err,
        );
        throw err;
      }
    }

    // Allowlist predicate. Runs AFTER cross-tenant assertion.
    let attachmentRedactionCount = 0;
    for (const row of rows) {
      const parentId =
        typeof row.message_id === "string" ? row.message_id : "";
      const shouldRedact = !subjectAuthoredMessageIds.has(parentId);
      const applied = redactRow(
        row,
        shouldRedact,
        ATTACHMENT_REDACT_FIELDS,
      );
      if (applied) attachmentRedactionCount += 1;
    }

    results.push({
      table: "message_attachments",
      spec: DSAR_TABLE_ALLOWLIST.message_attachments,
      rows,
      redactionCount: attachmentRedactionCount,
    });
  } else {
    results.push({
      table: "message_attachments",
      spec: DSAR_TABLE_ALLOWLIST.message_attachments,
      rows: [],
      redactionCount: 0,
    });
  }

  // -- kb_share_links ----------------------------------------------------
  {
    const { data, error } = await service
      .from("kb_share_links")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`kb_share_links read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "kb_share_links", {
      ownerField: "user_id",
    });
    results.push({
      table: "kb_share_links",
      spec: DSAR_TABLE_ALLOWLIST.kb_share_links,
      rows,
    });
  }

  // -- team_names --------------------------------------------------------
  {
    const { data, error } = await service
      .from("team_names")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`team_names read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "team_names", {
      ownerField: "user_id",
    });
    results.push({
      table: "team_names",
      spec: DSAR_TABLE_ALLOWLIST.team_names,
      rows,
    });
  }

  // -- audit_byok_use (founder_id) ---------------------------------------
  {
    const { data, error } = await service
      .from("audit_byok_use")
      .select("*")
      .eq("founder_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`audit_byok_use read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "audit_byok_use", {
      ownerField: "founder_id",
    });
    results.push({
      table: "audit_byok_use",
      spec: DSAR_TABLE_ALLOWLIST.audit_byok_use,
      rows,
    });
  }

  // -- tc_acceptances (T&C consent ledger; migration 044, AC15) ----------
  {
    const { data, error } = await service
      .from("tc_acceptances")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`tc_acceptances read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "tc_acceptances", {
      ownerField: "user_id",
    });
    results.push({
      table: "tc_acceptances",
      spec: DSAR_TABLE_ALLOWLIST.tc_acceptances,
      rows,
    });
  }

  // -- scope_grants (per-action-class consent ledger; migration 048, PR-G #3947) --
  {
    const { data, error } = await service
      .from("scope_grants")
      .select("*")
      .eq("founder_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`scope_grants read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "scope_grants", {
      ownerField: "founder_id",
    });
    results.push({
      table: "scope_grants",
      spec: DSAR_TABLE_ALLOWLIST.scope_grants,
      rows,
    });
  }

  // -- audit_github_token_use (GitHub App token use audit; migration 052, PR-H #3244) --
  {
    const { data, error } = await service
      .from("audit_github_token_use")
      .select("*")
      .eq("founder_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`audit_github_token_use read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "audit_github_token_use", {
      ownerField: "founder_id",
    });
    results.push({
      table: "audit_github_token_use",
      spec: DSAR_TABLE_ALLOWLIST.audit_github_token_use,
      rows,
    });
  }

  // -- action_sends (per-send WORM signature ledger; migration 051, PR-H #4077) --
  // Art. 15 right of access: the founder is entitled to a copy of every
  // signature row the platform recorded under their authorization. Body
  // and recipient are persisted as SHA-256 hashes only — the raw values
  // never enter the table — but the founder still has access to the
  // metadata (action_class, tier_at_send, clicked_at, confirmed_typed,
  // approval_signature_sha256, grant_id). Marked Art. 15-only because
  // the row is platform-generated evidence of the click, not founder-
  // provided content; portability (Art. 20) does not apply.
  {
    const { data, error } = await service
      .from("action_sends")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`action_sends read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "action_sends", {
      ownerField: "user_id",
    });
    results.push({
      table: "action_sends",
      spec: DSAR_TABLE_ALLOWLIST.action_sends,
      rows,
    });
  }

  // -- email_triage_items (operator email-triage WORM ledger; migration 102) --
  // Art. 15+20: sender/subject/summary/message_id are the data-subject-
  // linkable metadata of emails received in the operator's delegated ops@
  // inbox (legitimate interest, Art. 6(1)(f)). The body is never persisted
  // (structural parse-and-discard), so this export covers ALL stored
  // personal data for the class. WORM trigger + anonymise_email_triage_items
  // RPC handle Art. 17 erasure separately (user_id FK ON DELETE RESTRICT).
  {
    const { data, error } = await service
      .from("email_triage_items")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`email_triage_items read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "email_triage_items", {
      ownerField: "user_id",
    });
    results.push({
      table: "email_triage_items",
      spec: DSAR_TABLE_ALLOWLIST.email_triage_items,
      rows,
    });
  }

  // -- outbound_sends (cold-outbound WORM audit; migration 104, #5325) --
  // Art. 15: the founder is entitled to a copy of every cold send the platform
  // recorded on their behalf. Recipient + body are persisted as a keyed HMAC /
  // SHA-256 hashes only (raw values never enter the table); the founder still
  // has access to the metadata (recipient_hash, approved/per_send body hashes,
  // resend_id, action_class, sent_at). Art. 15-only — platform-generated audit
  // evidence, not founder-provided content (portability does not apply).
  {
    const { data, error } = await service
      .from("outbound_sends")
      .select("*")
      .eq("owner_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`outbound_sends read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "outbound_sends", {
      ownerField: "owner_id",
    });
    results.push({
      table: "outbound_sends",
      spec: DSAR_TABLE_ALLOWLIST.outbound_sends,
      rows,
    });
  }

  // -- email_suppression (per-founder permanent suppression set; migration 104, #5325) --
  // Art. 15: the founder can obtain which recipients they have suppressed
  // (recipient_hash — keyed HMAC, never plaintext — reason, added_at). Art.
  // 15-only: a derived control list, not portable founder-provided content.
  {
    const { data, error } = await service
      .from("email_suppression")
      .select("*")
      .eq("owner_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`email_suppression read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "email_suppression", {
      ownerField: "owner_id",
    });
    results.push({
      table: "email_suppression",
      spec: DSAR_TABLE_ALLOWLIST.email_suppression,
      rows,
    });
  }

  // -- template_authorizations (per-template authorization ledger; migration 053, PR-I #4078) --
  // Art. 15+20: the founder explicitly authorised each template via the
  // first-send-IS-authorization pattern (the Send click on a labeled
  // draft_one_click button IS the Art. 7(3) "specific" + "informed"
  // consent act). The ledger captures (template_hash, action_class,
  // authorized_at, expires_at, soft_reconfirm_at, max_sends, revoked_at,
  // revocation_reason, grant_id). Pure-template-hash + bounds are
  // user-generated context — Art. 20 portability applies alongside
  // Art. 15 access. WORM trigger + anonymise_template_authorizations
  // RPC handle erasure separately.
  {
    const { data, error } = await service
      .from("template_authorizations")
      .select("*")
      .eq("founder_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) {
      throw new Error(`template_authorizations read failed: ${error.message}`);
    }
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "template_authorizations", {
      ownerField: "founder_id",
    });
    results.push({
      table: "template_authorizations",
      spec: DSAR_TABLE_ALLOWLIST.template_authorizations,
      rows,
    });
  }

  // -- organizations (migration 053, feat-team-workspace-multi-user) ----
  // Art. 15: every organization the user owns (1:1 today, N:1 future
  // when an operator-managed org adopts existing user as owner). Direct
  // ownerField = owner_user_id; no JOIN required.
  {
    const { data, error } = await service
      .from("organizations")
      .select("*")
      .eq("owner_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`organizations read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "organizations", {
      ownerField: "owner_user_id",
    });
    results.push({
      table: "organizations",
      spec: DSAR_TABLE_ALLOWLIST.organizations,
      rows,
    });
  }

  // -- workspace_members (migration 053) --------------------------------
  // Art. 15+20: every membership row the user holds. Direct
  // ownerField = user_id; the row is user-provided (they clicked accept
  // on the invite) so portability applies. After a member is removed
  // via remove_workspace_member (058+062), their workspace_members row
  // is gone — the historical-attestations UNION below recovers
  // workspaceIds so the workspaces export still includes the workspace
  // they left.
  let workspaceIds: string[] = [];
  {
    const { data, error } = await service
      .from("workspace_members")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(`workspace_members read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "workspace_members", {
      ownerField: "user_id",
    });
    workspaceIds = rows
      .map((r) => r.workspace_id)
      .filter((v): v is string => typeof v === "string");
    results.push({
      table: "workspace_members",
      spec: DSAR_TABLE_ALLOWLIST.workspace_members,
      rows,
    });
  }

  // -- workspaceIds historical UNION (Approach A — #4230) ---------------
  // Add workspace_id values from workspace_member_attestations rows
  // where the user is the invitee — recovers workspaces the user has
  // since left (their workspace_members row was DELETEd by
  // remove_workspace_member, but the attestation row is WORM and
  // survives). Without this UNION a departed member's DSAR bundle
  // silently omits any workspace they left, which fails Art. 15
  // completeness for the workspaces export block below.
  {
    const { data, error } = await service
      .from("workspace_member_attestations")
      .select("workspace_id")
      .eq("invitee_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(
        `workspace_member_attestations (workspaceIds UNION) read failed: ${error.message}`,
      );
    const historicalIds = ((data ?? []) as { workspace_id?: unknown }[])
      .map((r) => r.workspace_id)
      .filter((v): v is string => typeof v === "string");
    workspaceIds = Array.from(new Set([...workspaceIds, ...historicalIds]));
  }

  // -- workspaces (joinVia workspace_members) ---------------------------
  // Art. 15: the workspace rows the user belongs to, reached through
  // the workspace_members JOIN above (no direct user_id column on
  // workspaces). Cross-tenant scope: every returned row's id MUST
  // appear in the owner-scoped workspaceIds set (otherwise raise
  // CrossTenantViolation, mirroring the messages-via-conversations
  // shape).
  if (workspaceIds.length > 0) {
    const { data, error } = await service
      .from("workspaces")
      .select("*")
      .in("id", workspaceIds);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`workspaces read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    const ownedSet = new Set(workspaceIds);
    for (const row of rows) {
      if (typeof row.id !== "string" || !ownedSet.has(row.id)) {
        const err = new CrossTenantViolation(
          "workspaces",
          expectedUserId,
          null,
        );
        mirrorCrossTenantViolation(null, expectedUserId, "workspaces", err);
        throw err;
      }
    }
    results.push({
      table: "workspaces",
      spec: DSAR_TABLE_ALLOWLIST.workspaces,
      rows,
    });
  } else {
    results.push({
      table: "workspaces",
      spec: DSAR_TABLE_ALLOWLIST.workspaces,
      rows: [],
    });
  }

  // -- workspace_member_attestations (migration 058) --------------------
  // Art. 15: WORM consent records the user clicked-accept on. Both the
  // INVITEE side (rows where the user clicked accept) and the INVITER
  // side (rows where the user invited someone) are personal data the
  // user has the right to access — once removed from the workspace,
  // a one-sided `.eq("invitee_user_id", X)` would miss every inviter-
  // side row, especially for ex-members whose workspace_members linkage
  // is gone (#4230 Kieran P1-1).
  //
  // The `.or()` filter recovers BOTH sides under one query. The inlined
  // two-arm scope check below (NOT assertReadScope — which is single-
  // ownerField) asserts each returned row's owner column matches
  // expectedUserId on EITHER invitee_user_id OR inviter_user_id.
  {
    const { data, error } = await service
      .from("workspace_member_attestations")
      .select("*")
      .or(
        `invitee_user_id.eq.${expectedUserId},inviter_user_id.eq.${expectedUserId}`,
      );
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(
        `workspace_member_attestations read failed: ${error.message}`,
      );
    const rows = (data ?? []) as Record<string, unknown>[];
    // Two-arm scope check: row belongs to expectedUserId iff EITHER
    // invitee_user_id OR inviter_user_id matches. Anonymised (post-
    // Art-17) rows where both columns are NULL are surfaced via the
    // .or() because the row's anonymise transition is the cascade
    // signal; but the response set must not contain rows where NEITHER
    // column matches the user (PostgREST .or() shape never returns
    // those, but we re-assert defensively).
    for (const row of rows) {
      const inv = (row as { invitee_user_id?: unknown }).invitee_user_id;
      const inr = (row as { inviter_user_id?: unknown }).inviter_user_id;
      const ok = inv === expectedUserId || inr === expectedUserId;
      if (!ok) {
        const offending =
          typeof inv === "string"
            ? inv
            : typeof inr === "string"
            ? inr
            : null;
        const err = new CrossTenantViolation(
          "workspace_member_attestations",
          expectedUserId,
          offending,
        );
        mirrorCrossTenantViolation(
          offending,
          expectedUserId,
          "workspace_member_attestations",
          err,
        );
        throw err;
      }
    }
    results.push({
      table: "workspace_member_attestations",
      spec: DSAR_TABLE_ALLOWLIST.workspace_member_attestations,
      rows,
    });
  }

  // -- workspace_invitations (migration 075, #4519) ----------------------
  // Art. 15+20: pending and resolved invitations where the user is
  // invitee or inviter. Two-arm scope check mirrors attestations.
  {
    const [byInvitee, byInviter] = await Promise.all([
      service
        .from("workspace_invitations")
        .select("*")
        .eq("invitee_user_id", expectedUserId),
      service
        .from("workspace_invitations")
        .select("*")
        .eq("inviter_user_id", expectedUserId),
    ]);
    if (signal.aborted) throw new Error("aborted");
    if (byInvitee.error)
      throw new Error(
        `workspace_invitations (invitee) read failed: ${byInvitee.error.message}`,
      );
    if (byInviter.error)
      throw new Error(
        `workspace_invitations (inviter) read failed: ${byInviter.error.message}`,
      );
    const allRows = [...(byInvitee.data ?? []), ...(byInviter.data ?? [])] as Record<string, unknown>[];
    const seen = new Set<string>();
    const rows = allRows.filter((r) => {
      const id = r.id as string;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    for (const row of rows) {
      const inv = (row as { invitee_user_id?: unknown }).invitee_user_id;
      const inr = (row as { inviter_user_id?: unknown }).inviter_user_id;
      const ok = inv === expectedUserId || inr === expectedUserId;
      if (!ok) {
        const offending =
          typeof inv === "string" ? inv : typeof inr === "string" ? inr : null;
        const err = new CrossTenantViolation(
          "workspace_invitations",
          expectedUserId,
          offending,
        );
        mirrorCrossTenantViolation(offending, expectedUserId, "workspace_invitations", err);
        throw err;
      }
    }
    results.push({
      table: "workspace_invitations",
      spec: DSAR_TABLE_ALLOWLIST.workspace_invitations,
      rows,
    });
  }

  // -- workspace_member_removals (migration 062, #4230) -----------------
  // Art. 15: WORM ledger of removal events. ownerField =
  // removed_user_id; assertReadScope single-arm because the row's
  // identity-of-record is the removed user. The actor (removed_by_user_id)
  // sees their own outgoing removals when they file their own DSAR via
  // a separate sibling query — but the Art. 15 owner here is the
  // removed party. After Art. 17 anonymise both PII columns are NULL;
  // the row stays for the 36-mo retention window and falls out of
  // every owner-scoped SELECT (NULL never matches `.eq(<owner>, X)`).
  {
    const { data, error } = await service
      .from("workspace_member_removals")
      .select("*")
      .eq("removed_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error)
      throw new Error(
        `workspace_member_removals read failed: ${error.message}`,
      );
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "workspace_member_removals", {
      ownerField: "removed_user_id",
    });
    results.push({
      table: "workspace_member_removals",
      spec: DSAR_TABLE_ALLOWLIST.workspace_member_removals,
      rows,
    });
  }

  // -- workspace_member_actions (migration 063, #4231) ------------------
  // Art. 15: append-only audit log of membership mutations. The user
  // can be either the actor (owner who added/removed/role-changed
  // someone) or the target (the affected member). OR-semantics requires
  // two separate per-row WHERE chains; each chain carries its own .eq()
  // for the per-row-where lint (AC30). Results merged + deduped by id
  // before push so a row where both actor and target are the same user
  // (structurally impossible for v1 RPCs but defensive) is not double-
  // counted.
  {
    const { data: actorRows, error: actorErr } = await service
      .from("workspace_member_actions")
      .select("*")
      .eq("actor_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (actorErr)
      throw new Error(
        `workspace_member_actions (actor) read failed: ${actorErr.message}`,
      );
    const actorTyped = (actorRows ?? []) as Record<string, unknown>[];
    assertReadScope(actorTyped, expectedUserId, "workspace_member_actions", {
      ownerField: "actor_user_id",
    });

    const { data: targetRows, error: targetErr } = await service
      .from("workspace_member_actions")
      .select("*")
      .eq("target_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (targetErr)
      throw new Error(
        `workspace_member_actions (target) read failed: ${targetErr.message}`,
      );
    const targetTyped = (targetRows ?? []) as Record<string, unknown>[];
    assertReadScope(targetTyped, expectedUserId, "workspace_member_actions", {
      ownerField: "target_user_id",
    });

    const seen = new Set<string>();
    const merged: Record<string, unknown>[] = [];
    for (const row of [...actorTyped, ...targetTyped]) {
      const id = row.id;
      if (typeof id !== "string" || seen.has(id)) continue;
      seen.add(id);
      merged.push(row);
    }
    results.push({
      table: "workspace_member_actions",
      spec: DSAR_TABLE_ALLOWLIST.workspace_member_actions,
      rows: merged,
    });
  }

  // -- byok_delegations (migration 064, #4232) --------------------------
  // Art. 15+20: WORM ledger of BYOK funding delegations. A given user
  // can appear in any of five actor columns — grantor (funder), grantee
  // (beneficiary), created_by/revoked_by/cap_updated_by (administrative
  // actors). OR-semantics requires one per-row WHERE chain per column
  // (per-row-where lint AC30 — the lint parses literal .eq() calls so
  // the five reads are spelled out explicitly rather than iterated).
  // Rows merged + deduped by id so a single row in which the user
  // appears in multiple positions (e.g. grantor == created_by) is not
  // double-counted.
  {
    const seen = new Set<string>();
    const merged: Record<string, unknown>[] = [];
    const accumulate = (
      rows: Record<string, unknown>[],
      ownerField: string,
    ) => {
      assertReadScope(rows, expectedUserId, "byok_delegations", {
        ownerField,
      });
      for (const row of rows) {
        const id = row.id;
        if (typeof id !== "string" || seen.has(id)) continue;
        seen.add(id);
        merged.push(row);
      }
    };

    const { data: grantorRows, error: grantorErr } = await service
      .from("byok_delegations")
      .select("*")
      .eq("grantor_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (grantorErr)
      throw new Error(
        `byok_delegations (grantor) read failed: ${grantorErr.message}`,
      );
    accumulate(
      (grantorRows ?? []) as Record<string, unknown>[],
      "grantor_user_id",
    );

    const { data: granteeRows, error: granteeErr } = await service
      .from("byok_delegations")
      .select("*")
      .eq("grantee_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (granteeErr)
      throw new Error(
        `byok_delegations (grantee) read failed: ${granteeErr.message}`,
      );
    accumulate(
      (granteeRows ?? []) as Record<string, unknown>[],
      "grantee_user_id",
    );

    const { data: createdByRows, error: createdByErr } = await service
      .from("byok_delegations")
      .select("*")
      .eq("created_by_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (createdByErr)
      throw new Error(
        `byok_delegations (created_by) read failed: ${createdByErr.message}`,
      );
    accumulate(
      (createdByRows ?? []) as Record<string, unknown>[],
      "created_by_user_id",
    );

    const { data: revokedByRows, error: revokedByErr } = await service
      .from("byok_delegations")
      .select("*")
      .eq("revoked_by_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (revokedByErr)
      throw new Error(
        `byok_delegations (revoked_by) read failed: ${revokedByErr.message}`,
      );
    accumulate(
      (revokedByRows ?? []) as Record<string, unknown>[],
      "revoked_by_user_id",
    );

    const { data: capUpdatedByRows, error: capUpdatedByErr } = await service
      .from("byok_delegations")
      .select("*")
      .eq("cap_updated_by_user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (capUpdatedByErr)
      throw new Error(
        `byok_delegations (cap_updated_by) read failed: ${capUpdatedByErr.message}`,
      );
    accumulate(
      (capUpdatedByRows ?? []) as Record<string, unknown>[],
      "cap_updated_by_user_id",
    );

    results.push({
      table: "byok_delegations",
      spec: DSAR_TABLE_ALLOWLIST.byok_delegations,
      rows: merged,
    });
  }

  // -- byok_delegation_acceptances (migration 074, #4232 PR-B) ------------
  if (DSAR_TABLE_ALLOWLIST.byok_delegation_acceptances) {
    const { data: acceptRows, error: acceptErr } = await service
      .from("byok_delegation_acceptances")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (acceptErr)
      throw new Error(
        `byok_delegation_acceptances read failed: ${acceptErr.message}`,
      );
    assertReadScope(
      (acceptRows ?? []) as Record<string, unknown>[],
      expectedUserId,
      "byok_delegation_acceptances",
    );
    results.push({
      table: "byok_delegation_acceptances",
      spec: DSAR_TABLE_ALLOWLIST.byok_delegation_acceptances,
      rows: (acceptRows ?? []) as Record<string, unknown>[],
    });
  }

  // -- byok_delegation_withdrawals (migration 084, #4625) ----------------
  if (DSAR_TABLE_ALLOWLIST.byok_delegation_withdrawals) {
    const { data: withdrawRows, error: withdrawErr } = await service
      .from("byok_delegation_withdrawals")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (withdrawErr)
      throw new Error(
        `byok_delegation_withdrawals read failed: ${withdrawErr.message}`,
      );
    assertReadScope(
      (withdrawRows ?? []) as Record<string, unknown>[],
      expectedUserId,
      "byok_delegation_withdrawals",
    );
    results.push({
      table: "byok_delegation_withdrawals",
      spec: DSAR_TABLE_ALLOWLIST.byok_delegation_withdrawals,
      rows: (withdrawRows ?? []) as Record<string, unknown>[],
    });
  }

  return results;
}

// ---------------------------------------------------------------------------
// Storage attachments — list `chat-attachments/<userId>/...` recursively,
// download each blob via service-role, archive under `attachments/<path>`.
//
// Path-prefix guard per AC26 + the 2026-04-11 IDOR learning: every
// resolved storage path MUST start with `<userId>/` AND MUST NOT
// contain `..`. Either violation is FAIL-JOB-LOUD — silently skipping
// a `..`-bearing path treats security-validation regressions as
// data-quality concerns. assertReadScope's twin for the Storage path.
// ---------------------------------------------------------------------------

const STORAGE_LIST_PAGE_SIZE = 1000;

interface AttachmentBinary {
  /** storage path relative to bucket root (e.g. "<userId>/conv-1/foo.png"). */
  storagePath: string;
  /** archive path inside the ZIP (e.g. "attachments/conv-1/foo.png"). */
  archivePath: string;
  buffer: Buffer;
}

async function enumerateChatAttachments(
  expectedUserId: string,
  signal: AbortSignal,
): Promise<AttachmentBinary[]> {
  const service = createServiceClient();
  const bucket = service.storage.from("chat-attachments");
  const results: AttachmentBinary[] = [];

  // Two-level listing: <userId>/<convId>/<file>. The convId folders
  // are discovered by listing under the user's prefix.
  const { data: folders, error: listErr } = await bucket.list(expectedUserId, {
    limit: STORAGE_LIST_PAGE_SIZE,
  });
  if (signal.aborted) throw new Error("aborted");
  if (listErr) {
    throw new Error(`chat-attachments list failed: ${listErr.message}`);
  }
  if (!folders) return results;

  for (const folder of folders) {
    if (signal.aborted) throw new Error("aborted");
    // Storage list returns both files and folders mixed; folders have
    // metadata=null. A bare file directly under <userId>/ would be
    // unusual (the schema places attachments at <userId>/<convId>/) but
    // we handle both for robustness.
    const subPrefix = `${expectedUserId}/${folder.name}`;
    let isFile = (folder as { metadata?: unknown }).metadata !== null;
    if (!isFile) {
      const { data: inner, error: innerErr } = await bucket.list(subPrefix, {
        limit: STORAGE_LIST_PAGE_SIZE,
      });
      if (signal.aborted) throw new Error("aborted");
      if (innerErr) {
        throw new Error(
          `chat-attachments list ${subPrefix} failed: ${innerErr.message}`,
        );
      }
      for (const file of inner ?? []) {
        const storagePath = `${subPrefix}/${file.name}`;
        assertSafeStoragePath(storagePath, expectedUserId);
        const buf = await downloadAttachment(bucket, storagePath, signal);
        results.push({
          storagePath,
          archivePath: `attachments/${folder.name}/${file.name}`,
          buffer: buf,
        });
      }
    } else {
      const storagePath = subPrefix;
      assertSafeStoragePath(storagePath, expectedUserId);
      const buf = await downloadAttachment(bucket, storagePath, signal);
      results.push({
        storagePath,
        archivePath: `attachments/${folder.name}`,
        buffer: buf,
      });
    }
  }

  return results;
}

function assertSafeStoragePath(
  storagePath: string,
  expectedUserId: string,
): void {
  // Reject any path segment of `..` AND any path not anchored at
  // `<userId>/`. Service-role bypasses RLS so a path-prefix bug here
  // could surface another user's blob in the bundle — fail-job-loud
  // per AC26.
  const norm = posixPath.normalize(storagePath);
  if (
    !norm.startsWith(`${expectedUserId}/`) ||
    norm.includes("/../") ||
    norm.endsWith("/..") ||
    norm.startsWith("../")
  ) {
    const err = new CrossTenantViolation(
      "chat-attachments",
      expectedUserId,
      null,
    );
    mirrorCrossTenantViolation(null, expectedUserId, "chat-attachments", err);
    throw err;
  }
}

async function downloadAttachment(
  bucket: ReturnType<ReturnType<typeof createServiceClient>["storage"]["from"]>,
  storagePath: string,
  signal: AbortSignal,
): Promise<Buffer> {
  const { data, error } = await bucket.download(storagePath);
  if (signal.aborted) throw new Error("aborted");
  if (error) throw new Error(`download ${storagePath}: ${error.message}`);
  if (!data) throw new Error(`download ${storagePath}: null body`);
  const arr = new Uint8Array(await data.arrayBuffer());
  return Buffer.from(arr);
}

// ---------------------------------------------------------------------------
// Workspace files — walk `<workspacePath>/` with `O_NOFOLLOW` opens +
// `fstat` ino verify per AC17 + AC18. Per-file SHA-256 computed in the
// same fd-pass that streams bytes to the archiver (no re-open).
//
// Per AC26 per-file error policy:
//   - Symlink (ELOOP) on workspace file: skip-with-manifest-entry.
//   - fstat ino-mismatch (TOCTOU evidence): skip-with-manifest-entry.
//   - All other errors: propagate (worker fails the job).
// ---------------------------------------------------------------------------

interface WorkspaceFileResult {
  /** absolute path on disk. */
  absPath: string;
  /** archive path inside the ZIP, prefixed with workspace/. */
  archivePath: string;
  /** sha256 hex + byte count, populated for included files only. */
  sha256: string;
  bytes: number;
}

interface WorkspaceSkip {
  archivePath: string;
  reason: "symlink_rejected" | "inode_mismatch";
}

interface WorkspaceWalkResult {
  included: WorkspaceFileResult[];
  skipped: WorkspaceSkip[];
}

const MAX_WORKSPACE_DEPTH = 16;
const MAX_WORKSPACE_FILES = 100_000; // bounded sweep — defense in depth

async function enumerateWorkspaceFiles(
  workspacePath: string | null,
  signal: AbortSignal,
  appendToArchive: (
    archivePath: string,
    buf: Buffer,
  ) => void,
): Promise<WorkspaceWalkResult> {
  const included: WorkspaceFileResult[] = [];
  const skipped: WorkspaceSkip[] = [];
  if (!workspacePath) return { included, skipped };

  let resolvedRoot: string;
  try {
    const st = await stat(workspacePath);
    if (!st.isDirectory()) return { included, skipped };
    resolvedRoot = workspacePath;
  } catch {
    return { included, skipped };
  }

  let fileCount = 0;
  const queue: { abs: string; rel: string; depth: number }[] = [
    { abs: resolvedRoot, rel: "", depth: 0 },
  ];

  while (queue.length > 0) {
    if (signal.aborted) throw new Error("aborted");
    const dir = queue.shift()!;
    if (dir.depth > MAX_WORKSPACE_DEPTH) continue;

    let entries;
    try {
      entries = await readdir(dir.abs, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const e of entries) {
      if (fileCount >= MAX_WORKSPACE_FILES) break;
      const abs = join(dir.abs, e.name);
      const rel = dir.rel ? `${dir.rel}/${e.name}` : e.name;
      const archivePath = `workspace/${rel}`;

      if (e.isSymbolicLink()) {
        skipped.push({ archivePath, reason: "symlink_rejected" });
        continue;
      }
      if (e.isDirectory()) {
        queue.push({ abs, rel, depth: dir.depth + 1 });
        continue;
      }
      if (!e.isFile()) continue;

      let fd: number | null = null;
      try {
        fd = openSync(abs, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
        const openStat = fstatSync(fd);
        if (!openStat.isFile()) {
          skipped.push({ archivePath, reason: "inode_mismatch" });
          continue;
        }
        // Single fd-pass: read into a buffer + hash in one go per AC18.
        // For workspaces that may have large files, the buffer is the
        // archive's input — there is no re-open seam to TOCTOU through.
        const stream = createReadStream("", { fd, autoClose: false });
        const chunks: Buffer[] = [];
        const hash = createHash("sha256");
        await new Promise<void>((resolve, reject) => {
          stream.on("data", (c) => {
            const buf = Buffer.isBuffer(c) ? c : Buffer.from(c);
            chunks.push(buf);
            hash.update(buf);
          });
          stream.on("end", resolve);
          stream.on("error", reject);
        });
        const buf = Buffer.concat(chunks);
        // Post-read fstat: ino + size must match pre-read fstat.
        const reStat = fstatSync(fd);
        if (
          reStat.ino !== openStat.ino ||
          reStat.size !== openStat.size
        ) {
          skipped.push({ archivePath, reason: "inode_mismatch" });
          continue;
        }
        const sha256 = hash.digest("hex");
        appendToArchive(archivePath, buf);
        included.push({
          absPath: abs,
          archivePath,
          sha256,
          bytes: buf.length,
        });
        fileCount++;
      } catch (err) {
        // ELOOP from O_NOFOLLOW races (symlink swapped in after readdir).
        if ((err as NodeJS.ErrnoException).code === "ELOOP") {
          skipped.push({ archivePath, reason: "symlink_rejected" });
          continue;
        }
        // Any other I/O error propagates so the worker fails the job
        // rather than silently dropping data.
        throw err;
      } finally {
        if (fd !== null) {
          try {
            closeSync(fd);
          } catch {
            // Closing already-closed fd is safe to swallow.
          }
        }
      }
    }
  }

  return { included, skipped };
}

// ---------------------------------------------------------------------------
// Archive construction — disk-then-upload (ADR-028 §D4).
// ---------------------------------------------------------------------------

interface BuildArchiveResult {
  localPath: string;
  sha256: string;
  bytes: number;
  manifest: ManifestRoot;
}

/**
 * Exported (#4319 Phase 7 integration test). Not part of the public
 * worker API — callers should go through `runExport`.
 */
export async function buildArchiveToDisk(
  jobId: string,
  userId: string,
  tables: TableExportResult[],
  workspacePath: string | null,
  pseudonymSalt: Buffer,
  signal: AbortSignal,
): Promise<BuildArchiveResult> {
  const tmpRoot = join(tmpdir(), "dsar-exports");
  await mkdir(tmpRoot, { recursive: true });
  const localPath = join(tmpRoot, `${jobId}.zip`);

  const files: ManifestFileEntry[] = [];
  const excluded: ManifestFileEntry[] = [];

  const out = createWriteStream(localPath);
  const archive = new ZipArchive({ zlib: { level: 6 } });
  const archiveDone = new Promise<void>((resolve, reject) => {
    out.on("close", () => resolve());
    out.on("error", reject);
    archive.on("error", reject);
  });
  archive.pipe(out);

  // Per AC18: per-file SHA-256 computed at the same point the bytes
  // are handed to the archiver. For in-memory JSON tables this is a
  // single buffer hash before append — no re-open, no fd-cross.
  for (const t of tables) {
    if (signal.aborted) {
      archive.abort();
      throw new Error("aborted");
    }
    const json = dsarStringify({
      table: t.table,
      article: t.spec.article,
      row_count: t.rows.length,
      rows: t.rows,
    });
    const buf = Buffer.from(json, "utf-8");
    const hash = sha256Hex(buf);
    const path = `tables/${t.table}.json`;
    archive.append(buf, { name: path });
    files.push({
      path,
      included: true,
      article: t.spec.article,
      source_table: t.table,
      row_count: t.rows.length,
      sha256: hash,
      bytes: buf.length,
    });
  }

  // Storage attachments (chat-attachments bucket). Path-prefix guard
  // fail-job-loud per AC26 is inside `enumerateChatAttachments`.
  const attachments = await enumerateChatAttachments(userId, signal);
  for (const a of attachments) {
    if (signal.aborted) {
      archive.abort();
      throw new Error("aborted");
    }
    archive.append(a.buffer, { name: a.archivePath });
    files.push({
      path: a.archivePath,
      included: true,
      article: "15+20",
      sha256: sha256Hex(a.buffer),
      bytes: a.buffer.length,
    });
  }

  // Co-uploader attachments (#4445 Art. 15 completeness). Manifest-only
  // metadata entries (bytes NOT included in ZIP). Same pseudonymSalt as
  // exportSqlTable so cross-table pseudonym consistency is maintained.
  const coUploaderEntries = await enumerateCoUploaderAttachments(
    userId,
    pseudonymSalt,
    signal,
  );
  for (const entry of coUploaderEntries) {
    files.push(entry);
  }

  // Workspace files (`/workspaces/<userId>/*`). O_NOFOLLOW + fstat ino
  // verify per AC17 + AC18. Per-file errors land in `excluded_files[]`
  // per AC26.
  const workspaceWalk = await enumerateWorkspaceFiles(
    workspacePath,
    signal,
    (archivePath, buf) => {
      archive.append(buf, { name: archivePath });
    },
  );
  for (const w of workspaceWalk.included) {
    files.push({
      path: w.archivePath,
      included: true,
      article: "15+20",
      sha256: w.sha256,
      bytes: w.bytes,
    });
  }
  for (const s of workspaceWalk.skipped) {
    excluded.push({
      path: s.archivePath,
      included: false,
      reason: s.reason,
    });
  }

  // Art. 15(4) redaction disclosure (#4319). Builds one entry per
  // table that had at least one redacted row; tables with count=0 are
  // omitted so the manifest stays empty in single-user-workspace
  // exports. Counts flow from exportSqlTable via the per-table
  // `redactionCount` channel on TableExportResult.
  const redactions: ManifestRoot["redactions"] = [];
  const messagesTable = tables.find((t) => t.table === "messages");
  if (messagesTable && (messagesTable.redactionCount ?? 0) > 0) {
    redactions.push({
      path: "tables/messages.json",
      reason: REDACTION_REASON,
      count: messagesTable.redactionCount!,
    });
  }
  const attachmentsTable = tables.find(
    (t) => t.table === "message_attachments",
  );
  if (attachmentsTable && (attachmentsTable.redactionCount ?? 0) > 0) {
    redactions.push({
      path: "tables/message_attachments.json",
      reason: REDACTION_REASON,
      count: attachmentsTable.redactionCount!,
    });
  }

  if (coUploaderEntries.length > 0) {
    redactions.push({
      path: "attachments/co-uploader/",
      reason: "art-15-co-uploader",
      count: coUploaderEntries.length,
    });
  }

  // Manifest LAST per spec FR4 step 8.
  const manifest: ManifestRoot = {
    schema_version: MANIFEST_SCHEMA_VERSION,
    generated_at: new Date().toISOString(),
    user_id: userId,
    job_id: jobId,
    serialization: {
      timestamp_format: "ISO 8601 with UTC offset (Z)",
      bytea_encoding: "base64",
      null_encoding: "JSON null",
      object_keys: "sorted alphabetically",
    },
    files,
    excluded_files: excluded,
    redactions,
  };
  const manifestJson = dsarStringify(manifest);
  archive.append(Buffer.from(manifestJson, "utf-8"), {
    name: "manifest.json",
  });

  await archive.finalize();
  await archiveDone;

  const fileStat = await stat(localPath);
  if (fileStat.size > SIZE_CAP_BYTES) {
    await rm(localPath, { force: true });
    // Distinct error class so runExport can map to a
    // `bundle_too_large` failure_reason (vs the generic
    // `archive_error` which tells the user to retry — retry won't
    // help against the cap). The user-facing copy points to the
    // legal@jikigai.com operator-fallback. User-impact-reviewer P1
    // on PR #3634.
    throw new BundleTooLargeError(
      `Bundle size ${fileStat.size} exceeds DSAR_EXPORT_SIZE_CAP_MB cap of ${SIZE_CAP_BYTES} bytes`,
    );
  }

  // SHA-256 of the entire bundle for `bundle_sha256` audit column.
  const bundleHash = createHash("sha256");
  await pipeline(
    createReadStream(localPath),
    async function* (src: AsyncIterable<Buffer>) {
      for await (const chunk of src) {
        bundleHash.update(chunk);
        yield chunk;
      }
    },
    new PassThrough(),
  );
  const bundleSha256 = bundleHash.digest("hex");

  // Art. 15(4) observability emission (#4319 Phase 6). Info-level →
  // pino-only (no Sentry over-paging at SENTRY_BREADCRUMB_MIN_LEVEL=warn).
  // Counts only; no raw user_id, content, salt, or row IDs in the
  // payload. Long-horizon WORM trail tracked at #4359.
  const messagesRedactCount = messagesTable?.redactionCount ?? 0;
  const attachmentsRedactCount = attachmentsTable?.redactionCount ?? 0;
  if (messagesRedactCount > 0 || attachmentsRedactCount > 0) {
    log.info(
      {
        feature: "dsar-export",
        op: "redact-foreign-author",
        userIdHash: hashUserId(userId),
        redactions: {
          messages: messagesRedactCount,
          message_attachments: attachmentsRedactCount,
        },
      },
      "redacted foreign-author content",
    );
  }

  return { localPath, sha256: bundleSha256, bytes: fileStat.size, manifest };
}

// ---------------------------------------------------------------------------
// Storage upload — raw fetch with duplex: 'half'. The Storage REST
// shape: POST /storage/v1/object/<bucket>/<path> with the service-role
// key as Authorization Bearer.
// ---------------------------------------------------------------------------

async function uploadToStorage(
  userId: string,
  jobId: string,
  localPath: string,
  signal: AbortSignal,
): Promise<void> {
  const fileStat = statSync(localPath);
  const url = `${serverUrl()}/storage/v1/object/${STORAGE_BUCKET}/${userId}/${jobId}.zip`;
  const body = Readable.toWeb(createReadStream(localPath));
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ""}`,
      "Content-Type": "application/zip",
      "Content-Length": String(fileStat.size),
      "x-upsert": "true",
    },
    body: body as unknown as BodyInit,
    // Required by Node 18+ undici when sending a streaming body.
    // @ts-expect-error — `duplex` is a Node-specific RequestInit option.
    duplex: "half",
    signal,
  });
  if (!res.ok) {
    throw new Error(
      `Storage upload failed: HTTP ${res.status} ${await res.text()}`,
    );
  }
}

// ---------------------------------------------------------------------------
// enqueueExport — INSERT a job row + audit-PII row, return 202 payload.
// ---------------------------------------------------------------------------

export async function enqueueExport(
  input: EnqueueExportInput,
): Promise<EnqueueExportResult> {
  if (!input.workspaceId) {
    throw new Error("enqueueExport: workspaceId is required");
  }
  const service = createServiceClient();

  // Application-layer idempotency aligned to the partial unique index:
  // at most one in-flight or completed-not-yet-expired job per user
  // (status IN ('pending','running','completed')). The hourly TR14
  // sweep flips completed -> expired when signed_url_expires_at lapses,
  // so 'completed' is bounded to the bundle TTL (~7d). Fix from
  // code-review P1 (data-integrity-guardian, PR #3634): the prior
  // .gte("requested_at", now-24h) predicate let lookups miss a still-
  // completed row from >24h ago; the INSERT path then collided with
  // the unbounded partial unique index and 500'd the user. Aligning
  // the lookup with the index makes "1 active or completed-in-TTL"
  // the load-bearing invariant in BOTH layers.
  const { data: existing, error: lookupErr } = await service
    .from("dsar_export_jobs")
    .select("id, status, requested_at, acknowledged_at")
    .eq("user_id", input.userId)
    .in("status", ["pending", "running", "completed"])
    .order("requested_at", { ascending: false })
    .limit(1);
  if (lookupErr) {
    throw new Error(`dsar idempotency lookup failed: ${lookupErr.message}`);
  }
  if (existing && existing.length > 0) {
    const row = existing[0] as { id: string; acknowledged_at: string };
    return { jobId: row.id, acknowledgedAt: row.acknowledged_at };
  }

  const { data: inserted, error: insertErr } = await service
    .from("dsar_export_jobs")
    .insert({
      user_id: input.userId,
      workspace_id: input.workspaceId,
      owner_session_id: input.sessionId,
      reauth_event_id: input.reauthEventId,
      status: "pending",
    })
    .select("id, acknowledged_at")
    .single();
  if (insertErr || !inserted) {
    throw new Error(
      `dsar_export_jobs insert failed: ${insertErr?.message ?? "no row"}`,
    );
  }
  const row = inserted as { id: string; acknowledged_at: string };

  // Audit PII (separate table, WORM-trigger gated, service-role only).
  const { error: auditErr } = await service.rpc("write_dsar_export_audit_pii", {
    p_job_id: row.id,
    p_user_id: input.userId,
    p_event_type: "enqueue",
    p_requester_ip: input.requesterIp,
    p_user_agent: input.userAgent,
  });
  if (auditErr) {
    log.error({ jobId: row.id, err: auditErr.message }, "audit PII write failed (non-fatal)");
  }

  return { jobId: row.id, acknowledgedAt: row.acknowledged_at };
}

// ---------------------------------------------------------------------------
// runExport — orchestrate one job from claim to completed.
// ---------------------------------------------------------------------------

async function runExport(job: {
  id: string;
  user_id: string;
  owner_session_id: string;
}): Promise<void> {
  const service = createServiceClient();
  const expectedUserId = job.user_id;
  const controller = new AbortController();
  const timeoutHandle = setTimeout(
    () => controller.abort(new Error("job_timeout")),
    JOB_HARD_TIMEOUT_MS,
  );

  let localPath: string | null = null;

  try {
    const pseudonymSalt = randomBytes(32);
    const tables = await exportSqlTable(expectedUserId, pseudonymSalt, controller.signal);
    // #5005 — workspace-files enumeration root, resolved id-keyed from the
    // subject's workspace id (`<WORKSPACES_ROOT>/<expectedUserId>`), NOT from
    // the subject's legacy `users.workspace_path` column (stale/empty after the
    // ADR-044 relocation → silently truncated workspace files from the export).
    // DSAR is per-subject, so this is the SOLO/N2 path — see
    // `resolveDsarWorkspacePath` for the no-over-export rationale. The `users`
    // table is still emitted by `exportSqlTable` above; only the path *source*
    // moved.
    const workspacePath = resolveDsarWorkspacePath(expectedUserId);
    const archive = await buildArchiveToDisk(
      job.id,
      expectedUserId,
      tables,
      workspacePath,
      pseudonymSalt,
      controller.signal,
    );
    localPath = archive.localPath;

    await uploadToStorage(expectedUserId, job.id, archive.localPath, controller.signal);

    // AC19 — signed-URL TTL relaxation (1h -> 7d) standing reminder:
    // the compensating defences are
    //   (1) session_id binding — owner_session_id checked at download
    //   (2) IP bind — /24 (IPv4) or /48 (IPv6) checked at download
    //   (3) single-use — atomic UPDATE status='delivered' on download
    //   (4) hard-delete on download OR TTL — Storage object deleted
    //       on first successful download AND by TR14 sweep at 7d
    // The new ceiling is 7d hard expiry plus Storage object lifetime
    // bounded by whichever of (4) fires first. Do NOT drop any one
    // defence without explicitly naming the new ceiling that
    // replaces it.
    const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_MS);

    const { error: updateErr } = await service
      .from("dsar_export_jobs")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
        signed_url_expires_at: expiresAt.toISOString(),
        bundle_sha256: archive.sha256,
        bundle_size_bytes: archive.bytes,
      })
      .eq("id", job.id);
    if (updateErr) {
      throw new Error(`job complete update failed: ${updateErr.message}`);
    }

    // Email is fire-and-forget — a Resend failure does not roll back
    // the completed job. The user sees the new job in /settings/privacy
    // even if the email never arrives.
    await sendDsarExportReadyEmail(expectedUserId, job.id, expiresAt);

    log.info({ jobId: job.id, bytes: archive.bytes }, "DSAR job completed");
  } catch (err) {
    // Distinct failure_reason values so the failure email picks the
    // right user-facing copy (user-impact-reviewer P1 on PR #3634):
    //   - job_timeout       -> the 30-min worker timeout fired
    //   - bundle_too_large  -> exceeded DSAR_EXPORT_SIZE_CAP_MB; retry
    //                          will fail identically, user must email
    //                          legal@jikigai.com for operator fallback
    //   - archive_error     -> generic; retry is the right next step
    const reason = controller.signal.aborted
      ? "job_timeout"
      : err instanceof BundleTooLargeError
        ? "bundle_too_large"
        : "archive_error";
    log.error({ jobId: job.id, err, reason }, "DSAR job failed");
    await service
      .from("dsar_export_jobs")
      .update({
        status: "failed",
        failure_reason: reason,
        completed_at: new Date().toISOString(),
      })
      .eq("id", job.id);
    await sendDsarExportFailedEmail(expectedUserId, job.id, reason);
  } finally {
    clearTimeout(timeoutHandle);
    if (localPath) {
      await rm(localPath, { force: true }).catch(() => {});
    }
  }
}

// ---------------------------------------------------------------------------
// Poller — mirrors agent-runner.ts:698-714 pattern.
//
// On-startup orphan reset per S3: any job in `running` status from a
// previous Node lifetime is reset to `pending` so the next tick claims
// it. Replaces TR12's pg_cron stuck-job sweep.
// ---------------------------------------------------------------------------

let pollerStarted = false;

export async function startDsarExportReaper(): Promise<NodeJS.Timeout> {
  if (pollerStarted) {
    throw new Error("dsar reaper already started");
  }
  pollerStarted = true;

  // On-startup orphan reset per S3.
  try {
    const service = createServiceClient();
    const { error: resetErr } = await service
      .from("dsar_export_jobs")
      .update({ status: "pending", started_at: null })
      .eq("status", "running");
    if (resetErr) {
      log.error(
        { err: resetErr.message },
        "DSAR orphan reset failed at startup",
      );
    }
  } catch (err) {
    log.error({ err }, "DSAR orphan reset threw at startup");
  }

  const timer = setInterval(async () => {
    try {
      const service = createServiceClient();
      const { data, error } = await service.rpc("claim_next_dsar_export_job");
      if (error) {
        log.error({ err: error.message }, "claim_next_dsar_export_job error");
        return;
      }
      const rows = (data ?? []) as Array<{
        id: string;
        user_id: string;
        owner_session_id: string;
      }>;
      if (rows.length === 0) return;
      // One job per tick keeps memory/IO bounded. The next tick will
      // claim the next queued job.
      await runExport(rows[0]);
    } catch (err) {
      log.error({ err }, "DSAR reaper tick threw");
    }
  }, POLLER_INTERVAL_MS);

  // Allow process to exit cleanly in tests.
  timer.unref?.();
  return timer;
}

// ---------------------------------------------------------------------------
// Test-only escape hatch — reset the poller-started latch.
// ---------------------------------------------------------------------------

export function __resetDsarReaperForTests(): void {
  pollerStarted = false;
}
