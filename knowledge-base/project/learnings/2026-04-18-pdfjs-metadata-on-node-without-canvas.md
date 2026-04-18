# Learning: metadata-only pdfjs reads on Node without canvas

## Problem

Needed per-PDF metadata (numPages + page-1 viewport) inside an in-process MCP
agent tool (`kb_share_preview`) running under Node 22 in a Next.js server
context, with zero additional native dependencies. pdfjs-dist's main entry
assumes browser `Worker` and will throw `ReferenceError: DOMMatrix is not
defined` on Node; naive `getDocument({ data: ... })` calls with
`disableWorker: true` fail the TypeScript types (that option is not on
`DocumentInitParameters` in pdfjs-dist 5.x).

## Solution

- Import from `pdfjs-dist/legacy/build/pdf.mjs` — this entry point ships a
  fake worker for Node and is the canonical SSR-safe surface.
- Pass `{ data: buffer, isEvalSupported: false }`. `data` accepts any
  `Uint8Array`; Node `Buffer` IS a `Uint8Array` subclass, so wrapping via
  `new Uint8Array(buffer)` is a redundant 50 MB copy — pass the `Buffer`
  directly.
- Do NOT set `disableWorker` — that field was removed from the public type
  surface in pdfjs-dist 5.x; the legacy entry handles worker fallback
  automatically.
- Metadata-only reads (`doc.numPages`, `doc.getPage(1).getViewport({ scale: 1 })`)
  work without `canvas` / `node-canvas`. These are parser-level, not raster.

```ts
const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
const doc = await pdfjs.getDocument({
  data: buffer,              // Buffer directly; no Uint8Array wrap
  isEvalSupported: false,    // SSR-safe posture
}).promise;
try {
  const page = await doc.getPage(1);
  const viewport = page.getViewport({ scale: 1 });
  return { numPages: doc.numPages, width: viewport.width, height: viewport.height };
} finally {
  await doc.destroy().catch(() => {});
}
```

### Engine requirement

pdfjs-dist 5.4.296's `package.json` declares
`"engines": { "node": ">=20.16.0 || >=22.3.0" }`. Node 21 lacks
`process.getBuiltinModule`, which the DOMMatrix/ImageData polyfill fallback
relies on — preflight on 21 crashes at import time. Our Docker runtime is
node:22-slim, so production is fine; local dev via Node 21 must skip the
preflight or switch to Node 22.

## Key Insight

When feeding a parser that allocates a full object graph (pdfjs, sharp,
libxml), cap the input separately from the storage limit. A 50 MB PDF can
peak at 200-300 MB RSS during parse; a 15 MB preview cap keeps a single
agent call bounded without reducing coverage (any PDF a user actually
shares fits under the cap for metadata purposes). Fail closed with
`firstPagePreview: undefined` — the outer tool still ships core metadata.

## Prevention

- **Engine mismatch:** when adding an npm dep, run
  `node -e "console.log(require('<pkg>/package.json').engines)"` and compare
  against the Docker runtime. Mismatches between `node:22-slim` and local
  Node 21 produce import-time crashes that unit tests with mocked deps will
  not catch.
- **Parser DoS:** every new parser (pdfjs, sharp, libxml, jsdom) gets an
  input-size cap that is smaller than the source storage limit. The storage
  cap protects disk; the parser cap protects RSS.
- **Uint8Array wrapping:** `new Uint8Array(buffer)` on a Node `Buffer` is a
  full copy, not a view (Buffer IS a Uint8Array subclass). For parser input
  via `data:`, pass the Buffer directly.

## Session Errors

- **pdfjs `disableWorker: true` rejected by TS types.** — Recovery: removed the
  option; legacy entry handles worker fallback automatically. — Prevention:
  before passing options to a lazy-imported dep, read the installed dep's
  `*.d.ts` for the expected shape rather than relying on online docs / training
  data.
- **Union-type test access `result.firstPagePreview?.numPages`.** — Recovery:
  narrowed via `if (result.firstPagePreview?.kind === "pdf")`. — Prevention:
  when a tagged union's variants have different fields, narrow before
  accessing.
- **openBinaryStream spy wrapper always called real impl.** — Recovery: made
  the spy itself the mock via `vi.fn()` with `mockImplementation(actual.fn)`
  in beforeEach. — Prevention: when a test spy needs to both record AND allow
  override, use the spy as the mock, seeding the default from
  `vi.importActual` in setup — do not call-through inside the factory wrapper.
- **Node 21 crashes on pdfjs import (`process.getBuiltinModule` missing).** —
  Recovery: re-ran preflight on Node 22 (matches Docker). — Prevention: check
  `node_modules/<pkg>/package.json` `engines` before first import.
- **Bash tool CWD not persistent across calls.** — Recovery: used absolute
  paths or a single `cd abs && cmd` compound call. — Prevention: already
  covered by `cq-for-local-verification-of-apps-doppler` in AGENTS.md.
- **Rebase conflict: `MAX_BINARY_SIZE` moved to `kb-limits` during feature
  development.** — Recovery: updated import in the rebase-conflict
  resolution. — Prevention: rebase earlier and more often when main is
  actively refactored; the git-history-analyzer agent correctly flagged this.
- **Mock default `new Error("share not found")` didn't match production
  PostgREST shape.** — Recovery: test uses `shareError: { code: "PGRST116" }`
  to match what supabase-js emits for a zero-row `.single()`. — Prevention:
  before asserting against a mock error shape, check what the real library
  returns for the same scenario.
- **Existing kb-share-tools.test.ts registration test asserted 3 tools.** —
  Recovery: updated to `toEqual([...4 names])` when adding the fourth tool. —
  Prevention: grep for array-length assertions against tool name lists before
  inserting a new tool; add to the existing test rather than forking.

## Tags

- category: integration-issues
- module: kb-share
- tech: pdfjs-dist, sharp, Node 22
