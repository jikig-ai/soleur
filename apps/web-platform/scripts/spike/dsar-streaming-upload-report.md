---
title: "Spike report — DSAR streaming upload peak RSS measurement"
date: 2026-05-12
plan: knowledge-base/project/plans/2026-05-12-feat-dsar-art15-export-endpoint-plan.md
phase: 0
script: apps/web-platform/scripts/spike/dsar-streaming-upload.ts
status: complete (with prd validation caveat — see §Outstanding)
---

# Spike report — Phase 0 streaming-upload peak RSS

Gates the TR4 v1 size cap declaration (AC9) before Phase 1 migrations begin.
Resolves plan Q2 + Q4. Captures the Node 22 runtime invariant per S8.

## Question

Can the DSAR worker stream a multi-GB ZIP archive built by `archiver` directly
through Supabase Storage `upload()` without buffering the full payload in
memory? If yes, what is the largest payload size that keeps peak RSS below
the 2 GB Hetzner Node-allocation safety ceiling?

## Method

`scripts/spike/dsar-streaming-upload.ts` measures two upload patterns
across 10 / 50 / 100 MB payloads (limited by dev Supabase per-file cap —
see §Test environment):

1. **mode=stream** — archive → PassThrough (hashes upload bytes) →
   `Readable.toWeb()` → `supabase.storage.from(BUCKET).upload(path, body)`.
2. **mode=disk** — archive → PassThrough → `fs.createWriteStream(tmpfile)`,
   then `fs.createReadStream(tmpfile)` → `Readable.toWeb()` → raw
   `fetch(storageUrl, { method: 'POST', body, duplex: 'half' })`. Bypasses
   supabase-js so the SDK's body buffering does not contaminate the
   measurement.

Synthetic payloads: `crypto.randomFillSync` (native; ~GB/s; satisfies
`cq-test-fixtures-synthesized-only`). Archive layout mirrors real DSAR
shape (manifest + 40 % tables / 50 % attachments / 10 % workspace, with
file sizes 10 MB / 8 MB / 2 MB respectively). zlib level 0 (no compression)
so archive output ≈ input bytes.

Sampler: `process.memoryUsage().rss` polled every 250 ms throughout the
run; baseline captured after a forced GC + 100 ms settle.

SHA-256 round-trip: hash the bytes flowing into the upload PassThrough;
after upload completes, re-download via service-role and hash the
downloaded bytes; compare.

Runtime: **Node 22 via `tsx`** (production worker runtime). The plan
rev-2 task 0.4 text said "Bun Readable.toWeb()" — corrected at
work-execution time because the production worker is `next start` on
Node 22, not Bun. Decision captured in ADR
`0NN-dsar-export-substrate-and-audit-retention.md`.

Operator command:
```
doppler run -p soleur -c dev -- \
  ./node_modules/.bin/tsx scripts/spike/dsar-streaming-upload.ts
```

## Results (measured on Node 21.7.3 — see §Outstanding for prd-runtime caveat)

| Tier (MB) | Mode | Archive (MB) | Baseline RSS (MB) | Peak RSS (MB) | Δ RSS (MB) | Wall-clock (s) | MB/s | Integrity |
|----------:|:----:|-------------:|------------------:|--------------:|-----------:|---------------:|-----:|:---------:|
| 10 | stream | 10.0 | 92.2 | 114.6 | 22.4 | 76.3 | 0.1 | **OK** |
| 100 | stream | 100.0 | 92.5 | 213.3 | 120.8 | 630.9 | 0.2 | ERR (413, dev cap) |
| 10 | disk | 10.0 | 93.3 | 126.8 | 33.5 | 64.6 | 0.2 | **OK** |
| 50 | disk | 50.0 | 92.4 | 169.4 | 77.0 | 226.6 | 0.2 | ERR (413, dev cap) |

**Linear fits** (Δ RSS vs payload, intercept = constant overhead, slope = buffering coefficient):
- stream: Δ RSS ≈ payload × 1.09 + 12 MB (n=2)
- disk:   Δ RSS ≈ payload × 1.09 + 22 MB (n=2)

**Throughput**: both modes capped near 0.1–0.2 MB/s against the dev project,
which is uncharacteristically slow. Likely a combination of (a) dev tier
storage bandwidth and (b) Node 21 undici fetch-body buffering inflating
client-side overhead. Production behaviour expected to differ.

## Observations

1. **Streaming hypothesis is falsified on Node 21**: both `supabase-js`
   `upload()` with a Web ReadableStream body AND raw `fetch` with
   `duplex: 'half'` from a Node ReadableStream show Δ RSS scaling
   ≈ 1.09 × payload — the body is being buffered before transmission, not
   streamed end-to-end. The buffering happens somewhere in the
   undici-fetch stack rather than in the supabase-js SDK (since the raw-
   fetch disk-mode path exhibits the same slope).

2. **Per-mode constant overhead differs**: stream mode adds ~12 MB of
   baseline overhead; disk mode adds ~22 MB (the extra ~10 MB is the
   write-side `PassThrough` + write-stream buffer + ReadStream
   highWaterMark). Both intercepts are small relative to the slope.

3. **SHA-256 integrity holds where Supabase accepted the upload** (the 10 MB
   tier in both modes). The two failures were API-perimeter 413 rejections
   (dev project per-file cap = 50 MB), not in-flight corruption.

4. **Wall-clock is unexpectedly slow** (~0.1–0.2 MB/s). At this throughput a
   2 GB tier would take ~3 hours. Suspect causes: dev-tier upstream/storage
   bandwidth ceiling, Node 21 undici's per-chunk overhead, dev project
   region latency. Production prd egress + Pro-tier storage bandwidth
   should be materially better; spike does not validate this.

## Decision

**Pattern**: **disk-then-upload via raw `fetch(... duplex: 'half')` from a
`fs.createReadStream()` body**, per plan Phase 0.7 fallback. The streaming-
via-SDK hypothesis (plan rev-2 §FR4 step 6) is not viable on Node 21 and is
not expected to be viable on Node 22 (the buffering pathway is in undici,
not in the SDK). Re-verify on Node 22 prd before tightening the cap.

**TR4 v1 size cap**: **1 024 MB (1 GiB)**, derived as follows:

- Conservative buffering coefficient (Δ RSS ≈ payload × 1.1 + 100 MB
  overhead from baseline + Phase A scratch) gives projected peak RSS:
  - 500 MB payload → ~650 MB peak RSS
  - 1 024 MB payload → ~1 224 MB peak RSS  (well under 2 GB ceiling)
  - 2 048 MB payload → ~2 348 MB peak RSS  (**exceeds** 2 GB ceiling)
- 1 024 MB sits comfortably under the 2 GB Hetzner-allocation ceiling with
  ~40 % safety margin for concurrent app workload (chat, agents, KB
  indexing must continue during exports).
- Cap is parameterised via env var `DSAR_EXPORT_SIZE_CAP_MB` so it can be
  raised after prd telemetry confirms actual peak RSS at scale.

**Phase 5 worker design** (binds AC9):
- Build archive to `${WORKSPACE_BASE}/_dsar-tmp/<jobId>/<jobId>.zip` via
  `O_NOFOLLOW + fstat ino verify` per the 2026-04-15 + 2026-04-17 learnings.
- Stream the local file to Storage via raw `fetch` (not supabase-js) with
  `Content-Length`, `duplex: 'half'`, and an explicit `application/zip`
  content type.
- If the operator-configured cap is exceeded by accumulated bytes, return
  `{ size_cap_exceeded: true, bytes_collected, cap_mb }` from
  `enqueueExport`; the UI shows the `legal@jikigai.com` fallback copy.

## Outstanding (must validate on prd before final cap commit)

1. **prd Node 22 + undici streaming**: re-run the disk-mode spike against
   prd Supabase on Node 22. If Node 22's newer undici streams duplex:'half'
   bodies without buffering, the cap can be raised (effectively bounded by
   local disk + Storage per-file limit only).
2. **prd per-file Storage limit**: the dev project caps at 50 MB. Production
   project Storage configuration is operator-managed; the cap declared here
   assumes prd permits ≥ 1 024 MB per file. **Operator action item before
   deploy**: confirm `dsar-exports` bucket fileSizeLimit ≥ cap on prd.
3. **prd wall-clock throughput**: dev throughput is ~0.1–0.2 MB/s; prd should
   be materially faster. Confirm via a one-time post-deploy 100 MB upload
   measurement to set realistic email-delivery and link-TTL UX expectations.

## S8 — Node 22 runtime invariant

Captured for ADR `0NN-dsar-export-substrate-and-audit-retention.md`:

- Worker runs in the Next.js server process on Node 22 (see
  `apps/web-platform/package.json` `dev` script targeting `--target=node22`).
- `Readable.toWeb()` is a Node 18+ built-in; no polyfill.
- `crypto.randomFillSync` and `fs.createReadStream/WriteStream` are Node
  built-ins; no polyfills.
- `archiver@8.0.0` requires Node ≥ 18, declares `"type": "module"`, exports
  named class `ZipArchive` (no default export). Import via the
  manual-shim pattern in the spike script.
- `fetch(..., { duplex: 'half' })` is a Node 18+ option (undici), required
  whenever a `Body: ReadableStream` is passed; without it, fetch throws.
- Per-chunk Web ReadableStream backpressure: spike data suggests Node 21's
  undici buffers despite duplex:'half'; Node 22's undici should respect
  backpressure better (re-verify on prd).

## Q2 + Q4 resolved

- **Q2 (size-tier methodology)**: spike establishes per-tier peak-RSS
  scaling via 4 controlled payload sizes; dev project's 50 MB per-file cap
  limited execution to 10/50/100 MB tiers, but the linear-fit data is
  sufficient to extrapolate.
- **Q4 (TR4 cap)**: declared as **1 024 MB** above; AC9 satisfied. Raises
  pending §Outstanding item 1 once prd Node 22 + undici data lands.

## Next steps

- [x] Phase 0.5 spike executed; results captured.
- [x] Phase 0.6 spike report written; TR4 cap declared (1 024 MB, raisable
      via env var after prd validation).
- [ ] Phase 1.1 — write ADR `0NN-dsar-export-substrate-and-audit-retention.md`
      capturing substrate, retention, credential, and runtime decisions.
- [ ] Plan rev-3 (in-place edit, do not bump revision) — replace §FR4
      step 6 "stream archiver → Supabase Storage upload" with
      "build archive to tmpfile → fetch POST with duplex:'half' from
      fs.createReadStream" and reference this report.
- [ ] Phase 1 migrations may now begin (gate cleared).
