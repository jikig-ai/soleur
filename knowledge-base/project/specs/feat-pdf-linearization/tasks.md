---
title: "Tasks: PDF Linearization on Upload"
plan: knowledge-base/project/plans/2026-04-17-perf-pdf-linearization-on-upload-plan.md
spec: knowledge-base/project/specs/feat-pdf-linearization/spec.md
issue: 2456
pr: 2457
branch: pdf-linearization
date: 2026-04-17
status: planned
---

# Tasks: PDF Linearization on Upload

Run vitest from the app directory (per rule `cq-in-worktrees-run-vitest-via-node-node`):

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run <test-files>
```

Write failing tests before implementation code (per rule `cq-write-failing-tests-before`).

## Phase 1 — Helper Module (TDD)

- [ ] **1.1** Write failing tests at `apps/web-platform/test/pdf-linearize.test.ts` covering: (a) exit 0 + stdout returns `{ ok: true, buffer }`, (b) non-zero exit returns `{ ok: false, reason: "non_zero_exit", detail: <stderr> }`, (c) OS-killed (`code=null, signal=SIGKILL`) returns `non_zero_exit` with signal in detail, (d) spawn error (ENOENT) returns `{ ok: false, reason: "spawn_error" }`, (e) subprocess never closes → timeout fires, child is SIGKILLed, returns `reason: "timeout"`. Use `vi.hoisted()` for the `mockSpawn`, `PassThrough` streams in the `fakeChild`, `vi.useFakeTimers()` for the timeout test. Import with relative path `../server/pdf-linearize` (not `@/` alias).
- [ ] **1.2** Run tests — all 5 FAIL with "Cannot find module `../server/pdf-linearize`". Record RED snapshot.
- [ ] **1.3** Implement `apps/web-platform/server/pdf-linearize.ts` per plan Task 1.2 code block. Key invariants: `let timer` declared before `settle` closure, inline env allowlist (no helper function), no `opts` parameter (module-level `TIMEOUT_MS = 10_000`), `stdout_closed` NOT in the reason union, no logger import (keeps module pure).
- [ ] **1.4** Run tests — all 5 PASS. Record GREEN snapshot.
- [ ] **1.5** Run typecheck: `cd apps/web-platform && npm run typecheck` (or `npx tsc --noEmit` if no typecheck script). Must pass.
- [ ] **1.6** Verify no env spread: `grep -n '\.\.\.process\.env' apps/web-platform/server/pdf-linearize.ts` returns empty.

## Phase 2 — Dockerfile runner stage (with preflight)

- [ ] **2.0** Preflight: verify `qpdf --linearize - -` works with piped stdin/stdout inside `node:22-slim`. Use a small fixture PDF. Expected output: `qpdf version 11.x.x` AND `Linearization: yes` from `qpdf --check` on the output. Record qpdf version.
  - [ ] **2.0.1** If piping fails, abort — re-plan helper around tempfile I/O (write input, run `qpdf --linearize in.pdf out.pdf`, read output, `unlinkSync`). Re-run plan review before continuing.
- [ ] **2.1** Append `qpdf` to the existing `apt-get install` line in `apps/web-platform/Dockerfile` (line 40). Do NOT add a new `RUN` layer.
- [ ] **2.2** Build image: `cd apps/web-platform && docker build -t soleur-web-platform:linearize-check .` — must succeed.
- [ ] **2.3** Verify binary in built image: `docker run --rm soleur-web-platform:linearize-check qpdf --version` — must exit 0.

## Phase 3 — Upload route integration (TDD)

- [ ] **3.0** Pre-task: read `apps/web-platform/app/api/kb/upload/route.ts` lines 173–198. Identify (a) the variable holding `Buffer.concat(chunks)` (may be inline today), (b) the variable holding the uploaded filename / sanitized name, (c) the existing casing convention. Adapt Task 3.2 code to match.
- [ ] **3.1** Extend `apps/web-platform/test/kb-upload.test.ts` with three new cases: (a) PDF + linearize success → GitHub PUT carries `linearized.toString("base64")`, (b) PDF + linearize failure → GitHub PUT carries original base64 AND `logger.warn` called with `{ reason, detail, inputSize, durationMs, userId, path }`, (c) non-PDF file → `mockLinearize` NOT called. Mock `linearizePdf` via `vi.hoisted() + vi.mock("../server/pdf-linearize", ...)`. Use relative import, not `@/`.
- [ ] **3.2** Run tests — new cases FAIL, existing cases still pass.
- [ ] **3.3** Modify `apps/web-platform/app/api/kb/upload/route.ts`:
  - [ ] **3.3.1** Add `export const maxDuration = 30;` near the top, alongside the POST handler.
  - [ ] **3.3.2** Import `linearizePdf` via the route's existing relative-import convention.
  - [ ] **3.3.3** Replace the inline `Buffer.concat(chunks).toString("base64")` with: extract `const buffer = Buffer.concat(chunks)`, conditionally run `linearizePdf(buffer)` when `filename.toLowerCase().endsWith(".pdf")`, log warn on failure with `{ reason, detail, inputSize: buffer.length, durationMs, userId, path }`, `const base64Content = payloadBuffer.toString("base64")`.
- [ ] **3.4** Run tests — all cases PASS, including pre-existing ones.
- [ ] **3.5** Exit-criterion grep: `grep -E '^export' apps/web-platform/app/api/kb/upload/route.ts` shows only `POST` and `maxDuration` — no leaked helpers.
- [ ] **3.6** Exit-criterion grep: `grep -n '\.\.\.process\.env' apps/web-platform/app/api/kb/upload/route.ts` returns empty.
- [ ] **3.7** Typecheck: `npm run typecheck` passes.

## Phase 4 — End-to-end verification

- [ ] **4.1** Build + run locally: `cd apps/web-platform && docker build -t soleur-linearize-e2e . && docker run --rm -p 3000:3000 --env-file <(doppler secrets download -p soleur -c dev --no-file --format env) soleur-linearize-e2e`.
- [ ] **4.2** Upload a known non-linearized PDF via the KB upload UI or `curl POST /api/kb/upload`. Fetch the committed file from GitHub raw API and confirm `qpdf --check /tmp/doc.pdf | grep -i linearization` returns `Linearization: yes`. Capture as PR screenshot.
- [ ] **4.3** Upload a password-protected PDF (generate with `qpdf --encrypt user owner 256 -- input.pdf encrypted.pdf`). Confirm upload succeeds, original bytes committed, pino log contains `{"level":"warn","reason":"non_zero_exit","detail":"...encrypted...","inputSize":<N>,"durationMs":<N>,"msg":"pdf linearization failed, committing original"}`.
- [ ] **4.4** Confirm AC5 manually in KB viewer — open a newly-uploaded linearized PDF, observe page 1 renders within ~2s on broadband.

## Phase 5 — Ship

- [ ] **5.1** All acceptance criteria (AC1–AC7 from spec) verified.
- [ ] **5.2** Full vitest run green: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
- [ ] **5.3** `/soleur:review` — clean review.
- [ ] **5.4** `/soleur:compound` — capture any new learnings.
- [ ] **5.5** `/soleur:ship` — mark PR ready, auto-merge, post-merge verify.

## Cross-cutting Reminders

- Route file MUST only export HTTP methods and allowed Next.js config exports. Any helper, singleton, or non-HTTP export belongs in `server/` — violation surfaces only at `next build` time (precedent: hotfix #2401). See rule `cq-nextjs-route-files-http-only-exports`.
- Mocks via `vi.hoisted()` only — factory closures run before `const` init. See learning `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md`.
- Env passed to `spawn` is an allowlist, NEVER `{ ...process.env }`. See learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`.
- `qpdf` added to the EXISTING apt-get line, not a new `RUN` layer. See learning `2026-04-06-node-slim-missing-ca-certificates.md`.
