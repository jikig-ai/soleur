# refactor: extract prepareUploadPayload from kb upload route

**Issue:** #2474
**Branch:** `feat-one-shot-2474-prepare-upload-payload`
**Semver:** patch
**Type:** refactor (code quality / maintainability)
**Owner domain:** engineering

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Helper Contract, Route Integration, Test Scenarios, Acceptance Criteria, Risks, Implementation Phases
**Research inputs applied:**

- Learning `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md` — this is a *second* KB-route extraction refactor in the same month. The prior one (PR #2235) broke negative-space tests because substring scans in tests referenced strings that moved into the helper. The same failure mode applies here.
- Existing route-level test file `apps/web-platform/test/kb-upload.test.ts` has **4 PDF-specific assertions** that observe the inline call shape. These WILL fail after a naive extraction unless either (a) the helper preserves exact call shape, or (b) the assertions migrate.
- `warnSilentFallback` contract confirmed via `apps/web-platform/test/observability.test.ts` — with non-Error input it emits `Sentry.captureMessage("<feature> silent fallback", ...)`, NOT the original `"pdf linearization failed"` string.

### Key Improvements vs. initial plan

1. **Existing `test/kb-upload.test.ts` needs migration, not just a new helper test.** The 4 PDF tests (lines 525–628) observe call shape that will break — plan now explicitly enumerates each affected assertion and the migration path.
2. **Sentry message-string decision.** `warnSilentFallback(null, ...)` emits `"kb-upload silent fallback"` — this is a different string than the current `"pdf linearization failed"`. Choice documented below: **keep the current string** via the `message:` option so existing Sentry dashboards/searches keep working. The helper's API supports this cleanly.
3. **Proof-of-delegation test added.** Per the 2026-04-15 learning, extracting enforcement/behavior logic into a helper requires tests that prove the route *invokes* the helper AND *uses its result*, not just that the import appears. A regex assertion on the route source is cheap and catches dead imports.
4. **Scope-of-route-test change clarified.** After extraction, the route-level PDF tests SHOULD shrink to "route calls the helper" smoke tests; deep behavior tests live in `kb-upload-payload.test.ts`. Plan explicitly says which tests move, which stay, and which get replaced.

## Overview

Extract the stream-read + conditional PDF linearize + structured warn-log block from
`apps/web-platform/app/api/kb/upload/route.ts` (POST handler, currently lines ~176–212)
into a new helper `prepareUploadPayload(file, sanitizedName, userId, filePath): Promise<Buffer>`.

Scope is deliberately narrow: this PR restructures one named step of the pipeline to
improve readability and testability. It does NOT touch dup-check, GitHub PUT, token-mint,
credential helper, `git pull --ff-only`, or workspace-sync — those are pre-existing
accretion that the issue scope-out rationale explicitly flags as related-but-out-of-scope
(#2244 `syncWorkspace` migration is the right vehicle for them).

The extraction has two secondary wins worth folding in:

1. **Silent-fallback helper alignment** — the existing inline `Sentry.captureMessage(...)`
   with `level: "warning"` duplicates the exact contract of `warnSilentFallback` in
   `apps/web-platform/server/observability.ts`. Replacing the hand-rolled call with the
   helper matches AGENTS.md rule `cq-silent-fallback-must-mirror-to-sentry` and the
   helper is already in use at 15+ other sites (PR #2480/#2484 rollout).
2. **Named-step composition** — the POST handler becomes easier to scan because one
   vertical block collapses to a single function call, making the remaining named steps
   (dup-check, upload, sync, cleanup) visually coherent.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Place helper adjacent to the route or in `apps/web-platform/server/kb-upload/` if one already exists" | `server/kb-upload/` does NOT exist. No sibling modules to `route.ts`. `server/` is flat (46 files). | Place helper at `apps/web-platform/server/kb-upload-payload.ts` (flat, matches existing conventions like `kb-binary-response.ts`, `kb-content-hash.ts`, `kb-reader.ts`, `kb-validation.ts`). Do NOT create a new `kb-upload/` directory — overkill for one helper, and the existing flat convention is established. |
| "Structured warn-log" in the extracted block | Current code uses `logger.warn` + `Sentry.captureMessage(..., level: "warning")` inline. `warnSilentFallback` in `server/observability.ts` is the canonical helper for this pattern (mentioned explicitly in `cq-silent-fallback-must-mirror-to-sentry`). | Helper uses `warnSilentFallback` with `feature: "kb-upload"`, `op: "linearize"`. Drop the hand-rolled `Sentry.captureMessage`. |
| "Non-HTTP exports from route files are a Next.js build error" (AGENTS.md rule `cq-nextjs-route-files-http-only-exports`) | Confirmed — route currently exports only `POST` + `maxDuration`. Both are allowed. | Helper lives in `server/kb-upload-payload.ts`, imported into route. No non-HTTP exports added to `route.ts`. |
| Test framework for the helper | `apps/web-platform/test/` uses `vitest` with a flat naming convention (`kb-binary-response-etag.test.ts`, `pdf-linearize.test.ts`). No `__tests__` directory in src. | New test lives at `apps/web-platform/test/kb-upload-payload.test.ts` matching convention. Follow the mocking pattern from `test/pdf-linearize.test.ts` (vi.hoisted + vi.mock for `linearizePdf` and `@/server/observability`). |

## Open Code-Review Overlap

One open scope-out touches `apps/web-platform/app/api/kb/upload/route.ts`:

- **#2244: refactor(kb): migrate upload route to syncWorkspace (finish PR #2235 scope)** — **Defer.**
  The issue targets the workspace-sync block (credential helper + `git pull --ff-only`),
  which is explicitly out of scope for #2474. No file-level conflict: #2244 rewrites
  lines 231–264 of the route; #2474 rewrites lines 176–212 of the route. The two
  refactors are sequential and non-overlapping. Rationale: #2244 is a larger migration
  that pulls in a new abstraction (`syncWorkspace`), folding it in would balloon this
  PR past its stated scope and contradict the issue's own scope-out rationale.
  Disposition: leave #2244 open, no re-evaluation note needed (it already tracks its own
  scope). This PR's diff stays narrow by design.

A secondary match (`kb-upload` substring, #2246) is in the `description` field only and
refers to banner components, not this route. No action.

## Files to Edit

- `apps/web-platform/app/api/kb/upload/route.ts`
  - Remove lines 176–212 (stream-read + conditional linearize + inline Sentry mirror).
  - Replace with a single `await prepareUploadPayload(file, sanitizedName, user.id, filePath)` call.
  - Remove now-unused import: `linearizePdf` from `@/server/pdf-linearize`.
  - Keep `Sentry` import (outer catch still uses `Sentry.captureException`).
  - Keep the surrounding `try` / `catch` block untouched — payload prep errors (if any
    uncaught escape the helper) still flow through the route's existing error handler.

- `apps/web-platform/test/kb-upload.test.ts` **(CRITICAL — existing route-level tests
  will break without updates; see "Route-Level Test Migration" below)**
  - Update the 4 PDF test blocks (lines 525–628) to match the post-refactor
    observability surface (`warnSilentFallback` path).
  - Keep the `vi.mock("@/server/pdf-linearize", ...)` — still needed because the
    helper imports it.
  - Add proof-of-delegation test — see Test Scenario 5.

## Files to Create

- `apps/web-platform/server/kb-upload-payload.ts` — the helper module.
- `apps/web-platform/test/kb-upload-payload.test.ts` — unit tests for the helper (4 scenarios).

## Helper Contract

```ts
// apps/web-platform/server/kb-upload-payload.ts
import { linearizePdf } from "@/server/pdf-linearize";
import { warnSilentFallback } from "@/server/observability";
import logger from "@/server/logger";

/**
 * Read a File stream into a Buffer, applying PDF linearization when the
 * extension is `.pdf`. On linearize failure (excluding the intentional
 * `skip_signed` pass-through), falls back to the original buffer and mirrors
 * the warning to pino + Sentry via warnSilentFallback.
 *
 * Errors that escape (e.g., an upstream stream.read() rejection) propagate to
 * the caller's try/catch — the helper does NOT swallow stream errors.
 *
 * @param file        FormData File from the upload route.
 * @param sanitizedName Already-sanitized filename (extension extraction uses this).
 * @param userId      Authenticated user id — included in the silent-fallback extra.
 * @param filePath    Target repo path — included in the silent-fallback extra.
 * @returns Buffer ready to base64-encode for the GitHub contents API.
 */
export async function prepareUploadPayload(
  file: File,
  sanitizedName: string,
  userId: string,
  filePath: string,
): Promise<Buffer> {
  // 1. Stream-to-buffer (chunked to avoid holding File blob + ArrayBuffer simultaneously).
  const chunks: Uint8Array[] = [];
  const reader = file.stream().getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const buffer: Buffer = Buffer.concat(chunks);

  // 2. Non-PDF passthrough.
  const ext = sanitizedName.split(".").pop()?.toLowerCase();
  if (ext !== "pdf") return buffer;

  // 3. Conditional linearize with silent-fallback mirror.
  const t0 = Date.now();
  const result = await linearizePdf(buffer);
  if (result.ok) return result.buffer;

  if (result.reason === "skip_signed") {
    // Intentional pass-through — signed PDFs would be invalidated by
    // linearization. Silent in both sinks, matches prior behavior.
    return buffer;
  }

  warnSilentFallback(null, {
    feature: "kb-upload",
    op: "linearize",
    // IMPORTANT: Preserve the exact Sentry message string the pre-refactor code
    // emitted. Existing Sentry dashboards, alerts, and saved searches reference
    // `"pdf linearization failed"`. If we default to `warnSilentFallback`'s
    // auto-generated `"kb-upload silent fallback"`, we silently break
    // observability continuity. `warnSilentFallback` supports this via the
    // `message:` option.
    message: "pdf linearization failed",
    extra: {
      reason: result.reason,
      detail: result.detail,
      inputSize: buffer.length,
      durationMs: Date.now() - t0,
      userId,
      path: filePath,
    },
  });
  return buffer;
}
```

**Message-string continuity:** The choice to keep `"pdf linearization failed"` (exact
match to the pre-refactor string) is deliberate. Any Sentry query filtering by
`message:"pdf linearization failed"` — whether a saved search, dashboard tile, or alert
rule — continues to work after the refactor. The pre-refactor code also tagged
`reason: result.reason` on the Sentry event; `warnSilentFallback` does NOT auto-tag
the reason, so it flows through `extra` instead. That is acceptable: Sentry searches
over `extra.reason` work the same way as tag searches, and the alert surface stays
identical.

**Design notes:**

- The helper takes `sanitizedName` (not the raw file.name) because the route has already
  sanitized and extension-validated; recomputing `ext` inside the helper keeps it
  self-contained without forcing the caller to pass an extra param.
- `warnSilentFallback(null, ...)` is the correct call — the linearize failure is a
  degraded-condition, not an `Error` value (linearizePdf returns a discriminated union,
  not a thrown error). The helper's `null` branch matches the `kb-share` example in
  `server/observability.ts`.
- `logger.warn` is emitted inside `warnSilentFallback` — the prior standalone
  `logger.warn` call is redundant and gets removed.

## Route Integration

```ts
// apps/web-platform/app/api/kb/upload/route.ts (after extraction, abbreviated)
import { prepareUploadPayload } from "@/server/kb-upload-payload";
// ... other imports unchanged; drop: import { linearizePdf } from "@/server/pdf-linearize";

// inside POST, replacing lines 176–212:
const payloadBuffer = await prepareUploadPayload(
  file,
  sanitizedName,
  user.id,
  filePath,
);

const base64Content = payloadBuffer.toString("base64");
// ... rest of the route unchanged
```

## Route-Level Test Migration

This section is load-bearing. The existing `apps/web-platform/test/kb-upload.test.ts`
has four PDF-specific assertions that directly inspect the pre-refactor observability
shape. All four will either break or become stale after the extraction. Per the
2026-04-15 negative-space learning, the correct approach is NOT to delete them but to
migrate them to match the post-refactor reality.

### Affected assertions and migration plan

| Existing test (line range) | What it currently asserts | Post-refactor status |
| --- | --- | --- |
| **"PDF upload: commits linearized bytes when qpdf succeeds"** (525–550) | `mockLinearize` called once; GitHub PUT called with linearized base64. | **KEEP AS-IS.** The helper calls `linearizePdf`, so `mockLinearize` still fires. GitHub PUT shape is unchanged (route still composes the payload into the PUT body). |
| **"PDF upload: commits original bytes and logs warning when qpdf fails"** (552–605) | Three layered assertions: (a) GitHub PUT with original bytes, (b) `logger.warn` with specific `{reason, detail, inputSize, durationMs, userId, path}` top-level payload, (c) `Sentry.captureMessage("pdf linearization failed", {level:"warning", tags:{feature, reason}, extra:{...}})`. | **REWRITE.** After extraction: (a) stays (byte-level behavior is identical), (b) the `logger.warn` payload shape changes — `warnSilentFallback` emits `{err, feature, op, reason, detail, inputSize, durationMs, userId, path}` (adds `err`, `feature`, `op`; keeps the rest via `...extra` spread). Tests must loosen to `expect.objectContaining({reason, detail, inputSize, durationMs, userId, path})` — the fields are preserved; the envelope gained extra keys. (c) The `Sentry.captureMessage` call shape changes: `warnSilentFallback(null, {feature, op, message, extra})` calls `captureMessage(message, {level:"warning", tags:{feature, op}, extra:{err:null, ...extra}})`. Tests must update `tags` from `{feature, reason}` to `{feature, op}` and accept `reason` via `extra` rather than `tags`. |
| **"PDF upload: skip_signed is silent in BOTH pino and Sentry"** (607–619) | `logger.warn` and `Sentry.captureMessage` both NOT called. | **KEEP AS-IS.** Post-refactor helper still short-circuits on `skip_signed` without invoking `warnSilentFallback`. Both sinks stay silent. Assertion shape unchanged. |
| **"non-PDF upload: does not invoke linearize"** (621–628) | `mockLinearize` not called. | **KEEP AS-IS.** Helper's non-PDF branch returns before calling `linearizePdf`. |

### Alternative considered: move the deep observability tests to the helper test

A reviewer might argue that asserting `logger.warn`/`Sentry.captureMessage` shape at
the *route* level duplicates coverage from the new `kb-upload-payload.test.ts`. That is
true. However, deleting the route-level observability assertions weakens the negative-
space gate — a future edit that silently stops passing the observability path through
the helper would pass route tests. The compromise:

- **Keep** a single route-level assertion that the PDF-failure path results in a
  `warnSilentFallback` call (or equivalent observable side effect) with the expected
  `feature: "kb-upload"` tag. This is the proof-of-delegation.
- **Move** detailed payload-shape assertions (every key in the `extra` object, exact
  durationMs presence, etc.) to the helper test.

Concretely, the route test's rewritten PDF-failure block asserts:

```ts
// After refactor: proof of delegation + minimal behavior assertion
const Sentry = await import("@sentry/nextjs");
expect(Sentry.captureMessage).toHaveBeenCalledWith(
  "pdf linearization failed",
  expect.objectContaining({
    level: "warning",
    tags: expect.objectContaining({ feature: "kb-upload", op: "linearize" }),
  }),
);
// GitHub PUT still receives the original bytes:
expect(mockGithubApiPost).toHaveBeenCalledWith(
  TEST_INSTALLATION_ID,
  expect.stringContaining("enc.pdf"),
  expect.objectContaining({ content: originalBase64 }),
  "PUT",
);
```

The exhaustive `extra` object assertions move to the helper test (Scenario 3).

### Proof-of-delegation test (new)

Per the 2026-04-15 learning — "substring presence is not proof of delegation." Add a
small new test that proves the route actually invokes the helper and uses its result,
not just that the import line exists:

```ts
// apps/web-platform/test/kb-upload.test.ts — new test block
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("route delegates to prepareUploadPayload helper", () => {
  const routeSrc = readFileSync(
    resolve(__dirname, "../app/api/kb/upload/route.ts"),
    "utf-8",
  );

  it("imports the helper", () => {
    expect(routeSrc).toMatch(
      /import\s*\{\s*prepareUploadPayload\s*\}\s*from\s*["']@\/server\/kb-upload-payload["']/,
    );
  });

  it("invokes the helper and awaits its result", () => {
    // Require `await prepareUploadPayload(...)` — proves invocation, not just import.
    expect(routeSrc).toMatch(/await\s+prepareUploadPayload\s*\(/);
  });

  it("does not keep the inline linearize block after extraction", () => {
    // Regression gate — if someone adds a second inline linearize path back, fail loud.
    expect(routeSrc).not.toMatch(/linearizePdf\s*\(/);
  });
});
```

The third assertion is the negative-space gate: if a future edit re-introduces an
inline `linearizePdf(` call in the route (either alongside or instead of the helper),
this test fails. That is the specific failure mode the 2026-04-15 learning warns about.

## Acceptance Criteria

- [x] Helper `prepareUploadPayload` exists at `apps/web-platform/server/kb-upload-payload.ts`
      with the exact signature `(file: File, sanitizedName: string, userId: string, filePath: string) => Promise<Buffer>`.
- [x] Route file at `apps/web-platform/app/api/kb/upload/route.ts` imports and calls the helper.
- [x] Route file no longer imports `linearizePdf` directly.
- [x] Route file no longer contains the stream-read loop or the linearize/warn block inline.
- [x] Unit test file at `apps/web-platform/test/kb-upload-payload.test.ts` covers the 4 scenarios below.
- [x] Existing `apps/web-platform/test/kb-upload.test.ts` PDF-failure block updated per the Route-Level Test Migration table.
- [x] Proof-of-delegation test block added to `apps/web-platform/test/kb-upload.test.ts`:
      (a) helper import regex, (b) `await prepareUploadPayload(` invocation regex, (c) no `linearizePdf(` in route source.
- [x] Sentry message string preserved as `"pdf linearization failed"` (continuity for saved searches/alerts).
- [x] `warnSilentFallback` is called with `feature: "kb-upload"`, `op: "linearize"` (proof-of-delegation for observability path).
- [x] All test scenarios pass under `vitest` — both the new helper test file and the updated route test file.
- [x] Full web-platform vitest suite passes (no regressions from the extraction).
- [x] `next build` succeeds locally (route-file export validator — AGENTS.md `cq-nextjs-route-files-http-only-exports`).
- [x] PR body contains `Closes #2474`.
- [x] Semver label: `semver:patch`.
- [x] Route handler POST behavior is byte-identical to pre-refactor for all four input cases
      (non-PDF, PDF success, PDF linearize failure, PDF `skip_signed`).

## Test Scenarios

Located at `apps/web-platform/test/kb-upload-payload.test.ts`. Use the `vi.hoisted` + `vi.mock`
pattern already established in `test/pdf-linearize.test.ts`.

### Scenario 1 — Non-PDF passthrough

**Given** a `File` whose sanitized name ends in `.md` and whose stream yields bytes
`<Buffer 01 02 03>`,
**When** `prepareUploadPayload(file, "notes.md", "user-1", "knowledge-base/notes/notes.md")`
is called,
**Then** the returned buffer equals `Buffer.from([0x01, 0x02, 0x03])` AND `linearizePdf`
is NOT called AND `warnSilentFallback` is NOT called.

### Scenario 2 — PDF linearize success

**Given** a `File` whose sanitized name ends in `.pdf`, whose stream yields the raw PDF
bytes, AND `linearizePdf` is mocked to return `{ ok: true, buffer: <linearized> }`,
**When** `prepareUploadPayload(file, "doc.pdf", "user-1", "knowledge-base/docs/doc.pdf")`
is called,
**Then** the returned buffer equals the mocked linearized buffer (NOT the raw buffer)
AND `warnSilentFallback` is NOT called.

### Scenario 3 — PDF linearize failure mirrors to Sentry via warnSilentFallback

**Given** a `File` whose sanitized name ends in `.pdf`, whose stream yields raw bytes
`<Buffer 11 22 33>`, AND `linearizePdf` is mocked to return
`{ ok: false, reason: "non_zero_exit", detail: "exit=2 stderr=..." }`,
**When** `prepareUploadPayload(file, "broken.pdf", "user-2", "knowledge-base/broken.pdf")`
is called,
**Then**:

1. The returned buffer equals the raw input buffer (`Buffer.from([0x11, 0x22, 0x33])`) —
   fallback to the original.
2. `warnSilentFallback` is called exactly once with:
   - First arg: `null` (non-Error degraded condition).
   - Options: `feature: "kb-upload"`, `op: "linearize"`, `message: "pdf linearization failed, committing original"`.
   - `extra` includes `reason: "non_zero_exit"`, `detail: "exit=2 stderr=..."`, `inputSize: 3`,
     `userId: "user-2"`, `path: "knowledge-base/broken.pdf"`, and a numeric `durationMs`.

### Scenario 4 (bonus) — signed-PDF skip is silent

**Given** `linearizePdf` returns `{ ok: false, reason: "skip_signed" }`,
**When** the helper runs on a `.pdf` input of bytes `<Buffer 99>`,
**Then** the returned buffer equals the raw `<Buffer 99>` AND `warnSilentFallback` is NOT called.

This scenario is included because `skip_signed` is explicitly called out as an
intentional pass-through in the current route — the refactor must preserve that
behavior and it's cheap to lock in.

## Test Implementation Sketch

```ts
// apps/web-platform/test/kb-upload-payload.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockLinearize, mockWarn } = vi.hoisted(() => ({
  mockLinearize: vi.fn(),
  mockWarn: vi.fn(),
}));

vi.mock("@/server/pdf-linearize", () => ({ linearizePdf: mockLinearize }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: mockWarn }));

import { prepareUploadPayload } from "../server/kb-upload-payload";

function fakeFile(bytes: Uint8Array): File {
  return {
    stream() {
      let sent = false;
      return {
        getReader() {
          return {
            async read() {
              if (sent) return { done: true, value: undefined };
              sent = true;
              return { done: false, value: bytes };
            },
          };
        },
      } as unknown as ReadableStream<Uint8Array>;
    },
  } as unknown as File;
}

beforeEach(() => {
  mockLinearize.mockReset();
  mockWarn.mockReset();
});

describe("prepareUploadPayload", () => {
  it("non-PDF passthrough returns raw buffer", async () => {
    const f = fakeFile(new Uint8Array([1, 2, 3]));
    const out = await prepareUploadPayload(f, "notes.md", "u1", "path/notes.md");
    expect(out).toEqual(Buffer.from([1, 2, 3]));
    expect(mockLinearize).not.toHaveBeenCalled();
    expect(mockWarn).not.toHaveBeenCalled();
  });

  it("PDF linearize success returns linearized buffer", async () => {
    mockLinearize.mockResolvedValue({ ok: true, buffer: Buffer.from("linearized") });
    const f = fakeFile(new Uint8Array([0x25, 0x50]));
    const out = await prepareUploadPayload(f, "doc.pdf", "u1", "path/doc.pdf");
    expect(out).toEqual(Buffer.from("linearized"));
    expect(mockWarn).not.toHaveBeenCalled();
  });

  it("PDF linearize failure falls back and mirrors to Sentry", async () => {
    mockLinearize.mockResolvedValue({
      ok: false,
      reason: "non_zero_exit",
      detail: "exit=2 stderr=...",
    });
    const f = fakeFile(new Uint8Array([0x11, 0x22, 0x33]));
    const out = await prepareUploadPayload(f, "broken.pdf", "u2", "path/broken.pdf");
    expect(out).toEqual(Buffer.from([0x11, 0x22, 0x33]));
    expect(mockWarn).toHaveBeenCalledTimes(1);
    expect(mockWarn).toHaveBeenCalledWith(null, expect.objectContaining({
      feature: "kb-upload",
      op: "linearize",
      message: "pdf linearization failed, committing original",
      extra: expect.objectContaining({
        reason: "non_zero_exit",
        detail: "exit=2 stderr=...",
        inputSize: 3,
        userId: "u2",
        path: "path/broken.pdf",
      }),
    }));
  });

  it("signed-PDF skip returns raw buffer silently", async () => {
    mockLinearize.mockResolvedValue({ ok: false, reason: "skip_signed" });
    const f = fakeFile(new Uint8Array([0x99]));
    const out = await prepareUploadPayload(f, "signed.pdf", "u1", "path/signed.pdf");
    expect(out).toEqual(Buffer.from([0x99]));
    expect(mockWarn).not.toHaveBeenCalled();
  });
});
```

## Implementation Phases

### Phase 1 — RED (failing tests)

1. Create `apps/web-platform/test/kb-upload-payload.test.ts` with the four test scenarios
   listed in "Test Scenarios" above. Tests will fail because the helper doesn't exist yet.
2. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-upload-payload.test.ts`.
   Confirm all four fail with "module not found" or equivalent.
3. Also add the new proof-of-delegation block to `apps/web-platform/test/kb-upload.test.ts`
   (helper import regex + invocation regex + no-inline-linearizePdf negative regex). This
   block will fail initially — the route has not been updated yet. That is intentional and
   constitutes the RED signal for the route-level extraction.
4. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-upload.test.ts`.
   Confirm only the new proof-of-delegation assertions fail; the 4 pre-existing PDF
   assertions still pass (route unchanged at this point).

### Phase 2 — GREEN (helper + route + route-test migration)

1. Create `apps/web-platform/server/kb-upload-payload.ts` with the exported helper.
2. Re-run `test/kb-upload-payload.test.ts`. All four scenarios should pass.
3. Edit `apps/web-platform/app/api/kb/upload/route.ts`:
   - Add `import { prepareUploadPayload } from "@/server/kb-upload-payload";`.
   - Replace the stream-read + linearize block (lines 176–212) with a single
     `const payloadBuffer = await prepareUploadPayload(file, sanitizedName, user.id, filePath);`.
   - Remove the now-unused `import { linearizePdf } from "@/server/pdf-linearize";`.
4. Update `apps/web-platform/test/kb-upload.test.ts` per the Route-Level Test Migration
   table — keep the 3 "as-is" assertions; rewrite the PDF-failure block to match the
   `warnSilentFallback` output shape (tags `feature + op`, `reason` in `extra`, message
   string `"pdf linearization failed"` preserved).
5. Run full web-platform vitest suite:
   `cd apps/web-platform && ./node_modules/.bin/vitest run`.
   Expect no regressions. Specifically confirm:
   - `kb-upload-payload.test.ts`: 4/4 pass.
   - `kb-upload.test.ts`: all pre-existing tests pass (20 non-PDF + 4 PDF + 3 proof-of-delegation).
   - `observability.test.ts`: untouched, still green.
   - `pdf-linearize.test.ts`: untouched, still green.
6. Run `cd apps/web-platform && npx tsc --noEmit` to catch any type regressions.
7. Run `next build` to validate the App Router route-file export validator
   (AGENTS.md `cq-nextjs-route-files-http-only-exports`). The helper lives in `server/`,
   so there are no new non-HTTP exports on `route.ts`, but this catch-step is cheap and
   the rule has caused post-merge prod outages twice (PR #2347, learning
   `2026-04-15-nextjs-15-route-file-non-http-exports.md`).
   Command (single Bash call, per `cq-for-local-verification-of-apps-doppler`):
   `cd apps/web-platform && doppler run -p soleur -c dev -- npm run build`.

### Phase 3 — REFACTOR (optional polish)

- Review the resulting `POST` handler for further named-step clarity. Do NOT rename or
  restructure other steps in this PR (explicit scope-out).
- Confirm the route diff is small and readable: roughly -37 lines (old block), +1 line
  (new helper call), and -1 line (removed `linearizePdf` import). Net ~-37 LOC in the
  route.

### Phase 4 — Ship

1. `skill: soleur:review` on the PR branch.
2. `skill: soleur:compound` to capture any session learnings.
3. `skill: soleur:ship` — PR title `refactor(kb-upload): extract prepareUploadPayload helper`,
   body starts with `Closes #2474`, label `semver:patch`.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Behavior drift in the PDF path | low | high | Four helper-level scenarios lock byte-identical output for non-PDF, linearize-success, linearize-fail, signed-skip. Route-level PDF tests retained for end-to-end coverage. |
| Sentry message-string regression (dashboards/alerts) | medium | medium | Helper call explicitly sets `message: "pdf linearization failed"` to preserve the exact pre-refactor string. Acceptance criterion locks this. |
| Sentry tag regression (`reason` moved from `tags` to `extra`) | medium | low | Documented in Acceptance Criteria. Reviewer should grep Sentry dashboards/alerts for `tags.reason` filters touching `feature=kb-upload` before merge; at time of writing, none are known. If one exists, add it to migrate before cut-over. |
| Existing route-level PDF assertions break silently | high if ignored, zero if followed | medium | Route-Level Test Migration table enumerates each of the 4 affected assertions and their disposition. Phase 2 step 5 explicitly asserts the full route test file stays green. |
| Route-file export validator breakage | very low | high | Helper lives in `server/`, route only gains one named import. Phase 2 step 7 runs `next build` locally before push. AGENTS.md learning `2026-04-15-nextjs-15-route-file-non-http-exports.md` documents the consequences of skipping. |
| Logger output shape changes | low | low | `warnSilentFallback` emits `logger.warn({ err, feature, op, ...extra }, msg)` — the `extra` keys match the prior call site's `logCtx`. Downstream log parsers see the same fields plus three new top-level keys (`err: null`, `feature`, `op`). Acceptable. |
| Dead-import regression (someone re-adds inline linearize later) | low | medium | Proof-of-delegation negative-space test asserts `linearizePdf(` does NOT appear in `route.ts` source. Future edit that re-introduces inline call fails the test suite loudly. Mitigates the exact failure mode described in `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`. |

## Out of Scope (explicit non-goals)

- `syncWorkspace` migration → tracked by #2244.
- Duplicate-check extraction (dup-check block lines 152–174).
- GitHub PUT extraction (upload + commit block).
- Credential-helper + `git pull --ff-only` extraction.
- Any change to `server/pdf-linearize.ts`.
- Any change to `server/observability.ts`.
- Refactoring the outer try/catch error-handling block.

## Domain Review

**Domains relevant:** none (infrastructure/tooling change — code-quality refactor with
zero user-facing surface, zero API contract change, zero product implication).

This is a pure internal refactor of a single POST handler's internal composition. No
new dependencies, no UI, no new routes, no database touches, no external services. The
AGENTS.md-recommended domain-sweep outcome for a refactor of this shape is "no domains
relevant"; product, marketing, content, legal, finance, operations, security, and
customer-support all have zero surface here. Engineering is the owning domain and the
task IS the engineering work.

## PR Metadata

- **Title:** `refactor(kb-upload): extract prepareUploadPayload helper`
- **Body preamble:** `Closes #2474`
- **Semver label:** `semver:patch`
- **Other labels:** `type/chore`, `domain/engineering`, `priority/p3-low` (inherited from #2474).
