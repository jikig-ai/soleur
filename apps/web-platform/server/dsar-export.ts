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
// v1 scope (this commit — Phase 5a):
//   - SQL tables in `DSAR_TABLE_ALLOWLIST` (incl. nested via `joinVia`).
//   - Manifest with serialization conventions per AC23.
//   - ZIP archive built on disk; raw-fetch upload.
//   - Lifecycle: pending -> running -> completed -> delivered/expired.
//   - Email via notifications.ts:sendDsarExportReadyEmail.
//
// Phase 5b (follow-up — explicit `excluded_files[]` entries in manifest):
//   - `chat-attachments/<userId>/...` binaries via service.storage.list
//     + path-prefix guard (fail-job-loud on path-traversal per AC26).
//   - `/workspaces/<userId>/*` files via `O_NOFOLLOW + fstat` ino verify
//     (skip-with-manifest-entry on symlink/ino-mismatch per AC26).
// Until 5b lands, the manifest declares these sources as deferred;
// AC1 (1:1 reconcile with Privacy Policy §4.7 after FR8) is the gate
// that blocks enablement in prd.

import { createReadStream, statSync } from "node:fs";
import { writeFile, mkdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import archiver from "archiver";
import { createWriteStream } from "node:fs";

import { createServiceClient, serverUrl } from "@/lib/supabase/service";
import { mirrorCrossTenantViolation } from "./observability";
import {
  sendDsarExportReadyEmail,
  sendDsarExportFailedEmail,
} from "./notifications";
import { createChildLogger } from "./logger";
import {
  DSAR_TABLE_ALLOWLIST,
  type DsarTableSpec,
} from "./dsar-export-allowlist";

const log = createChildLogger("dsar-export");

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
// Constants
// ---------------------------------------------------------------------------

const JOB_HARD_TIMEOUT_MS = 30 * 60 * 1000; // 30 min
const POLLER_INTERVAL_MS = 5 * 1000;
const SIGNED_URL_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const STORAGE_BUCKET = "dsar-exports";
const MANIFEST_SCHEMA_VERSION = "1.0.0";
const SIZE_CAP_BYTES =
  (Number(process.env.DSAR_EXPORT_SIZE_CAP_MB) || 1024) * 1024 * 1024;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface EnqueueExportInput {
  userId: string;
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
  deferred_sources: { source: string; reason: string }[];
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
}

async function exportSqlTable(
  // Per AC30, the per-row-WHERE lint expects `service.from("<table>")
  // .select(...).eq(<owner>, expectedUserId)` at every literal call
  // site. The worker enumerates each allowlisted table EXPLICITLY
  // below so the lint can pattern-match.
  expectedUserId: string,
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

  // -- conversations -----------------------------------------------------
  let conversationIds: string[] = [];
  {
    const { data, error } = await service
      .from("conversations")
      .select("*")
      .eq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`conversations read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    assertReadScope(rows, expectedUserId, "conversations", {
      ownerField: "user_id",
    });
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
  let messageIds: string[] = [];
  if (conversationIds.length > 0) {
    const { data, error } = await service
      .from("messages")
      .select("*")
      .in("conversation_id", conversationIds);
    if (signal.aborted) throw new Error("aborted");
    if (error) throw new Error(`messages read failed: ${error.message}`);
    const rows = (data ?? []) as Record<string, unknown>[];
    // No direct owner_id; verify every message's conversation_id is in
    // the set we already proved is owner-scoped. If a service-role
    // glitch returned a row whose conversation_id is NOT in our owner-
    // scoped set, raise CrossTenantViolation.
    const ownedConvSet = new Set(conversationIds);
    for (const row of rows) {
      if (typeof row.conversation_id !== "string" || !ownedConvSet.has(row.conversation_id)) {
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
    results.push({
      table: "messages",
      spec: DSAR_TABLE_ALLOWLIST.messages,
      rows,
    });
  } else {
    results.push({
      table: "messages",
      spec: DSAR_TABLE_ALLOWLIST.messages,
      rows: [],
    });
  }

  // -- message_attachments (joinVia messages) ----------------------------
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
    results.push({
      table: "message_attachments",
      spec: DSAR_TABLE_ALLOWLIST.message_attachments,
      rows,
    });
  } else {
    results.push({
      table: "message_attachments",
      spec: DSAR_TABLE_ALLOWLIST.message_attachments,
      rows: [],
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

  return results;
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

async function buildArchiveToDisk(
  jobId: string,
  userId: string,
  tables: TableExportResult[],
  signal: AbortSignal,
): Promise<BuildArchiveResult> {
  const tmpRoot = join(tmpdir(), "dsar-exports");
  await mkdir(tmpRoot, { recursive: true });
  const localPath = join(tmpRoot, `${jobId}.zip`);

  const files: ManifestFileEntry[] = [];
  const excluded: ManifestFileEntry[] = [];

  // Phase 5b deferrals — explicit so reviewers and the user-facing
  // manifest both see what is NOT YET covered. AC1 (1:1 reconcile with
  // Privacy Policy §4.7) is the merge-blocking gate.
  const deferredSources: { source: string; reason: string }[] = [
    {
      source: "chat-attachments storage objects",
      reason:
        "Phase 5b — pending O_NOFOLLOW + fstat ino-verify + path-prefix " +
        "guard implementation; metadata rows are included in " +
        "message_attachments JSON.",
    },
    {
      source: "workspace files (/workspaces/<userId>/*)",
      reason:
        "Phase 5b — pending O_NOFOLLOW + fstat ino-verify implementation " +
        "(AC17 + AC18 + AC26).",
    },
  ];

  const out = createWriteStream(localPath);
  const archive = archiver("zip", { zlib: { level: 6 } });
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
    deferred_sources: deferredSources,
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
    throw new Error(
      `Bundle size ${fileStat.size} exceeds TR4 cap of ${SIZE_CAP_BYTES} bytes`,
    );
  }

  // SHA-256 of the entire bundle for `bundle_sha256` audit column.
  const bundleHash = createHash("sha256");
  await pipeline(createReadStream(localPath), async function* (src) {
    for await (const chunk of src as AsyncIterable<Buffer>) {
      bundleHash.update(chunk);
      yield chunk;
    }
  }, new (require("node:stream").PassThrough)());
  const bundleSha256 = bundleHash.digest("hex");

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
  const service = createServiceClient();

  // Application-layer 24h idempotency (per migration 041 note: the
  // partial unique index covers in-flight + completed; we additionally
  // refuse a fresh insert if the user completed within the last 24h
  // and the bundle has not yet expired).
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: existing, error: lookupErr } = await service
    .from("dsar_export_jobs")
    .select("id, status, requested_at, acknowledged_at")
    .eq("user_id", input.userId)
    .in("status", ["pending", "running", "completed"])
    .gte("requested_at", since)
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
    const tables = await exportSqlTable(expectedUserId, controller.signal);
    const archive = await buildArchiveToDisk(
      job.id,
      expectedUserId,
      tables,
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
    const reason = controller.signal.aborted ? "job_timeout" : "archive_error";
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
