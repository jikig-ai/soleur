---
title: "perf(kb): PDF linearization on upload via qpdf"
type: perf
issue: 2456
pr: 2457
brainstorm: knowledge-base/project/brainstorms/2026-04-17-pdf-linearization-on-upload-brainstorm.md
spec: knowledge-base/project/specs/feat-pdf-linearization/spec.md
branch: pdf-linearization
worktree: .worktrees/pdf-linearization
date: 2026-04-17
status: planned
---

# Plan: PDF Linearization on Upload via `qpdf` Subprocess

## Overview

Introduce a server-side subprocess step that linearizes `.pdf` uploads via `qpdf --linearize` before they are committed to the user's GitHub repo by `apps/web-platform/app/api/kb/upload/route.ts`. Pairs with the read-path Range + `disableAutoFetch` fixes from #2451/#2452/#2455 to deliver page-1 rendering within ~2s for newly-uploaded PDFs of any size up to the 20MB upload cap.

This is the **write-side** half of the progressive-rendering rule introduced as `cq-progressive-rendering-for-large-assets` in `AGENTS.md`. Read path stays untouched.

The plan rejects the original issue proposal (on-demand linearization with 250MB in-memory LRU cache) in favor of on-upload linearization. Rationale is captured in the brainstorm — short version: KB content lives in the user's git repo, not R2; caching a deterministic transform of immutable git-committed content in volatile per-replica RAM is the wrong tier.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| TR6: "Upload route `maxDuration` export (if present) MUST accommodate the subprocess timeout plus GitHub commit latency. Align to a single value (suggested 30s) and document." | `apps/web-platform/app/api/kb/upload/route.ts` has **no** `maxDuration`, `runtime`, or `dynamic` exports. Next.js default is 10s. | Phase 2 **adds** `export const maxDuration = 30` to the route file — one of the HTTP-only-allowed exports per rule `cq-nextjs-route-files-http-only-exports`. |
| TR2: "Spawns `qpdf --linearize - -` via `child_process.spawn`, pipes input via stdin, collects stdout." | **Preflight result (Phase 2 Task 2.0):** qpdf 11.3.0 in `node:22-slim` rejects stdin input — `qpdf --help=usage` explicitly states `reading from stdin is not supported`. Falls back to plan Task 2.0.1 (tempfile I/O). Helper writes input Buffer to `/tmp/pdf-linearize-in-<hex>.pdf`, spawns `qpdf --linearize <in> <out>`, reads `<out>`, unlinks both in a `finally`. `stdio: ["ignore", "pipe", "pipe"]`. The `{ ok, reason }` contract and test shape are preserved; the helper uses `spawn` + `fs/promises` rather than stdin streaming. |
| Spec was silent on subprocess env handling. | Learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` documents CWE-526 env leak when `{ ...process.env }` is passed to `spawn`. | Helper passes an inline env allowlist (`PATH`, `HOME`, `LANG`, `LC_ALL`, `TMPDIR`), never `process.env` spread. Enforced via exit-criterion grep. |
| TR1: "Add `qpdf` to the runner stage of `apps/web-platform/Dockerfile`." | Runner stage at `Dockerfile:32`, existing `apt-get install` on lines 39–41. Learning `2026-04-06-node-slim-missing-ca-certificates.md` specifies "extend the existing line, not a new RUN layer." | Phase 2 appends `qpdf` to the **existing** apt-get line, no new `RUN` layer. |
| AC1 + Spec R4 assume `qpdf` is in `node:22-slim` apt sources AND that `qpdf --linearize - -` works with piped stdin/stdout. | Availability **and** the stdin/stdout pipe form are both unverified. Kieran challenge: `-` may not be supported, which would collapse the helper design. | Phase 2 Task 2.0 pipes a real fixture PDF through `qpdf --linearize - -` inside the runner image and runs `qpdf --check` on the output. No Phase 3 work until this passes. If `-` piping fails, the plan pivots to a tempfile I/O helper. |

## Files to Create / Modify

**Create:**

- `apps/web-platform/server/pdf-linearize.ts` — helper wrapping `child_process.spawn` around `qpdf --linearize`.
- `apps/web-platform/test/pdf-linearize.test.ts` — unit tests for the helper.

**Modify:**

- `apps/web-platform/app/api/kb/upload/route.ts` — add `export const maxDuration = 30`; call the helper for PDF uploads between `Buffer.concat(chunks)` and the GitHub PUT.
- `apps/web-platform/Dockerfile` — add `qpdf` to the runner-stage `apt-get install` line (line 40).
- `apps/web-platform/test/kb-upload.test.ts` — add three cases: linearize success, linearize failure (fallback + warn), non-PDF skip.

**No changes (deliberate):**

- `apps/web-platform/server/kb-binary-response.ts` (read path).
- PDF viewer client code under `apps/web-platform/components/**`.
- Any npm dependencies.

### Mechanical UX-Gate Escalation Check

Files to create match **none** of `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product/UX tier: **NONE**. No UX artifacts required.

## Implementation Phases

### Phase 1 — Helper Module + RED tests (TDD)

**Goal:** Produce `pdf-linearize.ts` with full unit coverage. Tests first per `cq-write-failing-tests-before`.

Task 1.1 — Write failing tests at `apps/web-platform/test/pdf-linearize.test.ts`. Use a relative import for the module under test (the `@/` alias is a Next.js path alias and is not guaranteed to resolve in the vitest config):

```ts
// apps/web-platform/test/pdf-linearize.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

const { mockSpawn } = vi.hoisted(() => ({ mockSpawn: vi.fn() }));
vi.mock("node:child_process", () => ({ spawn: mockSpawn }));

import { linearizePdf } from "../server/pdf-linearize";

type FakeChildOpts = {
  stdoutChunks?: Buffer[];
  stderrChunks?: Buffer[];
  exitCode?: number | null;
  exitSignal?: NodeJS.Signals | null;
  spawnError?: Error;
  holdStdinOpen?: boolean;
};

function fakeChild(opts: FakeChildOpts) {
  const child = new EventEmitter() as EventEmitter & {
    stdin: PassThrough;
    stdout: PassThrough;
    stderr: PassThrough;
    kill: ReturnType<typeof vi.fn>;
  };
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = vi.fn();

  if (opts.spawnError) {
    // Emit error on nextTick so handlers registered synchronously see it
    queueMicrotask(() => child.emit("error", opts.spawnError!));
    return child;
  }

  // Push stdout/stderr content synchronously, then end, THEN emit close.
  // This guarantees 'data' events drain before 'close' settles the promise.
  queueMicrotask(() => {
    for (const c of opts.stdoutChunks ?? []) child.stdout.write(c);
    for (const c of opts.stderrChunks ?? []) child.stderr.write(c);
    child.stdout.end();
    child.stderr.end();
    if (!opts.holdStdinOpen) {
      queueMicrotask(() => child.emit("close", opts.exitCode ?? 0, opts.exitSignal ?? null));
    }
  });

  return child;
}

beforeEach(() => mockSpawn.mockReset());

describe("linearizePdf", () => {
  it("returns ok=true with linearized bytes on exit 0", async () => {
    const linearized = Buffer.from("%PDF-1.7-linearized");
    mockSpawn.mockReturnValue(fakeChild({ stdoutChunks: [linearized], exitCode: 0 }));
    const result = await linearizePdf(Buffer.from("%PDF-1.7-original"));
    expect(result).toEqual({ ok: true, buffer: linearized });
  });

  it("returns ok=false reason=non_zero_exit on non-zero exit", async () => {
    mockSpawn.mockReturnValue(
      fakeChild({ exitCode: 3, stderrChunks: [Buffer.from("qpdf: file is encrypted")] }),
    );
    const result = await linearizePdf(Buffer.from("%PDF-encrypted"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("non_zero_exit");
      expect(result.detail).toMatch(/encrypted/);
    }
  });

  it("returns ok=false reason=non_zero_exit with signal detail when killed by OS (code=null)", async () => {
    mockSpawn.mockReturnValue(fakeChild({ exitCode: null, exitSignal: "SIGKILL" }));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("non_zero_exit");
      expect(result.detail).toMatch(/SIGKILL/);
    }
  });

  it("returns ok=false reason=spawn_error when qpdf binary is missing", async () => {
    const err = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    mockSpawn.mockReturnValue(fakeChild({ spawnError: err }));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("spawn_error");
  });

  it("kills the subprocess and returns reason=timeout when qpdf never closes", async () => {
    // Use a fake timer to avoid wall-clock waits
    vi.useFakeTimers();
    const child = fakeChild({ holdStdinOpen: true });
    mockSpawn.mockReturnValue(child);
    const p = linearizePdf(Buffer.from("%PDF"));
    await vi.advanceTimersByTimeAsync(10_001);
    const result = await p;
    vi.useRealTimers();
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("timeout");
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
  });
});
```

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-linearize.test.ts` (per rule `cq-in-worktrees-run-vitest-via-node-node`). All 5 tests FAIL with "Cannot find module `../server/pdf-linearize`".

Task 1.2 — Write the helper at `apps/web-platform/server/pdf-linearize.ts`. `timer` is declared BEFORE `settle` closes over it (Kieran-flagged TDZ clarity), env allowlist is inline (no helper function), `stdout_closed` is removed from the reason union (never produced), there is no `opts` parameter (single hard-coded timeout):

```ts
// apps/web-platform/server/pdf-linearize.ts
import { spawn } from "node:child_process";

export type LinearizeResult =
  | { ok: true; buffer: Buffer }
  | { ok: false; reason: "spawn_error" | "non_zero_exit" | "timeout"; detail?: string };

const TIMEOUT_MS = 10_000;

export async function linearizePdf(input: Buffer): Promise<LinearizeResult> {
  return new Promise((resolve) => {
    let settled = false;
    let timer: NodeJS.Timeout | undefined;

    const settle = (r: LinearizeResult) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolve(r);
    };

    const child = spawn("qpdf", ["--linearize", "-", "-"], {
      env: {
        PATH: process.env.PATH,
        HOME: process.env.HOME,
        LANG: process.env.LANG,
        LC_ALL: process.env.LC_ALL,
        TMPDIR: process.env.TMPDIR,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    child.stdout.on("data", (c: Buffer) => stdoutChunks.push(c));
    child.stderr.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err) => settle({ ok: false, reason: "spawn_error", detail: err.message }));
    child.on("close", (code, signal) => {
      if (code === 0) {
        settle({ ok: true, buffer: Buffer.concat(stdoutChunks) });
        return;
      }
      const exitPart = code === null ? `signal=${signal}` : `exit=${code}`;
      const stderr = Buffer.concat(stderrChunks).toString("utf8").slice(0, 512);
      settle({ ok: false, reason: "non_zero_exit", detail: `${exitPart} stderr=${stderr}` });
    });

    timer = setTimeout(() => {
      child.kill("SIGKILL");
      settle({ ok: false, reason: "timeout", detail: `exceeded ${TIMEOUT_MS}ms` });
    }, TIMEOUT_MS);

    child.stdin.on("error", (err) =>
      settle({ ok: false, reason: "spawn_error", detail: `stdin: ${err.message}` }),
    );
    child.stdin.end(input);
  });
}
```

Rationale for no logger inside the helper: keeps the module pure and testable. The caller decides whether a given failure is worth logging, and only the caller has the request context (`userId`, `path`) that makes a log useful.

Run the tests — all 5 should PASS.

**Exit criteria:**

- 5/5 unit tests pass on `./node_modules/.bin/vitest run test/pdf-linearize.test.ts`.
- `tsc --noEmit` (or `npm run typecheck`) passes.
- `grep -n '\.\.\.process\.env' apps/web-platform/server/pdf-linearize.ts` returns empty — confirms no env spread.

### Phase 2 — Dockerfile runner stage (includes preflight)

**Goal:** Ship `qpdf` binary in the runner image and prove the stdin/stdout pipe form works.

Task 2.0 — **Preflight: verify `qpdf --linearize - -` works with a real PDF inside the runner base image.** This is load-bearing — the whole plan assumes qpdf supports stdin/stdout via `-`. Use a fixture PDF (any small non-linearized PDF; generate one with `qpdf --qdf --object-streams=disable`) and confirm the pipe form succeeds AND the output is a valid linearized PDF:

```bash
# Pull a small fixture PDF into the current directory first (e.g., a 1-page test PDF)
# Then run inside the base image:
docker run --rm -i node:22-slim bash -lc '
  apt-get update -qq
  apt-get install -y --no-install-recommends qpdf
  qpdf --version | head -1
  cat > /tmp/in.pdf
  qpdf --linearize - - < /tmp/in.pdf > /tmp/out.pdf
  qpdf --check /tmp/out.pdf | grep -i linearization
' < fixture.pdf
```

Expected output: `qpdf version 11.x.x` and `Linearization: yes`. Record qpdf version in the PR description.

**If stdin/stdout piping fails**, abort this plan and re-plan the helper around tempfile I/O (write input to `/tmp/in-<uuid>.pdf`, run `qpdf --linearize /tmp/in-<uuid>.pdf /tmp/out-<uuid>.pdf`, read output, `unlinkSync` both). The test mocks and `{ ok, reason }` contract stay; only the spawn args and piping change. Re-run plan review before proceeding.

Task 2.1 — Modify `apps/web-platform/Dockerfile` line 40 (append to the existing `apt-get install` list, per learning `2026-04-06-node-slim-missing-ca-certificates.md`):

```diff
 RUN apt-get update && apt-get install -y --no-install-recommends \
-    ca-certificates git bubblewrap socat \
+    ca-certificates git bubblewrap socat qpdf \
     && rm -rf /var/lib/apt/lists/*
```

Task 2.2 — Verify the built image:

```bash
cd apps/web-platform && docker build -t soleur-web-platform:linearize-check . && \
  docker run --rm soleur-web-platform:linearize-check qpdf --version
```

Expected: exits 0 and prints `qpdf version ...`.

**Exit criteria:**

- Task 2.0 exits 0 with `Linearization: yes` in the output.
- Docker build succeeds with `qpdf` added to the existing apt-get line.
- `qpdf --version` inside the built image exits 0.

### Phase 3 — Upload route integration + RED tests

**Goal:** Wire the helper into the upload route for `.pdf` files only, with graceful fallback.

**Pre-task — Verify the actual variable name and filename-check pattern used in the route today.** The plan pseudocode below references `filename`, `sanitizedName`, and `chunks` — before editing, open the route at `apps/web-platform/app/api/kb/upload/route.ts` lines 173–198 and confirm: (a) the variable holding `Buffer.concat(chunks)` today (currently passed inline to `.toString("base64")`), (b) the variable holding the uploaded file's name / the sanitized name used for the commit path, (c) the existing filename-case convention. Adapt the code below to match. Extension-based branching (`.endsWith(".pdf")`) is a **deliberate** choice — magic-byte sniffing adds complexity and qpdf will produce `non_zero_exit` on non-PDF bytes anyway, triggering the fallback path.

Task 3.1 — Extend `apps/web-platform/test/kb-upload.test.ts` with three new cases. Existing tests stay untouched. Mocks via `vi.hoisted` per learning `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`:

```ts
const { mockLinearize } = vi.hoisted(() => ({ mockLinearize: vi.fn() }));
vi.mock("../server/pdf-linearize", () => ({ linearizePdf: mockLinearize }));

describe("kb upload — PDF linearization", () => {
  beforeEach(() => mockLinearize.mockReset());

  it("commits linearized bytes when qpdf succeeds", async () => {
    const original = Buffer.from("%PDF-original");
    const linearized = Buffer.from("%PDF-linearized");
    mockLinearize.mockResolvedValue({ ok: true, buffer: linearized });

    const response = await postPdfUpload({ fileBuffer: original, filename: "doc.pdf" });
    expect(response.status).toBe(200);

    expect(githubPutSpy).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ content: linearized.toString("base64") }),
      "PUT",
    );
    expect(githubPutSpy).not.toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ content: original.toString("base64") }),
      "PUT",
    );
  });

  it("commits original bytes and logs warning when qpdf fails", async () => {
    const original = Buffer.from("%PDF-encrypted");
    mockLinearize.mockResolvedValue({ ok: false, reason: "non_zero_exit", detail: "encrypted" });

    const response = await postPdfUpload({ fileBuffer: original, filename: "doc.pdf" });
    expect(response.status).toBe(200);
    expect(githubPutSpy).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ content: original.toString("base64") }),
      "PUT",
    );
    expect(loggerWarnSpy).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "non_zero_exit", inputSize: original.length }),
      expect.stringMatching(/pdf linearization failed/i),
    );
  });

  it("does not invoke linearize for non-PDF files", async () => {
    await postPdfUpload({ fileBuffer: Buffer.from("# markdown"), filename: "note.md" });
    expect(mockLinearize).not.toHaveBeenCalled();
  });
});
```

(`postPdfUpload` and `githubPutSpy` follow existing helpers in the test file — extend them rather than rewriting.)

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-upload.test.ts`. New cases FAIL.

Task 3.2 — Modify `apps/web-platform/app/api/kb/upload/route.ts`. Two discrete changes:

**Change A — Add config export at the top of the file.** This is one of the HTTP-route-file allowed exports per rule `cq-nextjs-route-files-http-only-exports`:

```ts
export const maxDuration = 30;
```

**Change B — Replace the inline `Buffer.concat(chunks).toString("base64")` with an extraction + `.pdf` branch.** The route currently reads something like:

```ts
// Current (line ~183):
const base64Content = Buffer.concat(chunks).toString("base64");
```

Replace with (adapt variable names to match the route's actual pattern identified in the pre-task):

```ts
const buffer = Buffer.concat(chunks);
let payloadBuffer = buffer;

const lowerName = filename.toLowerCase(); // or sanitizedName — match the route's existing var
if (lowerName.endsWith(".pdf")) {
  const t0 = Date.now();
  const result = await linearizePdf(buffer);
  if (result.ok) {
    payloadBuffer = result.buffer;
  } else {
    logger.warn(
      {
        reason: result.reason,
        detail: result.detail,
        inputSize: buffer.length,
        durationMs: Date.now() - t0,
        userId,
        path,
      },
      "pdf linearization failed, committing original",
    );
  }
}

const base64Content = payloadBuffer.toString("base64");
```

Add the import near the existing server-module imports: `import { linearizePdf } from "../../../../server/pdf-linearize";` (relative path from `app/api/kb/upload/route.ts` to `server/`). Adjust depth if the tsconfig base path differs; prefer the path convention the surrounding imports already use.

Task 3.3 — Re-run the full upload test file; new cases PASS and existing cases still pass.

**Exit criteria:**

- All tests in `test/kb-upload.test.ts` pass.
- Route file still has only HTTP-method and allowed-config exports (`grep -E '^export' apps/web-platform/app/api/kb/upload/route.ts` shows only `POST` and `maxDuration` — no stray helpers).
- `grep -n '\.\.\.process\.env' apps/web-platform/app/api/kb/upload/route.ts` returns empty.

### Phase 4 — End-to-end verification

**Goal:** Confirm the whole pipeline works in a live-ish environment.

Task 4.1 — Build + run the web-platform container locally against Doppler dev secrets:

```bash
cd apps/web-platform && docker build -t soleur-linearize-e2e . && \
  docker run --rm -p 3000:3000 --env-file <(doppler secrets download -p soleur -c dev --no-file --format env) \
    soleur-linearize-e2e
```

Task 4.2 — Upload a known non-linearized PDF via the KB upload UI (or curl `POST /api/kb/upload`). Pull the committed file from GitHub and confirm it is linearized:

```bash
curl -L "https://api.github.com/repos/OWNER/REPO/contents/knowledge-base/<target>/doc.pdf" \
  -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github.raw" > /tmp/doc.pdf
qpdf --check /tmp/doc.pdf | grep -i linearization
```

Expected: `Linearization: yes`.

Task 4.3 — Upload a password-protected PDF (generate with `qpdf --encrypt user owner 256 -- input.pdf encrypted.pdf`). Confirm the upload succeeds, the original is committed (check GitHub), and a warning appears in the pino logs:

```json
{"level":"warn","reason":"non_zero_exit","detail":"exit=3 stderr=qpdf: ...encrypted...","inputSize":<bytes>,"durationMs":<ms>,"msg":"pdf linearization failed, committing original"}
```

**Exit criteria:**

- All 3 verification tasks produce the expected output, captured as screenshots or log snippets in the PR description.

## Test Strategy

**Unit tests:** `apps/web-platform/test/pdf-linearize.test.ts` — helper contract (success, non-zero exit, OS-killed, spawn error, timeout).

**Integration tests:** `apps/web-platform/test/kb-upload.test.ts` — route-level behavior (linearized-commit path, fallback + warn path, non-PDF skip).

**Runner invocation:** `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-linearize.test.ts test/kb-upload.test.ts` (per rule `cq-in-worktrees-run-vitest-via-node-node` — do NOT use `npx vitest` in a worktree).

**Mocking hygiene:** All `child_process.spawn` and `pdf-linearize` mocks declared via `vi.hoisted()` (per learning `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`). Fake timers via `vi.useFakeTimers()` for the timeout test to avoid wall-clock waits.

**No new test framework.** Vitest is already installed at `apps/web-platform/node_modules/.bin/vitest`.

**End-to-end:** Manual per Phase 4. No automated e2e harness for KB upload exists today; adding one is out of scope.

## Acceptance Criteria

Inherited from the spec; reproduced for PR-body convenience.

- [ ] **AC1.** `docker build` succeeds and the runner image answers `qpdf --version` with exit 0.
- [ ] **AC2.** Uploading a known non-linearized PDF results in a GitHub commit whose content returns `Linearization: yes` via `qpdf --check`.
- [ ] **AC3.** Uploading a password-protected PDF results in the original being committed, a warning logged with `reason: "non_zero_exit"` and detail containing `encrypted` (or qpdf's stderr equivalent), and the upload response reporting success.
- [ ] **AC4.** Uploading a 20MB non-linearized PDF completes end-to-end within 5s.
- [ ] **AC5.** Opening an uploaded-and-linearized PDF in the KB viewer renders page 1 within 2s on cold page load on broadband.
- [ ] **AC6.** Uploading a non-PDF (`.md`, `.png`, `.csv`) produces zero `qpdf` subprocess invocations and zero measurable latency regression vs `main`.
- [ ] **AC7.** Upload response payload shape and fields are identical to `main` for all inputs.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm); Product (carry-forward, inferred).

### Engineering

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** CTO recommended linearize-on-upload over the issue's in-memory LRU and flagged stampede, multi-replica RAM, cold-start penalty, encrypted-PDF fallback, image bloat, and subprocess failure modes. All addressed: on-upload placement eliminates stampede and RAM cost; env allowlist + 10s timeout + SIGKILL bounds blast radius; `{ ok, reason }` return contract eliminates throw-into-route. No new engineering concerns surfaced during planning beyond the Kieran-flagged qpdf-pipe-form verification (now Phase 2 Task 2.0) and TDZ ordering (now fixed in Task 1.2).

### Product

**Status:** reviewed (brainstorm carry-forward, inferred).
**Assessment:** Brainstorm answered the "qpdf failure → commit original vs reject" product question — linearization is a perf optimization, not a correctness gate. Existing KB viewer UX unchanged.

### Product/UX Gate

**Tier:** none.

### Brainstorm-recommended specialists

None — no conversion-optimizer, copywriter, retention-strategist, etc. recommended in brainstorm.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `qpdf` absent from `node:22-slim` apt, or `- -` stdin/stdout form unsupported | Plan design collapses | Phase 2 Task 2.0 pipes a real fixture PDF through the pipe form inside the base image. Failure → pivot to tempfile I/O (documented). |
| Subprocess runs longer than 10s on pathological inputs | Upload stalls | 10s timeout → SIGKILL → graceful fallback to original. Route `maxDuration = 30` absorbs remaining latency. |
| qpdf `--linearize` is lossless at the document level but byte-different | Users downloading direct from GitHub see linearized bytes, not exact original | Documented in spec NG and brainstorm. Pages, text, annotations, metadata unchanged. |
| Two concurrent 20MB uploads = two concurrent qpdf subprocesses | Peak memory ~2 × (upload size × replicas) under parallel load | No explicit semaphore. At current scale (low concurrent KB upload rate), accepted. If concurrency grows, add a `p-queue`-style concurrency gate in the upload route — tracked in follow-up if observed. |
| Secret leak to subprocess (CWE-526) | Medium | Inline env allowlist (`PATH`, `HOME`, `LANG`, `LC_ALL`, `TMPDIR`), no `process.env` spread. Enforced by grep exit criterion. |

## Rollout / Rollback

**Rollout:** Standard merge → CI → deploy. No feature flag — linearization is transparent and falls back to `main` behavior on any qpdf failure.

**Rollback:** Single-commit revert on main. Linearized PDFs already committed to user repos remain valid PDFs; readers don't depend on linearization. qpdf binary drops out of the image on revert.

**Monitoring:** After merge, spot-check pino logs for `msg: "pdf linearization failed, committing original"`. If the warning is loud (common, not rare), open a follow-up issue — no numeric threshold; use judgment based on absolute count and variety of `reason`/`detail` values.

## Alternative Approaches Considered

See brainstorm for full rationale. Headline alternatives rejected:

- **On-read in-memory LRU (the issue's original proposal)** — wrong cache tier for immutable content; stampede, RAM, cold-start costs.
- **On-read persist-to-R2 (CTO conditional recommendation)** — KB content is not stored in R2; it's in the user's git repo.
- **Client-side skeleton only (no qpdf)** — doesn't fix the underlying structural problem.
- **Async/queued linearization** — out of proportion at current scale.
- **Backfill legacy PDFs** — deferred (spec NG1).

## References

- Issue: <https://github.com/jikig-ai/soleur/issues/2456>
- Draft PR: <https://github.com/jikig-ai/soleur/pull/2457>
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-17-pdf-linearization-on-upload-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pdf-linearization/spec.md`
- Progressive rendering rule: AGENTS.md `cq-progressive-rendering-for-large-assets`
- Next.js route file exports rule: AGENTS.md `cq-nextjs-route-files-http-only-exports`
- Worktree vitest invocation rule: AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`
- CWE-526 env leak learning: `knowledge-base/project/learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`
- node:22-slim apt learning: `knowledge-base/project/learnings/2026-04-06-node-slim-missing-ca-certificates.md`
- vitest hoisting learning: `knowledge-base/project/learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`
- Route file non-HTTP exports learning: `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
