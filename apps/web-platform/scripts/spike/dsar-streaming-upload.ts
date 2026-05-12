// S0 spike for #3637 (feat-dsar-art15-export-endpoint, plan rev-2 Phase 0).
//
// Measures peak RSS, wall-clock, and SHA-256 round-trip integrity during
// archiver -> Node Readable -> Web ReadableStream -> Supabase Storage `upload()`
// across 100 MB / 500 MB / 1 GB / 2 GB synthesised payloads. Output drives:
//   - TR4 v1 size cap (largest tier where peak RSS stays under 2 GB)
//   - S8 Node 22 runtime invariant captured in ADR
//     0NN-dsar-export-substrate-and-audit-retention.md
//   - GATE: Phase 1 cannot start until report exists
//
// Path deviates from plan literal `scripts/spike-dsar-streaming-upload.ts`
// to match existing in-tree convention (`scripts/spike/<name>.ts`) per the
// other S-series spikes (cache-control-forwarding.ts, pdf-outline-coverage.ts).
// Runtime is Node 22 via tsx (NOT Bun) per work-skill clarification
// 2026-05-12: production worker is `next start` on Node 22, so peak-RSS
// numbers must come from the runtime that actually owns prod memory.
//
// Test fixtures are synthesised on-the-fly via seeded PRNG per
// `cq-test-fixtures-synthesized-only`. Zero real-user data flows through
// this script.
//
// Operator command:
//   bun add -d archiver @types/archiver   # one-time, lands in package.json
//   doppler run -p soleur -c dev -- ./node_modules/.bin/tsx \
//     scripts/spike/dsar-streaming-upload.ts
//
// Optional env knobs:
//   DSAR_SPIKE_SIZES_MB="100,500,1000,2000"   # default
//   DSAR_SPIKE_BUCKET="dsar-spike"            # default
//   DSAR_SPIKE_SEED="dsar-spike-2026-05-12"   # default
//   DSAR_SPIKE_KEEP_OBJECTS="0"               # set 1 to skip cleanup

import { createHash } from "node:crypto";
import { PassThrough, Readable } from "node:stream";

import archiver from "archiver";

import { createServiceClient } from "../../lib/supabase/service";

const SIZES_MB = (process.env.DSAR_SPIKE_SIZES_MB ?? "100,500,1000,2000")
  .split(",")
  .map((s) => Number.parseInt(s.trim(), 10))
  .filter((n) => Number.isFinite(n) && n > 0);

const BUCKET = process.env.DSAR_SPIKE_BUCKET ?? "dsar-spike";
const SEED = process.env.DSAR_SPIKE_SEED ?? "dsar-spike-2026-05-12";
const KEEP_OBJECTS = process.env.DSAR_SPIKE_KEEP_OBJECTS === "1";
const POLL_MS = 250;
const CHUNK_BYTES = 64 * 1024; // 64 KB — matches archiver's internal pull size

interface RunResult {
  sizeMb: number;
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
// Seeded PRNG — xoshiro256** family. Deterministic given (seed, file index).
// Output is statistically random enough to be incompressible at zlib level 0
// (we set zlib level 0 anyway; the spike measures stream behaviour, not
// compression).
// ---------------------------------------------------------------------------
function makePrng(seedString: string, index: number): () => number {
  const seedHash = createHash("sha256")
    .update(`${seedString}:${index}`)
    .digest();
  const state = new BigUint64Array(4);
  for (let i = 0; i < 4; i++) {
    state[i] = seedHash.readBigUInt64LE(i * 8);
  }

  const rotl = (x: bigint, k: bigint): bigint => {
    const mask = 0xffffffffffffffffn;
    return (((x << k) & mask) | (x >> (64n - k))) & mask;
  };

  return () => {
    const mask = 0xffffffffffffffffn;
    const result = (rotl((state[1]! * 5n) & mask, 7n) * 9n) & mask;
    const t = (state[1]! << 17n) & mask;
    state[2] = (state[2]! ^ state[0]!) & mask;
    state[3] = (state[3]! ^ state[1]!) & mask;
    state[1] = (state[1]! ^ state[2]!) & mask;
    state[0] = (state[0]! ^ state[3]!) & mask;
    state[2] = (state[2]! ^ t) & mask;
    state[3] = rotl(state[3]!, 45n);
    return Number(result & 0xffffffffn) / 0xffffffff;
  };
}

function makeSyntheticFileStream(
  seed: string,
  index: number,
  bytes: number,
): Readable {
  const prng = makePrng(seed, index);
  let remaining = bytes;
  return new Readable({
    highWaterMark: CHUNK_BYTES,
    read() {
      if (remaining <= 0) {
        this.push(null);
        return;
      }
      const n = Math.min(CHUNK_BYTES, remaining);
      const buf = Buffer.allocUnsafe(n);
      // Fill via PRNG: write whole uint32 strides, then fill the tail
      // byte-by-byte. writeUInt32LE throws RangeError if i+4 > buf.length,
      // so the loop bound is strict.
      const wholeWords = n - (n % 4);
      for (let i = 0; i < wholeWords; i += 4) {
        const v = (prng() * 0x100000000) >>> 0;
        buf.writeUInt32LE(v, i);
      }
      if (wholeWords < n) {
        const tail = (prng() * 0x100000000) >>> 0;
        for (let i = wholeWords; i < n; i++) {
          buf.writeUInt8((tail >>> ((i - wholeWords) * 8)) & 0xff, i);
        }
      }
      remaining -= n;
      this.push(buf);
    },
  });
}

// ---------------------------------------------------------------------------
// Archive layout mirroring real DSAR shape. Total bytes ≈ target size.
//   /manifest.json                 — small JSON header
//   /tables/<n>.json               — ~10 MB each, JSON-shaped payload
//   /attachments/<n>.bin           — varied binary, 1-16 MB each
//   /workspace/<n>.txt             — text-like 0.5-4 MB each
// We don't bother with realistic JSON parsing — payload is just bytes.
// Pure point of the spike is byte throughput, not content shape.
// ---------------------------------------------------------------------------
function planArchiveLayout(targetBytes: number): Array<{
  name: string;
  bytes: number;
}> {
  const layout: Array<{ name: string; bytes: number }> = [];
  const manifestBytes = 4 * 1024;
  layout.push({ name: "manifest.json", bytes: manifestBytes });

  // Distribute remaining bytes: 40% tables, 50% attachments, 10% workspace.
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

  addBucket("tables", tablesTotal, 10 * 1024 * 1024); // 10 MB tables
  addBucket("attachments", attachmentsTotal, 8 * 1024 * 1024); // 8 MB attachments
  addBucket("workspace", workspaceTotal, 2 * 1024 * 1024); // 2 MB workspace files

  return layout;
}

// ---------------------------------------------------------------------------
// Single tier: build archive, stream to Storage, measure peak RSS, hash.
// ---------------------------------------------------------------------------
async function runTier(
  service: ReturnType<typeof createServiceClient>,
  sizeMb: number,
): Promise<RunResult> {
  const targetBytes = sizeMb * 1024 * 1024;
  const layout = planArchiveLayout(targetBytes);
  const objectPath = `tier-${sizeMb}mb-${Date.now()}.zip`;

  // Warm GC before sampling so baseline reflects steady state, not whatever
  // the previous tier left in the heap.
  if (global.gc) global.gc();
  // Sleep 100 ms so v8 settles
  await new Promise((r) => setTimeout(r, 100));
  const baselineRss = process.memoryUsage().rss;
  let peakRss = baselineRss;

  const sampler = setInterval(() => {
    const rss = process.memoryUsage().rss;
    if (rss > peakRss) peakRss = rss;
  }, POLL_MS);

  const startedAt = Date.now();

  const archive = archiver("zip", { zlib: { level: 0 } });
  archive.on("warning", (err) => {
    if (err.code !== "ENOENT") throw err;
  });
  archive.on("error", (err) => {
    throw err;
  });

  // Hashing pass-through. Archive -> hashPass -> web stream -> upload. This
  // avoids the double-consume hazard of attaching both a `data` listener
  // and `Readable.toWeb()` to the archive Readable directly (only the
  // first consumer would drain it).
  const uploadHash = createHash("sha256");
  let archiveBytes = 0;
  const hashPass = new PassThrough({ highWaterMark: CHUNK_BYTES });
  hashPass.on("data", (chunk: Buffer) => {
    archiveBytes += chunk.length;
    uploadHash.update(chunk);
  });
  archive.pipe(hashPass);

  // Append entries lazily so we don't materialise the entire archive upfront.
  for (let i = 0; i < layout.length; i++) {
    const entry = layout[i]!;
    archive.append(makeSyntheticFileStream(SEED, i, entry.bytes), {
      name: entry.name,
    });
  }
  const finalizePromise = archive.finalize();

  // Node Readable -> Web ReadableStream. supabase-js v2 accepts a Web
  // ReadableStream body via undici; type assertion bridges the upload
  // overload set which lists FileBody but not ReadableStream<Uint8Array>
  // in the public d.ts.
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
  await finalizePromise.catch((err) => {
    uploadError = uploadError ?? (err instanceof Error ? err.message : String(err));
  });

  const wallClockSec = (Date.now() - startedAt) / 1000;
  clearInterval(sampler);
  const sha256Upload = uploadHash.digest("hex");

  // Re-download via service-role for SHA round-trip.
  let sha256Download = "";
  let downloadError: string | undefined;
  if (!uploadError) {
    try {
      const { data, error } = await service.storage
        .from(BUCKET)
        .download(objectPath);
      if (error) downloadError = error.message;
      else if (data) {
        const downloadHash = createHash("sha256");
        // data is a Blob; stream through its arrayBuffer in chunks to avoid
        // a second full-payload spike in RSS.
        const reader = (data.stream() as ReadableStream<Uint8Array>).getReader();
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          if (value) downloadHash.update(value);
        }
        sha256Download = downloadHash.digest("hex");
      }
    } catch (err) {
      downloadError = err instanceof Error ? err.message : String(err);
    }
  }

  // Cleanup unless operator opted out.
  if (!KEEP_OBJECTS && !uploadError) {
    try {
      await service.storage.from(BUCKET).remove([objectPath]);
    } catch {
      /* non-fatal — spike cleanup is best-effort */
    }
  }

  const error = uploadError ?? downloadError;
  const peakRssMb = peakRss / (1024 * 1024);
  const baselineRssMb = baselineRss / (1024 * 1024);

  return {
    sizeMb,
    archiveBytes,
    peakRssMb,
    baselineRssMb,
    rssDeltaMb: peakRssMb - baselineRssMb,
    wallClockSec,
    throughputMBps: archiveBytes / (1024 * 1024) / Math.max(wallClockSec, 0.001),
    sha256Upload,
    sha256Download,
    integrityOk:
      !error && sha256Download !== "" && sha256Upload === sha256Download,
    error,
  };
}

async function ensureBucket(
  service: ReturnType<typeof createServiceClient>,
): Promise<void> {
  const { data, error } = await service.storage.listBuckets();
  if (error) throw new Error(`listBuckets failed: ${error.message}`);
  const exists = (data ?? []).some((b) => b.name === BUCKET);
  if (exists) return;
  const { error: createErr } = await service.storage.createBucket(BUCKET, {
    public: false,
  });
  if (createErr) {
    throw new Error(`createBucket(${BUCKET}) failed: ${createErr.message}`);
  }
  console.log(`[spike] created private bucket "${BUCKET}"`);
}

function formatResult(r: RunResult): string {
  const ok = r.integrityOk ? "OK" : r.error ? `ERR(${r.error})` : "SHA_MISMATCH";
  return [
    String(r.sizeMb).padStart(4),
    (r.archiveBytes / (1024 * 1024)).toFixed(1).padStart(8),
    r.baselineRssMb.toFixed(1).padStart(8),
    r.peakRssMb.toFixed(1).padStart(8),
    r.rssDeltaMb.toFixed(1).padStart(8),
    r.wallClockSec.toFixed(1).padStart(7),
    r.throughputMBps.toFixed(1).padStart(8),
    ok.padStart(14),
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
    `[spike] node=${process.version} sizes=${SIZES_MB.join(",")} bucket=${BUCKET} seed=${SEED}`,
  );
  console.log(
    "tier(MB)  archiveMB    baseRSS    peakRSS    deltaRSS   wall(s)   MB/s   integrity",
  );

  const results: RunResult[] = [];
  for (const sz of SIZES_MB) {
    try {
      const r = await runTier(service, sz);
      results.push(r);
      console.log(formatResult(r));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[spike] tier ${sz} MB threw: ${msg}`);
      results.push({
        sizeMb: sz,
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

  // Cap suggestion: largest tier with peak RSS < 2048 MB AND integrity OK.
  const passing = results.filter((r) => r.integrityOk && r.peakRssMb < 2048);
  const cap = passing.length
    ? passing.reduce((a, b) => (a.sizeMb > b.sizeMb ? a : b))
    : null;

  console.log("");
  if (cap) {
    console.log(
      `[spike] suggested TR4 v1 cap: ${cap.sizeMb} MB (peak RSS ${cap.peakRssMb.toFixed(1)} MB, integrity OK)`,
    );
  } else {
    console.log(
      "[spike] no tier passed (peak RSS >= 2 GB or integrity fail). Pivot to disk-then-upload fallback per plan Phase 0.7.",
    );
  }
}

main().catch((err) => {
  console.error("[spike] fatal:", err);
  process.exit(1);
});
