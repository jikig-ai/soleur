// S0 spike for #3637 (feat-dsar-art15-export-endpoint, plan rev-2 Phase 0).
//
// Measures peak RSS, wall-clock, and SHA-256 round-trip integrity for two
// upload patterns across 100 MB / 500 MB / 1 GB / 2 GB synthesised payloads:
//
//   - mode=stream: archiver -> Node Readable -> Web ReadableStream ->
//     supabase.storage.upload()  -- the plan rev-2 "streaming" hypothesis.
//
//   - mode=disk:   archiver -> tempfile -> fs.createReadStream() -> raw fetch
//     POST to /storage/v1/object/{bucket}/{path} with `duplex: 'half'` --
//     plan Phase 0.7 disk-then-upload fallback. Bypasses supabase-js so the
//     SDK's body-buffering does not contaminate the RSS measurement.
//
// Output drives:
//   - TR4 v1 size cap (largest tier where peak RSS stays under 2 GB)
//   - S8 Node 22 runtime invariant captured in ADR
//     0NN-dsar-export-substrate-and-audit-retention.md
//   - GATE: Phase 1 cannot start until report exists
//
// Path deviates from plan literal `scripts/spike-dsar-streaming-upload.ts`
// to match existing in-tree convention (`scripts/spike/<name>.ts`).
// Runtime is Node 22 via tsx (NOT Bun) per work-skill clarification
// 2026-05-12: production worker is `next start` on Node 22.
//
// Test fixtures are synthesised on-the-fly via crypto.randomFillSync (native)
// per `cq-test-fixtures-synthesized-only`. Zero real-user data flows.
//
// Operator command:
//   bun add archiver && bun add -d @types/archiver   # one-time
//   doppler run -p soleur -c dev -- ./node_modules/.bin/tsx \
//     scripts/spike/dsar-streaming-upload.ts
//
// Optional env knobs:
//   DSAR_SPIKE_SIZES_MB="100,500,1000,2000"   # default
//   DSAR_SPIKE_MODES="stream,disk"            # default; values: stream|disk
//   DSAR_SPIKE_BUCKET="dsar-spike"            # default
//   DSAR_SPIKE_KEEP_OBJECTS="0"               # set 1 to skip cleanup
//   DSAR_SPIKE_TMP_DIR=<path>                 # default $TMPDIR for disk mode

import { createHash, randomFillSync } from "node:crypto";
import {
  createReadStream,
  createWriteStream,
  mkdtempSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { PassThrough, Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

// archiver@8 is ESM-only with no default export (breaking change from v7).
// @types/archiver@7 still ships the v7 CJS shape (factory function), so we
// import the runtime class through a manual shim. The runtime export was
// verified via `grep -E "^export" node_modules/archiver/index.js`.
import type * as ArchiverNS from "archiver";
import * as ArchiverRuntime from "archiver";
type Archive = ArchiverNS.Archiver;
const ZipArchive = (
  ArchiverRuntime as unknown as {
    ZipArchive: new (opts?: ArchiverNS.ArchiverOptions) => Archive;
  }
).ZipArchive;

import { createServiceClient, serverUrl } from "../../lib/supabase/service";

type Mode = "stream" | "disk";

const SIZES_MB = (process.env.DSAR_SPIKE_SIZES_MB ?? "100,500,1000,2000")
  .split(",")
  .map((s) => Number.parseInt(s.trim(), 10))
  .filter((n) => Number.isFinite(n) && n > 0);

const MODES: Mode[] = (process.env.DSAR_SPIKE_MODES ?? "stream,disk")
  .split(",")
  .map((s) => s.trim())
  .filter((s): s is Mode => s === "stream" || s === "disk");

const BUCKET = process.env.DSAR_SPIKE_BUCKET ?? "dsar-spike";
const KEEP_OBJECTS = process.env.DSAR_SPIKE_KEEP_OBJECTS === "1";
const TMP_BASE = process.env.DSAR_SPIKE_TMP_DIR ?? tmpdir();
const POLL_MS = 250;
const CHUNK_BYTES = 64 * 1024;
// Per-file ceiling for the bucket (5 GB — well above the 2 GB Hetzner RSS
// ceiling so the bucket itself never becomes the cap). Supabase Pro tier
// supports file sizes up to 500 GB.
const BUCKET_FILE_LIMIT = 5 * 1024 * 1024 * 1024;

interface RunResult {
  sizeMb: number;
  mode: Mode;
  archiveBytes: number;
  peakRssMb: number;
  baselineRssMb: number;
  rssDeltaMb: number;
  wallClockSec: number;
  throughputMBps: number;
  sha256Upload: string;
  sha256Download: string;
  integrityOk: boolean;
  error?: string;
}

// ---------------------------------------------------------------------------
// Synthetic byte generator. Uses node:crypto randomFillSync (native, ~GB/s).
// Per `cq-test-fixtures-synthesized-only` (no real-user data).
// ---------------------------------------------------------------------------
function makeSyntheticFileStream(bytes: number): Readable {
  let remaining = bytes;
  const scratch = Buffer.allocUnsafe(CHUNK_BYTES);
  return new Readable({
    highWaterMark: CHUNK_BYTES,
    read() {
      if (remaining <= 0) {
        this.push(null);
        return;
      }
      const n = Math.min(CHUNK_BYTES, remaining);
      randomFillSync(scratch, 0, n);
      remaining -= n;
      // Copy so subsequent overwrites don't clobber queued chunks.
      this.push(Buffer.from(scratch.subarray(0, n)));
    },
  });
}

// ---------------------------------------------------------------------------
// Archive layout mirroring real DSAR shape. Total bytes ≈ target size.
// ---------------------------------------------------------------------------
function planArchiveLayout(targetBytes: number): Array<{
  name: string;
  bytes: number;
}> {
  const layout: Array<{ name: string; bytes: number }> = [];
  const manifestBytes = 4 * 1024;
  layout.push({ name: "manifest.json", bytes: manifestBytes });

  let remaining = targetBytes - manifestBytes;
  const tablesTotal = Math.floor(remaining * 0.4);
  const attachmentsTotal = Math.floor(remaining * 0.5);
  const workspaceTotal = remaining - tablesTotal - attachmentsTotal;

  const addBucket = (
    prefix: string,
    total: number,
    fileBytes: number,
  ): void => {
    let consumed = 0;
    let i = 0;
    while (consumed < total) {
      const n = Math.min(fileBytes, total - consumed);
      layout.push({ name: `${prefix}/${String(i).padStart(4, "0")}`, bytes: n });
      consumed += n;
      i += 1;
    }
  };

  addBucket("tables", tablesTotal, 10 * 1024 * 1024);
  addBucket("attachments", attachmentsTotal, 8 * 1024 * 1024);
  addBucket("workspace", workspaceTotal, 2 * 1024 * 1024);

  return layout;
}

function buildArchiveSource(
  layout: Array<{ name: string; bytes: number }>,
): { archive: Archive; finalize: Promise<void> } {
  const archive = new ZipArchive({ zlib: { level: 0 } });
  archive.on("warning", (err: NodeJS.ErrnoException) => {
    if (err.code !== "ENOENT") throw err;
  });
  archive.on("error", (err: Error) => {
    throw err;
  });
  for (const entry of layout) {
    archive.append(makeSyntheticFileStream(entry.bytes), { name: entry.name });
  }
  // Hold a reference to the finalize promise so callers can await completion
  // after their consumer drains.
  const finalize = archive.finalize();
  return { archive, finalize };
}

function startRssSampler(): {
  baseline: number;
  stop: () => { peak: number };
} {
  if (global.gc) global.gc();
  const baseline = process.memoryUsage().rss;
  let peak = baseline;
  const id = setInterval(() => {
    const rss = process.memoryUsage().rss;
    if (rss > peak) peak = rss;
  }, POLL_MS);
  return {
    baseline,
    stop: () => {
      clearInterval(id);
      return { peak };
    },
  };
}

// ---------------------------------------------------------------------------
// Re-download the uploaded object via service-role and hash. Streams the
// Blob so we do not spike RSS a second time.
// ---------------------------------------------------------------------------
async function fetchHash(
  service: ReturnType<typeof createServiceClient>,
  objectPath: string,
): Promise<{ sha256: string; error?: string }> {
  try {
    const { data, error } = await service.storage
      .from(BUCKET)
      .download(objectPath);
    if (error) return { sha256: "", error: error.message };
    if (!data) return { sha256: "", error: "download returned no body" };
    const hash = createHash("sha256");
    const reader = (data.stream() as ReadableStream<Uint8Array>).getReader();
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) hash.update(value);
    }
    return { sha256: hash.digest("hex") };
  } catch (err) {
    return {
      sha256: "",
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

// ---------------------------------------------------------------------------
// Mode=stream: archive -> hashPass -> Readable.toWeb() -> SDK upload.
// ---------------------------------------------------------------------------
async function runTierStream(
  service: ReturnType<typeof createServiceClient>,
  sizeMb: number,
): Promise<RunResult> {
  const targetBytes = sizeMb * 1024 * 1024;
  const layout = planArchiveLayout(targetBytes);
  const objectPath = `tier-${sizeMb}mb-stream-${Date.now()}.zip`;

  const sampler = startRssSampler();
  const startedAt = Date.now();

  const { archive, finalize } = buildArchiveSource(layout);
  const uploadHash = createHash("sha256");
  let archiveBytes = 0;
  const hashPass = new PassThrough({ highWaterMark: CHUNK_BYTES });
  hashPass.on("data", (chunk: Buffer) => {
    archiveBytes += chunk.length;
    uploadHash.update(chunk);
  });
  archive.pipe(hashPass);

  const webStream = Readable.toWeb(
    hashPass,
  ) as unknown as ReadableStream<Uint8Array>;

  let uploadError: string | undefined;
  try {
    const { error } = await service.storage
      .from(BUCKET)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      .upload(objectPath, webStream as any, {
        contentType: "application/zip",
        upsert: true,
      });
    if (error) uploadError = error.message;
  } catch (err) {
    uploadError = err instanceof Error ? err.message : String(err);
  }
  await finalize.catch((err) => {
    uploadError = uploadError ?? (err instanceof Error ? err.message : String(err));
  });

  const wallClockSec = (Date.now() - startedAt) / 1000;
  const { peak } = sampler.stop();

  const sha256Upload = uploadHash.digest("hex");
  const { sha256: sha256Download, error: downloadError } = uploadError
    ? { sha256: "", error: undefined as string | undefined }
    : await fetchHash(service, objectPath);

  if (!KEEP_OBJECTS && !uploadError) {
    try {
      await service.storage.from(BUCKET).remove([objectPath]);
    } catch {
      /* best-effort */
    }
  }

  const error = uploadError ?? downloadError;
  const peakRssMb = peak / (1024 * 1024);
  const baselineRssMb = sampler.baseline / (1024 * 1024);
  return {
    sizeMb,
    mode: "stream",
    archiveBytes,
    peakRssMb,
    baselineRssMb,
    rssDeltaMb: peakRssMb - baselineRssMb,
    wallClockSec,
    throughputMBps:
      archiveBytes / (1024 * 1024) / Math.max(wallClockSec, 0.001),
    sha256Upload,
    sha256Download,
    integrityOk:
      !error && sha256Download !== "" && sha256Upload === sha256Download,
    error,
  };
}

// ---------------------------------------------------------------------------
// Mode=disk: archive -> tempfile (hashing en route) -> raw fetch POST with
// fs.createReadStream + duplex: 'half'. Bypasses supabase-js so the SDK's
// body-buffering does not contaminate the measurement.
// ---------------------------------------------------------------------------
async function runTierDisk(
  service: ReturnType<typeof createServiceClient>,
  sizeMb: number,
): Promise<RunResult> {
  const targetBytes = sizeMb * 1024 * 1024;
  const layout = planArchiveLayout(targetBytes);
  const objectPath = `tier-${sizeMb}mb-disk-${Date.now()}.zip`;
  const tmpDir = mkdtempSync(path.join(TMP_BASE, "dsar-spike-"));
  const tmpFile = path.join(tmpDir, `tier-${sizeMb}mb.zip`);

  const sampler = startRssSampler();
  const startedAt = Date.now();

  // Phase A — archive to disk.
  const { archive, finalize } = buildArchiveSource(layout);
  const uploadHash = createHash("sha256");
  let archiveBytes = 0;
  const hashPass = new PassThrough({ highWaterMark: CHUNK_BYTES });
  hashPass.on("data", (chunk: Buffer) => {
    archiveBytes += chunk.length;
    uploadHash.update(chunk);
  });

  let phaseAError: string | undefined;
  try {
    await pipeline(archive, hashPass, createWriteStream(tmpFile));
    await finalize.catch(() => {
      /* finalize fires after pipe completes; ignore double-end */
    });
  } catch (err) {
    phaseAError = err instanceof Error ? err.message : String(err);
  }
  const sha256Upload = uploadHash.digest("hex");

  // Phase B — fetch POST from disk stream. Bypass supabase-js entirely.
  let phaseBError: string | undefined;
  if (!phaseAError) {
    const fileSize = statSync(tmpFile).size;
    const url = `${serverUrl()}/storage/v1/object/${encodeURIComponent(
      BUCKET,
    )}/${encodeURIComponent(objectPath)}`;
    const token = process.env.SUPABASE_SERVICE_ROLE_KEY!;
    const body = createReadStream(tmpFile, { highWaterMark: 1024 * 1024 });

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          apikey: token,
          "Content-Type": "application/zip",
          "Content-Length": String(fileSize),
          "x-upsert": "true",
        },
        body: Readable.toWeb(body) as unknown as ReadableStream<Uint8Array>,
        // @ts-expect-error -- undici-only option; TS lib.dom lacks it.
        duplex: "half",
      });
      if (!res.ok) {
        const txt = await res.text();
        phaseBError = `HTTP ${res.status}: ${txt.slice(0, 200)}`;
      }
    } catch (err) {
      phaseBError = err instanceof Error ? err.message : String(err);
    }
  }

  const wallClockSec = (Date.now() - startedAt) / 1000;
  const { peak } = sampler.stop();

  const uploadError = phaseAError ?? phaseBError;
  const { sha256: sha256Download, error: downloadError } = uploadError
    ? { sha256: "", error: undefined as string | undefined }
    : await fetchHash(service, objectPath);

  if (!KEEP_OBJECTS && !uploadError) {
    try {
      await service.storage.from(BUCKET).remove([objectPath]);
    } catch {
      /* best-effort */
    }
  }
  try {
    rmSync(tmpDir, { recursive: true, force: true });
  } catch {
    /* best-effort */
  }

  const error = uploadError ?? downloadError;
  const peakRssMb = peak / (1024 * 1024);
  const baselineRssMb = sampler.baseline / (1024 * 1024);
  return {
    sizeMb,
    mode: "disk",
    archiveBytes,
    peakRssMb,
    baselineRssMb,
    rssDeltaMb: peakRssMb - baselineRssMb,
    wallClockSec,
    throughputMBps:
      archiveBytes / (1024 * 1024) / Math.max(wallClockSec, 0.001),
    sha256Upload,
    sha256Download,
    integrityOk:
      !error && sha256Download !== "" && sha256Upload === sha256Download,
    error,
  };
}

// ---------------------------------------------------------------------------
// Bucket setup. Create with explicit fileSizeLimit; updateBucket if the
// existing bucket has a smaller limit (idempotent across re-runs).
// ---------------------------------------------------------------------------
async function ensureBucket(
  service: ReturnType<typeof createServiceClient>,
): Promise<void> {
  const { data, error } = await service.storage.listBuckets();
  if (error) throw new Error(`listBuckets failed: ${error.message}`);
  const existing = (data ?? []).find((b) => b.name === BUCKET);
  if (existing) {
    const { error: updErr } = await service.storage.updateBucket(BUCKET, {
      public: false,
      fileSizeLimit: BUCKET_FILE_LIMIT,
    });
    if (updErr) {
      console.warn(
        `[spike] updateBucket(${BUCKET}) returned: ${updErr.message} (continuing — pre-existing limit may be sufficient)`,
      );
    }
    return;
  }
  const { error: createErr } = await service.storage.createBucket(BUCKET, {
    public: false,
    fileSizeLimit: BUCKET_FILE_LIMIT,
  });
  if (createErr) {
    throw new Error(`createBucket(${BUCKET}) failed: ${createErr.message}`);
  }
  console.log(
    `[spike] created private bucket "${BUCKET}" with fileSizeLimit ${BUCKET_FILE_LIMIT}`,
  );
}

function formatResult(r: RunResult): string {
  const ok = r.integrityOk ? "OK" : r.error ? `ERR(${r.error.slice(0, 60)})` : "SHA_MISMATCH";
  return [
    String(r.sizeMb).padStart(5),
    r.mode.padStart(6),
    (r.archiveBytes / (1024 * 1024)).toFixed(1).padStart(8),
    r.baselineRssMb.toFixed(1).padStart(8),
    r.peakRssMb.toFixed(1).padStart(8),
    r.rssDeltaMb.toFixed(1).padStart(8),
    r.wallClockSec.toFixed(1).padStart(7),
    r.throughputMBps.toFixed(1).padStart(6),
    ok,
  ].join("  ");
}

async function main(): Promise<void> {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY not set. Run via: doppler run -p soleur -c dev -- ./node_modules/.bin/tsx scripts/spike/dsar-streaming-upload.ts",
    );
  }
  const service = createServiceClient();
  await ensureBucket(service);

  console.log(
    `[spike] node=${process.version} sizes=${SIZES_MB.join(",")} modes=${MODES.join(",")} bucket=${BUCKET}`,
  );
  console.log(
    "tier(MB)    mode   archMB   baseRSS   peakRSS  deltaRSS  wall(s)   MB/s  integrity",
  );

  const results: RunResult[] = [];
  for (const sz of SIZES_MB) {
    for (const mode of MODES) {
      try {
        const r =
          mode === "stream"
            ? await runTierStream(service, sz)
            : await runTierDisk(service, sz);
        results.push(r);
        console.log(formatResult(r));
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[spike] tier ${sz} MB mode=${mode} threw: ${msg}`);
        results.push({
          sizeMb: sz,
          mode,
          archiveBytes: 0,
          peakRssMb: 0,
          baselineRssMb: 0,
          rssDeltaMb: 0,
          wallClockSec: 0,
          throughputMBps: 0,
          sha256Upload: "",
          sha256Download: "",
          integrityOk: false,
          error: msg,
        });
      }
    }
  }

  console.log("");
  for (const mode of MODES) {
    const passing = results.filter(
      (r) => r.mode === mode && r.integrityOk && r.peakRssMb < 2048,
    );
    const cap = passing.length
      ? passing.reduce((a, b) => (a.sizeMb > b.sizeMb ? a : b))
      : null;
    if (cap) {
      console.log(
        `[spike] mode=${mode}: largest passing tier ${cap.sizeMb} MB (peak ${cap.peakRssMb.toFixed(1)} MB)`,
      );
    } else {
      console.log(`[spike] mode=${mode}: NO tier passed within 2 GB ceiling`);
    }
  }
}

main().catch((err) => {
  console.error("[spike] fatal:", err);
  process.exit(1);
});
